/// Tests of the session config of the agent runners and of the model families (Story 1.2; AD-7, AD-19). Pure: no provider is built
/// and nothing is sent. The tests change the rows of OcuTalon.Bridge.Data.ModelFamily, and put every row back as it was found.
///   - TestFamilies: Compose gives, for each row of the matrix, the exact config: the cap at the family's CapKey, the effort at its
///     EffortKey, max_iterations when the agent has one, and the cache block; a model that starts with a longer prefix takes that
///     family; an empty model and a model that no row matches fail, naming the model;
///   - TestAgents: the exact config of Triage (effort low), Diagnosis (effort high) and Chat (no effort, 4 iterations), from the
///     compiled agents and the seeds of the Production step;
///   - TestNoSampling: no config holds temperature, top_p or top_k at any depth, also for an agent whose Temperature is set before the
///     build, once the adapter has cleared it;
///   - TestInstallerRows: the installer writes the three families exactly, keeps a row of another family, and writes a changed
///     seeded row again;
///   - TestInstallerRun: Installer.Run, the call of the after-start installer, writes the three families (it needs an Interoperability
///     namespace, and registers the audit events as it does at every start);
///   - TestComposeBranches: a family row that has no CapKey fails the compose, naming the model, and gives no config.
/// Added by Story 1.7 (AD-7, AD-8):
///   - TestTimeoutMs: Compose with no timeoutMs ("" or not passed) gives exactly the config it gave before, and with a timeoutMs adds
///     "timeout_ms" last, as a number, for every family; a compose that fails still gives no config.
Class OcuTalon.Test.Bridge.SessionConfig Extends %UnitTest.TestCase
{

/// The cache block of every config.
Parameter CACHE = "{""enabled"":1,""cache_system_prompt"":1,""cache_tool_definitions"":1,""min_tokens_for_cache"":512}";

/// The three families that the installer writes, as Rows gives them: Family|ModelPrefix|CapKey|EffortKey, ordered by family.
Parameter FAMILYROWS = "anthropic|claude-|max_tokens|extra_params.output_config.effort;default||max_tokens|;gpt-5|gpt-5|extra_params.max_completion_tokens|";

/// The rows of ModelFamily when the class began, as JSON: [{"family","prefix","cap","effort"}].
Property Saved As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set rows = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Family, ModelPrefix, CapKey, EffortKey FROM OcuTalon_Bridge_Data.ModelFamily")
	While result.%Next() {
		Do rows.%Push({"family": (result.%Get("Family")), "prefix": (result.%Get("ModelPrefix")), "cap": (result.%Get("CapKey")), "effort": (result.%Get("EffortKey"))})
	}
	Set ..Saved = rows.%ToJSON()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Restore()
	Quit $$$OK
}

/// Compose for every pure row of the matrix, with the rows the installer writes. The longest prefix wins, so a row for claude-haiku
/// takes a haiku model from the Anthropic family, and only that model.
Method TestFamilies()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).SeedModelFamilies(), "the installer's families are written")
	Try {
		Do ..AssertCompose("", "claude-haiku-5-5", "low", "{""max_tokens"":8000,""extra_params"":{""output_config"":{""effort"":""low""}},""cache"":"_..#CACHE_"}", "an Anthropic model gets max_tokens and the effort")
		Do ..AssertCompose("", "claude-sonnet-5-5", "", "{""max_tokens"":8000,""cache"":"_..#CACHE_"}", "an Anthropic model with an empty effort gets no effort")
		Do ..AssertCompose(4, "claude-haiku-5-5", "", "{""max_tokens"":8000,""max_iterations"":4,""cache"":"_..#CACHE_"}", "max_iterations follows the cap, and comes before the cache block")
		Do ..AssertCompose("", "gpt-5-mini", "high", "{""extra_params"":{""max_completion_tokens"":8000},""cache"":"_..#CACHE_"}", "a GPT-5 model gets max_completion_tokens in extra_params, no max_tokens and no effort")
		Do ..AssertCompose(4, "gpt-5", "high", "{""extra_params"":{""max_completion_tokens"":8000},""max_iterations"":4,""cache"":"_..#CACHE_"}", "gpt-5 itself is in the family")
		Do ..AssertCompose("", "zz-other-model", "high", "{""max_tokens"":8000,""cache"":"_..#CACHE_"}", "another model gets the default family: max_tokens and no effort")

		Do ..Upsert("ZzHaiku", "claude-haiku", "extra_params.zz.cap", "extra_params.zz.effort")
		Do ..AssertCompose("", "claude-haiku-5-5", "low", "{""extra_params"":{""zz"":{""cap"":8000,""effort"":""low""}},""cache"":"_..#CACHE_"}", "the longest prefix wins: claude-haiku beats claude-")
		Do ..AssertCompose("", "claude-sonnet-5-5", "low", "{""max_tokens"":8000,""extra_params"":{""output_config"":{""effort"":""low""}},""cache"":"_..#CACHE_"}", "and a model that starts with claude- only keeps the Anthropic family")
		Do ..Delete("ZzHaiku")

		Set sc = ##class(OcuTalon.Bridge.Adapter.Agent).Compose("", "", "low", .config)
		Do $$$AssertStatusNotOK(sc, "an empty model fails")
		Do $$$AssertEquals(config, "", "and gives no config")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "No model resolves", "and says that none resolves: "_$SYSTEM.Status.GetErrorText(sc))

		Do ..Delete("default")
		Set sc = ##class(OcuTalon.Bridge.Adapter.Agent).Compose("", "zz-other-model", "low", .config)
		Do $$$AssertStatusNotOK(sc, "a model that no row matches fails, as it can only without the default row")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "zz-other-model", "and the error names the model: "_$SYSTEM.Status.GetErrorText(sc))
		Do $$$AssertEquals(config, "", "and gives no config")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..Restore()
}

/// The agents of the product: the config that each runner composes from its agent and the seeds of the Production step.
Method TestAgents()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).SeedModelFamilies(), "the installer's families are written")
	Try {
		Set step = "OcuTalon.Install.Step.Production"
		Set expected("OcuTalon.Agent.Triage") = "{""max_tokens"":8000,""extra_params"":{""output_config"":{""effort"":""low""}},""cache"":"_..#CACHE_"}"
		Set expected("OcuTalon.Agent.Diagnosis") = "{""max_tokens"":8000,""extra_params"":{""output_config"":{""effort"":""high""}},""cache"":"_..#CACHE_"}"
		Set expected("OcuTalon.Agent.Chat") = "{""max_tokens"":8000,""max_iterations"":4,""cache"":"_..#CACHE_"}"
		Set class = ""
		For {
			Set class = $Order(expected(class))
			Quit:class=""
			Set agent = $ClassMethod(class, "%New")
			Do $$$AssertEquals(agent.Model, "claude-haiku-5-5", class_" has the model claude-haiku-5-5")
			Do ..AssertCompose(agent.MaxIterations, agent.Model, $ClassMethod(step, "AgentEffort", class), expected(class), class_" composes its config")
		}
		Do $$$AssertEquals($ClassMethod(step, "AgentEffort", "OcuTalon.Agent.Triage"), "low", "Triage seeds the effort low")
		Do $$$AssertEquals($ClassMethod(step, "AgentEffort", "OcuTalon.Agent.Diagnosis"), "high", "Diagnosis seeds the effort high")
		Do $$$AssertEquals($ClassMethod(step, "AgentEffort", "OcuTalon.Agent.Chat"), "", "Chat seeds no effort")
		Do $$$AssertEquals(##class(OcuTalon.Agent.Triage).%New().MaxIterations, "", "Triage sets no max_iterations")
		Do $$$AssertEquals(##class(OcuTalon.Agent.Diagnosis).%New().MaxIterations, "", "and neither does Diagnosis")
		Do $$$AssertEquals(##class(OcuTalon.Agent.Chat).%New().MaxIterations, 4, "Chat sets 4")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..Restore()
}

/// No config holds temperature, top_p or top_k at any depth. An agent that has a Temperature before the build gets a session config
/// with a temperature from AI Hub (the control), and none once the adapter has cleared it.
Method TestNoSampling()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).SeedModelFamilies(), "the installer's families are written")
	Try {
		Set agent = ##class(OcuTalon.Test.Bridge.ProbeAgent).%New()
		Do $$$AssertEquals(agent.Temperature, 0.7, "the probe agent has a temperature before the build")
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Adapter.Agent).Compose(agent.MaxIterations, agent.Model, "high", .config), "a config is composed")
		Set control = ##class(%AI.Agent).%New()
		Set control.Temperature = 0.7
		Set built = control.BuildSessionConfig({}.%FromJSON(config.%ToJSON()))
		Do $$$AssertTrue(built.%ToJSON() [ """temperature""", "the control: AI Hub adds the temperature of an agent that has one: "_built.%ToJSON())
		Do ##class(OcuTalon.Bridge.Adapter.Agent).ClearSampling(agent)
		Do $$$AssertEquals(agent.Temperature, "", "the adapter clears the temperature of the agent")
		Set built = agent.BuildSessionConfig({}.%FromJSON(config.%ToJSON()))
		Do $$$AssertEquals(built.%ToJSON(), config.%ToJSON(), "and AI Hub then adds nothing to the composed config")
		Set families = $ListBuild("claude-haiku-5-5", "gpt-5-mini", "zz-other-model")
		Set position = 0
		While $ListNext(families, position, model) {
			Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Adapter.Agent).Compose(4, model, "high", .config), "a config is composed for "_model)
			Set json = config.%ToJSON()
			For key = "temperature", "top_p", "top_k" {
				Do $$$AssertTrue(json '[ ("""" _ key _ """"), "the config for "_model_" holds no "_key_" at any depth")
			}
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..Restore()
}

/// The installer writes the three families of the spec, exactly. A row of another family is kept, a changed seeded row is written
/// again, and a deleted one is written again.
Method TestInstallerRows()
{
	Try {
		Set expected = ..#FAMILYROWS
		Do $$$AssertEquals($ListLength(##class(OcuTalon.Bridge.Installer).ModelFamilies()), 3, "the installer has three families")
		Do ..Upsert("ZzFamily", "zz-", "zz_cap", "zz_effort")
		Do ..Upsert("anthropic", "changed-", "changed_cap", "changed_effort")
		Do ..Delete("gpt-5")
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).SeedModelFamilies(), "the installer writes the families")
		Do $$$AssertEquals(..Rows("Family IN ('anthropic', 'default', 'gpt-5')"), expected, "the three families are exactly the seeded ones, whatever the rows were")
		Do $$$AssertEquals(..Rows("Family = 'ZzFamily'"), "ZzFamily|zz-|zz_cap|zz_effort", "the row of another family is kept as it is")
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).SeedModelFamilies(), "the installer writes the families again")
		Do $$$AssertEquals(..Rows("Family IN ('anthropic', 'default', 'gpt-5')"), expected, "a second run changes nothing")
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ModelFamily WHERE Family IN ('anthropic', 'gpt-5', 'default')")
		Do result.%Next()
		Do $$$AssertEquals(result.%GetData(1), 3, "and there is one row for each of the three families")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..Restore()
}

/// The call of the after-start installer, Installer.Run, writes the three families: with the rows deleted, Run succeeds and the
/// rows are exactly the seeded ones, so a start that runs the installer leaves every runner a family to compose from.
Method TestInstallerRun()
{
	Try {
		For family = "anthropic", "gpt-5", "default" {
			Do ..Delete(family)
		}
		Do $$$AssertEquals(..Rows("Family IN ('anthropic', 'default', 'gpt-5')"), "", "the three families are deleted")
		Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).Run(), "the installer's Run succeeds")
		Do $$$AssertEquals(..Rows("Family IN ('anthropic', 'default', 'gpt-5')"), ..#FAMILYROWS, "and has written the three families")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..Restore()
}

/// A family row with no CapKey does not compose: the compose fails, says which model and that the CapKey is missing, and gives no
/// config, so that no request goes out without its output cap.
Method TestComposeBranches()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).SeedModelFamilies(), "the installer's families are written")
	Try {
		Do ..Upsert("ZzNoCap", "zz-nocap-", "", "extra_params.zz.effort")
		Set sc = ##class(OcuTalon.Bridge.Adapter.Agent).Compose("", "zz-nocap-1", "low", .config)
		Do $$$AssertStatusNotOK(sc, "a family row with no CapKey fails the compose")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "zz-nocap-1", "and the error names the model: "_$SYSTEM.Status.GetErrorText(sc))
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "CapKey", "and says that the CapKey is missing")
		Do $$$AssertEquals(config, "", "and gives no config")
		Do ..AssertCompose("", "claude-haiku-5-5", "low", "{""max_tokens"":8000,""extra_params"":{""output_config"":{""effort"":""low""}},""cache"":"_..#CACHE_"}", "while a model of a family with a CapKey still composes")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..Restore()
}

/// timeout_ms is the last key of the config, set only when timeoutMs is given (Timeouts.Derive gives it from the bridge timer): without it the
/// config is exactly what it was, for every family, and a compose that fails gives no config with or without it.
Method TestTimeoutMs()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).SeedModelFamilies(), "the installer's families are written")
	Try {
		Set agent = "OcuTalon.Bridge.Adapter.Agent"
		Set anthropic = "{""max_tokens"":8000,""extra_params"":{""output_config"":{""effort"":""low""}},""max_iterations"":4,""cache"":"_..#CACHE_"}"
		Do ..AssertCompose(4, "claude-haiku-5-5", "low", anthropic, "no timeoutMs gives the config as it was")
		Set sc = $ClassMethod(agent, "Compose", 4, "claude-haiku-5-5", "low", .empty, "")
		Do $$$AssertStatusOK(sc, "an empty timeoutMs composes")
		If $$$ISOK(sc) Do $$$AssertEquals(empty.%ToJSON(), anthropic, "and gives the config as it was: no timeout_ms")
		Set sc = $ClassMethod(agent, "Compose", 4, "claude-haiku-5-5", "low", .with, 55000)
		Do $$$AssertStatusOK(sc, "a timeoutMs of 55000 composes")
		If $$$ISOK(sc) {
			Do $$$AssertEquals(with.%ToJSON(), $Extract(anthropic, 1, *-1)_",""timeout_ms"":55000}", "and adds ""timeout_ms"":55000 after the cache block, as a number")
			Do $$$AssertEquals(with.%GetTypeOf("timeout_ms"), "number", "its type is number")
		}
		Set sc = $ClassMethod(agent, "Compose", 4, "claude-haiku-5-5", "low", .text, "55000")
		If $$$ISOK(sc) Do $$$AssertEquals(text.%GetTypeOf("timeout_ms"), "number", "a timeoutMs given as text is a number too")
		Set derived = ##class(OcuTalon.Bridge.Timeouts).Derive(60).%Get("timeout_ms")
		Set sc = $ClassMethod(agent, "Compose", "", "gpt-5-mini", "high", .gpt, derived)
		Do $$$AssertStatusOK(sc, "the timeout_ms that Timeouts.Derive gives for 60 composes")
		If $$$ISOK(sc) Do $$$AssertEquals(gpt.%ToJSON(), "{""extra_params"":{""max_completion_tokens"":8000},""cache"":"_..#CACHE_",""timeout_ms"":55000}", "for a GPT-5 model as well")
		Set sc = $ClassMethod(agent, "Compose", "", "zz-other-model", "", .other, 15000)
		If $$$ISOK(sc) Do $$$AssertEquals(other.%ToJSON(), "{""max_tokens"":8000,""cache"":"_..#CACHE_",""timeout_ms"":15000}", "and for the default family")
		Set sc = $ClassMethod(agent, "Compose", "", "", "low", .none, 55000)
		Do $$$AssertStatusNotOK(sc, "an empty model still fails with a timeoutMs")
		Do $$$AssertEquals(none, "", "and gives no config")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ..Restore()
}

/// --- helpers ---
/// Asserts that Compose gives exactly the JSON.
Method AssertCompose(maxIterations As %Integer, model As %String, effort As %String, json As %String, label As %String) [ Private ]
{
	Set sc = ##class(OcuTalon.Bridge.Adapter.Agent).Compose(maxIterations, model, effort, .config)
	Do $$$AssertStatusOK(sc, label_": Compose succeeds")
	If $$$ISOK(sc) Do $$$AssertEquals(config.%ToJSON(), json, label)
}

/// The rows that the condition selects, as Family|ModelPrefix|CapKey|EffortKey, ordered by family and separated by semicolons.
ClassMethod Rows(condition As %String) As %String [ Private ]
{
	Set text = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Family, ModelPrefix, CapKey, EffortKey FROM OcuTalon_Bridge_Data.ModelFamily WHERE "_condition_" ORDER BY Family")
	While result.%Next() {
		Set text = text _ $Select(text = "": "", 1: ";") _ result.%Get("Family") _ "|" _ result.%Get("ModelPrefix") _ "|" _ result.%Get("CapKey") _ "|" _ result.%Get("EffortKey")
	}
	Quit text
}

/// Writes the row of the family with the values: it changes the row when it exists and creates it otherwise.
ClassMethod Upsert(family As %String, prefix As %String, cap As %String, effort As %String) [ Private ]
{
	If ##class(OcuTalon.Bridge.Data.ModelFamily).FamilyIndexExists(family, .id) {
		Set row = ##class(OcuTalon.Bridge.Data.ModelFamily).%OpenId(id)
	} Else {
		Set row = ##class(OcuTalon.Bridge.Data.ModelFamily).%New()
		Set row.Family = family
	}
	Set row.ModelPrefix = prefix
	Set row.CapKey = cap
	Set row.EffortKey = effort
	Do row.%Save()
}

/// Deletes the row of the family, if there is one.
ClassMethod Delete(family As %String) [ Private ]
{
	If ##class(OcuTalon.Bridge.Data.ModelFamily).FamilyIndexExists(family, .id) Do ##class(OcuTalon.Bridge.Data.ModelFamily).%DeleteId(id)
}

/// Puts the rows of ModelFamily back as the class found them: the rows it found are written again, and the others are deleted.
Method Restore() [ Private ]
{
	Set saved = {}.%FromJSON(..Saved)
	Kill keep
	Set iterator = saved.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set keep(row.family) = ""
		Do ..Upsert(row.family, row.prefix, row.cap, row.effort)
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Family FROM OcuTalon_Bridge_Data.ModelFamily")
	While result.%Next() {
		Set family = result.%Get("Family")
		If '$Data(keep(family)) Set doomed(family) = ""
	}
	Set family = ""
	For {
		Set family = $Order(doomed(family))
		Quit:family=""
		Do ..Delete(family)
	}
}

}
