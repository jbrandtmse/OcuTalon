/// Tests of OcuTalon.Core.Files, the file-store call (Story 25.3; AD-4, AD-14, AD-21; security conditions (iii) and (iv)). Safe on a slot: no production is needed.
/// Every sentence is written out here, never read from the class under test, except where a test pins two copies equal. The rows are made for the SessionRefs
/// ZzFilesA and ZzFilesB and removed before each test and after the tests.
///   - TestStoreEachType: a PDF, a Word file, a JPEG and a PNG are stored with the exact media type, a row of the session, the exact file object and the channel;
///   - TestSizeLimit: 10,485,760 bytes are accepted and 10,485,761 are too_large with no row; the size check comes before the type check;
///   - TestEmpty: no bytes are empty, with no row;
///   - TestWrongType: every other kind of bytes or name is wrong_type with no row: text, markdown, GIF, the old .doc, a PNG name on PDF bytes, unknown bytes, MZ bytes
///     named x.pdf, HTML bytes named x.pdf and x.png, a zip without word/document.xml named x.docx, a name with no extension and a .docx name on PDF bytes; the checks
///     run in order size, empty, type;
///   - TestWordEntryAfterFirstChunk: the document entry is found past the first 32,000 bytes and across a chunk boundary;
///   - TestDefaultName: a name that is empty after SafeName becomes photo.jpg, photo.png, file.pdf or file.docx;
///   - TestTelegramChannel: channel telegram gives the same row shape;
///   - TestSafeName: a 400-character name holding <script>, a newline and U+202E is cut to 255 with the controls gone, and white space is trimmed;
///   - TestOpenIsOwnerScoped, TestDescribe: Open and Describe find the session's own file only, and Describe never carries the bytes;
///   - TestSetItem: SetItem sets the four file fields and never the text; the content marker is in no property of the Item;
///   - TestRefusalText: RefusalText gives the PUBLIC TEXT sentences, equal to Docs.Extract's frame, and SizeText equals Docs.Extract's;
///   - TestNoReaderText: the fixed reply, with the safe name;
///   - TestNoReaderYet: Readable() is 0 on this branch and Agent.Input defines READSFILES as 0 (Story 26.2 added the parameter and Story 25.6 flips it, with its chip and texts, so that
///     the feature head stays releasable); a reader class with READSFILES 1 is readable, and a class whose parameter is absent, 0 or "1 " is not.
Class OcuTalon.Test.Core.Files Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Do ..DeleteFixtures()
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Do ..DeleteFixtures()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..DeleteFixtures()
	Quit $SYSTEM.Status.OK()
}

Method TestStoreEachType()
{
	Set cases = $ListBuild($ListBuild("a.pdf", "application/pdf", "pdf"), $ListBuild("B.DOCX", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "docx"), $ListBuild("c.jpg", "image/jpeg", "jpeg"), $ListBuild("c.jpeg", "image/jpeg", "jpeg"), $ListBuild("d.png", "image/png", "png"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set name = $List(case, 1), mediaType = $List(case, 2), kind = $List(case, 3)
		Set bytes = ..Sample(kind, "zzmarker")
		Set size = bytes.Size
		Set code = ##class(OcuTalon.Core.Files).Store("ZzFilesA", "web", name, bytes, .file, .sc)
		Do $$$AssertStatusOK(sc, name_": the status is OK")
		Do $$$AssertEquals(code, "", name_": no refusal")
		Do $$$AssertEquals($Select($IsObject(file): file.%ToJSON(), 1: ""), {"ref": (file.ref), "name": (name), "mediaType": (mediaType), "size": (size)}.%ToJSON(), name_": the file object holds ref, name, media type and size, in that order")
		Set row = ##class(OcuTalon.Data.SentFile).RefIndexOpen(file.ref)
		Do $$$AssertEquals(row.SessionRef_"|"_row.Channel_"|"_row.Name_"|"_row.MediaType_"|"_row.Size, "ZzFilesA|web|"_name_"|"_mediaType_"|"_size, name_": the row holds the session, the channel, the name, the media type and the size")
		Set opened = ##class(OcuTalon.Core.Files).Open(file.ref, "ZzFilesA")
		Do $$$AssertEquals(opened.Size, size, name_": Open gives all the bytes")
	}
	Do $$$AssertEquals(..Count("ZzFilesA"), 5, "one row for each file")
}

Method TestSizeLimit()
{
	Set exact = ..Padded("pdf", 10485760)
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Store("ZzFilesA", "web", "big.pdf", exact, .file, .sc), "", "10,485,760 bytes are accepted")
	Do $$$AssertEquals(..Count("ZzFilesA"), 1, "and stored")
	Do ##class(OcuTalon.Data.SentFile).DropSession("ZzFilesA")
	Set over = ..Padded("pdf", 10485761)
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Store("ZzFilesA", "web", "big.pdf", over, .file, .sc), "too_large", "10,485,761 bytes are too_large")
	Do $$$AssertEquals(..Count("ZzFilesA")_"|"_$IsObject(file), "0|0", "with no row and no file object")
	Set overUnknown = ..Padded("none", 10485761)
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Store("ZzFilesA", "web", "big.exe", overUnknown, .file), "too_large", "the size check comes before the type check")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Store("ZzFilesA", "web", "big.exe", ..Stream(""), .file), "empty", "the empty check comes before the type check")
}

Method TestEmpty()
{
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Store("ZzFilesA", "web", "a.pdf", ..Stream(""), .file), "empty", "no bytes are empty")
	Do $$$AssertEquals(..Count("ZzFilesA"), 0, "with no row")
}

Method TestWrongType()
{
	Set cases = $ListBuild("x.txt|text", "x.md|text", "x.gif|gif", "x.doc|doc", "x.png|pdf", "x.pdf|none", "x.pdf|exe", "x.pdf|html", "x.png|html", "x.docx|zipnoword", "x|pdf", "x.docx|pdf", "x.pdf|png", "x.jpg|png", "x.pdf|docx", "x.exe|pdf", "x.pdf.exe|pdf", "x.pdf |none")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set name = $Piece(case, "|", 1), kind = $Piece(case, "|", 2)
		Set code = ##class(OcuTalon.Core.Files).Store("ZzFilesA", "web", name, ..Sample(kind, "zzmarker"), .file, .sc)
		Do $$$AssertEquals(code, "wrong_type", name_" with "_kind_" bytes is wrong_type")
		Do $$$AssertEquals($IsObject(file), 0, name_": no file object")
	}
	Do $$$AssertEquals(..Count("ZzFilesA"), 0, "no row for any of them")
}

/// The Word check reads the whole stream: the entry word/document.xml is found after the first 32,000 bytes and across a chunk boundary, and a zip that
/// names it nowhere is still wrong_type.
Method TestWordEntryAfterFirstChunk()
{
	For lead = 31925, 70000 {
		Set entries(1) = "a.bin"
		Set entries(1, "data") = $Translate($Justify("", lead), " ", "a")
		Set entries(2) = "word/document.xml"
		Set entries(2, "data") = "<w:document/>"
		Set stream = ##class(OcuTalon.Test.Docs.Samples).Zip(.entries, 2)
		Do stream.Rewind()
		Set code = ##class(OcuTalon.Core.Files).Store("ZzFilesA", "web", "big.docx", stream, .file, .sc)
		Do $$$AssertEquals(code, "", "a Word file with its document entry after "_lead_" bytes is stored")
		If code = "" Do $$$AssertEquals(file.mediaType, ##class(OcuTalon.Core.Files).#DOCX, "as Word ("_lead_")")
	}
	Set entries(1) = "a.bin"
	Set entries(1, "data") = $Translate($Justify("", 70000), " ", "a")
	Kill entries(2)
	Set stream = ##class(OcuTalon.Test.Docs.Samples).Zip(.entries, 1)
	Do stream.Rewind()
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Store("ZzFilesA", "web", "big.docx", stream, .file, .sc), "wrong_type", "a large zip with no document entry is wrong_type")
}

Method TestDefaultName()
{
	Set cases = $ListBuild($ListBuild("pdf", "file.pdf"), $ListBuild("docx", "file.docx"), $ListBuild("jpeg", "photo.jpg"), $ListBuild("png", "photo.png"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set code = ##class(OcuTalon.Core.Files).Store("ZzFilesA", "telegram", "  "_$Char(10, 8238)_" ", ..Sample($List(case, 1)), .file)
		Do $$$AssertEquals(code_"|"_file.name, "|"_$List(case, 2), "a name with nothing left becomes "_$List(case, 2))
	}
}

Method TestTelegramChannel()
{
	Set code = ##class(OcuTalon.Core.Files).Store("ZzFilesB", "telegram", "photo.jpg", ..Sample("jpeg"), .file, .sc)
	Do $$$AssertEquals(code, "", "a Telegram file is stored")
	Set row = ##class(OcuTalon.Data.SentFile).RefIndexOpen(file.ref)
	Do $$$AssertEquals(row.Channel_"|"_row.SessionRef_"|"_row.MediaType, "telegram|ZzFilesB|image/jpeg", "the row has channel telegram and the same shape")
}

Method TestSafeName()
{
	Set name = "  zz<script>"_$Char(10)_"alert(1)"_$Char(8238)_"x"_$Translate($Justify("", 400), " ", "q")_".pdf"
	Set safe = ##class(OcuTalon.Core.Files).SafeName(name)
	Do $$$AssertEquals($Length(safe), 255, "the name is cut to 255 characters")
	Do $$$AssertEquals(safe, "zz<script>alert(1)x"_$Translate($Justify("", 236), " ", "q"), "the controls, the bidirectional control and the white space are gone")
	For code = 8234, 8235, 8236, 8237, 8238, 8294, 8295, 8296, 8297 {
		Do $$$AssertEquals(##class(OcuTalon.Core.Files).SafeName("a"_$Char(code)_"b"), "ab", "U+"_$ZHex(code)_" is removed")
	}
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).SafeName(" "_$Char(9)_"x y "_$Char(0)), "x y", "white space is trimmed and a NUL removed")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).SafeName($Char(233)_".pdf"), $Char(233)_".pdf", "a letter is kept")
	Set code = ##class(OcuTalon.Core.Files).Store("ZzFilesA", "web", "zz"_$Char(10)_"<b>x"_$Translate($Justify("", 400), " ", "q")_".pdf", ..Sample("pdf"), .file)
	Do $$$AssertEquals(code_"|"_$Length(file.name), "|255", "Store cuts a long name to 255 characters")
	Do $$$AssertEquals(code, "", "its extension is checked before the cut")
}

Method TestOpenIsOwnerScoped()
{
	Set ref = ..Add("ZzFilesA", "pdf")
	Set opened = ##class(OcuTalon.Core.Files).Open(ref, "ZzFilesA", .sc)
	Do $$$AssertStatusOK(sc, "the owner's read is OK")
	Do $$$AssertEquals(opened.Read(5), "%PDF-", "the owner reads the bytes")
	Set other = ##class(OcuTalon.Core.Files).Open(ref, "ZzFilesB", .sc)
	Do $$$AssertEquals(other, "", "another session finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Open("", "ZzFilesA"), "", "an empty Ref finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Open(ref, ""), "", "an empty SessionRef finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Discard(ref, "ZzFilesB"), 1, "Discard with another session's SessionRef is OK")
	Do $$$AssertEquals(..Count("ZzFilesA"), 1, "and deletes nothing")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Discard(ref, "ZzFilesA"), 1, "Discard of the owner's file is OK")
	Do $$$AssertEquals(..Count("ZzFilesA"), 0, "and deletes it")
}

Method TestDescribe()
{
	Set ref = ..Add("ZzFilesA", "png", "zzmarker")
	Set file = ##class(OcuTalon.Core.Files).Describe(ref, "ZzFilesA")
	Do $$$AssertEquals(file.%ToJSON(), {"ref": (ref), "name": "zz.png", "mediaType": "image/png", "size": (..Sample("png", "zzmarker").Size)}.%ToJSON(), "Describe gives ref, name, media type and size")
	Do $$$AssertTrue(file.%ToJSON() '[ "zzmarker", "and never the bytes")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Describe(ref, "ZzFilesB"), "", "another session finds nothing")
}

Method TestSetItem()
{
	Set code = ##class(OcuTalon.Core.Files).Store("ZzFilesA", "web", "zz.pdf", ..Sample("pdf", "zzmarker"), .file)
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.SessionRef = "ZzFilesA"
	Set item.Text = "kept text"
	Do ##class(OcuTalon.Core.Files).SetItem(item, file)
	Do $$$AssertEquals(item.FileRef_"|"_item.FileName_"|"_item.FileMediaType_"|"_item.FileSize, file.ref_"|zz.pdf|application/pdf|"_file.size, "SetItem sets the four fields")
	Do $$$AssertEquals(item.Text, "kept text", "and never the text")
	Set blank = ##class(OcuTalon.Msg.Item).%New()
	Set blank.SessionRef = "ZzFilesA"
	Do ##class(OcuTalon.Core.Files).SetItem(blank, file)
	Do $$$AssertEquals(blank.Text, "", "an Item with no text keeps none")
	Set dump = ""
	For property = "ItemId", "SourceItemId", "SessionRef", "Channel", "Provenance", "Text", "Sender", "Subject", "CatalogKey", "Slots", "ClientId", "FileRef", "FileName", "FileMediaType", "FileSize" {
		Set dump = dump_$Property(blank, property)_"|"
	}
	Do $$$AssertTrue(dump '[ "zzmarker", "the content marker is in no property of the Item")
}

Method TestRefusalText()
{
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).RefusalText("too_large", 14680064), "That file is 14 MB; the limit is 10 MB.", "too large, with the size")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).RefusalText("too_large", 10485761), "That file is 10.1 MB; the limit is 10 MB.", "a size with a tenth")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).RefusalText("empty"), "I couldn't read that file: the file is empty.", "empty")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).RefusalText("wrong_type"), "I couldn't read that file: it isn't a PDF, Word (.docx), JPEG or PNG file.", "wrong type")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).#TEXTUNREADABLE, ##class(OcuTalon.Docs.Extract).#FAILUREFRAME, "the frame is Docs.Extract's")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).#TEXTOFFONDEMO, "Sending files is off on the online demo. It works on your own install.", "the off text")
	For bytes = 0, 1, 1023, 1024, 1025, 1048575, 1048576, 2202009, 10485760, 14680064, 15728640 {
		Do $$$AssertEquals(##class(OcuTalon.Core.Files).SizeText(bytes), ##class(OcuTalon.Docs.Extract).SizeText(bytes), "SizeText of "_bytes_" equals Docs.Extract's")
	}
}

Method TestNoReaderText()
{
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).NoReaderText("report.pdf"), "I got report.pdf, but I can't read files yet.", "the fixed reply")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).NoReaderText("a"_$Char(10)_"<b>"_$Char(8238)_".pdf"), "I got a<b>.pdf, but I can't read files yet.", "with the safe name")
}

/// The tripwire that Story 25.6 flips: Agent.Input defines READSFILES as 0, so nothing reads a sent file yet.
Method TestNoReaderYet()
{
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Readable(), 0, "Readable() is 0 on this branch")
	Do $$$AssertEquals(##class(%Dictionary.CompiledClass).%ExistsId(##class(OcuTalon.Core.Files).#READERCLASS), 1, "the class that Readable() probes exists, so its parameter is read")
	Do $$$AssertEquals(##class(%Dictionary.CompiledParameter).%ExistsId("OcuTalon.Agent.Input||READSFILES"), 1, "Agent.Input defines READSFILES")
	Do $$$AssertEquals($Parameter("OcuTalon.Agent.Input", "READSFILES"), 0, "as 0, which Story 25.6 flips")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Readable("OcuTalon.Test.Core.FilesReaderProbe"), 1, "a reader class with READSFILES 1 is readable")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Readable("OcuTalon.Test.Core.FilesReaderProbeAbsent"), 0, "a class with no READSFILES is not")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Readable("OcuTalon.Test.Core.FilesReaderProbeZero"), 0, "READSFILES 0 is not")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Readable("OcuTalon.Test.Core.FilesReaderProbeSpaced"), 0, "READSFILES ""1 "" is not")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Readable("OcuTalon.Zz.NoSuchClass"), 0, "a class that does not exist is not")
}

/// --- helpers ---
/// A new binary stream that holds the string.
Method Stream(data As %String) As %Stream.TmpBinary [ Private ]
{
	Set stream = ##class(%Stream.TmpBinary).%New()
	If data '= "" Do stream.Write(data)
	Do stream.Rewind()
	Quit stream
}

/// The bytes of a small file of the kind (pdf, docx, jpeg, png, text, gif, doc, exe, html, zipnoword, none), with the marker inside.
Method Sample(kind As %String, marker As %String = "zzfile") As %Stream.TmpBinary [ Private ]
{
	If kind = "pdf" Quit ..Stream("%PDF-1.4 "_marker)
	If kind = "png" Quit ..Stream($Char(137, 80, 78, 71, 13, 10, 26, 10)_"IHDR "_marker)
	If kind = "jpeg" Quit ..Stream($Char(255, 216, 255, 224)_"JFIF "_marker)
	If kind = "text" Quit ..Stream("plain text "_marker)
	If kind = "gif" Quit ..Stream("GIF89a "_marker)
	If kind = "doc" Quit ..Stream($Char(208, 207, 17, 224, 161, 177, 26, 225)_marker)
	If kind = "exe" Quit ..Stream("MZ"_$Char(144, 0, 3, 0)_marker)
	If kind = "html" Quit ..Stream("<html><script>alert('"_marker_"')</script></html>")
	If kind = "docx" {
		Set stream = ##class(OcuTalon.Test.Docs.Samples).Docx(##class(OcuTalon.Test.Docs.Samples).Paragraph(marker))
		Do stream.Rewind()
		Quit stream
	}
	If kind = "zipnoword" {
		Set entries(1) = "readme.txt"
		Set entries(1, "data") = marker
		Set stream = ##class(OcuTalon.Test.Docs.Samples).Zip(.entries, 1)
		Do stream.Rewind()
		Quit stream
	}
	Quit ..Stream("unknown bytes "_marker)
}

/// A stream of exactly size bytes that starts like a file of the kind (none: with no signature).
Method Padded(kind As %String, size As %Integer) As %Stream.TmpBinary [ Private ]
{
	Set stream = ##class(%Stream.TmpBinary).%New()
	Set head = $Select(kind = "pdf": "%PDF-", 1: "zzzzz")
	Do stream.Write(head)
	Do ##class(OcuTalon.Test.Docs.Samples).Fill(stream, size - $Length(head))
	Do stream.Rewind()
	Quit stream
}

/// Stores a file of the kind for the session, named zz.<extension>, and returns its Ref.
Method Add(session As %String, kind As %String, marker As %String = "zzfile") As %String [ Private ]
{
	Set code = ##class(OcuTalon.Core.Files).Store(session, "web", "zz."_$Select(kind = "jpeg": "jpg", 1: kind), ..Sample(kind, marker), .file, .sc)
	Do $$$AssertEquals(code, "", "the fixture file is stored")
	Quit file.ref
}

Method Count(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SentFile WHERE SessionRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

Method DeleteFixtures() [ Private ]
{
	Do ##class(OcuTalon.Data.SentFile).DropSession("ZzFilesA")
	Do ##class(OcuTalon.Data.SentFile).DropSession("ZzFilesB")
}

}
