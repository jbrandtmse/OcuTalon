/// Tests of the live role re-read of Web.Api OnPreDispatch (Story 25.4; AD-13; Planner ruling C-24h), over real HTTP against the instance's own web server, with a real
/// CSP session. THROWAWAY STACKS AND CI ONLY (Rule 21): they create and delete security users and roles, and change a user's roles while its session is open.
/// Test.Core.AnswersInWebRoles.Reason refuses everything else. The fixture users have the prefix ZzLiveRoles; the fixture roles are Test.Install.RolesAssign's.
///   - TestRemovedViewerEndsItsSession: a viewer who is signed in reads /v1/state, has OcuTalonViewer removed, and on its next request, on the same session, gets 401
///     signed_out, and the session is over (it stays 401 when the user is given the role back);
///   - TestRemovedUserEndsItsSession: the same for a user whose OcuTalonUser is removed;
///   - TestHoldingBothRolesIsUnaffected: a user who holds both roles and loses one still reads /v1/state;
///   - TestRereadCostIsSmall: the re-read ($SYSTEM.Security.GetUserRecursedRoleSet of the job's own name, in a job that holds the roles of a web request and not
///     %Admin_Secure) needs no privilege, and its p95 over 250 calls is under 5 ms (the bound that decides whether a per-session cache is needed); the p95 and the
///     median are left under ^OcuTalonTest("LiveRolesApi", "cost").
Class OcuTalon.Test.Web.LiveRolesApi Extends %UnitTest.TestCase
{

Parameter USER = "ZzLiveRoles";

Parameter PORT = 52773;

/// The calls that Measure makes.
Parameter CALLS = 250;

/// The most milliseconds that the 95th percentile of the re-read may take.
Parameter P95MAX = 5;

Property Missing As %String(MAXLEN = 300);

Property Created As %String;

Method OnBeforeAllTests() As %Status
{
	Set running = ##class(Ens.Director).IsProductionRunning(.name)
	Set ..Missing = ##class(OcuTalon.Test.Core.AnswersInWebRoles).Reason($SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL"), $SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER"), running, $Get(name))
	If ..Missing '= "" Quit $SYSTEM.Status.Error(5001, ..Missing)
	Do ..Clean()
	Set ..Created = ##class(OcuTalon.Test.Install.RolesAssign).EnsureRoles()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If ..Missing '= "" Quit $$$OK
	Do ..Clean()
	Do ##class(OcuTalon.Test.Install.RolesAssign).DropRoles(..Created)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Missing = "" Do ..Clean()
	Kill ^OcuTalonTest("LiveRolesApi", "job")
	Quit $$$OK
}

Method TestRemovedViewerEndsItsSession()
{
	If '..Guard() Quit
	Set user = ..#USER_"v"
	Set password = ..NewUser(user, "OcuTalonViewer")
	Set request = ..SignIn(user, password)
	Do $$$AssertEquals(..State(request, .body), 200, "the viewer's /v1/state answers 200")
	Do $$$AssertEquals(body.viewer, 1, "viewer is true")
	Do $$$AssertEquals(body.admin, 0, "and admin false")
	Do $$$AssertEquals(..Remove(user, "OcuTalonViewer"), 1, "the role is removed while the session is open")
	Do $$$AssertEquals(..State(request, .body), 401, "the next request on the same session is 401")
	Do $$$AssertEquals(body.error.code, "signed_out", "signed_out")
	Do $$$AssertEquals(..Add(user, "OcuTalonViewer"), 1, "the role is given back")
	Do $$$AssertEquals(..State(request, .body), 401, "the session is over: the next request is 401 although the user holds the role again")
	Do $$$AssertEquals(body.error.code, "signed_out", "signed_out")
}

Method TestRemovedUserEndsItsSession()
{
	If '..Guard() Quit
	Set user = ..#USER_"u"
	Set password = ..NewUser(user, "OcuTalonUser")
	Set request = ..SignIn(user, password)
	Do $$$AssertEquals(..State(request, .body), 200, "the user's /v1/state answers 200")
	Do $$$AssertEquals(body.viewer, 0, "viewer is false")
	Do $$$AssertEquals(..Remove(user, "OcuTalonUser"), 1, "OcuTalonUser is removed while the session is open")
	Do $$$AssertEquals(..State(request, .body), 401, "the next request on the same session is 401")
	Do $$$AssertEquals(body.error.code, "signed_out", "signed_out")
}

Method TestHoldingBothRolesIsUnaffected()
{
	If '..Guard() Quit
	Set user = ..#USER_"b"
	Set password = ..NewUser(user, "OcuTalonUser,OcuTalonViewer")
	Set request = ..SignIn(user, password)
	Do $$$AssertEquals(..State(request, .body), 200, "the /v1/state of a user with both roles answers 200")
	Do $$$AssertEquals(body.viewer, 0, "and the user is no viewer")
	Do $$$AssertEquals(..Remove(user, "OcuTalonViewer"), 1, "one role is removed")
	Do $$$AssertEquals(..State(request, .body), 200, "the same session still answers 200")
	Do $$$AssertEquals(..State(request, .body), 200, "and again")
}

Method TestRereadCostIsSmall()
{
	If '..Guard() Quit
	Set user = ..#USER_"c"
	Do ..NewUser(user, "OcuTalonUser"_##class(OcuTalon.Test.Install.RolesAssign).AppRoles())
	Set run = $Name(^OcuTalonTest("LiveRolesApi", "job"))
	Kill @run
	Job ##class(OcuTalon.Test.Web.LiveRolesApi).Measure(user)
	Set finished = ##class(OcuTalon.Test.Agent.RunnerFixture).WaitFor($Name(@run@("done")), 120)
	Do $$$AssertTrue(finished, "the job reports")
	Do $$$AssertEquals($Get(@run@("error")), "", "and threw nothing: "_$Get(@run@("error")))
	Do $$$AssertEquals($Get(@run@("login")), 1, "control: the job logged in as the fixture user")
	Do $$$AssertEquals($Get(@run@("privilege")), 0, "control: the job holds no %Admin_Secure:USE")
	Do $$$AssertEquals($Get(@run@("status")), 1, "the re-read of the job's own name is OK without it")
	Do $$$AssertTrue($Get(@run@("roles")) [ "OcuTalonUser", "and answers the user's roles")
	Do $$$AssertTrue($Get(@run@("p95"), 999) < ..#P95MAX, "its p95 over "_..#CALLS_" calls is under "_..#P95MAX_" ms: "_$Get(@run@("p95")))
	Set ^OcuTalonTest("LiveRolesApi", "cost") = "p95 "_$Get(@run@("p95"))_" ms, median "_$Get(@run@("median"))_" ms, max "_$Get(@run@("max"))_" ms over "_..#CALLS_" calls"
}

/// The job: logs in as the user (no password), reads its own recursed role set CALLS times and reports the times in milliseconds.
ClassMethod Measure(user As %String)
{
	Set run = $Name(^OcuTalonTest("LiveRolesApi", "job"))
	Try {
		Set @run@("login") = $SYSTEM.Security.Login(user)
		Set @run@("privilege") = +$SYSTEM.Security.Check("%Admin_Secure", "USE")
		Kill times
		For i = 1:1:..#CALLS {
			Set start = $ZHorolog
			Set sc = $SYSTEM.Security.GetUserRecursedRoleSet($Username, .roles)
			Set times(i) = ($ZHorolog - start) * 1000
			If i = 1 Set @run@("status") = $SYSTEM.Status.IsOK(sc), @run@("roles") = roles
		}
		Set sorted = ""
		For i = 1:1:..#CALLS Set ordered(times(i), i) = ""
		Set count = 0, key = ""
		For {
			Set key = $Order(ordered(key))
			Quit:key=""
			Set at = ""
			For {
				Set at = $Order(ordered(key, at))
				Quit:at=""
				Set count = count + 1
				Set value(count) = key
			}
		}
		Set @run@("p95") = $Fnumber(value($Justify(..#CALLS * 0.95, 0, 0)), "", 3)
		Set @run@("median") = $Fnumber(value($Justify(..#CALLS * 0.5, 0, 0)), "", 3)
		Set @run@("max") = $Fnumber(value(..#CALLS), "", 3)
	} Catch exception {
		Set @run@("error") = exception.DisplayString()
	}
	Set @run@("done") = 1
}

/// --- helpers ---
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// Creates the fixture user with the roles (a comma list; a caller that needs the application roles of a web request adds them); returns its (random) password.
Method NewUser(user As %String, roles As %String) As %String [ Private ]
{
	Set password = "Zz"_$TR($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(18)), "+/=", "abc")_"xY9"
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(user) Do ##class(Security.Users).Delete(user)
	Set sc = ##class(Security.Users).Create(user, roles, password, "OcuTalon test fixture", , , , 0, 1)
	Set $Namespace = "OCUTALON"
	Do $$$AssertStatusOK(sc, "the fixture user "_user_" is created with "_roles)
	Quit password
}

/// Removes the role from the user (in %SYS); 1 when it worked.
ClassMethod Remove(user As %String, role As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set names = role
	Quit $SYSTEM.Status.IsOK(##class(Security.Users).RemoveRoles(user, .names))
}

/// Gives the role to the user (in %SYS); 1 when it worked.
ClassMethod Add(user As %String, role As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set names = role
	Quit $SYSTEM.Status.IsOK(##class(Security.Users).AddRoles(user, .names))
}

/// An HttpRequest that has signed in to /ocutalon/ as the user and keeps the session's cookies.
Method SignIn(user As %String, password As %String) As %Net.HttpRequest [ Private ]
{
	Set request = ##class(%Net.HttpRequest).%New()
	Set request.Server = "127.0.0.1"
	Set request.Port = ..#PORT
	Set request.FollowRedirect = 0
	Do request.Get("/ocutalon/")
	Do request.InsertFormData("IRISUsername", user)
	Do request.InsertFormData("IRISPassword", password)
	Do request.InsertFormData("IRISLogin", "Login")
	Set sc = request.Post("/ocutalon/")
	Do $$$AssertStatusOK(sc, "the sign-in is sent")
	Quit request
}

/// GET /ocutalon/api/v1/state on the signed-in request; the status, and the body as an object in body (empty for a body that is not JSON).
Method State(request As %Net.HttpRequest, Output body As %DynamicObject) As %Integer [ Private ]
{
	Set body = {}
	Set sc = request.Get("/ocutalon/api/v1/state")
	If $SYSTEM.Status.IsError(sc) || '$IsObject(request.HttpResponse) Quit 0
	Try {
		Set text = request.HttpResponse.Data.Read(3000000)
		Set body = ##class(%DynamicAbstractObject).%FromJSON(text)
	} Catch {
		Set body = {}
	}
	Quit request.HttpResponse.StatusCode
}

/// Deletes the fixture users.
ClassMethod Clean() [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Users WHERE Name %STARTSWITH ?", ..#USER)
	While result.%Next() {
		Do ##class(Security.Users).Delete(result.%GetData(1))
	}
}

}
