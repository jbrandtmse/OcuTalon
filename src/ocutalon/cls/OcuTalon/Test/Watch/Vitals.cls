/// Tests of the vital-sign reads of OcuTalon.Watch.Reader (Story 17.5; AD-3, AD-18) and of the item and queue reads of Failures. THEY RUN IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case: they read the real instance, make a database with a maximum size
/// in a temporary folder and remove it, write a severe line to messages.log, and put a status into the host monitor and queued headers into OCUORDERS
/// (each put back or deleted, also after a failure). A test that needs a healthy Orders first sets aside the Error status of every item (a business
/// process keeps it after a failed message until its job restarts), and puts it back after.
///   - TestFiveSigns: the five signs are read; the databases are OcuTalon's four and the two of Orders, each once, each read without a maximum and with a
///     volume share between 0 and 100; only counts and percentages leave the reader;
///   - TestCappedDatabase: a database created with a 50 MB maximum reads a maxBlocks above 0 (the one routine that gives it without a privilege), and one
///     with none reads 0; a directory that is not a database is the outcome error;
///   - TestSystemLog: a severe line written now is counted in a window around now and in no other, also in a process whose zone is not UTC;
///   - TestSwitchedLog: when IRIS has switched the log, the severe lines of the window that were written before the switch (in the files it kept as
///     messages.old_*) are counted, the read goes back only as far as the first file that starts before the window, and the lines outside the window
///     are not counted;
///   - TestUnreadableSwitchedLog: a kept file that cannot be read makes the sign an error;
///   - TestStartNoise: IRIS's own two start-up lines at severity 2 (the Sharding error, and the failover line of a start in a new container) are not
///     counted, for one start and for two (Story 17.13, DW-980);
///   - TestLaterRealError: a real later error of severity 2 or 3, near misses of the two lines and the Sharding text at severity 3 are still counted;
///   - TestNoiseIdBounds: the container id of the failover line is 12 to 64 lower-case hex digits and nothing else; the Sharding text is matched whole (a word
///     after it or another label counts); the failover line counts at severity 3;
///   - TestNoiseTextBounds: the whole text after the severity is matched: both lines under another category, or after a space or a word, are counted;
///   - TestStartNoiseRow: Checks.Coverage Build over the real reader and the kept files: the "system log" row passes over start-up noise alone, and
///     fails with its count and the check time over a real later error;
///   - TestRealStartNoise: the real messages.log of the stack holds the lines of its own last start, and they are not counted;
///   - TestErroredItems and TestQueues: Failures names an item whose host status is Error and gives each item's queue with its count and its oldest message;
///   - TestBuildOnRealSeams: Checks.Coverage Build over the real readers (Vitals, Failures, Heartbeat Gaps): the five vital rows are read, and an item in
///     error makes the production watch's row failed;
///   - TestNoSwitch: Vitals leaves the namespace as it was, and no reader method of the vital signs switches one.
Class OcuTalon.Test.Watch.Vitals Extends OcuTalon.Test.Watch.Case
{

/// The id of each header that a test made in OCUORDERS, comma-separated, for the clean-up.
Property Headers As %String(MAXLEN = "");

/// The folder of the test's database, "" when none.
Property Folder As %String(MAXLEN = "");

/// The Refs of the fixture session and check of TestBuildOnRealSeams, comma-separated, for the clean-up.
Property Fixtures As %String(MAXLEN = "");

/// The process's time zone before the test, as $SYSTEM.Process.TimeZone gives it.
Property Zone As %String;

/// IRIS's start-up line at severity 2 of the Sharding error, the whole text after the severity (builds 154 and 109), as the tests write it.
Parameter SHARDINGTEXT = "[Utility.Event] Error: ERROR #5002: ObjectScript error: <METHOD DOES NOT EXIST>Sharding+2^STU *Sharding,SYS.ICM";

/// The start of IRIS's failover line at severity 2, with its closing space, as the tests write it; the container id follows.
Parameter FAILOVERTEXT = "[Utility.Event] System appears to have failed over from node ";

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Zone = $SYSTEM.Process.TimeZone()
	Do ..DropSwitchedLogs()
	Quit ##super(testname)
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do $SYSTEM.Process.TimeZone($Select(..Zone = -1: "", 1: ..Zone))
	Do ..DropBuildFixtures()
	Do ..DropHeaders()
	Do ..DropDatabase()
	Do ..DropSwitchedLogs()
	Do ..PutMonitor("restore")
	Do ..RestoreMonitor()
	Quit ##super(testname)
}

Method OnAfterAllTests() As %Status
{
	Do ..DropBuildFixtures()
	Do ..DropHeaders()
	Do ..DropDatabase()
	Do ..DropSwitchedLogs()
	Do ..PutMonitor("restore")
	Do ..RestoreMonitor()
	Quit ##super()
}

Method TestFiveSigns()
{
	If '..Ready() Quit
	Set from = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -86400)
	Set vitals = ##class(OcuTalon.Watch.Reader).Vitals($ListBuild(..#ORDERS), from, ##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(vitals.instance.outcome, "read", "the instance is read")
	Do $$$AssertTrue(vitals.instance.upSeconds '< 0, "with its uptime in seconds: "_vitals.instance.upSeconds)
	Do $$$AssertEquals(vitals.instance.upSeconds, vitals.instance.upSeconds \ 1, "a whole number")
	Set names = ""
	Set iterator = vitals.databases.%GetIterator()
	While iterator.%GetNext(, .database) {
		Set names = names_$Select(names = "": "", 1: ",")_database.name
		Do $$$AssertEquals(database.outcome, "read", database.name_" is read")
		Do $$$AssertEquals(database.maxBlocks, 0, database.name_" has no maximum size")
		Do $$$AssertTrue((database.volumeFreePercent '< 0) && (database.volumeFreePercent '> 100), database.name_" has a volume share between 0 and 100: "_database.volumeFreePercent)
		Do $$$AssertTrue($Extract(database.directory, *) = "/", database.name_" has its closing separator")
	}
	Do $$$AssertEquals(names, "OCUTALON_CODE,OCUTALON_DATA,OCUTALON_PRIVATE,OCUTALON_PUBLIC,OCUORDERS_CODE,OCUORDERS_DATA", "OcuTalon's four databases and Orders' two, each once")
	Do $$$AssertEquals(vitals.journal.outcome, "read", "the journal is read")
	Do $$$AssertTrue((vitals.journal.freePercent > 0) && (vitals.journal.freePercent '> 100), "with its volume's free share: "_vitals.journal.freePercent)
	Do $$$AssertEquals(vitals.license.outcome, "read", "the license is read")
	Do $$$AssertTrue((vitals.license.units > 0) && (vitals.license.consumed '< 0), "with units and consumed units: "_vitals.license.units_", "_vitals.license.consumed)
	Do $$$AssertEquals(vitals.license.usePercent, vitals.license.consumed * 100 / vitals.license.units, "and the unrounded use")
	Do $$$AssertEquals(vitals.systemLog.outcome, "read", "the system log is read")
	Do $$$AssertTrue((vitals.systemLog.count '< 0) && (vitals.systemLog.count = (vitals.systemLog.count \ 1)), "with a count: "_vitals.systemLog.count)
	Do $$$AssertEquals(..Names(vitals.systemLog), "count,outcome", "and nothing else of the log")
	Set again = ##class(OcuTalon.Watch.Reader).Vitals("", "", "")
	Do $$$AssertEquals(again.databases.%Size(), 4, "with no namespace given the databases are OcuTalon's four")
	Set missing = ##class(OcuTalon.Watch.Reader).Vitals($ListBuild("ZZNONE"), "", "")
	Do $$$AssertEquals(missing.databases.%Size(), 5, "a namespace that does not exist adds one entry")
	Do $$$AssertEquals(missing.databases.%Get(4).name_"|"_missing.databases.%Get(4).outcome, "ZZNONE|error", "which is named for it and unread")
}

Method TestCappedDatabase()
{
	If '..Ready() Quit
	Set folder = ..MakeDatabase(50)
	If folder = "" Quit
	Set capped = ##class(OcuTalon.Watch.Reader).Database(folder)
	Do $$$AssertEquals(capped.outcome, "read", "a database with a 50 MB maximum is read")
	Do $$$AssertTrue(capped.maxBlocks > 0, "its maximum is above 0 blocks: "_capped.maxBlocks)
	Do $$$AssertEquals(capped.maxBlocks * 8192, 50 * 1048576, "and is 50 MB at 8192 bytes a block")
	Do $$$AssertEquals(capped.name, "ZZVITALS17", "the name is the last folder, in upper case")
	Do $$$AssertTrue((capped.volumeFreePercent > 0) && (capped.volumeFreePercent '> 100), "with its volume's free share: "_capped.volumeFreePercent)
	Set home = ##class(OcuTalon.Watch.Reader).Database($Piece(##class(%SYS.Namespace).GetGlobalDest("OCUTALON", "^OcuTalonP.Zz"), "^", 2))
	Do $$$AssertEquals(home.maxBlocks, 0, "OcuTalon's private database has no maximum")
	Set bad = ##class(OcuTalon.Watch.Reader).Database(##class(%File).NormalizeDirectory(folder_"nothere"))
	Do $$$AssertEquals(bad.outcome_"|"_bad.volumeFreePercent_"|"_bad.maxBlocks, "error||", "a directory that is not a database is unread, with no number")
	Set empty = ##class(OcuTalon.Watch.Reader).Database("")
	Do $$$AssertEquals(empty.outcome, "error", "and so is an empty one")
}

/// A severe line written now is in a window around now, and in no window that excludes now. The same in a process whose zone is not UTC.
Method TestSystemLog()
{
	If '..Ready() Quit
	Set zone = $SYSTEM.Process.TimeZone()
	For test = "default", "America/New_York", "Asia/Kolkata" {
		If test '= "default" Do $SYSTEM.Process.TimeZone(test)
		Set before = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -5)
		Set pastBefore = ##class(OcuTalon.Watch.Reader).Vitals("", "", ##class(OcuTalon.Data.Time).AddSeconds(before, -3 * 86400)).systemLog.count
		Do ##class(%SYS.System).WriteToConsoleLog("zz OcuTalon vitals test, ignore ("_test_")", 0, 2)
		Hang 1
		Set after = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 5)
		Set inside = ##class(OcuTalon.Watch.Reader).Vitals("", before, after).systemLog.count
		Do $$$AssertTrue(inside '< 1, test_": the severe line is counted in a window around now ("_inside_")")
		Set future = ##class(OcuTalon.Watch.Reader).Vitals("", ##class(OcuTalon.Data.Time).AddSeconds(after, 3 * 86400), "").systemLog.count
		Do $$$AssertEquals(future, 0, test_": none is counted in a window three days ahead (a line of another test's zone lies at most a day away)")
		Set past = ##class(OcuTalon.Watch.Reader).Vitals("", "", ##class(OcuTalon.Data.Time).AddSeconds(before, -3 * 86400)).systemLog.count
		Do $$$AssertEquals(past, pastBefore, test_": a window that ended three days ago does not include it")
	}
	Do $SYSTEM.Process.TimeZone(zone)
}

/// Task 0 of Story 17.5: the zone of the times of messages.log. A line is stamped in the zone of the process that writes it (here New York and Kolkata
/// against an instance in UTC), so the reader, which reads the stamps in its own process's zone (Data.Time.FromLocal), agrees with every writer that
/// shares the instance zone.
Method TestLogStampZone()
{
	If '..Ready() Quit
	Set zone = $SYSTEM.Process.TimeZone()
	For test = "America/New_York", "Asia/Kolkata" {
		Do $SYSTEM.Process.TimeZone(test)
		Set marker = "zz vitals zone "_##class(OcuTalon.Bridge.Ids).NewRef()
		Set local = $Extract($ZDateTime($Horolog, 3, 1), 12, 16)
		Do ##class(%SYS.System).WriteToConsoleLog(marker, 0, 2)
		Set stamp = ..StampOf(marker)
		Set after = $Extract($ZDateTime($Horolog, 3, 1), 12, 16)
		Do $SYSTEM.Process.TimeZone($Select(zone = -1: "", 1: zone))
		Set utc = $Extract(##class(OcuTalon.Data.Time).NowUtc(), 12, 16)
		Do $$$AssertTrue(stamp '= "", test_": the line is found in messages.log")
		Do $$$AssertTrue(($Extract(stamp, 1, 5) '< local) && ($Extract(stamp, 1, 5) '> after), test_": its stamp "_stamp_" is the process's local time ("_local_" to "_after_"), not UTC ("_utc_")")
	}
}

/// The time hh:mm:ss of the newest line of messages.log that holds the text, or "".
ClassMethod StampOf(marker As %String) As %String
{
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(##class(%File).NormalizeFilename($SYSTEM.Util.ManagerDirectory()_"messages.log"))
	Set stamp = ""
	While 'stream.AtEnd {
		Set line = stream.ReadLine(4000)
		If line [ marker Set stamp = $Extract(line, 10, 17)
	}
	Quit stamp
}

/// IRIS keeps the log it switched as messages.old_*. Three files are written, oldest first, at times before b, two days before the current file starts
/// (c): a line that another test wrote in a zone behind UTC is stamped at most a day before its time, so the current file holds nothing before b, and
/// the windows below, which end a minute before b, count the kept files' lines only (the kept files of the instance, older than these, are never
/// read). The newest kept file starts inside the window (read on), the next one starts before it (read, then the read stops), and the oldest holds a
/// severe line that would be inside the window (never read). A window from before b up to now counts the current file's severe lines as well.
Method TestSwitchedLog()
{
	If '..Ready() Quit
	Set c = ..FirstTimeOfCurrent()
	Do $$$AssertTrue(c '= "", "the current messages.log has a timed line: "_c)
	If c = "" Quit
	Set b = ##class(OcuTalon.Data.Time).AddSeconds(c, -2 * 86400)
	Set from = ##class(OcuTalon.Data.Time).AddSeconds(b, -3600)
	Set to = ##class(OcuTalon.Data.Time).AddSeconds(b, -60)
	Do ..WriteKept("3", b, $ListBuild($ListBuild(-9000, 0), $ListBuild(-1800, 2)))
	Hang 1.1
	Do ..WriteKept("2", b, $ListBuild($ListBuild(-7200, 0), $ListBuild(-6600, 2), $ListBuild(-3300, 3)))
	Hang 1.1
	Do ..WriteKept("1", b, $ListBuild($ListBuild(-3000, 0), $ListBuild(-2400, 2), $ListBuild(-1200, 2), $ListBuild(-30, 2)))
	Set vitals = ##class(OcuTalon.Watch.Reader).Vitals("", from, to)
	Do $$$AssertEquals(vitals.systemLog.outcome, "read", "the log is read")
	Do $$$AssertEquals(vitals.systemLog.count, 3, "the two lines of the newest kept file and the one of the next that lie in the window, no more")
	Set inner = ##class(OcuTalon.Watch.Reader).Vitals("", ##class(OcuTalon.Data.Time).AddSeconds(b, -7000), to)
	Do $$$AssertEquals(inner.systemLog.count, 4, "a window that starts inside the second kept file counts its lines from that time on: the two of the first and the two of the second")
	Set edge = ##class(OcuTalon.Watch.Reader).Vitals("", ##class(OcuTalon.Data.Time).AddSeconds(b, -7200), to)
	Do $$$AssertEquals(edge.systemLog.count, 5, "a file whose first line is at the start of the window does not end the read: the older file is read too")
	Do ##class(%SYS.System).WriteToConsoleLog("zz OcuTalon vitals test, ignore (switched)", 0, 2)
	Hang 1
	Set across = ##class(OcuTalon.Watch.Reader).Vitals("", from, ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 5))
	Do $$$AssertTrue(across.systemLog.count > 4, "a window across the switch counts the four lines of the kept files from its start and the current file's severe line too, the current file first: "_across.systemLog.count)
}

/// IRIS's own start-up lines are not counted: the five lines of one start in a new container (the failover line and the Sharding error at severity 2)
/// give 0, and so do two such starts 600 s apart. The window is that of TestSwitchedLog: only the kept file contributes.
Method TestStartNoise()
{
	If '..Ready() Quit
	Set c = ..FirstTimeOfCurrent()
	Do $$$AssertTrue(c '= "", "the current messages.log has a timed line: "_c)
	If c = "" Quit
	Set b = ##class(OcuTalon.Data.Time).AddSeconds(c, -2 * 86400)
	Set from = ##class(OcuTalon.Data.Time).AddSeconds(b, -3600)
	Set to = ##class(OcuTalon.Data.Time).AddSeconds(b, -60)
	Do ..WriteKept("5", b, ..Lead()_..NoiseLines(-3000))
	Set one = ##class(OcuTalon.Watch.Reader).Vitals("", from, to)
	Do $$$AssertEquals(one.systemLog.outcome, "read", "the log is read")
	Do $$$AssertEquals(one.systemLog.count, 0, "the failover line and the Sharding line of one start are not counted")
	Do ..DropSwitchedLogs()
	Do ..WriteKept("5", b, ..Lead()_..NoiseLines(-3000)_..NoiseLines(-2400, "5f4e3d2c1b0a"))
	Set two = ##class(OcuTalon.Watch.Reader).Vitals("", from, to)
	Do $$$AssertEquals(two.systemLog.outcome_"|"_two.systemLog.count, "read|0", "nor are those of two starts 600 s apart")
}

/// A real error after a start still counts, with the lines that only look like the start-up lines: a failover line that names a longer id change
/// ("from node X to Y") or a host name that is not hex, and the Sharding text at severity 3. The five lines of the noise are not counted, the five others are.
Method TestLaterRealError()
{
	If '..Ready() Quit
	Set c = ..FirstTimeOfCurrent()
	Do $$$AssertTrue(c '= "", "the current messages.log has a timed line: "_c)
	If c = "" Quit
	Set b = ##class(OcuTalon.Data.Time).AddSeconds(c, -2 * 86400)
	Set from = ##class(OcuTalon.Data.Time).AddSeconds(b, -3600)
	Set to = ##class(OcuTalon.Data.Time).AddSeconds(b, -60)
	Do ..WriteKept("6", b, ..Lead()_..NoiseLines(-3000)_..LaterLines())
	Set vitals = ##class(OcuTalon.Watch.Reader).Vitals("", from, to)
	Do $$$AssertEquals(vitals.systemLog.outcome, "read", "the log is read")
	Do $$$AssertEquals(vitals.systemLog.count, 5, "the later error, the severity 3 line, the two near-miss failover lines and the Sharding text at severity 3 are counted; the noise is not")
}

/// The container id of the failover line is 12 to 64 lower-case hex digits and nothing after them; the Sharding text is matched whole (a word after
/// it or another label counts); the failover line with a valid id counts at severity 3.
Method TestNoiseIdBounds()
{
	If '..Ready() Quit
	Set c = ..FirstTimeOfCurrent()
	Do $$$AssertTrue(c '= "", "the current messages.log has a timed line: "_c)
	If c = "" Quit
	Set b = ##class(OcuTalon.Data.Time).AddSeconds(c, -2 * 86400)
	Set from = ##class(OcuTalon.Data.Time).AddSeconds(b, -3600)
	Set to = ##class(OcuTalon.Data.Time).AddSeconds(b, -60)
	Set h16 = "0123456789abcdef"
	Set ignored = $ListBuild($ListBuild(-3000, 2, ..#FAILOVERTEXT_h16_h16_h16_h16), $ListBuild(-2900, 2, ..#FAILOVERTEXT_"0a1b2c3d4e5f"))
	Do ..WriteKept("7", b, ..Lead()_ignored)
	Set vitals = ##class(OcuTalon.Watch.Reader).Vitals("", from, to)
	Do $$$AssertEquals(vitals.systemLog.outcome_"|"_vitals.systemLog.count, "read|0", "an id of 64 and one of 12 hex digits are not counted")
	Set counted = $ListBuild($ListBuild(-2800, 2, ..#FAILOVERTEXT_"0a1b2c3d4e5"), $ListBuild(-2700, 2, ..#FAILOVERTEXT_h16_h16_h16_h16_"a"), $ListBuild(-2600, 2, ..#FAILOVERTEXT_"0A1B2C3D4E5F"), $ListBuild(-2500, 2, ..#FAILOVERTEXT_"0a1b2c3d4e5f x"), $ListBuild(-2400, 2, ..#FAILOVERTEXT_"0a1b2c3d4e5f "), $ListBuild(-2300, 2, ..#SHARDINGTEXT_" again"), $ListBuild(-2200, 2, "[Utility.Event] Error: ERROR #5002: ObjectScript error: <METHOD DOES NOT EXIST>Sharding+3^STU *Sharding,SYS.ICM"), $ListBuild(-2100, 3, ..#FAILOVERTEXT_"0a1b2c3d4e5f"))
	Do ..DropSwitchedLogs()
	Do ..WriteKept("7", b, ..Lead()_ignored_counted)
	Set vitals = ##class(OcuTalon.Watch.Reader).Vitals("", from, to)
	Do $$$AssertEquals(vitals.systemLog.outcome_"|"_vitals.systemLog.count, "read|8", "an id of 11 or 65 digits, one in upper case, one with text or a space after it, two near-miss Sharding lines and a failover line at severity 3 are counted")
}

/// The whole text after the severity is matched, nothing before it either: both start-up lines under another category, with a space or a word before
/// them, are counted (the lines at severity 2 are otherwise exactly the start-up lines).
Method TestNoiseTextBounds()
{
	If '..Ready() Quit
	Set c = ..FirstTimeOfCurrent()
	Do $$$AssertTrue(c '= "", "the current messages.log has a timed line: "_c)
	If c = "" Quit
	Set b = ##class(OcuTalon.Data.Time).AddSeconds(c, -2 * 86400)
	Set from = ##class(OcuTalon.Data.Time).AddSeconds(b, -3600)
	Set to = ##class(OcuTalon.Data.Time).AddSeconds(b, -60)
	Set id = "0a1b2c3d4e5f"
	Set ignored = $ListBuild($ListBuild(-3000, 2, ..#FAILOVERTEXT_id), $ListBuild(-2900, 2, ..#SHARDINGTEXT))
	Do ..WriteKept("9", b, ..Lead()_ignored)
	Set vitals = ##class(OcuTalon.Watch.Reader).Vitals("", from, to)
	Do $$$AssertEquals(vitals.systemLog.outcome_"|"_vitals.systemLog.count, "read|0", "the two lines as they are, at severity 2, are not counted")
	Set counted = $ListBuild($ListBuild(-2800, 2, $Replace(..#FAILOVERTEXT, "[Utility.Event]", "[Generic.Event]")_id), $ListBuild(-2700, 2, $Replace(..#SHARDINGTEXT, "[Utility.Event]", "[Generic.Event]")), $ListBuild(-2600, 2, " "_..#SHARDINGTEXT), $ListBuild(-2500, 2, "zz "_..#FAILOVERTEXT_id))
	Do ..DropSwitchedLogs()
	Do ..WriteKept("9", b, ..Lead()_ignored_counted)
	Set vitals = ##class(OcuTalon.Watch.Reader).Vitals("", from, to)
	Do $$$AssertEquals(vitals.systemLog.outcome_"|"_vitals.systemLog.count, "read|4", "both lines under another category, the Sharding line after a space and the failover line after a word are counted")
}

/// The "system log" row of the coverage, over the real reader and the kept files of the window: it passes over start-up noise alone, and over a real
/// later error it fails with its count and the time of the check, as the row and as the digest line.
Method TestStartNoiseRow()
{
	If '..Ready() Quit
	Set c = ..FirstTimeOfCurrent()
	Do $$$AssertTrue(c '= "", "the current messages.log has a timed line: "_c)
	If c = "" Quit
	Set b = ##class(OcuTalon.Data.Time).AddSeconds(c, -2 * 86400)
	Set from = ##class(OcuTalon.Data.Time).AddSeconds(b, -3600)
	Set to = ##class(OcuTalon.Data.Time).AddSeconds(b, -60)
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzvitalsnoise")
	Set ..Fixtures = session
	Do ..WriteKept("8", b, ..Lead()_..NoiseLines(-3000)_..NoiseLines(-2400))
	Set sc = ##class(OcuTalon.Checks.Coverage).Build(session, from, to, .rows, .lines, .vitals)
	Do $$$AssertStatusOK(sc, "Build is OK over start-up noise")
	Do $$$AssertEquals(rows.%Get(4).entry_"|"_rows.%Get(4).result_"|"_rows.%Get(4).finding, "system log|passed|", "the system log row passes over start-up noise alone, with no finding")
	Do $$$AssertEquals(lines.%Get(4).key, "digest.passed", "and so does its line")
	Do ..DropSwitchedLogs()
	Do ..WriteKept("8", b, ..Lead()_..NoiseLines(-3000)_..LaterLines())
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Set sc = ##class(OcuTalon.Checks.Coverage).Build(session, from, to, .rows, .lines, .vitals)
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(sc, "Build is OK over a real later error")
	Set row = rows.%Get(4)
	Do $$$AssertEquals(row.entry_"|"_row.result_"|"_row.finding, "system log|failed|5 errors", "the system log row fails with its count")
	Do $$$AssertTrue('(before ] row.checkedAt) && '(row.checkedAt ] after), "with the time of the check: "_row.checkedAt)
	Set line = lines.%Get(4)
	Do $$$AssertEquals(line.key, "digest.failed", "its line is a failed line")
	Do $$$AssertEquals(line.slots.finding, "5 errors", "with the finding of the row")
	Do $$$AssertEquals(line.slots.time, row.checkedAt, "and the time of the row")
}

/// The real messages.log of this stack holds the lines of its own last start. The window from the last "Instance 'IRIS' starting on node" line to a
/// second after the Sharding line that follows it holds no counted line.
Method TestRealStartNoise()
{
	If '..Ready() Quit
	Do ..LastStart(.started, .sharding)
	Do $$$AssertTrue(started '= "", "the start line of the last start is found: "_started)
	Do $$$AssertTrue(sharding '= "", "and the Sharding line that follows it: "_sharding)
	If (started = "") || (sharding = "") Quit
	Set vitals = ##class(OcuTalon.Watch.Reader).Vitals("", started, ##class(OcuTalon.Data.Time).AddSeconds(sharding, 1))
	Do $$$AssertEquals(vitals.systemLog.outcome_"|"_vitals.systemLog.count, "read|0", "the start's own lines are not counted")
}

/// The UTC times of the last "Instance 'IRIS' starting on node" line of the current messages.log (started) and of the first Sharding line after it
/// (sharding, "" when none). It is a class method, so that its stream is closed before the reader opens the same file.
ClassMethod LastStart(Output started As %String, Output sharding As %String)
{
	Set started = "", sharding = ""
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(##class(%File).NormalizeFilename($SYSTEM.Util.ManagerDirectory()_"messages.log"))
	While 'stream.AtEnd {
		Set line = stream.ReadLine(4000)
		If line '? 2N1"/"2N1"/"2N1"-"2N1":"2N1":"2N1":"3N1" ".E Continue
		If ($Piece(line, " ", 4, 5) = "[Utility.Event] Instance") && ($Piece(line, " ", 6, 8) = "'IRIS' starting on") {
			Set started = ..UtcOf(line)
			Set sharding = ""
		} ElseIf (started '= "") && (sharding = "") && ($Piece(line, " ", 3) = 2) && ($Piece(line, " ", 4, *) = ..#SHARDINGTEXT) {
			Set sharding = ..UtcOf(line)
		}
	}
}

/// The UTC time of a timed line of messages.log.
ClassMethod UtcOf(line As %String) As %String
{
	Quit ##class(OcuTalon.Data.Time).FromLocal("20"_$Extract(line, 7, 8)_"-"_$Extract(line, 1, 2)_"-"_$Extract(line, 4, 5)_"T"_$Extract(line, 10, 17))
}

/// The lines of one start in a new container, from the second at seconds from the base (see WriteKept): the start line, the failover line from the
/// node id, "Enabling logons", "Interoperability System Startup Complete" and the Sharding error.
ClassMethod NoiseLines(at As %Integer, id As %String = "0a1b2c3d4e5f") As %List
{
	Quit $ListBuild($ListBuild(at, 0, "[Utility.Event] Instance 'IRIS' starting on node zzhostnew by user 'irisowner' on 11/09/2026 UTC"), $ListBuild(at + 1, 2, ..#FAILOVERTEXT_id), $ListBuild(at + 2, 0, "[Utility.Event] Enabling logons"), $ListBuild(at + 3, 0, "[Utility.Event] Interoperability System Startup Complete"), $ListBuild(at + 3, 2, ..#SHARDINGTEXT))
}

/// The five counted lines after a start (see WriteKept): a real error at severity 2 and one at severity 3, the failover line naming an id change
/// ("from node X to Y") and a host name that is not hex, and the Sharding text at severity 3.
ClassMethod LaterLines() As %List
{
	Quit $ListBuild($ListBuild(-2000, 2, "[Utility.Event] Error: ERROR #5002: ObjectScript error: <UNDEFINED>zzvitals+1^ZZVITALS17 *zz"), $ListBuild(-1900, 3, "[Generic.Event] zz a real error of severity 3, ignore"), $ListBuild(-1800, 2, ..#FAILOVERTEXT_"0a1b2c3d4e5f to 5f4e3d2c1b0a"), $ListBuild(-1700, 2, ..#FAILOVERTEXT_"zzhostold"), $ListBuild(-1600, 3, ..#SHARDINGTEXT))
}

/// A line before the window of the tests above, so that the read stops after the kept file (the older files of the instance are not read).
ClassMethod Lead() As %List
{
	Quit $ListBuild($ListBuild(-4000, 0, "[Utility.Event] zz an earlier line of a kept log, ignore"))
}

/// A switched file that cannot be read makes the sign an error, never a count that leaves its lines out.
Method TestUnreadableSwitchedLog()
{
	If '..Ready() Quit
	Set c = ..FirstTimeOfCurrent()
	Do $$$AssertTrue(c '= "", "the current messages.log has a timed line: "_c)
	If c = "" Quit
	Do ..WriteKept("4", c, $ListBuild($ListBuild(-100, 2)))
	Set path = $SYSTEM.Util.ManagerDirectory()_"messages.old_zzvitals17_4"
	Do $$$AssertEquals($ZF(-100, "/SHELL", "chmod", "000", path), 0, "the kept file is made unreadable")
	Set vitals = ##class(OcuTalon.Watch.Reader).Vitals("", "", "")
	Do $$$AssertEquals(vitals.systemLog.outcome, "error", "a kept file that cannot be read: the sign is an error")
}

/// The UTC time of the first timed line of the current messages.log, or "".
ClassMethod FirstTimeOfCurrent() As %String
{
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(##class(%File).NormalizeFilename($SYSTEM.Util.ManagerDirectory()_"messages.log"))
	While 'stream.AtEnd {
		Set line = stream.ReadLine(4000)
		If line ? 2N1"/"2N1"/"2N1"-"2N1":"2N1":"2N1":"3N1" ".E Quit
	}
	If $Get(line) '? 2N1"/"2N1"/"2N1"-"2N1":"2N1":"2N1":"3N1" ".E Quit ""
	Quit ..UtcOf(line)
}

/// Writes a kept log, messages.old_zzvitals17_<name>, with one line for each {seconds from base (UTC), severity, text} of lines; the text after the
/// severity is optional (default: "[Zz.Event] a line of a kept log, ignore").
Method WriteKept(name As %String, base As %String, lines As %List)
{
	Set file = ##class(%Stream.FileCharacter).%New()
	Set file.Filename = $SYSTEM.Util.ManagerDirectory()_"messages.old_zzvitals17_"_name
	Set position = 0
	While $ListNext(lines, position, item) {
		Set local = ##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).AddSeconds(base, $List(item, 1)))
		Do file.WriteLine($Extract(local, 6, 7)_"/"_$Extract(local, 9, 10)_"/"_$Extract(local, 3, 4)_"-"_$Extract(local, 12, 19)_":000 (1) "_$List(item, 2)_" "_$Select($ListLength(item) > 2: $List(item, 3), 1: "[Zz.Event] a line of a kept log, ignore"))
	}
	Do $$$AssertStatusOK(file.%Save(), "the kept log "_name_" is written")
}

Method DropSwitchedLogs()
{
	Set directory = $SYSTEM.Util.ManagerDirectory()
	Set file = $ZSearch(directory_"messages.old_zzvitals17_*")
	While file '= "" {
		Set found($Increment(found)) = file
		Set file = $ZSearch("")
	}
	For i = 1:1:+$Get(found) {
		Do ##class(%File).Delete(found(i))
	}
}

/// An item whose host status is Error is named in errored; one that is not, is not.
Method TestErroredItems()
{
	If '..Ready() Quit
	Do ..ClearMonitor()
	Set from = ##class(OcuTalon.Watch.Mark).FromCreated(##class(OcuTalon.Data.Time).NowUtc())
	Do $$$AssertEquals(##class(OcuTalon.Watch.Reader).Failures(..#ORDERS, ..#ORDERSPRODUCTION, from, 10, .rows, .state, .disabled, .stoppedAt, .errored, .queues), "read", "the outcome is read")
	Do $$$AssertEquals(errored.%ToJSON()_"|"_queues.%ToJSON(), "[]|[]", "a healthy Orders has no item in error and no queue")
	Do ..PutMonitor("Error")
	Do ##class(OcuTalon.Watch.Reader).Failures(..#ORDERS, ..#ORDERSPRODUCTION, from, 10, .rows, .state, .disabled, .stoppedAt, .errored, .queues)
	Do $$$AssertEquals(errored.%ToJSON(), "["""_..#ITEMNAME_"""]", "an item whose status is Error is named")
	Do ..PutMonitor("restore")
	Do ##class(OcuTalon.Watch.Reader).Failures(..#ORDERS, ..#ORDERSPRODUCTION, from, 10, .rows, .state, .disabled, .stoppedAt, .errored, .queues)
	Do $$$AssertEquals(errored.%ToJSON(), "[]", "and not once its status is put back")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Reader).Failures(..#ORDERS, "Zz.Other", from, 10, .rows, .state, .disabled, .stoppedAt, .errored, .queues), "not_current", "another production is not current")
	Do $$$AssertEquals(errored.%ToJSON()_"|"_queues.%ToJSON(), "[]|[]", "and gives neither")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Reader).Failures("ZZNONE", ..#ORDERSPRODUCTION, from, 10, .rows, .state, .disabled, .stoppedAt, .errored, .queues), "unreadable", "an unreadable namespace is unreadable")
	Do $$$AssertEquals(errored.%ToJSON()_"|"_queues.%ToJSON(), "[]|[]", "and gives neither")
}

/// Queued messages (Status 2) of an item of the production are its queue, with the count and the time of the oldest.
Method TestQueues()
{
	If '..Ready() Quit
	Set from = ##class(OcuTalon.Watch.Mark).FromCreated(##class(OcuTalon.Data.Time).NowUtc())
	Set old = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -660)
	Set newer = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -60)
	Do ..Queue(..#ITEMNAME, 2, old)
	Do ..Queue(..#ITEMNAME, 1, newer)
	Do ..Queue("ZzNotAnItem", 1, old)
	Do $$$AssertEquals(##class(OcuTalon.Watch.Reader).Failures(..#ORDERS, ..#ORDERSPRODUCTION, from, 10, .rows, .state, .disabled, .stoppedAt, .errored, .queues), "read", "the outcome is read")
	Do $$$AssertTrue($IsObject(queues) && (queues.%Size() = 1), "one queue: a queue of a name that is not an item of the production is not its own: "_$Select($IsObject(queues): queues.%ToJSON(), 1: "unread:"_queues)_" headers "_..Headers)
	If '$IsObject(queues) || (queues.%Size() '= 1) Quit
	Set queue = queues.%Get(0)
	Do $$$AssertEquals(queue.name_"|"_queue.count_"|"_queue.oldestAt, ..#ITEMNAME_"|3|"_old, "the item's queue: its count and the time of its oldest message")
	Do ..DropHeaders()
	Do ##class(OcuTalon.Watch.Reader).Failures(..#ORDERS, ..#ORDERSPRODUCTION, from, 10, .rows, .state, .disabled, .stoppedAt, .errored, .queues)
	Do $$$AssertEquals(queues.%ToJSON(), "[]", "no queue once the messages are gone")
}

/// Build over the real readers: with a production watch on Orders and a history that ran every minute, the five vital rows are read (never
/// not_checked on the throwaway), the watch passes, and an item in error makes its row failed through the real live read.
Method TestBuildOnRealSeams()
{
	If '..Ready() Quit
	Do ..ClearMonitor()
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzvitalsbuild")
	Set check = ##class(OcuTalon.Test.Data.Fixture).Check(session, ..#ORDERS, ..#ORDERSPRODUCTION, {"CreatedAt": "2030-05-01T10:00:00Z", "DisplayName": "Orders"})
	Set ..Fixtures = session_","_check
	For i = 0:1:9 {
		Set insert = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO OcuTalon_Digest_Data.CheckRun (CheckRef, SessionRef, RanAt, Result, Reason, Finding) VALUES (?, ?, ?, 'passed', '', '')", check, session, ##class(OcuTalon.Data.Time).AddSeconds("2030-06-01T11:50:30Z", i * 60))
		Do $$$AssertTrue(insert.%SQLCODE '< 0, "a run is recorded")
	}
	Set sc = ##class(OcuTalon.Checks.Coverage).Build(session, "2030-06-01T11:50:00Z", "2030-06-01T12:00:00Z", .rows, .lines, .vitals)
	Do $$$AssertStatusOK(sc, "Build is OK")
	Do $$$AssertEquals(rows.%Size(), 6, "five vital rows and the watch")
	For i = 0:1:4 {
		Do $$$AssertTrue(rows.%Get(i).result '= "not_checked", rows.%Get(i).entry_" was read: "_rows.%Get(i).result_" "_rows.%Get(i).finding)
	}
	Do $$$AssertEquals(rows.%Get(5).result_"|"_rows.%Get(5).entry, "passed|Orders production", "the watch passes with nothing found live")
	Do $$$AssertTrue(vitals.figures.upDays?1.N, "upDays is a whole number: "_vitals.figures.upDays)
	Do ..PutMonitor("Error")
	Set sc = ##class(OcuTalon.Checks.Coverage).Build(session, "2030-06-01T11:50:00Z", "2030-06-01T12:00:00Z", .rows, .lines, .vitals)
	Do $$$AssertStatusOK(sc, "Build is OK with an item in error")
	Do $$$AssertEquals(rows.%Get(5).result_"|"_rows.%Get(5).finding, "failed|1 item in error", "an item in error makes the watch's row failed")
}

/// Removes the session, check and runs of TestBuildOnRealSeams.
Method DropBuildFixtures()
{
	If ..Fixtures = "" Quit
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.CheckRun WHERE SessionRef = ?", $Piece(..Fixtures, ",", 1))
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Fixtures)
	Set ..Fixtures = ""
}

Method TestNoSwitch()
{
	Set here = $Namespace
	Do ##class(OcuTalon.Watch.Reader).Vitals($ListBuild(..#ORDERS), "", "")
	Do $$$AssertEquals($Namespace, here, "the namespace is as it was")
	For name = "Vitals", "Database", "DatabaseName", "VolumeFree", "Databases", "Add", "SevereLines", "SevereLinesIn", "StartNoise" {
		Set method = ##class(%Dictionary.CompiledMethod).%OpenId("OcuTalon.Watch.Reader||"_name)
		Do $$$AssertTrue($IsObject(method), name_" exists")
		If '$IsObject(method) Continue
		Set code = $ZConvert(method.Implementation.Read(32000), "U")
		Do $$$AssertTrue(($Find(code, "$NAMESPACE") = 0) && ($Find(code, "ZNSPACE") = 0) && ($Find(code, "$ZNSPACE") = 0), name_" has no namespace switch in its code (AD-3: only Current switches)")
	}
}

/// --- helpers ---
/// A database created in a temporary folder with a maximum size of megabytes; the folder, "" when it could not be made.
Method MakeDatabase(megabytes As %Integer) As %String
{
	Set folder = ##class(%File).NormalizeDirectory("/tmp/zzvitals17")
	Do ##class(%File).RemoveDirectoryTree(folder)
	Do ##class(%File).CreateDirectoryChain(folder)
	Set ..Folder = folder
	New $Namespace
	Set $Namespace = "%SYS"
	Set sc = $$CreateDatabase^%SYS.DATABASE(folder, 8192, 1, , , megabytes)
	Do $$$AssertStatusOK(sc, "the database is created")
	Quit $Select(+sc: folder, 1: "")
}

Method DropDatabase()
{
	If ..Folder = "" Quit
	New $Namespace
	Set $Namespace = "%SYS"
	Set sc = $$DeleteDatabase^%SYS.DATABASE(..Folder)
	Do ##class(%File).RemoveDirectoryTree(..Folder)
	Set ..Folder = ""
}

/// Puts the host status of ITEMNAME in OCUORDERS: "Error" saves the one found and writes it, "restore" puts the saved one back.
Method PutMonitor(value As %String)
{
	If '##class(%SYS.Namespace).Exists(..#ORDERS) Quit
	New $Namespace
	Set $Namespace = ..#ORDERS
	If value = "restore" {
		If $Data(^||VitalsTest("status")) {
			If $ListGet(^||VitalsTest("status"), 1) {
				Set ^IRIS.Temp.EnsHostMonitor(..#ORDERS, ..#ITEMNAME, "%Status") = $List(^||VitalsTest("status"), 2)
			} Else {
				Kill ^IRIS.Temp.EnsHostMonitor(..#ORDERS, ..#ITEMNAME, "%Status")
			}
			Kill ^||VitalsTest("status")
		}
		Quit
	}
	If '$Data(^||VitalsTest("status")) {
		Set ^||VitalsTest("status") = $ListBuild($Data(^IRIS.Temp.EnsHostMonitor(..#ORDERS, ..#ITEMNAME, "%Status")) # 10, $Get(^IRIS.Temp.EnsHostMonitor(..#ORDERS, ..#ITEMNAME, "%Status")))
	}
	Set ^IRIS.Temp.EnsHostMonitor(..#ORDERS, ..#ITEMNAME, "%Status") = value
}

/// Sets aside the host status of every item of OCUORDERS whose status is Error, writing OK in its place; RestoreMonitor puts each back.
Method ClearMonitor()
{
	If '##class(%SYS.Namespace).Exists(..#ORDERS) Quit
	New $Namespace
	Set $Namespace = ..#ORDERS
	Set item = ""
	For {
		Set item = $Order(^IRIS.Temp.EnsHostMonitor(..#ORDERS, item))
		Quit:item=""
		If $Get(^IRIS.Temp.EnsHostMonitor(..#ORDERS, item, "%Status")) '= "Error" Continue
		If '$Data(^||VitalsTest("cleared", item)) Set ^||VitalsTest("cleared", item) = "Error"
		Set ^IRIS.Temp.EnsHostMonitor(..#ORDERS, item, "%Status") = "OK"
	}
}

/// Puts back the statuses that ClearMonitor set aside.
Method RestoreMonitor()
{
	If '##class(%SYS.Namespace).Exists(..#ORDERS) Quit
	New $Namespace
	Set $Namespace = ..#ORDERS
	Set item = ""
	For {
		Set item = $Order(^||VitalsTest("cleared", item))
		Quit:item=""
		Set ^IRIS.Temp.EnsHostMonitor(..#ORDERS, item, "%Status") = ^||VitalsTest("cleared", item)
	}
	Kill ^||VitalsTest("cleared")
}

/// count queued headers (Status 2) for the item in OCUORDERS, created at the UTC time; their ids are kept for DropHeaders.
Method Queue(item As %String, count As %Integer, at As %String)
{
	New $Namespace
	Set $Namespace = ..#ORDERS
	Set stamp = $Translate($Extract(at, 1, 19), "TZ", " ")
	For i = 1:1:count {
		Set header = ##class(Ens.MessageHeader).%New()
		Set header.TimeCreated = stamp
		Set header.SourceConfigName = "ZzVitalsTest"
		Set header.TargetConfigName = item
		Set header.Type = 1
		Set header.Status = 2
		Set header.MessageBodyClassName = "Ens.StringRequest"
		$$$ThrowOnError(header.%Save())
		Set ..Headers = ..Headers_$Select(..Headers = "": "", 1: ",")_header.%Id()
	}
}

Method DropHeaders()
{
	If (..Headers = "") || '##class(%SYS.Namespace).Exists(..#ORDERS) Quit
	New $Namespace
	Set $Namespace = ..#ORDERS
	For i = 1:1:$Length(..Headers, ",") {
		Do ##class(Ens.MessageHeader).%DeleteId($Piece(..Headers, ",", i))
	}
	Set ..Headers = ""
}

/// The member names of an object, sorted, comma-separated.
ClassMethod Names(object As %DynamicObject) As %String
{
	Kill list
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.name) {
		Set list(name) = ""
	}
	Set text = ""
	Set name = ""
	For {
		Set name = $Order(list(name))
		Quit:name=""
		Set text = text_$Select(text = "": "", 1: ",")_name
	}
	Quit text
}

}
