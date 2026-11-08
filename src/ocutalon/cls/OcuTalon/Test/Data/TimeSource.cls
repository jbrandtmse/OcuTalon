/// Tests of where Data.Time takes the instance zone from (Story 18.2; AD-18, DW-34, DW-643). The zone is saved the way an admin saves it,
/// through Bridge.Time.SetZone, which needs the active production, so this class runs on a throwaway stack (CI), never on a slot. The base class
/// (Test.Bridge.ZoneCase) removes the InstanceZone row and the process-private state of Apply before every test and puts both and the process
/// zone back after it.
///   - TestZoneFollowsBridge: after SetZone, the first conversion of the process is a Data.Time call and it converts, formats a message time and
///     reads a local time in the saved zone; Zone() names it;
///   - TestZoneCleared: after SetZone("") the conversions go back to the zone the process inherited, and Zone() names it;
///   - TestOsZone: with no row and no TZ, Zone() is OsZone() or UTC, and OsZone reads a zone file's name, the UTC aliases as UTC and "" for a
///     link that does not resolve;
///   - TestFoldZero: FromLocal of a repeated-hour time in New York, Berlin and Sydney, and of a repeated half hour in Lord Howe, gives the first
///     instant after each of six preceding calls (none, a winter and a summer ToLocal, a winter and a summer FromLocal, a conversion in another
///     zone), each in a process that has converted nothing before them;
///   - TestGapKept: the hour that a spring-forward day leaves out is read one hour later;
///   - TestAgreesWithBridgeAfterSetZone: the 290 instants around the two 2025 changes give the same local time from Data.Time and
///     Bridge.Time after SetZone to America/New_York and then to Europe/Berlin, Data.Time converting first after each change;
///   - TestPreamble: Agent.Input.Preamble shows the saved zone and the local time in it;
///   - TestReminderKeepsDueAt: a zone change moves the text of a pending reminder's time, and the stored DueAt stays.
Class OcuTalon.Test.Data.TimeSource Extends OcuTalon.Test.Bridge.ZoneCase
{

/// The Ref of the reminder that TestReminderKeepsDueAt makes, so that its cleanup finds it.
Property ReminderRef As %String;

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..ReminderRef '= "" {
		Set row = ##class(OcuTalon.Data.Reminder).RefIndexOpen(..ReminderRef)
		If $IsObject(row) Do ##class(OcuTalon.Data.Reminder).%DeleteId(row.%Id())
		Set row = ""
		Set ..ReminderRef = ""
	}
	Quit ##super(testname)
}

/// Saves the zone, and fails the test when it is refused.
Method Save(zone As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Time).SetZone(zone), "the instance zone is saved as '" _ zone _ "'")
}

/// The saved zone is the first thing a job reads: the first conversion of the process is a Data.Time call.
Method TestZoneFollowsBridge()
{
	Set time = "OcuTalon.Data.Time"
	Do ..PutZone("Europe/London")
	Do ..Save("Asia/Kolkata")
	Do $$$AssertTrue('$Data(^||OcuTalon.Bridge.Time), "no Bridge.Time call has run in this process yet")
	Do $$$AssertEquals($ClassMethod(time, "ToLocal", "2026-01-15T12:00:00Z"), "2026-01-15T17:30:00", "ToLocal converts in Asia/Kolkata")
	Do $$$AssertEquals($ClassMethod(time, "Zone"), "Asia/Kolkata", "Zone() names the saved zone")
	Do ..Forget()
	Do $$$AssertEquals($ClassMethod(time, "ForMessage", "2026-01-15T12:00:00Z", "2026-01-15T12:00:00Z"), "17:30", "ForMessage converts in Asia/Kolkata")
	Do ..Forget()
	Do $$$AssertEquals($ClassMethod(time, "FromLocal", "2026-01-15T17:30:00"), "2026-01-15T12:00:00Z", "FromLocal reads Asia/Kolkata")
}

/// Forgets what this process applied and puts the inherited zone (Europe/London) back, so that the next call is the first one of a process.
Method Forget() [ Private ]
{
	Kill ^||OcuTalon.Bridge.Time
	Do ..PutZone("Europe/London")
}

/// An empty InstanceZone after a zone was applied: the conversions go back to the zone the process inherited.
Method TestZoneCleared()
{
	Set time = "OcuTalon.Data.Time"
	Do ..PutZone("Europe/Berlin")
	Do ..Save("Asia/Kolkata")
	Do $$$AssertEquals($ClassMethod(time, "ToLocal", "2026-01-15T12:00:00Z"), "2026-01-15T17:30:00", "the saved zone is applied")
	Do ..Save("")
	Do $$$AssertEquals($ClassMethod(time, "ToLocal", "2026-01-15T12:00:00Z"), "2026-01-15T13:00:00", "the inherited zone (Europe/Berlin) is back")
	Do $$$AssertEquals($ClassMethod(time, "Zone"), "Europe/Berlin", "Zone() reports the inherited TZ")
}

/// With no row and no TZ, Zone() is the operating system's zone.
Method TestOsZone()
{
	Set time = "OcuTalon.Data.Time"
	Do ..PutZone(-1)
	Set os = $ClassMethod(time, "OsZone")
	Do $$$AssertTrue((os = "") || (os = "UTC") || ##class(%File).Exists("/usr/share/zoneinfo/" _ os), "OsZone() '" _ os _ "' is empty, UTC or a zone file")
	Do $$$AssertEquals($ClassMethod(time, "Zone"), $Select(os = "": "UTC", 1: os), "Zone() is OsZone(), or UTC when that is empty")
	Do $$$AssertEquals($ClassMethod(time, "OsZone", "/usr/share/zoneinfo/Europe/Berlin"), "Europe/Berlin", "a zone file gives its name")
	Do $$$AssertEquals($ClassMethod(time, "OsZone", "/usr/share/zoneinfo/Zz/NoSuchZone"), "", "an unresolvable link gives an empty name")
	If ##class(%File).Exists("/usr/share/zoneinfo/Etc/UTC") {
		Do $$$AssertEquals($ClassMethod(time, "OsZone", "/usr/share/zoneinfo/Etc/UTC"), "UTC", "Etc/UTC is reported as UTC")
	}
	Do ..Save("America/New_York")
	Do $$$AssertEquals($ClassMethod(time, "Zone"), "America/New_York", "a saved zone comes before the operating system's")
}

/// FromLocal of a repeated-hour time is the first instant, after each of six preceding calls.
Method TestFoldZero()
{
	Set time = "OcuTalon.Data.Time"
	Set cases = $ListBuild($ListBuild("America/New_York", "2026-11-01T01:30:00", "2026-11-01T05:30:00Z"), $ListBuild("Europe/Berlin", "2026-10-25T02:30:00", "2026-10-25T00:30:00Z"), $ListBuild("Australia/Sydney", "2026-04-05T02:30:00", "2026-04-04T15:30:00Z"), $ListBuild("Australia/Lord_Howe", "2026-04-05T01:45:00", "2026-04-04T14:45:00Z"))
	Set orders = $ListBuild("fresh", "winter ToLocal", "summer ToLocal", "winter FromLocal", "summer FromLocal", "another zone")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set zone = $List(case, 1)
		Set orderPosition = 0
		While $ListNext(orders, orderPosition, order) {
			Do ..Forget()
			Do ..Save(zone)
			Do ..Prepare(order, zone)
			Do $$$AssertEquals($ClassMethod(time, "FromLocal", $List(case, 2)), $List(case, 3), zone _ " " _ $List(case, 2) _ " is the first instant after: " _ order)
		}
	}
}

/// The call that precedes the FromLocal under test in the zone.
Method Prepare(order As %String, zone As %String) [ Private ]
{
	Set time = "OcuTalon.Data.Time"
	If order = "winter ToLocal" Do $ClassMethod(time, "ToLocal", "2026-01-15T12:00:00Z")
	If order = "summer ToLocal" Do $ClassMethod(time, "ToLocal", "2026-07-15T12:00:00Z")
	If order = "winter FromLocal" Do $ClassMethod(time, "FromLocal", "2026-01-15T12:00:00")
	If order = "summer FromLocal" Do $ClassMethod(time, "FromLocal", "2026-07-15T12:00:00")
	If order = "another zone" {
		Do ..Save("Asia/Tokyo")
		Do $ClassMethod(time, "ToLocal", "2026-07-15T12:00:00Z")
		Do ..Save(zone)
	}
}

/// The hour that a spring-forward day leaves out is read one hour later.
Method TestGapKept()
{
	Do ..Save("America/New_York")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).FromLocal("2026-03-08T02:30:00"), "2026-03-08T07:30:00Z", "02:30 in the gap is 03:30 EDT")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).FromLocal("2026-03-08T01:30:00"), "2026-03-08T06:30:00Z", "01:30 before the gap")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).FromLocal("2026-03-08T03:30:00"), "2026-03-08T07:30:00Z", "03:30 after the gap")
}

/// The walk of Test.Bridge.Time across the 2025 changes, with Data.Time converting first after each change of the saved zone.
Method TestAgreesWithBridgeAfterSetZone()
{
	Set data = "OcuTalon.Data.Time"
	Set bridge = "OcuTalon.Bridge.Time"
	Set zones = $ListBuild($ListBuild("America/New_York", "2025-07-01T12:00:00Z", "2025-07-01T08:00:00"), $ListBuild("Europe/Berlin", "2025-07-01T12:00:00Z", "2025-07-01T14:00:00"))
	Set position = 0
	While $ListNext(zones, position, row) {
		Set zone = $List(row, 1)
		Do ..Save(zone)
		Do $$$AssertEquals($ClassMethod(data, "ToLocal", $List(row, 2)), $List(row, 3), zone _ ": the first conversion after the change, a Data.Time one, is in the new zone")
		Set compared = 0
		Set differences = ""
		For start = "2025-03-08", "2025-11-01" {
			Set days = $ZDateH(start, 3)
			For seconds = 0:1800:(3 * 86400) {
				Set utc = $Translate($ZDateTime((days + (seconds \ 86400)) _ "," _ (seconds # 86400), 3, 1), " ", "T") _ "Z"
				Set expected = $ClassMethod(bridge, "ToLocal", utc)
				Set actual = $ClassMethod(data, "ToLocal", utc)
				Set compared = compared + 1
				If (expected = "") || (actual '= expected) {
					If $Length(differences) < 200 Set differences = differences _ " " _ utc
				}
			}
		}
		Do $$$AssertEquals(compared, 290, zone _ ": 290 instants are compared")
		Do $$$AssertEquals(differences, "", zone _ ": Data.Time agrees with Bridge.Time at each of them")
	}
	Do $$$AssertEquals($ClassMethod(data, "ToLocal", "2025-03-30T00:59:59Z"), "2025-03-30T01:59:59", "Berlin is on standard time just before its March change")
	Do $$$AssertEquals($ClassMethod(data, "ToLocal", "2025-03-30T01:00:00Z"), "2025-03-30T03:00:00", "and on summer time right after it")
}

/// The preamble that the model sees shows the saved zone and the local time in it.
Method TestPreamble()
{
	Do ..PutZone("Europe/London")
	Do ..Save("Asia/Kolkata")
	Do $$$AssertEquals(##class(OcuTalon.Agent.Input).Preamble("2026-01-15T12:00:00Z"), "Local time: Thursday 2026-01-15 17:30 (time zone Asia/Kolkata)", "the preamble is in the saved zone")
	Do ..Save("America/New_York")
	Do $$$AssertEquals(##class(OcuTalon.Agent.Input).Preamble("2026-01-15T12:00:00Z"), "Local time: Thursday 2026-01-15 07:00 (time zone America/New_York)", "and follows the next change")
}

/// A zone change moves the text of a pending reminder's time and leaves the stored DueAt as it was.
Method TestReminderKeepsDueAt()
{
	Set row = ##class(OcuTalon.Data.Reminder).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = "zztimesrc"
	Set row.Text = "zz time source"
	Set row.DueAt = "2031-06-12T14:00:00Z"
	Set row.State = "pending"
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(row.%Save(), "the pending reminder is saved")
	Set ..ReminderRef = row.Ref
	Set id = row.%Id()
	Set row = ""
	Set now = "2031-06-12T10:00:00Z"
	Do ..Save("America/New_York")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ForMessage("2031-06-12T14:00:00Z", now), "10:00", "in New York the reminder reads 10:00")
	Do ..Save("Asia/Kolkata")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ForMessage("2031-06-12T14:00:00Z", now), "19:30", "in Kolkata the same instant reads 19:30")
	Set row = ##class(OcuTalon.Data.Reminder).%OpenId(id)
	Do $$$AssertEquals(row.DueAt, "2031-06-12T14:00:00Z", "the stored DueAt is unchanged")
	Do $$$AssertEquals(row.State, "pending", "and the reminder is still pending")
}

}
