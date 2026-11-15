/// Registers an MCP server (AD-1, AD-21, Story 35.2). From origin web_admin only, owner McpOps; a tool never sends it. It carries no secret: Handoff is the uri that OcuTalon.Core.SecretHandoff.Put returned for the server's credential (empty for a server with none), and McpOps takes the secret from it once, in its own job, writes it to the wallet and writes the Config Store entry, which holds only a secret:// reference (Story 21.4; DW-1041). McpOps validates the values.
Class OcuTalon.Msg.Command.AddMcpServer Extends OcuTalon.Msg.Command
{

/// The server's name: the <server> of the Config Store entry AI.MCP.OcuTalon_<server>.
Property Server As %String(MAXLEN = 40);

/// The server's URL.
Property Url As %String(MAXLEN = 2000);

/// The uri of the credential's handoff (secret://handoff/<name>), never the credential; empty when the server has none.
Property Handoff As %String(MAXLEN = 128);

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
<Value name="4">
<Value>Handoff</Value>
</Value>
</Data>
<DefaultData>AddMcpServerDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
