/// The Demo step: creates or removes the OCUORDERS namespace and what it holds.
/// It does nothing yet; the owner, Story 0.6, fills it in place, and the registry's order stays as it is.
Class OcuTalon.Install.Step.Demo Extends OcuTalon.Install.Step
{

ClassMethod Run() As %Status
{
	Quit $SYSTEM.Status.OK()
}

}
