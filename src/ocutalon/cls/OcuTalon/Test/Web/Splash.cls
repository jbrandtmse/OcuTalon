/// Tests of the online demo's splash screen (Story 16.2; AD-13, AD-3): the texts of OcuTalon.Web.Public.Splash, the policy over the
/// hashes of its own two inline blocks, the hand-over from Login.Show on the online-demo flag, the page's markup, the failed sign-in
/// and no-role states, and the values that are not set or need escaping. The page is rendered in process with a stand-in request, so
/// no web application is needed; the browser rows are those of the online-demo unit (web/e2e-online/splash.spec.ts). Every public
/// setting is saved before each test and put back after it, also after a failure.
Class OcuTalon.Test.Web.Splash Extends %UnitTest.TestCase
{

/// The own text parameters of Splash, each as the AC and the UX give it.
Method TestTexts()
{
	Set splash = "OcuTalon.Web.Public.Splash"
	Set texts = ""
	Set texts = texts_$ListBuild($ListBuild("TITLE", "Try OcuTalon"))
	Set texts = texts_$ListBuild($ListBuild("HEADING", "Try OcuTalon in two minutes"))
	Set texts = texts_$ListBuild($ListBuild("SUBHEADING", "Break the feed, and approve the fix from your phone."))
	Set texts = texts_$ListBuild($ListBuild("DESCRIPTION", "OcuTalon is an assistant that lives inside InterSystems IRIS Interoperability. When a feed breaks, it reads the failed messages and the trace, names the cause in plain English, and proposes a fix that waits for your approval. For everything that arrives, an AI Hub agent makes one attention decision (ignore it, save it for your daily digest, tell you now, or act), and every decision, with its reasons and cost, is a production message you can open in Visual Trace. No API key needed."))
	Set texts = texts_$ListBuild($ListBuild("SIGNINHEADING", "Sign in to the demo"))
	Set texts = texts_$ListBuild($ListBuild("SESSIONNOTE", "Your session is yours alone and lasts until the next reset. Signing in again from this browser picks it up."))
	Set texts = texts_$ListBuild($ListBuild("WARNING", "Other visitors can see messages in Visual Trace, so don't type personal information."))
	Set texts = texts_$ListBuild($ListBuild("SUBMIT", "Sign in and start"))
	Set texts = texts_$ListBuild($ListBuild("COPYUSERNAME", "Copy user name"))
	Set texts = texts_$ListBuild($ListBuild("COPYPASSWORD", "Copy password"))
	Set texts = texts_$ListBuild($ListBuild("COPIED", "Copied"))
	Set texts = texts_$ListBuild($ListBuild("COPYFAILED", "Couldn't copy. Select the text and copy it yourself."))
	Set texts = texts_$ListBuild($ListBuild("BEFOREHEADING", "Before you start"))
	Set texts = texts_$ListBuild($ListBuild("RESETLINE", "The demo resets every {interval}. Next reset: {time} ({countdown})."))
	Set texts = texts_$ListBuild($ListBuild("OWNLINE", "Your chat, phone, mailbox and orders are yours alone."))
	Set texts = texts_$ListBuild($ListBuild("TELEGRAMLINE", "Have Telegram? You can scan a QR code inside to get the notices on your own phone."))
	Set texts = texts_$ListBuild($ListBuild("LIMITLINE", "Each session can send {limit} messages an hour in the chat or Telegram."))
	Set texts = texts_$ListBuild($ListBuild("TOOMANY", "Too many new sessions from your network this hour. You can start another at {time}."))
	Set texts = texts_$ListBuild($ListBuild("BUSY", "The demo is busy right now. Try again in a few minutes, or install it yourself."))
	Set texts = texts_$ListBuild($ListBuild("SHELLLINE", "OcuTalon can't run shell commands, and every action it takes is recorded in the IRIS audit log."))
	Set texts = texts_$ListBuild($ListBuild("VISUALTRACE", "Read-only Visual Trace account, for opening Visual Trace in the portal yourself (trace links on the page are already signed in). See each decision with its cost, and every step."))
	Set texts = texts_$ListBuild($ListBuild("COPYTRACEUSERNAME", "Copy Visual Trace user name"))
	Set texts = texts_$ListBuild($ListBuild("COPYTRACEPASSWORD", "Copy Visual Trace password"))
	Set texts = texts_$ListBuild($ListBuild("FOOTERNOTE", "OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation."))
	Set texts = texts_$ListBuild($ListBuild("INSTALL", "Install it yourself (README)"))
	Set texts = texts_$ListBuild($ListBuild("NEWTAB", "(opens in a new tab)"))
	Set texts = texts_$ListBuild($ListBuild("INTERVALONE", "{n} hour"))
	Set texts = texts_$ListBuild($ListBuild("INTERVALOTHER", "{n} hours"))
	Set texts = texts_$ListBuild($ListBuild("README", "https://github.com/jbrandtmse/OcuTalon#readme"))
	Set position = 0
	While $ListNext(texts, position, pair) {
		Set name = $List(pair, 1)
		Do $$$AssertEquals($Parameter(splash, name), $List(pair, 2), name_" is the AC's text")
		Do $$$AssertTrue(..IsAscii($Parameter(splash, name)), name_" is printable ASCII")
	}
	Do $$$AssertEquals($Parameter(splash, "USERLABEL"), "User name", "the user name label is Login's")
	Do $$$AssertEquals($Parameter(splash, "PASSWORDLABEL"), "Password", "the password label is Login's")
	Do $$$AssertEquals($Parameter(splash, "LOGOALT"), "OcuTalon", "the logo's alt is Login's")
}

/// The policy is AD-13's template over the hashes of SplashAssets' blocks, which Splash's inherited generators compute, and the
/// local page's policy is unchanged.
Method TestPolicy()
{
	Set css = $Parameter("OcuTalon.Web.Public.SplashAssets", "CSS")
	Set script = $Parameter("OcuTalon.Web.Public.SplashAssets", "SCRIPT")
	Do $$$AssertTrue($Length(css) > 1000, "the splash's stylesheet is generated")
	Do $$$AssertTrue($Length(script) > 500, "the splash's script is generated")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Public.Splash", "CSS"), css, "Splash's stylesheet is SplashAssets'")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Public.Splash", "SCRIPT"), script, "Splash's script is SplashAssets'")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Splash).StyleHash(), ..Hash(css), "Splash.StyleHash is the hash of SplashAssets' stylesheet")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Splash).ScriptHash(), ..Hash(script), "Splash.ScriptHash is the hash of SplashAssets' script")
	Set expected = "default-src 'none'; script-src 'sha256-"_..Hash(script)_"'; style-src 'sha256-"_..Hash(css)_"'; img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Splash).Policy(), expected, "the splash's policy")
	Set signInCss = $Parameter("OcuTalon.Web.Public.SignInAssets", "CSS")
	Set signInScript = $Parameter("OcuTalon.Web.Public.SignInAssets", "SCRIPT")
	Do $$$AssertTrue(css '= signInCss, "the splash's stylesheet is not the local page's")
	Do $$$AssertEquals($Parameter("OcuTalon.Web.Public.Login", "CSS"), signInCss, "Login keeps the local stylesheet")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Login).Policy(), "default-src 'none'; script-src 'sha256-"_..Hash(signInScript)_"'; style-src 'sha256-"_..Hash(signInCss)_"'; img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'", "Login's policy is unchanged")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Login).StyleHash(), ..Hash(signInCss), "Login.StyleHash is unchanged")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Login).ScriptHash(), ..Hash(signInScript), "Login.ScriptHash is unchanged")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Login).UseSplash(), 1, "Login hands over with the flag set")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Splash).UseSplash(), 0, "Splash does not hand over again")

	New %request, %response, %session
	Set %request = ##class(%CSP.Request).%New()
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New("ZzSplashTest", 0)
	Do $$$AssertTrue(##class(OcuTalon.Web.Public.Splash).OnPreHTTP(), "OnPreHTTP lets the page be written")
	Do $$$AssertEquals(%response.GetHeader("Content-Security-Policy"), expected, "the header")
	Do $$$AssertEquals(%response.GetHeader("Cache-Control"), "no-store", "Cache-Control")
}

/// Login.Show writes the local page, byte for byte what Login's own OnPreHTTP and OnPage write, when the flag is "0" or unset, and
/// the splash with the splash's policy when it is "1".
Method TestShowFollowsTheFlag()
{
	Set login = "OcuTalon.Web.Public.Login"
	Set splash = "OcuTalon.Web.Public.Splash"
	Set own = ..Render("login", "", .ownPolicy)
	Do $$$AssertTrue($Length(own) > 1000, "Login's own page is written")
	Do $$$AssertTrue(own [ "<title>Sign in &middot; OcuTalon</title>", "it is the local page")
	Do $$$AssertEquals(ownPolicy, ##class(OcuTalon.Web.Public.Login).Policy(), "Login's own header is Login.Policy()")
	For flag = "0", "" {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", flag)
		Set shown = ..Render("show", "", .shownPolicy)
		Do $$$AssertEquals(shown, own, "Show with the flag '"_flag_"' writes the local page byte for byte")
		Do $$$AssertEquals(shownPolicy, ##class(OcuTalon.Web.Public.Login).Policy(), "and the local policy")
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "1")
	Set shown = ..Render("show", "", .shownPolicy)
	Do $$$AssertEquals(shown, ..Render("splash", "", .direct), "Show with the flag '1' writes the splash")
	Do $$$AssertTrue(shown [ "<title>Try OcuTalon</title>", "it is the splash")
	Do $$$AssertEquals(shownPolicy, ##class(OcuTalon.Web.Public.Splash).Policy(), "with the splash's policy")
	Do $$$AssertEquals(direct, ##class(OcuTalon.Web.Public.Splash).Policy(), "which OnPreHTTP of Splash also sets")
	Do $$$AssertTrue(shownPolicy '= ownPolicy, "the two policies differ")
}

/// The first visit: the head, the sign-in card with its prefilled values and copy buttons, the Before you start card, the Visual
/// Trace card and the footer, with the markup the browser rows rely on.
Method TestPage()
{
	Set page = ..Page("", $SYSTEM.Status.Error(864), "")
	Do $$$AssertTrue(page [ "<html lang=""en"">", "lang is en")
	Do $$$AssertTrue(page [ "<title>Try OcuTalon</title>", "the tab title")
	Do $$$AssertTrue(page [ "alt=""OcuTalon"" width=""240"" height=""134"">", "the 240px logo with its alt")
	Do $$$AssertTrue(page [ "<h1>Try OcuTalon in two minutes</h1>", "the heading")
	Do $$$AssertTrue(page [ "<p class=""subhead"">Break the feed, and approve the fix from your phone.</p>", "the subheading")
	Do $$$AssertTrue(page [ "<p class=""lead"">OcuTalon is an assistant that lives inside InterSystems IRIS Interoperability.", "the description")
	Do $$$AssertTrue(page [ "<h2 class=""card-title"" id=""ocu-signin-h"">Sign in to the demo</h2>", "the sign-in card's heading")
	Do $$$AssertTrue(page [ "<label class=""field-label"" for=""ocu-user"">User name</label>", "the user name label")
	Do $$$AssertTrue(page [ "<label class=""field-label"" for=""ocu-pass"">Password</label>", "the password label")
	Do $$$AssertTrue(page [ "id=""ocu-user"" type=""text"" name=""IRISUsername""", "the user field is a text input named IRISUsername")
	Do $$$AssertTrue(page [ "id=""ocu-pass"" type=""text"" name=""IRISPassword""", "the password field is a text input named IRISPassword")
	Do $$$AssertTrue(page [ "name=""IRISUsername"" autocomplete=""off"" autocapitalize=""none"" spellcheck=""false"" value=""DemoVisitor"">", "the user field holds the published demo user")
	Do $$$AssertTrue(page [ "name=""IRISPassword"" autocomplete=""off"" autocapitalize=""none"" spellcheck=""false"" value=""demo-secret"">", "the password field holds the published demo password")
	For name = "Copy user name", "Copy password", "Copy Visual Trace user name", "Copy Visual Trace password" {
		Do $$$AssertTrue(page [ "aria-label="""_name_""">", "the copy button '"_name_"'")
	}
	Do $$$AssertEquals(..Count(page, "type=""button"""), 4, "four buttons that are not the submit button")
	Do $$$AssertTrue(page '[ "Show password", "there is no show or hide toggle")
	Do $$$AssertTrue(page [ "<p class=""hint"">Your session is yours alone and lasts until the next reset. Signing in again from this browser picks it up.</p>", "the session line")
	Do $$$AssertTrue(page [ "<p>Other visitors can see messages in Visual Trace, so don't type personal information.</p></div>"_$Char(10)_"<button class=""btn-primary"" type=""submit"" name=""IRISLogin"" value=""Sign in and start"" aria-describedby=""ocu-warning"">Sign in and start</button>", "the warning is the element just before the button, which it describes")
	Do $$$AssertTrue(page [ "<div class=""notice"" id=""ocu-warning""><svg", "the warning notice has the id the button names")
	Do $$$AssertTrue(page [ "<path d=""m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3""/>", "the warning notice draws the warning triangle")
	Do $$$AssertTrue(page [ "<h2 class=""card-title"" id=""ocu-before-h"">Before you start</h2>", "the Before you start card")
	Do $$$AssertTrue(page [ "<li>The demo resets every 4 hours. Next reset: <span class=""nowrap""><time class=""tnum"" id=""ocu-reset-time"" datetime=""", "the reset line's start")
	Do $$$AssertTrue(page [ "data-step=""14400""></time> (<span class=""tnum"" id=""ocu-countdown"" aria-hidden=""true""></span><span class=""sr-only"" id=""ocu-countdown-spoken""></span>).</span></li>", "the reset line's time and countdown elements, for the script")
	Do $$$AssertTrue(page [ "<li>Your chat, phone, mailbox and orders are yours alone.</li>", "the second line")
	Do $$$AssertTrue(page [ "<li>Have Telegram? You can scan a QR code inside to get the notices on your own phone.</li>", "the Telegram line")
	Do $$$AssertTrue(page [ "<li>Each session can send 50 messages an hour in the chat or Telegram.</li>", "the limit line")
	Do $$$AssertTrue(page [ "<li>OcuTalon can't run shell commands, and every action it takes is recorded in the IRIS audit log.</li>", "the shell line")
	Do $$$AssertTrue(page [ "<h2 class=""card-title"" id=""ocu-vt-h"">Read-only Visual Trace account,</h2><p>for opening Visual Trace in the portal yourself (trace links on the page are already signed in). See each decision with its cost, and every step.</p>", "the Visual Trace card's heading and paragraph")
	Do $$$AssertTrue(page [ "<dt>User name</dt><dd><span id=""ocu-vt-user"">TraceReader</span>", "the read-only user")
	Do $$$AssertTrue(page [ "<dt>Password</dt><dd><span id=""ocu-vt-pass"">trace-secret</span>", "the read-only password")
	Do $$$AssertTrue(page [ "</main>"_$Char(10)_"<footer class=""splash-footer""><p>OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.</p>", "the footer is outside main, with the note")
	Do $$$AssertTrue(page [ "<a class=""link"" href=""https://github.com/jbrandtmse/OcuTalon#readme"" target=""_blank"" rel=""noopener noreferrer"">Install it yourself (README)<span class=""sr-only""> (opens in a new tab)</span><svg", "the README link")
	Do $$$AssertEquals(..Count(page, "role=""status"""), 1, "one live region")
	Do $$$AssertEquals(..Count(page, "autofocus"), 0, "nothing has the focus on a first visit")
	Do $$$AssertTrue(page '[ "id=""ocu-error""", "no error element")

	Do $$$AssertEquals(..Count(page, "<form "), 1, "one form")
	Do $$$AssertTrue(page [ "<form name=""Login"" method=""post"" action=""/ocutalon/x?a=1&amp;b=2"">", "the action is Error:FullURL, escaped")
	Set formText = $Piece($Piece(page, "<form ", 2), "</form>", 1)
	Set allowed = $ListBuild("IRISSessionToken", "IRISUsername", "IRISPassword", "IRISLogin")
	Set names = "", at = 0
	While 1 {
		Set at = $Find(formText, " name=""", at)
		If 'at Quit
		Set stop = $Find(formText, """", at)
		Set names = names_$ListBuild($Extract(formText, at, stop - 2))
	}
	Set position = 0
	While $ListNext(names, position, name) {
		Do $$$AssertTrue($ListFind(allowed, name) > 0, "the form field '"_name_"' is one of the four that the proxy admits")
	}
	For name = "IRISUsername", "IRISPassword", "IRISLogin" {
		Do $$$AssertTrue($ListFind(names, name) > 0, "the form has the field "_name)
	}
	Do $$$AssertTrue(($ZConvert(page, "L") '[ "oldpassword") && ($ZConvert(page, "L") '[ "repeatpassword"), "no old-password or repeat-password field")
	Do $$$AssertEquals(..Count(page, "<style>"), 1, "one inline style")
	Do $$$AssertEquals(..Count(page, "<script>"), 1, "one inline script")
	Do $$$AssertTrue(page '[ " style=", "no style attribute")
	Do $$$AssertTrue(page '[ "<script src", "no external script")
	Do $$$AssertTrue(page '[ "<link rel=""stylesheet""", "no external stylesheet")
	Do $$$AssertTrue(page '[ "@import", "no import")
	Do $$$AssertTrue(page '[ "url(", "no url() in the stylesheet")
	Do $$$AssertTrue(page '[ " onclick=", "no inline handler")
	Set images = $ListFromString($Parameter("OcuTalon.Web.Public.Login", "IMAGES"))
	Set readme = $Parameter("OcuTalon.Web.Public.Splash", "README")
	Set referenced = ..References(page)
	Set position = 0
	While $ListNext(referenced, position, reference) {
		Do $$$AssertTrue(($ListFind(images, $Extract(reference, 2, *)) > 0) || (reference = readme), reference_" is one of the five images or the README link")
	}
	Set position = 0
	While $ListNext(images, position, image) {
		Do $$$AssertTrue($ListFind(referenced, "/"_image) > 0, image_" is used by the page")
	}
	Do $$$AssertTrue($ListFind(referenced, readme) > 0, "the README link is on the page")

	Set again = ..Page("", $SYSTEM.Status.Error(864), "", 1)
	Do $$$AssertEquals(again, page, "?signedOut=1 shows no notice on the splash")
}

/// A refused sign-in keeps the typed user name, clears the password, marks both fields and shows the error under the button, with
/// the focus.
Method TestWrongPassword()
{
	Set page = ..Page("", $SYSTEM.Status.Error(822), "alice")
	Set error = "<p class=""field-error"" id=""ocu-error"" tabindex=""-1"" autofocus>"
	Do $$$AssertTrue(page [ error, "the error is a focusable element that has the focus")
	Do $$$AssertTrue(page [ "<span>That user name and password didn't work.</span></p>", "the wrong-credentials text")
	Do $$$AssertTrue($Find(page, error) > $Find(page, "Sign in and start</button>"), "the error comes after the button")
	Do $$$AssertEquals(..Count(page, "aria-invalid=""true"" aria-describedby=""ocu-error"""), 2, "both fields are marked")
	Do $$$AssertEquals(..Count(page, "autofocus"), 1, "only the error has the focus")
	Do $$$AssertTrue(page [ "spellcheck=""false"" value=""alice"" aria-invalid=""true""", "the user field keeps the typed name")
	Do $$$AssertTrue(page [ "name=""IRISPassword"" autocomplete=""off"" autocapitalize=""none"" spellcheck=""false"" value="""" aria-invalid=""true""", "the password field is empty")
	Do $$$AssertTrue(page '[ "demo-secret", "the published password is not written")
	Do $$$AssertEquals(..Count(page, "<div class=""input invalid"">"), 2, "both boxes show the error border")
}

/// An account without the OcuTalon role gets the no-role text, with nothing marked and the published values in the fields.
Method TestNoRole()
{
	Set page = ..Page("norole", "", "")
	Do $$$AssertTrue(page [ "id=""ocu-error"" tabindex=""-1"" autofocus>", "the message has the focus")
	Do $$$AssertTrue(page [ "<span>This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it.</span></p>", "the no-role text")
	Do $$$AssertTrue(page '[ "aria-invalid", "no field is marked")
	Do $$$AssertTrue(page [ "value=""DemoVisitor""", "the user field holds the published value")
	Do $$$AssertTrue(page [ "value=""demo-secret""", "the password field holds the published value")
}

/// The address-limit refusal (Story 16.3): Login.Show with the state "addressLimit" and the time puts the AC's sentence under the
/// button, with the time element (datetime escaped, empty in the markup) where {time} is; nothing is marked, the button is enabled, the
/// published values stay in the fields, the error has the focus, and the policy is the splash's. TOOMANY is the catalog's text.
Method TestTooManySessions()
{
	Set until = "2026-10-25T15:20:00Z"
	Set page = ..Render("show", "addressLimit", .policy, "", "", 0, until)
	Set error = "<p class=""field-error"" id=""ocu-error"" tabindex=""-1"" autofocus>"
	Do $$$AssertTrue(page [ error, "the error is a focusable element that has the focus")
	Do $$$AssertTrue(page [ "<span>Too many new sessions from your network this hour. You can start another at <time class=""tnum"" id=""ocu-error-time"" datetime=""2026-10-25T15:20:00Z""></time>.</span></p>", "the AC's sentence with the time element")
	Do $$$AssertTrue($Find(page, error) > $Find(page, "Sign in and start</button>"), "the error comes after the button")
	Do $$$AssertTrue(page '[ "aria-invalid", "no field is marked")
	Do $$$AssertTrue(page '[ "disabled", "the button is enabled")
	Do $$$AssertEquals(..Count(page, "autofocus"), 1, "only the error has the focus")
	Do $$$AssertTrue(page [ "value=""DemoVisitor""", "the user field holds the published value")
	Do $$$AssertTrue(page [ "value=""demo-secret""", "the password field holds the published value")
	Do $$$AssertEquals(policy, ##class(OcuTalon.Web.Public.Splash).Policy(), "the splash's exact policy")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Splash).#TOOMANY, ##class(OcuTalon.Msg.Catalog).Entry("splash.tooManySessions").text, "TOOMANY is the catalog's text")
	Set hostile = ..Render("show", "addressLimit", .policy, "", "", 0, "x""><b id=pwned>&")
	Do $$$AssertTrue(hostile [ "datetime=""x&quot;&gt;&lt;b id=pwned&gt;&amp;""", "the time attribute is escaped")
	Do $$$AssertTrue(hostile '[ "<b id=pwned>", "and never written raw")
	Set plain = ..Render("show", "", .policy, "", "", 0, until)
	Do $$$AssertTrue(plain '[ "id=""ocu-error""", "a state of no refusal shows no error, whatever time is given")
	Set again = ..Render("show", "norole", .policy, "", "", 0, "")
	Do $$$AssertTrue(again '[ "<time class=""tnum"" id=""ocu-error-time""", "no other state writes the time element")
}

/// The busy state (Story 16.5, rows 2 and 3): with the demo busy (a reserve larger than the cap forces it), a request with no state
/// and no message shows the busy text, then the README link as the footer writes it, under the button, and the page and the marker
/// header agree. Nothing is marked, the button is enabled, the published values stay, the error has the focus and the policy is the
/// splash's. The other messages win, and a page that is not busy has no error and no header. BUSY is the catalog's text.
Method TestDemoBusy()
{
	Set settings = "OcuTalon.Data.Public.Settings"
	Do $ClassMethod(settings, "Set", "connectionCap", 1)
	Do $ClassMethod(settings, "Set", "connectionReserve", 9)
	Set link = ..Link(..Render("show", "", .policy, "", "", 0, "", .header))
	Do $$$AssertTrue(link [ "href=""https://github.com/jbrandtmse/OcuTalon#readme"" target=""_blank"" rel=""noopener noreferrer"">Install it yourself (README)<span class=""sr-only""> (opens in a new tab)</span><svg", "the footer's link: the README, a new tab, its text, the sr-only text and the icon")
	Set busy = "<span>The demo is busy right now. Try again in a few minutes, or install it yourself. "_link_"</span></p>"
	For mode = "show", "splash" {
		Set page = ..Render(mode, "", .policy, "", "", 0, "", .header)
		Set error = "<p class=""field-error"" id=""ocu-error"" tabindex=""-1"" autofocus>"
		Do $$$AssertTrue(page [ error, mode_": the error is a focusable element that has the focus")
		Do $$$AssertTrue(page [ busy, mode_": the busy text, then the README link as the footer writes it")
		Do $$$AssertTrue($Find(page, error) > $Find(page, "Sign in and start</button>"), mode_": the error comes after the button")
		Do $$$AssertTrue(page '[ "aria-invalid", mode_": no field is marked")
		Do $$$AssertTrue(page '[ "disabled", mode_": the button is enabled")
		Do $$$AssertEquals(..Count(page, "autofocus"), 1, mode_": only the error has the focus")
		Do $$$AssertTrue(page [ "value=""DemoVisitor""", mode_": the user field holds the published value")
		Do $$$AssertTrue(page [ "value=""demo-secret""", mode_": the password field holds the published value")
		Do $$$AssertEquals(policy, ##class(OcuTalon.Web.Public.Splash).Policy(), mode_": the splash's exact policy")
		Do $$$AssertEquals(header, "1", mode_": the marker header")
	}
	Do $$$AssertEquals(..Count(..Render("show", "", .policy, "", "", 0, "", .header), link), 2, "a busy page writes the link twice: the error's and the footer's")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Splash).#BUSY, ##class(OcuTalon.Msg.Catalog).Render("banner.demoBusy", "", "web"), "BUSY is the catalog's text")
	Do $$$AssertEquals(##class(OcuTalon.Web.Public.Status).#BUSYHEADER, "X-OcuTalon-Busy", "the header's name is Status'")

	Set credentials = ..Render("show", "", .policy, 822, "someone", 0, "", .header)
	Do $$$AssertTrue(credentials [ "That user name and password didn't work.", "the wrong-credentials error wins")
	Do $$$AssertTrue(credentials [ "aria-invalid=""true""", "and marks both fields")
	Do $$$AssertTrue(credentials '[ "The demo is busy", "and shows no busy text")
	Do $$$AssertEquals(header, "", "and sets no header")
	Set norole = ..Render("show", "norole", .policy, "", "", 0, "", .header)
	Do $$$AssertTrue(norole [ "This IRIS account doesn't have the OcuTalon user role.", "the no-role text wins")
	Do $$$AssertTrue(norole '[ "The demo is busy", "and shows no busy text")
	Do $$$AssertEquals(header, "", "and sets no header")
	Set limit = ..Render("show", "addressLimit", .policy, "", "", 0, "2026-10-25T15:20:00Z", .header)
	Do $$$AssertTrue(limit [ "Too many new sessions from your network this hour.", "TOOMANY shows")
	Do $$$AssertTrue(limit '[ "The demo is busy", "and shows no busy text")
	Do $$$AssertEquals(header, "", "and sets no header")

	Set refusal = ..Render("show", "busy", .policy, "", "", 0, "", .header)
	Do $$$AssertTrue(refusal [ busy, "the post-sign-in refusal's state shows the busy error")
	Do $$$AssertEquals(header, "1", "and carries the marker header")

	Do $ClassMethod(settings, "Set", "connectionCap", 1000000)
	Do $ClassMethod(settings, "Set", "connectionReserve", 2)
	Set plain = ..Render("show", "", .policy, "", "", 0, "", .header)
	Do $$$AssertTrue(plain '[ "id=""ocu-error""", "a demo that is not busy shows no error")
	Do $$$AssertEquals(header, "", "and no header")
	Do $ClassMethod(settings, "Set", "connectionCap", "")
	Set plain = ..Render("splash", "", .policy, "", "", 0, "", .header)
	Do $$$AssertTrue(plain '[ "id=""ocu-error""", "without a cap there is no error")
	Do $$$AssertEquals(header, "", "and no header")
}

/// The README link as the footer of a page writes it: the anchor, from its tag to its end tag.
ClassMethod Link(page As %String) As %String [ Private ]
{
	Set footer = $Piece($Piece(page, "<footer class=""splash-footer"">", 2), "</footer>", 1)
	Quit $Piece(footer, "</p>", 2, *)
}

/// (QA) The typed user name comes back from the request, so it is escaped where it is written, whatever it holds: a name with markup
/// is never written raw and never closes the value attribute, and the page still has its one style and one script.
Method TestTypedNameIsEscaped()
{
	Set hostile = "x""><b id=pwned>&'"
	Set page = ..Page("", $SYSTEM.Status.Error(822), hostile)
	Do $$$AssertTrue(page [ "spellcheck=""false"" value=""x&quot;&gt;&lt;b id=pwned&gt;&amp;", "the typed name is escaped in the user field")
	Do $$$AssertTrue(page '[ "<b id=pwned>", "the typed markup is never written raw")
	Do $$$AssertTrue(page '[ "pwned>", "the typed angle bracket is not written raw")
	Do $$$AssertTrue(page '[ "&'""", "the typed apostrophe is not written raw")
	Do $$$AssertEquals(..Count(page, "<style>"), 1, "still one inline style")
	Do $$$AssertEquals(..Count(page, "<script>"), 1, "still one inline script")
	Do $$$AssertEquals(..Count(page, "aria-invalid=""true"" aria-describedby=""ocu-error"""), 2, "both fields are still marked")
}

/// (QA) Every error code but 864 is a refusal: the wrong-credentials text under the button, both fields marked, the user name kept
/// and the password empty. The first visit (864), no code and the signed-out query show none of it.
Method TestEveryCodeButTheFirstVisitIsARefusal()
{
	For code = 801, 822, 853, 863, 885, 5001 {
		Set page = ..Page("", $SYSTEM.Status.Error(code), "carol")
		Do $$$AssertTrue(page [ "<span>That user name and password didn't work.</span></p>", "code "_code_": the wrong-credentials text")
		Do $$$AssertEquals(..Count(page, "aria-invalid=""true"" aria-describedby=""ocu-error"""), 2, "code "_code_": both fields are marked")
		Do $$$AssertTrue(page [ "spellcheck=""false"" value=""carol"" aria-invalid=""true""", "code "_code_": the typed name is kept")
		Do $$$AssertTrue(page [ "name=""IRISPassword"" autocomplete=""off"" autocapitalize=""none"" spellcheck=""false"" value="""" aria-invalid=""true""", "code "_code_": the password is empty")
		Do $$$AssertTrue(page '[ "demo-secret", "code "_code_": the published password is not written")
		Do $$$AssertEquals(..Count(page, "autofocus"), 1, "code "_code_": only the error has the focus")
	}
	For code = "", $SYSTEM.Status.Error(864) {
		Set page = ..Page("", code, "carol")
		Do $$$AssertTrue(page '[ "id=""ocu-error""", "no error element for code '"_$Select(code = "": "none", 1: "864")_"'")
		Do $$$AssertTrue(page '[ "aria-invalid", "no field is marked")
		Do $$$AssertTrue(page [ "value=""DemoVisitor""", "the published user name is shown, not the typed one")
		Do $$$AssertEquals(..Count(page, "autofocus"), 0, "nothing has the focus")
	}
}

/// Values that are not set leave their line or card out, one hour reads in the singular, and a value is escaped where it is written.
Method TestEdgeValues()
{
	Set settings = "OcuTalon.Data.Public.Settings"
	Do $ClassMethod(settings, "Set", "resetAnchor", "")
	Set page = ..Page("", "", "")
	Do $$$AssertTrue(page '[ "id=""ocu-reset-time""", "no anchor: no reset line")
	Do $$$AssertTrue(page '[ "The demo resets every", "no anchor: no words about the reset")
	Do $$$AssertTrue(page [ "<li>Each session can send 50 messages", "the other lines stay")
	Do $ClassMethod(settings, "Set", "resetAnchor", "2026-10-18T00:00:00Z")

	Do $ClassMethod(settings, "Set", "resetIntervalHours", "")
	Set page = ..Page("", "", "")
	Do $$$AssertTrue(page '[ "id=""ocu-reset-time""", "no interval: no reset line")
	Do $ClassMethod(settings, "Set", "resetIntervalHours", 1)
	Set page = ..Page("", "", "")
	Do $$$AssertTrue(page [ "<li>The demo resets every 1 hour. Next reset: ", "an interval of 1 reads '1 hour'")
	Do $$$AssertTrue(page [ "data-step=""3600""", "and steps by 3600 seconds")
	Do $ClassMethod(settings, "Set", "resetIntervalHours", 4)

	Do $ClassMethod(settings, "Set", "messageAllowance", "")
	Set page = ..Page("", "", "")
	Do $$$AssertTrue(page '[ "messages an hour", "no allowance: no limit line")
	Do $$$AssertTrue(page [ "<li>Have Telegram?", "the other lines stay")
	Do $ClassMethod(settings, "Set", "messageAllowance", 50)

	Do $ClassMethod(settings, "Set", "readonlyPassword", "")
	Set page = ..Page("", "", "")
	Do $$$AssertTrue(page '[ "Read-only Visual Trace", "no read-only password: no Visual Trace card")
	Do $$$AssertTrue(page '[ "Copy Visual Trace", "and no copy buttons for it")
	Do $$$AssertTrue(page '[ "trace-secret", "and no value of it")
	Do $$$AssertTrue(page [ "</main>", "the page is complete")
	Do $ClassMethod(settings, "Set", "readonlyPassword", "trace-secret")
	Do $ClassMethod(settings, "Set", "readonlyUser", "")
	Set page = ..Page("", "", "")
	Do $$$AssertTrue(page '[ "Read-only Visual Trace", "no read-only user: no Visual Trace card")
	Do $ClassMethod(settings, "Set", "readonlyUser", "TraceReader")

	Do $ClassMethod(settings, "Set", "demoUser", "zz<""&'>")
	Set page = ..Page("", "", "")
	Do $$$AssertTrue(page [ "value=""zz&lt;&quot;&amp;", "the demo user is escaped in the input's value")
	Do $$$AssertTrue(page [ "&gt;""", "to its end")
	Do $$$AssertTrue(page '[ "zz<", "and never written raw")
	Do $$$AssertTrue(page '[ "'>""", "the apostrophe is escaped too")
	Do $ClassMethod(settings, "Set", "demoUser", "DemoVisitor")

	For key = "demoPassword", "readonlyUser", "readonlyPassword", "messageAllowance" {
		Do $ClassMethod(settings, "Set", key, "zz<""&'>")
		Set page = ..Page("", "", "")
		Do $$$AssertTrue(page [ "zz&lt;&quot;&amp;", key_" is escaped where it is written")
		Do $$$AssertTrue(page '[ "zz<", key_" is never written raw")
		Do $$$AssertTrue(page '[ "'>", key_": the apostrophe is escaped too")
		Do $ClassMethod(settings, "Set", key, $Case(key, "demoPassword": "demo-secret", "readonlyUser": "TraceReader", "readonlyPassword": "trace-secret", : 50))
	}
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^||SplashSaved
	Set settings = "OcuTalon.Data.Public.Settings"
	Set keys = $ListFromString($Parameter(settings, "KEYS"))
	Set position = 0
	While $ListNext(keys, position, key) {
		Set ^||SplashSaved(key) = $ClassMethod(settings, "Get", key)
	}
	Set values = $ListBuild($ListBuild("onlineDemo", "1"), $ListBuild("demoUser", "DemoVisitor"), $ListBuild("demoPassword", "demo-secret"), $ListBuild("readonlyUser", "TraceReader"), $ListBuild("readonlyPassword", "trace-secret"), $ListBuild("resetIntervalHours", 4), $ListBuild("resetAnchor", "2026-10-18T00:00:00Z"), $ListBuild("messageAllowance", 50), $ListBuild("connectionCap", ""))
	Set position = 0
	While $ListNext(values, position, pair) {
		Do $ClassMethod(settings, "Set", $List(pair, 1), $List(pair, 2))
	}
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set settings = "OcuTalon.Data.Public.Settings"
	Set key = ""
	For {
		Set key = $Order(^||SplashSaved(key), 1, value)
		Quit:key=""
		Do $ClassMethod(settings, "Set", key, value)
	}
	Kill ^||SplashSaved
	Quit $$$OK
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

ClassMethod Count(text As %String, what As %String) As %Integer [ Private ]
{
	Quit $Length(text, what) - 1
}

/// The splash for a state, the server's error code and the typed user name (and the query signedOut=1 when signedOut is 1).
Method Page(state As %String, code As %String, user As %String, signedOut As %Boolean = 0) As %String [ Private ]
{
	Quit ..Render("splash", state, .policy, code, user, signedOut)
}

/// Writes a page in process, with a stand-in request, and returns it with the Content-Security-Policy that the response then holds:
///   splash  Splash.OnPage (and Splash's OnPreHTTP, for the policy)
///   login   Login's own OnPreHTTP, then its OnPage
///   show    Login.Show with no header to write, as the shell's dispatch calls it
/// busyHeader is the marker header that the response then holds.
Method Render(mode As %String, state As %String, Output policy As %String, code As %String = "", user As %String = "", signedOut As %Boolean = 0, until As %String = "", Output busyHeader As %String) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(%CSP.Request).%New()
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New("ZzSplashTest", 0)
	Set %request.Data("Error:FullURL", 1) = "/ocutalon/x?a=1&b=2"
	Set %request.Data("Error:URL", 1) = "/ocutalon/x"
	If code '= "" Set %request.Data("Error:ErrorCode", 1) = code
	If user '= "" Set %request.Data("IRISUsername", 1) = user
	If signedOut Set %request.Data("signedOut", 1) = 1
	Set %OcuTalonState = state
	Set %OcuTalonUntil = until
	Set file = ##class(%File).TempFilename("html")
	Set io = $IO
	Open file:("NWS"):5
	If '$Test Quit ""
	Use file
	Try {
		If mode = "show" {
			Set sc = ##class(OcuTalon.Web.Public.Login).Show(state, 0, until)
		} ElseIf mode = "login" {
			Do ##class(OcuTalon.Web.Public.Login).OnPreHTTP()
			Set sc = ##class(OcuTalon.Web.Public.Login).OnPage()
		} Else {
			Do ##class(OcuTalon.Web.Public.Splash).OnPreHTTP()
			Set sc = ##class(OcuTalon.Web.Public.Splash).OnPage()
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Use io
	Close file
	Kill %OcuTalonState, %OcuTalonUntil
	Set policy = %response.GetHeader("Content-Security-Policy")
	Set busyHeader = %response.GetHeader(##class(OcuTalon.Web.Public.Status).#BUSYHEADER)
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(file)
	Set page = stream.Read(200000)
	Kill stream
	Do ##class(%File).Delete(file)
	Do $$$AssertStatusOK(sc, "the page is written ("_mode_")")
	Quit $Replace(page, $Char(13), "")
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
