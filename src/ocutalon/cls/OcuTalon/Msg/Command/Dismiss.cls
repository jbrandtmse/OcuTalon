/// Dismisses one of the session's own incidents (AD-15).
Class OcuTalon.Msg.Command.Dismiss Extends OcuTalon.Msg.Command
{

/// The incident to dismiss.
Property IncidentRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="DismissDefaultData">
<Subscript>"Dismiss"</Subscript>
<Value name="1">
<Value>IncidentRef</Value>
</Value>
</Data>
<DefaultData>DismissDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
