/// The one table for every background check, a production watch included (AD-18). Lane A. WatchOps creates and removes a row, and Checks records each
/// run on it: LastRunAt, Result, Finding, LastRunHeaderId and NextDueAt.
Class OcuTalon.Data.BackgroundCheck Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Check";

/// The public reference: 22 base64url characters from OcuTalon.Bridge.Ids.NewRef().
Property Ref As %String(MAXLEN = 22);

/// The owning session's Ref.
Property SessionRef As %String(MAXLEN = 22);

/// The kind of check: production.
Property Kind As %String(MAXLEN = 32);

/// The namespace of the watched production.
Property Namespace As %String(MAXLEN = 128);

/// The watched production class.
Property Production As %String(MAXLEN = 128);

/// The name shown to the user.
Property DisplayName As %String(MAXLEN = 128);

/// The IRIS user who asked for the check.
Property AskedBy As %String(MAXLEN = 128);

/// When the check was created: UTC to the second, written by WatchOps. A watch's failures start no earlier than the earliest of these.
Property CreatedAt As %String(MAXLEN = 20);

/// When the check is next due.
Property NextDueAt As %String(MAXLEN = 20);

/// When the check last ran.
Property LastRunAt As %String(MAXLEN = 20);

/// One of Msg.Enum CHECKRESULT.
Property Result As %String(MAXLEN = 32);

/// What the last run found.
Property Finding As %String(MAXLEN = 1000);

/// The trace header id of the latest run.
Property LastRunHeaderId As %Integer;

Index RefIndex On Ref [ Unique ];

Index SessionRefIndex On SessionRef;

Index NamespaceProductionIndex On (Namespace, Production);

Storage Default
{
<Data name="BackgroundCheckDefaultData">
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
<Value>Kind</Value>
</Value>
<Value name="5">
<Value>Namespace</Value>
</Value>
<Value name="6">
<Value>Production</Value>
</Value>
<Value name="7">
<Value>DisplayName</Value>
</Value>
<Value name="8">
<Value>AskedBy</Value>
</Value>
<Value name="9">
<Value>NextDueAt</Value>
</Value>
<Value name="10">
<Value>LastRunAt</Value>
</Value>
<Value name="11">
<Value>Result</Value>
</Value>
<Value name="12">
<Value>Finding</Value>
</Value>
<Value name="13">
<Value>LastRunHeaderId</Value>
</Value>
<Value name="14">
<Value>CreatedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.CheckD</DataLocation>
<DefaultData>BackgroundCheckDefaultData</DefaultData>
<IdLocation>^OcuTalonP.CheckD</IdLocation>
<IndexLocation>^OcuTalonP.CheckI</IndexLocation>
<StreamLocation>^OcuTalonP.CheckS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
