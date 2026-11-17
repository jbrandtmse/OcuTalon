/// The trace record of a message that a channel refused because its sender may not chat (AD-14, AD-26; DW-1284): Conversation sends it for a Slack or Telegram Item, TelegramIn for a
/// paired chat's file, and EmailIn for an email, each to Intake, asynchronously, in the message's own trace session. Intake drops it silently, so that Visual Trace shows that a message
/// arrived and went no further. It holds ONLY the channel and a fixed reason: no text, no file, no sender, chat, member or team id, no user name, no address and no Ref. It is not an Item, so it has
/// no owner, no provenance and no session, and nothing decides on it.
Class OcuTalon.Channel.Refused Extends Ens.Request
{

/// The channels that send it, as a comma-separated list.
Parameter CHANNELS = "slack,telegram,email";

/// The reasons that it records, as a comma-separated list.
Parameter REASONS = "not_user";

/// The channel of the refused message: one of CHANNELS.
Property Channel As %String(MAXLEN = 16);

/// Why it went no further: one of REASONS.
Property Reason As %String(MAXLEN = 32);

Storage Default
{
<Data name="RefusedDefaultData">
<Subscript>"Refused"</Subscript>
<Value name="1">
<Value>Channel</Value>
</Value>
<Value name="2">
<Value>Reason</Value>
</Value>
</Data>
<DefaultData>RefusedDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
