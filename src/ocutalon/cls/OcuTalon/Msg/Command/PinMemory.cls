/// Pins one of the session's memories so that it is always recalled (AD-1, AD-21, AD-29; Story 41.9). Owner: MemoryOps (OcuTalon.Memory.Ops, Lane A; handled from Story 41.12).
/// Origin: web_user only; the web layer sets the CSP session's SessionRef.
Class OcuTalon.Msg.Command.PinMemory Extends OcuTalon.Msg.Command
{

/// The memory's Ref (OcuTalon.Data.Memory).
Property MemoryRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="PinMemoryDefaultData">
<Subscript>"PinMemory"</Subscript>
<Value name="1">
<Value>MemoryRef</Value>
</Value>
</Data>
<DefaultData>PinMemoryDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
