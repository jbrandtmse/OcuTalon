/// The text of a PDF or Word (.docx) file (AD-21, "PDF and Word"): the caller side of the extraction service. This class holds no Python and no %AI
/// reference, so it may be called from anywhere, inside a tool's turn included (it is among the callback helpers that Test.Bridge.CodeRules scans). The
/// reading is done by OcuTalon.Docs.Extractor, a worker of its own category (AD-6).
///   - Read(content, contentType, timeout) returns a dynamic object and never throws. It stores nothing: it writes the bytes to a private temporary file
///     below the temp directory's ocutalon-extract folder, queues one work item, and deletes the file before it returns, whatever happened. A file of that
///     folder older than MAXAGE is deleted when a call is about to write a file (a call that answers from the type or the size alone writes none).
///   - A text answer is {ok:1, text, cut, markers, job}: markers is page for a PDF, heading for a .docx with headings, none otherwise; the text holds PAGEMARKER
///     lines (PDF) or Markdown heading lines (.docx); a text over MAXTEXT characters is cut at a line break and followed by a blank line and CUTNOTE (cut:1).
///   - A failure is {ok:0, reason, detail?}. reason is one of CODES, fixed and independent of the wording; detail is for the operator only and never for a user.
///     Reason(code) is the plain reason, REASON<CODE> without the underscores, and Failure(code) puts it in FAILUREFRAME.
///   - The type and the size are checked first, with no worker and no file: wrong_type, too_large (over MAXBYTES) and damaged (no bytes).
///   - Answer(sc, .result) maps a work item's status and result to the answer, so that every branch is testable without a worker.
Class OcuTalon.Docs.Extract
{

/// The most bytes of an input file; pinned equal to the web upload limit (Web.Documents FILEMAX) by a test, never read from it here.
Parameter MAXBYTES = 10485760;

/// The most characters of text before the cut note, and the most bytes a .docx may declare unpacked in all its zip entries.
Parameter MAXTEXT = 200000;

Parameter MAXUNPACKED = 104857600;

/// Seconds that a caller waits for the worker.
Parameter TIMEOUT = 120;

/// The temporary folder (below the temp directory) and the age in seconds from which a leftover file in it is deleted.
Parameter FOLDER = "ocutalon-extract";

Parameter MAXAGE = 3600;

/// The content types that are read, and the machine reason codes.
Parameter TYPES = "pdf,docx";

Parameter CODES = "too_large,contents_too_large,wrong_type,encrypted,damaged,no_text,legacy_doc,timed_out,failed";

/// User-facing text (PUBLIC TEXT): the page marker line ({n} is the page number; it becomes a citation's section), the note after a cut text, the sentence
/// that frames a reason (UX-DR147) and the nine reasons, each read as "I couldn't read that file: {reason}.".
Parameter PAGEMARKER = "## Page {n}";

Parameter CUTNOTE = "[OcuTalon read only the first 200,000 characters of this file.]";

Parameter FAILUREFRAME = "I couldn't read that file: {reason}.";

Parameter REASONTOOLARGE = "it is over the 10 MB limit";

Parameter REASONCONTENTSTOOLARGE = "its contents are too large to read";

Parameter REASONWRONGTYPE = "it is not a PDF or Word (.docx) file";

Parameter REASONENCRYPTED = "it is protected with a password";

Parameter REASONDAMAGED = "it is damaged or incomplete";

Parameter REASONNOTEXT = "it has no text to read, for example a scanned PDF without a text layer";

Parameter REASONLEGACYDOC = "it is an old Word file (.doc), so save it as .docx and try again";

Parameter REASONTIMEDOUT = "reading it took too long";

Parameter REASONFAILED = "something went wrong while reading it";

ClassMethod Read(content As %Stream.Object, contentType As %String, timeout As %Integer = {..#TIMEOUT}) As %DynamicObject
{
	Set file = ""
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
				Set sc = ##class(OcuTalon.Docs.Extractor).Submit("Read", timeout, .result, file, ..#MAXTEXT, ..#MAXUNPACKED, ..#PAGEMARKER)
				Set answer = ..Answer(sc, .result)
			}
		}
	} Catch exception {
		Set answer = ..Fail("failed", exception.DisplayString())
	}
	If file '= "" Do ##class(%File).Delete(file)
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

/// The plain reason for a code, as a part of FAILUREFRAME; an unknown code has the reason of failed.
ClassMethod Reason(code As %String) As %String
{
	If '$ListFind($ListFromString(..#CODES, ","), code) Set code = "failed"
	Quit $PARAMETER($ClassName(), "REASON" _ $ZConvert($Translate(code, "_"), "U"))
}

/// The sentence that tells the user why a file could not be read: FAILUREFRAME with the code's reason.
ClassMethod Failure(code As %String) As %String
{
	Quit $Replace(..#FAILUREFRAME, "{reason}", ..Reason(code))
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
