Include Ensemble

/// The method behind OcuTalon.Tools.Email (AD-1, AD-4, AD-6, AD-9, AD-10, AD-16, AD-17, AD-25; Story 22.7): the send_email tool of the Chat agent.
///   - The classification is per call and is code's (ClassifySENDEMAIL, which only delegates to OcuTalon.Fix.Kind.Email): safe only when every recipient is the session user's own email
///     address, risky otherwise. A risky call in a user's turn never reaches the tool method: the gate calls HoldSENDEMAIL, which raises a request of the fix kind email and denies the call with
///     the gate's HELD sentence, and FixExecutor sends the email once after the user approves it. The tool is not read-only (READONLYSENDEMAIL 0), so in a turn that holds content that did
///     not come from the user, every send_email call is denied UNTRUSTED, one to the user's own address included.
///   - SendEmail runs only for a safe call. The session comes from the bridge context, never from an argument: a call that is not a session's turn answers NOSESSION and submits nothing. On the
///     online demo the answer is not_available with Channel.Email.Out's own sentence, and nothing is submitted. Otherwise it submits SendEmail through OcuTalon.Tools.CommandCall (origin tool,
///     IdempotencyKey the turn's ItemId, a colon and the command's position) to the one own address, and writes the kind's Action entry when the command was submitted.
///   - Trusted output (TRUSTEDOUTPUTSENDEMAIL 1): the answer is {ok, outcome, message}, built in code from the CommandResult of the owner (Channel.Email.Out and Core.CommandsIn): a boolean, the
///     owner's outcome word and its fixed sentence. It holds no recipient, subject, text or text of the mail server, so no content from outside a user's untainted turn reaches the model through it.
///     Test.Tools.Email pins the three members.
/// The tool declares, by the naming rule of OcuTalon.Tools.ReminderTools, its step label (STEPLABELSENDEMAIL, AD-9) and its classification flags (READONLYSENDEMAIL and TRUSTEDOUTPUTSENDEMAIL, AD-10), and
/// CLASSIFYRULESENDEMAIL is the rule that the security overview shows after "per call: ". The hooks are Internal, because a public method of a tool class becomes a tool, and they quit only through
/// ..Return like every method of the class. It extends OcuTalon.Tools.Result. A tool method runs inside AI Hub's callback, so this class makes no AI Hub call and no Python call (AD-6). The
/// description of the tool is its method's doc comment, and an argument's DESCRIPTION is what the model reads about it: they are text for the model, never shown to the user as written.
Class OcuTalon.Tools.EmailTools Extends OcuTalon.Tools.Result
{

Parameter STEPLABELSENDEMAIL = "Sending an email";

Parameter READONLYSENDEMAIL = 0;

Parameter TRUSTEDOUTPUTSENDEMAIL = 1;

/// The rule that the security overview shows after "per call: ".
Parameter CLASSIFYRULESENDEMAIL = "safe when every recipient is the user's own email address; otherwise risky, so it waits for approval";

/// Sends a plain-text email from the user's connected mailbox. Email to the user's own address is sent at once; email to anyone else becomes an approval request and is sent only after the user approves it. The answer says whether the email was sent.
ClassMethod SendEmail(recipients As %DynamicArray(DESCRIPTION = "The email addresses to send to: one or more, at most 20."), subject As %String(DESCRIPTION = "The subject, one line, at most 200 characters."), text As %String(DESCRIPTION = "The body of the email, plain text.")) As %DynamicObject
{
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Session(.context)
	If $IsObject(refusal) Quit ..Return(refusal)
	If ##class(OcuTalon.Watch.Reader).OnlineDemo() {
		Quit ..Return({"ok": false, "outcome": "not_available", "message": ($Parameter("OcuTalon.Channel.Email.Out", "MESSAGEUNAVAILABLE"))})
	}
	Set command = ##class(OcuTalon.Msg.Command.SendEmail).%New()
	Set command.Recipients = ##class(OcuTalon.Fix.Kind.Email).SendTo(recipients)
	Set command.Subject = subject
	Set command.Text = text
	Set refusal = ##class(OcuTalon.Tools.CommandCall).Run(command, .result)
	If $IsObject(refusal) Quit ..Return(refusal)
	Set sc = ##class(OcuTalon.Fix.Kind.Email).Audit(result.Outcome, "", context.OwnerRef, context.Channel, $Length(command.Recipients, ","))
	If $$$ISERR(sc) {
		$$$LOGWARNING("A send_email call could not write its audit entry: "_##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	}
	Set answer = {}
	Do answer.%Set("ok", +result.Ok, "boolean")
	Set answer.outcome = result.Outcome
	Set answer.message = result.Message
	Quit ..Return(answer)
}

/// The classification of a call, which the gate asks (AD-10): the email kind's rule. Internal, so that it is not a tool.
ClassMethod ClassifySENDEMAIL(arguments As %DynamicObject) As %String [ Internal ]
{
	Quit ..Return(##class(OcuTalon.Fix.Kind.Email).Classify(arguments))
}

/// The hold of a risky call in a user's turn, which the gate calls instead of raising a tool_call request (AD-10, AD-16): the email kind raises the request or sets the refusal.
ClassMethod HoldSENDEMAIL(arguments As %DynamicObject, ownerRef As %String, traceRef As %String, sinkClass As %String, Output ref As %String, Output refusal As %String) As %Status [ Internal ]
{
	Quit ..Return(##class(OcuTalon.Fix.Kind.Email).Raise(arguments, ownerRef, traceRef, sinkClass, .ref, .refusal))
}

}
