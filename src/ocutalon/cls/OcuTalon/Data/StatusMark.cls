/// A named status mark, such as the last heartbeat tick or the Telegram state (AD-18). Lane B.
Class OcuTalon.Data.StatusMark Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.StatusMark";

/// The name of the mark; unique.
Property Mark As %String(MAXLEN = 128);

/// The value of the mark.
Property Value As %String(MAXLEN = 1000);

/// When the row was recorded, UTC to the second.
Property RecordedAt As %String(MAXLEN = 20);

Index MarkIndex On Mark [ Unique ];

Storage Default
{
<Data name="StatusMarkDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Mark</Value>
</Value>
<Value name="3">
<Value>Value</Value>
</Value>
<Value name="4">
<Value>RecordedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.StatusMarkD</DataLocation>
<DefaultData>StatusMarkDefaultData</DefaultData>
<IdLocation>^OcuTalonP.StatusMarkD</IdLocation>
<IndexLocation>^OcuTalonP.StatusMarkI</IndexLocation>
<StreamLocation>^OcuTalonP.StatusMarkS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
