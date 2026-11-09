/// Tests of Data.Handled.Purge (Story 18.4; DW-695, AD-14, AD-27): it deletes the Handled rows whose HandledAt is before Bridge.Time.DaysCutoff(daysToKeep)
/// and no others. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY: a purge deletes every old Handled row (and the Core area's, every old unpaired
/// pairing row), so a slot's rows must not be in its way. The rows are made with Refs of the run's number n, from ^OcuTalonTest("HandledPurge","n") (never
/// reset), and every row the tests make is removed in OnAfterAllTests.
///   - TestPurgeDeletesOldRows: a row handled a day before the cutoff goes, one a day after it and a row handled now stay; the answer is OK;
///   - TestCutoffRowStays: a row handled at the cutoff itself stays (the comparison is strictly before it). The cutoff moves with the clock, so a run in which
///     the second changed during the purge is repeated, up to 20 times;
///   - TestBadDayCountsDeleteNothing: "", 0, 00, -1, 1.5 and abc are an error status that names the class, and an old row stays;
///   - TestOtherRowsAreUntouched: a Delivery row and a SimMessage of a session are still there after a purge, and so is a recent Handled row;
///   - TestCoreAreaPurgesHandled: the Core area's Purge (Install.Step.Core, which the purge task calls through the registry) deletes an old Handled row.
Class OcuTalon.Test.Data.HandledPurge Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Refs of the Handled rows of the run, comma-separated.
Property HandledRefs As %String(MAXLEN = "");

/// The Refs of the fixture sessions of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("HandledPurge", "n"))
	Set ..HandledRefs = ""
	Set ..Refs = ""
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	For i = 1:1:$Length(..HandledRefs, ",") {
		Set ref = $Piece(..HandledRefs, ",", i)
		If ref '= "" {
			Set row = ##class(OcuTalon.Data.Handled).RefIndexOpen(ref)
			If $IsObject(row) Do ##class(OcuTalon.Data.Handled).%DeleteId(row.%Id())
		}
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
}

/// A row handled a day before the cutoff of 90 days is deleted, a row handled a day after the cutoff and one handled now stay.
Method TestPurgeDeletesOldRows()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Time).DaysCutoff(90, "test", .cutoff), "the cutoff is made")
	Set old = ..Row("old", ..Shift(cutoff, -1))
	Set inside = ..Row("inside", ..Shift(cutoff, 1))
	Set recent = ..Row("recent", ##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Handled).Purge(90), "Purge(90) is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(old), 0, "the row handled before the cutoff is deleted")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(inside), 1, "the row handled after the cutoff stays")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(recent), 1, "and so does a row handled now")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Handled).Purge(90), "a second Purge(90) is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(inside), 1, "and changes nothing")
}

/// A row handled at the cutoff itself stays. The cutoff is the clock moved back 90 days, so the row is made at the cutoff of the second before the call; when the
/// second has changed by the end of the call the row may legitimately go, and the run is repeated.
Method TestCutoffRowStays()
{
	Set checked = 0
	For attempt = 1:1:20 {
		Do ##class(OcuTalon.Bridge.Time).DaysCutoff(90, "test", .before)
		Set ref = ..Row("edge"_attempt, before)
		Set sc = ##class(OcuTalon.Data.Handled).Purge(90)
		Do ##class(OcuTalon.Bridge.Time).DaysCutoff(90, "test", .after)
		If before '= after {
			Continue
		}
		Do $$$AssertStatusOK(sc, "Purge(90) is OK")
		Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(ref), 1, "a row handled at the cutoff stays")
		Set checked = 1
		Quit
	}
	Do $$$AssertTrue(checked, "the clock stood still for one purge within 20 tries")
}

/// A day count that is not a whole number of at least 1 is an error that names the class, and nothing is deleted.
Method TestBadDayCountsDeleteNothing()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Time).DaysCutoff(90, "test", .cutoff), "the cutoff is made")
	Set old = ..Row("badold", ..Shift(cutoff, -5))
	For days = "", 0, "00", -1, 1.5, "abc" {
		Set sc = ##class(OcuTalon.Data.Handled).Purge(days)
		Do $$$AssertStatusNotOK(sc, "Purge('"_days_"') is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Data.Handled.Purge", "and the error names the class")
		Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(old), 1, "and the old row stays")
	}
	Set sc = ##class(OcuTalon.Data.Handled).Purge()
	Do $$$AssertStatusNotOK(sc, "Purge() with no argument is refused")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(old), 1, "and the old row stays")
}

/// A purge touches Handled rows only: a session's Delivery row and SimMessage, however old, and a recent Handled row stay.
Method TestOtherRowsAreUntouched()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzhpurge"_..Number)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_session
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(session, "phone", "ZzHpurgeMsg"_..Number, "", "handled", "", "ZzHpurgeDecision"_..Number, "", "", .delivery), "a Delivery row is recorded")
	Set delivery.RecordedAt = "2000-01-01T00:00:00Z"
	Do $$$AssertStatusOK(delivery.%Save(), "and made old")
	Set message = ##class(OcuTalon.Data.SimMessage).%New()
	Set message.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set message.SessionRef = session
	Set message.Kind = "phone"
	Set message.Direction = "out"
	Set message.Text = "zz old"
	Set message.CreatedAt = "2000-01-01T00:00:00Z"
	Do $$$AssertStatusOK(message.%Save(), "a SimMessage is saved, made old")
	Set recent = ..Row("others", ##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Handled).Purge(90), "Purge(90) is OK")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount(session), 1, "the Delivery row stays")
	Do $$$AssertEquals(##class(OcuTalon.Data.SimMessage).RefIndexExists(message.Ref), 1, "and so does the SimMessage")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(recent), 1, "and the recent Handled row")
}

/// The Core area's Purge, which the purge task calls through the registry, purges the Handled rows too.
Method TestCoreAreaPurgesHandled()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Time).DaysCutoff(90, "test", .cutoff), "the cutoff is made")
	Set old = ..Row("core", ..Shift(cutoff, -2))
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Core).Purge(90), "the Core area's Purge(90) is OK")
	Do $$$AssertEquals(##class(OcuTalon.Data.Handled).RefIndexExists(old), 0, "the old Handled row is deleted")
}

/// --- helpers ---
/// A Handled row of the name with HandledAt as given (a session of nobody, the channel web); its Ref is kept for the clean-up and returned.
Method Row(name As %String, handledAt As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Handled).%New()
	Set row.Ref = "ZzHp"_..Number_name
	Set row.SessionRef = "ZzHpSession"_..Number
	Set row.Channel = "web"
	Set row.HandledAt = handledAt
	Do $$$AssertStatusOK(row.%Save(), "the Handled row '"_name_"' is saved")
	Set ..HandledRefs = ..HandledRefs_$Select(..HandledRefs = "": "", 1: ",")_row.Ref
	Quit row.Ref
}

/// The UTC time moved by whole days, the time of day kept.
Method Shift(utc As %String, days As %Integer) As %String [ Private ]
{
	Quit $ZDate($ZDateH($Piece(utc, "T", 1), 3) + days, 3)_"T"_$Piece(utc, "T", 2)
}

}
