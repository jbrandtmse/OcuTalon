/// Searches one of the session's memories for a query (AD-1, AD-21, AD-29; Story 41.9). A read: it changes nothing, needs no approval and is no command that
/// an evaluation counts as acting. Owner: MemoryOps (OcuTalon.Memory.Ops, Lane A), which searches with this command's own SessionRef and answers the items in
/// CommandResult Data. Origin: web_user only; the web layer sets the CSP session's SessionRef, never the client's. Not a tool verb.
Class OcuTalon.Msg.Command.SearchMemory Extends OcuTalon.Msg.Command
{

/// The text to search for, at most 2,000 characters (the length of OcuTalon.Data.Memory Text).
Property Query As %String(MAXLEN = 2000);

Storage Default
{
<Data name="SearchMemoryDefaultData">
<Subscript>"SearchMemory"</Subscript>
<Value name="1">
<Value>Query</Value>
</Value>
</Data>
<DefaultData>SearchMemoryDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
