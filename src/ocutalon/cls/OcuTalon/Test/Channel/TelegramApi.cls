/// Tests of the Bot API client (Story 12.2; AD-14, AD-19, NFR-11). Only TestPlainHttpIgnoresSSLConfig needs the mock
/// and the CI dummy token (a throwaway stack or CI); without them it fails with the reason. The other tests run anywhere.
///   - TestSplitLineBreaks, TestSplitOneLongLine, TestSplitSurrogatePair, TestSplitLimits and TestSplitEmpty: Split cuts at the last line
///     break inside the limit, else at the limit, never inside a surrogate pair, never makes an empty part, and the parts joined (with a
///     line feed after a cut at a line break, with nothing after a cut at the limit) give the text back;
///   - TestEndpoint: good bases give their parts, and a bad base gives an error that names the setting and not the value;
///   - TestNoTokenInErrors: with a fake token set in the environment, a call to a closed port gives an error status that holds neither
///     the token nor /bot, for an http and an https base, and Safe removes the token;
///   - TestNoToken: with no token a call is not made, and the error says so;
///   - TestPlainHttpIgnoresSSLConfig (U-164 condition 2): an http:// base makes a plain request, so a missing SSL configuration changes
///     nothing, while an https:// base with a missing configuration is refused.
/// The process environment is put back as found after each test.
Class OcuTalon.Test.Channel.TelegramApi Extends %UnitTest.TestCase
{

Parameter API = "OcuTalon.Channel.Telegram.Api";

Parameter ENV = "OcuTalon.Test.Agent.KeyScan";

/// A token that no one uses: the exact-replacement test needs a value that the redactor does not know.
Parameter FAKE = "zz-fake-bot-token-for-the-api-test";

/// The environment variable as found: 1 when it was set, and its value.
Property TokenSet As %Boolean [ Private ];

Property TokenValue As %String(MAXLEN = "") [ Private ];

Method OnBeforeAllTests() As %Status
{
	Set var = $Parameter(..#API, "TOKENVAR")
	Set ..TokenSet = $ClassMethod(..#ENV, "HasEnv", var)
	Set ..TokenValue = $SYSTEM.Util.GetEnviron(var)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..PutBack()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..PutBack()
	Quit $$$OK
}

/// Puts the token variable back as OnBeforeAllTests found it.
Method PutBack() [ Private ]
{
	Set var = $Parameter(..#API, "TOKENVAR")
	If ..TokenSet {
		Do $ClassMethod(..#ENV, "SetEnv", var, ..TokenValue)
	} Else {
		Do $ClassMethod(..#ENV, "UnsetEnv", var)
	}
}

/// The text of n lines of 89 characters, joined with line feeds.
ClassMethod Lines(n As %Integer) As %String [ Private ]
{
	Set text = ""
	For i = 1:1:n {
		Set line = "L"_i_" "
		Set line = line_$Extract($TRanslate($J("", 89), " ", "x"), 1, 89 - $Length(line))
		Set text = text _ $Select(i = 1: "", 1: $Char(10)) _ line
	}
	Quit text
}

/// The parts as a $ListBuild list joined with the separator.
ClassMethod Joined(parts As %List, separator As %String) As %String [ Private ]
{
	Quit $ListToString(parts, separator)
}

/// The longest part of a list of parts.
ClassMethod Longest(parts As %List) As %Integer [ Private ]
{
	Set longest = 0
	Set position = 0
	While $ListNext(parts, position, part) {
		If $Length(part) > longest Set longest = $Length(part)
	}
	Quit longest
}

/// 9,000 characters of 90-character lines: each part is at most 4,096, each is cut at a line break, they come in order, and the parts
/// joined with a line feed are the text.
Method TestSplitLineBreaks()
{
	Set text = ..Lines(101)
	Do $$$AssertTrue($Length(text) > 9000, "the text is over 9,000 characters")
	Set parts = $ClassMethod(..#API, "Split", text, 4096)
	Do $$$AssertEquals($ListLength(parts), 3, "three parts")
	Do $$$AssertTrue(..Longest(parts) <= 4096, "each part is 4,096 characters or fewer")
	Do $$$AssertEquals(..Joined(parts, $Char(10)), text, "the parts joined with a line feed are the text")
	Set whole = 1
	Set position = 0
	While $ListNext(parts, position, part) {
		For i = 1:1:$Length(part, $Char(10)) {
			If $Length($Piece(part, $Char(10), i)) '= 89 Set whole = 0
		}
	}
	Do $$$AssertEquals(whole, 1, "every part is cut at a line break: it holds whole lines only")
	Do $$$AssertEquals($Length($List(parts, 1)), 45 * 89 + 44, "the first part is cut at the last line break inside the limit")
}

/// A line of 9,000 characters with no break: 4,096, 4,096 and the rest; the parts joined with nothing are the text.
Method TestSplitOneLongLine()
{
	Set text = $TRanslate($J("", 9000), " ", "a")
	Set parts = $ClassMethod(..#API, "Split", text, 4096)
	Do $$$AssertEquals($ListLength(parts), 3, "three parts")
	Do $$$AssertEquals($Length($List(parts, 1))_"|"_$Length($List(parts, 2))_"|"_$Length($List(parts, 3)), "4096|4096|808", "cut at the limit")
	Do $$$AssertEquals(..Joined(parts, ""), text, "the parts joined with nothing are the text")
}

/// A surrogate pair that straddles the limit is never split.
Method TestSplitSurrogatePair()
{
	Set pair = $Char(55357, 56832)
	Set text = $TRanslate($J("", 4095), " ", "a")_pair_$TRanslate($J("", 5000), " ", "b")
	Set parts = $ClassMethod(..#API, "Split", text, 4096)
	Do $$$AssertTrue(..Longest(parts) <= 4096, "each part is 4,096 units or fewer")
	Do $$$AssertEquals(..Joined(parts, ""), text, "the parts joined with nothing are the text")
	Set clean = 1
	Set position = 0
	While $ListNext(parts, position, part) {
		If ($Ascii(part, $Length(part)) >= 55296) && ($Ascii(part, $Length(part)) <= 56319) Set clean = 0
		If ($Ascii(part, 1) >= 56320) && ($Ascii(part, 1) <= 57343) Set clean = 0
	}
	Do $$$AssertEquals(clean, 1, "no part ends with half a pair or starts with the other half")
	Do $$$AssertEquals($Length($List(parts, 1)), 4095, "the first part is one unit short of the limit, so that the pair stays whole")
}

/// A text of exactly the limit is one part, one unit more is two, and a text of line feeds only makes no empty part.
Method TestSplitLimits()
{
	Set exact = $TRanslate($J("", 4096), " ", "a")
	Do $$$AssertEquals($ListLength($ClassMethod(..#API, "Split", exact, 4096)), 1, "a text of exactly 4,096 is one part")
	Do $$$AssertEquals($List($ClassMethod(..#API, "Split", exact, 4096), 1), exact, "unchanged")
	Set over = exact_"b"
	Set parts = $ClassMethod(..#API, "Split", over, 4096)
	Do $$$AssertEquals($ListLength(parts)_"|"_$Length($List(parts, 2)), "2|1", "4,097 is two parts, the second one unit")
	Set breaks = $TRanslate($J("", 9000), " ", $Char(10))
	Set parts = $ClassMethod(..#API, "Split", breaks, 4096)
	Set empty = 0
	Set position = 0
	While $ListNext(parts, position, part) {
		If part = "" Set empty = empty + 1
	}
	Do $$$AssertEquals(empty, 0, "a text of line feeds makes no empty part")
	Do $$$AssertTrue(..Longest(parts) <= 4096, "and each part is within the limit")
	Set short = "a*b_c [x](y) `z` <b>&amp; 1.5! #t"
	Do $$$AssertEquals($List($ClassMethod(..#API, "Split", short), 1), short, "a short text is one part, byte for byte, with the default limit")
}

/// An empty text has no part.
Method TestSplitEmpty()
{
	Do $$$AssertEquals($ListLength($ClassMethod(..#API, "Split", "", 4096)), 0, "an empty text has no part")
}

/// Good and bad bases.
Method TestEndpoint()
{
	Set sc = $ClassMethod(..#API, "Endpoint", "http://mock:8080", .server, .port, .https, .prefix)
	Do $$$AssertStatusOK(sc, "an http base with a port")
	Do $$$AssertEquals(server_"|"_port_"|"_https_"|"_prefix, "mock|8080|0|", "its parts")
	Set sc = $ClassMethod(..#API, "Endpoint", "https://api.telegram.org", .server, .port, .https, .prefix)
	Do $$$AssertEquals(server_"|"_port_"|"_https_"|"_prefix, "api.telegram.org|443|1|", "the public API: https, port 443")
	Set sc = $ClassMethod(..#API, "Endpoint", "http://host", .server, .port, .https, .prefix)
	Do $$$AssertEquals(server_"|"_port_"|"_https_"|"_prefix, "host|80|0|", "an http base with no port: 80")
	Set sc = $ClassMethod(..#API, "Endpoint", "https://gateway.example:8443/relay/tg/", .server, .port, .https, .prefix)
	Do $$$AssertStatusOK(sc, "a base with a path")
	Do $$$AssertEquals(server_"|"_port_"|"_https_"|"_prefix, "gateway.example|8443|1|/relay/tg", "its path, without the trailing slash")
	Set sc = $ClassMethod(..#API, "Endpoint", "http://mock:8080/", .server, .port, .https, .prefix)
	Do $$$AssertEquals(prefix, "", "a lone slash is no path")
	For bad = "", "mock:8080", "ftp://mock", "http://", "https://:80", "http://a b", "http://h:99999", "http://h:0", "http://h:x", "http://h?q=1", "http://h/p#f", "//h" {
		Set sc = $ClassMethod(..#API, "Endpoint", bad, .server, .port, .https, .prefix)
		Do $$$AssertStatusNotOK(sc, "'"_bad_"' is refused")
		Do $$$AssertTrue($Find($SYSTEM.Status.GetErrorText(sc), "ApiBase") > 0, "'"_bad_"': the error names the setting")
	}
	Set sc = $ClassMethod(..#API, "Endpoint", "http://zz-secret-host:99999/zz-secret-path", .server, .port, .https, .prefix)
	Do $$$AssertEquals($Find($SYSTEM.Status.GetErrorText(sc), "zz-secret"), 0, "the error holds neither the host nor the path of the base")
}

/// A call to a closed port, with a fake token in the environment: the error holds neither the token nor /bot, and Safe cuts the token.
Method TestNoTokenInErrors()
{
	Set var = $Parameter(..#API, "TOKENVAR")
	Do $ClassMethod(..#ENV, "SetEnv", var, ..#FAKE)
	For base = "http://127.0.0.1:1", "https://127.0.0.1:1" {
		Set answer = $ClassMethod(..#API, "Call", base, "NoSuchConfig", "getMe", {}, 2, .code, .sc)
		Do $$$AssertEquals(answer, "", base_": no answer")
		Do $$$AssertStatusNotOK(sc, base_": an error status")
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertEquals($Find(text, ..#FAKE), 0, base_": the error text holds no token")
		Do $$$AssertEquals($Find(text, "/bot"), 0, base_": and no path")
		Do $$$AssertEquals($Find(text, "127.0.0.1"), 0, base_": and no host")
		Do $$$AssertTrue($Find(text, "getMe") > 0, base_": it names the method")
	}
	Set safe = $ClassMethod(..#API, "Safe", "before "_..#FAKE_" after")
	Do $$$AssertEquals($Find(safe, ..#FAKE), 0, "Safe removes the exact token")
	Do $$$AssertEquals(safe, "before [redacted] after", "and leaves the rest")
	Set bad = $ClassMethod(..#API, "Failure", "getMe", 401, {"ok": false, "description": ("Unauthorized "_..#FAKE)})
	Do $$$AssertEquals($Find(bad, ..#FAKE), 0, "Failure removes the token from Telegram's description")
	Do $$$AssertEquals(bad, "Telegram answered getMe with HTTP 401: Unauthorized [redacted]", "and is a fixed phrase with the method, the status and the description")
}

/// With no token the call is not made.
Method TestNoToken()
{
	Do $ClassMethod(..#ENV, "UnsetEnv", $Parameter(..#API, "TOKENVAR"))
	Set answer = $ClassMethod(..#API, "Call", "http://127.0.0.1:1", "", "getMe", {}, 2, .code, .sc)
	Do $$$AssertEquals(answer_"|"_code, "|", "no answer and no HTTP status")
	Do $$$AssertStatusNotOK(sc, "an error status")
	Do $$$AssertTrue($Find($SYSTEM.Status.GetErrorText(sc), "no bot token") > 0, "which says that no token is set")
	Set answer = $ClassMethod(..#API, "Call", "ftp://x", "", "getMe", {}, 2, .code, .sc)
	Do $$$AssertStatusNotOK(sc, "a bad base is an error even with no token")
}

/// U-164 condition 2: an http:// base is a plain request. The SSL configuration named does not exist, and the call works against the mock
/// (when this stack is a throwaway with the mock and the CI dummy token); the same missing configuration on an https:// base is refused.
Method TestPlainHttpIgnoresSSLConfig()
{
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set base = $SYSTEM.Util.GetEnviron($Parameter(mock, "TELEGRAMBASEVAR"))
	Set reason = $ClassMethod(mock, "TelegramMissingReason", base, $SYSTEM.Util.GetEnviron($Parameter(mock, "TELEGRAMTOKENVAR")))
	If reason = "" Set reason = $ClassMethod("OcuTalon.Test.Channel.BotApi", "PollerReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set answer = $ClassMethod(..#API, "Call", base, "ZzNoSuchSSLConfig", "getMe", {}, 5, .code, .sc)
	Do $$$AssertStatusOK(sc, "a call to the mock's http base works with a configuration that does not exist")
	Do $$$AssertEquals(code, 200, "answered 200")
	Set name = ""
	Set ok = 0
	If $IsObject(answer) {
		Set ok = +answer.ok
		If $IsObject(answer.result) Set name = answer.result.username
	}
	Do $$$AssertEquals(ok, 1, "with an ok answer")
	Do $$$AssertEquals(name, "ocutalon_ci_bot", "that is the mock's getMe")
	Set secure = $Replace(base, "http://", "https://")
	Set answer = $ClassMethod(..#API, "Call", secure, "ZzNoSuchSSLConfig", "getMe", {}, 5, .code, .sc)
	Do $$$AssertEquals(answer, "", "the same host over https with that configuration gets no answer")
	Do $$$AssertStatusNotOK(sc, "it is an error status")
	Do $$$AssertStatusOK($ClassMethod("OcuTalon.Test.Channel.BotApi", "Reset"), "the mock's Bot API side is reset after the test")
}

}
