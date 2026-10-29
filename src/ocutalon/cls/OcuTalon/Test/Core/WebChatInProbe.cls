/// A subclass of OcuTalon.Channel.WebChat.In for the tests, which overrides its three private seams so that the unit tests run on a
/// slot with no production (Story 2.4; AD-22). It has no Test methods and the product never refers to it.
///   - Allowed records a call under ^OcuTalonTest("WebChatIn", RunNumber, n), with n counted in ^OcuTalonTest("WebChatIn",
///     RunNumber): target allowed, sessionRef, channel and text; it answers 0 when Refuse is 1 (retryAt 2030-01-01T00:00:00Z and
///     firstRefusal FirstRefusal) or RefuseBusy is 1 (an empty retryAt, a lock that was busy), otherwise what the allowance says;
///   - Send records a call the same way: target, class, the %SessionId and the %SuperSession of the service, for an Item its
///     itemId, sessionRef, channel, provenance, text, fromGuide and clientId, for a RunTurns its sessionRef, for a Notification its
///     sessionRef, kind, catalogKey and slots. After it records, NewSession, when it is set and the service has no %SessionId,
///     becomes the service's %SessionId, as the framework sets it from the header of a message that starts a session. FailSend
///     makes it answer an error, FailNotice makes it answer an error for a send to Notify only, ThrowSend makes it throw, and
///     DropRow deletes the session's row, after the record in every case;
///   - Refund records a call with the target refund and the sessionRef, and gives nothing back unless RealRefund is 1, when it then
///     gives the entry back through the service's own Refund.
Class OcuTalon.Test.Core.WebChatInProbe Extends OcuTalon.Channel.WebChat.In
{

/// The subscript of the run under ^OcuTalonTest("WebChatIn").
Property RunNumber As %String [ Transient ];

/// 1 when Allowed refuses every message.
Property Refuse As %Boolean [ InitialExpression = 0, Transient ];

/// 1 when Allowed's refusal is the first of its window.
Property FirstRefusal As %Boolean [ InitialExpression = 1, Transient ];

/// 1 when Allowed refuses with no retryAt, as it does when the session's lock was busy or it threw.
Property RefuseBusy As %Boolean [ InitialExpression = 0, Transient ];

/// 1 when a send to Notify answers an error status after it records the call.
Property FailNotice As %Boolean [ InitialExpression = 0, Transient ];

/// The session id that a send starts when the service has none, as the framework gives it after a send; empty for none.
Property NewSession As %Integer [ Transient ];

/// 1 when Send answers an error status after it records the call.
Property FailSend As %Boolean [ InitialExpression = 0, Transient ];

/// 1 when Send throws after it records the call.
Property ThrowSend As %Boolean [ InitialExpression = 0, Transient ];

/// 1 when Send deletes the row of the Item's session after it records the call.
Property DropRow As %Boolean [ InitialExpression = 0, Transient ];

/// 1 when Refund, after it records the call, also runs the service's own Refund.
Property RealRefund As %Boolean [ InitialExpression = 0, Transient ];

Method Send(target As %String, request As %Library.Persistent) As %Status [ Private ]
{
	Set n = $Increment(^OcuTalonTest("WebChatIn", ..RunNumber))
	Set call = $Name(^OcuTalonTest("WebChatIn", ..RunNumber, n))
	Set @call@("target") = target
	Set @call@("class") = $ClassName(request)
	Set @call@("sessionId") = ..%SessionId
	Set @call@("superSession") = ..%SuperSession
	If (..NewSession '= "") && (..%SessionId = "") Set ..%SessionId = ..NewSession
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
	} ElseIf request.%Extends("OcuTalon.Msg.Notification") {
		Set @call@("sessionRef") = request.SessionRef
		Set @call@("kind") = request.Kind
		Set @call@("catalogKey") = request.CatalogKey
		Set @call@("slots") = request.Slots
	}
	If ..DropRow && request.%Extends("OcuTalon.Msg.Item") Do ##class(OcuTalon.Data.Session).RefIndexDelete(request.SessionRef)
	If ..ThrowSend Throw ##class(%Exception.General).%New("zz send threw", 5001, , "zz send threw")
	If ..FailNotice && (target = ..#NOTIFY) Quit $SYSTEM.Status.Error(5001, "zz notice failed")
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
		Set firstRefusal = ..FirstRefusal
		Quit 0
	}
	If ..RefuseBusy {
		Set retryAt = ""
		Set firstRefusal = 0
		Quit 0
	}
	Quit ##super(sessionRef, channel, text, .retryAt, .firstRefusal)
}

Method Refund(sessionRef As %String) [ Private ]
{
	Set n = $Increment(^OcuTalonTest("WebChatIn", ..RunNumber))
	Set call = $Name(^OcuTalonTest("WebChatIn", ..RunNumber, n))
	Set @call@("target") = "refund"
	Set @call@("sessionRef") = sessionRef
	If ..RealRefund Do ##super(sessionRef)
}

}
