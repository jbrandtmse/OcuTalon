/// A shipment as the test feed's partner sends it (Story 9.9; AD-22). Every property is text, so that any body saves and reaches its item: the typed
/// record that RECORDCLASS names decides whether the values are valid. It shares the Ens.MessageBody extent and sets no DEFAULTGLOBAL (a message, not a
/// table). The values are synthetic.
Class OcuTalon.Test.Eval.Feed.Shipment Extends (Ens.Request, %JSON.Adaptor)
{

/// The typed record that Intake validates this message as.
Parameter RECORDCLASS = "OcuTalon.Test.Eval.Feed.LedgerEntry";

Property ShipmentId As %String(MAXLEN = 40);

Property OrderNumber As %String(MAXLEN = 40);

/// The time of shipping, written as the carrier writes it.
Property ShippedAt As %String(MAXLEN = 40);

/// The weight in kilograms, written as the carrier writes it.
Property Weight As %String(MAXLEN = 40);

Property Carrier As %String(MAXLEN = 40);

Storage Default
{
<Data name="ShipmentDefaultData">
<Subscript>"Shipment"</Subscript>
<Value name="1">
<Value>ShipmentId</Value>
</Value>
<Value name="2">
<Value>OrderNumber</Value>
</Value>
<Value name="3">
<Value>ShippedAt</Value>
</Value>
<Value name="4">
<Value>Weight</Value>
</Value>
<Value name="5">
<Value>Carrier</Value>
</Value>
</Data>
<DefaultData>ShipmentDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
