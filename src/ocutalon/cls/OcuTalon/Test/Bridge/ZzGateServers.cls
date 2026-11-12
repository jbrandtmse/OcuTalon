/// The McpServersClass of the gate tests that need a host with a governed proxy (Story 22.3; AD-31): a test fixture, never part of a production. It lists no server
/// and offers OcuTalon.Tools.McpProxy as its proxy toolset, so that the gate rewrites an allowed native MCP call into a call of the proxy. Test.Bridge.Gate names it in the
/// McpServersClass setting of Decide for its own run. Its ServerOf (Story 22.4) names the server zzserver for the toolref mcp:zzserver and no server for any other.
Class OcuTalon.Test.Bridge.ZzGateServers Extends OcuTalon.Bridge.Ext.McpServers
{

ClassMethod ProxyToolSet() As %String
{
	Quit "OcuTalon.Tools.McpProxy"
}

ClassMethod ServerOf(toolref As %String) As %String
{
	Quit $Select(toolref = "mcp:zzserver": "zzserver", 1: "")
}

}
