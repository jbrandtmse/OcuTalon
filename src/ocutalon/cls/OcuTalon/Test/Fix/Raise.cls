Include Ensemble

/// Tests of the approval request that the incident notice raises (Story 7.2; AD-4, AD-11, AD-15, AD-16, AD-26, AD-32). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21), fresh (IncidentManager and ApprovalHold are code of the running production, so a warm stack's jobs keep their old code), with demo mode on, through
/// Test.Watch.Case: real failed orders of OCUORDERS (from the real poller, or delivered to IncidentManager as a FailureBatch with the real header ids), the CI mock as
/// the model (its diagnosis scenario, a data-format change with the fix repair_resend), the real FixExecutor dry run, the real Approval.Raise and the real hold. They
/// fail with the reason where the production, OCUORDERS, demo mode or the ANSWERER account's role is missing. A test waits at most 90 seconds for a diagnosis and 20
/// for the rest (test bounds, not NFR-7). The incidents, requests, holds and tasks of a test are removed after it (Case.DropIncidentRows).
///   - TestInstanceWatchers (AC 4): sessions A and B watch Orders and C does not, the online demo is off, and untagged failing orders make one instance incident:
///     exactly one request names it (owner instance, no trace Ref, repair_resend), A and B each have one incident.withFix Notification that carries that request's
///     Ref, and C has none;
///   - TestRejectChangesNothing (AC 5, AC 7; DW-271): session S's request is rejected through Approval.Answer: the incident is open with the variant rejected, one
///     answered.rejected Notification (the channel and the time of the answer, the request's Ref and the incident's) lies in the incident's trace session, the incident
///     event lists the request as rejected and /state does too, no Execute goes to FixExecutor, and a snapshot of OCUORDERS shows no change;
///   - TestExpiryChangesNothing (AC 5): the same for the timer: the request is aged, its hold deleted and the holds re-armed (Approval.Reconcile), which expires it:
///     open with the variant expired, one answered.expired Notification with the request's ExpiresAt, no Execute and no change in OCUORDERS;
///   - TestCancelSendsNoOutcome (AC 6): Approval.Cancel ends the hold and no ApprovalOutcome from ApprovalHold names the request; the incident stays awaiting_approval
///     with the same NoticedAt and no new Notification;
///   - TestUnscopedOrdersGetTheNoFixNotice (AC 8, V2): the failed orders are untagged (of the instance scope) and the incident is session S's, so the dry run refuses
///     them: the incident gets incident.noFix (open, no_fix), no request, and one Type 3 warning that names it.
Class OcuTalon.Test.Fix.Raise Extends OcuTalon.Test.Watch.Case
{

/// The number of orders that a test fails.
Parameter ORDERCOUNT = 3;

/// The longest wait for the end of a hold, and for an outcome to be handled, in seconds (test bounds, not NFR-7).
Parameter WAITHOLD = 20;

Method TestInstanceWatchers()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	If '..ApprovalReady() Quit
	Do ..SetOnlineDemo("")
	Set a = ..Session("watchera")
	Set b = ..Session("watcherb")
	Set c = ..Session("watcherc")
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	Do ..Watch(b)
	If '..Fail(..#ORDERCOUNT, "") Quit
	Set failed = ..WaitFailed(..#ORDERCOUNT)
	Set rows = ..WaitIncident("instance", ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(rows.%Size(), 1, "one instance incident for the untagged failures")
	If rows.%Size() < 1 Quit
	Set ref = rows.%Get(0).ref
	If '..Noticed(ref, 2) Quit
	Set requests = ..Requests(ref)
	Do $$$AssertEquals(requests.%Size(), 1, "exactly one request names the incident")
	If requests.%Size() '= 1 Quit
	Set request = requests.%Get(0)
	Do $$$AssertEquals(request.kind_"|"_request.ownerRef_"|"_request.traceRef_"|"_request.fixKind_"|"_request.state, "fix|instance||repair_resend|pending", "it is a pending repair_resend fix of the instance, with no trace Ref")
	Set bodies = ..NoticeBodies(ref)
	Do $$$AssertEquals(bodies.%Size(), 2, "two Notifications carry the incident's Ref")
	Set sessions = ""
	Set iterator = bodies.%GetIterator()
	While iterator.%GetNext(, .note) {
		Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef, "incident|incident.withFix|"_request.ref, "each is the with-fix notice and carries the request's Ref")
		Set sessions = sessions_","_note.sessionRef_","
	}
	Do $$$AssertEquals(($Find(sessions, ","_a_",") > 0)_"|"_($Find(sessions, ","_b_",") > 0)_"|"_($Find(sessions, ","_c_",") > 0), "1|1|0", "one for A, one for B and none for C")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_row.RequestRefs, "awaiting_approval||"_request.ref, "the incident is awaiting approval and lists the request")
}

Method TestRejectChangesNothing()
{
	If '..Raised("reject", .a, .ref, .request) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row
	Set namespaces = $ListBuild(..#ORDERS)
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .before)
	Set done = ##class(OcuTalon.Bridge.Approval).Answer(request.ref, "reject", "web", ..#ANSWERER, a, .winner)
	Do $$$AssertEquals(done, "done", "the rejection is accepted")
	Set variant = ..WaitRow(ref, "OpenVariant", "", ..#WAITHOLD)
	Do $$$AssertEquals(variant, "rejected", "the incident is open with the variant rejected")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.RequestRefs, "open|"_request.ref, "it is open and still lists the request")
	Kill row
	Set answered = ..Answered(ref, 1)
	If $IsObject(answered) {
		Set after = ..Requests(ref).%Get(0)
		Do $$$AssertEquals(answered.kind_"|"_answered.catalogKey_"|"_answered.approvalRef_"|"_answered.incidentRef_"|"_answered.sessionRef_"|"_answered.decisionRef, "answered|answered.rejected|"_request.ref_"|"_ref_"|"_a_"|", "one answered notification: the key, the request's Ref, the incident's and no decision")
		Do $$$AssertEquals(answered.slots.channel_"|"_answered.slots.time, "web|"_after.answeredAt, "with the channel and the time of the answer")
		Set text = ##class(OcuTalon.Msg.Catalog).Render(answered.catalogKey, answered.slots.%ToJSON(), "phone", .sc)
		Do $$$AssertStatusOK(sc, "it renders")
		Do $$$AssertTrue(($Extract(text, 1, 30) = "Rejected from the web chat at ") && ($Extract(text, $Length(text) - 21, *) = ". Nothing was changed."), "as Rejected from the web chat at the time, Nothing was changed: "_text)
		Do $$$AssertEquals(..NoticeSessionOf(answered.id), trace, "in the incident's trace session")
	}
	Set events = ..Stream(a)
	Set last = ""
	Set iterator = events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If (event.type = "incident") && (event.payload.ref = ref) Set last = event.payload
	}
	Do $$$AssertTrue($IsObject(last), "the incident has events on S's stream")
	If $IsObject(last) Do $$$AssertEquals(last.state_"|"_last.openVariant_"|"_last.requests.%Size()_"|"_last.requests.%Get(0).ref_"|"_last.requests.%Get(0).state, "open|rejected|1|"_request.ref_"|rejected", "the last incident event lists the request as rejected")
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(a))
	Set found = ""
	Set iterator = body.chat.%GetIterator()
	While iterator.%GetNext(, .each) {
		If (each.type = "incident") && (each.payload.ref = ref) Set found = each.payload
	}
	Do $$$AssertTrue($IsObject(found), "/state lists the incident")
	If $IsObject(found) Do $$$AssertEquals(found.requests.%Size()_"|"_found.requests.%Get(0).ref_"|"_found.requests.%Get(0).state, "1|"_request.ref_"|rejected", "with the request as rejected")
	Do $$$AssertEquals(..HeadersBetween(trace, 1, "IncidentManager", "FixExecutor", "OcuTalon.Fix.Msg.Execute"), 0, "no Execute went to FixExecutor")
	Do ..Unchanged(namespaces, before)
}

Method TestExpiryChangesNothing()
{
	If '..Raised("expiry", .a, .ref, .request) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row
	Set namespaces = $ListBuild(..#ORDERS)
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .before)
	Set oldHold = ##class(OcuTalon.Bridge.Approval).LiveHold(request.ref)
	Do $$$AssertTrue(oldHold '= "", "the request has a live hold")
	Do ##class(OcuTalon.Test.Bridge.Approval).Age(request.ref, 86460, -60)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.ApprovalHold).%DeleteId(oldHold), "the hold instance is deleted")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Reconcile(), "Reconcile re-arms the hold, which is past its expiry and fires at once")
	Set variant = ..WaitRow(ref, "OpenVariant", "", ..#WAITHOLD)
	Do $$$AssertEquals(variant, "expired", "the incident is open with the variant expired")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.RequestRefs, "open|"_request.ref, "it is open and still lists the request")
	Kill row
	Set answered = ..Answered(ref, 1)
	If $IsObject(answered) {
		Set after = ..Requests(ref).%Get(0)
		Do $$$AssertEquals(after.state, "expired", "the request is expired")
		Do $$$AssertEquals(answered.kind_"|"_answered.catalogKey_"|"_answered.approvalRef_"|"_answered.incidentRef_"|"_answered.sessionRef_"|"_answered.decisionRef, "answered|answered.expired|"_request.ref_"|"_ref_"|"_a_"|", "one answered notification: the key, the request's Ref, the incident's and no decision")
		Do $$$AssertEquals(answered.slots.%ToJSON(), {"time": (after.expiresAt)}.%ToJSON(), "with the request's ExpiresAt")
		Set text = ##class(OcuTalon.Msg.Catalog).Render(answered.catalogKey, answered.slots.%ToJSON(), "phone", .sc)
		Do $$$AssertStatusOK(sc, "it renders")
		Do $$$AssertTrue(($Extract(text, 1, 11) = "Expired at ") && ($Extract(text, $Length(text) - 21, *) = ". Nothing was changed."), "as Expired at the time, Nothing was changed: "_text)
	}
	Do $$$AssertEquals(..HeadersBetween(trace, 1, "IncidentManager", "FixExecutor", "OcuTalon.Fix.Msg.Execute"), 0, "no Execute went to FixExecutor")
	Do ..Unchanged(namespaces, before)
}

Method TestCancelSendsNoOutcome()
{
	If '..Raised("cancel", .a, .ref, .request) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Set noticedAt = row.NoticedAt
	Kill row
	Set notices = ..Notifications(ref)
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(a, "incident").%Size()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Approval).Cancel(request.ref), "the request is cancelled")
	Set end = $ZHorolog + ..#WAITHOLD
	While (##class(OcuTalon.Bridge.Approval).LiveHold(request.ref) '= "") && ($ZHorolog < end) {
		Hang 0.2
	}
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).LiveHold(request.ref), "", "the hold ends")
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Approval).WaitHoldSettled(request.ref, trace, ..#WAITHOLD), "and its OnResponse has returned")
	Do $$$AssertEquals(..Requests(ref).%Get(0).state, "cancelled", "the row is cancelled")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE MessageBodyClassName = 'OcuTalon.Bridge.Msg.ApprovalOutcome' AND SourceConfigName = 'ApprovalHold'")
	Set outcomes = 0
	While rs.%Next() {
		Set body = ##class(OcuTalon.Bridge.Msg.ApprovalOutcome).%OpenId(rs.%Get("MessageBodyId"))
		If $IsObject(body) && (body.ApprovalRef = request.ref) Set outcomes = outcomes + 1
	}
	Do $$$AssertEquals(outcomes, 0, "no ApprovalOutcome from ApprovalHold names the request")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.NoticedAt_"|"_row.RequestRefs, "awaiting_approval|"_noticedAt_"|"_request.ref, "the incident stays awaiting approval, with the same NoticedAt")
	Do $$$AssertEquals(..Notifications(ref), notices, "and no new Notification")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(a, "incident").%Size(), events, "nor a new incident event")
}

Method TestUnscopedOrdersGetTheNoFixNotice()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	If '..ApprovalReady() Quit
	Set a = ..Session("unscoped")
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..ClearMark(..#ORDERS)
	If '..Fail(2, "") Quit
	Set failed = ..WaitFailed(2)
	If failed.%Size() '= 2 Quit
	Set failures = []
	For i = 0:1:1 {
		Do failures.%Push({"item": "OrdersFromPartner", "text": (..#ORDERDATETEXT), "at": (##class(OcuTalon.Test.Watch.Incidents).Stamp(-1)), "id": (failed.%Get(i).id)})
	}
	Do $$$AssertStatusOK(..SendBatch(..#ORDERS, ..#ORDERSPRODUCTION, a, failures), "the two untagged failed orders are delivered as S's failures")
	Set rows = ..WaitIncident(a, ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(rows.%Size(), 1, "one incident of S")
	If rows.%Size() < 1 Quit
	Set ref = rows.%Get(0).ref
	If '..Noticed(ref, 1) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_row.RequestRefs_"|"_row.CauseCategory, "open|no_fix||data_format_change", "the incident is open with the variant no_fix and lists no request, although the cause is a data-format change")
	Do $$$AssertEquals(..Requests(ref).%Size(), 0, "no request names it")
	Set bodies = ..NoticeBodies(ref)
	Do $$$AssertEquals(bodies.%Size(), 1, "S has one Notification of it")
	If bodies.%Size() = 1 {
		Set note = bodies.%Get(0)
		Do $$$AssertEquals(note.kind_"|"_note.catalogKey_"|"_note.approvalRef_"|"_note.slots.cause, "incident|incident.noFix||"_row.Cause, "the no-fix notice, with the cause and no request")
	}
	Do $$$AssertEquals(..HeadersBetween(row.TraceHeaderId, 1, "IncidentManager", "FixExecutor", "OcuTalon.Fix.Msg.DryRun"), 1, "the dry run was asked")
	Set warned = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Proposed", $Parameter("OcuTalon.Watch.IncidentManager", "LOGPROPOSE"))
	Do $$$AssertEquals(warned, 1, "and one Type 3 warning names the incident and the dry run's reason: "_text)
	If warned Do $$$AssertTrue($Find(text, ref) > 0, "the incident is in the warning")
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Proposed", $Parameter("OcuTalon.Watch.IncidentManager", "LOGPROPOSE"))
}

/// --- helpers ---
/// The set-up of a test with a raised request of session S: the production is ready, the mock is pointed to, the approval role is ready, S watches Orders and
/// ORDERCOUNT failing orders tagged with S's trace Ref become an incident that is noticed with its fix. a is S, ref the incident and request the request, as
/// Case.Requests gives it. 1 when the set-up is done.
Method Raised(name As %String, Output a As %String, Output ref As %String, Output request As %DynamicObject) As %Boolean [ Private ]
{
	Set (a, ref, request) = ""
	If '..Ready() Quit 0
	If '..PointKeys() Quit 0
	If '..ApprovalReady() Quit 0
	Set a = ..Session(name)
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	If '..Fail(..#ORDERCOUNT, trace) Quit 0
	Set failed = ..WaitFailed(..#ORDERCOUNT)
	Set rows = ..WaitIncident(a, ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(rows.%Size(), 1, "one incident for the burst of S")
	If rows.%Size() < 1 Quit 0
	Set ref = rows.%Get(0).ref
	If '..Noticed(ref, 1) Quit 0
	Set requests = ..Requests(ref)
	Do $$$AssertEquals(requests.%Size(), 1, "one request names the incident")
	If requests.%Size() '= 1 Quit 0
	Set request = requests.%Get(0)
	Do $$$AssertEquals(request.state, "pending", "and it is pending")
	Quit (request.state = "pending")
}

/// Waits for the diagnosis of the incident to be handled and the notice to be sent: IncidentManager has handled Decide's answer, NoticedAt is set and count
/// Notifications carry the incident's Ref. 1 when all three are, else 0 with a failed assertion.
Method Noticed(ref As %String, count As %Integer) As %Boolean [ Private ]
{
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Do $$$AssertTrue(..WaitDiagnosed(ref), "the incident holds its diagnosis")
	Do $$$AssertTrue(..WaitAnswered(ref), "and IncidentManager has handled the answer")
	Set noticed = (..WaitRow(ref, "NoticedAt", "", ..#WAITINCIDENT) '= "")
	Do $$$AssertTrue(noticed, "the notice follows: NoticedAt is set")
	If 'noticed Quit 0
	Do ..WaitNotices(ref, count)
	Quit 1
}

/// The answered Notification of the incident once count of them exist: {"id", "sessionRef", "kind", "catalogKey", "slots", "approvalRef", "incidentRef",
/// "decisionRef"}, or "" with a failed assertion when there are not exactly count.
Method Answered(ref As %String, count As %Integer) As %DynamicObject [ Private ]
{
	Set end = $ZHorolog + ..#WAITHOLD
	For {
		Set found = ..AnsweredNotices(ref)
		If (found.%Size() '< count) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(found.%Size(), count, count_" answered notification(s) carry the incident's Ref")
	If found.%Size() '= count Quit ""
	Quit found.%Get(0)
}

/// The Notifications of kind answered that carry the incident's Ref, oldest first, as {"id", "sessionRef", "kind", "catalogKey", "slots", "approvalRef",
/// "incidentRef", "decisionRef"}.
ClassMethod AnsweredNotices(ref As %String) As %DynamicArray [ Private ]
{
	Set found = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Msg.Notification WHERE IncidentRef = ? AND Kind = 'answered' ORDER BY ID", ref)
	While rs.%Next() {
		Set note = ##class(OcuTalon.Msg.Notification).%OpenId(rs.%GetData(1))
		If '$IsObject(note) Continue
		Do found.%Push({"id": (note.%Id()), "sessionRef": (note.SessionRef), "kind": (note.Kind), "catalogKey": (note.CatalogKey), "slots": ({}.%FromJSON(note.Slots)), "approvalRef": (note.ApprovalRef), "incidentRef": (note.IncidentRef), "decisionRef": (note.DecisionRef)})
	}
	Quit found
}

/// The trace session of the header that carried the Notification.
ClassMethod NoticeSessionOf(id As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT SessionId FROM Ens.MessageHeader WHERE MessageBodyClassName = 'OcuTalon.Msg.Notification' AND MessageBodyId = ? ORDER BY ID", id)
	If rs.%Next() Quit rs.%GetData(1)
	Quit ""
}

/// Asserts that OCUORDERS is as the snapshot was: the new snapshot differs in no header, production, state, default setting or queue.
Method Unchanged(namespaces As %List, before As %DynamicObject) [ Private ]
{
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .after)
	Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(before, after)
	Do $$$AssertEquals(lines.%Size(), 0, "OCUORDERS did not change: "_lines.%ToJSON())
}

}
