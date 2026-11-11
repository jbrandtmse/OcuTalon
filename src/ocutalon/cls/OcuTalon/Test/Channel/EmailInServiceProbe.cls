/// A subclass of OcuTalon.Channel.Email.In for the tests (Story 21.2), which overrides its private Send so that the unit tests run on a slot with no
/// production. Send records each call under ^OcuTalonTest("EmailInServiceProbe", RunNumber, n): the target, the request's class, the service's
/// %SuperSession and, for an Item, every property; it answers an error status when FailSend is 1. The product never refers to it.
Class OcuTalon.Test.Channel.EmailInServiceProbe Extends OcuTalon.Channel.Email.In
{

/// The subscript of the run under ^OcuTalonTest("EmailInServiceProbe").
Property RunNumber As %String [ Transient ];

/// 1 when Send answers an error status after it records the call.
Property FailSend As %Boolean [ InitialExpression = 0, Transient ];

Method Send(target As %String, request As %Library.Persistent) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("EmailInServiceProbe", ..RunNumber))
	Set call = $Name(^OcuTalonTest("EmailInServiceProbe", ..RunNumber, n))
	Set @call@("target") = target
	Set @call@("class") = $ClassName(request)
	Set @call@("superSession") = ..%SuperSession
	If request.%Extends("OcuTalon.Msg.Item") {
		For name = "ItemId", "SourceItemId", "SessionRef", "Channel", "Provenance", "Text", "Sender", "Subject", "FromGuide", "CatalogKey", "Slots", "ClientId" {
			Set @call@($ZConvert($Extract(name, 1), "L")_$Extract(name, 2, *)) = $Property(request, name)
		}
	}
	If ..FailSend Quit $SYSTEM.Status.Error(5001, "zz the send failed")
	Quit $SYSTEM.Status.OK()
}

}
