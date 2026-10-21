/// Tests of the installer-step registry with a fixture area (AD-23, AD-27, AD-29): discovery, the Roles,
/// Tasks and Reconcile steps, and the purge task. The fixture area, a role and a task are created in
/// OnBeforeAllTests and removed in OnAfterAllTests, with the fixture's ^OcuTalonTest nodes.
Class OcuTalon.Test.Install.Registry Extends %UnitTest.TestCase
{

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

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..RolesBefore = ..OcuTalonRoles()
	Set ..Number = $Increment(^OcuTalonTest("Registry", "n"))
	Set ..Area = "OcuTalon.Install.Step.ZzFixture"_..Number
	Set ..Abstract = ..Area_"Abstract"
	Set ..Outside = "OcuTalon.Test.Install.ZzOutside"_..Number
	Set ..BadArea = "OcuTalon.Install.Step.ZzBad"_..Number
	Set ..Role = "OcuTalonZzFixture"_..Number
	Set ..TaskName = "OcuTalonZzFixture"_..Number
	Set ..Probe = "OcuTalon.Test.Install.ZzRegistryProbe"_..Number
	Set sc = ..Create("FixtureArea", ..Area, ..Number)
	If $$$ISOK(sc) Set sc = ..Create("FixtureAbstract", ..Abstract, ..Number)
	If $$$ISOK(sc) Set sc = ..Create("FixtureOutside", ..Outside, ..Number)
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Do ..RemoveRoles()
	Do ..RemoveNewRoles()
	Do ..RemoveTask(..TaskName)
	Do ..Clean()
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
	Do $$$AssertEquals(..Sorted(..RoleResources(..Role)), "%DB_USER:RW,%Development:U", "the role holds exactly the declared resources")
	Do $$$AssertEquals(..RoleResources(..Role_"Alone"), "", "the role declared alone holds nothing")

	Do ..SetRoleResources(..Role, "%DB_USER:RW,%Development:U,%Service_Terminal:U")
	Do $$$AssertEquals(..Sorted(..RoleResources(..Role)), "%DB_USER:RW,%Development:U,%Service_Terminal:U", "an extra grant was added by hand")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs again")
	Do $$$AssertEquals(..Sorted(..RoleResources(..Role)), "%DB_USER:RW,%Development:U", "the role is back to exactly the declared set")
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

/// --- fixtures ---
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
	Do statement.%Prepare("SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'OcuTalon.Install.Step.Zz' OR Name %STARTSWITH 'OcuTalon.Test.Install.ZzOutside' OR Name %STARTSWITH 'OcuTalon.Test.Install.ZzRegistryProbe'")
	Set result = statement.%Execute()
	While result.%Next() {
		Do $SYSTEM.OBJ.Delete(result.%GetData(1), "-d")
	}
	Kill ^OcuTalonTest("Registry")
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
	Quit [{"role":"OcuTalonZzFixture@N@","resource":"%DB_USER","permission":"R"},{"role":"OcuTalonZzFixture@N@","resource":"%DB_USER","permission":"W"},{"role":"OcuTalonZzFixture@N@","resource":"%Development","permission":"U"},{"role":"OcuTalonZzFixture@N@Alone","resource":"","permission":""}]
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

/// Reads, sets or deletes a role in %SYS. get gives "<none>" for a role that does not exist.
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
	If '##class(Security.Roles).Exists(role) Quit "<none>"
	Do ##class(Security.Roles).Get(role, .properties)
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
	Quit [{"role":"@ROLE@","resource":"%Development","permission":"U"}]
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

}
