/// The start of one reminder's waiter (AD-5, AD-18): ReminderOps sends it to ReminderTimer, which answers once it has stored its
/// start header on the reminder's row and set its timer. It names the row by its Ref only. Internal to the Schedule area.
Class OcuTalon.Schedule.ReminderStart Extends Ens.Request
{

/// The Ref of the Reminder row that the waiter waits for.
Property Ref As %String(MAXLEN = 22);

Storage Default
{
<Data name="ReminderStartDefaultData">
<Subscript>"ReminderStart"</Subscript>
<Value name="1">
<Value>Ref</Value>
</Value>
</Data>
<DefaultData>ReminderStartDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
