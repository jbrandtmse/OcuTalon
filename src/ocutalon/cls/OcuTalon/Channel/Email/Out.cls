/// EmailOut, the business operation that sends one email over SMTP (Story 21.6; AD-1, AD-10, AD-14, AD-19, AD-25, AD-33). It takes a
/// OcuTalon.Msg.Command.SendEmail from CommandsIn (origin tool: the session user's own address; origin system: FixExecutor's approved email fix) and
/// answers an OcuTalon.Msg.CommandResult on every path, never an error status. Its adapter, Channel.Email.Sender, connects over TLS only (see
/// there); the item is disabled in the production until SettingsOps saves an outgoing server (the System Default Settings rows of the item), and it
/// stays disabled on the online demo. For each command, in order:
///   - the online demo answers not_available (Ok 0, MESSAGEUNAVAILABLE) before anything else, whatever the rows say;
///   - the product key email.address (read from its row, never the cache) is the From address; with none the answer is not_connected (Ok 0);
///   - the values are checked (Check): 1 to MAXRECIPIENTS recipients, each one address (SettingsOps.IsAddress); a subject of 1 to SUBJECTMAX
///     characters; a text of 1 to TEXTMAX characters; no control character in a recipient or the subject, none in the text but a tab, a line feed
///     or a carriage return. A refusal answers refused (Ok 0, MESSAGEREFUSED) with Data {"fields": [...]} naming recipients, subject or text;
///   - the recipients are enforced here too, whatever CommandsIn did (Authorised): origin tool must name exactly one recipient, equal ignoring case to
///     email.address, and its SessionRef must be the product key email.owner; origin system must name its approval (ApprovalRef): the row of
///     Bridge.Data.ApprovalRequest must be of Kind fix, in State executing, with FixKind FIXKIND, and its FixParameters member recipients (an array
///     of addresses) must equal the command's recipients as a set of lower-cased addresses. Any other origin, a missing row or any mismatch answers
///     refused, naming recipients, and sends nothing;
///   - a system send is claimed first (Claim): under a lock on its ApprovalRef, a Data.Delivery row of channel email with that ApprovalRef means the
///     approval was sent already, so the answer is already_sent (Ok 1, MESSAGESENT) and nothing is sent; a row marked failed (a send that did not go
///     through) or still pending (a send that never finished, such as one whose job was stopped during it) answers failed (Ok 0, MESSAGEFAILED) and sends
///     nothing; otherwise the claim row is written, with FallbackReason pending (CLAIMPENDING), and the send follows. A sent email clears the mark; a
///     failed send, or an error after the claim, keeps the claim with FallbackReason failed, so no approval is ever sent twice and only an email that
///     was sent ever answers already_sent;
///   - the message is one text/plain part in UTF-8 with no attachment, sent once through Deliver. Success records a Data.Delivery row (owner: the
///     command's SessionRef, or instance when it has none; channel email; a new Ref as the message id; the approval's Ref for a system send) and answers sent
///     (Ok 1, MESSAGESENT). A failure answers failed (Ok 0) with the message of Sender.Classify's class: MESSAGEUNREACHABLE, MESSAGEREFUSEDLOGIN or
///     MESSAGEREJECTED, and records nothing for a tool send.
/// The operation logs counts and outcomes only: never an address, a subject, a text, the server's words or a credential.
Class OcuTalon.Channel.Email.Out Extends OcuTalon.Channel.Operation
{

Parameter ADAPTER = "OcuTalon.Channel.Email.Sender";

Property Adapter As OcuTalon.Channel.Email.Sender;

/// The channel of the Delivery rows: one of Msg.Enum CHANNEL.
Parameter CHANNEL = "email";

/// The FixKind of the approval request of an email fix (the contract of Story 22.7's fix kind), and the FixParameters member that lists its recipients.
Parameter FIXKIND = "email";

Parameter FIXRECIPIENTS = "recipients";

/// The Delivery owner of a command with no session.
Parameter INSTANCE = "instance";

/// The product keys of the mailbox: its address and the session that owns it.
Parameter ADDRESSKEY = "email.address";

Parameter OWNERKEY = "email.owner";

/// The limits of the values.
Parameter MAXRECIPIENTS = 20;

Parameter SUBJECTMAX = 200;

Parameter TEXTMAX = 100000;

/// What Claimed answers for the claim row of a send that failed or never finished.
Parameter CLAIMFAILED = 2;

/// The FallbackReason of a claim row while its send has not finished.
Parameter CLAIMPENDING = "pending";

/// How long a system send waits for the lock of its approval, in seconds.
Parameter CLAIMWAIT = 10;

/// The Message of each answer (Public text Q1 to Q4, P1a, P1b and P2).
Parameter MESSAGESENT = "The email was sent.";

Parameter MESSAGEREFUSED = "The email wasn't sent because a recipient, the subject or the text wasn't allowed.";

Parameter MESSAGENOTCONNECTED = "No outgoing mail server is connected, so the email wasn't sent.";

Parameter MESSAGEREJECTED = "The mail server didn't accept the email, so it wasn't sent.";

Parameter MESSAGEUNREACHABLE = "OcuTalon couldn't reach the mail server.";

Parameter MESSAGEREFUSEDLOGIN = "The mail server refused the user name or password.";

Parameter MESSAGEUNAVAILABLE = "Email can't be connected on the online demo. Nothing was changed.";

Parameter MESSAGEFAILED = "Something went wrong inside OcuTalon, so the command may not have finished.";

XData MessageMap
{
<MapItems>
<MapItem MessageType="OcuTalon.Msg.Command.SendEmail">
<Method>OnSendEmail</Method>
</MapItem>
</MapItems>
}

/// Sends one email; see the class description. Always answers OK with a CommandResult.
Method OnSendEmail(request As OcuTalon.Msg.Command.SendEmail, Output response As OcuTalon.Msg.CommandResult) As %Status
{
	Set response = ""
	Try {
		Set response = ..Handle(request)
	} Catch exception {
		$$$LOGERROR("EmailOut failed: "_exception.Name)
		Set response = ..Result(0, "failed", ..#MESSAGEFAILED)
	}
	Quit $$$OK
}

/// The steps of the class description.
Method Handle(request As OcuTalon.Msg.Command.SendEmail) As OcuTalon.Msg.CommandResult [ Private ]
{
	If ##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1 Quit ..Result(0, "not_available", ..#MESSAGEUNAVAILABLE)
	Set from = ##class(OcuTalon.Data.Setting).Fresh(..#ADDRESSKEY)
	If '##class(OcuTalon.Core.SettingsOps).IsAddress(from) Quit ..Result(0, "not_connected", ..#MESSAGENOTCONNECTED)
	Set bad = ..Check(request, .recipients)
	If bad.%Size() Quit ..Refused(bad)
	If '..Authorised(request, from, .recipients) Quit ..Refused(["recipients"])
	Set owner = $Select(request.SessionRef '= "": request.SessionRef, 1: ..#INSTANCE)
	If (request.Origin '= "system") || (request.ApprovalRef = "") Quit ..Send(request, from, .recipients, owner, "")
	Set approval = request.ApprovalRef
	Lock +^OcuTalon.EmailOut.Approval(approval):..#CLAIMWAIT
	If '$Test Quit ..Result(0, "failed", ..#MESSAGEFAILED)
	Set result = ""
	Set claim = ""
	Try {
		Set claimed = ..Claimed(approval)
		If claimed = ..#CLAIMFAILED {
			Set result = ..Result(0, "failed", ..#MESSAGEFAILED)
		} ElseIf claimed {
			Set result = ..Result(1, "already_sent", ..#MESSAGESENT)
		} Else {
			Set sc = ##class(OcuTalon.Data.Delivery).Record(owner, ..#CHANNEL, ##class(OcuTalon.Bridge.Ids).NewRef(), approval, "", "", "", "", ..#CLAIMPENDING, .claim)
			Set result = $Select($$$ISERR(sc): ..Result(0, "failed", ..#MESSAGEFAILED), 1: ..Send(request, from, .recipients, owner, claim))
		}
	} Catch exception {
		$$$LOGERROR("EmailOut failed: "_exception.Name)
		Set result = ..Result(0, "failed", ..#MESSAGEFAILED)
		If $IsObject(claim) {
			Set claim.FallbackReason = "failed"
			Do claim.%Save()
		}
	}
	Lock -^OcuTalon.EmailOut.Approval(approval)
	Quit result
}

/// Builds the message, delivers it once and answers; claim is the claim row of a system send, "" for a tool send.
Method Send(request As OcuTalon.Msg.Command.SendEmail, from As %String, ByRef recipients, owner As %String, claim As OcuTalon.Data.Delivery) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set message = ##class(%Net.MailMessage).%New("UTF-8")
	Set message.From = from
	Set message.Subject = request.Subject
	For i = 1:1:recipients Do message.To.Insert(recipients(i))
	Do message.TextData.Write(request.Text)
	Set sc = ..Deliver(message)
	If $$$ISOK(sc) {
		If '$IsObject(claim) {
			Set recorded = ##class(OcuTalon.Data.Delivery).Record(owner, ..#CHANNEL, ##class(OcuTalon.Bridge.Ids).NewRef(), "")
			If $$$ISERR(recorded) $$$LOGERROR("EmailOut sent an email but could not record its delivery")
		} Else {
			Set claim.FallbackReason = ""
			If $$$ISERR(claim.%Save()) $$$LOGERROR("EmailOut sent an email but could not mark its claim sent")
		}
		$$$LOGINFO("EmailOut sent one email to "_recipients_" recipient(s)")
		Quit ..Result(1, "sent", ..#MESSAGESENT)
	}
	Set class = ##class(OcuTalon.Channel.Email.Sender).Classify(sc)
	Set errorMessage = $Select(class = ##class(OcuTalon.Channel.Email.Sender).#REFUSED: ..#MESSAGEREFUSEDLOGIN, class = ##class(OcuTalon.Channel.Email.Sender).#REJECTED: ..#MESSAGEREJECTED, 1: ..#MESSAGEUNREACHABLE)
	If $IsObject(claim) {
		Set claim.FallbackReason = "failed"
		Set saved = claim.%Save()
		If $$$ISERR(saved) $$$LOGERROR("EmailOut could not mark the claim of a failed send")
	}
	$$$LOGWARNING("EmailOut did not send the email: "_class)
	Quit ..Result(0, "failed", errorMessage)
}

/// The one send of the class: the message through the adapter, once. A test subclass overrides it to stand in for the adapter.
Method Deliver(message As %Net.MailMessage) As %Status [ Private ]
{
	Quit ..Adapter.SendMail(message)
}

/// Checks the values of the command. recipients is the number of recipients, and recipients(n) each one trimmed; the answer names the refused
/// fields (recipients, subject, text) in a dynamic array.
Method Check(request As OcuTalon.Msg.Command.SendEmail, Output recipients) As %DynamicArray [ Private ]
{
	Kill recipients
	Set recipients = 0
	Set bad = []
	Set raw = request.Recipients
	Set ok = (raw '= "") && '..HasControl(raw)
	If ok {
		Set count = $Length(raw, ",")
		If count > ..#MAXRECIPIENTS Set ok = 0
		For i = 1:1:count {
			Set one = $ZStrip($Piece(raw, ",", i), "<>W")
			If 'ok || '##class(OcuTalon.Core.SettingsOps).IsAddress(one) {
				Set ok = 0
				Quit
			}
			Set recipients(i) = one, recipients = i
		}
	}
	If 'ok {
		Kill recipients
		Set recipients = 0
		Do bad.%Push("recipients")
	}
	Set subject = request.Subject
	If ($ZStrip(subject, "<>W") = "") || ($Length(subject) > ..#SUBJECTMAX) || ..HasControl(subject) Do bad.%Push("subject")
	Set text = request.Text
	If ($ZStrip(text, "<>WC") = "") || ($Length(text) > ..#TEXTMAX) || ..HasControl($Translate(text, $Char(9, 10, 13))) Do bad.%Push("text")
	Quit bad
}

/// 1 when the text holds a control character.
ClassMethod HasControl(text As %String) As %Boolean [ Private ]
{
	Quit ($ZStrip(text, "*C") '= text)
}

/// 1 when the recipients may be sent to by this command's origin (see the class description).
Method Authorised(request As OcuTalon.Msg.Command.SendEmail, from As %String, ByRef recipients) As %Boolean [ Private ]
{
	If request.Origin = "tool" {
		Quit (recipients = 1) && ($ZConvert(recipients(1), "L") = $ZConvert($ZStrip(from, "<>W"), "L")) && (request.SessionRef '= "") && (request.SessionRef = ##class(OcuTalon.Data.Setting).Fresh(..#OWNERKEY))
	}
	If request.Origin '= "system" Quit 0
	If request.ApprovalRef = "" Quit 0
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request.ApprovalRef)
	If '$IsObject(row) || $$$ISERR(row.%Reload()) Quit 0
	If (row.Kind '= "fix") || (row.State '= "executing") || (row.FixKind '= ..#FIXKIND) Quit 0
	Kill allowed, asked
	Try {
		Set parameters = {}.%FromJSON(row.FixParameters)
		Set list = parameters.%Get(..#FIXRECIPIENTS)
		If '$IsObject(list) || (list.%Size() = 0) Quit
		Set iterator = list.%GetIterator()
		While iterator.%GetNext(, .address) {
			Set allowed($ZConvert($ZStrip(address, "<>W"), "L")) = ""
		}
	} Catch {
		Kill allowed
	}
	If '$Data(allowed) Quit 0
	For i = 1:1:recipients Set asked($ZConvert(recipients(i), "L")) = ""
	Set key = ""
	For {
		Set key = $Order(asked(key))
		Quit:key=""
		If '$Data(allowed(key)) Quit
	}
	If key '= "" Quit 0
	For {
		Set key = $Order(allowed(key))
		Quit:key=""
		If '$Data(asked(key)) Quit
	}
	Quit (key = "")
}

/// What a Delivery row of channel email says about the approval: 0 when there is none, CLAIMFAILED when the row is the claim of a send that failed or
/// never finished (FallbackReason failed or CLAIMPENDING), and 1 for a row of an email that was sent.
ClassMethod Claimed(approval As %String) As %Integer [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT TOP 1 FallbackReason FROM OcuTalon_Data.Delivery WHERE ApprovalRef = ? AND Channel = ?")
	If $$$ISERR(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Set rows = statement.%Execute(approval, ..#CHANNEL)
	If rows.%SQLCODE < 0 Throw ##class(%Exception.SQL).CreateFromSQLCODE(rows.%SQLCODE, rows.%Message)
	If 'rows.%Next() Quit 0
	Quit $Select(rows.%Get("FallbackReason") = "": 1, 1: ..#CLAIMFAILED)
}

/// A refused answer naming the fields.
ClassMethod Refused(fields As %DynamicArray) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set result = ..Result(0, "refused", ..#MESSAGEREFUSED)
	Set result.Data = {"fields": (fields)}.%ToJSON()
	Quit result
}

/// A CommandResult.
ClassMethod Result(ok As %Boolean, outcome As %String, message As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = ok
	Set result.Outcome = outcome
	Set result.Message = message
	Quit result
}

}
