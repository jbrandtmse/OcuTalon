/// The price of a model, in US dollars per million tokens, with the long-input tier (AD-19, AD-20). Lane A.
/// Cost prices the usage of one agent turn from a row, and CostFor looks the row up by the exact model id.
Class OcuTalon.Bridge.Data.Price Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonBP.Price";

/// The model id; unique.
Property Model As %String(MAXLEN = 128);

/// Input tokens.
Property InputPerMTok As %Numeric(SCALE = 4);

/// Output tokens.
Property OutputPerMTok As %Numeric(SCALE = 4);

/// Cache-read input tokens.
Property CacheReadPerMTok As %Numeric(SCALE = 4);

/// Cache-write input tokens.
Property CacheWritePerMTok As %Numeric(SCALE = 4);

/// The input size above which the long tier applies.
Property LongThresholdTokens As %Integer;

/// Input tokens above the threshold.
Property LongInputPerMTok As %Numeric(SCALE = 4);

/// Output tokens above the threshold.
Property LongOutputPerMTok As %Numeric(SCALE = 4);

Index ModelIndex On Model [ Unique ];

/// The cost in US dollars of the usage of one agent turn at this row's rates, rounded to 6 decimals (AD-20):
/// (prompt x InputPerMTok + cacheRead x CacheReadPerMTok + cacheWrite x CacheWritePerMTok + completion x OutputPerMTok) / 1,000,000.
/// When LongThresholdTokens is set and the largest request of the turn is above it, the whole turn is priced at the long tier:
/// input at LongInputPerMTok, output at LongOutputPerMTok, and each cache rate scaled by LongInputPerMTok / InputPerMTok. The largest
/// request is largest, or, when largest is empty, the input of the turn (prompt, cache-read and cache-write tokens) divided by
/// requestCount (at least 1). A token count or rate that is empty counts as 0.
Method Cost(prompt As %Integer, cacheRead As %Integer, cacheWrite As %Integer, completion As %Integer, largest As %Integer = "", requestCount As %Integer = 1) As %Numeric
{
	Set prompt = +prompt, cacheRead = +cacheRead, cacheWrite = +cacheWrite, completion = +completion
	Set input = ..InputPerMTok, readRate = ..CacheReadPerMTok, writeRate = ..CacheWritePerMTok, outputRate = ..OutputPerMTok
	If largest = "" Set largest = (prompt + cacheRead + cacheWrite) / $Select(+requestCount < 1: 1, 1: +requestCount)
	If (+..LongThresholdTokens > 0) && (largest > ..LongThresholdTokens) {
		Set scale = $Select(+..InputPerMTok = 0: 1, 1: ..LongInputPerMTok / ..InputPerMTok)
		Set input = ..LongInputPerMTok
		Set readRate = readRate * scale
		Set writeRate = writeRate * scale
		Set outputRate = ..LongOutputPerMTok
	}
	Quit $Number((prompt * input + (cacheRead * readRate) + (cacheWrite * writeRate) + (completion * outputRate)) / 1000000, 6)
}

/// The cost of the usage of one agent turn for the model (Cost at the row whose Model is exactly model), or "" when no row has the
/// model: an unknown cost is never 0.
ClassMethod CostFor(model As %String, prompt As %Integer, cacheRead As %Integer, cacheWrite As %Integer, completion As %Integer, largest As %Integer = "", requestCount As %Integer = 1) As %Numeric
{
	If model = "" Quit ""
	Set price = ..ModelIndexOpen(model)
	If '$IsObject(price) || (price.Model '= model) Quit ""
	Quit price.Cost(prompt, cacheRead, cacheWrite, completion, largest, requestCount)
}

Storage Default
{
<Data name="PriceDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Model</Value>
</Value>
<Value name="3">
<Value>InputPerMTok</Value>
</Value>
<Value name="4">
<Value>OutputPerMTok</Value>
</Value>
<Value name="5">
<Value>CacheReadPerMTok</Value>
</Value>
<Value name="6">
<Value>CacheWritePerMTok</Value>
</Value>
<Value name="7">
<Value>LongThresholdTokens</Value>
</Value>
<Value name="8">
<Value>LongInputPerMTok</Value>
</Value>
<Value name="9">
<Value>LongOutputPerMTok</Value>
</Value>
</Data>
<DataLocation>^OcuTalonBP.PriceD</DataLocation>
<DefaultData>PriceDefaultData</DefaultData>
<IdLocation>^OcuTalonBP.PriceD</IdLocation>
<IndexLocation>^OcuTalonBP.PriceI</IndexLocation>
<StreamLocation>^OcuTalonBP.PriceS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
