/// Tests of the pure class of Story 5.3's settle rule, OcuTalon.Watch.Settle, and of the key rule Mark.KeyOf that IncidentManager shares with the poller
/// (AD-5, AD-15, AD-19). They need no production and no namespace, so they run anywhere, a slot included.
///   - TestPattern: each run of digits is one #, each run of white space one space and the ends are trimmed, so two dates of the measured sentence are one
///     pattern while another item's words, other words and a different case are not; an empty or undefined text is empty;
///   - TestWait: the burst edge (the quiet time ends the rule), the trickle edge (the maximum ends it), a maximum below the quiet time, a failure time after now,
///     the second before an end (at least 1), and stamps that are not stamps (the rule has ended);
///   - TestHold: the keys that the set holds are not new, a key twice in one batch is new once, the order is oldest first, and the set is cut to its newest
///     1000 keys while the new keys are all given;
///   - TestValues: the settings (given only in the process's own cache of Data.Setting, which the test puts back, so that no setting row is written and no
///     production job can read them) give 4 and 12, and the defaults 10 and 30 when they are absent, 0, not a number, negative or fractional;
///   - TestKeyOf: h<header id> for a header failure, l<log id> for any other, and Key of the reader's row gives the same.
Class OcuTalon.Test.Watch.Settle Extends %UnitTest.TestCase
{

Parameter SETTLE = "OcuTalon.Watch.Settle";

Parameter MARK = "OcuTalon.Watch.Mark";

/// The process's cached entries of the two settings before a test changed them: "" for none, else the cache node.
Property SavedQuiet As %String(MAXLEN = "");

Property SavedMax As %String(MAXLEN = "");

Property Saved As %Boolean [ InitialExpression = 0 ];

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..PutBack()
	Quit $$$OK
}

/// The stamp of the second that is seconds after 2026-10-25T08:00:00Z.
ClassMethod At(seconds As %Integer) As %String
{
	Quit ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift("2026-10-25 08:00:00.000", seconds))
}

Method TestPattern()
{
	Set one = "The order date was not in the expected format. Expected YYYY-MM-DD, got '10/16/2026'."
	Set two = "The order date was not in the expected format. Expected YYYY-MM-DD, got '10/17/2026'."
	Set masked = "The order date was not in the expected format. Expected YYYY-MM-DD, got '#/#/#'."
	Do $$$AssertEquals($ClassMethod(..#SETTLE, "Pattern", one), masked, "each run of digits of the measured sentence is one #")
	Do $$$AssertEquals($ClassMethod(..#SETTLE, "Pattern", one), $ClassMethod(..#SETTLE, "Pattern", two), "two dates are one pattern")
	Do $$$AssertEquals($ClassMethod(..#SETTLE, "Pattern", "order 7 of 120 failed, id 0042"), "order # of # failed, id #", "ids and counts of any length are masked")
	Do $$$AssertEquals($ClassMethod(..#SETTLE, "Pattern", "a1b22c333"), "a#b#c#", "a run of digits inside a word is masked")
	Do $$$AssertEquals($ClassMethod(..#SETTLE, "Pattern", "  a  b"_$Char(9)_"c"_$Char(13, 10)_"d  "), "a b c d", "each run of white space is one space and the ends are trimmed")
	Do $$$AssertEquals($ClassMethod(..#SETTLE, "Pattern", "Field 'Qty' is missing"), "Field 'Qty' is missing", "words are kept")
	Do $$$AssertTrue($ClassMethod(..#SETTLE, "Pattern", "Field 'Qty' is missing") '= $ClassMethod(..#SETTLE, "Pattern", "Field 'Sku' is missing"), "another name is another pattern")
	Do $$$AssertTrue($ClassMethod(..#SETTLE, "Pattern", "Field 'Qty' is missing") '= $ClassMethod(..#SETTLE, "Pattern", "field 'qty' is missing"), "and so is another case: the pattern is compared exactly")
	Do $$$AssertEquals($ClassMethod(..#SETTLE, "Pattern", ""), "", "an empty text gives an empty pattern")
	Do $$$AssertEquals($ClassMethod(..#SETTLE, "Pattern", "   "), "", "so does white space")
	Do $$$AssertEquals($ClassMethod(..#SETTLE, "Pattern", "123"), "#", "and a number is one #")
}

Method TestWait()
{
	Set settle = ..#SETTLE
	Do $$$AssertEquals($ClassMethod(settle, "Wait", ..At(0), ..At(3), ..At(5), 10, 30), 8, "burst: the failures stopped at +3, so the quiet time ends the rule at +13 and 8 seconds are left at +5")
	Do $$$AssertEquals($ClassMethod(settle, "Wait", ..At(0), ..At(3), ..At(13), 10, 30), 0, "the rule ends when the last failure is the quiet time ago")
	Do $$$AssertEquals($ClassMethod(settle, "Wait", ..At(0), ..At(3), ..At(40), 10, 30), 0, "and stays ended")
	Do $$$AssertEquals($ClassMethod(settle, "Wait", ..At(0), ..At(3), ..At(12), 10, 30), 1, "one second before the end it is 1")
	Do $$$AssertEquals($ClassMethod(settle, "Wait", ..At(0), ..At(26), ..At(27), 10, 30), 3, "trickle: the last failure keeps moving the quiet end past the maximum, so the maximum ends the rule at +30")
	Do $$$AssertEquals($ClassMethod(settle, "Wait", ..At(0), ..At(26), ..At(30), 10, 30), 0, "the rule ends at the maximum after the first failure")
	Do $$$AssertEquals($ClassMethod(settle, "Wait", ..At(0), ..At(0), ..At(2), 10, 5), 3, "a maximum below the quiet time ends the rule at the maximum")
	Do $$$AssertEquals($ClassMethod(settle, "Wait", ..At(0), ..At(0), ..At(5), 10, 5), 0, "and no later")
	Do $$$AssertEquals($ClassMethod(settle, "Wait", ..At(0), ..At(20), ..At(1), 10, 30), 29, "a failure time after now (a clock that differs) is held to the maximum: 29 seconds at +1")
	Do $$$AssertEquals($ClassMethod(settle, "Wait", ..At(0), ..At(0), ..At(0), 4, 12), 4, "with 4 and 12 the quiet time is 4 seconds at once")
	Do $$$AssertEquals($ClassMethod(settle, "Wait", ..At(86390), ..At(86395), ..At(86396), 10, 30), 9, "a day boundary does not matter")
	Do $$$AssertEquals($ClassMethod(settle, "Wait", "", ..At(0), ..At(0), 10, 30), 0, "a first time that is no stamp ends the rule")
	Do $$$AssertEquals($ClassMethod(settle, "Wait", ..At(0), "2026-10-25 08:00:00", ..At(0), 10, 30), 0, "so does a last time that is not a stamp")
	Do $$$AssertEquals($ClassMethod(settle, "Wait", ..At(0), ..At(0), "x", 10, 30), 0, "and a now")
	Do $$$AssertEquals($ClassMethod(settle, "Wait", ..At(0), "2026-13-45T25:61:61Z", ..At(0), 10, 30), 0, "and so does a stamp of the right shape that is no date or time")
}

Method TestHold()
{
	Set settle = ..#SETTLE
	Set seen = $ClassMethod(settle, "Hold", "", "h1,h2,l3", .fresh)
	Do $$$AssertEquals(seen_"|"_fresh, "h1,h2,l3|h1,h2,l3", "an empty set takes every key, in order")
	Set seen = $ClassMethod(settle, "Hold", "h1,h2", "h2,h3,h3,l1", .fresh)
	Do $$$AssertEquals(seen_"|"_fresh, "h1,h2,h3,l1|h3,l1", "a held key is ignored, a key twice is new once, and a header and a log row of one number differ")
	Set seen = $ClassMethod(settle, "Hold", "h1,h2", "h2,h1", .fresh)
	Do $$$AssertEquals(seen_"|"_fresh, "h1,h2|", "a batch of held keys adds nothing")
	Set seen = $ClassMethod(settle, "Hold", "h1,h2", "", .fresh)
	Do $$$AssertEquals(seen_"|"_fresh, "h1,h2|", "and so does an empty batch")
	Set keys = ""
	For i = 1:1:1500 {
		Set keys = keys_$Select(keys = "": "", 1: ",")_"h"_i
	}
	Set seen = $ClassMethod(settle, "Hold", "", keys, .fresh)
	Do $$$AssertEquals($Length(seen, ","), 1000, "the set is cut to 1000 keys")
	Do $$$AssertEquals($Piece(seen, ",", 1)_"|"_$Piece(seen, ",", 1000), "h501|h1500", "the newest ones, newest last")
	Do $$$AssertEquals($Length(fresh, ","), 1500, "while every new key is given")
	Set seen = $ClassMethod(settle, "Hold", seen, "h1,h1500,h1501", .fresh)
	Do $$$AssertEquals(fresh, "h1,h1501", "a key that was cut out of the set is new again, and a held one is not")
	Do $$$AssertEquals($Length(seen, ",")_"|"_$Piece(seen, ",", 1)_"|"_$Piece(seen, ",", 1000), "1000|h503|h1501", "and the set is cut again")
}

Method TestValues()
{
	Set settle = ..#SETTLE
	Do ..Give(4, 12)
	Do $ClassMethod(settle, "Values", .quiet, .max)
	Do $$$AssertEquals(quiet_"|"_max, "4|12", "the settings in the cache give 4 and 12")
	Do ..Give("", "")
	Do $ClassMethod(settle, "Values", .quiet, .max)
	Do $$$AssertEquals(quiet_"|"_max, "10|30", "settings that are absent give the defaults 10 and 30")
	For each = 0, "x", -3, "1.5", "4s", " " {
		Do ..Give(each, each)
		Do $ClassMethod(settle, "Values", .quiet, .max)
		Do $$$AssertEquals(quiet_"|"_max, "10|30", "'"_each_"' is not a positive whole number: the defaults")
	}
	Do ..Give(7, "x")
	Do $ClassMethod(settle, "Values", .quiet, .max)
	Do $$$AssertEquals(quiet_"|"_max, "7|30", "each setting stands alone")
	Do ..PutBack()
}

Method TestKeyOf()
{
	Set mark = ..#MARK
	Do $$$AssertEquals($ClassMethod(mark, "KeyOf", "header", 5, ""), "h5", "a header failure is h<header id>")
	Do $$$AssertEquals($ClassMethod(mark, "KeyOf", "error", "", 9), "l9", "an error log row is l<log id>")
	Do $$$AssertEquals($ClassMethod(mark, "KeyOf", "alert", "", 9), "l9", "so is an alert")
	Do $$$AssertEquals($ClassMethod(mark, "KeyOf", "header", 5, 9), "h5", "a header failure keeps its header id when it has a log id")
	Do $$$AssertEquals($ClassMethod(mark, "Key", {"kind": "header", "headerId": 7, "logId": ""}), "h7", "Key of a reader's row is KeyOf of its parts: a header")
	Do $$$AssertEquals($ClassMethod(mark, "Key", {"kind": "error", "headerId": "", "logId": 8}), "l8", "and a log row")
}

/// Puts the two settings in the process's cache of Data.Setting (the node ^||OcuTalon.Setting(key)); "" removes the entry, so that the setting is absent.
/// The cache before the first change is kept for PutBack.
Method Give(quiet As %String, max As %String) [ Private ]
{
	If '..Saved {
		Set ..SavedQuiet = $Get(^||OcuTalon.Setting(##class(OcuTalon.Watch.Settle).#QUIETKEY))
		Set ..SavedMax = $Get(^||OcuTalon.Setting(##class(OcuTalon.Watch.Settle).#MAXKEY))
		Set ..Saved = 1
	}
	Do ..Cache(##class(OcuTalon.Watch.Settle).#QUIETKEY, quiet)
	Do ..Cache(##class(OcuTalon.Watch.Settle).#MAXKEY, max)
}

ClassMethod Cache(key As %String, value As %String) [ Private ]
{
	If value = "" {
		Kill ^||OcuTalon.Setting(key)
	} Else {
		Set ^||OcuTalon.Setting(key) = $ListBuild(value, 1, $ZHorolog)
	}
}

/// Puts the process's cache of the two settings back as it was before the test.
Method PutBack() [ Private ]
{
	If '..Saved Quit
	Set ..Saved = 0
	If ..SavedQuiet = "" {
		Kill ^||OcuTalon.Setting(##class(OcuTalon.Watch.Settle).#QUIETKEY)
	} Else {
		Set ^||OcuTalon.Setting(##class(OcuTalon.Watch.Settle).#QUIETKEY) = ..SavedQuiet
	}
	If ..SavedMax = "" {
		Kill ^||OcuTalon.Setting(##class(OcuTalon.Watch.Settle).#MAXKEY)
	} Else {
		Set ^||OcuTalon.Setting(##class(OcuTalon.Watch.Settle).#MAXKEY) = ..SavedMax
	}
}

}
