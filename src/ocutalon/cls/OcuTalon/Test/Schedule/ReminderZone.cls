/// Tests of the local-to-UTC conversion of the reminders across daylight-saving time (Story 8.4; AD-18, FR-34). They set the zone of the
/// process, because a throwaway runs in UTC, and the base class (Test.Bridge.ZoneCase) puts it back after every test. They need no
/// production.
///   - TestFromLocal: Data.Time.FromLocal in America/New_York for the two Thursdays either side of the end of daylight-saving time
///     (2030-10-31 and 2030-11-07), the hour that a spring-forward day leaves out (read one hour later) and the hour that a fall-back day
///     repeats (the first instant), the values it refuses, Asia/Kolkata, no zone, the round trip through ToLocal, and its agreement with
///     Bridge.Time.DayStartUtc, the bridge's twin, over 2030-11-01 to 2030-11-09;
///   - TestResolveThursdayAt10: Schedule.Reminder.Resolve of "Thursday at 10" in New York gives 15:00:00Z after the change and 14:00:00Z the
///     week before.
Class OcuTalon.Test.Schedule.ReminderZone Extends OcuTalon.Test.Bridge.ZoneCase
{

/// Puts the process in the zone.
ClassMethod Zone(zone As %String) [ Private ]
{
	Do $SYSTEM.Process.TimeZone(zone)
}

/// FromLocal in New York, Kolkata and no zone.
Method TestFromLocal()
{
	Set time = "OcuTalon.Data.Time"
	Do ..Zone("America/New_York")
	Do $$$AssertEquals($ClassMethod(time, "FromLocal", "2030-11-07T10:00:00"), "2030-11-07T15:00:00Z", "Thursday 10:00 after the change is 15:00:00Z")
	Do $$$AssertEquals($ClassMethod(time, "FromLocal", "2030-10-31T10:00:00"), "2030-10-31T14:00:00Z", "Thursday 10:00 the week before is 14:00:00Z")
	Do $$$AssertEquals($ClassMethod(time, "FromLocal", "2026-03-08T01:30:00"), "2026-03-08T06:30:00Z", "01:30 before the spring-forward gap")
	Do $$$AssertEquals($ClassMethod(time, "FromLocal", "2026-03-08T02:30:00"), "2026-03-08T07:30:00Z", "02:30 in the gap is read as 03:30 EDT")
	Do $$$AssertEquals($ClassMethod(time, "FromLocal", "2026-03-08T03:00:00"), "2026-03-08T07:00:00Z", "03:00 after the gap")
	Do $$$AssertEquals($ClassMethod(time, "FromLocal", "2026-11-01T00:30:00"), "2026-11-01T04:30:00Z", "00:30 before the overlap")
	Do $$$AssertEquals($ClassMethod(time, "FromLocal", "2026-11-01T01:30:00"), "2026-11-01T05:30:00Z", "01:30 in the overlap is the first instant")
	Do $$$AssertEquals($ClassMethod(time, "ToLocal", $ClassMethod(time, "FromLocal", "2030-11-07T10:00:00")), "2030-11-07T10:00:00", "ToLocal gives the Thursday back")
	Do $$$AssertEquals($ClassMethod(time, "ToLocal", $ClassMethod(time, "FromLocal", "2030-10-31T10:00:00")), "2030-10-31T10:00:00", "ToLocal gives the earlier Thursday back")
	Set refused = $ListBuild("2026-02-30T10:00:00", "next Thursday", "2030-11-07 10:00:00", "2030-11-07T10:00", "2030-11-07T10:00:00Z", "", "2030-11-07T25:00:00", "9999-12-31T23:00:00")
	Set position = 0
	While $ListNext(refused, position, value) {
		Do $$$AssertEquals($ClassMethod(time, "FromLocal", value), "", "'" _ value _ "' is refused")
	}
	Do ..Zone("Asia/Kolkata")
	Do $$$AssertEquals($ClassMethod(time, "FromLocal", "2030-11-07T10:00:00"), "2030-11-07T04:30:00Z", "in Kolkata 10:00 is 04:30:00Z")
	Do ..PutZone(-1)
	Do $$$AssertEquals($ClassMethod(time, "ToLocal", $ClassMethod(time, "FromLocal", "2030-11-07T10:00:00")), "2030-11-07T10:00:00", "with no zone ToLocal gives the local time back")
	Do $$$AssertEquals($ClassMethod(time, "ToLocal", $ClassMethod(time, "FromLocal", "2030-10-31T10:00:00")), "2030-10-31T10:00:00", "also for the earlier Thursday")
	Do ..Zone("America/New_York")
	For day = "2030-11-01", "2030-11-02", "2030-11-03", "2030-11-04", "2030-11-05", "2030-11-06", "2030-11-07", "2030-11-08", "2030-11-09" {
		Do $$$AssertEquals($ClassMethod(time, "FromLocal", day _ "T00:00:00"), ##class(OcuTalon.Bridge.Time).DayStartUtc(day), "FromLocal of midnight on " _ day _ " is the bridge's DayStartUtc")
	}
}

/// "Thursday at 10" in New York resolves to 15:00:00Z after the end of daylight-saving time and to 14:00:00Z the week before.
Method TestResolveThursdayAt10()
{
	Do ..Zone("America/New_York")
	Set now = "2030-01-01T10:00:00Z"
	Set command = ##class(OcuTalon.Msg.Command.SetReminder).%New()
	Set command.Text = "zz stretch"
	Set command.LocalDueAt = "2030-11-07T10:00:00"
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Resolve(command, now, .dueAt) _ "|" _ dueAt, "|2030-11-07T15:00:00Z", "Thursday at 10 after the change")
	Set command.LocalDueAt = "2030-10-31T10:00:00"
	Do $$$AssertEquals(##class(OcuTalon.Schedule.Reminder).Resolve(command, now, .dueAt) _ "|" _ dueAt, "|2030-10-31T14:00:00Z", "Thursday at 10 the week before")
}

}
