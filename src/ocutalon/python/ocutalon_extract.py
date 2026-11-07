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
"""

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


def _read_pdf(path, limit, page_marker):
    import pdfplumber
    from pdfminer.pdfdocument import PDFEncryptionError
    from pdfminer.psparser import PSException
    from pdfplumber.utils.exceptions import MalformedPDFException, PdfminerException

    parts = []
    size = 0
    cut = False
    try:
        with pdfplumber.open(path) as pdf:
            for number, page in enumerate(pdf.pages, 1):
                text = (page.extract_text() or "").strip()
                if not text:
                    continue
                part = page_marker.format(n=number) + "\n" + text
                size += len(part) + (2 if parts else 0)
                parts.append(part)
                if size > limit:
                    cut = True
                    break
    except PdfminerException as error:
        wrapped = error.args[0] if error.args else error
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


def _read_docx(path, limit, max_unpacked):
    import docx
    from docx.opc.exceptions import PackageNotFoundError
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
        for item in document.iter_inner_content():
            if type(item).__name__ == "Table":
                lines = []
                for row in item.rows:
                    cells = []
                    previous = None
                    for cell in row.cells:
                        if cell._tc is previous:
                            continue
                        previous = cell._tc
                        cells.append(cell.text.replace("\n", " ").strip())
                    if any(cells):
                        lines.append(" | ".join(cells))
                part = "\n".join(lines)
            else:
                part = item.text.strip()
                prefix = _heading_prefix(item.style.name if item.style is not None else None) if part else None
                if prefix:
                    headings = True
                    part = prefix + " " + part.replace("\n", " ")
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
    reading stops once over it). max_unpacked is the most bytes a .docx may declare in all its zip entries.
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
        return _read_pdf(path, limit, page_marker)
    return _read_docx(path, limit, max_unpacked)
