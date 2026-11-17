/// Removes a Slack member's link (AD-1; Story 27.3). LinkRef is the link's own opaque Ref (Data.SlackLink), which names no person, so the command needs no handoff.
/// Origin: web_admin only; no tool verb and no verb of a Slack sender.
Class OcuTalon.Msg.Command.UnlinkSlackMember Extends OcuTalon.Msg.Command
{

/// The link's Ref.
Property LinkRef As %String(MAXLEN = 22);

/// The IRIS user who asked; set by the submitting code from its authenticated context, never from an argument.
Property ActingUser As %String(MAXLEN = 160);

Storage Default
{
<Data name="UnlinkSlackMemberDefaultData">
<Subscript>"UnlinkSlackMember"</Subscript>
<Value name="1">
<Value>LinkRef</Value>
</Value>
<Value name="2">
<Value>ActingUser</Value>
</Value>
</Data>
<DefaultData>UnlinkSlackMemberDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
