Include Ensemble

/// Tests of the runners' models in a production that the Production step started (Story 1.1; AD-7, AD-19). THIS CLASS RUNS IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the Model rows that the Production step seeded at the start, and it
/// restarts one runner item of the running production. Where the production does not run, the tests fail with that reason.
///   - TestAppliedAtStart: the running items of the three runners apply claude-haiku-5-5 as the Production step started them,
///     so the step seeded the rows before it started the production;
///   - TestRunnersResolve: the three runners resolve claude-haiku-5-5, an unknown item resolves nothing, each runner has a
///     Model row with claude-haiku-5-5, and the step's own check, Production.UnresolvedRunners, names no runner;
///   - TestModelChange: one change of DiagnosisAgent's Model row to claude-sonnet-5-5 and a restart of that item make both
///     ResolveModel and the runtime setting of the item sonnet, with the item's job alive; the row is then put back, the item
///     restarted again, and both read claude-haiku-5-5.
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

/// The longest to wait for the item to run again, in seconds.
Parameter WAITSECONDS = 30;

/// The running items apply the default model as the step started them: the step seeded the rows before it started the
/// production, so no update of the production was needed. The name of this test sorts before TestModelChange, whose update
/// of the production would refresh every item; run after it, the test still passes.
Method TestAppliedAtStart()
{
	If '..Running() Quit
	Set runners = $ListFromString(..#RUNNERS)
	Set position = 0
	While $ListNext(runners, position, item) {
		Do $$$AssertEquals($Get($$$ConfigSetting(item, "Adapter", "Model")), ..#DEFAULTMODEL, item_" applies "_..#DEFAULTMODEL_" as started")
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
	If ##class(Ens.Director).IsProductionRunning(.running), running = ..#PRODUCTION Quit 1
	Do $$$AssertTrue(0, ..#PRODUCTION_" does not run: this class runs in throwaways and CI only, after the Production step has started it (Rule 21)")
	Quit 0
}

/// Stops the item temporarily and starts it again, each through the director, and waits until every item runs.
Method Restart(name As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(Ens.Director).TempStopConfigItem(name, 1), "the item "_name_" is stopped")
	Do $$$AssertStatusOK(##class(Ens.Director).TempStopConfigItem(name, 0), "and started again")
	Set deadline = $ZHorolog + ..#WAITSECONDS
	While (##class(OcuTalon.Install.Step.Production).NotRunning() '= "") && ($ZHorolog < deadline) {
		Hang 1
	}
}

}
