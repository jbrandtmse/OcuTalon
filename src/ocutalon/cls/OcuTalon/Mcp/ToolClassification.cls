/// The classification of one tool of a registered MCP server (AD-10, AD-21, AD-33). Lane A. Written only by OcuTalon.Mcp.Ops (the sole writer of this
/// table and of Mcp.Server). One row for each tool that a server offers, keyed by the server's name and the tool's name:
///   - Classification is unclassified, read-only or risky; a new row is unclassified, which counts as risky.
///   - Fingerprint is the fingerprint (OcuTalon.Bridge.Context ToolFingerprint) that the last attach reported for the tool, or empty for a tool that
///     the server offers under the name of a built-in tool and so was refused. A classification holds for the fingerprint the row had when the
///     admin set it; a different reported fingerprint makes the row unclassified again.
///   - ChangedAt is when the row's classification last changed, UTC to the second.
/// The row holds no URL, no credential and no user name. It lives as long as its server, and a tool that the server stops offering loses its row at
/// the next attach.
Class OcuTalon.Mcp.ToolClassification Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.McpTool";

/// The classifications a row holds, comma-separated; OcuTalon.Mcp.Ops accepts these words and no other.
Parameter CLASSIFICATIONS = "unclassified,read-only,risky";

/// The name of the registered server (OcuTalon.Mcp.Server Name).
Property Server As %String(MAXLEN = 40) [ Required ];

/// The tool's name on that server. MCP tool names are case-sensitive, so the collation is EXACT: the unique index tells Foo from foo.
Property Tool As %String(COLLATION = "EXACT", MAXLEN = 128) [ Required ];

/// One of CLASSIFICATIONS.
Property Classification As %String(MAXLEN = 16, VALUELIST = ",unclassified,read-only,risky") [ InitialExpression = "unclassified", Required ];

/// The fingerprint the last attach reported for the tool, or empty.
Property Fingerprint As %String(MAXLEN = 64);

/// When the classification last changed, UTC to the second (YYYY-MM-DDThh:mm:ssZ).
Property ChangedAt As %String(MAXLEN = 20);

Index ServerToolIndex On (Server, Tool) [ Unique ];

Storage Default
{
<Data name="ToolClassificationDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Server</Value>
</Value>
<Value name="3">
<Value>Tool</Value>
</Value>
<Value name="4">
<Value>Classification</Value>
</Value>
<Value name="5">
<Value>Fingerprint</Value>
</Value>
<Value name="6">
<Value>ChangedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.McpToolD</DataLocation>
<DefaultData>ToolClassificationDefaultData</DefaultData>
<IdLocation>^OcuTalonP.McpToolD</IdLocation>
<IndexLocation>^OcuTalonP.McpToolI</IndexLocation>
<StreamLocation>^OcuTalonP.McpToolS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
