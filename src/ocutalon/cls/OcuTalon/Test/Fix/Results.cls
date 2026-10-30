Include Ensemble

/// Tests of the end of an approved run that resent copies (Story 7.4; AD-12, AD-13, AD-15, AD-16, AD-17, AD-26, AD-32). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21), fresh (IncidentManager and FixExecutor are code of the running production, so a warm stack's jobs keep their old code), with demo mode on, through
/// Test.Watch.Case: real failed orders of OCUORDERS, the CI mock as the model (its diagnosis scenario, a data-format change with the fix repair_resend), the real
/// FixExecutor dry run, the real Approval.Raise and Approval.Answer, the real hold, IncidentManager and FixExecutor. They fail with the reason where the production,
/// OCUORDERS, demo mode or the ANSWERER account's role is missing. A test waits at most 90 seconds for a diagnosis or the end of a run, WAITRUN seconds for the copies
/// and 20 for the rest (test bounds, not NFR-7). The incidents, requests, holds, tasks and runs of a test, and every message it made in OCUORDERS (the copies
/// included), are removed after it.
///   - TestAllFiftyWentThrough (AC 1, AC 2, AC 5, AC 9; Integration; the matrix row "All went through"): session S's incident awaits approval with R1 over 50 failed
///     orders and the ANSWERER account approves it through Approval.Answer. R1's FixRun holds 50 copies, all Completed, and the stored result 50/50/50/0/0, Interrupted
///     0 and no reason, with a ResentAt and an EndedAt; R1 is done; one FixResult (R1, the incident, Final 1) goes to IncidentManager in the trace session and the
///     incident is resolved. S gets exactly one result Notification (result.allThrough, count 50, R1's Ref and the incident's) that renders "All 50 orders went
///     through.", and WebChatOut and SimPhoneOut (Task 0 (c)) record its result Delivery row. The last incident event and /state (Web.Api.StateBody) list R1 done with the
///     result {total 50, resent 50, completed 50, failedAgain 0, skipped 0, interrupted 0}, as numbers, and /state keeps its groups, evidence and trace targets. The
///     audit log holds one OcuTalon Action entry (the approver, S, web, repair_resend, the Orders production in OCUORDERS, done, the counts and R1's Ref, and no key,
///     token, password or chat identity) and IRIS's own Resend entry for each of the 50 copies (it names the copy's header id; Task 0 (d)); the mock logged no request;
///   - TestLaterRequestPendingAfterTheResult (AC 1; the matrix row "Later request pending"): R1 and R2 are pending over S's incident and only R1 is approved. After R1's
///     result (result.allThrough, 3) the incident is awaiting_approval, and its last event lists R1 done with its result and R2 pending with none.
Class OcuTalon.Test.Fix.Results Extends OcuTalon.Test.Watch.Case
{

/// The number of failed orders of the first test.
Parameter ORDERSCOUNT = 50;

/// The longest the end of a run is waited for, in seconds (a test bound, not NFR-7).
Parameter WAITEND = 90;

/// The words that no audit entry of the run may hold, in lower case (the entry holds no key, token, password or chat identity).
Parameter FORBIDDEN = "sk-ant,token,password,secret,telegram,chatid,chat id,bearer";

Method TestAllFiftyWentThrough()
{
	If '..Raised("fifty", .a, .ref, .request, ..#ORDERSCOUNT) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row
	Set originals = ..Failed(..OrdersFloor)
	Set ids = ..HeaderIds(originals)
	Do $$$AssertEquals(request.fixTargets, ids, "R1's targets are the "_..#ORDERSCOUNT_" failed orders")
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Do $$$AssertTrue(mark > 0, "the mock's request log is read")
	Set auditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(request.ref, "approve", "web", ..#ANSWERER, a, .winner), "done", "R1 is approved")

	// the run: 50 copies, all completed, counted
	Set run = ..WaitRun(ref, request.ref, ..#ORDERSCOUNT)
	Do $$$AssertTrue($IsObject(run) && (run.copies.%Size() = ..#ORDERSCOUNT), "R1's FixRun holds "_..#ORDERSCOUNT_" copies")
	If '$IsObject(run) || (run.copies.%Size() '= ..#ORDERSCOUNT) Quit
	Set copies = ..Joined(run.copies)
	Do $$$AssertEquals(..WaitState(ref, request.ref, "done", ..#WAITEND), "done", "R1 is done: its copies are counted")
	Do $$$AssertEquals(..CompletedCount(..#ORDERS, copies), ..#ORDERSCOUNT, "all "_..#ORDERSCOUNT_" copies are Completed")
	Set closed = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request.ref)
	Do $$$AssertEquals(closed.State_"|"_closed.Result_"|"_(closed.FinishedAt '= ""), "done|done|1", "R1 has the Result done and a FinishedAt")
	Kill closed
	Set run = ..RunOf(ref, request.ref)
	Do $$$AssertEquals(..Runs(ref).%Size(), 1, "the incident has one FixRun")
	Do $$$AssertEquals(run.total_"|"_run.resent_"|"_run.completed_"|"_run.failedAgain_"|"_run.skipped_"|"_run.interrupted_"|"_run.reason, "50|50|50|0|0|0|", "which stores the result 50/50/50/0/0, Interrupted 0 and no reason")
	Do $$$AssertTrue((run.startedAt '= "") && (run.resentAt '= "") && (run.endedAt '= "") && ('(run.resentAt ] run.endedAt)), "with a StartedAt, a ResentAt and an EndedAt that is not before it")

	// the FixResult and the incident
	Set results = ..FixResultsOf(trace, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes from FixExecutor to IncidentManager in the trace session")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.ApprovalRef_"|"_result.IncidentRef_"|"_result.Final_"|"_result.Interrupted, request.ref_"|"_ref_"|1|0", "it names R1 and the incident and is final")
		Do $$$AssertEquals(result.Total_"|"_result.Resent_"|"_result.Completed_"|"_result.FailedAgain_"|"_result.Skipped_"|"_result.Reason, "50|50|50|0|0|", "with the counts 50, 50, 50, 0 and 0 and no reason")
	}
	Do $$$AssertEquals(..HeadersBetween(trace, 1, "FixExecutor", "IncidentManager", "OcuTalon.Fix.Msg.FixResult"), 1, "and it is the only one")
	Do $$$AssertEquals(..WaitIncidentState(ref, "resolved"), "resolved", "the incident is resolved")

	// the notice
	Set end = $ZHorolog + ..#WAITHOLD
	For {
		Set notes = ..NoticeBodies(ref, "result")
		If (notes.%Size() '< 1) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Hang 2
	Set notes = ..NoticeBodies(ref, "result")
	Do $$$AssertEquals(notes.%Size(), 1, "S has exactly one result Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef_"|"_note.incidentRef_"|"_note.sessionRef_"|"_note.decisionRef, "result|result.allThrough|"_request.ref_"|"_ref_"|"_a_"|", "of the key allThrough, with R1's Ref, the incident's and no decision")
		Do $$$AssertEquals(note.slots.count, ..#ORDERSCOUNT, "whose count is "_..#ORDERSCOUNT)
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc), "All 50 orders went through.", "which renders as the UX document has it")
		Do $$$AssertEquals(..NoticeSessionOf(note.id), trace, "in the incident's trace session")
	}
	Do ..AssertDeliveredIn(a, ##class(OcuTalon.Channel.WebChat.Out).#CHANNEL, "result", request.ref)
	Do ..AssertDeliveredIn(a, ##class(OcuTalon.Channel.SimPhone.Out).#CHANNEL, "result", request.ref)

	// the event and /state carry the stored result
	Set last = ..LastIncident(a, ref)
	Do $$$AssertTrue($IsObject(last), "the incident event is on S's stream")
	If $IsObject(last) {
		Do $$$AssertEquals(last.state_"|"_..Listed(last), "resolved|1|"_request.ref_"|done", "the last one lists R1 done in the resolved incident")
		Do $$$AssertEquals(..ResultOf(last), "50|50|50|0|0|0|", "with the result 50/50/50/0/0/0 and no reason")
		If $IsObject(last.requests.%Get(0).result) Do $$$AssertEquals(last.requests.%Get(0).result.%GetTypeOf("total")_"|"_last.requests.%Get(0).result.%GetTypeOf("interrupted"), "number|number", "as numbers")
	}
	Set state = ..StateIncident(a, ref)
	Do $$$AssertTrue($IsObject(state), "/state lists the incident")
	If $IsObject(state) {
		Do $$$AssertEquals(state.state_"|"_..Listed(state), "resolved|1|"_request.ref_"|done", "/state lists R1 done in the resolved incident")
		Do $$$AssertEquals(..ResultOf(state), "50|50|50|0|0|0|", "with the same result")
		Do $$$AssertEquals(state.groups.%Size()_"|"_state.groups.%Get(0).count, "1|"_..#ORDERSCOUNT, "and it keeps its group of "_..#ORDERSCOUNT)
		Do $$$AssertTrue($IsObject(state.evidence) && (state.evidence.items.%Size() = 1) && $IsObject(state.traceTargets) && (state.traceTargets.diagnosis.traceHeaderId = trace), "and its evidence and its trace targets")
	}

	// the audit log: OcuTalon's Action entry, and IRIS's own entry for each copy
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(auditMark, "OcuTalon", "Action", "", request.ref, "", 1, 20)
	Do $$$AssertEquals(entries.%Size(), 1, "the audit log holds one OcuTalon Action entry for R1")
	If entries.%Size() = 1 {
		Set data = entries.%Get(0).data
		Do $$$AssertEquals(..SortedKeys(data), "action,approvalRef,channel,counts,irisUser,result,sessionRef,target", "it has the members of the Action shape and no other")
		Do $$$AssertEquals(data.irisUser_"|"_data.sessionRef_"|"_data.channel_"|"_data.action_"|"_data.target_"|"_data.result_"|"_data.approvalRef, ..#ANSWERER_"|"_a_"|web|repair_resend|"_..#ORDERSPRODUCTION_" in "_..#ORDERS_"|done|"_request.ref, "naming the approver, S, the channel, the kind, the production, the result and R1")
		Do $$$AssertEquals(data.counts.%ToJSON(), "{""total"":50,""resent"":50,""completed"":50,""failedAgain"":0,""skipped"":0}", "with the counts as numbers")
		Set text = $ZConvert(data.%ToJSON()_" "_entries.%Get(0).description, "L")
		Set bad = ""
		For i = 1:1:$Length(..#FORBIDDEN, ",") {
			If text [ $Piece(..#FORBIDDEN, ",", i) Set bad = bad _ $Piece(..#FORBIDDEN, ",", i) _ " "
		}
		Do $$$AssertEquals(bad, "", "and holds no key, token, password or chat identity")
	}
	Set resends = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(auditMark, "%Ensemble", "%Message", "Resend", "", "", ..#ORDERSCOUNT, 30)
	Set missing = 0
	For i = 1:1:$Length(copies, ",") {
		Set found = 0
		For j = 0:1:resends.%Size() - 1 {
			If resends.%Get(j).data [ ("MessageHeaderId = "_$Piece(copies, ",", i)_",") Set found = 1
		}
		If 'found Set missing = missing + 1
	}
	Do $$$AssertEquals(missing, 0, "IRIS's own Resend entry names each of the "_..#ORDERSCOUNT_" copies by its header id ("_resends.%Size()_" entries)")
	Do $$$AssertEquals(..Posts(mark), 0, "the mock logged no request during the run")
}

Method TestLaterRequestPendingAfterTheResult()
{
	If '..RaisedTwo("later", .a, .ref, .r1, .r2) Quit
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(r1.ref, "approve", "web", ..#ANSWERER, a, .winner), "done", "R1 is approved")
	Do $$$AssertEquals(..WaitState(ref, r1.ref, "done", ..#WAITEND), "done", "R1 is done: its copies are counted")
	Set end = $ZHorolog + ..#WAITHOLD
	For {
		Set notes = ..NoticeBodies(ref, "result")
		If (notes.%Size() '< 1) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(notes.%Size(), 1, "S has one result Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.catalogKey_"|"_note.approvalRef_"|"_note.slots.count, "result.allThrough|"_r1.ref_"|"_$Length(r1.fixTargets, ","), "of the key allThrough with R1's Ref and R1's count")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc), "All "_$Length(r1.fixTargets, ",")_" orders went through.", "which renders as the UX document has it")
	}
	Do $$$AssertEquals(..WaitIncidentState(ref, "awaiting_approval"), "awaiting_approval", "the incident is awaiting approval: R2 is still pending")
	Set last = ..LastIncident(a, ref)
	Do $$$AssertTrue($IsObject(last), "the incident event is on S's stream")
	If $IsObject(last) {
		Do $$$AssertEquals(last.state_"|"_..Listed(last, 0)_"|"_..Listed(last, 1), "awaiting_approval|2|"_r1.ref_"|done|2|"_r2.ref_"|pending", "the last one lists R1 done and R2 pending")
		Do $$$AssertEquals(..ResultOf(last, 0)_"#"_..ResultOf(last, 1), $Length(r1.fixTargets, ",")_"|"_$Length(r1.fixTargets, ",")_"|"_$Length(r1.fixTargets, ",")_"|0|0|0|#none", "R1 has its result and R2 has none")
	}
	Do $$$AssertEquals(..Requests(ref).%Get(1).state, "pending", "R2 is pending in its row")
	Do $$$AssertEquals(..Runs(ref).%Size(), 1, "and only R1 has a FixRun")
}

}
