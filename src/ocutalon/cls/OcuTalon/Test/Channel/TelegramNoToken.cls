/// The token search of the Telegram items (Story 12.2; NFR-11, AD-14, AD-19). THIS TEST RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21),
/// like OcuTalon.Test.Channel.LiveCase, which it extends: it runs every failure path of the items against the CI mock and its dummy token,
/// and then looks for the token in every place that could hold it. The paths are a rejected start, a 409 (with its pause onset on the
/// instance stream), a 429 for getUpdates, a 429 for sendMessage that ends in an error status, a client call to a closed port, and a client
/// call to the mock with no token. The places are the production's settings and item settings, the event log and the saved sessions
/// (KeyScan.Find), the %Status texts that the paths returned, the message headers and the exported bodies since the mark, the audit entries
/// since the mark, the live events since the mark, and the body of /state. Every scan has a positive control, a value that its store does
/// hold, so that a scan that cannot read its store is not read as clean:
///   - KeyScan.Find: the base of the mock, which the ApiBase rows hold;
///   - the %Status texts: the three texts are read, and the closed-port error carries its method name;
///   - the message headers: the test's messages to TelegramOut;
///   - the message bodies: the test's unique text in the Outbound body;
///   - the audit entries: a Pairing entry that the test writes through the product's audit writer with a unique reason;
///   - the live events: the pause time in StatusMonitor's onset;
///   - /state: ocutalon_ci_bot.
Class OcuTalon.Test.Channel.TelegramNoToken Extends OcuTalon.Test.Channel.LiveCase
{

Parameter API = "OcuTalon.Channel.Telegram.Api";

/// The statuses' texts that the paths returned, as a list.
Property Texts As %String(MAXLEN = "") [ Private ];

/// Every text of every row of a SELECT that names its columns, as one text.
ClassMethod RowsText(sql As %String, mark As %Integer) As %String [ Private ]
{
	Set text = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, sql, mark)
	While result.%Next() {
		For column = 1:1:result.%ResultColumnCount {
			Set text = text _ result.%GetData(column) _ $Char(10)
		}
	}
	Quit text
}

/// The exported body of every message header after the mark, as one text.
ClassMethod Bodies(mark As %Integer) As %String [ Private ]
{
	Set text = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE ID > ?", mark)
	While result.%Next() {
		Set class = result.%GetData(1)
		Set id = result.%GetData(2)
		If (class = "") || (id = "") Continue
		Try {
			Set body = $ClassMethod(class, "%OpenId", id)
			If $IsObject(body) {
				Set xml = ""
				If body.%Extends("%XML.Adaptor") && $$$ISOK(body.XMLExportToString(.xml)) Set text = text _ xml _ $Char(10)
			}
		} Catch {
			Set text = text _ "body not readable: " _ class _ $Char(10)
		}
	}
	Quit text
}

/// Keeps the text of a status for the scan.
Method Keep(sc As %Status) [ Private ]
{
	Set ..Texts = ..Texts _ $ListBuild($SYSTEM.Status.GetErrorText(sc))
}

/// The token is in none of the places, and every scan finds what its store holds.
Method TestNoTokenAnywhere()
{
	If '..ReadyLive() Quit
	Set var = $Parameter(..#API, "TOKENVAR")
	Set since = ..InstanceSeq()
	Try {
		Set session = ..FixtureSession("zztgtok")
		Set token = ..Token
		Do $$$AssertTrue(token '= "", "this stack has the dummy token")
		Do $$$AssertTrue(..WaitMonitor(), "StatusMonitor's job is past its silent first run")
		Set since = ..InstanceSeq()
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set headers = ..HeaderMark()
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set liveMark = ..LiveMark()
		Set unique = "zznotoken "_##class(OcuTalon.Bridge.Ids).NewRef()
		Set ..Texts = ""

		// A rejected start.
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-getme-rejected"}), "a rejected getMe is queued")
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Do $$$AssertTrue(..WaitState("rejected", 20), "the start is rejected")
		Do $$$AssertStatusOK(..StopItems(), "TelegramIn is stopped")

		// A 409, with its onset, and /state while the item runs.
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled again")
		Do $$$AssertTrue(..WaitState("on", 20), "the state becomes on")
		Do $$$AssertTrue(..WaitCalls("getUpdates", 1, 20).%Size() >= 1, "a long poll is open")
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-conflict"}), "a 409 is queued")
		Do $$$AssertTrue(..WaitMark("telegramPaused", 1, 5), "the pause mark is set")
		Set paused = ##class(OcuTalon.Data.StatusMark).Get("telegramPaused")
		Set onset = ..WaitEvent(since, 1)
		Do $$$AssertTrue(onset > 0, "StatusMonitor publishes the onset")
		Set state = ##class(OcuTalon.Web.Api).StateBody(session).%ToJSON()

		// A 429 for getUpdates.
		Do ##class(OcuTalon.Data.StatusMark).Record("telegramPaused", "")
		Set polls = ..CallsOf("getUpdates").%Size()
		Do $$$AssertTrue(..WaitCalls("getUpdates", polls + 1, 10).%Size() > polls, "TelegramIn polls again after the pause")
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-updates-busy"}), "a 429 for getUpdates is queued")
		Set deadline = $ZHorolog + 10
		For {
			Set told = ##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(log, "asked TelegramIn to wait")
			If told || ($ZHorolog >= deadline) Quit
			Hang 0.25
		}
		Do $$$AssertTrue(told > 0, "TelegramIn handled the 429")
		Do $$$AssertStatusOK(..StopItems(), "TelegramIn is stopped again")

		// A 429 for sendMessage, which ends in an error status.
		Set ref = ##class(OcuTalon.Data.Pairing).RecordChat(8507, "", .sc)
		Do ..Chat(8507)
		Do $$$AssertStatusOK(sc, "the fixture chat has a row")
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-rate-limited"}), "a 429 for sendMessage is queued")
		Set message = ##class(OcuTalon.Msg.Outbound).%New()
		Set message.ChatRef = ref
		Set message.Text = unique
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", message, .response), "the limited message is sent after one retry")
		Set limited = {"status": 429, "body": {"ok": false, "error_code": 429, "description": "Too Many Requests: retry after 1", "parameters": {"retry_after": 1}}}
		Set replies = []
		For i = 1:1:5 Do replies.%Push(limited)
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "sendMessage", "replies": (replies)}), "five 429s are queued")
		Set message = ##class(OcuTalon.Msg.Outbound).%New()
		Set message.ChatRef = ref
		Set message.Text = unique_" again"
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", message, .response)
		Do $$$AssertStatusNotOK(sc, "five 429s end in an error status")
		Do ..Keep(sc)
		Do $$$AssertStatusOK(..StopItems(), "TelegramOut is stopped")

		// A call to a closed port, and a call to the mock with no token.
		Set answer = $ClassMethod(..#API, "Call", "http://127.0.0.1:1", "", "getMe", {}, 2, .code, .sc)
		Do $$$AssertStatusNotOK(sc, "a call to a closed port is an error")
		Do ..Keep(sc)
		Set closed = $SYSTEM.Status.GetErrorText(sc)
		Do $ClassMethod("OcuTalon.Test.Agent.KeyScan", "UnsetEnv", var)
		Set base = $SYSTEM.Util.GetEnviron($Parameter(..#MOCK, "TELEGRAMBASEVAR"))
		Set answer = $ClassMethod(..#API, "Call", base, "", "getMe", {}, 2, .code, .sc)
		Do $ClassMethod("OcuTalon.Test.Agent.KeyScan", "SetEnv", var, token)
		Do $$$AssertStatusNotOK(sc, "a call with no token is an error")
		Do ..Keep(sc)

		// A positive control for the audit scan: an entry of the product's own writer with a unique reason.
		Set reason = "zz-notoken-"_$Increment(^OcuTalonTest("TelegramLive", "n"))
		Set data = {"irisUser": "zztgtok", "sessionRef": "", "channel": "telegram", "change": "rejected", "reason": (reason)}
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Audit).Record("Pairing", data), "a Pairing entry is written")

		// The scans.
		Set found = ##class(OcuTalon.Test.Agent.KeyScan).Find(token)
		Do $$$AssertEquals($ListToString(found, ", "), "", "the settings, item settings, event log and sessions hold no token")
		Set control = ##class(OcuTalon.Test.Agent.KeyScan).Find(##class(OcuTalon.Test.Contract.Mock).#TELEGRAMBASE)
		Do $$$AssertTrue($ListLength(control) > 0, "the key scan finds the mock's base, which the ApiBase rows hold")

		Set texts = ..Texts
		Set holds = 0, position = 0
		While $ListNext(texts, position, text) {
			If $Find(text, token) Set holds = holds + 1
		}
		Do $$$AssertEquals(holds, 0, "no %Status text holds the token")
		Do $$$AssertEquals($ListLength(texts), 3, "the status scan reads the three texts that the paths returned")
		Do $$$AssertTrue($Find(closed, "getMe") > 0, "and the status scan reads a text that names its method")

		Set headerText = ..RowsText("SELECT * FROM Ens.MessageHeader WHERE ID > ?", headers)
		Set bodyText = ..Bodies(headers)
		Do $$$AssertEquals($Find(headerText, token), 0, "no message header holds the token")
		Do $$$AssertTrue($Find(headerText, "TelegramOut") > 0, "and the header scan reads the headers of the test's messages")
		Do $$$AssertEquals($Find(bodyText, token), 0, "no message body holds the token")
		Do $$$AssertTrue($Find(bodyText, unique) > 0, "and the body scan reads the Outbound body of the test")

		Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(audit, "OcuTalon", "Pairing", "Pairing", reason, "", 1, 20)
		Do $$$AssertEquals(entries.%Size(), 1, "the audit scan reads the entry that the test wrote")
		Set everything = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(audit).%ToJSON()
		Do $$$AssertEquals($Find(everything, token), 0, "no audit entry since the mark holds the token")

		Set liveText = ..RowsText("SELECT Payload FROM OcuTalon_Live.Event WHERE %ID > ?", liveMark)
		Do $$$AssertEquals($Find(liveText, token), 0, "no live event since the mark holds the token")
		Do $$$AssertTrue($Find(liveText, paused) > 0, "and the live-event scan reads the pause time of StatusMonitor's onset")

		Do $$$AssertEquals($Find(state, token), 0, "the body of /state holds no token")
		Do $$$AssertTrue($Find(state, "ocutalon_ci_bot") > 0, "and it holds the bot's name")
	} Catch ex {
		Do $$$AssertTrue(0, "the token search failed: "_..Safe(ex))
	}
	Do $ClassMethod("OcuTalon.Test.Agent.KeyScan", "SetEnv", var, ..Token)
	Do ..Cleanup()
	Do $$$AssertTrue(..WaitClear(since), "StatusMonitor has published the clear of the test's pause")
}

/// The highest id of the live events: the mark that the live-event scan reads from.
ClassMethod LiveMark() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(%ID) FROM OcuTalon_Live.Event")
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
