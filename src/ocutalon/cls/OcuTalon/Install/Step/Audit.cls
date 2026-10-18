/// The Audit step: registers OcuTalon's audit events.
/// It does nothing yet; the owner, Story 0.4, fills it in place, and the registry's order stays as it is.
Class OcuTalon.Install.Step.Audit Extends OcuTalon.Install.Step
{

ClassMethod Run() As %Status
{
	Quit $SYSTEM.Status.OK()
}

}
