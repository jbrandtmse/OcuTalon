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

/// The Ref of the decision the "This was noise" control of the message acts on (Story 41.5): from the session's own phone tell-now Delivery row of
/// the message, for a tell-now or act notice and for a row written before DecisionRef existed; empty for a message that asks for an approval and for
/// any other message. Got it reads decisionRef, never this.
Property NoiseRef As %String(%JSONFIELDNAME = "noiseRef", MAXLEN = 22);

/// The payload for a phone message: ref, direction, text, approvalRef, answer, decisionRef and createdAt from the row (a row written before
/// ApprovalRef, Answer and DecisionRef existed gives them empty), and noiseRef: for a message with no ApprovalRef, the decision Ref of the session's
/// own phone tell-now Delivery row of the message (Ownership.PhoneDecision; a failed read leaves it empty), which covers act notices and older rows.
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
	If row.ApprovalRef = "" {
		Set noiseRef = ##class(OcuTalon.Data.Ownership).PhoneDecision(row.Ref, row.SessionRef, .sc)
		If $SYSTEM.Status.IsOK(sc) Set payload.NoiseRef = noiseRef
	}
	Quit payload
}

}
