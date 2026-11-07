/// The removal of the digests that a test tick sent far ahead of the clock causes, and the tests that pin it (Story 17.7, DW-816). A Tick whose time is a day or
/// more ahead (Test.Checks.BeatCase Due is two days ahead, and Test.Checks.Turns ticks at a watch's due time a day ahead) reaches Digest through Checks, and
/// Digest queues a scheduled digest for every session on the stack that the tick makes due. The Compose bodies and the Sent rows of those digests have a DueAt
/// in the future, and a Sent row with a future DueAt covers the stack's real scheduled digests (Covered, DueAt at least the due time) for one or two days. The
/// product's due rule is not touched: the tests that send such a tick remove what it caused.
///   - Remove (ClassMethod) waits, for at most the seconds, until Checks and Digest have no message in flight (Opened: a Tick or a Compose of the last ten minutes), then
///     deletes the scheduled Sent rows and Compose bodies whose DueAt is later than the clock, and looks again; it repeats while a message has opened, and answers 1 only
///     when the look after the last deletion found nothing in flight. Count gives how many such rows there are. BeatCase and Test.Checks.Turns call them after
///     every test and assert both that Remove drained and that none is left;
///   - TestOpenedCountsOnlyInFlight (QA): Opened counts a Created, Queued, Delivered or Deferred header to Checks or Digest under ten minutes old, and no other;
///   - TestRemoveWaitsForTheMessage (QA): a queued header that a job completes after 1.5 seconds holds Remove until then, and the row is deleted after it;
///   - TestRemoveSaysWhenItDidNotDrain (QA): a message that stays in flight gives 0;
///   - TestRemovesFutureRows: Remove deletes the future-dated Sent rows and Compose bodies of the stack, a past-dated Sent row and a future-dated row of a
///     requested digest (no DueAt) stay, and Count is 0 afterwards;
///   - TestCountsOnlyFutureRows: Count counts the future-dated scheduled rows and Compose bodies, not the past-dated ones.
/// The pin that the tests that send far-ahead ticks leave no such row is the assertion in the OnAfterOneTest of BeatCase and of Turns, after each of their tests.
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

/// Waits for the messages of Checks and Digest that are in flight (Opened), then deletes the scheduled Sent rows and Compose bodies whose DueAt is later than the
/// clock. A Tick reaches Digest through Checks, and each hand-over creates the next message's header before the one that made it is completed. A Compose with
/// saved items is the one exception: its header is completed while Digest waits for the summary from Decide, which Opened does not count. Its Sent row is
/// written only from that Compose body, so once the body is deleted the late answer finds no request (Ensemble's load of it fails, and Digest records the
/// error) and no row comes of it. The deletion is repeated while a message has opened since the last look. Answers 1 when the last look, after the last
/// deletion, found no message in flight, and 0 when the seconds ran out first (then a late row is possible, and the caller says so).
ClassMethod Remove(seconds As %Integer = {..#WAIT}) As %Boolean
{
	Set end = $ZHorolog + seconds
	Set drained = 0
	For {
		For {
			If '..Open() || ($ZHorolog > end) Quit
			Hang 0.25
		}
		Set now = ##class(OcuTalon.Data.Time).NowUtc()
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.Sent WHERE Kind = 'scheduled' AND DueAt > ?", now)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Msg.Compose WHERE Kind = 'scheduled' AND DueAt > ?", now)
		If '..Open() {
			Set drained = 1
			Quit
		}
		If $ZHorolog > end Quit
	}
	Quit drained
}

/// 1 when Checks or Digest has a message of the last ten minutes that is in flight (Opened), as a Tick is on its way to Digest through Checks.
ClassMethod Open() As %Boolean
{
	Quit ..Opened() '= 0
}

/// The number of messages of the last ten minutes, to Checks or Digest, that are in flight: Created, Queued, Delivered or Deferred. -1 when the headers cannot
/// be read, which counts as in flight (a failed read never ends the wait).
ClassMethod Opened() As %Integer
{
	Set since = $Translate($Extract(##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -60 * ..#MINUTES), 1, 19), "T", " ")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE TargetConfigName IN ('Checks', 'Digest') AND Status IN (1, 2, 3, 6) AND TimeCreated >= ?", since)
	If rs.%SQLCODE < 0 Quit -1
	Do rs.%Next()
	Quit +rs.%GetData(1)
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

/// What Opened gains from one header of the target, the status and the age in seconds: the count with the header minus the count without it. A read is
/// repeated (at most five times) while the stack's own messages change the count between the two reads, so only the header's own effect is measured.
/// -99 when no steady reading was had.
ClassMethod Gain(target As %String, status As %Integer, age As %Integer) As %Integer
{
	Set gain = -99
	For try = 1:1:5 {
		Set before = ..Opened()
		Set header = ##class(Ens.MessageHeader).%New()
		Set header.TimeCreated = $Select(age: ..Earlier(age), 1: $ZDateTime($ZTimeStamp, 3, 1, 3))
		Set header.TimeProcessed = header.TimeCreated
		Set header.SourceConfigName = "zzFutureSent"
		Set header.TargetConfigName = target
		Set header.Type = 1
		Set header.Status = status
		Set header.MessageBodyClassName = "Ens.StringRequest"
		Set sc = header.%Save()
		If $$$ISERR(sc) Quit
		Set id = header.%Id()
		Set with = ..Opened()
		Do ##class(Ens.MessageHeader).%DeleteId(id)
		Set after = ..Opened()
		If (before = after) && (with '= -1) {
			Set gain = with - before
			Quit
		}
	}
	Quit gain
}

/// The UTC time stamp of the given number of seconds ago, as the headers hold it.
ClassMethod Earlier(seconds As %Integer) As %String
{
	Set horolog = $ZTimeStamp
	Set total = ($Piece(horolog, ",", 1) * 86400) + $Piece(horolog, ",", 2) - seconds
	Quit $ZDateTime((total \ 86400)_","_(total # 86400), 3, 1, 3)
}

/// Opened counts a message of Checks or Digest that is Created, Queued, Delivered or Deferred and under ten minutes old, and no other: a Discarded, Suspended,
/// Aborted, Error or Completed one, a message to another item and an old one are not in flight. This is what Remove waits on.
Method TestOpenedCountsOnlyInFlight()
{
	For target = "Checks", "Digest" {
		For status = 1, 2, 3, 6 {
			Do $$$AssertEquals(..Gain(target, status, 0), 1, "a message to "_target_" with status "_status_" is in flight")
		}
		For status = 4, 5, 7, 8, 9 {
			Do $$$AssertEquals(..Gain(target, status, 0), 0, "a message to "_target_" with status "_status_" is not in flight")
		}
	}
	Do $$$AssertEquals(..Gain("zzFutureSentOther", 2, 0), 0, "a queued message to another item is not counted")
	Do $$$AssertEquals(..Gain("Digest", 2, 900), 0, "a queued message that is fifteen minutes old is not counted")
	Do $$$AssertEquals(..Gain("Digest", 2, 300), 1, "and one that is five minutes old is")
}

/// Remove waits while a message is in flight and does not end before it: a queued header to Digest that is completed by another process 1.5 seconds after
/// Remove starts holds Remove for that time, and a future-dated row is deleted after it. The header is completed by a job started here, so the test owns the message.
Method TestRemoveWaitsForTheMessage()
{
	Set session = ..Session()
	Set future = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 172800)
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.TimeCreated = $ZDateTime($ZTimeStamp, 3, 1, 3)
	Set header.SourceConfigName = "zzFutureSent"
	Set header.TargetConfigName = "Digest"
	Set header.Type = 1
	Set header.Status = 2
	Set header.MessageBodyClassName = "Ens.StringRequest"
	Do $$$AssertStatusOK(header.%Save(), "a queued header to Digest is saved")
	Set id = header.%Id()
	Do ..Sent(session, future)
	Job ##class(OcuTalon.Test.Digest.FutureSent).Complete(id, 1.5)
	Set started = $ZHorolog
	Set drained = ..Remove(20)
	Set waited = $ZHorolog - started
	Do ##class(Ens.MessageHeader).%DeleteId(id)
	Do $$$AssertTrue(waited >= 1, "Remove waited for the message ("_waited_" s)")
	Do $$$AssertEquals(drained, 1, "and found nothing in flight afterwards")
	Do $$$AssertEquals(..Rows("OcuTalon_Digest_Data.Sent", session), 0, "the future-dated Sent row is gone")
}

/// Sets the status of the header to Completed after the seconds. Run in a job.
ClassMethod Complete(id As %String, seconds As %Numeric)
{
	Hang seconds
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE Ens.MessageHeader SET Status = 9 WHERE %ID = ?", id)
}

/// Remove answers 0 when a message stays in flight until the seconds run out.
Method TestRemoveSaysWhenItDidNotDrain()
{
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.TimeCreated = $ZDateTime($ZTimeStamp, 3, 1, 3)
	Set header.SourceConfigName = "zzFutureSent"
	Set header.TargetConfigName = "Checks"
	Set header.Type = 1
	Set header.Status = 2
	Set header.MessageBodyClassName = "Ens.StringRequest"
	Do $$$AssertStatusOK(header.%Save(), "a queued header to Checks is saved")
	Set id = header.%Id()
	Set drained = ..Remove(1)
	Do ##class(Ens.MessageHeader).%DeleteId(id)
	Do $$$AssertEquals(drained, 0, "a message still in flight when the time runs out gives 0")
}

/// The number of rows of the table of the session.
ClassMethod Rows(table As %String, session As %String) As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_table_" WHERE SessionRef = ?", session)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

}
