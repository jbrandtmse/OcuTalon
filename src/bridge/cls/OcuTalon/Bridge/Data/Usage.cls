/// One row per agent turn, written by the runner right after Chat (AD-20). Lane A.
Class OcuTalon.Bridge.Data.Usage Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonBP.Usage";

/// The Ref of the Decision row whose Decide call this agent turn served (AD-20).
Property DecisionRef As %String(MAXLEN = 22);

/// The item's Ref (AD-14).
Property ItemId As %String(MAXLEN = 22);

/// One of Msg.Enum REQUESTKIND.
Property Kind As %String(MAXLEN = 32);

/// The agent that ran, or compaction for the summarizer (AD-20).
Property Agent As %String(MAXLEN = 32);

/// The channel: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

/// The owner; eval rows count toward no session total (AD-20).
Property OwnerRef As %String(MAXLEN = 22);

/// The model id that answered; display names live in the catalog (AD-20).
Property Model As %String(MAXLEN = 128);

/// Number of model requests in the turn.
Property RequestCount As %Integer;

/// Input tokens of the turn: prompt, cache-read and cache-write tokens together (AD-20).
Property InputTokens As %Integer;

/// Output tokens of the turn (AD-20).
Property OutputTokens As %Integer;

/// Cache-read input tokens of the turn (AD-20).
Property CacheReadTokens As %Integer;

/// Cache-write input tokens of the turn (AD-20).
Property CacheWriteTokens As %Integer;

/// The largest estimated request size of the turn.
Property LargestRequestTokens As %Integer;

/// Cost of the turn in US dollars, priced from Bridge.Data.Price (AD-20).
Property CostUSD As %Numeric(SCALE = 6);

/// True for a compaction row, whose tokens are an estimate (AD-20).
Property Estimated As %Boolean [ InitialExpression = 0 ];

/// When the row was recorded, UTC to the second.
Property RecordedAt As %String(MAXLEN = 20);

Index DecisionRefIndex On DecisionRef;

Index OwnerRefIndex On OwnerRef;

Storage Default
{
<Data name="UsageDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>DecisionRef</Value>
</Value>
<Value name="3">
<Value>ItemId</Value>
</Value>
<Value name="4">
<Value>Kind</Value>
</Value>
<Value name="5">
<Value>Agent</Value>
</Value>
<Value name="6">
<Value>Channel</Value>
</Value>
<Value name="7">
<Value>OwnerRef</Value>
</Value>
<Value name="8">
<Value>Model</Value>
</Value>
<Value name="9">
<Value>RequestCount</Value>
</Value>
<Value name="10">
<Value>InputTokens</Value>
</Value>
<Value name="11">
<Value>OutputTokens</Value>
</Value>
<Value name="12">
<Value>CacheReadTokens</Value>
</Value>
<Value name="13">
<Value>CacheWriteTokens</Value>
</Value>
<Value name="14">
<Value>LargestRequestTokens</Value>
</Value>
<Value name="15">
<Value>CostUSD</Value>
</Value>
<Value name="16">
<Value>Estimated</Value>
</Value>
<Value name="17">
<Value>RecordedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonBP.UsageD</DataLocation>
<DefaultData>UsageDefaultData</DefaultData>
<IdLocation>^OcuTalonBP.UsageD</IdLocation>
<IndexLocation>^OcuTalonBP.UsageI</IndexLocation>
<StreamLocation>^OcuTalonBP.UsageS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
