/// Tests of the Roles routes (Story 25.4; AD-1, AD-4, AD-13, AD-19, AD-24; DW-1267), called with stand-in request and response objects through Test.Web.RoleSettingsProbe
/// and a CSP session whose OcuTalon.SessionRef is a fixture session. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): the routes go through the real
/// production, Commands.Submit, CommandsIn, the real SettingsOps and Install.Step.Roles, which change a fixture user's roles. Test.Core.AnswersInWebRoles.Reason refuses
/// everything else. The signed-in user's roles come from Test.Web.ApiProbe's seam; the fixture users have the prefix ZzRoleLeak and the fixture roles are
/// Test.Install.RolesAssign's.
///   - TestNotAdmin: a user with the OcuTalon user role only gets 403 not_admin from OnPreDispatch and from each route, for GET and POST; %All is not the admin role;
///   - TestRemovedAdminIsRefused: an admin whose live roles no longer hold OcuTalonAdmin gets 403 not_admin from OnPreDispatch and from each route itself, with nothing
///     submitted and no handoff made;
///   - TestNoChangeWritesNoEntry: a grant of a role the user already holds and a removal of a role the user does not hold each answer changed false and write no
///     Settings entry, and the real changes around them are the only entries;
///   - TestViewerPostIsReadOnly: a viewer-only admin's POST is 403 read_only from OnPreDispatch, which stops the dispatch before the route runs, and its GET is 403
///     not_admin, from OnPreDispatch and from the list route itself, with nothing submitted;
///   - TestOnlineDemo: with the online-demo flag set an admin gets 409 not_available for GET and POST, a malformed body included, with no handoff made and no command
///     submitted (the probe's counters and the command tables);
///   - TestBadShapes: each body that is not exactly {user, role, grant} of the right types is 400 bad_settings naming the fields, with no handoff and no submit;
///   - TestGrantAndRemove: a grant answers {"result":"done","changed":true} and the user holds the role, the same grant again says changed false, GET lists the user with the
///     role, a removal says changed true and the role is gone, each effective change writes one Settings entry;
///   - TestRefusals: each refused role and user is 400 bad_settings with its fields and reason, and changes nothing;
///   - TestChangesIsOnlyAHandoff: the SaveSettings command that a save submitted holds exactly {"handoff":"secret://handoff/<32 hex>"};
///   - TestUserNameNeverStored: the fixture user's name is in no SaveSettings or ListRoles message, no CommandResult column, no message header or event-log row, no
///     trace global and no ^OcuTalon* global, and is in the IRIS audit entry; every handoff uri that the calls made is gone;
///   - TestHandoffDiscardedOnFailure: when the submit fails or throws, the route answers 500 and the handoff is discarded all the same;
///   - TestListAndSaveOutcomes: a list whose submit fails or throws is 500, and a list or a save whose command is not built is 501 not_built, the save's handoff discarded;
///   - TestRolesReady: RolesReady is 0 for the install's roles class on this branch and 1 for a class that declares STEP6ROLES = 1.
Class OcuTalon.Test.Web.RolesApi Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Web.RoleSettingsProbe";

Parameter USER = "ZzRoleLeak";

/// The online-demo flag before the tests.
Property SavedOnline As %String;

/// The Refs of the fixture session.
Property A As %String;

/// The TraceRefs of the fixture sessions, for the clean-up of the messages.
Property Traces As %DynamicArray;

Property Missing As %String(MAXLEN = 300);

Property Created As %String;

/// The name of the fixture user of the test, with a random part.
Property Target As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set running = ##class(Ens.Director).IsProductionRunning(.name)
	Set ..Missing = ##class(OcuTalon.Test.Core.AnswersInWebRoles).Reason($SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL"), $SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER"), running, $Get(name))
	If ..Missing = "" {
		Do ..Clean()
		Set ..Created = ##class(OcuTalon.Test.Install.RolesAssign).EnsureRoles()
	}
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Set ..Traces = []
	Kill ^OcuTalonTest("RoleSettingsProbe")
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set ..A = ..Session()
	Set ..Target = ..#USER_$Random(100000000)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("ApiProbe")
	Kill ^OcuTalonTest("RoleSettingsProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Traces)
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	If ..Missing = "" Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	If ..Missing '= "" Quit $$$OK
	Do ..Clean()
	Do ##class(OcuTalon.Test.Install.RolesAssign).DropRoles(..Created)
	Quit $$$OK
}

Method TestNotAdmin()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	For method = "GET", "POST" {
		Set written = ..PreDispatch("/v1/settings/roles", method, .continue)
		Do $$$AssertEquals(continue, 0, method_": the dispatch stops")
		Do $$$AssertTrue(written [ """not_admin""", method_": 403 not_admin")
	}
	If ..Missing '= "" Quit
	Set body = ..Call("List", , .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "the list route refuses a non-admin itself")
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "not_admin", "not_admin")
	Set body = ..Call("Save", {"user": (..Target), "role": "OcuTalonViewer", "grant": true}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "the save route refuses a non-admin itself")
	Set ^OcuTalonTest("ApiProbe", "roles") = "%All,OcuTalonUser"
	Set body = ..Call("List", , .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "%All is not the admin role")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("RoleSettingsProbe", "submits")), 0, "nothing was submitted")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("RoleSettingsProbe", "offers")), 0, "and no handoff was made")
}

Method TestRemovedAdminIsRefused()
{
	Set ^OcuTalonTest("ApiProbe", "liveRoles") = "OcuTalonUser"
	For method = "GET", "POST" {
		Set written = ..PreDispatch("/v1/settings/roles", method, .continue)
		Do $$$AssertEquals(continue, 0, method_": the dispatch stops")
		Do $$$AssertTrue(written [ """not_admin""", method_": 403 not_admin")
	}
	If ..Missing '= "" Quit
	Set body = ..Call("List", , .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "the list route refuses it itself")
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "not_admin", "not_admin")
	Set body = ..Call("Save", ..Body(..Target, "OcuTalonViewer", 1), .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "the save route refuses it itself")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("RoleSettingsProbe", "submits")), 0, "nothing was submitted")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("RoleSettingsProbe", "offers")), 0, "and no handoff was made")
	Kill ^OcuTalonTest("ApiProbe", "liveRoles")
	Set written = ..PreDispatch("/v1/settings/roles", "GET", .continue)
	Do $$$AssertEquals(continue, 1, "control: with the role live again the list goes on")
}

Method TestNoChangeWritesNoEntry()
{
	If '..Guard() Quit
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set user = ..NewTarget()
	Set body = ..Call("Save", ..Body(user, "OcuTalonViewer", 0), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a removal of a role the user does not hold answers 200: "_body)
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.result_"|"_answer.changed, "done|0", "done, changed false")
	Do $$$AssertEquals(..OcuTalonRoles(user), "OcuTalonUser", "the user's roles are as they were")
	Set body = ..Call("Save", ..Body(user, "OcuTalonViewer", 1), .response)
	Do $$$AssertEquals({}.%FromJSON(body).changed, 1, "control: the grant changes the roles")
	Set body = ..Call("Save", ..Body(user, "OcuTalonViewer", 1), .response)
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.result_"|"_answer.changed, "done|0", "a grant of a role the user already holds is done, changed false")
	Do $$$AssertEquals(..OcuTalonRoles(user), "OcuTalonUser,OcuTalonViewer", "the roles are as they were")
	Set body = ..Call("Save", ..Body(user, "OcuTalonViewer", 0), .response)
	Do $$$AssertEquals({}.%FromJSON(body).changed, 1, "control: the removal that follows changes the roles")
	Set body = ..Call("Save", ..Body(user, "OcuTalonViewer", 0), .response)
	Do $$$AssertEquals({}.%FromJSON(body).changed, 0, "and a removal of the role it no longer holds changes nothing")
	Set body = ..Call("Save", ..Body(user, "OcuTalonApprover", 1), .response)
	Do $$$AssertEquals({}.%FromJSON(body).changed, 1, "the closing grant (the last entry) changes the roles")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", user, "", 3)
	Do $$$AssertEquals(entries.%Size(), 3, "exactly the three real changes wrote an entry, the no-ops none")
	Do $$$AssertEquals(entries.%Get(0).data.to, "OcuTalonUser,OcuTalonViewer", "the grant's entry")
	Do $$$AssertEquals(entries.%Get(1).data.to, "OcuTalonUser", "the removal's entry")
	Do $$$AssertEquals(entries.%Get(2).data.to, "OcuTalonApprover,OcuTalonUser", "and the closing grant's entry follows it directly")
}

Method TestViewerPostIsReadOnly()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonViewer,OcuTalonAdmin"
	Set written = ..PreDispatch("/v1/settings/roles", "POST", .continue)
	Do $$$AssertEquals(continue, 0, "the dispatch stops")
	Do $$$AssertTrue(written [ """read_only""", "403 read_only")
	Do $$$AssertTrue(written [ "You have the viewer role, so you can look but not change anything.", "with the viewer text")
	Set written = ..PreDispatch("/v1/settings/roles", "GET", .continue)
	Do $$$AssertEquals(continue, 0, "GET: the dispatch stops")
	Do $$$AssertTrue(written [ """not_admin""", "GET: a viewer is no admin, so the list is 403 not_admin")
	If ..Missing '= "" Quit
	Set body = ..Call("List", , .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "the list route refuses a viewer itself")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("RoleSettingsProbe", "submits")), 0, "and submits nothing")
}

Method TestOnlineDemo()
{
	If '..Guard() Quit
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set commands = ..Columns("OcuTalon_Msg_Command.SaveSettings")_..Columns("OcuTalon_Msg_Command.ListRoles")
	Set expected = "Roles can't be changed on the online demo."
	For body = "", "{""user"": 5", "not json", {"user": (..Target), "role": "OcuTalonViewer", "grant": true}.%ToJSON() {
		For route = "List", "Save" {
			Set text = ..Call(route, body, .response)
			Do $$$AssertEquals(response.Status, "409 Conflict", route_" with '"_$Extract(body, 1, 20)_"': 409")
			Set answer = {}.%FromJSON(text)
			Do $$$AssertEquals(answer.error.code, "not_available", route_": not_available")
			Do $$$AssertEquals(answer.error.message, expected, route_": with the ruled text")
		}
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("RoleSettingsProbe", "offers")), 0, "no handoff was made")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("RoleSettingsProbe", "submits")), 0, "no command was submitted")
	Do $$$AssertEquals(..Columns("OcuTalon_Msg_Command.SaveSettings")_..Columns("OcuTalon_Msg_Command.ListRoles"), commands, "and no command was stored")
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	Set text = ..Call("List", , .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "a visitor is never an admin, so the demo answers a visitor 403")
}

Method TestBadShapes()
{
	If '..Guard() Quit
	Set cases = $ListBuild(
		"|[]",
		"[]|[]",
		"""text""|[]",
		"not json|[]",
		"{}|[""user"",""role"",""grant""]",
		"{""user"":""a"",""role"":""OcuTalonViewer""}|[""grant""]",
		"{""user"":""a"",""grant"":true}|[""role""]",
		"{""role"":""OcuTalonViewer"",""grant"":true}|[""user""]",
		"{""user"":5,""role"":""OcuTalonViewer"",""grant"":true}|[""user""]",
		"{""user"":""a"",""role"":5,""grant"":true}|[""role""]",
		"{""user"":""a"",""role"":""OcuTalonViewer"",""grant"":""yes""}|[""grant""]",
		"{""user"":""a"",""role"":""OcuTalonViewer"",""grant"":1}|[""grant""]",
		"{""user"":""a"",""role"":""OcuTalonViewer"",""grant"":true,""extra"":1}|[""extra""]")
	Set position = 0
	While $ListNext(cases, position, one) {
		Set text = $Piece(one, "|", 1)
		Set fields = $Piece(one, "|", 2, *)
		Set body = ..Call("Save", text, .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", "'"_text_"' is 400")
		Set answer = {}.%FromJSON(body)
		Do $$$AssertEquals(answer.error.code, "bad_settings", "bad_settings")
		Do $$$AssertEquals(answer.fields.%ToJSON(), fields, "naming "_fields)
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("RoleSettingsProbe", "offers")), 0, "no handoff was made")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("RoleSettingsProbe", "submits")), 0, "and nothing was submitted")
}

Method TestGrantAndRemove()
{
	If '..Guard() Quit
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set user = ..NewTarget()
	Set body = ..Call("Save", ..Body(user, "OcuTalonViewer", 1), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a grant answers 200: "_body)
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.result_"|"_answer.changed, "done|1", "done, changed true")
	Do $$$AssertEquals(answer.%GetTypeOf("changed"), "boolean", "changed is a boolean")
	Do $$$AssertTrue($ListFind($ListFromString(..RoleSet(user)), "OcuTalonViewer"), "the user holds the role")
	Set body = ..Call("Save", ..Body(user, "OcuTalonViewer", 1), .response)
	Do $$$AssertEquals({}.%FromJSON(body).changed, 0, "the same grant again says changed false")
	Set list = {}.%FromJSON(..Call("List", , .response))
	Do $$$AssertEquals(response.Status, "200 OK", "the list answers 200")
	Set found = ""
	For i = 0:1:list.users.%Size() - 1 {
		If list.users.%Get(i).user = user Set found = list.users.%Get(i)
	}
	Do $$$AssertTrue($IsObject(found), "GET lists the user")
	If $IsObject(found) {
		Do $$$AssertEquals(found.roles.%ToJSON(), "[""OcuTalonUser"",""OcuTalonViewer""]", "with its OcuTalon roles")
		Do $$$AssertEquals(found.managed, 0, "not managed")
		Do $$$AssertEquals(found.%Size(), 3, "and only user, roles and managed")
	}
	Set body = ..Call("Save", ..Body(user, "OcuTalonViewer", 0), .response)
	Do $$$AssertEquals({}.%FromJSON(body).changed, 1, "a removal says changed true")
	Do $$$AssertEquals(..OcuTalonRoles(user), "OcuTalonUser", "and the role is gone")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", user, "", 2)
	Do $$$AssertEquals(entries.%Size(), 2, "the grant and the removal each wrote one Settings entry")
	Do $$$AssertEquals(entries.%Get(0).data.setting, "roles."_user, "the setting is roles.<user>")
	Do $$$AssertEquals(entries.%Get(0).data.to, "OcuTalonUser,OcuTalonViewer", "the grant's entry")
	Do $$$AssertEquals(entries.%Get(0).data.channel, "web", "on the web channel")
	Do $$$AssertEquals(entries.%Get(0).data.irisUser, $Username, "naming the admin of the call")
	Do $$$AssertEquals(entries.%Get(0).data.sessionRef, ..A, "and the session")
}

Method TestRefusals()
{
	If '..Guard() Quit
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set user = ..NewTarget()
	Set before = ..RoleSet(user)
	Set marked = ..#USER_"Marked"
	Do ##class(OcuTalon.Test.Install.RolesAssign).CreateUser(marked, "OcuTalonUser", ##class(OcuTalon.Install.Step.Users).#MARKER)
	Set cases = $ListBuild(
		"role|OcuTalonAdmin|"_user, "role|OcuTalonUser|"_user, "role|OcuTalonTraceViewer|"_user, "role|OcuTalonWebhook|"_user, "role|OcuTalonApprover_resend|"_user,
		"role|%All|"_user, "role|%Manager|"_user, "role|ZzNoSuchRole|"_user,
		"user_managed|OcuTalonViewer|OcuTalonService", "user_managed|OcuTalonViewer|OcuTalonWorkflow", "user_managed|OcuTalonViewer|OcuTalonSqlReader", "user_managed|OcuTalonViewer|"_marked,
		"user_system|OcuTalonViewer|UnknownUser", "user_system|OcuTalonViewer|_SYSTEM", "user_system|OcuTalonViewer|SuperUser", "user_system|OcuTalonViewer|%xzz",
		"user_unknown|OcuTalonViewer|ZzNoSuchUser", "user_unknown|OcuTalonViewer|", "user_unknown|OcuTalonViewer|"_$Translate($Justify("", 161), " ", "z"))
	Set messages = $ListBuild("Only the approver and viewer roles can be changed here.", "There is no IRIS user with that name.", "OcuTalon manages this account, so its roles can't be changed here.", "This is an IRIS system account, so its roles can't be changed here.")
	Set position = 0
	While $ListNext(cases, position, one) {
		Set reason = $Piece(one, "|", 1), role = $Piece(one, "|", 2), name = $Piece(one, "|", 3)
		Set label = reason_" "_role_" "_$Extract(name, 1, 20)
		Set body = ..Call("Save", ..Body(name, role, 1), .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", label_": 400")
		Set answer = {}.%FromJSON(body)
		Do $$$AssertEquals(answer.error.code, "bad_settings", label_": bad_settings")
		Do $$$AssertEquals(answer.fields.%ToJSON(), $Select(reason = "role": "[""role""]", 1: "[""user""]"), label_": the field")
		Do $$$AssertEquals(answer.reason, reason, label_": the reason")
		Do $$$AssertEquals(answer.error.message, $ListGet(messages, $Case(reason, "role": 1, "user_unknown": 2, "user_managed": 3, : 4)), label_": the reason's text")
	}
	Do $$$AssertEquals(..RoleSet(user), before, "the target's roles are unchanged")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Settings").%Size(), 0, "and no Settings entry was written")
}

Method TestChangesIsOnlyAHandoff()
{
	If '..Guard() Quit
	Set user = ..NewTarget()
	Do ..Call("Save", ..Body(user, "OcuTalonApprover", 1), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the save is accepted")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Changes, Slug, ActingUser FROM OcuTalon_Msg_Command.SaveSettings WHERE Slug = 'roles' ORDER BY ID DESC")
	Do $$$AssertTrue(result.%Next(), "the command is stored")
	Set changes = result.%Get("Changes")
	Do $$$AssertTrue($Match(changes, "^\{""handoff"":""secret://handoff/[0-9A-F]{32}""\}$"), "its Changes is exactly {""handoff"": <uri>}: "_changes)
	Do $$$AssertEquals(result.%Get("ActingUser"), $Username, "its ActingUser is the IRIS user of the call")
	Do $$$AssertEquals(result.%Get("ActingUser") [ ..Target, 0, "and not the target")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take({}.%FromJSON(changes).handoff, .left, 0), "its handoff is gone")
}

Method TestUserNameNeverStored()
{
	If '..Guard() Quit
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set log = ##class(OcuTalon.Test.Web.WebhookTools).LastLog()
	Set user = ..NewTarget()
	Set listsBefore = ..Handoffs()
	Do ..Call("Save", ..Body(user, "OcuTalonViewer", 1), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the grant is accepted")
	Do ..Call("List", , .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the list is accepted")
	Do ..Call("Save", ..Body(user, "OcuTalonViewer", 0), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "and so is the removal")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", user, "", 2)
	Do $$$AssertEquals(entries.%Size(), 2, "the IRIS audit log holds the name in each entry")
	For table = "OcuTalon_Msg_Command.SaveSettings", "OcuTalon_Msg_Command.ListRoles", "OcuTalon_Msg.CommandResult" {
		Do $$$AssertTrue(##class(OcuTalon.Test.Web.WebhookTools).Columns(table) '[ user, table_": no column of any row holds the name")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("Ens.MessageHeader", "Description", user), 0, "no message header's description holds it")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("Ens_Util.Log", "Text", user), 0, "no event-log row holds it")
	Do $$$AssertTrue(##class(OcuTalon.Test.Web.WebhookTools).LogText(log) '[ user, "and none written during the run does")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(user), "", "no trace global (message body, header or log row) holds it")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).Leaks(user), "", "no ^OcuTalon* global holds it")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Changes FROM OcuTalon_Msg_Command.SaveSettings WHERE Slug = 'roles'")
	While result.%Next() {
		Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take({}.%FromJSON(result.%GetData(1)).handoff, .left, 0), "a save's handoff is gone")
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Data FROM OcuTalon_Msg.CommandResult WHERE Data [ 'secret://handoff/'")
	Set lists = 0
	While result.%Next() {
		Set lists = lists + 1
		Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take({}.%FromJSON(result.%GetData(1)).handoff, .left, 0), "so is the list's: it was taken once, by the route")
	}
	Do $$$AssertTrue(lists > listsBefore, "the list's result carried a handoff uri")
}

Method TestHandoffDiscardedOnFailure()
{
	If '..Guard() Quit
	For mode = "fail", "throw" {
		Kill ^OcuTalonTest("RoleSettingsProbe")
		Set ^OcuTalonTest("RoleSettingsProbe", "mode") = mode
		Set body = ..Call("Save", ..Body(..Target, "OcuTalonViewer", 1), .response)
		Do $$$AssertEquals(response.Status, "500 Internal Server Error", "a submit that "_mode_"s answers 500")
		Set uri = $Get(^OcuTalonTest("RoleSettingsProbe", "uri", 1))
		Do $$$AssertTrue(uri '= "", mode_": a handoff was made")
		Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), mode_": and it is gone")
		Do $$$AssertEquals(left, "", "holding nothing")
	}
}

Method TestListAndSaveOutcomes()
{
	If '..Guard() Quit
	For mode = "fail", "throw" {
		Kill ^OcuTalonTest("RoleSettingsProbe")
		Set ^OcuTalonTest("RoleSettingsProbe", "mode") = mode
		Set body = ..Call("List", , .response)
		Do $$$AssertEquals(response.Status, "500 Internal Server Error", "a list whose submit "_mode_"s answers 500")
		Do $$$AssertTrue(body '[ """users""", mode_": and lists nothing")
	}
	Kill ^OcuTalonTest("RoleSettingsProbe")
	Set ^OcuTalonTest("RoleSettingsProbe", "mode") = "notbuilt"
	Set body = ..Call("List", , .response)
	Do $$$AssertEquals(response.Status, "501 Not Implemented", "a list that is not built answers 501")
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "not_built", "with its code")
	Set body = ..Call("Save", ..Body(..Target, "OcuTalonViewer", 1), .response)
	Do $$$AssertEquals(response.Status, "501 Not Implemented", "so does a save")
	Set uri = $Get(^OcuTalonTest("RoleSettingsProbe", "uri", 1))
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), "and its handoff is gone")
}

Method TestRolesReady()
{
	Do $$$AssertEquals(##class(OcuTalon.Web.RoleSettings).RolesReady(), 0, "RolesReady is 0 for the install's roles class on this branch (Story 26.4 adds STEP6ROLES)")
	Do $$$AssertEquals(##class(OcuTalon.Web.RoleSettings).RolesReady("OcuTalon.Test.Web.RolesReadyProbe"), 1, "and 1 for a class that declares STEP6ROLES = 1")
	Do $$$AssertEquals(##class(OcuTalon.Web.RoleSettings).RolesReady("OcuTalon.Test.Web.RolesApi"), 0, "and 0 for a class that declares none")
}

/// --- helpers ---
/// The number of CommandResult rows that carry a handoff uri.
ClassMethod Handoffs() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Msg.CommandResult WHERE Data [ 'secret://handoff/'")
	If result.%Next() Quit +result.%GetData(1)
	Quit 0
}

Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// A fixture session of the IRIS user who runs the tests (the CSP session resolves to it through its OcuTalon.SessionRef).
Method Session() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Do ..Traces.%Push(##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef)
	Quit ref
}

/// The fixture target user, with the OcuTalon user role; returns its name.
Method NewTarget() As %String [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Install.RolesAssign).CreateUser(..Target, "OcuTalonUser"), "the fixture target "_..Target_" is created")
	Quit ..Target
}

ClassMethod Body(user As %String, role As %String, grant As %Boolean) As %String [ Private ]
{
	Set body = {"user": (user), "role": (role)}
	Do body.%Set("grant", grant, "boolean")
	Quit body.%ToJSON()
}

/// Calls the route method of the probe as the CSP session of the fixture session; response is the %response.
Method Call(method As %String, body As %String, Output response) As %String [ Private ]
{
	New %request, %response, %session
	Set application = "/ocutalon/api/"
	Set %request = $Select($Get(body) = "": ##class(OcuTalon.Test.Web.StubRequest).Make(application), 1: ##class(OcuTalon.Test.Web.StubRequest).MakeBody(application, body))
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %response.Status = "200 OK"
	Set %session = ##class(%CSP.Session).%New("ZzRolesApi", 0)
	Set %session.Data("OcuTalon.SessionRef") = ..A
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, method)
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
	Set %session = ##class(%CSP.Session).%New("ZzRolesApi", 0)
	Set %response.ContentType = ""
	Set continue = 1
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Test.Web.ApiProbe", "OnPreDispatch", url, method, .continue)
	Do $$$AssertStatusOK(sc, "OnPreDispatch returns OK")
	Quit written
}

/// The value of every column of every row of the table, joined.
Method Columns(table As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Web.WebhookTools).Columns(table)
}

/// The user's recursed role set as a comma list.
ClassMethod RoleSet(user As %String) As %String [ Private ]
{
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet(user, .roles)
	Quit $Select($SYSTEM.Status.IsError(sc): "", 1: roles)
}

/// The OcuTalon roles of the user's recursed role set, sorted.
ClassMethod OcuTalonRoles(user As %String) As %String [ Private ]
{
	Set roles = ..RoleSet(user)
	Kill held
	For i = 1:1:$Length(roles, ",") {
		If $Extract($Piece(roles, ",", i), 1, 8) = "OcuTalon" Set held($Piece(roles, ",", i)) = ""
	}
	Set list = "", role = ""
	For {
		Set role = $Order(held(role))
		Quit:role=""
		Set list = list_$Select(list = "": "", 1: ",")_role
	}
	Quit list
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
