/// A subclass of OcuTalon.Schedule.ReminderOps for the tests, which keeps the real private seam StartWaiter and overrides the send it
/// makes, SendRequestSync: nothing is sent. The send records the target, the request's Ref, the timeout and this operation's session id
/// and SuperSession as they are at the call, and then does what Mode says (ok: answers a response; noanswer: answers OK with no response;
/// error: answers an error status; throw: throws). Start calls the seam, which is private. The product never refers to it.
Class OcuTalon.Test.Schedule.ReminderOpsSendProbe Extends OcuTalon.Schedule.ReminderOps
{

/// What the send does: ok, noanswer, error or throw.
Property Mode As %String [ InitialExpression = "ok" ];

/// What the send saw, as an object {target, ref, timeout, sessionId, superSession}, or "" before a call.
Property Seen As %DynamicObject;

/// Runs the real seam for the row.
Method Start(row As OcuTalon.Data.Reminder) As %Status
{
	Quit ..StartWaiter(row)
}

Method SendRequestSync(pTargetDispatchName As %String, pRequest As %Library.Persistent, ByRef pResponse As %Library.Persistent, pTimeout As %Numeric = -1, pDescription As %String = "") As %Status
{
	Set ..Seen = {"target": (pTargetDispatchName), "ref": (pRequest.Ref), "timeout": (pTimeout), "sessionId": (..%SessionId), "superSession": (..%SuperSession)}
	If ..Mode = "throw" Throw ##class(%Exception.General).%New("zz the send threw")
	If ..Mode = "error" Quit $SYSTEM.Status.Error(5001, "zz the send failed")
	Set pResponse = $Select(..Mode = "ok": ##class(Ens.Response).%New(), 1: "")
	Quit $$$OK
}

}
