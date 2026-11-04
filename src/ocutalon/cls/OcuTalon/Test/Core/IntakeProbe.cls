/// A subclass of OcuTalon.Core.Intake for the tests, which overrides its private send seam so that the unit tests run on a slot
/// with no production (Story 2.7; AD-22). It has no Test methods and the product never refers to it. It adds only transient
/// properties. The recording of each call under ^OcuTalonTest("IntakeProbe", RunNumber, n), the answers of the Decide double
/// and Deliver, which hands the kept answers to OnError and OnResponse with the Item as the original request, are those of
/// Test.Core.ProbeSeam.
///   - Send records each call (target, class, key, required and the trace session the instance had set); for a Bridge.Msg.Request
///     the request's fields; for an ItemDecision itemId, sourceItemId, ownerRef, channel, summary, decisionRef, outcome,
///     fallback, fallbackReason, catalogKey and slots. A request to Decide goes to a shadow instance of Test.Core.DecideDouble and
///     its answer is kept; a send to any other target is recorded only. FailTarget names a target whose send fails, and FailKey a
///     completion key whose send fails (turn, for the send of the untrusted turn). ThrowIn makes Decided (decided) throw, for the
///     test of a failure inside the class.
Class OcuTalon.Test.Core.IntakeProbe Extends (OcuTalon.Core.Intake, OcuTalon.Test.Core.ProbeSeam)
{

/// The first subscript of the probe's records.
Parameter ROOT = "IntakeProbe";

/// The completion key whose send fails with an error status.
Property FailKey As %String [ Transient ];

/// The method that throws: decided (the decide answer), or empty for none.
Property ThrowIn As %String [ Transient ];

/// The Item is kept as the original request that Deliver hands to the callbacks.
Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Set ..Original = $Get(request)
	Quit ##super(request, .response)
}

Method Decided(item As OcuTalon.Msg.Item, answer As %RegisteredObject) As %Status [ Private ]
{
	If ..ThrowIn = "decided" Throw ##class(%Exception.General).%New("zz decided threw", 5001, , "zz decided threw")
	Quit ##super(item, answer)
}

Method Send(target As %String, request As %Library.Persistent, responseRequired As %Boolean, key As %String) As %Status [ Private ]
{
	Set call = ..Record(target, $ClassName(request), key, responseRequired)
	If request.%Extends("OcuTalon.Bridge.Msg.Request") {
		Do ..RecordRequest(call, request)
	} ElseIf request.%Extends("OcuTalon.Msg.ItemDecision") {
		Set @call@("itemId") = request.ItemId
		Set @call@("sourceItemId") = request.SourceItemId
		Set @call@("ownerRef") = request.OwnerRef
		Set @call@("channel") = request.Channel
		Set @call@("summary") = request.Summary
		Set @call@("decisionRef") = request.DecisionRef
		Set @call@("outcome") = request.Outcome
		Set @call@("fallback") = request.Fallback
		Set @call@("fallbackReason") = request.FallbackReason
		Set @call@("catalogKey") = request.CatalogKey
		Set @call@("slots") = request.Slots
	}
	If (..FailTarget '= "") && (target = ..FailTarget) Quit $SYSTEM.Status.Error(5001, "zz send to "_target_" failed")
	If (..FailKey '= "") && (key = ..FailKey) Quit $SYSTEM.Status.Error(5001, "zz send with the key "_key_" failed")
	If target '= ..#DECIDE Quit $SYSTEM.Status.OK()
	Quit ..AskDecide(request, key)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
