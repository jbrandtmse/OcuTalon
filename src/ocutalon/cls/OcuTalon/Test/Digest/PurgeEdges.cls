/// Edge tests of the purges of the digest area's coverage rows (Story 17.5; AD-27, DW-646), beyond Test.Digest.Purge. The rows are fixtures of sessions
/// whose Refs are made here and removed after each test.
///   - TestSentTieKeepsOne: two digests of a session sent at the same old time leave exactly one, so the session still has its newest digest;
///   - TestEachPurgeTouchesItsOwnTable: the check-run purge leaves old digests and items, the digest purge leaves old check runs and items, and the item
///     purge leaves old check runs and digests;
///   - TestStepKeepsTheRecentOfEveryTable: the step's purge keeps what is within the days to keep in all three tables, and removes a mixed set by age;
///   - TestStepFirstErrorOrder: an invalid day count gives the status of the first table (the items), whichever table is checked after it.
Class OcuTalon.Test.Digest.PurgeEdges Extends %UnitTest.TestCase
{

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
		If ref = "" Continue
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.CheckRun WHERE SessionRef = ?", ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ?", ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.Item WHERE SessionRef = ?", ref)
	}
	Set ..Sessions = ""
}

Method TestSentTieKeepsOne()
{
	Set session = ..Session()
	Set at = ##class(OcuTalon.Test.Digest.Store).AgoUtc(100 * 86400)
	Set one = ##class(OcuTalon.Test.Install.Retention).NewSent(session, at)
	Set two = ##class(OcuTalon.Test.Install.Retention).NewSent(session, at)
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Sent).Purge(60), "the digests are purged")
	Set count = ##class(OcuTalon.Digest.Data.Sent).%ExistsId(one) + ##class(OcuTalon.Digest.Data.Sent).%ExistsId(two)
	Do $$$AssertEquals(count, 1, "of two digests sent at the same old time exactly one stays")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.Sent).%ExistsId(two), 1, "the one saved last")
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Sent).Purge(60), "a second purge is OK")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.Sent).%ExistsId(two), 1, "and still leaves it")
}

Method TestEachPurgeTouchesItsOwnTable()
{
	Set session = ..Session()
	Set run = ..Run(session, 100)
	Set old = ..Sent(session, 100)
	Set newer = ..Sent(session, 90)
	Set item = ..Item(session, 100)
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.CheckRun).Purge(60), "the check runs are purged")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.CheckRun).%ExistsId(run)_"|"_##class(OcuTalon.Digest.Data.Sent).%ExistsId(old)_"|"_##class(OcuTalon.Digest.Data.Sent).%ExistsId(newer)_"|"_##class(OcuTalon.Digest.Data.Item).%ExistsId(item), "0|1|1|1", "the run is gone and the old digests and the item are untouched")
	Set run = ..Run(session, 100)
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Sent).Purge(60), "the digests are purged")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.CheckRun).%ExistsId(run)_"|"_##class(OcuTalon.Digest.Data.Sent).%ExistsId(old)_"|"_##class(OcuTalon.Digest.Data.Sent).%ExistsId(newer)_"|"_##class(OcuTalon.Digest.Data.Item).%ExistsId(item), "1|0|1|1", "the older digest is gone and the run and the item are untouched")
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Item).Purge(60), "the items are purged")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.CheckRun).%ExistsId(run)_"|"_##class(OcuTalon.Digest.Data.Sent).%ExistsId(newer)_"|"_##class(OcuTalon.Digest.Data.Item).%ExistsId(item), "1|1|0", "the item is gone and the run and the digest are untouched")
}

Method TestStepKeepsTheRecentOfEveryTable()
{
	Set session = ..Session()
	Set runs = ..Run(session, 1)_","_..Run(session, 30)_","_..Run(session, 59)_","_..Run(session, 61)_","_..Run(session, 400)
	Set sents = ..Sent(session, 1)_","_..Sent(session, 30)_","_..Sent(session, 59)_","_..Sent(session, 61)_","_..Sent(session, 400)
	Set items = ..Item(session, 1)_","_..Item(session, 59)_","_..Item(session, 61)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Digest).Purge(60), "the step's purge is OK")
	Do $$$AssertEquals(..Exist("OcuTalon.Digest.Data.CheckRun", runs), "1,1,1,0,0", "check runs: 1, 30 and 59 days old stay; 61 and 400 are gone")
	Do $$$AssertEquals(..Exist("OcuTalon.Digest.Data.Sent", sents), "1,1,1,0,0", "digests: the same, the newest being a recent one")
	Do $$$AssertEquals(..Exist("OcuTalon.Digest.Data.Item", items), "1,1,0", "items: 1 and 59 days old stay, 61 is gone")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Digest).Purge(60), "a second purge is OK")
	Do $$$AssertEquals(..Exist("OcuTalon.Digest.Data.CheckRun", runs), "1,1,1,0,0", "and changes nothing")
}

Method TestStepFirstErrorOrder()
{
	Set session = ..Session()
	Set run = ..Run(session, 400)
	Set sc = ##class(OcuTalon.Install.Step.Digest).Purge("abc")
	Do $$$AssertStatusNotOK(sc, "'abc' days is refused")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue(text [ "OcuTalon.Digest.Data.Item.Purge", "the status is the items': "_text)
	Do $$$AssertTrue(text '[ "CheckRun", "and not the check runs'")
	Do $$$AssertTrue(text '[ "Data.Sent", "nor the digests': "_text)
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.CheckRun).%ExistsId(run), 1, "and nothing was deleted")
}

/// --- helpers ---
Method Session() As %String
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Quit ref
}

Method Run(session As %String, days As %Integer) As %String
{
	Quit ##class(OcuTalon.Test.Install.Retention).NewRun(session, ##class(OcuTalon.Test.Digest.Store).AgoUtc(days * 86400))
}

Method Sent(session As %String, days As %Integer) As %String
{
	Quit ##class(OcuTalon.Test.Install.Retention).NewSent(session, ##class(OcuTalon.Test.Digest.Store).AgoUtc(days * 86400))
}

/// A saved digest item of the session that many days old; its id.
Method Item(session As %String, days As %Integer) As %String
{
	Set item = ##class(OcuTalon.Test.Digest.Store).NewRow(session, ##class(OcuTalon.Bridge.Ids).NewRef(), ##class(OcuTalon.Test.Digest.Store).AgoUtc(days * 86400), .sc)
	Do $$$AssertStatusOK(sc, "an item "_days_" days old")
	Quit item.%Id()
}

/// 1 or 0 for each id of the comma-separated list, comma-separated, for the rows of the class.
ClassMethod Exist(class As %String, ids As %String) As %String
{
	Set text = ""
	For i = 1:1:$Length(ids, ",") {
		Set text = text_$Select(i = 1: "", 1: ",")_$ClassMethod(class, "%ExistsId", $Piece(ids, ",", i))
	}
	Quit text
}

}
