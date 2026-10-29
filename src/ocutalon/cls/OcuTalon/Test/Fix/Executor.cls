/// Tests of what FixExecutor does with an Execute (Story 7.3; AD-11, AD-16), through a shadow instance of Test.Fix.ExecutorProbe in the test process, over fixture
/// sessions, incidents and approval requests of Test.Data.Fixture and the product's own handler, FixRun row, StartExecution and FinishExecution. The probe records the
/// FixResults that the handler sends (no production is needed to send them) and stands in for the kind's Recheck and Execute and for the resources check, so that each
/// route is driven without an Orders production; the real re-check, resend and result are pinned by Test.Fix.Recheck, Execute, Refused and Runs on a fresh stack. They run warm.
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
///   - TestNothingResent (AC 3; V2): a run whose targets are all skipped (by the re-check, by the resend, or by both) closes its request done and sends one final FixResult:
///     Total and Skipped the number of targets, Resent, Completed and FailedAgain 0 and the reason of the lowest skipped target;
///   - TestResentRunSendsNoResult (V2): a run that registered a copy ends after the registration with its request still executing, its copies on the FixRun and no FixResult;
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

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The incident Refs of the test being run (the FixRun rows that name them are deleted), comma-separated.
Property Incidents As %String(MAXLEN = "");

/// The number of the newest row of the event log when the test began.
Property LogMark As %Integer;

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
	For i = 1:1:$Length(..Incidents, ",") {
		If $Piece(..Incidents, ",", i) '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.FixRun WHERE IncidentRef = ?", $Piece(..Incidents, ",", i))
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
	Do $$$AssertEquals(..Row(ref), "executing||", "and the request stays executing: the copy is not counted yet")
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
	Set last = $Select($IsObject(host.Results): host.Results.%Get(host.Results.%Size() - 1), 1: "")
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
	Set noun = {"one": "order", "other": "orders"}

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
		Set sent = host.Results.%Get(i)
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
		Set key = ##class(OcuTalon.Watch.Notice).ResultKey("failed", result)
		Do $$$AssertEquals(key, "result.couldNotStart", label(i)_": the key of the result")
		Set slots = ##class(OcuTalon.Watch.Notice).ResultSlots(key, result, noun, .sc)
		Do $$$AssertStatusOK(sc, label(i)_": the slots are built")
		If '$IsObject(slots) Continue
		Set text = ##class(OcuTalon.Msg.Catalog).Render(key, slots.%ToJSON(), "phone", .sc)
		Do $$$AssertStatusOK(sc, label(i)_": it renders")
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

Method TestResentRunSendsNoResult()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set host.MissingIs = "none"
	Set owner = ..Owner("resent")

	Set incident = ..Incident(owner)
	Set host.CheckIs = "{""passed"":""101,102,103"",""skipped"":[]}"
	Set host.CarryIs = "{""copies"":[""9001"",""9002"",""9003""],""skipped"":[]}"
	Set ref = ..Request(owner, incident, "approved")
	Do $$$AssertStatusOK(..Send(host, ref), "a run that resent three copies is handled")
	Do $$$AssertEquals(..Row(ref), "executing||", "its request stays executing: not done, with no Result and no FinishedAt")
	Set runs = ..Runs(incident)
	Do $$$AssertEquals(runs.%Size(), 1, "one FixRun is written")
	If runs.%Size() = 1 Do $$$AssertEquals(runs.%Get(0).approvalRef_"|"_runs.%Get(0).incidentRef_"|"_(runs.%Get(0).startedAt '= "")_"|"_runs.%Get(0).copies.%ToJSON(), ref_"|"_incident_"|1|[""9001"",""9002"",""9003""]", "it names the request and the incident, has a start and holds the three copies in order")
	Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0), 0, "and no FixResult is sent: the copies are not counted yet")

	// some skipped, some resent: the same
	Set incident = ..Incident(owner)
	Set host.CarryIs = "{""copies"":[""9004""],""skipped"":[{""id"":102,""reason"":""b""},{""id"":103,""reason"":""c""}]}"
	Set ref = ..Request(owner, incident, "approved")
	Do $$$AssertStatusOK(..Send(host, ref), "a run that resent one copy and skipped two is handled")
	Do $$$AssertEquals(..Row(ref), "executing||", "its request stays executing")
	Do $$$AssertEquals($Select($IsObject(host.Results): host.Results.%Size(), 1: 0), 0, "and no FixResult is sent")

	// a second Execute for the request that executes is refused: still one FixRun with its copies
	Set copies = ..Runs(incident).%Get(0).copies.%ToJSON()
	Do $$$AssertStatusOK(..Send(host, ref), "a second Execute for the executing request is handled")
	Do $$$AssertEquals(..Runs(incident).%Size()_"|"_..Runs(incident).%Get(0).copies.%ToJSON(), "1|"_copies, "it is refused: still one FixRun with the same copies")
	Do $$$AssertEquals(..Calls(host), "2/2", "and nothing was re-checked or resent for it")
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
	Set last = $Select($IsObject(host.Results): host.Results.%Get(host.Results.%Size() - 1), 1: "")
	Do $$$AssertTrue($IsObject(last), label_": a FixResult was sent")
	If '$IsObject(last) Quit
	Do $$$AssertEquals(last.approvalRef_"|"_last.incidentRef_"|"_last.final_"|"_last.interrupted, ref_"|"_incident_"|1|0", label_": the FixResult names the request and the incident and is final")
	Do $$$AssertEquals(last.total_"|"_last.resent_"|"_last.completed_"|"_last.failedAgain_"|"_last.skipped, total_"|0|0|0|"_skipped, label_": with the counts Total "_total_", Skipped "_skipped_" and the rest 0")
	Do $$$AssertEquals(last.reason, reason, label_": and the reason")
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
}

}
