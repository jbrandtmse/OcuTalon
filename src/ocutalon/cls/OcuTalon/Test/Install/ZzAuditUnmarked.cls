/// The Audit step with a status mark that cannot be written (ZzAuditSeam): the step's mark-write warning. A fixture of
/// OcuTalon.Test.Install.Audit, never part of a production; it is not an area of the registry, which takes only OcuTalon.Install.Step.* classes.
Class OcuTalon.Test.Install.ZzAuditUnmarked Extends OcuTalon.Install.Step.Audit
{

Parameter MARKS = "OcuTalon.Test.Install.ZzAuditSeam";

}
