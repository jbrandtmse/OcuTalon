/// One order as the simulated partner sends it (Story 0.10). The order date is text, so that a date written in the wrong
/// format can arrive and fail in the transform. It holds no name, user name, phone number or SessionRef: the session's tag is
/// the header's SuperSession (AD-4). It shares the Ens.MessageBody extent and sets no DEFAULTGLOBAL (AD-3, AD-5).
Class OcuTalon.Demo.Orders.PartnerOrder Extends Ens.Request
{

/// The partner's order number, PO-0001 and up.
Property OrderNumber As %String(MAXLEN = 20);

/// The order date as the partner writes it: YYYY-MM-DD or MM/DD/YYYY.
Property OrderDate As %String(MAXLEN = 20);

/// The item ordered.
Property Sku As %String(MAXLEN = 20);

/// How many of the item.
Property Quantity As %Integer(MINVAL = 1);

Storage Default
{
<Data name="PartnerOrderDefaultData">
<Subscript>"PartnerOrder"</Subscript>
<Value name="1">
<Value>OrderNumber</Value>
</Value>
<Value name="2">
<Value>OrderDate</Value>
</Value>
<Value name="3">
<Value>Sku</Value>
</Value>
<Value name="4">
<Value>Quantity</Value>
</Value>
</Data>
<DefaultData>PartnerOrderDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
