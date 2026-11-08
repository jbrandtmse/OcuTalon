"""Text extraction from PDF and Word (.docx) files for OcuTalon (AD-6, AD-21).

extract() runs only in a worker of the WorkMgr category OcuTalon.Docs.Extractor, imported with
%SYS.Python.Import by OcuTalon.Docs.Extractor. It reads one file and returns a dict:

  success  {"ok": True, "text": str, "cut": bool, "markers": "page" | "heading" | "none"}
  failure  {"ok": False, "reason": code, "detail": str}

The reason codes are too_large and timed_out and failed (set by the caller side, never here) and
contents_too_large, wrong_type, encrypted, damaged, no_text, legacy_doc. detail is a technical note for the
operator and holds no user text. A failure that is none of those (a library bug) is raised, not returned.

The file kind comes from its signature. The module reads the one file it is given, writes nothing, makes
no network call and holds no user-facing text: the page marker comes in as an argument.

The text it returns is Markdown-shaped: the page marker lines of a PDF and the Heading 1 lines of a .docx
are the only lines that start with "## "; a line of the file's own text that starts with "## " is written "\\## ".
While a PDF is read, every Flate, LZW, RunLength and CCITT fax decoding of pdfminer.six counts its output against
max_unpacked before it keeps it (Flate asks zlib for at most the bytes that are left), and once the budget is passed every
later decoding of the read is refused too, so a decompression bomb is refused as contents_too_large instead of filling the
worker. ASCII85 and ASCIIHex output is at most four times the file's bytes and is not counted.
"""

import contextlib
import re
import zipfile
import zlib

PDF_SIGNATURE = b"%PDF-"
PDF_WINDOW = 1024
ZIP_SIGNATURE = b"PK\x03\x04"
OLE2_SIGNATURE = bytes.fromhex("D0CF11E0A1B11AE1")
ENCRYPTED_STREAM = "EncryptedPackage".encode("utf-16-le")
LEGACY_STREAM = "WordDocument".encode("utf-16-le")
DOCUMENT_PART = "word/document.xml"
HEADING = re.compile(r"^heading\s+(\d+)$", re.IGNORECASE)


def _escape(text):
    """The text without NUL and with each line that starts with "## " written "\\## ", so that only the markers this module writes open a section."""
    text = text.replace("\x00", "").replace("\r\n", "\n").replace("\r", "\n")
    return "\n".join("\\" + line if line.startswith("## ") else line for line in text.split("\n"))


class _TooLarge(Exception):
    """The inflated bytes of a read passed its budget. Not a zlib.error, so that no fallback of pdfminer swallows it."""


class _BoundedZlib:
    """A stand-in for the zlib module of pdfminer.pdftypes for one read, and the budget of its other decoders.

    It offers what that module uses (decompress, decompressobj, error, MAX_WBITS). Every call asks zlib for at most the
    bytes that are left of the budget plus one; the LZW, RunLength and CCITT fax decoders count their output before they
    keep it. A call past the budget raises _TooLarge, and so does every later call, also when a caller swallowed the first.
    """

    error = zlib.error
    MAX_WBITS = zlib.MAX_WBITS

    def __init__(self, budget):
        self.left = budget

    def room(self):
        """The most bytes the next call may produce: what is left plus the one byte that proves an excess."""
        if self.left < 0:
            raise _TooLarge()
        return self.left + 1

    def spend(self, count):
        self.left -= count
        if self.left < 0:
            raise _TooLarge()

    def decompress(self, data, wbits=zlib.MAX_WBITS, bufsize=16384):
        """Like zlib.decompress: the whole stream, or zlib.error for a bad or truncated one (then nothing is counted, as
        pdfminer reads the same data again through its fallback, which counts it)."""
        stream = zlib.decompressobj(wbits)
        out = stream.decompress(data, self.room())
        if not stream.eof and len(out) <= self.left:
            raise zlib.error("Error -5 while decompressing data: incomplete or truncated stream")
        self.spend(len(out))
        return out

    def decompressobj(self, wbits=zlib.MAX_WBITS, zdict=b""):
        return _BoundedObject(self, wbits, zdict)

    def lzwdecode(self, data):
        """Like pdfminer's lzwdecode, each decoded piece counted before it is kept."""
        from io import BytesIO
        from pdfminer.lzw import LZWDecoder

        pieces = []
        for piece in LZWDecoder(BytesIO(data)).run():
            self.spend(len(piece))
            pieces.append(piece)
        return b"".join(pieces)

    def rldecode(self, data):
        """Like pdfminer's rldecode, once the length it decodes to is counted."""
        from pdfminer.runlength import rldecode

        self.room()
        total = 0
        at = 0
        while at < len(data) and data[at] != 128:
            if data[at] < 128:
                total += data[at] + 1
                at += data[at] + 2
            else:
                total += 257 - data[at]
                at += 2
        self.spend(total)
        return rldecode(data)

    def ccittfaxdecode(self, data, params):
        """Like pdfminer's ccittfaxdecode, each decoded row counted before it is kept."""
        import pdfminer.ccitt as ccitt

        owner = self
        base = ccitt.CCITTFaxDecoder

        class _Rows(base):
            def output_line(self, y, bits):
                owner.spend((len(bits) + 7) // 8)
                base.output_line(self, y, bits)

        ccitt.CCITTFaxDecoder = _Rows
        try:
            return ccitt.ccittfaxdecode(data, params)
        finally:
            ccitt.CCITTFaxDecoder = base


class _BoundedObject:
    """A decompression object whose every decompress call is bounded by the owner's budget."""

    def __init__(self, owner, wbits, zdict):
        self._owner = owner
        self._inner = zlib.decompressobj(wbits, zdict) if zdict else zlib.decompressobj(wbits)

    def decompress(self, data, max_length=0):
        limit = self._owner.room()
        if max_length:
            limit = min(limit, max_length)
        out = self._inner.decompress(data, limit)
        self._owner.spend(len(out))
        return out

    def __getattr__(self, name):
        return getattr(self._inner, name)


BOUNDED_DECODERS = ("zlib", "lzwdecode", "rldecode", "ccittfaxdecode")


@contextlib.contextmanager
def _bounded_decoding(pdftypes, budget):
    """For one read, the decoders that pdfminer.pdftypes uses (BOUNDED_DECODERS) are those of a _BoundedZlib of the
    budget, which is yielded; the module's own are put back afterwards, whatever happened."""
    bounded = _BoundedZlib(budget)
    saved = {name: getattr(pdftypes, name) for name in BOUNDED_DECODERS}
    pdftypes.zlib = bounded
    pdftypes.lzwdecode = bounded.lzwdecode
    pdftypes.rldecode = bounded.rldecode
    pdftypes.ccittfaxdecode = bounded.ccittfaxdecode
    try:
        yield bounded
    finally:
        for name, value in saved.items():
            setattr(pdftypes, name, value)


def _fail(reason, detail=""):
    return {"ok": False, "reason": reason, "detail": str(detail)[:200]}


def _finish(parts, limit, cut, markers):
    """Join the parts, normalise line ends, strip NUL and cut at limit; no text at all is no_text."""
    text = "\n\n".join(parts).replace("\r\n", "\n").replace("\r", "\n").replace("\x00", "")
    if not text.strip():
        return _fail("no_text")
    if len(text) > limit:
        cut = True
        end = text.rfind("\n", 0, limit + 1)
        text = text[:end] if end > 0 else text[:limit]
    return {"ok": True, "text": text, "cut": bool(cut), "markers": markers}


def _read_pdf(path, limit, max_unpacked, page_marker):
    import pdfplumber
    import pdfminer.pdftypes as pdftypes
    from pdfminer.pdfdocument import PDFEncryptionError
    from pdfminer.psparser import PSException
    from pdfplumber.utils.exceptions import MalformedPDFException, PdfminerException

    parts = []
    size = 0
    cut = False
    try:
        with _bounded_decoding(pdftypes, max_unpacked), pdfplumber.open(path) as pdf:
            for number, page in enumerate(pdf.pages, 1):
                text = _escape((page.extract_text() or "").strip())
                if not text:
                    continue
                part = page_marker.format(n=number) + "\n" + text
                size += len(part) + (2 if parts else 0)
                parts.append(part)
                if size > limit:
                    cut = True
                    break
    except _TooLarge:
        return _fail("contents_too_large", "the streams decode past %d bytes" % max_unpacked)
    except PdfminerException as error:
        wrapped = error.args[0] if error.args else error
        if isinstance(wrapped, _TooLarge):
            return _fail("contents_too_large", "the streams decode past %d bytes" % max_unpacked)
        if isinstance(wrapped, PDFEncryptionError):
            return _fail("encrypted", type(wrapped).__name__)
        return _fail("damaged", "%s: %s" % (type(wrapped).__name__, wrapped))
    except (MalformedPDFException, PSException) as error:
        return _fail("damaged", "%s: %s" % (type(error).__name__, error))
    return _finish(parts, limit, cut, "page")


def _heading_prefix(style_name):
    """The Markdown heading prefix of a paragraph style name: Title is one #, Heading n is n+1 (at most 6), else None (also for no style)."""
    if style_name == "Title":
        return "#"
    found = HEADING.match(style_name or "")
    if found:
        return "#" * min(int(found.group(1)) + 1, 6)
    return None


def _blocks(element, parent):
    """The paragraphs and tables of a block container (w:body, w:tc or w:sdtContent) in document order; a w:sdt is read through its w:sdtContent, recursively."""
    from docx.oxml.ns import qn
    from docx.table import Table
    from docx.text.paragraph import Paragraph

    for child in element.iterchildren():
        if child.tag == qn("w:p"):
            yield Paragraph(child, parent)
        elif child.tag == qn("w:tbl"):
            yield Table(child, parent)
        elif child.tag == qn("w:sdt"):
            content = child.find(qn("w:sdtContent"))
            if content is not None:
                yield from _blocks(content, parent)


def _runs_text(element, paragraph):
    """The text of the runs of a paragraph, of its hyperlinks, tracked insertions, simple fields, smart tags and custom XML, and of its inline content
    controls (nested ones too), in order; a text box and a tracked deletion are not read."""
    from docx.oxml.ns import qn
    from docx.text.run import Run

    wrappers = (qn("w:hyperlink"), qn("w:ins"), qn("w:fldSimple"), qn("w:smartTag"), qn("w:customXml"))
    out = []
    for child in element.iterchildren():
        if child.tag == qn("w:r"):
            out.append(Run(child, paragraph).text)
        elif child.tag in wrappers:
            out.append(_runs_text(child, paragraph))
        elif child.tag == qn("w:sdt"):
            content = child.find(qn("w:sdtContent"))
            if content is not None:
                out.append(_runs_text(content, paragraph))
    return "".join(out)


def _paragraph_text(paragraph):
    return _runs_text(paragraph._p, paragraph)


def _block_text(item):
    """The text of a block inside a cell: a paragraph's text, or a nested table's cell texts in row order, joined by a space."""
    from docx.table import Table

    if isinstance(item, Table):
        return " ".join(text for cells in _rows(item) for text in cells if text)
    return _paragraph_text(item).strip()


def _cell_text(cell):
    """A cell's text: the texts of its blocks (nested tables and content controls included) joined by a space, line breaks as spaces."""
    texts = [_block_text(item) for item in _blocks(cell._tc, cell)]
    return " ".join(text for text in texts if text).replace("\n", " ").strip()


def _rows(table):
    """The cell texts of each row of a table; a merged cell is read once."""
    for row in table.rows:
        cells = []
        previous = None
        for cell in row.cells:
            if cell._tc is previous:
                continue
            previous = cell._tc
            cells.append(_cell_text(cell))
        yield cells


def _read_docx(path, limit, max_unpacked):
    import docx
    from docx.opc.exceptions import PackageNotFoundError
    from docx.table import Table
    from lxml import etree

    try:
        with zipfile.ZipFile(path) as archive:
            unpacked = sum(info.file_size for info in archive.infolist())
            has_document = DOCUMENT_PART in archive.namelist()
    except zipfile.BadZipFile as error:
        return _fail("damaged", error)
    if unpacked > max_unpacked:
        return _fail("contents_too_large", unpacked)
    if not has_document:
        return _fail("wrong_type", "no " + DOCUMENT_PART)

    parts = []
    size = 0
    cut = False
    headings = False
    try:
        document = docx.Document(path)
        for item in _blocks(document.element.body, document):
            if isinstance(item, Table):
                part = _escape("\n".join(" | ".join(cells) for cells in _rows(item) if any(cells)))
            else:
                part = _paragraph_text(item).strip()
                prefix = _heading_prefix(item.style.name if item.style is not None else None) if part else None
                if prefix:
                    headings = True
                    part = prefix + " " + part.replace("\n", " ")
                else:
                    part = _escape(part)
            if not part:
                continue
            size += len(part) + (2 if parts else 0)
            parts.append(part)
            if size > limit:
                cut = True
                break
    except (zipfile.BadZipFile, KeyError, PackageNotFoundError, etree.XMLSyntaxError, zlib.error, EOFError) as error:
        return _fail("damaged", "%s: %s" % (type(error).__name__, error))
    except ValueError as error:
        # python-docx refuses a main part that is not a Word document (a .docm, a .dotx).
        if "is not a Word file" not in str(error):
            raise
        return _fail("wrong_type", error)
    except NotImplementedError as error:
        # zipfile refuses strong encryption and a compression method it does not have (caught before RuntimeError, its base class).
        if "encryption" in str(error):
            return _fail("encrypted", error)
        if "compression method" not in str(error):
            raise
        return _fail("damaged", error)
    except RuntimeError as error:
        # zipfile refuses a password-protected entry.
        if "encrypted" not in str(error):
            raise
        return _fail("encrypted", error)
    return _finish(parts, limit, cut, "heading" if headings else "none")


def extract(path, limit, max_unpacked, page_marker):
    """Read the file at path: PDF with pdfplumber, .docx with python-docx.

    limit is the most characters of text kept (the text is cut at the last line break at or before it, and the
    reading stops once over it). max_unpacked is the most bytes a .docx may declare in all its zip entries, and the
    most bytes that all Flate, LZW, RunLength and CCITT fax streams of a PDF may decode to.
    page_marker is a format string with {n} for the page number.
    """
    with open(path, "rb") as stream:
        head = stream.read(PDF_WINDOW)
        if not head:
            return _fail("damaged", "no bytes")
        if head.startswith(ZIP_SIGNATURE):
            kind = "docx"
        elif head.startswith(OLE2_SIGNATURE):
            data = head + stream.read()
            if ENCRYPTED_STREAM in data:
                return _fail("encrypted", "OLE2 EncryptedPackage")
            if LEGACY_STREAM in data:
                return _fail("legacy_doc", "OLE2 WordDocument")
            return _fail("wrong_type", "OLE2 without a Word stream")
        elif PDF_SIGNATURE in head:
            kind = "pdf"
        else:
            return _fail("wrong_type", "no PDF, ZIP or OLE2 signature")
    if kind == "pdf":
        return _read_pdf(path, limit, max_unpacked, page_marker)
    return _read_docx(path, limit, max_unpacked)
