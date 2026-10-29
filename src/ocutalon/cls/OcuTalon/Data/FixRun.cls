/// One run of an approved fix (AD-16): one row per approved request that FixExecutor takes up, a run that could not start included. Copies holds the header ids of
/// the copies that the run resent, in resend order, each registered right after its resend, so that a run that was cut off still shows how far it got. Lane A.
Class OcuTalon.Data.FixRun Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.FixRun";

/// The Ref of the approval request (AD-11).
Property ApprovalRef As %String(MAXLEN = 22);

/// The Ref of the incident (AD-15).
Property IncidentRef As %String(MAXLEN = 22);

/// When the run started, UTC to the second.
Property StartedAt As %String(MAXLEN = 20);

/// The header ids of the copies the run resent, in resend order (the production's header ids, as text).
Property Copies As list Of %String(MAXLEN = 20);

Index ApprovalRefIndex On ApprovalRef;

Index IncidentRefIndex On IncidentRef;

Storage Default
{
<Data name="FixRunDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>ApprovalRef</Value>
</Value>
<Value name="3">
<Value>IncidentRef</Value>
</Value>
<Value name="4">
<Value>StartedAt</Value>
</Value>
<Value name="5">
<Value>Copies</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.FixRunD</DataLocation>
<DefaultData>FixRunDefaultData</DefaultData>
<IdLocation>^OcuTalonP.FixRunD</IdLocation>
<IndexLocation>^OcuTalonP.FixRunI</IndexLocation>
<StreamLocation>^OcuTalonP.FixRunS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
