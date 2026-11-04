/// Cancels a reminder (AD-29).
Class OcuTalon.Msg.Command.CancelReminder Extends OcuTalon.Msg.Command
{

/// The reminder's Ref.
Property ReminderRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="CancelReminderDefaultData">
<Subscript>"CancelReminder"</Subscript>
<Value name="1">
<Value>ReminderRef</Value>
</Value>
</Data>
<DefaultData>CancelReminderDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
