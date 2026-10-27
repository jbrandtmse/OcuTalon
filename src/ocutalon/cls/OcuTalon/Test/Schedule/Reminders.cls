Include Ensemble

/// End-to-end tests of the reminders over the running production (Story 8.3; AD-1, AD-5, AD-12, AD-14, AD-18, AD-26, AD-32, FR-34, NFR-10).
/// THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the running OcuTalon.Production, which a slot never has. Where
/// the production does not run, every test fails with that reason. A reminder is set through Test.Schedule.ReminderFixture, which
/// submits a SetReminder under a bridge context as the chat's tool does. CI asserts order and outcome and never seconds: a reminder is
/// never created before its due time, and one notification arrives per channel.
///   - TestSetAndWaiting: a reminder due in 12 seconds is one pending row, one live waiter in a trace session of its own, one
///     created event and a row of the rail with its trace link; then a row that is no longer pending ends the waiter and sends nothing;
///   - TestFiresOnEveryChannel: a reminder due in 5 seconds fires once: the row is fired, one Notification goes to Notify, which sends
///     it to the web chat and the simulated phone (not to Telegram), each leaves one card and one event, and the Telegram route is
///     checked on Notify's rule with a fixture pairing.
/// The guard, the fixture sessions, the run's number (^OcuTalonTest("Reminders","n")) and the clean-up are those of
/// Test.Core.InProduction; OnAfterOneTest removes the test's reminders with everything the product made for them (ReminderFixture.Remove)
/// and puts the Telegram test switch back.
Class OcuTalon.Test.Schedule.Reminders Extends OcuTalon.Test.Core.InProduction
{

/// The start of the user name of each fixture session.
Parameter SESSIONPREFIX = "zzprodrem";

/// Seconds to wait for a reminder's waiter to end after its due time.
Parameter FIRESECONDS = 30;

/// Seconds to wait for what the product leaves.
Parameter WAIT = 20;

/// The Refs of the reminders of the running test, comma-separated.
Property Reminders As %String(MAXLEN = "");

/// The test switch for Telegram before a test changed it, "" while it is as it was found.
Property TelegramWas As %String;

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Reminders, ",") {
		Set ref = $Piece(..Reminders, ",", i)
		If ref '= "" Do ##class(OcuTalon.Test.Schedule.ReminderFixture).Remove(ref)
	}
	Set ..Reminders = ""
	If ..TelegramWas '= "" Do ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(..TelegramWas)
	Set ..TelegramWas = ""
	Quit $$$OK
}

/// Sets a reminder of the session and keeps its Ref for the clean-up.
Method SetReminder(session As %String, text As %String, seconds As %Integer) As %DynamicObject [ Private ]
{
	Set found = ##class(OcuTalon.Test.Schedule.ReminderFixture).Set(session, text, seconds)
	If found.ref '= "" Set ..Reminders = ..Reminders _ $Select(..Reminders = "": "", 1: ",") _ found.ref
	Quit found
}

/// The ReminderTimer instances with the Ref, as an array of their ids.
ClassMethod Timers(ref As %String) As %DynamicArray [ Private ]
{
	Set ids = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Schedule.ReminderTimer WHERE Ref = ?", ref)
	While result.%Next() {
		Do ids.%Push(result.%Get("ID"))
	}
	Quit ids
}

/// 1 when the ReminderTimer is waiting: not completed, not terminated, and still waiting for a response.
ClassMethod IsWaiting(id As %String) As %Boolean [ Private ]
{
	Set timer = ##class(OcuTalon.Schedule.ReminderTimer).%OpenId(id)
	If '$IsObject(timer) Quit 0
	Quit 'timer.%IsCompleted && 'timer.%IsTerminated && (timer.%MasterPendingResponses.Count() > 0)
}

/// Waits until no ReminderTimer with the Ref is waiting any more (a completed waiter is deleted by the framework), for at most seconds.
/// Answers 1 when none is.
ClassMethod WaitEnded(ref As %String, seconds As %Integer) As %Boolean [ Private ]
{
	Set end = $ZHorolog + seconds
	For {
		Set timers = ..Timers(ref)
		Set waiting = 0
		For i = 0:1:timers.%Size() - 1 {
			If ..IsWaiting(timers.%Get(i)) Set waiting = waiting + 1
		}
		If 'waiting || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit 'waiting
}

/// The seconds since 1840 of a header's TimeCreated (UTC to the second).
ClassMethod CreatedSeconds(headerId As %String) As %Integer [ Private ]
{
	Set header = ##class(Ens.MessageHeader).%OpenId(headerId)
	Quit ##class(OcuTalon.Data.Time).Seconds($Translate($Piece(header.TimeCreated, ".", 1), " ", "T") _ "Z")
}

/// The action list that the rule returns for the message, evaluated on a shadow instance of the routing engine as the router does; an
/// error is returned as "ERROR <text>".
Method Route(rule As %String, document As %RegisteredObject) As %String [ Private ]
{
	Set engine = ##class(Ens.Host).GetShadowInstance("class||EnsLib.MsgRouter.RoutingEngine", .sc)
	If '$IsObject(engine) Quit "ERROR "_$SYSTEM.Status.GetErrorText(sc)
	Set engine.Document = document
	Set engine.MsgClass = $ClassName(document)
	Set engine.Source = "zzsource"
	Set sc = ##class(Ens.Rule.RuleDefinition).EvaluateRulesEx(rule, 0, engine, "", .return, .reason, 1, "e")
	If $SYSTEM.Status.IsError(sc) Quit "ERROR "_$SYSTEM.Status.GetErrorText(sc)
	Quit $Get(return)
}

/// A reminder due in 12 seconds: the result, one pending row, the created event, the start header that begins the waiter's own trace
/// session under the session's TraceRef, the timer request, a live waiter, the command's answer in the command's session and the
/// rail row with its trace link. Then the row is cancelled: the waiter ends at its due time, sends nothing and publishes nothing.
Method TestSetAndWaiting()
{
	If '..Guard() Quit
	Set session = ..Session("set")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set text = "zz stretch " _ ..Number
	Set found = ..SetReminder(session, text, 12)
	Do $$$AssertEquals(found.ok_"|"_found.outcome, "1|set", "the SetReminder is carried out")
	If found.ref = "" Quit
	Do $$$AssertTrue($Match(found.dueAt, "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"), "the result has the due time, UTC to the second")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(found.ref)
	Do $$$AssertTrue($IsObject(row), "the row exists")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.SessionRef_"|"_row.Text_"|"_row.DueAt_"|"_row.State_"|"_row.Late, session_"|"_text_"|"_found.dueAt_"|pending|0", "a pending row with the values of the command")
	Do $$$AssertTrue($Match(row.CreatedAt, "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"), "created at a UTC time")
	Do $$$AssertTrue(row.TraceHeaderId > 0, "the row keeps its waiter's header id")
	Do $$$AssertEquals(row.TraceHeaderId, found.traceHeaderId, "the fixture read the same id")
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Reminder WHERE SessionRef = ?", session)
	Do rows.%Next()
	Do $$$AssertEquals(rows.%GetData(1), 1, "the session has exactly one reminder row")

	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "reminder", 1, ..#WAIT)
	Do $$$AssertEquals(events.%Size(), 1, "one reminder event is published")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.text_"|"_payload.dueAt_"|"_payload.state_"|"_payload.late, found.ref_"|"_text_"|"_found.dueAt_"|pending|0", "the event is the pending reminder")
		Do $$$AssertEquals(payload.traceHeaderId_"|"_payload.traceNamespace, found.traceHeaderId_"|"_$Namespace, "the event carries its trace target")
	}

	Set waiter = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(found.traceHeaderId)
	Do $$$AssertTrue(waiter.%Size() > 0, "the waiter's session has headers")
	If waiter.%Size() > 0 {
		Set start = waiter.%Get(0)
		Do $$$AssertEquals(start.id_"|"_start.sessionId, found.traceHeaderId_"|"_found.traceHeaderId, "the start header is the row's header and begins its own session")
		Do $$$AssertEquals(start.type_"|"_start.source_"|"_start.target_"|"_start.superSession, "1|ReminderOps|ReminderTimer|"_trace, "from ReminderOps to ReminderTimer, under the session's TraceRef")
		Do $$$AssertEquals(start.bodyClass, "OcuTalon.Schedule.ReminderStart", "the body is a ReminderStart")
		Set body = ##class(OcuTalon.Schedule.ReminderStart).%OpenId(start.bodyId)
		Do $$$AssertEquals(body.Ref, found.ref, "naming the reminder")
	}
	Set alarms = ##class(OcuTalon.Test.Data.Fixture).Between(waiter, 1, "ReminderTimer", "Ens.Alarm")
	Do $$$AssertEquals(alarms.%Size(), 1, "one request goes from ReminderTimer to Ens.Alarm in that session")
	If alarms.%Size() = 1 {
		Do $$$AssertEquals(alarms.%Get(0).id, found.alarmHeaderId, "the fixture read the same header")
		Do $$$AssertTrue((alarms.%Get(0).status = 2) || (alarms.%Get(0).status = 3), "and it is pending: queued or delivered (status " _ alarms.%Get(0).status _ ")")
	}
	Set timers = ..Timers(found.ref)
	Do $$$AssertEquals(timers.%Size(), 1, "one ReminderTimer has the Ref")
	If timers.%Size() = 1 Do $$$AssertEquals(..IsWaiting(timers.%Get(0)), 1, "and it is live")

	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set commands = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "CommandsIn", "ReminderOps")
	Set answers = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 2, "ReminderOps", "CommandsIn")
	Do $$$AssertEquals(commands.%Size()_"|"_answers.%Size(), "1|1", "one command reaches ReminderOps and one answer comes back")
	If (commands.%Size() = 1) && (answers.%Size() = 1) {
		Do $$$AssertEquals(answers.%Get(0).sessionId, commands.%Get(0).sessionId, "ReminderOps' answer is in the command's session")
		Do $$$AssertTrue(answers.%Get(0).sessionId '= found.traceHeaderId, "and not in the waiter's")
	}

	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(session))
	Set listed = ""
	For i = 0:1:body.rail.reminders.%Size() - 1 {
		If body.rail.reminders.%Get(i).ref = found.ref Set listed = body.rail.reminders.%Get(i)
	}
	Do $$$AssertTrue($IsObject(listed), "the rail lists the reminder")
	If $IsObject(listed) {
		Do $$$AssertEquals(listed.traceHeaderId_"|"_listed.traceNamespace, found.traceHeaderId_"|"_$Namespace, "the rail row carries its trace target")
		Do $$$AssertEquals(listed.traceUrl, "/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID="_found.traceHeaderId, "and the link to its session in Visual Trace")
	}

	Set row.State = "cancelled"
	Do $$$AssertStatusOK(row.%Save(), "the row is cancelled")
	Set row = ""
	Do $$$AssertTrue(..WaitEnded(found.ref, ..#FIRESECONDS), "the waiter ends after its due time")
	Set waiter = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(found.traceHeaderId)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(waiter, 1, "ReminderTimer", "Notify").%Size(), 0, "it sent nothing to Notify")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "reminder").%Size(), 1, "and published no second event")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(found.ref)
	Do $$$AssertEquals(row.State_"|"_row.Late, "cancelled|0", "the row is as it was left")
}

/// A reminder due in 5 seconds fires once on every channel: the row is fired, the waiter sends one Notification to Notify, Notify
/// sends it to the web chat and the simulated phone and not to Telegram, each leaves one card and one event, and none is created
/// before the due time. With Telegram included and a fixture pairing, Notify's rule sends the same Notification to Telegram too.
Method TestFiresOnEveryChannel()
{
	If '..Guard() Quit
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Demo).Mode(), 1, "demo mode is on")
	Set session = ..Session("fire")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set text = "zz stretch " _ ..Number
	Set found = ..SetReminder(session, text, 5)
	Do $$$AssertEquals(found.ok_"|"_found.outcome, "1|set", "the SetReminder is carried out")
	If found.ref = "" Quit
	Set due = ##class(OcuTalon.Data.Time).Seconds(found.dueAt)
	Do $$$AssertTrue(..WaitEnded(found.ref, ..#FIRESECONDS), "the waiter ends within "_..#FIRESECONDS_" seconds")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(found.ref)
	Do $$$AssertEquals(row.State, "fired", "the row is fired")
	Set waiter = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(found.traceHeaderId)
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(waiter, 1, "ReminderTimer", "Notify")
	Do $$$AssertEquals(sent.%Size(), 1, "one request goes from ReminderTimer to Notify")
	If sent.%Size() < 1 Quit
	Set key = $Select(row.Late: "reminder.late", 1: "reminder.due")
	Set notification = ##class(OcuTalon.Msg.Notification).%OpenId(sent.%Get(0).bodyId)
	Do $$$AssertEquals(notification.Kind_"|"_notification.CatalogKey_"|"_notification.SessionRef, "reminder|"_key_"|"_session, "a reminder Notification for the session, with the key that agrees with Late")
	Set slots = $Select(row.Late: "{""time"":"""_found.dueAt_""",""text"":"""_text_""",""dueAt"":"""_found.dueAt_"""}", 1: "{""text"":"""_text_""",""dueAt"":"""_found.dueAt_"""}")
	Do $$$AssertEquals(notification.Slots, slots, "with the UTC slots")
	Do $$$AssertTrue(..CreatedSeconds(sent.%Get(0).id) >= due, "created no earlier than the due time")

	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "Notify", "WebChatOut", 1, ..#WAIT), "WebChatOut has handled the Notification")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "Notify", "SimPhoneOut", 1, ..#WAIT), "SimPhoneOut has handled it")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(found.traceHeaderId)
	Set toWeb = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Notify", "WebChatOut")
	Set toPhone = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Notify", "SimPhoneOut")
	Set toTelegram = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Notify", "TelegramOut")
	Do $$$AssertEquals(toWeb.%Size()_"|"_toPhone.%Size()_"|"_toTelegram.%Size(), "1|1|0", "Notify sends one request to the web chat and one to the phone, and none to Telegram")
	For i = 0:1:toWeb.%Size() - 1 Do $$$AssertEquals(toWeb.%Get(i).status_"|"_toWeb.%Get(i).isError, "9|0", "the web chat's request is completed with no error")
	For i = 0:1:toPhone.%Size() - 1 Do $$$AssertEquals(toPhone.%Get(i).status_"|"_toPhone.%Get(i).isError, "9|0", "the phone's request is completed with no error")

	Set onlineDemo = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set cards = ##class(OcuTalon.Data.Ownership).RecentNotices(session, 10)
	Do $$$AssertEquals(cards.Count(), 1, "the session has one web card")
	If cards.Count() = 1 {
		Set card = cards.GetAt(1)
		Do $$$AssertEquals(card.Kind_"|"_card.DueAt, "reminder|"_found.dueAt, "a reminder card with the due time")
		Do $$$AssertEquals(card.Text, ##class(OcuTalon.Msg.Catalog).RenderAt(key, slots, "web", card.RecordedAt, onlineDemo), "with the catalog text for the web")
		Do $$$AssertTrue(##class(OcuTalon.Data.Time).Seconds(card.RecordedAt) >= due, "recorded no earlier than the due time")
	}
	Set phone = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10)
	Do $$$AssertEquals(phone.Count(), 1, "the session has one phone message")
	If phone.Count() = 1 {
		Do $$$AssertEquals(phone.GetAt(1).Text, ##class(OcuTalon.Msg.Catalog).RenderAt(key, slots, "phone", phone.GetAt(1).CreatedAt, onlineDemo), "with the catalog text for the phone")
		Do $$$AssertTrue(##class(OcuTalon.Data.Time).Seconds(phone.GetAt(1).CreatedAt) >= due, "created no earlier than the due time")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "notification", 1, ..#WAIT).%Size(), 1, "one notification event is published")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "phone", 1, ..#WAIT).%Size(), 1, "and one phone event")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "reminder", 2, ..#WAIT)
	Set states = ""
	For i = 0:1:events.%Size() - 1 Set states = states _ $Select(states = "": "", 1: ",") _ events.%Get(i).payload.state
	Do $$$AssertEquals(states, "pending,fired", "and the reminder events are pending, then fired")

	Set body = ##class(OcuTalon.Msg.Notification).%OpenId(sent.%Get(0).bodyId)
	Set ..TelegramWas = ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(1)
	Do $$$AssertEquals(..Route("OcuTalon.Core.Rule.Notify", body), "send:WebChatOut,SimPhoneOut:", "Telegram included but not paired: Notify's rule sends to the web chat and the phone")
	Set pairing = ##class(OcuTalon.Test.Data.Fixture).Pairing(session)
	Set ..Refs = ..Refs _ "," _ pairing
	Do $$$AssertEquals(..Route("OcuTalon.Core.Rule.Notify", body), "send:WebChatOut,SimPhoneOut,TelegramOut:", "paired: Notify's rule sends the same Notification to Telegram too")
}

}
