/// The governed proxy inside the production's own runner job (Story 22.3 QA; DW-1222, DW-1223; AD-6, AD-10, AD-19, AD-21). THESE TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they
/// need the running production and the CI mock (RunnerFixture ReadyReason), they point the key entry of ChatAgent at the CI mock key variable (PointKeys) and put it back, and they make
/// the fixtures of one MCP server named zzmcp, the name that the mock's scenarios mcp-proxy-call and mcp-two-native-calls use: the row, the Use permission on its resource, the
/// loopback MCP mock that checks a header, a wallet collection and secret (a random value of the run), the Config Store entry AI.MCP.OcuTalon_zzmcp whose header is a secret:// reference
/// to it, and the two tool rows (zz_lookup read-only). OnAfterOneTest removes them whether the test passed or failed, asserts that none is left and that the secret shows in no event-log
/// row, key-scan store or audit entry.
///   - TestRunnerJob, part 1 (DW-1223, condition (e)): ChatAgent's job (a process of its own, started by the production, running as a user other than this test's) answers a user's turn
///     of the scenario mcp-proxy-call, in which the model calls call_mcp_tool. The proxy ran in that job: the audit entry of the call was written by the job's user, the MCP mock got an
///     initialize, the notification, a tools/list and a tools/call from the client iris, every one with the header resolved from the wallet by that job (the mock says matched), and the
///     model's next request carries the tool's text, so the job read the wallet secret. The turn is tainted, one tool step is ok and labelled with the tool and the server, one MCP
///     entry says called, and the secret and the mock's address show in no step, reply, event-log row, audit entry or store of the key scan, and not in the model's requests;
///   - TestRunnerJob, part 2 (DW-1222): the scenario mcp-two-native-calls makes the model call the read-only tool zz_lookup twice in one response, natively. AI Hub's own loop runs both in the
///     job: each is rewritten once into the proxy (the mock got two tools/call from the client iris and none from AI Hub's), each has its own step (two tool steps, both ok), its own audit
///     entry and its own result in the model's next request, and no call is held or denied;
///   - TestRunnerJob, at the end (condition (a)): the body of every message of the Visual Trace since the first request, as its XML export, holds neither the secret nor the
///     mock's address, while it does hold the first turn's input and the tool's text (the control that the bodies were read).
Class OcuTalon.Test.Mcp.ProxyJob Extends %UnitTest.TestCase
{

Parameter RUNNER = "ChatAgent";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Mcp.Mock";

Parameter HEADER = "X-Zz-Key";

/// The name of the server that the scenarios name.
Parameter SERVER = "zzmcp";

Property Port As %Integer [ InitialExpression = 0 ];

Property UsedPort As %Integer [ InitialExpression = 0 ];

Property Secret As %String(MAXLEN = "") [ Transient ];

/// 1 when the test pointed the key entry of the runner at the mock key variable and has to put it back.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The ItemIds of the requests that the test sent, whose steps, Decision rows and Usage rows OnAfterOneTest deletes.
Property ItemIds As %List;

Property LogMark As %Integer;

Property AuditMark As %String;

Property SessionMark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Port = 0
	Set ..UsedPort = 0
	Set ..Pointed = 0
	Set ..ItemIds = ""
	Set ..Secret = $Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(18)), "+/=", "AAA")
	Set ..LogMark = $ClassMethod(..#FIXTURE, "EventMark")
	Set ..AuditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set ..SessionMark = $ClassMethod(..#FIXTURE, "SessionMark")
	Do ..Remove()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Pointed {
		Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "RestoreKeys", ..#RUNNER), "the key entry of " _ ..#RUNNER _ " is put back to the placeholder of the Provider step")
		Set ..Pointed = 0
	}
	Do ..Remove()
	Do $ClassMethod(..#FIXTURE, "DropSince", ..SessionMark)
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do $ClassMethod(..#FIXTURE, "DeleteSteps", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Do $$$AssertEquals(..Leftovers(), "", "the test leaves no fixture behind")
	Do $$$AssertEquals(..Places(..Secret), "", "the secret shows in no log row, no audit entry and no store of the key scan")
	Set ..Secret = ""
	Quit $$$OK
}

Method TestRunnerJob()
{
	Set fixture = ..#FIXTURE
	Set reason = $ClassMethod(fixture, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Do ..Setup()
	// the runner builds its agent on its first request, so the restart that PointKeys makes comes after the fixtures: its build attaches the server
	Set ..Pointed = 1
	Set sc = $ClassMethod(fixture, "PointKeys", ..#RUNNER)
	Do $$$AssertStatusOK(sc, "the key entry of " _ ..#RUNNER _ " is pointed at the CI mock key variable and the runner is restarted")
	If $$$ISERR(sc) Quit
	Set user = ..JobUser(..#RUNNER)
	Do $$$AssertTrue(user '= "", "the job of " _ ..#RUNNER _ " runs as the user " _ user)
	Do $$$AssertTrue(user '= $Username, "which is not the user of this test process, so the wallet is read by the job and not by us")
	Set label = "Running zz_lookup on " _ ..#SERVER
	Set traceMark = ..HeaderMark()

	// part 1: the model calls call_mcp_tool itself
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set before = $ClassMethod(..#MOCK, "Requests", ..Port).%Size()
	Set eventMark = $ClassMethod(fixture, "EventMark")
	Set sc = $ClassMethod(fixture, "Ask", ..#RUNNER, "turn", "user", "Look up ticket 1. [[mock:mcp-proxy-call]]", .reply, .requests, .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Do $$$AssertStatusOK(sc, "the turn of mcp-proxy-call is answered by the production's job")
	If '$IsObject(reply) || 'reply.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(reply.Text, "The proxy answered.", "the turn is answered with the second reply of the scenario")
	Do $$$AssertEquals(reply.Tainted, 1, "the turn is tainted: an MCP result is not trusted output")
	Set steps = ##class(%DynamicAbstractObject).%FromJSON(reply.Steps)
	Set tools = ..ToolSteps(steps)
	Do $$$AssertEquals(tools.%Size(), 1, "the Reply holds one tool step")
	If tools.%Size() = 1 Do $$$AssertEquals(tools.%Get(0).status _ "|" _ tools.%Get(0).label, "ok|" _ label, "which is ok and labelled with the tool and the server")
	Do $$$AssertEquals(requests.%Size(), 2, "the mock got the request and the one that follows the tool call")
	If requests.%Size() = 2 {
		Set results = $ClassMethod(fixture, "ToolResults", requests.%Get(1))
		Do $$$AssertEquals($ListLength(results), 1, "the model's next request carries one tool result")
		Do $$$AssertTrue($ListToString(results, "|") [ "The mock ran zz_lookup", "the tool's text: the job resolved the wallet secret and the server accepted the header: " _ $ListToString(results, "|"))
		Do $$$AssertTrue($ListToString(results, "|") '[ $Parameter("OcuTalon.Tools.McpCall", "MCPFAILED"), "and not the refusal of a failed run")
		Do $$$AssertTrue(requests.%ToJSON() '[ ..Secret, "the model's requests do not hold the secret")
	}
	// OcuTalon's probe (Story 22.9) sends an initialize with no credential, from the same client; the proxy's own requests carry the header that the job resolved from the wallet
	Set methods = ""
	Set probes = ""
	Set native = 0
	Set iterator = $ClassMethod(..#MOCK, "Requests", ..Port).%GetIterator()
	While iterator.%GetNext(.index, .request) {
		If index < before Continue
		If request.client = "iris" {
			If request.auth = "matched" {
				Set methods = methods _ $ListBuild(request.method)
			} Else {
				Set probes = probes _ $ListBuild(request.method _ "/" _ request.auth)
			}
		} ElseIf request.method = "tools/call" {
			Set native = native + 1
		}
	}
	Do $$$AssertEquals($ListToString(methods), "initialize,notifications/initialized,tools/list,tools/call", "the mock got one initialize, the notification, one tools/list and one tools/call from the proxy of the job, each with the header that the job resolved from the wallet (matched)")
	Do $$$AssertTrue($ListLength(methods) > 0, "so the job read the wallet secret")
	Set position = 0
	While $ListNext(probes, position, probe) {
		Do $$$AssertEquals(probe, "initialize/absent", "any other request of OcuTalon's client is a probe: an initialize that sends no credential")
	}
	Do $$$AssertEquals(native, 0, "and no tools/call from AI Hub's client")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "MCP", "MCP", ..#SERVER)
	Do $$$AssertEquals(entries.%Size(), 1, "one MCP audit entry exists")
	If entries.%Size() {
		Do $$$AssertEquals(entries.%Get(0).data.change _ "|" _ entries.%Get(0).data.server _ "|" _ entries.%Get(0).data.tool _ "|" _ entries.%Get(0).data.outcome, "called|" _ ..#SERVER _ "|zz_lookup|ok", "it says called, the server, the tool and ok")
		Do $$$AssertEquals(entries.%Get(0).username, user, "and the job's user wrote it, so the proxy ran in the runner job")
	}
	Do $$$AssertEquals($ClassMethod(fixture, "LeakPlaces", ..Secret, steps, reply, eventMark), "", "the secret shows in no step, reply, event-log row or store of the key scan")
	Do $$$AssertEquals($ClassMethod(fixture, "LeakPlaces", "127.0.0.1:" _ ..Port, steps, reply, eventMark), "", "nor the mock's address")

	// part 2: two native calls in one response
	Do $ClassMethod(..#MOCK, "Call", ..Port, "echo")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set before = $ClassMethod(..#MOCK, "Requests", ..Port).%Size()
	Set eventMark = $ClassMethod(fixture, "EventMark")
	Set sc = $ClassMethod(fixture, "Ask", ..#RUNNER, "turn", "user", "Look up tickets 1 and 2. [[mock:mcp-two-native-calls]]", .reply, .requests, .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Do $$$AssertStatusOK(sc, "the turn of mcp-two-native-calls is answered by the production's job")
	If '$IsObject(reply) || 'reply.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(reply.Text, "Both lookups ran.", "the turn is answered with the second reply of the scenario")
	Do $$$AssertEquals(reply.Tainted, 1, "the turn is tainted")
	Set steps = ##class(%DynamicAbstractObject).%FromJSON(reply.Steps)
	Set tools = ..ToolSteps(steps)
	Set text = ""
	Set iterator = tools.%GetIterator()
	While iterator.%GetNext(, .step) {
		Set text = text _ $ListBuild(step.status _ "|" _ step.label)
	}
	Do $$$AssertEquals($ListToString(text, ","), "ok|" _ label _ ",ok|" _ label, "the Reply holds two tool steps, both ok and labelled with the tool and the server: none twice, none denied")
	Do $$$AssertEquals(requests.%Size(), 2, "the mock got the request and the one that follows the two tool calls")
	If requests.%Size() = 2 {
		Set results = $ClassMethod(fixture, "ToolResults", requests.%Get(1))
		Do $$$AssertEquals($ListLength(results), 2, "the model's next request carries two tool results")
		If $ListLength(results) = 2 {
			Do $$$AssertTrue(($List(results, 1) [ "echo:") && ($List(results, 1) [ "1") && ($List(results, 1) '[ "2"), "the first is the result of the call with id 1: " _ $List(results, 1))
			Do $$$AssertTrue(($List(results, 2) [ "echo:") && ($List(results, 2) [ "2") && ($List(results, 2) '[ "1"), "and the second of the call with id 2: " _ $List(results, 2))
		}
	}
	Set calls = 0
	Set native = 0
	Set iterator = $ClassMethod(..#MOCK, "Requests", ..Port).%GetIterator()
	While iterator.%GetNext(.index, .request) {
		If (index < before) || (request.method '= "tools/call") Continue
		If request.client = "iris" {
			Set calls = calls + 1
		} Else {
			Set native = native + 1
		}
	}
	Do $$$AssertEquals(calls _ "|" _ native, "2|0", "the mock got two tools/call from the proxy of the job and none from AI Hub's client: each call was rewritten once")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "MCP", "MCP", ..#SERVER, , 2)
	Do $$$AssertEquals(entries.%Size(), 2, "two MCP audit entries exist")
	Set outcomes = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set outcomes = outcomes _ $ListBuild(entry.data.change _ "|" _ entry.data.tool _ "|" _ entry.data.outcome)
	}
	Do $$$AssertEquals($ListToString(outcomes, ","), "called|zz_lookup|ok,called|zz_lookup|ok", "each says called, the tool and ok")
	Do $$$AssertEquals($ClassMethod(fixture, "LeakPlaces", ..Secret, steps, reply, eventMark), "", "the secret shows in no step, reply, event-log row or store of the key scan")
	Do $$$AssertTrue($ClassMethod(..#MOCK, "Requests", ..Port).%ToJSON() '[ ..Secret, "nor in the request log of the MCP mock")

	// condition (a): the Visual Trace of both turns, every message body since the first request
	Set holds = ..TraceHolds(traceMark, $ListBuild("Look up ticket 1.", "The mock ran zz_lookup", ..Secret, "127.0.0.1:" _ ..Port), .scanned)
	Do $$$AssertTrue(scanned > 0, "the message bodies of the Visual Trace were read: " _ scanned)
	Do $$$AssertEquals($ListGet(holds, 1) _ $ListGet(holds, 2), "11", "control: the trace holds the first turn's input and the tool's text")
	Do $$$AssertEquals($ListGet(holds, 3), 0, "no message body of the Visual Trace holds the secret")
	Do $$$AssertEquals($ListGet(holds, 4), 0, "nor the mock's address")
}

/// The ID of the newest row of Ens.MessageHeader, 0 when there is none: the mark of TraceHolds.
ClassMethod HeaderMark() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens.MessageHeader")
	If result.%Next() Quit +result.%GetData(1)
	Quit 0
}

/// Whether the Visual Trace since the mark holds each of the values: one 1 or 0 for each value, in order. The trace is the body of every Ens.MessageHeader row after the mark,
/// read as its XML export (scanned counts the bodies that were read); no value is ever part of an answer or a message.
ClassMethod TraceHolds(mark As %Integer, values As %List, Output scanned As %Integer) As %List [ Private ]
{
	Set scanned = 0
	Set holds = ""
	For i = 1:1:$ListLength(values) Set $List(holds, i) = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE ID > ? ORDER BY ID", mark)
	While result.%Next() {
		Set class = result.%GetData(1)
		Set id = result.%GetData(2)
		If (class = "") || (id = "") Continue
		Set text = ""
		Try {
			Set body = $ClassMethod(class, "%OpenId", id)
			If $IsObject(body) && body.%Extends("%XML.Adaptor") && $$$ISOK(body.XMLExportToString(.text)) Set scanned = scanned + 1
		} Catch {
			Set text = ""
		}
		For i = 1:1:$ListLength(values) {
			If text [ $List(values, i) Set $List(holds, i) = 1
		}
	}
	Quit holds
}

/// The tool steps of a Reply's steps, as a dynamic array.
Method ToolSteps(steps As %DynamicArray) As %DynamicArray [ Private ]
{
	Set found = []
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		If step.kind = "tool" Do found.%Push(step)
	}
	Quit found
}

/// The fixtures of the server zzmcp: the mock (that checks the header and the secret), the wallet collection and secret, the entry AI.MCP.OcuTalon_zzmcp whose header names the secret,
/// the row, the Use permission on its resource and the two tool rows (zz_lookup read-only, zz_delete_ticket risky) with the fingerprints of the mock's definitions.
Method Setup() [ Private ]
{
	Do ..Ok($ClassMethod(..#MOCK, "Start", .port, , ..#HEADER, ..Secret), "the mock starts")
	Set ..Port = port
	Set ..UsedPort = port
	Set collection = ..Collection()
	Do ..Ok(##class(%Wallet.Collection).Create(collection, {"EditResource": "%DB_%DEFAULT", "UseResource": "%DB_%DEFAULT"}), "the fixture wallet collection is made")
	Do ..Ok(##class(%Wallet.KeyValue).Create(collection _ ".Key", {"Secret": {"token": (..Secret)}, "RequireTLS": 0, "Usage": "CUSTOM"}), "the fixture wallet secret is made")
	Do ..Ok(##class(%ConfigStore.DescriptorManager).RebuildRegistry(), "the Config Store registry is rebuilt")
	Do ..Ok(##class(%ConfigStore.Configuration).Create("AI", "MCP", "", "OcuTalon_" _ ..#SERVER, {"transport": "remote", "url": ("http://127.0.0.1:" _ port _ "/mcp"), "auth": {"type": "header", "name": (..#HEADER), "value": ("secret://" _ collection _ ".Key#token")}}), "the fixture entry is made")
	Set row = ##class(OcuTalon.Mcp.Server).%New()
	Set row.Name = ..#SERVER
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Ok(row.%Save(), "the fixture row " _ ..#SERVER _ " is saved")
	Do ..Ok(##class(OcuTalon.Install.Step.Mcp).Grant(..#SERVER), "and the service role holds the Use permission on its resource")
	Set spec = "mcp:remote:@{config:AI.MCP.OcuTalon_" _ ..#SERVER _ "}"
	Set schema = {"type": "object", "properties": {"id": {"type": "string"}}}
	Do ..Row("zz_lookup", "read-only", ##class(OcuTalon.Bridge.Context).ToolFingerprint(spec, "zz_lookup", "Looks up a ticket.", schema))
	Do ..Row("zz_delete_ticket", "risky", ##class(OcuTalon.Bridge.Context).ToolFingerprint(spec, "zz_delete_ticket", "Deletes a ticket.", schema))
}

/// A tool row of the fixture server with the classification and the fingerprint.
Method Row(tool As %String, classification As %String, fingerprint As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.ToolClassification).%New()
	Set row.Server = ..#SERVER
	Set row.Tool = tool
	Set row.Classification = classification
	Set row.Fingerprint = fingerprint
	Do ..Ok(row.%Save(), "the tool row " _ tool _ " is saved")
}

/// Where the value shows ("" when nowhere): the event log after the mark of the test, the stores of the key scan and the audit entries since the mark.
Method Places(value As %String) As %String [ Private ]
{
	Set places = ""
	If value = "" Quit places
	If ..LogMark = "" Quit "the test set no log mark"
	If $ClassMethod(..#FIXTURE, "LogRowsHolding", ..LogMark, value) Set places = places _ $ListBuild("the event log")
	If $ClassMethod("OcuTalon.Test.Agent.KeyScan", "Find", value) '= "" Set places = places _ $ListBuild("a store of the key scan")
	If ##class(OcuTalon.Test.Bridge.AuditLog).Entries(..AuditMark, "OcuTalon", , , value).%Size() Set places = places _ $ListBuild("the audit log")
	Quit $ListToString(places, ", ")
}

/// The user that the job of the production item runs as, or "" when it has no alive job or the process cannot be read.
ClassMethod JobUser(item As %String) As %String [ Private ]
{
	Set user = ""
	Try {
		Set jobs = ##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(item)
		If $ListLength(jobs) '= 0 {
			Set process = ##class(%SYS.ProcessQuery).%OpenId($List(jobs, 1))
			If $IsObject(process) Set user = process.UserName
		}
	} Catch {
		Set user = ""
	}
	Quit user
}

Method Collection() As %String [ Private ]
{
	Quit "OcuTalonZzMcpJob"
}

Method Ok(sc As %Status, label As %String) [ Private ]
{
	Do $$$AssertTrue($$$ISOK(sc), label)
}

/// Removes every fixture that this test may have made. Each removal is attempted whatever happened before.
Method Remove() [ Private ]
{
	If ..Port Do $ClassMethod(..#MOCK, "Stop", ..Port), $ClassMethod(..#MOCK, "Forget", ..Port)
	Set ..Port = 0
	Set entry = "AI.MCP.OcuTalon_" _ ..#SERVER
	If ##class(%ConfigStore.Configuration).Exists(entry) Do ##class(%ConfigStore.Configuration).Delete(entry)
	If ##class(%Wallet.Secret).Exists(..Collection() _ ".Key") Do ##class(%Wallet.KeyValue).Delete(..Collection() _ ".Key")
	If ##class(%Wallet.Collection).Exists(..Collection()) Do ##class(%Wallet.Collection).Delete(..Collection())
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", ..#SERVER)
	If ##class(OcuTalon.Mcp.Server).NameIndexExists(..#SERVER, .id) Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
	Do ##class(OcuTalon.Install.Step.Mcp).Revoke(..#SERVER)
}

/// What is left of the fixtures, as a text of places ("" when nothing).
Method Leftovers() As %String [ Private ]
{
	Set places = ""
	If ##class(OcuTalon.Mcp.Server).NameIndexExists(..#SERVER) Set places = places _ $ListBuild("the row")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", ..#SERVER)
	Do result.%Next()
	If result.%GetData(1) Set places = places _ $ListBuild("the tool rows")
	If ##class(%ConfigStore.Configuration).Exists("AI.MCP.OcuTalon_" _ ..#SERVER) Set places = places _ $ListBuild("the Config Store entry")
	If ##class(%Wallet.Secret).Exists(..Collection() _ ".Key") Set places = places _ $ListBuild("the wallet secret")
	If ##class(%Wallet.Collection).Exists(..Collection()) Set places = places _ $ListBuild("the wallet collection")
	If ..UsedPort, $Data(^IRIS.Temp.OcuTalonMcpMock(..UsedPort)) || $ClassMethod(..#MOCK, "Running", ..UsedPort) Set places = places _ $ListBuild("a mock node or job")
	Quit $ListToString(places, ", ")
}

}
