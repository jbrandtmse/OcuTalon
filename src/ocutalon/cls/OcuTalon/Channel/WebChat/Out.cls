/// WebChatOut, the business operation that delivers a message to the web chat (AD-12, AD-14, AD-32, AD-33). Its message map
/// takes the two messages that Notify routes here, and it acts only when the message's SessionRef is a session (Session.Recipients
/// gives it back); for any other owner it logs a warning and records nothing.
///   - Notification of a card kind (tellnow, reminder): it renders Msg.Catalog.Render(CatalogKey, Slots, "web") and records the
///     web chat's copy of the card on a Delivery row: a new Ref as ChannelMessageId, the kind, the whole rendered text, the
///     DecisionRef, DueAt (the slot dueAt of a reminder) and FallbackReason (the value of the slot that the key's catalog entry
///     declares as type fallbackReason). After the save it publishes one notification event on the session's stream, with
///     Live.Payload.Notification.FromRow of the row: it is the only publisher of that event (AD-33). A render error is returned
///     with no row and no event, and a failed publish is logged and leaves the row. A reload shows the card from the row (DW-62);
///   - Notification of any other kind: only its Delivery row (the kind, the decision and the approval Ref), with no text and no
///     event, until the story that designs that kind's web form;
///   - Outbound (a reply): only its Delivery row for channel web, with the DecisionRef and no ChannelMessageId, because the page
///     shows the turn itself.
Class OcuTalon.Channel.WebChat.Out Extends OcuTalon.Channel.Operation
{

/// The channel of the Delivery rows: one of Msg.Enum CHANNEL.
Parameter CHANNEL = "web";

/// The notification kinds that the web chat shows as cards.
Parameter CARDKINDS = "tellnow,reminder";

/// The channel of the catalog text.
Parameter TEXTCHANNEL = "web";

Parameter LOGNOTASESSION = "WebChatOut dropped a message: its owner is not a session: ";

Parameter LOGPUBLISH = "WebChatOut could not publish a notification: ";

XData MessageMap
{
<MapItems>
<MapItem MessageType="OcuTalon.Msg.Notification">
<Method>OnNotification</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Msg.Outbound">
<Method>OnOutbound</Method>
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
	Set sc = ##class(OcuTalon.Data.Delivery).Record(request.SessionRef, ..#CHANNEL, ##class(OcuTalon.Bridge.Ids).NewRef(), request.ApprovalRef, request.Kind, text, request.DecisionRef, $Select(request.Kind = "reminder": ..SlotOf(request, "dueAt"), 1: ""), ..FallbackReasonOf(request), .row)
	If $$$ISERR(sc) Quit sc
	Do ..Announce(row.OwnerRef, "notification", "OcuTalon.Live.Payload.Notification", row)
	Quit $$$OK
}

/// A reply: only its Delivery row.
Method OnOutbound(request As OcuTalon.Msg.Outbound, Output response As Ens.Response) As %Status
{
	Set response = ""
	If '..IsSession(request.SessionRef) Quit $$$OK
	Quit ##class(OcuTalon.Data.Delivery).Record(request.SessionRef, ..#CHANNEL, "", "", "", "", request.DecisionRef)
}

/// The string slot of the notification, "" when the slots have none.
Method SlotOf(request As OcuTalon.Msg.Notification, name As %String) As %String [ Private ]
{
	Set value = ""
	Try {
		Set slots = ##class(%DynamicAbstractObject).%FromJSON(request.Slots)
		If $IsObject(slots) && (slots.%GetTypeOf(name) = "string") Set value = slots.%Get(name)
	} Catch exception {
		Set value = ""
	}
	Quit value
}

/// The value of the slot that the key's catalog entry declares as type fallbackReason, "" when it declares none.
Method FallbackReasonOf(request As OcuTalon.Msg.Notification) As %String [ Private ]
{
	Set reason = ""
	Try {
		Set entry = ##class(OcuTalon.Msg.Catalog).Entry(request.CatalogKey, .sc)
		If $$$ISOK(sc) && $IsObject(entry) && (entry.%GetTypeOf("slots") = "object") {
			Set iterator = entry.slots.%GetIterator()
			While iterator.%GetNext(.name, .type) {
				If type = "fallbackReason" {
					Set reason = ..SlotOf(request, name)
					Quit
				}
			}
		}
	} Catch exception {
		Set reason = ""
	}
	Quit reason
}

}
