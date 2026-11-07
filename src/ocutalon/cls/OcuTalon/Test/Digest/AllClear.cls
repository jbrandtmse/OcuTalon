/// Tests of the all-clear rules of the digest as one rule set (Story 17.7; AD-28, AD-32, FR-35, FR-37, SM-4). Safe on a slot: no production runs; a Compose is
/// handled on a shadow instance of OcuTalon.Test.Digest.ProcessProbe, whose rows are Checks.Coverage.Build over fixture watches and their runs, through
/// OcuTalon.Test.Digest.CoverageProbe (a production in error through FeedRead, a heartbeat gap through FeedGaps), or are fed to the probe. The window of a
/// Compose is ten minutes long. The parts are rendered through Catalog.Render for the channel telegram.
///   - TestProductionInError, TestChecksPaused, TestAllPassing: the three cases of step 2. The key, AllClear, whatFailed in Render's order, the quiet sentence and
///     the rendered reserved part: an item in error gives checks.notEverythingRestPassed with the entry named before "Everything else I checked passed."; a
///     check paused by a heartbeat gap gives checks.notEverything with its entries named and no "Everything else"; every check passing gives the all-clear
///     with what was checked;
///   - TestRecordedCasesAgree: the rows, expectation and results of eval/digest-production-error, eval/digest-checks-paused and eval/digest-all-passing agree with
///     what the probe composes in the same three situations (the entries and results of the rows, the key, AllClear, the named and the checked entries);
///   - TestFailedBeforeNotChecked: with a not-checked entry before a failed one in Build's order, whatFailed names the failed one first;
///   - TestPassWithoutTime: a row that says passed with no check time is not checked: it is named, the quiet sentence is not used and AllClear is 0;
///   - TestVitalWithoutTime: a vital sign that says passed with no check time is named in digest.vitalsNotAll and AllClear is 0;
///   - TestNothingWatched: the vital signs are reported, the digest says nothing is watched, the key is checks.nothingWatched, AllClear is 0 and no rendering
///     says that everything passed;
///   - TestMorningDigest (UJ-2): with every row passing and the vital figures 3 days, 60% and 20%, at 08:00, the rendering holds the greeting, the healthy
///     sentence with the figures, the production summary and the reserved sentence, which come from code parts; other figures give other sentences.
Class OcuTalon.Test.Digest.AllClear Extends OcuTalon.Test.Digest.ProbeCase
{

Parameter RESERVED = "Everything I checked passed.";

Parameter RESTPASSED = "Everything else I checked passed.";

Parameter HEALTHY = "Your IRIS system is healthy";

/// Composes the digest of a session in one of the three situations of step 2 ("error", "paused" or "passing"), with the watches Results then Orders ("error") or Orders
/// then Results and the vital readings of reading (healthy by default), and gives {notice, sent, text, rows}: the Notification, the Sent row, the rendering and the watched rows of the Notification.
Method Situation(which As %String, endLocal As %String = "2030-06-03T09:00:00", reading As %DynamicObject = "") As %DynamicObject
{
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#COVERAGE, "Reset")
	If $IsObject(reading) Do $ClassMethod(..#COVERAGE, "Feed", reading)
	Set session = ..Session()
	Set compose = ..Compose(session, endLocal, session_":"_which)
	Set names = $Select(which = "error": $ListBuild("Results", "Orders"), 1: $ListBuild("Orders", "Results"))
	Set position = 0
	While $ListNext(names, position, name) {
		Set production = "Zz.AllClear."_name
		Set ref = ..Watch(session, production, name)
		Do ..Every(ref, session, compose)
		If (which = "error") && (name = "Orders") Do $ClassMethod(..#COVERAGE, "FeedRead", production, {"errored": ["OrdersToWarehouse"]})
	}
	If which = "paused" {
		Set from = ##class(OcuTalon.Data.Time).AddSeconds(compose.WindowStart, 180)
		Do $ClassMethod(..#COVERAGE, "FeedGaps", [{"start": (from), "end": (##class(OcuTalon.Data.Time).AddSeconds(from, 300)), "missed": 5}])
	}
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(compose, host), which_": the Compose is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 1, which_": one Notification is sent")
	Set notice = ..Notice(1)
	Set rows = []
	If $IsObject(notice) {
		For i = 5:1:notice.slots.rows.%Size() - 1 {
			Do rows.%Push(notice.slots.rows.%Get(i))
		}
	}
	Quit {"notice": (notice), "sent": (..Sent(session)), "text": (..Render(notice.slots)), "rows": (rows), "session": (session)}
}

Method TestProductionInError()
{
	Set got = ..Situation("error")
	Set notice = got.notice
	Do $$$AssertEquals(..Keys(notice.slots), "digest.greetingMorning,digest.healthy,digest.checked,checks.notEverythingRestPassed,digest.needsYouOne,digest.savedNone,digest.cost", "the parts: the vital signs, what was checked, the reserved part and what needs the user")
	Do $$$AssertEquals(notice.catalogKey, "checks.notEverythingRestPassed", "the key says that the rest passed")
	Do $$$AssertEquals(..Part(notice.slots, "checks.notEverythingRestPassed").slots.%ToJSON(), "{""whatFailed"":""Orders production""}", "and names the production in error")
	Do $$$AssertEquals(..Part(notice.slots, "digest.checked").slots.checked, "the Results production and the Orders production", "what was checked is every watched entry, in Build's order")
	Do $$$AssertEquals(got.sent.AllClear, 0, "AllClear is 0")
	Set reserved = ..RenderOne("checks.notEverythingRestPassed", ..Part(notice.slots, "checks.notEverythingRestPassed").slots)
	Do $$$AssertEquals(reserved, "Not everything: Orders production. "_..#RESTPASSED, "the rendered part names the entry before "_..#RESTPASSED)
	Do $$$AssertTrue('(got.text [ ..#RESERVED), "and nothing says: "_..#RESERVED)
	Do $$$AssertTrue('(got.text [ "(all running, no errors, no backlog)"), "or that all is running")
	Do $$$AssertEquals(..Part(notice.slots, "digest.needsYouOne").slots.what, "Orders production: 1 item in error", "the failed row is what needs the user")
}

Method TestChecksPaused()
{
	Set got = ..Situation("paused")
	Set notice = got.notice
	Do $$$AssertEquals(..Keys(notice.slots), "digest.greetingMorning,digest.healthy,digest.checked,checks.notEverything,digest.savedNone,digest.cost", "the parts hold the reserved part of nothing passed")
	Do $$$AssertEquals(notice.catalogKey, "checks.notEverything", "the key is checks.notEverything")
	Do $$$AssertEquals(..Part(notice.slots, "checks.notEverything").slots.%ToJSON(), "{""whatFailed"":""Orders production and Results production""}", "its entries are named, in the order of the rows")
	Do $$$AssertEquals(got.sent.AllClear, 0, "AllClear is 0")
	Do $$$AssertTrue('(got.text [ ..#RESERVED), "nothing says: "_..#RESERVED)
	Do $$$AssertTrue('(got.text [ ..#RESTPASSED), "and nothing says: "_..#RESTPASSED)
	Do $$$AssertTrue(got.text [ "Not everything: Orders production and Results production.", "the rendering names them")
	Do $$$AssertEquals(got.rows.%Get(0).result_"|"_got.rows.%Get(0).finding, "not_checked|Background checks were paused", "the rows are not checked, paused")
}

Method TestAllPassing()
{
	Set got = ..Situation("passing")
	Set notice = got.notice
	Do $$$AssertEquals(..Keys(notice.slots), "digest.greetingMorning,digest.healthy,digest.checkedQuiet,checks.allPassed,digest.savedNone,digest.cost", "the quiet parts")
	Do $$$AssertEquals(notice.catalogKey, "checks.allPassed", "the key is the all-clear")
	Do $$$AssertEquals(..Part(notice.slots, "digest.checkedQuiet").slots.checked, "the Orders production and the Results production", "with what was checked")
	Do $$$AssertEquals(got.sent.AllClear, 1, "AllClear is 1")
	Do $$$AssertTrue(got.text [ "I checked the Orders production and the Results production (all running, no errors, no backlog).", "the rendering says what was checked")
	Do $$$AssertTrue(got.text [ ..#RESERVED, "and gives the all-clear: "_..#RESERVED)
	Do $$$AssertTrue('(got.text [ ..#RESTPASSED), "not the sentence of the rest")
}

/// The recorded cases and the probe's rows agree: the same entries, results and findings, and the key, AllClear, named and checked entries that the case expects.
Method TestRecordedCasesAgree()
{
	Set folder = ##class(%File).NormalizeDirectory(##class(OcuTalon.Eval.In).#FOLDER)
	Do $$$AssertTrue(##class(%File).DirectoryExists(folder), "the repository's eval/ is mounted at "_folder_" (a throwaway or CI stack)")
	If '##class(%File).DirectoryExists(folder) Quit
	For which = "error|digest-production-error", "paused|digest-checks-paused", "passing|digest-all-passing" {
		Set name = $Piece(which, "|", 2)
		Set case = ##class(%DynamicAbstractObject).%FromJSONFile(##class(%File).NormalizeFilename("case.json", ##class(%File).SubDirectoryName(folder, name)))
		Set got = ..Situation($Piece(which, "|", 1))
		Set recorded = ""
		Set iterator = case.checks.%GetIterator()
		While iterator.%GetNext(, .row) {
			Set recorded = recorded_$Select(recorded = "": "", 1: ";")_row.result_"|"_row.entry_"|"_row.finding
		}
		Set built = ""
		Set iterator = got.rows.%GetIterator()
		While iterator.%GetNext(, .row) {
			Set built = built_$Select(built = "": "", 1: ";")_row.result_"|"_row.entry_"|"_row.finding
		}
		Do $$$AssertEquals(built, recorded, name_": the rows that Build gives are the case's recorded rows")
		Set expectation = case.expectation
		Do $$$AssertEquals(got.notice.catalogKey, expectation.catalogKey, name_": the key is the expected one")
		Do $$$AssertEquals(got.sent.AllClear, +expectation.allClear, name_": AllClear is the expected one")
		Set whatFailed = ""
		Set part = ..Part(got.notice.slots, expectation.catalogKey)
		If $IsObject(part) && part.slots.%IsDefined("whatFailed") Set whatFailed = part.slots.whatFailed
		Set named = ""
		Set iterator = expectation.named.%GetIterator()
		While iterator.%GetNext(, .entry) {
			Set named = named_$Select(named = "": "", 1: "|")_entry
		}
		Do $$$AssertEquals($Replace(whatFailed, " and ", "|"), named, name_": whatFailed names the expected entries in the expected order")
		Set checked = ""
		Set iterator = expectation.checked.%GetIterator()
		While iterator.%GetNext(, .entry) {
			Set checked = checked_$Select(checked = "": "", 1: " and ")_"the "_entry
		}
		Set quiet = ..Part(got.notice.slots, $Select(expectation.named.%Size() = 0: "digest.checkedQuiet", 1: "digest.checked"))
		Do $$$AssertTrue($IsObject(quiet) && (quiet.slots.checked = checked), name_": and the checked part lists the expected entries")
		Set key = ##class(OcuTalon.Checks.Render).Render(case.checks, .ordered)
		Do $$$AssertEquals(key, expectation.catalogKey, name_": Checks.Render gives the key over the recorded rows")
		Set failedFirst = ""
		Set iterator = ordered.%GetIterator()
		While iterator.%GetNext(, .row) {
			If row.result '= "passed" Set failedFirst = failedFirst_$Select(failedFirst = "": "", 1: "|")_row.entry
		}
		Do $$$AssertEquals(failedFirst, named, name_": and the entries it does not pass, in its order, are the expected named ones")
	}
}

/// Build's order puts a not-checked entry before a failed one; the digest names the failed one first.
Method TestFailedBeforeNotChecked()
{
	Set session = ..Session()
	Do $ClassMethod(..#PROBE, "Feed", [(..Watched("not_checked", "A production", "Couldn't be read")), (..Watched("failed", "B production", "3 items in error"))])
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(..Compose(session), host), "the Compose is handled")
	Set notice = ..Notice(1)
	Do $$$AssertEquals(notice.catalogKey, "checks.notEverything", "nothing passed")
	Do $$$AssertEquals(..Part(notice.slots, "checks.notEverything").slots.whatFailed, "B production and A production", "the failed entry comes first")
	Do $$$AssertEquals(..Part(notice.slots, "digest.checked").slots.checked, "the A production and the B production", "what was checked keeps Build's order")
	Do $$$AssertEquals(..Part(notice.slots, "digest.needsYouOne").slots.what, "B production: 3 items in error", "and what needs the user is the failed row alone")
	Do $$$AssertEquals(..Sent(session).AllClear, 0, "AllClear is 0")
	Do $$$AssertTrue(..Render(notice.slots) [ "Not everything: B production and A production.", "and the rendering names the failed one first")
}

/// A row that says passed but has no check time is not checked.
Method TestPassWithoutTime()
{
	Set session = ..Session()
	Do $ClassMethod(..#PROBE, "Feed", [(..Watched("passed", "A production", "", ""))])
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(..Compose(session), host), "the Compose is handled")
	Set notice = ..Notice(1)
	Do $$$AssertEquals(..Keys(notice.slots), "digest.greetingMorning,digest.healthy,digest.checked,checks.notEverything,digest.savedNone,digest.cost", "the checked part is digest.checked, not the quiet one")
	Do $$$AssertEquals(notice.catalogKey, "checks.notEverything", "the key is checks.notEverything")
	Do $$$AssertEquals(..Part(notice.slots, "checks.notEverything").slots.whatFailed, "A production", "the entry is named")
	Do $$$AssertEquals(..Sent(session).AllClear, 0, "AllClear is 0")
	Set text = ..Render(notice.slots, 0)
	Do $$$AssertTrue('(text [ "(all running, no errors, no backlog)") && '(text [ ..#RESERVED), "nothing says that all is running or that everything passed")
	Do $$$AssertTrue(text [ "I checked the A production.", "and the part renders")
}

/// A vital sign that says passed but has no check time is not passed.
Method TestVitalWithoutTime()
{
	Set session = ..Session()
	Set vitals = $ClassMethod(..#PROBE, "Healthy")
	Set row = vitals.rows.%Get(0)
	Set row.checkedAt = ""
	Do $ClassMethod(..#PROBE, "Feed", [(..Watched("passed", "A production"))], vitals)
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(..Compose(session), host), "the Compose is handled")
	Set notice = ..Notice(1)
	Do $$$AssertEquals(..Keys(notice.slots), "digest.greetingMorning,digest.vitalsNotAll,digest.checkedQuiet,checks.allPassed,digest.savedNone,digest.cost", "the vital part is digest.vitalsNotAll")
	Do $$$AssertEquals(..Part(notice.slots, "digest.vitalsNotAll").slots.whatFailed, "IRIS instance", "which names the sign")
	Do $$$AssertEquals(..Sent(session).AllClear, 0, "AllClear is 0 although every watched entry passed")
	Set text = ..Render(notice.slots, 0)
	Do $$$AssertTrue(text [ "Not every vital sign passed: IRIS instance.", "the rendering names it")
	Do $$$AssertTrue('(text [ ..#HEALTHY), "and says nothing of a healthy system")
}

/// With nothing watched the vital signs are reported and nothing says that everything passed.
Method TestNothingWatched()
{
	Set session = ..Session()
	Do $ClassMethod(..#PROBE, "Feed", [])
	Set host = ..Host()
	Do $$$AssertStatusOK(..Handle(..Compose(session), host), "the Compose is handled")
	Set notice = ..Notice(1)
	Do $$$AssertEquals(..Keys(notice.slots), "digest.greetingMorning,digest.healthy,digest.nothingWatched,digest.savedNone,digest.cost", "the parts: the vital signs and nothing watched")
	Do $$$AssertEquals(notice.catalogKey, "checks.nothingWatched", "the key is checks.nothingWatched")
	Do $$$AssertEquals(..Sent(session).AllClear, 0, "AllClear is 0")
	Set text = ..Render(notice.slots)
	Do $$$AssertTrue(text [ "I'm not watching any productions yet, so this digest covers the vital signs only. Ask me to watch one.", "the digest says that nothing is watched")
	Do $$$AssertTrue(text [ ..#HEALTHY, "and reports the vital signs")
	Do $$$AssertTrue('(text [ ..#RESERVED) && '(text [ ..#RESTPASSED), "no rendering gives an all-clear")
}

/// UJ-2: the morning digest with every check passing; the figures, the production summary, the healthy sentence and the all-clear come from code parts.
Method TestMorningDigest()
{
	Set got = ..Situation("passing", "2030-06-03T08:00:00")
	Set text = got.text
	Do $$$AssertTrue(text [ "Good morning.", "the greeting")
	Do $$$AssertTrue(text [ "Your IRIS system is healthy: up 3 days, databases 60% full, journal space fine, license use 20%.", "the vital signs with their figures")
	Do $$$AssertTrue(text [ "I checked the Orders production and the Results production (all running, no errors, no backlog).", "the production summary")
	Do $$$AssertTrue(text [ ..#RESERVED, "and the all-clear")
	Do $$$AssertEquals(got.sent.AllClear, 1, "AllClear is 1")
	Set healthy = ..Part(got.notice.slots, "digest.healthy")
	Do $$$AssertEquals(healthy.slots.count_"|"_healthy.slots.databasesFull_"|"_healthy.slots.licenseUse, "3|60|20", "the figures are slots of the code part")
	Set reading = $ClassMethod(..#COVERAGE, "Healthy")
	Set reading.instance.upSeconds = 7 * 86400 + 60
	Set database = reading.databases.%Get(0)
	Set database.volumeFreePercent = 65
	Set reading.license.usePercent = 41
	Set other = ..Situation("passing", "2030-06-03T08:00:00", reading)
	Do $$$AssertTrue(other.text [ "Your IRIS system is healthy: up 7 days, databases 35% full, journal space fine, license use 41%.", "other readings give other figures: they are read from the rows, not fixed")
}

}
