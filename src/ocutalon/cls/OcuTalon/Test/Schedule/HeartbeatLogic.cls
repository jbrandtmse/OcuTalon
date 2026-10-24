/// Tests of the heartbeat's rules (Story 8.1; AD-18, FR-32) that need no production: OcuTalon.Schedule.Heartbeat Next and Gaps, and the
/// two helpers of OcuTalon.Data.Time that count the minutes (Seconds and AddSeconds). The fixture gap marks are dated 2001, so that
/// no real gap can overlap their windows, and they are deleted after every test. The process time zone is put back after every test.
///   - TestNext: every row of the matrix of the spec through Next: first tick, next minute (the second of a late run included), same
///     minute, one run missed, seven minutes down, an unreadable previous time, a previous time in the future, the hour and the day
///     boundaries, and the repeated hour of a daylight-saving change, where the clock minutes still count real minutes;
///   - TestSeconds and TestAddSeconds: the fixed scale, the same answer in every process zone, "" for an unreadable time, a
///     result that leaves the years the scale covers, and a fraction of a second;
///   - TestGaps: Gaps keeps the gaps that overlap the window (inside, across either end, around it, touching an end), leaves out
///     those before and after it and a gap mark that is not a JSON object, gives them oldest first, and treats an empty bound as open.
Class OcuTalon.Test.Schedule.HeartbeatLogic Extends %UnitTest.TestCase
{

/// The process time zone before the tests: -1 when it was undefined.
Property SavedZone As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..SavedZone = $SYSTEM.Process.TimeZone()
	Do ..DeleteFixtures()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..RestoreZone()
	Do ..DeleteFixtures()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..RestoreZone()
	Do ..DeleteFixtures()
	Quit $$$OK
}

/// Next for every row of the matrix. Each case is $ListBuild(label, previous, now, PreviousTickAt, CatchUp, missed).
Method TestNext()
{
	Set cases = ""
	Set cases = cases _ $ListBuild($ListBuild("first tick: no mark", "", "2001-01-01T12:00:00Z", "", 0, 0))
	Set cases = cases _ $ListBuild($ListBuild("next minute", "2001-01-01T12:00:00Z", "2001-01-01T12:01:00Z", "2001-01-01T12:00:00Z", 0, 0))
	Set cases = cases _ $ListBuild($ListBuild("next minute, a few seconds late", "2001-01-01T12:00:59Z", "2001-01-01T12:01:02Z", "2001-01-01T12:00:59Z", 0, 0))
	Set cases = cases _ $ListBuild($ListBuild("next minute, the last second of it", "2001-01-01T12:00:00Z", "2001-01-01T12:01:59Z", "2001-01-01T12:00:00Z", 0, 0))
	Set cases = cases _ $ListBuild($ListBuild("same minute", "2001-01-01T12:00:10Z", "2001-01-01T12:00:50Z", "2001-01-01T12:00:10Z", 0, 0))
	Set cases = cases _ $ListBuild($ListBuild("same second", "2001-01-01T12:00:10Z", "2001-01-01T12:00:10Z", "2001-01-01T12:00:10Z", 0, 0))
	Set cases = cases _ $ListBuild($ListBuild("one run missed", "2001-01-01T12:00:00Z", "2001-01-01T12:02:00Z", "2001-01-01T12:00:00Z", 1, 1))
	Set cases = cases _ $ListBuild($ListBuild("one run missed, counted by the clock minute", "2001-01-01T12:00:59Z", "2001-01-01T12:02:00Z", "2001-01-01T12:00:59Z", 1, 1))
	Set cases = cases _ $ListBuild($ListBuild("an hour down", "2001-01-01T11:00:00Z", "2001-01-01T12:00:00Z", "2001-01-01T11:00:00Z", 1, 59))
	Set cases = cases _ $ListBuild($ListBuild("the hour boundary", "2001-01-01T11:59:30Z", "2001-01-01T12:00:10Z", "2001-01-01T11:59:30Z", 0, 0))
	Set cases = cases _ $ListBuild($ListBuild("the day boundary", "2001-01-01T23:59:30Z", "2001-01-02T00:00:10Z", "2001-01-01T23:59:30Z", 0, 0))
	Set cases = cases _ $ListBuild($ListBuild("the year boundary, two minutes", "2001-12-31T23:59:00Z", "2002-01-01T00:02:00Z", "2001-12-31T23:59:00Z", 1, 2))
	Set cases = cases _ $ListBuild($ListBuild("a leap day", "2004-02-29T23:59:00Z", "2004-03-01T00:02:00Z", "2004-02-29T23:59:00Z", 1, 2))
	Set cases = cases _ $ListBuild($ListBuild("unreadable previous: garbage", "garbage", "2001-01-01T12:00:00Z", "", 0, 0))
	Set cases = cases _ $ListBuild($ListBuild("unreadable previous: not a date", "2001-02-30T12:00:00Z", "2001-01-01T12:00:00Z", "", 0, 0))
	Set cases = cases _ $ListBuild($ListBuild("unreadable previous: no Z", "2001-01-01T12:00:00", "2001-01-01T12:05:00Z", "", 0, 0))
	Set cases = cases _ $ListBuild($ListBuild("previous in the future", "2001-01-01T12:05:00Z", "2001-01-01T12:00:00Z", "2001-01-01T12:05:00Z", 0, 0))
	Set cases = cases _ $ListBuild($ListBuild("previous a day ahead", "2001-01-02T12:00:00Z", "2001-01-01T12:00:00Z", "2001-01-02T12:00:00Z", 0, 0))
	For i = 1:1:$ListLength(cases) {
		Set case = $List(cases, i)
		Set tick = ##class(OcuTalon.Schedule.Heartbeat).Next($List(case, 2), $List(case, 3), .missed)
		Set label = $List(case, 1)
		Do $$$AssertEquals(tick.TickAt, $List(case, 3), label_": TickAt is now")
		Do $$$AssertEquals(tick.PreviousTickAt, $List(case, 4), label_": PreviousTickAt")
		Do $$$AssertEquals(tick.CatchUp, $List(case, 5), label_": CatchUp")
		Do $$$AssertEquals(missed, $List(case, 6), label_": missed")
		Do $$$AssertEquals(tick.%Id(), "", label_": the tick is not saved")
	}

	Set now = "2001-01-01T12:00:00Z"
	Set previous = ##class(OcuTalon.Data.Time).AddSeconds(now, -420)
	Set tick = ##class(OcuTalon.Schedule.Heartbeat).Next(previous, now, .missed)
	Do $$$AssertEquals(previous, "2001-01-01T11:53:00Z", "control: seven minutes before is built by AddSeconds")
	Do $$$AssertEquals(tick.PreviousTickAt, previous, "seven minutes down: one Tick that names the old tick")
	Do $$$AssertEquals(tick.CatchUp, 1, "seven minutes down: it is a catch-up")
	Do $$$AssertEquals(missed, 6, "seven minutes down: six minutes were missed")
}

/// A repeated hour of a daylight-saving change: 05:59Z and 06:01Z on 2026-11-01 both show 01:xx in America/New_York, and 05:30Z and
/// 06:30Z both show 01:30. The clock minutes are UTC minutes, so the real distance counts, whatever the process zone is.
Method TestNextInOtherZones()
{
	For zone = "America/New_York", "Asia/Kolkata", "Pacific/Auckland" {
		Do $SYSTEM.Process.TimeZone(zone)
		Set tick = ##class(OcuTalon.Schedule.Heartbeat).Next("2026-11-01T05:59:00Z", "2026-11-01T06:01:00Z", .missed)
		Do $$$AssertEquals(missed, 1, zone_": two real minutes across the repeated hour miss one")
		Do $$$AssertEquals(tick.CatchUp, 1, zone_": and it is a catch-up")
		Set tick = ##class(OcuTalon.Schedule.Heartbeat).Next("2026-11-01T05:30:00Z", "2026-11-01T06:30:00Z", .missed)
		Do $$$AssertEquals(missed, 59, zone_": the same local time an hour apart is 59 missed minutes")
		Set tick = ##class(OcuTalon.Schedule.Heartbeat).Next("2026-03-08T06:59:00Z", "2026-03-08T07:00:00Z", .missed)
		Do $$$AssertEquals(missed, 0, zone_": the minute across the spring-forward gap misses none")
	}
}

/// Seconds: the fixed scale (the seconds since Horolog day 0, 1840-12-31), the same in every process zone, and "" for what it cannot read.
Method TestSeconds()
{
	Set time = "OcuTalon.Data.Time"
	Do $$$AssertEquals($ClassMethod(time, "Seconds", "1840-12-31T00:00:00Z"), 0, "Horolog day 0 is second 0")
	Do $$$AssertEquals($ClassMethod(time, "Seconds", "2001-01-01T00:00:00Z"), 58440 * 86400, "2001-01-01 is Horolog day 58440")
	Do $$$AssertEquals($ClassMethod(time, "Seconds", "2001-01-01T01:02:03Z"), (58440 * 86400) + 3723, "the time of day is added")
	Do $$$AssertEquals($ClassMethod(time, "Seconds", "2001-01-02T00:00:00Z") - $ClassMethod(time, "Seconds", "2001-01-01T00:00:00Z"), 86400, "a day is 86400 seconds")
	Do $$$AssertEquals($ClassMethod(time, "Seconds", "2004-03-01T00:00:00Z") - $ClassMethod(time, "Seconds", "2004-02-28T00:00:00Z"), 2 * 86400, "a leap year has a 29th of February")
	Do $$$AssertEquals($ClassMethod(time, "Seconds", "9999-12-31T23:59:59Z"), $Parameter(time, "LASTSECOND"), "the last second the scale covers is LASTSECOND")
	For zone = "", "America/New_York", "Asia/Kolkata", "Pacific/Auckland" {
		Do $SYSTEM.Process.TimeZone(zone)
		Do $$$AssertEquals($ClassMethod(time, "Seconds", "2026-11-01T06:30:00Z") - $ClassMethod(time, "Seconds", "2026-11-01T05:30:00Z"), 3600, "'"_zone_"': the repeated local hour is one real hour")
		Do $$$AssertEquals($ClassMethod(time, "Seconds", "2001-01-01T00:00:00Z"), 58440 * 86400, "'"_zone_"': the zone changes nothing")
	}
	For utc = "", "junk", "2001-01-01", "2001-01-01T00:00:00", "2001-01-01 00:00:00Z", "2001-13-01T00:00:00Z", "2001-02-30T00:00:00Z", "2001-01-01T24:00:00Z", "2001-01-01T00:60:00Z", "2001-01-01T00:00:60Z", "1840-12-30T23:59:59Z" {
		Do $$$AssertEquals($ClassMethod(time, "Seconds", utc), "", "'"_utc_"' is unreadable")
	}
}

/// AddSeconds: a UTC time, in either direction, that Seconds reads back; "" for what it cannot read or make.
Method TestAddSeconds()
{
	Set time = "OcuTalon.Data.Time"
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "2001-01-01T12:00:00Z", 0), "2001-01-01T12:00:00Z", "zero seconds change nothing")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "2001-01-01T12:00:00Z", 60), "2001-01-01T12:01:00Z", "a minute ahead")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "2001-01-01T12:00:00Z", -420), "2001-01-01T11:53:00Z", "seven minutes back")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "2001-01-01T00:00:00Z", -1), "2000-12-31T23:59:59Z", "one second back crosses the year")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "2001-01-01T23:59:59Z", 1), "2001-01-02T00:00:00Z", "one second ahead crosses the day")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "2004-02-28T12:00:00Z", 86400), "2004-02-29T12:00:00Z", "a leap day")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "2001-01-01T12:00:00Z", "90"), "2001-01-01T12:01:30Z", "seconds given as text")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "2001-01-01T12:00:00Z", 1.9), "2001-01-01T12:00:01Z", "a fraction of a second is cut off")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "2001-01-01T12:00:00Z", -1.9), "2001-01-01T11:59:59Z", "also going back")
	For zone = "", "America/New_York", "Asia/Kolkata" {
		Do $SYSTEM.Process.TimeZone(zone)
		Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "2026-11-01T05:30:00Z", 3600), "2026-11-01T06:30:00Z", "'"_zone_"': an hour across the repeated local hour")
		Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "2026-03-08T06:59:00Z", 60), "2026-03-08T07:00:00Z", "'"_zone_"': a minute across the gap")
	}
	Set base = "2026-10-24T13:20:00Z"
	For seconds = -86400, -3600, -61, -1, 0, 1, 59, 60, 3601, 86400 * 400 {
		Set made = $ClassMethod(time, "AddSeconds", base, seconds)
		Do $$$AssertEquals($ClassMethod(time, "Seconds", made) - $ClassMethod(time, "Seconds", base), seconds, "Seconds reads back what AddSeconds made for "_seconds)
	}
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "", 60), "", "an empty time gives ''")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "junk", 60), "", "an unreadable time gives ''")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "2001-02-30T00:00:00Z", 60), "", "a date that does not exist gives ''")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "2001-01-01T12:00:00Z", "soon"), "", "seconds that are no number give ''")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "2001-01-01T12:00:00Z", ""), "", "empty seconds give ''")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "9999-12-31T23:59:59Z", 1), "", "a result after the last second gives ''")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "9999-12-31T23:59:58Z", 1), "9999-12-31T23:59:59Z", "the last second can be made")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "1840-12-31T00:00:00Z", -1), "", "a result before the first second gives ''")
	Do $$$AssertEquals($ClassMethod(time, "AddSeconds", "1840-12-31T00:00:01Z", -1), "1840-12-31T00:00:00Z", "the first second can be made")
}

/// Gaps over fixture gap marks of 2001, for the window 10:00:00Z to 11:00:00Z of 2001-01-01. The gaps that overlap it are the
/// one around it (08:00 to 12:00), the one that ends where the window starts (09:30 to 10:00), the one across its start (09:50 to
/// 10:10), the one inside it (10:20 to 10:30), the one across its end (10:50 to 11:10) and the one that starts where it ends
/// (11:00 to 11:05); the gaps 09:00 to 09:20 and 11:30 to 11:40 do not, and a gap mark that is not a JSON object (no JSON, an array, no end) is left out.
Method TestGaps()
{
	Do ..AddGap("2001-01-01T09:00:00Z", "2001-01-01T09:20:00Z", 19)
	Do ..AddGap("2001-01-01T08:00:00Z", "2001-01-01T12:00:00Z", 239)
	Do ..AddGap("2001-01-01T09:30:00Z", "2001-01-01T10:00:00Z", 29)
	Do ..AddGap("2001-01-01T09:50:00Z", "2001-01-01T10:10:00Z", 19)
	Do ..AddGap("2001-01-01T10:20:00Z", "2001-01-01T10:30:00Z", 9)
	Do ..AddGap("2001-01-01T10:50:00Z", "2001-01-01T11:10:00Z", 19)
	Do ..AddGap("2001-01-01T11:00:00Z", "2001-01-01T11:05:00Z", 4)
	Do ..AddGap("2001-01-01T11:30:00Z", "2001-01-01T11:40:00Z", 9)
	Set unreadable = ##class(OcuTalon.Schedule.Heartbeat).#GAPMARK _ "2001-01-01T10:40:00Z"
	Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).Record(unreadable, "not json"), "a gap mark that holds no JSON is written")
	Set noEnd = ##class(OcuTalon.Schedule.Heartbeat).#GAPMARK _ "2001-01-01T10:45:00Z"
	Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).Record(noEnd, "{""start"":""2001-01-01T10:45:00Z""}"), "and one with no end")
	Set array = ##class(OcuTalon.Schedule.Heartbeat).#GAPMARK _ "2001-01-01T10:46:00Z"
	Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).Record(array, "[""2001-01-01T10:46:00Z"",""2001-01-01T10:47:00Z""]"), "and one that holds a JSON array")

	Set gaps = ##class(OcuTalon.Schedule.Heartbeat).Gaps("2001-01-01T10:00:00Z", "2001-01-01T11:00:00Z")
	Do $$$AssertTrue($IsObject(gaps) && gaps.%IsA("%Library.DynamicArray"), "Gaps is a dynamic array")
	Do $$$AssertEquals(..Starts(gaps), "2001-01-01T08:00:00Z,2001-01-01T09:30:00Z,2001-01-01T09:50:00Z,2001-01-01T10:20:00Z,2001-01-01T10:50:00Z,2001-01-01T11:00:00Z", "the window keeps the gaps that overlap it, oldest first")
	Do $$$AssertEquals(gaps.%Get(0).end, "2001-01-01T12:00:00Z", "a gap has its end")
	Do $$$AssertEquals(gaps.%Get(0).missed, 239, "and its minutes missed")
	Do $$$AssertEquals(gaps.%Get(3).%ToJSON(), "{""start"":""2001-01-01T10:20:00Z"",""end"":""2001-01-01T10:30:00Z"",""missed"":9}", "and holds nothing else")
	Do $$$AssertEquals(gaps.%Get(0).%GetTypeOf("missed"), "number", "missed is a number")

	Set gaps = ##class(OcuTalon.Schedule.Heartbeat).Gaps("2001-01-01T10:25:00Z", "2001-01-01T10:26:00Z")
	Do $$$AssertEquals(..Starts(gaps), "2001-01-01T08:00:00Z,2001-01-01T10:20:00Z", "a window inside a gap keeps the gap that spans it and the one around it")
	Set gaps = ##class(OcuTalon.Schedule.Heartbeat).Gaps("2001-01-01T09:21:00Z", "2001-01-01T09:29:00Z")
	Do $$$AssertEquals(..Starts(gaps), "2001-01-01T08:00:00Z", "a window between two gaps keeps only the one around it")
	Set gaps = ##class(OcuTalon.Schedule.Heartbeat).Gaps("2001-01-01T12:01:00Z", "2001-01-01T12:02:00Z")
	Do $$$AssertEquals(..Starts(gaps), "", "a window after every gap keeps none")
	Set gaps = ##class(OcuTalon.Schedule.Heartbeat).Gaps("2001-01-01T07:00:00Z", "2001-01-01T07:59:59Z")
	Do $$$AssertEquals(..Starts(gaps), "", "a window before every gap keeps none")
	Set gaps = ##class(OcuTalon.Schedule.Heartbeat).Gaps("2001-01-01T09:21:00Z", "2001-01-01T09:29:59Z")
	Do $$$AssertEquals(..Starts(gaps), "2001-01-01T08:00:00Z", "a window that ends just before a gap does not reach it")
	Set gaps = ##class(OcuTalon.Schedule.Heartbeat).Gaps("", "2001-01-01T09:25:00Z")
	Do $$$AssertEquals(..Starts(gaps), "2001-01-01T08:00:00Z,2001-01-01T09:00:00Z", "an empty start leaves the window open before")
	Set gaps = ##class(OcuTalon.Schedule.Heartbeat).Gaps("2001-01-01T11:20:00Z", "")
	Do $$$AssertEquals(..Starts(gaps, "2001-"), "2001-01-01T08:00:00Z,2001-01-01T11:30:00Z", "an empty end leaves the window open after (real gaps of this install are left out of the comparison)")
	Set gaps = ##class(OcuTalon.Schedule.Heartbeat).Gaps("2001-01-01T00:00:00Z", "2001-01-01T23:59:59Z")
	Do $$$AssertEquals(..Starts(gaps), "2001-01-01T08:00:00Z,2001-01-01T09:00:00Z,2001-01-01T09:30:00Z,2001-01-01T09:50:00Z,2001-01-01T10:20:00Z,2001-01-01T10:50:00Z,2001-01-01T11:00:00Z,2001-01-01T11:30:00Z", "the whole day keeps every readable gap")
}

/// The gap mark of a gap {start, end, missed}, written as Heartbeat.Record writes it; the name of the mark.
Method AddGap(start As %String, end As %String, missed As %Integer) As %String [ Private ]
{
	Set name = ##class(OcuTalon.Schedule.Heartbeat).#GAPMARK _ start
	Set sc = ##class(OcuTalon.Data.StatusMark).Record(name, {"start": (start), "end": (end), "missed": (missed)}.%ToJSON())
	Do $$$AssertStatusOK(sc, "the fixture gap mark "_name_" is written")
	Quit name
}

/// The starts of the gaps of a Gaps answer, as a comma list; with a prefix, only those that begin with it.
ClassMethod Starts(gaps As %DynamicArray, prefix As %String = "") As %String
{
	Set starts = ""
	Set iterator = gaps.%GetIterator()
	While iterator.%GetNext(, .gap) {
		If ($Extract(gap.start, 1, $Length(prefix)) = prefix) Set starts = starts _ $Select(starts = "": "", 1: ",") _ gap.start
	}
	Quit starts
}

/// Deletes every gap mark dated 2001, which only these tests write.
ClassMethod DeleteFixtures()
{
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT Mark FROM OcuTalon_Data.StatusMark WHERE Mark %STARTSWITH ?", ##class(OcuTalon.Schedule.Heartbeat).#GAPMARK _ "2001-")
	While rows.%Next() {
		Set marks($Increment(marks)) = rows.%GetData(1)
	}
	For i = 1:1:+$Get(marks) {
		Do ##class(OcuTalon.Data.StatusMark).Record(marks(i), "")
	}
}

/// Puts the process time zone back as it was before the tests.
Method RestoreZone()
{
	Do $SYSTEM.Process.TimeZone($Select(..SavedZone = -1: "", 1: ..SavedZone))
}

}
