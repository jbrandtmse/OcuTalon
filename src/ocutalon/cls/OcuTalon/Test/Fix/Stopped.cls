Include Ensemble

/// Tests of a run whose waiter stopped while the production kept running (Story 7.5; DW-395; AD-15, AD-16, AD-17, AD-18, AD-26, AD-33). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21), fresh (IncidentManager, FixExecutor and Checks are code of the running production, so a warm stack's jobs keep their old code), with demo mode on, through Test.Watch.Case:
/// real failed orders of OCUORDERS, the CI mock as the model, the real Approval.Raise and Approval.Answer, the real hold, IncidentManager, FixExecutor and Checks. They fail with the
/// reason where the production, OCUORDERS, demo mode or the ANSWERER account's role is missing. A test waits at most 90 seconds for a diagnosis and 20 for the rest (test bounds, not
/// NFR-7). The incidents, requests, holds, tasks and runs of a test, and every message it made in OCUORDERS (the copies included), are removed after it, and the items it stopped are
/// started again.
///   - TestRunOfAStoppedWaiterEnds (AC 3, AC 4, AC 5; the matrix row "Waiter stopped"): session S's R1, over three failed orders, is approved while OrdersFromPartner is stopped, so
///     that its copies stay Queued and FixExecutor's waiter waits for them. FixExecutor's item is stopped and started again: the waiter quits, lets go of its lock and leaves the run
///     (no EndedAt, no FixResult). OrdersFromPartner starts again and the copies complete inside R1's 60 seconds. A Tick inside the wait changes nothing: R1 stays executing and
///     nothing is sent. A Tick after ResentAt + 60 seconds ends the run: R1 is done and its FixRun holds 3/3/3/0/0 with Interrupted 0; Checks sends one FixResult (Final 1, Interrupted 0)
///     in the incident's trace session with R1's TraceRef; S gets result.allThrough, "All 3 orders went through."; one OcuTalon Action entry records the result done; the incident
///     is resolved. A further Tick, fixture or real-shaped, gives nothing.
/// The elapsed seconds that the two timing bounds depend on (DW-399) are written by Timing, so that a passing run shows them too: how long after R1's ResentAt the copies' item was started
/// again, and how long after it the Tick inside the wait came. Timing logs a message and an assert of the status skipped (2), which ci/iris.sh prints as a SKIP line under the class result
/// (a status 2 never fails a class); a log message alone is stored but not printed.
Class OcuTalon.Test.Fix.Stopped Extends OcuTalon.Test.Watch.Case
{

/// The longest the end of a run is waited for, in seconds (a test bound, not NFR-7).
Parameter WAITEND = 60;

/// The most seconds, counted in stamps from R1's ResentAt, that may have passed when the test starts the item of the copies again: the product's 60 seconds less ten for the copies to
/// complete and for the first Tick to come inside the wait.
Parameter MARGIN = {##class(OcuTalon.Fix.Executor).#WAITSECONDS - 10};

/// The longest the waiter's lock is waited for to be let go, in seconds (a test bound, not NFR-7).
Parameter LOCKWAIT = 10;

Method TestRunOfAStoppedWaiterEnds()
{
	If '..Raised("stopped", .a, .ref, .request) Quit
	Set refR = request.ref
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row
	Set auditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()

	// R1 is approved while OrdersFromPartner is stopped: its copies stay queued, and FixExecutor's waiter waits for them
	If '..TempStopItem("OrdersFromPartner") Quit
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(refR, "approve", "web", ..#ANSWERER, a, .winner), "done", "R1 is approved while OrdersFromPartner is stopped")
	Set run = ..WaitResent(ref, refR, 3)
	Do $$$AssertTrue($IsObject(run) && (run.copies.%Size() = 3) && (run.resentAt '= ""), "R1's FixRun holds three copies and a ResentAt")
	If '$IsObject(run) || (run.copies.%Size() '= 3) || (run.resentAt = "") Quit
	Set resentAt = run.resentAt
	Do $$$AssertEquals(..WaitQueued(run.copies), 3, "the three copies are queued: their item is stopped")
	Do $$$AssertEquals(run.endedAt_"|"_..RequestState(ref, refR), "|executing", "R1's run has no EndedAt and R1 is executing")
	Do $$$AssertEquals(..WaitLockFree(0), 0, "FixExecutor's waiter holds the wait lock")

	// the waiter's item stops and starts again: the waiter quits and leaves the run
	If '..TempStopOwn("FixExecutor") Quit
	Do $$$AssertEquals(..WaitLockFree(..#LOCKWAIT), 1, "the waiter lets go of the wait lock when its item stops")
	If '..TempStartOwn("FixExecutor") Quit
	Do $$$AssertEquals(..WaitLockFree(..#LOCKWAIT), 1, "and no job holds it after the item starts again")
	Set run = ..RunOf(ref, refR)
	Do $$$AssertEquals(run.endedAt_"|"_..RequestState(ref, refR)_"|"_..FixResultsFor(refR).%Size(), "|executing|0", "the run is not ended: R1 is executing, with no EndedAt and no FixResult")

	// OrdersFromPartner starts again inside R1's 60 seconds: the copies complete
	Set used = ..SecondsSince(resentAt)
	Do ..Timing("DW-399: OrdersFromPartner is started again "_used_" seconds after R1's ResentAt (the most allowed: "_..#MARGIN_"; R1's wait: "_##class(OcuTalon.Fix.Executor).#WAITSECONDS_")")
	Do $$$AssertTrue(used '> ..#MARGIN, "the item is started again "_used_" seconds after R1's ResentAt, at most "_..#MARGIN_" seconds after it, so that the copies complete inside its "_##class(OcuTalon.Fix.Executor).#WAITSECONDS_" seconds")
	If used > ..#MARGIN Quit
	If '..TempStartItem("OrdersFromPartner") Quit
	Do $$$AssertTrue(..WaitCompleted(..#ORDERS, ..Joined(run.copies)), "the three copies complete")

	// a Tick inside the wait changes nothing
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set inside = ..SecondsSince(resentAt)
	Do ..Timing("DW-399: the Tick inside the wait came "_inside_" seconds after R1's ResentAt (the wait: "_##class(OcuTalon.Fix.Executor).#WAITSECONDS_")")
	Do $$$AssertTrue(inside < ##class(OcuTalon.Fix.Executor).#WAITSECONDS, "that Tick came "_inside_" seconds after R1's ResentAt, inside its "_##class(OcuTalon.Fix.Executor).#WAITSECONDS_" seconds")
	If inside '< ##class(OcuTalon.Fix.Executor).#WAITSECONDS Quit
	Set run = ..RunOf(ref, refR)
	Do $$$AssertEquals(run.endedAt_"|"_..RequestState(ref, refR)_"|"_..FixResultsFor(refR).%Size(), "|executing|0", "it changed nothing: R1 is executing, with no EndedAt and no FixResult")

	// a Tick after ResentAt + 60 seconds ends the run
	While ..SecondsSince(resentAt) '> ##class(OcuTalon.Fix.Executor).#WAITSECONDS {
		Hang 1
	}
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Set results = ..WaitFixResults(refR, 1)
	Do $$$AssertEquals(results.%Size(), 1, "exactly one FixResult for R1 exists, from any sender in any session")
	If results.%Size() '= 1 Quit
	Set sent = results.%Get(0)
	Do $$$AssertEquals(sent.source_"|"_sent.target_"|"_sent.sessionId_"|"_sent.superSession, "Checks|IncidentManager|"_trace_"|"_request.traceRef, "Checks sent it to IncidentManager, in the incident's trace session with R1's TraceRef")
	Do $$$AssertEquals(sent.incidentRef_"|"_sent.final_"|"_sent.interrupted, ref_"|1|0", "it names the incident, is final and is not interrupted")
	Do $$$AssertEquals(sent.total_"|"_sent.resent_"|"_sent.completed_"|"_sent.failedAgain_"|"_sent.skipped_"|"_sent.reason, "3|3|3|0|0|", "with the counts 3/3/3/0/0 and no reason")
	Do $$$AssertEquals(..WaitState(ref, refR, "done", ..#WAITEND), "done", "R1 is done")
	Set closed = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(refR)
	Do $$$AssertEquals(closed.State_"|"_closed.Result_"|"_(closed.FinishedAt '= ""), "done|done|1", "with the Result done and a FinishedAt")
	Kill closed
	Set run = ..RunOf(ref, refR)
	Do $$$AssertEquals((run.endedAt '= "")_"|"_run.total_"|"_run.resent_"|"_run.completed_"|"_run.failedAgain_"|"_run.skipped_"|"_run.interrupted_"|"_run.reason, "1|3|3|3|0|0|0|", "its FixRun has an EndedAt and holds 3/3/3/0/0 with Interrupted 0")
	Do $$$AssertEquals(..WaitIncidentState(ref, "resolved"), "resolved", "the incident is resolved")
	Set notes = ..WaitResultNotices(ref, 1)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one result Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.catalogKey_"|"_note.approvalRef_"|"_note.slots.count, "result.allThrough|"_refR_"|3", "result.allThrough with R1's Ref and count 3")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc), "All 3 orders went through.", "which renders as the UX document has it")
	}
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(auditMark, "OcuTalon", "Action", "", refR, "", 1, 20)
	Do $$$AssertEquals(entries.%Size(), 1, "the audit log holds one OcuTalon Action entry for R1")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.result_"|"_entries.%Get(0).data.counts.%ToJSON(), "done|{""total"":3,""resent"":3,""completed"":3,""failedAgain"":0,""skipped"":0}", "with the result done and the counts")

	// a further Tick gives nothing
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	Do ..RealTick()
	Hang 2
	Do $$$AssertEquals(..FixResultsFor(refR).%Size(), 1, "more Ticks send no second FixResult")
	Do $$$AssertEquals(..NoticeBodies(ref, "result").%Size(), 1, "and make no second Notification")
}

/// Makes a measured value visible in the output of a run that passes (DW-399): a log message, and an assert of the status skipped, which ci/iris.sh prints as "SKIP <method>: <text>".
/// It does not set SkipTest, so the rest of the test runs.
Method Timing(text As %String) [ Private ]
{
	Do $$$LogMessage(text)
	Do ..Manager.LogAssert(2, "Timing", text)
}

/// 1 when no job holds FixExecutor's wait lock (^OcuTalon.Fix.Wait): this process takes it at once and lets go; with seconds above 0 it tries again every tenth of a second until then.
Method WaitLockFree(seconds As %Integer) As %Boolean [ Private ]
{
	Set end = $ZHorolog + seconds
	For {
		Lock +^OcuTalon.Fix.Wait:0
		Set free = $Test
		If free {
			Lock -^OcuTalon.Fix.Wait
			Quit
		}
		If $ZHorolog '< end Quit
		Hang 0.1
	}
	Quit free
}

}
