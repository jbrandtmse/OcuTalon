Include Ensemble

/// Tests of the heartbeat task and service (Story 8.1; AD-1, AD-18, AD-23, AD-29, FR-32, NFR-20). THESE TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): they act on the running OcuTalon.Production, the Task Manager and the status marks, so they need the production started by the
/// Production step, and they fail with the reason where it does not run. Checks is Lane A's, so OnBeforeAllTests puts the double
/// Test.Schedule.ChecksDouble behind the Checks item (Test.Agent.RunnerFixture UseItemClass), and the double records each Tick in
/// ^OcuTalonTest("ChecksDouble","ticks"). The tests that call HeartbeatTask.OnTask in the test process suspend the real task first, so that no
/// scheduled run adds a tick.
///   - TestTaskDeclared (AC 1, 2): exactly one task of class HeartbeatTask in this namespace, named OcuTalon heartbeat, with the schedule that
///     Install.Step.Schedule.Tasks() declares, RescheduleOnStart 1 and a run within a minute; the Tasks step run again leaves the same task;
///   - TestCatchUp (AC 3, 4): with the tick mark 7 minutes back and the double set to hang 5 s, OnTask returns OK at once and sends one Tick,
///     CatchUp 1, naming the old tick, with one message header from HeartbeatIn to Checks; Gaps reads one gap of 6 minutes; a tick one minute
///     after the previous one adds no gap;
///   - TestStoppedThenStarted (AC 5): with the production stopped (the scheduler settled first, DW-28), a run of the task through
///     RunNow ends OK, writes no HeartbeatIn header and leaves both marks; when the production starts again the next scheduled run sends the one
///     catch-up Tick;
///   - TestStubSkipped (AC 7): with a stub behind Checks (Lane A's own class while it carries STUB), a run ends OK, sends no Tick, writes no
///     error row, and records the gap mark and the tick mark;
///   - TestStubFixtureSkipped: the same as TestStubSkipped with the stub of this test behind Checks, so that the fixture runs before Story 5.6;
///   - TestLockBusy (Always): a run that cannot take the lock for 5 s ends OK, sends nothing and changes no mark;
///   - TestSendFails (Always): a send that fails records neither mark and gives no Tick, and the next run catches up;
///   - TestRecordKeepsTickWhenGapFails (Always): a gap mark that cannot be written leaves the tick mark as it was;
///   - TestDisabledItem and TestQuiet (Always): with HeartbeatIn disabled the task ends OK and sends nothing; the codes that end a run quietly.
/// OnAfterOneTest and OnAfterAllTests put back what a test changed, also after a failure: the task's Suspended value, HeartbeatIn enabled, the
/// production running with every item, the Checks item's class, the tick mark, the gap marks (all of them are saved before the tests and put back after them, because the
/// tests write gaps of their own) and ^OcuTalonTest("ChecksDouble"). OnAfterAllTests returns an error when the class behind Checks, the task or
/// the production is not as it was found.
Class OcuTalon.Test.Schedule.Heartbeat Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

/// The item that the double sits behind.
Parameter ITEM = "Checks";

/// The item that ticks.
Parameter SERVICE = "HeartbeatIn";

/// The test double of Checks.
Parameter DOUBLE = "OcuTalon.Test.Schedule.ChecksDouble";

/// A stub, for when the class that the item had no longer carries STUB.
Parameter STUBFIXTURE = "OcuTalon.Test.Schedule.ChecksStub";

Parameter TASK = "OcuTalon heartbeat";

Parameter TASKCLASS = "OcuTalon.Schedule.HeartbeatTask";

/// The longest to wait for the double to record a tick, in seconds. A ceiling, not a delay: the wait polls and returns as soon as it has.
Parameter RECORDSECONDS = 30;

/// The longest to wait for the Task Manager to run the task, in seconds. A ceiling: it runs the task once a minute, and RunNow takes up to a minute.
Parameter RUNSECONDS = 75;

/// What UseItemClass saved ({"className"}) when the double was put behind Checks, as JSON text, or "" while the item is as it was found. A text,
/// because an object property would read as a new empty object when it is unset.
Property Swap As %String(MAXLEN = "");

/// The Suspended value of the task when a test first suspended it, or "" while the task is as it was found.
Property SuspendedWas As %String;

/// The Suspended value of the task when the tests began.
Property SuspendedFound As %String;

/// 1 once the marks have been saved (OnBeforeAllTests), so that they are put back.
Property Saved As %Boolean [ InitialExpression = 0 ];

/// 1 while a test has HeartbeatIn disabled.
Property Disabled As %Boolean [ InitialExpression = 0 ];

/// The tick mark as found, "" when there was none.
Property TickWas As %String;

/// The gap marks as found, as JSON text of {mark: value}.
Property GapsWas As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set reason = $ClassMethod(..#FIXTURE, "RunningReason")
	If reason '= "" Quit $SYSTEM.Status.Error(5001, reason)
	Set task = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(..#TASK))
	Set ..SuspendedFound = $Select($IsObject(task): task.Suspended, 1: "")
	Set ..TickWas = ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Schedule.Heartbeat).#TICKMARK)
	Set ..GapsWas = ..GapMarks().%ToJSON()
	Set ..Saved = 1
	Do ..ClearGaps()
	Set sc = $ClassMethod(..#FIXTURE, "UseItemClass", ..#ITEM, ..#DOUBLE, .saved)
	If $IsObject(saved) Set ..Swap = saved.%ToJSON()
	If $$$ISERR(sc) Quit $SYSTEM.Status.AppendStatus(sc, ..Restore())
	Quit sc
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("ChecksDouble")
	Do ..ClearGaps()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..ResumeTask()
	Kill ^OcuTalonTest("ChecksDouble")
	Kill ^OcuTalonTest("Heartbeat")
	Set sc = ..EnableService()
	If '$ClassMethod(..#FIXTURE, "Running") Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Install.Step.Production).Start())
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	If '..Saved Quit $$$OK
	Quit ..Restore()
}

/// Enables HeartbeatIn again when a test disabled it.
Method EnableService() As %Status
{
	If '..Disabled Quit $$$OK
	Set sc = ##class(Ens.Director).EnableConfigItem(..#SERVICE, 1, 1)
	If $$$ISOK(sc) Set ..Disabled = 0
	Quit sc
}

/// Puts back everything the tests changed and reports what is not as it was found.
Method Restore() As %Status
{
	Set sc = $SYSTEM.Status.AppendStatus(..HoldTask(), ..EnableService())
	If '$ClassMethod(..#FIXTURE, "Running") Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Install.Step.Production).Start())
	If ..Swap '= "" {
		Set saved = {}.%FromJSON(..Swap)
		Set ..Swap = ""
		Set sc = $SYSTEM.Status.AppendStatus(sc, $ClassMethod(..#FIXTURE, "RestoreItemClass", ..#ITEM, saved))
		Set class = $Get($$$ConfigClassName(..#ITEM))
		If class '= saved.className Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The "_..#ITEM_" item runs "_class_" after the restore, not "_saved.className))
	}
	If ..Saved {
		Set ..Saved = 0
		Do ##class(OcuTalon.Data.StatusMark).Record(##class(OcuTalon.Schedule.Heartbeat).#TICKMARK, ..TickWas)
		Do ..ClearGaps()
		Set was = {}.%FromJSON(..GapsWas)
		Set iterator = was.%GetIterator()
		While iterator.%GetNext(.mark, .value) {
			Do ##class(OcuTalon.Data.StatusMark).Record(mark, value)
		}
	}
	Kill ^OcuTalonTest("ChecksDouble")
	Kill ^OcuTalonTest("Heartbeat")
	Do ..ResumeTask()
	Set missing = ##class(OcuTalon.Install.Step.Production).NotRunning()
	If missing '= "" Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The production does not run every item after the tests: "_missing))
	Set task = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(..#TASK))
	If '$IsObject(task) Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The task "_..#TASK_" is gone after the tests"))
	If $IsObject(task) && (task.Suspended '= ..SuspendedFound) Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The task "_..#TASK_" has Suspended "_task.Suspended_" after the tests, not "_..SuspendedFound))
	Quit sc
}

/// AC 1 and 2. Exactly one task of the heartbeat's class exists, in this namespace, named OcuTalon heartbeat, with the schedule that
/// Install.Step.Schedule.Tasks() declares (the start date aside, which is the day the task was created), RescheduleOnStart 1 (a start
/// drops the missed runs) and a next run within a minute, seen as a run in the Task Manager's history within RUNSECONDS (the task's
/// own next-run columns hold the last run between runs, so they are not read). The Tasks step run again leaves one task, with the
/// same id and schedule, read from a task object that is opened again.
Method TestTaskDeclared()
{
	Set declared = ##class(OcuTalon.Install.Step.Schedule).Tasks()
	Do $$$AssertEquals(declared.%Size(), 1, "the schedule area declares one task")
	Set entry = declared.%Get(0)
	Do $$$AssertEquals(entry.name, ..#TASK, "its name is "_..#TASK)
	Do $$$AssertEquals(entry.taskClass, ..#TASKCLASS, "its class is "_..#TASKCLASS)
	Do $$$AssertEquals(..TaskCount(), 1, "exactly one task has the class "_..#TASKCLASS)
	Do $$$AssertEquals(..TaskCount(..#TASK), 1, "and it is the task "_..#TASK)
	Set id = ##class(%SYS.Task).FindId(..#TASK)
	Do $$$AssertTrue(id '= "", "the task is found by its name")
	Set task = ##class(%SYS.Task).%OpenId(id)
	Do $$$AssertTrue($IsObject(task), "and opens")
	If '$IsObject(task) Quit
	Do $$$AssertEquals(task.TaskClass, ..#TASKCLASS, "the task class")
	Do $$$AssertEquals(task.NameSpace, "OCUTALON", "the task runs in OCUTALON")
	Do $$$AssertEquals(task.Name, ..#TASK, "the task name")
	Do $$$AssertEquals(task.Suspended, 0, "the task is not suspended")
	Set iterator = entry.task.%GetIterator()
	While iterator.%GetNext(.property, .value) {
		If property = "StartDate" Continue
		Do $$$AssertEquals($Property(task, property), value, "the task carries the declared "_property)
	}
	Do $$$AssertTrue((task.StartDate '= "") && (task.StartDate '> +$Horolog), "the start date is a day up to today: "_task.StartDate)
	Do $$$AssertEquals(entry.task.RescheduleOnStart, 1, "AC 2: the declaration sets RescheduleOnStart 1")
	Do $$$AssertEquals(task.RescheduleOnStart, 1, "AC 2: the task has it, so a start drops the runs it missed instead of replaying them")
	Do $$$AssertEquals(task.TimePeriod_"|"_task.TimePeriodEvery_"|"_task.DailyFrequency_"|"_task.DailyFrequencyTime_"|"_task.DailyIncrement_"|"_task.DailyStartTime_"|"_task.DailyEndTime, "0|1|1|0|1|0|0", "it runs every minute, all day")
	Set schedule = ..ScheduleOf(task)
	Set historyMark = ..HistoryMark()
	Do $$$AssertTrue(..WaitRuns(historyMark, ..#RUNSECONDS) > 0, "the next run comes within a minute: the Task Manager ran the task within "_..#RUNSECONDS_" s")

	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Tasks).Run(), "the Tasks step runs again")
	Do $$$AssertEquals(..TaskCount(..#TASK), 1, "there is still one task")
	Do $$$AssertEquals(##class(%SYS.Task).FindId(..#TASK), id, "with the same id")
	Set task = ""
	Set again = ##class(%SYS.Task).%OpenId(id)
	Do $$$AssertEquals(..ScheduleOf(again), schedule, "and the same schedule")
}

/// AC 3 and 4. The production runs, the double sits behind Checks, the real task is suspended, the tick mark is 7 minutes back and the double
/// hangs 5 s. OnTask returns OK in under 5 s, because the heartbeat does not wait for a check. The double records exactly one tick: CatchUp 1,
/// PreviousTickAt the old time, TickAt the new tick mark; exactly one message header goes from HeartbeatIn to Checks, with a Tick as its body, and
/// none for a missed minute. Gaps over the last 10 minutes reads one gap, {start: the old time, end: TickAt, missed: 6}. A tick one minute after
/// the previous one adds no gap.
Method TestCatchUp()
{
	If '..Prepare(..#DOUBLE) Quit
	Do ..WaitForSafeMinute()
	Set old = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -420)
	Do ..SetTick(old)
	Set ^OcuTalonTest("ChecksDouble", "hang") = 5
	Set headerMark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Set eventMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set started = $ZHorolog
	Set sc = ##class(OcuTalon.Schedule.HeartbeatTask).%New().OnTask()
	Set elapsed = $ZHorolog - started
	Do $$$AssertStatusOK(sc, "OnTask returns OK")
	Do $$$AssertEquals(..LogRows(eventMark, ..#SERVICE), 0, "a run that succeeds writes no event-log row of HeartbeatIn")
	Do $$$AssertTrue(elapsed < 5, "OnTask returns in under 5 s, not after the check: "_$FNumber(elapsed, "", 2)_" s")
	Set tickAt = ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Schedule.Heartbeat).#TICKMARK)
	Do $$$AssertTrue((tickAt '= old) && (##class(OcuTalon.Data.Time).Seconds(tickAt) '< ##class(OcuTalon.Data.Time).Seconds(old)), "the tick mark moved on: "_tickAt)
	Do $$$AssertEquals(..Headers(headerMark), 1, "exactly one message header goes from HeartbeatIn to Checks, with a Tick as its body")
	Do $$$AssertEquals(..WaitTicks(1), 1, "the double records one tick")
	Set tick = $Get(^OcuTalonTest("ChecksDouble", "ticks", 1))
	Do $$$AssertEquals($List(tick, 1), tickAt, "its TickAt is the new tick mark")
	Do $$$AssertEquals($List(tick, 2), old, "its PreviousTickAt is the old tick")
	Do $$$AssertEquals($List(tick, 3), 1, "its CatchUp is 1")
	Set header = ##class(Ens.MessageHeader).%OpenId($List(tick, 4))
	Do $$$AssertTrue($IsObject(header), "its message header exists")
	If $IsObject(header) {
		Do $$$AssertEquals(header.SourceConfigName_">"_header.TargetConfigName_" "_header.MessageBodyClassName, "HeartbeatIn>Checks OcuTalon.Msg.Tick", "from HeartbeatIn to Checks, with a Tick as its body")
		Do $$$AssertTrue(header.SessionId > 0, "in a session of its own, which Visual Trace shows: "_header.SessionId)
	}
	Set gaps = ##class(OcuTalon.Schedule.Heartbeat).Gaps(##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -600), ##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(gaps.%Size(), 1, "Gaps over the last 10 minutes reads one gap")
	Set missed = ..MinutesBetween(old, tickAt)
	Do $$$AssertEquals(missed, 6, "the minutes of the two times are 7 apart, so 6 were missed")
	If gaps.%Size() = 1 Do $$$AssertEquals(gaps.%Get(0).%ToJSON(), {"start": (old), "end": (tickAt), "missed": (missed)}.%ToJSON(), "{start: the old tick, end: TickAt, missed: 6}")

	Kill ^OcuTalonTest("ChecksDouble", "hang")
	Do ..WaitForSafeMinute()
	Set oneMinuteBack = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -60)
	Do ..SetTick(oneMinuteBack)
	Set headerMark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.HeartbeatTask).%New().OnTask(), "a run one minute after the previous tick returns OK")
	Do $$$AssertEquals(..Headers(headerMark), 1, "and sends one Tick")
	Do $$$AssertEquals(..WaitTicks(2), 2, "which the double records after the first one")
	Set tick = $Get(^OcuTalonTest("ChecksDouble", "ticks", 2))
	Do $$$AssertEquals($List(tick, 2)_"|"_$List(tick, 3), oneMinuteBack_"|0", "naming the previous tick, with CatchUp 0")
	Set gaps = ##class(OcuTalon.Schedule.Heartbeat).Gaps(##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -600), ##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(gaps.%Size(), 1, "a tick one minute after the previous one adds no gap")
	Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Schedule.Heartbeat).#GAPMARK_oneMinuteBack), "", "and no gap mark of its own")
}

/// AC 5. The production is stopped (after the scheduler settled, DW-28) and the tick mark is 3 minutes back. The Task Manager runs the task
/// (RunNow): its history shows no error, no HeartbeatIn message header is written, and the tick mark and the gap marks are unchanged. When the
/// Production step starts the production again, the next scheduled run (within RUNSECONDS) is the single catch-up tick: PreviousTickAt is the mark
/// from before the stop, CatchUp is 1, the double records it once, its message header exists, and the history of the runs since the stop shows
/// no error. The real task is not suspended, since the schedule is what is tested.
Method TestStoppedThenStarted()
{
	If '..Prepare(..#DOUBLE, 0) Quit
	Do $$$AssertTrue(..SettleScheduler(), "the scheduler is settled before the production stops (DW-28)")
	Set sc = ##class(Ens.Director).StopProduction(10, 0)
	Do $$$AssertStatusOK(sc, "the production stops")
	Do $$$AssertEquals(##class(Ens.Director).IsProductionRunning(), 0, "it does not run")
	If $$$ISERR(sc) Quit
	Kill ^OcuTalonTest("ChecksDouble")
	Set headerMark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Set historyMark = ..HistoryMark()
	Set old = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -180)
	Do ..SetTick(old)
	Set marks = ..Marks()
	Set eventMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()

	Do $$$AssertStatusOK(##class(%SYS.Task).RunNow(##class(%SYS.Task).FindId(..#TASK)), "the Task Manager is asked to run the task now")
	Do $$$AssertTrue(..WaitRuns(historyMark, ..#RUNSECONDS) > 0, "the task ran while the production was stopped")
	Do $$$AssertEquals(..RunErrors(historyMark), 0, "its history has no error")
	Do $$$AssertEquals(..HeartbeatHeaders(headerMark), 0, "no HeartbeatIn header was written")
	Do $$$AssertEquals(..Marks(), marks, "the tick mark and the gap marks are unchanged")
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Test.Agent.RunnerFixture).ErrorRows(eventMark), "; "), "", "and the quiet end wrote no error row to the event log")

	Set historyMark = ..HistoryMark()
	Set sc = ##class(OcuTalon.Install.Step.Production).Start()
	Do $$$AssertStatusOK(sc, "the Production step starts the production again")
	If $$$ISERR(sc) Quit
	Do $$$AssertTrue(..WaitTicks(1, ..#RUNSECONDS) > 0, "the double receives a tick at the next scheduled run")
	Do $$$AssertTrue(..WaitRuns(historyMark, ..#RUNSECONDS) > 0, "the Task Manager ran the task after the start")
	Set tick = $Get(^OcuTalonTest("ChecksDouble", "ticks", 1))
	Do $$$AssertEquals($List(tick, 2), old, "the first tick names the mark from before the stop")
	Do $$$AssertEquals($List(tick, 3), 1, "and is a catch-up")
	Set catchUps = 0
	For n = 1:1:+$Get(^OcuTalonTest("ChecksDouble", "ticks")) {
		If $List(^OcuTalonTest("ChecksDouble", "ticks", n), 2) = old Set catchUps = catchUps + 1
	}
	Do $$$AssertEquals(catchUps, 1, "the double records the old tick as the previous one once")
	Set header = ##class(Ens.MessageHeader).%OpenId($List(tick, 4))
	Do $$$AssertTrue($IsObject(header) && (header.SourceConfigName_">"_header.TargetConfigName = "HeartbeatIn>Checks"), "its message header exists, from HeartbeatIn to Checks")
	Do $$$AssertEquals(..RunErrors(historyMark), 0, "the history of the runs after the start has no error")
	Set gap = ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Schedule.Heartbeat).#GAPMARK_old)
	Do $$$AssertTrue(gap '= "", "the gap mark of the stop is recorded: "_gap)
	If gap '= "" Do $$$AssertEquals({}.%FromJSON(gap).start, old, "it starts at the old tick")
}

/// AC 7 (ruling U-52). A stub is behind Checks: Lane A's own class while it carries STUB, else the stub of this test. The real task is suspended and
/// the tick mark is 3 minutes back. OnTask returns OK; no message header goes from HeartbeatIn to Checks; the tick mark is the new tick time; one gap
/// mark (missed 2) is recorded; and no error or alert row is written to the event log, which a Tick sent into the stub would have caused.
Method TestStubSkipped()
{
	Set original = $Select(..Swap = "": "", 1: {}.%FromJSON(..Swap).className)
	Do ..AssertStubSkipped($Select((original '= "") && $Parameter(original, "STUB"): original, 1: ..#STUBFIXTURE))
}

/// The same as TestStubSkipped with the stub of this test (Test.Schedule.ChecksStub) behind Checks, so that the fixture that TestStubSkipped falls
/// back to after Story 5.6 is run now.
Method TestStubFixtureSkipped()
{
	Do ..AssertStubSkipped(..#STUBFIXTURE)
}

/// Puts stub behind Checks and shows that a run sends no Tick and still records the marks, with no error row.
Method AssertStubSkipped(stub As %String) [ Private ]
{
	Do $$$AssertEquals(+$Parameter(stub, "STUB"), 1, "control: "_stub_" carries STUB")
	If '..Prepare(stub) Quit
	Do ..WaitForSafeMinute()
	Set old = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -180)
	Do ..SetTick(old)
	Set headerMark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Set eventMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.HeartbeatTask).%New().OnTask(), "OnTask returns OK")
	Do $$$AssertEquals(..Headers(headerMark), 0, "no message header goes from HeartbeatIn to Checks")
	Set tickAt = ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Schedule.Heartbeat).#TICKMARK)
	Do $$$AssertTrue((tickAt '= old) && (##class(OcuTalon.Data.Time).Seconds(tickAt) > ##class(OcuTalon.Data.Time).Seconds(old)), "the tick mark is the new tick time: "_tickAt)
	Set gaps = ##class(OcuTalon.Schedule.Heartbeat).Gaps(##class(OcuTalon.Data.Time).AddSeconds(old, -1), tickAt)
	Do $$$AssertEquals(gaps.%Size(), 1, "one gap mark is recorded")
	Set missed = ..MinutesBetween(old, tickAt)
	Do $$$AssertEquals(missed, 2, "the minutes of the two times are 3 apart, so 2 were missed")
	If gaps.%Size() = 1 Do $$$AssertEquals(gaps.%Get(0).%ToJSON(), {"start": (old), "end": (tickAt), "missed": (missed)}.%ToJSON(), "{start: the old tick, end: TickAt, missed: 2}")
	Hang 2
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Test.Agent.RunnerFixture).ErrorRows(eventMark)), 0, "no error or alert row was written: "_$ListToString(##class(OcuTalon.Test.Agent.RunnerFixture).ErrorRows(eventMark), "; "))
	Do $$$AssertEquals(..Headers(headerMark), 0, "and still no message header after a wait")
}

/// A send that fails records nothing. A HeartbeatIn whose send is refused (Test.Schedule.HeartbeatInFailing) returns the status and no Tick, and
/// leaves the tick mark and the gap marks as they were; the next run of the task finds the same gap and sends the one catch-up Tick.
Method TestSendFails()
{
	If '..Prepare(..#DOUBLE) Quit
	Set old = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -180)
	Do ..SetTick(old)
	Set marks = ..Marks()
	Set service = ##class(OcuTalon.Test.Schedule.HeartbeatInFailing).%New(..#SERVICE)
	Do $$$AssertTrue($IsObject(service), "the service with a failing send is made")
	If '$IsObject(service) Quit
	Set sc = service.OnProcessInput("", .output)
	Do $$$AssertTrue($$$ISERR(sc), "the failed send is returned")
	Do $$$AssertEquals($Get(output), "", "no Tick is given")
	Do $$$AssertEquals(..Marks(), marks, "and neither the gap mark nor the tick mark is recorded")
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.HeartbeatTask).%New().OnTask(), "the next run returns OK")
	Do $$$AssertEquals(..WaitTicks(1), 1, "and sends the one catch-up Tick")
	Set tick = $Get(^OcuTalonTest("ChecksDouble", "ticks", 1))
	Do $$$AssertEquals($List(tick, 2)_"|"_$List(tick, 3), old_"|1", "that names the old tick, with CatchUp 1")
}

/// Heartbeat.Record writes the gap mark first and returns its status when it fails, so that the tick mark is left as it was and the next run finds
/// the same gap. The gap mark cannot be written when its name is longer than a mark's name can be.
Method TestRecordKeepsTickWhenGapFails()
{
	Set old = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -180)
	Do ..SetTick(old)
	Set marks = ..Marks()
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set tick.PreviousTickAt = $Justify("", 129)
	Set tick.CatchUp = 1
	Do $$$AssertTrue($$$ISERR(##class(OcuTalon.Schedule.Heartbeat).Record(tick, 2)), "a gap mark that cannot be written returns its status")
	Do $$$AssertEquals(..Marks(), marks, "and the tick mark is left as it was")
}

/// HeartbeatIn disabled: CreateBusinessService says so, and the task ends OK, sends nothing and leaves the marks as they were. The item is enabled
/// again afterwards (EnableService).
Method TestDisabledItem()
{
	If '..Prepare(..#DOUBLE) Quit
	Set old = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -180)
	Do ..SetTick(old)
	Set marks = ..Marks()
	Set headerMark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Set ..Disabled = 1
	Do $$$AssertStatusOK(##class(Ens.Director).EnableConfigItem(..#SERVICE, 0, 1), ..#SERVICE_" is disabled")
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.HeartbeatTask).%New().OnTask(), "OnTask returns OK")
	Do $$$AssertEquals(..HeartbeatHeaders(headerMark), 0, "no HeartbeatIn header is written")
	Do $$$AssertEquals(..Marks(), marks, "and neither mark changed")
	Do $$$AssertStatusOK(..EnableService(), ..#SERVICE_" is enabled again")
	Do $$$AssertStatusOK(##class(OcuTalon.Schedule.HeartbeatTask).%New().OnTask(), "and the next run returns OK")
	Do $$$AssertEquals(..Headers(headerMark), 1, "and sends the Tick")
}

/// Quiet: the failures that only mean that the production is not ticking right now end a run quietly (with the production running, the quiescent,
/// disabled and not-running codes); every other failure is returned, so that the task history shows it.
Method TestQuiet()
{
	Set task = "OcuTalon.Schedule.HeartbeatTask"
	Do $$$AssertEquals(##class(Ens.Director).IsProductionRunning(), 1, "control: the production runs, so that only the code decides")
	For code = $$$EnsErrProductionQuiescent, $$$EnsErrConfigDisabled, $$$EnsErrProductionNotRunning {
		Do $$$AssertEquals($ClassMethod(task, "Quiet", $SYSTEM.Status.Error(code, "x")), 1, "code "_code_" ends a run quietly")
	}
	Do $$$AssertEquals($ClassMethod(task, "Quiet", $SYSTEM.Status.Error($$$EnsErrBusinessDispatchNameNotRegistered, "x")), 0, "a service that is not registered in a running production is an error")
	Do $$$AssertEquals($ClassMethod(task, "Quiet", $SYSTEM.Status.Error(5001, "x")), 0, "so is any other failure")
}

/// The lock. This test holds the lock of the heartbeat while a job runs the task: the run waits for the lock, ends OK after about 5 s, sends
/// nothing and leaves the marks as they were.
Method TestLockBusy()
{
	If '..Prepare(..#DOUBLE) Quit
	Set old = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -180)
	Do ..SetTick(old)
	Set marks = ..Marks()
	Set eventMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set headerMark = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderMark()
	Set run = $Name(^OcuTalonTest("Heartbeat", "lock"))
	Set lock = ##class(OcuTalon.Schedule.Heartbeat).#LOCK
	Kill @run
	Lock +@lock:5
	Set held = $Test
	Do $$$AssertEquals(held, 1, "the test holds the heartbeat lock")
	If 'held Quit
	Try {
		Job ##class(OcuTalon.Test.Schedule.Heartbeat).RunInJob(run)
		Do ..WaitFor($Name(@run@("done")), 1, 60)
		Do $$$AssertEquals($Get(@run@("done")), 1, "the run returns although the lock is held")
		Do $$$AssertEquals($Get(@run@("ok")), 1, "with OK")
		Do $$$AssertTrue(($Get(@run@("seconds"), 0) '< 4) && ($Get(@run@("seconds"), 0) < 15), "after it waited its 5 seconds for the lock: "_$Get(@run@("seconds"))_" seconds")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Lock -@lock
	Do $$$AssertEquals(..Headers(headerMark), 0, "nothing was sent")
	Do $$$AssertEquals(..Marks(), marks, "and no mark changed")
	Kill @run
}

/// The body of the job of TestLockBusy: runs the task and records, under run, that it finished, whether it returned OK and how long it took.
ClassMethod RunInJob(run As %String)
{
	Set started = $ZHorolog
	Set sc = ##class(OcuTalon.Schedule.HeartbeatTask).%New().OnTask()
	Set @run@("seconds") = $ZHorolog - started
	Set @run@("ok") = $$$ISOK(sc)
	Set @run@("done") = 1
}

/// 1 when the production runs and the class behind Checks is className, putting it there when it is not (the status of the swap is asserted),
/// with the double's record empty. With suspend 1 the real task is suspended too, which the tests that run the task in this process need, so that
/// no scheduled run adds a tick.
Method Prepare(className As %String, suspend As %Boolean = 1) As %Boolean [ Private ]
{
	Set reason = $ClassMethod(..#FIXTURE, "RunningReason")
	Do $$$AssertEquals(reason, "", "the production runs")
	If reason '= "" Quit 0
	If $$$ConfigClassName(..#ITEM) '= className {
		Set sc = $ClassMethod(..#FIXTURE, "UseItemClass", ..#ITEM, className, .saved)
		If (..Swap = "") && $IsObject(saved) Set ..Swap = saved.%ToJSON()
		Do $$$AssertStatusOK(sc, className_" is put behind "_..#ITEM)
		If $$$ISERR(sc) Quit 0
	}
	If suspend Do ..SuspendTask()
	Kill ^OcuTalonTest("ChecksDouble")
	Quit 1
}

/// Suspends the real task (HoldTask) and asserts that it did.
Method SuspendTask()
{
	Do $$$AssertStatusOK(..HoldTask(), "the real task is suspended")
}

/// Suspends the real task, remembering its Suspended value the first time, and waits for a run that is in the heartbeat service to finish.
Method HoldTask() As %Status
{
	Set task = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(..#TASK))
	If '$IsObject(task) Quit $SYSTEM.Status.Error(5001, "The task "_..#TASK_" does not exist")
	If ..SuspendedWas = "" Set ..SuspendedWas = task.Suspended
	Set task.Suspended = 1
	Set sc = task.%Save()
	Set lock = ##class(OcuTalon.Schedule.Heartbeat).#LOCK
	Lock +@lock:10
	Lock -@lock
	Quit sc
}

/// Puts the Suspended value of the real task back as it was found, when a test changed it.
Method ResumeTask()
{
	If ..SuspendedWas = "" Quit
	Set task = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(..#TASK))
	If $IsObject(task) {
		Set task.Suspended = ..SuspendedWas
		Do task.%Save()
	}
	Set ..SuspendedWas = ""
}

/// Waits, when the clock is in the last seconds of a clock minute, for the next minute to start (up to 15 s), so that a run a few seconds later is
/// still in the same clock minute as the time the test builds its tick marks from.
Method WaitForSafeMinute()
{
	While +$Extract(##class(OcuTalon.Data.Time).NowUtc(), 18, 19) > 45 {
		Hang 0.5
	}
}

/// The clock minutes between two UTC times, less one: the minutes the heartbeat missed. It is how the heartbeat counts, from the minutes of the two times.
ClassMethod MinutesBetween(from As %String, to As %String) As %Integer
{
	Quit (##class(OcuTalon.Data.Time).Seconds(to) \ 60) - (##class(OcuTalon.Data.Time).Seconds(from) \ 60) - 1
}

/// Writes the tick mark of a fixture run.
Method SetTick(utc As %String)
{
	Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).Record(##class(OcuTalon.Schedule.Heartbeat).#TICKMARK, utc), "the tick mark is set to "_utc)
}

/// All the gap marks as a dynamic object {mark: value}.
ClassMethod GapMarks() As %DynamicObject
{
	Set marks = {}
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT Mark, Value FROM OcuTalon_Data.StatusMark WHERE Mark %STARTSWITH ?", ##class(OcuTalon.Schedule.Heartbeat).#GAPMARK)
	While rows.%Next() {
		Do marks.%Set(rows.%GetData(1), rows.%GetData(2))
	}
	Quit marks
}

/// Deletes every gap mark.
ClassMethod ClearGaps()
{
	Set marks = ..GapMarks()
	Set iterator = marks.%GetIterator()
	While iterator.%GetNext(.mark) {
		Do ##class(OcuTalon.Data.StatusMark).Record(mark, "")
	}
}

/// The tick mark and the gap marks as one text, to compare before and after.
ClassMethod Marks() As %String
{
	Set text = "tick=" _ ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Schedule.Heartbeat).#TICKMARK)
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT Mark, Value FROM OcuTalon_Data.StatusMark WHERE Mark %STARTSWITH ? ORDER BY Mark", ##class(OcuTalon.Schedule.Heartbeat).#GAPMARK)
	While rows.%Next() {
		Set text = text _ "|" _ rows.%GetData(1) _ "=" _ rows.%GetData(2)
	}
	Quit text
}

/// The number of message headers after the mark that go from HeartbeatIn to Checks with a Tick as their body.
ClassMethod Headers(mark As %Integer) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'HeartbeatIn' AND TargetConfigName = 'Checks' AND MessageBodyClassName = 'OcuTalon.Msg.Tick'", mark)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The number of message headers after the mark that HeartbeatIn wrote, whatever their target.
ClassMethod HeartbeatHeaders(mark As %Integer) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'HeartbeatIn'", mark)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The number of event-log rows after the mark that the item wrote, of any type.
ClassMethod LogRows(mark As %Integer, item As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND ConfigName = ?", mark, item)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// Waits, up to seconds, until the double has recorded at least count ticks. The number recorded.
ClassMethod WaitTicks(count As %Integer, seconds As %Integer = {..#RECORDSECONDS}) As %Integer
{
	Set deadline = $ZHorolog + seconds
	While (+$Get(^OcuTalonTest("ChecksDouble", "ticks")) < count) && ($ZHorolog < deadline) {
		Hang 0.2
	}
	Quit +$Get(^OcuTalonTest("ChecksDouble", "ticks"))
}

/// Waits, up to seconds, until the global node holds the value.
ClassMethod WaitFor(node As %String, value As %String, seconds As %Integer)
{
	Set deadline = $ZHorolog + seconds
	While ($Get(@node) '= value) && ($ZHorolog < deadline) {
		Hang 0.2
	}
}

/// The highest id of the Task Manager's history: the mark that WaitRuns and RunErrors read from.
ClassMethod HistoryMark() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM %SYS_Task.History")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The condition that picks the runs of the heartbeat task after a history mark: its name and its class, and not the Task Manager's own
/// note that a task expired. A run that failed has no Error text (its Status holds the error), so the condition lets an empty Error through.
ClassMethod RunsWhere() As %String [ Private ]
{
	Quit "ID > ? AND Name = '"_..#TASK_"' AND UPPER(ExecuteCode) = '"_$ZConvert(..#TASKCLASS, "U")_"' AND (Error IS NULL OR UPPER(Error) NOT LIKE 'TASK HAS EXPIRED%')"
}

/// The number of runs of the heartbeat task in the history after the mark.
ClassMethod Runs(mark As %Integer) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM %SYS_Task.History WHERE "_..RunsWhere(), mark)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The number of those runs that ended in an error: a status that is not OK (Status is 1 for a run that returned OK) or an untrapped error.
ClassMethod RunErrors(mark As %Integer) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM %SYS_Task.History WHERE "_..RunsWhere()_" AND ((Status <> '1') OR (ER IS NOT NULL AND ER <> ''))", mark)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// Waits, up to seconds, until the history holds a run of the task after the mark. The number of runs.
ClassMethod WaitRuns(mark As %Integer, seconds As %Integer) As %Integer
{
	Set deadline = $ZHorolog + seconds
	While (..Runs(mark) = 0) && ($ZHorolog < deadline) {
		Hang 1
	}
	Quit ..Runs(mark)
}

/// The number of tasks, in any namespace, of the heartbeat's class (no name given) or of the name.
ClassMethod TaskCount(name As %String = "") As %Integer
{
	If name = "" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM %SYS.Task WHERE TaskClass = ?", ..#TASKCLASS)
	} Else {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM %SYS.Task WHERE Name = ?", name)
	}
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The schedule fields of a task as one text, the next run aside.
ClassMethod ScheduleOf(task As %SYS.Task) As %String
{
	Set text = ""
	For property = "TimePeriod", "TimePeriodEvery", "DailyFrequency", "DailyFrequencyTime", "DailyIncrement", "DailyStartTime", "DailyEndTime", "StartDate", "RescheduleOnStart", "Suspended" {
		Set text = text _ property _ "=" _ $Property(task, property) _ ";"
	}
	Quit text
}

/// Waits until Ens.ScheduleHandler is idle (DW-28): a stop right after a production update fails unless it is. This is the line settle_scheduler of
/// docker/tests/lib-live.sh, as ObjectScript: it ends once the handler's queue is empty and its job is Alive, dequeuing and has no active message,
/// or after 10 s. 1 when it settled.
ClassMethod SettleScheduler() As %Boolean
{
	Set busy = 1
	Set seen = 0
	For k = 1:1:100 {
		Set busy = (##class(Ens.Queue).GetCount("Ens.ScheduleHandler") > 0)
		Set seen = 0
		Set rs = ##class(%ResultSet).%New("Ens.Job:Enumerate")
		Set sc = rs.Execute()
		While rs.Next() {
			If rs.Get("ConfigName") = "Ens.ScheduleHandler" {
				Set seen = 1
				If '((rs.Get("State") = "Alive") && (rs.Get("Status") = "dequeuing") && (rs.Get("ActiveMessage") = "")) Set busy = 1
			}
		}
		If seen && 'busy Quit
		Hang 0.1
	}
	Quit seen && 'busy
}

}
