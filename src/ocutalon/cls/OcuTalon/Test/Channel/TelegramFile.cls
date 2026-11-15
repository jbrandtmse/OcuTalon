Include Ensemble

/// Tests of the file of a paired Telegram chat (Story 26.2; AD-4, AD-14, AD-19, AD-21, AD-25, AD-32; FR-54). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), against the CI mock and its dummy token (never
/// api.telegram.org, never a real bot). Each test calls the private File of OcuTalon.Test.Channel.TelegramInProbe (RunFile) with the message object of an update, so that no production item polls: the probe records the
/// allowance call, the Item and the Notifications instead of sending them, and everything else is real: getFile and the download go to the mock (the fixture files are registered through Mock.Control("files")),
/// Core.Files.Store writes the SentFile rows, and the calls the mock got are read from /_mock/telegram/calls. The mock's Bot API side is reset before and after each test. OcuTalon.Test.Channel.TelegramChat.TestFileTurn
/// is the same through the production. The reader switch is the probe's: READSFILES is 0 until Story 25.6, so the tests that fetch turn it on in the probe (Readable), and TestNoReader leaves it to the product.
///   - TestDocument (matrix "Telegram document"): a PDF document with a caption, reported under the limit, is fetched with getFile and the download (in that order, and nothing else), stored as a SentFile row of channel telegram
///     with its bytes, and sent as one untrusted Item of channel telegram with the four file fields and the caption as its text, after one allowance call; nothing is refused;
///   - TestPhoto (matrix "Telegram photo"): the last size of a photo array is fetched, and with no file name the file is stored as photo.jpg;
///   - TestReportedTooLarge (matrix "Telegram over 10 MB", AC5): a document that reports 10,485,761 bytes is refused with files.tooLarge {size 10.1 MB} before any call: the mock got no call, there is no row, and no Item;
///   - TestStreamTooLarge (Planner condition 2): a file whose update claims under the limit but whose stream is over it is cut off at 10 MB of bytes read and refused as files.tooLarge, with no row and
///     the allowance entry given back; a body of exactly 10 MB is read whole;
///   - TestDownloadDeadline (DW-1341): a download still being read at its time limit is cut off, an error status with no stream that names no path, and the same file with the default limit is read;
///   - TestOtherTypeAndEmpty (matrix "Telegram other type"): a document whose bytes are text, and an empty one, are downloaded and refused by Store as files.unreadable with Core.Files' reasons, with no row;
///   - TestFetchFails (matrix "Telegram fetch fails", condition 3): getFile answered 400, a download answered 404, and a call with no bot token are files.unreadable with Docs.Extract's failed reason and one warning that
///     holds no token, no download address and no file path; no row and no Item;
///   - TestOnlineDemo (matrix "Telegram on the demo", AC6): on the demo no call is made, there is no row, and the chat is answered files.offOnDemo, whether or not a reader is on, also for a
///     document or photo part with no file_id (the demo guard comes first);
///   - TestNoReader (Planner ruling H2): with the product's own reader switch (READSFILES 0), a document and a photo get files.noReader with the file's name, no getFile, no download, no row and no Item, and the size check still comes first;
///   - TestNotSent (matrix "Telegram not sent"; DW-1340): an allowance refusal and a session with no row fetch nothing and store nothing, and a failed send gives no Item, discards the stored file
///     and gives the entry back;
///   - TestRenders (AC5): the texts of the files.* keys for the channel telegram are those of Core.Files and Docs.Extract;
///   - TestDownloadApi (conditions 2 and 3): Api.Download refuses a path that is not one getFile answers, with an error text that names no value; and its error texts, and the event log, audit entries and Ensemble messages after every test, hold no token,
///     no "file/bot" and no file path;
///   - (QA) TestFetchBadPath and TestDownloadUnreachable (condition 3): a getFile path that Download refuses, and a download with no server, are refused with no path, address or token in any text.
/// Every refusal after the allowance took the message (a fetch or store that failed) also gives the entry back (Targets "allowed|Notify|refund").
/// The fixture sessions (zztgfile...) come from Test.Data.Fixture and are removed with their files after each test. The probe records under ^OcuTalonTest("TelegramInProbe", n), which OnAfterAllTests kills.
Class OcuTalon.Test.Channel.TelegramFile Extends OcuTalon.Test.Channel.LiveCase
{

Parameter SAMPLES = "OcuTalon.Test.Docs.Samples";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture sessions of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 300);

/// The marks of the test's scans: the event log, the headers and the audit time.
Property MarkLog As %Integer [ Transient ];

Property MarkHeader As %Integer [ Transient ];

Property MarkAudit As %String [ Transient ];

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("TelegramFile", "n"))
	Set ..Refs = ""
	Set ..Missing = ..ReadyReason()
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("TelegramInProbe", ..Number)
	If ..Missing = "" Do ##class(OcuTalon.Test.Channel.BotApi).Reset()
	Set ..MarkLog = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set ..MarkHeader = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Set ..MarkAudit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Missing = "" Do ##class(OcuTalon.Test.Channel.BotApi).Reset()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("TelegramInProbe", ..Number)
	For i = 1:1:$Length(..Refs, ",") {
		If $Piece(..Refs, ",", i) '= "" Do ##class(OcuTalon.Data.SentFile).DropSession($Piece(..Refs, ",", i))
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	If ..Missing = "" Do ##class(OcuTalon.Test.Channel.BotApi).Reset()
	Quit $$$OK
}

/// 1 when the class is set up; otherwise the test fails with the reason.
Method Go() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// A fixture session, kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zztgfile"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A shadow instance of the probe, in the run's records, with the demo flag and the reader switch as given (readable "" leaves the product's own).
Method NewProbe(demo As %Boolean = 0, readable As %String = 1) As OcuTalon.Test.Channel.TelegramInProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Channel.TelegramInProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.RunNumber = ..Number
	Set ^OcuTalonTest("TelegramInProbe", ..Number, "demo") = demo
	If readable '= "" Set ^OcuTalonTest("TelegramInProbe", ..Number, "readable") = readable
	Quit probe
}

/// Registers a fixture file on the mock under the file id and path; 1 when the mock took it.
Method Register(fileId As %String, path As %String, contentType As %String, bytes As %String) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Test.Contract.Mock).Control("files", {"fileId": (fileId), "filePath": (path), "contentType": (contentType), "base64": ($SYSTEM.Encryption.Base64Encode(bytes, 1))})
}

/// Registers a PDF of exactly size bytes on the mock, a few thousand at a time (the body is longer than a string). 1 when the mock took it.
Method RegisterBig(fileId As %String, path As %String, size As %Integer) As %Boolean [ Private ]
{
	Set sc = ##class(OcuTalon.Channel.Telegram.Api).Endpoint($SYSTEM.Util.GetEnviron(##class(OcuTalon.Channel.Telegram.Api).#BASEVAR), .server, .port, .https, .prefix)
	If $$$ISERR(sc) Quit 0
	Set request = ##class(%Net.HttpRequest).%New()
	Set request.Server = server
	Set request.Port = port
	Set request.ContentType = "application/json"
	Set request.Timeout = 120
	Do request.EntityBody.Write("{""fileId"":"""_fileId_""",""filePath"":"""_path_""",""contentType"":""application/pdf"",""base64"":""")
	Set chunk = 30000
	Set left = size
	Set first = 1
	While left > 0 {
		Set n = $Select(left < chunk: left, 1: chunk)
		Set data = $Select(first: "%PDF-1.4"_$Char(10)_$Justify("", n - 9), 1: $Justify("", n))
		Set first = 0
		Do request.EntityBody.Write($SYSTEM.Encryption.Base64Encode(data, 1))
		Set left = left - n
	}
	Do request.EntityBody.Write("""}")
	Quit $$$ISOK(request.Post("/_mock/telegram/files")) && (request.HttpResponse.StatusCode = 200)
}

/// A document message of a chat: file_name, file_size (the reported size) and the caption.
ClassMethod DocumentMessage(fileId As %String, name As %String, size As %Integer, caption As %String = "") As %DynamicObject [ Private ]
{
	Set document = {"file_id": (fileId)}
	If name '= "" Do document.%Set("file_name", name)
	If size '= "" Do document.%Set("file_size", size, "number")
	Set message = {"chat": {"type": "private"}, "document": (document)}
	If caption '= "" Do message.%Set("caption", caption)
	Quit message
}

/// A photo message: two sizes, the last of which is the largest.
ClassMethod PhotoMessage(smallId As %String, largeId As %String, caption As %String = "") As %DynamicObject [ Private ]
{
	Set message = {"chat": {"type": "private"}, "photo": [{"file_id": (smallId), "width": 90, "height": 90}, {"file_id": (largeId), "width": 800, "height": 800}]}
	If caption '= "" Do message.%Set("caption", caption)
	Quit message
}

/// The Bot API methods that the mock got, in order, joined with "," (every method: a test of a file expects getFile and download and nothing else).
Method Called() As %String [ Private ]
{
	Set found = ""
	Set iterator = ##class(OcuTalon.Test.Contract.Mock).Calls().%GetIterator()
	While iterator.%GetNext(, .call) {
		Set found = found _ $Select(found = "": "", 1: ",") _ call.method
	}
	Quit found
}

/// The targets of the recorded calls in order, joined with "|".
Method Targets() As %String [ Private ]
{
	Set found = ""
	For n = 1:1:+$Get(^OcuTalonTest("TelegramInProbe", ..Number)) {
		Set found = found _ $Select(found = "": "", 1: "|") _ ..Call(n, "target")
	}
	Quit found
}

/// One field of one recorded call.
Method Call(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("TelegramInProbe", ..Number, n, field))
}

/// The number of the recorded call of the target (the first), or 0.
Method CallOf(target As %String) As %Integer [ Private ]
{
	For n = 1:1:+$Get(^OcuTalonTest("TelegramInProbe", ..Number)) {
		If ..Call(n, "target") = target Quit
	}
	Quit $Select(n > +$Get(^OcuTalonTest("TelegramInProbe", ..Number)): 0, 1: n)
}

/// The number of SentFile rows of the session.
ClassMethod Rows(session As %String) As %Integer [ Private ]
{
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SentFile WHERE SessionRef = ?", session)
	Do rows.%Next()
	Quit rows.%GetData(1)
}

/// The one Notification of the run: "<key>|<slots JSON>"; "" when there is none or more than one.
Method OneNotification() As %String [ Private ]
{
	Set found = ""
	Set count = 0
	For n = 1:1:+$Get(^OcuTalonTest("TelegramInProbe", ..Number)) {
		If ..Call(n, "target") '= "Notify" Continue
		Set count = count + 1
		Set found = ..Call(n, "catalogKey")_"|"_..Call(n, "slots")
	}
	Quit $Select(count = 1: found, 1: "")
}

/// The text of the key and slots for the channel telegram.
ClassMethod TextOf(key As %String, slots As %DynamicObject = {{}}) As %String [ Private ]
{
	Quit ##class(OcuTalon.Msg.Catalog).Render(key, slots.%ToJSON(), "telegram")
}

/// The scans of the token URL (conditions 3): after a path, the event-log rows, the audit entries and every Ensemble message since the marks hold neither the dummy token, nor "file/bot", nor any of the file paths (a
/// comma-separated list), and no trace global holds the base64 of the file when it is given.
Method AssertQuiet(label As %String, paths As %String = "", base64 As %String = "") [ Private ]
{
	Set token = $SYSTEM.Util.GetEnviron(##class(OcuTalon.Test.Contract.Mock).#TELEGRAMTOKENVAR)
	Set values = $ListBuild(token, "file/bot")
	For i = 1:1:$Length(paths, ",") {
		If $Piece(paths, ",", i) '= "" Set values = values _ $ListBuild($Piece(paths, ",", i))
	}
	Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(..MarkAudit).%ToJSON()
	Set bodies = ..Bodies(..MarkHeader)
	Set headers = ..RowsText("SELECT * FROM Ens.MessageHeader WHERE ID > ?", ..MarkHeader)
	Do $$$AssertTrue(token '= "", label_": the scan has a token to look for")
	Set position = 0
	While $ListNext(values, position, value) {
		Set what = $Select(value = token: "the token", value = "file/bot": "file/bot", 1: "the file path")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(..MarkLog, value), 0, label_": the event log holds no "_what)
		Do $$$AssertNotTrue($Find(audit, value), label_": the audit entries hold no "_what)
		Do $$$AssertNotTrue($Find(bodies, value), label_": no message body holds "_what)
		Do $$$AssertNotTrue($Find(headers, value), label_": no message header holds "_what)
	}
	If base64 '= "" Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(base64), "", label_": no trace global holds the file's base64")
}

/// A document with a caption, reported under the limit, is fetched, stored and sent as one untrusted Item.
Method TestDocument()
{
	If '..Go() || '..Ready() Quit
	Try {
		Set session = ..Session("doc")
		Set text = "zz26s2 tg-"_..Number_" [[mock:file-read]]"
		Set bytes = ..Bytes($ClassMethod(..#SAMPLES, "PdfText", text))
		Set fileId = "zzDoc"_..Number, path = "documents/zzdoc"_..Number_".pdf"
		Do $$$AssertTrue(..Register(fileId, path, "application/pdf", bytes), "the PDF is registered on the mock")
		Do ..NewProbe().RunFile("zzchatref", session, ..DocumentMessage(fileId, "report.pdf", $Length(bytes), "c"))
		Do $$$AssertEquals(..Called(), "getFile,download", "the mock got getFile, then the download, and nothing else")
		Do $$$AssertEquals(..Targets(), "allowed|Conversation", "the allowance was asked and one Item was sent, with no Notification")
		Do $$$AssertEquals(..Call(1, "text"), "c", "the allowance was asked for the caption")
		Set n = ..CallOf("Conversation")
		Do $$$AssertEquals(..Call(n, "sessionRef")_"|"_..Call(n, "channel")_"|"_..Call(n, "provenance")_"|"_..Call(n, "text")_"|"_..Call(n, "fromGuide")_"|"_..Call(n, "clientId"), session_"|telegram|untrusted|c|0|", "the Item is the session's, of channel telegram and provenance untrusted, with the caption as its text")
		Do $$$AssertEquals(..Call(n, "fileName")_"|"_..Call(n, "fileMediaType")_"|"_..Call(n, "fileSize"), "report.pdf|application/pdf|"_$Length(bytes), "and it names the file's name, type and size")
		Set row = ##class(OcuTalon.Data.Ownership).SentFile(..Call(n, "fileRef"), session)
		Do $$$AssertTrue($IsObject(row), "the Item's fileRef is a SentFile row of the session")
		If $IsObject(row) {
			Do $$$AssertEquals(row.Channel_"|"_row.Name_"|"_row.MediaType_"|"_row.Size, "telegram|report.pdf|application/pdf|"_$Length(bytes), "of channel telegram")
			Do $$$AssertEquals(##class(OcuTalon.Core.Files).Open(row.Ref, session).Read(row.Size) = bytes, 1, "holding the downloaded bytes")
		}
		Do $$$AssertEquals(..Rows(session), 1, "the session has that one file")
		Do ..AssertQuiet("a document", path, ..Base64(bytes))
	} Catch ex {
		Do $$$AssertTrue(0, "the document test failed: "_..Safe(ex))
	}
}

/// The last size of a photo is fetched; with no name the file is stored as photo.jpg.
Method TestPhoto()
{
	If '..Go() || '..Ready() Quit
	Try {
		Set session = ..Session("photo")
		Set bytes = $Char(255, 216, 255, 224)_"zz26s2 jpeg "_..Number
		Set small = "zzSmall"_..Number, large = "zzLarge"_..Number, path = "photos/zzphoto"_..Number_".jpg"
		Do $$$AssertTrue(..Register(large, path, "image/jpeg", bytes), "the large size is registered on the mock")
		Do ..NewProbe().RunFile("zzchatref", session, ..PhotoMessage(small, large))
		Set calls = ##class(OcuTalon.Test.Contract.Mock).Calls()
		Do $$$AssertEquals(..Called(), "getFile,download", "the mock got getFile, then the download")
		If calls.%Size() '= 2 Quit
		Do $$$AssertEquals(calls.%Get(0).params."file_id", large, "getFile asked for the last, largest size")
		Do $$$AssertEquals(..Targets(), "allowed|Conversation", "one Item was sent")
		Set n = ..CallOf("Conversation")
		Do $$$AssertEquals(..Call(n, "provenance")_"|"_..Call(n, "channel")_"|"_..Call(n, "text")_"|"_..Call(n, "fileName")_"|"_..Call(n, "fileMediaType"), "untrusted|telegram||photo.jpg|image/jpeg", "it is untrusted, of channel telegram, with no text, and its file is photo.jpg")
		Do $$$AssertEquals(..Rows(session), 1, "the session has the file")
		Do ..AssertQuiet("a photo", path, ..Base64(bytes))
	} Catch ex {
		Do $$$AssertTrue(0, "the photo test failed: "_..Safe(ex))
	}
}

/// A reported size over the limit is refused before any call.
Method TestReportedTooLarge()
{
	If '..Go() || '..Ready() Quit
	Try {
		Set session = ..Session("reported")
		Set fileId = "zzBig"_..Number
		Do $$$AssertTrue(..Register(fileId, "documents/zzbig"_..Number_".pdf", "application/pdf", ..Bytes($ClassMethod(..#SAMPLES, "PdfText", "zz26s2 big"))), "a file is registered, which a call would fetch")
		Set limit = ##class(OcuTalon.Core.Files).#FILEMAX
		Do ..NewProbe().RunFile("zzchatref", session, ..DocumentMessage(fileId, "big.pdf", limit + 1))
		Do $$$AssertEquals(..Called(), "", "the mock got no call, so neither getFile nor the download")
		Do $$$AssertEquals(..Targets(), "Notify", "one Notification and no Item was sent, and the allowance was not asked")
		Set notification = ..OneNotification()
		Do $$$AssertEquals($Piece(notification, "|", 1), "files.tooLarge", "it is files.tooLarge")
		Do $$$AssertEquals({}.%FromJSON($Piece(notification, "|", 2, *)).size, "10.1 MB", "with the size 10.1 MB")
		Do $$$AssertEquals(..TextOf("files.tooLarge", {"size": "10.1 MB"}), "That file is 10.1 MB; the limit is 10 MB.", "which reads as the chat's text")
		Do $$$AssertEquals(..Rows(session), 0, "no file was stored")
		// The limit itself is not too large.
		Kill ^OcuTalonTest("TelegramInProbe", ..Number)
		Do ..NewProbe().RunFile("zzchatref", session, ..DocumentMessage(fileId, "big.pdf", limit))
		Do $$$AssertEquals(..Called(), "getFile,download", "a reported size of exactly 10 MB is fetched")
	} Catch ex {
		Do $$$AssertTrue(0, "the reported-size test failed: "_..Safe(ex))
	}
}

/// A stream over the limit whose update claims less is cut off at 10 MB of bytes read and refused (Planner condition 2).
Method TestStreamTooLarge()
{
	If '..Go() || '..Ready() Quit
	Try {
		Set session = ..Session("stream")
		Set fileId = "zzStream"_..Number, path = "documents/zzstream"_..Number_".pdf"
		Set limit = ##class(OcuTalon.Core.Files).#FILEMAX
		Do $$$AssertTrue(..RegisterBig(fileId, path, limit + 1), "a PDF of 10,485,761 bytes is registered on the mock")
		Do ..NewProbe().RunFile("zzchatref", session, ..DocumentMessage(fileId, "stream.pdf", 1000))
		Do $$$AssertEquals(..Called(), "getFile,download", "the update's claimed size passed, so the mock got getFile and the download")
		Do $$$AssertEquals(..Targets(), "allowed|Notify|refund", "the allowance took the message, one Notification and no Item was sent, and the entry was given back")
		Set notification = ..OneNotification()
		Do $$$AssertEquals($Piece(notification, "|", 1)_"|"_{}.%FromJSON($Piece(notification, "|", 2, *)).size, "files.tooLarge|10.1 MB", "it is files.tooLarge with the size 10.1 MB")
		Do $$$AssertEquals(..Rows(session), 0, "no file was stored")
		// Download itself stops at the limit: the body is cut off, not read whole and refused after.
		Set stream = ##class(OcuTalon.Channel.Telegram.Api).Download($SYSTEM.Util.GetEnviron(##class(OcuTalon.Channel.Telegram.Api).#BASEVAR), "", path, 30, .status, .sc, .tooLarge)
		Do $$$AssertEquals($IsObject(stream)_"|"_status_"|"_tooLarge, "0|200|1", "Api.Download answers no stream, with the status 200 and tooLarge 1: it stopped at 10 MB of bytes read")
		Do $$$AssertTrue($SYSTEM.Status.IsError(sc) && ($Find($SYSTEM.Status.GetErrorText(sc), path) = 0), "and an error status that names no path")
		// A body of exactly the limit is read whole: the cut-off is above 10 MB, as Store's limit is.
		Set exactId = "zzExact"_..Number, exactPath = "documents/zzexact"_..Number_".pdf"
		Do $$$AssertTrue(..RegisterBig(exactId, exactPath, limit), "a PDF of exactly 10,485,760 bytes is registered on the mock")
		Set stream = ##class(OcuTalon.Channel.Telegram.Api).Download($SYSTEM.Util.GetEnviron(##class(OcuTalon.Channel.Telegram.Api).#BASEVAR), "", exactPath, 30, .status, .sc, .tooLarge)
		Do $$$AssertEquals($IsObject(stream)_"|"_status_"|"_tooLarge_"|"_$Select($IsObject(stream): stream.Size, 1: ""), "1|200|0|"_limit, "Api.Download reads a body of exactly 10 MB whole: a stream of 10,485,760 bytes, not tooLarge")
		Do $$$AssertStatusOK(sc, "with an OK status")
		Do ..AssertQuiet("a stream over the limit", path_","_exactPath)
	} Catch ex {
		Do $$$AssertTrue(0, "the stream-size test failed: "_..Safe(ex))
	}
}

/// A document of another type and an empty one are fetched and refused by Store.
Method TestOtherTypeAndEmpty()
{
	If '..Go() || '..Ready() Quit
	Try {
		Set session = ..Session("type")
		Set cases = $ListBuild($ListBuild("text", "zz26s2 plain text", "notes.txt", ##class(OcuTalon.Core.Files).#REASONWRONGTYPE), $ListBuild("empty", "", "empty.pdf", ##class(OcuTalon.Core.Files).#REASONEMPTY))
		Set position = 0
		While $ListNext(cases, position, case) {
			Set label = $List(case, 1)
			Kill ^OcuTalonTest("TelegramInProbe", ..Number)
			Do ##class(OcuTalon.Test.Channel.BotApi).Reset()
			Set fileId = "zzType"_..Number_label, path = "documents/zztype"_..Number_label_".bin"
			Do $$$AssertTrue(..Register(fileId, path, "application/octet-stream", $List(case, 2)), label_": the file is registered")
			Do ..NewProbe().RunFile("zzchatref", session, ..DocumentMessage(fileId, $List(case, 3), $Length($List(case, 2))))
			Do $$$AssertEquals(..Called(), "getFile,download", label_": it is fetched")
			Do $$$AssertEquals(..Targets(), "allowed|Notify|refund", label_": one Notification and no Item, and the entry was given back")
			Set notification = ..OneNotification()
			Do $$$AssertEquals($Piece(notification, "|", 1)_"|"_{}.%FromJSON($Piece(notification, "|", 2, *)).reason, "files.unreadable|"_$List(case, 4), label_": files.unreadable with Core.Files' reason")
			Do $$$AssertEquals(..Rows(session), 0, label_": no file was stored")
		}
		Do $$$AssertEquals(..TextOf("files.unreadable", {"reason": (##class(OcuTalon.Core.Files).#REASONWRONGTYPE)}), ##class(OcuTalon.Core.Files).RefusalText(##class(OcuTalon.Core.Files).#WRONGTYPE), "the wrong-type text is Core.Files' RefusalText")
		Do $$$AssertEquals(..TextOf("files.unreadable", {"reason": (##class(OcuTalon.Core.Files).#REASONEMPTY)}), ##class(OcuTalon.Core.Files).RefusalText(##class(OcuTalon.Core.Files).#EMPTY), "and so is the empty-file text")
	} Catch ex {
		Do $$$AssertTrue(0, "the other-type test failed: "_..Safe(ex))
	}
}

/// getFile answered 400, a download answered 404 and a call with no token are files.unreadable with one warning that holds no token, address or path.
Method TestFetchFails()
{
	If '..Go() || '..Ready() Quit
	Try {
		Set session = ..Session("fetch")
		Set failed = ##class(OcuTalon.Docs.Extract).Reason("failed")
		Set start = ##class(OcuTalon.Channel.Telegram.In).#LOGFETCH
		Set token = $SYSTEM.Util.GetEnviron(##class(OcuTalon.Test.Contract.Mock).#TELEGRAMTOKENVAR)
		Set cases = $ListBuild("getFile 400", "download 404", "no token")
		Set position = 0
		While $ListNext(cases, position, label) {
			Kill ^OcuTalonTest("TelegramInProbe", ..Number)
			Do ##class(OcuTalon.Test.Channel.BotApi).Reset()
			Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
			Set fileId = "zzFail"_..Number_$Translate(label, " ", ""), path = "documents/zzgone"_..Number_".pdf"
			If label = "download 404" {
				Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "getFile", "replies": [{"status": 200, "body": {"ok": true, "result": {"file_id": (fileId), "file_unique_id": "uzz", "file_path": (path)}}}]}), label_": getFile is told to name a path that no file has")
			} ElseIf label = "no token" {
				Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv(##class(OcuTalon.Test.Contract.Mock).#TELEGRAMTOKENVAR)
			}
			Try {
				Do ..NewProbe().RunFile("zzchatref", session, ..DocumentMessage(fileId, "gone.pdf", 100))
			} Catch inner {
				Do $$$AssertTrue(0, label_": File threw: "_..Safe(inner))
			}
			If label = "no token" Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(##class(OcuTalon.Test.Contract.Mock).#TELEGRAMTOKENVAR, token)
			Do $$$AssertEquals(..Targets(), "allowed|Notify|refund", label_": one Notification and no Item, and the entry was given back")
			Set notification = ..OneNotification()
			Do $$$AssertEquals($Piece(notification, "|", 1)_"|"_{}.%FromJSON($Piece(notification, "|", 2, *)).reason, "files.unreadable|"_failed, label_": files.unreadable with the reason of failed")
			Do $$$AssertEquals(..TextOf("files.unreadable", {"reason": (failed)}), ##class(OcuTalon.Docs.Extract).Failure("failed"), label_": which reads as Docs.Extract's Failure of failed")
			Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .warning, "Fetch", start), 1, label_": one warning was logged: "_$Extract(warning, 1, 160))
			Do $$$AssertEquals($Find(warning, "file/bot") + $Find(warning, path) + $Find(warning, $Select(token = "": "zzno-token", 1: token)), 0, label_": and it holds no download address, path or token")
			Do $$$AssertEquals(..Rows(session), 0, label_": no file was stored")
			Do ..AssertQuiet(label, path)
			Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Fetch", start)
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the fetch-failure test failed: "_..Safe(ex))
	}
}

/// On the online demo a file is never fetched and is answered with the off text, whether or not a reader is on.
Method TestOnlineDemo()
{
	If '..Go() || '..Ready() Quit
	Try {
		Set session = ..Session("demo")
		Set fileId = "zzDemo"_..Number, path = "documents/zzdemo"_..Number_".pdf"
		Do $$$AssertTrue(..Register(fileId, path, "application/pdf", ..Bytes($ClassMethod(..#SAMPLES, "PdfText", "zz26s2 demo"))), "a file is registered, which a call would fetch")
		For readable = 1, 0 {
			Kill ^OcuTalonTest("TelegramInProbe", ..Number)
			Do ..NewProbe(1, readable).RunFile("zzchatref", session, ..DocumentMessage(fileId, "demo.pdf", 100))
			Do $$$AssertEquals(..Called(), "", "reader "_readable_": the mock got no call")
			Do $$$AssertEquals(..Targets(), "Notify", "reader "_readable_": one Notification and no Item")
			Set notification = ..OneNotification()
			Do $$$AssertEquals($Piece(notification, "|", 1)_"|"_$Piece(notification, "|", 2, *), "files.offOnDemo|{}", "reader "_readable_": files.offOnDemo with no slots")
			Do $$$AssertEquals(..Rows(session), 0, "reader "_readable_": no file was stored")
		}
		// The demo guard comes first: a part with no file_id gets the off text too, not the unreadable one.
		For label = "a document with no file_id", "a photo size with no file_id" {
			Kill ^OcuTalonTest("TelegramInProbe", ..Number)
			Set message = $Select(label [ "document": {"chat": {"type": "private"}, "document": {"file_name": "demo.pdf", "file_size": 100}}, 1: {"chat": {"type": "private"}, "photo": [{"width": 90, "height": 90}]})
			Do ..NewProbe(1, 1).RunFile("zzchatref", session, message)
			Do $$$AssertEquals(..Called()_"|"_..OneNotification(), "|files.offOnDemo|{}", label_": no call, and files.offOnDemo")
		}
		Do $$$AssertEquals(..TextOf("files.offOnDemo"), ##class(OcuTalon.Core.Files).#TEXTOFFONDEMO, "the text is Core.Files' TEXTOFFONDEMO")
	} Catch ex {
		Do $$$AssertTrue(0, "the online-demo test failed: "_..Safe(ex))
	}
}

/// H2: while READSFILES is 0 a document and a photo get Core.Files' no-reader reply and nothing is fetched or stored.
Method TestNoReader()
{
	If '..Go() || '..Ready() Quit
	Try {
		Set session = ..Session("noreader")
		Do $$$AssertEquals(##class(OcuTalon.Core.Files).Readable(), 0, "the product's reader switch is off")
		Set fileId = "zzNoRead"_..Number
		Do $$$AssertTrue(..Register(fileId, "documents/zznoread"_..Number_".pdf", "application/pdf", ..Bytes($ClassMethod(..#SAMPLES, "PdfText", "zz26s2 no reader"))), "a file is registered, which a call would fetch")
		Set cases = $ListBuild($ListBuild("a document", "document", "report.pdf", "report.pdf"), $ListBuild("a nameless document", "document", "", "file"), $ListBuild("a photo", "photo", "", "photo.jpg"))
		Set position = 0
		While $ListNext(cases, position, case) {
			Set label = $List(case, 1)
			Kill ^OcuTalonTest("TelegramInProbe", ..Number)
			Set probe = ..NewProbe(0, "")
			Set message = $Select($List(case, 2) = "document": ..DocumentMessage(fileId, $List(case, 3), 100, "c"), 1: ..PhotoMessage("zzSmall", fileId, "c"))
			Do probe.RunFile("zzchatref", session, message)
			Do $$$AssertEquals(..Called(), "", label_": the mock got no getFile and no download")
			Do $$$AssertEquals(..Targets(), "Notify", label_": one Notification, no Item and no allowance call")
			Set notification = ..OneNotification()
			Do $$$AssertEquals($Piece(notification, "|", 1)_"|"_{}.%FromJSON($Piece(notification, "|", 2, *)).name, "files.noReader|"_$List(case, 4), label_": files.noReader with the file's name")
			Do $$$AssertEquals(..TextOf("files.noReader", {"name": ($List(case, 4))}), ##class(OcuTalon.Core.Files).NoReaderText($List(case, 4)), label_": which reads as Core.Files' no-reader reply, as the web chat's")
			Do $$$AssertEquals(..Rows(session), 0, label_": no file was stored")
		}
		// The size check comes first, as Store's does on the web route.
		Kill ^OcuTalonTest("TelegramInProbe", ..Number)
		Do ..NewProbe(0, "").RunFile("zzchatref", session, ..DocumentMessage(fileId, "big.pdf", ##class(OcuTalon.Core.Files).#FILEMAX + 1))
		Do $$$AssertEquals($Piece(..OneNotification(), "|", 1), "files.tooLarge", "a file over 10 MB is refused as too large, as on the web route")
		// The demo guard comes before the reader switch.
		Kill ^OcuTalonTest("TelegramInProbe", ..Number)
		Do ..NewProbe(1, "").RunFile("zzchatref", session, ..DocumentMessage(fileId, "demo.pdf", 100))
		Do $$$AssertEquals($Piece(..OneNotification(), "|", 1), "files.offOnDemo", "on the demo the off text comes first")
		Do $$$AssertEquals(..Called(), "", "and no call was made")
	} Catch ex {
		Do $$$AssertTrue(0, "the no-reader test failed: "_..Safe(ex))
	}
}

/// (QA) A getFile answer that names no path, or a path that Download refuses ("../", a space), is files.unreadable with no download call: the answer of Telegram is not trusted into the address (Planner condition 3).
Method TestFetchBadPath()
{
	If '..Go() || '..Ready() Quit
	Try {
		Set session = ..Session("badpath")
		Set failed = ##class(OcuTalon.Docs.Extract).Reason("failed")
		Set start = ##class(OcuTalon.Channel.Telegram.In).#LOGFETCH
		Set cases = $ListBuild($ListBuild("traversal", "../../etc/passwd"), $ListBuild("a space", "documents/a b.pdf"), $ListBuild("no path", ""))
		Set position = 0
		While $ListNext(cases, position, case) {
			Set label = $List(case, 1), path = $List(case, 2)
			Kill ^OcuTalonTest("TelegramInProbe", ..Number)
			Do ##class(OcuTalon.Test.Channel.BotApi).Reset()
			Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
			Set fileId = "zzBadPath"_..Number_$Translate(label, " ", "")
			Set result = {"file_id": (fileId), "file_unique_id": "uzz"}
			If path '= "" Do result.%Set("file_path", path)
			Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "getFile", "replies": [{"status": 200, "body": {"ok": true, "result": (result)}}]}), label_": getFile is told to answer "_$Select(path = "": "no path", 1: "a path that is not safe"))
			Do ..NewProbe().RunFile("zzchatref", session, ..DocumentMessage(fileId, "bad.pdf", 100))
			Do $$$AssertEquals(..Called(), "getFile", label_": the mock got getFile and no download")
			Do $$$AssertEquals(..Targets(), "allowed|Notify|refund", label_": one Notification and no Item, and the entry was given back")
			Set notification = ..OneNotification()
			Do $$$AssertEquals($Piece(notification, "|", 1)_"|"_{}.%FromJSON($Piece(notification, "|", 2, *)).reason, "files.unreadable|"_failed, label_": files.unreadable with the reason of failed")
			Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .warning, "Fetch", start), 1, label_": one warning was logged: "_$Extract(warning, 1, 160))
			Do $$$AssertEquals($Find(warning, "etc/passwd") + $Find(warning, "a b.pdf") + $Find(warning, "file/bot"), 0, label_": and it holds no path or download address")
			Do $$$AssertEquals(..Rows(session), 0, label_": no file was stored")
			Do ..AssertQuiet(label, $Select(path = "": "zz-no-path", 1: path))
			Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Fetch", start)
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the bad-path test failed: "_..Safe(ex))
	}
}

/// (QA) A download that gets no answer at all (nothing listens at the address) is an error status and no stream, and its text holds no token, address or path (Planner condition 3, the failure path of the transport).
Method TestDownloadUnreachable()
{
	If '..Go() || '..Ready() Quit
	Try {
		Set token = $SYSTEM.Util.GetEnviron(##class(OcuTalon.Test.Contract.Mock).#TELEGRAMTOKENVAR)
		Set path = "documents/zzunreachable"_..Number_".pdf"
		Set stream = ##class(OcuTalon.Channel.Telegram.Api).Download("http://127.0.0.1:1", "", path, 3, .status, .sc, .tooLarge)
		Do $$$AssertEquals($IsObject(stream)_"|"_tooLarge, "0|0", "no stream, and not too large")
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "the status is an error: "_text)
		Do $$$AssertEquals($Find(text, "file/bot") + $Find(text, path) + $Find(text, token), 0, "and its text holds no address, path or token: "_text)
		Do ..AssertQuiet("an unreachable server", path)
	} Catch ex {
		Do $$$AssertTrue(0, "the unreachable-download test failed: "_..Safe(ex))
	}
}

/// A download that is still being read at its time limit is cut off, with no stream and an error that names no path (DW-1341); the same file read with the default limit is whole.
Method TestDownloadDeadline()
{
	If '..Go() || '..Ready() Quit
	Try {
		Set base = $SYSTEM.Util.GetEnviron(##class(OcuTalon.Channel.Telegram.Api).#BASEVAR)
		Set fileId = "zzSlow"_..Number, path = "documents/zzslow"_..Number_".pdf"
		Set size = 4194304
		Do $$$AssertTrue(..RegisterBig(fileId, path, size), "a PDF of 4 MB is registered on the mock")
		Set stream = ##class(OcuTalon.Channel.Telegram.Api).Download(base, "", path, 30, .status, .sc, .tooLarge, 0.001)
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertEquals($IsObject(stream)_"|"_tooLarge, "0|0", "with a time limit of 1 ms the download is cut off: no stream, and not too large")
		Do $$$AssertTrue($SYSTEM.Status.IsError(sc) && (text [ "time limit"), "an error status that says it took longer than its time limit: "_text)
		Do $$$AssertEquals($Find(text, "file/bot") + $Find(text, path), 0, "and names no address or path")
		Set stream = ##class(OcuTalon.Channel.Telegram.Api).Download(base, "", path, 30, .status, .sc, .tooLarge)
		Do $$$AssertEquals($IsObject(stream)_"|"_status_"|"_$Select($IsObject(stream): stream.Size, 1: ""), "1|200|"_size, "with the default limit (DOWNLOADSECONDS) the same file is read whole")
		Do $$$AssertEquals(##class(OcuTalon.Channel.Telegram.Api).#DOWNLOADSECONDS, 60, "the default limit is 60 seconds")
		Do ..AssertQuiet("a download over its time", path)
	} Catch ex {
		Do $$$AssertTrue(0, "the download-deadline test failed: "_..Safe(ex))
	}
}

/// A file whose Item is not sent leaves no row: an allowance refusal and a session with no row fetch nothing (DW-1340), and a failed send discards the stored file.
Method TestNotSent()
{
	If '..Go() || '..Ready() Quit
	Try {
		Set session = ..Session("notsent")
		Set bytes = ..Bytes($ClassMethod(..#SAMPLES, "PdfText", "zz26s2 not sent"))
		Set fileId = "zzNotSent"_..Number
		For case = "refused", "no session row", "failed send" {
			Kill ^OcuTalonTest("TelegramInProbe", ..Number)
			Do ##class(OcuTalon.Test.Channel.BotApi).Reset()
			Do $$$AssertTrue(..Register(fileId, "documents/zznotsent"_..Number_".pdf", "application/pdf", bytes), case_": a file is registered")
			Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
			Set probe = ..NewProbe()
			Set owner = session
			If case = "refused" Set probe.Refuse = 1
			If case = "failed send" Set probe.FailSend = 1
			If case = "no session row" Set owner = "zznosession"_..Number
			Do probe.RunFile("zzchatref", owner, ..DocumentMessage(fileId, "n.pdf", $Length(bytes)))
			Do $$$AssertEquals(..Called(), $Select(case = "failed send": "getFile,download", 1: ""), case_": "_$Select(case = "failed send": "the file was fetched", 1: "nothing was fetched, before the allowance or the row let the message in (DW-1340)"))
			Do $$$AssertEquals(..Rows(owner), 0, case_": and no row is left")
			Set targets = ..Targets()
			If case = "refused" Do $$$AssertEquals(targets, "allowed|Notify", case_": the allowance was refused and gave its notice, and no Item was sent")
			If case = "no session row" Do $$$AssertEquals(targets, "", case_": nothing was asked or sent")
			If case = "failed send" {
				Do $$$AssertEquals(targets, "allowed|Conversation|refund", case_": the send failed and gave the entry back")
				Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .warning, "Turn", ##class(OcuTalon.Channel.Telegram.In).#LOGSEND), 1, case_": with one warning")
			}
			Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Turn", "TelegramIn could not")
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the not-sent test failed: "_..Safe(ex))
	}
}

/// The catalog texts of the files.* keys for the channel telegram are the texts of Core.Files and Docs.Extract (AC5).
Method TestRenders()
{
	Set limit = ##class(OcuTalon.Core.Files).#FILEMAX
	For size = 1048576, limit + 1, 2621440 {
		Do $$$AssertEquals(..TextOf("files.tooLarge", {"size": (##class(OcuTalon.Core.Files).SizeText(size))}), ##class(OcuTalon.Core.Files).RefusalText(##class(OcuTalon.Core.Files).#TOOLARGE, size), "files.tooLarge of "_size_" bytes is Core.Files' RefusalText")
	}
	Do $$$AssertEquals(..TextOf("files.unreadable", {"reason": (##class(OcuTalon.Core.Files).#REASONWRONGTYPE)}), ##class(OcuTalon.Core.Files).RefusalText(##class(OcuTalon.Core.Files).#WRONGTYPE), "files.unreadable with the wrong-type reason")
	Do $$$AssertEquals(..TextOf("files.unreadable", {"reason": (##class(OcuTalon.Core.Files).#REASONEMPTY)}), ##class(OcuTalon.Core.Files).RefusalText(##class(OcuTalon.Core.Files).#EMPTY), "files.unreadable with the empty reason")
	Do $$$AssertEquals(..TextOf("files.unreadable", {"reason": (##class(OcuTalon.Docs.Extract).Reason("failed"))}), ##class(OcuTalon.Docs.Extract).Failure("failed"), "files.unreadable with the failed reason is Docs.Extract's Failure")
	Do $$$AssertEquals(..TextOf("files.offOnDemo"), ##class(OcuTalon.Core.Files).#TEXTOFFONDEMO, "files.offOnDemo is Core.Files' TEXTOFFONDEMO")
	Do $$$AssertEquals(..TextOf("files.noReader", {"name": "a.pdf"}), ##class(OcuTalon.Core.Files).NoReaderText("a.pdf"), "files.noReader is Core.Files' NoReaderText")
}

/// Api.Download refuses a path that getFile would not answer, with an error text that names no value, and no error text holds the token, the address or the path.
Method TestDownloadApi()
{
	If '..Go() || '..Ready() Quit
	Try {
		Set token = $SYSTEM.Util.GetEnviron(##class(OcuTalon.Test.Contract.Mock).#TELEGRAMTOKENVAR)
		Set base = $SYSTEM.Util.GetEnviron(##class(OcuTalon.Channel.Telegram.Api).#BASEVAR)
		Do $$$AssertEquals(##class(OcuTalon.Channel.Telegram.Api).PathOk("documents/file_1.pdf"), 1, "a path of letters, digits, dot, underscore and slash is taken")
		For path = "", "../x.pdf", "a/../b.pdf", "a//b.pdf", "./a", "a/.", "/a.pdf", "a b.pdf", "a?x=1", "a%2e.pdf", "a\b", $Translate($Justify("", 201), " ", "a") {
			Do $$$AssertEquals(##class(OcuTalon.Channel.Telegram.Api).PathOk(path), 0, "the path '"_$Extract(path, 1, 20)_"' is refused")
			Set stream = ##class(OcuTalon.Channel.Telegram.Api).Download(base, "", path, 5, .status, .sc, .tooLarge)
			Do $$$AssertEquals($IsObject(stream), 0, "Download of '"_$Extract(path, 1, 20)_"' answers no stream")
			Set text = $SYSTEM.Status.GetErrorText(sc)
			Do $$$AssertTrue($SYSTEM.Status.IsError(sc) && ($Find(text, $Select(path = "": "zz-no-path", 1: path)) = 0) && ($Find(text, token) = 0), "and its error text names no value: "_text)
		}
		Set stream = ##class(OcuTalon.Channel.Telegram.Api).Download(base, "", "documents/zzabsent.pdf", 5, .status, .sc, .tooLarge)
		Do $$$AssertEquals($IsObject(stream)_"|"_status_"|"_tooLarge, "0|404|0", "a path that no file has is a 404 and no stream")
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue($SYSTEM.Status.IsError(sc) && ($Find(text, "file/bot") = 0) && ($Find(text, "zzabsent") = 0) && ($Find(text, token) = 0), "whose error text holds no address, path or token: "_text)
		Set stream = ##class(OcuTalon.Channel.Telegram.Api).Download("not a base", "", "documents/zzabsent.pdf", 5, .status, .sc, .tooLarge)
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue($SYSTEM.Status.IsError(sc) && ($Find(text, "not a base") = 0), "a bad base is an error that names the setting and not its value: "_text)
		Do ..AssertQuiet("the downloads", "zzabsent")
	} Catch ex {
		Do $$$AssertTrue(0, "the download test failed: "_..Safe(ex))
	}
}

/// The bytes of the stream.
ClassMethod Bytes(stream As %Stream.Object) As %String [ Private ]
{
	Do stream.Rewind()
	Set bytes = stream.Read(stream.Size)
	Do stream.Rewind()
	Quit bytes
}

/// The base64 of the bytes, on one line, as a model request carries it.
ClassMethod Base64(bytes As %String) As %String [ Private ]
{
	Quit $SYSTEM.Encryption.Base64Encode(bytes, 1)
}

}
