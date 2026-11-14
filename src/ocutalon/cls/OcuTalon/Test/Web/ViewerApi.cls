/// Tests of the viewer role at the API (Story 25.4; AD-13, AD-24; Planner rulings C2 and C-24h), through Test.Web.ApiProbe and the stand-in request and response
/// objects, with the roles of the signed-in user from its seam. They change nothing: no row, no security object. The probe answers the live role set as the same roles.
///   - TestEveryWriteRouteRefusesAViewer: every Route and Map of Web.Api's compiled UrlMap and of each class it forwards to is enumerated; for the role OcuTalonViewer each
///     route whose method is not GET is 403 read_only from OnPreDispatch with the dispatch stopped, POST /v1/session/end passes, and so does every GET route but the two
///     memory reads that submit a command;
///   - TestEveryGetRouteIsClassified: the GET routes are exactly the ones this class knows, each read-only except the memory items and pinned reads (C2), so that a new GET
///     route that writes must be decided here;
///   - TestMemoryReadsRefuseAViewer: GET /v1/memory/items (with and without q) and /v1/memory/pinned are 403 read_only for a viewer, with the dispatch stopped before any
///     route runs (so nothing is submitted), and pass for a user;
///   - TestViewerAndUser: with OcuTalonViewer and OcuTalonUser nothing is refused, and viewer is false;
///   - TestViewerAndAdmin: with OcuTalonViewer and OcuTalonAdmin, POST /v1/settings/budgets is read_only, the settings reads (GET /v1/settings, the webhooks and the Roles
///     list, which submits a command) are 403 not_admin, and admin is false;
///   - TestHasRole: Shell.HasRole admits the viewer and the user and refuses OcuTalonTraceViewer alone, and ViewerOnly is true only for the viewer without the user role;
///   - TestStateFlags: /v1/state's viewer, admin and rolesAssignable for each role set, with the flag of the roles' existence on and off;
///   - TestDemoAccount: the demo account's roles with the online demo forced give admin, viewer and rolesAssignable false, and the Roles routes 403 not_admin;
///   - TestLiveRolesRefusal: a user whose live roles hold neither role gets 401 signed_out and the CSP session ends, and one whose live read fails gets 500 server_error
///     with the session kept;
///   - TestStateFollowsLiveRoles: /v1/state's viewer and admin read the live roles too, so a user cut down to the viewer role is a viewer there;
///   - TestAdminFollowsLiveRoles: OcuTalonAdmin is read from the live roles and not from the session's: a user whose live roles lost it is 403 not_admin on /v1/settings,
///     below it and on the Roles routes, with the session kept and admin false in /v1/state; a live read that fails refuses that one request with 500 server_error, keeps the
///     session, and leaves no admin in /v1/state; with the role live again GET /v1/settings goes on and admin is true in /v1/state.
Class OcuTalon.Test.Web.ViewerApi Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Web.ApiProbe";

/// The GET routes that submit a command or write a row for the caller, so that a viewer is refused them (Planner ruling C2).
Parameter WRITINGGETS = "/v1/memory/items,/v1/memory/pinned";

/// The GET routes of the release, as "<url>" with each :name kept, comma-separated. A GET route that is not here must be classified before this class passes.
Parameter GETROUTES = "/v1/state,/v1/events,/v1/persona,/v1/heartbeat,/v1/memory/precedents,/v1/memory/notes,/v1/memory/items,/v1/memory/pinned,/v1/settings,/v1/documents,/v1/documents/:ref,/v1/usage,/v1/history/decisions,/v1/history/incidents,/v1/settings/channels/webhooks,/v1/settings/roles";

Property SavedOnline As %String;

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("ApiProbe")
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("ApiProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $$$OK
}

Method TestEveryWriteRouteRefusesAViewer()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonViewer"
	Set routes = ..Routes()
	Do $$$AssertTrue(routes.%Size() > 40, "the routes are read: "_routes.%Size())
	Set refused = 0, passed = 0
	For i = 0:1:routes.%Size() - 1 {
		Set route = routes.%Get(i)
		Set label = route.method_" "_route.url
		Set written = ..PreDispatch(route.url, route.method, .continue)
		If (route.method = "POST") && (route.url = "/v1/session/end") {
			Do $$$AssertEquals(continue, 1, label_": a viewer may sign out")
			Do $$$AssertTrue(written '[ "read_only", label_": with no refusal")
			Set passed = passed + 1
		} ElseIf route.method '= "GET" {
			Do $$$AssertEquals(continue, 0, label_": the dispatch stops")
			Do $$$AssertTrue(written [ """read_only""", label_": 403 read_only")
			Set refused = refused + 1
		} ElseIf ..Writes(route.url) {
			Do $$$AssertEquals(continue, 0, label_": a GET that submits a command stops")
			Do $$$AssertTrue(written [ """read_only""", label_": 403 read_only")
		} ElseIf $Extract(route.url, 1, 12) = "/v1/settings" {
			Do $$$AssertTrue(written [ """not_admin""", label_": a viewer is no admin, so a settings read stops at the admin check")
			Do $$$AssertTrue(written '[ "read_only", label_": and not as read_only")
		} Else {
			Do $$$AssertEquals(continue, 1, label_": a read passes")
			Do $$$AssertTrue(written '[ "read_only", label_": with no refusal")
			Set passed = passed + 1
		}
	}
	Do $$$AssertTrue(refused > 20, "many write routes were refused: "_refused)
	Do $$$AssertTrue(passed > 10, "and the reads passed: "_passed)
}

Method TestEveryGetRouteIsClassified()
{
	Set routes = ..Routes()
	Set found = "", known = ..#GETROUTES
	For i = 0:1:routes.%Size() - 1 {
		Set route = routes.%Get(i)
		If route.method '= "GET" Continue
		Do $$$AssertTrue($ListFind($ListFromString(known), route.url), "GET "_route.url_" is a route this class has classified")
		Set found = found_$ListBuild(route.url)
	}
	Set position = 0
	Set list = $ListFromString(known)
	While $ListNext(list, position, url) {
		Do $$$AssertTrue($ListFind(found, url), "the classified route GET "_url_" exists")
	}
	Set position = 0
	Set writing = $ListFromString(..#WRITINGGETS)
	While $ListNext(writing, position, url) {
		Do $$$AssertTrue($ListFind(list, url), "the GET route that writes, "_url_", is among them")
	}
}

Method TestMemoryReadsRefuseAViewer()
{
	For url = "/v1/memory/items", "/v1/memory/items?q=zz", "/v1/memory/pinned", "/V1/Memory/Items?q=a%20b" {
		Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonViewer"
		Set written = ..PreDispatch(url, "GET", .continue)
		Do $$$AssertEquals(continue, 0, url_": a viewer's dispatch stops")
		Do $$$AssertEquals(..Status, "403 Forbidden", url_": with status 403")
		Do $$$AssertTrue(written [ """read_only""", url_": 403 read_only")
		Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
		Set written = ..PreDispatch(url, "GET", .continue)
		Do $$$AssertEquals(continue, 1, url_": a user's passes")
	}
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonViewer"
	Set written = ..PreDispatch("/v1/memory/precedents", "GET", .continue)
	Do $$$AssertEquals(continue, 1, "a read that submits nothing still passes for a viewer")
}

Method TestViewerAndUser()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonViewer,OcuTalonUser"
	Set routes = ..Routes()
	For i = 0:1:routes.%Size() - 1 {
		Set route = routes.%Get(i)
		Set written = ..PreDispatch(route.url, route.method, .continue)
		Do $$$AssertTrue(written '[ "read_only", route.method_" "_route.url_": nothing is refused as read_only")
		If (route.method '= "GET") && (route.url '[ "/settings") Do $$$AssertEquals(continue, 1, route.method_" "_route.url_": the dispatch goes on")
	}
	Do $$$AssertEquals(..State("OcuTalonViewer,OcuTalonUser").viewer, 0, "viewer is false for a user who also holds the viewer role")
}

Method TestViewerAndAdmin()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonViewer,OcuTalonAdmin"
	Set written = ..PreDispatch("/v1/settings/budgets", "POST", .continue)
	Do $$$AssertEquals(continue, 0, "the dispatch stops")
	Do $$$AssertTrue(written [ """read_only""", "POST /v1/settings/budgets is 403 read_only")
	For url = "/v1/settings", "/v1/settings/channels/webhooks", "/v1/settings/roles" {
		Set written = ..PreDispatch(url, "GET", .continue)
		Do $$$AssertEquals(continue, 0, "GET "_url_": the dispatch stops")
		Do $$$AssertTrue(written [ """not_admin""", "GET "_url_": 403 not_admin, as admin is false in /v1/state")
	}
	Set body = ..State("OcuTalonViewer,OcuTalonAdmin")
	Do $$$AssertEquals(body.admin, 0, "admin is false")
	Do $$$AssertEquals(body.viewer, 1, "viewer is true")
}

Method TestHasRole()
{
	Set shell = "OcuTalon.Web.Public.Shell"
	Do $$$AssertEquals($ClassMethod(shell, "HasRole", "OcuTalonViewer"), 1, "HasRole admits the viewer")
	Do $$$AssertEquals($ClassMethod(shell, "HasRole", "OcuTalonUser"), 1, "and the user")
	Do $$$AssertEquals($ClassMethod(shell, "HasRole", "%DB_X,OcuTalonViewer,%All"), 1, "by the whole name in a list")
	Do $$$AssertEquals($ClassMethod(shell, "HasRole", "OcuTalonTraceViewer"), 0, "and refuses OcuTalonTraceViewer alone")
	Do $$$AssertEquals($ClassMethod(shell, "HasRole", "OcuTalonViewerX,XOcuTalonUser,%All"), 0, "a name that only contains a role is not the role")
	Do $$$AssertEquals($ClassMethod(shell, "HasRole", ""), 0, "and an empty list holds neither")
	Do $$$AssertEquals($ClassMethod(shell, "ViewerOnly", "OcuTalonViewer"), 1, "ViewerOnly is true for the viewer alone")
	Do $$$AssertEquals($ClassMethod(shell, "ViewerOnly", "OcuTalonViewer,OcuTalonUser"), 0, "and false with the user role")
	Do $$$AssertEquals($ClassMethod(shell, "ViewerOnly", "OcuTalonUser"), 0, "and for the user alone")
	Do $$$AssertEquals($ClassMethod(shell, "ViewerOnly", "OcuTalonTraceViewer"), 0, "and for the trace viewer")
}

Method TestStateFlags()
{
	Set cases = $ListBuild(
		"OcuTalonUser|0|0|0", "OcuTalonViewer|1|0|0", "OcuTalonViewer,OcuTalonUser|0|0|0", "OcuTalonUser,OcuTalonAdmin|0|1|0", "OcuTalonViewer,OcuTalonAdmin|1|0|0",
		"OcuTalonUser,%All|0|0|0")
	For ready = 0, 1 {
		Set ^OcuTalonTest("ApiProbe", "rolesReady") = ready
		Set position = 0
		While $ListNext(cases, position, case) {
			Set roles = $Piece(case, "|", 1)
			Set body = ..State(roles)
			Set label = roles_" (roles exist "_ready_")"
			Do $$$AssertEquals(body.%GetTypeOf("viewer")_body.%GetTypeOf("rolesAssignable"), "booleanboolean", label_": both are booleans")
			Do $$$AssertEquals(body.viewer, +$Piece(case, "|", 2), label_": viewer")
			Do $$$AssertEquals(body.admin, +$Piece(case, "|", 3), label_": admin")
			Do $$$AssertEquals(body.rolesAssignable, ready, label_": rolesAssignable follows the roles' existence")
			Set keys = ""
			Set iterator = body.%GetIterator()
			While iterator.%GetNext(.key) {
				Set keys = keys_$Select(keys = "": "", 1: ",")_key
			}
			Do $$$AssertTrue(keys [ "demoMode,filesReadable,viewer,rolesAssignable,models", label_": the keys follow filesReadable in that order: "_keys)
		}
	}
}

Method TestDemoAccount()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set ^OcuTalonTest("ApiProbe", "rolesReady") = 1
	Set roles = "OcuTalonUser,OcuTalonTraceViewer,OcuTalonApprover"
	Set ^OcuTalonTest("ApiProbe", "roles") = roles
	Set body = ..State(roles)
	Do $$$AssertEquals(body.onlineDemo, 1, "control: the online demo is on")
	Do $$$AssertEquals(body.admin, 0, "admin is false")
	Do $$$AssertEquals(body.viewer, 0, "viewer is false")
	Do $$$AssertEquals(body.rolesAssignable, 0, "rolesAssignable is false even when the roles exist")
	For method = "GET", "POST" {
		Set written = ..PreDispatch("/v1/settings/roles", method, .continue)
		Do $$$AssertEquals(continue, 0, method_" /v1/settings/roles stops")
		Do $$$AssertTrue(written [ """not_admin""", "with 403 not_admin")
	}
	Set written = ..PreDispatch("/v1/messages", "POST", .continue)
	Do $$$AssertEquals(continue, 1, "the demo account's own requests go on")
}

Method TestLiveRolesRefusal()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	Set ^OcuTalonTest("ApiProbe", "liveRoles") = "OcuTalonTraceViewer"
	Set written = ..PreDispatch("/v1/state", "GET", .continue)
	Do $$$AssertEquals(continue, 0, "a user whose live roles hold neither role is stopped")
	Do $$$AssertTrue(written [ """signed_out""", "with 401 signed_out")
	Do $$$AssertEquals(..Ended, 1, "and the CSP session is ended")
	Set ^OcuTalonTest("ApiProbe", "liveRoles") = ""
	Set written = ..PreDispatch("/v1/state", "GET", .continue)
	Do $$$AssertEquals(continue, 0, "so is one whose live roles are empty")
	Do $$$AssertTrue(written [ """signed_out""", "with 401 signed_out")
	Set ^OcuTalonTest("ApiProbe", "liveRoles") = "OcuTalonViewer"
	Set written = ..PreDispatch("/v1/state", "GET", .continue)
	Do $$$AssertEquals(continue, 1, "a live viewer is read-only but not signed out")
	Set written = ..PreDispatch("/v1/messages", "POST", .continue)
	Do $$$AssertTrue(written [ """read_only""", "and a user whose live roles were cut down to the viewer role is read-only at once")
	Set ^OcuTalonTest("ApiProbe", "liveRoles") = "OcuTalonUser"
	Set written = ..PreDispatch("/v1/state", "GET", .continue)
	Do $$$AssertEquals(continue, 1, "a live user goes on")
	Kill ^OcuTalonTest("ApiProbe", "liveRoles")
	Set ^OcuTalonTest("ApiProbe", "liveError") = 1
	Set written = ..PreDispatch("/v1/state", "GET", .continue)
	Do $$$AssertEquals(continue, 0, "a live read that fails stops the one request")
	Do $$$AssertTrue(written [ """server_error""", "with 500 server_error, not 401")
	Do $$$AssertTrue(written '[ "signed_out", "so the answer is not signed_out")
	Do $$$AssertEquals(..Ended, 0, "and the session is not ended")
}

Method TestStateFollowsLiveRoles()
{
	Set ^OcuTalonTest("ApiProbe", "liveRoles") = "OcuTalonViewer"
	Set body = ..State("OcuTalonUser,OcuTalonAdmin")
	Do $$$AssertEquals(body.viewer, 1, "a user whose live roles were cut down to the viewer role is a viewer in /v1/state")
	Do $$$AssertEquals(body.admin, 0, "and not an admin")
	Kill ^OcuTalonTest("ApiProbe", "liveRoles")
	Set body = ..State("OcuTalonUser,OcuTalonAdmin")
	Do $$$AssertEquals(body.viewer, 0, "with the live roles back, viewer is false")
	Do $$$AssertEquals(body.admin, 1, "and admin is true")
}

Method TestAdminFollowsLiveRoles()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set ^OcuTalonTest("ApiProbe", "liveRoles") = "OcuTalonUser"
	For request = "GET|/v1/settings", "POST|/v1/settings/budgets", "GET|/v1/settings/channels/webhooks", "GET|/v1/settings/roles", "POST|/v1/settings/roles" {
		Set method = $Piece(request, "|", 1), url = $Piece(request, "|", 2)
		Set written = ..PreDispatch(url, method, .continue)
		Do $$$AssertEquals(continue, 0, method_" "_url_": a user whose live roles lost OcuTalonAdmin is stopped")
		Do $$$AssertTrue(written [ """not_admin""", method_" "_url_": 403 not_admin")
		Do $$$AssertEquals(..Ended, 0, method_" "_url_": and the session is kept")
	}
	Set body = ..State("OcuTalonUser,OcuTalonAdmin")
	Do $$$AssertEquals(body.admin, 0, "admin is false in /v1/state")
	Do $$$AssertEquals(body.viewer, 0, "and viewer is false")
	Set written = ..PreDispatch("/v1/messages", "POST", .continue)
	Do $$$AssertEquals(continue, 1, "the same user's other requests go on")
	Kill ^OcuTalonTest("ApiProbe", "liveRoles")
	Set ^OcuTalonTest("ApiProbe", "liveError") = 1
	Set written = ..PreDispatch("/v1/settings", "GET", .continue)
	Do $$$AssertEquals(continue, 0, "a live read that fails stops the one settings request")
	Do $$$AssertTrue(written [ """server_error""", "with 500 server_error")
	Do $$$AssertEquals(..Ended, 0, "and does not end the session")
	Set body = ..State("OcuTalonUser,OcuTalonAdmin")
	Do $$$AssertEquals(body.admin, 0, "no admin is shown while the live read fails")
	Kill ^OcuTalonTest("ApiProbe", "liveError")
	Set written = ..PreDispatch("/v1/settings", "GET", .continue)
	Do $$$AssertEquals(continue, 1, "with the live roles readable and holding the role, GET /v1/settings goes on")
	Set body = ..State("OcuTalonUser,OcuTalonAdmin")
	Do $$$AssertEquals(body.admin, 1, "and admin is true")
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	Set ^OcuTalonTest("ApiProbe", "liveRoles") = "OcuTalonUser,OcuTalonAdmin"
	Set written = ..PreDispatch("/v1/settings", "GET", .continue)
	Do $$$AssertEquals(continue, 1, "a role that the live set holds is read from the live set, not the session's")
}

/// --- helpers ---
/// The routes of Web.Api and, recursively, of each class that a Map forwards to, as an array of {method, url}: a :name in a URL is replaced by zzref.
ClassMethod Routes() As %DynamicArray
{
	Set routes = []
	Do ..Collect("OcuTalon.Web.Api", "", routes)
	Quit routes
}

ClassMethod Collect(class As %String, prefix As %String, routes As %DynamicArray) [ Private ]
{
	Set sc = ##class(%XML.TextReader).ParseStream(##class(%Dictionary.CompiledXData).%OpenId(class_"||UrlMap").Data, .reader)
	If $SYSTEM.Status.IsError(sc) Quit
	While reader.Read() {
		If reader.NodeType '= "element" Continue
		If reader.Name = "Route" {
			Do reader.MoveToAttributeName("Url")
			Set url = reader.Value
			Do reader.MoveToAttributeName("Method")
			Set method = reader.Value
			Do routes.%Push({"method": (method), "url": (prefix_url)})
		} ElseIf reader.Name = "Map" {
			Do reader.MoveToAttributeName("Prefix")
			Set mapPrefix = reader.Value
			Do reader.MoveToAttributeName("Forward")
			Set forward = reader.Value
			Do ..Collect(forward, prefix_mapPrefix, routes)
		}
	}
}

/// 1 when the GET route submits a command or writes a row for the caller (WRITINGGETS), whatever its query.
ClassMethod Writes(url As %String) As %Boolean [ Private ]
{
	Quit ''$ListFind($ListFromString(..#WRITINGGETS), $ZConvert($Piece(url, "?", 1), "L"))
}

/// 1 when the stand-in session of the last PreDispatch was ended (EndSession).
Property Ended As %Boolean [ Private ];

/// The response status that the last PreDispatch left.
Property Status As %String [ Private ];

/// Runs OnPreDispatch of Web.Api's probe for the URL and method with a stand-in request; returns what it wrote. continue is the dispatch flag it left.
Method PreDispatch(url As %String, method As %String, Output continue) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", method, "application/json", 1, "http://localhost", "localhost")
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New("ZzViewerApi", 0)
	Set %response.ContentType = ""
	Set continue = 1
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, "OnPreDispatch", $Translate(url, ":", "z"), method, .continue)
	Do $$$AssertStatusOK(sc, "OnPreDispatch returns OK")
	Set ..Ended = +%session.EndSession
	Set ..Status = %response.Status
	Quit written
}

/// The snapshot (Api.StateBody) of a session for a fixture user, with the probe's roles set to the list.
Method State(roles As %String) As %DynamicObject [ Private ]
{
	Set ^OcuTalonTest("ApiProbe", "roles") = roles
	Set session = ##class(OcuTalon.Data.Session).ForUser("zzviewerapi"_$Job, .sc)
	Do $$$AssertStatusOK(sc, "the fixture session")
	Set body = $ClassMethod(..#PROBE, "StateBody", session)
	Do ##class(OcuTalon.Test.Data.Fixture).Clean($Select($IsObject(session): session.Ref, 1: ""))
	Quit body
}

}
