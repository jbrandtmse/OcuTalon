/// The approval of a held MCP call, through the production's own runner job (Story 22.4; AD-2, AD-6, AD-10, AD-11, AD-17, AD-21, AD-25, AD-30). THESE TESTS RUN IN THROWAWAY STACKS AND IN CI
/// ONLY (Rule 21): they need the running production and the CI mock (RunnerFixture ReadyReason), and they use the fixtures of OcuTalon.Test.Mcp.JobFixture (the server zzmcp: the loopback MCP
/// mock that checks a header, a wallet secret, the Config Store entry, the row, the Use permission, the tool rows zz_lookup and zz_delete_ticket) with a fixture session as the owner of the
/// requests. Each test removes what it made, whether it passed or failed, and asserts that none is left and that the secret shows nowhere.
///   - TestHeldThenReplayed (the end-to-end AC, DW-1220): a user's turn of the scenario mcp-held-replay calls the risky zz_delete_ticket natively. The gate holds it as one tool_call row in native
///     form (the tool, the canonical arguments, the server's toolref, the tool's fingerprint, the runner, the owner), the model gets HELD and the mock logs no tools/call. Approval.Answer
///     approves it: the replay runs call_mcp_tool on the replay manager and the mock logs exactly one tools/call, from OcuTalon's own client (client iris, after one initialize, the
///     notification and one tools/list that checked the fingerprint) and none from AI Hub's client, with arguments byte-equal to the row's; the row ends done, one MCP called entry and one
///     Action entry exist, the next turn's note names the tool done, and no reply, column, event, notice or log holds the result text or the secret;
///   - TestChangedBeforeReplay: a risky zz_lookup that the model calls through call_mcp_tool is held in the same native form; the mock then changes the tool's description (case 1) or its
///     input schema (case 2); after the approval the mock logs no tools/call, the row ends failed with the result changed, one MCP refused entry says changed, and the owner gets the notice
///     mcp.replayToolChanged;
///   - TestSecondReplay: a second replay of a finished Ref is refused at the start, nothing runs and the mock's tools/call count stays at one; TestNoGrant: call_mcp_tool on the replay's governed
///     manager in a replay context that has no grant is denied and the mock gets no tools/call;
///   - TestRemovedWhilePending: RemoveMcpServer cancels the pending request of the server through Approval.Cancel: state cancelled, one Approval entry that names the admin, the approval event
///     reaches the owner's stream, and a later Answer approves nothing and runs nothing; a second cancel is a no-op. TestRemovedWhileApproved: an approved request whose server was removed
///     before the replay fails at the gate and the server gets no request; TestUnknownToolref: an approved request whose toolref the host's ServerOf does not know fails with no call;
///   - TestUnclassifiedReplays: the exact call approved for an unclassified tool runs once; TestRefusedReplayFails: a call that the server answers with an error ends the row failed, never done;
///     TestNoFingerprintNoReplay: an approved MCP request that holds no fingerprint is not replayed;
///   - TestNoFingerprintNoHold: a call of an MCP tool that the turn's map does not hold is denied FAILED and holds nothing;
///   - TestDemoRefusesTheReplay (the Contest Planner's online-demo rule): with the online-demo flag on, an approved MCP request does not run: it fails before any outbound request.
Class OcuTalon.Test.Mcp.Approval Extends OcuTalon.Test.Mcp.JobFixture
{

/// The IRIS user who answers: it holds OcuTalonUser.
Parameter ANSWERER = "ocutalon";

/// The scenarios of the CI mock.
Parameter HELDSCENARIO = "mcp-held-replay";

Parameter PROXYSCENARIO = "mcp-proxy-call";

/// The Ref of the fixture session that owns the requests of the test.
Property SessionRef As %String;

/// The Refs of the approval requests that the test made, comma-separated.
Property Requests As %String(MAXLEN = "");

/// The ID of the newest message header when the test began its turn (a diagnosis only).
Property HeaderStart As %Integer;

/// The Refs of the Turn rows that the test made, comma-separated.
Property Turns As %String(MAXLEN = "");

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
	Set refs = ..Requests
	For i = 1:1:$Length(refs, ",") {
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen($Piece(refs, ",", i))
		If $IsObject(row) Do ##class(OcuTalon.Bridge.Data.ApprovalRequest).%DeleteId(row.%Id())
	}
	Set ..Requests = ""
	If ..SessionRef '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..SessionRef _ $Select(..Turns '= "": "," _ ..Turns, 1: ""))
	Set ..SessionRef = ""
	Set ..Turns = ""
	Quit ##super(testname)
}

/// The end-to-end AC and DW-1220 (see the class description).
Method TestHeldThenReplayed()
{
	If '..Prepare() Quit
	Set toolref = ##class(OcuTalon.Mcp.Attach).Toolref(..#SERVER)
	Set schema = {"type": "object", "properties": {"id": {"type": "string"}}}
	Set fingerprint = ##class(OcuTalon.Bridge.Context).ToolFingerprint(toolref, "zz_delete_ticket", "Deletes a ticket.", schema)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set eventMark = $ClassMethod(..#FIXTURE, "EventMark")
	Set ..HeaderStart = ..HeaderMark()
	Set before = $ClassMethod(..#MOCK, "Requests", ..Port).%Size()

	// the hold
	Set sc = ..AskAs("Delete ticket T-1. [[mock:" _ ..#HELDSCENARIO _ "]]", .reply, .requests, .itemRef)
	Set ..ItemIds = ..ItemIds _ $ListBuild(itemRef)
	Do $$$AssertStatusOK(sc, "the turn of " _ ..#HELDSCENARIO _ " is answered by the production's job")
	If '$IsObject(reply) || 'reply.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(reply.Text, "The ticket deletion was held for approval.", "the turn is answered with the second reply of the scenario")
	Set ref = ..PendingRef()
	Do $$$AssertTrue(ref '= "", "exactly one request was raised for the owner")
	If ref = "" Quit
	Set row = ..Fresh(ref)
	Do $$$AssertEquals(row.Kind _ "|" _ row.State _ "|" _ row.ToolName _ "|" _ row.ToolArguments, "tool_call|pending|zz_delete_ticket|{""id"":""T-1""}", "one pending tool_call request holds the tool and its canonical arguments")
	Do $$$AssertEquals(row.ToolSource _ "|" _ row.Runner _ "|" _ row.OwnerRef, toolref _ "|" _ ..#RUNNER _ "|" _ ..SessionRef, "the server's toolref, the runner that held it and the owner")
	Do $$$AssertEquals(row.ToolFingerprint, fingerprint, "and the fingerprint of the tool at the hold")
	Do $$$AssertEquals(row.DryRun _ row.ResultTarget _ row.IncidentRef, "", "with no dry run, no result target and no incident")
	If requests.%Size() = 2 {
		Set results = $ClassMethod(..#FIXTURE, "ToolResults", requests.%Get(1))
		Do $$$AssertTrue($ListToString(results, "|") [ $Parameter("OcuTalon.Bridge.Policy.Gate", "HELD"), "the model got HELD: " _ $ListToString(results, "|"))
	} Else {
		Do $$$AssertEquals(requests.%Size(), 2, "the mock got the request and the one that follows the tool call")
	}
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Calls", ..Port, "zz_delete_ticket"), 0, "the MCP mock logged no tools/call before the approval")

	// the approval
	Set answered = ..Approve(ref, row.OwnerRef)
	Do $$$AssertEquals(answered, "done", "Answer approves the request")
	Set state = ..WaitFinished(ref, 90)
	Do $$$AssertEquals(state, "done", "the replay ends the row done" _ $Select(state '= "done": ": " _ ..Diagnosis(ref, eventMark), 1: ""))
	Set row = ..Fresh(ref)
	Do $$$AssertEquals(row.Result _ "|" _ (row.FinishedAt '= ""), "done|1", "with the result done and the time it finished")
	Do $$$AssertEquals(row.ToolArguments _ "|" _ row.ToolFingerprint, "{""id"":""T-1""}|" _ fingerprint, "the stored call is as it was held")
	Set methods = ""
	Set args = ""
	Set native = 0
	Set iterator = $ClassMethod(..#MOCK, "Requests", ..Port).%GetIterator()
	While iterator.%GetNext(.index, .request) {
		If index < before Continue
		If (request.client = "iris") && (request.auth = "matched") {
			Set methods = methods _ $ListBuild(request.method)
			If request.method = "tools/call" Set args = args _ $ListBuild(request.tool _ ":" _ request.arguments)
		} ElseIf request.method = "tools/call" {
			Set native = native + 1
		}
	}
	Do $$$AssertEquals($ListToString(methods), "initialize,notifications/initialized,tools/list,tools/call", "the mock got one initialize, the notification, one tools/list and one tools/call from OcuTalon's own client (client iris) with the credential header; the unauthenticated probes of the runner's build are not among them")
	Do $$$AssertEquals(native, 0, "and no tools/call from AI Hub's client (DW-1220)")
	Do $$$AssertEquals($ListToString(args, "|"), "zz_delete_ticket:" _ row.ToolArguments, "the tools/call carries the tool and arguments byte-equal to the row's")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Calls", ..Port, "zz_delete_ticket"), 1, "exactly one")

	// the audit trail
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "MCP", "MCP", ..#SERVER)
	Do $$$AssertEquals(entries.%Size(), 1, "one MCP audit entry exists")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.change _ "|" _ entries.%Get(0).data.tool _ "|" _ entries.%Get(0).data.outcome, "called|zz_delete_ticket|ok", "it says called, the tool and ok")
	Set actions = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", ref)
	Do $$$AssertEquals(actions.%Size(), 1, "one Action entry names the request")
	If actions.%Size() = 1 Do $$$AssertEquals(actions.%Get(0).data.action _ "|" _ actions.%Get(0).data.result _ "|" _ actions.%Get(0).data.target, "zz_delete_ticket|done|" _ toolref, "it holds the tool, done and the toolref")
	Set approvals = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Approval", "Approval", ref, , 3)
	Kill changes
	Set iterator = approvals.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set changes(entry.data.change) = ""
	}
	Set names = ""
	Set name = ""
	For {
		Set name = $Order(changes(name))
		Quit:name=""
		Set names = names _ $ListBuild(name)
	}
	Do $$$AssertEquals($ListToString(names, ",") _ "|" _ approvals.%Size(), "answered,finished,started|3", "the request has three Approval entries: answered, started and finished")

	// the agent's own manager holds no MCP server and no proxy once the replay is over
	Set sc = $ClassMethod(..#FIXTURE, "Send", ..#RUNNER, ##class(OcuTalon.Bridge.Msg.ToolInventory).%New(), .response)
	Do $$$AssertStatusOK(sc, "the runner answers a ToolInventory request")
	If $IsObject(response) && response.%IsA("Ens.StringResponse") {
		Set names = ""
		Set iterator = {}.%FromJSON(response.StringValue).tools.%GetIterator()
		While iterator.%GetNext(, .tool) {
			Set names = names _ $ListBuild(tool.name)
		}
		Do $$$AssertEquals($ListFind(names, "call_mcp_tool") + $ListFind(names, "zz_lookup") + $ListFind(names, "zz_delete_ticket"), 0, "the agent's own manager holds neither the proxy nor a tool of the MCP server: " _ $ListToString(names))
	} Else {
		Do $$$AssertTrue(0, "the answer is an Ens.StringResponse")
	}

	// the next turn's note, and what shows nowhere
	Set turn = ##class(OcuTalon.Test.Data.Fixture).Turn(..SessionRef, ##class(OcuTalon.Bridge.Time).PlusSeconds(row.FinishedAt, 1), "queued", "zz next", "zzc" _ $Random(1000000))
	Set ..Turns = turn
	Set note = ##class(OcuTalon.Core.Conversation).ToolNote(##class(OcuTalon.Data.Turn).RefIndexOpen(turn))
	Do $$$AssertTrue($Piece(note, $Char(10), 2) [ "- zz_delete_ticket: done at ", "the next turn's note names the tool done: " _ note)
	Do $$$AssertEquals($Find(note, "The mock ran"), 0, "and holds no result text")
	Set text = "The mock ran zz_delete_ticket"
	Do $$$AssertEquals(..Shows(text, eventMark, row), "", "the tool's result text shows in no column, event, notice, audit entry or log row")
	Do $$$AssertEquals(..Shows(..Secret, eventMark, row), "", "nor does the secret")
}

/// The changed tool (see the class description), in two cases on one server.
Method TestChangedBeforeReplay()
{
	If '..Prepare() Quit
	Set toolref = ##class(OcuTalon.Mcp.Attach).Toolref(..#SERVER)
	Set schema = {"type": "object", "properties": {"id": {"type": "string"}}}
	Set fingerprint = ##class(OcuTalon.Bridge.Context).ToolFingerprint(toolref, "zz_lookup", "Looks up a ticket.", schema)
	// the admin classified zz_lookup risky, so the model's call is held
	Set row = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(..#SERVER, "zz_lookup")
	Set row.Classification = "risky"
	Do ..Ok(row.%Save(), "zz_lookup is classified risky")
	For case = "description", "schema" {
		Set label = "case " _ case _ ": "
		Do $ClassMethod(..#MOCK, "Describe", ..Port, "Looks up a ticket.")
		Do $ClassMethod(..#MOCK, "Shape", ..Port, "{""type"": ""object"", ""properties"": {""id"": {""type"": ""string""}}}")
		Set row.Fingerprint = fingerprint
		Do ..Ok(row.%Save(), label _ "the tool's row holds the fingerprint of the tool as it is")
		Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set before = $ClassMethod(..#MOCK, "Requests", ..Port).%Size()
		Set sc = ..AskAs("Look up ticket 1. [[mock:" _ ..#PROXYSCENARIO _ "]]", .reply, .requests, .itemRef)
		Set ..ItemIds = ..ItemIds _ $ListBuild(itemRef)
		Do $$$AssertStatusOK(sc, label _ "the turn of " _ ..#PROXYSCENARIO _ " is answered")
		Set ref = ..PendingRef()
		Do $$$AssertTrue(ref '= "", label _ "the direct call of the proxy is held as one request")
		If ref = "" Quit
		Set request = ..Fresh(ref)
		Do $$$AssertEquals(request.ToolName _ "|" _ request.ToolArguments _ "|" _ request.ToolSource _ "|" _ request.ToolFingerprint, "zz_lookup|{""id"":""1""}|" _ toolref _ "|" _ fingerprint, label _ "it is held in the native form of the tool's call")
		If case = "description" {
			Do $ClassMethod(..#MOCK, "Describe", ..Port, "Looks up a ticket, differently.")
		} Else {
			Do $ClassMethod(..#MOCK, "Describe", ..Port, "Looks up a ticket.")
			Do $ClassMethod(..#MOCK, "Shape", ..Port, "{""type"": ""object"", ""properties"": {""id"": {""type"": ""number""}}}")
		}
		// the admin classifies the changed tool again before the approval: its row now holds the new fingerprint, which the request was not made at
		Set changed = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(..#SERVER, "zz_lookup")
		Set changed.Fingerprint = $Select(case = "description": ##class(OcuTalon.Bridge.Context).ToolFingerprint(toolref, "zz_lookup", "Looks up a ticket, differently.", schema), 1: ##class(OcuTalon.Bridge.Context).ToolFingerprint(toolref, "zz_lookup", "Looks up a ticket.", {"type": "object", "properties": {"id": {"type": "number"}}}))
		Do ..Ok(changed.%Save(), label _ "the tool's row holds the new fingerprint")
		Set callsBefore = $ClassMethod(..#MOCK, "Calls", ..Port, "zz_lookup")
		Do $$$AssertEquals(..Approve(ref, request.OwnerRef), "done", label _ "Answer approves the request")
		Do $$$AssertEquals(..WaitFinished(ref, 90), "failed", label _ "the replay ends the row failed")
		Set request = ..Fresh(ref)
		Do $$$AssertEquals(request.Result, "changed", label _ "with the result changed")
		Do $$$AssertEquals($ClassMethod(..#MOCK, "Calls", ..Port, "zz_lookup"), callsBefore, label _ "the mock logged no tools/call: nothing was run")
		Set native = 0
		Set iterator = $ClassMethod(..#MOCK, "Requests", ..Port).%GetIterator()
		While iterator.%GetNext(.index, .logged) {
			If (index >= before) && (logged.method = "tools/call") Set native = native + 1
		}
		Do $$$AssertEquals(native, 0, label _ "from no client")
		Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "MCP", "MCP", ..#SERVER)
		Do $$$AssertEquals(entries.%Size(), 1, label _ "one MCP audit entry exists")
		If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.change _ "|" _ entries.%Get(0).data.tool _ "|" _ entries.%Get(0).data.outcome, "refused|zz_lookup|changed", label _ "it says refused, the tool and changed")
		Do $$$AssertEquals(..ResultNotice(ref), 1, label _ "the owner gets a result notice for the request (the bridge sink's mcp.replayToolChanged, R1)")
	}
	Do $ClassMethod(..#MOCK, "Describe", ..Port, "Looks up a ticket.")
	Do $ClassMethod(..#MOCK, "Shape", ..Port, "{""type"": ""object"", ""properties"": {""id"": {""type"": ""string""}}}")
}

/// A second replay of a finished Ref (see the class description).
Method TestSecondReplay()
{
	If '..Prepare() Quit
	Set ref = ..Approved("zz_delete_ticket", "{""id"":""T-2""}")
	If ref = "" Quit
	Do $$$AssertEquals(..Replay(ref, .reply), "done", "the replay of the approved request ends the row done")
	Set calls = $ClassMethod(..#MOCK, "Calls", ..Port, "zz_delete_ticket")
	Do $$$AssertEquals(calls, 1, "the mock logged one tools/call")
	Set finished = ..Fresh(ref).FinishedAt
	Set sc = ..Send(ref, .again)
	Do $$$AssertStatusOK(sc, "a second replay request is answered")
	Do $$$AssertTrue($IsObject(again) && (again.ToolsRun = 0) && (again.FailureText '= ""), "with a failure and no tool run: the start is refused")
	Set row = ..Fresh(ref)
	Do $$$AssertEquals(row.State _ "|" _ row.Result _ "|" _ row.FinishedAt, "done|done|" _ finished, "the row is as it was")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Calls", ..Port, "zz_delete_ticket"), 1, "and the mock's tools/call count stays at one")
}

/// call_mcp_tool in a replay context with no grant (see the class description).
Method TestNoGrant()
{
	If '..Prepare() Quit
	Set before = $ClassMethod(..#MOCK, "Requests", ..Port).%Size()
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "tool"
	Set request.Provenance = "user"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = ..SessionRef
	Set request.Channel = "system"
	Do ..Ok(##class(OcuTalon.Bridge.Context).Begin(request, "", ..#RUNNER), "a replay context begins, and no grant is built")
	Set manager = ##class(%AI.ToolMgr).%New()
	Do ..Ok(manager.RegisterToolSet("OcuTalon.Tools.McpProxy"), "a manager holds the proxy toolset")
	Do ..Ok(manager.SetAuthPolicy(##class(OcuTalon.Bridge.Policy.Gate).%New()), "governed by the gate")
	Do ..Ok(manager.SetAuditPolicy(##class(OcuTalon.Bridge.Policy.StepAudit).%New()), "and the step audit")
	Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).Start(0)
	Set thrown = ""
	Set answer = ""
	Try {
		Set answer = manager.ExecuteTool("call_mcp_tool", {"server": (..#SERVER), "tool": "zz_delete_ticket", "arguments": {"id": "T-3"}})
	} Catch exception {
		Set thrown = ##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString())
	}
	Set text = $Select($IsObject(answer): answer.%ToJSON(), 1: "")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).End()
	Set denial = $Parameter("OcuTalon.Bridge.Policy.Gate", "FAILED")
	Set unregistered = $Parameter("OcuTalon.Bridge.Policy.Gate", "UNREGISTERED")
	Do $$$AssertTrue((thrown [ "Tool access denied") || (text [ "Tool access denied") || (text [ denial) || (text [ unregistered), "ToolAccessDenied: " _ $Extract(thrown _ text, 1, 200))
	Do $$$AssertTrue($Find(text, "The mock ran") = 0, "no result of the tool")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Requests", ..Port).%Size(), before, "the mock got no request at all")
}

/// The removal of a server with a pending request (see the class description).
Method TestRemovedWhilePending()
{
	If '..Prepare() Quit
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set sc = ..AskAs("Delete ticket T-1. [[mock:" _ ..#HELDSCENARIO _ "]]", .reply, .requests, .itemRef)
	Set ..ItemIds = ..ItemIds _ $ListBuild(itemRef)
	Set ref = ..PendingRef()
	Do $$$AssertTrue(ref '= "", "the call is held as one pending request")
	If ref = "" Quit
	Set owner = ..Fresh(ref).OwnerRef
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(..SessionRef, "approval", 1, 20).%Size() > 0, 1, "the raised event reached the owner's stream")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(..SessionRef, "approval").%Size()
	Set result = ..RemoveServer()
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "1|removed", "RemoveMcpServer removes the server")
	Do $$$AssertEquals(..Fresh(ref).State, "cancelled", "the pending request is cancelled")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Approval", "Approval", ref, , 1)
	Do $$$AssertEquals(entries.%Size(), 1, "one Approval entry exists for it")
	If entries.%Size() = 1 {
		Set data = entries.%Get(0).data
		Do $$$AssertEquals(data.change _ "|" _ data.to _ "|" _ data.irisUser _ "|" _ data.channel, "cancelled|cancelled|" _ ..#ANSWERER _ "|web", "it says cancelled and names the admin and the web channel")
	}
	Set after = ##class(OcuTalon.Test.Core.Observe).Events(..SessionRef, "approval", events + 1, 20)
	Do $$$AssertTrue(after.%Size() > events, "approval.cancelled reached the owner's stream")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(ref, "approve", "web", ..#ANSWERER, owner, .winner), "not_found", "a later Answer approves nothing: not_found")
	Do $$$AssertEquals(..Fresh(ref).State, "cancelled", "the request is still cancelled")
	Set sc = ##class(OcuTalon.Bridge.Approval).Cancel(ref)
	Do $$$AssertStatusNotOK(sc, "cancelling it again is refused")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Approval", "Approval", ref).%Size(), 1, "and adds no second entry")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Calls", ..Port, "zz_delete_ticket"), 0, "nothing ran")
}

/// An approved request whose server was removed before the replay (see the class description).
Method TestRemovedWhileApproved()
{
	If '..Prepare() Quit
	Set ref = ..Approved("zz_delete_ticket", "{""id"":""T-4""}")
	If ref = "" Quit
	Set result = ..RemoveServer()
	Do $$$AssertEquals(result.Ok _ "|" _ result.Outcome, "1|removed", "the server is removed")
	Do $$$AssertEquals(..Fresh(ref).State, "approved", "the approved request is not cancelled: only a pending one can be")
	Set before = $ClassMethod(..#MOCK, "Requests", ..Port).%Size()
	Do $$$AssertEquals(..Replay(ref, .reply), "failed", "the replay ends the row failed: the gate denies the call because the server is not registered")
	Set row = ..Fresh(ref)
	Do $$$AssertEquals(row.Result, "failed", "with the result failed")
	Do $$$AssertEquals(..Credentialed(before), 0, "no request with the credential, and no tools/call, went to any server")
}

/// An approved request whose toolref the host does not know (condition 4): it fails with no call.
Method TestUnknownToolref()
{
	If '..Prepare() Quit
	Set ref = ..Approved("zz_delete_ticket", "{""id"":""T-5""}", "mcp:zzunknown")
	If ref = "" Quit
	Do $$$AssertEquals(..Replay(ref, .reply), "failed", "the replay ends the row failed")
	Do $$$AssertTrue($IsObject(reply) && (reply.ToolsRun = 0), "no call was made")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Calls", ..Port, "zz_delete_ticket"), 0, "and the server got no tools/call (the runner's own attach of the registered server is the only traffic)")
}

/// A replayed request whose tool has no classification of the admin (Story 22.4, Decided in-stage 4): the exact call that was approved runs once, because the approved fingerprint and
/// not the classification rules a replay.
Method TestUnclassifiedReplays()
{
	If '..Prepare() Quit
	Set tool = ##class(OcuTalon.Mcp.ToolClassification).ServerToolIndexOpen(..#SERVER, "zz_lookup")
	Set tool.Classification = "unclassified"
	Do ..Ok(tool.%Save(), "zz_lookup is unclassified")
	Set ref = ..Approved("zz_lookup", "{""id"":""1""}", "", "Looks up a ticket.")
	If ref = "" Quit
	Do $$$AssertEquals(..Replay(ref, .reply), "done", "the replay of the approved request ends the row done")
	Do $$$AssertEquals(..Fresh(ref).Result, "done", "with the result done")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Calls", ..Port, "zz_lookup"), 1, "the mock logged exactly one tools/call for the unclassified tool")
}

/// A replay that the proxy refuses for a reason other than a change (Story 22.4): the server answers the call with an error, so the row ends failed with the result failed (never
/// done, and never changed), though the refusal sentence is the tool's answer.
Method TestRefusedReplayFails()
{
	If '..Prepare() Quit
	Set ref = ..Approved("zz_delete_ticket", "{""id"":""T-9""}")
	If ref = "" Quit
	Do $ClassMethod(..#MOCK, "Call", ..Port, "iserror")
	Do $$$AssertEquals(..Replay(ref, .reply), "failed", "the replay ends the row failed")
	Set row = ..Fresh(ref)
	Do $$$AssertEquals(row.Result, "failed", "with the result failed, not done and not changed")
}

/// A request that holds no fingerprint (a row of an MCP tool made before the column existed): it is not replayed, so no call is made (condition 2(e)).
Method TestNoFingerprintNoReplay()
{
	If '..Prepare() Quit
	Set row = ##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow("tool_call", "zz_delete_ticket", "{""id"":""T-8""}", ##class(OcuTalon.Mcp.Attach).Toolref(..#SERVER), ..#RUNNER)
	Set row.OwnerRef = ..SessionRef
	Set sc = ##class(OcuTalon.Test.Bridge.ApprovalRows).Save(row, "approved", 3600, ..#ANSWERER, .ref)
	Do $$$AssertStatusOK(sc, "an approved request with no fingerprint is saved")
	If $$$ISERR(sc) Quit
	Do ..Track(ref)
	Do $$$AssertEquals(..Replay(ref, .reply), "failed", "the replay ends the row failed")
	Do $$$AssertTrue($IsObject(reply) && (reply.ToolsRun = 0), "no tool ran")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Calls", ..Port, "zz_delete_ticket"), 0, "and the server got no tools/call")
}

/// A call whose tool the turn's map does not hold is denied and holds nothing (condition 2(e)).
Method TestNoFingerprintNoHold()
{
	If '..Prepare() Quit
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = ..SessionRef
	Set request.TraceRef = ##class(OcuTalon.Data.Session).RefIndexOpen(..SessionRef).TraceRef
	Set request.Channel = "system"
	Do ..Ok(##class(OcuTalon.Bridge.Context).Begin(request, "", ..#RUNNER), "a user's turn begins")
	Set toolref = ##class(OcuTalon.Mcp.Attach).Toolref(..#SERVER)
	Set catalog = [{"tool_ref": (toolref), "name": "zz_lookup", "description": "Looks up a ticket.", "parameters": {"type": "object"}}]
	Do ..Ok(##class(OcuTalon.Bridge.Context).SetMcpTools(catalog, {}.%Set(..#SERVER, toolref, "string")), "the turn's map holds zz_lookup and not zz_delete_ticket")
	Set rows = ..RowCount()
	Set failed = $Parameter("OcuTalon.Bridge.Policy.Gate", "FAILED")
	Set native = ##class(OcuTalon.Bridge.Policy.Gate).Check(toolref, {"id": "call_id", "name": "zz_delete_ticket", "arguments": {"id": "T-6"}}, {}, "")
	Set proxy = ##class(OcuTalon.Bridge.Policy.Gate).Check("call_mcp_tool", {"id": "call_id", "name": "call_mcp_tool", "arguments": {"server": (..#SERVER), "tool": "zz_delete_ticket", "arguments": {"id": "T-6"}}}, {"origin_class": "OcuTalon.Tools.McpCall", "requires_auth": false}, "")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(native) [ failed, "the native call is denied with FAILED: " _ $SYSTEM.Status.GetErrorText(native))
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(proxy) [ failed, "and so is the call through the proxy: " _ $SYSTEM.Status.GetErrorText(proxy))
	Do $$$AssertEquals(..RowCount(), rows, "no request was raised")
}

/// The online-demo rule (see the class description).
Method TestDemoRefusesTheReplay()
{
	If '..Prepare() Quit
	Set ref = ..Approved("zz_delete_ticket", "{""id"":""T-7""}")
	If ref = "" Quit
	Set settings = "OcuTalon.Data.Public.Settings"
	Set saved = $ClassMethod(settings, "Get", "onlineDemo")
	Set before = $ClassMethod(..#MOCK, "Requests", ..Port).%Size()
	Set state = ""
	Set reply = ""
	Try {
		Do ..Ok($ClassMethod(settings, "Set", "onlineDemo", 1), "the online-demo flag is on")
		Do $$$AssertEquals(##class(OcuTalon.Mcp.Attach).ProxyToolSet() _ "|" _ ##class(OcuTalon.Mcp.Proxy).OnlineDemo(), "|1", "the host offers no proxy on the demo")
		Set state = ..Replay(ref, .reply)
	} Catch exception {
		Do $$$AssertTrue(0, "the replay raised: " _ exception.DisplayString())
	}
	Do ..Ok($ClassMethod(settings, "Set", "onlineDemo", saved), "the flag is put back")
	Do $$$AssertEquals(state, "failed", "the approval does not run the call: the row ends failed")
	Do $$$AssertTrue($IsObject(reply) && (reply.ToolsRun = 0), "no tool ran")
	Do $$$AssertEquals(..Credentialed(before), 0, "the mock got no request with the credential and no tools/call: the replay was refused before any outbound request")
}

/// --- helpers ---
/// The request of the Ref, read again from the database (an open instance of the row in this process would otherwise show what it held when it was opened).
Method Fresh(ref As %String) As OcuTalon.Bridge.Data.ApprovalRequest [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If $IsObject(row) Do row.%Reload()
	Quit row
}

/// What the request and the event log show after a replay that did not end done: the row's State and Result and the last warnings and errors since the mark, cut. (A diagnosis for a failure; it holds no secret.)
Method Diagnosis(ref As %String, mark As %Integer) As %String [ Private ]
{
	Set row = ..Fresh(ref)
	Set text = row.State _ "/" _ row.Result
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 12 SourceClass, SourceMethod, Text FROM Ens_Util.Log WHERE ID > ? AND Type IN (2, 3, 4) AND SourceClass NOT [ 'Checks' AND SourceClass NOT [ 'Heartbeat' ORDER BY ID DESC", mark)
	While result.%Next() {
		Set text = text _ " | " _ result.%Get("SourceClass") _ "." _ result.%Get("SourceMethod") _ ": " _ $Extract(##class(OcuTalon.Bridge.Redact).Text(result.%Get("Text")), 1, 200)
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 30 SourceConfigName AS S, TargetConfigName AS T, MessageBodyClassName AS B, Status AS St, IsError AS E FROM Ens.MessageHeader WHERE ID > ? ORDER BY ID DESC", ..HeaderStart)
	While result.%Next() {
		Set text = text _ " || " _ result.%Get("S") _ ">" _ result.%Get("T") _ " " _ $Piece(result.%Get("B"), ".", *) _ " " _ result.%Get("St") _ " " _ result.%Get("E")
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Kind AS K, Outcome AS O, Fallback AS F, FallbackReason AS R, Reasons AS Y FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", ref)
	While result.%Next() {
		Set text = text _ " ## decision " _ result.%Get("K") _ " " _ result.%Get("O") _ " " _ result.%Get("F") _ " " _ result.%Get("R") _ " " _ $Extract(##class(OcuTalon.Bridge.Redact).Text(result.%Get("Y")), 1, 300)
	}
	Quit text
}

/// 1 when the production is ready, the fixtures are made, the key entry points at the CI mock key and the answerer holds OcuTalonUser; otherwise the test fails with the reason.
Method Prepare() As %Boolean [ Private ]
{
	Set reason = $ClassMethod(..#FIXTURE, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet(..#ANSWERER, .roles)
	Set holds = $$$ISOK(sc) && ''$ListFind($ListFromString(roles), "OcuTalonUser")
	Do $$$AssertTrue(holds, "the answerer " _ ..#ANSWERER _ " holds OcuTalonUser")
	If 'holds Quit 0
	Do ..Setup()
	Set ..SessionRef = ##class(OcuTalon.Test.Data.Fixture).Session("zzmcpapprover")
	// the runner builds its agent on its first request, so the restart that PointKeys makes comes after the fixtures: its build attaches the server
	Set ..Pointed = 1
	Set sc = $ClassMethod(..#FIXTURE, "PointKeys", ..#RUNNER)
	Do $$$AssertStatusOK(sc, "the key entry of " _ ..#RUNNER _ " is pointed at the CI mock key variable and the runner is restarted")
	Quit $$$ISOK(sc)
}

/// Sends a user's turn owned by the fixture session to the runner and reads the mock's log for it (RunnerFixture Ask, with an owner).
Method AskAs(text As %String, Output reply As %Persistent, Output requests As %DynamicArray, Output ref As %String) As %Status [ Private ]
{
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", "turn", "user", text, .ref, ..SessionRef)
	Set request.TraceRef = ##class(OcuTalon.Data.Session).RefIndexOpen(..SessionRef).TraceRef
	Set requests = []
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set sc = $ClassMethod(..#FIXTURE, "Send", ..#RUNNER, request, .reply)
	If $$$ISOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries)) Set requests = $ClassMethod(..#FIXTURE, "FindRequests", entries, ref)
	Quit sc
}

/// The Ref of the one request of the owner that the test has not tracked yet, tracked for the clean-up; "" when there is none or more than one.
Method PendingRef() As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE OwnerRef = ?", ..SessionRef)
	Set refs = ""
	While result.%Next() {
		If '$ListFind($ListFromString(..Requests, ","), result.%Get("Ref")) Set refs = refs _ $ListBuild(result.%Get("Ref"))
	}
	If $ListLength(refs) '= 1 Quit ""
	Set ref = $List(refs, 1)
	Do ..Track(ref)
	Quit ref
}

/// Tracks the Ref for the clean-up (the holds are ended by Test.Bridge.Approval Clean, the rows by OnAfterOneTest).
Method Track(ref As %String) [ Private ]
{
	Set ..Requests = ..Requests _ $Select(..Requests = "": "", 1: ",") _ ref
	Set ^OcuTalonTest("Approval", "refs", ref) = ""
}

/// Answers the request approved through Approval.Answer, as the web, Telegram and the phone do; the result of Answer.
Method Approve(ref As %String, owner As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Approval).Answer(ref, "approve", "web", ..#ANSWERER, owner, .winner)
}

/// The State of the request once it is done or failed (polled up to the seconds), else the state at the deadline.
Method WaitFinished(ref As %String, seconds As %Integer) As %String [ Private ]
{
	Set deadline = $ZHorolog + seconds
	For {
		Set state = ..Fresh(ref).State
		If (state = "done") || (state = "failed") || ($ZHorolog > deadline) Quit
		Hang 0.25
	}
	Quit state
}

/// A saved approved tool_call request (a fixture row with no hold) for the tool of the fixture server, owned by the fixture session, held at the fingerprint of the tool with the
/// description (the mock's definition of zz_delete_ticket unless given) and answered by the answerer; source is the server's toolref unless given. Its Ref is tracked.
Method Approved(tool As %String, arguments As %String, source As %String = "", description As %String = "Deletes a ticket.") As %String [ Private ]
{
	Set toolref = $Select(source '= "": source, 1: ##class(OcuTalon.Mcp.Attach).Toolref(..#SERVER))
	Set row = ##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow("tool_call", tool, arguments, toolref, ..#RUNNER)
	Set row.OwnerRef = ..SessionRef
	Set row.ToolFingerprint = ##class(OcuTalon.Bridge.Context).ToolFingerprint(toolref, tool, description, {"type": "object", "properties": {"id": {"type": "string"}}})
	Set sc = ##class(OcuTalon.Test.Bridge.ApprovalRows).Save(row, "approved", 3600, ..#ANSWERER, .ref)
	Do $$$AssertStatusOK(sc, "an approved request for " _ tool _ " is saved")
	If $$$ISERR(sc) Quit ""
	Do ..Track(ref)
	Quit ref
}

/// Sends the replay request of the Ref to the runner, as Decide does for an approved request; the Reply is in reply. The status is the one Send gives.
Method Send(ref As %String, Output reply As %Persistent) As %Status [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "tool"
	Set request.Provenance = "user"
	Set request.ItemId = ref
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = ..SessionRef
	Set request.Channel = "system"
	Set request.Summary = "Test " _ ref
	Set request.Input = "replay " _ ref
	Quit $ClassMethod(..#FIXTURE, "Send", ..#RUNNER, request, .reply)
}

/// Replays the approved request and answers the state the row is in afterwards (done or failed).
Method Replay(ref As %String, Output reply As %Persistent) As %String [ Private ]
{
	Set sc = ..Send(ref, .reply)
	Do $$$AssertStatusOK(sc, "the replay request is answered")
	Set state = ..Fresh(ref).State
	Quit state
}

/// RemoveMcpServer for the fixture server, through OcuTalon's own handler with the restart of the runners left out (the probe of Test.Mcp.Ops), in the answerer's name; the CommandResult.
Method RemoveServer() As OcuTalon.Msg.CommandResult [ Private ]
{
	Set probe = ##class(OcuTalon.Test.Mcp.OpsProbe).Shadow("CommandsIn", .sc)
	Do $$$AssertStatusOK(sc, "the probe of McpOps is made")
	Set command = ##class(OcuTalon.Msg.Command.RemoveMcpServer).%New()
	Set command.Server = ..#SERVER
	Set command.Origin = "web_admin"
	Set command.ActingUser = ..#ANSWERER
	Set sc = probe.MessageHandler(command, .result)
	Do $$$AssertStatusOK(sc, "the command is delivered and answered with an OK status")
	Quit result
}

/// The number of requests that the mock read since the index (its log size at that time) that carried the credential header or were a tools/call: what a run of a tool sends.
/// (The unauthenticated probe of a runner that builds its agent is not one.)
Method Credentialed(since As %Integer) As %Integer [ Private ]
{
	Set count = 0
	Set iterator = $ClassMethod(..#MOCK, "Requests", ..Port).%GetIterator()
	While iterator.%GetNext(.index, .request) {
		If (index >= since) && ((request.auth = "matched") || (request.method = "tools/call")) Set count = count + 1
	}
	Quit count
}

/// The number of approval requests of the fixture session (the owner of every request that the tests raise).
Method RowCount() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE OwnerRef = ?", ..SessionRef)
	Do result.%Next()
	Quit +result.%Get("N")
}

/// 1 when the owner's web chat holds a Delivery row of kind result for the request (polled up to 30 seconds): the notice that the bridge sink sends when the run ends reached the channel.
Method ResultNotice(ref As %String) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + 30
	Set found = 0
	For {
		Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(..SessionRef)
		For i = 1:1:rows.Count() {
			Set one = rows.GetAt(i)
			If (one.Kind = "result") && (one.ApprovalRef = ref) && (one.Channel = "web") Set found = 1
		}
		If found || ($ZHorolog > deadline) Quit
		Hang 0.25
	}
	Quit found
}

/// Where the value shows ("" when nowhere), after a replay: the columns of the request, the owner's deliveries, the owner's events, the audit entries and the event log since the mark.
Method Shows(value As %String, eventMark As %Integer, row As OcuTalon.Bridge.Data.ApprovalRequest) As %String [ Private ]
{
	Set places = ""
	If value = "" Quit places
	Set columns = row.Kind _ row.State _ row.ToolName _ row.ToolArguments _ row.ToolSource _ row.ToolFingerprint _ row.Result _ row.OwnerRef _ row.TraceRef _ row.DryRun
	If columns [ value Set places = places _ $ListBuild("a column of the request")
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(..SessionRef)
	For i = 1:1:rows.Count() {
		If rows.GetAt(i).Text [ value Set places = places _ $ListBuild("a notice")
	}
	If ##class(OcuTalon.Test.Core.Observe).Events(..SessionRef, "approval").%ToJSON() [ value Set places = places _ $ListBuild("an event of the owner")
	If ##class(OcuTalon.Test.Bridge.AuditLog).Entries(..AuditMark, "OcuTalon", , , value).%Size() Set places = places _ $ListBuild("the audit log")
	If $ClassMethod(..#FIXTURE, "LogRowsHolding", eventMark, value) Set places = places _ $ListBuild("the event log")
	Quit $ListToString(places, ", ")
}

}
