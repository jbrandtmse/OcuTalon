/// Completes a Telegram pairing (AD-4).
Class OcuTalon.Msg.Command.Pair Extends OcuTalon.Msg.Command
{

/// The hash of the pairing code, never the code (AD-4).
Property CodeHash As %String(MAXLEN = 128);

/// The chat's Ref, never a chat id (AD-14).
Property ChatRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="PairDefaultData">
<Subscript>"Pair"</Subscript>
<Value name="1">
<Value>CodeHash</Value>
</Value>
<Value name="2">
<Value>ChatRef</Value>
</Value>
</Data>
<DefaultData>PairDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
