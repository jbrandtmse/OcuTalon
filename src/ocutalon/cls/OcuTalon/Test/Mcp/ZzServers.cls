/// The McpServersClass of the attach tests that need to choose the servers and see the reports (Story 35.1; AD-31): a test fixture, never part of a
/// production. Servers gives the servers that ^||ZzMcp("servers") holds as JSON text (a failing Servers when ^||ZzMcp("servers", "fail") is 1, and a Servers that throws when it is 2), and OnAttach notes
/// each report in ^||ZzMcp("report", n) as "<server>|<report as JSON>" and then answers by ^||ZzMcp("mode"): "error" returns an error status, "throw" throws, and
/// anything else returns OK. Probe gives "" (no probe) unless ^||ZzMcp("probe") is set, when it counts the call in ^||ZzMcp("probes") and, by the value, delegates to
/// OcuTalon.Mcp.Attach Probe (1), throws (2), gives a word that is not a reason (3) or answers "" without asking the server (4) (Story 22.9), so that a test can see how often
/// the runner asks and what it does with each kind of answer. The nodes are process-private, so the class serves the build that the test makes in its own process.
Class OcuTalon.Test.Mcp.ZzServers Extends OcuTalon.Bridge.Ext.McpServers
{

ClassMethod Servers(Output servers As %DynamicArray) As %Status
{
	Set servers = []
	If $Get(^||ZzMcp("servers", "fail")) = 2 Throw ##class(%Exception.General).%New("ZzServers", 5002, , "ZzServers throws on purpose")
	If $Get(^||ZzMcp("servers", "fail")) = 1 Quit $$$ERROR($$$GeneralError, "ZzServers fails on purpose")
	If $Get(^||ZzMcp("servers")) '= "" Set servers = ##class(%DynamicAbstractObject).%FromJSON(^||ZzMcp("servers"))
	Quit $$$OK
}

ClassMethod Probe(server As %String, config As %String) As %String
{
	Set mode = +$Get(^||ZzMcp("probe"))
	If 'mode Quit ""
	Set ^||ZzMcp("probes") = $Get(^||ZzMcp("probes")) + 1
	If mode = 2 Throw ##class(%Exception.General).%New("ZzProbeThrows")
	If mode = 3 Quit "bogus"
	If mode = 4 Quit ""
	Quit ##class(OcuTalon.Mcp.Attach).Probe(server, config)
}

ClassMethod OnAttach(server As %String, report As %DynamicObject) As %Status
{
	Set n = $Increment(^||ZzMcp("report"))
	Set ^||ZzMcp("report", n) = server _ "|" _ report.%ToJSON()
	Set mode = $Get(^||ZzMcp("mode"))
	If mode = "error" Quit $$$ERROR($$$GeneralError, "ZzServers refuses the report on purpose")
	If mode = "throw" Throw ##class(%Exception.General).%New("ZzServers", 5001, , "ZzServers throws on purpose")
	Quit $$$OK
}

}
