/// Renders the results of the background checks for a reply (AD-28): the one place that chooses the reserved sentence about them. It is a
/// pure function: it reads no table and no context, writes nothing, and never throws for any JSON value.
///   - The input is a %DynamicArray. When results is not one, the key is "" and rows is []. An empty array is nothing watched: KEYNOTHINGWATCHED
///     and [].
///   - An element is a result only when it is an object whose entry is a string that is not blank. Other elements are skipped, so a non-empty
///     array with no result gives "" and [].
///   - A result becomes the row {"result", "entry", "finding", "checkedAt"}. checkedAt is the element's own when it is a UTC stamp
///     (YYYY-MM-DDThh:mm:ssZ), else "". result is passed or failed only when the element says exactly that and checkedAt is set, else not_checked
///     (a pass needs a time). finding is the element's string, else ""; a not_checked row with no finding and no checkedAt gets REASONNOTRUN.
///     entry and finding are cut to LIMIT characters, the limit of Live.Payload.Part.CheckRow.
///   - The rows are ordered failed, then not_checked, then passed, each group in input order.
///   - The key is KEYALLPASSED when every row passed, else KEYRESTPASSED when at least one row passed, else KEYNOTEVERYTHING. The catalog sentence
///     of the key says whether everything passed, so only this method can make an all-clear (the model's words are filtered by ReplyGuard).
Class OcuTalon.Checks.Render
{

/// The catalog key when every row passed.
Parameter KEYALLPASSED = "checks.allPassed";

/// The catalog key when something did not pass and at least one row passed.
Parameter KEYRESTPASSED = "checks.notEverythingRestPassed";

/// The catalog key when something did not pass and no row passed.
Parameter KEYNOTEVERYTHING = "checks.notEverything";

/// The catalog key when nothing is watched.
Parameter KEYNOTHINGWATCHED = "checks.nothingWatched";

/// The reason of a row that has not run yet and has no finding.
Parameter REASONNOTRUN = "Not run yet";

/// The longest entry and finding of a row, in characters.
Parameter LIMIT = 1000;

/// The catalog key that renders the check results, with the rows to show in rows (see the class description).
ClassMethod Render(results As %DynamicArray, Output rows As %DynamicArray) As %String
{
	Set rows = []
	Set key = ""
	Try {
		Set key = ..Build($Get(results), .built)
		Set rows = built
	} Catch exception {
		Set rows = []
		Set key = ""
	}
	Quit key
}

/// The key and the ordered rows of the results (see the class description).
ClassMethod Build(results, Output rows As %DynamicArray) As %String [ Private ]
{
	Set rows = []
	If '$IsObject(results) || 'results.%IsA("%Library.DynamicArray") Quit ""
	If results.%Size() = 0 Quit ..#KEYNOTHINGWATCHED
	Set failed = [], notChecked = [], passed = []
	Set iterator = results.%GetIterator()
	While iterator.%GetNext(, .element) {
		Set row = ..Row(element)
		If row = "" Continue
		If row.result = "failed" {
			Do failed.%Push(row)
		} ElseIf row.result = "passed" {
			Do passed.%Push(row)
		} Else {
			Do notChecked.%Push(row)
		}
	}
	For order = 1:1:3 {
		Set group = $Case(order, 1: failed, 2: notChecked, : passed)
		Set iterator = group.%GetIterator()
		While iterator.%GetNext(, .row) {
			Do rows.%Push(row)
		}
	}
	If rows.%Size() = 0 Quit ""
	If (failed.%Size() = 0) && (notChecked.%Size() = 0) Quit ..#KEYALLPASSED
	Quit $Select(passed.%Size() > 0: ..#KEYRESTPASSED, 1: ..#KEYNOTEVERYTHING)
}

/// The row of an element, or "" when the element is no result.
ClassMethod Row(element) As %DynamicObject [ Private ]
{
	If '$IsObject(element) || 'element.%IsA("%Library.DynamicObject") Quit ""
	If element.%GetTypeOf("entry") '= "string" Quit ""
	Set entry = element.entry
	If $ZStrip($Translate(entry, $Char(160), " "), "<>WC") = "" Quit ""
	Set checkedAt = $Select(element.%GetTypeOf("checkedAt") = "string": element.checkedAt, 1: "")
	If checkedAt '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" Set checkedAt = ""
	Set result = $Select(element.%GetTypeOf("result") = "string": element.result, 1: "")
	If '((result = "passed") || (result = "failed")) || (checkedAt = "") Set result = "not_checked"
	Set finding = $Select(element.%GetTypeOf("finding") = "string": element.finding, 1: "")
	If (result = "not_checked") && (finding = "") && (checkedAt = "") Set finding = ..#REASONNOTRUN
	Quit {"result": (result), "entry": ($Extract(entry, 1, ..#LIMIT)), "finding": ($Extract(finding, 1, ..#LIMIT)), "checkedAt": (checkedAt)}
}

}
