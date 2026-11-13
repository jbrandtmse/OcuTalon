/// The bridge's tool classification extension (AD-31): resolves the classification of a tool beyond what code and
/// settings say. The default resolves nothing, so the bridge runs alone (FR-5). A host extends this class and names
/// the subclass in the ClassificationClass setting of the Decide item. The gate asks it last for a tool of a class
/// source (after the code of the class and the ToolClassification setting), and first and alone for an MCP tool, whose source is
/// the toolref that starts with mcp: (AD-10).
///   - Classify answers by source and name alone, for a class source (and, in the default ClassifyMcp, for an MCP tool).
///   - ClassifyMcp is the one question the gate asks for an MCP tool (AD-10, AD-31): it answers the classification, the read-only flag and whether the tool's
///     server is registered together, so that a change between two questions cannot mix them. fingerprint is the fingerprint that the turn's map holds for the
///     tool (OcuTalon.Bridge.Context McpFingerprint), "" when the map has none. The default delegates to Classify and never says that a server is unregistered,
///     so the bridge runs alone.
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

/// The answer for an MCP call, as {"classification": "safe", "risky" or "", "readOnly": 1 or 0, "registered": 1 or 0}, or "" for none:
///   - classification and readOnly are the tool's classification (any other value counts as none), and readOnly 1 counts only with safe;
///   - registered 0 says that the tool's server is not registered, and the gate denies the call at once (UNREGISTERED), before any other step.
/// source is the toolref of the MCP tool, name the tool's name and fingerprint the turn's fingerprint for the tool. A host that keeps a classification
/// for the fingerprint it was given for answers none for a fingerprint that differs, and may clear that classification from here (a changed tool, AD-21).
/// The gate calls this method inside AI Hub's authorization callback, and the runner calls it once for each MCP tool when a request composes its tools, outside
/// every callback: it makes no AI Hub call and runs no Python (AD-6). Returns the answer of Classify, with readOnly 0 and registered 1, by default.
ClassMethod ClassifyMcp(source As %String, name As %String, fingerprint As %String = "") As %DynamicObject
{
	Quit {"classification": (..Classify(source, name)), "readOnly": 0, "registered": 1}
}

}
