/// The McpServersClass of the test of a proxy toolset that cannot be registered (Story 22.3): a test fixture, never part of a production. It is OcuTalon.Mcp.Attach, except that
/// ProxyToolSet names a class that does not exist, so the runner cannot register the proxy on the manager of a request that holds a server.
Class OcuTalon.Test.Mcp.ZzBrokenProxy Extends OcuTalon.Mcp.Attach
{

ClassMethod ProxyToolSet() As %String
{
	Quit "OcuTalon.Test.Mcp.ZzNoSuchToolSet"
}

}
