/// Tests of the Slack settings routes (Story 27.3; AD-1, AD-4, AD-13, AD-24), called with stand-in request and response objects through Test.Web.SlackSettingsProbe and a CSP
/// session whose OcuTalon.SessionRef is a fixture session. The probe stands in for Commands.Submit, so no production runs; the real SettingsOps is tested by Test.Core.SettingsSlack and
/// the whole chain by web/e2e/api/slack.spec.ts. The signed-in user's roles come from Test.Web.ApiProbe's seam.
///   - TestRoutes: GET, POST and DELETE reach their verbs (ListSlackLinks, LinkSlackMember, UnlinkSlackMember) with the admin's session and user; the list is answered from its handoff,
///     taken once; the link's user and member reach the operation only in a handoff, and the answers are the specified ones;
///   - TestBodyShape: each body that is not exactly {user, member} of the right types is 400 bad_settings naming the fields, with no handoff and no submit;
///   - TestRefusalTexts: each refusal reason is 400 bad_slack_link with its fields, the reason and its catalog text, {user} filled in the route; an unknown refusal is 500;
///   - TestOutcomes: a not_available result is 409, an unknown Ref 404, a failed or unexpected outcome 500, for each route;
///   - TestNotAdmin, TestViewer: a user with the OcuTalon user role only, and a viewer, get 403 not_admin from OnPreDispatch and from each route itself, with nothing submitted;
///   - TestOnlineDemo: with the online-demo flag set every route is 409 not_available with the text settings.slackOffOnDemo, a malformed body included, with no handoff made and
///     nothing submitted;
///   - TestHandoffDiscarded: when the submit fails or throws, the route answers 500 and the link's handoff is discarded all the same, and a handoff is also gone after a good answer.
Class OcuTalon.Test.Web.SlackSettingsApi Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Web.SlackSettingsProbe";

Parameter URL = "/v1/settings/channels/slack";

/// The online-demo flag before the tests.
Property SavedOnline As %String;

/// The Ref of the fixture session.
Property A As %String;

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("SlackSettingsProbe")
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set ..A = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("ApiProbe")
	Kill ^OcuTalonTest("SlackSettingsProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(..A)
	Quit $$$OK
}

Method TestRoutes()
{
	Set ^OcuTalonTest("SlackSettingsProbe", "listBody") = {"state": "on", "path": "/ocutalon/hook/slack/events", "links": [{"ref": "zzSlackRef000000000009", "user": "sam", "member": "U012AB3CDE"}], "users": ["sam", "pat"]}.%ToJSON()
	Set body = ..Call("List", , .response)
	Do $$$AssertEquals(response.Status, "200 OK", "GET answers 200")
	Set list = {}.%FromJSON(body)
	Do $$$AssertEquals(list.state_"|"_list.path_"|"_list.links.%Size()_"|"_list.users.%Size(), "on|/ocutalon/hook/slack/events|1|2", "with the list that the handoff held")
	Do $$$AssertEquals(list.links.%Get(0).user_"|"_list.links.%Get(0).member, "sam|U012AB3CDE", "and its links")
	Do $$$AssertEquals(..CallClass(1), "OcuTalon.Msg.Command.ListSlackLinks", "GET submitted one ListSlackLinks")
	Do $$$AssertEquals(..Field(1, "sessionRef"), ..A, "for the CSP session's own session")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(^OcuTalonTest("SlackSettingsProbe", "listUri"), .left, 0), "and the list's handoff was taken, so none is left")

	Set body = ..Call("Save", {"user": "sam", "member": " u012ab3cde "}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "POST answers 200")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.result_"|"_answer.message, "done|"_..Text("settings.slackLinked"), "done, with the text of slackLinked")
	Do $$$AssertEquals(answer.link.ref_"|"_answer.link.user_"|"_answer.link.member, "zzSlackRef000000000001|sam|U012AB3CDE", "and the link's Ref, user and member as the operation stores them")
	Do $$$AssertEquals(answer.link.%Size(), 3, "and nothing else of it")
	Do $$$AssertEquals(..CallClass(2), "OcuTalon.Msg.Command.LinkSlackMember", "POST submitted one LinkSlackMember")
	Do $$$AssertEquals(..Field(2, "sessionRef")_"|"_..Field(2, "actingUser"), ..A_"|"_$Username, "for the CSP session's session and the IRIS user of the call")
	Set taken = {}.%FromJSON(^OcuTalonTest("SlackSettingsProbe", "calls", 2, "taken"))
	Do $$$AssertEquals(taken.user_"|"_taken.member_"|"_taken.%Size(), "sam| u012ab3cde |2", "the handoff held exactly the user and the member as typed")
	Do $$$AssertTrue(..Field(2, "handoff") ? 1"secret://handoff/"32AN, "and the command held its uri")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(..Field(2, "handoff"), .left, 0), "which is gone")

	Set body = ..Call("Remove", , .response, "zzSlackRef000000000001")
	Do $$$AssertEquals(response.Status, "200 OK", "DELETE answers 200")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.result_"|"_answer.message, "done|"_..Text("settings.slackUnlinked"), "done, with the text of slackUnlinked")
	Do $$$AssertEquals(..CallClass(3)_"|"_..Field(3, "linkRef")_"|"_..Field(3, "actingUser"), "OcuTalon.Msg.Command.UnlinkSlackMember|zzSlackRef000000000001|"_$Username, "DELETE submitted one UnlinkSlackMember of the Ref")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SlackSettingsProbe", "handoffs")), 1, "and only the link made a handoff")
	Do $$$AssertTrue(##class(OcuTalon.Web.SlackSettings).%GetParameter("REFMAX") = 22, "control: a Ref is 22 characters")
}

Method TestBodyShape()
{
	For body = "", "not json", "[1]", "5", "{}", "{""user"": ""sam""}", "{""member"": ""U012AB3CDE""}", "{""user"": 5, ""member"": ""U012AB3CDE""}", "{""user"": ""sam"", ""member"": null}", "{""user"": ""sam"", ""member"": ""U012AB3CDE"", ""team"": ""T1""}" {
		Set text = ..Call("Save", body, .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", "'"_$Extract(body, 1, 40)_"': 400")
		Set answer = {}.%FromJSON(text)
		Do $$$AssertEquals(answer.error.code, "bad_settings", "bad_settings")
		Do $$$AssertEquals(answer.error.message, ##class(OcuTalon.Web.SlackSettings).#MESSAGEBADSETTINGS, "with the plain not-saved text")
		Do $$$AssertTrue($IsObject(answer.fields), "and the fields")
	}
	Set answer = {}.%FromJSON(..Call("Save", "{""user"": 5, ""member"": ""U012AB3CDE"", ""team"": ""T1""}", .response))
	Do $$$AssertEquals(answer.fields.%Get(0)_"|"_answer.fields.%Get(1)_"|"_answer.fields.%Size(), "user|team|2", "the fields are the wrong ones and the extra one")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SlackSettingsProbe", "submits")), 0, "nothing was submitted")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SlackSettingsProbe", "handoffs")), 0, "and no handoff was made")
}

Method TestRefusalTexts()
{
	Set cases = $ListBuild("bad_member|member|settings.slackBadMemberId", "member_taken|member|settings.slackMemberTaken", "user_taken|user|settings.slackUserTaken", "user_unknown|user|settings.slackUnknownUser", "no_workspace||settings.slackNoWorkspace")
	Set position = 0
	While $ListNext(cases, position, one) {
		Set reason = $Piece(one, "|", 1), field = $Piece(one, "|", 2), key = $Piece(one, "|", 3)
		Set ^OcuTalonTest("SlackSettingsProbe", "result") = {"ok": 0, "outcome": "refused", "message": "", "data": ({"reason": (reason), "field": (field)}.%ToJSON())}.%ToJSON()
		Set text = ..Call("Save", {"user": "sam", "member": "U012AB3CDE"}.%ToJSON(), .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", reason_": 400")
		Set answer = {}.%FromJSON(text)
		Do $$$AssertEquals(answer.error.code, "bad_slack_link", reason_": bad_slack_link")
		Set expected = $Select(key = "settings.slackUserTaken": ..Text(key, {"user": "sam"}), 1: ..Text(key))
		Do $$$AssertEquals(answer.error.message, expected, reason_": with the text of "_key)
		Do $$$AssertEquals(answer.reason, reason, reason_": and the reason")
		Do $$$AssertEquals(answer.fields.%Size()_"|"_answer.fields.%Get(0), $Select(field = "": "0|", 1: "1|"_field), reason_": and the field it names")
	}
	Do $$$AssertTrue(..Text("settings.slackUserTaken", {"user": "sam"}) [ "sam already has a linked Slack member.", "control: the user's name is in the user_taken text")
	Do $$$AssertTrue(..Text("settings.slackUserTaken", {"user": "sam"}) '[ "{user}", "and the slot is filled")
	Set odd = {"reason": "zz_other", "field": "user"}.%ToJSON()
	Set ^OcuTalonTest("SlackSettingsProbe", "result") = {"ok": 0, "outcome": "refused", "message": "", "data": (odd)}.%ToJSON()
	Set text = ..Call("Save", {"user": "sam", "member": "U012AB3CDE"}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "500 Internal Server Error", "a reason that the route does not know is 500")
	Do $$$AssertEquals({}.%FromJSON(text).error.code, "server_error", "server_error")
}

Method TestOutcomes()
{
	Set ^OcuTalonTest("SlackSettingsProbe", "result") = {"ok": 0, "outcome": "not_available", "message": "settings.slackOffOnDemo", "data": ""}.%ToJSON()
	For route = "List", "Save", "Remove" {
		Set text = ..Call(route, $Select(route = "Save": {"user": "sam", "member": "U012AB3CDE"}.%ToJSON(), 1: ""), .response, "zzSlackRef000000000001")
		Do $$$AssertEquals(response.Status, "409 Conflict", route_": a not_available result is 409")
		Do $$$AssertEquals({}.%FromJSON(text).error.code, "not_available", route_": not_available")
	}
	Set ^OcuTalonTest("SlackSettingsProbe", "result") = {"ok": 0, "outcome": "not_found", "message": "", "data": ""}.%ToJSON()
	Set text = ..Call("Remove", , .response, "zzSlackRef000000000001")
	Do $$$AssertEquals(response.Status, "404 Not Found", "an unknown Ref is 404")
	Set answer = {}.%FromJSON(text)
	Do $$$AssertEquals(answer.error.code_"|"_answer.error.message, "not_found|"_##class(OcuTalon.Web.SlackSettings).#MESSAGENOTFOUND, "not_found with the plain not-found text")
	Set submits = +$Get(^OcuTalonTest("SlackSettingsProbe", "submits"))
	For ref = "", $Translate($Justify("", 23), " ", "A") {
		Set text = ..Call("Remove", , .response, ref)
		Do $$$AssertEquals(response.Status, "404 Not Found", "a Ref of "_$Length(ref)_" characters is 404")
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SlackSettingsProbe", "submits")), submits, "without a submit")
	For outcome = "failed", "not_audited", "no_session", "not_allowed", "zz_other" {
		Set ^OcuTalonTest("SlackSettingsProbe", "result") = {"ok": 0, "outcome": (outcome), "message": "", "data": ""}.%ToJSON()
		For route = "List", "Save", "Remove" {
			Set text = ..Call(route, $Select(route = "Save": {"user": "sam", "member": "U012AB3CDE"}.%ToJSON(), 1: ""), .response, "zzSlackRef000000000001")
			Do $$$AssertEquals(response.Status_"|"_{}.%FromJSON(text).error.code, "500 Internal Server Error|server_error", route_": outcome "_outcome_" is 500 server_error")
		}
	}
	Set gone = "secret://handoff/00000000000000000000000000000000"
	Set ^OcuTalonTest("SlackSettingsProbe", "result") = {"ok": 1, "outcome": "listed", "message": "", "data": ({"handoff": (gone)}.%ToJSON())}.%ToJSON()
	Set text = ..Call("List", , .response)
	Do $$$AssertEquals(response.Status, "500 Internal Server Error", "a list whose handoff is gone is 500")
	Set ^OcuTalonTest("SlackSettingsProbe", "result") = {"ok": 1, "outcome": "done", "message": "", "data": "not json"}.%ToJSON()
	Set text = ..Call("Save", {"user": "sam", "member": "U012AB3CDE"}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "500 Internal Server Error", "a link whose answer holds no Ref is 500")
}

Method TestNotAdmin()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	Do ..AssertRefusedEverywhere("403 Forbidden", "not_admin")
	Set ^OcuTalonTest("ApiProbe", "roles") = "%All,OcuTalonUser"
	Set text = ..Call("List", , .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "%All is not the admin role")
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Set ^OcuTalonTest("ApiProbe", "liveRoles") = "OcuTalonUser"
	Do ..AssertRefusedEverywhere("403 Forbidden", "not_admin")
}

Method TestViewer()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonViewer,OcuTalonAdmin"
	Set written = ..PreDispatch(..#URL, "POST", .continue)
	Do $$$AssertEquals(continue, 0, "the dispatch stops")
	Do $$$AssertTrue(written [ """read_only""", "a viewer's POST is 403 read_only from OnPreDispatch")
	Set written = ..PreDispatch(..#URL_"/zzSlackRef000000000001", "DELETE", .continue)
	Do $$$AssertTrue(written [ """read_only""", "and so is its DELETE")
	Set written = ..PreDispatch(..#URL, "GET", .continue)
	Do $$$AssertTrue(written [ """not_admin""", "a viewer is no admin, so its GET is 403 not_admin")
	Do ..AssertRefusedEverywhere("403 Forbidden", "not_admin", 0)
}

Method TestOnlineDemo()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set expected = ##class(OcuTalon.Core.SettingsOps).WebhookFieldText("settings.slackOffOnDemo")
	Do $$$AssertTrue(expected [ "Slack is off on the online demo, so it has no public Slack address.", "control: the text is the approved one")
	For body = "", "{""user"": 5", "not json", {"user": "sam", "member": "U012AB3CDE"}.%ToJSON() {
		For route = "List", "Save", "Remove" {
			Set text = ..Call(route, $Select(route = "Save": body, 1: ""), .response, "zzSlackRef000000000001")
			Do $$$AssertEquals(response.Status, "409 Conflict", route_" with '"_$Extract(body, 1, 20)_"': 409")
			Set answer = {}.%FromJSON(text)
			Do $$$AssertEquals(answer.error.code_"|"_answer.error.message, "not_available|"_expected, route_": not_available with settings.slackOffOnDemo")
		}
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SlackSettingsProbe", "submits")), 0, "nothing was submitted")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SlackSettingsProbe", "handoffs")), 0, "and no handoff was made")
}

Method TestHandoffDiscarded()
{
	Set body = {"user": "sam", "member": "U012AB3CDE"}.%ToJSON()
	For mode = "fail", "throw" {
		Kill ^OcuTalonTest("SlackSettingsProbe")
		Set ^OcuTalonTest("SlackSettingsProbe", "mode") = mode
		Set text = ..Call("Save", body, .response)
		Do $$$AssertEquals(response.Status_"|"_{}.%FromJSON(text).error.code, "500 Internal Server Error|server_error", mode_": a failed submit is 500 server_error")
		Do $$$AssertEquals(+$Get(^OcuTalonTest("SlackSettingsProbe", "handoffs")), 1, mode_": a handoff was made")
		Do $$$AssertTrue(..Field(1, "handoff") ? 1"secret://handoff/"32AN, mode_": and the command held its uri")
		Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(..Field(1, "handoff"), .left, 0), mode_": which was discarded all the same")
		Set text = ..Call("List", , .response)
		Do $$$AssertEquals(response.Status, "500 Internal Server Error", mode_": a list whose submit fails is 500")
		Set text = ..Call("Remove", , .response, "zzSlackRef000000000001")
		Do $$$AssertEquals(response.Status, "500 Internal Server Error", mode_": so is an unlink")
	}
	Kill ^OcuTalonTest("SlackSettingsProbe")
	Set text = ..Call("Save", body, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "control: a good link is 200")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(..Field(1, "handoff"), .left, 0), "and its handoff is gone too")
}

/// --- helpers ---
/// Every route, called as the signed-in user with the roles now set, answers the status and code with no submit and no handoff, and OnPreDispatch of each URL refuses
/// when dispatched is 1.
Method AssertRefusedEverywhere(status As %String, code As %String, dispatched As %Boolean = 1) [ Private ]
{
	If dispatched {
		For method = "GET", "POST" {
			Set written = ..PreDispatch(..#URL, method, .continue)
			Do $$$AssertEquals(continue, 0, method_": the dispatch stops")
			Do $$$AssertTrue(written [ ("""not_admin"""), method_": 403 not_admin")
		}
		Set written = ..PreDispatch(..#URL_"/zzSlackRef000000000001", "DELETE", .continue)
		Do $$$AssertEquals(continue, 0, "DELETE: the dispatch stops")
		Do $$$AssertTrue(written [ """not_admin""", "DELETE: 403 not_admin")
	}
	For route = "List", "Save", "Remove" {
		Set text = ..Call(route, $Select(route = "Save": {"user": "sam", "member": "U012AB3CDE"}.%ToJSON(), 1: ""), .response, "zzSlackRef000000000001")
		Do $$$AssertEquals(response.Status_"|"_{}.%FromJSON(text).error.code, status_"|"_code, route_" itself refuses with "_status)
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SlackSettingsProbe", "submits")), 0, "nothing was submitted")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("SlackSettingsProbe", "handoffs")), 0, "and no handoff was made")
}

/// The catalog text of the key for the web, with the slots.
ClassMethod Text(key As %String, slots As %DynamicObject = "") As %String [ Private ]
{
	Quit ##class(OcuTalon.Msg.Catalog).Render(key, slots, "web")
}

/// The class of the command of the nth submit, and one of its recorded fields.
Method CallClass(n As %Integer) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("SlackSettingsProbe", "calls", n, "class"))
}

Method Field(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("SlackSettingsProbe", "calls", n, field))
}

/// Calls the route method of the probe as the CSP session of the fixture session (body is the request's content, ref the :ref argument of Remove); response is the %response.
Method Call(method As %String, body As %String, Output response, ref As %String = "") As %String [ Private ]
{
	New %request, %response, %session
	Set application = "/ocutalon/api/"
	Set %request = $Select($Get(body) = "": ##class(OcuTalon.Test.Web.StubRequest).Make(application), 1: ##class(OcuTalon.Test.Web.StubRequest).MakeBody(application, body))
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %response.Status = "200 OK"
	Set %session = ##class(%CSP.Session).%New("ZzSlackSettings", 0)
	Set %session.Data("OcuTalon.SessionRef") = ..A
	If method = "Remove" {
		Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, method, ref)
	} Else {
		Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, method)
	}
	Do $$$AssertStatusOK(sc, method_" returns OK")
	Set response = %response
	Quit written
}

/// Runs OnPreDispatch of Web.Api's probe for the URL and method with a stand-in request; returns what it wrote. continue is the dispatch flag it left.
Method PreDispatch(url As %String, method As %String, Output continue) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", method, "application/json", 1, "http://localhost", "localhost")
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New("ZzSlackSettings", 0)
	Set %response.ContentType = ""
	Set continue = 1
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Test.Web.ApiProbe", "OnPreDispatch", url, method, .continue)
	Do $$$AssertStatusOK(sc, "OnPreDispatch returns OK")
	Quit written
}

}
