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

/// When the message was created, UTC to the second.
Property CreatedAt As %String(%JSONFIELDNAME = "createdAt", MAXLEN = 20);

/// The payload for a phone message: ref, direction, text and createdAt from the row. ApprovalRef stays empty until the story
/// that adds Approve and Reject to the phone sets it.
ClassMethod FromRow(row As OcuTalon.Data.SimMessage) As OcuTalon.Live.Payload.Phone
{
	Set payload = ..%New()
	Set payload.Ref = row.Ref
	Set payload.Direction = row.Direction
	Set payload.Text = row.Text
	Set payload.ApprovalRef = ""
	Set payload.CreatedAt = row.CreatedAt
	Quit payload
}

}
