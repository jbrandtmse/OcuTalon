/// Tests of the sign-in page's contract (matrix row 18): the Content-Security-Policy header with the hashes of
/// the served stylesheet and script, the UX texts verbatim, the states of the page, the five images, and no
/// style attribute in the sources of the public classes. The page is rendered with a stand-in request, so no
/// web application is needed; the browser rows are test-sign-in.sh's.
Class OcuTalon.Test.Web.SignIn Extends %UnitTest.TestCase
{

/// The page's texts, as the UX gives them, with the middle dot as an entity.
Method TestTexts()
{
	Set login = "OcuTalon.Web.Public.Login"
	Do $$$AssertEquals($Parameter(login, "TITLE"), "Sign in &middot; OcuTalon", "the tab title")
	Do $$$AssertEquals($Parameter(login, "HEADING"), "Sign in to OcuTalon", "the heading")
	Do $$$AssertEquals($Parameter(login, "USERLABEL"), "User name", "the user name label")
	Do $$$AssertEquals($Parameter(login, "PASSWORDLABEL"), "Password", "the password label")
	Do $$$AssertEquals($Parameter(login, "SHOWPASSWORD"), "Show password", "the toggle's name")
	Do $$$AssertEquals($Parameter(login, "SUBMIT"), "Sign in", "the button")
	Do $$$AssertEquals($Parameter(login, "HELP"), "Use the IRIS account your install created; the README lists it.", "the help line")
	Do $$$AssertEquals($Parameter(login, "ERRORCREDENTIALS"), "That user name and password didn't work.", "the wrong-credentials error")
	Do $$$AssertEquals($Parameter(login, "ERRORNOROLE"), "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it.", "the no-role error")
	For name = "TITLE", "HEADING", "USERLABEL", "PASSWORDLABEL", "SHOWPASSWORD", "SUBMIT", "HELP", "ERRORCREDENTIALS", "ERRORNOROLE", "LOGOALT" {
		Do $$$AssertTrue(..IsAscii($Parameter(login, name)), name_" is printable ASCII")
	}
}

/// The header is AD-13's template, with the base64 of the SHA-256 of the stylesheet and of the script that the
/// generated class holds, recomputed here. OnPreHTTP sets it, with Cache-Control: no-store.
Method TestPolicy()
{
	Set css = $Parameter("OcuTalon.Web.Public.SignInAssets", "CSS")
	Set script = $Parameter("OcuTalon.Web.Public.SignInAssets", "SCRIPT")
	Do $$$AssertTrue($Length(css) > 1000, "the stylesheet is generated")
	Do $$$AssertTrue($Length(script) > 100, "the script is generated")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Public.Login", "CSS"), css, "Login inherits the stylesheet")
	Set expected = "default-src 'none'; script-src 'sha256-"_..Hash(script)_"'; style-src 'sha256-"_..Hash(css)_"'; img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Login).Policy(), expected, "the policy")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Login).StyleHash(), ..Hash(css), "StyleHash")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Login).ScriptHash(), ..Hash(script), "ScriptHash")

	New %request, %response
	Set %request = ##class(%CSP.Request).%New()
	Set %response = ##class(%CSP.Response).%New()
	Do $$$AssertTrue(##class(OcuTalon.Web.Public.Login).OnPreHTTP(), "OnPreHTTP lets the page be written")
	Do $$$AssertEquals(%response.GetHeader("Content-Security-Policy"), expected, "the header")
	Do $$$AssertEquals(%response.GetHeader("Cache-Control"), "no-store", "Cache-Control")
}

/// The first visit shows no error, and the user name has the focus.
Method TestFirstVisit()
{
	Set page = ..Page("", $SYSTEM.Status.Error(864), "")
	Do $$$AssertTrue(page [ "<html lang=""en"">", "lang is en")
	Do $$$AssertTrue(page [ "<title>Sign in &middot; OcuTalon</title>", "the tab title")
	Do $$$AssertTrue(page [ "<h1>Sign in to OcuTalon</h1>", "the heading")
	Do $$$AssertTrue(page [ ">User name</label>", "the user name label")
	Do $$$AssertTrue(page [ ">Password</label>", "the password label")
	Do $$$AssertTrue(page [ "aria-label=""Show password"" aria-pressed=""false""", "the toggle")
	Do $$$AssertTrue(page [ ">Sign in</button>", "the button")
	Do $$$AssertTrue(page [ "<p class=""help"">Use the IRIS account your install created; the README lists it.</p>", "the help line")
	Do $$$AssertTrue(page '[ "ocu-error", "no error element")
	Do $$$AssertTrue(page '[ "aria-invalid", "no field is marked")
	Do $$$AssertTrue(page '[ "didn't work", "no wrong-credentials text")
	Do $$$AssertTrue(page [ "name=""IRISUsername"" autocomplete=""username"" autocapitalize=""none"" spellcheck=""false"" value="""" autofocus>", "the user name has the focus")
	Do $$$AssertTrue(page [ "name=""IRISPassword""", "the password field")
	Do $$$AssertTrue(page [ "name=""IRISLogin""", "the sign-in button's field")
	Do $$$AssertTrue(page [ "<form name=""Login"" method=""post"" action=""/ocutalon/x?a=1&amp;b=2"">", "the action is Error:FullURL")
	Set css = $Parameter("OcuTalon.Web.Public.SignInAssets", "CSS")
	Set script = $Parameter("OcuTalon.Web.Public.SignInAssets", "SCRIPT")
	Do $$$AssertTrue(page [ ("<style>"_css_"</style>"), "the stylesheet is inline, as hashed")
	Do $$$AssertTrue(page [ ("<script>"_script_"</script>"), "the script is inline, as hashed")
	Do $$$AssertEquals(..Count(page, "<script"), 1, "one script")
	Do $$$AssertEquals(..Count(page, "<style"), 1, "one style element")
}

/// A wrong password (code 822) keeps the user name, marks both fields, and puts the focus on the error.
Method TestWrongPassword()
{
	Set page = ..Page("", $SYSTEM.Status.Error(822), "a<b""c")
	Do $$$AssertTrue(page [ "<span>That user name and password didn't work.</span>", "the error text")
	Do $$$AssertTrue(page [ "<p class=""error"" id=""ocu-error"" tabindex=""-1"" autofocus>", "the error has the focus")
	Do $$$AssertEquals(..Count(page, "aria-invalid=""true"" aria-describedby=""ocu-error"""), 2, "both fields are marked and described")
	Do $$$AssertEquals(..Count(page, "class=""input invalid"""), 2, "both fields are drawn as invalid")
	Do $$$AssertTrue(page [ "value=""a&lt;b&quot;c""", "the user name is kept, escaped")
	Do $$$AssertTrue(page '[ "value=""a<b", "and never raw")
	Do $$$AssertEquals(..Count(page, " autofocus"), 1, "one element has autofocus")
	Do $$$AssertTrue(page [ "<circle cx=""12"" cy=""12"" r=""10""/>", "the circle-alert icon")
	Do $$$AssertTrue(page [ "aria-hidden=""true"" focusable=""false""><circle", "the icon is hidden from assistive technology")
	Set page = ..Page("", $SYSTEM.Status.Error(5001, "anything"), "")
	Do $$$AssertTrue(page [ "didn't work", "any other code shows the wrong-credentials text")
}

/// The no-role state shows its message and marks no field.
Method TestNoRole()
{
	Set page = ..Page("norole", "", "")
	Do $$$AssertTrue(page [ "<span>This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it.</span>", "the message")
	Do $$$AssertTrue(page [ "<p class=""error"" id=""ocu-error"" tabindex=""-1"" autofocus>", "the message has the focus")
	Do $$$AssertTrue(page '[ "aria-invalid", "no field is marked")
	Do $$$AssertTrue(page '[ "class=""input invalid""", "no field is drawn as invalid")
	Do $$$AssertTrue(page '[ "didn't work", "not the wrong-credentials text")
	Do $$$AssertEquals(..Count(page, " autofocus"), 1, "one element has autofocus")
}

/// The page loads no script or file but its own inline blocks and the five images, and has no style attribute.
Method TestNoExternalReference()
{
	Set images = $ListFromString($Parameter("OcuTalon.Web.Public.Login", "IMAGES"))
	Do $$$AssertEquals($ListLength(images), 5, "five sign-in images")
	For state = "", "norole" {
		Set page = ..Page(state, $SYSTEM.Status.Error(822), "")
		Do $$$AssertTrue(page '[ " style=", "no style attribute")
		Do $$$AssertTrue(page '[ "<script src", "no external script")
		Do $$$AssertTrue(page '[ "<link rel=""stylesheet""", "no external stylesheet")
		Do $$$AssertTrue(page '[ "@import", "no import")
		Do $$$AssertTrue(page '[ "url(", "no url() in the stylesheet")
		Do $$$AssertTrue(page '[ " onclick=", "no inline handler")
		Set referenced = ..References(page)
		Set position = 0
		While $ListNext(referenced, position, reference) {
			Do $$$AssertTrue($ListFind(images, $Extract(reference, 2, *)), reference_" is one of the five images")
		}
		Set position = 0
		While $ListNext(images, position, image) {
			Do $$$AssertTrue($ListFind(referenced, "/"_image), image_" is used by the page")
		}
	}
}

/// The shell serves exactly the five images without a session, by exact path.
Method TestImageAllowList()
{
	Set login = "OcuTalon.Web.Public.Login"
	For path = "assets/brand/OcuTalon-Logo-light-640.png", "assets/brand/OcuTalon-Logo-light-1280.png", "assets/brand/OcuTalon-Logo-dark-640.png", "assets/brand/OcuTalon-Logo-dark-1280.png", "assets/brand/favicon-32.png" {
		Do $$$AssertTrue($ClassMethod(login, "IsSignInImage", path), path_" is served")
	}
	For path = "", "assets/brand/icon-192.png", "assets/brand/", "assets/brand/favicon-16.png", "assets/brand/favicon-32.png/", "ASSETS/brand/favicon-32.png", "assets/brand/../brand/favicon-32.png", "index.html", "assets/brand/favicon" {
		Do $$$AssertTrue('$ClassMethod(login, "IsSignInImage", path), "'"_path_"' is not served")
	}
}

/// The two web classes: sessions on, and the shell dispatches the three routes.
Method TestDispatchClasses()
{
	For class = "OcuTalon.Web.Public.Shell", "OcuTalon.Web.Api" {
		Do $$$AssertTrue($ClassMethod(class, "%Extends", "%CSP.REST"), class_" is a %CSP.REST class")
		Do $$$AssertEquals($Parameter(class, "UseSession"), 1, class_" uses the session")
	}
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Api", "CONTENTTYPE"), "application/json", "the API speaks JSON")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Public.Shell", "ROLE"), "OcuTalonUser", "the shell checks the user role")
	Do $ClassMethod("OcuTalon.Web.Public.Shell", "AccessCheck", .authorized)
	Do $$$AssertEquals(authorized, 1, "AccessCheck always authorises")
	Do $$$AssertTrue($ClassMethod("OcuTalon.Web.Public.Login", "%Extends", "%CSP.Login"), "Login is a %CSP.Login class")
}

/// None of the three classes has a style attribute in its source.
Method TestNoStyleAttributeInSources()
{
	For class = "OcuTalon.Web.Public.Login", "OcuTalon.Web.Public.Shell", "OcuTalon.Web.Public.SignInAssets" {
		Set sc = ##class(%Compiler.UDL.TextServices).GetTextAsString($Namespace, class, .text)
		Do $$$AssertStatusOK(sc, "the source of "_class)
		Do $$$AssertTrue($Length(text) > 200, class_" has a source")
		Do $$$AssertTrue($ZConvert(text, "L") '[ "style=", class_" has no style attribute")
	}
}

/// --- helpers ---

/// base64(SHA-256(text)), as a Content-Security-Policy source expression holds it.
ClassMethod Hash(text As %String) As %String [ Private ]
{
	Quit $SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(256, text))
}

ClassMethod IsAscii(text As %String) As %Boolean [ Private ]
{
	Set ascii = 1
	For i = 1:1:$Length(text) {
		Set code = $Ascii(text, i)
		If (code < 32) || (code > 126) Set ascii = 0
	}
	Quit ascii
}

/// Renders the page for a state, the server's error code and the typed user name, and returns it.
Method Page(state As %String, code As %String, user As %String) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(%CSP.Request).%New()
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New("ZzSignInTest", 0)
	Set %request.Data("Error:FullURL", 1) = "/ocutalon/x?a=1&b=2"
	Set %request.Data("Error:URL", 1) = "/ocutalon/x"
	If code '= "" Set %request.Data("Error:ErrorCode", 1) = code
	If user '= "" Set %request.Data("IRISUsername", 1) = user
	Set %OcuTalonState = state
	Set file = ##class(%File).TempFilename("html")
	Set io = $IO
	Open file:("NWS"):5
	If '$Test Quit ""
	Use file
	Try {
		Set sc = ##class(OcuTalon.Web.Public.Login).OnPage()
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Use io
	Close file
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(file)
	Set page = stream.Read(200000)
	Kill stream
	Do ##class(%File).Delete(file)
	Do $$$AssertStatusOK(sc, "the page is written")
	Quit $Replace(page, $Char(13), "")
}

ClassMethod Count(text As %String, what As %String) As %Integer [ Private ]
{
	Quit $Length(text, what) - 1
}

/// The values of src, srcset and href attributes of the page: a list of the paths, one per file used.
ClassMethod References(page As %String) As %List [ Private ]
{
	Set list = ""
	For attribute = " src=""", " srcset=""", " href=""" {
		Set from = 1
		For {
			Set at = $Find(page, attribute, from)
			Quit:'at
			Set end = $Find(page, """", at)
			Set value = $Extract(page, at, end - 2)
			Set from = end
			For i = 1:1:$Length(value, ",") {
				Set one = $ZStrip($Piece($ZStrip($Piece(value, ",", i), "<>W"), " ", 1), "<>W")
				If (one '= "") && ('$ListFind(list, one)) Set list = list_$ListBuild(one)
			}
		}
	}
	Quit list
}

}
