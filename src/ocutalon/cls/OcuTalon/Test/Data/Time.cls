/// Tests of OcuTalon.Data.Time (Story 0.4, AD-18; ForMessage from Story 0.9) in a process whose TZ is unset and in one set
/// to America/New_York. The process time zone is restored after every test.
Class OcuTalon.Test.Data.Time Extends %UnitTest.TestCase
{

/// The TZ of the process before the tests: -1 when it was undefined.
Property SavedZone As %String;

Method OnBeforeAllTests() As %Status
{
	Set ..SavedZone = $SYSTEM.Process.TimeZone()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..RestoreZone()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..RestoreZone()
	Quit $$$OK
}

/// With TZ unset the instance zone is UTC and a local time equals the UTC time.
Method TestUnsetZone()
{
	Do $SYSTEM.Process.TimeZone("")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).Zone(), "UTC", "the zone is UTC")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal("2026-11-01T06:30:00Z"), "2026-11-01T06:30:00", "a local time equals the UTC time")
}

/// In America/New_York both UTC times of the repeated hour on 2026-11-01 give 01:30, and the spring-forward gap
/// on 2026-03-08 is crossed from 01:30 to 03:30.
Method TestNewYorkZone()
{
	Do $SYSTEM.Process.TimeZone("America/New_York")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).Zone(), "America/New_York", "the zone is America/New_York")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal("2026-11-01T05:30:00Z"), "2026-11-01T01:30:00", "05:30Z is 01:30 daylight time")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal("2026-11-01T06:30:00Z"), "2026-11-01T01:30:00", "06:30Z is 01:30 standard time")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal("2026-03-08T06:30:00Z"), "2026-03-08T01:30:00", "06:30Z is 01:30 before the gap")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal("2026-03-08T07:30:00Z"), "2026-03-08T03:30:00", "07:30Z is 03:30 after the gap")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal("2026-07-01T12:00:00Z"), "2026-07-01T08:00:00", "noon UTC in July is 08:00")
}

/// An empty or unreadable time gives "".
Method TestUnreadableTime()
{
	Do $SYSTEM.Process.TimeZone("America/New_York")
	For utc = "", "junk", "2026-13-45T10:00:00Z", "2026-02-30T00:00:00Z", "2026-11-01T06:30:00", "2026-11-01 06:30:00Z" {
		Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal(utc), "", "'"_utc_"' gives an empty string")
	}
}

/// ForMessage in America/New_York against now = Friday 2026-10-16 14:20 EDT: the local date decides the form (same day,
/// 1 to 6 days before or after, 7 days or more, another year); winter times are EST; an unreadable time gives "" and an
/// empty now means the current time. English names do not depend on the locale.
Method TestForMessage()
{
	Do $SYSTEM.Process.TimeZone("America/New_York")
	Set now = "2026-10-16T18:20:00Z"
	Set cases = $ListBuild($ListBuild("2026-10-16T18:12:00Z", "14:12", "the same local day"))
	Set cases = cases_$ListBuild($ListBuild("2026-10-17T02:00:00Z", "22:00", "02:00Z is 22:00 on the same local day"))
	Set cases = cases_$ListBuild($ListBuild("2026-10-16T04:00:00Z", "00:00", "midnight at the start of the local day"))
	Set cases = cases_$ListBuild($ListBuild("2026-10-15T18:12:00Z", "Thursday at 14:12", "one day before"))
	Set cases = cases_$ListBuild($ListBuild("2026-10-19T14:00:00Z", "Monday at 10:00", "three days ahead"))
	Set cases = cases_$ListBuild($ListBuild("2026-10-10T18:12:00Z", "Saturday at 14:12", "six days before"))
	Set cases = cases_$ListBuild($ListBuild("2026-10-22T18:12:00Z", "Thursday at 14:12", "six days ahead"))
	Set cases = cases_$ListBuild($ListBuild("2026-10-09T18:12:00Z", "Oct 9 at 14:12", "seven days before"))
	Set cases = cases_$ListBuild($ListBuild("2026-10-23T18:12:00Z", "Oct 23 at 14:12", "seven days ahead"))
	Set cases = cases_$ListBuild($ListBuild("2025-12-30T15:00:00Z", "Dec 30, 2025 at 10:00", "another year, in standard time"))
	Set cases = cases_$ListBuild($ListBuild("2027-01-05T15:00:00Z", "Jan 5, 2027 at 10:00", "another year ahead"))
	Set cases = cases_$ListBuild($ListBuild("2026-07-01T12:00:00Z", "Jul 1 at 08:00", "a summer time is EDT"))
	Set cases = cases_$ListBuild($ListBuild("2026-01-05T15:00:00Z", "Jan 5 at 10:00", "a winter time is EST"))
	For i = 1:1:$ListLength(cases) {
		Set case = $ListGet(cases, i)
		Do $$$AssertEquals(##class(OcuTalon.Data.Time).ForMessage($List(case, 1), now), $List(case, 2), $List(case, 3))
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ForMessage("2026-10-17T04:30:00Z", "2026-10-17T03:30:00Z"), "Saturday at 00:30", "the next local day decides, one hour after now")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ForMessage("2026-10-17T03:10:00Z", "2026-10-17T03:30:00Z"), "23:10", "the same local day as 23:30")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ForMessage("2025-12-31T17:00:00Z", "2026-01-02T17:00:00Z"), "Wednesday at 12:00", "a weekday within 6 days across a new year")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ForMessage("2026-01-15T22:30:00Z", "2026-01-15T17:00:00Z"), "17:30", "a winter time on a winter day")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ForMessage("2026-03-08T07:30:00Z", "2026-03-07T17:00:00Z"), "Sunday at 03:30", "the spring-forward gap is crossed")
	For utc = "", "junk", "2026-13-45T10:00:00Z", "2026-11-01T06:30:00", "2026-11-01 06:30:00Z" {
		Do $$$AssertEquals(##class(OcuTalon.Data.Time).ForMessage(utc, now), "", "'"_utc_"' gives an empty string")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ForMessage("2026-10-16T18:12:00Z", "junk"), "", "an unreadable now gives an empty string")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Set text = ##class(OcuTalon.Data.Time).ForMessage(before)
	Set empty = ##class(OcuTalon.Data.Time).ForMessage(before, "")
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Set sameDay = ##class(OcuTalon.Data.Time).ForMessage(before, before)
	Set nextDay = ##class(OcuTalon.Data.Time).ForMessage(before, after)
	Do $$$AssertTrue((text = sameDay) || (text = nextDay), "no now means the current time: "_text)
	Do $$$AssertTrue((empty = sameDay) || (empty = nextDay), "an empty now means the current time: "_empty)
	Set stamp = $ZDateTimeH($Extract(before, 1, 10)_" "_$Extract(before, 12, 19), 3)
	Set twoDaysAgo = $Translate($ZDateTime(($Piece(stamp, ",", 1) - 2)_","_$Piece(stamp, ",", 2), 3), " ", "T")_"Z"
	Do $$$AssertTrue(##class(OcuTalon.Data.Time).ForMessage(twoDaysAgo) ? 1U1.L1" at "2N1":"2N, "an empty now is the current time, so a time two days back has a weekday: "_##class(OcuTalon.Data.Time).ForMessage(twoDaysAgo))
	Do $$$AssertTrue(##class(OcuTalon.Data.Time).ForMessage(twoDaysAgo, "") ? 1U1.L1" at "2N1":"2N, "an explicit empty now gives the same weekday form")
}

/// NowUtc is a UTC time in the stored form, whatever the process zone.
Method TestNowUtc()
{
	Do $SYSTEM.Process.TimeZone("")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Do $SYSTEM.Process.TimeZone("America/New_York")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Do $SYSTEM.Process.TimeZone("")
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertTrue($Match(now, "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"), "NowUtc matches YYYY-MM-DDThh:mm:ssZ")
	Do $$$AssertTrue((before ']] now) && (now ']] after), "NowUtc is UTC in America/New_York too: "_before_" <= "_now_" <= "_after)
}

/// Restores the TZ that the process had before the tests.
Method RestoreZone() [ Private ]
{
	Do $SYSTEM.Process.TimeZone($Select(..SavedZone = -1: "", 1: ..SavedZone))
}

}
