/// The base of the Story 5.1 test classes that run over the running production (Test.Watch.Reader, Grant, Ops, Tools and Turns). THEY RUN IN THROWAWAY
/// STACKS AND IN CI ONLY (Rule 21), with demo mode on: they need the running OcuTalon.Production and the Orders demo production in OCUORDERS, and fail
/// with the reason where they do not have them (Reason), so that a broken start can never give a green shard. It extends Test.Core.InProduction (Guard,
/// the fixture sessions, the clean-up of the run's messages) and adds what the watch tests share:
///   - Reason: "" when OCUORDERS exists, demo mode is on and the Orders production is current there;
///   - the changes that a test makes to the instance, each put back by OnAfterOneTest, also after a failure: SetOnlineDemo (the public flag), GrantRole
///     and RevokeRole (a resource of the service role), and Described (a production's description in a namespace's definition table);
///   - UseDouble and RestoreDouble (Test.Tools.CommandsDouble behind the CommandsIn item), Begin (a bridge context for a turn), Calls (what the double
///     recorded), Rows and Row (the BackgroundCheck rows of a session) and Watch (a fixture session's watch of Orders);
///   - OnAfterOneTest and OnAfterAllTests delete the BackgroundCheck rows of the run's sessions, so a row that a test made through WatchOps is gone too.
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

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("CommandsDouble")
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
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Set sc = ..PutBack()
	If ..Swap '= "" {
		Set saved = {}.%FromJSON(..Swap)
		Set ..Swap = ""
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreItemClass(..#ITEM, saved))
	}
	If ..Pointed && ##class(OcuTalon.Test.Agent.RunnerFixture).Running() {
		Set ..Pointed = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys())
	}
	Do ..DropRows()
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
/// "lastRunAt","result"}.
ClassMethod Rows(sessionRef As %String) As %DynamicArray
{
	Set rows = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, Kind, Namespace, Production, DisplayName, AskedBy, NextDueAt, LastRunAt, Result FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ? ORDER BY ID", sessionRef)
	While rs.%Next() {
		Do rows.%Push({"ref": (rs.%GetData(1)), "kind": (rs.%GetData(2)), "namespace": (rs.%GetData(3)), "production": (rs.%GetData(4)), "displayName": (rs.%GetData(5)), "askedBy": (rs.%GetData(6)), "nextDueAt": (rs.%GetData(7)), "lastRunAt": (rs.%GetData(8)), "result": (rs.%GetData(9))})
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

/// A fixture row: the session watches the production of OCUORDERS under the display name Orders. The Ref of the row is given back.
Method Watch(sessionRef As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(sessionRef, ##class(OcuTalon.Install.Step.Demo).#NAMESPACE, ##class(OcuTalon.Install.Step.Demo).#PRODUCTION, {"DisplayName": "Orders", "AskedBy": "zzfixture"})
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
