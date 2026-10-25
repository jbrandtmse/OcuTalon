/// The payload of the decision live event (AD-12). Each JSON key is the property name with a lower-case first letter. Lane B publishes it.
Class OcuTalon.Live.Payload.Decision Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The decision's Ref.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 22);

/// One of Msg.Enum REQUESTKIND.
Property Kind As %String(%JSONFIELDNAME = "kind", MAXLEN = 32);

/// The item's Ref (AD-14).
Property ItemId As %String(%JSONFIELDNAME = "itemId", MAXLEN = 22);

/// The item's code-written summary line (AD-6).
Property ItemSummary As %String(%JSONFIELDNAME = "itemSummary", MAXLEN = 80);

/// The decision outcome: one of Msg.Enum OUTCOME.
Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 32);

/// The reasons, one per line.
Property Reasons As %String(%JSONFIELDNAME = "reasons", MAXLEN = "");

/// The model-reported confidence, 0 to 1 with two decimals.
Property Confidence As %Numeric(%JSONFIELDNAME = "confidence", MAXVAL = 1, MINVAL = 0, SCALE = 2);

/// True when the result took the fallback route (AD-8).
Property Fallback As %Boolean(%JSONFIELDNAME = "fallback") [ InitialExpression = 0 ];

/// The fallback reason: one of Msg.Enum FALLBACKREASON. Empty when Fallback is false.
Property FallbackReason As %String(%JSONFIELDNAME = "fallbackReason", MAXLEN = 32);

/// Input tokens of the turn: prompt, cache-read and cache-write tokens together (AD-20).
Property InputTokens As %Integer(%JSONFIELDNAME = "inputTokens");

/// Output tokens of the turn (AD-20).
Property OutputTokens As %Integer(%JSONFIELDNAME = "outputTokens");

/// Cache-read input tokens of the turn (AD-20).
Property CacheReadTokens As %Integer(%JSONFIELDNAME = "cacheReadTokens");

/// Cache-write input tokens of the turn (AD-20).
Property CacheWriteTokens As %Integer(%JSONFIELDNAME = "cacheWriteTokens");

/// Number of agent steps in the turn (AD-20).
Property AgentStepCount As %Integer(%JSONFIELDNAME = "agentStepCount");

/// Duration of the turn in milliseconds (AD-20).
Property DurationMs As %Integer(%JSONFIELDNAME = "durationMs");

/// Cost of the turn in US dollars, priced from Bridge.Data.Price (AD-20).
Property CostUSD As %Numeric(%JSONFIELDNAME = "costUSD", SCALE = 6);

/// The model id that answered; display names live in the catalog (AD-20).
Property Model As %String(%JSONFIELDNAME = "model", MAXLEN = 128);

/// When the row was recorded, UTC to the second.
Property RecordedAt As %String(%JSONFIELDNAME = "recordedAt", MAXLEN = 20);

/// Where the decision's trace opens (AD-26): the header of the owner's Turn made from the decision's Item, when the
/// owner is a session that has such a Turn with a header, so that the link lands on the turn; otherwise the decision's
/// TraceSessionId, the session that holds its decision message.
Property TraceHeaderId As %Integer(%JSONFIELDNAME = "traceHeaderId");

/// The namespace that holds the trace.
Property TraceNamespace As %String(%JSONFIELDNAME = "traceNamespace", MAXLEN = 128);

/// The position of the turn's header in the item list that Visual Trace draws for its session, with the event-log rows
/// shown (AD-26); absent unless the trace opens at the owner's Turn and the Turn has it.
Property TraceItemIndex As %Integer(%JSONFIELDNAME = "traceItemIndex");

/// The same position with the event-log rows hidden.
Property TraceItemIndexNoEvents As %Integer(%JSONFIELDNAME = "traceItemIndexNoEvents");

/// The payload for a decision row, with every row-backed field set: itemSummary is the row's Summary and model the
/// display name of the row's model id. The trace target is the row's TraceSessionId in the current namespace, unless
/// the row's OwnerRef is a session that has a Turn made from the row's Item (Ownership.TurnOfItem) and that Turn has a
/// TraceHeaderId: then the target is the Turn's header and its two item indexes, so that the link opens the day's thread
/// on the turn's page (DW-129). A missing Turn, a Turn without a header, a failed read and an owner that is not a
/// session keep the TraceSessionId target.
ClassMethod FromRow(row As OcuTalon.Bridge.Data.Decision) As OcuTalon.Live.Payload.Decision
{
	Set payload = ..%New()
	Set payload.Ref = row.Ref
	Set payload.Kind = row.Kind
	Set payload.ItemId = row.ItemId
	Set payload.ItemSummary = row.Summary
	Set payload.Outcome = row.Outcome
	Set payload.Reasons = row.Reasons
	Set payload.Confidence = row.Confidence
	Set payload.Fallback = row.Fallback
	Set payload.FallbackReason = row.FallbackReason
	Set payload.InputTokens = row.InputTokens
	Set payload.OutputTokens = row.OutputTokens
	Set payload.CacheReadTokens = row.CacheReadTokens
	Set payload.CacheWriteTokens = row.CacheWriteTokens
	Set payload.AgentStepCount = row.AgentStepCount
	Set payload.DurationMs = row.DurationMs
	Set payload.CostUSD = row.CostUSD
	Set payload.Model = ..ModelName(row.Model)
	Set payload.RecordedAt = row.RecordedAt
	Set payload.TraceHeaderId = row.TraceSessionId
	Set payload.TraceNamespace = $Namespace
	Set turn = ##class(OcuTalon.Data.Ownership).TurnOfItem(row.ItemId, row.OwnerRef, .sc)
	If $SYSTEM.Status.IsOK(sc), $IsObject(turn), turn.TraceHeaderId '= "" {
		Set payload.TraceHeaderId = turn.TraceHeaderId
		If turn.TraceItemIndex '= "" Set payload.TraceItemIndex = turn.TraceItemIndex
		If turn.TraceItemIndexNoEvents '= "" Set payload.TraceItemIndexNoEvents = turn.TraceItemIndexNoEvents
	}
	Quit payload
}

/// The display name of a model id: "Claude Haiku 5.5" for claude-haiku-5-5 and "Claude Sonnet 5.5" for
/// claude-sonnet-5-5. Any other id is returned as it is, and "" stays "". This is the one display-name table.
ClassMethod ModelName(id As %String) As %String
{
	Quit $Case(id, "claude-haiku-5-5": "Claude Haiku 5.5", "claude-sonnet-5-5": "Claude Sonnet 5.5", : id)
}

}
