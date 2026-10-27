Include Ensemble

/// ReminderOps, the business operation that carries out the reminder commands (AD-1, AD-5, AD-18). Built so far: a SetReminder whose one
/// due form is a UTC DueAt (Reminder.Accepts) for a session that exists. It
///   - saves the Reminder row (pending);
///   - starts one ReminderTimer waiter, synchronously, in a trace session of its own whose SuperSession is the session row's TraceRef
///     (AD-26): it clears the session id and sets the SuperSession for the start and puts both back after it, so that its own answer
///     stays in the command's session. The waiter writes its start header id to the row before it answers. A start that fails or gets no
///     answer in STARTSECONDS deletes the row and answers failed;
///   - publishes the reminder event (created) after the save; a failed publish is a warning, and the row and the waiter stay;
///   - answers Ok 1, outcome set, with the reminder's Ref and DueAt.
/// Every other command and message, the other due forms, a refusal, ListReminders and CancelReminder included, is answered with the
/// not-implemented status and nothing is written, so that CommandsIn answers not_built. An error thrown while setting is logged and
/// answers failed.
Class OcuTalon.Schedule.ReminderOps Extends Ens.BusinessOperation
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

/// Seconds to wait for the waiter's answer to its start.
Parameter STARTSECONDS = 10;

/// The item that waits for one reminder.
Parameter TIMERITEM = "ReminderTimer";

/// The Message of the answer to a reminder that is set. It is for the model and is never shown as it is written.
Parameter MESSAGESET = "The reminder is set.";

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Set pResponse = ""
	Set command = $Get(pRequest)
	If '##class(OcuTalon.Schedule.Reminder).Accepts(command) || '..SessionExists(command.SessionRef) {
		Quit $$$ERROR($$$NotImplemented)
	}
	Try {
		Set pResponse = ..Set(command)
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
		Set pResponse = ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Quit $$$OK
}

/// Sets the reminder of the command and returns the CommandResult to answer.
Method Set(command As OcuTalon.Msg.Command.SetReminder) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set row = ##class(OcuTalon.Data.Reminder).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = command.SessionRef
	Set row.Text = command.Text
	Set row.DueAt = command.DueAt
	Set row.State = "pending"
	Set row.Late = 0
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = row.%Save()
	If $$$ISERR(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Set ref = row.Ref, dueAt = row.DueAt, session = row.SessionRef, id = row.%Id()
	Set sc = ..StartWaiter(row)
	Set row = ""
	If $$$ISERR(sc) {
		$$$LOGERROR("OcuTalon.Schedule.ReminderOps: the waiter of " _ ref _ " did not start: " _ $SYSTEM.Status.GetErrorText(sc))
		Do ##class(OcuTalon.Data.Reminder).%DeleteId(id)
		Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	If $IsObject(row) {
		Set published = ##class(OcuTalon.Live.Publish).Publish(session, "reminder", ##class(OcuTalon.Live.Payload.Reminder).FromRow(row), .seq)
		If $$$ISERR(published) {
			$$$LOGWARNING("OcuTalon.Schedule.ReminderOps: the reminder event (created) of " _ ref _ " was not published: " _ $SYSTEM.Status.GetErrorText(published))
		}
	}
	Set result = ..Result(1, "set", ..#MESSAGESET)
	Set result.Ref = ref
	Set result.DueAt = dueAt
	Quit result
}

/// Starts the row's waiter and waits for its answer (AD-26): the waiter's session begins at its start header and its SuperSession is
/// the TraceRef of the row's Session. This operation's own session id and SuperSession are put back after the start, also when it
/// throws. An error status when the start fails or gets no answer in STARTSECONDS. A test subclass overrides it.
Method StartWaiter(row As OcuTalon.Data.Reminder) As %Status [ Private ]
{
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(row.SessionRef)
	If '$IsObject(session) Quit $SYSTEM.Status.Error(5001, "There is no session " _ row.SessionRef)
	Set start = ##class(OcuTalon.Schedule.ReminderStart).%New()
	Set start.Ref = row.Ref
	Set sessionId = ..%SessionId, superSession = ..%SuperSession
	Set ..%SessionId = "", ..%SuperSession = session.TraceRef
	Try {
		Set sc = ..SendRequestSync(..#TIMERITEM, start, .response, ..#STARTSECONDS)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Set ..%SessionId = sessionId, ..%SuperSession = superSession
	If $$$ISOK(sc) && '$IsObject($Get(response)) {
		Set sc = $SYSTEM.Status.Error(5001, "ReminderTimer did not answer the start of " _ row.Ref _ " within " _ ..#STARTSECONDS _ " seconds")
	}
	Quit sc
}

/// 1 when the Ref names a Session row.
ClassMethod SessionExists(ref As %String) As %Boolean [ Private ]
{
	If $Get(ref) = "" Quit 0
	Quit $IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(ref))
}

/// A CommandResult with the outcome and the message.
ClassMethod Result(ok As %Boolean, outcome As %String, message As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = ok
	Set result.Outcome = outcome
	Set result.Message = message
	Quit result
}

}
