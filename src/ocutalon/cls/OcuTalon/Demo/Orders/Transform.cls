/// The Orders transform (Story 0.10): a PartnerOrder becomes a WarehouseOrder. The order date is the only field that is checked:
/// OrderDate accepts YYYY-MM-DD and throws the error status below for anything else, which ends the transform with that status
/// as the DTL runtime does for any assignment whose value throws. The error text is the evidence that the diagnosis reads
/// (UX L286, L789): it names the order date and the value that was sent. The event log holds it inside the framework's
/// "Terminating BP" wrapper (see Translator).
Class OcuTalon.Demo.Orders.Transform Extends Ens.DataTransformDTL [ DependsOn = (OcuTalon.Demo.Orders.PartnerOrder, OcuTalon.Demo.Orders.WarehouseOrder) ]
{

Parameter IGNOREMISSINGSOURCE = 1;

Parameter REPORTERRORS = 1;

Parameter TREATEMPTYREPEATINGFIELDASEMPTY = 0;

/// The order date as a $HOROLOG day number when value is a valid date written YYYY-MM-DD; otherwise it throws the status
/// "The order date was not in the expected format. Expected YYYY-MM-DD, got '<value>'." (error 5001).
ClassMethod OrderDate(value As %String) As %Date
{
	If value?4N1"-"2N1"-"2N {
		Set date = $ZDATEH(value, 3, , , , , , , -1)
		If date '= -1 Quit date
	}
	$$$ThrowStatus($$$ERROR($$$GeneralError, "The order date was not in the expected format. Expected YYYY-MM-DD, got '"_value_"'."))
}

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='OcuTalon.Demo.Orders.PartnerOrder' targetClass='OcuTalon.Demo.Orders.WarehouseOrder' create='new' language='objectscript' >
<assign value='source.OrderNumber' property='target.OrderNumber' action='set' />
<assign value='source.Sku' property='target.Sku' action='set' />
<assign value='source.Quantity' property='target.Quantity' action='set' />
<assign value='..OrderDate(source.OrderDate)' property='target.OrderDate' action='set' />
</transform>
}

}
