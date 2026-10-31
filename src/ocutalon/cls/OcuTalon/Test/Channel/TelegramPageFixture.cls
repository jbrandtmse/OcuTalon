/// The IRIS side of the page's real-pause browser test (Story 12.8; FR-22, AD-12, AD-14, AD-18, NFR-11): web/e2e/demo-path/telegram-page.spec.ts
/// calls it from IRIS scripts, one method per step, to drive the real TelegramIn against the CI mock and the production's own StatusMonitor.
/// THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it has no Test method, so it is no test class and joins no shard run.
/// It is built on the class methods of OcuTalon.Test.Channel.LiveCase, which it calls instead of copying.
///   - Start guards the stack, saves what Finish puts back and starts TelegramIn; Conflict queues the 409 and waits for the pause and for
///     StatusMonitor's onset; Resume stands in for the five minutes by moving the mark; Finish puts everything back.
///   - Each of those methods returns "" when it worked, or the reason it did not. No reason, and no value this class returns except Token,
///     holds the Bot API token: an exception's text has the token cut out.
///   - Finish is safe after any partial Start. It does nothing for a Start that was refused before it changed anything (saved is "").
///   - Token is the stack's dummy token, for the spec's search of the page and nothing else.
///   - Story 12.3 (FR-18, AD-4): Start takes an optional botName and queues a getMe reply that names it, so that the card's link follows
///     getMe and not the mock's default name. Start also saves the Refs of the code rows that exist, and Finish deletes every other code
///     row (the rows the page made during the test). CodeMark takes the marks of the stores that Codes searches before the page asks for
///     its first code. Codes reads back the session's code row and searches the production's stores (message headers and bodies, event
///     log, settings, sessions, live events and audit entries) for the plaintext codes: the server holds only their hashes. Issuing a code
///     writes nothing to most of those stores, so Codes first writes one probe to each through the product's own paths and checks that its
///     scan finds it, then removes the probes (the audit entry stays: the audit log is append-only). It returns "" or the first failed
///     check, which names the check and never a code.
Class OcuTalon.Test.Channel.TelegramPageFixture Extends %RegisteredObject
{

/// The live-test helpers.
Parameter CASE = "OcuTalon.Test.Channel.LiveCase";

/// The item the page's pause comes from.
Parameter ITEM = "TelegramIn";

/// The pause mark.
Parameter MARK = "telegramPaused";

/// The longest, in seconds, to wait for TelegramIn to record that it is on.
Parameter WAITON = 20;

/// The longest, in seconds, to wait for a long poll to be open.
Parameter WAITPOLL = 20;

/// The longest, in seconds, to wait for the pause mark after the 409 is queued.
Parameter WAITMARK = 5;

/// The longest, in seconds, to wait for TelegramIn to delete the mark once its time has passed.
Parameter WAITRESUME = 20;

/// Starts TelegramIn against the mock. The guards come first: the Bot API base is the mock's, the token is set, no TelegramIn job is live
/// and the production runs. Then StatusMonitor must be past its silent first run and the mock's Bot API side is reset. saved is what
/// Finish needs: it is set before TelegramIn is enabled, and again once its Enabled row is known. Returns "" once the Telegram state is on.
/// When botName is not empty, one getMe reply that names that bot is queued after the reset and before TelegramIn is enabled, so that the
/// user name /state shows is botName (the mock's default name otherwise). saved also holds the Refs of the code rows that exist now.
ClassMethod Start(Output saved As %String, botName As %String = "") As %String
{
	Set saved = ""
	Set rows = ""
	Set marks = ""
	Set since = 0
	Set codes = ""
	Try {
		Set mock = "OcuTalon.Test.Contract.Mock"
		Set reason = $ClassMethod(mock, "TelegramMissingReason", $SYSTEM.Util.GetEnviron($Parameter(mock, "TELEGRAMBASEVAR")), ..Token())
		If reason = "" Set reason = ##class(OcuTalon.Test.Channel.BotApi).PollerReason()
		If reason = "" Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).RunningReason()
		If reason '= "" Return reason
		If '$ClassMethod(..#CASE, "WaitMonitor") Return "StatusMonitor's job is not past its silent first run"
		Set sc = ##class(OcuTalon.Test.Channel.BotApi).Reset()
		If $$$ISERR(sc) Return $SYSTEM.Status.GetErrorText(sc)
		Set marks = $ClassMethod(..#CASE, "Marks")
		Set since = $ClassMethod(..#CASE, "InstanceSeq")
		Set codes = $ListBuild(1, ..CodeRefs())
		Set saved = ..Pack(rows, marks, since, codes)
		If botName '= "" {
			Set result = {"id": 424243, "is_bot": true, "first_name": "OcuTalon QR", "username": (botName)}
			Set reply = {"status": 200, "body": {"ok": true, "result": (result)}}
			If '##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "getMe", "replies": [(reply)]}) Return "the mock did not accept the getMe reply"
		}
		Set sc = $ClassMethod(..#CASE, "Enable", ..#ITEM, .rows)
		Set saved = ..Pack(rows, marks, since, codes)
		If $$$ISERR(sc) Return $SYSTEM.Status.GetErrorText(sc)
		If '$ClassMethod(..#CASE, "WaitState", "on", ..#WAITON) Return ..#ITEM_" did not record the state on within "_..#WAITON_" s"
	} Catch ex {
		If marks '= "" Set saved = ..Pack(rows, marks, since, codes)
		Return "Start failed: "_..Safe(ex)
	}
	Quit ""
}

/// Queues the 409 while a long poll is open and waits for the pause: until is the mark (a UTC time) and onset is the Seq of StatusMonitor's
/// onset event on the instance stream. Returns "" when both came.
ClassMethod Conflict(Output until As %String, Output onset As %Integer) As %String
{
	Set until = ""
	Set onset = 0
	Try {
		Set since = $ClassMethod(..#CASE, "InstanceSeq")
		If $ClassMethod(..#CASE, "WaitCalls", "getUpdates", 1, ..#WAITPOLL).%Size() < 1 Return "no long poll is open within "_..#WAITPOLL_" s"
		If '##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-conflict"}) Return "the mock did not accept the telegram-conflict scenario"
		If '$ClassMethod(..#CASE, "WaitMark", ..#MARK, 1, ..#WAITMARK) Return "the pause mark is not set within "_..#WAITMARK_" s of the 409"
		Set until = ##class(OcuTalon.Data.StatusMark).Get(..#MARK)
		Set onset = $ClassMethod(..#CASE, "WaitEvent", since, 1)
		If 'onset Return "StatusMonitor published no onset of the pause"
	} Catch ex {
		Return "Conflict failed: "_..Safe(ex)
	}
	Quit ""
}

/// Stands in for the elapsed pause: the mark is moved to seconds ahead, TelegramIn's first 200 deletes it, and clear is the Seq of
/// StatusMonitor's clear event after onset. Returns "" when both happened.
ClassMethod Resume(seconds As %Numeric, onset As %Integer, Output clear As %Integer) As %String
{
	Set clear = 0
	Try {
		Set until = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), seconds)
		Set sc = ##class(OcuTalon.Data.StatusMark).Record(..#MARK, until)
		If $$$ISERR(sc) Return $SYSTEM.Status.GetErrorText(sc)
		If '$ClassMethod(..#CASE, "WaitMark", ..#MARK, 0, ..#WAITRESUME) Return "TelegramIn did not delete the pause mark within "_..#WAITRESUME_" s"
		Set clear = $ClassMethod(..#CASE, "WaitEvent", onset, 0)
		If 'clear Return "StatusMonitor published no clear of the pause"
	} Catch ex {
		Return "Resume failed: "_..Safe(ex)
	}
	Quit ""
}

/// Puts back what Start saved, after any partial Start: TelegramIn is disabled and has no job, its Enabled row and the two Telegram marks
/// are as they were (the marks are read back and compared), the mock's Bot API side is reset (after the item has no job, as BotApi.Reset
/// requires), and StatusMonitor has published the clear of any pause. Every code row that Start did not find is deleted, after TelegramIn is
/// disabled (a saved that holds no list of code rows, or whose Start did not get as far as reading them, deletes none). Returns "" or the first reason something was not put back.
ClassMethod Finish(saved As %String) As %String
{
	If saved = "" Quit ""
	Set first = ""
	Try {
		Set list = $ZConvert($SYSTEM.Encryption.Base64Decode(saved), "I", "UTF8")
		Set rows = $List(list, 1)
		Set marks = $List(list, 2)
		Set since = $List(list, 3)
		If rows '= "" {
			Set sc = $ClassMethod(..#CASE, "Disable", ..#ITEM, rows)
			If $$$ISERR(sc) Set first = $SYSTEM.Status.GetErrorText(sc)
		}
		Set held = $Select($ListLength(list) > 3: $List(list, 4), 1: "")
		If held '= "" {
			Set reason = ..DropCodes($List(held, 2))
			If (reason '= "") && (first = "") Set first = reason
		}
		Do $ClassMethod(..#CASE, "PutMarks", marks)
		If ($ClassMethod(..#CASE, "Marks") '= marks) && (first = "") Set first = "the two Telegram marks are not as Start found them"
		Set sc = ##class(OcuTalon.Test.Channel.BotApi).Reset()
		If $$$ISERR(sc) && (first = "") Set first = $SYSTEM.Status.GetErrorText(sc)
		If '$ClassMethod(..#CASE, "WaitClear", since) && (first = "") Set first = "StatusMonitor published no clear of the pause"
	} Catch ex {
		If first = "" Set first = "Finish failed: "_..Safe(ex)
	}
	Quit first
}

/// The marks that Codes reads from, as one line of base64 without line breaks: the UTF-8 of $ListBuild(header mark, audit mark, live-event
/// mark, event-log mark). The spec takes it before the page asks for its first code.
ClassMethod CodeMark() As %String
{
	Quit $SYSTEM.Encryption.Base64Encode($ZConvert($ListBuild($ClassMethod(..#CASE, "HeaderMark"), ##class(OcuTalon.Test.Bridge.AuditLog).Now(), $ClassMethod(..#CASE, "LiveMark"), ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()), "O", "UTF8"), 1)
}

/// Checks the codes the page was given for the user's session, and searches the production for them. codes is comma-separated, in issue
/// order, and expiresAt is the last answer's, as the server sent it; mark is CodeMark's. Returns "" or the first failed check (CodeRow's
/// and CodeSearch's), which names the check and holds no code and no token.
ClassMethod Codes(mark As %String, user As %String, codes As %String, expiresAt As %String) As %String
{
	Try {
		Set list = $ZConvert($SYSTEM.Encryption.Base64Decode(mark), "I", "UTF8")
		If ($ListLength(list) '= 4) || (codes = "") Return "the mark or the codes are not as the fixture expects"
		Set reason = ..CodeRow(user, codes, expiresAt)
		If reason '= "" Return reason
	} Catch ex {
		Return "Codes failed: "_..Safe(ex)
	}
	Quit ..CodeSearch(list, codes)
}

/// The server side of the codes: the session's one code row holds the hash of the last code with the answer's expiry and is unused and
/// unpaired, the earlier codes' hashes find no row, and no column of any Pairing row holds any code.
ClassMethod CodeRow(user As %String, codes As %String, expiresAt As %String) As %String [ Private ]
{
	Try {
		Set session = ##class(OcuTalon.Data.Session).ForUser(user, .sc)
		If '$IsObject(session) Return "the session of the user could not be read"
		Set count = $Length(codes, ",")
		Set pairing = "OcuTalon.Data.Pairing"
		Set row = $ClassMethod(pairing, "ForCode", $ClassMethod(pairing, "HashCode", $Piece(codes, ",", count)))
		If '$IsObject(row) Return "no code row holds the hash of the last code"
		If row.CodeSessionRef '= session.Ref Return "the last code's row belongs to another session"
		If row.CodeExpiresAt '= expiresAt Return "the last code's row does not hold the answer's expiry"
		If row.CodeUsedAt '= "" Return "the last code's row is marked used"
		If (row.ChatId '= "") || (row.SessionRef '= "") Return "the last code's row is a chat or a pairing"
		Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Pairing WHERE CodeSessionRef = ?", session.Ref)
		Do rows.%Next()
		If +rows.%GetData(1) '= 1 Return "the session does not have exactly one code row"
		For i = 1:1:count {
			Set code = $Piece(codes, ",", i)
			If (i < count) && $IsObject($ClassMethod(pairing, "ForCode", $ClassMethod(pairing, "HashCode", code))) Return "the hash of code "_i_" still finds a row"
			Set held = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Pairing WHERE Ref [ ? OR SessionRef [ ? OR ChatId [ ? OR DisplayName [ ? OR CodeSessionRef [ ? OR CodeHash [ ? OR CodeExpiresAt [ ? OR CodeUsedAt [ ? OR ReplySlotAt [ ? OR SeenAt [ ? OR CreatedAt [ ?", code, code, code, code, code, code, code, code, code, code, code)
			Do held.%Next()
			If +held.%GetData(1) > 0 Return "a column of a Pairing row holds code "_i
		}
	} Catch ex {
		Return "the code row check failed: "_..Safe(ex)
	}
	Quit ""
}

/// The search for the plaintext codes, with a probe for every store (Story 12.3, Decided 10): the probes are written through the product's
/// paths first (CodeProbed checks that each scan finds its probe), then the probes are removed on every path (the audit entry stays).
/// list is CodeMark's list.
ClassMethod CodeSearch(list As %List, codes As %String) As %String [ Private ]
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set reason = ""
	Set probe = ""
	Set trace = ""
	Set unique = ""
	Try {
		Set number = $Increment(^OcuTalonTest("TelegramLive", "n"))
		Set unique = "zzcodes-"_number_"-"_##class(OcuTalon.Bridge.Ids).NewRef()
		Set probe = $ClassMethod(fixture, "Session", "zztgqr"_number)
		Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(probe).TraceRef
		Set reason = ..CodeProbed(list, codes, probe, "zzcodes"_number, unique)
	} Catch ex {
		Set reason = "the code search failed: "_..Safe(ex)
	}
	Try {
		If unique '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Text [ ?", unique)
		If trace '= "" Do $ClassMethod(fixture, "RemoveMessages", [(trace)])
		If probe '= "" Do $ClassMethod(fixture, "Clean", probe)
	} Catch {
	}
	Quit reason
}

/// Writes the probes (a command that reaches SessionOps for the probe session, an event-log row with the unique text, a live event with
/// the condition on the probe's stream, and a Pairing audit entry with the unique reason), checks that each scan finds its probe, and
/// then that no scan finds any code. Returns "" or the first failed check.
ClassMethod CodeProbed(list As %List, codes As %String, probe As %String, condition As %String, unique As %String) As %String [ Private ]
{
	Set case = ..#CASE
	Set scan = "OcuTalon.Test.Agent.KeyScan"
	Set runner = "OcuTalon.Test.Agent.RunnerFixture"
	Set log = "OcuTalon.Test.Bridge.AuditLog"
	Set headers = $List(list, 1), audit = $List(list, 2), liveMark = $List(list, 3), events = $List(list, 4)

	Set command = ##class(OcuTalon.Msg.Command.Unpair).%New()
	Set command.SessionRef = probe
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
	If $$$ISERR(sc) Return "the probe command was not submitted"
	Do ##class(Ens.Util.Log).LogInfo("OcuTalon.Test.Channel.TelegramPageFixture", "CodeSearch", unique)
	Set status = ##class(OcuTalon.Live.Payload.Status).%New()
	Set status.Condition = condition
	Set status.Active = 1
	Set sc = ##class(OcuTalon.Live.Publish).Publish(probe, "status", status)
	If $$$ISERR(sc) Return "the probe live event was not published"
	Set data = {"irisUser": "zztgqr", "sessionRef": "", "channel": "telegram", "change": "rejected", "reason": (unique)}
	If $$$ISERR(##class(OcuTalon.Bridge.Audit).Record("Pairing", data)) Return "the probe audit entry was not written"

	If $ClassMethod(scan, "Find", ##class(OcuTalon.Test.Contract.Mock).#TELEGRAMBASE) = "" Return "the key scan does not find the mock's base, which the settings hold"
	Set headerText = $ClassMethod(case, "RowsText", "SELECT * FROM Ens.MessageHeader WHERE ID > ?", headers)
	Set bodyText = $ClassMethod(case, "Bodies", headers)
	If '$Find(headerText, "SessionOps") Return "the header scan does not read the probe's headers"
	If '$Find(bodyText, probe) Return "the body scan does not read the probe's body"
	If $ClassMethod(runner, "LogRowsHolding", events, unique) '= 1 Return "the event-log scan does not find the probe's row"
	Set liveText = $ClassMethod(case, "RowsText", "SELECT Payload FROM OcuTalon_Live.Event WHERE %ID > ?", liveMark)
	If '$Find(liveText, condition) Return "the live-event scan does not read the probe's event"
	If $ClassMethod(log, "Wait", audit, "OcuTalon", "Pairing", "Pairing", unique, "", 1, 20).%Size() < 1 Return "the audit scan does not find the probe's entry"
	Set everything = $ClassMethod(log, "Entries", audit).%ToJSON()

	For i = 1:1:$Length(codes, ",") {
		Set code = $Piece(codes, ",", i)
		If $ClassMethod(scan, "Find", code) '= "" Return "the settings, item settings, event log or sessions hold code "_i
		If $Find(headerText, code) Return "a message header holds code "_i
		If $Find(bodyText, code) Return "a message body holds code "_i
		If $ClassMethod(runner, "LogRowsHolding", events, code) Return "the event log holds code "_i
		If $Find(liveText, code) Return "a live event holds code "_i
		If $Find(everything, code) Return "an audit entry holds code "_i
	}
	Quit ""
}

/// The Bot API token of this stack (the CI dummy), read from the environment (AD-19). For the spec's search of the page only.
ClassMethod Token() As %String
{
	Quit $SYSTEM.Util.GetEnviron(##class(OcuTalon.Test.Contract.Mock).#TELEGRAMTOKENVAR)
}

/// What Finish needs, as one line of base64 without line breaks: the UTF-8 of $ListBuild(rows, marks, since, codes), where codes is
/// "" until Start has read the code rows, and then $ListBuild(1, the list of the Refs of the code rows that Start found).
ClassMethod Pack(rows As %List, marks As %List, since As %Integer, codes As %List = "") As %String [ Private ]
{
	Quit $SYSTEM.Encryption.Base64Encode($ZConvert($ListBuild(rows, marks, since, codes), "O", "UTF8"), 1)
}

/// The Refs of every code row (a Pairing row with a CodeSessionRef), as a list.
ClassMethod CodeRefs() As %List [ Private ]
{
	Set refs = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Pairing WHERE CodeSessionRef IS NOT NULL AND CodeSessionRef <> ''")
	While result.%Next() {
		Set refs = refs _ $ListBuild(result.%GetData(1))
	}
	Quit refs
}

/// Deletes every code row whose Ref is not in keep (a list), and returns "" or the first reason one was not deleted.
ClassMethod DropCodes(keep As %List) As %String [ Private ]
{
	Set first = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Ref FROM OcuTalon_Data.Pairing WHERE CodeSessionRef IS NOT NULL AND CodeSessionRef <> ''")
	While result.%Next() {
		If $ListFind(keep, result.%GetData(2)) Continue
		Set sc = ##class(OcuTalon.Data.Pairing).%DeleteId(result.%GetData(1))
		If $$$ISERR(sc) && (first = "") Set first = "a code row was not deleted: "_$SYSTEM.Status.GetErrorText(sc)
	}
	Quit first
}

/// The text of an exception, in one line, with the token cut out (LiveCase.Cut).
ClassMethod Safe(ex As %Exception.AbstractException) As %String [ Private ]
{
	Quit $ClassMethod(..#CASE, "Cut", ex.DisplayString(), ..Token())
}

}
