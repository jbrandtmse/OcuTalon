/// Stops watching a production (AD-15).
Class OcuTalon.Msg.Command.StopWatch Extends OcuTalon.Msg.Command
{

/// The namespace of the watched production.
Property Namespace As %String(MAXLEN = 128);

/// The watched production class.
Property Production As %String(MAXLEN = 128);

/// The kind of watch: queues for the queue-backlog check, empty (or production) for a production watch.
Property Kind As %String(MAXLEN = 32);

Storage Default
{
<Data name="StopWatchDefaultData">
<Subscript>"StopWatch"</Subscript>
<Value name="1">
<Value>Namespace</Value>
</Value>
<Value name="2">
<Value>Production</Value>
</Value>
<Value name="3">
<Value>Kind</Value>
</Value>
</Data>
<DefaultData>StopWatchDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
