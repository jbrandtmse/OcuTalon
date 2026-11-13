/// Acknowledges one page (AD-14, AD-29; Story 36.2): owner IncidentManager (Story 23.4). It is not a tool verb, and it copies GotIt's two properties instead of extending GotIt, which SessionOps tests by class.
Class OcuTalon.Msg.Command.AckPage Extends OcuTalon.Msg.Command
{

/// The page's Ref: the Ref of its Data.Page row, which every channel's Delivery row records as its DecisionRef.
Property Ref As %String(MAXLEN = 22);

/// Where the acknowledgement came from: web, phone or telegram.
Property Channel As %String(MAXLEN = 32);

Storage Default
{
<Data name="AckPageDefaultData">
<Subscript>"AckPage"</Subscript>
<Value name="1">
<Value>Ref</Value>
</Value>
<Value name="2">
<Value>Channel</Value>
</Value>
</Data>
<DefaultData>AckPageDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
