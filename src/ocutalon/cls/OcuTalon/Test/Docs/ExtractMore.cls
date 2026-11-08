/// More tests of OcuTalon.Docs.Extract and the worker behind it (Story 19.7; AD-6, AD-21): the four extraction gaps that Story 19.6 left (DW-827, DW-828, DW-831,
/// DW-832) and the packages of the image (AC4). They read generated samples (OcuTalon.Test.Docs.Samples) through the real pdfplumber and python-docx, so they run
/// only on OcuTalon's Docker image (a throwaway stack or CI) and record one named skip elsewhere. Every read is checked for what it leaves behind: the extraction
/// folder holds the same files after it as before.
///   - TestEscapedLines (DW-832): a line of a file's own text that starts with two number signs and a space (a PDF page line, a Word paragraph, a table row, a content
///     control) is written with a backslash in front, so the page marker and the Heading 1 lines are the only section lines, and the splitter reads the line as text;
///   - TestContentControls (DW-831): the text of body-level and inline content controls and of a nested table is read once, in document order, a text box is not
///     read, and a file of content controls alone is read (not no_text), and the words of a hyperlink are read in a paragraph and in a cell;
///   - TestBombStops (DW-828): a Flate stream that inflates past MAXUNPACKED is contents_too_large within 15 seconds, and the same worker reads the next file;
///   - TestFlateStreams (DW-828): a PDF whose content stream is Flate data is read through the bounded stand-in for zlib, whole and without its Adler-32
///     (pdfminer's fallback for corrupted data);
///   - TestWorkerEscape (DW-832): in the worker, a line that is NUL and then two number signs and a space is escaped once the NUL is gone;
///   - TestOneReadAtATime (DW-827): a read waits for the read that holds the extraction lock and then runs on the same worker, and a read that cannot get the lock
///     within its time answers timed_out in about that time and writes no file;
///   - TestImagePackages (AC4): a work item in the Extractor reports the versions and the folders of pdfplumber and python-docx that the image pins.
/// Each test removes its jobs' nodes (^OcuTalonTest("ExtractMore")) and waits for its jobs to end.
Class OcuTalon.Test.Docs.ExtractMore Extends %UnitTest.TestCase
{

Parameter CATEGORY = "OcuTalon.Docs.Extractor";

Parameter SAMPLES = "OcuTalon.Test.Docs.Samples";

Parameter EXTRACT = "OcuTalon.Docs.Extract";

/// The distributions that the image pins (Story 34.2).
Parameter PDFPLUMBER = "0.11.10";

Parameter PYTHONDOCX = "1.1.2";

Method OnBeforeAllTests() As %Status
{
	Kill ^OcuTalonTest("ExtractMore")
	Kill ^||OcuTalonTestDocsMore
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit $$$OK
	If '##class(OcuTalon.Test.Memory.Fixture).CategoryExists(..#CATEGORY) {
		Set sc = ##class(OcuTalon.Install.Step.Memory).EnsureCategory(..#CATEGORY, ##class(OcuTalon.Docs.Extractor).#MAXACTIVEWORKERS, ##class(OcuTalon.Docs.Extractor).#DEFAULTWORKERS)
		If $SYSTEM.Status.IsError(sc) Quit sc
		Set ^||OcuTalonTestDocsMore("category") = 1
	}
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("ExtractMore")
	If $Get(^||OcuTalonTestDocsMore("category")) {
		New $Namespace
		Set $Namespace = "%SYS"
		Do ##class(Config.WorkQueues).Delete(..#CATEGORY)
	}
	Kill ^||OcuTalonTestDocsMore
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
	Set answer = $ClassMethod(..#EXTRACT, "Read", stream, type, timeout)
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.Extract).Files(), before, "the read leaves no file in the extraction folder")
	Quit answer
}

Method TestEscapedLines()
{
	If '..OnImage() Quit
	Set answer = ..ReadSample($ClassMethod(..#SAMPLES, "PdfHashLine"), "pdf")
	Do $$$AssertEquals(answer.ok, 1, "a PDF with a page line that starts with two number signs and a space is read")
	Do $$$AssertEquals(answer.text, $ClassMethod(..#SAMPLES, "ExpectedPdfHashLine"), "the line is written with a backslash in front; the page marker is the only section line")
	Set escaped = $Char(10) _ "\## Not a heading" _ $Char(10)
	Do $$$AssertTrue(answer.text [ escaped, "the line is literally \## Not a heading")
	Do $ClassMethod("OcuTalon.Docs.Passages", "Split", answer.text, "pdf", .passages)
	Do $$$AssertTrue(passages.%Size() > 0, "the splitter finds a passage in it")
	If passages.%Size() = 0 Quit
	Do $$$AssertEquals(passages.%Size() _ "|" _ passages.%Get(0).section, "1|Page 1", "the splitter finds one section, Page 1, and none named Not a heading")
	Do $$$AssertEquals(passages.%Get(0).text, "Intro line" _ $Char(10) _ "## Not a heading" _ $Char(10) _ "Last line", "and the passage holds the line without its backslash")
	Set answer = ..ReadSample($ClassMethod(..#SAMPLES, "DocxHashLine"), "docx")
	Do $$$AssertEquals(answer.ok, 1, "a Word file with such lines in a paragraph, a table row and a content control is read")
	Do $$$AssertEquals(answer.text, $ClassMethod(..#SAMPLES, "ExpectedDocxHashLine"), "each is written with a backslash in front; the Heading 1 line is the only section line")
	Do $ClassMethod("OcuTalon.Docs.Passages", "Split", answer.text, "docx", .passages)
	Do $$$AssertTrue(passages.%Size() > 0, "the splitter finds a passage in it")
	If passages.%Size() = 0 Quit
	Do $$$AssertEquals(passages.%Size() _ "|" _ passages.%Get(0).section, "1|Real section", "the splitter finds one section, Real section")
	Do $$$AssertEquals(passages.%Get(0).text, "## Not a heading" _ $Char(10, 10) _ "## Cell line | x" _ $Char(10, 10) _ "## In a control", "and the passage holds the lines without their backslashes")
}

Method TestContentControls()
{
	If '..OnImage() Quit
	Set answer = ..ReadSample($ClassMethod(..#SAMPLES, "DocxContentControls"), "docx")
	Do $$$AssertEquals(answer.ok, 1, "a Word file with content controls, a nested table and a text box is read")
	Do $$$AssertEquals(answer.text, $ClassMethod(..#SAMPLES, "ExpectedDocxContentControls"), "each text once, in document order, the nested table inside the outer cell, no text box")
	Do $$$AssertTrue(answer.text '[ "Box text", "the text of the text box is not read")
	Set answer = ..ReadSample($ClassMethod(..#SAMPLES, "DocxOnlyControls"), "docx")
	Do $$$AssertEquals(answer.ok _ "|" _ answer.%Get("reason"), "1|", "a Word file made only of content controls is read, not no_text")
	Do $$$AssertEquals(answer.text, $ClassMethod(..#SAMPLES, "ExpectedDocxOnlyControls"), "with their text")
	Set answer = ..ReadSample($ClassMethod(..#SAMPLES, "DocxHyperlinks"), "docx")
	Do $$$AssertEquals(answer.ok, 1, "a Word file with a hyperlink in a paragraph and in a table cell is read")
	Do $$$AssertEquals(answer.text, $ClassMethod(..#SAMPLES, "ExpectedDocxHyperlinks"), "with the hyperlink's words in both")
}

Method TestBombStops()
{
	If '..OnImage() Quit
	Set start = $ZHorolog
	Set answer = ..ReadSample($ClassMethod(..#SAMPLES, "PdfBomb"), "pdf")
	Set elapsed = $ZHorolog - start
	Do $$$AssertEquals(answer.ok _ "|" _ answer.reason, "0|contents_too_large", "a Flate stream that inflates past MAXUNPACKED is contents_too_large")
	Do $$$AssertTrue(elapsed < 15, "within 15 seconds (" _ $FNumber(elapsed, "", 2) _ ")")
	Set again = ..ReadSample($ClassMethod(..#SAMPLES, "PdfFlate"), "pdf")
	Do $$$AssertEquals(again.ok, 1, "the next read, of a PDF with a Flate stream, is answered")
	Do $$$AssertEquals(again.text, $ClassMethod(..#SAMPLES, "ExpectedPdfFlate"), "with its text")
	Do $$$AssertEquals(again.job, answer.job, "by the worker that refused the bomb, which was not stopped")
}

Method TestFlateStreams()
{
	If '..OnImage() Quit
	Set expected = $ClassMethod(..#SAMPLES, "ExpectedPdfFlate")
	Set answer = ..ReadSample($ClassMethod(..#SAMPLES, "PdfFlate"), "pdf")
	Do $$$AssertEquals(answer.ok, 1, "a PDF whose content stream is Flate data is read")
	Do $$$AssertEquals(answer.text, expected, "with its text")
	Set answer = ..ReadSample($ClassMethod(..#SAMPLES, "PdfFlateTruncated"), "pdf")
	Do $$$AssertEquals(answer.ok, 1, "so is one whose Flate data lacks its Adler-32 (read through the fallback for corrupted data)")
	Do $$$AssertEquals(answer.text, expected, "with the same text")
}

/// The job that reads a PDF of 40 dense pages (about 3 seconds) and records when it began and ended.
ClassMethod BackgroundRead(key As %String)
{
	Try {
		Set stream = $ClassMethod(..#SAMPLES, "PdfPages", 40)
		Set ^OcuTalonTest("ExtractMore", key, "start") = $ZHorolog
		Set answer = $ClassMethod(..#EXTRACT, "Read", stream, "pdf", 100)
		Set ^OcuTalonTest("ExtractMore", key, "ok") = answer.ok
	} Catch {
		Set ^OcuTalonTest("ExtractMore", key, "ok") = "error"
	}
	Set ^OcuTalonTest("ExtractMore", key, "end") = $ZHorolog
}

/// The job that takes the extraction lock and holds it until the node release is set (or 30 seconds).
ClassMethod HoldLock(key As %String)
{
	Lock +^OcuTalon.Docs.Extract:10
	Set ^OcuTalonTest("ExtractMore", key, "held") = $Test
	Set deadline = $ZHorolog + 30
	While '$Get(^OcuTalonTest("ExtractMore", key, "release")) && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Lock -^OcuTalon.Docs.Extract
	Set ^OcuTalonTest("ExtractMore", key, "end") = $ZHorolog
}

/// Waits up to seconds for the node to be set.
ClassMethod WaitNode(key As %String, node As %String, seconds As %Integer = 30) As %Boolean
{
	Set deadline = $ZHorolog + seconds
	While '$Data(^OcuTalonTest("ExtractMore", key, node)) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Quit $Data(^OcuTalonTest("ExtractMore", key, node)) > 0
}

/// Waits up to seconds for the job to end; 1 when it has.
ClassMethod WaitEnd(job As %Integer, seconds As %Integer = 60) As %Boolean
{
	Set deadline = $ZHorolog + seconds
	While $Data(^$JOB(job)) && ($ZHorolog < deadline) {
		Hang 0.2
	}
	Quit '$Data(^$JOB(job))
}

Method TestOneReadAtATime()
{
	If '..OnImage() Quit
	Kill ^OcuTalonTest("ExtractMore", "one"), ^OcuTalonTest("ExtractMore", "hold")
	Set files = ##class(OcuTalon.Test.Docs.Extract).Files()
	Job ##class(OcuTalon.Test.Docs.ExtractMore).BackgroundRead("one")
	Set first = $ZChild
	Do $$$AssertTrue(first > 0, "a job reads a PDF of 40 pages")
	Set deadline = $ZHorolog + 30
	While '$Data(^$LOCK("^OcuTalon.Docs.Extract")) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Do $$$AssertTrue($Data(^$LOCK("^OcuTalon.Docs.Extract")) > 0, "and holds the extraction lock")
	Set began = $ZHorolog
	Set answer = $ClassMethod(..#EXTRACT, "Read", $ClassMethod(..#SAMPLES, "Pdf3"), "pdf", 100)
	Set ended = $ZHorolog
	Do $$$AssertEquals(answer.ok, 1, "meanwhile the test reads the 3-page PDF")
	Do ..WaitNode("one", "end")
	Do $$$AssertEquals($Get(^OcuTalonTest("ExtractMore", "one", "ok")), 1, "the background read succeeded")
	Do $$$AssertTrue(began < $Get(^OcuTalonTest("ExtractMore", "one", "end")), "the test's read began before the background read ended")
	Do $$$AssertTrue(ended > $Get(^OcuTalonTest("ExtractMore", "one", "end")), "and ended after it: the two reads did not run together")
	Do $$$AssertTrue(..WaitEnd(first), "the background job ended")
	Do $$$AssertEquals($Data(^$LOCK("^OcuTalon.Docs.Extract")), 0, "and the lock is free")
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.Extract).Files(), files, "and neither read left a file in the extraction folder")
	Job ##class(OcuTalon.Test.Docs.ExtractMore).HoldLock("hold")
	Set second = $ZChild
	Do $$$AssertTrue(..WaitNode("hold", "held") && $Get(^OcuTalonTest("ExtractMore", "hold", "held")), "a job holds the extraction lock")
	Set began = $ZHorolog
	Set answer = ..ReadSample($ClassMethod(..#SAMPLES, "Pdf3"), "pdf", 2)
	Set elapsed = $ZHorolog - began
	Do $$$AssertEquals(answer.ok _ "|" _ answer.reason, "0|timed_out", "a read that cannot get the lock within 2 seconds is timed_out")
	Do $$$AssertTrue((elapsed > 1.5) && (elapsed < 6), "after about 2 seconds (" _ $FNumber(elapsed, "", 2) _ ")")
	Do $$$AssertEquals(answer.%IsDefined("job"), 0, "without a worker")
	Set ^OcuTalonTest("ExtractMore", "hold", "release") = 1
	Do $$$AssertTrue(..WaitEnd(second), "the holding job ended")
	Do $$$AssertEquals($Data(^$LOCK("^OcuTalon.Docs.Extract")), 0, "and the lock is free again")
	Set answer = ..ReadSample($ClassMethod(..#SAMPLES, "Pdf3"), "pdf")
	Do $$$AssertEquals(answer.ok, 1, "a read after it is answered")
	Kill ^OcuTalonTest("ExtractMore", "one"), ^OcuTalonTest("ExtractMore", "hold")
}

/// The work item that reports the versions and the folders of the two distributions.
ClassMethod Packages() As %Status
{
	Kill %result
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set plumber = ##class(%SYS.Python).Import("pdfplumber")
		Set docx = ##class(%SYS.Python).Import("docx")
		Set %result("pdfplumber") = plumber."__version__"
		Set %result("pdfplumberFile") = plumber."__file__"
		Set %result("docx") = docx."__version__"
		Set %result("docxFile") = docx."__file__"
	} Catch exception {
		Kill %result
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The work item that runs the escape of the extraction module on a line that is NUL and then two number signs and a space.
ClassMethod Escape() As %Status
{
	Kill %result
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set module = ##class(%SYS.Python).Import("ocutalon_extract")
		Set %result("escaped") = module."_escape"($Char(0) _ "## Own line" _ $Char(10) _ "plain")
	} Catch exception {
		Kill %result
		Set sc = exception.AsStatus()
	}
	Quit sc
}

Method TestWorkerEscape()
{
	If '..OnImage() Quit
	Set sc = ##class(OcuTalon.Docs.Extractor).Submit("##class(" _ $ClassName() _ ").Escape", 60, .result)
	Do $$$AssertStatusOK(sc, "a work item in the Extractor escapes a line")
	Do $$$AssertEquals($Get(result("escaped")), "\## Own line" _ $Char(10) _ "plain", "a NUL in front of two number signs and a space does not keep the line from being escaped")
}

Method TestImagePackages()
{
	If '..OnImage() Quit
	Set sc = ##class(OcuTalon.Docs.Extractor).Submit("##class(" _ $ClassName() _ ").Packages", 60, .result)
	Do $$$AssertStatusOK(sc, "a work item in the Extractor imports the two packages")
	Set folder = $SYSTEM.Util.InstallDirectory() _ "mgr/python/"
	Do $$$AssertEquals($Get(result("pdfplumber")), ..#PDFPLUMBER, "pdfplumber is the pinned version")
	Do $$$AssertEquals($Get(result("docx")), ..#PYTHONDOCX, "python-docx is the pinned version")
	Do $$$AssertEquals($Extract($Get(result("pdfplumberFile")), 1, $Length(folder)), folder, "pdfplumber is imported from the image's python folder: " _ $Get(result("pdfplumberFile")))
	Do $$$AssertEquals($Extract($Get(result("docxFile")), 1, $Length(folder)), folder, "python-docx is imported from the image's python folder: " _ $Get(result("docxFile")))
}

}
