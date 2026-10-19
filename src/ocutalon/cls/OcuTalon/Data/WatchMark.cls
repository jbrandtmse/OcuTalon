/// A watched production's high-water mark (AD-15). Lane A.
Class OcuTalon.Data.WatchMark Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.WatchMark";

/// The namespace of the watched production.
Property Namespace As %String(MAXLEN = 128);

/// The watched production class.
Property Production As %String(MAXLEN = 128);

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
</Data>
<DataLocation>^OcuTalonP.WatchMarkD</DataLocation>
<DefaultData>WatchMarkDefaultData</DefaultData>
<IdLocation>^OcuTalonP.WatchMarkD</IdLocation>
<IndexLocation>^OcuTalonP.WatchMarkI</IndexLocation>
<StreamLocation>^OcuTalonP.WatchMarkS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
