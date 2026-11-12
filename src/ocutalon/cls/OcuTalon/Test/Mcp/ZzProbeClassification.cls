/// The ClassificationClass of the tests that read the admin notices of a changed MCP tool (Story 22.8; AD-10, AD-21): a test fixture, never part of a production.
/// It is OcuTalon.Mcp.Classification with one seam changed: the clear of a changed tool goes to OcuTalon.Test.Mcp.OpsProbe, which writes the row and the audit
/// entry as the real clear does and records the notices in process-private nodes instead of sending them, so a test that composes a turn and calls a tool in its
/// own process reads them where the runner's check and the gate left them. The comparison of the fingerprints is the real class's.
Class OcuTalon.Test.Mcp.ZzProbeClassification Extends OcuTalon.Mcp.Classification
{

/// While the node ^||ZzOps("classifyThrows") is set, the answer throws, so that a test sees what the runner's turn-start check does with a host class that fails.
ClassMethod ClassifyMcp(source As %String, name As %String, fingerprint As %String = "") As %DynamicObject
{
	If $Get(^||ZzOps("classifyThrows")) Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "The probe classification throws"))
	Quit ##super(source, name, fingerprint)
}

ClassMethod Clear(server As %String, name As %String, fingerprint As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Test.Mcp.OpsProbe).ClearChanged(server, name, fingerprint)
}

}
