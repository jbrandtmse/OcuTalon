/// Tests of the heartbeat task's resume (Story 8.8; AD-18, AD-19, AD-23, FR-32; DW-1018). THESE TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): they act on the Task Manager, and two of them on the real task OcuTalon heartbeat and the running OcuTalon.Production. The real
/// task's Suspended value is put back as found after each test that changes it (OnAfterOneTest).
///   - TestNotSuspended (AC 2): ResumeTask on a probe task with Suspended 0 is OK, writes no warning and changes no property, its id included;
///   - TestSuspended (AC 1): for Suspended 1 and 2, ResumeTask is OK, the stored Suspended is 0, exactly one warning says that the task was
///     suspended and resumed, no other property changes, and there is still one task of that name with the same id;
///   - TestMissing (AC 3): ResumeTask for a name with no task is OK, writes no warning and creates no task;
///   - TestReconcileResumesHeartbeat (AC 1, 5): with the real task Suspended 1, Install.Step.Schedule.Reconcile() is OK, the task is at 0, the
///     heartbeat warning occurs exactly once and the schedule is unchanged. This is the Reconcile step that every start path runs, including
///     Registry.Run("ipm");
///   - TestReconcileLeavesHeartbeat (AC 2): with the real task at 0, Reconcile() writes no heartbeat warning and changes no property;
///   - TestResumeFails (matrix row 5): while another job holds the row lock of a Suspended probe task, ResumeTask returns the failed status
///     of Resume (after the SQL lock timeout, about 10 s), writes no warning and leaves the task Suspended;
///   - TestReconcileReportsFailedResume (matrix row 5): the same on the real task, through Install.Step.Schedule.Reconcile(), which returns
///     the failed status and writes no heartbeat warning;
///   - TestReconcileInResumes (AC 1, 5): with the real task Suspended 1, a poll of a shadow instance of Install.ReconcileIn writes one Event Log
///     Warning row, ReconcileIn: <the heartbeat line>, and the task is at 0.
/// A probe task is ZzResumeProbe <job>-<n>, of the class ResumeProbeTask, in this namespace, on a start date a year ahead so that it never runs;
/// it is deleted after the test. The real-task tests wait for a clock second between 5 and 45 first, so that no run the Task Manager dispatched at
/// the minute boundary is in flight. The Event Log row count is a copy of Test.Install.ReconcileIn's Rows and LastRow, which are Private in that
/// (Lane A's) class.
Class OcuTalon.Test.Schedule.TaskResume Extends %UnitTest.TestCase
{

/// The real task.
Parameter TASK = "OcuTalon heartbeat";

/// The longest, in seconds, that a test waits for a clock second between 5 and 45.
Parameter WAITCLOCK = 21;

/// The longest, in seconds, that the ReconcileIn test waits for every item of the production to run.
Parameter WAITITEMS = 60;

/// How long, in seconds, the lock-holding job keeps a task's row lock. It is longer than the SQL lock timeout (10 s) that ends a blocked
/// Resume.
Parameter HOLDSECONDS = 14;

/// The name of the probe task of the running test, and its id.
Property ProbeName As %String;

Property ProbeId As %String;

/// The real task's stored Suspended value, as the running test found it; "" when the test did not touch it.
Property Found As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..ProbeName = ""
	Set ..ProbeId = ""
	Set ..Found = ""
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	If (testname '= "TestNotSuspended") && (testname '= "TestSuspended") && (testname '= "TestResumeFails") Quit $$$OK
	Set ..ProbeName = "ZzResumeProbe " _ $Job _ "-" _ $Increment(^OcuTalonTest("TaskResume", "n"))
	Set task = ##class(%SYS.Task).%New()
	Set task.Name = ..ProbeName
	Set task.Description = "Probe task of OcuTalon.Test.Schedule.TaskResume; deleted after the test."
	Set task.TaskClass = "OcuTalon.Test.Schedule.ResumeProbeTask"
	Set task.NameSpace = $Namespace
	Set task.RunAsUser = $Username
	Set task.TimePeriod = 0
	Set task.TimePeriodEvery = 1
	Set task.DailyFrequency = 1
	Set task.DailyFrequencyTime = 0
	Set task.DailyIncrement = 1
	Set task.DailyStartTime = 0
	Set task.DailyEndTime = 0
	Set task.StartDate = +$Horolog + 365
	Set sc = task.AssignSettings(##class(OcuTalon.Test.Schedule.ResumeProbeTask).%New())
	If $$$ISOK(sc) Set sc = task.%Save()
	Do $$$AssertStatusOK(sc, "the probe task is created")
	If $$$ISOK(sc) Set ..ProbeId = task.%Id()
	Quit sc
}

/// Deletes the probe task, and puts the real task's Suspended value back when the test has not already (RestoreRealTask). The warnings are cleared.
Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = $$$OK
	If ..ProbeId '= "" Set sc = ##class(%SYS.Task).%DeleteId(..ProbeId)
	Set ..ProbeId = ""
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..PutBack())
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	Quit sc
}

/// Puts the real task's stored Suspended back to the value Found, when the test changed it, and forgets Found.
Method PutBack() As %Status [ Private ]
{
	Set sc = $$$OK
	If ..Found '= "" {
		Set id = ##class(%SYS.Task).FindId(..#TASK)
		If (id '= "") && (..Found '= 0) Set sc = ##class(%SYS.Task).Suspend(id, ..Found)
		If (id '= "") && (..Found = 0) Set sc = ##class(%SYS.Task).Resume(id)
		Set ..Found = ""
	}
	Quit sc
}

/// Puts the real task back (PutBack) and asserts that its stored Suspended is the value the test found.
Method RestoreRealTask(id As %String) [ Private ]
{
	Set found = ..Found
	Do $$$AssertStatusOK(..PutBack(), "the heartbeat task is put back")
	Do $$$AssertEquals(##class(%SYS.Task).SuspendedGetStored(id), found, "its stored Suspended is as the test found it")
}

Method TestNotSuspended()
{
	Set id = ..ProbeId
	If id = "" Quit
	Do $$$AssertEquals(##class(%SYS.Task).SuspendedGetStored(id), 0, "the probe task is not suspended")
	Set before = ..Snapshot(id)
	Set sc = ##class(OcuTalon.Install.Step.Schedule).ResumeTask(..ProbeName)
	Set lines = ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertStatusOK(sc, "ResumeTask returns OK")
	Do $$$AssertEquals($ListLength(lines), 0, "and writes no line")
	Do $$$AssertEquals(##class(%SYS.Task).SuspendedGetStored(id), 0, "the task is still not suspended")
	Do $$$AssertEquals(..Snapshot(id), before, "no property and not the id changed")
}

Method TestSuspended()
{
	Set id = ..ProbeId
	If id = "" Quit
	Set before = ..Snapshot(id)
	Set text = "the task """ _ ..ProbeName _ """ was suspended, so it was resumed"
	For flag = 1, 2 {
		Do $$$AssertStatusOK(##class(%SYS.Task).Suspend(id, flag), "the task is suspended with flag " _ flag)
		Do $$$AssertEquals(##class(%SYS.Task).SuspendedGetStored(id), flag, "its stored Suspended is " _ flag)
		Do ##class(OcuTalon.Install.Step).TakeWarnings()
		Set sc = ##class(OcuTalon.Install.Step.Schedule).ResumeTask(..ProbeName)
		Set lines = ##class(OcuTalon.Install.Step).TakeWarnings()
		Do $$$AssertStatusOK(sc, "ResumeTask returns OK (Suspended " _ flag _ ")")
		Do $$$AssertEquals(##class(%SYS.Task).SuspendedGetStored(id), 0, "the stored Suspended is 0")
		Do $$$AssertEquals($ListLength(lines), 1, "exactly one line is written")
		Do $$$AssertEquals($ListGet(lines, 1), text, "and it names the task")
		Do $$$AssertEquals(..Snapshot(id), before, "no other property and not the id changed")
		Do $$$AssertEquals(##class(OcuTalon.Test.Schedule.Heartbeat).TaskCount(..ProbeName), 1, "there is one task of that name")
	}
}

Method TestResumeFails()
{
	Set id = ..ProbeId
	If id = "" Quit
	Do $$$AssertStatusOK(##class(%SYS.Task).Suspend(id, 1), "the probe task is suspended")
	If '..HoldRow(id) Quit
	Set sc = ##class(OcuTalon.Install.Step.Schedule).ResumeTask(..ProbeName)
	Set lines = ##class(OcuTalon.Install.Step).TakeWarnings()
	Do ..ReleaseRow(id)
	Do $$$AssertStatusNotOK(sc, "a Resume that fails returns its status")
	Do $$$AssertEquals($ListLength(lines), 0, "and writes no line")
	Do $$$AssertEquals(##class(%SYS.Task).SuspendedGetStored(id), 1, "the task is still suspended")
}

Method TestMissing()
{
	Set name = "ZzResumeProbe missing " _ $Job
	Do $$$AssertEquals(##class(OcuTalon.Test.Schedule.Heartbeat).TaskCount(name), 0, "no task has the name")
	Set sc = ##class(OcuTalon.Install.Step.Schedule).ResumeTask(name)
	Set lines = ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertStatusOK(sc, "ResumeTask returns OK")
	Do $$$AssertEquals($ListLength(lines), 0, "and writes no line")
	Do $$$AssertEquals(##class(OcuTalon.Test.Schedule.Heartbeat).TaskCount(name), 0, "and creates no task")
}

Method TestReconcileResumesHeartbeat()
{
	Set id = ..HoldRealTask(1)
	If id = "" Quit
	Set before = ..Snapshot(id)
	Set sc = ##class(OcuTalon.Install.Step.Schedule).Reconcile()
	Set lines = ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertStatusOK(sc, "Reconcile returns OK")
	Do $$$AssertEquals(##class(%SYS.Task).SuspendedGetStored(id), 0, "the heartbeat task is at 0")
	Do $$$AssertEquals(..Count(lines, ..Text()), 1, "the heartbeat line occurs exactly once")
	Do $$$AssertEquals(..Snapshot(id), before, "no other property and not the id changed")
	Do $$$AssertEquals(##class(OcuTalon.Test.Schedule.Heartbeat).TaskCount(..#TASK), 1, "there is one heartbeat task")
	Do ..RestoreRealTask(id)
}

Method TestReconcileLeavesHeartbeat()
{
	Set id = ..HoldRealTask(0)
	If id = "" Quit
	Set before = ..Snapshot(id)
	Set sc = ##class(OcuTalon.Install.Step.Schedule).Reconcile()
	Set lines = ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertStatusOK(sc, "Reconcile returns OK")
	Do $$$AssertEquals(##class(%SYS.Task).SuspendedGetStored(id), 0, "the heartbeat task is still at 0")
	Do $$$AssertEquals(..Count(lines, ..Text()), 0, "no heartbeat line is written")
	Do $$$AssertEquals(..Snapshot(id), before, "no property and not the id changed")
	Do ..RestoreRealTask(id)
}

Method TestReconcileReportsFailedResume()
{
	Set id = ..HoldRealTask(1)
	If id = "" Quit
	If '..HoldRow(id) Quit
	Set sc = ##class(OcuTalon.Install.Step.Schedule).Reconcile()
	Set lines = ##class(OcuTalon.Install.Step).TakeWarnings()
	Do ..ReleaseRow(id)
	Do $$$AssertStatusNotOK(sc, "Reconcile returns the failed status of the Resume")
	Do $$$AssertEquals(..Count(lines, ..Text()), 0, "and writes no heartbeat line")
	Do $$$AssertEquals(##class(%SYS.Task).SuspendedGetStored(id), 1, "the heartbeat task is still suspended")
	Do ..RestoreRealTask(id)
}

Method TestReconcileInResumes()
{
	Set id = ..HoldRealTask(1)
	If id = "" Quit
	Set end = $ZHorolog + ..#WAITITEMS
	While (##class(OcuTalon.Install.Step.Production).NotRunning() '= "") && (end > $ZHorolog) {
		Hang 1
	}
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).NotRunning(), "", "every item of the production runs, so a poll reconciles")
	Set item = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Install.ReconcileIn", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the item is made")
	If '$IsObject(item) Quit
	Do $$$AssertStatusOK(item.OnInit(), "OnInit runs")
	Do $$$AssertEquals(item.ByStep, 0, "with the start lock free")
	Set first = ..LastRow()
	Set sc = item.OnProcessInput("", .output)
	Set last = ..LastRow()
	Do $$$AssertStatusOK(sc, "the poll returns OK")
	Do $$$AssertEquals(item.Done, 1, "and the reconcile ran")
	Do $$$AssertEquals(..Rows(first, last, 3, "ReconcileIn: " _ ..Text()), 1, "the heartbeat line is one Warning row")
	Do $$$AssertEquals(##class(%SYS.Task).SuspendedGetStored(id), 0, "the heartbeat task is at 0")
	Do ..RestoreRealTask(id)
}

/// Starts a job that holds the row lock of the task for HOLDSECONDS, so that a Resume in this job fails on the lock. 1 when the lock is held.
Method HoldRow(id As %String) As %Boolean [ Private ]
{
	Kill ^OcuTalonTest("TaskResume", "held", id)
	Job ..HoldRowJob(id, ..#HOLDSECONDS)
	Set end = $ZHorolog + 10
	While ('$Data(^OcuTalonTest("TaskResume", "held", id))) && ($ZHorolog < end) {
		Hang 0.2
	}
	Do $$$AssertTrue($Data(^OcuTalonTest("TaskResume", "held", id)), "another job holds the lock of the task")
	Quit $Data(^OcuTalonTest("TaskResume", "held", id))
}

/// Waits until the lock-holding job has released the lock (up to HOLDSECONDS plus 5 s).
Method ReleaseRow(id As %String) [ Private ]
{
	Set end = $ZHorolog + ..#HOLDSECONDS + 5
	While ($Data(^OcuTalonTest("TaskResume", "held", id))) && ($ZHorolog < end) {
		Hang 0.5
	}
	Do $$$AssertTrue('$Data(^OcuTalonTest("TaskResume", "held", id)), "the lock is released")
}

/// The lock-holding job: locks the task's row (the lock that an update of the task takes), marks it in ^OcuTalonTest, holds it, and releases it.
ClassMethod HoldRowJob(id As %String, seconds As %Integer)
{
	Lock +^|"^^"_$ZU(12)|SYS("Task", "TaskD", id):5
	If '$Test Quit
	Set ^OcuTalonTest("TaskResume", "held", id) = 1
	Hang seconds
	Lock -^|"^^"_$ZU(12)|SYS("Task", "TaskD", id)
	Kill ^OcuTalonTest("TaskResume", "held", id)
}

/// The warning that the resume writes for the real task.
Method Text() As %String [ Private ]
{
	Quit "the task """ _ ..#TASK _ """ was suspended, so it was resumed"
}

/// Waits for a clock second between 5 and 45 (up to WAITCLOCK seconds), remembers the real task's stored Suspended value in Found, and puts the
/// task at suspended (1 to Suspend with flag 1, 0 to Resume). The task's id; "" (after a failed assertion) when the task does not exist.
Method HoldRealTask(suspended As %Boolean) As %String [ Private ]
{
	Set end = $ZHorolog + ..#WAITCLOCK
	While ('..SecondInWindow()) && ($ZHorolog < end) {
		Hang 0.5
	}
	Set id = ##class(%SYS.Task).FindId(..#TASK)
	Do $$$AssertNotEquals(id, "", "the task " _ ..#TASK _ " exists")
	If id = "" Quit ""
	Set ..Found = ##class(%SYS.Task).SuspendedGetStored(id)
	Set sc = $$$OK
	If ..Found '= 0 Set sc = ##class(%SYS.Task).Resume(id)
	If $$$ISOK(sc) && suspended Set sc = ##class(%SYS.Task).Suspend(id, 1)
	Do $$$AssertStatusOK(sc, "the task is put in the state the test needs")
	Do $$$AssertEquals(##class(%SYS.Task).SuspendedGetStored(id), suspended, "its stored Suspended is " _ suspended)
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	Quit id
}

/// 1 when the clock second (UTC) is between 5 and 45, so that a run that the Task Manager dispatched at the minute boundary is over.
ClassMethod SecondInWindow() As %Boolean [ Private ]
{
	Set second = +$Extract(##class(OcuTalon.Data.Time).NowUtc(), 18, 19)
	Quit (second >= 5) && (second <= 45)
}

/// The number of lines of the list that equal the text.
ClassMethod Count(lines As %List, text As %String) As %Integer [ Private ]
{
	Set n = 0
	Set position = 0
	While $ListNext(lines, position, line) {
		If line = text Set n = n + 1
	}
	Quit n
}

/// The task's id, schedule fields, RunAsUser, NameSpace, TaskClass and Description as one text, each read from a fresh open of the stored task
/// (no OREF of the task is held across the call, so the read is not a cached one). The Suspended value is not part of it.
ClassMethod Snapshot(id As %String) As %String [ Private ]
{
	Set task = ##class(%SYS.Task).%OpenId(id)
	If '$IsObject(task) Quit "missing " _ id
	Set text = id _ "|" _ $Replace(##class(OcuTalon.Test.Schedule.Heartbeat).ScheduleOf(task), "Suspended=" _ task.Suspended _ ";", "")
	For property = "RunAsUser", "NameSpace", "TaskClass", "Description", "Name" {
		Set text = text _ "|" _ property _ "=" _ $Property(task, property)
	}
	Quit text
}

/// The highest row id of the event log, 0 when it is empty.
ClassMethod LastRow() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of event log rows of ReconcileIn that this job logged after row id from and up to row id to, of the type (2 Error, 3 Warning,
/// 4 Info) and whose Text is LIKE text.
ClassMethod Rows(from As %Integer, to As %Integer, type As %Integer, text As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND ID <= ? AND Job = ? AND SourceClass = ? AND Type = ? AND Text LIKE ?", from, to, $Job, "OcuTalon.Install.ReconcileIn", type, text)
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
