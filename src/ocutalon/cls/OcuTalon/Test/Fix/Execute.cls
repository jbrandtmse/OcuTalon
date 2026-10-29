Include Ensemble

/// Tests of an approved fix that is carried out (Story 7.3; AD-3, AD-11, AD-15, AD-16, AD-22, AD-26, AD-32). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh
/// (IncidentManager and FixExecutor are code of the running production, so a warm stack's jobs keep their old code), with demo mode on, through Test.Watch.Case: real
/// failed orders of OCUORDERS, the CI mock as the model (its diagnosis scenario, a data-format change with the fix repair_resend), the real FixExecutor dry run, the real
/// Approval.Raise and Approval.Answer and the real hold, IncidentManager and FixExecutor. They fail with the reason where the production, OCUORDERS, demo mode or the
/// ANSWERER account's role is missing. A test waits at most 90 seconds for a diagnosis, WAITRUN seconds for a run to register its copies, WAITCOPY seconds for the copies
/// to complete and 20 for the rest (test bounds, not NFR-7). The incidents, requests, holds, tasks and runs of a test, and every message it made in OCUORDERS (the
/// copies included), are removed after it.
///   - TestApprovedRepairsAreResent (AC 1, AC 3, AC 7; Integration; the matrix rows "Approved" and "Second Execute"): session S's incident awaits approval with R1
///     over three failed orders dated 10/16/2026, and the ANSWERER account approves it. At once the incident is fixing; S gets one answered.approved Notification
///     (channel web, time AnsweredAt, R1's Ref and the incident's, no decision) in the incident's trace session, which renders as "Approved from the web chat at ...",
///     and WebChatOut records its answered Delivery row with R1's Ref; one Execute that carries only R1's Ref goes from IncidentManager to FixExecutor in the trace
///     session. Then R1 is executing and has one FixRun (R1, the incident, a start) whose Copies are three new header ids; each copy is in its original's
///     session with its SuperSession, its Description is "Resent <original>", its body is of its original's class with a body of its own, its OrderDate is
///     2026-10-16 and its other fields are equal, and it completes; the originals and their bodies are unchanged (a snapshot of OCUORDERS differs in no line but the
///     copies' sessions' new messages), there is no FixResult and no result Notification yet (the end of a run that resent copies is Story 7.4's), the incident is
///     still fixing and the mock logged no request. A second Execute for R1, sent to the real item, is refused: one info line, still one FixRun and three copies,
///     and nothing new in OCUORDERS;
///   - TestCouldNotStart (AC 5; Integration; the matrix row "No resources"): the service role no longer holds %Ens_MessageResend when R1 is approved. One FixRun with
///     no copies; R1 is failed (Result failed); one FixResult goes from FixExecutor to IncidentManager in the trace session (R1, the incident, Final 1, Total 3, every
///     other count 0, the reason "OcuTalon isn't allowed to resend messages in that production"); the incident is resolved; S has one result.couldNotStart
///     Notification with R1's Ref that renders "Nothing was resent: OcuTalon isn't allowed to resend messages in that production. Nothing was changed." and WebChatOut
///     records its result Delivery row; and OCUORDERS did not change.
Class OcuTalon.Test.Fix.Execute Extends OcuTalon.Test.Watch.Case
{

/// The date the repair writes, and the order fields that the copies keep.
Parameter REPAIRED = "2026-10-16";

Parameter KEPT = "OrderNumber,Sku,Quantity";

Method TestApprovedRepairsAreResent()
{
	If '..Raised("run", .a, .ref, .request) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row
	Set originals = ..Failed(..OrdersFloor)
	Set ids = ..HeaderIds(originals)
	Do $$$AssertEquals(request.fixTargets, ids, "R1's targets are the three failed orders")
	Set sessions = ""
	For i = 0:1:originals.%Size() - 1 {
		Set sessions = sessions _ $Select(sessions = "": "", 1: ",") _ originals.%Get(i).sessionId
	}
	Set namespaces = $ListBuild(..#ORDERS)
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .before)
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Do $$$AssertTrue(mark > 0, "the mock's request log is read and holds the diagnosis, so a log with no request since means something")
	Set done = ##class(OcuTalon.Bridge.Approval).Answer(request.ref, "approve", "web", ..#ANSWERER, a, .winner)
	Do $$$AssertEquals(done, "done", "the approval is accepted")

	// at once: the notice, the state and the order
	Set answered = ..Answered(ref, 1)
	If $IsObject(answered) {
		Set after = ..Requests(ref).%Get(0)
		Do $$$AssertEquals(answered.kind_"|"_answered.catalogKey_"|"_answered.approvalRef_"|"_answered.incidentRef_"|"_answered.sessionRef_"|"_answered.decisionRef, "answered|answered.approved|"_request.ref_"|"_ref_"|"_a_"|", "one answered notification: the key, the request's Ref, the incident's and no decision")
		Do $$$AssertEquals(answered.slots.channel_"|"_answered.slots.time, "web|"_after.answeredAt, "with the channel and the time of the answer")
		Set text = ##class(OcuTalon.Msg.Catalog).Render(answered.catalogKey, answered.slots.%ToJSON(), "phone", .sc)
		Do $$$AssertStatusOK(sc, "it renders")
		Do $$$AssertTrue(($Extract(text, 1, 30) = "Approved from the web chat at ") && ($Extract(text, *) = "."), "as Approved from the web chat at the time: "_text)
		Do $$$AssertEquals(..NoticeSessionOf(answered.id), trace, "in the incident's trace session")
		Do ..AssertDelivered(a, "answered", request.ref)
	}
	Set sent = ..ExecutesOf(trace, request.ref, ..#WAITINCIDENT)
	Do $$$AssertEquals(sent.%Size(), 1, "one Execute that carries R1's Ref goes from IncidentManager to FixExecutor in the trace session")
	Set executes = ..HeadersBetween(trace, 1, "IncidentManager", "FixExecutor", "OcuTalon.Fix.Msg.Execute")
	Do $$$AssertEquals(executes, 1, "and it is the only one")

	// then: the run
	Set run = ..WaitRun(ref, request.ref, 3)
	Do $$$AssertTrue($IsObject(run) && (run.copies.%Size() = 3), "R1's FixRun holds three copies")
	If '$IsObject(run) || (run.copies.%Size() '= 3) Quit
	Do $$$AssertEquals(..Runs(ref).%Size(), 1, "and it is the only FixRun of the incident")
	Do $$$AssertEquals(run.approvalRef_"|"_run.incidentRef_"|"_(run.startedAt '= ""), request.ref_"|"_ref_"|1", "it names R1 and the incident and has a start")
	Do $$$AssertEquals(..Requests(ref).%Get(0).state, "executing", "R1 is executing")
	Set copies = ""
	For i = 0:1:2 {
		Set copies = copies _ $Select(copies = "": "", 1: ",") _ run.copies.%Get(i)
	}
	Set completed = ..WaitCompleted(..#ORDERS, copies)
	Do $$$AssertTrue(completed, "the three copies complete")
	For i = 0:1:2 {
		Set original = ..Header(..#ORDERS, originals.%Get(i).id)
		Set copy = ..Header(..#ORDERS, run.copies.%Get(i))
		Do $$$AssertTrue($IsObject(copy), "copy "_(i + 1)_" exists")
		If '$IsObject(copy) Continue
		Do $$$AssertEquals(copy.sessionId_"|"_copy.superSession, original.sessionId_"|"_original.superSession, "copy "_(i + 1)_" is in its original's session with its SuperSession")
		Do $$$AssertEquals(copy.description, "Resent "_original.id, "its description names the original")
		Do $$$AssertEquals(copy.bodyClass_"|"_(copy.bodyId '= original.bodyId), original.bodyClass_"|1", "its body is of the original's class and is a body of its own")
		Do $$$AssertEquals(copy.body.OrderDate_"|"_original.body.OrderDate, ..#REPAIRED_"|10/16/2026", "its OrderDate is repaired and the original's is not")
		Do $$$AssertEquals(copy.status, $$$eMessageStatusCompleted, "it completes")
		For field = 1:1:$Length(..#KEPT, ",") {
			Set name = $Piece(..#KEPT, ",", field)
			Do $$$AssertEquals(copy.body.%Get(name), original.body.%Get(name), "its "_name_" is the original's")
		}
		Do $$$AssertEquals(original.status, $$$eMessageStatusError, "the original is still in the error status")
	}
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .afterRun)
	Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(before, afterRun, sessions, ..#ORDERS)
	Do $$$AssertEquals(lines.%Size(), 0, "OCUORDERS changed in no header but the new messages of the originals' sessions: "_lines.%ToJSON())

	// nothing is told of the end: the copies are not counted yet
	Do $$$AssertEquals(..HeadersBetween(trace, 1, "FixExecutor", "IncidentManager", "OcuTalon.Fix.Msg.FixResult"), 0, "no FixResult has gone to IncidentManager")
	Do $$$AssertEquals(..NoticeBodies(ref, "result").%Size(), 0, "and S has no result Notification")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant, "fixing|", "the incident is still fixing")
	Kill row
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's request log is read")
	Set posts = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.path = "/v1/messages") Set posts = posts + 1
	}
	Do $$$AssertEquals(posts, 0, "the mock logged no request during the run")

	// a second Execute for R1 is refused
	Set logMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do $$$AssertStatusOK(..SendExecute(request.ref), "a second Execute for R1 is handled")
	Set again = ..Runs(ref)
	Do $$$AssertEquals(again.%Size()_"|"_again.%Get(0).copies.%ToJSON(), "1|"_run.copies.%ToJSON(), "it is refused: still one FixRun with the same three copies")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", logMark, $Parameter("OcuTalon.Fix.Executor", "LOGREFUSED")_request.ref)
	Do rs.%Next()
	Do $$$AssertEquals(+rs.%GetData(1), 1, "and one info line names the request")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", logMark, $Parameter("OcuTalon.Fix.Executor", "LOGREFUSED")_request.ref)
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .afterTwo)
	Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(afterRun, afterTwo)
	Do $$$AssertEquals(lines.%Size(), 0, "nothing new is in OCUORDERS: "_lines.%ToJSON())
}

Method TestCouldNotStart()
{
	If '..Raised("nores", .a, .ref, .request) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row
	Set namespaces = $ListBuild(..#ORDERS)
	Do ..RevokeRole("%Ens_MessageResend")
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .before)
	Set done = ##class(OcuTalon.Bridge.Approval).Answer(request.ref, "approve", "web", ..#ANSWERER, a, .winner)
	Do $$$AssertEquals(done, "done", "the approval is accepted")

	Set state = ..WaitState(ref, request.ref, "failed")
	Do $$$AssertEquals(state, "failed", "R1 is closed failed")
	Set closed = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request.ref)
	Do $$$AssertEquals(closed.State_"|"_closed.Result_"|"_(closed.FinishedAt '= ""), "failed|failed|1", "with the Result failed and a FinishedAt")
	Kill closed
	Set runs = ..Runs(ref)
	Do $$$AssertEquals(runs.%Size(), 1, "one FixRun is written")
	If runs.%Size() = 1 Do $$$AssertEquals(runs.%Get(0).approvalRef_"|"_runs.%Get(0).copies.%Size(), request.ref_"|0", "for R1, with no copies")
	Set results = ..FixResultsOf(trace, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes from FixExecutor to IncidentManager in the trace session")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.ApprovalRef_"|"_result.IncidentRef_"|"_result.Final_"|"_result.Interrupted, request.ref_"|"_ref_"|1|0", "it names R1 and the incident and is final")
		Do $$$AssertEquals(result.Total_"|"_result.Resent_"|"_result.Completed_"|"_result.FailedAgain_"|"_result.Skipped, "3|0|0|0|0", "with Total 3 and every other count 0")
		Do $$$AssertEquals(result.Reason, "OcuTalon isn't allowed to resend messages in that production", "and the plain reason")
	}
	Do $$$AssertEquals(..WaitIncidentState(ref, "resolved"), "resolved", "the incident is resolved")
	Set end = $ZHorolog + ..#WAITHOLD
	For {
		Set notes = ..NoticeBodies(ref, "result")
		If (notes.%Size() '< 1) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(notes.%Size(), 1, "S has one result Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef_"|"_note.incidentRef_"|"_note.sessionRef_"|"_note.decisionRef, "result|result.couldNotStart|"_request.ref_"|"_ref_"|"_a_"|", "of the key couldNotStart, with R1's Ref, the incident's and no decision")
		Set text = ##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc)
		Do $$$AssertStatusOK(sc, "it renders")
		Do $$$AssertEquals(text, "Nothing was resent: OcuTalon isn't allowed to resend messages in that production. Nothing was changed.", "as the UX document has it")
		Do $$$AssertEquals(..NoticeSessionOf(note.id), trace, "in the incident's trace session")
		Do ..AssertDelivered(a, "result", request.ref)
	}
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .afterRun)
	Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(before, afterRun)
	Do $$$AssertEquals(lines.%Size(), 0, "no copy was made and OCUORDERS did not change: "_lines.%ToJSON())
}

}
