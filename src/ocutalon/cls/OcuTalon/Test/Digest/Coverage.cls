/// Tests of the coverage list, OcuTalon.Checks.Coverage (Story 17.5; AD-18, AD-28), through Test.Digest.CoverageProbe: the vital signs, the live read of a
/// production and the heartbeat gaps are fed, the CheckRun rows are real. Every time of a history is a fixed time in 2030 (FROM to TO), so the results do
/// not depend on the moment; the clock is used by the live read (the age of a queue) and gives the time of the vital rows (the moment of each Build).
///   - TestEntries: a session with one watch that ran every minute gives the five vital rows and the watch row, all passed, lines that match them, the
///     figures as whole numbers, no source row; with no watch there are five rows; the five-argument call works;
///   - TestFigures and TestVitalFailures: the unrounded readings are compared and the figures rounded; each vital sign fails on its own;
///   - TestCappedDatabase: the four cases of the database-space rule, with the ruled text and key;
///   - TestVitalsUnread: a sign that cannot be read, or a read that throws, is not_checked and never passed;
///   - TestPaused, TestMissed, TestNeverRan, TestStale, TestReasonMap, TestUnreachableStreak: the rules of a check's history in their order;
///   - TestLiveRead: the live read of a production watch, item by item, and the reads that cannot be made;
///   - TestBeatLeavesCoverageAlone: an update of a check's row that leaves its LastRunAt as it was (what a heartbeat beat would be, if it touched the row)
///     writes no CheckRun and leaves Build's rows and lines as they were, the vital rows' time (the clock) left out;
///   - TestGapsSignature: the seam Gaps agrees with Schedule.Heartbeat.Gaps;
///   - TestFixedStrings: the ruled text and the digest line, byte for byte.
Class OcuTalon.Test.Digest.Coverage Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Digest.CoverageProbe";

Parameter FROM = "2030-06-01T11:50:00Z";

Parameter TO = "2030-06-01T12:00:00Z";

/// The Refs of the fixture rows, comma-separated, for the clean-up.
Property Refs As %String(MAXLEN = "");

/// The Refs of the sessions of the fixture checks, comma-separated.
Property Sessions As %String(MAXLEN = "");

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do $ClassMethod(..#PROBE, "Reset")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do $ClassMethod(..#PROBE, "Reset")
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

Method Clean()
{
	For i = 1:1:$Length(..Sessions, ",") {
		Set ref = $Piece(..Sessions, ",", i)
		If ref '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.CheckRun WHERE SessionRef = ?", ref)
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Set ..Sessions = ""
}

/// --- the matrix ---
Method TestEntries()
{
	Set session = ..Session()
	Set ref = ..Watch(session, "Zz.Cov", "Orders")
	Do ..Every(ref, session, "2030-06-01T11:50:30Z", 10, 60)
	Do ..Built(session, .rows, .lines, .vitals)
	Do $$$AssertEquals(rows.%Size(), 6, "the five vital rows and the watch")
	Do $$$AssertEquals(..Entries(rows), "IRIS instance,database space,journal space,license use,system log,Orders production", "the entries, in order")
	Do $$$AssertEquals(..Results(rows), "passed,passed,passed,passed,passed,passed", "all passed")
	Do $$$AssertEquals(lines.%Size(), 6, "one line for each row")
	For i = 0:1:5 {
		Set row = rows.%Get(i)
		Set line = lines.%Get(i)
		Do $$$AssertEquals(line.key, "digest.passed", "line "_i_" is digest.passed")
		Do $$$AssertEquals(line.slots.entry_"|"_line.slots.time, row.entry_"|"_row.checkedAt, "and carries the row's entry and time")
		Do $$$AssertEquals(row.finding, "", "no finding on a passed row")
		Do $$$AssertTrue(row.checkedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "the time is UTC to the second: "_row.checkedAt)
	}
	Do $$$AssertEquals(rows.%Get(5).checkedAt, "2030-06-01T11:59:30Z", "the watch row is at its latest run")
	Do $$$AssertEquals(vitals.rows.%Size(), 5, "vitals holds the five vital rows")
	Do $$$AssertEquals(vitals.rows.%Get(0).entry_"|"_vitals.rows.%Get(4).entry, "IRIS instance|system log", "the first and the last")
	Do $$$AssertEquals(vitals.figures.%ToJSON(), "{""upDays"":3,""databasesFull"":60,""licenseUse"":20}", "the figures are whole numbers")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Namespaces"), "ZZNS", "the vital read was given the watched namespace")
	Set sc = $ClassMethod(..#PROBE, "Build", session, ..#FROM, ..#TO, .five, .fiveLines)
	Do $$$AssertStatusOK(sc, "the five-argument call is OK")
	Do $$$AssertEquals(five.%Size()_"|"_fiveLines.%Size(), "6|6", "and gives the rows and the lines")
	Set none = ..Session()
	Do ..Built(none, .nothing, .nothingLines, .nothingVitals)
	Do $$$AssertEquals(nothing.%Size(), 5, "with nothing watched there are the five vital rows and no source row")
	Do $$$AssertEquals(nothingVitals.rows.%Size(), 5, "and vitals holds them")
}

/// The unrounded readings are compared; only the figures are rounded.
Method TestFigures()
{
	Set session = ..Session()
	Set vitals = ..Reading()
	Set vitals.databases = [(..Database("OCUTALON_DATA", 9.6))]
	Set vitals.license.usePercent = 90.4
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(rows.%Get(1).result_"|"_rows.%Get(1).finding, "failed|OCUTALON_DATA 9% free", "9.6% free is below 10 and failed, whatever it rounds to")
	Do $$$AssertEquals(rows.%Get(3).result_"|"_rows.%Get(3).finding, "failed|91% in use", "90.4% in use is above 90 and failed")
	Do $$$AssertEquals(figures.figures.%ToJSON(), "{""upDays"":3,""databasesFull"":90,""licenseUse"":90}", "the figures are rounded: 90.4 full is 90, 90.4 in use is 90")
	Set vitals.databases = [(..Database("OCUTALON_DATA", 10))]
	Set vitals.license.usePercent = 90
	Set vitals.journal.freePercent = 10
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(..Results(rows), "passed,passed,passed,passed,passed", "exactly at a threshold passes: free 10, in use 90, journal 10")
	Set vitals.databases = [(..Database("OCUTALON_DATA", 9.99))]
	Set vitals.journal.freePercent = 9.99
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(rows.%Get(1).result_"|"_rows.%Get(1).finding, "failed|OCUTALON_DATA 9% free", "9.99% free fails")
	Do $$$AssertEquals(rows.%Get(2).result_"|"_rows.%Get(2).finding, "failed|9% free", "and so does a journal 9.99% free")
	Do $$$AssertEquals(figures.figures.databasesFull, 90, "100 less 9.99 is 90")
	Do $$$AssertEquals(figures.figures.upDays, 3, "up days are whole")
}

/// Each vital sign fails on its own, with its finding, and the others stay passed.
Method TestVitalFailures()
{
	Set session = ..Session()
	Set vitals = ..Reading()
	Set vitals.databases = [(..Database("OCUTALON_DATA", 8)), (..Database("OCUTALON_CODE", 40)), (..Database("OCUORDERS_DATA", 3))]
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(..Results(rows), "passed,failed,passed,passed,passed", "a low database fails only database space")
	Do $$$AssertEquals(rows.%Get(1).finding, "OCUTALON_DATA 8% free, OCUORDERS_DATA 3% free", "the finding names each low database")
	Do $$$AssertEquals(lines.%Get(1).key, "digest.failed", "its line is digest.failed")
	Do $$$AssertEquals(lines.%Get(1).slots.finding, rows.%Get(1).finding, "with the finding")
	Do $$$AssertEquals(figures.figures.databasesFull, 97, "the figure follows the lowest")
	Set vitals = ..Reading()
	Set vitals.journal.freePercent = 8
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(..Results(rows)_"|"_rows.%Get(2).finding, "passed,passed,failed,passed,passed|8% free", "a low journal fails journal space")
	Set vitals = ..Reading()
	Set vitals.license.usePercent = 91
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(..Results(rows)_"|"_rows.%Get(3).finding, "passed,passed,passed,failed,passed|91% in use", "a license above the threshold fails license use")
	Do $$$AssertEquals(figures.figures.licenseUse, 91, "and the figure is 91")
	Set vitals = ..Reading()
	Set vitals.systemLog.count = 2
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(..Results(rows)_"|"_rows.%Get(4).finding, "passed,passed,passed,passed,failed|2 errors", "severe lines fail the system log")
	Set vitals.systemLog.count = 1
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(rows.%Get(4).finding, "1 error", "one severe line is 1 error")
}

/// The database-space rule: failed on a low volume whatever else; not_checked on an unread database; not_checked with the size-limit reason on a
/// database with a maximum; else passed. A capped database is never passed.
Method TestCappedDatabase()
{
	Set session = ..Session()
	Set vitals = ..Reading()
	Set vitals.databases = [(..Database("OCUTALON_DATA", 40)), (..Database("OCUTALON_CODE", 55))]
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(rows.%Get(1).result_"|"_figures.figures.databasesFull, "passed|60", "no maximum, lowest volume 40% free: passed, 60 full")
	Set capped = ..Database("OCUTALON_DATA", 40)
	Set capped.maxBlocks = 6400
	Set vitals.databases = [(capped), (..Database("OCUTALON_CODE", 55))]
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(rows.%Get(1).result_"|"_rows.%Get(1).finding, "not_checked|"_$Parameter(..#PROBE, "REASONSIZELIMIT"), "a database with a maximum: not_checked, with the size-limit reason")
	Do $$$AssertEquals(lines.%Get(1).key, "digest.notCheckedSizeLimit", "its line is the ruled key")
	Do $$$AssertEquals(lines.%Get(1).slots.%ToJSON(), "{""entry"":""database space""}", "which has one slot")
	Do $$$AssertEquals(figures.figures.databasesFull, "", "and databasesFull is empty")
	Do $$$AssertEquals(..Results(rows), "passed,not_checked,passed,passed,passed", "the other signs are unaffected")
	Set capped.volumeFreePercent = 8
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(rows.%Get(1).result_"|"_rows.%Get(1).finding, "failed|OCUTALON_DATA 8% free", "a capped database on a volume 8% free: failed")
	Do $$$AssertEquals(figures.figures.databasesFull, 92, "the figure is 92")
	Set unread = ..Database("OCUORDERS_DATA", 0)
	Set unread.outcome = "error"
	Set unread.volumeFreePercent = ""
	Set unread.maxBlocks = ""
	Set capped.volumeFreePercent = 40
	Set vitals.databases = [(unread), (capped)]
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(rows.%Get(1).result_"|"_rows.%Get(1).finding, "not_checked|"_##class(OcuTalon.Checks.Process).#REASONREAD, "one database unread and another with a maximum: Couldn't be read")
	Do $$$AssertEquals(lines.%Get(1).key, "digest.notCheckedError", "on the error line")
	Set low = ..Database("OCUTALON_CODE", 8)
	Set vitals.databases = [(unread), (low)]
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(rows.%Get(1).result_"|"_rows.%Get(1).finding, "failed|OCUTALON_CODE 8% free", "a database on a volume 8% free fails whether or not another could be read")
	Set vitals.databases = []
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(rows.%Get(1).result, "not_checked", "no database read at all is not_checked, never passed")
}

/// A sign that cannot be read, or a read that throws, is not_checked with the reason of an unread check.
Method TestVitalsUnread()
{
	Set session = ..Session()
	Set reason = ##class(OcuTalon.Checks.Process).#REASONREAD
	For sign = "instance", "journal", "license", "systemLog" {
		Set vitals = ..Reading()
		Do vitals.%Get(sign).%Set("outcome", "error")
		Do ..Feed(vitals)
		Do ..Built(session, .rows, .lines, .figures)
		Set index = $Case(sign, "instance": 0, "journal": 2, "license": 3, : 4)
		Set row = rows.%Get(index)
		Do $$$AssertEquals(row.result_"|"_row.finding_"|"_lines.%Get(index).key, "not_checked|"_reason_"|digest.notCheckedError", sign_": not_checked, "_reason)
		Do $$$AssertEquals(lines.%Get(index).slots.entry, row.entry, sign_": the line names the entry")
		Do $$$AssertEquals($Length(..Results(rows), "passed") - 1, 4, sign_": the other four passed")
	}
	Set vitals = ..Reading()
	Do vitals.instance.%Set("outcome", "error")
	Do vitals.license.%Set("outcome", "error")
	Do ..Feed(vitals)
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(figures.figures.%ToJSON(), "{""upDays"":"""",""databasesFull"":60,""licenseUse"":""""}", "a figure whose sign was not read is empty")
	Do $ClassMethod(..#PROBE, "Break")
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(..Results(rows), "not_checked,not_checked,not_checked,not_checked,not_checked", "a vital read that throws leaves five rows, all not_checked")
	Do $$$AssertEquals(figures.figures.%ToJSON(), "{""upDays"":"""",""databasesFull"":"""",""licenseUse"":""""}", "and no figure")
	Do $ClassMethod(..#PROBE, "Break", 0)
	Do ..Feed({})
	Do ..Built(session, .rows, .lines, .figures)
	Do $$$AssertEquals(rows.%Size(), 5, "a reading with no sign in it still gives the five rows")
	Do $$$AssertEquals(..Results(rows), "not_checked,not_checked,not_checked,not_checked,not_checked", "all not_checked")
}

/// Rule 1: a heartbeat gap in the span is paused, with the gap clamped to the span, whatever the runs say.
Method TestPaused()
{
	Set session = ..Session()
	Set ref = ..Watch(session, "Zz.Paused", "Orders")
	Do ..Every(ref, session, "2030-06-01T11:50:30Z", 10, 60)
	Do $ClassMethod(..#PROBE, "FeedGaps", [{"start": "2030-06-01T11:53:00Z", "end": "2030-06-01T11:58:00Z", "missed": 5}])
	Do ..Built(session, .rows, .lines)
	Set row = rows.%Get(5)
	Set line = lines.%Get(5)
	Do $$$AssertEquals(row.result_"|"_row.finding, "not_checked|Background checks were paused", "paused: not_checked")
	Do $$$AssertEquals(line.key_"|"_line.slots.from_"|"_line.slots.to, "digest.notCheckedPaused|2030-06-01T11:53:00Z|2030-06-01T11:58:00Z", "on the paused line, from and to the gap")
	Do $ClassMethod(..#PROBE, "FeedGaps", [{"start": "2030-06-01T11:30:00Z", "end": "2030-06-01T12:30:00Z", "missed": 60}])
	Do ..Built(session, .rows, .lines)
	Set line = lines.%Get(5)
	Do $$$AssertEquals(line.slots.from_"|"_line.slots.to, ..#FROM_"|"_..#TO, "a gap that spans the span is clamped to it")
	Do $ClassMethod(..#PROBE, "FeedGaps", [{"start": "2030-06-01T11:58:00Z", "end": "", "missed": 0}])
	Do ..Built(session, .rows, .lines)
	Do $$$AssertEquals(lines.%Get(5).slots.from_"|"_lines.%Get(5).slots.to, "2030-06-01T11:58:00Z|"_..#TO, "an open end reads as the end of the span")
	Set none = ..Watch(session, "Zz.PausedNone", "Billing")
	Do $ClassMethod(..#PROBE, "FeedGaps", [{"start": "2030-06-01T11:53:00Z", "end": "2030-06-01T11:58:00Z", "missed": 5}])
	Do ..Built(session, .rows, .lines)
	Do $$$AssertEquals(lines.%Get(6).key, "digest.notCheckedPaused", "a gap pauses a check that never ran too")
}

/// Rule 3: more than 180 seconds between runs, between the span's start and the first run, or between the last run and the end, is missed.
Method TestMissed()
{
	Set session = ..Session()
	Set between = ..Watch(session, "Zz.MissedBetween", "Between")
	Do ..Run(between, session, "2030-06-01T11:51:00Z", "passed")
	Do ..Run(between, session, "2030-06-01T11:55:00Z", "passed")
	Do ..Run(between, session, "2030-06-01T11:59:00Z", "passed")
	Set first = ..Watch(session, "Zz.MissedFirst", "First")
	Do ..Run(first, session, "2030-06-01T11:54:00Z", "passed")
	Do ..Run(first, session, "2030-06-01T11:55:00Z", "passed")
	Do ..Run(first, session, "2030-06-01T11:56:00Z", "passed")
	Do ..Run(first, session, "2030-06-01T11:57:00Z", "passed")
	Do ..Run(first, session, "2030-06-01T11:58:00Z", "passed")
	Do ..Run(first, session, "2030-06-01T11:59:00Z", "passed")
	Set last = ..Watch(session, "Zz.MissedLast", "Last")
	Do ..Every(last, session, "2030-06-01T11:51:00Z", 6, 60)
	Set edge = ..Watch(session, "Zz.MissedEdge", "Edge")
	Do ..Run(edge, session, "2030-06-01T11:53:00Z", "passed")
	Do ..Run(edge, session, "2030-06-01T11:56:00Z", "passed")
	Do ..Run(edge, session, "2030-06-01T11:59:00Z", "passed")
	Do ..Built(session, .rows, .lines)
	Do $$$AssertEquals(rows.%Get(5).result_"|"_rows.%Get(5).finding, "not_checked|The check didn't run", "runs 4 minutes apart: missed")
	Do $$$AssertEquals(lines.%Get(5).key_"|"_lines.%Get(5).slots.from_"|"_lines.%Get(5).slots.to, "digest.notCheckedMissed|2030-06-01T11:51:00Z|2030-06-01T11:55:00Z", "from the first run of the first gap to the second")
	Do $$$AssertEquals(lines.%Get(6).slots.from_"|"_lines.%Get(6).slots.to, "2030-06-01T11:50:00Z|2030-06-01T11:54:00Z", "the span's start to the first run")
	Do $$$AssertEquals(lines.%Get(7).slots.from_"|"_lines.%Get(7).slots.to, "2030-06-01T11:56:00Z|"_..#TO, "the last run to the end of the span")
	Do $$$AssertEquals(rows.%Get(8).result, "passed", "runs exactly 180 seconds apart, from the span's start to the end, are not missed")
	Do $$$AssertEquals(rows.%Get(8).checkedAt, "2030-06-01T11:59:00Z", "and the row is at its latest run")
}

/// Rule 2: no run in the span is missed from the span's start when the check never ran, stale when an earlier run exists. A check created inside the
/// window counts from its creation.
Method TestNeverRan()
{
	Set session = ..Session()
	Set never = ..Watch(session, "Zz.Never", "Never")
	Set created = ..Watch(session, "Zz.NeverCreated", "Created", {"CreatedAt": "2030-06-01T11:55:00Z"})
	Do ..Built(session, .rows, .lines)
	Do $$$AssertEquals(rows.%Get(5).result_"|"_rows.%Get(5).finding_"|"_rows.%Get(5).checkedAt, "not_checked|The check didn't run|"_..#FROM, "a check that never ran: missed")
	Do $$$AssertEquals(lines.%Get(5).key_"|"_lines.%Get(5).slots.from_"|"_lines.%Get(5).slots.to, "digest.notCheckedMissed|"_..#FROM_"|"_..#TO, "from the span's start to its end")
	Do $$$AssertEquals(lines.%Get(6).slots.from_"|"_lines.%Get(6).slots.to, "2030-06-01T11:55:00Z|"_..#TO, "a check created in the window counts from its creation")
}

Method TestStale()
{
	Set session = ..Session()
	Set ref = ..Watch(session, "Zz.Stale", "Orders")
	Do ..Run(ref, session, "2030-06-01T10:00:00Z", "passed")
	Do ..Run(ref, session, "2030-06-01T11:00:00Z", "passed")
	Do ..Built(session, .rows, .lines)
	Do $$$AssertEquals(rows.%Get(5).result_"|"_rows.%Get(5).finding_"|"_rows.%Get(5).checkedAt, "not_checked|Its last check was too long ago|2030-06-01T11:00:00Z", "the last run before the span: stale")
	Do $$$AssertEquals(lines.%Get(5).key_"|"_lines.%Get(5).slots.time, "digest.notCheckedStale|2030-06-01T11:00:00Z", "with that run's time")
}

/// Rule 4: the latest run's reason picks the line; an empty or unknown reason is error.
Method TestReasonMap()
{
	Set session = ..Session()
	Set cases = $ListBuild("error", "timeout", "unreachable", "", "zz")
	Set keys = $ListBuild("digest.notCheckedError", "digest.notCheckedTimeout", "digest.notCheckedUnreachable", "digest.notCheckedError", "digest.notCheckedError")
	For i = 1:1:$ListLength(cases) {
		Set ref = ..Watch(session, "Zz.Reason"_i, "Reason"_i)
		Do ..Every(ref, session, "2030-06-01T11:50:30Z", 9, 60)
		Do ..Run(ref, session, "2030-06-01T11:59:30Z", "not_checked", $List(cases, i), "Couldn't be read")
	}
	Do ..Built(session, .rows, .lines)
	For i = 1:1:$ListLength(cases) {
		Set row = rows.%Get(4 + i)
		Set line = lines.%Get(4 + i)
		Do $$$AssertEquals(row.result_"|"_row.finding_"|"_row.checkedAt, "not_checked|Couldn't be read|2030-06-01T11:59:30Z", "reason '"_$List(cases, i)_"': not_checked with the run's finding and time")
		Do $$$AssertEquals(line.key_"|"_line.slots.time_"|"_line.slots.entry, $List(keys, i)_"|2030-06-01T11:59:30Z|"_row.entry, "reason '"_$List(cases, i)_"' is "_$List(keys, i))
	}
}

/// Rule 4, unreachable: the time is the first run of the unbroken streak of unreachable runs that ends at the latest.
Method TestUnreachableStreak()
{
	Set session = ..Session()
	Set ref = ..Watch(session, "Zz.Streak", "Streak")
	Do ..Slots(ref, session, "pppppupuuu")
	Set timed = ..Watch(session, "Zz.StreakTimeout", "Timed")
	Do ..Slots(timed, session, "pppppppput")
	Do ..Built(session, .rows, .lines)
	Do $$$AssertEquals(lines.%Get(5).key_"|"_lines.%Get(5).slots.time, "digest.notCheckedUnreachable|2030-06-01T11:57:30Z", "since the first run of the trailing streak, not of an earlier one")
	Do $$$AssertEquals(lines.%Get(6).key_"|"_lines.%Get(6).slots.time, "digest.notCheckedTimeout|2030-06-01T11:59:30Z", "a timeout is at the latest run's time")
	Set mixed = ..Watch(session, "Zz.StreakMixed", "Mixed")
	Do ..Slots(mixed, session, "ppppeuuuuu")
	Set gapped = ..Watch(session, "Zz.StreakGap", "Gapped")
	Do ..Run(gapped, session, "2030-06-01T11:50:30Z", "passed")
	Do ..Run(gapped, session, "2030-06-01T11:51:30Z", "passed")
	Do ..Run(gapped, session, "2030-06-01T11:59:30Z", "not_checked", "error", "Couldn't be read")
	Do ..Built(session, .rows, .lines)
	Do $$$AssertEquals(lines.%Get(7).key_"|"_lines.%Get(7).slots.time, "digest.notCheckedUnreachable|2030-06-01T11:55:30Z", "an earlier run that is not unreachable ends the streak")
	Do $$$AssertEquals(lines.%Get(8).key_"|"_lines.%Get(8).slots.from, "digest.notCheckedMissed|2030-06-01T11:51:30Z", "a gap between runs is missed, before the latest run's reason is read")
}

/// A run's failed result is the row's, with its finding at its time.
Method TestFailedRun()
{
	Set session = ..Session()
	Set ref = ..Watch(session, "Zz.FailedRun", "Orders")
	Do ..Every(ref, session, "2030-06-01T11:50:30Z", 9, 60)
	Do ..Run(ref, session, "2030-06-01T11:59:30Z", "failed", "", "Production stopped, 2 new failures")
	Do ..Built(session, .rows, .lines)
	Do $$$AssertEquals(rows.%Get(5).result_"|"_rows.%Get(5).finding_"|"_rows.%Get(5).checkedAt, "failed|Production stopped, 2 new failures|2030-06-01T11:59:30Z", "failed, with the run's finding and time")
	Do $$$AssertEquals(lines.%Get(5).key_"|"_lines.%Get(5).slots.finding, "digest.failed|Production stopped, 2 new failures", "on a digest.failed line")
	Set bare = ..Watch(session, "Zz.FailedBare", "Bare")
	Do ..Every(bare, session, "2030-06-01T11:50:30Z", 9, 60)
	Do ..Run(bare, session, "2030-06-01T11:59:30Z", "failed", "", "")
	Do ..Built(session, .rows, .lines)
	Do $$$AssertEquals(rows.%Get(6).result_"|"_rows.%Get(6).finding, "not_checked|"_##class(OcuTalon.Checks.Process).#REASONREAD, "a failed run with no finding is never passed: it is not_checked")
	Do $$$AssertEquals(lines.%Get(6).key, "digest.notCheckedError", "on the error line")
}

/// A queue-backlog row (Story 23.7; AC8) is an entry of its own, named by its display name: its row and line come from its CheckRun history alone, with no live read, and a
/// not_checked run is never shown as passed.
Method TestQueueRow()
{
	Do $ClassMethod(..#PROBE, "Reset")
	Set session = ..Session()
	Set ref = ..Watch(session, "", "Queue-backlog check", {"Kind": "queues", "Namespace": ""})
	Do ..Every(ref, session, "2030-06-01T11:50:30Z", 9, 60)
	Do ..Run(ref, session, "2030-06-01T11:59:30Z", "failed", "", "1 queue over its threshold")
	Do ..Built(session, .rows, .lines)
	Do $$$AssertEquals(rows.%Get(5).result_"|"_rows.%Get(5).finding_"|"_rows.%Get(5).entry_"|"_rows.%Get(5).checkedAt, "failed|1 queue over its threshold|Queue-backlog check|2030-06-01T11:59:30Z", "a failed queue run: failed, with its finding, the entry Queue-backlog check and its time")
	Do $$$AssertEquals(lines.%Get(5).key_"|"_lines.%Get(5).slots.entry_"|"_lines.%Get(5).slots.finding, "digest.failed|Queue-backlog check|1 queue over its threshold", "on a digest.failed line")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Calls").%Size(), 0, "no live read was made for it")
	Set other = ..Session()
	Set unread = ..Watch(other, "", "Queue-backlog check", {"Kind": "queues", "Namespace": ""})
	Do ..Every(unread, other, "2030-06-01T11:50:30Z", 9, 60)
	Do ..Run(unread, other, "2030-06-01T11:59:30Z", "not_checked", "error", "Couldn't be read")
	Do ..Built(other, .rows, .lines)
	Do $$$AssertEquals(rows.%Get(5).result_"|"_rows.%Get(5).finding_"|"_rows.%Get(5).entry, "not_checked|Couldn't be read|Queue-backlog check", "a not_checked queue run is not_checked, never passed")
	Do $$$AssertEquals(lines.%Get(5).key, "digest.notCheckedError", "on the error line")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Calls").%Size(), 0, "and no live read was made for it either")
}

/// The live read of a production watch, whose history stands on its latest run.
Method TestLiveRead()
{
	Set session = ..Session()
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set other = ..Session()
	Set otherTrace = ##class(OcuTalon.Data.Session).RefIndexOpen(other).TraceRef
	Set ref = ..Watch(session, "Zz.Live", "Orders")
	Do ..Every(ref, session, "2030-06-01T11:50:30Z", 10, 60)
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Built(session, .rows, .lines)
	Do $$$AssertEquals(rows.%Get(5).result, "passed", "control: nothing found, the history stands")
	Do $$$AssertEquals(rows.%Get(5).checkedAt, "2030-06-01T11:59:30Z", "at the latest run")
	Set calls = $ClassMethod(..#PROBE, "Calls")
	Do $$$AssertEquals(calls.%Size(), 1, "one live read")
	Do $$$AssertEquals(calls.%Get(0).namespace_"|"_calls.%Get(0).production_"|"_calls.%Get(0).from_"|"_calls.%Get(0).limit, "ZZNS|Zz.Live|2030-06-01 11:50:00.000|500", "of the production, from the span's start")
	Do ..Live("Zz.Live", {"errored": ["OrdersToWarehouse"]}, session, .row, .line)
	Do $$$AssertEquals(row.result_"|"_row.finding, "failed|1 item in error", "an item in error: failed")
	Do $$$AssertTrue((row.checkedAt '= "2030-06-01T11:59:30Z") && '(before ]] row.checkedAt), "at the read time, not the run's: "_row.checkedAt)
	Do $$$AssertEquals(line.key_"|"_line.slots.finding, "digest.failed|1 item in error", "on a failed line")
	Do ..Live("Zz.Live", {"errored": ["A", "B"]}, session, .row)
	Do $$$AssertEquals(row.finding, "2 items in error", "two items in error")
	Do ..Live("Zz.Live", {"disabled": ["OrdersToWarehouse"]}, session, .row)
	Do $$$AssertEquals(row.result_"|"_row.finding, "failed|1 item disabled", "a disabled item: failed")
	Do ..Live("Zz.Live", {"disabled": ["A", "B", "C"]}, session, .row)
	Do $$$AssertEquals(row.finding, "3 items disabled", "three disabled items")
	Do ..Live("Zz.Live", {"state": "stopped"}, session, .row)
	Do $$$AssertEquals(row.result_"|"_row.finding, "failed|Production stopped", "a stopped production: failed")
	Do ..Live("Zz.Live", {"queues": [{"name": "A", "count": 101, "oldestAt": (..Ago(30))}]}, session, .row)
	Do $$$AssertEquals(row.result_"|"_row.finding, "failed|101 messages queued", "101 messages queued: failed")
	Do ..Live("Zz.Live", {"queues": [{"name": "A", "count": 100, "oldestAt": (..Ago(30))}]}, session, .row)
	Do $$$AssertEquals(row.result, "passed", "100 messages queued: passed")
	Do ..Live("Zz.Live", {"queues": [{"name": "A", "count": 3, "oldestAt": (..Ago(660))}]}, session, .row)
	Do $$$AssertEquals(row.result_"|"_row.finding, "failed|A message waiting 11 minutes", "an oldest message that waited 11 minutes: failed")
	Do ..Live("Zz.Live", {"queues": [{"name": "A", "count": 3, "oldestAt": (..Ago(540))}]}, session, .row)
	Do $$$AssertEquals(row.result, "passed", "one that waited 9 minutes: passed")
	Do ..Live("Zz.Live", {"rows": [{"superSession": (trace)}, {"superSession": (trace)}, {"superSession": (otherTrace)}]}, session, .row)
	Do $$$AssertEquals(row.result_"|"_row.finding, "failed|2 new failures", "the failures of the session are counted, not another session's")
	Do ..Live("Zz.Live", {"rows": [{"superSession": (otherTrace)}]}, session, .row)
	Do $$$AssertEquals(row.result, "passed", "another session's failure alone: passed")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Reader).OnlineDemo(), 0, "control: this is not the online demo")
	Do ..Live("Zz.Live", {"rows": [{"superSession": ""}, {"superSession": "zzNoSuchTrace"}]}, session, .row)
	Do $$$AssertEquals(row.result_"|"_row.finding, "failed|2 new failures", "failures that no session owns are the instance's, and counted off the online demo")
	Do ..Live("Zz.Live", {"state": "suspended"}, session, .row)
	Do $$$AssertEquals(row.result_"|"_row.finding, "failed|Production suspended", "a suspended production: failed")
	Do ..Live("Zz.Live", {"state": "network_stopped"}, session, .row)
	Do $$$AssertEquals(row.result_"|"_row.finding, "failed|Production not running", "a production not running: failed")
	Do ..Live("Zz.Live", {"state": "troubled", "errored": ["A"], "rows": [{"superSession": (trace)}], "queues": [{"name": "A", "count": 200, "oldestAt": (..Ago(900))}]}, session, .row)
	Do $$$AssertEquals(row.finding, "Production troubled, 1 item in error, 1 new failure, 200 messages queued, a message waiting 15 minutes", "the findings are listed together")
	Set many = []
	Set max = ##class(OcuTalon.Watch.Mark).#MAXFAILURES
	For i = 1:1:max {
		Do many.%Push({"superSession": (otherTrace)})
	}
	Do ..Live("Zz.Live", {"rows": (many)}, session, .row, .line)
	Do $$$AssertEquals(row.result_"|"_row.finding_"|"_line.key, "not_checked|"_##class(OcuTalon.Checks.Process).#REASONTOOMANY_"|digest.notCheckedError", "a read cut at its limit with none of its rows the session's: not_checked, never passed")
	Set many = []
	For i = 1:1:max {
		Do many.%Push({"superSession": (trace)})
	}
	Do ..Live("Zz.Live", {"rows": (many)}, session, .row)
	Do $$$AssertEquals(row.result_"|"_row.finding, "failed|At least "_max_" new failures", "a read cut at its limit with the session's failures: at least that many")
	Do ..Live("Zz.Live", {"outcome": "unreadable"}, session, .row, .line)
	Do $$$AssertEquals(row.result_"|"_row.finding_"|"_line.key, "not_checked|No read access to its namespace|digest.notCheckedUnreachable", "unreadable: not_checked, unreachable")
	Do ..Live("Zz.Live", {"outcome": "not_current"}, session, .row, .line)
	Do $$$AssertEquals(row.result_"|"_row.finding_"|"_line.key, "not_checked|No longer its namespace's production|digest.notCheckedUnreachable", "not current: not_checked, unreachable")
	Do ..Live("Zz.Live", {"state": "timeout"}, session, .row, .line)
	Do $$$AssertEquals(row.result_"|"_row.finding_"|"_line.key, "not_checked|No answer in time|digest.notCheckedTimeout", "a read that times out: not_checked, timeout")
	Do ..Live("Zz.Live", {"throw": "boom"}, session, .row, .line)
	Do $$$AssertEquals(row.result_"|"_row.finding_"|"_line.key, "not_checked|Couldn't be read|digest.notCheckedError", "a read that throws: not_checked, error")
	Do ..Live("Zz.Live", {"state": "unknown"}, session, .row, .line)
	Do $$$AssertEquals(row.result_"|"_line.key, "not_checked|digest.notCheckedError", "an unknown state: not_checked, error")
	Do ..Live("Zz.Live", {"queues": "unread"}, session, .row, .line)
	Do $$$AssertEquals(row.result_"|"_row.finding_"|"_line.key, "not_checked|Couldn't be read|digest.notCheckedError", "queues that could not be read are never an empty backlog")
	Do ..Live("Zz.Live", {"errored": "unread"}, session, .row, .line)
	Do $$$AssertEquals(row.result_"|"_line.key, "not_checked|digest.notCheckedError", "nor are items that could not be read")
	Set late = ..Watch(session, "Zz.LiveHistory", "History")
	Do ..Every(late, session, "2030-06-01T11:50:30Z", 9, 60)
	Do ..Run(late, session, "2030-06-01T11:59:30Z", "failed", "", "Production stopped")
	Do $ClassMethod(..#PROBE, "FeedRead", "Zz.LiveHistory", {"queues": []})
	Do ..Built(session, .rows, .lines)
	Do $$$AssertEquals(rows.%Get(6).result_"|"_rows.%Get(6).finding, "failed|Production stopped", "a failed history with nothing found live stays failed")
	Set errored = ..Watch(session, "Zz.LiveSkipped", "Skipped")
	Do ..Every(errored, session, "2030-06-01T11:50:30Z", 9, 60)
	Do ..Run(errored, session, "2030-06-01T11:59:30Z", "not_checked", "error", "Couldn't be read")
	Do $ClassMethod(..#PROBE, "Reset")
	Do ..Built(session, .rows, .lines)
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Calls").%Size(), 2, "a watch whose latest run was not_checked is not read live: two reads for the other two")
}

/// An update that leaves LastRunAt as it was writes no CheckRun and changes nothing in Build: the same time again by SQL and by object, and the due time,
/// the name and the result alone. The result is set to failed, so a run written for one of these updates would change the watch's row. The vital signs
/// carry the time of each Build call, so the two Builds are compared without it (Settled).
Method TestBeatLeavesCoverageAlone()
{
	Set session = ..Session()
	Set ref = ..Watch(session, "Zz.Beat", "Beat", {"LastRunAt": "2030-06-01T11:59:30Z"})
	Do ..Every(ref, session, "2030-06-01T11:50:30Z", 10, 60)
	Do ..Built(session, .rows, .lines)
	Set runs = ##class(OcuTalon.Test.Digest.RecordTrigger).Count(ref)
	Do $$$AssertEquals(runs, 10, "ten runs are recorded")
	Do $$$AssertEquals(..Results(rows), "passed,passed,passed,passed,passed,passed", "and the watch passed")
	Do ..UpdateOne("UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ? WHERE Ref = ?", "2030-06-01T11:59:30Z", ref)
	Do ..UpdateOne("UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ?, NextDueAt = ? WHERE Ref = ?", "2030-06-01T11:59:30Z", "2030-06-01T12:00:30Z", ref)
	Do ..UpdateOne("UPDATE OcuTalon_Data.BackgroundCheck SET Result = ?, Finding = ?, DisplayName = ? WHERE Ref = ?", "failed", "Production stopped", "Beat", ref)
	Set object = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
	Set object.LastRunAt = "2030-06-01T11:59:30Z"
	Set object.NextDueAt = "2030-06-01T12:01:30Z"
	Do $$$AssertStatusOK(object.%Save(), "an object save that sets LastRunAt to the value it has")
	Do $$$AssertEquals(##class(OcuTalon.Test.Digest.RecordTrigger).Count(ref), runs, "none of these updates wrote a CheckRun")
	Do ..Built(session, .after, .afterLines)
	Do $$$AssertEquals(..Settled(after), ..Settled(rows), "and Build's rows are as they were")
	Do $$$AssertEquals(..Settled(afterLines), ..Settled(lines), "and so are its lines")
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref).LastRunAt, "2030-06-01T11:59:30Z", "the check still holds its last run")
}

/// The JSON of Build's rows or lines with the time of the five vital signs left out: those are read at the moment of the call (the clock), so two calls
/// a second apart differ in them alone. The time of the watch's row is its latest run, and stays in.
ClassMethod Settled(items As %DynamicArray) As %String
{
	Set copy = ##class(%DynamicArray).%FromJSON(items.%ToJSON())
	For i = 0:1:4 {
		Set item = copy.%Get(i)
		If item.%IsDefined("checkedAt") Do item.%Remove("checkedAt")
		If $IsObject(item.slots) && item.slots.%IsDefined("time") Do item.slots.%Remove("time")
	}
	Quit copy.%ToJSON()
}

/// Runs one UPDATE of the check with the ref last in args, and asserts that it ran and changed that one row.
Method UpdateOne(sql As %String, args...)
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, sql, args...)
	Do $$$AssertTrue(result.%SQLCODE '< 0, "the update ran: "_sql)
	Do $$$AssertEquals(result.%ROWCOUNT, 1, "and it changed the one row")
}

Method TestGapsSignature()
{
	Set own = ##class(%Dictionary.CompiledMethod).%OpenId("OcuTalon.Checks.Coverage||Gaps")
	Set heartbeat = ##class(%Dictionary.CompiledMethod).%OpenId("OcuTalon.Schedule.Heartbeat||Gaps")
	Do $$$AssertTrue($IsObject(own) && $IsObject(heartbeat), "both methods exist")
	Do $$$AssertEquals(..Names(own.FormalSpec), ..Names(heartbeat.FormalSpec), "the seam takes the arguments of Heartbeat.Gaps, by name and in order")
	Do $$$AssertEquals(..Names(heartbeat.FormalSpec), "fromUtc,toUtc", "which are fromUtc and toUtc")
	Do $$$AssertTrue(heartbeat.ReturnType [ "DynamicArray", "and it returns the array of gaps: "_heartbeat.ReturnType)
}

/// The ruled text and the digest line, byte for byte.
Method TestFixedStrings()
{
	Do $$$AssertEquals($Parameter(..#PROBE, "REASONSIZELIMIT"), "OcuTalon can't read this database's size limit", "the size-limit reason")
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("digest.notCheckedSizeLimit", {"entry": "database space"}, "telegram", "2030-06-01T12:00:00Z", 0, .sc)
	Do $$$AssertStatusOK(sc, "the key renders")
	Do $$$AssertEquals(text, "Not checked: database space (OcuTalon can't read this database's size limit).", "the digest line for database space")
}

/// --- helpers ---
/// A fixture session; its Ref.
Method Session() As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzcoverage")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Quit ref
}

/// A fixture production watch of the session, created before the window unless fields say otherwise; its Ref.
Method Watch(session As %String, production As %String, name As %String, fields As %DynamicObject = "") As %String
{
	Set all = {"CreatedAt": "2030-05-01T10:00:00Z", "DisplayName": (name)}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.key, .value) {
			Do all.%Set(key, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, "ZZNS", production, all)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// One CheckRun of the check, written as it is (not through RecordRun, so that a reason can be anything).
Method Run(ref As %String, session As %String, ranAt As %String, result As %String, reason As %String = "", finding As %String = "")
{
	Set insert = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO OcuTalon_Digest_Data.CheckRun (CheckRef, SessionRef, RanAt, Result, Reason, Finding) VALUES (?, ?, ?, ?, ?, ?)", ref, session, ranAt, result, reason, finding)
	Do $$$AssertTrue(insert.%SQLCODE '< 0, "a run is recorded: "_insert.%Message)
}

/// count passed runs of the check, step seconds apart from the time.
Method Every(ref As %String, session As %String, first As %String, count As %Integer, step As %Integer)
{
	For i = 0:1:count - 1 {
		Do ..Run(ref, session, ##class(OcuTalon.Data.Time).AddSeconds(first, i * step), "passed")
	}
}

/// Ten runs a minute apart from 11:50:30, one for each character of codes: p passed, f failed, u not_checked unreachable, t not_checked timeout, e not_checked error.
Method Slots(ref As %String, session As %String, codes As %String)
{
	For i = 1:1:$Length(codes) {
		Set at = ##class(OcuTalon.Data.Time).AddSeconds("2030-06-01T11:50:30Z", (i - 1) * 60)
		Set code = $Extract(codes, i)
		If code = "p" Do ..Run(ref, session, at, "passed")
		If code = "f" Do ..Run(ref, session, at, "failed", "", "Production stopped")
		If code = "u" Do ..Run(ref, session, at, "not_checked", "unreachable", "No read access to its namespace")
		If code = "t" Do ..Run(ref, session, at, "not_checked", "timeout", "No answer in time")
		If code = "e" Do ..Run(ref, session, at, "not_checked", "error", "Couldn't be read")
	}
}

/// Build over the window of the probe, asserted OK.
Method Built(session As %String, Output rows As %DynamicArray, Output lines As %DynamicArray, Output vitals As %DynamicObject)
{
	Set sc = $ClassMethod(..#PROBE, "Build", session, ..#FROM, ..#TO, .rows, .lines, .vitals)
	Do $$$AssertStatusOK(sc, "Build is OK")
}

/// Feeds the live read of the production, builds, and gives the row and the line of the session's first watch (the first row after the vital signs).
Method Live(production As %String, spec As %DynamicObject, session As %String, Output row As %DynamicObject, Output line As %DynamicObject)
{
	Do $ClassMethod(..#PROBE, "FeedRead", production, spec)
	Do ..Built(session, .rows, .lines)
	Set row = rows.%Get(5)
	Set line = lines.%Get(5)
}

/// Healthy readings of the signs, as a fresh object.
Method Reading() As %DynamicObject
{
	Quit $ClassMethod(..#PROBE, "Healthy")
}

/// Feeds the readings of the signs.
Method Feed(vitals As %DynamicObject)
{
	Do $ClassMethod(..#PROBE, "Feed", vitals)
}

/// One database reading with that free share of its volume and no maximum.
Method Database(name As %String, free As %Numeric) As %DynamicObject
{
	Quit {"name": (name), "directory": ("/zz/"_$ZConvert(name, "L")_"/"), "volumeFreePercent": (free), "maxBlocks": 0, "outcome": "read"}
}

/// The UTC time that many seconds before now.
Method Ago(seconds As %Integer) As %String
{
	Quit ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -seconds)
}

ClassMethod Entries(rows As %DynamicArray) As %String
{
	Set text = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set text = text_$Select(text = "": "", 1: ",")_row.entry
	}
	Quit text
}

/// The results of the first five rows (the vital signs) when the rows are the five of vitals, else of all rows, comma-separated.
ClassMethod Results(rows As %DynamicArray) As %String
{
	Set text = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set text = text_$Select(text = "": "", 1: ",")_row.result
	}
	Quit text
}

/// The argument names of a formal specification, comma-separated.
ClassMethod Names(spec As %String) As %String
{
	Set names = ""
	For i = 1:1:$Length(spec, ",") {
		Set names = names_$Select(names = "": "", 1: ",")_$Piece($Piece(spec, ",", i), ":", 1)
	}
	Quit names
}

}
