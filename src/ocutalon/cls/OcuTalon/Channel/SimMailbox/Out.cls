/// SimMailboxOut, the business operation that delivers a message to the simulated mailbox (AD-14, AD-32, AD-33). Its message map
/// takes OcuTalon.Msg.Outbound only, and it acts only when the message's SessionRef is a session (Session.Recipients gives it
/// back); for any other owner it logs a warning and records nothing (AD-4). It renders Msg.Catalog.Render(CatalogKey, Slots,
/// "mailbox") when the message has a key, otherwise it takes the message's Text, and in one transaction (Operation.Keep) saves
/// the sent mail (a SimMessage of Kind mailbox, direction out, Sender "OcuTalon", Subject Conversation.Summary of the text: its
/// first line, cut at 80 characters, no ItemId) and its Delivery row (channel mailbox, the SimMessage's Ref as ChannelMessageId, the DecisionRef, no kind or text).
/// After the commit it publishes one mailbox event on the session's stream with Live.Payload.Mailbox.FromRow of the row (the
/// other publisher is SimMailboxIn, AD-33). A render error is returned with no row and no event; a failed save keeps nothing
/// and a failed publish is logged and leaves the rows.
Class OcuTalon.Channel.SimMailbox.Out Extends OcuTalon.Channel.Operation
{

/// The channel of the Delivery rows: one of Msg.Enum CHANNEL.
Parameter CHANNEL = "mailbox";

/// The channel of the catalog text.
Parameter TEXTCHANNEL = "mailbox";

/// The sender of the mail OcuTalon sends.
Parameter SENDER = "OcuTalon";

Parameter LOGNOTASESSION = "SimMailboxOut dropped a message: its owner is not a session: ";

Parameter LOGPUBLISH = "SimMailboxOut could not publish a mailbox message: ";

XData MessageMap
{
<MapItems>
<MapItem MessageType="OcuTalon.Msg.Outbound">
<Method>OnOutbound</Method>
</MapItem>
</MapItems>
}

/// A message to send: rendered when it has a catalog key, recorded and published.
Method OnOutbound(request As OcuTalon.Msg.Outbound, Output response As Ens.Response) As %Status
{
	Set response = ""
	If '..IsSession(request.SessionRef) Quit $$$OK
	Set text = request.Text
	If request.CatalogKey '= "" {
		Set text = ##class(OcuTalon.Msg.Catalog).Render(request.CatalogKey, request.Slots, ..#TEXTCHANNEL, .sc)
		If $$$ISERR(sc) Quit sc
	}
	Set message = ##class(OcuTalon.Data.SimMessage).%New()
	Set message.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set message.SessionRef = request.SessionRef
	Set message.Kind = "mailbox"
	Set message.Direction = "out"
	Set message.Sender = ..#SENDER
	Set message.Subject = ##class(OcuTalon.Core.Conversation).Summary(text)
	Set message.Text = text
	Set message.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = ..Keep(message, ..#CHANNEL, "", "", request.DecisionRef, .row)
	If $$$ISERR(sc) Quit sc
	Do ..Announce(request.SessionRef, "mailbox", "OcuTalon.Live.Payload.Mailbox", row)
	Quit $$$OK
}

}
