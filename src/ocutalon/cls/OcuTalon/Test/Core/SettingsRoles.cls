/// Tests of the ListRoles command and the roles section of SaveSettings in OcuTalon.Core.SettingsOps (Story 25.4; AD-1, AD-19, AD-24; DW-1267), called on a shadow
/// instance of OcuTalon.Test.Core.SettingsRolesProbe, whose role calls go to OcuTalon.Test.Core.RolesStub, with the user and the role in a real SecretHandoff. They change
/// no security object, so they run anywhere the production's classes load; the real role changes are Test.Install.RolesAssign's and Test.Web.RolesApi's.
///   - TestChangesShape: Changes that are not exactly {"handoff": uri} are refused, and a uri that came with them is consumed;
///   - TestUriConsumedOnEveryOutcome: after a done, a refusal, a bad body, a stub, an error and the demo, the uri has no secret behind it any more;
///   - TestOriginAndDemo: an origin other than web_admin is not_allowed and the online demo is not_available, for both commands, and the stub is not called;
///   - TestRefusalCodes: each refusal code of Roles.Refusal gives the field and the reason, and Assign is not called;
///   - TestNotBuilt: a 5003 from either call gives not_built, and any other error gives failed;
///   - TestDataHoldsNoName: a done carries only {"changed"} (a list only {"handoff"}), no column of the CommandResult holds the user's name, and the list is behind the uri;
///   - TestBodyShape: a body that is not exactly {user, role, grant} of the right types is refused and the stub is not called;
///   - TestRoute: ListRoles is in CommandsIn's Routes, to SettingsOps from web_admin only.
Class OcuTalon.Test.Core.SettingsRoles Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Core.SettingsRolesProbe";

/// A name that the tests look for in every column of the result.
Parameter NAME = "ZzRolesOpsTarget";

Property SavedOnline As %String;

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe, ^OcuTalonTest("RolesStub")
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe, ^OcuTalonTest("RolesStub")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $$$OK
}

Method TestChangesShape()
{
	Set uri = ..Put({"user": (..#NAME), "role": "OcuTalonViewer", "grant": true}.%ToJSON())
	For changes = "{}", "[]", "not json", "{""handoff"": 3}", "{""handoff"": """", ""x"": 1}", ("{""handoff"": """_uri_""", ""x"": 1}"), ("{""other"": """_uri_"""}") {
		Set result = ..Save(changes, "web_admin")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", "Changes "_$Extract($Translate(changes, uri, "U"), 1, 40)_" is refused")
		Do $$$AssertEquals(result.Data, "{""fields"":[]}", "with no field named")
	}
	Do $$$AssertEquals(..Calls(), 0, "and the role calls are never made")
	Do $$$AssertEquals(..Taken(uri), 0, "the uri that came with extra members was consumed, so that nothing is left behind")
}

Method TestUriConsumedOnEveryOutcome()
{
	Set bodies = $ListBuild({"user": (..#NAME), "role": "OcuTalonViewer", "grant": true}.%ToJSON(), "not json", {"user": 1}.%ToJSON())
	For answer = "", "stub", "error" {
		For refusal = "", "role" {
			For b = 1:1:$ListLength(bodies) {
				Kill ^OcuTalonTest("RolesStub")
				Set ^OcuTalonTest("RolesStub", "answer") = answer
				Set ^OcuTalonTest("RolesStub", "refusal") = refusal
				Set uri = ..Put($List(bodies, b))
				Set result = ..Save({"handoff": (uri)}.%ToJSON(), "web_admin")
				Do $$$AssertEquals(..Taken(uri), 0, "answer '"_answer_"', refusal '"_refusal_"', body "_b_": the uri is consumed ("_result.Outcome_")")
			}
		}
	}
	Set uri = ..Put("{}")
	Set result = ..Save({"handoff": (uri)}.%ToJSON(), "system")
	Do $$$AssertEquals(result.Outcome, "not_allowed", "a system origin is refused")
	Do $$$AssertEquals(..Taken(uri), 0, "and its uri is consumed")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set uri = ..Put("{}")
	Set result = ..Save({"handoff": (uri)}.%ToJSON(), "web_admin")
	Do $$$AssertEquals(result.Outcome, "not_available", "the online demo refuses")
	Do $$$AssertEquals(..Taken(uri), 0, "and its uri is consumed")
}

Method TestOriginAndDemo()
{
	For origin = "system", "web_user", "tool", "telegram", "zz", "" {
		Set uri = ..Put({"user": (..#NAME), "role": "OcuTalonViewer", "grant": true}.%ToJSON())
		Set result = ..Save({"handoff": (uri)}.%ToJSON(), origin)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", "SaveRoles from '"_origin_"' is not_allowed")
		Set list = ..List(origin)
		Do $$$AssertEquals(list.Ok_"|"_list.Outcome, "0|not_allowed", "ListRoles from '"_origin_"' is not_allowed")
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set list = ..List("web_admin")
	Do $$$AssertEquals(list.Ok_"|"_list.Outcome, "0|not_available", "ListRoles on the online demo is not_available")
	Set uri = ..Put({"user": (..#NAME), "role": "OcuTalonViewer", "grant": true}.%ToJSON())
	Set result = ..Save({"handoff": (uri)}.%ToJSON(), "web_admin")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_available", "SaveRoles on the online demo is not_available")
	Do $$$AssertEquals(..Calls(), 0, "no role call was made")
}

Method TestRefusalCodes()
{
	For code = "role", "user_unknown", "user_system", "user_managed" {
		Kill ^OcuTalonTest("RolesStub")
		Set ^OcuTalonTest("RolesStub", "refusal") = code
		Set uri = ..Put({"user": (..#NAME), "role": "OcuTalonViewer", "grant": true}.%ToJSON())
		Set result = ..Save({"handoff": (uri)}.%ToJSON(), "web_admin")
		Set data = {}.%FromJSON(result.Data)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", code_" is refused")
		Do $$$AssertEquals(data.reason, code, "with the reason")
		Do $$$AssertEquals(data.fields.%ToJSON(), $Select(code = "role": "[""role""]", 1: "[""user""]"), "and the field it belongs to")
		Do $$$AssertEquals(..Calls("Assign"), 0, "and Assign is not called")
	}
}

Method TestNotBuilt()
{
	Set ^OcuTalonTest("RolesStub", "answer") = "stub"
	Set uri = ..Put({"user": (..#NAME), "role": "OcuTalonViewer", "grant": true}.%ToJSON())
	Set result = ..Save({"handoff": (uri)}.%ToJSON(), "web_admin")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_built", "a 5003 from Assign is not_built")
	Set list = ..List("web_admin")
	Do $$$AssertEquals(list.Ok_"|"_list.Outcome, "0|not_built", "a 5003 from Holders is not_built")
	Set ^OcuTalonTest("RolesStub", "answer") = "error"
	Set uri = ..Put({"user": (..#NAME), "role": "OcuTalonViewer", "grant": true}.%ToJSON())
	Set result = ..Save({"handoff": (uri)}.%ToJSON(), "web_admin")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "any other error from Assign is failed")
	Set list = ..List("web_admin")
	Do $$$AssertEquals(list.Ok_"|"_list.Outcome, "0|failed", "and from Holders")
	Do $$$AssertEquals(result.Message_list.Message [ ..#NAME, 0, "no message names the user")
}

Method TestDataHoldsNoName()
{
	Set ^OcuTalonTest("RolesStub", "users") = [{"user": (..#NAME), "roles": ["OcuTalonViewer"], "managed": false}].%ToJSON()
	Set list = ..List("web_admin")
	Do $$$AssertEquals(list.Ok_"|"_list.Outcome, "1|done", "the list is done")
	Set data = {}.%FromJSON(list.Data)
	Do $$$AssertEquals($Select(data.%Size() = 1: "handoff", 1: "?"), "handoff", "its Data has the one member handoff")
	Do $$$AssertTrue(data.handoff?1"secret://handoff/"32UN, "which is a handoff uri")
	Do $$$AssertEquals(list.Data [ ..#NAME, 0, "and Data does not hold the name")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Take(data.handoff, .json, 1), "the list is behind the uri")
	Do $$$AssertEquals({}.%FromJSON("{""u"":"_json_"}").u.%Get(0).user, ..#NAME, "and holds the user")

	Set uri = ..Put({"user": (..#NAME), "role": "OcuTalonViewer", "grant": true}.%ToJSON())
	Set result = ..Save({"handoff": (uri)}.%ToJSON(), "web_admin")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a grant is done")
	Do $$$AssertEquals(result.Data, "{""changed"":true}", "its Data is only changed")
	Do $$$AssertEquals(..Calls("Assign"), 1, "Assign was called once")
	Set call = ^OcuTalonTest("RolesStub", "calls", ..Last("Assign"))
	Do $$$AssertEquals(call, "Assign|"_..#NAME_"|OcuTalonViewer|1|zzadmin|zzSessionRef|web", "with the user, the role, the acting admin, the session and the channel web")
	Do $$$AssertEquals(result.Message [ ..#NAME, 0, "the result's message does not hold the name")
	Set ^OcuTalonTest("RolesStub", "changed") = 0
	Set uri = ..Put({"user": (..#NAME), "role": "OcuTalonViewer", "grant": false}.%ToJSON())
	Set result = ..Save({"handoff": (uri)}.%ToJSON(), "web_admin")
	Do $$$AssertEquals(result.Data, "{""changed"":false}", "a call that changed nothing says changed false")
}

Method TestBodyShape()
{
	For body = "{""user"": ""a"", ""role"": ""OcuTalonViewer""}", "{""user"": ""a"", ""role"": ""OcuTalonViewer"", ""grant"": ""yes""}", "{""user"": 1, ""role"": ""OcuTalonViewer"", ""grant"": true}", "{""user"": ""a"", ""role"": ""OcuTalonViewer"", ""grant"": true, ""x"": 1}", "[]" {
		Set uri = ..Put(body)
		Set result = ..Save({"handoff": (uri)}.%ToJSON(), "web_admin")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", body_" is refused")
	}
	Do $$$AssertEquals(..Calls(), 0, "and no role call was made")
}

Method TestRoute()
{
	Set routes = ##class(%DynamicAbstractObject).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Core.CommandsIn||Routes").Data)
	Set found = 0
	For i = 0:1:routes.%Size() - 1 {
		Set route = routes.%Get(i)
		If route.verb = "ListRoles" {
			Set found = found + 1
			Do $$$AssertEquals(route.owner_"|"_route.origins, "SettingsOps|web_admin", "ListRoles goes to SettingsOps from web_admin only")
		}
	}
	Do $$$AssertEquals(found, 1, "and has one row")
	Do $$$AssertTrue($Parameter("OcuTalon.Core.CommandsIn", "TOOLVERBS") '[ "ListRoles", "it is no tool verb")
}

/// A handoff of the text, returned as its uri.
Method Put(text As %String) As %String [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SecretHandoff).Put(text, .uri), "the text is put into a handoff")
	Quit uri
}

/// 1 when a Take of the uri found something: 0 when the uri is gone.
Method Taken(uri As %String) As %Boolean [ Private ]
{
	Quit $$$ISOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .secret, 0))
}

Method Save(changes As %String, origin As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = "roles"
	Set command.Changes = changes
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = "zzSessionRef"
	Set command.Origin = origin
	Quit ..Carry(command)
}

Method List(origin As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.ListRoles).%New()
	Set command.Origin = origin
	Quit ..Carry(command)
}

Method Carry(command As OcuTalon.Msg.Command) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

/// The number of recorded role calls whose method is the name (every call when the name is empty).
ClassMethod Calls(method As %String = "") As %Integer [ Private ]
{
	Set count = 0, n = ""
	For {
		Set n = $Order(^OcuTalonTest("RolesStub", "calls", n))
		Quit:n=""
		If (method = "") || ($Piece(^OcuTalonTest("RolesStub", "calls", n), "|", 1) = method) Set count = count + 1
	}
	Quit count
}

/// The number of the last recorded call of the method.
ClassMethod Last(method As %String) As %Integer [ Private ]
{
	Set last = 0, n = ""
	For {
		Set n = $Order(^OcuTalonTest("RolesStub", "calls", n))
		Quit:n=""
		If $Piece(^OcuTalonTest("RolesStub", "calls", n), "|", 1) = method Set last = n
	}
	Quit last
}

}
