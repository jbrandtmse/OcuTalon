/// Tests of the Mcp installer step for OcuTalon's own MCP server (Story 28.3; AD-21, AD-23, AD-24, AD-25): the application role, the web application and the resource that it makes, the
/// client role that it declares, the order of the step and the online demo, where none of them exists. THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), through Test.Mcp.ServiceCase.
/// The scratch names ZzMcp... stand for the installed objects wherever a test must create, change or delete them; TestDemoRemoves is the one test that runs the real step with the online
/// demo on and puts the installed objects back (OnAfterOneTest); it never runs the Roles step.
///   - TestInstalledObjects (AC 1), on the objects as the start left them (read by OnBeforeAllTests, before any test of the class changes them): the resource has no public permission;
///     /mcp/ocutalon has exactly ServiceApp's properties (password only, namespace OCUTALON, outside the sign-in group, dispatch OcuTalon.Mcp.Service, MatchRoles :OcuTalonMCPApp);
///     OcuTalonMCPApp holds exactly the three database read grants, no granted role, no SQL privilege and is held by no user or role; OcuTalonMCPClient holds exactly OcuTalon_MCPServer:U
///     and nothing else; OcuTalonUser holds none of them;
///   - TestStepOrder and TestFreshInstallRefusesNoStep: the Mcp step runs before Roles; the start's log shows STEP Mcp OK before STEP Roles OK, and the step makes the application role, the
///     application and the resource from nothing in that order (IRIS refuses an application whose MatchRoles names a missing role);
///   - TestStepRewritesDrift: a changed application, role or resource is put back to its definition by the next run, with no new object;
///   - TestGrants (AC 2): off the online demo Grants declares OcuTalonMCPClient with OcuTalon_MCPServer:U and the per-server pairs; on it, none;
///   - TestDemoRemoves (AC 2): on the online demo the step deletes the application, the resource and both roles where they exist, and makes none.
Class OcuTalon.Test.Mcp.ServiceInstall Extends OcuTalon.Test.Mcp.ServiceCase
{

Parameter STEP = "OcuTalon.Install.Step.Mcp";

Parameter LOG = "/durable/ocutalon-after-start.log";

Property OnlineBefore As %String;

Property OnlineSaved As %Boolean [ InitialExpression = 0 ];

/// The objects as the start left them: Installed(kind) is "exists" or "<none>" and Installed(kind, "p", key) their properties, for the kinds app, resource, appRole and client.
Property Installed As %String [ MultiDimensional ];

/// Reads the application, the resource and both roles before any test of the class changes them.
Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	If $$$ISERR(sc) Quit sc
	Set step = ..#STEP
	Set ..Installed("app") = ..Application($Parameter(step, "SERVICEAPP"), .props)
	Merge ..Installed("app", "p") = props
	Set ..Installed("resource") = ..ResourceOf($Parameter(step, "SERVICERESOURCE"), .props)
	Merge ..Installed("resource", "p") = props
	Set ..Installed("appRole") = ..RoleOf($Parameter(step, "APPROLE"), .props)
	Merge ..Installed("appRole", "p") = props
	Set ..Installed("client") = ..RoleOf($Parameter(step, "CLIENTROLE"), .props)
	Merge ..Installed("client", "p") = props
	Quit $$$OK
}

/// What OnBeforeAllTests read for the kind: "exists" or "<none>" (or "" when it read nothing), and the properties in props.
Method AsInstalled(kind As %String, Output props) As %String [ Private ]
{
	Kill props
	Merge props = ..Installed(kind, "p")
	Quit $Get(..Installed(kind))
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If (..Missing = "") && ..OnlineSaved {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..OnlineBefore)
		Set ..OnlineSaved = 0
		Do ..Restore()
	}
	Quit ##super(testname)
}

/// Sets the public flag onlineDemo; OnAfterOneTest puts it back, and puts the installed objects back with it.
Method SetOnlineDemo(value As %String) [ Private ]
{
	If '..OnlineSaved {
		Set ..OnlineBefore = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
		Set ..OnlineSaved = 1
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", value), "onlineDemo is set to '" _ value _ "'")
}

/// The installed objects as the install makes them: the Mcp step, then the client role with the one grant that the step declares (what the Roles step composes for it; the Roles step itself
/// is not run, because it would also take the grants that only the Demo step gives, which other tests need). Runs in %SYS for the role.
ClassMethod Restore() As %Status [ Private ]
{
	Set sc = $ClassMethod(..#STEP, "Run")
	If $$$ISERR(sc) Quit sc
	Set role = $Parameter(..#STEP, "CLIENTROLE")
	Set resources = $Parameter(..#STEP, "SERVICERESOURCE") _ ":" _ $Parameter(..#STEP, "PERMISSION")
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Roles).Exists(role) {
		Set properties("Resources") = resources
		Set properties("GrantedRoles") = ""
		Quit ##class(Security.Roles).Modify(role, .properties)
	}
	Quit ##class(Security.Roles).Create(role, "OcuTalon role", resources, "")
}

/// What is in %SYS: props of the application, the resource, the role (Resources and GrantedRoles) as strings, "<none>" for an object that does not exist.
ClassMethod Application(name As %String, Output props) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill props
	If '##class(Security.Applications).Exists(name) Quit "<none>"
	Do ##class(Security.Applications).Get(name, .props)
	Quit "exists"
}

ClassMethod ResourceOf(name As %String, Output props) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill props
	If '##class(Security.Resources).Exists(name) Quit "<none>"
	Do ##class(Security.Resources).Get(name, .props)
	Quit "exists"
}

ClassMethod RoleOf(name As %String, Output props) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill props
	If '##class(Security.Roles).Exists(name) Quit "<none>"
	Do ##class(Security.Roles).Get(name, .props)
	Quit "exists"
}

/// The text of a resource:permission list in sorted order.
ClassMethod Sorted(list As %String) As %String [ Private ]
{
	Kill held
	For i = 1:1:$Length(list, ",") {
		If $Piece(list, ",", i) '= "" Set held($Piece(list, ",", i)) = ""
	}
	Set sorted = ""
	Set item = ""
	For {
		Set item = $Order(held(item))
		Quit:item=""
		Set sorted = sorted _ $Select(sorted = "": "", 1: ",") _ item
	}
	Quit sorted
}

/// The users that hold the role directly and the roles that have it granted, as a comma list ("" for none). Runs in %SYS.
ClassMethod Holders(role As %String) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set holders = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, Roles FROM Security.Users")
	While result.%Next() {
		If $ListFind($ListFromString(result.%GetData(2)), role) Set holders = holders _ " user " _ result.%GetData(1)
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, GrantedRoles FROM Security.Roles")
	While result.%Next() {
		If $ListFind($ListFromString(result.%GetData(2)), role) Set holders = holders _ " role " _ result.%GetData(1)
	}
	Quit $ZStrip(holders, "<>W")
}

/// The SQL privileges of the grantee as a text, "" for none. Runs in %SYS.
ClassMethod SqlPrivileges(grantee As %String) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set text = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Namespace, SQLObject, Privilege FROM Security.SQLPrivileges WHERE Grantee = ?", grantee)
	While result.%Next() {
		Set text = text _ " " _ result.%GetData(1) _ "|" _ result.%GetData(2) _ "|" _ result.%GetData(3)
	}
	Quit $ZStrip(text, "<>W")
}

Method TestInstalledObjects()
{
	If '..Guard() Quit
	Set step = ..#STEP
	Set resource = $Parameter(step, "SERVICERESOURCE")
	Set app = $Parameter(step, "SERVICEAPP")
	Set appRole = $Parameter(step, "APPROLE")
	Set client = $Parameter(step, "CLIENTROLE")
	Do $$$AssertEquals(..AsInstalled("resource", .res), "exists", "the resource " _ resource _ " exists")
	Do $$$AssertEquals($Get(res("PublicPermission")), "", "and has no public permission")
	Do $$$AssertEquals(..AsInstalled("app", .props), "exists", "the application " _ app _ " exists")
	Do $ClassMethod(step, "ServiceApp", .expected)
	Set bad = ""
	Set key = ""
	For {
		Set key = $Order(expected(key))
		Quit:key=""
		If $Get(props(key)) '= expected(key) Set bad = bad _ " " _ key _ "=" _ $Get(props(key)) _ " (not " _ expected(key) _ ")"
	}
	Do $$$AssertEquals(bad, "", "it has exactly the properties of ServiceApp")
	Do $$$AssertEquals($Get(props("AutheEnabled")), 32, "it signs in with a password only")
	Do $$$AssertEquals($Get(props("MatchRoles")), ":" _ appRole, "its only application role is " _ appRole _ " and it has no match role")
	Do $$$AssertEquals($Get(props("GroupById")), "", "it is outside the sign-in group")
	Do $$$AssertEquals($Get(props("DispatchClass")), "OcuTalon.Mcp.Service", "it dispatches to OcuTalon.Mcp.Service")
	Do $$$AssertEquals($Get(props("Resource")), "", "and it needs no resource of its own")
	Do $$$AssertEquals(..AsInstalled("appRole", .role), "exists", "the application role " _ appRole _ " exists")
	Do $$$AssertEquals(..Sorted($Get(role("Resources"))), "%DB_OCUTALON_CODE:R,%DB_OCUTALON_DATA:R,%DB_OCUTALON_PRIVATE:R", "it holds exactly the three database read grants")
	Do $$$AssertEquals($Get(role("GrantedRoles")), "", "it is granted no role")
	Do $$$AssertEquals(..SqlPrivileges(appRole), "", "it holds no SQL privilege")
	Do $$$AssertEquals(..Holders(appRole), "", "and no user or role holds it")
	Do $$$AssertEquals(..AsInstalled("client", .role), "exists", "the client role " _ client _ " exists")
	Do $$$AssertEquals($Get(role("Resources")), resource _ ":U", "it holds exactly Use on the resource")
	Do $$$AssertEquals($Get(role("GrantedRoles")), "", "it is granted no role")
	Do $$$AssertEquals(..SqlPrivileges(client), "", "it holds no SQL privilege")
	Do $$$AssertEquals(..Holders(client), "", "and no user or role holds it: the installer grants it to no one")
	Do $$$AssertEquals(..RoleOf("OcuTalonUser", .role), "exists", "OcuTalonUser exists")
	Do $$$AssertEquals($Get(role("Resources")), "", "and holds no resource, as before")
	Do $$$AssertEquals($Get(role("GrantedRoles")), "", "or role")
}

Method TestStepOrder()
{
	Set order = ##class(OcuTalon.Install.Registry).Order()
	Do $$$AssertTrue($ListFind(order, "Mcp") > 0, "the registry runs the Mcp step")
	Do $$$AssertTrue($ListFind(order, "Mcp") < $ListFind(order, "Roles"), "before Roles, which composes the client role's grant on the resource it makes")
	Do $$$AssertTrue($ListFind(order, "Mcp") > $ListFind(order, "Public"), "and after Public, which writes the online-demo flag that it reads")
}

/// A fresh install refuses no step: the log of this stack's start has STEP Mcp OK before STEP Roles OK and no failed step; and the step makes its objects from nothing, application role first,
/// in the scratch names (an application whose MatchRoles names a missing role is refused by IRIS, ERROR #879).
Method TestFreshInstallRefusesNoStep()
{
	If '..Guard() Quit
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set sc = stream.LinkToFile(..#LOG)
	Set log = ""
	If $$$ISOK(sc) {
		While 'stream.AtEnd {
			Set log = log _ stream.ReadLine(2000) _ $Char(10)
		}
	}
	Do $$$AssertTrue(log '= "", "the log of the start is read")
	Set lf = $Char(10)
	Set mcp = $Find(lf _ log, lf _ "STEP Mcp OK")
	Set roles = $Find(lf _ log, lf _ "STEP Roles OK")
	Do $$$AssertTrue((mcp > 0) && (roles > mcp), "the log shows STEP Mcp OK before STEP Roles OK")
	Do $$$AssertTrue($Find(log, "FAILED") = 0, "and no step failed")
	Do $$$AssertTrue($Find(log, "#879") = 0, "and none was refused for a missing role (ERROR #879)")
	Set application = "/mcp/zzmcpfresh"
	Set resource = "ZzMcpFresh_Resource"
	Set appRole = "ZzMcpFreshApp"
	Do ..Scratch(application, resource, appRole)
	Try {
		Do $$$AssertEquals(..Application(application, .props), "<none>", "control: the scratch application does not exist")
		Do $$$AssertEquals(..RoleOf(appRole, .role), "<none>", "control: nor its application role")
		Do $$$AssertStatusOK($ClassMethod(..#STEP, "ApplyService", application, resource, appRole), "the step makes its objects from nothing, with no refusal")
		Do $$$AssertEquals(..Application(application, .props), "exists", "the application exists")
		Do $$$AssertEquals($Get(props("MatchRoles")), ":" _ appRole, "with the application role in its MatchRoles")
		Do $$$AssertEquals(..RoleOf(appRole, .role), "exists", "the application role exists")
		Do $$$AssertEquals(..ResourceOf(resource, .res), "exists", "and so does the resource")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the scratch objects are made without an exception")
	}
	Do ..Scratch(application, resource, appRole)
}

/// Removes the scratch application, resource and application role.
ClassMethod Scratch(application As %String, resource As %String, appRole As %String) [ Private ]
{
	Do $ClassMethod(..#STEP, "RemoveService", application, resource, appRole, "ZzMcpFreshClient")
}

Method TestStepRewritesDrift()
{
	If '..Guard() Quit
	Set application = "/mcp/zzmcpdrift"
	Set resource = "ZzMcpDrift_Resource"
	Set appRole = "ZzMcpDriftApp"
	Do ..Scratch(application, resource, appRole)
	Try {
		Do $$$AssertStatusOK($ClassMethod(..#STEP, "ApplyService", application, resource, appRole), "the step makes the scratch objects")
		Do ..Drift(application, appRole, resource)
		Do $$$AssertEquals(..Application(application, .props), "exists", "control: the application exists")
		Do $$$AssertEquals($Get(props("MatchRoles")) _ "|" _ $Get(props("AutheEnabled")) _ "|" _ $Get(props("GroupById")), ":%DB_OCUTALON_DATA|64|OcuTalon", "control: it was changed to the RW database role, no sign-in and the sign-in group")
		Do $$$AssertEquals(..RoleOf(appRole, .role), "exists", "control: the role exists")
		Do $$$AssertTrue($Get(role("Resources")) [ "%DB_OCUTALON_DATA:RW", "control: and holds write on the data database")
		Do $$$AssertEquals($Get(role("GrantedRoles")), "%DB_OCUTALON_DATA", "control: and is granted the RW database role")
		Do $$$AssertStatusOK($ClassMethod(..#STEP, "ApplyService", application, resource, appRole), "the step runs again")
		Do ..Application(application, .props)
		Do $ClassMethod(..#STEP, "ServiceApp", .expected, appRole, application)
		Set bad = ""
		Set key = ""
		For {
			Set key = $Order(expected(key))
			Quit:key=""
			If $Get(props(key)) '= expected(key) Set bad = bad _ " " _ key
		}
		Do $$$AssertEquals(bad, "", "the application is put back to the properties of ServiceApp")
		Do ..RoleOf(appRole, .role)
		Do $$$AssertEquals(..Sorted($Get(role("Resources"))), "%DB_OCUTALON_CODE:R,%DB_OCUTALON_DATA:R,%DB_OCUTALON_PRIVATE:R", "and the role to the three read grants")
		Do $$$AssertEquals($Get(role("GrantedRoles")), "", "with no granted role")
		Do $$$AssertEquals(..ResourceOf(resource, .res), "exists", "and the resource still exists")
		Do $$$AssertEquals($Get(res("PublicPermission")), "", "with no public permission")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the drift is put back without an exception")
	}
	Do ..Scratch(application, resource, appRole)
}

/// Changes the scratch application to unauthenticated sign-in in the sign-in group with the RW database role, the role to write on the data database and to be granted the RW database role,
/// and the resource to a public permission.
ClassMethod Drift(application As %String, appRole As %String, resource As %String) [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set properties("MatchRoles") = ":%DB_OCUTALON_DATA"
	Set properties("AutheEnabled") = 64
	Set properties("GroupById") = "OcuTalon"
	Do ##class(Security.Applications).Modify(application, .properties)
	Kill properties
	Set properties("Resources") = "%DB_OCUTALON_CODE:R,%DB_OCUTALON_DATA:RW"
	Set properties("GrantedRoles") = "%DB_OCUTALON_DATA"
	Do ##class(Security.Roles).Modify(appRole, .properties)
	Kill properties
	Set properties("PublicPermission") = "R"
	Do ##class(Security.Resources).Modify(resource, .properties)
}

Method TestGrants()
{
	If '..Guard() Quit
	Set step = ..#STEP
	Set client = $Parameter(step, "CLIENTROLE")
	Set resource = $Parameter(step, "SERVICERESOURCE")
	Do ..SetOnlineDemo(0)
	Set grants = $ClassMethod(step, "Grants")
	Set found = ""
	Set iterator = grants.%GetIterator()
	While iterator.%GetNext(, .grant) {
		If grant.role = client Set found = found _ " " _ grant.resource _ ":" _ grant.permission
	}
	Do $$$AssertEquals($ZStrip(found, "<>W"), resource _ ":U", "off the online demo Grants declares " _ client _ " with Use on the resource and nothing else")
	Do ..SetOnlineDemo(1)
	Set grants = $ClassMethod(step, "Grants")
	Do $$$AssertEquals(grants.%Size(), 0, "on the online demo Grants declares nothing")
}

Method TestDemoRemoves()
{
	If '..Guard() Quit
	Set step = ..#STEP
	Do $$$AssertStatusOK(..Restore(), "control: the objects are made as the install makes them")
	Do $$$AssertEquals(..Application($Parameter(step, "SERVICEAPP"), .props), "exists", "control: the application is installed")
	Do ..SetOnlineDemo(1)
	Do $$$AssertStatusOK($ClassMethod(step, "Run"), "the step runs on the online demo")
	Do $$$AssertEquals(..Application($Parameter(step, "SERVICEAPP"), .props), "<none>", "the application is gone")
	Do $$$AssertEquals(..ResourceOf($Parameter(step, "SERVICERESOURCE"), .res), "<none>", "the resource is gone")
	Do $$$AssertEquals(..RoleOf($Parameter(step, "APPROLE"), .role), "<none>", "the application role is gone")
	Do $$$AssertEquals(..RoleOf($Parameter(step, "CLIENTROLE"), .role), "<none>", "the client role is gone")
	Do $$$AssertStatusOK($ClassMethod(step, "Run"), "a second run, with nothing left, is not an error")
	Do $$$AssertEquals(..Application($Parameter(step, "SERVICEAPP"), .props), "<none>", "and makes no application")
	Do $$$AssertEquals(..RoleOf($Parameter(step, "APPROLE"), .role), "<none>", "no application role")
	Do $$$AssertEquals(..ResourceOf($Parameter(step, "SERVICERESOURCE"), .res), "<none>", "and no resource")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Compose(.composed), "the roles that the Roles step would make can be composed on the online demo")
	Do $$$AssertEquals($Data(composed($Parameter(step, "CLIENTROLE"))), 0, "and the client role is not one of them")
}

}
