/// Tests of the model-change API and of provider resolution over the running production (Story 17.3; AD-6, AD-7, AD-8, AD-19, AD-22; DW-52).
/// THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they need OcuTalon.Production running with its six runner items and the CI override's environment,
/// and the CI mock. The jobs of a throwaway have no model key, and a key variable that a test sets (a fake text, never a key) is set in the test's process only:
/// CheckModel reads it there, and the runner jobs never see it. So a test that sends a request through a runner after SetModel points the entry's key at the CI mock
/// key variable again (Test.Agent.RunnerFixture PointKeys), as the other live tests do. OnAfterOneTest puts back, in this order: the Config Store entries it
/// touched, to the pair of Anthropic and its placeholder through Merge's model shape (first, because the Provider step now keeps a valid chosen pair); the Provider
/// step; the System Default Settings rows it wrote, as found (no RetryItem row is left); every key variable of the process; and the items that were restarted.
///   - TestSetModelNextRequest: SetModel("TriageAgent", "anthropic", "claude-sonnet-5-5") merges the entry in the model-change shape (no model in it), writes the Model row,
///     restarts TriageAgent alone, and returns old as {provider, model}; the next decide's mock log model and Decision.Model are claude-sonnet-5-5;
///   - TestSecondModel: a second model sets the Model row of TriageAgentRetry and the RetryItem row of TriageAgent; with a refused first attempt the retry answers on
///     the second model; an empty provider and model clear RetryItem, leave the retry item as it is, and the next refusal is a fallback with no retry;
///   - TestSetModelEveryAgent (QA): the same changes for DiagnosisAgent and ChatAgent, a first model, a second model and the clear: each writes its own entry, Model row and
///     RetryItem row, restarts only its own item, and leaves the other agents' models alone;
///   - TestSetModelFailureRestores: a write that fails after the entry was merged (a more specific System Default Settings row of Model, and for a second model of
///     RetryItem, which the read-back finds) returns the error and puts back the entry and the rows as they were, and restarts the item again only when
///     it was restarted; a clear that fails the same way puts the RetryItem row back;
///   - TestRefusedChangeKeepsEverything: refused changes leave the entries, the Model and RetryItem rows and the jobs of every item as they were;
///   - TestResolvedLive: with Anthropic's key variable set in the test's process, and the entries of TriageAgent and TriageAgentRetry on OpenAI with no key, Keys.Absent is 0 for
///     both items and Providers.Resolve names Anthropic with its default model; with the variable unset Absent is 1 again;
///   - TestAdminModelNeverResolves: the same entries with an admin's model are not resolved: Absent is 1, and a decide falls back with no_key and nothing reaches the mock;
///   - TestNoSupportedKey: with every runner's key at an unset variable every item runs, Keys.Status is 0 and Keys.Absent 1 for each, and a decide falls back with no_key with no mock request;
///   - TestUnclassifiedStopLive: a reply with text and the stop reason pause_turn (the scenario unclassified-stop) reaches the runner's reply with the finish reason AI Hub
///     reports, and Decide falls back with unusable and no answer text;
///   - TestNoKeyValueAnywhere: after SetModel and a linked turn of ChatAgent, no store of Test.Agent.KeyScan.Find, no database of KeyProof.GlobalHits, and neither old nor
///     the status text holds the value that the test put in the key variable of its own process; the test fails with a reason when the variable is empty. The runner
///     job never sees that variable (no throwaway job holds a model key), so the scans after the turn prove that nothing in the instance holds what the test process
///     holds, and SetModel's status and old are the outputs that the value could reach; a leak of a key that a job holds is out of reach of a throwaway.
Class OcuTalon.Test.Bridge.ModelChange Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzmodel";

/// Seconds to wait for a turn through the mock.
Parameter WAIT = 90;

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

Parameter SETTINGS = "OcuTalon.Bridge.Settings";

Parameter SCAN = "OcuTalon.Test.Agent.KeyScan";

/// The key variables of the real provider table, which the tests set and clear in the test's process.
Parameter VARIABLES = "ANTHROPIC_API_KEY,OPENAI_API_KEY,GEMINI_API_KEY,AWS_BEARER_TOKEN_BEDROCK";

/// A text that is no key.
Parameter FAKE = "ocutalon-zz-not-a-key";

/// The second model.
Parameter SECOND = "claude-sonnet-5-5";

/// The reason line of the second model's decide reply (ci/mock/scenarios/A/retry-*.json).
Parameter SECONDREASON = "The CI mock answers on the second model.";

/// 1 while the entries of the six runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

/// The countdowns of the mock that the test armed, as a list of markers, to be cleared.
Property Armed As %List;

/// The System Default Settings rows before the test touched them (RunnerFixture RememberDefault), to be put back.
Property SavedRows As %List;

/// The items to start again after the rows are put back.
Property Restarts As %List;

/// The ids of the more specific System Default Settings rows that the test inserted, to be deleted.
Property Specific As %List;

/// The runner items whose Config Store entry the test changed.
Property Touched As %List;

/// The key variables as the test found them, each $ListBuild(variable, was set, value).
Property Env As %List;

/// The mark of the saved AI sessions when the test began (RunnerFixture SessionMark).
Property SessionMark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set ..Env = ""
	Set variables = $ListFromString(..#VARIABLES)
	Set position = 0
	While $ListNext(variables, position, variable) {
		Set ..Env = ..Env _ $ListBuild($ListBuild(variable, $ClassMethod(..#SCAN, "HasEnv", variable), $SYSTEM.Util.GetEnviron(variable)))
		Do $ClassMethod(..#SCAN, "UnsetEnv", variable)
	}
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set fixture = ..#FIXTURE
	If ..Missing = "" {
		Set position = 0
		While $ListNext(..Specific, position, id) {
			If ##class(Ens.Config.DefaultSettings).%ExistsId(id) Do ##class(Ens.Config.DefaultSettings).%DeleteId(id)
		}
		Set ..Specific = ""
		Set position = 0
		While $ListNext(..Armed, position, marker) {
			Do $ClassMethod(..#MOCK, "Arm", marker, "")
		}
		Set ..Armed = ""
		Set position = 0
		While $ListNext(..Touched, position, item) {
			Do ##class(OcuTalon.Bridge.ConfigStore).Merge(..EntryOf(item), {"model_provider": "anthropic", "api_key": "@{env:ANTHROPIC_API_KEY}"})
		}
		If ..Touched '= "" {
			Do ##class(OcuTalon.Install.Step.Provider).Run()
			Set ..Pointed = 0
		}
		Set ..Touched = ""
		Do $ClassMethod(fixture, "DropSince", ..SessionMark)
		Set position = 0
		While $ListNext(..ItemIds, position, itemId) {
			Do $ClassMethod(fixture, "DeleteSteps", itemId)
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
		}
		Set ..ItemIds = ""
		Do $ClassMethod(fixture, "RestoreDefaults", ..SavedRows)
		Set ..SavedRows = ""
		Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
		Set position = 0
		While $ListNext(..Restarts, position, item) {
			Do $ClassMethod(fixture, "Restart", ..#PRODUCTION_"||"_item)
		}
		Set ..Restarts = ""
	}
	Set position = 0
	While $ListNext(..Env, position, one) {
		If $List(one, 2) {
			Do $ClassMethod(..#SCAN, "SetEnv", $List(one, 1), $List(one, 3))
		} Else {
			Do $ClassMethod(..#SCAN, "UnsetEnv", $List(one, 1))
		}
	}
	Set ..Env = ""
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	If ..Missing = "" && $ClassMethod(..#FIXTURE, "Running") {
		Set ..Pointed = 0
		Do $ClassMethod(..#FIXTURE, "RestoreKeys", ..Runners())
	}
	Quit ##super()
}

/// A model change: the entry, the Model row, one restart and the next request.
Method TestSetModelNextRequest()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Do $ClassMethod(..#SCAN, "SetEnv", "ANTHROPIC_API_KEY", ..#FAKE)
	Do ..AtDefault("TriageAgent")
	Set jobs = ..Jobs()
	Set old = ""
	Set sc = $ClassMethod(..#SETTINGS, "SetModel", "TriageAgent", "anthropic", ..#SECOND, 0, .old)
	Set ..Touched = ..Touched _ $ListBuild("TriageAgent")
	Set ..Restarts = ..Restarts _ $ListBuild("TriageAgent")
	Do $$$AssertStatusOK(sc, "SetModel changes the model of TriageAgent")
	Do $$$AssertEquals($Select($IsObject(old): old.%ToJSON(), 1: ""), "{""provider"":""anthropic"",""model"":""claude-haiku-5-5""}", "old holds the provider and the model that were replaced, and no key")
	Set details = ..Details("TriageAgent")
	Do $$$AssertEquals(details."model_provider"_"|"_details."api_key"_"|"_details.%IsDefined("model"), "anthropic|@{env:ANTHROPIC_API_KEY}|0", "the entry holds the provider and the placeholder of its variable, and no model")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("TriageAgent", ..#PRODUCTION), ..#SECOND, "the Model row is the new model, as the item resolves it")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("Model", ..#PRODUCTION, "TriageAgent", .readSc, "Adapter"), ..#SECOND, "and as it reads back")
	Do ..AssertOnlyRestarted(jobs, "TriageAgent")
	Do $$$AssertStatusOK($ClassMethod(fixture, "PointKeys", "TriageAgent"), "the entry's key is pointed at the CI mock key variable again, so that the runner can answer")

	Set request = ..Ask("decide", "Triage this item.", .ref)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set sc = $ClassMethod(fixture, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "Decide answers")
	Do $$$AssertTrue($IsObject(response) && 'response.Fallback, "the answer is no fallback")
	Set row = $ClassMethod(fixture, "DecisionOf", request.ItemId, "decide")
	Do $$$AssertTrue($IsObject(row), "a row is recorded")
	If $IsObject(row) Do $$$AssertEquals(row.Model_"|"_row.Fallback, ..#SECOND_"|0", "and Decision.Model is the new model")
	Do $$$AssertEquals(..LoggedModels(mark, request.ItemId), ..#SECOND, "the mock saw one request, on the new model")
}

/// A second model: the retry item's model and the RetryItem row; a refused first attempt is answered by the second model; the clear.
Method TestSecondModel()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Do $ClassMethod(..#SCAN, "SetEnv", "ANTHROPIC_API_KEY", ..#FAKE)
	Do ..AtDefault("TriageAgent")
	Do ..AtDefault("TriageAgentRetry")
	Do ..Remember("TriageAgent", "RetryItem")
	Set old = ""
	Set sc = $ClassMethod(..#SETTINGS, "SetModel", "TriageAgent", "anthropic", ..#SECOND, 1, .old)
	Set ..Touched = ..Touched _ $ListBuild("TriageAgentRetry")
	Set ..Restarts = ..Restarts _ $ListBuild("TriageAgentRetry")
	Do $$$AssertStatusOK(sc, "SetModel names a second model for TriageAgent")
	Do $$$AssertEquals($Select($IsObject(old): old.%ToJSON(), 1: ""), "{""provider"":""anthropic"",""model"":""claude-haiku-5-5"",""retryItem"":""""}", "old holds the retry item's provider and model and the RetryItem that were replaced")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("TriageAgentRetry", ..#PRODUCTION), ..#SECOND, "the Model of TriageAgentRetry is the second model")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("TriageAgent", ..#PRODUCTION), "claude-haiku-5-5", "and TriageAgent keeps its own")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("RetryItem", ..#PRODUCTION, "TriageAgent"), "TriageAgentRetry", "RetryItem of TriageAgent is TriageAgentRetry")
	Set details = ..Details("TriageAgentRetry")
	Do $$$AssertEquals(details."model_provider"_"|"_details."api_key"_"|"_details.%IsDefined("model"), "anthropic|@{env:ANTHROPIC_API_KEY}|0", "the retry entry holds the provider and the placeholder, and no model")
	Do $$$AssertStatusOK($ClassMethod(fixture, "PointKeys", "TriageAgentRetry"), "the retry entry's key is pointed at the CI mock key variable again")

	Do ..Arm("retry-refusal", 1)
	Set request = ..Ask("decide", "[[mock:retry-refusal]] Triage this item.", .ref)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set sc = $ClassMethod(fixture, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "Decide answers")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason_"|"_response.Outcome_"|"_response.Reasons, 1: "none"), "0||digest|"_..#SECONDREASON, "the answer is the second model's decision, no fallback")
	Set row = $ClassMethod(fixture, "DecisionOf", request.ItemId, "decide")
	If $IsObject(row) Do $$$AssertEquals(row.Model_"|"_row.Fallback, ..#SECOND_"|0", "Decision.Model is the second model")
	Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", headers, "TriageAgent")_"|"_$ClassMethod(fixture, "CountTo", headers, "TriageAgentRetry"), "1|1", "one request went to each runner")
	Do $$$AssertEquals(..LoggedModels(mark, request.ItemId), "claude-haiku-5-5,"_..#SECOND, "the mock saw the first attempt on the first model and the retry on the second")

	// the clear
	Set cleared = ""
	Set sc = $ClassMethod(..#SETTINGS, "SetModel", "TriageAgent", "", "", 1, .cleared)
	Do $$$AssertStatusOK(sc, "an empty provider and model clear the second model")
	Do $$$AssertEquals($Select($IsObject(cleared): cleared.retryItem, 1: ""), "TriageAgentRetry", "old names the retry item that was set")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("RetryItem", ..#PRODUCTION, "TriageAgent"), "", "RetryItem is empty")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("TriageAgentRetry", ..#PRODUCTION), ..#SECOND, "and the retry item is left as it is")
	Do ..Arm("retry-refusal", 1)
	Set request = ..Ask("decide", "[[mock:retry-refusal]] Triage this item.", .ref)
	Set sc = $ClassMethod(fixture, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "Decide answers again")
	Set row = $ClassMethod(fixture, "DecisionOf", request.ItemId, "decide")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", response, row, "decide", "refusal"), "", "the refusal is release 1's fallback")
	Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", headers, "TriageAgentRetry"), 0, "and no retry was sent")
}

/// Every agent that has a model to change, not only TriageAgent: a first model, a second model and the clear on DiagnosisAgent and ChatAgent each write that agent's
/// own entry, Model row and RetryItem row, restart only the item that changed, and leave the models of the other agents as they were.
Method TestSetModelEveryAgent()
{
	If '..Prepare() Quit
	Do $ClassMethod(..#SCAN, "SetEnv", "ANTHROPIC_API_KEY", ..#FAKE)
	Set agents = $ListBuild("DiagnosisAgent", "ChatAgent")
	Set position = 0
	While $ListNext(agents, position, agent) {
		Set retry = agent_"Retry"
		Do ..AtDefault(agent)
		Do ..AtDefault(retry)
		Do ..Remember(agent, "RetryItem")
		Set ..Touched = ..Touched _ $ListBuild(agent, retry)
		Set ..Restarts = ..Restarts _ $ListBuild(agent, retry)
		Set label = agent_": "
		Set otherModels = ..ModelsExcept(agent)

		// a first model
		Set jobs = ..Jobs()
		Set old = ""
		Set sc = $ClassMethod(..#SETTINGS, "SetModel", agent, "anthropic", ..#SECOND, 0, .old)
		Do $$$AssertStatusOK(sc, label_"SetModel changes the model")
		Do $$$AssertEquals($Select($IsObject(old): old.%ToJSON(), 1: ""), "{""provider"":""anthropic"",""model"":""claude-haiku-5-5""}", label_"old holds the provider and the model that were replaced")
		Set details = ..Details(agent)
		Do $$$AssertEquals(details."model_provider"_"|"_details."api_key"_"|"_details.%IsDefined("model"), "anthropic|@{env:ANTHROPIC_API_KEY}|0", label_"its entry holds the provider and the placeholder, and no model")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(agent, ..#PRODUCTION), ..#SECOND, label_"its Model row is the new model")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(retry, ..#PRODUCTION), "claude-haiku-5-5", label_"and its retry item keeps its own")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("RetryItem", ..#PRODUCTION, agent), "", label_"and no RetryItem is set")
		Do ..AssertOnlyRestarted(jobs, agent)
		Do $$$AssertEquals(..ModelsExcept(agent), otherModels, label_"the models of the other agents are as they were")

		// a second model
		Set jobs = ..Jobs()
		Set old = ""
		Set sc = $ClassMethod(..#SETTINGS, "SetModel", agent, "anthropic", ..#SECOND, 1, .old)
		Do $$$AssertStatusOK(sc, label_"SetModel names a second model")
		Do $$$AssertEquals($Select($IsObject(old): old.%ToJSON(), 1: ""), "{""provider"":""anthropic"",""model"":""claude-haiku-5-5"",""retryItem"":""""}", label_"old holds the retry item's provider and model and the RetryItem that were replaced")
		Set details = ..Details(retry)
		Do $$$AssertEquals(details."model_provider"_"|"_details."api_key"_"|"_details.%IsDefined("model"), "anthropic|@{env:ANTHROPIC_API_KEY}|0", label_"the retry entry holds the provider and the placeholder, and no model")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(retry, ..#PRODUCTION), ..#SECOND, label_"the Model of the retry item is the second model")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(agent, ..#PRODUCTION), ..#SECOND, label_"and the first model stays")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("RetryItem", ..#PRODUCTION, agent), retry, label_"RetryItem is the retry item")
		Do ..AssertOnlyRestarted(jobs, retry)
		Do $$$AssertEquals(..ModelsExcept(agent), otherModels, label_"the models of the other agents are still as they were")

		// the clear
		Set jobs = ..Jobs()
		Set old = ""
		Set sc = $ClassMethod(..#SETTINGS, "SetModel", agent, "", "", 1, .old)
		Do $$$AssertStatusOK(sc, label_"an empty provider and model clear the second model")
		Do $$$AssertEquals($Select($IsObject(old): old.retryItem, 1: ""), retry, label_"old names the retry item that was set")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("RetryItem", ..#PRODUCTION, agent), "", label_"RetryItem is empty")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(retry, ..#PRODUCTION), ..#SECOND, label_"and the retry item is left as it is")
		Do $$$AssertEquals(..Jobs(), jobs, label_"and no item was restarted")
	}
}

/// A write that fails after the entry was merged returns the error, with the entry, the rows and the item as they were. A more specific System Default Settings row
/// (the class of the adapter for Model, the class of the runner for RetryItem) wins over the row that SetModel writes, so the read-back finds another value.
Method TestSetModelFailureRestores()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Do $ClassMethod(..#SCAN, "SetEnv", "ANTHROPIC_API_KEY", ..#FAKE)
	Do ..Remember("TriageAgent", "Model")
	Do ..Remember("TriageAgentRetry", "Model")
	Do ..Remember("TriageAgent", "RetryItem")
	Do ..InsertSpecific("TriageAgent", "OcuTalon.Bridge.Adapter.Agent", "Model", "zz-specific-model")
	Set ..Touched = ..Touched _ $ListBuild("TriageAgent", "TriageAgentRetry")
	Set ..Restarts = ..Restarts _ $ListBuild("TriageAgent", "TriageAgentRetry")
	Set before = ..State()
	Set jobs = ..Jobs()
	Set old = ""
	Set sc = $ClassMethod(..#SETTINGS, "SetModel", "TriageAgent", "anthropic", ..#SECOND, 0, .old)
	Do $$$AssertStatusNotOK(sc, "SetModel fails when the Model it wrote is not the Model the item reads")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "Model", "and the reason names the setting: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(..State(), before, "the entry and the Model and RetryItem rows are as they were")
	Do $$$AssertEquals(..Jobs(), jobs, "and no item was restarted: the change failed before its restart, so there is nothing to restart again")
	Do $$$AssertEquals($ClassMethod(fixture, "NotRunningNow"), "", "and every item runs")

	Do ..InsertSpecific("TriageAgent", "OcuTalon.Bridge.Operation.AgentRunner", "RetryItem", "zz-specific-retry")
	Set before = ..State()
	Set sc = $ClassMethod(..#SETTINGS, "SetModel", "TriageAgent", "anthropic", ..#SECOND, 1, .old)
	Do $$$AssertStatusNotOK(sc, "a second model fails when RetryItem is not the item that it wrote")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "RetryItem", "and the reason names the setting: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(..State(), before, "the retry entry, the Model row of the retry item and the RetryItem row are as they were")
	Do $$$AssertEquals($ClassMethod(fixture, "NotRunningNow"), "", "and every item runs again")

	Set sc = $ClassMethod(..#SETTINGS, "SetModel", "TriageAgent", "", "", 1, .old)
	Do $$$AssertStatusNotOK(sc, "a clear fails when RetryItem is not the empty value that it wrote")
	Do $$$AssertEquals(..State(), before, "and the RetryItem row is put back as it was")
}

/// Refused changes change nothing: not an entry, not a row, not a job.
Method TestRefusedChangeKeepsEverything()
{
	If '..Prepare() Quit
	Do $ClassMethod(..#SCAN, "SetEnv", "OPENAI_API_KEY", ..#FAKE)
	Do $ClassMethod(..#SCAN, "SetEnv", "ANTHROPIC_API_KEY", ..#FAKE)
	Set before = ..State()
	Set jobs = ..Jobs()
	Set cases = $ListBuild(
		$ListBuild("TriageAgent", "openai", "gpt-5.4", 0),
		$ListBuild("TriageAgent", "nope", "claude-haiku-5-5", 0),
		$ListBuild("TriageAgent", "anthropic", "gpt-5.4", 0),
		$ListBuild("TriageAgentRetry", "anthropic", "claude-haiku-5-5", 0),
		$ListBuild("TriageAgent", "anthropic", "@{env:PATH}", 0),
		$ListBuild("ChatAgent", "@{env:PATH}", "claude-haiku-5-5", 1),
		$ListBuild("DiagnosisAgent", "anthropic", "", 1))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set old = ""
		Set sc = $ClassMethod(..#SETTINGS, "SetModel", $List(case, 1), $List(case, 2), $List(case, 3), $List(case, 4), .old)
		Do $$$AssertStatusNotOK(sc, "SetModel("_$ListToString(case, ", ")_") is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) '[ "@{", "with a reason that holds no @{: "_$SYSTEM.Status.GetErrorText(sc))
	}
	Do $$$AssertEquals(..State(), before, "the entries and the Model and RetryItem rows are as they were")
	Do $$$AssertEquals(..Jobs(), jobs, "and no item was restarted")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("RetryItem", ..#PRODUCTION, "TriageAgent"), "", "and TriageAgent has no RetryItem")
}

/// An entry on OpenAI with no key, and the agent's default model: Absent is 0 for both items once Anthropic's key is set in this process.
Method TestResolvedLive()
{
	If '..Prepare() Quit
	Set keys = "OcuTalon.Bridge.Keys"
	Set providers = "OcuTalon.Bridge.Providers"
	Do ..AtDefault("TriageAgent")
	Do ..AtDefault("TriageAgentRetry")
	Do ..UseOpenAI("TriageAgent")
	Do ..UseOpenAI("TriageAgentRetry")
	For item = "TriageAgent", "TriageAgentRetry" {
		Do $$$AssertEquals($ClassMethod(keys, "Absent", item), 1, item_": with no key of a supported provider, Absent is 1")
	}
	Do $ClassMethod(..#SCAN, "SetEnv", "ANTHROPIC_API_KEY", ..#FAKE)
	For item = "TriageAgent", "TriageAgentRetry" {
		Do $$$AssertEquals($ClassMethod(keys, "Absent", item), 0, item_": with Anthropic's key set, Absent is 0: the runner resolves to Anthropic")
		Set provider = $ClassMethod(providers, "Resolve", item, "", "@{config:"_$Piece(..EntryOf(item), "AI.LLM.", 2)_"}", .config, .model)
		Do $$$AssertEquals(provider_"|"_model, "anthropic|claude-haiku-5-5", item_": Resolve names Anthropic and its default model")
		Do $$$AssertEquals($Select($IsObject(config): config."model_provider"_"|"_config."api_key", 1: ""), "anthropic|@{env:ANTHROPIC_API_KEY}", item_": with the placeholder of Anthropic's own variable")
		Do $$$AssertEquals($ClassMethod(keys, "Present", $Select($IsObject(config): config.%ToJSON(), 1: "")), 1, item_": and a key that is present")
		Set details = ..Details(item)
		Do $$$AssertEquals(details."model_provider"_"|"_details."api_key", "openai|@{env:OPENAI_API_KEY}", item_": nothing was written: the entry is still on OpenAI")
	}
	Do $ClassMethod(..#SCAN, "UnsetEnv", "ANTHROPIC_API_KEY")
	Do $$$AssertEquals($ClassMethod(keys, "Absent", "TriageAgent"), 1, "with the variable unset again Absent is 1")
}

/// The same entries with an admin's model never resolve: Absent is 1 and a decide falls back with no_key, with nothing sent.
Method TestAdminModelNeverResolves()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Do ..UseOpenAI("TriageAgent")
	Do ..Remember("TriageAgent", "Model")
	Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", "TriageAgent", "Model", ..#SECOND), "TriageAgent is given an admin's model")
	Do $ClassMethod(..#SCAN, "SetEnv", "ANTHROPIC_API_KEY", ..#FAKE)
	Do $$$AssertEquals($ClassMethod("OcuTalon.Bridge.Keys", "Absent", "TriageAgent"), 1, "Absent is 1: the model that an admin chose is never resolved away")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Bridge.Providers", "Resolve", "TriageAgent", ""), "", "and Resolve names none")
	Set request = ..Ask("decide", "Triage this item.", .ref)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set sc = $ClassMethod(fixture, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "Decide answers")
	Set row = $ClassMethod(fixture, "DecisionOf", request.ItemId, "decide")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", response, row, "decide", "no_key"), "", "with a no_key fallback")
	Do $$$AssertEquals(..LoggedModels(mark, request.ItemId), "", "and nothing reached the mock")
}

/// With every runner's key at an unset variable (Anthropic's own key variable is set in this process, so that only the entry's own provider could be resolved to,
/// which it never is), every item runs, the keys are absent and a decide falls back with no_key.
Method TestNoSupportedKey()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set ..Touched = ..Touched _ $ListFromString(..Runners())
	Set items = $ListFromString(..Runners())
	Set position = 0
	While $ListNext(items, position, item) {
		Set details = ..Details(item)
		Do details.%Set("api_key", "@{env:OCUTALON_ZZ17_UNSET_KEY}")
		Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).Modify(..EntryOf(item), details), item_"'s entry points at a variable that nothing sets")
	}
	Set position = 0
	While $ListNext(items, position, item) {
		Do $$$AssertStatusOK($ClassMethod(fixture, "Restart", ..#PRODUCTION_"||"_item), item_" is started again")
	}
	Do $ClassMethod(..#SCAN, "SetEnv", "ANTHROPIC_API_KEY", ..#FAKE)
	Do $$$AssertEquals($ClassMethod(fixture, "NotRunningNow"), "", "every item of the production runs")
	Do $$$AssertTrue($ClassMethod(fixture, "WaitRecords"), "and every runner recorded its key state")
	Set position = 0
	While $ListNext(items, position, item) {
		Do $$$AssertEquals($ClassMethod("OcuTalon.Bridge.Keys", "Absent", item)_"|"_$ClassMethod("OcuTalon.Bridge.Keys", "Status", item), "1|0", item_": Absent is 1 and Status is 0")
	}
	Set request = ..Ask("decide", "Triage this item.", .ref)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set sc = $ClassMethod(fixture, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "Decide answers")
	Set row = $ClassMethod(fixture, "DecisionOf", request.ItemId, "decide")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", response, row, "decide", "no_key"), "", "with a no_key fallback")
	Do $$$AssertEquals(..LoggedModels(mark, request.ItemId), "", "and no request reached the mock")
	Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", headers, "TriageAgent"), 0, "and none went to the runner")
}

/// A reply with text and the stop reason pause_turn: the runner's reply carries the finish reason AI Hub reports, and Decide falls back with unusable.
Method TestUnclassifiedStopLive()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	// the runner alone: the finish reason that AI Hub reports for the stop reason pause_turn
	Set sc = $ClassMethod(fixture, "Ask", "TriageAgent", "decide", "untrusted", "[[mock:unclassified-stop]] Triage this item.", .reply, .requests, .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Do $$$AssertStatusOK(sc, "the runner answers")
	Do $$$AssertTrue($IsObject(reply), "with a Reply")
	If $IsObject(reply) Do $$$AssertEquals(reply.FinishReason_"|"_(reply.Text '= ""), "pause_turn|1", "its finish reason is pause_turn, with a text")

	// through Decide
	Set request = ..Ask("decide", "[[mock:unclassified-stop]] Triage this item.", .ref)
	Set sc = $ClassMethod(fixture, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "Decide answers")
	Set row = $ClassMethod(fixture, "DecisionOf", request.ItemId, "decide")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", response, row, "decide", "unusable"), "", "with an unusable fallback and no answer text")
	Do $$$AssertTrue($IsObject(response) && (response.Reasons = ""), "the text of the model is not an answer")
}

/// The key's value is stored nowhere and returned nowhere after a model change and a linked turn.
Method TestNoKeyValueAnywhere()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set key = ..#FAKE_"-"_##class(OcuTalon.Bridge.Ids).NewRef()
	Do $ClassMethod(..#SCAN, "SetEnv", "ANTHROPIC_API_KEY", key)
	Do $$$AssertTrue($SYSTEM.Util.GetEnviron("ANTHROPIC_API_KEY") '= "", "the key variable is not empty, so the scan means something")
	If $SYSTEM.Util.GetEnviron("ANTHROPIC_API_KEY") = "" Quit
	Do ..Remember("ChatAgent", "Model")
	Set old = ""
	Set sc = $ClassMethod(..#SETTINGS, "SetModel", "ChatAgent", "anthropic", ..#SECOND, 0, .old)
	Set ..Touched = ..Touched _ $ListBuild("ChatAgent")
	Set ..Restarts = ..Restarts _ $ListBuild("ChatAgent")
	Do $$$AssertStatusOK(sc, "SetModel changes the model of ChatAgent")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) '[ key, "the status text holds no key")
	Do $$$AssertTrue($IsObject(old) && (old.%ToJSON() '[ key), "old holds no key")
	Do $$$AssertStatusOK($ClassMethod(fixture, "PointKeys", "ChatAgent"), "the entry's key is pointed at the CI mock key variable again, so that the runner can answer")
	Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", "Hello.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set sc = $ClassMethod(fixture, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "a linked turn of ChatAgent is answered")
	Do $$$AssertTrue($IsObject(response) && 'response.Fallback, "with no fallback")
	Do $$$AssertTrue($IsObject(response) && (response.XMLExportToString(.xml) = 1) && (xml '[ key), "and the answer holds no key")
	Do $$$AssertEquals($ListToString($ClassMethod(..#SCAN, "Find", key), "; "), "", "no entry, saved session, setting, event-log row or agent step holds the key")
	Set hits = ##class(OcuTalon.Test.Eval.KeyProof).GlobalHits(key, "", .places, .stats)
	Do $$$AssertEquals(hits, 0, "no node of any database holds the key: "_$Select($IsObject($Get(places)): places.%ToJSON(), 1: ""))
}

/// --- helpers ---
/// The six runner items, comma-separated.
ClassMethod Runners() As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).#RUNNERS_","_##class(OcuTalon.Test.Agent.RunnerFixture).#RETRYRUNNERS
}

/// 1 when the production runs with every item in the CI override's environment and the entries of the six runners are pointed at the mock key variable.
Method Prepare() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	Set reason = $ClassMethod(..#FIXTURE, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	If '..Pointed {
		Set ..Pointed = 1
		Set sc = $ClassMethod(..#FIXTURE, "PointKeys", ..Runners())
		Do $$$AssertStatusOK(sc, "the entries of the six runners are pointed at the CI mock key variable")
		If $$$ISERR(sc) Quit 0
	}
	Quit 1
}

/// Remembers the System Default Settings row of the setting of the item, once, for OnAfterOneTest.
Method Remember(item As %String, setting As %String) [ Private ]
{
	Set saved = ..SavedRows
	Do $ClassMethod(..#FIXTURE, "RememberDefault", .saved, item, setting)
	Set ..SavedRows = saved
}

/// Remembers the Model row of the item and sets it to the MODEL of the item's agent class, its default, so that a test that reads the model it replaces, or
/// that needs the default for resolution, does not depend on the row as it found it.
Method AtDefault(item As %String) [ Private ]
{
	Do ..Remember(item, "Model")
	Set agentClass = ##class(Ens.Director).GetAdapterSettingValue(..#PRODUCTION_"||"_item, "AgentClass", .sc)
	Set model = $Select($$$ISOK(sc) && (agentClass '= ""): $Parameter(agentClass, "MODEL"), 1: "")
	Do $$$AssertTrue(model '= "", item_" has an agent class with a MODEL")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "PutDefault", item, "Model", model), item_" is on its agent's own model, the default")
}

/// Inserts a System Default Settings row of the setting for the item on the host class (more specific than the row of any class), and remembers its id to be deleted.
Method InsertSpecific(item As %String, class As %String, setting As %String, value As %String) [ Private ]
{
	Set id = ..#PRODUCTION_"||"_item_"||"_class_"||"_setting
	Set result = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO Ens_Config.DefaultSettings (ProductionName, ItemName, HostClassName, SettingName, SettingValue, Description) VALUES (?, ?, ?, ?, ?, ?)", ..#PRODUCTION, item, class, setting, value, "Written by a test; the test deletes it.")
	Do $$$AssertEquals(result.%SQLCODE, 0, "the row "_id_" is inserted")
	Set ..Specific = ..Specific _ $ListBuild(id)
}

/// Puts the entry of the runner item on OpenAI with its placeholder (an unset variable), through Merge's model shape, and remembers to put it back.
Method UseOpenAI(item As %String) [ Private ]
{
	Set ..Touched = ..Touched _ $ListBuild(item)
	Set ..Restarts = ..Restarts _ $ListBuild(item)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.ConfigStore).Merge(..EntryOf(item), {"model_provider": "openai", "api_key": "@{env:OPENAI_API_KEY}"}), item_"'s entry is on OpenAI, with its key variable unset")
}

/// An untrusted request of the kind with the text, whose ItemId is cleaned up after the test.
Method Ask(kind As %String, text As %String, Output ref As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", kind, "untrusted", text, .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Quit request
}

/// Arms the countdown of the mock for the marker with the number of requests that get its first reply, and remembers the marker for OnAfterOneTest.
Method Arm(marker As %String, remaining As %Integer) [ Private ]
{
	Set ..Armed = ..Armed _ $ListBuild(marker)
	Do $$$AssertStatusOK($ClassMethod(..#MOCK, "Arm", marker, remaining), "the countdown of "_marker_" is armed with "_remaining)
}

/// The Config Store entry of the runner item, fully qualified (its ProviderConfig names it).
ClassMethod EntryOf(item As %String) As %String [ Private ]
{
	Set config = ##class(Ens.Director).GetAdapterSettingValue(..#PRODUCTION_"||"_item, "ProviderConfig", .sc)
	Quit ##class(OcuTalon.Bridge.ConfigStore).FullName(##class(OcuTalon.Bridge.ConfigStore).EntryOf(config))
}

/// The details of the runner item's entry, as stored.
ClassMethod Details(item As %String) As %DynamicObject [ Private ]
{
	Do ##class(OcuTalon.Bridge.ConfigStore).Details(..EntryOf(item), .details)
	Quit details
}

/// The Model of every runner item except the agent and its retry item, as one text, to compare before and after.
ClassMethod ModelsExcept(agent As %String) As %String [ Private ]
{
	Set text = ""
	Set items = $ListFromString(..Runners())
	Set position = 0
	While $ListNext(items, position, item) {
		If (item = agent) || (item = (agent_"Retry")) Continue
		Set text = text _ $Select(text = "": "", 1: ";") _ item _ "=" _ ##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(item, ..#PRODUCTION)
	}
	Quit text
}

/// The jobs of Decide and the six runner items, as one text, to compare before and after.
ClassMethod Jobs() As %String [ Private ]
{
	Set text = ""
	Set items = $ListFromString("Decide,"_..Runners())
	Set position = 0
	While $ListNext(items, position, item) {
		Set text = text _ $Select(text = "": "", 1: ";") _ item _ "=" _ $ListToString($ClassMethod(..#FIXTURE, "Jobs", item), ",")
	}
	Quit text
}

/// Asserts that the item was restarted (it has a job that it did not have) and that every other item has the jobs it had.
Method AssertOnlyRestarted(before As %String, item As %String) [ Private ]
{
	Set after = ..Jobs()
	For i = 1:1:$Length(before, ";") {
		Set was = $Piece(before, ";", i)
		Set now = $Piece(after, ";", i)
		Set name = $Piece(was, "=", 1)
		If name = item {
			Do $$$AssertTrue(was '= now, name_" was restarted: "_was_" -> "_now)
		} Else {
			Do $$$AssertEquals(now, was, name_" was not restarted")
		}
	}
}

/// The models of the requests that the mock logged since the mark and that carry the reference, comma-separated in order.
ClassMethod LoggedModels(mark As %Integer, ref As %String) As %String [ Private ]
{
	Do $ClassMethod(..#MOCK, "LogSince", mark, .entries)
	Set logged = $ClassMethod(..#FIXTURE, "FindRequests", entries, ref)
	Set models = ""
	Set iterator = logged.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set models = models _ $Select(models = "": "", 1: ",") _ entry.model
	}
	Quit models
}

/// The rows that a model change could write, as one text: the entries of the six runners and the Model and RetryItem rows.
ClassMethod State() As %String [ Private ]
{
	Set state = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SettingValue FROM Ens_Config.DefaultSettings WHERE SettingName IN ('Model', 'RetryItem') ORDER BY ID")
	While result.%Next() {
		Set state = state _ $Char(10) _ result.%GetData(1) _ "=" _ result.%GetData(2)
	}
	Set items = $ListFromString(..Runners())
	Set position = 0
	While $ListNext(items, position, item) {
		Set details = ..Details(item)
		Set state = state _ $Char(10) _ item _ " " _ details.%ToJSON()
	}
	Quit state
}

}
