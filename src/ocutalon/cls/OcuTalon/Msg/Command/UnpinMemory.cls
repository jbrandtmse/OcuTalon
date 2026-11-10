/// Unpins one of the session's memories (AD-1, AD-21, AD-29; Story 41.9). Owner: MemoryOps (OcuTalon.Memory.Ops, Lane A; handled from Story 41.12).
/// Origin: web_user only; the web layer sets the CSP session's SessionRef.
Class OcuTalon.Msg.Command.UnpinMemory Extends OcuTalon.Msg.Command
{

/// The memory's Ref (OcuTalon.Data.Memory).
Property MemoryRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="UnpinMemoryDefaultData">
<Subscript>"UnpinMemory"</Subscript>
<Value name="1">
<Value>MemoryRef</Value>
</Value>
</Data>
<DefaultData>UnpinMemoryDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
