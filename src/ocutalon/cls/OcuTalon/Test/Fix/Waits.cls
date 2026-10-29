Include Ensemble

/// Tests of the wait of a run (Story 7.4; AD-15, AD-16, AD-26; DW-381). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh (IncidentManager and FixExecutor
/// are code of the running production, and the pool of the item is the production's, so a warm stack's jobs keep their old code and pool), with demo mode on, through
/// Test.Watch.Case: real failed orders of OCUORDERS, the CI mock as the model, the real FixExecutor, the real Approval.Raise and Approval.Answer and the real hold and
/// IncidentManager. They fail with the reason where the production, OCUORDERS, demo mode or the ANSWERER account's role is missing. A test waits at most 90 seconds for
/// a diagnosis and 20 for the rest (test bounds, not NFR-7). The incidents, requests, holds, tasks and runs of a test, and every message it made in OCUORDERS, are
/// removed after it, and the item it stopped is started again.
///   - TestNoticeSentDuringAWait (AC 8, DW-381; the matrix row "A wait holds no notice"): OrdersFromPartner is temporarily stopped (TempStopConfigItem), and session S's
///     R1, over three failed orders, is approved. Its three copies stay Queued, and R1 is executing with a ResentAt and no EndedAt: FixExecutor waits for them. Then a
///     FailureBatch gives session S2 a new incident B (an old failed sample order of S2, which the dry run reads). Meanwhile B is noticed with its fix: NoticedAt is set,
///     B is awaiting_approval, S2 has one incident.withFix Notification and one request of its own, because FixExecutor's other job answered B's dry run while R1 still
///     waited. Once OrdersFromPartner starts again, inside R1's 60 seconds, the copies complete and R1 ends with result.allThrough.
Class OcuTalon.Test.Fix.Waits Extends OcuTalon.Test.Watch.Case
{

/// The longest B's notice is waited for, in seconds; R1 waits 60 seconds from its ResentAt, and B's notice must come inside them (a test bound, not NFR-7).
Parameter WAITNOTICE = 40;

/// The longest the end of R1's run is waited for once its item is started again, in seconds (a test bound, not NFR-7).
Parameter WAITEND = 60;

Method TestNoticeSentDuringAWait()
{
	If '..Raised("held", .a, .ref, .request) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row
	If '..TempStopItem("OrdersFromPartner") Quit
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(request.ref, "approve", "web", ..#ANSWERER, a, .winner), "done", "R1 is approved while OrdersFromPartner is stopped")

	// R1 resends its three copies and waits: they stay queued
	Set run = ..WaitRun(ref, request.ref, 3)
	Do $$$AssertTrue($IsObject(run) && (run.copies.%Size() = 3), "R1's FixRun holds three copies")
	If '$IsObject(run) || (run.copies.%Size() '= 3) Quit
	Hang 2
	For i = 0:1:2 {
		Set copy = ..Header(..#ORDERS, run.copies.%Get(i))
		Do $$$AssertEquals($Select($IsObject(copy): copy.status, 1: "none"), $$$eMessageStatusQueued, "copy "_(i + 1)_" is queued: its item is stopped")
	}
	Set run = ..RunOf(ref, request.ref)
	Do $$$AssertEquals((run.resentAt '= "")_"|"_run.endedAt, "1|", "R1's run has a ResentAt and no EndedAt")
	Do $$$AssertEquals(..Requests(ref).%Get(0).state, "executing", "and R1 is executing")

	// meanwhile S2's new incident is noticed with its fix: the other job answers its dry run
	Set a2 = ..Session("held2")
	Set super2 = ##class(OcuTalon.Data.Session).RefIndexOpen(a2).TraceRef
	Set sample = ..SampleOrder(super2)
	If sample = "" Quit
	Set sc = ..SendBatch(..#ORDERS, ..#ORDERSPRODUCTION, a2, [{"item": "OrdersFromPartner", "text": (..#ORDERDATETEXT), "at": (##class(OcuTalon.Data.Time).NowUtc()), "id": (sample)}])
	Do $$$AssertStatusOK(sc, "a FailureBatch gives S2 a failure of OrdersFromPartner")
	Set rows = ..WaitIncident(a2, ..#ORDERSPRODUCTION)
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
	Kill bRow
	Set requestsB = ..Requests(refB)
	Do $$$AssertEquals(requestsB.%Size(), 1, "one request names B")
	Set notesB = ..NoticeBodies(refB, "incident")
	Do $$$AssertEquals(notesB.%Size(), 1, "S2 has one incident Notification")
	If notesB.%Size() = 1 Do $$$AssertEquals(notesB.%Get(0).catalogKey_"|"_notesB.%Get(0).sessionRef_"|"_notesB.%Get(0).incidentRef, "incident.withFix|"_a2_"|"_refB, "the with-fix notice of B for S2")
	Do $$$AssertEquals(..NoticeBodies(ref, "result").%Size(), 0, "while S has no result yet")

	// OrdersFromPartner starts again inside R1's 60 seconds: the copies complete and R1 ends
	If '..TempStartItem("OrdersFromPartner") Quit
	Do $$$AssertEquals(..WaitState(ref, request.ref, "done", ..#WAITEND), "done", "R1 is done once its copies completed")
	Set run = ..RunOf(ref, request.ref)
	Do $$$AssertEquals(run.total_"|"_run.resent_"|"_run.completed_"|"_run.failedAgain_"|"_run.skipped_"|"_run.interrupted_"|"_run.reason, "3|3|3|0|0|0|", "with the result 3/3/3/0/0")
	Set notes = ..NoticeBodies(ref, "result")
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

}
