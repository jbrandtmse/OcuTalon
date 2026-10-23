/// The request to Decide (AD-6, AD-30). It carries rendered text, never an Item message. Lane A.
Class OcuTalon.Bridge.Msg.Request Extends Ens.Request
{

/// The values of SessionMode that Decide admits, comma-separated. An empty SessionMode means continue, and any other value is refused.
Parameter SESSIONMODES = "continue,fresh";

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

/// continue or fresh (AD-6), or empty for continue (SESSIONMODES). Only a turn with provenance user has a conversation to continue. The
/// runner opens the linked AI session for a continue turn, and moves the link to a new AI session for a fresh turn, after that turn is
/// answered and saved.
Property SessionMode As %String(MAXLEN = 32);

/// A code-written recap for a fresh session. The runner sends it only on a fresh turn of a conversation, as the start of the turn's one
/// user message: the seed, a blank line, the SystemNote, a blank line and the Input (Adapter.Agent ChatInput). A continue turn ignores it.
Property SeedText As %String(MAXLEN = "");

/// Code-written text sent before the input, never a tool result (AD-30). The runner sends it in the turn's one user message, after the
/// SeedText and before the Input, on every request that carries it.
Property SystemNote As %String(MAXLEN = "");

/// 1 when Decide flags the turn for compaction (AD-6, AD-20): the request is a turn whose estimated first model request is above
/// Decide's COMPACTTOKENS. Decide sets it on every request it sends to a runner, the first send and every re-send, and a value the
/// caller sets is replaced. The runner ignores it until Story 30.1 reads it, so a flagged turn is sent as it is.
Property Compact As %Boolean [ InitialExpression = 0 ];

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
<Value name="14">
<Value>Compact</Value>
</Value>
</Data>
<DefaultData>RequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
