/// A registered MCP server (AD-21, AD-33). Lane A. Written only by OcuTalon.Mcp.Ops (the sole writer of this table and of Mcp.ToolClassification). The row
/// holds the server's name and what a runner reported when it last attached the server (AttachStatus, AttachReason, AttachedAt, RefusedTools), which
/// Settings shows and the admin notices of Story 22.2 read. It holds no URL and no credential: the server's Config Store entry AI.MCP.OcuTalon_<Name>
/// holds the URL and a secret:// reference to the wallet (AD-19, AD-21), and the attach report holds code words and tool names only.
Class OcuTalon.Mcp.Server Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.McpServer";

/// The pattern of a server's name: a letter, then up to 39 letters, digits or underscores, so that AI.MCP.OcuTalon_<Name> is a Config Store name.
Parameter NAMEPATTERN = "^[A-Za-z][A-Za-z0-9_]{0,39}$";

/// The server's name, the <server> of the Config Store entry AI.MCP.OcuTalon_<server>.
Property Name As %String(MAXLEN = 40) [ Required ];

/// When the server was registered, UTC to the second (YYYY-MM-DDThh:mm:ssZ).
Property CreatedAt As %String(MAXLEN = 20);

/// What the last attach reported: attached or unavailable. Empty before the first runner build after the server was registered.
Property AttachStatus As %String(MAXLEN = 16);

/// Why the last attach was unavailable: a word the bridge writes (unreachable, failed or invalid), never AI Hub's text. Empty for an attached server.
Property AttachReason As %String(MAXLEN = 16);

/// When the last attach of a server that was attached finished, UTC to the second.
Property AttachedAt As %String(MAXLEN = 20);

/// The names of the server's tools that were refused at the last attach because a tool of that name was already on the agent's manager.
Property RefusedTools As %List;

Index NameIndex On Name [ Unique ];

/// A name that does not match NAMEPATTERN is refused.
Method %OnValidateObject() As %Status
{
	If '$Match(..Name, ..#NAMEPATTERN) Quit $$$ERROR($$$GeneralError, "An MCP server name is a letter followed by up to 39 letters, digits or underscores")
	Quit $$$OK
}

Storage Default
{
<Data name="ServerDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Name</Value>
</Value>
<Value name="3">
<Value>CreatedAt</Value>
</Value>
<Value name="4">
<Value>AttachStatus</Value>
</Value>
<Value name="5">
<Value>AttachReason</Value>
</Value>
<Value name="6">
<Value>AttachedAt</Value>
</Value>
<Value name="7">
<Value>RefusedTools</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.McpServerD</DataLocation>
<DefaultData>ServerDefaultData</DefaultData>
<IdLocation>^OcuTalonP.McpServerD</IdLocation>
<IndexLocation>^OcuTalonP.McpServerI</IndexLocation>
<StreamLocation>^OcuTalonP.McpServerS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
