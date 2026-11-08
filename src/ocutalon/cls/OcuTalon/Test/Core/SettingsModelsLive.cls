/// The models section and the model test of OcuTalon.Core.SettingsOps against the real bridge and the running production (Story 18.3; AD-1, AD-7, AD-8, AD-17, AD-19,
/// AD-20). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they need OcuTalon.Production running with its six runner items and the CI override's environment, and
/// the CI mock. The jobs of a throwaway have no model key, and a key variable that a test sets (a fake text, never a key) is set in the test's process only:
/// CheckModel reads it there, and the runner jobs never see it. So the tests that go through the real Bridge.Settings call it in the test's process (a shadow
/// instance of Test.Core.SettingsOpsProbe whose model and price seams pass through), and send a request through a runner only after the entry's key is pointed at the
/// CI mock key variable again (Test.Agent.RunnerFixture PointKeys), as Test.Bridge.ModelChange does. OnAfterOneTest puts back, in ModelChange's order: the Config Store
/// entries it touched (through Merge's model shape), the Provider step, the System Default Settings rows it wrote as found, the Price rows, every key variable of the
/// process, and the items that were restarted.
///   - TestSavedModelsApplyToTheNextDecide (AC 3): SettingsOps saves TriageAgent's model, a second model and a price on the real Bridge.Settings; Values().agents and the
///     page's prices show the new values; after PointKeys the next decide's Decision row has the new model, and the mock saw it; one Settings audit entry for each change is
///     read back from the IRIS audit log, price first;
///   - TestModelTestAnswers (AC 2): a TestModel for TriageAgent goes through Commands.Submit to the real SettingsOps job and Decide, after PointKeys, and is answered true
///     with the seconds above 0 and below the wait, no reason and no member besides those three; its Decision row, above the highest ID before the test, is the model's.
Class OcuTalon.Test.Core.SettingsModelsLive Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzsetmodl";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

Parameter SCAN = "OcuTalon.Test.Agent.KeyScan";

Parameter PROBE = "OcuTalon.Test.Core.SettingsOpsProbe";

Parameter AUDITLOG = "OcuTalon.Test.Bridge.AuditLog";

/// The key variables of the real provider table, which the tests set and clear in the test's process.
Parameter VARIABLES = "ANTHROPIC_API_KEY,OPENAI_API_KEY,GEMINI_API_KEY,AWS_BEARER_TOKEN_BEDROCK";

/// A text that is no key.
Parameter FAKE = "ocutalon-zz-not-a-key";

/// The model that the tests change TriageAgent to.
Parameter SECOND = "claude-sonnet-5-5";

/// The model that the tests give TriageAgent as its second model: not the first model, so that a first and a second model swapped show.
Parameter RETRY = "claude-haiku-5-5";

/// The price rows that the tests may change, as the model names.
Parameter MODELS = "claude-haiku-5-5,claude-sonnet-5-5";

/// The properties of a Price row, in the order of its list.
Parameter PROPERTIES = "InputPerMTok,OutputPerMTok,CacheReadPerMTok,CacheWritePerMTok,LongThresholdTokens,LongInputPerMTok,LongOutputPerMTok";

/// Seconds to wait for an audit entry.
Parameter AUDITSECONDS = 180;

/// 1 while the entries of the six runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

/// The System Default Settings rows before the test touched them (RunnerFixture RememberDefault), to be put back.
Property SavedRows As %List;

/// The items to start again after the rows are put back.
Property Restarts As %List;

/// The runner items whose Config Store entry the test changed.
Property Touched As %List;

/// The key variables as the test found them, each $ListBuild(variable, was set, value).
Property Env As %List;

/// The mark of the saved AI sessions when the test began (RunnerFixture SessionMark).
Property SessionMark As %Integer;

/// The Price rows before the test, each $ListBuild(model, existed, the seven values).
Property Prices As %List;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set ..Prices = ""
	Set models = $ListFromString(..#MODELS)
	Set position = 0
	While $ListNext(models, position, model) {
		Set one = $ListBuild(model, ##class(OcuTalon.Bridge.Data.Price).ModelIndexExists(model))
		If $List(one, 2) {
			Set row = ##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen(model)
			Set properties = $ListFromString(..#PROPERTIES)
			Set at = 0
			While $ListNext(properties, at, property) {
				Set one = one_$ListBuild($Property(row, property))
			}
		}
		Set ..Prices = ..Prices_$ListBuild(one)
	}
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
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe
	Set fixture = ..#FIXTURE
	If ..Missing = "" {
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
		Do ..DropTestRows()
		Set position = 0
		While $ListNext(..ItemIds, position, itemId) {
			Do $ClassMethod(fixture, "DeleteSteps", itemId)
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
		}
		Set ..ItemIds = ""
		Do $ClassMethod(fixture, "RestoreDefaults", ..SavedRows)
		Set ..SavedRows = ""
		Do ..RestorePrices()
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

/// SettingsOps saves TriageAgent's first model, its second model and the price of the new model on the real Bridge.Settings (the probe's seams pass through, the key
/// variable is set in this process as ModelChange does). The values read back through Bridge.Settings and the page's GET body; the next decide, after PointKeys, runs on the
/// new model; and each change has its Settings audit entry in the IRIS audit log, the price first.
Method TestSavedModelsApplyToTheNextDecide()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Do $ClassMethod(..#SCAN, "SetEnv", "ANTHROPIC_API_KEY", ..#FAKE)
	Do ..AtDefault("TriageAgent")
	Do ..AtDefault("TriageAgentRetry")
	Do ..Remember("TriageAgent", "RetryItem")
	Set ..Touched = ..Touched _ $ListBuild("TriageAgent", "TriageAgentRetry")
	Set ..Restarts = ..Restarts _ $ListBuild("TriageAgent", "TriageAgentRetry")
	Set page = ##class(OcuTalon.Core.SettingsOps).Values()
	Do $$$AssertTrue(page.prices.%IsDefined(..#SECOND), "control: the page lists the price of "_..#SECOND)
	If 'page.prices.%IsDefined(..#SECOND) Quit
	Set was = page.prices.%Get(..#SECOND).input
	Set new = was + 1
	Set body = {"agents": (page.bridge.agents), "prices": (page.prices)}
	Do body.agents.TriageAgent.%Set("model", ..#SECOND)
	Do body.agents.TriageAgent.%Set("secondProvider", "anthropic")
	Do body.agents.TriageAgent.%Set("secondModel", ..#RETRY)
	Do body.prices.%Get(..#SECOND).%Set("input", new, "number")
	Set before = ##class(OcuTalon.Bridge.Settings).Values().agents.TriageAgent
	Do $$$AssertEquals(before.model_"|"_before.secondModel, "claude-haiku-5-5|", "control: TriageAgent starts on Haiku with no second model")

	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "pass") = "models,prices"
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "record"
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set since = $ClassMethod(..#AUDITLOG, "Now")
	Set result = ..Save(body, ref)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "SettingsOps saves the model, the second model and the price: "_result.Data)

	Set values = ##class(OcuTalon.Bridge.Settings).Values().agents.TriageAgent
	Do $$$AssertEquals(values.provider_"|"_values.model_"|"_values.secondProvider_"|"_values.secondModel, "anthropic|"_..#SECOND_"|anthropic|"_..#RETRY, "Bridge.Settings.Values shows the new first and second model")
	Do $$$AssertEquals(##class(OcuTalon.Core.SettingsOps).Values().prices.%Get(..#SECOND).input, new, "the page's prices show the new price")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("TriageAgent", ..#PRODUCTION)_"|"_##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("TriageAgentRetry", ..#PRODUCTION), ..#SECOND_"|"_..#RETRY, "the runner resolves the first model and the retry item the second")
	Do $$$AssertStatusOK($ClassMethod(fixture, "PointKeys", "TriageAgent,TriageAgentRetry"), "the entries' keys are pointed at the CI mock key variable again, so that the runner can answer")

	Set request = ..Ask("decide", "Triage this item.", .itemRef)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set sc = $ClassMethod(fixture, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "Decide answers")
	Do $$$AssertTrue($IsObject(response) && 'response.Fallback, "the answer is no fallback")
	Set row = $ClassMethod(fixture, "DecisionOf", request.ItemId, "decide")
	Do $$$AssertTrue($IsObject(row), "a Decision row is recorded")
	If $IsObject(row) Do $$$AssertEquals(row.Model_"|"_row.Fallback, ..#SECOND_"|0", "and its Model is the new model")
	Do $$$AssertEquals(..LoggedModels(mark, request.ItemId), ..#SECOND, "the mock saw one request, on the new model")
	Set usage = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ? AND CostUSD > 0", $Select($IsObject(row): row.Ref, 1: ""))
	Do usage.%Next()
	Do $$$AssertTrue(usage.%GetData(1) > 0, "and its Usage is priced")

	Set entries = $ClassMethod(..#AUDITLOG, "Wait", since, "OcuTalon", "Settings", "", ref, "", 3, ..#AUDITSECONDS)
	Do $$$AssertEquals(entries.%Size(), 3, "three Settings entries are read back from the IRIS audit log, one for each change")
	If entries.%Size() < 3 Quit
	Set found = ""
	For i = 0:1:2 {
		Set data = entries.%Get(i).data
		Set found = found_$ListBuild(data.setting_"|"_data.from_"|"_data.to)
	}
	Do $$$AssertEquals($ListToString(found, ";"), "price."_..#SECOND_".input|"_was_"|"_new_";TriageAgent.model|anthropic/claude-haiku-5-5|anthropic/"_..#SECOND_";TriageAgent.secondModel||anthropic/"_..#RETRY, "the price first, then the first model, then the second model, each with the value it replaced")
	Set text = entries.%ToJSON()
	Do $$$AssertTrue(($Find(text, ..#FAKE) = 0) && ($Find(text, "@{") = 0), "and no entry holds a key or a placeholder")
}

/// A model test goes through Commands.Submit to the real SettingsOps job, which sends it to Decide: the runner answers through the CI mock.
Method TestModelTestAnswers()
{
	If '..Prepare() Quit
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set floor = ..LastDecision()
	Set command = ##class(OcuTalon.Msg.Command.TestModel).%New()
	Set command.Agent = "TriageAgent"
	Set command.SessionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
	Do $$$AssertStatusOK(sc, "the command is submitted")
	Do $$$AssertTrue($IsObject(result), "and answered")
	If '$IsObject(result) Quit
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|tested", "SettingsOps tested the model")
	Set answer = {}.%FromJSON(result.Data)
	Do $$$AssertEquals(answer.answered_"|"_answer.reason, "1|", "the model answered: "_result.Data)
	Do $$$AssertTrue((answer.seconds > 0) && (answer.seconds < ##class(OcuTalon.Core.SettingsOps).#TESTWAIT), "in "_answer.seconds_" seconds, inside the wait")
	Do $$$AssertEquals(answer.%GetTypeOf("answered")_"|"_answer.%GetTypeOf("seconds")_"|"_answer.%GetTypeOf("reason"), "boolean|number|string", "with the types of the answer")
	Set members = 0
	Set iterator = answer.%GetIterator()
	While iterator.%GetNext(.name) {
		Set members = members + 1
	}
	Do $$$AssertEquals(members, 3, "and no other member")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Drain", "TriageAgent"), "the runner is drained")
	Do $ClassMethod(..#MOCK, "LogSince", mark, .entries)
	Set expected = ##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("TriageAgent", ..#PRODUCTION)
	Set seen = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.model = expected Set seen = seen + 1
	}
	Do $$$AssertTrue(seen '< 1, "a request for the agent's model "_expected_" reached the mock")
	Set decision = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Model, Fallback FROM OcuTalon_Bridge_Data.Decision WHERE ItemId LIKE 'test.%' AND ID > ? ORDER BY ID DESC", floor)
	Do $$$AssertTrue(decision.%Next(), "a Decision row of the test is recorded")
	Do $$$AssertEquals(decision.%GetData(1)_"|"_decision.%GetData(2), expected_"|0", "with the agent's model, and no fallback")
}

/// --- helpers ---
/// The highest ID of the Decision table now, 0 for none: a row above it is a row of the test.
ClassMethod LastDecision() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM OcuTalon_Bridge_Data.Decision")
	Do result.%Next()
	Quit +result.%GetData(1)
}

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

/// Remembers the Model row of the item and sets it to the MODEL of the item's agent class, its default.
Method AtDefault(item As %String) [ Private ]
{
	Do ..Remember(item, "Model")
	Set agentClass = ##class(Ens.Director).GetAdapterSettingValue(..#PRODUCTION_"||"_item, "AgentClass", .sc)
	Set model = $Select($$$ISOK(sc) && (agentClass '= ""): $Parameter(agentClass, "MODEL"), 1: "")
	Do $$$AssertTrue(model '= "", item_" has an agent class with a MODEL")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "PutDefault", item, "Model", model), item_" is on its agent's own model, the default")
}

/// An untrusted request of the kind with the text, whose ItemId is cleaned up after the test.
Method Ask(kind As %String, text As %String, Output ref As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", kind, "untrusted", text, .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Quit request
}

/// The Config Store entry of the runner item, fully qualified (its ProviderConfig names it).
ClassMethod EntryOf(item As %String) As %String [ Private ]
{
	Set config = ##class(Ens.Director).GetAdapterSettingValue(..#PRODUCTION_"||"_item, "ProviderConfig", .sc)
	Quit ##class(OcuTalon.Bridge.ConfigStore).FullName(##class(OcuTalon.Bridge.ConfigStore).EntryOf(config))
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

/// Puts the Price rows back as OnBeforeOneTest found them.
Method RestorePrices() [ Private ]
{
	Set position = 0
	While $ListNext(..Prices, position, one) {
		Set model = $List(one, 1)
		If '$List(one, 2) {
			If ##class(OcuTalon.Bridge.Data.Price).ModelIndexExists(model) Do ##class(OcuTalon.Bridge.Data.Price).ModelIndexDelete(model)
			Continue
		}
		Set row = ##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen(model)
		Set properties = $ListFromString(..#PROPERTIES)
		For i = 1:1:$ListLength(properties) {
			Set $Property(row, $List(properties, i)) = $List(one, i + 2)
		}
		Do row.%Save()
	}
	Set ..Prices = ""
}

/// Deletes the Decision rows of model test requests (ItemId test.%) with their Usage and agent steps.
Method DropTestRows() [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT ItemId FROM OcuTalon_Bridge_Data.Decision WHERE ItemId LIKE 'test.%'")
	While result.%Next() {
		Set itemId = result.%GetData(1)
		Do $ClassMethod(..#FIXTURE, "DeleteSteps", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId LIKE 'test.%'")
}

/// A SaveSettings of the models section with the body for the session Ref, from web_admin for zzadmin, carried out by a shadow instance of the probe in this process.
Method Save(body As %DynamicObject, ref As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = "models"
	Set command.Changes = body.%ToJSON()
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = ref
	Set command.Origin = "web_admin"
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

}
