Include Ensemble

/// The Task Manager task that ticks the heartbeat once a minute (AD-1, AD-18, AD-23; FR-32). Install.Step.Schedule declares
/// it and the Tasks step creates it once. A run makes the adapterless service HeartbeatIn with Ens.Director.CreateBusinessService
/// and calls ProcessInput with no input; the service sends one Tick to Checks and returns at once, without waiting for a check.
///   - While OcuTalon.Production is not the running production, or is stopping or quiescent, or HeartbeatIn is disabled, the run
///     ends OK, sends nothing and records nothing: a restart or an upgrade is not an error. The next run after the production
///     starts again finds the gap and sends the one catch-up Tick.
///   - Any other failure is returned, so that the task history shows it.
Class OcuTalon.Schedule.HeartbeatTask Extends %SYS.Task.Definition
{

Parameter TaskName = "OcuTalon heartbeat";

/// The production that the heartbeat belongs to.
Parameter PRODUCTION = "OcuTalon.Production";

/// The item that ticks.
Parameter ITEM = "HeartbeatIn";

Method OnTask() As %Status
{
	If ..Stopped() Quit $$$OK
	Set sc = ##class(Ens.Director).CreateBusinessService(..#ITEM, .service)
	If $$$ISOK(sc) Set sc = service.ProcessInput("", .tick)
	If $$$ISERR(sc) && ..Quiet(sc) Quit $$$OK
	Quit sc
}

/// 1 when OcuTalon.Production is not the running production.
ClassMethod Stopped() As %Boolean
{
	If '##class(Ens.Director).IsProductionRunning(.running) Quit 1
	Quit running '= ..#PRODUCTION
}

/// 1 when the failure of a run only means that the production is not ticking right now: the production is quiescent (it is
/// stopping or being updated), the item is disabled, or the production stopped after the run began.
ClassMethod Quiet(sc As %Status) As %Boolean
{
	If $SYSTEM.Status.Equals(sc, $$$EnsErrProductionQuiescent, $$$EnsErrConfigDisabled, $$$EnsErrProductionNotRunning) Quit 1
	Quit ..Stopped()
}

}
