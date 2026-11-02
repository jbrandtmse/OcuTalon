/// Tests of the defaults of Test.Data.Fixture's fixture rows that other tests rely on (Story 11.1, DW-349).
///   - TestCheckIsNotDue: a check row made with no NextDueAt field is due CHECKAHEAD seconds from now (within two minutes), so
///     the heartbeat's Checks run leaves it alone; an explicit NextDueAt of "" replaces that default and leaves the row due at once.
/// The session and the rows the test makes are recorded with Fixture and removed with Fixture.Clean(refs) in the test's own
/// clean-up, so that nothing of it stays and no other test's row is touched.
Class OcuTalon.Test.Data.FixtureDefaults Extends %UnitTest.TestCase
{

/// The tolerance, in seconds, around the default due time.
Parameter SLACK = 120;

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("FixtureDefaults", "n"))
	Quit $SYSTEM.Status.OK()
}

/// A check with no NextDueAt field is due an hour ahead; with an explicit "" it is due.
Method TestCheckIsNotDue()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set session = $ClassMethod(fixture, "Session", "zzfixdef"_..Number)
	Set refs = session
	Try {
		Set plain = $ClassMethod(fixture, "Check", session)
		Set refs = refs_","_plain
		Set due = $ClassMethod(fixture, "Check", session, , , {"NextDueAt": ""})
		Set refs = refs_","_due
		Set time = "OcuTalon.Data.Time"
		Set now = $ClassMethod(time, "Seconds", $ClassMethod(time, "NowUtc"))
		Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(plain)
		Do $$$AssertTrue($IsObject(row), "the default check row is stored")
		If $IsObject(row) {
			Set expected = $Parameter(fixture, "CHECKAHEAD")
			Set ahead = $ClassMethod(time, "Seconds", row.NextDueAt) - now
			Do $$$AssertTrue(row.NextDueAt '= "", "the default row has a next due time")
			Do $$$AssertTrue((ahead >= (expected - ..#SLACK)) && (ahead <= (expected + ..#SLACK)), "the default row is due about "_expected_" seconds ahead (is "_ahead_")")
		}
		Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(due)
		Do $$$AssertTrue($IsObject(row), "the check with an explicit empty NextDueAt is stored")
		If $IsObject(row) Do $$$AssertEquals(row.NextDueAt, "", "an explicit empty NextDueAt makes the row due at once")
	} Catch exception {
		Do $$$AssertTrue(0, "the fixture checks are made: "_exception.DisplayString())
	}
	Do $ClassMethod(fixture, "Clean", refs)
}

}
