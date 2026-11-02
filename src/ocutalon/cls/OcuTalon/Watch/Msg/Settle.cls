/// The request that IncidentManager sends itself to start a waiter (AD-15): the waiter of a new incident's settle rule, or, for an incident whose rule has ended
/// (NoticeCount set), the waiter of a later round, which IncidentManager sends in the incident's trace session. The waiter is the BP instance that this request
/// starts: it keeps the incident's own trace session (AD-26) and re-reads the incident's rows on each wake, so nothing of the rule is in memory.
/// Lane A.
Class OcuTalon.Watch.Msg.Settle Extends Ens.Request
{

/// The Ref of the incident that settles.
Property IncidentRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="SettleDefaultData">
<Subscript>"Settle"</Subscript>
<Value name="1">
<Value>IncidentRef</Value>
</Value>
</Data>
<DefaultData>SettleDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
