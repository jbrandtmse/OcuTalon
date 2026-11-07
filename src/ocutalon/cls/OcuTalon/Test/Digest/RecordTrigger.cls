/// Tests of the update trigger of OcuTalon.Data.BackgroundCheck that records each run in Digest.Data.CheckRun (Story 17.5; AD-18), beyond
/// Test.Digest.Runs: the trigger runs once for each row whose LastRunAt changes, also in one statement over several rows, and for no other change. The rows are
/// fixtures of sessions made here and removed after each test.
///   - TestMultiRowUpdate: one UPDATE over three rows, one of which already holds the new LastRunAt, records one run for each of the two that changed, each
///     with its own CheckRef and the shared HeaderId; the same UPDATE again records none; a later time records one for each of the three;
///   - TestClearedAndNoHeader: clearing LastRunAt records nothing; a run saved with no header id has an empty HeaderId;
///   - TestRollsBackWithTheUpdate: the run is part of the update's transaction, so a rolled-back update leaves no CheckRun;
///   - TestFailedRecordOnlyWarns: a run that CheckRun refuses (a Result too long for it, stored by an UPDATE that skips the check) leaves the update applied,
///     logs one warning and throws nothing; the next run is recorded;
///   - TestOtherColumnsDoNotRecord: an update of the Result or the Finding alone, and of the NextDueAt, records nothing.
Class OcuTalon.Test.Digest.RecordTrigger Extends %UnitTest.TestCase
{

Property Refs As %String(MAXLEN = "");

Property Sessions As %String(MAXLEN = "");

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

Method Clean()
{
	For i = 1:1:$Length(..Sessions, ",") {
		Set ref = $Piece(..Sessions, ",", i)
		If ref '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.CheckRun WHERE SessionRef = ?", ref)
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Set ..Sessions = ""
}

Method TestMultiRowUpdate()
{
	Set session = ..Session()
	Set first = ..Watch(session, "Zz.TrigA", "")
	Set second = ..Watch(session, "Zz.TrigB", "")
	Set same = ..Watch(session, "Zz.TrigC", "2030-06-01T12:00:00Z")
	Set update = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ?, Result = ?, Finding = ?, LastRunHeaderId = ? WHERE SessionRef = ?", "2030-06-01T12:00:00Z", "passed", "", 41, session)
	Do $$$AssertEquals(update.%SQLCODE, 0, "one UPDATE over the session's three rows is applied")
	Do $$$AssertEquals(..Count(first)_"|"_..Count(second)_"|"_..Count(same), "1|1|0", "a run for each row whose LastRunAt changed, and none for the row that already held the time")
	Set one = ..RunsOf(first).%Get(0)
	Set two = ..RunsOf(second).%Get(0)
	Do $$$AssertEquals(one.checkRef_"|"_one.sessionRef_"|"_one.ranAt_"|"_one.result_"|"_one.headerId, first_"|"_session_"|2030-06-01T12:00:00Z|passed|41", "the first run is its own check's, with the shared values")
	Do $$$AssertEquals(two.checkRef_"|"_two.headerId, second_"|41", "and the second is its own check's")
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ?, Result = ? WHERE SessionRef = ?", "2030-06-01T12:00:00Z", "passed", session)
	Do $$$AssertEquals(..Count(first)_"|"_..Count(second)_"|"_..Count(same), "1|1|0", "the same UPDATE again records none")
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ?, Result = ? WHERE SessionRef = ?", "2030-06-01T12:01:00Z", "failed", session)
	Do $$$AssertEquals(..Count(first)_"|"_..Count(second)_"|"_..Count(same), "2|2|1", "a later time records one run for each of the three")
	Set last = ..RunsOf(same).%Get(0)
	Do $$$AssertEquals(last.ranAt_"|"_last.result, "2030-06-01T12:01:00Z|failed", "with the new time and result")
}

Method TestClearedAndNoHeader()
{
	Set session = ..Session()
	Set ref = ..Watch(session, "Zz.TrigClear", "")
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ?, Result = ? WHERE Ref = ?", "2030-06-01T12:00:00Z", "passed", ref)
	Set runs = ..RunsOf(ref)
	Do $$$AssertEquals(runs.%Size(), 1, "a run saved with no header id is recorded")
	Do $$$AssertEquals(runs.%Get(0).headerId, "", "with an empty HeaderId")
	Set clear = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = NULL WHERE Ref = ?", ref)
	Do $$$AssertEquals(clear.%SQLCODE, 0, "LastRunAt is cleared")
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref).LastRunAt, "", "to empty")
	Do $$$AssertEquals(..Count(ref), 1, "clearing it records no run")
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ? WHERE Ref = ?", "2030-06-01T12:05:00Z", ref)
	Do $$$AssertEquals(..Count(ref), 2, "a time set after the clear records one")
}

Method TestRollsBackWithTheUpdate()
{
	Set session = ..Session()
	Set ref = ..Watch(session, "Zz.TrigRollback", "")
	Set level = $TLevel
	TSTART
	Set update = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ?, Result = ? WHERE Ref = ?", "2030-06-01T12:00:00Z", "passed", ref)
	Set inside = ..Count(ref)
	TROLLBACK 1
	Do $$$AssertEquals(update.%SQLCODE, 0, "the update is applied inside the transaction")
	Do $$$AssertEquals(inside, 1, "and its run is recorded there")
	Do $$$AssertEquals($TLevel, level, "the transaction is closed")
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref).LastRunAt, "", "after the rollback the check has no run")
	Do $$$AssertEquals(..Count(ref), 0, "and there is no CheckRun for it")
}

Method TestFailedRecordOnlyWarns()
{
	Set session = ..Session()
	Set ref = ..Watch(session, "Zz.TrigRefused", "")
	Set mark = +$Get(^Ens.Util.LogD)
	Set long = $Justify("", 40)
	Set update = ##class(%SQL.Statement).%ExecDirect(, "UPDATE %NOCHECK OcuTalon_Data.BackgroundCheck SET LastRunAt = ?, Result = ? WHERE Ref = ?", "2030-06-01T12:00:00Z", long, ref)
	Do $$$AssertEquals(update.%SQLCODE, 0, "the update is applied though its run cannot be recorded")
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
	Do $$$AssertEquals(row.LastRunAt, "2030-06-01T12:00:00Z", "the check holds the new LastRunAt")
	Do $$$AssertEquals(..Count(ref), 0, "and no CheckRun was written")
	Set log = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND Text [ ?", mark, "A run of check "_ref_" could not be recorded")
	Do log.%Next()
	Do $$$AssertEquals(log.%GetData(1), 1, "one warning names the check")
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ?, Result = ? WHERE Ref = ?", "2030-06-01T12:01:00Z", "passed", ref)
	Do $$$AssertEquals(..Count(ref), 1, "the next run is recorded")
}

Method TestOtherColumnsDoNotRecord()
{
	Set session = ..Session()
	Set ref = ..Watch(session, "Zz.TrigOther", "2030-06-01T12:00:00Z")
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET Result = ?, Finding = ? WHERE Ref = ?", "failed", "Production stopped", ref)
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET NextDueAt = ? WHERE Ref = ?", "2030-06-01T13:00:00Z", ref)
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET DisplayName = ? WHERE Ref = ?", "Renamed", ref)
	Do $$$AssertEquals(..Count(ref), 0, "an update of the result, the finding, the due time or the name records no run")
}

/// --- helpers ---
Method Session() As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzrectrigger")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Quit ref
}

/// A fixture check of the session whose LastRunAt is the given time (empty for none); its Ref.
Method Watch(session As %String, production As %String, lastRunAt As %String) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, "ZZNS", production, {"LastRunAt": (lastRunAt), "DisplayName": (production)})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

ClassMethod Count(ref As %String) As %Integer
{
	Quit ..RunsOf(ref).%Size()
}

/// The CheckRun rows of the check, oldest first, as {checkRef, sessionRef, ranAt, result, headerId}.
ClassMethod RunsOf(ref As %String) As %DynamicArray
{
	Set runs = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT CheckRef, SessionRef, RanAt, Result, HeaderId FROM OcuTalon_Digest_Data.CheckRun WHERE CheckRef = ? ORDER BY RanAt, ID", ref)
	While result.%Next() {
		Do runs.%Push({"checkRef": (result.%Get("CheckRef")), "sessionRef": (result.%Get("SessionRef")), "ranAt": (result.%Get("RanAt")), "result": (result.%Get("Result")), "headerId": (result.%Get("HeaderId"))})
	}
	Quit runs
}

}
