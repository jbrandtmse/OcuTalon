/// One row per Decide call, except a busy refusal; unique on (ItemId, Kind) (AD-20). Lane A.
Class OcuTalon.Bridge.Data.Decision Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonBP.Decision";

/// The public reference: 22 base64url characters from OcuTalon.Bridge.Ids.NewRef().
Property Ref As %String(MAXLEN = 22);

/// decide, diagnose, turn or tool: one of Msg.Enum REQUESTKIND.
Property Kind As %String(MAXLEN = 32);

/// The item's Ref (AD-14).
Property ItemId As %String(MAXLEN = 22);

/// The owner: a session's Ref, the literal instance, or the literal eval.
Property OwnerRef As %String(MAXLEN = 22);

/// The code-written summary line of the request (AD-6).
Property Summary As %String(MAXLEN = 80);

/// The decision outcome: one of Msg.Enum OUTCOME.
Property Outcome As %String(MAXLEN = 32);

/// The reasons, one per line.
Property Reasons As %String(MAXLEN = "");

/// The model-reported confidence, 0 to 1 with two decimals.
Property Confidence As %Numeric(MAXVAL = 1, MINVAL = 0, SCALE = 2);

/// True when the result took the fallback route (AD-8).
Property Fallback As %Boolean [ InitialExpression = 0 ];

/// The fallback reason: one of Msg.Enum FALLBACKREASON. Empty when Fallback is false.
Property FallbackReason As %String(MAXLEN = 32);

/// The checked decision or diagnosis payload, as JSON.
Property Payload As %String(MAXLEN = "");

/// Input tokens of the turn: prompt, cache-read and cache-write tokens together (AD-20).
Property InputTokens As %Integer;

/// Output tokens of the turn (AD-20).
Property OutputTokens As %Integer;

/// Cache-read input tokens of the turn (AD-20).
Property CacheReadTokens As %Integer;

/// Cache-write input tokens of the turn (AD-20).
Property CacheWriteTokens As %Integer;

/// Number of agent steps in the turn (AD-20).
Property AgentStepCount As %Integer;

/// Duration of the turn in milliseconds (AD-20).
Property DurationMs As %Integer;

/// Cost of the turn in US dollars, priced from Bridge.Data.Price (AD-20).
Property CostUSD As %Numeric(SCALE = 6);

/// The model id that answered; display names live in the catalog (AD-20).
Property Model As %String(MAXLEN = 128);

/// The trace session that holds the decision message; Decide writes it (AD-20, AD-26).
Property TraceSessionId As %Integer;

/// When the row was recorded, UTC to the second.
Property RecordedAt As %String(MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

Index ItemIdKindIndex On (ItemId, Kind) [ Unique ];

Index OwnerRefIndex On OwnerRef;

Storage Default
{
<Data name="DecisionDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>Kind</Value>
</Value>
<Value name="4">
<Value>ItemId</Value>
</Value>
<Value name="5">
<Value>OwnerRef</Value>
</Value>
<Value name="6">
<Value>Summary</Value>
</Value>
<Value name="7">
<Value>Outcome</Value>
</Value>
<Value name="8">
<Value>Reasons</Value>
</Value>
<Value name="9">
<Value>Confidence</Value>
</Value>
<Value name="10">
<Value>Fallback</Value>
</Value>
<Value name="11">
<Value>FallbackReason</Value>
</Value>
<Value name="12">
<Value>Payload</Value>
</Value>
<Value name="13">
<Value>InputTokens</Value>
</Value>
<Value name="14">
<Value>OutputTokens</Value>
</Value>
<Value name="15">
<Value>CacheReadTokens</Value>
</Value>
<Value name="16">
<Value>CacheWriteTokens</Value>
</Value>
<Value name="17">
<Value>AgentStepCount</Value>
</Value>
<Value name="18">
<Value>DurationMs</Value>
</Value>
<Value name="19">
<Value>CostUSD</Value>
</Value>
<Value name="20">
<Value>Model</Value>
</Value>
<Value name="21">
<Value>TraceSessionId</Value>
</Value>
<Value name="22">
<Value>RecordedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonBP.DecisionD</DataLocation>
<DefaultData>DecisionDefaultData</DefaultData>
<IdLocation>^OcuTalonBP.DecisionD</IdLocation>
<IndexLocation>^OcuTalonBP.DecisionI</IndexLocation>
<StreamLocation>^OcuTalonBP.DecisionS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
