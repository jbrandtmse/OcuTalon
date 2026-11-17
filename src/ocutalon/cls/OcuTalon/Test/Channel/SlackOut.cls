Include Ensemble

/// Tests of the operation SlackOut (Story 27.2; AD-14, AD-19, AD-25, AD-26, NFR-11, R8, R9; Contest Planner rulings 2026-11-17). They need no production: each test calls OnOutbound
/// on a shadow instance of the real operation, which posts to CI's mock (the Slack side of Test.Contract.Mock, reset before every test; OCUTALON_SLACK_API_BASE and the fake SLACK_*
/// values are put in the environment of the process and restored). A run that cannot reach the mock fails with the reason and sends nothing anywhere else.
///   - TestReply: a reply to a linked member is one chat.postMessage to the member, with Telegram's text (the check sentence included), mrkdwn and both unfurls false, and one
///     Delivery row "<link Ref>:<ts>" with no text;
///   - TestEscaped: & < > go out as &amp; &lt; &gt;, & first, so that a typed entity stays as typed;
///   - TestNonAscii: accents, an ellipsis, CJK letters and an emoji reach the mock as the same characters, each encoded once;
///   - TestSplit: a reply over 4,000 units goes in parts cut at line breaks, in order, and one row holds the last part's ts; the escaping comes after the cut;
///   - TestNoResendAfterFailure: a part that fails stops the reply, the parts after it are not sent, a part that was sent is not sent again and no row is kept;
///   - TestRateLimited: a 429 with Retry-After 1 waits and sends the same part again, a 429 with no header waits 1 s, one with Retry-After 2 waits 2 s, and a reply that is always limited gives up after TRIES;
///   - TestRateLimitedGivesUp: a reply that is limited on every try is posted 5 times and then fails with the plain reason, with no row;
///   - TestWaitTooLong: a Retry-After over 30 s is not taken: one call, the reply's fixed reason and no row;
///   - TestSlackError: an ok false, an HTTP 500, an error code that is no code and a base that does not parse each give their fixed text and no row, and an ok with no ts is taken;
///   - TestUnreachable: a server that does not answer in time gives the fixed text ERRORREACH and no row;
///   - TestTokenNeverLogged: the token is in no status text, no event-log row, no row and no call of the mock, also when Slack's error code is the token;
///   - TestNoMember: a session with no link sends nothing, with one warning and an OK status, and an owner that is not a session is dropped with its own warning;
///   - TestOffAndOnlineDemo: with either variable empty, or on the online demo, the status is the error ERROROFF and nothing is sent;
///   - TestOnlyOutboundMapped: the compiled message map names OcuTalon.Msg.Outbound and nothing else, and a Notification handed to the operation's dispatcher
///     (MessageHandler, the superclasses' maps included) is refused and posts nothing, where an Outbound is posted;
///   - TestRecordHoldsNoIds: the Delivery row and the event log hold neither the member id, nor the text, nor the token.
///   - TestSplitBoundary (QA): a text of exactly 4,000 units is one post, one of 4,001 is two, and a surrogate pair is never cut;
///   - TestRetryAfterFloorAndCeiling (QA): a Retry-After of 0 or one that is not a number waits 1 s, not none, and 31 s is refused at once, 30 s being the most; on
///     Test.Channel.SlackOutProbe (MAXWAIT 2) a Retry-After equal to MAXWAIT is waited and taken and one over it is refused;
///   - TestStrictAnswer (QA): an ok that is not a JSON boolean (the number 1) is not taken, and a ts that is not seconds.digits is dropped from the Delivery row, never kept as text;
///   - TestBlankTextPostsNothing (QA): a reply of white space only posts nothing, records no row and is an OK status;
///   - TestRecordFailureIsAWarning (QA): a Delivery row that cannot be saved after the reply was sent is one warning with its fixed reason and an OK status;
///   - TestCheckWarning (QA): a check key that gives no sentence sends the reply alone, with one warning with its fixed reason, and still records the row.
/// The run's number is n from ^OcuTalonTest("SlackOut","n").
Class OcuTalon.Test.Channel.SlackOut Extends %UnitTest.TestCase
{

Parameter TEAM = "T0SLACKOUT";

Parameter MEMBER = "U0SLACKOUT";

Parameter BASE = "http://mock:8080/api";

/// The mock's request log, which the iris container reads from the mock-log volume.
Parameter MOCKLOG = "/opt/ocutalon/mock-log/requests.jsonl";

Parameter SECRET = "zz-slackout-secret";

/// A token of letters and digits only, so that it can pass for a Slack error code.
Parameter TOKEN = "zzSlackOutTokenValue";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture sessions of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

Property SavedOnline As %String;

Property Saved As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("SlackOut", "n"))
	Set ..Refs = ""
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..Saved = ""
	For name = "SLACK_SIGNING_SECRET", "SLACK_BOT_TOKEN", "OCUTALON_SLACK_API_BASE" {
		Set ..Saved = ..Saved_$ListBuild($ListBuild(name, ##class(OcuTalon.Test.Agent.KeyScan).HasEnv(name), $SYSTEM.Util.GetEnviron(name)))
	}
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SlackLink WHERE TeamId = ?", ..#TEAM)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do ..SetEnvironment(..#SECRET, ..#TOKEN, ..#BASE)
	Do ##class(OcuTalon.Test.Contract.Mock).Control("reset", "", "slack")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Set position = 0
	While $ListNext(..Saved, position, saved) {
		If $List(saved, 2) {
			Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv($List(saved, 1), $List(saved, 3))
		} Else {
			Do ##class(OcuTalon.Test.Agent.KeyScan).UnsetEnv($List(saved, 1))
		}
	}
	Do ##class(OcuTalon.Test.Contract.Mock).Control("reset", "", "slack")
	For i = 1:1:$Length(..Refs, ",") {
		Set ref = $Piece(..Refs, ",", i)
		If ref '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Delivery WHERE OwnerRef = ?", ref)
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SlackLink WHERE TeamId = ?", ..#TEAM)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $$$OK
}

Method TestReply()
{
	Set session = ..LinkedSession("reply")
	If '..MockReady() Quit
	Set message = ..Outbound(session, "zz hello from OcuTalon")
	Set message.CheckKey = "checks.allPassed"
	Set message.CheckRows = "[]"
	Set sc = ..Out().OnOutbound(message, .response)
	Do $$$AssertStatusOK(sc, "the reply is handled with an OK status")
	Set calls = ##class(OcuTalon.Test.Contract.Mock).Calls("slack")
	Do $$$AssertEquals(calls.%Size(), 1, "one call to the mock")
	If calls.%Size() '= 1 Quit
	Set call = calls.%Get(0)
	Do $$$AssertEquals(call.method, "chat.postMessage", "the method is chat.postMessage")
	Set params = call.params
	Do $$$AssertEquals(params.channel, ..#MEMBER, "channel is the linked member")
	Do $$$AssertEquals(params.text, "zz hello from OcuTalon"_$Char(10, 10)_"Everything I checked passed.", "the text is the reply, a blank line and the check sentence, as Telegram sends it")
	Do $$$AssertEquals(params.%GetTypeOf("mrkdwn")_"|"_params.mrkdwn, "boolean|0", "mrkdwn is false")
	Do $$$AssertEquals(params.%GetTypeOf("unfurl_links")_"|"_params."unfurl_links", "boolean|0", "unfurl_links is false")
	Do $$$AssertEquals(params.%GetTypeOf("unfurl_media")_"|"_params."unfurl_media", "boolean|0", "unfurl_media is false")
	Do $$$AssertEquals(..Keys(params), "channel,mrkdwn,text,unfurl_links,unfurl_media", "and the body holds nothing else")
	Do $$$AssertEquals(..LastPostTokenLength(), $Length(..#TOKEN), "the Authorization header held the bot token (its length, as the mock logs it), not the signing secret")
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(rows.Count(), 1, "one Delivery row")
	If rows.Count() '= 1 Quit
	Set row = rows.GetAt(1)
	Do $$$AssertEquals(row.Channel_"|"_row.Kind_"|"_row.Text_"|"_row.ApprovalRef, "slack|||", "of channel slack, with no kind, text or approval")
	Set linkRef = ##class(OcuTalon.Data.SlackLink).SessionRefIndexOpen(session).Ref
	Do $$$AssertEquals($Piece(row.ChannelMessageId, ":", 1), linkRef, "its message id starts with the link's Ref")
	Do $$$AssertTrue($Match($Piece(row.ChannelMessageId, ":", 2), "^[0-9]{10}\.000001$"), "and ends with the ts that the mock answered")
}

Method TestEscaped()
{
	Set session = ..LinkedSession("escaped")
	If '..MockReady() Quit
	Set sc = ..Out().OnOutbound(..Outbound(session, "a & b < c > d &amp; &lt; <@U0X> *bold*"), .response)
	Do $$$AssertStatusOK(sc, "the reply is handled")
	Set calls = ##class(OcuTalon.Test.Contract.Mock).Calls("slack")
	Do $$$AssertEquals(calls.%Size(), 1, "one call")
	If calls.%Size() = 1 Do $$$AssertEquals(calls.%Get(0).params.text, "a &amp; b &lt; c &gt; d &amp;amp; &amp;lt; &lt;@U0X&gt; *bold*", "& < > are written as entities, & first, and nothing else changes")
}

Method TestNonAscii()
{
	Set session = ..LinkedSession("nonascii")
	If '..MockReady() Quit
	Set text = "caf"_$Char(233)_" "_$Char(8230)_" "_$Char(26085, 26412)_" "_$Char(55357, 56832)
	Set sc = ..Out().OnOutbound(..Outbound(session, text), .response)
	Do $$$AssertStatusOK(sc, "a reply with accents, an ellipsis, CJK letters and an emoji is handled")
	Set calls = ##class(OcuTalon.Test.Contract.Mock).Calls("slack")
	Do $$$AssertEquals(calls.%Size(), 1, "one call")
	If calls.%Size() = 1 Do $$$AssertEquals(calls.%Get(0).params.text, text, "the mock reads the characters that were sent, each encoded once")
}

Method TestSplit()
{
	Set session = ..LinkedSession("split")
	If '..MockReady() Quit
	Set a = $Translate($Justify("", 3000), " ", "A")
	Set b = $Translate($Justify("", 3000), " ", "B")
	Set c = $Translate($Justify("", 999), " ", "C")
	Set sc = ..Out().OnOutbound(..Outbound(session, a_$Char(10)_b_$Char(10)_c), .response)
	Do $$$AssertStatusOK(sc, "a long reply is handled")
	Set calls = ##class(OcuTalon.Test.Contract.Mock).Calls("slack")
	Do $$$AssertEquals(calls.%Size(), 2, "it goes in two parts: a part is cut at a line break, and the rest fits one")
	If calls.%Size() = 2 {
		Do $$$AssertEquals(calls.%Get(0).params.text, a, "the first part is the first line")
		Do $$$AssertEquals(calls.%Get(1).params.text, b_$Char(10)_c, "the second part is the rest")
	}
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(rows.Count(), 1, "one Delivery row")
	If rows.Count() = 1 Do $$$AssertTrue($Match($Piece(rows.GetAt(1).ChannelMessageId, ":", 2), "^[0-9]{10}\.000002$"), "which holds the ts of the last part")
	Do ##class(OcuTalon.Test.Contract.Mock).Control("reset", "", "slack")
	Set marks = $Translate($Justify("", 3900), " ", "&")
	Set sc = ..Out().OnOutbound(..Outbound(session, marks), .response)
	Do $$$AssertStatusOK(sc, "a part that is escaped to over 4,000 units is handled")
	Set calls = ##class(OcuTalon.Test.Contract.Mock).Calls("slack")
	Do $$$AssertEquals(calls.%Size(), 1, "the cut is made before the escaping: one call")
	If calls.%Size() = 1 Do $$$AssertEquals($Length(calls.%Get(0).params.text), 3900 * 5, "and its text is the escaped part")
}

Method TestNoResendAfterFailure()
{
	Set session = ..LinkedSession("noresend")
	If '..MockReady() Quit
	Set a = $Translate($Justify("", 3000), " ", "A")
	Set b = $Translate($Justify("", 3000), " ", "B")
	Set c = $Translate($Justify("", 3000), " ", "C")
	Do ##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "chat.postMessage", "replies": [{"status": 200, "body": {"ok": true, "channel": "D0X", "ts": "1700000000.000100"}}, {"status": 200, "body": {"ok": false, "error": "channel_not_found"}}]}, "slack")
	Set sc = ..Out().OnOutbound(..Outbound(session, a_$Char(10)_b_$Char(10)_c), .response)
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "a reply whose second part fails is an error")
	Set calls = ##class(OcuTalon.Test.Contract.Mock).Calls("slack")
	Do $$$AssertEquals(calls.%Size(), 2, "two calls: the part after the failed one is not sent")
	If calls.%Size() = 2 Do $$$AssertEquals(calls.%Get(0).params.text_"|"_calls.%Get(1).params.text, a_"|"_b, "each part was posted once, in order: the sent part is not sent again")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, "and no Delivery row is kept")
}

Method TestRateLimited()
{
	Set session = ..LinkedSession("limited")
	If '..MockReady() Quit
	Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "slack-rate-limited"}, "slack"), "the 429 scenario with Retry-After 1 is queued")
	Set start = $ZHorolog
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz limited once"), .response)
	Set elapsed = $ZHorolog - start
	Do $$$AssertStatusOK(sc, "after the 429 the same part is sent and taken")
	Do $$$AssertTrue(elapsed >= 0.95, "OnOutbound waited the Retry-After second ("_elapsed_" s)")
	Set calls = ##class(OcuTalon.Test.Contract.Mock).Calls("slack")
	Do $$$AssertEquals(calls.%Size(), 2, "two calls")
	If calls.%Size() = 2 Do $$$AssertEquals(calls.%Get(0).params.text_"|"_calls.%Get(1).params.text, "zz limited once|zz limited once", "with the same part")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 1, "one Delivery row")
	Do ##class(OcuTalon.Test.Contract.Mock).Control("reset", "", "slack")
	Do ##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "chat.postMessage", "replies": [{"status": 429, "body": {"ok": false, "error": "ratelimited"}}]}, "slack")
	Set start = $ZHorolog
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz limited no header"), .response)
	Do $$$AssertStatusOK(sc, "a 429 with no Retry-After header is retried")
	Do $$$AssertTrue($ZHorolog - start >= 0.95, "after one second")
	Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 2, "with two calls")
	Do ##class(OcuTalon.Test.Contract.Mock).Control("reset", "", "slack")
	Do ##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "chat.postMessage", "replies": [{"status": 429, "headers": {"Retry-After": "2"}, "body": {"ok": false, "error": "ratelimited"}}]}, "slack")
	Set start = $ZHorolog
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz limited two seconds"), .response)
	Do $$$AssertStatusOK(sc, "a 429 with Retry-After 2 is retried")
	Do $$$AssertTrue($ZHorolog - start >= 1.95, "after the two seconds that Slack asked for")
}

/// A reply that is limited on every try gives up after TRIES tries: each retry waits Retry-After 1.
Method TestRateLimitedGivesUp()
{
	Set session = ..LinkedSession("giveup")
	If '..MockReady() Quit
	Set limited = {"status": 429, "headers": {"Retry-After": "1"}, "body": {"ok": false, "error": "ratelimited"}}
	Do ##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "chat.postMessage", "replies": [(limited), (limited), (limited), (limited), (limited), (limited)]}, "slack")
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz always limited"), .response)
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "a reply that is limited on every try is an error")
	Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 5, "after 5 tries, and no more")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "Slack did not take the reply (HTTP 429, error ratelimited), so it was not sent to Slack.", "with the plain reason: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, "and no row")
}

Method TestWaitTooLong()
{
	Set session = ..LinkedSession("toolong")
	If '..MockReady() Quit
	Do ##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "chat.postMessage", "replies": [{"status": 429, "headers": {"Retry-After": "120"}, "body": {"ok": false, "error": "ratelimited"}}]}, "slack")
	Set start = $ZHorolog
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz asked to wait"), .response)
	Do $$$AssertTrue($ZHorolog - start < 5, "a wait over 30 s is not taken")
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "the reply is an error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "Slack asked OcuTalon to wait 120 seconds, longer than the 30 it waits, so the reply was not sent to Slack.", "with its fixed reason: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 1, "after one call")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, "and no row")
}

Method TestSlackError()
{
	Set session = ..LinkedSession("error")
	If '..MockReady() Quit
	Do ##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "slack-not-found"}, "slack")
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz not found"), .response)
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "Slack did not take the reply (HTTP 200, error channel_not_found), so it was not sent to Slack.", "an ok false is the fixed reason with Slack's error code: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 1, "after one call: no retry")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, "and no row")
	Do ##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "chat.postMessage", "replies": [{"status": 500, "body": {"ok": false, "error": "fatal_error"}}, {"status": 200, "body": {"ok": false, "error": "a code with spaces <@U0X>"}}, {"status": 200, "body": {"ok": true}}]}, "slack")
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz http 500"), .response)
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "(HTTP 500, error fatal_error)", "an HTTP 500 fails at once, with its status: "_$SYSTEM.Status.GetErrorText(sc))
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz odd code"), .response)
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "(HTTP 200, error none)", "an error code that is not letters, digits and underscores is none: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) '[ "U0X", "and nothing of it is in the text")
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz ok without ts"), .response)
	Do $$$AssertStatusOK(sc, "an ok true with no ts is taken")
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(rows.Count(), 1, "and records one row")
	If rows.Count() = 1 Do $$$AssertEquals($Piece(rows.GetAt(1).ChannelMessageId, ":", 2), "", "with nothing after the colon")
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("OCUTALON_SLACK_API_BASE", "ftp://mock:8080/api")
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz bad base"), .response)
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OCUTALON_SLACK_API_BASE must be http(s)://host[:port][/path].", "a base that does not parse is the fixed text: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 1, "and none of the failures made a row")
}

/// A server that gives no answer in time is the fixed text ERRORREACH and no row (the probe waits one second, not fifteen).
Method TestUnreachable()
{
	Set session = ..LinkedSession("unreachable")
	If '..MockReady() Quit
	Do ##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "chat.postMessage", "replies": [{"status": 200, "delayMs": 3000, "body": {"ok": true, "ts": "1700000000.000100"}}]}, "slack")
	Set out = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Channel.SlackOutProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set sc = out.OnOutbound(..Outbound(session, "zz nobody answers"), .response)
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon could not reach Slack, so the reply was not sent to Slack.", "a server that does not answer is the fixed text: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, "and no row is recorded")
}

Method TestTokenNeverLogged()
{
	Set session = ..LinkedSession("token")
	If '..MockReady() Quit
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set texts = ""
	Do ##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "chat.postMessage", "replies": [{"status": 200, "body": {"ok": false, "error": (..#TOKEN)}}, {"status": 429, "headers": {"Retry-After": "300"}, "body": {"ok": false, "error": (..#TOKEN)}}]}, "slack")
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz token one"), .response)
	Set texts = texts_$SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "Slack's error code is the token: the reply fails")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "(HTTP 200, error [redacted])", "and the token is stripped from the text: "_$SYSTEM.Status.GetErrorText(sc))
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz token two"), .response)
	Set texts = texts_$SYSTEM.Status.GetErrorText(sc)
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz token three"), .response)
	Set texts = texts_$SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue(texts '[ ..#TOKEN, "no status text holds the token")
	Do $$$AssertTrue(texts '[ ..#MEMBER, "or the member id")
	Do ..AssertLogHolds(mark, ..#TOKEN, 0, "the token")
	Set mock = ##class(OcuTalon.Test.Contract.Mock).Calls("slack").%ToJSON()
	Do $$$AssertTrue(mock '[ ..#TOKEN, "the mock's call list does not hold the token: it is sent in the header only")
}

Method TestNoMember()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzslo"_..Number_"nomember")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_session
	If '..MockReady() Quit
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz nobody linked"), .response)
	Do $$$AssertStatusOK(sc, "a session with no link is handled with an OK status")
	Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 0, "nothing is sent")
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "OnOutbound", "SlackOut found no linked Slack member")
	Do $$$AssertEquals(count, 1, "with one warning")
	Do $$$AssertEquals(text, "SlackOut found no linked Slack member for this session, so the reply went only to the web chat.", "its fixed text")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, "and no row")
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set sc = ..Out().OnOutbound(..Outbound("zznosession"_..Number, "zz not a session"), .response)
	Do $$$AssertStatusOK(sc, "an owner that is not a session is dropped with an OK status")
	Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 0, "and nothing is sent")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, , "IsSession", "SlackOut dropped a message: its owner is not a session: "), 1, "with the one warning of a dropped owner")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, , "OnOutbound", "SlackOut found no linked Slack member"), 0, "and not the warning of a session with no link")
}

Method TestOffAndOnlineDemo()
{
	Set session = ..LinkedSession("off")
	If '..MockReady() Quit
	Set off = "Slack is off, so SlackOut sends nothing."
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_SIGNING_SECRET", "")
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz no secret"), .response)
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ off, "with no signing secret SlackOut refuses: "_$SYSTEM.Status.GetErrorText(sc))
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_SIGNING_SECRET", ..#SECRET)
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", "")
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz no token"), .response)
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ off, "with no token it refuses: "_$SYSTEM.Status.GetErrorText(sc))
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", ..#TOKEN)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz demo"), .response)
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ off, "on the online demo it refuses: "_$SYSTEM.Status.GetErrorText(sc))
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 0, "no call was made")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, "and no row was recorded")
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz on again"), .response)
	Do $$$AssertStatusOK(sc, "control: with both variables set and the demo off the same reply is sent")
	Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 1, "with one call")
}

Method TestOnlyOutboundMapped()
{
	Set session = ..LinkedSession("mapped")
	If '..MockReady() Quit
	Set map = ##class(%Dictionary.CompiledXData).%OpenId("OcuTalon.Channel.Slack.Out||MessageMap")
	Do $$$AssertTrue($IsObject(map), "the compiled class has a message map")
	If '$IsObject(map) Quit
	Set xml = map.Data.Read(32000)
	Do $$$AssertEquals($Length(xml, "MessageType=") - 1, 1, "it has one map item")
	Do $$$AssertTrue(xml [ "MessageType=""OcuTalon.Msg.Outbound""", "and it names OcuTalon.Msg.Outbound")
	Do $$$AssertTrue(xml '[ "Notification", "and no Notification")
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = session
	Set notification.Kind = "tellnow"
	Set notification.CatalogKey = "digest.cost"
	Set sc = ..Out().MessageHandler(notification, .response)
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "a Notification handed to the operation's dispatcher (its whole message map, the superclasses' included) is refused")
	Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 0, "and posts nothing")
	Set sc = ..Out().MessageHandler(..Outbound(session, "zz through the dispatcher"), .response)
	Do $$$AssertStatusOK(sc, "control: an Outbound handed to the same dispatcher is handled")
	Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 1, "and posted once")
}

Method TestRecordHoldsNoIds()
{
	Set session = ..LinkedSession("ids")
	If '..MockReady() Quit
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set marker = "zzmarker"_..Number
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz text "_marker), .response)
	Do $$$AssertStatusOK(sc, "the reply is sent")
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(rows.Count(), 1, "one Delivery row")
	If rows.Count() = 1 {
		Set row = rows.GetAt(1)
		Set all = row.ChannelMessageId_"|"_row.Text_"|"_row.ApprovalRef_"|"_row.Kind_"|"_row.DecisionRef_"|"_row.FallbackReason_"|"_row.CheckRows_"|"_row.DigestKey
		Do $$$AssertTrue((all '[ marker) && (all '[ ..#MEMBER) && (all '[ ..#TEAM) && (all '[ ..#TOKEN) && (all '[ "D0MOCK"), "the row holds no text, member id, team id, token or Slack channel id")
	}
	Do ..AssertLogHolds(mark, marker, 0, "the text")
	Do ..AssertLogHolds(mark, ..#MEMBER, 0, "the member id")
	Do ..AssertLogHolds(mark, "D0MOCK", 0, "Slack's channel id")
}

/// (QA) The cut of the 4,000-unit limit: a text of exactly 4,000 units is one post, one of 4,001 units is two (4,000 and 1), and a surrogate pair at the cut goes whole in the second.
Method TestSplitBoundary()
{
	Set session = ..LinkedSession("boundary")
	If '..MockReady() Quit
	Set sc = ..Out().OnOutbound(..Outbound(session, $Translate($Justify("", 4000), " ", "A")), .response)
	Do $$$AssertStatusOK(sc, "a text of exactly 4,000 units is handled")
	Set calls = ##class(OcuTalon.Test.Contract.Mock).Calls("slack")
	Do $$$AssertEquals(calls.%Size(), 1, "it is one post")
	If calls.%Size() = 1 Do $$$AssertEquals($Length(calls.%Get(0).params.text), 4000, "of all 4,000 units")
	Do ##class(OcuTalon.Test.Contract.Mock).Control("reset", "", "slack")
	Set sc = ..Out().OnOutbound(..Outbound(session, $Translate($Justify("", 4001), " ", "A")), .response)
	Do $$$AssertStatusOK(sc, "a text of 4,001 units is handled")
	Set calls = ##class(OcuTalon.Test.Contract.Mock).Calls("slack")
	Do $$$AssertEquals(calls.%Size(), 2, "it is two posts")
	If calls.%Size() = 2 Do $$$AssertEquals($Length(calls.%Get(0).params.text)_"|"_$Length(calls.%Get(1).params.text), "4000|1", "of 4,000 units and 1")
	Do ##class(OcuTalon.Test.Contract.Mock).Control("reset", "", "slack")
	Set pair = $Char(55357, 56832)
	Set sc = ..Out().OnOutbound(..Outbound(session, $Translate($Justify("", 3999), " ", "A")_pair), .response)
	Do $$$AssertStatusOK(sc, "a pair that starts at the 4,000th unit is handled")
	Set calls = ##class(OcuTalon.Test.Contract.Mock).Calls("slack")
	Do $$$AssertEquals(calls.%Size(), 2, "it is two posts")
	If calls.%Size() = 2 Do $$$AssertEquals($Length(calls.%Get(0).params.text)_"|"_calls.%Get(1).params.text, "3999|"_pair, "the pair is not cut: it is whole in the second")
}

/// (QA) The bounds of Retry-After: 0 and text are not a wait of none but 1 s, and 31 s is over the 30 that is taken, so it is refused with one call.
Method TestRetryAfterFloorAndCeiling()
{
	Set session = ..LinkedSession("bounds")
	If '..MockReady() Quit
	For value = "0", "soon" {
		Do ##class(OcuTalon.Test.Contract.Mock).Control("reset", "", "slack")
		Do ##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "chat.postMessage", "replies": [{"status": 429, "headers": {"Retry-After": (value)}, "body": {"ok": false, "error": "ratelimited"}}]}, "slack")
		Set start = $ZHorolog
		Set sc = ..Out().OnOutbound(..Outbound(session, "zz retry after "_value), .response)
		Set elapsed = $ZHorolog - start
		Do $$$AssertStatusOK(sc, "a 429 with Retry-After "_value_" is retried and taken")
		Do $$$AssertTrue((elapsed >= 0.95) && (elapsed < 5), "after 1 s, as 'missing, not a number or below 1' is 1 ("_elapsed_" s)")
		Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 2, "with two calls")
	}
	Do ##class(OcuTalon.Test.Contract.Mock).Control("reset", "", "slack")
	Do ##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "chat.postMessage", "replies": [{"status": 429, "headers": {"Retry-After": "31"}, "body": {"ok": false, "error": "ratelimited"}}]}, "slack")
	Set start = $ZHorolog
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz thirty-one"), .response)
	Do $$$AssertTrue($ZHorolog - start < 5, "31 s is not waited")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "Slack asked OcuTalon to wait 31 seconds, longer than the 30 it waits", "it is refused with the fixed reason: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 1, "after one call")
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Channel.SlackOutProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe (MAXWAIT 2) is made")
	For value = "2", "3" {
		Do ##class(OcuTalon.Test.Contract.Mock).Control("reset", "", "slack")
		Do ##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "chat.postMessage", "replies": [{"status": 429, "headers": {"Retry-After": (value)}, "body": {"ok": false, "error": "ratelimited"}}]}, "slack")
		Set start = $ZHorolog
		Set sc = probe.OnOutbound(..Outbound(session, "zz probe retry after "_value), .response)
		Set elapsed = $ZHorolog - start
		If value = 2 {
			Do $$$AssertStatusOK(sc, "a Retry-After equal to MAXWAIT is taken")
			Do $$$AssertTrue(elapsed >= 1.95, "after the whole wait ("_elapsed_" s)")
			Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 2, "with two calls")
		} Else {
			Do $$$AssertTrue($SYSTEM.Status.IsError(sc) && (elapsed < 1.5), "one over MAXWAIT is refused at once ("_elapsed_" s)")
			Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 1, "after one call")
		}
	}
}

/// (QA) What counts as taken: an ok that is the number 1 is not a JSON boolean and fails, and a ts that is not seconds.digits is dropped (nothing after the colon), so that a row
/// never holds text that Slack's answer carried.
Method TestStrictAnswer()
{
	Set session = ..LinkedSession("strict")
	If '..MockReady() Quit
	Do ##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "chat.postMessage", "replies": [{"status": 200, "body": {"ok": 1, "ts": "1700000000.000100"}}, {"status": 200, "body": {"ok": true, "ts": "text <@U0SLACKOUT> 1.2"}}]}, "slack")
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz ok as number"), .response)
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "Slack did not take the reply (HTTP 200, error none)", "an ok that is the number 1, not the boolean true, is not taken: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, "and it makes no row")
	Set sc = ..Out().OnOutbound(..Outbound(session, "zz odd ts"), .response)
	Do $$$AssertStatusOK(sc, "an ok true with a ts that is not seconds.digits is taken")
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Do $$$AssertEquals(rows.Count(), 1, "and records one row")
	If rows.Count() = 1 {
		Set id = rows.GetAt(1).ChannelMessageId
		Do $$$AssertEquals($Piece(id, ":", 2, *), "", "with nothing after the colon: "_id)
		Do $$$AssertTrue((id '[ "U0SLACKOUT") && (id '[ "text"), "and none of the answer's text in it")
	}
}

/// (QA) A reply that has no printable text has no part: nothing is posted, no row is kept and the status is OK (Telegram's way, Api.Split drops a blank part).
Method TestBlankTextPostsNothing()
{
	Set session = ..LinkedSession("blank")
	If '..MockReady() Quit
	Set sc = ..Out().OnOutbound(..Outbound(session, "   "_$Char(10)_"  "), .response)
	Do $$$AssertStatusOK(sc, "a reply of white space only is handled with an OK status")
	Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 0, "nothing is posted")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, "and no row is kept: nothing was sent")
}

/// (QA) The reply was sent but its Delivery row cannot be saved (a DecisionRef longer than the column): one warning with its fixed reason, the status stays OK so that the reply is never
/// sent again, and the warning holds no id and no text.
Method TestRecordFailureIsAWarning()
{
	Set session = ..LinkedSession("recfail")
	If '..MockReady() Quit
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set message = ..Outbound(session, "zz record fails")
	Set message.DecisionRef = $Translate($Justify("", 40), " ", "D")
	Set sc = ..Out().OnOutbound(message, .response)
	Do $$$AssertStatusOK(sc, "the reply is handled with an OK status: it was sent and is not sent again")
	Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls("slack").%Size(), 1, "it was posted once")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 0, "no row was saved")
	Do ..AssertWarning(mark, "SlackOut sent the reply but could not record its delivery: ", "SlackOut sent the reply but could not record its delivery: the row was not saved")
	Do ..AssertLogHolds(mark, ..#MEMBER, 0, "the member id")
	Do ..AssertLogHolds(mark, "zz record fails", 0, "the text")
}

/// (QA) A check key that gives no sentence: the reply goes alone, with one warning with its fixed reason (the reason of Telegram's, not the check's own text), and its row is recorded.
Method TestCheckWarning()
{
	Set session = ..LinkedSession("checkwarn")
	If '..MockReady() Quit
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set message = ..Outbound(session, "zz reply alone")
	Set message.CheckKey = "checks.nope"
	Set message.CheckRows = [{"result": "failed", "entry": "Gamma", "finding": "Stopped", "checkedAt": ""}].%ToJSON()
	Set sc = ..Out().OnOutbound(message, .response)
	Do $$$AssertStatusOK(sc, "the reply is handled")
	Set calls = ##class(OcuTalon.Test.Contract.Mock).Calls("slack")
	Do $$$AssertEquals(calls.%Size(), 1, "one post")
	If calls.%Size() = 1 Do $$$AssertEquals(calls.%Get(0).params.text, "zz reply alone", "with the reply alone")
	Do ..AssertWarning(mark, "SlackOut sent the reply without its check sentence: ", "SlackOut sent the reply without its check sentence: the sentence could not be built")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 1, "and the row is recorded")
}

/// --- helpers ---
/// A fixture session with the fixture member linked to it; its Ref is kept for the clean-up.
Method LinkedSession(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzslo"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Do ##class(OcuTalon.Data.SlackLink).Link(..#TEAM, ..#MEMBER, ref, .sc)
	Do $$$AssertStatusOK(sc, "the fixture member is linked to the session")
	Quit ref
}

/// A shadow instance of the real operation.
Method Out() As OcuTalon.Channel.Slack.Out [ Private ]
{
	Set out = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Channel.Slack.Out", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the operation is made")
	Quit out
}

/// An Outbound of a Slack turn for the session with the text.
Method Outbound(owner As %String, text As %String) As OcuTalon.Msg.Outbound [ Private ]
{
	Set outbound = ##class(OcuTalon.Msg.Outbound).%New()
	Set outbound.SessionRef = owner
	Set outbound.OriginChannel = "slack"
	Set outbound.Text = text
	Quit outbound
}

/// 1 when the mock's Slack side answers (and was reset); otherwise a failed assertion names the reason.
Method MockReady() As %Boolean [ Private ]
{
	Set ready = ##class(OcuTalon.Test.Contract.Mock).Control("reset", "", "slack")
	If 'ready Do $$$AssertTrue(0, "the CI mock's Slack side is not reachable at "_..#BASE_": this test needs the throwaway stack's mock")
	Quit ready
}

/// The length of the bearer token of the last chat.postMessage in the mock's request log (the mock logs the length and never the token), -1 when the log has none.
ClassMethod LastPostTokenLength() As %Integer [ Private ]
{
	Set length = -1
	Set stream = ##class(%Stream.FileCharacter).%New()
	Set sc = stream.LinkToFile(..#MOCKLOG)
	If $SYSTEM.Status.IsError(sc) Quit length
	While 'stream.AtEnd {
		Set line = stream.ReadLine()
		If line '[ """slackMethod"":""chat.postMessage""" Continue
		Try {
			Set entry = {}.%FromJSON(line)
			If entry.%GetTypeOf("tokenLength") = "number" Set length = entry.tokenLength
		} Catch {
		}
	}
	Quit length
}

/// The environment of the process: the signing secret, the bot token and the base of the Web API.
Method SetEnvironment(secret As %String, token As %String, base As %String) [ Private ]
{
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_SIGNING_SECRET", secret)
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("SLACK_BOT_TOKEN", token)
	Do ##class(OcuTalon.Test.Agent.KeyScan).SetEnv("OCUTALON_SLACK_API_BASE", base)
}

/// The names of a dynamic object's properties, sorted, comma-separated.
ClassMethod Keys(object As %DynamicObject) As %String [ Private ]
{
	Set list = ""
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set list = list_$ListBuild(key)
	}
	Set sorted = ""
	Set position = 0
	While $ListNext(list, position, key) {
		Set sorted(key) = ""
	}
	Set key = ""
	Set out = ""
	For {
		Set key = $Order(sorted(key))
		If key = "" Quit
		Set out = out_$Select(out = "": "", 1: ",")_key
	}
	Quit out
}

/// (QA) Asserts that exactly one warning after the mark starts with the text, and that the newest one is exactly the fixed text.
Method AssertWarning(mark As %Integer, start As %String, fixed As %String) [ Private ]
{
	Set count = 0
	Set text = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Text %STARTSWITH ? ORDER BY ID", mark, start)
	While result.%Next() {
		Set count = count + 1
		Set text = result.%Get("Text")
	}
	Do $$$AssertEquals(count, 1, "one warning starts '"_start_"'")
	Do $$$AssertEquals(text, fixed, "and it is the fixed text")
}

/// Asserts that the event-log rows after the mark hold the value (count 1) or none do (count 0).
Method AssertLogHolds(mark As %Integer, value As %String, wanted As %Boolean, label As %String) [ Private ]
{
	Set held = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ?", mark)
	While result.%Next() {
		If result.%Get("Text") [ value Set held = held + 1
	}
	Do $$$AssertEquals(''held, wanted, "no event-log row after the mark holds "_label)
}

}
