/// Tests of the installer-step registry with a fixture area (AD-23, AD-24, AD-27, AD-29): discovery, the Roles,
/// Tasks and Reconcile steps, the purge task, and the roles that the Roles step composes (Story 3.1). The fixture area, a role, a task
/// and the resource ZzOcuTalonGrantProbe are created in OnBeforeAllTests and removed in OnAfterAllTests, with the fixture's ^OcuTalonTest
/// nodes. The Roles step rebuilds the real roles, so OnBeforeAllTests saves the resources of the trace role and OnAfterAllTests puts them
/// back, together with the other security objects that the tests made (a service user, the roles that did not exist). The two steps
/// compile first (DependsOn), because the parameters below are read from them when this class compiles.
Class OcuTalon.Test.Install.Registry Extends %UnitTest.TestCase [ DependsOn = (OcuTalon.Install.Step.Users, OcuTalon.Install.Step.Web) ]
{

/// The trace role, the service user and the service role, from the steps that own them.
Parameter TRACEROLE = {##class(OcuTalon.Install.Step.Web).#TRACEROLE};

Parameter SERVICEUSER = {##class(OcuTalon.Install.Step.Users).#SERVICEUSER};

Parameter SERVICEROLE = {##class(OcuTalon.Install.Step.Users).#SERVICEROLE};

/// The resource that the grant tests make: public permission 0, so that a role is the only way to hold it.
Parameter PROBE = "ZzOcuTalonGrantProbe";

/// The committed fixture toolset whose tools declare the probe.
Parameter GRANTTOOLSET = "OcuTalon.Test.Install.ZzGrantToolset";

/// The fixture's number: the area is OcuTalon.Install.Step.ZzFixture<n>.
Property Number As %Integer;

Property Area As %String;

Property Abstract As %String;

Property Outside As %String;

/// The failing fixture area. Its name sorts before the healthy fixture's, so that the healthy one runs
/// after a failure.
Property BadArea As %String;

Property Role As %String;

Property TaskName As %String;

/// The probe: a subclass of the registry whose Order() is read from ^OcuTalonTest, so that Run() can be
/// observed over fixture steps.
Property Probe As %String;

/// The names of the OcuTalon roles that exist before any test runs: TestRolesStep runs the real Roles step,
/// which creates the real roles, and deletes the ones that were not here.
Property RolesBefore As %List;

/// The resources of the trace role before any test runs, or "<none>" when it did not exist.
Property TraceResources As %String;

/// 1 when the service user existed before any test ran.
Property ServiceUserBefore As %Boolean;

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..RolesBefore = ..OcuTalonRoles()
	Set ..TraceResources = ..ReadRole(..#TRACEROLE)
	Set ..ServiceUserBefore = ..UserExists(..#SERVICEUSER)
	Set ..Number = $Increment(^OcuTalonTest("Registry", "n"))
	Set ..Area = "OcuTalon.Install.Step.ZzFixture"_..Number
	Set ..Abstract = ..Area_"Abstract"
	Set ..Outside = "OcuTalon.Test.Install.ZzOutside"_..Number
	Set ..BadArea = "OcuTalon.Install.Step.ZzBad"_..Number
	Set ..Role = "OcuTalonZzFixture"_..Number
	Set ..TaskName = "OcuTalonZzFixture"_..Number
	Set ..Probe = "OcuTalon.Test.Install.ZzRegistryProbe"_..Number
	Set sc = ..CreateProbe()
	If $$$ISOK(sc) Set sc = ..Create("FixtureArea", ..Area, ..Number)
	If $$$ISOK(sc) Set sc = ..Create("FixtureAbstract", ..Abstract, ..Number)
	If $$$ISOK(sc) Set sc = ..Create("FixtureOutside", ..Outside, ..Number)
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Do ..RemoveRoles()
	Do ..RemoveTask(..TaskName)
	Do ..Clean()
	Do ##class(OcuTalon.Install.Step.Roles).Run()
	Do ..WriteRole(..#TRACEROLE, ..TraceResources)
	If '..ServiceUserBefore Do ..RemoveUser(..#SERVICEUSER)
	Do ..RemoveNewRoles()
	Do ..RemoveProbe()
	Quit $SYSTEM.Status.OK()
}

/// Discovery: the fixture is an area; the abstract subclass, the subclass outside the package and the
/// base class are not; the list is sorted.
Method TestAreas()
{
	Set areas = ##class(OcuTalon.Install.Registry).Areas()
	Do $$$AssertTrue($ListFind(areas, ..Area) > 0, "the fixture is discovered")
	Do $$$AssertTrue($ListFind(areas, ..Abstract) = 0, "the abstract subclass is not")
	Do $$$AssertTrue($ListFind(areas, ..Outside) = 0, "a subclass outside OcuTalon.Install.Step is not")
	Do $$$AssertTrue($ListFind(areas, "OcuTalon.Install.Step") = 0, "the base class is not")
	Do $$$AssertTrue($ListFind(areas, "OcuTalon.Install.Step.Roles") > 0, "a built-in step is an area")
	Set previous = ""
	Set sorted = 1
	Set position = 0
	While $ListNext(areas, position, area) {
		If previous ]] area Set sorted = 0
		Set previous = area
	}
	Do $$$AssertTrue(sorted, "the areas are sorted by name")
}

/// The order is the fixed list of 15 steps of AD-23, written out here, and every step in it exists.
Method TestOrder()
{
	Set order = ##class(OcuTalon.Install.Registry).Order()
	Do $$$AssertEquals($ListToString(order, ","), "Bridge.Installer,Public,Roles,Users,Web,SSL,Tasks,Demo,Provider,Audit,Telegram,Production,Reconcile,PrivateData,Ready", "the order of AD-23")
	Do $$$AssertEquals($ListLength(order), 15, "fifteen steps")
	Do $$$AssertEquals($ListGet(order, 1), "Bridge.Installer", "the bridge installer is first")
	Do $$$AssertEquals($ListGet(order, 15), "Ready", "readiness is last")
	Set position = 0
	While $ListNext(order, position, name) {
		If name = "Bridge.Installer" {
			Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId("OcuTalon.Bridge.Installer"), name_" exists")
		} ElseIf name = "Ready" {
			Do $$$AssertTrue(##class(%Dictionary.CompiledMethod).%ExistsId("OcuTalon.Install.Step.Public||Ready"), "Public.Ready exists")
		} Else {
			Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId("OcuTalon.Install.Step."_name), name_" exists")
		}
	}
}

/// The Roles step creates the declared role holding exactly the declared resources, the union of the
/// grants of the same role, and restores the set after a change by hand. A role declared without a
/// resource exists and holds none.
Method TestRolesStep()
{
	Do ..RemoveRoles()
	Do $$$AssertEquals(..RoleResources(..Role), "<none>", "no fixture role to begin with")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs")
	Do $$$AssertEquals(..Sorted(..RoleResources(..Role)), "%DB_USER:RW,%Ens_Portal:U", "the role holds exactly the declared resources")
	Do $$$AssertEquals(..RoleResources(..Role_"Alone"), "", "the role declared alone holds nothing")

	Do ..SetRoleResources(..Role, "%DB_USER:RW,%Ens_Portal:U,%Service_Terminal:U")
	Do $$$AssertEquals(..Sorted(..RoleResources(..Role)), "%DB_USER:RW,%Ens_Portal:U,%Service_Terminal:U", "an extra grant was added by hand")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs again")
	Do $$$AssertEquals(..Sorted(..RoleResources(..Role)), "%DB_USER:RW,%Ens_Portal:U", "the role is back to exactly the declared set")
	Do ..RemoveNewRoles()
}

/// A role name that does not start with OcuTalon fails the step, which names the area, and changes nothing.
/// The refused area sorts after the fixture, so the fixture's role is composed before the refusal and must not
/// be applied.
Method TestRoleNameRefused()
{
	Do ..RemoveRoles()
	Set bad = "OcuTalon.Install.Step.ZzzBad"_..Number
	Do ..Create("FixtureBad", bad, ..Number, "ZzNotOcuTalon", "OcuTalonZzFixture"_..Number_"Bad")
	Set sc = ##class(OcuTalon.Install.Step.Roles).Run()
	Do ..Delete(bad)
	Do $$$AssertStatusNotOK(sc, "the Roles step fails")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ bad, "the error names the area")
	Do $$$AssertEquals(..RoleResources(..Role), "<none>", "no role was created")
}

/// The Tasks step creates the declared task once, with the declared schedule and settings, and a second run
/// leaves a changed schedule and setting alone. The purge task passes its DaysToKeep to the area's Purge.
Method TestTasksStep()
{
	Do ..RemoveTask(..TaskName)
	Do $$$AssertEquals(..TaskCount(..TaskName), 0, "no fixture task to begin with")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Tasks).Run(), "the Tasks step runs")
	Do $$$AssertEquals(..TaskCount(..TaskName), 1, "the task exists once")
	Set task = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(..TaskName))
	Do $$$AssertEquals(task.TaskClass, "OcuTalon.Install.Task.Purge", "the task class")
	Do $$$AssertEquals(task.NameSpace, $Namespace, "the task runs in this namespace")
	Do $$$AssertEquals(task.Description, "Fixture task", "the description")
	Do $$$AssertEquals(task.Suspended, 1, "the task is suspended")
	Do $$$AssertEquals(task.TimePeriod, 0, "daily")
	Do $$$AssertEquals(task.DailyFrequency, 0, "once a day")
	Do $$$AssertEquals(task.DailyStartTime, 10800, "at 03:00")
	Do $$$AssertEquals(..DaysToKeep(task), 17, "DaysToKeep as declared")

	Set task.DailyStartTime = 7200
	Set task.Settings = $ListBuild("DaysToKeep", 33)
	Do $$$AssertStatusOK(task.%Save(), "the task is changed by hand")
	Kill task
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Tasks).Run(), "the Tasks step runs again")
	Do $$$AssertEquals(..TaskCount(..TaskName), 1, "the task still exists once")
	Set task = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(..TaskName))
	Do $$$AssertEquals(task.DailyStartTime, 7200, "the changed start time is kept")
	Do $$$AssertEquals(..DaysToKeep(task), 33, "the changed DaysToKeep is kept")

	Kill ^OcuTalonTest("Registry", ..Number, "purge")
	Set definition = ##class(OcuTalon.Install.Task.Purge).%New()
	Do $$$AssertStatusOK(definition.SetSettings(task.Settings), "the task's settings are applied")
	Do $$$AssertEquals(definition.DaysToKeep, 33, "the purge task reads its DaysToKeep")
	Do $$$AssertStatusOK(definition.OnTask(), "the purge task runs")
	Do $$$AssertEquals($Get(^OcuTalonTest("Registry", ..Number, "purge")), 33, "the area's Purge received the task's DaysToKeep")
}

/// A task name that does not start with OcuTalon, or that another area declares, fails the step, which names
/// the area and creates nothing.
Method TestTaskNamesRefused()
{
	Do ..RemoveTask(..TaskName)
	Set bad = ..BadArea
	For taskName = "ZzNotOcuTalon", ..TaskName {
		Do ..Create("FixtureBad", bad, ..Number, "OcuTalonZzFixture"_..Number_"Bad", taskName)
		Set sc = ##class(OcuTalon.Install.Step.Tasks).Run()
		Do ..Delete(bad)
		Do $$$AssertStatusNotOK(sc, "the Tasks step fails for the name "_taskName)
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ bad, "the error names the area")
		Do $$$AssertEquals(..TaskCount(..TaskName), 0, "no task was created")
	}
}

/// The Reconcile step calls the Reconcile of the area once per run, and an area that throws fails it by name
/// after every other area ran.
Method TestReconcileStep()
{
	Kill ^OcuTalonTest("Registry", ..Number, "reconcile")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Reconcile).Run(), "the Reconcile step runs")
	Do $$$AssertEquals($Get(^OcuTalonTest("Registry", ..Number, "reconcile")), 1, "the area was reconciled once")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Reconcile).Run(), "the Reconcile step runs again")
	Do $$$AssertEquals($Get(^OcuTalonTest("Registry", ..Number, "reconcile")), 2, "and once more")

	Set bad = ..BadArea
	Do ..Create("FixtureBad", bad, ..Number, "OcuTalonZzFixture"_..Number_"Bad", "OcuTalonZzFixture"_..Number_"Bad")
	Set sc = ##class(OcuTalon.Install.Step.Reconcile).Run()
	Do ..Delete(bad)
	Do $$$AssertStatusNotOK(sc, "an area that throws fails the step")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ bad, "the error names the area")
	Do $$$AssertEquals($Get(^OcuTalonTest("Registry", ..Number, "reconcile")), 3, "the other areas still ran")
}

/// Purge calls the Purge of every area with the number of days, and combines the failures by area.
Method TestPurge()
{
	Kill ^OcuTalonTest("Registry", ..Number, "purge")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Registry).Purge(21), "Purge")
	Do $$$AssertEquals($Get(^OcuTalonTest("Registry", ..Number, "purge")), 21, "the area received the days")

	Set bad = ..BadArea
	Do ..Create("FixtureBad", bad, ..Number, "OcuTalonZzFixture"_..Number_"Bad", "OcuTalonZzFixture"_..Number_"Bad")
	Set sc = ##class(OcuTalon.Install.Registry).Purge(8)
	Do ..Delete(bad)
	Do $$$AssertStatusNotOK(sc, "a failing area fails Purge")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ bad, "the error names the area")
	Do $$$AssertEquals($Get(^OcuTalonTest("Registry", ..Number, "purge")), 8, "the other areas still ran")
}

/// The step contract does nothing by default: an area overrides only what it declares.
Method TestStepDefaults()
{
	Set step = "OcuTalon.Install.Step"
	Do $$$AssertEquals(##class(%Dictionary.CompiledClass).%OpenId(step).Abstract, 1, "the contract is abstract")
	Do $$$AssertStatusOK($ClassMethod(step, "Run"), "Run succeeds")
	Do $$$AssertStatusOK($ClassMethod(step, "Reconcile"), "Reconcile succeeds")
	Do $$$AssertStatusOK($ClassMethod(step, "Purge", 30), "Purge succeeds")
	Set grants = $ClassMethod(step, "Grants")
	Do $$$AssertTrue($IsObject(grants) && grants.%IsA("%Library.DynamicArray"), "Grants is a dynamic array")
	Do $$$AssertEquals(grants.%Size(), 0, "Grants declares nothing")
	Set tasks = $ClassMethod(step, "Tasks")
	Do $$$AssertTrue($IsObject(tasks) && tasks.%IsA("%Library.DynamicArray"), "Tasks is a dynamic array")
	Do $$$AssertEquals(tasks.%Size(), 0, "Tasks declares nothing")
	Do $ClassMethod(step, "TakeWarnings")
	Do $$$AssertEquals($ClassMethod(step, "TakeWarnings"), "", "TakeWarnings returns nothing when nothing was recorded")
	Do $ClassMethod(step, "Warn", "a")
	Do $ClassMethod(step, "Warn", "b"_$Char(13, 10)_"c")
	Do $$$AssertEquals($ClassMethod(step, "TakeWarnings"), $ListBuild("a", "b  c"), "TakeWarnings returns the warnings in order, with each CR and LF a space")
	Do $$$AssertEquals($ClassMethod(step, "TakeWarnings"), "", "TakeWarnings clears them")
}

/// The purge task: its name, and 90 days to keep unless the task says otherwise, which it passes to the areas.
Method TestPurgeTaskDefaults()
{
	Set purge = "OcuTalon.Install.Task.Purge"
	Do $$$AssertEquals($Parameter(purge, "TaskName"), "OcuTalon purge", "the task's name")
	Do $$$AssertTrue($ClassMethod(purge, "%Extends", "%SYS.Task.Definition"), "a task definition")
	Kill ^OcuTalonTest("Registry", ..Number, "purge")
	Set definition = $ClassMethod(purge, "%New")
	Do $$$AssertEquals(definition.DaysToKeep, 90, "DaysToKeep is 90 by default")
	Do $$$AssertStatusOK(definition.OnTask(), "the purge task runs with its default")
	Do $$$AssertEquals($Get(^OcuTalonTest("Registry", ..Number, "purge")), 90, "the areas received 90 days")
}

/// Run() writes one line per step and stops at the first step that fails or throws, and returns that failure. A step's
/// warnings follow its line, one WARN line each, whether the step succeeded or failed. It is run over fixture steps by a
/// subclass of the registry whose Order() names them.
Method TestRun()
{
	Set number = ..Number
	Set ok = "ZzRunOk"_number
	Set fail = "ZzRunFail"_number
	Set throw = "ZzRunThrow"_number
	Set last = "ZzRunLast"_number
	Set warn = "ZzRunWarn"_number
	Set prefix = "OcuTalon.Install.Step."
	Set okBody = "Quit $SYSTEM.Status.OK()"
	Set sc = ..Create("FixtureRunStep", prefix_ok, number, , , okBody)
	If $$$ISOK(sc) Set sc = ..Create("FixtureRunStep", prefix_fail, number, , , "Quit $SYSTEM.Status.Error(5001, ""Step failed on purpose"")")
	If $$$ISOK(sc) Set sc = ..Create("FixtureRunStep", prefix_throw, number, , , "Throw ##class(%Exception.General).%New(""Step threw"", 5001, , ""Step threw on purpose"")")
	If $$$ISOK(sc) Set sc = ..Create("FixtureRunStep", prefix_last, number, , , okBody)
	If $$$ISOK(sc) Set sc = ..Create("FixtureRunStep", prefix_warn, number, , , "Do ..Warn(""Fixture warning "_number_""") Quit $Select($Get(^OcuTalonTest(""Registry"", "_number_", ""warnFails"")): $SYSTEM.Status.Error(5001, ""Warn step failed on purpose""), 1: $SYSTEM.Status.OK())")
	If $$$ISOK(sc) Set sc = ..Create("FixtureProbe", ..Probe, number)
	Do $$$AssertStatusOK(sc, "the fixture steps and the probe compile")
	If $$$ISERR(sc) Quit

	Kill ^OcuTalonTest("Registry", number, "run")
	Set text = ..RunProbe($ListBuild(ok, fail, last), .sc)
	Do $$$AssertStatusNotOK(sc, "a failing step fails the run")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "Step failed on purpose", "the run returns the step's failure")
	Set line = ..Line(text, "STEP "_ok_" OK ")
	Set seconds = $Piece(line, " ", 4)
	Do $$$AssertTrue(($Piece(line, " ", 1, 3) = ("STEP "_ok_" OK")) && ($Extract(seconds, $Length(seconds)) = "s") && $IsValidNum($Extract(seconds, 1, $Length(seconds) - 1)), "the step before is reported OK with its time: "_line)
	Do $$$AssertTrue(..Line(text, "STEP "_fail_" FAILED ") [ "Step failed on purpose", "the failing step is reported FAILED with its text")
	Do $$$AssertTrue($Find(text, "STEP "_ok_" ") < $Find(text, "STEP "_fail_" "), "the lines come in the order of the steps")
	Do $$$AssertTrue(text '[ last, "the step after the failure has no line")
	Do $$$AssertEquals($Get(^OcuTalonTest("Registry", number, "run", prefix_ok)), 1, "the step before ran once")
	Do $$$AssertEquals($Get(^OcuTalonTest("Registry", number, "run", prefix_fail)), 1, "the failing step ran once")
	Do $$$AssertEquals($Get(^OcuTalonTest("Registry", number, "run", prefix_last)), "", "the step after the failure did not run")

	Kill ^OcuTalonTest("Registry", number, "run")
	Set text = ..RunProbe($ListBuild(ok, throw, last), .sc)
	Do $$$AssertStatusNotOK(sc, "a step that throws fails the run")
	Do $$$AssertTrue(..Line(text, "STEP "_throw_" FAILED ") [ "Step threw", "the throwing step is reported FAILED with its text")
	Do $$$AssertTrue(text '[ last, "the step after the exception has no line")
	Do $$$AssertEquals($Get(^OcuTalonTest("Registry", number, "run", prefix_last)), "", "the step after the exception did not run")

	Kill ^OcuTalonTest("Registry", number, "run")
	Do ##class(OcuTalon.Install.Step).Warn("Stale warning "_number)
	Set text = ..RunProbe($ListBuild(ok, last), .sc)
	Do $$$AssertStatusOK(sc, "steps that succeed give a successful run")
	Do $$$AssertTrue(text '[ "Stale warning", "a warning recorded before the run belongs to no step and is discarded")
	Do $$$AssertTrue(text '[ "FAILED", "no step is reported FAILED")
	Do $$$AssertTrue(($Find(text, "STEP "_ok_" OK ") > 0) && ($Find(text, "STEP "_ok_" OK ") < $Find(text, "STEP "_last_" OK ")), "both steps are reported OK, in order")
	Do $$$AssertEquals($Get(^OcuTalonTest("Registry", number, "run", prefix_ok)), 1, "the first step ran once")
	Do $$$AssertEquals($Get(^OcuTalonTest("Registry", number, "run", prefix_last)), 1, "the last step ran once")

	Kill ^OcuTalonTest("Registry", number, "run")
	Set text = ..RunProbe($ListBuild(warn, last), .sc)
	Do $$$AssertStatusOK(sc, "a step that warns and succeeds gives a successful run")
	Set okLine = ..Line(text, "STEP "_warn_" OK ")
	Do $$$AssertTrue(okLine '= "", "the step that warns is reported OK: "_okLine)
	Do $$$AssertTrue($Find(text, okLine_$Char(10)_"WARN "_warn_" Fixture warning "_number_$Char(10)_"STEP "_last_" OK ") > 0, "the WARN line is the next line after the step's line, and the step after follows it")
	Do $$$AssertEquals($Length(text, "WARN "), 2, "only the step that warns has a WARN line")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step).TakeWarnings(), "", "the registry took the warnings")

	Kill ^OcuTalonTest("Registry", number, "run")
	Set ^OcuTalonTest("Registry", number, "warnFails") = 1
	Set text = ..RunProbe($ListBuild(warn, last), .sc)
	Kill ^OcuTalonTest("Registry", number, "warnFails")
	Do $$$AssertStatusNotOK(sc, "a failing step that warned fails the run")
	Set failedLine = ..Line(text, "STEP "_warn_" FAILED ")
	Do $$$AssertTrue(failedLine [ "Warn step failed on purpose", "the failing step is reported FAILED: "_failedLine)
	Do $$$AssertTrue($Find(text, failedLine_$Char(10)_"WARN "_warn_" Fixture warning "_number) > 0, "the failing step's WARN line follows its FAILED line")
	Do $$$AssertTrue(text '[ last, "the step after the failure has no line")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step).TakeWarnings(), "", "the registry took the warnings of the failing step")

	Do ..Delete(..Probe)
	For name = ok, fail, throw, last, warn {
		Do ..Delete(prefix_name)
	}
}

/// Matrix row 3 (integration): the resources that the tools of a toolset declare reach the service user. A fixture area returns
/// Tools.GrantsOf of the fixture toolset (alpha: U; beta: R from its class; gamma: none), so after the Roles step the service role holds
/// ZzOcuTalonGrantProbe:RU, and CheckUserPermission, the exact call that the gate makes, says 1 for U and for R and 0 for W, one letter per
/// call. When the area is gone, the next run takes the grant away.
Method TestToolResourcesReachTheServiceUser()
{
	Set role = ..#SERVICEROLE
	Set service = ..#SERVICEUSER
	Set area = "OcuTalon.Install.Step.ZzTools"_..Number
	Do $$$AssertStatusOK(..Create("FixtureToolsArea", area, ..Number, , , ..#GRANTTOOLSET), "the fixture area compiles")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs")
	Do $$$AssertEquals(..Permissions(role, ..#PROBE), "RU", "the service role holds R and U on the probe")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Users).EnsureService(), "the service user holds the service role")
	Do $$$AssertEquals(..Allowed(service, ..#PROBE, "U"), 1, "the service user may use the probe")
	Do $$$AssertEquals(..Allowed(service, ..#PROBE, "R"), 1, "and read it")
	Do $$$AssertEquals(..Allowed(service, ..#PROBE, "W"), 0, "and not write it")

	Do ..Delete(area)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs without the area")
	Do $$$AssertEquals(..Permissions(role, ..#PROBE), "", "the service role no longer holds the probe")
	Do $$$AssertEquals(..Allowed(service, ..#PROBE, "U"), 0, "and the service user may not use it")
	Do $$$AssertEquals(..Allowed(service, ..#PROBE, "R"), 0, "or read it")
}

/// The Tools area as the installer finds it (rows 3 and 4 reach the service user through a fixture area): a toolset of the package
/// OcuTalon.Tools, made here and deleted again, whose tool declares the probe resource. Toolsets lists it, Grants holds its pair for the
/// service role, and the Roles step gives the pair to the role; with the two classes gone, the next run takes it away.
Method TestToolsAreaFindsABuiltInToolset()
{
	Set area = "OcuTalon.Install.Step.Tools"
	Set tool = "OcuTalon.Tools.ZzProbe"_..Number_"Tool"
	Set toolset = "OcuTalon.Tools.ZzProbe"_..Number
	Set sc = ..Create("FixtureProbeTool", tool, ..Number)
	If $$$ISOK(sc) Set sc = ..Create("FixtureBadToolset", toolset, ..Number, , , tool)
	Do $$$AssertStatusOK(sc, "the fixture tool and toolset compile")
	If $$$ISERR(sc) {
		Do ..Delete(toolset)
		Do ..Delete(tool)
		Quit
	}
	Do $$$AssertTrue($ListFind($ClassMethod(area, "Toolsets"), toolset) > 0, "Toolsets lists the toolset")
	Set found = 0
	Set iterator = $ClassMethod(area, "Grants").%GetIterator()
	While iterator.%GetNext(, .grant) {
		If (grant.role = ..#SERVICEROLE) && (grant.resource = ..#PROBE) && (grant.permission = "U") Set found = 1
	}
	Do $$$AssertTrue(found, "Grants holds the pair of its tool for the service role")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs")
	Do $$$AssertEquals(..Permissions(..#SERVICEROLE, ..#PROBE), "U", "the service role holds the probe")
	Do ..Delete(toolset)
	Do ..Delete(tool)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs without them")
	Do $$$AssertEquals(..Permissions(..#SERVICEROLE, ..#PROBE), "", "and the service role no longer holds the probe")
}

/// Matrix row 4: a tool whose RESOURCES is malformed makes GrantsOf throw, naming the class and the tool, and the Roles step fail, naming the
/// area, with no role changed. The tool class, its toolset and the area are made here and deleted again.
Method TestMalformedResourcesFailTheStep()
{
	Set tool = "OcuTalon.Test.Install.ZzBadTool"_..Number
	Set toolset = "OcuTalon.Test.Install.ZzBadToolset"_..Number
	Set area = "OcuTalon.Install.Step.ZzzBadTools"_..Number
	Set sc = ..Create("FixtureBadTool", tool, ..Number)
	If $$$ISOK(sc) Set sc = ..Create("FixtureBadToolset", toolset, ..Number, , , tool)
	If $$$ISOK(sc) Set sc = ..Create("FixtureToolsArea", area, ..Number, , , toolset)
	Do $$$AssertStatusOK(sc, "the fixture tool, toolset and area compile")
	If $$$ISERR(sc) Quit
	Set thrown = ""
	Try {
		Do ##class(OcuTalon.Install.Step.Tools).GrantsOf($ListBuild(toolset))
	} Catch exception {
		Set thrown = $SYSTEM.Status.GetErrorText(exception.AsStatus())
	}
	Do $$$AssertTrue(thrown [ tool, "GrantsOf throws, and the error names the tool class")
	Do $$$AssertTrue(thrown [ " alpha ", "and the tool")

	Do ..RemoveRoles()
	Set serviceBefore = ..ReadRole(..#SERVICEROLE)
	Set sc = ##class(OcuTalon.Install.Step.Roles).Run()
	Do ..Delete(area)
	Do ..Delete(toolset)
	Do ..Delete(tool)
	Do $$$AssertStatusNotOK(sc, "the Roles step fails")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ area, "and the error names the area")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ tool, "and the tool class")
	Do $$$AssertEquals(..RoleResources(..Role), "<none>", "no role was created")
	Do $$$AssertEquals(..ReadRole(..#SERVICEROLE), serviceBefore, "and the service role is as it was")
}

/// Matrix row 5: a declaration of a forbidden resource fails the Roles step with a status that names the area, the role and the resource,
/// whatever the case of the resource, and no role is created or changed. AD-24's seven resources are the list.
Method TestForbiddenGrantRefused()
{
	Set list = "%All,%Development,%Ens_MessageEditResend,%Ens_MessageDiscard,%Ens_ProductionRun,%Ens_ProductionConfig,%Ens_WorkflowConfig"
	Do $$$AssertEquals($Parameter("OcuTalon.Install.Step.Roles", "FORBIDDEN"), list, "the forbidden resources are AD-24's seven")
	Do ..RemoveRoles()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs and makes the fixture role")
	Set byHand = "%DB_USER:RW,%Ens_Portal:U,%Service_Terminal:U"
	Do ..SetRoleResources(..Role, byHand)
	Set bad = "OcuTalon.Install.Step.ZzzForbidden"_..Number
	Set forbiddenRole = "OcuTalonZzFixture"_..Number_"Forbidden"
	Set sc = ..Create("FixtureForbidden", bad, ..Number, forbiddenRole)
	Do $$$AssertStatusOK(sc, "the fixture area compiles")
	If $$$ISERR(sc) Quit
	Set resources = $ListFromString(list)
	Set resources = resources _ $ListBuild($ZConvert($ListGet(resources, 4), "L"), $ZConvert($ListGet(resources, 1), "U"))
	Set position = 0
	While $ListNext(resources, position, resource) {
		Set ^OcuTalonTest("Registry", ..Number, "forbidden") = resource
		Set sc = ##class(OcuTalon.Install.Step.Roles).Run()
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertStatusNotOK(sc, "the Roles step refuses "_resource)
		Do $$$AssertTrue((text [ bad) && (text [ forbiddenRole) && (text [ resource), "and the error names the area, the role and "_resource)
	}
	Do $$$AssertEquals(..RoleResources(forbiddenRole), "<none>", "the forbidden role was not created")
	Do $$$AssertEquals(..Sorted(..RoleResources(..Role)), byHand, "and no role was changed: the fixture role keeps its extra grant")
	Do ..Delete(bad)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs without the area")
	Do $$$AssertEquals(..Sorted(..RoleResources(..Role)), "%DB_USER:RW,%Ens_Portal:U", "and rebuilds the fixture role")
}

/// Matrix row 6: a role that was given a granted role and an extra resource by hand has exactly its declared resources and no granted role
/// after the next run.
Method TestHandAddedPrivilegeIsRemoved()
{
	Do ..RemoveRoles()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs and makes the fixture role")
	Do ..SetRoleResources(..Role, "%DB_USER:RW,%Ens_Portal:U,%Service_Terminal:U")
	Do ..SetRoleGranted(..Role, "%Developer")
	Do $$$AssertEquals(..RoleGranted(..Role), "%Developer", "a role was granted by hand")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs again")
	Do $$$AssertEquals(..Sorted(..RoleResources(..Role)), "%DB_USER:RW,%Ens_Portal:U", "the role has exactly its declared resources")
	Do $$$AssertEquals(..RoleGranted(..Role), "", "and no granted role")
}

/// Matrix row 7 (integration with the Demo step's composition): a trace role that holds the OCUORDERS databases is rebuilt with exactly the six
/// OCUTALON grants of AD-24. The Demo step's own composition, WithOrders (fixture grants until Story 4.1), adds exactly the two OCUORDERS
/// databases on top of them with demo mode on, and none with it off. The trace role holds no private or public database.
Method TestTraceRoleGrants()
{
	Set trace = ..#TRACEROLE
	Set demo = "OcuTalon.Install.Step.Demo"
	Set six = "%DB_OCUTALON_CODE:R,%DB_OCUTALON_DATA:R,%Ens_MessageContent:U,%Ens_MessageHeader:U,%Ens_MessageTrace:U,%Ens_Portal:U"
	Set orders = "%DB_OCUORDERS_CODE:R,%DB_OCUORDERS_DATA:R"
	Do ..WriteRole(trace, $ClassMethod(demo, "WithOrders", ..ReadRole(trace), 1))
	Do $$$AssertTrue(..ReadRole(trace) [ "%DB_OCUORDERS_DATA:R", "the trace role holds the OCUORDERS databases to begin with")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs")
	Do $$$AssertEquals(..Sorted(..ReadRole(trace)), ..Sorted(six), "the trace role holds exactly the six OCUTALON grants")
	Do $$$AssertEquals(..Sorted($ClassMethod(demo, "WithOrders", ..ReadRole(trace), 1)), ..Sorted(six_","_orders), "the Demo step's composition with demo mode on adds exactly the two OCUORDERS databases")
	Do $$$AssertEquals(..Sorted($ClassMethod(demo, "WithOrders", ..ReadRole(trace), 0)), ..Sorted(six), "and with it off adds none")
	Do $$$AssertTrue((..ReadRole(trace) '[ "%DB_OCUTALON_PRIVATE") && (..ReadRole(trace) '[ "%DB_OCUTALON_PUBLIC"), "the trace role holds neither the private nor the public database")
}

/// The trace role's SQL privileges are the Web step's and the Demo step's, and the Roles step leaves them: after a run its rows in
/// Security.SQLPrivileges are exactly SELECT on Ens.MessageHeader, in OCUTALON, and in OCUORDERS where it exists. A missing grant is made by
/// the test and removed again; nothing else is touched.
Method TestTraceRoleSql()
{
	Set trace = ..#TRACEROLE
	Set added = ""
	Set namespaces = $ListBuild("OCUTALON", "OCUORDERS")
	Set position = 0
	While $ListNext(namespaces, position, namespace) {
		If '##class(%SYS.Namespace).Exists(namespace) Continue
		If ..HoldsSelect(trace, namespace) Continue
		Do $$$AssertStatusOK(..GrantSelect(trace, namespace), "SELECT on Ens.MessageHeader is granted in "_namespace_" for the test")
		Set added = added _ $ListBuild(namespace)
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs")
	Set expected = ""
	Set sorted = $ListBuild("OCUORDERS", "OCUTALON")
	Set position = 0
	While $ListNext(sorted, position, namespace) {
		If '##class(%SYS.Namespace).Exists(namespace) Continue
		Set expected = expected _ $Select(expected = "": "", 1: ";") _ namespace_"|1,Ens.MessageHeader|s"
	}
	Do $$$AssertEquals(..SqlPrivileges(trace), expected, "the trace role's SQL privileges are exactly SELECT on Ens.MessageHeader, in each namespace of the install")
	Set position = 0
	While $ListNext(added, position, namespace) {
		Do $$$AssertStatusOK(..RevokeSelect(trace, namespace), "the test's grant in "_namespace_" is removed")
	}
}

/// Matrix rows 3 to 7 together (AC 3): after the Roles step, no OcuTalon role holds a forbidden resource or a granted role, and the trace role
/// holds no private or public database. The README account, the service user and the two public accounts (made here under fixture names) are
/// no Workflow user and no Workflow role member, in OCUTALON and in OCUORDERS, and no resource that they hold is forbidden.
Method TestEveryRole()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs")
	Set forbidden = $ListFromString($ZConvert("%All,%Development,%Ens_MessageEditResend,%Ens_MessageDiscard,%Ens_ProductionRun,%Ens_ProductionConfig,%Ens_WorkflowConfig", "U"))
	Set roles = ..OcuTalonRoles()
	Do $$$AssertTrue($ListLength(roles) >= 4, "the OcuTalon roles are there: "_$ListLength(roles))
	Set bad = ""
	Set position = 0
	While $ListNext(roles, position, role) {
		Set resources = ..ReadRole(role)
		For i = 1:1:$Length(resources, ",") {
			If $ListFind(forbidden, $ZConvert($Piece($Piece(resources, ",", i), ":", 1), "U")) Set bad = bad _ " " _ role _ " holds " _ $Piece(resources, ",", i)
		}
		If ..RoleGranted(role) '= "" Set bad = bad _ " " _ role _ " is granted " _ ..RoleGranted(role)
	}
	Do $$$AssertEquals(bad, "", "no OcuTalon role holds a forbidden resource or a granted role")
	Set traceResources = ..ReadRole(..#TRACEROLE)
	Do $$$AssertTrue((traceResources '[ "%DB_OCUTALON_PRIVATE") && (traceResources '[ "%DB_OCUTALON_PUBLIC"), "the trace role holds neither the private nor the public database")

	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Users).EnsureService(), "the service user is there")
	Set demoUser = "ZzRegistry"_..Number_"Demo"
	Set readonlyUser = "ZzRegistry"_..Number_"Ro"
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Users).EnsurePublic(demoUser, "Zz-demo-pw-1", $Parameter("OcuTalon.Install.Step.Users", "DEMOROLES")), "the demo account is made")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Users).EnsurePublic(readonlyUser, "Zz-ro-pw-1", $Parameter("OcuTalon.Install.Step.Users", "READONLYROLES")), "the read-only account is made")
	Set accounts = $ListBuild(..#SERVICEUSER, demoUser, readonlyUser)
	If ..UserExists($Parameter("OcuTalon.Install.Step.Users", "USER")) Set accounts = accounts _ $ListBuild($Parameter("OcuTalon.Install.Step.Users", "USER"))
	Set position = 0
	While $ListNext(accounts, position, account) {
		Do $$$AssertEquals(..WorkflowRows(account), 0, account_" is no Workflow user and no member of a Workflow role, in either namespace")
		Set held = ..UserResources(account)
		Set found = ""
		For i = 1:1:$Length(held, ",") {
			If $ListFind(forbidden, $ZConvert($Piece($Piece(held, ",", i), ":", 1), "U")) Set found = found _ " " _ $Piece(held, ",", i)
		}
		Do $$$AssertEquals(found, "", account_" holds no forbidden resource, the Workflow configuration included")
	}
	Do $$$AssertTrue(..UserResources(demoUser) [ "%Ens_Portal", "control: the resources of an account are read, so an empty answer is not a failed read")
	Do ..RemoveUser(demoUser)
	Do ..RemoveUser(readonlyUser)
}

/// Row 5, the other side: only AD-24's seven names are refused. Resources whose names begin like a forbidden one, and the ones that later tools
/// declare (%Ens_MessageResend, %Ens_ConfigItemRun), are composed into a role.
Method TestNearMissesAreNotForbidden()
{
	Set bad = "OcuTalon.Install.Step.ZzzNear"_..Number
	Set nearRole = "OcuTalonZzFixture"_..Number_"Near"
	Set sc = ..Create("FixtureForbidden", bad, ..Number, nearRole)
	Do $$$AssertStatusOK(sc, "the fixture area compiles")
	If $$$ISERR(sc) Quit
	Set resources = $ListBuild("%Ens_MessageResend", "%Ens_ConfigItemRun", "%Ens_ProductionDocumentation")
	Set position = 0
	While $ListNext(resources, position, resource) {
		Set ^OcuTalonTest("Registry", ..Number, "forbidden") = resource
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step accepts "_resource)
		Do $$$AssertEquals(..Permissions(nearRole, resource), "U", "and the role holds Use on "_resource)
	}
	Do ..Delete(bad)
	Do $ClassMethod(..Area, "Role", "delete", nearRole)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs without the area")
}

/// A declaration of a resource that the instance does not have fails the Roles step before any role is touched, with a status that names
/// the area, the role and the resource: the role that would hold it is not made, and a role that sorts before it keeps a grant added by hand.
Method TestUnknownResourceFailsTheStep()
{
	Set resource = "ZzOcuTalonNoSuchResource"
	Set bad = "OcuTalon.Install.Step.ZzzUnknown"_..Number
	Set unknownRole = "OcuTalonZzFixture"_..Number_"Unknown"
	Do $$$AssertNotTrue(..ResourceExists(resource), "the resource does not exist")
	Do ..RemoveRoles()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs and makes the fixture role")
	Set byHand = "%DB_USER:RW,%Ens_Portal:U,%Service_Terminal:U"
	Do ..SetRoleResources(..Role, byHand)
	Set sc = ..Create("FixtureForbidden", bad, ..Number, unknownRole)
	Do $$$AssertStatusOK(sc, "the fixture area compiles")
	If $$$ISERR(sc) Quit
	Set ^OcuTalonTest("Registry", ..Number, "forbidden") = resource
	Set sc = ##class(OcuTalon.Install.Step.Roles).Run()
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do ..Delete(bad)
	Do $$$AssertStatusNotOK(sc, "the Roles step fails")
	Do $$$AssertTrue((text [ bad) && (text [ unknownRole) && (text [ resource), "and the error names the area, the role and the resource: "_text)
	Do $$$AssertEquals(..ReadRole(unknownRole), "<none>", "and the role is not made")
	Do $$$AssertEquals(..Sorted(..RoleResources(..Role)), byHand, "and no role was changed: the fixture role, which sorts first, keeps its extra grant")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs without the area")
	Do $$$AssertEquals(..Sorted(..RoleResources(..Role)), "%DB_USER:RW,%Ens_Portal:U", "and rebuilds the fixture role")
}

/// The Tools area lists the compiled, non-abstract toolsets only: an abstract toolset of the package OcuTalon.Tools is not one, and a built-in
/// toolset still is.
Method TestToolsetsSkipAnAbstractToolset()
{
	Set toolset = "OcuTalon.Tools.ZzProbe"_..Number_"Abstract"
	Set sc = ..Create("FixtureAbstractToolset", toolset, ..Number)
	Do $$$AssertStatusOK(sc, "the abstract toolset compiles")
	If $$$ISERR(sc) Quit
	Set toolsets = $ClassMethod("OcuTalon.Install.Step.Tools", "Toolsets")
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%OpenId(toolset).Abstract, "control: the toolset is compiled and abstract")
	Do $$$AssertEquals($ListFind(toolsets, toolset), 0, "Toolsets does not list it")
	Do $$$AssertTrue($ListFind(toolsets, "OcuTalon.Tools.Reminders") > 0, "and still lists a built-in toolset")
	Do ..Delete(toolset)
}

/// The Workflow check of TestEveryRole can fail: a Workflow user is counted, in OCUTALON and in OCUORDERS, so a count of 0 for an account is
/// a finding about the account and not a blind spot of the query. The fixture Workflow user is removed again (and by Clean).
Method TestWorkflowCheckCountsAWorkflowUser()
{
	Set name = "ZzRegistry"_..Number_"Wf"
	Do $$$AssertTrue(##class(%SYS.Namespace).Exists("OCUORDERS"), "OCUORDERS exists on the stack")
	Do $$$AssertEquals(..WorkflowRows(name), 0, "no row for a name that is no Workflow user")
	New $Namespace
	Set home = $Namespace
	For namespace = home, "OCUORDERS" {
		Set $Namespace = namespace
		Set user = ##class(EnsLib.Workflow.UserDefinition).%New()
		Set user.Name = name
		Set sc = user.%Save()
		Set $Namespace = home
		Do $$$AssertStatusOK(sc, "the fixture Workflow user is saved in "_namespace)
		Do $$$AssertEquals(..WorkflowRows(name), 1, "a Workflow user in "_namespace_" is counted")
		Set $Namespace = namespace
		Do ##class(EnsLib.Workflow.UserDefinition).%DeleteId(name)
		Set $Namespace = home
		Do $$$AssertEquals(..WorkflowRows(name), 0, "and is not counted once it is deleted from "_namespace)
	}
}

/// --- fixtures ---
/// 1 when the resource exists. Runs in %SYS.
ClassMethod ResourceExists(resource As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ''##class(Security.Resources).Exists(resource)
}

/// Deletes the fixture Workflow users, in OCUTALON and in OCUORDERS where it exists.
ClassMethod ClearWorkflow() [ Private ]
{
	New $Namespace
	Set namespaces = $ListBuild("OCUTALON", "OCUORDERS")
	Set position = 0
	While $ListNext(namespaces, position, namespace) {
		If '##class(%SYS.Namespace).Exists(namespace) Continue
		Set $Namespace = namespace
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM EnsLib_Workflow.UserDefinition WHERE Name %STARTSWITH 'ZzRegistry'")
	}
}

/// Runs Run() of the probe, whose order is the list, with its output in a temporary file. Returns the output
/// (line ends as $Char(10)) and leaves the status of the run in sc.
Method RunProbe(order As %List, Output sc As %Status) As %String [ Private ]
{
	Set ^OcuTalonTest("Registry", ..Number, "order") = order
	Set file = ##class(%File).TempFilename("txt")
	Set io = $IO
	Open file:("NWS"):5
	If '$Test {
		Set sc = $SYSTEM.Status.Error(5001, "The output file "_file_" could not be opened")
		Quit ""
	}
	Use file
	Try {
		Set sc = $ClassMethod(..Probe, "Run", "TestRun")
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Use io
	Close file
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(file)
	Set text = stream.Read(32000)
	Kill stream
	Do ##class(%File).Delete(file)
	Quit $Replace(text, $Char(13), "")
}

/// The first line of text that holds what, or "".
ClassMethod Line(text As %String, what As %String) As %String [ Private ]
{
	Set start = $Find(text, what)
	If 'start Quit ""
	Set begin = start - $Length(what)
	Set end = $Find(text, $Char(10), start)
	Quit $Extract(text, begin, $Select(end: end - 2, 1: $Length(text)))
}

/// Creates and compiles a class from an XData block of this class, with @CLASS@ replaced by the class name,
/// @N@ by the fixture's number, @ROLE@ and @TASK@ by the arguments and @BODY@ by the body.
Method Create(block As %String, className As %String, number As %Integer, role As %String = "", task As %String = "", body As %String = "") As %Status [ Private ]
{
	Set text = ##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||"_block).Data.Read(100000)
	Set text = $Replace(text, $Char(13), "")
	Set text = $Replace($Replace($Replace($Replace($Replace(text, "@CLASS@", className), "@N@", number), "@ROLE@", role), "@TASK@", task), "@BODY@", body)
	Set sc = ##class(%Compiler.UDL.TextServices).SetTextFromString($Namespace, className, text, $Char(10))
	If $$$ISOK(sc) Set sc = $SYSTEM.OBJ.Compile(className, "ck-d")
	Quit sc
}

Method Delete(className As %String) [ Private ]
{
	Do $SYSTEM.OBJ.Delete(className, "-d")
}

/// Deletes every fixture class that an earlier run may have left, and this fixture's nodes.
ClassMethod Clean() [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Do statement.%Prepare("SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'OcuTalon.Install.Step.Zz' OR Name %STARTSWITH 'OcuTalon.Test.Install.ZzOutside' OR Name %STARTSWITH 'OcuTalon.Test.Install.ZzRegistryProbe' OR Name %STARTSWITH 'OcuTalon.Test.Install.ZzBadTool' OR Name %STARTSWITH 'OcuTalon.Tools.ZzProbe'")
	Set result = statement.%Execute()
	While result.%Next() {
		Do $SYSTEM.OBJ.Delete(result.%GetData(1), "-d")
	}
	Kill ^OcuTalonTest("Registry")
	Do ..ClearWorkflow()
	New $Namespace
	Set $Namespace = "%SYS"
	Set statement = ##class(%SQL.Statement).%New()
	Do statement.%Prepare("SELECT Name FROM Security.Users WHERE Name %STARTSWITH 'ZzRegistry'")
	Set result = statement.%Execute()
	While result.%Next() {
		Do ##class(Security.Users).Delete(result.%GetData(1))
	}
}

/// The OcuTalon roles that exist now, as a list of names.
ClassMethod OcuTalonRoles() As %List [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set names = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Roles WHERE Name %STARTSWITH 'OcuTalon'")
	While result.%Next() {
		Set names = names_$ListBuild(result.%GetData(1))
	}
	Quit names
}

/// Deletes every OcuTalon role that did not exist before the tests: the real roles that the Roles step creates.
Method RemoveNewRoles() [ Private ]
{
	Set current = ..OcuTalonRoles()
	New $Namespace
	Set $Namespace = "%SYS"
	Set position = 0
	While $ListNext(current, position, role) {
		If '$ListFind(..RolesBefore, role) Do ##class(Security.Roles).Delete(role)
	}
}

Method RemoveRoles() [ Private ]
{
	If ##class(%Dictionary.CompiledClass).%ExistsId(..Area) {
		Do $ClassMethod(..Area, "Role", "delete", ..Role)
		Do $ClassMethod(..Area, "Role", "delete", ..Role_"Alone")
	}
}

Method RoleResources(role As %String) As %String [ Private ]
{
	Quit $ClassMethod(..Area, "Role", "get", role)
}

Method SetRoleResources(role As %String, resources As %String) [ Private ]
{
	Do $ClassMethod(..Area, "Role", "set", role, resources)
}

Method SetRoleGranted(role As %String, granted As %String) [ Private ]
{
	Do $ClassMethod(..Area, "Role", "setgranted", role, granted)
}

ClassMethod RemoveTask(name As %String) [ Private ]
{
	Set id = ##class(%SYS.Task).FindId(name)
	If id '= "" Do ##class(%SYS.Task).%DeleteId(id)
}

ClassMethod TaskCount(name As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM %SYS.Task WHERE Name = ?", name)
	Do result.%Next()
	Quit result.%GetData(1)
}

ClassMethod DaysToKeep(task As %SYS.Task) As %String [ Private ]
{
	Set position = $ListFind(task.Settings, "DaysToKeep")
	Quit $Select(position: $List(task.Settings, position + 1), 1: "")
}

/// The resources of a role as a comma list, or "<none>" when it does not exist. Runs in %SYS.
ClassMethod ReadRole(role As %String) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If '##class(Security.Roles).Exists(role) Quit "<none>"
	Do ##class(Security.Roles).Get(role, .properties)
	Quit $Get(properties("Resources"))
}

/// Gives the role exactly these resources (not for "<none>"). Runs in %SYS.
ClassMethod WriteRole(role As %String, resources As %String) [ Private ]
{
	If resources = "<none>" Quit
	New $Namespace
	Set $Namespace = "%SYS"
	If '##class(Security.Roles).Exists(role) Quit
	Set properties("Resources") = resources
	Do ##class(Security.Roles).Modify(role, .properties)
}

/// The granted roles of a role as a comma list.
Method RoleGranted(role As %String) As %String [ Private ]
{
	Quit $ClassMethod(..Area, "Role", "getgranted", role)
}

/// The permissions of the role on the resource, "" when it holds none.
ClassMethod Permissions(role As %String, resource As %String) As %String [ Private ]
{
	Set resources = ..ReadRole(role)
	Set permissions = ""
	For i = 1:1:$Length(resources, ",") {
		Set entry = $Piece(resources, ",", i)
		If $Piece(entry, ":", 1) = resource Set permissions = $Piece(entry, ":", 2)
	}
	Quit permissions
}

/// 1 or 0: whether the user holds one permission letter on the resource, as the gate asks.
ClassMethod Allowed(user As %String, resource As %String, letter As %String) As %Boolean [ Private ]
{
	Quit +$SYSTEM.Security.CheckUserPermission(user, resource, letter)
}

/// 1 when the user exists. Runs in %SYS.
ClassMethod UserExists(user As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ''##class(Security.Users).Exists(user)
}

ClassMethod RemoveUser(user As %String) [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(user) Do ##class(Security.Users).Delete(user)
}

/// The resources of the user's roles as one comma list. Runs in %SYS.
ClassMethod UserResources(user As %String) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Do ##class(Security.Users).GetResourceSet(user, , .resources)
	Quit $Get(resources)
}

/// The number of rows that make the user a Workflow user or a Workflow role member, in OCUTALON and in OCUORDERS where it exists, or -1
/// when a namespace cannot be read.
ClassMethod WorkflowRows(user As %String) As %Integer [ Private ]
{
	New $Namespace
	Set rows = 0
	Set namespaces = $ListBuild("OCUTALON", "OCUORDERS")
	Set position = 0
	While $ListNext(namespaces, position, namespace) {
		If '##class(%SYS.Namespace).Exists(namespace) Continue
		Set $Namespace = namespace
		For table = "EnsLib_Workflow.UserDefinition|Name", "EnsLib_Workflow.RoleMembership|UserName" {
			Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_$Piece(table, "|", 1)_" WHERE "_$Piece(table, "|", 2)_" = ?", user)
			If result.%SQLCODE < 0 Quit
			Do result.%Next()
			Set rows = rows + result.%GetData(1)
		}
		If result.%SQLCODE < 0 Quit
	}
	Quit $Select(result.%SQLCODE < 0: -1, 1: rows)
}

/// 1 when the role holds SQL SELECT on Ens.MessageHeader in the namespace.
ClassMethod HoldsSelect(role As %String, namespace As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = namespace
	Quit ($SYSTEM.SQL.Security.CheckPrivilege(role, 1, "Ens.MessageHeader", "s") = 1)
}

/// Grants the role SELECT on Ens.MessageHeader in the namespace: in OCUTALON by the Web step's own call, and in OCUORDERS, where the Web step's
/// class is not mapped, by the system call that it makes.
ClassMethod GrantSelect(role As %String, namespace As %String) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = namespace
	If namespace = "OCUTALON" Quit ##class(OcuTalon.Install.Step.Web).GrantTraceSql(role)
	Quit $SYSTEM.SQL.Security.GrantPrivilege("SELECT", "Ens.MessageHeader", "TABLE", role)
}

ClassMethod RevokeSelect(role As %String, namespace As %String) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = namespace
	Quit $SYSTEM.SQL.Security.RevokePrivilege("SELECT", "Ens.MessageHeader", "TABLE", role)
}

/// The SQL privileges of the role as Namespace|SQLObject|Privilege, sorted, as a list separated by semicolons. Runs in %SYS.
ClassMethod SqlPrivileges(role As %String) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Namespace, SQLObject, Privilege FROM Security.SQLPrivileges WHERE Grantee = ?", role)
	While result.%Next() {
		Set rows(result.%GetData(1)_"|"_result.%GetData(2)_"|"_result.%GetData(3)) = ""
	}
	Set list = ""
	Set row = ""
	For {
		Set row = $Order(rows(row))
		Quit:row=""
		Set list = list _ $Select(list = "": "", 1: ";") _ row
	}
	Quit list
}

/// Makes the probe resource with public permission 0, or sets it to 0 when a failed run left it.
ClassMethod CreateProbe() As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Resources).Exists(..#PROBE) {
		Set properties("PublicPermission") = 0
		Quit ##class(Security.Resources).Modify(..#PROBE, .properties)
	}
	Quit ##class(Security.Resources).Create(..#PROBE, "OcuTalon test fixture", 0)
}

ClassMethod RemoveProbe() [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Resources).Exists(..#PROBE) Do ##class(Security.Resources).Delete(..#PROBE)
}

/// The resources of a role as a comma list in sorted order.
ClassMethod Sorted(resources As %String) As %String [ Private ]
{
	Set list = $ListFromString(resources)
	Set position = 0
	While $ListNext(list, position, resource) {
		Set sorted(resource) = ""
	}
	Set result = ""
	Set resource = ""
	For {
		Set resource = $Order(sorted(resource))
		Quit:resource=""
		Set result = result_$Select(result = "": "", 1: ",")_resource
	}
	Quit result
}

/// The area that the tests declare: one role with a union of grants and a role alone, and a suspended task.
XData FixtureArea [ MimeType = text/plain ]
{
Class @CLASS@ Extends OcuTalon.Install.Step
{

ClassMethod Grants() As %DynamicArray
{
	Quit [{"role":"OcuTalonZzFixture@N@","resource":"%DB_USER","permission":"R"},{"role":"OcuTalonZzFixture@N@","resource":"%DB_USER","permission":"W"},{"role":"OcuTalonZzFixture@N@","resource":"%Ens_Portal","permission":"U"},{"role":"OcuTalonZzFixture@N@Alone","resource":"","permission":""}]
}

ClassMethod Tasks() As %DynamicArray
{
	Quit [{"name":"OcuTalonZzFixture@N@","taskClass":"OcuTalon.Install.Task.Purge","description":"Fixture task","task":{"Suspended":1,"TimePeriod":0,"DailyFrequency":0,"DailyStartTime":10800},"settings":{"DaysToKeep":17}}]
}

ClassMethod Reconcile() As %Status
{
	Do $Increment(^OcuTalonTest("Registry", @N@, "reconcile"))
	Quit $SYSTEM.Status.OK()
}

ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Set ^OcuTalonTest("Registry", @N@, "purge") = daysToKeep
	Quit $SYSTEM.Status.OK()
}

/// Reads, sets or deletes a role in %SYS. get gives its resources, and getgranted its granted roles; set and setgranted replace them.
/// get gives "<none>" for a role that does not exist.
ClassMethod Role(operation As %String, role As %String, resources As %String = "") As %String
{
	New $Namespace
	Set $Namespace = "%SYS"
	If operation = "delete" {
		If ##class(Security.Roles).Exists(role) Do ##class(Security.Roles).Delete(role)
		Quit ""
	}
	If operation = "set" {
		Set properties("Resources") = resources
		Do ##class(Security.Roles).Modify(role, .properties)
		Quit ""
	}
	If operation = "setgranted" {
		Set properties("GrantedRoles") = resources
		Do ##class(Security.Roles).Modify(role, .properties)
		Quit ""
	}
	If '##class(Security.Roles).Exists(role) Quit "<none>"
	Do ##class(Security.Roles).Get(role, .properties)
	If operation = "getgranted" Quit $Get(properties("GrantedRoles"))
	Quit $Get(properties("Resources"))
}

}
}

/// A step for the registry's Run: it counts its runs and does what the body says.
XData FixtureRunStep [ MimeType = text/plain ]
{
Class @CLASS@ Extends OcuTalon.Install.Step
{

ClassMethod Run() As %Status
{
	Do $Increment(^OcuTalonTest("Registry", @N@, "run", "@CLASS@"))
	@BODY@
}

}
}

/// A registry whose order is the list that the test stores.
XData FixtureProbe [ MimeType = text/plain ]
{
Class @CLASS@ Extends OcuTalon.Install.Registry
{

ClassMethod Order() As %List
{
	Quit $Get(^OcuTalonTest("Registry", @N@, "order"))
}

}
}

/// An abstract area: never discovered.
XData FixtureAbstract [ MimeType = text/plain ]
{
Class @CLASS@ Extends OcuTalon.Install.Step [ Abstract ]
{
}
}

/// A subclass of the step contract outside the area package: never discovered.
XData FixtureOutside [ MimeType = text/plain ]
{
Class @CLASS@ Extends OcuTalon.Install.Step
{
}
}

/// An area that breaks the rules named by its role and task, fails its purge and throws in its reconcile.
XData FixtureBad [ MimeType = text/plain ]
{
Class @CLASS@ Extends OcuTalon.Install.Step
{

ClassMethod Grants() As %DynamicArray
{
	Quit [{"role":"@ROLE@","resource":"%Ens_Portal","permission":"U"}]
}

ClassMethod Tasks() As %DynamicArray
{
	Quit [{"name":"@TASK@","taskClass":"OcuTalon.Install.Task.Purge","description":"Fixture task","task":{"Suspended":1}}]
}

ClassMethod Reconcile() As %Status
{
	Throw ##class(%Exception.General).%New("Reconcile failed", 5001, , "Reconcile failed on purpose")
}

ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Quit $SYSTEM.Status.Error(5001, "Purge failed on purpose")
}

}
}


/// An area whose grants are the grants of a toolset: @BODY@ is the toolset class.
XData FixtureToolsArea [ MimeType = text/plain ]
{
Class @CLASS@ Extends OcuTalon.Install.Step
{

ClassMethod Grants() As %DynamicArray
{
	Quit ##class(OcuTalon.Install.Step.Tools).GrantsOf($ListBuild("@BODY@"))
}

}
}

/// A tool that declares the probe resource: Use.
XData FixtureProbeTool [ MimeType = text/plain ]
{
Class @CLASS@ Extends OcuTalon.Tools.Result
{

Parameter STEPLABEL = "Probing";

Parameter RESOURCESALPHA = "ZzOcuTalonGrantProbe:U";

ClassMethod Alpha() As %DynamicObject
{
	Quit ..Return({})
}

}
}

/// A tool whose RESOURCES is malformed: no colon.
XData FixtureBadTool [ MimeType = text/plain ]
{
Class @CLASS@ Extends OcuTalon.Tools.Result
{

Parameter RESOURCESALPHA = "ZzNoColon";

ClassMethod Alpha() As %DynamicObject
{
	Quit ..Return({})
}

}
}

/// A toolset of one tool, alpha: @BODY@ is the tool class.
XData FixtureBadToolset [ MimeType = text/plain ]
{
Class @CLASS@ Extends %AI.ToolSet [ DependsOn = @BODY@ ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="OcuTalonZzBad@N@">
  <Description>A fixture tool.</Description>
  <Tool Name="alpha" Class="@BODY@" Method="Alpha"/>
</ToolSet>
}

}
}

/// An abstract toolset: never a built-in one.
XData FixtureAbstractToolset [ MimeType = text/plain ]
{
Class @CLASS@ Extends %AI.ToolSet [ Abstract ]
{
}
}

/// An area that declares a resource for @ROLE@ that the test chooses: the resource is read from the test's global.
XData FixtureForbidden [ MimeType = text/plain ]
{
Class @CLASS@ Extends OcuTalon.Install.Step
{

ClassMethod Grants() As %DynamicArray
{
	Quit [{"role":"@ROLE@","resource":(^OcuTalonTest("Registry", @N@, "forbidden")),"permission":"U"}]
}

}
}

}
