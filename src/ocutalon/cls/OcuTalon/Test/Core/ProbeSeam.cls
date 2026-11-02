/// The recording and delivery that the probes of the business processes share (Story 2.7; Test.Core.ConversationProbe and
/// Test.Core.IntakeProbe extend their process and this class). It has no Test methods and the product never refers to it.
/// A probe overrides the process's private send seam, calls Record for each send, and for a request to Decide calls AskDecide:
///   - Record keeps a call under ^OcuTalonTest(<ROOT>, RunNumber, n), with n counted in ^OcuTalonTest(<ROOT>, RunNumber): target,
///     class, key, required and the trace session the instance had set (sessionId, superSession); RecordRequest adds, for a
///     Bridge.Msg.Request, kind, provenance, input, itemId, summary, ownerRef, traceRef, channel, threadSessionId, sessionMode and
///     seedText;
///   - AskDecide hands a request to a shadow instance of Test.Core.DecideDouble and keeps its answer;
///   - Deliver hands the kept answers, in the order they were sent, to OnError and OnResponse as the framework does: an answer
///     that is an error status goes to OnError and then to OnResponse with no answer; any other answer goes to OnResponse; the
///     end of a wait (an entry of three items) goes to OnResponse as an Ens.AlarmResponse. The original request that the
///     callbacks get is Original ("" for none).
/// FailTarget names a target whose send fails.
Class OcuTalon.Test.Core.ProbeSeam Extends %RegisteredObject [ Abstract ]
{

/// The first subscript of the probe's records: ^OcuTalonTest(<ROOT>, RunNumber, n). The probe class sets it.
Parameter ROOT;

/// The subscript of the run under ^OcuTalonTest(<ROOT>).
Property RunNumber As %String [ Transient ];

/// The target whose send fails with an error status.
Property FailTarget As %String [ Transient ];

/// The request that OnError and OnResponse get as the original request.
Property Original As %RegisteredObject [ Transient ];

/// The kept answers: Pending(n) = $ListBuild(key, status), Pending(n, "response") = the answer object.
Property Pending [ MultiDimensional, Transient ];

/// Records a call and returns the global reference of its record.
Method Record(target As %String, class As %String, key As %String, required As %Boolean) As %String [ Private ]
{
	Set n = $Increment(^OcuTalonTest(..#ROOT, ..RunNumber))
	Set call = $Name(^OcuTalonTest(..#ROOT, ..RunNumber, n))
	Set @call@("target") = target
	Set @call@("class") = class
	Set @call@("key") = key
	Set @call@("required") = required
	Set @call@("sessionId") = ..%SessionId
	Set @call@("superSession") = ..%SuperSession
	Quit call
}

/// Records the fields of a request to Decide in the call's record.
Method RecordRequest(call As %String, request As OcuTalon.Bridge.Msg.Request) [ Private ]
{
	Set @call@("kind") = request.Kind
	Set @call@("provenance") = request.Provenance
	Set @call@("input") = request.Input
	Set @call@("itemId") = request.ItemId
	Set @call@("summary") = request.Summary
	Set @call@("ownerRef") = request.OwnerRef
	Set @call@("traceRef") = request.TraceRef
	Set @call@("channel") = request.Channel
	Set @call@("threadSessionId") = request.ThreadSessionId
	Set @call@("sessionMode") = request.SessionMode
	Set @call@("seedText") = request.SeedText
}

/// Hands the request to a shadow instance of the Decide double and keeps its answer under the key.
Method AskDecide(request As OcuTalon.Bridge.Msg.Request, key As %String) As %Status [ Private ]
{
	Set double = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.DecideDouble", .sc)
	If '$IsObject(double) Quit sc
	Set sc = double.OnRequest(request, .response)
	Set n = $Increment(..Pending)
	Set ..Pending(n) = $ListBuild(key, sc)
	If $IsObject($Get(response)) Set ..Pending(n, "response") = response
	Quit $SYSTEM.Status.OK()
}

/// Hands the kept answers to the callbacks, oldest first, until none is left or max have been handed (0 for all); answers that
/// the callbacks send in turn are handed too. Returns the number handed.
Method Deliver(max As %Integer = 0) As %Integer
{
	Set count = 0
	While (max = 0) || (count < max) {
		Set n = $Order(..Pending(""))
		If n = "" Quit
		Set entry = ..Pending(n)
		Set response = $Get(..Pending(n, "response"))
		Kill ..Pending(n)
		Set count = count + 1
		Set key = $List(entry, 1)
		Set sc = $List(entry, 2)
		If $ListLength(entry) > 2 {
			Do ..OnResponse(..Original, , "", ##class(Ens.AlarmResponse).%New(), key)
		} ElseIf $SYSTEM.Status.IsError(sc) {
			Do ..OnError(..Original, , "", sc, key)
			Do ..OnResponse(..Original, , "", "", key)
		} Else {
			Do ..OnResponse(..Original, , "", response, key)
		}
	}
	Quit count
}

/// The number of answers kept and not yet handed.
Method PendingCount() As %Integer
{
	Set count = 0
	Set n = ""
	For {
		Set n = $Order(..Pending(n))
		Quit:n=""
		Set count = count + 1
	}
	Quit count
}

}
