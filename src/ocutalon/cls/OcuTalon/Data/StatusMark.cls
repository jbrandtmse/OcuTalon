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

/// Creates or replaces the row of the mark, with the value and RecordedAt (UTC, to the second). An empty value deletes the
/// row, and a mark that has none is an error status that names the empty mark.
ClassMethod Record(mark As %String, value As %String) As %Status
{
	If $Get(mark) = "" Quit $SYSTEM.Status.Error(5001, "A status mark needs a name: the mark is empty")
	Set row = ..MarkIndexOpen(mark)
	If $Get(value) = "" {
		If $IsObject(row) Quit ..%DeleteId(row.%Id())
		Quit $SYSTEM.Status.OK()
	}
	If '$IsObject(row) {
		Set row = ..%New()
		Set row.Mark = mark
	}
	Set row.Value = value
	Set row.RecordedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit row.%Save()
}

/// The value of the mark, or "" when it has no row.
ClassMethod Get(mark As %String) As %String
{
	If $Get(mark) = "" Quit ""
	Set row = ..MarkIndexOpen(mark)
	Quit $Select($IsObject(row): row.Value, 1: "")
}

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
