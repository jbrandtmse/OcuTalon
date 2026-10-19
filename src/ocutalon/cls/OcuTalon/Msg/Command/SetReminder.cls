/// Sets a reminder (AD-18, AD-29). Lane B handles it in ReminderOps.
Class OcuTalon.Msg.Command.SetReminder Extends OcuTalon.Msg.Command
{

/// What to remind the user of.
Property Text As %String(MAXLEN = 1000);

/// Exactly one due form is set. The due time in UTC.
Property DueAt As %String(MAXLEN = 20);

/// Exactly one due form is set. The delay from now in seconds, for relative phrasing.
Property DelaySeconds As %Integer;

/// Exactly one due form is set. A local date and time without a zone, which ReminderOps converts in the instance zone (AD-18, AD-29).
Property LocalDueAt As %String(MAXLEN = 19);

Storage Default
{
<Data name="SetReminderDefaultData">
<Subscript>"SetReminder"</Subscript>
<Value name="1">
<Value>Text</Value>
</Value>
<Value name="2">
<Value>DueAt</Value>
</Value>
<Value name="3">
<Value>DelaySeconds</Value>
</Value>
<Value name="4">
<Value>LocalDueAt</Value>
</Value>
</Data>
<DefaultData>SetReminderDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
