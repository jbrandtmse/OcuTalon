/// The review item of the Orders production (Story 23.2): an adapterless operation that accepts each PartnerOrder and answers OK. It takes part only when a failed order is
/// rerouted to it (the fix kind reroute); until then it processes nothing, so the demo's other flows don't pass through it. A request of any other class is an error naming it, as
/// Translator's is, so that an order that reaches it in another form (the transformed WarehouseOrder, when the setting TargetConfigName of OrdersFromPartner names it) fails here.
Class OcuTalon.Demo.Orders.Review Extends Ens.BusinessOperation
{

Method OnMessage(request As OcuTalon.Demo.Orders.PartnerOrder, Output response As Ens.Response) As %Status
{
	If '$IsObject(request) || 'request.%IsA("OcuTalon.Demo.Orders.PartnerOrder") {
		Quit $$$ERROR($$$GeneralError, "Review takes a PartnerOrder, not "_$Select($IsObject(request): $ClassName(request), 1: "'"_$Get(request)_"'"))
	}
	Quit $$$OK
}

}
