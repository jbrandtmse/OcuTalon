/// The payload of the pairing live event: whether the session is paired with a Telegram chat. Lane B publishes it.
Class OcuTalon.Live.Payload.Pairing Extends (%RegisteredObject, %JSON.Adaptor)
{

/// True while a chat is paired.
Property Paired As %Boolean(%JSONFIELDNAME = "paired") [ InitialExpression = 0 ];

/// The paired chat's display name.
Property DisplayName As %String(%JSONFIELDNAME = "displayName", MAXLEN = 128);

}
