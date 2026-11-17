/// The base of the tests that change security records for OcuTalon's own MCP server (Story 28.3): Test.Mcp.ServiceInstall, ServiceHttp and ServiceRoles. THEY RUN IN THROWAWAY STACKS AND IN CI
/// ONLY (Rule 21): they create and delete security users and roles, and some of them change the installed objects of the Mcp step and put them back. Test.Core.AnswersInWebRoles Reason refuses
/// everything else (the CI override's mock and a running OcuTalon.Production, as Test.Web.LiveRolesApi requires). The fixture users have the prefix USER, the fixture roles are ROLEREADS and
/// ROLEINSIDE, and OnBeforeAllTests, OnAfterOneTest and OnAfterAllTests remove them. It has no Test method.
///   - ROLEREADS holds the three database read grants of the application role and not the resource; ROLEINSIDE holds exactly the grants of the Mcp step's application role (a copy, so that
///     the real application role is held by no user, even for a test);
///   - NewUser makes a fixture user with the roles and a random password, which is returned.
Class OcuTalon.Test.Mcp.ServiceCase Extends %UnitTest.TestCase [ Abstract ]
{

Parameter USER = "ZzMcpUser";

Parameter ROLEREADS = "ZzMcpReads";

Parameter ROLEINSIDE = "ZzMcpInside";

/// The web server's port inside the container.
Parameter PORT = 52773;

Property Missing As %String(MAXLEN = 300);

Method OnBeforeAllTests() As %Status
{
	Set running = ##class(Ens.Director).IsProductionRunning(.name)
	Set ..Missing = ##class(OcuTalon.Test.Core.AnswersInWebRoles).Reason($SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL"), $SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER"), running, $Get(name))
	If ..Missing '= "" Quit $SYSTEM.Status.Error(5001, ..Missing)
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Missing = "" Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If ..Missing = "" Do ..Clean()
	Quit $$$OK
}

/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// Creates the fixture user (the prefix USER and the suffix) with the roles (a comma list); returns the name, and the random password in password.
Method NewUser(suffix As %String, roles As %String, Output password As %String) As %String [ Private ]
{
	Set user = ..#USER _ suffix
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Install.RolesAssign).CreateUser(user, roles, , .password), "the fixture user " _ user _ " is created with " _ roles)
	Quit user
}

/// Creates the fixture role with the resources (a resource:permission comma list), replacing one that exists.
Method NewRole(role As %String, resources As %String) [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Roles).Exists(role) Do ##class(Security.Roles).Delete(role)
	Do $$$AssertStatusOK(##class(Security.Roles).Create(role, "OcuTalon test fixture", resources, ""), "the fixture role " _ role _ " is created")
}

/// Deletes the fixture users and roles.
ClassMethod Clean()
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Users WHERE Name %STARTSWITH ?", ..#USER)
	While result.%Next() {
		Do ##class(Security.Users).Delete(result.%GetData(1))
	}
	For role = ..#ROLEREADS, ..#ROLEINSIDE {
		If ##class(Security.Roles).Exists(role) Do ##class(Security.Roles).Delete(role)
	}
}

}
