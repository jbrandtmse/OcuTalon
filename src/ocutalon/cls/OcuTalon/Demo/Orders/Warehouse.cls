/// The target of the Orders production (Story 0.10): an adapterless operation that accepts each WarehouseOrder and answers OK.
Class OcuTalon.Demo.Orders.Warehouse Extends Ens.BusinessOperation
{

Method OnMessage(request As OcuTalon.Demo.Orders.WarehouseOrder, Output response As Ens.Response) As %Status
{
	Quit $$$OK
}

}
