Include Ensemble

/// The reminder logic of the frozen ReminderTimer waiter and of ReminderOps (AD-5, AD-18, AD-32). The Reminder row is the truth and the
/// waiter mirrors it.
///   - Resolve is the due-form rule of a SetReminder, which ReminderOps applies; SecondsUntil, IsLate and Notification are pure;
///   - Start is the waiter's OnRequest: it stores the waiter's start header id on the pending row (the target of the row's trace link),
///     sets the timer for the time until DueAt (key due) and replies to the start, so that ReminderOps returns while the waiter keeps
///     waiting. For a row that is missing or not pending it only replies;
///   - Wake is the waiter's OnResponse. It opens the row with an exclusive lock. A missing or non-pending row ends the waiter and sends
///     nothing. A wake before DueAt sets the timer again for the rest. Otherwise, holding the lock, it marks the row fired (Late when it
///     woke more than LATESECONDS after DueAt) and saves it, sends one Notification of kind reminder to Notify (reminder.due, or
///     reminder.late when Late), releases the lock and publishes the reminder event (fired). A failed send is logged with the Ref and not
///     retried, so that a reminder never fires twice. The open waits for the lock up to the process's lock timeout ($$$LockTimeout);
///     a row whose lock is still busy then is tried again a second later.
/// Times go only through OcuTalon.Data.Time, and no text is rendered here: the Notification carries a catalog key and its slots.
Class OcuTalon.Schedule.Reminder
{

/// The completion key of the timer.
Parameter TIMERKEY = "due";

/// A reminder is late when the waiter woke more than this many seconds after DueAt.
Parameter LATESECONDS = 10;

/// The item that carries Notifications to the channels.
Parameter NOTIFYITEM = "Notify";

/// The due-form rule of a SetReminder, pure: "" with dueAt set to the UTC due time (YYYY-MM-DDThh:mm:ssZ), or one refusal code, the
/// first of these that holds, in this order:
///   - no_text: the Text is blank after stripping whitespace and control characters (a line break included) from both ends;
///   - due_forms: not exactly one of DueAt, DelaySeconds and LocalDueAt is set;
///   - bad_time: the one form cannot be read: a DueAt that Data.Time.Seconds cannot read, a DelaySeconds that is not an optionally
///     signed whole number or whose AddSeconds result is "", or a LocalDueAt that Data.Time.FromLocal gives "" for;
///   - past: the due time is not later than now, a DelaySeconds of 0 or less included.
/// DelaySeconds counts from now, and LocalDueAt is read in the instance zone. dueAt is "" for a refusal.
ClassMethod Resolve(command As OcuTalon.Msg.Command.SetReminder, now As %String = {##class(OcuTalon.Data.Time).NowUtc()}, Output dueAt As %String) As %String
{
	Set dueAt = ""
	If $ZStrip(command.Text, "<>WC") = "" Quit "no_text"
	If ((command.DueAt '= "") + (command.DelaySeconds '= "") + (command.LocalDueAt '= "")) '= 1 Quit "due_forms"
	If command.DueAt '= "" {
		Set due = command.DueAt
	} ElseIf command.DelaySeconds '= "" {
		Set delay = command.DelaySeconds
		If delay '? .1(1"+",1"-")1.N Quit "bad_time"
		Set due = ##class(OcuTalon.Data.Time).AddSeconds(now, +delay)
	} Else {
		Set due = ##class(OcuTalon.Data.Time).FromLocal(command.LocalDueAt)
	}
	Set dueSeconds = ##class(OcuTalon.Data.Time).Seconds(due)
	If dueSeconds = "" Quit "bad_time"
	Set current = ##class(OcuTalon.Data.Time).Seconds(now)
	If (current = "") || (dueSeconds '> current) Quit "past"
	Set dueAt = due
	Quit ""
}

/// The whole seconds from now until dueAt, at least 1 (also for a time that is past or unreadable).
ClassMethod SecondsUntil(dueAt As %String, now As %String = {##class(OcuTalon.Data.Time).NowUtc()}) As %Integer
{
	Set due = ##class(OcuTalon.Data.Time).Seconds(dueAt)
	Set current = ##class(OcuTalon.Data.Time).Seconds(now)
	If (due = "") || (current = "") Quit 1
	Set seconds = due - current
	Quit $Select(seconds < 1: 1, 1: seconds)
}

/// 1 when now is more than LATESECONDS after dueAt; exactly LATESECONDS is on time.
ClassMethod IsLate(dueAt As %String, now As %String = {##class(OcuTalon.Data.Time).NowUtc()}) As %Boolean
{
	Set due = ##class(OcuTalon.Data.Time).Seconds(dueAt)
	Set current = ##class(OcuTalon.Data.Time).Seconds(now)
	If (due = "") || (current = "") Quit 0
	Quit ((current - due) > ..#LATESECONDS)
}

/// The Notification of a fired reminder, unsaved: Kind reminder for the row's session, with the key reminder.due and the slots
/// {"text","dueAt"}, or, when late, the key reminder.late and {"time","text","dueAt"} where time is the due time.
ClassMethod Notification(row As OcuTalon.Data.Reminder, late As %Boolean) As OcuTalon.Msg.Notification
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = row.SessionRef
	Set notification.Kind = "reminder"
	Set slots = {}
	If late Do slots.%Set("time", row.DueAt, "string")
	Do slots.%Set("text", row.Text, "string")
	Do slots.%Set("dueAt", row.DueAt, "string")
	Set notification.CatalogKey = $Select(late: "reminder.late", 1: "reminder.due")
	Set notification.Slots = slots.%ToJSON()
	Quit notification
}

/// The waiter's OnRequest: stores the Ref on the process; for a pending row writes the start header's id to the row's TraceHeaderId,
/// sets the timer for the time until DueAt, and replies to the start.
ClassMethod Start(timer As OcuTalon.Schedule.ReminderTimer, request As OcuTalon.Schedule.ReminderStart, Output response As %Persistent) As %Status [ Internal ]
{
	Set response = ""
	Set ref = request.Ref
	Set timer.Ref = ref
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref, 4)
	If $IsObject(row) && (row.State = "pending") {
		Set dueAt = row.DueAt
		Set row.TraceHeaderId = timer.%PrimaryRequestHeader.%Id()
		Set sc = row.%Save()
		Set row = ""
		If $$$ISERR(sc) Quit sc
		Set sc = timer.SetTimer(..SecondsUntil(dueAt), ..#TIMERKEY)
		If $$$ISERR(sc) Quit sc
	}
	Set row = ""
	Quit timer.Reply(##class(Ens.Response).%New())
}

/// The waiter's OnResponse: the firing rule of the class description.
ClassMethod Wake(timer As OcuTalon.Schedule.ReminderTimer, completionKey As %String) As %Status [ Internal ]
{
	Set ref = timer.Ref
	Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(ref, 4, .sc)
	If '$IsObject(row) {
		If $ListFind($ListFromString($SYSTEM.Status.GetErrorCodes($Get(sc))), $$$LockFailedToAcquireExclusive) {
			$$$LOGWARNING("OcuTalon.Schedule.Reminder: the row of " _ ref _ " is locked; the waiter tries again in a second")
			Quit timer.SetTimer(1, ..#TIMERKEY)
		}
		Quit $$$OK
	}
	If row.State '= "pending" Quit $$$OK
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set due = ##class(OcuTalon.Data.Time).Seconds(row.DueAt)
	If (due '= "") && (##class(OcuTalon.Data.Time).Seconds(now) < due) {
		Set seconds = ..SecondsUntil(row.DueAt, now)
		Set row = ""
		Quit timer.SetTimer(seconds, ..#TIMERKEY)
	}
	Set late = ..IsLate(row.DueAt, now)
	Set row.State = "fired"
	Set row.Late = late
	Set sc = row.%Save()
	If $$$ISERR(sc) Quit sc
	Set notification = ..Notification(row, late)
	Set payload = ##class(OcuTalon.Live.Payload.Reminder).FromRow(row)
	Set session = row.SessionRef
	Set sent = timer.SendRequestAsync(..#NOTIFYITEM, notification, 0)
	If $$$ISERR(sent) {
		$$$LOGERROR("OcuTalon.Schedule.Reminder: the notification of " _ ref _ " was not sent to " _ ..#NOTIFYITEM _ ": " _ $SYSTEM.Status.GetErrorText(sent))
	}
	Set row = ""
	Set published = ##class(OcuTalon.Live.Publish).Publish(session, "reminder", payload, .seq)
	If $$$ISERR(published) {
		$$$LOGWARNING("OcuTalon.Schedule.Reminder: the reminder event (fired) of " _ ref _ " was not published: " _ $SYSTEM.Status.GetErrorText(published))
	}
	Quit $$$OK
}

}
