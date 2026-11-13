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

/// The position of the turn's header in the item list that Visual Trace draws for its session, with the event-log rows shown
/// (AD-26); absent until Conversation has worked it out.
Property TraceItemIndex As %Integer(%JSONFIELDNAME = "traceItemIndex");

/// The same position with the event-log rows hidden.
Property TraceItemIndexNoEvents As %Integer(%JSONFIELDNAME = "traceItemIndexNoEvents");

/// The decision the turn shows (AD-20): the reply decision of a fallback reply, else the triage decision; empty while the turn has none.
Property Decision As OcuTalon.Live.Payload.Decision(%JSONFIELDNAME = "decision");

/// The cost of the whole turn: both decisions' usage. Set only when decision is.
Property TurnCost As OcuTalon.Live.Payload.Part.Cost(%JSONFIELDNAME = "turnCost");

/// The catalog key of the check results of the reply (AD-28); empty for a reply with none.
Property CheckKey As %String(%JSONFIELDNAME = "checkKey", MAXLEN = 128);

/// The check results of the reply, one row each.
Property Checks As list Of OcuTalon.Live.Payload.Part.CheckRow(%JSONFIELDNAME = "checks");

/// The citations of the reply, one per passage a documents tool call returned for the turn; absent for a reply with none.
Property Citations As list Of OcuTalon.Live.Payload.Part.Citation(%JSONFIELDNAME = "citations");

/// The memories the reply recalled, one per memory a memory search returned for the turn; absent for a reply with none.
Property Memories As list Of OcuTalon.Live.Payload.Part.Memory(%JSONFIELDNAME = "memories");

/// The learned saves the reply announces (Story 41.15), one per fact that the turn saved from the person's own words, shaped for the line under the reply (Memory.Learned.Shown); absent for a reply with none, and for a reply that already says "I'll remember".
Property Learned As list Of OcuTalon.Live.Payload.Part.Learned(%JSONFIELDNAME = "learned");

/// The file that the user's message carries (Story 25.3): ref, name, media type and size, never the bytes; absent for a message of text.
Property SentFile As OcuTalon.Live.Payload.Part.SentFile(%JSONFIELDNAME = "sentFile");

/// The payload for a turn row, with every field set from the row: ref, clientId, channel, fromGuide, state, text, replyText,
/// the fallback's catalogKey and fallbackReason, createdAt, the trace target (the row's TraceHeaderId, in the running
/// namespace; both stay empty while the row has none), the position of the trace target in its session's item list (both
/// indexes, set only when the row has them), the file (sentFile, set only when the row has one), the shown decision (Decision.FromRow of the row ShownDecisionRef
/// names, read as the session's own through Ownership) with the turn's cost, the check key and rows, and the citations and
/// memories. A read that fails leaves the decision, the cost and the rows empty; it never fails the payload.
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
	If row.TraceItemIndex '= "" Set payload.TraceItemIndex = row.TraceItemIndex
	If row.TraceItemIndexNoEvents '= "" Set payload.TraceItemIndexNoEvents = row.TraceItemIndexNoEvents
	Set payload.SentFile = ##class(OcuTalon.Live.Payload.Part.SentFile).FromJSON(row.SentFile)
	Do ..SetDecision(payload, row)
	Set payload.CheckKey = row.CheckKey
	Set list = ##class(OcuTalon.Live.Payload.Part.CheckRow).ListFromJSON(row.CheckRows)
	For i = 1:1:list.Count() Do payload.Checks.Insert(list.GetAt(i))
	Set list = ##class(OcuTalon.Live.Payload.Part.Citation).ListFromJSON(row.Citations)
	For i = 1:1:list.Count() Do payload.Citations.Insert(list.GetAt(i))
	Set list = ##class(OcuTalon.Live.Payload.Part.Memory).ListFromJSON(row.Memories)
	For i = 1:1:list.Count() Do payload.Memories.Insert(list.GetAt(i))
	Set list = ##class(OcuTalon.Live.Payload.Part.Learned).ListFromShown(##class(OcuTalon.Memory.Learned).Shown(row.Learned, row.ReplyText))
	For i = 1:1:list.Count() Do payload.Learned.Insert(list.GetAt(i))
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
