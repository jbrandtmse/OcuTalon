/// A session's guide state (AD-1). Lane B.
Class OcuTalon.Data.GuideState Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Guide";

/// Unique.
Property SessionRef As %String(MAXLEN = 22);

/// The session's run epoch.
Property RunEpoch As %Integer;

/// True once the session opened a trace link.
Property TraceOpened As %Boolean [ InitialExpression = 0 ];

Index SessionRefIndex On SessionRef [ Unique ];

Storage Default
{
<Data name="GuideStateDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>SessionRef</Value>
</Value>
<Value name="3">
<Value>RunEpoch</Value>
</Value>
<Value name="4">
<Value>TraceOpened</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.GuideD</DataLocation>
<DefaultData>GuideStateDefaultData</DefaultData>
<IdLocation>^OcuTalonP.GuideD</IdLocation>
<IndexLocation>^OcuTalonP.GuideI</IndexLocation>
<StreamLocation>^OcuTalonP.GuideS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
