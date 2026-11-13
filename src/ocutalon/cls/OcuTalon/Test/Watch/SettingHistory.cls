Include Ensemble

/// Tests of the setting history over a running production (Story 36.1; AD-3, AD-15, AD-18): OcuTalon.Watch.SettingHistory, driven from the Tick of Checks, and
/// Reader.Settings. THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case: they need OCUORDERS and the Orders demo
/// production, and fail with the reason where they do not have them. Each test watches Orders through a fixture session, takes its own snapshots by sending Ticks
/// (Case.Tick), and changes the production only through the saved definition (Test.Watch.OrdersDefinition) and a System Default Setting row, which OnAfterOneTest
/// puts back. A real Tick may run between a test's steps and do what a test's Tick would do, so each test asserts what holds whichever Tick acts first.
///   - TestMeasuredCounter (Task 0): the production-change counter, ^IRIS.Temp.EnsProdModCounter(OCUORDERS), moves when the saved definition of the running Orders
///     production is saved and when a System Default Setting row is saved, and does not move when Reader.Settings reads every setting; the settings that the
///     definition stores for an item and its class does not know are not among the entries that PopulateVirtualSettings lists;
///   - TestCounterUnchanged: a Tick with the marks of the newest snapshot and a check under an hour old reads no settings and writes no row, not even CheckedAt; an
///     hour or more later it checks again, and settings that are the same only refresh the marks;
///   - TestChangesRecorded: a first snapshot has no change; a setting saved in the definition and then a System Default Setting that applies each give one
///     SettingChange (Source production and default) on the next Tick, detected within the check interval, with only the columns the tables are specified to have
///     (none names a user); a class setting that nothing sets has the source class, and one that the definition sets the source production;
///   - TestRestartAndCounterGone (QA): a start mark that differs from the newest snapshot's (a restart) with the counter as it was reads the settings, and a setting
///     that differs gives one change and a snapshot with the live start mark; a counter that is gone (an IRIS restart) reads them too, and settings that are the same
///     only refresh CheckedAt and the marks;
///   - TestSnapshotChangesNothing: taking snapshots leaves the counter, the saved definition and the System Default Settings as they were;
///   - TestCredentialsReference: a setting that holds an Ens.Config.Credentials ID is recorded with the IDs, as a plain value;
///   - TestSecretValue: a setting whose value is a secret is recorded with both values blank and its hash in the snapshot only, and the same secret read again with
///     the earlier hash is no change;
///   - TestSameNameItems: items that share a name are one in a snapshot, the first of them that is enabled (else the first); a change to a disabled copy is no
///     change, and a change to the enabled one is recorded with its own earlier value;
///   - TestClassSettings: on an item whose class has a credentialsSelector setting that is not named Credentials and a class setting whose name looks like a secret,
///     the first keeps its ID with credential 0 and the second is blank with a hash that never reaches a change row;
///   - TestSkippedReads: a watched production whose namespace the service user cannot read (unreadable) or that is not the namespace's own (not_current) gets
///     no snapshot and no warning;
///   - TestReadFailure: a production whose read throws gets no row and a warning, and the next watched production is still snapshotted;
///   - TestOnlineDemoOff: with onlineDemo on, a Tick takes no snapshot and writes no row.
Class OcuTalon.Test.Watch.SettingHistory Extends OcuTalon.Test.Watch.Case [ DependsOn = OcuTalon.Test.Watch.OrdersDefinition ]
{

Parameter DEFINITION = "OcuTalon.Test.Watch.OrdersDefinition";

Parameter NOTE = {##class(OcuTalon.Test.Watch.OrdersDefinition).#NOTE};

/// The item of the Orders production whose settings the definition changes (the failing item), and the class setting that the System Default Setting row sets.
Parameter DEFINEDITEM = {##class(OcuTalon.Test.Watch.OrdersDefinition).#ITEM};

Parameter SDSSETTING = "RetryInterval";

Parameter SDSVALUE = 7;

/// The comment that marks the items a test adds to the saved Orders definition, so that they are the only ones taken out again.
Parameter MARK = "zz-setting-history-test";

/// The class of the item that TestClassSettings adds: its adapter has ProxyAuthorization (a credentialsSelector setting) and UseCookies (a name that looks like a secret).
Parameter PROBECLASS = "EnsLib.HTTP.GenericOperation";

/// The spelling of the Orders namespace that a test made watched in addition to the exact one, "" when none: its Orders history is removed with the test.
Property Other As %String;

/// The production-change counter of OCUORDERS that a test took away, "" when none: OnAfterOneTest puts it back if it is still gone.
Property TakenCounter As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do ..DropItems()
	Do ..DropHistory()
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	If ..TakenCounter '= "" {
		If $Get(^IRIS.Temp.EnsProdModCounter(..#ORDERS)) = "" Set ^IRIS.Temp.EnsProdModCounter(..#ORDERS) = ..TakenCounter
		Set ..TakenCounter = ""
	}
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..DropItems())
	Set sc = $SYSTEM.Status.AppendStatus(sc, $ClassMethod(..#DEFINITION, "Put", 0))
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..DropDefault())
	Do ..DropHistory()
	If ..Other '= "" {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SettingChange WHERE Namespace = ? AND Production = ?", ..Other, ..#ORDERSPRODUCTION)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SettingSnapshot WHERE Namespace = ? AND Production = ?", ..Other, ..#ORDERSPRODUCTION)
		Set ..Other = ""
	}
	Quit sc
}

/// The production-change counter of OCUORDERS, "" when it has none.
ClassMethod Counter() As %String
{
	Quit $Get(^IRIS.Temp.EnsProdModCounter(..#ORDERS))
}

/// Saves the System Default Setting row of SDSSETTING for ITEMNAME in the Orders production, through the class, so that the production-change counter moves.
ClassMethod SaveDefault(value As %String) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set row = ##class(Ens.Config.DefaultSettings).%New()
	Set row.ProductionName = ..#ORDERSPRODUCTION
	Set row.ItemName = ..#ITEMNAME
	Set row.HostClassName = "*"
	Set row.SettingName = ..#SDSSETTING
	Set row.SettingValue = value
	Quit row.%Save()
}

/// Removes that row; OK when it is not there.
ClassMethod DropDefault() As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set id = ..#ORDERSPRODUCTION_"||"_..#ITEMNAME_"||*||"_..#SDSSETTING
	If '##class(Ens.Config.DefaultSettings).%ExistsId(id) Quit $$$OK
	Quit ##class(Ens.Config.DefaultSettings).%DeleteId(id)
}

/// 1 when PopulateVirtualSettings lists the setting for the item of the Orders production.
ClassMethod VirtualListed(item As %String, setting As %String) As %Boolean
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set production = ##class(Ens.Config.Production).%OpenId(..#ORDERSPRODUCTION)
	Set found = 0
	For i = 1:1:production.Items.Count() {
		Set entry = production.Items.GetAt(i)
		If entry.Name '= item Continue
		Do entry.PopulateVirtualSettings()
		For j = 1:1:entry.VirtualSettings.Count() {
			If $List(entry.VirtualSettings.GetAt(j), 2) = setting Set found = 1
		}
	}
	Quit found
}

/// A checksum of what Interoperability stores for the Orders production: its definition, its items with their settings and the System Default Settings.
ClassMethod Fingerprint() As %Integer
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set crc = 0
	For root = "^Ens.Config.ProductionD", "^Ens.Config.ItemD", "^Ens.Config.DefaultSettingsD" {
		If '$Data(@root) Continue
		Set crc = $ZCrc(root, 7, crc)
		Set node = root
		For {
			Set node = $Query(@node, 1, data)
			Quit:node=""
			Set crc = $ZCrc(data, 7, $ZCrc(node, 7, crc))
		}
	}
	Quit crc
}

/// Deletes the history rows of the Orders production and of the fixture productions of TestSkippedReads, and only those.
ClassMethod DropHistory()
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SettingSnapshot WHERE (Namespace = 'ZZNS' AND Production = 'Zz.Unreadable') OR (Namespace = ? AND Production = 'Zz.NotCurrent')", ..#ORDERS)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SettingChange WHERE Namespace = ? AND Production = ?", ..#ORDERS, ..#ORDERSPRODUCTION)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SettingSnapshot WHERE Namespace = ? AND Production = ?", ..#ORDERS, ..#ORDERSPRODUCTION)
}

/// The class of the item that the definition changes.
ClassMethod ItemClass() As %String
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set production = ##class(Ens.Config.Production).%OpenId(..#ORDERSPRODUCTION)
	If '$IsObject(production) Quit ""
	For i = 1:1:production.Items.Count() {
		If production.Items.GetAt(i).Name = ..#DEFINEDITEM Quit
	}
	Quit $Select(i '> production.Items.Count(): production.Items.GetAt(i).ClassName, 1: "")
}

/// Adds an item to the saved Orders definition, marked by MARK: the class (the defined item's when className is empty), enabled or not, at position in the
/// definition's items (the end when 0), with settings (a dynamic array of {"target", "name", "value"}). It does not update the running production.
ClassMethod AddItem(name As %String, enabled As %Boolean, position As %Integer = 0, settings As %DynamicArray = "", className As %String = "") As %Status
{
	Set class = $Select(className '= "": className, 1: ..ItemClass())
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set production = ##class(Ens.Config.Production).%OpenId(..#ORDERSPRODUCTION)
	If '$IsObject(production) Quit $SYSTEM.Status.Error(5001, "There is no definition of "_..#ORDERSPRODUCTION)
	Set item = ##class(Ens.Config.Item).%New()
	Set item.Production = production
	Set item.Name = name
	Set item.ClassName = class
	Set item.Enabled = enabled
	Set item.PoolSize = 1
	Set item.Comment = ..#MARK
	If $IsObject(settings) {
		Set iterator = settings.%GetIterator()
		While iterator.%GetNext(, .entry) {
			Set setting = ##class(Ens.Config.Setting).%New()
			Set setting.Target = entry.target
			Set setting.Name = entry.name
			Set setting.Value = entry.value
			Do item.Settings.Insert(setting)
		}
	}
	Set sc = item.%Save()
	If $$$ISERR(sc) Quit sc
	If position > 0 {
		Do production.Items.InsertAt(item, position)
	} Else {
		Do production.Items.Insert(item)
	}
	Quit production.%Save()
}

/// Sets the stored setting of the items of that name whose Enabled is enabled (the setting is added where it is not there), and saves the definition.
ClassMethod ChangeStored(name As %String, enabled As %Boolean, target As %String, setting As %String, value As %String) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set production = ##class(Ens.Config.Production).%OpenId(..#ORDERSPRODUCTION)
	If '$IsObject(production) Quit $SYSTEM.Status.Error(5001, "There is no definition of "_..#ORDERSPRODUCTION)
	Set changed = 0
	Set sc = $$$OK
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		If (item.Name '= name) || (+item.Enabled '= +enabled) Continue
		Set found = 0
		For j = 1:1:item.Settings.Count() {
			Set stored = item.Settings.GetAt(j)
			If (stored.Target = target) && (stored.Name = setting) Set stored.Value = value, found = 1
		}
		If 'found {
			Set stored = ##class(Ens.Config.Setting).%New()
			Set stored.Target = target
			Set stored.Name = setting
			Set stored.Value = value
			Do item.Settings.Insert(stored)
		}
		Set sc = item.%Save()
		If $$$ISERR(sc) Quit
		Set changed = changed + 1
	}
	If $$$ISERR(sc) Quit sc
	If 'changed Quit $SYSTEM.Status.Error(5001, "The definition has no such item "_name)
	Quit production.%Save()
}

/// Takes the items that AddItem added out of the saved Orders definition and deletes them; OK when there are none.
ClassMethod DropItems() As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set production = ##class(Ens.Config.Production).%OpenId(..#ORDERSPRODUCTION)
	If '$IsObject(production) Quit $$$OK
	Set removed = 0
	For i = production.Items.Count():-1:1 {
		Set item = production.Items.GetAt(i)
		If '$IsObject(item) Continue
		If item.Comment '= ..#MARK Continue
		Do production.RemoveItem(item)
		Set removed = removed + 1
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Config.Item WHERE Production = ? AND Comment = ?", ..#ORDERSPRODUCTION, ..#MARK)
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "The marked items were not deleted: SQLCODE "_result.%SQLCODE)
	If 'removed Quit $$$OK
	Quit production.%Save()
}

/// The number of snapshots of the Orders production.
ClassMethod Snapshots() As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SettingSnapshot WHERE Namespace = ? AND Production = ?", ..#ORDERS, ..#ORDERSPRODUCTION)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The newest snapshot of the Orders production, or "".
ClassMethod Newest() As OcuTalon.Data.SettingSnapshot
{
	Set id = ##class(OcuTalon.Data.SettingSnapshot).Newest(..#ORDERS, ..#ORDERSPRODUCTION)
	Set snapshot = $Select(id '= "": ##class(OcuTalon.Data.SettingSnapshot).%OpenId(id), 1: "")
	If $IsObject(snapshot) Do snapshot.%Reload()
	Quit snapshot
}

/// The entry of the snapshot's settings for the item and the setting, or "".
ClassMethod Entry(snapshot As OcuTalon.Data.SettingSnapshot, item As %String, setting As %String) As %DynamicObject
{
	If '$IsObject(snapshot) Quit ""
	Set iterator = ##class(%Library.DynamicAbstractObject).%FromJSON(snapshot.Settings).%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.item = item) && (entry.setting = setting) Quit
	}
	Quit $Select($IsObject($Get(entry)) && (entry.item = item) && (entry.setting = setting): entry, 1: "")
}

/// The change rows of the Orders production, by id, as a dynamic array of {"item","target","setting","oldValue","newValue","source","credential","detectedAt","snapshotRef"},
/// those of the setting only when one is given.
ClassMethod Changes(setting As %String = "") As %DynamicArray
{
	Set changes = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Item, Target, Setting, OldValue, NewValue, Source, Credential, DetectedAt, SnapshotRef FROM OcuTalon_Data.SettingChange WHERE Namespace = ? AND Production = ? ORDER BY ID", ..#ORDERS, ..#ORDERSPRODUCTION)
	While rs.%Next() {
		If (setting '= "") && (rs.%GetData(3) '= setting) Continue
		Do changes.%Push({"item": (rs.%GetData(1)), "target": (rs.%GetData(2)), "setting": (rs.%GetData(3)), "oldValue": (rs.%GetData(4)), "newValue": (rs.%GetData(5)), "source": (rs.%GetData(6)), "credential": (+rs.%GetData(7)), "detectedAt": (rs.%GetData(8)), "snapshotRef": (rs.%GetData(9))})
	}
	Quit changes
}

/// Makes Orders watched (a fixture session's watch, due far ahead so that no Tick runs the row), so that SettingHistory visits it.
Method Watched() [ Private ]
{
	Do ..Watch(..Session("history"))
}

Method TestMeasuredCounter()
{
	If '..Ready() Quit
	Set before = ..Counter()
	Do $$$AssertStatusOK($ClassMethod(..#DEFINITION, "Put", 1, "zzSentinelA", "", "Credentials,ApiKey"), "settings are saved in the definition of the running Orders production")
	Set saved = ..Counter()
	Do $$$AssertTrue(saved > before, "saving the definition moves the counter ("_before_" to "_saved_")")
	Do $$$AssertStatusOK(..SaveDefault(..#SDSVALUE), "a System Default Setting row for an item of Orders is saved")
	Set defaulted = ..Counter()
	Do $$$AssertTrue(defaulted > saved, "saving the System Default Setting moves it ("_saved_" to "_defaulted_")")
	Set outcome = ##class(OcuTalon.Watch.Reader).Settings(..#ORDERS, ..#ORDERSPRODUCTION, 1, , .marks, .settings)
	Do $$$AssertEquals(outcome, "read", "Reader.Settings reads Orders")
	Do $$$AssertEquals(..Counter(), defaulted, "reading every setting does not move the counter")
	Do $$$AssertEquals(marks.counter, defaulted, "the counter mark is the counter")
	Do $$$AssertTrue($Length(marks.started, "|") = 2, "the start mark is a start time and a check sum: "_marks.started)
	Do $$$AssertTrue(settings.%Size() > 0, "settings were read")
	Do $$$AssertEquals(..VirtualListed(..#DEFINEDITEM, "TargetConfigName"), 1, "PopulateVirtualSettings lists a class setting of the item")
	Do $$$AssertEquals(..VirtualListed(..#DEFINEDITEM, "ApiKey"), 0, "it does not list a stored setting that the class does not have")
	Do $$$AssertEquals(..VirtualListed(..#DEFINEDITEM, "Credentials"), 0, "nor the stored Credentials setting")
	Set iterator = settings.%GetIterator()
	Set stored = 0
	While iterator.%GetNext(, .entry) {
		If (entry.item = ..#DEFINEDITEM) && (entry.setting = "Credentials") && (entry.value = "zzSentinelA") Set stored = 1
	}
	Do $$$AssertEquals(stored, 1, "so Reader.Settings adds the stored settings to the listed ones")
}

Method TestCounterUnchanged()
{
	If '..Ready() Quit
	Do ..Watched()
	Set first = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Tick(first)
	Do $$$AssertEquals(..Snapshots(), 1, "the first Tick takes the production's first snapshot")
	Set snapshot = ..Newest()
	If '$IsObject(snapshot) Quit
	Set checkedAt = snapshot.CheckedAt
	Set text = snapshot.Settings.Read(100000000)
	Do snapshot.Settings.Clear()
	Do snapshot.Settings.Write("[]")
	Do $$$AssertStatusOK(snapshot.%Save(), "the stored settings are replaced by an empty list, so that a read of the settings would show")
	Do ..Tick(##class(OcuTalon.Data.Time).AddSeconds(first, 30))
	Set again = ..Newest()
	Do $$$AssertEquals(again.CheckedAt, checkedAt, "with the counter and the start mark as they were and the check under an hour old, CheckedAt is as it was")
	Do $$$AssertEquals(again.Settings.Read(100000000), "[]", "no settings were read or kept")
	Do $$$AssertEquals(..Snapshots()_"|"_..Changes().%Size(), "1|0", "and no row was written")
	Do again.Settings.Clear()
	Do again.Settings.Write(text)
	Do $$$AssertStatusOK(again.%Save(), "the stored settings are put back")
	Set later = ##class(OcuTalon.Data.Time).AddSeconds(checkedAt, ##class(OcuTalon.Watch.SettingHistory).#SAFETYSECONDS)
	Do ..Tick(later)
	Set net = ..Newest()
	Do $$$AssertEquals(net.CheckedAt, later, "an hour after the last check, the settings are checked again")
	Do $$$AssertEquals(..Snapshots()_"|"_..Changes().%Size(), "1|0", "and settings that are the same only refresh the marks: no new snapshot and no change")
	Do $$$AssertEquals(net.Settings.Read(100000000), text, "the snapshot keeps its content")
}

Method TestChangesRecorded()
{
	If '..Ready() Quit
	Do ..Watched()
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(..Snapshots(), 1, "the production's first snapshot is taken")
	Do $$$AssertEquals(..Changes().%Size(), 0, "and a first snapshot has no SettingChange")
	Set interval = ##class(OcuTalon.Checks.Process).#INTERVALSECONDS
	Set sdsBefore = ..Entry(..Newest(), ..#ITEMNAME, ..#SDSSETTING)
	Do $$$AssertTrue($IsObject(sdsBefore), "the snapshot holds the class setting that a System Default Setting will override")
	If $IsObject(sdsBefore) Do $$$AssertEquals(sdsBefore.source, "class", "a class setting that nothing sets has the source class")
	Set target = ..Entry(..Newest(), ..#DEFINEDITEM, "TargetConfigName")
	Do $$$AssertTrue($IsObject(target), "the snapshot holds a class setting that the production definition sets")
	If $IsObject(target) Do $$$AssertEquals(target.value_"|"_target.source, ..#ITEMNAME_"|production", "with the definition's value and the source production")
	Set from = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK($ClassMethod(..#DEFINITION, "Put", 1, "", "first value", ..#NOTE), "a setting is saved in the definition of an item")
	Set savedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Tick(savedAt)
	Set note = ..Changes(..#NOTE)
	Do $$$AssertEquals(note.%Size(), 1, "the next Tick records one change for it")
	Do $$$AssertEquals(..Changes().%Size(), 1, "and no other")
	If note.%Size() = 1 {
		Set row = note.%Get(0)
		Do $$$AssertEquals(row.item_"|"_row.target_"|"_row.setting_"|"_row.oldValue_"|"_row.newValue_"|"_row.source_"|"_row.credential, ..#DEFINEDITEM_"|Host|"_..#NOTE_"||first value|production|0", "it names the item, the target, the setting, both values and the source")
		Do $$$AssertTrue(##class(OcuTalon.Data.Time).AddSeconds(from, -interval) '] row.detectedAt, "it was detected by a Tick no earlier than the check interval before the change (a real Tick sent just before it may be the one that reads it)")
		Do $$$AssertTrue(row.detectedAt '] ##class(OcuTalon.Data.Time).AddSeconds(savedAt, interval), "and within the check interval of it: "_row.detectedAt)
	}
	Set from = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(..SaveDefault(..#SDSVALUE), "a System Default Setting that applies to an item is saved")
	Set savedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Tick(savedAt)
	Set default = ..Changes(..#SDSSETTING)
	Do $$$AssertEquals(default.%Size(), 1, "the next Tick records one change for it")
	Do $$$AssertEquals(..Changes().%Size(), 2, "and the total is the two changes")
	If default.%Size() = 1 {
		Set row = default.%Get(0)
		Do $$$AssertEquals(row.item_"|"_row.setting_"|"_row.oldValue_"|"_row.newValue_"|"_row.source_"|"_row.credential, ..#ITEMNAME_"|"_..#SDSSETTING_"|"_sdsBefore.value_"|"_..#SDSVALUE_"|default|0", "it is on the item it applies to, with the earlier value, the new one and the source default")
		Do $$$AssertEquals(row.target, sdsBefore.target, "and the target of the class setting")
		Do $$$AssertTrue(row.detectedAt '] ##class(OcuTalon.Data.Time).AddSeconds(savedAt, interval), "detected within the check interval: "_row.detectedAt)
	}
	Set text = ..Changes().%ToJSON()
	Do $$$AssertTrue($Username '= "", "a user is signed in")
	Do $$$AssertEquals($Find(text, $Username), 0, "no change row names the user "_$Username)
	Do $$$AssertEquals(..PropertyNames("OcuTalon.Data.SettingChange"), "Credential,DetectedAt,Item,Namespace,NewValue,OldValue,Production,Ref,Setting,SnapshotRef,Source,Target", "SettingChange has exactly the specified properties, none of which names a user")
	Do $$$AssertEquals(..PropertyNames("OcuTalon.Data.SettingSnapshot"), "CheckedAt,Counter,Namespace,Production,Ref,Settings,Started,TakenAt", "and so has SettingSnapshot")
}

/// The names of a class's own properties (those that do not start with a percent sign), sorted and comma-separated.
ClassMethod PropertyNames(class As %String) As %String
{
	Kill found
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledProperty WHERE parent = ?", class)
	While rs.%Next() {
		If $Extract(rs.%GetData(1)) '= "%" Set found(rs.%GetData(1)) = ""
	}
	Set names = ""
	Set name = ""
	For {
		Set name = $Order(found(name))
		Quit:name=""
		Set names = names_$Select(names = "": "", 1: ",")_name
	}
	Quit names
}

Method TestRestartAndCounterGone()
{
	If '..Ready() Quit
	Do ..Watched()
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(..Snapshots(), 1, "the first Tick takes the production's first snapshot")
	Set snapshot = ..Newest()
	If '$IsObject(snapshot) Quit
	Set started = snapshot.Started
	Do $$$AssertTrue($Length(started, "|") = 2, "which holds the start mark: "_started)
	// a restart that came with a setting changed while the production was stopped: another start mark, the counter as it was, an earlier value in the snapshot
	Set list = ##class(%Library.DynamicAbstractObject).%FromJSON(snapshot.Settings)
	Set iterator = list.%GetIterator()
	Set picked = ""
	While iterator.%GetNext(, .entry) {
		If (entry.item = ..#DEFINEDITEM) && (entry.setting = "TargetConfigName") && 'entry.credential Set picked = entry.value Do entry.%Set("value", "zz-before-the-restart") Quit
	}
	Do $$$AssertTrue(picked '= "", "the snapshot holds a class setting of the item to give an earlier value: "_picked)
	Do snapshot.Settings.Clear()
	Do snapshot.Settings.Write(list.%ToJSON())
	Set snapshot.Started = "zz-before|1"
	Do $$$AssertStatusOK(snapshot.%Save(), "the newest snapshot is made to look as it did before a restart")
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set changes = ..Changes("TargetConfigName")
	Do $$$AssertEquals(changes.%Size(), 1, "a start mark that differs is read: the setting that differs is one change")
	If changes.%Size() = 1 {
		Set row = changes.%Get(0)
		Do $$$AssertEquals(row.item_"|"_row.oldValue_"|"_row.newValue, ..#DEFINEDITEM_"|zz-before-the-restart|"_picked, "from the earlier value to the live one")
	}
	Set newest = ..Newest()
	Do $$$AssertEquals(..Snapshots()_"|"_newest.Started, "2|"_started, "in a new snapshot that holds the live start mark")
	// the counter is gone, as after an IRIS restart: the same settings, so only the marks and CheckedAt are refreshed
	Set checked = newest.CheckedAt
	Hang 1.1
	Set counter = ..Counter()
	Do $$$AssertTrue(counter '= "", "the live counter is there to be taken away: "_counter)
	Set ..TakenCounter = counter
	Kill ^IRIS.Temp.EnsProdModCounter(..#ORDERS)
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set after = ..Newest()
	If counter '= "" Set ^IRIS.Temp.EnsProdModCounter(..#ORDERS) = counter
	Set ..TakenCounter = ""
	Do $$$AssertEquals(after.Counter, "", "the missing counter is read, as a value of its own")
	Do $$$AssertTrue(after.CheckedAt ] checked, "the settings were checked again: CheckedAt moved from "_checked_" to "_after.CheckedAt)
	Do $$$AssertEquals(..Snapshots()_"|"_..Changes().%Size(), "2|1", "and settings that are the same wrote no snapshot and no change")
}

Method TestSnapshotChangesNothing()
{
	If '..Ready() Quit
	Do ..Watched()
	Set counter = ..Counter()
	Set definition = $ClassMethod(..#DEFINITION, "Defined")
	Set stored = ..Fingerprint()
	Do $$$AssertTrue(stored '= 0, "the checksum covers stored data")
	Set first = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Tick(first)
	Do $$$AssertEquals(..Snapshots(), 1, "a snapshot is taken")
	Do $$$AssertEquals(..Counter(), counter, "the counter has not moved")
	Do $$$AssertEquals($ClassMethod(..#DEFINITION, "Defined"), definition, "the settings of the item in the saved definition are as they were")
	Do $$$AssertEquals(..Fingerprint(), stored, "and what Interoperability stores for the production, its items and the System Default Settings is as it was")
	Do ..Tick(##class(OcuTalon.Data.Time).AddSeconds(first, ##class(OcuTalon.Watch.SettingHistory).#SAFETYSECONDS))
	Do $$$AssertEquals(..Counter()_"|"_..Fingerprint(), counter_"|"_stored, "also after the hourly check")
}

Method TestCredentialsReference()
{
	If '..Ready() Quit
	Do $$$AssertStatusOK($ClassMethod(..#DEFINITION, "Put", 1, "ZzCredA", "", "Credentials"), "the item's Credentials setting holds the ID ZzCredA")
	Do ..Watched()
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set entry = ..Entry(..Newest(), ..#DEFINEDITEM, "Credentials")
	Do $$$AssertTrue($IsObject(entry), "the first snapshot holds the setting")
	If $IsObject(entry) Do $$$AssertEquals(entry.value_"|"_entry.credential_"|"_entry.hash, "ZzCredA|0|", "with its ID as the value, not marked as a secret, and no hash")
	Do $$$AssertStatusOK($ClassMethod(..#DEFINITION, "Put", 1, "ZzCredB", "", "Credentials"), "it is changed to ZzCredB")
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set changes = ..Changes()
	Do $$$AssertEquals(changes.%Size(), 1, "one change is recorded")
	If changes.%Size() = 1 {
		Set row = changes.%Get(0)
		Do $$$AssertEquals(row.setting_"|"_row.oldValue_"|"_row.newValue_"|"_row.credential, "Credentials|ZzCredA|ZzCredB|0", "with the old and the new ID and Credential 0")
	}
}

Method TestSecretValue()
{
	If '..Ready() Quit
	Set first = "zz-secret-one-"_$Random(1000000000)
	Set second = "zz-secret-two-"_$Random(1000000000)
	Do $$$AssertStatusOK($ClassMethod(..#DEFINITION, "Put", 1, first, "", "ApiKey"), "the item's ApiKey setting holds a secret")
	Do ..Watched()
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set entry = ..Entry(..Newest(), ..#DEFINEDITEM, "ApiKey")
	Do $$$AssertTrue($IsObject(entry), "the first snapshot holds the setting")
	If $IsObject(entry) {
		Do $$$AssertEquals(entry.value_"|"_entry.credential, "|1", "with no value and marked as a secret")
		Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).Matches(entry.hash, first), "and a hash that matches the secret")
		Set hash = entry.hash
	}
	Do $$$AssertStatusOK($ClassMethod(..#DEFINITION, "Put", 1, second, "", "ApiKey"), "the secret is changed")
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set changes = ..Changes()
	Do $$$AssertEquals(changes.%Size(), 1, "one change is recorded")
	If changes.%Size() = 1 {
		Set row = changes.%Get(0)
		Do $$$AssertEquals(row.setting_"|"_row.oldValue_"|"_row.newValue_"|"_row.credential, "ApiKey|||1", "with both values blank and Credential 1")
	}
	Set entry = ..Entry(..Newest(), ..#DEFINEDITEM, "ApiKey")
	If $IsObject(entry) {
		Do $$$AssertEquals(entry.value, "", "the new snapshot holds no value")
		Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).Matches(entry.hash, second), "its hash matches the new secret")
		Do $$$AssertNotTrue(##class(OcuTalon.Data.Webhook).Matches(entry.hash, first), "and not the old one")
		Set kept = entry.hash
	}
	Do ..Tick(##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), ##class(OcuTalon.Watch.SettingHistory).#SAFETYSECONDS))
	Do $$$AssertEquals(..Changes().%Size(), 1, "the same secret read again is no change")
	Do $$$AssertEquals(..Entry(..Newest(), ..#DEFINEDITEM, "ApiKey").hash, $Get(kept), "and its hash keeps the salt it had")
	Set newest = ..Newest()
	Do $$$AssertEquals(newest.Settings.Read(100000000) [ first, 0, "neither secret is in the stored settings")
	Do $$$AssertEquals(newest.Settings.Read(100000000) [ second, 0, "not the second either")
}

Method TestSameNameItems()
{
	If '..Ready() Quit
	Do $$$AssertStatusOK($ClassMethod(..#DEFINITION, "Put", 1, "", "enabled value", ..#NOTE), "the enabled item has a stored setting")
	Do $$$AssertStatusOK(..AddItem(..#DEFINEDITEM, 0, 1, [{"target": "Host", "name": (..#NOTE), "value": "disabled first"}]), "a disabled copy of it comes first in the definition")
	Do $$$AssertStatusOK(..AddItem(..#DEFINEDITEM, 0, 0, [{"target": "Host", "name": (..#NOTE), "value": "disabled last"}]), "and another comes last")
	Do $$$AssertStatusOK(..AddItem("ZzSameName", 0, 0, [{"target": "Host", "name": (..#NOTE), "value": "zz-first"}]), "two disabled items share another name")
	Do $$$AssertStatusOK(..AddItem("ZzSameName", 0, 0, [{"target": "Host", "name": (..#NOTE), "value": "zz-second"}]), "and neither is enabled")
	Do ..Watched()
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set entry = ..Entry(..Newest(), ..#DEFINEDITEM, ..#NOTE)
	Do $$$AssertTrue($IsObject(entry), "the first snapshot holds the setting of the item")
	If $IsObject(entry) Do $$$AssertEquals(entry.value, "enabled value", "its value is the enabled item's, not that of a disabled copy before it or after it")
	Set other = ..Entry(..Newest(), "ZzSameName", ..#NOTE)
	Do $$$AssertTrue($IsObject(other), "the snapshot holds the setting of the name that has no enabled item")
	If $IsObject(other) Do $$$AssertEquals(other.value, "zz-first", "its value is the first item's")
	Do $$$AssertEquals(..Changes().%Size(), 0, "a first snapshot has no change")
	Set marked = ..Newest().Counter
	Do $$$AssertStatusOK(..ChangeStored(..#DEFINEDITEM, 0, "Host", ..#NOTE, "disabled changed"), "the disabled copies are changed")
	Do $$$AssertTrue(..Counter() '= marked, "and the production-change counter moved")
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(..Newest().Counter, ..Counter(), "the Tick read the settings again: the snapshot holds the new counter")
	Do $$$AssertEquals(..Changes().%Size(), 0, "that is no change")
	Do $$$AssertStatusOK(..ChangeStored(..#DEFINEDITEM, 1, "Host", ..#NOTE, "enabled changed"), "the enabled item is changed")
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set changes = ..Changes(..#NOTE)
	Do $$$AssertEquals(changes.%Size()_"|"_..Changes().%Size(), "1|1", "that is one change")
	If changes.%Size() = 1 {
		Set row = changes.%Get(0)
		Do $$$AssertEquals(row.item_"|"_row.oldValue_"|"_row.newValue_"|"_row.source, ..#DEFINEDITEM_"|enabled value|enabled changed|production", "from the enabled item's earlier value to its new one")
	}
}

Method TestClassSettings()
{
	If '..Ready() Quit
	Set item = "ZzHttpProbe"
	Set proxyA = "ZzProxyA"
	Set proxyB = "ZzProxyB"
	Set secretA = "zz-cookie-one-"_$Random(1000000000)
	Set secretB = "zz-cookie-two-"_$Random(1000000000)
	Do $$$AssertStatusOK(..AddItem(item, 0, 0, [{"target": "Adapter", "name": "ProxyAuthorization", "value": (proxyA)}, {"target": "Adapter", "name": "UseCookies", "value": (secretA)}], ..#PROBECLASS), "an item whose adapter has a credentialsSelector setting and a secret-looking class setting is saved")
	Do ..Watched()
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set reference = ..Entry(..Newest(), item, "ProxyAuthorization")
	Set secret = ..Entry(..Newest(), item, "UseCookies")
	Do $$$AssertTrue($IsObject(reference) && $IsObject(secret), "the first snapshot holds both class settings")
	If '$IsObject(reference) || '$IsObject(secret) Quit
	Do $$$AssertEquals(reference.target_"|"_reference.value_"|"_reference.credential_"|"_reference.hash, "Adapter|"_proxyA_"|0|", "the class setting that references a credential keeps its ID, with credential 0 and no hash")
	Do $$$AssertEquals(secret.target_"|"_secret.value_"|"_secret.credential, "Adapter||1", "the class setting whose name looks like a secret has no value and credential 1")
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).Matches(secret.hash, secretA), "and a hash that matches its value")
	Set hash = secret.hash
	Do $$$AssertStatusOK(..ChangeStored(item, 0, "Adapter", "ProxyAuthorization", proxyB), "the reference is changed")
	Do $$$AssertStatusOK(..ChangeStored(item, 0, "Adapter", "UseCookies", secretB), "and so is the secret")
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set proxy = ..Changes("ProxyAuthorization")
	Set cookies = ..Changes("UseCookies")
	Do $$$AssertEquals(proxy.%Size()_"|"_cookies.%Size()_"|"_..Changes().%Size(), "1|1|2", "each is one change")
	If proxy.%Size() = 1 {
		Set row = proxy.%Get(0)
		Do $$$AssertEquals(row.item_"|"_row.target_"|"_row.oldValue_"|"_row.newValue_"|"_row.credential, item_"|Adapter|"_proxyA_"|"_proxyB_"|0", "the reference's change holds the old and the new ID and Credential 0")
	}
	If cookies.%Size() = 1 {
		Set row = cookies.%Get(0)
		Do $$$AssertEquals(row.item_"|"_row.target_"|"_row.oldValue_"|"_row.newValue_"|"_row.credential, item_"|Adapter|||1", "the secret's change holds both values blank and Credential 1")
	}
	Set newest = ..Newest()
	Set stored = newest.Settings.Read(100000000)
	Set text = ..Changes().%ToJSON()
	Do $$$AssertEquals(stored [ secretA, 0, "neither secret is in the stored settings")
	Do $$$AssertEquals(stored [ secretB, 0, "not the second either")
	Do $$$AssertEquals(text [ secretA, 0, "neither is in a change row")
	Do $$$AssertEquals(text [ secretB, 0, "not the second either")
	Do $$$AssertEquals(text [ hash, 0, "and the earlier hash is not in a change row")
	Set entry = ..Entry(newest, item, "UseCookies")
	If $IsObject(entry) {
		Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).Matches(entry.hash, secretB), "the new hash matches the new secret")
		Do $$$AssertEquals(text [ entry.hash, 0, "and it is not in a change row either")
	}
}

Method TestSkippedReads()
{
	If '..Ready() Quit
	Set session = ..Session("history")
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(session, "ZZNS", "Zz.Unreadable")
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(session, ..#ORDERS, "Zz.NotCurrent")
	Set unreadable = ##class(OcuTalon.Watch.Reader).Settings("ZZNS", "Zz.Unreadable", 1, , .marks, .settings)
	Do $$$AssertEquals(unreadable_"|"_marks.counter_"|"_marks.started_"|"_settings.%Size(), "unreadable|||0", "a namespace that the service user cannot read is unreadable, with no marks and no settings")
	Set other = ##class(OcuTalon.Watch.Reader).Settings(..#ORDERS, "Zz.NotCurrent", 1, , .marks, .settings)
	Do $$$AssertEquals(other_"|"_marks.counter_"|"_marks.started_"|"_settings.%Size(), "not_current|||0", "a production that is not the namespace's own is not_current, with no marks and no settings")
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SettingSnapshot WHERE (Namespace = 'ZZNS' AND Production = 'Zz.Unreadable') OR (Namespace = ? AND Production = 'Zz.NotCurrent')", ..#ORDERS)
	Do rs.%Next()
	Do $$$AssertEquals(+rs.%GetData(1), 0, "a Tick writes no snapshot for either")
	Set start = $Parameter("OcuTalon.Watch.SettingHistory", "LOGPRODUCTION")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Watch", start_"Zz."), 0, "and logs no warning")
}

Method TestReadFailure()
{
	If '..Ready() Quit
	Do ..Watched()
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(..Snapshots(), 1, "the first Tick takes the Orders snapshot")
	Set broken = "zz-not-json-"_$Random(1000000000)
	Set snapshot = ..Newest()
	Do snapshot.Settings.Clear()
	Do snapshot.Settings.Write(broken)
	Set snapshot.Counter = "zz-moved"
	Do $$$AssertStatusOK(snapshot.%Save(), "the Orders snapshot is made unreadable and due")
	Set follower = $ZConvert(..#ORDERS, "L")
	Set ..Other = follower
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(..Session("history"), follower, ..#ORDERSPRODUCTION)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set start = $Parameter("OcuTalon.Watch.SettingHistory", "LOGPRODUCTION")_..#ORDERSPRODUCTION_" in "_..#ORDERS_": "
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Watch", start)
	Do $$$AssertTrue(warned '< 1, "a read that throws logs a warning for that production, one for each Tick that reads it (a real Tick may also run): "_warned)
	Set kept = ..Newest()
	Do $$$AssertEquals(..Snapshots()_"|"_kept.Settings.Read(100000000)_"|"_..Changes().%Size(), "1|"_broken_"|0", "and writes nothing")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SettingSnapshot WHERE Namespace = ? AND Production = ?", follower, ..#ORDERSPRODUCTION)
	Do rs.%Next()
	Do $$$AssertEquals(+rs.%GetData(1), 1, "while the production that follows it (the same production, named by the namespace's lower-case spelling) is snapshotted")
}

Method TestOnlineDemoOff()
{
	If '..Ready() Quit
	Do ..SetOnlineDemo(1)
	Do ..Watched()
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(..Snapshots()_"|"_..Changes().%Size(), "0|0", "with onlineDemo on, a Tick takes no snapshot and writes no change")
	Do ..SetOnlineDemo(0)
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(..Snapshots(), 1, "with it off, the same Tick takes the snapshot")
}

}
