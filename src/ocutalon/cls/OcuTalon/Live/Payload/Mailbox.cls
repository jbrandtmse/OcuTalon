/// The payload of the mailbox live event: one mail of the simulated mailbox. Lane B publishes it.
Class OcuTalon.Live.Payload.Mailbox Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The mail's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// One of in, out.
Property Direction As %String(%JSONFIELDNAME = "direction", MAXLEN = 32);

/// The item's Ref (AD-14).
Property ItemId As %String(%JSONFIELDNAME = "itemId", MAXLEN = 22);

/// The sender.
Property Sender As %String(%JSONFIELDNAME = "sender", MAXLEN = 1000);

/// The subject.
Property Subject As %String(%JSONFIELDNAME = "subject", MAXLEN = 1000);

/// The body.
Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = "");

/// 1 for every mail the server serves: the server records no reading; the page keeps which mails were opened in its browser.
Property Unread As %Boolean(%JSONFIELDNAME = "unread") [ InitialExpression = 0 ];

/// When the mail arrived or was sent, UTC to the second.
Property CreatedAt As %String(%JSONFIELDNAME = "createdAt", MAXLEN = 20);

/// The payload for a mailbox row: every column, with Unread 1.
ClassMethod FromRow(row As OcuTalon.Data.SimMessage) As OcuTalon.Live.Payload.Mailbox
{
	Set payload = ..%New()
	Set payload.Ref = row.Ref
	Set payload.Direction = row.Direction
	Set payload.ItemId = row.ItemId
	Set payload.Sender = row.Sender
	Set payload.Subject = row.Subject
	Set payload.Text = row.Text
	Set payload.Unread = 1
	Set payload.CreatedAt = row.CreatedAt
	Quit payload
}

}
