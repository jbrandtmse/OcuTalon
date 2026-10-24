/// The bridge's tool classification extension (AD-31): resolves the classification of a tool beyond what code and
/// settings say. The default resolves nothing, so the bridge runs alone (FR-5). A host extends this class and names
/// the subclass in the ClassificationClass setting of the Decide item. The gate asks it last for a tool of a class
/// source (after the code of the class and the ToolClassification setting), and first and alone for an MCP tool, whose source is
/// the toolref that starts with mcp: (AD-10).
Class OcuTalon.Bridge.Ext.Classification
{

/// The classification of the tool call: safe or risky, or "" when this extension has none (any other value counts as none). source is the
/// implementing class of a built-in or developer tool, or the toolref of an MCP tool (mcp:<server>); name is the tool's name; arguments is the
/// call's arguments, or "" when the caller has none. The gate always passes none: a call's content classifies nothing except through the Classify
/// method of the tool's own class, so an extension classifies by source and name alone. The source lets an extension keep an MCP tool off a
/// built-in's classification. The gate calls this method inside AI Hub's authorization callback, so it makes no AI Hub call and runs no Python
/// (AD-6). Returns "" by default.
ClassMethod Classify(source As %String, name As %String, arguments As %DynamicObject = "") As %String
{
	Quit ""
}

}
