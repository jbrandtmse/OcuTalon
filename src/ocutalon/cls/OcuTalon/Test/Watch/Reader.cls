/// Tests of OcuTalon.Watch.Reader (Story 5.1; AD-3, AD-4). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on, through
/// Test.Watch.Case: they need the running production and the Orders demo production in OCUORDERS, and fail with the reason where they do not have them.
///   - TestOrdersIsListed: Productions lists the Orders production, as {namespace OCUORDERS, production OcuTalon.Demo.Orders.Production, displayName
///     Orders}, once, and Find finds it by the display name in any case, with white space around it, with a trailing " production", by the class name, and
///     with the namespace argument in any case; a name that is not Orders, an empty name and another namespace find nothing;
///   - TestUnreadableNamespaceIsLeftOut: the service user cannot read OCUTALON's data database in a throwaway, and OCUTALON is not listed (a filter that
///     is dropped lists it);
///   - TestReadableNamespaceOffersItsOwnProduction (DW-38): with OCUTALON made readable and its definition table holding OcuTalon.Demo.Orders.Production
///     described Orders, the only match for Orders is in OCUORDERS, and OCUTALON offers only its current production;
///   - TestOnlineDemoListsOnlyOrders: with onlineDemo 1 the list holds only Orders, also with OCUTALON readable;
///   - TestLabel: a description becomes a display name that fits the 128 characters of the command's and the row's DisplayName: white-space runs
///     (line breaks and tabs too) become one space, the ends are trimmed, a long text is cut without a trailing space, and an empty one stays empty;
///   - TestAdmits: Admits is 1 for Orders with its display name, and 0 for the other pairs: the production of OCUTALON, another namespace, an empty
///     namespace and an empty production.
/// Every change to the instance is put back by Test.Watch.Case, also after a failure.
Class OcuTalon.Test.Watch.Reader Extends OcuTalon.Test.Watch.Case
{

Parameter READER = "OcuTalon.Watch.Reader";

Method TestOrdersIsListed()
{
	If '..Ready() Quit
	Set orders = ##class(OcuTalon.Install.Step.Demo).#NAMESPACE
	Set production = ##class(OcuTalon.Install.Step.Demo).#PRODUCTION
	Set entries = $ClassMethod(..#READER, "Productions")
	Set count = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.namespace = orders {
			Set count = count + 1
			Do $$$AssertEquals(entry.production_"|"_entry.displayName, production_"|Orders", "the entry of "_orders_" is the Orders production, named Orders")
			Do $$$AssertEquals(..SortedKeys(entry), "displayName,namespace,production", "and has those three fields")
		}
	}
	Do $$$AssertEquals(count, 1, orders_" is listed once")
	For name = "Orders", "orders", "  ORDERS  ", "Orders production", "the Orders Production", production, $ZConvert(production, "U") {
		Set found = $ClassMethod(..#READER, "Find", name)
		Do $$$AssertEquals(found.%Size(), $Select(name [ "the ": 0, 1: 1), "Find('"_name_"') finds "_$Select(name [ "the ": "nothing (the leading word is not dropped)", 1: "the Orders production"))
		If found.%Size() = 1 Do $$$AssertEquals(found.%Get(0).namespace_"|"_found.%Get(0).production, orders_"|"_production, "and it is the one of "_orders)
	}
	Do $$$AssertEquals($ClassMethod(..#READER, "Find", "Orders", "ocuorders").%Size(), 1, "the namespace argument is compared in any case")
	Do $$$AssertEquals($ClassMethod(..#READER, "Find", "Orders", "OCUTALON").%Size(), 0, "and another namespace finds nothing")
	For name = "Billing", "", "   ", " production", "Order" {
		Do $$$AssertEquals($ClassMethod(..#READER, "Find", name).%Size(), 0, "Find('"_name_"') finds nothing")
	}
}

Method TestUnreadableNamespaceIsLeftOut()
{
	If '..Ready() Quit
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser", , , .sc)
	Do $$$AssertStatusOK(sc, "the service user is read from Decide's setting")
	Set home = ..#HOMEDATA
	Do $$$AssertEquals(''$SYSTEM.Security.CheckUserPermission(user, home, "R"), 0, "control: the service user cannot read "_home_" in a throwaway")
	Set entries = $ClassMethod(..#READER, "Productions")
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Do $$$AssertNotEquals(entry.namespace, "OCUTALON", "OCUTALON is not listed: the service user cannot read its data database")
	}
	Do $$$AssertEquals($ClassMethod(..#READER, "Admits", "OCUTALON", "OcuTalon.Production"), 0, "and OcuTalon.Production is not admitted")
}

Method TestReadableNamespaceOffersItsOwnProduction()
{
	If '..Ready() Quit
	Set orders = ##class(OcuTalon.Install.Step.Demo).#NAMESPACE
	Set ordersProduction = ##class(OcuTalon.Install.Step.Demo).#PRODUCTION
	Set description = ..Defined("OCUTALON", ordersProduction)
	Do $$$AssertEquals(description, "Orders", "control: OCUTALON holds a definition of "_ordersProduction_" described Orders")
	Do ..GrantRole(..#HOMEDATA)
	Set entries = $ClassMethod(..#READER, "Productions")
	Set homeProduction = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.namespace = "OCUTALON" Set homeProduction = homeProduction _ $ListBuild(entry.production)
	}
	Do $$$AssertEquals($ListToString(homeProduction), "OcuTalon.Production", "OCUTALON, now readable, offers only its current production")
	Set found = $ClassMethod(..#READER, "Find", "Orders")
	Do $$$AssertEquals(found.%Size(), 1, "the only match for Orders is one production")
	If found.%Size() = 1 Do $$$AssertEquals(found.%Get(0).namespace, orders, "and it is in "_orders_", not in OCUTALON")
	Do $$$AssertEquals($ClassMethod(..#READER, "Admits", "OCUTALON", ordersProduction), 0, "OCUTALON's definition of the Orders production is not admitted")
	Do $$$AssertEquals($ClassMethod(..#READER, "Admits", "OCUTALON", "OcuTalon.Production"), 1, "while its own production is")
}

Method TestOnlineDemoListsOnlyOrders()
{
	If '..Ready() Quit
	Do ..GrantRole(..#HOMEDATA)
	Set before = $ClassMethod(..#READER, "Productions")
	Do $$$AssertTrue(before.%Size() > 1, "control: with OCUTALON readable the list holds more than one production: "_before.%ToJSON())
	Do $$$AssertEquals($ClassMethod(..#READER, "OnlineDemo"), 0, "control: this is not the online demo")
	Do ..SetOnlineDemo(1)
	Do $$$AssertEquals($ClassMethod(..#READER, "OnlineDemo"), 1, "onlineDemo 1 is the online demo")
	Set entries = $ClassMethod(..#READER, "Productions")
	Do $$$AssertEquals(entries.%Size(), 1, "the list holds one production")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).namespace_"|"_entries.%Get(0).production_"|"_entries.%Get(0).displayName, ##class(OcuTalon.Install.Step.Demo).#NAMESPACE_"|"_##class(OcuTalon.Install.Step.Demo).#PRODUCTION_"|Orders", "the Orders production")
	Do $$$AssertEquals($ClassMethod(..#READER, "Find", "Orders").%Size(), 1, "Orders is found")
	Do $$$AssertEquals($ClassMethod(..#READER, "Admits", "OCUTALON", "OcuTalon.Production"), 0, "and OcuTalon.Production is not admitted")
}

Method TestLabel()
{
	Set reader = ..#READER
	Do $$$AssertEquals($ClassMethod(reader, "Label", "Orders"), "Orders", "a plain description is kept")
	Do $$$AssertEquals($ClassMethod(reader, "Label", "  Orders"_$Char(13, 10)_"  production"_$Char(9)_" x "), "Orders production x", "white-space runs become one space and the ends are trimmed")
	Set long = ""
	For i = 1:1:100 Set long = long_"ab "
	Set label = $ClassMethod(reader, "Label", long)
	Do $$$AssertTrue($Length(label) <= 128, "a long description is cut to 128 characters: "_$Length(label))
	Do $$$AssertEquals($Extract(label, *), "b", "and the cut leaves no trailing space")
	Do $$$AssertEquals($ClassMethod(reader, "Label", ""), "", "an empty description stays empty")
}

Method TestAdmits()
{
	If '..Ready() Quit
	Set orders = ##class(OcuTalon.Install.Step.Demo).#NAMESPACE
	Set production = ##class(OcuTalon.Install.Step.Demo).#PRODUCTION
	Do $$$AssertEquals($ClassMethod(..#READER, "Admits", orders, production, .name), 1, "Orders is admitted")
	Do $$$AssertEquals(name, "Orders", "with its display name")
	For pair = $ListBuild(orders, "OcuTalon.Production"), $ListBuild("OCUTALON", production), $ListBuild("", production), $ListBuild(orders, ""), $ListBuild("ZZNS", production), $ListBuild(orders, "Orders") {
		Set admitted = $ClassMethod(..#READER, "Admits", $List(pair, 1), $List(pair, 2), .name)
		Do $$$AssertEquals(admitted_"|"_name, "0|", "('"_$List(pair, 1)_"', '"_$List(pair, 2)_"') is not admitted")
	}
}

}
