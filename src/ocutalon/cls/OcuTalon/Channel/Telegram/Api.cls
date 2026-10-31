/// The Telegram Bot API client of TelegramIn and TelegramOut (Story 12.2; AD-14, AD-19, NFR-11). It is the one place that builds a
/// Bot API request, with %Net.HttpRequest, and the one place that reads the bot token.
///   - Call reads the token from the environment on every call (TOKENVAR) and keeps it nowhere: not in a property, a setting, a row,
///     a global, a message, a trace entry, a log line or a status text. It builds a new request object for every call, because a reused
///     one sends the previous URL as its Referer, and it follows no redirect.
///   - Every error text that Call or Failure returns is a fixed phrase with the method, the HTTP status and Telegram's description. It
///     never holds the URL, the path, a host or the token, and it goes through Safe.
///   - The base (the ApiBase host setting) is http(s)://host[:port][/path]. Only an https base gets Https and the SSL configuration
///     (the SSLConfig host setting); an http base makes a plain request whatever the configuration names (AD-19, AD-22).
///   - Split cuts a text into parts of at most LIMIT UTF-16 units, as Telegram counts, at the last line break inside the limit, else at
///     the limit, and never inside a surrogate pair.
Class OcuTalon.Channel.Telegram.Api Extends %RegisteredObject
{

/// The environment variable that holds the bot token.
Parameter TOKENVAR = "TELEGRAM_BOT_TOKEN";

/// The environment variable that overrides the API base (the CI override and the online demo set it).
Parameter BASEVAR = "OCUTALON_TELEGRAM_API_BASE";

/// The public Bot API, the default base.
Parameter PUBLICBASE = "https://api.telegram.org";

/// The client SSL configuration that the installer makes (Install.Step.SSL), the default of the SSLConfig host setting.
Parameter SSLCONFIG = "OcuTalonClient";

/// The most UTF-16 units of one message text.
Parameter LIMIT = 4096;

/// The setting whose value Endpoint refuses, as the error names it.
Parameter BASESETTING = "ApiBase";

/// The answer of the Bot API call, parsed, whatever the HTTP status, with the status in httpStatus. It is "" with sc set when the call
/// could not be made, did not reach the API, timed out, or was answered with a body that is not JSON. method is the Bot API method;
/// params is a dynamic object (an empty one for none); seconds is the read timeout.
ClassMethod Call(base As %String, sslConfig As %String, method As %String, params As %DynamicObject, seconds As %Integer, Output httpStatus As %Integer, Output sc As %Status) As %DynamicObject
{
	Set httpStatus = ""
	Set sc = $SYSTEM.Status.OK()
	Set answer = ""
	Try {
		Set method = $Get(method)
		If method '? 1.A {
			Set sc = $SYSTEM.Status.Error(5001, "A Telegram call needs a method name of letters")
			Quit
		}
		Set sc = ..Endpoint($Get(base), .server, .port, .https, .prefix)
		If $SYSTEM.Status.IsError(sc) Quit
		Set token = $SYSTEM.Util.GetEnviron(..#TOKENVAR)
		If token = "" {
			Set sc = $SYSTEM.Status.Error(5001, ..Safe("The Telegram call "_method_" was not made: no bot token is set in the environment"))
			Quit
		}
		Set request = ##class(%Net.HttpRequest).%New()
		Set request.Server = server
		Set request.Port = port
		Set request.FollowRedirect = 0
		Set request.Timeout = +$Get(seconds, 8)
		If https {
			Set request.Https = 1
			Set request.SSLConfiguration = $Get(sslConfig)
		}
		Set request.ContentType = "application/json"
		Set body = $Select($IsObject($Get(params)): params.%ToJSON(), 1: "{}")
		Do request.EntityBody.Write($ZConvert(body, "O", "UTF8"))
		Set post = request.Post(prefix_"/bot"_token_"/"_method)
		Kill token
		Set response = request.HttpResponse
		If $SYSTEM.Status.IsError(post) || '$IsObject(response) {
			Set sc = $SYSTEM.Status.Error(5001, ..Safe("The Telegram call "_method_" did not get an answer from the Bot API (error "_$SYSTEM.Status.GetErrorCodes(post)_")"))
			Quit
		}
		Set httpStatus = response.StatusCode
		Try {
			Set answer = {}.%FromJSON(response.Data)
		} Catch {
			Set answer = ""
		}
		If '$IsObject(answer) || ($ClassName(answer) '= "%Library.DynamicObject") {
			Set answer = ""
			Set sc = $SYSTEM.Status.Error(5001, ..Safe("The Telegram call "_method_" was answered with HTTP "_httpStatus_" and a body that is not JSON"))
		}
	} Catch exception {
		Set answer = ""
		Set sc = $SYSTEM.Status.Error(5001, ..Safe("The Telegram call "_$Get(method)_" failed ("_exception.Name_")"))
	}
	Quit answer
}

/// The text of a Bot API answer that is not a success: a fixed phrase with the method, the HTTP status and Telegram's description (at
/// most 200 characters, "" when there is none), through Safe.
ClassMethod Failure(method As %String, httpStatus As %Integer, answer As %DynamicObject) As %String
{
	Set description = ""
	If $IsObject($Get(answer)) && (answer.%GetTypeOf("description") = "string") Set description = $Extract(answer.%Get("description"), 1, 200)
	Quit ..Safe("Telegram answered "_$Get(method)_" with HTTP "_$Get(httpStatus)_$Select(description '= "": ": "_description, 1: ""))
}

/// The parts of a base of the form http(s)://host[:port][/path]: the host in server, the port (80 or 443 when the base names none),
/// 1 in https for an https base, and the path without a trailing slash in prefix. An error status that names the ApiBase setting, and not
/// its value, for anything else.
ClassMethod Endpoint(base As %String, Output server As %String, Output port As %Integer, Output https As %Boolean, Output prefix As %String) As %Status
{
	Set server = "", port = "", https = 0, prefix = ""
	Set base = $Get(base)
	Set scheme = $Piece(base, "://", 1)
	Set rest = $Piece(base, "://", 2, *)
	Set bad = $SYSTEM.Status.Error(5001, "The setting "_..#BASESETTING_" must be http(s)://host[:port][/path]")
	If ($Length(base, "://") < 2) || '$ListFind($ListBuild("http", "https"), scheme) Quit bad
	Set authority = $Piece(rest, "/", 1)
	Set path = $Select($Length(rest, "/") > 1: "/"_$Piece(rest, "/", 2, *), 1: "")
	If '$Match(authority, "^[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]{1,5})?$") Quit bad
	If '$Match(path, "^(/[^ ?#]*)?$") Quit bad
	Set server = $Piece(authority, ":", 1)
	Set port = $Select($Length(authority, ":") > 1: +$Piece(authority, ":", 2), scheme = "https": 443, 1: 80)
	If (port < 1) || (port > 65535) Quit bad
	Set https = (scheme = "https")
	While $Extract(path, *) = "/" {
		Set path = $Extract(path, 1, *-1)
	}
	Set prefix = path
	Quit $SYSTEM.Status.OK()
}

/// The text cut into parts of at most limit UTF-16 units, as a list. A text longer than the limit is cut after the last line break
/// inside the limit (the line feed is dropped, so that the parts joined with a line feed give the text back when no cut was empty),
/// else at the limit; a cut never separates a surrogate pair, and a part is never empty.
ClassMethod Split(text As %String, limit As %Integer = {..#LIMIT}) As %List
{
	Set parts = ""
	Set text = $Get(text)
	Set limit = $Select(+$Get(limit) < 2: ..#LIMIT, 1: +limit \ 1)
	While $Length(text) > limit {
		Set window = $Extract(text, 1, limit)
		Set cut = 0
		For position = limit:-1:2 {
			If $Extract(window, position) = $Char(10) {
				Set cut = position
				Quit
			}
		}
		If cut {
			Set part = $Extract(text, 1, cut - 1)
			Set text = $Extract(text, cut + 1, *)
		} Else {
			Set size = limit
			Set last = $Ascii(window, limit)
			If (last >= 55296) && (last <= 56319) Set size = limit - 1
			Set part = $Extract(text, 1, size)
			Set text = $Extract(text, size + 1, *)
		}
		If part '= "" Set parts = parts _ $ListBuild(part)
	}
	If text '= "" Set parts = parts _ $ListBuild(text)
	Quit parts
}

/// The text with the exact bot token replaced, and then with every sensitive value replaced by the bridge's redactor. The redactor does
/// not recognise the CI dummy token, so the exact value is replaced first.
ClassMethod Safe(text As %String) As %String
{
	Set text = $Get(text)
	Set token = $SYSTEM.Util.GetEnviron(..#TOKENVAR)
	If token '= "" Set text = $Replace(text, token, "[redacted]")
	Quit ##class(OcuTalon.Bridge.Redact).Text(text)
}

}
