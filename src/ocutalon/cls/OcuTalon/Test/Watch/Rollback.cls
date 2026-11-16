Include Ensemble

/// Tests of the setting rollback and its undo over the running Orders production (Story 23.3; AD-3, AD-15, AD-16, AD-24). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh
/// (FixExecutor is code of the running production), with demo mode on, through Test.Watch.Case: they need the running OcuTalon.Production and the Orders demo production in OCUORDERS. The
/// setting that they change is the stored Host setting ZzFixtureNote of the failing item OrdersFromPartner (Test.Watch.OrdersDefinition), changed through the saved definition
/// and recorded by the Tick of Checks; the definition is put back after each test.
///   - TestMeasured (Task 0, a hard gate): FixExecutor's own job carries out an approved rollback_setting through Fix.Executor.InProduction, which sets the stored setting in the saved
///     definition and calls Ens.Director.UpdateProduction in OCUORDERS; every other item of OCUORDERS keeps its job. The figures are logged and printed as SKIP lines (a status 2
///     never fails a class): the SKIP line of TestMeasuredRemoval is such a figure (Timing), not a skipped test, and the assertions after it run.
///   - TestUndoSystemDefaultChanged and TestUndoDefaultMovesAfterDryRun (DW-1366, DW-1378): the undo of a rollback of a System Default Setting change shows, in its dry run, the setting's
///     current default as After (the default that changed while the item's own value hid it), and a default that moves after the dry run skips the run with result.settingChangedSince;
///     the incident payload's request part names that After too, and the band's slots render to the chat's result line, and a run that changed the setting leaves the item with that After (DW-1378);
///   - TestUndoDefaultGone: the System Default Setting that the item's own value hid is gone, so the undo's After is the class value, and refused when that is empty;
///   - TestUpdateFailureRestoresRemoval and TestUpdateFailureRestoresInsert (DW-1365): the restore after a forced update failure puts a removed stored setting back and takes an inserted one out;
///   - TestUpdateFailureRestores and TestUpdateFailureNotApplied (DW-1365): Fix.Executor InProduction, given a plan entry whose updateErrors makes Ens.Director.UpdateProduction fail
///     once or twice (a test-only member of the entry that no kind sets), writes the earlier value back and reports the entry unreached as refused, or reports it as notapplied;
///   - Story 24.4a (the redaction of a setting's values; AskDryRun below is this class's override, which takes the hand-off of the dry run's raw values so that every fixture request holds
///     what IncidentManager stores):
///     TestTokenValueRestoredRaw (AC4, AC5): a rollback of a token URL through the real raise restores it byte for byte and stores the raw dry run, every view of it is redacted, and the
///     DryRunResult and Notification bodies, the event log, the live events and the phone messages hold the marker and not the token, and the incident payload's request part shows the
///     after redacted, the result notice's {after} (DW-1378);
///     TestTakeMissingNoRequest (the Planner's V6 condition): an answer whose hand-off entry is gone when IncidentManager takes it raises no request, stores no redacted dry run and takes
///     the refusal path with the kind's NOSTART;
///     TestUndoSystemDefaultTokenRaw (AC7): the undo of a rollback of a System Default Setting change whose current default is a token URL restores that URL byte for byte;
///     TestUndoRequestTokenRedacted (QA, AC2, AC4, AC5): a rollback of a token URL and then its undo, asked by a real ProposeFix: the phone messages of both requests, the undo request's
///     payload, notice slots and text show the token redacted, its stored dry run is raw, the undo restores the plain value, and no trace body, log row, live event or phone message holds the token;
///   - TestMeasuredOnline and TestRolesPutBackAfterAFailure: the Roles step rewrites every OcuTalon role, so the roles are saved (SaveRoles) and put back, by the test and by PutBack after a failed one;
///     OnBeforeAllTests reads every OcuTalon role and OnAfterAllTests fails the class when one is not as the class found it.
Class OcuTalon.Test.Watch.Rollback Extends OcuTalon.Test.Watch.Case [ DependsOn = OcuTalon.Test.Watch.OrdersDefinition ]
{

Parameter DEFINITION = "OcuTalon.Test.Watch.OrdersDefinition";

Parameter NOTE = {##class(OcuTalon.Test.Watch.OrdersDefinition).#NOTE};

/// The failing item of the fixture incident.
Parameter FAILING = {##class(OcuTalon.Test.Watch.OrdersDefinition).#ITEM};

Parameter SDSSETTING = "RetryInterval";

/// A Host setting of the failing item whose class default is empty (Ens.Host's BusinessPartner), for TestUndoDefaultGone's empty default.
Parameter EMPTYSETTING = "BusinessPartner";

/// Every OcuTalon role as the class found it (the JSON text of OcuTalonRoles), which OnAfterAllTests compares after its put-back.
Property RolesAtStart As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	Set ..RolesAtStart = ..OcuTalonRoles().%ToJSON()
	Quit sc
}

/// Fails the class when an OcuTalon role is not as the class found it once every put-back has run.
Method OnAfterAllTests() As %Status
{
	Set sc = ##super()
	If ..RolesAtStart = "" Quit sc
	Set difference = ..RolesDifference(..RolesAtStart)
	If difference '= "" Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "Test.Watch.Rollback leaves an OcuTalon role as it did not find it: "_difference))
	Quit sc
}

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
	// a rollback of a System Default Setting change leaves the item's own value of the setting in the definition, which Put does not name
	Set sc = $SYSTEM.Status.AppendStatus(sc, $ClassMethod(..#DEFINITION, "Put", 0, "", "", ..#SDSSETTING_","_..#EMPTYSETTING))
	Set sc = $SYSTEM.Status.AppendStatus(sc, ..DropDefault())
	Do ..DropHistory()
	Quit sc
}

/// Asks FixExecutor for the dry run (Test.Watch.Case) and, when the answer holds the hand-off reference of a setting kind's raw values, gives back an unsaved clone whose DryRun is the JSON
/// after Fix.Executor TakeValues: what IncidentManager would store, so that every fixture request holds raw values and no entry is left behind. The answer in the trace is never changed.
Method AskDryRun(incidentRef As %String, kind As %String, parameters As %String, super As %String, Output session As %Integer, Output sc As %Status, wait As %Integer = {..#SENDWAIT}) As OcuTalon.Fix.Msg.DryRunResult [ Private ]
{
	Set answer = ##super(incidentRef, kind, parameters, super, .session, .sc, wait)
	If '$IsObject(answer) || (answer.DryRun = "") Quit answer
	Set dry = {}.%FromJSON(answer.DryRun)
	If 'dry.%IsDefined("values") Quit answer
	Set taken = ##class(OcuTalon.Fix.Executor).TakeValues(dry)
	If $$$ISERR(taken) Set sc = taken
	Set clone = answer.%ConstructClone()
	Set clone.DryRun = dry.%ToJSON()
	Quit clone
}

/// Deletes the history rows of the Orders production.
ClassMethod DropHistory()
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SettingChange WHERE Namespace = ? AND Production = ?", ..#ORDERS, ..#ORDERSPRODUCTION)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SettingSnapshot WHERE Namespace = ? AND Production = ?", ..#ORDERS, ..#ORDERSPRODUCTION)
}

/// Saves a System Default Setting row of the setting for the item in the Orders production, through the class: a new row, or the value of the row that is there.
ClassMethod SaveDefault(item As %String, setting As %String, value As %String) As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set id = ..#ORDERSPRODUCTION_"||"_item_"||*||"_setting
	Set row = $Select(##class(Ens.Config.DefaultSettings).%ExistsId(id): ##class(Ens.Config.DefaultSettings).%OpenId(id), 1: ##class(Ens.Config.DefaultSettings).%New())
	If row.%Id() = "" {
		Set row.ProductionName = ..#ORDERSPRODUCTION
		Set row.ItemName = item
		Set row.HostClassName = "*"
		Set row.SettingName = setting
	}
	Set row.SettingValue = value
	Quit row.%Save()
}

/// Removes the System Default Setting row of the setting for the item; OK when it is not there.
ClassMethod DropDefault() As %Status
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set sc = $$$OK
	For setting = ..#SDSSETTING, ..#EMPTYSETTING {
		Set id = ..#ORDERSPRODUCTION_"||"_..#FAILING_"||*||"_setting
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
/// The Roles step rewrites every OcuTalon role from the areas' Grants only, so the roles are saved first and put back as they were (the trace role's OCUORDERS databases, which the Demo step
/// granted, are not among the Grants): after the put-back every OcuTalon role holds what it held before, which Test.Install.SecurityOverview reads in either order.
Method TestMeasuredOnline()
{
	If '..Ready() Quit
	Set user = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ServiceUser")
	Set trace = ##class(OcuTalon.Install.Step.Web).#TRACEROLE
	Do ..SaveRoles()
	Set rolesBefore = ..RolesBefore
	Set saved = {}.%FromJSON(rolesBefore)
	Do $$$AssertTrue($IsObject(saved.%Get(trace)) && $IsObject(saved.%Get(..#ROLE)), "the saved roles hold the trace role and the service role")
	If '$IsObject(saved.%Get(trace)) Quit
	Set traceBefore = saved.%Get(trace).resources
	Do $$$AssertTrue(traceBefore [ ..#ORDERSDATA, "the trace role holds the OCUORDERS data database before the Roles step runs (demo mode on)")
	Do ..SetOnlineDemo(1)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs again with onlineDemo 1")
	Do $$$AssertEquals(''$SYSTEM.Security.CheckUserPermission(user, "%Ens_ProductionConfig", "W"), 0, "the service user holds no %Ens_ProductionConfig:W")
	Do ..SetOnlineDemo(0)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Roles).Run(), "the Roles step runs again with onlineDemo 0")
	Do $$$AssertEquals(''$SYSTEM.Security.CheckUserPermission(user, "%Ens_ProductionConfig", "W"), 1, "and the service user holds it again")
	Do ..Timing("Task 0 (c): the trace role's resources after the Roles step: "_..OcuTalonRoles().%Get(trace).resources)
	Do $$$AssertStatusOK(..PutRolesBack(), "every OcuTalon role is put back as it was")
	Do $$$AssertEquals(..RolesDifference(rolesBefore), "", "every OcuTalon role holds what it held before the Roles step ran again")
	Do $$$AssertEquals(..OcuTalonRoles().%Get(trace).resources, traceBefore, "and the trace role holds the OCUORDERS databases again")
}

/// The put-back that OnAfterOneTest and OnAfterAllTests run (PutBack) restores every saved OcuTalon role when the test body did not: the trace role is damaged after SaveRoles, directly
/// through Security.Roles (without its OCUORDERS data database, as the Roles step leaves it, and with the service role granted, so both halves of the put-back are needed), PutBack runs as
/// it does after a failed test, and every role is as saved.
Method TestRolesPutBackAfterAFailure()
{
	If '..Ready() Quit
	Set trace = ##class(OcuTalon.Install.Step.Web).#TRACEROLE
	Do ..SaveRoles()
	Set rolesBefore = ..RolesBefore
	Set saved = {}.%FromJSON(rolesBefore).%Get(trace)
	Do $$$AssertTrue($IsObject(saved) && $IsObject({}.%FromJSON(rolesBefore).%Get(..#ROLE)), "the saved roles hold the trace role and the service role")
	If '$IsObject(saved) Quit
	Set damaged = ..Without(saved.resources, ..#ORDERSDATA)
	Set home = $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Kill props
	Set props("Resources") = damaged
	Set props("GrantedRoles") = ..#ROLE
	Set sc = ##class(Security.Roles).Modify(trace, .props)
	Set $NAMESPACE = home
	Do $$$AssertStatusOK(sc, "the trace role is damaged: no OCUORDERS data database, the service role granted")
	Do $$$AssertNotEquals(..RolesDifference(rolesBefore), "", "the damage shows")
	Do $$$AssertStatusOK(..PutBack(), "PutBack runs as it does after a failed test")
	Do $$$AssertEquals(..RolesDifference(rolesBefore), "", "every OcuTalon role is as it was saved")
	Set now = ..OcuTalonRoles().%Get(trace)
	Do $$$AssertEquals($Select($IsObject(now): now.resources_"|"_now.granted, 1: "<no trace role>"), saved.resources_"|"_saved.granted, "and the trace role holds its resources and granted roles again")
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


/// The rollback of a System Default Setting change made by FixExecutor's job: a System Default Setting row gives the setting of the failing item the value 7, one Tick records the change
/// (class value to 7, source default), the rollback writes the class value on the item, and a second Tick records the rollback's own change. The incident is
/// in incident, the class value in before and the item's stored settings from before the rollback in storedBefore. The result is the change's Ref, "" when it was not recorded.
Method RollBackDefault(a As %String, trace As %String, Output incident As %String, Output before As %String, Output storedBefore As %String) As %String [ Private ]
{
	Set incident = ""
	Set item = ..#FAILING
	Set setting = ..#SDSSETTING
	Set before = ..Effective(item, "Host", setting)
	Set storedBefore = ..Stored(item)
	Do $$$AssertStatusOK(..SaveDefault(item, setting, 7), "a System Default Setting row gives "_setting_" the value 7")
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set rows = ..ChangeRows(setting)
	Do $$$AssertEquals(rows.%Size(), 1, "the Tick records one change for it: "_rows.%ToJSON()_" stored "_..Stored(item)_" effective "_..Effective(item, "Host", setting))
	If rows.%Size() '= 1 Quit ""
	Set row = rows.%Get(0)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set fixture = ..Fixture(a, "1", ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (now), "FirstAt": (##class(OcuTalon.Data.Time).AddSeconds(row.detectedAt, 120)), "LastAt": (##class(OcuTalon.Data.Time).AddSeconds(row.detectedAt, 125))})
	Set incident = fixture.Ref
	Do ..Run(a, trace, incident, "rollback_setting", row.ref, item, setting, "Host", "7", before)
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(..ChangeRows(setting).%Size(), 2, "the second Tick records the rollback's own change")
	Quit row.ref
}

/// DW-1366 (Planner pre-push ruling 2026-11-15): the rollback of a System Default Setting change put the class value on the item, and the System Default Setting then changed to 9 while
/// the item's own value hid it (no change is recorded for it: the item's effective value did not move). The undo's dry run shows After 9, the setting's current default, not the
/// recorded new value 7, and the undo that runs takes the item's stored setting out, so that 9 applies; the incident payload's request part names 9 too, and the band's slots render to
/// the chat's result line (DW-1378). mutation: the dry run's After from the recorded new value; the part's after from the change's recorded new value.
Method TestUndoSystemDefaultChanged()
{
	If '..Ready() Quit
	Set a = ..Prepare(.trace)
	Set change = ..RollBackDefault(a, trace, .incident, .before, .storedBefore)
	If change = "" Quit
	Do $$$AssertStatusOK(..SaveDefault(..#FAILING, ..#SDSSETTING, 9), "the System Default Setting changes to 9 while the item's own value hides it")
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(..ChangeRows(..#SDSSETTING).%Size(), 2, "no change is recorded for it: the item's effective value did not move")
	Do $$$AssertEquals(..Effective(..#FAILING, "Host", ..#SDSSETTING), before, "and the item still has its own value")
	Do ..Run(a, trace, incident, "undo_rollback", change, ..#FAILING, ..#SDSSETTING, "Host", before, "9")
	Do $$$AssertEquals(..Effective(..#FAILING, "Host", ..#SDSSETTING), "9", "the undo made the current default apply")
	Do $$$AssertEquals(..Stored(..#FAILING), storedBefore, "and the item's stored settings are as they were before the rollback")
	Set notes = ..WaitResultNotices(incident, 2)
	Do $$$AssertEquals(notes.%Size(), 2, "the session has the rollback's and the undo's result Notifications")
	If notes.%Size() '= 2 Quit
	Set note = notes.%Get(1)
	Do $$$AssertEquals(note.catalogKey_"|"_note.slots.after, "result.rollbackUndone|9", "the undo's result line names 9")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.SettingChangeRef = change
	Do $$$AssertStatusOK(row.%Save(), "the incident names the change, as IncidentManager Answered does for a diagnosed one")
	Set payload = ##class(OcuTalon.Live.Payload.Incident).FromRow(row)
	Kill row
	Set part = ..RequestPart(payload, "undo_rollback")
	Do $$$AssertTrue($IsObject(part) && $IsObject(payload.SettingChange), "the incident payload lists the undo and names the change")
	If '$IsObject(part) || '$IsObject(payload.SettingChange) Quit
	Do $$$AssertEquals(part.After_"|"_payload.SettingChange.NewValue, "9|7", "the request part names the value the item has, and the recorded new value is stale")
	Set bandSlots = {"setting": (payload.SettingChange.Setting), "target": (payload.SettingChange.Item), "after": (part.After)}
	Set band = ##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, bandSlots.%ToJSON(), "web", .sc)
	Set chat = ##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "web", .sc)
	Do $$$AssertTrue((band = chat) && (band [ "is back to 9."), "the band's text is the chat's result line (the CONDITION): "_band)
}

/// The request part of the payload whose fix kind is kind (the first), "" when it has none.
ClassMethod RequestPart(payload As OcuTalon.Live.Payload.Incident, kind As %String) As OcuTalon.Live.Payload.Part.IncidentRequest [ Private ]
{
	For i = 1:1:payload.Requests.Count() {
		If payload.Requests.GetAt(i).FixKind = kind Quit
	}
	Quit $Select(i '> payload.Requests.Count(): payload.Requests.GetAt(i), 1: "")
}

/// DW-1366: the System Default Setting moves again (to 11) after the undo's dry run (After 9) was approved: the run re-reads the value that the removal would leave, finds that it is
/// not the After that was approved, writes nothing and reports result.settingChangedSince. A done run means the setting equals the dry run's After (DW-1378): the undo changed nothing, and no
/// request part of a run that changed the setting names a value that the item does not have, so the band and the chat never claim one. mutation: Plan's comparison with the approved After made to
/// pass when the value moved (the run then succeeds with the default at 11, and the part's After 9 is not the item's value).
Method TestUndoDefaultMovesAfterDryRun()
{
	If '..Ready() Quit
	Set a = ..Prepare(.trace)
	Set change = ..RollBackDefault(a, trace, .incident, .before, .storedBefore)
	If change = "" Quit
	Do $$$AssertStatusOK(..SaveDefault(..#FAILING, ..#SDSSETTING, 9), "the System Default Setting changes to 9")
	Set parameters = {"change": (change)}.%ToJSON()
	Set answer = ..AskDryRun(incident, "undo_rollback", parameters, trace, .dry, .sc)
	Do $$$AssertTrue($IsObject(answer) && (answer.Reason = ""), "the undo's dry run is made")
	If '$IsObject(answer) || (answer.Reason '= "") Quit
	Do $$$AssertEquals({}.%FromJSON(answer.DryRun).after, "9", "its After is the current default")
	Set request = ..Request(a, incident, "undo_rollback", parameters, answer.Targets, answer.DryRun)
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.RequestRefs = $Select(row.RequestRefs = "": request, 1: row.RequestRefs_","_request)
	Do $$$AssertStatusOK(row.%Save(), "the incident names the request")
	Kill row
	Do $$$AssertStatusOK(..SaveDefault(..#FAILING, ..#SDSSETTING, 11), "the System Default Setting changes to 11 after the dry run")
	Set stored = ..Stored(..#FAILING)
	Do $$$AssertStatusOK(..SendExecute(request, .session), "the Execute is handled")
	Set results = ..WaitFixResults(request, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.total_"|"_result.resent_"|"_result.completed_"|"_result.skipped_"|"_result.reason, "1|0|0|1|"_##class(OcuTalon.Fix.Kind.RollbackSetting).ChangedAgain(..#SDSSETTING, ..#FAILING), "Skipped 1, nothing changed, with the reason that names the setting")
	}
	Do $$$AssertEquals(..Stored(..#FAILING)_"|"_..Effective(..#FAILING, "Host", ..#SDSSETTING), stored_"|"_before, "nothing was written: the item still has its own value")
	Set notes = ..WaitResultNotices(incident, 2)
	Do $$$AssertEquals(notes.%Size(), 2, "the session has the rollback's and the undo's result Notifications")
	If notes.%Size() = 2 Do $$$AssertEquals(notes.%Get(1).catalogKey, "result.settingChangedSince", "the undo's is result.settingChangedSince")
	// DW-1378, Pin A: a done run means the setting equals the dry run's After, so the card and the chat never claim a value that the item does not have
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.SettingChangeRef = change
	Do $$$AssertStatusOK(row.%Save(), "the incident names the change")
	Set payload = ##class(OcuTalon.Live.Payload.Incident).FromRow(row)
	Kill row
	Set claimed = ""
	Set counts = ""
	For i = 1:1:payload.Requests.Count() {
		Set part = payload.Requests.GetAt(i)
		If part.Ref '= request Continue
		Set counts = part.Result.Completed_"|"_part.Result.Skipped
		If part.Result.Completed > 0 Set claimed = $Select(part.After '= ..Effective(..#FAILING, "Host", ..#SDSSETTING): "the band claims "_part.After_" but the item has "_..Effective(..#FAILING, "Host", ..#SDSSETTING), 1: "")
	}
	Do $$$AssertEquals(claimed, "", "no run that changed the setting names a value that the item does not have")
	Do $$$AssertEquals(counts, "0|1", "and the undo whose default moved after its dry run changed nothing: Completed 0, Skipped 1")
}

/// A plan entry for the Host setting of the failing item that sets it to value when it is expect.
ClassMethod PlanEntry(expect As %String, value As %String, updateErrors As %Integer) As %DynamicObject
{
	Quit {"id": 1, "setting": (..#NOTE), "target": "Host", "item": (..#FAILING), "production": (..#ORDERSPRODUCTION), "expect": (expect), "value": (value), "updateErrors": (updateErrors)}
}

/// DW-1365 (Planner pre-push ruling 2026-11-15), the restore works: Ens.Director.UpdateProduction fails once after the definition was saved with the new value (the test-only
/// updateErrors 1), InProduction writes the earlier value back, saves and updates again: the entry is unreached as refused with the production's error, the item's stored settings and
/// value are as they were, and so "Nothing was changed" is true. The second update is the real Ens.Director.UpdateProduction: the Orders event log gains exactly one "updating" line
/// of the production from this job (the first, forced, call writes none). mutation: the restore block of InProduction taken out; the restore's UpdateProduction replaced by $$$OK.
Method TestUpdateFailureRestores()
{
	If '..Ready() Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).ChangeStored(..#FAILING, 1, "Host", ..#NOTE, "beta"), "the stored Host setting is beta")
	Set stored = ..Stored(..#FAILING)
	Set floor = ..Top("Ens_Util.Log", ..#ORDERS)
	Do ##class(OcuTalon.Fix.Executor).InProduction(..#ORDERS, [(..PlanEntry("beta", "alpha", 1))], "", .done, .skipped, .unreached)
	Do $$$AssertEquals(done_"|"_skipped.%Size()_"|"_unreached.%Size(), "0|0|1", "nothing was done and nothing skipped, and the entry is unreached")
	If unreached.%Size() = 1 Do $$$AssertEquals(unreached.%Get(0).id_"|"_unreached.%Get(0).code, "1|refused", "as refused")
	Do $$$AssertEquals(..Stored(..#FAILING)_"|"_..Effective(..#FAILING, "Host", ..#NOTE), stored_"|beta", "the earlier value was written back: the stored settings and the value are as they were")
	Set log = ..LogSince(floor)
	// the lines of this job have no config name; Ens.ScheduleHandler's own update after an item restart names itself
	Do $$$AssertEquals($Length(" / "_log, " / : Production '"_..#ORDERSPRODUCTION_"' updating") - 1, 1, "the restore updated the running production once: "_log)
}

/// DW-1365, the restore fails too: Ens.Director.UpdateProduction fails twice (updateErrors 2), so the earlier value is written back but the production cannot apply it: the entry is
/// unreached as notapplied with the production's error as its reason, without the "ERROR <Ens>Name: " prefix of an Ens error, and the stored settings hold the earlier value again.
/// mutation: the code of that entry set to refused; the reason cleaned of an "ERROR #" prefix only.
Method TestUpdateFailureNotApplied()
{
	If '..Ready() Quit
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).ChangeStored(..#FAILING, 1, "Host", ..#NOTE, "beta"), "the stored Host setting is beta")
	Set stored = ..Stored(..#FAILING)
	Do ##class(OcuTalon.Fix.Executor).InProduction(..#ORDERS, [(..PlanEntry("beta", "alpha", 2))], "", .done, .skipped, .unreached)
	Do $$$AssertEquals(done_"|"_skipped.%Size()_"|"_unreached.%Size(), "0|0|1", "nothing was done and nothing skipped, and the entry is unreached")
	If unreached.%Size() = 1 Do $$$AssertEquals(unreached.%Get(0).id_"|"_unreached.%Get(0).code_"|"_unreached.%Get(0).reason, "1|notapplied|the update was refused by the test", "as notapplied, with the production's error")
	Do $$$AssertEquals(..Stored(..#FAILING), stored, "the earlier value was written back to the definition")
	// without the test-only member the same entry is carried out
	Do ##class(OcuTalon.Fix.Executor).InProduction(..#ORDERS, [(..PlanEntry("beta", "alpha", 0))], "", .done, .skipped, .unreached)
	Do $$$AssertEquals(done_"|"_skipped.%Size()_"|"_unreached.%Size()_"|"_..Effective(..#FAILING, "Host", ..#NOTE), "1|0|0|alpha", "with no forced failure the entry is done and the value is alpha")
}

/// A plan entry that takes the stored Host setting of the failing item out, which is expect now (an undo of a System Default Setting change), with the forced update failures.
ClassMethod RemoveEntry(setting As %String, expect As %String, updateErrors As %Integer) As %DynamicObject
{
	Quit {"id": 1, "setting": (setting), "target": "Host", "item": (..#FAILING), "production": (..#ORDERSPRODUCTION), "expect": (expect), "value": "", "remove": 1, "updateErrors": (updateErrors)}
}

/// DW-1365, the restore of a removal: the item's own stored value of RetryInterval (8) sits between two other stored settings, and a plan entry with remove 1 takes it out. With the update
/// forced to fail once, the stored setting is back in its place and the effective value is 8 again, and the entry is unreached as refused. Without the forced failure the same entry
/// is done: the stored setting is gone and the class value applies. mutation: the loop of InProduction that puts the removed entries back taken out.
Method TestUpdateFailureRestoresRemoval()
{
	If '..Ready() Quit
	Set setting = ..#SDSSETTING
	Do $$$AssertStatusOK($ClassMethod(..#DEFINITION, "Put", 0, "", "", setting), "the item has no stored "_setting)
	Set classValue = ..Effective(..#FAILING, "Host", setting)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).ChangeStored(..#FAILING, 1, "Host", setting, 8), "the stored Host setting "_setting_" is 8")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).ChangeStored(..#FAILING, 1, "Host", ..#NOTE, "beta"), "and a stored setting follows it")
	Set stored = ..Stored(..#FAILING)
	Do $$$AssertTrue(stored [ ("Host:"_setting_"=8|"), "the stored settings are "_stored)
	Do $$$AssertEquals(..Effective(..#FAILING, "Host", setting), "8", "the effective value is 8")
	Do ##class(OcuTalon.Fix.Executor).InProduction(..#ORDERS, [(..RemoveEntry(setting, "8", 1))], "", .done, .skipped, .unreached)
	Do $$$AssertEquals(done_"|"_skipped.%Size()_"|"_unreached.%Size(), "0|0|1", "nothing was done and nothing skipped, and the entry is unreached")
	If unreached.%Size() = 1 Do $$$AssertEquals(unreached.%Get(0).id_"|"_unreached.%Get(0).code, "1|refused", "as refused")
	Do $$$AssertEquals(..Stored(..#FAILING)_"|"_..Effective(..#FAILING, "Host", setting), stored_"|8", "the stored setting is back in its place and the value is as it was")
	// without the forced failure the same entry is carried out
	Do ##class(OcuTalon.Fix.Executor).InProduction(..#ORDERS, [(..RemoveEntry(setting, "8", 0))], "", .done, .skipped, .unreached)
	Do $$$AssertEquals(done_"|"_skipped.%Size()_"|"_unreached.%Size(), "1|0|0", "with no forced failure the entry is done")
	Do $$$AssertEquals(..Stored(..#FAILING)_"|"_..Effective(..#FAILING, "Host", setting), $Replace(stored, "Host:"_setting_"=8|", "")_"|"_classValue, "and the stored setting is gone, so that the class value applies")
}

/// DW-1365, the restore of an insert: the item has no stored RetryInterval, and a rollback entry adds one (8). With the update forced to fail once, the added entry is gone again and the
/// effective value is the class value, and the entry is unreached as refused. Without the forced failure the same entry is done and the item's stored settings gain the entry.
/// mutation: the line of InProduction that takes the inserted entry out again taken out.
Method TestUpdateFailureRestoresInsert()
{
	If '..Ready() Quit
	Set setting = ..#SDSSETTING
	Do $$$AssertStatusOK($ClassMethod(..#DEFINITION, "Put", 0, "", "", setting), "the item has no stored "_setting)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Watch.SettingHistory).ChangeStored(..#FAILING, 1, "Host", ..#NOTE, "beta"), "another setting is stored")
	Set classValue = ..Effective(..#FAILING, "Host", setting)
	Set stored = ..Stored(..#FAILING)
	Do $$$AssertTrue(stored '[ ("Host:"_setting_"="), "the stored settings are "_stored)
	Set entry = ..PlanEntry(classValue, 8, 1)
	Do entry.%Set("setting", setting)
	Do ##class(OcuTalon.Fix.Executor).InProduction(..#ORDERS, [(entry)], "", .done, .skipped, .unreached)
	Do $$$AssertEquals(done_"|"_skipped.%Size()_"|"_unreached.%Size(), "0|0|1", "nothing was done and nothing skipped, and the entry is unreached")
	If unreached.%Size() = 1 Do $$$AssertEquals(unreached.%Get(0).id_"|"_unreached.%Get(0).code, "1|refused", "as refused")
	Do $$$AssertEquals(..Stored(..#FAILING)_"|"_..Effective(..#FAILING, "Host", setting), stored_"|"_classValue, "the inserted entry is gone and the value is as it was")
	// without the forced failure the same entry is carried out
	Do entry.%Set("updateErrors", 0, "number")
	Do ##class(OcuTalon.Fix.Executor).InProduction(..#ORDERS, [(entry)], "", .done, .skipped, .unreached)
	Do $$$AssertEquals(done_"|"_skipped.%Size()_"|"_unreached.%Size(), "1|0|0", "with no forced failure the entry is done")
	Do $$$AssertEquals(..Stored(..#FAILING)_"|"_..Effective(..#FAILING, "Host", setting), stored_"|Host:"_setting_"=8|8", "and the item has the stored setting")
}

/// DW-1366, the System Default Setting that the item's own value hid is gone: a rollback of a System Default Setting change (RetryInterval 5 to 7) put 5 on the item, and the System Default
/// Setting row is then dropped, so that the value the item will have without its own value is the class value.
///   - Non-empty class default: the undo's dry run shows After = the class value 5 (not the recorded new value 7), and the undo that runs takes the item's own value out again.
///   - Empty class default (BusinessPartner, whose class default is empty, with two System Default values alpha and beta, a rollback that puts alpha on the item and the row then dropped): the
///     dry run is refused with the CHANGEDAGAIN reason, because the value that the item will have is empty.
/// mutation: the line of UndoRollback.Undoable that refuses an empty After taken out (the empty-default part red), and After taken from the recorded new value (the non-empty part red).
Method TestUndoDefaultGone()
{
	If '..Ready() Quit
	Set a = ..Prepare(.trace)
	Set change = ..RollBackDefault(a, trace, .incident, .before, .storedBefore)
	If change = "" Quit
	Do $$$AssertStatusOK(..DropDefault(), "the System Default Setting row is dropped")
	Do $$$AssertEquals(..Effective(..#FAILING, "Host", ..#SDSSETTING), before, "the item still has its own value, the class value "_before)
	Do ..Run(a, trace, incident, "undo_rollback", change, ..#FAILING, ..#SDSSETTING, "Host", before, before)
	Do $$$AssertEquals(..Stored(..#FAILING), storedBefore, "the undo took the item's own value out: the stored settings are as they were before the rollback")
	Do $$$AssertEquals(..Effective(..#FAILING, "Host", ..#SDSSETTING), before, "and the class value applies")
	// the empty class default
	Set setting = ..#EMPTYSETTING
	Set item = ..#FAILING
	Do $$$AssertEquals(..Effective(item, "Host", setting), "", "the class default of "_setting_" is empty")
	Do $$$AssertStatusOK(..SaveDefault(item, setting, "alpha"), "a System Default Setting gives "_setting_" the value alpha")
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertStatusOK(..SaveDefault(item, setting, "beta"), "and then beta")
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set rows = ..ChangeRows(setting)
	Do $$$AssertEquals(rows.%Size(), 2, "the Ticks record two changes for it: "_rows.%ToJSON())
	If rows.%Size() '= 2 Quit
	Set row = rows.%Get(1)
	Do $$$AssertEquals(row.oldValue_"|"_row.newValue_"|"_row.source, "alpha|beta|default", "the newest is alpha to beta, with the source default")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set fixture = ..Fixture(a, "2", ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (now), "FirstAt": (##class(OcuTalon.Data.Time).AddSeconds(row.detectedAt, 120)), "LastAt": (##class(OcuTalon.Data.Time).AddSeconds(row.detectedAt, 125))})
	Set second = fixture.Ref
	Do ..Run(a, trace, second, "rollback_setting", row.ref, item, setting, "Host", "beta", "alpha")
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertStatusOK(..DropDefault(), "the System Default Setting row is dropped")
	Do $$$AssertEquals(..Effective(item, "Host", setting), "alpha", "the item still has its own value alpha")
	Set answer = ..AskDryRun(second, "undo_rollback", {"change": (row.ref)}.%ToJSON(), trace, .dry, .sc)
	Do $$$AssertTrue($IsObject(answer), "FixExecutor answers the undo's dry run")
	If $IsObject(answer) Do $$$AssertEquals(answer.Reason, ##class(OcuTalon.Fix.Kind.RollbackSetting).ChangedAgain(setting, item), "it is refused with the CHANGEDAGAIN reason: the value the item will have is empty")
}

/// The first-round rollback of the token change through the real raise (the mock diagnosis rollback), up to the raised request: the incident's Ref in incident, the request's row in request ("" when
/// none was raised). Returns 0 when a step failed (the failure is asserted).
Method RaiseTokenRollback(a As %String, Output incident As %String, Output request As %DynamicObject) As %Boolean [ Private ]
{
	Set incident = ""
	Set request = ""
	Set at = ##class(OcuTalon.Test.Watch.Incidents).Stamp(0)
	Do $$$AssertStatusOK(..SendBatch(..#ORDERS, ..#ORDERSPRODUCTION, a, [{"item": (..#FAILING), "text": "[[mock:diagnosis-rollback]] The target is not configured", "at": (at)}]), "a failure at the failing item is sent")
	Set rows = ..WaitIncident(a, ..#ORDERSPRODUCTION, 1)
	Do $$$AssertEquals(rows.%Size(), 1, "one incident")
	If rows.%Size() '= 1 Quit 0
	Set incident = rows.%Get(0).ref
	Set ..ItemIds = ..ItemIds _ $ListBuild(incident)
	Do $$$AssertTrue(..WaitDiagnosed(incident), "it holds its diagnosis")
	Do $$$AssertTrue(..WaitRow(incident, "NoticedAt", "", ..#WAITINCIDENT) '= "", "and it is noticed")
	Do ..WaitNotices(incident, 1)
	Set requests = ..Requests(incident)
	If requests.%Size() = 1 Set request = requests.%Get(0)
	Quit 1
}

/// The first node of the message-body global that holds the text, as "<node> => <data>" cut to 400 characters, "" when none does (for the message of a failed leak check).
ClassMethod FirstHit(text As %String) As %String [ Private ]
{
	Set node = "^Ens.MessageBodyD"
	For {
		Set node = $Query(@node, 1, data)
		If node = "" Quit
		If (data [ text) || (node [ text) Quit
	}
	If node = "" Quit ""
	Set found = $Extract(node_" => "_data, 1, 400)
	Set clean = ""
	For i = 1:1:$Length(found) {
		Set code = $Ascii(found, i)
		Set clean = clean_$Select((code > 31) && (code < 127): $Extract(found, i), 1: ".")
	}
	Quit clean
}

/// The token URL of the token fixtures as every view shows it: redacted.
ClassMethod Shown() As %String [ Private ]
{
	Quit "https://feed.example.test/orders?token=[redacted]"
}

/// V5 condition 2, AC4, AC5 (integration): a real setting change whose old value is a token URL, the diagnosis from the mock, the real raise, the real approval and run. The rollback restores the
/// token URL byte for byte, the stored dry run of the request holds the raw values, and every view of it is redacted: the approval payload, the incident payload, the notices' slots and their phone
/// text. After the run the incident's DryRunResult bodies hold the marker and a hand-off reference and not the token, its Notification bodies hold the marker in Slots and not the token, and no
/// Ens message body or header, event-log row, live event or phone message holds the token.
Method TestTokenValueRestoredRaw()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	If '..ApprovalReady() Quit
	Set url = ##class(OcuTalon.Test.Watch.SettingCause).TokenUrl()
	Set token = ##class(OcuTalon.Test.Watch.SettingCause).Token()
	Set plain = "https://feed.example.test/orders?format=json"
	Set shown = ..Shown()
	Set a = ..Prepare(.trace)
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set change = ..Change(a, "Host", url, plain, .unused, 0)
	If change = "" Quit
	If '..RaiseTokenRollback(a, .incident, .request) Quit
	Do $$$AssertTrue($IsObject(request), "one request is raised")
	If '$IsObject(request) Quit
	Set dry = {}.%FromJSON(request.dryRun)
	Do $$$AssertEquals(dry.%IsDefined("values")_"|"_dry.field_"|"_dry.before_"|"_dry.after, "0|"_..#NOTE_"|"_plain_"|"_url, "the stored dry run holds the raw values (the current value before and the token URL after) and no hand-off reference: "_$Extract(request.dryRun, 1, 200))
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request.ref)
	Set part = ##class(OcuTalon.Live.Payload.Approval).FromRow(row).DryRun
	Do $$$AssertEquals(part.Before_"|"_part.After, plain_"|"_shown, "the approval payload shows the token URL redacted and the plain value as it is")
	Kill row
	Set incidentRow = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set payload = ##class(OcuTalon.Live.Payload.Incident).FromRow(incidentRow)
	Do $$$AssertEquals(payload.SettingChange.OldValue_"|"_payload.SettingChange.NewValue, shown_"|"_plain, "the incident payload shows the old value redacted")
	Set partAfter = ""
	For i = 1:1:payload.Requests.Count() {
		If payload.Requests.GetAt(i).Ref = request.ref Set partAfter = payload.Requests.GetAt(i).After
	}
	Do $$$AssertEquals(partAfter, shown, "and its request part shows the after redacted (DW-1378)")
	Kill incidentRow
	Set notes = ..NoticeBodies(incident, "incident")
	Do $$$AssertEquals(notes.%Size(), 1, "one incident Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.catalogKey_"|"_note.slots.before_"|"_note.slots.after, "incident.rollbackRequest|"_plain_"|"_shown, "incident.rollbackRequest: {before} is the plain value and {after} the redacted URL")
		Set text = ##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc)
		Do $$$AssertTrue((text [ shown) && ($Find(text, token) = 0), "and its phone text holds the marker and no token: "_text)
	}
	Set done = ##class(OcuTalon.Bridge.Approval).Answer(request.ref, "approve", "web", ..#ANSWERER, a, .winner)
	Do $$$AssertEquals(done, "done", "the approval is accepted")
	Do $$$AssertEquals(..WaitState(incident, request.ref, "done"), "done", "the request is done")
	Do $$$AssertEquals(..Effective(..#FAILING, "Host", ..#NOTE), url, "the item's setting is the token URL again, byte for byte")
	Set results = ..WaitResultNotices(incident, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one result Notification")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.catalogKey_"|"_result.slots.after, "result.settingRestored|"_shown, "result.settingRestored: {after} is the redacted URL")
		Do $$$AssertEquals(result.slots.after, partAfter, "the result notice's {after} is the request part's after")
		Set text = ##class(OcuTalon.Msg.Catalog).Render(result.catalogKey, result.slots.%ToJSON(), "phone", .sc)
		Do $$$AssertTrue((text [ shown) && ($Find(text, token) = 0), "and its phone text holds the marker and no token: "_text)
	}
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request.ref)
	Do $$$AssertEquals({}.%FromJSON(row.DryRun).after, url, "the stored dry run still holds the token URL after the run")
	Kill row
	// the trace: the incident's DryRunResult and Notification bodies
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT DryRun FROM OcuTalon_Fix_Msg.DryRunResult WHERE IncidentRef = ? AND DryRun <> ''", incident)
	Set bodies = 0
	While rs.%Next() {
		Set bodies = bodies + 1
		Set text = rs.%GetData(1)
		Do $$$AssertTrue((text [ "[redacted]") && (text [ "secret://handoff/") && ($Find(text, token) = 0), "a DryRunResult body holds the marker and a hand-off reference and not the token: "_text)
	}
	Do $$$AssertTrue(bodies '< 1, "the incident has a DryRunResult body")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT CatalogKey, Slots FROM OcuTalon_Msg.Notification WHERE IncidentRef = ? AND CatalogKey IN (?, ?)", incident, "incident.rollbackRequest", "result.settingRestored")
	Set bodies = 0
	While rs.%Next() {
		Set bodies = bodies + 1
		Set text = rs.%GetData(2)
		Do $$$AssertTrue((text [ "[redacted]") && ($Find(text, token) = 0), "the "_rs.%GetData(1)_" Notification body holds the marker in Slots and not the token: "_text)
	}
	Do $$$AssertEquals(bodies, 2, "both Notification bodies are there")
	Set leaks = ##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(token)
	Do $$$AssertEquals(leaks, "", "no Ens message body or header and no event-log global holds the token: "_leaks_" "_..FirstHit(token))
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(mark, token), 0, "no event-log row holds the token")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("OcuTalon_Live.Event", "Payload", token), 0, "no live event payload holds the token")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("OcuTalon_Data.SimMessage", "Text", token), 0, "and no phone message")
}

/// The Planner's V6 condition: the hand-off entry of the dry run's raw values is gone (here, an entry whose lifetime is 0) when IncidentManager takes it. No request is raised, no stored dry run of
/// the incident holds the marker, the incident takes the refusal path with the kind's NOSTART (the no-fix notice, one warning naming the reason), and the item's setting is unchanged.
Method TestTakeMissingNoRequest()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set url = ##class(OcuTalon.Test.Watch.SettingCause).TokenUrl()
	Set token = ##class(OcuTalon.Test.Watch.SettingCause).Token()
	Set plain = "https://feed.example.test/orders?format=json"
	Set a = ..Prepare(.trace)
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set change = ..Change(a, "Host", url, plain, .unused, 0)
	If change = "" Quit
	Set counter = ..Counter()
	Set stored = ..Stored(..#FAILING)
	Set ^IRIS.Temp.OcuTalon.Fix("valuesSeconds") = 0
	Try {
		If '..RaiseTokenRollback(a, .incident, .request) Quit
		Do $$$AssertEquals($IsObject(request), 0, "no request is raised")
		Do $$$AssertEquals(..Requests(incident).%Size(), 0, "and no ApprovalRequest row names the incident")
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE IncidentRef = ? AND DryRun [ ?", incident, "[redacted]")
		Do rs.%Next()
		Do $$$AssertEquals(rs.%GetData(1), 0, "no stored dry run of the incident holds the marker")
		Set notes = ..NoticeBodies(incident, "incident")
		Do $$$AssertEquals(notes.%Size(), 1, "one incident Notification")
		If notes.%Size() = 1 Do $$$AssertEquals(notes.%Get(0).catalogKey, "incident.noFix", "the incident took the refusal path: the no-fix notice")
		Do $$$AssertTrue(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(mark, ##class(OcuTalon.Fix.Kind.RollbackSetting).#NOSTART) '< 1, "with a warning that names the reason NOSTART")
		Do $$$AssertEquals(..Counter()_"|"_..Stored(..#FAILING)_"|"_..Effective(..#FAILING, "Host", ..#NOTE), counter_"|"_stored_"|"_plain, "the item's setting is unchanged")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(token), "", "and no trace body holds the token")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "no error")
	}
	Kill ^IRIS.Temp.OcuTalon.Fix("valuesSeconds")
}

/// AC7 (V5 condition 3): BusinessPartner, whose class default is empty, has the System Default Setting alpha and then beta; the rollback of the beta change puts alpha on the item; the System Default
/// then becomes a token URL while the item's own value hides it. The undo works from the stored raw After: the item's effective value is the token URL byte for byte, and the item's stored settings
/// are as they were before the rollback.
Method TestUndoSystemDefaultTokenRaw()
{
	If '..Ready() Quit
	Set a = ..Prepare(.trace)
	Set item = ..#FAILING
	Set setting = ..#EMPTYSETTING
	Set url = ##class(OcuTalon.Test.Watch.SettingCause).TokenUrl()
	Set storedBefore = ..Stored(item)
	Do $$$AssertEquals(..Effective(item, "Host", setting), "", "the class default of "_setting_" is empty")
	Do $$$AssertStatusOK(..SaveDefault(item, setting, "alpha"), "a System Default Setting gives "_setting_" the value alpha")
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertStatusOK(..SaveDefault(item, setting, "beta"), "and then beta")
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set rows = ..ChangeRows(setting)
	Do $$$AssertEquals(rows.%Size(), 2, "the Ticks record two changes for it: "_rows.%ToJSON())
	If rows.%Size() '= 2 Quit
	Set row = rows.%Get(1)
	Do $$$AssertEquals(row.oldValue_"|"_row.newValue_"|"_row.source, "alpha|beta|default", "the newest is alpha to beta, with the source default")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set fixture = ..Fixture(a, "1", ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (now), "FirstAt": (##class(OcuTalon.Data.Time).AddSeconds(row.detectedAt, 120)), "LastAt": (##class(OcuTalon.Data.Time).AddSeconds(row.detectedAt, 125))})
	Set incident = fixture.Ref
	Do ..Run(a, trace, incident, "rollback_setting", row.ref, item, setting, "Host", "beta", "alpha")
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(..Effective(item, "Host", setting), "alpha", "the rollback put alpha on the item")
	Do $$$AssertStatusOK(..SaveDefault(item, setting, url), "the System Default Setting becomes the token URL while the item's own value hides it")
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(..Effective(item, "Host", setting), "alpha", "the item still has its own value")
	Do ..Run(a, trace, incident, "undo_rollback", row.ref, item, setting, "Host", "alpha", url)
	Do $$$AssertEquals(..Effective(item, "Host", setting), url, "the undo made the token URL apply, byte for byte")
	Do $$$AssertEquals(..Stored(item), storedBefore, "and the item's stored settings are as they were before the rollback")
}

/// The Notification bodies of the incident with the catalog key, as NoticeBodies gives them, waiting up to WAITINCIDENT seconds for at least one.
Method NoticesWithKey(incident As %String, key As %String) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + ..#WAITINCIDENT
	For {
		Set found = []
		Set all = ..NoticeBodies(incident)
		For i = 0:1:all.%Size() - 1 {
			If all.%Get(i).catalogKey = key Do found.%Push(all.%Get(i))
		}
		If (found.%Size() '< 1) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit found
}

/// QA of Story 24.4a (AC2, AC4, AC5; the undo request's Before and After end to end, and the phone page on the real runtime): a real setting change whose old value is a token URL, the real
/// rollback (the mock diagnosis, the real raise, the real approval and run), and then the undo that the chat asks for (a real ProposeFix to IncidentManager, which asks FixExecutor for the
/// dry run, takes the hand-off, raises the request and sends its notice). The phone message of each request holds the marker and not the token; the undo request's stored dry run holds the
/// raw values (the token URL as Before), and its approval payload, its notice's slots and its phone text show the token redacted and the plain After as it is; the undo restores the plain
/// value; the result notice's slots hold no token; and no trace body, event-log row, live event or phone message holds the token, the DryRunResult bodies of both asks holding the marker
/// and a hand-off reference.
Method TestUndoRequestTokenRedacted()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	If '..ApprovalReady() Quit
	Set url = ##class(OcuTalon.Test.Watch.SettingCause).TokenUrl()
	Set token = ##class(OcuTalon.Test.Watch.SettingCause).Token()
	Set plain = "https://feed.example.test/orders?format=json"
	Set shown = ..Shown()
	Set a = ..Prepare(.trace)
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set change = ..Change(a, "Host", url, plain, .unused, 0)
	If change = "" Quit
	If '..RaiseTokenRollback(a, .incident, .rollback) Quit
	Do $$$AssertTrue($IsObject(rollback), "the rollback request is raised")
	If '$IsObject(rollback) Quit
	// the rollback request on the phone page: the token URL is the After
	Set phone = ..PhoneText(a, rollback.ref)
	Do $$$AssertTrue((phone [ shown) && ($Find(phone, token) = 0), "the phone message of the rollback request holds the marker and no token: "_phone)
	Set done = ##class(OcuTalon.Bridge.Approval).Answer(rollback.ref, "approve", "web", ..#ANSWERER, a, .winner)
	Do $$$AssertEquals(done, "done", "the rollback is approved")
	Do $$$AssertEquals(..WaitState(incident, rollback.ref, "done"), "done", "and it is done")
	Do $$$AssertEquals(..Effective(..#FAILING, "Host", ..#NOTE), url, "the item's setting is the token URL again")
	Do $$$AssertEquals(..WaitIncidentState(incident, "resolved"), "resolved", "the incident is resolved")
	// the Tick records the rollback's own change, which the undo must not take for a later change of the setting
	Hang 1
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	// the undo, asked as the chat's tool asks it: a ProposeFix to the real IncidentManager
	Set sc = ##class(Ens.Director).CreateBusinessService(..#SENDER, .service)
	Do $$$AssertStatusOK(sc, "the sender service is there")
	If $$$ISERR(sc) Quit
	Set command = ##class(OcuTalon.Msg.Command.ProposeFix).%New()
	Set command.Origin = "tool"
	Set command.SessionRef = a
	Set command.IncidentRef = incident
	Set command.FixKind = "undo_rollback"
	Set command.Parameters = "{}"
	Set sc = service.SendRequestSync(..#MANAGER, command, .response, 60)
	Set ..ExecuteSessions = ..ExecuteSessions _ $Select(..ExecuteSessions = "": "", 1: ",") _ service.%SessionId
	Do $$$AssertStatusOK(sc, "IncidentManager answers the ProposeFix")
	If $$$ISERR(sc) || '$IsObject($Get(response)) Quit
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|raised", "the undo is raised: "_response.Message)
	If response.Outcome '= "raised" Quit
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(response.Ref)
	Do $$$AssertTrue($IsObject(row), "the undo request's row exists")
	If '$IsObject(row) Quit
	Set stored = {}.%FromJSON(row.DryRun)
	Do $$$AssertEquals(row.FixKind_"|"_stored.%IsDefined("values")_"|"_stored.field_"|"_stored.before_"|"_stored.after, "undo_rollback|0|"_..#NOTE_"|"_url_"|"_plain, "its stored dry run holds the raw values (the token URL as Before) and no hand-off reference: "_$Extract(row.DryRun, 1, 200))
	Set part = ##class(OcuTalon.Live.Payload.Approval).FromRow(row).DryRun
	Do $$$AssertEquals(part.Before_"|"_part.After, shown_"|"_plain, "its approval payload shows the token URL redacted in Before and the plain After as it is")
	Kill row
	Set notes = ..NoticesWithKey(incident, "incident.undoRollbackRequest")
	Do $$$AssertEquals(notes.%Size(), 1, "one incident.undoRollbackRequest Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.slots.before_"|"_note.slots.after, shown_"|"_plain, "its slots: {before} is the redacted URL and {after} the plain value")
		Set text = ##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc)
		Do $$$AssertTrue((text [ shown) && ($Find(text, token) = 0), "and its text holds the marker and no token: "_text)
	}
	Set phone = ..PhoneText(a, response.Ref)
	Do $$$AssertTrue((phone [ shown) && ($Find(phone, token) = 0), "the phone message of the undo request holds the marker and no token: "_phone)
	Set done = ##class(OcuTalon.Bridge.Approval).Answer(response.Ref, "approve", "web", ..#ANSWERER, a, .winner)
	Do $$$AssertEquals(done, "done", "the undo is approved")
	Do $$$AssertEquals(..WaitState(incident, response.Ref, "done"), "done", "and it is done")
	Do $$$AssertEquals(..Effective(..#FAILING, "Host", ..#NOTE), plain, "the undo put the plain value back")
	Set results = ..WaitResultNotices(incident, 2)
	Set undone = ""
	For i = 0:1:results.%Size() - 1 {
		If results.%Get(i).catalogKey = "result.rollbackUndone" Set undone = results.%Get(i)
	}
	Do $$$AssertTrue($IsObject(undone), "the session reads result.rollbackUndone")
	If $IsObject(undone) Do $$$AssertEquals(undone.slots.after, plain, "its {after} is the plain value")
	// the trace: both asks' DryRunResult bodies hold the marker and a reference, never the token
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT DryRun FROM OcuTalon_Fix_Msg.DryRunResult WHERE IncidentRef = ? AND DryRun <> ''", incident)
	Set bodies = 0
	While rs.%Next() {
		Set bodies = bodies + 1
		Set text = rs.%GetData(1)
		Do $$$AssertTrue((text [ "[redacted]") && (text [ "secret://handoff/") && ($Find(text, token) = 0), "a DryRunResult body holds the marker and a hand-off reference and not the token: "_text)
	}
	Do $$$AssertTrue(bodies '< 2, "the incident has a DryRunResult body for each ask")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT CatalogKey, Slots FROM OcuTalon_Msg.Notification WHERE IncidentRef = ?", incident)
	While rs.%Next() {
		Do $$$AssertEquals($Find(rs.%GetData(2), token), 0, "the "_rs.%GetData(1)_" Notification body holds no token")
	}
	Set leaks = ##class(OcuTalon.Test.Core.SecretHandoff).TraceLeaks(token)
	Do $$$AssertEquals(leaks, "", "no Ens message body or header and no event-log global holds the token: "_leaks_" "_..FirstHit(token))
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(mark, token), 0, "no event-log row holds the token")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("OcuTalon_Live.Event", "Payload", token), 0, "no live event payload holds the token")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.SecretHandoff).TableHolds("OcuTalon_Data.SimMessage", "Text", token), 0, "and no phone message")
}
}
