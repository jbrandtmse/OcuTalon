/// The classification extension of the gate tests (Story 3.2; AD-31): a test fixture, never part of a production. It gives safe for the MCP
/// tool zz_mcp_safe of the server mcp:zzserver, and nothing for any other source and name. Test.Bridge.Gate names it in the ClassificationClass
/// setting of Decide for its own run.
Class OcuTalon.Test.Bridge.ZzGateClassification Extends OcuTalon.Bridge.Ext.Classification
{

ClassMethod Classify(source As %String, name As %String, arguments As %DynamicObject = "") As %String
{
	Quit $Select((source = "mcp:zzserver") && (name = "zz_mcp_safe"): "safe", 1: "")
}

}
