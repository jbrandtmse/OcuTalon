/// The poll of a source in the bridge (Story 22.11; AD-2, AD-6, AD-10, AD-21, AD-30). THESE TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), as Test.Mcp.JobFixture's do: the gate
/// and the proxy tests need the loopback MCP mock, the fixtures of the server zzmcp (the row, the entry, the wallet secret, the Use permission, the tool rows zz_lookup read-only and
/// zz_delete_ticket risky) and OcuTalon's own McpServersClass and ClassificationClass in the production's settings. Each test removes what it made.
///   - TestAdmitPoll: Decide.Admit admits a tool request of provenance untrusted only when its Input is exactly {"source": <a Ref>} (the ItemId is a new one, no approval Ref); any other
///     untrusted tool request is refused naming Provenance; a user tool request is the replay's, unchanged (its ItemId must be an approval Ref);
///   - TestRunnerForPoll: a poll gets the runner of kind decide (TriageAgent), and a user tool request still gets its row's runner;
///   - TestPollNoDecisionRow: through a Decide shadow, a poll's success, its timer, a runner that fails and the answer of no runner write no Decision row and no decision.recorded,
///     and the success sends its steps to AgentSteps; the answer is a bare Reply with the runner's text, taint, steps and failure word, and the timer's is Fallback 1 with timeout;
///   - TestPollOnlyProxy: in a poll's context the gate denies every call but call_mcp_tool with FAILED, one that a user's turn is allowed to make included;
///   - TestPollNoGrant: a read-only proxy call runs in a poll's context with no grant (no grant is built or consumed), once, and the mock logs one tools/call from OcuTalon's client;
///   - TestPollRiskyDenied: a risky tool's proxy call is denied with UNTRUSTED, never held (no approval request), and the mock gets no tools/call;
///   - TestSeedMcpKeys: SeedMcp keys one tool and one server into a poll's map, and refuses no context, an empty or too long key, a toolref that is not mcp: and an empty fingerprint, leaving the map as it was;
///   - TestPollCallDefault: the bridge's own PollCall answers invalid, with every output empty;
///   - TestPollRunWords: Poll.Run with OcuTalon's PollCall for a source row: the answer's text and one step on success, and the word of every refusal (invalid, notreadonly, changed,
///     unreachable, timeout, denied; arguments that are no JSON object are invalid; a tools/call that the proxy refuses after the listing is its word, never text), with no tools/call after a refusal, and no context or step buffer left behind.
Class OcuTalon.Test.Bridge.Poll Extends OcuTalon.Test.Mcp.JobFixture
{

Parameter SINK = "OcuTalon.Test.Bridge.ProbeSink";

Parameter AGENT = "OcuTalon.Test.Bridge.ZzGateAgent";

Parameter DECIDE = "OcuTalon.Bridge.Process.Decide";

/// The name of the source rows that a test made, for the clean-up.
Property Sources As %String(MAXLEN = "");

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).End()
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.CheckRun WHERE CheckRef IN (SELECT Ref FROM OcuTalon_Data.BackgroundCheck WHERE Server = ?)", ..#SERVER)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.BackgroundCheck WHERE Server = ?", ..#SERVER)
	Kill ^||ZzDecideCalls, ^||ZzProbeSink
	Quit ##super(testname)
}

/// Admit (see the class description).
Method TestAdmitPoll()
{
	Set decide = ..#DECIDE
	Set source = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ..NewPoll(source)
	Do $$$AssertStatusOK($ClassMethod(decide, "Admit", request), "a tool request of provenance untrusted whose Input is {""source"": <Ref>} is admitted")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).IsRef(request.ItemId), 1, "its ItemId is a new Ref of its own")
	Set request.ItemId = "zz-not-an-approval-ref"
	Do $$$AssertStatusOK($ClassMethod(decide, "Admit", request), "and its ItemId need not be the Ref of an approval request")
	Set request = ..NewPoll(source)
	Set request.Input = {"source": (source)}.%ToJSON() _ " "
	Do $$$AssertStatusOK($ClassMethod(decide, "Admit", request), "white space after the JSON does not matter")
	For input = "", " ", "x", "{}", "[]", "[""" _ source _ """]", """" _ source _ """", "{""source"":""short""}", "{""source"":7}", "{""source"":null}", "{""source"":""" _ source _ "!""}", {"source": (source), "extra": 1}.%ToJSON(), {"Source": (source)}.%ToJSON(), {"source": ({"a": 1})}.%ToJSON() {
		Set request = ..NewPoll(source)
		Set request.Input = input
		Set sc = $ClassMethod(decide, "Admit", request)
		Do $$$AssertStatusNotOK(sc, "the untrusted tool request with the Input '" _ $Extract(input, 1, 40) _ "' is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "Provenance", "and the refusal names Provenance")
	}
	Set user = ..NewPoll(source)
	Set user.Provenance = "user"
	Set user.ItemId = "zz-no-approval-ref"
	Set sc = $ClassMethod(decide, "Admit", user)
	Do $$$AssertStatusNotOK(sc, "a user tool request whose ItemId is no approval Ref is refused, as before")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ItemId", "naming ItemId")
	Set user.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK($ClassMethod(decide, "Admit", user), "a user tool request with a Ref as its ItemId is admitted, whatever its Input")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Poll).SourceOf({"source": (source)}.%ToJSON()), source, "SourceOf gives the Ref of the Input")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Poll).SourceOf("{""source"":""x""}"), "", "and gives nothing for a value that is no Ref")
}

/// RunnerFor (see the class description).
Method TestRunnerForPoll()
{
	Set decide = ..#DECIDE
	Set poll = ..NewPoll(##class(OcuTalon.Bridge.Ids).NewRef())
	Do $$$AssertEquals($ClassMethod(decide, "RunnerFor", "tool", poll), "TriageAgent", "a poll gets the runner of kind decide")
	Do $$$AssertEquals($ClassMethod(decide, "RunnerFor", "tool", poll), $ClassMethod(decide, "RunnerFor", "decide"), "which RUNNERS gives for decide")
	Set user = ..NewPoll(##class(OcuTalon.Bridge.Ids).NewRef())
	Set user.Provenance = "user"
	Set user.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertEquals($ClassMethod(decide, "RunnerFor", "tool", user), "", "a user tool request with no approval row still gets no runner")
	Do $$$AssertEquals($ClassMethod(decide, "RunnerFor", "tool"), "", "and so does a tool kind with no request")
	Do $$$AssertEquals($ClassMethod(decide, "RunnerFor", "turn"), "ChatAgent", "the other kinds are as they were")
}

/// A poll's success, its timer, a runner that fails and no answer, through the Decide shadow (see the class description).
Method TestPollNoDecisionRow()
{
	Kill ^||ZzDecideCalls, ^||ZzProbeSink
	Set request = ..NewPoll(##class(OcuTalon.Bridge.Ids).NewRef())
	Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
	Set recorder = ..Recorder()
	Do $$$AssertStatusOK(recorder.OnRequest(request, .response), "OnRequest takes the poll")
	Do $$$AssertEquals(response, "", "it does not answer yet")
	Set call = ^||ZzDecideCalls("send", 1)
	Do $$$AssertEquals(^||ZzDecideCalls("send") _ "|" _ $List(call, 1) _ "|" _ $List(call, 3) _ "|" _ $List(call, 4) _ "|" _ $Get(^||ZzDecideCalls("timer")), "1|TriageAgent|1|reply|1", "one send to TriageAgent with the key reply, and one timer")
	Do $$$AssertEquals($List(call, 2), recorder.DecisionRef, "the request carries the DecisionRef that Decide allocated")
	Do $$$AssertEquals(..Rows(request.ItemId, recorder.DecisionRef), 0, "no precheck, no fallback and no Decision row exist")
	Set callRequest = request.%ConstructClone()
	Set callRequest.DecisionRef = recorder.DecisionRef
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = "T-1 open"
	Set reply.Tainted = 1
	Set reply.ToolsRun = 1
	Set reply.AgentStepCount = 1
	Set reply.Steps = [{"kind": "tool", "label": "Running zz_lookup on zz", "summary": "call_mcp_tool.", "durationMs": 3, "status": "ok", "estimatedTokens": 5}].%ToJSON()
	Do $$$AssertStatusOK(recorder.OnResponse(request, .out, callRequest, reply, "reply"), "OnResponse takes the runner's Reply")
	Do $$$AssertTrue($IsObject(out) && out.%IsA("OcuTalon.Bridge.Msg.Reply"), "the answer is a Reply")
	If $IsObject(out) Do $$$AssertEquals(out.Text _ "|" _ out.Tainted _ "|" _ out.ToolsRun _ "|" _ out.FailureText _ "|" _ out.Fallback _ "|" _ out.DecisionRef, "T-1 open|1|1||0|", "with the runner's text, taint and tools run, no failure, no fallback and no DecisionRef")
	If $IsObject(out) Do $$$AssertEquals(##class(%DynamicAbstractObject).%FromJSON(out.Steps).%Size(), 1, "and the steps")
	Do $$$AssertEquals(..Rows(request.ItemId, recorder.DecisionRef), 0, "no Decision row is written")
	Do $$$AssertEquals(..SinkTypes(), "", "and no decision.recorded is fired")
	Set steps = 0
	For n = 1:1:$Get(^||ZzDecideCalls("send")) {
		If $List(^||ZzDecideCalls("send", n), 1) = "AgentSteps" Set steps = steps + 1
	}
	Do $$$AssertEquals(steps, 1, "the step was sent to AgentSteps")

	// the timer
	Kill ^||ZzDecideCalls, ^||ZzProbeSink
	Set timed = ..NewPoll(##class(OcuTalon.Bridge.Ids).NewRef())
	Set ..ItemIds = ..ItemIds _ $ListBuild(timed.ItemId)
	Set recorder = ..Recorder()
	Do $$$AssertStatusOK(recorder.OnRequest(timed, .nothing), "(timer) the poll is taken")
	Do $$$AssertStatusOK(recorder.OnResponse(timed, .out, "", "", "timer"), "(timer) the timer ends it")
	Do $$$AssertTrue($IsObject(out) && out.%IsA("OcuTalon.Bridge.Msg.Reply"), "(timer) with a Reply")
	If $IsObject(out) Do $$$AssertEquals(out.Fallback _ "|" _ out.FallbackReason _ "|" _ out.FailureText _ "|" _ out.Text, "1|timeout|timeout|", "(timer) of Fallback 1, FallbackReason timeout and FailureText timeout")
	Do $$$AssertEquals(..Rows(timed.ItemId, recorder.DecisionRef) _ "|" _ ..SinkTypes() _ "|" _ $Get(^||ZzDecideCalls("send")), "0||1", "(timer) no Decision row, no event and no second send (no retry)")

	// a runner that fails: an error status, and a Reply of no object
	Kill ^||ZzDecideCalls, ^||ZzProbeSink
	Set failed = ..NewPoll(##class(OcuTalon.Bridge.Ids).NewRef())
	Set ..ItemIds = ..ItemIds _ $ListBuild(failed.ItemId)
	Set recorder = ..Recorder()
	Do $$$AssertStatusOK(recorder.OnRequest(failed, .nothing), "(runner error) the poll is taken")
	Set callFailed = failed.%ConstructClone()
	Set callFailed.DecisionRef = recorder.DecisionRef
	Do $$$AssertStatusOK(recorder.OnError(failed, .nothing, callFailed, $$$ERROR($$$GeneralError, "zz runner failure with a url http://zz.example/secret"), "reply"), "(runner error) OnError keeps the status")
	Do $$$AssertStatusOK(recorder.OnResponse(failed, .out, callFailed, "", "reply"), "(runner error) OnResponse answers")
	If $IsObject(out) Do $$$AssertEquals(out.FailureText _ "|" _ out.Fallback _ "|" _ out.Text, "failed|0|", "(runner error) with the word failed, never the runner's text")
	Do $$$AssertEquals(..Rows(failed.ItemId, recorder.DecisionRef) _ "|" _ ..SinkTypes() _ "|" _ $Get(^||ZzDecideCalls("send")), "0||1", "(runner error) no Decision row, no event, no retry and no re-send")

	// the pure answer
	Set none = $ClassMethod(..#DECIDE, "PollAnswer", "", 0)
	Do $$$AssertEquals(none.FailureText _ "|" _ none.Fallback, "failed|0", "(no runner) the answer of no Reply is the word failed")
}

/// A poll's context allows the proxy alone (see the class description).
Method TestPollOnlyProxy()
{
	Set gate = "OcuTalon.Bridge.Policy.Gate"
	Set list = "OcuTalon.Tools.ReminderTools"
	Do ..Begin("turn", "untrusted")
	Kill ^||ZzProbeSink
	Set sc = $ClassMethod(gate, "Check", "list_reminders", {"id": "call_id", "name": "list_reminders", "arguments": {}}, {"origin_class": (list), "requires_auth": false}, ..#SINK)
	Do $$$AssertEquals(..Sentence(sc), "<OK>", "control: a safe, read-only built-in call is allowed in an untrusted turn")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Begin("tool", "untrusted")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).IsPoll(), 1, "the context of kind tool and provenance untrusted is a poll's")
	Kill ^||ZzProbeSink
	Set sc = $ClassMethod(gate, "Check", "list_reminders", {"id": "call_id", "name": "list_reminders", "arguments": {}}, {"origin_class": (list), "requires_auth": false}, ..#SINK)
	Do $$$AssertEquals(..Sentence(sc), $Parameter(gate, "FAILED"), "the same call is denied with FAILED in a poll's")
	Do $$$AssertEquals(..SinkCalls(), 0, "and reports no step")
	Set sc = $ClassMethod(gate, "Check", "set_reminder", {"id": "call_id", "name": "set_reminder", "arguments": {}}, {"origin_class": (list), "requires_auth": false}, ..#SINK)
	Do $$$AssertEquals(..Sentence(sc), $Parameter(gate, "UNTRUSTED"), "a safe call that is not read-only is denied with UNTRUSTED, as in any untrusted turn")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ..Begin("tool", "user")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).IsPoll(), 0, "a replay's context (kind tool, provenance user) is not a poll's")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).IsPoll(), 0, "and with no context nothing is a poll")
}

/// A read-only proxy call in a poll's context runs with no grant (see the class description).
Method TestPollNoGrant()
{
	Do ..Setup()
	Do ..Begin("tool", "untrusted")
	Do ..Seed("zz_lookup")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).GrantSource(), "", "the context holds no grant")
	Set manager = ..Manager()
	Set mark = $ClassMethod(..#MOCK, "Requests", ..Port).%Size()
	Set answer = ""
	Set thrown = ""
	Try {
		Set answer = manager.ExecuteTool("call_mcp_tool", {"server": (..#SERVER), "tool": "zz_lookup", "arguments": {"id": "T-1"}})
	} Catch exception {
		Set thrown = ##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString())
	}
	Do $$$AssertEquals(thrown, "", "the call is allowed with no grant")
	Do $$$AssertTrue($IsObject(answer) && (answer.%Get("value") [ "The mock ran zz_lookup"), "and gives the tool's result")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Calls", ..Port, "zz_lookup"), 1, "the mock logged one tools/call")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).ReplayRefusal(), "", "the proxy noted no refusal")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Current().Tainted, 1, "the turn is tainted by the result")
	Set steps = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Records()
	Do $$$AssertEquals(steps.%Size() _ "|" _ steps.%Get(0).label _ "|" _ steps.%Get(0).status, "1|Running zz_lookup on " _ ..#SERVER _ "|ok", "one step is recorded, named for the tool and the server")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Requests", ..Port).%Size() - mark, 4, "from OcuTalon's client: initialize, the notification, tools/list and tools/call")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).End()
}

/// A risky tool's proxy call in a poll's context is denied (see the class description).
Method TestPollRiskyDenied()
{
	Do ..Setup()
	Do ..Begin("tool", "untrusted")
	Do ..Seed("zz_delete_ticket")
	Set manager = ..Manager()
	Set held = ..Held()
	Set thrown = ""
	Try {
		Do manager.ExecuteTool("call_mcp_tool", {"server": (..#SERVER), "tool": "zz_delete_ticket", "arguments": {"id": "T-1"}})
	} Catch exception {
		Set thrown = exception.DisplayString()
	}
	Do $$$AssertTrue(thrown [ "ToolAccessDenied", "ExecuteTool raises ToolAccessDenied")
	Do $$$AssertTrue(thrown [ $Parameter("OcuTalon.Bridge.Policy.Gate", "UNTRUSTED"), "with the UNTRUSTED sentence")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Calls", ..Port, "zz_delete_ticket"), 0, "the mock got no tools/call")
	Set steps = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Records()
	Do $$$AssertEquals(steps.%Size() _ "|" _ steps.%Get(0).status, "1|denied", "the step is denied")
	Do $$$AssertEquals(..Held(), held, "and nothing was held: no approval request was raised for it")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).End()
}

/// SeedMcp (see the class description).
Method TestSeedMcpKeys()
{
	Set context = "OcuTalon.Bridge.Context"
	Do $$$AssertStatusNotOK($ClassMethod(context, "SeedMcp", "zz", "mcp:zz", "zz_lookup", "zzfp"), "with no context the seed is an error status")
	Do ..Begin("tool", "untrusted")
	Do $$$AssertEquals($ClassMethod(context, "IsPoll"), 1, "a context of kind tool and provenance untrusted is a poll's")
	Do $$$AssertStatusOK($ClassMethod(context, "SeedMcp", "zz", "mcp:zz", "zz_lookup", "zzfp"), "a usable seed is accepted")
	Do $$$AssertEquals($ClassMethod(context, "McpFingerprint", "mcp:zz", "zz_lookup"), "zzfp", "and the map holds the fingerprint")
	Set long = $Justify("", $Parameter(context, "MCPKEYMAX") + 1)
	Set long = $Translate(long, " ", "x")
	For case = $ListBuild("", "mcp:zz", "zz_lookup", "zzfp"), $ListBuild("zz", "zz", "zz_lookup", "zzfp"), $ListBuild("zz", "mcp:zz", "", "zzfp"), $ListBuild("zz", "mcp:zz", "zz_lookup", ""), $ListBuild(long, "mcp:zz", "zz_lookup", "zzfp"), $ListBuild("zz", "mcp:zz", long, "zzfp") {
		Do $$$AssertStatusNotOK($ClassMethod(context, "SeedMcp", $List(case, 1), $List(case, 2), $List(case, 3), $List(case, 4)), "a seed with the server '" _ $Extract($List(case, 1), 1, 6) _ "', the toolref '" _ $Extract($List(case, 2), 1, 6) _ "', the tool '" _ $Extract($List(case, 3), 1, 6) _ "' and the fingerprint '" _ $List(case, 4) _ "' is refused")
	}
	Do $$$AssertEquals($ClassMethod(context, "McpFingerprint", "mcp:zz", "zz_lookup"), "zzfp", "and a refused seed leaves the map as it was")
}

/// The bridge's own PollCall (see the class description).
Method TestPollCallDefault()
{
	Set word = ##class(OcuTalon.Bridge.Ext.McpServers).PollCall(##class(OcuTalon.Bridge.Ids).NewRef(), .server, .tool, .arguments, .toolref, .fingerprint)
	Do $$$AssertEquals(word _ "|" _ server _ "|" _ tool _ "|" _ arguments _ "|" _ toolref _ "|" _ fingerprint, "invalid|||||", "the base answers invalid with every output empty")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.McpServers).PollCall("", .server), "invalid", "also for no source")
}

/// Poll.Run with OcuTalon's PollCall (see the class description).
Method TestPollRunWords()
{
	Do ..Setup()
	Set source = ..Source("Words", "{""q"":""zzargvalue""}")
	Set host = ##class(OcuTalon.Test.Bridge.Runner).NewRunner(..#AGENT)
	Set adapter = host.Adapter
	Set request = ..NewPoll(source)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Poll).Run(adapter, request, "", .reply), "Poll.Run answers")
	Do $$$AssertTrue($IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply"), "with a Reply")
	Do $$$AssertEquals(reply.FailureText _ "|" _ reply.Text _ "|" _ reply.ToolsRun _ "|" _ reply.Tainted _ "|" _ reply.AgentStepCount, "|The mock ran zz_lookup|1|1|1", "a read-only tool: the answer's text, one tool run, the taint and one step, no failure word")
	Set steps = ##class(%DynamicAbstractObject).%FromJSON(reply.Steps)
	Do $$$AssertEquals(steps.%Get(0).label _ "|" _ steps.%Get(0).status, "Running zz_lookup on " _ ..#SERVER _ "|ok", "the step is labelled for the tool and the server")
	Do $$$AssertEquals(reply.Steps [ "zzargvalue", 0, "and holds no argument value")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active() _ "|" _ ##class(OcuTalon.Bridge.Adapter.StepBuffer).Active(), "0|0", "no context and no step buffer are left behind")
	Set requests = $ClassMethod(..#MOCK, "Requests", ..Port)
	Set methods = ""
	For i = 0:1:requests.%Size() - 1 {
		Set methods = methods _ $Select(methods = "": "", 1: ",") _ requests.%Get(i).method _ ":" _ requests.%Get(i).client
	}
	Do $$$AssertEquals(methods, "initialize:iris,notifications/initialized:iris,tools/list:iris,initialize:iris,notifications/initialized:iris,tools/list:iris,tools/call:iris", "the mock saw the seed listing, then the proxy's initialize, tools/list and tools/call, all from OcuTalon's client")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Calls", ..Port, "zz_lookup"), 1, "one tools/call")
	Set calls = ..Calls()

	Do ..Refuses(adapter, ..NewPoll(##class(OcuTalon.Bridge.Ids).NewRef()), "invalid", "a request whose Ref names no source", calls)
	Set bad = ..NewPoll(source)
	Set bad.Input = "{""source"":""zz""}"
	Do ..Refuses(adapter, bad, "invalid", "an Input that is not a Ref", calls)
	// no longer read-only
	Do ..Classify("zz_lookup", "risky")
	Do ..Refuses(adapter, request, "notreadonly", "a tool classified risky", calls)
	Do ..Classify("zz_lookup", "unclassified")
	Do ..Refuses(adapter, request, "notreadonly", "a tool that is unclassified", calls)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ? AND Tool = ?", ..#SERVER, "zz_lookup")
	Do ..Refuses(adapter, request, "notfound", "a tool with no classification row", calls)
	Do ..Row("zz_lookup", "read-only", ##class(OcuTalon.Bridge.Context).ToolFingerprint(##class(OcuTalon.Mcp.Attach).Toolref(..#SERVER), "zz_lookup", "Looks up a ticket.", {"type": "object", "properties": {"id": {"type": "string"}}}))
	// changed
	Do $ClassMethod(..#MOCK, "Describe", ..Port, "a changed description")
	Do ..Refuses(adapter, request, "changed", "a tool whose live fingerprint is not the classified one", calls)
	Do $ClassMethod(..#MOCK, "Describe", ..Port, "Looks up a ticket.")
	// arguments that are not a JSON object
	Do ..Refuses(adapter, ..NewPoll(..Source("Array", "[1]")), "invalid", "arguments that are a JSON array", calls)
	Do ..Refuses(adapter, ..NewPoll(..Source("Scalar", "7")), "invalid", "arguments that are a JSON number", calls)
	// a refusal of the proxy after the seed listing: the tools/call is held past its bound, and the refusal is a word, never the tool's text
	Do $ClassMethod(..#MOCK, "Call", ..Port, "silent")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Poll).Run(adapter, request, "", .reply), "(call timeout) Poll.Run answers")
	Do $ClassMethod(..#MOCK, "Call", ..Port, "text", "The mock ran zz_lookup")
	Do $$$AssertEquals(reply.FailureText _ "|" _ reply.Text _ "|" _ reply.ToolsRun _ "|" _ reply.AgentStepCount, "timeout||1|1", "(call timeout) a call that the proxy refuses after the listing is the word timeout, with no text, and one step")
	Set calls = ..Calls()
	// the gate's denial: the service role loses the Use permission
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Mcp).Revoke(..#SERVER), "the Use permission is taken away")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Poll).Run(adapter, request, "", .reply), "(denied) Poll.Run answers")
	Do $$$AssertEquals(reply.FailureText _ "|" _ reply.Text _ "|" _ reply.ToolsRun, "denied||1", "(denied) the gate's denial is the word denied")
	Do $$$AssertEquals(..Calls(), calls, "(denied) and no tools/call was made")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Mcp).Grant(..#SERVER), "the permission is given again")
	// a refusal of the proxy after the listing: the tool changes between the seed and the call is not made here; the server stops instead
	Do $ClassMethod(..#MOCK, "Silence", ..Port, 20)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Poll).Run(adapter, request, "", .reply), "(timeout) Poll.Run answers")
	Do $$$AssertEquals(reply.FailureText _ "|" _ reply.ToolsRun, "timeout|0", "(timeout) a server that answers nothing is the word timeout, with no tool run")
	Do $ClassMethod(..#MOCK, "Speak", ..Port)
	Do $ClassMethod(..#MOCK, "Stop", ..Port)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Poll).Run(adapter, request, "", .reply), "(unreachable) Poll.Run answers")
	Do $$$AssertEquals(reply.FailureText _ "|" _ reply.ToolsRun _ "|" _ reply.Steps, "unreachable|0|", "(unreachable) a server that is not there is the word unreachable, with no tool run and no step")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active() _ "|" _ ##class(OcuTalon.Bridge.Adapter.StepBuffer).Active(), "0|0", "no context and no step buffer are left behind")
}

/// Runs the poll and asserts that it ended with the word, with no tool run, no step and no new tools/call.
Method Refuses(adapter As OcuTalon.Bridge.Adapter.Agent, request As OcuTalon.Bridge.Msg.Request, word As %String, label As %String, calls As %Integer) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Poll).Run(adapter, request, "", .reply), "(" _ word _ ") Poll.Run answers")
	Do $$$AssertEquals(reply.FailureText _ "|" _ reply.Text _ "|" _ reply.ToolsRun _ "|" _ reply.Steps, word _ "||0|", label _ ": the word " _ word _ ", no text, no tool run and no step")
	Do $$$AssertEquals(..Calls(), calls, label _ ": the mock got no new tools/call")
}

/// The approval requests of the tool zz_delete_ticket that exist.
ClassMethod Held() As %Integer [ Private ]
{
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE ToolName = ?", "zz_delete_ticket")
	Do rows.%Next()
	Quit +rows.%GetData(1)
}

/// The tools/call requests that the mock has logged so far.
Method Calls() As %Integer [ Private ]
{
	Quit $ClassMethod(..#MOCK, "Calls", ..Port, "zz_lookup")
}

/// Sets the classification of the fixture tool.
Method Classify(tool As %String, classification As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(..#SERVER, tool)
	Set row.Classification = classification
	Do ..Ok(row.%Save(), "the tool " _ tool _ " is classified " _ classification)
}

/// A source row of the fixture server, tool zz_lookup, of a new session ref; its Ref.
Method Source(name As %String, arguments As %String) As %String [ Private ]
{
	Do ..Ok(##class(OcuTalon.Watch.Ops).SetSource(##class(OcuTalon.Bridge.Ids).NewRef(), ..#SERVER, "zz_lookup", name, arguments, 15, "zzpoll", .ref, .created), "the source row " _ name)
	// not due, so that the production's own Checks never polls the fixture row
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET NextDueAt = ? WHERE Ref = ?", "2099-01-01T00:00:00Z", ref)
	Quit ref
}

/// A request of kind tool and provenance untrusted for the source.
Method NewPoll(source As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "tool"
	Set request.Provenance = "untrusted"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.Channel = "system"
	Set request.Summary = "Source poll"
	Set request.Input = {"source": (source)}.%ToJSON()
	Quit request
}

/// Begins a context of the kind and provenance, in this process.
Method Begin(kind As %String, provenance As %String) [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = provenance
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.Channel = "system"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, "", "TriageAgent"), "a context of kind " _ kind _ " and provenance " _ provenance _ " begins")
}

/// Seeds the poll's map with the fixture tool, as PollCall gives it.
Method Seed(tool As %String) As %String [ Private ]
{
	Set toolref = ##class(OcuTalon.Mcp.Attach).Toolref(..#SERVER)
	Set row = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(..#SERVER, tool)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).SeedMcp(..#SERVER, toolref, tool, row.Fingerprint), "the map is seeded with " _ tool)
	Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).Start(0)
}

/// A manager that holds only the proxy toolset, as the adapter's PollManager builds it, on a shadow runner.
Method Manager() As %RegisteredObject [ Private ]
{
	Set host = ##class(OcuTalon.Test.Bridge.Runner).NewRunner(..#AGENT)
	Do $$$AssertStatusOK(host.Adapter.PollManager(.manager), "PollManager builds the manager, with no agent built")
	Do $$$AssertEquals($IsObject(host.Adapter.Agent), 0, "and the adapter has built no agent")
	Quit manager
}

/// A Decide shadow with the settings of a runner-less process, and the probe sink as its host sink.
Method Recorder() As OcuTalon.Test.Bridge.ZzDecide [ Private ]
{
	Set recorder = ##class(OcuTalon.Test.Bridge.ZzDecide).%New("Decide")
	Set recorder.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set recorder.HostSinkClass = ..#SINK
	Set recorder.TimerSeconds = 60
	Set recorder.%SessionId = 4302
	Quit recorder
}

/// The Decision rows of the item or the DecisionRef.
ClassMethod Rows(itemId As %String, decisionRef As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ? OR Ref = ?", itemId, decisionRef)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The event types that the probe sink recorded, comma-separated.
ClassMethod SinkTypes() As %String [ Private ]
{
	Set types = ""
	For n = 1:1:+$Get(^||ZzProbeSink) {
		Set types = types _ $Select(types = "": "", 1: ",") _ $List($Get(^||ZzProbeSink(n)), 1)
	}
	Quit types
}

/// The number of events that the probe sink recorded.
ClassMethod SinkCalls() As %Integer [ Private ]
{
	Quit +$Get(^||ZzProbeSink)
}

/// "<OK>" for an allowed call, "<code ...>" for a status that is no ToolAccessDenied, and otherwise the sentence of the denial.
ClassMethod Sentence(sc As %Status) As %String [ Private ]
{
	If $$$ISOK(sc) Quit "<OK>"
	Set codes = $SYSTEM.Status.GetErrorCodes(sc)
	If codes '= "<%AICore>ToolAccessDenied" Quit "<code " _ codes _ ">"
	Set text = $SYSTEM.Status.GetOneStatusText(sc)
	Set prefix = "Tool access denied: "
	Quit $Select($Extract(text, 1, $Length(prefix)) = prefix: $Extract(text, $Length(prefix) + 1, *), 1: text)
}

}
