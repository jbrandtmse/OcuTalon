/// The schedule area's declaration of the heartbeat task (AD-23, AD-18; FR-32): one Task Manager task that runs
/// OcuTalon.Schedule.HeartbeatTask every minute. The area is not in OcuTalon.Install.Registry Order(), so it runs no step; it
/// only declares, and the registry finds it by its name. The Tasks step creates the task once and leaves an existing one alone.
///   - DailyFrequency 1, DailyFrequencyTime 0 and DailyIncrement 1 run it every minute; DailyStartTime 0 and DailyEndTime 0 are
///     the whole day.
///   - RescheduleOnStart 1 drops the runs that an IRIS stop missed instead of replaying them at the start, so a restart leaves one
///     gap and the next run sends the one catch-up Tick.
Class OcuTalon.Install.Step.Schedule Extends OcuTalon.Install.Step
{

/// The name of the heartbeat task.
Parameter HEARTBEATTASK = "OcuTalon heartbeat";

/// The scheduled tasks of the area: the heartbeat.
ClassMethod Tasks() As %DynamicArray
{
	Quit [{
		"name": (..#HEARTBEATTASK),
		"taskClass": "OcuTalon.Schedule.HeartbeatTask",
		"description": "Ticks the heartbeat every minute: sends one Tick to Checks, and records the tick time and any gap of missed minutes (FR-32).",
		"task": {
			"TimePeriod": 0,
			"TimePeriodEvery": 1,
			"DailyFrequency": 1,
			"DailyFrequencyTime": 0,
			"DailyIncrement": 1,
			"DailyStartTime": 0,
			"DailyEndTime": 0,
			"StartDate": (+$Horolog),
			"RescheduleOnStart": 1
		}
	}]
}

}
