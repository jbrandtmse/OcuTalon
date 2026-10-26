/// A FailurePoller whose read and send are under test control (test only; Story 5.2, matrix rows "Read or send error" and "Flood"). Test.Watch.Poller calls the
/// OnProcessInput of a shadow instance of it, in its own process:
///   - with no ^||PollerProbe("mode"), the private read seam throws, as a read that cannot be done does, and the poller must warn, keep the mark and still
///     answer OK;
///   - with the mode "rows", the read answers read with the rows of ^||PollerProbe("feed") (a JSON array of reader rows, in time order) from the stamp on, at
///     most the limit it is given (each call's limit is kept in ^||PollerProbe("limit", n)), and a send is kept in ^||PollerProbe("sent", n) as a list of its
///     target, OwnerRef, number of failures, first header id, SuperSession, SessionId and PolledAt instead of reaching a queue, or answers an error when
///     ^||PollerProbe("send") is "fail".
/// It is not an item of any production.
Class OcuTalon.Test.Watch.PollerProbe Extends OcuTalon.Watch.FailurePoller
{

/// The text of the failure.
Parameter FAILURE = "The probe's read fails.";

/// The text of the failure of a send.
Parameter SENDFAILURE = "The probe's send fails.";

Method Read(namespace As %String, production As %String, from As %String, limit As %Integer, Output rows As %DynamicArray) As %String [ Private ]
{
	Set rows = []
	If $Get(^||PollerProbe("mode")) '= "rows" $$$ThrowStatus($SYSTEM.Status.Error(5001, ..#FAILURE))
	Set ^||PollerProbe("limit", $Increment(^||PollerProbe("limit"))) = limit
	Set iterator = ##class(%DynamicArray).%FromJSON(^||PollerProbe("feed")).%GetIterator()
	While iterator.%GetNext(, .row) {
		If (rows.%Size() '< limit) Quit
		If '(from ] row.at) Do rows.%Push(row)
	}
	Quit "read"
}

Method SendRequestAsync(pTargetDispatchName As %String, pRequest As %Library.Persistent, pDescription As %String = "") As %Status
{
	If $Get(^||PollerProbe("mode")) '= "rows" Quit ##super(pTargetDispatchName, pRequest, pDescription)
	If $Get(^||PollerProbe("send")) = "fail" Quit $SYSTEM.Status.Error(5001, ..#SENDFAILURE)
	Set ^||PollerProbe("sent", $Increment(^||PollerProbe("sent"))) = $ListBuild(pTargetDispatchName, pRequest.OwnerRef, pRequest.Failures.Count(), pRequest.Failures.GetAt(1).HeaderId, ..%SuperSession, ..%SessionId, pRequest.PolledAt)
	Quit $$$OK
}

}
