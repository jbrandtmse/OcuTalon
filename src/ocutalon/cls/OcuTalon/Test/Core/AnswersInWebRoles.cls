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
///   - TestDemoApproverOwnSessionOnly (Story 25.4): with the online demo forced on, a user who holds the demo account's roles, OcuTalonApprover and the application roles answers
///     its own session's request, whose RequiredRole is OcuTalonApprover, through AnswersIn.FromPage (approved) and gets not_found for another session's request (not_visible on Telegram), which stays pending;
///   - TestMayAnswerInAWebJob (Story 25.5, Task 0): in the job (exactly OcuTalonUser and the application roles) Approval.MayAnswer for the job's own user answers 1 for a request whose
///     RequiredRole the user holds and 0 for a fixture role that it lacks and for a role that does not exist, with no error and no <PROTECT>, and the approval payload's answerable and approverKind
///     are computed for that session in the same job;
///   - TestApproverMatrix (Story 25.5, AC 6): the fixture roles OcuTalonApprover and OcuTalonApprover_<kind> for the seven kinds, through AnswersIn and the Telegram entry with the approval double
///     scripted to the step 6 rule over real roles (ApprovalDouble Kind): the holder of only another kind's role is refused with the kind, the holder of the kind's role, of OcuTalonApprover and the
///     README account with the fixture OcuTalonApprover are handed over, and a refused request stays pending;
///   - TestFixtureRoleOnTheRealPath (Story 25.5, AC 2 and AC 6): through the real production in the job, a request that needs the fixture OcuTalonApprover is refused to a user without it
///     ({"kind": ""}, still pending) and answered for a holder; with the online demo forced, the demo account's holder answers its own request and gets not_found, never a role refusal, for another
///     session's request, which stays pending;
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

/// The approver kinds of AD-11 (step 6).
Parameter KINDS = "resend,reroute,suspend,rollback,partner,email,tool";

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

/// The fixture roles that this run made (EnsureRole), comma-separated: OnAfterOneTest deletes them after the users.
Property MadeRoles As %String(MAXLEN = "");

/// 1 when a test granted the fixture OcuTalonApprover to the README account: OnAfterOneTest takes it back.
Property GrantedReadme As %Boolean [ InitialExpression = 0 ];

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
	Do ..RestoreRoles()
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
	Do ##class(OcuTalon.Test.Core.ApprovalDouble).End()
	Do ..Clean()
	Do ..RestoreRoles()
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

Method TestDemoApproverOwnSessionOnly()
{
	If '..Guard() Quit
	Set created = ##class(OcuTalon.Test.Install.RolesAssign).EnsureRoles()
	Set saved = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Try {
		Set demoRoles = ##class(OcuTalon.Install.Step.Users).#DEMOROLES_",OcuTalonApprover,"_$Piece(..Roles(), ",", 2, *)
		Set user = ..#USER_..Number_"d"
		Do $$$AssertStatusOK(..CreateUser(user, demoRoles), "the demo account's fixture user holds the demo roles, OcuTalonApprover and the application roles")
		Set s1 = ..Session(user)
		Set s2 = ..Session(..#USER_"other"_..Number)
		Set own = ##class(OcuTalon.Test.Data.Fixture).Approval(s1, , "pending", , {"RequiredRole": "OcuTalonApprover"})
		Set other = ##class(OcuTalon.Test.Data.Fixture).Approval(s2, , "pending", , {"RequiredRole": "OcuTalonApprover"})
		Set ..Refs = ..Refs_","_own_","_other
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Set run = ..RunProbe("page", user, s1, "", own, "")
		If run '= "" {
			Do $$$AssertEquals($Get(@run@("login")), 1, "control: the job logs in as the demo account's user")
			Do $$$AssertEquals($Get(@run@("page")), "1|done|"_s1, "it answers its own session's request")
			Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(own)
			Do $$$AssertEquals(row.State_"|"_row.AnsweredBy, "approved|"_user, "which is approved by that user")
		}
		Set run = ..RunProbe("page", user, s1, "", other, "")
		If run '= "" {
			Do $$$AssertEquals($Get(@run@("page")), "1|not_found|"_s1, "it gets not_found (not_visible to Telegram) for another session's request")
			Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(other)
			Do $$$AssertEquals(row.State, "pending", "which stays pending")
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", saved)
	Do ##class(OcuTalon.Test.Install.RolesAssign).DropRoles(created)
}

/// Story 25.5, Task 0: in a job logged in as a user with exactly the roles of a web request, MayAnswer for the job's own user and the approval payload's answerable are computed with no error.
Method TestMayAnswerInAWebJob()
{
	If '..Guard() Quit
	Do ..EnsureRole("OcuTalonApprover")
	Set user = ..NewUser("m")
	If user = "" Quit
	Set s1 = ..Session(user)
	Set held = ##class(OcuTalon.Test.Data.Fixture).Approval(s1, , "pending", , {"RequiredRole": "OcuTalonUser"})
	Set lacks = ##class(OcuTalon.Test.Data.Fixture).Approval(s1, , "pending", , {"RequiredRole": "OcuTalonApprover"})
	Set nobody = ##class(OcuTalon.Test.Data.Fixture).Approval(s1, , "pending", , {"RequiredRole": ("ZzNobody"_..Number)})
	Set ..Refs = ..Refs_","_held_","_lacks_","_nobody
	Set run = ..RunProbe("may", user, s1, "", held_","_lacks_","_nobody, "")
	If run = "" Quit
	Do ..AssertContext(run, user)
	Do $$$AssertEquals($Get(@run@("may", 1)), "1|", "MayAnswer answers 1, with no kind, for a request whose RequiredRole the user holds")
	Do $$$AssertEquals($Get(@run@("may", 2)), "0|", "0 for a fixture role that the user lacks")
	Do $$$AssertEquals($Get(@run@("may", 3)), "0|", "and 0 for a role that nobody holds")
	Do $$$AssertEquals($Get(@run@("answerable", 1))_"/"_$Get(@run@("answerable", 2))_"/"_$Get(@run@("answerable", 3)), "1|/0|/0|", "and the payload's answerable is computed for the session in the same job")
}

/// Story 25.5, AC 6: each approver kind answered through AnswersIn and through the Telegram entry by the holder of only another kind's role, of the kind's role, of OcuTalonApprover and by the README
/// account with the fixture OcuTalonApprover. The approval double applies the step 6 rule over the users' real roles; nothing else of Approval is faked.
Method TestApproverMatrix()
{
	If '..Guard() Quit
	Set double = "OcuTalon.Test.Core.ApprovalDouble"
	Do ..EnsureRole("OcuTalonApprover")
	For i = 1:1:$Length(..#KINDS, ",") {
		Do ..EnsureRole("OcuTalonApprover_"_$Piece(..#KINDS, ",", i))
	}
	Set count = $Length(..#KINDS, ",")
	For i = 1:1:count {
		Set kindUser(i) = ..#USER_..Number_"k"_i
		Do $$$AssertStatusOK(..CreateUser(kindUser(i), "OcuTalonApprover_"_$Piece(..#KINDS, ",", i)), "the user of only OcuTalonApprover_"_$Piece(..#KINDS, ",", i)_" is made")
		Set kindSession(i) = ..Session(kindUser(i))
	}
	Set allUser = ..#USER_..Number_"all"
	Do $$$AssertStatusOK(..CreateUser(allUser, "OcuTalonApprover"), "the user of OcuTalonApprover is made")
	Set allSession = ..Session(allUser)
	Set readme = ##class(OcuTalon.Test.Bridge.ApprovalRows).#ANSWERER
	Set readmeSession = ..Session(readme)
	Do ..GrantReadme()
	Do $$$AssertEquals(..Holds(readme, "OcuTalonApprover"), 1, "control: the README account holds the fixture OcuTalonApprover")
	Set web = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.AnswersInProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	For i = 1:1:count {
		Set kind = $Piece(..#KINDS, ",", i)
		Set otherSession = kindSession($Select(i = count: 1, 1: i + 1))
		Set cases = $ListBuild($ListBuild("the holder of only another kind's role", otherSession, 0), $ListBuild("the holder of the kind's role", kindSession(i), 1), $ListBuild("the holder of OcuTalonApprover", allSession, 1), $ListBuild("the README account with OcuTalonApprover", readmeSession, 1))
		Set position = 0
		While $ListNext(cases, position, case) {
			Set label = kind_", "_$List(case, 1)
			Set session = $List(case, 2), may = $List(case, 3)
			Set request = ..Request(session)
			Do $CLASSMETHOD(double, "Begin")
			Do $CLASSMETHOD(double, "Kind", request, kind)
			Set sc = ..AnswerWeb(web, request, session, .result)
			Do $$$AssertEquals(result_"|"_web.Refusal.%ToJSON(), $Select(may: "done|{}", 1: "not_allowed|{""kind"":"""_kind_"""}"), label_": the web answer")
			Do $$$AssertEquals($CLASSMETHOD(double, "Calls"), may, label_": Approval.Answer "_$Select(may: "was", 1: "was not")_" called")
			Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request).State, "pending", label_": the fixture row is never changed by the double")
			Set request = ..Request(session)
			Do $CLASSMETHOD(double, "Begin")
			Do $CLASSMETHOD(double, "Kind", request, kind)
			Set chat = ..Chat(session)
			Do $$$AssertStatusOK(##class(OcuTalon.Test.Core.AnswersTelegramProbe).FromTelegram(request, "approve", chat, .code, .slots), label_": the Telegram press is handled")
			Do $$$AssertEquals(code_"|"_$Select(may: "", 1: slots.%ToJSON()), $Select(may: "approved|", 1: "not_allowed|{""kind"":"""_kind_"""}"), label_": the Telegram answer")
			Do $$$AssertEquals($CLASSMETHOD(double, "Calls"), may, label_": and on Telegram Approval.Answer "_$Select(may: "was", 1: "was not")_" called")
		}
	}
	Do $CLASSMETHOD(double, "End")
	Kill ^OcuTalonTest("AnswersTelegramProbe")
}

/// Story 25.5, AC 2 and AC 6: the real production in the web-context job, on requests that need the fixture OcuTalonApprover.
Method TestFixtureRoleOnTheRealPath()
{
	If '..Guard() Quit
	Set created = ##class(OcuTalon.Test.Install.RolesAssign).EnsureRoles()
	Set saved = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Try {
		Set plain = ..NewUser("p")
		Set holder = ..#USER_..Number_"h"
		Do $$$AssertStatusOK(..CreateUser(holder, ..Roles()_",OcuTalonApprover"), "the holder of the fixture OcuTalonApprover with the application roles is made")
		If plain = "" Quit
		Set sPlain = ..Session(plain)
		Set sHolder = ..Session(holder)
		Set needs = {"RequiredRole": "OcuTalonApprover"}
		Set refused = ##class(OcuTalon.Test.Data.Fixture).Approval(sPlain, , "pending", , needs)
		Set allowed = ##class(OcuTalon.Test.Data.Fixture).Approval(sHolder, , "pending", , needs)
		Set ..Refs = ..Refs_","_refused_","_allowed
		Set run = ..RunProbe("page", plain, sPlain, "", refused, "")
		If run '= "" {
			Do $$$AssertEquals($Get(@run@("page")), "1|not_allowed|"_sPlain, "a user without the role is not_allowed through FromPage")
			Do $$$AssertEquals($Get(@run@("refusal")), "{""kind"":""""}", "with no kind, as the role check names none yet")
			Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(refused).State, "pending", "and the request stays pending")
		}
		Set run = ..RunProbe("page", holder, sHolder, "", allowed, "")
		If run '= "" {
			Do $$$AssertEquals($Get(@run@("page")), "1|done|"_sHolder, "the holder of the role answers its own request")
			Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(allowed).State, "approved", "which is approved")
		}
		Set demoRoles = ##class(OcuTalon.Install.Step.Users).#DEMOROLES_",OcuTalonApprover,"_$Piece(..Roles(), ",", 2, *)
		Set demo = ..#USER_..Number_"d"
		Do $$$AssertStatusOK(..CreateUser(demo, demoRoles), "the demo account's fixture user holds the demo roles, OcuTalonApprover and the application roles")
		Set sDemo = ..Session(demo)
		Set sOther = ..Session(..#USER_"other"_..Number)
		Set own = ##class(OcuTalon.Test.Data.Fixture).Approval(sDemo, , "pending", , needs)
		Set otherAllowed = ##class(OcuTalon.Test.Data.Fixture).Approval(sOther, , "pending", , needs)
		Set otherLacking = ##class(OcuTalon.Test.Data.Fixture).Approval(sOther, , "pending", , {"RequiredRole": ("ZzNobody"_..Number)})
		Set ..Refs = ..Refs_","_own_","_otherAllowed_","_otherLacking
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Set run = ..RunProbe("page", demo, sDemo, "", own, "")
		If run '= "" Do $$$AssertEquals($Get(@run@("page")), "1|done|"_sDemo, "on the online demo the holder answers its own request")
		For other = otherAllowed, otherLacking {
			Set run = ..RunProbe("page", demo, sDemo, "", other, "")
			If run '= "" {
				Do $$$AssertEquals($Get(@run@("page")), "1|not_found|"_sDemo, "another session's request is not_found, whether or not the holder may answer it: the owning-session rule comes first")
				Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(other).State, "pending", "and it stays pending")
			}
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", saved)
	Do ##class(OcuTalon.Test.Install.RolesAssign).DropRoles(created)
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
/// (watchers, approvalIncident, recipients), for mode may (request is a comma list of Refs) per Ref i Approval.MayAnswer for the job's own user as "<1 or 0>|<kind>" (may, i) and the
/// approval payload's "<answerable>|<approverKind>" for the session (answerable, i), and for mode page the answer of AnswersIn.FromPage with a CSP session bound to the session
/// as "<1 when the status is OK>|<result>|<the session Ref it resolved>" (page) and the refusal's JSON (refusal); or error when it throws; then done.
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
		} ElseIf mode = "may" {
			For i = 1:1:$Length(request, ",") {
				Set ref = $Piece(request, ",", i)
				Set may = ##class(OcuTalon.Bridge.Approval).MayAnswer(ref, $Username, .kind)
				Set @run@("may", i) = may_"|"_kind
				Set payload = ##class(OcuTalon.Live.Payload.Approval).FromRow(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref), session)
				Set @run@("answerable", i) = payload.Answerable_"|"_payload.ApproverKind
			}
		} Else {
			Set %session = ##class(%CSP.Session).%New("ZzWR"_number, 0)
			Set %session.Data("OcuTalon.SessionRef") = session
			Set sc = ##class(OcuTalon.Core.AnswersIn).FromPage(request, "approve", "web", .answer, .ref, .refusal)
			Set @run@("page") = $SYSTEM.Status.IsOK(sc)_"|"_$Select($IsObject($Get(answer)): answer.Result, 1: "")_"|"_$Get(ref)
			Set @run@("refusal") = $Select($IsObject($Get(refusal)): refusal.%ToJSON(), 1: "")
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

/// Makes the fixture role (with no resources, Test.Install.RolesAssign EnsureRoles) when the instance does not have it, and keeps it for RestoreRoles. 1 when it made it.
Method EnsureRole(name As %String) As %Boolean [ Private ]
{
	Set made = ##class(OcuTalon.Test.Install.RolesAssign).EnsureRoles(name)
	If made = "" Quit 0
	Set ..MadeRoles = ..MadeRoles_$Select(..MadeRoles = "": "", 1: ",")_made
	Quit 1
}

/// Takes back the grant to the README account, and deletes the roles that EnsureRole made (Test.Install.RolesAssign DropRoles).
Method RestoreRoles() [ Private ]
{
	If ..GrantedReadme {
		Do ##class(OcuTalon.Test.Install.RolesAssign).RemoveRole(##class(OcuTalon.Test.Bridge.ApprovalRows).#ANSWERER, "OcuTalonApprover")
		Set ..GrantedReadme = 0
	}
	Do ##class(OcuTalon.Test.Install.RolesAssign).DropRoles(..MadeRoles)
	Set ..MadeRoles = ""
}

/// Grants the fixture OcuTalonApprover to the README account when it does not hold it; RestoreRoles takes it back.
Method GrantReadme() [ Private ]
{
	Set readme = ##class(OcuTalon.Test.Bridge.ApprovalRows).#ANSWERER
	If ..Holds(readme, "OcuTalonApprover") Quit
	New $Namespace
	Set $Namespace = "%SYS"
	If $$$ISOK(##class(Security.Users).AddRoles(readme, "OcuTalonApprover")) Set ..GrantedReadme = 1
}

/// 1 when the IRIS user's recursed role set holds the role.
ClassMethod Holds(user As %String, role As %String) As %Boolean [ Private ]
{
	If $$$ISERR($SYSTEM.Security.GetUserRecursedRoleSet(user, .roles)) Quit 0
	Quit ''$ListFind($ListFromString(roles), role)
}

/// A fixture approval request of the session's, kept for the clean-up, that needs the role OcuTalonApprover.
Method Request(session As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(session, , "pending", , {"RequiredRole": "OcuTalonApprover"})
	Set ..Refs = ..Refs_","_ref
	Quit ref
}

/// A chat row that is on the session, kept for the clean-up; its ChatRef.
Method Chat(session As %String) As %String [ Private ]
{
	Set ..Setups = ..Setups + 1
	Set chatId = "73"_..Number_"0"_..Setups
	Set chat = ##class(OcuTalon.Data.Pairing).RecordChat(chatId, "Dana", .sc)
	Set row = ##class(OcuTalon.Data.Pairing).Chat(chat)
	Set row.SessionRef = session
	Do row.%Save()
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	Quit chat
}

/// The answer approve from the web to the request, given to the probe's OnProcessInput as the session; result is the AnswerResult's Result.
Method AnswerWeb(probe As OcuTalon.Test.Core.AnswersInProbe, request As %String, session As %String, Output result As %String) As %Status [ Private ]
{
	Set answer = ##class(OcuTalon.Core.Msg.Answer).%New()
	Set answer.Ref = request
	Set answer.Action = "approve"
	Set answer.Channel = "web"
	Set answer.SessionRef = session
	Set sc = probe.OnProcessInput(answer, .output)
	Set result = $Select($IsObject($Get(output)): output.Result, 1: "")
	Quit sc
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
