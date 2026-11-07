/// The removal of the digests that a test tick sent far ahead of the clock causes, and the tests that pin it (Story 17.7, DW-816). A Tick whose time is a day or
/// more ahead (Test.Checks.BeatCase Due is two days ahead) reaches Digest through Checks, and Digest queues a scheduled digest for every session on the stack
/// that the tick makes due. The Compose bodies and the Sent rows of those digests have a DueAt in the future, and a Sent row with a future DueAt covers the
/// stack's real scheduled digests (Covered, DueAt at least the due time) for one or two days. The product's due rule is not touched: the tests that send such
/// a tick remove what it caused.
///   - Remove (ClassMethod) waits, for at most the seconds, until Checks and Digest have no open message of the last ten minutes (a Tick or a Compose), then deletes the
///     scheduled Sent rows and Compose bodies whose DueAt is later than the clock; Count gives how many such rows there are. BeatCase calls them after every
///     test and asserts that none is left;
///   - TestRemovesFutureRows: Remove deletes the future-dated Sent rows and Compose bodies of the stack, a past-dated Sent row and a future-dated row of a
///     requested digest (no DueAt) stay, and Count is 0 afterwards;
///   - TestCountsOnlyFutureRows: Count counts the future-dated scheduled rows and Compose bodies, not the past-dated ones;
///   - TestNoFutureRowIsLeft: a sweep that no scheduled Sent row or Compose body with a DueAt later than the clock is left on the stack when it runs. The pin of
///     the tests that send far-ahead ticks is the assertion in BeatCase OnAfterOneTest, which runs after each of their tests.
Class OcuTalon.Test.Digest.FutureSent Extends %UnitTest.TestCase
{

/// The seconds that Remove waits for Digest, and the minutes of messages it looks at.
Parameter WAIT = 30;

Parameter MINUTES = 10;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Refs '= "" {
		For i = 1:1:$Length(..Refs, ",") {
			Set ref = $Piece(..Refs, ",", i)
			If ref '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ?", ref)
			If ref '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Msg.Compose WHERE SessionRef = ?", ref)
		}
		Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	}
	Set ..Refs = ""
	Quit $$$OK
}

/// The number of scheduled Sent rows and scheduled Compose bodies, of any session, whose DueAt is later than the clock.
ClassMethod Count() As %Integer
{
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set count = 0
	For table = "OcuTalon_Digest_Data.Sent", "OcuTalon_Digest_Msg.Compose" {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_table_" WHERE Kind = 'scheduled' AND DueAt > ?", now)
		If rs.%SQLCODE < 0 Throw ##class(%Exception.SQL).CreateFromSQLCODE(rs.%SQLCODE, rs.%Message)
		Do rs.%Next()
		Set count = count + rs.%GetData(1)
	}
	Quit count
}

/// Waits for Digest to finish what it was sent in the last ten minutes, then deletes the scheduled Sent rows and Compose bodies whose DueAt is later than the clock.
ClassMethod Remove(seconds As %Integer = {..#WAIT})
{
	Set end = $ZHorolog + seconds
	For {
		If '..Open() || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.Sent WHERE Kind = 'scheduled' AND DueAt > ?", now)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Msg.Compose WHERE Kind = 'scheduled' AND DueAt > ?", now)
}

/// 1 when Checks or Digest has a message of the last ten minutes that is in flight (Created, Queued, Delivered or Deferred), as a Tick is on its way to
/// Digest through Checks.
ClassMethod Open() As %Boolean
{
	Set since = $Translate($Extract(##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -60 * ..#MINUTES), 1, 19), "T", " ")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE TargetConfigName IN ('Checks', 'Digest') AND Status IN (1, 2, 3, 6) AND TimeCreated >= ?", since)
	If rs.%SQLCODE < 0 Quit 0
	Do rs.%Next()
	Quit rs.%GetData(1) > 0
}

/// A scheduled Compose body of the session due at the time.
Method Compose(session As %String, dueAt As %String, kind As %String = "scheduled")
{
	Set compose = ##class(OcuTalon.Digest.Msg.Compose).%New()
	Set compose.SessionRef = session
	Set compose.Kind = kind
	Set compose.DueAt = dueAt
	Set compose.WindowEnd = dueAt
	Set compose.WindowStart = ##class(OcuTalon.Data.Time).AddSeconds(dueAt, -86400)
	Do $$$AssertStatusOK(compose.%Save(), "a "_kind_" Compose is saved")
}

/// A Sent row of the session of the kind due at the time.
Method Sent(session As %String, dueAt As %String, kind As %String = "scheduled")
{
	Set row = ##class(OcuTalon.Digest.Data.Sent).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = session
	Set row.Kind = kind
	Set row.DueAt = dueAt
	Set row.WindowStart = ##class(OcuTalon.Data.Time).AddSeconds(dueAt, -86400)
	Set row.SentAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.CatalogKey = "checks.nothingWatched"
	Set row.Slots = "{}"
	Do $$$AssertStatusOK(row.%Save(), "a "_kind_" Sent row is saved")
}

Method Session() As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzfuture")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

Method TestRemovesFutureRows()
{
	Set session = ..Session()
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set future = ##class(OcuTalon.Data.Time).AddSeconds(now, 172800)
	Set past = ##class(OcuTalon.Data.Time).AddSeconds(now, -172800)
	Set base = ..Count()
	Do ..Sent(session, future)
	Do ..Sent(session, past)
	Do ..Sent(session, "", "requested")
	Do ..Compose(session, future)
	Do ..Compose(session, "", "requested")
	Do $$$AssertEquals(..Count(), base + 2, "control: the future-dated Sent row and Compose body are counted")
	Do ..Remove(0)
	Do $$$AssertEquals(..Count(), 0, "Remove leaves no future-dated scheduled row or Compose body")
	Do $$$AssertEquals(..Rows("OcuTalon_Digest_Data.Sent", session), 2, "the past-dated Sent row and the requested one stay")
	Do $$$AssertEquals(..Rows("OcuTalon_Digest_Msg.Compose", session), 1, "and so does the requested Compose")
}

Method TestCountsOnlyFutureRows()
{
	Set session = ..Session()
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set base = ..Count()
	Do ..Sent(session, ##class(OcuTalon.Data.Time).AddSeconds(now, -60))
	Do ..Compose(session, ##class(OcuTalon.Data.Time).AddSeconds(now, -60))
	Do $$$AssertEquals(..Count(), base, "past-dated rows are not counted")
	Do ..Sent(session, ##class(OcuTalon.Data.Time).AddSeconds(now, 3600))
	Do $$$AssertEquals(..Count(), base + 1, "a Sent row due in an hour is counted")
	Do ..Compose(session, ##class(OcuTalon.Data.Time).AddSeconds(now, 3600))
	Do $$$AssertEquals(..Count(), base + 2, "and so is a Compose body")
}

/// No test that ran before this one left a future-dated scheduled Sent row or Compose body: the tests that send ticks far ahead of the clock remove what the
/// ticks cause (BeatCase).
Method TestNoFutureRowIsLeft()
{
	Do $$$AssertEquals(..Count(), 0, "no scheduled Sent row or Compose body is dated later than the clock")
}

/// The number of rows of the table of the session.
ClassMethod Rows(table As %String, session As %String) As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_table_" WHERE SessionRef = ?", session)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

}
