Include Ensemble

/// A subclass of OcuTalon.Channel.Slack.In for the tests, which overrides the two private sends so that OcuTalon.Test.Channel.SlackIn runs the service with no production
/// (Story 27.1; AD-22). It has no Test methods and the product never refers to it. Every send records a call under ^OcuTalonTest("SlackInProbe", RunNumber, n), with n
/// counted in ^OcuTalonTest("SlackInProbe", RunNumber):
///   - SendTurn (target Conversation) records the %SessionId and %SuperSession of the service at the moment of the send and the Item's fields (sessionRef, channel,
///     provenance, text, sender, subject, fromGuide, itemId); then NewSession, when it is set and the service has no %SessionId, becomes the %SessionId and the
///     job's session id, as the framework sets them after a send; FailSend makes it answer an error and ThrowSend makes it throw;
///   - SendIgnored (target Intake) records the %SessionId and %SuperSession of the service and the record's kind, reason and eventId; FailIgnored makes it answer an error.
Class OcuTalon.Test.Channel.SlackInProbe Extends OcuTalon.Channel.Slack.In
{

/// The subscript of the run under ^OcuTalonTest("SlackInProbe").
Property RunNumber As %String [ Transient ];

/// 1 when SendTurn answers an error status after it records the call.
Property FailSend As %Boolean [ InitialExpression = 0, Transient ];

/// 1 when SendTurn throws after it records the call.
Property ThrowSend As %Boolean [ InitialExpression = 0, Transient ];

/// 1 when SendIgnored answers an error status after it records the call.
Property FailIgnored As %Boolean [ InitialExpression = 0, Transient ];

/// The session id that a send starts when the service has none; empty for none.
Property NewSession As %Integer [ Transient ];

/// Records a call of the target and returns its node.
Method Note(target As %String) As %String [ Private ]
{
	Set n = $Increment(^OcuTalonTest("SlackInProbe", ..RunNumber))
	Set call = $Name(^OcuTalonTest("SlackInProbe", ..RunNumber, n))
	Set @call@("target") = target
	Set @call@("sessionId") = ..%SessionId
	Set @call@("superSession") = ..%SuperSession
	Quit call
}

Method SendTurn(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	Set call = ..Note(..#TARGET)
	Set @call@("itemId") = item.ItemId
	Set @call@("sessionRef") = item.SessionRef
	Set @call@("channel") = item.Channel
	Set @call@("provenance") = item.Provenance
	Set @call@("text") = item.Text
	Set @call@("sender") = item.Sender
	Set @call@("subject") = item.Subject
	Set @call@("fromGuide") = item.FromGuide
	Set @call@("fileRef") = item.FileRef
	Set @call@("clientId") = item.ClientId
	If (..NewSession '= "") && (..%SessionId = "") Set (..%SessionId, $$$JobSessionId) = ..NewSession
	If ..ThrowSend Throw ##class(%Exception.General).%New("zz send threw")
	If ..FailSend Quit $SYSTEM.Status.Error(5001, "zz send failed")
	Quit $SYSTEM.Status.OK()
}

Method SendIgnored(ignored As OcuTalon.Channel.Slack.Ignored) As %Status [ Private ]
{
	Set call = ..Note(..#INTAKE)
	Set @call@("kind") = ignored.Kind
	Set @call@("reason") = ignored.Reason
	Set @call@("eventId") = ignored.EventId
	If ..FailIgnored Quit $SYSTEM.Status.Error(5001, "zz ignored failed")
	Quit $SYSTEM.Status.OK()
}

}
