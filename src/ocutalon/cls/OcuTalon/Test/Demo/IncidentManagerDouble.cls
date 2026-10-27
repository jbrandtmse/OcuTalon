/// A stand-in for the IncidentManager item (Story 4.3; AD-22), put behind the item by Test.Demo.BreakFeedProduction
/// (Test.Agent.RunnerFixture.UseItemClass) in a throwaway. For an IncidentCommand it records, under
/// ^OcuTalonTest("IncidentManagerDouble", "commands", n), the verb, the incident ("ref"), the session, the origin and the number of
/// Break the feed runs that the session has at that moment ("runs"), and answers by ^OcuTalonTest("IncidentManagerDouble", "answer"):
/// "" closes the fixture incident (State closed, ClosedAt now) and answers Ok 1, "refuse" answers Ok 0, and "error" answers an error
/// status. ^OcuTalonTest("IncidentManagerDouble", "delay"), seconds, holds each command before it answers (a press that is slow to close
/// shows whether a second press can get in). Any other request, such as a batch of failures, is answered OK with no response. THROWAWAYS AND CI ONLY (Rule 21).
Class OcuTalon.Test.Demo.IncidentManagerDouble Extends Ens.BusinessProcess
{

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set response = ""
	If '$IsObject($Get(request)) || 'request.%IsA("OcuTalon.Msg.IncidentCommand") Quit $SYSTEM.Status.OK()
	Set n = $Increment(^OcuTalonTest("IncidentManagerDouble", "commands"))
	Set ^OcuTalonTest("IncidentManagerDouble", "commands", n) = request.Verb
	Set ^OcuTalonTest("IncidentManagerDouble", "commands", n, "ref") = request.IncidentRef
	Set ^OcuTalonTest("IncidentManagerDouble", "commands", n, "session") = request.SessionRef
	Set ^OcuTalonTest("IncidentManagerDouble", "commands", n, "origin") = request.Origin
	Set ^OcuTalonTest("IncidentManagerDouble", "commands", n, "runs") = ##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs(request.SessionRef)
	Hang +$Get(^OcuTalonTest("IncidentManagerDouble", "delay"))
	Set answer = $Get(^OcuTalonTest("IncidentManagerDouble", "answer"))
	If answer = "error" Quit $SYSTEM.Status.Error(5001, "zz the double answers an error")
	Set response = ##class(OcuTalon.Msg.CommandResult).%New()
	If answer = "refuse" {
		Set response.Ok = 0
		Set response.Outcome = "refused"
		Quit $SYSTEM.Status.OK()
	}
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(request.IncidentRef)
	If $IsObject(incident) {
		Set incident.State = "closed"
		Set incident.ClosedAt = ##class(OcuTalon.Data.Time).NowUtc()
		Set sc = incident.%Save()
		If $SYSTEM.Status.IsError(sc) Quit sc
	}
	Set response.Ok = 1
	Set response.Outcome = "closed"
	Set response.Ref = request.IncidentRef
	Quit $SYSTEM.Status.OK()
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
