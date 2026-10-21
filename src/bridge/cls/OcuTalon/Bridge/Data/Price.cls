/// The price of a model, in US dollars per million tokens, with the long-input tier (AD-19, AD-20). Lane A.
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
