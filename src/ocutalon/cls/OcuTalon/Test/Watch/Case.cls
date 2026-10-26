/// The base of the Story 5.1 test classes that run over the running production (Test.Watch.Reader, Grant, Ops, Tools and Turns). THEY RUN IN THROWAWAY
/// STACKS AND IN CI ONLY (Rule 21), with demo mode on: they need the running OcuTalon.Production and the Orders demo production in OCUORDERS, and fail
/// with the reason where they do not have them (Reason), so that a broken start can never give a green shard. It extends Test.Core.InProduction (Guard,
/// the fixture sessions, the clean-up of the run's messages) and adds what the watch tests share:
///   - Reason: "" when OCUORDERS exists, demo mode is on and the Orders production is current there;
///   - the changes that a test makes to the instance, each put back by OnAfterOneTest, also after a failure: SetOnlineDemo (the public flag), GrantRole
///     and RevokeRole (a resource of the service role), and Described (a production's description in a namespace's definition table);
///   - UseDouble and RestoreDouble (Test.Tools.CommandsDouble behind the CommandsIn item), Begin (a bridge context for a turn), Calls (what the double
///     recorded), Rows and Row (the BackgroundCheck rows of a session) and Watch (a fixture session's watch of Orders);
///   - OnAfterOneTest and OnAfterAllTests delete the BackgroundCheck rows of the run's sessions, so a row that a test made through WatchOps is gone too;
///   - for the tests of the failure reading (Story 5.2): Fail (failing orders in OCUORDERS through the partner), WaitFailed, LateHeader and LateError (a
///     header that enters the error status later), HeaderlessLog (an event-log row with no session), Since and Batches (the FailureBatch messages that
///     IncidentManager holds, as plain objects), WaitBatched and Ids, StopPoller and StartPoller (the item's temporary stop), StopOrders, StartOrders and
///     OrdersRunning, and ClearMark. Every message and row that they make in OCUORDERS (the headers after the first Fail, the fixture headers and log
///     rows) and every batch that the poller sent is removed by OnAfterOneTest and OnAfterAllTests, and the poller and Orders are started again if a test
///     stopped them.
/// It has no Test methods.
Class OcuTalon.Test.Watch.Case Extends OcuTalon.Test.Core.InProduction [ Abstract, DependsOn = (OcuTalon.Install.Step.Demo, OcuTalon.Install.Step.Users) ]
{

Parameter SESSIONPREFIX = "zzwatch";

/// The test double of CommandsIn and the item that it sits behind.
Parameter DOUBLE = "OcuTalon.Test.Tools.CommandsDouble";

Parameter ITEM = "CommandsIn";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter ROLE = {##class(OcuTalon.Install.Step.Users).#SERVICEROLE};

/// The namespace and the production of the Orders demo, from the Demo step's own parameters.
Parameter ORDERS = {##class(OcuTalon.Install.Step.Demo).#NAMESPACE};

Parameter ORDERSPRODUCTION = {##class(OcuTalon.Install.Step.Demo).#PRODUCTION};

/// The data database resource of OCUORDERS and of OCUTALON.
Parameter ORDERSDATA = {"%DB_"_##class(OcuTalon.Install.Step.Demo).#DATADB};

Parameter ORDERSCODE = {"%DB_"_##class(OcuTalon.Install.Step.Demo).#CODEDB};

Parameter HOMEDATA = "%DB_OCUTALON_DATA";

/// The sentence of a failing order of Fail, as ErrorText.Sentence gives it.
Parameter ORDERDATETEXT = "The order date was not in the expected format. Expected YYYY-MM-DD, got '10/16/2026'.";

/// The item that picks up failures, and the item that receives its batches.
Parameter POLLER = "FailurePoller";

Parameter MANAGER = "IncidentManager";

/// The longest a test waits for a batch, in seconds (a test bound, not NFR-7), and the pause that proves no further batch comes: two polls.
Parameter WAITBATCH = 30;

Parameter QUIET = 7;

/// What the CommandsIn item had before the double was put behind it, as JSON text, or "" while the double is not behind it.
Property Swap As %String(MAXLEN = "");

/// The resources of the service role before a test changed them, or "" with RoleSaved 0 when it did not.
Property RoleBefore As %String(MAXLEN = "");

Property RoleSaved As %Boolean [ InitialExpression = 0 ];

/// The value of the public flag onlineDemo before a test set it, with OnlineSaved 1 while it is changed.
Property OnlineBefore As %String;

Property OnlineSaved As %Boolean [ InitialExpression = 0 ];

/// The definitions that a test made or changed: JSON text of [{"namespace","production","existed","description"}, ...], or "".
Property Definitions As %String(MAXLEN = "");

/// The ItemIds of the turns that a test made, for the clean-up of their steps.
Property ItemIds As %List;

/// The entries of the runners point at the mock's key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The SessionMark of the saved AI sessions when a test began.
Property SessionMark As %Integer;

/// The newest header id and log id of OCUORDERS before the first failing order of a test, "" before it.
Property OrdersFloor As %Integer;

Property OrdersLogFloor As %Integer;

/// The newest header id of OCUTALON before the test first asked for it (Since), "" before it.
Property HomeFloor As %Integer;

/// The ids of the fixture headers and log rows that a test made in OCUORDERS.
Property FixtureHeaders As %List;

Property FixtureLogs As %List;

/// 1 while the test has the FailurePoller item temporarily stopped, and while it has stopped the Orders production.
Property PollerStopped As %Boolean [ InitialExpression = 0 ];

Property OrdersStopped As %Boolean [ InitialExpression = 0 ];

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble")
	Set ..OrdersFloor = ""
	Set ..OrdersLogFloor = ""
	Set ..HomeFloor = ""
	Set ..FixtureHeaders = ""
	Set ..FixtureLogs = ""
	If ##class(OcuTalon.Test.Agent.RunnerFixture).Running() Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble")
	Set sc = ..PutBack()
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).DeleteSteps(itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	If ##class(OcuTalon.Test.Agent.RunnerFixture).Running() && (..SessionMark '= "") Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	Do ..DropRows()
	Do ..DropMessages()
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Set sc = ..PutBack()
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..Unswap())
	If ..Pointed && ##class(OcuTalon.Test.Agent.RunnerFixture).Running() {
		Set ..Pointed = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys())
	}
	Do ..DropRows()
	Do ..DropMessages()
	Quit $SYSTEM.Status.AppendStatus(sc, ##super())
}

/// "" when the test may run: OCUORDERS exists, demo mode is on and the Orders production is the current production of OCUORDERS. Otherwise the reason.
ClassMethod Reason() As %String
{
	Set orders = ##class(OcuTalon.Install.Step.Demo).#NAMESPACE
	If '##class(%SYS.Namespace).Exists(orders) Quit "Namespace "_orders_" does not exist: these tests run in a throwaway with demo mode on"
	If ##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Install.Step.Demo).#MODEKEY) '= 1 Quit "Demo mode is off: these tests run in a throwaway with demo mode on"
	Set entries = ##class(OcuTalon.Watch.Reader).Productions()
	Set found = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.namespace = orders) && (entry.production = ##class(OcuTalon.Install.Step.Demo).#PRODUCTION) Set found = 1
	}
	If 'found Quit "The Orders production is not listed by Watch.Reader: "_entries.%ToJSON()
	Quit ""
}

/// 1 when the test may run (Guard and Reason). Otherwise it fails with the reason, and the test quits.
Method Ready() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	Set reason = ..Reason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Quit 1
}

/// Sets the public flag onlineDemo for the test; OnAfterOneTest puts it back.
Method SetOnlineDemo(value As %String) [ Private ]
{
	If '..OnlineSaved {
		Set ..OnlineBefore = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
		Set ..OnlineSaved = 1
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", value), "onlineDemo is set to '"_value_"'")
}

/// The resources of the service role, as the role has them ("resource:permission,..."), read in %SYS.
ClassMethod RoleResources() As %String
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Kill props
	Set sc = ##class(Security.Roles).Get(..#ROLE, .props)
	Quit $Select($$$ISOK(sc): $Get(props("Resources")), 1: "<no role>")
}

/// Writes the resources of the service role, in %SYS.
ClassMethod WriteRole(resources As %String) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Kill props
	Set props("Resources") = resources
	Quit ##class(Security.Roles).Modify(..#ROLE, .props)
}

/// Gives the service role Read on the resource (it keeps its other entries); OnAfterOneTest puts the role back as it was.
Method GrantRole(resource As %String) [ Private ]
{
	Set current = ..RoleResources()
	If '..RoleSaved {
		Set ..RoleBefore = current
		Set ..RoleSaved = 1
	}
	Set kept = ..Without(current, resource)
	Do $$$AssertStatusOK(..WriteRole(kept_$Select(kept = "": "", 1: ",")_resource_":R"), "the service role is given Read on "_resource)
}

/// Takes the resource from the service role (it keeps its other entries); OnAfterOneTest puts the role back as it was.
Method RevokeRole(resource As %String) [ Private ]
{
	Set current = ..RoleResources()
	If '..RoleSaved {
		Set ..RoleBefore = current
		Set ..RoleSaved = 1
	}
	Do $$$AssertStatusOK(..WriteRole(..Without(current, resource)), "the service role no longer holds "_resource)
}

/// The resource list without the entries of the resource.
ClassMethod Without(resources As %String, resource As %String) As %String
{
	Set result = ""
	For i = 1:1:$Length(resources, ",") {
		Set entry = $Piece(resources, ",", i)
		If (entry = "") || ($Piece(entry, ":", 1) = resource) Continue
		Set result = result_$Select(result = "": "", 1: ",")_entry
	}
	Quit result
}

/// The Description of the production in the namespace's definition table, "<none>" when it has no row. In the namespace itself.
ClassMethod DescriptionIn(namespace As %String, production As %String) As %String
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Set row = ##class(Ens.Config.Production).%OpenId(production)
	Quit $Select($IsObject(row): row.Description, 1: "<none>")
}

/// Makes sure the namespace's definition table has a row for the production, loaded from its class, and remembers what it did for OnAfterOneTest: a row
/// that the test made is deleted again. Returns the description that the row holds.
Method Defined(namespace As %String, production As %String) As %String [ Private ]
{
	If ..DescriptionIn(namespace, production) = "<none>" {
		Do $$$AssertStatusOK(..LoadDefinition(namespace, production), "the definition of "_production_" is loaded in "_namespace)
		Set list = $Select(..Definitions = "": [], 1: {}.%FromJSON(..Definitions))
		Do list.%Push({"namespace": (namespace), "production": (production)})
		Set ..Definitions = list.%ToJSON()
	}
	Quit ..DescriptionIn(namespace, production)
}

/// Loads the definition of the production from its class in the namespace. Calls only Ens classes while it is there.
ClassMethod LoadDefinition(namespace As %String, production As %String) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Quit ##class(Ens.Config.Production).LoadFromClass(production)
}

/// Puts back what the test changed: the service role, onlineDemo, and the definitions that it made.
Method PutBack() As %Status [ Private ]
{
	Set sc = $$$OK
	If ..PollerStopped {
		Set ..PollerStopped = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(Ens.Director).TempStopConfigItem(..#POLLER, 0, 1))
	}
	If ..OrdersStopped {
		Set ..OrdersStopped = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ..StartOrdersNow())
	}
	If ..RoleSaved {
		Set ..RoleSaved = 0
		Set sc = ..WriteRole(..RoleBefore)
	}
	If ..OnlineSaved {
		Set ..OnlineSaved = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..OnlineBefore))
	}
	If ..Definitions '= "" {
		Set list = {}.%FromJSON(..Definitions)
		Set ..Definitions = ""
		Set iterator = list.%GetIterator()
		While iterator.%GetNext(, .entry) {
			Set sc = $SYSTEM.Status.AppendStatus(sc, ..DeleteDefinition(entry.namespace, entry.production))
		}
	}
	Quit sc
}

/// Deletes the definition row of the production in the namespace, and returns to the namespace of the tests.
ClassMethod DeleteDefinition(namespace As %String, production As %String) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Quit ##class(Ens.Config.Production).%DeleteId(production)
}

/// Puts the double Test.Tools.CommandsDouble behind the CommandsIn item; OnAfterAllTests puts the real service back.
Method UseDouble() As %Boolean [ Private ]
{
	If ..Swap '= "" Quit 1
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).UseItemClass(..#ITEM, ..#DOUBLE, .saved)
	If $IsObject(saved) Set ..Swap = saved.%ToJSON()
	Do $$$AssertStatusOK(sc, "the double is put behind the "_..#ITEM_" item")
	Quit $$$ISOK(sc)
}

/// Puts the real CommandsIn class back behind the item when the double is there; OK when it was not.
Method Unswap() As %Status [ Private ]
{
	If ..Swap = "" Quit $$$OK
	Set saved = {}.%FromJSON(..Swap)
	Set ..Swap = ""
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreItemClass(..#ITEM, saved)
}

/// For a test that needs the real service behind the item: puts it back if an earlier test of the class put the double there (UseDouble puts the double
/// there again).
Method RestoreDouble() As %Boolean [ Private ]
{
	Set sc = ..Unswap()
	Do $$$AssertStatusOK(sc, "the real "_..#ITEM_" is behind the item")
	Quit $$$ISOK(sc)
}

/// Points the entries of the runners at the mock's key variable, for a turn through ChatAgent; OnAfterAllTests puts them back.
Method PointKeys() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	If ..Pointed Quit 1
	Set ..Pointed = 1
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).PointKeys()
	Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
	Quit $$$ISOK(sc)
}

/// Begins a bridge context in the test process for a turn of the owner with the ItemId and the provenance, as the runner does before Chat.
Method Begin(owner As %String, itemId As %String, provenance As %String = "user") [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = provenance
	Set request.ItemId = itemId
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = owner
	Set request.Channel = "system"
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(request, ""), "a context begins for the turn of '"_owner_"'")
}

/// The commands that the double recorded, in order, as a dynamic array of {"class","origin","sessionRef","key","fields"}.
ClassMethod Calls() As %DynamicArray
{
	Set calls = []
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("CommandsDouble", "calls", n))
		Quit:n=""
		Set call = ^OcuTalonTest("CommandsDouble", "calls", n)
		Do calls.%Push({"class": ($List(call, 1)), "origin": ($List(call, 2)), "sessionRef": ($List(call, 3)), "key": ($List(call, 4)), "fields": ({}.%FromJSON($List(call, 5)))})
	}
	Quit calls
}

/// The BackgroundCheck rows of the session, by ID, as a dynamic array of {"ref","kind","namespace","production","displayName","askedBy","nextDueAt",
/// "lastRunAt","result","createdAt"}.
ClassMethod Rows(sessionRef As %String) As %DynamicArray
{
	Set rows = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, Kind, Namespace, Production, DisplayName, AskedBy, NextDueAt, LastRunAt, Result, CreatedAt FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ? ORDER BY ID", sessionRef)
	While rs.%Next() {
		Do rows.%Push({"ref": (rs.%GetData(1)), "kind": (rs.%GetData(2)), "namespace": (rs.%GetData(3)), "production": (rs.%GetData(4)), "displayName": (rs.%GetData(5)), "askedBy": (rs.%GetData(6)), "nextDueAt": (rs.%GetData(7)), "lastRunAt": (rs.%GetData(8)), "result": (rs.%GetData(9)), "createdAt": (rs.%GetData(10))})
	}
	Quit rows
}

/// The number of BackgroundCheck rows of the whole table.
ClassMethod RowCount() As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck")
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// A fixture row: the session watches the production of OCUORDERS under the display name Orders, created now (CreatedAt, as WatchOps writes it). The
/// Ref of the row is given back.
Method Watch(sessionRef As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(sessionRef, ##class(OcuTalon.Install.Step.Demo).#NAMESPACE, ##class(OcuTalon.Install.Step.Demo).#PRODUCTION, {"DisplayName": "Orders", "AskedBy": "zzfixture", "CreatedAt": (##class(OcuTalon.Data.Time).NowUtc())})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// Deletes the BackgroundCheck rows of the sessions of the run (the rows that WatchOps made).
Method DropRows() [ Private ]
{
	For i = 1:1:$Length(..Sessions, ",") {
		Set ref = $Piece(..Sessions, ",", i)
		If ref '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?", ref)
	}
}

/// The newest id of the table of the namespace, 0 when it is empty. In the namespace, calling only SQL while it is there.
ClassMethod Top(table As %String, namespace As %String) As %Integer
{
	New $NAMESPACE
	Set $NAMESPACE = namespace
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM "_table)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// Sends count orders dated 2026-10-16 in the date format that fails (MM/DD/YYYY), so that each one fails with the sentence ORDERDATETEXT, every message tagged
/// with the trace reference (none when empty), through the Orders partner of OCUORDERS (a copy of the Demo test's private three-line Send, which is Epic 4's). Asserts that the partner accepts them.
Method Fail(count As %Integer, traceRef As %String = "") As %Boolean [ Private ]
{
	If ..OrdersFloor = "" {
		Set ..OrdersFloor = ..Top("Ens.MessageHeader", ..#ORDERS)
		Set ..OrdersLogFloor = ..Top("Ens_Util.Log", ..#ORDERS)
	}
	Set sc = ..SendOrders(count, traceRef)
	Do $$$AssertStatusOK(sc, count_" failing orders are sent"_$Select(traceRef '= "": " with a trace reference", 1: " with none"))
	Quit $$$ISOK(sc)
}

ClassMethod SendOrders(count As %Integer, traceRef As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Quit ##class(OcuTalon.Demo.Orders.Partner).Send(count, "MM/DD/YYYY", traceRef, "2026-10-16")
}

/// The failed headers (Status 8) of OCUORDERS after the first Fail of the test, as a dynamic array of {"id", "superSession", "at"}, by id.
ClassMethod Failed(floor As %Integer) As %DynamicArray
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set failed = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SuperSession, TimeProcessed FROM Ens.MessageHeader WHERE ID > ? AND Status = 8 ORDER BY ID", floor)
	While rs.%Next() {
		Do failed.%Push({"id": (rs.%GetData(1)), "superSession": (rs.%GetData(2)), "at": (rs.%GetData(3))})
	}
	Quit failed
}

/// Waits up to WAITBATCH seconds, polling every half second, for count failed headers in OCUORDERS after the test's first Fail; the failed headers.
Method WaitFailed(count As %Integer) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + ..#WAITBATCH
	For {
		Set failed = ..Failed(..OrdersFloor)
		If (failed.%Size() '< count) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(failed.%Size(), count, count_" orders are in the error status in OCUORDERS")
	Quit failed
}

/// The ids of the headers as a comma-separated list, in the order given.
ClassMethod HeaderIds(failed As %DynamicArray) As %String
{
	Set ids = ""
	Set iterator = failed.%GetIterator()
	While iterator.%GetNext(, .failure) {
		Set ids = ids_$Select(ids = "": "", 1: ",")_failure.id
	}
	Quit ids
}

/// A header in OCUORDERS that has not failed yet: a request from zzPollerSource to zzPollerTarget in the SuperSession, Status 3 (delivered), created and
/// processed five minutes ago, in a session of its own. LateError moves it to the error status later. Its id is given back, and removed with the test.
Method LateHeader(superSession As %String) As %Integer [ Private ]
{
	Set earlier = ##class(OcuTalon.Watch.Mark).Shift(##class(OcuTalon.Watch.Mark).Normal(##class(OcuTalon.Data.Time).NowUtc()), -300)
	Set id = ..MakeHeader(superSession, earlier)
	Set ..FixtureHeaders = ..FixtureHeaders_$ListBuild(id)
	Quit id
}

ClassMethod MakeHeader(superSession As %String, stamp As %String) As %Integer [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.SuperSession = superSession
	Set header.TimeCreated = stamp
	Set header.TimeProcessed = stamp
	Set header.SourceConfigName = "zzPollerSource"
	Set header.TargetConfigName = "zzPollerTarget"
	Set header.Type = 1
	Set header.Status = 3
	Set sc = header.%Save()
	If $$$ISOK(sc) {
		Set header.SessionId = header.%Id()
		Set sc = header.%Save()
	}
	Quit $Select($$$ISOK(sc): header.%Id(), 1: "")
}

/// Moves the fixture header to the error status (SetStatus, which sets its TimeProcessed to now).
ClassMethod LateError(id As %Integer) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set header = ##class(Ens.MessageHeader).%OpenId(id)
	If '$IsObject(header) Quit $SYSTEM.Status.Error(5001, "No header "_id)
	Do header.SetStatus(8)
	Quit $$$OK
}

/// A header in OCUORDERS from zzPollerSource to zzPollerTarget for the fields (an object; all optional): Status (8), Type (1), IsError (0), ErrorStatus (a status
/// text, "" for none) and SessionId (its own id). TimeProcessed is now; removed with the test. Its id is given back.
Method FixtureHeader(fields As %DynamicObject) As %Integer [ Private ]
{
	Set id = ..MakeFixtureHeader(fields)
	Set ..FixtureHeaders = ..FixtureHeaders_$ListBuild(id)
	Quit id
}

ClassMethod MakeFixtureHeader(fields As %DynamicObject) As %Integer [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set now = $ZDateTime($ZTimeStamp, 3, 1, 3)
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.TimeCreated = now
	Set header.TimeProcessed = now
	Set header.SourceConfigName = "zzPollerSource"
	Set header.TargetConfigName = "zzPollerTarget"
	Set header.Type = $Select(fields.%IsDefined("Type"): fields.Type, 1: 1)
	Set header.Status = $Select(fields.%IsDefined("Status"): fields.Status, 1: 8)
	Set header.IsError = $Select(fields.%IsDefined("IsError"): fields.IsError, 1: 0)
	If fields.ErrorStatus '= "" Set header.ErrorStatus = $SYSTEM.Status.Error(5001, fields.ErrorStatus)
	Set sc = header.%Save()
	If $$$ISOK(sc) {
		Set header.SessionId = $Select(fields.%IsDefined("SessionId"): fields.SessionId, 1: header.%Id())
		Set sc = header.%Save()
	}
	Quit $Select($$$ISOK(sc): header.%Id(), 1: "")
}

/// A Type 2 event-log row of OCUORDERS in the session, naming the message id (may be empty) and the ConfigName; removed with the test. Its id is given back.
Method FixtureLog(sessionId As %Integer, messageId As %Integer, config As %String, text As %String) As %Integer [ Private ]
{
	Set id = ..MakeSessionLog(sessionId, messageId, config, text)
	Set ..FixtureLogs = ..FixtureLogs_$ListBuild(id)
	Quit id
}

ClassMethod MakeSessionLog(sessionId As %Integer, messageId As %Integer, config As %String, text As %String) As %Integer [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set log = ##class(Ens.Util.Log).%New()
	Set log.Type = 2
	Set log.ConfigName = config
	Set log.SessionId = sessionId
	Set log.MessageId = messageId
	Set log.Text = text
	Set log.TimeLogged = $ZDateTime($ZTimeStamp, 3, 1, 3)
	Set sc = log.%Save()
	Quit $Select($$$ISOK(sc): log.%Id(), 1: "")
}

/// An event-log row of OCUORDERS with no session, of the type (2 error, 6 alert) and the ConfigName; removed with the test. Its id is given back.
Method HeaderlessLog(type As %Integer, config As %String) As %Integer [ Private ]
{
	Set id = ..MakeLog(type, config)
	Set ..FixtureLogs = ..FixtureLogs_$ListBuild(id)
	Quit id
}

ClassMethod MakeLog(type As %Integer, config As %String) As %Integer [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set log = ##class(Ens.Util.Log).%New()
	Set log.Type = type
	Set log.ConfigName = config
	Set log.Text = "A fixture row with no session: "_config
	Set log.TimeLogged = $ZDateTime($ZTimeStamp, 3, 1, 3)
	Set sc = log.%Save()
	Quit $Select($$$ISOK(sc): log.%Id(), 1: "")
}

/// The newest header id of OCUTALON, where the poller's batches arrive; the first call of a test also fixes the floor that the clean-up removes from.
Method Since() As %Integer [ Private ]
{
	Set top = ..Top("Ens.MessageHeader", $Namespace)
	If ..HomeFloor = "" Set ..HomeFloor = top
	Quit top
}

/// The FailureBatch messages that IncidentManager holds after the header id since, as a dynamic array in id order of {"id", "status", "sessionId",
/// "superSession", "namespace", "production", "ownerRef", "polledAt", "failures": [{"kind", "headerId", "sessionId", "item", "source", "bodyClass",
/// "errorText", "failedAt", "logId"}]}.
ClassMethod Batches(since As %Integer) As %DynamicArray
{
	Set batches = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Status, SessionId, SuperSession, MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND TargetConfigName = ? AND MessageBodyClassName = 'OcuTalon.Watch.Msg.FailureBatch' ORDER BY ID", since, ..#MANAGER)
	While rs.%Next() {
		Set body = ##class(OcuTalon.Watch.Msg.FailureBatch).%OpenId(rs.%GetData(5))
		If '$IsObject(body) Continue
		Set failures = []
		For i = 1:1:body.Failures.Count() {
			Set failure = body.Failures.GetAt(i)
			Do failures.%Push({"kind": (failure.Kind), "headerId": (failure.HeaderId), "sessionId": (failure.SessionId), "item": (failure.ItemName), "source": (failure.SourceName), "bodyClass": (failure.BodyClass), "errorText": (failure.ErrorText), "failedAt": (failure.FailedAt), "logId": (failure.LogId)})
		}
		Do batches.%Push({"id": (rs.%GetData(1)), "status": (rs.%GetData(2)), "sessionId": (rs.%GetData(3)), "superSession": (rs.%GetData(4)), "namespace": (body.Namespace), "production": (body.Production), "ownerRef": (body.OwnerRef), "polledAt": (body.PolledAt), "failures": (failures)})
	}
	Quit batches
}

/// The number of failures in the batches, of the owner when it is not empty.
ClassMethod Count(batches As %DynamicArray, owner As %String = "") As %Integer
{
	Set count = 0
	Set iterator = batches.%GetIterator()
	While iterator.%GetNext(, .batch) {
		If (owner = "") || (batch.ownerRef = owner) Set count = count + batch.failures.%Size()
	}
	Quit count
}

/// Waits up to WAITBATCH seconds, polling every half second, until the batches after since hold at least count failures (of the owner, when it is
/// not empty); the batches then. A shortfall is the caller's assertion.
Method WaitBatched(since As %Integer, count As %Integer, owner As %String = "") As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + ..#WAITBATCH
	For {
		Set batches = ..Batches(since)
		If (..Count(batches, owner) '< count) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit batches
}

/// The header ids of the failures of the batches (of the owner when it is not empty), ascending, each as many times as it appears.
ClassMethod Ids(batches As %DynamicArray, owner As %String = "") As %String
{
	Set iterator = batches.%GetIterator()
	While iterator.%GetNext(, .batch) {
		If (owner '= "") && (batch.ownerRef '= owner) Continue
		Set at = batch.failures.%GetIterator()
		While at.%GetNext(, .failure) {
			Set key = $Select(failure.headerId '= "": failure.headerId, 1: "l"_failure.logId)
			Set seen(key) = $Get(seen(key)) + 1
		}
	}
	Set ids = ""
	Set key = ""
	For {
		Set key = $Order(seen(key))
		Quit:key=""
		For i = 1:1:seen(key) {
			Set ids = ids_$Select(ids = "": "", 1: ",")_key
		}
	}
	Quit ids
}

/// Waits the pause that two polls take (QUIET seconds).
ClassMethod Settle()
{
	Hang ..#QUIET
}

/// Deletes the WatchMark rows of the namespace (the poller is the only writer of the mark; a test that needs a reading from the watch's CreatedAt on
/// begins by clearing it).
ClassMethod ClearMark(namespace As %String)
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.WatchMark WHERE Namespace = ?", namespace)
}

/// The WatchMark row of the production as {"exists", "markAt", "seen"}.
ClassMethod Mark(namespace As %String, production As %String) As %DynamicObject
{
	Set row = ##class(OcuTalon.Data.WatchMark).NamespaceProductionIndexOpen(namespace, production)
	If '$IsObject(row) Quit {"exists": 0, "markAt": "", "seen": ""}
	Quit {"exists": 1, "markAt": (row.MarkAt), "seen": (row.Seen)}
}

/// Waits up to WAITBATCH seconds for the WatchMark row of the production (the poller saves it just after it sends); its state as Mark gives it.
Method WaitMark(namespace As %String, production As %String) As %DynamicObject [ Private ]
{
	Set end = $ZHorolog + ..#WAITBATCH
	For {
		Set mark = ..Mark(namespace, production)
		If mark.exists || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit mark
}

/// Stops the FailurePoller item for the test (TempStopConfigItem, which leaves the definition as it is); OnAfterOneTest starts it again.
Method StopPoller() As %Boolean [ Private ]
{
	Set ..PollerStopped = 1
	Set sc = ##class(Ens.Director).TempStopConfigItem(..#POLLER, 1, 1)
	Do $$$AssertStatusOK(sc, "the "_..#POLLER_" item is stopped for the test")
	Quit $$$ISOK(sc)
}

/// Starts the FailurePoller item again.
Method StartPoller() As %Boolean [ Private ]
{
	Set sc = ##class(Ens.Director).TempStopConfigItem(..#POLLER, 0, 1)
	Do $$$AssertStatusOK(sc, "the "_..#POLLER_" item is started again")
	If $$$ISOK(sc) Set ..PollerStopped = 0
	Quit $$$ISOK(sc)
}

/// Stops the Orders production in OCUORDERS for the test; OnAfterOneTest starts it again.
Method StopOrders() As %Boolean [ Private ]
{
	Set ..OrdersStopped = 1
	Set sc = ..StopOrdersNow()
	Do $$$AssertStatusOK(sc, "the Orders production is stopped")
	Quit $$$ISOK(sc)
}

/// Starts the Orders production in OCUORDERS again, and asserts that it runs.
Method StartOrders() As %Boolean [ Private ]
{
	Set sc = ..StartOrdersNow()
	Do $$$AssertStatusOK(sc, "the Orders production is started again")
	Do $$$AssertTrue(..OrdersRunning(), "and it runs")
	If $$$ISOK(sc) Set ..OrdersStopped = 0
	Quit $$$ISOK(sc)
}

ClassMethod StopOrdersNow() As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Quit ##class(Ens.Director).StopProduction(10, 1)
}

ClassMethod StartOrdersNow() As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	If ##class(Ens.Director).IsProductionRunning() Quit $$$OK
	Quit ##class(Ens.Director).StartProduction(..#ORDERSPRODUCTION)
}

/// 1 when the Orders production runs in OCUORDERS.
ClassMethod OrdersRunning() As %Boolean
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Quit ''##class(Ens.Director).IsProductionRunning(.name) && (name = ..#ORDERSPRODUCTION)
}

/// Removes what the test made in OCUORDERS (the headers after the floor, with their bodies and the log rows of their sessions, the tagged messages of the
/// run, the fixture headers and log rows) and the FailureBatch messages that the poller sent to IncidentManager after the test's floor.
Method DropMessages() [ Private ]
{
	If (..OrdersFloor '= "") || (..FixtureHeaders '= "") || (..FixtureLogs '= "") {
		If ..OrdersFloor '= "" Do ..DropOrders(..OrdersFloor, ..OrdersLogFloor)
		Do ..DropFixtures(..FixtureHeaders, ..FixtureLogs)
		If (..OrdersFloor '= "") && (..Supers.%Size() > 0) Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Supers, ..#ORDERS)
	}
	If ..HomeFloor '= "" Do ..DropBatches(..HomeFloor)
	Set ..OrdersFloor = ""
	Set ..HomeFloor = ""
	Set ..FixtureHeaders = ""
	Set ..FixtureLogs = ""
}

/// The headers of OCUORDERS after the floor, their bodies and the log rows of their sessions, and the log rows after the log floor that have no
/// session and a type of error or alert. In the namespace, calling only Ens, % and the message bodies' classes while it is there.
ClassMethod DropOrders(floor As %Integer, logFloor As %Integer) [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SessionId, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE ID > ?", floor)
	While rs.%Next() {
		Set ids(rs.%GetData(1)) = $ListBuild(rs.%GetData(3), rs.%GetData(4))
		If rs.%GetData(2) '= "" Set sessions(rs.%GetData(2)) = ""
	}
	Set id = ""
	For {
		Set id = $Order(ids(id), 1, body)
		Quit:id=""
		If $List(body, 1) '= "" Do $ClassMethod($List(body, 1), "%DeleteId", $List(body, 2))
		Do ##class(Ens.MessageHeader).%DeleteId(id)
	}
	Set session = ""
	For {
		Set session = $Order(sessions(session))
		Quit:session=""
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE SessionId = ?", session)
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND SessionId IS NULL AND Type IN (2, 6) AND ConfigName LIKE 'zz%'", logFloor)
}

/// The fixture headers and log rows of OCUORDERS by id.
ClassMethod DropFixtures(headers As %List, logs As %List) [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set position = 0
	While $ListNext(headers, position, id) {
		Do ##class(Ens.MessageHeader).%DeleteId(id)
	}
	Set position = 0
	While $ListNext(logs, position, id) {
		Do ##class(Ens.Util.Log).%DeleteId(id)
	}
}

/// The FailureBatch messages after the header id in OCUTALON (the header and the body of each).
ClassMethod DropBatches(floor As %Integer) [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND TargetConfigName = ? AND MessageBodyClassName = 'OcuTalon.Watch.Msg.FailureBatch'", floor, ..#MANAGER)
	While rs.%Next() {
		Set ids(rs.%GetData(1)) = rs.%GetData(2)
	}
	Set id = ""
	For {
		Set id = $Order(ids(id), 1, body)
		Quit:id=""
		Do ##class(OcuTalon.Watch.Msg.FailureBatch).%DeleteId(body)
		Do ##class(Ens.MessageHeader).%DeleteId(id)
	}
}

/// The names of the keys of the object, sorted, comma-separated.
ClassMethod SortedKeys(object As %DynamicObject) As %String
{
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set sorted(key) = ""
	}
	Set names = ""
	Set key = ""
	For {
		Set key = $Order(sorted(key))
		Quit:key=""
		Set names = names _ $Select(names = "": "", 1: ",") _ key
	}
	Quit names
}

/// Asserts that the answer (a dynamic object, or the JSON text that the model got) has the fields of the expected flat object with its values and types,
/// and no other. A field that holds an array or an object is compared by its JSON text.
Method AssertObject(actual As %Any, expected As %DynamicObject, label As %String) [ Private ]
{
	If '$IsObject(actual) {
		Set text = actual
		Set actual = ""
		Try {
			Set actual = {}.%FromJSON(text)
		} Catch {
			Set actual = ""
		}
		If '$IsObject(actual) {
			Do $$$AssertTrue(0, label_": the result is a JSON object: "_$Extract(text, 1, 200))
			Quit
		}
	}
	Do $$$AssertEquals(..SortedKeys(actual), ..SortedKeys(expected), label_": the fields")
	Set iterator = expected.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		Do $$$AssertEquals(actual.%GetTypeOf(key), expected.%GetTypeOf(key), label_": "_key_" is a "_expected.%GetTypeOf(key))
		If $IsObject(value) {
			Do $$$AssertEquals(actual.%Get(key).%ToJSON(), value.%ToJSON(), label_": "_key_" is "_value.%ToJSON())
		} Else {
			Do $$$AssertEquals(actual.%Get(key), value, label_": "_key_" is '"_value_"'")
		}
	}
}

}
