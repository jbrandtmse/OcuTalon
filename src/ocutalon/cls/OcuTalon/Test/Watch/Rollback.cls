Include Ensemble

/// Tests of the setting rollback and its undo over the running Orders production (Story 23.3; AD-3, AD-15, AD-16, AD-24). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh
/// (FixExecutor is code of the running production), with demo mode on, through Test.Watch.Case: they need the running OcuTalon.Production and the Orders demo production in OCUORDERS. The
/// setting that they change is the stored Host setting ZzFixtureNote of the failing item OrdersFromPartner (Test.Watch.OrdersDefinition), changed through the saved definition
/// and recorded by the Tick of Checks; the definition is put back after each test.
///   - TestMeasured (Task 0, a hard gate): FixExecutor's own job carries out an approved rollback_setting through Fix.Executor.InProduction, which sets the stored setting in the saved
///     definition and calls Ens.Director.UpdateProduction in OCUORDERS; every other item of OCUORDERS keeps its job. The figures are logged and printed as SKIP lines (a status 2
///     never fails a class).
Class OcuTalon.Test.Watch.Rollback Extends OcuTalon.Test.Watch.Case [ DependsOn = OcuTalon.Test.Watch.OrdersDefinition ]
{

Parameter DEFINITION = "OcuTalon.Test.Watch.OrdersDefinition";

Parameter NOTE = {##class(OcuTalon.Test.Watch.OrdersDefinition).#NOTE};

/// The failing item of the fixture incident.
Parameter FAILING = {##class(OcuTalon.Test.Watch.OrdersDefinition).#ITEM};

Parameter SDSSETTING = "RetryInterval";

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do ..DropHistory()
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Set sc = $SYSTEM.Status.AppendStatus(sc, $ClassMethod(..#DEFINITION, "Put", 0))
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..DropDefault())
	Do ..DropHistory()
	Quit sc
}

/// Deletes the history rows of the Orders production.
ClassMethod DropHistory()
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SettingChange WHERE Namespace = ? AND Production = ?", ..#ORDERS, ..#ORDERSPRODUCTION)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SettingSnapshot WHERE Namespace = ? AND Production = ?", ..#ORDERS, ..#ORDERSPRODUCTION)
}

/// Saves a System Default Setting row of the setting for the item in the Orders production, through the class.
ClassMethod SaveDefault(item As %String, setting As %String, value As %String) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set row = ##class(Ens.Config.DefaultSettings).%New()
	Set row.ProductionName = ..#ORDERSPRODUCTION
	Set row.ItemName = item
	Set row.HostClassName = "*"
	Set row.SettingName = setting
	Set row.SettingValue = value
	Quit row.%Save()
}

/// Removes the System Default Setting row of the setting for the item; OK when it is not there.
ClassMethod DropDefault() As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set sc = $$$OK
	For item = ..#FAILING {
		Set id = ..#ORDERSPRODUCTION_"||"_item_"||*||"_..#SDSSETTING
		If ##class(Ens.Config.DefaultSettings).%ExistsId(id) Set sc = ##class(Ens.Config.DefaultSettings).%DeleteId(id)
	}
	Quit sc
}

/// The time stamp of the class definition of the Orders production class, in OCUORDERS.
ClassMethod ClassTime() As %String
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set class = ##class(%Dictionary.ClassDefinition).%OpenId(..#ORDERSPRODUCTION)
	Quit $Select($IsObject(class): class.TimeChanged, 1: "<no class>")
}

/// The production-change counter of OCUORDERS, "" when it has none.
ClassMethod Counter() As %String
{
	Quit $Get(^IRIS.Temp.EnsProdModCounter(..#ORDERS))
}

/// The effective value of the setting of the item in the running Orders production's definition, read with Ens.Director.GetItemSettingValue in OCUORDERS.
ClassMethod Effective(item As %String, target As %String, setting As %String) As %String
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set value = ##class(Ens.Director).GetItemSettingValue(..#ORDERSPRODUCTION_"||"_item, target, setting, .sc)
	Quit $Select($$$ISOK(sc): value, 1: "<"_$SYSTEM.Status.GetOneErrorText(sc)_">")
}

/// The stored settings of the item in the saved definition, as "target:name=value" joined by "|", in list order.
ClassMethod Stored(item As %String) As %String
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set production = ##class(Ens.Config.Production).%OpenId(..#ORDERSPRODUCTION)
	If '$IsObject(production) Quit "<no definition>"
	Set text = ""
	For i = 1:1:production.Items.Count() {
		Set each = production.Items.GetAt(i)
		If each.Name '= item Continue
		For j = 1:1:each.Settings.Count() {
			Set setting = each.Settings.GetAt(j)
			Set text = text_$Select(text = "": "", 1: "|")_setting.Target_":"_setting.Name_"="_setting.Value
		}
		Quit
	}
	Quit text
}

/// The running jobs of the Orders production as "item=job@registered" joined by ";", sorted by item, read in OCUORDERS.
ClassMethod Jobs() As %String
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Kill found
	Set job = ""
	For {
		Set job = $Order($$$EnsJobStatus($$$SystemName, job))
		If job = "" Quit
		Set name = $Get($$$EnsJobStatus($$$SystemName, job, $$$eJobStartConfigName))
		If name = "" Continue
		Set found(name_"|"_job) = job_"@"_$Get($$$EnsJobStatus($$$SystemName, job, $$$eJobRegTime))
	}
	Set text = ""
	Set key = ""
	For {
		Set key = $Order(found(key), 1, value)
		If key = "" Quit
		Set text = text_$Select(text = "": "", 1: ";")_$Piece(key, "|", 1)_"="_value
	}
	Quit text
}

/// The entries of a Jobs text that are not the failing item's, joined by ";".
ClassMethod OtherJobs(jobs As %String) As %String
{
	Set text = ""
	For i = 1:1:$Length(jobs, ";") {
		Set one = $Piece(jobs, ";", i)
		If (one = "") || ($Piece(one, "=", 1) = ..#FAILING) Continue
		Set text = text_$Select(text = "": "", 1: ";")_one
	}
	Quit text
}

/// The log rows of OCUORDERS after the floor as "config: text" joined by " / ", the text cut to 80 characters.
ClassMethod LogSince(floor As %Integer) As %String
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ConfigName, Text FROM Ens_Util.Log WHERE ID > ? ORDER BY ID", floor)
	Set text = ""
	While rs.%Next() {
		Set text = text_$Select(text = "": "", 1: " / ")_rs.%GetData(1)_": "_$Extract(rs.%GetData(2), 1, 80)
	}
	Quit text
}

/// The change rows of the setting of the Orders production, oldest first, as a dynamic array of {"ref", "item", "target", "setting", "oldValue", "newValue", "source", "detectedAt"}.
ClassMethod ChangeRows(setting As %String) As %DynamicArray
{
	Set rows = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref, Item, Target, Setting, OldValue, NewValue, Source, DetectedAt FROM OcuTalon_Data.SettingChange WHERE Namespace = ? AND Production = ? AND Setting = ? ORDER BY ID", ..#ORDERS, ..#ORDERSPRODUCTION, setting)
	While rs.%Next() {
		Do rows.%Push({"ref": (rs.%GetData(1)), "item": (rs.%GetData(2)), "target": (rs.%GetData(3)), "setting": (rs.%GetData(4)), "oldValue": (rs.%GetData(5)), "newValue": (rs.%GetData(6)), "source": (rs.%GetData(7)), "detectedAt": (rs.%GetData(8))})
	}
	Quit rows
}

/// Makes a measured value visible in the output of a run that passes: a log message, and an assert of the status skipped, which ci/iris.sh prints as "SKIP <method>: <text>".
Method Timing(text As %String) [ Private ]
{
	Do $$$LogMessage(text)
	Do ..Manager.LogAssert(2, "Timing", text)
}

/// A fix request of the owner for the incident in the state (approved by default), with the parameters, targets and dry run given; its Ref.
Method Request(owner As %String, incident As %String, kind As %String, parameters As %String, targets As %String, dryRun As %String, state As %String = "approved") As %String [ Private ]
{
	Set fields = {"FixKind": (kind), "FixTargets": (targets), "FixParameters": (parameters), "DryRun": (dryRun), "ResultTarget": "IncidentManager", "AnsweredChannel": "web", "AnsweredAt": "2030-01-01T10:00:00Z"}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, state, , fields)
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ ref
	Quit ref
}

/// Records the setting change old -> new of the stored setting of the failing item through the saved definition and two Ticks, then makes a fixture incident that fails at the item
/// just after it: the change's Ref, or "" when it was not recorded. The incident's Ref is in incident.
Method Change(session As %String, target As %String, old As %String, new As %String, Output incident As %String, fixture As %Boolean = 1) As %String [ Private ]
{
	Set incident = ""
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).ChangeStored(..#FAILING, 1, target, ..#NOTE, old), "the stored "_target_" setting is "_old)
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Hang 1
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).ChangeStored(..#FAILING, 1, target, ..#NOTE, new), "and then "_new)
	Set tickAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Tick(tickAt)
	Set rows = ..ChangeRows(..#NOTE)
	Do $$$AssertTrue(rows.%Size() '< 1, "a change is recorded")
	If rows.%Size() = 0 Quit ""
	Set row = rows.%Get(rows.%Size() - 1)
	Do $$$AssertEquals(row.item_"|"_row.target_"|"_row.oldValue_"|"_row.newValue_"|"_row.source, ..#FAILING_"|"_target_"|"_old_"|"_new_"|production", "the newest change is the one that was made")
	If 'fixture Quit row.ref
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set made = ..Fixture(session, "1", ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (now), "FirstAt": (##class(OcuTalon.Data.Time).AddSeconds(row.detectedAt, 120)), "LastAt": (##class(OcuTalon.Data.Time).AddSeconds(row.detectedAt, 125))})
	Set incident = made.Ref
	Quit row.ref
}

/// The first snapshot of a watched Orders production: the session of the fixture watch and its trace Ref, "" when the snapshot was not taken.
Method Prepare(Output trace As %String) As %String [ Private ]
{
	Set a = ..Session("rollback")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..Watch(a)
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(##class(OcuTalon.Test.Watch.SettingHistory).Snapshots(), 1, "the first snapshot is taken")
	Quit a
}

/// Task 0 (the hard gate), a Host setting: see the class description.
Method TestMeasured()
{
	If '..Ready() Quit
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser")
	Do $$$AssertEquals(''$SYSTEM.Security.CheckUserPermission(user, "%Ens_ProductionConfig", "W"), 1, "the service user "_user_" holds %Ens_ProductionConfig:W after the Fix step on a local install")
	Do $$$AssertEquals(''$SYSTEM.Security.CheckUserPermission(user, "%Ens_ProductionConfig", "R"), 0, "and not Read on it")
	Set a = ..Prepare(.trace)
	Do ..Cycle(a, trace, "Host")
}

/// Task 0 (b), an Adapter setting: the same through the stored Adapter setting of the failing item (the Orders production has no item with an adapter, so the item's own
/// stored Adapter setting stands in; the executor treats both targets alike). It then removes a stored setting, so that the inherited value applies again.
Method TestMeasuredAdapter()
{
	If '..Ready() Quit
	Set a = ..Prepare(.trace)
	Do ..Cycle(a, trace, "Adapter")
}

/// Task 0 (b), removing a stored setting: a System Default Setting changes the setting of the failing item, the rollback writes the old value on the item, and the undo takes
/// the item's stored setting out again: the item's stored settings are as they were before the rollback, and the inherited value applies again.
Method TestMeasuredRemoval()
{
	If '..Ready() Quit
	Set a = ..Prepare(.trace)
	Set item = ..#FAILING
	Set setting = ..#SDSSETTING
	Set before = ..Effective(item, "Host", setting)
	Do ..Timing("Task 0 (b): the class value of "_setting_" on "_item_" is "_before)
	Set storedBefore = ..Stored(item)
	Do $$$AssertStatusOK(..SaveDefault(item, setting, 7), "a System Default Setting row gives "_setting_" the value 7")
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set rows = ..ChangeRows(setting)
	Do $$$AssertEquals(rows.%Size(), 1, "the Tick records one change for it")
	If rows.%Size() '= 1 Quit
	Set row = rows.%Get(0)
	Do $$$AssertEquals(row.item_"|"_row.oldValue_"|"_row.newValue_"|"_row.source, item_"|"_before_"|7|default", "from the class value to 7, with the source default")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set fixture = ..Fixture(a, "1", ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (now), "FirstAt": (##class(OcuTalon.Data.Time).AddSeconds(row.detectedAt, 120)), "LastAt": (##class(OcuTalon.Data.Time).AddSeconds(row.detectedAt, 125))})
	Set incident = fixture.Ref
	Do ..Run(a, trace, incident, "rollback_setting", row.ref, item, setting, "Host", "7", before)
	Do $$$AssertEquals(..Effective(item, "Host", setting), before, "the rollback put the old value back on the item")
	Do $$$AssertEquals(..Stored(item), storedBefore_"|Host:"_setting_"="_before, "as a stored setting of the item: "_..Stored(item))
	// the Tick records the rollback's own change, which the undo must not take for a later change of the setting
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set own = ..ChangeRows(setting)
	Do $$$AssertEquals(own.%Size(), 2, "the Tick recorded the rollback's own change")
	Do ..Run(a, trace, incident, "undo_rollback", row.ref, item, setting, "Host", before, "7")
	Do $$$AssertEquals(..Effective(item, "Host", setting), "7", "the undo made the inherited value apply again")
	Do $$$AssertEquals(..Stored(item), storedBefore, "and the item's stored settings are as they were before the rollback")
}

/// Task 0 (c): on an online-demo install the service role holds no %Ens_ProductionConfig:W once the Roles step has run again, and it holds it again after the flag is off.
Method TestMeasuredOnline()
{
	If '..Ready() Quit
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser")
	// the Roles step rewrites the role from the Grants of the areas only, so the role is put back as it was (the Demo step's read of OCUORDERS is not among them)
	Set ..RoleBefore = ..RoleResources()
	Set ..RoleSaved = 1
	Do ..SetOnlineDemo(1)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs again with onlineDemo 1")
	Do $$$AssertEquals(''$SYSTEM.Security.CheckUserPermission(user, "%Ens_ProductionConfig", "W"), 0, "the service user holds no %Ens_ProductionConfig:W")
	Do ..SetOnlineDemo(0)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs again with onlineDemo 0")
	Do $$$AssertEquals(''$SYSTEM.Security.CheckUserPermission(user, "%Ens_ProductionConfig", "W"), 1, "and the service user holds it again")
}

/// The change old to new of the stored setting of the target, recorded, then a rollback of it carried out by FixExecutor's job: the figures are logged.
Method Cycle(a As %String, trace As %String, target As %String) [ Private ]
{
	Set change = ..Change(a, target, "alpha", "beta", .incident)
	If change = "" Quit
	Set classBefore = ..ClassTime()
	Set counterBefore = ..Counter()
	Set storedBefore = ..Stored(..#FAILING)
	Set floor = ..Top("Ens_Util.Log", ..#ORDERS)
	Set jobsBefore = ..Jobs()
	Do $$$AssertEquals(..Effective(..#FAILING, target, ..#NOTE), "beta", "GetItemSettingValue gives the new value before the rollback")
	Set seconds = ..Run(a, trace, incident, "rollback_setting", change, ..#FAILING, ..#NOTE, target, "beta", "alpha", classBefore, counterBefore, storedBefore)
	Set counterAfter = ..Counter()
	Set jobsAfter = ..Jobs()
	Do $$$AssertEquals(..Effective(..#FAILING, target, ..#NOTE), "alpha", "GetItemSettingValue returns the old value after the rollback")
	Do $$$AssertEquals(..ClassTime(), classBefore, "the class definition of the Orders production is unchanged")
	Do $$$AssertEquals(..Stored(..#FAILING), $Replace(storedBefore, target_":"_..#NOTE_"=beta", target_":"_..#NOTE_"=alpha"), "only the stored setting of the failing item changed: "_..Stored(..#FAILING))
	Do $$$AssertTrue(counterAfter '= counterBefore, "the production-change counter moved ("_counterBefore_" to "_counterAfter_")")
	Set log = ..LogSince(floor)
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set rows = ..ChangeRows(..#NOTE)
	Do $$$AssertEquals(rows.%Size(), 3, "the next Tick records the rollback as one more change")
	If rows.%Size() = 3 {
		Set again = rows.%Get(2)
		Do $$$AssertEquals(again.oldValue_"|"_again.newValue_"|"_again.source, "beta|alpha|production", "beta to alpha, source production")
	}
	Do ..Timing("Task 0 ("_target_"): Execute of a rollback from FixExecutor's job: "_$FNumber(seconds, "", 3)_" s (SendExecute to the end of the handler)")
	Do ..Timing("Task 0 ("_target_"): OCUORDERS jobs before: "_jobsBefore)
	Do ..Timing("Task 0 ("_target_"): OCUORDERS jobs after:  "_jobsAfter)
	Do $$$AssertEquals(..OtherJobs(jobsAfter), ..OtherJobs(jobsBefore), "only the failing item restarted: every other item of OCUORDERS kept its job")
	Do ..Timing("Task 0 ("_target_"): OCUORDERS log after the run: "_log)
	Do $$$AssertEquals(..WaitIncidentState(incident, "resolved"), "resolved", "the incident is resolved")
	Set answer = ..AskDryRun(incident, "rollback_setting", {"change": (change)}.%ToJSON(), trace, .dry, .sc)
	Do $$$AssertTrue($IsObject(answer), "FixExecutor's own job survived and answers a dry run again")
}

/// Asks FixExecutor for the dry run of the kind for the change (its Ref), checks it, raises an approved request for it and has FixExecutor's job carry it out; the seconds
/// from the Execute to the end of its handler. before and after are the values of the dry run. The run's one Action entry in the audit log is read back: its action is the kind,
/// its target is "<setting> on <item> in <production> in <namespace>", its result is done, and it holds neither value. With classBefore, counterBefore and storedBefore given it
/// also checks that the dry run changed none of them.
Method Run(a As %String, trace As %String, incident As %String, kind As %String, change As %String, item As %String, setting As %String, target As %String, before As %String, after As %String, classBefore As %String = "", counterBefore As %String = "", storedBefore As %String = "") As %Numeric [ Private ]
{
	Set parameters = {"change": (change)}.%ToJSON()
	Set answer = ..AskDryRun(incident, kind, parameters, trace, .dry, .sc)
	Do $$$AssertTrue($IsObject(answer), "FixExecutor answers the "_kind_" dry run")
	If '$IsObject(answer) Quit 0
	Do $$$AssertEquals(answer.Reason, "", "without a reason")
	If answer.Reason '= "" Quit 0
	Set shown = {}.%FromJSON(answer.DryRun)
	Do $$$AssertEquals(shown.item_"|"_shown.field_"|"_shown.before_"|"_shown.after_"|"_shown.%GetTypeOf("before")_shown.%GetTypeOf("after"), item_"|"_setting_"|"_before_"|"_after_"|stringstring", "the dry run is the item, the setting, the current value and the value it will have, the values as strings: "_answer.DryRun)
	If classBefore '= "" Do $$$AssertEquals(..Counter()_"|"_..ClassTime()_"|"_..Stored(item)_"|"_..Effective(item, target, setting), counterBefore_"|"_classBefore_"|"_storedBefore_"|"_before, "the dry run changed nothing: the counter, the class, the stored settings and the value")
	Set request = ..Request(a, incident, kind, parameters, answer.Targets, answer.DryRun)
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.RequestRefs = $Select(row.RequestRefs = "": request, 1: row.RequestRefs_","_request)
	Do $$$AssertStatusOK(row.%Save(), "the incident names the request")
	Kill row
	Set auditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set start = $ZHorolog
	Do $$$AssertStatusOK(..SendExecute(request, .session), "the Execute is handled by FixExecutor's job and returns")
	Set seconds = $ZHorolog - start
	Set results = ..WaitFixResults(request, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.final_"|"_result.interrupted_"|"_result.total_"|"_result.resent_"|"_result.completed_"|"_result.failedAgain_"|"_result.skipped_"|"_result.unreached, "1|0|1|0|1|0|0|0", "it is final and holds Total 1, Resent 0, Completed 1: "_result.reason)
	}
	Do $$$AssertEquals(..WaitState(incident, request, "done"), "done", "the request is done")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(auditMark, "OcuTalon", "Action", "", request, "", 1, 20)
	Do $$$AssertEquals(entries.%Size(), 1, kind_": one Action entry names the request")
	If entries.%Size() = 1 {
		Set data = entries.%Get(0).data
		Do $$$AssertEquals(data.action_"|"_data.target_"|"_data.result, kind_"|"_setting_" on "_item_" in "_..#ORDERSPRODUCTION_" in "_..#ORDERS_"|done", kind_": the entry names the setting, the item, the production and the namespace")
		Set text = data.%ToJSON()
		For value = before, after {
			Set quoted = $Char(34)_value_$Char(34)
			If value '= "" Do $$$AssertEquals($Find(text, quoted), 0, kind_": the entry holds no value of the setting ("_value_")")
		}
	}
	Quit seconds
}


/// AC3 (changed again): the setting changes between the dry run and the approved run: the Recheck skips it with the CHANGEDAGAIN reason and nothing is written; the session reads
/// result.settingChangedSince. Then Fix.Executor InProduction itself, given a plan whose expected value is not the effective one, writes nothing and reports the skip.
Method TestChangedAgain()
{
	If '..Ready() Quit
	Set a = ..Prepare(.trace)
	Set change = ..Change(a, "Host", "alpha", "beta", .incident)
	If change = "" Quit
	Set parameters = {"change": (change)}.%ToJSON()
	Set answer = ..AskDryRun(incident, "rollback_setting", parameters, trace, .dry, .sc)
	Do $$$AssertTrue($IsObject(answer) && (answer.Reason = ""), "the dry run is made")
	If '$IsObject(answer) Quit
	Set request = ..Request(a, incident, "rollback_setting", parameters, answer.Targets, answer.DryRun)
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.RequestRefs = request
	Do $$$AssertStatusOK(row.%Save(), "the incident names the request")
	Kill row
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).ChangeStored(..#FAILING, 1, "Host", ..#NOTE, "gamma"), "the setting changes again before the run")
	Set counter = ..Counter()
	Set stored = ..Stored(..#FAILING)
	Do $$$AssertStatusOK(..SendExecute(request, .session), "the Execute is handled")
	Set results = ..WaitFixResults(request, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.total_"|"_result.resent_"|"_result.completed_"|"_result.skipped_"|"_result.reason, "1|0|0|1|"_##class(OcuTalon.Fix.Kind.RollbackSetting).ChangedAgain(..#NOTE, ..#FAILING), "Skipped 1, nothing changed, with the reason that names the setting")
	}
	Do $$$AssertEquals(..Counter()_"|"_..Stored(..#FAILING)_"|"_..Effective(..#FAILING, "Host", ..#NOTE), counter_"|"_stored_"|gamma", "nothing was written: the counter, the stored settings and the value are as they were")
	Set notes = ..WaitResultNotices(incident, 1)
	Do $$$AssertEquals(notes.%Size(), 1, "the session has one result Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.catalogKey, "result.settingChangedSince", "result.settingChangedSince")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc), ..#NOTE_" on "_..#FAILING_" was not changed: it changed again after the dry run. It needs a new approval.", "which says that it needs a new approval")
	}
	// InProduction reads the effective value again when it writes: a plan whose expected value is not the effective one writes nothing
	Set plan = [{"id": 1, "setting": (..#NOTE), "target": "Host", "item": (..#FAILING), "production": (..#ORDERSPRODUCTION), "expect": "not-the-value", "value": "alpha"}]
	Do ##class(OcuTalon.Fix.Executor).InProduction(..#ORDERS, plan, "", .done, .skipped, .unreached)
	Do $$$AssertEquals(done_"|"_skipped.%Size()_"|"_unreached.%Size(), "0|1|0", "InProduction does not write when the effective value is not the expected one")
	Do $$$AssertEquals(..Counter()_"|"_..Stored(..#FAILING), counter_"|"_stored, "and it changed nothing")
}

/// The Execute of a pending, rejected, expired or cancelled request of either kind writes nothing and makes no FixRun.
Method TestNoApprovedRow()
{
	If '..Ready() Quit
	Set a = ..Session("rollbacknorow")
	Set row = ..Fixture(a, "1")
	Set incident = row.Ref
	Kill row
	Set storedBefore = ..Stored(..#FAILING)
	Set counter = ..Counter()
	For kind = "rollback_setting", "undo_rollback" {
		For state = "pending", "rejected", "expired", "cancelled" {
			Set ref = ..Request(a, incident, kind, {"change": "zzchangeref0000000001"}.%ToJSON(), "1", {"item": (..#FAILING), "field": (..#NOTE), "before": "beta", "after": "alpha"}.%ToJSON(), state)
			Do $$$AssertStatusOK(..SendExecute(ref, .session), kind_" "_state_": the Execute is handled")
			Do $$$AssertEquals(..Counter()_"|"_..Stored(..#FAILING), counter_"|"_storedBefore, kind_" "_state_": nothing was written")
			Do $$$AssertEquals(..Runs(incident).%Size(), 0, kind_" "_state_": no FixRun is written")
		}
	}
}

/// AC5, AC7: with %Ens_ProductionConfig taken from the service role the run could not start: nothing is written, the request failed with NOTALLOWED and the session reads
/// result.itemNotChanged; an undo_rollback run fails the same way, with NOTALLOWED. The same for an online-demo install (the public flag on, no grant), where both kinds also refuse
/// their dry run with ONLINESHARED and the pack lists no change.
Method TestNotAllowedAndOnlineDemo()
{
	If '..Ready() Quit
	Set a = ..Prepare(.trace)
	Set change = ..Change(a, "Host", "alpha", "beta", .incident)
	If change = "" Quit
	Set parameters = {"change": (change)}.%ToJSON()
	Set answer = ..AskDryRun(incident, "rollback_setting", parameters, trace, .dry, .sc)
	Do $$$AssertTrue($IsObject(answer) && (answer.Reason = ""), "the dry run is made on a local install")
	If '$IsObject(answer) Quit
	Set counter = ..Counter()
	Set stored = ..Stored(..#FAILING)
	Set request = ..Request(a, incident, "rollback_setting", parameters, answer.Targets, answer.DryRun)
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.RequestRefs = request
	Do $$$AssertStatusOK(row.%Save(), "the incident names the request")
	Kill row
	// a pack on the online demo lists no change
	Do ..SetOnlineDemo(1)
	Set made = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set pack = {"firstAt": (made.FirstAt)}
	Do ##class(OcuTalon.Watch.SettingCause).AddTo(pack, made)
	Do $$$AssertEquals(pack.%IsDefined("settingChanges"), 0, "on the online demo the pack lists no setting change")
	For kind = "rollback_setting", "undo_rollback" {
		Set sc = $ClassMethod("OcuTalon.Fix.Kind."_$Select(kind = "rollback_setting": "RollbackSetting", 1: "UndoRollback"), "DryRun", made, {"change": (change)}, .targets, .dryRun)
		Do $$$AssertEquals($SYSTEM.Status.GetOneErrorText(sc), "ERROR #5001: "_##class(OcuTalon.Fix.Kind.RollbackSetting).#ONLINESHARED, kind_": the dry run is refused with ONLINESHARED on the online demo")
	}
	Kill made
	// with that check bypassed (the approved row goes to the executor with its dry run), the service role holds no grant there
	Do ..RevokeRole("%Ens_ProductionConfig")
	Do $$$AssertTrue(..RoleResources() '[ "%Ens_ProductionConfig", "the service role holds no %Ens_ProductionConfig, as on an online-demo install")
	Do $$$AssertStatusOK(..SendExecute(request, .session), "the Execute is handled")
	Do $$$AssertEquals(..WaitState(incident, request, "failed"), "failed", "the request failed")
	Set results = ..WaitFixResults(request, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.total_"|"_result.resent_"|"_result.completed_"|"_result.skipped_"|"_result.reason, "1|0|0|0|"_##class(OcuTalon.Fix.Kind.RollbackSetting).#NOTALLOWED, "Total 1, nothing changed, and the kind's reason")
	}
	Do $$$AssertEquals(..Counter()_"|"_..Stored(..#FAILING), counter_"|"_stored, "nothing was written")
	Set notes = ..WaitResultNotices(incident, 1)
	Do $$$AssertEquals(notes.%Size(), 1, "the session has one result Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc), "Nothing was changed: OcuTalon isn't allowed to change settings in that production.", "result.itemNotChanged says that nothing was changed, with the plain reason")
	}
	// the undo declares the same resource (inherited), and the executor checks it the same way
	Set undo = ..Request(a, incident, "undo_rollback", parameters, answer.Targets, answer.DryRun)
	Do $$$AssertStatusOK(..SendExecute(undo, .session), "the Execute of an undo is handled")
	Do $$$AssertEquals(..WaitState(incident, undo, "failed"), "failed", "the undo failed")
	Set undone = ..WaitFixResults(undo, 1)
	Do $$$AssertEquals(undone.%Size(), 1, "one FixResult for the undo")
	If undone.%Size() = 1 Do $$$AssertEquals(undone.%Get(0).completed_"|"_undone.%Get(0).reason, "0|"_##class(OcuTalon.Fix.Kind.RollbackSetting).#NOTALLOWED, "the undo changed nothing, with NOTALLOWED")
	Do $$$AssertEquals(..Counter()_"|"_..Stored(..#FAILING), counter_"|"_stored, "nothing was written by the undo either")
}

/// AC2, AC3, AC9 (integration): a real setting change in OCUORDERS and a diagnosis from the mock (the marker diagnosis-rollback) at the failing item: IncidentManager names the
/// change, the incident's notice is incident.rollbackRequest with the gap sentence, one rollback_setting request is raised with a dry run that changed nothing, and a second
/// session gets nothing.
Method TestIncidentNamesTheChange()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set a = ..Prepare(.trace)
	Set b = ..Session("rollbackother")
	// the second session watches the Orders production too, so that a request delivered to every watcher would reach it
	Do ..Watch(b)
	Set change = ..Change(a, "Host", "alpha", "beta", .unused, 0)
	If change = "" Quit
	Set counter = ..Counter()
	Set stored = ..Stored(..#FAILING)
	Set classBefore = ..ClassTime()
	Set at = ##class(OcuTalon.Test.Watch.Incidents).Stamp(0)
	Do $$$AssertStatusOK(..SendBatch(..#ORDERS, ..#ORDERSPRODUCTION, a, [{"item": (..#FAILING), "text": "[[mock:diagnosis-rollback]] The target is not configured", "at": (at)}]), "a failure at the failing item is sent")
	Set rows = ..WaitIncident(a, ..#ORDERSPRODUCTION, 1)
	Do $$$AssertEquals(rows.%Size(), 1, "one incident")
	If rows.%Size() '= 1 Quit
	Set incident = rows.%Get(0).ref
	Set ..ItemIds = ..ItemIds _ $ListBuild(incident)
	Do $$$AssertTrue(..WaitDiagnosed(incident), "it holds its diagnosis")
	Do $$$AssertTrue(..WaitRow(incident, "NoticedAt", "", ..#WAITINCIDENT) '= "", "and it is noticed")
	Do ..WaitNotices(incident, 1)
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.CauseCategory_"|"_row.Element_"|"_row.SettingChangeRef, "setting_change|"_..#NOTE_"|"_##class(OcuTalon.Data.SettingChange).RefIndexOpen(change).Ref, "the incident is a setting_change that names the setting and the change")
	Set requests = ..Requests(incident)
	Do $$$AssertEquals(requests.%Size(), 1, "one request is raised")
	If requests.%Size() = 1 {
		Set request = requests.%Get(0)
		Do $$$AssertEquals(request.fixKind_"|"_request.state_"|"_request.fixParameters, "rollback_setting|pending|"_{"change": (change)}.%ToJSON(), "a pending rollback_setting request for the change")
		Set dry = {}.%FromJSON(request.dryRun)
		Do $$$AssertEquals(dry.item_"|"_dry.field_"|"_dry.before_"|"_dry.after, ..#FAILING_"|"_..#NOTE_"|beta|alpha", "with the dry run: the current value before and the old value after: "_request.dryRun)
		Set notes = ..NoticeBodies(incident, "incident")
		Set all = ""
		Set every = ..NoticeBodies(incident)
		For i = 0:1:every.%Size() - 1 Set all = all_every.%Get(i).kind_"/"_every.%Get(i).catalogKey_" "
		Do $$$AssertEquals(notes.%Size(), 1, "one incident Notification: "_all)
		If notes.%Size() = 1 {
			Set note = notes.%Get(0)
			Do $$$AssertEquals(note.catalogKey, "incident.rollbackRequest", "its key is incident.rollbackRequest")
			Set text = ##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc)
			Set detectedAt = ##class(OcuTalon.Data.SettingChange).RefIndexOpen(change).DetectedAt
			Set minutes = ##class(OcuTalon.Watch.SettingCause).GapMinutes(detectedAt, row.FirstAt)
			// the expected gap is the catalog's own rendering of the minutes that code computed (words for 2 to 9)
			Set expected = ##class(OcuTalon.Msg.Catalog).Render("incident.settingChangeCause", {"minutes": (+minutes), "setting": (..#NOTE), "target": (..#FAILING), "time": (detectedAt)}, "phone", .sc)
			Set lead = $Piece(expected, ", at ", 1)_", at "
			Do $$$AssertTrue((lead [ "The feed broke ") && (text [ lead), "the text names the gap, computed by code: "_text)
			Do $$$AssertTrue(text [ ("I can put "_..#NOTE_" on "_..#FAILING_" back to its earlier value. Approve?"), "and offers the rollback")
		}
		Do ..AssertDelivered(a, "incident", request.ref)
		Do $$$AssertEquals(..Deliveries(b, "web", "approval", request.ref), 0, "a second session has no approval Delivery for it")
	}
	Do $$$AssertEquals(..Counter()_"|"_..ClassTime()_"|"_..Stored(..#FAILING), counter_"|"_classBefore_"|"_stored, "the dry run changed nothing: the counter, the class and the stored settings are as they were")
	Do $$$AssertEquals(..NoticeBodies(incident, "incident").%Size(), 1, "and there is no further notice")
}

/// AC4 (after the close): a rollback that FixExecutor's job carried out, the incident closed, and the undo asked of FixExecutor for the closed incident: the dry run and the run
/// go through, the value the rollback replaced is back, and the session reads result.rollbackUndone.
Method TestUndoAfterClose()
{
	If '..Ready() Quit
	Set a = ..Prepare(.trace)
	Set change = ..Change(a, "Host", "alpha", "beta", .incident)
	If change = "" Quit
	Do ..Run(a, trace, incident, "rollback_setting", change, ..#FAILING, ..#NOTE, "Host", "beta", "alpha")
	Do $$$AssertEquals(..Effective(..#FAILING, "Host", ..#NOTE), "alpha", "the rollback put the old value back")
	Do $$$AssertEquals(..WaitIncidentState(incident, "resolved"), "resolved", "and the incident is resolved")
	// the Tick records the rollback's own change, which the undo must not take for a later change of the setting
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set own = ..ChangeRows(..#NOTE)
	Do $$$AssertEquals(own.%Size(), 3, "the Tick recorded the rollback's own change after the setting's first sight and its change")
	Set stored = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set stored.State = "closed"
	Set stored.ClosedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(stored.%Save(), "the incident is closed")
	Kill stored
	// not refused though the rollback's own change is on record: the dry run is the current value (alpha) and the value the rollback replaced (beta)
	Do ..Run(a, trace, incident, "undo_rollback", change, ..#FAILING, ..#NOTE, "Host", "alpha", "beta")
	Do $$$AssertEquals(..Effective(..#FAILING, "Host", ..#NOTE), "beta", "the undo restored the value that the rollback replaced")
	Do $$$AssertEquals(##class(OcuTalon.Data.Incident).RefIndexOpen(incident).State, "closed", "and the incident stayed closed")
	Set notes = ..WaitResultNotices(incident, 2)
	Set keys = ""
	For i = 0:1:notes.%Size() - 1 Set keys = keys_$Select(keys = "": "", 1: ",")_notes.%Get(i).catalogKey
	Do $$$AssertEquals(keys, "result.settingRestored,result.rollbackUndone", "the session read result.settingRestored, then result.rollbackUndone")
	If notes.%Size() = 2 {
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(notes.%Get(0).catalogKey, notes.%Get(0).slots.%ToJSON(), "phone", .sc), ..#NOTE_" on "_..#FAILING_" is back to alpha. To undo it, ask me to undo the rollback.", "the rollback's text shows the restored old value")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(notes.%Get(1).catalogKey, notes.%Get(1).slots.%ToJSON(), "phone", .sc), "The rollback is undone: "_..#NOTE_" on "_..#FAILING_" is back to beta.", "and the undo's text shows the new value that is back")
	}
	// the rollback is spent: a second undo is refused (one undo for each rollback)
	Set answer = ..AskDryRun(incident, "undo_rollback", {"change": (change)}.%ToJSON(), trace, .dry, .sc)
	Do $$$AssertTrue($IsObject(answer) && (answer.Reason '= ""), "a second undo is refused")
	If $IsObject(answer) Do $$$AssertEquals(answer.Reason, ##class(OcuTalon.Fix.Kind.RollbackSetting).#NOTHINGTOUNDO, "with NOTHINGTOUNDO")
}

/// AC14: an undo is offered only while the rollback is the setting's latest change: a later change of the setting, or a current value that is not the restored one, refuses with
/// CHANGEDAGAIN.
Method TestUndoOnlyWhileLatest()
{
	If '..Ready() Quit
	Set a = ..Prepare(.trace)
	Set change = ..Change(a, "Host", "alpha", "beta", .incident)
	If change = "" Quit
	Do ..Run(a, trace, incident, "rollback_setting", change, ..#FAILING, ..#NOTE, "Host", "beta", "alpha")
	// the value moves again after the rollback
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).ChangeStored(..#FAILING, 1, "Host", ..#NOTE, "gamma"), "the setting changes again after the rollback")
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set answer = ..AskDryRun(incident, "undo_rollback", {"change": (change)}.%ToJSON(), trace, .dry, .sc)
	Do $$$AssertTrue($IsObject(answer), "FixExecutor answers")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.Reason, ##class(OcuTalon.Fix.Kind.RollbackSetting).ChangedAgain(..#NOTE, ..#FAILING), "the current value is not the restored one: CHANGEDAGAIN")
	// back to the restored value, but a later change of the setting was recorded
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).ChangeStored(..#FAILING, 1, "Host", ..#NOTE, "alpha"), "the value is the restored one again")
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set answer = ..AskDryRun(incident, "undo_rollback", {"change": (change)}.%ToJSON(), trace, .dry, .sc)
	Do $$$AssertTrue($IsObject(answer), "FixExecutor answers again")
	If $IsObject(answer) Do $$$AssertEquals(answer.Reason, ##class(OcuTalon.Fix.Kind.RollbackSetting).ChangedAgain(..#NOTE, ..#FAILING), "a later change of the setting is on record: CHANGEDAGAIN though the value is the restored one")
}

/// AC14 (QA): the current value of the setting is not the one that the rollback restored, and no Tick has recorded a later change yet (the value moved since the last Tick): the dry run of the
/// undo refuses with CHANGEDAGAIN on the value alone, a refusal that a recorded later row (TestUndoOnlyWhileLatest) does not exercise.
Method TestUndoRefusesUnseenChange()
{
	If '..Ready() Quit
	Set a = ..Prepare(.trace)
	Set change = ..Change(a, "Host", "alpha", "beta", .incident)
	If change = "" Quit
	Do ..Run(a, trace, incident, "rollback_setting", change, ..#FAILING, ..#NOTE, "Host", "beta", "alpha")
	Do $$$AssertEquals(..Effective(..#FAILING, "Host", ..#NOTE), "alpha", "the rollback put the old value back")
	// the value moves after the rollback and no Tick records it
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).ChangeStored(..#FAILING, 1, "Host", ..#NOTE, "gamma"), "the setting changes again after the rollback, with no Tick after it")
	Set rows = ..ChangeRows(..#NOTE)
	Do $$$AssertEquals(rows.%Size(), 2, "no row records the move yet: the setting's first sight and the change")
	Set answer = ..AskDryRun(incident, "undo_rollback", {"change": (change)}.%ToJSON(), trace, .dry, .sc)
	Do $$$AssertTrue($IsObject(answer), "FixExecutor answers")
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.Reason, ##class(OcuTalon.Fix.Kind.RollbackSetting).ChangedAgain(..#NOTE, ..#FAILING), "the current value is not the restored one: CHANGEDAGAIN")
	Do $$$AssertEquals(answer.Targets, "", "and the dry run names no target")
}

}
