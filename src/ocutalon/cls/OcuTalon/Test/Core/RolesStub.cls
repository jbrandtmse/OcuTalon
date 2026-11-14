/// The stand-in for OcuTalon.Install.Step.Roles that the tests of the roles commands give SettingsOps (through SettingsRolesProbe.RolesClass). It has the three run-time
/// calls and changes no security object. Each call is recorded under ^OcuTalonTest("RolesStub", "calls", n) as "<method>|<arguments>". The answers come from
/// ^OcuTalonTest("RolesStub", "answer"): "" is OK, "stub" is "not implemented" (code 5003) and "error" an error status; Refusal answers the code in
/// ^OcuTalonTest("RolesStub", "refusal") (the value "throw" makes it throw instead), and Holders the JSON in ^OcuTalonTest("RolesStub", "users") (an empty list when there is none).
Class OcuTalon.Test.Core.RolesStub
{

ClassMethod Record(text As %String)
{
	Set n = $Increment(^OcuTalonTest("RolesStub", "calls"))
	Set ^OcuTalonTest("RolesStub", "calls", n) = text
}

ClassMethod Refusal(userName As %String, role As %String) As %String
{
	Do ..Record("Refusal|"_userName_"|"_role)
	If $Get(^OcuTalonTest("RolesStub", "refusal")) = "throw" Throw ##class(%Exception.General).%New("zz refusal threw")
	Quit $Get(^OcuTalonTest("RolesStub", "refusal"))
}

ClassMethod Assign(userName As %String, role As %String, grant As %Boolean, Output changed As %Boolean, actingUser As %String = "", sessionRef As %String = "", channel As %String = "system") As %Status
{
	Set changed = 0
	Do ..Record("Assign|"_userName_"|"_role_"|"_grant_"|"_actingUser_"|"_sessionRef_"|"_channel)
	Set answer = $Get(^OcuTalonTest("RolesStub", "answer"))
	If answer = "stub" Quit $$$ERROR($$$NotImplemented)
	If answer = "error" Quit $SYSTEM.Status.Error(5001, "zz assign failed")
	Set changed = $Get(^OcuTalonTest("RolesStub", "changed"), 1)
	Quit $$$OK
}

ClassMethod Holders(Output users As %DynamicArray) As %Status
{
	Set users = []
	Do ..Record("Holders")
	Set answer = $Get(^OcuTalonTest("RolesStub", "answer"))
	If answer = "stub" Quit $$$ERROR($$$NotImplemented)
	If answer = "error" Quit $SYSTEM.Status.Error(5001, "zz holders failed")
	If $Get(^OcuTalonTest("RolesStub", "users")) '= "" Set users = [].%FromJSON(^OcuTalonTest("RolesStub", "users"))
	Quit $$$OK
}

}
