/// Tests of POST /v1/mailbox/incoming and POST /v1/mailbox/samples/:name (Story 4.6; matrix rows 1, 3, 4 and 5; AD-1, AD-4, AD-13),
/// called with stand-in request and response objects like Test.Web.BreakFeedApi, through Test.Web.ApiProbe, whose Mail answers
/// for SimMailboxIn (^OcuTalonTest("ApiProbe", "mail")) and records each input under ^OcuTalonTest("ApiProbe", "mails", n), so
/// that no production is needed:
///   - TestIncoming: 202 {"ref"}; SimMailboxIn is asked once, with the CSP session's Ref and the three fields; a sessionRef in the
///     body is ignored; a missing from is empty; a body of SimMailboxIn's BODYMAX characters is handed on whole;
///   - TestFieldErrors: a blank subject (checked first), a blank body, both, and every other bad body (a body over BODYMAX
///     characters among them) are 400 bad_email with their texts, and SimMailboxIn is never asked;
///   - TestSamples: each sample name is 202 and passes Sample, with the body unread; an unknown name is 404 and nothing is asked;
///   - TestDemoOff: with demo mode off, or with no demo.mode row, both routes are 404 not_found before the body or the session is
///     read;
///   - TestFailures: no session, a service error and an output that isn't JSON with a ref are 500 server_error, and so is a refusal
///     with no retryAt;
///   - TestEmailLimit (Story 16.9): an email that SimMailboxIn refuses with a retryAt, by the form or by a sample chip, is 429
///     email_limit with exactly the members error and retryAt;
///   - TestRoutes: the route table names MailboxIncoming and MailboxSample.
/// The fixture session is a row of the IRIS user who runs the tests, which is the user that Ownership.SessionRef resolves the CSP
/// session for; demo.mode is saved before the tests and put back after them.
Class OcuTalon.Test.Web.MailboxApi Extends %UnitTest.TestCase
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

/// A typed email: 202 {"ref"} from the service's output; the service is asked once, for the CSP session's Ref, with the three
/// fields and no sample; a sessionRef in the body is ignored; a missing from is empty.
Method TestIncoming()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set other = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set json = {"from": "zz Dana <dana@example.com>", "subject": "zz Invoice", "body": "zz body", "sessionRef": (other)}.%ToJSON()
	Set body = ..Post("MailboxIncoming", ..Csp(ref), json, .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "202")
	Do $$$AssertEquals(response.ContentType, "application/json", "JSON")
	Do $$$AssertEquals(body, {"ref": "zzMailRef0123456789abc"}.%ToJSON(), "the body is {ref} of the service's output")
	Do $$$AssertEquals($Get(^OcuTalonTest("ApiProbe", "mails")), 1, "SimMailboxIn is asked once")
	Do $$$AssertEquals(^OcuTalonTest("ApiProbe", "mails", 1, "session"), ref, "for the CSP session's Ref, not the body's")
	Do $$$AssertEquals(^OcuTalonTest("ApiProbe", "mails", 1, "sample")_"|"_^OcuTalonTest("ApiProbe", "mails", 1, "sender")_"|"_^OcuTalonTest("ApiProbe", "mails", 1, "subject")_"|"_^OcuTalonTest("ApiProbe", "mails", 1, "text"), "|zz Dana <dana@example.com>|zz Invoice|zz body", "with no sample and the three fields")
	Kill ^OcuTalonTest("ApiProbe", "mails")
	Do ..Post("MailboxIncoming", ..Csp(ref), {"subject": "zz s", "body": "zz b"}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "202 with no from")
	Do $$$AssertEquals(^OcuTalonTest("ApiProbe", "mails", 1, "sender"), "", "and an empty sender")
	Kill ^OcuTalonTest("ApiProbe", "mails")
	Set long = $Translate($Justify("", 1000), " ", "x")
	Do ..Post("MailboxIncoming", ..Csp(ref), {"from": (long), "subject": (long), "body": "zz b"}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "202 for a from and a subject of 1000 characters")
	Kill ^OcuTalonTest("ApiProbe", "mails")
	Set text = $Translate($Justify("", ##class(OcuTalon.Channel.SimMailbox.In).#BODYMAX), " ", "y")
	Do ..Post("MailboxIncoming", ..Csp(ref), {"subject": "zz s", "body": (text)}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "202 for a body of BODYMAX characters")
	Do $$$AssertEquals($Length(^OcuTalonTest("ApiProbe", "mails", 1, "text")), 10000, "and the whole body is handed on")
}

/// Field errors and bad bodies: 400 bad_email with the text of the first blank field (subject, then body) or the general text;
/// SimMailboxIn is never asked.
Method TestFieldErrors()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set subject = ##class(OcuTalon.Web.Api).#MESSAGEEMPTYSUBJECT
	Set emptyBody = ##class(OcuTalon.Web.Api).#MESSAGEEMPTYBODY
	Set general = ##class(OcuTalon.Web.Api).#MESSAGEBADEMAIL
	Do $$$AssertEquals(subject_"|"_emptyBody, "Enter a subject.|Enter a body.", "the field texts")
	Do $$$AssertEquals(general, "An email needs a subject and a body. From and subject can be at most 1000 characters, and the body at most 10000.", "the general text")
	Do $$$AssertEquals(##class(OcuTalon.Channel.SimMailbox.In).#BODYMAX, 10000, "the body's bound")
	Set long = $Translate($Justify("", 1001), " ", "x")
	Set longBody = $Translate($Justify("", 10001), " ", "y")
	Set cases = $ListBuild($ListBuild("a blank subject", "{""subject"":"""",""body"":""zz b""}", subject))
	Set cases = cases_$ListBuild($ListBuild("a blank body", "{""subject"":""zz s"",""body"":""""}", emptyBody))
	Set cases = cases_$ListBuild($ListBuild("both blank (the subject first)", "{""subject"":"""",""body"":""""}", subject))
	Set cases = cases_$ListBuild($ListBuild("white space only", "{""subject"":"" "",""body"":""\t\n""}", subject))
	Set cases = cases_$ListBuild($ListBuild("an empty object", "{}", subject))
	Set cases = cases_$ListBuild($ListBuild("a subject only", "{""subject"":""zz s""}", emptyBody))
	Set cases = cases_$ListBuild($ListBuild("not JSON", "not json", general), $ListBuild("an array", "[1]", general), $ListBuild("no body", "", general))
	Set cases = cases_$ListBuild($ListBuild("a subject that is not a string", "{""subject"":5,""body"":""zz b""}", general), $ListBuild("a body that is null", "{""subject"":""zz s"",""body"":null}", general))
	Set cases = cases_$ListBuild($ListBuild("a from that is not a string", "{""from"":[],""subject"":""zz s"",""body"":""zz b""}", general))
	Set cases = cases_$ListBuild($ListBuild("a from over 1000 characters", "{""from"":"""_long_""",""subject"":""zz s"",""body"":""zz b""}", general))
	Set cases = cases_$ListBuild($ListBuild("a subject over 1000 characters", "{""subject"":"""_long_""",""body"":""zz b""}", general))
	Set cases = cases_$ListBuild($ListBuild("a body over 10000 characters", "{""subject"":""zz s"",""body"":"""_longBody_"""}", general))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set body = ..Post("MailboxIncoming", ..Csp(ref), $List(case, 2), .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", $List(case, 1)_": 400")
		Set error = ##class(%DynamicObject).%FromJSON(body).error
		Do $$$AssertEquals(error.code_"|"_error.message, "bad_email|"_$List(case, 3), $List(case, 1)_": bad_email and its text")
	}
	Do $$$AssertEquals($Get(^OcuTalonTest("ApiProbe", "mails"), 0), 0, "SimMailboxIn is never asked")
}

/// The three samples are 202 and pass the sample's name; the body is not read; an unknown name or another case is 404 not_found
/// and nothing is asked.
Method TestSamples()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set names = $ListBuild("newsletter", "partner-notice", "suspicious-request")
	Set position = 0
	While $ListNext(names, position, name) {
		Set body = ..Post("MailboxSample", ..Csp(ref), "not json", .response, name)
		Do $$$AssertEquals(response.Status, "202 Accepted", name_": 202")
		Do $$$AssertEquals(body, {"ref": "zzMailRef0123456789abc"}.%ToJSON(), name_": {ref}")
		Set n = ^OcuTalonTest("ApiProbe", "mails")
		Do $$$AssertEquals(^OcuTalonTest("ApiProbe", "mails", n, "session")_"|"_^OcuTalonTest("ApiProbe", "mails", n, "sample"), ref_"|"_name, name_": the CSP session's Ref and the sample")
		Do $$$AssertEquals(^OcuTalonTest("ApiProbe", "mails", n, "sender")_^OcuTalonTest("ApiProbe", "mails", n, "subject")_^OcuTalonTest("ApiProbe", "mails", n, "text"), "", name_": no fields: the service holds the sample")
	}
	Do $$$AssertEquals(^OcuTalonTest("ApiProbe", "mails"), 3, "three asks")
	For name = "zz", "Newsletter", "newsletter " {
		Set body = ..Post("MailboxSample", ..Csp(ref), "", .response, name)
		Do $$$AssertEquals(response.Status, "404 Not Found", "'"_name_"': 404")
		Do $$$AssertEquals(##class(%DynamicObject).%FromJSON(body).error.code, "not_found", "'"_name_"': not_found")
	}
	Do $$$AssertEquals(^OcuTalonTest("ApiProbe", "mails"), 3, "an unknown name asks nothing")
}

/// Demo mode off, or no demo.mode row: both routes are 404 not_found before the body or the session is read, with and without a
/// CSP session.
Method TestDemoOff()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set valid = {"subject": "zz s", "body": "zz b"}.%ToJSON()
	Do ##class(OcuTalon.Test.Demo.Step).Put(0, ##class(OcuTalon.Data.Time).NowUtc())
	For csp = ..Csp(ref), "" {
		Set body = ..Post("MailboxIncoming", csp, valid, .response)
		Do $$$AssertEquals(response.Status_"|"_##class(%DynamicObject).%FromJSON(body).error.code, "404 Not Found|not_found", "incoming: 404 not_found")
		Set body = ..Post("MailboxIncoming", csp, "not json", .response)
		Do $$$AssertEquals(response.Status_"|"_##class(%DynamicObject).%FromJSON(body).error.code, "404 Not Found|not_found", "incoming with a bad body: 404 before the body is read")
		Set body = ..Post("MailboxSample", csp, "", .response, "newsletter")
		Do $$$AssertEquals(response.Status_"|"_##class(%DynamicObject).%FromJSON(body).error.code, "404 Not Found|not_found", "sample: 404 not_found")
	}
	Do $$$AssertEquals($Get(^OcuTalonTest("ApiProbe", "mails"), 0), 0, "SimMailboxIn is never asked")
	Do ##class(OcuTalon.Test.Demo.Step).Remove()
	Do ..Post("MailboxIncoming", ..Csp(ref), valid, .response)
	Do $$$AssertEquals(response.Status, "404 Not Found", "incoming: 404 with no demo.mode row")
	Do ..Post("MailboxSample", ..Csp(ref), "", .response, "newsletter")
	Do $$$AssertEquals(response.Status, "404 Not Found", "sample: 404 with no demo.mode row")
	Do $$$AssertEquals($Get(^OcuTalonTest("ApiProbe", "mails"), 0), 0, "and SimMailboxIn is still not asked")
}

/// A session that can't be read (no CSP session), an error from SimMailboxIn, and an output that is no JSON, has no ref or a ref
/// that is not a string are 500 server_error, for both routes.
Method TestFailures()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set valid = {"subject": "zz s", "body": "zz b"}.%ToJSON()
	Set body = ..Post("MailboxIncoming", "", valid, .response)
	Do $$$AssertEquals(response.Status, "500 Internal Server Error", "incoming: 500 for a session that can't be read")
	Do $$$AssertEquals(##class(%DynamicObject).%FromJSON(body).error.code, "server_error", "server_error")
	Set body = ..Post("MailboxSample", "", "", .response, "newsletter")
	Do $$$AssertEquals(response.Status, "500 Internal Server Error", "sample: 500 for a session that can't be read")
	Do $$$AssertEquals($Get(^OcuTalonTest("ApiProbe", "mails"), 0), 0, "SimMailboxIn is not asked for it")
	For answer = "fail", "not json", "{}", "[]", "{""ref"":5}", "{""ref"":""""}", "{""refused"":1}", "{""refused"":1,""retryAt"":""""}", "{""refused"":1,""retryAt"":5}" {
		Set ^OcuTalonTest("ApiProbe", "mail") = answer
		For route = "MailboxIncoming", "MailboxSample" {
			Set body = ..Post(route, ..Csp(ref), $Select(route = "MailboxIncoming": valid, 1: ""), .response, "newsletter")
			Do $$$AssertEquals(response.Status, "500 Internal Server Error", route_": 500 for '"_answer_"'")
			Set error = ##class(%DynamicObject).%FromJSON(body).error
			Do $$$AssertEquals(error.code_"|"_error.message, "server_error|"_##class(OcuTalon.Web.Api).#MESSAGESERVERERROR, route_": server_error and its text for '"_answer_"'")
		}
	}
}

/// An email that SimMailboxIn refuses (the online demo's 20 an hour, Story 16.9) answers 429 Too Many Requests, for the form and
/// for each sample chip: exactly {"error":{"code":"email_limit","message"},"retryAt"} with the time that the service gave.
Method TestEmailLimit()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set ^OcuTalonTest("ApiProbe", "mail") = {"refused": 1, "retryAt": "2030-01-01T00:00:00Z"}.%ToJSON()
	Set wanted = "{""error"":{""code"":""email_limit"",""message"":""You've simulated 20 emails this hour.""},""retryAt"":""2030-01-01T00:00:00Z""}"
	Set body = ..Post("MailboxIncoming", ..Csp(ref), {"subject": "zz s", "body": "zz b"}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "429 Too Many Requests", "the form: 429")
	Do $$$AssertEquals(response.ContentType, "application/json", "JSON")
	Do $$$AssertEquals(body, wanted, "exactly error and retryAt")
	For name = "newsletter", "partner-notice", "suspicious-request" {
		Set body = ..Post("MailboxSample", ..Csp(ref), "", .response, name)
		Do $$$AssertEquals(response.Status, "429 Too Many Requests", name_": 429")
		Do $$$AssertEquals(body, wanted, name_": exactly error and retryAt")
	}
	Do $$$AssertEquals($Get(^OcuTalonTest("ApiProbe", "mails")), 4, "the service was asked each time")
	Do $$$AssertEquals(##class(OcuTalon.Web.Api).#MESSAGEEMAILLIMIT, "You've simulated 20 emails this hour.", "the message is the first sentence of the UX's text")
}

/// The route table sends the two mailbox paths to their methods, and no mailbox path answers not built any more.
Method TestRoutes()
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Web.Api||UrlMap")
	Set text = xdata.Data.Read(1000000)
	Do $$$AssertTrue(text [ "<Route Url=""/v1/mailbox/incoming"" Method=""POST"" Call=""MailboxIncoming""/>", "incoming calls MailboxIncoming")
	Do $$$AssertTrue(text [ "<Route Url=""/v1/mailbox/samples/:name"" Method=""POST"" Call=""MailboxSample""/>", "samples/:name calls MailboxSample")
}

/// A CSP session that holds the fixture session's Ref.
Method Csp(ref As %String) As %CSP.Session [ Private ]
{
	Set csp = ##class(%CSP.Session).%New("ZzMailboxApi", 0)
	Set csp.Data("OcuTalon.SessionRef") = ref
	Quit csp
}

/// Calls the route's method of the probe with a stand-in request whose body is json and the given CSP session, and returns the
/// body that it wrote. arg is the route's :name.
Method Post(method As %String, session As %RegisteredObject, json As %String, Output response, arg As %String = "") As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", json)
	Set %response = ##class(%CSP.Response).%New()
	Set %session = session
	Set %response.ContentType = ""
	If method = "MailboxSample" {
		Set body = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Test.Web.ApiProbe", method, arg)
	} Else {
		Set body = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Test.Web.ApiProbe", method)
	}
	Set response = %response
	Do $$$AssertStatusOK(sc, method_" returns OK")
	Quit body
}

}
