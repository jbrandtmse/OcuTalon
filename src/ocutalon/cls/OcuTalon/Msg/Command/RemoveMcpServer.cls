/// Removes a registered MCP server (AD-1, AD-21, Story 35.2). From origin web_admin only, owner McpOps; a tool never sends it. McpOps validates the value.
Class OcuTalon.Msg.Command.RemoveMcpServer Extends OcuTalon.Msg.Command
{

/// The server's name.
Property Server As %String(MAXLEN = 40);

/// The IRIS user who asked; set by the submitting code from its authenticated context, never from an argument.
Property ActingUser As %String(MAXLEN = 160);

Storage Default
{
<Data name="RemoveMcpServerDefaultData">
<Subscript>"RemoveMcpServer"</Subscript>
<Value name="1">
<Value>Server</Value>
</Value>
<Value name="2">
<Value>ActingUser</Value>
</Value>
</Data>
<DefaultData>RemoveMcpServerDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
