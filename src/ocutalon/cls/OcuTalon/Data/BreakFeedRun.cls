/// A Break the feed run, owned by Lane B (AD-33).
Class OcuTalon.Data.BreakFeedRun Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.BreakFeed";

/// The owning session's Ref.
Property SessionRef As %String(MAXLEN = 22);

/// sending or sent.
Property State As %String(MAXLEN = 32);

/// When the run started, UTC to the second.
Property StartedAt As %String(MAXLEN = 20);

Index SessionRefIndex On SessionRef;

Storage Default
{
<Data name="BreakFeedRunDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>SessionRef</Value>
</Value>
<Value name="3">
<Value>State</Value>
</Value>
<Value name="4">
<Value>StartedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.BreakFeedD</DataLocation>
<DefaultData>BreakFeedRunDefaultData</DefaultData>
<IdLocation>^OcuTalonP.BreakFeedD</IdLocation>
<IndexLocation>^OcuTalonP.BreakFeedI</IndexLocation>
<StreamLocation>^OcuTalonP.BreakFeedS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
