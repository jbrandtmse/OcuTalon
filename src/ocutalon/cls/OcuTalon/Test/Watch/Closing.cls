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
/// The rows and events of a test are removed after it, and so are the request, its hold and its task.
Class OcuTalon.Test.Watch.Closing Extends OcuTalon.Test.Watch.Case
{

/// The namespace and the production of the incidents that SendBatch makes: nothing runs there, so the pack has no sample.
Parameter SYNTHNS = "ZZNS";

Parameter SYNTH = "Zz.Closing";

/// The README account that answers (Install.Step.Users USER), the local install's real approver.
Parameter ANSWERER = "ocutalon";

/// The sink of the host events in this process.
Parameter SINK = "OcuTalon.Test.Bridge.ProbeSink";

/// The ApprovalRole row of Decide before the test touched it (RunnerFixture.RememberDefault), "" when the test did not.
Property SavedRole As %List;

Property RoleSaved As %Boolean [ InitialExpression = 0 ];

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..RoleSaved {
		Do ##class(OcuTalon.Test.Bridge.Approval).Clean()
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..SavedRole)
		Set ..RoleSaved = 0
		Set ..SavedRole = ""
	}
	Quit ##super(testname)
}

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
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()
	If reason '= "" {
		Do $$$AssertEquals(reason, "", "the production is ready")
		Quit
	}
	Set user = ..#ANSWERER
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet(user, .roles)
	Set holds = $$$ISOK(sc) && ''$ListFind($ListFromString(roles), "OcuTalonUser")
	Do $$$AssertTrue(holds, "the answerer "_user_" holds OcuTalonUser")
	If 'holds Quit
	Set a = ..Session("hold")
	Set rows = ""
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RememberDefault(.rows, "Decide", "ApprovalRole")
	Set ..SavedRole = rows
	Set ..RoleSaved = 1
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(##class(OcuTalon.Test.Agent.RunnerFixture).DefaultId("Decide", "ApprovalRole"))

	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(a, ##class(OcuTalon.Data.Time).NowUtc(), ..#SYNTHNS, ..#SYNTH_".hold"_..Number, {"State": "awaiting_approval", "OpenVariant": ""})
	Set request = ##class(OcuTalon.Bridge.Data.ApprovalRequest).%New()
	Set request.Kind = "fix"
	Set request.OwnerRef = a
	Set request.TraceRef = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set request.IncidentRef = incident
	Set request.ResultTarget = ..#MANAGER
	Set request.DryRun = "{""affected"":3,""resend"":3,""leftOut"":0,""field"":""OrderDate"",""before"":""10/24/2026"",""after"":""2026-10-24"",""itemNoun"":""orders""}"
	Set sc = ##class(OcuTalon.Bridge.Approval).Raise(request, .approval, ..#SINK)
	If approval '= "" Set ^OcuTalonTest("Approval", "refs", approval) = ""
	Do $$$AssertStatusOK(sc, "a fix request is raised for the incident")
	If $$$ISERR(sc) Quit
	Kill request
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Set row.RequestRefs = approval
	Do $$$AssertStatusOK(row.%Save(), "the request is listed in the incident's RequestRefs")
	Kill row
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Approval).WaitTask(approval, 10) '= "", "the request is held: its task exists")

	Set done = ##class(OcuTalon.Bridge.Approval).Answer(approval, "reject", "web", user, ##class(OcuTalon.Bridge.Ids).NewRef(), .winner, ..#SINK)
	Do $$$AssertEquals(done, "done", "the answerer rejects the request")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(a, "incident", 1, ..#WAITINCIDENT)
	Do $$$AssertEquals(events.%Size(), 1, "an incident event reaches A's stream")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.ref_"|"_events.%Get(0).payload.state_"|"_events.%Get(0).payload.openVariant, incident_"|open|rejected", "the incident is open, with the variant rejected")
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(row.State_"|"_row.OpenVariant_"|"_row.ClosedAt, "open|rejected|", "and so is its row")
	Kill row
	Set end = $ZHorolog + ..#WAITINCIDENT
	While (##class(OcuTalon.Bridge.Approval).LiveHold(approval) '= "") && ($ZHorolog < end) {
		Hang 0.2
	}
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).LiveHold(approval), "", "the hold ends")
}

/// --- helpers ---
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
