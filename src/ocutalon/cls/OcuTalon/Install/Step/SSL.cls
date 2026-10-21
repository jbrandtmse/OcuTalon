/// The SSL step: creates the SSL configurations.
/// It does nothing yet; the first story that needs a client SSL configuration fills it in place, and the registry's order stays as it is.
Class OcuTalon.Install.Step.SSL Extends OcuTalon.Install.Step
{

ClassMethod Run() As %Status
{
	Quit $SYSTEM.Status.OK()
}

}
