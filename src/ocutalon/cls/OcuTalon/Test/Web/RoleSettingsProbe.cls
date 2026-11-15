/// A subclass of OcuTalon.Web.RoleSettings for the tests (Story 25.4); it has no Test methods and the product never refers to it. The roles of the signed-in user are
/// the text in ^OcuTalonTest("ApiProbe", "roles") when it is set (comma-separated, as $Roles is), which the OcuTalon user role check, the viewer check and the admin
/// check all read, and the process's own $Roles otherwise (as Test.Web.ApiProbe does); the live role set is the same text unless ^OcuTalonTest("ApiProbe", "liveRoles") is set.
/// Submit and Offer count each call under ^OcuTalonTest("RoleSettingsProbe", "submits") and ("offers"). With ^OcuTalonTest("RoleSettingsProbe", "mode") "fail" or "throw",
/// Submit records the command's Changes in ^OcuTalonTest("RoleSettingsProbe", "changes") and answers an error status or throws, and submits nothing; with the mode
/// "offer" Offer records the uri it made in ^OcuTalonTest("RoleSettingsProbe", "uri").
Class OcuTalon.Test.Web.RoleSettingsProbe Extends OcuTalon.Web.RoleSettings
{

ClassMethod Roles() As %String [ Private ]
{
	If $Data(^OcuTalonTest("ApiProbe", "roles")) Quit ^OcuTalonTest("ApiProbe", "roles")
	Quit ##super()
}

ClassMethod HasUserRole() As %Boolean [ Private ]
{
	If $Data(^OcuTalonTest("ApiProbe", "roles")) Quit ##class(OcuTalon.Web.Public.Shell).HasRole(^OcuTalonTest("ApiProbe", "roles"))
	Quit ##super()
}

ClassMethod LiveRoles(Output roles As %String) As %Status [ Private ]
{
	Set roles = $Select($Data(^OcuTalonTest("ApiProbe", "liveRoles")): ^OcuTalonTest("ApiProbe", "liveRoles"), 1: ..Roles())
	Quit $$$OK
}

ClassMethod Offer(text As %String, Output uri As %String) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("RoleSettingsProbe", "offers"))
	Set sc = ##super(text, .uri)
	Set ^OcuTalonTest("RoleSettingsProbe", "uri", n) = uri
	Quit sc
}

ClassMethod Submit(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("RoleSettingsProbe", "submits"))
	Set mode = $Get(^OcuTalonTest("RoleSettingsProbe", "mode"))
	If mode = "" Quit ##super(command, .result)
	If $IsObject(command) && command.%IsA("OcuTalon.Msg.Command.SaveSettings") Set ^OcuTalonTest("RoleSettingsProbe", "changes") = command.Changes
	If mode = "notbuilt" {
		Set result = ##class(OcuTalon.Msg.CommandResult).%New()
		Set result.Ok = 0
		Set result.Outcome = "not_built"
		Quit $$$OK
	}
	If mode = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz submit threw"))
	Quit $SYSTEM.Status.Error(5001, "zz submit failed")
}

}
