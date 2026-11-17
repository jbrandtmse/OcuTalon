/// The message that tells MemoryOps which memories a reply used (AD-1, AD-4, AD-21, AD-26, Story 28.2): the memories that were in the HostData of a usable turn reply
/// that Decide accepted, which Agent.Content sends through the adapterless service MemoryIn. It is not a command: no tool, route or channel can send it, and it names
/// one owner (AD-4). MemoryOps sets LastUsedAt of those of the owner's memories that it names, never to an earlier time than they already have, and ignores a Ref that
/// another owner's memory or no memory has. It holds Refs and a time only, never a memory's text.
Class OcuTalon.Memory.Msg.Used Extends Ens.Request
{

/// The Ref of the session that owns the memories (the turn's OwnerRef).
Property SessionRef As %String(MAXLEN = 22);

/// The Refs of the memories that the reply used, as a JSON array of strings.
Property MemoryRefs As %String(MAXLEN = 1000);

/// When the reply was accepted: UTC to the second.
Property UsedAt As %String(MAXLEN = 20);

Storage Default
{
<Data name="UsedDefaultData">
<Subscript>"Used"</Subscript>
<Value name="1">
<Value>SessionRef</Value>
</Value>
<Value name="2">
<Value>MemoryRefs</Value>
</Value>
<Value name="3">
<Value>UsedAt</Value>
</Value>
</Data>
<DefaultData>UsedDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
