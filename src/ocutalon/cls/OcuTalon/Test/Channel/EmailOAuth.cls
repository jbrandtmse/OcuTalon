/// Tests of OcuTalon.Channel.Email.OAuth (Story 21.3; AD-1, AD-3, AD-19, AD-25; U-320 conditions 1, 2, 4, 5 and 7) against IRIS's real %SYS OAuth2 objects on a
/// throwaway: a probe subclass (EmailOAuthProbe) stands in for the production job and the online-demo flag, the objects are made and removed here, and the web application
/// /csp/sys/oauth2 and the OAuth2 objects are put back as they were found (the throwaway has none). No provider is reached; no client secret, token or ID is real.
///   - TestEndpointsAreHttps, TestMockSwitchIsExactlyOne, TestScopesAreTheMinimum: the provider constants are https, the CI-only switch is exactly the value 1, and the scopes
///     are the minimum for POP3 and SMTP (c4, c5);
///   - TestSysIsTheOneNamespaceMethod, TestOnlyOneCallerOfTheClass: Sys is the one method that holds the namespace switch, and SettingsOps the one class that calls the class (c1, c2);
///   - TestSysRefusesOutsideTheJob, TestSysRefusesOnTheOnlineDemo: outside SettingsOps' production job, and on the online demo, every action refuses and changes nothing in %SYS (c1, c7);
///   - TestRegisterAndRemove: the client and the server definition with the fixed https endpoints, the client's fields, a re-register that keeps the tokens, a changed client
///     ID that deletes them, the removal of exactly what OcuTalon made, and the web application enabled and disabled by OcuTalon only;
///   - TestForeignClient, TestForeignServer: an OcuTalonMail client and a server definition for the issuer with other endpoints that OcuTalon did not create are left as they are;
///   - TestRemoveKeepsTheAppForOtherClients, TestAdminDisabledAppStaysDisabled, TestStartNeedsAClient (c2): the web application is enabled by a register that creates the client or a
///     start, never by a re-register, and not disabled while another client remains;
///   - TestState: signed in is a token row with an access token and no error; TestStartAddress: the authorization address; TestMockWarns: the mock's endpoints log a warning.
Class OcuTalon.Test.Channel.EmailOAuth Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Channel.EmailOAuthProbe";

Parameter ORIGIN = "http://127.0.0.1:52773";

Parameter CLIENTID = "zz-oauth-client-1.example";

Parameter OTHERNAME = "ZzOtherClient";

Parameter OTHERISSUER = "https://zz-other-issuer.example";

/// Why the class does not run ("" when it may): it changes IRIS's OAuth2 objects, so it runs only on a throwaway that the CI override made.
Property Missing As %String [ Private ];

Method OnBeforeAllTests() As %Status
{
	If $SYSTEM.Util.GetEnviron(##class(OcuTalon.Channel.Email.OAuth).#TESTVARIABLE) '= 1 {
		Set ..Missing = "this is not a throwaway made with the CI override ("_##class(OcuTalon.Channel.Email.OAuth).#TESTVARIABLE_" is not 1), so the OAuth2 tests don't run here"
		Quit $$$OK
	}
	Kill ^OcuTalonTest("EmailOAuth")
	Set ^OcuTalonTest("EmailOAuth", "app") = ..AppEnabled()
	Do ..Wipe()
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	If ..Missing '= "" Quit $$$OK
	Kill ^||OcuTalonEmailOAuthProbe
	Do ..Wipe()
	Do ..SetApp(0)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If ..Missing '= "" Quit $$$OK
	Kill ^||OcuTalonEmailOAuthProbe
	Do ..Wipe()
	Do ..SetApp(+$Get(^OcuTalonTest("EmailOAuth", "app"), 0))
	Kill ^OcuTalonTest("EmailOAuth")
	Quit $$$OK
}

/// 1 when the class may change IRIS's OAuth2 objects here; otherwise the test fails with the reason.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// c4: the provider endpoints are https constants whatever the environment says, except exactly 1, and the issuer, authorization and token endpoint of a provider agree.
Method TestEndpointsAreHttps()
{
	For provider = "google", "microsoft" {
		Set ^||OcuTalonEmailOAuthProbe("env") = ""
		Do $$$AssertTrue($ClassMethod(..#PROBE, "Endpoints", provider, .ep), provider_": the provider is known")
		Do $$$AssertEquals($Extract(ep("issuer"), 1, 8)_"|"_$Extract(ep("authorize"), 1, 8)_"|"_$Extract(ep("token"), 1, 8), "https://|https://|https://", provider_": issuer, authorization and token endpoints are https")
		Kill ep
		For env = "", "0", "true", " 1", "1 ", "01", "yes", "TRUE", "2" {
			Set ^||OcuTalonEmailOAuthProbe("env") = env
			Do $ClassMethod(..#PROBE, "Endpoints", provider, .ep)
			Do $$$AssertEquals($Extract(ep("token"), 1, 8), "https://", provider_": the value '"_env_"' keeps the https constants")
			Kill ep
		}
	}
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Endpoints", "yahoo", .none), 0, "an unknown provider has no endpoints")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Endpoints", "google", .ep)_"|"_ep("issuer")_"|"_ep("authorize")_"|"_ep("token"), "1|https://accounts.google.com|https://accounts.google.com/o/oauth2/v2/auth|https://oauth2.googleapis.com/token", "Google's constants")
	Kill ep
	Do $ClassMethod(..#PROBE, "Endpoints", "microsoft", .ep)
	Do $$$AssertEquals(ep("issuer")_"|"_ep("authorize")_"|"_ep("token"), "https://login.microsoftonline.com/common/v2.0|https://login.microsoftonline.com/common/oauth2/v2.0/authorize|https://login.microsoftonline.com/common/oauth2/v2.0/token", "Microsoft 365's constants")
}

/// c4: the mock's plain HTTP endpoints only for the value 1, and then under the mock's base.
Method TestMockSwitchIsExactlyOne()
{
	Do $$$AssertEquals(##class(OcuTalon.Channel.Email.OAuth).IsOn("1"), 1, "the value 1 turns it on")
	For env = "", "0", "true", " 1", "1 ", "01", "yes", "TRUE", "2" {
		Do $$$AssertEquals(##class(OcuTalon.Channel.Email.OAuth).IsOn(env), 0, "the value '"_env_"' does not")
	}
	Do $$$AssertEquals(##class(OcuTalon.Channel.Email.OAuth).#TESTVARIABLE, "OCUTALON_TEST_OAUTH_MOCK", "the variable's name")
	Set ^||OcuTalonEmailOAuthProbe("env") = "1"
	For provider = "google", "microsoft" {
		Do $ClassMethod(..#PROBE, "Endpoints", provider, .ep)
		Do $$$AssertEquals(ep("issuer")_"|"_ep("authorize")_"|"_ep("token"), "http://mock:8080/_mock/oauth/"_provider_"|http://mock:8080/_mock/oauth/"_provider_"/authorize|http://mock:8080/_mock/oauth/"_provider_"/token", provider_": with the switch on the endpoints are the mock's")
		Kill ep
	}
}

/// c5: the scopes are exactly the minimum for POP3 and SMTP, with the switch on or off.
Method TestScopesAreTheMinimum()
{
	For env = "", "1" {
		Set ^||OcuTalonEmailOAuthProbe("env") = env
		Do $ClassMethod(..#PROBE, "Endpoints", "google", .g)
		Do $ClassMethod(..#PROBE, "Endpoints", "microsoft", .m)
		Do $$$AssertEquals(g("scope"), "https://mail.google.com/", "Google's scope (switch '"_env_"')")
		Do $$$AssertEquals(m("scope"), "https://outlook.office.com/POP.AccessAsUser.All https://outlook.office.com/SMTP.Send offline_access", "Microsoft 365's scopes (switch '"_env_"')")
		Kill g, m
	}
}

/// c1: Sys is the one method of the class whose code switches the namespace (and none other names it in any form).
Method TestSysIsTheOneNamespaceMethod()
{
	Set definition = ##class(%Dictionary.ClassDefinition).%OpenId("OcuTalon.Channel.Email.OAuth")
	Set switching = ""
	For i = 1:1:definition.Methods.Count() {
		Set method = definition.Methods.GetAt(i)
		Set code = $ZConvert(method.Implementation.Read(1000000), "U")
		If (code [ "$NAMESPACE") || (code [ "$ZNSPACE") || (code [ "ZNSPACE") || (code [ "ZNSPACE") || ($ZStrip(code, "*W") [ "ZN""") Set switching = switching_$Select(switching = "": "", 1: ",")_method.Name
		If method.Name = "Sys" Do $$$AssertTrue(code [ "NEW $NAMESPACE", "Sys saves the namespace with New")
	}
	Do $$$AssertEquals(switching, "Sys", "Sys is the one method that holds the namespace")
}

/// c1, c2: nothing but SettingsOps calls the class, so no install, start or background path can reach IRIS's OAuth2 objects or the web application; the CI-only variable is read
/// only by it.
Method TestOnlyOneCallerOfTheClass()
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM %Dictionary.ClassDefinition WHERE ID %STARTSWITH 'OcuTalon.' AND NOT ID %STARTSWITH 'OcuTalon.Test.' AND ID <> 'OcuTalon.Channel.Email.OAuth'")
	Do $$$AssertTrue(rs.%SQLCODE >= 0, "the class list is read: "_rs.%Message)
	Set callers = "", names = 0
	While rs.%Next() {
		Set definition = ##class(%Dictionary.ClassDefinition).%OpenId(rs.%Get("ID"))
		If '$IsObject(definition) Continue
		Set names = names + 1
		Set found = 0
		For i = 1:1:definition.Methods.Count() {
			Set code = $ZConvert(definition.Methods.GetAt(i).Implementation.Read(1000000), "U")
			If (code [ "CHANNEL.EMAIL.OAUTH") || (code [ "OCUTALON_TEST_OAUTH_MOCK") || (code [ "/CSP/SYS/OAUTH2") || (code [ "OAUTH2.CLIENT") || (code [ "OAUTH2.SERVERDEFINITION") Set found = 1
		}
		If found Set callers = callers_$Select(callers = "": "", 1: ",")_rs.%Get("ID")
	}
	Do $$$AssertTrue(names > 200, "the product's classes were scanned ("_names_")")
	Do $$$AssertEquals(callers, "OcuTalon.Core.SettingsOps", "SettingsOps is the one class that calls the OAuth2 client class")
}

/// c1: outside SettingsOps' production job every action refuses and creates, changes and removes nothing in %SYS. This process is not a production job.
Method TestSysRefusesOutsideTheJob()
{
	If '..Guard() Quit
	Set before = ..Snapshot()
	Set sc = ##class(OcuTalon.Channel.Email.OAuth).Register("google", ..#CLIENTID, "zz-dummy-secret", ..#ORIGIN, "", .changed, .owned, .app)
	Do $$$AssertStatusNotOK(sc, "Register refuses outside the job")
	Do $$$AssertEquals(changed_"|"_owned_"|"_app, "0||", "and answers nothing changed")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Channel.Email.OAuth).Remove("client,server,app"), "Remove refuses")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Channel.Email.OAuth).State(.signedIn), "State refuses")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Channel.Email.OAuth).Start("google", ..#ORIGIN, "client", .url), "Start refuses")
	Do $$$AssertEquals(..Snapshot(), before, "%SYS is as it was")
	Set ^||OcuTalonEmailOAuthProbe("job") = 0
	Do $$$AssertStatusNotOK($ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "zz-dummy-secret", ..#ORIGIN, "", .changed, .owned, .app), "the probe outside the job refuses too")
	Do $$$AssertEquals(..Snapshot(), before, "%SYS is as it was")
}

/// c1, c7: on the online demo every action refuses and the web application stays as it was (disabled).
Method TestSysRefusesOnTheOnlineDemo()
{
	If '..Guard() Quit
	Do ..SetApp(0)
	Set before = ..Snapshot()
	Set ^||OcuTalonEmailOAuthProbe("demo") = 1
	Do $$$AssertStatusNotOK($ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "zz-dummy-secret", ..#ORIGIN, "", .changed, .owned, .app), "Register refuses on the online demo")
	Do $$$AssertStatusNotOK($ClassMethod(..#PROBE, "Remove", "client,server,app"), "Remove refuses")
	Do $$$AssertStatusNotOK($ClassMethod(..#PROBE, "State", .signedIn), "State refuses")
	Do $$$AssertStatusNotOK($ClassMethod(..#PROBE, "Start", "google", ..#ORIGIN, "client", .url, .nowOwned, .app), "Start refuses")
	Do $$$AssertEquals(..Snapshot(), before, "%SYS is as it was")
	Do $$$AssertEquals(..AppEnabled(), 0, "the web application /csp/sys/oauth2 is still disabled")
	Do $$$AssertEquals($Get(url), "", "and no authorization address came out")
}

/// The client and the server definition, and the application's flag, from a first register to the removal.
Method TestRegisterAndRemove()
{
	If '..Guard() Quit
	Do ..SetApp(0)
	Set secret = "zz-dummy-secret-"_$Random(1000000)
	Set sc = $ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, secret, ..#ORIGIN, "", .changed, .owned, .app)
	Do $$$AssertStatusOK(sc, "a first register is OK")
	Do $$$AssertEquals(changed_"|"_..Norm(owned)_"|"_app, "1|app,client,server|enabled", "it created the server definition and the client and enabled the web application")
	Do $$$AssertEquals(..AppEnabled(), 1, "the web application is enabled")
	Set fields = ..ClientFields()
	Do $$$AssertEquals(fields, "confidential|OcuTalonClient|"_..#ORIGIN_"|client_secret_post|https://mail.google.com/|"_..#CLIENTID_"|1|https://accounts.google.com", "the client: confidential, the client SSL configuration, the page's origin, client_secret_post, the scope, the ID, enabled, the issuer")
	Do $$$AssertEquals(..ServerEndpoints("https://accounts.google.com"), "https://accounts.google.com/o/oauth2/v2/auth|https://oauth2.googleapis.com/token|", "the server definition holds the fixed endpoints and no revocation endpoint")
	Do $$$AssertEquals(..SecretMatches(secret), 1, "the client holds the secret")
	Do ..SeedToken("zz-dummy-access", "zz-dummy-refresh", "")
	Set sc = $ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "", ..#ORIGIN, owned, .changed, .owned2, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_changed_"|"_..Norm(owned2)_"|"_app, "1|0|"_..Norm(owned)_"|", "a re-register with nothing new changes nothing")
	Do $$$AssertEquals(..SecretMatches(secret), 1, "an omitted secret keeps the stored one")
	Do $$$AssertEquals(..TokenRows(), 1, "and the tokens are kept")
	Set sc = $ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "", "http://127.0.0.1:52999", owned, .changed, .owned2, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_changed_"|"_..TokenRows(), "1|1|1", "a changed origin changes the client and keeps the tokens")
	Set sc = $ClassMethod(..#PROBE, "Register", "google", "zz-oauth-client-2.example", "", ..#ORIGIN, owned, .changed, .owned2, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_changed_"|"_..TokenRows(), "1|1|0", "a changed client ID deletes the tokens")
	Do $$$AssertEquals(..SecretMatches(secret), 1, "and keeps the secret")
	Do ..SeedToken("zz-dummy-access", "zz-dummy-refresh", "")
	Set sc = $ClassMethod(..#PROBE, "Register", "microsoft", "zz-oauth-client-3.example", "zz-dummy-secret-2", ..#ORIGIN, owned, .changed, .owned3, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_changed_"|"_..Norm(owned3)_"|"_app, "1|1|app,client,server|", "another provider replaces the client")
	Do $$$AssertEquals(..TokenRows(), 0, "and deletes its tokens")
	Do $$$AssertEquals(..ServerCount("https://accounts.google.com")_"|"_..ServerCount("https://login.microsoftonline.com/common/v2.0"), "0|1", "the old server definition went (OcuTalon made it, nobody else used it) and the new one exists")
	Do $$$AssertEquals($Piece(..ClientFields(), "|", 6)_"|"_$Piece(..ClientFields(), "|", 8), "zz-oauth-client-3.example|https://login.microsoftonline.com/common/v2.0", "the client is Microsoft's")
	Do ..SeedToken("zz-dummy-access", "zz-dummy-refresh", "")
	Set sc = $ClassMethod(..#PROBE, "Remove", owned3, .nowOwned, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_nowOwned_"|"_app, "1||disabled", "the removal is OK, owns nothing and disabled the web application")
	Do $$$AssertEquals(..Snapshot(), "0|0|0|0|1|", "no client, no server definition, no token remains; the web application is disabled")
	Do $$$AssertEquals(..AppEnabled(), 0, "the web application is disabled again")
	Set sc = $ClassMethod(..#PROBE, "Remove", "", .nowOwned, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_nowOwned_"|"_app, "1||", "a removal when nothing is registered is OK")
}

/// A client OcuTalonMail that OcuTalon did not create is never changed, replaced or removed, whether its server definition is one of OcuTalon's constants or not.
Method TestForeignClient()
{
	If '..Guard() Quit
	For identical = 0, 1 {
		Do ..Wipe()
		If identical Do ..MakeServer("https://accounts.google.com", "https://accounts.google.com/o/oauth2/v2/auth", "https://oauth2.googleapis.com/token", "")
		Do ..MakeClient("OcuTalonMail", "https://accounts.google.com", "zz-foreign-id")
		Set before = ..Snapshot()
		Set label = $Select(identical: " (the server definition is OcuTalon's constants)", 1: " (the server definition has other endpoints)")
		Set sc = $ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "zz-dummy-secret", ..#ORIGIN, "", .changed, .owned, .app)
		Do $$$AssertStatusNotOK(sc, "a register over a foreign client is refused"_label)
		Do $$$AssertEquals(changed_"|"_owned_"|"_app, "0||", "and answers nothing changed"_label)
		Do $$$AssertEquals($Piece(..ClientFields(), "|", 6), "zz-foreign-id", "the foreign client is as it was"_label)
		Do $$$AssertEquals(..Snapshot(), before, "nothing else changed"_label)
		Set sc = $ClassMethod(..#PROBE, "Remove", "server,app")
		Do $$$AssertStatusNotOK(sc, "a removal when the list does not name the client is refused"_label)
		Do $$$AssertEquals(..Snapshot(), before, "the foreign client and its server definition stay"_label)
		Set sc = $ClassMethod(..#PROBE, "Start", "google", ..#ORIGIN, "server", .url, .owned, .app)
		Do $$$AssertStatusNotOK(sc, "a start over a foreign client is refused"_label)
		Do $$$AssertEquals(..Snapshot(), before, "and enables nothing"_label)
	}
}

/// A server definition for the issuer that has other endpoints, or names a revocation endpoint, is foreign: not reused, not changed, not deleted.
Method TestForeignServer()
{
	If '..Guard() Quit
	Do ..MakeServer("https://accounts.google.com", "https://accounts.google.com/other/auth", "https://oauth2.googleapis.com/token", "")
	Set before = ..Snapshot()
	Set sc = $ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "zz-dummy-secret", ..#ORIGIN, "", .changed, .owned, .app)
	Do $$$AssertStatusNotOK(sc, "a register over a server definition with other endpoints is refused")
	Do $$$AssertEquals(..Snapshot(), before, "nothing was created or changed")
	Do $$$AssertEquals(..ServerEndpoints("https://accounts.google.com"), "https://accounts.google.com/other/auth|https://oauth2.googleapis.com/token|", "the foreign server definition is as it was")
	Set sc = $ClassMethod(..#PROBE, "Remove", "server,app", .nowOwned, .app)
	Do $$$AssertStatusOK(sc, "a removal that names the server definition is OK")
	Do $$$AssertEquals(..ServerEndpoints("https://accounts.google.com"), "https://accounts.google.com/other/auth|https://oauth2.googleapis.com/token|", "and leaves the foreign server definition, whose endpoints are not OcuTalon's")
	Do ..Wipe()
	Do ..MakeServer("https://accounts.google.com", "https://accounts.google.com/o/oauth2/v2/auth", "https://oauth2.googleapis.com/token", "https://oauth2.googleapis.com/revoke")
	Set sc = $ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "zz-dummy-secret", ..#ORIGIN, "", .changed, .owned, .app)
	Do $$$AssertStatusNotOK(sc, "a server definition that names a revocation endpoint is refused (IRIS would call it when deleting a token)")
	Do ..Wipe()
	Do ..MakeServer("https://accounts.google.com", "https://accounts.google.com/o/oauth2/v2/auth", "https://oauth2.googleapis.com/token", "")
	Set sc = $ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "zz-dummy-secret", ..#ORIGIN, "", .changed, .owned, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_..Norm(owned), "1|app,client", "an identical server definition is reused, and not owned")
	Set sc = $ClassMethod(..#PROBE, "Remove", owned, .nowOwned, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_..ServerCount("https://accounts.google.com"), "1|1", "removing the client leaves the reused server definition")
}

/// c2: the web application is disabled only when OcuTalon enabled it and no OAuth2 client remains.
Method TestRemoveKeepsTheAppForOtherClients()
{
	If '..Guard() Quit
	Do ..SetApp(0)
	Do ..MakeClient(..#OTHERNAME, ..#OTHERISSUER, "zz-other-id")
	Do ..SetApp(0)
	Set sc = $ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "zz-dummy-secret", ..#ORIGIN, "", .changed, .owned, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_app, "1|enabled", "a register with a disabled application enables it")
	Set sc = $ClassMethod(..#PROBE, "Remove", owned, .nowOwned, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_nowOwned_"|"_app, "1|app|", "the removal does not disable it while another client remains, and OcuTalon still owns the enable")
	Do $$$AssertEquals(..AppEnabled(), 1, "the web application is still enabled")
	Do $$$AssertEquals(..ClientExists(..#OTHERNAME)_"|"_..ServerCount(..#OTHERISSUER), "1|1", "and the other client and its server definition are untouched")
	Do ..Wipe()
	Do ..SetApp(1)
	Set sc = $ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "zz-dummy-secret", ..#ORIGIN, "", .changed, .owned, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_..Norm(owned)_"|"_app, "1|client,server|", "an application that was already enabled is not OcuTalon's")
	Set sc = $ClassMethod(..#PROBE, "Remove", owned, .nowOwned, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_app_"|"_..AppEnabled(), "1||1", "and the removal leaves it enabled")
}

/// c2: a re-register never re-enables a web application that an admin disabled; the next explicit sign-in (Start) does, and says so.
Method TestAdminDisabledAppStaysDisabled()
{
	If '..Guard() Quit
	Set sc = $ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "zz-dummy-secret", ..#ORIGIN, "", .changed, .owned, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_..AppEnabled(), "1|1", "the register enabled it")
	Do ..SetApp(0)
	Set sc = $ClassMethod(..#PROBE, "Register", "google", "zz-oauth-client-2.example", "", ..#ORIGIN, owned, .changed, .owned2, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_changed_"|"_app_"|"_..AppEnabled(), "1|1||0", "a re-register that changes the client leaves the disabled application disabled")
	Set sc = $ClassMethod(..#PROBE, "Register", "google", "zz-oauth-client-2.example", "", ..#ORIGIN, owned, .changed, .owned2, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_changed_"|"_..AppEnabled(), "1|0|0", "and so does one that changes nothing")
	Do $$$AssertStatusOK($ClassMethod(..#PROBE, "State", .signedIn), "State reads")
	Do $$$AssertEquals(..AppEnabled(), 0, "State does not enable it")
	Set sc = $ClassMethod(..#PROBE, "Start", "google", ..#ORIGIN, owned, .url, .nowOwned, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_app_"|"_..Norm(nowOwned)_"|"_..AppEnabled(), "1|enabled|"_..Norm(owned)_"|1", "the next sign-in enables it")
	Set sc = $ClassMethod(..#PROBE, "Start", "google", ..#ORIGIN, nowOwned, .url, .nowOwned2, .app)
	Do $$$AssertEquals($$$ISOK(sc)_"|"_app_"|"_nowOwned2, "1||"_nowOwned, "a start with the application enabled changes nothing")
}

/// c2: a start with no client registered is an error and enables nothing.
Method TestStartNeedsAClient()
{
	If '..Guard() Quit
	Do ..SetApp(0)
	Set before = ..Snapshot()
	Set sc = $ClassMethod(..#PROBE, "Start", "google", ..#ORIGIN, "client", .url, .nowOwned, .app)
	Do $$$AssertStatusNotOK(sc, "no client: a start is an error")
	Do $$$AssertEquals(..Snapshot()_"|"_..AppEnabled(), before_"|0", "and nothing changes: the web application stays disabled")
}

/// Signed in is a token row of the mailbox with an access token and no error.
Method TestState()
{
	If '..Guard() Quit
	Do $$$AssertStatusOK($ClassMethod(..#PROBE, "State", .signedIn), "State is OK with no row")
	Do $$$AssertEquals(signedIn, 0, "no token row: not signed in")
	Do ..SeedToken("zz-dummy-access", "zz-dummy-refresh", "")
	Do $ClassMethod(..#PROBE, "State", .signedIn)
	Do $$$AssertEquals(signedIn, 1, "an access token and no error: signed in")
	Do ..Wipe()
	Do ..SeedToken("", "zz-dummy-refresh", "access_denied")
	Do $ClassMethod(..#PROBE, "State", .signedIn)
	Do $$$AssertEquals(signedIn, 0, "a row with an error and no access token: not signed in")
	Do ..Wipe()
	Do ..SeedToken("zz-dummy-access", "zz-dummy-refresh", "server_error")
	Do $ClassMethod(..#PROBE, "State", .signedIn)
	Do $$$AssertEquals(signedIn, 0, "a row with an error, whatever else it holds: not signed in")
	Do ..Wipe()
	Do ..SeedToken("", "", "")
	Do $ClassMethod(..#PROBE, "State", .signedIn)
	Do $$$AssertEquals(signedIn, 0, "a pending row with no access token: not signed in")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Text [ 'zz-dummy-'")
	Do rs.%Next()
	Do $$$AssertEquals(rs.%GetData(1), 0, "no token value reached the Interoperability log")
}

/// Start answers IRIS's address of the authorization code flow: below the page's origin, with the state in its query; the token row is pending with a PKCE verifier.
Method TestStartAddress()
{
	If '..Guard() Quit
	Set sc = $ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "zz-dummy-secret", ..#ORIGIN, "", .changed, .owned, .app)
	Set sc = $ClassMethod(..#PROBE, "Start", "google", ..#ORIGIN, owned, .url, .nowOwned, .app)
	Do $$$AssertStatusOK(sc, "Start is OK")
	Do $$$AssertTrue($Match(url, "^"_..#ORIGIN_"/csp/sys/oauth2/OAuth2\.Response\.cls\?auth=1&state=[A-Za-z0-9_-]+$"), "the address is IRIS's response page with auth=1 and a state")
	Do $$$AssertEquals(..PendingRow(), "new|0|1|"_..#ORIGIN_"/ocutalon/#/settings/channels?signin=1|https://mail.google.com/", "the token row is new, holds no access token, has a PKCE verifier, and returns to Settings > Channels")
}

/// c4: the mock's endpoints log a warning each time the class is used with the switch on, and none with it off.
Method TestMockWarns()
{
	If '..Guard() Quit
	Set before = ..WarningCount()
	Set sc = $ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "zz-dummy-secret", ..#ORIGIN, "", .changed, .owned, .app)
	Do $$$AssertEquals(..WarningCount() - before, 0, "with the switch off nothing is logged")
	Do $$$AssertEquals(..ServerEndpoints("https://accounts.google.com"), "https://accounts.google.com/o/oauth2/v2/auth|https://oauth2.googleapis.com/token|", "and the registered endpoints are the https constants")
	Do ..Wipe()
	Set ^||OcuTalonEmailOAuthProbe("env") = "1"
	Set before = ..WarningCount()
	Set sc = $ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "zz-dummy-secret", ..#ORIGIN, "", .changed, .owned, .app)
	Do $$$AssertEquals(..WarningCount() - before, 1, "with the switch on the register logs one warning")
	Do $$$AssertEquals(..ServerEndpoints("http://mock:8080/_mock/oauth/google"), "http://mock:8080/_mock/oauth/google/authorize|http://mock:8080/_mock/oauth/google/token|", "and the registered endpoints are the mock's")
	Set sc = $ClassMethod(..#PROBE, "Start", "google", ..#ORIGIN, owned, .url)
	Do $$$AssertEquals(..WarningCount() - before, 2, "and a start logs one more")
}

/// The comma list with its items in alphabetical order.
ClassMethod Norm(list As %String) As %String
{
	Set all = $ListFromString(list), position = 0
	While $ListNext(all, position, one) {
		Set sorted(one) = ""
	}
	Set out = "", item = ""
	For {
		Set item = $Order(sorted(item))
		Quit:item=""
		Set out = out_$Select(out = "": "", 1: ",")_item
	}
	Quit out
}

/// --- helpers (they work in %SYS, as the product's Sys does not; the throwaway's own objects only) ---

/// The number of warnings in the event log that name the CI-only variable.
ClassMethod WarningCount() As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Type = 3 AND Text [ 'OCUTALON_TEST_OAUTH_MOCK'")
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// 1 or 0: the enabled flag of the web application /csp/sys/oauth2 ("" when it does not exist).
ClassMethod AppEnabled() As %String
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	If '##class(Security.Applications).Exists("/csp/sys/oauth2", .app) Quit ""
	Quit +app.Enabled
}

/// Sets the flag of the web application (a fixture).
ClassMethod SetApp(enabled As %Boolean)
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set props("Enabled") = +enabled
	Do ##class(Security.Applications).Modify("/csp/sys/oauth2", .props)
}

/// The counts the tests compare: "clients|servers|tokens|<clients named OcuTalonMail>|<application disabled>|" (a text that a refused call must leave as it found it).
ClassMethod Snapshot() As %String
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set out = ""
	For table = "OAuth2.Client", "OAuth2.ServerDefinition", "OAuth2.AccessToken" {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_table)
		Do rs.%Next()
		Set out = out_rs.%GetData(1)_"|"
	}
	Set out = out_+##class(OAuth2.Client).Exists("OcuTalonMail")_"|"
	Set out = out_'+..AppEnabled()_"|"
	Quit out
}

/// The fields of the client OcuTalonMail: "type|SSL|redirection endpoint|auth method|scope|ID|enabled|issuer".
ClassMethod ClientFields() As %String
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	If '##class(OAuth2.Client).Exists("OcuTalonMail", .client) Quit ""
	Quit client.ClientType_"|"_client.SSLConfiguration_"|"_client.RedirectionEndpoint.GetServerURL()_"|"_client.Metadata."token_endpoint_auth_method"_"|"_client.DefaultScope_"|"_client.ClientId_"|"_client.Enabled_"|"_$Select($IsObject(client.ServerDefinition): client.ServerDefinition.IssuerEndpoint, 1: "")
}

/// 1 when the client holds the secret (the test compares it in %SYS and prints nothing).
ClassMethod SecretMatches(secret As %String) As %Boolean
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	If '##class(OAuth2.Client).Exists("OcuTalonMail", .client) Quit 0
	Quit (client.ClientSecret = secret)
}

/// 1 when a client of the name exists.
ClassMethod ClientExists(name As %String) As %Boolean
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Quit +##class(OAuth2.Client).Exists(name)
}

/// "authorization endpoint|token endpoint|revocation endpoint" of the server definition of the issuer, "" when there is none.
ClassMethod ServerEndpoints(issuer As %String) As %String
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set server = ##class(OAuth2.ServerDefinition).OpenByIssuer(issuer)
	If '$IsObject(server) Quit ""
	Quit server.Metadata."authorization_endpoint"_"|"_server.Metadata."token_endpoint"_"|"_server.Metadata."revocation_endpoint"
}

/// 1 or 0: whether the issuer has a server definition.
ClassMethod ServerCount(issuer As %String) As %Integer
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Quit +$IsObject(##class(OAuth2.ServerDefinition).OpenByIssuer(issuer))
}

/// A server definition (a fixture that stands for one that is not OcuTalon's).
ClassMethod MakeServer(issuer As %String, authorize As %String, token As %String, revoke As %String)
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set meta = {"issuer": (issuer), "authorization_endpoint": (authorize), "token_endpoint": (token)}
	If revoke '= "" Do meta.%Set("revocation_endpoint", revoke)
	Set sd("Metadata") = meta.%ToJSON(), sd("SSLConfiguration") = "OcuTalonClient"
	Do ##class(OAuth2.ServerDefinition).Create(issuer, .sd)
}

/// A client with its server definition (fixtures that stand for ones that are not OcuTalon's).
ClassMethod MakeClient(name As %String, issuer As %String, clientId As %String)
{
	If '..ServerCount(issuer) Do ..MakeServer(issuer, issuer_"/auth", issuer_"/token", "")
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set cl("ServerDefinition") = issuer, cl("ClientType") = "confidential", cl("SSLConfiguration") = "OcuTalonClient"
	Set cl("RedirectionEndpoint") = "http://127.0.0.1:52773", cl("ClientId") = clientId, cl("ClientSecret") = "zz-foreign-secret", cl("Enabled") = 1
	Set cl("Metadata") = {"token_endpoint_auth_method": "client_secret_post"}.%ToJSON()
	Do ##class(OAuth2.Client).Create(name, .cl)
}

/// A token row of the mailbox (a fixture): the dummy values are the test's own.
ClassMethod SeedToken(access As %String, refresh As %String, error As %String)
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set token = ##class(OAuth2.AccessToken).%New()
	Set token.SessionId = "OcuTalonMail", token.ApplicationName = "OcuTalonMail", token.AccessToken = access, token.RefreshToken = refresh
	If error '= "" Do token.SetError(##class(%OAuth2.Error).%New(error))
	Do token.%Save()
}

/// The number of token rows of the mailbox.
ClassMethod TokenRows() As %Integer
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Quit +##class(OAuth2.AccessToken).SAIndexExists("OcuTalonMail", "OcuTalonMail")
}

/// "stage|has an access token|has a PKCE verifier|return address|scope" of the mailbox's token row.
ClassMethod PendingRow() As %String
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set token = ##class(OAuth2.AccessToken).OpenForSession("OcuTalonMail", "OcuTalonMail")
	If '$IsObject(token) Quit ""
	Quit token.Stage_"|"_(token.AccessToken '= "")_"|"_(token.CodeVerifier '= "")_"|"_token.RedirectURL_"|"_token.Scope
}

/// Removes every OAuth2 object that the tests make: the clients OcuTalonMail and ZzOtherClient, the server definitions of the tests, and the mailbox's token rows.
ClassMethod Wipe()
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	For name = "OcuTalonMail", ..#OTHERNAME {
		If ##class(OAuth2.Client).Exists(name) Do ##class(OAuth2.Client).DeleteId(name)
	}
	For issuer = "https://accounts.google.com", "https://login.microsoftonline.com/common/v2.0", "http://mock:8080/_mock/oauth/google", "http://mock:8080/_mock/oauth/microsoft", ..#OTHERISSUER {
		Do ##class(OAuth2.ServerDefinition).DeleteByIssuer(issuer)
	}
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OAuth2.AccessToken WHERE ApplicationName = 'OcuTalonMail'")
	While rs.%Next() {
		Do ##class(OAuth2.AccessToken).%DeleteId(rs.%Get("ID"))
	}
}

/// c4: the real SwitchOn reads the CI-only variable and nothing else (the probe replaces it everywhere else).
Method TestSwitchOnReadsTheVariable()
{
	Set method = ##class(%Dictionary.MethodDefinition).%OpenId("OcuTalon.Channel.Email.OAuth||SwitchOn")
	Do $$$AssertTrue($IsObject(method), "SwitchOn is a method of the class")
	Set code = $ZConvert($ZStrip(method.Implementation.Read(1000000), "*WC"), "U")
	Do $$$AssertEquals(code, "QUIT..ISON($SYSTEM.UTIL.GETENVIRON(..#TESTVARIABLE))", "SwitchOn is IsOn of the variable's value")
}

/// c1, c7: the real OnlineDemo reads the public online-demo flag.
Method TestOnlineDemoReadsThePublicFlag()
{
	Set was = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
		Do $$$AssertEquals(##class(OcuTalon.Channel.Email.OAuth).OnlineDemo(), 0, "off the online demo")
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Do $$$AssertEquals(##class(OcuTalon.Channel.Email.OAuth).OnlineDemo(), 1, "on the online demo")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", was)
}

/// A removal deletes only the server definition of the client's own issuer: an identical definition of the other provider that no client uses stays.
Method TestRemoveDropsOnlyTheClientsServer()
{
	If '..Guard() Quit
	Set sc = $ClassMethod(..#PROBE, "Register", "google", ..#CLIENTID, "zz-dummy-secret", ..#ORIGIN, "", .changed, .owned, .app)
	Do $$$AssertStatusOK(sc, "a register is OK")
	Do ..MakeServer("https://login.microsoftonline.com/common/v2.0", "https://login.microsoftonline.com/common/oauth2/v2.0/authorize", "https://login.microsoftonline.com/common/oauth2/v2.0/token", "")
	Set sc = $ClassMethod(..#PROBE, "Remove", owned, .nowOwned, .app)
	Do $$$AssertStatusOK(sc, "the removal is OK")
	Do $$$AssertEquals(..ServerCount("https://accounts.google.com")_"|"_..ServerCount("https://login.microsoftonline.com/common/v2.0"), "0|1", "the client's own server definition went and the other provider's definition stayed")
}

}
