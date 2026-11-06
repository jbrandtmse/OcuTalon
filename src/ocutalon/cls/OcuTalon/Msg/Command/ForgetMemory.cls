/// Forgets one of the session's memories (AD-1, AD-21, AD-29; Story 34.2). Owner: MemoryOps (OcuTalon.Memory.Ops, Lane A). Origin: tool only,
/// with the same context check as SaveMemory: a tool forgets only its own session's memory.
Class OcuTalon.Msg.Command.ForgetMemory Extends OcuTalon.Msg.Command
{

/// The memory's Ref (OcuTalon.Data.Memory).
Property MemoryRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="ForgetMemoryDefaultData">
<Subscript>"ForgetMemory"</Subscript>
<Value name="1">
<Value>MemoryRef</Value>
</Value>
</Data>
<DefaultData>ForgetMemoryDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
