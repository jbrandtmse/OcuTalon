/// Tests of the Orders production's classes (Story 0.10) that need no OCUORDERS and no running production, so they run on a
/// slot and in the lane-b shard:
///   - TestMessageContracts: PartnerOrder and WarehouseOrder have exactly their contracts and share the Ens.MessageBody extent;
///   - TestTransformAcceptsTheExpectedFormat and TestTransformFailsOnTheChangedFormat: the DTL's Transform, called in
///     OCUTALON with no production, converts a YYYY-MM-DD order date and fails with the error text for anything else;
///   - TestBatch: Partner.Orders builds the orders of a batch of 1 to 1000, in the batch's format, and refuses a bad batch with an error
///     that names the value, building nothing;
///   - TestProductionDefinition: the compiled definition of OcuTalon.Demo.Orders.Production holds exactly the three items,
///     read through %XML.Reader as an Ens.Config.Production.
/// It starts and stops nothing, writes no row and creates no namespace.
Class OcuTalon.Test.Demo.Orders Extends OcuTalon.Test.Contract
{

/// The partner class.
Parameter PARTNER = "OcuTalon.Demo.Orders.Partner";

/// The production class.
Parameter PRODUCTION = "OcuTalon.Demo.Orders.Production";

/// Both message classes have exactly their contract and use the Ens.MessageBody extent with no DEFAULTGLOBAL.
Method TestMessageContracts()
{
	Do ..AssertContract("Contracts")
	Do ..AssertMessageExtent("Contracts")
}

/// A date written YYYY-MM-DD becomes the $HOROLOG day of that date, and the other fields are copied.
Method TestTransformAcceptsTheExpectedFormat()
{
	Set order = ..NewOrder("2026-10-16")
	Set sc = ##class(OcuTalon.Demo.Orders.Transform).Transform(order, .target)
	Do $$$AssertStatusOK(sc, "the transform accepts 2026-10-16")
	Do $$$AssertEquals($IsObject($Get(target)) && target.%IsA("OcuTalon.Demo.Orders.WarehouseOrder"), 1, "the target is a WarehouseOrder")
	If '$IsObject($Get(target)) Quit
	Do $$$AssertEquals(target.OrderDate, $ZDATEH("2026-10-16", 3), "the order date is the day number of 2026-10-16")
	Do $$$AssertEquals(target.OrderNumber, "PO-0007", "the order number is copied")
	Do $$$AssertEquals(target.Sku, "SKU-1002", "the Sku is copied")
	Do $$$AssertEquals(target.Quantity, 3, "the quantity is copied")
	Do $$$AssertEquals(##class(OcuTalon.Demo.Orders.Transform).OrderDate("2026-02-28"), $ZDATEH("2026-02-28", 3), "OrderDate converts a valid date")
}

/// Any other value ends the transform with error 5001 and the text of the evidence, naming the value it got.
Method TestTransformFailsOnTheChangedFormat()
{
	Set values = $ListBuild("10/16/2026", "", "2026-02-30", "2026-1-6", "16.10.2026")
	Set position = 0
	While $ListNext(values, position, value) {
		Kill target
		Set sc = ##class(OcuTalon.Demo.Orders.Transform).Transform(..NewOrder(value), .target)
		Do $$$AssertStatusNotOK(sc, "the transform fails on '"_value_"'")
		Do $$$AssertEquals($SYSTEM.Status.GetErrorText(sc), "ERROR #5001: The order date was not in the expected format. Expected YYYY-MM-DD, got '"_value_"'.", "the error names '"_value_"'")
	}
}

/// Rows 12 and 17 of the matrix: the orders of a good batch, and the errors of a bad one.
Method TestBatch()
{
	Set batch = ..NewBatch(3, "MM/DD/YYYY", "2026-10-16", "")
	Do $$$AssertStatusOK(##class(OcuTalon.Demo.Orders.Partner).Orders(batch, .orders), "a good batch is accepted")
	Do $$$AssertEquals($Get(orders), 3, "the batch holds 3 orders")
	Set skus = $ListFromString($Parameter(..#PARTNER, "SKUS"))
	For i = 1:1:+$Get(orders) {
		Do $$$AssertEquals(orders(i).OrderNumber, "PO-000"_i, "order "_i_" is numbered PO-000"_i)
		Do $$$AssertEquals(orders(i).OrderDate, "10/16/2026", "order "_i_" is dated 10/16/2026")
		Do $$$AssertEquals(orders(i).Sku, $List(skus, i), "order "_i_" takes SKU "_i)
		Do $$$AssertEquals(orders(i).Quantity, i, "order "_i_" has quantity "_i)
	}

	Set batch = ..NewBatch(6, "YYYY-MM-DD", "2026-10-16", "")
	Do $$$AssertStatusOK(##class(OcuTalon.Demo.Orders.Partner).Orders(batch, .orders), "a batch of 6 is accepted")
	Do $$$AssertEquals(orders(6).OrderDate, "2026-10-16", "the expected format keeps the date as it is")
	Do $$$AssertEquals(orders(6).Sku, $List(skus, 1), "the sixth order starts the Sku cycle again")
	Do $$$AssertEquals(orders(6).Quantity, 2, "the sixth order has quantity 2")

	Set batch = ..NewBatch(1000, "YYYY-MM-DD", "2026-10-16", "")
	Do $$$AssertStatusOK(##class(OcuTalon.Demo.Orders.Partner).Orders(batch, .orders), "a batch of 1000, the most, is accepted")
	Do $$$AssertEquals($Get(orders), 1000, "the batch of 1000 holds 1000 orders")

	Set before = $ZDATE($HOROLOG, 3)
	Set batch = ..NewBatch(1, "YYYY-MM-DD", "", "")
	Do $$$AssertStatusOK(##class(OcuTalon.Demo.Orders.Partner).Orders(batch, .orders), "a batch with no order date is accepted")
	Set after = $ZDATE($HOROLOG, 3)
	Do $$$AssertTrue((orders(1).OrderDate = before) || (orders(1).OrderDate = after), "an empty order date is the partner's local date today")

	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set batch = ..NewBatch(2, "YYYY-MM-DD", "2026-10-16", ref)
	Do $$$AssertStatusOK(##class(OcuTalon.Demo.Orders.Partner).Orders(batch, .orders), "a batch with a 22-character reference is accepted")

	Set bad(1) = ..NewBatch(0, "YYYY-MM-DD", "", "")
	Set bad(2) = ..NewBatch(1001, "YYYY-MM-DD", "", "")
	Set bad(3) = ..NewBatch("x", "YYYY-MM-DD", "", "")
	Set bad(4) = ..NewBatch(1.5, "YYYY-MM-DD", "", "")
	Set bad(5) = ..NewBatch(1, "DD.MM.YYYY", "", "")
	Set bad(6) = ..NewBatch(1, "YYYY-MM-DD", "10/16/2026", "")
	Set bad(7) = ..NewBatch(1, "YYYY-MM-DD", "2026-02-30", "")
	Set bad(8) = ..NewBatch(1, "YYYY-MM-DD", "", "abc")
	Set accented = $Translate($Justify("", 22), " ", $Char(233))
	Set bad(9) = ..NewBatch(1, "YYYY-MM-DD", "", accented)
	Set expected = $ListBuild(
		"The batch size must be a whole number from 1 to 1000, not '0'.",
		"The batch size must be a whole number from 1 to 1000, not '1001'.",
		"The batch size must be a whole number from 1 to 1000, not 'x'.",
		"The batch size must be a whole number from 1 to 1000, not '1.5'.",
		"The date format must be YYYY-MM-DD or MM/DD/YYYY, not 'DD.MM.YYYY'.",
		"The order date must be a date written YYYY-MM-DD, not '10/16/2026'.",
		"The order date must be a date written YYYY-MM-DD, not '2026-02-30'.",
		"The trace reference must be empty or 22 characters of A-Z, a-z, 0-9, - and _, not 'abc'.",
		"The trace reference must be empty or 22 characters of A-Z, a-z, 0-9, - and _, not '"_accented_"'.")
	For i = 1:1:$ListLength(expected) {
		Kill orders
		Set sc = ##class(OcuTalon.Demo.Orders.Partner).Orders(bad(i), .orders)
		Do $$$AssertEquals($SYSTEM.Status.GetErrorText(sc), "ERROR #5001: "_$List(expected, i), "bad batch "_i_" is refused naming its value")
		Do $$$AssertEquals($Data(orders), 0, "bad batch "_i_" builds no order")
	}
}

/// The compiled XData of the production holds exactly its three items, read as an Ens.Config.Production.
Method TestProductionDefinition()
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(..#PRODUCTION_"||ProductionDefinition")
	Do $$$AssertTrue($IsObject(xdata), "the production has a compiled ProductionDefinition")
	If '$IsObject(xdata) Quit
	Set reader = ##class(%XML.Reader).%New()
	Do $$$AssertStatusOK(reader.OpenStream(xdata.Data), "the definition opens as XML")
	Do reader.Correlate("Production", "Ens.Config.Production")
	Set found = reader.Next(.production, .sc)
	Do $$$AssertTrue(found, "the definition reads as a production")
	If 'found Quit
	Do $$$AssertEquals(production.Name, ..#PRODUCTION, "the production is named for its class")
	Do $$$AssertEquals(production.TestingEnabled, 0, "testing is disabled")
	Do $$$AssertEquals(production.Description, "Orders", "the description is Orders")
	Set expected = $ListBuild(
		"PartnerOrdersIn|OcuTalon.Demo.Orders.Partner|0|1|Host:TargetConfigName=OrdersFromPartner",
		"OrdersFromPartner|OcuTalon.Demo.Orders.Translator|1|1|Host:TargetConfigName=OrdersToWarehouse",
		"OrdersToWarehouse|OcuTalon.Demo.Orders.Warehouse|1|1|")
	Do $$$AssertEquals(production.Items.Count(), $ListLength(expected), "the production has exactly three items")
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		Set settings = ""
		For j = 1:1:item.Settings.Count() {
			Set setting = item.Settings.GetAt(j)
			Set settings = settings _ $Select(settings = "": "", 1: ";") _ setting.Target _ ":" _ setting.Name _ "=" _ setting.Value
		}
		Set line = item.Name_"|"_item.ClassName_"|"_item.PoolSize_"|"_item.Enabled_"|"_settings
		Do $$$AssertEquals(line, $ListGet(expected, i), "item "_i_" is "_$ListGet(expected, i))
		Do $$$AssertEquals($Extract(item.ClassName, 1, 21), "OcuTalon.Demo.Orders.", "item "_i_" is a class of OcuTalon.Demo.Orders")
	}
}

/// A PartnerOrder with the given date: number PO-0007, Sku SKU-1002, quantity 3.
ClassMethod NewOrder(date As %String) As OcuTalon.Demo.Orders.PartnerOrder [ Private ]
{
	Set order = ##class(OcuTalon.Demo.Orders.PartnerOrder).%New()
	Set order.OrderNumber = "PO-0007"
	Set order.OrderDate = date
	Set order.Sku = "SKU-1002"
	Set order.Quantity = 3
	Quit order
}

/// A batch with the given fields.
ClassMethod NewBatch(count, dateFormat, orderDate, traceRef) As OcuTalon.Demo.Orders.Batch [ Private ]
{
	Set batch = ##class(OcuTalon.Demo.Orders.Batch).%New()
	Set batch.Count = count
	Set batch.DateFormat = dateFormat
	Set batch.OrderDate = orderDate
	Set batch.TraceRef = traceRef
	Quit batch
}

/// The contracts of the two message classes.
XData Contracts [ MimeType = application/json ]
{
{
 "OcuTalon.Demo.Orders.PartnerOrder": {
  "super": "Ens.Request",
  "props": {
   "OrderNumber": "%String(MAXLEN=20)",
   "OrderDate": "%String(MAXLEN=20)",
   "Sku": "%String(MAXLEN=20)",
   "Quantity": "%Integer(MINVAL=1)"
  }
 },
 "OcuTalon.Demo.Orders.WarehouseOrder": {
  "super": "Ens.Request",
  "props": {
   "OrderNumber": "%String(MAXLEN=20)",
   "Sku": "%String(MAXLEN=20)",
   "OrderDate": "%Date",
   "Quantity": "%Integer(MINVAL=1)"
  }
 }
}
}

}
