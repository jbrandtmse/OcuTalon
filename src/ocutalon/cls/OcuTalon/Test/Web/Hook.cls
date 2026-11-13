/// Tests of the webhook endpoint (Story 35.3; AD-13, AD-14, AD-17, AD-19, AD-24), called with stand-in request and response objects through
/// Test.Web.HookProbe, which carries the secret, the body, the size, the clock and the flags from ^OcuTalonTest("HookProbe") and records what the hook
/// hands to WebhookIn. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): the rejections write real audit entries. The fixtures are a session
/// and webhooks (Test.Data.Fixture), removed after every test, with the hook's counters of their Refs and of the slot "?".
///   - TestAccept: H1, a right secret and a JSON object or array of at most 65,536 bytes answers 202 with no body and hands exactly one event to WebhookIn
///     with the owning session, the webhook's name as the subject and the body as the text; the hour's accepted count is 1, nothing is counted as a rejection, and the answer carries no SuperSession header;
///   - TestUnauthorized: H2, an unknown or malformed Ref, a missing or wrong secret and a Ref whose owning session has no row each answer the same 401 with no
///     body and hand nothing over; an unknown Ref is compared against DUMMYHASH, a known one against its row's hash, and every request compares once;
///   - TestTooBig: H3, 65,537 bytes with the right secret answer 413 and the body is never read;
///   - TestNotJson: H4, a scalar, text, an empty body, a form and a string answer 400 and hand nothing over, and a JSON array is accepted;
///   - TestOverLimit: H5, the 121st valid event of a webhook in one UTC hour answers 429 with Retry-After, the accepted count stays 120, the next hour
///     accepts again, and another webhook is unaffected;
///   - TestOtherPaths: H6, GET, PUT, OPTIONS, HEAD and DELETE on a Ref, the empty path and a path of two segments answer 404 with no body and no Allow header,
///     and none is counted as a rejection;
///   - TestRejectionAudit: H7, five rejections of one Ref within 60 seconds write one webhook_rejected Action entry (target the Ref, counts.rejected 1), a
///     rejection 61 seconds after it writes a second with the count since, unknown Refs share the slot "?" with the target empty, and an audit write that
///     fails is logged without request data and changes no answer;
///   - TestOnlineDemo: the hook answers 404 on the online demo whatever the secret;
///   - TestUnavailable: a hand-over that fails answers 503, logs the Ref and a status text only, gives the hour's accepted count back, counts no rejection and
///     writes no audit entry; a hand-over that throws answers the same 503;
///   - TestNoProductionHeader: the SuperSession header that a hand-over sets on the response is deleted from the 202 and from the 503;
///   - TestLogsHoldNothing: after the cases above, no console line holds a secret or a body.
Class OcuTalon.Test.Web.Hook Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Web.HookProbe";

/// The secret of the fixture webhooks.
Parameter SECRET = "zz-hook-secret-0123456789";

/// The saved online-demo flag.
Property SavedOnline As %String;

/// The Ref of the fixture session, and of its webhook.
Property Session As %String;

Property Ref As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("HookProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Kill ^OcuTalonP.WebhookC("r", "?")
	Set ..Session = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set ..Ref = ##class(OcuTalon.Test.Data.Fixture).Webhook(..Session, "zz hook "_$Random(1000000), ..#SECRET)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..DropCounters()
	Kill ^OcuTalonP.WebhookC("r", "?")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("HookProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $$$OK
}

Method TestAccept()
{
	Set now = "2030-01-01T10:15:30Z"
	Set ^OcuTalonTest("HookProbe", "now") = now
	Set written = ..Post(..Ref, ..#SECRET, "{""event"":""a"",""n"":1}", .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "a JSON object with the right secret is accepted")
	Do $$$AssertEquals(written, "", "with no body")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("HookProbe", "sent")), 1, "one event is handed to WebhookIn")
	Do $$$AssertEquals($Get(^OcuTalonTest("HookProbe", "sent", 1, "session")), ..Session, "for the owning session")
	Do $$$AssertEquals($Get(^OcuTalonTest("HookProbe", "sent", 1, "name")), ##class(OcuTalon.Data.Webhook).RefIndexOpen(..Ref).Name, "with the webhook's name")
	Do $$$AssertEquals($Get(^OcuTalonTest("HookProbe", "sent", 1, "text")), "{""event"":""a"",""n"":1}", "and the body as the text")
	Do $$$AssertEquals(+$Get(^OcuTalonP.WebhookC("a", ..Ref, "2030-01-01T10")), 1, "the hour's accepted count is 1")
	Do $$$AssertEquals($Data(^OcuTalonP.WebhookC("r", ..Ref)), 0, "and nothing is counted as a rejection")
	Set written = ..Post(..Ref, ..#SECRET, "[1,2,3]", .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "a JSON array is accepted")
	Set bytes = "{""a"":"""_$Translate($Justify("", ##class(OcuTalon.Data.Webhook).#BODYMAX - 8), " ", "x")_"""}"
	Do $$$AssertEquals($Length(bytes), ##class(OcuTalon.Data.Webhook).#BODYMAX, "a body of exactly 65,536 bytes")
	Set written = ..Post(..Ref, ..#SECRET, bytes, .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "is accepted")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("HookProbe", "sent")), 3, "three events in all")
}

Method TestUnauthorized()
{
	Set ^OcuTalonTest("HookProbe", "now") = "2030-01-01T10:15:30Z"
	Set orphan = ##class(OcuTalon.Test.Data.Fixture).Webhook(##class(OcuTalon.Bridge.Ids).NewRef(), "zz orphan "_$Random(1000000), ..#SECRET)
	Set unknown = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set cases = $ListBuild("unknown Ref|"_unknown_"|"_..#SECRET, "malformed Ref|abc|"_..#SECRET, "wrong secret|"_..Ref_"|nope", "missing secret|"_..Ref_"|", "owning session has no row|"_orphan_"|"_..#SECRET)
	Set position = 0
	While $ListNext(cases, position, one) {
		Kill ^OcuTalonTest("HookProbe", "compared")
		Set written = ..Post($Piece(one, "|", 2), $Piece(one, "|", 3), "{}", .response)
		Do $$$AssertEquals(response.Status, "401 Unauthorized", $Piece(one, "|", 1)_": 401")
		Do $$$AssertEquals(written, "", $Piece(one, "|", 1)_": with no body")
		Do $$$AssertEquals(+$Get(^OcuTalonTest("HookProbe", "compared")), 1, $Piece(one, "|", 1)_": one comparison, whatever the reason")
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("HookProbe", "sent")), 0, "nothing is handed over")
	Kill ^OcuTalonTest("HookProbe", "compared")
	Do ..Post(unknown, ..#SECRET, "{}", .response)
	Do $$$AssertEquals($Get(^OcuTalonTest("HookProbe", "compared", 1)), ##class(OcuTalon.Data.Webhook).#DUMMYHASH, "an unknown Ref is compared against DUMMYHASH")
	Kill ^OcuTalonTest("HookProbe", "compared")
	Do ..Post("abc", ..#SECRET, "{}", .response)
	Do $$$AssertEquals($Get(^OcuTalonTest("HookProbe", "compared", 1)), ##class(OcuTalon.Data.Webhook).#DUMMYHASH, "so is a malformed one")
	Kill ^OcuTalonTest("HookProbe", "compared")
	Do ..Post(..Ref, "nope", "{}", .response)
	Do $$$AssertEquals($Get(^OcuTalonTest("HookProbe", "compared", 1)), ##class(OcuTalon.Data.Webhook).RefIndexOpen(..Ref).SecretHash, "a known Ref is compared against its own hash")
}

Method TestTooBig()
{
	Set ^OcuTalonTest("HookProbe", "now") = "2030-01-01T10:15:30Z"
	Set ^OcuTalonTest("HookProbe", "size") = ##class(OcuTalon.Data.Webhook).#BODYMAX + 1
	Set written = ..Post(..Ref, ..#SECRET, "{}", .response, 1)
	Do $$$AssertEquals(response.Status, "413 Content Too Large", "65,537 bytes are refused")
	Do $$$AssertEquals(written, "", "with no body")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("HookProbe", "bodyReads")), 0, "and the body is not read")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("HookProbe", "sent")), 0, "nothing is handed over")
	Do $$$AssertEquals(+$Get(^OcuTalonP.WebhookC("a", ..Ref, "2030-01-01T10")), 0, "and the refusal is not an accepted event")
	Set ^OcuTalonTest("HookProbe", "size") = ##class(OcuTalon.Data.Webhook).#BODYMAX
	Do ..Post(..Ref, ..#SECRET, "{}", .response, 1)
	Do $$$AssertEquals(response.Status, "202 Accepted", "exactly 65,536 bytes are accepted")
	Set ^OcuTalonTest("HookProbe", "size") = 70000
	Do ..Post(..Ref, "nope", "{}", .response, 1)
	Do $$$AssertEquals(response.Status, "401 Unauthorized", "the secret is checked before the size")
}

Method TestNotJson()
{
	Set ^OcuTalonTest("HookProbe", "now") = "2030-01-01T10:15:30Z"
	Set cases = $ListBuild("a scalar|5", "text|hello", "an empty body|", "a string|""hello""", "a broken object|{""a"":")
	Set position = 0
	While $ListNext(cases, position, one) {
		Do ..Post(..Ref, ..#SECRET, $Piece(one, "|", 2, *), .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", $Piece(one, "|", 1)_" is refused")
	}
	Set ^OcuTalonTest("HookProbe", "form") = 1
	Do ..Post(..Ref, ..#SECRET, "{""a"":1}", .response)
	Do $$$AssertEquals(response.Status, "400 Bad Request", "a form is refused even when its text parses")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("HookProbe", "sent")), 0, "nothing is handed over")
	Do $$$AssertEquals(+$Get(^OcuTalonP.WebhookC("a", ..Ref, "2030-01-01T10")), 0, "and none is an accepted event")
	Kill ^OcuTalonTest("HookProbe", "form")
	Do ..Post(..Ref, ..#SECRET, "[]", .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "an empty JSON array is accepted")
}

Method TestOverLimit()
{
	Set max = ##class(OcuTalon.Data.Webhook).#ACCEPTEDMAX
	Set other = ##class(OcuTalon.Test.Data.Fixture).Webhook(..Session, "zz other "_$Random(1000000), ..#SECRET)
	Set ^OcuTalonTest("HookProbe", "now") = "2030-01-01T10:15:30Z"
	For i = 1:1:max {
		Do ..Post(..Ref, ..#SECRET, "{""i"":"_i_"}", .response)
		If response.Status '= "202 Accepted" Do $$$AssertEquals(response.Status, "202 Accepted", "event "_i_" is accepted")
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("HookProbe", "sent")), max, max_" events are accepted")
	Set written = ..Post(..Ref, ..#SECRET, "{}", .response)
	Do $$$AssertEquals(response.Status, "429 Too Many Requests", "the next is refused")
	Do $$$AssertEquals(written, "", "with no body")
	Do $$$AssertEquals(response.GetHeader("Retry-After"), 2670, "and Retry-After is the seconds to the next UTC hour")
	Do $$$AssertEquals(+$Get(^OcuTalonP.WebhookC("a", ..Ref, "2030-01-01T10")), max, "the accepted count is not raised")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("HookProbe", "sent")), max, "and nothing more is handed over")
	Do $$$AssertEquals($ListGet($Get(^OcuTalonP.WebhookC("r", ..Ref)), 1) '= "", 1, "the refusal is counted as a rejection")
	Do ..Post(other, ..#SECRET, "{}", .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "another webhook has its own allowance")
	Set ^OcuTalonTest("HookProbe", "now") = "2030-01-01T11:00:00Z"
	Do ..Post(..Ref, ..#SECRET, "{}", .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "the next hour accepts again")
	Set ^OcuTalonTest("HookProbe", "now") = "2030-01-01T10:59:59Z"
	Do ..Post(..Ref, "nope", "{}", .response)
	Do $$$AssertEquals(response.Status, "401 Unauthorized", "a wrong secret is not told that the limit is reached")
}

Method TestOtherPaths()
{
	Set ^OcuTalonTest("HookProbe", "secret") = ..#SECRET
	Set ^OcuTalonTest("HookProbe", "body") = "{}"
	For method = "GET", "PUT", "OPTIONS", "HEAD", "DELETE", "PATCH" {
		Set written = ..Dispatch("/"_..Ref, method, .response)
		Do $$$AssertEquals(response.Status, "404 Not Found", method_" on a Ref is 404")
		Do $$$AssertEquals(written, "", method_": with no body")
		Do $$$AssertEquals(response.GetHeader("Allow"), "", method_": and no Allow header")
	}
	For url = "/", "", "/a/b", "/"_..Ref_"/secret", "/"_..Ref_"/" {
		Set written = ..Dispatch(url, "POST", .response)
		Do $$$AssertEquals(response.Status, "404 Not Found", "POST "_url_" is 404")
		Do $$$AssertEquals(written, "", "POST "_url_": with no body")
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("HookProbe", "sent")), 0, "nothing is handed over")
	Do $$$AssertEquals($Data(^OcuTalonP.WebhookC("r", ..Ref)) + $Data(^OcuTalonP.WebhookC("r", "?")), 0, "and no rejection is counted")
}

Method TestRejectionAudit()
{
	Set start = "2030-01-01T10:00:00Z"
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	For i = 0:10:40 {
		Set ^OcuTalonTest("HookProbe", "now") = ##class(OcuTalon.Data.Time).AddSeconds(start, i)
		Do ..Post(..Ref, "nope", "{}", .response)
		Do $$$AssertEquals(response.Status, "401 Unauthorized", "rejection at +"_i_" seconds")
	}
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", ..Ref, "", 1)
	Do $$$AssertEquals(entries.%Size(), 1, "five rejections within 60 seconds write one audit entry")
	Set data = entries.%Get(0).data
	Do $$$AssertEquals(data.action, "webhook_rejected", "action webhook_rejected")
	Do $$$AssertEquals(data.channel, "webhook", "channel webhook")
	Do $$$AssertEquals(data.target, ..Ref, "target the Ref")
	Do $$$AssertEquals(data.counts.rejected, 1, "counting the first rejection")
	Do $$$AssertEquals(data.result, "rejected", "result rejected")
	Set ^OcuTalonTest("HookProbe", "now") = ##class(OcuTalon.Data.Time).AddSeconds(start, 61)
	Do ..Post(..Ref, "nope", "{}", .response)
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", ..Ref, "", 2)
	Do $$$AssertEquals(entries.%Size(), 2, "a rejection 61 seconds after the entry writes a second one")
	Do $$$AssertEquals(entries.%Get(1).data.counts.rejected, 5, "counting the rejections since the previous entry")
	Do $$$AssertEquals(entries.%Get(0).data.counts.rejected + entries.%Get(1).data.counts.rejected, 6, "so every rejection is counted once")

	Set unknown = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set ^OcuTalonTest("HookProbe", "now") = ##class(OcuTalon.Data.Time).AddSeconds(start, 200)
	Do ..Post(unknown, ..#SECRET, "{}", .response)
	Do ..Post(##class(OcuTalon.Bridge.Ids).NewRef(), ..#SECRET, "{}", .response)
	Do ..Post("abc", ..#SECRET, "{}", .response)
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", "webhook_rejected", "", 1)
	Set shared = 0
	For i = 0:1:entries.%Size() - 1 {
		If entries.%Get(i).data.target = "" Set shared = shared + 1
	}
	Do $$$AssertEquals(shared, 1, "unknown and malformed Refs share one slot, with the target empty, and write one entry")

	Set ^OcuTalonTest("HookProbe", "mode") = "auditfail"
	Set other = ##class(OcuTalon.Test.Data.Fixture).Webhook(..Session, "zz audit "_$Random(1000000), ..#SECRET)
	Do ..Post(other, "nope", "{}", .response)
	Do $$$AssertEquals(response.Status, "401 Unauthorized", "an audit write that fails changes no answer")
	Set logs = ..Logs()
	Do $$$AssertTrue(logs [ "audit entry could not be written", "and is logged")
	Do $$$AssertTrue((logs '[ other) && (logs '[ "nope"), "without the Ref or the secret")
}

Method TestOnlineDemo()
{
	Set ^OcuTalonTest("HookProbe", "online") = 1
	Set written = ..Post(..Ref, ..#SECRET, "{}", .response)
	Do $$$AssertEquals(response.Status, "404 Not Found", "the online demo answers 404 to a right secret")
	Do $$$AssertEquals(written, "", "with no body")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("HookProbe", "sent")), 0, "and hands nothing over")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("HookProbe", "compared")), 0, "or even compares a secret")
	Kill ^OcuTalonTest("HookProbe", "online")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..Post(..Ref, ..#SECRET, "{}", .response)
	Do $$$AssertEquals(response.Status, "404 Not Found", "and so does the public flag itself")
}

Method TestUnavailable()
{
	Set ^OcuTalonTest("HookProbe", "now") = "2030-01-01T10:15:30Z"
	Set ^OcuTalonTest("HookProbe", "mode") = "fail"
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set written = ..Post(..Ref, ..#SECRET, "{""secret-body"":1}", .response)
	Do $$$AssertEquals(response.Status, "503 Service Unavailable", "a hand-over that fails is 503")
	Do $$$AssertEquals(written, "", "with no body")
	Set logs = ..Logs()
	Do $$$AssertTrue((logs [ ..Ref) && (logs [ "WebhookIn unavailable"), "the console line names the Ref and the service")
	Do $$$AssertTrue((logs '[ ..#SECRET) && (logs '[ "secret-body"), "and holds neither the secret nor the body")
	Do $$$AssertEquals($Data(^OcuTalonP.WebhookC("r", ..Ref)), 0, "a 503 is not counted as a rejection")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Action", "Action", ..Ref).%Size(), 0, "and writes no audit entry")
	Do $$$AssertEquals(+$Get(^OcuTalonP.WebhookC("a", ..Ref, "2030-01-01T10")), 0, "and the hour's accepted count is given back")
	Kill ^OcuTalonTest("HookProbe", "logs")
	Set ^OcuTalonTest("HookProbe", "mode") = "throw"
	Set written = ..Post(..Ref, ..#SECRET, "{""secret-body"":1}", .response)
	Do $$$AssertEquals(response.Status, "503 Service Unavailable", "a hand-over that throws is 503 too")
	Do $$$AssertEquals(written, "", "with no body")
	Do $$$AssertTrue(..Logs() [ ..Ref, "and its console line names the Ref")
	Do $$$AssertEquals(+$Get(^OcuTalonP.WebhookC("a", ..Ref, "2030-01-01T10")), 0, "with the accepted count given back")
}

Method TestNoProductionHeader()
{
	Set ^OcuTalonTest("HookProbe", "now") = "2030-01-01T10:15:30Z"
	Set ^OcuTalonTest("HookProbe", "header") = 1
	Do ..Post(..Ref, ..#SECRET, "{}", .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "the event is accepted")
	Do $$$AssertEquals(response.GetHeader(##class(OcuTalon.Web.Hook).#SUPERSESSIONHEADER), "", "and the answer carries no SuperSession header")
	Set ^OcuTalonTest("HookProbe", "mode") = "fail"
	Do ..Post(..Ref, ..#SECRET, "{}", .response)
	Do $$$AssertEquals(response.Status, "503 Service Unavailable", "a hand-over that fails is 503")
	Do $$$AssertEquals(response.GetHeader(##class(OcuTalon.Web.Hook).#SUPERSESSIONHEADER), "", "and that answer carries none either")
}

Method TestLogsHoldNothing()
{
	Set ^OcuTalonTest("HookProbe", "now") = "2030-01-01T10:15:30Z"
	Do ..Post(..Ref, "wrong-secret-value", "{""secret-body"":1}", .response)
	Set ^OcuTalonTest("HookProbe", "mode") = "fail"
	Do ..Post(..Ref, ..#SECRET, "{""secret-body"":1}", .response)
	Set logs = ..Logs()
	Do $$$AssertTrue((logs '[ "wrong-secret-value") && (logs '[ ..#SECRET) && (logs '[ "secret-body") && (logs '[ "X-OcuTalon-Webhook-Secret"), "no console line holds a secret, a body or a header")
}

/// --- helpers ---
/// Calls Receive of the probe with the secret and body; response is the %response. size is 1 when the test set "size" itself.
Method Post(ref As %String, secret As %String, body As %String, Output response, keepSize As %Boolean = 0) As %String [ Private ]
{
	Set ^OcuTalonTest("HookProbe", "secret") = secret
	Set ^OcuTalonTest("HookProbe", "body") = body
	If 'keepSize Kill ^OcuTalonTest("HookProbe", "size")
	New %request, %response
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/hook/", "POST")
	Set %response = ##class(%CSP.Response).%New()
	Set %response.Status = ""
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, "Receive", ref)
	Do $$$AssertStatusOK(sc, "Receive returns OK")
	Set response = %response
	Quit written
}

/// Dispatches the URL (below the application) and method through the probe, as the CSP server does; response is the %response.
Method Dispatch(url As %String, method As %String, Output response) As %String [ Private ]
{
	New %request, %response
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/hook/", method)
	Set %response = ##class(%CSP.Response).%New()
	Set %response.Status = ""
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, "DispatchRequest", url, method)
	Do $$$AssertStatusOK(sc, "DispatchRequest returns OK")
	Set response = %response
	Quit written
}

/// The console lines of the probe, joined with line feeds.
Method Logs() As %String [ Private ]
{
	Set text = ""
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("HookProbe", "logs", n), 1, line)
		Quit:n=""
		Set text = text_line_$Char(10)
	}
	Quit text
}

/// Kills the hook's accepted-event counters and rejection slots of the fixture webhooks.
Method DropCounters() [ Private ]
{
	Set id = ""
	For {
		Set id = $Order(^OcuTalonTest("Fixture", "OcuTalon.Data.Webhook", id), 1, ref)
		Quit:id=""
		Kill ^OcuTalonP.WebhookC("a", ref)
		Kill ^OcuTalonP.WebhookC("r", ref)
	}
}

}
