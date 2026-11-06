/// Tests of the agent heartbeat's beats and the names of its settings (Stories 39.1 and 39.3; AD-5, AD-18, AD-19, AD-20, AD-28, AD-33): the BeatNow message has
/// exactly its contract and shares the Ens.MessageBody extent, the setting names, defaults and caps are the spine's (the checklist cap being the length of
/// Setting.Value), a HeartbeatBeat row keeps all 15 fields through a save and a reopen, with the defaults of an empty row, in the private global
/// ^OcuTalonP.HeartbeatBeat, a second row of the same SessionRef is refused and leaves the first untouched, and SettingKey takes a name only exactly as KEYS lists
/// it. The tests need no production (warm). Every time-dependent test uses fixed clocks in 2099 (local times built with Data.Time.FromLocal), so no real tick finds
/// a row of a test due (a due row is due at the test's own 2099 tick), and every RunDue call names its sessions, so that the rows of a warm stack are never touched. The tests make their fixture sessions
/// with Test.Data.Fixture, make each row before the settings, and remove their HeartbeatBeat rows, Setting rows and fixture decisions after each test. A real tick
/// may reschedule a row that is on and not due (Checks.Beat.Rescheduled) only to the NextDueAt the test's own tick gives it, so a row that must keep its NextDueAt
/// while off gets its LastBeatAt only after on is 0.
///   - TestValues: the defaults, the online demo's on, an interval outside the allowed ones, an all-day pair and a bad pair;
///   - TestActiveHours: the window over midnight, the normal window, from = to and all day, and the same windows read in America/New_York;
///   - TestNextDue: the next start of the active hours for hours, one interval for every other reason, and the same in America/New_York;
///   - TestSkipOrder: each reason alone, in pairs and all at once, and the run-now variant that leaves out hours and unchanged;
///   - TestKey: 64 lower-case hexadecimal characters, the SHA-256 of the UTF-8 text, stable, deaf to the status line, changed by the checklist, and the snapshot of a person with no rows;
///   - TestDueSelection: a beat that is not due, a person with no row, an off person, a restart that catches up once;
///   - TestBeatRow: the Item and the row of a beat that runs;
///   - TestDecisionIsRecorded: ignore, a pending beat, a fallback with an interval of 30 and of 1440 minutes;
///   - TestUnchangedAfterIgnore: a checklist unchanged since the last ignore is skipped, a changed one beats;
///   - TestRunNow: hours and unchanged do not hold it, the other reasons do, and the cooldown at 119 and 120 seconds;
///   - TestRunNowReadsStoredValues (Story 39.8; AC 1, AC 3): a person whose settings this process has cached, and another process then saves a checklist, an interval and off (rows
///     saved without Setting.Set, so that the entries stay): the values still read the cached ones, a RunDue tick reads the cached empty checklist and records the empty skip with no Item,
///     and RunNow drops the five cache entries, answers sent with an Item that starts with the checklist and a next due time one stored interval on, after which the values read the stored
///     settings; a pending fallback decision is recorded by RunNow with the stored interval;
///   - TestRunNowDropsAllFiveKeys (QA; Story 39.8, AC 1): all five settings, from and to included, saved without Setting.Set after this process cached them: RunNow sends, and the values then read the stored ones;
///   - TestSavedIntervalMovesNextDue (Story 39.8; AC 2, AC 3): a NextDueAt set by a beat or by a skip other than hours under a longer interval moves to the base plus the saved
///     interval, saved with no view and no Item, and the next tick writes nothing and the tick at that time beats; a time that has passed beats at once with one view; a longer
///     interval, an hours skip that is the newest write, an off person and a row with no base keep NextDueAt;
///   - TestSkipsAreRecordedByRunDue (QA): what RunDue writes for hours, hours with the cap, backoff, cap and nokey, and that a skip leaves an earlier beat's fields;
///   - TestRecordedDecisionCountsInTheSameRunDue (QA): an ignore, a fallback and an off person's pending decision are recorded before the due run;
///   - TestOneFailureLeavesTheOthers: a person whose row cannot be saved leaves the person after it to beat, and the status holds the count and an error code only;
///   - TestFailedDecisionHoldsTheBeat: a person whose decision cannot be recorded does not beat over it and counts once, and the person after it is recorded and beats;
///   - TestUnreadableRowIsReported: a row that stops the read of the rows gives an error status, and the people still beat;
///   - TestInputsAreRead: Capped follows the day's mark, Keyed follows Bridge.Keys, and RunDue and RunNow read both when they are given none;
///   - TestViewsInCommitOrder (Story 39.7): the views of RunDue and RunNow, one for each commit of a row and in commit order, each equal to Heartbeat.FromRow of the
///     reopened row at that point: a recorded ignore then the unchanged skip of one RunDue (two views), an off person's recorded decision, nothing for a person
///     who is not due or is off with nothing pending, a run now that sends (also after a recorded decision), a run now that is held, and a cooldown (nothing, or
///     only the recorded result of a pending decision);
///   - TestRunDueEmptySkipGivesNoView (Story 39.7, CI rework; AC 1): a RunDue skip for an empty checklist is saved with its reason and gives no view, a back-off skip still does,
///     and a pending decision's recorded result is still viewed;
///   - TestFailedCommitsGiveNoView (Story 39.7, QA; AC 3): a recorded decision that cannot be saved, a row refused as a duplicate and a RunNow that cannot settle give no view,
///     and the person after a failure still gives a view for each of its commits.
Class OcuTalon.Test.Checks.Beat Extends OcuTalon.Test.Contract
{

Parameter BEAT = "OcuTalon.Checks.Beat";

/// The Refs of the fixture rows of the test being run (sessions and decisions), comma-separated.
Property Refs As %String(MAXLEN = "");

/// The sessions whose settings and HeartbeatBeat rows the test made, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The day whose mark ^OcuTalonBP.UsageCapped the test set, "" for none.
Property Day As %String;

/// The public setting onlineDemo before the test.
Property SavedOnline As %String;

/// The TZ of the process before the test: -1 when it was undefined.
Property SavedZone As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Sessions = ""
	Set ..Day = ""
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..SavedZone = $SYSTEM.Process.TimeZone()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do $SYSTEM.Process.TimeZone($Select(..SavedZone = -1: "", 1: ..SavedZone))
	If ..Day '= "" Kill ^OcuTalonBP.UsageCapped(..Day)
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ..Forget($Piece(..Sessions, ",", i))
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $$$OK
}

Method TestBeatNowContract()
{
	Do ..AssertContract("Contracts")
	Do ..AssertMessageExtent("Contracts")
}

Method TestSettingNames()
{
	Set ref = "zzbeatname"
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "interval"), "person.zzbeatname.heartbeat.interval", "a known name gives its key")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "zz"), "", "an unknown name gives empty")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, ""), "", "so does an empty name")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "on,interval"), "", "and a list of names")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "ON"), "", "a name in another case is unknown")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "int"), "", "so is a part of a name")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "interval "), "", "and a name with a space after it")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "interval,"), "", "and with a comma after it")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", "zzother", "on"), "person.zzother.heartbeat.on", "each session has its own key")
	Set keys = $ListFromString($Parameter(..#BEAT, "KEYS"))
	Set position = 0
	While $ListNext(keys, position, name) {
		Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, name), "person.zzbeatname.heartbeat."_name, "the key of "_name)
	}
	Do $$$AssertEquals($Parameter(..#BEAT, "KEYS"), "on,interval,from,to,checklist", "the keys")
	Do $$$AssertEquals($Parameter(..#BEAT, "INTERVALS"), "30,60,120,240,480,1440", "the intervals")
	Do $$$AssertEquals($Parameter(..#BEAT, "DEFAULTON"), 1, "on by default")
	Do $$$AssertEquals($Parameter(..#BEAT, "DEFAULTONDEMO"), 0, "and off on the online demo")
	Do $$$AssertEquals($Parameter(..#BEAT, "DEFAULTINTERVAL"), 30, "the default interval")
	Do $$$AssertEquals($Parameter(..#BEAT, "DEFAULTFROM"), "08:00", "the default start of the window")
	Do $$$AssertEquals($Parameter(..#BEAT, "DEFAULTTO"), "20:00", "the default end of the window")
	Do $$$AssertEquals($Parameter(..#BEAT, "CHECKLISTMAX"), 1000, "the checklist cap")
	Set value = ##class(%Dictionary.CompiledProperty).%OpenId("OcuTalon.Data.Setting||Value")
	Do $$$AssertEquals($Select($IsObject(value): value.Parameters.GetAt("MAXLEN"), 1: ""), $Parameter(..#BEAT, "CHECKLISTMAX"), "which is the length of Setting.Value (AD-19)")
}

Method TestHeartbeatBeatRowAndUniqueness()
{
	Set first = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set second = ##class(OcuTalon.Bridge.Ids).NewRef()
	Try {
		Set row = ##class(OcuTalon.Data.HeartbeatBeat).%New()
		Set row.SessionRef = first
		Set row.NextDueAt = "2030-06-01T12:30:00Z"
		Set row.LastBeatAt = "2030-06-01T12:00:00Z"
		Set row.LastItemId = "item-ref"
		Set row.LastOutcome = "item"
		Set row.LastFallback = 1
		Set row.LastCostUSD = 0.012346
		Set row.LastDecisionRef = "decision-ref"
		Set row.LastTraceSessionId = 4242
		Set row.LastSkipAt = "2030-06-01T11:00:00Z"
		Set row.LastSkipReason = "quiet_hours"
		Set row.LastRunNowAt = "2030-06-01T11:30:00Z"
		Set row.BackoffUntil = "2030-06-01T13:00:00Z"
		Set row.LastSnapshotKey = "snapshot-key"
		Set row.LastQuietKey = "quiet-key"
		Do $$$AssertStatusOK(row.%Save(), "a row with all 15 fields is saved")
		Set id = row.%Id()
		Kill row
		Set row = ..Open(first)
		Do $$$AssertTrue($IsObject(row), "and found again by its SessionRef")
		If $IsObject(row) {
			Do $$$AssertEquals(row.NextDueAt_"|"_row.LastBeatAt_"|"_row.LastItemId_"|"_row.LastOutcome_"|"_row.LastFallback_"|"_row.LastCostUSD_"|"_row.LastDecisionRef_"|"_row.LastTraceSessionId, "2030-06-01T12:30:00Z|2030-06-01T12:00:00Z|item-ref|item|1|.012346|decision-ref|4242", "the first eight fields come back")
			Do $$$AssertEquals(row.LastSkipAt_"|"_row.LastSkipReason_"|"_row.LastRunNowAt_"|"_row.BackoffUntil_"|"_row.LastSnapshotKey_"|"_row.LastQuietKey, "2030-06-01T11:00:00Z|quiet_hours|2030-06-01T11:30:00Z|2030-06-01T13:00:00Z|snapshot-key|quiet-key", "and so do the other six")
		}
		Do $$$AssertTrue($Data(^OcuTalonP.HeartbeatBeatD(id)), "the row is in the private data global ^OcuTalonP.HeartbeatBeatD")
		Do $$$AssertEquals($Data(^OcuTalon.HeartbeatBeatD) + $Data(^OcuTalon.Data.HeartbeatBeatD), 0, "and in no default global")

		// a second row of the same SessionRef is refused; another SessionRef is accepted
		Set duplicate = ##class(OcuTalon.Data.HeartbeatBeat).%New()
		Set duplicate.SessionRef = first
		Set duplicate.NextDueAt = "2031-01-01T00:00:00Z"
		Do $$$AssertStatusNotOK(duplicate.%Save(), "a second row of the same SessionRef is refused")
		Do $$$AssertEquals(..Rows(first), 1, "so the session still has one row")
		Set row = ..Open(first)
		Do $$$AssertEquals(row.NextDueAt, "2030-06-01T12:30:00Z", "and the first row is untouched")
		Set other = ##class(OcuTalon.Data.HeartbeatBeat).%New()
		Set other.SessionRef = second
		Do $$$AssertStatusOK(other.%Save(), "a row of another SessionRef is saved")
		Set other = ..Open(second)
		Do $$$AssertEquals(other.LastFallback_"|"_other.NextDueAt_"|"_other.LastTraceSessionId, "0||", "and an empty row has fallback 0 and empty times")
	} Catch exception {
		Do $$$AssertTrue(0, "no exception: "_exception.DisplayString())
	}
	Kill row, duplicate, other
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.HeartbeatBeat WHERE SessionRef IN (?, ?)", first, second)
	Do $$$AssertEquals(..Rows(first) + ..Rows(second), 0, "the fixture rows are removed")
}

Method TestValues()
{
	Set ref = ..Person("", {"NextDueAt": "2099-12-31T00:00:00Z"})
	Set values = ..BValues(ref)
	Do $$$AssertEquals(values.on_"|"_values.interval_"|"_values.from_"|"_values.to_"|"_values.checklist, "1|30|08:00|20:00|", "a person with no settings has the defaults")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertEquals(..BValues(ref).on, 0, "on is off by default on the online demo")
	Do ..Put(ref, "on", "1")
	Do $$$AssertEquals(..BValues(ref).on, 1, "and a stored on of 1 turns it on")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do ..Put(ref, "on", "0")
	Do $$$AssertEquals(..BValues(ref).on, 0, "a stored on of 0 is off")
	For stored = 60, 120, 240, 480, 1440 {
		Do ..Put(ref, "interval", stored)
		Do $$$AssertEquals(..BValues(ref).interval, stored, "the allowed interval "_stored_" is read as it is")
	}
	For stored = 15, 10, 0, 45, 90, 2880, "abc", "060" {
		Do ..Put(ref, "interval", stored)
		Do $$$AssertEquals(..BValues(ref).interval, 30, "the interval '"_stored_"' reads as 30, so that nothing under 30 minutes runs")
	}
	Do ..Put(ref, "from", "22:00")
	Do ..Put(ref, "to", "06:00")
	Set values = ..BValues(ref)
	Do $$$AssertEquals(values.from_"|"_values.to, "22:00|06:00", "a stored window is read as it is")
	Do ..Put(ref, "from", "")
	Do ..Put(ref, "to", "")
	Set values = ..BValues(ref)
	Do $$$AssertEquals(values.from_"|"_values.to, "|", "from and to both stored as empty mean all day")
	Do ..Put(ref, "from", "08:00")
	Set values = ..BValues(ref)
	Do $$$AssertEquals(values.from_"|"_values.to, "08:00|20:00", "only one of them stored empty is no pair: the defaults")
	For pair = "25:00,20:00", "8:00,20:00", "08:00,24:00", "08:60,20:00", "ab:cd,20:00", "08:00,", ",20:00", "0800,2000" {
		Do ..Put(ref, "from", $Piece(pair, ",", 1))
		Do ..Put(ref, "to", $Piece(pair, ",", 2))
		Set values = ..BValues(ref)
		Do $$$AssertEquals(values.from_"|"_values.to, "08:00|20:00", "the pair '"_pair_"' reads as the defaults")
	}
	Do ..Put(ref, "checklist", "check the orders")
	Do $$$AssertEquals(..BValues(ref).checklist, "check the orders", "the checklist is read as it is")
}

Method TestActiveHours()
{
	Set over = ..V("c", "22:00", "06:00")
	For clock = "23:00", "05:00", "22:00", "00:00", "05:59" {
		Do $$$AssertTrue(..BHours(over, ..Local(clock)), "local "_clock_" is inside 22:00 to 06:00")
	}
	For clock = "12:00", "06:00", "21:59", "07:00" {
		Do $$$AssertNotTrue(..BHours(over, ..Local(clock)), "local "_clock_" is outside 22:00 to 06:00")
	}
	Set normal = ..V("c", "08:00", "20:00")
	For clock = "08:00", "12:00", "19:59" {
		Do $$$AssertTrue(..BHours(normal, ..Local(clock)), "local "_clock_" is inside 08:00 to 20:00")
	}
	For clock = "21:00", "07:00", "20:00", "00:00" {
		Do $$$AssertNotTrue(..BHours(normal, ..Local(clock)), "local "_clock_" is outside 08:00 to 20:00")
	}
	Do $$$AssertTrue(..BHours(..V("c", "09:00", "09:00"), ..Local("03:00")), "from = to counts as all day")
	Do $$$AssertTrue(..BHours(..V("c", "", ""), ..Local("03:00")), "and so does an empty pair")

	// the hours are the instance zone's: New York is 5 hours behind UTC in January
	Do $SYSTEM.Process.TimeZone("America/New_York")
	Do $$$AssertEquals(##class(OcuTalon.Data.Time).ToLocal("2099-01-15T22:00:00Z"), "2099-01-15T17:00:00", "the zone is in force: 22:00Z is 17:00 local")
	Do $$$AssertTrue(..BHours(normal, "2099-01-15T22:00:00Z"), "22:00Z is 17:00 local, inside 08:00 to 20:00")
	Do $$$AssertTrue(..BHours(normal, "2099-01-15T13:00:00Z"), "13:00Z is 08:00 local, inside")
	Do $$$AssertNotTrue(..BHours(normal, "2099-01-15T12:59:00Z"), "12:59Z is 07:59 local, outside")
	Do $$$AssertNotTrue(..BHours(normal, "2099-01-16T01:00:00Z"), "01:00Z is 20:00 local, outside")
}

Method TestNextDue()
{
	Set noon = ..Local("12:00")
	Set normal = ..V("c", "08:00", "20:00", 60)
	Do $$$AssertEquals(..BNext(normal, noon, "empty"), ..Plus(noon, 3600), "a skip for another reason waits one interval")
	Do $$$AssertEquals(..BNext(normal, noon, "unchanged"), ..Plus(noon, 3600), "unchanged too")
	Do $$$AssertEquals(..BNext(normal, ..Local("21:00"), "hours"), ..Local("08:00", "2099-06-16"), "outside a normal window in the evening the next start is tomorrow's")
	Do $$$AssertEquals(..BNext(normal, ..Local("07:00"), "hours"), ..Local("08:00"), "and in the morning today's")
	Do $$$AssertEquals(..BNext(..V("c", "22:00", "06:00", 60), noon, "hours"), ..Local("22:00"), "outside a window over midnight the next start is today's 22:00")
	Do $$$AssertEquals(..BNext(..V("c", "22:00", "06:00", 60), ..Local("06:00"), "hours"), ..Local("22:00"), "from the end of such a window too")
	Do $$$AssertEquals(..BNext(..V("c", "", "", 120), noon, "hours"), ..Plus(noon, 7200), "an all-day window has no start to wait for")

	// the start is the instance zone's: New York is 5 hours behind UTC in January
	Do $SYSTEM.Process.TimeZone("America/New_York")
	Do $$$AssertEquals(..BNext(normal, "2099-01-15T12:00:00Z", "hours"), "2099-01-15T13:00:00Z", "at 07:00 local the next start is today's 08:00 local, 13:00Z")
	Do $$$AssertEquals(..BNext(normal, "2099-01-15T13:00:00Z", "hours"), "2099-01-16T13:00:00Z", "and at 08:00 local, tomorrow's")
}

Method TestSkipOrder()
{
	Do ..Case("none", "", 0, 0, 0, 0, 0, 0, 0)
	Do ..Case("empty alone", "empty", 1, 0, 0, 0, 0, 0, 0)
	Do ..Case("hours alone", "hours", 0, 1, 0, 0, 0, 0, 0)
	Do ..Case("backoff alone", "backoff", 0, 0, 1, 0, 0, 0, 0)
	Do ..Case("cap alone", "cap", 0, 0, 0, 1, 0, 0, 0)
	Do ..Case("nokey alone", "nokey", 0, 0, 0, 0, 1, 0, 0)
	Do ..Case("unchanged alone", "unchanged", 0, 0, 0, 0, 0, 1, 0)
	Do ..Case("empty and hours", "empty", 1, 1, 0, 0, 0, 0, 0)
	Do ..Case("hours and backoff", "hours", 0, 1, 1, 0, 0, 0, 0)
	Do ..Case("backoff and cap", "backoff", 0, 0, 1, 1, 0, 0, 0)
	Do ..Case("cap and nokey", "cap", 0, 0, 0, 1, 1, 0, 0)
	Do ..Case("nokey and unchanged", "nokey", 0, 0, 0, 0, 1, 1, 0)
	Do ..Case("empty and unchanged", "empty", 1, 0, 0, 0, 0, 1, 0)
	Do ..Case("hours and cap", "hours", 0, 1, 0, 1, 0, 0, 0)
	Do ..Case("all six", "empty", 1, 1, 1, 1, 1, 1, 0)
	Do ..Case("run now: none", "", 0, 0, 0, 0, 0, 0, 1)
	Do ..Case("run now: hours do not hold it", "", 0, 1, 0, 0, 0, 0, 1)
	Do ..Case("run now: unchanged does not hold it", "", 0, 0, 0, 0, 0, 1, 1)
	Do ..Case("run now: empty", "empty", 1, 1, 0, 0, 0, 1, 1)
	Do ..Case("run now: backoff", "backoff", 0, 1, 1, 0, 0, 1, 1)
	Do ..Case("run now: cap", "cap", 0, 1, 0, 1, 0, 1, 1)
	Do ..Case("run now: nokey", "nokey", 0, 1, 0, 0, 1, 1, 1)
	Set noon = ..Local("12:00")
	Set values = ..V("c")
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).%New()
	Set row.LastQuietKey = "k"
	Do $$$AssertEquals(..BSkip(values, row, noon, 0, 0, 1, ""), "", "an empty key leaves unchanged out")
	Set row.LastQuietKey = ""
	Do $$$AssertEquals(..BSkip(values, row, noon, 0, 0, 1, "k"), "", "an empty LastQuietKey never matches")
	Do $$$AssertEquals(..BSkip(values, row, noon, 0, 0, 1, ""), "", "not even an empty key")
	Set row.LastQuietKey = "k"
	Set row.BackoffUntil = noon
	Do $$$AssertEquals(..BSkip(values, row, noon, 0, 0, 1, "j"), "", "a back-off that ends now no longer holds")
	Set row.BackoffUntil = ..Plus(noon, 1)
	Do $$$AssertEquals(..BSkip(values, row, noon, 0, 0, 1, "j"), "backoff", "and one that ends a second later does")
	Do $$$AssertEquals(..BSkip(values, "", noon, 0, 0, 1, "k"), "", "a person with no row skips for nothing")
}

Method TestKey()
{
	Set key = ..BKey("check the orders")
	Do $$$AssertTrue(key ? 64(1N,1"a",1"b",1"c",1"d",1"e",1"f"), "the key is 64 lower-case hexadecimal characters: "_key)
	Do $$$AssertEquals(..BKey("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "it is the SHA-256 of the text")
	Do $$$AssertEquals(..BKey("check the orders"), key, "it is stable")
	Set status = $Char(10)_"Status at 12:00 (built by OcuTalon):"
	Do $$$AssertEquals(..BKey("check the orders"_status), key, "a status line does not change it")
	Do $$$AssertEquals(..BKey("check the orders"_$Char(10)_"Status at 13:45 on Monday (built by OcuTalon):"), key, "whatever its time")
	Do $$$AssertEquals(..BKey("Status at 12:00 (built by OcuTalon):"_$Char(10)_"check the orders"), key, "and wherever it is")
	Do $$$AssertNotTrue(..BKey("check the orders!") = key, "a changed checklist changes it")
	Do $$$AssertNotTrue(..BKey("check the orders"_$Char(10)_"Status at 12:00 and more") = key, "a line that only starts like the status line is part of the text")
	Do $$$AssertEquals(..BKey($Char(233)), "4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c", "a character of 128 to 255 is hashed as UTF-8")
	Do $$$AssertEquals(..BKey($Char(8364)), "c4cc90ed3d26f12d4b08a75140970a7904035c31cbb4515a83f19b9003c00d1d", "and so is one above 255")
	Do $$$AssertNotTrue(..BKey($Char(10)_"abc") = ..BKey("abc"), "a leading empty line is part of the text")
	Do $$$AssertEquals(..BKey("Status at 12:00 (built by OcuTalon):"_$Char(10, 10)_"abc"), ..BKey($Char(10)_"abc"), "and the line of the status takes only itself with it")
	Set ref = ..Person("check the orders", {"NextDueAt": "2099-12-31T00:00:00Z"})
	Set lf = $Char(10)
	Set snapshot = ..BSnap(ref, ..Local("12:00"))
	Do $$$AssertEquals(snapshot, "check the orders"_lf_lf_"Status at 2099-06-15 12:00 (built by OcuTalon):"_lf_"Incidents: none"_lf_"Watches: none"_lf_"Approval requests: none"_lf_"Reminders: none"_lf_"Decisions: none", "a person with no rows: the checklist, a blank line, the status line and a none line for each of the five kinds")
	Do $$$AssertEquals(..BKey(snapshot), ..BKey("check the orders"_lf_lf_"Incidents: none"_lf_"Watches: none"_lf_"Approval requests: none"_lf_"Reminders: none"_lf_"Decisions: none"), "its key is that of the text without the status line")
	Do $$$AssertEquals(..BKey(..BSnap(ref, ..Local("13:45"))), ..BKey(snapshot), "so a snapshot at another time has the same key")
}

Method TestDueSelection()
{
	Set noon = ..Local("12:00")
	Set stale = ..BKey("an earlier checklist")

	// not due
	Set notDue = ..Person("not due", {"NextDueAt": (..Plus(noon, 600)), "LastQuietKey": (stale)})
	// no row, empty checklist
	Set fresh = ..Person()
	// off
	Set off = ..Person("off", {"NextDueAt": (..Plus(noon, -60)), "LastQuietKey": (stale)})
	Do ..Put(off, "on", "0")
	Set sc = ..BDue(noon, .items, notDue_","_fresh_","_off)
	Do $$$AssertStatusOK(sc, "RunDue is OK")
	Do $$$AssertEquals(items.Count(), 0, "no beat runs: a beat that is not due, an empty checklist and an off person send nothing")
	Set row = ..Open(notDue)
	Do $$$AssertEquals(row.NextDueAt_"|"_row.LastBeatAt_"|"_row.LastSkipAt_"|"_row.LastItemId, ..Plus(noon, 600)_"|||", "the row that is not due is unchanged")
	Set row = ..Open(fresh)
	Do $$$AssertTrue($IsObject(row), "a person with no row gets one")
	If $IsObject(row) Do $$$AssertEquals(row.LastSkipAt_"|"_row.LastSkipReason_"|"_row.NextDueAt, noon_"|empty|"_..Plus(noon, 1800), "recording the empty skip at the tick, and the next due time one interval on")
	Set row = ..Open(off)
	Do $$$AssertEquals(row.NextDueAt_"|"_row.LastSkipAt_"|"_row.LastItemId, ..Plus(noon, -60)_"||", "nothing is written for a person who is off")

	// the slack
	Set early = ..Person("early", {"NextDueAt": (..Plus(noon, 5)), "LastQuietKey": (stale)})
	Set later = ..Person("later", {"NextDueAt": (..Plus(noon, 6)), "LastQuietKey": (stale)})
	Do $$$AssertStatusOK(..BDue(noon, .items, early_","_later), "RunDue is OK again")
	Do $$$AssertEquals(items.Count(), 1, "a beat due 5 seconds after the tick runs, one due 6 seconds after does not")
	If items.Count() = 1 Do $$$AssertEquals(items.GetAt(1).SessionRef, early, "it is the first one's")

	// restart: a beat missed by hours runs once
	Set restart = ..Person("restart", {"NextDueAt": (..Plus(noon, -10800)), "LastQuietKey": (stale)})
	Do $$$AssertStatusOK(..BDue(noon, .items, restart), "RunDue is OK at the first tick")
	Do $$$AssertEquals(items.Count(), 1, "the missed beat runs once at the first tick")
	Set row = ..Open(restart)
	Do $$$AssertEquals(row.LastBeatAt_"|"_row.NextDueAt, noon_"|"_..Plus(noon, 1800), "its next due time is the tick plus one interval")
	Do $$$AssertStatusOK(..BDue(..Plus(noon, 60), .items, restart), "RunDue is OK at the next tick")
	Do $$$AssertEquals(items.Count(), 0, "and the tick a minute later runs none")
	Set row = ..Open(restart)
	Do $$$AssertEquals(row.NextDueAt, ..Plus(noon, 1800), "leaving the next due time as it was")
}

Method TestBeatRow()
{
	Set noon = ..Local("12:00")
	Set ref = ..Person("watch the orders production", {"NextDueAt": (noon), "LastQuietKey": (..BKey("another text")), "LastOutcome": "ignore", "LastFallback": 1, "LastCostUSD": 0.5, "LastDecisionRef": "olddecision", "LastTraceSessionId": 7})
	Set snapshot = ..BSnap(ref, noon)
	Do $$$AssertStatusOK(..BDue(noon, .items, ref), "RunDue is OK")
	Do $$$AssertEquals(items.Count(), 1, "one beat runs")
	If items.Count() '= 1 Quit
	Set item = items.GetAt(1)
	Do $$$AssertTrue(item.ItemId '= "", "the Item has a new ItemId")
	Do $$$AssertEquals(item.Provenance_"|"_item.Channel_"|"_item.SessionRef_"|"_item.Subject_"|"_item.Text, "untrusted|heartbeat|"_ref_"|Heartbeat check-in|"_snapshot, "it is untrusted, on the heartbeat channel, for the person, with the subject and the snapshot")
	Do $$$AssertEquals(item.Sender, "", "and it has no sender")
	Do $$$AssertEquals($Piece(item.Text, $Char(10, 10), 1), "watch the orders production", "which starts with the checklist")
	Set row = ..Open(ref)
	Do $$$AssertEquals(row.LastBeatAt_"|"_row.LastItemId_"|"_row.LastSnapshotKey_"|"_row.NextDueAt, noon_"|"_item.ItemId_"|"_..BKey(snapshot)_"|"_..Plus(noon, 1800), "the row records the beat, its Item, the snapshot's key and the next due time")
	Do $$$AssertEquals(row.LastOutcome_"|"_row.LastFallback_"|"_row.LastCostUSD_"|"_row.LastDecisionRef_"|"_row.LastTraceSessionId, "|0|||", "the five decision fields are cleared, so that the beat is pending")
	Do $$$AssertEquals(row.LastQuietKey, ..BKey("another text"), "the quiet key is left as it was")
	Do $$$AssertEquals(row.LastSkipAt_"|"_row.LastSkipReason, "|", "and no skip is recorded")
	Do ..Put(ref, "interval", 60)
	Set row.NextDueAt = ""
	Do row.%Save()
	Do $$$AssertStatusOK(..BDue(..Plus(noon, 60), .items, ref), "RunDue is OK again")
	Set row = ..Open(ref)
	Do $$$AssertEquals(row.NextDueAt, ..Plus(noon, 3660), "an interval of 60 minutes moves the next due time by an hour")
}

Method TestDecisionIsRecorded()
{
	Set noon = ..Local("12:00")
	Set tick = ..Plus(noon, 60)
	Set quiet = ..BKey("what the beat read")
	Set due = ..Plus(noon, 1800)

	// ignore
	Set ignored = ..Person("c", {"NextDueAt": (due), "LastItemId": "itemignore", "LastSnapshotKey": (quiet)})
	Set decision = ..Decision(ignored, "itemignore", {"Outcome": "ignore", "CostUSD": 0.0004, "TraceSessionId": 4242})
	// pending: no decision yet
	Set pending = ..Person("c", {"NextDueAt": (due), "LastItemId": "itempending", "LastSnapshotKey": (quiet)})
	// fallback, 30 minutes
	Set fallen = ..Person("c", {"NextDueAt": (due), "LastItemId": "itemfallen", "LastSnapshotKey": (quiet)})
	Do ..Decision(fallen, "itemfallen", {"Outcome": "tellnow", "Fallback": 1})
	// fallback, a day
	Set day = ..Person("c", {"NextDueAt": (due), "LastItemId": "itemday", "LastSnapshotKey": (quiet)})
	Do ..Put(day, "interval", 1440)
	Do ..Decision(day, "itemday", {"Outcome": "tellnow", "Fallback": 1})
	// outside the sessions of the call
	Set outside = ..Person("c", {"NextDueAt": (due), "LastItemId": "itemoutside", "LastSnapshotKey": (quiet)})
	Do ..Decision(outside, "itemoutside", {"Outcome": "ignore"})
	Do $$$AssertStatusOK(..BDue(tick, .items, ignored_","_pending_","_fallen_","_day), "RunDue is OK")
	Do $$$AssertEquals(items.Count(), 0, "no beat runs: none is due")
	Set row = ..Open(ignored)
	Do $$$AssertEquals(row.LastOutcome_"|"_row.LastFallback_"|"_row.LastCostUSD_"|"_row.LastDecisionRef_"|"_row.LastTraceSessionId, "ignore|0|.0004|"_decision_"|4242", "the row records the outcome, the fallback, the cost, the decision and its trace session")
	Do $$$AssertEquals(row.LastQuietKey_"|"_row.BackoffUntil, quiet_"|", "an ignore copies the snapshot's key to the quiet key and sets no back-off")
	Set row = ..Open(pending)
	Do $$$AssertEquals(row.LastItemId_"|"_row.LastDecisionRef_"|"_row.LastQuietKey, "itempending||", "a beat with no decision yet stays pending")
	Set row = ..Open(fallen)
	Do $$$AssertEquals(row.LastFallback_"|"_row.BackoffUntil_"|"_row.LastQuietKey, "1|"_..Plus(tick, 14400)_"|", "a fallback holds the beats back for 4 hours and is no quiet reading")
	Set row = ..Open(day)
	Do $$$AssertEquals(row.BackoffUntil, ..Plus(tick, 86400), "and for an interval of a day, for a day")
	Set row = ..Open(outside)
	Do $$$AssertEquals(row.LastDecisionRef_"|"_row.LastQuietKey, "|", "a person outside the sessions of the call is left alone")
	Do $$$AssertStatusOK(..BDue(..Plus(tick, 60), .items, ignored_","_fallen), "RunDue is OK again")
	Set row = ..Open(ignored)
	Do $$$AssertEquals(row.LastDecisionRef, decision, "a recorded decision is not recorded again")
	Set row = ..Open(fallen)
	Do $$$AssertEquals(row.BackoffUntil, ..Plus(tick, 14400), "so a later tick does not move the back-off on")
}

Method TestUnchangedAfterIgnore()
{
	Set noon = ..Local("12:00")
	Set ref = ..Person("same as before", {"NextDueAt": (..Plus(noon, -60))})
	Do ..SetRow(ref, "LastQuietKey", ..BWholeKey(ref, noon))
	Do $$$AssertStatusOK(..BDue(noon, .items, ref), "RunDue is OK")
	Do $$$AssertEquals(items.Count(), 0, "a checklist unchanged since the last ignore sends nothing")
	Set row = ..Open(ref)
	Do $$$AssertEquals(row.LastSkipAt_"|"_row.LastSkipReason_"|"_row.NextDueAt_"|"_row.LastItemId, noon_"|unchanged|"_..Plus(noon, 1800)_"|", "it is skipped as unchanged, one interval on")
	Do ..Put(ref, "checklist", "changed since")
	Do $$$AssertStatusOK(..BDue(..Plus(noon, 1800), .items, ref), "RunDue is OK at the next due time")
	Do $$$AssertEquals(items.Count(), 1, "a changed checklist beats")
}

Method TestRunNow()
{
	Set noon = ..Local("12:00")
	Set late = ..Local("21:00")
	Set far = ..Plus(noon, 86400)

	// hours and unchanged do not hold it; neither does an off person
	Set ref = ..Person("c", {"NextDueAt": (far)})
	Set quiet = ..BWholeKey(ref, late)
	Do ..SetRow(ref, "LastQuietKey", quiet)
	Do ..Put(ref, "on", "0")
	Set sc = ..BNow(ref, late, .item, .outcome, .availableAt)
	Do $$$AssertStatusOK(sc, "RunNow is OK")
	Do $$$AssertEquals(outcome_"|"_availableAt, "sent|", "outside the hours, with an unchanged snapshot and while off, the beat is sent")
	Set row = ..Open(ref)
	Do $$$AssertEquals(row.LastSnapshotKey, quiet, "and the snapshot was unchanged: the key that the beat stores is the quiet key")
	If $IsObject(item) Do $$$AssertEquals(row.LastRunNowAt_"|"_row.NextDueAt_"|"_row.LastItemId_"|"_row.LastBeatAt, late_"|"_..Plus(late, 1800)_"|"_item.ItemId_"|"_late, "the row records the request, moves the next due time to now plus one interval and records the beat")
	Do $$$AssertTrue($IsObject(item), "an Item is returned")
	If $IsObject(item) Do $$$AssertEquals(item.Channel_"|"_item.Text_"|"_item.SessionRef, "heartbeat|"_..BSnap(ref, late)_"|"_ref, "for the person's snapshot")

	// the held reasons
	Set empty = ..Person("", {"NextDueAt": (far)})
	Do ..BNow(empty, noon, .item, .outcome, .availableAt)
	Do $$$AssertEquals(outcome_"|"_$IsObject(item), "empty|0", "an empty checklist holds it")
	Set row = ..Open(empty)
	Do $$$AssertEquals(row.LastRunNowAt_"|"_row.NextDueAt_"|"_row.LastSkipAt, noon_"|"_far_"|", "the request is recorded, the next due time is unchanged and no skip is recorded")
	Set held = ..Person("c", {"NextDueAt": (far), "BackoffUntil": (..Plus(noon, 600))})
	Do ..BNow(held, noon, .item, .outcome, .availableAt)
	Do $$$AssertEquals(outcome_"|"_availableAt_"|"_$IsObject(item), "backoff|"_..Plus(noon, 600)_"|0", "a back-off holds it and says when it ends")
	Set capped = ..Person("c", {"NextDueAt": (far)})
	Do ..BNow(capped, noon, .item, .outcome, .availableAt, 1, 1)
	Do $$$AssertEquals(outcome_"|"_availableAt_"|"_$IsObject(item), "cap||0", "the cap holds it")
	Set keyless = ..Person("c", {"NextDueAt": (far)})
	Do ..BNow(keyless, noon, .item, .outcome, .availableAt, 0, 0)
	Do $$$AssertEquals(outcome_"|"_availableAt_"|"_$IsObject(item), "nokey||0", "so does a missing key")
	Set row = ..Open(keyless)
	Do $$$AssertEquals(row.LastRunNowAt_"|"_row.NextDueAt, noon_"|"_far, "and it is recorded without moving the next due time")

	// the cooldown
	Set cool = ..Person("c", {"NextDueAt": (far), "LastRunNowAt": (..Plus(noon, -119))})
	Do ..BNow(cool, noon, .item, .outcome, .availableAt)
	Do $$$AssertEquals(outcome_"|"_availableAt_"|"_$IsObject(item), "cooldown|"_..Plus(noon, 1)_"|0", "a request 119 seconds after the last one waits, and says when it may run")
	Set row = ..Open(cool)
	Do $$$AssertEquals(row.LastRunNowAt_"|"_row.NextDueAt_"|"_row.LastItemId, ..Plus(noon, -119)_"|"_far_"|", "and writes nothing")
	Set ready = ..Person("c", {"NextDueAt": (far), "LastRunNowAt": (..Plus(noon, -120))})
	Do ..BNow(ready, noon, .item, .outcome, .availableAt)
	Do $$$AssertEquals(outcome_"|"_availableAt_"|"_$IsObject(item), "sent||1", "one 120 seconds after the last one runs")

	// a pending decision is recorded first, also while the cooldown holds
	Set pending = ..Person("c", {"NextDueAt": (far), "LastRunNowAt": (..Plus(noon, -30)), "LastItemId": "itemnow", "LastSnapshotKey": (..BKey("c"))})
	Set decision = ..Decision(pending, "itemnow", {"Outcome": "ignore"})
	Do ..BNow(pending, noon, .item, .outcome, .availableAt)
	Set row = ..Open(pending)
	Do $$$AssertEquals(outcome_"|"_row.LastDecisionRef_"|"_row.LastQuietKey, "cooldown|"_decision_"|"_..BKey("c"), "the cooldown comes after it")

	// a decision that is already recorded is not recorded again, so a run now does not move the back-off on
	Set settled = ..Person("c", {"NextDueAt": (far), "LastItemId": "itemsettled", "LastDecisionRef": "decisionsettled", "LastFallback": 1, "BackoffUntil": (..Plus(noon, 600))})
	Do ..Decision(settled, "itemsettled", {"Outcome": "tellnow", "Fallback": 1})
	Do ..BNow(settled, noon, .item, .outcome, .availableAt)
	Do $$$AssertEquals(outcome_"|"_availableAt_"|"_..Open(settled).BackoffUntil, "backoff|"_..Plus(noon, 600)_"|"_..Plus(noon, 600), "a run now during a back-off leaves it as it is")
}

/// Story 39.8 (AC 1): RunNow reads what is stored, a tick reads through the cache.
Method TestRunNowReadsStoredValues()
{
	Set noon = ..Local("12:00")
	Set text = "check the orders"
	Set ref = ..Person("", {"NextDueAt": (..Plus(noon, -60))})
	Set cached = ..Shape(ref)
	Do $$$AssertEquals(..BValues(ref).checklist, "", "the checklist reads empty, and this process now caches its settings")

	// another process saves the five settings: the rows are saved without Setting.Set, so that this process's cache entries stay
	Do ..Bare(ref, "checklist", text)
	Do ..Bare(ref, "interval", 60)
	Do ..Bare(ref, "on", 0)
	Do $$$AssertEquals(..Shape(ref)_"|"_..BValues(ref).checklist, cached_"|", "precondition: this process still reads the cached settings")

	// a tick reads through the cache
	Do $$$AssertStatusOK(..BDue(noon, .items, ref), "RunDue is OK")
	Do $$$AssertEquals(items.Count(), 0, "the tick reads the cached empty checklist and sends no Item")
	Set row = ..Open(ref)
	Do $$$AssertEquals(row.LastSkipAt_"|"_row.LastSkipReason_"|"_row.LastItemId, noon_"|empty|", "and records the empty skip")

	// run now reads what is stored: all five settings
	Do $$$AssertStatusOK(..BNow(ref, noon, .item, .outcome, .availableAt), "RunNow is OK")
	Do $$$AssertEquals(outcome, "sent", "RunNow sends the beat")
	Do $$$AssertTrue($IsObject(item), "with an Item")
	If $IsObject(item) Do $$$AssertEquals($Piece(item.Text, $Char(10, 10), 1), text, "which starts with the stored checklist")
	Do $$$AssertEquals(..Open(ref).NextDueAt, ..Plus(noon, 3600), "and the next due time is one stored interval on")
	Do $$$AssertEquals(..Shape(ref)_"|"_..BValues(ref).checklist, "0|60|"_text, "and this process's values now read the stored settings")

	// a pending decision is recorded on the stored values too: the back-off of a fallback is the stored interval (480 minutes) after the time
	Set pending = ..Person("check the orders", {"NextDueAt": (..Plus(noon, 86400)), "LastItemId": "itemstored", "LastSnapshotKey": (..BKey("c"))})
	Do ..Decision(pending, "itemstored", {"Outcome": "tellnow", "Fallback": 1})
	Do $$$AssertEquals(..BValues(pending).interval, 30, "the interval reads 30, and this process caches it")
	Do ..Bare(pending, "interval", 480)
	Do $$$AssertStatusOK(..BNow(pending, noon, .item, .outcome, .availableAt), "RunNow is OK with a pending fallback")
	Do $$$AssertEquals(outcome_"|"_availableAt, "backoff|"_..Plus(noon, 28800), "its back-off is the stored interval, not the cached one")
}

/// Story 39.8 (QA; AC 1): RunNow drops the cache entries of all five keys, the active hours (from, to) included, which no other test of the story reads back.
Method TestRunNowDropsAllFiveKeys()
{
	Set noon = ..Local("12:00")
	Set ref = ..Person("", {"NextDueAt": (..Plus(noon, -60))})
	Do ..Bare(ref, "on", 1)
	Do ..Bare(ref, "interval", 30)
	Do ..Bare(ref, "from", "07:00")
	Do ..Bare(ref, "to", "19:00")
	Do ..Bare(ref, "checklist", "old list")
	Set cached = ..BValues(ref)
	Set first = cached.on_"|"_cached.interval_"|"_cached.from_"|"_cached.to_"|"_cached.checklist
	Do $$$AssertEquals(first, "1|30|07:00|19:00|old list", "this process caches the five settings")

	// another process saves all five settings anew: the rows are saved without Setting.Set, so that this process's cache entries stay
	Do ..Bare(ref, "on", 0)
	Do ..Bare(ref, "interval", 60)
	Do ..Bare(ref, "from", "09:00")
	Do ..Bare(ref, "to", "17:00")
	Do ..Bare(ref, "checklist", "check the orders")
	Set still = ..BValues(ref)
	Do $$$AssertEquals(still.on_"|"_still.interval_"|"_still.from_"|"_still.to_"|"_still.checklist, first, "precondition: this process still reads the cached settings")

	Do $$$AssertStatusOK(..BNow(ref, noon, .item, .outcome, .availableAt), "RunNow is OK")
	Do $$$AssertEquals(outcome, "sent", "RunNow sends the beat")
	Set read = ..BValues(ref)
	Do $$$AssertEquals(read.on_"|"_read.interval_"|"_read.from_"|"_read.to_"|"_read.checklist, "0|60|09:00|17:00|check the orders", "and all five values now read what is stored")
}

/// Story 39.8 (AC 2, AC 3): a saved shorter interval moves the NextDueAt that a longer interval set; a longer one, an hours skip, an off person and a row with no base do not.
Method TestSavedIntervalMovesNextDue()
{
	Set b = ..Local("12:00")

	// shorter, the new time ahead: saved on the tick, no view, no Item; the next tick writes nothing; the tick at the new time beats
	Set ahead = ..Person("c", {"LastBeatAt": (b), "NextDueAt": (..Plus(b, 3600))})
	Do $$$AssertStatusOK(..BDue(..Plus(b, 60), .items, ahead, 0, 1, .views), "RunDue is OK one minute after the beat")
	Set row = ..Open(ahead)
	Do $$$AssertEquals(items.Count()_"|"_+$Get(views)_"|"_row.NextDueAt_"|"_row.LastBeatAt_"|"_row.LastItemId_"|"_row.LastSkipAt, "0|0|"_..Plus(b, 1800)_"|"_b_"||", "the new time is the beat plus 30 minutes, saved, with no Item and no view")
	Do $$$AssertStatusOK(..BDue(..Plus(b, 120), .items, ahead, 0, 1, .views), "RunDue is OK again")
	Set row = ..Open(ahead)
	Do $$$AssertEquals(items.Count()_"|"_+$Get(views)_"|"_row.NextDueAt_"|"_row.LastBeatAt, "0|0|"_..Plus(b, 1800)_"|"_b, "the next tick changes nothing and gives no view")
	Do $$$AssertStatusOK(..BDue(..Plus(b, 1800), .items, ahead, 0, 1, .views), "RunDue is OK at the new time")
	Set row = ..Open(ahead)
	Do $$$AssertEquals(items.Count()_"|"_..ViewRefs(.views, ahead)_"|"_row.LastBeatAt_"|"_row.NextDueAt, "1|1:1|"_..Plus(b, 1800)_"|"_..Plus(b, 3600), "the tick at the new time beats once, with one view")
	If +$Get(views) = 1 Do $$$AssertEquals(..ViewJson(.views, 1), ..RowJson(ahead), "which is FromRow of the stored row")

	// shorter, the new time has passed: the beat runs at that tick, one commit
	Set passed = ..Person("c", {"LastBeatAt": (..Plus(b, -2400)), "NextDueAt": (..Plus(b, 1200))})
	Do $$$AssertStatusOK(..BDue(b, .items, passed, 0, 1, .views), "RunDue is OK when the new time has passed")
	Set row = ..Open(passed)
	Do $$$AssertEquals(items.Count()_"|"_..ViewRefs(.views, passed)_"|"_row.LastBeatAt_"|"_row.NextDueAt, "1|1:1|"_b_"|"_..Plus(b, 1800), "the beat runs at the tick, with one view")
	If +$Get(views) = 1 Do $$$AssertEquals(..ViewJson(.views, 1), ..RowJson(passed), "which is FromRow of the stored row")

	// longer: NextDueAt stands until the beat, which uses the new interval
	Set longer = ..Person("c", {"LastBeatAt": (b), "NextDueAt": (..Plus(b, 1800))})
	Do ..Put(longer, "interval", 120)
	Do $$$AssertStatusOK(..BDue(..Plus(b, 60), .items, longer, 0, 1, .views), "RunDue is OK with a longer interval")
	Set row = ..Open(longer)
	Do $$$AssertEquals(items.Count()_"|"_+$Get(views)_"|"_row.NextDueAt, "0|0|"_..Plus(b, 1800), "NextDueAt is kept, with no view")
	Do $$$AssertStatusOK(..BDue(..Plus(b, 1800), .items, longer, 0, 1, .views), "RunDue is OK at the kept time")
	Set row = ..Open(longer)
	Do $$$AssertEquals(items.Count()_"|"_row.LastBeatAt_"|"_row.NextDueAt, "1|"_..Plus(b, 1800)_"|"_..Plus(b, 9000), "the beat there sets NextDueAt with the new interval")

	// a skip set it (a newer cap skip), and an older hours skip does not matter after a newer beat
	Set skipped = ..Person("c", {"LastBeatAt": (..Plus(b, -7200)), "LastSkipAt": (b), "LastSkipReason": "cap", "NextDueAt": (..Plus(b, 3600))})
	Set older = ..Person("c", {"LastBeatAt": (b), "LastSkipAt": (..Plus(b, -7200)), "LastSkipReason": "hours", "NextDueAt": (..Plus(b, 3600))})

	// kept: an hours skip is the newest write; the person is off; the row has no base
	Set hours = ..Person("c", {"LastBeatAt": (..Plus(b, -7200)), "LastSkipAt": (b), "LastSkipReason": "hours", "NextDueAt": (..Plus(b, 43200))})
	Set off = ..Person("c", {"NextDueAt": (..Plus(b, 3600))})
	Do ..Put(off, "on", "0")
	Do ..SetRow(off, "LastBeatAt", b)
	Set bare = ..Person("c", {"NextDueAt": (..Plus(b, 3600))})
	Set all = skipped_","_older_","_hours_","_off_","_bare
	Do $$$AssertStatusOK(..BDue(..Plus(b, 60), .items, all, 0, 1, .views), "RunDue is OK for the rest")
	Do $$$AssertEquals(items.Count()_"|"_+$Get(views), "0|0", "none of them beats or gives a view")
	Do $$$AssertEquals(..Open(skipped).NextDueAt, ..Plus(b, 1800), "a newer skip other than hours moves NextDueAt to the skip plus 30 minutes")
	Do $$$AssertEquals(..Open(older).NextDueAt, ..Plus(b, 1800), "an hours skip older than the beat does not stop the move")
	Do $$$AssertEquals(..Open(hours).NextDueAt, ..Plus(b, 43200), "an hours skip that is the newest write keeps NextDueAt")
	Do $$$AssertEquals(..Open(off).NextDueAt, ..Plus(b, 3600), "an off person keeps NextDueAt")
	Do $$$AssertEquals(..Open(bare).NextDueAt, ..Plus(b, 3600), "a row with no beat and no skip keeps NextDueAt")
}

/// QA: what RunDue writes for each skip, through the whole beat (not Skip and NextDue alone): the reason, the tick, and the next due time, which is the next
/// start of the hours for hours (also when another rule holds too) and one interval on for the others.
Method TestSkipsAreRecordedByRunDue()
{
	Set noon = ..Local("12:00")
	Set late = ..Local("21:00")
	Set start = ..Local("08:00", "2099-06-16")

	// outside the hours: the next start, not one interval on
	Set outside = ..Person("c", {"NextDueAt": (noon)})
	Do $$$AssertStatusOK(..BDue(late, .items, outside), "RunDue is OK outside the hours")
	Do $$$AssertEquals(items.Count(), 0, "outside the hours sends nothing")
	Set row = ..Open(outside)
	Do $$$AssertEquals(row.LastSkipAt_"|"_row.LastSkipReason_"|"_row.NextDueAt_"|"_row.LastItemId, late_"|hours|"_start_"|", "it records hours, and the next start of the hours as the next due time")

	// two rules at once: the first one's next due time
	Set both = ..Person("c", {"NextDueAt": (noon)})
	Do $$$AssertStatusOK(..BDue(late, .items, both, 1), "RunDue is OK outside the hours with the cap reached")
	Set row = ..Open(both)
	Do $$$AssertEquals(items.Count()_"|"_row.LastSkipReason_"|"_row.NextDueAt, "0|hours|"_start, "hours and cap give hours, and its next due time")

	// back-off
	Set backoff = ..Person("c", {"NextDueAt": (noon), "BackoffUntil": (..Plus(noon, 600))})
	Do $$$AssertStatusOK(..BDue(noon, .items, backoff), "RunDue is OK during a back-off")
	Set row = ..Open(backoff)
	Do $$$AssertEquals(items.Count()_"|"_row.LastSkipAt_"|"_row.LastSkipReason_"|"_row.NextDueAt_"|"_row.LastItemId, "0|"_noon_"|backoff|"_..Plus(noon, 1800)_"|", "it records backoff and one interval on")

	// cap
	Set capped = ..Person("c", {"NextDueAt": (noon)})
	Do $$$AssertStatusOK(..BDue(noon, .items, capped, 1), "RunDue is OK with the cap reached")
	Set row = ..Open(capped)
	Do $$$AssertEquals(items.Count()_"|"_row.LastSkipAt_"|"_row.LastSkipReason_"|"_row.NextDueAt_"|"_row.LastItemId, "0|"_noon_"|cap|"_..Plus(noon, 1800)_"|", "it records cap and one interval on")

	// no key
	Set keyless = ..Person("c", {"NextDueAt": (noon)})
	Do $$$AssertStatusOK(..BDue(noon, .items, keyless, 0, 0), "RunDue is OK with no key")
	Set row = ..Open(keyless)
	Do $$$AssertEquals(items.Count()_"|"_row.LastSkipAt_"|"_row.LastSkipReason_"|"_row.NextDueAt_"|"_row.LastItemId, "0|"_noon_"|nokey|"_..Plus(noon, 1800)_"|", "it records nokey and one interval on")

	// a skip after a beat leaves the beat's own fields as they were
	Set beaten = ..Person("c", {"NextDueAt": (noon), "LastBeatAt": (..Plus(noon, -7200)), "LastItemId": "itembefore", "LastSnapshotKey": "keybefore", "LastDecisionRef": "decisionbefore"})
	Do $$$AssertStatusOK(..BDue(noon, .items, beaten, 1), "RunDue is OK with the cap reached after an earlier beat")
	Set row = ..Open(beaten)
	Do $$$AssertEquals(row.LastBeatAt_"|"_row.LastItemId_"|"_row.LastSnapshotKey_"|"_row.LastDecisionRef, ..Plus(noon, -7200)_"|itembefore|keybefore|decisionbefore", "and the earlier beat's fields are left as they were")
}

/// QA: a decision recorded at the start of RunDue counts for the beats of the same call: an Ignore makes the unchanged snapshot skip at once, a fallback holds
/// the same tick back, and an off person's pending decision is recorded all the same.
Method TestRecordedDecisionCountsInTheSameRunDue()
{
	Set noon = ..Local("12:00")
	Set far = ..Plus(noon, 86400)

	// ignore, and the beat is due at the same tick
	Set ignored = ..Person("same", {"NextDueAt": (..Plus(noon, -60)), "LastItemId": "itemsame"})
	Set ignoreRef = ..Decision(ignored, "itemsame", {"Outcome": "ignore", "Summary": "Heartbeat check-in"})
	Set sameKey = ..BWholeKey(ignored, noon)
	Do ..SetRow(ignored, "LastSnapshotKey", sameKey)

	// fallback, and the beat is due at the same tick
	Set fallen = ..Person("c", {"NextDueAt": (..Plus(noon, -60)), "LastItemId": "itemfall", "LastSnapshotKey": (..BKey("c"))})
	Set fallRef = ..Decision(fallen, "itemfall", {"Outcome": "tellnow", "Fallback": 1})

	// off, with a pending decision
	Set off = ..Person("same", {"NextDueAt": (far), "LastItemId": "itemoff", "LastSnapshotKey": (..BKey("same"))})
	Do ..Put(off, "on", "0")
	Set offRef = ..Decision(off, "itemoff", {"Outcome": "ignore"})
	Do $$$AssertStatusOK(..BDue(noon, .items, ignored_","_fallen_","_off), "RunDue is OK")
	Do $$$AssertEquals(items.Count(), 0, "no Item is sent: the settled decisions hold both due beats")
	Set row = ..Open(ignored)
	Do $$$AssertEquals(row.LastDecisionRef_"|"_row.LastQuietKey_"|"_row.LastSkipReason_"|"_row.NextDueAt, ignoreRef_"|"_sameKey_"|unchanged|"_..Plus(noon, 1800), "the ignore is recorded first, so the due beat is skipped as unchanged")
	Set row = ..Open(fallen)
	Do $$$AssertEquals(row.LastDecisionRef_"|"_row.BackoffUntil_"|"_row.LastSkipReason_"|"_row.NextDueAt, fallRef_"|"_..Plus(noon, 14400)_"|backoff|"_..Plus(noon, 1800), "the fallback is recorded first, so the due beat is skipped for the back-off")
	Set row = ..Open(off)
	Do $$$AssertEquals(row.LastDecisionRef_"|"_row.LastQuietKey_"|"_row.NextDueAt_"|"_row.LastSkipAt, offRef_"|"_..BKey("same")_"|"_far_"|", "an off person's pending decision is recorded too, and nothing else is written")
}

Method TestOneFailureLeavesTheOthers()
{
	Set noon = ..Local("12:00")
	Set b = ..Person("b", {"NextDueAt": (noon)})
	Set a = ..Person("a", {"NextDueAt": (noon)})

	// B comes first. B's row cannot be opened (its node is gone and its index entry is not), so B's new row is refused: the SessionRef is not unique
	Set sc = ..BDueBroken(b, "", noon, .items, b_","_a)
	Do $$$AssertStatusNotOK(sc, "RunDue answers an error status")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue($Piece(text, "error codes ", 2) ? 1.N, "which holds the error code: "_text)
	Do $$$AssertTrue(text [ "1 heartbeat beat failed", "and the count: "_text)
	Do $$$AssertNotTrue((text [ a) || (text [ b), "and no SessionRef")
	Do $$$AssertEquals(items.Count(), 1, "A still beats")
	If items.Count() = 1 Do $$$AssertEquals(items.GetAt(1).SessionRef, a, "the one Item is A's")
	Set row = ..Open(a)
	Do $$$AssertEquals(row.LastBeatAt, noon, "and A's row records it")
}

Method TestFailedDecisionHoldsTheBeat()
{
	Set noon = ..Local("12:00")
	Set b = ..Person("b", {"NextDueAt": (noon), "LastItemId": "itemb", "LastSnapshotKey": (..BKey("b"))})
	Set a = ..Person("a", {"NextDueAt": (noon), "LastItemId": "itema", "LastSnapshotKey": (..BKey("an earlier text"))})
	Do ..Decision(b, "itemb", {"Outcome": "ignore"})
	Do ..Decision(a, "itema", {"Outcome": "ignore"})

	// B's stored snapshot key is 65 characters, written straight into its node, so that its copy to LastQuietKey fails the save
	Set id = ..Open(b).%Id()
	Set $List(^OcuTalonP.HeartbeatBeatD(id), 15) = ..BKey("b")_"0"
	Set sc = ..BDue(noon, .items, b_","_a)
	Do $$$AssertStatusNotOK(sc, "RunDue answers an error status")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue(text [ "1 heartbeat beat failed", "which counts the person once: "_text)
	Do $$$AssertTrue($Piece(text, "error codes ", 2) ? 1.N, "and holds the error code: "_text)
	Do $$$AssertNotTrue((text [ a) || (text [ b), "and no SessionRef")
	Do $$$AssertEquals(items.Count(), 1, "one beat runs")
	If items.Count() = 1 Do $$$AssertEquals(items.GetAt(1).SessionRef, a, "A's, whose decision is recorded after B's failure")
	Do $$$AssertEquals(..Open(a).LastQuietKey, ..BKey("an earlier text"), "A's ignore is recorded")
	Set row = ..Open(b)
	Do $$$AssertEquals(row.LastItemId_"|"_row.LastBeatAt_"|"_row.NextDueAt, "itemb||"_noon, "B stays pending, for its decision to be recorded on a later tick")
}

Method TestUnreadableRowIsReported()
{
	Set noon = ..Local("12:00")
	Set a = ..Person("a", {"NextDueAt": (noon)})
	Set b = ..Person("b", {"NextDueAt": (..Plus(noon, 86400))})
	Set sc = ..BDueBroken(b, "not a list", noon, .items, a)
	Do $$$AssertStatusNotOK(sc, "a row that stops the read of the rows gives an error status, not a quiet OK")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "error codes 5001", "with the error code")
	Do $$$AssertEquals(items.Count(), 1, "and the people still beat")
}

Method TestInputsAreRead()
{
	Set noon = ..Local("12:00", "2099-07-01")
	Set ..Day = ##class(OcuTalon.Bridge.Time).LocalDate(noon)
	Do $$$AssertEquals(..BCapped(noon), 0, "the cap is not reached on a day with no mark")
	Set ^OcuTalonBP.UsageCapped(..Day) = noon
	Do $$$AssertEquals(..BCapped(noon), 1, "a day marked as capped reads as capped")
	Do $$$AssertEquals(..BCapped(..Local("12:00", "2099-07-02")), 0, "and the next day does not")
	Set ref = ..Person("c", {"NextDueAt": (noon)})
	Do $$$AssertStatusOK(..BDue(noon, .items, ref, "", 1), "RunDue is OK with the cap left to be read")
	Set row = ..Open(ref)
	Do $$$AssertEquals(items.Count()_"|"_row.LastSkipReason, "0|cap", "it skips for the cap of that day")
	Set other = ..Person("c", {"NextDueAt": (noon)})
	Do $$$AssertStatusOK($ClassMethod(..#BEAT, "RunNow", other, noon, .item, .outcome, .availableAt), "RunNow is OK with the cap and the key left to be read")
	Do $$$AssertEquals(outcome, "cap", "and it holds a run now for the cap of that day")
	Kill ^OcuTalonBP.UsageCapped(..Day)
	Set ..Day = ""
	Do $$$AssertEquals(..BCapped(noon), 0, "a mark that is gone no longer caps")
	Do $$$AssertEquals(..BKeyed(), +##class(OcuTalon.Bridge.Keys).Status("TriageAgent"), "Keyed is the TriageAgent's key state")
}

/// Story 39.7: RunDue and RunNow give one view for each commit of a row, in commit order, each Heartbeat.FromRow of the row as saved and the settings. Nothing is
/// viewed for a call that commits nothing.
Method TestViewsInCommitOrder()
{
	Set noon = ..Local("12:00")
	Set far = ..Plus(noon, 86400)

	// RunDue: a recorded ignore then the unchanged skip (two commits of one person), an off person's recorded decision, a person who is not due and an off person
	Set ignored = ..Person("same", {"NextDueAt": (..Plus(noon, -60)), "LastItemId": "itemsame"})
	Do ..Decision(ignored, "itemsame", {"Outcome": "ignore", "Summary": "Heartbeat check-in"})
	Do ..SetRow(ignored, "LastSnapshotKey", ..BWholeKey(ignored, noon))
	Set off = ..Person("same", {"NextDueAt": (far), "LastItemId": "itemoff", "LastSnapshotKey": (..BKey("same"))})
	Do ..Put(off, "on", "0")
	Do ..Decision(off, "itemoff", {"Outcome": "ignore"})
	Set idle = ..Person("c", {"NextDueAt": (far)})
	Set silent = ..Person("c", {"NextDueAt": (..Plus(noon, -60))})
	Do ..Put(silent, "on", "0")
	Set all = ignored_","_off_","_idle_","_silent
	Do $$$AssertStatusOK(..BDue(noon, .items, all, 0, 1, .views), "RunDue is OK")
	Do $$$AssertEquals(..ViewRefs(.views, all), "3:1,2,1", "three views: the recorded ignore, the off person's recorded decision and the unchanged skip, and none for the idle and the off person")
	Set first = ..ViewJson(.views, 1)
	Set exported = ##class(%DynamicObject).%FromJSON(first)
	Do $$$AssertEquals(exported.lastOutcome_"|"_exported.%IsDefined("lastSkipAt")_"|"_exported.%IsDefined("lastBeatAt")_"|"_exported.traceHeaderId_"|"_exported.traceNamespace, "ignore|0|0|42|"_$Namespace, "the first view holds the recorded result and no skip yet, with the decision's trace")
	Set second = ##class(%DynamicObject).%FromJSON(..ViewJson(.views, 2))
	Do $$$AssertEquals(second.on_"|"_second.lastOutcome_"|"_second.nextDueAt, "0|ignore|"_far, "the off person's view says off, with the result recorded and the schedule as it was")
	Do $$$AssertEquals(..ViewJson(.views, 2), ..RowJson(off), "and it is FromRow of the reopened row")
	Do $$$AssertEquals(..ViewJson(.views, 3), ..RowJson(ignored), "the last view is FromRow of the reopened row")
	Set third = ##class(%DynamicObject).%FromJSON(..ViewJson(.views, 3))
	Do $$$AssertEquals(third.lastSkipAt_"|"_third.lastSkipReason_"|"_third.lastOutcome_"|"_third.nextDueAt, noon_"|unchanged|ignore|"_..Plus(noon, 1800), "which holds the skip, the recorded result and the moved schedule")

	// RunDue with nothing to commit
	Do $$$AssertStatusOK(..BDue(noon, .items, idle_","_silent, 0, 1, .views), "RunDue is OK for a person who is not due and an off person with nothing pending")
	Do $$$AssertEquals(+$Get(views), 0, "and gives no view")

	// a beat that runs: one view, FromRow of the row, with the beat's time and schedule and no result
	Set beats = ..Person("c", {"NextDueAt": (noon)})
	Do $$$AssertStatusOK(..BDue(noon, .items, beats, 0, 1, .views), "RunDue is OK for a due beat")
	Do $$$AssertEquals(..ViewRefs(.views, beats), "1:1", "one view")
	Do $$$AssertEquals(..ViewJson(.views, 1), ..RowJson(beats), "which is FromRow of the reopened row")
	Set beat = ##class(%DynamicObject).%FromJSON(..ViewJson(.views, 1))
	Do $$$AssertEquals(beat.lastBeatAt_"|"_beat.nextDueAt_"|"_beat.%IsDefined("lastOutcome"), noon_"|"_..Plus(noon, 1800)_"|0", "with the beat's time, the schedule and no result")

	// a run now that sends, for a person with no row
	Set sent = ..Person("c")
	Do $$$AssertStatusOK(..BNow(sent, noon, .item, .outcome, .availableAt, 0, 1, .views), "RunNow is OK")
	Do $$$AssertEquals(outcome, "sent", "the beat is sent")
	Do $$$AssertEquals(..ViewRefs(.views, sent), "1:1", "one view")
	Do $$$AssertEquals(..ViewJson(.views, 1), ..RowJson(sent), "which is FromRow of the reopened row")
	Set view = ##class(%DynamicObject).%FromJSON(..ViewJson(.views, 1))
	Do $$$AssertEquals(view.lastRunNowAt_"|"_view.lastBeatAt_"|"_view.nextDueAt, noon_"|"_noon_"|"_..Plus(noon, 1800), "with lastRunNowAt, the beat's time and the schedule")

	// a cooldown with a pending decision: only the recorded result, and lastRunNowAt as it was
	Set pendingItem = ..Open(sent).LastItemId
	Do ..Decision(sent, pendingItem, {"Outcome": "ignore"})
	Set soon = ..Plus(noon, 30)
	Do $$$AssertStatusOK(..BNow(sent, soon, .item, .outcome, .availableAt, 0, 1, .views), "RunNow is OK on the cooldown")
	Do $$$AssertEquals(outcome, "cooldown", "the outcome is cooldown")
	Do $$$AssertEquals(..ViewRefs(.views, sent), "1:1", "and its Settle gave one view")
	Do $$$AssertEquals(..ViewJson(.views, 1), ..RowJson(sent), "which is FromRow of the reopened row")
	Set view = ##class(%DynamicObject).%FromJSON(..ViewJson(.views, 1))
	Do $$$AssertEquals(view.lastOutcome_"|"_view.lastRunNowAt, "ignore|"_noon, "with the recorded result and lastRunNowAt unchanged")

	// a cooldown with nothing pending: no view
	Do $$$AssertStatusOK(..BNow(sent, soon, .item, .outcome, .availableAt, 0, 1, .views), "RunNow is OK on the cooldown again")
	Do $$$AssertEquals(outcome_"|"_+$Get(views), "cooldown|0", "a cooldown with nothing pending gives no view")

	// a run now that records a pending decision first: two views, the result then the new state
	Set later = ..Plus(noon, 600)
	Do $$$AssertStatusOK(..BNow(sent, later, .item, .outcome, .availableAt, 0, 1, .views), "RunNow is OK after the cooldown")
	Do $$$AssertEquals(outcome_"|"_+$Get(views), "sent|1", "with nothing pending the beat gives one view")
	Set pendingItem = ..Open(sent).LastItemId
	Do ..Decision(sent, pendingItem, {"Outcome": "ignore"})
	Set muchLater = ..Plus(noon, 1200)
	Do $$$AssertStatusOK(..BNow(sent, muchLater, .item, .outcome, .availableAt, 0, 1, .views), "RunNow is OK with a pending decision")
	Do $$$AssertEquals(outcome_"|"_..ViewRefs(.views, sent), "sent|2:1,1", "the decision and the beat give two views")
	Set one = ##class(%DynamicObject).%FromJSON(..ViewJson(.views, 1))
	Set two = ##class(%DynamicObject).%FromJSON(..ViewJson(.views, 2))
	Do $$$AssertEquals(one.lastOutcome_"|"_one.lastRunNowAt, "ignore|"_later, "the first holds the recorded result, before the new run now")
	Do $$$AssertEquals(two.%IsDefined("lastOutcome")_"|"_two.lastRunNowAt_"|"_two.lastBeatAt, "0|"_muchLater_"|"_muchLater, "the second holds the new state")
	Do $$$AssertEquals(..ViewJson(.views, 2), ..RowJson(sent), "which is FromRow of the reopened row")

	// a run now that is held: one view with lastRunNowAt and no skip
	Set held = ..Person("")
	Do $$$AssertStatusOK(..BNow(held, noon, .item, .outcome, .availableAt, 0, 1, .views), "RunNow is OK for an empty checklist")
	Do $$$AssertEquals(outcome_"|"_..ViewRefs(.views, held), "empty|1:1", "it is held, with one view")
	Do $$$AssertEquals(..ViewJson(.views, 1), ..RowJson(held), "which is FromRow of the reopened row")
	Set view = ##class(%DynamicObject).%FromJSON(..ViewJson(.views, 1))
	Do $$$AssertEquals(view.lastRunNowAt_"|"_view.%IsDefined("lastSkipAt")_"|"_view.%IsDefined("lastBeatAt"), noon_"|0|0", "with lastRunNowAt, and no skip and no beat")
}

/// Story 39.7 (CI rework; AC 1): a RunDue skip for an empty checklist saves the row (the skip's time, the reason empty and the moved schedule) and gives no view, while
/// a back-off skip of the same RunDue gives one, and a run now held for the same empty checklist still gives one (TestViewsInCommitOrder). A person with an empty
/// checklist and a recorded decision pending still gives the recorded result's view, and no view for the empty skip after it. The times are fixed (2099).
Method TestRunDueEmptySkipGivesNoView()
{
	Set noon = ..Local("12:00")

	// a due person with an empty checklist (no row yet), and one with a back-off: only the back-off is viewed
	Set bare = ..Person("")
	Set backoff = ..Person("c", {"NextDueAt": (noon), "BackoffUntil": (..Plus(noon, 600))})
	Set both = bare_","_backoff
	Do $$$AssertStatusOK(..BDue(noon, .items, both, 0, 1, .views), "RunDue is OK")
	Do $$$AssertEquals(items.Count(), 0, "no beat runs")
	Set row = ..Open(bare)
	Do $$$AssertTrue($IsObject(row), "the person with an empty checklist gets a row")
	If $IsObject(row) Do $$$AssertEquals(row.LastSkipAt_"|"_row.LastSkipReason_"|"_row.NextDueAt, noon_"|empty|"_..Plus(noon, 1800), "which holds the empty skip and the moved schedule")
	Do $$$AssertEquals(..ViewRefs(.views, both), "1:2", "but only the back-off skip gives a view, and the empty one gives none")
	Do $$$AssertEquals(..ViewJson(.views, 1), ..RowJson(backoff), "which is FromRow of the reopened row")

	// the empty person alone: no view at all
	Set alone = ..Person("", {"NextDueAt": (noon)})
	Do $$$AssertStatusOK(..BDue(noon, .items, alone, 0, 1, .views), "RunDue is OK for a row that is due")
	Do $$$AssertEquals(+$Get(views), 0, "an empty skip of a person with a row gives no view")
	Set row = ..Open(alone)
	Do $$$AssertEquals($Select($IsObject(row): row.LastSkipReason, 1: "no row"), "empty", "and the row is saved with the reason")

	// a pending decision is still viewed, the empty skip after it is not
	Set pending = ..Person("", {"NextDueAt": (..Plus(noon, -60)), "LastItemId": "itemempty"})
	Do ..Decision(pending, "itemempty", {"Outcome": "ignore"})
	Do $$$AssertStatusOK(..BDue(noon, .items, pending, 0, 1, .views), "RunDue is OK for a pending decision")
	Do $$$AssertEquals(..ViewRefs(.views, pending), "1:1", "the recorded result gives one view")
	Set recorded = ##class(%DynamicObject).%FromJSON(..ViewJson(.views, 1))
	Do $$$AssertEquals(recorded.lastOutcome_"|"_recorded.%IsDefined("lastSkipAt"), "ignore|0", "which holds the result and no skip")
	Set row = ..Open(pending)
	Do $$$AssertEquals($Select($IsObject(row): row.LastSkipReason, 1: "no row"), "empty", "while the row has the empty skip")
}

/// Story 39.7 (QA; AC 3): a commit that fails gives no view. RunDue and RunNow view only a row that was saved: a person whose recorded decision cannot be saved
/// (a stored LastSnapshotKey one character longer than its MAXLEN), whose row is refused as a duplicate, or whose RunNow cannot settle gets none, while the person after it
/// still gives a view for each of its commits.
Method TestFailedCommitsGiveNoView()
{
	Set noon = ..Local("12:00")

	// RunDue: B's recorded decision cannot be saved (a 65-character LastSnapshotKey, MAXLEN 64, written straight into its node), so it gives no view and stays pending; A's two commits give two
	Set b = ..Person("b", {"NextDueAt": (noon), "LastItemId": "itemb", "LastSnapshotKey": (..BKey("b"))})
	Set a = ..Person("a", {"NextDueAt": (noon), "LastItemId": "itema", "LastSnapshotKey": (..BKey("an earlier text"))})
	Do ..Decision(b, "itemb", {"Outcome": "ignore"})
	Do ..Decision(a, "itema", {"Outcome": "ignore"})
	Set id = ..Open(b).%Id()
	Set $List(^OcuTalonP.HeartbeatBeatD(id), 15) = ..BKey("b")_"0"
	Do $$$AssertStatusNotOK(..BDue(noon, .items, b_","_a, 0, 1, .views), "RunDue answers an error status for B")
	Do $$$AssertEquals(..ViewRefs(.views, b_","_a), "2:2,2", "and gives A's two views and none of B's")
	Do $$$AssertEquals(..ViewJson(.views, 2), ..RowJson(a), "the last is FromRow of A's reopened row")

	// RunNow: the same row cannot be settled, so the answer is an error status, with no outcome, no Item and no view
	Do $$$AssertStatusNotOK(..BNow(b, noon, .item, .outcome, .availableAt, 0, 1, .views), "RunNow answers an error status for B")
	Do $$$AssertEquals(+$Get(views)_"|"_outcome_"|"_$IsObject(item), "0||0", "with no view, no outcome and no Item")

	// RunDue: B's row is refused as a duplicate (its node is gone), so it gives no view, while A beats and gives one
	Set b2 = ..Person("b", {"NextDueAt": (noon)})
	Set a2 = ..Person("a", {"NextDueAt": (noon)})
	Do $$$AssertStatusNotOK(..BDueBroken(b2, "", noon, .items, b2_","_a2, .views), "RunDue answers an error status for the refused row")
	Do $$$AssertEquals(..ViewRefs(.views, b2_","_a2), "1:2", "and gives A's one view and none for the refused row")
	Do $$$AssertEquals(..ViewJson(.views, 1), ..RowJson(a2), "which is FromRow of A's reopened row")
}

/// The HeartbeatBeat row of the session Ref, found by SQL (so that the test does not rely on the unique index), or "".
Method Open(ref As %String) As OcuTalon.Data.HeartbeatBeat
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM OcuTalon_Data.HeartbeatBeat WHERE SessionRef = ? ORDER BY ID", ref)
	If result.%Next() Quit ##class(OcuTalon.Data.HeartbeatBeat).%OpenId(result.%GetData(1))
	Quit ""
}

/// The number of HeartbeatBeat rows of the session Ref, or of all sessions when ref is empty.
Method Rows(ref As %String) As %Integer
{
	If ref = "" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.HeartbeatBeat")
	} Else {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.HeartbeatBeat WHERE SessionRef = ?", ref)
	}
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// --- helpers ---
/// The values object of a test: a checklist, the window and the interval in minutes.
ClassMethod V(checklist As %String, from As %String = "08:00", to As %String = "20:00", interval As %Integer = 30) As %DynamicObject [ Private ]
{
	Quit {"on": 1, "interval": (interval), "from": (from), "to": (to), "checklist": (checklist)}
}

/// The UTC time of the local clock (HH:MM) on the day (a date in 2099).
ClassMethod Local(clock As %String, day As %String = "2099-06-15") As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Time).FromLocal(day_"T"_clock_":00")
}

/// The UTC time that many seconds after at.
ClassMethod Plus(at As %String, seconds As %Integer) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Time).AddSeconds(at, seconds)
}

/// A fixture session; its Ref. With fields (an object of HeartbeatBeat properties) it also gets its HeartbeatBeat row, made before the settings, and with
/// a checklist its checklist setting.
Method Person(checklist As %String = "", fields As %DynamicObject = "") As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzbeat"_$Increment(^OcuTalonTest("ChecksBeat", "n")))
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	If $IsObject(fields) {
		Set row = ##class(OcuTalon.Data.HeartbeatBeat).%New()
		Set row.SessionRef = ref
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Set $Property(row, name) = value
		}
		Do $$$AssertStatusOK(row.%Save(), "the fixture row is saved")
	}
	If checklist '= "" Do ..Put(ref, "checklist", checklist)
	Quit ref
}

/// Sets one property of the person's HeartbeatBeat row and saves it.
Method SetRow(ref As %String, name As %String, value As %String) [ Private ]
{
	Set row = ..Open(ref)
	Set $Property(row, name) = value
	Do $$$AssertStatusOK(row.%Save(), "the row's "_name_" is set")
}

/// Writes the person's setting, and drops this process's cache entry of it.
Method Put(ref As %String, name As %String, value As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set($ClassMethod(..#BEAT, "SettingKey", ref, name), value), "the setting "_name_" is written")
}

/// Saves the person's setting as another process would: the Setting row is saved without Setting.Set, so that this process's cache entry of it stays.
Method Bare(ref As %String, name As %String, value As %String) [ Private ]
{
	Set key = $ClassMethod(..#BEAT, "SettingKey", ref, name)
	Set setting = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	If '$IsObject(setting) {
		Set setting = ##class(OcuTalon.Data.Setting).%New()
		Set setting.Key = key
	}
	Set setting.Value = value
	Set setting.UpdatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(setting.%Save(), "the setting "_name_" is saved")
}

/// The on and interval values this process reads for the person, as on|interval.
Method Shape(ref As %String) As %String [ Private ]
{
	Set values = ..BValues(ref)
	Quit values.on_"|"_values.interval
}

/// A decision of Kind decide for the person's beat item; its Ref (removed with the test).
Method Decision(ref As %String, itemId As %String, fields As %DynamicObject) As %String [ Private ]
{
	Do fields.%Set("ItemId", itemId)
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(ref, "decide", ##class(OcuTalon.Data.Time).NowUtc(), fields)
	Set ..Refs = ..Refs_","_decision
	Quit decision
}

/// BDue while the node of the person's row holds broken ("" removes it); the node is put back after the call, also after a throw.
Method BDueBroken(ref As %String, broken As %String, tickAt As %String, Output items As %ListOfObjects, sessions As %String, Output views) As %Status [ Private ]
{
	Set id = ..Open(ref).%Id()
	Set node = ^OcuTalonP.HeartbeatBeatD(id)
	Kill ^OcuTalonP.HeartbeatBeatD(id)
	If broken '= "" Set ^OcuTalonP.HeartbeatBeatD(id) = broken
	Try {
		Set sc = ..BDue(tickAt, .items, sessions, 0, 1, .views)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Set ^OcuTalonP.HeartbeatBeatD(id) = node
	Quit sc
}

/// Removes the HeartbeatBeat row and the Setting rows of the session, and the cache entries of the settings.
ClassMethod Forget(ref As %String)
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.HeartbeatBeat WHERE SessionRef = ?", ref)
	Set keys = $ListFromString($Parameter(..#BEAT, "KEYS"))
	Set position = 0
	While $ListNext(keys, position, name) {
		Set key = $ClassMethod(..#BEAT, "SettingKey", ref, name)
		Kill ^||OcuTalon.Setting(key)
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
	}
}

/// One case of the skip order: expected is the first reason (or ""), and each flag makes its rule hold alone (the rules, in order).
Method Case(label As %String, expected As %String, empty As %Boolean, hours As %Boolean, backoff As %Boolean, cap As %Boolean, nokey As %Boolean, unchanged As %Boolean, runNow As %Boolean) [ Private ]
{
	Set at = ..Local($Select(hours: "21:00", 1: "12:00"))
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).%New()
	Set row.BackoffUntil = $Select(backoff: ..Plus(at, 60), 1: "")
	Set row.LastQuietKey = $Select(unchanged: "k", 1: "j")
	Set reason = ..BSkip(..V($Select(empty: "  "_$Char(9, 10)_" ", 1: "c")), row, at, runNow, cap, 'nokey, "k")
	Do $$$AssertEquals(reason, expected, label_": '"_expected_"'")
}

Method BValues(ref As %String) As %DynamicObject [ Private ]
{
	Quit $ClassMethod(..#BEAT, "Values", ref)
}

Method BHours(values As %DynamicObject, at As %String) As %Boolean [ Private ]
{
	Quit $ClassMethod(..#BEAT, "InHours", values, at)
}

Method BNext(values As %DynamicObject, at As %String, reason As %String) As %String [ Private ]
{
	Quit $ClassMethod(..#BEAT, "NextDue", values, at, reason)
}

Method BSkip(values As %DynamicObject, row As %RegisteredObject, at As %String, runNow As %Boolean, capped As %Boolean, keyed As %Boolean, key As %String) As %String [ Private ]
{
	Quit $ClassMethod(..#BEAT, "Skip", values, row, at, runNow, capped, keyed, key)
}

Method BKey(snapshot As %String) As %String [ Private ]
{
	Quit $ClassMethod(..#BEAT, "Key", snapshot)
}

Method BSnap(ref As %String, now As %String) As %String [ Private ]
{
	Quit $ClassMethod(..#BEAT, "Snapshot", ref, now)
}

/// The key that Run stores for the person's snapshot at the UTC time: the key of the whole, uncut text.
Method BWholeKey(ref As %String, now As %String) As %String [ Private ]
{
	Do $ClassMethod(..#BEAT, "Snapshot", ref, now, .whole)
	Quit ..BKey(whole)
}

Method BCapped(at As %String) As %Boolean [ Private ]
{
	Quit $ClassMethod(..#BEAT, "Capped", at)
}

Method BKeyed() As %Boolean [ Private ]
{
	Quit $ClassMethod(..#BEAT, "Keyed")
}

/// RunDue for the sessions (comma-separated) with the cap not reached and the key present unless given; the Items in items.
Method BDue(tickAt As %String, Output items As %ListOfObjects, sessions As %String, capped As %String = 0, keyed As %String = 1, Output views) As %Status [ Private ]
{
	Quit $ClassMethod(..#BEAT, "RunDue", tickAt, .items, sessions, capped, keyed, .views)
}

Method BNow(ref As %String, now As %String, Output item As OcuTalon.Msg.Item, Output outcome As %String, Output availableAt As %String, capped As %String = 0, keyed As %String = 1, Output views) As %Status [ Private ]
{
	Quit $ClassMethod(..#BEAT, "RunNow", ref, now, .item, .outcome, .availableAt, capped, keyed, .views)
}

/// The JSON of the nth view of a Beat call.
Method ViewJson(ByRef views, n As %Integer) As %String [ Private ]
{
	Do views(n, "payload").%JSONExportToString(.json)
	Quit json
}

/// The JSON of Heartbeat.FromRow of the person's row as stored now and the person's settings.
Method RowJson(ref As %String) As %String [ Private ]
{
	Do ##class(OcuTalon.Live.Payload.Heartbeat).FromRow(..Open(ref), ..BValues(ref)).%JSONExportToString(.json)
	Quit json
}

/// The refs of a Beat call's views, in order, as "count:ref,ref" with each ref named by its place in the list (refs, comma-separated).
Method ViewRefs(ByRef views, refs As %String) As %String [ Private ]
{
	Set text = ""
	For n = 1:1:+$Get(views) {
		Set text = text_$Select(n = 1: "", 1: ",")_$Select($ListFind($ListFromString(refs), views(n)): $ListFind($ListFromString(refs), views(n)), 1: "?")
	}
	Quit +$Get(views)_":"_text
}

XData Contracts [ MimeType = application/json ]
{
{
 "OcuTalon.Checks.Msg.BeatNow": {
  "super": "Ens.Request",
  "props": {
   "SessionRef": "%String(MAXLEN=22)",
   "RequestedAt": "%String(MAXLEN=20)"
  }
 }
}
}

}
