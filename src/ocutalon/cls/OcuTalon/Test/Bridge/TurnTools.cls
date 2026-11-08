/// Tests of the tools of one request (Story 19.5; AD-6, AD-10, AD-21, AD-31): the TurnToolsClass extension and the adapter's composition of a tool manager for
/// a request. THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), except TestBaseGivesNone, which needs nothing: the others send requests to the CI mock, so they
/// need the CI override's environment, and they change the TurnToolsClass setting of the Decide item of the running production (RunnerFixture UseItemSetting) and
/// put it back. The runner host is a shadow made in memory (Test.Bridge.Runner NewRunner) with the test adapter ZzTurnAdapter, whose agent ZzTurnAgent has the
/// tools of StepsTools, and whose OnAfterAgentInit attaches the toolset ZzTurnToolset through Attach. The test TurnToolsClass ZzTurnTools gives one holder that
/// adds the tool zz_turn_probe when the node ^OcuTalonTest("TurnTools", "give") is 1.
///   - TestBaseGivesNone: the base gives an empty list and OK for any owner and kind, and the accessor reads TurnToolsClass against the base;
///   - TestTurnTools (the fixture-toolset AC): a turn that gets turn tools has a model request that offers the agent's tools, the fixture toolset's tool and the
///     fixture turn tool; the composed manager is a new one with the gate and the step audit policy, the gate decides the call of the turn tool (the tool ran,
///     the step is recorded and the Reply says a tool ran), the class was asked once, with the OwnerRef and the kind; the next request without turn tools offers the
///     agent's tools and the fixture toolset's tool only, and the agent's own manager is put back; Inventory lists no turn tool;
///   - TestOtherKinds: a request of kind decide gets no manager of its own when the class gives none for the kind, and the owner and kind reach the class;
///   - TestComposesOnce: two session configs of one request (as a compaction composes) ask the class once and give the same composed manager, and the agent's own
///     manager is put back; an agent that is built again records each attached spec once;
///   - TestFailureRestores: a request whose session config fails after its manager was composed (ZzTurnAdapter's fail node) ends in that error with no model
///     request, the agent's own manager is put back, and the next request, which gets no turn tool, offers none of the failed request's;
///   - TestSkills: an agent that declares skills fails a request that gets turn tools, with an error that names the agent, and no model request is sent; the same
///     agent runs a request that gets none;
///   - TestMissingClass: a TurnToolsClass that is not a compiled class, or that does not extend the base, ends the request with that error and sends no model request.
Class OcuTalon.Test.Bridge.TurnTools Extends %UnitTest.TestCase
{

Parameter RUNNERCLASS = "OcuTalon.Test.Bridge.ZzTurnRunner";

Parameter AGENT = "OcuTalon.Test.Bridge.ZzTurnAgent";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter TURNTOOLS = "OcuTalon.Test.Bridge.ZzTurnTools";

/// The agent's own tools, sorted and comma-separated, and the tool of the toolset that the adapter attaches.
Parameter OWN = "zz_steps_card,zz_steps_note,zz_steps_text";

/// What UseItemSetting saved, as JSON text, to be put back; empty when the test changed nothing.
Property Saved As %String(MAXLEN = "");

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^||ZzTurn, ^OcuTalonTest("TurnTools")
	Set ..Saved = ""
	Set ..SessionMark = $ClassMethod(..#FIXTURE, "SessionMark")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^||ZzTurn, ^OcuTalonTest("TurnTools")
	If ..Saved '= "" Do $ClassMethod(..#FIXTURE, "RestoreItemSetting", "Decide", {}.%FromJSON(..Saved))
	Set ..Saved = ""
	Do $ClassMethod(..#FIXTURE, "DropSince", ..SessionMark)
	Quit $$$OK
}

Method TestBaseGivesNone()
{
	Set base = "OcuTalon.Bridge.Ext.TurnTools"
	Set sc = $ClassMethod(base, "Tools", "an-owner", "turn", .tools)
	Do $$$AssertStatusOK(sc, "the base answers OK")
	Do $$$AssertTrue($IsObject(tools) && tools.%IsA("%Library.ListOfObjects"), "with a list of objects")
	Do $$$AssertEquals(tools.Count(), 0, "which is empty")
	For kind = "turn", "decide", "diagnose" {
		Set sc = $ClassMethod(base, "Tools", "", kind, .tools)
		Do $$$AssertEquals($$$ISOK(sc) _ "|" _ tools.Count(), "1|0", "and so for the kind " _ kind _ " and an empty owner")
	}
	Set pair = ",TurnToolsClass=" _ base
	Do $$$AssertTrue($Parameter("OcuTalon.Bridge.Ext.Accessor", "BASES") [ pair, "the accessor pairs TurnToolsClass with the base")
	Do $$$AssertEquals(##class(%Dictionary.CompiledProperty).%OpenId("OcuTalon.Bridge.Process.Decide||TurnToolsClass").InitialExpression, """OcuTalon.Bridge.Ext.TurnTools""", "and Decide's property starts as the base")
}

Method TestTurnTools()
{
	If ..Guard() Quit
	Do ..Use(..#TURNTOOLS)
	Set ^OcuTalonTest("TurnTools", "give") = 1
	Set host = ..Runner(..#AGENT)
	Set adapter = host.Adapter
	Do $$$AssertStatusOK(adapter.BuildAgent(), "the agent builds")
	Set own = adapter.Agent.ToolManager
	Set request = ..NewRequest("turn", "[[mock:turn-tools-probe]] Run the turn probe.", "zz-turn-owner-1")
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "a turn that gets turn tools is answered")
	If '$IsObject(reply) Quit
	Set requests = ..Requests(request)
	Do $$$AssertEquals(requests.%Size(), 2, "the mock got two model requests: " _ requests.%Size())
	If requests.%Size() < 2 Quit
	Set offered = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(requests.%Get(0))
	Do $$$AssertEquals(offered, ..#OWN _ ",zz_turn_probe,zz_turn_set", "the request offers the agent's tools, the tool of the toolset attached in OnAfterAgentInit and the turn tool")
	Do $$$AssertEquals(reply.Text, "The CI mock used the turn tool.", "the reply is the text of the scenario")
	Do $$$AssertEquals(reply.ToolsRun, 1, "a tool ran")
	Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(requests.%Get(1))
	Do $$$AssertEquals($ListLength(results), 1, "the second request carries one tool result")
	If $ListLength(results) = 1 Do $$$AssertEquals($List(results, 1), "{""tool"":""zz_turn_probe"",""topic"":""probe""}", "the result of the turn tool")
	Do $$$AssertEquals($Get(^||ZzTurn("ran", "zz_turn_probe")) _ "|" _ $Get(^||ZzTurn("ran", "zz_turn_set")), "1|", "the turn tool ran once, and the attached one did not")
	Set steps = {}.%FromJSON("{""steps"":" _ reply.Steps _ "}").steps
	Do $$$AssertEquals(steps.%Size(), 3, "the Reply holds three step records: model, tool, model")
	If steps.%Size() = 3 Do $$$AssertEquals(steps.%Get(0).kind _ "," _ steps.%Get(1).kind _ "," _ steps.%Get(2).kind _ "|" _ steps.%Get(1).status, "model,tool,model|ok", "the tool step is recorded by the step audit policy of the composed manager")
	Do $$$AssertEquals($Get(^||ZzTurn("calls")) _ "|" _ $Get(^||ZzTurn("last")), "1|zz-turn-owner-1|turn", "the class was asked once, with the OwnerRef and the kind")
	Set config = $Get(^||ZzTurn("config", 1))
	Do $$$AssertEquals($Piece(config, "|", 1, 3), "OcuTalon.Bridge.Policy.Gate|OcuTalon.Bridge.Policy.StepAudit|1", "the manager of the request is a new one with the gate and the step audit policy")
	Do $$$AssertEquals($Piece(config, "|", 4), "zz_steps_card,zz_steps_note,zz_steps_text,zz_turn_probe,zz_turn_set", "with the agent's tools, the attached tool and the turn tool: " _ $Piece(config, "|", 4))
	Do $$$AssertEquals(adapter.Agent.ToolManager = own, 1, "the agent's own manager is put back when the request ends")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and the context is over")

	// The next request, which gets none: the agent's own manager, the same job.
	Set ^OcuTalonTest("TurnTools", "give") = 0
	Set request = ..NewRequest("turn", "[[mock:recall-ask]] Where is the build server?", "zz-turn-owner-2")
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "a turn that gets none is answered")
	Set requests = ..Requests(request)
	Do $$$AssertEquals(requests.%Size(), 1, "with one model request")
	If requests.%Size() = 1 Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(requests.%Get(0)), ..#OWN _ ",zz_turn_set", "which offers the agent's tools and the attached tool only")
	Do $$$AssertEquals($Piece($Get(^||ZzTurn("config", 2)), "|", 3), 0, "its manager is the agent's own: " _ $Get(^||ZzTurn("config", 2)))
	Do $$$AssertEquals(adapter.Agent.ToolManager = own, 1, "and stays the agent's own manager")

	// Inventory reads the agent's own manager, outside any request.
	Set sc = adapter.Inventory(.inventory)
	Do $$$AssertStatusOK(sc, "Inventory answers")
	Set names = ""
	Set iterator = inventory.tools.%GetIterator()
	While iterator.%GetNext(, .tool) {
		Set names = names _ $Select(names = "": "", 1: ",") _ tool.name
	}
	Do $$$AssertTrue(names [ "zz_turn_set", "the inventory lists the attached tool")
	Do $$$AssertTrue(names '[ "zz_turn_probe", "and no turn tool")
}

Method TestOtherKinds()
{
	If ..Guard() Quit
	Do ..Use(..#TURNTOOLS)
	Set ^OcuTalonTest("TurnTools", "give") = 0
	Set host = ..Runner(..#AGENT)
	Set request = ..NewRequest("decide", "[[mock:recall-ask]] Decide something.", "")
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "a request of kind decide is answered")
	Do $$$AssertEquals($Get(^||ZzTurn("last")), "|decide", "the class was asked with the kind decide and the empty owner")
	Set requests = ..Requests(request)
	Do $$$AssertEquals(requests.%Size(), 1, "it sends one model request")
	If requests.%Size() = 1 Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(requests.%Get(0)), ..#OWN _ ",zz_turn_set", "it offers the agent's tools and the attached tool")
	Do $$$AssertEquals($Piece($Get(^||ZzTurn("config", 1)), "|", 3), 0, "with the agent's own manager")
	Kill ^||ZzTurn("config"), ^||ZzTurn("calls"), ^||ZzTurn("last")
	Set ^OcuTalonTest("TurnTools", "give") = 1
	Set request = ..NewRequest("diagnose", "[[mock:turn-tools-probe]] Run the turn probe.", "")
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "a request of kind diagnose that gets a tool is answered")
	Set requests = ..Requests(request)
	Do $$$AssertTrue(requests.%Size() > 0, "it sends a model request")
	If requests.%Size() > 0 Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(requests.%Get(0)), ..#OWN _ ",zz_turn_probe,zz_turn_set", "the class decides by kind, so a fixture that gives a tool for any kind adds it")
	Do $$$AssertEquals($Get(^||ZzTurn("last")), "|diagnose", "and was asked with the kind diagnose")
}

Method TestComposesOnce()
{
	If ..Guard() Quit
	Do ..Use(..#TURNTOOLS)
	Set ^OcuTalonTest("TurnTools", "give") = 1
	Set host = ..Runner(..#AGENT)
	Set adapter = host.Adapter
	Do $$$AssertStatusOK(adapter.TwoConfigs("zz-turn-owner-6"), "two session configs of one request are composed")
	Do $$$AssertEquals($Get(^||ZzTurn("calls")), 1, "the class was asked once")
	Do $$$AssertEquals($Get(^||ZzTurn("config")), 2, "for two session configs")
	Set first = $Get(^||ZzTurn("config", 1))
	Do $$$AssertEquals($Piece(first, "|", 3), 1, "the first holds the manager of the request: " _ first)
	Do $$$AssertEquals($Get(^||ZzTurn("config", 2)), first, "and the second holds the same one")
	Do $$$AssertEquals(adapter.Agent.ToolManager.%token, ^||ZzTurn("built"), "the agent's own manager is put back")
	Do $$$AssertEquals(adapter.AttachedCount(), 1, "the attached spec is recorded once")
	Set adapter.Agent = ""
	Do $$$AssertStatusOK(adapter.BuildAgent(), "the agent is built again")
	Do $$$AssertEquals(adapter.AttachedCount(), 1, "and the attached spec is still recorded once")
}

Method TestFailureRestores()
{
	If ..Guard() Quit
	Do ..Use(..#TURNTOOLS)
	Set ^OcuTalonTest("TurnTools", "give") = 1
	Set ^OcuTalonTest("TurnTools", "fail") = 1
	Set host = ..Runner(..#AGENT)
	Set adapter = host.Adapter
	Do $$$AssertStatusOK(adapter.BuildAgent(), "the agent builds")
	Set own = adapter.Agent.ToolManager
	Set request = ..NewRequest("diagnose", "[[mock:turn-tools-probe]] Run the turn probe.", "zz-turn-owner-7")
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusNotOK(sc, "a request that fails after its manager was composed ends in an error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "after the composition", "the fixture's error: " _ $SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals($Get(^||ZzTurn("calls")), 1, "control: the class was asked and gave the turn tool")
	Do $$$AssertEquals(..Requests(request).%Size(), 0, "no model request was sent")
	Do $$$AssertEquals(adapter.Agent.ToolManager = own, 1, "the agent's own manager is put back on the error path")
	Kill ^OcuTalonTest("TurnTools", "fail")
	Set ^OcuTalonTest("TurnTools", "give") = 0
	Set request = ..NewRequest("diagnose", "[[mock:recall-ask]] Where is the build server?", "zz-turn-owner-8")
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "the next request, which gets none, is answered")
	Set requests = ..Requests(request)
	Do $$$AssertEquals(requests.%Size(), 1, "with one model request")
	If requests.%Size() = 1 Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(requests.%Get(0)), ..#OWN _ ",zz_turn_set", "which offers no tool of the failed request")
}

Method TestSkills()
{
	If ..Guard() Quit
	Do ..Use(..#TURNTOOLS)
	Set ^OcuTalonTest("TurnTools", "give") = 1
	Set host = ..Runner("OcuTalon.Test.Bridge.ZzTurnSkillAgent")
	Set request = ..NewRequest("turn", "[[mock:turn-tools-probe]] Run the turn probe.", "zz-turn-owner-3")
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusNotOK(sc, "an agent that declares skills fails a request that gets turn tools")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Test.Bridge.ZzTurnSkillAgent", "with an error that names the agent: " _ $SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(..Requests(request).%Size(), 0, "and sends no model request")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "the context is over")
	Do $$$AssertEquals(host.Adapter.Agent.ToolManager.%token = ^||ZzTurn("built"), 1, "and the agent's own manager is still the agent's")
	Set ^OcuTalonTest("TurnTools", "give") = 0
	Set request = ..NewRequest("turn", "[[mock:recall-ask]] Where is the build server?", "zz-turn-owner-4")
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "the same agent runs a request that gets none")
	Set requests = ..Requests(request)
	Do $$$AssertEquals(requests.%Size(), 1, "with one model request")
}

Method TestMissingClass()
{
	If ..Guard() Quit
	Set host = ..Runner(..#AGENT)
	For class = "OcuTalon.Test.Bridge.ZzNoSuchTurnTools", "OcuTalon.Test.Bridge.ProbeSink" {
		Do ..Use(class)
		Set request = ..NewRequest("turn", "[[mock:recall-ask]] Where is the build server?", "zz-turn-owner-5")
		Set sc = host.OnMessage(request, .reply)
		Do $$$AssertStatusNotOK(sc, "TurnToolsClass " _ class _ " ends the request with an error")
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue((text [ class) && (text [ "TurnToolsClass"), "that names the setting and the class: " _ text)
		Do $$$AssertTrue($Select(class [ "NoSuch": text [ "not compiled", 1: text [ "does not extend"), "and the problem")
		Do $$$AssertEquals(..Requests(request).%Size(), 0, "no model request is sent, so no turn runs without its tools")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "the context is over")
	}
}

/// Puts the TurnToolsClass setting of the Decide item to the class for the test, once (OnAfterOneTest puts it back).
Method Use(class As %String)
{
	Set sc = $ClassMethod(..#FIXTURE, "UseItemSetting", "Decide", "Host", "TurnToolsClass", class, .saved)
	If (..Saved = "") && $IsObject(saved) Set ..Saved = saved.%ToJSON()
	Do $$$AssertStatusOK(sc, "the TurnToolsClass setting of Decide is " _ class)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("TurnToolsClass"), class, "and the accessor reads it")
}

/// A shadow runner of the test adapter for the agent class.
Method Runner(agentClass As %String) As OcuTalon.Bridge.Operation.AgentRunner
{
	Quit ##class(OcuTalon.Test.Bridge.Runner).NewRunner(agentClass, , , "ZzRunner", ..#RUNNERCLASS)
}

/// A request of the kind with the input (carrying its ItemId, so that the mock's log finds it) and the owner. A turn of provenance user is linked to a
/// conversation of its own.
ClassMethod NewRequest(kind As %String, text As %String, owner As %String) As OcuTalon.Bridge.Msg.Request
{
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", kind, "user", text, .ref, owner)
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	If kind '= "turn" Set request.OwnerRef = owner
	Set ^||ZzTurn("mark", ref) = $ClassMethod("OcuTalon.Test.Contract.Mock", "LogMark")
	Quit request
}

/// The entries of the mock's log for the request, in order.
ClassMethod Requests(request As OcuTalon.Bridge.Msg.Request) As %DynamicArray
{
	If $ClassMethod("OcuTalon.Test.Contract.Mock", "LogSince", ^||ZzTurn("mark", request.ItemId), .entries) '= 1 Quit []
	Quit $ClassMethod(..#FIXTURE, "FindRequests", entries, request.ItemId)
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

}
