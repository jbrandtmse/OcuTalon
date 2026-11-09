/// Registers an MCP server (AD-1, AD-21, Story 35.2). From origin web_admin only, owner McpOps; a tool never sends it. It carries no secret: the server's credential reaches the wallet through SettingsOps.SaveMcpEntry before this command is submitted, and the Config Store entry holds only a secret:// reference. McpOps validates the values.
Class OcuTalon.Msg.Command.AddMcpServer Extends OcuTalon.Msg.Command
{

/// The server's name: the <server> of the Config Store entry AI.MCP.OcuTalon_<server>.
Property Server As %String(MAXLEN = 40);

/// The server's URL.
Property Url As %String(MAXLEN = 2000);

/// The IRIS user who asked; set by the submitting code from its authenticated context, never from an argument.
Property ActingUser As %String(MAXLEN = 160);

Storage Default
{
<Data name="AddMcpServerDefaultData">
<Subscript>"AddMcpServer"</Subscript>
<Value name="1">
<Value>Server</Value>
</Value>
<Value name="2">
<Value>Url</Value>
</Value>
<Value name="3">
<Value>ActingUser</Value>
</Value>
</Data>
<DefaultData>AddMcpServerDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
