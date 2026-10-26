/// Tests of OcuTalon.Watch.Reader (Story 5.1; AD-3, AD-4). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on, through
/// Test.Watch.Case: they need the running production and the Orders demo production in OCUORDERS, and fail with the reason where they do not have them.
///   - TestOrdersIsListed: Productions lists the Orders production, as {namespace OCUORDERS, production OcuTalon.Demo.Orders.Production, displayName
///     Orders}, once, and Find finds it by the display name in any case, with white space around it (a line break included, as Label treats it), with a
///     trailing " production", by the class name, and with the namespace argument in any case; a name that is not Orders, an empty name and another
///     namespace find nothing;
///   - TestUnreadableNamespaceIsLeftOut: the service user cannot read OCUTALON's data database in a throwaway, and OCUTALON is not listed (a filter that
///     is dropped lists it);
///   - TestReadableNamespaceOffersItsOwnProduction (DW-38): with OCUTALON made readable and its definition table holding OcuTalon.Demo.Orders.Production
///     described Orders, the only match for Orders is in OCUORDERS, and OCUTALON offers only its current production;
///   - TestOnlineDemoListsOnlyOrders: with onlineDemo 1 the list holds only Orders, also with OCUTALON readable;
///   - TestLabel: a description becomes a display name that fits the 128 characters of the command's and the row's DisplayName: white-space runs
///     (line breaks and tabs too) become one space, the ends are trimmed, a long text is cut without a trailing space, and an empty one stays empty;
///   - TestAdmits: Admits is 1 for Orders with its display name, and 0 for the other pairs: the production of OCUTALON, another namespace, an empty
///     namespace and an empty production.
///   - TestFailures (Story 5.2): Failures gives the failed headers of the Orders production from a time on with the measured fields (the header's ids, session,
///     SuperSession, item, sender, body class, time, the id of the log row of the error and its raw text), in time and id order, at most limit, and nothing
///     for a limit of 0;
///   - TestFailureDefinition (Story 5.2): from fixture headers, a header in the error status is a failure whatever its IsError, a response header with only IsError
///     is not one, and the text of a failure is, in turn, the log row of its message, the session's log row at its target, the header's own error status when
///     IsError, and empty;
///   - TestFailuresUnreadable: with no Read on the Orders data database the outcome is unreadable and no row is given (a reader that skips the readability
///     check reads the failures, which the service user must not see);
///   - TestFailuresNotCurrent (DW-38): a production that is not its namespace's own gives not_current and no row: another production in OCUORDERS, and the
///     Orders production asked for in OCUTALON, which is readable;
///   - TestStoppedProduction (DW-222): with the Orders production cleanly stopped, Productions and Find still list it, Failures still reads the failures that it
///     made, and a StartWatch reaches WatchOps' shadow instance and is admitted; the production is started again and the test asserts it runs;
///   - TestMatches (pure): the matcher of Find over any list of entries.
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
	For name = "Orders", "orders", "  ORDERS  ", "Orders"_$Char(13, 10), "Orders"_$Char(9)_" production", "Orders production", "the Orders Production", production, $ZConvert(production, "U") {
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
	For i = 1:1:50 Set long = long_"abc "
	Set label = $ClassMethod(reader, "Label", long)
	Do $$$AssertTrue($Length(label) <= 128, "a long description is cut to 128 characters: "_$Length(label))
	Do $$$AssertEquals($Length(label)_"|"_$Extract(label, *), "127|c", "and a cut that ends on a space leaves no trailing space (the 128th character is a space)")
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

Method TestFailures()
{
	If '..Ready() Quit
	Set a = ..Session("failures")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set from = ##class(OcuTalon.Watch.Mark).Normal(##class(OcuTalon.Data.Time).NowUtc())
	If '..Fail(3, trace) Quit
	Set failed = ..WaitFailed(3)
	Do $$$AssertEquals($ClassMethod(..#READER, "Failures", ..#ORDERS, ..#ORDERSPRODUCTION, from, 10, .rows), "read", "the outcome is read")
	Do $$$AssertEquals(rows.%Size(), 3, "three failures are given")
	Do $$$AssertEquals(..HeaderIdsOf(rows), ..HeaderIds(failed), "the failed headers, in id order")
	Set last = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Do $$$AssertEquals(..SortedKeys(row), "at,bodyClass,errorText,headerId,item,kind,logId,sessionId,source,superSession", "a row has those ten fields")
		Do $$$AssertEquals(row.kind_"|"_row.item_"|"_row.superSession, "header|OrdersFromPartner|"_trace, "a header failure of OrdersFromPartner with the SuperSession of the tag")
		Do $$$AssertTrue((row.sessionId '= "") && (row.source '= "") && (row.bodyClass '= "") && (row.logId '= ""), "with its session, sender, body class and the log row of its error")
		Do $$$AssertTrue(row.at ? 4N1"-"2N1"-"2N1" "2N1":"2N1":"2N1"."3N, "at is IRIS UTC with milliseconds: "_row.at)
		Do $$$AssertTrue('(last ]] row.at), "the rows are in time order")
		Set last = row.at
		Do $$$AssertTrue($Extract(row.errorText, 1, 42) = "ERROR <Ens>ErrBPTerminated: Terminating BP", "the text is the raw log text: "_$Extract(row.errorText, 1, 60))
		Do $$$AssertEquals(##class(OcuTalon.Watch.ErrorText).Sentence(row.errorText), ..#ORDERDATETEXT, "whose sentence is the error's own")
	}
	Do $$$AssertEquals($ClassMethod(..#READER, "Failures", ..#ORDERS, ..#ORDERSPRODUCTION, from, 2, .two), "read", "with a limit")
	Do $$$AssertEquals(..HeaderIdsOf(two), $Piece(..HeaderIds(failed), ",", 1, 2), "the first two are given")
	Do $$$AssertEquals($ClassMethod(..#READER, "Failures", ..#ORDERS, ..#ORDERSPRODUCTION, from, 0, .none), "read", "a limit of 0 still reads")
	Do $$$AssertEquals(none.%Size(), 0, "and gives nothing")
	Set later = ##class(OcuTalon.Watch.Mark).Shift(from, 3600)
	Do $$$AssertEquals($ClassMethod(..#READER, "Failures", ..#ORDERS, ..#ORDERSPRODUCTION, later, 10, .future), "read", "from a time after them")
	Do $$$AssertEquals(future.%Size(), 0, "none is given")
}

Method TestFailureDefinition()
{
	If '..Ready() Quit
	Set from = ##class(OcuTalon.Watch.Mark).Normal(##class(OcuTalon.Data.Time).NowUtc())
	Set byItem = ..FixtureHeader({})
	Set byItemLog = ..FixtureLog(byItem, "", "zzPollerTarget", "zz text of the session's log row at the target")
	Do ..FixtureLog(byItem, "", "zzOtherItem", "zz text of another item")
	Set own = ..FixtureHeader({"IsError": 1, "ErrorStatus": "zz header status text"})
	Set empty = ..FixtureHeader({})
	Set response = ..FixtureHeader({"Type": 2, "Status": 3, "IsError": 1, "ErrorStatus": "zz response status text"})
	Do $$$AssertEquals($ClassMethod(..#READER, "Failures", ..#ORDERS, ..#ORDERSPRODUCTION, from, 50, .rows), "read", "the outcome is read")
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set found(row.headerId) = row
	}
	Do $$$AssertTrue($Data(found(byItem)) && $Data(found(own)) && $Data(found(empty)), "headers in the error status are failures, with IsError 0 or 1")
	Do $$$AssertTrue('$Data(found(response)), "a response header with only IsError is not a failure")
	Do $$$AssertEquals($Select($Data(found(byItem)): found(byItem).errorText_"|"_found(byItem).logId, 1: "missing"), "zz text of the session's log row at the target|"_byItemLog, "no log row names the message: the session's row at its target gives the text")
	Do $$$AssertEquals($Select($Data(found(own)): found(own).errorText, 1: "missing"), $SYSTEM.Status.GetErrorText($SYSTEM.Status.Error(5001, "zz header status text")), "no log row: the header's own error status gives it")
	Do $$$AssertEquals($Select($Data(found(empty)): found(empty).errorText_"|"_found(empty).logId, 1: "missing"), "|", "none of them: empty")
}

Method TestFailuresUnreadable()
{
	If '..Ready() Quit
	Set a = ..Session("unreadable")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set from = ##class(OcuTalon.Watch.Mark).Normal(##class(OcuTalon.Data.Time).NowUtc())
	If '..Fail(1, trace) Quit
	Do ..WaitFailed(1)
	Do $$$AssertEquals($ClassMethod(..#READER, "Failures", ..#ORDERS, ..#ORDERSPRODUCTION, from, 10, .control), "read", "control: the failure is read while the service user can read the Orders data")
	Do $$$AssertEquals(control.%Size(), 1, "and it is given")
	Do ..RevokeRole(..#ORDERSDATA)
	Set here = $Namespace
	Do $$$AssertEquals($ClassMethod(..#READER, "Failures", ..#ORDERS, ..#ORDERSPRODUCTION, from, 10, .rows), "unreadable", "with no Read on "_..#ORDERSDATA_" the outcome is unreadable")
	Do $$$AssertEquals(rows.%Size(), 0, "and no row is given")
	Do $$$AssertEquals($Namespace, here, "the namespace is the one of the caller")
}

Method TestFailuresNotCurrent()
{
	If '..Ready() Quit
	Set from = "2000-01-01 00:00:00.000"
	Do $$$AssertEquals($ClassMethod(..#READER, "Failures", ..#ORDERS, "OcuTalon.Production", from, 10, .rows), "not_current", "another production in OCUORDERS is not its own production")
	Do $$$AssertEquals(rows.%Size(), 0, "and nothing is read")
	Do $$$AssertEquals($ClassMethod(..#READER, "Failures", ..#ORDERS, "", from, 10, .rows), "not_current", "an empty production is not one either")
	Do ..GrantRole(..#HOMEDATA)
	Do $$$AssertEquals($ClassMethod(..#READER, "Failures", "OCUTALON", ..#ORDERSPRODUCTION, from, 10, .rows), "not_current", "the Orders production asked for in the readable OCUTALON is not OCUTALON's own production (DW-38)")
	Do $$$AssertEquals(rows.%Size(), 0, "and nothing is read")
	Do $$$AssertEquals($ClassMethod(..#READER, "Failures", "OCUTALON", "OcuTalon.Production", from, 10, .rows), "read", "control: OCUTALON's own production is read")
}

Method TestStoppedProduction()
{
	If '..Ready() Quit
	Set a = ..Session("stopped")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set from = ##class(OcuTalon.Watch.Mark).Normal(##class(OcuTalon.Data.Time).NowUtc())
	If '..Fail(1, trace) Quit
	Do ..WaitFailed(1)
	If '..StopOrders() Quit
	Do $$$AssertEquals(..OrdersRunning(), 0, "control: the Orders production is stopped")
	Set count = 0
	Set iterator = $ClassMethod(..#READER, "Productions").%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.namespace = ..#ORDERS) && (entry.production = ..#ORDERSPRODUCTION) {
			Set count = count + 1
			Do $$$AssertEquals(entry.displayName, "Orders", "the stopped production is listed as Orders")
		}
	}
	Do $$$AssertEquals(count, 1, "it is listed once")
	Do $$$AssertEquals($ClassMethod(..#READER, "Find", "Orders").%Size(), 1, "Find finds it")
	Do $$$AssertEquals($ClassMethod(..#READER, "Admits", ..#ORDERS, ..#ORDERSPRODUCTION, .name), 1, "and Admits admits it")
	Do $$$AssertEquals($ClassMethod(..#READER, "Failures", ..#ORDERS, ..#ORDERSPRODUCTION, from, 10, .rows), "read", "its failures are still read")
	Do $$$AssertEquals(rows.%Size(), 1, "the one that it made is given")
	Set host = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Watch.Ops", .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of WatchOps is made")
	If $IsObject(host) {
		Set command = ##class(OcuTalon.Msg.Command.StartWatch).%New()
		Set command.SessionRef = a
		Set command.IdempotencyKey = "zzstopped1"
		Set command.Origin = "tool"
		Set command.Namespace = ..#ORDERS
		Set command.Production = ..#ORDERSPRODUCTION
		Do $$$AssertStatusOK(host.OnStart(command, .response), "WatchOps answers the start")
		Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|started", "and admits it")
	}
	Do ..StartOrders()
}

Method TestMatches()
{
	Set entries = [{"namespace": "NSA", "production": "A.Production", "displayName": "Orders"}, {"namespace": "NSB", "production": "B.Orders", "displayName": "Billing"}]
	Do $$$AssertEquals($ClassMethod(..#READER, "Matches", entries, "orders").%Size(), 1, "a name matches the display name in any case")
	Do $$$AssertEquals($ClassMethod(..#READER, "Matches", entries, "orders").%Get(0).namespace, "NSA", "and gives the entry")
	Do $$$AssertEquals($ClassMethod(..#READER, "Matches", entries, "b.orders").%Get(0).namespace, "NSB", "or the class name")
	Do $$$AssertEquals($ClassMethod(..#READER, "Matches", entries, "Billing production").%Size(), 1, "with a trailing production dropped")
	Do $$$AssertEquals($ClassMethod(..#READER, "Matches", entries, "Orders", "nsb").%Size(), 0, "the namespace narrows the match")
	Do $$$AssertEquals($ClassMethod(..#READER, "Matches", entries, "  ").%Size(), 0, "an empty name matches nothing")
	Do $$$AssertEquals($ClassMethod(..#READER, "Matches", [], "Orders").%Size(), 0, "an empty list matches nothing")
}

/// The header ids of the rows of the reader, comma-separated, in order.
ClassMethod HeaderIdsOf(rows As %DynamicArray) As %String [ Private ]
{
	Set ids = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set ids = ids_$Select(ids = "": "", 1: ",")_row.headerId
	}
	Quit ids
}

}
