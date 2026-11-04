/// An item's decision as it travels from Intake to OutcomeRouter, DigestStore or EvalSink (AD-14, AD-30). Lane B.
Class OcuTalon.Msg.ItemDecision Extends Ens.Request
{

/// The item's Ref (AD-14).
Property ItemId As %String(MAXLEN = 22);

/// Copied from the Item: the evaluation case id, empty otherwise.
Property SourceItemId As %String(MAXLEN = 128);

/// The owner: a session's Ref, the literal instance, or the literal eval.
Property OwnerRef As %String(MAXLEN = 22);

/// The channel: one of Msg.Enum CHANNEL.
Property Channel As %String(MAXLEN = 32);

/// One code-written line set by the caller, at most 80 characters; never model text (AD-6).
Property Summary As %String(MAXLEN = 80);

/// The Ref of the Decision row that holds the attention decision (AD-20).
Property DecisionRef As %String(MAXLEN = 22);

/// The decision outcome: one of Msg.Enum OUTCOME.
Property Outcome As %String(MAXLEN = 32);

/// True when the result took the fallback route (AD-8).
Property Fallback As %Boolean [ InitialExpression = 0 ];

/// The fallback reason: one of Msg.Enum FALLBACKREASON. Empty when Fallback is false.
Property FallbackReason As %String(MAXLEN = 32);

/// Optional: copied from the Item by Intake (AD-30).
Property CatalogKey As %String(MAXLEN = 128);

/// Optional: copied from the Item by Intake (AD-30).
Property Slots As %String(MAXLEN = "");

Storage Default
{
<Data name="ItemDecisionDefaultData">
<Subscript>"ItemDecision"</Subscript>
<Value name="1">
<Value>ItemId</Value>
</Value>
<Value name="2">
<Value>SourceItemId</Value>
</Value>
<Value name="3">
<Value>OwnerRef</Value>
</Value>
<Value name="4">
<Value>Channel</Value>
</Value>
<Value name="5">
<Value>Summary</Value>
</Value>
<Value name="6">
<Value>DecisionRef</Value>
</Value>
<Value name="7">
<Value>Outcome</Value>
</Value>
<Value name="8">
<Value>Fallback</Value>
</Value>
<Value name="9">
<Value>FallbackReason</Value>
</Value>
<Value name="10">
<Value>CatalogKey</Value>
</Value>
<Value name="11">
<Value>Slots</Value>
</Value>
</Data>
<DefaultData>ItemDecisionDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
