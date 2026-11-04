/// Drops a Telegram pairing (AD-4).
Class OcuTalon.Msg.Command.Unpair Extends OcuTalon.Msg.Command
{

/// The chat's Ref.
Property ChatRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="UnpairDefaultData">
<Subscript>"Unpair"</Subscript>
<Value name="1">
<Value>ChatRef</Value>
</Value>
</Data>
<DefaultData>UnpairDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
