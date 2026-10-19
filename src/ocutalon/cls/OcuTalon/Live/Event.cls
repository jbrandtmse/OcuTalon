/// A live event row (AD-12). Lane B. Rows are written only by OcuTalon.Live.Publish, which allocates Seq under
/// the stream's lock; nothing else saves, updates or deletes a row except the purge (Story 2.2), which deletes
/// rows and never the stream's counter. Row ids never leave the server.
Class OcuTalon.Live.Event Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.LiveEvent";

/// The most events that one poll returns for one stream.
Parameter MAXEVENTS = 200;

/// The event's number in its stream: 1, 2, 3 without gaps, committed in order.
Property Seq As %Integer;

/// A session's Ref, or the literal instance.
Property Stream As %String(COLLATION = "EXACT", MAXLEN = 22);

/// When the event was published, UTC to the second.
Property Ts As %String(MAXLEN = 20);

/// One of the types of OcuTalon.Live.Publish TYPES.
Property Type As %String(MAXLEN = 32);

/// The payload object's JSON, as the payload class exports it.
Property Payload As %String(MAXLEN = "");

Index StreamSeqIndex On (Stream, Seq) [ Unique ];

/// The events of stream with Seq above after, in Seq order, at most max, as envelopes
/// {"seq", "stream": label, "ts", "type", "payload": <object>}. label is what the browser calls the stream.
/// The query is OcuTalon's own, with no user input in its text, and runs for signed-in users who hold no SQL
/// privilege on the table, so it is prepared without the privilege check.
ClassMethod Since(stream As %String, after As %Integer, max As %Integer = {..#MAXEVENTS}, label As %String = "") As %DynamicArray
{
	Set events = []
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT TOP ? Seq, Ts, Type, Payload FROM OcuTalon_Live.Event WHERE Stream = ? AND Seq > ? ORDER BY Seq", 0)
	If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
	Set result = statement.%Execute(max, stream, after)
	If result.%SQLCODE < 0 Throw ##class(%Exception.SQL).CreateFromSQLCODE(result.%SQLCODE, result.%Message)
	While result.%Next() {
		Do events.%Push({"seq": (+result.%Get("Seq")), "stream": (label), "ts": (result.%Get("Ts")), "type": (result.%Get("Type")), "payload": (##class(%DynamicObject).%FromJSON(result.%Get("Payload")))})
	}
	Quit events
}

Storage Default
{
<Data name="EventDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Seq</Value>
</Value>
<Value name="3">
<Value>Stream</Value>
</Value>
<Value name="4">
<Value>Ts</Value>
</Value>
<Value name="5">
<Value>Type</Value>
</Value>
<Value name="6">
<Value>Payload</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.LiveEventD</DataLocation>
<DefaultData>EventDefaultData</DefaultData>
<IdLocation>^OcuTalonP.LiveEventD</IdLocation>
<IndexLocation>^OcuTalonP.LiveEventI</IndexLocation>
<StreamLocation>^OcuTalonP.LiveEventS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
