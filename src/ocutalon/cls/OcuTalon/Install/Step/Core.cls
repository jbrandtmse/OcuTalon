/// The Core area's declaration for the purge task (AD-23, AD-27): the old Telegram pairing rows go with the task's own day count. The area
/// is not in OcuTalon.Install.Registry Order(), so it runs no step; it only declares, and the registry finds it by its name.
Class OcuTalon.Install.Step.Core Extends OcuTalon.Install.Step
{

/// Removes the pairing rows that no writer touched for daysToKeep days and that hold no session (Data.Pairing.Purge), and the precedents answered
/// more than daysToKeep days ago (Data.Precedent.Purge; AD-21, AD-27). The day count comes only from the caller: the purge task's DaysToKeep. Both
/// purges run, and the result is the first error.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Set sc = ##class(OcuTalon.Data.Pairing).Purge(daysToKeep)
	Set precedents = ##class(OcuTalon.Data.Precedent).Purge(daysToKeep)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Quit precedents
}

}
