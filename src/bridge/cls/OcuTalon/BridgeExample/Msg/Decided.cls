/// An item's decision as it travels from ExampleTriage to ExampleRouter (FR-5, AD-30). The rule of the router reads Fallback and
/// Outcome. The example's counterpart of OcuTalon.Msg.ItemDecision, which the example never references (AD-2).
Class OcuTalon.BridgeExample.Msg.Decided Extends Ens.Request
{

/// The item's Ref (AD-14).
Property ItemId As %String(MAXLEN = 22);

/// One code-written line, at most 80 characters; never model text (AD-6).
Property Summary As %String(MAXLEN = 80);

/// The Ref of the Decision row that holds the decision (AD-20).
Property DecisionRef As %String(MAXLEN = 22);

/// The decision outcome: one of OcuTalon.Bridge.Msg.Enum OUTCOME.
Property Outcome As %String(MAXLEN = 32);

/// True when the decision took the fallback route (AD-8).
Property Fallback As %Boolean [ InitialExpression = 0 ];

/// The fallback reason: one of OcuTalon.Bridge.Msg.Enum FALLBACKREASON. Empty when Fallback is false.
Property FallbackReason As %String(MAXLEN = 32);

Storage Default
{
<Data name="DecidedDefaultData">
<Subscript>"Decided"</Subscript>
<Value name="1">
<Value>ItemId</Value>
</Value>
<Value name="2">
<Value>Summary</Value>
</Value>
<Value name="3">
<Value>DecisionRef</Value>
</Value>
<Value name="4">
<Value>Outcome</Value>
</Value>
<Value name="5">
<Value>Fallback</Value>
</Value>
<Value name="6">
<Value>FallbackReason</Value>
</Value>
</Data>
<DefaultData>DecidedDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
