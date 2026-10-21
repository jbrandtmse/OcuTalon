/// The fields every decision and reply message carries: the verdict and the turn totals (AD-6, AD-20, AD-26). Lane A.
Class OcuTalon.Bridge.Msg.Result Extends Ens.Response [ Abstract ]
{

/// The Ref of the Decision row of this decision or reply, whatever its Kind (AD-20).
Property DecisionRef As %String(MAXLEN = 22);

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

Storage Default
{
<Data name="ResultDefaultData">
<Subscript>"Result"</Subscript>
<Value name="1">
<Value>DecisionRef</Value>
</Value>
<Value name="2">
<Value>Outcome</Value>
</Value>
<Value name="3">
<Value>Reasons</Value>
</Value>
<Value name="4">
<Value>Confidence</Value>
</Value>
<Value name="5">
<Value>Fallback</Value>
</Value>
<Value name="6">
<Value>FallbackReason</Value>
</Value>
<Value name="7">
<Value>InputTokens</Value>
</Value>
<Value name="8">
<Value>OutputTokens</Value>
</Value>
<Value name="9">
<Value>CacheReadTokens</Value>
</Value>
<Value name="10">
<Value>CacheWriteTokens</Value>
</Value>
<Value name="11">
<Value>AgentStepCount</Value>
</Value>
<Value name="12">
<Value>DurationMs</Value>
</Value>
<Value name="13">
<Value>CostUSD</Value>
</Value>
<Value name="14">
<Value>Model</Value>
</Value>
</Data>
<DefaultData>ResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
