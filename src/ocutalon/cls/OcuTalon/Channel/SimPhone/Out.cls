/// SimPhoneOut, the business operation that delivers a message to the simulated phone (AD-14, AD-32, AD-33). Notify routes every
/// notification here while demo mode is on, except kind allowance. Its message map takes OcuTalon.Msg.Notification only, and it
/// acts only when the message's SessionRef is a session (Session.Recipients gives it back); for any other owner it logs a
/// warning and records nothing (AD-4).
///   - A notification of a card kind (tellnow, reminder): it renders Msg.Catalog.Render(CatalogKey, Slots, "phone"), the same
///     text as Telegram's, and in one transaction saves the phone message (a SimMessage of Kind phone, direction out, with the
///     text) and its Delivery row (channel phone, the SimMessage's Ref as ChannelMessageId, the kind and the Refs, no text).
///     After the commit it publishes one phone event on the session's stream, with Live.Payload.Phone.FromRow of the message:
///     it is the only publisher of that event (AD-33). A render error is returned with no row and no event, and a failed
///     publish is logged and leaves the rows;
///   - a notification of any other kind: only its Delivery row (the kind, the decision and the approval Ref), with no message
///     and no event, until the story that designs that kind's phone form.
Class OcuTalon.Channel.SimPhone.Out Extends OcuTalon.Channel.Operation
{

/// The channel of the Delivery rows: one of Msg.Enum CHANNEL.
Parameter CHANNEL = "phone";

/// The notification kinds that the phone shows as messages.
Parameter CARDKINDS = "tellnow,reminder";

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

/// A notification: a card kind is rendered, recorded and published; any other kind is recorded only.
Method OnNotification(request As OcuTalon.Msg.Notification, Output response As Ens.Response) As %Status
{
	Set response = ""
	If '..IsSession(request.SessionRef) Quit $$$OK
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

/// Saves the phone message and its Delivery row in one transaction; row is the saved message. On a failure nothing is kept.
Method Save(request As OcuTalon.Msg.Notification, text As %String, Output row As OcuTalon.Data.SimMessage) As %Status [ Private ]
{
	Set row = ""
	Set started = 0
	Set sc = $$$OK
	Try {
		TSTART
		Set started = 1
		Set message = ##class(OcuTalon.Data.SimMessage).%New()
		Set message.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set message.SessionRef = request.SessionRef
		Set message.Kind = "phone"
		Set message.Direction = "out"
		Set message.Text = text
		Set message.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
		Set sc = message.%Save()
		If $$$ISOK(sc) Set sc = ##class(OcuTalon.Data.Delivery).Record(request.SessionRef, ..#CHANNEL, message.Ref, request.ApprovalRef, request.Kind, "", request.DecisionRef)
		If $$$ISOK(sc) {
			TCOMMIT
			Set started = 0
			Set row = message
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If started TROLLBACK 1
	Quit sc
}

}
