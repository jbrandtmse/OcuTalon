/// The one redactor of the bridge (AD-31, Consistency Conventions: Redaction). Text(text) returns the text with every sensitive
/// value replaced by [redacted]; the agent steps (AD-9), and from later stories the audit writer and the recorded files, pass
/// their text through it. Structural rules come first in the code that builds a record (AD-4, AD-14), and this class is the backstop.
///   - A text that is a JSON object or array is parsed. The value of every key in SENSITIVEKEYS, at any depth, is replaced
///     (the names are compared in lower case with _ and - removed, so api_key, apiKey and API-KEY are one name), and every string
///     value is checked for the patterns below. The result is the serialized JSON.
///   - A text that is exactly one JSON string (a tool that returns text has its result encoded so) is redacted by its content, as a
///     text of its own: JSON inside the string is parsed as above. A string that needs no change is returned as it is.
///   - Then, anywhere in the text, these patterns are replaced: sk-ant- keys and other sk- keys of 20 or more characters (the prefix included), Telegram
///     bot tokens (6 to 12 digits, a colon and 30 or more of A-Z, a-z, 0-9, _ and -), Bearer tokens, JWT-shaped tokens, GitHub
///     tokens (ghp_ and the other gh*_ forms, github_pat_) and AWS access key ids (AKIA). A key of SENSITIVEKEYS followed by =
///     or : and a value is replaced too, in text that is not JSON and in the string values of JSON that is.
///   - It is idempotent: Text(Text(x)) is Text(x).
///   - It never throws and never logs or stores its input. When it fails (for example when the redacted form of a text would
///     pass the limit of a string), it fails closed: it returns UNCHECKED and nothing of the text.
/// The class names no other OcuTalon package (AD-2).
Class OcuTalon.Bridge.Redact
{

/// What replaces a sensitive value.
Parameter REDACTED = "[redacted]";

/// What Text returns when it cannot check the text.
Parameter UNCHECKED = "[redacted: the text could not be checked]";

/// The names of the keys whose values are sensitive, comma-separated, in lower case with _ and - removed.
Parameter SENSITIVEKEYS = "password,passwd,pwd,passphrase,secret,clientsecret,token,accesstoken,refreshtoken,idtoken,bottoken,apikey,xapikey,authorization,cookie,privatekey,chatid,firstname,lastname,username,displayname";

/// The deepest nesting of JSON that Text checks; a deeper text is not checked.
Parameter MAXDEPTH = 100;

/// The text with every sensitive value replaced by [redacted], or UNCHECKED when it cannot be checked.
ClassMethod Text(text As %String = "") As %String
{
	Set result = ..#UNCHECKED
	Try {
		Set result = ..Redacted(text)
	} Catch {
		Set result = ..#UNCHECKED
	}
	Quit result
}

/// 1 when the key names a sensitive value: in lower case with _ and - removed, it is in SENSITIVEKEYS.
ClassMethod SensitiveKey(key As %String) As %Boolean
{
	Quit $ListFind($ListFromString(..#SENSITIVEKEYS), $Translate($ZConvert(key, "L"), "_-"))
}

/// Text without the safety net: a JSON object or array is parsed and scrubbed, a JSON string is redacted by its content (Literal), and
/// the patterns are applied. depth counts the nested JSON strings.
ClassMethod Redacted(text As %String, depth As %Integer = 0) As %String [ Private ]
{
	If $ZStrip(text, "*WC") = "" Quit text
	Set first = $Extract($ZStrip(text, "<W"))
	If (first = "{") || (first = "[") {
		Set object = ""
		Try {
			Set object = ##class(%Library.DynamicAbstractObject).%FromJSON(text)
		} Catch {
			Set object = ""
		}
		If $IsObject(object) {
			Do ..Scrub(object, 0)
			Quit ..Patterns(object.%ToJSON(), 0)
		}
	} ElseIf first = """" {
		Set literal = ..Literal(text, depth)
		If literal '= "" Quit literal
	}
	Quit ..Patterns(text, 1)
}

/// The redacted form of a text that is exactly one JSON string, such as the result of a tool that returns text (AI Hub encodes a tool's
/// string result as a JSON string), or "" when it is not one. The string's content is redacted as a text of its own, so that JSON
/// inside the string is parsed, and the string is encoded again; a string that needs no change is returned as it is.
ClassMethod Literal(text As %String, depth As %Integer) As %String [ Private ]
{
	If depth > ..#MAXDEPTH Throw ##class(%Exception.General).%New("TooDeep", 5001, , "The JSON strings are nested too deeply to be checked")
	Set wrapped = ""
	Try {
		Set wrapped = ##class(%Library.DynamicAbstractObject).%FromJSON("[" _ text _ "]")
	} Catch {
		Set wrapped = ""
	}
	If '$IsObject(wrapped) || (wrapped.%Size() '= 1) || (wrapped.%GetTypeOf(0) '= "string") Quit ""
	Set content = wrapped.%Get(0)
	Set clean = ..Redacted(content, depth + 1)
	If clean = content Quit text
	Do wrapped.%Set(0, clean, "string")
	Set json = wrapped.%ToJSON()
	Quit $Extract(json, 2, *-1)
}

/// Replaces, in a parsed JSON object or array and at any depth, the value of each sensitive key, and checks each string value
/// for the patterns (the key rule included).
ClassMethod Scrub(node As %Library.DynamicAbstractObject, depth As %Integer) [ Private ]
{
	If depth > ..#MAXDEPTH Throw ##class(%Exception.General).%New("TooDeep", 5001, , "The JSON is nested too deeply to be checked")
	Set isObject = node.%IsA("%Library.DynamicObject")
	Set changes = ""
	Set iterator = node.%GetIterator()
	While iterator.%GetNext(.key, .value, .type) {
		If isObject && ..SensitiveKey(key) {
			Set changes = changes _ $ListBuild($ListBuild(key, ..#REDACTED))
		} ElseIf (type = "object") || (type = "array") {
			Do ..Scrub(value, depth + 1)
		} ElseIf type = "string" {
			Set clean = ..Patterns(value, 1)
			If clean '= value Set changes = changes _ $ListBuild($ListBuild(key, clean))
		}
	}
	Set position = 0
	While $ListNext(changes, position, change) {
		Do node.%Set($List(change, 1), $List(change, 2), "string")
	}
}

/// The text with each pattern of the list replaced. kv is 1 to include the rule for a sensitive key followed by = or : and a value.
ClassMethod Patterns(text As %String, kv As %Boolean) As %String [ Private ]
{
	Set patterns = ..PatternList(kv)
	Set position = 0
	While $ListNext(patterns, position, pattern) {
		If text = "" Quit
		Set text = ##class(%Regex.Matcher).%New($List(pattern, 1), text).ReplaceAll($List(pattern, 2))
	}
	Quit text
}

/// The patterns, as a list of $ListBuild(regular expression, replacement). The specific shapes come first, the key rule last.
ClassMethod PatternList(kv As %Boolean) As %List [ Private ]
{
	Set mark = ..#REDACTED
	Set patterns = $ListBuild(
		$ListBuild("(?i)sk-ant-[A-Za-z0-9_-]+", mark),
		$ListBuild("(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{17,}", mark),
		$ListBuild("(?<![0-9])[0-9]{6,12}:[A-Za-z0-9_-]{30,}", mark),
		$ListBuild("(?i)(\bBearer\s+)[^\s""',;]+", "$1"_mark),
		$ListBuild("eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*", mark),
		$ListBuild("gh[pousr]_[A-Za-z0-9]{20,}", mark),
		$ListBuild("github_pat_[A-Za-z0-9_]{20,}", mark),
		$ListBuild("AKIA[0-9A-Z]{16}", mark))
	If kv {
		Set keys = ..KeyPattern()
		Set patterns = patterns _ $ListBuild(
			$ListBuild(keys _ """[^""]*""", "$1""" _ mark _ """"),
			$ListBuild(keys _ "'[^']*'", "$1'" _ mark _ "'"),
			$ListBuild(keys _ "(?:(?:Bearer|Basic|Digest|Negotiate)\s+)?[^\s""',;&]+", "$1" _ mark))
	}
	Quit patterns
}

/// The start of the regular expression of a sensitive key followed by = or : and a value: group 1 is the key and the separator.
/// Each name of SENSITIVEKEYS matches with an optional _ or - between its letters and in any case. The value, which follows, is a
/// double-quoted string, a single-quoted string, or a run of characters up to a space, quote, comma, semicolon or ampersand (after an
/// authentication scheme such as Bearer or Basic, which belongs to the value); a quoted value keeps its quotes, so that a JSON fragment
/// in a text stays well formed.
ClassMethod KeyPattern() As %String [ Private ]
{
	Set names = $ListFromString(..#SENSITIVEKEYS)
	Set alternatives = ""
	Set position = 0
	While $ListNext(names, position, name) {
		Set spaced = ""
		For i = 1:1:$Length(name) {
			Set spaced = spaced _ $Select(i = 1: "", 1: "[_-]?") _ $Extract(name, i)
		}
		Set alternatives = alternatives _ $Select(alternatives = "": "", 1: "|") _ spaced
	}
	Quit "(?i)((?:" _ alternatives _ ")[""']?\s*[=:]\s*)"
}

}
