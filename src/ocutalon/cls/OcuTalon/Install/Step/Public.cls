/// Writes the public settings at every start, through the accessor (AD-19), and sets readiness last.
/// Run() writes the online-demo flag from OCUTALON_ONLINE_DEMO; readiness stays cleared until Ready().
Class OcuTalon.Install.Step.Public Extends OcuTalon.Install.Step
{

/// Structural: the flag is 1 when OCUTALON_ONLINE_DEMO is 1, and 0 otherwise.
ClassMethod Run() As %Status
{
	Set demo = ($SYSTEM.Util.GetEnviron("OCUTALON_ONLINE_DEMO") = 1)
	Quit ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", demo)
}

/// The last step of a start: stores readiness.
ClassMethod Ready() As %Status
{
	Quit ##class(OcuTalon.Data.Public.Settings).SetReady()
}

}
