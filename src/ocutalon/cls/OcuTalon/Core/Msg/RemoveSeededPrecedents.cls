/// The removal of every precedent row that an evaluation run seeded (AD-21 as amended 2026-11-08, AD-22; Story 41.2). EvalIn is the only sender, and
/// PrecedentOps accepts it only while PrecedentOps.EvalOn() is 1.
Class OcuTalon.Core.Msg.RemoveSeededPrecedents Extends Ens.Request
{

/// Every message to PrecedentOps is answered with a CommandResult.
Parameter RESPONSECLASSNAME = "OcuTalon.Msg.CommandResult";

/// The Ref of the evaluation run whose rows are removed.
Property RunRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="RemoveSeededPrecedentsDefaultData">
<Subscript>"RemoveSeededPrecedents"</Subscript>
<Value name="1">
<Value>RunRef</Value>
</Value>
</Data>
<DefaultData>RemoveSeededPrecedentsDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
