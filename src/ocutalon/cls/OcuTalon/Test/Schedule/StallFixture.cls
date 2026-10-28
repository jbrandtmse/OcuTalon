Include Ensemble

/// The fixture that stalls the real heartbeat for the tests of Story 8.2 (FR-32; AD-12, AD-18, AD-33), the unit test Test.Schedule.Stalled
/// and the browser spec web/e2e/heartbeat/heartbeat.spec.ts. THESE CALLS RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they suspend the
/// real Task Manager task and move the tick mark of the running production. The browser spec calls each one in its own iris session, so
/// every method is a class method and the state that has to outlive a call is the global ^OcuTalonTest("StallFixture"): "suspended" is the
/// task's Suspended value as it was found, kept the first time Hold runs after a Release.
///   - Hold(secondsBack) suspends the task, waits out a run in flight and StatusMonitor's silent first run, and sets the tick mark;
///   - InstanceSeq() and WaitEvent(after, active) read the status events that StatusMonitor publishes on the instance stream;
///   - Tick() writes a real tick (HeartbeatTask.OnTask);
///   - Release() puts the task back as found, kills the state and writes a real tick, so that the mark is fresh (the ambient heartbeat
///     that Status.Computed reads must not flip under other tests).
/// It has no Test methods and the product never refers to it.
Class OcuTalon.Test.Schedule.StallFixture
{

/// The task that Hold suspends.
Parameter TASK = "OcuTalon heartbeat";

/// The item whose job must have run its silent first run before Hold moves the mark.
Parameter MONITOR = "StatusMonitor";

/// StatusMonitor's CallInterval in the production (seconds); Hold waits until its job is older than this plus MARGIN.
Parameter CALLINTERVAL = 15;

/// The seconds added to CALLINTERVAL.
Parameter MARGIN = 2;

/// The longest, in seconds, that Hold waits for the clock second to enter its window.
Parameter WAITCLOCK = 21;

/// The longest, in seconds, that Hold waits for the heartbeat's lock.
Parameter WAITLOCK = 10;

/// The longest, in seconds, that Hold waits for the monitor's job to be old enough.
Parameter WAITMONITOR = 60;

/// Suspends the real task (remembering its Suspended value the first time), waits for a clock second between 5 and 45 (up to WAITCLOCK
/// seconds: the longest wait from clock second 46 to second 5 of the next minute), takes and releases the heartbeat's lock (WAITLOCK seconds) to wait out a run in flight, waits until StatusMonitor's job
/// was registered at least CALLINTERVAL + MARGIN seconds ago (so that its silent first run is over), and then sets the tick mark to
/// now - secondsBack seconds, or removes it when secondsBack is "". Returns the mark. Throws when the task is missing, the lock is
/// not free in time, or the monitor's job is not found or not old enough in WAITMONITOR seconds.
ClassMethod Hold(secondsBack As %Integer) As %String
{
	Set task = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(..#TASK))
	If '$IsObject(task) Throw ##class(%Exception.General).%New("StallFixture", 5001, , "The task "_..#TASK_" does not exist")
	If '$Data(^OcuTalonTest("StallFixture", "suspended")) Set ^OcuTalonTest("StallFixture", "suspended") = task.Suspended
	Set task.Suspended = 1
	Do ..Check(task.%Save())

	Set deadline = $ZHorolog + ..#WAITCLOCK
	While ('..SecondInWindow()) && ($ZHorolog < deadline) {
		Hang 0.5
	}

	Set lock = ##class(OcuTalon.Schedule.Heartbeat).#LOCK
	Lock +@lock:..#WAITLOCK
	If '$Test Throw ##class(%Exception.General).%New("StallFixture", 5001, , "A run of the heartbeat still holds its lock "_..#WAITLOCK_" s after the task was suspended")
	Lock -@lock

	Set deadline = $ZHorolog + ..#WAITMONITOR
	While ('..MonitorSettled()) && ($ZHorolog < deadline) {
		Hang 0.5
	}
	If '..MonitorSettled() Throw ##class(%Exception.General).%New("StallFixture", 5001, , "The "_..#MONITOR_" job is not registered, or is younger than "_(..#CALLINTERVAL + ..#MARGIN)_" s, after "_..#WAITMONITOR_" s")

	Set mark = $Select($Get(secondsBack) = "": "", 1: ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -secondsBack))
	Do ..Check(##class(OcuTalon.Data.StatusMark).Record(##class(OcuTalon.Schedule.Heartbeat).#TICKMARK, mark))
	Quit ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Schedule.Heartbeat).#TICKMARK)
}

/// The Seq of the last event on the instance stream.
ClassMethod InstanceSeq() As %Integer
{
	Quit ##class(OcuTalon.Live.Publish).LastSeq(##class(OcuTalon.Live.Publish).#INSTANCE)
}

/// The Seq of the first status event on the instance stream after after whose payload is the heartbeatStalled condition with
/// active (1 or 0), polled every 0.5 s for up to seconds; 0 when there is none.
ClassMethod WaitEvent(after As %Integer, active As %Boolean, seconds As %Numeric = 30) As %Integer
{
	Set deadline = $ZHorolog + seconds
	For {
		Set events = ##class(OcuTalon.Live.Event).Since(##class(OcuTalon.Live.Publish).#INSTANCE, after, 200, "instance")
		Set iterator = events.%GetIterator()
		While iterator.%GetNext(, .event) {
			If event.type '= "status" Continue
			If event.payload.condition '= "heartbeatStalled" Continue
			If +event.payload.active = +active Return event.seq
		}
		If $ZHorolog >= deadline Quit
		Hang 0.5
	}
	Quit 0
}

/// A real tick: HeartbeatTask.OnTask, as the Task Manager runs it.
ClassMethod Tick() As %Status
{
	Quit ##class(OcuTalon.Schedule.HeartbeatTask).%New().OnTask()
}

/// Puts the task's Suspended value back as Hold found it, kills the fixture's state (only when the task was put back, so that the found value is not lost) and writes a real tick.
ClassMethod Release() As %Status
{
	Set sc = $$$OK
	If $Data(^OcuTalonTest("StallFixture", "suspended")) {
		Set task = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(..#TASK))
		If $IsObject(task) {
			Set task.Suspended = ^OcuTalonTest("StallFixture", "suspended")
			Set sc = task.%Save()
		}
	}
	If $$$ISOK(sc) Kill ^OcuTalonTest("StallFixture")
	Quit $SYSTEM.Status.AppendStatus(sc, ..Tick())
}

/// 1 when the clock second (UTC) is between 5 and 45, so that a run that the Task Manager dispatched at the minute boundary is over.
ClassMethod SecondInWindow() As %Boolean [ Private ]
{
	Set second = +$Extract(##class(OcuTalon.Data.Time).NowUtc(), 18, 19)
	Quit (second >= 5) && (second <= 45)
}

/// 1 when StatusMonitor's job was registered at least CALLINTERVAL + MARGIN seconds ago.
ClassMethod MonitorSettled() As %Boolean [ Private ]
{
	Set age = ..MonitorAge()
	Quit (age '= "") && (age >= (..#CALLINTERVAL + ..#MARGIN))
}

/// The whole seconds since the newest job of the StatusMonitor item was registered, or "" when there is no such job. The registration
/// time is the platform's job status, $$$eJobRegTime (UTC, "YYYY-MM-DD hh:mm:ss.fff"); it is read to the second and counted through
/// Data.Time.Seconds, like the current time.
ClassMethod MonitorAge() As %Numeric [ Private ]
{
	Set newest = ""
	Set job = ""
	For {
		Set job = $Order($$$EnsJobStatus($$$SystemName, job))
		If job = "" Quit
		If $Get($$$EnsJobStatus($$$SystemName, job, $$$eJobStartConfigName)) '= ..#MONITOR Continue
		Set registered = ##class(OcuTalon.Data.Time).Seconds($Translate($Extract($Get($$$EnsJobStatus($$$SystemName, job, $$$eJobRegTime)), 1, 19), " ", "T")_"Z")
		If registered = "" Continue
		If (newest = "") || (registered > newest) Set newest = registered
	}
	If newest = "" Quit ""
	Quit ##class(OcuTalon.Data.Time).Seconds(##class(OcuTalon.Data.Time).NowUtc()) - newest
}

/// Throws the status when it is an error.
ClassMethod Check(sc As %Status) [ Private ]
{
	If $$$ISERR(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
}

}
