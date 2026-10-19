/// A signed-in session (AD-4). Lane B.
Class OcuTalon.Data.Session Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Session";

/// The session Ref: the SessionRef of its messages and rows.
Property Ref As %String(MAXLEN = 22);

/// The trace reference of the session; unique.
Property TraceRef As %String(MAXLEN = 22);

/// The IRIS user of the session.
Property IrisUser As %String(MAXLEN = 128);

/// When the row was created, UTC to the second.
Property CreatedAt As %String(MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

Index TraceRefIndex On TraceRef [ Unique ];

Index IrisUserIndex On IrisUser;

Storage Default
{
<Data name="SessionDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>TraceRef</Value>
</Value>
<Value name="4">
<Value>IrisUser</Value>
</Value>
<Value name="5">
<Value>CreatedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.SessionD</DataLocation>
<DefaultData>SessionDefaultData</DefaultData>
<IdLocation>^OcuTalonP.SessionD</IdLocation>
<IndexLocation>^OcuTalonP.SessionI</IndexLocation>
<StreamLocation>^OcuTalonP.SessionS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
