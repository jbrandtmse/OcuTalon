/// Sets the classification of one MCP tool (AD-1, AD-10, AD-21, Story 35.2). From origin web_admin only, owner McpOps; a tool never sends it. McpOps validates the values.
Class OcuTalon.Msg.Command.ClassifyTool Extends OcuTalon.Msg.Command
{

/// The server's name.
Property Server As %String(MAXLEN = 40);

/// The tool's name on that server.
Property Tool As %String(MAXLEN = 128);

/// One of unclassified, read-only or risky.
Property Classification As %String(MAXLEN = 16);

/// The IRIS user who asked; set by the submitting code from its authenticated context, never from an argument.
Property ActingUser As %String(MAXLEN = 160);

Storage Default
{
<Data name="ClassifyToolDefaultData">
<Subscript>"ClassifyTool"</Subscript>
<Value name="1">
<Value>Server</Value>
</Value>
<Value name="2">
<Value>Tool</Value>
</Value>
<Value name="3">
<Value>Classification</Value>
</Value>
<Value name="4">
<Value>ActingUser</Value>
</Value>
</Data>
<DefaultData>ClassifyToolDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
