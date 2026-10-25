/// ApprovalStartIn, the adapterless service through which any job starts the hold of one approval request (AD-11): the gate's
/// %CanExecute through Approval.Raise (synchronously), IncidentManager, and the Reconcile step through Approval.Reconcile. It takes an
/// OcuTalon.Bridge.Msg.ApprovalStart and sends it to ApprovalHold with a time limit of Approval STARTSECONDS. The hold answers once it has
/// sent its Workflow task and set its timer, so the call returns while the hold keeps waiting. The hold joins the session and SuperSession
/// that the message carries (AD-26); the service base clears both before OnProcessInput, so they are set there.
Class OcuTalon.Bridge.Service.ApprovalStart Extends Ens.BusinessService
{

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	If '$IsObject(pInput) || '$ClassMethod($ClassName(pInput), "%Extends", "OcuTalon.Bridge.Msg.ApprovalStart") || (pInput.Ref = "") {
		Quit $SYSTEM.Status.Error(5001, "ApprovalStartIn takes an OcuTalon.Bridge.Msg.ApprovalStart with a Ref")
	}
	If pInput.SessionId > 0 Set ..%SessionId = pInput.SessionId
	Set ..%SuperSession = pInput.SuperSession
	Quit ..SendRequestSync(##class(OcuTalon.Bridge.Approval).#HOLDITEM, pInput, .pOutput, ##class(OcuTalon.Bridge.Approval).#STARTSECONDS)
}

}
