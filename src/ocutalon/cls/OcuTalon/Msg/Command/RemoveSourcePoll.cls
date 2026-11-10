/// Stops one MCP source poll and removes it (AD-1, AD-21, Story 35.2). From origin web_admin only, owner McpOps; a tool never sends it. McpOps validates the value.
Class OcuTalon.Msg.Command.RemoveSourcePoll Extends OcuTalon.Msg.Command
{

/// The source's Ref.
Property SourceRef As %String(MAXLEN = 22);

/// The IRIS user who asked; set by the submitting code from its authenticated context, never from an argument.
Property ActingUser As %String(MAXLEN = 160);

Storage Default
{
<Data name="RemoveSourcePollDefaultData">
<Subscript>"RemoveSourcePoll"</Subscript>
<Value name="1">
<Value>SourceRef</Value>
</Value>
<Value name="2">
<Value>ActingUser</Value>
</Value>
</Data>
<DefaultData>RemoveSourcePollDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
