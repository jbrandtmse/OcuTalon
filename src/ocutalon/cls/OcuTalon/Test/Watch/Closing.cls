/// Tests of the incident lifecycle over the RUNNING production (Story 5.5; AD-1, AD-4, AD-11, AD-12, AD-15). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21), fresh (the item IncidentManager is code of the running production, so a warm stack's job keeps its old code), with demo mode on, through
/// Test.Watch.Case. The model is the CI mock: a failure whose text holds a [[mock:<name>]] marker picks the scenario. They fail with the reason where the
/// production, OCUORDERS or demo mode is missing. A test waits at most 90 seconds for a diagnosis and 20 for the rest (test bounds, not NFR-7).
///   - TestDismissThroughCommandsIn: session A's no-fix incident (a [[mock:diagnosis-nofix]] batch on ZZNS) is noticed. The Dismiss of session B is not_found and
///     changes nothing; the Dismiss of A, submitted through Commands.Submit with origin web_user, is answered by CommandsIn and IncidentManager at once: Ok 1,
///     closed, and the row is closed. The newest incident event on A's stream is closed. A same-cause batch then makes a second incident with a new Ref, and one
///     Notification carries that Ref.
///   - TestRejectThroughTheHold: A's fixture incident is noticed and awaiting approval, and a real fix request (Approval.Raise, with the probe sink and
///     ResultTarget IncidentManager) is raised for it and listed in the incident's RequestRefs. The ANSWERER account's Answer (reject) ends the real hold, which
///     sends the ApprovalOutcome to IncidentManager: the incident is open with the variant rejected, and an incident event for it reaches A's stream.
///   - TestApproveSendsExecuteToFixExecutor (QA): the same set-up, and the ANSWERER account's Answer (approve) ends the hold with an approved outcome: the incident is
///     fixing, and the real SendExecute puts one Execute (the request's Ref) on the way from IncidentManager to FixExecutor, in the incident's trace session
///     (TraceHeaderId) with the SuperSession kept (the request's TraceRef), and once FixExecutor has handled it (the stub refuses it), no answer comes back to
///     IncidentManager within NOANSWERSECONDS. This reaches the header that the probe's SendExecute stands in for (DW-281); the handler's own test is still Story 7.3's.
///   The two hold tests share their set-up (HeldRequest) and the wait for the end of the hold (WaitHoldEnds).
/// The rows and events of a test are removed after it, and so are the request, its hold and its task.
Class OcuTalon.Test.Watch.Closing Extends OcuTalon.Test.Watch.Case
{

/// The namespace and the production of the incidents that SendBatch makes: nothing runs there, so the pack has no sample.
Parameter SYNTHNS = "ZZNS";

Parameter SYNTH = "Zz.Closing";

/// The item that carries out an approved fix (a stub until Story 7.3: the header of the order is what the test reads).
Parameter FIXEXECUTOR = "FixExecutor";

/// The statuses of a request header that its target has handled (Ens.DataType.MessageStatus: Discarded, Aborted, Error, Completed).
Parameter HANDLED = "4,7,8,9";

/// Seconds to look for an answer to the Execute after FixExecutor has handled it (an answer, when one is wanted, follows the handling at once).
Parameter NOANSWERSECONDS = 2;

/// The sink of the host events in this process.
Parameter SINK = "OcuTalon.Test.Bridge.ProbeSink";

Method TestDismissThroughCommandsIn()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	If '..UseReal() Quit
	Set a = ..Session("dismissa")
	Set b = ..Session("dismissb")
	Set item = ..Item("d")
	Set failure = {"item": (item), "text": "[[mock:diagnosis-nofix]] Field 'Qty' was empty", "at": (##class(OcuTalon.Test.Watch.Incidents).Stamp(-1))}
	Do $$$AssertStatusOK(..SendBatch(..#SYNTHNS, ..#SYNTH, a, [(failure)]), "a no-fix failure is sent")
	Set rows = ..WaitIncident(a, ..#SYNTH)
	Do $$$AssertEquals(rows.%Size(), 1, "it makes an incident")
	If rows.%Size() '= 1 Quit
	Set ref = rows.%Get(0).ref
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Do $$$AssertTrue(..WaitDiagnosed(ref), "the incident holds its diagnosis")
	Do $$$AssertTrue(..WaitRow(ref, "NoticedAt", "", ..#WAITINCIDENT) '= "", "and is noticed")
	Do ..WaitNotices(ref, 1)
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(a, "incident", 1, ..#WAITINCIDENT)
	Do $$$AssertEquals(events.%Size(), 1, "A's stream holds the notice's incident event")
	If events.%Size() '= 1 Quit
	Do $$$AssertEquals(events.%Get(0).payload.state_"|"_events.%Get(0).payload.openVariant, "open|no_fix", "which says open and no_fix")

	Set sc = ##class(OcuTalon.Core.Commands).Submit(..Dismissal(b, ref), "web_user", .result)
	Do $$$AssertStatusOK(sc, "B's Dismiss is submitted")
	Do $$$AssertEquals($IsObject(result) && (result.Ok_"|"_result.Outcome = "0|not_found"), 1, "it is not_found: B is not a recipient of the incident")
	Do $$$AssertEquals(..Incidents(a, ..#SYNTH).%Get(0).state, "open", "and the incident is still open")

	Set sc = ##class(OcuTalon.Core.Commands).Submit(..Dismissal(a, ref), "web_user", .result)
	Do $$$AssertStatusOK(sc, "A's Dismiss is submitted")
	Do $$$AssertEquals($IsObject(result) && (result.Ok_"|"_result.Outcome_"|"_result.Ref = ("1|closed|"_ref)), 1, "it is answered at once: Ok 1, closed, the Ref")
	Set row = ..Incidents(a, ..#SYNTH).%Get(0)
	Do $$$AssertEquals(row.state_"|"_row.openVariant_"|"_(row.closedAt '= ""), "closed||1", "the row is closed with ClosedAt and no variant")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(a, "incident", 2, ..#WAITINCIDENT)
	Do $$$AssertEquals(events.%Size(), 2, "A's stream holds a second incident event")
	If events.%Size() = 2 Do $$$AssertEquals(events.%Get(1).payload.ref_"|"_events.%Get(1).payload.state_"|"_events.%Get(1).payload.openVariant, ref_"|closed|", "the newest is the incident, closed, with no variant")

	Set second = {"item": (item), "text": "[[mock:diagnosis-nofix]] Field 'Qty' was empty", "at": (##class(OcuTalon.Test.Watch.Incidents).Stamp(0))}
	Do $$$AssertStatusOK(..SendBatch(..#SYNTHNS, ..#SYNTH, a, [(second)]), "a failure of the same cause is sent")
	Set rows = ..WaitIncident(a, ..#SYNTH, 2)
	Do $$$AssertEquals(rows.%Size(), 2, "it makes a second incident")
	If rows.%Size() '= 2 Quit
	Set again = rows.%Get(1).ref
	Do $$$AssertTrue(again '= ref, "with a new Ref")
	Do $$$AssertEquals(rows.%Get(0).state_"|"_rows.%Get(1).state, "closed|open", "the dismissed incident stays closed and the new one is open")
	Set ..ItemIds = ..ItemIds _ $ListBuild(again)
	Do $$$AssertTrue(..WaitDiagnosed(again), "the new incident holds its diagnosis")
	Do $$$AssertTrue(..WaitRow(again, "NoticedAt", "", ..#WAITINCIDENT) '= "", "and is noticed")
	Do ..WaitNotices(again, 1)
	Do $$$AssertEquals(..Notifications(again), 1, "one Notification carries the new Ref")
	Do $$$AssertEquals(..Notifications(ref), 1, "and the first incident still has its one")
}

Method TestRejectThroughTheHold()
{
	If '..Ready() Quit
	Set a = ..Session("hold")
	If '..HeldRequest(a, "hold", "", .incident, .approval) Quit

	Set done = ##class(OcuTalon.Bridge.Approval).Answer(approval, "reject", "web", ..#ANSWERER, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK)
	Do $$$AssertEquals(done, "done", "the answerer rejects the request")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(a, "incident", 1, ..#WAITINCIDENT)
	Do $$$AssertEquals(events.%Size(), 1, "an incident event reaches A's stream")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.ref_"|"_events.%Get(0).payload.state_"|"_events.%Get(0).payload.openVariant, incident_"|open|rejected", "the incident is open, with the variant rejected")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_row.ClosedAt, "open|rejected|", "and so is its row")
	Kill row
	Do ..WaitHoldEnds(approval)
}

Method TestApproveSendsExecuteToFixExecutor()
{
	If '..Ready() Quit
	Set a = ..Session("approve")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	// the incident has a trace session of its own (a number that no real header has)
	Set traceId = ..#SYNTHFIRST + 70000 + ..Number
	If '..HeldRequest(a, "approve", {"TraceHeaderId": (traceId)}, .incident, .approval) Quit

	Set done = ##class(OcuTalon.Bridge.Approval).Answer(approval, "approve", "web", ..#ANSWERER, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK)
	Do $$$AssertEquals(done, "done", "the answerer approves the request")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(a, "incident", 1, ..#WAITINCIDENT)
	Do $$$AssertEquals(events.%Size(), 1, "an incident event reaches A's stream")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.ref_"|"_events.%Get(0).payload.state, incident_"|fixing", "the incident is fixing")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_row.ClosedAt, "fixing||", "and so is its row")
	Kill row

	// the real send: one Execute header from IncidentManager to FixExecutor in the incident's trace session, read once FixExecutor has handled it
	Set end = $ZHorolog + ..#WAITINCIDENT
	Set sent = []
	While $ZHorolog < end {
		Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(traceId), 1, ..#MANAGER, ..#FIXEXECUTOR)
		If (sent.%Size() '= 0) && ..Handled(sent.%Get(0).status) Quit
		Hang 0.2
	}
	Do $$$AssertEquals(sent.%Size(), 1, "one request header goes from IncidentManager to FixExecutor, in the incident's trace session")
	If sent.%Size() '= 1 Quit
	Set header = sent.%Get(0)
	Do $$$AssertTrue(..Handled(header.status), "and FixExecutor has handled it (status "_header.status_")")
	Do $$$AssertEquals(header.bodyClass, "OcuTalon.Fix.Msg.Execute", "its body is an Execute")
	Set body = ##class(OcuTalon.Fix.Msg.Execute).%OpenId(header.bodyId)
	Do $$$AssertTrue($IsObject(body) && (body.ApprovalRef = approval), "which carries the Ref of the approved request")
	Do $$$AssertEquals(header.superSession, trace, "with the SuperSession kept")
	Set answers = []
	Set end = $ZHorolog + ..#NOANSWERSECONDS
	While (answers.%Size() = 0) && ($ZHorolog < end) {
		Set answers = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(traceId), 2, ..#FIXEXECUTOR, ..#MANAGER)
		If answers.%Size() = 0 Hang 0.2
	}
	Do $$$AssertEquals(answers.%Size(), 0, "and no answer comes back to IncidentManager: none was wanted")
	Do ..WaitHoldEnds(approval)
}

/// --- helpers ---
/// The set-up of the hold tests: Case.ApprovalReady (the production is ready, the answerer holds OcuTalonUser, the ApprovalRole default of Decide is set aside
/// and put back after the test; else this gives 0); a fixture incident of the session, awaiting approval, with the fields after the
/// defaults, in a production of the name; and a real fix request for it (Approval.Raise with the probe sink and ResultTarget IncidentManager), listed in the
/// incident's RequestRefs and held (its task exists). incident and approval are their Refs; 1 when the set-up is done.
Method HeldRequest(session As %String, name As %String, fields As %DynamicObject, Output incident As %String, Output approval As %String) As %Boolean [ Private ]
{
	Set (incident, approval) = ""
	If '..ApprovalReady() Quit 0

	Set all = {"State": "awaiting_approval", "OpenVariant": ""}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.key, .value) {
			Do all.%Set(key, value)
		}
	}
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(session, ##class(OcuTalon.Data.Time).NowUtc(), ..#SYNTHNS, ..#SYNTH_"."_name_..Number, all)
	Set request = ##class(OcuTalon.Bridge.Data.ApprovalRequest).%New()
	Set request.Kind = "fix"
	Set request.OwnerRef = session
	Set request.TraceRef = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set request.IncidentRef = incident
	Set request.ResultTarget = ..#MANAGER
	Set request.DryRun = "{""affected"":3,""resend"":3,""leftOut"":0,""field"":""OrderDate"",""before"":""10/24/2026"",""after"":""2026-10-24"",""itemNoun"":""orders""}"
	Set request.FixKind = "zz_fix"
	Set request.FixParameters = "{""field"":""OrderDate""}"
	Set request.FixTargets = "101,102,103"
	Set sc = ##class(OcuTalon.Bridge.Approval).Raise(request, .approval, ..#SINK)
	If approval '= "" Set ^OcuTalonTest("Approval", "refs", approval) = ""
	Do $$$AssertStatusOK(sc, "a fix request is raised for the incident")
	If $$$ISERR(sc) Quit 0
	Kill request
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.RequestRefs = approval
	Do $$$AssertStatusOK(row.%Save(), "the request is listed in the incident's RequestRefs")
	Kill row
	Set task = ##class(OcuTalon.Test.Bridge.Approval).WaitTask(approval, 10)
	Do $$$AssertTrue(task '= "", "the request is held: its task exists")
	Quit (task '= "")
}

/// 1 when a request header's status is one of HANDLED.
ClassMethod Handled(status As %String) As %Boolean [ Private ]
{
	Quit ((","_..#HANDLED_",") [ (","_status_","))
}

/// Waits at most WAITINCIDENT seconds for the hold of the request to end, and asserts that it has.
Method WaitHoldEnds(approval As %String) [ Private ]
{
	Set end = $ZHorolog + ..#WAITINCIDENT
	While (##class(OcuTalon.Bridge.Approval).LiveHold(approval) '= "") && ($ZHorolog < end) {
		Hang 0.2
	}
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).LiveHold(approval), "", "the hold ends")
}

/// A Dismiss of the incident for the session.
Method Dismissal(session As %String, incident As %String) As OcuTalon.Msg.Command.Dismiss [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.Dismiss).%New()
	Set command.SessionRef = session
	Set command.IncidentRef = incident
	Set command.IdempotencyKey = "zzclosing"_..Number_$Piece($Horolog, ",", 2)_session_incident
	Quit command
}

}
