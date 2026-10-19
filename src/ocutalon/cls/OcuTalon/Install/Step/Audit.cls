/// The Audit step: confirms that OcuTalon's audit events are registered and enabled (AD-17, AD-23).
/// OcuTalon.Bridge.Installer registers them in its own step, which runs first; this step fails the start,
/// naming the event, when one is missing or disabled.
Class OcuTalon.Install.Step.Audit Extends OcuTalon.Install.Step
{

ClassMethod Run() As %Status
{
	Quit ##class(OcuTalon.Bridge.Installer).CheckAudit()
}

}
