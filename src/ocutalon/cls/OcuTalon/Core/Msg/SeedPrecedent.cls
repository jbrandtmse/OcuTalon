/// One precedent row for an evaluation run (AD-21 as amended 2026-11-08, AD-22; Story 41.2). EvalIn is the only sender, and PrecedentOps accepts it only
/// while PrecedentOps.EvalOn() is 1. The row has owner eval and EvalRunRef set to RunRef.
Class OcuTalon.Core.Msg.SeedPrecedent Extends Ens.Request
{

/// Every message to PrecedentOps is answered with a CommandResult.
Parameter RESPONSECLASSNAME = "OcuTalon.Msg.CommandResult";

/// The Ref of the evaluation run that owns the row.
Property RunRef As %String(MAXLEN = 22);

/// The row's channel: one of Msg.Enum CHANNEL, or empty.
Property Channel As %String(MAXLEN = 32);

/// The row's match key.
Property MatchKey As %String(MAXLEN = 512);

/// The row's summary.
Property Summary As %String(MAXLEN = 80);

/// The outcome then: one of Msg.Enum OUTCOME, or empty.
Property Outcome As %String(MAXLEN = 32);

/// noise, approved or rejected.
Property Answer As %String(MAXLEN = 32);

/// When the answer was given, UTC to the second; empty means now.
Property AnsweredAt As %String(MAXLEN = 20);

Storage Default
{
<Data name="SeedPrecedentDefaultData">
<Subscript>"SeedPrecedent"</Subscript>
<Value name="1">
<Value>RunRef</Value>
</Value>
<Value name="2">
<Value>Channel</Value>
</Value>
<Value name="3">
<Value>MatchKey</Value>
</Value>
<Value name="4">
<Value>Summary</Value>
</Value>
<Value name="5">
<Value>Outcome</Value>
</Value>
<Value name="6">
<Value>Answer</Value>
</Value>
<Value name="7">
<Value>AnsweredAt</Value>
</Value>
</Data>
<DefaultData>SeedPrecedentDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
