/// The sign-in page of a local or IPM install (AD-13): IRIS password authentication behind a branded page.
/// It runs before sign-in with no roles, so it lives in OCUTALON_PUBLIC and references only %CSP and its own
/// package. It keeps %CSP.Login's form contract: the action is Error:FullURL, InsertHiddenFields follows the
/// form tag, the fields are IRISUsername, IRISPassword and IRISLogin, and OnPreHTTP calls the superclass.
/// The page carries its stylesheet and one script inline, generated into OcuTalon.Web.Public.SignInAssets, and
/// the Content-Security-Policy header pins both by hash. There is no style attribute, no external script and
/// no font file: the fonts are the system's. The page keeps its own copy of the UX texts as parameters (AD-3);
/// a non-ASCII character in them is an HTML entity. With the online-demo flag set, Show hands the page to its subclass
/// OcuTalon.Web.Public.Splash, the online demo's splash screen.
Class OcuTalon.Web.Public.Login Extends (%CSP.Login, OcuTalon.Web.Public.SignInAssets)
{

Parameter TITLE = "Sign in &middot; OcuTalon";

Parameter HEADING = "Sign in to OcuTalon";

Parameter USERLABEL = "User name";

Parameter PASSWORDLABEL = "Password";

Parameter SHOWPASSWORD = "Show password";

Parameter SUBMIT = "Sign in";

Parameter HELP = "Use the IRIS account your install created; the README lists it.";

Parameter ERRORCREDENTIALS = "That user name and password didn't work.";

Parameter ERRORNOROLE = "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it.";

Parameter LOGOALT = "OcuTalon";

/// The five files that anyone may fetch without a session, relative to the application: the logos of the
/// sign-in page in both themes and two densities, and the icon of the tab.
Parameter IMAGES = "assets/brand/OcuTalon-Logo-light-640.png,assets/brand/OcuTalon-Logo-light-1280.png,assets/brand/OcuTalon-Logo-dark-640.png,assets/brand/OcuTalon-Logo-dark-1280.png,assets/brand/favicon-32.png";

Parameter LOGOLIGHT = "assets/brand/OcuTalon-Logo-light-640.png,assets/brand/OcuTalon-Logo-light-1280.png";

Parameter LOGODARK = "assets/brand/OcuTalon-Logo-dark-640.png,assets/brand/OcuTalon-Logo-dark-1280.png";

Parameter FAVICON = "assets/brand/favicon-32.png";

/// Lucide eye and circle-alert (ISC), drawn on a 24 grid.
Parameter ICONEYE = "<path d=""M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0""/><circle cx=""12"" cy=""12"" r=""3""/>";

Parameter ICONALERT = "<circle cx=""12"" cy=""12"" r=""10""/><line x1=""12"" x2=""12"" y1=""8"" y2=""12""/><line x1=""12"" x2=""12.01"" y1=""16"" y2=""16""/>";

/// 1 when path, relative to the application, is one of the five images.
ClassMethod IsSignInImage(path As %String) As %Boolean
{
	Quit (path '= "") && ''$ListFind($ListFromString(..#IMAGES), path)
}

/// The base64 of the SHA-256 of the stylesheet, as the browser hashes the style element's text.
ClassMethod StyleHash() As %String [ CodeMode = objectgenerator ]
{
	Set css = $Get(%parameter("CSS"))
	If css = "" Quit $SYSTEM.Status.Error(5001, "Parameter CSS is empty: compile OcuTalon.Web.Public.SignInAssets first")
	Do %code.WriteLine(" Quit """_$SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(256, css))_"""")
	Quit $SYSTEM.Status.OK()
}

/// The base64 of the SHA-256 of the script, as the browser hashes the script element's text.
ClassMethod ScriptHash() As %String [ CodeMode = objectgenerator ]
{
	Set script = $Get(%parameter("SCRIPT"))
	If script = "" Quit $SYSTEM.Status.Error(5001, "Parameter SCRIPT is empty: compile OcuTalon.Web.Public.SignInAssets first")
	Do %code.WriteLine(" Quit """_$SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(256, script))_"""")
	Quit $SYSTEM.Status.OK()
}

/// The Content-Security-Policy of the page: no source but the two inline blocks, by hash, and the same origin
/// for images and form posts.
ClassMethod Policy() As %String
{
	Quit "default-src 'none'; script-src 'sha256-"_..ScriptHash()_"'; style-src 'sha256-"_..StyleHash()_"'; img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
}

/// The superclass sets the session token when the application uses one; this adds the policy and no-store.
ClassMethod OnPreHTTP() As %Boolean [ ServerOnly = 1 ]
{
	Set ok = ##super()
	Do %response.SetHeader("Content-Security-Policy", ..Policy())
	Do %response.SetHeader("Cache-Control", "no-store")
	Quit ok
}

/// 1 when the online-demo flag is set, so that the page is the splash screen. Splash returns 0.
ClassMethod UseSplash() As %Boolean
{
	Quit ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo") = "1"
}

/// Sends the page: the response headers, then the page. state is "" for the page that a request without a
/// session gets, or "norole" for a signed-in user who lacks the OcuTalon user role. writeHeader is 1 where
/// nothing has been sent yet (the Login method of a dispatch class), and 0 inside a REST dispatch, where the
/// first write sends the header and writing it again would put a second header in the page. Returns the
/// status of writing the header or the page.
ClassMethod Show(state As %String = "", writeHeader As %Boolean = 1) As %Status
{
	If ..UseSplash() Quit ##class(OcuTalon.Web.Public.Splash).Show(state, writeHeader)
	Set %OcuTalonState = state
	If '..OnPreHTTP() Quit $SYSTEM.Status.OK()
	If writeHeader {
		Set sc = %response.WriteHTTPHeader()
		If $SYSTEM.Status.IsError(sc) Quit sc
	}
	Quit ..OnPage()
}

/// The message for a state, the server's error code and whether the request carried signedOut=1. The no-role text
/// for "norole" and the wrong-credentials text for any code but 864 come first. For the first visit (code 864) and
/// for no code the message is the signed-out text, the API's own (ApiBase MESSAGESIGNEDOUT), when signedOut is 1, and
/// none otherwise.
ClassMethod Message(state As %String, code As %String, signedOut As %Boolean = 0) As %String
{
	If state = "norole" Quit ..#ERRORNOROLE
	Set notice = $Select(signedOut: ##class(OcuTalon.Web.Public.ApiBase).#MESSAGESIGNEDOUT, 1: "")
	If code = "" Quit notice
	Set codes = ""
	Try {
		Set codes = $SYSTEM.Status.GetErrorCodes(code)
	} Catch {
		Set codes = ""
	}
	If (","_codes_",") [ ",864," Quit notice
	Quit ..#ERRORCREDENTIALS
}

/// Writes the page. A wrong password marks both fields and keeps the user name; the no-role state and the signed-out
/// notice (the query signedOut=1) mark nothing. Each puts the message under the button and focuses it. Otherwise the
/// user name has the focus.
ClassMethod OnLoginPage() As %Status
{
	Set state = $Get(%OcuTalonState)
	Kill %OcuTalonState
	Set message = ..Message(state, $Get(%request.Data("Error:ErrorCode", 1)), $Get(%request.Data("signedOut", 1)) = 1)
	Set marked = (message = ..#ERRORCREDENTIALS)
	Set base = %request.Application
	If $Extract(base, $Length(base)) '= "/" Set base = base_"/"
	Set base = $ZConvert(base, "O", "HTML")
	Set action = $ZConvert($Get(%request.Data("Error:FullURL", 1)), "O", "HTML")
	Set user = $ZConvert($Get(%request.Data("IRISUsername", 1)), "O", "HTML")
	Set invalid = $Select(marked: " invalid", 1: "")
	Set described = $Select(marked: " aria-invalid=""true"" aria-describedby=""ocu-error""", 1: "")

	Write "<!DOCTYPE html>", !
	Write "<html lang=""en""><head><meta charset=""utf-8"">", !
	Write "<meta name=""viewport"" content=""width=device-width, initial-scale=1"">", !
	Write "<title>", ..#TITLE, "</title>", !
	Write "<link rel=""icon"" type=""image/png"" href=""", base, ..#FAVICON, """>", !
	Write "<style>", ..#CSS, "</style>", !
	Write "</head><body><main class=""page"">", !
	Write "<picture><source media=""(prefers-color-scheme: dark)"" srcset=""", base, $Piece(..#LOGODARK, ",", 1), " 1x, ", base, $Piece(..#LOGODARK, ",", 2), " 2x"">"
	Write "<img class=""logo"" src=""", base, $Piece(..#LOGOLIGHT, ",", 1), """ srcset=""", base, $Piece(..#LOGOLIGHT, ",", 1), " 1x, ", base, $Piece(..#LOGOLIGHT, ",", 2), " 2x"" alt=""", ..#LOGOALT, """ width=""320"" height=""179""></picture>", !
	Write "<div class=""card""><h1>", ..#HEADING, "</h1>", !
	Write "<form name=""Login"" method=""post"" action=""", action, """>", !
	Write ..InsertHiddenFields($ZConvert($Get(%request.Data("Error:URL", 1)), "O", "HTML")), !
	Write "<div class=""field""><label class=""label"" for=""ocu-user"">", ..#USERLABEL, "</label>"
	Write "<div class=""input", invalid, """><input id=""ocu-user"" type=""text"" name=""IRISUsername"" autocomplete=""username"" autocapitalize=""none"" spellcheck=""false"" value=""", user, """", described, $Select(message = "": " autofocus", 1: ""), "></div></div>", !
	Write "<div class=""field""><label class=""label"" for=""ocu-pass"">", ..#PASSWORDLABEL, "</label>"
	Write "<div class=""input", invalid, """><input id=""ocu-pass"" type=""password"" name=""IRISPassword"" autocomplete=""current-password""", described, ">"
	Write "<button class=""toggle"" id=""ocu-toggle"" type=""button"" aria-label=""", ..#SHOWPASSWORD, """ aria-pressed=""false"">", ..Icon(..#ICONEYE), "</button></div></div>", !
	Write "<button class=""primary"" type=""submit"" name=""IRISLogin"" value=""", ..#SUBMIT, """>", ..#SUBMIT, "</button>", !
	If message '= "" {
		Write "<p class=""error"" id=""ocu-error"" tabindex=""-1"" autofocus>", ..Icon(..#ICONALERT), "<span>", message, "</span></p>", !
	}
	Write "</form>", !
	Write "<p class=""help"">", ..#HELP, "</p>", !
	Write "</div></main>", !
	Write "<script>", ..#SCRIPT, "</script>", !
	Write "</body></html>", !
	Quit $SYSTEM.Status.OK()
}

/// An inline icon: the shapes inside a 24 grid, hidden from assistive technology.
ClassMethod Icon(shapes As %String) As %String [ Private ]
{
	Quit "<svg class=""icon"" viewBox=""0 0 24 24"" aria-hidden=""true"" focusable=""false"">"_shapes_"</svg>"
}

}
