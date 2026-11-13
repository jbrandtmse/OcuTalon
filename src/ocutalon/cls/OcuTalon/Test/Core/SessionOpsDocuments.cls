/// Tests of the step 3 drops of OcuTalon.Core.SessionOps.End (Story 34.2; AD-4, AD-21): an online-demo sign-out calls OcuTalon.Docs.DropSession,
/// OcuTalon.Memory.DropSession and OcuTalon.Data.Upload.DropSession with the session's SessionRef. Safe on a slot: no production is needed, because the fixture sessions have no
/// chat, reminder, watch or approval request for End to send. The sessions are fixture rows (Test.Data.Fixture), removed before and after.
///   - TestBothDropsCalled: End calls the documents and memories drops once each, with the session's SessionRef, the documents first, and answers ended with the resume hash
///     cleared; another session's SessionRef is never passed;
///   - TestFailingDropFails: a drop that answers an error status or throws makes End answer failed and keeps the resume hash, a warning names the
///     session, and the other drops (the uploads included) and the later steps (here a pending approval request's cancel) still run;
///   - TestUploadsDropped: End calls the uploads drop once, with the session's SessionRef, and the real Upload.DropSession deletes the session's
///     upload rows and no other session's; an uploads drop that answers an error or throws makes End answer failed, keeps the resume hash and
///     still runs the other drops and the later steps (here a pending approval request's cancel);
///   - TestSentFilesDropped: End calls the sent files drop once, with the session's SessionRef, and the real SentFile.DropSession deletes the session's rows and no other
///     session's; a drop that answers an error or throws makes End answer failed, keeps the resume hash and still runs the other drops and the later steps (Story 25.3);
///   - TestRealStubsEnd: SessionOps (through Test.Core.SessionOpsProbe, which sends no drop to PrecedentOps for a session with no rows) with Lane A's DropSession
///     stubs answers ended and clears the resume hash (Story 34.1's stubs return OK and change nothing).
Class OcuTalon.Test.Core.SessionOpsDocuments Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Core.SessionOpsDropProbe";

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ..DropRecordedUploads()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("SessionOpsDocumentsRun"))
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("SessionOpsDocuments"), ^OcuTalonTest("SessionOpsUploads"), ^OcuTalonTest("SessionOpsSentFiles")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..DropRecordedUploads()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Kill ^OcuTalonTest("SessionOpsDocuments"), ^OcuTalonTest("SessionOpsUploads"), ^OcuTalonTest("SessionOpsSentFiles")
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
}

/// A failing drop is a failed End that keeps the session resumable and still tries every other step.
Method TestFailingDropFails()
{
	For switch = "documents", "memories" {
		For how = "error", "throw" {
			Kill ^OcuTalonTest("SessionOpsDocuments"), ^OcuTalonTest("SessionOpsUploads"), ^OcuTalonTest("SessionOpsSentFiles")
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
			Do $$$AssertEquals(..UploadCalls(), session, label_": the uploads drop still ran")
			Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request).State, "cancelled", label_": a later step still ran, the pending request is cancelled")
			Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(session).ResumeHash, ##class(OcuTalon.Data.Session).Hash(switch_how), label_": the resume hash is kept")
			Do $$$AssertEquals(..Logged(text), warnings + 1, label_": one warning names the session")
		}
	}
}

/// End drops the session's uploads: the call is made with the session's SessionRef, the real drop deletes that session's rows only, and a
/// failing drop fails End without stopping the others.
Method TestUploadsDropped()
{
	Set mine = ..Session("upmine"), other = ..Session("upother")
	Do ..SetResumeHash(mine, "upmine")
	Do ..Seed(mine, 2), ..Seed(other, 1)
	Set probe = ..Probe()
	Set result = ..End(probe, "web_user", mine)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|ended", "Ok 1, ended")
	Do $$$AssertEquals(..UploadCalls(), mine, "the uploads drop was called once, with the session's SessionRef")
	Do $$$AssertEquals(..Uploads(mine)_"|"_..Uploads(other), "0|1", "the session's uploads are deleted and another session's is not")
	For how = "error", "throw" {
		Kill ^OcuTalonTest("SessionOpsDocuments"), ^OcuTalonTest("SessionOpsUploads"), ^OcuTalonTest("SessionOpsSentFiles")
		Set session = ..Session("upfail"_how)
		Do ..SetResumeHash(session, "upfail"_how)
		Set request = ##class(OcuTalon.Test.Data.Fixture).Approval(session)
		Set probe = ..Probe()
		Set probe.FailUploads = how
		Set label = "an uploads drop that "_$Select(how = "error": "answers an error", 1: "throws")
		Set text = "the uploads of session "_session_" could not be dropped"
		Set warnings = ..Logged(text)
		Set result = ..End(probe, "web_user", session)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", label_": Ok 0, failed")
		Do $$$AssertEquals(..Calls(), "documents|"_session_",memories|"_session, label_": the other drops ran")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request).State, "cancelled", label_": a later step still ran, the pending request is cancelled")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(session).ResumeHash, ##class(OcuTalon.Data.Session).Hash("upfail"_how), label_": the resume hash is kept")
		Do $$$AssertEquals(..Logged(text), warnings + 1, label_": one warning names the session")
	}
	Do ##class(OcuTalon.Data.Upload).DropSession(other)
}

/// End drops the session's sent files: the call is made with the session's SessionRef, the real drop deletes that session's rows only, and a failing drop
/// fails End without stopping the others.
Method TestSentFilesDropped()
{
	Set mine = ..Session("sfmine"), other = ..Session("sfother")
	Do ..SetResumeHash(mine, "sfmine")
	Do ..SeedFiles(mine, 2), ..SeedFiles(other, 1)
	Set probe = ..Probe()
	Set result = ..End(probe, "web_user", mine)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|ended", "Ok 1, ended")
	Do $$$AssertEquals(..SentFileCalls(), mine, "the sent files drop was called once, with the session's SessionRef")
	Do $$$AssertEquals(..SentFiles(mine)_"|"_..SentFiles(other), "0|1", "the session's sent files are deleted and another session's is not")
	For how = "error", "throw" {
		Kill ^OcuTalonTest("SessionOpsDocuments"), ^OcuTalonTest("SessionOpsUploads"), ^OcuTalonTest("SessionOpsSentFiles")
		Set session = ..Session("sffail"_how)
		Do ..SetResumeHash(session, "sffail"_how)
		Set request = ##class(OcuTalon.Test.Data.Fixture).Approval(session)
		Set probe = ..Probe()
		Set probe.FailSentFiles = how
		Set label = "a sent files drop that "_$Select(how = "error": "answers an error", 1: "throws")
		Set text = "the sent files of session "_session_" could not be dropped"
		Set warnings = ..Logged(text)
		Set result = ..End(probe, "web_user", session)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", label_": Ok 0, failed")
		Do $$$AssertEquals(..Calls(), "documents|"_session_",memories|"_session, label_": the other drops ran")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request).State, "cancelled", label_": a later step still ran, the pending request is cancelled")
		Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(session).ResumeHash, ##class(OcuTalon.Data.Session).Hash("sffail"_how), label_": the resume hash is kept")
		Do $$$AssertEquals(..Logged(text), warnings + 1, label_": one warning names the session")
	}
	Do ##class(OcuTalon.Data.SentFile).DropSession(other)
}

/// SessionOps with the real DropSession stubs ends the session. The probe leaves the documents, memories and uploads drops as they are and sends nothing to PrecedentOps.
Method TestRealStubsEnd()
{
	Set session = ..Session("real")
	Do ..SetResumeHash(session, "real")
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.SessionOpsProbe", .sc)
	Do $$$AssertStatusOK(sc, "SessionOps is made")
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
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzsessopsdocs"_..Number_name)
	Set ^OcuTalonTest("SessionOpsDocumentsRefs", ref) = 1
	Quit ref
}

/// Deletes the upload rows of every session that Session made (a test that stopped early leaves them), and forgets the sessions.
Method DropRecordedUploads() [ Private ]
{
	Set ref = ""
	For {
		Set ref = $Order(^OcuTalonTest("SessionOpsDocumentsRefs", ref))
		Quit:ref=""
		Do ##class(OcuTalon.Data.Upload).DropSession(ref)
		Do ##class(OcuTalon.Data.SentFile).DropSession(ref)
	}
	Kill ^OcuTalonTest("SessionOpsDocumentsRefs")
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

/// The SessionRefs the uploads drop was called with, in order, comma-separated.
Method UploadCalls() As %String [ Private ]
{
	Set calls = ""
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("SessionOpsUploads", n), 1, call)
		Quit:n=""
		Set calls = calls_$Select(calls = "": "", 1: ",")_call
	}
	Quit calls
}

/// Stores the number of upload rows for the session.
Method Seed(session As %String, count As %Integer) [ Private ]
{
	Set source = ##class(%Stream.TmpBinary).%New()
	Do source.Write("zz")
	For i = 1:1:count {
		Do source.Rewind()
		Do ##class(OcuTalon.Data.Upload).Put(session, source, .sc)
		Do $$$AssertStatusOK(sc, "an upload of the session is stored")
	}
}

/// The number of upload rows of the session.
Method Uploads(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Upload WHERE SessionRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The SessionRefs the sent files drop was called with, in order, comma-separated.
Method SentFileCalls() As %String [ Private ]
{
	Set calls = ""
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("SessionOpsSentFiles", n), 1, call)
		Quit:n=""
		Set calls = calls_$Select(calls = "": "", 1: ",")_call
	}
	Quit calls
}

/// Stores the number of sent file rows for the session.
Method SeedFiles(session As %String, count As %Integer) [ Private ]
{
	For i = 1:1:count {
		Do ##class(OcuTalon.Test.Data.Fixture).SentFile(session)
	}
}

/// The number of sent file rows of the session.
Method SentFiles(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SentFile WHERE SessionRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of warnings in the production log that carry the text.
Method Logged(text As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Type = 3 AND Text [ ?", text)
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
