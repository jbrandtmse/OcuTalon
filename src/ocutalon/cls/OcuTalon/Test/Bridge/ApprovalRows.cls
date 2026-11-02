/// Fixture approval rows for the bridge tests (Test.Bridge.Approval, Decide, Gate and Runner): a request is built unsaved (NewRow) and saved directly
/// in a state with no hold and no task (Save). Each test class tracks the Refs it saves and deletes them itself.
Class OcuTalon.Test.Bridge.ApprovalRows
{

/// The approver of the fixture rows: the README account (Install.Step.Users USER), the local install's real approver.
Parameter ANSWERER = "ocutalon";

/// An unsaved request of the kind with new OwnerRef and TraceRef. A tool_call holds the call: name, arguments, source and runner (the defaults are
/// the gate fixture's held call zz_gate_held with {"value":1} from ZzGateTool and no runner). A fix has IncidentRef, ResultTarget IncidentManager, a
/// DryRun and the fix's FixKind zz_fix, FixParameters {"field":"OrderDate"} and FixTargets 101,102,103.
ClassMethod NewRow(kind As %String, name As %String = "zz_gate_held", arguments As %String = "{""value"":1}", source As %String = "OcuTalon.Test.Bridge.ZzGateTool", runner As %String = "") As OcuTalon.Bridge.Data.ApprovalRequest
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).%New()
	Set row.Kind = kind
	Set row.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.TraceRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	If kind = "tool_call" {
		Set row.ToolName = name
		Set row.ToolArguments = arguments
		Set row.ToolSource = source
		Set row.Runner = runner
	} Else {
		Set row.IncidentRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set row.ResultTarget = "IncidentManager"
		Set row.DryRun = "{""affected"":3,""resend"":3,""leftOut"":0,""field"":""OrderDate"",""before"":""10/24/2026"",""after"":""2026-10-24"",""itemNoun"":""orders""}"
		Set row.FixKind = "zz_fix"
		Set row.FixParameters = "{""field"":""OrderDate""}"
		Set row.FixTargets = "101,102,103"
	}
	Quit row
}

/// Saves the unsaved row in the state with a new Ref, returned in ref: RequiredRole OcuTalonUser, RaisedAt a minute ago and ExpiresAt expiresIn
/// seconds from now. An answered state (approved, rejected, executing, done, failed) has the answer of answerer over the web half a minute ago, and
/// a finished one (done, failed) its Result and FinishedAt.
ClassMethod Save(row As OcuTalon.Bridge.Data.ApprovalRequest, state As %String, expiresIn As %Integer = 3600, answerer As %String = {..#ANSWERER}, Output ref As %String) As %Status
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set now = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set row.Ref = ref
	Set row.State = state
	Set row.RequiredRole = "OcuTalonUser"
	Set row.RaisedAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(now, -60)
	Set row.ExpiresAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(now, expiresIn)
	If $ListFind($ListBuild("approved", "rejected", "executing", "done", "failed"), state) {
		Set row.AnsweredAction = $Select(state = "rejected": "reject", 1: "approve")
		Set row.AnsweredChannel = "web"
		Set row.AnsweredBy = answerer
		Set row.AnsweredAt = ##class(OcuTalon.Bridge.Time).PlusSeconds(now, -30)
	}
	If (state = "done") || (state = "failed") {
		Set row.Result = state
		Set row.FinishedAt = now
	}
	Quit row.%Save()
}

/// The column of the approval row of the Ref, read again from the database, or "<no row>".
ClassMethod Prop(ref As %String, name As %String) As %String
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	If '$IsObject(row) Quit "<no row>"
	Quit $Property(row, name)
}

}
