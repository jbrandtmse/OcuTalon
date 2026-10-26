/// Tests of the transition table of an incident (Story 5.5; AD-15) and of the quiet-time rule that closeQuiet uses. The class is pure: it calls
/// OcuTalon.Watch.Transitions.Next and OcuTalon.Watch.Settle.Quiet and nothing else, so it runs warm.
///   - TestRows: every row of the table, each at every combination of the facts pending, waiting and demoMode (and at the variants a notice may carry), gives
///     its target state, open variant and execute choice;
///   - TestRefusedMoves: every pair of state (none, open not noticed, open noticed, awaiting_approval, fixing, resolved, closed) and event, at every combination
///     of the facts, is refused unless a row accepts it, and a refused move gives no target, variant or execute;
///   - TestQuiet: Settle.Quiet is 0 at 899 and 900 seconds, 1 at 901, and 0 for a time it cannot read.
/// The rows are in Rows, one place, so that the two table tests read the same rows: each is a list of the state, whether the incident is noticed ("*" for either),
/// the event, the condition on the facts (space-separated tokens p0 p1 w0 w1 d0 d1, and v for a variant of a notice), and the expected target, variant
/// ("<v>" for the variant given) and execute choice.
Class OcuTalon.Test.Watch.Transitions Extends %UnitTest.TestCase
{

Method TestRows()
{
	Set rows = ..Rows()
	Set position = 0
	While $ListNext(rows, position, row) {
		Set state = $List(row, 1)
		Set event = $List(row, 3)
		For noticed = 0, 1 {
			If ($List(row, 2) '= "*") && ($List(row, 2) '= noticed) Continue
			For variant = "", "fallback", "no_fix", "rejected" {
				For pending = 0, 1 {
					For waiting = 0, 1 {
						For demo = 0, 1 {
							If '..Holds($List(row, 4), variant, pending, waiting, demo) Continue
							Set facts = {"variant": (variant), "pending": (pending), "waiting": (waiting), "demoMode": (demo)}
							Set accepted = ##class(OcuTalon.Watch.Transitions).Next(state, noticed, event, facts, .to, .kept, .execute)
							Set expected = $List(row, 5)_"|"_$Select($List(row, 6) = "<v>": variant, 1: $List(row, 6))_"|"_$List(row, 7)
							Do $$$AssertEquals(accepted_"|"_to_"|"_kept_"|"_execute, "1|"_expected, "'"_state_"' (noticed "_noticed_") + "_event_" at "_..Describe(variant, pending, waiting, demo)_" gives "_expected)
						}
					}
				}
			}
		}
	}
}

Method TestRefusedMoves()
{
	Set rows = ..Rows()
	Set states = $ListBuild("|0", "open|0", "open|1", "awaiting_approval|0", "fixing|0", "resolved|0", "closed|0", "closed|1", "awaiting_approval|1", "fixing|1", "resolved|1")
	Set events = $ListFromString(##class(OcuTalon.Watch.Transitions).#EVENTS)
	Do $$$AssertEquals($ListLength(events), 11, "the table knows eleven events")
	Set checked = 0
	Set refused = 0
	Set sPosition = 0
	While $ListNext(states, sPosition, pair) {
		Set state = $Piece(pair, "|", 1)
		Set noticed = $Piece(pair, "|", 2)
		Set ePosition = 0
		While $ListNext(events, ePosition, event) {
			For variant = "", "fallback", "no_fix", "rejected" {
				For pending = 0, 1 {
					For waiting = 0, 1 {
						For demo = 0, 1 {
							Set facts = {"variant": (variant), "pending": (pending), "waiting": (waiting), "demoMode": (demo)}
							Set accepted = ##class(OcuTalon.Watch.Transitions).Next(state, noticed, event, facts, .to, .kept, .execute)
							Set listed = ..Listed(rows, state, noticed, event, variant, pending, waiting, demo)
							Set checked = checked + 1
							If listed {
								If 'accepted Do $$$AssertTrue(0, "'"_state_"' (noticed "_noticed_") + "_event_" at "_..Describe(variant, pending, waiting, demo)_" is a row but was refused")
								Continue
							}
							Set refused = refused + 1
							If accepted || (to_kept_execute '= "") {
								Do $$$AssertTrue(0, "'"_state_"' (noticed "_noticed_") + "_event_" at "_..Describe(variant, pending, waiting, demo)_" is no row but gave "_accepted_"|"_to_"|"_kept_"|"_execute)
							}
						}
					}
				}
			}
		}
	}
	Do $$$AssertTrue(checked > 1000, "every pair was tried at every combination of the facts: "_checked)
	Do $$$AssertTrue(refused > 0, "and some are refused: "_refused)
	Do $$$AssertEquals(##class(OcuTalon.Watch.Transitions).Next("closed", 1, "dismiss", "", .to), 0, "an event on a closed incident is refused (without facts too)")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Transitions).Next("awaiting_approval", 1, "dismiss", {"pending": 0}, .to), 0, "dismiss while awaiting_approval is refused")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Transitions).Next("fixing", 1, "dismiss", {"pending": 0}, .to), 0, "dismiss while fixing is refused")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Transitions).Next("open", 0, "dismiss", {}, .to), 0, "dismiss of an unnoticed open incident is refused")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Transitions).Next("open", 0, "notice", {"variant": "rejected"}, .to), 0, "a notice with another variant is refused")
}

Method TestQuiet()
{
	Set now = "2030-01-01T10:15:00Z"
	Do $$$AssertEquals(##class(OcuTalon.Watch.Settle).Quiet("2030-01-01T10:00:01Z", now, 900), 0, "899 seconds is not quiet")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Settle).Quiet("2030-01-01T10:00:00Z", now, 900), 0, "900 seconds is not quiet: more than the seconds is needed")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Settle).Quiet("2030-01-01T09:59:59Z", now, 900), 1, "901 seconds is quiet")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Settle).Quiet("2030-01-01T10:30:00Z", now, 900), 0, "a failure in the future is not quiet")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Settle).Quiet("", now, 900), 0, "an empty time is not quiet")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Settle).Quiet("yesterday", now, 900), 0, "an unreadable last time is not quiet")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Settle).Quiet("2030-01-01T09:00:00Z", "", 900), 0, "an empty now is not quiet")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Settle).Quiet("2030-01-01T09:00:00Z", "soon", 900), 0, "an unreadable now is not quiet")
}

/// --- helpers ---
/// The rows of the table: $ListBuild(state, noticed, event, condition, target, variant, execute); see the class description for the condition.
ClassMethod Rows() As %List [ Private ]
{
	Quit $ListBuild(
		$ListBuild("", "*", "first", "", "open", "", ""),
		$ListBuild("open", 0, "notice", "v", "open", "<v>", ""),
		$ListBuild("open", 0, "raised", "", "awaiting_approval", "", ""),
		$ListBuild("awaiting_approval", "*", "approved", "", "fixing", "", "own"),
		$ListBuild("awaiting_approval", "*", "rejected", "p0", "open", "rejected", ""),
		$ListBuild("awaiting_approval", "*", "rejected", "p1", "awaiting_approval", "", ""),
		$ListBuild("awaiting_approval", "*", "expired", "p0", "open", "expired", ""),
		$ListBuild("awaiting_approval", "*", "expired", "p1", "awaiting_approval", "", ""),
		$ListBuild("fixing", "*", "progress", "", "fixing", "", ""),
		$ListBuild("fixing", "*", "finished", "w1", "fixing", "", "earliest"),
		$ListBuild("fixing", "*", "finished", "w0 p1", "awaiting_approval", "", ""),
		$ListBuild("fixing", "*", "finished", "w0 p0", "resolved", "", ""),
		$ListBuild("fixing", "*", "approved", "", "fixing", "", ""),
		$ListBuild("fixing", "*", "rejected", "", "fixing", "", ""),
		$ListBuild("fixing", "*", "expired", "", "fixing", "", ""),
		$ListBuild("awaiting_approval", "*", "raised", "", "awaiting_approval", "", ""),
		$ListBuild("resolved", "*", "raised", "", "awaiting_approval", "", ""),
		$ListBuild("fixing", "*", "raised", "", "fixing", "", ""),
		$ListBuild("resolved", "*", "dismiss", "", "closed", "", ""),
		$ListBuild("resolved", "*", "closeForReplay", "", "closed", "", ""),
		$ListBuild("resolved", "*", "closeQuiet", "", "closed", "", ""),
		$ListBuild("open", 1, "dismiss", "", "closed", "", ""),
		$ListBuild("open", 1, "closeQuiet", "d0", "closed", "", ""))
}

/// 1 when the condition holds at the facts: p0, p1, w0, w1, d0 and d1 are the facts, v means that the variant of the notice is fallback or no_fix.
ClassMethod Holds(condition As %String, variant As %String, pending As %Boolean, waiting As %Boolean, demo As %Boolean) As %Boolean [ Private ]
{
	For i = 1:1:$Length(condition, " ") {
		Set token = $Piece(condition, " ", i)
		If token = "" Continue
		If token = "v" {
			If (variant '= "fallback") && (variant '= "no_fix") Return 0
		} Else {
			Set fact = $Case($Extract(token, 1), "p": pending, "w": waiting, "d": demo, : "")
			If fact '= $Extract(token, 2) Return 0
		}
	}
	Quit 1
}

/// 1 when a row accepts the state, noticed flag, event and facts.
ClassMethod Listed(rows As %List, state As %String, noticed As %Boolean, event As %String, variant As %String, pending As %Boolean, waiting As %Boolean, demo As %Boolean) As %Boolean [ Private ]
{
	Set found = 0
	Set position = 0
	While $ListNext(rows, position, row) {
		If ($List(row, 1) '= state) || ($List(row, 3) '= event) Continue
		If (state = "open") && ($List(row, 2) '= noticed) Continue
		If ..Holds($List(row, 4), variant, pending, waiting, demo) {
			Set found = 1
			Quit
		}
	}
	Quit found
}

/// The facts as text, for the label of an assertion.
ClassMethod Describe(variant As %String, pending As %Boolean, waiting As %Boolean, demo As %Boolean) As %String [ Private ]
{
	Quit "variant '"_variant_"', pending "_pending_", waiting "_waiting_", demoMode "_demo
}

}
