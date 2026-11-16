/// The trace record of a Slack event that is not a turn (AD-26, NFR-14; Story 27.1): SlackIn sends it to Intake, asynchronously, in a trace session of its own,
/// and Intake drops it silently. It exists so that Visual Trace shows that an event arrived and went no further. It holds ONLY a fixed Kind, a fixed Reason
/// and the event's id: no text, no Slack member, team or channel id, no name and no email. It is not an Item, so it has no owner, no provenance and no
/// session, and nothing decides on it.
Class OcuTalon.Channel.Slack.Ignored Extends Ens.Request
{

/// The kinds of event that SlackIn records, as a comma-separated list.
Parameter KINDS = "message.im,message.channel,message.other,app_mention,other";

/// The reasons that SlackIn records, as a comma-separated list.
Parameter REASONS = "unlinked,other_team,bot,subtype,not_im,blank,no_sender,unhandled_type";

/// What kind of event it was: one of KINDS.
Property Kind As %String(MAXLEN = 32);

/// Why it went no further: one of REASONS.
Property Reason As %String(MAXLEN = 32);

/// The event_id of the envelope, as Slack sent it; empty when the envelope had none.
Property EventId As %String(MAXLEN = 64);

Storage Default
{
<Data name="IgnoredDefaultData">
<Subscript>"Ignored"</Subscript>
<Value name="1">
<Value>Kind</Value>
</Value>
<Value name="2">
<Value>Reason</Value>
</Value>
<Value name="3">
<Value>EventId</Value>
</Value>
</Data>
<DefaultData>IgnoredDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
