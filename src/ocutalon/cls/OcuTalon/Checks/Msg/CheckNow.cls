/// The request that IncidentManager sends the Checks item after an accepted move that resolves an incident, reopens it after a rejected or expired fix
/// request, or closes a noticed open incident by dismiss or closeQuiet (AD-1, AD-18, AD-33). Checks, the single writer of the run fields, answers it by
/// running each production watch of that namespace and production that the incident's owner covers (AD-4) once, at once, through its normal run; the
/// schedule (NextDueAt) is left as it was. The sender sends it asynchronously, with no answer wanted, in the incident's trace session. Lane A.
Class OcuTalon.Checks.Msg.CheckNow Extends Ens.Request
{

/// The namespace of the incident's production.
Property Namespace As %String(MAXLEN = 128);

/// The incident's production class.
Property Production As %String(MAXLEN = 128);

/// The incident's owner: a session's Ref, or instance or eval.
Property OwnerRef As %String(MAXLEN = 22);

/// The Ref of the incident that caused the request (it names the incident in a log line).
Property IncidentRef As %String(MAXLEN = 22);

Storage Default
{
<Data name="CheckNowDefaultData">
<Subscript>"CheckNow"</Subscript>
<Value name="1">
<Value>Namespace</Value>
</Value>
<Value name="2">
<Value>Production</Value>
</Value>
<Value name="3">
<Value>OwnerRef</Value>
</Value>
<Value name="4">
<Value>IncidentRef</Value>
</Value>
</Data>
<DefaultData>CheckNowDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
