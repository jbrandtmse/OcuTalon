/// A watched production's high-water mark (AD-15). Lane A. Written only by OcuTalon.Watch.FailurePoller (AD-33); the mark is time-based, so a
/// failure whose header enters the error status late is still read (see OcuTalon.Watch.Mark).
Class OcuTalon.Data.WatchMark Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.WatchMark";

/// The namespace of the watched production.
Property Namespace As %String(MAXLEN = 128);

/// The watched production class.
Property Production As %String(MAXLEN = 128);

/// The newest failure time read, as IRIS stores it: UTC, YYYY-MM-DD HH:MM:SS.sss. Empty before the first failure.
Property MarkAt As %String(MAXLEN = 23);

/// The failures already batched whose time is within the overlap before MarkAt: h<header id> or l<log id>, comma-separated.
Property Seen As %String(MAXLEN = "");

Index NamespaceProductionIndex On (Namespace, Production) [ Unique ];

Storage Default
{
<Data name="WatchMarkDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Namespace</Value>
</Value>
<Value name="3">
<Value>Production</Value>
</Value>
<Value name="4">
<Value>MarkAt</Value>
</Value>
<Value name="5">
<Value>Seen</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.WatchMarkD</DataLocation>
<DefaultData>WatchMarkDefaultData</DefaultData>
<IdLocation>^OcuTalonP.WatchMarkD</IdLocation>
<IndexLocation>^OcuTalonP.WatchMarkI</IndexLocation>
<StreamLocation>^OcuTalonP.WatchMarkS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
