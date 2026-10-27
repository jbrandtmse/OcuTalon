/// SimPhoneOut, the business operation that delivers a message to the simulated phone (AD-14, AD-32, AD-33). Notify routes every
/// notification here while demo mode is on, except kind allowance. Its message map takes OcuTalon.Msg.Notification only, and it
/// acts only when the message's SessionRef is a session (Session.Recipients gives it back); for any other owner it logs a
/// warning and records nothing (AD-4).
///   - A notification of a message kind (tellnow, reminder, incident, approval, result): it renders
///     Msg.Catalog.Render(CatalogKey, Slots, "phone"), the same text as Telegram's, and in one transaction saves the phone
///     message (a SimMessage of Kind phone, direction out, with the text) and its Delivery row (channel phone, the
///     SimMessage's Ref as ChannelMessageId, the kind and the Refs, no text). The message keeps the notification's ApprovalRef
///     only for the kinds incident and approval (AD-32): that Ref is what makes the page draw Approve and Reject, so no
///     other kind ever gives a message one. A result (Story 6.4) is a new message of its own, never an edit of the request's message,
///     with no ApprovalRef and so no buttons; the answered edit below stays the only edit. After the commit it publishes one phone event on the session's stream, with
///     Live.Payload.Phone.FromRow of the message: it is the only publisher of that event (AD-33). A render error is
///     returned with no row and no event, and a failed publish is logged and leaves the rows;
///   - a notification of kind answered edits the delivered message in place (AD-14): Delivery.FindByApproval(ApprovalRef,
///     "phone", SessionRef) gives the message's Ref, and the message must be this session's phone message. Its Answer
///     becomes the rendered text, its Ref and Text stay, and the edit and a Delivery row (kind answered, the message's Ref as
///     ChannelMessageId) are saved in one transaction, followed by one more phone event. The first answer stays: a message
///     that already has an Answer records the Delivery row only (the message's Ref as ChannelMessageId), with no edit and no
///     event. When there is no such message, or the key is empty, only the Delivery row is recorded (ChannelMessageId empty),
///     with no message and no event. A render error on a found message is returned and changes nothing;
///   - a notification of any other kind: only its Delivery row (the kind, the decision and the approval Ref), with no message
///     and no event.
Class OcuTalon.Channel.SimPhone.Out Extends OcuTalon.Channel.Operation
{

/// The channel of the Delivery rows: one of Msg.Enum CHANNEL.
Parameter CHANNEL = "phone";

/// The notification kinds that the phone shows as messages.
Parameter CARDKINDS = "tellnow,reminder,incident,approval,result";

/// The notification kinds whose phone message keeps the ApprovalRef and so gets Approve and Reject (AD-32).
Parameter REQUESTKINDS = "incident,approval";

/// The channel of the catalog text.
Parameter TEXTCHANNEL = "phone";

Parameter LOGNOTASESSION = "SimPhoneOut dropped a message: its owner is not a session: ";

Parameter LOGPUBLISH = "SimPhoneOut could not publish a phone message: ";

XData MessageMap
{
<MapItems>
<MapItem MessageType="OcuTalon.Msg.Notification">
<Method>OnNotification</Method>
</MapItem>
</MapItems>
}

/// A notification: a message kind is rendered, recorded and published; answered edits its message; any other kind is recorded only.
Method OnNotification(request As OcuTalon.Msg.Notification, Output response As Ens.Response) As %Status
{
	Set response = ""
	If '..IsSession(request.SessionRef) Quit $$$OK
	If request.Kind = "answered" Quit ..EditAnswered(request)
	If '$ListFind($ListFromString(..#CARDKINDS), request.Kind) {
		Quit ##class(OcuTalon.Data.Delivery).Record(request.SessionRef, ..#CHANNEL, "", request.ApprovalRef, request.Kind, "", request.DecisionRef)
	}
	Set text = ##class(OcuTalon.Msg.Catalog).Render(request.CatalogKey, request.Slots, ..#TEXTCHANNEL, .sc)
	If $$$ISERR(sc) Quit sc
	Set sc = ..Save(request, text, .row)
	If $$$ISERR(sc) Quit sc
	Do ..Announce(request.SessionRef, "phone", "OcuTalon.Live.Payload.Phone", row)
	Quit $$$OK
}

/// An answered notification: the line replaces the Approve and Reject of the session's message for the request, in place.
Method EditAnswered(request As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Set message = ""
	If request.CatalogKey '= "" {
		Set messageRef = ##class(OcuTalon.Data.Delivery).FindByApproval(request.ApprovalRef, ..#CHANNEL, request.SessionRef)
		If messageRef '= "" Set message = ##class(OcuTalon.Data.SimMessage).RefIndexOpen(messageRef)
	}
	If '$IsObject(message) || (message.SessionRef '= request.SessionRef) || (message.Kind '= "phone") {
		Quit ##class(OcuTalon.Data.Delivery).Record(request.SessionRef, ..#CHANNEL, "", request.ApprovalRef, request.Kind, "", request.DecisionRef)
	}
	If message.Answer '= "" {
		Quit ##class(OcuTalon.Data.Delivery).Record(request.SessionRef, ..#CHANNEL, message.Ref, request.ApprovalRef, request.Kind, "", request.DecisionRef)
	}
	Set text = ##class(OcuTalon.Msg.Catalog).Render(request.CatalogKey, request.Slots, ..#TEXTCHANNEL, .sc)
	If $$$ISERR(sc) Quit sc
	Set message.Answer = text
	Set sc = ..Keep(message, ..#CHANNEL, request.ApprovalRef, request.Kind, request.DecisionRef, .row)
	If $$$ISERR(sc) Quit sc
	Do ..Announce(request.SessionRef, "phone", "OcuTalon.Live.Payload.Phone", row)
	Quit $$$OK
}

/// Saves the phone message and its Delivery row in one transaction (Operation.Keep); row is the saved message. On a failure
/// nothing is kept.
Method Save(request As OcuTalon.Msg.Notification, text As %String, Output row As OcuTalon.Data.SimMessage) As %Status [ Private ]
{
	Set row = ""
	Set message = ##class(OcuTalon.Data.SimMessage).%New()
	Set message.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set message.SessionRef = request.SessionRef
	Set message.Kind = "phone"
	Set message.Direction = "out"
	Set message.Text = text
	If $ListFind($ListFromString(..#REQUESTKINDS), request.Kind) Set message.ApprovalRef = request.ApprovalRef
	Set message.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit ..Keep(message, ..#CHANNEL, request.ApprovalRef, request.Kind, request.DecisionRef, .row)
}

}
