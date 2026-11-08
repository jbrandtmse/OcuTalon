/// More tests of OcuTalon.Docs.Extract and the worker behind it (Story 19.7; AD-6, AD-21): the four extraction gaps that Story 19.6 left (DW-827, DW-828, DW-831,
/// DW-832) and the packages of the image (AC4). They read generated samples (OcuTalon.Test.Docs.Samples) through the real pdfplumber and python-docx, so they run
/// only on OcuTalon's Docker image (a throwaway stack or CI) and record one named skip elsewhere. Every read is checked for what it leaves behind: the extraction
/// folder holds the same files after it as before.
///   - TestEscapedLines (DW-832): a line of a file's own text that starts with two number signs and a space (a PDF page line, a Word paragraph, a table row, a content
///     control) is written with a backslash in front, so the page marker and the Heading 1 lines are the only section lines, and the splitter reads the line as text;
///   - TestContentControls (DW-831): the text of body-level and inline content controls and of a nested table is read once, in document order, a text box is not
///     read, and a file of content controls alone is read (not no_text), and the words of a hyperlink, and of a tracked insertion, a simple field, a smart tag
///     and custom XML (DW-926, not those of a tracked deletion) are read in a paragraph and in a cell;
///   - TestBombStops (DW-828): a Flate stream that inflates past MAXUNPACKED is contents_too_large within 15 seconds, and the same worker reads the next file;
///   - TestBoundedDecoders (DW-828): in the worker, pdfminer's own stream decoding with the bounded decoders installed reads LZW, RunLength, CCITT fax and Flate
///     data as pdfminer does, refuses each past its budget, counts a Flate stream without its Adler-32 once, asks zlib for nothing more once the budget is passed
///     (also when the first refusal was swallowed), and leaves pdfminer's own decoders in place afterwards;
///   - TestFlateStreams (DW-828): a PDF whose content stream is Flate data is read through the bounded stand-in for zlib, whole and without its Adler-32
///     (pdfminer's fallback for corrupted data);
///   - TestWorkerEscape (DW-832): in the worker, a line that is NUL and then two number signs and a space is escaped once the NUL is gone;
///   - TestOneReadAtATime (DW-827): a real read keeps the extraction lock while the worker reads its file; a read that meets a held extraction lock does not run:
///     it neither ends nor writes a file while another job holds the lock, it answers once that job lets go, and a read that cannot get the lock within its time
///     answers timed_out in about that time and writes no file; two real reads started together are both answered;
///   - TestTimeLeft (DW-827): the worker gets only the seconds of the timeout that the wait for the lock left, so a read that would finish within the whole
///     timeout but not within what is left answers timed_out;
///   - TestImagePackages (AC4): a work item in the Extractor reports the versions, the distribution versions and the folders of the pdfplumber and python-docx
///     modules that it imports, which the image pins.
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
	Set answer = ..ReadSample($ClassMethod(..#SAMPLES, "DocxTracked"), "docx")
	Do $$$AssertEquals(answer.ok, 1, "a Word file with a tracked insertion and deletion, a simple field, a smart tag and custom XML is read")
	Do $$$AssertEquals(answer.text, $ClassMethod(..#SAMPLES, "ExpectedDocxTracked"), "with the inserted, field, smart tag and custom XML words and without the deleted word, in the paragraph and in the cell")
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

/// The job that reads a PDF of the given number of dense pages (40 take about 3 seconds) and records when it began (before the read) and ended.
ClassMethod BackgroundRead(key As %String, pages As %Integer = 40)
{
	Try {
		Set stream = $ClassMethod(..#SAMPLES, "PdfPages", pages)
		Set ^OcuTalonTest("ExtractMore", key, "start") = $ZHorolog
		Set answer = $ClassMethod(..#EXTRACT, "Read", stream, "pdf", 100)
		Set ^OcuTalonTest("ExtractMore", key, "ok") = answer.ok
	} Catch {
		Set ^OcuTalonTest("ExtractMore", key, "ok") = "error"
	}
	Set ^OcuTalonTest("ExtractMore", key, "end") = $ZHorolog
}

/// The job that takes the extraction lock and holds it until the node release is set (or the seconds have passed).
ClassMethod HoldLock(key As %String, seconds As %Integer = 30)
{
	Lock +^OcuTalon.Docs.Extract:10
	Set ^OcuTalonTest("ExtractMore", key, "held") = $Test
	Set deadline = $ZHorolog + seconds
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
	Kill ^OcuTalonTest("ExtractMore", "one"), ^OcuTalonTest("ExtractMore", "hold"), ^OcuTalonTest("ExtractMore", "wait")
	Set files = ##class(OcuTalon.Test.Docs.Extract).Files()
	Job ##class(OcuTalon.Test.Docs.ExtractMore).BackgroundRead("one", 40)
	Set first = $ZChild
	Do $$$AssertTrue(first > 0, "a job reads a PDF of 40 pages")
	Set deadline = $ZHorolog + 30
	While '$Data(^$LOCK("^OcuTalon.Docs.Extract")) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Do $$$AssertTrue($Data(^$LOCK("^OcuTalon.Docs.Extract")) > 0, "and holds the extraction lock")
	Set deadline = $ZHorolog + 30
	While (##class(OcuTalon.Test.Docs.Extract).Files() = files) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Do $$$AssertTrue(##class(OcuTalon.Test.Docs.Extract).Files() '= files, "it writes its file for the worker")
	Do $$$AssertEquals($Get(^$LOCK("^OcuTalon.Docs.Extract", "OWNER")), first, "and keeps the lock while the worker reads the file")
	Set answer = $ClassMethod(..#EXTRACT, "Read", $ClassMethod(..#SAMPLES, "Pdf3"), "pdf", 100)
	Do $$$AssertEquals(answer.ok, 1, "meanwhile the test reads the 3-page PDF and is answered")
	Do $$$AssertTrue(..WaitNode("one", "end"), "the background read ended")
	Do $$$AssertEquals($Get(^OcuTalonTest("ExtractMore", "one", "ok")), 1, "and was answered")
	Do $$$AssertTrue(..WaitEnd(first), "the background job ended")
	Do $$$AssertEquals($Data(^$LOCK("^OcuTalon.Docs.Extract")), 0, "and the lock is free")
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.Extract).Files(), files, "and neither read left a file in the extraction folder")
	Job ##class(OcuTalon.Test.Docs.ExtractMore).HoldLock("hold")
	Set holder = $ZChild
	Do $$$AssertTrue(..WaitNode("hold", "held") && $Get(^OcuTalonTest("ExtractMore", "hold", "held")), "a job holds the extraction lock")
	Job ##class(OcuTalon.Test.Docs.ExtractMore).BackgroundRead("wait", 3)
	Set waiter = $ZChild
	Do $$$AssertTrue(..WaitNode("wait", "start"), "another job begins to read a PDF of 3 pages")
	Hang 2
	Do $$$AssertEquals($Data(^OcuTalonTest("ExtractMore", "wait", "end")), 0, "the other job's read has not ended 2 seconds on, while the holder keeps the lock")
	Do $$$AssertEquals($Get(^$LOCK("^OcuTalon.Docs.Extract", "OWNER")), holder, "and the lock is the holder's")
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.Extract).Files(), files, "and it has written no file")
	Set began = $ZHorolog
	Set answer = ..ReadSample($ClassMethod(..#SAMPLES, "Pdf3"), "pdf", 2)
	Set elapsed = $ZHorolog - began
	Do $$$AssertEquals(answer.ok _ "|" _ answer.reason, "0|timed_out", "a read that cannot get the lock within 2 seconds is timed_out")
	Do $$$AssertTrue((elapsed > 1.5) && (elapsed < 6), "after about 2 seconds (" _ $FNumber(elapsed, "", 2) _ ")")
	Do $$$AssertEquals(answer.%IsDefined("job"), 0, "without a worker")
	Do $$$AssertEquals($Data(^OcuTalonTest("ExtractMore", "wait", "end")), 0, "and the other job's read is still waiting")
	Set released = $ZHorolog
	Set ^OcuTalonTest("ExtractMore", "hold", "release") = 1
	Do $$$AssertTrue(..WaitNode("wait", "end", 60), "after the holder lets go the other job's read ends")
	Do $$$AssertEquals($Get(^OcuTalonTest("ExtractMore", "wait", "ok")), 1, "and is answered")
	Do $$$AssertTrue($Get(^OcuTalonTest("ExtractMore", "wait", "end")) > released, "after the release, which it could not run before")
	Do $$$AssertTrue(..WaitEnd(holder), "the holding job ended")
	Do $$$AssertTrue(..WaitEnd(waiter), "and the reading job ended")
	Do $$$AssertEquals($Data(^$LOCK("^OcuTalon.Docs.Extract")), 0, "and the lock is free again")
	Do $$$AssertEquals(##class(OcuTalon.Test.Docs.Extract).Files(), files, "and no read left a file in the extraction folder")
	Set answer = ..ReadSample($ClassMethod(..#SAMPLES, "Pdf3"), "pdf")
	Do $$$AssertEquals(answer.ok, 1, "a read after it is answered")
	Kill ^OcuTalonTest("ExtractMore", "one"), ^OcuTalonTest("ExtractMore", "hold"), ^OcuTalonTest("ExtractMore", "wait")
}

Method TestTimeLeft()
{
	If '..OnImage() Quit
	Kill ^OcuTalonTest("ExtractMore", "left")
	Set files = ##class(OcuTalon.Test.Docs.Extract).Files()
	Set stream = $ClassMethod(..#SAMPLES, "PdfPages", 40)
	Job ##class(OcuTalon.Test.Docs.ExtractMore).HoldLock("left", 5)
	Set holder = $ZChild
	Do $$$AssertTrue(..WaitNode("left", "held") && $Get(^OcuTalonTest("ExtractMore", "left", "held")), "a job holds the extraction lock for 5 seconds")
	Set began = $ZHorolog
	Set answer = ..ReadSample(stream, "pdf", 6)
	Set elapsed = $ZHorolog - began
	Do $$$AssertEquals(answer.ok _ "|" _ answer.reason, "0|timed_out", "a read of 40 pages (about 3 seconds) with a timeout of 6 seconds, about 5 of them spent waiting for the lock, is timed_out")
	Do $$$AssertTrue((elapsed > 4) && (elapsed < 15), "after the wait for the lock and the second that was left (" _ $FNumber(elapsed, "", 2) _ ")")
	Do $$$AssertTrue(..WaitEnd(holder), "the holding job ended")
	Do $$$AssertEquals($Data(^$LOCK("^OcuTalon.Docs.Extract")), 0, "and the lock is free")
	Set answer = ..ReadSample($ClassMethod(..#SAMPLES, "Pdf3"), "pdf")
	Do $$$AssertEquals(answer.ok, 1, "a read after it is answered")
	Kill ^OcuTalonTest("ExtractMore", "left")
}

/// The Python that TestBoundedDecoders runs in the worker: it sets result to the outcomes, joined by a vertical bar.
XData DecoderProbe [ MimeType = text/x-python ]
{
import zlib
import ocutalon_extract as m
import pdfminer.pdftypes as t
from pdfminer.psparser import LIT
from pdfminer.lzw import lzwdecode
from pdfminer.runlength import rldecode
from pdfminer.ccitt import ccittfaxdecode

def data(f, raw, parms=None):
    attrs = {"Filter": LIT(f)}
    if parms:
        attrs["DecodeParms"] = parms
    return t.PDFStream(attrs, raw).get_data()

def bounded(f, raw, budget, parms=None):
    with m._bounded_decoding(t, budget):
        try:
            data(f, raw, parms)
            return "read"
        except m._TooLarge:
            return "too_large"

def check(step):
    try:
        return step()
    except Exception as error:
        return "error " + type(error).__name__

def read_all():
    with m._bounded_decoding(t, 1000):
        return all((data("LZWDecode", lzw) == lzwdecode(lzw), data("RunLengthDecode", rl) == rldecode(rl),
                    data("CCITTFaxDecode", fax, parms) == ccittfaxdecode(fax, parms), data("FlateDecode", zlib.compress(b"C" * 100)) == b"C" * 100))

def truncated():
    with m._bounded_decoding(t, 150):
        return data("FlateDecode", zlib.compress(b"D" * 100)[:-4]) == b"D" * 100

def swallowed():
    with m._bounded_decoding(t, 50) as budget:
        for raw in (zlib.compress(b"A" * 100), zlib.compress(b"B" * 1000000)):
            try:
                data("FlateDecode", raw)
            except m._TooLarge:
                pass
        return budget.left

lzw = bytes.fromhex("800b6050220c0c8501")
rl = bytes([2]) + b"abc" + bytes([253]) + b"x" + bytes([128])
fax = b"\xff" * 4
parms = {"K": -1, "Columns": 8}
out = [check(read_all)]
out.append(check(lambda: bounded("LZWDecode", lzw, 9)))
out.append(check(lambda: bounded("RunLengthDecode", rl, 6)))
out.append(check(lambda: bounded("CCITTFaxDecode", fax, 31, parms)))
out.append(check(truncated))
out.append(check(swallowed))
out.append(all(getattr(t, n) is v for n, v in (("zlib", zlib), ("lzwdecode", lzwdecode), ("rldecode", rldecode), ("ccittfaxdecode", ccittfaxdecode))))
result = "|".join(str(x) for x in out)
}

/// The work item that runs DecoderProbe.
ClassMethod Decoders() As %Status
{
	Kill %result
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($ClassName() _ "||DecoderProbe")
		Set code = ""
		While 'xdata.Data.AtEnd {
			Set code = code _ xdata.Data.ReadLine() _ $Char(10)
		}
		Set builtins = ##class(%SYS.Python).Builtins()
		Set scope = builtins.dict()
		Do builtins.exec(code, scope)
		Set %result("decoders") = scope."__getitem__"("result")
	} Catch exception {
		Kill %result
		Set sc = exception.AsStatus()
	}
	Quit sc
}

Method TestBoundedDecoders()
{
	If '..OnImage() Quit
	Set sc = ##class(OcuTalon.Docs.Extractor).Submit("##class(" _ $ClassName() _ ").Decoders", 60, .result)
	Do $$$AssertStatusOK(sc, "a work item in the Extractor decodes streams through pdfminer with the bounded decoders")
	Set got = $Get(result("decoders"))
	Do $$$AssertEquals($Piece(got, "|", 1), "True", "LZW, RunLength, CCITT fax and Flate data decode as pdfminer decodes them: " _ got)
	Do $$$AssertEquals($Piece(got, "|", 2), "too_large", "LZW data that decode past the budget are refused")
	Do $$$AssertEquals($Piece(got, "|", 3), "too_large", "so are RunLength data")
	Do $$$AssertEquals($Piece(got, "|", 4), "too_large", "and CCITT fax data")
	Do $$$AssertEquals($Piece(got, "|", 5), "True", "a Flate stream without its Adler-32 that fits the budget is read, counted once although pdfminer reads it twice")
	Do $$$AssertEquals($Piece(got, "|", 6), "-1", "once the budget is passed and the refusal swallowed, the next Flate stream asks zlib for nothing")
	Do $$$AssertEquals($Piece(got, "|", 7), "True", "pdfminer's own decoders are back after the read")
}

/// The work item that reports the versions and the folders of the two distributions.
ClassMethod Packages() As %Status
{
	Kill %result
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set plumber = ##class(%SYS.Python).Import("pdfplumber")
		Set docx = ##class(%SYS.Python).Import("docx")
		Set metadata = ##class(%SYS.Python).Import("importlib.metadata")
		Set %result("pdfplumberDist") = metadata.version("pdfplumber")
		Set %result("docxDist") = metadata.version("python-docx")
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
	Do $$$AssertEquals($Get(result("pdfplumberDist")), ..#PDFPLUMBER, "the installed distribution pdfplumber is the pinned version")
	Do $$$AssertEquals($Get(result("docxDist")), ..#PYTHONDOCX, "the installed distribution python-docx is the pinned version")
	Do $$$AssertEquals($Extract($Get(result("pdfplumberFile")), 1, $Length(folder)), folder, "pdfplumber is imported from the image's python folder: " _ $Get(result("pdfplumberFile")))
	Do $$$AssertEquals($Extract($Get(result("docxFile")), 1, $Length(folder)), folder, "python-docx is imported from the image's python folder: " _ $Get(result("docxFile")))
}

}
