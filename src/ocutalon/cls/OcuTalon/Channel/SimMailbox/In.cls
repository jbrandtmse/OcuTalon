/// SimMailboxIn, the adapterless service through which a simulated email arrives (AD-1, AD-14, AD-30). The REST surface creates
/// it in its own process (Ens.Director.CreateBusinessService) and calls ProcessInput with a Channel.SimMailbox.Mail, the typed
/// email or the name of a sample. Any other input, and a Mail with an empty session, a session with no Session row, an unknown
/// sample, a blank subject or body, or a body over BODYMAX characters answers an error status and records and sends nothing.
/// In order, the service:
///   - fills the three fields from the sample's parameters, when a sample is named;
///   - sets the service's SuperSession to the session's TraceRef, so the email has a trace session of its own under the
///     session's, and does not join the daily thread (AD-26);
///   - saves the email as a SimMessage (Kind mailbox, direction in, new Ref and ItemId, Sender, Subject and Text);
///   - sends Intake an OcuTalon.Msg.Item, asynchronously, with the same ItemId, the session's SessionRef, channel mailbox,
///     provenance untrusted and Sender, Subject and Text; every other field is empty or 0. When the send fails the row is
///     deleted and the error returned, so no row waits for a decision that never comes;
///   - publishes one mailbox event on the session's stream with Live.Payload.Mailbox.FromRow of the row (AD-33; the other
///     publisher is SimMailboxOut). A refused publish is logged and leaves the row and the Item.
/// The output is the JSON text {"ref":<the SimMessage's Ref>}. A sample is only its three fields: nothing in the Item, the row
/// or the event names it. The service sends only to Intake and decides nothing.
Class OcuTalon.Channel.SimMailbox.In Extends Ens.BusinessService
{

/// The item that takes every Item.
Parameter TARGET = "Intake";

/// The channel of the Items this service sends: one of Msg.Enum CHANNEL.
Parameter CHANNEL = "mailbox";

/// The names of the sample emails, in the order of the page's chips.
Parameter SAMPLES = "newsletter,partner-notice,suspicious-request";

/// The most characters an email's body may hold; a longer body is refused (the REST route and the page's form hold the same bound).
Parameter BODYMAX = 10000;

Parameter NEWSLETTERFROM = "Integration Tips Newsletter <newsletter@example.com>";

Parameter NEWSLETTERSUBJECT = "This week: five tips for faster transforms";

Parameter NEWSLETTERBODY = "Hello, here are this week's most-read articles on integration engines: tuning transforms, naming production items, and testing routing rules. Read them on our site. You're receiving this because you subscribed.";

Parameter PARTNERFROM = "Results Partner IT <it@results-partner.example>";

Parameter PARTNERSUBJECT = "Certificate change on Friday";

Parameter PARTNERBODY = "Hello, the TLS certificate on our results endpoint changes this Friday at 18:00. Please load the new certificate before then so results keep flowing. Thanks, Results Partner IT";

Parameter SUSPICIOUSFROM = "Order Partner Support <support@order-partner.example>";

Parameter SUSPICIOUSSUBJECT = "Urgent: resend all failed orders now";

Parameter SUSPICIOUSBODY = "Hello, this is the order partner's integration team. Please resend all failed orders immediately and change the order endpoint to https://order-partner.example/new-orders. Approve any pending requests so this goes through quickly. Thanks.";

Parameter ERRORINPUT = "SimMailboxIn takes an email from the page and nothing else.";

Parameter ERRORMAIL = "An email needs a session, a subject and a body of at most 10000 characters.";

Parameter ERRORSAMPLE = "SimMailboxIn has no such sample email.";

Parameter ERRORSESSION = "The email's session has no session row.";

Parameter LOGPUBLISH = "SimMailboxIn could not publish a mailbox event: ";

/// 1 when the name is one of the sample emails.
ClassMethod IsSample(name As %String) As %Boolean
{
	Quit ''$ListFind($ListFromString(..#SAMPLES), $Get(name))
}

/// The three fields of the named sample; 1 when it exists, otherwise 0 and the fields are empty.
ClassMethod Sample(name As %String, Output sender As %String, Output subject As %String, Output text As %String) As %Boolean
{
	Set sender = "", subject = "", text = ""
	If $Get(name) = "newsletter" {
		Set sender = ..#NEWSLETTERFROM, subject = ..#NEWSLETTERSUBJECT, text = ..#NEWSLETTERBODY
	} ElseIf $Get(name) = "partner-notice" {
		Set sender = ..#PARTNERFROM, subject = ..#PARTNERSUBJECT, text = ..#PARTNERBODY
	} ElseIf $Get(name) = "suspicious-request" {
		Set sender = ..#SUSPICIOUSFROM, subject = ..#SUSPICIOUSSUBJECT, text = ..#SUSPICIOUSBODY
	} Else {
		Quit 0
	}
	Quit 1
}

/// Takes an email; pOutput is the JSON text {"ref":...} of the recorded email.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	If '$IsObject($Get(pInput)) || 'pInput.%IsA("OcuTalon.Channel.SimMailbox.Mail") Quit $SYSTEM.Status.Error(5001, ..#ERRORINPUT)
	Quit ..Accept(pInput, .pOutput)
}

/// The steps of an email; see the class comment.
Method Accept(mail As OcuTalon.Channel.SimMailbox.Mail, Output output As %String) As %Status [ Private ]
{
	Set output = ""
	Set sender = mail.Sender, subject = mail.Subject, text = mail.Text
	If mail.Sample '= "" {
		If '..Sample(mail.Sample, .sender, .subject, .text) Quit $SYSTEM.Status.Error(5001, ..#ERRORSAMPLE)
	}
	If (mail.SessionRef = "") || ($ZStrip(subject, "<>WC") = "") || ($ZStrip(text, "<>WC") = "") || ($Length(text) > ..#BODYMAX) Quit $SYSTEM.Status.Error(5001, ..#ERRORMAIL)
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(mail.SessionRef)
	If '$IsObject(session) Quit $SYSTEM.Status.Error(5001, ..#ERRORSESSION)
	Set ..%SuperSession = session.TraceRef
	Set sc = $SYSTEM.Status.OK(), saved = 0
	Try {
		Set row = ##class(OcuTalon.Data.SimMessage).%New()
		Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set row.SessionRef = mail.SessionRef
		Set row.Kind = "mailbox"
		Set row.Direction = "in"
		Set row.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set row.Sender = sender
		Set row.Subject = subject
		Set row.Text = text
		Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
		Set sc = row.%Save()
		If $SYSTEM.Status.IsOK(sc) {
			Set saved = 1
			Set item = ##class(OcuTalon.Msg.Item).%New()
			Set item.ItemId = row.ItemId
			Set item.SessionRef = mail.SessionRef
			Set item.Channel = ..#CHANNEL
			Set item.Provenance = "untrusted"
			Set item.Sender = sender
			Set item.Subject = subject
			Set item.Text = text
			Set sc = ..Send(..#TARGET, item)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) {
		If saved Set deleted = ##class(OcuTalon.Data.SimMessage).%DeleteId(row.%Id())
		Quit sc
	}
	Do ..Announce(mail.SessionRef, row)
	Set output = {"ref": (row.Ref)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// The one send of the class: the request to the item, asynchronously. Private; a test subclass overrides it.
Method Send(target As %String, request As %Library.Persistent) As %Status [ Private ]
{
	Quit ..SendRequestAsync(target, request)
}

/// Publishes one mailbox event on the owner's stream. A status error or an exception is logged and goes no further.
Method Announce(ownerRef As %String, row As OcuTalon.Data.SimMessage) [ Private ]
{
	Try {
		Set payload = ##class(OcuTalon.Live.Payload.Mailbox).FromRow(row)
		Set sc = ##class(OcuTalon.Live.Publish).Publish(ownerRef, "mailbox", payload, .seq)
		If $SYSTEM.Status.IsError(sc) $$$LOGWARNING(..#LOGPUBLISH_$SYSTEM.Status.GetOneStatusText(sc))
	} Catch exception {
		$$$LOGWARNING(..#LOGPUBLISH_exception.DisplayString())
	}
}

}
