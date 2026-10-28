/// Tests of the later requests of an incident (Story 7.6; AD-4, AD-11, AD-15, AD-16, AD-26, AD-32). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh
/// (IncidentManager, FixExecutor and ApprovalHold are code of the running production, so a warm stack's jobs keep their old code), with demo mode on, through
/// Test.Watch.Case: real failed orders of OCUORDERS (from the real poller), the CI mock as the model (its diagnosis scenario, a data-format change with the fix
/// repair_resend), the real FixExecutor dry run, the real Approval.Raise and the real hold. They fail with the reason where the production, OCUORDERS, demo mode
/// or the ANSWERER account's role is missing. A test waits at most WAITLATER seconds for a later request, and at most 90 seconds for a diagnosis and 20 for the
/// rest (test bounds, not NFR-7). The incidents, requests, holds and tasks of a test are removed after it (Case.DropIncidentRows).
///   - TestLaterFailuresGetTheirOwnRequest (AC 1, AC 2, AC 3; Integration): session S's incident awaits approval with R1 over three failed orders, and two more
///     orders of the same cause fail with S's trace Ref. At once the count is 5, NoticeCount stays 3, the last incident event has the count 5 and lists R1 only,
///     and R1's targets, dry run and state are as they were. After the settle, FixExecutor is asked a second time in the incident's trace session, and a request R2
///     of the same kind and parameters is raised over the two new orders alone, with its own dry run and its hold in the trace session; the incident stays
///     awaiting_approval with the same NoticedAt and lists R1 and R2; S gets one approval Notification (incident.laterRequest, R2's Ref, the count and first
///     time of the two failures, R2's dry run), which renders as the later request, and WebChatOut records its approval Delivery row with R2's Ref; the incident
///     event and /state list R1 and R2 pending; the mock logged no request. Rejecting R2 while R1 is pending keeps the incident awaiting_approval, sends one
///     answered.rejected Notification with R2's Ref, lists R2 as rejected and sends no Execute;
///   - TestOpenIncidentOnlyCounts (AC 6): S's incident is open (R1 rejected) when two more orders of the cause fail: the count and one more incident event come,
///     LaterSince stays empty, and after the quiet time and three seconds there is still one request, no approval Notification and one dry run.
Class OcuTalon.Test.Fix.Later Extends OcuTalon.Test.Watch.Case
{

/// The longest a test waits for the later request after the failures, in seconds (a test bound, not NFR-7): the quiet time, the dry run and the raise.
Parameter WAITLATER = 30;

Method TestLaterFailuresGetTheirOwnRequest()
{
	If '..Raised("later", .a, .ref, .first) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Set noticedAt = row.NoticedAt
	Set summary = row.FixSummary
	Kill row
	Set traceRef = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set before = ##class(OcuTalon.Test.Core.Observe).Events(a, "incident").%Size()
	If '..Fail(2, traceRef) Quit
	Set started = $ZHorolog
	Set failed = ..WaitFailed(5)
	If failed.%Size() '= 5 Quit
	Set ids = ..HeaderIds(failed)

	// at once: the count and the event, nothing else
	Do $$$AssertEquals(..WaitCount(ref, 5), 5, "the count moves to 5")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertEquals(row.NoticeCount_"|"_row.State_"|"_row.NoticedAt, "3|awaiting_approval|"_noticedAt, "NoticeCount, the state and NoticedAt stand")
	Do $$$AssertTrue(row.LaterSince '= "", "and LaterSince is set: a later round gathers")
	Kill row
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(a, "incident", before + 1, 10)
	Do $$$AssertTrue(events.%Size() '< (before + 1), "the new count has an incident event")
	If events.%Size() '< (before + 1) {
		Set last = events.%Get(events.%Size() - 1).payload
		Do $$$AssertEquals(last.count_"|"_last.noticeCount_"|"_..Listed(last), "5|3|1|"_first.ref_"|pending", "carrying the count 5 and listing R1 only")
	}
	Set requests = ..Requests(ref)
	Do $$$AssertEquals(requests.%Size(), 1, "and there is still one request")
	If requests.%Size() = 1 Do $$$AssertEquals(requests.%Get(0).fixTargets_"|"_requests.%Get(0).state_"|"_(requests.%Get(0).dryRun = first.dryRun), $Piece(ids, ",", 1, 3)_"|pending|1", "R1's targets, dry run and state are as they were")

	// after the settle: the later request
	Set end = $ZHorolog + ..#WAITLATER
	For {
		Set requests = ..Requests(ref)
		If (requests.%Size() '< 2) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(requests.%Size(), 2, "a second request names the incident")
	If requests.%Size() '= 2 Quit
	Do ..WaitNotices(ref, 2)
	Do $$$LogMessage("the later request was raised "_$Justify($ZHorolog - started, 0, 1)_" seconds after the failed orders were all in the error status")
	Set second = requests.%Get(1)
	Do $$$AssertEquals(second.kind_"|"_second.state_"|"_second.ownerRef_"|"_second.resultTarget, "fix|pending|"_a_"|IncidentManager", "R2 is a pending fix of S's")
	Do $$$AssertEquals(second.fixKind_"|"_second.fixParameters, first.fixKind_"|"_first.fixParameters, "of R1's kind and parameters")
	Do $$$AssertEquals(second.fixTargets, $Piece(ids, ",", 4, 5), "over the two new orders alone, ascending: "_second.fixTargets_" of "_ids_" in "_..Group(ref).seen)
	Set dryRun = {}.%FromJSON(second.dryRun)
	Do $$$AssertEquals(dryRun.affected_"|"_dryRun.resend_"|"_dryRun.leftOut_"|"_dryRun.field_"|"_dryRun.before_"|"_dryRun.after_"|"_dryRun.itemNoun.other, "2|2|0|order date|10/16/2026|2026-10-16|orders", "with its own dry run: "_second.dryRun)
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.RequestRefs_"|"_row.NoticedAt_"|"_row.LaterSince_"|"_row.AskingSince_"|"_row.Count_"|"_row.NoticeCount, "awaiting_approval|"_first.ref_","_second.ref_"|"_noticedAt_"|||5|3", "the incident is awaiting approval, lists R1 and R2, was noticed as before and has no round open")
	Kill row

	// the notification, the page and the trace
	Set notes = ..NoticeBodies(ref, "approval")
	Do $$$AssertEquals(notes.%Size(), 1, "S has one approval Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef_"|"_note.incidentRef_"|"_note.sessionRef, "approval|incident.laterRequest|"_second.ref_"|"_ref_"|"_a, "of the later request, with R2's Ref")
		Set slots = note.slots
		Do $$$AssertEquals(slots.count_"|"_slots.time_"|"_slots.itemNoun.other_"|"_slots.fixSummary, "2|"_##class(OcuTalon.Watch.Mark).FailedAt(failed.%Get(3).at)_"|orders|"_summary, "with the count and the first time of the two failures")
		Do $$$AssertEquals(slots.field_"|"_slots.before_"|"_slots.after_"|"_slots.resendCount, "order date|10/16/2026|2026-10-16|2", "and R2's dry run: "_note.slots.%ToJSON())
		Set text = ##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, slots.%ToJSON(), "phone", .sc)
		Do $$$AssertStatusOK(sc, "it renders")
		Do $$$AssertEquals($Extract(text, 1, 27), "2 more orders failed since ", "as the later request: "_text)
		Do $$$AssertTrue($Find(text, $Char(10, 10)_"Dry run: 2 orders affected. Example: order date 10/16/2026 becomes 2026-10-16. I'll resend 2 repaired copies; the originals stay unchanged. Nothing has changed yet.") > 0, "with its own Dry run paragraph: "_text)
	}
	Do ..AssertDelivered(a, "approval", second.ref)
	Set last = ..LastIncident(a, ref)
	Do $$$AssertTrue($IsObject(last), "the incident has events on S's stream")
	If $IsObject(last) Do $$$AssertEquals(last.state_"|"_..Listed(last, 0)_"|"_..Listed(last, 1), "awaiting_approval|2|"_first.ref_"|pending|2|"_second.ref_"|pending", "the last incident event lists R1 and R2 pending")
	Set found = ..StateIncident(a, ref)
	Do $$$AssertTrue($IsObject(found), "/state lists the incident")
	If $IsObject(found) Do $$$AssertEquals(..Listed(found, 0)_"|"_..Listed(found, 1), "2|"_first.ref_"|pending|2|"_second.ref_"|pending", "with R1 and R2 pending")
	Do $$$AssertEquals(..HeadersBetween(trace, 1, "IncidentManager", "FixExecutor", "OcuTalon.Fix.Msg.DryRun"), 2, "two dry runs went to FixExecutor in the incident's trace session")
	Do $$$AssertTrue(..HeadersBetween(trace, 1, "IncidentManager", "IncidentManager", "OcuTalon.Watch.Msg.Settle") '< 2, "and the later waiter's Settle lies in it too")
	Do $$$AssertTrue(..HoldInSession(trace, second.ref), "R2's hold started in the trace session")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's request log is read")
	Set posts = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.path = "/v1/messages") Set posts = posts + 1
	}
	Do $$$AssertEquals(posts, 0, "the mock logged no request for the later round")

	// R2 rejected while R1 is pending
	Set done = ##class(OcuTalon.Bridge.Approval).Answer(second.ref, "reject", "web", ..#ANSWERER, a, .winner)
	Do $$$AssertEquals(done, "done", "R2's rejection is accepted")
	Set answered = ..Answered(ref, 1)
	If $IsObject(answered) {
		Do $$$AssertEquals(answered.kind_"|"_answered.catalogKey_"|"_answered.approvalRef_"|"_answered.incidentRef_"|"_answered.sessionRef, "answered|answered.rejected|"_second.ref_"|"_ref_"|"_a, "one answered.rejected Notification carries R2's Ref")
		Do ..AssertDelivered(a, "answered", second.ref)
	}
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.RequestRefs, "awaiting_approval|"_first.ref_","_second.ref, "the incident stays awaiting approval, with both requests")
	Kill row
	Set last = ..LastIncident(a, ref)
	If $IsObject(last) Do $$$AssertEquals(last.state_"|"_..Listed(last, 0)_"|"_..Listed(last, 1), "awaiting_approval|2|"_first.ref_"|pending|2|"_second.ref_"|rejected", "and the event lists R2 as rejected")
	Do $$$AssertEquals(..HeadersBetween(trace, 1, "IncidentManager", "FixExecutor", "OcuTalon.Fix.Msg.Execute"), 0, "no Execute went to FixExecutor")
}

Method TestOpenIncidentOnlyCounts()
{
	If '..Raised("opencount", .a, .ref, .first) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row
	Set traceRef = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set done = ##class(OcuTalon.Bridge.Approval).Answer(first.ref, "reject", "web", ..#ANSWERER, a, .winner)
	Do $$$AssertEquals(done, "done", "R1's rejection is accepted")
	Do $$$AssertEquals(..WaitRow(ref, "OpenVariant", "", ..#WAITHOLD), "rejected", "the incident is open with the variant rejected")
	Do $$$AssertTrue($IsObject(..Answered(ref, 1)), "R1's rejection is told to the watcher")
	Set end = $ZHorolog + ..#WAITHOLD
	For {
		Set last = ..LastIncident(a, ref)
		If ($IsObject(last) && (last.state = "open")) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertTrue($IsObject(last) && (last.state = "open"), "and so is the incident event that opens it")
	Set notices = ..Notifications(ref)
	Set before = ##class(OcuTalon.Test.Core.Observe).Events(a, "incident").%Size()
	If '..Fail(2, traceRef) Quit
	Set failed = ..WaitFailed(5)
	If failed.%Size() '= 5 Quit
	Do $$$AssertEquals(..WaitCount(ref, 5), 5, "the count moves to 5")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(a, "incident", before + 1, 10)
	Do $$$AssertTrue(events.%Size() '< (before + 1), "with an incident event")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.LaterSince_"|"_row.AskingSince, "open||", "the incident stays open and no round gathers")
	Kill row
	Do ##class(OcuTalon.Watch.Settle).Values(.quiet, .max)
	Hang quiet + 3
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.RequestRefs_"|"_row.LaterSince_"|"_row.AskingSince, "open|"_first.ref_"||", "after the quiet time it is as it was, with R1 only")
	Kill row
	Do $$$AssertEquals(..Requests(ref).%Size(), 1, "there is one request")
	Do $$$AssertEquals(..NoticeBodies(ref, "approval").%Size(), 0, "no approval Notification was sent")
	Do $$$AssertEquals(..Notifications(ref), notices, "and no Notification at all")
	Do $$$AssertEquals(..HeadersBetween(trace, 1, "IncidentManager", "FixExecutor", "OcuTalon.Fix.Msg.DryRun"), 1, "and the dry run was asked once")
}

/// --- helpers ---
/// The payload of the newest incident event of the incident on the session's stream, or "" when there is none.
ClassMethod LastIncident(session As %String, ref As %String) As %DynamicObject
{
	Set last = ""
	Set iterator = ..Stream(session).%GetIterator()
	While iterator.%GetNext(, .event) {
		If (event.type = "incident") && (event.payload.ref = ref) Set last = event.payload
	}
	Quit last
}

}
