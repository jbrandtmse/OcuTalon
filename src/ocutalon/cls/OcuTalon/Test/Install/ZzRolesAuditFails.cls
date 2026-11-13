/// A subclass of OcuTalon.Install.Step.Roles for the tests (Story 25.4): its audit write fails, so Test.Install.RolesAssign can pin that Assign puts a role change
/// back when its entry cannot be written. It has no Test methods and the product never refers to it.
Class OcuTalon.Test.Install.ZzRolesAuditFails Extends OcuTalon.Install.Step.Roles
{

ClassMethod Audit(data As %DynamicObject) As %Status [ Private ]
{
	Set ^OcuTalonTest("RolesAssign", "auditCalls") = $Get(^OcuTalonTest("RolesAssign", "auditCalls")) + 1
	Quit $SYSTEM.Status.Error(5001, "zz audit write failed")
}

}
