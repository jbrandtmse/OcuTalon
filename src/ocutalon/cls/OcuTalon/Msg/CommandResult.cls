/// The synchronous answer to every command (AD-1). Lane B.
Class OcuTalon.Msg.CommandResult Extends Ens.Response
{

/// True when the command was carried out.
Property Ok As %Boolean [ InitialExpression = 0 ];

/// A plain-English line for the caller.
Property Message As %String(MAXLEN = 1000);

/// A code for what happened, owned by the verb.
Property Outcome As %String(MAXLEN = 32);

/// The Ref of what the command created or found.
Property Ref As %String(MAXLEN = 22);

/// The due time of a reminder, UTC to the second.
Property DueAt As %String(MAXLEN = 20);

/// The result data of the verb, as JSON.
Property Data As %String(MAXLEN = "");

Storage Default
{
<Data name="CommandResultDefaultData">
<Subscript>"CommandResult"</Subscript>
<Value name="1">
<Value>Ok</Value>
</Value>
<Value name="2">
<Value>Message</Value>
</Value>
<Value name="3">
<Value>Outcome</Value>
</Value>
<Value name="4">
<Value>Ref</Value>
</Value>
<Value name="5">
<Value>DueAt</Value>
</Value>
<Value name="6">
<Value>Data</Value>
</Value>
</Data>
<DefaultData>CommandResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
