/// The attach of the registered MCP servers to a runner's agent (Story 35.1; AD-6, AD-10, AD-19, AD-21, AD-31). THESE TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): they build an agent of a shadow runner of the test adapter OcuTalon.Test.Bridge.ZzTurnAdapter, so they need the CI override's environment and the
/// running production (RunnerFixture GuardReason, RunningReason), and they put the McpServersClass setting of the Decide item to the class a test needs and back.
/// Each test makes its own fixtures and removes them in OnAfterOneTest, whether it passed or failed: the row zzmcp<n> of OcuTalon.Mcp.Server, the Config Store entry
/// AI.MCP.OcuTalon_zzmcp<n> (url = the loopback mock, auth = a header whose value is a secret:// reference), the wallet collection and secret that the reference names
/// (a random value of this run, written by the test and deleted by it), and the mock of OcuTalon.Test.Mcp.Mock. Afterwards the test asserts that none is left. No
/// assertion message, Write or log line holds the secret: a check of where the value shows names places only.
///   - TestAttach (matrix rows 1 and 3): the manager of the agent lists the agent's own tools, the tool of the fixture toolset and the mock's zz_lookup and
///     zz_delete_ticket; Attached holds mcp:remote:@{config:AI.MCP.OcuTalon_<server>}; the row says attached, with no reason, the time and no refused tool; every request
///     of the mock carried the header; the gate classifies both tools as unclassified by their toolref and denies them in an untrusted turn; the secret shows nowhere;
///   - TestTurnManager (row 2): the manager that a request with turn tools composes lists the mock's tools too;
///   - TestTurnServerDown: the server is down when a request composes its manager: the request still gets it, without the server's tools;
///   - TestUnavailable (row 4): the mock is down, the build is OK, the manager has no mock tool and no mcp spec is recorded, the row says unavailable (unreachable),
///     and the secret, which AI Hub's error text holds, shows nowhere;
///   - TestShadow (row 5): a tool of the mock with the name of one of the agent's own tools is refused: the row holds its name, the manager lists the name once, and a bare
///     manager of the same shape runs the agent's tool and not the mock's;
///   - TestBridgeAlone (row 6): the base class attaches nothing and the mock sees no request; TestFreshInstall: with no Mcp.Server row the build attaches nothing;
///   - TestWrongClass (row 7): a McpServersClass that is missing or does not extend the base fails the build with an error that names the setting;
///   - TestBadConfig (row 8) and TestReports: a config name that does not match is reported invalid and never attached; a report has the status, the reason, the tools
///     and the refused tools; an error or an exception from OnAttach, and an error from Servers, never fail the build, and the next server is still tried.
Class OcuTalon.Test.Mcp.Attach Extends %UnitTest.TestCase
{

Parameter RUNNERCLASS = "OcuTalon.Test.Bridge.ZzTurnRunner";

Parameter AGENT = "OcuTalon.Test.Bridge.ZzTurnAgent";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter TURNTOOLS = "OcuTalon.Test.Bridge.ZzTurnTools";

Parameter ATTACH = "OcuTalon.Mcp.Attach";

Parameter SERVERS = "OcuTalon.Test.Mcp.ZzServers";

Parameter BASE = "OcuTalon.Bridge.Ext.McpServers";

/// The agent's own tools, sorted and comma-separated.
Parameter OWN = "zz_steps_card,zz_steps_note,zz_steps_text";

/// The header the entry names and the mock checks.
Parameter HEADER = "X-Zz-Key";

/// What UseItemSetting saved, as a JSON array of its records, to be put back in reverse order; empty when the test changed nothing.
Property Saved As %String(MAXLEN = "");

/// The mark of the saved AI sessions, of the event log and of the audit log when the test began.
Property SessionMark As %Integer;

Property LogMark As %Integer;

Property AuditMark As %String;

/// The fixture: the number of the test, the server name, the port of the mock, and the random secret of the run (never written to a message).
Property Number As %Integer;

Property Server As %String;

Property Port As %Integer [ InitialExpression = 0 ];

Property Secret As %String(MAXLEN = "") [ Transient ];

/// The port of the mock the test started, kept after the mock is stopped so that Leftovers can look for its nodes.
Property UsedPort As %Integer [ InitialExpression = 0 ];

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^||ZzTurn, ^||ZzMcp, ^OcuTalonTest("TurnTools")
	Set ..Saved = ""
	Set ..Port = 0
	Set ..UsedPort = 0
	Set ..Number = $Increment(^OcuTalonTest("Mcp", "n"))
	Set ..Server = "zzmcp" _ ..Number
	Set ..Secret = $Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(18)), "+/=", "AAA")
	Set ..SessionMark = $ClassMethod(..#FIXTURE, "SessionMark")
	Set ..LogMark = $ClassMethod(..#FIXTURE, "EventMark")
	Set ..AuditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do ..Remove()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Remove()
	Set leftovers = ..Leftovers()
	Do $$$AssertEquals(leftovers, "", "the test leaves no fixture behind")
	Set ..Secret = ""
	Kill ^||ZzTurn, ^||ZzMcp, ^OcuTalonTest("TurnTools")
	If ..Saved '= "" {
		Set saved = ##class(%DynamicAbstractObject).%FromJSON(..Saved)
		For i = saved.%Size() - 1:-1:0 Do $ClassMethod(..#FIXTURE, "RestoreItemSetting", "Decide", saved.%Get(i))
	}
	Set ..Saved = ""
	Do $ClassMethod(..#FIXTURE, "DropSince", ..SessionMark)
	Quit $$$OK
}

Method TestAttach()
{
	If ..Guard() Quit
	Do ..Use("McpServersClass", ..#ATTACH)
	Do ..Register(, 1)
	Set host = ..Runner()
	Set adapter = host.Adapter
	Do ..Ok(adapter.BuildAgent(), "the agent builds with the server attached")
	If '$IsObject(adapter.Agent) Quit
	Set names = ..Names(adapter.Agent.ToolManager)
	Do $$$AssertEquals(names, "zz_delete_ticket,zz_lookup," _ ..#OWN _ ",zz_turn_set", "the manager lists the agent's own tools, the tool of the toolset attached in OnAfterAgentInit and the two tools of the mock: " _ names)
	Set spec = ..Spec()
	Do $$$AssertEquals($ListToString(adapter.AttachedSpecs()), spec _ ",iris:OcuTalon.Test.Bridge.ZzTurnToolset", "Attached holds the placeholder spec and no URL or value")
	Set row = ..Row()
	Do $$$AssertEquals(row.AttachStatus _ "|" _ row.AttachReason _ "|" _ $ListToString(row.RefusedTools), "attached||", "the row says attached, with no reason and no refused tool")
	Do $$$AssertTrue(row.AttachedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "and the time of the attach")
	Set requests = ##class(OcuTalon.Test.Mcp.Mock).Requests(..Port)
	Set matched = 0, other = 0
	Set iterator = requests.%GetIterator()
	While iterator.%GetNext(, .request) {
		If request.auth = "matched" {
			Set matched = matched + 1
		} Else {
			Set other = other + 1
		}
	}
	Do $$$AssertTrue(matched > 0, "the mock got requests")
	Do $$$AssertEquals(other, 0, "and every one carried the header with the value the entry's secret reference gives")
	// every new tool is unclassified, whatever the mock's annotations say
	Set gate = "OcuTalon.Bridge.Policy.Gate"
	For name = "zz_lookup", "zz_delete_ticket" {
		Set result = $ClassMethod(gate, "ClassificationOf", spec, name)
		Do $$$AssertEquals(result.classification _ "|" _ result.by, "|", name _ " is unclassified by its toolref, so the annotations of the mock change nothing")
		Do $$$AssertEquals(..UntrustedSentence(spec, name), $Parameter(gate, "UNTRUSTED"), name _ " is denied in an untrusted turn")
	}
	Do $$$AssertEquals(..Leaks(adapter), "", "the secret shows in none of the places that are checked")
}

Method TestTurnManager()
{
	If ..Guard() Quit
	Do ..Use("McpServersClass", ..#ATTACH)
	Do ..Use("TurnToolsClass", ..#TURNTOOLS)
	Do ..Register(, 1)
	Set ^OcuTalonTest("TurnTools", "give") = 1
	Set host = ..Runner()
	Set adapter = host.Adapter
	Do ..Ok(adapter.TwoConfigs("zz-mcp-owner"), "a request with turn tools composes its manager")
	Set config = $Get(^||ZzTurn("config", 1))
	Do $$$AssertEquals($Piece(config, "|", 1, 3), "OcuTalon.Bridge.Policy.Gate|OcuTalon.Bridge.Policy.StepAudit|1", "which is a new manager with the gate and the step audit policy")
	Set names = $Piece(config, "|", 4)
	Do $$$AssertEquals(names, "zz_delete_ticket,zz_lookup," _ ..#OWN _ ",zz_turn_probe,zz_turn_set", "and lists the agent's tools, the fixture tools and both tools of the mock: " _ names)
	Do $$$AssertEquals(adapter.Agent.ToolManager.%token = $Get(^||ZzTurn("built")), 1, "the agent's own manager is put back")
	Do $$$AssertEquals(..Leaks(adapter), "", "the secret shows in none of the places that are checked")
}

Method TestUnavailable()
{
	If ..Guard() Quit
	Do ..Use("McpServersClass", ..#ATTACH)
	Do ..Register(, 0)
	Set host = ..Runner()
	Set adapter = host.Adapter
	Do ..Ok(adapter.BuildAgent(), "the agent builds although the server is down")
	If '$IsObject(adapter.Agent) Quit
	Set names = ..Names(adapter.Agent.ToolManager)
	Do $$$AssertEquals(names, ..#OWN _ ",zz_turn_set", "the manager has the agent's own tools and none of the mock's: " _ names)
	Do $$$AssertEquals(adapter.AttachedCount(), 1, "no mcp spec is recorded")
	Set row = ..Row()
	Do $$$AssertEquals(row.AttachStatus _ "|" _ row.AttachReason _ "|" _ row.AttachedAt _ "|" _ $ListToString(row.RefusedTools), "unavailable|unreachable||", "the row says unavailable, unreachable, with no time and no refused tool")
	Do $$$AssertEquals(..Leaks(adapter), "", "the secret, which AI Hub's error text holds, shows in none of the places that are checked")
}

Method TestShadow()
{
	If ..Guard() Quit
	Do ..Use("McpServersClass", ..#ATTACH)
	Do ..Register($ListBuild("zz_steps_note"), 1)
	Set host = ..Runner()
	Set adapter = host.Adapter
	Do ..Ok(adapter.BuildAgent(), "the agent builds")
	If '$IsObject(adapter.Agent) Quit
	Set names = ..Names(adapter.Agent.ToolManager)
	Do $$$AssertEquals(names, "zz_delete_ticket,zz_lookup," _ ..#OWN _ ",zz_turn_set", "the manager lists the other tools of the server and the agent's own: " _ names)
	Do $$$AssertEquals(..Listed(adapter.Agent.ToolManager, "zz_steps_note"), 1, "and lists zz_steps_note once")
	Set row = ..Row()
	Do $$$AssertEquals(row.AttachStatus _ "|" _ row.AttachReason _ "|" _ $ListToString(row.RefusedTools), "attached||zz_steps_note", "the row says attached and holds the refused name")
	// a bare manager of the same shape: the agent's tool runs, the mock's copy never does
	Set manager = ##class(%AI.ToolMgr).%New()
	Do ..Ok(manager.RegisterToolSet("OcuTalon.Test.Bridge.StepsTools"), "a bare manager takes the agent's toolset")
	Do ..Ok(manager.AddTool(..Spec()), "and then the server")
	Do manager.SetAuthPolicy(##class(OcuTalon.Test.Mcp.ZzAllow).%New())
	Set result = manager.ExecuteTool("zz_steps_note", {"topic": "zzmcp"})
	Do $$$AssertEquals(result.value.topic _ "|" _ result.value.note, "zzmcp|All systems normal.", "zz_steps_note runs the agent's tool")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.Mock).Calls(..Port, "zz_steps_note"), 0, "and the mock is not called for it")
	Do $$$AssertEquals(..Leaks(adapter), "", "the secret shows in none of the places that are checked")
}

Method TestBridgeAlone()
{
	If ..Guard() Quit
	Do ..Use("McpServersClass", ..#BASE)
	Do ..Register(, 1)
	Set host = ..Runner()
	Set adapter = host.Adapter
	Do ..Ok(adapter.BuildAgent(), "the agent builds with the base class")
	If '$IsObject(adapter.Agent) Quit
	Do $$$AssertEquals(..Names(adapter.Agent.ToolManager), ..#OWN _ ",zz_turn_set", "the manager has no mock tool")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.Mock).Requests(..Port).%Size(), 0, "the mock got no request")
	Set row = ..Row()
	Do $$$AssertEquals(row.AttachStatus _ "|" _ row.AttachReason _ "|" _ row.AttachedAt, "||", "and the row is as it was made")
}

/// A fresh install has no Mcp.Server row: every runner builds as before and attaches nothing.
Method TestFreshInstall()
{
	If ..Guard() Quit
	Do ..Use("McpServersClass", ..#ATTACH)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.Server WHERE Name %STARTSWITH 'zzmcp'")
	Do $$$AssertEquals(..RowCount(), 0, "no Mcp.Server row exists")
	If ..RowCount() '= 0 Quit
	Do ..Ok(##class(OcuTalon.Mcp.Attach).Servers(.servers), "Servers answers")
	Do $$$AssertEquals(servers.%Size(), 0, "with no server")
	Set host = ..Runner()
	Set adapter = host.Adapter
	Do ..Ok(adapter.BuildAgent(), "the agent builds")
	If '$IsObject(adapter.Agent) Quit
	Do $$$AssertEquals(..Names(adapter.Agent.ToolManager) _ "|" _ adapter.AttachedCount(), ..#OWN _ ",zz_turn_set|1", "and has only its own tools and the fixture toolset")
}

Method TestWrongClass()
{
	If ..Guard() Quit
	For class = "OcuTalon.Test.Mcp.ZzNoSuchServers", "OcuTalon.Bridge.Ext.HostSink" {
		Do ..Use("McpServersClass", class)
		Set host = ..Runner()
		Set adapter = host.Adapter
		Set sc = adapter.BuildAgent()
		Do $$$AssertStatusNotOK(sc, "the build fails for the class " _ class)
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "McpServersClass", "with an error that names the setting")
		Do $$$AssertEquals($IsObject(adapter.Agent), 0, "and leaves no agent, with no fallback to the base")
	}
}

Method TestBadConfig()
{
	If ..Guard() Quit
	Do ..Use("McpServersClass", ..#SERVERS)
	Set servers = []
	For config = "AI.MCP.Bad Name", "AI.LLM.OcuTalon_zz", "OcuTalon_zz", "AI.MCP.OcuTalon_zz}", "AI.MCP.", "" {
		Do servers.%Push({"server": ("zzbad"_(servers.%Size() + 1)), "config": (config)})
	}
	Do servers.%Push({"server": "zznoconfig"})
	Set ^||ZzMcp("servers") = servers.%ToJSON()
	Set host = ..Runner()
	Set adapter = host.Adapter
	Do ..Ok(adapter.BuildAgent(), "the agent builds")
	If '$IsObject(adapter.Agent) Quit
	Do $$$AssertEquals(..Names(adapter.Agent.ToolManager) _ "|" _ adapter.AttachedCount(), ..#OWN _ ",zz_turn_set|1", "nothing is attached and nothing is recorded")
	Do $$$AssertEquals(+$Get(^||ZzMcp("report")), 7, "and every server got a report")
	For n = 1:1:+$Get(^||ZzMcp("report")) {
		Set report = $Piece($Get(^||ZzMcp("report", n)), "|", 2, *)
		Do $$$AssertEquals(report, "{""status"":""unavailable"",""reason"":""invalid"",""tools"":[],""refused"":[]}", "report " _ n _ " is unavailable, invalid")
	}
}

Method TestReports()
{
	If ..Guard() Quit
	Do ..Use("McpServersClass", ..#SERVERS)
	// a live server, one that is down, one with no entry, and a bad name; OnAttach answers an error, so the next server is still tried
	Do ..Register($ListBuild("zz_steps_card"), 1)
	Set ^||ZzMcp("mode") = "error"
	Set servers = []
	Do servers.%Push({"server": "zzbad", "config": "AI.MCP.Bad Name"})
	Do servers.%Push({"server": "zznone", "config": "AI.MCP.OcuTalon_zznoconnect"})
	Do servers.%Push({"server": (..Server), "config": ("AI.MCP.OcuTalon_" _ ..Server)})
	Set ^||ZzMcp("servers") = servers.%ToJSON()
	Set host = ..Runner()
	Set adapter = host.Adapter
	Do ..Ok(adapter.BuildAgent(), "the agent builds although OnAttach answers an error")
	Do $$$AssertEquals(+$Get(^||ZzMcp("report")), 3, "and every server got its report, in order")
	Do $$$AssertEquals($Get(^||ZzMcp("report", 1)), "zzbad|{""status"":""unavailable"",""reason"":""invalid"",""tools"":[],""refused"":[]}", "an invalid name")
	Do $$$AssertEquals($Get(^||ZzMcp("report", 2)), "zznone|{""status"":""unavailable"",""reason"":""failed"",""tools"":[],""refused"":[]}", "an entry that does not exist is failed, although its name holds a word that marks an unreachable server")
	Do $$$AssertEquals($Get(^||ZzMcp("report", 3)), ..Server _ "|{""status"":""attached"",""reason"":"""",""tools"":[""zz_delete_ticket"",""zz_lookup""],""refused"":[""zz_steps_card""]}", "a live server lists its tools and the refused one")
	Do $$$AssertEquals(..Leaks(adapter), "", "the secret shows in none of the places that are checked")
	// the same with an OnAttach that throws, and a Servers that fails
	Kill ^||ZzMcp("report")
	Set ^||ZzMcp("mode") = "throw"
	Set host = ..Runner()
	Set adapter = host.Adapter
	Do ..Ok(adapter.BuildAgent(), "the agent builds although OnAttach throws")
	Do $$$AssertEquals(+$Get(^||ZzMcp("report")), 3, "and every server is still tried")
	Kill ^||ZzMcp("report")
	Set ^||ZzMcp("servers", "fail") = 1
	Set host = ..Runner()
	Set adapter = host.Adapter
	Do ..Ok(adapter.BuildAgent(), "the agent builds although Servers fails")
	If $IsObject(adapter.Agent) Do $$$AssertEquals(..Names(adapter.Agent.ToolManager), ..#OWN _ ",zz_turn_set", "with nothing attached")
	Do $$$AssertEquals(+$Get(^||ZzMcp("report")), 0, "and no report")
	Set ^||ZzMcp("servers", "fail") = 2
	Set host = ..Runner()
	Set adapter = host.Adapter
	Do ..Ok(adapter.BuildAgent(), "the agent builds although Servers throws")
	If $IsObject(adapter.Agent) Do $$$AssertEquals(..Names(adapter.Agent.ToolManager), ..#OWN _ ",zz_turn_set", "with nothing attached")
	Do $$$AssertEquals(+$Get(^||ZzMcp("report")), 0, "and no report")
}

/// A server that was up when the agent was built and is down when a request composes its manager: the request still gets its manager, with the tools of the
/// agent and of the request and none of the server's, and no status text of AI Hub, which can hold the secret, reaches the request.
Method TestTurnServerDown()
{
	If ..Guard() Quit
	Do ..Use("McpServersClass", ..#ATTACH)
	Do ..Use("TurnToolsClass", ..#TURNTOOLS)
	Do ..Register(, 1)
	Set ^OcuTalonTest("TurnTools", "give") = 1
	Set host = ..Runner()
	Set adapter = host.Adapter
	Do ..Ok(adapter.BuildAgent(), "the agent builds with the server up")
	If '$IsObject(adapter.Agent) Quit
	Do $$$AssertEquals($ListLength(adapter.AttachedSpecs()), 2, "and records the server's spec")
	Do ##class(OcuTalon.Test.Mcp.Mock).Stop(..Port)
	Do ..Ok(adapter.ComposeTwice("zz-mcp-owner"), "a request composes its manager although the server is down now")
	Set names = $Piece($Get(^||ZzTurn("config", 1)), "|", 4)
	Do $$$AssertEquals(names, ..#OWN _ ",zz_turn_probe,zz_turn_set", "and lists the agent's tools and the fixture tools, none of the server's: " _ names)
	Do $$$AssertEquals(..Leaks(adapter, 0), "", "the secret shows in none of the places that are checked, except the agent's own manager, which lists the server that is down")
}

/// Asserts that the status is OK. A failure names the label only: the text of a status from AI Hub can hold the URL and the value of a header, so it is never
/// part of a message.
Method Ok(sc As %Status, label As %String) [ Private ]
{
	Do $$$AssertTrue($$$ISOK(sc), label)
}

/// A shadow runner of the test adapter for the agent class.
Method Runner() As OcuTalon.Bridge.Operation.AgentRunner [ Private ]
{
	Quit ##class(OcuTalon.Test.Bridge.Runner).NewRunner(..#AGENT, , , "ZzRunner", ..#RUNNERCLASS)
}

/// Puts the setting of the Decide item to the class for the test, once (OnAfterOneTest puts it back). A setting that already has the value is left alone.
Method Use(setting As %String, class As %String) [ Private ]
{
	If ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor(setting) '= class {
		Set sc = $ClassMethod(..#FIXTURE, "UseItemSetting", "Decide", "Host", setting, class, .saved)
		If $IsObject(saved) {
			Set all = $Select(..Saved = "": [], 1: ##class(%DynamicAbstractObject).%FromJSON(..Saved))
			Do all.%Push(saved)
			Set ..Saved = all.%ToJSON()
		}
		Do ..Ok(sc, "the " _ setting _ " setting of Decide is " _ class)
	}
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor(setting), class, "the accessor reads " _ setting _ " as " _ class)
}

/// 1 when the test must not run: the environment is not the CI override's or the production does not run, and the test fails with the reason.
Method Guard() As %Boolean [ Private ]
{
	Set reason = $ClassMethod(..#FIXTURE, "GuardReason")
	If reason = "" Set reason = $ClassMethod(..#FIXTURE, "RunningReason")
	If reason = "" Quit 0
	Do $$$AssertTrue(0, reason)
	Quit 1
}

/// The fixtures of the registered server: the row, the mock (with the names of extra tools to offer too), the wallet entries and the Config Store entry. live 0 stops
/// the mock again, so that the entry names a port with no listener.
Method Register(extra As %List = "", live As %Boolean = 1) [ Private ]
{
	Set row = ##class(OcuTalon.Mcp.Server).%New()
	Set row.Name = ..Server
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Ok(row.%Save(), "the fixture row " _ ..Server _ " is saved")
	Do ..Ok(##class(OcuTalon.Test.Mcp.Mock).Start(.port, extra, ..#HEADER, ..Secret), "the mock starts")
	Set ..Port = port
	Set ..UsedPort = port
	Set collection = ..Collection()
	Do ..Ok(##class(%Wallet.Collection).Create(collection, {"EditResource": "%DB_%DEFAULT", "UseResource": "%DB_%DEFAULT"}), "the fixture wallet collection is made")
	Do ..Ok(##class(%Wallet.KeyValue).Create(collection _ ".Key", {"Secret": {"token": (..Secret)}, "RequireTLS": 0, "Usage": "CUSTOM"}), "the fixture wallet secret is made")
	Do ..Ok(##class(%ConfigStore.DescriptorManager).RebuildRegistry(), "the Config Store registry is rebuilt")
	Set details = {"transport": "remote", "url": ("http://127.0.0.1:" _ port _ "/mcp"), "auth": {"type": "header", "name": (..#HEADER), "value": ("secret://" _ collection _ ".Key#token")}}
	Do ..Ok(##class(%ConfigStore.Configuration).Create("AI", "MCP", "", "OcuTalon_" _ ..Server, details), "the fixture entry AI.MCP.OcuTalon_" _ ..Server _ " is made")
	If 'live Do ##class(OcuTalon.Test.Mcp.Mock).Stop(port)
}

/// Removes every fixture that this test may have made. Each removal is attempted whatever happened before.
Method Remove() [ Private ]
{
	If ..Port Do ##class(OcuTalon.Test.Mcp.Mock).Stop(..Port), ##class(OcuTalon.Test.Mcp.Mock).Forget(..Port)
	Set ..Port = 0
	Set entry = "AI.MCP.OcuTalon_" _ ..Server
	If ##class(%ConfigStore.Configuration).Exists(entry) Do ##class(%ConfigStore.Configuration).Delete(entry)
	If ##class(%Wallet.Secret).Exists(..Collection() _ ".Key") Do ##class(%Wallet.KeyValue).Delete(..Collection() _ ".Key")
	If ##class(%Wallet.Collection).Exists(..Collection()) Do ##class(%Wallet.Collection).Delete(..Collection())
	If ##class(OcuTalon.Mcp.Server).NameIndexExists(..Server, .id) Do ##class(OcuTalon.Mcp.Server).%DeleteId(id)
}

/// What is left of the fixtures, as a text of places ("" when nothing): the row, the entry, the wallet secret and collection, the mock's job and its log.
Method Leftovers() As %String [ Private ]
{
	Set places = ""
	If ##class(OcuTalon.Mcp.Server).NameIndexExists(..Server) Set places = places _ $ListBuild("the row")
	If ##class(%ConfigStore.Configuration).Exists("AI.MCP.OcuTalon_" _ ..Server) Set places = places _ $ListBuild("the Config Store entry")
	If ##class(%Wallet.Secret).Exists(..Collection() _ ".Key") Set places = places _ $ListBuild("the wallet secret")
	If ##class(%Wallet.Collection).Exists(..Collection()) Set places = places _ $ListBuild("the wallet collection")
	If ..UsedPort, $Data(^IRIS.Temp.OcuTalonMcpMock(..UsedPort)) || ##class(OcuTalon.Test.Mcp.Mock).Running(..UsedPort) Set places = places _ $ListBuild("a mock node or job")
	Quit $ListToString(places, ", ")
}

/// The wallet collection of the test's secret.
Method Collection() As %String [ Private ]
{
	Quit "OcuTalonZzMcp" _ ..Number
}

/// The spec that the adapter attaches for the fixture server.
Method Spec() As %String [ Private ]
{
	Quit "mcp:remote:@{config:AI.MCP.OcuTalon_" _ ..Server _ "}"
}

/// The row of the fixture server.
Method Row() As OcuTalon.Mcp.Server [ Private ]
{
	Quit ##class(OcuTalon.Mcp.Server).NameIndexOpen(..Server)
}

/// The number of rows of OcuTalon.Mcp.Server.
Method RowCount() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Mcp.Server")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The names of the tools the manager lists, sorted and comma-separated.
ClassMethod Names(manager As %AI.ToolMgr) As %String [ Private ]
{
	Set iterator = manager.%Discover().%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set names(tool.%Get("name")) = ""
	}
	Set list = ""
	Set name = ""
	For {
		Set name = $Order(names(name))
		Quit:name=""
		Set list = list _ $Select(list = "": "", 1: ",") _ name
	}
	Quit list
}

/// How many times the manager lists a tool of the name.
ClassMethod Listed(manager As %AI.ToolMgr, name As %String) As %Integer [ Private ]
{
	Set count = 0
	Set iterator = manager.%Discover().%GetIterator()
	While iterator.%GetNext(, .tool) {
		If tool.%Get("name") = name Set count = count + 1
	}
	Quit count
}

/// The sentence of the gate's denial of an MCP call of the tool by the toolref in an untrusted turn, or "<OK>" when it is allowed and "" when no context began.
ClassMethod UntrustedSentence(toolref As %String, name As %String) As %String [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "untrusted"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.TraceRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.Channel = "system"
	If $$$ISERR(##class(OcuTalon.Bridge.Context).Begin(request)) Quit ""
	Set call = {"id": "call_id", "name": (name), "arguments": {}}
	Set sc = ##class(OcuTalon.Bridge.Policy.Gate).Check(toolref, call, {}, "OcuTalon.Bridge.Ext.HostSink")
	Do ##class(OcuTalon.Bridge.Context).End()
	If $$$ISOK(sc) Quit "<OK>"
	Set text = $SYSTEM.Status.GetOneStatusText(sc)
	Set prefix = "Tool access denied: "
	Quit $Select($Extract(text, 1, $Length(prefix)) = prefix: $Extract(text, $Length(prefix) + 1, *), 1: text)
}

/// Where the secret shows, as a text of the places ("" when nowhere). The value is looked for by containment and is never part of the text: the event log after the
/// mark of the test, the stores of the key scan, the audit entries since the mark, the specs recorded as attached, the statuses and the catalog of the agent's manager,
/// the fields of the fixture row and the request log of the mock. With manager 0 the agent's own manager is not asked (it lists a server that is down).
Method Leaks(adapter As OcuTalon.Test.Bridge.ZzTurnAdapter, manager As %Boolean = 1) As %String [ Private ]
{
	Set secret = ..Secret
	Set places = ""
	If $ClassMethod(..#FIXTURE, "LogRowsHolding", ..LogMark, secret) Set places = places _ $ListBuild("the event log")
	If $ClassMethod("OcuTalon.Test.Agent.KeyScan", "Find", secret) '= "" Set places = places _ $ListBuild("a store of the key scan")
	If ##class(OcuTalon.Test.Bridge.AuditLog).Entries(..AuditMark, , , , secret).%Size() Set places = places _ $ListBuild("the audit log")
	If $ListToString(adapter.AttachedSpecs()) [ secret Set places = places _ $ListBuild("an Attached spec")
	If manager, $IsObject(adapter.Agent) {
		Set toolManager = adapter.Agent.ToolManager
		If toolManager.GetToolStatuses().%ToJSON() [ secret Set places = places _ $ListBuild("the tool statuses")
		If toolManager.%Discover().%ToJSON() [ secret Set places = places _ $ListBuild("the tool catalog")
	}
	Set row = ..Row()
	If $IsObject(row), (row.Name _ row.CreatedAt _ row.AttachStatus _ row.AttachReason _ row.AttachedAt _ $ListToString(row.RefusedTools)) [ secret Set places = places _ $ListBuild("the row")
	If ..Port, ##class(OcuTalon.Test.Mcp.Mock).Requests(..Port).%ToJSON() [ secret Set places = places _ $ListBuild("the request log of the mock")
	Quit $ListToString(places, ", ")
}

}
