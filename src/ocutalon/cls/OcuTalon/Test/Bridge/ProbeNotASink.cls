/// A class with the OnEvent signature of a host sink that does not extend OcuTalon.Bridge.Ext.HostSink (Story 1.3), for the tests
/// of Decide: Decide must refuse it as a HostSinkClass and send it no event. It counts its calls in the process-private global
/// ^||ZzProbeSink, which the test that sets it kills.
Class OcuTalon.Test.Bridge.ProbeNotASink
{

ClassMethod OnEvent(type As %String, ownerRef As %String, payload As %DynamicObject) As %Status
{
	Set n = $Increment(^||ZzProbeSink)
	Quit $$$OK
}

}
