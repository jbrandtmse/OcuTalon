/// Test of OcuTalon.Core.SettingsOps.RestartRunners over the running OcuTalon.Production (Story 35.2; AD-21). THROWAWAY STACKS AND CI ONLY
/// (InProduction). TestEveryRunnerRestarts records the alive jobs of every runner item (Install.Step.Production.Runners), restarts them,
/// and asserts that the call answers OK, that every item that had a job has one that is not in its old set, and that the production
/// still runs under its own name.
Class OcuTalon.Test.Core.RestartRunners Extends OcuTalon.Test.Core.InProduction
{

/// Every runner item with a job gets a new job, and the production keeps running.
Method TestEveryRunnerRestarts()
{
	If '..Guard() Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).Runners(..#PRODUCTION, .runners), "the runner items are listed")
	Do $$$AssertTrue(runners > 0, "the production has runner items")
	Kill old
	Set withJobs = 0
	For i = 1:1:runners {
		Set item = $List(runners(i), 1)
		Set old(item) = ..Jobs(item)
		If old(item) '= "" Set withJobs = withJobs + 1
	}
	Do $$$AssertTrue(withJobs > 0, "at least one runner item has a job before: "_withJobs)
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SettingsOps).RestartRunners(), "RestartRunners answers OK")
	For i = 1:1:runners {
		Set item = $List(runners(i), 1)
		If old(item) = "" Continue
		Set fresh = 0
		Set now = ..Jobs(item)
		Set position = 0
		While $ListNext(now, position, job) {
			If '$ListFind(old(item), job) Set fresh = 1
		}
		Do $$$AssertEquals(fresh, 1, item_" has a new job")
	}
	Do $$$AssertTrue(##class(Ens.Director).IsProductionRunning(.name), "the production still runs")
	Do $$$AssertEquals(name, ..#PRODUCTION, "under the same name")
}

/// The alive jobs of the item that are not in error, as a list of job ids ("" for none).
ClassMethod Jobs(item As %String) As %List [ Private ]
{
	Set jobs = ""
	Set result = ##class(%ResultSet).%New("Ens.Job:Enumerate")
	If $$$ISERR(result.Execute()) Quit jobs
	While result.Next() {
		If (result.Get("ConfigName") '= item) || (result.Get("State") '= "Alive") Continue
		If $ListFind($ListBuild("error", "halted", "terminated"), result.Get("Status")) Continue
		Set jobs = jobs _ $ListBuild(result.Get("Job"))
	}
	Quit jobs
}

}
