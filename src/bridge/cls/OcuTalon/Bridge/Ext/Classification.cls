/// The bridge's tool classification extension (AD-31): resolves the classification of a tool beyond what code and
/// settings say. The default resolves nothing, so the bridge runs alone (FR-5). A host extends this class and names
/// the subclass in the ClassificationClass setting of the Decide item.
Class OcuTalon.Bridge.Ext.Classification
{

/// The classification of the tool call, or "" when this extension has none. Returns "" by default.
ClassMethod Classify(tool As %String, arguments As %DynamicObject = "") As %String
{
	Quit ""
}

}
