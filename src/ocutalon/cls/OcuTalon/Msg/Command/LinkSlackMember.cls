/// Links a Slack member to an OcuTalon user (AD-1, AD-24; Story 27.3). The user's name and the member id are never properties: Handoff is the uri that
/// OcuTalon.Core.SecretHandoff.Put returned for {user, member}, and SettingsOps takes them from it. Origin: web_admin only; no tool verb and no verb of a Slack sender.
Class OcuTalon.Msg.Command.LinkSlackMember Extends OcuTalon.Msg.Command
{

/// The uri of the handoff of {user, member} (secret://handoff/<Ref>), never the values.
Property Handoff As %String(MAXLEN = 200);

/// The IRIS user who asked; set by the submitting code from its authenticated context, never from an argument.
Property ActingUser As %String(MAXLEN = 160);

Storage Default
{
<Data name="LinkSlackMemberDefaultData">
<Subscript>"LinkSlackMember"</Subscript>
<Value name="1">
<Value>Handoff</Value>
</Value>
<Value name="2">
<Value>ActingUser</Value>
</Value>
</Data>
<DefaultData>LinkSlackMemberDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
