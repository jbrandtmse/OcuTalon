/// A subclass of OcuTalon.Core.BridgeSink for the tests: both of its handlers throw, so that a test can see OnEvent return OK
/// and log a warning when a handler fails, and its recipients read always fails, so that a test can see an approval event
/// publish nothing and log a warning. It adds nothing to the product's surface; the product never refers to it.
Class OcuTalon.Test.Core.BridgeSinkProbe Extends OcuTalon.Core.BridgeSink
{

/// The decision.recorded handler, as the subclass sees it: it throws.
ClassMethod Recorded(ownerRef As %String, payload As %DynamicObject) [ Private ]
{
	Throw ##class(%Exception.General).%New("ZzSinkProbe", 5001, , "the probe's decision handler fails")
}

/// The turn.step handler, as the subclass sees it: it throws.
ClassMethod Step(ownerRef As %String, payload As %DynamicObject) [ Private ]
{
	Throw ##class(%Exception.General).%New("ZzSinkProbe", 5001, , "the probe's step handler fails")
}

/// The recipients seam, as the subclass sees it: the read fails.
ClassMethod Recipients(ownerRef As %String, incidentRef As %String, Output sc As %Status) As %List [ Private ]
{
	Set sc = $SYSTEM.Status.Error(5001, "zz the watchers could not be read")
	Quit ""
}

}
