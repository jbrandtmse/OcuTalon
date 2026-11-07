/// Tests of the purge of the digest area's coverage rows (Story 17.5; AD-27, DW-646): Digest.Data.CheckRun by RanAt and Digest.Data.Sent by SentAt, each
/// through Bridge.Time.DaysCutoff, and each session's newest digest kept. The rows are fixtures of sessions whose Refs are made here.
///   - TestPurgeKeepsRecent: with 60 days to keep, the rows 61 days old are gone and the rows 59 days old stay;
///   - TestNewestSentIsKept: the only digest of a session stays whatever its age, and of two old ones only the newer stays;
///   - TestStepRunsAll: the Digest area purges the items, the check runs and the digests, through the registry and through the area;
///   - TestRefuses: a day count that is not a whole number of at least 1 is an error that names the table and deletes nothing.
Class OcuTalon.Test.Digest.Purge Extends %UnitTest.TestCase
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

Method TestPurgeKeepsRecent()
{
	Set session = ..Session()
	Set run61 = ..Run(session, 61)
	Set run59 = ..Run(session, 59)
	Set sent61 = ..Sent(session, 61)
	Set sent59 = ..Sent(session, 59)
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.CheckRun).Purge(60), "the check runs are purged")
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Sent).Purge(60), "the digests are purged")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.CheckRun).%ExistsId(run61), 0, "the run 61 days old is gone")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.CheckRun).%ExistsId(run59), 1, "the run 59 days old stays")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.Sent).%ExistsId(sent61), 0, "the digest 61 days old is gone")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.Sent).%ExistsId(sent59), 1, "the digest 59 days old stays")
	Set pinned = 0
	For attempt = 1:1:20 {
		Set before = ##class(OcuTalon.Data.Time).NowUtc()
		Set edge = ..Run(session, 60)
		Set sc = ##class(OcuTalon.Digest.Data.CheckRun).Purge(60)
		If before '= ##class(OcuTalon.Data.Time).NowUtc() Continue
		Set pinned = 1
		Do $$$AssertStatusOK(sc, "a purge within one second of the run's time is OK")
		Do $$$AssertEquals(##class(OcuTalon.Digest.Data.CheckRun).%ExistsId(edge), 1, "the run exactly at the cutoff stays")
		Quit
	}
	Do $$$AssertTrue(pinned, "a purge ran within the second of the cutoff")
	Set newest = ..Sent(session, 1)
	Set pinned = 0
	For attempt = 1:1:20 {
		Set before = ##class(OcuTalon.Data.Time).NowUtc()
		Set edge = ..Sent(session, 60)
		Set sc = ##class(OcuTalon.Digest.Data.Sent).Purge(60)
		If before '= ##class(OcuTalon.Data.Time).NowUtc() Continue
		Set pinned = 1
		Do $$$AssertStatusOK(sc, "a digest purge within one second of the digest's time is OK")
		Do $$$AssertEquals(##class(OcuTalon.Digest.Data.Sent).%ExistsId(edge)_"|"_##class(OcuTalon.Digest.Data.Sent).%ExistsId(newest), "1|1", "the digest exactly at the cutoff stays")
		Quit
	}
	Do $$$AssertTrue(pinned, "a digest purge ran within the second of the cutoff")
}

Method TestNewestSentIsKept()
{
	Set only = ..Session()
	Set lone = ..Sent(only, 100)
	Set two = ..Session()
	Set older = ..Sent(two, 100)
	Set newer = ..Sent(two, 90)
	Set recent = ..Session()
	Set old = ..Sent(recent, 80)
	Set now = ..Sent(recent, 1)
	Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Sent).Purge(60), "the digests are purged")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.Sent).%ExistsId(lone), 1, "the only digest of a session stays, though it is 100 days old")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.Sent).%ExistsId(older), 0, "of two old digests the older goes")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.Sent).%ExistsId(newer), 1, "and the newer stays")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.Sent).%ExistsId(old), 0, "an old digest goes when a newer one exists")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.Sent).%ExistsId(now), 1, "and the newer one stays")
}

Method TestStepRunsAll()
{
	Set session = ..Session()
	Set item = ##class(OcuTalon.Test.Digest.Store).NewRow(session, ##class(OcuTalon.Bridge.Ids).NewRef(), ##class(OcuTalon.Test.Digest.Store).AgoUtc(61 * 86400), .sc)
	Do $$$AssertStatusOK(sc, "an item 61 days old")
	Set run = ..Run(session, 61)
	Set kept = ..Sent(session, 59)
	Set sent = ..Sent(session, 61)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Registry).Purge(60), "Registry.Purge(60) is OK")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.Item).%ExistsId(item.%Id()), 0, "the item is gone")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.CheckRun).%ExistsId(run), 0, "the run is gone")
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.Sent).%ExistsId(sent)_"|"_##class(OcuTalon.Digest.Data.Sent).%ExistsId(kept), "0|1", "the older digest is gone and the newest stays")
}

Method TestRefuses()
{
	Set session = ..Session()
	Set run = ..Run(session, 400)
	Set sent = ..Sent(session, 400)
	Set other = ..Sent(session, 500)
	For days = 0, -1, "abc", "", 1.5 {
		Set sc = ##class(OcuTalon.Install.Step.Digest).Purge(days)
		Do $$$AssertStatusNotOK(sc, "'"_days_"' days is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Digest.Data.Item.Purge", "and the status names the first table: "_$SYSTEM.Status.GetErrorText(sc))
		Do $$$AssertStatusNotOK(##class(OcuTalon.Digest.Data.CheckRun).Purge(days), "the check runs refuse it")
		Do $$$AssertStatusNotOK(##class(OcuTalon.Digest.Data.Sent).Purge(days), "and so do the digests")
	}
	Do $$$AssertEquals(##class(OcuTalon.Digest.Data.CheckRun).%ExistsId(run)_"|"_##class(OcuTalon.Digest.Data.Sent).%ExistsId(sent)_"|"_##class(OcuTalon.Digest.Data.Sent).%ExistsId(other), "1|1|1", "nothing was deleted")
}

/// --- helpers ---
Method Session() As %String
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Quit ref
}

/// A check run of the session finished that many days ago; its id.
Method Run(session As %String, days As %Integer) As %String
{
	Quit ##class(OcuTalon.Test.Install.Retention).NewRun(session, ##class(OcuTalon.Test.Digest.Store).AgoUtc(days * 86400))
}

/// A digest of the session sent that many days ago; its id.
Method Sent(session As %String, days As %Integer) As %String
{
	Quit ##class(OcuTalon.Test.Install.Retention).NewSent(session, ##class(OcuTalon.Test.Digest.Store).AgoUtc(days * 86400))
}

}
