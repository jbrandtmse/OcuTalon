/// Marks one tell-now notice as handled (AD-14; Story 18.4). The first press wins.
Class OcuTalon.Msg.Command.GotIt Extends OcuTalon.Msg.Command
{

/// The notice's Ref: the Ref of the Decision behind it, which every channel's Delivery row records as its DecisionRef.
Property Ref As %String(MAXLEN = 22);

/// Where the press came from: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

Storage Default
{
<Data name="GotItDefaultData">
<Subscript>"GotIt"</Subscript>
<Value name="1">
<Value>Ref</Value>
</Value>
<Value name="2">
<Value>Channel</Value>
</Value>
</Data>
<DefaultData>GotItDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
