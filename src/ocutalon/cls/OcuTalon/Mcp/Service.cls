/// OcuTalon's own MCP server (Story 28.3; AD-1, AD-4, AD-10, AD-17, AD-21, AD-24): the web service at /mcp/ocutalon that offers a developer's own MCP client the read-only tools of
/// OcuTalon.Mcp.ServiceTools, and nothing else. It extends %AI.MCP.Service, whose dispatcher answers 401 to an anonymous caller or a wrong password and, with RESOURCE set, 403 to
/// a caller without the Use permission on that resource, and which serves tools only to the MCP gateway (every other authenticated request is 502 GATEWAY_REQUIRED).
///   - Read-only by construction (R-28.3-1): SPECIFICATION is the one toolset OcuTalon.Mcp.ServiceTools, whose tools are methods of OcuTalon.Mcp.ServiceRead only. ReadOnlyProblem checks
///     every tool of the specification through the readers that the gate uses (StepBuffer ToolParameter, Gate HookFor) and OnAuthenticate refuses every request, discovery and calls,
///     while it is not "". The service never begins a bridge context, so no tool can submit a command, and the role that serves a call holds read permission on the databases and
///     never write permission.
///   - Owners never mix (R-28.3-2): a served tool's owner is the session of the calling IRIS user, found by OwnerOf, which never creates a session.
///   - Off on the online demo (R-28.3-3): OnlineDemo is the installer's own seam, and OnAuthenticate refuses every request there.
///   - Served writes the one IRIS audit entry of a served call (type MCP, change served, server SERVERNAME, the tool, one outcome word, the caller, the session Ref and channel CHANNEL),
///     through OcuTalon.Bridge.Audit. It holds no argument, result or text.
Class OcuTalon.Mcp.Service Extends %AI.MCP.Service [ DependsOn = (OcuTalon.Mcp.ServiceTools, OcuTalon.Bridge.Audit) ]
{

Parameter SPECIFICATION = "OcuTalon.Mcp.ServiceTools";

/// The resource that a caller needs Use on; it is the one that Install.Step.Mcp creates (SERVICERESOURCE, pinned by a test).
Parameter RESOURCE = "OcuTalon_MCPServer";

/// The server name of the audit entries and the channel of the served calls.
Parameter SERVERNAME = "ocutalon";

Parameter CHANNEL = {##class(OcuTalon.Bridge.Audit).#MCPCHANNEL};

/// The package of the only classes whose methods may be offered as tools.
Parameter PROVIDERPACKAGE = "OcuTalon.Mcp.";

/// What the service says on the online demo.
Parameter DEMOOFF = "OcuTalon's MCP server is off on the online demo.";

/// Refuses every request on the online demo and while any tool of the specification is not offered read-only (ReadOnlyProblem); otherwise lets the request through.
ClassMethod OnAuthenticate(authType As %String, auth As %String, headers As %DynamicObject = "") As %Status
{
	If ..OnlineDemo() Quit $SYSTEM.Status.Error(5001, ..#DEMOOFF)
	Set problem = ..ReadOnlyProblem()
	If problem '= "" Quit $SYSTEM.Status.Error(5001, problem)
	Quit $SYSTEM.Status.OK()
}

/// 1 on an online-demo install (the public setting onlineDemo, which the installer writes and the service's role can read).
ClassMethod OnlineDemo() As %Boolean
{
	Quit +##class(OcuTalon.Data.Public.Settings).Get("onlineDemo") = 1
}

/// "" when every tool of the specification (a comma list of toolset classes) is a method of a class in PROVIDERPACKAGE that the gate's readers classify exactly safe and
/// read-only (READONLY exactly 1) with no Classify or Hold hook; otherwise the sentences that name every tool that is not (or the one that says a toolset could not be read),
/// then that no tool is offered.
ClassMethod ReadOnlyProblem(specification As %String = {..GetSpecification()}) As %String
{
	Set problem = ""
	Try {
		For i = 1:1:$Length(specification, ",") {
			Set toolset = $ZStrip($Piece(specification, ",", i), "<>W")
			If toolset = "" Continue
			Set tools = $ClassMethod(toolset, "%New").%Discover().tools
			Set iterator = tools.%GetIterator()
			While iterator.%GetNext(, .tool) {
				Set one = ..ToolProblem(tool.provider, tool.name)
				If one '= "" Set problem = problem _ $Select(problem = "": "", 1: " ") _ one
			}
		}
	} Catch exception {
		Set problem = "A toolset of the specification could not be read."
	}
	Quit $Select(problem = "": "", 1: problem _ " No tool is offered.")
}

/// "" when the tool of the provider class is offered read-only, otherwise the sentence that says why not.
ClassMethod ToolProblem(provider As %String, name As %String) As %String
{
	Set buffer = "OcuTalon.Bridge.Adapter.StepBuffer"
	Set gate = "OcuTalon.Bridge.Policy.Gate"
	Set reason = ""
	If $Extract(provider, 1, $Length(..#PROVIDERPACKAGE)) '= ..#PROVIDERPACKAGE {
		Set reason = "is not a method of a class in " _ ..#PROVIDERPACKAGE
	} ElseIf $ClassMethod(buffer, "ToolParameter", provider, name, "CLASSIFICATION") '= "safe" {
		Set reason = "is not classified safe"
	} ElseIf $ClassMethod(buffer, "ToolParameter", provider, name, "READONLY") '= 1 {
		Set reason = "is not read-only"
	} ElseIf ($ClassMethod(gate, "HookFor", provider, name, "Classify") '= "") || ($ClassMethod(gate, "HookFor", provider, name, "Hold") '= "") {
		Set reason = "is classified or held by its arguments"
	}
	Quit $Select(reason = "": "", 1: "The tool " _ name _ " " _ reason _ ".")
}

/// The Ref of the OcuTalon session of the IRIS user, or "" when the user has none or the lookup failed (sc is then an error). It never creates a session: it is the lookup of
/// Data.Session ForUser without the create, prepared without the privilege check because the caller holds no SQL privilege on the table.
ClassMethod OwnerOf(irisUser As %String, Output sc As %Status) As %String
{
	Set sc = $SYSTEM.Status.OK()
	Set ref = ""
	If $Get(irisUser) = "" Quit ""
	Try {
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("SELECT TOP 1 Ref FROM OcuTalon_Data.Session WHERE IrisUser = ? ORDER BY ID", 0)
		If $$$ISOK(sc) {
			Set result = statement.%Execute(irisUser)
			If result.%SQLCODE < 0 {
				Set sc = $SYSTEM.Status.Error(5001, "The session lookup failed")
			} ElseIf result.%Next() {
				Set ref = result.%Get("Ref")
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
		Set ref = ""
	}
	If $$$ISERR(sc) Quit ""
	Quit ref
}

/// Writes the audit entry of one served call (see the class description): the tool, the outcome word (ok, demo, nosession or notread), the session Ref of the owner (or "") and the
/// calling IRIS user. The status is the audit writer's; an exception is an error status.
ClassMethod Served(tool As %String, outcome As %String, sessionRef As %String, irisUser As %String) As %Status
{
	Try {
		Set data = {}
		Do data.%Set("change", "served", "string")
		Do data.%Set("server", ..#SERVERNAME, "string")
		Do data.%Set("tool", tool, "string")
		Do data.%Set("outcome", outcome, "string")
		Do data.%Set("irisUser", irisUser, "string")
		Do data.%Set("sessionRef", sessionRef, "string")
		Do data.%Set("channel", ..#CHANNEL, "string")
		Set sc = ##class(OcuTalon.Bridge.Audit).Record("MCP", data)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

}
