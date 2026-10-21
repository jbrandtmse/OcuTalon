/// The heartbeat's tick: HeartbeatIn sends it to Checks every minute (AD-18). Lane B.
Class OcuTalon.Msg.Tick Extends Ens.Request
{

/// When this tick was taken, UTC to the second.
Property TickAt As %String(MAXLEN = 20);

/// When the previous tick was taken; empty on the first.
Property PreviousTickAt As %String(MAXLEN = 20);

/// True when ticks were missed since the previous one; Checks then runs each due check once (AD-18).
Property CatchUp As %Boolean [ InitialExpression = 0 ];

Storage Default
{
<Data name="TickDefaultData">
<Subscript>"Tick"</Subscript>
<Value name="1">
<Value>TickAt</Value>
</Value>
<Value name="2">
<Value>PreviousTickAt</Value>
</Value>
<Value name="3">
<Value>CatchUp</Value>
</Value>
</Data>
<DefaultData>TickDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
