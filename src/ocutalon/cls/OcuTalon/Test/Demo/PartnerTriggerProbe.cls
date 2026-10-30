/// A subclass of OcuTalon.Demo.PartnerTrigger for the tests, which override its private seams WriteAudit and Send so that the operation
/// runs on a slot with no production and no OCUORDERS (Story 4.3; AD-22). Each seam call is recorded under
/// ^OcuTalonTest("PartnerTriggerProbe", "calls", n) as "audit" or "send"; the audit records the data as JSON ("data") and the
/// description ("description"), the send the traceRef ("traceRef"). The answers come from ^OcuTalonTest("PartnerTriggerProbe", "answer",
/// seam): "" is OK, "error" is an error status, and for "audit" "record" hands the data to Bridge.Audit.Record and answers its status.
/// The product never refers to it.
Class OcuTalon.Test.Demo.PartnerTriggerProbe Extends OcuTalon.Demo.PartnerTrigger
{

Method WriteAudit(data As %DynamicObject, description As %String) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("PartnerTriggerProbe", "calls"))
	Set ^OcuTalonTest("PartnerTriggerProbe", "calls", n) = "audit"
	Set ^OcuTalonTest("PartnerTriggerProbe", "calls", n, "data") = data.%ToJSON()
	Set ^OcuTalonTest("PartnerTriggerProbe", "calls", n, "description") = description
	Set answer = $Get(^OcuTalonTest("PartnerTriggerProbe", "answer", "audit"))
	If answer = "record" Quit ##class(OcuTalon.Bridge.Audit).Record("Action", data)
	Quit $Select(answer = "error": $SYSTEM.Status.Error(5001, "zz audit failed"), 1: $SYSTEM.Status.OK())
}

Method Send(traceRef As %String) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("PartnerTriggerProbe", "calls"))
	Set ^OcuTalonTest("PartnerTriggerProbe", "calls", n) = "send"
	Set ^OcuTalonTest("PartnerTriggerProbe", "calls", n, "traceRef") = traceRef
	Quit $Select($Get(^OcuTalonTest("PartnerTriggerProbe", "answer", "send")) = "error": $SYSTEM.Status.Error(5001, "zz send failed"), 1: $SYSTEM.Status.OK())
}

}
