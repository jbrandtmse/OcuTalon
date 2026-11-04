/// The classification extension of the gate tests (Story 3.2; AD-31): a test fixture, never part of a production. It gives safe for the MCP
/// tool zz_mcp_safe of the server mcp:zzserver; for zz_mcp_args of that server only when it is given arguments (the gate gives none); and for
/// zz_gate_risky and zz_gate_held of ZzGateTool and odd_param of ZzGateOdd, so that the tests show what it classifies (a tool that code and the
/// setting leave unclassified) and what it never changes (what code declares). Nothing for any other source and name. Test.Bridge.Gate names it in
/// the ClassificationClass setting of Decide for its own run.
Class OcuTalon.Test.Bridge.ZzGateClassification Extends OcuTalon.Bridge.Ext.Classification
{

ClassMethod Classify(source As %String, name As %String, arguments As %DynamicObject = "") As %String
{
	If (source = "mcp:zzserver") && (name = "zz_mcp_safe") Quit "safe"
	If (source = "mcp:zzserver") && (name = "zz_mcp_args") && $IsObject(arguments) Quit "safe"
	If $ListFind($ListBuild("OcuTalon.Test.Bridge.ZzGateTool:zz_gate_risky", "OcuTalon.Test.Bridge.ZzGateTool:zz_gate_held", "OcuTalon.Test.Bridge.ZzGateOdd:odd_param"), source_":"_name) Quit "safe"
	Quit ""
}

}
