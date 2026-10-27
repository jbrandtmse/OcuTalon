/// Tests of the reminder logic that need no production (Story 8.3; AD-5, AD-18, AD-32, FR-34, NFR-10). They call the methods of
/// OcuTalon.Schedule.Reminder (Wake on a Test.Schedule.ReminderTimerDouble, over fixture rows) and shadow instances of the ReminderOps
/// probes (ReminderOpsProbe, ReminderOpsStartedProbe, ReminderOpsSendProbe); TestWakeBusyRowTriesAgain also starts jobs that hold and
/// try a row's lock. The reminders that really wait and fire are Test.Schedule.Reminders'. The keys and slots are written out here, never
/// read from the product.
///   - TestAccepts: each row of the handled set: a SetReminder with a Text, a future UTC DueAt and no other due form is carried out; the
///     other due forms, both forms, no form, a blank Text, an unreadable or past DueAt and any other command are not;
///   - TestTimes: SecondsUntil is at least 1 for a due time that is past, now, one and five seconds ahead; IsLate is true only beyond
///     10 seconds;
///   - TestNotification: the exact Kind, key and slots of the Notification, on time and late, and the text of each for the web;
///   - TestNotHandledWritesNothing: ReminderOps answers the not-implemented status for what it does not carry out, and writes no row
///     and no event;
///   - TestStartFailureKeepsNothing: a waiter that does not start deletes the row, publishes no event and answers failed;
///   - TestCreatedEventFailureStillSets: a created event that cannot be published is a warning, and the answer is still set, with the
///     model-facing message;
///   - TestStartWaiterSeam: the real StartWaiter seam, on a Test.Schedule.ReminderOpsSendProbe whose send is a stand-in: the start goes to
///     ReminderTimer with the Ref, in a session of its own under the session's TraceRef, the operation's own session id and SuperSession
///     are put back after an answer, no answer, an error and a throw, and the last three are errors;
///   - TestWakeEarlySetsTimerAgain, TestWakeFiresOnTime, TestWakeFiresLate, TestWakeSendFails, TestWakeNotPendingSendsNothing and
///     TestWakeBusyRowTriesAgain: the firing rule of Reminder.Wake, run on a Test.Schedule.ReminderTimerDouble, for each row of the
///     matrix that the waiter in a production cannot be made to show in a test (an early wake, a late wake, a failed send), and for a row
///     whose lock another job holds.
Class OcuTalon.Test.Schedule.ReminderLogic Extends %UnitTest.TestCase
{

/// The probe under test.
Parameter PROBE = "OcuTalon.Test.Schedule.ReminderOpsProbe";

/// The most seconds the lock job of TestWakeBusyRowTriesAgain holds the row's lock when the test does not let it go.
Parameter HOLDSECONDS = 40;

/// The Refs of the fixture sessions of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

Method OnAfterAllTests() As %Status
{
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Kill ^OcuTalonTest("ReminderLogic", "held"), ^OcuTalonTest("ReminderLogic", "tried"), ^OcuTalonTest("ReminderLogic", "release")
	Quit $$$OK
}

/// A SetReminder with the text and the due time; the other members are as given by the caller after the call.
ClassMethod Command(session As %String, text As %String, dueAt As %String) As OcuTalon.Msg.Command.SetReminder [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SetReminder).%New()
	Set command.SessionRef = session
	Set command.IdempotencyKey = "zzkeylogic"
	Set command.Text = text
	Set command.DueAt = dueAt
	Quit command
}

/// Each input of the handled set against the time of a fixed now.
Method TestAccepts()
{
	Set now = "2030-01-01T10:00:00Z"
	Set later = "2030-01-01T10:05:00Z"
	Set command = ..Command("zzsession", "Stretch", later)
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(command, now), 1, "a Text and a future DueAt only is carried out")
	Set command = ..Command("zzsession", "Stretch", "2030-01-01T10:00:01Z")
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(command, now), 1, "a DueAt one second ahead is carried out")
	Set command = ..Command("zzsession", "Stretch", later)
	Set command.DelaySeconds = 60
	Set command.DueAt = ""
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(command, now), 0, "DelaySeconds is another due form")
	Set command = ..Command("zzsession", "Stretch", "")
	Set command.LocalDueAt = "2030-01-01T11:00:00"
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(command, now), 0, "LocalDueAt is another due form")
	Set command = ..Command("zzsession", "Stretch", later)
	Set command.DelaySeconds = 60
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(command, now), 0, "DueAt and DelaySeconds are two due forms")
	Set command = ..Command("zzsession", "Stretch", later)
	Set command.LocalDueAt = "2030-01-01T11:00:00"
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(command, now), 0, "DueAt and LocalDueAt are two due forms")
	Set command = ..Command("zzsession", "Stretch", "")
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(command, now), 0, "no due form")
	Set command = ..Command("zzsession", "", later)
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(command, now), 0, "an empty Text")
	Set command = ..Command("zzsession", "   ", later)
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(command, now), 0, "a blank Text")
	Set command = ..Command("zzsession", "Stretch", "tomorrow")
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(command, now), 0, "an unreadable DueAt")
	Set command = ..Command("zzsession", "Stretch", "2030-01-01T10:00:00")
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(command, now), 0, "a DueAt with no Z is unreadable")
	Set command = ..Command("zzsession", "Stretch", "2030-01-01T09:59:59Z")
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(command, now), 0, "a past DueAt")
	Set command = ..Command("zzsession", "Stretch", now)
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(command, now), 0, "a DueAt that is now")
	Set other = ##class(OcuTalon.Msg.Command.ListReminders).%New()
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(other, now), 0, "ListReminders")
	Set other = ##class(OcuTalon.Msg.Command.CancelReminder).%New()
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts(other, now), 0, "CancelReminder")
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Accepts("", now), 0, "no command")
}

/// SecondsUntil at a past time, now, one and five seconds ahead, and IsLate at -5, 0, 10 and 11 seconds from the due time.
Method TestTimes()
{
	Set now = "2030-01-01T10:00:00Z"
	Set reminder = "OcuTalon.Schedule.Reminder"
	Do $$$AssertEquals($ClassMethod(reminder, "SecondsUntil", "2030-01-01T09:00:00Z", now), 1, "a past time waits 1 second")
	Do $$$AssertEquals($ClassMethod(reminder, "SecondsUntil", now, now), 1, "now waits 1 second")
	Do $$$AssertEquals($ClassMethod(reminder, "SecondsUntil", "2030-01-01T10:00:01Z", now), 1, "one second ahead waits 1 second")
	Do $$$AssertEquals($ClassMethod(reminder, "SecondsUntil", "2030-01-01T10:00:05Z", now), 5, "five seconds ahead waits 5 seconds")
	Do $$$AssertEquals($ClassMethod(reminder, "SecondsUntil", "unreadable", now), 1, "an unreadable time waits 1 second")
	Set due = now
	Do $$$AssertEquals($ClassMethod(reminder, "IsLate", due, "2030-01-01T09:59:55Z"), 0, "5 seconds before the due time is not late")
	Do $$$AssertEquals($ClassMethod(reminder, "IsLate", due, "2030-01-01T10:00:00Z"), 0, "at the due time is not late")
	Do $$$AssertEquals($ClassMethod(reminder, "IsLate", due, "2030-01-01T10:00:10Z"), 0, "10 seconds after is on time")
	Do $$$AssertEquals($ClassMethod(reminder, "IsLate", due, "2030-01-01T10:00:11Z"), 1, "11 seconds after is late")
}

/// The Notification of an on-time and of a late reminder, and the web text of each.
Method TestNotification()
{
	Set row = ##class(OcuTalon.Data.Reminder).%New()
	Set row.Ref = "zzref"
	Set row.SessionRef = "zzsession"
	Set row.Text = "zz stretch"
	Set row.DueAt = "2030-01-01T10:00:00Z"
	Set notification = ##class(OcuTalon.Schedule.Reminder).Notification(row, 0)
	Do $$$AssertEquals(notification.%IsA("OcuTalon.Msg.Notification"), 1, "the message is a Notification")
	Do $$$AssertEquals(notification.Kind_"|"_notification.CatalogKey_"|"_notification.SessionRef, "reminder|reminder.due|zzsession", "on time: kind, key and session")
	Do $$$AssertEquals(notification.Slots, "{""text"":""zz stretch"",""dueAt"":""2030-01-01T10:00:00Z""}", "on time: the slots")
	Do $$$AssertEquals(notification.%Id(), "", "the Notification is not saved")
	Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).RenderAt(notification.CatalogKey, notification.Slots, "web", row.DueAt, 0, .sc), "Reminder: zz stretch.", "on time: the web text")
	Do $$$AssertStatusOK(sc, "the on-time text renders")
	Set late = ##class(OcuTalon.Schedule.Reminder).Notification(row, 1)
	Do $$$AssertEquals(late.Kind_"|"_late.CatalogKey_"|"_late.SessionRef, "reminder|reminder.late|zzsession", "late: kind, key and session")
	Do $$$AssertEquals(late.Slots, "{""time"":""2030-01-01T10:00:00Z"",""text"":""zz stretch"",""dueAt"":""2030-01-01T10:00:00Z""}", "late: the slots")
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(late.CatalogKey, late.Slots, "web", row.DueAt, 0, .sc)
	Do $$$AssertStatusOK(sc, "the late text renders")
	Do $$$AssertEquals(text, "Reminder (late; it was due at "_##class(OcuTalon.Data.Time).ForMessage(row.DueAt, row.DueAt)_"): zz stretch.", "late: the web text names the due time")
}

/// The commands that ReminderOps does not carry out get the not-implemented status, and nothing is written.
Method TestNotHandledWritesNothing()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogicnh" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set probe = ##class(Ens.Host).GetShadowInstance("class||" _ ..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(probe) Quit
	Set future = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)
	Set list = $ListBuild("delay", "local", "both", "none", "empty", "past", "unknown session", "list", "cancel", "other")
	Set position = 0
	While $ListNext(list, position, which) {
		Set command = ..Command(session, "zz stretch", future)
		If which = "delay" Set command.DueAt = "", command.DelaySeconds = 60
		If which = "local" Set command.DueAt = "", command.LocalDueAt = "2030-01-01T11:00:00"
		If which = "both" Set command.DelaySeconds = 60
		If which = "none" Set command.DueAt = ""
		If which = "empty" Set command.Text = ""
		If which = "past" Set command.DueAt = "2020-01-01T10:00:00Z"
		If which = "unknown session" Set command.SessionRef = "zznosuchsession"
		If which = "list" Set command = ##class(OcuTalon.Msg.Command.ListReminders).%New(), command.SessionRef = session
		If which = "cancel" Set command = ##class(OcuTalon.Msg.Command.CancelReminder).%New(), command.SessionRef = session
		If which = "other" Set command = ##class(OcuTalon.Msg.Command.StartWatch).%New(), command.SessionRef = session
		Set response = ""
		Set sc = probe.OnMessage(command, .response)
		Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, which_": the status is not-implemented")
		Do $$$AssertEquals(response, "", which_": there is no answer")
	}
	Do $$$AssertEquals(..Rows(session), 0, "no row was written")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(session), 0, "no event was published")
}

/// A valid SetReminder for a fixture session whose waiter does not start: the row is deleted, no event is published, and the answer
/// is failed with the plain-English failure text, with one error in the log.
Method TestStartFailureKeepsNothing()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogicsf" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set probe = ##class(Ens.Host).GetShadowInstance("class||" _ ..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(probe) Quit
	Set command = ..Command(session, "zz stretch", ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600))
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set response = ""
	Set sc = probe.OnMessage(command, .response)
	Do $$$AssertStatusOK(sc, "the status is OK")
	If '$IsObject(response) {
		Do $$$AssertTrue(0, "a CommandResult comes back")
		Quit
	}
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "0|failed", "the answer is failed")
	Do $$$AssertEquals(response.Message, ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED, "with the failure text")
	Do $$$AssertEquals(..Rows(session), 0, "the row is deleted")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(session), 0, "no event was published")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND Text %STARTSWITH ?", mark, "OcuTalon.Schedule.ReminderOps: the waiter of ")
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "one error is logged")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND Text %STARTSWITH ?", mark, "OcuTalon.Schedule.ReminderOps: the waiter of ")
}

/// A pending fixture reminder of the session that was due that many seconds ago (a negative number for one due later); its Ref is kept
/// for the clean-up.
Method DueReminder(session As %String, secondsAgo As %Integer, state As %String = "pending") As %String [ Private ]
{
	Set dueAt = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -secondsAgo)
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Reminder(session, dueAt, state)
	Set ..Refs = ..Refs _ "," _ ref
	Quit ref
}

/// Runs the waiter's wake for the Ref on a double, whose send answers the status, and returns the double.
Method Wake(ref As %String, sendStatus As %Status = 1) As OcuTalon.Test.Schedule.ReminderTimerDouble [ Private ]
{
	Set timer = ##class(OcuTalon.Test.Schedule.ReminderTimerDouble).%New(ref)
	Set timer.SendStatus = sendStatus
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.Reminder).Wake(timer, "due"), "the wake ends OK")
	Quit timer
}

/// The reminder events of the session, as the states of their payloads, comma-separated.
ClassMethod EventStates(session As %String) As %String [ Private ]
{
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "reminder")
	Set states = ""
	For i = 0:1:events.%Size() - 1 Set states = states _ $Select(states = "": "", 1: ",") _ events.%Get(i).payload.state
	Quit states
}

/// A wake before the due time sets the timer again for the rest, sends nothing, publishes nothing and leaves the row pending.
Method TestWakeEarlySetsTimerAgain()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogicwe" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set ref = ..DueReminder(session, -600)
	Set timer = ..Wake(ref)
	Do $$$AssertEquals(timer.Sent.%Size(), 0, "nothing is sent")
	Do $$$AssertEquals(timer.Timers.%Size(), 1, "the timer is set once more")
	Set seconds = +$Piece(timer.Timers.%Get(0), "|", 1)
	Do $$$AssertTrue((seconds >= 590) && (seconds <= 600), "for the rest of the time (" _ seconds _ " seconds)")
	Do $$$AssertEquals($Piece(timer.Timers.%Get(0), "|", 2), "due", "with the key due")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.Late, "pending|0", "the row is still pending")
	Do $$$AssertEquals(..EventStates(session), "", "no event is published")
}

/// A wake within 10 seconds after the due time marks the row fired and not late and saves it before it sends one reminder.due
/// Notification, and publishes the fired event.
Method TestWakeFiresOnTime()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogicft" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set ref = ..DueReminder(session, 3)
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Set text = row.Text, dueAt = row.DueAt
	Set row = ""
	Set timer = ..Wake(ref)
	Do $$$AssertEquals(timer.Timers.%Size(), 0, "no timer is set again")
	Do $$$AssertEquals(timer.Sent.%Size(), 1, "one request is sent")
	If timer.Sent.%Size() = 1 {
		Set sent = timer.Sent.%Get(0)
		Do $$$AssertEquals(sent.target_"|"_sent.kind_"|"_sent.key_"|"_sent.session, "Notify|reminder|reminder.due|"_session, "to Notify, a reminder.due Notification for the session")
		Do $$$AssertEquals(sent.responseRequired, 0, "and no answer is waited for")
		Do $$$AssertEquals(sent.slots, "{""text"":"""_text_""",""dueAt"":"""_dueAt_"""}", "with the text and the due time")
		Do $$$AssertEquals(sent.storedState, "fired", "the row is saved fired before the send")
	}
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.Late, "fired|0", "the row is fired and not late")
	Set row = ""
	Do $$$AssertEquals(..EventStates(session), "fired", "the fired event is published")
}

/// A wake more than 10 seconds after the due time marks the row fired and late and sends a reminder.late Notification whose time is the
/// due time.
Method TestWakeFiresLate()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogiclt" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set ref = ..DueReminder(session, 60)
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Set text = row.Text, dueAt = row.DueAt
	Set row = ""
	Set timer = ..Wake(ref)
	Do $$$AssertEquals(timer.Sent.%Size(), 1, "one request is sent")
	If timer.Sent.%Size() = 1 {
		Set sent = timer.Sent.%Get(0)
		Do $$$AssertEquals(sent.target_"|"_sent.kind_"|"_sent.key_"|"_sent.session, "Notify|reminder|reminder.late|"_session, "to Notify, a reminder.late Notification for the session")
		Do $$$AssertEquals(sent.slots, "{""time"":"""_dueAt_""",""text"":"""_text_""",""dueAt"":"""_dueAt_"""}", "with the due time as the time")
	}
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.Late, "fired|1", "the row is fired and late")
	Set row = ""
	Do $$$AssertEquals(..EventStates(session), "fired", "the fired event is published")
}

/// A send that fails is logged with the Ref and not retried; the row stays fired and the event is published.
Method TestWakeSendFails()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogicsx" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set ref = ..DueReminder(session, 3)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set timer = ..Wake(ref, $SYSTEM.Status.Error(5001, "zz the send failed"))
	Do $$$AssertEquals(timer.Sent.%Size(), 1, "the send was tried once")
	Do $$$AssertEquals(timer.Timers.%Size(), 0, "and not tried again")
	Set start = "OcuTalon.Schedule.Reminder: the notification of " _ ref _ " was not sent"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND Text %STARTSWITH ?", mark, start)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "one error is logged with the Ref")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND Text %STARTSWITH ?", mark, start)
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State, "fired", "the row stays fired")
	Set row = ""
	Do $$$AssertEquals(..EventStates(session), "fired", "and the fired event is published")
}

/// A wake for a row that is cancelled, already fired or missing sends nothing, sets no timer and publishes nothing.
Method TestWakeNotPendingSendsNothing()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogicnp" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set list = $ListBuild("cancelled", "fired", "missing")
	Set position = 0
	While $ListNext(list, position, which) {
		Set ref = $Select(which = "missing": "zznosuchreminder", 1: ..DueReminder(session, 3, which))
		Set timer = ..Wake(ref)
		Do $$$AssertEquals(timer.Sent.%Size()_"|"_timer.Timers.%Size(), "0|0", which_": nothing is sent and no timer is set")
		If which '= "missing" {
			Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
			Do $$$AssertEquals(row.State_"|"_row.Late, which_"|0", which_": the row is as it was")
			Set row = ""
		}
	}
	Do $$$AssertEquals(..EventStates(session), "", "no event is published")
}

/// A row whose lock another job holds is not fired and not dropped: the wake sets the timer again for a second and sends nothing. Once
/// the other job lets go, the next wake fires the reminder once, and the lock is free again for another job. The other job holds the
/// lock until the test lets it go after the first wake, so the outcome does not depend on the lock timeout; it needs a process lock
/// timeout under HOLDSECONDS (the default is 10 seconds).
Method TestWakeBusyRowTriesAgain()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogicbl" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set ref = ..DueReminder(session, 3)
	Kill ^OcuTalonTest("ReminderLogic", "held", ref), ^OcuTalonTest("ReminderLogic", "tried", ref), ^OcuTalonTest("ReminderLogic", "release", ref)
	Job ##class(OcuTalon.Test.Schedule.ReminderLogic).HoldLock(ref, ..#HOLDSECONDS)::10
	Set started = $Test
	Do $$$AssertTrue(started, "a job is started that holds the row's lock")
	If 'started Quit
	Set end = $ZHorolog + 10
	While '$Data(^OcuTalonTest("ReminderLogic", "held", ref)) && (end > $ZHorolog) {
		Hang 0.1
	}
	Do $$$AssertTrue($Data(^OcuTalonTest("ReminderLogic", "held", ref)) > 0, "and it holds it")
	If '$Data(^OcuTalonTest("ReminderLogic", "held", ref)) Quit
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set timer = ..Wake(ref)
	Do $$$AssertEquals(timer.Sent.%Size(), 0, "a wake on the busy row sends nothing")
	Do $$$AssertEquals(timer.Timers.%Size(), 1, "and sets the timer again")
	If timer.Timers.%Size() = 1 Do $$$AssertEquals(timer.Timers.%Get(0), "1|due", "for a second, with the key due")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State, "pending", "the row is still pending")
	Set row = ""
	Set start = "OcuTalon.Schedule.Reminder: the row of " _ ref _ " is locked"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Text %STARTSWITH ?", mark, start)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "one warning is logged with the Ref")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Text %STARTSWITH ?", mark, start)
	Set ^OcuTalonTest("ReminderLogic", "release", ref) = 1
	Set end = $ZHorolog + 20
	While $Data(^OcuTalonTest("ReminderLogic", "held", ref)) && (end > $ZHorolog) {
		Hang 0.1
	}
	Do $$$AssertEquals($Data(^OcuTalonTest("ReminderLogic", "held", ref)), 0, "the other job lets go")
	Set timer = ..Wake(ref)
	Do $$$AssertEquals(timer.Sent.%Size()_"|"_timer.Timers.%Size(), "1|0", "the next wake sends once and sets no timer")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State, "fired", "the row is fired")
	Set row = ""
	Do $$$AssertEquals(..EventStates(session), "fired", "and the fired event is published")
	Job ##class(OcuTalon.Test.Schedule.ReminderLogic).TryLock(ref)::10
	Do $$$AssertTrue($Test, "a job is started that tries the row's lock")
	Set end = $ZHorolog + 10
	While '$Data(^OcuTalonTest("ReminderLogic", "tried", ref)) && (end > $ZHorolog) {
		Hang 0.1
	}
	Do $$$AssertEquals($Get(^OcuTalonTest("ReminderLogic", "tried", ref)), 1, "and the lock is free after the wake")
}

/// The job of TestWakeBusyRowTriesAgain that holds the row's exclusive lock until the test sets the flag under release, for at most the
/// seconds; the flag under held tells that it does.
ClassMethod HoldLock(ref As %String, seconds As %Integer)
{
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref, 4)
	If '$IsObject(row) Quit
	Set ^OcuTalonTest("ReminderLogic", "held", ref) = 1
	Set end = $ZHorolog + seconds
	While '$Data(^OcuTalonTest("ReminderLogic", "release", ref)) && (end > $ZHorolog) {
		Hang 0.1
	}
	Set row = ""
	Kill ^OcuTalonTest("ReminderLogic", "held", ref)
}

/// The job of TestWakeBusyRowTriesAgain that tries the row's exclusive lock; the flag under tried is 1 when it gets it.
ClassMethod TryLock(ref As %String)
{
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref, 4)
	Set ^OcuTalonTest("ReminderLogic", "tried", ref) = $IsObject(row)
}

/// A created event that cannot be published (here, inside an open transaction) is a warning: the answer is still set, with the Ref and
/// the due time, and the row stays. The transaction is rolled back, so nothing is left.
Method TestCreatedEventFailureStillSets()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogicce" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Schedule.ReminderOpsStartedProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(probe) Quit
	Set command = ..Command(session, "zz stretch", ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600))
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set response = ""
	TSTART
	Try {
		Set sc = probe.OnMessage(command, .response)
		Set rows = ..Rows(session)
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Text %STARTSWITH ?", mark, "OcuTalon.Schedule.ReminderOps: the reminder event (created) of ")
		Do result.%Next()
		Set warnings = +result.%GetData(1)
	} Catch exception {
		Set sc = exception.AsStatus(), rows = "", warnings = ""
	}
	TROLLBACK 1
	Do $$$AssertStatusOK(sc, "the status is OK")
	If '$IsObject(response) {
		Do $$$AssertTrue(0, "a CommandResult comes back")
		Quit
	}
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|set", "the answer is still set")
	Do $$$AssertEquals(response.Message, "The reminder is set.", "with the message for the model")
	Do $$$AssertTrue(response.Ref '= "", "with the Ref")
	Do $$$AssertEquals(response.DueAt, command.DueAt, "and the due time")
	Do $$$AssertEquals(rows, 1, "the row stays")
	Do $$$AssertEquals(warnings, 1, "one warning is logged")
	Do $$$AssertEquals(..Rows(session), 0, "nothing is left after the rollback")
}

/// The real StartWaiter seam against a stand-in send: the start request goes to ReminderTimer, names the Ref and waits at most 10
/// seconds; while it is sent, the operation has no session id and its SuperSession is the session row's TraceRef (the waiter's own
/// trace session, AD-26); afterwards both are as they were, whatever the send did. A send that gets no answer, fails or throws is an
/// error status (the caller deletes the row and answers failed).
Method TestStartWaiterSeam()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogicsw" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Do $$$AssertTrue(trace '= "", "the session has a TraceRef")
	Set row = ##class(OcuTalon.Data.Reminder).%New()
	Set row.Ref = "zzseamref"
	Set row.SessionRef = session
	Set modes = $ListBuild("ok", "noanswer", "error", "throw")
	Set position = 0
	While $ListNext(modes, position, mode) {
		Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Schedule.ReminderOpsSendProbe", .sc)
		Do $$$AssertStatusOK(sc, mode_": a shadow instance of the probe is made")
		If '$IsObject(probe) Continue
		Set probe.Mode = mode
		Set probe.%SessionId = 4711
		Set probe.%SuperSession = "zzbefore"
		Set sc = probe.Start(row)
		If mode = "ok" {
			Do $$$AssertStatusOK(sc, mode_": a waiter that answers is started")
		} Else {
			Do $$$AssertTrue($$$ISERR(sc), mode_": the start is an error")
		}
		If $IsObject(probe.Seen) {
			Do $$$AssertEquals(probe.Seen.target_"|"_probe.Seen.ref_"|"_probe.Seen.timeout, "ReminderTimer|zzseamref|10", mode_": the start goes to ReminderTimer, names the Ref, waits 10 seconds")
			Do $$$AssertEquals(probe.Seen.sessionId_"|"_probe.Seen.superSession, "|"_trace, mode_": it is sent with no session id, under the TraceRef")
		} Else {
			Do $$$AssertTrue(0, mode_": the send was made")
		}
		Do $$$AssertEquals(probe.%SessionId_"|"_probe.%SuperSession, "4711|zzbefore", mode_": the operation's session id and SuperSession are put back")
	}
}

/// The number of Reminder rows of the session.
ClassMethod Rows(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Reminder WHERE SessionRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
