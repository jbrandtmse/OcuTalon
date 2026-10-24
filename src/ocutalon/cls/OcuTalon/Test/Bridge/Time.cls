/// Tests of the bridge's clock against the product's (Story 1.4; AD-2, AD-18, AD-20). Pure: nothing is written. The bridge cannot name
/// OcuTalon.Data.Time, so OcuTalon.Bridge.Time keeps its own copy of the conversion, and these tests keep the two in step.
///   - TestAgreesWithDataTime: from 2025-03-08T00:00Z to 2025-03-11T00:00Z and from 2025-11-01T00:00Z to 2025-11-04T00:00Z, the two
///     daylight-saving changes of 2025, at every half hour, in America/New_York, Asia/Kolkata and with no zone set, ToLocal gives what
///     Data.Time.ToLocal gives, and LocalDate is its date;
///   - TestDayBounds: DayStartUtc and DayEndUtc in New York: 2025-03-09 starts at 05:00Z and lasts 23 hours, 2025-11-02 lasts 25 hours,
///     the first instant of a day is its local midnight and the second before it is 23:59:59 of the day before; in America/Havana
///     2025-03-09, whose midnight does not exist, starts at its first instant, local 01:00; with no zone a day is a UTC day;
///   - TestUnreadable: every method gives "" for an input it cannot read;
///   - TestMsSince: the milliseconds since a UTC timestamp 250 ms old, the same result in three zones, 0 for a timestamp ahead of the clock;
///   - TestMsSinceFraction: the fraction of a second counts: a stamp with .900 reads about 900 ms less than the same second with .000
///     (at least 600 ms less, whatever pause there is between the two reads);
///   - TestZoneCase (Story 1.10, DW-32): the zone base of the test classes that change the process zone (Test.Bridge.ZoneCase) puts back what it
///     read, a named zone and "no zone" (-1, which it takes as an empty zone) alike, also through its hooks (OnBeforeOneTest saves the zone and
///     OnAfterOneTest puts it back); the six classes that extend it (this one, Test.Agent.Render, Test.Bridge.Usage, Test.Bridge.Budget,
///     Test.Bridge.Decide and Test.Tools.Reminders) keep no zone copy of their own, and no other test class of Lane A's packages (Agent, Bridge, Tools,
///     Install, Digest) calls the process time zone without extending the base: the scanner is first shown to flag a sample. The base saves and restores
///     the zone around every test of this class too.
Class OcuTalon.Test.Bridge.Time Extends OcuTalon.Test.Bridge.ZoneCase
{

/// ToLocal and LocalDate of the bridge are those of Data.Time at every half hour of the two weekends, in three zones.
Method TestAgreesWithDataTime()
{
	Set zones = $ListBuild("America/New_York", "Asia/Kolkata", "")
	Set position = 0
	While $ListNext(zones, position, zone) {
		Do $SYSTEM.Process.TimeZone(zone)
		Set label = $Select(zone = "": "no zone", 1: zone)
		Set compared = 0
		Set differences = ""
		For start = "2025-03-08", "2025-11-01" {
			Set days = $ZDateH(start, 3)
			For seconds = 0:1800:(3 * 86400) {
				Set utc = $Translate($ZDateTime((days + (seconds \ 86400))_","_(seconds # 86400), 3, 1), " ", "T")_"Z"
				Set expected = ##class(OcuTalon.Data.Time).ToLocal(utc)
				Set compared = compared + 1
				If (expected = "") || (##class(OcuTalon.Bridge.Time).ToLocal(utc) '= expected) || (##class(OcuTalon.Bridge.Time).LocalDate(utc) '= $Piece(expected, "T", 1)) {
					If $Length(differences) < 200 Set differences = differences _ " " _ utc
				}
			}
		}
		Do $$$AssertEquals(compared, 290, label_": 290 instants are compared")
		Do $$$AssertEquals(differences, "", label_": ToLocal and LocalDate agree with Data.Time at each of them")
	}
	Do $SYSTEM.Process.TimeZone("America/New_York")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Time).ToLocal("2025-03-09T06:59:59Z"), "2025-03-09T01:59:59", "New York is on standard time just before the change")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Time).ToLocal("2025-03-09T07:00:00Z"), "2025-03-09T03:00:00", "and on daylight-saving time right after it")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Time).LocalDate("2025-03-10T03:59:59Z"), "2025-03-09", "local midnight of 2025-03-10 is 04:00Z")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Time).LocalDate("2025-03-10T04:00:00Z"), "2025-03-10", "so 04:00Z is the next date")
}

/// The first instant of a local date, and the end of the date.
Method TestDayBounds()
{
	Set time = "OcuTalon.Bridge.Time"
	Do $SYSTEM.Process.TimeZone("America/New_York")
	Do $$$AssertEquals($ClassMethod(time, "DayStartUtc", "2025-03-09"), "2025-03-09T05:00:00Z", "2025-03-09 starts at 05:00Z in New York")
	Do $$$AssertEquals($ClassMethod(time, "DayStartUtc", "2025-03-10"), "2025-03-10T04:00:00Z", "2025-03-10 starts at 04:00Z, after the change")
	Do $$$AssertEquals($ClassMethod(time, "DayStartUtc", "2025-11-02"), "2025-11-02T04:00:00Z", "2025-11-02 starts at 04:00Z")
	Do $$$AssertEquals($ClassMethod(time, "DayStartUtc", "2025-11-03"), "2025-11-03T05:00:00Z", "2025-11-03 starts at 05:00Z, after the change")
	Do $$$AssertEquals($ClassMethod(time, "DayEndUtc", "2025-03-09"), "2025-03-10T04:00:00Z", "2025-03-09 ends where 2025-03-10 starts")
	Do $$$AssertEquals(..Hours("2025-03-09"), 23, "2025-03-09 lasts 23 hours")
	Do $$$AssertEquals(..Hours("2025-03-10"), 24, "2025-03-10 lasts 24 hours")
	Do $$$AssertEquals(..Hours("2025-11-02"), 25, "2025-11-02 lasts 25 hours")
	Do $$$AssertEquals(..Hours("2025-11-03"), 24, "2025-11-03 lasts 24 hours")
	For day = "2025-03-09", "2025-03-10", "2025-11-02", "2025-11-03", "2025-01-15", "2025-07-15" {
		Set start = $ClassMethod(time, "DayStartUtc", day)
		Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal(start), day_"T00:00:00", day_": its first instant is local midnight")
		Set before = ..Shift(start, -1)
		Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal(before), ..DayBefore(day)_"T23:59:59", day_": the second before it is 23:59:59 of the day before")
		Do $$$AssertEquals($ClassMethod(time, "LocalDate", start)_"|"_$ClassMethod(time, "LocalDate", before), day_"|"_..DayBefore(day), day_": LocalDate tells the two apart")
	}
	Do $SYSTEM.Process.TimeZone("America/Havana")
	Set start = $ClassMethod(time, "DayStartUtc", "2025-03-09")
	Do $$$AssertEquals(start, "2025-03-09T05:00:00Z", "in Havana 2025-03-09 starts at 05:00Z")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal(start), "2025-03-09T01:00:00", "which is local 01:00, because midnight does not exist that day")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal(..Shift(start, -1)), "2025-03-08T23:59:59", "and the second before it is still the day before")
	Do $SYSTEM.Process.TimeZone("Asia/Kolkata")
	Do $$$AssertEquals($ClassMethod(time, "DayStartUtc", "2025-03-09"), "2025-03-08T18:30:00Z", "in Kolkata 2025-03-09 starts at 18:30Z of the day before")
	Do $SYSTEM.Process.TimeZone("")
	Do $$$AssertEquals($ClassMethod(time, "DayStartUtc", "2001-02-04"), "2001-02-04T00:00:00Z", "with no zone a day starts at 00:00Z")
	Do $$$AssertEquals($ClassMethod(time, "DayEndUtc", "2001-02-04"), "2001-02-05T00:00:00Z", "and ends at 00:00Z of the next date")
	Do $$$AssertEquals($ClassMethod(time, "DayEndUtc", "2001-12-31"), "2002-01-01T00:00:00Z", "also at the end of a year")
	Do $$$AssertEquals($ClassMethod(time, "DayEndUtc", "2004-02-28"), "2004-02-29T00:00:00Z", "and before a leap day")
}

/// An input that cannot be read gives "" from every method, and a time that is not UTC or a date that does not exist is one of them.
Method TestUnreadable()
{
	Set time = "OcuTalon.Bridge.Time"
	For input = "", "x", "2025-03-09", "2025-03-09 05:00:00", "2025-03-09T05:00:00", "2025-13-09T05:00:00Z", "2025-02-30T05:00:00Z" {
		Do $$$AssertEquals($ClassMethod(time, "ToLocal", input)_"|"_$ClassMethod(time, "LocalDate", input), "|", "ToLocal and LocalDate of '"_input_"' are empty")
	}
	For input = "", "x", "2025-3-9", "2025-13-09", "2025-02-30", "2025-03-09T05:00:00Z" {
		Do $$$AssertEquals($ClassMethod(time, "DayStartUtc", input)_"|"_$ClassMethod(time, "DayEndUtc", input), "|", "DayStartUtc and DayEndUtc of '"_input_"' are empty")
	}
	For input = "", "x", "2025-03-09", "2025-03-09T05:00:00Z", "2025-03-09 05:00", "2025-13-09 05:00:00", "2025-03-09 25:00:00", "2025-03-09 05:00:00." {
		Do $$$AssertEquals($ClassMethod(time, "MsSince", input), "", "MsSince of '"_input_"' is empty")
	}
}

/// MsSince of a UTC timestamp that is 250 ms old is at least 200 and under 10 seconds (11 for a stamp with no fraction), however slow the
/// machine, whatever the zone of the process; a timestamp ahead of the clock gives 0.
Method TestMsSince()
{
	Set time = "OcuTalon.Bridge.Time"
	For zone = "", "America/New_York", "Asia/Kolkata" {
		Do $SYSTEM.Process.TimeZone(zone)
		Set stamp = $ZDateTime($ZTimeStamp, 3, 1, 3)
		Hang 0.25
		Set ms = $ClassMethod(time, "MsSince", stamp)
		Do $$$AssertTrue((ms >= 200) && (ms < 10000), "a timestamp 250 ms old is "_ms_" ms old in the zone '"_zone_"'")
		Do $$$AssertEquals(ms, ms \ 1, "in whole milliseconds")
		Set whole = $Piece(stamp, ".", 1)
		Set ms = $ClassMethod(time, "MsSince", whole)
		Do $$$AssertTrue((ms >= 200) && (ms < 11000), "and so is the same timestamp with no fraction: "_ms_" ms")
	}
	Do $$$AssertEquals($ClassMethod(time, "MsSince", "2999-01-01 00:00:00.000"), 0, "a timestamp ahead of the clock gives 0")
}

/// Two stamps of the same second, five seconds ago, one with the fraction .000 and one with .900, read one after the other: the second
/// reads 900 ms less than the first, less the pause between the two reads, which stays far under 300 ms, so the fraction is counted.
Method TestMsSinceFraction()
{
	Set time = "OcuTalon.Bridge.Time"
	Set second = $Translate($Extract(..Shift($ClassMethod(time, "NowUtc"), -5), 1, 19), "T", " ")
	Set zero = $ClassMethod(time, "MsSince", second_".000")
	Set late = $ClassMethod(time, "MsSince", second_".900")
	Do $$$AssertTrue((zero - late > 600) && (zero - late '> 900), "the stamp .900 of the second "_second_" reads "_(zero - late)_" ms less than its .000")
}

/// The zone base (DW-32). A process that has had no zone reads -1 (CurrentZone), and PutZone(-1) puts back no zone: it takes -1 as an empty zone, whose local
/// time is UTC. With a named zone, PutZone puts that zone back after the process has been given another (the local time shows which one is set). The classes
/// that fold their zone save and restore into the base declare no SavedZone of their own and extend it, and no other test class of Lane A's packages calls the
/// process time zone: a copy would be a class that does and does not extend the base.
Method TestZoneCase()
{
	Set base = "OcuTalon.Test.Bridge.ZoneCase"
	Do $SYSTEM.Process.TimeZone(-1)
	Set none = $ClassMethod(base, "CurrentZone")
	Do $$$AssertEquals(none, -1, "a process that has had no zone reads -1")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal("2025-07-01T12:00:00Z"), "2025-07-01T12:00:00", "and its local time is UTC")
	Do $SYSTEM.Process.TimeZone("America/New_York")
	Do $$$AssertNotEquals($ClassMethod(base, "CurrentZone"), -1, "a process with a zone does not")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal("2025-07-01T12:00:00Z"), "2025-07-01T08:00:00", "control: its local time is New York's in summer")
	Do $ClassMethod(base, "PutZone", none)
	Do $$$AssertEquals($ClassMethod(base, "CurrentZone"), "", "PutZone(-1) puts back no zone: -1 is taken as an empty zone, not as a zone")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal("2025-07-01T12:00:00Z"), "2025-07-01T12:00:00", "whose local time is UTC again")

	Do $SYSTEM.Process.TimeZone("America/New_York")
	Set named = $ClassMethod(base, "CurrentZone")
	Do $SYSTEM.Process.TimeZone("Asia/Kolkata")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal("2025-07-01T12:00:00Z"), "2025-07-01T17:30:00", "control: Kolkata is five and a half hours ahead of UTC")
	Do $ClassMethod(base, "PutZone", named)
	Do $$$AssertEquals($ClassMethod(base, "CurrentZone"), named, "PutZone puts back the named zone that CurrentZone gave")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal("2025-07-01T12:00:00Z"), "2025-07-01T08:00:00", "whose local time is New York's in summer")

	Set own = ..SavedZone
	Do $SYSTEM.Process.TimeZone("America/New_York")
	Do ..OnBeforeOneTest("TestZoneCase")
	Do $SYSTEM.Process.TimeZone("Asia/Kolkata")
	Do ..OnAfterOneTest("TestZoneCase")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal("2025-07-01T12:00:00Z"), "2025-07-01T08:00:00", "the hooks save the zone before a test and put it back after: a named zone")
	Do $SYSTEM.Process.TimeZone(-1)
	Do ..OnBeforeOneTest("TestZoneCase")
	Do $SYSTEM.Process.TimeZone("Asia/Kolkata")
	Do ..OnAfterOneTest("TestZoneCase")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal("2025-07-01T12:00:00Z"), "2025-07-01T12:00:00", "and no zone")
	Set ..SavedZone = own

	Set classes = $ListBuild("OcuTalon.Test.Bridge.Time", "OcuTalon.Test.Agent.Render", "OcuTalon.Test.Bridge.Usage", "OcuTalon.Test.Bridge.Budget", "OcuTalon.Test.Bridge.Decide", "OcuTalon.Test.Tools.Reminders")
	Set position = 0
	While $ListNext(classes, position, class) {
		Do $$$AssertTrue($ClassMethod(class, "%Extends", base), class_" extends the zone base")
		Do $$$AssertNotTrue(##class(%Dictionary.PropertyDefinition).%ExistsId(class_"||SavedZone"), class_" declares no SavedZone of its own")
	}
	Do $$$AssertTrue(##class(%Dictionary.ClassDefinition).%OpenId(base).Abstract, "the base is abstract")
	Set tests = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM %Dictionary.MethodDefinition WHERE parent = ? AND Name %STARTSWITH 'Test'", base)
	Do tests.%Next()
	Do $$$AssertEquals(tests.%GetData(1), 0, "and holds no method whose name starts with Test, so ci/iris.sh runs no class of it")

	Set pattern = "process\.timezone\("
	Set source = "OcuTalon.Test.Bridge.Source"
	Do $$$AssertTrue($ClassMethod(source, "Matches", $Char(9)_"Do $SYSTEM.Process.TimeZone(saved)", pattern), "control: the scanner flags a call of the process time zone")
	Do $$$AssertTrue('$ClassMethod(source, "Matches", "/// puts the zone back through Process.TimeZone(saved)"_$Char(10)_$Char(9)_"Quit 1", pattern), "and passes a comment line")
	Set scanned = 0
	Set copies = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'OcuTalon.Test.' ORDER BY Name")
	While result.%Next() {
		Set name = result.%GetData(1)
		Set area = $Piece(name, ".", 3)
		If '$ListFind($ListBuild("Agent", "Bridge", "Tools", "Install", "Digest"), area) || (name = base) || '##class(%Dictionary.CompiledClass).%ExistsId(name) Continue
		Set scanned = scanned + 1
		If $ClassMethod(name, "%Extends", base) Continue
		If $$$ISOK($ClassMethod(source, "Text", name, .text)) && $ClassMethod(source, "Matches", text, pattern) Set copies = copies _ " " _ name
	}
	Do $$$AssertTrue(scanned '< 20, "the scan read the test classes of Lane A's packages: "_scanned)
	Do $$$AssertEquals(copies, "", "and none that calls the process time zone is outside the base")
}

/// --- helpers ---
/// The hours from the start of the local date to its end.
ClassMethod Hours(day As %String) As %Integer [ Private ]
{
	Set start = ##class(OcuTalon.Bridge.Time).DayStartUtc(day)
	Set end = ##class(OcuTalon.Bridge.Time).DayEndUtc(day)
	Quit (..Seconds(end) - ..Seconds(start)) / 3600
}

/// The UTC time shifted by whole seconds.
ClassMethod Shift(utc As %String, seconds As %Integer) As %String [ Private ]
{
	Set total = ..Seconds(utc) + seconds
	Quit $Translate($ZDateTime((..Base() + (total \ 86400))_","_(total # 86400), 3, 1), " ", "T")_"Z"
}

/// The seconds from the base day to the UTC time.
ClassMethod Seconds(utc As %String) As %Integer [ Private ]
{
	Quit ($ZDateH($Piece(utc, "T", 1), 3) - ..Base()) * 86400 + $ZTimeH($Piece($Piece(utc, "T", 2), "Z", 1), 1)
}

/// The base day of the second counts: 2000-01-01.
ClassMethod Base() As %Integer [ Private ]
{
	Quit $ZDateH("2000-01-01", 3)
}

/// The date before YYYY-MM-DD.
ClassMethod DayBefore(day As %String) As %String [ Private ]
{
	Quit $ZDate($ZDateH(day, 3) - 1, 3)
}

}
