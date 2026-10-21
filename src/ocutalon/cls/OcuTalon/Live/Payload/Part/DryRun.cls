/// The stored dry run of an approval request; its keys are the keys of ApprovalRequest DRYRUNKEYS. Lane B.
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

}
