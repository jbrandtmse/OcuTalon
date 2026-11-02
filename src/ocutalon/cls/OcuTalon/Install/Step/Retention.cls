/// The retention area's declaration of the purge tasks (AD-27, AD-23; NFR-19): three daily tasks at 03:00 instance time in the namespace OCUTALON, and
/// the bridge's part of the purge. The area is not in OcuTalon.Install.Registry Order(), so it runs no step; it only declares, and the registry finds
/// it by its name. The Tasks step creates each task once and leaves an existing one alone, so a day count or a time that an admin changed in the Task
/// Manager is kept (AD-19). No declaration names a namespace or a user: the step runs each task in the namespace it was created in, as the installing user.
///   - the standard Ens.Util.Tasks.Purge for the heartbeat and check messages (the items HeartbeatIn and Checks), with their bodies, 7 days;
///   - the standard Ens.Util.Tasks.Purge for all of OCUTALON's Interoperability data, 90 days; unfinished sessions are kept (KeepIntegrity);
///   - the OcuTalon purge task (OcuTalon.Install.Task.Purge), 90 days, which calls the Purge(daysToKeep) of every area through the registry.
Class OcuTalon.Install.Step.Retention Extends OcuTalon.Install.Step
{

/// The name of the task that purges the heartbeat and check messages.
Parameter MESSAGESTASK = "OcuTalon purge heartbeat and check messages";

/// The name of the task that purges all Interoperability data.
Parameter ALLTASK = "OcuTalon purge Interoperability data";

/// The items whose messages the messages task purges, separated by commas with no space.
Parameter MESSAGEITEMS = "HeartbeatIn,Checks";

/// The seconds before 03:00 under which a task created today would start in the past by the time it is saved, so it starts tomorrow.
Parameter STARTMARGIN = 300;

/// The scheduled tasks of the area: the three purges.
ClassMethod Tasks() As %DynamicArray
{
	Quit [
		{
			"name": (..#MESSAGESTASK),
			"taskClass": "Ens.Util.Tasks.Purge",
			"description": "Purges heartbeat and check messages (HeartbeatIn, Checks) older than NumberOfDaysToKeep days.",
			"settings": {
				"TypesToPurge": "messages",
				"NumberOfDaysToKeep": 7,
				"optionalMessageLimitToConfigItems": (..#MESSAGEITEMS),
				"KeepIntegrity": 1,
				"BodiesToo": 1
			},
			"task": (..Schedule())
		},
		{
			"name": (..#ALLTASK),
			"taskClass": "Ens.Util.Tasks.Purge",
			"description": "Purges Interoperability data (messages, processes, logs) older than NumberOfDaysToKeep days.",
			"settings": {
				"TypesToPurge": "all",
				"NumberOfDaysToKeep": 90,
				"KeepIntegrity": 1,
				"BodiesToo": 1
			},
			"task": (..Schedule())
		},
		{
			"name": ($Parameter("OcuTalon.Install.Task.Purge", "TaskName")),
			"taskClass": "OcuTalon.Install.Task.Purge",
			"description": "Deletes OcuTalon's own records older than DaysToKeep days, and AI sessions unlinked for a day.",
			"settings": {
				"DaysToKeep": 90
			},
			"task": (..Schedule())
		}
	]
}

/// Deletes the bridge's records older than daysToKeep days and the AI sessions that no conversation link has named for a day
/// (OcuTalon.Bridge.Purge.Run). The day count comes only from the caller: the purge task's DaysToKeep.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Quit ##class(OcuTalon.Bridge.Purge).Run(daysToKeep)
}

/// The schedule of every task: daily at 03:00 instance time (DailyStartTime 10800). The Task Manager refuses a task whose first start (StartDate and
/// DailyStartTime) is not ahead of the clock, so StartDate is today while 03:00 is more than STARTMARGIN seconds away and tomorrow otherwise; the first
/// run is the next 03:00 that is more than STARTMARGIN seconds away, so a task created from 02:55 on first runs at 03:00 the next day. now is a Horolog value (default the current time). RescheduleOnStart 1 drops the runs that an IRIS stop missed instead of replaying them at the start.
ClassMethod Schedule(now As %String = "") As %DynamicObject
{
	If now = "" Set now = $Horolog
	Quit {
		"TimePeriod": 0,
		"TimePeriodEvery": 1,
		"DailyFrequency": 0,
		"DailyStartTime": 10800,
		"StartDate": ($Piece(now, ",", 1) + ($Piece(now, ",", 2) + ..#STARTMARGIN '< 10800)),
		"RescheduleOnStart": 1
	}
}

}
