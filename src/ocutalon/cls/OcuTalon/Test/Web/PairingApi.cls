/// Tests of POST /v1/pairing/code and DELETE /v1/pairing (Story 10.3; AD-1, AD-4, AD-13, AD-14, AD-17), called with stand-in request and
/// response objects and a CSP session whose OcuTalon.SessionRef is the fixture session (as Test.Web.DismissApi does), through the real
/// production: the unpair route submits through Commands.Submit, CommandsIn sends the Unpair to the real SessionOps, which audits, publishes
/// and sends its notice to Notify. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): where OcuTalon.Production does not run every
/// test fails with that reason, so that a broken stack can never give a green shard. ^OcuTalonTest("TelegramIncluded"), the telegramState
/// and telegramPaused marks are put back in OnAfterAllTests, and the fixture rows, events and the sessions' messages are removed.
/// With Telegram included, Notify sends the page notice to the disabled TelegramOut, where the item is queued (measured in Story 10.3): each
/// test that unpairs a paired session removes its own queued item with Ens.Queue (EnumerateItem and AbortItem) and checks that the queue is
/// as it was.
///   - TestSwitchOffAnswers404: with Included 0, whatever the Telegram state, both routes answer 404 not_found and nothing is read or written
///     (no code row, no command, no event);
///   - TestCodeRoute: with Included 1 and the state on, the route answers 200 {"code","expiresAt"}: a 22-character code and an expiry 600
///     seconds away, the session's code row holds only HashCode(code), and the code is in no Pairing column, no live event and no audit entry;
///     a second call replaces the hash; a Pair with the hash of the code pairs the chat;
///   - TestCodeRouteNotAvailable: the state off or rejected, or a pause in the future, answers 409 not_available with the matching text and
///     leaves the code row as it was; a pause in the past does not stop it;
///   - TestPageUnpair: the paired session's DELETE answers 200 {"result":"done"}, and the chat is unlinked through CommandsIn and SessionOps with
///     an audit entry (page, web), the pairing event, and the notice pairing.unpairedFromPage with the chat's ChatRef;
///   - TestPageUnpairNothingPaired: with nothing paired the answer is 200 {"result":"done"} and nothing is audited, published or sent;
///   - TestBodyNamesNoSession: a body that names another session and its chat unlinks the caller's own chat and changes nothing of theirs;
///   - TestNoSessionIs500: with no CSP session to take the OcuTalon session from, both routes answer 500 server_error and write nothing.
Class OcuTalon.Test.Web.PairingApi Extends %UnitTest.TestCase
{

/// The longest to wait for an event or an audit entry, in seconds.
Parameter SECONDS = 20;

/// The run's number.
Property Number As %Integer;

/// The count of chats made, for their chat ids.
Property Chats As %Integer [ InitialExpression = 0 ];

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 200);

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The TraceRefs of the fixture sessions, for the clean-up of the messages.
Property Traces As %DynamicArray;

/// The value of ^OcuTalonTest("TelegramIncluded") before the run, "" when it was absent.
Property SavedIncluded As %String;

/// The telegramState and telegramPaused marks before the run.
Property SavedState As %String(MAXLEN = 1000);

Property SavedPaused As %String(MAXLEN = 1000);

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("PairingApi", "n"))
	Set ..Traces = []
	Set ..Refs = ""
	Set ..Missing = ""
	Set ..SavedIncluded = $Get(^OcuTalonTest("TelegramIncluded"))
	Set ..SavedState = ##class(OcuTalon.Data.StatusMark).Get("telegramState")
	Set ..SavedPaused = ##class(OcuTalon.Data.StatusMark).Get("telegramPaused")
	If '##class(Ens.Director).IsProductionRunning(.name) || (name '= "OcuTalon.Production") {
		Set ..Missing = "OcuTalon.Production does not run in OCUTALON: this class runs in throwaways and CI only (Rule 21)"
	}
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Set ^OcuTalonTest("TelegramIncluded") = 1
	Do ##class(OcuTalon.Data.StatusMark).RecordTelegram("on", "ocutalon_ci_bot")
	Do ##class(OcuTalon.Data.StatusMark).Record("telegramPaused", "")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	If ..SavedIncluded = "" {
		Kill ^OcuTalonTest("TelegramIncluded")
	} Else {
		Set ^OcuTalonTest("TelegramIncluded") = ..SavedIncluded
	}
	Do ##class(OcuTalon.Data.StatusMark).Record("telegramState", ..SavedState)
	Do ##class(OcuTalon.Data.StatusMark).Record("telegramPaused", ..SavedPaused)
	If ..Missing = "" Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Traces, "OCUTALON")
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
}

/// With Included 0 both routes answer 404 not_found, before anything is read: the state on and a paired session change nothing. No code
/// row is made, no command reaches SessionOps, and the paired chat stays paired.
Method TestSwitchOffAnswers404()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set chat = ..PairedChat(session)
	Set ^OcuTalonTest("TelegramIncluded") = 0
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set body = ..Call("POST", .response)
	Do $$$AssertEquals(response.Status_"|"_body, "404 Not Found|"_..ErrorBody("not_found", ##class(OcuTalon.Web.Api).#MESSAGENOTFOUND), "POST /pairing/code is 404 not_found")
	Set body = ..Call("DELETE", .response)
	Do $$$AssertEquals(response.Status_"|"_body, "404 Not Found|"_..ErrorBody("not_found", ##class(OcuTalon.Web.Api).#MESSAGENOTFOUND), "DELETE /pairing is 404 not_found")
	Do $$$AssertEquals(..CodeRows(session), 0, "no code row was made")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, session, "the paired chat stays paired")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Pairing", "Pairing", session).%Size(), 0, "no Pairing entry names the session")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "pairing").%Size(), 0, "no pairing event was published")
	Hang 1
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "CommandsIn", "SessionOps").%Size(), 0, "and no command went to SessionOps")
}

/// With Included 1 and the state on, POST /pairing/code answers 200 {"code","expiresAt"}. The code is 22 characters of [A-Za-z0-9_-], the
/// expiry is 600 seconds from now in UTC, the session's code row holds HashCode(code) and no column holds the code, and neither a live event
/// nor an audit entry written meanwhile does. A second call replaces the hash (one row), and a Pair with the hash of the code pairs.
Method TestCodeRoute()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set chat = ..NewChat("Dana")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Set body = ..Call("POST", .response)
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "200 JSON")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(..Keys(answer), "code,expiresAt", "the body is {code, expiresAt}")
	Set code = answer.code
	Do $$$AssertTrue(code ? 22(1AN,1"-",1"_"), "the code is 22 characters of [A-Za-z0-9_-]: "_$Length(code))
	Do $$$AssertTrue((##class(OcuTalon.Data.Time).AddSeconds(before, 600) '] answer.expiresAt) && (answer.expiresAt '] ##class(OcuTalon.Data.Time).AddSeconds(after, 600)), "expiresAt is now plus 600 seconds, UTC: "_answer.expiresAt)
	Set row = ##class(OcuTalon.Data.Pairing).ForCode(##class(OcuTalon.Data.Pairing).HashCode(code))
	Do $$$AssertTrue($IsObject(row), "the session's code row holds the hash of the code")
	If '$IsObject(row) Quit
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	Do $$$AssertEquals(row.CodeSessionRef_"|"_row.CodeExpiresAt_"|"_row.CodeUsedAt_"|"_row.ChatId_"|"_row.SessionRef, session_"|"_answer.expiresAt_"|||", "for the session, with the expiry, unused, with no chat and no session")
	Set first = row.CodeHash
	Set row = ""
	Do $$$AssertEquals($Length(first), 43, "the hash is 43 characters")
	Do $$$AssertEquals(..ColumnsHold(code), 0, "no Pairing column of any row holds the code")
	Set events = ##class(OcuTalon.Live.Event).Since(session, 0)
	Do $$$AssertTrue(events.%ToJSON() '[ code, "no live event holds the code")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "", "", code).%Size(), 0, "and no audit entry does")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Pairing(session, .sc), "", "the session is not paired by a code")

	Set second = {}.%FromJSON(..Call("POST", .response))
	Do $$$AssertEquals(response.Status, "200 OK", "a second call is 200")
	Do $$$AssertTrue(second.code '= code, "with another code")
	Do $$$AssertEquals(..CodeRows(session), 1, "still one code row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).ForCode(first), "", "the first hash finds nothing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).ForCode(##class(OcuTalon.Data.Pairing).HashCode(second.code)).CodeSessionRef, session, "the second hash is the session's")

	Set command = ##class(OcuTalon.Msg.Command.Pair).%New()
	Set command.CodeHash = ##class(OcuTalon.Data.Pairing).HashCode(second.code)
	Set command.ChatRef = chat
	Do $$$AssertStatusOK(##class(OcuTalon.Core.Commands).Submit(command, "telegram", .result), "a Pair with the hash is submitted")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|paired", "and pairs the chat")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, session, "the chat is on the session")
}

/// A state of off or rejected is 409 not_available with MESSAGETELEGRAMOFF, a pause in the future is 409 not_available with
/// MESSAGETELEGRAMPAUSED; neither changes the code row. A pause that has passed does not stop the route.
Method TestCodeRouteNotAvailable()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set answer = {}.%FromJSON(..Call("POST", .response))
	Set hash = ##class(OcuTalon.Data.Pairing).HashCode(answer.code)
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Adopt(##class(OcuTalon.Data.Pairing).ForCode(hash))
	Set expiry = ##class(OcuTalon.Data.Pairing).ForCode(hash).CodeExpiresAt
	For state = "off", "rejected" {
		Do ##class(OcuTalon.Data.StatusMark).RecordTelegram(state, "")
		Set body = ..Call("POST", .response)
		Do $$$AssertEquals(response.Status_"|"_body, "409 Conflict|"_..ErrorBody("not_available", ##class(OcuTalon.Web.Api).#MESSAGETELEGRAMOFF), "the state "_state_": 409 not_available")
	}
	Do ##class(OcuTalon.Data.StatusMark).RecordTelegram("on", "ocutalon_ci_bot")
	Do ##class(OcuTalon.Data.StatusMark).Record("telegramPaused", ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 300))
	Set body = ..Call("POST", .response)
	Do $$$AssertEquals(response.Status_"|"_body, "409 Conflict|"_..ErrorBody("not_available", ##class(OcuTalon.Web.Api).#MESSAGETELEGRAMPAUSED), "a pause in the future: 409 not_available")
	Do $$$AssertEquals(..CodeRows(session)_"|"_##class(OcuTalon.Data.Pairing).ForCode(hash).CodeExpiresAt, "1|"_expiry, "the code row is as it was")
	Do ##class(OcuTalon.Data.StatusMark).Record("telegramPaused", ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -30))
	Set body = ..Call("POST", .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a pause that has passed does not stop it")
}

/// DELETE /pairing for a paired session, with Telegram included: 200 {"result":"done"}; the chat is unlinked through CommandsIn and SessionOps
/// with an unlinked entry (page, web), the not-paired event, and the Notification pairing.unpairedFromPage with the chat's ChatRef, which
/// Notify sends to TelegramOut alone. The test removes the queued TelegramOut item it caused, and the queue is as it was.
Method TestPageUnpair()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set chat = ..NewChat("Dana")
	Set code = ..Code(session, .hash)
	Set command = ##class(OcuTalon.Msg.Command.Pair).%New()
	Set command.CodeHash = hash
	Set command.ChatRef = chat
	Do ##class(OcuTalon.Core.Commands).Submit(command, "telegram", .result)
	Do $$$AssertEquals(result.Outcome, "paired", "control: the chat is paired")
	Set queued = +##class(Ens.Queue).GetCount("TelegramOut")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set body = ..Call("DELETE", .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType_"|"_body, "200 OK|application/json|{""result"":""done""}", "200 {result: done}")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, "", "the chat is unlinked")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Pairing(session, .sc), "", "and the session has no pairing")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Pairing", "Pairing", session, "", 1, ..#SECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one Pairing entry names the session")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.change_"|"_entries.%Get(0).data.reason_"|"_entries.%Get(0).data.channel_"|"_entries.%Get(0).data.irisUser, "unlinked|page|web|"_$Username, "unlinked, page, on web, by the session's user")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "pairing", 2, ..#SECONDS).%Size(), 2, "two pairing events: paired, then not paired")
	Do $$$AssertEquals(..Hops(trace, "CommandsIn", "SessionOps"), 1, "the Unpair went from CommandsIn to SessionOps, in the session's SuperSession")
	Do ..WaitHops(trace, "Notify", "TelegramOut", 1)
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "SessionOps", "Notify")
	Do $$$AssertEquals(sent.%Size(), 1, "one Notification goes from SessionOps to Notify")
	If sent.%Size() = 1 {
		Set notification = ##class(OcuTalon.Msg.Notification).%OpenId(sent.%Get(0).bodyId)
		Do $$$AssertEquals(notification.SessionRef_"|"_notification.ChatRef_"|"_notification.Kind_"|"_notification.CatalogKey, session_"|"_chat_"|pairing|pairing.unpairedFromPage", "with the ChatRef and the key")
	}
	Set toTelegram = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "Notify", "TelegramOut")
	Do $$$AssertEquals(toTelegram.%Size(), 1, "Notify sends it to TelegramOut alone")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "Notify", "WebChatOut").%Size(), 0, "and not to the web chat")
	Do ..AbortQueued("TelegramOut", trace)
	Do $$$AssertEquals(+##class(Ens.Queue).GetCount("TelegramOut"), queued, "the item it queued for TelegramOut is removed")
}

/// DELETE /pairing for a session with nothing paired: 200 {"result":"done"}, and nothing is audited, published or sent.
Method TestPageUnpairNothingPaired()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set body = ..Call("DELETE", .response)
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""done""}", "200 {result: done}")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Pairing", "Pairing", session).%Size(), 0, "no Pairing entry")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "pairing").%Size(), 0, "no pairing event")
	Do $$$AssertEquals(..Hops(trace, "CommandsIn", "SessionOps"), 1, "the command reached SessionOps")
	Do $$$AssertEquals(..Hops(trace, "SessionOps", "Notify"), 0, "and no Notification was sent")
}

/// A body that names another session and its chat is not read: the other session's pairing stays, and the caller's own is unlinked. The
/// test removes the queued TelegramOut item that the caller's page notice caused, and the queue is as it was.
Method TestBodyNamesNoSession()
{
	If '..Guard() Quit
	Set mine = ..Session()
	Set trace = ..TraceOf(mine)
	Set theirs = ##class(OcuTalon.Test.Data.Fixture).Session("zzpairapi"_..Number_"other")
	Set ..Refs = ..Refs_","_theirs
	Do ..Keep(theirs)
	Set theirChat = ..PairedChat(theirs)
	Set myChat = ..PairedChat(mine)
	Set queued = +##class(Ens.Queue).GetCount("TelegramOut")
	Set body = ..Call("DELETE", .response, "{""sessionRef"":"""_theirs_""",""chatRef"":"""_theirChat_"""}")
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""done""}", "200 {result: done}")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(myChat).SessionRef, "", "the caller's own chat is unlinked")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(theirChat).SessionRef, theirs, "the other session's pairing stays")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(theirs, "pairing").%Size(), 0, "and it got no event")
	Do ..WaitHops(trace, "Notify", "TelegramOut", 1)
	Do ..AbortQueued("TelegramOut", trace)
	Do $$$AssertEquals(+##class(Ens.Queue).GetCount("TelegramOut"), queued, "the item the page notice queued for TelegramOut is removed")
}

/// With no CSP session to take the OcuTalon session from, both routes answer 500 server_error, and no code row is made.
Method TestNoSessionIs500()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set rowsBefore = ..CodeRows(session)
	For method = "POST", "DELETE" {
		Set body = ..Call(method, .response, "", 1)
		Do $$$AssertEquals(response.Status, "500 Internal Server Error", method_": the answer is 500")
		Do $$$AssertEquals(body, ..ErrorBody("server_error", ##class(OcuTalon.Web.Api).#MESSAGESERVERERROR), method_": server_error")
	}
	Do $$$AssertEquals(..CodeRows(session), rowsBefore, "and no code row was made")
}

/// --- helpers ---
/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// The fixture session of the IRIS user who runs the tests (the user that Ownership.SessionRef resolves the CSP session for).
Method Session() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Do ..Keep(ref)
	Set ..Current = ref
	Quit ref
}

/// The session that the stand-in CSP session is bound to.
Property Current As %String;

/// Keeps the session's TraceRef for the clean-up of the messages.
Method Keep(ref As %String) [ Private ]
{
	Do ..Traces.%Push(..TraceOf(ref))
}

/// The TraceRef of the session.
Method TraceOf(ref As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef
}

/// The next chat id of the run.
Method NextChatId() As %String [ Private ]
{
	Set ..Chats = ..Chats + 1
	Quit "75"_..Number_"0"_..Chats
}

/// A chat row with the name, recorded for the clean-up. Returns its ChatRef.
Method NewChat(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Data.Pairing).RecordChat(..NextChatId(), name, .sc)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_##class(OcuTalon.Test.Data.Fixture).Adopt(##class(OcuTalon.Data.Pairing).Chat(ref))
	Quit ref
}

/// A chat row on the session (a fixture link), recorded for the clean-up. Returns its ChatRef.
Method PairedChat(session As %String) As %String [ Private ]
{
	Set ref = ..NewChat("Dana")
	Set row = ##class(OcuTalon.Data.Pairing).Chat(ref)
	Set row.SessionRef = session
	Do row.%Save()
	Quit ref
}

/// Stores a code for the session (the route's own work, done here so that a Pair can use it) and records its row. Returns the code, and its
/// hash in hash.
Method Code(session As %String, Output hash As %String) As %String [ Private ]
{
	Set code = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set hash = ##class(OcuTalon.Data.Pairing).HashCode(code)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Pairing).StoreCode(session, hash, ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)), "a code is stored")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_##class(OcuTalon.Test.Data.Fixture).Adopt(##class(OcuTalon.Data.Pairing).ForCode(hash))
	Quit code
}

/// Calls the pairing route as the CSP session of the current session, through Written; method is POST or DELETE, body the request's
/// content; response is the %response and the result is what the route wrote. With noSession the call has no CSP session at all.
Method Call(method As %String, Output response, body As %String = "", noSession As %Boolean = 0) As %String [ Private ]
{
	New %request, %response, %session
	Set application = "/ocutalon/api/"
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall(application, method)
	If body '= "" {
		Set stream = ##class(%CSP.CharacterStream).%New()
		Do stream.Write(body)
		Do stream.Rewind()
		Set %request.Content = stream
	}
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	If 'noSession {
		Set %session = ##class(%CSP.Session).%New("ZzPairingApi"_..Number, 0)
		Set %session.Data("OcuTalon.SessionRef") = ..Current
	}
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Api", "Pairing")
	Do $$$AssertStatusOK(sc, "Pairing returns OK")
	Set response = %response
	Quit written
}

/// The error body of the route for the code and the message.
Method ErrorBody(code As %String, message As %String) As %String [ Private ]
{
	Quit {"error": {"code": (code), "message": (message)}}.%ToJSON()
}

/// The member names of the object, comma-separated.
Method Keys(object As %DynamicObject) As %String [ Private ]
{
	Set keys = ""
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Quit keys
}

/// The number of code rows of the session.
Method CodeRows(session As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Pairing WHERE CodeSessionRef = ?", session)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// 1 when any column of any Pairing row holds the text.
Method ColumnsHold(text As %String) As %Boolean [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Pairing WHERE Ref [ ? OR SessionRef [ ? OR ChatId [ ? OR DisplayName [ ? OR CodeSessionRef [ ? OR CodeHash [ ? OR CodeExpiresAt [ ? OR CodeUsedAt [ ? OR ReplySlotAt [ ? OR SeenAt [ ? OR CreatedAt [ ?", text, text, text, text, text, text, text, text, text, text, text)
	Do rs.%Next()
	Quit +rs.%GetData(1) > 0
}

/// The number of requests from the source item to the target item in the trace session of the session.
Method Hops(trace As %String, source As %String, target As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, source, target).%Size()
}

/// Waits up to SECONDS seconds until count requests have gone from the source item to the target item.
Method WaitHops(trace As %String, source As %String, target As %String, count As %Integer) [ Private ]
{
	Set end = $ZHorolog + ..#SECONDS
	For {
		If (..Hops(trace, source, target) >= count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
}

/// Aborts the items in the queue whose message belongs to the trace's SuperSession (the test's own), and no other item.
Method AbortQueued(queue As %String, superSession As %String) [ Private ]
{
	Set rs = ##class(%ResultSet).%New("Ens.Queue:EnumerateItem")
	Set sc = rs.Execute(queue)
	Kill found
	While rs.Next() {
		Set header = ##class(Ens.MessageHeader).%OpenId(rs.Get("MessageId"))
		If $IsObject(header) && (header.SuperSession = superSession) Set found($Increment(found)) = $ListBuild(rs.Get("Priority"), rs.Get("Index"))
	}
	For i = 1:1:+$Get(found) {
		Do $$$AssertStatusOK(##class(Ens.Queue).AbortItem(queue, $List(found(i), 1), $List(found(i), 2)), "the queued item is aborted")
	}
}

}
