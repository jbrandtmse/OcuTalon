/// An escalation timer that has fallen due: ReminderTimer sends it to IncidentManager, which pages the backup unless the page was acknowledged (AD-18, Story 24.3). Lane B creates the class (Story 36.2); Lane A handles it.
Class OcuTalon.Msg.Escalation Extends Ens.Request
{

/// The incident that was paged.
Property IncidentRef As %String(MAXLEN = 22);

/// The Ref of the Data.Page row that was not acknowledged in time.
Property PageRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="EscalationDefaultData">
<Subscript>"Escalation"</Subscript>
<Value name="1">
<Value>IncidentRef</Value>
</Value>
<Value name="2">
<Value>PageRef</Value>
</Value>
</Data>
<DefaultData>EscalationDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
