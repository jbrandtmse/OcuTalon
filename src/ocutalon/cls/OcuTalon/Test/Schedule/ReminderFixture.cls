/// The one helper of the reminder tests that sets and removes a product-made reminder (Story 8.3), for the unit tests of
/// OcuTalon.Test.Schedule.Reminders and for the browser spec (web/e2e/reminder/reminder.spec.ts), which runs it through irisScript. It has
/// no Test methods and the product never refers to it.
///   - Set submits a SetReminder for a session through Commands.Submit under a bridge context of the session, as the chat's tool does, and
///     returns what the test needs to know about the reminder and its waiter;
///   - Remove deletes the reminder and everything the product made for it.
Class OcuTalon.Test.Schedule.ReminderFixture Extends %RegisteredObject
{

/// Sets a reminder of the session with the text, due that many seconds from now. Returns {ok, outcome, ref, dueAt, traceHeaderId,
/// alarmHeaderId}: the CommandResult's Ok and Outcome, its Ref and DueAt, the row's TraceHeaderId, and the id of the ReminderTimer to
/// Ens.Alarm request in the waiter's session ("" for each that does not exist). The context is the bridge context of the session
/// (OwnerRef the session, SuperSession its TraceRef) and is ended before Set returns.
ClassMethod Set(sessionRef As %String, text As %String, seconds As %Integer) As %DynamicObject
{
	Set found = {"ok": 0, "outcome": "", "ref": "", "dueAt": "", "traceHeaderId": "", "alarmHeaderId": ""}
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef)
	If '$IsObject(session) Quit found
	Set command = ##class(OcuTalon.Msg.Command.SetReminder).%New()
	Set command.SessionRef = sessionRef
	Set command.Text = text
	Set command.IdempotencyKey = "zzrem" _ $Increment(^OcuTalonTest("ReminderFixture", "n"))
	Set command.DueAt = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), seconds)
	Set begin = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set begin.OwnerRef = sessionRef
	Do ##class(OcuTalon.Bridge.Context).Begin(begin, session.TraceRef)
	Try {
		Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "tool", .result)
	} Catch exception {
		Set sc = exception.AsStatus()
		Set result = ""
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	If $SYSTEM.Status.IsError(sc) || '$IsObject(result) Quit found
	Set found.ok = +result.Ok
	Set found.outcome = result.Outcome
	Set found.ref = result.Ref
	Set found.dueAt = result.DueAt
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(result.Ref)
	If '$IsObject(row) || (row.TraceHeaderId = "") Quit found
	Set found.traceHeaderId = +row.TraceHeaderId
	Set alarms = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(row.TraceHeaderId), 1, "ReminderTimer", "Ens.Alarm")
	If alarms.%Size() > 0 Set found.alarmHeaderId = alarms.%Get(0).id
	Quit found
}

/// Removes the reminder with the Ref and what the product made for it, whatever its state:
///   - the session's web Delivery rows of kind reminder with the reminder's DueAt;
///   - the session's phone Delivery rows of kind reminder recorded since the reminder was created, with their SimMessages;
///   - the headers of the waiter's trace session (its TraceHeaderId), with their bodies and their event-log, rule-log and I/O-log rows;
///   - the ReminderTimer instances with that Ref;
///   - the Reminder row.
/// It does nothing for a Ref that has no row.
ClassMethod Remove(ref As %String)
{
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	If '$IsObject(row) Quit
	Set id = row.%Id(), session = row.SessionRef, dueAt = row.DueAt, createdAt = row.CreatedAt, trace = row.TraceHeaderId
	Set row = ""
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND Channel = 'web' AND Kind = 'reminder' AND DueAt = ?", session, dueAt)
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, ChannelMessageId FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND Channel = 'phone' AND Kind = 'reminder' AND RecordedAt >= ?", session, createdAt)
	While result.%Next() {
		Set messages(result.%Get("ID")) = result.%Get("ChannelMessageId")
	}
	Set at = ""
	For {
		Set at = $Order(messages(at), 1, message)
		Quit:at=""
		Do ##class(OcuTalon.Data.SimMessage).RefIndexDelete(message)
		Do ##class(OcuTalon.Data.Delivery).%DeleteId(at)
	}
	If trace '= "" Do ..RemoveSession(trace)
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Schedule.ReminderTimer WHERE Ref = ?", ref)
	While result.%Next() {
		Set timers(result.%Get("ID")) = ""
	}
	Set at = ""
	For {
		Set at = $Order(timers(at))
		Quit:at=""
		Do ##class(OcuTalon.Schedule.ReminderTimer).%DeleteId(at)
	}
	Do ##class(OcuTalon.Data.Reminder).%DeleteId(id)
}

/// Deletes every header of the trace session with its body and the session's event-log, rule-log and I/O-log rows.
ClassMethod RemoveSession(sessionId As %String) [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ?", sessionId)
	While result.%Next() {
		Set headers(result.%Get("ID")) = $ListBuild(result.%Get("MessageBodyClassName"), result.%Get("MessageBodyId"))
	}
	Set at = ""
	For {
		Set at = $Order(headers(at), 1, body)
		Quit:at=""
		If $List(body, 1) '= "" Do $ClassMethod($List(body, 1), "%DeleteId", $List(body, 2))
		Do ##class(Ens.MessageHeader).%DeleteId(at)
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE SessionId = ?", sessionId)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Rule.Log WHERE SessionId = ?", sessionId)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.IOLog WHERE SessionId = ?", sessionId)
}

}
