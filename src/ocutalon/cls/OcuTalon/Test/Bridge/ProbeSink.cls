/// A host sink for the tests of Decide (Story 1.3). Its mode comes from ^||ZzProbeSink("mode"):
///   - record (the default): OnEvent returns OK;
///   - error: OnEvent returns an error status;
///   - throw: OnEvent throws.
/// Every call is kept in ^||ZzProbeSink(<call>) as a $ListBuild of the type, the owner, the payload as JSON, $TLevel, and 1 when
/// the Decision row that the payload's ref names exists at that moment. ^||ZzProbeSink holds the number of calls. The test
/// that sets the global kills it.
Class OcuTalon.Test.Bridge.ProbeSink Extends OcuTalon.Bridge.Ext.HostSink
{

ClassMethod OnEvent(type As %String, ownerRef As %String, payload As %DynamicObject) As %Status
{
	Set n = $Increment(^||ZzProbeSink)
	Set ^||ZzProbeSink(n) = $ListBuild(type, ownerRef, payload.%ToJSON(), $TLevel, ##class(OcuTalon.Bridge.Data.Decision).RefIndexExists(payload.ref))
	Set mode = $Get(^||ZzProbeSink("mode"), "record")
	If mode = "error" Quit $$$ERROR($$$GeneralError, "The probe sink was set to fail")
	If mode = "throw" Throw ##class(%Exception.General).%New("ProbeSink", 5001, , "The probe sink was set to throw")
	Quit $$$OK
}

}
