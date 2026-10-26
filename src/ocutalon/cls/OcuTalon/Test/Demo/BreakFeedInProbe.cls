/// A subclass of OcuTalon.Demo.BreakFeedIn for the tests, which override its private seams Close and Trigger so that the press runs on a
/// slot with no production (Story 4.3; AD-22). Every other step, the lock, Guide.Compute, the run rows and the publishes, is the real
/// one. Each seam call is recorded under ^OcuTalonTest("BreakFeedInProbe", "calls", n) as "close" or "trigger", with the number and the
/// states of the pressing session's runs at that moment ("runs", for example "1:sending"), and the SuperSession that the service holds
/// ("superSession"); a close also records the command ("verb", "ref", "session", "origin") and a trigger the request ("session",
/// "channel"). The answers come from ^OcuTalonTest("BreakFeedInProbe", "answer", seam): "" is OK (a close answers Ok 1, a trigger an
/// Ens.Response), "refuse" is a close answered Ok 0, "error" is an error status, and "none" is OK with no answer, as SendRequestSync
/// returns when its timeout runs out. LOCKWAIT is 1, so that a test of a
/// held lock does not wait for the real ten seconds. The product never refers to it.
Class OcuTalon.Test.Demo.BreakFeedInProbe Extends OcuTalon.Demo.BreakFeedIn
{

Parameter LOCKWAIT = 1;

Method Close(command As OcuTalon.Msg.IncidentCommand, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set result = ""
	Set n = ..Record("close", command.SessionRef)
	Set ^OcuTalonTest("BreakFeedInProbe", "calls", n, "verb") = command.Verb
	Set ^OcuTalonTest("BreakFeedInProbe", "calls", n, "ref") = command.IncidentRef
	Set ^OcuTalonTest("BreakFeedInProbe", "calls", n, "session") = command.SessionRef
	Set ^OcuTalonTest("BreakFeedInProbe", "calls", n, "origin") = command.Origin
	Set answer = $Get(^OcuTalonTest("BreakFeedInProbe", "answer", "close"))
	If answer = "error" Quit $SYSTEM.Status.Error(5001, "zz close failed")
	If answer = "none" Quit $SYSTEM.Status.OK()
	Set result = ##class(OcuTalon.Msg.CommandResult).%New()
	Set result.Ok = (answer '= "refuse")
	Set result.Outcome = $Select(answer = "refuse": "refused", 1: "closed")
	Quit $SYSTEM.Status.OK()
}

Method Trigger(request As OcuTalon.Demo.Msg.SendOrders, Output response As Ens.Response) As %Status [ Private ]
{
	Set response = ""
	Set n = ..Record("trigger", request.SessionRef)
	Set ^OcuTalonTest("BreakFeedInProbe", "calls", n, "session") = request.SessionRef
	Set ^OcuTalonTest("BreakFeedInProbe", "calls", n, "channel") = request.Channel
	Set answer = $Get(^OcuTalonTest("BreakFeedInProbe", "answer", "trigger"))
	If answer = "error" Quit $SYSTEM.Status.Error(5001, "zz trigger failed")
	If answer = "none" Quit $SYSTEM.Status.OK()
	Set response = ##class(Ens.Response).%New()
	Quit $SYSTEM.Status.OK()
}

/// Records a call of the seam, with the runs of the session and the SuperSession, and returns its number.
Method Record(seam As %String, sessionRef As %String) As %Integer [ Private ]
{
	Set n = $Increment(^OcuTalonTest("BreakFeedInProbe", "calls"))
	Set ^OcuTalonTest("BreakFeedInProbe", "calls", n) = seam
	Set ^OcuTalonTest("BreakFeedInProbe", "calls", n, "runs") = ..Runs(sessionRef)
	Set ^OcuTalonTest("BreakFeedInProbe", "calls", n, "superSession") = ..%SuperSession
	Quit n
}

/// The runs of the session as "<count>:<state>,<state>...", oldest first; "0:" when it has none.
ClassMethod Runs(sessionRef As %String) As %String
{
	Set states = ""
	Set count = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT State FROM OcuTalon_Data.BreakFeedRun WHERE SessionRef = ? ORDER BY ID", sessionRef)
	While result.%Next() {
		Set count = count + 1
		Set states = states_$Select(states = "": "", 1: ",")_result.%Get("State")
	}
	Quit count_":"_states
}

}
