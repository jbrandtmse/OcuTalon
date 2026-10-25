Include Ensemble

/// Tests of the guide refresh in StatusMonitor's tick (Story 4.2; matrix row 16; AD-12, AD-18), the integration of the tick with
/// Live.Publish.RefreshGuide and Demo.Guide. They drive a shadow instance of Test.Core.StatusMonitorProbe with fixed readings and a
/// private status stream, so that nothing is published on the instance stream, and fixture sessions (zzstatguide<n>) with an Orders
/// check and a Break the feed run started some seconds before the real clock:
///   - TestTickPublishesTheClockStages: a run 100 s old gets still_waiting at the first run of the monitor, nothing at the second, and
///     no_notice once the run is 200 s old;
///   - TestOldRunIsNotRefreshed: a run 300 s old is not refreshed;
///   - TestWindowEdges: the window is 240 s: a run 230 s old is refreshed and one 250 s old is not;
///   - TestDemoOffDoesNothing: with demo mode off the tick publishes nothing.
/// demo.mode is saved before the tests and put back after them.
Class OcuTalon.Test.Core.StatusMonitorGuide Extends %UnitTest.TestCase
{

Parameter NS = "OCUORDERS";

Parameter PROD = "OcuTalon.Demo.Orders.Production";

/// The run's number.
Property Number As %Integer;

/// The fixture session whose stream is the monitor's private status stream.
Property Stream As %String;

Property SavedModeFound As %Boolean;

Property SavedModeValue As %String(MAXLEN = 1000);

Property SavedModeUpdatedAt As %String(MAXLEN = 20);

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("StatusMonitorGuide", "n"))
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set ..SavedModeFound = found, ..SavedModeValue = value, ..SavedModeUpdatedAt = updatedAt
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, ##class(OcuTalon.Data.Time).NowUtc())
	Set ..Stream = ##class(OcuTalon.Test.Data.Fixture).Session("zzstatguide"_..Number)
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..SavedModeFound, ..SavedModeValue, ..SavedModeUpdatedAt)
	Quit $SYSTEM.Status.OK()
}

/// A run 100 s old: the first run of the monitor publishes still_waiting, the second nothing, and a run now 200 s old no_notice.
Method TestTickPublishesTheClockStages()
{
	Set ref = ..WatchingSession(100)
	Set probe = ..Probe()
	Do $$$AssertStatusOK(probe.OnProcessInput($$$NULLOREF, .output), "the first run returns OK")
	Set events = ..GuideEvents(ref)
	Do $$$AssertEquals(events.%Size(), 1, "the first run publishes one guide.state")
	Do $$$AssertEquals(events.%Get(0).payload.breakFeed.stage_"|"_events.%Get(0).payload.breakFeed.active, "still_waiting|0", "still_waiting, with Break the feed unavailable")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..GuideEvents(ref).%Size(), 1, "a second run publishes nothing")

	Set run = ##class(OcuTalon.Data.Ownership).LatestBreakFeedRun(ref, .sc)
	Set run.StartedAt = ..SecondsAgo(200)
	Do $$$AssertStatusOK(run.%Save(), "the run is 200 s old")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set events = ..GuideEvents(ref)
	Do $$$AssertEquals(events.%Size(), 2, "the next run publishes the new stage")
	Do $$$AssertEquals(events.%Get(1).payload.breakFeed.stage_"|"_events.%Get(1).payload.breakFeed.active, "no_notice|1", "no_notice, with Break the feed available")
}

/// A run 300 s old is past the tick's window: nothing is refreshed for its session.
Method TestOldRunIsNotRefreshed()
{
	Set ref = ..WatchingSession(300)
	Set probe = ..Probe()
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..GuideEvents(ref).%Size(), 0, "no guide.state for a run 300 s old")
}

/// The window is GUIDESECONDS (240 s): a run 230 s old is refreshed, a run 250 s old is not.
Method TestWindowEdges()
{
	Set ref = ..WatchingSession(230)
	Set probe = ..Probe()
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set events = ..GuideEvents(ref)
	Do $$$AssertEquals(events.%Size(), 1, "a run 230 s old is refreshed")
	Do $$$AssertEquals(events.%Get(0).payload.breakFeed.stage, "no_notice", "no_notice")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ref = ..WatchingSession(250)
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..GuideEvents(ref).%Size(), 0, "a run 250 s old is not")
}

/// With demo mode off the tick publishes nothing.
Method TestDemoOffDoesNothing()
{
	Set ref = ..WatchingSession(100)
	Do ##class(OcuTalon.Test.Demo.Step).Put(0, ##class(OcuTalon.Data.Time).NowUtc())
	Set probe = ..Probe()
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..GuideEvents(ref).%Size(), 0, "no guide.state with demo mode off")
}

/// A fixture session that watches Orders and whose Break the feed run started that many seconds ago.
Method WatchingSession(age As %Integer) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzstatguide"_..Number)
	Do ##class(OcuTalon.Test.Data.Fixture).Check(ref, ..#NS, ..#PROD)
	Do ##class(OcuTalon.Test.Data.Fixture).BreakFeedRun(ref, "sent", ..SecondsAgo(age))
	Quit ref
}

/// The shadow monitor with fixed readings and the private status stream.
Method Probe() As OcuTalon.Test.Core.StatusMonitorProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.StatusMonitorProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.StreamRef = ..Stream
	Set probe.KeysReading = {"TriageAgent": 1, "DiagnosisAgent": 1, "ChatAgent": 1}
	Set probe.BudgetReading = {"spent": 0, "cap": 0, "resetsAt": "", "capped": false}
	Quit probe
}

/// The guide.state events of the session's stream.
Method GuideEvents(ref As %String) As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(ref, "guide.state")
}

/// The UTC time that many seconds before now.
ClassMethod SecondsAgo(seconds As %Integer) As %String [ Private ]
{
	Set now = $ZTimeStamp
	Set total = ($Piece(now, ",", 1) * 86400) + $Piece(now, ",", 2) - seconds
	Quit $Translate($ZDateTime((total \ 86400)_","_(total # 86400), 3, 1), " ", "T")_"Z"
}

}
