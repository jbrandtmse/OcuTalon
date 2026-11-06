/// The digest area's step and declaration (AD-19, AD-23, AD-27, Story 17.5): it seeds the check thresholds and declares the area's purge.
///   - Run seeds the five checks.thresholds.* settings with their defaults (OcuTalon.Checks.Coverage THRESHOLDS) as seed values, through
///     OcuTalon.Install.Seeds: a key that exists keeps its value, so a threshold an admin changed survives a restart and an upgrade.
///   - Purge removes the digest area's old rows: the saved items, the check runs and the sent digests, each by its own time.
/// It declares no grant: the vital signs are read without a privilege that OcuTalon's roles lack.
Class OcuTalon.Install.Step.Digest Extends OcuTalon.Install.Step
{

/// Seeds the thresholds. A failure stops the start before the ready marker is written.
ClassMethod Run() As %Status
{
	Quit ##class(OcuTalon.Install.Seeds).Defaults(##class(OcuTalon.Checks.Coverage).Thresholds())
}

/// Removes the digest items recorded, the check runs finished and the digests sent more than daysToKeep days ago (each session's newest digest
/// stays). The day count comes only from the caller: the purge task's DaysToKeep. All three run whatever an earlier one returned; the result is
/// the first error.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Set sc = ##class(OcuTalon.Digest.Data.Item).Purge(daysToKeep)
	Set runs = ##class(OcuTalon.Digest.Data.CheckRun).Purge(daysToKeep)
	Set sent = ##class(OcuTalon.Digest.Data.Sent).Purge(daysToKeep)
	If $SYSTEM.Status.IsError(sc) Quit sc
	If $SYSTEM.Status.IsError(runs) Quit runs
	Quit sent
}

}
