/// The fix kind that sends one email from the chat to anyone but the user (AD-16, Story 22.7). It has no incident: the gate raises its request for a risky send_email call in a
/// user's turn (Raise, through the hold hook of OcuTalon.Tools.EmailTools), and FixExecutor sends the approved email itself, once, with origin system.
///   - The parameters are {"recipients": [address, ...], "subject", "text"}, validated by CheckParameters against the limits of Channel.Email.Out (read with $Parameter, never copied). The
///     targets are the recipients' positions 1..n (TARGETTYPE recipient), and the stored dry run is {"to": [every recipient], "subject", "text"}, the exact values that the approval covers.
///   - Classify gives safe only when the call's parameters are valid and every recipient is the session user's own address (OwnAddressOnly), and risky otherwise, also for bad input and
///     for an exception. It reads only the call's recipients, subject and text, the stored product keys email.address and email.owner (Data.Setting.Fresh) and the context's OwnerRef.
///   - Raise refuses before it raises anything, with Channel.Email.Out's sentence: on the online demo (MESSAGEUNAVAILABLE), with no mailbox address (MESSAGENOTCONNECTED) and for
///     parameters that CheckParameters or the dry run refuses (MESSAGEREFUSED; the dry run also refuses recipients too long for a SendEmail command). Otherwise it raises one fix request with no incident and ResultTarget FixExecutor through Approval.Raise.
///   - Execute submits the approved email as a SendEmail command with origin system, the request's ApprovalRef, the owner's session, the subject and the text and no recipients (EmailOut
///     reads them from the request's row), and answers {sent, outcome, message} from the CommandResult; it sends nothing itself. FixExecutor calls it after StartExecution, so one approval sends once; Out claims the approval as the second guard.
///   - MayApprove is the interim approver rule of an email request (DW-1262): an approval of an email to anyone but the owner's own address is answered only by a holder of the role
///     OcuTalonAdmin. AnswerOps asks it before every approve.
///   - Audit writes the one Action entry of a send (tool or approved): the action email, the target EmailOut, the outcome, the number of recipients sent to and, for an approved send, the IRIS user who approved it (AD-17). It holds no address, subject or text.
/// Lane A.
Class OcuTalon.Fix.Kind.Email Extends OcuTalon.Fix.Kind
{

Parameter NAME = "email";

Parameter PARAMETERS = "recipients,subject,text";

Parameter RESOURCES;

Parameter TARGETTYPE = "recipient";

Parameter DIAGNOSED = 0;

Parameter ASKED = 0;

/// The production item that receives the outcome of the request.
Parameter RESULTTARGET = "FixExecutor";

/// The class whose limits and sentences this kind uses.
Parameter OUT = "OcuTalon.Channel.Email.Out";

/// The FixRun Reason of an approved email that could not start: expired, unreadable or not as approved (public text, veto 22.7).
Parameter EMAILNOSTART = "OcuTalon couldn't start sending the email, so it wasn't sent.";

/// The target and the action of the Action entry.
Parameter AUDITTARGET = "EmailOut";

/// The schema check of the base does not fit the array: recipients is an array of 1 to the limit of addresses, subject is one line of 1 to the limit of characters and text is 1 to the limit of
/// characters in which only a tab, a line feed and a carriage return are control characters; the keys are exactly PARAMETERS.
ClassMethod CheckParameters(parameters As %DynamicObject, fields As %DynamicArray) As %Status
{
	If '$IsObject(parameters) || 'parameters.%IsA("%Library.DynamicObject") {
		Quit $$$ERROR($$$GeneralError, "The parameters of "_..#NAME_" are not a JSON object")
	}
	Set names = $ListFromString(..#PARAMETERS)
	Set iterator = parameters.%GetIterator()
	While iterator.%GetNext(.key) {
		If '$ListFind(names, key) Return $$$ERROR($$$GeneralError, "The parameter '"_key_"' is not one of "_..#PARAMETERS)
	}
	Set recipients = parameters.%Get("recipients")
	If parameters.%GetTypeOf("recipients") '= "array" Quit $$$ERROR($$$GeneralError, "The parameter 'recipients' of "_..#NAME_" is required and is an array")
	If (recipients.%Size() < 1) || (recipients.%Size() > $Parameter(..#OUT, "MAXRECIPIENTS")) {
		Quit $$$ERROR($$$GeneralError, "The parameter 'recipients' of "_..#NAME_" holds 1 to "_$Parameter(..#OUT, "MAXRECIPIENTS")_" addresses")
	}
	For i = 0:1:recipients.%Size() - 1 {
		If (recipients.%GetTypeOf(i) '= "string") || '##class(OcuTalon.Core.SettingsOps).IsAddress(recipients.%Get(i)) {
			Return $$$ERROR($$$GeneralError, "The parameter 'recipients' of "_..#NAME_" holds an entry that is not an email address")
		}
	}
	Set subject = parameters.%Get("subject")
	If (parameters.%GetTypeOf("subject") '= "string") || ($ZStrip(subject, "<>W") = "") || ($Length(subject) > $Parameter(..#OUT, "SUBJECTMAX")) || (..HasControl(subject)) {
		Quit $$$ERROR($$$GeneralError, "The parameter 'subject' of "_..#NAME_" is required and is one line of 1 to "_$Parameter(..#OUT, "SUBJECTMAX")_" characters")
	}
	Set text = parameters.%Get("text")
	If (parameters.%GetTypeOf("text") '= "string") || ($ZStrip(text, "<>WC") = "") || ($Length(text) > $Parameter(..#OUT, "TEXTMAX")) || (..HasControl($Translate(text, $Char(9, 10, 13)))) {
		Quit $$$ERROR($$$GeneralError, "The parameter 'text' of "_..#NAME_" is required and is 1 to "_$Parameter(..#OUT, "TEXTMAX")_" characters")
	}
	Quit $$$OK
}

/// 1 when the text holds a control character.
ClassMethod HasControl(text As %String) As %Boolean [ Private ]
{
	Quit ($ZStrip(text, "*C") '= text)
}

/// The parameters of a send_email call's arguments: the members recipients (each string trimmed), subject and text, and no other member, so that no extra key of the call has any
/// effect. A recipient of another type is kept as it is, and an object or array becomes an empty string, for CheckParameters to refuse.
ClassMethod Parameters(arguments As %DynamicObject) As %DynamicObject
{
	Set parameters = {}
	If '$IsObject(arguments) || 'arguments.%IsA("%Library.DynamicObject") Quit parameters
	If arguments.%GetTypeOf("recipients") = "array" {
		Set list = []
		Set iterator = arguments.recipients.%GetIterator()
		While iterator.%GetNext(, .value, .type) {
			Set nested = ((type = "object") || (type = "array"))
			Do list.%Push($Select(type = "string": $ZStrip(value, "<>W"), nested: "", 1: value), $Select(nested: "string", 1: type))
		}
		Set parameters.recipients = list
	}
	For name = "subject", "text" {
		If arguments.%GetTypeOf(name) = "string" Do parameters.%Set(name, arguments.%Get(name), "string")
	}
	Quit parameters
}

/// 1 when a mailbox exists with a valid address, the mailbox belongs to the session of ownerRef (email.owner), recipients is an array of 1 to MAXRECIPIENTS strings and every one of them,
/// trimmed and lower-cased, equals the address, trimmed and lower-cased. Both keys are read from their rows and never from the per-process cache. The one Lane A copy of the rule
/// of CommandsIn and of Out.
ClassMethod OwnAddressOnly(ownerRef As %String, recipients As %DynamicArray) As %Boolean
{
	Set own = 0
	Try {
		Set address = $ZConvert($ZStrip(##class(OcuTalon.Data.Setting).Fresh(..Address()), "<>W"), "L")
		If '##class(OcuTalon.Core.SettingsOps).IsAddress(address) Quit
		If ($Get(ownerRef) = "") || (##class(OcuTalon.Data.Setting).Fresh($Parameter(..#OUT, "OWNERKEY")) '= ownerRef) Quit
		If '$IsObject(recipients) || 'recipients.%IsA("%Library.DynamicArray") Quit
		If (recipients.%Size() < 1) || (recipients.%Size() > $Parameter(..#OUT, "MAXRECIPIENTS")) Quit
		Set own = 1
		For i = 0:1:recipients.%Size() - 1 {
			If (recipients.%GetTypeOf(i) '= "string") || ($ZConvert($ZStrip(recipients.%Get(i), "<>W"), "L") '= address) Set own = 0
		}
	} Catch {
		Set own = 0
	}
	Quit own
}

/// The product key that holds the mailbox's address.
ClassMethod Address() As %String [ Private ]
{
	Quit $Parameter(..#OUT, "ADDRESSKEY")
}

/// safe when the call's parameters pass CheckParameters and every recipient is the session user's own address (OwnAddressOnly, the context's OwnerRef), and risky for everything else:
/// no context, bad input and an exception. Nothing else of the call classifies it.
ClassMethod Classify(arguments As %DynamicObject) As %String
{
	Set classification = "risky"
	Try {
		If '##class(OcuTalon.Bridge.Context).Active() Quit
		Set parameters = ..Parameters(arguments)
		If $$$ISERR(..CheckParameters(parameters, "")) Quit
		If ..OwnAddressOnly(##class(OcuTalon.Bridge.Context).Current().OwnerRef, parameters.recipients) Set classification = "safe"
	} Catch {
		Set classification = "risky"
	}
	Quit classification
}

/// The targets 1..n (the recipients' positions) and the dry run {"to", "subject", "text"} of the parameters, which change nothing. incident is not used (an email has none). An error status
/// that says why when the parameters do not pass CheckParameters, or when the recipients, joined by commas, do not fit the Recipients of a SendEmail command (its own validation, so that the list stays one that EmailOut can check).
ClassMethod DryRun(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, Output targets As %String, Output dryRun As %DynamicObject) As %Status
{
	Set targets = ""
	Set dryRun = ""
	Set sc = ..CheckParameters(parameters, "")
	If $$$ISERR(sc) Quit sc
	If $$$ISERR(##class(OcuTalon.Msg.Command.SendEmail).RecipientsIsValid(..Joined(parameters.recipients))) {
		Quit $$$ERROR($$$GeneralError, "The parameter 'recipients' of "_..#NAME_" is longer than a SendEmail command holds")
	}
	For i = 1:1:parameters.recipients.%Size() {
		Set targets = targets _ $Select(targets = "": "", 1: ",") _ i
	}
	Set dryRun = {"to": (parameters.recipients), "subject": (parameters.subject), "text": (parameters.text)}
	Quit $$$OK
}

/// Every target passes: the recipients are the approved ones and nothing outside the row is read.
ClassMethod Recheck(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output passed As %String, Output skipped As %DynamicArray) As %Status
{
	Set passed = targets
	Set skipped = []
	Quit $$$OK
}

/// 1 when the stored dry run of the row is exactly the parameters it would send: the same recipients in the same order, subject and text. A dry run or parameters that cannot be read give 0.
ClassMethod AsApproved(dryRun As %DynamicObject, parameters As %DynamicObject) As %Boolean
{
	Set same = 0
	Try {
		If (dryRun.%GetTypeOf("to") '= "array") || (parameters.%GetTypeOf("recipients") '= "array") Quit
		Set same = (dryRun.to.%ToJSON() = parameters.recipients.%ToJSON()) && (dryRun.%GetTypeOf("subject") = "string") && (dryRun.%Get("subject") = parameters.%Get("subject")) && (dryRun.%GetTypeOf("text") = "string") && (dryRun.%Get("text") = parameters.%Get("text"))
	} Catch {
		Set same = 0
	}
	Quit same
}

/// Submits the approved email as a SendEmail command with origin system, the ApprovalRef of the run and the SessionRef of the request's owner, the parameters' subject and text and
/// no recipients: EmailOut takes the recipients from the approval's row, so that no address is in the command or in its trace (DW-1255). result is {"sent": 1 or 0, "outcome", "message"} from the CommandResult. A command that never reached CommandsIn is not sent, with Out's MESSAGEFAILED.
ClassMethod Execute(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output result As %DynamicObject, run As OcuTalon.Data.FixRun = "") As %Status
{
	Set result = {"sent": 0, "outcome": "failed", "message": ($Parameter(..#OUT, "MESSAGEFAILED"))}
	Set row = $Select($IsObject(run): ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(run.ApprovalRef), 1: "")
	If '$IsObject(row) Quit $$$OK
	Set command = ##class(OcuTalon.Msg.Command.SendEmail).%New()
	Set command.SessionRef = row.OwnerRef
	Set command.ApprovalRef = row.Ref
	Set command.Subject = parameters.subject
	Set command.Text = parameters.text
	Set answered = ""
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "system", .answered)
	If $$$ISERR(sc) || '$IsObject(answered) Quit $$$OK
	Set result = {"sent": (+answered.Ok), "outcome": (answered.Outcome), "message": (answered.Message)}
	Quit $$$OK
}

/// The recipients of an approved email as the Recipients of its SendEmail command: the entries as they are, joined by commas.
ClassMethod Joined(recipients As %DynamicArray) As %String [ Private ]
{
	Set joined = ""
	Set iterator = recipients.%GetIterator()
	While iterator.%GetNext(, .address) {
		Set joined = joined _ $Select(joined = "": "", 1: ",") _ address
	}
	Quit joined
}

/// Raises the request of a risky send_email call (see the class description). arguments is the call's arguments, ownerRef and traceRef those of the context and sinkClass the host sink
/// of the gate. ref is the new request's Ref. refusal is the sentence of a call that is refused before anything is raised, and then ref is empty and the status is OK. An error status
/// when Approval.Raise fails (no row is left).
ClassMethod Raise(arguments As %DynamicObject, ownerRef As %String, traceRef As %String, sinkClass As %String, Output ref As %String, Output refusal As %String) As %Status
{
	Set ref = ""
	Set refusal = ""
	Set sc = $$$OK
	Try {
		If +##class(OcuTalon.Data.Setting).Get("onlineDemo") '= 0 {
			Set refusal = $Parameter(..#OUT, "MESSAGEUNAVAILABLE")
			Quit
		}
		If '##class(OcuTalon.Core.SettingsOps).IsAddress($ZStrip(##class(OcuTalon.Data.Setting).Fresh(..Address()), "<>W")) {
			Set refusal = $Parameter(..#OUT, "MESSAGENOTCONNECTED")
			Quit
		}
		Set parameters = ..Parameters(arguments)
		Set sc = ..DryRun("", parameters, .targets, .dryRun)
		If $$$ISERR(sc) {
			Set sc = $$$OK
			Set refusal = $Parameter(..#OUT, "MESSAGEREFUSED")
			Quit
		}
		Set request = ##class(OcuTalon.Bridge.Data.ApprovalRequest).%New()
		Set request.Kind = "fix"
		Set request.OwnerRef = ownerRef
		Set request.TraceRef = traceRef
		Set request.ResultTarget = ..#RESULTTARGET
		Set request.FixKind = ..#NAME
		Set request.FixParameters = parameters.%ToJSON()
		Set request.FixTargets = targets
		Set request.DryRun = dryRun.%ToJSON()
		Set sc = ##class(OcuTalon.Bridge.Approval).Raise(request, .ref, sinkClass)
		If $$$ISERR(sc) Set ref = ""
	} Catch exception {
		Set ref = ""
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// 1 when the IRIS user may approve the request (DW-1262, until the approver-role check of Story 25.5 covers the kind email). Any row that is not a fix request of the kind email
/// may be answered as before. An email request whose recipients are exactly the own address of the request's owner (OwnAddressOnly) may be answered as before. Any other email
/// request (any other address, a mailbox that now belongs to another session, parameters that cannot be read) may be approved only by a user who holds the role OcuTalonAdmin by its
/// whole name, among the roles the user holds directly or through other roles (never the job's roles). An unknown user, an error and a user with no roles hold nobody. A reject is not asked.
ClassMethod MayApprove(row As OcuTalon.Bridge.Data.ApprovalRequest, irisUser As %String) As %Boolean
{
	If '$IsObject(row) || (row.Kind '= "fix") || (row.FixKind '= ..#NAME) Quit 1
	Set may = 0
	Try {
		Set recipients = {}.%FromJSON(row.FixParameters).recipients
		If ..OwnAddressOnly(row.OwnerRef, recipients) Set may = 1
	} Catch {
		Set may = 0
	}
	If may Quit 1
	If $Get(irisUser) = "" Quit 0
	Try {
		Set sc = $SYSTEM.Security.GetUserRecursedRoleSet(irisUser, .roles)
		Set may = $$$ISOK(sc) && ##class(OcuTalon.Core.Admin).Held(roles)
	} Catch {
		Set may = 0
	}
	Quit may
}

/// Writes the one Action entry of an email send (see the class description). outcome is the CommandResult's outcome word or the run's result, approvalRef is the request's Ref ("" for a
/// tool send), sessionRef the session (or ""), channel a channel of Msg.Enum CHANNEL (system for any other value), recipients the number of recipients and irisUser the IRIS user who
/// answered the request (AD-17; the job's own user when it is empty, as for a tool send). It holds no address, subject or text.
ClassMethod Audit(outcome As %String, approvalRef As %String, sessionRef As %String, channel As %String, recipients As %Integer, irisUser As %String = "") As %Status
{
	Set data = {}
	Do data.%Set("action", ..#NAME, "string")
	Do data.%Set("target", ..#AUDITTARGET, "string")
	Do data.%Set("result", outcome, "string")
	Do data.%Set("counts", {"recipients": (+recipients)})
	Do data.%Set("approvalRef", approvalRef, "string")
	Do data.%Set("irisUser", $Select($Get(irisUser) '= "": irisUser, 1: $Username), "string")
	Do data.%Set("sessionRef", $Select(##class(OcuTalon.Bridge.Approval).IsRef(sessionRef): sessionRef, 1: ""), "string")
	Do data.%Set("channel", $Select($ListFind($ListFromString(##class(OcuTalon.Bridge.Msg.Enum).#CHANNEL), channel): channel, 1: "system"), "string")
	Quit ##class(OcuTalon.Bridge.Audit).Record("Action", data)
}

/// The Audit of an approved email: the entry of the request's row, with the approver's IRIS user and channel (the job's user and system when none) and the number of recipients in its parameters.
ClassMethod AuditRow(row As OcuTalon.Bridge.Data.ApprovalRequest, outcome As %String) As %Status
{
	Set count = 0
	Try {
		Set count = {}.%FromJSON(row.FixParameters).recipients.%Size()
	} Catch {
		Set count = 0
	}
	Quit ..Audit(outcome, row.Ref, row.OwnerRef, row.AnsweredChannel, count, row.AnsweredBy)
}

}
