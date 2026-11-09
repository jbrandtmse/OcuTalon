/// The MCP servers class of OcuTalon (AD-21, AD-31): names the registered servers to the runners and takes each runner's attach report. It is the value of
/// the McpServersClass setting of the Decide item in OcuTalon.Production.
///   - Servers: one {"server", "config"} for each row of OcuTalon.Mcp.Server in the order of the names, the config being AI.MCP.OcuTalon_<Name>. The
///     row holds no URL and no credential: the Config Store entry does.
///   - OnAttach: hands the report to OcuTalon.Mcp.Ops.RecordAttach, which writes the server's row. Nothing else: no notification, no look-up of an
///     administrator and no read outside this namespace (Story 22.2 sends the admin notices from the row).
Class OcuTalon.Mcp.Attach Extends OcuTalon.Bridge.Ext.McpServers
{

/// The prefix of a server's Config Store entry, after AI.MCP.
Parameter ENTRYPREFIX = "OcuTalon_";

ClassMethod Servers(Output servers As %DynamicArray) As %Status
{
	Set servers = []
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT Name FROM OcuTalon_Mcp.Server ORDER BY Name")
	If $$$ISERR(sc) Quit sc
	Set result = statement.%Execute()
	If result.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, result.%SQLCODE, result.%Message)
	While result.%Next() {
		Do servers.%Push({"server": (result.%Get("Name")), "config": ("AI.MCP."_..#ENTRYPREFIX_result.%Get("Name"))})
	}
	Quit $$$OK
}

ClassMethod OnAttach(server As %String, report As %DynamicObject) As %Status
{
	Quit ##class(OcuTalon.Mcp.Ops).RecordAttach(server, report)
}

}
