/// The review item of the Orders production (Story 23.2): an adapterless operation that accepts each PartnerOrder and answers OK. It takes part only when a failed order is
/// rerouted to it (the fix kind reroute); until then it processes nothing, so the demo's other flows don't pass through it.
Class OcuTalon.Demo.Orders.Review Extends Ens.BusinessOperation
{

Method OnMessage(request As OcuTalon.Demo.Orders.PartnerOrder, Output response As Ens.Response) As %Status
{
	Quit $$$OK
}

}
