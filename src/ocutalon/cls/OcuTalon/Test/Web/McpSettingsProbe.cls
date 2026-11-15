/// A subclass of OcuTalon.Web.McpSettings for the tests (Story 21.4); it has no Test methods and the product never refers to it. The roles of the signed-in
/// user are the text in ^OcuTalonTest("ApiProbe", "roles") when it is set (comma-separated, as $Roles is), which both the OcuTalon user role check and the
/// admin check read, and the process's own $Roles otherwise (as Test.Web.ApiProbe does). HandOff counts its calls in ^OcuTalonTest("McpSettingsProbe", "handoffs") and Submit
/// counts its calls in ^OcuTalonTest("McpSettingsProbe", "submits") and records the handoff uri of an AddMcpServer in ^OcuTalonTest("McpSettingsProbe", "uri"), each before it goes on (neither
/// records a secret). When ^OcuTalonTest("McpSettingsProbe", "mode") is "fail" or "throw", Submit answers an error status or throws, and submits nothing; when it is
/// "outcome:<word>", Submit answers an OK status and a CommandResult with that outcome and the message "zz" (Ok 1 with Ref "zzref" for saved and removed, Ok 0 for any other word), and submits nothing.
/// Submit also records the command's class and, for a SetSourcePoll or a RemoveSourcePoll, every field, as JSON in ^OcuTalonTest("McpSettingsProbe", "command").
Class OcuTalon.Test.Web.McpSettingsProbe Extends OcuTalon.Web.McpSettings
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

ClassMethod HandOff(command As OcuTalon.Msg.Command, secret As %String, Output result As OcuTalon.Msg.CommandResult, optional As %Boolean = 0) As %Status [ Private ]
{
	Set ^OcuTalonTest("McpSettingsProbe", "handoffs") = $Get(^OcuTalonTest("McpSettingsProbe", "handoffs")) + 1
	Quit ##super(command, $Get(secret), .result, optional)
}

ClassMethod Submit(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set ^OcuTalonTest("McpSettingsProbe", "submits") = $Get(^OcuTalonTest("McpSettingsProbe", "submits")) + 1
	Set mode = $Get(^OcuTalonTest("McpSettingsProbe", "mode"))
	Set ^OcuTalonTest("McpSettingsProbe", "uri") = $Select(command.%Extends("OcuTalon.Msg.Command.AddMcpServer"): command.Handoff, 1: "")
	Set ^OcuTalonTest("McpSettingsProbe", "command") = ..Recorded(command)
	If mode = "" Quit ##super(command, .result)
	If $Piece(mode, ":") = "outcome" {
		Set result = ##class(OcuTalon.Msg.CommandResult).%New()
		Set outcome = $Piece(mode, ":", 2)
		Set result.Ok = ((outcome = "saved") || (outcome = "removed"))
		Set result.Outcome = outcome
		Set result.Message = "zz"
		If result.Ok Set result.Ref = "zzref"
		Quit $SYSTEM.Status.OK()
	}
	If mode = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz submit threw"))
	Quit $SYSTEM.Status.Error(5001, "zz submit failed")
}

/// The submitted command as JSON: its class and, for a SetSourcePoll or a RemoveSourcePoll, every field (no secret is ever in these).
ClassMethod Recorded(command As OcuTalon.Msg.Command) As %String [ Private ]
{
	Set recorded = {"class": ($ClassName(command)), "sessionRef": (command.SessionRef), "actingUser": (command.ActingUser)}
	If command.%IsA("OcuTalon.Msg.Command.SetSourcePoll") {
		Do recorded.%Set("server", command.Server)
		Do recorded.%Set("tool", command.Tool)
		Do recorded.%Set("name", command.Name)
		Do recorded.%Set("arguments", command.Arguments)
		Do recorded.%Set("intervalMinutes", command.IntervalMinutes, "number")
	} ElseIf command.%IsA("OcuTalon.Msg.Command.RemoveSourcePoll") {
		Do recorded.%Set("sourceRef", command.SourceRef)
	}
	Quit recorded.%ToJSON()
}

}
