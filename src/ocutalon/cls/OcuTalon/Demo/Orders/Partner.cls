/// The simulated partner of the Orders production (Story 0.10): an adapterless service that sends a batch of orders to
/// TargetConfigName, each order in its own session. It keeps no state between calls: the date format of a batch is the
/// batch's own. Send is the cross-lane entry; it runs in namespace OCUORDERS, where this package resolves (AD-3). Every
/// message of a batch carries the batch's trace reference as SuperSession (AD-4, AD-26).
Class OcuTalon.Demo.Orders.Partner Extends Ens.BusinessService
{

/// The production item that Send drives.
Parameter ITEM = "PartnerOrdersIn";

/// The date formats a batch may use, as a comma list: the expected one first.
Parameter FORMATS = "YYYY-MM-DD,MM/DD/YYYY";

/// The most orders one batch may hold.
Parameter MAXCOUNT = 1000;

/// The items the partner orders, cycled in this order.
Parameter SKUS = "SKU-1001,SKU-1002,SKU-1003,SKU-1004,SKU-1005";

Parameter SETTINGS = "TargetConfigName:Basic";

/// The item that takes each order.
Property TargetConfigName As Ens.DataType.ConfigName;

/// The orders of a batch as orders(1..n) = a PartnerOrder, and orders = n. Pure: it saves and sends nothing. It validates the
/// batch first and returns an error status naming the value that is wrong, so a bad batch builds no order. Order i has the
/// number PO-<i as four digits>, the batch's date in the batch's format (the partner's local date today when the batch has no
/// order date), the ((i-1)#5+1)th of SKUS and the quantity (i-1)#4+1.
ClassMethod Orders(batch As OcuTalon.Demo.Orders.Batch, Output orders) As %Status
{
	Kill orders
	Set count = batch.Count
	If (count '= +count) || (count '= (count \ 1)) || (count < 1) || (count > ..#MAXCOUNT) {
		Quit $$$ERROR($$$GeneralError, "The batch size must be a whole number from 1 to "_..#MAXCOUNT_", not '"_count_"'.")
	}
	Set format = batch.DateFormat
	If '$ListFind($ListFromString(..#FORMATS), format) {
		Quit $$$ERROR($$$GeneralError, "The date format must be "_$Replace(..#FORMATS, ",", " or ")_", not '"_format_"'.")
	}
	Set date = batch.OrderDate
	If date = "" {
		Set date = $ZDATE($HOROLOG, 3)
	} ElseIf '(date?4N1"-"2N1"-"2N) || ($ZDATEH(date, 3, , , , , , , -1) = -1) {
		Quit $$$ERROR($$$GeneralError, "The order date must be a date written YYYY-MM-DD, not '"_date_"'.")
	}
	Set ref = batch.TraceRef
	If (ref '= "") && '$Match(ref, "^[A-Za-z0-9_-]{22}$") {
		Quit $$$ERROR($$$GeneralError, "The trace reference must be empty or 22 characters of A-Z, a-z, 0-9, - and _, not '"_ref_"'.")
	}
	Set written = $Select(format = "MM/DD/YYYY": $Piece(date, "-", 2)_"/"_$Piece(date, "-", 3)_"/"_$Piece(date, "-", 1), 1: date)
	Set skus = $ListFromString(..#SKUS)
	For i = 1:1:count {
		Set order = ##class(OcuTalon.Demo.Orders.PartnerOrder).%New()
		Set order.OrderNumber = "PO-"_$Translate($Justify(i, 4), " ", "0")
		Set order.OrderDate = written
		Set order.Sku = $List(skus, (i - 1) # $ListLength(skus) + 1)
		Set order.Quantity = (i - 1) # 4 + 1
		Set orders(i) = order
	}
	Set orders = count
	Quit $$$OK
}

/// Sends each order of the batch to TargetConfigName, each in a session of its own, with the batch's trace reference as
/// SuperSession. Sessions are reset inside this method, after the host's start of input has cleared them.
Method OnProcessInput(pInput As OcuTalon.Demo.Orders.Batch, Output pOutput As %RegisteredObject) As %Status
{
	Set sc = ..Orders(pInput, .orders)
	If $$$ISERR(sc) Quit sc
	For i = 1:1:orders {
		Set ..%SessionId = ""
		Set ..%SuperSession = pInput.TraceRef
		Set sc = ..SendRequestAsync(..TargetConfigName, orders(i))
		If $$$ISERR(sc) Quit
	}
	Quit sc
}

/// The cross-lane entry (Story 4.3's PartnerTrigger, Story 7.4): sends count orders (1 to MAXCOUNT) written in dateFormat
/// (YYYY-MM-DD or MM/DD/YYYY), dated orderDate (YYYY-MM-DD; empty is the partner's local date today), every message carrying
/// traceRef (empty, or a 22-character reference) as SuperSession. Call it in namespace OCUORDERS. A batch that fails validation
/// returns the error status and sends nothing.
ClassMethod Send(count As %Integer, dateFormat As %String, traceRef As %String = "", orderDate As %String = "") As %Status
{
	Set batch = ##class(OcuTalon.Demo.Orders.Batch).%New()
	Set batch.Count = count
	Set batch.DateFormat = dateFormat
	Set batch.TraceRef = traceRef
	Set batch.OrderDate = orderDate
	Set sc = ..Orders(batch, .orders)
	If $$$ISERR(sc) Quit sc
	Kill orders
	Set sc = ##class(Ens.Director).CreateBusinessService(..#ITEM, .service)
	If $$$ISERR(sc) Quit sc
	Quit service.ProcessInput(batch)
}

}
