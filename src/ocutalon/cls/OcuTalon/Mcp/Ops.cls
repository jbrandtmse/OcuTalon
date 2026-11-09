/// McpOps (AD-1, AD-21, AD-29, AD-33; Lane A): the operation that owns the MCP servers an admin registers. It is the only writer of OcuTalon.Mcp.Server
/// and of OcuTalon.Mcp.ToolClassification. It is not an item of the production yet (Story 22.2 adds it), so this class holds the two methods that
/// others already call:
///   - Tools: the tools of a server for Settings (Story 21.4). A stub until Story 22.2: any server name gives OK and an empty list.
///   - RecordAttach: writes what a runner reported about one attach (OcuTalon.Mcp.Attach.OnAttach) to the server's row: AttachStatus, AttachReason
///     (a code word of OcuTalon.Bridge.Ext.McpServers REASONS, anything else is stored as empty), AttachedAt (now, UTC, only when the server was
///     attached) and RefusedTools. A server with no row is an error and nothing is written. It writes the row only: it writes no Config Store
///     entry and no wallet secret (OcuTalon.Core.SettingsOps does, Story 35.2), sends no notification (Story 22.2 sends them from the row) and
///     stores no text from AI Hub.
Class OcuTalon.Mcp.Ops Extends Ens.BusinessOperation
{

/// The statuses of an attach that a row holds.
Parameter STATUSES = "attached,unavailable";

/// The tools of the server for Settings, as a %DynamicArray of {"name", "classification", "status"}. The stub gives an empty array for any server and OK.
ClassMethod Tools(server As %String, Output tools As %DynamicArray) As %Status
{
	Set tools = []
	Quit $$$OK
}

/// Writes the report of one attach ({"status", "reason", "tools", "refused"}, OcuTalon.Bridge.Ext.McpServers) to the row of the server.
ClassMethod RecordAttach(server As %String, report As %DynamicObject) As %Status
{
	If '$IsObject($Get(report)) Quit $$$ERROR($$$GeneralError, "The attach report is not an object")
	Set sc = $$$OK
	Lock +^OcuTalon.Mcp.Server(server):5
	If '$Test Quit $$$ERROR($$$GeneralError, "The MCP server "_server_" is busy, so its attach report was not recorded")
	Try {
		Set row = ##class(OcuTalon.Mcp.Server).NameIndexOpen(server, , .sc)
		If '$IsObject(row) {
			Set sc = $$$ERROR($$$GeneralError, "There is no MCP server named "_server_", so its attach report was not recorded")
		} Else {
			Set status = report.%Get("status")
			Set reason = report.%Get("reason")
			Set row.AttachStatus = $Select($ListFind($ListFromString(..#STATUSES), status): status, 1: "")
			Set row.AttachReason = $Select($ListFind($ListFromString(##class(OcuTalon.Bridge.Ext.McpServers).#REASONS), reason): reason, 1: "")
			If row.AttachStatus = "attached" Set row.AttachedAt = ##class(OcuTalon.Data.Time).NowUtc()
			Set row.RefusedTools = ..NamesOf(report.%Get("refused"))
			Set sc = row.%Save()
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Lock -^OcuTalon.Mcp.Server(server)
	Quit sc
}

/// The names in a %DynamicArray of strings as a list; anything else gives an empty list.
ClassMethod NamesOf(array As %DynamicArray) As %List [ Private ]
{
	Set names = ""
	If '$IsObject(array) || ('array.%IsA("%Library.DynamicArray")) Quit names
	Set iterator = array.%GetIterator()
	While iterator.%GetNext(, .name) {
		If '$IsObject(name) Set names = names _ $ListBuild(name)
	}
	Quit names
}

}
