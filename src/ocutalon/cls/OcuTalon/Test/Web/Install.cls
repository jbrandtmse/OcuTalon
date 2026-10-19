/// Tests of the Web step's declarations (matrix row 17): the application table, the trace application of a
/// namespace, the trace role's grants, Apply, BundleCheck and the trace role's SQL privilege. The real
/// applications, roles and user are never touched: Apply and the SQL grant run on fixtures (ZzWeb<n>), which
/// OnAfterAllTests removes together with the fixture folder.
Class OcuTalon.Test.Web.Install Extends %UnitTest.TestCase
{

/// The fixture's number: the application is /zzweb<n>, the roles ZzWeb<n>RoleA and ZzWeb<n>RoleB.
Property Number As %Integer;

Property Application As %String;

Property RoleA As %String;

Property RoleB As %String;

Property Directory As %String;

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("WebInstall", "n"))
	Set ..Application = "/zzweb"_..Number
	Set ..RoleA = "ZzWeb"_..Number_"RoleA"
	Set ..RoleB = "ZzWeb"_..Number_"RoleB"
	Set file = ##class(%File).TempFilename("d")
	Do ##class(%File).Delete(file)
	Set ..Directory = ##class(%File).NormalizeDirectory(file)
	Quit ..CreateRoles()
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	If ..Directory '= "" Do ##class(%File).RemoveDirectoryTree(..Directory)
	Quit $SYSTEM.Status.OK()
}

/// The application table of the Web step, key by key: three applications, every key passed, an empty CORS list.
Method TestDefinitions()
{
	Set sc = ##class(OcuTalon.Install.Step.Web).Definitions(.apps)
	Do $$$AssertStatusOK(sc, "Definitions")
	Set names = ""
	Set name = ""
	For {
		Set name = $Order(apps(name))
		Quit:name=""
		Set names = names_$Select(names = "": "", 1: ",")_name
	}
	Do $$$AssertEquals(names, "/ocutalon,/ocutalon/api,/ocutalon/trace/ocutalon", "the three applications")
	For name = "/ocutalon", "/ocutalon/api", "/ocutalon/trace/ocutalon" {
		Kill expected
		Do ..Expected(name, .expected)
		Set key = ""
		For {
			Set key = $Order(expected(key))
			Quit:key=""
			Do $$$AssertEquals($Get(apps(name, key), "<undefined>"), expected(key), name_" "_key)
		}
		Set key = ""
		For {
			Set key = $Order(apps(name, key))
			Quit:key=""
			Do $$$AssertTrue($Data(expected(key)), name_" "_key_" is in the table")
		}
	}
}

/// The trace application of a namespace: its name from the namespace, AD-24's seven permitted classes, no
/// application roles and no dispatch class.
Method TestTraceApp()
{
	Set name = ##class(OcuTalon.Install.Step.Web).TraceApp("ZZNS", .props)
	Do $$$AssertEquals(name, "/ocutalon/trace/zzns", "the name is the namespace in lower case")
	Do $$$AssertEquals(props("NameSpace"), "ZZNS", "the namespace")
	Do $$$AssertEquals(props("CookiePath"), "/ocutalon/trace/zzns/", "the cookie path")
	Do $$$AssertEquals(props("GroupById"), "OcuTalon", "the sign-in group")
	Do $$$AssertEquals(props("MatchRoles"), "", "no application roles")
	Do $$$AssertEquals(props("DispatchClass"), "", "no dispatch class")
	Do $$$AssertEquals(props("ServeFiles"), 1, "ServeFiles 1")
	Do $$$AssertEquals(props("CSPZENEnabled"), 1, "the ZEN pages are enabled")
	Do $$$AssertEquals(props("PermittedClasses"), ..SevenClasses(), "exactly the seven classes of AD-24")
	Do $$$AssertEquals($Length(props("PermittedClasses"), ","), 7, "seven classes")
	Kill expected
	Do ..Expected("/ocutalon/trace/ocutalon", .expected)
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Web).TraceApp("OCUTALON", .props), "/ocutalon/trace/ocutalon", "the OCUTALON trace application")
	Set key = ""
	For {
		Set key = $Order(expected(key))
		Quit:key=""
		Do $$$AssertEquals($Get(props(key), "<undefined>"), expected(key), "OCUTALON trace "_key)
	}
}

/// The trace role: exactly Use on four Ens resources and Read on the data and code databases, and none of the
/// resources that AD-24 forbids to every OcuTalon role. The Users step adds two roles without a resource.
Method TestGrants()
{
	Set grants = ##class(OcuTalon.Install.Step.Web).Grants()
	Do $$$AssertEquals(grants.%Size(), 6, "six grants")
	Set seen = ""
	For i = 0:1:grants.%Size() - 1 {
		Set grant = grants.%Get(i)
		Do $$$AssertEquals(grant.role, "OcuTalonTraceViewer", "the grant "_i_" is the trace role's")
		Set seen(grant.resource) = grant.permission
		Do $$$AssertTrue(..Forbidden(grant.resource) = 0, grant.resource_" is not a forbidden resource")
	}
	Do $$$AssertEquals($Get(seen("%Ens_Portal")), "U", "Use on %Ens_Portal")
	Do $$$AssertEquals($Get(seen("%Ens_MessageTrace")), "U", "Use on %Ens_MessageTrace")
	Do $$$AssertEquals($Get(seen("%Ens_MessageHeader")), "U", "Use on %Ens_MessageHeader")
	Do $$$AssertEquals($Get(seen("%Ens_MessageContent")), "U", "Use on %Ens_MessageContent")
	Do $$$AssertEquals($Get(seen("%DB_OCUTALON_DATA")), "R", "Read on the data database")
	Do $$$AssertEquals($Get(seen("%DB_OCUTALON_CODE")), "R", "Read on the code database")

	Set sc = ##class(OcuTalon.Install.Registry).Declared("Grants", .declared)
	Do $$$AssertStatusOK(sc, "the declarations of all the areas")
	Set holds = 0
	Set user = 0
	Set n = ""
	For {
		Set n = $Order(declared(n))
		Quit:n=""
		Set role = declared(n).role
		If role = "OcuTalonTraceViewer" Set holds = holds + 1
		If (role = "OcuTalonUser") || (role = "OcuTalonAdmin") {
			Set user = user + 1
			Do $$$AssertEquals(declared(n).resource, "", role_" holds no resource")
		}
		If $Extract(role, 1, 8) = "OcuTalon" {
			Do $$$AssertTrue(..Forbidden(declared(n).resource) = 0, "no OcuTalon role holds the forbidden "_declared(n).resource)
		}
	}
	Do $$$AssertEquals(holds, 6, "the registry sees the trace role's six grants")
	Do $$$AssertEquals(user, 2, "the registry sees the two roles without a resource")
}

/// Apply creates an application with the given properties and, when it exists, modifies it back to them.
Method TestApply()
{
	Do ..RemoveApplication()
	Do $$$AssertEquals(..Application(.stored), 0, "no fixture application to begin with")
	Do ##class(OcuTalon.Install.Step.Web).TraceApp("OCUTALON", .props)
	Set props("CookiePath") = ..Application_"/"
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Apply(..Application, .props), "Apply creates the application")
	Do $$$AssertEquals(..Application(.stored), 1, "the application exists")
	Do ..AssertProperties(.props, .stored, "created")
	Do $$$AssertEquals($Get(stored("CorsAllowlist")), "", "no CORS list")

	Kill changes
	Set changes("Enabled") = 0
	Set changes("Timeout") = 100
	Set changes("ServeFiles") = 3
	Set changes("GroupById") = "ZzOther"
	Set changes("PermittedClasses") = ""
	Set changes("AutheEnabled") = 64
	Set changes("CorsAllowlist") = "https://zz.example.com"
	Do ..ModifyApplication(.changes)
	Do ..Application(.stored)
	Do $$$AssertEquals(stored("Timeout"), 100, "the timeout was changed by hand")
	Do $$$AssertEquals(stored("GroupById"), "ZzOther", "the group was changed by hand")
	Do $$$AssertEquals(stored("CorsAllowlist"), "https://zz.example.com", "a CORS list was added by hand")

	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Apply(..Application, .props), "Apply modifies the application")
	Do ..Application(.stored)
	Do ..AssertProperties(.props, .stored, "restored")
	Do $$$AssertEquals($Get(stored("CorsAllowlist")), "", "the CORS list added by hand is gone")
}

/// The bundle folder must hold index.html; the error names the path that is missing.
Method TestBundleCheck()
{
	Do ##class(%File).CreateDirectoryChain(..Directory)
	Set index = ..Directory_"index.html"
	Do ##class(%File).Delete(index)
	Set sc = ##class(OcuTalon.Install.Step.Web).BundleCheck(..Directory)
	Do $$$AssertStatusNotOK(sc, "BundleCheck fails without index.html")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ index, "the error names the path: "_$SYSTEM.Status.GetErrorText(sc))
	Set sc = ##class(OcuTalon.Install.Step.Web).BundleCheck($Extract(..Directory, 1, $Length(..Directory) - 1))
	Do $$$AssertStatusNotOK(sc, "the folder name without its trailing separator fails the same way")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ index, "and names the same path")

	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(index)
	Do stream.Write("<!doctype html>")
	Do $$$AssertStatusOK(stream.%Save(), "index.html is written")
	Kill stream
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).BundleCheck(..Directory), "BundleCheck passes with index.html")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).BundleCheck($Extract(..Directory, 1, $Length(..Directory) - 1)), "and without the trailing separator")
}

/// The trace role's SQL privilege is granted once, in the current namespace, to the role that is named.
Method TestGrantTraceSql()
{
	Do $$$AssertEquals($SYSTEM.SQL.Security.CheckPrivilege(..RoleA, 1, "Ens.MessageHeader", "s"), 0, "the fixture role holds no privilege to begin with")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).GrantTraceSql(..RoleA), "GrantTraceSql")
	Do $$$AssertEquals($SYSTEM.SQL.Security.CheckPrivilege(..RoleA, 1, "Ens.MessageHeader", "s"), 1, "SELECT on Ens.MessageHeader")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).GrantTraceSql(..RoleA), "GrantTraceSql again")
	Do $$$AssertEquals($SYSTEM.SQL.Security.CheckPrivilege(..RoleA, 1, "Ens.MessageHeader", "s"), 1, "still SELECT")
	Do $$$AssertEquals($SYSTEM.SQL.Security.CheckPrivilege(..RoleB, 1, "Ens.MessageHeader", "s"), 0, "another role holds nothing")
	Do $$$AssertEquals($SYSTEM.SQL.Security.CheckPrivilege(..RoleA, 1, "Ens.MessageHeader", "i"), 0, "and the role holds no more than SELECT")
}

/// --- fixtures ---
/// The table of the Design Notes for an application: expected(key) = value.
ClassMethod Expected(name As %String, Output expected) [ Private ]
{
	Kill expected
	Set expected("NameSpace") = "OCUTALON"
	Set expected("Enabled") = 1
	Set expected("AutheEnabled") = 32
	Set expected("GroupById") = "OcuTalon"
	Set expected("SessionScope") = 2
	Set expected("Timeout") = 28800
	Set expected("LoginPage") = ""
	Set expected("InbndWebServicesEnabled") = 0
	Set expected("IsNameSpaceDefault") = 0
	Set expected("AutoCompile") = 0
	Set expected("CSPZENEnabled") = 1
	Set expected("CorsAllowlist") = ""
	If name = "/ocutalon/trace/ocutalon" {
		Set expected("DispatchClass") = ""
		Set expected("Path") = ""
		Set expected("ServeFiles") = 1
		Set expected("CookiePath") = "/ocutalon/trace/ocutalon/"
		Set expected("MatchRoles") = ""
		Set expected("PermittedClasses") = ..SevenClasses()
		Quit
	}
	Set expected("CookiePath") = "/ocutalon/"
	Set expected("MatchRoles") = ":%DB_OCUTALON_CODE:%DB_OCUTALON_DATA:%DB_OCUTALON_PRIVATE"
	Set expected("PermittedClasses") = ""
	If name = "/ocutalon" {
		Set expected("DispatchClass") = "OcuTalon.Web.Public.Shell"
		Set expected("Path") = $SYSTEM.Util.DataDirectory()_"csp/ocutalon/"
		Set expected("ServeFiles") = 3
	} Else {
		Set expected("DispatchClass") = "OcuTalon.Web.Api"
		Set expected("Path") = ""
		Set expected("ServeFiles") = 0
	}
}

/// AD-24's seven classes, as S7 tested them.
ClassMethod SevenClasses() As %String [ Private ]
{
	Quit "1(1""%CSP.Broker"",1""EnsPortal.VisualTrace"",1""EnsPortal.SVG.VisualTrace"",1""EnsPortal.VisualTraceLegend"",1""EnsPortal.SVG.TraceLegend"",1""EnsPortal.MessageContents"",1""EnsPortal.MessageViewer"")"
}

/// 1 for a resource that no OcuTalon role may hold (AD-24).
ClassMethod Forbidden(resource As %String) As %Boolean [ Private ]
{
	If $ListFind($ListBuild("%All", "%Development", "%Ens_MessageEditResend", "%Ens_MessageDiscard", "%Ens_ProductionRun", "%Ens_ProductionConfig", "%DB_OCUTALON_PRIVATE", "%DB_OCUTALON_PUBLIC"), resource) Quit 1
	Quit $Extract(resource, 1, 13) = "%Ens_Workflow"
}

/// Asserts that every given property is stored with that value.
Method AssertProperties(ByRef props, ByRef stored, label As %String) [ Private ]
{
	Set key = ""
	For {
		Set key = $Order(props(key))
		Quit:key=""
		Do $$$AssertEquals($Get(stored(key), "<undefined>"), props(key), label_" "_key)
	}
}

/// 1 when the fixture application exists; stored(property) holds its properties.
Method Application(Output stored) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill stored
	If '##class(Security.Applications).Exists(..Application) Quit 0
	Do ##class(Security.Applications).Get(..Application, .stored)
	Quit 1
}

Method ModifyApplication(ByRef changes) [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Do ##class(Security.Applications).Modify(..Application, .changes)
}

Method RemoveApplication() [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Applications).Exists(..Application) Do ##class(Security.Applications).Delete(..Application)
}

Method CreateRoles() As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set sc = ##class(Security.Roles).Create(..RoleA, "OcuTalon test fixture", "")
	If $SYSTEM.Status.IsOK(sc) Set sc = ##class(Security.Roles).Create(..RoleB, "OcuTalon test fixture", "")
	Quit sc
}

/// Deletes every fixture application and role that an earlier run may have left, with the role's SQL
/// privilege, and the fixture's nodes.
ClassMethod Clean() [ Private ]
{
	Kill ^OcuTalonTest("WebInstall")
	New $Namespace
	Set home = $Namespace
	Set $Namespace = "%SYS"
	Set roles = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Roles WHERE Name %STARTSWITH 'ZzWeb'")
	While result.%Next() {
		Set roles = roles_$ListBuild(result.%GetData(1))
	}
	Set position = 0
	While $ListNext(roles, position, role) {
		Set $Namespace = home
		Do $SYSTEM.SQL.Security.RevokePrivilege("SELECT", "Ens.MessageHeader", "TABLE", role)
		Set $Namespace = "%SYS"
		Do ##class(Security.Roles).Delete(role)
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Applications WHERE Name %STARTSWITH '/zzweb'")
	While result.%Next() {
		Do ##class(Security.Applications).Delete(result.%GetData(1))
	}
}

}
