Include Ensemble

/// The poll of a source (Story 22.11; AD-6, AD-10, AD-21, AD-30): the runner's answer to a request of kind tool and provenance untrusted, whose Input is {"source": <the source's Ref>}.
/// It makes exactly one call of the host's governed proxy (call_mcp_tool) and never calls a model, takes a grant or writes a Decision row. Run does, in this order:
///   1. The Input is read (SourceOf): anything but one member source that is a Ref is the failure invalid, with no call.
///   2. The manager is built (Adapter.Agent PollManager): a standalone tool manager that holds only the host's proxy toolset, governed by the gate and the step audit policy. It needs no
///      agent and no key, so a poll runs on an install with no model key. When the host has no proxy (the bridge alone, the online demo) the run is the failure failed.
///   3. The context is begun from the request (Context Begin: kind tool, provenance untrusted, no grant).
///   4. The host prepares the call (McpServersClass PollCall, asked through Ext.Accessor): the server, the tool, the arguments of the source's own row, the server's toolref and the
///      live fingerprint of the tool. A word of POLLREASONS ends the run with that word, and no call is made.
///   5. The context's map is seeded with that one tool (Context SeedMcp), so that the gate classifies the proxy call as the native call of the tool, and the step is labelled for it.
///   6. The step buffer starts, and the manager runs ExecuteTool of call_mcp_tool {server, tool, arguments}. The gate (the untrusted rule: only a safe and read-only call runs, and anything
///      else is denied, never held; no grant is needed or taken), the step audit and the proxy's own checks apply. A gate denial is the word denied, and any other exception is failed.
///   7. The reply: Text is the answer's value, only when the proxy noted no refusal (Context ReplayRefusal); FailureText is "" or one word, the proxy's refusal word (demo, changed, failed or
///      timeout), denied, or a word of POLLREASONS from step 4; Tainted is 1 when the call ran; ToolsRun is 1 once ExecuteTool was reached; Steps, AgentStepCount and DurationMs are as in any
///      reply. The words are for Checks alone and are never shown to a person.
/// The context, the step buffer and the manager are let go of on every path. The reply holds no argument, URL or credential. This class names no host class (AD-2): the host is reached
/// through the McpServersClass extension only.
Class OcuTalon.Bridge.Poll
{

/// The FailureText of a call that the gate denied.
Parameter DENIED = "denied";

/// The FailureText of a Reply whose Input is not {"source": <Ref>}.
Parameter INVALID = "invalid";

/// The FailureText of a run that could not be made for any other reason (no proxy, an exception, a call that gave no answer).
Parameter FAILED = "failed";

/// The Ref of the source that the Input names, or "" for any other Input: the Input must be a JSON object whose one member is source, a text of the 22 characters of a Ref. It never throws.
ClassMethod SourceOf(input As %String) As %String
{
	Set source = ""
	Try {
		Set object = {}.%FromJSON($Get(input))
		If $IsObject(object) && object.%IsA("%Library.DynamicObject") && (object.%Size() = 1) && (object.%GetTypeOf("source") = "string") && ##class(OcuTalon.Bridge.Approval).IsRef(object.source) Set source = object.source
	} Catch {
		Set source = ""
	}
	Quit source
}

/// Polls the source of the request in the job of adapter (see the class description). reply is the Reply described above. The status is OK for every outcome that the reply tells.
ClassMethod Run(adapter As OcuTalon.Bridge.Adapter.Agent, request As OcuTalon.Bridge.Msg.Request, superSession As %String = "", Output reply As OcuTalon.Bridge.Msg.Reply) As %Status
{
	Set reply = ""
	Set started = $ZHorolog
	Set source = ..SourceOf(request.Input)
	If source = "" {
		Set reply = ..Failure(..#INVALID)
		Quit $$$OK
	}
	Set text = ""
	Set word = ..#FAILED
	Set executed = 0
	Set tainted = 0
	Set steps = ""
	Set count = 0
	Set manager = ""
	Set begun = 0
	Set buffered = 0
	Try {
		Set sc = adapter.PollManager(.manager)
		If $$$ISERR(sc) Quit
		Set sc = ##class(OcuTalon.Bridge.Context).Begin(request, superSession, adapter.BusinessHost.%ConfigName)
		If $$$ISERR(sc) Quit
		Set begun = 1
		Set class = ##class(OcuTalon.Bridge.Ext.Accessor).ClassFor("McpServersClass", "", "Decide", .sc)
		If $$$ISERR(sc) Quit
		Set word = $ClassMethod(class, "PollCall", source, .server, .tool, .arguments, .toolref, .fingerprint)
		If word '= "" {
			If '$ListFind($ListFromString(##class(OcuTalon.Bridge.Ext.McpServers).#POLLREASONS), word) Set word = ..#FAILED
			Quit
		}
		Set word = ..#FAILED
		If '$IsObject(arguments) Set arguments = {}
		Set sc = ##class(OcuTalon.Bridge.Context).SeedMcp(server, toolref, tool, fingerprint)
		If $$$ISERR(sc) Quit
		Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).Start(0)
		Set buffered = 1
		Set executed = 1
		Set answer = ""
		Try {
			Set answer = manager.ExecuteTool(##class(OcuTalon.Bridge.Policy.Gate).#MCPPROXY, {"server": (server), "tool": (tool), "arguments": (arguments)})
			Set refusal = ##class(OcuTalon.Bridge.Context).ReplayRefusal()
			If refusal '= "" {
				Set word = $Select($ListFind($ListFromString(##class(OcuTalon.Bridge.Ext.McpServers).#POLLREASONS), refusal): refusal, 1: ..#FAILED)
			} ElseIf $IsObject(answer) && (answer.%GetTypeOf("value") = "string") {
				Set text = answer.value
				Set word = ""
				Set tainted = 1
			}
		} Catch exception {
			Set word = $Select($SYSTEM.Status.GetErrorCodes(exception.AsStatus()) [ "ToolAccessDenied": ..#DENIED, 1: ..#FAILED)
		}
	} Catch {
		Set word = ..#FAILED
	}
	Try {
		If buffered {
			Set records = adapter.StepRecords()
			Set steps = adapter.StepsJson(records)
			If $IsObject(records) Set count = records.%Size()
		}
	} Catch {
	}
	Set manager = ""
	If begun Do ##class(OcuTalon.Bridge.Context).End()
	If buffered Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).End()
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = text
	Set reply.ToolsRun = executed
	Set reply.Tainted = tainted
	Set reply.Steps = steps
	Set reply.AgentStepCount = count
	Set reply.DurationMs = $Number(($ZHorolog - started) * 1000, 0)
	Set reply.FailureText = word
	Quit $$$OK
}

/// A failure Reply for a poll that was not made: the word as FailureText, ToolsRun 0.
ClassMethod Failure(word As %String) As OcuTalon.Bridge.Msg.Reply [ Private ]
{
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.FailureText = word
	Set reply.ToolsRun = 0
	Quit reply
}

}
