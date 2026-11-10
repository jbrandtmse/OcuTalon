/// Forgets one of the session's memories (AD-1, AD-21, AD-29; Story 34.2). Owner: MemoryOps (OcuTalon.Memory.Ops, Lane A). Origin: tool or web_user.
/// From tool it has the same context check as SaveMemory: a tool forgets only its own session's memory. From web_user (Story 41.9) the
/// web layer sets the CSP session's SessionRef, and MemoryOps forgets only that session's own row.
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
