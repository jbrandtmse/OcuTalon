/// The MCP servers class of OcuTalon (AD-21, AD-31): names the registered servers to the runners and takes each runner's attach report. It is the value of
/// the McpServersClass setting of the Decide item in OcuTalon.Production.
///   - Servers: one {"server", "config"} for each row of OcuTalon.Mcp.Server in the order of the names, the config being AI.MCP.OcuTalon_<Name>. The
///     row holds no URL and no credential: the Config Store entry does.
///   - OnAttach: hands the report ({"status", "reason", "tools", "refused"} and, for an attached server, "fingerprints": each listed tool's name to its
///     fingerprint) to OcuTalon.Mcp.Ops.RecordAttach, which writes the server's row and its tool rows and sends the admin notices. RecordAttach
///     looks up the administrators' sessions through OcuTalon.Data.Ownership AdminSessions to address the notices. OnAttach itself does nothing else.
///   - ToolsReadOnly: 1 only when the row's last attach was attached and every tool row of the server that is not in the row's RefusedTools (a refused tool never
///     runs) is classified read-only; an attached server with no such row counts as 1. A server whose last attach was unavailable or never happened, a server with no
///     row, an empty name and any error count as 0. It reads and writes nothing else (DW-724).
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
	While result.%Next(.sc) {
		Do servers.%Push({"server": (result.%Get("Name")), "config": ("AI.MCP."_..#ENTRYPREFIX_result.%Get("Name"))})
	}
	Quit sc
}

ClassMethod OnAttach(server As %String, report As %DynamicObject) As %Status
{
	Quit ##class(OcuTalon.Mcp.Ops).RecordAttach(server, report)
}

ClassMethod ToolsReadOnly(server As %String) As %Boolean
{
	Try {
		If '$Match(server, ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) Return 0
		Set row = ##class(OcuTalon.Mcp.Server).NameIndexOpen(server)
		If '$IsObject(row) || (row.AttachStatus '= "attached") Return 0
		Set refused = row.RefusedTools
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("SELECT Tool, Classification FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?")
		If $$$ISERR(sc) Return 0
		Set result = statement.%Execute(server)
		If result.%SQLCODE < 0 Return 0
		While result.%Next(.sc) {
			If $ListFind(refused, result.%Get("Tool")) Continue
			If result.%Get("Classification") '= "read-only" Return 0
		}
		Return $$$ISOK(sc)
	} Catch {
	}
	Quit 0
}

}
