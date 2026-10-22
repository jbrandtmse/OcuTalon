/// One row per agent turn, written by the runner right after Chat (AD-20). Lane A. The class methods serve the runner (Delta, HasSpend, FromStats) and Decide (Totals):
///   - Delta: the change of one counter of AI Hub's session stats between two readings;
///   - HasSpend: whether the turn spent a request or a token, so that a Chat that threw still gets its row;
///   - Largest: the largest request of a turn, the larger of the last request's measured input and the estimates of the other requests;
///   - FromStats: the unsaved row of one Chat, from the request, the two stats readings, the last response's usage and the estimates;
///   - Totals: the sums over the rows of one decision, which Decide puts on its Decision row and its answer.
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

/// The change of the counter between two GetStats() readings (after minus before, at least 0). A reading that is not an object, and a
/// counter that a reading does not hold, count as 0.
ClassMethod Delta(before As %DynamicObject, after As %DynamicObject, key As %String) As %Integer
{
	Set was = $Select($IsObject(before): +before.%Get(key), 1: 0)
	Set now = $Select($IsObject(after): +after.%Get(key), 1: 0)
	Quit $Select(now > was: now - was, 1: 0)
}

/// 1 when the readings differ by a model request or by a token (a prompt, completion, cache-read or cache-write token), otherwise 0.
ClassMethod HasSpend(before As %DynamicObject, after As %DynamicObject) As %Boolean
{
	Set spent = 0
	For key = "total_interactions", "total_prompt_tokens", "total_completion_tokens", "total_cache_read_tokens", "total_cache_creation_tokens" {
		If ..Delta(before, after, key) > 0 Set spent = 1
	}
	Quit spent
}

/// The largest request of a turn in tokens (AD-20, AD-9): the larger of two values, or "" when there is neither.
///   - The measured input of the last request, from last (the Usage of the last response: prompt_tokens, cache_read_tokens and
///     cache_creation_tokens), when last is an object.
///   - The estimates of the other requests, from estimates (a list of the estimated tokens of the model requests, in order; see
///     OcuTalon.Bridge.Adapter.StepBuffer.Estimates). When a measurement exists, the last estimate is the last request's own and is
///     dropped; when nothing was measured, as after a Chat that threw, all of them count.
ClassMethod Largest(last As %DynamicObject, estimates As %List = "") As %Integer
{
	Set largest = $Select($IsObject(last): +last.%Get("prompt_tokens") + last.%Get("cache_read_tokens") + last.%Get("cache_creation_tokens"), 1: "")
	Set count = $ListLength(estimates) - $Select($IsObject(last): 1, 1: 0)
	For i = 1:1:count {
		Set estimate = +$List(estimates, i)
		If (largest = "") || (estimate > largest) Set largest = estimate
	}
	Quit largest
}

/// Builds the unsaved row of one Chat call (AD-20) in row and returns OK, or returns an error when after is not a stats reading.
///   - DecisionRef, ItemId, Kind, OwnerRef and Channel come from the request; agent and model are given;
///   - RequestCount is the delta of total_interactions, OutputTokens the delta of total_completion_tokens, and CacheReadTokens and
///     CacheWriteTokens the deltas of total_cache_read_tokens and total_cache_creation_tokens;
///   - InputTokens adds the delta of total_prompt_tokens to those two, because AI Hub's prompt tokens exclude the cached input;
///   - LargestRequestTokens is Largest(last, estimates): the larger of the input of the last request, from last (the Usage of the
///     response: prompt_tokens, cache_read_tokens and cache_creation_tokens), and the estimates of the other requests (all of them
///     when last is not an object, as after a Chat that threw), or empty when there is neither;
///   - CostUSD is Price.CostFor of the model, empty when no Price row has it; Estimated is 0; RecordedAt is the current UTC time.
ClassMethod FromStats(request As OcuTalon.Bridge.Msg.Request, agent As %String, model As %String, before As %DynamicObject, after As %DynamicObject, last As %DynamicObject, Output row As OcuTalon.Bridge.Data.Usage, estimates As %List = "") As %Status
{
	Set row = ""
	If '$IsObject(after) Quit $$$ERROR($$$GeneralError, "No stats reading after the call, so no usage row can be built")
	Set prompt = ..Delta(before, after, "total_prompt_tokens")
	Set cacheRead = ..Delta(before, after, "total_cache_read_tokens")
	Set cacheWrite = ..Delta(before, after, "total_cache_creation_tokens")
	Set output = ..Delta(before, after, "total_completion_tokens")
	Set requests = ..Delta(before, after, "total_interactions")
	Set largest = ..Largest(last, estimates)
	Set row = ..%New()
	Set row.DecisionRef = request.DecisionRef
	Set row.ItemId = request.ItemId
	Set row.Kind = request.Kind
	Set row.OwnerRef = request.OwnerRef
	Set row.Channel = request.Channel
	Set row.Agent = agent
	Set row.Model = model
	Set row.RequestCount = requests
	Set row.InputTokens = prompt + cacheRead + cacheWrite
	Set row.OutputTokens = output
	Set row.CacheReadTokens = cacheRead
	Set row.CacheWriteTokens = cacheWrite
	Set row.LargestRequestTokens = largest
	Set row.CostUSD = ##class(OcuTalon.Bridge.Data.Price).CostFor(model, prompt, cacheRead, cacheWrite, output, largest, requests)
	Set row.Estimated = 0
	Set row.RecordedAt = ##class(OcuTalon.Bridge.Time).NowUtc()
	Quit $$$OK
}

/// The totals of the rows of a decision as {"inputTokens","outputTokens","cacheReadTokens","cacheWriteTokens","costUSD","model","rows"}
/// (AD-20): the sums of the token counts and of the cost, the model of the newest row, and the number of rows. The values are empty
/// ("") for an empty ref and for a ref with no row, except rows, which is 0; and costUSD is empty when any row has no cost, because an
/// unknown cost is never 0.
ClassMethod Totals(decisionRef As %String) As %DynamicObject
{
	Set totals = {"inputTokens": "", "outputTokens": "", "cacheReadTokens": "", "cacheWriteTokens": "", "costUSD": "", "model": "", "rows": 0}
	If decisionRef = "" Quit totals
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT InputTokens, OutputTokens, CacheReadTokens, CacheWriteTokens, CostUSD, Model FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ? ORDER BY ID", decisionRef)
	If result.%SQLCODE < 0 Quit totals
	Set rows = 0, input = 0, output = 0, cacheRead = 0, cacheWrite = 0, cost = 0, unknown = 0, model = ""
	While result.%Next() {
		Set rows = rows + 1
		Set input = input + result.%GetData(1)
		Set output = output + result.%GetData(2)
		Set cacheRead = cacheRead + result.%GetData(3)
		Set cacheWrite = cacheWrite + result.%GetData(4)
		If result.%GetData(5) = "" {
			Set unknown = 1
		} Else {
			Set cost = cost + result.%GetData(5)
		}
		Set model = result.%GetData(6)
	}
	If 'rows Quit totals
	Do totals.%Set("inputTokens", input, "number")
	Do totals.%Set("outputTokens", output, "number")
	Do totals.%Set("cacheReadTokens", cacheRead, "number")
	Do totals.%Set("cacheWriteTokens", cacheWrite, "number")
	If 'unknown Do totals.%Set("costUSD", $Number(cost, 6), "number")
	Do totals.%Set("model", model)
	Do totals.%Set("rows", rows, "number")
	Quit totals
}

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
