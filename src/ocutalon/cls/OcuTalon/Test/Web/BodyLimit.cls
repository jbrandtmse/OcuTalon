/// Tests of the request body limit (Story 11.22; AD-13), called with stand-in request and response objects through OnPreDispatch of
/// Test.Web.ApiProbe (no declaration: the default bound) and Test.Web.BodyLimitProbe (an XData BodyBounds). The roles of the signed-in
/// user come from the probe's roles seam, which each test clears. No production and no session is needed.
///   - TestAtTheLimitContinues: a body of exactly 262144 bytes goes on to the route on every POST route, and a GET with no body goes on;
///   - TestOverTheLimitIsRefused: 262145 bytes on every route is 413 body_too_large in the error shape, the dispatch stops, and the route
///     writes nothing; an oversized body that breaks the envelope keeps its 403 wrong_origin;
///   - TestDeclaredBound: the route that the probe's XData BodyBounds names takes bodies up to its bound and refuses one byte more, a
///     :name segment matches one segment, another route and another method of the same class keep 262144 bytes, and a malformed entry is skipped;
///   - TestBadDeclarationMeansDefault: a declaration that is not valid JSON, or not an array, or a class with none, means 262144 bytes.
Class OcuTalon.Test.Web.BodyLimit Extends %UnitTest.TestCase
{

/// Every POST route of the REST surface, with a value in each :name segment.
Parameter POSTROUTES = "/v1/messages,/v1/approvals/zzRef/answer,/v1/incidents/zzRef/dismiss,/v1/demo/break-feed,/v1/mailbox/incoming,/v1/mailbox/samples/zzSample,/v1/guide/markers,/v1/session/end,/v1/pairing/code,/v1/settings/models,/v1/settings/budgets,/v1/settings/channels,/v1/settings/daily-digest,/v1/settings/time-zone,/v1/settings/check-thresholds,/v1/settings/demo-mode,/v1/heartbeat/run,/v1/settings/daily-digest/send,/v1/settings/models/test,/v1/decisions/zzRef/got-it,/v1/decisions/zzRef/noise";

/// The probe with no declaration.
Parameter PROBE = "OcuTalon.Test.Web.ApiProbe";

/// The probe with a declaration.
Parameter DECLARED = "OcuTalon.Test.Web.BodyLimitProbe";

/// The temporary class of TestBadDeclarationMeansDefault.
Parameter TEMPCLASS = "OcuTalon.Test.Web.ZzBodyBoundsTemp";

Method OnBeforeOneTest() As %Status
{
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonUser,OcuTalonAdmin"
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Kill ^OcuTalonTest("ApiProbe", "roles")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..DropTemp()
	Quit $SYSTEM.Status.OK()
}

/// A body of exactly 262144 bytes goes on to the route, whatever the route; a request with no body goes on too.
Method TestAtTheLimitContinues()
{
	Set limit = 262144
	Do $$$AssertEquals(##class(OcuTalon.Web.BodyLimit).#MAXBYTES, limit, "the limit is 256 KB")
	Set urls = $ListFromString(..#POSTROUTES)
	Do $$$AssertEquals($ListLength(urls), 21, "all twenty-one POST routes are tried")
	Set position = 0
	While $ListNext(urls, position, url) {
		Set body = ..Dispatch(..#PROBE, url, "POST", limit, "http://h:1", .response, .continue)
		Do $$$AssertEquals(continue_"|"_body, "1|", "POST "_url_" with "_limit_" bytes goes on and writes nothing")
	}
	Set body = ..Dispatch(..#PROBE, "/v1/state", "GET", 0, "", .response, .continue)
	Do $$$AssertEquals(continue_"|"_body, "1|", "a GET with no body goes on")
	Set body = ..Dispatch(..#PROBE, "/v1/pairing", "DELETE", 0, "http://h:1", .response, .continue)
	Do $$$AssertEquals(continue_"|"_body, "1|", "a DELETE with no body goes on")
}

/// A body of 262145 bytes is refused with 413 body_too_large before the route, on every route; the envelope is checked first.
Method TestOverTheLimitIsRefused()
{
	Set wanted = {"error": {"code": "body_too_large", "message": (##class(OcuTalon.Web.BodyLimit).#MESSAGEBODYTOOLARGE)}}.%ToJSON()
	Set over = 262145
	Set urls = $ListFromString(..#POSTROUTES)
	Set position = 0
	While $ListNext(urls, position, url) {
		Set body = ..Dispatch(..#PROBE, url, "POST", over, "http://h:1", .response, .continue)
		Do $$$AssertEquals(response.Status, "413 Content Too Large", "POST "_url_" with "_over_" bytes is 413")
		Do $$$AssertEquals(body, wanted, "POST "_url_": body_too_large in the error shape")
		Do $$$AssertEquals(continue, 0, "POST "_url_": the dispatch stops")
	}
	Set body = ..Dispatch(..#PROBE, "/v1/messages", "POST", 3000000, "http://h:1", .response, .continue)
	Do $$$AssertEquals(response.Status_"|"_body, "413 Content Too Large|"_wanted, "a body of 3 MB is refused as well")
	Set body = ..Dispatch(..#PROBE, "/v1/messages", "POST", over, "http://other:1", .response, .continue)
	Do $$$AssertEquals(response.Status_"|"_continue, "403 Forbidden|0", "an oversized body with the wrong Origin is refused by the envelope first")
	Do $$$AssertEquals($Piece(body, """", 6), "wrong_origin", "with the envelope's code, not body_too_large")
	Set ^OcuTalonTest("ApiProbe", "roles") = "OcuTalonAdmin"
	Set body = ..Dispatch(..#PROBE, "/v1/messages", "POST", over, "http://h:1", .response, .continue)
	Do $$$AssertEquals(response.Status_"|"_$Piece(body, """", 6), "403 Forbidden|no_role", "an oversized body from a user without the role is refused by the role check first")
}

/// A route that the class's XData BodyBounds names takes bodies up to its bound, one byte over is 413, and nothing else changes.
Method TestDeclaredBound()
{
	Set default = 262144
	Do $$$AssertEquals(##class(OcuTalon.Web.BodyLimit).Bound(..#DECLARED, "/v1/messages", "POST"), 300000, "the declared route's bound is 300000")
	Do $$$AssertEquals(##class(OcuTalon.Web.BodyLimit).Bound(..#PROBE, "/v1/messages", "POST"), default, "the class with no declaration keeps the default")
	For size = default, default + 1, 280000, 300000 {
		Set body = ..Dispatch(..#DECLARED, "/v1/messages", "POST", size, "http://h:1", .response, .continue)
		Do $$$AssertEquals(continue_"|"_body, "1|", "the declared route takes "_size_" bytes")
	}
	Set body = ..Dispatch(..#DECLARED, "/v1/messages", "POST", 300001, "http://h:1", .response, .continue)
	Do $$$AssertEquals(response.Status_"|"_continue, "413 Content Too Large|0", "the declared route refuses 300001 bytes")
	Do $$$AssertEquals($Piece(body, """", 6), "body_too_large", "with body_too_large")
	Set body = ..Dispatch(..#DECLARED, "/v1/messages?x=1", "POST", 300000, "http://h:1", .response, .continue)
	Do $$$AssertEquals(continue, 1, "a query string does not change the route")
	Set body = ..Dispatch(..#DECLARED, "/v1/guide/markers", "POST", default + 1, "http://h:1", .response, .continue)
	Do $$$AssertEquals(response.Status_"|"_continue, "413 Content Too Large|0", "another route of the same class is still refused over 262144 bytes")
	Set body = ..Dispatch(..#DECLARED, "/v1/messages", "PUT", default + 1, "http://h:1", .response, .continue)
	Do $$$AssertEquals(response.Status_"|"_continue, "413 Content Too Large|0", "another method on the declared route is still refused over 262144 bytes")
	Set body = ..Dispatch(..#DECLARED, "/v1/messages/zz", "POST", default + 1, "http://h:1", .response, .continue)
	Do $$$AssertEquals(response.Status_"|"_continue, "413 Content Too Large|0", "a longer url is not the declared route")
	Set body = ..Dispatch(..#DECLARED, "/v1/approvals/zzRef/answer", "POST", 270000, "http://h:1", .response, .continue)
	Do $$$AssertEquals(continue, 1, "a :name segment matches one segment of the url")
	Set body = ..Dispatch(..#DECLARED, "/v1/approvals/zzRef/answer", "POST", 270001, "http://h:1", .response, .continue)
	Do $$$AssertEquals(response.Status_"|"_continue, "413 Content Too Large|0", "and its bound still ends")
	Set body = ..Dispatch(..#DECLARED, "/v1/approvals//answer", "POST", default + 1, "http://h:1", .response, .continue)
	Do $$$AssertEquals(response.Status_"|"_continue, "413 Content Too Large|0", "a :name segment does not match an empty segment")
	Set body = ..Dispatch(..#DECLARED, "/v1/approvals/a/b/answer", "POST", default + 1, "http://h:1", .response, .continue)
	Do $$$AssertEquals(response.Status_"|"_continue, "413 Content Too Large|0", "a :name segment does not match two segments")
}

/// A declaration that is not valid JSON or not an array, and a class with none, mean the default bound.
Method TestBadDeclarationMeansDefault()
{
	Set default = 262144
	Try {
		Do ..MakeTemp("[{""method"": ""POST"", ""url"": ""/v1/messages"", ""bytes"": 300000}]")
		Do $$$AssertEquals(##class(OcuTalon.Web.BodyLimit).Bound(..#TEMPCLASS, "/v1/messages", "POST"), 300000, "control: the same temporary class with a valid declaration gives its bound")
		For text = "[{""method"": ""POST"", ""url"": ""/v1/messages"", ""bytes"": 300000", "{""method"": ""POST"", ""url"": ""/v1/messages"", ""bytes"": 300000}", "[]", "[{""method"": ""POST"", ""url"": ""/v1/messages"", ""bytes"": 100}]" {
			Do ..MakeTemp(text)
			Do $$$AssertEquals(##class(OcuTalon.Web.BodyLimit).Bound(..#TEMPCLASS, "/v1/messages", "POST"), default, "the declaration "_text_" means "_default)
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the temporary class could be made")
	}
	Do ..DropTemp()
	Do $$$AssertEquals(##class(OcuTalon.Web.BodyLimit).Bound("OcuTalon.Test.Web.ZzNoSuchClass", "/v1/messages", "POST"), default, "a class that does not exist means the default")
}

/// Makes (or remakes) the temporary class with an XData BodyBounds holding the text.
Method MakeTemp(text As %String) [ Private ]
{
	Do ..DropTemp()
	Set definition = ##class(%Dictionary.ClassDefinition).%New(..#TEMPCLASS)
	Set xdata = ##class(%Dictionary.XDataDefinition).%New()
	Set xdata.Name = "BodyBounds"
	Set xdata.MimeType = "application/json"
	Do xdata.Data.Write(text)
	Set xdata.parent = definition
	Do $$$AssertStatusOK(definition.%Save(), "the temporary class is saved")
	Do $$$AssertStatusOK($SYSTEM.OBJ.Compile(..#TEMPCLASS, "-d"), "and compiled")
}

/// Removes the temporary class.
Method DropTemp() [ Private ]
{
	If ##class(%Dictionary.ClassDefinition).%ExistsId(..#TEMPCLASS) Do $SYSTEM.OBJ.Delete(..#TEMPCLASS, "-d")
}

/// Runs OnPreDispatch of the class for a request with a body of exactly bytes ASCII characters (as bytes), the whole browser envelope for the
/// origin (empty: no Origin), and returns what it wrote. response is the %response and continue the dispatch flag that it left.
Method Dispatch(class As %String, url As %String, method As %String, bytes As %Integer, origin As %String, Output response, Output continue) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", method, "application/json", 1, origin, "h:1")
	If bytes > 0 Set %request.Content = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", $Translate($Justify("", bytes), " ", "x"), 1).Content
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set continue = 1
	Set sc = ##class(OcuTalon.Test.Web.Api).Capture(.capture)
	If $SYSTEM.Status.IsOK(sc) {
		Try {
			Set sc = $ClassMethod(class, "OnPreDispatch", url, method, .continue)
		} Catch exception {
			Set sc = exception.AsStatus()
		}
	}
	Set written = ##class(OcuTalon.Test.Web.Api).Collect(.capture)
	Set response = %response
	Do $$$AssertStatusOK(sc, "OnPreDispatch returns OK")
	Quit written
}

}
