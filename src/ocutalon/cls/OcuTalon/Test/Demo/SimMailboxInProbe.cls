/// A subclass of OcuTalon.Channel.SimMailbox.In for the tests, which overrides its private Send so that the unit tests run on a
/// slot with no production (Story 4.6; AD-22). It has no Test methods and the product never refers to it. Send records each call
/// under ^OcuTalonTest("SimMailboxInProbe", RunNumber, n): the target, the request's class, the service's %SuperSession and, for an
/// Item, every property (itemId, sourceItemId, sessionRef, channel, provenance, text, sender, subject, fromGuide, catalogKey,
/// slots and clientId); it answers an error status when FailSend is 1 and throws when ThrowSend is 1.
Class OcuTalon.Test.Demo.SimMailboxInProbe Extends OcuTalon.Channel.SimMailbox.In
{

/// The subscript of the run under ^OcuTalonTest("SimMailboxInProbe").
Property RunNumber As %String [ Transient ];

/// 1 when Send answers an error status after it records the call.
Property FailSend As %Boolean [ InitialExpression = 0, Transient ];

/// 1 when Send throws after it records the call.
Property ThrowSend As %Boolean [ InitialExpression = 0, Transient ];

Method Send(target As %String, request As %Library.Persistent) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("SimMailboxInProbe", ..RunNumber))
	Set call = $Name(^OcuTalonTest("SimMailboxInProbe", ..RunNumber, n))
	Set @call@("target") = target
	Set @call@("class") = $ClassName(request)
	Set @call@("superSession") = ..%SuperSession
	If request.%Extends("OcuTalon.Msg.Item") {
		Set @call@("itemId") = request.ItemId
		Set @call@("sourceItemId") = request.SourceItemId
		Set @call@("sessionRef") = request.SessionRef
		Set @call@("channel") = request.Channel
		Set @call@("provenance") = request.Provenance
		Set @call@("text") = request.Text
		Set @call@("sender") = request.Sender
		Set @call@("subject") = request.Subject
		Set @call@("fromGuide") = request.FromGuide
		Set @call@("catalogKey") = request.CatalogKey
		Set @call@("slots") = request.Slots
		Set @call@("clientId") = request.ClientId
	}
	If ..ThrowSend Throw ##class(%Exception.General).%New("zz the send threw", 5001)
	If ..FailSend Quit $SYSTEM.Status.Error(5001, "zz the send failed")
	Quit $SYSTEM.Status.OK()
}

}
