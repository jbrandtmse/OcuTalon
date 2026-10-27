/// Tests of the reply guard, OcuTalon.Checks.ReplyGuard (Story 5.7; AD-28, AD-31). The tests need no production, and run warm.
///   - TestReservedSentences and TestBannedPhrases: the two lists equal their sources. RESERVED holds the catalog texts of checks.allPassed and
///     checks.everythingElsePassed without their periods, and "Your IRIS system is healthy"; BANNED is the closed list of EXPERIENCE.md, as written here;
///   - TestVariants (matrix "Guard removes"): each phrase of both lists is removed in lower, upper and mixed case, with U+2019 for an apostrophe, with two
///     spaces or a no-break space between its words, and followed by a full stop, an exclamation mark, a comma or nothing;
///   - TestKeepsTheRest (matrix "Guard keeps"): a phrase inside a longer word, a text that has no match, with double spaces, tabs and CRLF, comes back
///     byte for byte;
///   - TestLines (matrix "Guard lines"): the text is filtered line by line, the tidy runs only in a line that had a match, a CR before an LF stays with the
///     line break, and an emptied line goes with its break;
///   - TestEmptied: a text that the guard empties is "" (for a turn, Decide's existing fallback invalid);
///   - TestFailsClosed: a guard that fails inside Filter returns "";
///   - TestThroughConclude (AC 5): Decide.Conclude with the guard as its filter class removes the phrase from a turn's text, and from the reasons of a decide
///     reply, where a reason that the guard empties is left out; the test removes its Decision rows.
Class OcuTalon.Test.Checks.Guard Extends %UnitTest.TestCase
{

Parameter GUARD = "OcuTalon.Checks.ReplyGuard";

/// EXPERIENCE.md's closed list of phrases that model text never says, as it is written there (Voice and Tone).
Parameter UXBANNED = "all good,everything's fine,everything is fine,no issues,no problems,nothing to worry about";

Property ItemIds As %List;

Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Quit $$$OK
}

Method TestReservedSentences()
{
	Set all = ##class(OcuTalon.Msg.Catalog).Render("checks.allPassed", "", "web", .sc)
	Do $$$AssertStatusOK(sc, "the catalog renders checks.allPassed")
	Set rest = ##class(OcuTalon.Msg.Catalog).Render("checks.everythingElsePassed", "", "web", .sc)
	Do $$$AssertStatusOK(sc, "the catalog renders checks.everythingElsePassed")
	Do $$$AssertEquals(all, "Everything I checked passed.", "the sentence of checks.allPassed")
	Do $$$AssertEquals(rest, "Everything else I checked passed.", "the sentence of checks.everythingElsePassed")
	Set expected = $Piece(all, ".", 1)_","_$Piece(rest, ".", 1)_",Your IRIS system is healthy"
	Do $$$AssertEquals($Parameter(..#GUARD, "RESERVED"), expected, "RESERVED holds the two catalog sentences without their periods, and the sentence about the system's health")
}

Method TestBannedPhrases()
{
	Do $$$AssertEquals($Parameter(..#GUARD, "BANNED"), ..#UXBANNED, "BANNED is the closed list of EXPERIENCE.md")
	Do $$$AssertEquals($Length(..#UXBANNED, ","), 6, "of six phrases")
	Do $$$AssertEquals($Parameter(..#GUARD, "PUNCTUATION"), ".!?,;:", "and the punctuation that goes with a phrase is . ! ? , ; :")
}

Method TestVariants()
{
	Set apostrophe = $Char(8217)
	Set nbsp = $Char(160)
	Set phrases = $ListFromString($Parameter(..#GUARD, "RESERVED")_","_$Parameter(..#GUARD, "BANNED"))
	Do $$$AssertEquals($ListLength(phrases), 9, "nine phrases in all")
	Set position = 0
	While $ListNext(phrases, position, phrase) {
		Set forms = $ListBuild(phrase, $ZConvert(phrase, "U"), $ZConvert($Extract(phrase, 1), "U")_$Extract(phrase, 2, $Length(phrase)), $ZConvert(phrase, "L"), $Replace(phrase, "'", apostrophe), $Replace(phrase, " ", "  "), $Replace(phrase, " ", nbsp), $Replace(phrase, " ", $Char(9)), $Replace($Replace(phrase, "'", apostrophe), " ", nbsp_" "))
		Set marks = $ListBuild("", ".", "!", ",", "?", ";", ":", "...", "!?")
		Set at = 0
		While $ListNext(forms, at, form) {
			Set next = 0
			While $ListNext(marks, next, mark) {
				Set label = "'"_phrase_"' as form "_$ListFind(forms, form)_" followed by '"_mark_"'"
				Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("Intro. "_form_mark_" The Orders production is running."), "Intro. The Orders production is running.", label_": removed in the middle of a line")
				Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter(form_mark_" The Orders production is running."), "The Orders production is running.", label_": removed at the start")
				Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("I looked at Orders. "_form_mark), "I looked at Orders.", label_": removed at the end")
			}
		}
	}
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("All good! The Orders production is running."), "The Orders production is running.", "the matrix row: All good!")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("Everything"_apostrophe_"s fine, nothing to worry about. I looked at Orders."), "I looked at Orders.", "the matrix row: Everything(U+2019)s fine, nothing to worry about.")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("Everything I checked passed. Everything else I checked passed. Your IRIS system is healthy. See Orders."), "See Orders.", "the reserved sentences, one after the other")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("All good all good, no issues."), "", "the same phrase twice and another: all removed")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("Orders is (all good) today."), "Orders is () today.", "a phrase between brackets: only the phrase goes")
}

Method TestKeepsTheRest()
{
	Set texts = $ListBuild(
		"Overall good progress.",
		"no issuesX",
		"Xno issues",
		"no issues42",
		"all goodness",
		"all-good",
		"Nothing failed.",
		"Everything I checked passed" _ "ly.",
		"Not everything is fine" _ "x",
		"everything  is" _ $Char(10) _ "fine",
		"A  text with  double spaces and a tab" _ $Char(9) _ "here.",
		"CRLF" _ $Char(13, 10) _ "lines" _ $Char(13, 10) _ "stay  as they are." _ $Char(13, 10),
		"  leading and trailing white space  ",
		$Char(10) _ "blank lines" _ $Char(10, 10),
		"",
		" ",
		"Nothing to worry",
		"The Orders production has no problem.")
	Set position = 0
	While $ListNext(texts, position, text) {
		Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter(text), text, "kept byte for byte: '"_$Translate(text, $Char(9, 10, 13, 160), "TLRN")_"'")
	}
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("Keep  this" _ $Char(13, 10) _ "and  this." _ $Char(13, 10) _ "No issues." _ $Char(13, 10) _ "And  this  too."), "Keep  this" _ $Char(13, 10) _ "and  this." _ $Char(13, 10) _ "And  this  too.", "lines without a match keep their double spaces and CRLF, also beside a line that had one")
}

Method TestLines()
{
	Set lf = $Char(10)
	Set cr = $Char(13)
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("Line one." _ lf _ lf _ "All good." _ lf _ "Line three."), "Line one." _ lf _ lf _ "Line three.", "an emptied line goes with its break, a blank line stays")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("Everything I checked passed."), "", "a text that is one reserved sentence is empty")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("Line one." _ cr _ lf _ "All good." _ cr _ lf _ "Line three."), "Line one." _ cr _ lf _ "Line three.", "a CR before an LF stays with the break, and goes with the emptied line")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("Keep  spaces." _ lf _ "All good!  Done   here." _ lf), "Keep  spaces." _ lf _ "Done here." _ lf, "the tidy runs in the line that had a match only")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("a" _ $Char(9) _ "b all good c" _ $Char(9, 9) _ "d"), "a b c d", "runs of spaces and tabs become one space in a line that had a match")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("  All good. Next  "), "Next", "and the line is trimmed")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("Hi." _ lf _ "All good."), "Hi." _ lf, "an emptied last line has no break of its own, so the break before it stays")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("All good." _ lf _ "Hi."), "Hi.", "an emptied first line goes with its break")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("No issues." _ lf _ "No problems." _ lf), "", "every line emptied")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("One. Two" _ lf _ "all" _ lf _ "good" _ lf), "One. Two" _ lf _ "all" _ lf _ "good" _ lf, "a phrase split over two lines is not one")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("Orders: no issues, no problems; all good!" _ lf _ "Done."), "Orders:" _ lf _ "Done.", "punctuation after a phrase goes, the text before it stays")
}

Method TestEmptied()
{
	Set lf = $Char(10)
	Set texts = $ListBuild("All good.", "  Everything I checked passed!  ", "All good." _ lf _ "No issues." _ lf, "all good no issues, no problems.", "Your IRIS system is healthy.", "NOTHING TO WORRY ABOUT!!!")
	Set position = 0
	While $ListNext(texts, position, text) {
		Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter(text), "", "emptied: '"_$Translate(text, lf, "L")_"'")
	}
	Set blank = lf _ "All good." _ lf _ lf
	Do $$$AssertEquals($ZStrip(##class(OcuTalon.Checks.ReplyGuard).Filter(blank), "*WC"), "", "a text of blank lines around a phrase is left with blank lines only")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("All good."), "", "an emptied text is exactly empty, so that Decide falls back with invalid")
}

Method TestFailsClosed()
{
	Do $$$AssertEquals(##class(OcuTalon.Test.Checks.BrokenGuard).Filter("Hello there."), "", "a guard that fails returns an empty text, never the unfiltered one")
	Do $$$AssertEquals(##class(OcuTalon.Test.Checks.BrokenGuard).Filter(""), "", "also for an empty text")
	Do $$$AssertEquals(##class(OcuTalon.Checks.ReplyGuard).Filter("Hello there."), "Hello there.", "while the real guard keeps it")
}

Method TestThroughConclude()
{
	Set filter = "OcuTalon.Checks.ReplyGuard"
	Set turn = ..NewRequest("turn", "user")
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = "All good. I looked at Orders."
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Conclude(turn, ##class(OcuTalon.Bridge.Ids).NewRef(), reply, "OcuTalon.Bridge.Msg.DecisionPayload", filter, "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
	Do $$$AssertStatusOK(sc, "Conclude answers a turn")
	Do $$$AssertEquals(response.Text, "I looked at Orders.", "the text of the turn is filtered once, and the rest is kept")
	Do $$$AssertEquals(response.Fallback, 0, "and it is no fallback")

	Set emptied = ..NewRequest("turn", "user")
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = "Everything I checked passed."
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Conclude(emptied, ##class(OcuTalon.Bridge.Ids).NewRef(), reply, "OcuTalon.Bridge.Msg.DecisionPayload", filter, "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
	Do $$$AssertStatusOK(sc, "Conclude answers a turn that the guard empties")
	Do $$$AssertEquals(response.Fallback_"|"_response.FallbackReason_"|"_response.Text, "1|invalid|", "it is Decide's fallback invalid, with no text")

	Set decide = ..NewRequest("decide", "untrusted")
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = {"outcome": "digest", "reasons": ["No issues.", "The partner changed its date format."], "confidence": 0.5}.%ToJSON()
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Conclude(decide, ##class(OcuTalon.Bridge.Ids).NewRef(), reply, "OcuTalon.Bridge.Msg.DecisionPayload", filter, "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
	Do $$$AssertStatusOK(sc, "Conclude answers a decide reply")
	Do $$$AssertEquals(response.Reasons, "The partner changed its date format.", "a reason that the guard empties is left out, and only the second reason line is kept")
	Do $$$AssertEquals(response.Fallback_"|"_response.Outcome, "0|digest", "and it is no fallback")
}

/// --- helpers ---
/// A request of the kind and provenance with an ItemId of its own, whose Decision rows OnAfterOneTest deletes.
Method NewRequest(kind As %String, provenance As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = provenance
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = "instance"
	Set request.Summary = "Test "_request.ItemId
	Set request.Input = "Triage this item."
	Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
	Quit request
}

}
