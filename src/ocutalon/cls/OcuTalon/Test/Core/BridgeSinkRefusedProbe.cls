/// A subclass of OcuTalon.Core.BridgeSink for the tests: its recipients seam names the owner eval first, whose read
/// Ownership refuses, and then the owner itself, so that a test can see the failed read of one recipient log a warning while
/// the next recipient still gets the event. It adds nothing to the product's surface; the product never refers to it.
Class OcuTalon.Test.Core.BridgeSinkRefusedProbe Extends OcuTalon.Core.BridgeSink
{

/// The recipients seam, as the subclass sees it: eval, then the owner.
ClassMethod Recipients(ownerRef As %String, incidentRef As %String, Output sc As %Status) As %List [ Private ]
{
	Set sc = $SYSTEM.Status.OK()
	Quit $ListBuild(##class(OcuTalon.Data.Ownership).#EVAL, ownerRef)
}

}
