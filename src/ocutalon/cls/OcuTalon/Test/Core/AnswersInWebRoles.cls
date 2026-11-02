/// Live tests of what a web request can and cannot read, and of the answer path that avoids it (Story 6.2; DW-68, DW-113; AD-4,
/// AD-11, AD-13). THROWAWAY STACKS AND CI ONLY (Rule 21): they create and delete a security user and need the running
/// OcuTalon.Production with its CI override. Reason refuses everything else (the demo host, a user's instance, an IPM test run and
/// a slot carry neither the mock's base URL nor the CI switch OCUTALON_MOCK_KEY_HEADER), and the setup then fails with the reason
/// before any user or row is made.
/// A job logs in (the one-argument $SYSTEM.Security.Login) as a fixture user whose roles are exactly OcuTalonUser and the
/// application roles of Install.Step.Web (APPLICATIONROLES, parsed): the context of a web request. Probe is that job.
///   - TestWatcherReadsFailInAWebRequest (DW-113): in the job Ownership.Watchers, Ownership.ApprovalIncident and
///     Session.Recipients("instance", ...) each return "" with an error status; in this process they return the two watchers and
///     the incident;
///   - TestInstanceAnswerReachesBothWatchers (DW-68): with a CSP session bound to a session of that user, which watches the
///     production together with a second session, AnswersIn.FromPage answers an instance request through AnswerOps and the answered
///     approval event reaches both sessions' streams;
///   - TestGuardRefusesOutsideAThrowaway: Reason is empty only for the CI override's pair of values, and the setup of a run whose
///     environment lacks them fails and provisions no user;
///   - TestFixtureUserIsRemoved: the hooks that end a test remove the fixture user, and a user left by an earlier run is removed
///     before the next one; the password is new for each user.
///   - TestPasswordIsNeverWritten (QA, AC16): after a user is created no report, event-log row or global of the run holds the password's
///     shape, and the code is the only place that sees it: Password() is read once, by CreateUser, which writes, logs and stores
///     nothing, and the job's Login names no password.
/// The user's password is random for each user and is never written to a log, an output or a global: the job logs in with no
/// password. OnAfterOneTest and OnAfterAllTests remove every user with the prefix whatever the result of the test, and
/// OnBeforeAllTests removes a leftover of an earlier run. OnAfterAllTests also removes the messages of the run's sessions
/// (Fixture.RemoveMessages). The report of a job is under ^OcuTalonTest("AnswersInWebRoles", <number>).
Class OcuTalon.Test.Core.AnswersInWebRoles Extends %UnitTest.TestCase
{

/// The fixture users' prefix: users with it are deleted before and after the run.
Parameter USER = "ZzAnswersWR";

/// The longest the parent waits for the job's report, in seconds.
Parameter JOBSECONDS = 90;

/// The longest the parent waits for an event, in seconds.
Parameter EVENTSECONDS = 20;

/// The run's number.
Property Number As %Integer;

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 300);

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The number of Setup calls, which gives each test a production of its own.
Property Setups As %Integer [ InitialExpression = 0 ];

/// The TraceRefs of the run's sessions: the SuperSessions of the messages that OnAfterAllTests removes.
Property Supers As %DynamicArray;

/// Values that stand in for the process environment, by variable name (Environ): a test sets them to run the setup as it runs
/// outside a throwaway.
Property Environment As %String [ MultiDimensional ];

Method OnBeforeAllTests() As %Status
{
	Set running = ##class(Ens.Director).IsProductionRunning(.name)
	Set ..Missing = ..Reason(..Environ("OCUTALON_MODEL_BASE_URL"), ..Environ("OCUTALON_MOCK_KEY_HEADER"), running, $Get(name))
	If ..Missing '= "" Quit $SYSTEM.Status.Error(5001, ..Missing)
	Set ..Number = $Increment(^OcuTalonTest("AnswersInWebRoles", "n"))
	Set ..Refs = ""
	Set ..Supers = []
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If ..Missing '= "" Quit $$$OK
	Do ..Clean()
	If $IsObject(..Supers) Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Supers)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $$$OK
}

/// The environment variable: the value that Environment holds for it when a test set one, else the process's.
Method Environ(name As %String) As %String [ Private ]
{
	Quit $Select($Data(..Environment(name)): ..Environment(name), 1: $SYSTEM.Util.GetEnviron(name))
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Missing '= "" Quit $$$OK
	Do ..Clean()
	Quit $$$OK
}

/// The reason why these tests must not run, or "" when they may: the environment must be the CI override's (Test.Contract.Mock:
/// the mock's base URL and the switch OCUTALON_MOCK_KEY_HEADER = 1, which only ci/compose.ci.yml sets) and OcuTalon.Production must
/// run. The values are arguments so that a test can pin each refusal.
ClassMethod Reason(baseUrl As %String, switch As %String, running As %Boolean, production As %String) As %String
{
	Set reason = ##class(OcuTalon.Test.Contract.Mock).MissingReason(baseUrl, switch)
	If reason '= "" Quit reason
	Set expected = ##class(OcuTalon.Test.Agent.RunnerFixture).#PRODUCTION
	If 'running || (production '= expected) Quit expected_" does not run: this class runs in throwaways and CI only (Rule 21)"
	Quit ""
}

/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	If '##class(OcuTalon.Test.Agent.RunnerFixture).WaitAllRun() {
		Do $$$AssertTrue(0, "Not every item of the production runs: "_##class(OcuTalon.Install.Step.Production).NotRunning())
		Quit 0
	}
	Quit 1
}

Method TestWatcherReadsFailInAWebRequest()
{
	If '..Guard() Quit
	Set user = ..NewUser("r")
	If user = "" Quit
	Do ..Setup(user, .s1, .s2, .incident, .request, .production)
	Set watchers = ##class(OcuTalon.Data.Ownership).Watchers("ZZNS", production, .sc)
	Do $$$AssertStatusOK(sc, "control: the test process reads the watchers")
	Do $$$AssertEquals($ListLength(watchers), 2, "control: and there are two")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).ApprovalIncident(request, .sc), incident, "control: the test process reads the request's incident")
	Do $$$AssertStatusOK(sc, "control: with an OK status")
	Set recipients = ##class(OcuTalon.Data.Session).Recipients("instance", incident, .sc)
	Do $$$AssertEquals($ListLength(recipients), 2, "control: the test process reads two recipients")
	Set run = ..RunProbe("reads", user, s1, incident, request, production)
	If run = "" Quit
	Do ..AssertContext(run, user)
	Do $$$AssertEquals($Get(@run@("watchers")), "0|1", "Watchers returns no watchers and an error status in a web request")
	Do $$$AssertEquals($Get(@run@("approvalIncident")), "|1", "ApprovalIncident returns no incident and an error status")
	Do $$$AssertEquals($Get(@run@("recipients")), "0|1", "Session.Recipients returns no recipients and passes the error status through")
}

Method TestInstanceAnswerReachesBothWatchers()
{
	If '..Guard() Quit
	Set user = ..NewUser("a")
	If user = "" Quit
	Do ..Setup(user, .s1, .s2, .incident, .request, .production)
	Set run = ..RunProbe("page", user, s1, incident, request, production)
	If run = "" Quit
	Do ..AssertContext(run, user)
	Do $$$AssertEquals($Get(@run@("page")), "1|done|"_s1, "AnswersIn.FromPage answers done for the session of the web-role user")
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request)
	Do $$$AssertEquals(row.State_"|"_row.AnsweredChannel_"|"_row.AnsweredBy, "approved|web|"_user, "the request is approved from the web by that user")
	For session = s1, s2 {
		Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "approval", 1, ..#EVENTSECONDS)
		Do $$$AssertEquals(events.%Size(), 1, "the session "_session_" got one approval event")
		If events.%Size() = 0 Continue
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.state_"|"_payload.answeredChannel, request_"|approved|web", "and it is the answered request")
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Type = 3 AND Text %STARTSWITH ?", "OcuTalon.Bridge.Approval: no open task of "_request)
}

Method TestGuardRefusesOutsideAThrowaway()
{
	Set production = ##class(OcuTalon.Test.Agent.RunnerFixture).#PRODUCTION
	Set mock = "http://mock:8080/v1/"
	Do $$$AssertEquals(..Reason(mock, 1, 1, production), "", "the CI override's environment with the production running may run")
	For case = "a demo host or a user's instance||", "an IPM test run||", "the real API|https://api.anthropic.com/v1/|1", "the mock without the CI switch|"_mock_"|", "the switch off|"_mock_"|0" {
		Set label = $Piece(case, "|", 1), url = $Piece(case, "|", 2), switch = $Piece(case, "|", 3)
		Set reason = ..Reason(url, switch, 1, production)
		Do $$$AssertNotEquals(reason, "", label_" is refused")
	}
	Do $$$AssertNotEquals(..Reason(mock, 1, 0, ""), "", "a stack with no production running is refused")
	Do $$$AssertNotEquals(..Reason(mock, 1, 1, "Other.Production"), "", "so is another production")
	Set users = ..UserCount()
	Set outside = ##class(OcuTalon.Test.Core.AnswersInWebRoles).%New("")
	Set outside.Environment("OCUTALON_MODEL_BASE_URL") = "", outside.Environment("OCUTALON_MOCK_KEY_HEADER") = ""
	Set sc = outside.OnBeforeAllTests()
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), "the setup of a run whose environment lacks the CI override's values fails")
	Do $$$AssertNotEquals(outside.Missing, "", "with the reason")
	Do $$$AssertEquals(outside.Provision("x"), "", "and the run provisions no user")
	Set refused = ##class(OcuTalon.Test.Core.AnswersInWebRoles).%New("")
	Set refused.Missing = "refused for this check"
	Set refused.Number = ..Number
	Do $$$AssertEquals(refused.Provision("x"), "", "a refused run provisions no user")
	Do $$$AssertEquals(..UserCount(), users, "and creates none")
}

Method TestFixtureUserIsRemoved()
{
	If '..Guard() Quit
	Set left = ..#USER_"left"
	Do $$$AssertStatusOK(..CreateUser(left, "OcuTalonUser"), "a user is left by an earlier failed run")
	Set next = ##class(OcuTalon.Test.Core.AnswersInWebRoles).%New("")
	Set next.Number = ..Number
	Do next.OnBeforeAllTests()
	Do $$$AssertEquals(..UserExists(left), 0, "the next run removes the leftover before it begins")
	Set failed = ..#USER_"failed"
	Do $$$AssertStatusOK(..CreateUser(failed, "OcuTalonUser"), "a test creates its user")
	Do $$$AssertEquals(..UserExists(failed), 1, "control: the user exists")
	Do next.OnAfterOneTest("TestThatFailed")
	Do $$$AssertEquals(..UserExists(failed), 0, "the hook that ends every test, a failed one too, removes the user")
	Set other = ..#USER_"other"
	Do $$$AssertStatusOK(..CreateUser(other, "OcuTalonUser"), "a user is left when a class ends")
	Do next.OnAfterAllTests()
	Do $$$AssertEquals(..UserExists(other), 0, "the hook that ends the class removes it")
	Do $$$AssertNotEquals(..Password(), ..Password(), "the password is new for each user")
	Do $$$AssertTrue($Length(..Password()) > 20, "and is long")
}

/// QA (AC16 (2)): the fixture user's password is random and is never written to a log, an output or a global. The password's shape
/// ("Zz...xY!9") is looked for in the run's reports, the event log and the test globals after a user is created, and the code is
/// read: Password() has one caller, CreateUser, which does no output, logging or global write; the job logs in with no password.
Method TestPasswordIsNeverWritten()
{
	If '..Guard() Quit
	Set user = ..NewUser("w")
	If user = "" Quit
	Do $$$AssertEquals(..UserExists(user), 1, "control: the user is created")
	Set shape = "xY!9"
	Set home = $Namespace
	Set hits = ..GlobalHits(shape)
	New $Namespace
	Set $Namespace = "%SYS"
	Set hits = hits + ..GlobalHits(shape)
	Set $Namespace = home
	Do $$$AssertEquals(hits, 0, "no node of ^OcuTalonTest, in this namespace or in %SYS (where the user is made), holds a password")
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Text LIKE ?", "%"_shape_"%")
	Do rows.%Next()
	Do $$$AssertEquals(+rows.%GetData(1), 0, "and no event-log row does")
	Set callers = "", bodies = ""
	Set methods = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.MethodDefinition WHERE parent = 'OcuTalon.Test.Core.AnswersInWebRoles' ORDER BY Name")
	While methods.%Next() {
		Set name = methods.%Get("Name")
		Set stream = ##class(%Dictionary.MethodDefinition).%OpenId("OcuTalon.Test.Core.AnswersInWebRoles||"_name).Implementation
		If stream.Size = 0 Continue
		Set code = stream.Read(stream.Size)
		If name = "Password" || (name = "TestPasswordIsNeverWritten") Continue
		If code [ "Password()" Set callers = callers_$ListBuild(name)
		If name = "CreateUser" Set bodies = code
		If name = "Probe" Do $$$AssertTrue(code [ "Login(user)", "the job logs in with the one-argument Login: no password")
	}
	Do $$$AssertEquals($ListToString(callers), "CreateUser,TestFixtureUserIsRemoved", "Password() is read by CreateUser and by the randomness check only")
	Do $$$AssertTrue(bodies [ "Security.Users).Create(", "control: CreateUser's code was read")
	For forbidden = "Write", "^", "Log", "LOG", "$$$Assert" {
		Do $$$AssertEquals(bodies [ forbidden, 0, "CreateUser has no '"_forbidden_"': the password goes to Security.Users.Create and nowhere else")
	}
}

/// --- helpers ---
/// The number of nodes of ^OcuTalonTest in the current namespace whose value holds the text.
ClassMethod GlobalHits(text As %String) As %Integer [ Private ]
{
	Set hits = 0, node = $Name(^OcuTalonTest)
	For {
		Set node = $Query(@node)
		Quit:node=""
		If $Extract(node, 1, $Length("^OcuTalonTest(")) '= "^OcuTalonTest(" Quit
		If $Data(@node) # 2, $Get(@node) [ text Set hits = hits + 1
	}
	Quit hits
}

/// Two sessions that watch the production, the first of the user, and an instance incident of the production with a pending fix
/// request that needs OcuTalonUser. The rows are kept for the clean-up.
Method Setup(user As %String, Output s1 As %String, Output s2 As %String, Output incident As %String, Output request As %String, Output production As %String) [ Private ]
{
	Set s1 = ..Session(user)
	Set s2 = ..Session(..#USER_"other"_..Number)
	Set ..Setups = ..Setups + 1
	Set production = "Zz.WR"_..Number_"."_..Setups
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(s1, "ZZNS", production)_","_##class(OcuTalon.Test.Data.Fixture).Check(s2, "ZZNS", production)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", production)
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", incident, "pending", , {"RequiredRole": "OcuTalonUser"})
	Set ..Refs = ..Refs_","_incident_","_request
}

/// Starts the job in the mode (reads or page) for the user and waits for its report. Returns the node of the report, or "" (with a
/// failure) when the job does not finish in JOBSECONDS or throws.
Method RunProbe(mode As %String, user As %String, session As %String, incident As %String, request As %String, production As %String) As %String [ Private ]
{
	Set number = ..Number_mode
	Set run = $Name(^OcuTalonTest("AnswersInWebRoles", number))
	Kill @run
	Job ##class(OcuTalon.Test.Core.AnswersInWebRoles).Probe(number, mode, user, session, incident, request, production)
	Set finished = ##class(OcuTalon.Test.Agent.RunnerFixture).WaitFor($Name(@run@("done")), ..#JOBSECONDS)
	Do $$$AssertTrue(finished, "the job reports within "_..#JOBSECONDS_" seconds")
	Do $$$AssertEquals($Get(@run@("error")), "", "and threw nothing")
	If finished && ($Get(@run@("error")) = "") Quit run
	Quit ""
}

/// The job: logs in as the user, the context of a web request, and reports under ^OcuTalonTest("AnswersInWebRoles", number): job, login
/// (the result of Login), user and roles, then for mode reads the cross-owner reads as "<length or Ref>|<1 when the status is an error>"
/// (watchers, approvalIncident, recipients), and for mode page the answer of AnswersIn.FromPage with a CSP session bound to the session
/// as "<1 when the status is OK>|<result>|<the session Ref it resolved>" (page); or error when it throws; then done.
ClassMethod Probe(number As %String, mode As %String, user As %String, session As %String, incident As %String, request As %String, production As %String)
{
	Set run = $Name(^OcuTalonTest("AnswersInWebRoles", number))
	Try {
		Set @run@("job") = $Job
		Set @run@("login") = $SYSTEM.Security.Login(user)
		Set @run@("user") = $Username
		Set @run@("roles") = $Roles
		If mode = "reads" {
			Set watchers = ##class(OcuTalon.Data.Ownership).Watchers("ZZNS", production, .sc)
			Set @run@("watchers") = $ListLength(watchers)_"|"_$SYSTEM.Status.IsError(sc)
			Set found = ##class(OcuTalon.Data.Ownership).ApprovalIncident(request, .sc)
			Set @run@("approvalIncident") = found_"|"_$SYSTEM.Status.IsError(sc)
			Set recipients = ##class(OcuTalon.Data.Session).Recipients("instance", incident, .sc)
			Set @run@("recipients") = $ListLength(recipients)_"|"_$SYSTEM.Status.IsError(sc)
		} Else {
			Set %session = ##class(%CSP.Session).%New("ZzWR"_number, 0)
			Set %session.Data("OcuTalon.SessionRef") = session
			Set sc = ##class(OcuTalon.Core.AnswersIn).FromPage(request, "approve", "web", .answer, .ref)
			Set @run@("page") = $SYSTEM.Status.IsOK(sc)_"|"_$Select($IsObject($Get(answer)): answer.Result, 1: "")_"|"_$Get(ref)
		}
	} Catch exception {
		Set @run@("error") = exception.DisplayString()
	}
	Set @run@("done") = 1
}

/// The controls of the job's context: it logged in, as the user, with exactly the roles of a web request, and is not this process.
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
	Do $$$AssertTrue(same, "control: its roles are exactly "_..Roles()_": "_$Get(@run@("roles")))
}

/// 1 when the security user exists.
ClassMethod UserExists(user As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ''##class(Security.Users).Exists(user)
}

/// The number of fixture users.
ClassMethod UserCount() As %Integer [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Security.Users WHERE Name %STARTSWITH ?", ..#USER)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// A fixture session of the IRIS user; its Ref is kept for the clean-up, and its TraceRef is a SuperSession of the run.
Method Session(user As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session(user)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	If $IsObject(..Supers) Do ..Supers.%Push(##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef)
	Quit ref
}

/// Creates the fixture user with exactly the roles of a web request, and reports it as an assertion. The name is returned, or ""
/// with a failure.
Method NewUser(suffix As %String) As %String [ Private ]
{
	Set user = ..Provision(suffix, .sc)
	Do $$$AssertStatusOK(sc, "the fixture user is created with the roles "_..Roles())
	Quit user
}

/// Creates the fixture user and returns its name; it creates nothing and returns "" when the run is refused (Missing).
Method Provision(suffix As %String, Output sc As %Status) As %String
{
	Set sc = $$$OK
	If ..Missing '= "" Quit ""
	Set user = ..#USER_..Number_suffix
	Set sc = ..CreateUser(user, ..Roles())
	Quit $Select($$$ISOK(sc): user, 1: "")
}

/// Creates the user (in %SYS) with the roles, a comma list, and a password that is random for each user and that nothing uses.
ClassMethod CreateUser(user As %String, roles As %String) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(user) Do ##class(Security.Users).Delete(user)
	Quit ##class(Security.Users).Create(user, roles, ..Password(), "OcuTalon test fixture", , , , 0, 1)
}

/// A password of random characters, new at each call.
ClassMethod Password() As %String [ Private ]
{
	Quit "Zz"_$SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(18))_"xY!9"
}

/// The roles of a web request: OcuTalonUser and Install.Step.Web.APPLICATIONROLES (a MatchRoles form, ":role:role:role"), as a comma list.
ClassMethod Roles() As %String [ Private ]
{
	Set roles = "OcuTalonUser"
	Set spec = ##class(OcuTalon.Install.Step.Web).#APPLICATIONROLES
	For i = 1:1:$Length(spec, ":") {
		Set role = $Piece(spec, ":", i)
		If role '= "" Set roles = roles _ "," _ role
	}
	Quit roles
}

/// Deletes the fixture users of every run and the reports of every run but the counter.
ClassMethod Clean() [ Private ]
{
	Set node = ""
	For {
		Set node = $Order(^OcuTalonTest("AnswersInWebRoles", node))
		Quit:node=""
		If node '= "n" Kill ^OcuTalonTest("AnswersInWebRoles", node)
	}
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Users WHERE Name %STARTSWITH ?", ..#USER)
	While result.%Next() {
		Do ##class(Security.Users).Delete(result.%GetData(1))
	}
}

}
