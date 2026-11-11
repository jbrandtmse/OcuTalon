/// A subclass of OcuTalon.Test.Core.SettingsOpsProbe for the tests of the email section (Story 21.2), which stands in for the four places where
/// SaveEmail writes outside the product keys, so that a test changes no credential, no System Default Setting and no production:
///   - the credential OcuTalonMail is the process-private global ^||OcuTalonSettingsEmailProbe("cred") = $ListBuild(user, password), which dies
///     with the process and is never stored (the password is a dummy of the test);
///   - the settings rows of the mail items are ^||OcuTalonSettingsEmailProbe("sds", item, name) = value (item EmailIn or EmailOut);
///   - StartItem records a call and runs no production update.
/// Every call is recorded in order under ^||OcuTalonSettingsEmailProbe("calls", n) as "credential|<user>|<setPassword>", "deleteCredential",
/// "sds|<item>|<name>|<value>", "deleteSds|<item>|<name>" or "start", never with a password. The answers come from ^OcuTalonTest("SettingsEmailProbe", "answer", what):
/// "credential", "sds", "start" are "" for OK and "error" for an error status, and "sdsAt" (a number n) fails the nth settings write only (across both items). The product
/// never refers to it.
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
