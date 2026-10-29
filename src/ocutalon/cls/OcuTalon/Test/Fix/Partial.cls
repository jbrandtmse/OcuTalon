Include Ensemble

/// Tests of the end of a run that did not send everything through (Story 7.4; AD-3, AD-12, AD-15, AD-16, AD-17, AD-26, AD-32). THEY RUN IN THROWAWAY STACKS AND IN
/// CI ONLY (Rule 21), fresh (IncidentManager and FixExecutor are code of the running production, so a warm stack's jobs keep their old code), with demo mode on, through
/// Test.Watch.Case: real failed orders of OCUORDERS, the CI mock as the model, the real FixExecutor dry run, the real Approval.Raise and Approval.Answer, the real hold,
/// IncidentManager and FixExecutor. They fail with the reason where the production, OCUORDERS, demo mode or the ANSWERER account's role is missing. A test waits at
/// most 90 seconds for a diagnosis or the end of a run, WAITRUN seconds for the copies and 20 for the rest (test bounds, not NFR-7). The incidents, requests, holds,
/// tasks and runs of a test, and every message it made in OCUORDERS (the copies included), are removed after it.
///   - TestSomeHadChanged (AC 3; the matrix row "Some had changed"): session S's incident awaits approval with R1 over five failed orders, and two of them are rewritten
///     to the target format before the approval. Three copies are made, of the three that were not rewritten, and the two rewritten orders get none. The FixResult is
///     5/3/3/0/2 with an empty reason, the FixRun stores the same, the Notification is result.skipped and renders "3 of 5 orders went through. 2 had changed since the
///     dry run, so I skipped them; they need a new approval.", and the incident is resolved;
///   - TestCopiesFailAgain (AC 3, AC 4; the matrix row "Copies fail again"): R1 is over three failed orders, and before the approval its FixParameters get the target
///     format DD/MM/YYYY, so that the copies fail at OrdersFromPartner with the incident's own error. The FixResult is 3/3/0/3/0 with the reason "the order date still
///     wasn't accepted" and the Notification renders "0 of 3 orders went through. 3 failed again (the order date still wasn't accepted). I won't retry them without
///     a new approval." The incident's last event and /state list R1 done with that result and its reason. The copies' failures arrive in a FailureBatch of the poller, but
///     IncidentManager takes them for no new failure: the incident's Count, its group's Count and Seen are unchanged, S has no other incident, LaterSince stays empty and
///     no later request comes. R1 gets no other Execute, FixRun or copy, and no header names a copy as resent.
Class OcuTalon.Test.Fix.Partial Extends OcuTalon.Test.Watch.Case
{

/// The longest the end of a run is waited for, in seconds (a test bound, not NFR-7).
Parameter WAITEND = 90;

/// The parameters of the repair that fails again: the date goes to DD/MM/YYYY, which the Orders transform refuses.
Parameter FAILAGAIN = "{""field"":""OrderDate"",""sourceFormat"":""MM/DD/YYYY"",""targetFormat"":""DD/MM/YYYY""}";

Method TestSomeHadChanged()
{
	If '..Raised("changed", .a, .ref, .request, 5) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row
	Set ids = request.fixTargets
	Do $$$AssertEquals($Length(ids, ","), 5, "R1 has five targets")
	If $Length(ids, ",") '= 5 Quit
	Set rewritten = $Piece(ids, ",", 2)_","_$Piece(ids, ",", 4)
	Set kept = $Piece(ids, ",", 1)_","_$Piece(ids, ",", 3)_","_$Piece(ids, ",", 5)
	Do $$$AssertStatusOK(..SetOrderDate($Piece(ids, ",", 2), "2026-10-16"), "the second order is written in the target format")
	Do $$$AssertStatusOK(..SetOrderDate($Piece(ids, ",", 4), "2026-10-16"), "and so is the fourth")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(request.ref, "approve", "web", ..#ANSWERER, a, .winner), "done", "R1 is approved")
	Do $$$AssertEquals(..WaitState(ref, request.ref, "done", ..#WAITEND), "done", "R1 is done")

	Set run = ..RunOf(ref, request.ref)
	Do $$$AssertTrue($IsObject(run), "R1 has a FixRun")
	If '$IsObject(run) Quit
	Do $$$AssertEquals(..Originals(..Copies(ref, request.ref)), kept, "three copies were made, of the three orders that were not rewritten and none of the two that were")
	Do $$$AssertEquals(run.total_"|"_run.resent_"|"_run.completed_"|"_run.failedAgain_"|"_run.skipped_"|"_run.interrupted_"|"_run.reason, "5|3|3|0|2|0|", "the FixRun stores 5/3/3/0/2 and no reason")
	Set results = ..FixResultsOf(trace, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.ApprovalRef_"|"_result.IncidentRef_"|"_result.Final_"|"_result.Interrupted, request.ref_"|"_ref_"|1|0", "it names R1 and the incident and is final")
		Do $$$AssertEquals(result.Total_"|"_result.Resent_"|"_result.Completed_"|"_result.FailedAgain_"|"_result.Skipped_"|"_result.Reason, "5|3|3|0|2|", "with the counts 5, 3, 3, 0 and 2 and an empty reason")
	}
	Do $$$AssertEquals(..WaitIncidentState(ref, "resolved"), "resolved", "the incident is resolved")
	Set notes = ..WaitResults(ref, 1)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one result Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.catalogKey_"|"_note.approvalRef_"|"_note.incidentRef, "result.skipped|"_request.ref_"|"_ref, "of the key skipped, with R1's Ref and the incident's")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc), "3 of 5 orders went through. 2 had changed since the dry run, so I skipped them; they need a new approval.", "which renders as the UX document has it")
	}
	Set last = ..LastIncident(a, ref)
	Do $$$AssertTrue($IsObject(last), "the incident event is on S's stream")
	If $IsObject(last) Do $$$AssertEquals(..ResultOf(last), "5|3|3|0|2|0|", "and lists R1 with the same result")
}

Method TestCopiesFailAgain()
{
	If '..Raised("again", .a, .ref, .request) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Set count = row.Count
	Kill row
	Set group = ..Group(ref)
	Set seen = group.seen
	Set groupCount = group.groups.%Get(0).count
	Do $$$AssertEquals(count_"|"_groupCount_"|"_$Length(seen, ","), "3|3|3", "the incident, its group and its Seen hold the three failures")
	If '..SetFixParameters(request.ref, ..#FAILAGAIN) Quit
	Set since = ..Since()
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(request.ref, "approve", "web", ..#ANSWERER, a, .winner), "done", "R1 is approved")
	Do $$$AssertEquals(..WaitState(ref, request.ref, "done", ..#WAITEND), "done", "R1 is done")

	// the run: three copies that failed again
	Set run = ..RunOf(ref, request.ref)
	Do $$$AssertTrue($IsObject(run), "R1 has a FixRun")
	If '$IsObject(run) Quit
	Set copies = ..Joined(run.copies)
	Do $$$AssertEquals(run.copies.%Size(), 3, "which holds three copies")
	Do $$$AssertEquals(run.total_"|"_run.resent_"|"_run.completed_"|"_run.failedAgain_"|"_run.skipped_"|"_run.interrupted_"|"_run.reason, "3|3|0|3|0|0|the order date still wasn't accepted", "and stores 3/3/0/3/0 with the reason the order date still wasn't accepted")
	Set results = ..FixResultsOf(trace, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.ApprovalRef_"|"_result.IncidentRef_"|"_result.Final_"|"_result.Interrupted, request.ref_"|"_ref_"|1|0", "it names R1 and the incident and is final")
		Do $$$AssertEquals(result.Total_"|"_result.Resent_"|"_result.Completed_"|"_result.FailedAgain_"|"_result.Skipped_"|"_result.Reason, "3|3|0|3|0|the order date still wasn't accepted", "with the counts 3, 3, 0, 3 and 0 and the plain reason")
	}
	Set notes = ..WaitResults(ref, 1)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one result Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.catalogKey_"|"_note.approvalRef_"|"_note.incidentRef, "result.failedAgain|"_request.ref_"|"_ref, "of the key failedAgain, with R1's Ref and the incident's")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc), "0 of 3 orders went through. 3 failed again (the order date still wasn't accepted). I won't retry them without a new approval.", "which renders as the UX document has it")
	}
	Do $$$AssertEquals(..WaitIncidentState(ref, "resolved"), "resolved", "the incident is resolved")

	// the incident event and /state list R1 with the stored result and its reason
	Set expected = "3|3|0|3|0|0|the order date still wasn't accepted"
	Set last = ..WaitResultOf(a, ref, expected)
	Do $$$AssertTrue($IsObject(last), "the incident event is on S's stream")
	If $IsObject(last) Do $$$AssertEquals(last.state_"|"_..Listed(last)_"|"_..ResultOf(last), "resolved|1|"_request.ref_"|done|"_expected, "and lists R1 done with the result 3/3/0/3/0/0 and its reason")
	Set state = ..StateIncident(a, ref)
	Do $$$AssertTrue($IsObject(state), "/state lists the incident")
	If $IsObject(state) Do $$$AssertEquals(..ResultOf(state), expected, "with the same result and reason")

	// the copies' failures reach IncidentManager and are taken for no new failure
	Set batches = ..WaitBatched(since, 3, a)
	Set sent = $ListFromString(..Ids(batches, a))
	Set absent = ""
	For i = 1:1:$Length(copies, ",") {
		If '$ListFind(sent, $Piece(copies, ",", i)) Set absent = absent _ $Piece(copies, ",", i) _ " "
	}
	Do $$$AssertEquals(absent, "", "the poller sent the three copies' failures in FailureBatch messages of S")
	Set end = $ZHorolog + ..#WAITBATCH
	For {
		Set open = 0
		Set batches = ..Batches(since)
		For i = 0:1:batches.%Size() - 1 {
			If batches.%Get(i).status '= $$$eMessageStatusCompleted Set open = open + 1
		}
		If 'open || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(open, 0, "and IncidentManager has handled every batch")
	Do ..Settle()
	Set incidents = ..Incidents(a, ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(incidents.%Size(), 1, "S has no other incident")
	If incidents.%Size() = 1 {
		Set incident = incidents.%Get(0)
		Do $$$AssertEquals(incident.count_"|"_incident.laterSince_"|"_incident.askingSince, count_"||", "the incident's Count is unchanged and its LaterSince and AskingSince are empty")
	}
	Set group = ..Group(ref)
	Do $$$AssertEquals(group.groups.%Get(0).count_"|"_group.seen, groupCount_"|"_seen, "and so are its group's Count and Seen")
	Do $$$AssertEquals(group.count, 1, "and it has no other group")
	Do $$$AssertEquals(..Requests(ref).%Size(), 1, "no later request comes")
	Do $$$AssertEquals(..HeadersBetween(trace, 1, "IncidentManager", "FixExecutor", "OcuTalon.Fix.Msg.Execute"), 1, "R1 had one Execute")
	Do $$$AssertEquals(..Runs(ref).%Size(), 1, "and one FixRun")
	Do $$$AssertEquals(..ResentNames(..OrdersFloor), request.fixTargets, "only the three originals are named as resent by a header, and no copy")
}

/// The ids that the headers of OCUORDERS after the floor name as resent (their Description is "Resent <id>"), comma-separated, in the order of the headers.
ClassMethod ResentNames(floor As %Integer) As %String [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = ..#ORDERS
	Set names = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Description FROM Ens.MessageHeader WHERE ID > ? AND Description %STARTSWITH 'Resent ' ORDER BY ID", floor)
	While rs.%Next() {
		Set names = names _ $Select(names = "": "", 1: ",") _ $Piece($Piece(rs.%GetData(1), " ", 2), ":", 1)
	}
	Quit names
}

/// Waits up to WAITHOLD seconds, polling every half second, until the newest incident event of the incident on S's stream lists the first request with the result
/// (as ResultOf gives it); that event, or "" when there is none.
Method WaitResultOf(session As %String, ref As %String, result As %String) As %DynamicObject [ Private ]
{
	Set end = $ZHorolog + ..#WAITHOLD
	For {
		Set last = ..LastIncident(session, ref)
		If ($IsObject(last) && (..ResultOf(last) = result)) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit last
}

/// The header ids of the run's copies as a dynamic array.
Method Copies(ref As %String, approvalRef As %String) As %DynamicArray [ Private ]
{
	Set run = ..RunOf(ref, approvalRef)
	Quit $Select($IsObject(run): run.copies, 1: [])
}

/// The result Notification messages of the incident, once there are count of them (up to WAITHOLD seconds).
Method WaitResults(ref As %String, count As %Integer) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + ..#WAITHOLD
	For {
		Set notes = ..NoticeBodies(ref, "result")
		If (notes.%Size() '< count) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit notes
}

}
