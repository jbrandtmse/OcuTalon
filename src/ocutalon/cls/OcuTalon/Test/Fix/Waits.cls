Include Ensemble

/// Tests of the wait of a run (Story 7.4; AD-15, AD-16, AD-26; DW-381). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh (IncidentManager and FixExecutor
/// are code of the running production, and the pool of the item is the production's, so a warm stack's jobs keep their old code and pool), with demo mode on, through
/// Test.Watch.Case: real failed orders of OCUORDERS, the CI mock as the model, the real FixExecutor, the real Approval.Raise and Approval.Answer and the real hold and
/// IncidentManager. They fail with the reason where the production, OCUORDERS, demo mode or the ANSWERER account's role is missing. A test waits at most 90 seconds for
/// a diagnosis and 20 for the rest (test bounds, not NFR-7). The incidents, requests, holds, tasks and runs of a test, and every message it made in OCUORDERS, are
/// removed after it, and the item it stopped is started again.
/// Both tests first wait until FixExecutor runs both jobs of its pool. They stop OrdersFromPartner (TempStopConfigItem) before R1 is approved, so that R1's three copies stay
/// Queued and FixExecutor waits for them, and everything a test needs while the run waits (a second session and its failed sample order, or the second incident of the
/// dry-run test) is made before the approval, so that nothing but the system under test runs inside R1's 60 seconds. Each test waits for the system's own signals (the
/// run's ResentAt, a NoticedAt, a request's state, an answer) and, at the moment it starts the item again, measures the seconds since R1's ResentAt in the product's own
/// unit (a stamp to the second): they must be at most MARGIN, so that the copies complete and the waiter's next pass ends R1 well before its 60 seconds. A host that is too
/// slow for the window fails with that number, not with a run that never ended.
///   - TestNoticeSentDuringAWait (AC 8, DW-381; the matrix row "A wait holds no notice"): session S's R1, over three failed orders, is approved while OrdersFromPartner is
///     stopped. Its three copies stay Queued, and R1 is executing with a ResentAt and no EndedAt: FixExecutor waits for them. At once a FailureBatch gives session S2 a new
///     incident B (an old failed sample order of S2, which the dry run reads). B is noticed with its fix: NoticedAt is set, B is awaiting_approval, S2 has one
///     incident.withFix Notification and one request of its own, because FixExecutor's other job answered B's dry run while R1 still waited. Once OrdersFromPartner starts
///     again, inside R1's 60 seconds, the copies complete and R1 ends with result.allThrough;
///   - TestDryRunAnsweredDuringAWait (AC 8, DW-381; AD-15's 35-second notice): while R1 waits for its queued copies, a DryRun that asks for ANOTHER incident (a second
///     incident of S over the same failed orders) is sent to FixExecutor and answered with its targets and dry run within the notice budget, and R1 has not ended when
///     the answer comes. With one job in the pool the ask would sit behind R1's wait, which ends 60 seconds after its ResentAt.
Class OcuTalon.Test.Fix.Waits Extends OcuTalon.Test.Watch.Case
{

/// The longest B's notice is waited for, in seconds, from the moment its batch is sent; R1 waits 60 seconds from its ResentAt, and B's notice must come inside them (a test
/// bound, not NFR-7).
Parameter WAITNOTICE = 40;

/// The longest the end of R1's run is waited for once its item is started again, in seconds (a test bound, not NFR-7).
Parameter WAITEND = 60;

/// The most seconds, counted in stamps from R1's ResentAt, that may have passed when the test restarts the item: the product's 60 seconds less ten for the copies to complete
/// and for the waiter's next pass (every half second) to end R1.
Parameter MARGIN = {##class(OcuTalon.Fix.Executor).#WAITSECONDS - 10};

/// AD-15's notice budget in seconds: a DryRun that FixExecutor's second job answers during a wait must come well inside it (the typical answer takes a few hundredths).
Parameter NOTICEBUDGET = 35;

/// The longest the pool's jobs are waited for, in seconds (a test bound, not NFR-7).
Parameter JOBSWAIT = 30;

/// How long the dry-run test waits for FixExecutor's answer, in seconds: longer than the budget, so that a late answer is measured, shorter than R1's 60 seconds.
Parameter ASKWAIT = 45;

Method TestNoticeSentDuringAWait()
{
	If '..Raised("held", .a, .ref, .request) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row

	// FixExecutor runs both jobs of its pool, and what B needs is made before R1's window opens
	Do $$$AssertEquals(..WaitJobs(..#EXECUTOR, 2), 2, "FixExecutor runs two jobs: its pool is two")
	Set a2 = ..Session("held2")
	Set super2 = ##class(OcuTalon.Data.Session).RefIndexOpen(a2).TraceRef
	Set sample = ..SampleOrder(super2)
	If sample = "" Quit
	If '..TempStopItem("OrdersFromPartner") Quit
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(request.ref, "approve", "web", ..#ANSWERER, a, .winner), "done", "R1 is approved while OrdersFromPartner is stopped")

	// B's failure goes in at once, so that its settle runs beside R1's wait
	Set sc = ..SendBatch(..#ORDERS, ..#ORDERSPRODUCTION, a2, [{"item": "OrdersFromPartner", "text": (..#ORDERDATETEXT), "at": (##class(OcuTalon.Data.Time).NowUtc()), "id": (sample)}])
	Do $$$AssertStatusOK(sc, "a FailureBatch gives S2 a failure of OrdersFromPartner")

	// R1 resends its three copies and waits: they stay queued
	Set run = ..WaitResent(ref, request.ref, 3)
	Do $$$AssertTrue($IsObject(run) && (run.copies.%Size() = 3) && (run.resentAt '= ""), "R1's FixRun holds three copies and a ResentAt")
	If '$IsObject(run) || (run.copies.%Size() '= 3) || (run.resentAt = "") Quit
	Set resentAt = run.resentAt
	Do $$$AssertEquals(..WaitQueued(run.copies), 3, "the three copies are queued: their item is stopped")
	Do $$$AssertEquals(run.endedAt_"|"_..Requests(ref).%Get(0).state, "|executing", "R1's run has no EndedAt and R1 is executing")

	// meanwhile S2's new incident is noticed with its fix: the other job answers its dry run
	Set rows = ..WaitIncident(a2, ..#ORDERSPRODUCTION, 1, ..#WAITNOTICE)
	Do $$$AssertEquals(rows.%Size(), 1, "S2 has one incident, B")
	If rows.%Size() '= 1 Quit
	Set refB = rows.%Get(0).ref
	Set ..ItemIds = ..ItemIds _ $ListBuild(refB)
	Set noticed = ..WaitRow(refB, "NoticedAt", "", ..#WAITNOTICE)
	Do $$$AssertTrue(noticed '= "", "B is noticed while R1 waits")
	Set run = ..RunOf(ref, request.ref)
	Do $$$AssertEquals(run.endedAt_"|"_..Requests(ref).%Get(0).state, "|executing", "and R1 has not ended: its run still waits")
	Set bRow = ##class(OcuTalon.Data.Incident).RefIndexOpen(refB)
	Do $$$AssertEquals(bRow.State_"|"_bRow.OpenVariant, "awaiting_approval|", "B is awaiting approval with its fix")
	Set bNoticed = bRow.NoticedAt
	Do $$$AssertTrue('(resentAt ] bNoticed), "B was noticed at "_bNoticed_", not before R1's ResentAt "_resentAt)
	Kill bRow
	Set requestsB = ..Requests(refB)
	Do $$$AssertEquals(requestsB.%Size(), 1, "one request names B")
	Set notesB = ..NoticeBodies(refB, "incident")
	Do $$$AssertEquals(notesB.%Size(), 1, "S2 has one incident Notification")
	If notesB.%Size() = 1 Do $$$AssertEquals(notesB.%Get(0).catalogKey_"|"_notesB.%Get(0).sessionRef_"|"_notesB.%Get(0).incidentRef, "incident.withFix|"_a2_"|"_refB, "the with-fix notice of B for S2")
	Do $$$AssertEquals(..NoticeBodies(ref, "result").%Size(), 0, "while S has no result yet")

	// OrdersFromPartner starts again inside R1's 60 seconds: the copies complete and R1 ends
	Set used = ..SecondsSince(resentAt)
	Do $$$AssertTrue(used '> ..#MARGIN, "B was noticed at "_bNoticed_", and the item is started again "_used_" seconds after R1's ResentAt, at most "_..#MARGIN_" seconds after it, so that R1 can end inside its "_##class(OcuTalon.Fix.Executor).#WAITSECONDS_" seconds")
	If used > ..#MARGIN Quit
	If '..TempStartItem("OrdersFromPartner") Quit
	Do $$$AssertEquals(..WaitState(ref, request.ref, "done", ..#WAITEND), "done", "R1 is done once its copies completed")
	Set run = ..RunOf(ref, request.ref)
	Do $$$AssertEquals(run.total_"|"_run.resent_"|"_run.completed_"|"_run.failedAgain_"|"_run.skipped_"|"_run.interrupted_"|"_run.reason, "3|3|3|0|0|0|", "with the result 3/3/3/0/0")
	Set end = $ZHorolog + ..#WAITHOLD
	For {
		Set notes = ..NoticeBodies(ref, "result")
		If (notes.%Size() '< 1) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(notes.%Size(), 1, "S has one result Notification")
	If notes.%Size() = 1 Do $$$AssertEquals(notes.%Get(0).catalogKey_"|"_notes.%Get(0).approvalRef, "result.allThrough|"_request.ref, "result.allThrough with R1's Ref")
	Do $$$AssertEquals(..WaitIncidentState(ref, "resolved"), "resolved", "and the incident is resolved")
}

Method TestDryRunAnsweredDuringAWait()
{
	If '..Raised("asked", .a, .ref, .request) Quit

	// FixExecutor runs both jobs of its pool, and the other incident, F, of S over the same failed orders (the dry run keeps to the incident's owner's scope), is made
	// before R1's window opens
	Do $$$AssertEquals(..WaitJobs(..#EXECUTOR, 2), 2, "FixExecutor runs two jobs: its pool is two")
	Set super = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set ids = request.fixTargets
	Set other = ..Fixture(a, ids)
	Set refF = other.Ref
	Kill other
	Do $$$AssertTrue((refF '= "") && (refF '= ref), "F is an incident of its own")
	If '..TempStopItem("OrdersFromPartner") Quit
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(request.ref, "approve", "web", ..#ANSWERER, a, .winner), "done", "R1 is approved while OrdersFromPartner is stopped")

	// R1 waits: its copies stay queued
	Set run = ..WaitResent(ref, request.ref, 3)
	Do $$$AssertTrue($IsObject(run) && (run.copies.%Size() = 3) && (run.resentAt '= ""), "R1's FixRun holds three copies and a ResentAt")
	If '$IsObject(run) || (run.copies.%Size() '= 3) || (run.resentAt = "") Quit
	Set resentAt = run.resentAt
	Do $$$AssertEquals(run.endedAt_"|"_..Requests(ref).%Get(0).state, "|executing", "R1's run has no EndedAt and R1 is executing")

	// the ask for F is answered by the other job, inside the notice budget
	Set started = $ZHorolog
	Set response = ..AskDryRun(refF, request.fixKind, request.fixParameters, super, .session, .sc, ..#ASKWAIT)
	Set asked = $ZHorolog - started
	Do $$$AssertStatusOK(sc, "FixExecutor answers F's DryRun while R1 waits")
	Do $$$AssertTrue($IsObject(response), "with a DryRunResult")
	Do $$$AssertTrue(asked '> ..#NOTICEBUDGET, "FixExecutor's answer took "_$Justify(asked, 0, 2)_" seconds, and AD-15's notice budget is "_..#NOTICEBUDGET_" seconds")
	If $IsObject(response) {
		Set dryRun = $Select(response.DryRun '= "": {}.%FromJSON(response.DryRun), 1: {})
		Do $$$AssertEquals(response.Reason_"|"_response.IncidentRef_"|"_response.Targets, "|"_refF_"|"_ids, "it names F and holds F's three targets, with no reason")
		Do $$$AssertEquals(dryRun.affected_"|"_dryRun.resend_"|"_dryRun.leftOut, "3|3|0", "and a dry run of 3 affected, 3 to resend and none left out")
	}
	Set run = ..RunOf(ref, request.ref)
	Do $$$AssertEquals(run.endedAt_"|"_..Requests(ref).%Get(0).state, "|executing", "R1 had not ended when the answer came: its run still waited")

	// the item starts again inside R1's 60 seconds: the copies complete and R1 ends
	Set used = ..SecondsSince(resentAt)
	Do $$$AssertTrue(used '> ..#MARGIN, "the item is started again "_used_" seconds after R1's ResentAt, at most "_..#MARGIN_" seconds after it, so that R1 can end inside its "_##class(OcuTalon.Fix.Executor).#WAITSECONDS_" seconds")
	If used > ..#MARGIN Quit
	If '..TempStartItem("OrdersFromPartner") Quit
	Do $$$AssertEquals(..WaitState(ref, request.ref, "done", ..#WAITEND), "done", "R1 is done once its copies completed")
	Set run = ..RunOf(ref, request.ref)
	Do $$$AssertEquals(run.total_"|"_run.resent_"|"_run.completed_"|"_run.failedAgain_"|"_run.skipped_"|"_run.interrupted_"|"_run.reason, "3|3|3|0|0|0|", "with the result 3/3/3/0/0")
	Do $$$AssertEquals(..WaitIncidentState(ref, "resolved"), "resolved", "and the incident is resolved")
}

/// Waits up to WAITRUN seconds, polling every half second, until the request's FixRun holds at least count copies and a ResentAt (the run waits for them); the run as
/// Runs gives it, or "" when there is none.
Method WaitResent(incidentRef As %String, approvalRef As %String, count As %Integer) As %DynamicObject [ Private ]
{
	Set end = $ZHorolog + ..#WAITRUN
	For {
		Set run = ..RunOf(incidentRef, approvalRef)
		If ($IsObject(run) && (run.copies.%Size() '< count) && (run.resentAt '= "")) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit run
}

/// Waits up to JOBSWAIT seconds, polling every half second, until the item has count alive jobs; the number of its alive jobs then.
Method WaitJobs(item As %String, count As %Integer) As %Integer [ Private ]
{
	Set end = $ZHorolog + ..#JOBSWAIT
	For {
		Set jobs = $ListLength(##class(OcuTalon.Test.Agent.RunnerFixture).Jobs(item))
		If (jobs '< count) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit jobs
}

/// Waits up to 10 seconds, polling every quarter second, until every copy (an array of header ids of OCUORDERS) is Queued; the number of copies that are Queued then.
Method WaitQueued(copies As %DynamicArray) As %Integer [ Private ]
{
	Set end = $ZHorolog + 10
	For {
		Set queued = 0
		For i = 0:1:copies.%Size() - 1 {
			Set copy = ..Header(..#ORDERS, copies.%Get(i))
			If $IsObject(copy) && (copy.status = $$$eMessageStatusQueued) Set queued = queued + 1
		}
		If (queued = copies.%Size()) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit queued
}

/// The seconds from the stamp (UTC to the second) to now, in stamps, as the executor's deadline counts them.
ClassMethod SecondsSince(stamp As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Watch.Settle).Seconds(##class(OcuTalon.Data.Time).NowUtc()) - ##class(OcuTalon.Watch.Settle).Seconds(stamp)
}

}
