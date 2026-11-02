Include Ensemble

/// A subclass of OcuTalon.Core.BridgeSink for the end-to-end tests of the daily-cap message (QA, Story 16.9; AD-31): it keeps the real
/// handlers and the real Notice seam (NoticesIn.Send, so the notice goes through the running production) and overrides only Visitors,
/// so that a test writes the daily-cap day of its own fixture sessions and no other open session of the instance. It has no Test
/// methods and the product never refers to it.
///   - Visitors answers the list in ^OcuTalonTest("BridgeSinkVisitors", "visitors"), and nobody when the node is not set.
Class OcuTalon.Test.Core.BridgeSinkVisitorsProbe Extends OcuTalon.Core.BridgeSink
{

ClassMethod Visitors(Output sc As %Status) As %List [ Private ]
{
	Set sc = $SYSTEM.Status.OK()
	Quit $Get(^OcuTalonTest("BridgeSinkVisitors", "visitors"))
}

}
