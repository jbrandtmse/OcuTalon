/// The request that WatchOps sends the Checks item after it starts or stops a watch (AD-1, AD-18, AD-33). Checks, the single publisher of the
/// check event, answers it by publishing the change on the session's stream: for a start the new row's payload, for a stop a payload of the
/// fields below with stopped true, because the row is already gone. The sender sends it asynchronously, with no answer wanted. Lane A.
Class OcuTalon.Checks.Msg.CheckChanged Extends Ens.Request
{

/// The Ref of the check (the row's Ref).
Property CheckRef As %String(MAXLEN = 22);

/// The Ref of the session that owns the check, whose stream the event goes on.
Property SessionRef As %String(MAXLEN = 22);

/// True when the watch was stopped (its row is gone), false when it was started.
Property Stopped As %Boolean [ InitialExpression = 0 ];

/// The kind of the check.
Property Kind As %String(MAXLEN = 32);

/// The namespace of the watched production.
Property Namespace As %String(MAXLEN = 128);

/// The watched production class.
Property Production As %String(MAXLEN = 128);

/// The name shown to the user.
Property DisplayName As %String(MAXLEN = 128);

Storage Default
{
<Data name="CheckChangedDefaultData">
<Subscript>"CheckChanged"</Subscript>
<Value name="1">
<Value>CheckRef</Value>
</Value>
<Value name="2">
<Value>SessionRef</Value>
</Value>
<Value name="3">
<Value>Stopped</Value>
</Value>
<Value name="4">
<Value>Kind</Value>
</Value>
<Value name="5">
<Value>Namespace</Value>
</Value>
<Value name="6">
<Value>Production</Value>
</Value>
<Value name="7">
<Value>DisplayName</Value>
</Value>
</Data>
<DefaultData>CheckChangedDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
