/// The request that the Digest item sends to itself to build and send one digest (AD-3, AD-18; Story 17.6). It holds the fixed facts of the digest
/// and no text. A Tick queues one for each session that is due (Kind scheduled, DueAt the due time), and a SendDigest queues one (Kind requested, DueAt
/// empty, IdempotencyKey the command's). The window is fixed when the request is queued, so that the count of saved items and the summary of the
/// digest cover the same items: WindowStart is the session's newest digest, or 24 hours before WindowEnd for its first, and WindowEnd is the time of
/// the queueing. The body is kept until the message purge, and the due check and the repeat-key check read it as the marker of a digest that is
/// queued and not yet sent. Lane A.
Class OcuTalon.Digest.Msg.Compose Extends Ens.Request
{

/// The Ref of the session the digest is for.
Property SessionRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// scheduled, or requested.
Property Kind As %String(MAXLEN = 32);

/// The time a scheduled digest was due, UTC to the second; empty for a requested one.
Property DueAt As %String(MAXLEN = 20);

/// The IdempotencyKey of the SendDigest command; empty for a scheduled digest.
Property IdempotencyKey As %String(COLLATION = "EXACT", MAXLEN = 128);

/// The start of the window the digest covers, UTC to the second.
Property WindowStart As %String(MAXLEN = 20);

/// The end of the window the digest covers, UTC to the second: when the request was queued.
Property WindowEnd As %String(MAXLEN = 20);

Index SessionKeyIndex On (SessionRef, IdempotencyKey);

Storage Default
{
<Data name="ComposeDefaultData">
<Subscript>"Compose"</Subscript>
<Value name="1">
<Value>SessionRef</Value>
</Value>
<Value name="2">
<Value>Kind</Value>
</Value>
<Value name="3">
<Value>DueAt</Value>
</Value>
<Value name="4">
<Value>IdempotencyKey</Value>
</Value>
<Value name="5">
<Value>WindowStart</Value>
</Value>
<Value name="6">
<Value>WindowEnd</Value>
</Value>
</Data>
<DefaultData>ComposeDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
