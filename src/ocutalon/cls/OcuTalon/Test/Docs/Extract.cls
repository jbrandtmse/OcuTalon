/// Tests of OcuTalon.Docs.Extract and the worker behind it (Story 19.6; AD-6, AD-21). They read generated samples (OcuTalon.Test.Docs.Samples) through the real
/// pdfplumber and python-docx, so they run only on OcuTalon's Docker image (a throwaway stack or CI) and record one named skip elsewhere. Every read is checked
/// for what it leaves behind: the extraction folder holds the same files after it as before. Each test makes the category OcuTalon.Docs.Extractor when the
/// install has not, and removes only what it made.
///   - TestPdfPages, TestDocxHeadings, TestDocxMergedCell, TestCut, TestAtTheLimit: the texts with their markers (the page marker and the cut note as literal
///     texts), a merged table cell read once, the cut and the 10 MB file;
///   - TestTooLarge, TestContentsTooLarge, TestWrongType, TestEncrypted, TestDamaged, TestNoText, TestLegacyDoc, TestTimeLimit: one reason code each, and the
///     worker free again after a timeout;
///   - TestRunsInAWorker, TestNeverInTheCaller: the work is done in a worker of the category, and the calling process never imports the packages;
///   - TestCategory, TestResourcesCurrent, TestNoticesKept: the install step makes the one-worker category, the worker imports the resources that the image
///     holds, and the image keeps the third-party notices of both packages;
///   - TestLimitsPinned, TestReasonsFitTheFrame: MAXBYTES equals the web upload limit, and each reason reads as part of the failure sentence;
///   - TestReasonsAreTheRuledText: the reasons, the frame, the cut note, the page marker and the size text are the ruled PUBLIC TEXT, byte for byte;
///   - TestNothingStored: no file is left, no document or knowledge-base global changes, and a leftover older than an hour is deleted by the next read;
///   - TestWorkerFailure, TestDetailHoldsNoSecret: a work item that fails comes back as an error and as the reason failed, and its detail holds no secret.
Class OcuTalon.Test.Docs.Extract Extends %UnitTest.TestCase
{

Parameter CATEGORY = "OcuTalon.Docs.Extractor";

Method OnBeforeAllTests() As %Status
{
	Kill ^||OcuTalonTestDocs
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit $$$OK
	If '##class(OcuTalon.Test.Memory.Fixture).CategoryExists(..#CATEGORY) {
		Set sc = ##class(OcuTalon.Install.Step.Memory).EnsureCategory(..#CATEGORY, ##class(OcuTalon.Docs.Extractor).#MAXACTIVEWORKERS, ##class(OcuTalon.Docs.Extractor).#DEFAULTWORKERS)
		If $SYSTEM.Status.IsError(sc) Quit sc
		Set ^||OcuTalonTestDocs("category") = 1
	}
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If $Get(^||OcuTalonTestDocs("category")) {
		New $Namespace
		Set $Namespace = "%SYS"
		Do ##class(Config.WorkQueues).Delete(..#CATEGORY)
	}
	Kill ^||OcuTalonTestDocs
	Quit $$$OK
}

/// 1 on the image; otherwise records the skip.
Method OnImage() As %Boolean [ Private ]
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit 1
	Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
	Quit 0
}

/// The names of the files in the extraction folder, as a list.
ClassMethod Files() As %List
{
	Set list = ""
	Set name = $ZSearch(##class(OcuTalon.Docs.Extract).Folder() _ "*")
	While name '= "" {
		Set list = list _ $ListBuild(name)
		Set name = $ZSearch("")
	}
	Quit list
}

/// Reads the sample and asserts that the extraction folder is the same after it as before.
Method ReadSample(stream As %Stream.Object, type As %String, timeout As %Integer = 120) As %DynamicObject [ Private ]
{
	Set before = ..Files()
	Set answer = ##class(OcuTalon.Docs.Extract).Read(stream, type, timeout)
	Do $$$AssertEquals(..Files(), before, "the read leaves no file in the extraction folder")
	Quit answer
}

/// Asserts a failure with the code and the plain reason that goes with it.
Method AssertFailure(answer As %DynamicObject, code As %String, what As %String) [ Private ]
{
	Do $$$AssertEquals(answer.ok, 0, what _ " is not read")
	Do $$$AssertEquals(answer.reason, code, what _ " has the reason " _ code)
	Do $$$AssertTrue(##class(OcuTalon.Docs.Extract).Failure(code) [ ##class(OcuTalon.Docs.Extract).Reason(code), what _ " has a plain reason in the failure sentence")
}

Method TestPdfPages()
{
	If '..OnImage() Quit
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Pdf3(), "pdf")
	Do $$$AssertEquals(answer.ok, 1, "the PDF is read")
	Do $$$AssertEquals(answer.markers, "page", "with page markers")
	Do $$$AssertEquals(answer.cut, 0, "not cut")
	Do $$$AssertTrue(##class(OcuTalon.Docs.Extract).#PAGEMARKER [ "{n}", "the page marker has the page number in it")
	Do $$$AssertTrue(answer.text [ $Replace(##class(OcuTalon.Docs.Extract).#PAGEMARKER, "{n}", 2), "and the text holds the marker of page 2")
	Do $$$AssertEquals(answer.text, ##class(OcuTalon.Test.Docs.Samples).ExpectedPdf3(), "each page's text under its marker line, in page order, the accent kept")
	Do $$$AssertEquals($Extract(answer.text, 1, 9), "## Page 1", "and it starts with the literal marker line of page 1")
	Do $$$AssertTrue(answer.job '= "" && (answer.job '= $Job), "the work ran in a job that is not the caller's")
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Pdf3(), "DOCX")
	Do $$$AssertEquals(answer.text, ##class(OcuTalon.Test.Docs.Samples).ExpectedPdf3(), "the signature decides the parser, not the declared type")
}

Method TestDocxHeadings()
{
	If '..OnImage() Quit
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).DocxHeadings(), "docx")
	Do $$$AssertEquals(answer.ok, 1, "the Word file is read")
	Do $$$AssertEquals(answer.markers, "heading", "with heading markers")
	Do $$$AssertEquals(answer.text, ##class(OcuTalon.Test.Docs.Samples).ExpectedDocxHeadings(), "the title is # , a heading n is n+1 # , the table rows come in order and the cells are joined by a bar")
}

Method TestDocxMergedCell()
{
	If '..OnImage() Quit
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).DocxMergedCell(), "docx")
	Do $$$AssertEquals(answer.ok, 1, "a Word file with a table cell that spans two columns is read")
	Do $$$AssertEquals(answer.text, ##class(OcuTalon.Test.Docs.Samples).ExpectedDocxMergedCell(), "the merged cell is read once, not once for each column it spans")
}

Method TestCut()
{
	If '..OnImage() Quit
	For kind = "pdf", "docx" {
		Set stream = $Select(kind = "pdf": ##class(OcuTalon.Test.Docs.Samples).PdfBigText(), 1: ##class(OcuTalon.Test.Docs.Samples).DocxBigText())
		Set answer = ..ReadSample(stream, kind)
		Do $$$AssertEquals(answer.ok, 1, "the " _ kind _ " with more text than the limit is read")
		Do $$$AssertEquals(answer.cut, 1, "and cut")
		Set note = $Char(10, 10) _ ##class(OcuTalon.Docs.Extract).#CUTNOTE
		Set whole = $Length(answer.text)
		Do $$$AssertEquals($Extract(answer.text, whole - $Length(note) + 1, whole), note, "it ends with a blank line and the cut note")
		Set literal = $Char(10, 10) _ "[OcuTalon read only the first 200,000 characters of this file.]"
		Do $$$AssertEquals($Extract(answer.text, whole - $Length(literal) + 1, whole), literal, "which is the literal note text")
		Do $$$AssertEquals(answer.markers, $Select(kind = "pdf": "page", 1: "none"), "a Word file with no heading has no markers, a PDF has page markers")
		Set kept = $Extract(answer.text, 1, whole - $Length(note))
		Do $$$AssertTrue($Length(kept) '> ##class(OcuTalon.Docs.Extract).#MAXTEXT, "the text before the note is at most the limit")
		Do $$$AssertTrue($Length(kept) > ##class(OcuTalon.Docs.Extract).#MAXTEXT - 400, "and is cut at the last line break before it, not much earlier")
	}
}

Method TestAtTheLimit()
{
	If '..OnImage() Quit
	Set stream = ##class(OcuTalon.Test.Docs.Samples).PdfPadded(##class(OcuTalon.Docs.Extract).#MAXBYTES)
	Do $$$AssertEquals(stream.Size, 10485760, "the sample PDF is exactly 10,485,760 bytes")
	Set start = $ZHorolog
	Set answer = ..ReadSample(stream, "pdf")
	Do $$$AssertEquals(answer.ok, 1, "a PDF of exactly the limit is read like any PDF")
	Do $$$AssertEquals(answer.text, $Replace(##class(OcuTalon.Docs.Extract).#PAGEMARKER, "{n}", 1) _ $Char(10) _ "Padded text page", "and gives its text")
	Do $$$AssertTrue($ZHorolog - start < ##class(OcuTalon.Docs.Extract).#TIMEOUT, "within the time limit")
}

Method TestTooLarge()
{
	If '..OnImage() Quit
	For type = "pdf", "docx" {
		Set stream = ##class(OcuTalon.Test.Docs.Samples).Padded(##class(OcuTalon.Docs.Extract).#MAXBYTES + 1)
		Set answer = ..ReadSample(stream, type)
		Do ..AssertFailure(answer, "too_large", "a " _ type _ " of 10,485,761 bytes")
		Do $$$AssertEquals(answer.%IsDefined("job"), 0, "no worker was called")
	}
	// No file is written: a leftover over an hour old survives a too-large read, because only a call that writes a file purges the folder.
	Set folder = ##class(OcuTalon.Docs.Extract).Folder()
	If '##class(%File).DirectoryExists(folder) Do ##class(%File).CreateDirectoryChain(folder)
	Set old = folder _ "zz-docs-old-toolarge.bin"
	Set stream = ##class(%Stream.FileBinary).%New()
	Do stream.LinkToFile(old)
	Do stream.Write("x")
	Do stream.%Save()
	Kill stream
	Do $$$AssertEquals($ZF(-100, "/SHELL", "touch", "-d", "2 hours ago", old), 0, "a planted file is made two hours old")
	Set answer = ##class(OcuTalon.Docs.Extract).Read(##class(OcuTalon.Test.Docs.Samples).Padded(##class(OcuTalon.Docs.Extract).#MAXBYTES + 1), "pdf")
	Do $$$AssertEquals(answer.reason, "too_large", "a too-large read")
	Do $$$AssertEquals(##class(%File).Exists(old), 1, "writes no file (it does not reach the purge)")
	Do ##class(%File).Delete(old)
}

Method TestContentsTooLarge()
{
	If '..OnImage() Quit
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).DocxDeclaring(##class(OcuTalon.Docs.Extract).#MAXUNPACKED + 1), "docx")
	Do ..AssertFailure(answer, "contents_too_large", "a Word file that declares more than 100 MB unpacked")
	Do $$$AssertEquals(answer.%IsDefined("job"), 1, "which the worker answers, without python-docx opening it")
}

Method TestWrongType()
{
	If '..OnImage() Quit
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Pdf3(), "txt")
	Do ..AssertFailure(answer, "wrong_type", "a file of another declared type")
	Do $$$AssertEquals(answer.%IsDefined("job"), 0, "no worker was called for it")
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Junk("hello"), "pdf")
	Do ..AssertFailure(answer, "wrong_type", "bytes with no PDF, ZIP or OLE2 signature")
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).ZipWithoutDocument(), "docx")
	Do ..AssertFailure(answer, "wrong_type", "a zip without word/document.xml")
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Ole("Workbook"), "docx")
	Do ..AssertFailure(answer, "wrong_type", "an OLE2 file with neither Word stream")
}

Method TestEncrypted()
{
	If '..OnImage() Quit
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).PdfEncrypted(), "pdf")
	Do ..AssertFailure(answer, "encrypted", "a PDF that the empty password does not open")
}

Method TestEncryptedDocx()
{
	If '..OnImage() Quit
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Ole("EncryptedPackage"), "docx")
	Do ..AssertFailure(answer, "encrypted", "a Word file that is an OLE2 container with an EncryptedPackage stream")
}

Method TestDamaged()
{
	If '..OnImage() Quit
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).PdfJunk(), "pdf")
	Do ..AssertFailure(answer, "damaged", "a PDF header followed by junk")
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Junk("PK" _ $Char(3, 4)), "docx")
	Do ..AssertFailure(answer, "damaged", "a zip header followed by junk")
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).DocxBroken(), "docx")
	Do ..AssertFailure(answer, "damaged", "a zip whose word/document.xml is not XML")
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Empty(), "pdf")
	Do ..AssertFailure(answer, "damaged", "a file of zero bytes")
	Do $$$AssertEquals(answer.%IsDefined("job"), 0, "which no worker is asked to read")
}

Method TestNoText()
{
	If '..OnImage() Quit
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).PdfDrawing(), "pdf")
	Do ..AssertFailure(answer, "no_text", "a PDF whose pages only draw lines")
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).DocxEmpty(), "docx")
	Do ..AssertFailure(answer, "no_text", "a Word file with no text")
}

Method TestLegacyDoc()
{
	If '..OnImage() Quit
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Ole("WordDocument"), "docx")
	Do ..AssertFailure(answer, "legacy_doc", "an OLE2 file with a WordDocument stream and no EncryptedPackage")
}

Method TestTimeLimit()
{
	If '..OnImage() Quit
	// A read leaves its worker idle; a group of one worker takes it again, so it is the one that the slow read keeps busy.
	Set worker = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Pdf3(), "pdf").job
	Set locksBefore = ..GroupLocks()
	Do $$$AssertTrue($Data(^$JOB(worker)) > 0, "a worker of the category is idle (job " _ worker _ ")")
	Set start = $ZHorolog
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).PdfPages(400), "pdf", 1)
	Set elapsed = $ZHorolog - start
	Do ..AssertFailure(answer, "timed_out", "a PDF that takes over 5 seconds, with a limit of 1 second")
	Do $$$AssertTrue(elapsed < 20, "which ends at the limit, not when the reading is done (" _ $FNumber(elapsed, "", 2) _ " seconds; the reading takes about 20)")
	Do $$$AssertEquals(..GroupLocks(), locksBefore, "the calling process holds no work group lock that it did not hold before")
	For i = 1:1:20 {
		Quit:'$Data(^$JOB(worker))
		Hang 0.5
	}
	Do $$$AssertEquals($Data(^$JOB(worker)), 0, "the busy worker is stopped: its job no longer exists")
	Set start = $ZHorolog
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Pdf3(), "pdf")
	Do $$$AssertEquals(answer.ok, 1, "the next read of the 3-page PDF is answered")
	Do $$$AssertTrue(answer.job '= worker, "by another worker")
	Do $$$AssertTrue($ZHorolog - start < 20, "in normal time (" _ $FNumber($ZHorolog - start, "", 2) _ " seconds)")
}

/// The work group locks that this process holds, as a text (empty when none).
ClassMethod GroupLocks() As %String
{
	Set count = ""
	Set prefix = "^IRIS.WorkQueue(""Group"","
	Set name = $Order(^$LOCK(""))
	While name '= "" {
		If ($Extract(name, 1, $Length(prefix)) = prefix) && ($Get(^$LOCK(name, "OWNER")) = $Job) Set count = count _ name _ " "
		Set name = $Order(^$LOCK(name))
	}
	Quit count
}

/// The work item that reports where it runs and which resources it imports.
ClassMethod InWorker() As %Status
{
	Kill %result
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set %result("job") = $Job
		Set %result("worker") = $SYSTEM.WorkMgr.IsWorkerJob()
		Set %result("extract") = ##class(%SYS.Python).Import("ocutalon_extract")."__file__"
		Set %result("memory") = ##class(%SYS.Python).Import("ocutalon_memory")."__file__"
	} Catch exception {
		Kill %result
		Set sc = exception.AsStatus()
	}
	Quit sc
}

Method TestRunsInAWorker()
{
	If '..OnImage() Quit
	Set sc = ##class(OcuTalon.Docs.Extractor).Submit("##class(" _ $ClassName() _ ").InWorker", 60, .result)
	Do $$$AssertStatusOK(sc, "the work item runs")
	Do $$$AssertTrue(result("job") '= $Job, "in a job that is not the caller's")
	Do $$$AssertEquals(result("worker"), 1, "which is a WorkMgr worker")
	Do $$$AssertTrue(##class(OcuTalon.Test.Memory.Fixture).WorkerInCategory(result("job"), ..#CATEGORY), "of the category " _ ..#CATEGORY)
	Set answer = ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Pdf3(), "pdf")
	Do $$$AssertTrue(##class(OcuTalon.Test.Memory.Fixture).WorkerInCategory(answer.job, ..#CATEGORY), "and so does a read: its job is a worker of the category")
}

Method TestNeverInTheCaller()
{
	If '..OnImage() Quit
	Do ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Pdf3(), "pdf")
	Do ..ReadSample(##class(OcuTalon.Test.Docs.Samples).DocxHeadings(), "docx")
	Set modules = ##class(%SYS.Python).Import("sys").modules
	For name = "pdfplumber", "docx", "ocutalon_extract" {
		Do $$$AssertEquals(modules."__contains__"(name), 0, "the calling process has not imported " _ name)
	}
}

Method TestCategory()
{
	If '..OnImage() Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Memory).EnsureCategory(..#CATEGORY, 5, 3), "the category is first put to 5 active and 3 default workers")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Memory).Run(), "the Memory step runs")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).CategoryProperties(..#CATEGORY, .properties), "the category exists")
	Do $$$AssertEquals($Get(properties("MaxActiveWorkers")), 1, "with 1 active worker")
	Do $$$AssertEquals($Get(properties("DefaultWorkers")), 1, "and 1 default worker")
	// The category is left at the declared values whatever happened above, so no later test meets 5 and 3.
	Do ##class(OcuTalon.Install.Step.Memory).EnsureCategory(..#CATEGORY, ##class(OcuTalon.Docs.Extractor).#MAXACTIVEWORKERS, ##class(OcuTalon.Docs.Extractor).#DEFAULTWORKERS)
}

Method TestResourcesCurrent()
{
	If '..OnImage() Quit
	Set sc = ##class(OcuTalon.Docs.Extractor).Submit("##class(" _ $ClassName() _ ").InWorker", 60, .result)
	Do $$$AssertStatusOK(sc, "a worker of the category imports both resources")
	Set folder = $SYSTEM.Util.ManagerDirectory() _ "python/"
	For name = "extract", "memory" {
		Set file = "ocutalon_" _ name _ ".py"
		Do $$$AssertEquals(##class(%File).GetDirectory($Get(result(name)), 1), ##class(%File).NormalizeDirectory(folder), file _ " is imported from the manager directory's python folder")
		Set image = "/opt/ocutalon/src/ocutalon/python/" _ file
		Do $$$AssertTrue(##class(%File).Exists(image), file _ " is in the image")
		Do $$$AssertEquals(..Content(folder _ file), ..Content(image), file _ " equals the image's file")
	}
}

/// The bytes of a file as a string (the resources are small).
ClassMethod Content(file As %String) As %String
{
	Set stream = ##class(%Stream.FileBinary).%New()
	Do stream.LinkToFile(file)
	Quit stream.Read(stream.Size)
}

Method TestNoticesKept()
{
	If '..OnImage() Quit
	Set file = "/opt/ocutalon/THIRD-PARTY-NOTICES"
	Do $$$AssertTrue(##class(%File).Exists(file), "the image keeps its third-party notices")
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set stream.TranslateTable = "UTF8"
	Do stream.LinkToFile(file)
	Set pdf = 0, word = 0
	While 'stream.AtEnd {
		Set line = stream.ReadLine(1000)
		If line = "pdfplumber 0.11.10" Set pdf = 1
		If line = "python-docx 1.1.2" Set word = 1
	}
	Do $$$AssertTrue(pdf, "they name pdfplumber 0.11.10")
	Do $$$AssertTrue(word, "and python-docx 1.1.2")
}

Method TestLimitsPinned()
{
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).#MAXBYTES, ##class(OcuTalon.Web.Documents).#FILEMAX, "the input limit equals the web upload limit")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).#MAXBYTES, 10485760, "10,485,760 bytes")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).#MAXTEXT, 200000, "the text limit is 200,000 characters")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).#MAXUNPACKED, 104857600, "the unpacked limit is 100 MB")
}

Method TestReasonsFitTheFrame()
{
	Set codes = $ListFromString(##class(OcuTalon.Docs.Extract).#CODES, ",")
	Do $$$AssertEquals($ListLength(codes), 9, "there are nine reason codes")
	Set position = 0
	While $ListNext(codes, position, code) {
		Set reason = ##class(OcuTalon.Docs.Extract).Reason(code)
		Do $$$AssertTrue(reason '= "", code _ " has a reason")
		Set ascii = 1
		For i = 1:1:$Length(reason) {
			If $Ascii(reason, i) > 127 Set ascii = 0
		}
		Do $$$AssertTrue(ascii, code _ " is ASCII")
		Do $$$AssertTrue($Ascii(reason) '< 97 && ($Ascii(reason) '> 122), code _ " starts with a lower-case letter")
		Set sentence = ##class(OcuTalon.Docs.Extract).Failure(code)
		Do $$$AssertTrue($Extract(sentence, *-1, *) '= "..", code _ ": the sentence does not end with two periods")
		Do $$$AssertTrue($Length(sentence) '> 120, code _ ": the failure sentence is at most 120 characters (" _ $Length(sentence) _ ")")
		Do $$$AssertEquals($Extract(sentence, 1, 27), "I couldn't read that file: ", code _ ": the sentence starts with the frame")
		Do $$$AssertEquals($Extract(sentence, $Length(sentence)), ".", code _ ": and ends with its period")
	}
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).Reason("no_such_code"), ##class(OcuTalon.Docs.Extract).Reason("failed"), "an unknown code has the reason of failed")
	Set sentence = ##class(OcuTalon.Docs.Extract).Failure("too_large", 104857600)
	Do $$$AssertTrue($Length(sentence) '> 120, "too_large with a size: the failure sentence is at most 120 characters (" _ $Length(sentence) _ ")")
}

/// The ruled PUBLIC TEXT (the Contest Planner's ruling of 2026-11-06), compared byte for byte, so that any edit turns this test red.
Method TestReasonsAreTheRuledText()
{
	Set x = "OcuTalon.Docs.Extract"
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).Reason("too_large"), "it's over the 10 MB limit", "too_large without a size")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).Reason("too_large", 10485761), "that file is 10.1 MB; the limit is 10 MB.", "too_large with a size (the web app's catalog text)")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).Reason("contents_too_large"), "its text is too long to read", "contents_too_large")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).Reason("wrong_type"), "it isn't a Markdown, plain-text, PDF or Word (.docx) file.", "wrong_type (the web app's catalog text)")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).Reason("encrypted"), "it's protected with a password", "encrypted")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).Reason("damaged"), "it's damaged or incomplete", "damaged")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).Reason("no_text"), "it has no text to read, for example a scanned PDF without a text layer", "no_text")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).Reason("legacy_doc"), "it's an old Word file (.doc); save it as .docx and try again", "legacy_doc")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).Reason("timed_out"), "reading it took too long", "timed_out")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).Reason("failed"), "something went wrong while reading it", "failed")
	Do $$$AssertEquals($Parameter(x, "FAILUREFRAME"), "I couldn't read that file: {reason}.", "the chat frame")
	Do $$$AssertEquals($Parameter(x, "CUTNOTE"), "[OcuTalon read only the first 200,000 characters of this file.]", "the cut note")
	Do $$$AssertEquals($Parameter(x, "PAGEMARKER"), "## Page {n}", "the page marker")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).Failure("encrypted"), "I couldn't read that file: it's protected with a password.", "a framed reason")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).Failure("wrong_type"), "I couldn't read that file: it isn't a Markdown, plain-text, PDF or Word (.docx) file.", "a framed catalog reason ends with one period")
	Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).Failure("too_large", 20971520), "I couldn't read that file: that file is 20 MB; the limit is 10 MB.", "a framed too_large with a size")
	// The size as the web app's formatSize writes it: whole KB rounded up under 1 MB, otherwise MB with one decimal rounded up and no ".0".
	For pair = "0|0 KB", "1|1 KB", "1024|1 KB", "1025|2 KB", "1048575|1024 KB", "1048576|1 MB", "1048577|1.1 MB", "10485760|10 MB", "10485761|10.1 MB", "15728640|15 MB", "15833497|15.1 MB", "15833498|15.2 MB" {
		Do $$$AssertEquals(##class(OcuTalon.Docs.Extract).SizeText($Piece(pair, "|")), $Piece(pair, "|", 2), $Piece(pair, "|") _ " bytes")
	}
}

Method TestNothingStored()
{
	If '..OnImage() Quit
	Set before = ..Signature()
	Do $$$AssertTrue(before [ "|Docs=", "the signature has the knowledge-base half: the table OcuTalonKB.Docs exists (Story 19.4, DW-833)")
	Do ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Pdf3(), "pdf")
	Do ..ReadSample(##class(OcuTalon.Test.Docs.Samples).DocxHeadings(), "docx")
	Do ..ReadSample(##class(OcuTalon.Test.Docs.Samples).PdfJunk(), "pdf")
	Do ..ReadSample(##class(OcuTalon.Test.Docs.Samples).Junk("hello"), "pdf")
	Do $$$AssertEquals(..Signature(), before, "no document or knowledge-base global changed")
	// A leftover of more than an hour is deleted by the next read; a recent one is not.
	Set folder = ##class(OcuTalon.Docs.Extract).Folder()
	If '##class(%File).DirectoryExists(folder) Do ##class(%File).CreateDirectoryChain(folder)
	Set old = folder _ "zz-docs-old.bin", recent = folder _ "zz-docs-recent.bin"
	For file = old, recent {
		Set stream = ##class(%Stream.FileBinary).%New()
		Do stream.LinkToFile(file)
		Do stream.Write("x")
		Do stream.%Save()
	}
	Do $$$AssertEquals($ZF(-100, "/SHELL", "touch", "-d", "2 hours ago", old), 0, "a planted file is made two hours old")
	Try {
		Set answer = ##class(OcuTalon.Docs.Extract).Read(##class(OcuTalon.Test.Docs.Samples).Pdf3(), "pdf")
		Do $$$AssertEquals(answer.ok, 1, "a read runs")
		Do $$$AssertEquals(##class(%File).Exists(old), 0, "and deletes the file that is over an hour old")
		Do $$$AssertEquals(##class(%File).Exists(recent), 1, "but not the recent one")
	} Catch exception {
		Do $$$AssertTrue(0, "the purge test fell over: " _ exception.DisplayString())
	}
	Do ##class(%File).Delete(old)
	Do ##class(%File).Delete(recent)
}

/// What the documents and the knowledge bases hold: the number of document rows, the row count of each knowledge-base table, the document extent's id counter and the
/// row count of OcuTalonKB.Docs, as one text.
ClassMethod Signature() As %String
{
	Set signature = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Document")
	If result.%Next() Set signature = "documents=" _ result.%GetData(1)
	Set tables = ##class(%SQL.Statement).%ExecDirect(, "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'OcuTalonKB' ORDER BY TABLE_NAME")
	While tables.%Next() {
		Set name = tables.%GetData(1)
		Set count = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalonKB." _ name)
		Set signature = signature _ "|" _ name _ "=" _ $Select(count.%Next(): count.%GetData(1), 1: "?")
	}
	Quit signature _ "|counter=" _ $Get(^OcuTalonP.DocumentD) _ "|kb=" _ ##class(OcuTalon.Docs.Store).Count()
}

Method TestWorkerFailure()
{
	If '..OnImage() Quit
	Set sc = ##class(OcuTalon.Docs.Extractor).Submit("Read", 60, .result, "/no/such/file.pdf", 1000, 1000, "## {n}")
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "a work item that cannot read its file is an error status")
	Set answer = ##class(OcuTalon.Docs.Extract).Answer(sc, .result)
	Do ..AssertFailure(answer, "failed", "the answer to it")
	Do $$$AssertTrue(answer.detail '= "", "with a detail for the operator")
	// Answer maps every branch without a worker.
	Kill result
	Set result("ok") = 1, result("text") = "body", result("cut") = 0, result("markers") = "page", result("job") = 77
	Set answer = ##class(OcuTalon.Docs.Extract).Answer($$$OK, .result)
	Do $$$AssertEquals(answer.ok, 1, "a text result is ok")
	Do $$$AssertEquals(answer.text, "body", "with its text")
	Do $$$AssertEquals(answer.cut, 0, "not cut")
	Set result("cut") = 1
	Set answer = ##class(OcuTalon.Docs.Extract).Answer($$$OK, .result)
	Do $$$AssertEquals(answer.text, "body" _ $Char(10, 10) _ ##class(OcuTalon.Docs.Extract).#CUTNOTE, "a cut text ends with the cut note")
	Do $$$AssertEquals(answer.cut, 1, "and says so")
	Kill result
	Set codes = $ListFromString(##class(OcuTalon.Docs.Extract).#CODES, ",")
	Set position = 0
	While $ListNext(codes, position, code) {
		Kill result
		Set result("ok") = 0, result("reason") = code, result("detail") = "note"
		Set answer = ##class(OcuTalon.Docs.Extract).Answer($$$OK, .result)
		Do ..AssertFailure(answer, code, "a reason from the worker")
	}
	Kill result
	Set result = "timeout"
	Set answer = ##class(OcuTalon.Docs.Extract).Answer($SYSTEM.Status.Error(5001, "The work item Read did not finish within 1 seconds"), .result)
	Do ..AssertFailure(answer, "timed_out", "a timeout")
	Kill result
	Set answer = ##class(OcuTalon.Docs.Extract).Answer($SYSTEM.Status.Error(5001, "something else"), .result)
	Do ..AssertFailure(answer, "failed", "another error")
	Do $$$AssertEquals(answer.detail, "ERROR #5001: something else", "with the status text as the detail")
	Kill result
	Set result("ok") = 0, result("reason") = "no_such_reason"
	Set answer = ##class(OcuTalon.Docs.Extract).Answer($$$OK, .result)
	Do ..AssertFailure(answer, "failed", "a reason that is not one of the codes")
}

Method TestDetailHoldsNoSecret()
{
	If '..OnImage() Quit
	Set sc = ##class(OcuTalon.Docs.Extractor).Submit("Read", 60, .result, "/no/such/file.pdf", 1000, 1000, "## {n}")
	Set answer = ##class(OcuTalon.Docs.Extract).Answer(sc, .result)
	Do ##class(OcuTalon.Test.Memory.Install).Secrets(.secrets)
	Do $$$AssertTrue($Data(secrets) > 0, "the environment of the process is read")
	Do $$$AssertEquals(##class(OcuTalon.Test.Memory.Install).Leaks(answer.detail, .secrets), "", "the detail of a failed read prints no key, token or variable value")
}

}
