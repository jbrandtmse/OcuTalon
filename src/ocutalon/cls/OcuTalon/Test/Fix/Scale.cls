Include Ensemble

/// The test of one request over 500 orders (Story 7.4; AC 6; AD-16). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), fresh (IncidentManager and FixExecutor are
/// code of the running production, so a warm stack's jobs keep their old code), with demo mode on, through Test.Watch.Case: 500 real failed orders of OCUORDERS from the
/// partner, the CI mock as the model (its diagnosis scenario), the real FixExecutor dry run, the real Approval.Raise and Approval.Answer, the real hold, IncidentManager
/// and FixExecutor. It fails with the reason where the production, OCUORDERS, demo mode or the ANSWERER account's role is missing. The incident, request, hold, task and
/// run, and every message it made in OCUORDERS (the 500 copies included), are removed after it. The bounds of its waits (test bounds, not NFR-7) are WAITRUN of
/// 120 seconds for the run and for its end.
///   - TestFiveHundredOrders (AC 6; the matrix row "500 orders"): one request over exactly 500 failed orders of session S. The dry run's affected and resend are 500
///     and the request's FixTargets hold 500 ids; once the request is approved, FixExecutor resends 500 copies, all of them complete, the FixRun stores the result
///     500/500/500/0/0, one FixResult has those counts, the incident is resolved and S's one result Notification reads "All 500 orders went through."
Class OcuTalon.Test.Fix.Scale Extends OcuTalon.Test.Watch.Case
{

/// The number of failed orders: the most the poller reads in one poll (Watch.Mark MAXFAILURES).
Parameter ORDERSCOUNT = 500;

/// The longest the run and its end are waited for, in seconds (a test bound, not NFR-7).
Parameter WAITRUN = 120;

Method TestFiveHundredOrders()
{
	If '..Raised("scale", .a, .ref, .request, ..#ORDERSCOUNT) Quit
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Set trace = row.TraceHeaderId
	Kill row
	Set originals = ..Failed(..OrdersFloor)
	Do $$$AssertEquals(originals.%Size(), ..#ORDERSCOUNT, "OCUORDERS holds exactly "_..#ORDERSCOUNT_" failed orders")
	Set dryRun = {}.%FromJSON(request.dryRun)
	Do $$$AssertEquals(dryRun.affected_"|"_dryRun.resend_"|"_dryRun.leftOut, ..#ORDERSCOUNT_"|"_..#ORDERSCOUNT_"|0", "the dry run counts "_..#ORDERSCOUNT_" affected and "_..#ORDERSCOUNT_" to resend")
	Do $$$AssertEquals($Length(request.fixTargets, ","), ..#ORDERSCOUNT, "and the request holds "_..#ORDERSCOUNT_" fixed targets")
	Do $$$AssertEquals(request.fixTargets, ..HeaderIds(originals), "which are the "_..#ORDERSCOUNT_" failed orders, ascending")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Approval).Answer(request.ref, "approve", "web", ..#ANSWERER, a, .winner), "done", "the request is approved")

	Set run = ..WaitRun(ref, request.ref, ..#ORDERSCOUNT, ..#WAITRUN)
	Do $$$AssertTrue($IsObject(run) && (run.copies.%Size() = ..#ORDERSCOUNT), "the FixRun holds "_..#ORDERSCOUNT_" copies")
	If '$IsObject(run) || (run.copies.%Size() '= ..#ORDERSCOUNT) Quit
	Do $$$AssertEquals(..WaitState(ref, request.ref, "done", ..#WAITRUN), "done", "the request is done: its copies are counted")
	Do $$$AssertEquals(..CompletedCount(..#ORDERS, ..Joined(run.copies)), ..#ORDERSCOUNT, "all "_..#ORDERSCOUNT_" copies are Completed")
	Set run = ..RunOf(ref, request.ref)
	Do $$$AssertEquals(run.total_"|"_run.resent_"|"_run.completed_"|"_run.failedAgain_"|"_run.skipped_"|"_run.interrupted_"|"_run.reason, "500|500|500|0|0|0|", "the FixRun stores 500/500/500/0/0")
	Set results = ..FixResultsOf(trace, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.Final_"|"_result.Total_"|"_result.Resent_"|"_result.Completed_"|"_result.FailedAgain_"|"_result.Skipped_"|"_result.Reason, "1|500|500|500|0|0|", "with the counts 500, 500, 500, 0 and 0")
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
		Do $$$AssertEquals(note.catalogKey_"|"_note.approvalRef, "result.allThrough|"_request.ref, "of the key allThrough with the request's Ref")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc), "All 500 orders went through.", "which reads All 500 orders went through.")
	}
}

}
