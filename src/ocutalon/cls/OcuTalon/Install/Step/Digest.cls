/// The digest area's step and declaration (AD-19, AD-23, AD-27, Stories 17.5 and 17.6): it seeds the digest's settings and declares the area's purge.
///   - Run seeds the five checks.thresholds.* settings with their defaults (OcuTalon.Checks.Coverage THRESHOLDS), and digest.time with its own
///     (OcuTalon.Digest.Process Seeds), as seed values, through OcuTalon.Install.Seeds: a key that exists keeps its value, so a value an admin
///     changed survives a restart and an upgrade. digest.channels is not seeded: its default lives in OcuTalon.Core.SettingsOps and is read when no
///     value is saved.
///   - Purge removes the digest area's old rows: the saved items, the check runs and the sent digests, each by its own time.
/// It declares no grant: the vital signs are read without a privilege that OcuTalon's roles lack.
Class OcuTalon.Install.Step.Digest Extends OcuTalon.Install.Step
{

/// Seeds the thresholds and the digest's settings. A failure stops the start before the ready marker is written.
ClassMethod Run() As %Status
{
	Set sc = ##class(OcuTalon.Install.Seeds).Defaults(##class(OcuTalon.Checks.Coverage).Thresholds())
	Set digest = ##class(OcuTalon.Install.Seeds).Defaults(##class(OcuTalon.Digest.Process).Seeds())
	Quit $Select($SYSTEM.Status.IsError(sc): sc, 1: digest)
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
