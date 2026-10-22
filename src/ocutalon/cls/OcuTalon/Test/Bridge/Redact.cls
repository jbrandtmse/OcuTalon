/// Tests of the redactor (Story 1.5; AD-31, Consistency Conventions: Redaction; NFR-11), pure: nothing is sent and no production runs. Every
/// fake secret is built from fragments here, so that no file holds a key-like string.
///   - TestSensitiveKeys: each name of SENSITIVEKEYS, in snake, kebab, camel and upper case, as a key of a JSON object, nested in an
///     object and in an array, has its value replaced by [redacted], whatever the type of the value (a string, a number, an object or an
///     array); a key that is not in the list keeps its value, and the text is the serialized JSON;
///   - TestPatterns: the free-text patterns (a key followed by = or :, a quoted value, Bearer, sk-ant- and other sk- keys, a Telegram bot
///     token also inside a URL, a JWT, ghp_ and github_pat_ tokens, an AKIA key) are replaced, and the text around them is kept;
///   - TestJsonString: a text that is exactly one JSON string, as AI Hub gives the result of a tool that returns text, is redacted by
///     its content: JSON inside the string (also encoded twice) has its sensitive keys replaced, text inside it has its patterns
///     replaced, and a string that needs no change, or that is not alone in the text, is returned as it is or by the free-text rules;
///   - TestPlainText: plain text, a sentence about a password with no value, an empty text and a number are returned as they are;
///   - TestIdempotent: Text(Text(x)) is Text(x) for every text of this class;
///   - TestFailsClosed: a text near the limit of a string whose redacted form would pass it, a JSON text nested too deeply and a text
///     with control characters give the answer of the safety net or the text, and raise nothing; the failure text holds nothing of the input.
Class OcuTalon.Test.Bridge.Redact Extends %UnitTest.TestCase
{

Parameter REDACT = "OcuTalon.Bridge.Redact";

Parameter MARK = "[redacted]";

/// Each name of SENSITIVEKEYS, in four spellings, as a JSON key: the value is replaced; nested, in an array, and for values of every type.
Method TestSensitiveKeys()
{
	Set names = $ListFromString(##class(OcuTalon.Bridge.Redact).#SENSITIVEKEYS)
	Do $$$AssertEquals($ListLength(names), 21, "the list holds 21 names")
	Set position = 0
	While $ListNext(names, position, name) {
		Set half = $Length(name) \ 2
		For spelling = name, $ZConvert(name, "U"), $Extract(name, 1, half) _ "_" _ $Extract(name, half + 1, *), $Extract(name, 1, half) _ "-" _ $ZConvert($Extract(name, half + 1, *), "U"), $ZConvert($Extract(name, 1, 1), "U") _ $Extract(name, 2, *) {
			Set object = {}
			Do object.%Set(spelling, "zzvalue")
			Do $$$AssertEquals(..Text(object.%ToJSON()), ..Expected(spelling), "the key '" _ spelling _ "' has its value replaced")
		}
		Set nested = {"outer": {"inner": [{"plain": "keep"}]}}
		Do nested.outer.inner.%Get(0).%Set(name, "zzvalue")
		Do $$$AssertEquals(..Text(nested.%ToJSON()), "{""outer"":{""inner"":[{""plain"":""keep"",""" _ name _ """:""" _ ..#MARK _ """}]}}", "'" _ name _ "' is replaced inside an object and an array")
	}
	Do $$$AssertEquals(..Text("{""token"":12345,""password"":{""a"":1},""secret"":[1,2],""apiKey"":null,""cookie"":true}"), "{""token"":""[redacted]"",""password"":""[redacted]"",""secret"":""[redacted]"",""apiKey"":""[redacted]"",""cookie"":""[redacted]""}", "a number, an object, an array, null and a boolean are replaced as well")
	Do $$$AssertEquals(..Text("[{""chatId"":777},{""displayName"":""Ada L"",""first_name"":""Ada"",""LastName"":""L"",""user-name"":""ada""}]"), "[{""chatId"":""[redacted]""},{""displayName"":""[redacted]"",""first_name"":""[redacted]"",""LastName"":""[redacted]"",""user-name"":""[redacted]""}]", "a Telegram identity is replaced under every spelling, in an array")
	Set plain = "{""topic"":""status"",""note"":""All systems normal."",""count"":3,""items"":[1,2],""flag"":true,""none"":null,""tokenCount"":5,""secretary"":""Ada""}"
	Do $$$AssertEquals(..Text(plain), plain, "keys that are not in the list keep their values, also when they start with a name of the list")
	Do $$$AssertEquals(..Text("  {""topic"" : ""status"" , ""n"" : 1}  "), "{""topic"":""status"",""n"":1}", "the text of a JSON object is its serialized form")
}

/// The free-text patterns.
Method TestPatterns()
{
	Set mark = ..#MARK
	Do $$$AssertEquals(..Text("password=x"), "password=" _ mark, "password=x")
	Do $$$AssertEquals(..Text("The card is locked: password=Zz-1.2 apiKey=k1 done"), "The card is locked: password=" _ mark _ " apiKey=" _ mark _ " done", "two keys in a sentence")
	Do $$$AssertEquals(..Text("api_key: abc, token : def; pwd=ghi&x=1"), "api_key: " _ mark _ ", token : " _ mark _ "; pwd=" _ mark _ "&x=1", "a colon, a space around it, and the separators , ; and &")
	Do $$$AssertEquals(..Text("password=""my pass phrase"" then more"), "password=""" _ mark _ """ then more", "a double-quoted value is replaced whole, with its quotes")
	Do $$$AssertEquals(..Text("secret='a b' end"), "secret='" _ mark _ "' end", "and a single-quoted one")
	Do $$$AssertEquals(..Text("{bad ""password"":""zz"" and more"), "{bad ""password"":""" _ mark _ """ and more", "a JSON fragment that is not JSON keeps its quotes")
	Do $$$AssertEquals(..Text("Authorization: Bearer abc.def-ghi"), "Authorization: " _ mark, "an Authorization header: the key rule takes the scheme")
	Do $$$AssertEquals(..Text("sent Bearer x to the host"), "sent Bearer " _ mark _ " to the host", "Bearer x")
	Do $$$AssertEquals(..Text("Authorization: Basic dXNlcjpwYXNz"), "Authorization: " _ mark, "an Authorization header with another scheme")
	Do $$$AssertEquals(..Text("see BEARER abcdef"), "see BEARER " _ mark, "Bearer in upper case")
	Set model = "sk-" _ "ant-api03-AbC_dEf-123456"
	Do $$$AssertEquals(..Text("key " _ model _ " ok"), "key " _ mark _ " ok", "an sk-ant- key")
	Do $$$AssertEquals(..Text("key " _ $ZConvert(model, "U") _ " ok"), "key " _ mark _ " ok", "also in upper case")
	Do $$$AssertEquals(..Text("sk-" _ $Translate($Justify("", 17), " ", "a")), mark, "another sk- key of 20 characters")
	Do $$$AssertEquals(..Text("sk-" _ $Translate($Justify("", 16), " ", "a")), "sk-" _ $Translate($Justify("", 16), " ", "a"), "an sk- word of 19 characters is not a key")
	Do $$$AssertEquals(..Text("risk-" _ $Translate($Justify("", 30), " ", "a")), "risk-" _ $Translate($Justify("", 30), " ", "a"), "an sk- inside a word is not a key")
	Set telegram = "123456789" _ ":" _ "AAH" _ $Translate($Justify("", 32), " ", "z")
	Do $$$AssertEquals(..Text("token " _ telegram _ " end"), "token " _ mark _ " end", "a Telegram bot token")
	Do $$$AssertEquals(..Text("https://api.example.test/bot" _ telegram _ "/getMe"), "https://api.example.test/bot" _ mark _ "/getMe", "also inside a URL")
	Do $$$AssertEquals(..Text("1234:" _ $Translate($Justify("", 40), " ", "z")), "1234:" _ $Translate($Justify("", 40), " ", "z"), "a number that is too short for a bot token is not one")
	Set jwt = "eyJ" _ "hbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.c2lnbmF0dXJl"
	Do $$$AssertEquals(..Text("jwt " _ jwt _ "."), "jwt " _ mark _ ".", "a JWT")
	Set github = "gh" _ "p_" _ $Translate($Justify("", 30), " ", "A")
	Do $$$AssertEquals(..Text("t " _ github), "t " _ mark, "a ghp_ token")
	Set pat = "github" _ "_pat_" _ $Translate($Justify("", 30), " ", "B") _ "_9"
	Do $$$AssertEquals(..Text("t " _ pat _ "!"), "t " _ mark _ "!", "a github_pat_ token")
	Set aws = "AK" _ "IA" _ "ABCDEFGH12345678"
	Do $$$AssertEquals(..Text("id " _ aws _ " ok"), "id " _ mark _ " ok", "an AKIA key")
	Do $$$AssertEquals(..Text("{""note"":""the password: foo and sk-" _ "ant-zzz"",""x"":1}"), "{""note"":""the password: " _ mark _ " and " _ mark _ """,""x"":1}", "the string values of a JSON object are checked for the patterns too")
	Do $$$AssertEquals(..Text("{""list"":[""Bearer abc"",""fine""]}"), "{""list"":[""Bearer " _ mark _ """,""fine""]}", "and so are the strings of an array")
}

/// A text that is exactly one JSON string is redacted by its content, and is a JSON string again.
Method TestJsonString()
{
	Set mark = ..#MARK
	Set json = {"password": "hunter2", "chatId": 777001, "displayName": "Ada L", "keep": "ok"}.%ToJSON()
	Set expected = {"password": (mark), "chatId": (mark), "displayName": (mark), "keep": "ok"}.%ToJSON()
	Do $$$AssertEquals(..Text(..Quote(json)), ..Quote(expected), "JSON inside a string has its sensitive keys replaced, and the result is a string")
	Do $$$AssertNotTrue(..Text(..Quote(json)) [ "hunter2", "the password is not in it")
	Do $$$AssertEquals(..Text(..Quote("the card is locked: password=abc apiKey=k1 done")), ..Quote("the card is locked: password=" _ mark _ " apiKey=" _ mark _ " done"), "text inside a string has its key rule applied")
	Set model = "sk-" _ "ant-api03-AbC_dEf-123456"
	Do $$$AssertEquals(..Text(..Quote("key " _ model _ " ok")), ..Quote("key " _ mark _ " ok"), "and its patterns")
	Set twice = {"note": ({"token": "zz"}.%ToJSON())}.%ToJSON()
	Set twiceExpected = {"note": ({"token": (mark)}.%ToJSON())}.%ToJSON()
	Do $$$AssertEquals(..Text(..Quote(twice)), ..Quote(twiceExpected), "JSON in a string in JSON in a string is redacted too")
	Set thrice = ..Quote(..Quote(json))
	Set once = ..Text(thrice)
	Do $$$AssertEquals(once, ..Quote(..Quote(expected)), "and a string in a string")
	Do $$$AssertEquals(..Text(once), once, "Text(Text(x)) is Text(x) for a string")

	Set strings = $ListBuild("""""", """Reading the test note""", """caf" _ $Char(233) _ " ok""", """a\nb""", """[1,2]""")
	Set position = 0
	Set number = 0
	While $ListNext(strings, position, text) {
		Set number = number + 1
		Do $$$AssertEquals(..Text(text), text, "the JSON string number " _ number _ " needs no change and is returned as it is")
	}
	Do $$$AssertEquals(..Text("""a"",""b"" password=x"), """a"",""b"" password=" _ mark, "two strings are not one string: the free-text rules apply")
	Do $$$AssertEquals(..Text("""abc"" password=x"), """abc"" password=" _ mark, "and so is a string followed by text")
}

/// Text with nothing sensitive is returned as it is.
Method TestPlainText()
{
	For text = "", " ", "Reading the test note", "zz_steps_note. Inputs: {""topic"":""status""}. Result: ok.", "The password is long and the token is short.", "Model request 3", "About 100 tokens sent (an estimate). Reply: 20 characters of text, 1 tool calls.", "tokenizer=on", "12345", "[1,2,3]", "{}", "[]" {
		Do $$$AssertEquals(..Text(text), text, "'" _ $Extract(text, 1, 40) _ "' is returned as it is")
	}
	Do $$$AssertEquals(..Text(12345), 12345, "a number")
	Do $$$AssertEquals(..Text($Char(9) _ "x" _ $Char(10)), $Char(9) _ "x" _ $Char(10), "white space around a word")
}

/// Text(Text(x)) is Text(x), for the texts of the other tests.
Method TestIdempotent()
{
	Set texts = $ListBuild(
		"{""password"":""x"",""n"":{""Api_Key"":[1,2],""keep"":""plain""},""list"":[{""X-API-KEY"":""k""}]}",
		"password=hunter2 and Bearer abc.def sk-" _ "ant-ABCDEF12345 done",
		"123456789" _ ":" _ "AAH" _ $Translate($Justify("", 32), " ", "z"),
		"eyJ" _ "hbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.sig",
		"{""note"":""the password: foo""}",
		"{bad json ""password"":""zz"" and password='a b c' x",
		"displayName=""Ada Lovelace"" user",
		"[""a"",{""token"":5}]",
		"Authorization: Bearer abc",
		"pwd=x pwd=x pwd=x",
		"""{\""password\"":\""x\""}""",
		"""the card is locked: password=abc""",
		"plain text, no secrets")
	Set position = 0
	While $ListNext(texts, position, text) {
		Set once = ..Text(text)
		Do $$$AssertEquals(..Text(once), once, "Text(Text(x)) is Text(x) for '" _ $Extract(text, 1, 40) _ "'")
	}
}

/// What the redactor cannot finish, it does not return: a text near the limit of a string, full of a key and a value, grows past the
/// limit when it is redacted, and gives the failure text, which holds nothing of the input. Nothing is raised for a JSON text nested too
/// deeply or for control characters.
Method TestFailsClosed()
{
	Set unit = "pwd=x "
	Set text = ""
	For i = 1:1:590000 {
		Set text = text _ unit
	}
	Do $$$AssertTrue($Length(text) > 3500000, "the text is near the limit of a string: " _ $Length(text))
	Set sc = $$$OK
	Try {
		Set out = ..Text(text)
	} Catch exception {
		Set out = ""
		Set sc = exception.AsStatus()
	}
	Do $$$AssertStatusOK(sc, "the redactor raises nothing")
	Do $$$AssertEquals(out, ##class(OcuTalon.Bridge.Redact).#UNCHECKED, "and fails closed: " _ $Extract(out, 1, 60))
	Do $$$AssertEquals(out, "[redacted: the text could not be checked]", "with this text")
	Do $$$AssertEquals(..Text(out), out, "which is its own redaction")

	Set deep = ""
	For i = 1:1:1000 {
		Set deep = deep _ "["
	}
	Set deep = deep _ """pwd=x""" _ $Translate($Justify("", 1000), " ", "]")
	Do $$$AssertEquals(..Text(deep), ##class(OcuTalon.Bridge.Redact).#UNCHECKED, "a JSON text nested too deeply is not checked, and so not returned")
	Set deep = ""
	For i = 1:1:50 {
		Set deep = deep _ "{""a"":"
	}
	Set deep = deep _ "{""password"":""x""}" _ $Translate($Justify("", 50), " ", "}")
	Do $$$AssertTrue(..Text(deep) '[ """x""", "a JSON text nested 50 deep is checked: the value is gone")
	Do $$$AssertEquals(..Text($Char(0, 1, 2) _ "password=" _ $Char(3) _ "x"), $Char(0, 1, 2) _ "password=" _ ..#MARK, "control characters raise nothing")
}

/// --- helpers ---
ClassMethod Text(text) As %String [ Private ]
{
	Quit $ClassMethod(..#REDACT, "Text", text)
}

/// {"<key>":"[redacted]"}
ClassMethod Expected(key As %String) As %String [ Private ]
{
	Quit "{""" _ key _ """:""" _ ..#MARK _ """}"
}

/// The text as a JSON string (with its quotes).
ClassMethod Quote(text As %String) As %String [ Private ]
{
	Set array = []
	Do array.%Push(text)
	Quit $Extract(array.%ToJSON(), 2, *-1)
}

}
