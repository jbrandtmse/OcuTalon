/// Makes one read-only MCP tool a source that OcuTalon calls on a schedule, or changes that source (AD-1, AD-21, Story 35.2). From origin web_admin only, owner McpOps; a tool never sends it. McpOps validates the values.
Class OcuTalon.Msg.Command.SetSourcePoll Extends OcuTalon.Msg.Command
{

/// The server's name.
Property Server As %String(MAXLEN = 40);

/// The tool's name on that server.
Property Tool As %String(MAXLEN = 128);

/// The source's name as the admin sees it.
Property Name As %String(MAXLEN = 100);

/// The text of a JSON object: the arguments of each call.
Property Arguments As %String(MAXLEN = "");

/// Minutes between two calls.
Property IntervalMinutes As %Integer;

/// The IRIS user who asked; set by the submitting code from its authenticated context, never from an argument.
Property ActingUser As %String(MAXLEN = 160);

Storage Default
{
<Data name="SetSourcePollDefaultData">
<Subscript>"SetSourcePoll"</Subscript>
<Value name="1">
<Value>Server</Value>
</Value>
<Value name="2">
<Value>Tool</Value>
</Value>
<Value name="3">
<Value>Name</Value>
</Value>
<Value name="4">
<Value>Arguments</Value>
</Value>
<Value name="5">
<Value>IntervalMinutes</Value>
</Value>
<Value name="6">
<Value>ActingUser</Value>
</Value>
</Data>
<DefaultData>SetSourcePollDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
