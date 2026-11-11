/// Tests that FixExecutor refuses an Execute that has no approved request behind it (Story 7.3; AD-11, AD-16, AD-22). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21), fresh, with demo mode on, through Test.Watch.Case: they need the running OcuTalon.Production (whose testing switch is off) and the Orders demo production
/// in OCUORDERS, make real failed orders there and fail with the reason where they do not have them. The Execute goes to the real item FixExecutor by name from the
/// SimMailboxIn service, so a wrong run would really resend the incident's failed orders. The incident, its rows and the messages of the test are removed after it.
///   - TestPastExpiryCannotStart (AC 4; DW-384): see the method;
///   - TestNoApprovedRowNoRun (AC 4; the matrix row "Refused"): OcuTalon.Production is running with TestingEnabled 0. For every registered kind (Fix.Kind Classes, partner_warning of Story 23.5 included: nothing is sent to any mailbox), an
///     incident over three real failed orders gets one request of that kind in each state that is not approved and unexpired: pending, rejected, expired, cancelled and
///     executing, a tool_call, and a Ref that has no row. An Execute for each is answered OK by the real item and changes nothing:
///     the row is as it was (every column), no FixRun is written, no FixResult goes to IncidentManager, no copy is made and a snapshot of OCUORDERS shows no change,
///     and one info line names the Ref.
Class OcuTalon.Test.Fix.Refused Extends OcuTalon.Test.Watch.Case
{

Method TestNoApprovedRowNoRun()
{
	If '..Ready() Quit
	Do $$$AssertTrue(##class(Ens.Director).IsProductionRunning(.name) && (name = ..#PRODUCTION), "OcuTalon.Production is running")
	Set production = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
	Do $$$AssertTrue($IsObject(production) && (production.TestingEnabled = 0), "with the testing switch off")
	Set a = ..Session("refused")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	If '..Fail(3, trace) Quit
	Set failed = ..WaitFailed(3)
	If failed.%Size() '= 3 Quit
	Set ids = ..HeaderIds(failed)
	Set incident = ..Fixture(a, ids)
	Set namespaces = $ListBuild(..#ORDERS)
	Set kinds = ##class(OcuTalon.Fix.Kind).Classes()
	Do $$$AssertTrue($ListLength(kinds) > 0, "there is at least one registered kind")
	Set position = 0
	While $ListNext(kinds, position, class) {
		Set kind = $Parameter(class, "NAME")
		Set cases = $ListBuild("pending", "rejected", "expired", "cancelled", "executing", "tool_call", "unknown")
		Set casePosition = 0
		While $ListNext(cases, casePosition, case) {
			Set label = kind_", "_case
			If case = "unknown" {
				Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
			} ElseIf case = "tool_call" {
				Set ref = ..Request(a, incident.Ref, "approved", kind, ids, {"Kind": "tool_call"})
			} Else {
				Set ref = ..Request(a, incident.Ref, case, kind, ids)
			}
			Set whole = ..Whole(ref)
			Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .before)
			Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
			Do $$$AssertStatusOK(..SendExecute(ref, .session), label_": the Execute is handled")
			Do $$$AssertEquals(..Whole(ref), whole, label_": the row is as it was, every column")
			Do $$$AssertEquals(..Runs(incident.Ref).%Size(), 0, label_": no FixRun is written")
			Set results = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(session), 1, ..#EXECUTOR, ..#MANAGER)
			Do $$$AssertEquals(results.%Size(), 0, label_": no FixResult goes to IncidentManager")
			Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .after)
			Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(before, after)
			Do $$$AssertEquals(lines.%Size(), 0, label_": no copy is made and OCUORDERS did not change: "_lines.%ToJSON())
			Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", mark, $Parameter("OcuTalon.Fix.Executor", "LOGREFUSED")_ref)
			Do rs.%Next()
			Do $$$AssertEquals(+rs.%GetData(1), 1, label_": one info line names the Ref")
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", mark, $Parameter("OcuTalon.Fix.Executor", "LOGREFUSED")_ref)
		}
	}
	Do $$$AssertEquals(..Requests(incident.Ref).%Size(), 6 * $ListLength(kinds), "the incident's requests are the six fixture rows of each kind, and the unknown Ref has none")
}

/// An approved request past its ExpiresAt is not refused: it ends as could not start (DW-384, U-161; the matrix row "Past expiry"). A fixing incident of session S over three real failed orders, its first and last failure now, names R, which is
/// approved with an ExpiresAt in 2020, and an Execute for R goes to the real FixExecutor. R is failed, with one FixRun that holds no copy, and one final FixResult of 3/0/0/0/0 with
/// the reason "OcuTalon couldn't start the resend". The incident is resolved and S has one result.couldNotStart Notification, which reads "Nothing was resent: OcuTalon couldn't
/// start the resend. Nothing was changed." The audit log holds one Action entry for R, and nothing in OCUORDERS changed.
Method TestPastExpiryCannotStart()
{
	If '..Ready() Quit
	Set a = ..Session("expired")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	If '..Fail(3, trace) Quit
	Set failed = ..WaitFailed(3)
	If failed.%Size() '= 3 Quit
	Set ids = ..HeaderIds(failed)
	Do ..Watch(a)
	// FirstAt and LastAt are now, so that a heartbeat's quiet sweep (QUIETSECONDS) does not close the incident between its move to resolved and the wait for it (DW-840).
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set row = ..Fixture(a, ids, ..#ORDERS, ..#ORDERSPRODUCTION, "h", {"State": "fixing", "OpenVariant": "", "NoticedAt": (now), "FirstAt": (now), "LastAt": (now)})
	Set incident = row.Ref
	Set ref = ..Request(a, incident, "approved", "repair_resend", ids, {"ExpiresAt": "2020-01-01T00:00:00Z"})
	Set row.RequestRefs = ref
	Do $$$AssertStatusOK(row.%Save(), "the incident names the request")
	Kill row
	Set namespaces = $ListBuild(..#ORDERS)
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .before)
	Set auditMark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertStatusOK(..SendExecute(ref, .session), "the Execute for the expired request is handled")
	Set results = ..WaitFixResults(ref, 1)
	Do $$$AssertEquals(results.%Size(), 1, "one FixResult goes to IncidentManager")
	If results.%Size() = 1 {
		Set result = results.%Get(0)
		Do $$$AssertEquals(result.final_"|"_result.interrupted_"|"_result.total_"|"_result.resent_"|"_result.completed_"|"_result.failedAgain_"|"_result.skipped_"|"_result.unreached_"|"_result.reason, "1|0|3|0|0|0|0|0|"_##class(OcuTalon.Fix.Executor).#NOSTART, "it is final and holds 3/0/0/0/0 with the reason NOSTART")
	}
	Set requests = ..Requests(incident)
	Do $$$AssertEquals(requests.%Size(), 1, "the incident has one request")
	If requests.%Size() = 1 Do $$$AssertEquals(requests.%Get(0).state, "failed", "which is failed")
	Set runs = ..Runs(incident)
	Do $$$AssertEquals(runs.%Size(), 1, "it has one FixRun")
	If runs.%Size() = 1 Do $$$AssertEquals(runs.%Get(0).copies.%Size()_"|"_runs.%Get(0).total_"|"_runs.%Get(0).resent_"|"_(runs.%Get(0).endedAt '= "")_"|"_runs.%Get(0).reason, "0|3|0|1|"_##class(OcuTalon.Fix.Executor).#NOSTART, "which holds no copy, 3 targets and the reason, and has ended")
	Do $$$AssertEquals(..WaitIncidentState(incident, "resolved"), "resolved", "the incident is resolved")
	Set notes = ..WaitResultNotices(incident, 1)
	Do $$$AssertEquals(notes.%Size(), 1, "S has one result Notification")
	If notes.%Size() = 1 {
		Set note = notes.%Get(0)
		Do $$$AssertEquals(note.catalogKey_"|"_note.approvalRef, "result.couldNotStart|"_ref, "result.couldNotStart with the request's Ref")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render(note.catalogKey, note.slots.%ToJSON(), "phone", .sc), "Nothing was resent: OcuTalon couldn't start the resend. Nothing was changed.", "which reads as the UX document has it")
	}
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(auditMark, "OcuTalon", "Action", "", ref, "", 1, 20)
	Do $$$AssertEquals(entries.%Size(), 1, "the audit log holds one Action entry for the request")
	Do ##class(OcuTalon.Test.Fix.Snapshot).Take(namespaces, .after)
	Set lines = ##class(OcuTalon.Test.Fix.Snapshot).Diff(before, after)
	Do $$$AssertEquals(lines.%Size(), 0, "and nothing in OCUORDERS changed: "_lines.%ToJSON())
}

/// --- helpers ---
/// A fix request of the owner for the incident in the state, of the kind (its parameters for the field OrderDate) over the targets, with the fields after the defaults;
/// its Ref. It is removed with the incident (Case.DropIncidentRows).
Method Request(owner As %String, incident As %String, state As %String, kind As %String, targets As %String, fields As %DynamicObject = "") As %String [ Private ]
{
	Set all = {"FixKind": (kind), "FixTargets": (targets), "ResultTarget": "IncidentManager", "AnsweredChannel": "web", "AnsweredAt": "2030-01-01T10:00:00Z"}
	Do all.%Set("FixParameters", {"field": "OrderDate", "sourceFormat": "MM/DD/YYYY", "targetFormat": "YYYY-MM-DD"}.%ToJSON())
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, state, , all)
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ ref
	Quit ref
}

/// Every column of the request's row as text, to compare before and after; "<none>" for a Ref with no row.
ClassMethod Whole(ref As %String) As %String [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT * FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE Ref = ?", ref)
	If 'rs.%Next() Quit "<none>"
	Set text = ""
	For i = 1:1:rs.%ResultColumnCount Set text = text _ rs.%GetData(i) _ $Char(31)
	Quit text
}

}
