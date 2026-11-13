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

/// "" or reminder is a reminder; escalation is an escalation timer (AD-18, Story 24.3). Until then ReminderOps answers any other value not_built.
Property Kind As %String(MAXLEN = 32);

/// For an escalation: the incident that was paged.
Property IncidentRef As %String(MAXLEN = 22);

/// For an escalation: the Ref of the page that was sent.
Property PageRef As %String(MAXLEN = 22);

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
<Value name="5">
<Value>Kind</Value>
</Value>
<Value name="6">
<Value>IncidentRef</Value>
</Value>
<Value name="7">
<Value>PageRef</Value>
</Value>
</Data>
<DefaultData>SetReminderDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
