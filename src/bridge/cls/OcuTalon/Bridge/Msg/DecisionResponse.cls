/// The answer Decide gives for decide and diagnose requests (AD-6). Lane A.
Class OcuTalon.Bridge.Msg.DecisionResponse Extends OcuTalon.Bridge.Msg.Result
{

/// The checked decision or diagnosis reply, as JSON.
Property Payload As %String(MAXLEN = "");

Storage Default
{
<Data name="DecisionResponseDefaultData">
<Subscript>"DecisionResponse"</Subscript>
<Value name="1">
<Value>Payload</Value>
</Value>
</Data>
<DefaultData>DecisionResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
