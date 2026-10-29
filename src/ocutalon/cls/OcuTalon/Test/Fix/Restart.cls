Include Ensemble

/// Tests of a resend that a restart cut short (Story 7.5; AD-5, AD-11, AD-12, AD-15, AD-16, AD-17, AD-18, AD-23, AD-26, AD-33). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh
/// (IncidentManager, FixExecutor and Checks are code of the running production, so a warm stack's jobs keep their old code), with demo mode on, through Test.Watch.Case: real failed
/// orders of OCUORDERS, the CI mock as the model, the real Approval.Raise and Approval.Answer, the real hold, IncidentManager, FixExecutor and Checks. They fail with the reason where
/// the production, OCUORDERS, demo mode or the ANSWERER account's role is missing. A test waits at most 90 seconds for a diagnosis and 20 for the rest (test bounds, not NFR-7). The
/// incidents, requests, holds, tasks and runs of a test, and every message it made in OCUORDERS (the copies included), are removed after it, and the item it stopped is started again.
/// The run is not cut short by a real restart (Epic 8's and Epic 15's units stay as they are): the test plays it, as the criterion says. FixExecutor is stopped (TempStopOwn), so that R1's
/// Execute waits in its queue, R1 is approved, and the test does what a run that was cut off had done: StartExecution, a FixRun, and the kind's Execute over the first three targets, whose
/// copies complete. The test holds the run's lock from its save until just before its own Tick, so that no real Tick sweeps the run before the test has looked at it.
///   - TestRestartSaysHowFarItGot (AC 1, AC 2, AC 3; Integration; the matrix rows "Cut short by a restart", "Started after the start" and "Reconcile again"): session S's incident awaits
///     approval with R1 over 5 failed orders. The first Reconcile step leaves the run, which started after the production's start: R1 stays executing and the run is not marked. With
///     the run's StartedAt backdated, the next Reconcile step marks it (Total 5, Interrupted 5, no EndedAt) and closes R1 failed with the Result interrupted, and sends no FixResult; one more
///     step changes nothing. FixExecutor starts again and refuses its queued Execute: the run keeps its 3 copies and R1 has no other FixRun. After a fixture Tick exactly one FixResult
///     (R1, the incident, Final 1, Interrupted 1, 5/3/3/0/0) goes from Checks to IncidentManager in the incident's trace session with R1's TraceRef; the run has an EndedAt, 5/3/3/0/0 and
///     Interrupted 2; the incident is resolved. S gets one result Notification (result.interrupted, count 5, completed 3, remaining 2) that renders "The resend stopped when OcuTalon
///     restarted: 3 of 5 orders went through. The other 2 need a new approval.", with a Delivery row in web and in phone; the last incident event and /state list R1 failed with the result
///     {5, 3, 3, 0, 0, 2}; targets 4 and 5 have no copy. The audit log holds one OcuTalon Action entry with the result interrupted and the counts, and the mock logged no request. More Ticks,
///     fixture and real-shaped, send no second FixResult and make no second Notification;
///   - TestReportedRunGetsNoSecondResult (AC 3; the matrix row "No second result"): a run that FixExecutor ended (Raised over 3 orders, approved, done) has exactly one FixResult across all
///     senders and sessions and one result Notification, also after more Ticks.
Class OcuTalon.Test.Fix.Restart Extends OcuTalon.Test.Watch.Case
{

/// The longest the end of a run is waited for, in seconds (a test bound, not NFR-7).
Parameter WAITEND = 90;

/// The words that no audit entry of the run may hold, in lower case.
Parameter FORBIDDEN = "sk-ant,token,password,secret,telegram,chatid,chat id,bearer";

Method TestRestartSaysHowFarItGot()
{
	If '..Raised("restart", .a, .ref, .request, 5) Quit
	Set refR = request.ref
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Do $$$AssertTrue(mark > 0, "the mock's request log is read")
	Set auditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()

	// FixExecutor is stopped and R1 approved: its Execute waits in the queue
	If '..TempStopOwn("FixExecutor") Quit
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(refR, "approve", "web", ..#ANSWERER, a, .winner), "done", "R1 is approved")
	Do $$$AssertEquals(..WaitIncidentState(ref, "fixing"), "fixing", "the incident is fixing")
	Set executes = ..ExecutesOf(trace, refR, 20)
	Do $$$AssertEquals(executes.%Size(), 1, "IncidentManager sent R1's Execute, which waits in FixExecutor's queue")
	If executes.%Size() '= 1 Quit

	// the run that was cut short: R1 executing, a FixRun with no ResentAt, and three copies of its first three targets that complete
	Set run = ..CutShortRun(request, ref, .id)
	If '$IsObject(run) Quit
	Set copies = ..CopiesOf(run)
	Kill run
	Do $$$AssertEquals($Length(copies, ","), 3, "the kind's Execute made three copies")
	Do $$$AssertTrue(..WaitCompleted(..#ORDERS, copies), "and they complete")
	Do $$$AssertEquals(..Runs(ref).%Size(), 1, "R1 has one FixRun")

	// the Reconcile step, first pass: the run started after the production's start
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Reconcile).Run(), "the Reconcile step runs")
	Do $$$AssertEquals(..RequestState(ref, refR)_"|"_..Marked(id), "executing|0", "it leaves the run: R1 is still executing, and the run is not marked")

	// with the run's StartedAt before the production's start, the next step marks it and closes R1
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.FixRun SET StartedAt = ? WHERE ID = ?", "2000-01-01T00:00:00Z", id)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Reconcile).Run(), "the Reconcile step runs again")
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Install.Step).TakeWarnings(), " ; "), "", "and warns of nothing")
	Set closed = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(refR)
	Do $$$AssertEquals(closed.State_"|"_closed.Result_"|"_(closed.FinishedAt '= ""), "failed|interrupted|1", "R1 is failed with the Result interrupted")
	Set finishedAt = closed.FinishedAt
	Kill closed
	Do $$$AssertEquals(##class(OcuTalon.Data.FixRun).EndedAtGetStored(id)_"|"_##class(OcuTalon.Data.FixRun).TotalGetStored(id)_"|"_##class(OcuTalon.Data.FixRun).InterruptedGetStored(id), "|5|5", "the run is marked: Total 5, Interrupted 5, no EndedAt")
	Do $$$AssertEquals(..FixResultsFor(refR).%Size(), 0, "and no FixResult has been sent")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Reconcile).Run(), "a third Reconcile step runs")
	Set closed = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(refR)
	Do $$$AssertEquals(closed.State_"|"_closed.FinishedAt, "failed|"_finishedAt, "it changes nothing: R1 is not closed a second time")
	Kill closed

	// FixExecutor starts again and refuses its queued Execute: no second run, no new copy
	If '..TempStartOwn("FixExecutor") Quit
	Set handled = ..WaitHandled(executes.%Get(0).id)
	Do $$$AssertEquals(handled, 1, "FixExecutor handles the queued Execute")
	Do $$$AssertEquals(..Runs(ref).%Size()_"|"_..RunOf(ref, refR).copies.%Size(), "1|3", "R1 still has one FixRun, with its 3 copies")
	Do $$$AssertEquals(..FixResultsFor(refR).%Size(), 0, "and the refused Execute made no FixResult")

	// the test lets go of the run's lock, and a Tick goes to Checks
	Do ..LetGoRun(id)
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set results = ..WaitFixResults(refR, 1)
	Do $$$AssertEquals(results.%Size(), 1, "exactly one FixResult for R1 now exists, from any sender in any session")
	If results.%Size() '= 1 Quit
	Set sent = results.%Get(0)
	Do $$$AssertEquals(sent.source_"|"_sent.target_"|"_sent.sessionId_"|"_sent.superSession, "Checks|IncidentManager|"_trace_"|"_request.traceRef, "Checks sent it to IncidentManager, in the incident's trace session with R1's TraceRef")
	Do $$$AssertEquals(sent.incidentRef_"|"_sent.final_"|"_sent.interrupted, ref_"|1|1", "it names the incident, is final and is interrupted")
	Do $$$AssertEquals(sent.total_"|"_sent.resent_"|"_sent.completed_"|"_sent.failedAgain_"|"_sent.skipped_"|"_sent.reason, "5|3|3|0|0|", "with the counts 5/3/3/0/0 and no reason")
	Set stored = ..RunOf(ref, refR)
	Do $$$AssertEquals((stored.endedAt '= "")_"|"_stored.total_"|"_stored.resent_"|"_stored.completed_"|"_stored.failedAgain_"|"_stored.skipped_"|"_stored.interrupted_"|"_stored.reason, "1|5|3|3|0|0|2|", "the run has an EndedAt and stores 5/3/3/0/0 with Interrupted 2")
	Do $$$AssertEquals(..WaitIncidentState(ref, "resolved"), "resolved", "the incident is resolved")

	// what S sees
	Set notes = ..WaitResultNotices(ref, 1)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one result Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef_"|"_note.incidentRef_"|"_note.sessionRef_"|"_note.decisionRef, "result|result.interrupted|"_refR_"|"_ref_"|"_a_"|", "of the key interrupted, with R1's Ref, the incident's and no decision")
		Do $$$AssertEquals(note.slots.count_"|"_note.slots.completed_"|"_note.slots.remaining, "5|3|2", "with count 5, completed 3 and remaining 2")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc), "The resend stopped when OcuTalon restarted: 3 of 5 orders went through. The other 2 need a new approval.", "which renders as the UX document has it")
		Do $$$AssertEquals(..NoticeSessionOf(note.id), trace, "in the incident's trace session")
	}
	Do ..AssertDeliveredIn(a, ##class(OcuTalon.Channel.WebChat.Out).#CHANNEL, "result", refR)
	Do ..AssertDeliveredIn(a, ##class(OcuTalon.Channel.SimPhone.Out).#CHANNEL, "result", refR)
	Set last = ..LastIncident(a, ref)
	Do $$$AssertTrue($IsObject(last), "the incident event is on S's stream")
	If $IsObject(last) {
		Do $$$AssertEquals(last.state_"|"_..Listed(last), "resolved|1|"_refR_"|failed", "the last one lists R1 failed in the resolved incident")
		Do $$$AssertEquals(..ResultOf(last), "5|3|3|0|0|2|", "with the result 5/3/3/0/0 and 2 cut off")
	}
	Set state = ..StateIncident(a, ref)
	Do $$$AssertTrue($IsObject(state), "/state lists the incident")
	If $IsObject(state) {
		Do $$$AssertEquals(state.state_"|"_..Listed(state), "resolved|1|"_refR_"|failed", "/state lists R1 failed")
		Do $$$AssertEquals(..ResultOf(state), "5|3|3|0|0|2|", "with the same result")
	}
	Do $$$AssertEquals(..Originals(stored.copies), $Piece(request.fixTargets, ",", 1, 3), "the copies are of the first three targets: the 4th and the 5th have no copy")

	// the audit log and the mock
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(auditMark, "OcuTalon", "Action", "", refR, "", 1, 20)
	Do $$$AssertEquals(entries.%Size(), 1, "the audit log holds one OcuTalon Action entry for R1")
	If entries.%Size() = 1 {
		Set data = entries.%Get(0).data
		Do $$$AssertEquals(..SortedKeys(data), "action,approvalRef,channel,counts,irisUser,result,sessionRef,target", "it has the members of the Action shape and no other")
		Do $$$AssertEquals(data.result_"|"_data.approvalRef_"|"_data.action_"|"_data.sessionRef, "interrupted|"_refR_"|repair_resend|"_a, "with the result interrupted, R1's Ref, the kind and S")
		Do $$$AssertEquals(data.counts.%ToJSON(), "{""total"":5,""resent"":3,""completed"":3,""failedAgain"":0,""skipped"":0}", "and the counts as numbers")
		Set text = $ZConvert(data.%ToJSON()_" "_entries.%Get(0).description, "L")
		Set bad = ""
		For i = 1:1:$Length(..#FORBIDDEN, ",") {
			If text [ $Piece(..#FORBIDDEN, ",", i) Set bad = bad _ $Piece(..#FORBIDDEN, ",", i) _ " "
		}
		Do $$$AssertEquals(bad, "", "holding no key, token, password or chat identity")
	}
	Do $$$AssertEquals(..Posts(mark), 0, "the mock logged no request")

	// no second result, from the fixture Ticks or the real heartbeat's
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do ..RealTick()
	Hang 2
	Do $$$AssertEquals(..FixResultsFor(refR).%Size(), 1, "more Ticks send no second FixResult")
	Do $$$AssertEquals(..NoticeBodies(ref, "result").%Size(), 1, "and make no second Notification")
	Do $$$AssertEquals(..Runs(ref).%Size(), 1, "R1 still has one FixRun")

	// the run has ended: End refuses to end it again, whoever asks (the stored EndedAt decides)
	Set counts = {"total": 5, "resent": 3, "completed": 3, "failedAgain": 0, "skipped": 0, "interrupted": 2, "reason": ""}
	Set wrote = ##class(OcuTalon.Fix.Executor).End(##class(OcuTalon.Data.FixRun).%OpenId(id), counts, 1, .sc)
	Do $$$AssertEquals(wrote, 0, "End refuses the run that has ended")
	Do $$$AssertEquals(##class(OcuTalon.Data.FixRun).InterruptedGetStored(id)_"|"_..FixResultsFor(refR).%Size(), "2|1", "and changes nothing")
}

Method TestReportedRunGetsNoSecondResult()
{
	If '..Raised("reported", .a, .ref, .request) Quit
	Set refR = request.ref
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(refR, "approve", "web", ..#ANSWERER, a, .winner), "done", "R1 is approved")
	Do $$$AssertEquals(..WaitState(ref, refR, "done", ..#WAITEND), "done", "FixExecutor ends R1: it is done")
	Set results = ..WaitFixResults(refR, 1)
	Do $$$AssertEquals(results.%Size(), 1, "R1 has one FixResult")
	If results.%Size() = 1 Do $$$AssertEquals(results.%Get(0).source_"|"_results.%Get(0).final_"|"_results.%Get(0).interrupted, "FixExecutor|1|0", "from FixExecutor, final and not interrupted")
	Set notes = ..WaitResultNotices(ref, 1)
	Do $$$AssertEquals(notes.%Size(), 1, "and S has one result Notification")
	Do $$$AssertEquals(..WaitIncidentState(ref, "resolved"), "resolved", "the incident is resolved")

	// Ticks: the fixture's and the real-shaped one change nothing
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do ..RealTick()
	Hang 2
	Do $$$AssertEquals(..FixResultsFor(refR).%Size(), 1, "more Ticks send no second FixResult, from any sender in any session")
	Do $$$AssertEquals(..NoticeBodies(ref, "result").%Size(), 1, "and make no second Notification")
}

/// The run that was cut short: R1 executing (StartExecution), a FixRun that started now and has no ResentAt, and the kind's Execute over the request's first three targets, which registers
/// their copies on the run. The test holds the run's lock from its save until LetGoRun. id is the run's id. The FixRun, or "" with a failed assertion.
Method CutShortRun(request As %DynamicObject, ref As %String, Output id As %Integer) As OcuTalon.Data.FixRun [ Private ]
{
	Set id = ""
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).StartExecution(request.ref), "R1 is executing: the test plays the run that was cut short")
	Set run = ##class(OcuTalon.Data.FixRun).%New()
	Set run.ApprovalRef = request.ref
	Set run.IncidentRef = ref
	Set run.StartedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(run.%Save(), "the FixRun is saved with no ResentAt")
	Set id = run.%Id()
	Do $$$AssertTrue(..HoldRun(id), "the test holds the run's lock")
	Set incident = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set parameters = {}.%FromJSON(request.fixParameters)
	Set first = $Piece(request.fixTargets, ",", 1, 3)
	Set sc = ##class(OcuTalon.Fix.Kind.RepairResend).Execute(incident, parameters, first, .result, run)
	Do $$$AssertStatusOK(sc, "the kind's Execute resends the first three targets")
	If $$$ISERR(sc) Quit ""
	Quit run
}

/// The header ids of the run's copies, comma-separated.
ClassMethod CopiesOf(run As OcuTalon.Data.FixRun) As %String
{
	Set copies = ""
	For i = 1:1:run.Copies.Count() Set copies = copies _ $Select(copies = "": "", 1: ",") _ run.Copies.GetAt(i)
	Quit copies
}

/// 1 when the run is marked as interrupted (its stored Interrupted is above 0).
ClassMethod Marked(id As %Integer) As %Boolean
{
	Quit +##class(OcuTalon.Data.FixRun).InterruptedGetStored(id) > 0
}

/// Waits up to 30 seconds, polling every quarter second, until the header (an Execute for FixExecutor) is Completed; 1 when it is.
Method WaitHandled(headerId As %Integer) As %Boolean [ Private ]
{
	Set end = $ZHorolog + 30
	For {
		Set status = ##class(Ens.MessageHeader).StatusGetStored(headerId)
		If (status = $$$eMessageStatusCompleted) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit (status = $$$eMessageStatusCompleted)
}

}
