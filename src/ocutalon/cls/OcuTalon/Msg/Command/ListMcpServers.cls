/// Lists the MCP servers and their tools for Settings (AD-1, AD-21; Story 21.4). A read: it changes nothing. CommandsIn takes it from origin web_admin only, and
/// SettingsOps answers it in its own production job (the REST process cannot run the reads), with the CommandResult's Data holding the body of GET /v1/settings/mcp.
/// No tool sends it. It carries nothing but the acting user.
Class OcuTalon.Msg.Command.ListMcpServers Extends OcuTalon.Msg.Command
{

/// The IRIS user who asked; set by the submitting code from its authenticated context, never from an argument.
Property ActingUser As %String(MAXLEN = 160);

Storage Default
{
<Data name="ListMcpServersDefaultData">
<Subscript>"ListMcpServers"</Subscript>
<Value name="1">
<Value>ActingUser</Value>
</Value>
</Data>
<DefaultData>ListMcpServersDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
