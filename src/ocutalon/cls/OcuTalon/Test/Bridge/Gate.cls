/// Tests of the governance gate (Story 3.2; AD-6, AD-9, AD-10, AD-24, AD-31). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it
/// reads and writes System Default Settings rows of Decide and, for the end-to-end tests, changes the running production and sends requests to the
/// CI mock. Every row it writes is put back after each test, the end-to-end tests are guarded by the environment of the CI override, and it creates
/// no IRIS user, role or resource: the privileges come from the real service user OcuTalonService (which holds only its own empty role) and from the
/// resources that IRIS makes public. The tool classes are OcuTalon.Test.Bridge.ZzGateTool (the toolset ZzGateTools) and ZzGateOdd.
/// The rows of the I/O matrix of the spec:
///   - TestSafeBuiltInIsAllowedAndReported (1): a safe built-in is allowed and fires turn.step once, with the owner and the exact payload; a sink in
///     error or throw mode changes nothing but one warning;
///   - TestWatchToolsAreClassified (2, DW-143): the three watch tools are safe and read-only by code, and TestEveryBuiltInToolIsClassified scans every
///     built-in tool;
///   - TestRiskyByCodeAndUnclassified (3, 4): risky in code and unclassified calls are denied with NEEDSAPPROVAL and report nothing;
///   - TestDeveloperSetting, TestMalformedSettingFailsClosed (5): the ToolClassification setting classifies a developer's tool after code and never
///     changes what code says; a malformed setting denies the tools that reach it with FAILED;
///   - TestArgumentDependent (6): a code Classify method decides by the arguments, which arrive as an object or a JSON string;
///   - TestSameNameAnotherClass, TestMcpShadow, TestExtension (7, 8, 9): the classification is by (source, name), an mcp: toolref only through the
///     extension, and the extension class must be usable;
///   - TestCallContentCannotClassify (10): nothing in the call or the context classifies it, and the call is not modified;
///   - TestPrivilegeHeld, TestOneLetterPerCall, TestPrivilegeMissing (11 to 13): the service user's privileges, one letter per call;
///   - TestNoContext, TestMalformedCall (14): no context, and a call that is no object or has no name, are denied with FAILED;
///   - TestExceptionEndToEnd, TestDeveloperRiskyEndToEnd, TestAllowedEndToEnd (15 to 17): through a shadow runner and the CI mock;
///   - TestEveryRiskyBuiltInIsDenied, TestGovernanceSample (18): the governance test, through a real %AI.ToolMgr with the gate and the step audit policy;
///     no built-in tool that AI Hub marks REQUIRESAUTH is safe or classifies by its arguments (DW-176), because the gate never reads requires_auth.
/// Also: TestSeveralPairsAndPrivilegeBeforeApproval (every pair of RESOURCES is checked, and the privilege comes before any approval),
/// TestStepLabelIsRedactedAndCut (the label of turn.step), TestClassWideHook (a class-wide Classify outranks the parameters), TestAnyRequestKindAndProvenance
/// (the gate decides every request kind alike), TestPrivilegeInProductionRunnerJob (DW-173: the service user's privilege is checked from the
/// production's own runner job), TestDenialText (what StepAudit.DenialText records for a denial), TestOddValues (only the exact values classify, and what code declares is final), TestSettings (the two settings of Decide), TestOneParser
/// (the installer parses RESOURCES with the gate's parser), TestSentences, TestCanExecute (the callback never raises) and TestGateHasNoProperties.
Class OcuTalon.Test.Bridge.Gate Extends %UnitTest.TestCase
{

Parameter GATE = "OcuTalon.Bridge.Policy.Gate";

/// The test tool class, the odd declarations, the built-in tool classes of rows 1 and 2, the toolset of the sample and the agent.
Parameter TOOLS = "OcuTalon.Test.Bridge.ZzGateTool";

Parameter ODD = "OcuTalon.Test.Bridge.ZzGateOdd";

Parameter REMINDERS = "OcuTalon.Tools.ReminderTools";

Parameter WATCH = "OcuTalon.Tools.WatchFixture";

Parameter SAMPLE = "OcuTalon.Test.Bridge.ZzGateTools";

Parameter AGENT = "OcuTalon.Test.Bridge.ZzGateAgent";

/// The production runner whose agent the production-job test swaps for the gate's agent.
Parameter RUNNER = "ChatAgent";

/// The host sink of the tests.
Parameter SINK = "OcuTalon.Test.Bridge.ProbeSink";

/// The code of every denial.
Parameter DENIED = "<%AICore>ToolAccessDenied";

/// The risky arguments of the built-in tools that classify by their arguments (a Classify method), one entry for each: provider:name=<JSON>,
/// the entries separated by a line feed. The governance test runs such a tool with them, and fails for a tool of that kind that has no entry
/// (TestEveryRiskyBuiltInIsDenied). There is no such tool today.
Parameter CASES = "";

/// The System Default Settings rows before the test touched them (RunnerFixture.RememberDefault), to be put back.
Property SavedRows As %List;

/// The setting of Decide's HostSinkClass before a test put its own (RunnerFixture.UseItemSetting), "" when none was put.
Property SavedSink As %DynamicObject;

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

/// What ChatAgent had of the AgentClass and AgentAllowList settings before the production-job test swapped in the gate's agent
/// (RunnerFixture.UseAgent), "" while it is not swapped.
Property SavedAgent As %DynamicObject;

/// 1 while the entries of the production's runners are pointed at the CI mock key variable (RunnerFixture.PointKeys).
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The ItemIds of the requests that the production-job test sent to the production's runner, whose Usage rows OnAfterOneTest deletes.
Property ItemIds As %List;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ..Clean()
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set rows = ""
	For setting = "ToolClassification", "ClassificationClass", "ServiceUser" {
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).RememberDefault(.rows, "Decide", setting)
		Do ##class(Ens.Config.DefaultSettings).%DeleteId(##class(OcuTalon.Test.Agent.RunnerFixture).DefaultId("Decide", setting))
	}
	Set ..SavedRows = rows
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Clean()
	If $IsObject(..SavedAgent) && ..SavedAgent.%IsDefined("allowListSet") {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).RestoreAgent(..#RUNNER, ..SavedAgent), "ChatAgent's agent class and allow-list are put back")
		Set ..SavedAgent = ""
	}
	If ..Pointed {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys(), "the entries of the runners are put back to the placeholder of the Provider step")
		Set ..Pointed = 0
	}
	If $IsObject(..SavedSink) && ..SavedSink.%IsDefined("valueSet") {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).RestoreItemSetting("Decide", ..SavedSink), "Decide's HostSinkClass is put back")
		Set ..SavedSink = ""
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..SavedRows), "the System Default Settings rows of the test are put back")
	Set ..SavedRows = ""
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE Agent = ?", "ZzRunner")
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Quit $$$OK
}

/// Row 1: a safe built-in (set_reminder of ReminderTools) is allowed, and the sink gets exactly one turn.step: the context's OwnerRef as owner, and
/// the payload {"decisionRef": <the DecisionRef>, "label": "Setting a reminder"}. A sink that returns an error or throws changes nothing: the call is
/// still allowed, and Decide.FireEvent logs one warning.
Method TestSafeBuiltInIsAllowedAndReported()
{
	Set request = ..Begin()
	Set sc = ..Verdict("set_reminder", ..#REMINDERS, {}, ..#SINK)
	Do $$$AssertStatusOK(sc, "a safe built-in is allowed")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "and the sink got one call")
	Set call = $Get(^||ZzProbeSink(1))
	Do $$$AssertEquals($ListGet(call, 1), "turn.step", "of the type turn.step")
	Do $$$AssertEquals($ListGet(call, 2), request.OwnerRef, "owned by the OwnerRef of the context")
	Do $$$AssertEquals($ListGet(call, 3), {"decisionRef": (request.DecisionRef), "label": "Setting a reminder"}.%ToJSON(), "with exactly the DecisionRef and the step label")
	For mode = "error", "throw" {
		Kill ^||ZzProbeSink
		Set ^||ZzProbeSink("mode") = mode
		Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set sc = ..Verdict("set_reminder", ..#REMINDERS, {}, ..#SINK)
		Do $$$AssertStatusOK(sc, "a sink in "_mode_" mode: the call is still allowed")
		Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "the sink was called once")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Process.Decide", "FireEvent", $ListBuild("turn.step")), 1, "and FireEvent logged one warning")
	}
}

/// Row 2 (DW-143): the three watch tools are safe, read-only and not trusted output, classified by code. A tool that is trusted output
/// (list_reminders) says so.
Method TestWatchToolsAreClassified()
{
	For name = "read_failed_messages", "read_event_log", "read_item_settings" {
		Set result = ##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(..#WATCH, name)
		Do $$$AssertEquals(result.%ToJSON(), {"classification": "safe", "readOnly": 1, "trustedOutput": 0, "by": "code"}.%ToJSON(), name_" is safe and read-only, by code")
	}
	Set result = ##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(..#REMINDERS, "list_reminders")
	Do $$$AssertEquals(result.%ToJSON(), {"classification": "safe", "readOnly": 1, "trustedOutput": 1, "by": "code"}.%ToJSON(), "list_reminders is safe, read-only and trusted output")
	Set result = ##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(..#REMINDERS, "set_reminder")
	Do $$$AssertEquals(result.%ToJSON(), {"classification": "safe", "readOnly": 0, "trustedOutput": 0, "by": "code"}.%ToJSON(), "set_reminder is safe, and neither read-only nor trusted output")
}

/// DW-143's scan: every tool of every toolset of OcuTalon.Tools is classified by code (safe or risky), so that no built-in tool is held as
/// unclassified. A tool that classifies by its arguments is asked with {}.
Method TestEveryBuiltInToolIsClassified()
{
	Set toolsets = ..BuiltInToolsets()
	Do $$$AssertTrue($ListLength(toolsets) > 1, "the scan found the built-in toolsets: "_$ListLength(toolsets))
	Set seen = 0
	Set unclassified = ""
	Set position = 0
	While $ListNext(toolsets, position, toolset) {
		Set iterator = $ClassMethod(toolset, "%New").%Discover().tools.%GetIterator()
		While iterator.%GetNext(, .tool) {
			Set seen = seen + 1
			Try {
				Set result = ##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(tool.provider, tool.name, {})
				If (result.by '= "code") || ((result.classification '= "safe") && (result.classification '= "risky")) Set unclassified = unclassified _ " " _ tool.name
			} Catch {
				Set unclassified = unclassified _ " " _ tool.name _ " (raises)"
			}
		}
	}
	Do $$$AssertTrue(seen '< 6, "the scan saw the tools of the reminders and the watch: "_seen)
	Do $$$AssertEquals(unclassified, "", "every built-in tool is classified by code")
}

/// Rows 3 and 4: a tool that is risky in code (zz_gate_held), an unclassified tool (zz_gate_risky, with no setting entry) and a call whose metadata
/// has no origin_class are denied with NEEDSAPPROVAL, and the sink gets no call.
Method TestRiskyByCodeAndUnclassified()
{
	Do ..Begin()
	Set needs = $Parameter(..#GATE, "NEEDSAPPROVAL")
	Set sc = ..Verdict("zz_gate_held", ..#TOOLS, {}, ..#SINK)
	Do $$$AssertEquals(..Sentence(sc), needs, "a tool that is risky in code is denied with NEEDSAPPROVAL")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and the sink gets no call")
	Set sc = ..Verdict("zz_gate_risky", ..#TOOLS, {}, ..#SINK)
	Do $$$AssertEquals(..Sentence(sc), needs, "an unclassified tool is denied with NEEDSAPPROVAL")
	Set sc = ##class(OcuTalon.Bridge.Policy.Gate).Check("zz_gate_risky", ..Call("zz_gate_risky", {}), {}, ..#SINK)
	Do $$$AssertEquals(..Sentence(sc), needs, "so is a call whose metadata has no origin_class")
	Set sc = ##class(OcuTalon.Bridge.Policy.Gate).Check("set_reminder", ..Call("set_reminder", {}), "", ..#SINK)
	Do $$$AssertEquals(..Sentence(sc), needs, "and one whose metadata is no object, though ReminderTools has a tool of that name")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "the sink got no call for any of them")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(..#TOOLS, "zz_gate_risky").%ToJSON(), {"classification": "", "readOnly": 0, "trustedOutput": 0, "by": ""}.%ToJSON(), "an unclassified tool has no classification, flags or origin")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf("", "zz_gate_risky").classification_"|"_##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(..#TOOLS, "").classification, "|", "and so is a call with no source or no name")
}

/// Row 5: the ToolClassification setting of Decide classifies the tools that code does not: zz_gate_risky risky and zz_gate_safe safe, both by
/// setting; it never changes what code says: zz_gate_held stays risky and set_reminder of ReminderTools stays safe, both by code. An entry's flags are
/// carried. A safe tool is allowed only because of the setting.
Method TestDeveloperSetting()
{
	Do ..Begin()
	Set entries = []
	Do entries.%Push(..Entry(..#TOOLS, "zz_gate_risky", "risky"))
	Do entries.%Push(..Entry(..#TOOLS, "zz_gate_safe", "safe", {"readOnly": 1, "trustedOutput": true}))
	Do entries.%Push(..Entry(..#TOOLS, "zz_gate_held", "safe"))
	Do entries.%Push(..Entry(..#REMINDERS, "set_reminder", "risky"))
	Do ..PutSetting("ToolClassification", entries.%ToJSON())
	Set gate = ..#GATE
	Set result = $ClassMethod(gate, "ClassificationOf", ..#TOOLS, "zz_gate_risky")
	Do $$$AssertEquals(result.classification_"|"_result.by, "risky|setting", "zz_gate_risky is risky, by the setting")
	Set result = $ClassMethod(gate, "ClassificationOf", ..#TOOLS, "zz_gate_safe")
	Do $$$AssertEquals(result.%ToJSON(), {"classification": "safe", "readOnly": 1, "trustedOutput": 1, "by": "setting"}.%ToJSON(), "zz_gate_safe is safe, by the setting, with the flags of its entry")
	Set result = $ClassMethod(gate, "ClassificationOf", ..#TOOLS, "zz_gate_held")
	Do $$$AssertEquals(result.classification_"|"_result.by, "risky|code", "zz_gate_held stays risky, by code, though the setting says safe")
	Set result = $ClassMethod(gate, "ClassificationOf", ..#REMINDERS, "set_reminder")
	Do $$$AssertEquals(result.classification_"|"_result.by, "safe|code", "set_reminder stays safe, by code, though the setting says risky")
	Set result = $ClassMethod(gate, "ClassificationOf", ..#TOOLS, "zz_gate_args")
	Do $$$AssertEquals(result.by, "code", "a tool with a Classify method is classified by code")
	Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_safe", ..#TOOLS, {}, ..#SINK)), "<OK>", "zz_gate_safe is allowed")
	Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_risky", ..#TOOLS, {}, ..#SINK)), $Parameter(gate, "NEEDSAPPROVAL"), "zz_gate_risky is denied")
	Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_held", ..#TOOLS, {}, ..#SINK)), $Parameter(gate, "NEEDSAPPROVAL"), "zz_gate_held is denied")
	Do $$$AssertEquals(..Sentence(..Verdict("set_reminder", ..#REMINDERS, {}, ..#SINK)), "<OK>", "and set_reminder of ReminderTools is allowed")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 2, "only the two allowed calls were reported")
}

/// Row 5, malformed: a setting that is not JSON, not an array, or holds an entry that is no object, has no class or no tool, says something other
/// than exactly safe or risky, has a key that is unknown or a flag that is not 1 or 0, or repeats a tool, is an error: the tools that reach the
/// setting are denied with FAILED and one warning that names ToolClassification and the tool. A tool that code classifies never reads it.
Method TestMalformedSettingFailsClosed()
{
	Do ..Begin()
	Set tools = ..#TOOLS
	Set good = ..Entry(tools, "zz_gate_risky", "risky")
	Set bad = $ListBuild(
		"not json",
		"{""class"":""x"",""tool"":""y"",""classification"":""risky""}",
		"[1]",
		"[{""tool"":""zz_gate_risky"",""classification"":""risky""}]",
		"[{""class"":"""_tools_""",""classification"":""risky""}]",
		"["_..Entry(tools, "zz_gate_risky", "Risky").%ToJSON()_"]",
		"["_..Entry(tools, "zz_gate_risky", "maybe").%ToJSON()_"]",
		"["_..Entry(tools, "zz_gate_risky", "risky", {"extra": 1}).%ToJSON()_"]",
		"["_..Entry(tools, "zz_gate_risky", "risky", {"readOnly": "yes"}).%ToJSON()_"]",
		"["_..Entry(tools, "zz_gate_risky", "risky", {"trustedOutput": 2}).%ToJSON()_"]",
		"["_good.%ToJSON()_","_..Entry(tools, "zz_gate_risky", "safe").%ToJSON()_"]")
	Set failed = $Parameter(..#GATE, "FAILED")
	Set position = 0
	While $ListNext(bad, position, value) {
		Do ..PutSetting("ToolClassification", value)
		Set label = $Extract(value, 1, 70)
		Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set sc = ..Verdict("zz_gate_risky", tools, {}, ..#SINK)
		Do $$$AssertEquals(..Sentence(sc), failed, "'"_label_"': a tool that reaches the setting is denied with FAILED")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, ..#GATE, "Warn", $ListBuild("ToolClassification", "zz_gate_risky")), 1, "with one warning that names ToolClassification and the tool")
		Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_held", tools, {}, ..#SINK)), $Parameter(..#GATE, "NEEDSAPPROVAL"), "a tool that code classifies never reads it")
		Do $$$AssertEquals(..Sentence(..Verdict("set_reminder", ..#REMINDERS, {}, ..#SINK)), "<OK>", "and a safe built-in is still allowed")
	}
	Set thrown = 0
	Try {
		Set result = ##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(tools, "zz_gate_risky")
	} Catch exception {
		Set thrown = 1
	}
	Do $$$AssertEquals(thrown, 1, "ClassificationOf throws for a malformed setting")
	Do ..PutSetting("ToolClassification", "["_good.%ToJSON()_"]")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(tools, "zz_gate_risky").by, "setting", "control: the well formed setting is read")
	Do ..PutSetting("ToolClassification", $Char(32, 9, 10))
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(tools, "zz_gate_risky").by, "", "control: a setting of white space is none")
}

/// Row 6: zz_gate_args classifies by its arguments (ClassifyZZGATEARGS): safe for {"to":"user"} and risky otherwise, whether the arguments come as an
/// object or as a JSON string. Arguments that are not JSON are an error (FAILED). A call with no arguments counts as {}.
Method TestArgumentDependent()
{
	Do ..Begin()
	Set gate = ..#GATE
	Set needs = $Parameter(gate, "NEEDSAPPROVAL")
	Set user = {"to": "user"}
	Set other = {"to": "x@example.com"}
	Set result = $ClassMethod(gate, "ClassificationOf", ..#TOOLS, "zz_gate_args", user)
	Do $$$AssertEquals(result.classification_"|"_result.by, "safe|code", "for {""to"":""user""} the tool is safe, by code")
	Set result = $ClassMethod(gate, "ClassificationOf", ..#TOOLS, "zz_gate_args", other)
	Do $$$AssertEquals(result.classification_"|"_result.by, "risky|code", "for another recipient it is risky, by code")
	Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_args", ..#TOOLS, user, ..#SINK)), "<OK>", "an object {""to"":""user""} is allowed")
	Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_args", ..#TOOLS, user.%ToJSON(), ..#SINK)), "<OK>", "so is the same JSON string")
	Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_args", ..#TOOLS, other, ..#SINK)), needs, "an object with another recipient is denied")
	Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_args", ..#TOOLS, other.%ToJSON(), ..#SINK)), needs, "so is the same JSON string")
	Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_args", ..#TOOLS, "", ..#SINK)), needs, "and a call with no arguments")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 2, "the sink got a call for each allowed one")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_args", ..#TOOLS, "not json", ..#SINK)), $Parameter(gate, "FAILED"), "arguments that are not JSON are denied with FAILED")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, gate, "Warn", $ListBuild("zz_gate_args")), 1, "with one warning that names the tool")
	Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_args", ..#TOOLS, "[1,2]", ..#SINK)), $Parameter(gate, "FAILED"), "and so are arguments that are JSON but no object")
}

/// Only the exact values safe and risky classify a tool, in a parameter, a Classify method or the setting; what code declares is final, so a value
/// that is not exact leaves the tool unclassified whatever the setting says, while an empty parameter declares nothing. A flag is 1 only when exactly 1.
Method TestOddValues()
{
	Set gate = ..#GATE
	Set odd = ..#ODD
	For name = "odd_param", "odd_hook" {
		Set result = $ClassMethod(gate, "ClassificationOf", odd, name, {})
		Do $$$AssertEquals(result.%ToJSON(), {"classification": "", "readOnly": 0, "trustedOutput": 0, "by": ""}.%ToJSON(), name_": a declared value that is not exactly safe or risky leaves the tool unclassified")
	}
	Set entries = []
	For name = "odd_param", "odd_hook", "odd_empty" {
		Do entries.%Push(..Entry(odd, name, "safe"))
	}
	Do ..PutSetting("ToolClassification", entries.%ToJSON())
	For name = "odd_param", "odd_hook" {
		Do $$$AssertEquals($ClassMethod(gate, "ClassificationOf", odd, name, {}).classification, "", name_": and no setting changes that")
	}
	Set result = $ClassMethod(gate, "ClassificationOf", odd, "odd_empty", {})
	Do $$$AssertEquals(result.classification_"|"_result.by, "safe|setting", "an empty CLASSIFICATION declares nothing, so the setting classifies the tool")
	Set result = $ClassMethod(gate, "ClassificationOf", odd, "odd_flags", {})
	Do $$$AssertEquals(result.%ToJSON(), {"classification": "safe", "readOnly": 0, "trustedOutput": 0, "by": "code"}.%ToJSON(), "READONLY 1.0 and TRUSTEDOUTPUT true are not 1, so both are 0")
}

/// Row 7: set_reminder whose origin_class is ZzGateTool is another tool than ReminderTools' set_reminder: it declares nothing, so it is unclassified
/// and denied, while ReminderTools' is safe.
Method TestSameNameAnotherClass()
{
	Do ..Begin()
	Set sc = ..Verdict("set_reminder", ..#TOOLS, {}, ..#SINK)
	Do $$$AssertEquals(..Sentence(sc), $Parameter(..#GATE, "NEEDSAPPROVAL"), "set_reminder of ZzGateTool is unclassified and denied")
	Do $$$AssertEquals(..Sentence(..Verdict("set_reminder", ..#REMINDERS, {}, ..#SINK)), "<OK>", "while ReminderTools' is allowed")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(..#TOOLS, "set_reminder").by, "", "the classification keys on the class as well as the name")
}

/// Row 8: an MCP call is recognised by its toolref first. With the toolref mcp:zzserver, the name set_reminder and the origin_class ReminderTools,
/// the parameters of ReminderTools are never read, and no ToolClassification entry is either: only the extension could classify it.
Method TestMcpShadow()
{
	Do ..Begin()
	Set needs = $Parameter(..#GATE, "NEEDSAPPROVAL")
	Set call = ..Call("set_reminder", {})
	Set meta = ..Meta(..#REMINDERS)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Policy.Gate).Source("mcp:zzserver", meta), "mcp:zzserver", "the source of an mcp: call is its toolref")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Policy.Gate).Source("MCP:zzserver", meta), "MCP:zzserver", "in any case")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Policy.Gate).Source("set_reminder", meta), ..#REMINDERS, "the source of any other call is the origin_class")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Policy.Gate).Source("set_reminder", {}), "", "or nothing")
	Do $$$AssertEquals(..Sentence(##class(OcuTalon.Bridge.Policy.Gate).Check("mcp:zzserver", call, meta, ..#SINK)), needs, "an MCP tool that shadows a built-in name is unclassified, so it is denied")
	Do $$$AssertEquals(..Sentence(##class(OcuTalon.Bridge.Policy.Gate).Check("MCP:zzserver", call, meta, ..#SINK)), needs, "also with the prefix in capitals")
	Set entries = []
	Do entries.%Push(..Entry("mcp:zzserver", "set_reminder", "safe"))
	Do ..PutSetting("ToolClassification", entries.%ToJSON())
	Do $$$AssertEquals(..Sentence(##class(OcuTalon.Bridge.Policy.Gate).Check("mcp:zzserver", call, meta, ..#SINK)), needs, "and a ToolClassification entry for it changes nothing")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf("mcp:zzserver", "set_reminder").by, "", "no source of an mcp: call reads the setting")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "the sink got no call")
}

/// Row 9: a ClassificationClass row that names ZzGateClassification, which gives safe for (mcp:zzserver, zz_mcp_safe): that MCP tool is safe by
/// extension and allowed; another MCP tool is denied. The extension also classifies a class source that code and the setting leave unclassified
/// (zz_gate_risky), after the ToolClassification setting, and never changes what code declares (zz_gate_held stays risky, odd_param unclassified).
/// It never gets the call's arguments: zz_mcp_args, which it calls safe only when it is given arguments, is denied. A ClassificationClass that is
/// not compiled, or does not extend the base, is an error (FAILED), with one warning.
Method TestExtension()
{
	Set request = ..Begin()
	Do ..PutSetting("ClassificationClass", "OcuTalon.Test.Bridge.ZzGateClassification")
	Set gate = ..#GATE
	Set result = $ClassMethod(gate, "ClassificationOf", "mcp:zzserver", "zz_mcp_safe")
	Do $$$AssertEquals(result.classification_"|"_result.by, "safe|extension", "the extension classifies the MCP tool")
	Set sc = ##class(OcuTalon.Bridge.Policy.Gate).Check("mcp:zzserver", ..Call("zz_mcp_safe", {}), {}, ..#SINK)
	Do $$$AssertStatusOK(sc, "and the call is allowed")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "and reported")
	Do $$$AssertEquals($ListGet($Get(^||ZzProbeSink(1)), 3), {"decisionRef": (request.DecisionRef), "label": "Running a tool"}.%ToJSON(), "with the generic label, since an MCP tool has no class parameters")
	Do $$$AssertEquals(..Sentence(##class(OcuTalon.Bridge.Policy.Gate).Check("mcp:zzserver", ..Call("zz_mcp_other", {}), {}, ..#SINK)), $Parameter(gate, "NEEDSAPPROVAL"), "another tool of the server is denied")
	Do $$$AssertEquals(..Sentence(##class(OcuTalon.Bridge.Policy.Gate).Check("mcp:otherserver", ..Call("zz_mcp_safe", {}), {}, ..#SINK)), $Parameter(gate, "NEEDSAPPROVAL"), "and so is the same name on another server")
	Do $$$AssertEquals($ClassMethod(gate, "ClassificationOf", ..#TOOLS, "zz_gate_safe").by, "", "a class source that code and the setting leave unclassified is asked of the extension, which has none")
	Set result = $ClassMethod(gate, "ClassificationOf", ..#TOOLS, "zz_gate_risky")
	Do $$$AssertEquals(result.classification_"|"_result.by, "safe|extension", "the extension classifies a class source that code and the setting leave unclassified")
	Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_risky", ..#TOOLS, {}, ..#SINK)), "<OK>", "and that call is allowed")
	Set result = $ClassMethod(gate, "ClassificationOf", ..#TOOLS, "zz_gate_held")
	Do $$$AssertEquals(result.classification_"|"_result.by, "risky|code", "it never changes what code declares: zz_gate_held stays risky")
	Do $$$AssertEquals($ClassMethod(gate, "ClassificationOf", ..#ODD, "odd_param", {}).%ToJSON(), {"classification": "", "readOnly": 0, "trustedOutput": 0, "by": ""}.%ToJSON(), "nor a value that code declares badly: odd_param stays unclassified")
	Do $$$AssertEquals(..Sentence(##class(OcuTalon.Bridge.Policy.Gate).Check("mcp:zzserver", ..Call("zz_mcp_args", {"classification": "safe"}), {}, ..#SINK)), $Parameter(gate, "NEEDSAPPROVAL"), "it never gets the call's arguments: zz_mcp_args is denied")
	Do ..PutSetting("ToolClassification", "["_..Entry(..#TOOLS, "zz_gate_risky", "risky").%ToJSON()_"]")
	Set result = $ClassMethod(gate, "ClassificationOf", ..#TOOLS, "zz_gate_risky")
	Do $$$AssertEquals(result.classification_"|"_result.by, "risky|setting", "and a ToolClassification entry comes before it")
	Set failed = $Parameter(gate, "FAILED")
	For class = "OcuTalon.Test.Bridge.ZzGateNoSuchClass", "OcuTalon.Test.Bridge.ProbeNotASink" {
		Do ..PutSetting("ClassificationClass", class)
		Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set sc = ##class(OcuTalon.Bridge.Policy.Gate).Check("mcp:zzserver", ..Call("zz_mcp_safe", {}), {}, ..#SINK)
		Do $$$AssertEquals(..Sentence(sc), failed, class_" as the ClassificationClass: FAILED")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, gate, "Warn", $ListBuild("zz_mcp_safe", "mcp:zzserver", class)), 1, "with one warning that names the tool, its source and the class")
	}
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 2, "the sink got a call for each of the two allowed calls, and no more")
}

/// Row 10: nothing in the call or the context classifies it. zz_gate_held, with metadata {"CLASSIFICATION":"safe","ReadOnly":"1"}, the arguments
/// {"classification":"safe"} and a context whose HostData says {"classification":"safe"}, is denied with NEEDSAPPROVAL, and so is an unclassified
/// tool with the same content. The call object's JSON is unchanged, also when the tool's Classify method changes the arguments it is given (odd_mutate).
Method TestCallContentCannotClassify()
{
	Do ..Begin()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Put("HostData", "{""classification"":""safe""}"), "the context's HostData says safe")
	Set needs = $Parameter(..#GATE, "NEEDSAPPROVAL")
	For name = "zz_gate_held", "zz_gate_risky" {
		Set call = {"id": "call_id", "name": (name), "arguments": {"classification": "safe"}}
		Set meta = {"CLASSIFICATION": "safe", "ReadOnly": "1", "origin_class": (..#TOOLS)}
		Set before = call.%ToJSON()
		Set sc = ##class(OcuTalon.Bridge.Policy.Gate).Check(name, call, meta, ..#SINK)
		Do $$$AssertEquals(..Sentence(sc), needs, name_": denied, whatever the call, its metadata and the context say")
		Do $$$AssertEquals(call.%ToJSON(), before, "and the call is unchanged")
	}
	Set call = {"id": "call_id", "name": "odd_mutate", "arguments": {"to": "user"}}
	Set before = call.%ToJSON()
	Do $$$AssertEquals(..Sentence(##class(OcuTalon.Bridge.Policy.Gate).Check("odd_mutate", call, ..Meta(..#ODD), ..#SINK)), needs, "odd_mutate, whose Classify method changes its input, is denied")
	Do $$$AssertEquals(call.%ToJSON(), before, "and the call keeps its own arguments")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "the sink got no call")
}

/// Row 11: the real service user OcuTalonService holds a public read: zz_gate_public (RESOURCES %DB_IRISLIB:R) is allowed.
Method TestPrivilegeHeld()
{
	Do ..Begin()
	Do $$$AssertEquals($SYSTEM.Security.CheckUserPermission("OcuTalonService", "%DB_IRISLIB", "R"), 1, "control: OcuTalonService reads %DB_IRISLIB through the public resource")
	Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_public", ..#TOOLS, {}, ..#SINK)), "<OK>", "zz_gate_public is allowed")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "and reported")
}

/// Row 12: one letter per call. zz_gate_write needs %DB_IRISLIB:RW; the service user reads but does not write it, so the call is denied with
/// NOPRIVILEGE and the missing pair is %DB_IRISLIB:W.
Method TestOneLetterPerCall()
{
	Do ..Begin()
	Do $$$AssertEquals($SYSTEM.Security.CheckUserPermission("OcuTalonService", "%DB_IRISLIB", "W"), 0, "control: OcuTalonService does not write %DB_IRISLIB")
	Set sc = ..Verdict("zz_gate_write", ..#TOOLS, {}, ..#SINK)
	Do $$$AssertEquals(..Sentence(sc), $Replace($Parameter(..#GATE, "NOPRIVILEGE"), "{privilege}", "%DB_IRISLIB:W"), "zz_gate_write is denied with NOPRIVILEGE, naming %DB_IRISLIB:W")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and the sink gets no call")
}

/// Row 13: zz_gate_admin needs %Admin_Secure:U, which the service user lacks: denied with NOPRIVILEGE, naming the pair. A ServiceUser row that
/// names a user that does not exist denies zz_gate_public (the user has no privilege at all), while a safe tool that declares no resources is still
/// allowed. A RESOURCES value that is no resources is an error (FAILED).
Method TestPrivilegeMissing()
{
	Do ..Begin()
	Set gate = ..#GATE
	Set sc = ..Verdict("zz_gate_admin", ..#TOOLS, {}, ..#SINK)
	Do $$$AssertEquals(..Sentence(sc), $Replace($Parameter(gate, "NOPRIVILEGE"), "{privilege}", "%Admin_Secure:U"), "zz_gate_admin is denied with NOPRIVILEGE, naming %Admin_Secure:U")
	Do ..PutSetting("ServiceUser", "ZzNoSuchGateUser")
	Set sc = ..Verdict("zz_gate_public", ..#TOOLS, {}, ..#SINK)
	Do $$$AssertEquals(..Sentence(sc), $Replace($Parameter(gate, "NOPRIVILEGE"), "{privilege}", "%DB_IRISLIB:R"), "with a ServiceUser that does not exist, zz_gate_public is denied, naming %DB_IRISLIB:R")
	Do $$$AssertEquals(..Sentence(..Verdict("set_reminder", ..#REMINDERS, {}, ..#SINK)), "<OK>", "a safe tool that declares no resources is still allowed")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "only that call was reported")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set sc = ..Verdict("odd_res", ..#ODD, {}, ..#SINK)
	Do $$$AssertEquals(..Sentence(sc), $Parameter(gate, "FAILED"), "a RESOURCES value that is no resources is denied with FAILED")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, gate, "Warn", $ListBuild("odd_res", "RESOURCES")), 1, "with one warning that names the tool")
}

/// Row 14: with no context (after Context.End) every call is denied with FAILED, also a safe one, and the sink gets no call.
Method TestNoContext()
{
	Do ..Begin()
	Do ##class(OcuTalon.Bridge.Context).End()
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set sc = ..Verdict("set_reminder", ..#REMINDERS, {}, ..#SINK)
	Do $$$AssertEquals(..Sentence(sc), $Parameter(..#GATE, "FAILED"), "a safe built-in is denied with FAILED")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and the sink gets no call")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, ..#GATE, "Warn", $ListBuild("set_reminder", ..#REMINDERS)), 1, "with one warning that names the tool and its source")
	Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_held", ..#TOOLS, {}, ..#SINK)), $Parameter(..#GATE, "FAILED"), "so is a risky tool: the missing context is what denies it, before any classification")
}

/// A call that is not an object, or has no name that is a string, is denied with FAILED.
Method TestMalformedCall()
{
	Do ..Begin()
	Set failed = $Parameter(..#GATE, "FAILED")
	Set meta = ..Meta(..#REMINDERS)
	Do $$$AssertEquals(..Sentence(##class(OcuTalon.Bridge.Policy.Gate).Check("set_reminder", "not an object", meta, ..#SINK)), failed, "a call that is a string")
	Do $$$AssertEquals(..Sentence(##class(OcuTalon.Bridge.Policy.Gate).Check("set_reminder", "", meta, ..#SINK)), failed, "an empty call")
	Do $$$AssertEquals(..Sentence(##class(OcuTalon.Bridge.Policy.Gate).Check("set_reminder", {"id": "call_id", "arguments": {}}, meta, ..#SINK)), failed, "a call with no name")
	Do $$$AssertEquals(..Sentence(##class(OcuTalon.Bridge.Policy.Gate).Check("set_reminder", {"id": "call_id", "name": 5}, meta, ..#SINK)), failed, "a call whose name is no string")
	Do $$$AssertEquals(..Sentence(##class(OcuTalon.Bridge.Policy.Gate).Check("set_reminder", {"id": "call_id", "name": ""}, meta, ..#SINK)), failed, "a call whose name is empty")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "the sink got no call")
}

/// The callback itself: %CanExecute returns the decision of Check as AI Hub calls it (the toolref is the tool's name), and raises nothing for
/// input that is not what AI Hub gives. The sink is the HostSinkClass setting of the production, which the test sets to ProbeSink (CI override only).
Method TestCanExecute()
{
	If ..Guard() Quit
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).UseItemSetting("Decide", "Host", "HostSinkClass", ..#SINK, .saved)
	Set ..SavedSink = saved
	Do $$$AssertStatusOK(sc, "Decide's HostSinkClass is ProbeSink")
	If $$$ISERR(sc) Quit
	Do ..Begin()
	Set gate = ##class(OcuTalon.Bridge.Policy.Gate).%New()
	Do $$$AssertStatusOK(gate.%CanExecute("set_reminder", ..Call("set_reminder", {}), ..Meta(..#REMINDERS)), "%CanExecute allows a safe built-in")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "and reports it to the sink that the HostSinkClass setting names")
	Set sc = gate.%CanExecute("zz_gate_held", ..Call("zz_gate_held", {}), ..Meta(..#TOOLS))
	Do $$$AssertEquals(..Sentence(sc), $Parameter(..#GATE, "NEEDSAPPROVAL"), "and denies a risky tool with a ToolAccessDenied status")
	Set sc = gate.%CanExecute("", "", "")
	Do $$$AssertEquals(..Sentence(sc), $Parameter(..#GATE, "FAILED"), "with input that is not a call, it denies with FAILED and raises nothing")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "the denials reported nothing")
	Do $$$AssertEquals(gate.%CanList("zz_gate_held", ..Meta(..#TOOLS)), 1, "%CanList is not the gate's business: every tool stays visible")
}

/// Rows 15 to 17 need the CI override's environment; the model is the CI mock. A shadow runner builds the gate's agent through the real adapter.
/// Row 15: the scenario gate-throw calls zz_gate_throw, whose Classify method raises <UNDEFINED>. The tool does not run, the Reply holds a tool step
/// with the status denied and the FAILED sentence, and the model's next request carries the sentence, and no source line: no ^OcuTalon, no ZzGateTool
/// and no <UNDEFINED>. One warning names zz_gate_throw. Nothing left %CanExecute: the audit policy recorded the denial.
Method TestExceptionEndToEnd()
{
	If ..Guard() Quit
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Do ..Turn("gate-throw", .reply, .requests, .request, .host)
	If '$IsObject(reply) Quit
	Set failed = $Parameter(..#GATE, "FAILED")
	Do $$$AssertEquals(reply.Text, "The CI mock tried the throwing gate test tool.", "the turn is answered with the second reply of the scenario")
	Do $$$AssertEquals($Data(^||ZzGateRan("zz_gate_throw")), 0, "the tool did not run")
	Set step = ..ToolStep(reply)
	Do $$$AssertEquals(step.status, "denied", "the Reply holds a tool step with the status denied")
	Do $$$AssertTrue(step.summary [ (". Denied: Tool access denied: "_$Extract(failed, 1, *-1)_". About "), "and the FAILED sentence after AI Hub's prefix, once and without its closing period: "_step.summary)
	Do $$$AssertEquals(requests.%Size(), 2, "the mock got the request and the one that follows the tool call")
	If requests.%Size() = 2 {
		Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(requests.%Get(1))
		Do $$$AssertEquals($ListLength(results), 1, "the next request carries one tool result")
		Set text = $ListGet(results, 1)
		Do $$$AssertTrue(text [ failed, "which holds the FAILED sentence: "_text)
		For leak = "^OcuTalon", "ZzGateTool", "<UNDEFINED>" {
			Do $$$AssertTrue(text '[ leak, "and no "_leak)
		}
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, ..#GATE, "Warn", $ListBuild("zz_gate_throw", ..#TOOLS)), 1, "one warning names zz_gate_throw and its class")
}

/// Row 16: a developer's tool (zz_gate_risky) that the ToolClassification setting says is risky does not run in a user's turn: the step is denied
/// with NEEDSAPPROVAL, the next request's tool result carries the sentence, and the built agent's AuthPolicy is the gate and its AuditPolicy the step
/// audit policy.
Method TestDeveloperRiskyEndToEnd()
{
	If ..Guard() Quit
	Set entries = []
	Do entries.%Push(..Entry(..#TOOLS, "zz_gate_risky", "risky"))
	Do ..PutSetting("ToolClassification", entries.%ToJSON())
	Do ..Turn("gate-risky", .reply, .requests, .request, .host)
	If '$IsObject(reply) Quit
	Set needs = $Parameter(..#GATE, "NEEDSAPPROVAL")
	Do $$$AssertEquals($Data(^||ZzGateRan("zz_gate_risky")), 0, "the tool did not run")
	Set step = ..ToolStep(reply)
	Do $$$AssertEquals(step.status, "denied", "its step is denied")
	Do $$$AssertTrue(step.summary [ (". Denied: Tool access denied: "_$Extract(needs, 1, *-1)_". About "), "with the NEEDSAPPROVAL sentence after AI Hub's prefix, once and without its closing period: "_step.summary)
	Do $$$AssertEquals(requests.%Size(), 2, "the mock got two requests")
	If requests.%Size() = 2 {
		Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(requests.%Get(1))
		Do $$$AssertTrue($ListGet(results, 1) [ needs, "and the next request's tool result carries the sentence: "_$ListGet(results, 1))
	}
	Set manager = host.Adapter.Agent.ToolManager
	Do $$$AssertTrue($IsObject(manager.AuthPolicy) && manager.AuthPolicy.%IsA(..#GATE), "the built agent's AuthPolicy is the gate")
	Do $$$AssertTrue($IsObject(manager.AuditPolicy) && manager.AuditPolicy.%IsA("OcuTalon.Bridge.Policy.StepAudit"), "and its AuditPolicy the step audit policy")
}

/// Row 17: the scenario gate-safe calls zz_gate_safe, which the ToolClassification setting says is safe; Decide's HostSinkClass is ProbeSink. The tool
/// ran and its step is ok, and the sink got exactly one call, turn.step, owned by the request's OwnerRef, with {"decisionRef": <the request's
/// DecisionRef>, "label": "Running the safe gate test tool"}. The setting is put back after the test, also after a failure.
Method TestAllowedEndToEnd()
{
	If ..Guard() Quit
	Set entries = []
	Do entries.%Push(..Entry(..#TOOLS, "zz_gate_safe", "safe"))
	Do ..PutSetting("ToolClassification", entries.%ToJSON())
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).UseItemSetting("Decide", "Host", "HostSinkClass", ..#SINK, .saved)
	Set ..SavedSink = saved
	Do $$$AssertStatusOK(sc, "Decide's HostSinkClass is ProbeSink")
	If $$$ISERR(sc) Quit
	Do ..Turn("gate-safe", .reply, .requests, .request, .host)
	If '$IsObject(reply) Quit
	Do $$$AssertEquals($Get(^||ZzGateRan("zz_gate_safe")), 1, "the tool ran")
	Set step = ..ToolStep(reply)
	Do $$$AssertEquals(step.status, "ok", "and its step is ok")
	Do $$$AssertEquals(step.label, "Running the safe gate test tool", "with the label of the tool")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "the sink got exactly one call")
	Set call = $Get(^||ZzProbeSink(1))
	Do $$$AssertEquals($ListGet(call, 1), "turn.step", "turn.step")
	Do $$$AssertEquals($ListGet(call, 2), request.OwnerRef, "owned by the OwnerRef of the request")
	Do $$$AssertEquals($ListGet(call, 3), {"decisionRef": (request.DecisionRef), "label": "Running the safe gate test tool"}.%ToJSON(), "with the DecisionRef of the request and the label")
}

/// Row 18, the built-in tools: every tool of every toolset of OcuTalon.Tools whose classification with {} (or with its case, CASES) is not safe, or
/// throws, goes through a fresh %AI.ToolMgr with the gate and the step audit policy in a user's turn, and is denied, its method does not run and its
/// only step is denied. A built-in tool that classifies by its arguments has an entry in CASES, or this test fails. There is no risky built-in tool
/// today, so the test shows that the scan finds the tools and fails nothing. DW-176: no built-in tool that AI Hub marks REQUIRESAUTH (AuthMarks) is
/// safe or classifies by its arguments, because the gate never reads metadata's requires_auth: such a tool declares itself risky.
Method TestEveryRiskyBuiltInIsDenied()
{
	Do ..Governance(..BuiltInToolsets(), ..#CASES, .ran, .noCase, .problems, .seen, .authSafe)
	Do $$$AssertTrue(seen '< 6, "the test saw the tools of the reminders and the watch: "_seen)
	Do $$$AssertEquals($ListToString(problems, "; "), "", "every risky or unclassified built-in tool is denied and does not run (denied here: "_$ListLength(ran)_")")
	Do $$$AssertEquals($ListToString(noCase, ","), "", "every built-in tool with a Classify method has a case in CASES")
	Do $$$AssertTrue(authSafe = "", "no built-in tool that AI Hub marks REQUIRESAUTH is safe or classifies by its arguments: "_$ListToString(authSafe, "; "))
}

/// Row 18, the sample: the toolset ZzGateTools through the same helper. zz_gate_held and zz_gate_risky are run and denied, and so are the other tools
/// that are not safe, among them the one whose Classify method raises; zz_gate_args and zz_gate_throw are flagged for having no case. With the
/// risky arguments of zz_gate_args as its case only zz_gate_throw is flagged, and a case that is not risky is a problem.
Method TestGovernanceSample()
{
	Set sample = $ListBuild(..#SAMPLE)
	Do ..Governance(sample, "", .ran, .noCase, .problems, .seen)
	Do $$$AssertEquals(seen, 9, "the sample has nine tools")
	Do $$$AssertEquals($ListToString(problems, "; "), "", "every one that is not safe was denied, and none ran")
	Do $$$AssertEquals(..Sorted(ran), "set_reminder,zz_gate_args,zz_gate_held,zz_gate_risky,zz_gate_safe,zz_gate_throw", "the tools that are not safe by code were run: zz_gate_held and zz_gate_risky among them")
	Do $$$AssertEquals(..Sorted(noCase), "zz_gate_args,zz_gate_throw", "zz_gate_args and zz_gate_throw are flagged for having no case")
	Set riskyCase = ..#TOOLS_":zz_gate_args={""to"":""x@example.com""}"
	Do ..Governance(sample, riskyCase, .ran, .noCase, .problems, .seen)
	Do $$$AssertEquals($ListToString(problems, "; "), "", "with a risky case for zz_gate_args, nothing is wrong")
	Do $$$AssertEquals(..Sorted(noCase), "zz_gate_throw", "and only zz_gate_throw is flagged")
	Set safeCase = ..#TOOLS_":zz_gate_args={""to"":""user""}"
	Do ..Governance(sample, safeCase, .ran, .noCase, .problems, .seen)
	Do $$$AssertTrue($ListToString(problems, "; ") [ "zz_gate_args: its case is not risky", "a case that classifies safe is a problem: "_$ListToString(problems, "; "))
}

/// The two settings of Decide: ServiceUser (initial value OcuTalonService) and ToolClassification (empty), both of the category Bridge.
Method TestSettings()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set settings = $ListFromString($Parameter(decide, "SETTINGS"))
	Do $$$AssertTrue($ListFind(settings, "ServiceUser:Bridge"), "ServiceUser is a setting of the category Bridge")
	Do $$$AssertTrue($ListFind(settings, "ToolClassification:Bridge"), "and so is ToolClassification")
	Set object = $ClassMethod(decide, "%New", "ZzGate")
	Do $$$AssertEquals(object.ServiceUser, "OcuTalonService", "ServiceUser starts as OcuTalonService")
	Do $$$AssertEquals(object.ServiceUser, ##class(OcuTalon.Install.Step.Users).#SERVICEUSER, "which is the service user that the installer creates")
	Do $$$AssertEquals(object.ToolClassification, "", "and ToolClassification is empty")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser"), "OcuTalonService", "the accessor reads the initial value when no row says otherwise")
	Do ..PutSetting("ServiceUser", "ZzOtherUser")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser"), "ZzOtherUser", "and the System Default Settings row when there is one")
}

/// One parser (Rule 2): the installer's Tools.Parse gives what the gate's Resources gives, and throws what it throws.
Method TestOneParser()
{
	Set value = "ZzA:R,%ZzB_c:WU"
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Tools).Parse(value, "zz").%ToJSON(), ##class(OcuTalon.Bridge.Policy.Gate).Resources(value, "zz").%ToJSON(), "the installer parses a value as the gate does")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Policy.Gate).Resources("", "zz").%Size(), 0, "an empty value is no pair")
	Set installer = ""
	Set direct = ""
	Try {
		Do ##class(OcuTalon.Install.Step.Tools).Parse("ZzRes:X", "zz tool")
	} Catch exception {
		Set installer = exception.AsStatus()
	}
	Try {
		Do ##class(OcuTalon.Bridge.Policy.Gate).Resources("ZzRes:X", "zz tool")
	} Catch exception {
		Set direct = exception.AsStatus()
	}
	Do $$$AssertTrue(($SYSTEM.Status.GetErrorText(installer) '= "") && ($SYSTEM.Status.GetErrorText(installer) = $SYSTEM.Status.GetErrorText(direct)), "and both throw the same error: "_$SYSTEM.Status.GetErrorText(direct))
}

/// The sentences are model-facing ASCII class parameters of the gate that read after AI Hub's "Tool access denied: ": lower case, one sentence
/// that ends in a period, with {privilege} in the one that names a privilege; a denial carries the code of AI Hub's ToolAccessDenied.
Method TestSentences()
{
	Set gate = ..#GATE
	For name = "NEEDSAPPROVAL", "NOPRIVILEGE", "FAILED" {
		Set text = $Parameter(gate, name)
		Do $$$AssertTrue(text ? 1.ANP, name_" is ASCII text: "_text)
		Do $$$AssertTrue($Extract(text) ? 1L, name_" starts in lower case")
		Do $$$AssertEquals($Extract(text, *), ".", name_" ends in a period")
		Do $$$AssertTrue(text [ "nothing was run", name_" says that nothing was run")
	}
	Do $$$AssertTrue($Parameter(gate, "NOPRIVILEGE") [ "{privilege}", "NOPRIVILEGE holds the place of the privilege")
	Do $$$AssertTrue(($Parameter(gate, "NEEDSAPPROVAL") '= $Parameter(gate, "FAILED")) && ($Parameter(gate, "NEEDSAPPROVAL") '= $Parameter(gate, "NOPRIVILEGE")) && ($Parameter(gate, "FAILED") '= $Parameter(gate, "NOPRIVILEGE")), "the three sentences differ, so a test can tell the denials apart")
	Set sc = $ClassMethod(gate, "Denial", "x")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), ..#DENIED, "a denial has the code of ToolAccessDenied")
	Do $$$AssertEquals($Parameter(gate, "DENIEDCODE"), ..#DENIED, "which DENIEDCODE names")
}

/// The gate defines no instance property (AI Hub infers a policy's statefulness from its properties; %%OID comes from the base class), and its
/// STATEFUL parameter is the base's 0.
Method TestGateHasNoProperties()
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM %Dictionary.CompiledProperty WHERE parent = ? AND Origin = ?", ..#GATE, ..#GATE)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 0, "the gate defines no property")
	Do $$$AssertEquals($Parameter(..#GATE, "STATEFUL"), 0, "and is not stateful")
}

/// Several pairs of RESOURCES: each is checked, and the denial names the first that the service user lacks. A call that the service user could not make
/// is denied for the privilege before any approval is asked: a risky tool that declares a resource the service user lacks is denied with NOPRIVILEGE.
Method TestSeveralPairsAndPrivilegeBeforeApproval()
{
	Do ..Begin()
	Set missing = $Parameter(..#GATE, "NOPRIVILEGE")
	Do $$$AssertEquals(..Sentence(..Verdict("odd_two_held", ..#ODD, {}, ..#SINK)), "<OK>", "a tool whose two pairs are both held is allowed")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "and reported")
	Set admin = $Replace(missing, "{privilege}", "%Admin_Secure:U")
	Do $$$AssertEquals(..Sentence(..Verdict("odd_two_late", ..#ODD, {}, ..#SINK)), admin, "the second pair is checked too: the missing %Admin_Secure:U denies the call")
	Do $$$AssertEquals(..Sentence(..Verdict("odd_two_first", ..#ODD, {}, ..#SINK)), admin, "with two pairs missing, the denial names the first")
	Do $$$AssertEquals(..Sentence(..Verdict("odd_risky_res", ..#ODD, {}, ..#SINK)), admin, "a risky tool that declares a resource the service user lacks is denied for the privilege, not for an approval")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "only the allowed call was reported")
}

/// The label of turn.step is redacted and cut as a step's label is (StepBuffer.Part): STEPLABELZZLEAKY of StepsCard holds a Bearer token, and
/// STEPLABELODDLONG of ZzGateOdd is 250 characters long.
Method TestStepLabelIsRedactedAndCut()
{
	Do ..Begin()
	Do $$$AssertStatusOK(..Verdict("zz_leaky", "OcuTalon.Test.Bridge.StepsCard", {}, ..#SINK), "a tool of StepsCard is allowed: its class declares it safe")
	Do $$$AssertStatusOK(..Verdict("odd_long", ..#ODD, {}, ..#SINK), "so is odd_long")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 2, "both were reported")
	Set leaky = {}.%FromJSON($ListGet($Get(^||ZzProbeSink(1)), 3)).label
	Do $$$AssertEquals(leaky, "Reading the card with Bearer [redacted]", "the label passes the redactor: "_leaky)
	Set long = {}.%FromJSON($ListGet($Get(^||ZzProbeSink(2)), 3)).label
	Do $$$AssertEquals($Length(long), ##class(OcuTalon.Bridge.Adapter.StepBuffer).#MAXLABEL, "and a label over the limit is cut to it")
	Do $$$AssertEquals($Extract(long, *-2, *), "...", "ending in three dots")
}

/// The code Classify methods of a class are tried before any CLASSIFICATION parameter, the method of the tool's own name before the class-wide one:
/// in ZzGateWide the class-wide Classify says risky, so wide_plain (which declares nothing) and wide_param (whose parameter says safe) are risky by
/// code, whatever the ToolClassification setting says, while wide_own has a method of its own that says safe.
Method TestClassWideHook()
{
	Set wide = "OcuTalon.Test.Bridge.ZzGateWide"
	Set gate = ..#GATE
	Set entries = []
	For name = "wide_plain", "wide_param", "wide_own" {
		Do entries.%Push(..Entry(wide, name, "safe"))
	}
	Do ..PutSetting("ToolClassification", entries.%ToJSON())
	Set result = $ClassMethod(gate, "ClassificationOf", wide, "wide_plain", {})
	Do $$$AssertEquals(result.classification_"|"_result.by, "risky|code", "the class-wide Classify decides a tool that declares nothing, though the setting says safe")
	Set result = $ClassMethod(gate, "ClassificationOf", wide, "wide_param", {})
	Do $$$AssertEquals(result.classification_"|"_result.by, "risky|code", "and it outranks the CLASSIFICATION parameter of the tool")
	Set result = $ClassMethod(gate, "ClassificationOf", wide, "wide_own", {})
	Do $$$AssertEquals(result.classification_"|"_result.by, "safe|code", "while the method of the tool's own name outranks the class-wide one")
}

/// The gate decides every request kind alike: in a decide, diagnose or turn request, whatever the provenance, a safe built-in is allowed and reported to
/// the sink with the request's own owner and DecisionRef, and a risky tool is denied and reported to nobody.
Method TestAnyRequestKindAndProvenance()
{
	Set needs = $Parameter(..#GATE, "NEEDSAPPROVAL")
	For kind = "decide", "diagnose", "turn" {
		Kill ^||ZzProbeSink
		Set request = ..Begin(kind, "untrusted")
		Do $$$AssertEquals(..Sentence(..Verdict("set_reminder", ..#REMINDERS, {}, ..#SINK)), "<OK>", kind_" with untrusted provenance: a safe built-in is allowed")
		Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "and reported")
		Set call = $Get(^||ZzProbeSink(1))
		Do $$$AssertEquals($ListGet(call, 2)_"|"_$ListGet(call, 3), request.OwnerRef_"|"_{"decisionRef": (request.DecisionRef), "label": "Setting a reminder"}.%ToJSON(), "to the owner and with the DecisionRef of the request")
		Do $$$AssertEquals(..Sentence(..Verdict("zz_gate_held", ..#TOOLS, {}, ..#SINK)), needs, "a risky tool is denied")
		Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "and not reported")
		Do ##class(OcuTalon.Bridge.Context).End()
	}
}

/// DW-173, the production's own runner job: the gate's check of the service user's privileges (CheckUserPermission for a user other than the
/// job's own needs %Admin_Secure:USE) is run from the AgentRunner job of the production, not from the test process. ChatAgent's item gets the gate's
/// agent (RunnerFixture.UseAgent), and a user's turn goes to it through ApprovalStartIn.
///   - the scenario gate-public calls zz_gate_public, which is safe and declares %DB_IRISLIB:R (public): the tool ran in that job (its result
///     {"ran":"zz_gate_public"} is in the model's next request) and its step is ok, so the job can read the service user's privilege;
///   - the scenario gate-admin calls zz_gate_admin, which declares %Admin_Secure:U, which the service user lacks: the step is denied with
///     NOPRIVILEGE naming that pair, and the tool did not run, so the allowed call above is no accident of a check that always answers 1;
///   - the job runs as a user other than the service user, so the check is of another user's privilege, as DW-173 asks.
Method TestPrivilegeInProductionRunnerJob()
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set reason = $ClassMethod(fixture, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set ..Pointed = 1
	Set sc = $ClassMethod(fixture, "PointKeys")
	Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
	If $$$ISERR(sc) Quit
	Set sc = $ClassMethod(fixture, "UseAgent", ..#RUNNER, ..#AGENT, .saved)
	Set ..SavedAgent = saved
	Do $$$AssertStatusOK(sc, "the gate's agent runs behind "_..#RUNNER)
	If $$$ISERR(sc) Quit
	Set user = ..JobUser(..#RUNNER)
	Do $$$AssertTrue(user '= "", "the job of "_..#RUNNER_" runs as the user "_user)
	Do $$$AssertTrue(user '= ##class(OcuTalon.Install.Step.Users).#SERVICEUSER, "which is not the service user, so the check is of another user's privilege")

	Set sc = $ClassMethod(fixture, "Ask", ..#RUNNER, "turn", "user", "Try the public tool. [[mock:gate-public]]", .reply, .requests, .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Do $$$AssertStatusOK(sc, "the turn of gate-public is answered by the production's job")
	If '$IsObject(reply) || 'reply.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(reply.Text, "The CI mock ran the public gate test tool.", "the turn is answered with the second reply of the scenario")
	Set step = ..ToolStep(reply)
	Do $$$AssertEquals(step.status, "ok", "the step of zz_gate_public is ok: the job can check the service user's %DB_IRISLIB:R")
	Do $$$AssertEquals(requests.%Size(), 2, "the mock got the request and the one that follows the tool call")
	If requests.%Size() = 2 {
		Set results = $ClassMethod(fixture, "ToolResults", requests.%Get(1))
		Do $$$AssertEquals($ListToString(results, "|"), "{""ran"":""zz_gate_public""}", "and the tool ran in that job: its result is in the next request")
	}

	Set sc = $ClassMethod(fixture, "Ask", ..#RUNNER, "turn", "user", "Try the admin tool. [[mock:gate-admin]]", .reply, .requests, .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Do $$$AssertStatusOK(sc, "the turn of gate-admin is answered by the production's job")
	If '$IsObject(reply) || 'reply.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Set step = ..ToolStep(reply)
	Do $$$AssertEquals(step.status, "denied", "the step of zz_gate_admin is denied")
	Set missing = $Replace($Parameter(..#GATE, "NOPRIVILEGE"), "{privilege}", "%Admin_Secure:U")
	Do $$$AssertTrue(step.summary [ (". Denied: Tool access denied: "_$Extract(missing, 1, *-1)_". About "), "with NOPRIVILEGE, naming %Admin_Secure:U: "_step.summary)
	If requests.%Size() = 2 {
		Set results = $ClassMethod(fixture, "ToolResults", requests.%Get(1))
		Do $$$AssertTrue($ListToString(results, "|") [ missing, "and the model's next request carries the sentence: "_$ListToString(results, "|"))
		Do $$$AssertTrue($ListToString(results, "|") '[ "{""ran""", "and the tool did not run")
	} Else {
		Do $$$AssertEquals(requests.%Size(), 2, "the mock got two requests")
	}
}

/// What StepAudit.DenialText gives for a denial, through %LogDenial: the step's detail, which is the text between "Denied: " and ". About ". A denial
/// by the gate, as AI Hub wraps it (its own "Tool access denied: " and the full text of the gate's status, which repeats the code), reads
/// "Tool access denied: <sentence>" once, without the sentence's closing period; a status text without AI Hub's wrapper, with or without a closing
/// period, is only cleared of its period; an empty text and an OK status give an empty detail, and an unreadable status still records its step and raises nothing.
/// AI Hub wraps the gate's status in its own ToolAccessDenied status, whose message is "Tool access denied: " and the gate's full status text.
Method TestDenialText()
{
	Set gate = ..#GATE
	Set sentence = "this tool is risky, so nothing was run."
	Set inner = $ClassMethod(gate, "Denial", sentence)
	Set wrapped = $SYSTEM.Status.Error(..#DENIED, $SYSTEM.Status.GetErrorText(inner))
	Do ..AssertDetail(wrapped, "Tool access denied: this tool is risky, so nothing was run", "a denial by the gate as AI Hub wraps it: the prefix and the code once, no closing period")
	Do ..AssertDetail(inner, "Tool access denied: this tool is risky, so nothing was run", "the gate's own status, not wrapped: the same text without its closing period")
	Do ..AssertDetail($SYSTEM.Status.Error(5001, "Policy said no."), "Policy said no", "a status text without the prefix keeps its text and loses its closing period")
	Do ..AssertDetail($SYSTEM.Status.Error(5001, "Policy said no"), "Policy said no", "a text that already ends without a period is kept as it is")
	Do ..AssertDetail($SYSTEM.Status.Error(5001, "Tool access denied: not the gate's code."), "Tool access denied: not the gate's code", "AI Hub's prefix alone, without the repeated code, is not taken off")
	Do ..AssertDetail($SYSTEM.Status.Error(5001, "Policy said no. Ask again later."), "Policy said no. Ask again later", "only the closing period goes, not the ones inside the text")
	Do ..AssertDetail($SYSTEM.Status.Error(5001, ""), "", "an empty text gives an empty detail")
	Set detail = ..DeniedDetail("")
	Do $$$AssertTrue($Extract(detail) '= "<", "an unreadable status still records a denied step and raises nothing (got '"_detail_"')")
	Do ..AssertDetail($$$OK, "", "and so does an OK status")
}

/// --- helpers ---
/// Begins a context of a user's turn (kind turn, provenance user) with refs of its own, and returns the request.
Method Begin(kind As %String = "turn", provenance As %String = "user") As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = provenance
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.Channel = "system"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request), "a context of a user's turn begins")
	Quit request
}

/// The call object AI Hub gives the gate: {"id","name","arguments"}, the arguments an object or a JSON string.
ClassMethod Call(name As %String, arguments As %RegisteredObject = "") As %DynamicObject [ Private ]
{
	Quit {"id": "call_id", "name": (name), "arguments": (arguments)}
}

/// The metadata AI Hub gives the gate for a tool of a toolset: the implementing class and requires_auth.
ClassMethod Meta(class As %String) As %DynamicObject [ Private ]
{
	Quit {"origin_class": (class), "requires_auth": false}
}

/// The gate's decision for the tool of the class (the toolref of a toolset tool is its name), with the sink class.
ClassMethod Verdict(name As %String, class As %String, arguments As %RegisteredObject, sink As %String) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Policy.Gate).Check(name, ..Call(name, arguments), ..Meta(class), sink)
}

/// "<OK>" for an allowed call, "<code ...>" for a status that is no ToolAccessDenied, and otherwise the sentence of the denial, without AI Hub's
/// "Tool access denied: " before it.
ClassMethod Sentence(sc As %Status) As %String [ Private ]
{
	If $$$ISOK(sc) Quit "<OK>"
	Set codes = $SYSTEM.Status.GetErrorCodes(sc)
	If codes '= ..#DENIED Quit "<code "_codes_">"
	Set text = $SYSTEM.Status.GetOneStatusText(sc)
	Set prefix = "Tool access denied: "
	Quit $Select($Extract(text, 1, $Length(prefix)) = prefix: $Extract(text, $Length(prefix) + 1, *), 1: text)
}

/// An entry of the ToolClassification setting, with the members of extra (readOnly, trustedOutput or a wrong key) added.
ClassMethod Entry(class As %String, tool As %String, classification As %String, extra As %DynamicObject = "") As %DynamicObject [ Private ]
{
	Set entry = {"class": (class), "tool": (tool), "classification": (classification)}
	If $IsObject(extra) {
		Set iterator = extra.%GetIterator()
		While iterator.%GetNext(.key, .value) {
			Do entry.%Set(key, value, extra.%GetTypeOf(key))
		}
	}
	Quit entry
}

/// Writes the System Default Settings row of the setting of Decide, after remembering the row as it was (put back after the test).
Method PutSetting(setting As %String, value As %String) [ Private ]
{
	Set rows = ..SavedRows
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RememberDefault(.rows, "Decide", setting)
	Set ..SavedRows = rows
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).PutDefault("Decide", setting, value), "the row of "_setting_" is written")
}

/// Ends the context and the step buffer, and kills the process-private globals of the tools and the sink.
ClassMethod Clean() [ Private ]
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).End()
	Kill ^||ZzGateRan, ^||ZzProbeSink
}

/// 1 when the test must not run: the environment is not the CI override's, and the test fails with the reason.
Method Guard() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).GuardReason()
	If reason = "" Quit 0
	Do $$$AssertTrue(0, reason)
	Quit 1
}

/// Sends a user's turn with the marker of the scenario through a shadow runner that has the gate's agent (the real AgentRunner.OnMessage and
/// adapter) to the CI mock. reply is the runner's Reply, requests the entries of the mock's log that belong to the turn, request the Request and
/// host the runner. The agent is built by the adapter, so its policies are the ones OnAfterAgentInit adds.
Method Turn(scenario As %String, Output reply As OcuTalon.Bridge.Msg.Reply, Output requests As %DynamicArray, Output request As OcuTalon.Bridge.Msg.Request, Output host As OcuTalon.Bridge.Operation.AgentRunner) [ Private ]
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set host = ##class(OcuTalon.Test.Bridge.Runner).NewRunner(..#AGENT)
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.Input = "Try the tool. [[mock:"_scenario_"]] (test "_ref_")"
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.Channel = "system"
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusOK(sc, "the turn of the scenario "_scenario_" is answered")
	Do $$$AssertTrue($IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply"), "with a Reply")
	Do ##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries)
	Set requests = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, ref)
}

/// The one tool step of the Reply, as a dynamic object ({} when it has none).
Method ToolStep(reply As OcuTalon.Bridge.Msg.Reply) As %DynamicObject [ Private ]
{
	Set steps = ##class(%DynamicAbstractObject).%FromJSON(reply.Steps)
	Set found = {}
	Set count = 0
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		If step.kind = "tool" {
			Set found = step
			Set count = count + 1
		}
	}
	Do $$$AssertEquals(count, 1, "the Reply holds one tool step")
	Quit found
}

/// The names of the list, sorted and joined by a comma.
ClassMethod Sorted(list As %List) As %String [ Private ]
{
	Set position = 0
	While $ListNext(list, position, name) {
		Set sorted(name) = ""
	}
	Set joined = ""
	Set name = ""
	For {
		Set name = $Order(sorted(name))
		Quit:name=""
		Set joined = joined _ $Select(joined = "": "", 1: ",") _ name
	}
	Quit joined
}

/// The toolsets of OcuTalon.Tools, as a list of class names (the test-side inventory of CodeRules.ToolClasses, toolsets only).
ClassMethod BuiltInToolsets() As %List [ Private ]
{
	Set toolsets = ""
	Set classes = ##class(OcuTalon.Test.Bridge.CodeRules).ToolClasses(1)
	Set position = 0
	While $ListNext(classes, position, class) {
		If $ClassMethod(class, "%Extends", "%AI.ToolSet") Set toolsets = toolsets _ $ListBuild(class)
	}
	Quit toolsets
}

/// The governance run (row 18) over the tools of the toolsets. cases holds the risky arguments of tools that classify by their arguments
/// (provider:name=<JSON>, separated by a line feed). For each tool: seen counts it; noCase lists (by name) the tools with a Classify method and no
/// case; authSafe lists (by name, with where) the tools that AI Hub marks REQUIRESAUTH (AuthMarks) and that are safe with their arguments or have a
/// Classify method; a tool whose classification with its arguments ({} without a case) is safe is skipped, but a case that is safe is a problem; any other,
/// and any that throws, runs through a fresh %AI.ToolMgr with the gate and the step audit policy, in a user's turn (RunDenied), and is listed in ran
/// when it was denied properly and in problems (with the reason) when not.
Method Governance(toolsets As %List, cases As %String, Output ran As %List, Output noCase As %List, Output problems As %List, Output seen As %Integer, Output authSafe As %List) [ Private ]
{
	Set ran = ""
	Set authSafe = ""
	Set noCase = ""
	Set problems = ""
	Set seen = 0
	For i = 1:1:$Length(cases, $Char(10)) {
		Set line = $Piece(cases, $Char(10), i)
		If line '= "" Set byTool($Piece(line, "=", 1)) = $Piece(line, "=", 2, *)
	}
	Set position = 0
	While $ListNext(toolsets, position, toolset) {
		Set iterator = $ClassMethod(toolset, "%New").%Discover().tools.%GetIterator()
		While iterator.%GetNext(, .tool) {
			Set seen = seen + 1
			Set key = tool.provider_":"_tool.name
			Set hasCase = $Data(byTool(key)) > 0
			Set hook = ##class(OcuTalon.Bridge.Policy.Gate).HookFor(tool.provider, tool.name)
			If (hook '= "") && 'hasCase Set noCase = noCase _ $ListBuild(tool.name)
			Set arguments = $Select(hasCase: {}.%FromJSON(byTool(key)), 1: {})
			Set safe = 0
			Try {
				Set safe = ##class(OcuTalon.Bridge.Policy.Gate).ClassificationOf(tool.provider, tool.name, arguments).classification = "safe"
			} Catch {
				Set safe = 0
			}
			Set marks = ..AuthMarks(toolset, tool)
			If (marks '= "") && (safe || (hook '= "")) Set authSafe = authSafe _ $ListBuild(tool.name_" (REQUIRESAUTH in "_marks_")")
			If safe {
				If hasCase Set problems = problems _ $ListBuild(tool.name_": its case is not risky")
				Continue
			}
			Set outcome = ..RunDenied(toolset, tool.name, arguments)
			If outcome = "" {
				Set ran = ran _ $ListBuild(tool.name)
			} Else {
				Set problems = problems _ $ListBuild(tool.name_": "_outcome)
			}
		}
	}
}

/// Where AI Hub marks the tool of the toolset as requiring an authorization (metadata.requires_auth): the requires_auth of its discovered spec, or the
/// REQUIRESAUTH parameter of its class or of its toolset, joined by a comma; "" when nowhere.
ClassMethod AuthMarks(toolset As %String, tool As %DynamicObject) As %String [ Private ]
{
	Set marks = ""
	If tool.%Get("requires_auth") = 1 Set marks = marks _ $ListBuild("its spec")
	If $Parameter(tool.provider, "REQUIRESAUTH") = 1 Set marks = marks _ $ListBuild(tool.provider)
	If $Parameter(toolset, "REQUIRESAUTH") = 1 Set marks = marks _ $ListBuild(toolset)
	Quit $ListToString(marks, ", ")
}

/// Runs the tool of the toolset through a fresh %AI.ToolMgr whose authorization policy is the gate and whose audit policy is the step audit policy,
/// in a user's turn, and returns "" when AI Hub raised ToolAccessDenied, the tool's method did not run and the only step is denied; otherwise
/// what went wrong. The context and the step buffer are over afterwards.
Method RunDenied(toolset As %String, name As %String, arguments As %DynamicObject) As %String [ Private ]
{
	Kill ^||ZzGateRan
	Do ..Clean()
	Set problem = ""
	Try {
		Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
		Set request.Kind = "turn"
		Set request.Provenance = "user"
		Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set sc = ##class(OcuTalon.Bridge.Context).Begin(request)
		If $$$ISOK(sc) Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).Start(0)
		Set manager = ##class(%AI.ToolMgr).%New()
		If $$$ISOK(sc) Set sc = manager.RegisterToolSet(toolset)
		If $$$ISOK(sc) Set sc = manager.SetAuthPolicy(##class(OcuTalon.Bridge.Policy.Gate).%New())
		If $$$ISOK(sc) Set sc = manager.SetAuditPolicy(##class(OcuTalon.Bridge.Policy.StepAudit).%New())
		If $$$ISERR(sc) {
			Set problem = "the tool manager cannot be set up: "_$SYSTEM.Status.GetErrorText(sc)
		} Else {
			Set raised = ""
			Try {
				Do manager.ExecuteTool(name, arguments)
			} Catch exception {
				Set raised = $SYSTEM.Status.GetErrorCodes(exception.AsStatus())
			}
			If raised '= ..#DENIED Set problem = "the call was not denied (raised '"_raised_"')"
			If $Data(^||ZzGateRan(name)) Set problem = problem _ $Select(problem = "": "", 1: "; ") _ "its method ran"
			Set records = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Records()
			If (records.%Size() '= 1) || (records.%Get(0).status '= "denied") {
				Set problem = problem _ $Select(problem = "": "", 1: "; ") _ "its steps are not one denied step: "_records.%ToJSON()
			} ElseIf (records.%Get(0).summary '[ ". Denied: Tool access denied: ") || (records.%Get(0).summary [ "ERROR") || (records.%Get(0).summary [ "..") {
				Set problem = problem _ $Select(problem = "": "", 1: "; ") _ "its denied step does not read 'Denied: Tool access denied: <sentence without its period>.': "_records.%Get(0).summary
			}
		}
	} Catch exception {
		Set problem = "the run raised "_exception.DisplayString()
	}
	Do ..Clean()
	Quit problem
}

/// Asserts that the detail of the denial of the status (DeniedDetail) is the expected text, and says what it was when it is not.
Method AssertDetail(status As %Status, expected As %String, description As %String) [ Private ]
{
	Set detail = ..DeniedDetail(status)
	Do $$$AssertTrue(detail = expected, description_" (got '"_detail_"')")
}

/// The detail that %LogDenial of the step audit policy records for the status: the text between "Denied: " and ". About " in the summary of the
/// one tool step it puts in a fresh step buffer. The buffer is over afterwards.
ClassMethod DeniedDetail(status As %Status) As %String [ Private ]
{
	Do ..Clean()
	Set detail = "<no step>"
	Try {
		Do ##class(OcuTalon.Bridge.Adapter.StepBuffer).Start(0)
		Set audit = ##class(OcuTalon.Bridge.Policy.StepAudit).%New()
		Set sc = audit.%LogDenial(..Call("zz_gate_held", {}), ..Meta(..#TOOLS), status)
		Set records = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Records()
		If $$$ISOK(sc) && (records.%Size() = 1) && (records.%Get(0).status = "denied") {
			Set detail = $Piece($Piece(records.%Get(0).summary, ". Denied: ", 2, *), ". About ", 1)
		}
	} Catch exception {
		Set detail = "<raised "_exception.DisplayString()_">"
	}
	Do ..Clean()
	Quit detail
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

}
