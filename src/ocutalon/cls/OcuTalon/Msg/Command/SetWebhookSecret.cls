/// Replaces the secret of one of the admin's own webhooks (AD-1, AD-19; Story 35.3). The secret is never a property: Handoff is the uri that
/// OcuTalon.Core.SecretHandoff.Put returned, and SettingsOps takes the secret from it.
Class OcuTalon.Msg.Command.SetWebhookSecret Extends OcuTalon.Msg.Command
{

/// The webhook's Ref.
Property WebhookRef As %String(MAXLEN = 22);

/// The uri of the secret's handoff (secret://handoff/<Ref>), never the secret.
Property Handoff As %String(MAXLEN = 128);

/// The IRIS user who asked; set by the submitting code from its authenticated context, never from an argument.
Property ActingUser As %String(MAXLEN = 160);

Storage Default
{
<Data name="SetWebhookSecretDefaultData">
<Subscript>"SetWebhookSecret"</Subscript>
<Value name="1">
<Value>WebhookRef</Value>
</Value>
<Value name="2">
<Value>Handoff</Value>
</Value>
<Value name="3">
<Value>ActingUser</Value>
</Value>
</Data>
<DefaultData>SetWebhookSecretDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
