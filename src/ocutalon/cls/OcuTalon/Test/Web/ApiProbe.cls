/// A subclass of OcuTalon.Web.Api for the tests, which overrides its private Post so that the REST tests run on a slot with no
/// production (Story 2.4; AD-22). It has no Test methods and the product never refers to it. Post hands the input to a shadow
/// instance of Test.Core.WebChatInProbe, which records under the run number in ^OcuTalonTest("ApiProbe", "run");
/// ^OcuTalonTest("ApiProbe", "mode") is "" to let the message through and "fail" to answer an error status, as a production
/// that can't take the message does. Press (Story 4.3) answers instead of BreakFeedIn: it records the session of each press under
/// ^OcuTalonTest("ApiProbe", "presses", n) and answers the text in ^OcuTalonTest("ApiProbe", "press"): "fail" is an error status, any
/// other text is the service's output as it is, and an absent value is a sent press.
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

/// The press that BreakFeedIn would carry out, answered from ^OcuTalonTest("ApiProbe", "press").
ClassMethod Press(input As %RegisteredObject, Output output As %String) As %Status [ Private ]
{
	Set output = ""
	Set n = $Increment(^OcuTalonTest("ApiProbe", "presses"))
	Set ^OcuTalonTest("ApiProbe", "presses", n) = input.SessionRef
	Set answer = $Get(^OcuTalonTest("ApiProbe", "press"), {"outcome": "sent", "state": "sent", "startedAt": "2030-01-01T10:00:00Z"}.%ToJSON())
	If answer = "fail" Quit $SYSTEM.Status.Error(5001, "zz BreakFeedIn is not running")
	Set output = answer
	Quit $SYSTEM.Status.OK()
}

}
