/// EmailOut, the business operation that sends one email over SMTP (Story 21.6, 21.7; AD-1, AD-10, AD-14, AD-19, AD-25, AD-32, AD-33). It has three paths,
/// all of them enumerated here, each with its own rule for the recipient. Its adapter, Channel.Email.Sender, connects over TLS only (see there); the
/// item is disabled in the production until SettingsOps saves an outgoing server (the System Default Settings rows of the item), and it stays
/// disabled on the online demo. Every email it sends carries the header X-OcuTalon-Ref, a random Ref (OcuTalon.Bridge.Ids.NewRef: 128 random bits, no
/// sequence, session or address in it) that is made before the send and is the ChannelMessageId of the email's Data.Delivery row, so that EmailIn can
/// tell the mail that comes back to the polled mailbox (see there).
/// The tool and system paths take an OcuTalon.Msg.Command.SendEmail from CommandsIn (origin tool: the session user's own address; origin system:
/// FixExecutor's approved email fix) and answer an OcuTalon.Msg.CommandResult on every path, never an error status. For each command, in order:
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
///   - a system send is claimed first (SendClaimed): under a lock on its ApprovalRef, a Data.Delivery row of channel email with that ApprovalRef means the
///     approval was sent already, so the answer is already_sent (Ok 1, MESSAGESENT) and nothing is sent; a row marked failed (a send that did not go
///     through) or still pending (a send that never finished, such as one whose job was stopped during it) answers failed (Ok 0, MESSAGEFAILED) and sends
///     nothing; otherwise the claim row is written, with FallbackReason pending (CLAIMPENDING), and the send follows. A sent email clears the mark; a
///     failed send, or an error after the claim, keeps the claim with FallbackReason failed, so no approval is ever sent twice and only an email that
///     was sent ever answers already_sent;
///   - a tool send with an IdempotencyKey is claimed the same way (SendClaimed), by its session and the key, and only the key decides: the subject, the
///     text and the recipients of a repeat are not compared. The claim row has the owner of the command's SessionRef, an empty ApprovalRef (even when the
///     command names an approval) and, in DigestKey, ToolKeyOf: 22 characters of the hash of the key, never equal to a digest's key. Under a lock on the
///     owner and the key, a sent row for the key answers sent (Ok 1, MESSAGESENT), as the first send did, and sends nothing; a row that is pending or
///     marked failed, or a lock that cannot be taken in CLAIMWAIT, answers failed (Ok 0, MESSAGEFAILED) and sends nothing; otherwise the claim is written
///     pending and the send follows. A sent email clears the mark. A failed send that the server did not take (one of Sender.Classify's classes) deletes
///     the claim, so that the key can be sent again and leaves no row; a failed send that may still have reached the server (Sender.MayHaveSent: a timeout
///     or a connection lost during DATA) and an error after the claim mark it failed, so that the key never sends twice. A tool send with no key is
///     sent every time;
///   - the message is one text/plain part in UTF-8 with no attachment, sent once through Deliver. Success records a Data.Delivery row (owner: the
///     command's SessionRef, or instance when it has none; channel email; the Ref of the header as the message id; the approval's Ref for a system send) and
///     answers sent (Ok 1, MESSAGESENT). A failure answers failed (Ok 0) with the message of Sender.Classify's class: MESSAGEUNREACHABLE,
///     MESSAGEREFUSEDLOGIN or MESSAGEREJECTED, and records nothing for a tool send. With a provider sign-in (the adapter's OAuth2ApplicationName is set,
///     Story 21.8) the refused class means that the sign-in cannot be used, so its message is MESSAGESIGNIN instead of MESSAGEREFUSEDLOGIN; a failed send
///     of the digest path is logged by its class, as a refused one, and nothing is recorded.
/// The third path is the daily digest (OnNotification): an OcuTalon.Msg.Notification of Kind digest that Notify routes here (rule DigestEmail). It
/// answers nothing and always returns OK. Nothing in the Notification chooses the recipient: the email goes to the product key email.address, read from
/// its row, and only when the Notification's SessionRef is the product key email.owner. In order:
///   - the online demo, a Kind other than digest (one warning), no address, or a session that does not own the mailbox: nothing is sent;
///   - the subject is the catalog text of email.digestSubject and the text is OcuTalon.Channel.DigestText.Text(Slots, "email"), both rendered here
///     (AD-32); a piece that does not render, or a subject or text beyond the limits of Check, sends nothing (one warning);
///   - under the one lock of the mailbox's digest emails, a digest with the same key (DigestKeyOf: session, decision, key, slots and the UTC day) that has
///     its Data.Delivery row is not sent again, and at most MAXDIGESTS digests go to the mailbox in one UTC day, whichever session owned it when each went
///     (the instance has one mailbox): the next one is refused and one warning is logged, with no contents; a count that cannot be read refuses as well;
///   - the message is sent once through Deliver, and success records a Data.Delivery row (owner the session, channel email, Kind digest, the Ref of the
///     header as the message id, the digest's DecisionRef and DigestKey; no text, no address). A failed send records nothing and is not tried again.
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

/// The most digests that go to the mailbox in one UTC day, whichever session owns it.
Parameter MAXDIGESTS = 10;

/// The catalog key of the subject of a digest email, and the channel of the catalog texts of a digest email.
Parameter DIGESTSUBJECT = "email.digestSubject";

Parameter TEXTCHANNEL = "email";

/// The header that every email carries, with the Ref of its Data.Delivery row.
Parameter REFHEADER = "X-OcuTalon-Ref";

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

/// The Message of a send that fails on the sign-in in OAuth2 mode (Public text T2).
Parameter MESSAGESIGNIN = "The mail sign-in is no longer valid, so the email wasn't sent. Sign in again in Settings > Channels > Email.";

Parameter MESSAGEUNAVAILABLE = "Email can't be connected on the online demo. Nothing was changed.";

Parameter MESSAGEFAILED = "Something went wrong inside OcuTalon, so the command may not have finished.";

XData MessageMap
{
<MapItems>
<MapItem MessageType="OcuTalon.Msg.Command.SendEmail">
<Method>OnSendEmail</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Msg.Notification">
<Method>OnNotification</Method>
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
	If (request.Origin = "system") && (request.ApprovalRef '= "") Quit ..SendClaimed(request, from, .recipients, owner, request.ApprovalRef, "")
	If (request.Origin = "tool") && (request.IdempotencyKey '= "") Quit ..SendClaimed(request, from, .recipients, owner, "", ..ToolKeyOf(request))
	Quit ..Send(request, from, .recipients, owner, "")
}

/// The claimed send of the class description, for a system send (approval is its ApprovalRef, key "") and for a keyed tool send (approval "", key is
/// ToolKeyOf). Under a lock on the approval or on the owner and key, a Data.Delivery row of channel email for it is looked up (Claimed); then the answer
/// is that of the class description, or the claim row is written pending and the send follows. A claim row never carries an ApprovalRef for a tool send.
Method SendClaimed(request As OcuTalon.Msg.Command.SendEmail, from As %String, ByRef recipients, owner As %String, approval As %String, key As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set lockName = $Select(approval '= "": $Name(^OcuTalon.EmailOut.Approval(approval)), 1: $Name(^OcuTalon.EmailOut.Key(owner, key)))
	Lock +@lockName:..#CLAIMWAIT
	If '$Test Quit ..Result(0, "failed", ..#MESSAGEFAILED)
	Set result = ""
	Set claim = ""
	Try {
		Set claimed = ..Claimed(approval, owner, key)
		If claimed = ..#CLAIMFAILED {
			Set result = ..Result(0, "failed", ..#MESSAGEFAILED)
		} ElseIf claimed {
			Set result = $Select(approval '= "": ..Result(1, "already_sent", ..#MESSAGESENT), 1: ..Result(1, "sent", ..#MESSAGESENT))
		} Else {
			Set sc = ##class(OcuTalon.Data.Delivery).Record(owner, ..#CHANNEL, ##class(OcuTalon.Bridge.Ids).NewRef(), approval, "", "", "", "", ..#CLAIMPENDING, .claim, "", key)
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
	Lock -@lockName
	Quit result
}

/// Builds the message, delivers it once and answers; claim is the claim row of a claimed send, "" for an unclaimed tool send. The Ref of the header is the claim
/// row's, or a new one that the Delivery row of a sent unclaimed tool email keeps. A failed send keeps the claim of an approval, marked failed. It deletes
/// the claim of a keyed tool send (it has no ApprovalRef), so that the same key can be sent again, unless the email may still have reached the server
/// (Sender.MayHaveSent); that claim is kept, marked failed.
Method Send(request As OcuTalon.Msg.Command.SendEmail, from As %String, ByRef recipients, owner As %String, claim As OcuTalon.Data.Delivery) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set ref = $Select($IsObject(claim): claim.ChannelMessageId, 1: ##class(OcuTalon.Bridge.Ids).NewRef())
	Set sc = ..Transmit(from, .recipients, request.Subject, request.Text, ref)
	If $$$ISOK(sc) {
		If '$IsObject(claim) {
			Set recorded = ##class(OcuTalon.Data.Delivery).Record(owner, ..#CHANNEL, ref, "")
			If $$$ISERR(recorded) $$$LOGERROR("EmailOut sent an email but could not record its delivery")
		} Else {
			Set claim.FallbackReason = ""
			If $$$ISERR(claim.%Save()) $$$LOGERROR("EmailOut sent an email but could not mark its claim sent")
		}
		$$$LOGINFO("EmailOut sent one email to "_recipients_" recipient(s)")
		Quit ..Result(1, "sent", ..#MESSAGESENT)
	}
	Set class = ##class(OcuTalon.Channel.Email.Sender).Classify(sc)
	Set errorMessage = $Select(class = ##class(OcuTalon.Channel.Email.Sender).#REFUSED: $Select(..OAuth2Mode(): ..#MESSAGESIGNIN, 1: ..#MESSAGEREFUSEDLOGIN), class = ##class(OcuTalon.Channel.Email.Sender).#REJECTED: ..#MESSAGEREJECTED, 1: ..#MESSAGEUNREACHABLE)
	If $IsObject(claim) {
		If (claim.ApprovalRef = "") && '##class(OcuTalon.Channel.Email.Sender).MayHaveSent(sc) {
			Set deleted = ##class(OcuTalon.Data.Delivery).%DeleteId(claim.%Id())
			If $$$ISERR(deleted) $$$LOGERROR("EmailOut could not remove the claim of a failed send")
		} Else {
			Set claim.FallbackReason = "failed"
			Set saved = claim.%Save()
			If $$$ISERR(saved) $$$LOGERROR("EmailOut could not mark the claim of a failed send")
		}
	}
	$$$LOGWARNING("EmailOut did not send the email: "_class)
	Quit ..Result(0, "failed", errorMessage)
}

/// 1 when the adapter signs in with OAuth2 (its OAuth2ApplicationName is set). A test subclass overrides it to stand in for the adapter.
Method OAuth2Mode() As %Boolean [ Private ]
{
	Quit $IsObject(..Adapter) && (..Adapter.OAuth2ApplicationName '= "")
}

/// The one message of every path: from, the recipients (recipients(1..n)), the subject and the text as one text/plain UTF-8 part, with the header
/// X-OcuTalon-Ref set to ref, delivered once. The status is Deliver's.
Method Transmit(from As %String, ByRef recipients, subject As %String, text As %String, ref As %String) As %Status [ Private ]
{
	Set message = ##class(%Net.MailMessage).%New("UTF-8")
	Set message.From = from
	Set message.Subject = subject
	For i = 1:1:recipients Do message.To.Insert(recipients(i))
	Do message.Headers.SetAt(ref, ..#REFHEADER)
	Do message.TextData.Write(text)
	Quit ..Deliver(message)
}

/// A Notification of Kind digest: the digest email of the class description. Always OK, and no response.
Method OnNotification(request As OcuTalon.Msg.Notification, Output response As Ens.Response) As %Status
{
	Set response = ""
	Try {
		Do ..SendDigest(request)
	} Catch exception {
		$$$LOGERROR("EmailOut failed: "_exception.Name)
	}
	Quit $$$OK
}

/// The steps of the digest path (see the class description).
Method SendDigest(request As OcuTalon.Msg.Notification) [ Private ]
{
	If ##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1 Quit
	If request.Kind '= "digest" {
		$$$LOGWARNING("EmailOut takes a notification of kind digest only, so it sent nothing")
		Quit
	}
	Set from = ##class(OcuTalon.Data.Setting).Fresh(..#ADDRESSKEY)
	Set owner = request.SessionRef
	If (owner = "") || (owner '= ##class(OcuTalon.Data.Setting).Fresh(..#OWNERKEY)) || '##class(OcuTalon.Core.SettingsOps).IsAddress(from) Quit
	Set subject = ##class(OcuTalon.Msg.Catalog).Render(..#DIGESTSUBJECT, "", ..#TEXTCHANNEL, .sc)
	If $$$ISOK(sc) Set text = ##class(OcuTalon.Channel.DigestText).Text(request.Slots, ..#TEXTCHANNEL, .sc)
	If $$$ISERR(sc) {
		$$$LOGWARNING("EmailOut could not render the digest, so it sent nothing")
		Quit
	}
	Set bad = []
	Do ..CheckValues(subject, text, bad)
	If bad.%Size() {
		$$$LOGWARNING("EmailOut refused a digest whose subject or text is not allowed, so it sent nothing")
		Quit
	}
	Set key = ..DigestKeyOf(request)
	Lock +^OcuTalon.EmailOut.Digest:..#CLAIMWAIT
	If '$Test {
		$$$LOGWARNING("EmailOut could not take the lock of the digest emails, so it sent nothing")
		Quit
	}
	Try {
		Do ..SendDigestLocked(request, from, owner, subject, text, key)
	} Catch exception {
		$$$LOGERROR("EmailOut failed: "_exception.Name)
	}
	Lock -^OcuTalon.EmailOut.Digest
}

/// The send of a digest under the lock of the mailbox's digest emails: the digest sends once, at most MAXDIGESTS go to the mailbox in one UTC day, and the
/// Delivery row follows the send.
Method SendDigestLocked(request As OcuTalon.Msg.Notification, from As %String, owner As %String, subject As %String, text As %String, key As %String) [ Private ]
{
	If ##class(OcuTalon.Data.Delivery).DigestEmailSent(owner, key) Quit
	Set today = $Extract(##class(OcuTalon.Data.Time).NowUtc(), 1, 10)_"T00:00:00Z"
	Set sent = ##class(OcuTalon.Data.Delivery).DigestEmailsSince(today)
	If sent < 0 {
		$$$LOGWARNING("EmailOut could not count the digest emails of the day, so it sent nothing")
		Quit
	}
	If sent '< ..#MAXDIGESTS {
		$$$LOGWARNING("EmailOut refused a digest email: the limit of "_..#MAXDIGESTS_" digest emails a day was reached, so it sent nothing")
		Quit
	}
	Set recipients = 1, recipients(1) = from
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = ..Transmit(from, .recipients, subject, text, ref)
	If $$$ISERR(sc) {
		$$$LOGWARNING("EmailOut did not send the digest email: "_##class(OcuTalon.Channel.Email.Sender).Classify(sc))
		Quit
	}
	Set recorded = ##class(OcuTalon.Data.Delivery).Record(owner, ..#CHANNEL, ref, "", "digest", "", request.DecisionRef, "", "", , "", key)
	If $$$ISERR(recorded) $$$LOGERROR("EmailOut sent a digest email but could not record its delivery")
	$$$LOGINFO("EmailOut sent one digest email")
}

/// The key of a digest: 22 characters of the SHA-256 hash of the Notification's session, decision, key and slots and the UTC day, so that the
/// same Notification handled twice is one digest. It holds no address and no text.
ClassMethod DigestKeyOf(request As OcuTalon.Msg.Notification) As %String
{
	Set lf = $Char(10)
	Quit ..HashOf(request.SessionRef_lf_request.DecisionRef_lf_request.CatalogKey_lf_request.Slots_lf_$Extract(##class(OcuTalon.Data.Time).NowUtc(), 1, 10))
}

/// The key of a tool send: 22 characters of the SHA-256 hash of the word tool, a line feed and the command's IdempotencyKey, so that it never equals the key
/// of a digest. It holds no address and no text; the session is the owner of the claim row, not part of the hash.
ClassMethod ToolKeyOf(request As OcuTalon.Msg.Command.SendEmail) As %String
{
	Quit ..HashOf("tool"_$Char(10)_request.IdempotencyKey)
}

/// 22 characters of the SHA-256 hash of the input (UTF-8), in URL-safe Base64.
ClassMethod HashOf(input As %String) As %String [ Private ]
{
	Quit $Translate($SYSTEM.Encryption.Base64Encode($Extract($SYSTEM.Encryption.SHAHash(256, $ZConvert(input, "O", "UTF8")), 1, 16), 1), "+/=", "-_")
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
	Do ..CheckValues(request.Subject, request.Text, bad)
	Quit bad
}

/// Pushes "subject" and "text" onto bad for a subject or a text that is not allowed (the limits of the class description).
ClassMethod CheckValues(subject As %String, text As %String, bad As %DynamicArray) [ Private ]
{
	If ($ZStrip(subject, "<>W") = "") || ($Length(subject) > ..#SUBJECTMAX) || ..HasControl(subject) Do bad.%Push("subject")
	If ($ZStrip(text, "<>WC") = "") || ($Length(text) > ..#TEXTMAX) || ..HasControl($Translate(text, $Char(9, 10, 13))) Do bad.%Push("text")
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

/// What a Delivery row of channel email says about a claim: for an approval (approval is not empty) the row with that ApprovalRef, for a keyed tool send
/// (approval empty) the row of the owner whose DigestKey is exactly key (the column compares without regard to case, so the value read is compared
/// again). 0 when there is none, CLAIMFAILED when the row is the claim of a send that failed or never finished (FallbackReason failed or CLAIMPENDING),
/// and 1 for a row of an email that was sent.
ClassMethod Claimed(approval As %String, owner As %String = "", key As %String = "") As %Integer [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	If approval '= "" {
		Set sc = statement.%Prepare("SELECT TOP 1 FallbackReason, DigestKey FROM OcuTalon_Data.Delivery WHERE ApprovalRef = ? AND Channel = ?")
	} Else {
		Set sc = statement.%Prepare("SELECT FallbackReason, DigestKey FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND Channel = ? AND DigestKey = ?")
	}
	If $$$ISERR(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Set rows = $Select(approval '= "": statement.%Execute(approval, ..#CHANNEL), 1: statement.%Execute(owner, ..#CHANNEL, key))
	If rows.%SQLCODE < 0 Throw ##class(%Exception.SQL).CreateFromSQLCODE(rows.%SQLCODE, rows.%Message)
	Set found = 0
	While 'found && rows.%Next() {
		If (approval '= "") || (rows.%Get("DigestKey") = key) Set found = $Select(rows.%Get("FallbackReason") = "": 1, 1: ..#CLAIMFAILED)
	}
	Quit found
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
