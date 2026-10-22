/// A host sink for the tests of Decide and Budget (Stories 1.3 and 1.4). Its mode comes from ^||ZzProbeSink("mode"):
///   - record (the default): OnEvent returns OK;
///   - error: OnEvent returns an error status;
///   - throw: OnEvent throws.
/// Every call is kept in ^||ZzProbeSink(<call>) as a $ListBuild of the type, the owner, the payload as JSON, $TLevel, 1 when the
/// Decision row that the payload's ref names exists at that moment (empty when the payload has no ref), and 1 when the day mark
/// ^OcuTalonBP.UsageCapped(<the payload's day>) exists at that moment, else 0 (empty when the payload has no day), and 1 when any
/// process holds the lock of that day's mark at that moment (LockHeld), else 0 (empty when the payload has no day).
/// ^||ZzProbeSink holds the number of calls. The test that sets the global kills it.
Class OcuTalon.Test.Bridge.ProbeSink Extends OcuTalon.Bridge.Ext.HostSink
{

ClassMethod OnEvent(type As %String, ownerRef As %String, payload As %DynamicObject) As %Status
{
	Set n = $Increment(^||ZzProbeSink)
	Set ref = payload.%Get("ref")
	Set day = payload.%Get("day")
	Set ^||ZzProbeSink(n) = $ListBuild(type, ownerRef, payload.%ToJSON(), $TLevel, $Select(ref '= "": ##class(OcuTalon.Bridge.Data.Decision).RefIndexExists(ref), 1: ""), $Select(day '= "": $Data(^OcuTalonBP.UsageCapped(day)) > 0, 1: ""), $Select(day '= "": ..LockHeld(day), 1: ""))
	Set mode = $Get(^||ZzProbeSink("mode"), "record")
	If mode = "error" Quit $$$ERROR($$$GeneralError, "The probe sink was set to fail")
	If mode = "throw" Throw ##class(%Exception.General).%New("ProbeSink", 5001, , "The probe sink was set to throw")
	Quit $$$OK
}

/// 1 when any process holds the lock of the day's mark, ^OcuTalonBP.UsageCapped(day), at this moment, as the lock table shows it
/// (^$LOCK); otherwise 0.
ClassMethod LockHeld(day As %String) As %Boolean
{
	Set held = 0
	Set name = ""
	For {
		Set name = $Order(^$LOCK(name))
		If name = "" Quit
		If name [ ("UsageCapped(""" _ day _ """)") {
			Set held = 1
			Quit
		}
	}
	Quit held
}

}
