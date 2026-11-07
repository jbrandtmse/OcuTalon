/// Tests that Checks.Coverage reads each of the five checks.thresholds.* settings from its own key (Story 17.5; AD-19), through
/// Test.Digest.CoverageProbe: Test.Digest.Thresholds pins licenseUsePercent, this class pins the other four and the fall-back to the default for a stored
/// value that is not a number. Every value is written the way Lane B writes it (Data.Setting Set), the 60-second cache is cleared after each write, and
/// every key is put back to the value it held before the class began.
///   - TestDiskFreePercent and TestJournalFreePercent: a free share that passes at the default fails once the key is raised above it, and the other sign does not;
///   - TestQueueMessages and TestQueueWaitMinutes: a queue that is within the default fails once its own key is lowered, and not the other key;
///   - TestNotANumber: a stored value that is not a number reads as the default for that key.
Class OcuTalon.Test.Digest.ThresholdKeys Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Digest.CoverageProbe";

Parameter PREFIX = "checks.thresholds.";

Parameter NAMES = "diskFreePercent,journalFreePercent,licenseUsePercent,queueMessages,queueWaitMinutes";

Parameter DEFAULTS = "10,10,90,100,10";

Parameter FROM = "2030-06-01T11:50:00Z";

Parameter TO = "2030-06-01T12:00:00Z";

Property Refs As %String(MAXLEN = "");

Property Sessions As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Kill ^||ThresholdKeysTest
	For i = 1:1:5 {
		Set key = ..#PREFIX_$Piece(..#NAMES, ",", i)
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		Set ^||ThresholdKeysTest(key) = $ListBuild($IsObject(row), $Select($IsObject(row): row.Value, 1: ""), $Piece(..#DEFAULTS, ",", i))
	}
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do $ClassMethod(..#PROBE, "Reset")
	For i = 1:1:5 {
		Do ##class(OcuTalon.Data.Setting).Set(..#PREFIX_$Piece(..#NAMES, ",", i), $Piece(..#DEFAULTS, ",", i))
	}
	Kill ^||OcuTalon.Setting
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do $ClassMethod(..#PROBE, "Reset")
	Do ..PutBack()
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..PutBack()
	Do ..Clean()
	Kill ^||ThresholdKeysTest
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

/// Puts every key back: its stored value, or the default when it had no row (a start seeds it anyway).
Method PutBack()
{
	Set key = ""
	For {
		Set key = $Order(^||ThresholdKeysTest(key), 1, was)
		Quit:key=""
		Do ##class(OcuTalon.Data.Setting).Set(key, $Select($List(was, 1): $List(was, 2), 1: $List(was, 3)))
	}
	Kill ^||OcuTalon.Setting
}

/// Stores the value of a threshold (a name of NAMES) and clears the cache.
Method Set(name As %String, value As %String)
{
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set(..#PREFIX_name, value), name_" is saved as '"_value_"'")
	Kill ^||OcuTalon.Setting
}

Method TestDiskFreePercent()
{
	Set session = ..Session()
	Set vitals = $ClassMethod(..#PROBE, "Healthy")
	Set vitals.databases = [{"name": "OCUTALON_DATA", "directory": "/zz/d/", "volumeFreePercent": 15, "maxBlocks": 0, "outcome": "read"}]
	Set vitals.journal.freePercent = 15
	Do $ClassMethod(..#PROBE, "Feed", vitals)
	Do ..Built(session, .rows)
	Do $$$AssertEquals(rows.%Get(1).result_"|"_rows.%Get(2).result, "passed|passed", "control: 15% free passes the defaults of 10")
	Do ..Set("diskFreePercent", 20)
	Do ..Built(session, .rows)
	Do $$$AssertEquals(rows.%Get(1).result_"|"_rows.%Get(1).finding, "failed|OCUTALON_DATA 15% free", "diskFreePercent 20: 15% free fails database space")
	Do $$$AssertEquals(rows.%Get(2).result, "passed", "and journal space, which has its own key, still passes")
}

Method TestJournalFreePercent()
{
	Set session = ..Session()
	Set vitals = $ClassMethod(..#PROBE, "Healthy")
	Set vitals.databases = [{"name": "OCUTALON_DATA", "directory": "/zz/d/", "volumeFreePercent": 15, "maxBlocks": 0, "outcome": "read"}]
	Set vitals.journal.freePercent = 15
	Do $ClassMethod(..#PROBE, "Feed", vitals)
	Do ..Set("journalFreePercent", 20)
	Do ..Built(session, .rows)
	Do $$$AssertEquals(rows.%Get(2).result_"|"_rows.%Get(2).finding, "failed|15% free", "journalFreePercent 20: 15% free fails journal space")
	Do $$$AssertEquals(rows.%Get(1).result, "passed", "and database space, which has its own key, still passes")
	Do ..Set("journalFreePercent", 5)
	Set vitals.journal.freePercent = 8
	Do $ClassMethod(..#PROBE, "Feed", vitals)
	Do ..Built(session, .rows)
	Do $$$AssertEquals(rows.%Get(2).result, "passed", "journalFreePercent 5: 8% free passes, where the default of 10 fails it")
}

Method TestQueueMessages()
{
	Set session = ..Session()
	Set watch = ..Watch(session, "Zz.KeysQueue")
	Do $ClassMethod(..#PROBE, "FeedRead", "Zz.KeysQueue", {"queues": [{"name": "A", "count": 6, "oldestAt": (..Ago(30))}]})
	Do ..Built(session, .rows)
	Do $$$AssertEquals(rows.%Get(5).result, "passed", "control: 6 queued messages pass the default of 100")
	Do ..Set("queueMessages", 5)
	Do ..Built(session, .rows)
	Do $$$AssertEquals(rows.%Get(5).result_"|"_rows.%Get(5).finding, "failed|6 messages queued", "queueMessages 5: 6 queued messages fail")
	Do ..Set("queueMessages", 6)
	Do ..Built(session, .rows)
	Do $$$AssertEquals(rows.%Get(5).result, "passed", "queueMessages 6: 6 queued messages are not more than 6")
	Do ..Set("queueMessages", 1)
	Do $ClassMethod(..#PROBE, "FeedRead", "Zz.KeysQueue", {"queues": [{"name": "A", "count": 2, "oldestAt": (..Ago(30))}]})
	Do ..Set("queueWaitMinutes", 1)
	Do ..Built(session, .rows)
	Do $$$AssertEquals(rows.%Get(5).finding, "2 messages queued", "the wait key does not change the count finding: 30 seconds is within one minute")
}

Method TestQueueWaitMinutes()
{
	Set session = ..Session()
	Set watch = ..Watch(session, "Zz.KeysWait")
	Do $ClassMethod(..#PROBE, "FeedRead", "Zz.KeysWait", {"queues": [{"name": "A", "count": 3, "oldestAt": (..Ago(190))}]})
	Do ..Built(session, .rows)
	Do $$$AssertEquals(rows.%Get(5).result, "passed", "control: a message waiting 3 minutes passes the default of 10")
	Do ..Set("queueWaitMinutes", 2)
	Do ..Built(session, .rows)
	Do $$$AssertEquals(rows.%Get(5).result_"|"_rows.%Get(5).finding, "failed|A message waiting 3 minutes", "queueWaitMinutes 2: a message waiting 3 minutes fails")
	Do ..Set("queueWaitMinutes", 4)
	Do ..Built(session, .rows)
	Do $$$AssertEquals(rows.%Get(5).result, "passed", "queueWaitMinutes 4: 3 minutes pass")
}

Method TestNotANumber()
{
	Set session = ..Session()
	Set vitals = $ClassMethod(..#PROBE, "Healthy")
	Set vitals.license.usePercent = 91
	Set vitals.journal.freePercent = 9
	Do $ClassMethod(..#PROBE, "Feed", vitals)
	Do ..Set("licenseUsePercent", "abc")
	Do ..Set("journalFreePercent", "")
	Do ..Built(session, .rows)
	Do $$$AssertEquals(rows.%Get(3).result_"|"_rows.%Get(3).finding, "failed|91% in use", "licenseUsePercent 'abc' reads as the default of 90: 91% fails")
	Do $$$AssertEquals(rows.%Get(2).result_"|"_rows.%Get(2).finding, "failed|9% free", "an empty journalFreePercent reads as the default of 10: 9% free fails")
	Set vitals.license.usePercent = 89
	Set vitals.journal.freePercent = 11
	Do $ClassMethod(..#PROBE, "Feed", vitals)
	Do ..Built(session, .rows)
	Do $$$AssertEquals(rows.%Get(3).result_"|"_rows.%Get(2).result, "passed|passed", "and 89% in use and 11% free pass")
}

/// --- helpers ---
Method Session() As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzthrkeys")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Quit ref
}

/// A production watch of the session that ran every minute through the window and was created before it; its Ref.
Method Watch(session As %String, production As %String) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, "ZZNS", production, {"CreatedAt": "2030-05-01T10:00:00Z", "DisplayName": "Orders"})
	Set ..Refs = ..Refs_","_ref
	For i = 0:1:9 {
		Set at = ##class(OcuTalon.Data.Time).AddSeconds("2030-06-01T11:50:30Z", i * 60)
		Set insert = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO OcuTalon_Digest_Data.CheckRun (CheckRef, SessionRef, RanAt, Result, Reason, Finding) VALUES (?, ?, ?, 'passed', '', '')", ref, session, at)
		Do $$$AssertTrue(insert.%SQLCODE '< 0, "a run is recorded: "_insert.%Message)
	}
	Quit ref
}

Method Built(session As %String, Output rows As %DynamicArray)
{
	Set sc = $ClassMethod(..#PROBE, "Build", session, ..#FROM, ..#TO, .rows, .lines)
	Do $$$AssertStatusOK(sc, "Build is OK")
}

Method Ago(seconds As %Integer) As %String
{
	Quit ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -seconds)
}

}
