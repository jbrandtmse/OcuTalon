/// The text of a PDF or Word (.docx) file (AD-21, "PDF and Word"): the caller side of the extraction service. This class holds no Python and no %AI
/// reference, so it may be called from anywhere, inside a tool's turn included (it is among the callback helpers that Test.Bridge.CodeRules scans). The
/// reading is done by OcuTalon.Docs.Extractor, a worker of its own category (AD-6).
///   - Read(content, contentType, timeout) returns a dynamic object and never throws. It stores nothing: it writes the bytes to a private temporary file
///     below the temp directory's ocutalon-extract folder, queues one work item, and deletes the file before it returns, whatever happened. A file of that
///     folder older than MAXAGE is deleted when a call is about to write a file (a call that answers from the type or the size alone writes none).
///   - A text answer is {ok:1, text, cut, markers, job}: markers is page for a PDF, heading for a .docx with headings, none otherwise; the text holds PAGEMARKER
///     lines (PDF) or Markdown heading lines (.docx); a text over MAXTEXT characters is cut at a line break and followed by a blank line and CUTNOTE (cut:1).
///   - A failure is {ok:0, reason, detail?}. reason is one of CODES, fixed and independent of the wording; detail is for the operator only and never for a user.
///     Reason(code, size) is the plain reason, REASON<CODE> without the underscores (too_large with a known size: REASONTOOLARGESIZE), and
///     Failure(code, size) puts it in FAILUREFRAME.
///   - The type and the size are checked first, with no worker and no file: wrong_type, too_large (over MAXBYTES) and damaged (no bytes).
///   - One read at a time on the instance (DW-827): the category has one worker, but two simultaneous callers would get two worker jobs, so a read takes the
///     lock ^OcuTalon.Docs.Extract after the type and size checks and before it writes its file, and releases it on every path. The wait for the lock counts
///     within timeout: a lock not got in time answers timed_out with no file and no worker, and the work item gets the seconds that are left (at least 1).
///   - Answer(sc, .result) maps a work item's status and result to the answer, so that every branch is testable without a worker.
Class OcuTalon.Docs.Extract
{

/// The most bytes of an input file; pinned equal to the web upload limit (Web.Documents FILEMAX) by a test, never read from it here.
Parameter MAXBYTES = 10485760;

/// The most characters of text before the cut note.
Parameter MAXTEXT = 200000;

/// The most bytes a .docx may declare unpacked in all its zip entries.
Parameter MAXUNPACKED = 104857600;

/// Seconds that a caller waits for the worker.
Parameter TIMEOUT = 120;

/// The temporary folder (below the temp directory) and the age in seconds from which a leftover file in it is deleted.
Parameter FOLDER = "ocutalon-extract";

Parameter MAXAGE = 3600;

/// The content types that are read, and the machine reason codes.
Parameter TYPES = "pdf,docx";

Parameter CODES = "too_large,contents_too_large,wrong_type,encrypted,damaged,no_text,legacy_doc,timed_out,failed";

/// User-facing text (PUBLIC TEXT, the Contest Planner's ruling): the page marker line ({n} is the page number; it becomes a citation's section), the note
/// after a cut text, the sentence that frames a reason in a chat reply (UX-DR147) and the reasons. REASONTOOLARGESIZE and REASONWRONGTYPE are the web
/// app's catalog reasons byte for byte (they end with a period); REASONTOOLARGESIZE is used when the file's size is known, with {size} written as the
/// web app writes it (SizeText).
Parameter PAGEMARKER = "## Page {n}";

Parameter CUTNOTE = "[OcuTalon read only the first 200,000 characters of this file.]";

Parameter FAILUREFRAME = "I couldn't read that file: {reason}.";

Parameter REASONTOOLARGE = "it's over the 10 MB limit";

Parameter REASONTOOLARGESIZE = "that file is {size}; the limit is 10 MB.";

Parameter REASONCONTENTSTOOLARGE = "its text is too long to read";

Parameter REASONWRONGTYPE = "it isn't a Markdown, plain-text, PDF or Word (.docx) file.";

Parameter REASONENCRYPTED = "it's protected with a password";

Parameter REASONDAMAGED = "it's damaged or incomplete";

Parameter REASONNOTEXT = "it has no text to read, for example a scanned PDF without a text layer";

Parameter REASONLEGACYDOC = "it's an old Word file (.doc); save it as .docx and try again";

Parameter REASONTIMEDOUT = "reading it took too long";

Parameter REASONFAILED = "something went wrong while reading it";

ClassMethod Read(content As %Stream.Object, contentType As %String, timeout As %Integer = {..#TIMEOUT}) As %DynamicObject
{
	Set file = ""
	Set locked = 0
	Try {
		Set type = $ZConvert($Get(contentType), "L")
		Set size = $Select($IsObject($Get(content)): content.Size, 1: 0)
		If '$ListFind($ListFromString(..#TYPES, ","), type) {
			Set answer = ..Fail("wrong_type")
		} ElseIf size > ..#MAXBYTES {
			Set answer = ..Fail("too_large")
		} ElseIf size = 0 {
			Set answer = ..Fail("damaged")
		} Else {
			Set began = $ZHorolog
			Lock +^OcuTalon.Docs.Extract:timeout
			If '$Test {
				Set answer = ..Fail("timed_out", "Another read of a file held the extraction for " _ timeout _ " seconds")
			} Else {
				Set locked = 1
				Set left = timeout - ($ZHorolog - began)
				If left < 1 Set left = 1
				Do ..Purge()
				Set folder = ..Folder()
				If '##class(%File).DirectoryExists(folder) Do ##class(%File).CreateDirectoryChain(folder)
				Set file = folder _ $ZConvert($SYSTEM.Util.CreateGUID(), "L") _ "." _ type
				Set stream = ##class(%Stream.FileBinary).%New()
				Set sc = stream.LinkToFile(file)
				If $SYSTEM.Status.IsOK(sc) {
					Do content.Rewind()
					Set sc = stream.CopyFromAndSave(content)
				}
				Kill stream
				If $SYSTEM.Status.IsError(sc) {
					Set answer = ..Answer(sc, .result)
				} Else {
					Set sc = ##class(OcuTalon.Docs.Extractor).Submit("Read", left, .result, file, ..#MAXTEXT, ..#MAXUNPACKED, ..#PAGEMARKER)
					Set answer = ..Answer(sc, .result)
				}
			}
		}
	} Catch exception {
		Set answer = ..Fail("failed", exception.DisplayString())
	}
	If file '= "" Do ##class(%File).Delete(file)
	If locked Lock -^OcuTalon.Docs.Extract
	Quit answer
}

/// The answer for a work item's status and result (the %result nodes that Submit returns): a text, a reason from the worker, timed_out (Submit marks a
/// timeout by the word timeout in result) or failed with the status text as the detail.
ClassMethod Answer(sc As %Status, ByRef result) As %DynamicObject
{
	If $SYSTEM.Status.IsError(sc) {
		If $Get(result) = "timeout" Quit ..Fail("timed_out")
		Quit ..Fail("failed", $SYSTEM.Status.GetErrorText(sc))
	}
	If $Get(result("ok")) {
		Set text = $Get(result("text"))
		If $Get(result("cut")) Set text = text _ $Char(10, 10) _ ..#CUTNOTE
		Quit {"ok": 1, "text": (text), "cut": (+$Get(result("cut"))), "markers": ($Get(result("markers"))), "job": ($Get(result("job")))}
	}
	Set code = $Get(result("reason"))
	If '$ListFind($ListFromString(..#CODES, ","), code) Quit ..Fail("failed", "The worker answered no text and the reason '" _ code _ "'")
	Quit ..Fail(code, $Get(result("detail")), $Get(result("job")))
}

/// {ok:0, reason, detail, job}; detail and job only when they are not empty.
ClassMethod Fail(code As %String, detail As %String = "", job As %String = "") As %DynamicObject [ Private ]
{
	Set answer = {"ok": 0, "reason": (code)}
	If detail '= "" Set answer.detail = detail
	If job '= "" Set answer.job = job
	Quit answer
}

/// The plain reason for a code; an unknown code has the reason of failed. size is the file's size in bytes when the caller knows it: too_large then
/// names it (REASONTOOLARGESIZE), and without it too_large is REASONTOOLARGE.
ClassMethod Reason(code As %String, size As %Integer = "") As %String
{
	If '$ListFind($ListFromString(..#CODES, ","), code) Set code = "failed"
	If (code = "too_large") && (+size > 0) Quit $Replace(..#REASONTOOLARGESIZE, "{size}", ..SizeText(size))
	Quit $PARAMETER($ClassName(), "REASON" _ $ZConvert($Translate(code, "_"), "U"))
}

/// The sentence that tells the user why a file could not be read: FAILUREFRAME with the code's reason (size as in Reason). A reason that ends with a
/// period gives it up to the frame's own, so the sentence ends with one period.
ClassMethod Failure(code As %String, size As %Integer = "") As %String
{
	Set reason = ..Reason(code, size)
	If $Extract(reason, *) = "." Set reason = $Extract(reason, 1, *-1)
	Quit $Replace(..#FAILUREFRAME, "{reason}", reason)
}

/// A size in bytes as the web app's Documents page writes it: whole KB rounded up under 1 MB, otherwise MB with one decimal rounded up and no ".0"
/// (1 KB = 1,024 bytes and 1 MB = 1,048,576 bytes).
ClassMethod SizeText(bytes As %Integer) As %String
{
	Set bytes = $Select(+bytes > 0: bytes \ 1, 1: 0)
	If bytes < 1048576 Quit ((bytes + 1023) \ 1024) _ " KB"
	Set tenths = (bytes * 10 + 1048575) \ 1048576
	Quit (tenths \ 10) _ $Select(tenths # 10 = 0: "", 1: "." _ (tenths # 10)) _ " MB"
}

/// The temporary folder of the files that are being read (with a closing slash).
ClassMethod Folder() As %String
{
	Quit ##class(%File).NormalizeDirectory(##class(%SYS.System).TempDirectory() _ "/" _ ..#FOLDER)
}

/// Deletes the files of the folder that were last changed more than MAXAGE seconds ago (left by a call that did not end). Never throws.
ClassMethod Purge()
{
	Try {
		Set folder = ..Folder()
		Set now = ..Seconds($Horolog)
		Set old = ""
		Set name = $ZSearch(folder _ "*")
		While name '= "" {
			If now - ..Seconds(##class(%File).GetFileDateModified(name)) > ..#MAXAGE Set old = old _ $ListBuild(name)
			Set name = $ZSearch("")
		}
		Set position = 0
		While $ListNext(old, position, name) {
			If '##class(%File).DirectoryExists(name) Do ##class(%File).Delete(name)
		}
	} Catch {
	}
}

/// A $HOROLOG value as seconds.
ClassMethod Seconds(horolog As %String) As %Integer [ CodeMode = expression, Private ]
{
$Piece(horolog, ",") * 86400 + $Piece(horolog, ",", 2)
}

}
