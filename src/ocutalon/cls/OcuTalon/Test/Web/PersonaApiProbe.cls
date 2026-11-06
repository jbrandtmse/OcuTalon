/// A subclass of OcuTalon.Web.Api for the tests of the persona routes (Story 40.8), which overrides the two private seams so that a
/// test can reach the failures that the real items never give, and records the cause of each 500. It has no Test methods and the product
/// never refers to it.
///   - SubmitPersona records each command under ^OcuTalonTest("PersonaApiProbe", "submitted", n) as "session", "preset", "language",
///     "custom" and answers from ^OcuTalonTest("PersonaApiProbe", "submit"): "fail" is an error status, "none" is an OK status with no
///     result, and any other text is the JSON {"ok", "outcome", "message", "data"} of the CommandResult to answer;
///   - ReadPersona answers an error status with a persona of pirate and a pending request when ^OcuTalonTest("PersonaApiProbe", "read")
///     is "fail", so that a route that sent the values would show; when it is "defaults" it answers the defaults with an OK status
///     whatever the session, so that only the route's own check of the session can refuse a call;
///   - ServerError records the text of the status it is given under ^OcuTalonTest("PersonaApiProbe", "logged"), the cause that it writes
///     to the console log, and answers as the route's own.
Class OcuTalon.Test.Web.PersonaApiProbe Extends OcuTalon.Web.Api
{

ClassMethod SubmitPersona(command As OcuTalon.Msg.Command.SetPersona, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set result = ""
	Set n = $Increment(^OcuTalonTest("PersonaApiProbe", "submitted"))
	Set ^OcuTalonTest("PersonaApiProbe", "submitted", n, "session") = command.SessionRef
	Set ^OcuTalonTest("PersonaApiProbe", "submitted", n, "preset") = command.Preset
	Set ^OcuTalonTest("PersonaApiProbe", "submitted", n, "language") = command.Language
	Set ^OcuTalonTest("PersonaApiProbe", "submitted", n, "custom") = command.Custom
	Set answer = $Get(^OcuTalonTest("PersonaApiProbe", "submit"))
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

ClassMethod ReadPersona(sessionRef As %String, Output sc As %Status) As %DynamicObject [ Private ]
{
	If $Get(^OcuTalonTest("PersonaApiProbe", "read")) = "fail" {
		Set sc = $SYSTEM.Status.Error(5001, "zz the persona could not be read")
		Quit {"preset": "pirate", "language": "", "custom": "", "customOffered": true, "pendingRef": "zzPendingRef0123456789"}
	}
	If $Get(^OcuTalonTest("PersonaApiProbe", "read")) = "defaults" {
		Set sc = $SYSTEM.Status.OK()
		Quit {"preset": "professional", "language": "", "custom": "", "customOffered": true, "pendingRef": ""}
	}
	Quit ##super(sessionRef, .sc)
}

ClassMethod ServerError(sc As %Status = {$SYSTEM.Status.OK()}) As %Status [ Private ]
{
	Set ^OcuTalonTest("PersonaApiProbe", "logged") = $SYSTEM.Status.GetErrorText(sc)
	Quit ##super(sc)
}

}
