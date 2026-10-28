Include Ensemble

/// End-to-end tests of the reminders over the running production (Stories 8.3 and 8.4; AD-1, AD-4, AD-5, AD-12, AD-14, AD-18, AD-26, AD-32, FR-34, NFR-10).
/// THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the running OcuTalon.Production, which a slot never has. Where
/// the production does not run, every test fails with that reason. A reminder is set through Test.Schedule.ReminderFixture, which
/// submits a SetReminder under a bridge context as the chat's tool does. CI asserts order and outcome and never seconds: a reminder is
/// never created before its due time, and one notification arrives per channel.
///   - TestSetAndWaiting: a reminder due in 12 seconds is one pending row, one live waiter in a trace session of its own, one
///     created event and a row of the rail with its trace link; then a row that is no longer pending ends the waiter and sends nothing;
///   - TestFiresOnEveryChannel: a reminder due in 5 seconds fires once: the row is fired, one Notification goes to Notify, which sends
///     it to the web chat and the simulated phone (not to Telegram), each leaves one card and one event, and the Telegram route is
///     checked on Notify's rule with a fixture pairing.
///   - TestSetByDelayAndLocal: the set tool, under a bridge context, with a delay and with a local time sets a pending reminder with a
///     waiter and a created event; a blank text is refused with the owner's Message and makes nothing;
///   - TestListToolReadsTheList: the list tool gives the session's two pending reminders in due order, not a fired or a cancelled one
///     and not another session's (DW-135);
///   - TestCancelEndsWaiter: the cancel tool cancels the reminder, its waiter ends at once, long before its due time, the event reaches
///     the rail, and the trigger is in the waiter's session under the session's TraceRef;
///   - TestCancelInterruptFails: a trigger that cannot be sent is a warning, and the reminder is still cancelled and its waiter ends
///     at its due time without a notification;
///   - TestCancelIsolationAndRepeats: another session's, an unknown, a fired and a cancelled reminder are refused no_reminder and nothing
///     changes; a repeated cancel key gets the first result, and a key for another reminder is reused_key;
///   - TestSetKeyOfAnotherSession and TestCancelKeyOfAnotherSession (AD-4): a key that another session used finds nothing and reveals
///     nothing: a set is a fresh set (never reused_key); a cancel with the other session's Ref gets the unknown-Ref refusal, member for
///     member, and with its own Ref cancels it normally; the session's own command again gets its first result;
///   - TestSetRepeatOneWaiter: a SetReminder submitted twice with one key makes one row, one waiter and one created event;
///   - TestSeveralCancelsFromOneToolCall (U-118): three cancels of one tool call, with the keys <item>:1 to :3, each cancel their own
///     reminder; the call run again gets each command its first result, and with the Refs in another order a key for another Ref is
///     reused_key;
///   - TestReconcileRearmsOnlyLostWaiters (Story 8.5, AC 1): Reminder.Reconcile starts one new waiter, in a trace session of its own under
///     the session's TraceRef, for a pending row that never had one and for one whose waiter ended, leaves a row with a live waiter, a
///     fired row and a cancelled row alone, starts nothing the second time, and the re-armed reminder then fires once, not late;
///   - TestReconcileFiresLateWhenDueWhileDown (AC 2): a pending row past its due time with no waiter fires once after Reconcile, late,
///     with the reminder.late text on the web and the phone;
///   - TestTwoWaitersFireOnce (AC 4): an old and a re-armed waiter of one row both wake, and one notification per channel and one fired
///     event result;
///   - TestReconcileSkipsReminderWithoutSession: a pending row whose session is gone is skipped and named, and nothing is started;
///   - TestRearmWithoutSessionFails: Rearm of a row whose session is gone answers an error that names the Ref and starts nothing;
///   - TestLiveWaiterRule: a ReminderTimer that is completed or terminated with a response pending, or that waits for no response, is
///     not a live waiter, and one that waits is;
///   - TestReconcileWithoutProductionDoesNothing: with the production stopped (the scheduler settled first), Reconcile is OK and skips
///     nothing; the production is started again by the test;
///   - TestReconcileOnlyRowsInTheList (QA): a pending row with no waiter that is not in the list of Refs is left alone;
///   - TestReconcileTriesEveryRowAndNamesFailures (QA): when ReminderTimer cannot take a start (its item is disabled), Reconcile tries
///     every row, answers an error that names each Ref, skips none and leaves the rows pending; the item is enabled again by the test,
///     which waits until it has handled the queued starts.
/// The guard, the fixture sessions, the run's number (^OcuTalonTest("Reminders","n")) and the clean-up are those of
/// Test.Core.InProduction; OnAfterOneTest removes the test's reminders with everything the product made for them (ReminderFixture.Remove)
/// and puts the Telegram test switch back. Where the production ran when the class began, it also enables ReminderTimer again and starts
/// the production again when a test left them off; where it did not (Guard), it never starts one.
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
	If (..Missing = "") && '##class(Ens.Director).IsItemEnabled("ReminderTimer") Do ##class(Ens.Director).EnableConfigItem("ReminderTimer", 1, 1)
	For i = 1:1:$Length(..Reminders, ",") {
		Set ref = $Piece(..Reminders, ",", i)
		If ref '= "" Do ##class(OcuTalon.Test.Schedule.ReminderFixture).Remove(ref)
	}
	Set ..Reminders = ""
	If (..Missing = "") && '##class(Ens.Director).IsProductionRunning() Do ##class(OcuTalon.Install.Step.Production).Start()
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
	Quit ##class(OcuTalon.Test.Schedule.ReminderFixture).Timers(ref)
}

/// 1 when the ReminderTimer is waiting: not completed, not terminated, and still waiting for a response.
ClassMethod IsWaiting(id As %String) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Test.Schedule.ReminderFixture).IsWaiting(id)
}

/// Waits until no ReminderTimer with the Ref is waiting any more, for at most seconds. Answers 1 when none is.
ClassMethod WaitEnded(ref As %String, seconds As %Integer) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Test.Schedule.ReminderFixture).WaitEnded(ref, seconds)
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

/// Keeps the Ref of a reminder that a tool made, for the clean-up, and returns it.
Method Keep(ref As %String) As %String [ Private ]
{
	If ref '= "" Set ..Reminders = ..Reminders _ $Select(..Reminders = "": "", 1: ",") _ ref
	Quit ref
}

/// The states of the session's reminder events, comma-separated, in order.
ClassMethod EventStates(session As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).States(##class(OcuTalon.Test.Core.Observe).Events(session, "reminder"))
}

/// The number of headers in the trace session from the source item to the target item (requests).
ClassMethod RequestsBetween(traceHeaderId As %String, source As %String, target As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(traceHeaderId), 1, source, target).%Size()
}

/// The number of Reminder rows of the session.
ClassMethod Rows(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Reminder WHERE SessionRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The text of the Message of the refusal no_reminder.
Parameter NOREMINDER = "This session has no pending reminder with that ref; it may have fired or been cancelled already. Nothing was cancelled.";

/// The set tool with a delay and with a local time: each is a pending row with one waiting waiter and one created event, the delay
/// counts from the arrival of the command, and the local time is converted by Data.Time.FromLocal. A blank text is refused with the
/// owner's Message, unchanged, and makes no row.
Method TestSetByDelayAndLocal()
{
	If '..Guard() Quit
	Set session = ..Session("delay")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Schedule.ReminderFixture).Begin(session), "the context begins")
	Set text = "zz delay " _ ..Number
	Set a = ##class(OcuTalon.Tools.ReminderTools).SetReminder(text, 30)
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Set text2 = "zz local " _ ..Number
	Set local = ##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).AddSeconds(before, 40))
	Set b = ##class(OcuTalon.Tools.ReminderTools).SetReminder(text2, "", local)
	Set c = ##class(OcuTalon.Tools.ReminderTools).SetReminder("", 30)
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Keep(a.ref), ..Keep(b.ref)
	Do $$$AssertEquals(a.ok, 1, "the delay is set")
	Do $$$AssertEquals(b.ok, 1, "the local time is set")
	If (a.ref = "") || (b.ref = "") Quit
	Set rowA = ##class(OcuTalon.Data.Reminder).RefIndexOpen(a.ref)
	Do $$$AssertTrue((rowA.DueAt '] ##class(OcuTalon.Data.Time).AddSeconds(after, 30)) && (##class(OcuTalon.Data.Time).AddSeconds(before, 30) '] rowA.DueAt), "the delay counts from the arrival: " _ rowA.DueAt)
	Do $$$AssertEquals(rowA.State_"|"_rowA.SessionRef_"|"_rowA.Text, "pending|" _ session _ "|" _ text, "a pending row of the session")
	Set rowB = ##class(OcuTalon.Data.Reminder).RefIndexOpen(b.ref)
	Do $$$AssertEquals(rowB.DueAt, ##class(OcuTalon.Data.Time).FromLocal(local), "the local time is converted by FromLocal")
	Do $$$AssertEquals(rowB.State, "pending", "a pending row")
	For ref = a.ref, b.ref {
		Set timers = ..Timers(ref)
		Do $$$AssertEquals(timers.%Size(), 1, "one ReminderTimer has the Ref")
		If timers.%Size() = 1 Do $$$AssertEquals(..IsWaiting(timers.%Get(0)), 1, "and it is waiting")
	}
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "reminder", 2, ..#WAIT)
	Do $$$AssertEquals(..EventStates(session), "pending,pending", "one created event each")
	Do $$$AssertEquals(a.message, "The reminder is set.", "the tool passes the message on")
	Do $$$AssertEquals(c.ok, 0, "a blank text is refused")
	Do $$$AssertEquals(c.message, "The reminder has no text, so nothing was set.", "with the owner's Message unchanged")
	Do $$$AssertEquals(..Rows(session), 2, "and makes no row")
}

/// The list tool gives the session's two pending reminders, the sooner first; a fired and a cancelled one of the session and a pending
/// one of another session are not in it.
Method TestListToolReadsTheList()
{
	If '..Guard() Quit
	Set a = ..Session("lista")
	Set b = ..Session("listb")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Schedule.ReminderFixture).Begin(a), "the context begins")
	Set slow = ##class(OcuTalon.Tools.ReminderTools).SetReminder("zz slow " _ ..Number, 300)
	Set fast = ##class(OcuTalon.Tools.ReminderTools).SetReminder("zz fast " _ ..Number, 200)
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Keep(slow.ref), ..Keep(fast.ref)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set ..Refs = ..Refs _ "," _ ##class(OcuTalon.Test.Data.Fixture).Reminder(a, ##class(OcuTalon.Data.Time).AddSeconds(now, 100), "fired")
	Set ..Refs = ..Refs _ "," _ ##class(OcuTalon.Test.Data.Fixture).Reminder(a, ##class(OcuTalon.Data.Time).AddSeconds(now, 150), "cancelled")
	Set other = ..SetReminder(b, "zz other " _ ..Number, 250)
	Do $$$AssertEquals(slow.ok_"|"_fast.ok_"|"_other.ok, "1|1|1", "the reminders are set")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Schedule.ReminderFixture).Begin(a), "the context begins")
	Set listed = ##class(OcuTalon.Tools.ReminderTools).ListReminders()
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(listed.ok, 1, "the list is read, never NOTREAD")
	If listed.ok '= 1 Quit
	Do $$$AssertEquals(listed.reminders.%Size(), 2, "two reminders")
	If listed.reminders.%Size() = 2 {
		Do $$$AssertEquals(listed.reminders.%Get(0).ref_"|"_listed.reminders.%Get(1).ref, fast.ref_"|"_slow.ref, "the session's pending reminders, the sooner first")
	}
}

/// The cancel tool ends the waiter at once: the answer confirms with the Ref and the due time, the row is cancelled with the call's key,
/// no ReminderTimer with the Ref waits any more, long before its due time, the events are created, then cancelled, the rail has no row
/// for it, and ReminderOps sent one trigger in the waiter's session under the session's TraceRef for the alarm's handle. That the
/// interrupted waiter sends nothing is TestCancelInterruptFails', which waits past the due time.
Method TestCancelEndsWaiter()
{
	If '..Guard() Quit
	Set session = ..Session("cancel")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set found = ..SetReminder(session, "zz cancel " _ ..Number, 120)
	Do $$$AssertEquals(found.ok_"|"_found.outcome, "1|set", "the reminder is set")
	If found.ref = "" Quit
	Set item = "zzcancelitem" _ ..Number
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Schedule.ReminderFixture).Begin(session, item), "the context begins")
	Set answer = ##class(OcuTalon.Tools.ReminderTools).CancelReminder(found.ref)
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(answer.ok_"|"_answer.message_"|"_answer.ref, "1|The reminder is cancelled.|" _ found.ref, "the answer confirms with the Ref")
	Do $$$AssertEquals(answer.dueLocal, ##class(OcuTalon.Data.Time).ToLocal(found.dueAt), "and the due time")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(found.ref)
	Do $$$AssertEquals(row.State_"|"_row.CancelKey, "cancelled|" _ item _ ":1", "the row is cancelled with the call's key")
	Set row = ""
	Do $$$AssertTrue(..WaitEnded(found.ref, 10), "the waiter ends within 10 seconds, long before its due time")
	Set waiter = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(found.traceHeaderId)
	Do ##class(OcuTalon.Test.Core.Observe).Events(session, "reminder", 2, ..#WAIT)
	Do $$$AssertEquals(..EventStates(session), "pending,cancelled", "the events are created, then cancelled")
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(session))
	Set listed = 0
	For i = 0:1:body.rail.reminders.%Size() - 1 {
		If body.rail.reminders.%Get(i).ref = found.ref Set listed = 1
	}
	Do $$$AssertEquals(listed, 0, "the rail has no row for it")
	Set triggers = ##class(OcuTalon.Test.Data.Fixture).Between(waiter, 1, "ReminderOps", "Ens.Alarm")
	Do $$$AssertEquals(triggers.%Size(), 1, "the waiter's session holds one request from ReminderOps to Ens.Alarm")
	If triggers.%Size() = 1 {
		Set trigger = triggers.%Get(0)
		Do $$$AssertEquals(trigger.bodyClass_"|"_trigger.superSession, "Ens.AlarmTriggerRequest|" _ trace, "an Ens.AlarmTriggerRequest under the session's TraceRef")
		Set handle = ##class(Ens.AlarmTriggerRequest).%OpenId(trigger.bodyId).AlarmHandle
		Do $$$AssertEquals(handle, ##class(Ens.MessageHeader).%OpenId(found.alarmHeaderId).MessageBodyId, "for the alarm request of the waiter")
	}
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set commands = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "CommandsIn", "ReminderOps")
	Set answers = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 2, "ReminderOps", "CommandsIn")
	Do $$$AssertEquals(commands.%Size()_"|"_answers.%Size(), "2|2", "the set and the cancel each reach ReminderOps and are answered")
}

/// A trigger that cannot be sent (ReminderOpsSendProbe with Mode error, a shadow instance): the reminder is still cancelled with one
/// cancelled event, one warning names the Ref, the one send went to Ens.Alarm in the waiter's session under the TraceRef with the
/// alarm's handle, the operation's own session id and SuperSession are as they were, and the waiter ends at its due time and sends
/// nothing.
Method TestCancelInterruptFails()
{
	If '..Guard() Quit
	Set session = ..Session("intfail")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set found = ..SetReminder(session, "zz interrupt " _ ..Number, 12)
	Do $$$AssertEquals(found.ok_"|"_found.outcome, "1|set", "the reminder is set")
	If found.ref = "" Quit
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Schedule.ReminderOpsSendProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(probe) Quit
	Set probe.Mode = "error"
	Set probe.%SessionId = 4711
	Set probe.%SuperSession = "zzbefore"
	Set command = ##class(OcuTalon.Msg.Command.CancelReminder).%New()
	Set command.SessionRef = session
	Set command.ReminderRef = found.ref
	Set command.IdempotencyKey = "zzintfail" _ ..Number
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set response = ""
	Set sc = probe.OnMessage(command, .response)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|cancelled", "the answer is cancelled")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(found.ref)
	Do $$$AssertEquals(row.State, "cancelled", "the row is cancelled")
	Set traceId = row.TraceHeaderId
	Set row = ""
	Do ##class(OcuTalon.Test.Core.Observe).Events(session, "reminder", 2, ..#WAIT)
	Do $$$AssertEquals(..EventStates(session), "pending,cancelled", "with one cancelled event")
	Set start = "OcuTalon.Schedule.ReminderOps: the waiter of " _ found.ref _ " was not interrupted"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Text %STARTSWITH ?", mark, start)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "one warning names the Ref")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Text %STARTSWITH ?", mark, start)
	Do $$$AssertEquals(probe.SeenAsync.%Size(), 1, "one send was made")
	If probe.SeenAsync.%Size() = 1 {
		Set seen = probe.SeenAsync.%Get(0)
		Do $$$AssertEquals(seen.target_"|"_seen.handle_"|"_seen.sessionId_"|"_seen.superSession, "Ens.Alarm|" _ ##class(Ens.MessageHeader).%OpenId(found.alarmHeaderId).MessageBodyId _ "|" _ traceId _ "|" _ trace, "to Ens.Alarm, for the alarm's handle, in the waiter's session under the TraceRef")
	}
	Do $$$AssertEquals(probe.%SessionId_"|"_probe.%SuperSession, "4711|zzbefore", "the operation's session id and SuperSession are put back")
	Do $$$AssertTrue(..WaitEnded(found.ref, ..#FIRESECONDS), "the waiter ends after its due time")
	Set waiter = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(found.traceHeaderId)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(waiter, 1, "ReminderTimer", "Notify").%Size(), 0, "and sent nothing to Notify")
}

/// Another session's, an unknown, a fired and a cancelled reminder are refused no_reminder and nothing changes; a repeated cancel key
/// gets the first result with one event and one trigger; a key that names another reminder is reused_key.
Method TestCancelIsolationAndRepeats()
{
	If '..Guard() Quit
	Set a = ..Session("isoa")
	Set b = ..Session("isob")
	Set first = ..SetReminder(a, "zz first " _ ..Number, 300)
	Set second = ..SetReminder(a, "zz second " _ ..Number, 310)
	Do $$$AssertEquals(first.ok_"|"_second.ok, "1|1", "the reminders are set")
	If (first.ref = "") || (second.ref = "") Quit
	Set fixture = "OcuTalon.Test.Schedule.ReminderFixture"
	Set noReminder = "0|refused|" _ ..#NOREMINDER
	Do $$$AssertStatusOK($ClassMethod(fixture, "Begin", b), "the context of the other session begins")
	Set foreign = ##class(OcuTalon.Tools.ReminderTools).CancelReminder(first.ref)
	Set unknown = ##class(OcuTalon.Tools.ReminderTools).CancelReminder("zznosuchreminder")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(foreign.ok_"|"_foreign.message, "0|" _ ..#NOREMINDER, "another session's Ref is refused no_reminder")
	Do $$$AssertEquals(unknown.ok_"|"_unknown.message, foreign.ok_"|"_foreign.message, "an unknown Ref gets the same answer")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(first.ref)
	Do $$$AssertEquals(row.State, "pending", "the reminder is still pending")
	Set row = ""
	Set timers = ..Timers(first.ref)
	Do $$$AssertEquals(timers.%Size(), 1, "with its waiter")
	If timers.%Size() = 1 Do $$$AssertEquals(..IsWaiting(timers.%Get(0)), 1, "waiting")
	Do $$$AssertEquals(..EventStates(a), "pending,pending", "and no event was published")
	Set key = "zzisokey" _ ..Number
	Set done = $ClassMethod(fixture, "Cancel", a, first.ref, key)
	Do $$$AssertEquals(done.ok_"|"_done.outcome_"|"_done.ref_"|"_done.dueAt, "1|cancelled|" _ first.ref _ "|" _ first.dueAt, "the owner cancels with the key")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(first.ref)
	Do $$$AssertEquals(row.State_"|"_row.CancelKey, "cancelled|" _ key, "the row holds the key")
	Set row = ""
	Set again = $ClassMethod(fixture, "Cancel", a, first.ref, key)
	Do $$$AssertEquals(again.ok_"|"_again.outcome_"|"_again.ref_"|"_again.dueAt, done.ok_"|"_done.outcome_"|"_done.ref_"|"_done.dueAt, "the same key again gets the first result")
	Do $$$AssertEquals(..EventStates(a), "pending,pending,cancelled", "with one cancelled event")
	Do $$$AssertEquals(..RequestsBetween(##class(OcuTalon.Data.Reminder).RefIndexOpen(first.ref).TraceHeaderId, "ReminderOps", "Ens.Alarm"), 1, "and one trigger")
	Set other = $ClassMethod(fixture, "Cancel", a, first.ref, "zznewkey" _ ..Number)
	Do $$$AssertEquals(other.ok_"|"_other.outcome_"|"_other.message, noReminder, "a new key for the cancelled reminder is no_reminder")
	Set firedRef = ##class(OcuTalon.Test.Data.Fixture).Reminder(a, ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 100), "fired")
	Set ..Refs = ..Refs _ "," _ firedRef
	Set fired = $ClassMethod(fixture, "Cancel", a, firedRef)
	Do $$$AssertEquals(fired.ok_"|"_fired.outcome_"|"_fired.message, noReminder, "and so is a fired reminder")
	Set reused = $ClassMethod(fixture, "Cancel", a, second.ref, key)
	Do $$$AssertEquals(reused.ok_"|"_reused.outcome_"|"_reused.message, "0|refused|This call reused the key of a different earlier call, so nothing was done.", "the key for another reminder is reused_key")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(second.ref)
	Do $$$AssertEquals(row.State, "pending", "which stays pending")
	Set row = ""
	Do $$$AssertEquals(..EventStates(a), "pending,pending,cancelled", "with no event")
}

/// Submits a SetReminder of the session with the key, the text and a delay in seconds, under the session's bridge context, keeps the
/// Ref of a reminder that it makes for the clean-up, and returns the CommandResult ("" when no answer came back).
Method SetKeyed(session As %String, key As %String, text As %String, seconds As %Integer) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SetReminder).%New()
	Set command.SessionRef = session
	Set command.IdempotencyKey = key
	Set command.Text = text
	Set command.DelaySeconds = seconds
	Set result = ##class(OcuTalon.Test.Schedule.ReminderFixture).Submit(session, command)
	If $IsObject(result) Do ..Keep(result.Ref)
	Quit result
}

/// A SetReminder carrying the IdempotencyKey of another session's reminder, with other fields, is a fresh set for its own session
/// (set, a new Ref, its own due time), never reused_key; the other session's reminder, row and waiter are untouched; the same command
/// again, while both sessions' rows hold the key, gets its own first result and makes no second row (AD-4, AD-1: a key is looked up
/// in the command's own session only).
Method TestSetKeyOfAnotherSession()
{
	If '..Guard() Quit
	Set a = ..Session("fsetkeya")
	Set b = ..Session("fsetkeyb")
	Set key = "zzfsetkey" _ ..Number
	Set theirText = "zz theirs " _ ..Number, myText = "zz mine " _ ..Number
	Set theirs = ..SetKeyed(b, key, theirText, 300)
	Set mine = ..SetKeyed(a, key, myText, 310)
	Do $$$AssertTrue($IsObject(theirs) && $IsObject(mine), "both commands are answered")
	If '$IsObject(theirs) || '$IsObject(mine) Quit
	Do $$$AssertEquals(theirs.Ok_"|"_theirs.Outcome, "1|set", "the other session's reminder is set")
	Do $$$AssertEquals(mine.Ok_"|"_mine.Outcome, "1|set", "the same key with other fields in this session is a fresh set, not reused_key")
	Do $$$AssertTrue(mine.Ref '= "" && (mine.Ref '= theirs.Ref), "with a new Ref that is not the other session's")
	Do $$$AssertTrue(mine.DueAt '= theirs.DueAt, "and its own due time")
	If (mine.Ref = "") || (theirs.Ref = "") Quit
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(mine.Ref)
	Do $$$AssertEquals(row.SessionRef_"|"_row.Text_"|"_row.State_"|"_row.IdempotencyKey, a_"|"_myText_"|pending|"_key, "its row is this session's, pending, with the key")
	Set row = ""
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(theirs.Ref)
	Do $$$AssertEquals(row.SessionRef_"|"_row.Text_"|"_row.DueAt_"|"_row.State_"|"_row.IdempotencyKey, b_"|"_theirText_"|"_theirs.DueAt_"|pending|"_key, "the other session's row is untouched")
	Set row = ""
	Do $$$AssertEquals(..Rows(a)_"|"_..Rows(b), "1|1", "each session has its one row")
	Set timers = ..Timers(theirs.Ref)
	Do $$$AssertEquals(timers.%Size(), 1, "the other session's reminder has its one waiter")
	If timers.%Size() = 1 Do $$$AssertEquals(..IsWaiting(timers.%Get(0)), 1, "which is waiting")
	Do $$$AssertEquals(..EventStates(a)_"|"_..EventStates(b), "pending|pending", "each session has its one created event")
	Set again = ..SetKeyed(a, key, myText, 310)
	Do $$$AssertTrue($IsObject(again), "this session's command again is answered")
	If '$IsObject(again) Quit
	Do $$$AssertEquals(again.Ok_"|"_again.Outcome_"|"_again.Message_"|"_again.Ref_"|"_again.DueAt, mine.Ok_"|"_mine.Outcome_"|"_mine.Message_"|"_mine.Ref_"|"_mine.DueAt, "this session's command again gets its own first result while the other session's row holds the key too")
	Do $$$AssertEquals(..Rows(a)_"|"_..EventStates(a), "1|pending", "and makes no second row or event")
}

/// A CancelReminder carrying the CancelKey of another session's cancel finds nothing and reveals nothing (AD-4):
///   - with the other session's Ref it gets exactly the no_reminder refusal that an unknown Ref gets (every member of the answer
///     equal), never the other session's first result and never reused_key; neither session gets an event, and this session's
///     reminder stays pending with its waiter and gets no trigger. The other session's reminder is already cancelled and its waiter
///     has ended, so for that session only its events can show a change;
///   - with its own pending Ref it cancels that reminder normally, never reused_key, and the other session's row keeps its state and
///     key; the same command again, while both sessions' rows hold the key, gets that first result and changes nothing.
Method TestCancelKeyOfAnotherSession()
{
	If '..Guard() Quit
	Set a = ..Session("fcankeya")
	Set b = ..Session("fcankeyb")
	Set fixture = "OcuTalon.Test.Schedule.ReminderFixture"
	Set theirs = ..SetReminder(b, "zz theirs " _ ..Number, 300)
	Set mine = ..SetReminder(a, "zz mine " _ ..Number, 310)
	Do $$$AssertEquals(theirs.ok_"|"_mine.ok, "1|1", "the reminders are set")
	If (theirs.ref = "") || (mine.ref = "") Quit
	Set key = "zzfcankey" _ ..Number
	Set done = $ClassMethod(fixture, "Cancel", b, theirs.ref, key)
	Do $$$AssertEquals(done.ok_"|"_done.outcome_"|"_done.ref, "1|cancelled|" _ theirs.ref, "the other session cancels its reminder with the key")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(theirs.ref)
	Set theirTrace = row.TraceHeaderId
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(mine.ref)
	Set myTrace = row.TraceHeaderId
	Set row = ""
	Do $$$AssertTrue(..WaitEnded(theirs.ref, 10), "and its waiter ends")

	Set unknown = $ClassMethod(fixture, "Cancel", a, "zznosuchreminder", "zzfcanunknown" _ ..Number)
	Set foreign = $ClassMethod(fixture, "Cancel", a, theirs.ref, key)
	Do $$$AssertEquals(unknown.ok_"|"_unknown.outcome_"|"_unknown.message, "0|refused|" _ ..#NOREMINDER, "an unknown Ref is refused no_reminder")
	Do $$$AssertEquals(foreign.%ToJSON(), unknown.%ToJSON(), "the other session's key and Ref get that answer, member for member: not its first result, not reused_key")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(theirs.ref)
	Do $$$AssertEquals(row.SessionRef_"|"_row.State_"|"_row.CancelKey, b_"|cancelled|"_key, "the other session's row is as it was")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(mine.ref)
	Do $$$AssertEquals(row.State_"|"_row.CancelKey, "pending|", "this session's reminder is pending and has no key")
	Set row = ""
	Set timers = ..Timers(mine.ref)
	Do $$$AssertEquals(timers.%Size(), 1, "with its waiter")
	If timers.%Size() = 1 Do $$$AssertEquals(..IsWaiting(timers.%Get(0)), 1, "waiting")
	Do $$$AssertEquals(..EventStates(a)_"|"_..EventStates(b), "pending|pending,cancelled", "no event came from the refusals")
	Do $$$AssertEquals(..RequestsBetween(theirTrace, "ReminderOps", "Ens.Alarm")_"|"_..RequestsBetween(myTrace, "ReminderOps", "Ens.Alarm"), "1|0", "and no trigger")

	Set own = $ClassMethod(fixture, "Cancel", a, mine.ref, key)
	Do $$$AssertEquals(own.ok_"|"_own.outcome_"|"_own.ref_"|"_own.dueAt, "1|cancelled|" _ mine.ref _ "|" _ mine.dueAt, "the other session's key with this session's own Ref cancels it, with its own result")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(mine.ref)
	Do $$$AssertEquals(row.State_"|"_row.CancelKey, "cancelled|" _ key, "its row is cancelled")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(theirs.ref)
	Do $$$AssertEquals(row.SessionRef_"|"_row.State_"|"_row.CancelKey, b_"|cancelled|"_key, "the other session's row is still as it was")
	Set row = ""
	Do $$$AssertEquals(..EventStates(a)_"|"_..EventStates(b), "pending,cancelled|pending,cancelled", "one cancelled event for this session, none for the other")
	Do $$$AssertTrue(..WaitEnded(mine.ref, 10), "its waiter ends")
	Do $$$AssertEquals(..RequestsBetween(theirTrace, "ReminderOps", "Ens.Alarm")_"|"_..RequestsBetween(myTrace, "ReminderOps", "Ens.Alarm"), "1|1", "with one trigger of its own")
	Set again = $ClassMethod(fixture, "Cancel", a, mine.ref, key)
	Do $$$AssertEquals(again.%ToJSON(), own.%ToJSON(), "this session's cancel again gets its own first result while the other session's row holds the key too")
	Do $$$AssertEquals(..EventStates(a)_"|"_..EventStates(b), "pending,cancelled|pending,cancelled", "and nothing changes")
}

/// A SetReminder submitted twice with one key makes one row, one start request to the waiter and one created event, and answers
/// the same both times; the key with another text is reused_key, and the row stays one.
Method TestSetRepeatOneWaiter()
{
	If '..Guard() Quit
	Set session = ..Session("setrep")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set key = "zzsetrep" _ ..Number
	For which = 1, 2, 3 {
		Set result(which) = ..SetKeyed(session, key, $Select(which = 3: "zz other", 1: "zz repeat " _ ..Number), 300)
	}
	Do $$$AssertTrue($IsObject(result(1)) && $IsObject(result(2)) && $IsObject(result(3)), "all three commands are answered")
	If '$IsObject(result(1)) || '$IsObject(result(2)) || '$IsObject(result(3)) Quit
	Do $$$AssertEquals(result(1).Ok_"|"_result(1).Outcome, "1|set", "the first is set")
	Do $$$AssertEquals(result(2).Ok_"|"_result(2).Outcome_"|"_result(2).Message_"|"_result(2).Ref_"|"_result(2).DueAt, result(1).Ok_"|"_result(1).Outcome_"|"_result(1).Message_"|"_result(1).Ref_"|"_result(1).DueAt, "the repeat gets the same answer")
	Do $$$AssertEquals(result(3).Ok_"|"_result(3).Outcome_"|"_result(3).Message, "0|refused|This call reused the key of a different earlier call, so nothing was done.", "the key with another text is reused_key")
	Do $$$AssertEquals(..Rows(session), 1, "one row")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(result(1).Ref)
	Do $$$AssertEquals(row.IdempotencyKey, key, "which holds the key")
	Set traceId = row.TraceHeaderId
	Set row = ""
	Do $$$AssertEquals(..RequestsBetween(traceId, "ReminderOps", "ReminderTimer"), 1, "one start request goes to the waiter")
	Set commands = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "ReminderOps", "ReminderTimer")
	Do $$$AssertEquals(commands.%Size(), 1, "and it is the only one under the session")
	Do ##class(OcuTalon.Test.Core.Observe).Events(session, "reminder", 1, ..#WAIT)
	Do $$$AssertEquals(..EventStates(session), "pending", "and one created event is published")
}

/// Three cancels of one tool call, submitted back to back through CommandCall.Run with the keys <item>:1 to :3 (U-118): each cancels its
/// own reminder with its own answer, one event and one trigger each, and each waiter ends; another session's reminder is untouched. The
/// call run again gets each command its first result and changes nothing; with the first two Refs swapped, a key that names another Ref is
/// reused_key.
Method TestSeveralCancelsFromOneToolCall()
{
	If '..Guard() Quit
	Set a = ..Session("sevena")
	Set b = ..Session("sevenb")
	Set dues = $ListBuild(300, 310, 320)
	For i = 1:1:3 {
		Set found(i) = ..SetReminder(a, "zz several " _ i _ " " _ ..Number, $List(dues, i))
		Set refs(i) = found(i).ref
		If refs(i) = "" Quit
	}
	If (refs(1) = "") || (refs(2) = "") || (refs(3) = "") {
		Do $$$AssertTrue(0, "the three reminders are set")
		Quit
	}
	Set foreign = ..SetReminder(b, "zz foreign " _ ..Number, 330)
	Set item = "zzseveral" _ ..Number
	Do ..CancelCall(a, item, $ListBuild(refs(1), refs(2), refs(3)), .results)
	For i = 1:1:3 {
		Do $$$AssertEquals(results(i), "1|cancelled|" _ refs(i) _ "|" _ found(i).dueAt, "command " _ i _ " is cancelled, with its own Ref and due time")
		Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(refs(i))
		Do $$$AssertEquals(row.State_"|"_row.CancelKey, "cancelled|" _ item _ ":" _ i, "its row holds the key " _ item _ ":" _ i)
		Set row = ""
	}
	Do ##class(OcuTalon.Test.Core.Observe).Events(a, "reminder", 6, ..#WAIT)
	Do $$$AssertEquals(..EventStates(a), "pending,pending,pending,cancelled,cancelled,cancelled", "three cancelled events")
	Set cancelled = ""
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(a, "reminder")
	For i = 3:1:5 Set cancelled = cancelled _ $Select(cancelled = "": "", 1: ",") _ events.%Get(i).payload.ref
	Do $$$AssertEquals(cancelled, refs(1) _ "," _ refs(2) _ "," _ refs(3), "one for each Ref")
	For i = 1:1:3 {
		Do $$$AssertTrue(..WaitEnded(refs(i), 10), "the waiter of " _ i _ " ends within 10 seconds")
		Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(refs(i))
		Set traceId(i) = row.TraceHeaderId
		Set row = ""
		Do $$$AssertEquals(..RequestsBetween(traceId(i), "ReminderOps", "Ens.Alarm"), 1, "after one trigger")
	}
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(foreign.ref)
	Do $$$AssertEquals(row.State, "pending", "the other session's reminder is pending")
	Set row = ""
	Set timers = ..Timers(foreign.ref)
	Do $$$AssertEquals(timers.%Size(), 1, "with its waiter")
	If timers.%Size() = 1 Do $$$AssertEquals(..IsWaiting(timers.%Get(0)), 1, "waiting")

	Do ..CancelCall(a, item, $ListBuild(refs(1), refs(2), refs(3)), .again)
	For i = 1:1:3 {
		Do $$$AssertEquals(again(i), results(i), "run again, command " _ i _ " gets its first result")
	}
	Do $$$AssertEquals(..EventStates(a), "pending,pending,pending,cancelled,cancelled,cancelled", "with no new event")
	For i = 1:1:3 Do $$$AssertEquals(..RequestsBetween(traceId(i), "ReminderOps", "Ens.Alarm"), 1, "and no new trigger for " _ i)

	Do ..CancelCall(a, item, $ListBuild(refs(2), refs(1), refs(3)), .swapped)
	Do $$$AssertEquals(swapped(1), "0|refused|This call reused the key of a different earlier call, so nothing was done.", "with the first two Refs swapped, the first command is reused_key")
	Do $$$AssertEquals(..EventStates(a), "pending,pending,pending,cancelled,cancelled,cancelled", "and nothing changes")
	For i = 1:1:3 {
		Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(refs(i))
		Do $$$AssertEquals(row.State_"|"_row.CancelKey, "cancelled|" _ item _ ":" _ i, "the row of " _ i _ " keeps its key")
		Set row = ""
	}
	Do $$$AssertEquals(..RequestsBetween(foreign.traceHeaderId, "ReminderTimer", "Ens.Alarm"), 1, "the other session's waiter never woke early: it set one alarm and none again")
}

/// One tool call of the session with the item: one CancelReminder per Ref of the list, submitted back to back through CommandCall.Run
/// under one context. results(i) is "Ok|Outcome|Ref|DueAt" of the answer to command i, and for a refusal "0|Outcome|Message".
Method CancelCall(session As %String, item As %String, refs As %List, Output results) [ Private ]
{
	Kill results
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Schedule.ReminderFixture).Begin(session, item), "the context of the call begins")
	For i = 1:1:$ListLength(refs) {
		Set command = ##class(OcuTalon.Msg.Command.CancelReminder).%New()
		Set command.ReminderRef = $List(refs, i)
		Set refusal = ##class(OcuTalon.Tools.CommandCall).Run(command, .result)
		If $IsObject(refusal) || '$IsObject(result) {
			Set results(i) = "no answer"
		} ElseIf result.Ok {
			Set results(i) = result.Ok _ "|" _ result.Outcome _ "|" _ result.Ref _ "|" _ result.DueAt
		} Else {
			Set results(i) = "0|" _ result.Outcome _ "|" _ result.Message
		}
	}
	Do ##class(OcuTalon.Bridge.Context).End()
}

/// Checks the waiter that Reconcile started for the pending row: its newest ReminderStart header is the row's TraceHeaderId, comes from
/// HeartbeatIn, begins a trace session of its own under the TraceRef, and has set one alarm. oldId is the TraceHeaderId before ("" when
/// there was none), which a re-armed waiter must not keep.
Method CheckRearmed(label As %String, ref As %String, traceRef As %String, oldId As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Set headers = ##class(OcuTalon.Test.Schedule.ReminderFixture).StartHeaders(ref)
	Do $$$AssertTrue(headers.%Size() > 0, label _ ": a start header exists")
	If headers.%Size() = 0 Quit
	Set last = headers.%Get(headers.%Size() - 1)
	Do $$$AssertEquals(row.TraceHeaderId, last.id, label _ ": the row keeps the id of the newest start header")
	Do $$$AssertEquals(last.source _ "|" _ last.target _ "|" _ last.sessionId _ "|" _ last.superSession, "HeartbeatIn|ReminderTimer|" _ last.id _ "|" _ traceRef, label _ ": from HeartbeatIn, the first header of its own session under the session's TraceRef")
	Do $$$AssertTrue(row.TraceHeaderId '= oldId, label _ ": the id is a new one")
	Do $$$AssertEquals(..RequestsBetween(last.id, "ReminderTimer", "Ens.Alarm"), 1, label _ ": one alarm is set in the waiter's session")
	Do $$$AssertEquals(row.State, "pending", label _ ": still pending")
}

/// The number of ReminderStart headers of the Ref.
ClassMethod StartCount(ref As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Schedule.ReminderFixture).StartHeaders(ref).%Size()
}

/// The number of ReminderTimer to Notify requests in the trace sessions of every start header of the Ref.
ClassMethod NotifyCount(ref As %String) As %Integer [ Private ]
{
	Set headers = ##class(OcuTalon.Test.Schedule.ReminderFixture).StartHeaders(ref)
	Set count = 0
	For i = 0:1:headers.%Size() - 1 {
		Set count = count + ..RequestsBetween(headers.%Get(i).sessionId, "ReminderTimer", "Notify")
	}
	Quit count
}

/// Reconcile on five rows of one session: lost (pending, never had a waiter), ended (pending, its first waiter ended), live (a waiter
/// is waiting), fired and cancelled. Only lost and ended get a new waiter, with the id of its start header on the row and the due time
/// unchanged. A second run starts nothing. The reminder events do not change. Then lost fires through its new waiter: fired, not late,
/// one Notification, one web card.
Method TestReconcileRearmsOnlyLostWaiters()
{
	If '..Guard() Quit
	Set session = ..Session("rearm")
	Set traceRef = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set ended = ..SetReminder(session, "zz ended " _ ..Number, 90)
	Set live = ..SetReminder(session, "zz live " _ ..Number, 90)
	Do $$$AssertEquals(ended.ok _ "|" _ live.ok, "1|1", "two reminders are set through the product")
	If (ended.ref = "") || (live.ref = "") Quit
	Set cancel = ##class(OcuTalon.Test.Schedule.ReminderFixture).Cancel(session, ended.ref)
	Do $$$AssertEquals(cancel.ok _ "|" _ cancel.outcome, "1|cancelled", "the first one is cancelled")
	Do $$$AssertTrue(..WaitEnded(ended.ref, 10), "and its waiter ends")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ended.ref)
	Set row.State = "pending"
	Set row.CancelKey = ""
	Set oldEnded = row.TraceHeaderId
	Do $$$AssertStatusOK(row.%Save(), "it is put back to pending, with no waiter")
	Set row = ""
	Set fired = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(session, "2030-01-01T10:00:00Z", "fired", {"Text": ("zz fired " _ ..Number)}))
	Set cancelled = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(session, "2030-01-01T10:00:00Z", "cancelled", {"Text": ("zz cancelled " _ ..Number)}))
	Set ..Refs = ..Refs _ "," _ fired _ "," _ cancelled
	Set liveRow = ##class(OcuTalon.Data.Reminder).RefIndexOpen(live.ref)
	Set liveId = liveRow.TraceHeaderId
	Set liveRow = ""
	Set endedRow = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ended.ref)
	Set endedDue = endedRow.DueAt
	Set endedRow = ""
	Do ##class(OcuTalon.Test.Core.Observe).Events(session, "reminder", 3, ..#WAIT)
	Set eventsBefore = ..EventStates(session)
	Set lostText = "zz lost " _ ..Number
	Set lostDue = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 15)
	Set lost = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(session, lostDue, "pending", {"Text": (lostText)}))
	Set ..Refs = ..Refs _ "," _ lost
	Set refs = ended.ref _ "," _ live.ref _ "," _ fired _ "," _ cancelled _ "," _ lost
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.Reminder).Reconcile(refs, .skipped), "Reconcile is OK")
	Do $$$AssertEquals(skipped, "", "and skips no row")
	Set fixture = "OcuTalon.Test.Schedule.ReminderFixture"
	Do $$$AssertEquals($ClassMethod(fixture, "WaitingCount", lost), 1, "lost has one waiter")
	Do $$$AssertEquals($ClassMethod(fixture, "WaitingCount", ended.ref), 1, "ended has one waiter")
	Do ..CheckRearmed("lost", lost, traceRef, "")
	Do ..CheckRearmed("ended", ended.ref, traceRef, oldEnded)
	Set lostRow = ##class(OcuTalon.Data.Reminder).RefIndexOpen(lost)
	Do $$$AssertEquals(lostRow.DueAt, lostDue, "lost keeps its due time")
	Set lostId = lostRow.TraceHeaderId
	Set lostRow = ""
	Set endedRow = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ended.ref)
	Do $$$AssertEquals(endedRow.DueAt, endedDue, "ended keeps its due time")
	Set endedId = endedRow.TraceHeaderId
	Set endedRow = ""
	Set liveRow = ##class(OcuTalon.Data.Reminder).RefIndexOpen(live.ref)
	Do $$$AssertEquals(liveRow.TraceHeaderId, liveId, "live keeps its header id")
	Set liveRow = ""
	Set starts = ##class(OcuTalon.Test.Schedule.ReminderFixture).StartHeaders(live.ref)
	Do $$$AssertEquals(starts.%Size(), 1, "live has one start header")
	If starts.%Size() = 1 Do $$$AssertEquals(starts.%Get(0).source, "ReminderOps", "from ReminderOps")
	Do $$$AssertEquals($ClassMethod(fixture, "WaitingCount", live.ref), 1, "and one waiter")
	For ref = fired, cancelled {
		Set other = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
		Do $$$AssertEquals(other.TraceHeaderId _ "|" _ other.Late, "|0", "a fired or cancelled row is not written")
		Set other = ""
		Do $$$AssertEquals($ClassMethod(fixture, "Timers", ref).%Size() _ "|" _ ..StartCount(ref), "0|0", "and has no waiter and no start header")
	}
	Do $$$AssertEquals(..EventStates(session), eventsBefore, "the reminder events are unchanged")
	Set counts = ..StartCount(lost) _ "|" _ ..StartCount(ended.ref) _ "|" _ ..StartCount(live.ref)
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.Reminder).Reconcile(refs, .skipped), "the second Reconcile is OK")
	Do $$$AssertEquals(..StartCount(lost) _ "|" _ ..StartCount(ended.ref) _ "|" _ ..StartCount(live.ref), counts, "and starts nothing")
	Do $$$AssertEquals($ClassMethod(fixture, "WaitingCount", lost) _ "|" _ $ClassMethod(fixture, "WaitingCount", ended.ref) _ "|" _ $ClassMethod(fixture, "WaitingCount", live.ref), "1|1|1", "each still has one waiter")

	Do $$$AssertTrue(..WaitEnded(lost, ..#FIRESECONDS), "lost fires through its new waiter within " _ ..#FIRESECONDS _ " seconds")
	Set lostRow = ##class(OcuTalon.Data.Reminder).RefIndexOpen(lost)
	Do $$$AssertEquals(lostRow.State _ "|" _ lostRow.Late, "fired|0", "it is fired, not late")
	Set lostRow = ""
	Set waiter = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(lostId)
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(waiter, 1, "ReminderTimer", "Notify")
	Do $$$AssertEquals(sent.%Size(), 1, "one request goes from ReminderTimer to Notify in its new session")
	If sent.%Size() = 1 Do $$$AssertTrue(..CreatedSeconds(sent.%Get(0).id) >= ##class(OcuTalon.Data.Time).Seconds(lostDue), "created no earlier than the due time")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(traceRef, "Notify", "WebChatOut", 1, ..#WAIT), "WebChatOut has handled the Notification")
	Set cards = ##class(OcuTalon.Data.Ownership).RecentNotices(session, 10)
	Do $$$AssertEquals(cards.Count(), 1, "the session has one web card")
	If cards.Count() = 1 Do $$$AssertEquals(cards.GetAt(1).Text, "Reminder: " _ lostText _ ".", "with the due text")
}

/// A pending row with no waiter that fell due 30 seconds ago: after Reconcile its new waiter fires it once, late. One Notification
/// with reminder.late and the slots time, text and dueAt, one web card and one phone message with the catalog's late text, and a fired
/// event with late true.
Method TestReconcileFiresLateWhenDueWhileDown()
{
	If '..Guard() Quit
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Demo).Mode(), 1, "demo mode is on")
	Set session = ..Session("late")
	Set traceRef = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set text = "zz late " _ ..Number
	Set dueAt = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -30)
	Set ref = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(session, dueAt, "pending", {"Text": (text)}))
	Set ..Refs = ..Refs _ "," _ ref
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.Reminder).Reconcile(ref, .skipped), "Reconcile is OK")
	Do $$$AssertTrue(..WaitEnded(ref, ..#FIRESECONDS), "the waiter ends within " _ ..#FIRESECONDS _ " seconds")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State _ "|" _ row.Late, "fired|1", "the row is fired, late")
	Set traceId = row.TraceHeaderId
	Set row = ""
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(traceId), 1, "ReminderTimer", "Notify")
	Do $$$AssertEquals(sent.%Size(), 1, "one request goes from ReminderTimer to Notify")
	If sent.%Size() '= 1 Quit
	Set notification = ##class(OcuTalon.Msg.Notification).%OpenId(sent.%Get(0).bodyId)
	Set slots = "{""time"":""" _ dueAt _ """,""text"":""" _ text _ """,""dueAt"":""" _ dueAt _ """}"
	Do $$$AssertEquals(notification.Kind _ "|" _ notification.CatalogKey _ "|" _ notification.SessionRef, "reminder|reminder.late|" _ session, "a reminder.late Notification for the session")
	Do $$$AssertEquals(notification.Slots, slots, "with time, text and dueAt")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(traceRef, "Notify", "WebChatOut", 1, ..#WAIT), "WebChatOut has handled the Notification")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(traceRef, "Notify", "SimPhoneOut", 1, ..#WAIT), "SimPhoneOut has handled it")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(traceId)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Notify", "WebChatOut").%Size() _ "|" _ ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Notify", "SimPhoneOut").%Size(), "1|1", "Notify sends one request to the web chat and one to the phone")
	Set onlineDemo = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set cards = ##class(OcuTalon.Data.Ownership).RecentNotices(session, 10)
	Do $$$AssertEquals(cards.Count(), 1, "the session has one web card")
	If cards.Count() = 1 {
		Set card = cards.GetAt(1)
		Do $$$AssertEquals(card.Text, ##class(OcuTalon.Msg.Catalog).RenderAt("reminder.late", slots, "web", card.RecordedAt, onlineDemo), "with the catalog's late text for the web")
		Do $$$AssertEquals($Extract(card.Text, 1, 30), "Reminder (late; it was due at ", "which starts as the late text")
	}
	Set phone = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 10)
	Do $$$AssertEquals(phone.Count(), 1, "the session has one phone message")
	If phone.Count() = 1 Do $$$AssertEquals(phone.GetAt(1).Text, ##class(OcuTalon.Msg.Catalog).RenderAt("reminder.late", slots, "phone", phone.GetAt(1).CreatedAt, onlineDemo), "with the catalog's late text for the phone")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "reminder", 1, ..#WAIT)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(events), "fired", "the one reminder event is fired")
	If events.%Size() = 1 Do $$$AssertEquals(+events.%Get(0).payload.late, 1, "and late")
}

/// A reminder due in 15 seconds (waiter A) and a second, re-armed waiter B of the same row: both are waiting, both wake, and the first
/// marks the row fired and sends; the second finds it not pending and sends nothing. One Notification across both sessions, one web
/// card, one phone message and one fired event.
Method TestTwoWaitersFireOnce()
{
	If '..Guard() Quit
	Set session = ..Session("two")
	Set traceRef = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set found = ..SetReminder(session, "zz two " _ ..Number, 15)
	Do $$$AssertEquals(found.ok _ "|" _ found.outcome, "1|set", "the reminder is set")
	If found.ref = "" Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.Reminder).Rearm(found.ref), "a second waiter is started")
	Do $$$AssertEquals(##class(OcuTalon.Test.Schedule.ReminderFixture).WaitingCount(found.ref), 2, "two waiters wait")
	Do $$$AssertEquals(..StartCount(found.ref), 2, "from two start headers")
	Do $$$AssertTrue(..WaitEnded(found.ref, ..#FIRESECONDS), "both waiters end within " _ ..#FIRESECONDS _ " seconds")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(found.ref)
	Do $$$AssertEquals(row.State _ "|" _ row.Late, "fired|0", "the row is fired, not late")
	Set row = ""
	Do $$$AssertEquals(..NotifyCount(found.ref), 1, "exactly one request goes from ReminderTimer to Notify across both sessions")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(traceRef, "Notify", "WebChatOut", 1, ..#WAIT), "WebChatOut has handled the Notification")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(traceRef, "Notify", "SimPhoneOut", 1, ..#WAIT), "SimPhoneOut has handled it")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 1, "the session has one web card")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentPhone(session, 10).Count(), 1, "and one phone message")
	Do ##class(OcuTalon.Test.Core.Observe).Events(session, "reminder", 2, ..#WAIT)
	Do $$$AssertEquals(..EventStates(session), "pending,fired", "the reminder events are pending, then fired")
}

/// A pending row whose session has no Session row: Reconcile is OK, skips it and names its Ref, and starts nothing.
Method TestReconcileSkipsReminderWithoutSession()
{
	If '..Guard() Quit
	Set gone = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ref = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(gone, "2030-01-01T10:00:00Z", "pending", {"Text": ("zz orphan " _ ..Number)}))
	Set ..Refs = ..Refs _ "," _ ref
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.Reminder).Reconcile(ref, .skipped), "Reconcile is OK")
	Do $$$AssertEquals(skipped, $ListBuild(ref), "the row is skipped and named")
	Do $$$AssertEquals(##class(OcuTalon.Test.Schedule.ReminderFixture).Timers(ref).%Size(), 0, "no ReminderTimer is made")
	Do $$$AssertEquals(..StartCount(ref), 0, "no start header is sent")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State _ "|" _ row.TraceHeaderId _ "|" _ row.SessionRef, "pending||" _ gone, "and the row is unchanged")
}

/// Rearm of a pending row whose session is gone: an error status that names the Ref, no ReminderTimer and no start header. HeartbeatIn
/// logs the error with no session id, so the test deletes that event-log row.
Method TestRearmWithoutSessionFails()
{
	If '..Guard() Quit
	Set gone = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ref = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(gone, "2030-01-01T10:00:00Z", "pending", {"Text": ("zz norearm " _ ..Number)}))
	Set ..Refs = ..Refs _ "," _ ref
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set sc = ##class(OcuTalon.Schedule.Reminder).Rearm(ref)
	Do $$$AssertTrue($$$ISERR(sc), "Rearm fails")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ref, "and its error names the Ref")
	Do $$$AssertEquals(##class(OcuTalon.Test.Schedule.ReminderFixture).Timers(ref).%Size() _ "|" _ ..StartCount(ref), "0|0", "no ReminderTimer and no start header")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND Text [ ?", mark, ref)
	Do result.%Next()
	Do $$$AssertEquals(+result.%GetData(1), 1, "one error that names the Ref is logged (by HeartbeatIn's ProcessInput)")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND Text [ ?", mark, ref)
}

/// LiveWaiter: instances of ReminderTimer with a Ref that are completed or terminated while a response is pending, or that wait for no
/// response, are not live (none is found); a waiter that waits for its alarm is, and its id is answered. The instances the test makes are deleted by the test.
Method TestLiveWaiterRule()
{
	If '..Guard() Quit
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ids = ""
	For kind = "completed", "terminated", "idle" {
		Set timer = ##class(OcuTalon.Schedule.ReminderTimer).%New("ReminderTimer")
		Set timer.Ref = ref
		If kind = "completed" Set timer.%IsCompleted = 1
		If kind = "terminated" Set timer.%IsTerminated = 1
		If kind '= "idle" Do timer.%MasterPendingResponses.Insert(##class(Ens.BP.MasterPendingResponse).%New("0", "zz", 0, ""))
		Set sc = timer.%Save()
		Do $$$AssertStatusOK(sc, "a " _ kind _ " ReminderTimer is made")
		If $$$ISOK(sc) Set ids = ids _ $ListBuild(timer.%Id())
		Set timer = ""
	}
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).LiveWaiter(ref), "", "none of the three is a live waiter")
	Set position = 0
	While $ListNext(ids, position, id) {
		Do ##class(OcuTalon.Schedule.ReminderTimer).%DeleteId(id)
	}
	Set found = ..SetReminder(..Session("livewaiter"), "zz livewaiter " _ ..Number, 90)
	Do $$$AssertEquals(found.ok, 1, "a reminder is set through the product")
	If found.ref = "" Quit
	Set timers = ##class(OcuTalon.Test.Schedule.ReminderFixture).Timers(found.ref)
	Do $$$AssertEquals(timers.%Size(), 1, "it has one ReminderTimer")
	If timers.%Size() = 1 Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).LiveWaiter(found.ref), timers.%Get(0), "which is its live waiter")
}

/// A pending row with no waiter while the production is stopped: Reconcile is OK and skips nothing (without its guard it would fail, because
/// HeartbeatIn cannot be made while the production is stopped). The scheduler is settled before the stop (DW-28). The test starts the
/// production again (the Production step) and then Reconcile starts the waiter.
Method TestReconcileWithoutProductionDoesNothing()
{
	If '..Guard() Quit
	Set session = ..Session("stopped")
	Set dueAt = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)
	Set ref = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(session, dueAt, "pending", {"Text": ("zz stopped " _ ..Number)}))
	Set ..Refs = ..Refs _ "," _ ref
	Do $$$AssertTrue(##class(OcuTalon.Test.Schedule.Heartbeat).SettleScheduler(), "the scheduler is settled before the production stops (DW-28)")
	Set sc = ##class(Ens.Director).StopProduction(10, 0)
	Do $$$AssertStatusOK(sc, "the production stops")
	Do $$$AssertEquals(##class(Ens.Director).IsProductionRunning(), 0, "it does not run")
	If $$$ISOK(sc) {
		Do $$$AssertStatusOK(##class(OcuTalon.Schedule.Reminder).Reconcile(ref, .skipped), "Reconcile is OK")
		Do $$$AssertEquals(skipped, "", "and skips nothing")
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).Start(), "the Production step starts the production again")
	If '##class(Ens.Director).IsProductionRunning() Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.Reminder).Reconcile(ref, .skipped), "with the production running, Reconcile is OK")
	Do $$$AssertEquals(##class(OcuTalon.Test.Schedule.ReminderFixture).WaitingCount(ref), 1, "and the row has one waiter")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State _ "|" _ row.DueAt, "pending|" _ dueAt, "still pending with its due time")
}

/// Two pending rows of one session with no waiter, and Reconcile with the Ref of one: it gets a waiter and the other row, which is not
/// in the list, gets nothing (no ReminderTimer, no start header).
Method TestReconcileOnlyRowsInTheList()
{
	If '..Guard() Quit
	Set session = ..Session("only")
	Set dueAt = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)
	Set listed = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(session, dueAt, "pending", {"Text": ("zz only listed " _ ..Number)}))
	Set other = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(session, dueAt, "pending", {"Text": ("zz only other " _ ..Number)}))
	Set ..Refs = ..Refs _ "," _ listed _ "," _ other
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.Reminder).Reconcile(listed, .skipped), "Reconcile of one Ref is OK")
	Do $$$AssertEquals(##class(OcuTalon.Test.Schedule.ReminderFixture).WaitingCount(listed), 1, "the listed row has one waiter")
	Do $$$AssertEquals(##class(OcuTalon.Test.Schedule.ReminderFixture).Timers(other).%Size() _ "|" _ ..StartCount(other), "0|0", "the other pending row has no ReminderTimer and no start header")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(other)
	Do $$$AssertEquals(row.State _ "|" _ row.TraceHeaderId, "pending|", "and is unchanged")
}

/// ReminderTimer cannot take a start (its item is disabled, so each start waits its 10 seconds and gets no answer): Reconcile of two
/// pending rows tries both, answers one error status that names both Refs, skips none, and leaves both pending. The test puts the
/// rows out of the way (cancelled) before it enables the item again, so that the queued starts find nothing to wait for, and waits until
/// the item has handled both of them (each start header completed) before the clean-up removes their sessions.
Method TestReconcileTriesEveryRowAndNamesFailures()
{
	If '..Guard() Quit
	Set item = "ReminderTimer"
	Set session = ..Session("failing")
	Set dueAt = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)
	Set first = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(session, dueAt, "pending", {"Text": ("zz failing first " _ ..Number)}))
	Set second = ..Keep(##class(OcuTalon.Test.Data.Fixture).Reminder(session, ##class(OcuTalon.Data.Time).AddSeconds(dueAt, 1), "pending", {"Text": ("zz failing second " _ ..Number)}))
	Set ..Refs = ..Refs _ "," _ first _ "," _ second
	Set disabled = ##class(Ens.Director).EnableConfigItem(item, 0, 1)
	Do $$$AssertStatusOK(disabled, item _ " is disabled")
	If $$$ISERR(disabled) Quit
	Set sc = ##class(OcuTalon.Schedule.Reminder).Reconcile(first _ "," _ second, .skipped)
	Do $$$AssertTrue($$$ISERR(sc), "Reconcile fails")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue(text [ first, "its error names the first Ref")
	Do $$$AssertTrue(text [ second, "and the second Ref, so the second row was still tried")
	Do $$$AssertEquals(skipped, "", "a failed start is not a skipped row")
	For ref = first, second {
		Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
		Do $$$AssertEquals(row.State _ "|" _ row.TraceHeaderId, "pending|", "the row stays pending with no waiter id")
		Set row.State = "cancelled"
		Do $$$AssertStatusOK(row.%Save(), "and is cancelled before the item is enabled again")
		Set row = ""
	}
	Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem(item, 1, 1), item _ " is enabled again")
	Set end = $ZHorolog + ..#WAIT
	For {
		Set starts = 0, open = 0
		For ref = first, second {
			Set headers = ##class(OcuTalon.Test.Schedule.ReminderFixture).StartHeaders(ref)
			For i = 0:1:headers.%Size() - 1 {
				Set starts = starts + 1
				If headers.%Get(i).status '= 9 Set open = open + 1
			}
		}
		If 'open || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Do $$$AssertEquals(starts _ "|" _ open, "2|0", "and has handled both queued starts: each start header is completed")
}

}
