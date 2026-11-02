/// The Core area's declaration for the purge task (AD-23, AD-27): the old Telegram pairing rows go with the task's own day count. The area
/// is not in OcuTalon.Install.Registry Order(), so it runs no step; it only declares, and the registry finds it by its name.
Class OcuTalon.Install.Step.Core Extends OcuTalon.Install.Step
{

/// Removes the pairing rows that no writer touched for daysToKeep days and that hold no session (Data.Pairing.Purge). The day count comes
/// only from the caller: the purge task's DaysToKeep.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Quit ##class(OcuTalon.Data.Pairing).Purge(daysToKeep)
}

}
