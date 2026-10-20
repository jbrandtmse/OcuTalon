/// One order as the warehouse takes it (Story 0.10): the transform's target. The order date is a %Date. The name avoids the
/// SQL reserved word ORDER. It holds no name, user name, phone number or SessionRef, shares the Ens.MessageBody extent and sets
/// no DEFAULTGLOBAL (AD-3, AD-5).
Class OcuTalon.Demo.Orders.WarehouseOrder Extends Ens.Request
{

/// The partner's order number.
Property OrderNumber As %String(MAXLEN = 20);

/// The item ordered.
Property Sku As %String(MAXLEN = 20);

/// The order date, as a $HOROLOG day number.
Property OrderDate As %Date;

/// How many of the item.
Property Quantity As %Integer(MINVAL = 1);

Storage Default
{
<Data name="WarehouseOrderDefaultData">
<Subscript>"WarehouseOrder"</Subscript>
<Value name="1">
<Value>OrderNumber</Value>
</Value>
<Value name="2">
<Value>Sku</Value>
</Value>
<Value name="3">
<Value>OrderDate</Value>
</Value>
<Value name="4">
<Value>Quantity</Value>
</Value>
</Data>
<DefaultData>WarehouseOrderDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
