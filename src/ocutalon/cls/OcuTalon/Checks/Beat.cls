/// The agent heartbeat's beats and the names of its settings (AD-18, AD-19). Lane A. Checks calls RunDue on every Tick, after the due checks, and RunNow
/// for a BeatNow. A beat is no background check (AD-28). RunDue, RunNow, Snapshot and Key do nothing yet: they return OK or "", write no row and send
/// nothing.
Class OcuTalon.Checks.Beat Extends %RegisteredObject
{

/// The setting names of a person's heartbeat: person.<SessionRef>.heartbeat.<name> (AD-19).
Parameter KEYS = "on,interval,from,to,checklist";

/// The allowed intervals in minutes.
Parameter INTERVALS = "30,60,120,240,480,1440";

/// The defaults of the settings: on (0 on the online demo), the interval in minutes, and the window from and to (HH:MM). The default checklist is empty.
Parameter DEFAULTON = 1;

Parameter DEFAULTONDEMO = 0;

Parameter DEFAULTINTERVAL = 30;

Parameter DEFAULTFROM = "08:00";

Parameter DEFAULTTO = "20:00";

/// The most characters that the checklist may hold.
Parameter CHECKLISTMAX = 1000;

/// Runs the beats that are due at the tick time (UTC, YYYY-MM-DDTHH:MM:SSZ).
ClassMethod RunDue(tickAt As %String) As %Status
{
	Quit $$$OK
}

/// Runs a beat now for the session.
ClassMethod RunNow(sessionRef As %String) As %Status
{
	Quit $$$OK
}

/// The snapshot of what a beat reads for the session at now.
ClassMethod Snapshot(sessionRef As %String, now As %String) As %String
{
	Quit ""
}

/// The key of a snapshot.
ClassMethod Key(snapshot As %String) As %String
{
	Quit ""
}

/// The settings key of the session for a name in KEYS, else "".
ClassMethod SettingKey(sessionRef As %String, name As %String) As %String
{
	If name = "" || '$ListFind($ListFromString(..#KEYS), name) Quit ""
	Quit "person."_sessionRef_".heartbeat."_name
}

}
