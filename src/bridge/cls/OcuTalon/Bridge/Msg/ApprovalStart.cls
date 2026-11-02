/// The request that starts the hold of one approval request (AD-11): ApprovalStartIn sends it to ApprovalHold. Ref is the request's public
/// Ref. SessionId is the trace session that the hold joins (0 or empty: a new one) and SuperSession the tag of its messages (AD-26). Lane A.
Class OcuTalon.Bridge.Msg.ApprovalStart Extends Ens.Request
{

/// The Ref of the ApprovalRequest row to hold.
Property Ref As %String(MAXLEN = 22);

/// The caller's trace session id; 0 or empty starts a new session.
Property SessionId As %Integer;

/// The SuperSession that the hold's messages carry.
Property SuperSession As %String(MAXLEN = 64);

Storage Default
{
<Data name="ApprovalStartDefaultData">
<Subscript>"ApprovalStart"</Subscript>
<Value name="1">
<Value>Ref</Value>
</Value>
<Value name="2">
<Value>SessionId</Value>
</Value>
<Value name="3">
<Value>SuperSession</Value>
</Value>
</Data>
<DefaultData>ApprovalStartDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
