/// The OAuth2 call-back handler of EmailIn and EmailOut (Story 21.8; AD-19, AD-25): the class that SettingsOps names in the System Default Settings row
/// OAuth2CallBackHandler of both items when the mailbox signs in with Google or Microsoft 365. It extends IRIS's Ens.Util.OAuth2.Handler, whose
/// OnGetAccessToken asks %SYS.OAuth2.AccessToken.IsAuthorized for the access token of the client OcuTalonMail (IRIS renews an expired token itself, over
/// the client's fixed token endpoint) and hands it to the adapter for one XOAUTH2 login.
///   - The session is SESSION, because the item settings cannot name one (OAuth2SessionId is not a setting of the items): the token row is the one that
///     Channel.Email.OAuth registered and the admin's consent filled. SESSION equals OAuth.#SESSION; this class does not name that class, because
///     Channel.Email.OAuth has SettingsOps as its only caller.
///   - On the online demo (Data.Setting onlineDemo is 1) OnGetAccessToken answers an error and makes no call to IRIS, so no token is read.
///   - A token that cannot be had is never fetched another way: every OnNotAuthorizedGrant method answers one fixed error and calls nothing, so IRIS
///     raises no Workflow request, builds no authorization address and posts no token request. The admin signs in again in Settings.
/// The access token goes only into the adapter's memory for one login. This class logs nothing, keeps nothing and puts no token in a status.
Class OcuTalon.Channel.Email.Token Extends Ens.Util.OAuth2.Handler
{

/// The session id of the mailbox's token row.
Parameter SESSION = "OcuTalonMail";

/// The setting that is 1 on the online demo (as Channel.Email.Out reads it).
Parameter DEMOKEY = "onlineDemo";

/// The session id for the running item.
ClassMethod GetDefaultSessionIdForRunningHostItem() As %String
{
	Quit ..#SESSION
}

/// IRIS's OnGetAccessToken (the same arguments), except that the online demo answers an error before any call to IRIS.
ClassMethod OnGetAccessToken(pCallerInstance As %RegisteredObject = "", pOAuth2GrantType As %String, pOAuth2ApplicationName As %String = "", pOAuth2SessionId As %String, pOAuth2Resource As %String, ByRef pOAuth2Scope As %String, ByRef pOAuth2AuthProperties As %String, ByRef pGrantTypeSpecific As %DynamicObject, Output pOAuth2IsAuthorized As %Boolean = 0, Output pOAuth2AccessToken As %String = "", Output pOAuth2HostShouldRetry As %Boolean = 0) As %Status
{
	If ##class(OcuTalon.Data.Setting).Get(..#DEMOKEY) = 1 {
		Set pOAuth2IsAuthorized = 0, pOAuth2AccessToken = "", pOAuth2HostShouldRetry = 0
		Quit ..NotAvailable()
	}
	Quit ##super(pCallerInstance, pOAuth2GrantType, pOAuth2ApplicationName, pOAuth2SessionId, pOAuth2Resource, .pOAuth2Scope, .pOAuth2AuthProperties, .pGrantTypeSpecific, .pOAuth2IsAuthorized, .pOAuth2AccessToken, .pOAuth2HostShouldRetry)
}

/// The one error status of every refusal here; it holds no token, address or name.
ClassMethod NotAvailable() As %Status [ Private ]
{
	Quit $$$ERROR($$$GeneralError, "No mail access token is available.")
}

ClassMethod OnNotAuthorizedGrantAuthCode(pCallerInstance As %RegisteredObject, pOAuth2ApplicationName As %String, pOAuth2SessionId As %String, pOAuth2Resource As %String, ByRef pOAuth2Scope As %String, ByRef pOAuth2AuthPropertiesArray, ByRef pGrantTypeSpecific As %DynamicObject) As %Status
{
	Quit ..NotAvailable()
}

ClassMethod OnNotAuthorizedGrantClientCredentials(pCallerInstance As %RegisteredObject, pOAuth2ApplicationName As %String, pOAuth2SessionId As %String, pOAuth2Resource As %String, ByRef pOAuth2Scope As %String, ByRef pOAuth2AuthPropertiesArray, ByRef pGrantTypeSpecific As %DynamicObject) As %Status
{
	Quit ..NotAvailable()
}

ClassMethod OnNotAuthorizedGrantJWTAuth(pCallerInstance As %RegisteredObject, pOAuth2ApplicationName As %String, pOAuth2SessionId As %String, pOAuth2Resource As %String, ByRef pOAuth2Scope As %String, ByRef pOAuth2AuthPropertiesArray, ByRef pGrantTypeSpecific As %DynamicObject) As %Status
{
	Quit ..NotAvailable()
}

ClassMethod OnNotAuthorizedGrantPassword(pCallerInstance As %RegisteredObject, pOAuth2ApplicationName As %String, pOAuth2SessionId As %String, pOAuth2Resource As %String, ByRef pOAuth2Scope As %String, ByRef pOAuth2AuthPropertiesArray, ByRef pGrantTypeSpecific As %DynamicObject) As %Status
{
	Quit ..NotAvailable()
}

}
