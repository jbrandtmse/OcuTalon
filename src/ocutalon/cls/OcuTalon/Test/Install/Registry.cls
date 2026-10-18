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

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("Registry", "n"))
	Set ..Area = "OcuTalon.Install.Step.ZzFixture"_..Number
	Set ..Abstract = ..Area_"Abstract"
	Set ..Outside = "OcuTalon.Test.Install.ZzOutside"_..Number
	Set ..BadArea = "OcuTalon.Install.Step.ZzBad"_..Number
	Set ..Role = "OcuTalonZzFixture"_..Number
	Set ..TaskName = "OcuTalonZzFixture"_..Number
	Set sc = ..Create("FixtureArea", ..Area, ..Number)
	If $$$ISOK(sc) Set sc = ..Create("FixtureAbstract", ..Abstract, ..Number)
	If $$$ISOK(sc) Set sc = ..Create("FixtureOutside", ..Outside, ..Number)
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Do ..RemoveRoles()
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

/// The order is the fixed list of 15 steps, and every step in it exists.
Method TestOrder()
{
	Set order = ##class(OcuTalon.Install.Registry).Order()
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
}

/// A role name that does not start with OcuTalon fails the step, which names the area, and changes nothing.
Method TestRoleNameRefused()
{
	Do ..RemoveRoles()
	Set bad = ..BadArea
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

/// --- fixtures ---

/// Creates and compiles a class from an XData block of this class, with @CLASS@ replaced by the class name,
/// @N@ by the fixture's number and @ROLE@ and @TASK@ by the arguments.
Method Create(block As %String, className As %String, number As %Integer, role As %String = "", task As %String = "") As %Status [ Private ]
{
	Set text = ##class(%Dictionary.CompiledXData).%OpenId($ClassName()_"||"_block).Data.Read(100000)
	Set text = $Replace(text, $Char(13), "")
	Set text = $Replace($Replace($Replace($Replace(text, "@CLASS@", className), "@N@", number), "@ROLE@", role), "@TASK@", task)
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
	Do statement.%Prepare("SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'OcuTalon.Install.Step.Zz' OR Name %STARTSWITH 'OcuTalon.Test.Install.ZzOutside'")
	Set result = statement.%Execute()
	While result.%Next() {
		Do $SYSTEM.OBJ.Delete(result.%GetData(1), "-d")
	}
	Kill ^OcuTalonTest("Registry")
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
