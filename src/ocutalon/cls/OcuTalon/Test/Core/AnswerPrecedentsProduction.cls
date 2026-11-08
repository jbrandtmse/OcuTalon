/// Tests of the precedents that an approval answer makes, over the running production and the real approval API (Story 41.5; AD-1, AD-21, FR-72). THEY RUN IN
/// THROWAWAY STACKS AND IN CI ONLY (InProduction). Each answer goes through Web.Api.AnswerApproval as AnswersInProduction does: a stand-in request with the body, a CSP
/// session bound to a fixture session of this process's user, and the capture of Test.Web.Api.Written. The fixture requests need a role that this process's user holds
/// (HeldRole). A fixture row has no hold, so each real answer waits the 5 seconds of Approval.CompleteHoldTask for a task that never appears and logs one warning, which
/// the tests remove. The row is written by PrecedentOps after AnswerOps' asynchronous send, so the tests wait for it by its SourceRef, a bounded time.
///   - TestApproveRecords: a fix request on an incident of ZZNS/Zz.Production, approved from the web: one row, approved, key production:ZZNS/Zz.Production,
///     AnsweredChannel web;
///   - TestRejectRecords: a tool_call request rejected from the web: one row, rejected, key tool:<ToolName>;
///   - TestRepeatAndSetting: a second press (409 already_answered) adds no row, and an approved setting request leaves none.
Class OcuTalon.Test.Core.AnswerPrecedentsProduction Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzansprec";

/// The longest to wait for a row, in seconds.
Parameter ROWSECONDS = 20;

/// How long to wait for a row that must not appear, in seconds.
Parameter ABSENTSECONDS = 3;

Method OnAfterAllTests() As %Status
{
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(OcuTalon.Data.Precedent).DropSession($Piece(..Sessions, ",", i))
	}
	Quit ##super()
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Quit $$$OK
}

/// A fix request approved from the web makes one approved row keyed by its incident's production.
Method TestApproveRecords()
{
	If '..Guard() Quit
	Set mine = ..WebSession("approve")
	Set incident = ..Incident(mine)
	Set request = ..Request(mine, "fix", {}, incident)
	Do ..Post(mine, request, "{""action"":""approve"",""channel"":""web""}", .status)
	Do $$$AssertEquals(status, "200 OK", "the answer is 200")
	Set row = ..WaitRow(request)
	Do $$$AssertTrue($IsObject(row), "PrecedentOps wrote a row")
	If $IsObject(row) {
		Do $$$AssertEquals(row.OwnerRef_"|"_row.Answer_"|"_row.MatchKey_"|"_row.AnsweredChannel_"|"_row.Channel, mine_"|approved|production:ZZNS/Zz.Production|web|system", "approved, keyed by the incident's production, from the web")
	}
	Do $$$AssertEquals(..Owned(mine), 1, "and it is the only row")
	Do ..RemoveTaskWarnings(request)
}

/// A tool_call request rejected from the web makes one rejected row keyed by the tool.
Method TestRejectRecords()
{
	If '..Guard() Quit
	Set mine = ..WebSession("reject")
	Set request = ..Request(mine, "tool_call", {"ToolName": "Zz.ProdTool"})
	Do ..Post(mine, request, "{""action"":""reject"",""channel"":""web""}", .status)
	Do $$$AssertEquals(status, "200 OK", "the answer is 200")
	Set row = ..WaitRow(request)
	Do $$$AssertTrue($IsObject(row), "PrecedentOps wrote a row")
	If $IsObject(row) {
		Do $$$AssertEquals(row.OwnerRef_"|"_row.Answer_"|"_row.MatchKey_"|"_row.AnsweredChannel, mine_"|rejected|tool:Zz.ProdTool|web", "rejected, keyed by the tool, from the web")
	}
	Do $$$AssertEquals(..Owned(mine), 1, "and it is the only row")
	Do ..RemoveTaskWarnings(request)
}

/// A second press adds no row, and an approved setting request leaves none.
Method TestRepeatAndSetting()
{
	If '..Guard() Quit
	Set mine = ..WebSession("repeat")
	Set request = ..Request(mine, "tool_call", {"ToolName": "Zz.RepeatTool"})
	Do ..Post(mine, request, "{""action"":""approve"",""channel"":""web""}", .status)
	Do $$$AssertEquals(status, "200 OK", "control: the first press is 200")
	Do $$$AssertTrue($IsObject(..WaitRow(request)), "control: the first press wrote its row")
	Set body = ..Post(mine, request, "{""action"":""reject"",""channel"":""web""}", .status)
	Do $$$AssertEquals(status, "409 Conflict", "a second press is 409")
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "already_answered", "already_answered")
	Hang ..#ABSENTSECONDS
	Set row = ##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(request)
	Do $$$AssertEquals(..Owned(mine)_"|"_$Select($IsObject(row): row.Answer, 1: ""), "1|approved", "still one row, the first answer")
	Set setting = ..Request(mine, "setting", {"DryRun": ("{""key"":""zz.prec.key"",""ownerRef"":"""_mine_""",""old"":""a"",""new"":""b""}")})
	Do ..Post(mine, setting, "{""action"":""approve"",""channel"":""web""}", .status)
	Do $$$AssertEquals(status, "200 OK", "a setting request is approved")
	Hang ..#ABSENTSECONDS
	Do $$$AssertEquals(##class(OcuTalon.Data.Precedent).SourceRefIndexExists(setting)_"|"_..Owned(mine), "0|1", "and leaves no row")
	Do ..RemoveTaskWarnings(request)
	Do ..RemoveTaskWarnings(setting)
}

/// --- helpers ---
/// The Precedent row of the request once PrecedentOps has written it; after ROWSECONDS seconds, "".
Method WaitRow(request As %String) As OcuTalon.Data.Precedent [ Private ]
{
	Set end = $ZHorolog + ..#ROWSECONDS
	Set row = ""
	For {
		Set row = ##class(OcuTalon.Data.Precedent).SourceRefIndexOpen(request)
		If $IsObject(row) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit row
}

/// The number of Precedent rows of the session.
Method Owned(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Precedent WHERE OwnerRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// A fixture session of this process's user (Ownership.SessionRef accepts only a session of the signed-in user).
Method WebSession(name As %String) As %String [ Private ]
{
	Set ref = ..Session(name)
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set row.IrisUser = $Username
	Do $$$AssertStatusOK(row.%Save(), "the fixture session "_name_" belongs to "_$Username)
	Quit ref
}

/// A role that this process's user holds.
ClassMethod HeldRole() As %String [ Private ]
{
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet($Username, .roles)
	Quit $Piece(roles, ",", 1)
}

/// A fixture incident of the session on ZZNS/Zz.Production, recorded for the clean-up. Returns its Ref.
Method Incident(owner As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, , "ZZNS", "Zz.Production")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A pending request of the owner and the kind, with the role that this process's user holds; fields set other properties. Its Ref is kept for the clean-up.
Method Request(owner As %String, kind As %String, fields As %DynamicObject = "", incident As %String = "") As %String [ Private ]
{
	Set all = {"RequiredRole": (..HeldRole()), "Kind": (kind)}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, incident, "pending", , all)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// Calls Web.Api.AnswerApproval for the ref as the session's user with the body, and returns what it wrote; status is the response's.
Method Post(session As %String, ref As %String, json As %String, Output status As %String) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", json)
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzAnswerPrec"_..Number, 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	Set body = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Api", "AnswerApproval", ref)
	Do $$$AssertStatusOK(sc, "AnswerApproval returns OK")
	Set status = %response.Status
	Quit body
}

/// Removes the warning that Approval.CompleteHoldTask logged for the request's missing task.
Method RemoveTaskWarnings(ref As %String) [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Type = 3 AND Text %STARTSWITH ?", "OcuTalon.Bridge.Approval: no open task of "_ref)
}

}
