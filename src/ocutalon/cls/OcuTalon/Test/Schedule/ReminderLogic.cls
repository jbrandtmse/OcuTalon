/// Tests of the reminder logic that need no production (Story 8.3; AD-5, AD-18, AD-32, FR-34, NFR-10). They call the methods of
/// OcuTalon.Schedule.Reminder (Wake on a Test.Schedule.ReminderTimerDouble, over fixture rows) and shadow instances of the ReminderOps
/// probes (ReminderOpsProbe, ReminderOpsStartedProbe, ReminderOpsSendProbe); TestWakeBusyRowTriesAgain also starts jobs that hold and
/// try a row's lock. The reminders that really wait and fire are Test.Schedule.Reminders'. The keys and slots are written out here, never
/// read from the product.
///   - TestResolve: the due-form rule of Schedule.Reminder.Resolve, by refusal code: every due form (DueAt, DelaySeconds, LocalDueAt),
///     its unreadable and past values, none and several forms, a blank Text, and the order of the checks;
///   - TestTimes: SecondsUntil is at least 1 for a due time that is past, now, one and five seconds ahead; IsLate is true only beyond
///     10 seconds;
///   - TestNotification: the exact Kind, key and slots of the Notification, on time and late, and the text of each for the web;
///   - TestRefusalsWriteNothing: each refusal of each verb (no session, and the set refusals) is status OK with Ok 0, outcome refused and
///     the exact Message, with no row and no event; a message that is not one of the three verbs is an error status that is not 5003,
///     with no answer and one logged error;
///   - TestListShape (DW-135): only the session's pending reminders, earliest due first, with ref, text and dueAt as strings, which
///     Tools.CommandCall.Listed reads; an empty list;
///   - TestCancelFixtureRow, TestCancelRacesFire and TestCancelBusyRowFails: a cancel marks the row cancelled with its key, publishes one
///     event and answers the first result to a repeat; a reminder that fires while the cancel waits for the lock is refused; a lock that
///     stays busy answers failed and changes nothing (jobs that hold the row's lock);
///   - TestSetRepeat: a key used again by a SetReminder of the session gets the first result, or reused_key for other fields;
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

/// The code that Resolve gives for the command at a fixed now, and the due time it resolves.
ClassMethod Resolved(command As OcuTalon.Msg.Command.SetReminder, now As %String, Output dueAt As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Schedule.Reminder).Resolve(command, now, .dueAt)
}

/// Each due form, refusal and order case of Resolve, by code, against a fixed now.
Method TestResolve()
{
	Set now = "2030-01-01T10:00:00Z"
	Set later = "2030-01-01T10:05:00Z"
	Set localLater = ##class(OcuTalon.Data.Time).ToLocal(later)
	Set localPast = ##class(OcuTalon.Data.Time).ToLocal("2030-01-01T09:55:00Z")
	Set command = ..Command("zzsession", "Stretch", later)
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "|"_later, "a Text and a future DueAt only is resolved to that DueAt")
	Set command = ..Command("zzsession", "Stretch", "2030-01-01T10:00:01Z")
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "|2030-01-01T10:00:01Z", "a DueAt one second ahead is resolved")
	Set command = ..Command("zzsession", "Stretch", "")
	Set command.DelaySeconds = 60
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "|2030-01-01T10:01:00Z", "DelaySeconds 60 counts from now")
	Set command.DelaySeconds = "+60"
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "|2030-01-01T10:01:00Z", "a signed DelaySeconds +60 is read")
	Set command.DelaySeconds = 1
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "|2030-01-01T10:00:01Z", "DelaySeconds 1 is the smallest delay")
	Set command.DelaySeconds = 0
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "past|", "DelaySeconds 0 is past")
	Set command.DelaySeconds = -5
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "past|", "DelaySeconds -5 is past")
	Set command.DelaySeconds = "1.5"
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "bad_time|", "DelaySeconds 1.5 is not a whole number")
	Set command.DelaySeconds = "abc"
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "bad_time|", "DelaySeconds abc cannot be read")
	Set command.DelaySeconds = 300000000000
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "bad_time|", "a DelaySeconds beyond year 9999 cannot be read")
	Set command = ..Command("zzsession", "Stretch", "")
	Set command.LocalDueAt = localLater
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "|"_##class(OcuTalon.Data.Time).FromLocal(localLater), "a LocalDueAt is the FromLocal of it")
	Set command.LocalDueAt = localPast
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "past|", "a past LocalDueAt")
	Set command.LocalDueAt = "next Thursday"
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "bad_time|", "an unreadable LocalDueAt")
	Set command.LocalDueAt = "2026-02-30T10:00:00"
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "bad_time|", "an impossible LocalDueAt")
	Set command = ..Command("zzsession", "Stretch", "tomorrow")
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "bad_time|", "an unreadable DueAt")
	Set command = ..Command("zzsession", "Stretch", "2030-01-01T10:00:00")
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "bad_time|", "a DueAt with no Z is unreadable")
	Set command = ..Command("zzsession", "Stretch", now)
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "past|", "a DueAt that is now is past")
	Set command = ..Command("zzsession", "Stretch", "2030-01-01T09:59:59Z")
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "past|", "a past DueAt")
	Set command = ..Command("zzsession", "Stretch", "")
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "due_forms|", "no due form")
	Set command = ..Command("zzsession", "Stretch", later)
	Set command.DelaySeconds = 60
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "due_forms|", "DueAt and DelaySeconds are two due forms")
	Set command = ..Command("zzsession", "Stretch", later)
	Set command.LocalDueAt = localLater
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "due_forms|", "DueAt and LocalDueAt are two due forms")
	Set command = ..Command("zzsession", "Stretch", "")
	Set command.DelaySeconds = 60, command.LocalDueAt = localLater
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "due_forms|", "DelaySeconds and LocalDueAt are two due forms")
	Set command = ..Command("zzsession", "Stretch", later)
	Set command.DelaySeconds = 60, command.LocalDueAt = localLater
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "due_forms|", "three due forms")
	Set command = ..Command("zzsession", "", later)
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "no_text|", "an empty Text")
	Set command = ..Command("zzsession", "   ", later)
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "no_text|", "a blank Text")
	Set command = ..Command("zzsession", "", "")
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "no_text|", "a blank Text comes before the due forms")
	Set command = ..Command("zzsession", "Stretch", "tomorrow")
	Set command.DelaySeconds = 60
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "due_forms|", "the number of forms comes before readability")
	Set command = ..Command("zzsession", "Stretch", "2030-13-01T10:00:00Z")
	Do $$$AssertEquals(..Resolved(command, now, .dueAt)_"|"_dueAt, "bad_time|", "readability comes before past: an impossible month is bad_time, not past")
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

/// Each refusal of each verb gives status OK and a CommandResult with Ok 0, outcome refused and the exact Message, and writes no row
/// and no event. A message that is not one of the three verbs gets an error status that is not 5003, no answer and one logged error.
Method TestRefusalsWriteNothing()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogicnh" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set probe = ##class(Ens.Host).GetShadowInstance("class||" _ ..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(probe) Quit
	Set future = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)
	Set noSession = "0|refused|This conversation has no signed-in session, so nothing was done."
	Set list = $ListBuild("set empty session", "set unknown session", "list empty session", "list unknown session", "cancel empty session", "cancel unknown session", "no text", "blank text", "no form", "two forms", "unreadable", "past", "past delay")
	Set position = 0
	While $ListNext(list, position, which) {
		Set command = ..Command(session, "zz stretch", future)
		Set expected = ""
		If which = "set empty session" Set command.SessionRef = "", expected = noSession
		If which = "set unknown session" Set command.SessionRef = "zznosuchsession", expected = noSession
		If which = "list empty session" Set command = ##class(OcuTalon.Msg.Command.ListReminders).%New(), expected = noSession
		If which = "list unknown session" Set command = ##class(OcuTalon.Msg.Command.ListReminders).%New(), command.SessionRef = "zznosuchsession", expected = noSession
		If which = "cancel empty session" Set command = ##class(OcuTalon.Msg.Command.CancelReminder).%New(), command.ReminderRef = "zzref", expected = noSession
		If which = "cancel unknown session" Set command = ##class(OcuTalon.Msg.Command.CancelReminder).%New(), command.SessionRef = "zznosuchsession", command.ReminderRef = "zzref", expected = noSession
		If which = "no text" Set command.Text = "", expected = "0|refused|The reminder has no text, so nothing was set."
		If which = "blank text" Set command.Text = "  ", expected = "0|refused|The reminder has no text, so nothing was set."
		If which = "no form" Set command.DueAt = "", expected = "0|refused|A reminder needs exactly one due time, either delaySeconds or localDueAt, so nothing was set."
		If which = "two forms" Set command.DelaySeconds = 60, expected = "0|refused|A reminder needs exactly one due time, either delaySeconds or localDueAt, so nothing was set."
		If which = "unreadable" Set command.DueAt = "", command.LocalDueAt = "next Thursday", expected = "0|refused|The due time could not be read, so nothing was set. Give delaySeconds as a whole number of seconds, or localDueAt as a local date and time in the form YYYY-MM-DDThh:mm:ss."
		If which = "past" Set command.DueAt = "2020-01-01T10:00:00Z", expected = "0|refused|That time has already passed, so nothing was set."
		If which = "past delay" Set command.DueAt = "", command.DelaySeconds = -5, expected = "0|refused|That time has already passed, so nothing was set."
		Set response = ""
		Set sc = probe.OnMessage(command, .response)
		Do $$$AssertStatusOK(sc, which_": the status is OK")
		If '$IsObject(response) {
			Do $$$AssertTrue(0, which_": a CommandResult comes back")
			Continue
		}
		Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Message, expected, which_": refused, with the exact Message")
		Do $$$AssertEquals(response.Ref_"|"_response.DueAt_"|"_response.Data, "||", which_": with no Ref, no DueAt and no Data")
	}
	Do $$$AssertEquals(..Rows(session), 0, "no row was written")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(session), 0, "no event was published")
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set command = ##class(OcuTalon.Msg.Command.StartWatch).%New()
	Set command.SessionRef = session
	Set response = ""
	Set sc = probe.OnMessage(command, .response)
	Do $$$AssertTrue($$$ISERR(sc), "a message that is not a verb is an error status")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorCodes(sc) '= 5003, "that is not 5003")
	Do $$$AssertEquals(response, "", "with no answer")
	Set start = "OcuTalon.Schedule.ReminderOps: it carries out no OcuTalon.Msg.Command.StartWatch"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND Text %STARTSWITH ?", mark, start)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "one error is logged that names the class")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND Text %STARTSWITH ?", mark, start)
	Do $$$AssertEquals(..Rows(session), 0, "and no row was written")
}

/// The session's pending reminders, earliest due first, with ref, text and dueAt as strings; only the session's pending ones; the list
/// is what Tools.CommandCall.Listed reads (DW-135); a session with none gets an empty list. The earlier row's Text is saved as the
/// number 100, which reads back as a number, so a list item that is not typed as a string would carry a JSON number.
Method TestListShape()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogicls" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set other = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogiclo" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set empty = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogicle" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session _ "," _ other _ "," _ empty
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set dueLater = ##class(OcuTalon.Data.Time).AddSeconds(now, 900)
	Set dueEarlier = ##class(OcuTalon.Data.Time).AddSeconds(now, 300)
	Set later = ##class(OcuTalon.Test.Data.Fixture).Reminder(session, dueLater, "pending")
	Set earlier = ##class(OcuTalon.Test.Data.Fixture).Reminder(session, dueEarlier, "pending", {"Text": 100})
	Set fired = ##class(OcuTalon.Test.Data.Fixture).Reminder(session, ##class(OcuTalon.Data.Time).AddSeconds(now, 100), "fired")
	Set cancelled = ##class(OcuTalon.Test.Data.Fixture).Reminder(session, ##class(OcuTalon.Data.Time).AddSeconds(now, 200), "cancelled")
	Set foreign = ##class(OcuTalon.Test.Data.Fixture).Reminder(other, ##class(OcuTalon.Data.Time).AddSeconds(now, 50), "pending")
	Set ..Refs = ..Refs _ "," _ later _ "," _ earlier _ "," _ fired _ "," _ cancelled _ "," _ foreign
	Set probe = ##class(Ens.Host).GetShadowInstance("class||" _ ..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(probe) Quit
	Set command = ##class(OcuTalon.Msg.Command.ListReminders).%New()
	Set command.SessionRef = session
	Set response = ""
	Set sc = probe.OnMessage(command, .response)
	Do $$$AssertStatusOK(sc, "the status is OK")
	If '$IsObject(response) {
		Do $$$AssertTrue(0, "a CommandResult comes back")
		Quit
	}
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|listed", "the answer is listed")
	Do $$$AssertEquals(response.Message, "These are the session's pending reminders, earliest first.", "with the message for the model")
	Set laterText = ##class(OcuTalon.Data.Reminder).RefIndexOpen(later).Text
	Do $$$AssertEquals(response.Data, "{""reminders"":[{""ref"":"""_earlier_""",""text"":""100"",""dueAt"":"""_dueEarlier_"""},{""ref"":"""_later_""",""text"":"""_laterText_""",""dueAt"":"""_dueLater_"""}]}", "Data holds the two pending reminders of the session, earliest first, with a text of digits as a string")
	Set listed = ##class(OcuTalon.Tools.CommandCall).Listed(response)
	Do $$$AssertEquals(listed.ok, 1, "the list tool reads it: ok")
	Do $$$AssertEquals(listed.reminders.%Size(), 2, "with two reminders")
	If listed.reminders.%Size() = 2 {
		Do $$$AssertEquals(listed.reminders.%Get(0).ref_"|"_listed.reminders.%Get(1).ref, earlier_"|"_later, "in due order")
	}
	Set command = ##class(OcuTalon.Msg.Command.ListReminders).%New()
	Set command.SessionRef = empty
	Set response = ""
	Set sc = probe.OnMessage(command, .response)
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Data, "1|listed|{""reminders"":[]}", "a session with none gets an empty list")
	Set listed = ##class(OcuTalon.Tools.CommandCall).Listed(response)
	Do $$$AssertEquals(listed.ok_"|"_listed.reminders.%Size(), "1|0", "which the list tool reads as an empty list")
}

/// A CancelReminder for a session through the probe (a shadow instance), with the key.
Method CancelCommand(session As %String, ref As %String, key As %String) As OcuTalon.Msg.Command.CancelReminder [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.CancelReminder).%New()
	Set command.SessionRef = session
	Set command.ReminderRef = ref
	Set command.IdempotencyKey = key
	Quit command
}

/// A pending fixture reminder with no waiter is cancelled: the row is cancelled with the CancelKey, one cancelled event is published and
/// no trigger is sent. The same key again gives the first result and no second event; another key gives no_reminder.
Method TestCancelFixtureRow()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogiccf" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set ref = ..DueReminder(session, -600)
	Set dueAt = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref).DueAt
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Schedule.ReminderOpsSendProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(probe) Quit
	Set response = ""
	Set sc = probe.OnMessage(..CancelCommand(session, ref, "zzcancelkey"), .response)
	Do $$$AssertStatusOK(sc, "the status is OK")
	If '$IsObject(response) {
		Do $$$AssertTrue(0, "a CommandResult comes back")
		Quit
	}
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Message_"|"_response.Ref_"|"_response.DueAt, "1|cancelled|The reminder is cancelled.|"_ref_"|"_dueAt, "the answer confirms with the Ref and the due time")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.CancelKey, "cancelled|zzcancelkey", "the row is cancelled with the key")
	Set row = ""
	Do $$$AssertEquals(..EventStates(session), "cancelled", "one cancelled event is published")
	Set response = ""
	Set sc = probe.OnMessage(..CancelCommand(session, ref, "zzcancelkey"), .response)
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref_"|"_response.DueAt, "1|cancelled|"_ref_"|"_dueAt, "the same key again gets the first result")
	Do $$$AssertEquals(..EventStates(session), "cancelled", "with no second event")
	Set response = ""
	Set sc = probe.OnMessage(..CancelCommand(session, ref, "zzcancelother"), .response)
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Message, "0|refused|This session has no pending reminder with that ref; it may have fired or been cancelled already. Nothing was cancelled.", "another key for the cancelled reminder is no_reminder")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Do $$$AssertEquals(row.CancelKey, "zzcancelkey", "and the row keeps its key")
	Set row = ""
	Do $$$AssertEquals(..EventStates(session), "cancelled", "with no event")
}

/// Starts the job that holds the row's lock for the seconds (and then saves it with the state, when one is given) and waits until it
/// holds it. 1 when it does.
Method HoldRow(ref As %String, seconds As %Integer, state As %String = "") As %Boolean [ Private ]
{
	Kill ^OcuTalonTest("ReminderLogic", "held", ref), ^OcuTalonTest("ReminderLogic", "release", ref)
	Job ##class(OcuTalon.Test.Schedule.ReminderLogic).HoldLock(ref, seconds, state)::10
	Set started = $Test
	Do $$$AssertTrue(started, "a job is started that holds the row's lock")
	If 'started Quit 0
	Set end = $ZHorolog + 10
	While '$Data(^OcuTalonTest("ReminderLogic", "held", ref)) && (end > $ZHorolog) {
		Hang 0.1
	}
	Set held = $Data(^OcuTalonTest("ReminderLogic", "held", ref)) > 0
	Do $$$AssertTrue(held, "and it holds it")
	Quit held
}

/// Waits until the job that held the row's lock has let go.
Method LetGo(ref As %String) [ Private ]
{
	Set ^OcuTalonTest("ReminderLogic", "release", ref) = 1
	Set end = $ZHorolog + 60
	While $Data(^OcuTalonTest("ReminderLogic", "held", ref)) && (end > $ZHorolog) {
		Hang 0.1
	}
	Do $$$AssertEquals($Data(^OcuTalonTest("ReminderLogic", "held", ref)), 0, "the other job lets go")
}

/// A reminder that fires while the cancel waits for the row's lock: the job holds the lock for a few seconds and marks the row fired
/// before it lets go, so the cancel sees fired under the lock and is refused no_reminder. Nothing changes: no CancelKey, no event.
Method TestCancelRacesFire()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogiccr" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set ref = ..DueReminder(session, -600)
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Schedule.ReminderOpsSendProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(probe) Quit
	If '..HoldRow(ref, 3, "fired") Quit
	Set response = ""
	Set sc = probe.OnMessage(..CancelCommand(session, ref, "zzracekey"), .response)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Message, "0|refused|This session has no pending reminder with that ref; it may have fired or been cancelled already. Nothing was cancelled.", "the cancel is refused no_reminder")
	Do ..LetGo(ref)
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.CancelKey, "fired|", "the row is fired, with no CancelKey")
	Set row = ""
	Do $$$AssertEquals(..EventStates(session), "", "and no cancelled event is published")
}

/// A row whose lock stays busy past the process lock timeout: the cancel answers failed, logs one warning that names the Ref and
/// changes nothing. It needs a process lock timeout under HOLDSECONDS (the default is 10 seconds).
Method TestCancelBusyRowFails()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogiccb" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set ref = ..DueReminder(session, -600)
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Schedule.ReminderOpsSendProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(probe) Quit
	If '..HoldRow(ref, ..#HOLDSECONDS) Quit
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set response = ""
	Set sc = probe.OnMessage(..CancelCommand(session, ref, "zzbusykey"), .response)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Message, "0|failed|"_##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED, "the cancel answers failed")
	Set start = "OcuTalon.Schedule.ReminderOps: the row of " _ ref _ " is locked"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Text %STARTSWITH ?", mark, start)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "one warning is logged with the Ref")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Text %STARTSWITH ?", mark, start)
	Do ..LetGo(ref)
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.CancelKey, "pending|", "the row stays pending, with no CancelKey")
	Set row = ""
	Do $$$AssertEquals(..EventStates(session), "", "no event is published")
}

/// A SetReminder with a key that an earlier SetReminder of the session used: the same fields get the first result with no second row or
/// event; another Text, or an absolute form naming another instant, is reused_key; a relative form compares only the Text; a repeat of a
/// row whose time has passed still gets its first result; an empty key makes two rows.
Method TestSetRepeat()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogicsr" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ session
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Schedule.ReminderOpsStartedProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	If '$IsObject(probe) Quit
	Set reused = "0|refused|This call reused the key of a different earlier call, so nothing was done."
	Set due = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)
	Set command = ..Command(session, "zz first", due)
	Set command.IdempotencyKey = "zzsetkey"
	Set sc = probe.OnMessage(command, .one)
	Do $$$AssertEquals(one.Ok_"|"_one.Outcome_"|"_one.DueAt, "1|set|"_due, "the first command is set")
	Do $$$AssertEquals(..Rows(session), 1, "one row")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "reminder").%Size(), 1, "and one created event")
	Set again = ..Command(session, "zz first", due)
	Set again.IdempotencyKey = "zzsetkey"
	Set sc = probe.OnMessage(again, .two)
	Do $$$AssertEquals(two.Ok_"|"_two.Outcome_"|"_two.Message_"|"_two.Ref_"|"_two.DueAt, one.Ok_"|"_one.Outcome_"|"_one.Message_"|"_one.Ref_"|"_one.DueAt, "the same key and fields get the first result")
	Do $$$AssertEquals(..Rows(session), 1, "with no second row")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "reminder").%Size(), 1, "and no second event")
	Set other = ..Command(session, "zz other", due)
	Set other.IdempotencyKey = "zzsetkey"
	Set sc = probe.OnMessage(other, .three)
	Do $$$AssertEquals(three.Ok_"|"_three.Outcome_"|"_three.Message, reused, "the same key with another Text is reused_key")
	Set other = ..Command(session, "zz first", ##class(OcuTalon.Data.Time).AddSeconds(due, 60))
	Set other.IdempotencyKey = "zzsetkey"
	Set sc = probe.OnMessage(other, .three)
	Do $$$AssertEquals(three.Ok_"|"_three.Outcome_"|"_three.Message, reused, "the same key with an absolute form naming another instant is reused_key")
	Set other = ..Command(session, "zz first", "")
	Set other.IdempotencyKey = "zzsetkey"
	Set other.LocalDueAt = ##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).AddSeconds(due, 60))
	Set sc = probe.OnMessage(other, .three)
	Do $$$AssertEquals(three.Ok_"|"_three.Outcome_"|"_three.Message, reused, "and so is a local form naming another instant")
	Do $$$AssertEquals(..Rows(session), 1, "none of them makes a row")
	Set relative = ..Command(session, "zz relative", "")
	Set relative.IdempotencyKey = "zzrelkey"
	Set relative.DelaySeconds = 600
	Set sc = probe.OnMessage(relative, .four)
	Set relative = ..Command(session, "zz relative", "")
	Set relative.IdempotencyKey = "zzrelkey"
	Set relative.DelaySeconds = 600
	Set sc = probe.OnMessage(relative, .five)
	Do $$$AssertEquals(five.Ok_"|"_five.Ref_"|"_five.DueAt, four.Ok_"|"_four.Ref_"|"_four.DueAt, "a relative form repeated gets the first result")
	Do $$$AssertEquals(..Rows(session), 2, "with no third row")
	Set localTime = ##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 900))
	Set local = ..Command(session, "zz local", "")
	Set local.IdempotencyKey = "zzlockey"
	Set local.LocalDueAt = localTime
	Set sc = probe.OnMessage(local, .localOne)
	Set local = ..Command(session, "zz local", "")
	Set local.IdempotencyKey = "zzlockey"
	Set local.LocalDueAt = localTime
	Set sc = probe.OnMessage(local, .localTwo)
	Do $$$AssertEquals(localOne.Ok_"|"_localOne.Outcome, "1|set", "a local form with a key is set")
	Do $$$AssertEquals(localTwo.Ok_"|"_localTwo.Ref_"|"_localTwo.DueAt, localOne.Ok_"|"_localOne.Ref_"|"_localOne.DueAt, "a local form repeated gets the first result")
	Do $$$AssertEquals(..Rows(session), 3, "with no fourth row")
	Set elsewhere = ##class(OcuTalon.Test.Data.Fixture).Session("zzlogicsr" _ $Increment(^OcuTalonTest("ReminderLogic", "n")))
	Set ..Refs = ..Refs _ "," _ elsewhere
	Set other = ..Command(elsewhere, "zz first", due)
	Set other.IdempotencyKey = "zzsetkey"
	Set sc = probe.OnMessage(other, .eight)
	Do $$$AssertEquals(eight.Ok_"|"_eight.Outcome, "1|set", "the key of another session is not seen: the same key and fields set a reminder")
	Do $$$AssertTrue(eight.Ref '= one.Ref, "with a reminder of its own")
	Do $$$AssertEquals(..Rows(elsewhere), 1, "one row in the other session")
	Set passed ="2020-01-01T10:00:00Z"
	Set pastRef = ##class(OcuTalon.Test.Data.Fixture).Reminder(session, passed, "pending", {"Text": "zz passed", "IdempotencyKey": "zzpastkey"})
	Set ..Refs = ..Refs _ "," _ pastRef
	Set repeat = ..Command(session, "zz passed", passed)
	Set repeat.IdempotencyKey = "zzpastkey"
	Set sc = probe.OnMessage(repeat, .six)
	Do $$$AssertEquals(six.Ok_"|"_six.Outcome_"|"_six.Ref_"|"_six.DueAt, "1|set|"_pastRef_"|"_passed, "a repeat of a row whose time has passed gets its first result, not past")
	Set before = ..Rows(session)
	For i = 1, 2 {
		Set none = ..Command(session, "zz no key", due)
		Set none.IdempotencyKey = ""
		Set sc = probe.OnMessage(none, .seven)
		Do $$$AssertEquals(seven.Ok_"|"_seven.Outcome, "1|set", "an empty key sets a reminder: "_i)
	}
	Do $$$AssertEquals(..Rows(session), before + 2, "twice, with two rows")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Reminder WHERE SessionRef = ? AND IdempotencyKey = 'zzsetkey'", session)
	Set rows = 0
	While result.%Next() {
		Set rows = rows + 1
	}
	Do $$$AssertEquals(rows, 1, "the row of the first command carries its key")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Reminder WHERE SessionRef = ? AND CreatedAt >= ?", session, ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -3600))
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

/// The job that holds the row's exclusive lock until the test sets the flag under release, for at most the seconds; the flag under held
/// tells that it does. When a state is given, the job saves the row with that state before it lets go.
ClassMethod HoldLock(ref As %String, seconds As %Integer, state As %String = "")
{
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref, 4)
	If '$IsObject(row) Quit
	Set ^OcuTalonTest("ReminderLogic", "held", ref) = 1
	Set end = $ZHorolog + seconds
	While '$Data(^OcuTalonTest("ReminderLogic", "release", ref)) && (end > $ZHorolog) {
		Hang 0.1
	}
	If state '= "" {
		Set row.State = state
		Do row.%Save()
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
