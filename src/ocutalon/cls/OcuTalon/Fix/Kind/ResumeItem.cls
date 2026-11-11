/// The fix kind that resumes (enables) an item of the incident's production, the undo of SuspendItem (Story 23.2): everything but its name and the direction of the change is
/// SuspendItem's. Lane A.
Class OcuTalon.Fix.Kind.ResumeItem Extends OcuTalon.Fix.Kind.SuspendItem
{

Parameter NAME = "resume_item";

Parameter ENABLE = 1;

}
