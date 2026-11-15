/// A subclass of OcuTalon.Web.HookSettings for the tests (Story 35.3); it has no Test methods and the product never refers to it. The roles of the signed-in
/// user are the text in ^OcuTalonTest("ApiProbe", "roles") when it is set (comma-separated, as $Roles is), which both the OcuTalon user role check and the
/// admin check read, and the process's own $Roles otherwise (as Test.Web.ApiProbe does). When ^OcuTalonTest("HookSettingsProbe", "mode") is "fail" or "throw", Submit
/// records the command's handoff uri in ^OcuTalonTest("HookSettingsProbe", "uri") and answers an error status or throws, and submits nothing.
Class OcuTalon.Test.Web.HookSettingsProbe Extends OcuTalon.Web.HookSettings
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

/// The live role set of OnPreDispatch's re-read: ^OcuTalonTest("ApiProbe", "liveRoles") when it is set, an error status when ^OcuTalonTest("ApiProbe", "liveError") is
/// set, and the test's own roles (Roles) otherwise.
ClassMethod LiveRoles(Output roles As %String) As %Status [ Private ]
{
	Set roles = ""
	If $Data(^OcuTalonTest("ApiProbe", "liveError")) Quit $SYSTEM.Status.Error(5001, "zz live roles unreadable")
	Set n = $Increment(^OcuTalonTest("ApiProbe", "liveReads"))
	Set roles = $Select($Data(^OcuTalonTest("ApiProbe", "liveRoles")): ^OcuTalonTest("ApiProbe", "liveRoles"), 1: ..Roles())
	Quit $$$OK
}

ClassMethod Submit(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set mode = $Get(^OcuTalonTest("HookSettingsProbe", "mode"))
	If mode = "" Quit ##super(command, .result)
	Set ^OcuTalonTest("HookSettingsProbe", "uri") = command.Handoff
	If mode = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz submit threw"))
	Quit $SYSTEM.Status.Error(5001, "zz submit failed")
}

}
