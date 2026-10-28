/// The digest area's declaration for the purge task (AD-23, AD-27): the old digest items go with the task's own day count. The area is not in
/// OcuTalon.Install.Registry Order(), so it runs no step; it only declares, and the registry finds it by its name.
Class OcuTalon.Install.Step.Digest Extends OcuTalon.Install.Step
{

/// Removes the digest items recorded more than daysToKeep days ago. The day count comes only from the caller: the purge task's DaysToKeep.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Quit ##class(OcuTalon.Digest.Data.Item).Purge(daysToKeep)
}

}
