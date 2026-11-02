/// Tests of the retention area, OcuTalon.Install.Step.Retention, and of the three purge tasks it declares (Story 30.2; AD-27, AD-23, AD-19, AD-17, AD-26,
/// NFR-19). THROWAWAY STACKS AND CI ONLY (Rule 21): the purges delete records that these tests did not make (every completed business-process instance
/// older than the fixture's, every decision, usage row and closed incident past its days), and the tests run the real tasks through the Task Manager.
/// OnBeforeAllTests seeds the fixtures of the purge rows, sets the stored DaysToKeep of the OcuTalon purge task to 60, runs the three tasks once with
/// RunNow (the two Interoperability purges together, then the OcuTalon purge, each waited for through its history row, ceiling RUNSECONDS) and puts DaysToKeep back; the purge tests then only read the
/// outcome. OnAfterAllTests removes every fixture that remains, the one in OCUORDERS included, and restores the tasks' settings. A missing OCUORDERS or a task
/// that did not run is a failure of every purge test, with the reason.
///   - TestStartDate: the declared StartDate at fixed clocks;
///   - TestDeclarations: Retention.Tasks() is exactly the three declarations, with no NameSpace, RunAsUser or Suspended, and the two item names are items of
///     OcuTalon.Production;
///   - TestNoSettingRead (AC 4): no purge code names OcuTalon.Data.Setting;
///   - TestCreatedOnce (matrix 1, 2): the start made one task of each name (counted in OnBeforeAllTests, before any test runs the Tasks step), with the
///     declared class, settings, schedule and namespace; the Tasks step run again leaves one of each, and recreates a deleted one as declared, the other
///     two keeping their ids;
///   - TestAdminChangesKept (matrix 3): the changed day counts and start time are kept by a later Tasks step;
///   - TestOwnNamespaceOnly (matrix 4): every run of every task was in OCUTALON (the Task Manager's history, read in OnBeforeAllTests) and the 92-day
///     message in OCUORDERS stays, with its body;
///   - TestMessagesPurge (matrix 5), TestAllPurge (matrix 6): the 7-day and the 90-day standard purges;
///   - TestOcuTalonPurge (matrix 7): the Task Manager's run of the OcuTalon purge task reaches Bridge.Purge and the Digest and Watch areas with the task's days;
///   - TestAuditUntouched (matrix 8), TestHistoryReadsTables (matrix 9: a decision whose trace session and an incident whose trace header are purged
///     are still read through Data.Ownership).
Class OcuTalon.Test.Install.Retention Extends %UnitTest.TestCase
{

/// The area under test.
Parameter AREA = "OcuTalon.Install.Step.Retention";

/// The namespace whose old message must stay.
Parameter ORDERS = "OCUORDERS";

/// The longest to wait for a task's history row, in seconds. A ceiling: the wait polls and returns as soon as the row exists.
Parameter RUNSECONDS = 180;

/// The seconds without a run after which RunNow is asked again for a task that has no job.
Parameter RETRYSECONDS = 60;

/// The stored DaysToKeep that the run of the OcuTalon purge task uses.
Parameter PURGEDAYS = 60;

/// The fixture's business-process class.
Parameter PROCESS = "OcuTalon.Test.Install.ZzRetentionProcess";

/// The test's own state, as a dynamic object: the ids of the fixtures and the outcome of the three runs.
Property Fx As %DynamicObject;

/// "" when the set-up worked, otherwise why it did not.
Property SetupProblem As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Fx = {"runs": {}, "errors": {}, "namespaces": {}, "started": {}}
	Set ..SetupProblem = ""
	Do ..RestoreAdmin()
	Do ..RestorePurgeSettings()
	Set names = ..Names()
	Set position = 0
	While $ListNext(names, position, name) {
		Do ..Fx.started.%Set(name, +..TaskCount(name))
	}
	Do ..Cleanup()
	Try {
		Do ..Seed()
		Do ..RunTasks()
	} Catch exception {
		Set ..SetupProblem = $Translate($SYSTEM.Status.GetErrorText(exception.AsStatus()), $Char(13, 10), "  ")
	}
	Do ..RestorePurgeSettings()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..RestoreAdmin()
	Do ..RestorePurgeSettings()
	Do ..Cleanup()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..RestoreAdmin()
	Quit $$$OK
}

/// The StartDate of the declared schedule at fixed clocks (Horolog values, day 66000): the same day while 03:00 is more than 300 s away, the next day from
/// 02:55:00 on, so that the first start is always ahead of the clock when the Task Manager saves the task.
Method TestStartDate()
{
	Set day = 66000
	Set cases = $ListBuild(0, 10499, 10500, 10799, 10800, 43200, 86399)
	Set expected = $ListBuild(day, day, day + 1, day + 1, day + 1, day + 1, day + 1)
	For i = 1:1:$ListLength(cases) {
		Set seconds = $List(cases, i)
		Set schedule = $ClassMethod(..#AREA, "Schedule", day_","_seconds)
		Do $$$AssertEquals(schedule.StartDate, $List(expected, i), "at "_seconds_" s of the day the first start is on day "_$List(expected, i))
		Do $$$AssertEquals(schedule.DailyStartTime, 10800, "and at 03:00")
	}
}

/// --- the declarations ---
/// Retention.Tasks() is the three declarations of AD-27, exactly.
Method TestDeclarations()
{
	Set tasks = $ClassMethod(..#AREA, "Tasks")
	Do $$$AssertEquals(tasks.%Size(), 3, "the area declares three tasks")
	Set names = ..Names()
	For i = 1:1:3 {
		Set entry = tasks.%Get(i - 1)
		Set name = $ListGet(names, i)
		Do $$$AssertEquals(entry.name, name, "task "_i_" is named "_name)
		Do $$$AssertTrue(entry.description '= "", name_": it has a description")
		Do $$$AssertEquals($Length(entry.description, $Char(10)), 1, name_": the description is one line")
		Do $$$AssertTrue($Length(entry.description) '> 100, name_": the description fits the 100 characters that the Task Manager keeps")
		Do $$$AssertNotTrue(entry.%IsDefined("NameSpace") || entry.task.%IsDefined("NameSpace") || entry.task.%IsDefined("RunAsUser") || entry.task.%IsDefined("Suspended"), name_": it names no namespace, user or suspension")
		Do $$$AssertEquals(..Schedule(entry.task), "0|1|0|10800|"_entry.task.StartDate_"|1", name_": the schedule is daily at 03:00, RescheduleOnStart 1")
		Do $$$AssertTrue(..FirstStartAhead(entry.task.StartDate), name_": the first start, "_entry.task.StartDate_" 03:00, is ahead of the clock and within a day and a half")
	}
	Set messages = tasks.%Get(0)
	Do $$$AssertEquals(messages.taskClass, "Ens.Util.Tasks.Purge", "the messages task is the standard purge")
	Do $$$AssertEquals(..SettingsText(messages.settings), "BodiesToo=1;KeepIntegrity=1;NumberOfDaysToKeep=7;TypesToPurge=messages;optionalMessageLimitToConfigItems=HeartbeatIn,Checks", "with its settings")
	Set all = tasks.%Get(1)
	Do $$$AssertEquals(all.taskClass, "Ens.Util.Tasks.Purge", "the all task is the standard purge")
	Do $$$AssertEquals(..SettingsText(all.settings), "BodiesToo=1;KeepIntegrity=1;NumberOfDaysToKeep=90;TypesToPurge=all", "with its settings")
	Set purge = tasks.%Get(2)
	Do $$$AssertEquals(purge.name, "OcuTalon purge", "the third task is the OcuTalon purge")
	Do $$$AssertEquals(purge.taskClass, "OcuTalon.Install.Task.Purge", "its class")
	Do $$$AssertEquals(..SettingsText(purge.settings), "DaysToKeep=90", "and its settings")

	Set items = ""
	Set production = ##class(Ens.Config.Production).%OpenId("OcuTalon.Production")
	Do $$$AssertTrue($IsObject(production), "OcuTalon.Production is defined")
	If $IsObject(production) {
		For i = 1:1:production.Items.Count() {
			Set items = items _ "," _ production.Items.GetAt(i).Name _ ","
		}
	}
	Set limit = $ListFromString($ClassMethod(..#AREA, "%GetParameter", "MESSAGEITEMS"))
	Do $$$AssertEquals($ListLength(limit), 2, "the messages task names two items")
	Set position = 0
	While $ListNext(limit, position, item) {
		Do $$$AssertTrue(items [ ("," _ item _ ","), item_" is an item of OcuTalon.Production")
	}
}

/// No purge reads a setting (AD-19, AD-27): the code of the purge task, the areas' purges, the bridge's purge and clock and the registry names OcuTalon.Data.Setting nowhere.
Method TestNoSettingRead()
{
	Set source = "OcuTalon.Test.Bridge.Source"
	Set pattern = "ocutalon\.data\.setting"
	Do $$$AssertTrue($ClassMethod(source, "Matches", $Char(9)_"Set days = ##class(OcuTalon.Data.Setting).Get(""PurgeDays"")", pattern), "the scanner flags a read of a setting")
	Do $$$AssertTrue('$ClassMethod(source, "Matches", "/// reads no OcuTalon.Data.Setting"_$Char(10)_$Char(9)_"Quit ##class(OcuTalon.Bridge.Purge).Run(days)", pattern), "and passes a comment line and a purge")
	For class = "OcuTalon.Install.Task.Purge", "OcuTalon.Install.Step.Retention", "OcuTalon.Install.Step.Watch", "OcuTalon.Install.Step.Digest", "OcuTalon.Bridge.Purge", "OcuTalon.Bridge.Time", "OcuTalon.Install.Registry", "OcuTalon.Digest.Data.Item" {
		Do $$$AssertStatusOK($ClassMethod(source, "Text", class, .text), class_" has source")
		Do $$$AssertEquals($ClassMethod(source, "Matches", text, pattern), 0, class_" names OcuTalon.Data.Setting nowhere")
	}
}

/// Matrix 1 and 2. The start made the three tasks; the Tasks step again leaves one of each and recreates a deleted one.
Method TestCreatedOnce()
{
	Set tasks = $ClassMethod(..#AREA, "Tasks")
	For i = 0:1:2 {
		Set entry = tasks.%Get(i)
		Do $$$AssertEquals(..Fx.started.%Get(entry.name), 1, entry.name_": the start made exactly one (counted before any test ran the step)")
		Do ..AssertTask(entry)
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Tasks).Run(), "the Tasks step runs")
	Set ids = ""
	For i = 0:1:2 {
		Set entry = tasks.%Get(i)
		Do $$$AssertEquals(..TaskCount(entry.name), 1, entry.name_": still one after the step")
		Set ids(i) = ##class(%SYS.Task).FindId(entry.name)
	}
	// an upgrade from a version with no such task: delete the Interoperability data task, run the step
	Set deleted = tasks.%Get(1).name
	Do $$$AssertStatusOK(##class(%SYS.Task).%DeleteId(ids(1)), "the task '"_deleted_"' is deleted")
	Do $$$AssertEquals(..TaskCount(deleted), 0, "it is gone")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Tasks).Run(), "the Tasks step runs again")
	For i = 0:1:2 {
		Set entry = tasks.%Get(i)
		Do $$$AssertEquals(..TaskCount(entry.name), 1, entry.name_": one after the upgrade")
		Do ..AssertTask(entry)
		If i '= 1 Do $$$AssertEquals(##class(%SYS.Task).FindId(entry.name), ids(i), entry.name_": it keeps its id")
	}
	Do $$$AssertNotEquals(##class(%SYS.Task).FindId(deleted), ids(1), "the deleted task is a new one")
}

/// Matrix 3. A day count and a start time that an admin changed are kept by a later Tasks step.
Method TestAdminChangesKept()
{
	Set names = ..Names()
	Set messages = $ListGet(names, 1), purge = $ListGet(names, 3), all = $ListGet(names, 2)
	Do ..SaveAdmin()
	Do ..ChangeTask(messages, "NumberOfDaysToKeep", 10)
	Do ..ChangeTask(purge, "DaysToKeep", 120)
	Do ..ChangeTask(all, "", "", 7200)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Tasks).Run(), "the Tasks step runs")
	Do $$$AssertEquals(..TaskSetting(messages, "NumberOfDaysToKeep"), 10, "NumberOfDaysToKeep 10 is kept")
	Do $$$AssertEquals(..TaskSetting(purge, "DaysToKeep"), 120, "DaysToKeep 120 is kept")
	Do $$$AssertEquals(..TaskField(all, "DailyStartTime"), 7200, "DailyStartTime 7200 is kept")
	Do ..RestoreAdmin()
	Do $$$AssertEquals(..TaskSetting(messages, "NumberOfDaysToKeep") _ "|" _ ..TaskSetting(purge, "DaysToKeep") _ "|" _ ..TaskField(all, "DailyStartTime"), "7|90|10800", "and the test put the declared values back")
}

/// --- the purge outcome (set-up in OnBeforeAllTests) ---
/// Matrix 4. Every declared task ran in OCUTALON, as the Task Manager's history of the runs records it, and the message in OCUORDERS is untouched.
Method TestOwnNamespaceOnly()
{
	If '..Ready() Quit
	Set names = ..Names()
	Set position = 0
	While $ListNext(names, position, name) {
		Do ..AssertRan(name)
		Do $$$AssertEquals(..Fx.namespaces.%Get(name), "OCUTALON", name_": every run of the task was in OCUTALON")
	}
	Do $$$AssertEquals(..HeaderState(..#ORDERS, "orders"), "1|1", "the 92-day message in "_..#ORDERS_" and its body are untouched")
	Do $$$AssertEquals(..HeaderState("OCUTALON", "msg92"), "0|0", "control: the 92-day message in OCUTALON is gone")
}

/// Matrix 5. The 7-day task purges the heartbeat and check messages and their bodies, and only those.
Method TestMessagesPurge()
{
	If '..Ready() Quit
	Do ..AssertRan($ListGet(..Names(), 1))
	Do $$$AssertEquals(..HeaderState("OCUTALON", "hb9"), "0|0", "HeartbeatIn to Checks, 9 days old: header and body are gone")
	Do $$$AssertEquals(..HeaderState("OCUTALON", "ck9"), "0|0", "Checks to IncidentManager, 9 days old: header and body are gone")
	Do $$$AssertEquals(..HeaderState("OCUTALON", "hb5"), "1|1", "HeartbeatIn to Checks, 5 days old: kept")
	Do $$$AssertEquals(..HeaderState("OCUTALON", "wc9"), "1|1", "WebChatIn to Conversation, 9 days old: kept")
}

/// Matrix 6. The 90-day task purges messages, business processes, rule logs and the event log older than 90 days and keeps the newer ones.
Method TestAllPurge()
{
	If '..Ready() Quit
	Do ..AssertRan($ListGet(..Names(), 2))
	Do $$$AssertEquals(..HeaderState("OCUTALON", "msg92"), "0|0", "a message 92 days old, with its body, is gone")
	Do $$$AssertEquals(..HeaderState("OCUTALON", "msg88"), "1|1", "one 88 days old is kept")
	Do $$$AssertEquals(..ObjectExists(..#PROCESS, "bp92"), 0, "a completed business-process instance 92 days old is gone")
	Do $$$AssertEquals(..ObjectExists(..#PROCESS, "bp88"), 1, "one 88 days old is kept")
	Do $$$AssertEquals(..ObjectExists("Ens.Rule.Log", "rule92"), 0, "a rule-log row 92 days old is gone")
	Do $$$AssertEquals(..ObjectExists("Ens.Rule.Log", "rule88"), 1, "one 88 days old is kept")
	Do $$$AssertEquals(..ObjectExists("Ens.Util.Log", "log92"), 0, "an event-log row 92 days old is gone")
	Do $$$AssertEquals(..ObjectExists("Ens.Util.Log", "log88"), 1, "one 88 days old is kept")
}

/// Matrix 7. The Task Manager's run of the OcuTalon purge task, with DaysToKeep 60, reaches the bridge and every area with 60.
Method TestOcuTalonPurge()
{
	If '..Ready() Quit
	Do ..AssertRan($ListGet(..Names(), 3))
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.Decision).RefIndexExists(..Fx.dec61) _ "|" _ ##class(OcuTalon.Test.Bridge.Purge).UsageExists(..Fx.use61), "0|0", "the decision and the usage row 61 days old are gone")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.Decision).RefIndexExists(..Fx.dec59) _ "|" _ ##class(OcuTalon.Test.Bridge.Purge).UsageExists(..Fx.use59), "1|1", "the ones 59 days old are kept")
	Do $$$AssertEquals(##class(OcuTalon.Data.Incident).RefIndexExists(..Fx.inc61), 0, "the incident closed 61 days ago is gone")
	Do $$$AssertEquals(##class(OcuTalon.Data.Incident).RefIndexExists(..Fx.inc59), 1, "the one closed 59 days ago is kept")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.Item).%ExistsId(..Fx.item61), 0, "the digest item 61 days old is gone")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.Item).%ExistsId(..Fx.item59), 1, "the one 59 days old is kept")
	Do $$$AssertEquals(##class(%AI.Agent.Session).%ExistsId(..Fx.session), 0, "the AI session that no link has named for two days is gone")
	Do $$$AssertEquals($Data(^OcuTalonBP.Unlinked(..Fx.session)), 0, "and so is its mark")
}

/// Matrix 8. The OcuTalon audit entry written before the runs is still there after them.
Method TestAuditUntouched()
{
	If '..Ready() Quit
	Do ..AssertRan($ListGet(..Names(), 1))
	Do ..AssertRan($ListGet(..Names(), 2))
	Do ..AssertRan($ListGet(..Names(), 3))
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..Fx.auditMark, "OcuTalon", "Settings", "Settings", ..Fx.auditMarker)
	Do $$$AssertEquals(entries.%Size(), 1, "the audit entry that carries the marker is still found after the three runs")
}

/// Matrix 9. After the messages are purged, the history is still read from the tables: a decision and an incident whose trace messages are gone.
Method TestHistoryReadsTables()
{
	If '..Ready() Quit
	Set names = ..Names()
	Set position = 0
	While $ListNext(names, position, name) {
		Do ..AssertRan(name)
	}
	Do $$$AssertEquals(..HeaderState("OCUTALON", "msg92"), "0|0", "the messages of the decision's trace session are gone")
	Do $$$AssertEquals(..HeaderState("OCUTALON", "ck9"), "0|0", "and the Checks message of the incident's trace")
	Set decision = ##class(OcuTalon.Data.Ownership).Decision(..Fx.dec59, ..Fx.owner, .sc)
	Do $$$AssertStatusOK(sc, "reading the decision is OK")
	Do $$$AssertTrue($IsObject(decision) && (decision.Ref = ..Fx.dec59), "the owner still reads the decision recorded 59 days ago")
	Set incident = ##class(OcuTalon.Data.Ownership).Incident(..Fx.inc30, ..Fx.owner, .sc)
	Do $$$AssertStatusOK(sc, "reading the incident is OK")
	Do $$$AssertTrue($IsObject(incident) && (incident.Ref = ..Fx.inc30), "and the incident closed and noticed 30 days ago")
}

/// --- set-up ---
/// Seeds the fixtures of the purge rows (4 to 9); every id is kept in Fx and every row is recorded for Cleanup.
Method Seed()
{
	If '##class(%SYS.Namespace).Exists(..#ORDERS) Throw ##class(%Exception.General).%New("Retention", 5001, , "The namespace "_..#ORDERS_" does not exist: the owner's rule (matrix 4) cannot be tested")
	Set ..Fx.owner = ##class(OcuTalon.Test.Data.Fixture).Session("zzretention")
	Do ..Track("refs", ..Fx.owner)
	// 4: a message in OCUORDERS
	Set ..Fx.orders = ..NewHeader(..#ORDERS, "ZzRetentionOrders", "ZzRetentionOrdersTarget", 92)
	// 5: the 7-day messages
	Set ..Fx.hb9 = ..NewHeader("OCUTALON", "HeartbeatIn", "Checks", 9)
	Set ..Fx.hb5 = ..NewHeader("OCUTALON", "HeartbeatIn", "Checks", 5)
	Set ..Fx.ck9 = ..NewHeader("OCUTALON", "Checks", "IncidentManager", 9)
	Set ..Fx.wc9 = ..NewHeader("OCUTALON", "WebChatIn", "Conversation", 9)
	// 6: the 90-day data; the older process instance is saved first, so that the newer one gets the higher id
	Set ..Fx.msg92 = ..NewHeader("OCUTALON", "ZzRetention", "ZzRetentionTarget", 92)
	Set ..Fx.msg88 = ..NewHeader("OCUTALON", "ZzRetention", "ZzRetentionTarget", 88)
	Set ..Fx.bp92 = ..NewProcess(92)
	Set ..Fx.bp88 = ..NewProcess(88)
	Set ..Fx.rule92 = ..NewRule(92)
	Set ..Fx.rule88 = ..NewRule(88)
	Set ..Fx.log92 = ..NewLog(92)
	Set ..Fx.log88 = ..NewLog(88)
	// 7: the records of the OcuTalon purge task, 61 and 59 days old
	Set owner = ..Fx.owner
	Set ..Fx.dec61 = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, "decide", ..Utc(61))
	Set ..Fx.dec59 = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, "decide", ..Utc(59), {"TraceSessionId": (..Fx.msg92)})
	Set ..Fx.use61 = ##class(OcuTalon.Test.Data.Fixture).Usage(##class(OcuTalon.Bridge.Ids).NewRef(), owner, {"RecordedAt": (..Utc(61))})
	Set ..Fx.use59 = ##class(OcuTalon.Test.Data.Fixture).Usage(##class(OcuTalon.Bridge.Ids).NewRef(), owner, {"RecordedAt": (..Utc(59))})
	Set ..Fx.inc61 = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, ..Utc(61), "ZZNS", "Zz.Retention61", {"State": "closed", "OpenVariant": "", "ClosedAt": (..Utc(61))})
	Set ..Fx.inc59 = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, ..Utc(59), "ZZNS", "Zz.Retention59", {"State": "closed", "OpenVariant": "", "ClosedAt": (..Utc(59))})
	Do ..Track("refs", ..Fx.dec61)
	Do ..Track("refs", ..Fx.dec59)
	Do ..Track("refs", ..Fx.use61)
	Do ..Track("refs", ..Fx.use59)
	Do ..Track("refs", ..Fx.inc61)
	Do ..Track("refs", ..Fx.inc59)
	// 9: an incident closed and noticed 30 days ago whose trace is the 9-day Checks message (a header that is its own session)
	Set ..Fx.inc30 = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, ..Utc(30), "ZZNS", "Zz.Retention30", {"State": "closed", "OpenVariant": "", "ClosedAt": (..Utc(30)), "TraceHeaderId": (..Fx.ck9)})
	Do ..Track("refs", ..Fx.inc30)
	// 7: digest items
	Set sessionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Track("digest", sessionRef)
	Set row = ##class(OcuTalon.Test.Digest.Store).NewRow(sessionRef, ##class(OcuTalon.Bridge.Ids).NewRef(), ..Utc(61), .sc)
	$$$ThrowOnError(sc)
	Set ..Fx.item61 = row.%Id()
	Set row = ##class(OcuTalon.Test.Digest.Store).NewRow(sessionRef, ##class(OcuTalon.Bridge.Ids).NewRef(), ..Utc(59), .sc)
	$$$ThrowOnError(sc)
	Set ..Fx.item59 = row.%Id()
	// 7: an AI session that no link names and that an earlier run marked two days ago
	Set session = ##class(%AI.Agent.Session).%New()
	Set session.Model = "zz-retention"
	$$$ThrowOnError(session.%Save())
	Set ..Fx.session = session.%Id()
	Do ..Track("session", ..Fx.session)
	Set ^OcuTalonBP.Unlinked(..Fx.session) = ..Utc(2)
	// 8: an audit entry, written only through Bridge.Audit
	Set ..Fx.auditMarker = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Fx.auditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set data = {"setting": "ZzRetention", "from": (..Fx.auditMarker), "to": "b", "irisUser": "ocutalon", "sessionRef": (..Fx.auditMarker), "channel": "web"}
	$$$ThrowOnError(##class(OcuTalon.Bridge.Audit).Record("Settings", data))
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(..Fx.auditMark, "OcuTalon", "Settings", "Settings", ..Fx.auditMarker)
	If entries.%Size() '= 1 Throw ##class(%Exception.General).%New("Retention", 5001, , "The audit entry that carries the marker was not found before the runs")
}

/// Sets the stored DaysToKeep of the OcuTalon purge task to PURGEDAYS, runs the three tasks (the two Interoperability purges together, then the OcuTalon purge),
/// waits for each task's history row (ceiling RUNSECONDS each) and puts DaysToKeep back (RestorePurgeSettings, which the caller runs on every path).
Method RunTasks()
{
	Set names = ..Names()
	Set purge = $ListGet(names, 3)
	Set position = 0
	While $ListNext(names, position, name) {
		If ##class(%SYS.Task).FindId(name) = "" Throw ##class(%Exception.General).%New("Retention", 5001, , "The task '"_name_"' does not exist: the Tasks step of the start did not create it")
	}
	Set task = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(purge))
	Set ^OcuTalonTest("Retention", "settings") = task.Settings
	Set task.Settings = ..WithSetting(task.Settings, "DaysToKeep", ..#PURGEDAYS)
	$$$ThrowOnError(task.%Save())
	Kill task
	Set mark = ..HistoryMark()
	// the two Interoperability purges run first and together; the OcuTalon purge runs after them, so that the records it keeps are read with the messages gone (matrix 9)
	Do ..RunAndWait($ListBuild($ListGet(names, 1), $ListGet(names, 2)), mark)
	Do ..RunAndWait($ListBuild(purge), mark)
}

/// RunNow for each task, then waits for each task's history row after the mark and keeps in Fx the number of runs, of failed runs and the namespaces
/// that the runs were in.
Method RunAndWait(names As %List, mark As %Integer)
{
	Set position = 0
	While $ListNext(names, position, name) {
		$$$ThrowOnError(##class(%SYS.Task).RunNow(##class(%SYS.Task).FindId(name)))
	}
	Set position = 0
	While $ListNext(names, position, name) {
		Do ..Fx.runs.%Set(name, ..WaitRun(name, mark))
		Do ..Fx.errors.%Set(name, ..RunErrors(name, mark))
		Do ..Fx.namespaces.%Set(name, ..RunNamespaces(name, mark))
		If ..Fx.runs.%Get(name) = 0 Do ..Fx.%Set("state "_name, ..TaskState(name))
	}
}

/// Waits, up to RUNSECONDS, until the history holds a run of the task after the mark, and asks for the run again every RETRYSECONDS while the task
/// has neither a run nor a job. The number of runs.
Method WaitRun(name As %String, mark As %Integer) As %Integer
{
	Set deadline = $ZHorolog + ..#RUNSECONDS
	Set again = $ZHorolog + ..#RETRYSECONDS
	While (..Runs(name, mark) = 0) && ($ZHorolog < deadline) {
		If $ZHorolog > again {
			Set again = $ZHorolog + ..#RETRYSECONDS
			Set id = ##class(%SYS.Task).FindId(name)
			Set task = $Select(id = "": "", 1: ##class(%SYS.Task).%OpenId(id))
			If $IsObject(task) && (task.RunningJobNumber = "") Do ##class(%SYS.Task).RunNow(id)
		}
		Hang 1
	}
	Quit ..Runs(name, mark)
}

/// The Task Manager's account of the task as text, for the message of a failed assertion.
ClassMethod TaskState(name As %String) As %String
{
	Set id = ##class(%SYS.Task).FindId(name)
	If id = "" Quit " (the task is gone)"
	Set task = ##class(%SYS.Task).%OpenId(id)
	Quit " (status "_task.DisplayStatus_", suspended "_task.Suspended_", job '"_task.RunningJobNumber_"', last started "_task.LastStarted_", last finished "_task.LastFinished_", next "_task.DisplayNextScheduled_")"
}

/// Puts the stored settings of the OcuTalon purge task back after RunTasks changed them.
ClassMethod RestorePurgeSettings()
{
	If '$Data(^OcuTalonTest("Retention", "settings")) Quit
	Set id = ##class(%SYS.Task).FindId($ListGet(..Names(), 3))
	If id '= "" {
		Set task = ##class(%SYS.Task).%OpenId(id)
		Set task.Settings = ^OcuTalonTest("Retention", "settings")
		Do task.%Save()
	}
	Kill ^OcuTalonTest("Retention", "settings")
}

/// Removes every fixture that was recorded, in OCUTALON and in OCUORDERS, then the record.
ClassMethod Cleanup()
{
	Set ns = ""
	For {
		Set ns = $Order(^OcuTalonTest("Retention", "header", ns))
		Quit:ns=""
		Set id = ""
		For {
			Set id = $Order(^OcuTalonTest("Retention", "header", ns, id), 1, body)
			Quit:id=""
			Do ..DeleteHeader(ns, id, $List(body, 1), $List(body, 2))
		}
	}
	Set class = ""
	For {
		Set class = $Order(^OcuTalonTest("Retention", "object", class))
		Quit:class=""
		Set id = ""
		For {
			Set id = $Order(^OcuTalonTest("Retention", "object", class, id))
			Quit:id=""
			Do $ClassMethod(class, "%DeleteId", id)
		}
	}
	Set refs = ""
	Set ref = ""
	For {
		Set ref = $Order(^OcuTalonTest("Retention", "refs", ref))
		Quit:ref=""
		Set refs = refs _ "," _ ref
	}
	If refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(refs)
	Set ref = ""
	For {
		Set ref = $Order(^OcuTalonTest("Retention", "digest", ref))
		Quit:ref=""
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.Item WHERE SessionRef = ?", ref)
	}
	Set id = ""
	For {
		Set id = $Order(^OcuTalonTest("Retention", "session", id))
		Quit:id=""
		Do ##class(%AI.Agent.Session).%DeleteId(id)
		Kill ^OcuTalonBP.Unlinked(id)
	}
	Kill ^OcuTalonTest("Retention", "header"), ^OcuTalonTest("Retention", "object"), ^OcuTalonTest("Retention", "refs"), ^OcuTalonTest("Retention", "digest"), ^OcuTalonTest("Retention", "session")
}

/// Records a fixture for Cleanup: a kind (refs, digest, session) and its key.
ClassMethod Track(kind As %String, key As %String)
{
	Set ^OcuTalonTest("Retention", kind, key) = ""
}

/// A completed message header with a body, created that many days ago (a UTC time stamp) in the namespace; its id. The header is its own session, so
/// that an old session is done as a whole. It switches namespace only to save the two rows, calling nothing but Ens classes there.
ClassMethod NewHeader(ns As %String, source As %String, target As %String, days As %Integer) As %String
{
	Set stamp = ..Stamp(days)
	Set id = ..SaveHeader(ns, source, target, stamp, .bodyId)
	Set ^OcuTalonTest("Retention", "header", ns, id) = $ListBuild("Ens.StringRequest", bodyId)
	Quit id
}

/// The part of NewHeader that runs in the namespace.
ClassMethod SaveHeader(ns As %String, source As %String, target As %String, stamp As %String, Output bodyId As %String) As %String [ Private ]
{
	New $Namespace
	If ns '= $Namespace Set $Namespace = ns
	Set body = ##class(Ens.StringRequest).%New()
	Set body.StringValue = "zz retention"
	$$$ThrowOnError(body.%Save())
	Set bodyId = body.%Id()
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.TimeCreated = stamp
	Set header.TimeProcessed = stamp
	Set header.SourceConfigName = source
	Set header.TargetConfigName = target
	Set header.Type = 1
	Set header.Status = 9
	Set header.MessageBodyClassName = "Ens.StringRequest"
	Set header.MessageBodyId = bodyId
	$$$ThrowOnError(header.%Save())
	Set header.SessionId = header.%Id()
	$$$ThrowOnError(header.%Save())
	Quit header.%Id()
}

/// Deletes the header and its body in the namespace, if they exist.
ClassMethod DeleteHeader(ns As %String, id As %String, bodyClass As %String, bodyId As %String)
{
	New $Namespace
	If ns '= $Namespace Set $Namespace = ns
	If bodyId '= "" Do $ClassMethod(bodyClass, "%DeleteId", bodyId)
	Do ##class(Ens.MessageHeader).%DeleteId(id)
}

/// "header|body": whether the header and its body of the fixture (key in Fx) exist, 1 or 0 each.
Method HeaderState(ns As %String, key As %String) As %String
{
	Set id = ..Fx.%Get(key)
	Set bodyId = $List(^OcuTalonTest("Retention", "header", ns, id), 2)
	Quit ..StateIn(ns, id, bodyId)
}

ClassMethod StateIn(ns As %String, id As %String, bodyId As %String) As %String [ Private ]
{
	New $Namespace
	If ns '= $Namespace Set $Namespace = ns
	Quit ##class(Ens.MessageHeader).%ExistsId(id) _ "|" _ ##class(Ens.StringRequest).%ExistsId(bodyId)
}

/// A completed business-process instance created that many days ago; its id.
ClassMethod NewProcess(days As %Integer) As %String
{
	Set process = $ClassMethod(..#PROCESS, "%New", "ZzRetention")
	Set process.%TimeCreated = ..Stamp(days)
	Set process.%IsCompleted = 1
	$$$ThrowOnError(process.%Save())
	Set ^OcuTalonTest("Retention", "object", ..#PROCESS, process.%Id()) = ""
	Quit process.%Id()
}

/// A rule-log row executed that many days ago; its id.
ClassMethod NewRule(days As %Integer) As %String
{
	Set row = ##class(Ens.Rule.Log).%New()
	Set row.SessionId = 0
	Set row.TimeExecuted = ..Stamp(days)
	Set row.RuleName = "ZzRetentionRule"
	$$$ThrowOnError(row.%Save())
	Set ^OcuTalonTest("Retention", "object", "Ens.Rule.Log", row.%Id()) = ""
	Quit row.%Id()
}

/// An event-log row logged that many days ago; its id.
ClassMethod NewLog(days As %Integer) As %String
{
	Set row = ##class(Ens.Util.Log).%New()
	Set row.Type = 4
	Set row.SourceClass = "OcuTalon.Test.Install.Retention"
	Set row.Text = "zz retention"
	Set row.ConfigName = "ZzRetention"
	Set row.TimeLogged = ..Stamp(days)
	$$$ThrowOnError(row.%Save())
	Set ^OcuTalonTest("Retention", "object", "Ens.Util.Log", row.%Id()) = ""
	Quit row.%Id()
}

/// 1 when the row of the class that the fixture (key in Fx) names exists.
Method ObjectExists(class As %String, key As %String) As %Boolean
{
	Quit $ClassMethod(class, "%ExistsId", ..Fx.%Get(key))
}

/// A UTC time stamp as the Interoperability classes hold it, YYYY-MM-DD hh:mm:ss.fff, that many days ago.
ClassMethod Stamp(days As %Integer) As %String
{
	Set now = $ZTimeStamp
	Quit $ZDateTime(($Piece(now, ",", 1) - days) _ "," _ $Piece(now, ",", 2), 3, , 3)
}

/// A UTC time as the product holds it, YYYY-MM-DDThh:mm:ssZ, that many days ago.
ClassMethod Utc(days As %Integer) As %String
{
	Quit ##class(OcuTalon.Bridge.Time).PlusSeconds(##class(OcuTalon.Bridge.Time).NowUtc(), -days * 86400)
}

/// --- the tasks ---
/// The three task names, in the order of the declarations: the messages task, the all task and the OcuTalon purge.
ClassMethod Names() As %List
{
	Set tasks = $ClassMethod(..#AREA, "Tasks")
	Set names = ""
	For i = 0:1:tasks.%Size() - 1 {
		Set names = names _ $ListBuild(tasks.%Get(i).name)
	}
	Quit names
}

ClassMethod TaskCount(name As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM %SYS.Task WHERE Name = ?", name)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The value of a field of the stored task.
ClassMethod TaskField(name As %String, field As %String) As %String
{
	Set task = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(name))
	Quit $Property(task, field)
}

/// The value of a setting of the stored task, or "" when it holds none.
ClassMethod TaskSetting(name As %String, setting As %String) As %String
{
	Set task = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(name))
	Set position = $ListFind(task.Settings, setting)
	Quit $Select(position: $List(task.Settings, position + 1), 1: "")
}

/// The settings list with the setting set to the value (added when it is not there).
ClassMethod WithSetting(settings As %List, setting As %String, value As %String) As %List
{
	Set position = $ListFind(settings, setting)
	If position Quit $List(settings, 1, position) _ $ListBuild(value) _ $List(settings, position + 2, *)
	Quit settings _ $ListBuild(setting, value)
}

/// The declared schedule of an entry's task object: TimePeriod|TimePeriodEvery|DailyFrequency|DailyStartTime|StartDate|RescheduleOnStart.
ClassMethod Schedule(task As %DynamicObject) As %String
{
	Quit task.TimePeriod _ "|" _ task.TimePeriodEvery _ "|" _ task.DailyFrequency _ "|" _ task.DailyStartTime _ "|" _ task.StartDate _ "|" _ task.RescheduleOnStart
}

/// 1 when 03:00 of the date, a Horolog day number, is ahead of the clock by less than a day and a half (a task created at any time of day starts at the next 03:00).
ClassMethod FirstStartAhead(date As %Integer) As %Boolean
{
	Set now = $Horolog
	Set ahead = ((date - $Piece(now, ",", 1)) * 86400) + 10800 - $Piece(now, ",", 2)
	Quit (ahead > 0) && (ahead '> 129600)
}

/// A declaration's settings as sorted text, name=value;name=value.
ClassMethod SettingsText(settings As %DynamicObject) As %String
{
	Kill pairs
	Set iterator = settings.%GetIterator()
	While iterator.%GetNext(.name, .value) {
		Set pairs(name) = value
	}
	Set text = ""
	Set name = ""
	For {
		Set name = $Order(pairs(name), 1, value)
		Quit:name=""
		Set text = text _ $Select(text = "": "", 1: ";") _ name _ "=" _ value
	}
	Quit text
}

/// The stored task is what the entry declares: class, namespace, schedule and settings.
Method AssertTask(entry As %DynamicObject)
{
	Set name = entry.name
	Set task = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(name))
	If '$IsObject(task) {
		Do $$$AssertTrue(0, name_": the task exists")
		Quit
	}
	Do $$$AssertEquals(task.TaskClass, entry.taskClass, name_": the task class")
	Do $$$AssertEquals(task.NameSpace, "OCUTALON", name_": the task runs in OCUTALON")
	Do $$$AssertEquals(task.Description, entry.description, name_": the description")
	Do $$$AssertEquals(task.TimePeriod _ "|" _ task.TimePeriodEvery _ "|" _ task.DailyFrequency _ "|" _ task.DailyStartTime _ "|" _ task.RescheduleOnStart, "0|1|0|10800|1", name_": the task is daily at 03:00 with RescheduleOnStart 1")
	Do $$$AssertTrue((task.StartDate '< (+$Horolog - 3)) && (task.StartDate '> (+$Horolog + 1)), name_": it starts today or tomorrow: "_task.StartDate)
	Set iterator = entry.settings.%GetIterator()
	While iterator.%GetNext(.setting, .value) {
		Do $$$AssertEquals(..TaskSetting(name, setting), value, name_": the setting "_setting)
	}
}

/// Changes a setting (when it is named) and the start time (when it is given) of the stored task. A new start time moves the StartDate to tomorrow,
/// as an admin would: the Task Manager refuses a change of DailyStartTime whose first start is not ahead of the clock (ERROR #7432), which a start
/// time of 02:00 on a StartDate of today is from 02:00 on. A change of the settings alone is accepted at any time.
Method ChangeTask(name As %String, setting As %String = "", value As %String = "", startTime As %String = "")
{
	Set task = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(name))
	If setting '= "" Set task.Settings = ..WithSetting(task.Settings, setting, value)
	If startTime '= "" Set task.DailyStartTime = startTime, task.StartDate = +$Horolog + 1
	Do $$$AssertStatusOK(task.%Save(), name_": the task is changed by hand")
}

/// Records the stored settings and start time of the three tasks, so that RestoreAdmin can put them back, also after a failure.
Method SaveAdmin()
{
	Set names = ..Names()
	Set position = 0
	While $ListNext(names, position, name) {
		Set task = ##class(%SYS.Task).%OpenId(##class(%SYS.Task).FindId(name))
		Set ^OcuTalonTest("Retention", "admin", name) = $ListBuild(task.Settings, task.DailyStartTime)
	}
}

/// Puts back what SaveAdmin recorded.
ClassMethod RestoreAdmin()
{
	Set name = ""
	For {
		Set name = $Order(^OcuTalonTest("Retention", "admin", name), 1, was)
		Quit:name=""
		Set id = ##class(%SYS.Task).FindId(name)
		If id '= "" {
			Set task = ##class(%SYS.Task).%OpenId(id)
			Set task.Settings = $List(was, 1)
			Set task.DailyStartTime = $List(was, 2)
			Do task.%Save()
		}
	}
	Kill ^OcuTalonTest("Retention", "admin")
}

/// --- the Task Manager's history ---
/// The highest id of the Task Manager's history: the mark that WaitRun and RunErrors read from. Name-keyed copies of Test.Schedule.Heartbeat's
/// HistoryMark, RunsWhere, Runs and RunErrors, which are Lane B's and keyed to the heartbeat task.
ClassMethod HistoryMark() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM %SYS_Task.History")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The condition that picks the runs of the task after a history mark, not the Task Manager's own note that a task expired.
ClassMethod RunsWhere() As %String [ Private ]
{
	Quit "ID > ? AND Name = ? AND (Error IS NULL OR UPPER(Error) NOT LIKE 'TASK HAS EXPIRED%')"
}

/// The number of runs of the task in the history after the mark.
ClassMethod Runs(name As %String, mark As %Integer) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM %SYS_Task.History WHERE "_..RunsWhere(), mark, name)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The number of those runs that ended in an error: a status that is not OK or an untrapped error.
ClassMethod RunErrors(name As %String, mark As %Integer) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM %SYS_Task.History WHERE "_..RunsWhere()_" AND ((Status <> '1') OR (ER IS NOT NULL AND ER <> ''))", mark, name)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The namespaces that the runs of the task after the mark were in, as the history records them: a comma list, in name order, "" with no run.
ClassMethod RunNamespaces(name As %String, mark As %Integer) As %String
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT %EXACT(NameSpace) FROM %SYS_Task.History WHERE "_..RunsWhere()_" ORDER BY 1", mark, name)
	Set list = ""
	While result.%Next() {
		Set list = list _ $Select(list = "": "", 1: ",") _ result.%GetData(1)
	}
	Quit list
}

/// 1 when the set-up worked; otherwise a failed assertion that says why.
Method Ready() As %Boolean
{
	Do $$$AssertEquals(..SetupProblem, "", "the set-up of the purge runs worked")
	Quit ..SetupProblem = ""
}

/// The task ran once or more after the mark, and its history has no error.
Method AssertRan(name As %String)
{
	Do $$$AssertTrue(..Fx.runs.%Get(name) > 0, name_": the Task Manager ran the task"_..Fx.%Get("state "_name))
	Do $$$AssertEquals(..Fx.errors.%Get(name), 0, name_": its history has no error")
}

}
