/// A subclass of OcuTalon.Web.SlackSettings for the tests (Story 27.3); it has no Test methods and the product never refers to it. The roles of the signed-in user are the text
/// in ^OcuTalonTest("ApiProbe", "roles") when it is set (comma-separated, as $Roles is), which the OcuTalon user role check, the viewer check and the admin check all read, and
/// the process's own $Roles otherwise (as Test.Web.ApiProbe does); the live role set is the same text unless ^OcuTalonTest("ApiProbe", "liveRoles") is set. It stands in for
/// Commands.Submit, so that no production is needed. HandOff counts each call under ^OcuTalonTest("SlackSettingsProbe", "handoffs"). Submit counts each call under ("submits"),
/// records the command of call n under ("calls", n): its class ("class"), SessionRef, ActingUser, LinkRef and Handoff, and with the "mode" unset answers as the operation would:
///   - a command with a Handoff has its handoff taken, and the text is recorded under ("calls", n, "taken");
///   - the answer is the CommandResult that ("result") holds as JSON {ok, outcome, message, data} (data is a JSON text); with none, the verb's own done answer: a ListSlackLinks
///     lists the body that ("listBody") holds, as a handoff of its own, a LinkSlackMember answers done with the Ref "zzSlackRef000000000001" and an UnlinkSlackMember done.
/// With the "mode" "fail" or "throw" Submit records the call without taking the handoff, and answers an error status or throws, and submits nothing.
Class OcuTalon.Test.Web.SlackSettingsProbe Extends OcuTalon.Web.SlackSettings
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

ClassMethod HandOff(command As OcuTalon.Msg.Command, secret As %String, Output result As OcuTalon.Msg.CommandResult, optional As %Boolean = 0) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("SlackSettingsProbe", "handoffs"))
	Quit ##super(command, secret, .result, optional)
}

ClassMethod Submit(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("SlackSettingsProbe", "submits"))
	Set call = $Name(^OcuTalonTest("SlackSettingsProbe", "calls", n))
	Set @call@("class") = $ClassName(command)
	Set @call@("sessionRef") = command.SessionRef
	Set @call@("actingUser") = $Select(command.%Extends("OcuTalon.Msg.Command.ListSlackLinks"): "", 1: command.ActingUser)
	Set @call@("linkRef") = $Select(command.%Extends("OcuTalon.Msg.Command.UnlinkSlackMember"): command.LinkRef, 1: "")
	Set handoff = $Select(command.%Extends("OcuTalon.Msg.Command.LinkSlackMember"): command.Handoff, 1: "")
	Set @call@("handoff") = handoff
	Set mode = $Get(^OcuTalonTest("SlackSettingsProbe", "mode"))
	If mode = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz submit threw"))
	If mode = "fail" Quit $SYSTEM.Status.Error(5001, "zz submit failed")
	If handoff '= "" {
		Set sc = ##class(OcuTalon.Core.SecretHandoff).Take(handoff, .taken, 0)
		Set @call@("taken") = $Select($SYSTEM.Status.IsOK(sc): taken, 1: "")
	}
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set answer = $Get(^OcuTalonTest("SlackSettingsProbe", "result"))
	If answer '= "" {
		Set one = {}.%FromJSON(answer)
		Set result.Ok = one.ok
		Set result.Outcome = one.outcome
		Set result.Message = one.message
		Set result.Data = one.data
		Quit $$$OK
	}
	Set result.Ok = 1
	If command.%Extends("OcuTalon.Msg.Command.ListSlackLinks") {
		Set result.Outcome = "listed"
		Set sc = ##class(OcuTalon.Core.SecretHandoff).Put($Get(^OcuTalonTest("SlackSettingsProbe", "listBody")), .uri)
		Set ^OcuTalonTest("SlackSettingsProbe", "listUri") = uri
		Set result.Data = {"handoff": (uri)}.%ToJSON()
	} ElseIf command.%Extends("OcuTalon.Msg.Command.LinkSlackMember") {
		Set result.Outcome = "done"
		Set result.Data = {"ref": "zzSlackRef000000000001"}.%ToJSON()
	} Else {
		Set result.Outcome = "done"
	}
	Quit $$$OK
}

}
