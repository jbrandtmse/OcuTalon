/// A subclass of OcuTalon.Channel.WebChat.In for the tests, which overrides its two private seams so that the unit tests run on a
/// slot with no production (Story 2.4; AD-22). It has no Test methods and the product never refers to it.
///   - Allowed records a call under ^OcuTalonTest("WebChatIn", RunNumber, n), with n counted in ^OcuTalonTest("WebChatIn",
///     RunNumber): target allowed, sessionRef, channel and text; it answers 0 when Refuse is 1, otherwise what the allowance says;
///   - Send records a call the same way: target, class, the %SuperSession of the service, for an Item its itemId, sessionRef,
///     channel, provenance, text, fromGuide and clientId, for a RunTurns its sessionRef. FailSend makes it answer an error.
Class OcuTalon.Test.Core.WebChatInProbe Extends OcuTalon.Channel.WebChat.In
{

/// The subscript of the run under ^OcuTalonTest("WebChatIn").
Property RunNumber As %String [ Transient ];

/// 1 when Allowed refuses every message.
Property Refuse As %Boolean [ InitialExpression = 0, Transient ];

/// 1 when Send answers an error status after it records the call.
Property FailSend As %Boolean [ InitialExpression = 0, Transient ];

Method Send(target As %String, request As %Library.Persistent) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("WebChatIn", ..RunNumber))
	Set call = $Name(^OcuTalonTest("WebChatIn", ..RunNumber, n))
	Set @call@("target") = target
	Set @call@("class") = $ClassName(request)
	Set @call@("superSession") = ..%SuperSession
	If request.%Extends("OcuTalon.Msg.Item") {
		Set @call@("itemId") = request.ItemId
		Set @call@("sessionRef") = request.SessionRef
		Set @call@("channel") = request.Channel
		Set @call@("provenance") = request.Provenance
		Set @call@("text") = request.Text
		Set @call@("fromGuide") = request.FromGuide
		Set @call@("clientId") = request.ClientId
	} ElseIf request.%Extends("OcuTalon.Core.Msg.RunTurns") {
		Set @call@("sessionRef") = request.SessionRef
	}
	If ..FailSend Quit $SYSTEM.Status.Error(5001, "zz send failed")
	Quit $SYSTEM.Status.OK()
}

Method Allowed(sessionRef As %String, channel As %String, text As %String, Output retryAt As %String, Output firstRefusal As %Boolean) As %Boolean [ Private ]
{
	Set n = $Increment(^OcuTalonTest("WebChatIn", ..RunNumber))
	Set call = $Name(^OcuTalonTest("WebChatIn", ..RunNumber, n))
	Set @call@("target") = "allowed"
	Set @call@("sessionRef") = sessionRef
	Set @call@("channel") = channel
	Set @call@("text") = text
	If ..Refuse {
		Set retryAt = "2030-01-01T00:00:00Z"
		Set firstRefusal = 1
		Quit 0
	}
	Quit ##super(sessionRef, channel, text, .retryAt, .firstRefusal)
}

}
