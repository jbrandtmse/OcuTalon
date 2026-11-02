/// Tests of POST /v1/demo/break-feed (Story 4.3; matrix row 13; AD-1, AD-13), called with stand-in request and response objects like
/// Test.Web.GuideApi, through Test.Web.ApiProbe, whose Press answers for BreakFeedIn (^OcuTalonTest("ApiProbe", "press")) so that no
/// production is needed:
///   - TestSent: the answer is 200 {"state":"sent","startedAt"}, and BreakFeedIn is asked once, for the CSP session's Ref;
///   - TestInactive: the answer is 409 {"error":{"code","message"}} with the reason as code and its plain-English hint;
///   - TestDemoOff: with demo mode off the answer is 404 not_found, before anything else, and BreakFeedIn is never asked;
///   - TestBodyIsIgnored: a sessionRef (or anything) in the body changes nothing: the session is the CSP session's;
///   - TestFailures: a session that can't be read, an error from BreakFeedIn and an answer the route doesn't know are 500 server_error;
///   - TestRoute: the route table names BreakFeed.
/// The fixture session is a row of the IRIS user who runs the tests, which is the user that Ownership.SessionRef resolves the CSP session
/// for (the rows are removed by Fixture.Clean); demo.mode is saved before the tests and
/// put back after them.
Class OcuTalon.Test.Web.BreakFeedApi Extends %UnitTest.TestCase
{

Property SavedModeFound As %Boolean;

Property SavedModeValue As %String(MAXLEN = 1000);

Property SavedModeUpdatedAt As %String(MAXLEN = 20);

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set ..SavedModeFound = found, ..SavedModeValue = value, ..SavedModeUpdatedAt = updatedAt
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("ApiProbe")
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, ##class(OcuTalon.Data.Time).NowUtc())
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Kill ^OcuTalonTest("ApiProbe")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..SavedModeFound, ..SavedModeValue, ..SavedModeUpdatedAt)
	Quit $SYSTEM.Status.OK()
}

/// A sent press: 200 with the run's state and start, and nothing else; BreakFeedIn is asked once for the session.
Method TestSent()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set body = ..Post(..Csp(ref), "", .response)
	Do $$$AssertEquals(..Ok(response), 1, "200: "_response.Status)
	Do $$$AssertEquals(response.ContentType, "application/json", "JSON")
	Do $$$AssertEquals(body, {"state": "sent", "startedAt": "2030-01-01T10:00:00Z"}.%ToJSON(), "the body is {state, startedAt}")
	Do $$$AssertEquals($Get(^OcuTalonTest("ApiProbe", "presses")), 1, "BreakFeedIn is asked once")
	Do $$$AssertEquals($Get(^OcuTalonTest("ApiProbe", "presses", 1)), ref, "for the CSP session's Ref")
}

/// An inactive press: 409 with the reason as the code and its hint, verbatim.
Method TestInactive()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set hints = $ListBuild($ListBuild("not_watching", "Ask OcuTalon to watch the Orders production first (step 1)."), $ListBuild("incident_in_progress", "Finish the current Orders incident first: approve or reject its fix, or dismiss the incident."))
	Set position = 0
	While $ListNext(hints, position, pair) {
		Set ^OcuTalonTest("ApiProbe", "press") = {"outcome": "inactive", "reason": ($List(pair, 1))}.%ToJSON()
		Set body = ..Post(..Csp(ref), "", .response)
		Do $$$AssertEquals(response.Status, "409 Conflict", "409 for "_$List(pair, 1))
		Do $$$AssertEquals(response.ContentType, "application/json", "JSON")
		Do $$$AssertEquals(body, {"error": {"code": ($List(pair, 1)), "message": ($List(pair, 2))}}.%ToJSON(), "the error body of "_$List(pair, 1))
	}
	Do $$$AssertEquals(##class(OcuTalon.Web.Api).#MESSAGENOTWATCHING, $List($List(hints, 1), 2), "the not_watching hint is the text of the experience")
	Do $$$AssertEquals(##class(OcuTalon.Web.Api).#MESSAGEINCIDENTINPROGRESS, $List($List(hints, 2), 2), "the incident_in_progress hint is the text of the experience")
}

/// Demo mode off: 404 not_found before anything else (the session, the body), and BreakFeedIn is never asked.
Method TestDemoOff()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Do ##class(OcuTalon.Test.Demo.Step).Put(0, ##class(OcuTalon.Data.Time).NowUtc())
	For csp = ..Csp(ref), "" {
		Set body = ..Post(csp, "not json", .response)
		Do $$$AssertEquals(response.Status, "404 Not Found", "404")
		Do $$$AssertEquals(##class(%DynamicObject).%FromJSON(body).error.code, "not_found", "not_found")
	}
	Do $$$AssertEquals($Get(^OcuTalonTest("ApiProbe", "presses"), 0), 0, "BreakFeedIn is never asked")
	Do ##class(OcuTalon.Test.Demo.Step).Remove()
	Do ..Post(..Csp(ref), "", .response)
	Do $$$AssertEquals(response.Status, "404 Not Found", "404 with no demo.mode row too")
	Do $$$AssertEquals($Get(^OcuTalonTest("ApiProbe", "presses"), 0), 0, "and BreakFeedIn is still not asked")
}

/// The body is not read: a sessionRef in it, or any text, changes nothing; the press is for the CSP session's Ref.
Method TestBodyIsIgnored()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set other = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	For json = "{""sessionRef"":"""_other_"""}", "not json", "[1,2]" {
		Set body = ..Post(..Csp(ref), json, .response)
		Do $$$AssertEquals(..Ok(response), 1, "200 for '"_json_"'")
	}
	Do $$$AssertEquals($Get(^OcuTalonTest("ApiProbe", "presses")), 3, "BreakFeedIn is asked for each")
	For n = 1:1:3 {
		Do $$$AssertEquals(^OcuTalonTest("ApiProbe", "presses", n), ref, "press "_n_" is for the CSP session's Ref")
	}
}

/// A session that can't be read (no CSP session at all), an error from BreakFeedIn, and an answer that is no JSON or has an outcome
/// the route doesn't know are 500 server_error.
Method TestFailures()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set body = ..Post("", "", .response)
	Do $$$AssertEquals(response.Status, "500 Internal Server Error", "500 for a session that can't be read")
	Do $$$AssertEquals(##class(%DynamicObject).%FromJSON(body).error.code, "server_error", "server_error")
	Do $$$AssertEquals($Get(^OcuTalonTest("ApiProbe", "presses"), 0), 0, "BreakFeedIn is not asked for it")
	For answer = "fail", "not json", "{""outcome"":""other""}", "{""outcome"":""inactive"",""reason"":""other""}", "[]" {
		Set ^OcuTalonTest("ApiProbe", "press") = answer
		Set body = ..Post(..Csp(ref), "", .response)
		Do $$$AssertEquals(response.Status, "500 Internal Server Error", "500 for '"_answer_"'")
		Set error = ##class(%DynamicObject).%FromJSON(body).error
		Do $$$AssertEquals(error.code_"|"_error.message, "server_error|"_##class(OcuTalon.Web.Api).#MESSAGESERVERERROR, "server_error and its text for '"_answer_"'")
	}
}

/// The route table sends POST /v1/demo/break-feed to BreakFeed.
Method TestRoute()
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Web.Api||UrlMap")
	Set text = xdata.Data.Read(1000000)
	Do $$$AssertTrue(text [ "<Route Url=""/v1/demo/break-feed"" Method=""POST"" Call=""BreakFeed""/>", "the route calls BreakFeed")
}

/// A CSP session that holds the fixture session's Ref.
Method Csp(ref As %String) As %CSP.Session [ Private ]
{
	Set csp = ##class(%CSP.Session).%New("ZzBreakFeedApi", 0)
	Set csp.Data("OcuTalon.SessionRef") = ref
	Quit csp
}

/// Calls BreakFeed of the probe with a stand-in request whose body is json and the given CSP session, and returns the body that it wrote.
Method Post(session As %RegisteredObject, json As %String, Output response) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", json)
	Set %response = ##class(%CSP.Response).%New()
	Set %session = session
	Set %response.ContentType = ""
	Set body = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Test.Web.ApiProbe", "BreakFeed")
	Set response = %response
	Do $$$AssertStatusOK(sc, "BreakFeed returns OK")
	Quit body
}

/// 1 when the response is a 200: the status line is empty (the default) or 200 OK.
ClassMethod Ok(response As %CSP.Response) As %Boolean [ Private ]
{
	Quit (response.Status = "") || (response.Status = "200 OK")
}

}
