/// Tests of the provider table, provider resolution and the model-change checks (Story 17.3; AD-7, AD-8, AD-19). In process: they send nothing to a provider and
/// write no setting or entry; the only rows they write are the Price rows that Installer.SeedPrices creates when they are missing (TestTable), as the install does. They need the CI mock only for the shadow runner (TestResolvedShadowRunner), which builds an agent for another provider and
/// must send nothing, so that test fails with the reason where the environment is not the CI override's (RunnerFixture GuardReason). Every test that sets a key
/// variable sets a fake, non-secret text in this process only and puts every variable back as it found it (OnBeforeOneTest and OnAfterOneTest).
///   - TestTable: the table has its four rows in order, with the default model, the selectable models and the key variable of each; only Anthropic is
///     supported; every selectable model has a row in Installer.Prices() and, once Installer.SeedPrices has run, a Price row (the cap key of each family is
///     proved by Test.Bridge.SessionConfig.TestEveryListedModel);
///   - TestChoose: Choose takes the first supported row in order whose key variable is set and that is not the entry's own provider, on its default model;
///     the unsupported and the unset rows are skipped; an admin's model, a present key and an unknown key never resolve; a table that is not an object
///     resolves nothing;
///   - TestResolvedShadowRunner: a shadow runner on a table of its own (ZzProviders), whose entry's Anthropic key is unset, is built on OpenAI with OpenAI's default
///     model: the agent's provider is openai, its model gpt-5.4-mini, the session config has extra_params.max_completion_tokens 8000 and no effort, the key state of
///     the resolved configuration is present, and building the agent and composing its config sent nothing (the mock's log is as it was; no request is made); a
///     runner with an admin's model is not resolved; a runner whose key is set is not resolved; a runner whose ProviderName setting is set is not resolved; the
///     retry item resolves too;
///   - TestResolvedEqualsDirect: a runner that resolves to a provider is built exactly as a runner that chose that provider directly (its model set, its key
///     variable set): the same provider, model, provider configuration and session config, for a resolution to OpenAI and to Anthropic;
///   - TestRecordKeyResolved: the adapter of a runner acting as a job (ZzProviderAdapter ForceJob) records the key state of the resolved configuration when it starts
///     (OnInit): Keys.Status is 0 while no supported provider's key is set and 1 once the resolved provider's is, and the record is forgotten afterwards;
///   - TestSettingsProviders: Settings.Providers gives the four rows in order with provider, defaultModel, models, keyVariable, keySet and supported, keySet
///     follows the environment, and nothing in it holds the value of a key;
///   - TestCheckModelRefusals: CheckModel and SetModel refuse each of an argument that holds @{, an agent outside the three, a provider that is not in the table, not
///     supported or whose key variable is not set, a model the provider does not list, and an empty provider or model for a first model, each with a plain reason that
///     holds no value, and nothing is written (the entries, the Model and RetryItem rows and the Price rows are as they were); the valid calls and an empty second model pass;
///   - TestIntegrationSettingsOps (Rule 1): the body of Lane B's SettingsOps.Values holds the providers that Settings.Providers gives: four rows with Anthropic first, each
///     with keySet and supported.
Class OcuTalon.Test.Bridge.Providers Extends %UnitTest.TestCase
{

Parameter SETTINGS = "OcuTalon.Bridge.Settings";

Parameter TABLE = "OcuTalon.Bridge.Providers";

Parameter ZZTABLE = "OcuTalon.Test.Bridge.ZzProviders";

Parameter SCAN = "OcuTalon.Test.Agent.KeyScan";

/// A text that is no key, which the tests put in a key variable of this process.
Parameter FAKE = "ocutalon-zz-not-a-key";

/// The key variables that the tests touch, each a $ListBuild(variable, was set, value), as OnBeforeOneTest found them.
Property Env As %List;

/// The key variables of the real table and of ZzProviders.
Parameter VARIABLES = "ANTHROPIC_API_KEY,OPENAI_API_KEY,GEMINI_API_KEY,AWS_BEARER_TOKEN_BEDROCK,OCUTALON_ZZ17_ANTHROPIC,OCUTALON_ZZ17_OPENAI,OCUTALON_ZZ17_GEMINI,OCUTALON_ZZ17_BEDROCK";

Method OnBeforeOneTest(testname As %String) As %Status
{
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

/// The table: four rows in order, with their values, one supported provider, and a price and a family for every selectable model.
Method TestTable()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).SeedPrices(), "Installer.SeedPrices creates the Price rows that are missing, as the install does")
	Set rows = $ClassMethod(..#TABLE, "Rows")
	Do $$$AssertEquals(rows.%Size(), 4, "the table has four rows")
	Set expected = $ListBuild(
		"anthropic|claude-haiku-5-5|claude-haiku-5-5,claude-sonnet-5-5|ANTHROPIC_API_KEY|1",
		"openai|gpt-5.4-mini|gpt-5.4-mini,gpt-5.4|OPENAI_API_KEY|0",
		"gemini|gemini-3.1-flash-lite|gemini-3.1-flash-lite,gemini-3.1-pro-preview|GEMINI_API_KEY|0",
		"bedrock|us.anthropic.claude-haiku-5-5|us.anthropic.claude-haiku-5-5,us.anthropic.claude-sonnet-5-5|AWS_BEARER_TOKEN_BEDROCK|0")
	Set prices = ##class(OcuTalon.Bridge.Installer).Prices()
	For i = 1:1:rows.%Size() {
		Set row = rows.%Get(i - 1)
		Set models = ""
		Set iterator = row.models.%GetIterator()
		While iterator.%GetNext(, .model) {
			Set models = models _ $Select(models = "": "", 1: ",") _ model
		}
		Do $$$AssertEquals(row.provider_"|"_row.defaultModel_"|"_models_"|"_row.keyVariable_"|"_(+row.supported), $List(expected, i), "row "_i_" is "_row.provider)
		Do $$$AssertTrue($ListFind($ListFromString(models, ","), row.defaultModel) > 0, row.provider_": the default model is one of the selectable models")
		Set iterator = row.models.%GetIterator()
		While iterator.%GetNext(, .model) {
			Set priced = 0
			Set position = 0
			While $ListNext(prices, position, price) {
				If $List(price, 1) = model Set priced = 1
			}
			Do $$$AssertTrue(priced, model_" has a row in Installer.Prices()")
			Do $$$AssertTrue(##class(OcuTalon.Bridge.Data.Price).ModelIndexExists(model), model_" has a Price row")
		}
	}
	Do $$$AssertEquals(rows.%Get(0).provider_"|"_rows.%Get(0).supported, "anthropic|1", "Anthropic is supported")
	Set supported = 0
	For i = 0:1:3 Set supported = supported + rows.%Get(i).supported
	Do $$$AssertEquals(supported, 1, "and it is the only provider that is")
	Set openai = $ClassMethod(..#TABLE, "Row", "openai")
	Do $$$AssertEquals(openai.defaultModel, "gpt-5.4-mini", "Row finds a provider")
	Do $$$AssertEquals($ClassMethod(..#TABLE, "Row", "nope"), "", "Row gives an empty string for a provider the table lacks")
	Do $$$AssertEquals($ClassMethod(..#TABLE, "Row", ""), "", "and for an empty name")
	Do $$$AssertEquals($ClassMethod(..#TABLE, "KeySet", "openai"), 0, "KeySet is 0 while the variable is unset")
	Do $ClassMethod(..#SCAN, "SetEnv", "OPENAI_API_KEY", ..#FAKE)
	Do $$$AssertEquals($ClassMethod(..#TABLE, "KeySet", "openai")_"|"_$ClassMethod(..#TABLE, "KeySet", "nope"), "1|0", "and 1 once it is set, and 0 for a provider the table lacks")
	Set zzRows = $ClassMethod(..#ZZTABLE, "Rows")
	Do $$$AssertEquals(zzRows.%Get(1).keyVariable, "OCUTALON_ZZ17_OPENAI", "a subclass reads its own table: Rows follows the class it is called on")
	Set zzBedrock = $ClassMethod(..#ZZTABLE, "Row", "bedrock")
	Do $$$AssertEquals(zzBedrock.supported, 1, "also through Row")
}

/// Choose: order, the entry's own provider, the unsupported and the unset rows, and the cases that never resolve.
Method TestChoose()
{
	Set rows = $ClassMethod(..#ZZTABLE, "Rows")
	Set zz = ..#ZZTABLE
	Do $$$AssertEquals(..Chosen(rows, "anthropic", "absent", 1), "|0", "with no key set, nothing resolves")
	Do $ClassMethod(..#SCAN, "SetEnv", "OCUTALON_ZZ17_GEMINI", ..#FAKE)
	Do $$$AssertEquals(..Chosen(rows, "anthropic", "absent", 1), "|0", "a key of an unsupported provider is skipped")
	Do $ClassMethod(..#SCAN, "SetEnv", "OCUTALON_ZZ17_BEDROCK", ..#FAKE)
	Do $$$AssertEquals(..Chosen(rows, "anthropic", "absent", 1), "bedrock|us.anthropic.claude-haiku-5-5|1", "the only supported row with a key is chosen, on its default model")
	Do $ClassMethod(..#SCAN, "SetEnv", "OCUTALON_ZZ17_OPENAI", ..#FAKE)
	Do $$$AssertEquals(..Chosen(rows, "anthropic", "absent", 1), "openai|gpt-5.4-mini|1", "the first row in table order wins")
	Do $ClassMethod(..#SCAN, "SetEnv", "OCUTALON_ZZ17_ANTHROPIC", ..#FAKE)
	Do $$$AssertEquals(..Chosen(rows, "anthropic", "absent", 1), "openai|gpt-5.4-mini|1", "the entry's own provider is skipped even when its variable is set")
	Do $$$AssertEquals(..Chosen(rows, "openai", "absent", 1), "anthropic|claude-haiku-5-5|1", "an entry of another provider resolves to the first row: Anthropic")
	Do $$$AssertEquals(..Chosen(rows, "", "absent", 1), "anthropic|claude-haiku-5-5|1", "an entry with no provider skips none")
	Do $$$AssertEquals(..Chosen(rows, "anthropic", "absent", 0), "|0", "an admin's model (not the default) never resolves")
	Do $$$AssertEquals(..Chosen(rows, "anthropic", "present", 1), "|0", "a present key never resolves")
	Do $$$AssertEquals(..Chosen(rows, "anthropic", "unknown", 1), "|0", "an unknown key state never resolves")
	Do $$$AssertEquals(..Chosen(rows, "anthropic", "", 1), "|0", "and neither does a missing state")
	Do $ClassMethod(..#SCAN, "UnsetEnv", "OCUTALON_ZZ17_OPENAI")
	Do $ClassMethod(..#SCAN, "UnsetEnv", "OCUTALON_ZZ17_ANTHROPIC")
	Do $$$AssertEquals(..Chosen(rows, "anthropic", "absent", 1), "bedrock|us.anthropic.claude-haiku-5-5|1", "with OpenAI's key unset again, the next supported row with a key is chosen")
	Set sc = $ClassMethod(zz, "Choose", "", "anthropic", "absent", 1, .provider, .model)
	Do $$$AssertEquals(sc_"|"_provider_"|"_model, "0||", "a table that is not an object resolves nothing")
	Set sc = $ClassMethod(zz, "Choose", [], "anthropic", "absent", 1, .provider, .model)
	Do $$$AssertEquals(sc_"|"_provider_"|"_model, "0||", "and neither does an empty table")
}

/// A shadow runner on ZzProviders: its entry's Anthropic key is unset and OpenAI's is set, so it is built on OpenAI with OpenAI's default model, and nothing is sent.
Method TestResolvedShadowRunner()
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).GuardReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set scan = ..#SCAN
	Set config = {"model_provider": "anthropic", "api_key": "@{env:OCUTALON_ZZ17_ANTHROPIC}", "base_url": (##class(OcuTalon.Test.Contract.Mock).#BASEURL)}.%ToJSON()
	Do $ClassMethod(scan, "SetEnv", "OCUTALON_ZZ17_OPENAI", ..#FAKE)
	For name = "ZzProvider", "ZzProviderRetry" {
		Set host = ##class(OcuTalon.Test.Bridge.Runner).NewRunner("OcuTalon.Agent.Triage", "low", config, name, "OcuTalon.Test.Bridge.ZzProviderRunner")
		Set adapter = host.Adapter
		Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
		Set sc = adapter.BuildAgent()
		Do $$$AssertStatusOK(sc, name_": the agent is built")
		If $$$ISERR(sc) Continue
		Do $$$AssertEquals(adapter.Agent.Provider.Name_"|"_adapter.Agent.Model, "openai|gpt-5.4-mini", name_": the agent's provider is openai and its model OpenAI's default")
		Set sc = adapter.SessionConfigFor(.session)
		Do $$$AssertStatusOK(sc, name_": the session config is composed")
		If $$$ISOK(sc) {
			Do $$$AssertEquals(session.%Get("extra_params").%Get("max_completion_tokens"), 8000, name_": the config has extra_params.max_completion_tokens 8000")
			Do $$$AssertEquals(session.%IsDefined("max_tokens")_"|"_session.%Get("extra_params").%IsDefined("output_config"), "0|0", name_": and no max_tokens and no effort")
			Do $$$AssertTrue(session.%ToJSON() '[ """temperature""", name_": and no sampling parameter")
		}
		Set state = $ClassMethod("OcuTalon.Bridge.Keys", "State", adapter.ProviderConfig)
		Do $$$AssertEquals(state, "present", name_": the key state of the resolved configuration is present")
		Do $ClassMethod("OcuTalon.Bridge.Keys", "Record", name, adapter.ProviderConfig)
		Do $$$AssertEquals($ClassMethod("OcuTalon.Bridge.Keys", "Status", name), 1, name_": Keys.Status answers for the resolved provider: 1")
		Do $ClassMethod("OcuTalon.Bridge.Keys", "Forget", name)
		Do $$$AssertEquals($ClassMethod("OcuTalon.Bridge.Keys", "Status", name), 0, name_": and the record is forgotten")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), name_": the mock's log is read")
		Do $$$AssertEquals($Select($IsObject($Get(entries)): entries.%Size(), 1: -1), 0, name_": building the agent and composing its config sent nothing: the mock's log is as it was")
		Set resolved = {}.%FromJSON(adapter.ProviderConfig)
		Do $$$AssertEquals(resolved."model_provider"_"|"_resolved."api_key", "openai|@{env:OCUTALON_ZZ17_OPENAI}", name_": the resolved configuration is the entry's details with the provider and the key replaced, as a placeholder")
		Do $$$AssertEquals(resolved.%IsDefined("base_url")_"|"_resolved.%IsDefined("http_config"), "0|0", name_": and without the base URL of the entry's own provider (DW-758); the entry has no timeouts here")
		Do $$$AssertTrue(adapter.ProviderConfig '[ ..#FAKE, name_": and holds no key value")
	}

	// an admin's model is never resolved away
	Set host = ##class(OcuTalon.Test.Bridge.Runner).NewRunner("OcuTalon.Agent.Triage", "low", config, "ZzProvider", "OcuTalon.Test.Bridge.ZzProviderRunner")
	Set host.Adapter.Model = "claude-sonnet-5-5"
	Do $$$AssertStatusNotOK(host.Adapter.BuildAgent(), "with an admin's model the agent is built on the entry's own provider, whose key is unset, and the build fails")
	Do $$$AssertEquals(host.Adapter.ProviderConfig_"|"_host.Adapter.Model, config_"|claude-sonnet-5-5", "and the adapter's settings are as they were")

	// a ProviderName setting is never resolved away
	Set host = ##class(OcuTalon.Test.Bridge.Runner).NewRunner("OcuTalon.Agent.Triage", "low", config, "ZzProvider", "OcuTalon.Test.Bridge.ZzProviderRunner")
	Set host.Adapter.ProviderName = "anthropic"
	Set modelBefore = host.Adapter.Model
	Do host.Adapter.BuildAgent()
	Do $$$AssertEquals(host.Adapter.ProviderConfig_"|"_host.Adapter.Model, config_"|"_modelBefore, "with a ProviderName setting the runner is not resolved: its configuration and model are as they were")

	// a key that is set is not resolved away
	Do $ClassMethod(scan, "SetEnv", "OCUTALON_ZZ17_ANTHROPIC", ..#FAKE)
	Set host = ##class(OcuTalon.Test.Bridge.Runner).NewRunner("OcuTalon.Agent.Triage", "low", config, "ZzProvider", "OcuTalon.Test.Bridge.ZzProviderRunner")
	Do $$$AssertStatusOK(host.Adapter.BuildAgent(), "with the entry's own key set the agent is built")
	Do $$$AssertEquals(host.Adapter.Agent.Provider.Name_"|"_host.Adapter.Agent.Model, "anthropic|claude-haiku-5-5", "on the entry's provider and the agent's own model")
	Do $$$AssertEquals(host.Adapter.ProviderConfig, config, "and the configuration is the entry's own")
}

/// The adapter of a runner that acts as a job records the key state of the provider it resolves to (RecordKey), so that Keys.Status answers for the provider it uses.
Method TestRecordKeyResolved()
{
	Set scan = ..#SCAN
	Set keys = "OcuTalon.Bridge.Keys"
	Set name = "ZzProviderKey"
	Set config = {"model_provider": "anthropic", "api_key": "@{env:OCUTALON_ZZ17_ANTHROPIC}"}.%ToJSON()
	Set host = ##class(OcuTalon.Test.Bridge.Runner).NewRunner("OcuTalon.Agent.Triage", "low", config, name, "OcuTalon.Test.Bridge.ZzProviderRunner")
	Set host.Adapter.ForceJob = 1
	Do $ClassMethod(keys, "Forget", name)
	Do $$$AssertStatusOK(host.Adapter.OnInit(), "the adapter starts")
	Do $$$AssertEquals($ClassMethod(keys, "Status", name), 0, "with no key of a supported provider set, the job records an absent key: Status is 0")
	Do $ClassMethod(scan, "SetEnv", "OCUTALON_ZZ17_OPENAI", ..#FAKE)
	Do $$$AssertStatusOK(host.Adapter.OnInit(), "the adapter starts again")
	Do $$$AssertEquals($ClassMethod(keys, "Status", name), 1, "once OpenAI's key is set the job records the resolved configuration: Status is 1")
	Do $ClassMethod(keys, "Forget", name)
	Do $$$AssertEquals($ClassMethod(keys, "Status", name), 0, "the record is forgotten")
}

/// Settings.Providers: the four rows in order with keySet and supported, following the environment, and no key.
Method TestSettingsProviders()
{
	Set providers = $ClassMethod(..#SETTINGS, "Providers")
	Do $$$AssertTrue($IsObject(providers) && providers.%IsA("%Library.DynamicArray"), "Providers is a dynamic array")
	Do $$$AssertEquals(providers.%Size(), 4, "with four rows")
	Set names = ""
	For i = 0:1:providers.%Size() - 1 {
		Set names = names _ $Select(names = "": "", 1: ",") _ providers.%Get(i).provider
	}
	Do $$$AssertEquals(names, "anthropic,openai,gemini,bedrock", "in table order")
	Set first = providers.%Get(0)
	Do $$$AssertEquals(first.provider_"|"_first.defaultModel_"|"_first.keyVariable, "anthropic|claude-haiku-5-5|ANTHROPIC_API_KEY", "Anthropic's row holds its default model and its key variable")
	Do $$$AssertEquals(first.models.%ToJSON(), "[""claude-haiku-5-5"",""claude-sonnet-5-5""]", "and its selectable models")
	Do $$$AssertEquals(first.%GetTypeOf("keySet")_"|"_first.%GetTypeOf("supported"), "boolean|boolean", "keySet and supported are booleans")
	Set keys = ""
	Set iterator = first.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys _ $Select(keys = "": "", 1: ",") _ key
	}
	Do $$$AssertEquals(keys, "provider,defaultModel,models,keyVariable,keySet,supported", "a row holds these fields and no other")
	Do $$$AssertEquals(..Flags(providers), "0|1;0|0;0|0;0|0", "with no key variable set, no row has keySet, and only Anthropic is supported")
	Do $ClassMethod(..#SCAN, "SetEnv", "OPENAI_API_KEY", ..#FAKE)
	Do $ClassMethod(..#SCAN, "SetEnv", "ANTHROPIC_API_KEY", ..#FAKE)
	Set providers = $ClassMethod(..#SETTINGS, "Providers")
	Do $$$AssertEquals(..Flags(providers), "1|1;1|0;0|0;0|0", "keySet follows the environment, and an unsupported provider can have its key set")
	Do $$$AssertTrue(providers.%ToJSON() '[ ..#FAKE, "and the answer holds no key value")
}

/// Every refused input of CheckModel (and of SetModel, which calls it first) is refused with a plain reason that holds no value and writes nothing.
Method TestCheckModelRefusals()
{
	Set settings = ..#SETTINGS
	Do $ClassMethod(..#SCAN, "SetEnv", "ANTHROPIC_API_KEY", ..#FAKE)
	Do $ClassMethod(..#SCAN, "SetEnv", "OPENAI_API_KEY", ..#FAKE)
	Set before = ..State()
	Set cases = []
	// agent, provider, model, second, a word that the reason holds
	Do cases.%Push({"agent": "TriageAgent", "provider": "anthropic", "model": "@{env:PATH}", "second": 0, "names": "model"})
	Do cases.%Push({"agent": "TriageAgent", "provider": "@{env:PATH}", "model": "claude-haiku-5-5", "second": 0, "names": "provider"})
	Do cases.%Push({"agent": "@{env:PATH}", "provider": "anthropic", "model": "claude-haiku-5-5", "second": 0, "names": "agent"})
	Do cases.%Push({"agent": "TriageAgent", "provider": "anthropic", "model": "claude-haiku-5-5@{x", "second": 1, "names": "model"})
	Do cases.%Push({"agent": "TriageAgentRetry", "provider": "anthropic", "model": "claude-haiku-5-5", "second": 0, "names": "agent"})
	Do cases.%Push({"agent": "Triage", "provider": "anthropic", "model": "claude-haiku-5-5", "second": 0, "names": "agent"})
	Do cases.%Push({"agent": "", "provider": "anthropic", "model": "claude-haiku-5-5", "second": 0, "names": "agent"})
	Do cases.%Push({"agent": "TriageAgent", "provider": "nope", "model": "claude-haiku-5-5", "second": 0, "names": "not in the provider table"})
	Do cases.%Push({"agent": "TriageAgent", "provider": "openai", "model": "gpt-5.4", "second": 0, "names": "not supported"})
	Do cases.%Push({"agent": "TriageAgent", "provider": "gemini", "model": "gemini-3.1-flash-lite", "second": 1, "names": "not supported"})
	Do cases.%Push({"agent": "TriageAgent", "provider": "anthropic", "model": "gpt-5.4", "second": 0, "names": "does not list"})
	Do cases.%Push({"agent": "TriageAgent", "provider": "anthropic", "model": "claude-opus-9", "second": 1, "names": "does not list"})
	Do cases.%Push({"agent": "TriageAgent", "provider": "", "model": "", "second": 0, "names": "empty"})
	Do cases.%Push({"agent": "TriageAgent", "provider": "anthropic", "model": "", "second": 0, "names": "empty"})
	Do cases.%Push({"agent": "TriageAgent", "provider": "", "model": "claude-haiku-5-5", "second": 0, "names": "empty"})
	Do cases.%Push({"agent": "TriageAgent", "provider": "", "model": "claude-haiku-5-5", "second": 1, "names": "empty"})
	Do cases.%Push({"agent": "TriageAgent", "provider": "anthropic", "model": "", "second": 1, "names": "empty"})
	For i = 1:1:cases.%Size() {
		Set case = cases.%Get(i - 1)
		Set label = "case "_i_" ("_case.agent_", "_case.provider_", "_case.model_", second "_case.second_")"
		Set sc = $ClassMethod(settings, "CheckModel", case.agent, case.provider, case.model, case.second)
		Do $$$AssertStatusNotOK(sc, label_" is refused by CheckModel")
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue(text [ case.names, label_" says why, with '"_case.names_"': "_text)
		Do $$$AssertTrue((text '[ "PATH") && (text '[ "@{") && (text '[ ..#FAKE), label_" holds no value in the reason")
		Set old = "x"
		Set sc = $ClassMethod(settings, "SetModel", case.agent, case.provider, case.model, case.second, .old)
		Do $$$AssertStatusNotOK(sc, label_" is refused by SetModel")
		Do $$$AssertTrue($IsObject(old) && (old.%ToJSON() = "{}"), label_": old is empty")
	}
	Do $$$AssertEquals(..State(), before, "nothing was written: the entries, the Model and RetryItem rows and the Price rows are as they were")

	// the valid inputs pass, and an empty second model passes
	For case = $ListBuild("TriageAgent", "anthropic", "claude-haiku-5-5", 0), $ListBuild("DiagnosisAgent", "anthropic", "claude-sonnet-5-5", 0), $ListBuild("ChatAgent", "anthropic", "claude-sonnet-5-5", 1), $ListBuild("TriageAgent", "", "", 1) {
		Do $$$AssertStatusOK($ClassMethod(settings, "CheckModel", $List(case, 1), $List(case, 2), $List(case, 3), $List(case, 4)), "CheckModel passes "_$ListToString(case, ", "))
	}
	Do $ClassMethod(..#SCAN, "UnsetEnv", "ANTHROPIC_API_KEY")
	Set sc = $ClassMethod(settings, "CheckModel", "TriageAgent", "anthropic", "claude-haiku-5-5", 0)
	Do $$$AssertStatusNotOK(sc, "a supported provider whose key variable is not set is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ANTHROPIC_API_KEY", "and the reason names the variable, never a value: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(..State(), before, "and nothing is written")
}

/// Rule 1: Lane B's SettingsOps.Values consumes Settings.Providers: its providers are the four rows, in table order, with keySet and supported.
Method TestIntegrationSettingsOps()
{
	Set body = ##class(OcuTalon.Core.SettingsOps).Values()
	Set providers = body.providers
	Do $$$AssertTrue($IsObject(providers) && providers.%IsA("%Library.DynamicArray"), "the body's providers is an array")
	If '$IsObject(providers) Quit
	Do $$$AssertEquals(providers.%Size(), 4, "it holds four rows")
	Set built = $ClassMethod(..#SETTINGS, "Providers")
	Do $$$AssertEquals(providers.%ToJSON(), built.%ToJSON(), "the rows are what Settings.Providers gives")
	Set names = ""
	For i = 0:1:providers.%Size() - 1 {
		Set row = providers.%Get(i)
		Set names = names _ $Select(names = "": "", 1: ",") _ row.provider
		Do $$$AssertEquals(row.%GetTypeOf("keySet")_"|"_row.%GetTypeOf("supported"), "boolean|boolean", row.provider_" carries keySet and supported")
	}
	Do $$$AssertEquals(names, "anthropic,openai,gemini,bedrock", "in table order, Anthropic first")
}

/// A runner that resolves to a provider is built as a runner that chose that provider directly: the same provider, model, provider configuration and session config.
Method TestResolvedEqualsDirect()
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).GuardReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set scan = ..#SCAN
	Set url = ##class(OcuTalon.Test.Contract.Mock).#BASEURL
	Set runner = "OcuTalon.Test.Bridge.ZzProviderRunner"
	Set cases = $ListBuild(
		$ListBuild("openai", "OCUTALON_ZZ17_ANTHROPIC", "OCUTALON_ZZ17_OPENAI", "anthropic", "openai", "gpt-5.4-mini"),
		$ListBuild("anthropic", "OCUTALON_ZZ17_OPENAI", "OCUTALON_ZZ17_ANTHROPIC", "openai", "anthropic", "claude-haiku-5-5"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set target = $List(case, 5)
		Do $ClassMethod(scan, "UnsetEnv", $List(case, 2))
		Do $ClassMethod(scan, "SetEnv", $List(case, 3), ..#FAKE)
		Set entry = {"model_provider": ($List(case, 4)), "api_key": ("@{env:"_$List(case, 2)_"}"), "base_url": (url)}.%ToJSON()
		Set direct = {"model_provider": (target), "api_key": ("@{env:"_$List(case, 3)_"}")}.%ToJSON()
		Set resolved = ##class(OcuTalon.Test.Bridge.Runner).NewRunner("OcuTalon.Agent.Triage", "low", entry, "ZzProvider", runner)
		Set chosen = ##class(OcuTalon.Test.Bridge.Runner).NewRunner("OcuTalon.Agent.Triage", "low", direct, "ZzProvider", runner)
		Set chosen.Adapter.Model = $List(case, 6)
		Set one = ..Outline(resolved)
		Set two = ..Outline(chosen)
		Do $$$AssertTrue(one '[ "build failed", target_": the resolved runner is built: "_one)
		Do $$$AssertTrue(two '[ "build failed", target_": the runner that chose the provider is built: "_two)
		Do $$$AssertEquals($Piece(one, "|", 1, 2), target_"|"_$List(case, 6), target_": the resolved runner has the provider and its default model")
		Do $$$AssertEquals(one, two, target_": a resolved runner is built exactly as one that chose the provider (provider, model, configuration and session config), neither with an endpoint field of the entry's provider (DW-758)")
	}
}

/// --- helpers ---
/// The provider, model, provider configuration and session config of the shadow runner's adapter once its agent is built: "<provider>|<model>|<configuration>|<session config>",
/// or "build failed: <reason>".
ClassMethod Outline(host As OcuTalon.Bridge.Operation.AgentRunner) As %String [ Private ]
{
	Set adapter = host.Adapter
	Set sc = adapter.BuildAgent()
	If $$$ISERR(sc) Quit "build failed: "_$SYSTEM.Status.GetErrorText(sc)
	Set sc = adapter.SessionConfigFor(.session)
	If $$$ISERR(sc) Quit "build failed: "_$SYSTEM.Status.GetErrorText(sc)
	Quit adapter.Agent.Provider.Name_"|"_adapter.Agent.Model_"|"_adapter.ProviderConfig_"|"_session.%ToJSON()
}

/// Choose on the rows (the ZzProviders table's): "<provider>|<model>|<result>".
ClassMethod Chosen(rows As %DynamicArray, entryProvider As %String, entryState As %String, isDefault As %Boolean) As %String [ Private ]
{
	Set result = $ClassMethod(..#ZZTABLE, "Choose", rows, entryProvider, entryState, isDefault, .provider, .model)
	Quit $Select(result: provider_"|"_model_"|"_result, 1: "|"_result)
}

/// "keySet|supported" of each row of the providers, separated by semicolons.
ClassMethod Flags(providers As %DynamicArray) As %String [ Private ]
{
	Set text = ""
	For i = 0:1:providers.%Size() - 1 {
		Set row = providers.%Get(i)
		Set text = text _ $Select(text = "": "", 1: ";") _ (+row.keySet) _ "|" _ (+row.supported)
	}
	Quit text
}

/// The rows that a model change could write, as one text: the Config Store entries of the six runners, the Model and RetryItem rows of the production and the Price rows.
ClassMethod State() As %String [ Private ]
{
	Set state = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SettingValue FROM Ens_Config.DefaultSettings WHERE SettingName IN ('Model', 'RetryItem') ORDER BY ID")
	While result.%Next() {
		Set state = state _ $Char(10) _ result.%GetData(1) _ "=" _ result.%GetData(2)
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT %ID, Model, InputPerMTok, OutputPerMTok FROM OcuTalon_Bridge_Data.Price ORDER BY %ID")
	While result.%Next() {
		Set state = state _ $Char(10) _ "price," _ result.%GetData(1) _ "," _ result.%GetData(2) _ "," _ result.%GetData(3) _ "," _ result.%GetData(4)
	}
	For name = "OcuTalonTriage", "OcuTalonDiagnosis", "OcuTalonChat", "OcuTalonTriageRetry", "OcuTalonDiagnosisRetry", "OcuTalonChatRetry" {
		Set found = ##class(%ConfigStore.Configuration).Exists("AI.LLM."_name)
		Set state = state _ $Char(10) _ name _ " " _ $Select(found && $$$ISOK(##class(%ConfigStore.Configuration).GetDetails("AI.LLM."_name, .details, 0, 0)): details.%ToJSON(), 1: "absent")
	}
	Quit state
}

}
