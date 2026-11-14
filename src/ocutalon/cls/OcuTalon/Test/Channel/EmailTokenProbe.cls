/// A subclass of OcuTalon.Channel.Email.Token for the tests (Story 21.8) that counts the calls that IRIS's OnGetAccessToken makes to OnNotAuthorizedGrantAuthCode, the
/// only way to see that it ran past the online-demo check, in the process-private global ^||OcuTalonEmailTokenProbe("authCode"). The product never refers to it.
Class OcuTalon.Test.Channel.EmailTokenProbe Extends OcuTalon.Channel.Email.Token
{

ClassMethod OnNotAuthorizedGrantAuthCode(pCallerInstance As %RegisteredObject, pOAuth2ApplicationName As %String, pOAuth2SessionId As %String, pOAuth2Resource As %String, ByRef pOAuth2Scope As %String, ByRef pOAuth2AuthPropertiesArray, ByRef pGrantTypeSpecific As %DynamicObject) As %Status
{
	Set ^||OcuTalonEmailTokenProbe("authCode") = $Get(^||OcuTalonEmailTokenProbe("authCode")) + 1
	Quit ##super(pCallerInstance, pOAuth2ApplicationName, pOAuth2SessionId, pOAuth2Resource, .pOAuth2Scope, .pOAuth2AuthPropertiesArray, .pGrantTypeSpecific)
}

}
