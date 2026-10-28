Include Ensemble

/// Tests of the runners' models in a production that the Production step started (Story 1.1; AD-7, AD-19). THIS CLASS RUNS IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the Model and Effort rows that the Production step seeded at the start,
/// it runs the Production step again, which restarts the production, and it restarts one runner item. Where the production does
/// not run, the tests fail with that reason.
///   - TestAppliedAtStart: with the three Model rows and the two Effort rows deleted, the Production step's Run() seeds them and
///     restarts the production, and the running items of the three runners then apply claude-haiku-5-5, the effort of their
///     agent class (low, high, none) and their ProviderConfig, so the step seeds the rows before it starts the production;
///   - TestRunnersResolve: the three runners resolve claude-haiku-5-5, an unknown item resolves nothing, each runner has a
///     Model row with claude-haiku-5-5, and the step's own check, Production.UnresolvedRunners, names no runner;
///   - TestModelChange: one change of DiagnosisAgent's Model row to claude-sonnet-5-5 and a restart of that item make both
///     ResolveModel and the runtime setting of the item sonnet, with the item's job alive; a diagnose Request then reaches the CI
///     mock with the model claude-sonnet-5-5, a cap of 8000 and the effort high (Story 1.2, AC3), with the keys pointed at the
///     CI mock key variable and put back; the row is then put back, the item restarted again, and both read claude-haiku-5-5.
/// The row and the item are put back as they were found, also when an assertion fails.
Class OcuTalon.Test.Agent.Models Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The runners of the production.
Parameter RUNNERS = "TriageAgent,DiagnosisAgent,ChatAgent";

/// The model that every runner resolves at the start.
Parameter DEFAULTMODEL = "claude-haiku-5-5";

/// The model that the change test switches DiagnosisAgent to.
Parameter OTHERMODEL = "claude-sonnet-5-5";

/// The runner whose model the change test switches.
Parameter CHANGED = "DiagnosisAgent";

/// The Production step seeds the Model and Effort rows before it starts the production. With the three Model rows and the two
/// Effort rows deleted, Run() writes them again and restarts the production, and the running items apply the default model and
/// the effort of their agent class (low for Triage, high for Diagnosis, none for Chat), which they would not if the rows were
/// written after the start. Each item also applies its ProviderConfig row. The rows must hold the seeded values when the test
/// starts, so that the seed puts them back as they were found; a run that fails leaves them seeded again.
Method TestAppliedAtStart()
{
	If '..Running() Quit
	Set runners = $ListFromString(..#RUNNERS)
	Set effort("TriageAgent") = "low", effort("DiagnosisAgent") = "high", effort("ChatAgent") = ""
	Set found = 1
	Set position = 0
	While $ListNext(runners, position, item) {
		Set id = ..#PRODUCTION_"||"_item_"||*||Model"
		Set found = ##class(Ens.Config.DefaultSettings).%ExistsId(id) && (##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue = ..#DEFAULTMODEL)
		Do $$$AssertTrue(found, item_" has a Model row with "_..#DEFAULTMODEL_" before the test")
		If 'found Quit
		If effort(item) = "" Continue
		Set id = ..#PRODUCTION_"||"_item_"||*||Effort"
		Set found = ##class(Ens.Config.DefaultSettings).%ExistsId(id) && (##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue = effort(item))
		Do $$$AssertTrue(found, item_" has an Effort row with "_effort(item)_" before the test")
		If 'found Quit
	}
	If 'found Quit
	Try {
		Set position = 0
		While $ListNext(runners, position, item) {
			Do $$$AssertStatusOK(##class(Ens.Config.DefaultSettings).%DeleteId(..#PRODUCTION_"||"_item_"||*||Model"), "the Model row of "_item_" is deleted")
			If effort(item) '= "" Do $$$AssertStatusOK(##class(Ens.Config.DefaultSettings).%DeleteId(..#PRODUCTION_"||"_item_"||*||Effort"), "the Effort row of "_item_" is deleted")
		}
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).Run(), "the Production step seeds the rows and restarts the production")
		Set position = 0
		While $ListNext(runners, position, item) {
			Do $$$AssertEquals($Get($$$ConfigSetting(item, "Adapter", "Model")), ..#DEFAULTMODEL, item_" applies "_..#DEFAULTMODEL_" as the step started it")
			Do $$$AssertEquals($Get($$$ConfigSetting(item, "Adapter", "Effort")), effort(item), item_" applies the effort '"_effort(item)_"' (empty: none) as the step started it")
			Set config = ##class(Ens.Director).GetAdapterSettingValue(..#PRODUCTION_"||"_item, "ProviderConfig", .status)
			Do $$$AssertTrue(config ? 1"@{config:OcuTalon"1.A1"}", item_"'s ProviderConfig names its entry: "_config)
			Do $$$AssertEquals($Get($$$ConfigSetting(item, "Adapter", "ProviderConfig")), config, item_" applies its ProviderConfig")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).SeedModels(..#PRODUCTION), "the rows are seeded where a failed run left none")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).SeedEfforts(..#PRODUCTION), "and so are the Effort rows")
	Set position = 0
	While $ListNext(runners, position, item) {
		Set id = ..#PRODUCTION_"||"_item_"||*||Model"
		Do $$$AssertTrue(##class(Ens.Config.DefaultSettings).%ExistsId(id) && (##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue = ..#DEFAULTMODEL), "the Model row of "_item_" holds "_..#DEFAULTMODEL_" again")
		If effort(item) = "" Continue
		Set id = ..#PRODUCTION_"||"_item_"||*||Effort"
		Do $$$AssertTrue(##class(Ens.Config.DefaultSettings).%ExistsId(id) && (##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue = effort(item)), "the Effort row of "_item_" holds "_effort(item)_" again")
	}
}

/// The three runners resolve the default model through their rows, and no runner is unresolved.
Method TestRunnersResolve()
{
	If '..Running() Quit
	Set runners = $ListFromString(..#RUNNERS)
	Set position = 0
	While $ListNext(runners, position, item) {
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(item, ..#PRODUCTION), ..#DEFAULTMODEL, item_" resolves "_..#DEFAULTMODEL)
		Set id = ..#PRODUCTION_"||"_item_"||*||Model"
		Do $$$AssertTrue(##class(Ens.Config.DefaultSettings).%ExistsId(id), item_" has a Model row")
		If ##class(Ens.Config.DefaultSettings).%ExistsId(id) {
			Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue, ..#DEFAULTMODEL, item_"'s Model row holds "_..#DEFAULTMODEL)
		}
	}
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("ZzNoSuchRunner", ..#PRODUCTION), "", "an unknown item resolves nothing")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).UnresolvedRunners(..#PRODUCTION), "", "the step's own check names no unresolved runner")
	Do $$$AssertTrue(##class(OcuTalon.Install.Step.Production).UnresolvedRunners("ZzNoSuchProduction.Production") '= "", "a production whose definition cannot be opened is not reported as resolved")
}

/// One change of DiagnosisAgent's Model row, and a restart of that item, make it resolve and apply the other model.
Method TestModelChange()
{
	If '..Running() Quit
	Set item = ..#CHANGED
	Set id = ..#PRODUCTION_"||"_item_"||*||Model"
	Set name = ..#PRODUCTION_"||"_item
	Set found = ##class(Ens.Config.DefaultSettings).%ExistsId(id)
	Do $$$AssertTrue(found, "the Model row of "_item_" exists before the change")
	If 'found Quit
	Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
	Set previous = row.SettingValue
	Set description = row.Description
	Try {
		Do $$$AssertEquals(previous, ..#DEFAULTMODEL, "the row holds "_..#DEFAULTMODEL_" before the change")
		Set row.SettingValue = ..#OTHERMODEL
		Do $$$AssertStatusOK(row.%Save(), "the row is changed to "_..#OTHERMODEL)
		Do ..Restart(name)
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(item, ..#PRODUCTION), ..#OTHERMODEL, "ResolveModel gives "_..#OTHERMODEL)
		Do $$$AssertEquals($Get($$$ConfigSetting(item, "Adapter", "Model")), ..#OTHERMODEL, "the item applies "_..#OTHERMODEL)
		Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).NotRunning(), "", "every item of the production runs, so the job of "_item_" is alive")
		Do ..AssertRequestUses(..#OTHERMODEL)
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the change runs without an exception")
	}
	Set row = ##class(Ens.Config.DefaultSettings).%OpenId(id)
	If $IsObject(row) {
		Set row.SettingValue = previous
		Set row.Description = description
		Do $$$AssertStatusOK(row.%Save(), "the row is put back")
	}
	Do ..Restart(name)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(item, ..#PRODUCTION), previous, "ResolveModel gives "_previous_" again")
	Do $$$AssertEquals($Get($$$ConfigSetting(item, "Adapter", "Model")), previous, "the item applies "_previous_" again")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).NotRunning(), "", "every item runs again")
}

/// --- helpers ---
/// 1 when OcuTalon.Production runs. Otherwise the test fails with the reason, and quits.
Method Running() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).RunningReason()
	If reason = "" Quit 1
	Do $$$AssertTrue(0, reason)
	Quit 0
}

/// Stops the item temporarily and starts it again, each through the director, and waits until every item runs.
Method Restart(name As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Restart(name), "the item "_name_" is stopped and started again")
}

/// Points the keys of the runners at the CI mock key variable, sends one diagnose Request to the changed runner, and asserts what
/// the mock logged for it: the model, the cap and the effort of the runner. The keys are put back, also when an assertion fails.
Method AssertRequestUses(model As %String) [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).GuardReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Try {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).PointKeys(), "the entries of the runners are pointed at the CI mock key variable")
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Ask(..#CHANGED, "diagnose", "user", "Why did the messages of the Orders production fail?", .reply, .requests)
		Do $$$AssertStatusOK(sc, "the diagnose Request to "_..#CHANGED_" is answered")
		Do $$$AssertTrue($IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply"), "with a Reply")
		Do $$$AssertTrue(requests.%Size() > 0, "the mock's log holds the requests of the Request: "_requests.%Size())
		Set iterator = requests.%GetIterator()
		While iterator.%GetNext(.position, .logged) {
			Do $$$AssertEquals(logged.model, model, "request "_(position + 1)_" names "_model)
			Do $$$AssertEquals(logged.maxTokens, 8000, "request "_(position + 1)_" has a cap of 8000")
			Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Effort(logged), "high", "request "_(position + 1)_" asks for the effort high")
			Do $$$AssertEquals(logged.status, 200, "request "_(position + 1)_" is accepted")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the request runs without an exception")
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys(), "the entries of the runners are put back")
}

}
