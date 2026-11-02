/// The cost of one turn (AD-20): the sums of its decisions' usage, as Ownership.TurnCost gives them. Shared by both lanes,
/// owned by Lane B.
Class OcuTalon.Live.Payload.Part.Cost Extends (%RegisteredObject, %JSON.Adaptor)
{

/// Input tokens: prompt, cache-read and cache-write tokens together.
Property InputTokens As %Integer(%JSONFIELDNAME = "inputTokens");

/// Output tokens.
Property OutputTokens As %Integer(%JSONFIELDNAME = "outputTokens");

/// Cache-read input tokens.
Property CacheReadTokens As %Integer(%JSONFIELDNAME = "cacheReadTokens");

/// Cache-write input tokens.
Property CacheWriteTokens As %Integer(%JSONFIELDNAME = "cacheWriteTokens");

/// Cost in US dollars.
Property CostUSD As %Numeric(%JSONFIELDNAME = "costUSD", SCALE = 6);

/// The part for a TurnCost or RunCost object: every total set from the object, a total it lacks as 0.
ClassMethod FromObject(cost As %DynamicObject) As OcuTalon.Live.Payload.Part.Cost
{
	Set part = ..%New()
	Set part.InputTokens = +cost.inputTokens
	Set part.OutputTokens = +cost.outputTokens
	Set part.CacheReadTokens = +cost.cacheReadTokens
	Set part.CacheWriteTokens = +cost.cacheWriteTokens
	Set part.CostUSD = +cost.costUSD
	Quit part
}

}
