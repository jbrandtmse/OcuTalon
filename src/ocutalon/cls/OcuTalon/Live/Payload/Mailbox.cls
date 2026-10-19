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

/// True until the mail is opened.
Property Unread As %Boolean(%JSONFIELDNAME = "unread") [ InitialExpression = 0 ];

/// When the mail arrived or was sent, UTC to the second.
Property CreatedAt As %String(%JSONFIELDNAME = "createdAt", MAXLEN = 20);

}
