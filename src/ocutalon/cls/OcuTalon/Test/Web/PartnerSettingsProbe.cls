/// A subclass of OcuTalon.Web.PartnerSettings for the tests (Story 24.2); it has no Test methods and the product never refers to it. The roles of the signed-in
/// user are the text in ^OcuTalonTest("ApiProbe", "roles") when it is set (comma-separated, as $Roles is), which both the OcuTalon user role check and the admin
/// check read, and the process's own $Roles otherwise (as Test.Web.ApiProbe does). Offer and Submit count their calls in ^OcuTalonTest("PartnerSettingsProbe",
/// "offers") and ("submits"). When ^OcuTalonTest("PartnerSettingsProbe", "mode") is "fail" or "throw", Submit records the handoff uri of the command's Changes in
/// ^OcuTalonTest("PartnerSettingsProbe", "uri") and answers an error status or throws, and submits nothing. When it is "not_available", Submit records the uri
/// the same way and answers OK with a CommandResult of outcome not_available (the answer of SettingsOps on the online demo), and submits nothing.
/// The class declares TABLE = 0, so that Test.Core.SettingsPartners can show that SettingsOps.PartnersShown reads the parameter of the class it is given.
Class OcuTalon.Test.Web.PartnerSettingsProbe Extends OcuTalon.Web.PartnerSettings
{

Parameter TABLE = 0;

ClassMethod Roles() As %String [ Private ]
{
	If $Data(^OcuTalonTest("ApiProbe", "roles")) Quit ^OcuTalonTest("ApiProbe", "roles")
	Quit ##super()
}

ClassMethod HasUserRole() As %Boolean [ Private ]
{
	If $Data(^OcuTalonTest("ApiProbe", "roles")) Quit (","_^OcuTalonTest("ApiProbe", "roles")_",") [ (","_##class(OcuTalon.Web.Public.Shell).#ROLE_",")
	Quit ##super()
}

/// The live role set of OnPreDispatch's re-read: the test's own roles (Roles).
ClassMethod LiveRoles(Output roles As %String) As %Status [ Private ]
{
	Set roles = ..Roles()
	Quit $$$OK
}

ClassMethod Offer(text As %String, Output uri As %String) As %Status [ Private ]
{
	Set count = $Increment(^OcuTalonTest("PartnerSettingsProbe", "offers"))
	Quit ##super(text, .uri)
}

ClassMethod Submit(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set count = $Increment(^OcuTalonTest("PartnerSettingsProbe", "submits"))
	Set mode = $Get(^OcuTalonTest("PartnerSettingsProbe", "mode"))
	If mode = "" Quit ##super(command, .result)
	Set ^OcuTalonTest("PartnerSettingsProbe", "uri") = {}.%FromJSON($Property(command, "Changes")).handoff
	If mode = "not_available" {
		Set result = ##class(OcuTalon.Msg.CommandResult).%New()
		Set result.Ok = 0, result.Outcome = "not_available", result.Message = "zz not shown"
		Quit $$$OK
	}
	If mode = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz submit threw"))
	Quit $SYSTEM.Status.Error(5001, "zz submit failed")
}

}
