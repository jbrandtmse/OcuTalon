/// Tests that FixExecutor refuses an Execute that has no approved request behind it (Story 7.3; AD-11, AD-16, AD-22). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21), fresh, with demo mode on, through Test.Watch.Case: they need the running OcuTalon.Production (whose testing switch is off) and the Orders demo production
/// in OCUORDERS, make real failed orders there and fail with the reason where they do not have them. The Execute goes to the real item FixExecutor by name from the
/// SimMailboxIn service, so a wrong run would really resend the incident's failed orders. The incident, its rows and the messages of the test are removed after it.
///   - TestNoApprovedRowNoRun (AC 4; the matrix row "Refused"): OcuTalon.Production is running with TestingEnabled 0. For every registered kind (Fix.Kind Classes), an
///     incident over three real failed orders gets one request of that kind in each state that is not approved and unexpired: pending, rejected, expired, cancelled and
///     executing, an approved one past its ExpiresAt, a tool_call, and a Ref that has no row. An Execute for each is answered OK by the real item and changes nothing:
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
		Set cases = $ListBuild("pending", "rejected", "expired", "cancelled", "executing", "past expiry", "tool_call", "unknown")
		Set casePosition = 0
		While $ListNext(cases, casePosition, case) {
			Set label = kind_", "_case
			If case = "unknown" {
				Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
			} ElseIf case = "past expiry" {
				Set ref = ..Request(a, incident.Ref, "approved", kind, ids, {"ExpiresAt": "2020-01-01T00:00:00Z"})
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
	Do $$$AssertEquals(..Requests(incident.Ref).%Size(), 7 * $ListLength(kinds), "the incident's requests are the seven fixture rows of each kind, and the unknown Ref has none")
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
