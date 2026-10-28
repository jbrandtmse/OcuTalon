/// A subclass of OcuTalon.Schedule.ReminderOps for the tests, which keeps the real private seams and overrides the two sends they make,
/// SendRequestSync (the waiter's start) and SendRequestAsync (the interrupt of a cancelled reminder's waiter): nothing is sent. The sync
/// send records the target, the request's Ref, the timeout and this operation's session id and SuperSession as they are at the call in
/// Seen; the async send records the target, the request's AlarmHandle and the same two ids in SeenAsync, one entry per call. Each then does
/// what Mode says (ok: answers a response, or OK; noanswer: answers OK with no response; error: answers an error status; throw: throws).
/// Start calls the start seam, which is private; OnMessage runs the real verbs. The product never refers to it.
Class OcuTalon.Test.Schedule.ReminderOpsSendProbe Extends OcuTalon.Schedule.ReminderOps
{

/// What the send does: ok, noanswer, error or throw.
Property Mode As %String [ InitialExpression = "ok" ];

/// What the send saw, as an object {target, ref, timeout, sessionId, superSession}, or "" before a call.
Property Seen As %DynamicObject;

/// What the async sends saw, an array of {target, handle, sessionId, superSession}, one per call.
Property SeenAsync As %DynamicArray [ InitialExpression = {[]} ];

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

Method SendRequestAsync(pTargetDispatchName As %String, pRequest As %Library.Persistent, pDescription As %String = "") As %Status
{
	Do ..SeenAsync.%Push({"target": (pTargetDispatchName), "handle": (pRequest.AlarmHandle), "sessionId": (..%SessionId), "superSession": (..%SuperSession)})
	If ..Mode = "throw" Throw ##class(%Exception.General).%New("zz the send threw")
	If ..Mode = "error" Quit $SYSTEM.Status.Error(5001, "zz the send failed")
	Quit $$$OK
}

}
