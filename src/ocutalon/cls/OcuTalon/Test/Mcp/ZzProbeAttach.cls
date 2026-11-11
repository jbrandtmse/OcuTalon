/// The McpServersClass of the attach tests that need to see the admin notices (Story 22.2; AD-31): a test fixture, never part of a production. It lists the
/// servers as OcuTalon.Mcp.Attach does and hands each report to OcuTalon.Test.Mcp.OpsProbe, which records the notices in process-private nodes instead of
/// sending them, so the build that the test makes in its own process leaves them where the test reads them.
Class OcuTalon.Test.Mcp.ZzProbeAttach Extends OcuTalon.Mcp.Attach
{

ClassMethod OnAttach(server As %String, report As %DynamicObject) As %Status
{
	Quit ##class(OcuTalon.Test.Mcp.OpsProbe).RecordAttach(server, report)
}

}
