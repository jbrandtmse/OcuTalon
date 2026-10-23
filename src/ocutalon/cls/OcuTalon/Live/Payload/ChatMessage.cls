/// The payload of the chat.message live event: one message of the chat. Lane B publishes it.
Class OcuTalon.Live.Payload.ChatMessage Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The turn's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// The page's own id for the message it sent.
Property ClientId As %String(%JSONFIELDNAME = "clientId", MAXLEN = 128);

/// One of Msg.Enum CHANNEL.
Property Channel As %String(%JSONFIELDNAME = "channel", MAXLEN = 32);

/// True when the message was sent from the guide.
Property FromGuide As %Boolean(%JSONFIELDNAME = "fromGuide") [ InitialExpression = 0 ];

/// One of queued, running, done.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 32);

/// The user's message.
Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = "");

/// The reply as it was sent; empty until the turn is done, and for a fallback.
Property ReplyText As %String(%JSONFIELDNAME = "replyText", MAXLEN = "");

/// The catalog key of a fallback reply; empty for a reply the model wrote.
Property CatalogKey As %String(%JSONFIELDNAME = "catalogKey", MAXLEN = 128);

/// The reason of a fallback reply: one of Msg.Enum FALLBACKREASON; empty for a reply the model wrote.
Property FallbackReason As %String(%JSONFIELDNAME = "fallbackReason", MAXLEN = 32);

/// When the message was created, UTC to the second.
Property CreatedAt As %String(%JSONFIELDNAME = "createdAt", MAXLEN = 20);

/// The turn's trace session id (AD-26).
Property TraceHeaderId As %Integer(%JSONFIELDNAME = "traceHeaderId");

/// The namespace that holds the trace.
Property TraceNamespace As %String(%JSONFIELDNAME = "traceNamespace", MAXLEN = 128);

/// The decision the turn shows (AD-20): the reply decision of a fallback reply, else the triage decision; empty while the turn has none.
Property Decision As OcuTalon.Live.Payload.Decision(%JSONFIELDNAME = "decision");

/// The cost of the whole turn: both decisions' usage. Set only when decision is.
Property TurnCost As OcuTalon.Live.Payload.Part.Cost(%JSONFIELDNAME = "turnCost");

/// The catalog key of the check results of the reply (AD-28); empty for a reply with none.
Property CheckKey As %String(%JSONFIELDNAME = "checkKey", MAXLEN = 128);

/// The check results of the reply, one row each.
Property Checks As list Of OcuTalon.Live.Payload.Part.CheckRow(%JSONFIELDNAME = "checks");

/// The payload for a turn row, with every field set from the row: ref, clientId, channel, fromGuide, state, text, replyText,
/// the fallback's catalogKey and fallbackReason, createdAt, the trace target (the row's TraceHeaderId, in the running
/// namespace; both stay empty while the row has none), the shown decision (Decision.FromRow of the row ShownDecisionRef
/// names, read as the session's own through Ownership) with the turn's cost, and the check key and rows. A read that fails
/// leaves the decision, the cost and the rows empty; it never fails the payload.
ClassMethod FromRow(row As OcuTalon.Data.Turn) As OcuTalon.Live.Payload.ChatMessage
{
	Set payload = ..%New()
	Set payload.Ref = row.Ref
	Set payload.ClientId = row.ClientId
	Set payload.Channel = row.Channel
	Set payload.FromGuide = row.FromGuide
	Set payload.State = row.State
	Set payload.Text = row.Text
	Set payload.ReplyText = row.ReplyText
	Set payload.CatalogKey = row.ReplyCatalogKey
	Set payload.FallbackReason = row.FallbackReason
	Set payload.CreatedAt = row.CreatedAt
	If row.TraceHeaderId '= "" {
		Set payload.TraceHeaderId = row.TraceHeaderId
		Set payload.TraceNamespace = $Namespace
	}
	Do ..SetDecision(payload, row)
	Set payload.CheckKey = row.CheckKey
	Set list = ##class(OcuTalon.Live.Payload.Part.CheckRow).ListFromJSON(row.CheckRows)
	For i = 1:1:list.Count() Do payload.Checks.Insert(list.GetAt(i))
	Quit payload
}

/// Sets the payload's decision and turn cost from the row's shown decision, when the session owns it and the cost can be read.
ClassMethod SetDecision(payload As OcuTalon.Live.Payload.ChatMessage, row As OcuTalon.Data.Turn) [ Private ]
{
	Set ref = row.ShownDecisionRef()
	If (ref = "") || (row.SessionRef = "") Quit
	Try {
		Set decision = ##class(OcuTalon.Data.Ownership).Decision(ref, row.SessionRef, .sc)
		If $SYSTEM.Status.IsError(sc) || '$IsObject(decision) Quit
		Set cost = ##class(OcuTalon.Data.Ownership).TurnCost(row.Ref, .sc)
		If $SYSTEM.Status.IsError(sc) Quit
		Set payload.Decision = ##class(OcuTalon.Live.Payload.Decision).FromRow(decision)
		Set payload.TurnCost = ##class(OcuTalon.Live.Payload.Part.Cost).FromObject(cost)
	} Catch exception {
		Set payload.Decision = ""
		Set payload.TurnCost = ""
	}
}

}
