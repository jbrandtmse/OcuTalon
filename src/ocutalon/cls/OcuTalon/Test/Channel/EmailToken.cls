/// Tests of the OAuth2 call-back handler of the mail items, OcuTalon.Channel.Email.Token (Story 21.8; AD-19, AD-25), without a registered client: nothing is created
/// in %SYS, and the public setting onlineDemo is put back. The cases that need IRIS's real client and tokens are Test.Channel.EmailLive (TestOAuth...).
///   - TestSession: the default session is OcuTalonMail and equals Channel.Email.OAuth's SESSION;
///   - TestExtendsTheHandler: the class extends Ens.Util.OAuth2.Handler, which is what the item setting OAuth2CallBackHandler requires;
///   - TestNotAuthorizedRaisesNothing: each of the four OnNotAuthorizedGrant methods is the class's own, answers the one fixed error status with no address, token or
///     name in it, and leaves no Workflow request message and no OAuth2 token row;
///   - TestNoTokenRowIsAnError: for an application with no token row OnGetAccessToken answers an error, not authorized and no token, asks for no authorization address
///     and creates no token row;
///   - TestOnlineDemoRefusesBeforeIris: with the online demo on, OnGetAccessToken answers the error with no call into IRIS's flow; with it off the same call goes
///     into it;
///   - TestCodeNamesNoClientClassAndLogsNothing: no method names the OAuth2 client class, the OAuth2 objects or the web application (the one-caller rule of Channel.Email.OAuth),
///     and none logs, traces or stores anything.
Class OcuTalon.Test.Channel.EmailToken Extends %UnitTest.TestCase
{

Parameter TOKEN = "OcuTalon.Channel.Email.Token";

Parameter PROBE = "OcuTalon.Test.Channel.EmailTokenProbe";

/// An application that no client of the stack has.
Parameter APPLICATION = "zzNoSuchMailClient";

Property OnlineWas As %String [ Private ];

Method OnBeforeAllTests() As %Status
{
	Set ..OnlineWas = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^||OcuTalonEmailTokenProbe
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^||OcuTalonEmailTokenProbe
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..OnlineWas)
	Quit $$$OK
}

/// The session id of the mailbox's token row.
Method TestSession()
{
	Do $$$AssertEquals($ClassMethod(..#TOKEN, "GetDefaultSessionIdForRunningHostItem"), "OcuTalonMail", "the default session is OcuTalonMail")
	Do $$$AssertEquals($ClassMethod(..#TOKEN, "GetDefaultSessionIdForRunningHostItem"), $Parameter("OcuTalon.Channel.Email.OAuth", "SESSION"), "and it equals the session that Channel.Email.OAuth registers")
	Do $$$AssertEquals($Parameter(..#TOKEN, "SESSION"), $Parameter("OcuTalon.Channel.Email.OAuth", "SESSION"), "as does the class's own constant")
}

/// The handler named by the item setting must extend IRIS's.
Method TestExtendsTheHandler()
{
	Do $$$AssertEquals($ClassMethod(..#TOKEN, "%Extends", "Ens.Util.OAuth2.Handler"), 1, "the class extends Ens.Util.OAuth2.Handler")
}

/// Each OnNotAuthorizedGrant method is the class's own, answers the one fixed error and raises no request.
Method TestNotAuthorizedRaisesNothing()
{
	Set requests = ..Requests(), tokens = ..TokenRows()
	Set first = "", same = 1
	For method = "OnNotAuthorizedGrantAuthCode", "OnNotAuthorizedGrantClientCredentials", "OnNotAuthorizedGrantJWTAuth", "OnNotAuthorizedGrantPassword" {
		Set origin = ##class(%Dictionary.CompiledMethod).%OpenId(..#TOKEN_"||"_method).Origin
		Do $$$AssertEquals(origin, ..#TOKEN, method_" is defined by the class itself, not inherited from IRIS")
		Set sc = $ClassMethod(..#TOKEN, method, "", ..#APPLICATION, "OcuTalonMail", "zz", "", "", "")
		Do $$$AssertStatusNotOK(sc, method_" answers an error")
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertTrue((text '[ ..#APPLICATION) && (text '[ "OcuTalonMail") && (text '[ "zz") && (text '[ "http"), method_": the status holds no name, resource or address")
		If first = "" Set first = text
		If text '= first Set same = 0
	}
	Do $$$AssertTrue((first '= "") && same, "and it is the same fixed status each time")
	Do $$$AssertEquals(..Requests(), requests, "no Workflow request message was made")
	Do $$$AssertEquals(..TokenRows(), tokens, "and no OAuth2 token row")
}

/// With no token row there is nothing to authorize; the handler does not go and get a token.
Method TestNoTokenRowIsAnError()
{
	Set requests = ..Requests(), tokens = ..TokenRows()
	Set scope = "", props = "", specific = ""
	Set sc = $ClassMethod(..#PROBE, "OnGetAccessToken", "", "AuthCode", ..#APPLICATION, "OcuTalonMail", "zzuser", .scope, .props, .specific, .authorized, .token, .retry)
	Do $$$AssertStatusNotOK(sc, "an application with no token row answers an error")
	Do $$$AssertEquals(authorized_"|"_token, "0|", "not authorized, and no token")
	Do $$$AssertEquals($Get(^||OcuTalonEmailTokenProbe("authCode")), 1, "the fixed refusal was reached once: IRIS's flow ran and found nothing")
	Do $$$AssertEquals(..Requests()_"|"_..TokenRows(), requests_"|"_tokens, "no Workflow request message and no token row appeared")
}

/// The online demo answers before IRIS is asked.
Method TestOnlineDemoRefusesBeforeIris()
{
	Set scope = "", props = "", specific = ""
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set sc = $ClassMethod(..#PROBE, "OnGetAccessToken", "", "AuthCode", ..#APPLICATION, "OcuTalonMail", "zzuser", .scope, .props, .specific, .authorized, .token, .retry)
	Do $$$AssertStatusNotOK(sc, "on the online demo the handler answers an error")
	Do $$$AssertEquals(authorized_"|"_token_"|"_retry, "0||0", "not authorized, no token, no retry")
	Do $$$AssertEquals(+$Get(^||OcuTalonEmailTokenProbe("authCode")), 0, "and IRIS's flow was not entered")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Set sc = $ClassMethod(..#PROBE, "OnGetAccessToken", "", "AuthCode", ..#APPLICATION, "OcuTalonMail", "zzuser", .scope, .props, .specific, .authorized, .token, .retry)
	Do $$$AssertStatusNotOK(sc, "control: off the online demo, with no token row, it is an error too")
	Do $$$AssertEquals(+$Get(^||OcuTalonEmailTokenProbe("authCode")), 1, "but this time IRIS's flow was entered")
}

/// The class never names the OAuth2 objects, and logs, traces and stores nothing.
Method TestCodeNamesNoClientClassAndLogsNothing()
{
	Set definition = ##class(%Dictionary.ClassDefinition).%OpenId(..#TOKEN)
	Do $$$AssertTrue($IsObject(definition) && (definition.Methods.Count() >= 6), "the class's methods were read")
	Set named = 0, logs = 0
	For i = 1:1:definition.Methods.Count() {
		Set code = $ZConvert(definition.Methods.GetAt(i).Implementation.Read(1000000), "U")
		If (code [ "CHANNEL.EMAIL.OAUTH") || (code [ "OCUTALON_TEST_OAUTH_MOCK") || (code [ "/CSP/SYS/OAUTH2") || (code [ "OAUTH2.CLIENT") || (code [ "OAUTH2.SERVERDEFINITION") Set named = named + 1
		If (code [ "$$$LOG") || (code [ "$$$TRACE") || (code [ "$$$CATTRACE") || (code [ "$$$SYSLOG") || (code [ "^") || (code [ "SAVE(") Set logs = logs + 1
	}
	Do $$$AssertEquals(named, 0, "no method names the OAuth2 client class, the server definition, the web application or the mock switch")
	Do $$$AssertEquals(logs, 0, "and none logs, traces, writes a global or saves a row")
}

/// The number of messages whose body class is the Workflow request that IRIS's default handler raises for an authorization.
ClassMethod Requests() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName [ 'OAuth2Request'")
	If result.%SQLCODE < 0 Quit -1
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of OAuth2 token rows, read in %SYS.
ClassMethod TokenRows() As %Integer [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OAuth2.AccessToken")
	If result.%SQLCODE < 0 Quit -1
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
