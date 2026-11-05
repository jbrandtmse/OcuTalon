/// Tests of the step 3 drops of OcuTalon.Core.SessionOps.End (Story 34.2; AD-4, AD-21): an online-demo sign-out calls OcuTalon.Docs.DropSession
/// and OcuTalon.Memory.DropSession with the session's SessionRef. Safe on a slot: no production is needed, because the fixture sessions have no
/// chat, reminder, watch or approval request for End to send. The sessions are fixture rows (Test.Data.Fixture), removed before and after.
///   - TestBothDropsCalled: End calls each drop once, with the session's SessionRef, the documents first, and answers ended with the resume hash
///     cleared; another session's SessionRef is never passed;
///   - TestFailingDropFails: a drop that answers an error status or throws makes End answer failed and keeps the resume hash, a warning names the
///     session, and the other drop and the later steps (here a pending approval request's cancel) still run;
///   - TestRealStubsEnd: the real SessionOps with Lane A's DropSession stubs answers ended and clears the resume hash (Story 34.1's stubs
///     return OK and change nothing).
Class OcuTalon.Test.Core.SessionOpsDocuments Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Core.SessionOpsDropProbe";

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("SessionOpsDocumentsRun"))
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("SessionOpsDocuments")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Kill ^OcuTalonTest("SessionOpsDocuments")
	Quit $$$OK
}

/// End calls both drops once, with the session's own SessionRef.
Method TestBothDropsCalled()
{
	Set mine = ..Session("mine"), other = ..Session("other")
	Do ..SetResumeHash(mine, "mine")
	Set probe = ..Probe()
	Set result = ..End(probe, "web_user", mine)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|ended", "Ok 1, ended")
	Do $$$AssertEquals(..Calls(), "documents|"_mine_",memories|"_mine, "both drops were called once, documents first, with the session's SessionRef")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(mine).ResumeHash, "", "the resume hash is cleared")
	Do $$$AssertTrue(##class(OcuTalon.Data.Session).RefIndexOpen(other).%Id() '= "", "another session's row is untouched")
	Do $$$AssertEquals(..Calls() [ other, 0, "and its SessionRef was never passed")
}

/// A failing drop is a failed End that keeps the session resumable and still tries every other step.
Method TestFailingDropFails()
{
	For switch = "documents", "memories" {
		For how = "error", "throw" {
			Kill ^OcuTalonTest("SessionOpsDocuments")
			Set session = ..Session(switch_how)
			Do ..SetResumeHash(session, switch_how)
			Set request = ##class(OcuTalon.Test.Data.Fixture).Approval(session)
			Set probe = ..Probe()
			If switch = "documents" Set probe.FailDocuments = how
			If switch = "memories" Set probe.FailMemories = how
			Set label = "a "_switch_" drop that "_$Select(how = "error": "answers an error", 1: "throws")
			Set text = "the "_switch_" of session "_session_" could not be dropped"
			Set warnings = ..Logged(text)
			Set result = ..End(probe, "web_user", session)
			Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", label_": Ok 0, failed")
			Do $$$AssertEquals(..Calls(), "documents|"_session_",memories|"_session, label_": the other drop still ran")
			Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request).State, "cancelled", label_": a later step still ran, the pending request is cancelled")
			Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(session).ResumeHash, ##class(OcuTalon.Data.Session).Hash(switch_how), label_": the resume hash is kept")
			Do $$$AssertEquals(..Logged(text), warnings + 1, label_": one warning names the session")
		}
	}
}

/// The real SessionOps with the real DropSession stubs ends the session.
Method TestRealStubsEnd()
{
	Set session = ..Session("real")
	Do ..SetResumeHash(session, "real")
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Core.SessionOps", .sc)
	Do $$$AssertStatusOK(sc, "the real SessionOps is made")
	Set result = ..End(probe, "web_user", session)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|ended", "Ok 1, ended")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(session).ResumeHash, "", "the resume hash is cleared")
}

/// --- helpers ---
/// A shadow instance of the drop probe.
Method Probe() As OcuTalon.Test.Core.SessionOpsDropProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Quit probe
}

/// A fixture session of the name. Returns its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Session("zzsessopsdocs"_..Number_name)
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

/// The drops the probe recorded, in order, comma-separated.
Method Calls() As %String [ Private ]
{
	Set calls = ""
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("SessionOpsDocuments", n), 1, call)
		Quit:n=""
		Set calls = calls_$Select(calls = "": "", 1: ",")_call
	}
	Quit calls
}

/// The number of warnings in the production log that carry the text.
Method Logged(text As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Type = 3 AND Text [ ?", text)
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
