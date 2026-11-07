/// QA tests of OcuTalon.Docs.Extract for the rows and details of Story 19.6 that OcuTalon.Test.Docs.Extract does not pin (added by the QA stage; the tests there are
/// not repeated). They read generated samples through the real pdfplumber and python-docx, so they run only on OcuTalon's Docker image (a throwaway stack or CI)
/// and record one named skip elsewhere, except TestReadNeverThrows, which needs no worker. Every read is checked for what it leaves behind. Tests assert reason
/// codes and structure, never the wording of a reason, the cut note or the page marker (those are PUBLIC TEXT with their own fixed-strings tests).
///   - TestAtTheTextLimit, TestCutWithoutLineBreak: a text of exactly MAXTEXT characters is not cut, and a text over it that has no line break is cut at MAXTEXT;
///   - TestPageNumbersAreReal: a page with no text gets no marker and the later pages keep their real numbers;
///   - TestHeadingLevels: Heading n is n+1 hash signs, at most six;
///   - TestPdfSignatureWindow: the PDF signature is looked for in the first 1,024 bytes, not only at the first byte and not further on, and a file that starts
///     with the ZIP signature is a zip even when %PDF- is in its first 1,024 bytes;
///   - TestWordFileVariants: a macro-enabled main part is wrong_type, a password-protected zip entry is encrypted, and a compression method zipfile does
///     not have or deflate data that is not deflate data is damaged (none of them failed);
///   - TestEncryptedBeatsLegacy: an OLE2 file with both Word stream names is encrypted, not a legacy .doc;
///   - TestContentsTooLargeAddsEntries, TestContentsAtTheLimit: the unpacked limit is the sum over all zip entries and a sum of exactly MAXUNPACKED is allowed;
///   - TestLineEndsNormalised: a carriage return in the file's text comes back as a line feed;
///   - TestReadNeverThrows: a content that is not a stream, or no content type, is a reason and not an error;
///   - TestEmbedderResource: ocutalon_memory.load_model asks for local files only and download passes the allow-pattern list, seen through stand-ins for the two
///     package calls in a worker of the Embedder's category (DW-792; no model is loaded and nothing is downloaded).
Class OcuTalon.Test.Docs.ExtractEdges Extends %UnitTest.TestCase
{

Parameter CATEGORY = "OcuTalon.Docs.Extractor";

Method OnBeforeAllTests() As %Status
{
	Kill ^||OcuTalonTestDocsEdges
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit $$$OK
	If '##class(OcuTalon.Test.Memory.Fixture).CategoryExists(..#CATEGORY) {
		Set sc = ##class(OcuTalon.Install.Step.Memory).EnsureCategory(..#CATEGORY, ##class(OcuTalon.Docs.Extractor).#MAXACTIVEWORKERS, ##class(OcuTalon.Docs.Extractor).#DEFAULTWORKERS)
		If $SYSTEM.Status.IsError(sc) Quit sc
		Set ^||OcuTalonTestDocsEdges("category") = 1
	}
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If $Get(^||OcuTalonTestDocsEdges("category")) {
		New $Namespace
		Set $Namespace = "%SYS"
		Do ##class(Config.WorkQueues).Delete(..#CATEGORY)
	}
	Kill ^||OcuTalonTestDocsEdges
	Quit $$$OK
}

/// 1 on the image; otherwise records the skip.
Method OnImage() As %Boolean [ Private ]
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit 1
	Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
	Quit 0
}

/// Reads the sample and asserts that the extraction folder is the same after it as before.
Method ReadSample(stream As %Stream.Object, type As %String, timeout As %Integer = 120) As %DynamicObject [ Private ]
{
	Set before = ##class(OcuTalon.Test.Docs.Extract).Files()
	Set answer = ##class(OcuTalon.Docs.Extract).Read(stream, type, timeout)
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.Extract).Files(), before, "the read leaves no file in the extraction folder")
	Quit answer
}

/// Asserts a failure with the reason code (and that the plain reason exists for it).
Method AssertFailure(answer As %DynamicObject, code As %String, what As %String) [ Private ]
{
	Do $$$AssertEquals(answer.ok, 0, what _ " is not read")
	Do $$$AssertEquals(answer.reason, code, what _ " has the reason " _ code)
}

/// A Word file whose body is one paragraph of count letters (no line break in it).
ClassMethod OneParagraph(count As %Integer) As %Stream.TmpBinary
{
	Quit ##class(OcuTalon.Test.Docs.Samples).Docx(##class(OcuTalon.Test.Docs.Samples).Paragraph($Translate($Justify("", count), " ", "y")))
}

Method TestAtTheTextLimit()
{
	If '..OnImage() Quit
	Set limit = ##class(OcuTalon.Docs.Extract).#MAXTEXT
	Set answer = ..ReadSample(..OneParagraph(limit), "docx")
	Do $$$AssertEquals(answer.ok, 1, "a Word file with exactly MAXTEXT characters of text is read")
	Do $$$AssertEquals(answer.cut, 0, "and not cut")
	Do $$$AssertEquals($Length(answer.text), limit, "its whole text comes back, with no note after it")
}

Method TestCutWithoutLineBreak()
{
	If '..OnImage() Quit
	Set limit = ##class(OcuTalon.Docs.Extract).#MAXTEXT
	Set answer = ..ReadSample(..OneParagraph(limit + 1), "docx")
	Do $$$AssertEquals(answer.ok, 1, "a Word file with one more character than MAXTEXT, all on one line, is read")
	Do $$$AssertEquals(answer.cut, 1, "and cut")
	Set note = $Char(10, 10) _ ##class(OcuTalon.Docs.Extract).#CUTNOTE
	Set whole = $Length(answer.text)
	Do $$$AssertEquals($Extract(answer.text, whole - $Length(note) + 1, whole), note, "it ends with a blank line and the cut note")
	Set kept = $Extract(answer.text, 1, whole - $Length(note))
	Do $$$AssertEquals($Length(kept), limit, "with no line break to cut at, the text is cut at MAXTEXT characters")
	Do $$$AssertEquals($Translate(kept, "y"), "", "and what is kept is the start of the text")
}

Method TestPageNumbersAreReal()
{
	If '..OnImage() Quit
	Set lines(1) = "First page text"
	Set pages(1) = ##class(OcuTalon.Test.Docs.Samples).TextPage(.lines, 1)
	Set pages(2) = "0 0 m 300 300 l S"
	Set lines(1) = "Third page text"
	Set pages(3) = ##class(OcuTalon.Test.Docs.Samples).TextPage(.lines, 1)
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Pdf(.pages, 3), "pdf")
	Do $$$AssertEquals(answer.ok, 1, "a PDF whose middle page has no text is read")
	Do $$$AssertEquals(answer.markers, "page", "with page markers")
	Set marker = ##class(OcuTalon.Docs.Extract).#PAGEMARKER
	Set expected = $Replace(marker, "{n}", 1) _ $Char(10) _ "First page text" _ $Char(10, 10) _ $Replace(marker, "{n}", 3) _ $Char(10) _ "Third page text"
	Do $$$AssertEquals(answer.text, expected, "the empty page has no marker and the last page keeps its real number 3")
}

Method TestHeadingLevels()
{
	If '..OnImage() Quit
	Set body = ##class(OcuTalon.Test.Docs.Samples).Paragraph("Level three", "Heading3")
	Set body = body _ ##class(OcuTalon.Test.Docs.Samples).Paragraph("Level five", "Heading5")
	Set body = body _ ##class(OcuTalon.Test.Docs.Samples).Paragraph("Level six", "Heading6")
	Set body = body _ ##class(OcuTalon.Test.Docs.Samples).Paragraph("Level nine", "Heading9")
	Set styles = "Heading3|heading 3,Heading5|heading 5,Heading6|heading 6,Heading9|heading 9"
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Docx(body, 0, "", styles), "docx")
	Do $$$AssertEquals(answer.ok, 1, "a Word file with deep headings is read")
	Do $$$AssertEquals(answer.markers, "heading", "with heading markers")
	Set expected = "#### Level three" _ $Char(10, 10) _ "###### Level five" _ $Char(10, 10) _ "###### Level six" _ $Char(10, 10) _ "###### Level nine"
	Do $$$AssertEquals(answer.text, expected, "Heading 3 is four hash signs, and Heading 5, 6 and 9 are six (at most 6)")
}

Method TestPdfSignatureWindow()
{
	If '..OnImage() Quit
	// A PDF with 100 bytes before its header is still a PDF (Acrobat's window is 1,024 bytes): never wrong_type.
	Set answer = ..ReadSample(..Prefixed(100), "pdf")
	Do $$$AssertTrue(answer.%Get("reason") '= "wrong_type", "a PDF with 100 bytes before %PDF- is not called a wrong type (ok " _ answer.ok _ ", reason " _ answer.%Get("reason") _ ")")
	// Further on than the window it is not found: no PDF, ZIP or OLE2 signature.
	Set answer = ..ReadSample(..Prefixed(1100), "pdf")
	Do ..AssertFailure(answer, "wrong_type", "a file whose %PDF- starts at byte 1,101")
	// A zip whose first entry name holds %PDF- is read as a zip: it has no word/document.xml, so wrong_type (as a PDF it would be damaged).
	Set entries(1) = "a%PDF-b.txt"
	Set entries(1, "data") = "x"
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Zip(.entries, 1), "docx")
	Do ..AssertFailure(answer, "wrong_type", "a zip with %PDF- in its first bytes")
	Do $$$AssertTrue(answer.%Get("detail") [ "word/document.xml", "which is read as a zip, not as a PDF (" _ answer.%Get("detail") _ ")")
}

Method TestWordFileVariants()
{
	If '..OnImage() Quit
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).DocxMacro(), "docx")
	Do ..AssertFailure(answer, "wrong_type", "a macro-enabled Word file (.docm)")
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).DocxEncryptedEntry(), "docx")
	Do ..AssertFailure(answer, "encrypted", "a Word file with a password-protected zip entry")
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).DocxOddCompression(), "docx")
	Do ..AssertFailure(answer, "damaged", "a Word file with a compression method that zipfile does not have")
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).DocxDeflateJunk(), "docx")
	Do ..AssertFailure(answer, "damaged", "a Word file whose deflated entry is not deflate data")
}

/// Pdf3 behind count bytes of filler (none of them a signature).
ClassMethod Prefixed(count As %Integer) As %Stream.TmpBinary
{
	Set stream = ##class(OcuTalon.Test.Docs.Samples).Stream($Translate($Justify("", count), " ", "x"))
	Set pdf = ##class(OcuTalon.Test.Docs.Samples).Pdf3()
	Do pdf.Rewind()
	Do stream.CopyFrom(pdf)
	Quit stream
}

Method TestEncryptedBeatsLegacy()
{
	If '..OnImage() Quit
	Set stream = ##class(OcuTalon.Test.Docs.Samples).Ole("WordDocument")
	Set name = "EncryptedPackage"
	For i = 1:1:$Length(name) {
		Do stream.Write($Extract(name, i) _ $Char(0))
	}
	Set answer = ..ReadSample(stream, "docx")
	Do ..AssertFailure(answer, "encrypted", "an OLE2 file with a WordDocument stream and an EncryptedPackage stream")
}

/// A zip with a word/document.xml part and a padding part that declare the sizes (the bytes of both are one character).
ClassMethod Declaring(first As %Integer, second As %Integer) As %Stream.TmpBinary
{
	Set entries(1) = "word/document.xml"
	Set entries(1, "data") = "x"
	Set entries(1, "declare") = first
	Set entries(2) = "padding.bin"
	Set entries(2, "data") = "y"
	Set entries(2, "declare") = second
	Quit ##class(OcuTalon.Test.Docs.Samples).Zip(.entries, 2)
}

Method TestContentsTooLargeAddsEntries()
{
	If '..OnImage() Quit
	Set limit = ##class(OcuTalon.Docs.Extract).#MAXUNPACKED
	// Each entry alone is under the limit; together they are one byte over.
	Set answer = ..ReadSample(..Declaring(60000000, limit - 60000000 + 1), "docx")
	Do ..AssertFailure(answer, "contents_too_large", "a Word file whose two parts declare one byte more than MAXUNPACKED together")
}

Method TestContentsAtTheLimit()
{
	If '..OnImage() Quit
	Set limit = ##class(OcuTalon.Docs.Extract).#MAXUNPACKED
	Set answer = ..ReadSample(..Declaring(60000000, limit - 60000000), "docx")
	Do $$$AssertEquals(answer.ok, 0, "a zip that is no Word file is not read")
	Do $$$AssertTrue(answer.%Get("reason") '= "contents_too_large", "but exactly MAXUNPACKED declared bytes are not too many (ok " _ answer.ok _ ", reason " _ answer.%Get("reason") _ ")")
}

Method TestLineEndsNormalised()
{
	If '..OnImage() Quit
	Set body = ##class(OcuTalon.Test.Docs.Samples).Paragraph("alpha&#13;&#10;beta") _ ##class(OcuTalon.Test.Docs.Samples).Paragraph("gamma&#13;delta")
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Docx(body), "docx")
	Do $$$AssertEquals(answer.ok, 1, "a Word file with carriage returns in its text is read")
	Do $$$AssertEquals(answer.text, "alpha" _ $Char(10) _ "beta" _ $Char(10, 10) _ "gamma" _ $Char(10) _ "delta", "a CR LF pair is one line feed and a lone CR is a line feed")
}

Method TestReadNeverThrows()
{
	Set before = ##class(OcuTalon.Test.Docs.Extract).Files()
	Try {
		Set answer = ##class(OcuTalon.Docs.Extract).Read("", "pdf")
		Do ..AssertFailure(answer, "damaged", "a content that is not a stream")
		Set answer = ##class(OcuTalon.Docs.Extract).Read("", "")
		Do ..AssertFailure(answer, "wrong_type", "no content and no type")
		Set answer = ##class(OcuTalon.Docs.Extract).Read(##class(OcuTalon.Test.Docs.Samples).Junk("hello"))
		Do ..AssertFailure(answer, "wrong_type", "a stream with no content type")
		Set answer = ##class(OcuTalon.Docs.Extract).Read(##class(OcuTalon.Test.Docs.Samples).Junk("hello"), "")
		Do ..AssertFailure(answer, "wrong_type", "a stream with an empty content type")
	} Catch exception {
		Do $$$AssertTrue(0, "Read threw: " _ exception.DisplayString())
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.Extract).Files(), before, "and none of them writes a file")
}

/// The work item that calls ocutalon_memory.load_model with a recording stand-in for fastembed.TextEmbedding (the package attribute is put back afterwards):
/// %result("args") and %result("kwargs") are the text of the arguments that the stand-in received. No model is loaded and nothing is downloaded.
ClassMethod RecordLoad(folder As %String) As %Status
{
	Kill %result
	Set sc = $SYSTEM.Status.OK()
	Set builtins = ##class(%SYS.Python).Import("builtins")
	Set package = ##class(%SYS.Python).Import("fastembed")
	Set original = builtins.getattr(package, "TextEmbedding")
	Try {
		Set mock = ##class(%SYS.Python).Import("unittest.mock").MagicMock()
		Do builtins.setattr(package, "TextEmbedding", mock)
		Do ##class(%SYS.Python).Import("ocutalon_memory")."load_model"("the-model", folder)
		Set %result("args") = builtins.str(mock."call_args".args)
		Set %result("kwargs") = builtins.str(mock."call_args".kwargs)
	} Catch exception {
		Kill %result
		Set sc = exception.AsStatus()
	}
	Do builtins.setattr(package, "TextEmbedding", original)
	Quit sc
}

/// The same for ocutalon_memory.download and huggingface_hub.snapshot_download, with a tuple of two patterns.
ClassMethod RecordDownload(folder As %String) As %Status
{
	Kill %result
	Set sc = $SYSTEM.Status.OK()
	Set builtins = ##class(%SYS.Python).Import("builtins")
	Set package = ##class(%SYS.Python).Import("huggingface_hub")
	Set original = builtins.getattr(package, "snapshot_download")
	Try {
		Set mock = ##class(%SYS.Python).Import("unittest.mock").MagicMock()
		Do builtins.setattr(package, "snapshot_download", mock)
		Set patterns = builtins.list()
		Do patterns.append("one.json")
		Do patterns.append("two.onnx")
		Do ##class(%SYS.Python).Import("ocutalon_memory").download("the/source", folder, builtins.tuple(patterns))
		Set %result("args") = builtins.str(mock."call_args".args)
		Set %result("kwargs") = builtins.str(mock."call_args".kwargs)
	} Catch exception {
		Kill %result
		Set sc = exception.AsStatus()
	}
	Do builtins.setattr(package, "snapshot_download", original)
	Quit sc
}

Method TestEmbedderResource()
{
	If '..OnImage() Quit
	Set folder = "/zz-docs-model-folder"
	Set sc = ##class(OcuTalon.Memory.Embedder).Submit("##class(" _ $ClassName() _ ").RecordLoad", 120, .result, folder)
	Do $$$AssertStatusOK(sc, "load_model ran in a worker with a stand-in for the model class")
	Do $$$AssertEquals($Get(result("args")), "('the-model',)", "it passes the model name as the one positional argument")
	Do $$$AssertTrue($Get(result("kwargs")) [ "'local_files_only': True", "and asks for local files only (no network try)")
	Do $$$AssertTrue($Get(result("kwargs")) [ ("'cache_dir': '" _ folder _ "'"), "and the folder as the cache directory")
	Kill result
	Set sc = ##class(OcuTalon.Memory.Embedder).Submit("##class(" _ $ClassName() _ ").RecordDownload", 120, .result, folder)
	Do $$$AssertStatusOK(sc, "download ran in a worker with a stand-in for snapshot_download")
	Do $$$AssertEquals($Get(result("args")), "('the/source',)", "it passes the source as the one positional argument")
	Do $$$AssertTrue($Get(result("kwargs")) [ ("'cache_dir': '" _ folder _ "'"), "and the folder as the cache directory")
	Do $$$AssertTrue($Get(result("kwargs")) [ "'allow_patterns': ['one.json', 'two.onnx']", "and the allow-patterns as a list")
}

}
