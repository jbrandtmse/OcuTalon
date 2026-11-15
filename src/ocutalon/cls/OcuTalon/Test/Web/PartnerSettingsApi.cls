/// Tests of the partner-contacts settings route (Story 24.2; AD-1, AD-4, AD-13, AD-19; DW-1254), called with stand-in request and response objects through
/// Test.Web.PartnerSettingsProbe and a CSP session whose OcuTalon.SessionRef is a fixture session. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): the
/// routes go through the real production, Commands.Submit, CommandsIn and the real SettingsOps, and a production of the instance (Watch.Reader Productions) is the one that a
/// contact concerns. The roles of the signed-in user come from Test.Web.ApiProbe's seam. The contacts that the tests make (names that begin zzpc), the online-demo flag and the
/// fixture rows are put back after each test.
///   - TestMapAndRoute: the Api URL map forwards /v1/settings/partner-contacts to the class, whose one route is POST with the empty remainder;
///   - TestNonAdmin403: a user without OcuTalonAdmin, and %All, get 403 not_admin from OnPreDispatch and from the route, and nothing is offered or submitted;
///   - TestOnlineDemoRefusesFirst: with the online-demo flag set an admin gets 409 not_available with the accepted text, and nothing is offered, submitted or written;
///   - TestSubmitNotAvailableIs409: a submit that answers the outcome not_available is 409 with the accepted off-demo text, and the handoff is gone;
///   - TestBadBody: a body that is not an object is 400 bad_settings with no field before anything is offered; an object of the wrong shape is 400 with no field, a bad address
///     and no production are 400 with each field named, and nothing is written;
///   - TestSubmitFailsOrThrows: a submit that fails or throws is 500 and the handoff is gone all the same;
///   - TestCommandHoldsOnlyTheHandoff: an admin's add is 200, and its SaveSettings command's Changes is exactly {"handoff": uri}; the sections hold the partner-contacts member
///     exactly when the switch of OcuTalon.Fix.PartnerContacts is on;
///   - TestValuesOnlyInTheRow (DW-1254, veto 3): the leak scan. An admin's add of a contact with a unique name and address goes through the real production. The one Settings audit
///     entry is partnerContact.<Ref> with the field names, and no audit row since the mark holds the name or the address; they are in no event log row, message header, SaveSettings,
///     CommandResult or Notification row, trace global (Ens.MessageBodyD/S, Ens.MessageHeaderD, Ens.Util.LogD) or ^OcuTalon* global but OcuTalonP.PartnerContactD (the positive
///     control). After the remove they are nowhere.
Class OcuTalon.Test.Web.PartnerSettingsApi Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Web.PartnerSettingsProbe";

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
	Do ..Clear()
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
	Kill ^OcuTalonTest("PartnerSettingsProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do ..Clear()
	Set ..A = ..Session($Username)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("ApiProbe", "roles")
	Kill ^OcuTalonTest("PartnerSettingsProbe")
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
	Do $$$AssertTrue(map [ "<Map Prefix=""/v1/settings/partner-contacts"" Forward=""OcuTalon.Web.PartnerSettings""/>", "the Api URL map forwards /v1/settings/partner-contacts to PartnerSettings")
	Set routes = ##class(OcuTalon.Test.Web.Api).Routes("OcuTalon.Web.PartnerSettings")
	Do $$$AssertEquals($ListToString(routes, "|"), "POST  Save", "the class has one route: POST with the empty remainder, called Save")
}

Method TestNonAdmin403()
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	For url = "/v1/settings/partner-contacts", "/v1/settings" {
		Set written = ..PreDispatch(url, $Select(url = "/v1/settings": "GET", 1: "POST"), .continue)
		Do $$$AssertEquals(continue, 0, url_": the dispatch stops")
		Do $$$AssertTrue(written [ """not_admin""", url_": 403 not_admin")
	}
	Set body = ..Call("Save", ..Valid(), ..A, .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "the route refuses a non-admin itself")
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "not_admin", "not_admin")
	Set ^OcuTalonTest("ApiProbe", "roles") = "%All,OcuTalonUser"
	Set written = ..PreDispatch("/v1/settings/partner-contacts", "POST", .continue)
	Do $$$AssertEquals(continue, 0, "%All: the dispatch stops")
	Do $$$AssertTrue(written [ """not_admin""", "%All: 403 not_admin from OnPreDispatch")
	Set body = ..Call("Save", ..Valid(), ..A, .response)
	Do $$$AssertEquals(response.Status, "403 Forbidden", "%All is not the admin role")
	Do $$$AssertEquals(..Offers()_"|"_..Submits(), "0|0", "nothing was offered or submitted")
	Do $$$AssertEquals(..Count(), 0, "nothing is stored")
}

Method TestOnlineDemoRefusesFirst()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set commands = ..LastCommand()
	Set body = ..Call("Save", ..Valid(), ..A, .response)
	Do $$$AssertEquals(response.Status, "409 Conflict", "an admin's save on the online demo is 409")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.error.code, "not_available", "not_available")
	Do $$$AssertEquals(answer.error.message, "Partner contacts are off on the online demo, where partner warnings go to simulated contacts. They work on your own install.", "with the accepted text")
	Do $$$AssertEquals(..Offers()_"|"_..Submits(), "0|0", "nothing was offered or submitted: the refusal comes before the body is read")
	Do $$$AssertEquals(..LastCommand(), commands, "no SaveSettings command was made")
	Do $$$AssertEquals(..Count(), 0, "and nothing was written")
	Set body = ..Call("Save", "not json", ..A, .response)
	Do $$$AssertEquals(response.Status, "409 Conflict", "a body that is not JSON gets the same 409, because it is never read")
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser"
	Set body = ..Call("Save", ..Valid(), ..A, .response)
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
	Do $$$AssertEquals(answer.error.code_"|"_answer.error.message_"|"_answer.fields.%Size(), "bad_settings|Couldn't save. Nothing was changed.|0", "bad_settings with the plain message and no field")
	Set valid = ..Valid()
	Set valid.email = "nope"
	Set valid.productions = []
	Set body = ..Call("Save", valid.%ToJSON(), ..A, .response)
	Do $$$AssertEquals(response.Status_"|"_$Piece(body, """fields"":", 2), "400 Bad Request|[""email"",""productions""]}", "a bad address and no production are named")
	Do $$$AssertEquals(..Count(), 0, "nothing was stored")
}

Method TestSubmitFailsOrThrows()
{
	If '..Guard() Quit
	For mode = "fail", "throw" {
		Kill ^OcuTalonTest("PartnerSettingsProbe")
		Set ^OcuTalonTest("PartnerSettingsProbe", "mode") = mode
		Set body = ..Call("Save", ..Valid(), ..A, .response)
		Do $$$AssertEquals(response.Status, "500 Internal Server Error", "a submit that "_mode_"s answers 500")
		Set uri = $Get(^OcuTalonTest("PartnerSettingsProbe", "uri"))
		Do $$$AssertTrue(uri '= "", mode_": the command carried a handoff uri")
		Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), mode_": the handoff is gone")
		Do $$$AssertEquals(left, "", "and held nothing")
		Do $$$AssertEquals(..Offers(), 1, mode_": the body was offered once")
	}
	Do $$$AssertEquals(..Count(), 0, "nothing is stored")
}

Method TestSubmitNotAvailableIs409()
{
	If '..Guard() Quit
	Set ^OcuTalonTest("PartnerSettingsProbe", "mode") = "not_available"
	Set body = ..Call("Save", ..Valid(), ..A, .response)
	Do $$$AssertEquals(response.Status, "409 Conflict", "a command that answers not_available is 409")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.error.code, "not_available", "not_available")
	Do $$$AssertEquals(answer.error.message, "Partner contacts are off on the online demo, where partner warnings go to simulated contacts. They work on your own install.", "with the accepted off-demo text")
	Do $$$AssertTrue(answer.error.message '= ##class(OcuTalon.Web.Api).#MESSAGENOTAVAILABLE, "and not the text of the email route")
	Set uri = $Get(^OcuTalonTest("PartnerSettingsProbe", "uri"))
	Do $$$AssertTrue(uri '= "", "the command carried a handoff uri")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Core.SecretHandoff).Take(uri, .left, 0), "the handoff is gone")
	Do $$$AssertEquals(left, "", "and held nothing")
	Do $$$AssertEquals(..Offers()_"|"_..Submits(), "1|1", "the body was offered once and submitted once")
	Do $$$AssertEquals(..Count(), 0, "nothing is stored")
}

Method TestCommandHoldsOnlyTheHandoff()
{
	If '..Guard() Quit
	Set mark = ..LastCommand()
	Set name = ..Name("C")
	Set valid = ..Valid()
	Set valid.name = name
	Set body = ..Call("Save", valid.%ToJSON(), ..A, .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "an admin's add is 200 JSON: "_body)
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.result, "done", "result done")
	Do $$$AssertEquals(answer.sections.%IsDefined("partner-contacts"), ##class(OcuTalon.Core.SettingsOps).PartnersShown(), "the sections hold the member exactly when the switch is on")
	Do $$$AssertEquals(..Count(), 1, "the contact is stored")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Changes FROM OcuTalon_Msg_Command.SaveSettings WHERE Slug = 'partner-contacts' AND ID > ?", mark)
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

Method TestValuesOnlyInTheRow()
{
	If '..Guard() Quit
	Set tag = $Random(1000000000)
	Set name = "zzpcleak"_tag_" Name", email = "zzpcleak"_tag_"x@example.com"
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set log = ##class(OcuTalon.Test.Web.WebhookTools).LastLog()
	Set header = ##class(OcuTalon.Test.Web.WebhookTools).LastHeader()
	Set body = {"action": "save", "ref": "", "name": (name), "email": (email), "productions": [(..Production())]}
	Set text = ..Call("Save", body.%ToJSON(), ..A, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the admin's add is 200: "_text)
	Set ref = ..RefOf(name)
	Do $$$AssertEquals($Length(ref), 22, "the contact is stored")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "", "partnerContact.", "", 1, 30)
	Do $$$AssertEquals(entries.%Size(), 1, "one audit entry")
	Set data = entries.%Get(0).data
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "partnerContact."_ref_"||name,email,productions", "it is partnerContact.<Ref>, from nothing to the three field names")
	Do $$$AssertEquals(data.irisUser_"|"_data.sessionRef_"|"_data.channel, $Username_"|"_..A_"|web", "and names the admin, the session and the web channel")
	Do ..Scan(name, email, mark, log, header, 1, "while the row exists")
	Set body = {"action": "remove", "ref": (ref)}
	Set text = ..Call("Save", body.%ToJSON(), ..A, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the admin's remove is 200: "_text)
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "", "partnerContact.", "", 2, 30)
	Do $$$AssertEquals(entries.%Size(), 2, "the remove has its own audit entry")
	Set data = entries.%Get(1).data
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "partnerContact."_ref_"|name,email,productions|", "from the three field names to nothing")
	Do ..Scan(name, email, mark, log, header, 0, "after the remove")
}

/// The leak scan for the name and the address: no audit row since the mark, no event log row since log, no message header since header, no row of the command, result or notice tables, and
/// no trace global holds either; the ^OcuTalon* globals that hold each are OcuTalonP.PartnerContactD while the row exists (held is 1; the positive control) and none after it is removed.
Method Scan(name As %String, email As %String, mark As %String, log As %Integer, header As %Integer, held As %Boolean, when As %String) [ Private ]
{
	Set needles = $ListBuild(name, email)
	Set position = 0
	While $ListNext(needles, position, needle) {
		Set label = when_": "_$Select(needle = name: "the name", 1: "the address")
		Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, , , , needle).%Size(), 0, label_": no audit row holds it")
		Do $$$AssertTrue(##class(OcuTalon.Test.Web.WebhookTools).LogText(log) '[ needle, label_": no event log row holds it")
		For table = "OcuTalon_Msg_Command.SaveSettings", "OcuTalon_Msg.CommandResult", "OcuTalon_Msg.Notification" {
			Do $$$AssertEquals(..TableHolds(table, 0, needle), 0, label_": "_table_" does not hold it")
		}
		Do $$$AssertEquals(..TableHolds("Ens.MessageHeader", header, needle), 0, label_": no message header holds it")
		Do $$$AssertEquals($ClassMethod("OcuTalon.Test.Core.SecretHandoff", "TraceLeaks", needle), "", label_": no trace global holds it")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).Leaks(needle), $Select(held: "OcuTalonP.PartnerContactD", 1: ""), label_": the ^OcuTalon* globals that hold it")
	}
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

/// The unique name of a contact of the test.
ClassMethod Name(suffix As %String) As %String [ Private ]
{
	Quit "zzpcapi"_suffix_$Job
}

/// A production of the instance, as {namespace, production}: the first that Watch.Reader gives.
ClassMethod Production() As %DynamicObject [ Private ]
{
	Set list = ##class(OcuTalon.Watch.Reader).Productions()
	If 'list.%Size() Quit {"namespace": "zznone", "production": "zznone"}
	Set first = list.%Get(0)
	Quit {"namespace": (first.namespace), "production": (first.production)}
}

/// A valid add: a unique name, an address and the instance's production.
ClassMethod Valid() As %DynamicObject [ Private ]
{
	Quit {"action": "save", "ref": "", "name": (..Name("V")), "email": "zzpcapi@example.com", "productions": [(..Production())]}
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
	Set %session = ##class(%CSP.Session).%New("ZzPartnerSettings", 0)
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
	Set %session = ##class(%CSP.Session).%New("ZzPartnerSettings", 0)
	Set %response.ContentType = ""
	Set continue = 1
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Test.Web.ApiProbe", "OnPreDispatch", url, method, .continue)
	Do $$$AssertStatusOK(sc, "OnPreDispatch returns OK")
	Quit written
}

/// The number of offers and of submits that the probe saw.
Method Offers() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("PartnerSettingsProbe", "offers"))
}

Method Submits() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("PartnerSettingsProbe", "submits"))
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

/// The Ref of the contact with the name in PartnerContact.List, or "".
ClassMethod RefOf(name As %String) As %String [ Private ]
{
	Set ref = ""
	Set iterator = ##class(OcuTalon.Data.PartnerContact).List().%GetIterator()
	While iterator.%GetNext(, .one) {
		If one.name = name Set ref = one.ref
	}
	Quit ref
}

/// The number of contacts that the tests made (names that begin zzpc).
ClassMethod Count() As %Integer [ Private ]
{
	Set count = 0
	Set iterator = ##class(OcuTalon.Data.PartnerContact).List().%GetIterator()
	While iterator.%GetNext(, .one) {
		If $Extract(one.name, 1, 4) = "zzpc" Set count = count + 1
	}
	Quit count
}

/// Deletes the contacts that the tests made.
ClassMethod Clear() [ Private ]
{
	Set id = ""
	For {
		Set id = $Order(^OcuTalonP.PartnerContactD(id))
		Quit:id=""
		Set row = ##class(OcuTalon.Data.PartnerContact).%OpenId(id)
		If $IsObject(row) && ($Extract(row.Name, 1, 4) = "zzpc") Do ##class(OcuTalon.Data.PartnerContact).%DeleteId(id)
	}
}

}
