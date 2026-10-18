/// Calls Reconcile() of every area: each re-arms its own waiters and rows (AD-5, AD-23).
Class OcuTalon.Install.Step.Reconcile Extends OcuTalon.Install.Step
{

ClassMethod Run() As %Status
{
	Quit ##class(OcuTalon.Install.Registry).CallAreas("Reconcile")
}

}
