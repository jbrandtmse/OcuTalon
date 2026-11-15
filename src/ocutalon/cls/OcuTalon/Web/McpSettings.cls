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

/// The answer from the CommandResult (kind is list, add, remove or classify): listed is 200 with the Data; added, removed and saved are 200 {"result", "message"}; bad_name,
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
	If result.Ok && ((outcome = "added") || (outcome = "removed") || (outcome = "saved")) {
		Set %response.ContentType = ..#CONTENTTYPE
		Write {"result": (outcome), "message": (result.Message)}.%ToJSON()
		Quit $SYSTEM.Status.OK()
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

}
