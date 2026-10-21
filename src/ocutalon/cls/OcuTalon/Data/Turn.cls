/// A turn in a session's queue (AD-30). Lane B.
Class OcuTalon.Data.Turn Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Turn";

/// The public reference: 22 base64url characters from OcuTalon.Bridge.Ids.NewRef().
Property Ref As %String(MAXLEN = 22);

/// The owning session's Ref.
Property SessionRef As %String(MAXLEN = 22);

/// queued, running or done.
Property State As %String(MAXLEN = 32);

/// The channel: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

/// Display only (AD-30).
Property FromGuide As %Boolean [ InitialExpression = 0 ];

/// The Ref of the turn's triage decision (AD-20).
Property TriageDecisionRef As %String(MAXLEN = 22);

/// The Ref of the turn's reply decision (AD-20).
Property TurnDecisionRef As %String(MAXLEN = 22);

/// When the row was created, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

Index SessionRefIndex On SessionRef;

Storage Default
{
<Data name="TurnDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>SessionRef</Value>
</Value>
<Value name="4">
<Value>State</Value>
</Value>
<Value name="5">
<Value>Channel</Value>
</Value>
<Value name="6">
<Value>FromGuide</Value>
</Value>
<Value name="7">
<Value>TriageDecisionRef</Value>
</Value>
<Value name="8">
<Value>TurnDecisionRef</Value>
</Value>
<Value name="9">
<Value>CreatedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.TurnD</DataLocation>
<DefaultData>TurnDefaultData</DefaultData>
<IdLocation>^OcuTalonP.TurnD</IdLocation>
<IndexLocation>^OcuTalonP.TurnI</IndexLocation>
<StreamLocation>^OcuTalonP.TurnS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
