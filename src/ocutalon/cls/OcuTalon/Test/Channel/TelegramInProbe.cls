Include Ensemble

/// A subclass of OcuTalon.Channel.Telegram.In for the tests, which overrides the four private seams of a paired chat's turn so that
/// OcuTalon.Test.Channel.TelegramInTurn runs a turn with no production (Story 12.6; AD-22). It has no Test methods and the product never refers
/// to it.
///   - Run calls the service's Turn for the session and the text.
///   - Every seam records a call under ^OcuTalonTest("TelegramInProbe", RunNumber, n), with n counted in ^OcuTalonTest("TelegramInProbe",
///     RunNumber):
///       - Allowed (target allowed, sessionRef, channel and text) answers 0 when Refuse is 1 (retryAt 2030-01-01T00:00:00Z and firstRefusal
///         FirstRefusal) or RefuseBusy is 1 (an empty retryAt), otherwise 1, and deletes the session's row after the record when DropRow is 1;
///       - SendTurn (target Conversation) records the %SessionId and %SuperSession of the service and the Item's fields; then NewSession,
///         when it is set and the service has no %SessionId, becomes the %SessionId and the job's session id, as the framework sets them
///         after a send; FailSend makes it answer an error, and ThrowSend makes it throw;
///       - Notify (target Notify) records the Notification's sessionRef, kind, catalogKey and chatRef and the service's %SessionId and
///         %SuperSession; FailNotify makes it answer an error;
///       - Refund (target refund) records the sessionRef; ThrowRefund makes it throw after the record.
Class OcuTalon.Test.Channel.TelegramInProbe Extends OcuTalon.Channel.Telegram.In
{

/// The subscript of the run under ^OcuTalonTest("TelegramInProbe").
Property RunNumber As %String [ Transient ];

/// 1 when Allowed refuses every message with a retryAt.
Property Refuse As %Boolean [ InitialExpression = 0, Transient ];

/// 1 when Allowed's refusal is the first of its window.
Property FirstRefusal As %Boolean [ InitialExpression = 1, Transient ];

/// 1 when Allowed refuses with no retryAt, as it does when the session's lock was busy or it threw.
Property RefuseBusy As %Boolean [ InitialExpression = 0, Transient ];

/// 1 when Notify answers an error status after it records the call.
Property FailNotify As %Boolean [ InitialExpression = 0, Transient ];

/// 1 when Allowed deletes the session's row after it records the call, so that the join of the trace thread fails.
Property DropRow As %Boolean [ InitialExpression = 0, Transient ];

/// The session id that a send starts when the service has none; empty for none.
Property NewSession As %Integer [ Transient ];

/// 1 when SendTurn answers an error status after it records the call.
Property FailSend As %Boolean [ InitialExpression = 0, Transient ];

/// 1 when SendTurn throws after it records the call.
Property ThrowSend As %Boolean [ InitialExpression = 0, Transient ];

/// 1 when Refund throws after it records the call.
Property ThrowRefund As %Boolean [ InitialExpression = 0, Transient ];

/// A paired chat's text as the session's turn.
Method Run(sessionRef As %String, text As %String)
{
	Do ..Turn(sessionRef, text)
}

/// Records a call of the target and returns its node.
Method Note(target As %String) As %String [ Private ]
{
	Set n = $Increment(^OcuTalonTest("TelegramInProbe", ..RunNumber))
	Set call = $Name(^OcuTalonTest("TelegramInProbe", ..RunNumber, n))
	Set @call@("target") = target
	Quit call
}

Method SendTurn(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	Set call = ..Note(..#TARGET)
	Set @call@("sessionId") = ..%SessionId
	Set @call@("superSession") = ..%SuperSession
	Set @call@("sessionRef") = item.SessionRef
	Set @call@("channel") = item.Channel
	Set @call@("provenance") = item.Provenance
	Set @call@("text") = item.Text
	Set @call@("clientId") = item.ClientId
	Set @call@("fromGuide") = item.FromGuide
	If (..NewSession '= "") && (..%SessionId = "") Set (..%SessionId, $$$JobSessionId) = ..NewSession
	If ..ThrowSend Throw ##class(%Exception.General).%New("zz send threw")
	If ..FailSend Quit $SYSTEM.Status.Error(5001, "zz send failed")
	Quit $SYSTEM.Status.OK()
}

Method Notify(notification As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Set call = ..Note(..#NOTIFY)
	Set @call@("sessionRef") = notification.SessionRef
	Set @call@("kind") = notification.Kind
	Set @call@("catalogKey") = notification.CatalogKey
	Set @call@("chatRef") = notification.ChatRef
	Set @call@("sessionId") = ..%SessionId
	Set @call@("superSession") = ..%SuperSession
	If ..FailNotify Quit $SYSTEM.Status.Error(5001, "zz notify failed")
	Quit $SYSTEM.Status.OK()
}

Method Refund(sessionRef As %String) [ Private ]
{
	Set call = ..Note("refund")
	Set @call@("sessionRef") = sessionRef
	If ..ThrowRefund Throw ##class(%Exception.General).%New("zz refund threw")
}

Method Allowed(sessionRef As %String, channel As %String, text As %String, Output retryAt As %String, Output firstRefusal As %Boolean) As %Boolean [ Private ]
{
	Set call = ..Note("allowed")
	Set @call@("sessionRef") = sessionRef
	Set @call@("channel") = channel
	Set @call@("text") = text
	Set retryAt = "", firstRefusal = 0
	If ..Refuse {
		Set retryAt = "2030-01-01T00:00:00Z"
		Set firstRefusal = ..FirstRefusal
		Quit 0
	}
	If ..RefuseBusy Quit 0
	If ..DropRow Do ##class(OcuTalon.Data.Session).RefIndexDelete(sessionRef)
	Quit 1
}

}
