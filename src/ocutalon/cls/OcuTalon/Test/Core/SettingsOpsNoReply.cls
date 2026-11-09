/// A subclass of OcuTalon.Core.SettingsOps for the tests whose SendRequestSync stands in for the wait on Decide, so that the real BridgeTest runs against the real
/// Bridge.Settings.TestRequest and TestAnswer. The answer comes from ^||OcuTalonSettingsOpsNoReply("mode"), a process-private global: "" is an OK status with no
/// response (the wait expired), "error" is an error status. The request that it was asked to send is recorded in ^||OcuTalonSettingsOpsNoReply("sent") as its ItemId
/// and the wait. The product never refers to it.
Class OcuTalon.Test.Core.SettingsOpsNoReply Extends OcuTalon.Core.SettingsOps
{

Method SendRequestSync(pTargetDispatchName As %String, pRequest As %Library.Persistent, ByRef pResponse As %Library.Persistent, pTimeout As %Numeric = -1, pDescription As %String = "") As %Status
{
	Set pResponse = ""
	Set ^||OcuTalonSettingsOpsNoReply("sent") = pTargetDispatchName_"|"_pRequest.ItemId_"|"_pTimeout
	If $Get(^||OcuTalonSettingsOpsNoReply("mode")) = "error" Quit $SYSTEM.Status.Error(5001, "zz send failed")
	Quit $$$OK
}

}
