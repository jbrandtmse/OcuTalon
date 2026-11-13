/// The watch area's declaration for the purge task (AD-23, AD-27): the closed incidents, with their groups and fix runs, and the old setting history go with the task's own day
/// count. The area is not in OcuTalon.Install.Registry Order(), so it runs no step; it only declares, and the registry finds it by its name.
Class OcuTalon.Install.Step.Watch Extends OcuTalon.Install.Step
{

/// Removes the incidents closed more than daysToKeep days ago (OcuTalon.Watch.IncidentManager.Purge) and the setting history older than that
/// (OcuTalon.Watch.SettingHistory.Purge, which keeps the newest snapshot of each watched production). The day count comes only from the caller: the
/// purge task's DaysToKeep. Both run whatever the other returned; the result is the first error.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Set incidents = ##class(OcuTalon.Watch.IncidentManager).Purge(daysToKeep)
	Set history = ##class(OcuTalon.Watch.SettingHistory).Purge(daysToKeep)
	If $SYSTEM.Status.IsError(incidents) Quit incidents
	Quit history
}

}
