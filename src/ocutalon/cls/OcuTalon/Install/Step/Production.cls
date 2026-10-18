/// The Production step: starts the production, and for now starts nothing.
/// It does nothing yet; the owner, Story 0.6, fills it in place, and the registry's order stays as it is.
Class OcuTalon.Install.Step.Production Extends OcuTalon.Install.Step
{

ClassMethod Run() As %Status
{
	Quit $SYSTEM.Status.OK()
}

}
