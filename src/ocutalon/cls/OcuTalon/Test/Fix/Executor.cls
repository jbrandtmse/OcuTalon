Include Ensemble

/// Tests of what FixExecutor does with an Execute (Stories 7.3 and 7.4; AD-11, AD-16), through a shadow instance of Test.Fix.ExecutorProbe in the test process, over fixture
/// sessions, incidents and approval requests of Test.Data.Fixture and the product's own handler, FixRun row, StartExecution and FinishExecution. The probe records the
/// FixResults that the handler sends (no production is needed to send them), the Action entries it would write and the session of each send, and stands in for the kind's
/// Recheck and Execute, for the resources check and for the read of the copies (canned statuses), so that each route is driven without an Orders production; the real
/// re-check, resend, wait and result are pinned by Test.Fix.Recheck, Execute, Refused, Runs, Results, Partial, Waits and Scale on a fresh stack. They run warm.
/// Each test asserts the FixRun rows, the request's state and Result and the recorded FixResult; a run's end also asserts that its counts and close were on disk when the
/// FixResult was sent.
///   - TestRefusedStates (AC 4): a request that is pending, rejected, expired, cancelled, executing, done or failed, an approved one past its ExpiresAt, a tool_call, a Ref
///     with no row and an empty Ref are each refused, as are a cancelled request of a closed incident and a pending one of an unregistered kind (the state decides, not
///     the row's other faults): the handler answers OK, writes no FixRun, leaves the row as it was (every column), sends no FixResult, calls neither the re-check nor the
///     resend and logs one Type 4 line that gives the case's own reason;
///   - TestStartExecutionRefusesWhatTheRefusalCheckLetsThrough (AC 3): with the refusal check let through (the probe's RefusalIs), a pending, a cancelled and an executing
///     request still are not run, because StartExecution refuses them: no FixRun, the row as it was, no FixResult, the re-check not called and one Type 4 line that says it
///     could not be started;
///   - TestCouldNotStartRoutes (AC 3, AC 5; V3): an approved request that cannot start is closed failed through FinishExecution after its FixRun is saved with no copies,
///     and one final FixResult goes: Total the number of targets, every other count 0 and the plain Reason. The service user lacking a pair of RESOURCES (or a check that
///     throws, which also logs one Type 3 warning) gives the kind's NOTALLOWED; an unregistered kind, parameters that are not one JSON object, targets that are empty, not numbers, not whole, with a leading zero,
///     repeated or not ascending, an incident that is closed and one that is missing give UNUSABLE ("OcuTalon couldn't read the approved fix"); the re-check and the resend
///     are not called;
///   - TestProductionNotRunningCannotStart (DW-368, AD-16; the matrix row 15): a target production that is stopped, suspended or network_stopped when the run starts ends the run as could not start:
///     the FixRun is saved with no copy, the request is failed, one final FixResult is Total the number of targets with every other count 0 and the reason NOTRUNNING, one Action entry is
///     written as failed, and the re-check is never called; a production that is troubled, running, timed out, not read or whose read throws goes on to the re-check (here a re-check that fails: NOREAD, as before);
///   - TestNotRunningResultNeverClaimsAChange (QA, DW-368): for a stopped, suspended and network_stopped production the result is result.couldNotStart and reads "Nothing was resent: the production isn't running. Nothing was changed.",
///     with no skip, no "changed since the dry run", and every count 0;
///   - TestUnreadable (V3): a re-check that gives an error status or throws, and a resend that gives an error before any copy, end like a run that cannot start with the reason
///     NOREAD, after the FixRun is saved, with one Type 3 warning each;
///   - TestRowIsTheTruth (AC 3; U-126): the kind's re-check and resend get the kind, the parameters and the targets of the request's row and the incident of its
///     IncidentRef, whatever the incident's failure groups hold (it has none): the row's targets, which no group names, are re-checked as they stand, and only the ones
///     the re-check passes are resent;
///   - TestFirstFixRunSaveFailsIsSavedAgain (AC 5; V3): when the first save of a run's FixRun fails, CouldNotStart is told that no FixRun was saved, saves it again
///     and the run ends like any run that could not read: one FixRun for the request and the incident (not a lost row), the request failed, the NOREAD result, one
///     Type 3 warning for the failed save of the run and none for a save of CouldNotStart;
///   - TestFixRunNeverSavedStillEnds (AC 5; V3): when the second save fails as well, the run still ends: no FixRun, the request failed, the NOREAD result, and one
///     Type 3 warning for the run that could not be saved;
///   - TestCouldNotStartReasonsRender (V3, U-141): the reason of each route that cannot start (no resources, an unusable row, a re-check that cannot read), as the
///     executor sends it, gives the key result.couldNotStart and renders whole, through Notice.ResultKey, ResultSlots and Catalog.Render, as "Nothing was resent:
///     OcuTalon isn't allowed to resend messages in that production. Nothing was changed.", "Nothing was resent: OcuTalon couldn't read the approved fix. Nothing was
///     changed." and "Nothing was resent: OcuTalon couldn't read the failed messages in that production. Nothing was changed.";
///   - TestNothingResent (AC 3, AC 5; V2): a run whose targets are all skipped (by the re-check, by the resend, or by both) closes its request done and sends one final FixResult:
///     Total and Skipped the number of targets, Resent, Completed and FailedAgain 0 and the reason of the lowest skipped target, with the counts stored and one Action entry;
///   - TestResentRunEndsWithItsCounts (AC 1, AC 3; the matrix row "Counts and reasons"): a run that resent copies counts them: 50 targets and 50 copies of which 48 completed
///     and 2 failed again with the incident's own error give 50/50/48/2/0, the reason "the order date still wasn't accepted" and the text "48 of 50 orders went through. 2 failed
///     again (the order date still wasn't accepted). I won't retry them without a new approval."; 47 copies of 50 targets, all completed, give 50/47/47/0/3 and "47 of 50 orders
///     went through. 3 had changed since the dry run, so I skipped them; they need a new approval."; a copy that is Created, Queued, Delivered or Deferred, or that the read lacks, is
///     still running (each on its own, beside a completed copy), so the run waits for the next pass; Aborted, Discarded and Suspended copies failed again, with the reason "no error text" when they have none. The
///     request is closed done, the FixRun stores the counts, ResentAt and EndedAt, and one Action entry and one FixResult are made;
///   - TestFailReasons (AC 3; V3): the reason of the failed copy with the lowest id, whichever order the copies were registered in: the incident's own error gives "the {field}
///     still wasn't accepted", another error its first sentence without the closing full stop, no error text "no error text", an error at another item the sentence too; a
///     key in the text is redacted and the reason is at most 1000 characters;
///   - TestRunThatErredAfterACopyStillWaits (AC 1): a resend that registers two copies of three targets and then fails still waits for the copies it has: the request is
///     closed done, the FixResult is 3/2/2/0/1 and reads as 2 of 3 orders went through, and one Type 3 warning (LOGRECHECK) names the request and the error;
///   - TestStillRunningAfterTheWait (AC 1): copies that stay queued past the wait leave the request executing, the FixRun without an EndedAt or counts, no FixResult and no
///     Action entry, and one Type 3 warning (LOGWAIT) that names the request and says how many copies still ran, once; a read that does not give read, or that throws, counts as still running,
///     and a read that throws logs one Type 3 warning (LOGLOOK) for the run, however many passes threw;
///   - TestOneWaiterFinishesEveryRun (AC 7, AC 8; the matrix row "One waiter for every run"): while another job holds the probe's wait lock, two Executes (two incidents) return
///     with no FixResult and both runs wait; once the lock is free one Wait sends two FixResults, each with its own Ref and counts, in its own incident's trace session
///     (TraceHeaderId) with its row's TraceRef as the SuperSession, and the host's own session is put back;
///   - TestHolderLooksOnceMoreAfterUnlocking (AC 8): a Waiting that finds no run on the waiter's first look (a run saved while it was unlocking) does not leave the run: the
///     waiter looks once more after it unlocks, takes the lock again and ends the run, with its one FixResult;
///   - TestWaiterThatErrsStopsAndReleasesTheLock (AC 8): a waiter whose read of the waiting runs throws logs one Type 3 warning (LOGWAIT, "(any)"), stops without reading a
///     copy or sending a result, leaves the request executing and the lock free (a job of its own takes it), and the next Wait ends the run;
///   - TestWaiterStopsWhenTheJobShouldQuiesceOrTerminate (AC 8): a job that Ens.Job says should quiesce, and one that should terminate, makes no pass: no copy is read, the
///     run is not given up, the request stays executing, the lock is free and the next Wait ends the run;
///   - TestFailedResentAtSaveLeavesTheRunUnwaited (AC 1): a run whose ResentAt cannot be saved after its copies were registered logs one Type 3 warning (LOGRUN), is not
///     waited for and sends no result, so the request stays executing with its FixRun holding the copies and no ResentAt or EndedAt, and a later Wait does not touch it;
///   - TestFailedEndSaveOrCloseStillSendsTheResult (AC 1): a run whose counts cannot be saved at its end logs one Type 3 warning (LOGRUN), and its request is closed done,
///     its Action entry written and its FixResult sent all the same, with no second result from a later Wait; a run whose request cannot be closed (its row was moved on)
///     logs one Type 3 warning (LOGFINISH), and its counts and EndedAt are stored, its entry written and its FixResult sent all the same;
///   - TestWaitLastsWaitSecondsFromResentAt (AC 1): on the long probe, a run whose ResentAt is 10 seconds inside the wait waits, though it started long before, and one whose
///     ResentAt is 2 seconds past the wait does not: the wait lasts WAITSECONDS from ResentAt;
///   - TestStartExecutionFailsForAnApprovedRequest (AC 11; DW-380): an approved request, not past its expiry, whose StartExecution fails ends as could not start: one FixRun, the
///     request failed, one FixResult with Total the number of targets, every other count 0 and the reason "OcuTalon couldn't start the resend", one Action entry, and
///     neither the re-check nor the resend is called; a pending, a cancelled and an executing request, and an approved one past its expiry, are refused; so is an approved
///     request whose row on disk was cancelled or started by another job while its StartExecution failed (the row is read again): no FixRun, no FixResult, the row as it was left;
///   - TestEveryRunWritesOneActionEntry (AC 5): a run that cannot start, one that resent nothing and one that resent copies each write one Action entry, with the row's FixKind,
///     the production and namespace of the incident, the result, the counts as numbers, the request's Ref, the approver and channel (the system and the job's user without
///     them), the owner as the session when that is a Ref, and no member beside the shape; a write that fails logs one Type 3 warning (LOGAUDIT) and the FixResult still goes;
///   - TestFailedSendLogsOneWarning: a send that fails logs one Type 3 warning and the request is closed all the same;
///   - TestUnknownRequest: a request that is neither a DryRun nor an Execute is the error 5001 that names its class, with no answer.
/// Story 7.5 (AD-5, AD-16, AD-18, AD-23, AD-33; DW-395) adds the ends that no waiter makes. These tests call Install.Step.Fix.ReconcileWith and Interrupt and Sweep of
/// Test.Fix.RunProbe (a Fix.Run whose seams are canned) over fixture runs, rows and incidents. The test process holds the lock of each fixture run from its save until the test
/// ends (Hold), and the runs are deleted before the locks are let go, so that the production's own Sweep, which runs on every Tick of a stack, never takes a fixture run; a test that
/// needs the lock free lets go of it (LetGo).
///   - TestInterruptMarksOnlyRunsCutByTheRestart (AC 1): of runs with no EndedAt, the one that started before the production's start and whose request is executing is marked
///     (Total and Interrupted the number of targets, no EndedAt) and its request is closed failed with the Result interrupted; a run that started after the start, one whose request is done and
///     an ended one are left; a run that is marked already keeps its mark and has its request closed; a second pass changes nothing and closes nothing; with no start time nothing is marked and
///     there is one problem; a run with no StartedAt and one that started in the second of the start are left; a read of the runs that fails is an error status;
///   - TestReconcileWarnsAndGoesOn (AC 1): ReconcileWith turns each problem into one WARN line of the step and returns OK: no start time, and a close that fails (the run stays marked);
///     a read of the runs that fails is the error status;
///   - TestSweepReportsAnInterruptedRunOnce (AC 2, AC 3): a marked run of 5 targets and 3 copies that completed ends interrupted with 5/3/3/0/0 and Interrupted 2: one final FixResult
///     with Interrupted 1, the row closed, one Action entry interrupted, one Type 4 line, and the text the UX document has it; a second Sweep returns nothing, and End refuses the ended run;
///   - TestSweepInterruptedCounts (AC 2; the matrix row "Interrupted counts"): 5 targets with 2 completed and 1 queued copy give Interrupted 3 and result.interrupted; copies that all completed give
///     result.allThrough with Interrupted 0; copies that failed again give result.failedAgain with the reason; a read that is not read, a read that throws (one Type 3 warning) and a missing
///     incident count no copy as completed;
///   - TestSweepClosesTheRowFirst (AC 2): the request is closed interrupted before the result comes back, so the key is result.interrupted; a close that fails gives no result, no EndedAt and one Type 3
///     warning, and the next Sweep reports the run; a close that throws logs one Type 3 warning and the next run is still swept;
///   - TestSweepEndsARunNoWaiterEnded (AC 4; DW-395): an unmarked run past its wait whose copies were all done inside it ends as the waiter would have ended it: Skipped is Total - Resent, Interrupted 0,
///     the row done, one Action entry done; a failed close logs one Type 3 warning and the result still comes;
///   - TestSweepLeavesRunsOfTheWaiterAndOfStory305 (AC 5): unmarked runs inside their wait, with a copy still queued, whose last copy finished after the wait or has no time, whose read is not read,
///     with no ResentAt or whose request is done get no result, no EndedAt and no close, and Sweep logs no warning and reads the copies of exactly the runs that get that far;
///   - TestSweepDecidesByTheLatestCopyTime (AC 4, AC 5; QA): the unmarked branch compares the latest time of the done copies with the end of the wait, strictly: one second before it the run ends done
///     (the latest copy first in the list, the others earlier), at the end of the wait it is left, and so is one whose copies are done but one of them has no time among others that have one, and one
///     whose latest done copy is a failed one;
///   - TestSweepGoesOnWhenTheEndFails: a marked or an unmarked run whose end cannot be saved gives no result, no entry and one Type 3 warning, and the next Sweep reports it once; a marked run whose audit
///     write throws still gives its result (one warning); an unmarked run whose close throws still gives its result and its entry (one warning);
///   - TestSweepSkipsALockedRun: a marked and an unmarked run whose locks other jobs hold are skipped, with nothing written or closed, and End and Mark refuse the marked one; once the
///     unmarked one's lock is free the next Sweep reports it, and the marked one, still held, is left (the marked one is held to the end of the test, and the unmarked one's copies are
///     of a fixture incident, which the production's own Sweep cannot read, so that no real Tick ends either);
///   - TestStartedIsTheProductionStart (AC 1): Fix.Run Started gives ^Ens.Runtime("StartTime") as a UTC stamp to the second, and the start of the instance when it is unset or not a time;
///   - TestEndRefusesAnEndedOrMarkedRun (AC 1, AC 3): End refuses an ended run, a normal end of a marked run and an interrupted end of an unmarked one, and Mark an ended or a marked run, each
///     without a write; Waiting leaves out a marked run, and a look at a marked run ends in a Finish that End refuses: nothing is closed, audited or sent, and one Type 4 line says why.
/// The fixture rows and the log lines of a test are removed after it.
Class OcuTalon.Test.Fix.Executor Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Fix.ExecutorProbe";

/// The probe with a wait of 30 seconds, for the tests that must not depend on the speed of the host (the probe's own three seconds are for the tests that sit the wait out).
Parameter LONGPROBE = "OcuTalon.Test.Fix.ExecutorProbeLong";

/// The parameters of the repair of the requests.
Parameter PARAMETERS = "{""field"":""OrderDate"",""sourceFormat"":""MM/DD/YYYY"",""targetFormat"":""YYYY-MM-DD""}";

/// The reasons that the executor gives (public text; the catalog renders them after "Nothing was resent: ").
Parameter NOTALLOWED = "OcuTalon isn't allowed to resend messages in that production";

Parameter UNUSABLE = "OcuTalon couldn't read the approved fix";

Parameter NOREAD = "OcuTalon couldn't read the failed messages in that production";

Parameter NOSTART = "OcuTalon couldn't start the resend";

Parameter NOTRUNNING = "the production isn't running";

/// The error text of a failing order of the Orders demo, whose pattern is the one of the incident's group.
Parameter ORDERDATETEXT = "The order date was not in the expected format. Expected YYYY-MM-DD, got '10/16/2026'.";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The incident Refs of the test being run (the FixRun rows that name them are deleted), comma-separated.
Property Incidents As %String(MAXLEN = "");

/// The number of the newest row of the event log when the test began.
Property LogMark As %Integer;

/// The flags of the jobs that hold a lock for the test (HoldLock: the probe's wait lock or a run's lock), comma-separated; "" when no test started one.
Property HoldFlag As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("FixExecutor", "n"))
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Incidents = ""
	Do ##class(OcuTalon.Test.Fix.RunProbe).Reset()
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Incidents, ",") {
		If $Piece(..Incidents, ",", i) '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.FixRun WHERE IncidentRef = ?", $Piece(..Incidents, ",", i))
		If $Piece(..Incidents, ",", i) '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.FailureGroup WHERE IncidentRef = ?", $Piece(..Incidents, ",", i))
	}
	Do ..ReleaseLock()
	Do ..FreeRuns()
	Do ##class(OcuTalon.Test.Fix.RunProbe).Reset()
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Set ..Incidents = ""
	Do ..RemoveLogs()
	Quit $$$OK
}

Method TestRefusedStates()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set owner = ..Owner("refused")
	Set incident = ..Incident(owner)
	Set closed = ..Incident(owner, {"State": "closed", "ClosedAt": "2030-01-01T10:00:00Z"})
	Set cases = $ListBuild("pending", "rejected", "expired", "cancelled", "executing", "done", "failed", "past expiry", "tool_call", "unknown", "empty", "cancelled on a closed incident", "pending of an unknown kind")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set where = incident
		Set because = "not approved"
		If case = "unknown" {
			Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
			Set because = "no approval request"
		} ElseIf case = "empty" {
			Set ref = ""
			Set because = "no approval request"
		} ElseIf case = "past expiry" {
			Set ref = ..Request(owner, incident, "approved", {"ExpiresAt": "2020-01-01T00:00:00Z"})
			Set because = "past its expiry"
		} ElseIf case = "tool_call" {
			Set ref = ..Request(owner, incident, "approved", {"Kind": "tool_call"})
			Set because = "not a fix"
		} ElseIf case = "cancelled on a closed incident" {
			Set where = closed
			Set ref = ..Request(owner, closed, "cancelled")
		} ElseIf case = "pending of an unknown kind" {
			Set ref = ..Request(owner, incident, "pending", {"FixKind": "zz_fix"})
		} Else {
			Set ref = ..Request(owner, incident, case)
		}
		Set whole = ..Whole(ref)
		Set infos = ..Infos()
		Set before = $Select($IsObject(host.Results): host.Results.%Size(), 1: 0)
		Do $$$AssertStatusOK(..Send(host, ref), case_": the Execute is handled")
		Do $$$AssertEquals(..Whole(ref), whole, case_": the row is as it was, every column")
		Do $$$AssertEquals(..Runs(where).%Size(), 0, case_": no FixRun is written")
		Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0), before, case_": no FixResult is sent")
		Do $$$AssertEquals(..Calls(host), 0, case_": neither the re-check nor the resend is called")
		Do $$$AssertEquals(..Infos() - infos, 1, case_": one info line is logged")
		Set line = ..RefusedLine(ref)
		Do $$$AssertTrue($Find(line, because) > 0, case_": and it says '"_because_"': "_line)
	}
}

Method TestStartExecutionRefusesWhatTheRefusalCheckLetsThrough()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set host.RefusalIs = "none"
	Set owner = ..Owner("startrefused")
	Set incident = ..Incident(owner)
	For state = "pending", "cancelled", "executing" {
		Set ref = ..Request(owner, incident, state)
		Set whole = ..Whole(ref)
		Set infos = ..Infos()
		Set before = $Select($IsObject(host.Results): host.Results.%Size(), 1: 0)
		Do $$$AssertStatusOK(..Send(host, ref), state_": the Execute is handled")
		Do $$$AssertEquals(..Whole(ref), whole, state_": the row is as it was, every column")
		Do $$$AssertEquals(..Runs(incident).%Size(), 0, state_": no FixRun is written")
		Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0), before, state_": no FixResult is sent")
		Do $$$AssertEquals(..Calls(host), 0, state_": neither the re-check nor the resend is called")
		Do $$$AssertEquals(..Infos() - infos, 1, state_": one info line is logged")
		Set line = ..RefusedLine(ref)
		Do $$$AssertTrue($Find(line, "could not be started") > 0, state_": and it says that StartExecution refused it: "_line)
	}
}

Method TestCouldNotStartRoutes()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("start")
	Set incident = ..Incident(owner)

	// no resources: a pair is missing, or the check throws
	For missing = "%Ens_MessageResend:U", "throw" {
		Set host.MissingIs = missing
		Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
		Set ref = ..Request(owner, incident, "approved")
		Do $$$AssertStatusOK(..Send(host, ref), "an approved request with '"_missing_"' missing is handled")
		Do ..AssertEnded(host, ref, incident, "failed|failed|finished", 3, ..#NOTALLOWED, "resources "_missing)
		Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Unchecked", $Parameter(..#PROBE, "LOGMISSING")_ref)
		Do $$$AssertEquals(warned, $Select(missing = "throw": 1, 1: 0), "resources "_missing_": "_$Select(missing = "throw": "one Type 3 warning names the request: "_text, 1: "no warning"))
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Unchecked", $Parameter(..#PROBE, "LOGMISSING"))
	}
	Set host.MissingIs = "none"

	// the row cannot be used
	Set closed = ..Incident(owner, {"State": "closed", "ClosedAt": "2030-01-01T10:00:00Z"})
	Set gone = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Incidents = ..Incidents _ "," _ gone
	Do ..AddCase(.bad, "an unknown kind", incident, "{""FixKind"":""zz_fix""}", 3)
	Do ..AddCase(.bad, "a kind in other letters", incident, "{""FixKind"":""Repair_Resend""}", 3)
	Do ..AddCase(.bad, "parameters that are an array", incident, "{""FixParameters"":""[1]""}", 3)
	Do ..AddCase(.bad, "parameters that are text", incident, "{""FixParameters"":""not json""}", 3)
	Do ..AddCase(.bad, "parameters that are a string", incident, "{""FixParameters"":""\""x\""""}", 3)
	Do ..AddCase(.bad, "no parameters", incident, "{""FixParameters"":""""}", 3)
	Do ..AddCase(.bad, "targets that are not numbers", incident, "{""FixTargets"":""101,abc""}", 2)
	Do ..AddCase(.bad, "targets that descend", incident, "{""FixTargets"":""102,101""}", 2)
	Do ..AddCase(.bad, "targets that repeat", incident, "{""FixTargets"":""101,101,102""}", 3)
	Do ..AddCase(.bad, "no targets", incident, "{""FixTargets"":""""}", 0)
	Do ..AddCase(.bad, "a target of 0", incident, "{""FixTargets"":""0,5""}", 2)
	Do ..AddCase(.bad, "a target with a leading zero", incident, "{""FixTargets"":""0101""}", 1)
	Do ..AddCase(.bad, "a negative target", incident, "{""FixTargets"":""-1""}", 1)
	Do ..AddCase(.bad, "a target that is not whole", incident, "{""FixTargets"":""101,1.5""}", 2)
	Do ..AddCase(.bad, "a closed incident", closed, "", 3)
	Do ..AddCase(.bad, "an incident that is gone", gone, "", 3)
	Set n = ""
	For {
		Set n = $Order(bad(n), 1, case)
		Quit:n=""
		Set label = $List(case, 1)
		Set ref = ..Request(owner, $List(case, 2), "approved", $Select($List(case, 3) = "": "", 1: {}.%FromJSON($List(case, 3))))
		Do $$$AssertStatusOK(..Send(host, ref), label_": the Execute is handled")
		Do ..AssertEnded(host, ref, $List(case, 2), "failed|failed|finished", $List(case, 4), ..#UNUSABLE, label)
	}
}

Method TestProductionNotRunningCannotStart()
{
	Set owner = ..Owner("notrunning")
	Set incident = ..Incident(owner)
	For state = "stopped", "suspended", "network_stopped" {
		Set host = ..Host()
		If '$IsObject(host) Quit
		Set host.MissingIs = "none"
		Set host.StateIs = state
		Set host.CheckIs = "{""passed"":""101,102,103"",""skipped"":[]}"
		Set ref = ..Request(owner, incident, "approved")
		Do $$$AssertStatusOK(..Send(host, ref), "a fix whose production is "_state_" is handled")
		Do ..AssertEnded(host, ref, incident, "failed|failed|finished", 3, ..#NOTRUNNING, state)
		Do $$$AssertEquals(..Calls(host), 0, state_": the re-check is never called")
		Do $$$AssertEquals(..LastResult(host).skipped, 0, state_": no target is reported as skipped")
	}
	For state = "troubled", "running", "timeout", "none", "throw" {
		Set host = ..Host()
		If '$IsObject(host) Quit
		Set host.MissingIs = "none"
		Set host.StateIs = state
		Set host.CheckIs = "error"
		Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
		Set ref = ..Request(owner, incident, "approved")
		Do $$$AssertStatusOK(..Send(host, ref), "a fix whose production state is '"_state_"' is handled")
		Do ..AssertEnded(host, ref, incident, "failed|failed|finished", 3, ..#NOREAD, "state "_state)
		Do $$$AssertEquals(..Calls(host), "1/0", "state "_state_": the run goes on to the re-check")
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Run", $Parameter(..#PROBE, "LOGRECHECK"))
	}
}

/// (QA, DW-368; AD-16) The result of a run that could not start because the production is not running reads as that, in the words of the catalog, and claims no change:
/// the key is result.couldNotStart (never the skipped result), the text is the whole sentence, and it names neither a skip nor an order that changed.
Method TestNotRunningResultNeverClaimsAChange()
{
	Set owner = ..Owner("notrunningtext")
	Set incident = ..Incident(owner)
	For state = "stopped", "suspended", "network_stopped" {
		Set host = ..Host()
		If '$IsObject(host) Quit
		Set host.MissingIs = "none"
		Set host.StateIs = state
		Set ref = ..Request(owner, incident, "approved")
		Do $$$AssertStatusOK(..Send(host, ref), "a fix whose production is "_state_" is handled")
		Set last = ..LastResult(host)
		Do $$$AssertTrue($IsObject(last), state_": a FixResult was sent")
		If '$IsObject(last) Continue
		Set text = ..Render(last, "failed", .key)
		Do $$$AssertEquals(key, "result.couldNotStart", state_": the key is couldNotStart")
		Do $$$AssertEquals(text, "Nothing was resent: the production isn't running. Nothing was changed.", state_": the whole text")
		Do $$$AssertTrue('(text [ "changed since") && '(text [ "dry run") && '(text [ "skipped"), state_": it claims no skip and no change in the orders: "_text)
		Do $$$AssertEquals(last.resent_"|"_last.completed_"|"_last.failedAgain_"|"_last.skipped, "0|0|0|0", state_": and no count says that anything was resent or skipped")
	}
}

Method TestUnreadable()
{
	Set owner = ..Owner("unreadable")
	Set incident = ..Incident(owner)
	For case = "error", "throw" {
		Set host = ..Host()
		If '$IsObject(host) Quit
		Set host.MissingIs = "none"
		Set host.CheckIs = case
		Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
		Set ref = ..Request(owner, incident, "approved")
		Do $$$AssertStatusOK(..Send(host, ref), "a re-check that gives '"_case_"' is handled")
		Do ..AssertEnded(host, ref, incident, "failed|failed|finished", 3, ..#NOREAD, "re-check "_case)
		Do $$$AssertEquals(..Warnings(mark, ref), 1, "re-check "_case_": one Type 3 warning names the request")
		Do $$$AssertEquals(..Calls(host), "1/0", "re-check "_case_": the re-check ran once and the resend not at all")
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Run", $Parameter(..#PROBE, "LOGRECHECK"))
	}
	// the resend gives an error before any copy: the same end
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set host.CheckIs = "{""passed"":""101,102,103"",""skipped"":[]}"
	Set host.CarryIs = "error"
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ref = ..Request(owner, incident, "approved")
	Do $$$AssertStatusOK(..Send(host, ref), "a resend that gives an error before any copy is handled")
	Do ..AssertEnded(host, ref, incident, "failed|failed|finished", 3, ..#NOREAD, "resend error")
	Do $$$AssertEquals(..Warnings(mark, ref), 1, "resend error: one Type 3 warning names the request")
	Do $$$AssertEquals(..Calls(host), "1/1", "resend error: the re-check and the resend ran once")
}

Method TestRowIsTheTruth()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set owner = ..Owner("truth")
	Set incident = ..Incident(owner)
	Set parameters = "{""field"":""ShipDate"",""sourceFormat"":""DD/MM/YYYY"",""targetFormat"":""YYYY-MM-DD""}"
	Set host.CheckIs = "{""passed"":""12"",""skipped"":[{""id"":7,""reason"":""message 7 has been resent already""},{""id"":500,""reason"":""message 500 is no longer in the production""}]}"
	Set host.CarryIs = "{""copies"":[""9001""],""skipped"":[]}"
	Set ref = ..Request(owner, incident, "approved", {"FixParameters": (parameters), "FixTargets": "7,12,500"})
	Do $$$AssertStatusOK(..Send(host, ref), "a request whose targets no failure group of its incident names is handled")
	Do $$$AssertEquals(..Calls(host), "1/1", "the re-check and the resend each ran once")
	If ..Calls(host) '= "1/1" Quit
	Set checked = host.Checked.%Get(0)
	Do $$$AssertEquals(checked.class_"|"_checked.incident, "OcuTalon.Fix.Kind.RepairResend|"_incident, "the re-check is the row's kind, over the incident that the row names")
	Do $$$AssertEquals(checked.parameters, parameters, "with the row's own parameters")
	Do $$$AssertEquals(checked.targets, "7,12,500", "and exactly the row's targets, whatever the incident's groups hold")
	Set carried = host.Carried.%Get(0)
	Do $$$AssertEquals(carried.class_"|"_carried.incident_"|"_carried.parameters, checked.class_"|"_incident_"|"_parameters, "the resend is the same kind over the same incident with the same parameters")
	Do $$$AssertEquals(carried.targets, "12", "and only the target that the re-check passed")
	Set run = ##class(OcuTalon.Test.Watch.Case).RunOf(incident, ref)
	Do $$$AssertTrue($IsObject(run), "the request has a FixRun")
	If $IsObject(run) Do $$$AssertEquals(run.copies.%ToJSON(), "[""9001""]", "which holds the one copy that was made")
	Do $$$AssertEquals(..Row(ref), "executing||", "and the request stays executing: the probe waits for no incident here, so the copy is not counted")
}

Method TestFirstFixRunSaveFailsIsSavedAgain()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set host.SaveFails = 1
	Set owner = ..Owner("save1")
	Set incident = ..Incident(owner)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ref = ..Request(owner, incident, "approved")
	Do $$$AssertStatusOK(..Send(host, ref), "an approved request whose first FixRun save fails is handled")
	Do $$$AssertEquals(host.SavedWas, 0, "CouldNotStart was told that no FixRun had been saved")
	Do ..AssertEnded(host, ref, incident, "failed|failed|finished", 3, ..#NOREAD, "first save fails")
	Do $$$AssertEquals(..Runs(incident).%Size(), 1, "the request's FixRun is not lost: the incident has exactly one")
	Do $$$AssertEquals(..Warnings(mark, ref), 1, "one Type 3 warning names the request: the failed save of the run")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "CouldNotStart", $Parameter(..#PROBE, "LOGRUN")_ref), 0, "and the save that followed worked: no warning for it")
	Do $$$AssertEquals(..Calls(host), 0, "the re-check and the resend never ran")
}

Method TestFixRunNeverSavedStillEnds()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set host.SaveFails = 2
	Set owner = ..Owner("save2")
	Set incident = ..Incident(owner)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ref = ..Request(owner, incident, "approved")
	Do $$$AssertStatusOK(..Send(host, ref), "an approved request whose FixRun cannot be saved at all is handled")
	Do $$$AssertEquals(host.SavedWas, 0, "CouldNotStart was told that no FixRun had been saved")
	Do $$$AssertEquals(..Row(ref), "failed|failed|finished", "the request is closed failed all the same")
	Do $$$AssertEquals(..Runs(incident).%Size(), 0, "no FixRun is stored for the incident")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.FixRun WHERE ApprovalRef = ?", ref)
	Do rs.%Next()
	Do $$$AssertEquals(+rs.%GetData(1), 0, "and none for the request")
	Set last = ..LastResult(host)
	Do $$$AssertTrue($IsObject(last), "a FixResult was sent")
	If $IsObject(last) {
		Do $$$AssertEquals(last.approvalRef_"|"_last.incidentRef_"|"_last.final_"|"_last.interrupted, ref_"|"_incident_"|1|0", "it names the request and the incident and is final")
		Do $$$AssertEquals(last.total_"|"_last.resent_"|"_last.completed_"|"_last.failedAgain_"|"_last.skipped, "3|0|0|0|0", "with Total 3 and every other count 0")
		Do $$$AssertEquals(last.reason, ..#NOREAD, "and the reason")
	}
	Do $$$AssertEquals(..Warnings(mark, ref), 1, "one Type 3 warning names the request: the failed save of the run")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "CouldNotStart", $Parameter(..#PROBE, "LOGRUN")_ref)
	Do $$$AssertEquals(warned, 1, "and one more says that the run could not be saved: "_text)
	Do $$$AssertEquals(..Calls(host), 0, "the re-check and the resend never ran")
}

Method TestCouldNotStartReasonsRender()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("render")
	Set incident = ..Incident(owner)

	// no resources, an unusable row, a re-check that cannot read: one approved request each
	Set host.MissingIs = "%Ens_MessageResend:U"
	Set first = ..Request(owner, incident, "approved")
	Do $$$AssertStatusOK(..Send(host, first), "a request that lacks its resources is handled")
	Set host.MissingIs = "none"
	Set second = ..Request(owner, incident, "approved", {"FixKind": "zz_fix"})
	Do $$$AssertStatusOK(..Send(host, second), "a request of an unregistered kind is handled")
	Set host.CheckIs = "error"
	Set third = ..Request(owner, incident, "approved")
	Do $$$AssertStatusOK(..Send(host, third), "a request whose failed messages cannot be read is handled")
	Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0), 3, "each sent one FixResult")
	If '$IsObject(host.Results) || (host.Results.%Size() '= 3) Quit

	Set expected(0) = "Nothing was resent: OcuTalon isn't allowed to resend messages in that production. Nothing was changed."
	Set expected(1) = "Nothing was resent: OcuTalon couldn't read the approved fix. Nothing was changed."
	Set expected(2) = "Nothing was resent: OcuTalon couldn't read the failed messages in that production. Nothing was changed."
	Set label(0) = "no resources"
	Set label(1) = "an unusable row"
	Set label(2) = "a re-check that cannot read"
	For i = 0:1:2 {
		Set text = ..Render(host.Results.%Get(i), "failed", .key)
		Do $$$AssertEquals(key, "result.couldNotStart", label(i)_": the key of the result")
		Do $$$AssertEquals(text, expected(i), label(i)_": the whole text")
	}
}

Method TestNothingResent()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set owner = ..Owner("nothing")

	// the re-check skips every target; the lowest id's reason is the Reason
	Set incident = ..Incident(owner)
	Set host.CheckIs = "{""passed"":"""",""skipped"":[{""id"":103,""reason"":""message 103 is gone""},{""id"":101,""reason"":""message 101 is no longer in the error status""},{""id"":102,""reason"":""message 102 is gone""}]}"
	Set ref = ..Request(owner, incident, "approved")
	Do $$$AssertStatusOK(..Send(host, ref), "a run whose targets all fail the re-check is handled")
	Do ..AssertEnded(host, ref, incident, "done|done|finished", 3, "message 101 is no longer in the error status", "re-check skips all", 3)
	Do $$$AssertEquals(..Calls(host), "1/0", "the resend was not called: nothing passed")

	// the resend skips every target
	Set incident = ..Incident(owner)
	Set host.CheckIs = "{""passed"":""101,102,103"",""skipped"":[]}"
	Set host.CarryIs = "{""copies"":[],""skipped"":[{""id"":102,""reason"":""message 102 was not resent because the production isn't running""},{""id"":101,""reason"":""message 101 was not resent because the production isn't running""},{""id"":103,""reason"":""message 103 was not resent because the production isn't running""}]}"
	Set ref = ..Request(owner, incident, "approved")
	Do $$$AssertStatusOK(..Send(host, ref), "a run whose copies are all skipped is handled")
	Do ..AssertEnded(host, ref, incident, "done|done|finished", 3, "message 101 was not resent because the production isn't running", "resend skips all", 3)
	Do $$$AssertEquals(..Calls(host), "2/1", "the resend was called once, with the targets that passed")
	Do $$$AssertEquals(host.Carried.%Get(0).targets, "101,102,103", "with all of them")

	// both skip some: the lowest id's reason, whichever skipped it
	Set incident = ..Incident(owner)
	Set host.CheckIs = "{""passed"":""102,103"",""skipped"":[{""id"":101,""reason"":""message 101 has been resent already""}]}"
	Set host.CarryIs = "{""copies"":[],""skipped"":[{""id"":103,""reason"":""c""},{""id"":102,""reason"":""b""}]}"
	Set ref = ..Request(owner, incident, "approved")
	Do $$$AssertStatusOK(..Send(host, ref), "a run whose targets are skipped by both is handled")
	Do ..AssertEnded(host, ref, incident, "done|done|finished", 3, "message 101 has been resent already", "both skip", 3)
}

Method TestResentRunEndsWithItsCounts()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set owner = ..Owner("counts")
	Set own = "The order date was not in the expected format. Expected YYYY-MM-DD, got '16/10/2026'."

	// 50 targets and 50 copies: 48 completed and 2 failed again with the incident's own error
	Set incident = ..Incident(owner)
	Do ..Group(incident, "OrdersFromPartner", ..#ORDERDATETEXT)
	Set host.Incidents = incident
	Set host.CheckIs = "{""passed"":"""_..TargetList(50)_""",""skipped"":[]}"
	Set host.CarryIs = ..CarryJSON(9001, 50)
	Set statuses = ..Canned(9001, 50, "Completed")
	Do statuses.%Set("9005", {"status": "Error", "error": (own), "target": "OrdersFromPartner"})
	Do statuses.%Set("9040", {"status": "Error", "error": (own), "target": "OrdersFromPartner"})
	Set host.StatusIs = statuses.%ToJSON()
	Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(50))})
	Do $$$AssertStatusOK(..Send(host, ref), "a run of 50 targets and 50 copies is handled")
	Do ..AssertCounted(host, ref, incident, "done|done|finished", "50|50|48|2|0", "the order date still wasn't accepted", "48 of 50 copies completed", "48 of 50 orders went through. 2 failed again (the order date still wasn't accepted). I won't retry them without a new approval.")
	Do $$$AssertEquals(host.Reads, 1, "the copies were all done at the first pass: one read")

	// 47 copies of 50 targets, all completed: 3 targets were skipped
	Set incident = ..Incident(owner)
	Set host.Incidents = incident
	Set host.CarryIs = ..CarryJSON(9101, 47)
	Set host.StatusIs = ..Canned(9101, 47, "Completed").%ToJSON()
	Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(50))})
	Do $$$AssertStatusOK(..Send(host, ref), "a run of 50 targets and 47 copies is handled")
	Do ..AssertCounted(host, ref, incident, "done|done|finished", "50|47|47|0|3", "", "47 copies of 50 targets", "47 of 50 orders went through. 3 had changed since the dry run, so I skipped them; they need a new approval.")

	// a copy that is Created, Queued, Delivered or Deferred, or that the read lacks, is still running: beside a completed copy, the first read ends nothing and the second finds both completed
	Set states = $ListBuild("Created", "Queued", "Delivered", "Deferred", "missing")
	Set position = 0
	Set first = 9200
	While $ListNext(states, position, state) {
		Set first = first + 10
		Set incident = ..Incident(owner)
		Set host.Incidents = incident
		Set host.CheckIs = "{""passed"":"""_..TargetList(2)_""",""skipped"":[]}"
		Set host.CarryIs = ..CarryJSON(first, 2)
		Set pending = ..Canned(first, 2, "Completed")
		If state = "missing" {
			Do pending.%Remove((first + 1)_"")
		} Else {
			Do pending.%Set((first + 1)_"", {"status": (state), "error": "", "target": "OrdersFromPartner"})
		}
		Set host.StatusIs = pending.%ToJSON()
		Set host.StatusThen = ..Canned(first, 2, "Completed").%ToJSON()
		Set host.ThenAfter = 1
		Set host.Reads = 0
		Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(2))})
		Do $$$AssertStatusOK(..Send(host, ref), state_": a run with a copy that is "_state_" at the first read is handled")
		Do $$$AssertEquals(host.Reads, 2, state_": the wait read twice: a copy that is "_state_" is not done")
		Do ..AssertCounted(host, ref, incident, "done|done|finished", "2|2|2|0|0", "", state_": the second read", "All 2 orders went through.")
	}
	Set host.StatusThen = ""
	Set host.ThenAfter = 0

	// Aborted, Discarded and Suspended copies failed again; with no error text the reason says so
	Set incident = ..Incident(owner)
	Set host.Incidents = incident
	Set host.CheckIs = "{""passed"":"""_..TargetList(3)_""",""skipped"":[]}"
	Set host.CarryIs = ..CarryJSON(9301, 3)
	Set failed = {}
	Do failed.%Set("9301", {"status": "Aborted", "error": "", "target": "OrdersFromPartner"})
	Do failed.%Set("9302", {"status": "Discarded", "error": "", "target": "OrdersFromPartner"})
	Do failed.%Set("9303", {"status": "Suspended", "error": "", "target": "OrdersFromPartner"})
	Set host.StatusIs = failed.%ToJSON()
	Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(3))})
	Do $$$AssertStatusOK(..Send(host, ref), "a run whose copies were aborted, discarded and suspended is handled")
	Do ..AssertCounted(host, ref, incident, "done|done|finished", "3|3|0|3|0", "no error text", "Aborted, Discarded and Suspended", "0 of 3 orders went through. 3 failed again (no error text). I won't retry them without a new approval.")
}

Method TestFailReasons()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set owner = ..Owner("reasons")
	Set own = "The order date was not in the expected format. Expected YYYY-MM-DD, got '16/10/2026'."
	// Built from parts, so that no key-shaped literal is committed (the boundaries check).
	Set key = "sk"_"-ant-"_"api03-ZQXJVKWBNMLPDRTYUHGF"
	Set long = $Translate($Justify("", 3000), " ", "a")
	Set cases = $ListBuild("own", "other", "unfinished", "none", "lowest", "elsewhere", "key", "long")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set incident = ..Incident(owner)
		Do ..Group(incident, "OrdersFromPartner", ..#ORDERDATETEXT)
		Set host.Incidents = incident
		Set host.CheckIs = "{""passed"":"""_..TargetList(2)_""",""skipped"":[]}"
		Set host.CarryIs = ..CarryJSON(9501, 2)
		Set statuses = ..Canned(9501, 2, "Completed")
		Set expected = ""
		If case = "own" {
			Do statuses.%Set("9501", {"status": "Error", "error": (own), "target": "OrdersFromPartner"})
			Set expected = "the order date still wasn't accepted"
		} ElseIf case = "other" {
			Do statuses.%Set("9501", {"status": "Error", "error": "The stock level is below zero. Expected 0 or more, got -3.", "target": "OrdersFromPartner"})
			Set expected = "The stock level is below zero"
		} ElseIf case = "unfinished" {
			Do statuses.%Set("9501", {"status": "Error", "error": "Field 'Qty' was empty", "target": "OrdersFromPartner"})
			Set expected = "Field 'Qty' was empty"
		} ElseIf case = "none" {
			Do statuses.%Set("9501", {"status": "Error", "error": "", "target": "OrdersFromPartner"})
			Set expected = "no error text"
		} ElseIf case = "lowest" {
			Set host.CarryIs = ..CarryList("9510,9509")
			Set statuses = {}
			Do statuses.%Set("9510", {"status": "Error", "error": (own), "target": "OrdersFromPartner"})
			Do statuses.%Set("9509", {"status": "Error", "error": "The stock level is below zero. Expected 0 or more, got -3.", "target": "OrdersFromPartner"})
			Set expected = "The stock level is below zero"
		} ElseIf case = "elsewhere" {
			Do statuses.%Set("9501", {"status": "Error", "error": (own), "target": "SomeOtherItem"})
			Set expected = "The order date was not in the expected format"
		} ElseIf case = "key" {
			Do statuses.%Set("9501", {"status": "Error", "error": ("The token "_key_" was refused. Try again later."), "target": "OrdersFromPartner"})
		} Else {
			Do statuses.%Set("9501", {"status": "Error", "error": (long), "target": "OrdersFromPartner"})
		}
		Set host.StatusIs = statuses.%ToJSON()
		Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(2))})
		Do $$$AssertStatusOK(..Send(host, ref), case_": the run is handled")
		Set last = ..LastResult(host)
		Do $$$AssertTrue($IsObject(last), case_": a FixResult was sent")
		If '$IsObject(last) Continue
		Do $$$AssertEquals(last.approvalRef_"|"_last.failedAgain, ref_"|"_$Select(case = "lowest": 2, 1: 1), case_": the run's FixResult counts the copies that failed again")
		If case = "key" {
			Do $$$AssertTrue((last.reason [ "[redacted]") && (last.reason '[ "ZQXJVKWBNMLPDRTYUHGF"), case_": the key in the error text is redacted: "_last.reason)
		} ElseIf case = "long" {
			Do $$$AssertTrue(($Length(last.reason) > 0) && ($Length(last.reason) '> 1000), case_": the reason is cut: "_$Length(last.reason)_" characters")
		} Else {
			Do $$$AssertEquals(last.reason, expected, case_": the reason")
		}
		Set run = ##class(OcuTalon.Test.Watch.Case).RunOf(incident, ref)
		If $IsObject(run) Do $$$AssertEquals(run.reason, last.reason, case_": the FixRun stores the same reason")
	}
}

Method TestRunThatErredAfterACopyStillWaits()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set owner = ..Owner("partway")
	Set incident = ..Incident(owner)
	Set host.Incidents = incident
	Set host.CheckIs = "{""passed"":"""_..TargetList(3)_""",""skipped"":[]}"
	Set carry = {}.%FromJSON(..CarryJSON(9401, 2))
	Do carry.%Set("fail", "The resend stopped")
	Set host.CarryIs = carry.%ToJSON()
	Set host.StatusIs = ..Canned(9401, 2, "Completed").%ToJSON()
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(3))})
	Do $$$AssertStatusOK(..Send(host, ref), "a run whose resend stopped after two copies is handled")
	Do ..AssertCounted(host, ref, incident, "done|done|finished", "3|2|2|0|1", "", "the two copies made", "2 of 3 orders went through. 1 had changed since the dry run, so I skipped it; it needs a new approval.")
	Do $$$AssertEquals(host.Reads, 1, "the wait read the two copies the run had")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Run", $Parameter(..#PROBE, "LOGRECHECK")_ref)
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the request: "_text)
	Do $$$AssertTrue($Find(text, "The resend stopped") > 0, "and says why the resend stopped")
}

Method TestStillRunningAfterTheWait()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set owner = ..Owner("running")
	Set incident = ..Incident(owner)
	Set host.Incidents = incident
	Set host.CheckIs = "{""passed"":"""_..TargetList(3)_""",""skipped"":[]}"
	Set host.CarryIs = ..CarryJSON(9601, 3)
	Set host.StatusIs = ..Canned(9601, 3, "Queued").%ToJSON()
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(3))})
	Set started = $ZHorolog
	Do $$$AssertStatusOK(..Send(host, ref), "a run whose copies stay queued is handled")
	Set waited = $ZHorolog - started
	Do $$$AssertTrue(waited '< ($Parameter(..#PROBE, "WAITSECONDS") - 1), "the handler waited the probe's "_$Parameter(..#PROBE, "WAITSECONDS")_" seconds from ResentAt, a stamp to the second: "_$Justify(waited, 0, 2))
	Do $$$AssertEquals(..Row(ref), "executing||", "the request stays executing, with no Result and no FinishedAt")
	Set run = ##class(OcuTalon.Test.Watch.Case).RunOf(incident, ref)
	Do $$$AssertTrue($IsObject(run), "the request has a FixRun")
	If $IsObject(run) {
		Do $$$AssertEquals((run.resentAt '= "")_"|"_run.endedAt_"|"_run.total_run.resent_run.completed_run.failedAgain_run.skipped_run.reason, "1||", "which has a ResentAt and no EndedAt and no counts")
		Do $$$AssertEquals(run.copies.%Size(), 3, "and holds the three copies")
	}
	Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0), 0, "no FixResult is sent")
	Do $$$AssertEquals($Select($IsObject(host.Audits): host.Audits.%Size(), 1: 0), 0, "and no Action entry is written")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Pass", $Parameter(..#PROBE, "LOGWAIT")_ref)
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the request: "_text)
	Do $$$AssertTrue($Find(text, "3 of 3 copies") > 0, "and says that 3 of 3 copies were still running")

	// the run is not waited for any more: another wait neither warns again nor sends anything
	Do host.WaitNow()
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Pass", $Parameter(..#PROBE, "LOGWAIT")_ref), 1, "a later Wait logs no second warning")
	Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0), 0, "and sends no result")
	Do $$$AssertEquals(..Row(ref), "executing||", "the request is still executing")

	// a read that does not give read counts as still running
	Set incident = ..Incident(owner)
	Set host.Incidents = incident
	Set host.CarryIs = ..CarryJSON(9701, 3)
	Set host.StatusIs = ..Canned(9701, 3, "Completed").%ToJSON()
	Set host.StatusOutcome = "unreadable"
	Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(3))})
	Do $$$AssertStatusOK(..Send(host, ref), "a run whose copies cannot be read is handled")
	Do $$$AssertEquals(..Row(ref), "executing||", "its request stays executing: an unreadable copy is never counted as completed")
	Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0), 0, "and no FixResult is sent")
	Set host.StatusOutcome = ""

	// a read that throws: one Type 3 warning for the run, however many passes threw, and the request stays executing
	Set incident = ..Incident(owner)
	Set host.Incidents = incident
	Set host.CarryIs = ..CarryJSON(9751, 3)
	Set host.StatusIs = ..Canned(9751, 3, "Completed").%ToJSON()
	Set host.StatusOutcome = "throw"
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(3))})
	Do $$$AssertStatusOK(..Send(host, ref), "a run whose copies cannot be read, because the read throws, is handled")
	Do $$$AssertEquals(..Row(ref), "executing||", "its request stays executing: a copy that cannot be read is never counted as completed")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Pass", $Parameter(..#PROBE, "LOGLOOK")_ref)
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the request, however many passes threw: "_text)
	Do $$$AssertTrue($Find(text, "The read threw") > 0, "and says why the copies could not be read")
	Set host.StatusOutcome = ""
}

Method TestOneWaiterFinishesEveryRun()
{
	Set host = ..Host(..#LONGPROBE)
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set owner = ..Owner("waiter")
	Set own = "The order date was not in the expected format. Expected YYYY-MM-DD, got '16/10/2026'."
	Set incidentA = ..Incident(owner, {"TraceHeaderId": 9201001})
	Set incidentB = ..Incident(owner, {"TraceHeaderId": 9201002})
	Do ..Group(incidentA, "OrdersFromPartner", ..#ORDERDATETEXT)
	Do ..Group(incidentB, "OrdersFromPartner", ..#ORDERDATETEXT)
	Set host.Incidents = incidentA_","_incidentB
	Set traceA = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set traceB = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set statuses = ..Canned(9801, 3, "Completed")
	Do statuses.%Set("9901", {"status": "Completed", "error": "", "target": "OrdersFromPartner"})
	Do statuses.%Set("9902", {"status": "Error", "error": (own), "target": "OrdersFromPartner"})
	Set host.StatusIs = statuses.%ToJSON()
	Set lock = $Parameter(..#PROBE, "WAITLOCK")
	Set flag = "hold"_..Number
	Set ..HoldFlag = flag
	Set ^OcuTalonTest("FixExecutor", flag) = ""
	Job ##class(OcuTalon.Test.Fix.Executor).HoldLock(lock, flag)
	Set end = $ZHorolog + 10
	While ($Get(^OcuTalonTest("FixExecutor", flag)) '= "held") && ($ZHorolog < end) {
		Hang 0.1
	}
	Do $$$AssertEquals($Get(^OcuTalonTest("FixExecutor", flag)), "held", "another job holds the probe's wait lock")
	If $Get(^OcuTalonTest("FixExecutor", flag)) '= "held" {
		Kill ^OcuTalonTest("FixExecutor", flag)
		Quit
	}
	Set own1 = host.%SessionId
	Set host.CheckIs = "{""passed"":"""_..TargetList(3)_""",""skipped"":[]}"
	Set host.CarryIs = ..CarryJSON(9801, 3)
	Set r1 = ..Request(owner, incidentA, "approved", {"FixTargets": (..TargetList(3)), "TraceRef": (traceA)})
	Do $$$AssertStatusOK(..Send(host, r1), "the first Execute is handled")
	Set host.CheckIs = "{""passed"":""201,202"",""skipped"":[]}"
	Set host.CarryIs = ..CarryJSON(9901, 2)
	Set r2 = ..Request(owner, incidentB, "approved", {"FixTargets": "201,202", "TraceRef": (traceB)})
	Do $$$AssertStatusOK(..Send(host, r2), "and so is the second, of another incident")
	Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0), 0, "neither sent a FixResult: the job that holds the lock finishes them")
	Do $$$AssertEquals(..Row(r1)_"#"_..Row(r2), "executing||#executing||", "both requests are executing")
	Set runA = ##class(OcuTalon.Test.Watch.Case).RunOf(incidentA, r1)
	Set runB = ##class(OcuTalon.Test.Watch.Case).RunOf(incidentB, r2)
	Do $$$AssertTrue($IsObject(runA) && $IsObject(runB) && (runA.resentAt '= "") && (runB.resentAt '= "") && (runA.endedAt = "") && (runB.endedAt = ""), "and both runs wait: each has a ResentAt and no EndedAt")

	// the lock is free: one Wait ends both
	Set ^OcuTalonTest("FixExecutor", flag) = "release"
	Set end = $ZHorolog + 10
	While ($Get(^OcuTalonTest("FixExecutor", flag)) '= "released") && ($ZHorolog < end) {
		Hang 0.1
	}
	Do $$$AssertEquals($Get(^OcuTalonTest("FixExecutor", flag)), "released", "the other job has released the lock")
	Kill ^OcuTalonTest("FixExecutor", flag)
	Do host.WaitNow()
	Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0), 2, "one Wait sends two FixResults")
	Do $$$AssertEquals(..Row(r1)_"#"_..Row(r2), "done|done|finished#done|done|finished", "and closes both requests done")
	If $Select($IsObject(host.Results): host.Results.%Size(), 1: 0) '= 2 Quit
	For i = 0:1:1 {
		Set sent = host.Results.%Get(i)
		Set note = host.Sessions.%Get(i)
		If sent.approvalRef = r1 {
			Do $$$AssertEquals(sent.incidentRef_"|"_sent.total_"|"_sent.resent_"|"_sent.completed_"|"_sent.failedAgain_"|"_sent.skipped_"|"_sent.reason, incidentA_"|3|3|3|0|0|", "R1's FixResult has R1's counts")
			Do $$$AssertEquals(note.session_"|"_note.super, "9201001|"_traceA, "and goes in incident A's trace session with R1's TraceRef")
		} ElseIf sent.approvalRef = r2 {
			Do $$$AssertEquals(sent.incidentRef_"|"_sent.total_"|"_sent.resent_"|"_sent.completed_"|"_sent.failedAgain_"|"_sent.skipped_"|"_sent.reason, incidentB_"|2|2|1|1|0|the order date still wasn't accepted", "R2's FixResult has R2's counts and its reason")
			Do $$$AssertEquals(note.session_"|"_note.super, "9201002|"_traceB, "and goes in incident B's trace session with R2's TraceRef")
		} Else {
			Do $$$AssertTrue(0, "a FixResult of no request of the test: "_sent.approvalRef)
		}
	}
	Do $$$AssertEquals(host.%SessionId, own1, "the host's own session is put back")
	Do $$$AssertEquals($Select($IsObject(host.Audits): host.Audits.%Size(), 1: 0), 2, "and each run wrote its Action entry")
}

Method TestHolderLooksOnceMoreAfterUnlocking()
{
	Set host = ..Host(..#LONGPROBE)
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set owner = ..Owner("lookagain")
	Set incident = ..Incident(owner)
	Set host.Incidents = incident
	Set host.CheckIs = "{""passed"":"""_..TargetList(3)_""",""skipped"":[]}"
	Set host.CarryIs = ..CarryJSON(9311, 3)
	Set host.StatusIs = ..Canned(9311, 3, "Completed").%ToJSON()

	// the waiter's first look finds no run, as if the run were saved while it was unlocking
	Set host.WaitingEmpty = 1
	Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(3))})
	Do $$$AssertStatusOK(..Send(host, ref), "a run that the waiter's first look does not find is handled")
	Do $$$AssertEquals(host.WaitingEmpty, 0, "the waiter's first look was the one that found no run")
	Do ..AssertCounted(host, ref, incident, "done|done|finished", "3|3|3|0|0", "", "the waiter's look after it unlocked", "All 3 orders went through.")
	Do $$$AssertEquals(host.Results.%Size(), 1, "and the run's FixResult was sent once")
}

Method TestWaiterThatErrsStopsAndReleasesTheLock()
{
	Set host = ..Host(..#LONGPROBE)
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set owner = ..Owner("waiterr")
	Set incident = ..Incident(owner)
	Set host.Incidents = incident
	Set host.CheckIs = "{""passed"":"""_..TargetList(3)_""",""skipped"":[]}"
	Set host.CarryIs = ..CarryJSON(9501, 3)
	Set host.StatusIs = ..Canned(9501, 3, "Completed").%ToJSON()
	Set host.WaitingThrows = 1
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(3))})
	Do $$$AssertStatusOK(..Send(host, ref), "a run whose waiter cannot read the waiting runs is handled")
	Do $$$AssertEquals(host.WaitingThrows, 0, "the waiter's read of the waiting runs threw")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Wait", $Parameter(..#PROBE, "LOGWAIT")_"(any)")
	Do $$$AssertEquals(warned, 1, "one Type 3 warning says that the waiter stopped: "_text)
	Do $$$AssertTrue($Find(text, "The waiting runs could not be read") > 0, "and why")
	Do $$$AssertEquals(host.Reads, 0, "the waiter read none of the copies")
	Do $$$AssertEquals(..Row(ref), "executing||", "the request stays executing: nobody counted its copies")
	Set run = ##class(OcuTalon.Test.Watch.Case).RunOf(incident, ref)
	Do $$$AssertTrue($IsObject(run) && (run.resentAt '= "") && (run.endedAt = ""), "its run has a ResentAt and no EndedAt: it waits for the next waiter")
	Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0), 0, "no FixResult is sent")
	Do $$$AssertTrue(..LockIsFree($Parameter(..#PROBE, "WAITLOCK")), "the waiter let go of the wait lock")

	// the next job to wait ends the run
	Do host.WaitNow()
	Do ..AssertCounted(host, ref, incident, "done|done|finished", "3|3|3|0|0", "", "the next waiter", "All 3 orders went through.")
}

Method TestWaiterStopsWhenTheJobShouldQuiesceOrTerminate()
{
	Set host = ..Host(..#LONGPROBE)
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set owner = ..Owner("jobstop")
	Set first = 9511
	For request = $$$eJobRequestQuiescent, $$$eJobRequestTerminate {
		Set incident = ..Incident(owner)
		Set host.Incidents = incident
		Set host.CheckIs = "{""passed"":"""_..TargetList(3)_""",""skipped"":[]}"
		Set host.CarryIs = ..CarryJSON(first, 3)
		Set host.StatusIs = ..Canned(first, 3, "Completed").%ToJSON()
		Set reads = host.Reads
		Set sent = $Select($IsObject(host.Results): host.Results.%Size(), 1: 0)
		Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
		Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(3))})
		Do $$$AssertStatusOK(..SendWhileJobIs(host, ref, request), request_": a run is handled by a job that should "_request)
		Do $$$AssertEquals(host.Reads - reads, 0, request_": the waiter read none of the copies")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Pass", $Parameter(..#PROBE, "LOGWAIT")_ref), 0, request_": and gave no run up")
		Do $$$AssertEquals(..Row(ref), "executing||", request_": the request stays executing")
		Set run = ##class(OcuTalon.Test.Watch.Case).RunOf(incident, ref)
		Do $$$AssertTrue($IsObject(run) && (run.resentAt '= "") && (run.endedAt = ""), request_": its run has a ResentAt and no EndedAt")
		Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0) - sent, 0, request_": no FixResult is sent")
		Do $$$AssertTrue(..LockIsFree($Parameter(..#PROBE, "WAITLOCK")), request_": the waiter let go of the wait lock")

		// the next job to wait ends the run
		Do host.WaitNow()
		Do ..AssertCounted(host, ref, incident, "done|done|finished", "3|3|3|0|0", "", request_": the next waiter", "All 3 orders went through.")
		Set first = first + 10
	}
}

Method TestFailedResentAtSaveLeavesTheRunUnwaited()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set host.ResentSaveFails = 1
	Set owner = ..Owner("resentsave")
	Set incident = ..Incident(owner)
	Set host.Incidents = incident
	Set host.CheckIs = "{""passed"":"""_..TargetList(3)_""",""skipped"":[]}"
	Set host.CarryIs = ..CarryJSON(9301, 3)
	Set host.StatusIs = ..Canned(9301, 3, "Completed").%ToJSON()
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(3))})
	Do $$$AssertStatusOK(..Send(host, ref), "a run whose ResentAt cannot be saved is handled")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Run", $Parameter(..#PROBE, "LOGRUN")_ref)
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the request: "_text)
	Do $$$AssertEquals(..Row(ref), "executing||", "the request stays executing: its copies are not counted")
	Set run = ##class(OcuTalon.Test.Watch.Case).RunOf(incident, ref)
	Do $$$AssertTrue($IsObject(run), "the request has a FixRun")
	If $IsObject(run) Do $$$AssertEquals(run.copies.%Size()_"|"_run.resentAt_"|"_run.endedAt, "3||", "which holds the three copies that were saved, with no ResentAt and no EndedAt")
	Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0), 0, "no FixResult is sent")
	Do $$$AssertEquals($Select($IsObject(host.Audits): host.Audits.%Size(), 1: 0), 0, "and no Action entry is written")

	// the run waits for nobody: a later Wait neither reads its copies nor ends it
	Do host.WaitNow()
	Do $$$AssertEquals(host.Reads, 0, "a later Wait reads none of its copies")
	Do $$$AssertEquals(..Row(ref), "executing||", "and the request is still executing")
}

Method TestFailedEndSaveOrCloseStillSendsTheResult()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set owner = ..Owner("endfault")
	Set host.CheckIs = "{""passed"":"""_..TargetList(3)_""",""skipped"":[]}"

	// the save of the counts fails: one Type 3 warning, and the request is closed, the entry written and the result sent all the same
	Set incident = ..Incident(owner)
	Set host.Incidents = incident
	Set host.CarryIs = ..CarryJSON(9851, 3)
	Set host.StatusIs = ..Canned(9851, 3, "Completed").%ToJSON()
	Set host.EndSaveFails = 1
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(3))})
	Do $$$AssertStatusOK(..Send(host, ref), "a run whose counts cannot be saved is handled")
	Set host.EndSaveFails = 0
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Finish", $Parameter(..#PROBE, "LOGRUN")_ref)
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the request: "_text)
	Do $$$AssertEquals(..Row(ref), "done|done|finished", "the request is closed done all the same")
	Set last = ..LastResult(host)
	Do $$$AssertTrue($IsObject(last) && (last.approvalRef = ref), "the FixResult is sent all the same")
	If $IsObject(last) Do $$$AssertEquals(last.total_"|"_last.resent_"|"_last.completed_"|"_last.failedAgain_"|"_last.skipped, "3|3|3|0|0", "with the run's counts")
	Set entry = ..LastAudit(host)
	Do $$$AssertTrue($IsObject(entry) && (entry.approvalRef = ref), "and the Action entry is written")
	Set run = ##class(OcuTalon.Test.Watch.Case).RunOf(incident, ref)
	Do $$$AssertTrue($IsObject(run), "the request has a FixRun")
	If $IsObject(run) Do $$$AssertEquals(run.endedAt, "", "which has no EndedAt on disk: its save failed")
	Set sent = host.Results.%Size()
	Do host.WaitNow()
	Do $$$AssertEquals(host.Results.%Size(), sent, "a later Wait sends no second result: the request is no longer executing")

	// the close fails: one Type 3 warning, and the counts are stored, the entry written and the result sent all the same
	Set incident = ..Incident(owner)
	Set host.Incidents = incident
	Set host.CarryIs = ..CarryJSON(9861, 3)
	Set host.StatusIs = ..Canned(9861, 3, "Completed").%ToJSON()
	Set host.CloseMoves = "cancelled"
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ref = ..Request(owner, incident, "approved", {"FixTargets": (..TargetList(3))})
	Do $$$AssertStatusOK(..Send(host, ref), "a run whose request cannot be closed is handled")
	Set host.CloseMoves = ""
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Close", $Parameter(..#PROBE, "LOGFINISH")_ref)
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the request: "_text)
	Do $$$AssertEquals(..Row(ref), "cancelled||", "the request is as the other change left it")
	Set last = ..LastResult(host)
	Do $$$AssertTrue($IsObject(last) && (last.approvalRef = ref), "the FixResult is sent all the same")
	Set entry = ..LastAudit(host)
	Do $$$AssertTrue($IsObject(entry) && (entry.approvalRef = ref), "and the Action entry is written")
	Set run = ##class(OcuTalon.Test.Watch.Case).RunOf(incident, ref)
	Do $$$AssertTrue($IsObject(run), "the request has a FixRun")
	If $IsObject(run) Do $$$AssertEquals(run.total_"|"_run.resent_"|"_run.completed_"|"_(run.endedAt '= ""), "3|3|3|1", "which stores the counts and an EndedAt")
}

Method TestWaitLastsWaitSecondsFromResentAt()
{
	Set host = ..Host(..#LONGPROBE)
	If '$IsObject(host) Quit
	Set wait = $Parameter(..#LONGPROBE, "WAITSECONDS")
	Set owner = ..Owner("window")
	Set incident = ..Incident(owner)
	Set host.Incidents = incident
	Set now = ##class(OcuTalon.Watch.Settle).Seconds(##class(OcuTalon.Data.Time).NowUtc())
	Set started = now - 100
	Set started = $Translate($ZDateTime((started \ 86400)_","_(started # 86400), 3, 1), " ", "T")_"Z"
	For case = "inside", "past" {
		Set ago = $Select(case = "inside": wait - 10, 1: wait + 2)
		Set resent = now - ago
		Set run = ##class(OcuTalon.Data.FixRun).%New()
		Set run.ApprovalRef = ..Request(owner, incident, "executing")
		Set run.IncidentRef = incident
		Set run.StartedAt = started
		Set run.ResentAt = $Translate($ZDateTime((resent \ 86400)_","_(resent # 86400), 3, 1), " ", "T")_"Z"
		Do run.Copies.Insert(9801)
		Do $$$AssertStatusOK(run.%Save(), case_": a run that started 100 seconds ago and registered its last copy "_ago_" seconds ago is saved")
		Set id(case) = run.%Id()
	}
	Set waiting = host.WaitingNow()
	Set position = 0
	While $ListNext(waiting, position, item) {
		Set listed(item) = ""
	}
	Do $$$AssertTrue($Data(listed(id("inside"))), "a run whose ResentAt is "_(wait - 10)_" seconds ago waits, though it started 100 seconds ago: the wait runs from ResentAt")
	Do $$$AssertTrue('$Data(listed(id("past"))), "a run whose ResentAt is "_(wait + 2)_" seconds ago no longer waits: the wait lasts WAITSECONDS ("_wait_") from ResentAt")
}

Method TestStartExecutionFailsForAnApprovedRequest()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set host.StartIs = "the lock could not be taken"
	Set owner = ..Owner("nostart")

	// an approved request, not past its expiry
	Set incident = ..Incident(owner)
	Set ref = ..Request(owner, incident, "approved")
	Do $$$AssertStatusOK(..Send(host, ref), "an approved request whose StartExecution fails is handled")
	Do ..AssertEnded(host, ref, incident, "failed|failed|finished", 3, ..#NOSTART, "StartExecution fails")
	Do $$$AssertEquals(..Calls(host), 0, "neither the re-check nor the resend was called")
	Do $$$AssertEquals(..Runs(incident).%Size(), 1, "the request has exactly one FixRun")

	// it reads as the plain sentence of the catalog
	Set last = ..LastResult(host)
	If $IsObject(last) Do $$$AssertEquals(..Render(last, "failed"), "Nothing was resent: OcuTalon couldn't start the resend. Nothing was changed.", "which renders as Nothing was resent: OcuTalon couldn't start the resend. Nothing was changed.")

	// the others are refused
	Set host.RefusalIs = "none"
	Set cases = $ListBuild("pending", "cancelled", "executing", "past expiry")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set incident = ..Incident(owner)
		If case = "past expiry" {
			Set ref = ..Request(owner, incident, "approved", {"ExpiresAt": "2020-01-01T00:00:00Z"})
		} Else {
			Set ref = ..Request(owner, incident, case)
		}
		Set whole = ..Whole(ref)
		Set before = $Select($IsObject(host.Results): host.Results.%Size(), 1: 0)
		Set infos = ..Infos()
		Do $$$AssertStatusOK(..Send(host, ref), case_": the Execute is handled")
		Do $$$AssertEquals(..Whole(ref), whole, case_": the row is as it was, every column")
		Do $$$AssertEquals(..Runs(incident).%Size(), 0, case_": no FixRun is written")
		Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0), before, case_": no FixResult is sent")
		Do $$$AssertEquals(..Infos() - infos, 1, case_": one info line is logged")
	}

	// an approved row that another job starts, or a cancel moves on, while StartExecution fails is read again and refused: the row the handler holds is stale
	Set host.RefusalIs = ""
	For moved = "cancelled", "executing" {
		Set host.StartMoves = moved
		Set incident = ..Incident(owner)
		Set ref = ..Request(owner, incident, "approved")
		Set before = $Select($IsObject(host.Results): host.Results.%Size(), 1: 0)
		Set infos = ..Infos()
		Do $$$AssertStatusOK(..Send(host, ref), moved_" on disk: the Execute is handled")
		Do $$$AssertEquals(..Row(ref), moved_"||", moved_" on disk: the row is as the other change left it")
		Do $$$AssertEquals(..Runs(incident).%Size(), 0, moved_" on disk: no FixRun is written")
		Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0), before, moved_" on disk: no FixResult is sent")
		Do $$$AssertEquals(..Infos() - infos, 1, moved_" on disk: one info line is logged")
	}
	Set host.StartMoves = ""
}

Method TestEveryRunWritesOneActionEntry()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set owner = ..Owner("audit")
	Set shape = ##class(OcuTalon.Test.Watch.Case).SortedKeys({"action": 1, "target": 1, "result": 1, "counts": 1, "approvalRef": 1, "irisUser": 1, "sessionRef": 1, "channel": 1})

	// could not start: no resources
	Set host.MissingIs = "%Ens_MessageResend:U"
	Set incident = ..Incident(owner)
	Set ref = ..Request(owner, incident, "approved", {"AnsweredBy": "zzapprover"})
	Do $$$AssertStatusOK(..Send(host, ref), "a run that cannot start is handled")
	Do ..AssertEntry(host, 0, ref, incident, owner, "failed", "zzapprover", "web", "3|0|0|0|0", "could not start")
	Set first = ..LastAudit(host)
	If $IsObject(first) {
		Do $$$AssertEquals(##class(OcuTalon.Test.Watch.Case).SortedKeys(first), shape, "the entry has the members of the Action shape and no other")
		Do $$$AssertEquals(first.counts.%GetTypeOf("total")_"|"_first.counts.%GetTypeOf("skipped"), "number|number", "the counts are numbers")
	}
	Set host.MissingIs = "none"

	// nothing resent: every target skipped
	Set incident = ..Incident(owner)
	Set host.CheckIs = "{""passed"":"""",""skipped"":[{""id"":101,""reason"":""a""},{""id"":102,""reason"":""b""},{""id"":103,""reason"":""c""}]}"
	Set ref = ..Request(owner, incident, "approved", {"AnsweredBy": "zzapprover"})
	Do $$$AssertStatusOK(..Send(host, ref), "a run that resent nothing is handled")
	Do ..AssertEntry(host, 1, ref, incident, owner, "done", "zzapprover", "web", "3|0|0|0|3", "nothing resent")

	// resent: three copies, two completed and one failed again
	Set incident = ..Incident(owner)
	Set host.Incidents = incident
	Set host.CheckIs = "{""passed"":""101,102,103"",""skipped"":[]}"
	Set host.CarryIs = ..CarryJSON(9001, 3)
	Set statuses = ..Canned(9001, 3, "Completed")
	Do statuses.%Set("9003", {"status": "Error", "error": "Field 'Qty' was empty", "target": "OrdersFromPartner"})
	Set host.StatusIs = statuses.%ToJSON()
	Set ref = ..Request(owner, incident, "approved", {"AnsweredBy": "zzapprover"})
	Do $$$AssertStatusOK(..Send(host, ref), "a run that resent copies is handled")
	Do ..AssertEntry(host, 2, ref, incident, owner, "done", "zzapprover", "web", "3|3|2|1|0", "resent")
	Do $$$AssertEquals($Select($IsObject(host.Audits): host.Audits.%Size(), 1: 0), 3, "three runs wrote three entries, one each")

	// the approver and the channel default to the job's user and system; a session that is not a Ref gives no session
	Set incident = ..Incident("instance")
	Set host.CheckIs = "{""passed"":"""",""skipped"":[{""id"":101,""reason"":""a""},{""id"":102,""reason"":""b""},{""id"":103,""reason"":""c""}]}"
	Set ref = ..Request("instance", incident, "approved", {"AnsweredBy": "", "AnsweredChannel": ""})
	Do $$$AssertStatusOK(..Send(host, ref), "a run of an instance request with no approver is handled")
	Set entry = $Select($IsObject(host.Audits) && (host.Audits.%Size() > 3): host.Audits.%Get(3), 1: "")
	Do $$$AssertTrue($IsObject(entry), "a fourth entry was written")
	If $IsObject(entry) Do $$$AssertEquals(entry.irisUser_"|"_entry.channel_"|"_entry.sessionRef_"|"_entry.approvalRef, $Username_"|system||"_ref, "the entry names the job's user, the channel system and no session")

	// a write that fails logs one warning, and the FixResult still goes
	Set host.AuditFails = 1
	Set incident = ..Incident(owner)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ref = ..Request(owner, incident, "approved")
	Set before = host.Results.%Size()
	Do $$$AssertStatusOK(..Send(host, ref), "a run whose entry cannot be written is handled")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Audit", $Parameter(..#PROBE, "LOGAUDIT")_ref)
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the request: "_text)
	Do $$$AssertEquals(host.Results.%Size() - before, 1, "and the FixResult still goes")
	Do $$$AssertEquals(..Row(ref), "done|done|finished", "and the request is closed")
}

Method TestFailedSendLogsOneWarning()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "%Ens_MessageResend:U"
	Set host.FailSend = 1
	Set owner = ..Owner("send")
	Set incident = ..Incident(owner)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ref = ..Request(owner, incident, "approved")
	Do $$$AssertStatusOK(..Send(host, ref), "an Execute whose result cannot be sent is handled")
	Do $$$AssertEquals(..Row(ref), "failed|failed|finished", "the request is closed all the same")
	Do $$$AssertEquals(..Runs(incident).%Size(), 1, "with its FixRun")
	Do $$$AssertEquals(host.Results.%Size(), 1, "the result was handed to the send once")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Report", $Parameter(..#PROBE, "LOGRESULT"))
	Do $$$AssertEquals(warned, 1, "and one Type 3 warning names the request: "_text)
	If warned Do $$$AssertTrue($Find(text, ref) > 0, "the Ref is in the warning")
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Report", $Parameter(..#PROBE, "LOGRESULT"))
}

Method TestUnknownRequest()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set sc = host.OnMessage(##class(Ens.StringRequest).%New("x"), .response)
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5001, "a request of another class is the error 5001, not 5003")
	Do $$$AssertTrue($Find($SYSTEM.Status.GetErrorText(sc), "Ens.StringRequest") > 0, "which names the class: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(response, "", "and gives no answer")
}

Method TestInterruptMarksOnlyRunsCutByTheRestart()
{
	Set probe = "OcuTalon.Test.Fix.RunProbe"
	Set owner = ..Owner("cut")
	Set start = "2026-06-01T00:00:00Z"
	Set before = "2026-05-31T23:00:00Z"
	Set iCut = ..Incident(owner)
	Set rCut = ..Request(owner, iCut, "executing", {"FixTargets": (..TargetList(5))})
	Set runCut = ..FixRun(iCut, rCut, {"startedAt": (before), "copies": [9001, 9002, 9003]})
	Set iNew = ..Incident(owner)
	Set rNew = ..Request(owner, iNew, "executing")
	Set runNew = ..FixRun(iNew, rNew, {"startedAt": "2026-06-01T00:00:01Z"})
	Set iDone = ..Incident(owner)
	Set rDone = ..Request(owner, iDone, "done")
	Set runDone = ..FixRun(iDone, rDone, {"startedAt": (before)})
	Set iEnded = ..Incident(owner)
	Set rEnded = ..Request(owner, iEnded, "executing")
	Set runEnded = ..FixRun(iEnded, rEnded, {"startedAt": (before), "endedAt": "2026-05-31T23:30:00Z"})
	Set iAgain = ..Incident(owner)
	Set rAgain = ..Request(owner, iAgain, "executing")
	Set runAgain = ..FixRun(iAgain, rAgain, {"startedAt": (before), "total": 2})
	Set iBlank = ..Incident(owner)
	Set rBlank = ..Request(owner, iBlank, "executing")
	Set runBlank = ..FixRun(iBlank, rBlank, {"startedAt": ""})
	Set iEdge = ..Incident(owner)
	Set rEdge = ..Request(owner, iEdge, "executing")
	Set runEdge = ..FixRun(iEdge, rEdge, {"startedAt": (start)})
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Do $ClassMethod(probe, "StartIs", start)
	Set rowsBefore = ..Whole(rNew)_..Whole(rDone)_..Whole(rEnded)_..Whole(rBlank)_..Whole(rEdge)
	Set sc = $ClassMethod(probe, "Interrupt", .problems)
	Do $$$AssertStatusOK(sc, "Interrupt reads the runs")
	Do $$$AssertEquals(problems.%Size(), 0, "and has no problem")
	Do $$$AssertEquals(..Stored(runCut.%Id()), "0|5|0|0|0|0|5|", "the run that started before the start is marked: Total and Interrupted 5, no EndedAt and no counts")
	Do $$$AssertEquals(..Row(rCut), "failed|interrupted|finished", "and its request is closed failed with the Result interrupted")
	Do $$$AssertEquals(##class(OcuTalon.Data.FixRun).%OpenId(runCut.%Id()).Copies.Count(), 3, "it keeps its three copies and makes none")
	Do $$$AssertEquals(..Stored(runNew.%Id())_"#"_..Row(rNew), "0|0|0|0|0|0|0|#executing||", "a run that started after the start is left: not marked, its request executing")
	Do $$$AssertEquals(..Stored(runDone.%Id())_"#"_..Row(rDone), "0|0|0|0|0|0|0|#done||", "so is one whose request is done")
	Do $$$AssertEquals(..Stored(runEnded.%Id())_"#"_..Row(rEnded), "1|0|0|0|0|0|0|#executing||", "and one that ended")
	Do $$$AssertEquals(..Stored(runAgain.%Id()), "0|2|0|0|0|0|2|", "a run that is marked already keeps its mark")
	Do $$$AssertEquals(..Row(rAgain), "failed|interrupted|finished", "and has its request closed")
	Do $$$AssertEquals(..Stored(runBlank.%Id())_"#"_..Row(rBlank)_"#"_..Stored(runEdge.%Id())_"#"_..Row(rEdge), "0|0|0|0|0|0|0|#executing||#0|0|0|0|0|0|0|#executing||", "a run with no StartedAt and one that started in the second of the start are left")
	Do $$$AssertEquals(..Whole(rNew)_..Whole(rDone)_..Whole(rEnded)_..Whole(rBlank)_..Whole(rEdge), rowsBefore, "the rows that were left are as they were")
	Do $$$AssertEquals(..ClosedList(), rCut_"|interrupted,"_rAgain_"|interrupted", "only the two runs that were cut short had their request closed, with the result interrupted")

	// a second pass changes nothing and closes nothing
	Set sc = $ClassMethod(probe, "Interrupt", .problems)
	Do $$$AssertStatusOK(sc, "a second Interrupt reads the runs")
	Do $$$AssertEquals(problems.%Size(), 0, "and has no problem")
	Do $$$AssertEquals(..ClosedList(), rCut_"|interrupted,"_rAgain_"|interrupted", "no request is closed a second time")
	Do $$$AssertEquals(..Stored(runCut.%Id())_"#"_..Stored(runAgain.%Id())_"#"_..Stored(runNew.%Id()), "0|5|0|0|0|0|5|#0|2|0|0|0|0|2|#0|0|0|0|0|0|0|", "and the runs are as they were")

	// no start time: nothing is marked, and one problem says so
	Set iLate = ..Incident(owner)
	Set rLate = ..Request(owner, iLate, "executing")
	Set runLate = ..FixRun(iLate, rLate, {"startedAt": (before)})
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Do $ClassMethod(probe, "StartIs", "")
	Set sc = $ClassMethod(probe, "Interrupt", .problems)
	Do $$$AssertStatusOK(sc, "with no start time Interrupt still gives OK")
	Do $$$AssertEquals(problems.%Size(), 1, "with one problem")
	Do $$$AssertEquals(..Stored(runLate.%Id())_"#"_..Row(rLate), "0|0|0|0|0|0|0|#executing||", "and nothing is marked or closed")

	// the runs cannot be read: the error status
	Do $ClassMethod(probe, "StartIs", start)
	Do $ClassMethod(probe, "UnendedThrows")
	Set sc = $ClassMethod(probe, "Interrupt", .problems)
	Do $$$AssertStatusNotOK(sc, "a read of the runs that fails is an error status")
}

Method TestReconcileWarnsAndGoesOn()
{
	Set probe = "OcuTalon.Test.Fix.RunProbe"
	Set owner = ..Owner("warn")
	Set start = "2026-06-01T00:00:00Z"
	Set before = "2026-05-31T23:00:00Z"
	Set iLate = ..Incident(owner)
	Set rLate = ..Request(owner, iLate, "executing")
	Set runLate = ..FixRun(iLate, rLate, {"startedAt": (before)})
	Do $ClassMethod(probe, "Narrow", ..Incidents)

	// no start time: one WARN line, the step still OK
	Do $ClassMethod(probe, "StartIs", "")
	Set sc = ##class(OcuTalon.Install.Step.Fix).ReconcileWith(probe)
	Do $$$AssertStatusOK(sc, "with no start time the step gives OK")
	Set lines = ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertEquals($ListLength(lines), 1, "and one warning line")
	Do $$$AssertEquals(..Stored(runLate.%Id()), "0|0|0|0|0|0|0|", "nothing is marked")

	// a close that fails: the run stays marked, one WARN line that names the request, the step OK
	Do $ClassMethod(probe, "StartIs", start)
	Do $ClassMethod(probe, "FailClose", rLate)
	Set sc = ##class(OcuTalon.Install.Step.Fix).ReconcileWith(probe)
	Do $$$AssertStatusOK(sc, "with a close that fails the step gives OK")
	Set lines = ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertEquals($ListLength(lines), 1, "with one warning line")
	Do $$$AssertTrue($ListLength(lines) && ($List(lines, 1) [ rLate), "which names the request: "_$Select($ListLength(lines): $List(lines, 1), 1: ""))
	Do $$$AssertEquals(..Stored(runLate.%Id())_"#"_..Row(rLate), "0|3|0|0|0|0|3|#executing||", "the run is marked, and its request is still executing")

	// the next pass closes it
	Do $ClassMethod(probe, "FailClose", "")
	Set sc = ##class(OcuTalon.Install.Step.Fix).ReconcileWith(probe)
	Do $$$AssertStatusOK(sc, "the next pass gives OK")
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Install.Step).TakeWarnings()), 0, "with no warning")
	Do $$$AssertEquals(..Row(rLate), "failed|interrupted|finished", "and closes the request")

	// the runs cannot be read: the step's status is the error
	Do $ClassMethod(probe, "UnendedThrows")
	Set sc = ##class(OcuTalon.Install.Step.Fix).ReconcileWith(probe)
	Do $$$AssertStatusNotOK(sc, "a read of the runs that fails is the error status")
}

Method TestSweepReportsAnInterruptedRunOnce()
{
	Set probe = "OcuTalon.Test.Fix.RunProbe"
	Set owner = ..Owner("once")
	Set incident = ..Incident(owner)
	Set ref = ..Request(owner, incident, "executing", {"FixTargets": (..TargetList(5))})
	Set run = ..FixRun(incident, ref, {"startedAt": "2026-05-31T23:00:00Z", "copies": [9501, 9502, 9503], "total": 5})
	Set id = run.%Id()
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Do $ClassMethod(probe, "Feed", ref, ..CannedAt(9501, 3, "Completed", ..Stamp(-5)))
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 1, "Sweep returns one FixResult")
	If results.Count() '= 1 Quit
	Set result = results.GetAt(1)
	Do $$$AssertEquals(result.ApprovalRef_"|"_result.IncidentRef_"|"_result.Final_"|"_result.Interrupted, ref_"|"_incident_"|1|1", "it names the request and the incident, is final and is interrupted")
	Do $$$AssertEquals(result.Total_"|"_result.Resent_"|"_result.Completed_"|"_result.FailedAgain_"|"_result.Skipped_"|"_result.Reason, "5|3|3|0|0|", "with the counts 5/3/3/0/0 and no reason")
	Do $$$AssertEquals(..Row(ref), "failed|interrupted|finished", "the request is closed failed with the Result interrupted")
	Do $$$AssertEquals(..Stored(id), "1|5|3|3|0|0|2|", "the run has an EndedAt, 5/3/3/0/0 and Interrupted 2, the targets the restart cut off")
	Do $$$AssertEquals(..ClosedList(), ref_"|interrupted", "the request was closed once")
	Set audits = $ClassMethod(probe, "Audits")
	Do $$$AssertEquals(audits.%Size(), 1, "one Action entry is written")
	If audits.%Size() = 1 {
		Set entry = audits.%Get(0)
		Do $$$AssertEquals(entry.approvalRef_"|"_entry.result_"|"_entry.action_"|"_entry.channel, ref_"|interrupted|repair_resend|web", "which names the request, the result interrupted, the kind and the channel")
		Do $$$AssertEquals(entry.counts.%ToJSON(), "{""total"":5,""resent"":3,""completed"":3,""failedAgain"":0,""skipped"":0}", "with the five counts as numbers")
	}
	Set text = ..Render(..AsSent(result), ..StateOf(ref), .key)
	Do $$$AssertEquals(key, "result.interrupted", "the key is result.interrupted")
	Do $$$AssertEquals(text, "The resend stopped when OcuTalon restarted: 3 of 5 orders went through. The other 2 need a new approval.", "and it reads as the UX document has it")
	Do $$$AssertEquals(..SweptLines(ref), 1, "one Type 4 line says that Sweep ended the run")

	// reported once
	Set again = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(again.Count(), 0, "a second Sweep returns nothing")
	Do $$$AssertEquals(..AuditCount()_"|"_..ClosedList(), "1|"_ref_"|interrupted", "writes no second entry and closes nothing again")
	Set counts = {"total": 5, "resent": 3, "completed": 3, "failedAgain": 0, "skipped": 0, "interrupted": 2, "reason": ""}
	Set wrote = ##class(OcuTalon.Fix.Executor).End(##class(OcuTalon.Data.FixRun).%OpenId(id), counts, 1, .sc)
	Do $$$AssertEquals(wrote, 0, "End refuses the ended run")
	Do $$$AssertStatusNotOK(sc, "with the reason")
	Do $$$AssertEquals(..Stored(id), "1|5|3|3|0|0|2|", "and writes nothing")
}

Method TestSweepInterruptedCounts()
{
	Set probe = "OcuTalon.Test.Fix.RunProbe"
	Set owner = ..Owner("counts")
	Set own = "The order date was not in the expected format. Expected YYYY-MM-DD, got '16/10/2026'."

	// a: 5 targets, 3 copies, 2 completed and 1 queued
	Set iA = ..Incident(owner)
	Set statuses = ..CannedAt(9601, 2, "Completed", ..Stamp(-5))
	Do statuses.%Set("9603", {"status": "Queued", "error": "", "target": "OrdersFromPartner", "at": (..Stamp(-5))})
	Set rA = ..MarkedRun(owner, iA, 5, "9601,9602,9603", statuses)

	// b: 3 targets, 3 copies, all completed
	Set iB = ..Incident(owner)
	Set rB = ..MarkedRun(owner, iB, 3, "9611,9612,9613", ..CannedAt(9611, 3, "Completed", ..Stamp(-5)))

	// c: 3 copies, 1 completed and 2 failed again with the incident's own error
	Set iC = ..Incident(owner)
	Do ..Group(iC, "OrdersFromPartner", ..#ORDERDATETEXT)
	Set statuses = ..CannedAt(9621, 1, "Completed", ..Stamp(-5))
	Do statuses.%Set("9622", {"status": "Error", "error": (own), "target": "OrdersFromPartner", "at": (..Stamp(-5))})
	Do statuses.%Set("9623", {"status": "Error", "error": (own), "target": "OrdersFromPartner", "at": (..Stamp(-5))})
	Set rC = ..MarkedRun(owner, iC, 3, "9621,9622,9623", statuses)

	// d: a read that is not read
	Set iD = ..Incident(owner)
	Set rD = ..MarkedRun(owner, iD, 3, "9631,9632,9633", ..CannedAt(9631, 3, "Completed", ..Stamp(-5)), "unreadable")

	// e: a read that throws
	Set iE = ..Incident(owner)
	Set rE = ..MarkedRun(owner, iE, 3, "9641,9642,9643", ..CannedAt(9641, 3, "Completed", ..Stamp(-5)))
	Do $ClassMethod(probe, "ReadThrows", rE)

	// f: a missing incident
	Set iF = "zzmissingincident0001"
	Set ..Incidents = ..Incidents_","_iF
	Set rF = ..MarkedRun(owner, iF, 3, "9651,9652,9653", ..CannedAt(9651, 3, "Completed", ..Stamp(-5)))

	// g: the request's row is gone: the run ends with its counts, and no entry or result is made
	Set iG = ..Incident(owner)
	Set rG = ..MarkedRun(owner, iG, 5, "9661,9662,9663", ..CannedAt(9661, 3, "Completed", ..Stamp(-5)))
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(rG)
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 6, "Sweep returns one FixResult for each of the six runs whose request exists")
	Do ..AssertCut(results, rA, "5|3|2|0|0", 1, 3, "result.interrupted", "The resend stopped when OcuTalon restarted: 2 of 5 orders went through. The other 3 need a new approval.", "a: 2 completed and 1 queued of 5")
	Do ..AssertCut(results, rB, "3|3|3|0|0", 0, 0, "result.allThrough", "All 3 orders went through.", "b: all 3 completed")
	Do ..AssertCut(results, rC, "3|3|1|2|0", 0, 0, "result.failedAgain", "1 of 3 orders went through. 2 failed again (the order date still wasn't accepted). I won't retry them without a new approval.", "c: 1 completed and 2 failed again")
	Do ..AssertCut(results, rD, "3|3|0|0|0", 1, 3, "result.interrupted", "The resend stopped when OcuTalon restarted: 0 of 3 orders went through. The other 3 need a new approval.", "d: an unreadable read counts no copy as completed")
	Do ..AssertCut(results, rE, "3|3|0|0|0", 1, 3, "result.interrupted", "The resend stopped when OcuTalon restarted: 0 of 3 orders went through. The other 3 need a new approval.", "e: a read that throws counts no copy as completed")
	Do ..AssertCut(results, rF, "3|3|0|0|0", 1, 3, "result.interrupted", "The resend stopped when OcuTalon restarted: 0 of 3 orders went through. The other 3 need a new approval.", "f: a missing incident counts no copy as completed")
	Do $$$AssertTrue('$IsObject(..ResultFor(results, rG)), "g: none for the run whose request is gone")
	Do $$$AssertEquals(..Stored(##class(OcuTalon.Data.FixRun).OfRequest(rG).%Id()), "1|5|3|3|0|0|2|", "g: but the run is ended with its counts, Total from the stored Total")
	Do $$$AssertEquals(..AuditCount(), 6, "and no entry is written for it")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "EndMarked", $Parameter("OcuTalon.Fix.Run", "LOGREAD")_rE)
	Do $$$AssertEquals(warned, 1, "the read that threw logged one Type 3 warning that names the request: "_text)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, , "EndMarked", $Parameter("OcuTalon.Fix.Run", "LOGREAD")), 1, "and no other read logged one")
}

Method TestSweepClosesTheRowFirst()
{
	Set probe = "OcuTalon.Test.Fix.RunProbe"
	Set owner = ..Owner("first")
	Set iA = ..Incident(owner)
	Set rA = ..MarkedRun(owner, iA, 5, "9701,9702,9703", ..CannedAt(9701, 3, "Completed", ..Stamp(-5)))
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 1, "Sweep returns the FixResult of a marked run whose request is executing")
	Do $$$AssertEquals(..Row(rA), "failed|interrupted|finished", "the request is closed interrupted by then, so it is not executing when the result is read")
	Do $$$AssertEquals(..ClosedList(), rA_"|interrupted", "it was closed once, with the result interrupted")
	If results.Count() = 1 {
		Do ..Render(..AsSent(results.GetAt(1)), ..StateOf(rA), .key)
		Do $$$AssertEquals(key, "result.interrupted", "so the key is result.interrupted, never result.stillResending")
	}

	// a close that fails: no result, no EndedAt, one warning; the next Sweep reports the run
	Set iB = ..Incident(owner)
	Set rB = ..MarkedRun(owner, iB, 5, "9711,9712,9713", ..CannedAt(9711, 3, "Completed", ..Stamp(-5)))
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Do $ClassMethod(probe, "FailClose", rB)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 0, "a request that cannot be closed gives no result")
	Do $$$AssertEquals(..Stored(##class(OcuTalon.Test.Watch.Case).RunOf(iB, rB).id)_"#"_..Row(rB), "0|5|0|0|0|0|5|#executing||", "the run has no EndedAt and the request is still executing")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "EndMarked", $Parameter("OcuTalon.Fix.Run", "LOGCLOSE")_rB)
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the request: "_text)
	Do $ClassMethod(probe, "FailClose", "")
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 1, "the next Sweep reports the run")
	Do $$$AssertEquals(..Row(rB), "failed|interrupted|finished", "and its request is closed")

	// a close that throws: one warning, and the next run is still swept
	Set iC = ..Incident(owner)
	Set rC = ..MarkedRun(owner, iC, 5, "9721,9722,9723", ..CannedAt(9721, 3, "Completed", ..Stamp(-5)))
	Set iD = ..Incident(owner)
	Set rD = ..MarkedRun(owner, iD, 5, "9731,9732,9733", ..CannedAt(9731, 3, "Completed", ..Stamp(-5)))
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Do $ClassMethod(probe, "ThrowClose", rC)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 1, "a close that throws gives no result for its run, and the next run is still swept")
	If results.Count() = 1 Do $$$AssertEquals(results.GetAt(1).ApprovalRef, rD, "the result of the next run")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Sweep", $Parameter("OcuTalon.Fix.Run", "LOGSWEEP")_rC)
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the request that threw: "_text)
}

Method TestSweepEndsARunNoWaiterEnded()
{
	Set probe = "OcuTalon.Test.Fix.RunProbe"
	Set owner = ..Owner("nowaiter")
	Set own = "The order date was not in the expected format. Expected YYYY-MM-DD, got '16/10/2026'."
	Set sentAt = ..Stamp(-100)
	Set doneAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(sentAt, 20)

	// A: 5 targets, 3 copies, all completed inside the wait
	Set iA = ..Incident(owner)
	Set rA = ..UnmarkedRun(owner, iA, 5, "9801,9802,9803", sentAt, ..CannedAt(9801, 3, "Completed", doneAt))

	// B: 3 targets, 3 copies, 2 completed and 1 failed again with the incident's own error
	Set iB = ..Incident(owner)
	Do ..Group(iB, "OrdersFromPartner", ..#ORDERDATETEXT)
	Set statuses = ..CannedAt(9811, 2, "Completed", doneAt)
	Do statuses.%Set("9813", {"status": "Error", "error": (own), "target": "OrdersFromPartner", "at": (doneAt)})
	Set rB = ..UnmarkedRun(owner, iB, 3, "9811,9812,9813", sentAt, statuses)

	// C: all completed, and a close that fails
	Set iC = ..Incident(owner)
	Set rC = ..UnmarkedRun(owner, iC, 3, "9821,9822,9823", sentAt, ..CannedAt(9821, 3, "Completed", doneAt))
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Do $ClassMethod(probe, "FailClose", rC)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 3, "Sweep returns one FixResult for each of the three runs")
	Do ..AssertDone(results, rA, iA, "5|3|3|0|2", "", "result.skipped", "3 of 5 orders went through. 2 had changed since the dry run, so I skipped them; they need a new approval.", "done|done|finished", "A: 3 of 5 targets resent, all completed")
	Do ..AssertDone(results, rB, iB, "3|3|2|1|0", "the order date still wasn't accepted", "result.failedAgain", "2 of 3 orders went through. 1 failed again (the order date still wasn't accepted). I won't retry it without a new approval.", "done|done|finished", "B: one copy failed again")
	Do ..AssertDone(results, rC, iC, "3|3|3|0|0", "", "result.stillResending", "Still resending: 3 of 3 orders have gone through so far. I'll tell you when it's done.", "executing||", "C: a close that fails leaves the request executing, so its notice reads still resending")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "EndLeft", $Parameter("OcuTalon.Fix.Run", "LOGCLOSE")_rC)
	Do $$$AssertEquals(warned, 1, "the close that failed logged one Type 3 warning that names the request: "_text)
	Set audits = $ClassMethod(probe, "Audits")
	Do $$$AssertEquals(audits.%Size(), 3, "one Action entry is written for each run")
	For i = 0:1:audits.%Size() - 1 {
		Do $$$AssertEquals(audits.%Get(i).result, "done", "entry "_(i + 1)_" has the result done")
	}
	Do $$$AssertEquals(..ClosedList(), rA_"|done,"_rB_"|done,"_rC_"|done", "each request was closed done once")
	Set again = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(again.Count(), 0, "a second Sweep returns nothing")
}

Method TestSweepLeavesRunsOfTheWaiterAndOfStory305()
{
	Set probe = "OcuTalon.Test.Fix.RunProbe"
	Set owner = ..Owner("left")
	Set sentAt = ..Stamp(-100)
	Set doneAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(sentAt, 20)
	Set lateAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(sentAt, 70)
	Set all = ..CannedAt(9901, 3, "Completed", doneAt)
	Set cases = 0

	// inside its wait
	Set i = ..Incident(owner)
	Set cases($Increment(cases)) = $ListBuild("inside its wait", ..UnmarkedRun(owner, i, 3, "9901,9902,9903", ..Stamp(-10), ..CannedAt(9901, 3, "Completed", ..Stamp(-5))), i)
	// past its wait, with a copy still queued
	Set i = ..Incident(owner)
	Set queued = ..CannedAt(9911, 2, "Completed", doneAt)
	Do queued.%Set("9913", {"status": "Queued", "error": "", "target": "OrdersFromPartner", "at": (sentAt)})
	Set cases($Increment(cases)) = $ListBuild("with a copy still queued", ..UnmarkedRun(owner, i, 3, "9911,9912,9913", sentAt, queued), i)
	// past its wait, the last copy done after the wait
	Set i = ..Incident(owner)
	Set late = ..CannedAt(9921, 2, "Completed", doneAt)
	Do late.%Set("9923", {"status": "Completed", "error": "", "target": "OrdersFromPartner", "at": (lateAt)})
	Set cases($Increment(cases)) = $ListBuild("whose last copy finished after the wait", ..UnmarkedRun(owner, i, 3, "9921,9922,9923", sentAt, late), i)
	// past its wait, a copy that is done and has no time
	Set i = ..Incident(owner)
	Set cases($Increment(cases)) = $ListBuild("with a copy that has no time", ..UnmarkedRun(owner, i, 3, "9931,9932,9933", sentAt, ..CannedAt(9931, 3, "Completed", "")), i)
	// no ResentAt
	Set i = ..Incident(owner)
	Set cases($Increment(cases)) = $ListBuild("with no ResentAt", ..UnmarkedRun(owner, i, 3, "9941,9942,9943", "", ..CannedAt(9941, 3, "Completed", doneAt)), i)
	// the request is done
	Set i = ..Incident(owner)
	Set cases($Increment(cases)) = $ListBuild("whose request is done", ..UnmarkedRun(owner, i, 3, "9951,9952,9953", sentAt, ..CannedAt(9951, 3, "Completed", doneAt), "done"), i)
	// the read is not read
	Set i = ..Incident(owner)
	Set cases($Increment(cases)) = $ListBuild("whose read is not read", ..UnmarkedRun(owner, i, 3, "9961,9962,9963", sentAt, ..CannedAt(9961, 3, "Completed", doneAt), "executing", "unreadable"), i)
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 0, "Sweep returns nothing for any of the runs")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, , "Sweep", $Parameter("OcuTalon.Fix.Run", "LOGSWEEP"))_"|"_##class(OcuTalon.Test.Core.Observe).Warnings(mark, , "EndLeft", $Parameter("OcuTalon.Fix.Run", "LOGREAD")), "0|0", "and logs no warning: none of the runs was left because Sweep failed on it")
	Do $$$AssertEquals($ClassMethod(probe, "Reads"), 4, "the copies were read for the four runs that are past their wait and whose request is executing, and for no other")
	Do $$$AssertEquals(..AuditCount()_"|"_..ClosedList(), "0|", "writes no entry and closes no request")
	For n = 1:1:cases {
		Set ref = $List(cases(n), 2)
		Set run = ##class(OcuTalon.Test.Watch.Case).RunOf($List(cases(n), 3), ref)
		Do $$$AssertEquals(..Stored(run.id)_"#"_..Row(ref), "0|0|0|0|0|0|0|#"_$Select($List(cases(n), 1) = "whose request is done": "done||", 1: "executing||"), "a run "_$List(cases(n), 1)_" has no EndedAt and keeps its request")
	}
}

Method TestSweepDecidesByTheLatestCopyTime()
{
	Set probe = "OcuTalon.Test.Fix.RunProbe"
	Set owner = ..Owner("latest")
	Set own = "The order date was not in the expected format. Expected YYYY-MM-DD, got '16/10/2026'."
	Set sentAt = ..Stamp(-100)
	Set early = ##class(OcuTalon.Bridge.Time).PlusSeconds(sentAt, 10)
	Set justIn = ##class(OcuTalon.Bridge.Time).PlusSeconds(sentAt, ##class(OcuTalon.Fix.Executor).#WAITSECONDS - 1)
	Set atEnd = ##class(OcuTalon.Bridge.Time).PlusSeconds(sentAt, ##class(OcuTalon.Fix.Executor).#WAITSECONDS)

	// A: the latest copy (one second before the end of the wait) is the first of the list: the run ends
	Set iA = ..Incident(owner)
	Set statuses = ..CannedAt(9971, 3, "Completed", early)
	Do statuses.%Set("9971", {"status": "Completed", "error": "", "target": "OrdersFromPartner", "at": (justIn)})
	Set rA = ..UnmarkedRun(owner, iA, 3, "9971,9972,9973", sentAt, statuses)

	// B: the latest copy is done at the end of the wait itself, and is the first of the list: the run is left
	Set iB = ..Incident(owner)
	Set statuses = ..CannedAt(9981, 3, "Completed", early)
	Do statuses.%Set("9981", {"status": "Completed", "error": "", "target": "OrdersFromPartner", "at": (atEnd)})
	Set rB = ..UnmarkedRun(owner, iB, 3, "9981,9982,9983", sentAt, statuses)

	// C: two copies are done early and the third has no time: the run is left
	Set iC = ..Incident(owner)
	Set statuses = ..CannedAt(9991, 2, "Completed", early)
	Do statuses.%Set("9993", {"status": "Completed", "error": "", "target": "OrdersFromPartner", "at": ""})
	Set rC = ..UnmarkedRun(owner, iC, 3, "9991,9992,9993", sentAt, statuses)

	// D: the copy that is done last is a failed one, at the end of the wait: the run is left
	Set iD = ..Incident(owner)
	Set statuses = ..CannedAt(9961, 2, "Completed", early)
	Do statuses.%Set("9963", {"status": "Error", "error": (own), "target": "OrdersFromPartner", "at": (atEnd)})
	Set rD = ..UnmarkedRun(owner, iD, 3, "9961,9962,9963", sentAt, statuses)
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 1, "Sweep returns one FixResult: that of the run whose latest copy was done a second before the end of its wait")
	Do ..AssertDone(results, rA, iA, "3|3|3|0|0", "", "result.allThrough", "All 3 orders went through.", "done|done|finished", "A: the latest copy done a second before the end of the wait, listed first")
	Set left = $ListBuild($ListBuild(rB, iB, "B: the latest copy done at the end of the wait, listed first"), $ListBuild(rC, iC, "C: one done copy has no time among copies that have one"), $ListBuild(rD, iD, "D: the copy done last is a failed one, at the end of the wait"))
	Set position = 0
	While $ListNext(left, position, each) {
		Set ref = $List(each, 1)
		Set run = ##class(OcuTalon.Test.Watch.Case).RunOf($List(each, 2), ref)
		Do $$$AssertEquals(..Stored(run.id)_"#"_..Row(ref), "0|0|0|0|0|0|0|#executing||", $List(each, 3)_": the run is left, with no EndedAt and its request executing")
		Do $$$AssertTrue('$IsObject(..ResultFor(results, ref)), $List(each, 3)_": no FixResult")
	}
	Do $$$AssertEquals($ClassMethod(probe, "Reads"), 4, "the copies of all four runs were read, so the three that are left were left for their copy times")
	Do $$$AssertEquals(..AuditCount()_"|"_..ClosedList(), "1|"_rA_"|done", "one entry is written and one request closed: those of run A")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, , "Sweep", $Parameter("OcuTalon.Fix.Run", "LOGSWEEP")), 0, "and Sweep logged no failure")
}

Method TestSweepGoesOnWhenTheEndFails()
{
	Set probe = "OcuTalon.Test.Fix.RunProbe"
	Set owner = ..Owner("endfails")
	Set sentAt = ..Stamp(-100)
	Set doneAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(sentAt, 20)

	// a marked run whose end cannot be saved: no result, no entry, one warning; the next Sweep reports it once
	Set iM = ..Incident(owner)
	Set rM = ..MarkedRun(owner, iM, 5, "9801,9802,9803", ..CannedAt(9801, 3, "Completed", ..Stamp(-5)))
	Set idM = ##class(OcuTalon.Test.Watch.Case).RunOf(iM, rM).id
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Do $ClassMethod(probe, "SpoilSave", rM)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 0, "a marked run whose end cannot be saved gives no result")
	Do $$$AssertEquals(..Stored(idM)_"#"_..AuditCount(), "0|5|0|0|0|0|5|#0", "its run has no EndedAt and no entry is written")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Ended", $Parameter("OcuTalon.Fix.Run", "LOGSAVE")_rM)
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the request: "_text)
	Do $ClassMethod(probe, "SpoilSave", "")
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 1, "the next Sweep reports the run")
	Do $$$AssertEquals(..Stored(idM)_"#"_..AuditCount(), "1|5|3|3|0|0|2|#1", "its run is ended and has one entry")
	Do $$$AssertEquals($ClassMethod(probe, "Sweep").Count(), 0, "and a further Sweep reports nothing")

	// an unmarked run whose end cannot be saved: the same, and its request is not closed
	Set iU = ..Incident(owner)
	Set rU = ..UnmarkedRun(owner, iU, 3, "9811,9812,9813", sentAt, ..CannedAt(9811, 3, "Completed", doneAt))
	Set idU = ##class(OcuTalon.Test.Watch.Case).RunOf(iU, rU).id
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Do $ClassMethod(probe, "SpoilSave", rU)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 0, "an unmarked run whose end cannot be saved gives no result")
	Do $$$AssertEquals(..Stored(idU)_"#"_..Row(rU)_"#"_..AuditCount(), "0|0|0|0|0|0|0|#executing||#1", "its run has no EndedAt, its request is still executing and no entry is written")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Ended", $Parameter("OcuTalon.Fix.Run", "LOGSAVE")_rU)
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the request: "_text)
	Do $ClassMethod(probe, "SpoilSave", "")
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 1, "the next Sweep reports the run")
	Do $$$AssertEquals(..Stored(idU)_"#"_..Row(rU)_"#"_..AuditCount(), "1|3|3|3|0|0|0|#done|done|finished#2", "it ends done, with one entry")
	Do $$$AssertEquals($ClassMethod(probe, "Sweep").Count(), 0, "and a further Sweep reports nothing")

	// a marked run whose audit write throws: one warning, and the result still comes
	Set iA = ..Incident(owner)
	Set rA = ..MarkedRun(owner, iA, 5, "9821,9822,9823", ..CannedAt(9821, 3, "Completed", ..Stamp(-5)))
	Set idA = ##class(OcuTalon.Test.Watch.Case).RunOf(iA, rA).id
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Do $ClassMethod(probe, "AuditThrows", rA)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 1, "a run whose audit write throws still gives its result")
	If results.Count() = 1 Do $$$AssertEquals(results.GetAt(1).ApprovalRef, rA, "the result of that run")
	Do $$$AssertEquals(..Stored(idA)_"#"_..AuditCount(), "1|5|3|3|0|0|2|#2", "its run is ended and no entry was recorded")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Entry", $Parameter("OcuTalon.Fix.Run", "LOGAUDIT")_rA)
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the request: "_text)
	Do $ClassMethod(probe, "AuditThrows", "")

	// an unmarked run whose close throws: one warning, and the entry and the result still come
	Set iT = ..Incident(owner)
	Set rT = ..UnmarkedRun(owner, iT, 3, "9831,9832,9833", sentAt, ..CannedAt(9831, 3, "Completed", doneAt))
	Set idT = ##class(OcuTalon.Test.Watch.Case).RunOf(iT, rT).id
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Do $ClassMethod(probe, "ThrowClose", rT)
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 1, "a run whose close throws still gives its result")
	If results.Count() = 1 Do $$$AssertEquals(results.GetAt(1).ApprovalRef, rT, "the result of that run")
	Do $$$AssertEquals(..Stored(idT)_"#"_..Row(rT)_"#"_..AuditCount(), "1|3|3|3|0|0|0|#executing||#3", "its run is ended and has its entry, and its request is still executing")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "EndLeft", $Parameter("OcuTalon.Fix.Run", "LOGCLOSE")_rT)
	Do $$$AssertEquals(warned, 1, "one Type 3 warning names the request: "_text)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, , "Sweep", $Parameter("OcuTalon.Fix.Run", "LOGSWEEP")), 0, "and Sweep did not give up on the run")
}

Method TestStartedIsTheProductionStart()
{
	Set had = $Data($$$EnsRuntime("StartTime"), saved)
	Set failed = ""
	Try {
		Set $$$EnsRuntime("StartTime") = "2026-10-29 17:11:27.941"
		Set one = ##class(OcuTalon.Fix.Run).Started()
		Set $$$EnsRuntime("StartTime") = "not a time"
		Set two = ##class(OcuTalon.Fix.Run).Started()
		Kill $$$EnsRuntime("StartTime")
		Set three = ##class(OcuTalon.Fix.Run).Started()
	} Catch exception {
		Set failed = exception.DisplayString()
	}
	If had Set $$$EnsRuntime("StartTime") = saved
	If 'had Kill $$$EnsRuntime("StartTime")
	Do $$$AssertEquals(failed, "", "the start is read without an error")
	If failed '= "" Quit
	Do $$$AssertEquals(one, "2026-10-29T17:11:27Z", "the production's start is that of ^Ens.Runtime(""StartTime""), as a UTC stamp to the second")
	Set now = ##class(OcuTalon.Watch.Settle).Seconds(##class(OcuTalon.Data.Time).NowUtc())
	For case = 2, 3 {
		Set fallback = ##class(OcuTalon.Watch.Settle).Seconds($Select(case = 2: two, 1: three))
		Set apart = $Select(fallback = "": "", 1: (now - fallback) - ($ZHorolog \ 1))
		Do $$$AssertTrue((apart '= "") && (apart '< -3) && (apart '> 3), $Select(case = 2: "a value that is not a time", 1: "no value")_" gives the start of the instance: "_apart_" seconds from the uptime")
	}
}

Method TestSweepSkipsALockedRun()
{
	Set probe = "OcuTalon.Test.Fix.RunProbe"
	Set owner = ..Owner("locked")
	// M: a marked run whose request is executing (a Sweep that took it would close the request first); its job holds its lock to the end of the test
	Set iM = ..Incident(owner)
	Set refM = ..MarkedRun(owner, iM, 5, "9971,9972,9973", ..CannedAt(9971, 3, "Completed", ..Stamp(-5)))
	// U: an unmarked run past its wait whose copies were done inside it; the production's own Sweep cannot read copies of a fixture incident, so only the probe's Sweep ends it
	Set iU = ..Incident(owner)
	Set sentAt = ..Stamp(-100)
	Set refU = ..UnmarkedRun(owner, iU, 3, "9974,9975,9976", sentAt, ..CannedAt(9974, 3, "Completed", ##class(OcuTalon.Data.Time).AddSeconds(sentAt, 20)))
	Do $ClassMethod(probe, "Narrow", ..Incidents)
	Set idM = ##class(OcuTalon.Test.Watch.Case).RunOf(iM, refM).id
	Set idU = ##class(OcuTalon.Test.Watch.Case).RunOf(iU, refU).id
	Set flagM = "runlock"_..Number
	Set flagU = "runlocku"_..Number
	Set ..HoldFlag = flagM_","_flagU
	For pair = $ListBuild(idM, flagM), $ListBuild(idU, flagU) {
		Set ^OcuTalonTest("FixExecutor", $List(pair, 2)) = ""
		Job ##class(OcuTalon.Test.Fix.Executor).HoldLock("^OcuTalon.Fix.Run("_$List(pair, 1)_")", $List(pair, 2))
		Do ..LetGo($List(pair, 1))
	}
	Set end = $ZHorolog + 10
	While (($Get(^OcuTalonTest("FixExecutor", flagM)) '= "held") || ($Get(^OcuTalonTest("FixExecutor", flagU)) '= "held")) && ($ZHorolog < end) {
		Hang 0.1
	}
	Set held = $Get(^OcuTalonTest("FixExecutor", flagM))_"|"_$Get(^OcuTalonTest("FixExecutor", flagU))
	Do $$$AssertEquals(held, "held|held", "other jobs hold the two runs' locks")
	If held '= "held|held" Quit
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 0, "Sweep returns nothing for a run it cannot lock")
	Do $$$AssertEquals(..Stored(idM)_"#"_..Row(refM), "0|5|0|0|0|0|5|#executing||", "and writes nothing for the marked run: no EndedAt, the request still executing")
	Do $$$AssertEquals(..Stored(idU)_"#"_..Row(refU), "0|0|0|0|0|0|0|#executing||", "nor for the unmarked one")
	Do $$$AssertEquals(..AuditCount()_"|"_..ClosedList(), "0|", "no entry and no close")
	Set counts = {"total": 5, "resent": 3, "completed": 3, "failedAgain": 0, "skipped": 0, "interrupted": 2, "reason": ""}
	Set wrote = ##class(OcuTalon.Fix.Executor).End(##class(OcuTalon.Data.FixRun).%OpenId(idM), counts, 1, .sc)
	Do $$$AssertEquals(wrote_"|"_($SYSTEM.Status.GetErrorText(sc) [ "lock"), "0|1", "End refuses a run whose lock another job holds, naming the lock")
	Set marked = ##class(OcuTalon.Fix.Executor).Mark(##class(OcuTalon.Data.FixRun).%OpenId(idM), 5, .sc)
	Do $$$AssertEquals(marked_"|"_($SYSTEM.Status.GetErrorText(sc) [ "lock"), "0|1", "and so does Mark")
	Do $$$AssertEquals(..Stored(idM), "0|5|0|0|0|0|5|", "neither wrote anything")
	Do ..ReleaseFlag(flagU)
	Set ..HoldFlag = flagM
	Do ..Hold(idU)
	Set results = $ClassMethod(probe, "Sweep")
	Do $$$AssertEquals(results.Count(), 1, "once a run's lock is free the next Sweep reports it")
	Do $$$AssertEquals($Select(results.Count() = 1: results.GetAt(1).ApprovalRef, 1: ""), refU, "the run whose lock was freed, and not the one still held")
	Do $$$AssertEquals(..Stored(idM)_"#"_..Row(refM), "0|5|0|0|0|0|5|#executing||", "which is still left as it was")
}

Method TestEndRefusesAnEndedOrMarkedRun()
{
	Set executor = "OcuTalon.Fix.Executor"
	Set owner = ..Owner("end")
	Set before = "2026-05-31T23:00:00Z"
	Set counts = {"total": 3, "resent": 3, "completed": 3, "failedAgain": 0, "skipped": 0, "reason": ""}
	Set cut = {"total": 3, "resent": 3, "completed": 3, "failedAgain": 0, "skipped": 0, "interrupted": 0, "reason": ""}

	// an ended run: nothing ends it again, nothing marks it
	Set i1 = ..Incident(owner)
	Set r1 = ..Request(owner, i1, "executing")
	Set ended = ..FixRun(i1, r1, {"startedAt": (before), "endedAt": "2026-05-31T23:30:00Z"})
	Do $$$AssertEquals($ClassMethod(executor, "End", ended, counts, 0, .sc), 0, "End refuses a run that has ended")
	Do $$$AssertStatusNotOK(sc, "with the reason")
	Do $$$AssertEquals($ClassMethod(executor, "End", ended, cut, 1, .sc), 0, "also for an interrupted end")
	Do $$$AssertEquals($ClassMethod(executor, "Mark", ended, 3, .sc), 0, "and Mark refuses it too")
	Do $$$AssertEquals(..Stored(ended.%Id()), "1|0|0|0|0|0|0|", "nothing is written")

	// a marked run: a normal end is refused, an interrupted end is not
	Set i2 = ..Incident(owner)
	Set r2 = ..Request(owner, i2, "executing")
	Set marked = ..FixRun(i2, r2, {"startedAt": (before), "total": 3})
	Do $$$AssertEquals($ClassMethod(executor, "End", marked, counts, 0, .sc), 0, "End refuses a normal end of a run that is marked as interrupted")
	Do $$$AssertEquals($ClassMethod(executor, "Mark", marked, 3, .sc), 0, "and Mark refuses a run that is marked already")
	Do $$$AssertEquals(..Stored(marked.%Id()), "0|3|0|0|0|0|3|", "nothing is written")

	// an unmarked run: an interrupted end is refused, a normal end writes
	Set i3 = ..Incident(owner)
	Set r3 = ..Request(owner, i3, "executing")
	Set plain = ..FixRun(i3, r3, {"startedAt": (before)})
	Do $$$AssertEquals($ClassMethod(executor, "End", plain, cut, 1, .sc), 0, "End refuses an interrupted end of a run that is not marked")
	Do $$$AssertEquals(..Stored(plain.%Id()), "0|0|0|0|0|0|0|", "and writes nothing")
	Do $$$AssertEquals($ClassMethod(executor, "End", plain, counts, 0, .sc), 1, "a normal end of it writes")
	Do $$$AssertStatusOK(sc, "and saves")
	Do $$$AssertEquals(..Stored(plain.%Id()), "1|3|3|3|0|0|0|", "EndedAt and the counts")
	Do $$$AssertEquals($ClassMethod(executor, "End", plain, counts, 0, .sc), 0, "and a second end is refused")

	// an unmarked run is marked once
	Set i4 = ..Incident(owner)
	Set r4 = ..Request(owner, i4, "executing")
	Set fresh = ..FixRun(i4, r4, {"startedAt": (before)})
	Do $$$AssertEquals($ClassMethod(executor, "Mark", fresh, 3, .sc), 1, "Mark marks a run that is not marked")
	Do $$$AssertEquals(..Stored(fresh.%Id()), "0|3|0|0|0|0|3|", "with Total and Interrupted 3 and no EndedAt")
	Do $$$AssertEquals($ClassMethod(executor, "Mark", fresh, 3, .sc), 0, "and once")

	// Waiting leaves out a marked run; a look at a marked run ends in a Finish that End refuses
	Set host = ..Host(..#LONGPROBE)
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set resentAt = ..Stamp(0)
	Set i5 = ..Incident(owner)
	Set r5 = ..Request(owner, i5, "executing")
	Set cutRun = ..FixRun(i5, r5, {"startedAt": (before), "copies": [9981, 9982, 9983], "resentAt": (resentAt), "total": 3})
	Set i6 = ..Incident(owner)
	Set r6 = ..Request(owner, i6, "executing")
	Set twin = ..FixRun(i6, r6, {"startedAt": (before), "copies": [9984, 9985, 9986], "resentAt": (resentAt)})
	Set host.Incidents = i5_","_i6
	Set waiting = host.WaitingNow()
	Do $$$AssertEquals($ListLength(waiting), 1, "Waiting gives one run of the two that wait")
	Do $$$AssertEquals($ListToString(waiting), twin.%Id(), "the one that is not marked")
	Set host.StatusIs = ..Canned(9981, 3, "Completed").%ToJSON()
	Set looked = host.LookNow(cutRun.%Id())
	Do $$$AssertEquals(looked, "", "a look at the marked run counts its copies and finishes it")
	Do $$$AssertEquals(..Row(r5), "executing||", "but End refuses the run: its request is not closed")
	Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0)_"|"_$Select($IsObject(host.Audits): host.Audits.%Size(), 1: 0), "0|0", "no FixResult is sent and no entry is written")
	Do $$$AssertEquals(..Stored(cutRun.%Id()), "0|3|0|0|0|0|3|", "and the run is as it was")
	Do $$$AssertEquals(..EndedLines(r5), 1, "one Type 4 line says that FixExecutor left the run")
}

/// --- helpers ---
/// A shadow instance of the probe (or of the class given, a subclass of it), in this process.
Method Host(class As %String = {..#PROBE}) As OcuTalon.Test.Fix.ExecutorProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_class, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	Quit host
}

/// A fixture session; its Ref is the owner of the fixture rows.
Method Owner(name As %String) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzexec"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A fixture incident of the owner (fixing, noticed) with the fields after the defaults; its Ref.
Method Incident(owner As %String, fields As %DynamicObject = "") As %String
{
	Set all = {"State": "fixing", "OpenVariant": ""}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, ##class(OcuTalon.Data.Time).NowUtc(), "ZZNS", "Zz.Executor"_..Number, all)
	Set ..Refs = ..Refs_","_ref
	Set ..Incidents = ..Incidents_","_ref
	Quit ref
}

/// A fixture fix request of the owner for the incident in the state, a repair_resend over the targets 101, 102 and 103, with the fields after the defaults; its Ref.
Method Request(owner As %String, incident As %String, state As %String, fields As %DynamicObject = "") As %String
{
	Set all = {"FixKind": "repair_resend", "FixParameters": (..#PARAMETERS), "FixTargets": "101,102,103", "ResultTarget": "IncidentManager", "AnsweredChannel": "web", "AnsweredAt": "2030-01-01T10:00:00Z"}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, state, , all)
	Set ..Refs = ..Refs_","_ref
	Quit ref
}

/// Adds a case of an unusable row to the list: label, the incident the request names, the fields of the request as JSON text ("" for none) and the number of targets.
ClassMethod AddCase(ByRef cases, label As %String, incident As %String, fields As %String, total As %Integer) [ Private ]
{
	Set cases($Order(cases(""), -1) + 1) = $ListBuild(label, incident, fields, total)
}

/// Hands the probe an Execute for the Ref; the status.
Method Send(host As OcuTalon.Test.Fix.ExecutorProbe, ref As %String) As %Status
{
	Set request = ##class(OcuTalon.Fix.Msg.Execute).%New()
	Set request.ApprovalRef = ref
	Set response = ""
	Set sc = host.OnMessage(request, .response)
	Do $$$AssertEquals(response, "", "the handler gives no response")
	Quit sc
}

/// Asserts how a run ended: the request is in the state "State|Result|finished" (see Row), the incident has one FixRun for the request with no copies, and the probe
/// recorded one more FixResult than the tests before it: final, Total the total, Resent, Completed and FailedAgain 0, Skipped the number given (0 by default) and the reason;
/// when it was sent, the FixRun's EndedAt and the request's close were on disk already.
Method AssertEnded(host As OcuTalon.Test.Fix.ExecutorProbe, ref As %String, incident As %String, row As %String, total As %Integer, reason As %String, label As %String, skipped As %Integer = 0)
{
	Do $$$AssertEquals(..Row(ref), row, label_": the request is "_row)
	Set run = ##class(OcuTalon.Test.Watch.Case).RunOf(incident, ref)
	Do $$$AssertTrue($IsObject(run), label_": the request has a FixRun")
	If $IsObject(run) Do $$$AssertEquals(run.approvalRef_"|"_run.incidentRef_"|"_(run.startedAt '= "")_"|"_run.copies.%Size(), ref_"|"_incident_"|1|0", label_": which names the request and the incident, has a start and holds no copy")
	Set last = ..LastResult(host)
	Do $$$AssertTrue($IsObject(last), label_": a FixResult was sent")
	If '$IsObject(last) Quit
	Do $$$AssertEquals(last.approvalRef_"|"_last.incidentRef_"|"_last.final_"|"_last.interrupted, ref_"|"_incident_"|1|0", label_": the FixResult names the request and the incident and is final")
	Do $$$AssertEquals(last.total_"|"_last.resent_"|"_last.completed_"|"_last.failedAgain_"|"_last.skipped, total_"|0|0|0|"_skipped, label_": with the counts Total "_total_", Skipped "_skipped_" and the rest 0")
	Do $$$AssertEquals(last.reason, reason, label_": and the reason")
	If $IsObject(run) Do $$$AssertEquals(last.storedEnd_"|"_last.storedState, "1|"_$Piece(row, "|", 1), label_": when it was sent, the FixRun's EndedAt and the request's close were saved already")
	If $IsObject(run) {
		Do $$$AssertEquals(run.total_"|"_run.resent_"|"_run.completed_"|"_run.failedAgain_"|"_run.skipped_"|"_run.interrupted_"|"_run.reason, total_"|0|0|0|"_skipped_"|0|"_reason, label_": the FixRun stores the same counts and reason")
		Do $$$AssertTrue(run.endedAt '= "", label_": and an EndedAt")
	}
	Set entry = ..LastAudit(host)
	Do $$$AssertTrue($IsObject(entry), label_": an Action entry was written")
	If $IsObject(entry) Do $$$AssertEquals(entry.approvalRef_"|"_entry.result_"|"_entry.counts.total_"|"_entry.counts.resent_"|"_entry.counts.skipped, ref_"|"_$Piece(row, "|", 1)_"|"_total_"|0|"_skipped, label_": which names the request, the result and the counts")
}

/// Asserts how a run that resent copies ended: the request is in the state row ("State|Result|finished"), the probe recorded the final FixResult with the counts
/// ("total|resent|completed|failedAgain|skipped") and the reason, the FixRun stores the same with a ResentAt and an EndedAt (on disk already when the result was sent, as was
/// the request's close), the last Action entry carries the same counts, and the result reads as text through the catalog.
Method AssertCounted(host As OcuTalon.Test.Fix.ExecutorProbe, ref As %String, incident As %String, row As %String, counts As %String, reason As %String, label As %String, text As %String)
{
	Do $$$AssertEquals(..Row(ref), row, label_": the request is "_row)
	Set last = ..LastResult(host)
	Do $$$AssertTrue($IsObject(last), label_": a FixResult was sent")
	If '$IsObject(last) Quit
	Do $$$AssertEquals(last.approvalRef_"|"_last.incidentRef_"|"_last.final_"|"_last.interrupted, ref_"|"_incident_"|1|0", label_": it names the request and the incident and is final")
	Do $$$AssertEquals(last.total_"|"_last.resent_"|"_last.completed_"|"_last.failedAgain_"|"_last.skipped, counts, label_": with the counts "_counts)
	Do $$$AssertEquals(last.reason, reason, label_": and the reason")
	Do $$$AssertEquals(last.storedEnd_"|"_last.storedState, "1|"_$Piece(row, "|", 1), label_": when it was sent, the FixRun's EndedAt and counts and the request's close were saved already")
	Set run = ##class(OcuTalon.Test.Watch.Case).RunOf(incident, ref)
	Do $$$AssertTrue($IsObject(run), label_": the request has a FixRun")
	If $IsObject(run) {
		Do $$$AssertEquals(run.total_"|"_run.resent_"|"_run.completed_"|"_run.failedAgain_"|"_run.skipped, counts, label_": which stores the same counts")
		Do $$$AssertEquals(run.interrupted_"|"_run.reason, "0|"_reason, label_": Interrupted 0 and the same reason")
		Do $$$AssertTrue((run.resentAt '= "") && (run.endedAt '= ""), label_": with a ResentAt and an EndedAt")
	}
	Set entry = ..LastAudit(host)
	Do $$$AssertTrue($IsObject(entry), label_": an Action entry was written")
	If $IsObject(entry) Do $$$AssertEquals(entry.approvalRef_"|"_entry.result_"|"_entry.counts.total_"|"_entry.counts.resent_"|"_entry.counts.completed_"|"_entry.counts.failedAgain_"|"_entry.counts.skipped, ref_"|"_$Piece(row, "|", 1)_"|"_counts, label_": which carries the same counts")
	Do $$$AssertEquals(..Render(last, $Piece(row, "|", 1)), text, label_": and the text reads as the UX document has it")
}

/// The FixResult the probe recorded last, "" when it recorded none.
ClassMethod LastResult(host As OcuTalon.Test.Fix.ExecutorProbe) As %DynamicObject
{
	If '$IsObject(host.Results) || (host.Results.%Size() = 0) Quit ""
	Quit host.Results.%Get(host.Results.%Size() - 1)
}

/// The Action entry the probe recorded last, "" when it recorded none.
ClassMethod LastAudit(host As OcuTalon.Test.Fix.ExecutorProbe) As %DynamicObject
{
	If '$IsObject(host.Audits) || (host.Audits.%Size() = 0) Quit ""
	Quit host.Audits.%Get(host.Audits.%Size() - 1)
}

/// Asserts the Action entry the probe recorded at the index: the row's kind, the production and namespace of the incident, the result, the approver, the channel, the
/// owner as the session, the request's Ref and the counts ("total|resent|completed|failedAgain|skipped").
Method AssertEntry(host As OcuTalon.Test.Fix.ExecutorProbe, index As %Integer, ref As %String, incident As %String, owner As %String, result As %String, user As %String, channel As %String, counts As %String, label As %String)
{
	Set entry = $Select($IsObject(host.Audits) && (host.Audits.%Size() > index): host.Audits.%Get(index), 1: "")
	Do $$$AssertTrue($IsObject(entry), label_": an Action entry was written")
	If '$IsObject(entry) Quit
	Do $$$AssertEquals(entry.action_"|"_entry.target_"|"_entry.result_"|"_entry.approvalRef, "repair_resend|Zz.Executor"_..Number_" in ZZNS|"_result_"|"_ref, label_": it names the kind, the production and namespace, the result and the request")
	Do $$$AssertEquals(entry.irisUser_"|"_entry.channel_"|"_entry.sessionRef, user_"|"_channel_"|"_owner, label_": the approver, the channel and the session")
	Do $$$AssertEquals(entry.counts.total_"|"_entry.counts.resent_"|"_entry.counts.completed_"|"_entry.counts.failedAgain_"|"_entry.counts.skipped, counts, label_": and the counts "_counts)
}

/// The text of the result as the catalog renders it, through Notice.ResultKey and ResultSlots with the noun of the orders; key is the catalog key. sent is a result as the
/// probe recorded it, state the request's state then.
Method Render(sent As %DynamicObject, state As %String, Output key As %String) As %String
{
	Set result = ##class(OcuTalon.Fix.Msg.FixResult).%New()
	Set result.ApprovalRef = sent.approvalRef
	Set result.IncidentRef = sent.incidentRef
	Set result.Final = sent.final
	Set result.Interrupted = sent.interrupted
	Set result.Total = sent.total
	Set result.Resent = sent.resent
	Set result.Completed = sent.completed
	Set result.FailedAgain = sent.failedAgain
	Set result.Skipped = sent.skipped
	Set result.Reason = sent.reason
	Set key = ##class(OcuTalon.Watch.Notice).ResultKey(state, result)
	Set slots = ##class(OcuTalon.Watch.Notice).ResultSlots(key, result, {"one": "order", "other": "orders"}, .sc)
	Do $$$AssertStatusOK(sc, "the slots of "_key_" are built")
	If '$IsObject(slots) Quit ""
	Set text = ##class(OcuTalon.Msg.Catalog).Render(key, slots.%ToJSON(), "phone", .sc)
	Do $$$AssertStatusOK(sc, "and it renders")
	Quit text
}

/// A group of the incident for the item, with the error pattern of the error text (the incident's own cause). The incident's groups are deleted after the test.
Method Group(incident As %String, item As %String, text As %String)
{
	Set group = ##class(OcuTalon.Data.FailureGroup).%New()
	Set group.IncidentRef = incident
	Set group.Seq = 1
	Set group.ItemName = item
	Set group.ErrorPattern = ##class(OcuTalon.Watch.Settle).Pattern(text)
	Do $$$AssertStatusOK(group.%Save(), "the incident has a group of "_item)
}

/// The targets 101 to 100 + count, comma-separated.
ClassMethod TargetList(count As %Integer) As %String
{
	Set list = ""
	For i = 1:1:count Set list = list _ $Select(list = "": "", 1: ",") _ (100 + i)
	Quit list
}

/// A canned CarryIs of count copies with the ids first, first + 1 and so on, and no skipped target.
ClassMethod CarryJSON(first As %Integer, count As %Integer) As %String
{
	Set copies = []
	For i = 0:1:count - 1 Do copies.%Push(first + i)
	Quit {"copies": (copies), "skipped": []}.%ToJSON()
}

/// A canned CarryIs of the copies in the list (comma-separated ids, in the order they are registered).
ClassMethod CarryList(ids As %String) As %String
{
	Set copies = []
	For i = 1:1:$Length(ids, ",") Do copies.%Push($Piece(ids, ",", i))
	Quit {"copies": (copies), "skipped": []}.%ToJSON()
}

/// A canned StatusIs of count copies with the ids first, first + 1 and so on, all in the status and with no error text, as a dynamic object.
ClassMethod Canned(first As %Integer, count As %Integer, status As %String) As %DynamicObject
{
	Set statuses = {}
	For i = 0:1:count - 1 Do statuses.%Set(first + i, {"status": (status), "error": "", "target": "OrdersFromPartner"})
	Quit statuses
}

/// Frees the probe's wait lock if a job of a test still holds it, and waits (up to 5 seconds) until that job has let go.
Method ReleaseLock()
{
	If ..HoldFlag = "" Quit
	Set flags = ..HoldFlag
	Set ..HoldFlag = ""
	For i = 1:1:$Length(flags, ",") {
		If $Piece(flags, ",", i) '= "" Do ..ReleaseFlag($Piece(flags, ",", i))
	}
}

/// Tells the HoldLock job of the flag to give its lock up, waits up to 5 seconds until it has, and removes the flag.
ClassMethod ReleaseFlag(flag As %String) [ Private ]
{
	If $Get(^OcuTalonTest("FixExecutor", flag)) = "held" Set ^OcuTalonTest("FixExecutor", flag) = "release"
	Set end = $ZHorolog + 5
	While ($Get(^OcuTalonTest("FixExecutor", flag)) = "release") && ($ZHorolog < end) {
		Hang 0.1
	}
	Kill ^OcuTalonTest("FixExecutor", flag)
}

/// Holds the lock (a global name) in a job of its own: it sets the flag (a subscript of ^OcuTalonTest("FixExecutor")) to held once it has the lock, and gives the lock up
/// when the flag is anything else, or after a minute, and sets the flag to released. A test starts it with Job and sets the flag to release to free the lock.
ClassMethod HoldLock(lock As %String, flag As %String)
{
	Lock +@lock:5
	If '$Test {
		Set ^OcuTalonTest("FixExecutor", flag) = "refused"
		Quit
	}
	Set ^OcuTalonTest("FixExecutor", flag) = "held"
	Set end = $ZHorolog + 60
	While ($Get(^OcuTalonTest("FixExecutor", flag)) = "held") && ($ZHorolog < end) {
		Hang 0.1
	}
	Lock -@lock
	Set ^OcuTalonTest("FixExecutor", flag) = "released"
}

/// Tries the lock (a global name) in a job of its own, for up to 5 seconds, and sets the flag (a subscript of ^OcuTalonTest("FixExecutor")) to free when it got it
/// (it lets go at once) or to busy when it did not. A test starts it with Job (see LockIsFree).
ClassMethod TryLock(lock As %String, flag As %String)
{
	Lock +@lock:5
	Set free = $Test
	Set ^OcuTalonTest("FixExecutor", flag) = $Select(free: "free", 1: "busy")
	If free Lock -@lock
}

/// 1 when a job of its own can take the lock (a global name) at once: nobody, this process included, holds it.
Method LockIsFree(lock As %String) As %Boolean
{
	Set flag = "try"_..Number_"x"_$Increment(^OcuTalonTest("FixExecutor", "try"))
	Set ^OcuTalonTest("FixExecutor", flag) = ""
	Job ##class(OcuTalon.Test.Fix.Executor).TryLock(lock, flag)
	Set end = $ZHorolog + 20
	While ($Get(^OcuTalonTest("FixExecutor", flag)) = "") && ($ZHorolog < end) {
		Hang 0.1
	}
	Set state = $Get(^OcuTalonTest("FixExecutor", flag))
	Kill ^OcuTalonTest("FixExecutor", flag)
	Quit (state = "free")
}

/// Hands the probe an Execute for the Ref (Send) while Ens.Job is asked to give this process the job request (quiescent or terminate); the request is taken back
/// afterwards, also when the handler throws. The status.
Method SendWhileJobIs(host As OcuTalon.Test.Fix.ExecutorProbe, ref As %String, request As %String) As %Status
{
	Set $$$EnsJobRequest($$$SystemName, $Job) = request
	Try {
		Set sc = ..Send(host, ref)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Kill $$$EnsJobRequest($$$SystemName, $Job)
	Quit sc
}

/// The row of the request as "State|Result|finished" ("finished" when FinishedAt is set); "<none>" for a Ref with no row.
ClassMethod Row(ref As %String) As %String
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT State, Result, FinishedAt FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE Ref = ?", ref)
	If 'rs.%Next() Quit "<none>"
	Quit rs.%Get("State")_"|"_rs.%Get("Result")_"|"_$Select(rs.%Get("FinishedAt") '= "": "finished", 1: "")
}

/// Every column of the request's row as text, to compare before and after; "<none>" for a Ref with no row.
ClassMethod Whole(ref As %String) As %String
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT * FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE Ref = ?", ref)
	If 'rs.%Next() Quit "<none>"
	Set text = ""
	For i = 1:1:rs.%ResultColumnCount Set text = text _ rs.%GetData(i) _ $Char(31)
	Quit text
}

/// The FixRun rows of the incident (Test.Watch.Case Runs).
ClassMethod Runs(incident As %String) As %DynamicArray
{
	Quit ##class(OcuTalon.Test.Watch.Case).Runs(incident)
}

/// The calls of the re-check and the resend that the probe recorded, as "checked/carried" (a number when both are 0 and a test asks for 0).
ClassMethod Calls(host As OcuTalon.Test.Fix.ExecutorProbe) As %String
{
	Set checked = $Select($IsObject(host.Checked): host.Checked.%Size(), 1: 0)
	Set carried = $Select($IsObject(host.Carried): host.Carried.%Size(), 1: 0)
	Quit $Select((checked = 0) && (carried = 0): 0, 1: checked_"/"_carried)
}

/// A fixture FixRun of the request for the incident, started now unless fields say otherwise, saved. fields is an object of startedAt, copies (an array of header ids),
/// resentAt, endedAt and total (a run that is marked as interrupted has Total and Interrupted set to it). The test process takes the run's lock at once and holds it until the test ends (Hold).
Method FixRun(incident As %String, ref As %String, fields As %DynamicObject = "") As OcuTalon.Data.FixRun
{
	Set run = ##class(OcuTalon.Data.FixRun).%New()
	Set run.ApprovalRef = ref
	Set run.IncidentRef = incident
	Set run.StartedAt = ##class(OcuTalon.Data.Time).NowUtc()
	If $IsObject(fields) {
		If fields.%IsDefined("startedAt") Set run.StartedAt = fields.startedAt
		If fields.%IsDefined("resentAt") Set run.ResentAt = fields.resentAt
		If fields.%IsDefined("endedAt") Set run.EndedAt = fields.endedAt
		If fields.%IsDefined("total") {
			Set run.Total = fields.total
			Set run.Interrupted = fields.total
		}
		If fields.%IsDefined("copies") {
			Set iterator = fields.copies.%GetIterator()
			While iterator.%GetNext(, .copy) {
				Do run.Copies.Insert(copy)
			}
		}
	}
	Do $$$AssertStatusOK(run.%Save(), "a FixRun is saved")
	Do ..Hold(run.%Id())
	Quit run
}

/// A marked run (Total and Interrupted the number of targets) of a new request over targets targets, with the copies (comma-separated header ids), fed the statuses and the outcome
/// for Test.Fix.RunProbe; the request's Ref. The request is executing.
Method MarkedRun(owner As %String, incident As %String, targets As %Integer, copies As %String, statuses As %DynamicObject, outcome As %String = "read") As %String
{
	Set ref = ..Request(owner, incident, "executing", {"FixTargets": (..TargetList(targets))})
	Set list = []
	For i = 1:1:$Length(copies, ",") Do list.%Push($Piece(copies, ",", i))
	Do ..FixRun(incident, ref, {"startedAt": "2026-05-31T23:00:00Z", "copies": (list), "total": (targets)})
	Do ##class(OcuTalon.Test.Fix.RunProbe).Feed(ref, statuses, outcome)
	Quit ref
}

/// An unmarked run of a new request over targets targets, with the copies, the ResentAt given and the request in the state (executing by default), fed the statuses and the outcome for
/// Test.Fix.RunProbe; the request's Ref.
Method UnmarkedRun(owner As %String, incident As %String, targets As %Integer, copies As %String, resentAt As %String, statuses As %DynamicObject, state As %String = "executing", outcome As %String = "read") As %String
{
	Set ref = ..Request(owner, incident, state, {"FixTargets": (..TargetList(targets))})
	Set list = []
	For i = 1:1:$Length(copies, ",") Do list.%Push($Piece(copies, ",", i))
	Set fields = {"startedAt": (##class(OcuTalon.Bridge.Time).PlusSeconds(##class(OcuTalon.Data.Time).NowUtc(), -200)), "copies": (list)}
	If resentAt '= "" Do fields.%Set("resentAt", resentAt)
	Do ..FixRun(incident, ref, fields)
	Do ##class(OcuTalon.Test.Fix.RunProbe).Feed(ref, statuses, outcome)
	Quit ref
}

/// Takes the lock of the run for this process (Executor.TakeRun) and remembers the hold, so that OnAfterOneTest lets go of it (Test.Watch.Case HoldRun).
Method Hold(id As %String)
{
	Do ##class(OcuTalon.Test.Watch.Case).HoldRun(id)
}

/// Lets go of one hold of the run's lock.
Method LetGo(id As %String)
{
	Do ##class(OcuTalon.Test.Watch.Case).LetGoRun(id)
}

/// Lets go of every hold.
Method FreeRuns()
{
	Do ##class(OcuTalon.Test.Watch.Case).FreeRuns()
}

/// The stored end of the FixRun as "ended|Total|Resent|Completed|FailedAgain|Skipped|Interrupted|Reason", ended being 1 when EndedAt is set; "<none>" for no such run.
ClassMethod Stored(id As %String) As %String
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT EndedAt, Total, Resent, Completed, FailedAgain, Skipped, Interrupted, Reason FROM OcuTalon_Data.FixRun WHERE ID = ?", id)
	If 'rs.%Next() Quit "<none>"
	Quit (rs.%GetData(1) '= "")_"|"_+rs.%GetData(2)_"|"_+rs.%GetData(3)_"|"_+rs.%GetData(4)_"|"_+rs.%GetData(5)_"|"_+rs.%GetData(6)_"|"_+rs.%GetData(7)_"|"_rs.%GetData(8)
}

/// The state of the request's row.
ClassMethod StateOf(ref As %String) As %String
{
	Quit $Piece(..Row(ref), "|", 1)
}

/// The calls of Close that Test.Fix.RunProbe recorded, comma-separated.
ClassMethod ClosedList() As %String
{
	Set closed = ##class(OcuTalon.Test.Fix.RunProbe).Closed()
	Set text = ""
	For i = 0:1:closed.%Size() - 1 Set text = text _ $Select(text = "": "", 1: ",") _ closed.%Get(i)
	Quit text
}

/// The number of Action entries that Test.Fix.RunProbe recorded.
ClassMethod AuditCount() As %Integer
{
	Quit ##class(OcuTalon.Test.Fix.RunProbe).Audits().%Size()
}

/// A canned status of count copies with the ids first, first + 1 and so on, all in the status with no error text and the time at (a header's timeProcessed), as a dynamic object.
ClassMethod CannedAt(first As %Integer, count As %Integer, status As %String, at As %String) As %DynamicObject
{
	Set statuses = {}
	For i = 0:1:count - 1 Do statuses.%Set(first + i, {"status": (status), "error": "", "target": "OrdersFromPartner", "at": (at)})
	Quit statuses
}

/// The UTC stamp that lies the number of seconds (negative for earlier) from now.
ClassMethod Stamp(seconds As %Integer) As %String
{
	Quit ##class(OcuTalon.Bridge.Time).PlusSeconds(##class(OcuTalon.Data.Time).NowUtc(), seconds)
}

/// The FixResult of the request among the results of a Sweep, "" when there is none.
ClassMethod ResultFor(results As %ListOfObjects, ref As %String) As OcuTalon.Fix.Msg.FixResult
{
	Set found = ""
	For i = 1:1:results.Count() {
		If results.GetAt(i).ApprovalRef = ref {
			Set found = results.GetAt(i)
			Quit
		}
	}
	Quit found
}

/// The FixResult as the dynamic object that Render takes (the fields of the probe's records).
ClassMethod AsSent(result As OcuTalon.Fix.Msg.FixResult) As %DynamicObject
{
	Quit {"approvalRef": (result.ApprovalRef), "incidentRef": (result.IncidentRef), "final": (+result.Final), "interrupted": (+result.Interrupted), "total": (+result.Total), "resent": (+result.Resent), "completed": (+result.Completed), "failedAgain": (+result.FailedAgain), "skipped": (+result.Skipped), "reason": (result.Reason)}
}

/// Asserts the FixResult that a Sweep gave for a marked run: the counts ("total|resent|completed|failedAgain|skipped"), the Interrupted flag of the result and of the stored run
/// (Interrupted is the stored count of the targets cut off), the key and the text, the request closed interrupted and the run ended.
Method AssertCut(results As %ListOfObjects, ref As %String, counts As %String, flag As %Boolean, cutOff As %Integer, key As %String, text As %String, label As %String)
{
	Set result = ..ResultFor(results, ref)
	Do $$$AssertTrue($IsObject(result), label_": a FixResult is returned")
	If '$IsObject(result) Quit
	Do $$$AssertEquals(result.Total_"|"_result.Resent_"|"_result.Completed_"|"_result.FailedAgain_"|"_result.Skipped, counts, label_": the counts "_counts)
	Do $$$AssertEquals(+result.Final_"|"_+result.Interrupted, "1|"_flag, label_": final, Interrupted "_flag)
	Set got = ..Render(..AsSent(result), ..StateOf(ref), .gotKey)
	Do $$$AssertEquals(gotKey, key, label_": the key is "_key)
	Do $$$AssertEquals(got, text, label_": the text")
	Do $$$AssertEquals(..Row(ref), "failed|interrupted|finished", label_": the request is failed with the Result interrupted")
	Set run = ##class(OcuTalon.Data.FixRun).OfRequest(ref)
	Do $$$AssertEquals(..Stored(run.%Id()), "1|"_$Piece(counts, "|", 1)_"|"_$Piece(counts, "|", 2)_"|"_$Piece(counts, "|", 3)_"|"_$Piece(counts, "|", 4)_"|"_$Piece(counts, "|", 5)_"|"_cutOff_"|"_result.Reason, label_": the run is ended with the same counts and Interrupted "_cutOff)
}

/// Asserts the FixResult that a Sweep gave for a run that no waiter ended: the counts, the reason, the key and the text, the Interrupted flag 0 and the state of the request's row.
Method AssertDone(results As %ListOfObjects, ref As %String, incident As %String, counts As %String, reason As %String, key As %String, text As %String, row As %String, label As %String)
{
	Set result = ..ResultFor(results, ref)
	Do $$$AssertTrue($IsObject(result), label_": a FixResult is returned")
	If '$IsObject(result) Quit
	Do $$$AssertEquals(result.IncidentRef_"|"_+result.Final_"|"_+result.Interrupted, incident_"|1|0", label_": it names the incident, is final and is not interrupted")
	Do $$$AssertEquals(result.Total_"|"_result.Resent_"|"_result.Completed_"|"_result.FailedAgain_"|"_result.Skipped, counts, label_": the counts "_counts)
	Do $$$AssertEquals(result.Reason, reason, label_": the reason")
	Set got = ..Render(..AsSent(result), ..StateOf(ref), .gotKey)
	Do $$$AssertEquals(gotKey, key, label_": the key is "_key)
	Do $$$AssertEquals(got, text, label_": the text")
	Do $$$AssertEquals(..Row(ref), row, label_": the request is "_row)
	Set run = ##class(OcuTalon.Data.FixRun).OfRequest(ref)
	Do $$$AssertEquals(..Stored(run.%Id()), "1|"_$Piece(counts, "|", 1)_"|"_$Piece(counts, "|", 2)_"|"_$Piece(counts, "|", 3)_"|"_$Piece(counts, "|", 4)_"|"_$Piece(counts, "|", 5)_"|0|"_reason, label_": the run is ended with the same counts and Interrupted 0")
}

/// The number of Type 4 lines in which Sweep said that it ended the run of the request, since the test began.
Method SweptLines(ref As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter("OcuTalon.Fix.Run", "LOGSWEPT")_ref)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of Type 4 lines in which FixExecutor said that it left the run of the request (End refused it), since the test began.
Method EndedLines(ref As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGENDED")_ref)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of Type 4 lines of the executor's refusals in the event log since the test began.
Method Infos() As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGREFUSED"))
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The text of the newest Type 4 line of a refusal that names the Ref ("" for any), "" when there is none.
Method RefusedLine(ref As %String) As %String
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ? ORDER BY ID DESC", ..LogMark, $Parameter(..#PROBE, "LOGREFUSED")_ref)
	If result.%Next() Quit result.%Get("Text")
	Quit ""
}

/// The number of Type 3 warnings of the re-check after the row mark that name the Ref.
Method Warnings(mark As %Integer, ref As %String) As %Integer
{
	Quit ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Run", $Parameter(..#PROBE, "LOGRECHECK")_ref)
}

/// Removes the lines that the tests made: the refusals and the warnings of the executor.
Method RemoveLogs()
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGREFUSED"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Run", $Parameter(..#PROBE, "LOGRECHECK"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Report", $Parameter(..#PROBE, "LOGRESULT"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Close", $Parameter(..#PROBE, "LOGFINISH"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "CouldNotStart", $Parameter(..#PROBE, "LOGRUN"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Unchecked", $Parameter(..#PROBE, "LOGMISSING"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Pass", $Parameter(..#PROBE, "LOGWAIT"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Pass", $Parameter(..#PROBE, "LOGLOOK"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Audit", $Parameter(..#PROBE, "LOGAUDIT"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Finish", $Parameter(..#PROBE, "LOGRUN"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Run", $Parameter(..#PROBE, "LOGRUN"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Wait", $Parameter(..#PROBE, "LOGWAIT"))
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGENDED"))
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter("OcuTalon.Fix.Run", "LOGSWEPT"))
	For method = "EndMarked", "EndLeft" {
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, method, $Parameter("OcuTalon.Fix.Run", "LOGCLOSE"))
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, method, $Parameter("OcuTalon.Fix.Run", "LOGREAD"))
	}
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Sweep", $Parameter("OcuTalon.Fix.Run", "LOGSWEEP"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Ended", $Parameter("OcuTalon.Fix.Run", "LOGSAVE"))
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Entry", $Parameter("OcuTalon.Fix.Run", "LOGAUDIT"))
}

}
