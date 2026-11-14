/// The sample files of the document extraction tests (Story 19.6), built byte by byte in ObjectScript so that no binary is committed and no Python runs in the
/// test process (OcuTalon.Test.Docs.Extract proves that the caller never imports it). Each method returns a new %Stream.TmpBinary. The files hold no
/// copyrighted text. Not a test case.
///   - Pdf(.pages, count, padTo, encrypt): a PDF of count pages, the content stream of page n in pages(n); with padTo, an unreferenced padding stream that makes
///     the file exactly padTo bytes; with encrypt, an /Encrypt entry with fixed hex /O and /U (no password opens it);
///   - PdfText(text, comment) and DocxText(text): a one-page PDF and a one-paragraph Word file of the text, the PDF with an optional comment line after its header;
///   - TextPage(.lines, count) is a page content stream that shows the lines; Pdf3(), PdfDrawing(), PdfEncrypted(), PdfJunk(), PdfPadded(size), PdfPages(count)
///     (dense text pages, which take a PDF reader about 50 ms each), PdfBigText() (more than MAXTEXT characters);
///   - Zip(.entries, count): a stored zip (CRC-32 from $ZCRC mode 7); entries(n) is the name, entries(n, "data") its bytes, entries(n, "declare") a
///     declared unpacked size when it is not the length of the bytes, and entries(n, "flags") and entries(n, "method") the entry's general-purpose flags and
///     compression method when they are not 0 (the bytes are written as they are);
///   - Docx(body, declare, raw, moreStyles, mainType, flags, method), DocxHeadings(), DocxMergedCell(), DocxEmpty(), DocxBigText(), DocxDeclaring(size),
///     DocxBroken(), ZipWithoutDocument(): Word files built from paragraphs and a table (raw replaces the whole document part, as junk);
///   - DocxMacro(), DocxEncryptedEntry(), DocxOddCompression(), DocxDeflateJunk(): a macro-enabled main part, a password-protected document entry, a
///     document entry with a compression method zipfile does not have, and a deflated document entry whose bytes are not deflate data;
///   - PdfRunbook(), DocxRunbook(): the Results runbook as a two-page PDF ("Page 1" the title and the intro, "Page 2" the rotation steps) and the lab feed runbook
///     as a Word file (a Title, two Heading 1 sections and a table), for the documents tests of Story 19.7; PdfHashLine(), DocxHashLine(): own lines that start
///     with two number signs and a space (DW-832); DocxContentControls(), DocxOnlyControls(): body-level and inline content controls, a nested table and a
///     text box, and a file of content controls alone (DW-831); PdfBomb(): one Flate content stream of about 1 MB that inflates to about 165 MB (DW-828);
///     DocxHyperlinks(): a paragraph and a table cell with a hyperlink; DocxTracked(): a paragraph with a tracked insertion and deletion, a simple field, a smart
///     tag and custom XML (DW-926); PdfFlate(), PdfFlateTruncated(): a one-page PDF whose content stream is zlib data (stored
///     block), whole and without its Adler-32 (FlateStored builds the data);
///   - Ole(name): the OLE2 signature followed by the UTF-16LE stream name, as a legacy .doc (WordDocument), an encrypted .docx (EncryptedPackage) or neither;
///   - Junk(prefix), Padded(size), Empty(): a prefix and filler, a file of exactly size bytes of filler, and no bytes.
/// The text of each sample is in Expected* so that the tests compare against one place.
Class OcuTalon.Test.Docs.Samples
{

/// The accented word of the PDF sample, written as an escape.
ClassMethod Cafe() As %String [ CodeMode = expression ]
{
"caf" _ $Char(233)
}

/// A new binary stream that holds the string (every character below 256).
ClassMethod Stream(data As %String = "") As %Stream.TmpBinary
{
	Set stream = ##class(%Stream.TmpBinary).%New()
	If data '= "" Do stream.Write(data)
	Quit stream
}

ClassMethod Empty() As %Stream.TmpBinary
{
	Quit ..Stream()
}

ClassMethod Junk(prefix As %String) As %Stream.TmpBinary
{
	Quit ..Stream(prefix _ " junk junk junk, not a document")
}

/// A stream of exactly size bytes of filler.
ClassMethod Padded(size As %Integer) As %Stream.TmpBinary
{
	Set stream = ..Stream()
	Do ..Fill(stream, size)
	Quit stream
}

ClassMethod Fill(stream As %Stream.TmpBinary, size As %Integer)
{
	Set chunk = $Justify("", 32768)
	Set left = size
	While left > 0 {
		If left < 32768 Set chunk = $Justify("", left)
		Do stream.Write(chunk)
		Set left = left - $Length(chunk)
	}
}

/// A page content stream that shows the lines (lines(n)), the first at the top.
ClassMethod TextPage(ByRef lines, count As %Integer) As %String
{
	Set content = "BT /F1 12 Tf 14 TL 50 780 Td"
	For n = 1:1:count {
		Set content = content _ " (" _ lines(n) _ ") Tj T*"
	}
	Quit content _ " ET"
}

/// The little-endian bytes of a number.
ClassMethod LE(value As %Integer, bytes As %Integer) As %String
{
	Set out = ""
	For i = 1:1:bytes {
		Set out = out _ $Char(value # 256)
		Set value = value \ 256
	}
	Quit out
}

/// The line feed.
ClassMethod NL() As %String [ CodeMode = expression ]
{
$Char(10)
}

/// A PDF; see the class text. pages(n) is the content stream of page n; with filter (for example FlateDecode) each content stream names it as its /Filter; with
/// comment, a comment line (a percent sign and the comment) follows the header, so that its text is in the bytes and never in the text of a page.
ClassMethod Pdf(ByRef pages, count As %Integer, padTo As %Integer = 0, encrypt As %Boolean = 0, filter As %String = "", comment As %String = "") As %Stream.TmpBinary
{
	Set nl = ..NL()
	Set kids = ""
	For i = 1:1:count {
		Set kids = kids _ (2 * i + 2) _ " 0 R "
	}
	Set objects(1) = "<< /Type /Catalog /Pages 2 0 R >>"
	Set objects(2) = "<< /Type /Pages /Kids [" _ kids _ "] /Count " _ count _ " >>"
	Set objects(3) = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
	For i = 1:1:count {
		Set objects(2 * i + 2) = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents " _ (2 * i + 3) _ " 0 R /Resources << /Font << /F1 3 0 R >> >> >>"
		Set objects(2 * i + 3) = "<< /Length " _ $Length(pages(i)) _ $Select(filter '= "": " /Filter /" _ filter, 1: "") _ " >>" _ nl _ "stream" _ nl _ pages(i) _ nl _ "endstream"
	}
	Set total = 2 * count + 3
	Set extra = ""
	If encrypt {
		Set total = total + 1
		Set objects(total) = "<< /Filter /Standard /V 1 /R 2 /O <" _ ..Hex(32, "11") _ "> /U <" _ ..Hex(32, "22") _ "> /P -44 >>"
		Set extra = " /Encrypt " _ total _ " 0 R /ID [<" _ ..Hex(16, "ab") _ "> <" _ ..Hex(16, "ab") _ ">]"
	}
	Set head = "%PDF-1.4" _ nl _ $Select(comment '= "": "%" _ comment _ nl, 1: "")
	Set position = $Length(head)
	Set body = head
	For i = 1:1:total {
		Set offset(i) = position
		Set text = i _ " 0 obj" _ nl _ objects(i) _ nl _ "endobj" _ nl
		Set body = body _ text
		Set position = position + $Length(text)
	}
	Set stream = ..Stream()
	If 'padTo {
		Do stream.Write(body _ ..Tail(.offset, total, position, extra))
		Quit stream
	}
	// The padding object is the last: its length L makes the whole file padTo bytes (the digits of L and of the xref offset are part of it).
	Set padNumber = total + 1
	Set length = 0
	For try = 1:1:6 {
		Set padHead = padNumber _ " 0 obj" _ nl _ "<< /Length " _ length _ " >>" _ nl _ "stream" _ nl
		Set padTail = nl _ "endstream" _ nl _ "endobj" _ nl
		Set offset(padNumber) = position
		Set xref = position + $Length(padHead) + length + $Length(padTail)
		Set tail = ..Tail(.offset, padNumber, xref, extra)
		Set size = position + $Length(padHead) + length + $Length(padTail) + $Length(tail)
		If size = padTo Quit
		Set length = length + (padTo - size)
	}
	Do stream.Write(body _ padHead)
	Do ..Fill(stream, length)
	Do stream.Write(padTail _ tail)
	Quit stream
}

/// The cross-reference table, the trailer and the end of file, for total objects and the table at xref.
ClassMethod Tail(ByRef offset, total As %Integer, xref As %Integer, extra As %String) As %String
{
	Set nl = ..NL()
	Set text = "xref" _ nl _ "0 " _ (total + 1) _ nl _ "0000000000 65535 f " _ nl
	For i = 1:1:total {
		Set text = text _ $Translate($Justify(offset(i), 10), " ", "0") _ " 00000 n " _ nl
	}
	Quit text _ "trailer" _ nl _ "<< /Size " _ (total + 1) _ " /Root 1 0 R" _ extra _ " >>" _ nl _ "startxref" _ nl _ xref _ nl _ "%%EOF" _ nl
}

/// 2 * bytes hex digits made of the two-digit pair.
ClassMethod Hex(bytes As %Integer, pair As %String) As %String
{
	Set out = ""
	For i = 1:1:bytes {
		Set out = out _ pair
	}
	Quit out
}

/// Three pages, each with a line; the first holds an accented word.
ClassMethod Pdf3() As %Stream.TmpBinary
{
	Set lines(1) = "Page one " _ ..Cafe() _ " rotation"
	Set pages(1) = ..TextPage(.lines, 1)
	Set lines(1) = "Page two runbook"
	Set pages(2) = ..TextPage(.lines, 1)
	Set lines(1) = "Page three end"
	Set pages(3) = ..TextPage(.lines, 1)
	Quit ..Pdf(.pages, 3)
}

/// The text of Pdf3 as the extraction returns it.
ClassMethod ExpectedPdf3() As %String
{
	Set marker = ##class(OcuTalon.Docs.Extract).#PAGEMARKER
	Quit $Replace(marker, "{n}", 1) _ $Char(10) _ "Page one " _ ..Cafe() _ " rotation" _ $Char(10, 10) _ $Replace(marker, "{n}", 2) _ $Char(10) _ "Page two runbook" _ $Char(10, 10) _ $Replace(marker, "{n}", 3) _ $Char(10) _ "Page three end"
}

/// One page that only draws lines: no text layer.
ClassMethod PdfDrawing() As %Stream.TmpBinary
{
	Set pages(1) = "0 0 m 300 300 l S 10 10 m 100 10 l S"
	Quit ..Pdf(.pages, 1)
}

/// A one-page PDF that shows the text as one line (the text holds no parenthesis or backslash); comment, when given, is a comment line of the bytes after the header.
ClassMethod PdfText(text As %String, comment As %String = "") As %Stream.TmpBinary
{
	Set lines(1) = text
	Set pages(1) = ..TextPage(.lines, 1)
	Quit ..Pdf(.pages, 1, 0, 0, "", comment)
}

/// A PDF with an /Encrypt entry that the empty password does not open.
ClassMethod PdfEncrypted() As %Stream.TmpBinary
{
	Set lines(1) = "secret"
	Set pages(1) = ..TextPage(.lines, 1)
	Quit ..Pdf(.pages, 1, 0, 1)
}

ClassMethod PdfJunk() As %Stream.TmpBinary
{
	Quit ..Junk("%PDF-1.4" _ $Char(10))
}

/// A PDF of exactly size bytes: one text page and an unreferenced padding stream.
ClassMethod PdfPadded(size As %Integer) As %Stream.TmpBinary
{
	Set lines(1) = "Padded text page"
	Set pages(1) = ..TextPage(.lines, 1)
	Quit ..Pdf(.pages, 1, size)
}

/// A PDF of count pages of dense text (50 lines each): a PDF reader needs about 50 ms for each page.
ClassMethod PdfPages(count As %Integer, lineLength As %Integer = 85) As %Stream.TmpBinary
{
	Set base = "The quick brown fox jumps over the lazy dog 0123456789 runbook certificate rotation "
	Set line = $Extract(base _ base, 1, lineLength)
	For n = 1:1:50 {
		Set lines(n) = line
	}
	Set page = ..TextPage(.lines, 50)
	For n = 1:1:count {
		Set pages(n) = page
	}
	Quit ..Pdf(.pages, count)
}

/// A PDF whose text is over MAXTEXT characters (60 pages of 50 lines of 90 characters).
ClassMethod PdfBigText() As %Stream.TmpBinary
{
	Quit ..PdfPages(60, 90)
}

/// A stored zip of the entries; see the class text.
ClassMethod Zip(ByRef entries, count As %Integer) As %Stream.TmpBinary
{
	Set central = ""
	Set stream = ..Stream()
	Set position = 0
	For n = 1:1:count {
		Set name = entries(n)
		Set data = $Get(entries(n, "data"))
		Set declared = $Get(entries(n, "declare"), $Length(data))
		Set flags = $Get(entries(n, "flags"), 0)
		Set method = $Get(entries(n, "method"), 0)
		Set crc = $ZCRC(data, 7) # 4294967296
		Set local = "PK" _ $Char(3, 4) _ ..LE(20, 2) _ ..LE(flags, 2) _ ..LE(method, 2) _ ..LE(0, 2) _ ..LE(33, 2) _ ..LE(crc, 4) _ ..LE($Length(data), 4) _ ..LE(declared, 4) _ ..LE($Length(name), 2) _ ..LE(0, 2) _ name
		Do stream.Write(local)
		Do stream.Write(data)
		Set central = central _ "PK" _ $Char(1, 2) _ ..LE(20, 2) _ ..LE(20, 2) _ ..LE(flags, 2) _ ..LE(method, 2) _ ..LE(0, 2) _ ..LE(33, 2) _ ..LE(crc, 4) _ ..LE($Length(data), 4) _ ..LE(declared, 4) _ ..LE($Length(name), 2) _ ..LE(0, 2) _ ..LE(0, 2) _ ..LE(0, 2) _ ..LE(0, 2) _ ..LE(0, 4) _ ..LE(position, 4) _ name
		Set position = position + $Length(local) + $Length(data)
	}
	Do stream.Write(central)
	Do stream.Write("PK" _ $Char(5, 6) _ ..LE(0, 2) _ ..LE(0, 2) _ ..LE(count, 2) _ ..LE(count, 2) _ ..LE($Length(central), 4) _ ..LE(position, 4) _ ..LE(0, 2))
	Quit stream
}

/// A paragraph of the Word body, in the named style when there is one.
ClassMethod Paragraph(text As %String, style As %String = "") As %String
{
	Quit "<w:p>" _ $Select(style '= "": "<w:pPr><w:pStyle w:val=""" _ style _ """/></w:pPr>", 1: "") _ "<w:r><w:t>" _ text _ "</w:t></w:r></w:p>"
}

/// A table of the rows: rows(r, c) is the text of a cell.
ClassMethod Table(ByRef rows, rowCount As %Integer, columnCount As %Integer) As %String
{
	Set table = "<w:tbl>"
	For r = 1:1:rowCount {
		Set table = table _ "<w:tr>"
		For c = 1:1:columnCount {
			Set table = table _ "<w:tc>" _ ..Paragraph(rows(r, c)) _ "</w:tc>"
		}
		Set table = table _ "</w:tr>"
	}
	Quit table _ "</w:tbl>"
}

/// A Word file with the body (the XML of paragraphs and tables) and the styles Title, Heading 1, Heading 2 and Normal. declare is the unpacked size
/// that the document part declares when it is not its length; raw, when given, is the bytes of the document part instead of the body; moreStyles, when given,
/// is a comma-separated list of styleId|name pairs that are added to the styles (for example Heading5|heading 5); mainType, when given, is the content type
/// of the document part; flags and method are the document entry's zip flags and compression method.
ClassMethod Docx(body As %String, declare As %Integer = 0, raw As %String = "", moreStyles As %String = "", mainType As %String = "", flags As %Integer = 0, method As %Integer = 0) As %Stream.TmpBinary
{
	Set xml = "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?>"
	Set rels = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
	Set w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
	Set entries(1) = "[Content_Types].xml"
	Set entries(1, "data") = xml _ "<Types xmlns=""http://schemas.openxmlformats.org/package/2006/content-types""><Default Extension=""rels"" ContentType=""application/vnd.openxmlformats-package.relationships+xml""/><Default Extension=""xml"" ContentType=""application/xml""/><Override PartName=""/word/document.xml"" ContentType=""" _ $Select(mainType '= "": mainType, 1: "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml") _ """/><Override PartName=""/word/styles.xml"" ContentType=""application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml""/></Types>"
	Set entries(2) = "_rels/.rels"
	Set entries(2, "data") = xml _ "<Relationships xmlns=""http://schemas.openxmlformats.org/package/2006/relationships""><Relationship Id=""rId1"" Type=""" _ rels _ "/officeDocument"" Target=""word/document.xml""/></Relationships>"
	Set entries(3) = "word/_rels/document.xml.rels"
	Set entries(3, "data") = xml _ "<Relationships xmlns=""http://schemas.openxmlformats.org/package/2006/relationships""><Relationship Id=""rId1"" Type=""" _ rels _ "/styles"" Target=""styles.xml""/></Relationships>"
	Set entries(4) = "word/document.xml"
	Set entries(4, "data") = $Select(raw '= "": raw, 1: xml _ "<w:document xmlns:w=""" _ w _ """><w:body>" _ body _ "</w:body></w:document>")
	If declare Set entries(4, "declare") = declare
	If flags Set entries(4, "flags") = flags
	If method Set entries(4, "method") = method
	Set entries(5) = "word/styles.xml"
	Set styles = xml _ "<w:styles xmlns:w=""" _ w _ """>"
	Set list = $ListFromString("Title|Title,Heading1|heading 1,Heading2|heading 2,Normal|Normal" _ $Select(moreStyles '= "": "," _ moreStyles, 1: ""), ",")
	Set position = 0
	While $ListNext(list, position, style) {
		Set styles = styles _ "<w:style w:type=""paragraph""" _ $Select($Piece(style, "|") = "Normal": " w:default=""1""", 1: "") _ " w:styleId=""" _ $Piece(style, "|") _ """><w:name w:val=""" _ $Piece(style, "|", 2) _ """/></w:style>"
	}
	Set entries(5, "data") = styles _ "</w:styles>"
	Quit ..Zip(.entries, 5)
}

/// A Word file of one paragraph, the text (which holds no markup characters).
ClassMethod DocxText(text As %String) As %Stream.TmpBinary
{
	Quit ..Docx(..Paragraph(text))
}

/// Title, Heading 1 "Rotating the certificate", a paragraph, Heading 2, a paragraph, a 2x2 table and a last paragraph.
ClassMethod DocxHeadings() As %Stream.TmpBinary
{
	Set rows(1, 1) = "a1", rows(1, 2) = "b1", rows(2, 1) = "a2", rows(2, 2) = "b2"
	Quit ..Docx(..Paragraph("Runbook", "Title") _ ..Paragraph("Rotating the certificate", "Heading1") _ ..Paragraph("First paragraph.") _ ..Paragraph("Sub step", "Heading2") _ ..Paragraph("Second paragraph.") _ ..Table(.rows, 2, 2) _ ..Paragraph("Last paragraph."))
}

/// The text of DocxHeadings as the extraction returns it.
ClassMethod ExpectedDocxHeadings() As %String
{
	Quit "# Runbook" _ $Char(10, 10) _ "## Rotating the certificate" _ $Char(10, 10) _ "First paragraph." _ $Char(10, 10) _ "### Sub step" _ $Char(10, 10) _ "Second paragraph." _ $Char(10, 10) _ "a1 | b1" _ $Char(10) _ "a2 | b2" _ $Char(10, 10) _ "Last paragraph."
}

/// A table whose first row is one cell that spans both columns ("Merged header") and whose second row has two cells (a2, b2).
ClassMethod DocxMergedCell() As %Stream.TmpBinary
{
	Set table = "<w:tbl><w:tblGrid><w:gridCol w:w=""2000""/><w:gridCol w:w=""2000""/></w:tblGrid>"
	Set table = table _ "<w:tr><w:tc><w:tcPr><w:gridSpan w:val=""2""/></w:tcPr>" _ ..Paragraph("Merged header") _ "</w:tc></w:tr>"
	Set table = table _ "<w:tr><w:tc>" _ ..Paragraph("a2") _ "</w:tc><w:tc>" _ ..Paragraph("b2") _ "</w:tc></w:tr></w:tbl>"
	Quit ..Docx(table)
}

/// The text of DocxMergedCell as the extraction returns it: the merged cell is read once.
ClassMethod ExpectedDocxMergedCell() As %String
{
	Quit "Merged header" _ $Char(10) _ "a2 | b2"
}

/// A zip with a word/document.xml part that is not XML: a zip python-docx cannot open.
ClassMethod DocxBroken() As %Stream.TmpBinary
{
	Quit ..Docx("", 0, "this is not xml, <w:document")
}

/// A macro-enabled Word file (.docm): the main part's content type is not a Word document's.
ClassMethod DocxMacro() As %Stream.TmpBinary
{
	Quit ..Docx(..Paragraph("With macros"), 0, "", "", "application/vnd.ms-word.document.macroEnabled.main+xml")
}

/// A Word file whose document entry is marked password-protected (zip flag bit 0).
ClassMethod DocxEncryptedEntry() As %Stream.TmpBinary
{
	Quit ..Docx(..Paragraph("Protected entry"), 0, "", "", "", 1)
}

/// A Word file whose document entry names compression method 98 (PPMd), which zipfile does not have.
ClassMethod DocxOddCompression() As %Stream.TmpBinary
{
	Quit ..Docx(..Paragraph("Odd compression"), 0, "", "", "", 0, 98)
}

/// A Word file whose document entry says deflated (method 8) but holds bytes that are not deflate data.
ClassMethod DocxDeflateJunk() As %Stream.TmpBinary
{
	Quit ..Docx("", 0, $Char(255, 255, 255, 255) _ "not deflate data", "", "", 0, 8)
}

/// A Word file with no paragraph.
ClassMethod DocxEmpty() As %Stream.TmpBinary
{
	Quit ..Docx("")
}

/// A Word file whose text is over MAXTEXT characters (3,000 paragraphs of 90 characters).
ClassMethod DocxBigText() As %Stream.TmpBinary
{
	Set body = ""
	Set text = $Justify("", 90)
	Set text = $Translate(text, " ", "y")
	For n = 1:1:3000 {
		Set body = body _ ..Paragraph(text)
	}
	Quit ..Docx(body)
}

/// A Word file whose document part declares size bytes unpacked.
ClassMethod DocxDeclaring(size As %Integer) As %Stream.TmpBinary
{
	Quit ..Docx(..Paragraph("Declared large"), size)
}

/// A zip that is not a Word file: it has no word/document.xml.
ClassMethod ZipWithoutDocument() As %Stream.TmpBinary
{
	Set entries(1) = "hello.txt"
	Set entries(1, "data") = "hi"
	Quit ..Zip(.entries, 1)
}

/// The OLE2 signature, a header of zeros and the stream name in UTF-16LE (WordDocument, EncryptedPackage or another).
ClassMethod Ole(name As %String) As %Stream.TmpBinary
{
	Set data = $Char($ZHex("D0"), $ZHex("CF"), $ZHex("11"), $ZHex("E0"), $ZHex("A1"), $ZHex("B1"), $ZHex("1A"), $ZHex("E1")) _ $Justify("", 504)
	Set data = $Translate(data, " ", $Char(0))
	For i = 1:1:$Length(name) {
		Set data = data _ $Extract(name, i) _ $Char(0)
	}
	Quit ..Stream(data _ $Translate($Justify("", 600), " ", $Char(0)))
}

/// The Results runbook as a PDF: page 1 holds the title and the intro, page 2 the three steps of the rotation (the Markdown runbook of the documents tests).
ClassMethod PdfRunbook() As %Stream.TmpBinary
{
	Set lines(1) = "Results runbook"
	Set lines(2) = "This runbook covers the Results production, the lab results feed"
	Set lines(3) = "that the clinic reads every morning."
	Set pages(1) = ..TextPage(.lines, 3)
	Kill lines
	Set lines(1) = "Rotating the Results certificate"
	Set lines(2) = "1. Stop the item named Results.Sender."
	Set lines(3) = "2. Install the new certificate in the SSL configuration named ResultsClient,"
	Set lines(4) = "then restart the item."
	Set lines(5) = "3. Send one test result and write the new expiry date in the on-call log."
	Set pages(2) = ..TextPage(.lines, 5)
	Quit ..Pdf(.pages, 2)
}

/// The text of PdfRunbook as the extraction returns it.
ClassMethod ExpectedPdfRunbook() As %String
{
	Set marker = ##class(OcuTalon.Docs.Extract).#PAGEMARKER
	Set lf = $Char(10)
	Quit $Replace(marker, "{n}", 1) _ lf _ "Results runbook" _ lf _ "This runbook covers the Results production, the lab results feed" _ lf _ "that the clinic reads every morning." _ lf _ lf _ $Replace(marker, "{n}", 2) _ lf _ "Rotating the Results certificate" _ lf _ "1. Stop the item named Results.Sender." _ lf _ "2. Install the new certificate in the SSL configuration named ResultsClient," _ lf _ "then restart the item." _ lf _ "3. Send one test result and write the new expiry date in the on-call log."
}

/// The lab feed runbook as a Word file: the Title, Heading 1 "Restarting the lab feed" with two steps, and Heading 1 "Checking the lab numbers" with a 2x2 table.
ClassMethod DocxRunbook() As %Stream.TmpBinary
{
	Set rows(1, 1) = "Counter", rows(1, 2) = "Expected", rows(2, 1) = "Queue length", rows(2, 2) = "zero"
	Quit ..Docx(..Paragraph("Lab feed runbook", "Title") _ ..Paragraph("Restarting the lab feed", "Heading1") _ ..Paragraph("1. Stop the item named Lab.Feed in the Management Portal.") _ ..Paragraph("2. Start the item again and watch the queue for ten minutes.") _ ..Paragraph("Checking the lab numbers", "Heading1") _ ..Table(.rows, 2, 2))
}

/// The text of DocxRunbook as the extraction returns it.
ClassMethod ExpectedDocxRunbook() As %String
{
	Set lf = $Char(10)
	Quit "# Lab feed runbook" _ lf _ lf _ "## Restarting the lab feed" _ lf _ lf _ "1. Stop the item named Lab.Feed in the Management Portal." _ lf _ lf _ "2. Start the item again and watch the queue for ten minutes." _ lf _ lf _ "## Checking the lab numbers" _ lf _ lf _ "Counter | Expected" _ lf _ "Queue length | zero"
}

/// One PDF page whose own text has a line that starts with two number signs and a space.
ClassMethod PdfHashLine() As %Stream.TmpBinary
{
	Set lines(1) = "Intro line"
	Set lines(2) = "## Not a heading"
	Set lines(3) = "Last line"
	Set pages(1) = ..TextPage(.lines, 3)
	Quit ..Pdf(.pages, 1)
}

/// The text of PdfHashLine as the extraction returns it: the file's own line is escaped with a backslash, the page marker is the only section line.
ClassMethod ExpectedPdfHashLine() As %String
{
	Set lf = $Char(10)
	Quit $Replace(##class(OcuTalon.Docs.Extract).#PAGEMARKER, "{n}", 1) _ lf _ "Intro line" _ lf _ "\## Not a heading" _ lf _ "Last line"
}

/// A Word file with a Heading 1, then own lines that start with two number signs and a space in a paragraph, in a table row and in a content control.
ClassMethod DocxHashLine() As %Stream.TmpBinary
{
	Set rows(1, 1) = "## Cell line", rows(1, 2) = "x"
	Quit ..Docx(..Paragraph("Real section", "Heading1") _ ..Paragraph("## Not a heading") _ ..Table(.rows, 1, 2) _ ..Control(..Paragraph("## In a control")))
}

/// The text of DocxHashLine as the extraction returns it.
ClassMethod ExpectedDocxHashLine() As %String
{
	Set lf = $Char(10)
	Quit "## Real section" _ lf _ lf _ "\## Not a heading" _ lf _ lf _ "\## Cell line | x" _ lf _ lf _ "\## In a control"
}

/// A block-level content control around the blocks (the XML of paragraphs and tables).
ClassMethod Control(blocks As %String) As %String
{
	Quit "<w:sdt><w:sdtPr><w:alias w:val=""control""/></w:sdtPr><w:sdtContent>" _ blocks _ "</w:sdtContent></w:sdt>"
}

/// A table of one row with the cells (the XML of their blocks), with its grid.
ClassMethod Row(first As %String, second As %String) As %String
{
	Quit "<w:tbl><w:tblGrid><w:gridCol w:w=""2000""/><w:gridCol w:w=""2000""/></w:tblGrid><w:tr><w:tc>" _ first _ "</w:tc><w:tc>" _ second _ "</w:tc></w:tr></w:tbl>"
}

/// A Word file with a paragraph, a body-level content control, a paragraph with an inline content control, a table whose first cell holds a paragraph and a nested
/// table, a paragraph with a text box, and a last paragraph.
ClassMethod DocxContentControls() As %Stream.TmpBinary
{
	Set inline = "<w:p><w:r><w:t xml:space=""preserve"">Inline </w:t></w:r><w:sdt><w:sdtPr><w:alias w:val=""inline""/></w:sdtPr><w:sdtContent><w:r><w:t>control</w:t></w:r></w:sdtContent></w:sdt><w:r><w:t xml:space=""preserve""> end</w:t></w:r></w:p>"
	Set nested = ..Row("<w:p><w:r><w:t>n1</w:t></w:r></w:p>", "<w:p><w:r><w:t>n2</w:t></w:r></w:p>")
	Set outer = ..Row(..Paragraph("Outer") _ nested _ "<w:p/>", ..Paragraph("Side"))
	Set box = "<w:p><w:r><w:t>Around the box</w:t></w:r><w:r><w:pict><v:shape xmlns:v=""urn:schemas-microsoft-com:vml""><v:textbox><w:txbxContent>" _ ..Paragraph("Box text") _ "</w:txbxContent></v:textbox></v:shape></w:pict></w:r></w:p>"
	Quit ..Docx(..Paragraph("Before controls") _ ..Control(..Paragraph("Body control text")) _ inline _ outer _ box _ ..Paragraph("After the box"))
}

/// The text of DocxContentControls as the extraction returns it: each text once, the nested table inside the outer cell, no text box.
ClassMethod ExpectedDocxContentControls() As %String
{
	Set lf = $Char(10)
	Quit "Before controls" _ lf _ lf _ "Body control text" _ lf _ lf _ "Inline control end" _ lf _ lf _ "Outer n1 n2 | Side" _ lf _ lf _ "Around the box" _ lf _ lf _ "After the box"
}

/// A Word file made only of content controls.
ClassMethod DocxOnlyControls() As %Stream.TmpBinary
{
	Quit ..Docx(..Control(..Paragraph("Only a control")) _ ..Control(..Paragraph("And another")))
}

/// The text of DocxOnlyControls as the extraction returns it.
ClassMethod ExpectedDocxOnlyControls() As %String
{
	Quit "Only a control" _ $Char(10, 10) _ "And another"
}

/// A PDF with one page whose content stream is Flate data of about 1 MB that inflates to about 165 MB (a decompression bomb): a zlib header, one fixed-Huffman
/// block of one literal and copies of 258 bytes at distance 1 (13 bits each, so eight copies are 13 bytes that repeat), an end of block and the Adler-32.
ClassMethod PdfBomb() As %Stream.TmpBinary
{
	Set pages(1) = ..BombFlate(80000)
	Quit ..Pdf(.pages, 1, 0, 0, "FlateDecode")
}

/// The zlib data of PdfBomb: one literal A and 1 + 8 * groups copies of length 258 and distance 1, so 1 + 258 * (1 + 8 * groups) bytes of A.
ClassMethod BombFlate(groups As %Integer) As %String
{
	Set copy = "1100010100000"
	Set cycle = ""
	For i = 1:1:8 Set cycle = cycle _ copy
	Set pattern = ..Pack(cycle)
	Set body = ""
	For i = 1:1:groups Set body = body _ pattern
	Set n = 1 + (258 * (1 + (8 * groups)))
	Set a = (1 + (65 * n)) # 65521
	Set b = (n + (65 * ((n * (n + 1) \ 2) # 65521))) # 65521
	Quit $Char(120, 1) _ ..Pack("110" _ "01110001" _ copy) _ body _ $Char(0) _ $Char(b \ 256, b # 256, a \ 256, a # 256)
}

/// The zlib data that holds data as one stored (uncompressed) deflate block, followed by its Adler-32 unless adler is 0 (a truncated stream).
ClassMethod FlateStored(data As %String, adler As %Boolean = 1) As %String
{
	Set a = 1
	Set b = 0
	For i = 1:1:$Length(data) {
		Set a = (a + $Ascii(data, i)) # 65521
		Set b = (b + a) # 65521
	}
	Set out = $Char(120, 1, 1) _ ..LE($Length(data), 2) _ ..LE(65535 - $Length(data), 2) _ data
	If adler Set out = out _ $Char(b \ 256, b # 256, a \ 256, a # 256)
	Quit out
}

/// A PDF of one page of two lines whose content stream is zlib data (a /FlateDecode stored block, with its Adler-32).
ClassMethod PdfFlate() As %Stream.TmpBinary
{
	Set lines(1) = "Flate page one"
	Set lines(2) = "second line of the Flate page"
	Set pages(1) = ..FlateStored(..TextPage(.lines, 2))
	Quit ..Pdf(.pages, 1, 0, 0, "FlateDecode")
}

/// PdfFlate with the Adler-32 cut off: zlib reports an incomplete stream and pdfminer reads it through its fallback for corrupted data.
ClassMethod PdfFlateTruncated() As %Stream.TmpBinary
{
	Set lines(1) = "Flate page one"
	Set lines(2) = "second line of the Flate page"
	Set pages(1) = ..FlateStored(..TextPage(.lines, 2), 0)
	Quit ..Pdf(.pages, 1, 0, 0, "FlateDecode")
}

/// The text of PdfFlate and of PdfFlateTruncated as the extraction returns it.
ClassMethod ExpectedPdfFlate() As %String
{
	Quit $Replace(##class(OcuTalon.Docs.Extract).#PAGEMARKER, "{n}", 1) _ $Char(10) _ "Flate page one" _ $Char(10) _ "second line of the Flate page"
}

/// A Word file with a paragraph that holds a hyperlink and a table whose first cell holds the same paragraph.
ClassMethod DocxHyperlinks() As %Stream.TmpBinary
{
	Set link = "<w:p><w:r><w:t xml:space=""preserve"">See </w:t></w:r><w:hyperlink w:anchor=""top""><w:r><w:t>the linked words</w:t></w:r></w:hyperlink><w:r><w:t xml:space=""preserve""> now</w:t></w:r></w:p>"
	Quit ..Docx(link _ ..Row(link, ..Paragraph("Side")))
}

/// The text of DocxHyperlinks as the extraction returns it: the hyperlink's words are in the paragraph and in the cell.
ClassMethod ExpectedDocxHyperlinks() As %String
{
	Quit "See the linked words now" _ $Char(10, 10) _ "See the linked words now | Side"
}

/// A Word file with one paragraph whose words sit in a tracked insertion, a simple field, a smart tag and custom XML, beside a tracked deletion, and a table
/// cell with the same paragraph (DW-926).
ClassMethod DocxTracked() As %Stream.TmpBinary
{
	Set run = "<w:r><w:t xml:space=""preserve"">{t}</w:t></w:r>"
	Set para = "<w:p>" _ $Replace(run, "{t}", "Plain ") _ "<w:ins w:id=""1"" w:author=""a"" w:date=""2026-01-01T00:00:00Z"">" _ $Replace(run, "{t}", "inserted ") _ "</w:ins>"
	Set para = para _ "<w:del w:id=""2"" w:author=""a"" w:date=""2026-01-01T00:00:00Z""><w:r><w:delText>deleted </w:delText></w:r></w:del>"
	Set para = para _ "<w:fldSimple w:instr="" PAGE "">" _ $Replace(run, "{t}", "7 ") _ "</w:fldSimple><w:smartTag w:uri=""urn:x"" w:element=""place"">" _ $Replace(run, "{t}", "tagged ") _ "</w:smartTag>"
	Set para = para _ "<w:customXml w:element=""part"">" _ $Replace(run, "{t}", "custom") _ "</w:customXml></w:p>"
	Quit ..Docx(para _ ..Row(para, ..Paragraph("Side")))
}

/// The text of DocxTracked as the extraction returns it: the inserted, field, smart tag and custom XML words are read, the deleted word is not.
ClassMethod ExpectedDocxTracked() As %String
{
	Quit "Plain inserted 7 tagged custom" _ $Char(10, 10) _ "Plain inserted 7 tagged custom | Side"
}

/// The bytes of a string of 0 and 1 characters, 8 to a byte, the first of each eight being the lowest bit (deflate's bit order).
ClassMethod Pack(bits As %String) As %String
{
	Set out = ""
	For i = 1:8:$Length(bits) {
		Set value = 0
		For j = 0:1:7 {
			If $Extract(bits, i + j) = 1 Set value = value + (2 ** j)
		}
		Set out = out _ $Char(value)
	}
	Quit out
}

}
