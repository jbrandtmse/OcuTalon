/// Tests of the heartbeat-stalled condition on the real heartbeat (Story 8.2; FR-32, AD-12, AD-18, AD-33). THESE TESTS RUN IN THROWAWAY STACKS
/// AND IN CI ONLY (Rule 21), like Test.Schedule.Heartbeat: they suspend the real task, move the tick mark of the running production and wait
/// for the production's own StatusMonitor job, so OnBeforeAllTests fails with the reason where the production does not run. Test.Schedule.StallFixture
/// does the stalling, across processes, and every test ends with Release, so that the task is as found and the mark is fresh.
///   - TestStateAndMonitor (AC 1): with the tick mark 240 s back, Web.Api.StateBody holds exactly one heartbeatStalled member, active, with the mark
///     as its time, and StatusMonitor's job publishes that payload on the instance stream; after a real tick StateBody holds none at once and the job
///     publishes the clear, with no heartbeatStalled event between the two. The only test that stalls, and it waits for its own clear;
///   - TestNoTickIsOff (AC 1): with no tick mark StateBody holds no heartbeatStalled;
///   - TestReading: Heartbeat.Reading holds the tick mark and the current time;
///   - TestReleaseLeavesFresh: Release puts the task back as found, kills the fixture's node and leaves a mark that is at most 5 s old.
/// The fixture sessions are zzstall<n>; their events and counters are removed before and after.
Class OcuTalon.Test.Schedule.Stalled Extends %UnitTest.TestCase
{

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter TASK = "OcuTalon heartbeat";

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set reason = $ClassMethod(..#FIXTURE, "RunningReason")
	If reason '= "" Quit $SYSTEM.Status.Error(5001, reason)
	If $Data(^OcuTalonTest("StallFixture")) Do ##class(OcuTalon.Test.Schedule.StallFixture).Release()
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("Stalled", "n"))
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Quit ##class(OcuTalon.Test.Schedule.StallFixture).Release()
}

Method OnAfterAllTests() As %Status
{
	Set sc = ##class(OcuTalon.Test.Schedule.StallFixture).Release()
	Do ..Clean()
	Quit sc
}

/// AC 1. The onset and the clear, on the real task, the real tick mark and StatusMonitor's real job.
Method TestStateAndMonitor()
{
	Set session = ##class(OcuTalon.Data.Session).ForUser("zzstall"_..Number, .sc)
	Do $$$AssertStatusOK(sc, "the fixture session is made")
	Set since = ##class(OcuTalon.Test.Schedule.StallFixture).InstanceSeq()
	Set mark = ##class(OcuTalon.Test.Schedule.StallFixture).Hold(240)
	Do $$$AssertEquals(mark, ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Schedule.Heartbeat).#TICKMARK), "Hold returns the tick mark")
	Do $$$AssertEquals($ZAbs(##class(OcuTalon.Data.Time).Seconds(##class(OcuTalon.Data.Time).NowUtc()) - ##class(OcuTalon.Data.Time).Seconds(mark) - 240) < 5, 1, "which is 240 s back")

	Set expected = {"condition": "heartbeatStalled", "active": true, "slots": {"time": (mark)}}.%ToJSON()
	Set members = ..Members(##class(OcuTalon.Web.Api).StateBody(session))
	Do $$$AssertEquals(members.%Size(), 1, "StateBody holds exactly one heartbeatStalled member")
	Do $$$AssertEquals(members.%Get(0).%ToJSON(), expected, "active, with the mark as its time")

	Set seqOn = ##class(OcuTalon.Test.Schedule.StallFixture).WaitEvent(since, 1, 30)
	Do $$$AssertTrue(seqOn > 0, "StatusMonitor publishes the onset within 30 s")
	Set events = ..Events(since)
	Do $$$AssertEquals(..Payloads(events, 1), expected, "the onset's payload is the condition with the mark as its time")

	Do $$$AssertStatusOK(##class(OcuTalon.Test.Schedule.StallFixture).Tick(), "a real tick is written")
	Do $$$AssertEquals(..Members(##class(OcuTalon.Web.Api).StateBody(session)).%Size(), 0, "StateBody holds no heartbeatStalled at once")

	Set seqOff = ##class(OcuTalon.Test.Schedule.StallFixture).WaitEvent(seqOn, 0, 30)
	Do $$$AssertTrue(seqOff > 0, "StatusMonitor publishes the clear within 30 s")
	Set events = ..Events(since)
	Do $$$AssertEquals(..Payloads(events, 0), "{""condition"":""heartbeatStalled"",""active"":false}", "the clear's payload carries no slots")
	Do $$$AssertEquals(..Count(events, since, seqOn), 0, "no heartbeatStalled event lies before the onset")
	Do $$$AssertEquals(..Count(events, seqOn, seqOff), 0, "and none between the onset and the clear")
}

/// AC 1. Never ticked: the condition is off.
Method TestNoTickIsOff()
{
	Set session = ##class(OcuTalon.Data.Session).ForUser("zzstall"_..Number, .sc)
	Do $$$AssertStatusOK(sc, "the fixture session is made")
	Set mark = ##class(OcuTalon.Test.Schedule.StallFixture).Hold("")
	Do $$$AssertEquals(mark, "", "no tick mark")
	Do $$$AssertEquals(..Members(##class(OcuTalon.Web.Api).StateBody(session)).%Size(), 0, "StateBody holds no heartbeatStalled")
	Set conditions = ##class(OcuTalon.Live.Payload.Status).Computed({}, {})
	Do $$$AssertEquals(conditions.GetAt(3).Condition_"|"_conditions.GetAt(3).Active, "heartbeatStalled|0", "and Computed gives it inactive")
}

/// Reading is the tick mark and the current time.
Method TestReading()
{
	Set mark = ##class(OcuTalon.Test.Schedule.StallFixture).Hold(100)
	Set reading = ##class(OcuTalon.Schedule.Heartbeat).Reading()
	Do $$$AssertEquals($ClassName(reading), "%Library.DynamicObject", "Reading is an object")
	Do $$$AssertEquals(reading.lastTick, mark, "lastTick is the tick mark")
	Set apart = ##class(OcuTalon.Data.Time).Seconds(##class(OcuTalon.Data.Time).NowUtc()) - ##class(OcuTalon.Data.Time).Seconds(reading.now)
	Do $$$AssertTrue((apart >= 0) && (apart <= 2), "now is the current time, within 2 s")
}

/// Release leaves the task as found, the fixture's node gone and a fresh mark.
Method TestReleaseLeavesFresh()
{
	Set found = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(..#TASK)).Suspended
	Do ##class(OcuTalon.Test.Schedule.StallFixture).Hold(100)
	Do $$$AssertEquals(##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(..#TASK)).Suspended, 1, "Hold suspends the task")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Schedule.StallFixture).Release(), "Release succeeds")
	Set mark = ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Schedule.Heartbeat).#TICKMARK)
	Set age = ##class(OcuTalon.Data.Time).Seconds(##class(OcuTalon.Data.Time).NowUtc()) - ##class(OcuTalon.Data.Time).Seconds(mark)
	Do $$$AssertTrue((mark '= "") && (age >= 0) && (age <= 5), "the mark is at most 5 s old")
	Do $$$AssertEquals(##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(..#TASK)).Suspended, found, "the task's Suspended is the value found")
	Do $$$AssertEquals($Data(^OcuTalonTest("StallFixture")), 0, "the fixture's node is gone")
}

/// The heartbeatStalled members of a snapshot's status array.
ClassMethod Members(body As %DynamicObject) As %DynamicArray [ Private ]
{
	Set members = []
	Set iterator = body.status.%GetIterator()
	While iterator.%GetNext(, .condition) {
		If condition.condition = "heartbeatStalled" Do members.%Push(condition)
	}
	Quit members
}

/// The status events of the instance stream after a Seq.
ClassMethod Events(after As %Integer) As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Live.Event).Since(##class(OcuTalon.Live.Publish).#INSTANCE, after, 200, "instance")
}

/// The JSON of the first heartbeatStalled status event with that active, or "".
ClassMethod Payloads(events As %DynamicArray, active As %Boolean) As %String [ Private ]
{
	Set iterator = events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If (event.type = "status") && (event.payload.condition = "heartbeatStalled") && (+event.payload.active = +active) Return event.payload.%ToJSON()
	}
	Quit ""
}

/// The number of heartbeatStalled status events with a Seq above from and below to.
ClassMethod Count(events As %DynamicArray, from As %Integer, to As %Integer) As %Integer [ Private ]
{
	Set count = 0
	Set iterator = events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If (event.type = "status") && (event.payload.condition = "heartbeatStalled") && (event.seq > from) && (event.seq < to) Set count = count + 1
	}
	Quit count
}

/// Removes the events and the counter of a stream.
ClassMethod ClearOf(stream As %String) [ Private ]
{
	If stream = "" Quit
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Live.Event WHERE Stream = ?", stream)
	Kill ^OcuTalonP.LiveEventC(stream)
}

/// Deletes the fixture sessions with their events and counters.
ClassMethod Clean() [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Session WHERE IrisUser %STARTSWITH 'zzstall'")
	While result.%Next() {
		Do ..ClearOf(result.%Get("Ref"))
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Session WHERE IrisUser %STARTSWITH 'zzstall'")
}

}
