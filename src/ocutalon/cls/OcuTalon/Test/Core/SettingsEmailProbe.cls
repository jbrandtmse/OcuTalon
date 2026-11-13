/// A subclass of OcuTalon.Test.Core.SettingsOpsProbe for the tests of the email section (Story 21.2), which stands in for the four places where
/// SaveEmail writes outside the product keys, so that a test changes no credential, no System Default Setting and no production:
///   - the credential OcuTalonMail is the process-private global ^||OcuTalonSettingsEmailProbe("cred") = $ListBuild(user, password), which dies
///     with the process and is never stored (the password is a dummy of the test);
///   - the settings rows of the mail items are ^||OcuTalonSettingsEmailProbe("sds", item, name) = value (item EmailIn or EmailOut);
///   - StartItem records a call and runs no production update.
/// Every call is recorded in order under ^||OcuTalonSettingsEmailProbe("calls", n) as "credential|<user>|<setPassword>", "deleteCredential",
/// "sds|<item>|<name>|<value>", "deleteSds|<item>|<name>" or "start", never with a password. The answers come from ^OcuTalonTest("SettingsEmailProbe", "answer", what):
/// "credential", "sds", "start" are "" for OK and "error" for an error status, and "sdsAt" (a number n) fails the nth settings write only (across both items).
/// The OAuth2 seams (Story 21.3) touch no %SYS object: RegisterOAuth records "oauthRegister|<provider>|<clientId>|<origin>|<owned>|secret or kept" (the client secret
/// itself is in the process-private ^||OcuTalonSettingsEmailProbe("oauthSecret") for the test to compare, never in the calls), RemoveOAuth "oauthRemove|<owned>",
/// OAuthStart "oauthStart|<provider>|<origin>|<owned>" and OAuthState "oauthState", and RecordSignIn stores the mark's provider and signedIn in
/// ^||OcuTalonSettingsEmailProbe("mark") and records "mark|<provider>|<signedIn>". The answers: "register", "remove", "start" and "state" are "" for OK and "error" for an
/// error status; "owned" is the list that a register or start answers (default: client,server,app for a first register, else the list it was given), "app" is "enabled"
/// or "disabled" or empty (default: enabled for a first register, disabled for a remove that names app, else empty), "changed" is the register's changed (default 1) and
/// "signedIn" is the state's (default 0). The product never refers to it.
Class OcuTalon.Test.Core.SettingsEmailProbe Extends OcuTalon.Test.Core.SettingsOpsProbe
{

ClassMethod Note(text As %String) [ Private ]
{
	Set n = $Increment(^||OcuTalonSettingsEmailProbe("calls"))
	Set ^||OcuTalonSettingsEmailProbe("calls", n) = text
}

ClassMethod Answer(what As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("SettingsEmailProbe", "answer", what))
}

ClassMethod ReadCredential(Output user As %String, Output password As %String, withPassword As %Boolean = 1) As %Boolean
{
	Set user = "", password = ""
	If '$Data(^||OcuTalonSettingsEmailProbe("cred"), stored) Quit 0
	Set user = $List(stored, 1)
	If withPassword Set password = $List(stored, 2)
	Quit 1
}

ClassMethod WriteCredential(user As %String, password As %String, setPassword As %Boolean) As %Status [ Private ]
{
	Do ..Note("credential|"_user_"|"_+setPassword)
	If ..Answer("credential") = "error" Quit $SYSTEM.Status.Error(5001, "zz credential failed")
	Set old = $Get(^||OcuTalonSettingsEmailProbe("cred"))
	Set ^||OcuTalonSettingsEmailProbe("cred") = $ListBuild(user, $Select(setPassword: password, old '= "": $List(old, 2), 1: ""))
	Quit $$$OK
}

ClassMethod DeleteCredential() As %Status [ Private ]
{
	Do ..Note("deleteCredential")
	Kill ^||OcuTalonSettingsEmailProbe("cred")
	Quit $$$OK
}

ClassMethod ItemSettingExists(item As %String, name As %String) As %Boolean [ Private ]
{
	Quit ''$Data(^||OcuTalonSettingsEmailProbe("sds", item, name))
}

ClassMethod ReadItemSetting(item As %String, name As %String) As %String [ Private ]
{
	Quit $Get(^||OcuTalonSettingsEmailProbe("sds", item, name))
}

ClassMethod WriteItemSetting(item As %String, name As %String, value As %String) As %Status [ Private ]
{
	Do ..Note("sds|"_item_"|"_name_"|"_value)
	Set writes = $Increment(^||OcuTalonSettingsEmailProbe("writes"))
	If (..Answer("sds") = "error") || (writes = +..Answer("sdsAt")) Quit $SYSTEM.Status.Error(5001, "zz settings row failed")
	Set ^||OcuTalonSettingsEmailProbe("sds", item, name) = value
	Quit $$$OK
}

ClassMethod DeleteItemSetting(item As %String, name As %String) As %Status [ Private ]
{
	Do ..Note("deleteSds|"_item_"|"_name)
	Kill ^||OcuTalonSettingsEmailProbe("sds", item, name)
	Quit $$$OK
}

ClassMethod StartItem() As %Status [ Private ]
{
	Do ..Note("start")
	If ..Answer("start") = "error" Quit $SYSTEM.Status.Error(5001, "zz update failed")
	Quit $$$OK
}

Method RegisterOAuth(provider As %String, clientId As %String, clientSecret As %String, origin As %String, owned As %String, Output changed As %Boolean, Output nowOwned As %String, Output app As %String) As %Status [ Private ]
{
	Do ..Note("oauthRegister|"_provider_"|"_clientId_"|"_origin_"|"_owned_"|"_$Select(clientSecret '= "": "secret", 1: "kept"))
	Set ^||OcuTalonSettingsEmailProbe("oauthSecret") = clientSecret
	Set changed = +$Select(..Answer("changed") '= "": ..Answer("changed"), 1: 1)
	Set nowOwned = $Select(..Answer("owned") '= "": ..Answer("owned"), owned = "": "client,server,app", 1: owned)
	Set app = $Select($Data(^OcuTalonTest("SettingsEmailProbe", "answer", "app")): ..Answer("app"), owned = "": "enabled", 1: "")
	If ..Answer("register") = "error" Quit $SYSTEM.Status.Error(5001, "zz register failed")
	Quit $$$OK
}

Method RemoveOAuth(owned As %String, Output nowOwned As %String, Output app As %String) As %Status [ Private ]
{
	Do ..Note("oauthRemove|"_owned)
	Set nowOwned = ""
	Set app = $Select($Data(^OcuTalonTest("SettingsEmailProbe", "answer", "app")): ..Answer("app"), $ListFind($ListFromString(owned), "app"): "disabled", 1: "")
	If ..Answer("remove") = "error" Quit $SYSTEM.Status.Error(5001, "zz remove failed")
	Quit $$$OK
}

Method OAuthStart(provider As %String, origin As %String, owned As %String, Output url As %String, Output nowOwned As %String, Output app As %String) As %Status [ Private ]
{
	Do ..Note("oauthStart|"_provider_"|"_origin_"|"_owned)
	Set url = "", nowOwned = $Select(..Answer("owned") '= "": ..Answer("owned"), 1: owned)
	Set app = ..Answer("app")
	If ..Answer("start") = "error" Quit $SYSTEM.Status.Error(5001, "zz start failed")
	Set url = origin_"/csp/sys/oauth2/OAuth2.Response.cls?auth=1&state=zzstate"
	Quit $$$OK
}

Method OAuthState(Output signedIn As %Boolean) As %Status [ Private ]
{
	Do ..Note("oauthState")
	Set signedIn = +..Answer("signedIn")
	If ..Answer("state") = "error" Quit $SYSTEM.Status.Error(5001, "zz state failed")
	Quit $$$OK
}

ClassMethod RecordSignIn(provider As %String, signedIn As %Boolean) [ Private ]
{
	Do ..Note("mark|"_provider_"|"_+signedIn)
	Set ^||OcuTalonSettingsEmailProbe("mark") = $ListBuild(provider, +signedIn)
}

ClassMethod SignedInMark(provider As %String) As %Boolean [ Private ]
{
	Set mark = $Get(^||OcuTalonSettingsEmailProbe("mark"))
	Quit (mark '= "") && ($List(mark, 1) = provider) && ($List(mark, 2) = 1)
}

/// Seeds the stand-in credential and the rows of EmailIn as an earlier save would have left them; with an outgoing host (and port) the rows of EmailOut too.
ClassMethod Seed(user As %String, password As %String, host As %String, port As %Integer, outHost As %String = "", outPort As %Integer = 587)
{
	Set ^||OcuTalonSettingsEmailProbe("cred") = $ListBuild(user, password)
	Set ^||OcuTalonSettingsEmailProbe("sds", "EmailIn", "POP3Server") = host
	Set ^||OcuTalonSettingsEmailProbe("sds", "EmailIn", "POP3Port") = port
	Set ^||OcuTalonSettingsEmailProbe("sds", "EmailIn", "Enabled") = 1
	If outHost '= "" {
		Set ^||OcuTalonSettingsEmailProbe("sds", "EmailOut", "SMTPServer") = outHost
		Set ^||OcuTalonSettingsEmailProbe("sds", "EmailOut", "SMTPPort") = outPort
		Set ^||OcuTalonSettingsEmailProbe("sds", "EmailOut", "Enabled") = 1
	}
}

}
