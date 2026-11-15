Include Ensemble

/// A subclass of OcuTalon.Core.BridgeSink for the tests of the daily-cap message (Story 16.9) and of a tool call's notices (Story 31.5; AD-31): it keeps the real handlers and
/// overrides the private seams that reach outside, so that no production is needed and no notice is really sent. It has no Test
/// methods and the product never refers to it.
///   - Notice records each notification under ^OcuTalonTest("BridgeSinkNotice", "calls", n): sessionRef, kind, catalogKey, slots,
///     approvalRef, incidentRef and decisionRef,
///     with n counted in ^OcuTalonTest("BridgeSinkNotice", "calls"); after it records, it throws when ^OcuTalonTest("BridgeSinkNotice",
///     "throwNotice") is set, and answers an error status when ^OcuTalonTest("BridgeSinkNotice", "failNotice") is set;
///   - Registered answers the value of ^OcuTalonTest("BridgeSinkNotice", "registered", server) when that node exists, otherwise the real
///     Mcp.Server read;
///   - Visitors answers the list in ^OcuTalonTest("BridgeSinkNotice", "visitors") when that node exists, and an error status when
///     ^OcuTalonTest("BridgeSinkNotice", "failVisitors") is set, otherwise the real Ownership.ActiveVisitors read.
Class OcuTalon.Test.Core.BridgeSinkNoticeProbe Extends OcuTalon.Core.BridgeSink
{

ClassMethod Notice(notification As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("BridgeSinkNotice", "calls"))
	Set ^OcuTalonTest("BridgeSinkNotice", "calls", n, "sessionRef") = notification.SessionRef
	Set ^OcuTalonTest("BridgeSinkNotice", "calls", n, "kind") = notification.Kind
	Set ^OcuTalonTest("BridgeSinkNotice", "calls", n, "catalogKey") = notification.CatalogKey
	Set ^OcuTalonTest("BridgeSinkNotice", "calls", n, "slots") = notification.Slots
	Set ^OcuTalonTest("BridgeSinkNotice", "calls", n, "approvalRef") = notification.ApprovalRef
	Set ^OcuTalonTest("BridgeSinkNotice", "calls", n, "incidentRef") = notification.IncidentRef
	Set ^OcuTalonTest("BridgeSinkNotice", "calls", n, "decisionRef") = notification.DecisionRef
	If $Get(^OcuTalonTest("BridgeSinkNotice", "throwNotice")) Throw ##class(%Exception.General).%New("zz the probe's notice throws", 5001, , "zz the probe's notice throws")
	If $Get(^OcuTalonTest("BridgeSinkNotice", "failNotice")) Quit $SYSTEM.Status.Error(5001, "zz the probe's notice fails")
	Quit $SYSTEM.Status.OK()
}

ClassMethod Registered(server As %String) As %Boolean [ Private ]
{
	If $Data(^OcuTalonTest("BridgeSinkNotice", "registered", server)) Quit ''^OcuTalonTest("BridgeSinkNotice", "registered", server)
	Quit ##super(server)
}

ClassMethod Visitors(Output sc As %Status) As %List [ Private ]
{
	Set sc = $SYSTEM.Status.OK()
	If $Get(^OcuTalonTest("BridgeSinkNotice", "failVisitors")) {
		Set sc = $SYSTEM.Status.Error(5001, "zz the probe's visitors read fails")
		Quit ""
	}
	If $Data(^OcuTalonTest("BridgeSinkNotice", "visitors")) Quit ^OcuTalonTest("BridgeSinkNotice", "visitors")
	Quit ##super(.sc)
}

}
