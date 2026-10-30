/// The watch area's declaration for the purge task (AD-23, AD-27): the closed incidents, with their groups and fix runs, go with the task's own day
/// count. The area is not in OcuTalon.Install.Registry Order(), so it runs no step; it only declares, and the registry finds it by its name.
Class OcuTalon.Install.Step.Watch Extends OcuTalon.Install.Step
{

/// Removes the incidents closed more than daysToKeep days ago (OcuTalon.Watch.IncidentManager.Purge). The day count comes only from the caller: the
/// purge task's DaysToKeep.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Quit ##class(OcuTalon.Watch.IncidentManager).Purge(daysToKeep)
}

}
