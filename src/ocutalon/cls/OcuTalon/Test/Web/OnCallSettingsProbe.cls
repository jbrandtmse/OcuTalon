/// A subclass of OcuTalon.Web.OnCallSettings for the tests (Story 36.4); it has no Test methods and the product never refers to it. The roles of the signed-in
/// user are the text in ^OcuTalonTest("ApiProbe", "roles") when it is set (comma-separated, as $Roles is), which both the OcuTalon user role check and the admin
/// check read, and the process's own $Roles otherwise (as Test.Web.ApiProbe does). Offer and Submit count their calls in ^OcuTalonTest("OnCallSettingsProbe",
/// "offers") and ("submits"). When ^OcuTalonTest("OnCallSettingsProbe", "mode") is "fail" or "throw", Submit records the handoff uri of the command's Changes in
/// ^OcuTalonTest("OnCallSettingsProbe", "uri") and answers an error status or throws, and submits nothing. When it is "not_available", Submit records the uri
/// the same way and answers OK with a CommandResult of outcome not_available (the answer of SettingsOps on the online demo), and submits nothing.
Class OcuTalon.Test.Web.OnCallSettingsProbe Extends OcuTalon.Web.OnCallSettings
{

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
	Set count = $Increment(^OcuTalonTest("OnCallSettingsProbe", "offers"))
	Quit ##super(text, .uri)
}

ClassMethod Submit(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set count = $Increment(^OcuTalonTest("OnCallSettingsProbe", "submits"))
	Set mode = $Get(^OcuTalonTest("OnCallSettingsProbe", "mode"))
	If mode = "" Quit ##super(command, .result)
	Set ^OcuTalonTest("OnCallSettingsProbe", "uri") = {}.%FromJSON($Property(command, "Changes")).handoff
	If mode = "not_available" {
		Set result = ##class(OcuTalon.Msg.CommandResult).%New()
		Set result.Ok = 0, result.Outcome = "not_available", result.Message = "zz not shown"
		Quit $$$OK
	}
	If mode = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz submit threw"))
	Quit $SYSTEM.Status.Error(5001, "zz submit failed")
}

}
