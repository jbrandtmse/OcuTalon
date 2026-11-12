/// A subclass of OcuTalon.Channel.Webhook.In for the tests (Story 35.3), which overrides its private Send so that the unit tests run on a slot with no
/// production. It has no Test methods and the product never refers to it. Send records a call under ^OcuTalonTest("WebhookIn", n), with n counted in
/// ^OcuTalonTest("WebhookIn"): target, class, the %SuperSession of the service, and for an Item its itemId, sessionRef, channel, provenance, subject,
/// text, sender and fromGuide. When ^OcuTalonTest("WebhookIn", "mode") is "fail" it answers an error status after it records the call.
Class OcuTalon.Test.Web.WebhookInProbe Extends OcuTalon.Channel.Webhook.In
{

Method Send(target As %String, request As %Library.Persistent) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("WebhookIn"))
	Set call = $Name(^OcuTalonTest("WebhookIn", n))
	Set @call@("target") = target
	Set @call@("class") = $ClassName(request)
	Set @call@("superSession") = ..%SuperSession
	If request.%Extends("OcuTalon.Msg.Item") {
		Set @call@("itemId") = request.ItemId
		Set @call@("sessionRef") = request.SessionRef
		Set @call@("channel") = request.Channel
		Set @call@("provenance") = request.Provenance
		Set @call@("subject") = request.Subject
		Set @call@("text") = request.Text
		Set @call@("sender") = request.Sender
		Set @call@("fromGuide") = request.FromGuide
	}
	If $Get(^OcuTalonTest("WebhookIn", "mode")) = "fail" Quit $SYSTEM.Status.Error(5001, "zz Intake is not running")
	Quit $SYSTEM.Status.OK()
}

}
