/// The payload of the phone live event: one message of the simulated phone. Lane B publishes it.
Class OcuTalon.Live.Payload.Phone Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The message's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// One of in, out.
Property Direction As %String(%JSONFIELDNAME = "direction", MAXLEN = 32);

/// The message text.
Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = "");

/// The approval request's Ref, when the message asks for one.
Property ApprovalRef As %String(%JSONFIELDNAME = "approvalRef", MAXLEN = 22);

/// The answered line in message form that replaced the message's Approve and Reject; empty while it has them.
Property Answer As %String(%JSONFIELDNAME = "answer", MAXLEN = 1000);

/// The Ref of the Decision behind a tell-now message, which is what the page's Got it control names; empty for any other message.
Property DecisionRef As %String(%JSONFIELDNAME = "decisionRef", MAXLEN = 22);

/// When the message was created, UTC to the second.
Property CreatedAt As %String(%JSONFIELDNAME = "createdAt", MAXLEN = 20);

/// The payload for a phone message: ref, direction, text, approvalRef, answer, decisionRef and createdAt from the row. A row written before
/// ApprovalRef, Answer and DecisionRef existed gives them empty, except that a message with no ApprovalRef and no stored DecisionRef gets its
/// decisionRef from Ownership.PhoneDecision (the session's phone Delivery row of kind tellnow); a failed read leaves it empty.
ClassMethod FromRow(row As OcuTalon.Data.SimMessage) As OcuTalon.Live.Payload.Phone
{
	Set payload = ..%New()
	Set payload.Ref = row.Ref
	Set payload.Direction = row.Direction
	Set payload.Text = row.Text
	Set payload.ApprovalRef = row.ApprovalRef
	Set payload.Answer = row.Answer
	Set payload.DecisionRef = row.DecisionRef
	Set payload.CreatedAt = row.CreatedAt
	If (row.ApprovalRef = "") && (payload.DecisionRef = "") {
		Set decisionRef = ##class(OcuTalon.Data.Ownership).PhoneDecision(row.Ref, row.SessionRef, .sc)
		If $SYSTEM.Status.IsOK(sc) Set payload.DecisionRef = decisionRef
	}
	Quit payload
}

}
