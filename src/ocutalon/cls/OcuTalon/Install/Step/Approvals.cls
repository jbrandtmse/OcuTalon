/// The approvals area's declaration for the Reconcile step (AD-5, AD-11, AD-23): after the production starts, the bridge's holds are re-armed.
/// The area is not in OcuTalon.Install.Registry Order(), so it runs no step; it only declares, and the registry finds it by its name.
Class OcuTalon.Install.Step.Approvals Extends OcuTalon.Install.Step
{

/// Cancels the Workflow tasks that no live hold owns and starts a new hold for each pending request whose hold is gone
/// (OcuTalon.Bridge.Approval.Reconcile). It changes nothing when every pending request has its hold.
ClassMethod Reconcile() As %Status
{
	Quit ##class(OcuTalon.Bridge.Approval).Reconcile()
}

}
