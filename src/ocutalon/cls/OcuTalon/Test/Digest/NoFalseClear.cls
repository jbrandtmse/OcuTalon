/// Tests that the database space row of Checks.Coverage never gives a false all-clear (Story 17.5; AD-18, owner ruling U-290 as reversed), through
/// Test.Digest.CoverageProbe. The expected row of every state of three databases is written out here in plain text, so that a change of a rule or of a
/// ruled text is seen. The rows are real; only the readings are fed.
///   - TestEveryCombination: three databases, each ok, ok with a maximum, low, low with a maximum, or unread (125 states): the row is failed when any
///     volume is low, else not_checked (unread) when any database is unread, else not_checked (size limit) when any database has a maximum, else
///     passed; a passed row never has a capped or an unread database behind it; vitals.rows holds the same row; databasesFull follows the rule;
///   - TestCappedRowEndToEnd: Build's line for a capped database, rendered by the catalog, reads as the ruled sentence, in plain ASCII, and the row is
///     not_checked whatever the window and with a watch beside it;
///   - TestSixthOutputOptional: the five-argument call gives the same rows.
Class OcuTalon.Test.Digest.NoFalseClear Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Digest.CoverageProbe";

Parameter FROM = "2030-06-01T11:50:00Z";

Parameter TO = "2030-06-01T12:00:00Z";

Parameter SIZELIMIT = "OcuTalon can't read this database's size limit";

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
	If ..Sessions '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Sessions)
	Set ..Sessions = ""
}

Method TestEveryCombination()
{
	Set session = ..Session()
	Set states = $ListBuild("ok", "okcap", "low", "lowcap", "err")
	Set names = $ListBuild("OCUTALON_CODE", "OCUTALON_DATA", "OCUORDERS_DATA")
	Set checked = 0
	Set passed = 0
	Set kinds = ""
	Set bad = ""
	For a = 1:1:5 {
		For b = 1:1:5 {
			For c = 1:1:5 {
				Set combo = $ListBuild($List(states, a), $List(states, b), $List(states, c))
				Set vitals = $ClassMethod(..#PROBE, "Healthy")
				Set vitals.databases = []
				Set position = 0
				Set index = 0
				While $ListNext(combo, position, state) {
					Set index = index + 1
					Do vitals.databases.%Push(..Database($List(names, index), state))
				}
				Do $ClassMethod(..#PROBE, "Feed", vitals)
				Set sc = $ClassMethod(..#PROBE, "Build", session, ..#FROM, ..#TO, .rows, .lines, .vit)
				Set expected = ..Expected(combo, names)
				Set row = rows.%Get(1)
				Set got = row.result_"|"_row.finding_"|"_lines.%Get(1).key_"|"_vit.figures.databasesFull
				Set checked = checked + 1
				If $SYSTEM.Status.IsError(sc) || (got '= expected) Set bad = bad_" ["_$ListToString(combo, "/")_" got "_got_" want "_expected_"]"
				If row.result = "passed" {
					Set passed = passed + 1
					If $ListFind(combo, "okcap") || $ListFind(combo, "err") Set bad = bad_" [FALSE ALL-CLEAR "_$ListToString(combo, "/")_"]"
				}
				Set same = vit.rows.%Get(1)
				If (same.result_"|"_same.finding_"|"_same.entry) '= (row.result_"|"_row.finding_"|"_row.entry) Set bad = bad_" [vitals.rows differs "_$ListToString(combo, "/")_"]"
				Set kinds = kinds_$Piece(got, "|", 1)_","
			}
		}
	}
	Do $$$AssertEquals(checked, 125, "all 125 states of three databases were built")
	Do $$$AssertEquals(bad, "", "every row is the expected one, and none is a false all-clear")
	Do $$$AssertEquals(passed, 1, "only the state of three plain databases passes (no maximum, no low volume, none unread)")
	Do $$$AssertTrue(kinds [ "failed,", "the failed rows were seen")
	Do $$$AssertTrue(kinds [ "not_checked,", "and the not_checked rows")
}

/// The expected result|finding|key|databasesFull of the database space row, from the plain rules.
ClassMethod Expected(combo As %List, names As %List) As %String
{
	Set low = ""
	Set err = 0
	Set cap = 0
	Set position = 0
	Set index = 0
	While $ListNext(combo, position, state) {
		Set index = index + 1
		If (state = "low") || (state = "lowcap") Set low = low_$ListBuild($List(names, index)_" 8% free")
		If state = "err" Set err = 1
		If (state = "okcap") || (state = "lowcap") Set cap = 1
	}
	Set lowest = $Select(low '= "": 8, 1: 40)
	If low '= "" Quit "failed|"_$ListToString(low, ", ")_"|digest.failed|"_(100 - lowest)
	If err Quit "not_checked|Couldn't be read|digest.notCheckedError|"
	If cap Quit "not_checked|"_..#SIZELIMIT_"|digest.notCheckedSizeLimit|"
	Quit "passed||digest.passed|"_(100 - lowest)
}

Method TestCappedRowEndToEnd()
{
	Set session = ..Session()
	Set watch = ##class(OcuTalon.Test.Data.Fixture).Check(session, "ZZNS", "Zz.NoFalse", {"CreatedAt": "2030-05-01T10:00:00Z", "DisplayName": "Orders"})
	Set ..Sessions = ..Sessions_","_watch
	Set vitals = $ClassMethod(..#PROBE, "Healthy")
	Set vitals.databases = [(..Database("OCUTALON_DATA", "okcap"))]
	Do $ClassMethod(..#PROBE, "Feed", vitals)
	Set windows = $ListBuild(..#FROM_"|"_..#TO, "|", "|"_..#TO, ..#FROM_"|", "2030-06-01T00:00:00Z|2030-06-02T00:00:00Z")
	For i = 1:1:$ListLength(windows) {
		Set window = $List(windows, i)
		Set sc = $ClassMethod(..#PROBE, "Build", session, $Piece(window, "|", 1), $Piece(window, "|", 2), .rows, .lines, .vit)
		Do $$$AssertStatusOK(sc, "window '"_window_"': Build is OK")
		Do $$$AssertEquals(rows.%Get(1).entry_"|"_rows.%Get(1).result_"|"_rows.%Get(1).finding, "database space|not_checked|"_..#SIZELIMIT, "window '"_window_"': a capped database is not_checked with the ruled reason")
		Do $$$AssertEquals(lines.%Get(1).key, "digest.notCheckedSizeLimit", "window '"_window_"': on the size-limit line")
		Do $$$AssertTrue(rows.%Size() = 6, "window '"_window_"': the watch row is beside the five vital rows")
	}
	Set sc = $ClassMethod(..#PROBE, "Build", session, ..#FROM, ..#TO, .rows, .lines, .vit)
	Set line = lines.%Get(1)
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(line.key, line.slots, "telegram", ..#TO, 0, .render)
	Do $$$AssertStatusOK(render, "the line renders")
	Do $$$AssertEquals(text, "Not checked: database space (OcuTalon can't read this database's size limit).", "Build's line reads as the ruled sentence")
	Set ascii = 1
	For i = 1:1:$Length(text) {
		If $Ascii(text, i) > 126 Set ascii = 0
	}
	Do $$$AssertTrue(ascii, "in plain ASCII")
	Do $$$AssertEquals($Extract(rows.%Get(1).finding, *), "t", "the finding has no full stop")
	Do $$$AssertEquals(vit.figures.databasesFull, "", "and no figure for a database that was not checked")
}

Method TestSixthOutputOptional()
{
	Set session = ..Session()
	Set vitals = $ClassMethod(..#PROBE, "Healthy")
	Set vitals.databases = [(..Database("OCUTALON_DATA", "lowcap"))]
	Do $ClassMethod(..#PROBE, "Feed", vitals)
	Set sc = $ClassMethod(..#PROBE, "Build", session, ..#FROM, ..#TO, .rows, .lines)
	Do $$$AssertStatusOK(sc, "the five-argument call is OK")
	Do $$$AssertEquals(rows.%Get(1).result_"|"_rows.%Get(1).finding, "failed|OCUTALON_DATA 8% free", "a low volume beats the maximum there too")
}

/// --- helpers ---
Method Session() As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zznofalse")
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Quit ref
}

/// One database reading in a state: ok (40% of its volume free, no maximum), okcap (the same with a 50 MB maximum), low (8% free), lowcap (low with a
/// maximum), err (not read).
Method Database(name As %String, state As %String) As %DynamicObject
{
	Set entry = {"name": (name), "directory": ("/zz/"_$ZConvert(name, "L")_"/"), "volumeFreePercent": 40, "maxBlocks": 0, "outcome": "read"}
	If (state = "low") || (state = "lowcap") Set entry.volumeFreePercent = 8
	If (state = "okcap") || (state = "lowcap") Set entry.maxBlocks = 6400
	If state = "err" {
		Set entry.volumeFreePercent = ""
		Set entry.maxBlocks = ""
		Set entry.outcome = "error"
	}
	Quit entry
}

}
