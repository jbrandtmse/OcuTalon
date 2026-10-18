/// The Provider step: writes the Config Store entries.
/// It does nothing yet; the owner, Story 1.1, fills it in place, and the registry's order stays as it is.
Class OcuTalon.Install.Step.Provider Extends OcuTalon.Install.Step
{

ClassMethod Run() As %Status
{
	Quit $SYSTEM.Status.OK()
}

}
