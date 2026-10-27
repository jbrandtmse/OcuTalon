/// Tests of Checks.Render, OcuTalon.Checks.Render (Story 5.7; AD-28, AD-30): the pure function from the check results to a catalog key and rows. The tests
/// need no production and no table, and run warm. One test for each Render row of the matrix:
///   - TestAllPassed ("All passed"): every row passed gives checks.allPassed, the rows in input order;
///   - TestOneFailing ("One failing"): a failing row among passed ones gives checks.notEverythingRestPassed, the failed row first;
///   - TestNonePassed ("None passed"): no passed row gives checks.notEverything, the failed row before the not-checked one; no passed row never gives the
///     rest-passed key, and a not-checked row never gives the all-passed key;
///   - TestNothingWatched ("Nothing watched"): [] gives checks.nothingWatched and no row;
///   - TestNotRunYet ("Not run yet"): an element with no result, finding or time is a not_checked row with the reason REASONNOTRUN;
///   - TestNotResults ("Not results"): what is not an array, an array of elements with no entry, and a non-array: "" and [];
///   - TestOddValues ("Odd values"): a pass with no or a bad time, an unknown result, values that are not strings, and an entry or finding of 1,200
///     characters;
///   - TestRowsShape: exactly four string keys, in order, and rows is always an array;
///   - TestKeysAreCatalogKeys: each KEY parameter renders through Msg.Catalog.
Class OcuTalon.Test.Checks.Render Extends %UnitTest.TestCase
{

Parameter RENDER = "OcuTalon.Checks.Render";

Parameter T1 = "2026-10-26T14:10:00Z";

Parameter T2 = "2026-10-26T14:11:00Z";

Parameter T3 = "2026-10-26T14:12:00Z";

Method TestAllPassed()
{
	Set key = ##class(OcuTalon.Checks.Render).Render([(..Result("passed", "A", "", ..#T1)), (..Result("passed", "B", "", ..#T2))], .rows)
	Do $$$AssertEquals(key, ..Param("KEYALLPASSED"), "every row passed: checks.allPassed")
	Do $$$AssertEquals(rows.%ToJSON(), [(..Result("passed", "A", "", ..#T1)), (..Result("passed", "B", "", ..#T2))].%ToJSON(), "the rows are A and B")
}

Method TestOneFailing()
{
	Set key = ##class(OcuTalon.Checks.Render).Render([(..Result("passed", "A", "", ..#T1)), (..Result("failed", "B", "3 new failures", ..#T2)), (..Result("passed", "C", "", ..#T3))], .rows)
	Do $$$AssertEquals(key, ..Param("KEYRESTPASSED"), "one failing and others passed: checks.notEverythingRestPassed")
	Do $$$AssertEquals(rows.%ToJSON(), [(..Result("failed", "B", "3 new failures", ..#T2)), (..Result("passed", "A", "", ..#T1)), (..Result("passed", "C", "", ..#T3))].%ToJSON(), "the failed row B comes first, then A and C in input order")
	Set key = ##class(OcuTalon.Checks.Render).Render([(..Result("passed", "A", "", ..#T1)), (..Result("not_checked", "B", "No answer in time", ..#T2)), (..Result("failed", "C", "x", ..#T3)), (..Result("not_checked", "D", "y", ..#T1))], .rows)
	Do $$$AssertEquals(key, ..Param("KEYRESTPASSED"), "a not-checked row with a passed one is the same key")
	Do $$$AssertEquals(..Entries(rows), "C,B,D,A", "the order is failed, then not checked, then passed, each group in input order")
}

Method TestNonePassed()
{
	Set key = ##class(OcuTalon.Checks.Render).Render([(..Result("not_checked", "A", "No answer in time", ..#T1)), (..Result("failed", "B", "Production stopped", ..#T2))], .rows)
	Do $$$AssertEquals(key, ..Param("KEYNOTEVERYTHING"), "no passed row: checks.notEverything, never the rest-passed key")
	Do $$$AssertEquals(rows.%ToJSON(), [(..Result("failed", "B", "Production stopped", ..#T2)), (..Result("not_checked", "A", "No answer in time", ..#T1))].%ToJSON(), "the failed row B before the not-checked row A")
	Set key = ##class(OcuTalon.Checks.Render).Render([(..Result("not_checked", "A", "No answer in time", ..#T1))], .rows)
	Do $$$AssertEquals(key, ..Param("KEYNOTEVERYTHING"), "one not-checked row alone is not an all-clear")
	Set key = ##class(OcuTalon.Checks.Render).Render([(..Result("passed", "A", "", ..#T1)), (..Result("not_checked", "B", "No answer in time", ..#T2))], .rows)
	Do $$$AssertTrue(key '= ..Param("KEYALLPASSED"), "a not-checked row among passed ones is never checks.allPassed")
}

Method TestNothingWatched()
{
	Set key = ##class(OcuTalon.Checks.Render).Render([], .rows)
	Do $$$AssertEquals(key, ..Param("KEYNOTHINGWATCHED"), "[] is checks.nothingWatched")
	Do $$$AssertEquals(rows.%ToJSON(), "[]", "with no row")
}

Method TestNotRunYet()
{
	Set key = ##class(OcuTalon.Checks.Render).Render([{"entry": "A", "result": "", "finding": "", "checkedAt": ""}], .rows)
	Do $$$AssertEquals(key, ..Param("KEYNOTEVERYTHING"), "an element that has not run is checks.notEverything")
	Do $$$AssertEquals(rows.%ToJSON(), [{"result": "not_checked", "entry": "A", "finding": "Not run yet", "checkedAt": ""}].%ToJSON(), "the row is not_checked with the reason Not run yet and no time")
	Do $$$AssertEquals(..Param("REASONNOTRUN"), "Not run yet", "REASONNOTRUN is Not run yet")
	Set key = ##class(OcuTalon.Checks.Render).Render([{"entry": "A"}], .rows)
	Do $$$AssertEquals(rows.%ToJSON(), [{"result": "not_checked", "entry": "A", "finding": "Not run yet", "checkedAt": ""}].%ToJSON(), "an element with the entry alone is the same row")
}

Method TestNotResults()
{
	#; Each input is JSON text, parsed for the call, so that no object lives in a list.
	Set cases = $ListBuild($ListBuild("an object", "{""entry"": ""A""}"), $ListBuild("an array with no entry", "[{""zz"": ""result""}]"), $ListBuild("scalars and a blank entry", "[1, ""x"", {""entry"": "" ""}]"), $ListBuild("entries that are no strings", "[{""entry"": 1}, {""entry"": []}, {""entry"": {}}, {""entry"": """"}, {""entry"": ""\t\n\u00a0""}]"), $ListBuild("arrays", "[[], [{""entry"": ""A""}]]"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set key = ##class(OcuTalon.Checks.Render).Render(..Parsed($List(case, 2)), .rows)
		Do $$$AssertEquals(key, "", $List(case, 1)_": the key is empty")
		Do $$$AssertEquals(rows.%ToJSON(), "[]", $List(case, 1)_": and the rows are []")
	}
	Set scalars = $ListBuild("text", 7, "")
	Set position = 0
	While $ListNext(scalars, position, scalar) {
		Set key = ##class(OcuTalon.Checks.Render).Render(scalar, .rows)
		Do $$$AssertEquals(key, "", "'"_scalar_"' is not an array: the key is empty")
		Do $$$AssertEquals(rows.%ToJSON(), "[]", "'"_scalar_"': and the rows are []")
	}
	Set key = ##class(OcuTalon.Checks.Render).Render([1, {"zz": "result"}, (..Result("passed", "A", "", ..#T1))], .rows)
	Do $$$AssertEquals(key, ..Param("KEYALLPASSED"), "elements that are no results are skipped, the others are rendered")
	Do $$$AssertEquals(rows.%Size(), 1, "one row")
}

Method TestOddValues()
{
	Set long = $Translate($Justify("", 1200), " ", "x")
	Set cut = $Extract(long, 1, 1000)
	Set t1 = ..#T1
	#; Each case is the label, the element as JSON text and the row that Render builds, as JSON text.
	Set cases = $ListBuild(
		$ListBuild("a pass with no time", {"entry": "A", "result": "passed", "finding": "kept"}.%ToJSON(), ..Row("not_checked", "A", "kept", "").%ToJSON()),
		$ListBuild("a pass with no time and no finding", {"entry": "A", "result": "passed"}.%ToJSON(), ..Row("not_checked", "A", "Not run yet", "").%ToJSON()),
		$ListBuild("a pass with a bad time", {"entry": "A", "result": "passed", "checkedAt": "yesterday"}.%ToJSON(), ..Row("not_checked", "A", "Not run yet", "").%ToJSON()),
		$ListBuild("a pass with a time that is no UTC stamp", {"entry": "A", "result": "passed", "checkedAt": "2026-10-26 14:10:00"}.%ToJSON(), ..Row("not_checked", "A", "Not run yet", "").%ToJSON()),
		$ListBuild("a failure with no time", {"entry": "A", "result": "failed", "finding": "3 new failures"}.%ToJSON(), ..Row("not_checked", "A", "3 new failures", "").%ToJSON()),
		$ListBuild("a result that is zz", {"entry": "A", "result": "zz", "finding": "f", "checkedAt": (t1)}.%ToJSON(), ..Row("not_checked", "A", "f", t1).%ToJSON()),
		$ListBuild("a result that is zz with no finding", {"entry": "A", "result": "zz", "checkedAt": (t1)}.%ToJSON(), ..Row("not_checked", "A", "", t1).%ToJSON()),
		$ListBuild("a result in upper case", {"entry": "A", "result": "PASSED", "checkedAt": (t1)}.%ToJSON(), ..Row("not_checked", "A", "", t1).%ToJSON()),
		$ListBuild("a result that is a number", {"entry": "A", "result": 1, "finding": "f", "checkedAt": (t1)}.%ToJSON(), ..Row("not_checked", "A", "f", t1).%ToJSON()),
		$ListBuild("a finding that is a number", {"entry": "A", "result": "passed", "finding": 5, "checkedAt": (t1)}.%ToJSON(), ..Row("passed", "A", "", t1).%ToJSON()),
		$ListBuild("a time that is a number", {"entry": "A", "result": "passed", "checkedAt": 5}.%ToJSON(), ..Row("not_checked", "A", "Not run yet", "").%ToJSON()),
		$ListBuild("an entry of 1,200 characters", {"entry": (long), "result": "passed", "checkedAt": (t1)}.%ToJSON(), ..Row("passed", cut, "", t1).%ToJSON()),
		$ListBuild("a finding of 1,200 characters", {"entry": "A", "result": "failed", "finding": (long), "checkedAt": (t1)}.%ToJSON(), ..Row("failed", "A", cut, t1).%ToJSON()),
		$ListBuild("an entry with white space around it is kept as it is", {"entry": " A ", "result": "passed", "checkedAt": (t1)}.%ToJSON(), ..Row("passed", " A ", "", t1).%ToJSON()),
		$ListBuild("members of no use", {"entry": "A", "result": "passed", "checkedAt": (t1), "extra": "zz"}.%ToJSON(), ..Row("passed", "A", "", t1).%ToJSON()))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set key = ##class(OcuTalon.Checks.Render).Render([(..Parsed($List(case, 2)))], .rows)
		Do $$$AssertEquals(rows.%Size(), 1, $List(case, 1)_": one row")
		If rows.%Size() = 1 Do $$$AssertEquals(rows.%Get(0).%ToJSON(), $List(case, 3), $List(case, 1))
		Do $$$AssertTrue(key '= "", $List(case, 1)_": there is a key")
	}
	Do $$$AssertEquals($Length(cut), 1000, "the cut is 1000 characters")
}

Method TestRowsShape()
{
	Set inputs = $ListBuild("[]", "[{""entry"": ""A"", ""result"": ""passed"", ""checkedAt"": ""2026-10-26T14:10:00Z""}]", "[{""entry"": ""A""}]", "[1]", "{}")
	Set position = 0
	While $ListNext(inputs, position, input) {
		Set key = ##class(OcuTalon.Checks.Render).Render(..Parsed(input), .rows)
		Do $$$AssertTrue($IsObject(rows) && rows.%IsA("%Library.DynamicArray"), input_": rows is an array")
		Set iterator = rows.%GetIterator()
		While iterator.%GetNext(, .row) {
			Set keys = ""
			Set members = row.%GetIterator()
			While members.%GetNext(.member, .value) {
				Set keys = keys_$Select(keys = "": "", 1: ",")_member
				Do $$$AssertEquals(row.%GetTypeOf(member), "string", member_" is a string")
			}
			Do $$$AssertEquals(keys, "result,entry,finding,checkedAt", "a row has exactly the four keys, in order")
		}
	}
	Set key = ##class(OcuTalon.Checks.Render).Render("x", .rows)
	Do $$$AssertTrue($IsObject(rows) && rows.%IsA("%Library.DynamicArray"), "rows is an array also for a scalar")
}

Method TestKeysAreCatalogKeys()
{
	For name = "KEYALLPASSED", "KEYRESTPASSED", "KEYNOTEVERYTHING", "KEYNOTHINGWATCHED" {
		Set key = ..Param(name)
		Set text = ##class(OcuTalon.Msg.Catalog).Render(key, {"whatFailed": "A"}, "web", .sc)
		Do $$$AssertStatusOK(sc, name_" ("_key_") renders through Msg.Catalog")
		Do $$$AssertTrue(text '= "", name_" has a text")
	}
	Do $$$AssertEquals(..Param("KEYALLPASSED")_"|"_..Param("KEYRESTPASSED")_"|"_..Param("KEYNOTEVERYTHING")_"|"_..Param("KEYNOTHINGWATCHED"), "checks.allPassed|checks.notEverythingRestPassed|checks.notEverything|checks.nothingWatched", "and they are the four keys of the spec")
}

/// --- helpers ---
ClassMethod Param(name As %String) As %String [ Private ]
{
	Quit $Parameter(..#RENDER, name)
}

/// The JSON text as a dynamic object or array.
ClassMethod Parsed(text As %String) As %DynamicAbstractObject [ Private ]
{
	Quit {}.%FromJSON(text)
}

/// A result element as the tool copies it: {"result", "entry", "finding", "checkedAt"}.
ClassMethod Result(result As %String, entry As %String, finding As %String, checkedAt As %String) As %DynamicObject [ Private ]
{
	Quit {"result": (result), "entry": (entry), "finding": (finding), "checkedAt": (checkedAt)}
}

/// A row as Render builds it (the same four members).
ClassMethod Row(result As %String, entry As %String, finding As %String, checkedAt As %String) As %DynamicObject [ Private ]
{
	Quit {"result": (result), "entry": (entry), "finding": (finding), "checkedAt": (checkedAt)}
}

/// The entries of the rows, comma-separated, in order.
ClassMethod Entries(rows As %DynamicArray) As %String [ Private ]
{
	Set list = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		Set list = list_$Select(list = "": "", 1: ",")_row.entry
	}
	Quit list
}

}
