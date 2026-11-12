Include Ensemble

/// The governed proxy's call of an MCP tool (Story 22.3; AD-6, AD-10, AD-19, AD-21, AD-25): the one place where OcuTalon calls a tool of a registered MCP server with its own
/// bounded client (OcuTalon.Mcp.Client). The tool call_mcp_tool (OcuTalon.Tools.McpCall) runs inside AI Hub's callback and calls Call; the gate has classified the call and
/// checked the service user's Use permission on the server's resource before this class runs.
///   - Call(server, tool, arguments, room) answers a dynamic object: {"text"} for a tool that ran, or {"refusal", "outcome"} for one that did not run. The refusal is one of
///     demo, changed, failed and timeout, which McpCall turns into its sentences, and the outcome is the fixed word that the audit entry holds. It never throws, and no answer
///     holds the url, the credential, an argument or any text of the server.
///   - The steps, in order, each of which refuses without running the tool: (1) the online demo (demo, before any request and without an audit entry); (2) a server name that matches
///     OcuTalon.Mcp.Server NAMEPATTERN with a row, a tool name of at most 128 characters, and the tool's OcuTalon.Mcp.ToolClassification row, which must be read-only or risky: a
///     missing server, tool or row is failed, and a row that is unclassified, because the tool changed or an admin cleared it since the gate allowed the call, is changed;
///     (3) the server's Config Store entry AI.MCP.OcuTalon_<server>, read without resolving anything (Bridge.ConfigStore Details), which must be a remote entry whose url passes
///     Mcp.Ops AddressAllowed (https, or http to this computer); (4) the credential header of the entry, resolved in memory, at this moment, from the entry's secret:// reference
///     (%ConfigStore.Configuration GetDetails with the secrets resolved, the API that AI Hub's own attach uses, measured in Task 0) and kept in a local variable that no log,
///     audit entry, trace or answer receives; (5) Client.ListTool, whose tool must still have the fingerprint of the row (Bridge.Context ToolFingerprint of the toolref, the name,
///     the description and the input schema): a different fingerprint, or a tool the server no longer lists, is changed and the tool is not called; (6) Client.CallTool; (7) the
///     text parts of the result joined by line feeds, every other kind of part as "[non-text content omitted]"; (8) one audit entry (Bridge.Audit Record, type MCP, change called or
///     refused, the server, the tool and the outcome: ok, cut when the text is longer than room characters, or the reason word of the refusal), for every run that passed step 2
///     (a run that reached a registered server's tool). An audit that fails is one redacted warning, and the answer is still returned.
///   - The replay of an approved call (Story 22.4; Bridge.Context ApprovedFingerprint(tool) is not empty, which only the gate's consumed grant sets) is the same run with two
///     differences: step 2 requires the server's row only and not the tool's classification row (an unclassified tool's exact call can be approved), and step 5 compares the live
///     fingerprint with the one the call was approved at (the request's ToolFingerprint) and not with the classification row, so that a tool changed in name, description or
///     schema since the hold is not called. Every refusal of a replay, the demo's included, notes its reason word in the context (Context NoteReplayRefusal) for the replay
///     to read.
///   - It writes no row and never clears a classification: a changed tool is refused, and the next turn's map clears the row (Story 22.8). The classes that this one runs inside
///     the callback make no AI Hub call and run no Python (AD-6).
Class OcuTalon.Mcp.Proxy
{

/// The longest tool name (the length of OcuTalon.Mcp.ToolClassification Tool).
Parameter TOOLMAX = 128;

/// The text of a part of a result that is not text.
Parameter OMITTED = "[non-text content omitted]";

/// Runs the tool of the server with the arguments (see the class description). room, when it is not empty, is the number of characters that the model step still has room for,
/// so that the audit entry can say cut; it changes nothing else.
ClassMethod Call(server As %String, tool As %String, arguments As %DynamicObject = "", room As %Integer = "") As %DynamicObject
{
	Set approved = ##class(OcuTalon.Bridge.Context).ApprovedFingerprint($Get(tool))
	If ..OnlineDemo() Quit ..Noted(..Refusal("demo", "demo"), approved)
	Set answer = ..Refusal("failed", "failed")
	Set reached = 0
	Try {
		If '..Registered($Get(server), $Get(tool), approved '= "", .row) Quit
		Set reached = 1
		Set answer = ..Run(server, tool, row, arguments, room, approved)
	} Catch exception {
		Set answer = ..Refusal("failed", "failed")
		$$$LOGWARNING("OcuTalon.Mcp.Proxy: a call of an MCP tool ended in an exception (" _ $Extract(exception.Name, 1, 40) _ "), so nothing is known to have run")
	}
	If reached Do ..Audit(server, tool, answer.outcome)
	Quit ..Noted(answer, approved)
}

/// The answer, after noting the word of its refusal in the context when the call is the replay of an approved one (approved is the fingerprint it was approved at, not empty)
/// and the answer is a refusal (Context NoteReplayRefusal), so that the replay can tell a refusal from a result. A call that is not a replay notes nothing.
ClassMethod Noted(answer As %DynamicObject, approved As %String) As %DynamicObject [ Private ]
{
	If (approved '= "") && (answer.%GetTypeOf("refusal") = "string") Do ##class(OcuTalon.Bridge.Context).NoteReplayRefusal(answer.refusal)
	Quit answer
}

/// 1 when the server is registered and the tool has a row of it: server matches the pattern of a name and has a row of OcuTalon.Mcp.Server, tool is a name of 1 to TOOLMAX
/// characters with no control character; row is the tool's classification row. For the replay of an approved call (replay 1) the server row is all that is required, because
/// the approved fingerprint and not the classification rules the run: row is then the tool's row when it has one, else "".
ClassMethod Registered(server As %String, tool As %String, replay As %Boolean, Output row As %RegisteredObject) As %Boolean [ Private ]
{
	Set row = ""
	If $IsObject(server) || $IsObject(tool) Quit 0
	If '$Match(server, ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) || '##class(OcuTalon.Mcp.Server).NameIndexExists(server) Quit 0
	If ($Length(tool) < 1) || ($Length(tool) > ..#TOOLMAX) || ($ZStrip(tool, "*C") '= tool) Quit 0
	Set row = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(server, tool)
	Quit replay || $IsObject(row)
}

/// Steps 2 to 7 of the class description for a server and a tool that Registered found. The answer is {"text", "outcome"} or {"refusal", "outcome"}.
ClassMethod Run(server As %String, tool As %String, row As OcuTalon.Mcp.ToolClassification, arguments As %DynamicObject, room As %Integer, approved As %String = "") As %DynamicObject [ Private ]
{
	If (approved = "") && ((row.Classification '= "read-only") && (row.Classification '= "risky")) Quit ..Refusal("changed", "changed")
	Set config = "AI.MCP." _ ##class(OcuTalon.Mcp.Attach).#ENTRYPREFIX _ server
	Set sc = ##class(OcuTalon.Bridge.ConfigStore).Details(config, .details)
	If $$$ISERR(sc) || '$IsObject(details) || (details.%GetTypeOf("url") '= "string") || (details.%GetTypeOf("transport") '= "string") Quit ..Refusal("failed", "failed")
	If '$ListFind($ListBuild("remote", "http", "https"), details.transport) || '##class(OcuTalon.Mcp.Ops).AddressAllowed(details.url) Quit ..Refusal("failed", "address")
	Set url = details.url
	Set header = ..Header(config, .ok)
	If 'ok Quit ..Refusal("failed", "credential")
	Set reason = ##class(OcuTalon.Mcp.Client).ListTool(url, header, tool, .definition, .session)
	If reason '= "" Quit ..Reason(reason)
	Set toolref = ##class(OcuTalon.Mcp.Attach).Toolref(server)
	Set fingerprint = ""
	Try {
		Set fingerprint = ##class(OcuTalon.Bridge.Context).ToolFingerprint(toolref, tool, definition.%Get("description"), $Select(definition.%GetTypeOf("inputSchema") = "object": definition.inputSchema, 1: ""))
	} Catch {
		Set fingerprint = ""
	}
	If (fingerprint = "") || (fingerprint '= $Select(approved '= "": approved, 1: row.Fingerprint)) Quit ..Refusal("changed", "changed")
	Set reason = ##class(OcuTalon.Mcp.Client).CallTool(url, header, tool, $Select($IsObject(arguments): arguments, 1: {}), .result, session)
	If reason '= "" Quit ..Reason(reason)
	Set text = ..TextOf(result)
	Set outcome = $Select((room '= "") && ($Length(text) > room): "cut", 1: "ok")
	Quit {"text": (text), "outcome": (outcome)}
}

/// The credential header of the entry, resolved now and held only in the variable that is returned: {"name", "value"}. ok is 0 when the
/// entry cannot be read, has no auth (AI Hub's descriptor requires one for a remote server), names an auth type that is not bearer, basic or header, or has not the values that its type needs. The values are never logged or returned
/// beyond the caller: a failure sets ok to 0 and nothing else.
ClassMethod Header(config As %String, Output ok As %Boolean) As %DynamicObject [ Private ]
{
	Set ok = 0
	Set header = ""
	Try {
		Set sc = ##class(%ConfigStore.Configuration).GetDetails(config, .resolved, 0, 1)
		If $$$ISERR(sc) || '$IsObject(resolved) Quit
		If resolved.%GetTypeOf("auth") '= "object" Quit
		Set auth = resolved.auth
		Set type = $Select(auth.%GetTypeOf("type") = "string": auth.type, 1: "")
		If type = "header" {
			If (auth.%GetTypeOf("name") = "string") && (auth.%GetTypeOf("value") = "string") && (auth.name '= "") && (auth.value '= "") {
				Set header = {"name": (auth.name), "value": (auth.value)}
			}
		} ElseIf type = "bearer" {
			If (auth.%GetTypeOf("token") = "string") && (auth.token '= "") Set header = {"name": "Authorization", "value": ("Bearer " _ auth.token)}
		} ElseIf type = "basic" {
			If (auth.%GetTypeOf("username") = "string") && (auth.%GetTypeOf("password") = "string") && (auth.username '= "") {
				Set header = {"name": "Authorization", "value": ("Basic " _ $SYSTEM.Encryption.Base64Encode($ZConvert(auth.username _ ":" _ auth.password, "O", "UTF8"), 1))}
			}
		}
		Set ok = $IsObject(header)
	} Catch {
		Set ok = 0
		Set header = ""
	}
	Quit header
}

/// The refusal for the reason word of a Client answer: a timeout is timeout, a tool that the server no longer lists is changed, and every other reason is failed. The outcome
/// is the reason word itself.
ClassMethod Reason(reason As %String) As %DynamicObject [ Private ]
{
	Quit ..Refusal($Case(reason, "timeout": "timeout", "notfound": "changed", : "failed"), reason)
}

/// {"refusal", "outcome"}.
ClassMethod Refusal(refusal As %String, outcome As %String) As %DynamicObject [ Private ]
{
	Quit {"refusal": (refusal), "outcome": (outcome)}
}

/// The text of a result: the text of each text part of its content, joined by line feeds, and OMITTED for any other part. A result with no content list has no text.
ClassMethod TextOf(result As %DynamicObject) As %String [ Private ]
{
	Set text = ""
	If result.%GetTypeOf("content") '= "array" Quit text
	Set iterator = result.content.%GetIterator()
	While iterator.%GetNext(, .part, .type) {
		Set piece = ..#OMITTED
		If (type = "object") && (part.%GetTypeOf("type") = "string") && (part.type = "text") && (part.%GetTypeOf("text") = "string") Set piece = part.text
		Set text = text _ $Select(text = "": "", 1: $Char(10)) _ piece
	}
	Quit text
}

/// Writes the one audit entry of a run that reached a registered server's tool: change called for a run that ran the tool, else refused, with the server, the tool and the
/// outcome word only. A failure of the writer is one warning with its redacted text.
ClassMethod Audit(server As %String, tool As %String, outcome As %String) [ Private ]
{
	Try {
		Set context = ##class(OcuTalon.Bridge.Context).Current()
		Set channel = $Select($IsObject(context) && $ListFind($ListFromString(##class(OcuTalon.Bridge.Msg.Enum).#CHANNEL), context.Channel): context.Channel, 1: "system")
		Set session = $Select($IsObject(context) && $Match(context.OwnerRef, "^[A-Za-z0-9_-]{22}$"): context.OwnerRef, 1: "")
		Set data = {}
		Do data.%Set("change", $Select(outcome = "ok" || (outcome = "cut"): "called", 1: "refused"), "string")
		Do data.%Set("server", server, "string")
		Do data.%Set("tool", tool, "string")
		Do data.%Set("outcome", outcome, "string")
		Do data.%Set("irisUser", $Select($Username '= "": $Username, 1: "system"), "string")
		Do data.%Set("sessionRef", session, "string")
		Do data.%Set("channel", channel, "string")
		Set sc = ..WriteAudit(data)
		If $$$ISERR(sc) $$$LOGWARNING("OcuTalon.Mcp.Proxy: the audit entry of a call could not be written: " _ ##class(OcuTalon.Bridge.Redact).Text($SYSTEM.Status.GetErrorText(sc)))
	} Catch exception {
		$$$LOGWARNING("OcuTalon.Mcp.Proxy: the audit entry of a call could not be written: " _ ##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
}

/// The one audit write of the class, through the one writer of product code. A seam for the tests.
ClassMethod WriteAudit(data As %DynamicObject) As %Status
{
	Quit ##class(OcuTalon.Bridge.Audit).Record("MCP", data)
}

/// 1 on the online demo (the Setting onlineDemo holds 1), as Mcp.Ops and Watch.Reader read it. A seam for the tests.
ClassMethod OnlineDemo() As %Boolean
{
	Quit (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
}

}
