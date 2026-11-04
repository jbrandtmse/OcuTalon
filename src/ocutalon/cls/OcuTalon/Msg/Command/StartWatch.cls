/// Starts watching a production; WatchOps reads the IRIS user from the Session row, never from the message (AD-4).
Class OcuTalon.Msg.Command.StartWatch Extends OcuTalon.Msg.Command
{

/// The namespace of the production to watch.
Property Namespace As %String(MAXLEN = 128);

/// The production class to watch.
Property Production As %String(MAXLEN = 128);

/// The name shown to the user.
Property DisplayName As %String(MAXLEN = 128);

Storage Default
{
<Data name="StartWatchDefaultData">
<Subscript>"StartWatch"</Subscript>
<Value name="1">
<Value>Namespace</Value>
</Value>
<Value name="2">
<Value>Production</Value>
</Value>
<Value name="3">
<Value>DisplayName</Value>
</Value>
</Data>
<DefaultData>StartWatchDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
