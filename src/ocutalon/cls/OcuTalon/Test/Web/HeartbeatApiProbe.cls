/// A subclass of OcuTalon.Web.Api for the tests of the heartbeat routes (Story 39.2), which overrides the three private seams so that a test can reach
/// the answers that the real items never give, and records the cause of each 500. It has no Test methods and the product never refers to it.
///   - SubmitHeartbeat records each command under ^OcuTalonTest("HeartbeatApiProbe", "submitted", n) as "class" (the command's class name without
///     the package), "session" and, for a SetHeartbeat, "on", "interval", "from", "to" and "checklist", and answers from
///     ^OcuTalonTest("HeartbeatApiProbe", "submit"): "fail" is an error status, "none" is an OK status with no result, and any other text is the
///     JSON {"ok", "outcome", "message", "data"} of the CommandResult to answer;
///   - ReadHeartbeat answers an error status with a heartbeat of on and a 60 minute interval when ^OcuTalonTest("HeartbeatApiProbe", "read") is
///     "fail", so that a route that sent the values would show; when it is "defaults" it answers the defaults with an OK status whatever the session,
///     so that only the route's own check of the session can refuse a call;
///   - ServerError records the text of the status it is given under ^OcuTalonTest("HeartbeatApiProbe", "logged"), the cause that it writes to the
///     console log, and answers as the route's own.
Class OcuTalon.Test.Web.HeartbeatApiProbe Extends OcuTalon.Web.Api
{

ClassMethod SubmitHeartbeat(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set result = ""
	Set n = $Increment(^OcuTalonTest("HeartbeatApiProbe", "submitted"))
	Set ^OcuTalonTest("HeartbeatApiProbe", "submitted", n, "class") = $Piece($ClassName(command), ".", *)
	Set ^OcuTalonTest("HeartbeatApiProbe", "submitted", n, "session") = command.SessionRef
	If command.%IsA("OcuTalon.Msg.Command.SetHeartbeat") {
		Set ^OcuTalonTest("HeartbeatApiProbe", "submitted", n, "on") = command.On
		Set ^OcuTalonTest("HeartbeatApiProbe", "submitted", n, "interval") = command.Interval
		Set ^OcuTalonTest("HeartbeatApiProbe", "submitted", n, "from") = command.From
		Set ^OcuTalonTest("HeartbeatApiProbe", "submitted", n, "to") = command.To
		Set ^OcuTalonTest("HeartbeatApiProbe", "submitted", n, "checklist") = command.Checklist
	}
	Set answer = $Get(^OcuTalonTest("HeartbeatApiProbe", "submit"))
	If answer = "fail" Quit $SYSTEM.Status.Error(5001, "zz CommandsIn is not running")
	If answer = "none" Quit $SYSTEM.Status.OK()
	Set spec = {}.%FromJSON(answer)
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = spec.ok
	Set result.Outcome = spec.outcome
	Set result.Message = spec.message
	Set result.Data = spec.data
	Quit $SYSTEM.Status.OK()
}

ClassMethod ReadHeartbeat(sessionRef As %String, Output sc As %Status) As %DynamicObject [ Private ]
{
	If $Get(^OcuTalonTest("HeartbeatApiProbe", "read")) = "fail" {
		Set sc = $SYSTEM.Status.Error(5001, "zz the heartbeat could not be read")
		Quit {"on": true, "interval": 60, "from": "07:00", "to": "21:00", "checklist": "zz not sent", "sample": false}
	}
	If $Get(^OcuTalonTest("HeartbeatApiProbe", "read")) = "defaults" {
		Set sc = $SYSTEM.Status.OK()
		Quit {"on": true, "interval": 30, "from": "08:00", "to": "20:00", "checklist": "", "sample": false}
	}
	Quit ##super(sessionRef, .sc)
}

ClassMethod ServerError(sc As %Status = {$SYSTEM.Status.OK()}) As %Status [ Private ]
{
	Set ^OcuTalonTest("HeartbeatApiProbe", "logged") = $SYSTEM.Status.GetErrorText(sc)
	Quit ##super(sc)
}

}
