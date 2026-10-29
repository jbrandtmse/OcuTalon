Include Ensemble

/// Tests of the runs of approved fixes (Stories 7.3 and 7.4; AD-3, AD-11, AD-15, AD-16, AD-26, AD-32). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh
/// (IncidentManager and FixExecutor are code of the running production, so a warm stack's jobs keep their old code), with demo mode on, through Test.Watch.Case: real
/// failed orders of OCUORDERS, the CI mock as the model, the real FixExecutor dry run, the real Approval.Raise and Approval.Answer, the real hold, IncidentManager and
/// FixExecutor. They fail with the reason where the production, OCUORDERS, demo mode or the ANSWERER account's role is missing. A test waits at most 90 seconds for a
/// diagnosis, WAITLATER for a later request, WAITRUN seconds for a run and 20 for the rest (test bounds, not NFR-7). The incidents, requests, holds, tasks and runs of a
/// test, and every message it made in OCUORDERS, are removed after it.
///   - TestTwoApprovedRequestsRunOneEach (AC 8, U-134; the matrix row "Two requests"): session S's incident awaits approval with R1 over three failed orders and R2 over
///     two later failures, and R1's bodies in OCUORDERS have been rewritten to the target format, so that none of them passes the re-check. Both are approved, one
///     after the other. Each request has its own FixRun and runs once, one at a time: R1's FixResult comes before R2's single Execute in the trace session; R1's
///     FixResult and its result.skipped Notification carry R1's Ref and R1's counts (Total 3, Skipped 3, nothing resent), R1 is done; R2 takes its targets from its
///     own row only, so its FixRun's Copies are copies of R2's two orders and none of R1's, and R2 ends with its own FixResult (2/2/2/0/0) and its own
///     result.allThrough Notification, after which the incident is resolved (Story 7.4);
///   - TestTwoResentRunsHaveTheirOwnResults (AC 7, U-140; the matrix row "Two resent runs"): R1 is over three failed orders, one of them rewritten to the target
///     format, and R2 over two later failures. Both are approved. R1's FixResult (3/2/2/0/1) comes before R2's single Execute and the incident stays fixing in between
///     (an incident event lists R1 done with its result and R2 not done); R2's is 2/2/2/0/0 and the incident is then resolved. S gets R1's result.skipped (2 of 3) and
///     R2's result.allThrough (2) Notification. Each run's Copies are copies of its own targets only, the two sets share none, and each request's FixRun, Action entry
///     and last incident event carry its own counts;
///   - TestStoppedProductionSkipsEveryCopy (AC 7, V4; the matrix row "Production stopped"): the Orders production is stopped when R1 is approved. The re-check still
///     reads the stopped production, and every copy is skipped with the plain reason that the production isn't running, because Ens.MessageHeader refuses with
///     ErrProductionNotRunning: no header is made, the FixRun holds no copies, R1 is done, the FixResult has Total 3, Skipped 3 and nothing resent, and the one result
///     Notification is result.skipped, whose text says the orders had changed since the dry run (V4: AD-16 counts a refused copy as skipped, the convention picks that
///     key, and no text of its own exists for a stopped production yet).
Class OcuTalon.Test.Fix.Runs Extends OcuTalon.Test.Watch.Case
{

Parameter REPAIRED = "2026-10-16";

Method TestTwoApprovedRequestsRunOneEach()
{
	If '..RaisedTwo("two", .a, .ref, .r1, .r2) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row
	Do $$$AssertEquals($Length(r1.fixTargets, ",")_"|"_$Length(r2.fixTargets, ","), "3|2", "R1 has three targets and R2 two")
	Do $$$AssertEquals(..Shared(r1.fixTargets, r2.fixTargets), "", "which share no order")
	For i = 1:1:$Length(r1.fixTargets, ",") {
		Do $$$AssertStatusOK(..SetOrderDate($Piece(r1.fixTargets, ",", i), ..#REPAIRED), "R1's order "_$Piece(r1.fixTargets, ",", i)_" is written in the target format")
	}

	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(r1.ref, "approve", "web", ..#ANSWERER, a, .winner), "done", "R1 is approved")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(r2.ref, "approve", "web", ..#ANSWERER, a, .winner), "done", "and so is R2")

	// R2 registers its copies when R1 has ended
	Set run2 = ..WaitRun(ref, r2.ref, 2)
	Do $$$AssertTrue($IsObject(run2) && (run2.copies.%Size() = 2), "R2's FixRun holds two copies")
	Set runs = ..Runs(ref)
	Do $$$AssertEquals(runs.%Size(), 2, "the incident has two FixRun rows")
	Set run1 = ..RunOf(ref, r1.ref)
	Do $$$AssertTrue($IsObject(run1) && $IsObject(run2) && (run1.id '= run2.id), "one for R1 and one for R2")
	If '$IsObject(run1) || '$IsObject(run2) || (run2.copies.%Size() '= 2) Quit
	Do $$$AssertEquals(run1.approvalRef_"|"_run1.incidentRef_"|"_run1.copies.%Size(), r1.ref_"|"_ref_"|0", "R1's run names R1 and has no copies")
	Do $$$AssertEquals(run2.approvalRef_"|"_run2.incidentRef, r2.ref_"|"_ref, "R2's run names R2")
	Do $$$AssertEquals(..WaitState(ref, r1.ref, "done"), "done", "R1 is done")
	Do $$$AssertEquals(..WaitState(ref, r2.ref, "done", 90), "done", "and so is R2, once its copies are counted")

	// R2's copies are copies of R2's orders only
	Set seen = ""
	For i = 0:1:1 {
		Set copy = ..Header(..#ORDERS, run2.copies.%Get(i))
		Do $$$AssertTrue($IsObject(copy), "R2's copy "_(i + 1)_" exists")
		If '$IsObject(copy) Continue
		Set original = +$Piece(copy.description, " ", 2)
		Set seen = seen _ $Select(seen = "": "", 1: ",") _ original
		Do $$$AssertEquals($Piece(copy.description, " ", 1), "Resent", "its description says it was resent")
		Do $$$AssertEquals(copy.body.OrderDate, ..#REPAIRED, "its OrderDate is repaired")
	}
	Do $$$AssertEquals(seen, r2.fixTargets, "the copies are of R2's two orders, in order, and of none of R1's")

	// the results: R1's own Ref and counts before R2's single Execute, then R2's
	Set results = ..FixResultsOf(trace, 2)
	Set found = ""
	Set foundTwo = ""
	For i = 0:1:results.%Size() - 1 {
		If $IsObject(results.%Get(i)) && (results.%Get(i).ApprovalRef = r1.ref) Set found = found _ $ListBuild(i)
		If $IsObject(results.%Get(i)) && (results.%Get(i).ApprovalRef = r2.ref) Set foundTwo = foundTwo _ $ListBuild(i)
	}
	Do $$$AssertEquals($ListLength(found)_"|"_$ListLength(foundTwo), "1|1", "one FixResult is R1's and one is R2's")
	Do $$$AssertEquals(results.%Size(), 2, "and they are the only two")
	If $ListLength(found) = 1 {
		Set result = results.%Get($List(found, 1))
		Do $$$AssertEquals(result.ApprovalRef_"|"_result.IncidentRef_"|"_result.Final_"|"_result.Interrupted, r1.ref_"|"_ref_"|1|0", "R1's FixResult names R1 and the incident and is final")
		Do $$$AssertEquals(result.Total_"|"_result.Resent_"|"_result.Completed_"|"_result.FailedAgain_"|"_result.Skipped, "3|0|0|0|3", "with Total 3, nothing resent and 3 skipped")
		Do $$$AssertTrue($Find(result.Reason, "message "_$Piece(r1.fixTargets, ",", 1)) > 0, "and the reason of the lowest order: "_result.Reason)
	}
	If $ListLength(foundTwo) = 1 {
		Set result = results.%Get($List(foundTwo, 1))
		Do $$$AssertEquals(result.ApprovalRef_"|"_result.IncidentRef_"|"_result.Final_"|"_result.Interrupted, r2.ref_"|"_ref_"|1|0", "R2's FixResult names R2 and the incident and is final")
		Do $$$AssertEquals(result.Total_"|"_result.Resent_"|"_result.Completed_"|"_result.FailedAgain_"|"_result.Skipped, "2|2|2|0|0", "with its own counts, 2, 2, 2, 0 and 0")
	}
	Set executes1 = ..ExecutesOf(trace, r1.ref, ..#WAITINCIDENT)
	Set executes2 = ..ExecutesOf(trace, r2.ref, ..#WAITINCIDENT)
	Do $$$AssertEquals(executes1.%Size()_"|"_executes2.%Size(), "1|1", "each request had one Execute")
	Do $$$AssertEquals(..HeadersBetween(trace, 1, "IncidentManager", "FixExecutor", "OcuTalon.Fix.Msg.Execute"), 2, "and there were two in all")
	If $ListLength(found) = 1 && (executes2.%Size() = 1) {
		Set resultHeader = ..ResultHeaderOf(trace, r1.ref)
		Do $$$AssertTrue(+resultHeader '= 0 && (+resultHeader < +executes2.%Get(0).id), "R1's FixResult (header "_resultHeader_") comes before R2's Execute (header "_executes2.%Get(0).id_") in the trace session")
	}

	// the notices: R1's skipped result and R2's, and then the incident is resolved
	Set end = $ZHorolog + ..#WAITHOLD
	For {
		Set notes = ..NoticeBodies(ref, "result")
		If (notes.%Size() '< 2) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(notes.%Size(), 2, "S has two result Notifications")
	If notes.%Size() = 2 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef_"|"_note.incidentRef_"|"_note.sessionRef_"|"_note.decisionRef, "result|result.skipped|"_r1.ref_"|"_ref_"|"_a_"|", "the first is result.skipped with R1's Ref")
		Do $$$AssertEquals(note.slots.count_"|"_note.slots.completed_"|"_note.slots.skipped_"|"_note.slots.itemNoun.other, "3|0|3|orders", "and R1's counts: "_note.slots.%ToJSON())
		Set text = ##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc)
		Do $$$AssertEquals(text, "0 of 3 orders went through. 3 had changed since the dry run, so I skipped them; they need a new approval.", "which renders as the UX document has it")
		Do ..AssertDelivered(a, "result", r1.ref)
		Set note = notes.%Get(1)
		Do $$$AssertEquals(note.catalogKey_"|"_note.approvalRef_"|"_note.incidentRef, "result.allThrough|"_r2.ref_"|"_ref, "the second is result.allThrough with R2's Ref")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc), "All 2 orders went through.", "and renders as All 2 orders went through.")
	}
	Do $$$AssertEquals(..WaitIncidentState(ref, "resolved"), "resolved", "the incident is resolved: R2 has ended too")
}

Method TestTwoResentRunsHaveTheirOwnResults()
{
	If '..RaisedTwo("own", .a, .ref, .r1, .r2) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row
	Do $$$AssertEquals($Length(r1.fixTargets, ",")_"|"_$Length(r2.fixTargets, ","), "3|2", "R1 has three targets and R2 two")
	Do $$$AssertEquals(..Shared(r1.fixTargets, r2.fixTargets), "", "which share no order")
	Set rewritten = $Piece(r1.fixTargets, ",", 2)
	Do $$$AssertStatusOK(..SetOrderDate(rewritten, ..#REPAIRED), "R1's second order "_rewritten_" is written in the target format")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(r1.ref, "approve", "web", ..#ANSWERER, a, .winner), "done", "R1 is approved")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(r2.ref, "approve", "web", ..#ANSWERER, a, .winner), "done", "and so is R2")
	Do $$$AssertEquals(..WaitState(ref, r1.ref, "done", 90), "done", "R1 is done")
	Do $$$AssertEquals(..WaitState(ref, r2.ref, "done", 90), "done", "and so is R2")
	Do $$$AssertEquals(..WaitIncidentState(ref, "resolved"), "resolved", "the incident is resolved")

	// each run has its own copies and counts
	Set run1 = ..RunOf(ref, r1.ref)
	Set run2 = ..RunOf(ref, r2.ref)
	Do $$$AssertTrue($IsObject(run1) && $IsObject(run2) && (run1.id '= run2.id), "each request has a FixRun of its own")
	If '$IsObject(run1) || '$IsObject(run2) Quit
	Do $$$AssertEquals(run1.copies.%Size()_"|"_run2.copies.%Size(), "2|2", "R1's run holds two copies and R2's two")
	Do $$$AssertEquals(..Shared(..Joined(run1.copies), ..Joined(run2.copies)), "", "and the two sets share no copy")
	Do $$$AssertEquals(..Originals(run1.copies), $Piece(r1.fixTargets, ",", 1)_","_$Piece(r1.fixTargets, ",", 3), "R1's copies are copies of its first and third order, not of the rewritten one")
	Do $$$AssertEquals(..Originals(run2.copies), r2.fixTargets, "and R2's of its own two orders")
	Do $$$AssertEquals(run1.total_"|"_run1.resent_"|"_run1.completed_"|"_run1.failedAgain_"|"_run1.skipped_"|"_run1.interrupted_"|"_run1.reason, "3|2|2|0|1|0|", "R1's run stores 3/2/2/0/1, interrupted 0 and no reason")
	Do $$$AssertEquals(run2.total_"|"_run2.resent_"|"_run2.completed_"|"_run2.failedAgain_"|"_run2.skipped_"|"_run2.interrupted_"|"_run2.reason, "2|2|2|0|0|0|", "and R2's 2/2/2/0/0")
	Do $$$AssertTrue((run1.resentAt '= "") && (run1.endedAt '= "") && (run2.resentAt '= "") && (run2.endedAt '= ""), "both runs have a ResentAt and an EndedAt")

	// the FixResults: R1's before R2's Execute, each with its own counts
	Set results = ..FixResultsOf(trace, 2)
	Do $$$AssertEquals(results.%Size(), 2, "two FixResults went to IncidentManager")
	For i = 0:1:results.%Size() - 1 {
		Set result = results.%Get(i)
		If result.ApprovalRef = r1.ref {
			Do $$$AssertEquals(result.Total_"|"_result.Resent_"|"_result.Completed_"|"_result.FailedAgain_"|"_result.Skipped_"|"_result.Final, "3|2|2|0|1|1", "R1's FixResult is 3/2/2/0/1 and final")
		} ElseIf result.ApprovalRef = r2.ref {
			Do $$$AssertEquals(result.Total_"|"_result.Resent_"|"_result.Completed_"|"_result.FailedAgain_"|"_result.Skipped_"|"_result.Final, "2|2|2|0|0|1", "R2's FixResult is 2/2/2/0/0 and final")
		} Else {
			Do $$$AssertTrue(0, "a FixResult of no request of the incident: "_result.ApprovalRef)
		}
	}
	Set executes2 = ..ExecutesOf(trace, r2.ref, ..#WAITINCIDENT)
	Do $$$AssertEquals(executes2.%Size(), 1, "R2 had one Execute")
	Set resultHeader = ..ResultHeaderOf(trace, r1.ref)
	If executes2.%Size() = 1 Do $$$AssertTrue(+resultHeader '= 0 && (+resultHeader < +executes2.%Get(0).id), "R1's FixResult (header "_resultHeader_") comes before R2's Execute (header "_executes2.%Get(0).id_")")

	// the incident stayed fixing between the two results
	Set between = 0
	Set events = ..Stream(a)
	For i = 0:1:events.%Size() - 1 {
		Set event = events.%Get(i)
		If (event.type = "incident") && (event.payload.ref = ref) && (..ResultOf(event.payload, 0) = "3|2|2|0|1|0|") && (..ResultOf(event.payload, 1) = "none") Set between = between + (event.payload.state = "fixing")
	}
	Do $$$AssertTrue(between > 0, "an incident event lists R1 done with its result and R2 without one, and the incident fixing")

	// the notices
	Set end = $ZHorolog + ..#WAITHOLD
	For {
		Set notes = ..NoticeBodies(ref, "result")
		If (notes.%Size() '< 2) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(notes.%Size(), 2, "S has two result Notifications")
	For i = 0:1:notes.%Size() - 1 {
		Set note = notes.%Get(i)
		Set text = ##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc)
		If note.approvalRef = r1.ref {
			Do $$$AssertEquals(note.catalogKey_"|"_text, "result.skipped|2 of 3 orders went through. 1 had changed since the dry run, so I skipped it; it needs a new approval.", "R1's is result.skipped, 2 of 3")
		} ElseIf note.approvalRef = r2.ref {
			Do $$$AssertEquals(note.catalogKey_"|"_text, "result.allThrough|All 2 orders went through.", "R2's is result.allThrough, 2")
		} Else {
			Do $$$AssertTrue(0, "a result Notification of no request of the incident: "_note.approvalRef)
		}
	}

	// the entries of the audit log, and the last event
	Set entries1 = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "", r1.ref)
	Set entries2 = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "", r2.ref)
	Do $$$AssertEquals(entries1.%Size()_"|"_entries2.%Size(), "1|1", "each request has one Action entry")
	If (entries1.%Size() = 1) && (entries2.%Size() = 1) {
		Do $$$AssertEquals(entries1.%Get(0).data.counts.%ToJSON(), "{""total"":3,""resent"":2,""completed"":2,""failedAgain"":0,""skipped"":1}", "R1's entry has R1's counts")
		Do $$$AssertEquals(entries2.%Get(0).data.counts.%ToJSON(), "{""total"":2,""resent"":2,""completed"":2,""failedAgain"":0,""skipped"":0}", "and R2's entry R2's")
	}
	Set last = ..LastIncident(a, ref)
	Do $$$AssertTrue($IsObject(last), "the incident event is on S's stream")
	If $IsObject(last) Do $$$AssertEquals(..ResultOf(last, 0)_"#"_..ResultOf(last, 1), "3|2|2|0|1|0|#2|2|2|0|0|0|", "the last one lists each request with its own result")
}

Method TestStoppedProductionSkipsEveryCopy()
{
	If '..Raised("stopped", .a, .ref, .request) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row
	Set originals = ..Failed(..OrdersFloor)
	Set namespaces = $ListBuild(..#ORDERS)
	If '..StopOrders() Quit
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .before)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(request.ref, "approve", "web", ..#ANSWERER, a, .winner), "done", "R1 is approved while the Orders production is stopped")

	Set results = ..FixResultsOf(trace, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.ApprovalRef_"|"_result.IncidentRef_"|"_result.Final_"|"_result.Interrupted, request.ref_"|"_ref_"|1|0", "it names R1 and the incident and is final")
		Do $$$AssertEquals(result.Total_"|"_result.Resent_"|"_result.Completed_"|"_result.FailedAgain_"|"_result.Skipped, "3|0|0|0|3", "with Total 3, nothing resent and 3 skipped")
		Do $$$AssertTrue($Find(result.Reason, "message "_originals.%Get(0).id) > 0, "the reason names the lowest order: "_result.Reason)
		Do $$$AssertTrue($Find(result.Reason, "the production isn't running") > 0, "and says that the production isn't running")
	}
	Do $$$AssertEquals(..WaitState(ref, request.ref, "done"), "done", "R1 is done")
	Set run = ..RunOf(ref, request.ref)
	Do $$$AssertTrue($IsObject(run), "R1 has a FixRun")
	If $IsObject(run) Do $$$AssertEquals(run.copies.%Size(), 0, "which holds no copy")
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
		Do $$$AssertEquals(note.catalogKey_"|"_note.approvalRef, "result.skipped|"_request.ref, "it is result.skipped with R1's Ref (V4: no text of its own for a stopped production)")
		Do $$$AssertEquals(note.slots.count_"|"_note.slots.completed_"|"_note.slots.skipped, "3|0|3", "and counts 3 skipped of 3")
	}
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .after)
	Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(before, after)
	Do $$$AssertEquals(lines.%Size(), 0, "no header was made and nothing in OCUORDERS changed: "_lines.%ToJSON())
}

/// --- helpers ---
/// The id of the header that carried the FixResult of the request from FixExecutor to IncidentManager in the trace session, "" when there is none.
Method ResultHeaderOf(trace As %String, approvalRef As %String) As %String [ Private ]
{
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(trace), 1, ..#EXECUTOR, ..#MANAGER)
	For i = 0:1:sent.%Size() - 1 {
		If sent.%Get(i).bodyClass '= "OcuTalon.Fix.Msg.FixResult" Continue
		Set body = ##class(OcuTalon.Fix.Msg.FixResult).%OpenId(sent.%Get(i).bodyId)
		If $IsObject(body) && (body.ApprovalRef = approvalRef) Return sent.%Get(i).id
	}
	Quit ""
}

/// The ids that both lists (comma-separated) hold, comma-separated, in the order of the first; "" when they share none.
ClassMethod Shared(one As %String, two As %String) As %String [ Private ]
{
	Set shared = ""
	For i = 1:1:$Length(one, ",") {
		Set id = $Piece(one, ",", i)
		If (id '= "") && $ListFind($ListFromString(two), id) Set shared = shared_$Select(shared = "": "", 1: ",")_id
	}
	Quit shared
}

}
