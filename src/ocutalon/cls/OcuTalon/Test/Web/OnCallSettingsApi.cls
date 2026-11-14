/// Tests of the on-call settings route (Story 36.4; AD-1, AD-4, AD-13, AD-19; DW-1249), called with stand-in request and response objects through
/// Test.Web.OnCallSettingsProbe and a CSP session whose OcuTalon.SessionRef is a fixture session. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): the
/// routes go through the real production, Commands.Submit, CommandsIn and the real SettingsOps. The roles of the signed-in user come from Test.Web.ApiProbe's seam.
/// The rows of the seven oncall.* keys, the online-demo flag and the fixture rows are put back after each test.
///   - TestMapAndRoute: the Api URL map forwards /v1/settings/on-call to the class, whose one route is POST with the empty remainder;
///   - TestNonAdmin403: a user without OcuTalonAdmin, and %All, get 403 not_admin from OnPreDispatch and from the route, and nothing is offered or submitted;
///   - TestOnlineDemoRefusesFirst: with the online-demo flag set an admin gets 409 not_available with the accepted text, and nothing is offered, submitted or written;
///   - TestSubmitNotAvailableIs409: a submit that answers the outcome not_available is 409 with the accepted off-demo text, and the handoff is gone;
///   - TestBadBody: a body that is not an object is 400 bad_settings with no field before anything is offered; an object of the wrong shape is 400 with each
///     field named, and nothing is written;
///   - TestSubmitFailsOrThrows: a submit that fails or throws is 500 and the handoff is gone all the same;
///   - TestCommandHoldsOnlyTheHandoff: an admin's save is 200 with the on-call section, and its SaveSettings command's Changes is exactly {"handoff": uri};
///   - TestValuesOnlyInTheAuditLog (V3, DW-1249): the one leak scan. An admin's save of unique addresses and a user name goes through the real production. They are in
///     the IRIS audit entries (the positive control) and in no event log row, message header, SaveSettings, CommandResult or Notification row, or ^OcuTalon* global
///     but the setting rows (and, for the user name, the session row that makes the user). None of them is in a trace global either (Ens.MessageBodyD/S,
///     Ens.MessageHeaderD, Ens.Util.LogD).
///   - TestUsersListedThroughTheVerb (DW-1278): GET /v1/settings lists a fixture user with paired in the on-call member, through one real ListOnCallUsers (origin web_admin)
///     that has no SessionRef and that the production's SettingsOps answers with Data that is exactly {"handoff": uri}; the user name is in no trace global
///     (TraceLeaks) and the handoff is gone.
Class OcuTalon.Test.Web.OnCallSettingsApi Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Web.OnCallSettingsProbe";

/// The seven keys.
Parameter KEYS = "oncall.primary.user,oncall.primary.email,oncall.primary.channels,oncall.backup.user,oncall.backup.email,oncall.backup.channels,oncall.escalationMinutes";

/// The online-demo flag before the tests.
Property SavedOnline As %String;

/// The Ref of the fixture session of the CSP session.
Property A As %String;

/// The TraceRefs of the fixture sessions, for the clean-up of the messages.
Property Traces As %DynamicArray;

/// The reason why the tests fail, or empty.
Property Missing As %String(MAXLEN = 200);

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Kill ^OcuTalonTest("OnCallSettingsApi")
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Set ^OcuTalonTest("OnCallSettingsApi", "saved", key) = $ListBuild(row.Value, row.UpdatedAt)
	}
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..Missing = ""
	If '##class(Ens.Director).IsProductionRunning(.name) || (name '= "OcuTalon.Production") {
		Set ..Missing = "OcuTalon.Production does not run in OCUTALON: this class runs in throwaways and CI only (Rule 21)"
	}
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Set ..Traces = []
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Kill ^OcuTalonTest("OnCallSettingsProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do ..Clear()
	Set ..A = ..Session($Username)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("ApiProbe", "roles")
	Kill ^OcuTalonTest("OnCallSettingsProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Traces)
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do ..Clear()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("ApiProbe", "roles")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ..Clear()
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		If $Data(^OcuTalonTest("OnCallSettingsApi", "saved", key), saved) {
			Set row = ##class(OcuTalon.Data.Setting).%New()
			Set row.Key = key, row.Value = $List(saved, 1), row.UpdatedAt = $List(saved, 2)
			Do row.%Save()
		}
	}
	Kill ^OcuTalonTest("OnCallSettingsApi")
	Quit $$$OK
}

Method TestMapAndRoute()
{
	Set stream = ##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Web.Api||UrlMap").Data
	Do stream.Rewind()
	Set map = ""
	While 'stream.AtEnd {
		Set map = map_stream.Read(32000)
	}
	Do $$$AssertTrue(map [ "<Map Prefix=""/v1/settings/on-call"" Forward=""OcuTalon.Web.OnCallSettings""/>", "the Api URL map forwards /v1/settings/on-call to OnCallSettings")
	Set routes = ##class(OcuTalon.Test.Web.Api).Routes("OcuTalon.Web.OnCallSettings")
	Do $$$AssertEquals($ListToString(routes, "|"), "POST  Save", "the class has one route: POST with the empty remainder, called Save")
}

Method TestNonAdmin403()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	Set before = ..Rows()
	For url = "/v1/settings/on-call", "/v1/settings" {
		Set written = ..PreDispatch(url, $Select(url = "/v1/settings": "GET", 1: "POST"), .continue)
		Do $$$AssertEquals(continue, 0, url_": the dispatch stops")
		Do $$$AssertTrue(written [ """not_admin""", url_": 403 not_admin")
	}
	Set body = ..Call("Save", ..Valid(..User("a")), ..A, .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "the route refuses a non-admin itself")
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "not_admin", "not_admin")
	Set ^OcuTalonTest("ApiProbe", "roles") = "%All,OcuTalonUser"
	Set written = ..PreDispatch("/v1/settings/on-call", "POST", .continue)
	Do $$$AssertEquals(continue, 0, "%All: the dispatch stops")
	Do $$$AssertTrue(written [ """not_admin""", "%All: 403 not_admin from OnPreDispatch")
	Set body = ..Call("Save", ..Valid(..User("a")), ..A, .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "%All is not the admin role")
	Do $$$AssertEquals(..Offers()_"|"_..Submits(), "0|0", "nothing was offered or submitted")
	Do $$$AssertEquals(..Rows(), before, "nothing is stored")
}

Method TestOnlineDemoRefusesFirst()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set commands = ..LastCommand()
	Set body = ..Call("Save", ..Valid(..User("a")), ..A, .response)
	Do $$$AssertEquals(response.Status, "409 Conflict", "an admin's save on the online demo is 409")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.error.code, "not_available", "not_available")
	Do $$$AssertEquals(answer.error.message, "The online demo has no on-call person, because its visitors aren't admins. On your own install, an admin chooses one here.", "with the accepted text")
	Do $$$AssertEquals(..Offers()_"|"_..Submits(), "0|0", "nothing was offered or submitted: the refusal comes before the body is read")
	Do $$$AssertEquals(..LastCommand(), commands, "no SaveSettings command was made")
	Do $$$AssertEquals(..Rows(), 0, "and nothing was written")
	Set body = ..Call("Save", "not json", ..A, .response)
	Do $$$AssertEquals(response.Status, "409 Conflict", "a body that is not JSON gets the same 409, because it is never read")
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	Set body = ..Call("Save", ..Valid(..User("a")), ..A, .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "a visitor is never an admin, so the demo answers a visitor 403")
}

Method TestBadBody()
{
	If '..Guard() Quit
	For text = "", "[]", """text""", "5", "null", "{", "[{}]" {
		Set body = ..Call("Save", text, ..A, .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", "the body '"_text_"' is 400")
		Set answer = {}.%FromJSON(body)
		Do $$$AssertEquals(answer.error.code_"|"_answer.fields.%Size(), "bad_settings|0", "bad_settings with no field")
	}
	Do $$$AssertEquals(..Offers()_"|"_..Submits(), "0|0", "nothing was offered for any of them")
	Set body = ..Call("Save", "{}", ..A, .response)
	Do $$$AssertEquals(response.Status, "400 Bad Request", "an object with none of the members is 400")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.error.code_"|"_answer.error.message, "bad_settings|Couldn't save. Nothing was changed.", "bad_settings with the plain message")
	Set names = ""
	Set iterator = answer.fields.%GetIterator()
	While iterator.%GetNext(, .name) {
		Set names = names_$Select(names = "": "", 1: ",")_name
	}
	Do $$$AssertEquals(names, "primaryUser,primaryEmail,primaryChannels,backupUser,backupEmail,backupChannels,escalationMinutes", "SettingsOps named every field, in the form's order")
	Set valid = ..Valid(..User("a"))
	Set valid.primaryEmail = "nope"
	Set valid.escalationMinutes = 0
	Set body = ..Call("Save", valid.%ToJSON(), ..A, .response)
	Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""primaryEmail"",""escalationMinutes""]}", "a bad address and bad minutes are named")
	Do $$$AssertEquals(..Rows(), 0, "nothing was stored")
}

Method TestSubmitFailsOrThrows()
{
	If '..Guard() Quit
	For mode = "fail", "throw" {
		Kill ^OcuTalonTest("OnCallSettingsProbe")
		Set ^OcuTalonTest("OnCallSettingsProbe", "mode") = mode
		Set body = ..Call("Save", ..Valid(..User("a")), ..A, .response)
		Do $$$AssertEquals(response.Status, "500 Internal Server Error", "a submit that "_mode_"s answers 500")
		Set uri = $Get(^OcuTalonTest("OnCallSettingsProbe", "uri"))
		Do $$$AssertTrue(uri '= "", mode_": the command carried a handoff uri")
		Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), mode_": the handoff is gone")
		Do $$$AssertEquals(left, "", "and held nothing")
		Do $$$AssertEquals(..Offers(), 1, mode_": the body was offered once")
	}
	Do $$$AssertEquals(..Rows(), 0, "nothing is stored")
}

Method TestSubmitNotAvailableIs409()
{
	If '..Guard() Quit
	Set ^OcuTalonTest("OnCallSettingsProbe", "mode") = "not_available"
	Set body = ..Call("Save", ..Valid(..User("a")), ..A, .response)
	Do $$$AssertEquals(response.Status, "409 Conflict", "a command that answers not_available is 409")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.error.code, "not_available", "not_available")
	Do $$$AssertEquals(answer.error.message, "The online demo has no on-call person, because its visitors aren't admins. On your own install, an admin chooses one here.", "with the accepted off-demo text")
	Do $$$AssertTrue(answer.error.message '= ##class(OcuTalon.Web.Api).#MESSAGENOTAVAILABLE, "and not the text of the email route")
	Set uri = $Get(^OcuTalonTest("OnCallSettingsProbe", "uri"))
	Do $$$AssertTrue(uri '= "", "the command carried a handoff uri")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), "the handoff is gone")
	Do $$$AssertEquals(left, "", "and held nothing")
	Do $$$AssertEquals(..Offers()_"|"_..Submits(), "1|1", "the body was offered once and submitted once")
	Do $$$AssertEquals(..Rows(), 0, "nothing is stored")
}

Method TestCommandHoldsOnlyTheHandoff()
{
	If '..Guard() Quit
	Set mark = ..LastCommand()
	Set user = ..User("a")
	Set body = ..Call("Save", ..Valid(user), ..A, .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "an admin's save is 200 JSON: "_body)
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.result, "done", "result done")
	Set values = answer.sections.%Get("on-call")
	Do $$$AssertEquals(values.primaryUser_"|"_values.primaryEmail_"|"_values.primaryChannels_"|"_values.escalationMinutes, user_"|"_..Address("a")_"|email|20", "the answer carries the saved section")
	Do $$$AssertEquals(..Row("oncall.primary.user")_"|"_..Row("oncall.escalationMinutes"), user_"|20", "the rows are written")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Changes FROM OcuTalon_Msg_Command.SaveSettings WHERE Slug = 'on-call' AND ID > ?", mark)
	Set count = 0
	While result.%Next() {
		Set count = count + 1
		Set changes = result.%GetData(1)
		Do $$$AssertTrue($Match(changes, "^\{""handoff"":""secret://handoff/[0-9A-F]{32}""\}$"), "the command's Changes is exactly {""handoff"": uri}")
		Set uri = {}.%FromJSON(changes).handoff
		Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), "and the handoff is gone")
	}
	Do $$$AssertEquals(count, 1, "one SaveSettings command was made")
	Do $$$AssertEquals(..Offers()_"|"_..Submits(), "1|1", "one offer and one submit")
}

Method TestValuesOnlyInTheAuditLog()
{
	If '..Guard() Quit
	Set tag = $Random(1000000000)
	Set user = "zzocleak"_tag_"u", primary = "zzleak"_tag_"a@example.com", backup = "zzleak"_tag_"b@example.com"
	Do ..Session(user)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set log = ##class(OcuTalon.Test.Web.WebhookTools).LastLog()
	Set header = ##class(OcuTalon.Test.Web.WebhookTools).LastHeader()
	Set body = {"primaryPerson": "user", "primaryUser": (user), "primaryEmail": (primary), "primaryChannels": "email", "backupPerson": "email", "backupUser": "", "backupEmail": (backup), "backupChannels": "email", "escalationMinutes": 20}
	Set text = ..Call("Save", body.%ToJSON(), ..A, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the admin's save is 200: "_text)
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "", "oncall.", "", 6, 30)
	Do $$$AssertEquals(entries.%Size(), 6, "six on-call keys changed, six audit entries")
	Set audit = ""
	For i = 0:1:entries.%Size() - 1 {
		Set data = entries.%Get(i).data
		Set audit = audit_$Select($IsObject(data): data.%ToJSON(), 1: data)_entries.%Get(i).description
		Do $$$AssertEquals(data.irisUser_"|"_data.sessionRef_"|"_data.channel, $Username_"|"_..A_"|web", "entry "_i_" names the admin, the session and the web channel")
	}
	Set needles = $ListBuild(primary, backup, user)
	Set position = 0
	While $ListNext(needles, position, needle) {
		Do $$$AssertTrue(audit [ needle, "positive control: the IRIS audit entries hold "_needle)
		Do $$$AssertTrue(##class(OcuTalon.Test.Web.WebhookTools).LogText(log) '[ needle, needle_": no event log row holds it")
		For table = "OcuTalon_Msg_Command.SaveSettings", "OcuTalon_Msg.CommandResult", "OcuTalon_Msg.Notification" {
			Do $$$AssertEquals(..TableHolds(table, 0, needle), 0, needle_": "_table_" does not hold it")
		}
		Do $$$AssertEquals(..TableHolds("Ens.MessageHeader", header, needle), 0, needle_": no message header holds it")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).Leaks(primary), "OcuTalonP.SettingD", "the on-call person's address is in no ^OcuTalon* global but the setting rows")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).Leaks(backup), "OcuTalonP.SettingD", "nor is the backup's")
	Set leaks = $ListFromString(##class(OcuTalon.Test.Core.SecretHandoff).Leaks(user))
	Set rest = ""
	Set position = 0
	While $ListNext(leaks, position, name) {
		If (name '= "OcuTalonP.SessionD") && (name '= "OcuTalonP.SessionI") Set rest = rest_$ListBuild(name)
	}
	Do $$$AssertEquals($ListToString(rest), "OcuTalonP.SettingD", "the user name is in no ^OcuTalon* global but the setting rows and the session row of the fixture user")
	Set handoff = "OcuTalon.Test.Core.SecretHandoff"
	Do $$$AssertEquals($ClassMethod(handoff, "TraceLeaks", primary), "", "no trace global holds the on-call person's address")
	Do $$$AssertEquals($ClassMethod(handoff, "TraceLeaks", backup), "", "no trace global holds the backup's address")
	Do $$$AssertEquals($ClassMethod(handoff, "TraceLeaks", user), "", "no trace global holds the user name")
}

/// DW-1278: the page's users come back through the real production. A fixture user whose name only the user list carries is in the on-call member of GET /v1/settings,
/// not paired; exactly one ListOnCallUsers command, with no SessionRef (the evaluation counts only a session's commands), and one result of outcome listed were made,
/// the result's Data is exactly {"handoff": uri} and that handoff is gone;
/// and no trace global holds the user name, which a list in the CommandResult would put there.
Method TestUsersListedThroughTheVerb()
{
	If '..Guard() Quit
	Set tag = $Random(1000000000)
	Set user = "zzocroster"_tag_"u"
	Do ..Session(user)
	Set header = ##class(OcuTalon.Test.Web.WebhookTools).LastHeader()
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM OcuTalon_Msg.CommandResult")
	Set mark = $Select(result.%Next(): +result.%GetData(1), 1: 0)
	Set text = ..Call("Settings", "", ..A, .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "GET /v1/settings is 200 JSON: "_$Extract(text, 1, 200))
	Set found = ""
	Set iterator = {}.%FromJSON(text).sections.%Get("on-call").users.%GetIterator()
	While iterator.%GetNext(, .one) {
		If one.user = user Set found = one.user_"|"_one.paired_"|"_one.%GetTypeOf("paired")
	}
	Do $$$AssertEquals(found, user_"|0|boolean", "the fixture user is listed, not paired")
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = 'OcuTalon.Msg.Command.ListOnCallUsers' AND SourceConfigName = 'CommandsIn' AND TargetConfigName = 'SettingsOps'", header)
	Do rows.%Next()
	Do $$$AssertEquals(rows.%GetData(1), 1, "one ListOnCallUsers went from CommandsIn to SettingsOps")
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT c.SessionRef FROM OcuTalon_Msg.Command c JOIN Ens.MessageHeader h ON h.MessageBodyId = c.ID WHERE h.ID > ? AND h.MessageBodyClassName = 'OcuTalon.Msg.Command.ListOnCallUsers' AND h.SourceConfigName = 'CommandsIn'", header)
	Set refs = ""
	While rows.%Next() {
		Set refs = refs_$ListBuild(rows.%GetData(1))
	}
	Do $$$AssertEquals($ListLength(refs)_"|"_$ListToString(refs, ","), "1|", "and it has no SessionRef, so the evaluation, which counts a session's commands, never counts it")
	Set results = ##class(%SQL.Statement).%ExecDirect(, "SELECT Data FROM OcuTalon_Msg.CommandResult WHERE ID > ? AND Outcome = 'listed' AND Data LIKE '%handoff%'", mark)
	Set count = 0
	While results.%Next() {
		Set count = count + 1
		Set data = results.%GetData(1)
		Do $$$AssertTrue($Match(data, "^\{""handoff"":""secret://handoff/[0-9A-F]{32}""\}$"), "the result's Data is exactly {""handoff"": uri}")
		Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take({}.%FromJSON(data).handoff, .left, 0), "and the handoff is gone")
	}
	Do $$$AssertEquals(count, 1, "one result of outcome listed was made")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(user), "", "no trace global holds the user name")
	Do $$$AssertEquals(..TableHolds("OcuTalon_Msg.CommandResult", mark, user), 0, "no CommandResult holds it")
}

/// --- helpers ---
/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// A fixture session of the IRIS user (the CSP session resolves to the one of the IRIS user who runs the tests through its OcuTalon.SessionRef).
Method Session(user As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session(user)
	Do ..Traces.%Push(##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef)
	Quit ref
}

/// The name of a fixture OcuTalon user for the suffix, who has a session and no paired chat.
Method User(suffix As %String) As %String [ Private ]
{
	Set user = "zzocapi"_suffix_$Job
	Do ..Session(user)
	Quit user
}

/// The address of the suffix's fixture user.
ClassMethod Address(suffix As %String) As %String [ Private ]
{
	Quit "zzocapi"_suffix_"@example.com"
}

/// A valid body of a save: the user as the on-call person, paged by email only, and nobody as the backup, with 20 minutes. Returned as the JSON text.
Method Valid(user As %String) As %DynamicObject [ Private ]
{
	Quit {"primaryPerson": "user", "primaryUser": (user), "primaryEmail": (..Address("a")), "primaryChannels": "email", "backupPerson": "nobody", "backupUser": "", "backupEmail": "", "backupChannels": "telegram,email", "escalationMinutes": 20}
}

/// Calls the route method of the probe as the CSP session of the session (body is the request's content; the body of a dynamic object is its JSON); response is the %response.
Method Call(method As %String, body As %String, session As %String, Output response) As %String [ Private ]
{
	New %request, %response, %session
	If $IsObject(body) Set body = body.%ToJSON()
	Set application = "/ocutalon/api/"
	Set %request = $Select($Get(body) = "": ##class(OcuTalon.Test.Web.StubRequest).Make(application), 1: ##class(OcuTalon.Test.Web.StubRequest).MakeBody(application, body))
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %response.Status = "200 OK"
	Set %session = ##class(%CSP.Session).%New("ZzOnCallSettings", 0)
	Set %session.Data("OcuTalon.SessionRef") = session
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
	Set %session = ##class(%CSP.Session).%New("ZzOnCallSettings", 0)
	Set %response.ContentType = ""
	Set continue = 1
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Test.Web.ApiProbe", "OnPreDispatch", url, method, .continue)
	Do $$$AssertStatusOK(sc, "OnPreDispatch returns OK")
	Quit written
}

/// The number of offers and of submits that the probe saw.
Method Offers() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("OnCallSettingsProbe", "offers"))
}

Method Submits() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("OnCallSettingsProbe", "submits"))
}

/// The newest id of the SaveSettings messages, 0 when there is none.
Method LastCommand() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM OcuTalon_Msg_Command.SaveSettings")
	If 'result.%Next() Quit 0
	Quit +result.%GetData(1)
}

/// 1 when a column of a row of the table with an id above minId holds the needle, or when the query fails (which can never pass a check).
Method TableHolds(table As %String, minId As %Integer, needle As %String) As %Boolean [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT * FROM "_table_" WHERE ID > ?", minId)
	If result.%SQLCODE < 0 Quit 1
	Set count = result.%GetMetadata().columns.Count()
	While result.%Next() {
		For i = 1:1:count {
			If result.%GetData(i) [ needle Return 1
		}
	}
	Quit 0
}

/// The stored value of the key, "" when there is no row.
Method Row(key As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	Quit $Select($IsObject(row): row.Value, 1: "")
}

/// The number of rows of the seven keys.
Method Rows() As %Integer [ Private ]
{
	Set count = 0
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		If ##class(OcuTalon.Data.Setting).KeyIndexExists(key) Set count = count + 1
	}
	Quit count
}

/// Deletes the rows of the seven keys.
Method Clear() [ Private ]
{
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(key)
	}
}

}
