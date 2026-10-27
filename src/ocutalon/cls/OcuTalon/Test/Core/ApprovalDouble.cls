/// The double of the approval API for the tests of AnswerOps (Story 6.2; AD-29): AnswerOpsProbe names it as its APPROVALAPI. Answer
/// returns the result scripted for the run (default done) with the winner shape of OcuTalon.Bridge.Approval.Answer, records every call's
/// arguments, and changes no row. The script and the record live under ^OcuTalonTest("ApprovalDouble", <run>), where the run is the
/// value that Begin set: "result" (the answer), "winner" (JSON; default the phone's approval for already_answered, {} otherwise) and
/// "calls" (the count) with "calls", n, "ref" | "action" | "channel" | "irisUser" | "sessionRef" for each call. The product never
/// refers to it.
Class OcuTalon.Test.Core.ApprovalDouble
{

/// Starts a run whose Answer returns the result, and clears the record. Returns the run.
ClassMethod Begin(result As %String = "done", winner As %String = "") As %String
{
	Set run = $Increment(^OcuTalonTest("ApprovalDouble", "n"))
	Set ^OcuTalonTest("ApprovalDouble", "run") = run
	Kill ^OcuTalonTest("ApprovalDouble", run)
	Set ^OcuTalonTest("ApprovalDouble", run, "result") = result
	If winner '= "" Set ^OcuTalonTest("ApprovalDouble", run, "winner") = winner
	Quit run
}

/// Removes the run and the pointer to it.
ClassMethod End()
{
	Set run = $Get(^OcuTalonTest("ApprovalDouble", "run"))
	If run '= "" Kill ^OcuTalonTest("ApprovalDouble", run)
	Kill ^OcuTalonTest("ApprovalDouble", "run")
}

/// The scripted answer; the arguments are recorded.
ClassMethod Answer(ref As %String, action As %String, channel As %String, irisUser As %String, sessionRef As %String, Output winner As %DynamicObject, sinkClass As %String = "") As %String
{
	Set run = $Get(^OcuTalonTest("ApprovalDouble", "run"))
	Set result = $Get(^OcuTalonTest("ApprovalDouble", run, "result"), "done")
	Set n = $Increment(^OcuTalonTest("ApprovalDouble", run, "calls"))
	Set ^OcuTalonTest("ApprovalDouble", run, "calls", n, "ref") = ref
	Set ^OcuTalonTest("ApprovalDouble", run, "calls", n, "action") = action
	Set ^OcuTalonTest("ApprovalDouble", run, "calls", n, "channel") = channel
	Set ^OcuTalonTest("ApprovalDouble", run, "calls", n, "irisUser") = irisUser
	Set ^OcuTalonTest("ApprovalDouble", run, "calls", n, "sessionRef") = sessionRef
	Set winner = {}
	If result = "already_answered" {
		Set text = $Get(^OcuTalonTest("ApprovalDouble", run, "winner"), "{""action"":""approve"",""channel"":""phone"",""at"":""2030-01-01T14:15:00Z""}")
		Set winner = {}.%FromJSON(text)
	}
	Quit result
}

/// The number of calls in the current run.
ClassMethod Calls() As %Integer
{
	Quit +$Get(^OcuTalonTest("ApprovalDouble", $Get(^OcuTalonTest("ApprovalDouble", "run")), "calls"))
}

/// The argument (ref, action, channel, irisUser or sessionRef) of call n of the current run.
ClassMethod Arg(n As %Integer, name As %String) As %String
{
	Quit $Get(^OcuTalonTest("ApprovalDouble", $Get(^OcuTalonTest("ApprovalDouble", "run")), "calls", n, name))
}

}
