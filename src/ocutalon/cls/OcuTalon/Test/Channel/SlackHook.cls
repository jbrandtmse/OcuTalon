/// Tests of the Slack route POST /slack/events of the hook application (Story 27.1; AD-13, AD-17, AD-19; Contest Planner rulings R3, R4, R5 and R9), called with
/// stand-in request and response objects through Test.Channel.SlackHookProbe, which carries the body bytes, the two Slack headers, the size, the clock and the flags from
/// ^OcuTalonTest("HookProbe") and records what the route hands to SlackIn. The probe's clock starts at the real time of each test, so that the web area's purge of the
/// rejection counters (Data.Webhook PurgeCounters, which writes an entry for a slot stamped in the future) cannot write an audit entry in the middle of a test. The signing secret and the bot token are fake values that the test puts in the environment of
/// its process and restores afterwards. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): the rejections write real audit entries. The signatures are made here,
/// from the secret and the bytes, and not by the product's class.
///   - TestChallenge: a signed url_verification answers 200 with the challenge as text/plain and hands nothing over;
///   - TestUnsignedChallenge401: R3, the same challenge with no signature is 401 with no body, so the challenge is never echoed;
///   - TestUnsigned: a missing signature, a missing timestamp, a wrong signature and a timestamp 301 s old or 301 s ahead are each 401 with no body and hand nothing over;
///     300 s either way is accepted;
///   - TestEvent: a signed event_callback answers 200 with no body and hands one Event over with its fields; nothing is counted as a rejection, nothing is claimed by the
///     route, and the answer carries no SuperSession header;
///   - TestRawBytesAreSigned: a signature made over the UTF-8 bytes of a body with a non-ASCII text is accepted and the Event's text is the decoded text;
///   - TestTooBig: 65,537 bytes are 413, counted, before the body is read; exactly 65,536 are accepted;
///   - TestNotJson: signed text, a scalar, an array, an empty body and a signed form are each 400, counted, and hand nothing over;
///   - TestOffWhenUnset: with either variable empty the route is 404 with no body, counts nothing and hands nothing over;
///   - TestOnlineDemo: with the online demo on and both variables set the route is 404 and counts nothing;
///   - TestOtherMethods: GET, PUT, DELETE, OPTIONS, HEAD and PATCH on the route are 404 and a deeper path is 404, counted as nothing;
///   - TestRejectedStoresNothing: R5, a 401 and a stale request that carry a marker in the body count in the slot slack, write at most one audit entry in 60 s, hand nothing
///     over, leave no node in ^OcuTalonP.SlackE, and the marker is in no log line and no audit entry;
///   - TestRejectionAudit: the entries of the slot slack are one per 60 s, with the target slack and the count since the previous entry;
///   - TestUnavailable: a hand-over that fails or throws is 503 with no body, logged with a status code and no body, counted as nothing and not audited;
///   - TestNoProductionHeader: the SuperSession header that a hand-over sets is deleted from the 200 and from the 503;
///   - TestLogsHoldNothing: no console line holds the secret, the token, a body or a Slack id.
Class OcuTalon.Test.Channel.SlackHook Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Channel.SlackHookProbe";

Property SavedOnline As %String;

Property SavedSecret As %String;

Property SavedToken As %String;

Property HadSecret As %Boolean;

Property HadToken As %Boolean;

/// The fake signing secret of the run.
Property Secret As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..HadSecret = ##class(OcuTalon.Test.Agent.KeyScan).HasEnv("SLACK_SIGNING_SECRET")
	Set ..HadToken = ##class(OcuTalon.Test.Agent.KeyScan).HasEnv("SLACK_BOT_TOKEN")
	Set ..SavedSecret = $SYSTEM.Util.GetEnviron("SLACK_SIGNING_SECRET")
	Set ..SavedToken = $SYSTEM.Util.GetEnviron("SLACK_BOT_TOKEN")
	Set ..Secret = "zz-slack-secret-"_##class(OcuTalon.Bridge.Ids).NewRef()
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("HookProbe")
	Kill ^OcuTalonP.SlackE
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_SIGNING_SECRET", ..Secret)
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", "zz-slack-token-"_##class(OcuTalon.Bridge.Ids).NewRef())
	Set ^OcuTalonTest("HookProbe", "now") = ##class(OcuTalon.Data.Time).NowUtc()
	Kill ^OcuTalonP.WebhookC("r", "slack")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonP.WebhookC("r", "slack")
	Kill ^OcuTalonP.SlackE
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("HookProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	If ..HadSecret {
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_SIGNING_SECRET", ..SavedSecret)
	} Else {
		Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv("SLACK_SIGNING_SECRET")
	}
	If ..HadToken {
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", ..SavedToken)
	} Else {
		Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv("SLACK_BOT_TOKEN")
	}
	Quit $$$OK
}

Method TestChallenge()
{
	Set written = ..PostSigned("{""type"":""url_verification"",""challenge"":""zz-challenge-123""}", .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a signed url_verification is 200")
	Do $$$AssertEquals(response.ContentType, "text/plain", "as text/plain")
	Do $$$AssertEquals(written, "zz-challenge-123", "with the challenge as the body")
	Do $$$AssertEquals(..Sent(), 0, "and nothing is handed over")
	Do $$$AssertEquals(..Rejections(), 0, "or counted as a rejection")
	Do $$$AssertEquals($Data(^OcuTalonP.SlackE), 0, "or claimed")
	Set written = ..PostSigned("{""type"":""url_verification""}", .response)
	Do $$$AssertEquals(response.Status, "400 Bad Request", "a url_verification with no challenge is 400")
}

Method TestUnsignedChallenge401()
{
	Set written = ..Post("{""type"":""url_verification"",""challenge"":""zz-challenge-123""}", "", "", .response)
	Do $$$AssertEquals(response.Status, "401 Unauthorized", "R3: an unsigned url_verification is 401")
	Do $$$AssertEquals(written, "", "with no body, so the challenge is not echoed")
	Do $$$AssertEquals(..Rejections(), 1, "and it is counted in the slot slack")
	Do $$$AssertEquals(..Sent(), 0, "and nothing is handed over")
}

Method TestUnsigned()
{
	Set body = ..Event("Ev0UNSIGNED", "U0FIXTURE1", "hello")
	Set ts = ..Epoch()
	Set good = ..Sign(ts, body)
	Set cases = $ListBuild("no signature|"_ts_"|", "no timestamp||"_good, "wrong signature|"_ts_"|"_$Extract(good, 1, 66)_"00", "301 s old|"_(ts - 301)_"|"_..Sign(ts - 301, body), "301 s ahead|"_(ts + 301)_"|"_..Sign(ts + 301, body))
	Set position = 0
	While $ListNext(cases, position, one) {
		Set written = ..Post(body, $Piece(one, "|", 2), $Piece(one, "|", 3), .response)
		Do $$$AssertEquals(response.Status, "401 Unauthorized", $Piece(one, "|", 1)_": 401")
		Do $$$AssertEquals(written, "", $Piece(one, "|", 1)_": with no body")
	}
	Do $$$AssertEquals(..Sent(), 0, "nothing is handed over")
	Do $$$AssertEquals(..Rejections(), 5, "and each of the five is counted")
	Do ..Post(body, ts - 300, ..Sign(ts - 300, body), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "300 s old is accepted")
	Do ..Post(body, ts + 300, ..Sign(ts + 300, body), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "300 s ahead is accepted")
	Do $$$AssertEquals(..Sent(), 2, "and handed over")
}

Method TestEvent()
{
	Set written = ..PostSigned(..Event("Ev0ONE", "U0FIXTURE1", "hello there"), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a signed event_callback is 200")
	Do $$$AssertEquals(written, "", "with no body")
	Do $$$AssertEquals(..Sent(), 1, "one event is handed over")
	Do $$$AssertEquals(..SentField(1, "EventId")_"|"_..SentField(1, "EnvelopeType")_"|"_..SentField(1, "EventType")_"|"_..SentField(1, "ChannelType"), "Ev0ONE|event_callback|message|im", "with its ids and types")
	Do $$$AssertEquals(..SentField(1, "TeamId")_"|"_..SentField(1, "MemberId")_"|"_..SentField(1, "Text"), "T0FIXTURE1|U0FIXTURE1|hello there", "its team, member and text")
	Do $$$AssertEquals(..SentField(1, "Subtype")_"|"_..SentField(1, "BotId"), "|", "and no subtype or bot id")
	Do $$$AssertEquals(..Rejections(), 0, "nothing is counted as a rejection")
	Do $$$AssertEquals($Data(^OcuTalonP.SlackE), 0, "and the route claims nothing: SlackIn does")
	Set body = "{""type"":""event_callback"",""event_id"":""Ev0TWO"",""team_id"":""T0FIXTURE1"",""event"":{""type"":""message"",""channel_type"":""im"",""subtype"":""message_changed"",""bot_id"":""B0BOT"",""user"":""U0FIXTURE1"",""text"":""x""}}"
	Do ..PostSigned(body, .response)
	Do $$$AssertEquals(..SentField(2, "Subtype")_"|"_..SentField(2, "BotId"), "message_changed|B0BOT", "a subtype and a bot id are handed over as they came")
	Do ..PostSigned("{""type"":""event_callback"",""event_id"":""Ev0THREE"",""event"":""not an object""}", .response)
	Do $$$AssertEquals(response.Status, "200 OK", "an event that is not an object is still handed over")
	Do $$$AssertEquals(..SentField(3, "EventType")_"|"_..SentField(3, "EventId"), "|Ev0THREE", "with no event type")
	Do ..PostSigned("{""type"":""event_callback"",""event_id"":""" _ $Translate($Justify("", 70), " ", "x") _ """,""team_id"":123}", .response)
	Do $$$AssertEquals(..SentField(4, "EventId")_"|"_..SentField(4, "TeamId"), "|", "an event id of more than 64 characters, and a number where a string is expected, are left empty")
}

Method TestRawBytesAreSigned()
{
	Set bytes = "{""type"":""event_callback"",""event_id"":""Ev0UTF"",""team_id"":""T0FIXTURE1"",""event"":{""type"":""message"",""channel_type"":""im"",""user"":""U0FIXTURE1"",""text"":""caf"_$Char(195, 169)_"""}}"
	Do ..PostSigned(bytes, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a signature made over the UTF-8 bytes is accepted")
	Do $$$AssertEquals(..SentField(1, "Text"), "caf"_$Char(233), "and the text is the decoded character")
	Set decoded = $ZConvert(bytes, "I", "UTF8")
	Do ..Post(bytes, ..Epoch(), ..Sign(..Epoch(), decoded), .response)
	Do $$$AssertEquals(response.Status, "401 Unauthorized", "a signature made over the decoded text is not the signature of the bytes")
}

Method TestTooBig()
{
	Set max = ##class(OcuTalon.Data.Webhook).#BODYMAX
	Set ^OcuTalonTest("HookProbe", "size") = max + 1
	Set written = ..Post("{}", "", "", .response, 1)
	Do $$$AssertEquals(response.Status, "413 Content Too Large", "65,537 bytes are refused, even unsigned")
	Do $$$AssertEquals(written, "", "with no body")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("HookProbe", "bodyReads")), 0, "and the body is not read")
	Do $$$AssertEquals(..Rejections(), 1, "it is counted")
	Set prefix = "{""type"":""event_callback"",""event_id"":""Ev0BIG"",""pad"":"""
	Set suffix = """}"
	Set body = prefix_$Translate($Justify("", max - $Length(prefix) - $Length(suffix)), " ", "x")_suffix
	Do $$$AssertEquals($Length(body), max, "a body of exactly 65,536 bytes")
	Kill ^OcuTalonTest("HookProbe", "size")
	Do ..PostSigned(body, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "is accepted")
}

Method TestNotJson()
{
	Set bodies = $ListBuild("this is not json", "123", """abc""", "[1,2]", "", "{""a"":")
	Set position = 0
	While $ListNext(bodies, position, body) {
		Set written = ..PostSigned(body, .response)
		Do $$$AssertEquals(response.Status_"|"_written, "400 Bad Request|", "'"_body_"': 400 with no body")
	}
	Set ^OcuTalonTest("HookProbe", "form") = 1
	Set written = ..PostSigned("token=abc&team_id=T0", .response)
	Do $$$AssertEquals(response.Status_"|"_written, "400 Bad Request|", "a form is 400 with no body")
	Do $$$AssertEquals(..Sent(), 0, "nothing is handed over")
	Do $$$AssertEquals(..Rejections(), 7, "and each of the seven is counted")
}

Method TestOffWhenUnset()
{
	For name = "SLACK_SIGNING_SECRET", "SLACK_BOT_TOKEN" {
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(name, "")
		Set written = ..PostSigned(..Event("Ev0OFF", "U0FIXTURE1", "hi"), .response)
		Do $$$AssertEquals(response.Status_"|"_written, "404 Not Found|", name_" empty: 404 with no body")
		Set written = ..Post("{}", "", "", .response)
		Do $$$AssertEquals(response.Status, "404 Not Found", name_" empty: an unsigned request is 404 too, as any unknown path")
		Set ^OcuTalonTest("HookProbe", "size") = ##class(OcuTalon.Data.Webhook).#BODYMAX + 1
		Do ..Post("{}", "", "", .response, 1)
		Do $$$AssertEquals(response.Status, "404 Not Found", name_" empty: an oversize request is 404 too")
		Kill ^OcuTalonTest("HookProbe", "size")
		Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv(name, "zz-restored-"_name)
	}
	Do $$$AssertEquals(..Sent()_"|"_..Rejections(), "0|0", "nothing is handed over or counted")
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_SIGNING_SECRET", ..Secret)
	Do ..PostSigned(..Event("Ev0ON", "U0FIXTURE1", "hi"), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "with both set again it answers")
}

Method TestOnlineDemo()
{
	Set ^OcuTalonTest("HookProbe", "online") = 1
	Set written = ..PostSigned(..Event("Ev0DEMO", "U0FIXTURE1", "hi"), .response)
	Do $$$AssertEquals(response.Status_"|"_written, "404 Not Found|", "the online demo answers 404 to a signed event")
	Do $$$AssertEquals(..Sent()_"|"_..Rejections(), "0|0", "and hands over and counts nothing")
	Kill ^OcuTalonTest("HookProbe", "online")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..PostSigned(..Event("Ev0DEMO", "U0FIXTURE1", "hi"), .response)
	Do $$$AssertEquals(response.Status, "404 Not Found", "and so does the public flag itself")
}

Method TestOtherMethods()
{
	For method = "GET", "PUT", "OPTIONS", "HEAD", "DELETE", "PATCH" {
		Set written = ..Dispatch("/slack/events", method, .response)
		Do $$$AssertEquals(response.Status_"|"_written_"|"_response.GetHeader("Allow"), "404 Not Found||", method_" on the route is 404, with no body and no Allow header")
	}
	Set written = ..Dispatch("/slack/events/x", "POST", .response)
	Do $$$AssertEquals(response.Status_"|"_written, "404 Not Found|", "a deeper path is 404")
	Do $$$AssertEquals(..Sent()_"|"_..Rejections(), "0|0", "and none is handed over or counted")
}

Method TestRejectedStoresNothing()
{
	Set marker = "zz-marker-"_##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Settle()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set body = "{""type"":""event_callback"",""event_id"":""Ev0"_marker_""",""team_id"":""T0"_marker_""",""event"":{""type"":""message"",""channel_type"":""im"",""user"":""U0"_marker_""",""text"":"""_marker_"""}}"
	Do ..Post(body, "", "", .response)
	Do $$$AssertEquals(response.Status, "401 Unauthorized", "an unsigned request is 401")
	Set ts = ..Epoch() - 301
	Do ..Post(body, ts, ..Sign(ts, body), .response)
	Do $$$AssertEquals(response.Status, "401 Unauthorized", "a stale one is 401")
	Do ..Post(body, ..Epoch(), "v0=wrong", .response)
	Do $$$AssertEquals(response.Status, "401 Unauthorized", "a wrongly signed one is 401")
	Do $$$AssertEquals(..Rejections(), 3, "R5: the three are counted in the slot slack")
	Do $$$AssertEquals(..Sent(), 0, "nothing is handed over")
	Do $$$AssertEquals($Data(^OcuTalonP.SlackE), 0, "no event id is claimed")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", "slack", "", 1)
	Do $$$AssertEquals(entries.%Size(), 1, "and one audit entry is written for the three")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Action", "Action", "slack").%Size(), 1, "and no second one")
	Do $$$AssertTrue(entries.%ToJSON() '[ marker, "the audit entry holds no part of the body")
	Do $$$AssertTrue(..Logs() '[ marker, "and no console line does")
	Do $$$AssertTrue(..Everywhere(marker) = "", "the body's marker is in no key or value of the Slack globals: "_..Everywhere(marker))
}

Method TestRejectionAudit()
{
	Set start = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Settle()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	For i = 0:10:40 {
		Set ^OcuTalonTest("HookProbe", "now") = ##class(OcuTalon.Data.Time).AddSeconds(start, i)
		Do ..Post("{}", "", "", .response)
		Do $$$AssertEquals(response.Status, "401 Unauthorized", "rejection at +"_i_" seconds")
	}
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", "slack", "", 1)
	Do $$$AssertEquals(entries.%Size(), 1, "five rejections within 60 seconds write one audit entry")
	Set data = entries.%Get(0).data
	Do $$$AssertEquals(data.action_"|"_data.target_"|"_data.result_"|"_data.counts.rejected, "webhook_rejected|slack|rejected|1", "action webhook_rejected, target slack, counting the first rejection")
	Set ^OcuTalonTest("HookProbe", "now") = ##class(OcuTalon.Data.Time).AddSeconds(start, 61)
	Do ..Post("{}", "", "", .response)
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", "slack", "", 2)
	Do $$$AssertEquals(entries.%Size(), 2, "a rejection 61 seconds after the entry writes a second one")
	Do $$$AssertEquals(entries.%Get(1).data.counts.rejected, 5, "counting the rejections since the previous entry")
	Set ^OcuTalonTest("HookProbe", "mode") = "auditfail"
	Set ^OcuTalonTest("HookProbe", "now") = ##class(OcuTalon.Data.Time).AddSeconds(start, 200)
	Do ..Post("{}", "", "", .response)
	Do $$$AssertEquals(response.Status, "401 Unauthorized", "an audit write that fails changes no answer")
	Do $$$AssertTrue(..Logs() [ "audit entry could not be written", "and is logged")
}

Method TestUnavailable()
{
	Set marker = "zz-body-"_##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Settle()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	For mode = "fail", "throw" {
		Kill ^OcuTalonTest("HookProbe", "logs")
		Set ^OcuTalonTest("HookProbe", "mode") = mode
		Set written = ..PostSigned(..Event("Ev0"_marker, "U0FIXTURE1", marker), .response)
		Do $$$AssertEquals(response.Status_"|"_written, "503 Service Unavailable|", mode_": a hand-over that does not work is 503 with no body")
		Set logs = ..Logs()
		Do $$$AssertTrue(logs [ "SlackIn unavailable", mode_": the console line names the service")
		Do $$$AssertTrue((logs '[ marker) && (logs '[ ..Secret) && (logs '[ "U0FIXTURE1") && (logs '[ "T0FIXTURE1"), mode_": and holds no body, secret or Slack id")
	}
	Do $$$AssertEquals(..Rejections(), 0, "a 503 is not counted as a rejection")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Action", "Action", "slack").%Size(), 0, "and writes no audit entry")
}

Method TestNoProductionHeader()
{
	Set ^OcuTalonTest("HookProbe", "header") = 1
	Do ..PostSigned(..Event("Ev0HDR", "U0FIXTURE1", "hi"), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the event is accepted")
	Do $$$AssertEquals(response.GetHeader(##class(OcuTalon.Web.Hook).#SUPERSESSIONHEADER), "", "and the answer carries no SuperSession header")
	Set ^OcuTalonTest("HookProbe", "mode") = "fail"
	Do ..PostSigned(..Event("Ev0HDR2", "U0FIXTURE1", "hi"), .response)
	Do $$$AssertEquals(response.Status, "503 Service Unavailable", "a hand-over that fails is 503")
	Do $$$AssertEquals(response.GetHeader(##class(OcuTalon.Web.Hook).#SUPERSESSIONHEADER), "", "and that answer carries none either")
}

Method TestLogsHoldNothing()
{
	Do ..Post(..Event("Ev0LOG", "U0FIXTURE1", "secret-body"), "", "", .response)
	Set ^OcuTalonTest("HookProbe", "mode") = "fail"
	Do ..PostSigned(..Event("Ev0LOG2", "U0FIXTURE1", "secret-body"), .response)
	Set logs = ..Logs()
	Do $$$AssertTrue((logs '[ ..Secret) && (logs '[ "secret-body") && (logs '[ "U0FIXTURE1") && (logs '[ "T0FIXTURE1") && (logs '[ "SLACK_"), "no console line holds a secret, a body, a Slack id or a variable name")
}

/// --- helpers ---

/// Lets the audit entries of the earlier tests (each test's first rejection writes one) land before a test takes its mark, so that a late entry is not counted as this test's.
Method Settle() [ Private ]
{
	Hang 1
}

/// The JSON of an event_callback envelope for a direct message.
Method Event(eventId As %String, memberId As %String, text As %String) As %String [ Private ]
{
	Quit "{""type"":""event_callback"",""event_id"":"""_eventId_""",""team_id"":""T0FIXTURE1"",""event"":{""type"":""message"",""channel_type"":""im"",""user"":"""_memberId_""",""text"":"""_text_"""}}"
}

/// The seconds since 1970 of the probe's clock.
Method Epoch() As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Data.Time).Seconds(^OcuTalonTest("HookProbe", "now")) - ##class(OcuTalon.Data.Time).Seconds("1970-01-01T00:00:00Z")
}

/// Slack's v0 signature of the bytes at the timestamp, under the run's secret, made here from HMAC-SHA256.
Method Sign(timestamp As %String, bytes As %String) As %String [ Private ]
{
	Set mac = $SYSTEM.Encryption.HMACSHA(256, "v0:"_timestamp_":"_bytes, ..Secret)
	Set hex = ""
	For i = 1:1:$Length(mac) {
		Set hex = hex_$ZConvert($Extract("0"_$ZHex($Ascii(mac, i)), *-1, *), "L")
	}
	Quit "v0="_hex
}

/// A POST of the route with the body bytes and the two headers; response is the %response; keepSize 1 keeps the size that the test set.
Method Post(body As %String, timestamp As %String, signature As %String, Output response, keepSize As %Boolean = 0) As %String [ Private ]
{
	Set ^OcuTalonTest("HookProbe", "slackBody") = body
	Kill ^OcuTalonTest("HookProbe", "slackTs"), ^OcuTalonTest("HookProbe", "slackSig")
	If timestamp '= "" Set ^OcuTalonTest("HookProbe", "slackTs") = timestamp
	If signature '= "" Set ^OcuTalonTest("HookProbe", "slackSig") = signature
	If 'keepSize Kill ^OcuTalonTest("HookProbe", "size")
	New %request, %response
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/hook/", "POST")
	Set %response = ##class(%CSP.Response).%New()
	Set %response.Status = ""
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, "Slack")
	Do $$$AssertStatusOK(sc, "Slack returns OK")
	Set response = %response
	Quit written
}

/// A POST that is signed correctly at the probe's clock.
Method PostSigned(body As %String, Output response) As %String [ Private ]
{
	Set ts = ..Epoch()
	Quit ..Post(body, ts, ..Sign(ts, body), .response, $Data(^OcuTalonTest("HookProbe", "size")))
}

/// Dispatches the URL (below the application) and method through the probe, as the CSP server does.
Method Dispatch(url As %String, method As %String, Output response) As %String [ Private ]
{
	New %request, %response
	Set ^OcuTalonTest("HookProbe", "slackBody") = "{}"
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/hook/", method)
	Set %response = ##class(%CSP.Response).%New()
	Set %response.Status = ""
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, "DispatchRequest", url, method)
	Do $$$AssertStatusOK(sc, "DispatchRequest returns OK")
	Set response = %response
	Quit written
}

Method Sent() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("HookProbe", "slackSent"))
}

Method SentField(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("HookProbe", "slackSent", n, field))
}

/// The number of rejections of the slot slack that the hook has counted: those that its audit writes named and those still pending.
Method Rejections() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("HookProbe", "auditCounts")) + +$ListGet($Get(^OcuTalonP.WebhookC("r", "slack")), 2)
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

/// "" when no subscript or value of ^OcuTalonP.SlackE, the counters of the slot slack or the probe's recorded events holds the text; otherwise where it was found.
Method Everywhere(text As %String) As %String [ Private ]
{
	Set found = ""
	For global = "^OcuTalonP.SlackE", "^OcuTalonP.WebhookC" {
		Set ref = global
		For {
			Set ref = $Query(@ref, 1, value)
			Quit:ref=""
			If (ref [ text) || (value [ text) Set found = found_global_" "
		}
	}
	Quit found
}

}
