/// Saves or removes one SQL query watch (AD-18, AD-29; Story 36.2): owner WatchOps (Story 23.8), origin web_admin only. It is not a tool verb.
Class OcuTalon.Msg.Command.SaveSqlWatch Extends OcuTalon.Msg.Command
{

/// save or remove.
Property Action As %String(MAXLEN = 16);

/// The watch's BackgroundCheck Ref; empty for a new watch.
Property CheckRef As %String(MAXLEN = 22);

/// The watch's name.
Property Name As %String(MAXLEN = 128);

/// The query, one SELECT statement.
Property Query As %String(MAXLEN = 4000);

/// Minutes between runs.
Property IntervalMinutes As %Integer;

Storage Default
{
<Data name="SaveSqlWatchDefaultData">
<Subscript>"SaveSqlWatch"</Subscript>
<Value name="1">
<Value>Action</Value>
</Value>
<Value name="2">
<Value>CheckRef</Value>
</Value>
<Value name="3">
<Value>Name</Value>
</Value>
<Value name="4">
<Value>Query</Value>
</Value>
<Value name="5">
<Value>IntervalMinutes</Value>
</Value>
</Data>
<DefaultData>SaveSqlWatchDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
