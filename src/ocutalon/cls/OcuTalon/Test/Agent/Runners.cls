/// Tests of the running agent runners (Story 1.2; AD-6, AD-7, AD-10, AD-19). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): it needs OcuTalon.Production running after the Production step, the CI override's environment (the mock's base URL
/// and OCUTALON_MOCK_KEY_HEADER=1) and the mock's request log. Where it does not have them, the test fails with the reason. CI starts
/// with no model key on purpose, so the tests that need a key point the Config Store entry of each runner at the non-secret CI
/// variable OCUTALON_MOCK_KEY_HEADER (RunnerFixture.PointKeys) and put it back afterwards. The requests go through ApprovalStartIn,
/// the adapterless service of the production, as a caller of the runners will send them.
///   - TestStartsWithNoKey: with no model key in the container, every runner runs; a Request gets an error that names the key
///     placeholder, twice, because the agent is built on first use and a failed build is not kept, and so does a ToolInventory
///     request; nothing reaches the mock and the item keeps its job. Since Story 1.6 (AD-6, AD-8, AD-19; FR-38) Keys.Status is 0 for each
///     runner, and a decide and a turn through Decide are fallbacks with the reason no_key that are never sent: the mock's log holds
///     nothing since the mark, Decide sent only its answer, every item still runs and the event log holds no error or alert row since
///     the Decide sends;
///   - TestStartRefused: a runner whose adapter has a refused setting (SystemPrompt), or whose agent class is not on the allow-list,
///     does not start, and the event log names the setting or the class; with the row put back it starts again;
///   - TestRequestsUnderTheModelRules: the Triage, Diagnosis and Chat requests reach the mock with the model of the runner, a cap of
///     8000, the effort of the runner (none for Chat), no sampling parameter and the cache marker where the cached prefix reaches
///     min_tokens_for_cache (Diagnosis's last tool; the short prefixes of Triage and Chat stay unmarked, and Test.Bridge.Runner
///     shows the block reaching the provider for a long prompt), and the mock accepts every one;
///   - TestToolInventory: the live ToolManager of each runner holds the tools of its agent and no AI Hub shell, filesystem, SQL or
///     web-search tool, and every tool is an OcuTalon tool of source iris whose code is clean (Test.Bridge.CodeRules.ToolCodeClean);
///   - TestForeignMessage: a message of a class the runner does not handle gets "not implemented" and no response, and the runner
///     keeps its job;
///   - TestPoolIsTheCap: each runner has as many alive jobs as its pool size;
///   - TestKeysAreRead: RunnerFixture.KeysAre tells the entries of the Provider step from the entries that PointKeys changed, which is
///     what lets TestStartsWithNoKey start from the entries of the Provider step whatever ran before it;
///   - TestSeedsOfTheProduction: the rows that the Production step seeded for OcuTalon.Production itself: the Effort of each runner
///     (low, high, none) and one AgentAllowList for every item that holds exactly the three agent classes of the runners.
/// Every wait is a poll with a generous ceiling (RunnerFixture.WAITSECONDS and this class's WAITSECONDS): it returns as soon as the
/// system shows what the test waits for, so a slower machine takes longer and does not fail.
/// OnAfterOneTest puts back the rows, the keys and the items that a test changed, also when it failed.
Class OcuTalon.Test.Agent.Runners Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The runners of the production.
Parameter RUNNERS = "TriageAgent,DiagnosisAgent,ChatAgent";

/// The environment variable of the model key, which the entries name as a placeholder.
Parameter KEYVARIABLE = "ANTHROPIC_API_KEY";

/// The model that every runner resolves.
Parameter MODEL = "claude-haiku-5-5";

/// The longest to wait for a refusal to show in the event log and in the jobs, in seconds. A ceiling, not a delay (the wait polls
/// once a second), and as long as RunnerFixture's wait for the items to run.
Parameter WAITSECONDS = 120;

/// 1 when the AgentAllowList row existed when the class began, with its value and description.
Property AllowFound As %Boolean;

Property AllowValue As %String(MAXLEN = "");

Property AllowDescription As %String(MAXLEN = "");

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The ItemIds of the requests that the test sent through Decide, whose rows OnAfterOneTest deletes.
Property ItemIds As %List;

Method OnBeforeAllTests() As %Status
{
	Set id = ..AllowId()
	Set ..AllowFound = ##class(Ens.Config.DefaultSettings).%ExistsId(id)
	If ..AllowFound {
		Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
		Set ..AllowValue = row.SettingValue
		Set ..AllowDescription = row.Description
	}
	Quit $$$OK
}

/// Puts back what a test may have changed: the SystemPrompt row of TriageAgent and the allow-list row, whether the production
/// runs or not, and, when it runs, the keys of the entries, and starts every runner that does not run.
Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).DeleteSteps(itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(..#PRODUCTION_"||TriageAgent||*||SystemPrompt")
	Do ..RestoreAllow()
	If '##class(OcuTalon.Test.Agent.RunnerFixture).Running() Quit $$$OK
	If ..Pointed {
		Set ..Pointed = 0
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys()
	}
	Set runners = $ListFromString(..#RUNNERS)
	Set position = 0
	While $ListNext(runners, position, item) {
		If '$ListLength(##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(item)) Do ##class(OcuTalon.Test.Agent.RunnerFixture).Restart(..#PRODUCTION_"||"_item)
	}
	Quit $$$OK
}

/// With no model key in the container, every runner runs, and a Request to each gets an error that names the key placeholder, with
/// no response. A second Request tries the build again and gets the same error, and so does a ToolInventory request, which needs
/// the built agent too. The entries must hold the placeholder of the Provider step and no job may hold an agent built before, so the
/// test puts the entries back and restarts the runners first. Nothing reaches the mock, and the item keeps its job.
Method TestStartsWithNoKey()
{
	If '..Ready() Quit
	If $SYSTEM.Util.GetEnviron(..#KEYVARIABLE) '= "" {
		Do $$$AssertTrue(0, ..#KEYVARIABLE_" is set in this container: this test is for CI's default of no model key")
		Quit
	}
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).NotRunning(), "", "every item runs with no model key")
	Set placeholder = "@{env:"_..#KEYVARIABLE_"}"
	If '..EnsureKeysAtPlaceholder(placeholder) Quit
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set runners = $ListFromString(..#RUNNERS)
	Set position = 0
	While $ListNext(runners, position, item) {
		Set before = ##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(item)
		Do $$$AssertEquals($ListLength(before), 1, item_" has one job")
		For attempt = 1, 2 {
			Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Ask(item, "decide", "user", "Triage this item.", .reply, .requests)
			Do $$$AssertStatusNotOK(sc, item_" answers request "_attempt_" with an error status")
			Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ placeholder, "that names "_placeholder_": "_$Extract($SYSTEM.Status.GetErrorText(sc), 1, 300))
			Do $$$AssertTrue('$IsObject(reply), "and gives no response")
		}
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send(item, ##class(OcuTalon.Bridge.Msg.ToolInventory).%New(), .inventory)
		Do $$$AssertStatusNotOK(sc, item_" answers a ToolInventory request with an error status too, because it builds the agent")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ placeholder, "that names "_placeholder_": "_$Extract($SYSTEM.Status.GetErrorText(sc), 1, 300))
		Do $$$AssertTrue('$IsObject(inventory), "and gives no inventory")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(item), before, item_" keeps its job")
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Do $$$AssertEquals(entries.%Size(), 0, "nothing reached the mock")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).NotRunning(), "", "and every item still runs")

	// Decide stops the same configuration before anything is sent: no_key (AC2, AC6)
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set runners = $ListFromString(..#RUNNERS)
	Set position = 0
	While $ListNext(runners, position, item) {
		Set status = ##class(OcuTalon.Bridge.Keys).Status(item)
		Do $$$AssertEquals(status, 0, "Keys.Status of "_item_" is 0: its key is not set")
		Do $$$AssertTrue((status = 0) || (status = 1), "exactly 0 or 1: '"_status_"'")
	}
	Set errorMark = $ClassMethod(fixture, "EventMark")
	Set mockMark = $ClassMethod(mock, "LogMark")
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "Triage this item.", .decideRef)
	Set ..ItemIds = ..ItemIds _ $ListBuild(decideRef)
	Set sc = $ClassMethod(fixture, "Run", request, .answer, .session)
	Do $$$AssertStatusOK(sc, "a decide through Decide is answered")
	Do $$$AssertEquals($Select($IsObject(answer): answer.%ClassName(1)_"|"_answer.Outcome_"|"_answer.Fallback_"|"_answer.FallbackReason, 1: "none"), "OcuTalon.Bridge.Msg.DecisionResponse|tellnow|1|no_key", "with a fallback with the reason no_key")
	Set row = $ClassMethod(fixture, "DecisionOf", decideRef, "decide")
	Do $$$AssertTrue($IsObject(row) && (row.Fallback = 1) && (row.FallbackReason = "no_key"), "and a row that says the same")
	Do $$$AssertEquals($ClassMethod(fixture, "Targets", $ClassMethod(fixture, "Headers", session, "Decide")), "ApprovalStartIn", "Decide sent no runner request and no timer, only its answer")
	Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", "What is going on?", .turnRef)
	Set ..ItemIds = ..ItemIds _ $ListBuild(turnRef)
	Set sc = $ClassMethod(fixture, "Run", request, .answer, .session)
	Do $$$AssertStatusOK(sc, "a turn through Decide is answered")
	Do $$$AssertEquals($Select($IsObject(answer): answer.%ClassName(1)_"|"_answer.Outcome_"|"_answer.Fallback_"|"_answer.FallbackReason_"|"_answer.Text, 1: "none"), "OcuTalon.Bridge.Msg.Reply|tellnow|1|no_key|", "with a no_key fallback Reply that has no text")
	Set row = $ClassMethod(fixture, "DecisionOf", turnRef, "turn")
	Do $$$AssertTrue($IsObject(row) && (row.Fallback = 1) && (row.FallbackReason = "no_key"), "and a row that says the same")
	Do $$$AssertEquals($ClassMethod(fixture, "Targets", $ClassMethod(fixture, "Headers", session, "Decide")), "ApprovalStartIn", "Decide sent only its answer for the turn too")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mockMark, .entries), "the mock's log is read")
	Do $$$AssertEquals(entries.%Size(), 0, "nothing reached the mock since the mark")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).NotRunning(), "", "every item still runs")
	Do $$$AssertEquals($ListToString($ClassMethod(fixture, "ErrorRows", errorMark), "; "), "", "and the event log holds no error or alert row since the mark")
}

/// A SystemPrompt row for TriageAgent, and then an allow-list that leaves out Triage, each stop the item at its start: it has no
/// job, and the event log of the item names the setting or the class. The other runners keep their jobs for the SystemPrompt row,
/// which is the item's own; the allow-list row is for every item, so they restart and run again. With the rows put back and a
/// restart, the item runs again.
Method TestStartRefused()
{
	If '..Ready() Quit
	Set item = "TriageAgent"
	Set name = ..#PRODUCTION_"||"_item
	Set others = $ListBuild("DiagnosisAgent", "ChatAgent")
	Set otherJobs = ""
	Set position = 0
	While $ListNext(others, position, other) {
		Set jobs = ##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(other)
		Do $$$AssertEquals($ListLength(jobs), 1, other_" has its one job before the change")
		Set otherJobs = otherJobs _ $ListBuild(jobs)
	}
	Try {
		Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).WriteDefault(..#PRODUCTION, item, "SystemPrompt", "A prompt that the runner must refuse.", "Written by a test; the test deletes it."), "a SystemPrompt row is written for "_item)
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Restart(name, 0), item_" is stopped and started again")
		Do ..AssertRefused(item, mark, "the setting SystemPrompt is set")
		Do ..AssertOthersKeep(others, otherJobs)
		Do $$$AssertStatusOK(##class(Ens.Config.DefaultSettings).%DeleteId(..#PRODUCTION_"||"_item_"||*||SystemPrompt"), "the SystemPrompt row is deleted")
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).Restart(name)
		Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).NotRunning(), "", "with the row deleted and a restart, every item runs")

		Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).WriteDefault(..#PRODUCTION, "*", "AgentAllowList", "OcuTalon.Agent.Diagnosis,OcuTalon.Agent.Chat", "Written by a test; the test puts the seed back."), "an allow-list without Triage is written")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Restart(name, 0), item_" is stopped and started again")
		Do ..AssertRefused(item, mark, "'OcuTalon.Agent.Triage' is not on the AgentAllowList")
		Do ..AssertOthersRun(others)
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(..#PRODUCTION_"||"_item_"||*||SystemPrompt")
	Do ..RestoreAllow()
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).Restart(name)
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).NotRunning(), "", "with the allow-list put back and a restart, every item runs again")
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(item)), 1, item_" has its job again")
}

/// The requests of the three runners reach the mock under the model rules. Each default scenario is picked by the mock key of the
/// agent. The mock accepts every request, so it saw no sampling parameter and a cap of at least 4000.
Method TestRequestsUnderTheModelRules()
{
	If '..Ready() Quit
	If '..Point() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"

	Set sc = $ClassMethod(fixture, "Ask", "TriageAgent", "decide", "user", "A new email arrived in the Orders inbox. Should the user hear about it now?", .reply, .requests)
	Do $$$AssertStatusOK(sc, "the decide Request to TriageAgent is answered")
	Do $$$AssertTrue($IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply"), "with a Reply")
	If $IsObject(reply) {
		Do $$$AssertEquals(reply.Text, $Parameter(fixture, "TRIAGETEXT"), "whose text is the text of triage.json")
		Do $$$AssertEquals(reply.FinishReason, ##class(OcuTalon.Test.Bridge.Runner).#NORMALFINISH, "and whose finish reason is that of a normal reply")
		Do $$$AssertEquals(reply.Tainted, 0, "and which is not tainted")
		Do $$$AssertEquals(reply.HostData, "", "and holds no host data")
	}
	Do $$$AssertEquals(requests.%Size(), 1, "Triage makes one request")
	Do ..AssertRequests(requests, "low", 0, "Triage")

	Set sc = $ClassMethod(fixture, "Ask", "DiagnosisAgent", "diagnose", "user", "Why did the messages of the Orders production fail?", .reply, .requests)
	Do $$$AssertStatusOK(sc, "the diagnose Request to DiagnosisAgent is answered")
	Do $$$AssertTrue($IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply"), "with a Reply")
	If $IsObject(reply) Do $$$AssertEquals(reply.Text, $Parameter(fixture, "DIAGNOSISTEXT"), "whose text is the final text of diagnosis.json")
	Do $$$AssertEquals(requests.%Size(), 2, "Diagnosis makes two requests, one more for the result of its tool")
	Do ..AssertRequests(requests, "high", 1, "Diagnosis")

	Set sc = $ClassMethod(fixture, "Ask", "ChatAgent", "turn", "user", "What is going on in my productions?", .reply, .requests)
	Do $$$AssertTrue(requests.%Size() > 0, "the mock's log holds the requests of the turn to ChatAgent: "_requests.%Size())
	Do ..AssertRequests(requests, "", 0, "Chat")
}

/// Every tool that a running runner holds is an OcuTalon tool of source iris whose code is clean, and the three runners hold exactly
/// the tools of their agents: none for Triage and Chat, the three read-only watch tools for Diagnosis. No AI Hub shell, filesystem,
/// SQL or web-search tool is registered.
Method TestToolInventory()
{
	If '..Ready() Quit
	If '..Point() Quit
	Set watch = $ListBuild(##class(OcuTalon.Tools.Names).#READEVENTLOG, ##class(OcuTalon.Tools.Names).#READFAILEDMESSAGES, ##class(OcuTalon.Tools.Names).#READITEMSETTINGS)
	Set expected("TriageAgent") = ""
	Set expected("DiagnosisAgent") = watch
	Set expected("ChatAgent") = ""
	Set runners = $ListFromString(..#RUNNERS)
	Set position = 0
	While $ListNext(runners, position, item) {
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send(item, ##class(OcuTalon.Bridge.Msg.ToolInventory).%New(), .response)
		Do $$$AssertStatusOK(sc, item_" answers the ToolInventory request")
		If '$IsObject(response) || 'response.%IsA("Ens.StringResponse") {
			Do $$$AssertTrue(0, item_" answers with an Ens.StringResponse")
			Continue
		}
		Set inventory = {}.%FromJSON(response.StringValue)
		Set names = ""
		Set bad = ""
		Set iterator = inventory.tools.%GetIterator()
		While iterator.%GetNext(, .tool) {
			Set names = names _ $ListBuild(tool.name)
			Set problems = ""
			If tool.source '= "iris" Set problems = problems _ " source "_tool.source
			If $Extract(tool.provider, 1, 9) '= "OcuTalon." Set problems = problems _ " provider "_tool.provider
			If (problems = "") && '##class(OcuTalon.Test.Bridge.CodeRules).ToolCodeClean(tool.provider, .code) Set problems = problems _ " code of "_tool.provider_": "_code
			If tool.status '= "available" Set problems = problems _ " status "_tool.status
			If tool.reason '= "" Set problems = problems _ " reason "_tool.reason
			If problems '= "" Set bad = bad _ " "_tool.name_":"_problems
		}
		Do $$$AssertEquals(bad, "", item_" holds only available OcuTalon tools of source iris with clean code")
		Do $$$AssertEquals($ListToString(..Sorted(names)), $ListToString(expected(item)), item_" holds exactly the tools of its agent: "_$ListToString(names))
		Set iterator = inventory.tools.%GetIterator()
		While iterator.%GetNext(, .tool) {
			Do $$$AssertEquals(tool.provider, "OcuTalon.Tools.WatchFixture", item_"'s tool "_tool.name_" is a method of the Watch fixture")
		}
	}
}

/// A message of a class that a runner does not handle gets "not implemented" (code 5003), with no response, and the runner keeps
/// its job. This is what Lane B's live check of the stubs sends to TriageAgent.
Method TestForeignMessage()
{
	If '..Ready() Quit
	Set item = "TriageAgent"
	Set before = ##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(item)
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send(item, ##class(Ens.StringRequest).%New("x"), .response)
	Do $$$AssertStatusNotOK(sc, item_" answers an Ens.StringRequest with an error status")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "with the code 5003")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "#5003: Not implemented", "and the text of the stubs: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertTrue('$IsObject(response), "and no response")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(item), before, item_" keeps its job")
}

/// Each runner has as many alive jobs as its pool size: the pool size is the concurrency cap of the runner (AD-6).
Method TestPoolIsTheCap()
{
	If '..Ready() Quit
	Set runners = $ListFromString(..#RUNNERS)
	Set position = 0
	While $ListNext(runners, position, item) {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT PoolSize FROM Ens_Config.Item WHERE Production = ? AND Name = ?", ..#PRODUCTION, item)
		Set found = result.%Next()
		Do $$$AssertTrue(found, item_" is an item of the production")
		If 'found Continue
		Set pool = result.%GetData(1)
		Do $$$AssertEquals(pool, 1, item_" has a pool size of 1")
		Do $$$AssertEquals($ListLength(##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(item)), pool, item_" has as many alive jobs as its pool size")
	}
}

/// RunnerFixture.KeysAre reads the api_key placeholder of each runner's Config Store entry: true for the placeholder of the Provider
/// step before PointKeys, true for the placeholder of the CI mock key variable and false for the first one after it. The test
/// starts from the entries of the Provider step, and OnAfterOneTest puts them back.
Method TestKeysAreRead()
{
	If '..Ready() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set placeholder = "@{env:"_..#KEYVARIABLE_"}"
	Set mockKey = "@{env:"_$Parameter(fixture, "MOCKKEYVARIABLE")_"}"
	If '..EnsureKeysAtPlaceholder(placeholder) Quit
	Do $$$AssertNotTrue($ClassMethod(fixture, "KeysAre", mockKey), "the entries do not hold "_mockKey_" before they are pointed")
	Do $$$AssertNotTrue($ClassMethod(fixture, "KeysAre", "@{env:ZZ_NO_SUCH_VARIABLE}"), "and do not hold a variable that nothing names")
	If '..Point() Quit
	Do $$$AssertTrue($ClassMethod(fixture, "KeysAre", mockKey), "after PointKeys every entry holds "_mockKey)
	Do $$$AssertNotTrue($ClassMethod(fixture, "KeysAre", placeholder), "and none holds "_placeholder)
}

/// The Production step has seeded the rows of OcuTalon.Production itself: the Effort of each runner comes from the EFFORT of its
/// agent class (low for Triage, high for Diagnosis, none for Chat), and one AgentAllowList for every item holds exactly the
/// AgentClass of the three runners, in the order of the runners, so that the allow-list admits no other agent class. The rows are
/// read the way a runner item resolves them.
Method TestSeedsOfTheProduction()
{
	If '..Ready() Quit
	Set expected("TriageAgent") = $ListBuild("OcuTalon.Agent.Triage", "low")
	Set expected("DiagnosisAgent") = $ListBuild("OcuTalon.Agent.Diagnosis", "high")
	Set expected("ChatAgent") = $ListBuild("OcuTalon.Agent.Chat", "")
	Set allowed = "OcuTalon.Agent.Triage,OcuTalon.Agent.Diagnosis,OcuTalon.Agent.Chat"
	Set runners = $ListFromString(..#RUNNERS)
	Set position = 0
	While $ListNext(runners, position, item) {
		Set name = ..#PRODUCTION_"||"_item
		Set value = ##class(Ens.Director).GetAdapterSettingValue(name, "AgentClass", .sc)
		Do $$$AssertStatusOK(sc, item_"'s AgentClass is read")
		Do $$$AssertEquals(value, $List(expected(item), 1), item_" runs "_$List(expected(item), 1))
		Set value = ##class(Ens.Director).GetAdapterSettingValue(name, "Effort", .sc)
		Do $$$AssertStatusOK(sc, item_"'s Effort is read")
		Do $$$AssertEquals(value, $List(expected(item), 2), item_" resolves the effort '"_$List(expected(item), 2)_"' (empty: none)")
		Set value = ##class(Ens.Director).GetAdapterSettingValue(name, "AgentAllowList", .sc)
		Do $$$AssertStatusOK(sc, item_"'s AgentAllowList is read")
		Do $$$AssertEquals(value, allowed, item_" resolves the allow-list of the three agent classes of the runners")
	}
}

/// --- helpers ---
/// 1 when OcuTalon.Production runs, every item of it has its job (the wait is a poll, up to RunnerFixture.WAITSECONDS), and the
/// environment is the CI override's (Test.Agent.RunnerFixture.ReadyReason). Otherwise the test fails with the reason, and quits.
Method Ready() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()
	If reason = "" Quit 1
	Do $$$AssertTrue(0, reason)
	Quit 0
}

/// Makes the entries of the runners hold the placeholder and the runners run with no agent built: the entries are put back to the
/// placeholder of the Provider step and every runner is restarted, whatever a test before this one left, so that no job holds an
/// agent that was built with another key. 1 when every entry holds the placeholder. Otherwise the test fails with the reason, and
/// quits.
Method EnsureKeysAtPlaceholder(placeholder As %String) As %Boolean [ Private ]
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Do $$$AssertStatusOK($ClassMethod(fixture, "RestoreKeys"), "the entries of the runners are put back to the placeholder of the Provider step, and the runners restarted")
	Set holds = $ClassMethod(fixture, "KeysAre", placeholder)
	Do $$$AssertTrue(holds, "the entry of each runner holds the placeholder "_placeholder)
	Quit holds
}

/// Points the keys of the runners at the CI mock key variable, and remembers to put them back. 1 when it worked.
Method Point() As %Boolean [ Private ]
{
	Set ..Pointed = 1
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).PointKeys()
	Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
	Quit $$$ISOK(sc)
}

/// Asserts what the mock logged for the requests of one runner: the model of the runner, a cap of 8000, the effort (none when
/// effort is ""), and no sampling parameter. AI Hub marks a block for the cache only when the prefix up to it reaches
/// min_tokens_for_cache (512): the system prompts of the three agents are about 190 to 310 tokens, so no system block is marked,
/// and a runner with tools (tools is 1) has the marker on its last tool, where the prefix of system and tools reaches the threshold,
/// while a runner without tools has none at all (measured in Story 1.2). The mock accepted each one: status 200 and nothing
/// rejected.
Method AssertRequests(requests As %DynamicArray, effort As %String, tools As %Boolean, label As %String) [ Private ]
{
	Set iterator = requests.%GetIterator()
	While iterator.%GetNext(.position, .logged) {
		Set here = label_" request "_(position + 1)
		Do $$$AssertEquals(logged.model, ..#MODEL, here_" names "_..#MODEL)
		Do $$$AssertEquals(logged.maxTokens, 8000, here_" has a cap of 8000")
		Do $$$AssertEquals(logged.status, 200, here_" is accepted")
		Do $$$AssertEquals(logged.%GetTypeOf("rejected"), "null", here_" is not rejected")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Effort(logged), effort, here_" asks for the effort '"_effort_"'")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).CacheMark(logged.request.system), "", here_" leaves the system block unmarked: its prefix is below min_tokens_for_cache")
		If tools {
			Set count = logged.request.tools.%Size()
			Do $$$AssertTrue(count > 0, here_" offers tools: "_count)
			For i = 0:1:count - 1 {
				Set expectedMark = $Select(i = (count - 1): "{""type"":""ephemeral""}", 1: "")
				Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).CacheMark(logged.request.tools.%Get(i)), expectedMark, here_" tool "_(i + 1)_" of "_count_" is marked only if it is the last")
			}
		} Else {
			Do $$$AssertEquals(logged.request.tools.%Size(), 0, here_" offers no tool, so no block of it is marked")
		}
		Set json = logged.request.%ToJSON()
		For key = "temperature", "top_p", "top_k" {
			Do $$$AssertTrue(json '[ ("""" _ key _ """"), here_" holds no "_key)
		}
	}
}

/// Asserts that the item does not run and that its event log, after the mark, holds an error row with the text. The wait is a poll
/// up to WAITSECONDS for all three at once: the row, no alive job, and the item named by the Production step's check. The event
/// log row is written while the job ends, so the jobs are read only once the row has shown.
Method AssertRefused(item As %String, mark As %Integer, text As %String) [ Private ]
{
	Set deadline = $ZHorolog + ..#WAITSECONDS
	For {
		Set found = 0
		Set rows = ##class(OcuTalon.Test.Agent.RunnerFixture).EventRows(mark, item)
		Set position = 0
		While $ListNext(rows, position, row) {
			If row [ text Set found = 1
		}
		Set settled = found && '$ListLength(##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(item)) && (##class(OcuTalon.Install.Step.Production).NotRunning() [ item)
		If settled || ($ZHorolog > deadline) Quit
		Hang 1
	}
	Do $$$AssertTrue(found, "the event log of "_item_" says '"_text_"': "_$ListToString(rows, " | "))
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(item)), 0, item_" has no alive job")
	Do $$$AssertTrue(##class(OcuTalon.Install.Step.Production).NotRunning() [ item, "and the Production step's check names it as not running")
}

/// Asserts that the other runners keep the jobs they had.
Method AssertOthersKeep(others As %List, jobs As %List) [ Private ]
{
	Set position = 0
	Set at = 0
	While $ListNext(others, position, other) {
		Set at = at + 1
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(other), $List(jobs, at), other_" keeps the job it had: "_$ListToString($List(jobs, at))_" now "_$ListToString(##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(other)))
	}
}

/// Asserts that the other runners run, each with exactly one alive job. A row for every item (the allow-list) changes the settings of
/// every runner, so the production update that follows a restart gives the other runners new jobs: they run again, but not as the
/// jobs they had. Each runner is given up to WAITSECONDS to get its job.
Method AssertOthersRun(others As %List) [ Private ]
{
	Set deadline = $ZHorolog + ..#WAITSECONDS
	Set position = 0
	While $ListNext(others, position, other) {
		While ($ListLength(##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(other)) '= 1) && ($ZHorolog < deadline) {
			Hang 1
		}
		Do $$$AssertEquals($ListLength(##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(other)), 1, other_" runs with its one job")
	}
}

/// The id of the AgentAllowList row for every item.
ClassMethod AllowId() As %String [ Private ]
{
	Quit ..#PRODUCTION_"||*||*||AgentAllowList"
}

/// Puts the allow-list row back as the class found it: the same value and description, or no row.
Method RestoreAllow() [ Private ]
{
	If ..AllowFound {
		Do ##class(OcuTalon.Install.Step.Production).WriteDefault(..#PRODUCTION, "*", "AgentAllowList", ..AllowValue, ..AllowDescription)
	} Else {
		Do ##class(Ens.Config.DefaultSettings).%DeleteId(..AllowId())
	}
}

/// The names of a list, in order of the name.
ClassMethod Sorted(names As %List) As %List [ Private ]
{
	Set position = 0
	While $ListNext(names, position, name) {
		Set sorted(name) = ""
	}
	Set result = ""
	Set name = ""
	For {
		Set name = $Order(sorted(name))
		Quit:name=""
		Set result = result _ $ListBuild(name)
	}
	Quit result
}

}
