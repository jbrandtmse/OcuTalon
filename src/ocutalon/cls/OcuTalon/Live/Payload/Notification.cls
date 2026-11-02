/// The payload of the notification live event: one notice card in the chat. Lane B publishes it (WebChatOut, the only
/// publisher) and the snapshot's chat holds the same payload for each kept card (Ownership.RecentNotices).
Class OcuTalon.Live.Payload.Notification Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The notification's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// One of Msg.Enum NOTIFICATIONKIND.
Property Kind As %String(%JSONFIELDNAME = "kind", MAXLEN = 32);

/// The rendered notice text; for a tell-now card it is the text without its last line, the "Why now:" line (WhyNow).
Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = "");

/// Why the notice came now: the last line of a tell-now card's text; empty for any other card.
Property WhyNow As %String(%JSONFIELDNAME = "whyNow", MAXLEN = 1000);

/// The decision's Ref, when the notice is about one.
Property DecisionRef As %String(%JSONFIELDNAME = "decisionRef", MAXLEN = 22);

/// The incident's Ref, when the notice is about one.
Property IncidentRef As %String(%JSONFIELDNAME = "incidentRef", MAXLEN = 22);

/// The approval request's Ref, when the notice asks for one.
Property ApprovalRef As %String(%JSONFIELDNAME = "approvalRef", MAXLEN = 22);

/// When the thing the notice is about is due, UTC to the second.
Property DueAt As %String(%JSONFIELDNAME = "dueAt", MAXLEN = 20);

/// When the notice was created, UTC to the second.
Property CreatedAt As %String(%JSONFIELDNAME = "createdAt", MAXLEN = 20);

/// The decision behind the notice (AD-20), as the card's strip shows it; empty when the notice has none or the session cannot see it.
Property Decision As OcuTalon.Live.Payload.Decision(%JSONFIELDNAME = "decision");

/// The reason of a fallback notice: one of Msg.Enum FALLBACKREASON; empty when the notice is not a fallback.
Property FallbackReason As %String(%JSONFIELDNAME = "fallbackReason", MAXLEN = 32);

/// The payload for a web notice card's Delivery row, with every field set from the row: ref (the row's ChannelMessageId),
/// kind, decisionRef, approvalRef, dueAt, fallbackReason and createdAt (the row's RecordedAt). For a tell-now card whose text
/// has two or more lines, text is every line but the last and whyNow is the last line; any other text is whole, with an
/// empty whyNow. decision is Decision.FromRow of the row the owner sees under DecisionRef; a read that fails or finds nothing
/// leaves it empty and never fails the payload.
ClassMethod FromRow(row As OcuTalon.Data.Delivery) As OcuTalon.Live.Payload.Notification
{
	Set payload = ..%New()
	Set payload.Ref = row.ChannelMessageId
	Set payload.Kind = row.Kind
	Set payload.DecisionRef = row.DecisionRef
	Set payload.ApprovalRef = row.ApprovalRef
	Set payload.DueAt = row.DueAt
	Set payload.FallbackReason = row.FallbackReason
	Set payload.CreatedAt = row.RecordedAt
	Set lines = $Length(row.Text, $Char(10))
	If (row.Kind = "tellnow") && (lines >= 2) {
		Set payload.Text = $Piece(row.Text, $Char(10), 1, lines - 1)
		Set payload.WhyNow = $Piece(row.Text, $Char(10), lines)
	} Else {
		Set payload.Text = row.Text
	}
	Do ..SetDecision(payload, row)
	Quit payload
}

/// Sets the payload's decision from the row's DecisionRef, when the row's owner sees that decision.
ClassMethod SetDecision(payload As OcuTalon.Live.Payload.Notification, row As OcuTalon.Data.Delivery) [ Private ]
{
	If (row.DecisionRef = "") || (row.OwnerRef = "") Quit
	Try {
		Set decision = ##class(OcuTalon.Data.Ownership).Decision(row.DecisionRef, row.OwnerRef, .sc)
		If $SYSTEM.Status.IsError(sc) || '$IsObject(decision) Quit
		Set payload.Decision = ##class(OcuTalon.Live.Payload.Decision).FromRow(decision)
	} Catch exception {
		Set payload.Decision = ""
	}
}

}
