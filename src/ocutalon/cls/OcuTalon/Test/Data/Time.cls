/// Tests of OcuTalon.Data.Time (Story 0.4, AD-18) in a process whose TZ is unset and in one set to America/New_York.
/// The process time zone is restored after every test.
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
