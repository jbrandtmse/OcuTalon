Include Ensemble

/// The mail OAuth2 client (Story 21.3; AD-1, AD-3, AD-19, AD-25): registers, enables for sign-in, reads and removes IRIS's OAuth2 client OcuTalonMail,
/// the one place where OcuTalon touches IRIS's %SYS OAuth2 objects. The client secret lives only in the client's ClientSecret; the tokens live only in
/// IRIS's OAuth2.AccessToken (application and session OcuTalonMail), and this class never reads, copies, logs or returns a token value.
/// The public methods are class methods of SettingsOps' production job (the item SettingsOps), which keeps email.oauthOwned, the comma list of what
/// OcuTalon created or enabled: client, server (the OAuth2.ServerDefinition of the provider) and app (the enabled flag of the web application
/// /csp/sys/oauth2). This class writes no product key and no audit entry; it answers what it changed and SettingsOps records it.
///   - Register creates or updates the confidential client for a provider (client_secret_post, the client SSL configuration OcuTalonClient, the redirection
///     endpoint of the page's origin, the provider's minimum scopes) and the server definition with fixed endpoints and no discovery. A server definition
///     is reused only when its endpoints equal the provider's constants and it names no revocation endpoint (IRIS would call it when deleting a token); one
///     with other endpoints, or a client OcuTalonMail that owned does not name, is foreign: nothing is changed and the status says so. An empty secret keeps
///     the stored one. A client ID that changes deletes the client's tokens; nothing else does.
///   - Remove deletes the client and its tokens, the server definition of the client's issuer only when owned names server, it is OcuTalon's and no client uses it, and disables
///     the web application only when owned names app and no OAuth2 client remains.
///   - Start enables the web application when it is disabled (an explicit sign-in, the only time besides Register) and asks IRIS for the authorization
///     address, which redirects to the provider's consent page with PKCE (S256), the provider's scopes and a state.
///   - State says whether the token row of the mailbox holds an access token and no error. It makes no outward call.
/// The web application /csp/sys/oauth2 is enabled only by a first Register (IRIS enables it when it saves the new client) and by Start. A re-save of a registered
/// client, a changed provider included, leaves a disabled application disabled.
/// Sys is the one method that switches namespace (to %SYS) and the one that changes OcuTalon's objects there; the one other call that reaches %SYS is Start's
/// request to IRIS's own authorization API, which IRIS answers by writing the pending token row in its token store, after Sys enabled the sign-in. Sys refuses unless it is called in the production job of
/// SettingsOps (InJob), and on the online demo. Only IRIS's own classes and this class's constants exist in %SYS, so everything else comes in through its input. Provider endpoints are https constants (Endpoints); the CI-only environment variable OCUTALON_TEST_OAUTH_MOCK
/// set to exactly 1 (SwitchOn) swaps them for the CI mock's plain HTTP endpoints and logs a warning each time it is used; no setting, row, route or form value
/// can switch it on.
Class OcuTalon.Channel.Email.OAuth Extends %RegisteredObject
{

/// The application name and the session id of the one mailbox's client and tokens.
Parameter APPLICATION = "OcuTalonMail";

Parameter SESSION = "OcuTalonMail";

/// The production item whose job may call Sys.
Parameter JOBITEM = "SettingsOps";

/// The web application of IRIS's OAuth2 redirection endpoint.
Parameter APPPATH = "/csp/sys/oauth2";

/// The CI-only environment variable that selects the mock's endpoints, and the mock's base address.
Parameter TESTVARIABLE = "OCUTALON_TEST_OAUTH_MOCK";

Parameter TESTBASE = "http://mock:8080/_mock/oauth/";

/// The Description of the client.
Parameter DESCRIPTION = "Written by OcuTalon for the mailbox sign-in; do not edit.";

/// The fixed endpoints of Google (https only; no discovery). GOOGLEREVOKE is not stored in the server definition: IRIS would call it when it deletes a token.
Parameter GOOGLEISSUER = "https://accounts.google.com";

Parameter GOOGLEAUTHORIZE = "https://accounts.google.com/o/oauth2/v2/auth";

Parameter GOOGLETOKEN = "https://oauth2.googleapis.com/token";

Parameter GOOGLEREVOKE = "https://oauth2.googleapis.com/revoke";

/// The minimum scope for POP3 and SMTP, and the extra authorization parameters (name=value, comma-separated).
Parameter GOOGLESCOPE = "https://mail.google.com/";

Parameter GOOGLEPROPS = "access_type=offline,prompt=consent";

/// The fixed endpoints of Microsoft 365 (tenant common; https only; no discovery; no revocation endpoint).
Parameter MICROSOFTISSUER = "https://login.microsoftonline.com/common/v2.0";

Parameter MICROSOFTAUTHORIZE = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize";

Parameter MICROSOFTTOKEN = "https://login.microsoftonline.com/common/oauth2/v2.0/token";

Parameter MICROSOFTSCOPE = "https://outlook.office.com/POP.AccessAsUser.All https://outlook.office.com/SMTP.Send offline_access";

Parameter MICROSOFTPROPS = "";

/// The return address of a sign-in, below the page's origin.
Parameter RETURNPATH = "/ocutalon/#/settings/channels?signin=1";

/// The plain text of the refusals and failures: they say nothing about why.
Parameter MESSAGEREFUSED = "The mail sign-in client can't be changed here.";

Parameter MESSAGEFOREIGN = "IRIS already has an OAuth2 object that OcuTalon did not create. Nothing was changed.";

Parameter MESSAGEUNKNOWN = "The sign-in provider is not one that OcuTalon knows.";

Parameter MESSAGENOTREGISTERED = "The mail sign-in client is not registered.";

/// The client SSL/TLS configuration that the installer makes (Install.Step.SSL) and that the client and the server definition use: the TLS connection to the
/// provider's endpoints checks the provider's certificate and host name. Sys cannot ask for it, because OcuTalon's classes do not exist in %SYS.
ClassMethod Client() As %String
{
	Quit ##class(OcuTalon.Install.Step.SSL).#NAME
}

/// 1 when the CI-only environment variable is exactly 1 (IsOn). A test subclass overrides it to stand in for a job that does not have the variable.
ClassMethod SwitchOn() As %Boolean
{
	Quit ..IsOn($SYSTEM.Util.GetEnviron(..#TESTVARIABLE))
}

/// 1 only when the value of the variable is exactly 1.
ClassMethod IsOn(value As %String) As %Boolean
{
	Quit ($Get(value) = "1")
}

/// 1 when this process is the production job of SettingsOps. A test subclass overrides it.
ClassMethod InJob() As %Boolean
{
	Quit ($$$JobConfigName = ..#JOBITEM)
}

/// 1 when the online-demo flag is set. A test subclass overrides it.
ClassMethod OnlineDemo() As %Boolean
{
	Quit (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
}

/// The name of a provider, "Google" or "Microsoft 365", and "" for any other.
ClassMethod ProviderName(provider As %String) As %String
{
	Quit $Case($Get(provider), "google": "Google", "microsoft": "Microsoft 365", : "")
}

/// The endpoints of the provider (google or microsoft) in ep: issuer, authorize, token, scope, props and name; 1 for a known provider, else 0. They are the
/// https constants; with the CI-only switch on (SwitchOn) the issuer, authorize and token are the mock's plain HTTP addresses instead.
ClassMethod Endpoints(provider As %String, Output ep) As %Boolean
{
	Quit ..Known($Get(provider), ..SwitchOn(), .ep)
}

/// Endpoints' work for the real constants (mock 0) or the mock's (mock 1).
ClassMethod Known(provider As %String, mock As %Boolean, Output ep) As %Boolean [ Private ]
{
	Kill ep
	If provider = "google" {
		Set ep("issuer") = ..#GOOGLEISSUER, ep("authorize") = ..#GOOGLEAUTHORIZE, ep("token") = ..#GOOGLETOKEN, ep("scope") = ..#GOOGLESCOPE, ep("props") = ..#GOOGLEPROPS
	} ElseIf provider = "microsoft" {
		Set ep("issuer") = ..#MICROSOFTISSUER, ep("authorize") = ..#MICROSOFTAUTHORIZE, ep("token") = ..#MICROSOFTTOKEN, ep("scope") = ..#MICROSOFTSCOPE, ep("props") = ..#MICROSOFTPROPS
	} Else {
		Quit 0
	}
	Set ep("name") = ..ProviderName(provider)
	If mock {
		Set base = ..#TESTBASE_provider
		Set ep("issuer") = base, ep("authorize") = base_"/authorize", ep("token") = base_"/token"
	}
	Quit 1
}

/// Logs the warning that the mock's plain HTTP endpoints are in use. It names no secret.
ClassMethod WarnMock() [ Private ]
{
	$$$LOGWARNING("The mail OAuth2 client uses the CI mock's plain HTTP endpoints ("_..#TESTVARIABLE_" is 1)")
}

/// Registers the client for the provider (see the class description): clientId, secret ("" keeps the stored one) and origin (the page's http or https
/// origin, which becomes the redirection endpoint). owned is the comma list in email.oauthOwned; nowOwned is the list after the call. changed is 1 when the
/// client was created or its provider, client ID, secret or redirection endpoint changed. app is "enabled" when this call enabled the web application, else "".
ClassMethod Register(provider As %String, clientId As %String, secret As %String, origin As %String, owned As %String, Output changed As %Boolean, Output nowOwned As %String, Output app As %String) As %Status
{
	Set changed = 0, nowOwned = $Get(owned), app = ""
	If '..Endpoints(provider, .ep) Quit $SYSTEM.Status.Error(5001, ..#MESSAGEUNKNOWN)
	If ..SwitchOn() Do ..WarnMock()
	Merge in = ep
	Set in("clientId") = clientId, in("secret") = $Get(secret), in("origin") = origin, in("owned") = $Get(owned), in("ssl") = ..Client()
	Set sc = ..Sys("register", .in, .out)
	Kill in
	If $$$ISOK(sc) Set changed = out("changed"), nowOwned = out("owned"), app = out("app")
	Quit sc
}

/// Removes the client (see the class description). nowOwned is "" afterwards, or "app" when the web application OcuTalon enabled stays enabled for another OAuth2 client; app is "disabled" when this call disabled the web application, else "".
ClassMethod Remove(owned As %String, Output nowOwned As %String, Output app As %String) As %Status
{
	Set nowOwned = $Get(owned), app = ""
	Set in("owned") = $Get(owned)
	Set sc = ..Sys("remove", .in, .out)
	If $$$ISOK(sc) Set nowOwned = out("owned"), app = out("app")
	Quit sc
}

/// Whether the mailbox holds tokens: signedIn is 1 for a token row with an access token and no error. No token value is returned and no call goes out.
ClassMethod State(Output signedIn As %Boolean) As %Status
{
	Set signedIn = 0
	Set sc = ..Sys("state", .in, .out)
	If $$$ISOK(sc) Set signedIn = out("signedIn")
	Quit sc
}

/// Starts a sign-in: enables the web application when it is disabled (app is "enabled" then, and nowOwned names app), then answers in url the address that
/// IRIS gives for the authorization code flow, with the return address origin and RETURNPATH. A client that is not registered is an error and enables nothing.
ClassMethod Start(provider As %String, origin As %String, owned As %String, Output url As %String, Output nowOwned As %String, Output app As %String) As %Status
{
	Set url = "", nowOwned = $Get(owned), app = ""
	If '..Endpoints(provider, .ep) Quit $SYSTEM.Status.Error(5001, ..#MESSAGEUNKNOWN)
	If ..SwitchOn() Do ..WarnMock()
	Set in("owned") = $Get(owned)
	Set sc = ..Sys("enable", .in, .out)
	If $$$ISERR(sc) Quit sc
	Set nowOwned = out("owned"), app = out("app")
	For i = 1:1:$Length(ep("props"), ",") {
		Set pair = $Piece(ep("props"), ",", i)
		If pair '= "" Set props($Piece(pair, "=", 1)) = $Piece(pair, "=", 2, *)
	}
	Set url = ##class(%SYS.OAuth2.Authorization).GetAuthorizationCodeEndpoint(..#APPLICATION, ep("scope"), origin_..#RETURNPATH, .props, .authorized, .sc, "query", ..#SESSION)
	If $$$ISERR(sc) Set url = ""
	Quit sc
}

/// The one method that works in %SYS (see the class description). action is register, remove, enable or state; in holds its input and out its answer:
///   - register: in(issuer, authorize, token, scope, clientId, secret, origin, owned, ssl); out(changed, owned, app)
///   - remove: in(owned); out(owned, app)
///   - enable: in(owned); out(owned, app)
///   - state: out(signedIn)
ClassMethod Sys(action As %String, ByRef in, Output out) As %Status [ Private ]
{
	Kill out
	If '..InJob() || ..OnlineDemo() Quit $SYSTEM.Status.Error(5001, ..#MESSAGEREFUSED)
	Set sc = $$$OK
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Try {
		If action = "register" {
			Set sc = ..SysRegister(.in, .out)
		} ElseIf action = "remove" {
			Set sc = ..SysRemove(.in, .out)
		} ElseIf action = "enable" {
			Set sc = ..SysEnable(.in, .out)
		} ElseIf action = "state" {
			Set sc = ..SysState(.out)
		} Else {
			Set sc = $SYSTEM.Status.Error(5001, ..#MESSAGEREFUSED)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// Sys register, in %SYS. Every check that can refuse runs before the first write; the writes are one transaction.
ClassMethod SysRegister(ByRef in, Output out) As %Status [ Private ]
{
	Set owned = in("owned")
	Set out("changed") = 0, out("owned") = owned, out("app") = ""
	Set appWas = ..AppEnabled()
	Set server = ##class(OAuth2.ServerDefinition).OpenByIssuer(in("issuer"), .sc)
	If $$$ISERR(sc) Quit sc
	If $IsObject(server) && '..SameServer(server, in("authorize"), in("token")) Quit $SYSTEM.Status.Error(5001, ..#MESSAGEFOREIGN)
	Set clientExists = ##class(OAuth2.Client).Exists(..#APPLICATION, .client)
	If clientExists && '..Has(owned, "client") Quit $SYSTEM.Status.Error(5001, ..#MESSAGEFOREIGN)
	If clientExists && '$IsObject(client.ServerDefinition) Quit $SYSTEM.Status.Error(5001, ..#MESSAGEFOREIGN)
	Set hadClient = clientExists
	Set sameIssuer = clientExists && (client.ServerDefinition.IssuerEndpoint = in("issuer"))
	If 'sameIssuer && (in("secret") = "") Quit $SYSTEM.Status.Error(5001, ..#MESSAGENOTREGISTERED)
	Set sc = $$$OK
	Set level = $TLevel
	TSTART
	Try {
		If clientExists && 'sameIssuer {
			Set sc = ..DropClient(owned, .owned)
			If $$$ISERR(sc) $$$ThrowStatus(sc)
			Set clientExists = 0, out("changed") = 1
			Set server = ##class(OAuth2.ServerDefinition).OpenByIssuer(in("issuer"), .sc)
			If $$$ISERR(sc) $$$ThrowStatus(sc)
		}
		If '$IsObject(server) {
			Set sd("Metadata") = {"issuer": (in("issuer")), "authorization_endpoint": (in("authorize")), "token_endpoint": (in("token"))}.%ToJSON()
			Set sd("SSLConfiguration") = in("ssl")
			Set sc = ##class(OAuth2.ServerDefinition).Create(in("issuer"), .sd)
			If $$$ISERR(sc) $$$ThrowStatus(sc)
			Set owned = ..Add(owned, "server")
		}
		If 'clientExists {
			Do ..ClientProperties(.in, .cl)
			Set sc = ##class(OAuth2.Client).Create(..#APPLICATION, .cl)
			If $$$ISERR(sc) $$$ThrowStatus(sc)
			Set owned = ..Add(owned, "client"), out("changed") = 1
		} Else {
			Do ..ClientProperties(.in, .cl)
			Kill mod
			If client.ClientId '= in("clientId") Set mod("ClientId") = in("clientId"), idChanged = 1
			If (in("secret") '= "") && (client.ClientSecret '= in("secret")) Set mod("ClientSecret") = in("secret")
			If client.RedirectionEndpoint.GetServerURL() '= in("origin") Set mod("RedirectionEndpoint") = in("origin")
			If client.SSLConfiguration '= cl("SSLConfiguration") Set mod("SSLConfiguration") = cl("SSLConfiguration")
			If client.ClientType '= "confidential" Set mod("ClientType") = "confidential"
			If client.DefaultScope '= ##class(%OAuth2.Utils).NormalizeScope(in("scope")) Set mod("DefaultScope") = in("scope")
			If client.Metadata."token_endpoint_auth_method" '= "client_secret_post" Set mod("Metadata") = cl("Metadata")
			If $Data(mod) {
				If $Get(idChanged) {
					Set sc = client.DeleteTokens()
					If $$$ISERR(sc) $$$ThrowStatus(sc)
				}
				Set sc = ##class(OAuth2.Client).Modify(..#APPLICATION, .mod)
				If $$$ISERR(sc) $$$ThrowStatus(sc)
				Set out("changed") = 1
			}
		}
		If (appWas '= 1) && (..AppEnabled() = 1) {
			If (appWas = 0) && hadClient {
				Set sc = ..SetApp(0)
				If $$$ISERR(sc) $$$ThrowStatus(sc)
			} Else {
				Set out("app") = "enabled", owned = ..Add(owned, "app")
			}
		}
		TCOMMIT
	} Catch exception {
		Set sc = exception.AsStatus()
		If $TLevel > level TROLLBACK 1
	}
	If $$$ISOK(sc) Set out("owned") = owned
	Quit sc
}

/// The properties of the client for ClientProperties: server, type, SSL configuration, redirection endpoint, ID, secret, scope, description and the
/// token endpoint authentication method client_secret_post.
ClassMethod ClientProperties(ByRef in, Output cl) [ Private ]
{
	Kill cl
	Set cl("ServerDefinition") = in("issuer"), cl("ClientType") = "confidential", cl("SSLConfiguration") = in("ssl")
	Set cl("RedirectionEndpoint") = in("origin"), cl("ClientId") = in("clientId"), cl("DefaultScope") = in("scope"), cl("Enabled") = 1
	Set cl("Description") = ..#DESCRIPTION
	Set cl("Metadata") = {"token_endpoint_auth_method": "client_secret_post"}.%ToJSON()
	If in("secret") '= "" Set cl("ClientSecret") = in("secret")
}

/// Deletes the client and its tokens, and OcuTalon's server definition when owned names it and no client uses it; newOwned is owned without what went.
ClassMethod DropClient(owned As %String, Output newOwned As %String) As %Status [ Private ]
{
	Set newOwned = owned
	Set issuer = ..ClientIssuer()
	Set sc = ##class(OAuth2.Client).DeleteId(..#APPLICATION)
	If $$$ISERR(sc) Quit sc
	Set newOwned = ..Drop(newOwned, "client")
	If ..Has(owned, "server") {
		Set sc = ..DropServers(.dropped, issuer)
		If $$$ISOK(sc) && dropped Set newOwned = ..Drop(newOwned, "server")
	}
	Quit sc
}

/// The issuer of the server definition the client OcuTalonMail uses, "" when there is no such client.
ClassMethod ClientIssuer() As %String [ Private ]
{
	If '##class(OAuth2.Client).Exists(..#APPLICATION, .client) Quit ""
	Quit $Select($IsObject(client.ServerDefinition): client.ServerDefinition.IssuerEndpoint, 1: "")
}

/// Deletes the OAuth2.ServerDefinition of issuer when it has OcuTalon's endpoints and no client; with no issuer, every definition with OcuTalon's endpoints
/// and no client. dropped is 1 when one went.
ClassMethod DropServers(Output dropped As %Boolean, issuer As %String = "") As %Status [ Private ]
{
	Set dropped = 0, sc = $$$OK
	For mock = 0, 1 {
		For provider = "google", "microsoft" {
			If '..Known(provider, mock, .ep) Continue
			If (issuer '= "") && (ep("issuer") '= issuer) Continue
			Set server = ##class(OAuth2.ServerDefinition).OpenByIssuer(ep("issuer"), .sc)
			If $$$ISERR(sc) Quit
			If '$IsObject(server) || '..SameServer(server, ep("authorize"), ep("token")) || (server.ClientCount() > 0) Continue
			Set sc = ##class(OAuth2.ServerDefinition).DeleteId(server.%Id())
			If $$$ISERR(sc) Quit
			Set dropped = 1
		}
		If $$$ISERR(sc) Quit
	}
	Quit sc
}

/// Sys remove, in %SYS.
ClassMethod SysRemove(ByRef in, Output out) As %Status [ Private ]
{
	Set owned = in("owned")
	Set out("owned") = owned, out("app") = ""
	Set clientExists = ##class(OAuth2.Client).Exists(..#APPLICATION)
	If clientExists && '..Has(owned, "client") Quit $SYSTEM.Status.Error(5001, ..#MESSAGEFOREIGN)
	Set issuer = ..ClientIssuer()
	Set sc = $$$OK
	Set level = $TLevel
	TSTART
	Try {
		If clientExists {
			Set sc = ##class(OAuth2.Client).DeleteId(..#APPLICATION)
			If $$$ISERR(sc) $$$ThrowStatus(sc)
		}
		If ..Has(owned, "server") {
			Set sc = ..DropServers(, issuer)
			If $$$ISERR(sc) $$$ThrowStatus(sc)
		}
		TCOMMIT
	} Catch exception {
		Set sc = exception.AsStatus()
		If $TLevel > level TROLLBACK 1
	}
	If $$$ISERR(sc) Quit sc
	If ..Has(owned, "app") && (..AppEnabled() = 1) && (..ClientTotal() = 0) {
		Set sc = ..SetApp(0)
		If $$$ISERR(sc) Quit sc
		Set out("app") = "disabled"
	}
	Set out("owned") = $Select(..Has(owned, "app") && (..AppEnabled() = 1): "app", 1: "")
	Quit sc
}

/// Sys enable, in %SYS: the web application is enabled when it is disabled; the client must be registered and OcuTalon's.
ClassMethod SysEnable(ByRef in, Output out) As %Status [ Private ]
{
	Set owned = in("owned")
	Set out("owned") = owned, out("app") = ""
	If '##class(OAuth2.Client).Exists(..#APPLICATION) Quit $SYSTEM.Status.Error(5001, ..#MESSAGENOTREGISTERED)
	If '..Has(owned, "client") Quit $SYSTEM.Status.Error(5001, ..#MESSAGEFOREIGN)
	If ..AppEnabled() '= 1 {
		Set sc = ..SetApp(1)
		If $$$ISERR(sc) Quit sc
		Set out("app") = "enabled", out("owned") = ..Add(owned, "app")
	}
	Quit $$$OK
}

/// Sys state, in %SYS: signedIn is 1 for a token row of the mailbox with an access token and no error.
ClassMethod SysState(Output out) As %Status [ Private ]
{
	Set out("signedIn") = 0
	Set token = ##class(OAuth2.AccessToken).OpenForSession(..#APPLICATION, ..#SESSION, .sc)
	If $$$ISERR(sc) Quit sc
	If $IsObject(token) Set out("signedIn") = (token.AccessToken '= "") && 'token.IsError()
	Quit $$$OK
}

/// 1 when the server definition has exactly these endpoints and names no revocation endpoint.
ClassMethod SameServer(server As %RegisteredObject, authorize As %String, token As %String) As %Boolean [ Private ]
{
	Set metadata = server.Metadata
	Quit $IsObject(metadata) && (metadata."authorization_endpoint" = authorize) && (metadata."token_endpoint" = token) && (metadata."revocation_endpoint" = "")
}

/// The enabled flag of the web application: 1, 0, or "" when it does not exist.
ClassMethod AppEnabled() As %String [ Private ]
{
	If '##class(Security.Applications).Exists(..#APPPATH, .app) Quit ""
	Quit +app.Enabled
}

/// Sets the enabled flag of the web application; a web application that does not exist is not created (S1 sets the flag only), so enabling it is an error.
ClassMethod SetApp(enabled As %Boolean) As %Status [ Private ]
{
	If '##class(Security.Applications).Exists(..#APPPATH) {
		If 'enabled Quit $$$OK
		Quit $SYSTEM.Status.Error(5001, ..#MESSAGEREFUSED)
	}
	Set props("Enabled") = +enabled
	Quit ##class(Security.Applications).Modify(..#APPPATH, .props)
}

/// The number of OAuth2 clients; -1 when it cannot be read, so that a removal keeps the web application (and the ownership of its enable) rather than disable it for others.
ClassMethod ClientTotal() As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OAuth2.Client")
	If rs.%SQLCODE < 0 Quit -1
	If 'rs.%Next() Quit 0
	Quit +rs.%GetData(1)
}

/// 1 when the comma list names the item.
ClassMethod Has(list As %String, item As %String) As %Boolean [ Private ]
{
	Quit ''$ListFind($ListFromString(list), item)
}

/// The comma list with the item added (once).
ClassMethod Add(list As %String, item As %String) As %String [ Private ]
{
	If ..Has(list, item) Quit list
	Quit $Select(list = "": item, 1: list_","_item)
}

/// The comma list without the item.
ClassMethod Drop(list As %String, item As %String) As %String [ Private ]
{
	Set out = "", all = $ListFromString(list)
	Set position = 0
	While $ListNext(all, position, one) {
		If one '= item Set out = $Select(out = "": one, 1: out_","_one)
	}
	Quit out
}

}
