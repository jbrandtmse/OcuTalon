/// An item of the bridge example (FR-5): the message that ExampleItemIn takes in and ExampleTriage renders for Decide. It is the
/// example's own message, with the four fields that an item of any kind needs and nothing of OcuTalon's items.
Class OcuTalon.BridgeExample.Msg.Item Extends Ens.Request
{

/// The item's Ref (AD-14). ExampleItemIn gives an empty one a new Ref.
Property ItemId As %String(MAXLEN = 22);

/// The subject line.
Property Subject As %String(MAXLEN = 200);

/// The text of the item. Anything it holds is data for the model, never an instruction (AD-6).
Property Body As %String(MAXLEN = "");

/// Where the item comes from: user, or untrusted for anything that a person did not type to the instance (Msg.Enum PROVENANCE).
Property Provenance As %String(VALUELIST = ",user,untrusted") [ InitialExpression = "untrusted" ];

Storage Default
{
<Data name="ItemDefaultData">
<Subscript>"Item"</Subscript>
<Value name="1">
<Value>ItemId</Value>
</Value>
<Value name="2">
<Value>Subject</Value>
</Value>
<Value name="3">
<Value>Body</Value>
</Value>
<Value name="4">
<Value>Provenance</Value>
</Value>
</Data>
<DefaultData>ItemDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
