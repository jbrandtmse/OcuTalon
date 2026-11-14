/// The MCP settings routes of Settings > Tools and MCP servers (Story 21.4; AD-1, AD-13, AD-19, AD-21), forwarded from OcuTalon.Web.Api's URL map
/// (<Map Prefix="/v1/settings/mcp">). Admin only: Api's OnPreDispatch refuses a signed-in user without OcuTalonAdmin with 403 not_admin before the forward, and every route
/// checks it again. MCP servers are instance settings, so no route reads or writes a table, a wallet or a Config Store entry: every change is a command submitted with
/// origin web_admin that McpOps carries out, and the list is a command that SettingsOps answers in its own job.
///   - GET /v1/settings/mcp answers 200 {"servers":[{name, address, status, tools, unclassified, pending}], "tools":[{server, name, classification, status}]} from one
///     ListMcpServers: no secret, no secret:// reference and no fingerprint. A read that fails is 500 server_error.
///   - POST /v1/settings/mcp/servers takes exactly {"name": string, "address": string} and an optional "secret": a string. It answers 200 {"result":"added","message"}. A body of
///     another shape is 400 bad_mcp_server with fields {}. Each value is checked before anything is put into the handoff: the name against Mcp.Server NAMEPATTERN, the address
///     against Mcp.Ops AddressAllowed (an http:// address to another computer is refused, with or without a secret) and for a ? or a # (a query string or a fragment: Mcp.Ops MESSAGEQUERY), any @{ in a value, and the secret (1 to 4,096 printable
///     ASCII characters, no space), and a refusal is 400 bad_mcp_server with fields {name, address, secret} (each the field's text) and nothing is offered, submitted or written. A name that
///     exists, and a value that McpOps refuses itself, are the same 400, mapped to their field.
///   - DELETE /v1/settings/mcp/servers/<server> answers 200 {"result":"removed","message"}; a name that no server has is 404 not_found.
///   - POST /v1/settings/mcp/classify takes exactly {"server", "tool", "classification"}, all strings, and answers 200 {"result":"saved","message"}; a classification that is not
///     unclassified, read-only or risky, and a body of another shape, are 400 bad_classification, and a server or tool that does not exist is 404 not_found.
///   - POST /v1/settings/mcp/sources (Story 21.5) takes exactly {"server", "tool", "name", "arguments", "intervalMinutes"}: four strings and a whole number. It submits one SetSourcePoll and
///     answers 200 {"result":"saved","message","ref"}; saving a name again updates its source. A body of another shape is 400 bad_source with fields {}; an @{ in the name or the arguments
///     is 400 bad_source with that field's settings.refusedExpansion; arguments that are not "" or the text of a JSON object are 400 bad_source with {arguments: settings.sourceBadArguments};
///     nothing is submitted. A name of more than Mcp.Ops NAMEMAX characters (after its edge spaces are stripped, as McpOps does) is 400 bad_source with {name: Mcp.Ops MESSAGESOURCENAME}, since the command
///     cannot hold it. McpOps judges the rest (a tool that is not Read-only, a blank name, the interval, the arguments' size and secret://) and its message is relayed in 400
///     bad_source with the field {tool}, {name}, {intervalMinutes} or {arguments}; a server or tool that does not exist is 404 not_found.
///   - DELETE /v1/settings/mcp/sources/<ref> submits one RemoveSourcePoll and answers 200 {"result":"removed","message"}; a Ref that is not a source row of the caller's own session
///     (another session's, another kind's, an unknown one) is 404 not_found and nothing is submitted.
///   - GET also lists the caller's own session's sources in "sources" ([{ref, name, server, tool, intervalMinutes}], by name, never the arguments).
///   - On the online demo every route answers 409 not_available with the text settings.mcpOffOnDemo, before anything is read, offered or submitted.
/// A server's secret reaches McpOps only through OcuTalon.Core.SecretHandoff (Api HandOff): put before the command is submitted, discarded on every path after it, an error
/// included. The command holds the handoff uri and no secret, and no answer, log line or audit entry holds the secret. Any other outcome, an error status and an exception
/// are 500 server_error.
Class OcuTalon.Web.McpSettings Extends OcuTalon.Web.Api
{

/// The longest address that the route hands on (the command's Url).
Parameter ADDRESSMAX = 2000;

/// The longest secret that the route hands on.
Parameter SECRETMAX = 4096;

/// The longest tool name that a classification can name (the command's Tool).
Parameter TOOLMAX = 128;

Parameter MESSAGESECRET = "Use a secret of up to 4,096 letters, digits and punctuation, with no spaces. Nothing was changed.";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="" Method="GET" Call="List"/>
<Route Url="/servers" Method="POST" Call="Add"/>
<Route Url="/servers/:server" Method="DELETE" Call="Remove"/>
<Route Url="/classify" Method="POST" Call="Classify"/>
<Route Url="/sources" Method="POST" Call="SetSource"/>
<Route Url="/sources/:ref" Method="DELETE" Call="RemoveSource"/>
</Routes>
}

/// 1 when the online-demo flag is set. A test subclass overrides it.
ClassMethod OnlineDemo() As %Boolean [ Private ]
{
	Quit (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
}

/// "" when the route may run, else the refusal that has been written: 403 not_admin for a user without OcuTalonAdmin, 409 not_available on the online demo.
ClassMethod Refusal() As %Status [ Private ]
{
	If '..IsAdmin() Quit ..Fail(403, "not_admin", ..#MESSAGENOTADMIN)
	If ..OnlineDemo() Quit ..Fail(409, "not_available", ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.mcpOffOnDemo"))
	Quit ""
}

/// GET /v1/settings/mcp: see the class description.
ClassMethod List() As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	Set command = ##class(OcuTalon.Msg.Command.ListMcpServers).%New()
	Set command.ActingUser = $Username
	Set sc = ..Context(command)
	If $SYSTEM.Status.IsOK(sc) Set sc = ..HandOff(command, , .result, 1)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Quit ..Answer(result, "list")
}

/// POST /v1/settings/mcp/servers: see the class description.
ClassMethod Add() As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	If '..SettingsBody(.body) Quit ..BadServer({})
	Set size = body.%Size()
	If (size < 2) || (size > 3) || (body.%GetTypeOf("name") '= "string") || (body.%GetTypeOf("address") '= "string") || ((size = 3) && 'body.%IsDefined("secret")) Quit ..BadServer({})
	Set secret = $Select(body.%IsDefined("secret"): body.secret, 1: "")
	Set fields = ..AddFields(body.name, body.address, $Select(body.%IsDefined("secret"): body.%GetTypeOf("secret"), 1: ""), secret)
	If fields.%Size() Quit ..BadServer(fields)
	Set command = ##class(OcuTalon.Msg.Command.AddMcpServer).%New()
	Set command.Server = body.name
	Set command.Url = body.address
	Set command.ActingUser = $Username
	Set sc = ..Context(command)
	If $SYSTEM.Status.IsOK(sc) Set sc = ..HandOff(command, secret, .result, 1)
	Kill secret
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Quit ..Answer(result, "add")
}

/// DELETE /v1/settings/mcp/servers/:server: see the class description.
ClassMethod Remove(server As %String) As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	If '$Match($Get(server), ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set command = ##class(OcuTalon.Msg.Command.RemoveMcpServer).%New()
	Set command.Server = server
	Set command.ActingUser = $Username
	Set sc = ..Context(command)
	If $SYSTEM.Status.IsOK(sc) Set sc = ..HandOff(command, , .result, 1)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Quit ..Answer(result, "remove")
}

/// POST /v1/settings/mcp/classify: see the class description.
ClassMethod Classify() As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	If '..SettingsBody(.body) || (body.%Size() '= 3) || (body.%GetTypeOf("server") '= "string") || (body.%GetTypeOf("tool") '= "string") || (body.%GetTypeOf("classification") '= "string") {
		Quit ..Fail(400, "bad_classification", ##class(OcuTalon.Mcp.Ops).#MESSAGECLASSIFICATION)
	}
	If '$ListFind($ListFromString(##class(OcuTalon.Mcp.ToolClassification).#CLASSIFICATIONS), body.classification) Quit ..Fail(400, "bad_classification", ##class(OcuTalon.Mcp.Ops).#MESSAGECLASSIFICATION)
	If '$Match(body.server, ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) || (body.tool = "") || ($Length(body.tool) > ..#TOOLMAX) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set command = ##class(OcuTalon.Msg.Command.ClassifyTool).%New()
	Set command.Server = body.server
	Set command.Tool = body.tool
	Set command.Classification = body.classification
	Set command.ActingUser = $Username
	Set sc = ..Context(command)
	If $SYSTEM.Status.IsOK(sc) Set sc = ..HandOff(command, , .result, 1)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Quit ..Answer(result, "classify")
}

/// POST /v1/settings/mcp/sources: see the class description.
ClassMethod SetSource() As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	If '..SettingsBody(.body) || (body.%Size() '= 5) || (body.%GetTypeOf("server") '= "string") || (body.%GetTypeOf("tool") '= "string") || (body.%GetTypeOf("name") '= "string") || (body.%GetTypeOf("arguments") '= "string") || (body.%GetTypeOf("intervalMinutes") '= "number") || (body.intervalMinutes '= (body.intervalMinutes \ 1)) Quit ..BadSource({})
	Set fields = {}
	For member = "name", "arguments" {
		If body.%Get(member) [ "@{" Do fields.%Set(member, ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.refusedExpansion", "@{"))
	}
	If 'fields.%IsDefined("name") && ($Length($ZStrip(body.name, "<>W")) > ##class(OcuTalon.Mcp.Ops).#NAMEMAX) Do fields.%Set("name", ##class(OcuTalon.Mcp.Ops).#MESSAGESOURCENAME)
	If 'fields.%IsDefined("arguments") && '..ArgumentsAreObject(body.arguments) Do fields.%Set("arguments", ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.sourceBadArguments"))
	If fields.%Size() Quit ..BadSource(fields)
	If '$Match(body.server, ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) || (body.tool = "") || ($Length(body.tool) > ..#TOOLMAX) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set command = ##class(OcuTalon.Msg.Command.SetSourcePoll).%New()
	Set command.Server = body.server
	Set command.Tool = body.tool
	Set command.Name = $ZStrip(body.name, "<>W")
	Set command.Arguments = body.arguments
	Set command.IntervalMinutes = body.intervalMinutes
	Set command.ActingUser = $USERNAME
	Set sc = ..Context(command)
	If $SYSTEM.Status.IsOK(sc) Set sc = ..HandOff(command, , .result, 1)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Quit ..Answer(result, "set")
}

/// DELETE /v1/settings/mcp/sources/:ref: see the class description.
ClassMethod RemoveSource(ref As %String) As %Status
{
	Set refused = ..Refusal()
	If refused '= "" Quit refused
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '..OwnSource(sessionRef, $Get(ref), .sc) {
		If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
		Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	}
	Set command = ##class(OcuTalon.Msg.Command.RemoveSourcePoll).%New()
	Set command.SourceRef = ref
	Set command.ActingUser = $USERNAME
	Set sc = ..Context(command)
	If $SYSTEM.Status.IsOK(sc) Set sc = ..HandOff(command, , .result, 1)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Quit ..Answer(result, "removeSource")
}

/// 1 when ref is a source row of the session's own checks (Ownership.Checks); sc is an error status when the read failed.
ClassMethod OwnSource(sessionRef As %String, ref As %String, Output sc As %Status) As %Boolean [ Private ]
{
	Set rows = ##class(OcuTalon.Data.Ownership).Checks(sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit 0
	Set found = 0
	For index = 1:1:rows.Count() {
		Set row = rows.GetAt(index)
		If (row.Ref = ref) && (row.Kind = "source") Set found = 1
	}
	Quit found && (ref '= "")
}

/// 1 when text is "" or the text of a JSON object.
ClassMethod ArgumentsAreObject(text As %String) As %Boolean [ Private ]
{
	If text = "" Quit 1
	Set object = ""
	Try {
		Set object = {}.%FromJSON(text)
	} Catch exception {
		Set object = ""
	}
	Quit $IsObject(object) && object.%IsA("%Library.DynamicObject")
}

/// Sets the CSP session's Ref on the command (AD-4: never from the client).
ClassMethod Context(command As OcuTalon.Msg.Command) As %Status [ Private ]
{
	Set command.SessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	Quit sc
}

/// The field errors of an add that the route finds before anything is offered, as {name, address, secret} with each refused field's text ({} when none): an @{ in a value is
/// settings.refusedExpansion; a name that does not match Mcp.Server NAMEPATTERN, an address that Mcp.Ops AddressAllowed refuses (or over ADDRESSMAX characters), and a secret that is not a
/// string, or is not 1 to SECRETMAX printable ASCII characters, are their texts. secretType is the JSON type of the secret ("" when it is absent, which is no secret).
ClassMethod AddFields(name As %String, address As %String, secretType As %String, secret As %String) As %DynamicObject [ Private ]
{
	Set fields = {}
	If name [ "@{" {
		Do fields.%Set("name", ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.refusedExpansion", "@{"))
	} ElseIf '$Match(name, ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) || ($ZStrip(name, "*C") '= name) {
		Do fields.%Set("name", ##class(OcuTalon.Mcp.Ops).#MESSAGENAME)
	}
	If address [ "@{" {
		Do fields.%Set("address", ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.refusedExpansion", "@{"))
	} ElseIf ($Length(address) > ..#ADDRESSMAX) || '##class(OcuTalon.Mcp.Ops).AddressAllowed(address) {
		Do fields.%Set("address", ##class(OcuTalon.Mcp.Ops).#MESSAGEADDRESS)
	} ElseIf (address [ "?") || (address [ "#") {
		Do fields.%Set("address", ##class(OcuTalon.Mcp.Ops).#MESSAGEQUERY)
	}
	If secretType = "" Quit fields
	If secretType '= "string" {
		Do fields.%Set("secret", ..#MESSAGESECRET)
	} ElseIf secret [ "@{" {
		Do fields.%Set("secret", ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.refusedExpansion", "@{"))
	} ElseIf (secret '= "") && (($Length(secret) > ..#SECRETMAX) || '$Match(secret, "^[!-~]+\z")) {
		Do fields.%Set("secret", ..#MESSAGESECRET)
	}
	Quit fields
}

/// The answer from the CommandResult (kind is list, add, remove, classify, set or removeSource): listed is 200 with the Data; added, removed and saved are 200 {"result", "message"}
/// (a saved set adds "ref"); for kind set, not_read_only, bad_name, reserved_name, bad_interval and bad_arguments are 400 bad_source with the field {tool}, {name}, {intervalMinutes} or
/// {arguments} and McpOps' text; for the other kinds bad_name,
/// bad_address and exists are 400 bad_mcp_server with the field and McpOps' text; bad_classification is 400; not_found is 404; not_available is 409 with the result's message; every
/// other outcome, and no result, is 500 server_error.
ClassMethod Answer(result As OcuTalon.Msg.CommandResult, kind As %String) As %Status [ Private ]
{
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	Set outcome = result.Outcome
	If result.Ok && (outcome = "listed") && (kind = "list") {
		Set %response.ContentType = ..#CONTENTTYPE
		Write result.Data
		Quit $SYSTEM.Status.OK()
	}
	If result.Ok && (kind = "set") && (outcome = "saved") {
		Set %response.ContentType = ..#CONTENTTYPE
		Write {"result": (outcome), "message": (result.Message), "ref": (result.Ref)}.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	If result.Ok && ((outcome = "added") || (outcome = "removed") || (outcome = "saved")) {
		Set %response.ContentType = ..#CONTENTTYPE
		Write {"result": (outcome), "message": (result.Message)}.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	If (kind = "set") && ((outcome = "not_read_only") || (outcome = "bad_name") || (outcome = "reserved_name") || (outcome = "bad_interval") || (outcome = "bad_arguments")) {
		Set fields = {}
		Do fields.%Set($Case(outcome, "not_read_only": "tool", "bad_interval": "intervalMinutes", "bad_arguments": "arguments", : "name"), result.Message)
		Quit ..BadSource(fields)
	}
	If (outcome = "bad_name") || (outcome = "bad_address") || (outcome = "exists") {
		Set fields = {}
		Do fields.%Set($Case(outcome, "bad_address": "address", : "name"), result.Message)
		Quit ..BadServer(fields)
	}
	If outcome = "bad_classification" Quit ..Fail(400, "bad_classification", result.Message)
	If outcome = "not_found" Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If outcome = "not_available" Quit ..Fail(409, "not_available", result.Message)
	Quit ..ServerError($SYSTEM.Status.Error(5001, "The MCP settings call was answered "_outcome))
}

/// 400 bad_mcp_server with the plain not-saved message and the refused fields, each with its text.
ClassMethod BadServer(fields As %DynamicObject) As %Status [ Private ]
{
	Quit ..Fail(400, "bad_mcp_server", ..#MESSAGEBADSETTINGS, , {"fields": (fields)})
}

/// 400 bad_source with the plain not-saved message and the refused fields, each with its text.
ClassMethod BadSource(fields As %DynamicObject) As %Status [ Private ]
{
	Quit ..Fail(400, "bad_source", ..#MESSAGEBADSETTINGS, , {"fields": (fields)})
}

}
