/// One run of an approved fix (AD-16). Lane A.
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
</Data>
<DataLocation>^OcuTalonP.FixRunD</DataLocation>
<DefaultData>FixRunDefaultData</DefaultData>
<IdLocation>^OcuTalonP.FixRunD</IdLocation>
<IndexLocation>^OcuTalonP.FixRunI</IndexLocation>
<StreamLocation>^OcuTalonP.FixRunS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
