/// The request to Decide (AD-6, AD-30). It carries rendered text, never an Item message. Lane A.
Class OcuTalon.Bridge.Msg.Request Extends Ens.Request
{

/// One of Msg.Enum REQUESTKIND.
Property Kind As %String(MAXLEN = 32);

/// One of Msg.Enum PROVENANCE.
Property Provenance As %String(MAXLEN = 32);

/// The rendered input text.
Property Input As %String(MAXLEN = "") [ SqlFieldName = InputText ];

/// The item's Ref (AD-14).
Property ItemId As %String(MAXLEN = 22);

/// One code-written line set by the caller, at most 80 characters; never model text (AD-6).
Property Summary As %String(MAXLEN = 80);

/// Allocated by Decide before sending (AD-20).
Property DecisionRef As %String(MAXLEN = 22);

/// The owner: a session's Ref, the literal instance, or the literal eval.
Property OwnerRef As %String(MAXLEN = 22);

/// The session's trace reference: the SuperSession that its messages carry (AD-26).
Property TraceRef As %String(MAXLEN = 22);

/// The channel: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

/// The caller's own trace session id (AD-26).
Property ThreadSessionId As %Integer;

/// continue or fresh (AD-6).
Property SessionMode As %String(MAXLEN = 32);

/// A code-written recap for a fresh session.
Property SeedText As %String(MAXLEN = "");

/// Code-written text sent before the input, never a tool result (AD-30).
Property SystemNote As %String(MAXLEN = "");

Storage Default
{
<Data name="RequestDefaultData">
<Subscript>"Request"</Subscript>
<Value name="1">
<Value>Kind</Value>
</Value>
<Value name="2">
<Value>Provenance</Value>
</Value>
<Value name="3">
<Value>Input</Value>
</Value>
<Value name="4">
<Value>ItemId</Value>
</Value>
<Value name="5">
<Value>Summary</Value>
</Value>
<Value name="6">
<Value>DecisionRef</Value>
</Value>
<Value name="7">
<Value>OwnerRef</Value>
</Value>
<Value name="8">
<Value>TraceRef</Value>
</Value>
<Value name="9">
<Value>Channel</Value>
</Value>
<Value name="10">
<Value>ThreadSessionId</Value>
</Value>
<Value name="11">
<Value>SessionMode</Value>
</Value>
<Value name="12">
<Value>SeedText</Value>
</Value>
<Value name="13">
<Value>SystemNote</Value>
</Value>
</Data>
<DefaultData>RequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
