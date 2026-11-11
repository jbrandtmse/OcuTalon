/// The stored dry run of an approval request; its keys are the keys of ApprovalRequest DRYRUNKEYS, and EitherWay and Reading, which FromRow works out for the
/// payload from the stored dry run and the request's parameters. Neither is kept on the request or in its dry run; Live.Event's Payload text holds them as it holds the rest of a payload. Lane B.
Class OcuTalon.Live.Payload.Part.DryRun Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The messages the action would touch.
Property Affected As %Integer(%JSONFIELDNAME = "affected");

/// The messages it would resend.
Property Resend As %Integer(%JSONFIELDNAME = "resend");

/// The messages it would leave out.
Property LeftOut As %Integer(%JSONFIELDNAME = "leftOut");

/// The field it would change.
Property Field As %String(%JSONFIELDNAME = "field", MAXLEN = 128);

/// The field before the change.
Property Before As %String(%JSONFIELDNAME = "before", MAXLEN = 1000);

/// The field after the change.
Property After As %String(%JSONFIELDNAME = "after", MAXLEN = 1000);

/// The item noun, singular and plural.
Property ItemNoun As OcuTalon.Live.Payload.Part.ItemNoun(%JSONFIELDNAME = "itemNoun");

/// The item a suspend or resume would change (Story 23.2); Before and After then hold its state, enabled or disabled.
Property Item As %String(%JSONFIELDNAME = "item", MAXLEN = 128);

/// The item a reroute's messages are at now, and the item it would send them to, and the header id of its first message (Story 23.2).
Property From As %String(%JSONFIELDNAME = "from", MAXLEN = 128);

Property To As %String(%JSONFIELDNAME = "to", MAXLEN = 128);

Property Example As %String(%JSONFIELDNAME = "example", MAXLEN = 32);

/// The text of a partner delay notice and each of its recipients as "Name <address>" (Story 23.5), and 1 when the notice goes to the Simulated mailbox, not to a real inbox: the
/// dry run of a partner_warning request holds all three.
Property Notice As %String(%JSONFIELDNAME = "notice", MAXLEN = "");

Property Recipients As list Of %String(%JSONFIELDNAME = "recipients", MAXLEN = 300);

Property Simulated As %Boolean(%JSONFIELDNAME = "simulated") [ InitialExpression = 0 ];

/// 1 when Watch.Notice Reading answers for the stored dry run and the request's parameters: the source format is MM/DD/YYYY or DD/MM/YYYY and before reads in both orders as
/// two different dates (the notice then carries the either-way line). Worked out for the payload, not kept on the request.
Property EitherWay As %Boolean(%JSONFIELDNAME = "eitherWay") [ InitialExpression = 0 ];

/// The reading the dry run used when EitherWay is 1 ("month first" or "day first"); empty otherwise. Worked out for the payload, not kept on the request.
Property Reading As %String(%JSONFIELDNAME = "reading", MAXLEN = 32);

}
