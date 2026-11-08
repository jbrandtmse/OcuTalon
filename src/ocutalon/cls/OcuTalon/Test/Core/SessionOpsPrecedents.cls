/// Tests of End's precedents step of OcuTalon.Core.SessionOps (Story 41.2; AD-4, AD-21): an online-demo sign-out sends one EndSession to PrecedentOps when the session has
/// precedent rows, and PrecedentOps deletes them. Safe on a slot: no production is needed, because the probe (Test.Core.SessionOpsPrecedentsProbe) hands the
/// message to a shadow instance of the real PrecedentOps. The sessions are fixture rows and the Precedent rows are saved directly; the test removes both.
///   - TestEndDropsRows: End answers ended, calls the drop once with the session's Ref, deletes the session's rows, and leaves another session's rows and the
///     seeded rows; the resume hash is cleared;
///   - TestNoRowsSendsNothing: a session with no rows makes no call, and End answers ended;
///   - TestFailedDropFailsEnd: a drop that fails or throws makes End answer failed, keeps the rows and the resume hash, and still runs the other steps (here a pending
///     approval request's cancel); a later End finishes;
///   - TestDropAfterEarlierFailure: when an earlier step (the per-person settings) fails, the drop is still called and deletes the rows, and End answers failed.
Class OcuTalon.Test.Core.SessionOpsPrecedents Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Core.SessionOpsPrecedentsProbe";

/// The run's number.
Property Number As %Integer;

/// The count of sessions made.
Property Count As %Integer [ InitialExpression = 0 ];

/// The Refs of the fixture sessions of the test, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the Precedent rows of the test, comma-separated.
Property Rows As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("SessionOpsPrecedentsRun"))
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Kill ^OcuTalonTest("SessionOpsPrecedents")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Rows, ",") {
		Set ref = $Piece(..Rows, ",", i)
		If ref '= "" {
			Set row = ##class(OcuTalon.Data.Precedent).RefIndexOpen(ref)
			If $IsObject(row) Do ##class(OcuTalon.Data.Precedent).%DeleteId(row.%Id())
		}
	}
	Set ..Rows = ""
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Kill ^OcuTalonTest("SessionOpsPrecedents")
	Quit $$$OK
}

/// End sends one drop for a session with rows; its rows go, and another session's and the seeded rows stay.
Method TestEndDropsRows()
{
	Set mine = ..Session("mine"), other = ..Session("other")
	Do ..SetResumeHash(mine, "mine")
	Do ..Row(mine, "zz.end1@example.com"), ..Row(mine, "zz.end2@example.com"), ..Row(other, "zz.end1@example.com")
	Set seeded = ..Row("eval", "zz.end1@example.com", "zzrunend"_..Number)
	Set probe = ..Probe()
	Set result = ..End(probe, "web_user", mine)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|ended", "Ok 1, ended")
	Do $$$AssertEquals(..Calls(), mine, "the drop was called once, with the session's SessionRef")
	Do $$$AssertEquals(..Owned(mine)_"|"_..Owned(other)_"|"_##class(OcuTalon.Data.Precedent).RefIndexExists(seeded), "0|1|1", "the session's rows are deleted; another session's and the seeded row stay")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(mine).ResumeHash, "", "the resume hash is cleared")
	Do ##class(OcuTalon.Data.Precedent).RemoveRun("zzrunend"_..Number)
}

/// A session with no precedent rows makes no call: the existing End tests need no PrecedentOps.
Method TestNoRowsSendsNothing()
{
	Set mine = ..Session("norows"), other = ..Session("norowsother")
	Do ..Row(other, "zz.norows@example.com")
	Do ..SetResumeHash(mine, "norows")
	Set probe = ..Probe()
	Set result = ..End(probe, "web_user", mine)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|ended", "Ok 1, ended")
	Do $$$AssertEquals(..Calls(), "", "no drop was called")
	Do $$$AssertEquals(..Owned(other), 1, "another session's row stays")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(mine).ResumeHash, "", "the resume hash is cleared")
}

/// A drop that fails or throws makes End failed and keeps the session resumable and its rows; the other steps still run, and a later End finishes.
Method TestFailedDropFailsEnd()
{
	For how = "error", "throw" {
		Kill ^OcuTalonTest("SessionOpsPrecedents")
		Set session = ..Session("fail"_how)
		Do ..Row(session, "zz.fail"_how_"@example.com")
		Do ..SetResumeHash(session, "fail"_how)
		Set request = ##class(OcuTalon.Test.Data.Fixture).Approval(session)
		Set probe = ..Probe()
		Set probe.FailDrop = how
		Set label = "a drop that "_$Select(how = "error": "fails", 1: "throws")
		Set text = "the precedents of session "_session_" were not deleted"
		Set warnings = ..Logged(text)
		Set result = ..End(probe, "web_user", session)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", label_": Ok 0, failed")
		Do $$$AssertEquals(..Owned(session), 1, label_": the row stays")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request).State, "cancelled", label_": the other steps still ran, the pending request is cancelled")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(session).ResumeHash, ##class(OcuTalon.Data.Session).Hash("fail"_how), label_": the resume hash is kept")
		If how = "throw" Do $$$AssertEquals(..Logged(text) - warnings, 1, label_": one warning names the session")
		Set probe.FailDrop = ""
		Set result = ..End(probe, "web_user", session)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|ended", label_": a later End finishes")
		Do $$$AssertEquals(..Owned(session)_"|"_##class(OcuTalon.Data.Session).RefIndexOpen(session).ResumeHash, "0|", label_": and deletes the row and clears the resume hash")
	}
}

/// An earlier step that fails does not skip the precedents step: the drop is called for the session and its rows go, and End answers failed.
Method TestDropAfterEarlierFailure()
{
	Set session = ..Session("early")
	Do ..Row(session, "zz.early@example.com")
	Do ..SetResumeHash(session, "early")
	Set probe = ..Probe()
	Set probe.SettingsAnswer = "error"
	Set result = ..End(probe, "web_user", session)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "an earlier failed step: Ok 0, failed")
	Do $$$AssertEquals(..Calls(), session, "the drop was still called, with the session's SessionRef")
	Do $$$AssertEquals(..Owned(session), 0, "and the session's rows are deleted")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(session).ResumeHash, ##class(OcuTalon.Data.Session).Hash("early"), "the resume hash is kept")
}

/// --- helpers ---
/// A shadow instance of the drop probe.
Method Probe() As OcuTalon.Test.Core.SessionOpsPrecedentsProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Quit probe
}

/// A fixture session of the name, recorded for the clean-up. Returns its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Set ..Count = ..Count + 1
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzsessopsprec"_..Number_name_..Count)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// Saves a Precedent row of the owner, recorded for the clean-up. Returns its Ref. A run Ref makes it a seeded row.
Method Row(owner As %String, key As %String, run As %String = "") As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Precedent).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = owner
	Set row.Channel = "mailbox"
	Set row.MatchKey = key
	Set row.Summary = "zz summary"
	Set row.Outcome = "tellnow"
	Set row.Answer = "noise"
	Set row.AnsweredAt = "2030-01-01T10:00:00Z"
	Set row.SourceRef = row.Ref
	Set row.EvalRunRef = run
	Do $$$AssertStatusOK(row.%Save(), "a fixture row is saved")
	Set ..Rows = ..Rows_$Select(..Rows = "": "", 1: ",")_row.Ref
	Quit row.Ref
}

/// Gives the fixture session a resume hash, the hash of the text.
Method SetResumeHash(session As %String, text As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Set row.ResumeHash = ##class(OcuTalon.Data.Session).Hash(text)
	Do $$$AssertStatusOK(row.%Save(), "the fixture session holds a resume hash")
}

/// Sends an EndSession to the operation and returns its CommandResult.
Method End(operation As OcuTalon.Core.SessionOps, origin As %String, session As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.EndSession).%New()
	Set command.Origin = origin
	Set command.SessionRef = session
	Set sc = operation.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

/// The SessionRefs the drop was called with, in order, comma-separated.
Method Calls() As %String [ Private ]
{
	Set calls = ""
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("SessionOpsPrecedents", n), 1, call)
		Quit:n=""
		Set calls = calls_$Select(calls = "": "", 1: ",")_call
	}
	Quit calls
}

/// The number of Precedent rows of the owner.
Method Owned(owner As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Precedent WHERE OwnerRef = ?", owner)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of warnings in the production log that carry the text.
Method Logged(text As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Type = 3 AND Text [ ?", text)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

}
