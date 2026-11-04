/// The outcome of an approval request (AD-11): ApprovalHold sends it to the row's ResultTarget (IncidentManager for a fix) when the request
/// was approved (a fix only), rejected or expired. ApprovalRef is the request's public Ref and IncidentRef the incident it belongs to, when
/// there is one; the receiver reads everything else from the row. A cancelled request sends none (AD-15). Lane A.
Class OcuTalon.Bridge.Msg.ApprovalOutcome Extends Ens.Request
{

/// The Ref of the ApprovalRequest row.
Property ApprovalRef As %String(MAXLEN = 22);

/// The row's IncidentRef; empty when the request has no incident.
Property IncidentRef As %String(MAXLEN = 22);

/// One of approved, rejected or expired.
Property Outcome As %String(MAXLEN = 32);

Storage Default
{
<Data name="ApprovalOutcomeDefaultData">
<Subscript>"ApprovalOutcome"</Subscript>
<Value name="1">
<Value>ApprovalRef</Value>
</Value>
<Value name="2">
<Value>IncidentRef</Value>
</Value>
<Value name="3">
<Value>Outcome</Value>
</Value>
</Data>
<DefaultData>ApprovalOutcomeDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
