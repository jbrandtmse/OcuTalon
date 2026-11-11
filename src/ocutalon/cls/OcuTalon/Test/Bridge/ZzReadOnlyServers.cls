/// The McpServersClass of the tests of Decide.ToolsReadOnly (Story 22.8; AD-8, AD-31, DW-724): a test fixture, never part of a production. Servers lists the
/// names in the process-private node ^||ZzReadOnlyServers("servers") (a JSON array of names) as {"server", "config"}, and ToolsReadOnly(server) answers the node
/// ^||ZzReadOnlyServers("ro", server). The node "mode" makes Servers misbehave: error (an error status), throw (an exception), text (a status OK and a text in
/// place of the array) or noname (an entry with no server name after the listed ones); the node "throws" names the server whose ToolsReadOnly throws.
Class OcuTalon.Test.Bridge.ZzReadOnlyServers Extends OcuTalon.Bridge.Ext.McpServers
{

ClassMethod Servers(Output servers As %DynamicArray) As %Status
{
	Set mode = $Get(^||ZzReadOnlyServers("mode"))
	If mode = "error" Quit $SYSTEM.Status.Error(5001, "ZzReadOnlyServers lists no server")
	If mode = "throw" $$$ThrowStatus($SYSTEM.Status.Error(5001, "ZzReadOnlyServers throws"))
	If mode = "text" {
		Set servers = "text"
		Quit $$$OK
	}
	Set servers = []
	Set names = $Get(^||ZzReadOnlyServers("servers"))
	If names '= "" {
		Set iterator = ##class(%DynamicAbstractObject).%FromJSON(names).%GetIterator()
		While iterator.%GetNext(, .name) {
			Do servers.%Push({"server": (name), "config": ("AI.MCP.OcuTalon_" _ name)})
		}
	}
	If mode = "noname" Do servers.%Push({"config": "AI.MCP.OcuTalon_zz"})
	Quit $$$OK
}

ClassMethod ToolsReadOnly(server As %String) As %Boolean
{
	If $Get(^||ZzReadOnlyServers("throws")) = server $$$ThrowStatus($SYSTEM.Status.Error(5001, "ZzReadOnlyServers throws for " _ server))
	Quit +$Get(^||ZzReadOnlyServers("ro", server))
}

}
