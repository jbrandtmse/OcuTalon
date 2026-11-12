/// A stand-in for OcuTalon.Channel.Email.Token for the tests of the adapters (Story 21.8), so that no IRIS OAuth2 object is read. Its OnGetAccessToken answers by the
/// process-private global ^||OcuTalonEmailInHandler("answer"): "" gives the token "zz-token-" and the call's number (an authorized, OK answer), error an error status
/// with no token, empty an OK status that is not authorized with an empty token, and throw raises an exception. It records the arguments of each call under
/// ^||OcuTalonEmailInHandler("call", n) = $ListBuild(application name, session id, resource (the user name), scope), and counts the calls in ^||OcuTalonEmailInHandler("calls").
/// The product never refers to it.
Class OcuTalon.Test.Channel.EmailInHandler Extends Ens.Util.OAuth2.Handler
{

ClassMethod OnGetAccessToken(pCallerInstance As %RegisteredObject = "", pOAuth2GrantType As %String, pOAuth2ApplicationName As %String = "", pOAuth2SessionId As %String, pOAuth2Resource As %String, ByRef pOAuth2Scope As %String, ByRef pOAuth2AuthProperties As %String, ByRef pGrantTypeSpecific As %DynamicObject, Output pOAuth2IsAuthorized As %Boolean = 0, Output pOAuth2AccessToken As %String = "", Output pOAuth2HostShouldRetry As %Boolean = 0) As %Status
{
	Set n = $Increment(^||OcuTalonEmailInHandler("calls"))
	Set ^||OcuTalonEmailInHandler("call", n) = $ListBuild(pOAuth2ApplicationName, $Get(pOAuth2SessionId), $Get(pOAuth2Resource), $Get(pOAuth2Scope))
	Set pOAuth2IsAuthorized = 0, pOAuth2AccessToken = "", pOAuth2HostShouldRetry = 0
	Set answer = $Get(^||OcuTalonEmailInHandler("answer"))
	If answer = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "SERVER-WORDS zzthrown@example.com"))
	If answer = "error" Quit $SYSTEM.Status.Error(5001, "SERVER-WORDS zzhandler@example.com")
	If answer = "empty" Quit $$$OK
	Set pOAuth2IsAuthorized = 1
	Set pOAuth2AccessToken = "zz-token-"_n
	Quit $$$OK
}

}
