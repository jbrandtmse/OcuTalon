/// The Audit step with a read of instance-wide auditing that fails (ZzAuditSeam): the step's "unknown" branch. A fixture of
/// OcuTalon.Test.Install.Audit, never part of a production; it is not an area of the registry, which takes only OcuTalon.Install.Step.* classes.
Class OcuTalon.Test.Install.ZzAuditUnreadable Extends OcuTalon.Install.Step.Audit
{

Parameter INSTALLER = "OcuTalon.Test.Install.ZzAuditSeam";

}
