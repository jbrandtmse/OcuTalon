/// The double of the approval API for the tests of AnswerOps (Story 6.2; AD-29): AnswerOpsProbe names it as its APPROVALAPI. Answer
/// returns the result scripted for the run (default done) with the winner shape of OcuTalon.Bridge.Approval.Answer, records every call's
/// arguments, and changes no row. The script and the record live under ^OcuTalonTest("ApprovalDouble", <run>), where the run is the
/// value that Begin set: "result" (the answer), "winner" (JSON; default the phone's approval for already_answered, {} otherwise) and
/// "calls" (the count) with "calls", n, "ref" | "action" | "channel" | "irisUser" | "sessionRef" for each call. MayAnswer (Story 25.5) answers
/// 1 with an empty kind unless the run scripts the request's Ref: May(ref, result, kind) scripts a fixed answer, and Kind(ref, kind) scripts the
/// step 6 rule over real roles (1 when the IRIS user's recursed role set holds the row's RequiredRole or RequiredRole_<kind>, else 0 with the kind).
/// Every MayAnswer call of a run is recorded under "mayCalls" (the count) with "mayCalls", n, "ref" | "irisUser". The product never refers to it.
Class OcuTalon.Test.Core.ApprovalDouble
{

/// Ends the run before it (End) and starts a run whose Answer returns the result, with an empty record. Returns the run.
ClassMethod Begin(result As %String = "done", winner As %String = "") As %String
{
	Do ..End()
	Set run = $Increment(^OcuTalonTest("ApprovalDouble", "n"))
	Set ^OcuTalonTest("ApprovalDouble", "run") = run
	Kill ^OcuTalonTest("ApprovalDouble", run)
	Set ^OcuTalonTest("ApprovalDouble", run, "result") = result
	If winner '= "" Set ^OcuTalonTest("ApprovalDouble", run, "winner") = winner
	Quit run
}

/// Removes the run, the RecordPrecedent record that AnswerOpsProbe kept for it, and the pointer to it.
ClassMethod End()
{
	Set run = $Get(^OcuTalonTest("ApprovalDouble", "run"))
	If run '= "" Kill ^OcuTalonTest("ApprovalDouble", run), ^OcuTalonTest("AnswerOpsPrecedent", run)
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

/// The double of Approval.MayAnswer. It records the call; with no run, or no script for the ref, it answers 1 with kind "" (so that a test whose fixture sessions name no real IRIS user
/// keeps its results), else the scripted answer.
ClassMethod MayAnswer(ref As %String, irisUser As %String, Output kind As %String) As %Boolean
{
	Set kind = ""
	Set run = $Get(^OcuTalonTest("ApprovalDouble", "run"))
	If run = "" Quit 1
	Set n = $Increment(^OcuTalonTest("ApprovalDouble", run, "mayCalls"))
	Set ^OcuTalonTest("ApprovalDouble", run, "mayCalls", n, "ref") = ref
	Set ^OcuTalonTest("ApprovalDouble", run, "mayCalls", n, "irisUser") = irisUser
	Set script = $Get(^OcuTalonTest("ApprovalDouble", run, "may", ref))
	If script = "" Quit 1
	If $List(script, 1) = "fixed" {
		Set kind = $List(script, 3)
		Quit $List(script, 2)
	}
	Set kind = $List(script, 2)
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If '$IsObject(row) Quit 0
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet(irisUser, .roles)
	If $$$ISERR(sc) Quit 0
	Set held = $ListFromString(roles)
	If $ListFind(held, row.RequiredRole) || $ListFind(held, row.RequiredRole_"_"_kind) Quit 1
	Quit 0
}

/// Scripts MayAnswer's answer for the request ref in the current run: result (1 or 0) and the kind it names.
ClassMethod May(ref As %String, result As %Boolean, kind As %String = "")
{
	Set ^OcuTalonTest("ApprovalDouble", $Get(^OcuTalonTest("ApprovalDouble", "run")), "may", ref) = $ListBuild("fixed", +result, kind)
}

/// Scripts MayAnswer for the request ref in the current run as the step 6 rule over real roles, for the approver kind.
ClassMethod Kind(ref As %String, kind As %String)
{
	Set ^OcuTalonTest("ApprovalDouble", $Get(^OcuTalonTest("ApprovalDouble", "run")), "may", ref) = $ListBuild("roles", kind)
}

/// The number of MayAnswer calls in the current run.
ClassMethod MayCalls() As %Integer
{
	Quit +$Get(^OcuTalonTest("ApprovalDouble", $Get(^OcuTalonTest("ApprovalDouble", "run")), "mayCalls"))
}

/// The argument (ref or irisUser) of MayAnswer call n of the current run.
ClassMethod MayArg(n As %Integer, name As %String) As %String
{
	Quit $Get(^OcuTalonTest("ApprovalDouble", $Get(^OcuTalonTest("ApprovalDouble", "run")), "mayCalls", n, name))
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
