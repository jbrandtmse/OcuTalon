/// The key scan (Story 1.1; AD-7, AD-19): a key in the environment reaches the model API and is stored nowhere. THIS CLASS RUNS IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21): it sends one chat to the CI mock, so it needs the CI override's environment
/// (OCUTALON_MODEL_BASE_URL is the mock's base URL and OCUTALON_MOCK_KEY_HEADER is 1, as Test.Contract.Mock checks) and the
/// mock's request log. Where it does not have them, the test fails with the reason and builds no provider, so that it can never
/// send a request to a real model API.
/// The fake key is "ocutalon-keyscan-" and a reference: it does not look like a key, and it lives only in the environment of the
/// test's process, restored afterwards. No callback runs in the process.
///   - TestKeyIsStoredNowhere: with the fake key in the environment, the Provider step runs again, a provider is built from the
///     ProviderConfig setting of TriageAgent the way the runners' adapter builds it, a Triage agent chats once with the model
///     that TriageAgent resolves, and the session is saved. The mock logs a key of the fake key's length, the mock-key header,
///     the script triage picked by the mock key, and the model; Find on the fake key names no store; Find on values that the
///     stores do hold names their stores, so that the scan is shown to see what it scans. The session is deleted.
/// Find(value) is the scan that other stories reuse: it names each of the stores it scans that holds the value (the stores
/// are listed at Find; the audit log, the journal and the jobs' runtime settings are not among them). The agent steps (the Label and
/// the Summary of every AgentStep message, Story 1.5) are one of the stores, and the positive control of TestKeyIsStoredNowhere saves
/// one step with a fresh value to show that the scan sees them. SetEnv, UnsetEnv and
/// HasEnv are the helpers that set, remove and test an environment variable of the process, for the tests that need a key
/// there.
/// Added by the QA stage of Story 1.5 (AD-31):
///   - TestLogRowsHolding: the count that the step tests make of the event-log rows after a mark that hold a value
///     (Test.Agent.RunnerFixture.LogRowsHolding) is shown to see a row: it counts a row of each type after the mark that holds the value,
///     not a row from before the mark, and not a value that no row holds. Without it, a test that expects 0 would also pass if the
///     count could never find anything. The rows are removed.
Class OcuTalon.Test.Agent.KeyScan Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The environment variable of the key, which the entries name as a placeholder.
Parameter KEYVARIABLE = "ANTHROPIC_API_KEY";

/// The start of the fake key.
Parameter FAKEPREFIX = "ocutalon-keyscan-";

/// The runner whose ProviderConfig the test uses.
Parameter RUNNER = "TriageAgent";

/// The agent class of that runner.
Parameter AGENT = "OcuTalon.Agent.Triage";

/// A key in the environment reaches the mock with its length, and no entry, session, setting or event-log row holds it.
Method TestKeyIsStoredNowhere()
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).GuardReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set fake = ..#FAKEPREFIX_##class(OcuTalon.Bridge.Ids).NewRef()
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set had = ..HasEnv(..#KEYVARIABLE)
	Set previous = $SYSTEM.Util.GetEnviron(..#KEYVARIABLE)
	Set sessionId = ""
	Set logText = ""
	Set stepId = ""
	Try {
		Do ..SetEnv(..#KEYVARIABLE, fake)
		Do $$$AssertEquals($SYSTEM.Util.GetEnviron(..#KEYVARIABLE), fake, "the fake key is in the environment of the process")
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Provider).Run(), "the Provider step runs again with the key in the environment")

		Set config = ##class(Ens.Director).GetAdapterSettingValue(..#PRODUCTION_"||"_..#RUNNER, "ProviderConfig", .status)
		Do $$$AssertStatusOK(status, "the ProviderConfig setting of "_..#RUNNER_" is read")
		Do $$$AssertEquals(config, "@{config:OcuTalonTriage}", "and names the entry")
		Do $$$AssertStatusOK(##class(%AI.Utils.SettingStore).RegisterDefaults(), "the setting stores are registered")
		Set settings = {}.%FromJSON(##class(%AI.Utils.SettingStore).Expand(config))
		Do $$$AssertEquals(settings."api_key", "@{env:ANTHROPIC_API_KEY}", "the expansion leaves the key as the placeholder")
		Set provider = ##class(%AI.Provider).Create(settings."model_provider", settings)
		Set model = ##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(..#RUNNER, ..#PRODUCTION)
		Do $$$AssertEquals(model, "claude-haiku-5-5", "the runner resolves claude-haiku-5-5")

		Set agent = $ClassMethod(..#AGENT, "%New", provider)
		Set agent.Model = model
		Do $$$AssertStatusOK(agent.%Init(), "the agent initializes")
		Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
		Set session = agent.CreateSession({"max_tokens": 8000})
		Set response = agent.Chat(session, "A new email arrived in the Orders inbox (test "_ref_"). Should the user hear about it now?")
		Do $$$AssertTrue(response.Content '= "", "the mock answered")
		Do $$$AssertStatusOK(session.%Save(), "the session is saved")
		Set sessionId = session.%Id()

		Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
		Set post = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequest(entries, ref)
		Do $$$AssertTrue($IsObject(post), "the log holds the request")
		If $IsObject(post) {
			Do $$$AssertEquals(post.keyLength, $Length(fake), "the key's length is the fake key's")
			Do $$$AssertTrue(##class(OcuTalon.Test.Agent.RunnerFixture).Has(post.headerNames, "x-api-key"), "the key traveled in x-api-key")
			Do $$$AssertTrue(##class(OcuTalon.Test.Agent.RunnerFixture).Has(post.headerNames, "x-ocutalon-mockkey"), "the mock key traveled in x-ocutalon-mockkey")
			Do $$$AssertEquals(post.selectedBy, "mockkey", "the script was picked by the mock key")
			Do $$$AssertEquals(post.scenario, "triage", "the script is triage")
			Do $$$AssertEquals(post.model, "claude-haiku-5-5", "the request names claude-haiku-5-5")
			Do $$$AssertEquals(post.status, 200, "and was answered with 200")
		}
		Do $$$AssertTrue(entries.%ToJSON() '[ fake, "the mock's log lines hold no key")

		Set found = ..Find(fake)
		Do $$$AssertEquals($ListToString(found, "; "), "", "the fake key is in no entry, saved session, setting or event-log row")

		// The scan sees what it scans.
		Set logText = "ocutalon-keyscan-control-"_##class(OcuTalon.Bridge.Ids).NewRef()
		Do ##class(Ens.Util.Log).LogInfo("OcuTalon.Test.Agent.KeyScan", "TestKeyIsStoredNowhere", logText)
		Set text = $ListToString(..Find(ref), "; ")
		Do $$$AssertTrue(text [ ("session "_sessionId), "Find sees the saved session by what the chat said: "_text)
		Set text = $ListToString(..Find("anthropic"), "; ")
		Do $$$AssertTrue(text [ "entry AI.LLM.OcuTalonTriage", "Find sees an entry: "_$Extract(text, 1, 200))
		Set text = $ListToString(..Find("@{config:OcuTalonTriage}"), "; ")
		Do $$$AssertTrue(text [ "setting OcuTalon.Production||TriageAgent||*||ProviderConfig", "Find sees a setting row: "_$Extract(text, 1, 200))
		Set text = $ListToString(..Find(..#AGENT), "; ")
		Do $$$AssertTrue(text [ "item setting TriageAgent:Adapter:AgentClass", "Find sees an item setting: "_$Extract(text, 1, 200))
		Set text = $ListToString(..Find(logText), "; ")
		Do $$$AssertTrue(text [ "event log", "Find sees an event-log row: "_text)
		Set stepText = "ocutalon-keyscan-step-"_##class(OcuTalon.Bridge.Ids).NewRef()
		Set step = ##class(OcuTalon.Bridge.Msg.AgentStep).%New()
		Set step.DecisionRef = "zzkeyscan"
		Set step.Position = 1
		Set step.StepKind = "tool"
		Set step.Label = "Reading the key scan control"
		Set step.Summary = "zz_keyscan. Inputs: {}. Result: "_stepText_"."
		Set step.Status = "ok"
		Do $$$AssertStatusOK(step.%Save(), "an agent step with a fresh value is saved")
		Set stepId = step.%Id()
		Set text = $ListToString(..Find(stepText), "; ")
		Do $$$AssertTrue(text [ ("agent steps "_stepId), "Find sees an agent step: "_text)
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the key scan runs without an exception")
	}
	If sessionId '= "" Do ##class(%AI.Agent.Session).%DeleteId(sessionId)
	If logText '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Text = ?", logText)
	If stepId '= "" Do ##class(OcuTalon.Bridge.Msg.AgentStep).%DeleteId(stepId)
	If had {
		Do ..SetEnv(..#KEYVARIABLE, previous)
	} Else {
		Do ..UnsetEnv(..#KEYVARIABLE)
	}
	Do $$$AssertEquals(..HasEnv(..#KEYVARIABLE), had, "the key variable is as it was found")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Provider).Run(), "the Provider step runs once more with the environment as it was")
}

/// LogRowsHolding sees a row of the event log that holds a value and was written after the mark. It runs with no production and no mock.
Method TestLogRowsHolding()
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set tag = "ocutalon-logscan-" _ ##class(OcuTalon.Bridge.Ids).NewRef()
	Set early = tag _ "-early"
	Set info = tag _ "-info"
	Set warning = tag _ "-warning"
	Try {
		Set start = $ClassMethod(fixture, "EventMark")
		Do ##class(Ens.Util.Log).LogInfo("OcuTalon.Test.Agent.KeyScan", "TestLogRowsHolding", "a row from before the mark: " _ early)
		Set mark = $ClassMethod(fixture, "EventMark")
		Do ##class(Ens.Util.Log).LogInfo("OcuTalon.Test.Agent.KeyScan", "TestLogRowsHolding", "an info row: " _ info _ " and more text")
		Do ##class(Ens.Util.Log).LogWarning("OcuTalon.Test.Agent.KeyScan", "TestLogRowsHolding", "a warning row: " _ warning)
		Do $$$AssertEquals($ClassMethod(fixture, "LogRowsHolding", mark, info), 1, "an info row after the mark that holds the value is counted")
		Do $$$AssertEquals($ClassMethod(fixture, "LogRowsHolding", mark, warning), 1, "and so is a warning row")
		Do $$$AssertEquals($ClassMethod(fixture, "LogRowsHolding", mark, tag), 2, "a value that two rows hold counts both")
		Do $$$AssertEquals($ClassMethod(fixture, "LogRowsHolding", mark, early), 0, "a row from before the mark is not counted")
		Do $$$AssertEquals($ClassMethod(fixture, "LogRowsHolding", start, early), 1, "but it is counted from a mark before it")
		Do $$$AssertEquals($ClassMethod(fixture, "LogRowsHolding", mark, tag _ "-none"), 0, "a value that no row holds is not counted")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the event log is written and counted without an exception")
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Text [ ?", tag)
	Do $$$AssertEquals($ClassMethod(fixture, "LogRowsHolding", 0, tag), 0, "the rows are removed")
}

/// The stores that hold the value, as a list of descriptions; "" when none does:
///   - "entry <name>": an AI.LLM entry named OcuTalon*, read without its secrets resolved;
///   - "session <id>": a saved AI Hub session, opened and exported (its context is stored compressed);
///   - "setting <id>": a row of the System Default Settings;
///   - "item setting <item>:<target>:<name>": an item setting of OcuTalon.Production, or "production setting <name>";
///   - "event log <id>": a row of the Event Log;
///   - "agent steps <id>": an AgentStep message whose Label or Summary holds it (FindSteps);
/// and "<store> could not be read" for a store that cannot be scanned, so that an unreadable store never counts as clean.
ClassMethod Find(value As %String) As %List
{
	Set found = ""
	If value = "" Quit found
	Try {
		Set found = found _ ..FindEntries(value) _ ..FindSettings(value) _ ..FindItemSettings(value) _ ..FindEventLog(value) _ ..FindSessions(value) _ ..FindSteps(value)
	} Catch exception {
		Set found = found _ $ListBuild("the scan failed: "_$SYSTEM.Status.GetErrorText(exception.AsStatus()))
	}
	Quit found
}

ClassMethod FindEntries(value As %String) As %List [ Private ]
{
	Set found = ""
	Set result = ##class(%ResultSet).%New("%ConfigStore.Configuration:List")
	Set sc = result.Execute("AI", "LLM", "*", "*", "*", "*")
	If $$$ISERR(sc) Quit $ListBuild("entries could not be read")
	While result.Next() {
		If $Extract(result.Get("Name"), 1, 8) '= "OcuTalon" Continue
		Set fqn = result.Get("FullyQualifiedName")
		If $$$ISERR(##class(%ConfigStore.Configuration).GetDetails(fqn, .details, 0, 0)) {
			Set found = found _ $ListBuild("entry "_fqn_" could not be read")
		} ElseIf details.%ToJSON() [ value {
			Set found = found _ $ListBuild("entry "_fqn)
		}
	}
	Quit found
}

ClassMethod FindSettings(value As %String) As %List [ Private ]
{
	Set found = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SettingValue, Description FROM Ens_Config.DefaultSettings")
	If result.%SQLCODE < 0 Quit $ListBuild("settings could not be read")
	While result.%Next() {
		If (result.%GetData(2) [ value) || (result.%GetData(3) [ value) Set found = found _ $ListBuild("setting "_result.%GetData(1))
	}
	Quit found
}

ClassMethod FindItemSettings(value As %String) As %List [ Private ]
{
	Set found = ""
	Set production = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
	If '$IsObject(production) Quit $ListBuild("the item settings could not be read")
	For i = 1:1:production.Settings.Count() {
		Set setting = production.Settings.GetAt(i)
		If setting.Value [ value Set found = found _ $ListBuild("production setting "_setting.Name)
	}
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		For j = 1:1:item.Settings.Count() {
			Set setting = item.Settings.GetAt(j)
			If setting.Value [ value Set found = found _ $ListBuild("item setting "_item.Name_":"_setting.Target_":"_setting.Name)
		}
	}
	Quit found
}

ClassMethod FindEventLog(value As %String) As %List [ Private ]
{
	Set found = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens_Util.Log WHERE Text [ ?", value)
	If result.%SQLCODE < 0 Quit $ListBuild("the event log could not be read")
	While result.%Next() {
		Set found = found _ $ListBuild("event log "_result.%GetData(1))
	}
	Quit found
}

ClassMethod FindSteps(value As %String) As %List [ Private ]
{
	Set found = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Bridge_Msg.AgentStep WHERE Label [ ? OR Summary [ ?", value, value)
	If result.%SQLCODE < 0 Quit $ListBuild("agent steps could not be read")
	While result.%Next() {
		Set found = found _ $ListBuild("agent steps "_result.%GetData(1))
	}
	Quit found
}

ClassMethod FindSessions(value As %String) As %List [ Private ]
{
	Set found = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM %AI_Agent.Session")
	If result.%SQLCODE < 0 Quit $ListBuild("saved sessions could not be read")
	Set agent = ""
	While result.%Next() {
		Set id = result.%GetData(1)
		Try {
			If agent = "" {
				Set agent = ##class(%AI.Agent).%New(##class(%AI.Provider).Create("anthropic", {"api_key": "ocutalon-keyscan-reader"}))
			}
			Set session = agent.OpenSession(id)
			If session.Export() [ value Set found = found _ $ListBuild("session "_id)
		} Catch exception {
			Set found = found _ $ListBuild("session "_id_" could not be read")
		}
	}
	Quit found
}

/// --- helpers ---
/// Sets an environment variable of this process (a helper that other test classes may call).
ClassMethod SetEnv(name As %String, value As %String) [ Language = python ]
{
	import os
	os.environ[name] = value
}

/// Removes an environment variable of this process.
ClassMethod UnsetEnv(name As %String) [ Language = python ]
{
	import os
	os.environ.pop(name, None)
}

/// 1 when this process has the environment variable, whatever its value.
ClassMethod HasEnv(name As %String) As %Boolean [ Language = python ]
{
	import os
	return name in os.environ
}

}
