/// Live tests of what a web request reads about the model key and the daily cap (DW-149; AD-6, AD-19, AD-20, AD-24, AD-28; FR-38).
/// THROWAWAY STACKS AND CI ONLY (Rule 21): they create and delete a security user, switch the audit event %System/%Security/AccessDenied
/// for their run, and restart the runners of the running OcuTalon.Production. They need that production and no model mock.
/// A job logs in (the one-argument $SYSTEM.Security.Login) as a fixture user whose roles are exactly the application roles of
/// Install.Step.Web (APPLICATIONROLES, parsed), which is the context of Epic 2's /state: the roles of the code, data and private
/// databases, and no %Admin_ConfigStore. Probe is that job. A control in the job shows that its roles are those, that it cannot read the
/// Config Store, and that a read of an entry is refused.
///   - TestMissingReadsMissing: with no model key (ANTHROPIC_API_KEY unset, the entries at the placeholder of the Provider step, the
///     runners restarted) Keys.Status of each runner is exactly 0, Keys.Present of the TriageAgent ProviderConfig is 0 and so is
///     Keys.Absent of TriageAgent, whose reference to an entry the job cannot read is not judged; the job's
///     user has exactly one %System/%Security/AccessDenied row since the mark, the control's, so the reads attempt no Config Store
///     read (the audit event is switched on for the run when it is off, and put back); with a daily cap set (the row is put back),
///     Budget.State returns spent, cap, capped and resetsAt, names the Usage line and no other in faults, and logs no warning, while
///     the test process, which holds the SQL privilege, gets no Usage line;
///   - TestPresentReadsPresent: with the entries pointed at OCUTALON_MOCK_KEY_HEADER (RunnerFixture.PointKeys, which restarts the runners)
///     Keys.Status of each runner is exactly 1 in the job;
///   - TestStoppedRunnerReadsMissing: with the entries pointed, a runner that is stopped (Ens.Director.TempStopConfigItem) reads 0 while
///     the other two read 1, and it reads 1 again after it is started.
/// Each test starts from the state it needs (the entries and the restarts), creates its own fixture user, and removes it. OnAfterAllTests
/// puts the entries back to the placeholder of the Provider step (RestoreKeys) and fails when they are not there.
Class OcuTalon.Test.Bridge.WebStatus Extends %UnitTest.TestCase
{

/// The fixture users' prefix: users with it are deleted before and after the run.
Parameter USER = "ZzWebStatus";

/// The variable that holds the key of the Provider step's entries.
Parameter KEYVARIABLE = "ANTHROPIC_API_KEY";

/// The audit event of a refused read.
Parameter EVENT = "%System/%Security/AccessDenied";

/// The longest the parent waits for the job's report, in seconds.
Parameter JOBSECONDS = 60;

/// The longest the parent waits for the audit row of the control to be readable, in seconds.
Parameter AUDITSECONDS = 120;

/// The daily cost cap that TestMissingReadsMissing sets, in US dollars: above 0, so that State would list the unpriced models.
Parameter CAP = 5;

/// The run's number.
Property Number As %Integer;

/// The state of the audit event before the run switched it on: "1", "0" or "", when the test left it as it was.
Property EventWas As %String;

/// 1 while a test has stopped TriageAgent and has not started it again.
Property Stopped As %Boolean [ InitialExpression = 0 ];

/// The System Default Settings rows that a test changed, for OnAfterOneTest (RunnerFixture.RememberDefault).
Property Saved As %List;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("WebStatus", "n"))
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	If $ClassMethod(fixture, "RunningReason") '= "" Quit $$$OK
	Set placeholder = ##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER
	If $ClassMethod(fixture, "KeysAre", placeholder) Quit $$$OK
	Set sc = $ClassMethod(fixture, "RestoreKeys")
	If $$$ISERR(sc) Quit sc
	If '$ClassMethod(fixture, "KeysAre", placeholder) Quit $SYSTEM.Status.Error(5001, "The entries of the runners are not at the placeholder of the Provider step after RestoreKeys")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Clean()
	If ..Stopped {
		Set ..Stopped = 0
		Do ##class(Ens.Director).TempStopConfigItem(..Production()_"||TriageAgent", 0)
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).WaitAllRun()
	}
	If ..EventWas '= "" {
		Do ..SetEvent(..EventWas)
		Set ..EventWas = ""
	}
	If ..Saved '= "" {
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..Saved)
		Set ..Saved = ""
	}
	Quit $$$OK
}

/// With no model key, a process that holds only the application roles reads each runner as having no key, attempts no Config Store read,
/// and gets a budget state that says what it could not count.
Method TestMissingReadsMissing()
{
	If '..Ready() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	If $SYSTEM.Util.GetEnviron(..#KEYVARIABLE) '= "" {
		Do $$$AssertTrue(0, ..#KEYVARIABLE_" is set in this container: this test is for CI's default of no model key")
		Quit
	}
	If '..SetupKeys(##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER, 0) Quit
	If '..EventOn() Quit
	Set config = ..ProviderConfigOf("TriageAgent")
	Set entry = ##class(OcuTalon.Bridge.ConfigStore).EntryOf(config)
	Do $$$AssertNotEquals(entry, "", "control: the ProviderConfig of TriageAgent names a Config Store entry: "_config)
	Set saved = ""
	Do $ClassMethod(fixture, "RememberDefault", .saved, "Decide", "DailyCostCapUSD")
	Set ..Saved = saved
	Do $$$AssertStatusOK($ClassMethod(fixture, "PutDefault", "Decide", "DailyCostCapUSD", ..#CAP), "a daily cost cap of "_..#CAP_" is set, so that State would list the unpriced models")
	Do ##class(OcuTalon.Bridge.Budget).State(, .ownFaults)
	Do $$$AssertEquals(..UsageLine(ownFaults), 0, "control: the test process holds the SQL privilege on Usage, so its State has no Usage line")
	Set user = ..NewUser("m")
	If user = "" Quit
	Set auditMark = ..AuditMark()
	Set logMark = $ClassMethod(fixture, "EventMark")
	Set run = ..RunProbe("missing", user, entry, config)
	If run = "" Quit
	Do ..AssertContext(run, user)

	// the read
	Set runners = $ListFromString(##class(OcuTalon.Test.Agent.RunnerFixture).#RUNNERS)
	Set position = 0
	While $ListNext(runners, position, item) {
		Do $$$AssertEquals($Get(@run@("status", item)), 0, "Keys.Status of "_item_" is exactly 0 in the job")
	}
	Do $$$AssertEquals($Get(@run@("present")), 0, "Keys.Present of the ProviderConfig of TriageAgent is exactly 0 in the job")
	Do $$$AssertEquals($Get(@run@("absent")), 0, "Keys.Absent of TriageAgent is exactly 0 in the job: a reference that it cannot read is not judged absent")

	// no Config Store read: the control's row is the only one
	Set deadline = $ZHorolog + ..#AUDITSECONDS
	While (..AuditRows(user, auditMark) < 1) && ($ZHorolog < deadline) {
		Hang 2
	}
	Hang 3
	Set rows = ..AuditRows(user, auditMark)
	Do $$$AssertTrue(rows > 0, "control: the row of the refused read of the control is readable in %SYS.Audit")
	Do $$$AssertEquals(rows, 1, "the job's user has exactly one AccessDenied row since the mark, the control's")

	// the budget
	Set budget = {}.%FromJSON($Get(@run@("budget")))
	For field = "spent", "cap", "capped", "resetsAt" {
		Do $$$AssertTrue(budget.%IsDefined(field), "Budget.State in the job has "_field)
	}
	Do $$$AssertEquals(budget.%Get("cap"), ..#CAP, "and reads the daily cost cap that was set")
	Set faults = {}.%FromJSON($Get(@run@("faults")))
	Do $$$AssertEquals(faults.%Size(), 1, "and names one fault")
	Do $$$AssertTrue(faults.%Get(0) [ "The Usage rows of the day cannot be read in this process", "the Usage line: "_faults.%Get(0))
	Do $$$AssertEquals($ClassMethod(fixture, "WarningRows", logMark, "", "OcuTalon.Bridge.Budget"), 0, "and no warning of Budget is in the event log since the mark")
}

/// With the entries pointed at a variable that is set, the job reads each runner as having a key.
Method TestPresentReadsPresent()
{
	If '..Ready() Quit
	If '..SetupKeys("@{env:"_##class(OcuTalon.Test.Agent.RunnerFixture).#MOCKKEYVARIABLE_"}", 1) Quit
	Set config = ..ProviderConfigOf("TriageAgent")
	Set entry = ##class(OcuTalon.Bridge.ConfigStore).EntryOf(config)
	Set user = ..NewUser("p")
	If user = "" Quit
	Set run = ..RunProbe("present", user, entry, config)
	If run = "" Quit
	Do ..AssertContext(run, user)
	Set runners = $ListFromString(##class(OcuTalon.Test.Agent.RunnerFixture).#RUNNERS)
	Set position = 0
	While $ListNext(runners, position, item) {
		Do $$$AssertEquals($Get(@run@("status", item)), 1, "Keys.Status of "_item_" is exactly 1 in the job")
	}
}

/// A runner that is stopped reads as having no key until it runs again; the others keep reading 1.
Method TestStoppedRunnerReadsMissing()
{
	If '..Ready() Quit
	If '..SetupKeys("@{env:"_##class(OcuTalon.Test.Agent.RunnerFixture).#MOCKKEYVARIABLE_"}", 1) Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set keys = "OcuTalon.Bridge.Keys"
	Set name = ..Production()_"||TriageAgent"
	Do $$$AssertEquals($ClassMethod(keys, "Status", "TriageAgent"), 1, "control: TriageAgent reads 1 while it runs")
	Set ..Stopped = 1
	Do $$$AssertStatusOK(##class(Ens.Director).TempStopConfigItem(name, 1), "TriageAgent is stopped")
	Set deadline = $ZHorolog + ..#JOBSECONDS
	While $ListLength($ClassMethod(fixture, "Jobs", "TriageAgent")) && ($ZHorolog < deadline) {
		Hang 1
	}
	Do $$$AssertEquals($ListLength($ClassMethod(fixture, "Jobs", "TriageAgent")), 0, "and has no job")
	Do $$$AssertEquals($ClassMethod(keys, "Status", "TriageAgent"), 0, "Keys.Status of TriageAgent is exactly 0 while it is stopped")
	Do $$$AssertEquals($ClassMethod(keys, "Status", "DiagnosisAgent"), 1, "and DiagnosisAgent still reads 1")
	Do $$$AssertEquals($ClassMethod(keys, "Status", "ChatAgent"), 1, "and ChatAgent too")
	Do $$$AssertStatusOK(##class(Ens.Director).TempStopConfigItem(name, 0), "TriageAgent is started again")
	Set ..Stopped = 0
	Do $$$AssertTrue($ClassMethod(fixture, "WaitAllRun"), "every item runs")
	Do $$$AssertTrue($ClassMethod(fixture, "WaitRecord", "TriageAgent"), "TriageAgent has recorded its state")
	Do $$$AssertEquals($ClassMethod(keys, "Status", "TriageAgent"), 1, "Keys.Status of TriageAgent is exactly 1 again")
}

/// The job: logs in as the user, then reads what a web request reads, and reports it under ^OcuTalonTest("WebStatus", number): login (the
/// result of Login), user, roles, canReadEntries (Check of %Admin_ConfigStore:USE), status(<runner>), present (Keys.Present of
/// configText), absent (Keys.Absent of TriageAgent), budget and faults (Budget.State as JSON), job (its number), and controlRefused (1 when GetDetails of the entry is
/// refused, which writes the one AccessDenied row that the test expects), then done; or error when it throws, then done.
ClassMethod Probe(number As %String, user As %String, entry As %String, configText As %String)
{
	Set run = $Name(^OcuTalonTest("WebStatus", number))
	Try {
		Set @run@("job") = $Job
		Set @run@("login") = $SYSTEM.Security.Login(user)
		Set @run@("user") = $Username
		Set @run@("roles") = $Roles
		Set @run@("canReadEntries") = $SYSTEM.Security.Check("%Admin_ConfigStore", "USE")
		Set runners = $ListFromString(##class(OcuTalon.Test.Agent.RunnerFixture).#RUNNERS)
		Set position = 0
		While $ListNext(runners, position, item) {
			Set @run@("status", item) = ##class(OcuTalon.Bridge.Keys).Status(item)
		}
		Set @run@("present") = ##class(OcuTalon.Bridge.Keys).Present(configText)
		Set @run@("absent") = ##class(OcuTalon.Bridge.Keys).Absent("TriageAgent")
		Set state = ##class(OcuTalon.Bridge.Budget).State(, .faults)
		Set @run@("budget") = state.%ToJSON()
		Set @run@("faults") = faults.%ToJSON()
		Set sc = ##class(%ConfigStore.Configuration).GetDetails(##class(OcuTalon.Bridge.ConfigStore).FullName(entry), .details, 0, 0)
		Set @run@("controlRefused") = $$$ISERR(sc)
	} Catch exception {
		Set @run@("error") = exception.DisplayString()
	}
	Set @run@("done") = 1
}

/// --- helpers ---
/// 1 when OcuTalon.Production runs with every item (RunningReason, WaitAllRun). Otherwise the test fails with the reason, and quits.
Method Ready() As %Boolean [ Private ]
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set reason = $ClassMethod(fixture, "RunningReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	If '$ClassMethod(fixture, "WaitAllRun") {
		Do $$$AssertTrue(0, "Not every item of the production runs: "_##class(OcuTalon.Install.Step.Production).NotRunning())
		Quit 0
	}
	Quit 1
}

/// The name of the running production.
Method Production() As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).#PRODUCTION
}

/// Sets the entry of each runner to the placeholder, with the runners restarted and their records written: pointed 0 puts the entries
/// back to the placeholder of the Provider step (RestoreKeys), and pointed 1 points them at OCUTALON_MOCK_KEY_HEADER (PointKeys).
/// 1 when the entries hold the placeholder and every runner runs and has recorded its state. Otherwise the test fails with the
/// reason, and quits.
Method SetupKeys(placeholder As %String, pointed As %Boolean) As %Boolean [ Private ]
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	If pointed {
		Set variable = $Parameter(fixture, "MOCKKEYVARIABLE")
		Do $$$AssertNotEquals($SYSTEM.Util.GetEnviron(variable), "", "control: "_variable_" is set in this process")
	}
	Set sc = $Select(pointed: $ClassMethod(fixture, "PointKeys"), 1: $ClassMethod(fixture, "RestoreKeys"))
	Do $$$AssertStatusOK(sc, "the entries of the runners are set to "_placeholder_" and the runners restarted")
	Set holds = $ClassMethod(fixture, "KeysAre", placeholder)
	Do $$$AssertTrue(holds, "the entry of each runner holds "_placeholder)
	Set runs = $ClassMethod(fixture, "WaitAllRun")
	Do $$$AssertTrue(runs, "every item runs")
	Set recorded = $ClassMethod(fixture, "WaitRecords")
	Do $$$AssertTrue(recorded, "and every runner has recorded its state")
	Quit holds && runs && recorded
}

/// The ProviderConfig setting of the runner item, as text.
Method ProviderConfigOf(item As %String) As %String [ Private ]
{
	Quit ##class(Ens.Director).GetAdapterSettingValue(..Production()_"||"_item, "ProviderConfig")
}

/// Starts the job for the user and waits for its report. Returns the node of the report, or "" (with a failure) when the job does not
/// finish in JOBSECONDS or throws.
Method RunProbe(label As %String, user As %String, entry As %String, config As %String) As %String [ Private ]
{
	Set number = ..Number_label
	Set run = $Name(^OcuTalonTest("WebStatus", number))
	Kill @run
	Job ##class(OcuTalon.Test.Bridge.WebStatus).Probe(number, user, entry, config)
	Set finished = ##class(OcuTalon.Test.Agent.RunnerFixture).WaitFor($Name(@run@("done")), ..#JOBSECONDS)
	Do $$$AssertTrue(finished, "the job reports within "_..#JOBSECONDS_" seconds")
	Do $$$AssertEquals($Get(@run@("error")), "", "and threw nothing")
	If finished && ($Get(@run@("error")) = "") Quit run
	Quit ""
}

/// The controls of the job's context: it logged in, as the user, with exactly the application roles and no %Admin_ConfigStore, and a
/// read of an entry is refused there.
Method AssertContext(run As %String, user As %String) [ Private ]
{
	Do $$$AssertEquals($Get(@run@("login")), 1, "control: the job logs in as the fixture user")
	Do $$$AssertEquals($Get(@run@("user")), user, "control: and runs as it")
	Do $$$AssertTrue($Get(@run@("job")) '= $Job, "control: the job is not this process")
	Set expected = $ListFromString(..Roles(), ",")
	Set actual = $ListFromString($Get(@run@("roles")), ",")
	Set same = ($ListLength(expected) = $ListLength(actual))
	Set position = 0
	While $ListNext(expected, position, role) {
		If '$ListFind(actual, role) Set same = 0
	}
	Do $$$AssertTrue(same, "control: its roles are exactly the application roles ("_..Roles()_"): "_$Get(@run@("roles")))
	Do $$$AssertEquals($Get(@run@("canReadEntries")), 0, "control: it does not hold %Admin_ConfigStore:USE")
	Do $$$AssertEquals($Get(@run@("controlRefused")), 1, "control: a read of an entry is refused there")
}

/// The roles of Install.Step.Web.APPLICATIONROLES (a MatchRoles form, ":role:role:role") as a comma list.
ClassMethod Roles() As %String [ Private ]
{
	Set spec = ##class(OcuTalon.Install.Step.Web).#APPLICATIONROLES
	Set roles = ""
	For i = 1:1:$Length(spec, ":") {
		Set role = $Piece(spec, ":", i)
		If role '= "" Set roles = roles _ $Select(roles = "": "", 1: ",") _ role
	}
	Quit roles
}

/// 1 when the faults (a dynamic array) hold the line of an unreadable Usage table.
ClassMethod UsageLine(faults As %DynamicArray) As %Boolean [ Private ]
{
	Set found = 0
	Set iterator = faults.%GetIterator()
	While iterator.%GetNext(, .line) {
		If line [ "The Usage rows of the day cannot be read in this process" Set found = 1
	}
	Quit found
}

/// --- security and audit (in %SYS) ---
/// Creates the fixture user with exactly the application roles. The name is returned, or "" with a failure.
Method NewUser(suffix As %String) As %String [ Private ]
{
	Set user = ..#USER_..Number_suffix
	Set sc = ..CreateUser(user, ..Roles())
	Do $$$AssertStatusOK(sc, "the fixture user "_user_" is created with the roles "_..Roles())
	Quit $Select($$$ISOK(sc): user, 1: "")
}

/// Creates the user (in %SYS) with the roles, a comma list, and a cryptographically random password that nothing uses.
ClassMethod CreateUser(user As %String, roles As %String) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(user) Do ##class(Security.Users).Delete(user)
	Set password = "Zz"_$SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(18))_"xY!9"
	Quit ##class(Security.Users).Create(user, roles, password, "OcuTalon test fixture", , , , 0, 1)
}

/// Deletes the fixture users of every run and the reports of every run but the counter.
ClassMethod Clean() [ Private ]
{
	Set node = ""
	For {
		Set node = $Order(^OcuTalonTest("WebStatus", node))
		Quit:node=""
		If node '= "n" Kill ^OcuTalonTest("WebStatus", node)
	}
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Users WHERE Name %STARTSWITH ?", ..#USER)
	While result.%Next() {
		Do ##class(Security.Users).Delete(result.%GetData(1))
	}
}

/// The highest AuditIndex of %SYS.Audit: the mark that AuditRows reads from.
ClassMethod AuditMark() As %Integer [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(AuditIndex) FROM %SYS.Audit")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of AccessDenied rows of the user in %SYS.Audit after the mark.
ClassMethod AuditRows(user As %String, mark As %Integer) As %Integer [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM %SYS.Audit WHERE AuditIndex > ? AND Username = ? AND EventSource = ? AND EventType = ? AND Event = ?", mark, user, "%System", "%Security", "AccessDenied")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The Enabled flag of the audit event, "1" or "0", or "" when the event does not exist.
ClassMethod EventState() As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill event
	If '##class(Security.Events).Exists(..#EVENT, , , .event) Quit ""
	Quit +event.Enabled
}

/// Sets the Enabled flag of the audit event.
ClassMethod SetEvent(enabled As %Boolean) [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set properties("Enabled") = enabled
	Do ##class(Security.Events).Modify(..#EVENT, , , .properties)
}

/// Switches the audit event on for this run when it is off, and remembers to put it back. 1 when it is on. Otherwise the test fails
/// with the reason, and quits.
Method EventOn() As %Boolean [ Private ]
{
	Set state = ..EventState()
	If state = "" {
		Do $$$AssertTrue(0, "the audit event "_..#EVENT_" does not exist")
		Quit 0
	}
	If 'state {
		Set ..EventWas = 0
		Do ..SetEvent(1)
	}
	Do $$$AssertEquals(..EventState(), 1, "the audit event "_..#EVENT_" is on")
	Quit ..EventState() = 1
}

}
