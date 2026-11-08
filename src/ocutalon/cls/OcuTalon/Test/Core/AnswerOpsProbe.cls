/// A subclass of OcuTalon.Core.AnswerOps for the tests: its approval API is OcuTalon.Test.Core.ApprovalDouble, which answers a scripted
/// result and changes no row. Everything else, the sender check and the session lookup included, is the real one. SendPrecedent sends nothing:
/// it records each RecordPrecedent under ^OcuTalonTest("AnswerOpsPrecedent", <the ApprovalDouble run, else 0>, n, "ref" | "action" | "channel" | "sessionRef")
/// (the count at ("AnswerOpsPrecedent", run, "calls")) and answers as FailSend says: "" is OK, "error" is an error status and "throw" throws.
/// The product never refers to it.
Class OcuTalon.Test.Core.AnswerOpsProbe Extends OcuTalon.Core.AnswerOps
{

Parameter APPROVALAPI = "OcuTalon.Test.Core.ApprovalDouble";

/// "", "error" or "throw" for the precedent send.
Property FailSend As %String;

Method SendPrecedent(message As OcuTalon.Core.Msg.RecordPrecedent) As %Status [ Private ]
{
	Set run = $Get(^OcuTalonTest("ApprovalDouble", "run"), 0)
	Set n = $Increment(^OcuTalonTest("AnswerOpsPrecedent", run, "calls"))
	Set ^OcuTalonTest("AnswerOpsPrecedent", run, n, "ref") = message.ApprovalRef
	Set ^OcuTalonTest("AnswerOpsPrecedent", run, n, "action") = message.Action
	Set ^OcuTalonTest("AnswerOpsPrecedent", run, n, "channel") = message.Channel
	Set ^OcuTalonTest("AnswerOpsPrecedent", run, n, "sessionRef") = message.SessionRef
	If ..FailSend = "error" Quit $SYSTEM.Status.Error(5001, "zz the precedent send failed")
	If ..FailSend = "throw" Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "zz the precedent send threw"))
	Quit $$$OK
}

}
