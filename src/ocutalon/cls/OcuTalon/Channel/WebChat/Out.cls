/// WebChatOut, the business operation that delivers a message to the web chat (AD-12, AD-14, AD-32, AD-33). Its message map
/// takes the two messages that Notify routes here, and it acts only when the message's SessionRef is a session (Session.Recipients
/// gives it back); for any other owner it logs a warning and records nothing.
///   - Notification of a card kind (tellnow, reminder, allowance): it renders Msg.Catalog.Render(CatalogKey, Slots, "web") and records the
///     web chat's copy of the card on a Delivery row: a new Ref as ChannelMessageId, the kind, the whole rendered text, the
///     DecisionRef, DueAt (the slot dueAt of a reminder) and FallbackReason (the value of the slot that the key's catalog entry
///     declares as type fallbackReason). After the save it publishes one notification event on the session's stream, with
///     Live.Payload.Notification.FromRow of the row: it is the only publisher of that event (AD-33). A render error is returned
///     with no row and no event, and a failed publish is logged and leaves the row. A reload shows the card from the row (DW-62).
///     An allowance card (Story 16.9) is the session's message allowance or the online demo's daily-cap message; its text is the
///     catalog's, rendered for the web with the time in instance time and "ET", and its row keeps no FallbackReason;
///   - Notification of the kind digest (Story 17.10): it takes the same card path, with the text of OcuTalon.Channel.DigestText.Text(Slots,
///     "web", .sc) in place of the rendering of the CatalogKey: the shared digest.* and checks.* texts, one piece per line, with no title. The
///     row's DueAt and FallbackReason are "" and its DecisionRef is the one sent. The row also keeps the Slots' rows (the check rows, as JSON; "[]" when
///     there are none) as CheckRows, and the event's payload carries them as checks, so a reload shows the same card (Story 18.4). A Slots or a
///     piece that cannot be rendered is an error with no row and no event;
///   - Notification of the kind summary (Story 23.6; AD-32): it takes the same card path, with the text of OcuTalon.Watch.Summary.Text(IncidentRef, "web", .sc), the
///     incident's stored summary rendered one catalog line per part, in place of the rendering of the CatalogKey (its Slots are empty, so no untrusted text and no
///     user name travels in the message). The row's DueAt and FallbackReason are "" and its DecisionRef is the one sent. A summary that cannot be read or rendered
///     is an error with no row and no event;
///   - Notification of the kind handled (Story 18.4; Core.SessionOps sends it once, when the user marks a tell-now notice as handled):
///     Ownership.DeliveryByRef(DecisionRef, "web", SessionRef) gives the notice's newest web row. When that row is a tell-now card with a
///     ChannelMessageId, it publishes one more notification event with Live.Payload.Notification.FromRow of THAT row, so the card keeps
///     its Ref and now carries handledAt, and then records the Delivery row of kind handled (no text, no ChannelMessageId). A row of kind
///     handled (a second press), or no card, records the Delivery row only, with no event;
///   - Notification of a tool-call card (Story 31.6; ToolCallCard: kind approval or result, an ApprovalRef, and a CatalogKey that is
///     one of Core.BridgeSink's five tool-call keys): it takes the same card path, so the chat shows the request with Approve and
///     Reject, the result and DW-454's held-call reason from the one Notification that the bridge sink built (DW-601). The persona
///     notices of Core.SettingsOps (Story 40.6) take the same path: its KEYPROPOSED (kind approval), KEYAPPLIED and KEYSTALE (kind
///     result), read by $Parameter, with an ApprovalRef; the kind answered stays a Delivery row only. The one result without an ApprovalRef that takes this path is
///     Watch.Notice KEYPARTNERNOTDRAFTED (Story 23.5), the notice that a delay notice could not be drafted: it has no request or incident card to be drawn in, so the chat
///     shows it as a card of its own;
///   - Notification of any other incident kind (INCIDENTKINDS: incident, approval, answered, result): only its Delivery row (the kind,
///     the decision and the approval Ref), with no text and no event, because the web form of these kinds is the incident card,
///     which the page draws from the incident event (Story 6.1). A fix's notices and the kind answered stay here;
///   - Notification of any other kind (fallback, pairing, status): only its Delivery row, with no text and no event, until the story that designs that kind's
///     web form;
///   - Outbound (a reply): only its Delivery row for channel web, with the DecisionRef and no ChannelMessageId, because the page
///     shows the turn itself.
Class OcuTalon.Channel.WebChat.Out Extends OcuTalon.Channel.Operation
{

/// The channel of the Delivery rows: one of Msg.Enum CHANNEL.
Parameter CHANNEL = "web";

/// The notification kinds that the web chat shows as cards.
Parameter CARDKINDS = "tellnow,reminder,allowance,digest,summary";

/// The notification kinds whose web form is the incident card: they record their Delivery row only and never a card or an event.
Parameter INCIDENTKINDS = "incident,approval,answered,result";

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

/// A notification: a card kind (a digest included) or a tool-call card is rendered, recorded and published; an incident kind or any other kind is
/// recorded only.
Method OnNotification(request As OcuTalon.Msg.Notification, Output response As Ens.Response) As %Status
{
	Set response = ""
	If '..IsSession(request.SessionRef) Quit $$$OK
	If request.Kind = "handled" Quit ..OnHandled(request)
	If '$ListFind($ListFromString(..#CARDKINDS), request.Kind) && '..ToolCallCard(request) {
		Quit ##class(OcuTalon.Data.Delivery).Record(request.SessionRef, ..#CHANNEL, "", request.ApprovalRef, request.Kind, "", request.DecisionRef)
	}
	If request.Kind = "digest" {
		Set text = ##class(OcuTalon.Channel.DigestText).Text(request.Slots, ..#TEXTCHANNEL, .sc)
	} ElseIf request.Kind = "summary" {
		Set text = ##class(OcuTalon.Watch.Summary).Text(request.IncidentRef, ..#TEXTCHANNEL, .sc)
	} Else {
		Set text = ##class(OcuTalon.Msg.Catalog).Render(request.CatalogKey, request.Slots, ..#TEXTCHANNEL, .sc)
	}
	If $$$ISERR(sc) Quit sc
	Set sc = ##class(OcuTalon.Data.Delivery).Record(request.SessionRef, ..#CHANNEL, ##class(OcuTalon.Bridge.Ids).NewRef(), request.ApprovalRef, request.Kind, text, request.DecisionRef, $Select(request.Kind = "reminder": ..SlotOf(request, "dueAt"), 1: ""), ..FallbackReasonOf(request), .row, $Select(request.Kind = "digest": ..RowsOf(request), 1: ""))
	If $$$ISERR(sc) Quit sc
	Do ..Announce(row.OwnerRef, "notification", "OcuTalon.Live.Payload.Notification", row)
	Quit $$$OK
}

/// A handled notification: the notice's card is published again with its handled marker, then the bare Delivery row is recorded (see the class comment).
Method OnHandled(request As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Set card = ##class(OcuTalon.Data.Ownership).DeliveryByRef(request.DecisionRef, ..#CHANNEL, request.SessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	If $IsObject(card) && (card.Kind = "tellnow") && (card.ChannelMessageId '= "") {
		Do ..Announce(card.OwnerRef, "notification", "OcuTalon.Live.Payload.Notification", card)
	}
	Quit ##class(OcuTalon.Data.Delivery).Record(request.SessionRef, ..#CHANNEL, "", request.ApprovalRef, request.Kind, "", request.DecisionRef)
}

/// 1 when the notification is a tool-call card or a persona card: kind approval or result, an ApprovalRef, and one of the bridge sink's
/// five tool-call catalog keys or SettingsOps' three persona keys (read from their parameters, never copied); also a result with the catalog key
/// Watch.Notice KEYPARTNERNOTDRAFTED, which has no ApprovalRef.
Method ToolCallCard(request As OcuTalon.Msg.Notification) As %Boolean [ Private ]
{
	If (request.Kind '= "approval") && (request.Kind '= "result") Quit 0
	If (request.Kind = "result") && (request.CatalogKey = $Parameter("OcuTalon.Watch.Notice", "KEYPARTNERNOTDRAFTED")) Quit 1
	If request.ApprovalRef = "" Quit 0
	Set keys = $ListBuild($Parameter("OcuTalon.Core.BridgeSink", "KEYREQUEST"), $Parameter("OcuTalon.Core.BridgeSink", "KEYREQUESTON"), $Parameter("OcuTalon.Core.BridgeSink", "KEYDONE"), $Parameter("OcuTalon.Core.BridgeSink", "KEYFAILED"), $Parameter("OcuTalon.Core.BridgeSink", "KEYFAILEDWHY"), $Parameter("OcuTalon.Core.SettingsOps", "KEYPROPOSED"), $Parameter("OcuTalon.Core.SettingsOps", "KEYAPPLIED"), $Parameter("OcuTalon.Core.SettingsOps", "KEYSTALE"))
	Quit $ListFind(keys, request.CatalogKey) > 0
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

/// The rows member of the notification's Slots as JSON; "[]" when the Slots have none or cannot be read.
Method RowsOf(request As OcuTalon.Msg.Notification) As %String [ Private ]
{
	Set json = "[]"
	Try {
		Set slots = ##class(%DynamicAbstractObject).%FromJSON(request.Slots)
		If $IsObject(slots) && (slots.%GetTypeOf("rows") = "array") Set json = slots.rows.%ToJSON()
	} Catch exception {
		Set json = "[]"
	}
	Quit json
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
