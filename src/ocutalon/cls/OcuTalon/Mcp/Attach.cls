/// The MCP servers class of OcuTalon (AD-21, AD-31): names the registered servers to the runners and takes each runner's attach report. It is the value of
/// the McpServersClass setting of the Decide item in OcuTalon.Production.
///   - Servers: one {"server", "config"} for each row of OcuTalon.Mcp.Server in the order of the names, the config being AI.MCP.OcuTalon_<Name>. The
///     row holds no URL and no credential: the Config Store entry does. On the online demo (Mcp.Proxy OnlineDemo) it lists no server, whatever rows exist, so
///     no runner attaches, probes, lists or offers an MCP server there (AD-25).
///   - OnAttach: hands the report ({"status", "reason", "tools", "refused"} and, for an attached server, "fingerprints": each listed tool's name to its
///     fingerprint) to OcuTalon.Mcp.Ops.RecordAttach, which writes the server's row and its tool rows and sends the admin notices. RecordAttach
///     looks up the administrators' sessions through OcuTalon.Data.Ownership AdminSessions to address the notices. OnAttach itself does nothing else.
///   - Probe: the entry's url, read through OcuTalon.Bridge.ConfigStore Details (which resolves no placeholder and no secret), goes to OcuTalon.Mcp.Client
///     Probe, an unauthenticated initialize with a 2 second limit. A server whose entry or url is missing counts as failed. Nothing else is read or written, and
///     no url, secret or error text is returned: the answer is "" or a code word.
///   - ProxyToolSet: OcuTalon.Tools.McpProxy, the toolset of the governed proxy call_mcp_tool (Story 22.3), which the runner registers on the tool manager of a request that holds
///     an MCP server; "" on the online demo, where no MCP server runs and the proxy is never offered.
///   - ServerOf and Toolref (Story 22.4): the toolref of a server's entry is exactly mcp:remote:@{config:AI.MCP.OcuTalon_<name>}, the form that the runner attaches. ServerOf gives
///     the name for exactly that form with a name that matches OcuTalon.Mcp.Server NAMEPATTERN, and "" for any other text; Toolref is its inverse and gives "" for a name that
///     does not match the pattern.
///   - ToolsReadOnly: 1 only when the row's last attach was attached and every tool row of the server that is not in the row's RefusedTools (a refused tool never
///     runs) is classified read-only; an attached server with no such row counts as 1. A server whose last attach was unavailable or never happened, a server with no
///     row, an empty name and any error count as 0. It reads and writes nothing else (DW-724).
///   - PollCall (Story 22.11): prepares the call of the source whose Ref is given, from the source's own row, in this order: the row must exist, be of Kind source and hold arguments that are a JSON object or none (else invalid); the
///     tool's OcuTalon.Mcp.ToolClassification row must exist (else notfound) and be read-only (else notreadonly); Mcp.Proxy Listed gives the live toolref and fingerprint, or its word; and
///     the live fingerprint must be the row's (else changed). The arguments are the row's alone. It answers "" with every output set, or one word of POLLREASONS with every output empty.
Class OcuTalon.Mcp.Attach Extends OcuTalon.Bridge.Ext.McpServers
{

/// The prefix of a server's Config Store entry, after AI.MCP.
Parameter ENTRYPREFIX = "OcuTalon_";

/// The start and the end of a server's toolref around ENTRYPREFIX and the name: mcp:remote:@{config:AI.MCP.OcuTalon_<name>}.
Parameter TOOLREFSTART = "mcp:remote:@{config:AI.MCP.";

Parameter TOOLREFEND = "}";

ClassMethod Servers(Output servers As %DynamicArray) As %Status
{
	Set servers = []
	If ##class(OcuTalon.Mcp.Proxy).OnlineDemo() Quit $$$OK
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

ClassMethod Probe(server As %String, config As %String) As %String
{
	Set answer = "failed"
	Try {
		Set sc = ##class(OcuTalon.Bridge.ConfigStore).Details($Get(config), .details)
		If $$$ISOK(sc) && $IsObject(details) && (details.%GetTypeOf("url") = "string") {
			Set answer = ##class(OcuTalon.Mcp.Client).Probe(details.url)
		}
	} Catch {
		Set answer = "failed"
	}
	Quit answer
}

ClassMethod OnAttach(server As %String, report As %DynamicObject) As %Status
{
	Quit ##class(OcuTalon.Mcp.Ops).RecordAttach(server, report)
}

ClassMethod ProxyToolSet() As %String
{
	Quit $Select(##class(OcuTalon.Mcp.Proxy).OnlineDemo(): "", 1: "OcuTalon.Tools.McpProxy")
}

ClassMethod ServerOf(toolref As %String) As %String
{
	Set prefix = ..#TOOLREFSTART _ ..#ENTRYPREFIX
	Set suffix = ..#TOOLREFEND
	If $IsObject($Get(toolref)) || ($Extract(toolref, 1, $Length(prefix)) '= prefix) || ($Extract(toolref, *-$Length(suffix) + 1, *) '= suffix) Quit ""
	Set name = $Extract(toolref, $Length(prefix) + 1, *-$Length(suffix))
	Quit $Select($Match(name, ##class(OcuTalon.Mcp.Server).#NAMEPATTERN): name, 1: "")
}

ClassMethod Toolref(server As %String) As %String
{
	If $IsObject($Get(server)) || '$Match($Get(server), ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) Quit ""
	Quit ..#TOOLREFSTART _ ..#ENTRYPREFIX _ server _ ..#TOOLREFEND
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

ClassMethod PollCall(source As %String, Output server As %String, Output tool As %String, Output arguments As %DynamicObject, Output toolref As %String, Output fingerprint As %String) As %String
{
	Set server = ""
	Set tool = ""
	Set arguments = ""
	Set toolref = ""
	Set fingerprint = ""
	Set word = "invalid"
	Try {
		Set row = $Select($Match($Get(source), "^[A-Za-z0-9_-]{22}$"): ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(source), 1: "")
		If '$IsObject(row) || (row.Kind '= ##class(OcuTalon.Watch.Ops).#SOURCEKIND) Return "invalid"
		Set live = row.Server
		Set name = row.Tool
		Set object = $Select($ZStrip(row.Arguments, "*WC") = "": {}, 1: {}.%FromJSON(row.Arguments))
		If '$IsObject(object) || 'object.%IsA("%Library.DynamicObject") Return "invalid"
		Set classified = $Select($Match(live, ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) && (name '= ""): ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(live, name), 1: "")
		If '$IsObject(classified) Return "notfound"
		If classified.Classification '= "read-only" Return "notreadonly"
		Set word = ##class(OcuTalon.Mcp.Proxy).Listed(live, name, .listedRef, .listedFingerprint)
		If word '= "" Return word
		If listedFingerprint '= classified.Fingerprint Return "changed"
		Set server = live
		Set tool = name
		Set arguments = object
		Set toolref = listedRef
		Set fingerprint = listedFingerprint
		Set word = ""
	} Catch {
		Set word = "invalid"
	}
	If word '= "" {
		Set server = ""
		Set tool = ""
		Set arguments = ""
		Set toolref = ""
		Set fingerprint = ""
	}
	Quit word
}

}
