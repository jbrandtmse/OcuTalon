/// The methods behind OcuTalon.Tools.Reminders (AD-1, AD-4, AD-7, AD-9, AD-10, AD-18): the three reminder tools of the Chat agent, set_reminder,
/// list_reminders and cancel_reminder. Each tool submits one of Epic 0's reminder commands through OcuTalon.Tools.CommandCall and returns the
/// owner's answer, so the tools never read or write a reminder themselves: ReminderOps owns the reminders and every check of a request
/// (empty text, a time that is past, not exactly one due form, a due time that cannot be read, a reminder that is not the session's).
/// The session comes from the bridge context of the call, never from an argument.
/// Each tool declares, by one naming rule (the tool's name in upper case with _ and - removed), its step label (STEPLABEL<NAME>, AD-9) and its
/// classification for the gate (CLASSIFICATION<NAME>: safe or risky; READONLY<NAME> and TRUSTEDOUTPUT<NAME>: 1 or 0, AD-10).
/// All three are safe and trusted output: their answers are built in code from the owner's CommandResult (CommandCall.Answer and Listed),
/// so a result never taints the turn, and two set_reminder calls in one response both run. list_reminders is read-only, so it also runs in an
/// untrusted or tainted turn. set_reminder and cancel_reminder are not read-only, so the gate denies them there. Listing stays trusted output
/// only because of that: every reminder's text was written in a user's untainted turn, and no text from outside one reaches a reminder.
/// It extends OcuTalon.Tools.Result and returns only through Return. A tool method runs inside AI Hub's callback, so it makes no AI Hub call
/// and no Python call (AD-6). The description of a tool is its method's doc comment, and an argument's DESCRIPTION is what the model reads
/// about it: they are text for the model, never shown to the user as written.
Class OcuTalon.Tools.ReminderTools Extends OcuTalon.Tools.Result
{

/// The answer when delaySeconds is not a whole number of seconds; nothing is submitted.
Parameter BADDELAY = "delaySeconds must be a whole number of seconds, so nothing was done.";

Parameter STEPLABELSETREMINDER = "Setting a reminder";

Parameter STEPLABELLISTREMINDERS = "Listing your reminders";

Parameter STEPLABELCANCELREMINDER = "Cancelling a reminder";

Parameter CLASSIFICATIONSETREMINDER = "safe";

Parameter READONLYSETREMINDER = 0;

Parameter TRUSTEDOUTPUTSETREMINDER = 1;

Parameter CLASSIFICATIONLISTREMINDERS = "safe";

Parameter READONLYLISTREMINDERS = 1;

Parameter TRUSTEDOUTPUTLISTREMINDERS = 1;

Parameter CLASSIFICATIONCANCELREMINDER = "safe";

Parameter READONLYCANCELREMINDER = 0;

Parameter TRUSTEDOUTPUTCANCELREMINDER = 1;

/// Sets a reminder for the user in this conversation, to be delivered when it is due. Give exactly one way to say when: delaySeconds for a
/// relative time, such as in 10 minutes, or localDueAt for a day and time, such as Thursday at 10. Never give both. For localDueAt, work
/// out the date from the Local time line at the start of the user's message. The answer says whether the reminder was set. When it was, it
/// gives the reminder's ref and its due time. When it was not, the message says why, in plain English, so tell the user.
ClassMethod SetReminder(text As %String(DESCRIPTION = "What to remind the user of, in a few words, such as: stretch."), delaySeconds As %Integer(DESCRIPTION = "For a relative time: how many seconds from now the reminder is due, a whole number, such as 600 for in 10 minutes. Leave it out when you give localDueAt.") = "", localDueAt As %String(DESCRIPTION = "For a day and time: a local date and time without a zone, in the form YYYY-MM-DDThh:mm:ss, such as 2026-10-29T10:00:00 for Thursday at 10. Leave it out when you give delaySeconds.") = "") As %DynamicObject
{
	If (delaySeconds '= "") && (delaySeconds '? 1.N) Quit ..Return({"ok": false, "message": (..#BADDELAY)})
	Set command = ##class(OcuTalon.Msg.Command.SetReminder).%New()
	Set command.Text = text
	Set command.DelaySeconds = delaySeconds
	Set command.LocalDueAt = localDueAt
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Run(command, .result)
	If $IsObject(refusal) Quit ..Return(refusal)
	Quit ..Return(##class(OcuTalon.Tools.CommandCall).Answer(result))
}

/// Lists the reminders that are still pending for the user in this conversation, the soonest first. Each has a ref, its text and its due
/// time. Use it to answer which reminders the user has, and to find the ref of a reminder that the user wants to cancel.
ClassMethod ListReminders() As %DynamicObject
{
	Set command = ##class(OcuTalon.Msg.Command.ListReminders).%New()
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Run(command, .result)
	If $IsObject(refusal) Quit ..Return(refusal)
	Quit ..Return(##class(OcuTalon.Tools.CommandCall).Listed(result))
}

/// Cancels one pending reminder of the user in this conversation. Give the ref that list_reminders gave for it. The answer says whether the
/// reminder was cancelled. When it was not, the message says why, in plain English, so tell the user.
ClassMethod CancelReminder(reminderRef As %String(DESCRIPTION = "The ref of the reminder, exactly as list_reminders gave it.")) As %DynamicObject
{
	Set command = ##class(OcuTalon.Msg.Command.CancelReminder).%New()
	Set command.ReminderRef = reminderRef
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Run(command, .result)
	If $IsObject(refusal) Quit ..Return(refusal)
	Quit ..Return(##class(OcuTalon.Tools.CommandCall).Answer(result))
}

}
