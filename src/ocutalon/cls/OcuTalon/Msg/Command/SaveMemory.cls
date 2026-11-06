/// Saves one memory for the session (AD-1, AD-21, AD-29; Story 34.2). Owner: MemoryOps (OcuTalon.Memory.Ops, Lane A). Origin: tool only,
/// and inside a bridge context CommandsIn refuses a SessionRef that is not the context's OwnerRef, so a tool saves only for its own session.
Class OcuTalon.Msg.Command.SaveMemory Extends OcuTalon.Msg.Command
{

/// What to remember: at most 2,000 characters.
Property Text As %String(MAXLEN = 2000);

Storage Default
{
<Data name="SaveMemoryDefaultData">
<Subscript>"SaveMemory"</Subscript>
<Value name="1">
<Value>Text</Value>
</Value>
</Data>
<DefaultData>SaveMemoryDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
