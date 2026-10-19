/// A group of same-cause failures within an incident (AD-15). Lane A.
Class OcuTalon.Data.FailureGroup Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.FailGroup";

/// The Ref of the incident (AD-15).
Property IncidentRef As %String(MAXLEN = 22);

/// The production item that failed.
Property ItemName As %String(MAXLEN = 128);

/// The normalised error text that groups the failures.
Property ErrorPattern As %String(MAXLEN = 1000);

Index IncidentRefIndex On IncidentRef;

Storage Default
{
<Data name="FailureGroupDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>IncidentRef</Value>
</Value>
<Value name="3">
<Value>ItemName</Value>
</Value>
<Value name="4">
<Value>ErrorPattern</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.FailGroupD</DataLocation>
<DefaultData>FailureGroupDefaultData</DefaultData>
<IdLocation>^OcuTalonP.FailGroupD</IdLocation>
<IndexLocation>^OcuTalonP.FailGroupI</IndexLocation>
<StreamLocation>^OcuTalonP.FailGroupS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
