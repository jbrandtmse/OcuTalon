Include Ensemble

/// HeartbeatIn, the adapterless service that ticks every minute (AD-1, AD-18; FR-32). The Task Manager task
/// OcuTalon.Schedule.HeartbeatTask makes it with Ens.Director.CreateBusinessService and calls ProcessInput with no input. Each
/// call makes one Tick (OcuTalon.Schedule.Heartbeat.Next), sends it to Checks without waiting for a check, and records the run in
/// the status marks, in this order: the send, the gap mark (when minutes were missed), the tick mark (Heartbeat.Record).
///   - After downtime the next call sends one Tick with CatchUp 1, never one per missed minute.
///   - A send that fails records nothing, so the next call finds the same gap and catches up.
///   - It works under one lock (Heartbeat LOCK), waited for 5 s. A call that cannot take it ends OK and sends nothing.
///   - While the class behind Checks carries STUB (as Lane A's OcuTalon.Checks.Process did until Story 5.6), it sends nothing and
///     records the marks as after a send, so that the stub writes no error row and the stalled warning stays real (ruling U-52).
///   - A call that succeeds writes no event-log row. The Tick is the output.
/// It is also the Schedule area's way in for the re-arm of a reminder's waiter (AD-1): a ReminderStart as the input is not a tick. It is
/// sent on to ReminderTimer (Reminder.StartFrom) before, and apart from, the lock, the tick and the status marks.
Class OcuTalon.Schedule.HeartbeatIn Extends Ens.BusinessService
{

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	If $IsObject(pInput) && pInput.%IsA("OcuTalon.Schedule.ReminderStart") Quit ##class(OcuTalon.Schedule.Reminder).StartFrom($this, pInput, .pOutput)
	Set lock = ##class(OcuTalon.Schedule.Heartbeat).#LOCK
	Lock +@lock:5
	If '$Test Quit $$$OK
	Set sc = $$$OK
	Try {
		Set previous = ##class(OcuTalon.Data.StatusMark).Get(##class(OcuTalon.Schedule.Heartbeat).#TICKMARK)
		Set tick = ##class(OcuTalon.Schedule.Heartbeat).Next(previous, ##class(OcuTalon.Data.Time).NowUtc(), .missed)
		If ..TargetBuilt() Set sc = ..SendRequestAsync(##class(OcuTalon.Schedule.Heartbeat).#TARGET, tick)
		If $$$ISOK(sc) Set sc = ##class(OcuTalon.Schedule.Heartbeat).Record(tick, missed)
		If $$$ISOK(sc) Set pOutput = tick
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Lock -@lock
	Quit sc
}

/// 0 when the class behind Checks in the running production carries STUB, and 1 for any other class. When the item has no
/// class, 1: the send then fails and says why.
ClassMethod TargetBuilt() As %Boolean
{
	Set class = $Get($$$ConfigClassName(##class(OcuTalon.Schedule.Heartbeat).#TARGET))
	If class = "" Quit 1
	Quit '$Parameter(class, "STUB")
}

}
