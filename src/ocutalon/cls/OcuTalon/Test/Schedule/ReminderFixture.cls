/// The one helper of the reminder tests that sets, cancels and removes a product-made reminder, for the unit tests of
/// OcuTalon.Test.Schedule (Reminders, ReminderChat) and for the browser specs that run it through irisScript (web/e2e/reminder/*.spec.ts
/// and web/e2e/demo-path/03-reminder.spec.ts). It has no Test methods and the product never refers to it.
///   - Begin starts the bridge context of a session as a chat tool call has it (OwnerRef the session, ItemId, SuperSession its TraceRef);
///     the caller ends it with Bridge.Context.End;
///   - Submit sends a command through Commands.Submit under such a context and ends it;
///   - Set submits a SetReminder for a session and returns what the test needs to know about the reminder and its waiter;
///   - Cancel submits a CancelReminder for a session and returns the answer;
///   - Remove cancels the reminder if it is pending, waits for its waiter to end, and deletes the reminder and everything the product
///     made for it;
///   - CancelPending cancels each pending reminder of a session through Cancel and answers how many were cancelled;
///   - RemoveAll removes every reminder of a session, whatever its state, through Remove;
///   - RemoveTurns removes every chat turn of a session with the Decision, AgentStep and Usage rows the product made for it;
///   - Timers, IsWaiting and WaitEnded tell whether the reminder's waiter is waiting, and WaitingCount how many of its waiters are;
///   - StartHeaders lists the ReminderStart headers of a reminder, one per waiter that was started for it (ReminderOps, or HeartbeatIn
///     for a re-arm).
Class OcuTalon.Test.Schedule.ReminderFixture Extends %RegisteredObject
{

/// Starts the bridge context of the session as a chat tool call has it: OwnerRef the session, ItemId the given one (by default a fresh
/// zzitem<n>) and SuperSession the session's TraceRef. An error status when the session does not exist. The caller ends the context.
ClassMethod Begin(sessionRef As %String, itemId As %String = "") As %Status
{
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef)
	If '$IsObject(session) Quit $SYSTEM.Status.Error(5001, "There is no session " _ sessionRef)
	Set begin = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set begin.OwnerRef = sessionRef
	Set begin.ItemId = $Select(itemId '= "": itemId, 1: "zzitem" _ $Increment(^OcuTalonTest("ReminderFixture", "item")))
	Quit ##class(OcuTalon.Bridge.Context).Begin(begin, session.TraceRef)
}

/// Sends the command through Commands.Submit under the bridge context of the session (Begin) and ends the context before it returns.
/// Returns the CommandResult, or "" when the session does not exist or Submit gives an error.
ClassMethod Submit(sessionRef As %String, command As OcuTalon.Msg.Command) As OcuTalon.Msg.CommandResult
{
	Set result = ""
	If $SYSTEM.Status.IsError(..Begin(sessionRef)) Quit ""
	Try {
		Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "tool", .result)
	} Catch exception {
		Set sc = exception.AsStatus()
		Set result = ""
	}
	Do ##class(OcuTalon.Bridge.Context).End()
	If $SYSTEM.Status.IsError(sc) Quit ""
	Quit result
}

/// Cancels the reminder with the Ref for the session, with the key (by default a fresh zzcan<n>). Returns {ok, outcome, message, ref,
/// dueAt, data}: every member of the CommandResult, or ok 0 with an empty outcome when no answer came back.
ClassMethod Cancel(sessionRef As %String, ref As %String, key As %String = "") As %DynamicObject
{
	Set command = ##class(OcuTalon.Msg.Command.CancelReminder).%New()
	Set command.SessionRef = sessionRef
	Set command.ReminderRef = ref
	Set command.IdempotencyKey = $Select(key '= "": key, 1: "zzcan" _ $Increment(^OcuTalonTest("ReminderFixture", "cancel")))
	Set result = ..Submit(sessionRef, command)
	If '$IsObject(result) Quit {"ok": 0, "outcome": "", "message": "", "ref": "", "dueAt": "", "data": ""}
	Quit {"ok": (+result.Ok), "outcome": (result.Outcome), "message": (result.Message), "ref": (result.Ref), "dueAt": (result.DueAt), "data": (result.Data)}
}

/// Sets a reminder of the session with the text, due that many seconds from now. Returns {ok, outcome, ref, dueAt, traceHeaderId,
/// alarmHeaderId}: the CommandResult's Ok and Outcome, its Ref and DueAt, the row's TraceHeaderId, and the id of the ReminderTimer to
/// Ens.Alarm request in the waiter's session ("" for each that does not exist). The context is the bridge context of the session
/// (OwnerRef the session, SuperSession its TraceRef) and is ended before Set returns.
ClassMethod Set(sessionRef As %String, text As %String, seconds As %Integer) As %DynamicObject
{
	Set found = {"ok": 0, "outcome": "", "ref": "", "dueAt": "", "traceHeaderId": "", "alarmHeaderId": ""}
	Set command = ##class(OcuTalon.Msg.Command.SetReminder).%New()
	Set command.SessionRef = sessionRef
	Set command.Text = text
	Set command.IdempotencyKey = "zzrem" _ $Increment(^OcuTalonTest("ReminderFixture", "n"))
	Set command.DueAt = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), seconds)
	Set result = ..Submit(sessionRef, command)
	If '$IsObject(result) Quit found
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

/// Removes the reminder with the Ref and what the product made for it, whatever its state. A pending reminder is first cancelled
/// through Cancel, which ends its waiter. Then Remove waits at most 10 seconds until no ReminderTimer with the Ref is waiting, and:
///   - the session's web Delivery rows of kind reminder with the reminder's DueAt;
///   - the session's phone Delivery rows of kind reminder recorded since the reminder was created, with their SimMessages;
///   - the headers of the waiter's trace session (its TraceHeaderId), and of the trace session of every ReminderStart header of the
///     Ref (StartHeaders: a re-armed waiter has its own), with their bodies and their event-log, rule-log and I/O-log rows;
///   - the ReminderTimer instances with that Ref;
///   - the Reminder row.
/// It does nothing for a Ref that has no row.
ClassMethod Remove(ref As %String)
{
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	If '$IsObject(row) Quit
	If row.State = "pending" {
		Set owner = row.SessionRef
		Set row = ""
		Do ..Cancel(owner, ref)
	}
	Set row = ""
	Do ..WaitEnded(ref, 10)
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
	Set starts = ..StartHeaders(ref)
	If trace '= "" Do ..RemoveSession(trace)
	For i = 0:1:starts.%Size() - 1 {
		Set started = starts.%Get(i).sessionId
		If (started '= "") && (started '= trace) Do ..RemoveSession(started)
	}
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

/// Cancels each pending reminder of the session through Cancel, which ends its waiter, and answers how many were answered cancelled.
/// The rows are read first and let go before the first cancel, which locks its row.
ClassMethod CancelPending(sessionRef As %String) As %Integer
{
	Set pending = ##class(OcuTalon.Data.Ownership).Reminders(sessionRef)
	Set refs = ""
	For i = 1:1:pending.Count() {
		Set refs = refs _ $ListBuild(pending.GetAt(i).Ref)
	}
	Set pending = ""
	Set cancelled = 0
	Set position = 0
	While $ListNext(refs, position, ref) {
		Set answer = ..Cancel(sessionRef, ref)
		If answer.ok_"|"_answer.outcome = "1|cancelled" Set cancelled = cancelled + 1
	}
	Quit cancelled
}

/// Removes every reminder of the session, whatever its state, through Remove.
ClassMethod RemoveAll(sessionRef As %String)
{
	Set refs = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Reminder WHERE SessionRef = ?", sessionRef)
	While result.%Next() {
		Set refs = refs _ $ListBuild(result.%Get("Ref"))
	}
	Set result = ""
	Set position = 0
	While $ListNext(refs, position, ref) {
		Do ..Remove(ref)
	}
}

/// Removes every Turn row of the session with what the product made for it: the AgentStep rows of its requests
/// (RunnerFixture.DeleteSteps), the Usage rows of its Item, and its triage and turn Decision rows (Fixture.AdoptTurns, then
/// Fixture.Clean of those Refs only). The AI sessions that the turns saved are the caller's (RunnerFixture.DropSince).
ClassMethod RemoveTurns(sessionRef As %String)
{
	Set items = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ItemId FROM OcuTalon_Data.Turn WHERE SessionRef = ? AND ItemId IS NOT NULL", sessionRef)
	While result.%Next() {
		Set items = items _ $ListBuild(result.%Get("ItemId"))
	}
	Set result = ""
	Set position = 0
	While $ListNext(items, position, itemId) {
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).DeleteSteps(itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(sessionRef, "")
	If refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(refs)
}

/// The ReminderTimer instances with the Ref, as an array of their ids.
ClassMethod Timers(ref As %String) As %DynamicArray
{
	Set ids = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Schedule.ReminderTimer WHERE Ref = ?", ref)
	While result.%Next() {
		Do ids.%Push(result.%Get("ID"))
	}
	Quit ids
}

/// 1 when the ReminderTimer is waiting: not completed, not terminated, and still waiting for a response.
ClassMethod IsWaiting(id As %String) As %Boolean
{
	Set timer = ##class(OcuTalon.Schedule.ReminderTimer).%OpenId(id)
	If '$IsObject(timer) Quit 0
	Quit 'timer.%IsCompleted && 'timer.%IsTerminated && (timer.%MasterPendingResponses.Count() > 0)
}

/// The number of ReminderTimer instances with the Ref that are waiting (Timers and IsWaiting).
ClassMethod WaitingCount(ref As %String) As %Integer
{
	Set timers = ..Timers(ref)
	Set waiting = 0
	For i = 0:1:timers.%Size() - 1 {
		If ..IsWaiting(timers.%Get(i)) Set waiting = waiting + 1
	}
	Quit waiting
}

/// The ReminderStart headers whose body names the Ref, oldest first, as an array of {id, sessionId, superSession, source, target,
/// status}. A waiter that ReminderOps started has a header from ReminderOps; a re-armed one from HeartbeatIn.
ClassMethod StartHeaders(ref As %String) As %DynamicArray
{
	Set headers = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT h.ID AS Id, h.SessionId AS SessionId, h.SuperSession AS SuperSession, h.SourceConfigName AS Source, h.TargetConfigName AS Target, h.Status AS Status FROM Ens.MessageHeader h JOIN OcuTalon_Schedule.ReminderStart b ON b.%ID = h.MessageBodyId WHERE h.MessageBodyClassName = 'OcuTalon.Schedule.ReminderStart' AND b.Ref = ? ORDER BY h.ID", ref)
	While result.%Next() {
		Do headers.%Push({"id": (result.%Get("Id")), "sessionId": (result.%Get("SessionId")), "superSession": (result.%Get("SuperSession")), "source": (result.%Get("Source")), "target": (result.%Get("Target")), "status": (result.%Get("Status"))})
	}
	Quit headers
}

/// Waits until no ReminderTimer with the Ref is waiting any more (a completed waiter is deleted by the framework), for at most seconds.
/// Answers 1 when none is.
ClassMethod WaitEnded(ref As %String, seconds As %Integer) As %Boolean
{
	Set end = $ZHorolog + seconds
	For {
		Set waiting = ..WaitingCount(ref)
		If 'waiting || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit 'waiting
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
