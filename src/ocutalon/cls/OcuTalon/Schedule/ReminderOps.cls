Include Ensemble

/// ReminderOps, the business operation that carries out the three reminder commands, SetReminder, ListReminders and CancelReminder
/// (AD-1, AD-4, AD-5, AD-18). The Reminder row is the truth. Every verb first checks the command's session (an empty SessionRef, or
/// one that names no Session row, is refused no_session). Then:
///   - SetReminder applies the repeat rule for a non-empty IdempotencyKey, resolves the one due form to a UTC DueAt (Reminder.Resolve:
///     a refusal creates nothing), then
///     - saves the Reminder row (pending) with the command's key;
///     - starts one ReminderTimer waiter, synchronously, in a trace session of its own whose SuperSession is the session row's
///       TraceRef (AD-26): it clears the session id and sets the SuperSession for the start and puts both back after it, so that its
///       own answer stays in the command's session. The waiter writes its start header id to the row before it answers. A start that
///       fails or gets no answer in STARTSECONDS deletes the row and answers failed;
///     - publishes the reminder event (created) after the save; a failed publish is a warning, and the row and the waiter stay;
///     - answers Ok 1, outcome set, with the reminder's Ref and DueAt;
///   - ListReminders answers the session's pending reminders, earliest due first, as Data {"reminders":[{"ref","text","dueAt"}]}, read
///     through Data.Ownership (outcome listed);
///   - CancelReminder cancels a pending reminder of the session, found through Data.Ownership. Under the row's exclusive lock it
///     re-checks that the row is pending, marks it cancelled with the command's key as CancelKey and saves it. After it has let go it
///     publishes the reminder event (cancelled) and ends the waiter at once: it sends an Ens.AlarmTriggerRequest to Ens.Alarm for the
///     waiter's alarm, in the waiter's own trace session. A failed publish or interrupt is a warning, and the waiter then ends at its
///     due time, sending nothing because its row is no longer pending. The answer is Ok 1, outcome cancelled, with the Ref and DueAt.
///     A lock that cannot be taken in the process lock timeout answers failed and changes nothing.
/// A command with a key that an earlier command of the same verb used in the session is a repeat: the same fields get the first
/// result and change nothing, other fields are refused reused_key (set: the Text, and for an absolute form the instant; cancel: the
/// Ref). ListReminders is read-only and answers the current list. An empty key turns repeat detection off. The two key lookups are
/// this operation's own session-scoped reads of its own table; every read of a target that the caller names goes through Ownership.
/// A refusal is Ok 0, outcome refused, with the plain-English Message of its code (the MESSAGE parameters); the messages are for the
/// model and are never shown as written. An error thrown while carrying out a verb is logged and answers failed. A message that is
/// not one of the three verbs is logged and answered with an error status that is not code 5003, so that CommandsIn answers failed.
/// The pool of the item is 1, so its commands are handled one at a time; the check of a key and the write that follows need that.
Class OcuTalon.Schedule.ReminderOps Extends Ens.BusinessOperation
{

/// Seconds to wait for the waiter's answer to its start.
Parameter STARTSECONDS = 10;

/// The item that waits for one reminder.
Parameter TIMERITEM = "ReminderTimer";

/// The platform's alarm host, which an Ens.AlarmTriggerRequest interrupts an alarm through.
Parameter ALARMITEM = "Ens.Alarm";

/// The Message of the answer to a reminder that is set. It is for the model and is never shown as it is written.
Parameter MESSAGESET = "The reminder is set.";

/// The Message of the answer to ListReminders.
Parameter MESSAGELISTED = "These are the session's pending reminders, earliest first.";

/// The Message of the answer to a reminder that is cancelled.
Parameter MESSAGECANCELLED = "The reminder is cancelled.";

/// The Message of the refusal no_session.
Parameter MESSAGENOSESSION = "This conversation has no signed-in session, so nothing was done.";

/// The Message of the refusal no_text.
Parameter MESSAGENOTEXT = "The reminder has no text, so nothing was set.";

/// The Message of the refusal due_forms.
Parameter MESSAGEDUEFORMS = "A reminder needs exactly one due time, either delaySeconds or localDueAt, so nothing was set.";

/// The Message of the refusal bad_time.
Parameter MESSAGEBADTIME = "The due time could not be read, so nothing was set. Give delaySeconds as a whole number of seconds, or localDueAt as a local date and time in the form YYYY-MM-DDThh:mm:ss.";

/// The Message of the refusal past.
Parameter MESSAGEPAST = "That time has already passed, so nothing was set.";

/// The Message of the refusal no_reminder: one text for an unknown, another session's, a fired and a cancelled reminder.
Parameter MESSAGENOREMINDER = "This session has no pending reminder with that ref; it may have fired or been cancelled already. Nothing was cancelled.";

/// The Message of the refusal reused_key.
Parameter MESSAGEREUSEDKEY = "This call reused the key of a different earlier call, so nothing was done.";

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Set pResponse = ""
	Set command = $Get(pRequest)
	Set class = $Select($IsObject(command): $ClassName(command), 1: "")
	If '$ListFind($ListBuild("OcuTalon.Msg.Command.SetReminder", "OcuTalon.Msg.Command.ListReminders", "OcuTalon.Msg.Command.CancelReminder"), class) {
		$$$LOGERROR("OcuTalon.Schedule.ReminderOps: it carries out no " _ $Select(class = "": "message that is not an object", 1: class))
		Quit $SYSTEM.Status.Error(5001, "ReminderOps carries out only SetReminder, ListReminders and CancelReminder")
	}
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Try {
		If class = "OcuTalon.Msg.Command.SetReminder" {
			Set pResponse = ..Set(command, now)
		} ElseIf class = "OcuTalon.Msg.Command.ListReminders" {
			Set pResponse = ..List(command)
		} Else {
			Set pResponse = ..Cancel(command)
		}
	} Catch exception {
		$$$LOGERROR(exception.DisplayString())
		Set pResponse = ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
	}
	Quit $$$OK
}

/// Sets the reminder of the command and returns the CommandResult to answer.
Method Set(command As OcuTalon.Msg.Command.SetReminder, now As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	If '..SessionExists(command.SessionRef) Quit ..Refuse("no_session")
	If command.IdempotencyKey '= "" {
		Set first = ..KeyedRow("IdempotencyKey", command.SessionRef, command.IdempotencyKey)
		If first '= "" Quit ..Repeated(first, command)
	}
	Set code = ##class(OcuTalon.Schedule.Reminder).Resolve(command, now, .dueAt)
	If code '= "" Quit ..Refuse(code)
	Set row = ##class(OcuTalon.Data.Reminder).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = command.SessionRef
	Set row.Text = command.Text
	Set row.DueAt = dueAt
	Set row.State = "pending"
	Set row.Late = 0
	Set row.CreatedAt = now
	Set row.IdempotencyKey = command.IdempotencyKey
	Set sc = row.%Save()
	If $$$ISERR(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Set ref = row.Ref, session = row.SessionRef, id = row.%Id()
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
	Quit ..Done("set", ..#MESSAGESET, ref, dueAt)
}

/// The answer to a SetReminder whose key an earlier SetReminder of the session used (the row, as $ListBuild(Ref, Text, DueAt)): the
/// first result when the Text is the same and, for an absolute form (DueAt or LocalDueAt), the instant is the row's DueAt; otherwise
/// reused_key. A command with more or fewer than one due form is a different command.
Method Repeated(first As %List, command As OcuTalon.Msg.Command.SetReminder) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set same = ((command.DueAt '= "") + (command.DelaySeconds '= "") + (command.LocalDueAt '= "")) = 1
	If same && (command.Text '= $List(first, 2)) Set same = 0
	If same && (command.DueAt '= "") Set same = (command.DueAt = $List(first, 3))
	If same && (command.LocalDueAt '= "") Set same = (##class(OcuTalon.Data.Time).FromLocal(command.LocalDueAt) = $List(first, 3))
	If 'same Quit ..Refuse("reused_key")
	Quit ..Done("set", ..#MESSAGESET, $List(first, 1), $List(first, 3))
}

/// Answers the session's pending reminders, earliest due first.
Method List(command As OcuTalon.Msg.Command.ListReminders) As OcuTalon.Msg.CommandResult [ Private ]
{
	If '..SessionExists(command.SessionRef) Quit ..Refuse("no_session")
	Set rows = ##class(OcuTalon.Data.Ownership).Reminders(command.SessionRef, .sc)
	If $$$ISERR($Get(sc, 1)) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Set list = []
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		Set item = {}
		Do item.%Set("ref", row.Ref, "string")
		Do item.%Set("text", row.Text, "string")
		Do item.%Set("dueAt", row.DueAt, "string")
		Do list.%Push(item)
	}
	Set rows = "", row = ""
	Set result = ..Result(1, "listed", ..#MESSAGELISTED)
	Set result.Data = {"reminders": (list)}.%ToJSON()
	Quit result
}

/// Cancels the session's pending reminder that the command names.
Method Cancel(command As OcuTalon.Msg.Command.CancelReminder) As OcuTalon.Msg.CommandResult [ Private ]
{
	If '..SessionExists(command.SessionRef) Quit ..Refuse("no_session")
	Set ref = command.ReminderRef
	If command.IdempotencyKey '= "" {
		Set first = ..KeyedRow("CancelKey", command.SessionRef, command.IdempotencyKey)
		If first '= "" {
			If $List(first, 1) '= ref Quit ..Refuse("reused_key")
			Quit ..Done("cancelled", ..#MESSAGECANCELLED, $List(first, 1), $List(first, 3))
		}
	}
	If '..IsPending(command.SessionRef, ref) Quit ..Refuse("no_reminder")
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref, 4, .sc)
	If '$IsObject(row) {
		If $ListFind($ListFromString($SYSTEM.Status.GetErrorCodes($Get(sc))), $$$LockFailedToAcquireExclusive) {
			$$$LOGWARNING("OcuTalon.Schedule.ReminderOps: the row of " _ ref _ " is locked, so it was not cancelled")
			Quit ..Result(0, "failed", ##class(OcuTalon.Core.CommandsIn).#MESSAGEFAILED)
		}
		Quit ..Refuse("no_reminder")
	}
	If row.State '= "pending" Quit ..Refuse("no_reminder")
	Set row.State = "cancelled"
	Set row.CancelKey = command.IdempotencyKey
	Set sc = row.%Save()
	If $$$ISERR(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Set session = row.SessionRef, dueAt = row.DueAt
	Set row = ""
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref)
	If $IsObject(row) {
		Set published = ##class(OcuTalon.Live.Publish).Publish(session, "reminder", ##class(OcuTalon.Live.Payload.Reminder).FromRow(row), .seq)
		If $$$ISERR(published) {
			$$$LOGWARNING("OcuTalon.Schedule.ReminderOps: the reminder event (cancelled) of " _ ref _ " was not published: " _ $SYSTEM.Status.GetErrorText(published))
		}
		Do ..EndWaiter(row)
	}
	Set row = ""
	Quit ..Done("cancelled", ..#MESSAGECANCELLED, ref, dueAt)
}

/// 1 when the Ref is one of the session's pending reminders (Data.Ownership, AD-4). The rows it opened are let go before it returns.
Method IsPending(sessionRef As %String, ref As %String) As %Boolean [ Private ]
{
	If ref = "" Quit 0
	Set rows = ##class(OcuTalon.Data.Ownership).Reminders(sessionRef, .sc)
	If $$$ISERR($Get(sc, 1)) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Set found = 0
	For i = 1:1:rows.Count() {
		If rows.GetAt(i).Ref = ref Set found = 1
	}
	Quit found
}

/// The session's earliest row whose key property is the key, as $ListBuild(Ref, Text, DueAt), or "". The statement is bound to the
/// session of the command, so a key of another session is never seen. No row is left open.
ClassMethod KeyedRow(property As %String, sessionRef As %String, key As %String) As %List [ Private ]
{
	If property = "IdempotencyKey" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Reminder WHERE SessionRef = ? AND IdempotencyKey = ? ORDER BY ID", sessionRef, key)
	} Else {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.Reminder WHERE SessionRef = ? AND CancelKey = ? ORDER BY ID", sessionRef, key)
	}
	If 'result.%Next() Quit ""
	Set row = ##class(OcuTalon.Data.Reminder).%OpenId(result.%Get("ID"))
	If '$IsObject(row) Quit ""
	Quit $ListBuild(row.Ref, row.Text, row.DueAt)
}

/// Ends the waiter of the row at once (AD-5, AD-26): sends an Ens.AlarmTriggerRequest to Ens.Alarm for each alarm that the waiter's
/// ReminderTimer has not completed, in the waiter's own trace session (the row's TraceHeaderId) under the session's TraceRef. The
/// alarm's handle is the id of its Ens.AlarmRequest body. A row with no waiter yet, a session that has gone, or a failed send is
/// a warning at most: the waiter then ends at its due time and sends nothing, because the row is no longer pending.
Method EndWaiter(row As OcuTalon.Data.Reminder) [ Private ]
{
	Set traceId = row.TraceHeaderId
	If traceId = "" Quit
	Set ref = row.Ref
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(row.SessionRef)
	If '$IsObject(session) Quit
	Set superSession = session.TraceRef
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ? AND TargetConfigName = ? AND MessageBodyClassName = 'Ens.AlarmRequest' AND Status <> 9 ORDER BY ID", traceId, ..#TIMERITEM, ..#ALARMITEM)
	While result.%Next() {
		Set handles($Increment(handles)) = result.%Get("MessageBodyId")
	}
	For i = 1:1:+$Get(handles) {
		Set trigger = ##class(Ens.AlarmTriggerRequest).%New(handles(i))
		Set sc = ..SendIn(..#ALARMITEM, trigger, traceId, superSession, 1)
		If $$$ISERR(sc) {
			$$$LOGWARNING("OcuTalon.Schedule.ReminderOps: the waiter of " _ ref _ " was not interrupted, so it ends at its due time: " _ $SYSTEM.Status.GetErrorText(sc))
		}
	}
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
	Set sc = ..SendIn(..#TIMERITEM, start, "", session.TraceRef, 0, .response)
	If $$$ISOK(sc) && '$IsObject($Get(response)) {
		Set sc = $SYSTEM.Status.Error(5001, "ReminderTimer did not answer the start of " _ row.Ref _ " within " _ ..#STARTSECONDS _ " seconds")
	}
	Quit sc
}

/// The one send of this class: the request to the target with this operation's session id and SuperSession set to the given ones
/// (the trace session of a waiter, AD-26), synchronously (waiting STARTSECONDS for response) or not (no answer comes back). Both are
/// put back afterwards, also when the send throws, whose error is the status.
Method SendIn(target As %String, request As %Library.Persistent, sessionId As %String, superSession As %String, async As %Boolean, Output response As %Library.Persistent) As %Status [ Private ]
{
	Set savedId = ..%SessionId, savedSuper = ..%SuperSession
	Set ..%SessionId = sessionId, ..%SuperSession = superSession
	Try {
		If async {
			Set sc = ..SendRequestAsync(target, request)
		} Else {
			Set sc = ..SendRequestSync(target, request, .response, ..#STARTSECONDS)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Set ..%SessionId = savedId, ..%SuperSession = savedSuper
	Quit sc
}

/// 1 when the Ref names a Session row.
ClassMethod SessionExists(ref As %String) As %Boolean [ Private ]
{
	If $Get(ref) = "" Quit 0
	Quit $IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(ref))
}

/// The refusal with the code (no_session, no_text, due_forms, bad_time, past, no_reminder or reused_key): Ok 0, outcome refused, and
/// the code's Message.
ClassMethod Refuse(code As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Quit ..Result(0, "refused", $Parameter("OcuTalon.Schedule.ReminderOps", "MESSAGE" _ $ZConvert($Translate(code, "_"), "U")))
}

/// The answer to a command that was carried out: Ok 1, the outcome, the message, the reminder's Ref and DueAt.
ClassMethod Done(outcome As %String, message As %String, ref As %String, dueAt As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set result = ..Result(1, outcome, message)
	Set result.Ref = ref
	Set result.DueAt = dueAt
	Quit result
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
