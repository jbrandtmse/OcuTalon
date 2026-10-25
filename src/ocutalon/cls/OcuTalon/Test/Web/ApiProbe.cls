/// A subclass of OcuTalon.Web.Api for the tests, which overrides its private Post so that the REST tests run on a slot with no
/// production (Story 2.4; AD-22). It has no Test methods and the product never refers to it. Post hands the input to a shadow
/// instance of Test.Core.WebChatInProbe, which records under the run number in ^OcuTalonTest("ApiProbe", "run");
/// ^OcuTalonTest("ApiProbe", "mode") is "" to let the message through and "fail" to answer an error status, as a production
/// that can't take the message does.
Class OcuTalon.Test.Web.ApiProbe Extends OcuTalon.Web.Api
{

ClassMethod Post(input As %RegisteredObject, Output output As %String) As %Status [ Private ]
{
	Set output = ""
	If $Get(^OcuTalonTest("ApiProbe", "mode")) = "fail" Quit $SYSTEM.Status.Error(5001, "zz the production is not running")
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.WebChatInProbe", .sc)
	If '$IsObject(probe) Quit sc
	Set probe.RunNumber = $Get(^OcuTalonTest("ApiProbe", "run"))
	Quit probe.OnProcessInput(input, .output)
}

}
