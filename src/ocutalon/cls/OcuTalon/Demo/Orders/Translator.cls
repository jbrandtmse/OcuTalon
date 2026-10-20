/// The host of the Orders transform (Story 0.10): a business process that runs Transform on each PartnerOrder, returns its error
/// status unchanged, and sends the WarehouseOrder on to TargetConfigName. A failed order therefore ends in header status Error
/// at this item, and the event-log row of this item for its session holds the transform's own error text inside the
/// framework's "Terminating BP" wrapper; the header's IsError and ErrorStatus stay unset, because the partner sends
/// asynchronously and expects no response. A request of any other class is an error naming it.
Class OcuTalon.Demo.Orders.Translator Extends Ens.BusinessProcess
{

Parameter SETTINGS = "TargetConfigName:Basic";

/// The item that takes the transformed order. Transient: a setting of the item, with no storage slot.
Property TargetConfigName As Ens.DataType.ConfigName [ Transient ];

Method OnRequest(request As OcuTalon.Demo.Orders.PartnerOrder, Output response As Ens.Response) As %Status
{
	If '$IsObject(request) || 'request.%IsA("OcuTalon.Demo.Orders.PartnerOrder") {
		Quit $$$ERROR($$$GeneralError, "Translator takes a PartnerOrder, not "_$Select($IsObject(request): $ClassName(request), 1: "'"_$Get(request)_"'"))
	}
	Set sc = ##class(OcuTalon.Demo.Orders.Transform).Transform(request, .order)
	If $$$ISERR(sc) Quit sc
	Quit ..SendRequestAsync(..TargetConfigName, order, 0)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
