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

/// The decision's TraceSessionId: the session that holds its decision message (AD-26).
Property TraceHeaderId As %Integer(%JSONFIELDNAME = "traceHeaderId");

/// The namespace that holds the trace.
Property TraceNamespace As %String(%JSONFIELDNAME = "traceNamespace", MAXLEN = 128);

}
