/// Tests of what FixExecutor does with an Execute (Stories 7.3 and 7.4; AD-11, AD-16), through a shadow instance of Test.Fix.ExecutorProbe in the test process, over fixture
/// sessions, incidents and approval requests of Test.Data.Fixture and the product's own handler, FixRun row, StartExecution and FinishExecution. The probe records the
/// FixResults that the handler sends (no production is needed to send them), the Action entries it would write and the session of each send, and stands in for the kind's
/// Recheck and Execute, for the resources check and for the read of the copies (canned statuses), so that each route is driven without an Orders production; the real
/// re-check, resend, wait and result are pinned by Test.Fix.Recheck, Execute, Refused, Runs, Results, Partial, Waits and Scale on a fresh stack. They run warm.
/// Each test asserts the FixRun rows, the request's state and Result and the recorded FixResult.
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
///   - TestStartExecutionFailsForAnApprovedRequest (AC 11; DW-380): an approved request, not past its expiry, whose StartExecution fails ends as could not start: one FixRun, the
///     request failed, one FixResult with Total the number of targets, every other count 0 and the reason "OcuTalon couldn't start the resend", one Action entry, and
///     neither the re-check nor the resend is called; a pending, a cancelled and an executing request, and an approved one past its expiry, are refused;
///   - TestEveryRunWritesOneActionEntry (AC 5): a run that cannot start, one that resent nothing and one that resent copies each write one Action entry, with the row's FixKind,
///     the production and namespace of the incident, the result, the counts as numbers, the request's Ref, the approver and channel (the system and the job's user without
///     them), the owner as the session when that is a Ref, and no member beside the shape; a write that fails logs one Type 3 warning (LOGAUDIT) and the FixResult still goes;
///   - TestFailedSendLogsOneWarning: a send that fails logs one Type 3 warning and the request is closed all the same;
///   - TestUnknownRequest: a request that is neither a DryRun nor an Execute is the error 5001 that names its class, with no answer.
/// The fixture rows and the log lines of a test are removed after it.
Class OcuTalon.Test.Fix.Executor Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Fix.ExecutorProbe";

/// The parameters of the repair of the requests.
Parameter PARAMETERS = "{""field"":""OrderDate"",""sourceFormat"":""MM/DD/YYYY"",""targetFormat"":""YYYY-MM-DD""}";

/// The reasons that the executor gives (public text; the catalog renders them after "Nothing was resent: ").
Parameter NOTALLOWED = "OcuTalon isn't allowed to resend messages in that production";

Parameter UNUSABLE = "OcuTalon couldn't read the approved fix";

Parameter NOREAD = "OcuTalon couldn't read the failed messages in that production";

Parameter NOSTART = "OcuTalon couldn't start the resend";

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

/// The flag of the job that holds the probe's wait lock (HoldLock), "" when no test started one.
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
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..ReleaseLock()
	For i = 1:1:$Length(..Incidents, ",") {
		If $Piece(..Incidents, ",", i) '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.FixRun WHERE IncidentRef = ?", $Piece(..Incidents, ",", i))
		If $Piece(..Incidents, ",", i) '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.FailureGroup WHERE IncidentRef = ?", $Piece(..Incidents, ",", i))
	}
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
	Set host = ..Host()
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

/// --- helpers ---
/// A shadow instance of the probe, in this process.
Method Host() As OcuTalon.Test.Fix.ExecutorProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
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
/// recorded one more FixResult than the tests before it: final, Total the total, Resent, Completed and FailedAgain 0, Skipped the number given (0 by default) and the reason.
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
	If $IsObject(run) {
		Do $$$AssertEquals(run.total_"|"_run.resent_"|"_run.completed_"|"_run.failedAgain_"|"_run.skipped_"|"_run.interrupted_"|"_run.reason, total_"|0|0|0|"_skipped_"|0|"_reason, label_": the FixRun stores the same counts and reason")
		Do $$$AssertTrue(run.endedAt '= "", label_": and an EndedAt")
	}
	Set entry = ..LastAudit(host)
	Do $$$AssertTrue($IsObject(entry), label_": an Action entry was written")
	If $IsObject(entry) Do $$$AssertEquals(entry.approvalRef_"|"_entry.result_"|"_entry.counts.total_"|"_entry.counts.resent_"|"_entry.counts.skipped, ref_"|"_$Piece(row, "|", 1)_"|"_total_"|0|"_skipped, label_": which names the request, the result and the counts")
}

/// Asserts how a run that resent copies ended: the request is in the state row ("State|Result|finished"), the probe recorded the final FixResult with the counts
/// ("total|resent|completed|failedAgain|skipped") and the reason, the FixRun stores the same with a ResentAt and an EndedAt, the last Action entry carries the same counts,
/// and the result reads as text through the catalog.
Method AssertCounted(host As OcuTalon.Test.Fix.ExecutorProbe, ref As %String, incident As %String, row As %String, counts As %String, reason As %String, label As %String, text As %String)
{
	Do $$$AssertEquals(..Row(ref), row, label_": the request is "_row)
	Set last = ..LastResult(host)
	Do $$$AssertTrue($IsObject(last), label_": a FixResult was sent")
	If '$IsObject(last) Quit
	Do $$$AssertEquals(last.approvalRef_"|"_last.incidentRef_"|"_last.final_"|"_last.interrupted, ref_"|"_incident_"|1|0", label_": it names the request and the incident and is final")
	Do $$$AssertEquals(last.total_"|"_last.resent_"|"_last.completed_"|"_last.failedAgain_"|"_last.skipped, counts, label_": with the counts "_counts)
	Do $$$AssertEquals(last.reason, reason, label_": and the reason")
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
	Set flag = ..HoldFlag
	Set ..HoldFlag = ""
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
}

}
