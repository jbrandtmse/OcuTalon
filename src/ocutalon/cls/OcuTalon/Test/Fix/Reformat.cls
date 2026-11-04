/// Tests of the reformatters (Story 7.1; AD-16): OcuTalon.Fix.Reformat. Pure: no production and no namespace, so they run anywhere, a slot included.
///   - TestRegistry: the registered formats are the five dates and the four numbers, written exactly, and Family tells the family of a name and gives "" for any
///     other name, also one in another case;
///   - TestConvertsDates and TestConvertsNumbers: every ordered pair of two formats of one family converts a table of valid values exactly (a leap day, a sign,
///     grouping, a fraction of any length, no rounding);
///   - TestRefuses: wrong separators, padding, a value of more than 40 characters, a day that is not on the calendar, a time, digits of other scripts, an empty value,
///     two formats of two families or one format twice, and a name that is not registered are refused, each with an error status and no result;
///   - TestReadings (DW-644): OtherOrder names the other order of the two slash formats and nothing else; Readings is 1 exactly when a value reads in the format and in
///     its other order, with the two day numbers (equal when the month equals the day), and 0, with both empty, for a value that reads one way only, in neither, a
///     malformed or empty one, and a format that has no other order;
///   - TestEvidence (DW-644; U-249 Conditions 1 and 2; Q1 ruled (a)): Fix.Kind.RepairResend Evidence over every outcome (n/a, oneway, arrival, same, none) and the count of
///     the two-way values: the tolerance edges (one day either side of the UTC date of the arrival, at the end and at the start of the day), the instance date against
///     the UTC date (a value of the 3rd with an arrival at 02:00 UTC on the 4th), a set of only same-date values, both orders, and an arrival that is empty or malformed
///     (it never matches);
///   - TestNeverEvaluates: injection-shaped values are refused by every source format and leave the sentinel global undefined;
///   - TestStaticScan: the code of Reformat and of RepairResend has no Xecute (the command, as a whole word: RepairResend's own method Execute is none), no indirection,
///     no $ZF, and no $ClassMethod, $Method or $Property.
Class OcuTalon.Test.Fix.Reformat Extends %UnitTest.TestCase
{

Parameter CLASS = "OcuTalon.Fix.Reformat";

/// The pattern of the Xecute command (a whole word, so that a method named Execute does not match).
Parameter XECUTE = "\bXecute\b";

/// The value, in the order of the DATES formats, of each date of the table, separated by a vertical bar.
Parameter DATES = "2026-10-16|10/16/2026|16/10/2026|16.10.2026|20261016;2024-02-29|02/29/2024|29/02/2024|29.02.2024|20240229;1840-12-31|12/31/1840|31/12/1840|31.12.1840|18401231;9999-12-31|12/31/9999|31/12/9999|31.12.9999|99991231";

/// The value, in the order of the NUMBERS formats, of each number of the table, separated by a vertical bar.
Parameter NUMBERS = "1234.56|1234,56|1,234.56|1.234,56;1234567.891|1234567,891|1,234,567.891|1.234.567,891;-1234567.5|-1234567,5|-1,234,567.5|-1.234.567,5;0.50|0,50|0.50|0,50;12|12|12|12;999|999|999|999;1000|1000|1,000|1.000;100000|100000|100,000|100.000;-0.001|-0,001|-0.001|-0,001;12345678901234567890.12345|12345678901234567890,12345|12,345,678,901,234,567,890.12345|12.345.678.901.234.567.890,12345";

Method TestRegistry()
{
	Set names = ##class(OcuTalon.Fix.Reformat).Names()
	Do $$$AssertEquals($ListLength(names), 9, "nine formats are registered")
	Set expected = $ListBuild("YYYY-MM-DD", "MM/DD/YYYY", "DD/MM/YYYY", "DD.MM.YYYY", "YYYYMMDD", "1234.56", "1234,56", "1,234.56", "1.234,56")
	Do $$$AssertEquals(names, expected, "the five dates and the four numbers, written exactly")
	Set position = 0
	While $ListNext(names, position, name) {
		Do $$$AssertEquals(##class(OcuTalon.Fix.Reformat).Family(name), $Select($Extract(name, 1) = "1": "number", 1: "date"), name_" is in its family")
	}
	For name = "", "yyyy-mm-dd", "Mm/dd/yyyy", "YYYY-MM-DD ", "ISO", "1234:56", "1 234.56", "date", "number" {
		Do $$$AssertEquals(##class(OcuTalon.Fix.Reformat).Family(name), "", "'"_name_"' is not registered")
	}
}

Method TestConvertsDates()
{
	Do ..AssertTable(..#DATES, "date")
}

Method TestConvertsNumbers()
{
	Do ..AssertTable(..#NUMBERS, "number")
}

/// Converts each row's value of every format into every other format of the family, and asserts the row's value of the target.
Method AssertTable(table As %String, family As %String) [ Private ]
{
	Set names = ""
	Set all = ##class(OcuTalon.Fix.Reformat).Names()
	Set position = 0
	While $ListNext(all, position, name) {
		If ##class(OcuTalon.Fix.Reformat).Family(name) = family Set names = names _ $ListBuild(name)
	}
	For row = 1:1:$Length(table, ";") {
		Set values = $Piece(table, ";", row)
		For i = 1:1:$ListLength(names) {
			For j = 1:1:$ListLength(names) {
				If i = j Continue
				Set source = $List(names, i)
				Set target = $List(names, j)
				Set sc = ##class(OcuTalon.Fix.Reformat).Convert($Piece(values, "|", i), source, target, .result)
				Do $$$AssertStatusOK(sc, $Piece(values, "|", i)_" "_source_" -> "_target_" converts")
				Do $$$AssertEquals(result, $Piece(values, "|", j), $Piece(values, "|", i)_" "_source_" -> "_target_" is exactly "_$Piece(values, "|", j))
				Do $$$AssertTrue(##class(OcuTalon.Fix.Reformat).Reads($Piece(values, "|", i), source), $Piece(values, "|", i)_" reads in "_source)
			}
		}
	}
}

Method TestRefuses()
{
	Set arabic = $Char(1634, 1632, 1634, 1638)
	Set fullwidth = $Char(65298, 65296, 65298, 65302)
	Set long = $Justify("", 41)
	Set long = $Translate(long, " ", "1")
	Do ..AssertRefused("2026/10/16", "YYYY-MM-DD", "YYYYMMDD", "slashes in a dashed date")
	Do ..AssertRefused("10-16-2026", "MM/DD/YYYY", "YYYY-MM-DD", "dashes in a slashed date")
	Do ..AssertRefused("16.10.2026", "DD/MM/YYYY", "YYYY-MM-DD", "dots in a slashed date")
	Do ..AssertRefused("16/10/2026", "DD.MM.YYYY", "YYYY-MM-DD", "slashes in a dotted date")
	Do ..AssertRefused("2026-10-16", "YYYYMMDD", "YYYY-MM-DD", "dashes in a compact date")
	Do ..AssertRefused("10/16/26", "MM/DD/YYYY", "YYYY-MM-DD", "a two-digit year")
	Do ..AssertRefused("1/6/2026", "MM/DD/YYYY", "YYYY-MM-DD", "no zero padding")
	Do ..AssertRefused("2026-10-6", "YYYY-MM-DD", "YYYYMMDD", "a day without its zero")
	Do ..AssertRefused(" 2026-10-16", "YYYY-MM-DD", "YYYYMMDD", "a leading space")
	Do ..AssertRefused("2026-10-16 ", "YYYY-MM-DD", "YYYYMMDD", "a trailing space")
	Do ..AssertRefused("2026-10-16"_$Char(10), "YYYY-MM-DD", "YYYYMMDD", "a trailing line feed")
	Do ..AssertRefused($Char(10)_"2026-10-16", "YYYY-MM-DD", "YYYYMMDD", "a leading line feed")
	Do ..AssertRefused("2026-10-16T10:00:00", "YYYY-MM-DD", "YYYYMMDD", "a date with a time")
	Do ..AssertRefused("2026-10-16T", "YYYY-MM-DD", "YYYYMMDD", "a date with a T")
	Do ..AssertRefused("2026-02-30", "YYYY-MM-DD", "YYYYMMDD", "February 30")
	Do ..AssertRefused("2026-02-29", "YYYY-MM-DD", "YYYYMMDD", "February 29 of a year that is not a leap year")
	Do ..AssertRefused("2100-02-29", "YYYY-MM-DD", "YYYYMMDD", "February 29 of 2100")
	Do ..AssertRefused("2026-13-01", "YYYY-MM-DD", "YYYYMMDD", "month 13")
	Do ..AssertRefused("2026-00-10", "YYYY-MM-DD", "YYYYMMDD", "month 0")
	Do ..AssertRefused("2026-04-31", "YYYY-MM-DD", "YYYYMMDD", "April 31")
	Do ..AssertRefused("2026-10-00", "YYYY-MM-DD", "YYYYMMDD", "day 0")
	Do ..AssertRefused("0000-01-01", "YYYY-MM-DD", "YYYYMMDD", "year 0")
	Do ..AssertRefused("1840-12-30", "YYYY-MM-DD", "YYYYMMDD", "the day before the first day of the calendar range")
	Do ..AssertRefused("31/12/2026", "MM/DD/YYYY", "YYYY-MM-DD", "a day in the month field")
	Do ..AssertRefused("12/31/2026", "DD/MM/YYYY", "YYYY-MM-DD", "a month in the day field")
	Do ..AssertRefused(arabic_"-10-16", "YYYY-MM-DD", "YYYYMMDD", "Arabic-Indic digits")
	Do ..AssertRefused("10/16/"_arabic, "MM/DD/YYYY", "YYYY-MM-DD", "Arabic-Indic digits in a slashed date")
	Do ..AssertRefused(arabic_"1016", "YYYYMMDD", "YYYY-MM-DD", "Arabic-Indic digits in a compact date")
	Do ..AssertRefused(fullwidth_"-10-16", "YYYY-MM-DD", "YYYYMMDD", "full-width digits")
	Do ..AssertRefused("", "YYYY-MM-DD", "YYYYMMDD", "an empty date")
	Do ..AssertRefused("", "1234.56", "1234,56", "an empty number")
	Do ..AssertRefused(long, "1234.56", "1234,56", "a number of 41 characters")
	Do ..AssertRefused($Translate($Justify("", 30), " ", "1")_"."_$Translate($Justify("", 10), " ", "1"), "1234.56", "1234,56", "a number of 41 characters with a fraction")
	Do ..AssertRefused("1,234,56", "1234,56", "1234.56", "a group separator in an ungrouped number")
	Do ..AssertRefused("1.234.56", "1234.56", "1234,56", "two decimal separators")
	Do ..AssertRefused("1234.56", "1234,56", "1234.56", "a point in a number that is written with a comma")
	Do ..AssertRefused("1234,56", "1234.56", "1234,56", "a comma in a number that is written with a point")
	Do ..AssertRefused("1.234,56", "1,234.56", "1234.56", "a European number in the American format")
	Do ..AssertRefused("1,234.56", "1.234,56", "1234.56", "an American number in the European format")
	Do ..AssertRefused("1,23.45", "1,234.56", "1234.56", "a group of two digits")
	Do ..AssertRefused("12,3456.78", "1,234.56", "1234.56", "a group of four digits")
	Do ..AssertRefused("1234,567.89", "1,234.56", "1234.56", "a first group of four digits")
	Do ..AssertRefused("1,234,.56", "1,234.56", "1234.56", "an empty group")
	Do ..AssertRefused("01,234.56", "1,234.56", "1234.56", "a leading zero")
	Do ..AssertRefused("01234.56", "1234.56", "1234,56", "a leading zero in a whole part")
	Do ..AssertRefused("1234.", "1234.56", "1234,56", "a decimal separator with no fraction")
	Do ..AssertRefused(".56", "1234.56", "1234,56", "a fraction with no whole part")
	Do ..AssertRefused("-", "1234.56", "1234,56", "a sign alone")
	Do ..AssertRefused("+12.5", "1234.56", "1234,56", "a plus sign")
	Do ..AssertRefused("--12.5", "1234.56", "1234,56", "two minus signs")
	Do ..AssertRefused("12.5-", "1234.56", "1234,56", "a sign after the number")
	Do ..AssertRefused("1 234.56", "1234.56", "1234,56", "a space in a number")
	Do ..AssertRefused(" 12.5", "1234.56", "1234,56", "a leading space in a number")
	Do ..AssertRefused("12.5 ", "1234.56", "1234,56", "a trailing space in a number")
	Do ..AssertRefused("12.5"_$Char(10), "1234.56", "1234,56", "a trailing line feed in a number")
	Do ..AssertRefused("1e3", "1234.56", "1234,56", "an exponent")
	Do ..AssertRefused("12.5%", "1234.56", "1234,56", "a percent sign")
	Do ..AssertRefused("$12.50", "1234.56", "1234,56", "a currency sign")
	Do ..AssertRefused(arabic_".56", "1234.56", "1234,56", "Arabic-Indic digits in a number")
	Do ..AssertRefused("12."_arabic, "1234.56", "1234,56", "Arabic-Indic digits in a fraction")
	Do ..AssertRefused("2026-10-16", "YYYY-MM-DD", "1234.56", "two formats of two families")
	Do ..AssertRefused("1234.56", "1234.56", "YYYY-MM-DD", "two formats of two families, a number first")
	Do ..AssertRefused("2026-10-16", "YYYY-MM-DD", "YYYY-MM-DD", "one format twice")
	Do ..AssertRefused("1234.56", "1234.56", "1234.56", "one number format twice")
	Do ..AssertRefused("2026-10-16", "yyyy-mm-dd", "YYYYMMDD", "a source name in lower case")
	Do ..AssertRefused("20261016", "YYYYMMDD", "Yyyy-Mm-Dd", "a target name in mixed case")
	Do ..AssertRefused("2026-10-16", "ISO", "YYYYMMDD", "an unregistered source")
	Do ..AssertRefused("2026-10-16", "YYYY-MM-DD", "", "an empty target")
	Do ..AssertRefused("2026-10-16", "", "YYYYMMDD", "an empty source")
}

/// Asserts that Convert refuses the value between the formats with an error status and an empty result.
Method AssertRefused(value As %String, source As %String, target As %String, label As %String) [ Private ]
{
	Set result = "kept"
	Set sc = ##class(OcuTalon.Fix.Reformat).Convert(value, source, target, .result)
	Do $$$AssertStatusNotOK(sc, label_" is refused")
	Do $$$AssertEquals(result, "", label_" gives no result")
}

Method TestNeverEvaluates()
{
	Kill ^OcuTalonTest("FixSentinel")
	Set inputs = $ListBuild("@^OcuTalonTest(""FixSentinel"")", "$$TOUCH^ZzFix", """_$Increment(^OcuTalonTest(""FixSentinel""))_""", "##class(OcuTalon.Test.Fix.ZzKind).Touch()", "$ZF(-100,""/bin/sh"",""-c"",""true"")", "$Increment(^OcuTalonTest(""FixSentinel""))", "1_$Increment(^OcuTalonTest(""FixSentinel""))", "Set ^OcuTalonTest(""FixSentinel"")=1", "2026-10-16;Set ^OcuTalonTest(""FixSentinel"")=1", "1234.56_$Increment(^OcuTalonTest(""FixSentinel""))")
	Set names = ##class(OcuTalon.Fix.Reformat).Names()
	Set position = 0
	While $ListNext(inputs, position, input) {
		Set formats = 0
		Set namePosition = 0
		While $ListNext(names, namePosition, source) {
			Set targetPosition = 0
			While $ListNext(names, targetPosition, target) {
				If (source = target) || (##class(OcuTalon.Fix.Reformat).Family(source) '= ##class(OcuTalon.Fix.Reformat).Family(target)) Continue
				Set sc = ##class(OcuTalon.Fix.Reformat).Convert(input, source, target, .result)
				If $$$ISOK(sc) || (result '= "") Set formats = formats + 1
			}
		}
		Do $$$AssertEquals(formats, 0, "'"_$Extract(input, 1, 40)_"' is refused by every format")
	}
	Do $$$AssertEquals($Data(^OcuTalonTest("FixSentinel")), 0, "and nothing evaluated any of them: the sentinel global is still undefined")
	Kill ^OcuTalonTest("FixSentinel")
}

Method TestReadings()
{
	Do $$$AssertEquals(##class(OcuTalon.Fix.Reformat).OtherOrder("MM/DD/YYYY"), "DD/MM/YYYY", "the other order of month first is day first")
	Do $$$AssertEquals(##class(OcuTalon.Fix.Reformat).OtherOrder("DD/MM/YYYY"), "MM/DD/YYYY", "and back")
	For format = "YYYY-MM-DD", "DD.MM.YYYY", "YYYYMMDD", "1234.56", "mm/dd/yyyy", "" {
		Do $$$AssertEquals(##class(OcuTalon.Fix.Reformat).OtherOrder(format), "", "'"_format_"' has no other order")
	}
	Set nov3 = $ZDateH("2026-11-03", 3)
	Set mar11 = $ZDateH("2026-03-11", 3)
	Do $$$AssertTrue(##class(OcuTalon.Fix.Reformat).Readings("11/03/2026", "MM/DD/YYYY", .source, .other), "11/03/2026 reads both ways")
	Do $$$AssertEquals(source_"|"_other, nov3_"|"_mar11, "month first is November 3, day first March 11")
	Do $$$AssertTrue(##class(OcuTalon.Fix.Reformat).Readings("03/11/2026", "DD/MM/YYYY", .source, .other), "03/11/2026 reads both ways")
	Do $$$AssertEquals(source_"|"_other, nov3_"|"_mar11, "day first is November 3, month first March 11")
	Do $$$AssertTrue(##class(OcuTalon.Fix.Reformat).Readings("11/11/2026", "MM/DD/YYYY", .source, .other), "11/11/2026 reads both ways")
	Do $$$AssertEquals(source, other, "as one date")
	Do $$$AssertTrue(##class(OcuTalon.Fix.Reformat).Readings("02/29/2024", "MM/DD/YYYY", .source, .other) = 0, "02/29/2024 reads month first only: day first has no month 29")
	Do $$$AssertTrue(##class(OcuTalon.Fix.Reformat).Readings("29/02/2024", "DD/MM/YYYY", .source, .other) = 0, "and 29/02/2024 reads day first only")
	Do $$$AssertEquals(source_"|"_other, "|", "with both day numbers empty")
	For case = $ListBuild("10/16/2026", "MM/DD/YYYY"), $ListBuild("16/10/2026", "DD/MM/YYYY"), $ListBuild("10/16/2026", "DD/MM/YYYY"), $ListBuild("16/10/2026", "MM/DD/YYYY"), $ListBuild("2026-11-03", "YYYY-MM-DD"), $ListBuild("03.11.2026", "DD.MM.YYYY"), $ListBuild("20261103", "YYYYMMDD"), $ListBuild("1234.56", "1234.56"), $ListBuild("11/03/26", "MM/DD/YYYY"), $ListBuild(" 11/03/2026", "MM/DD/YYYY"), $ListBuild("", "MM/DD/YYYY"), $ListBuild("13/13/2026", "MM/DD/YYYY"), $ListBuild("11/03/2026", "YYYY-MM-DD"), $ListBuild("11/03/2026", "") {
		Set source = "x"
		Set other = "x"
		Do $$$AssertEquals(##class(OcuTalon.Fix.Reformat).Readings($List(case, 1), $List(case, 2), .source, .other), 0, "'"_$List(case, 1)_"' does not read both ways in '"_$List(case, 2)_"'")
		Do $$$AssertEquals(source_"|"_other, "|", "and gives no day number")
	}
}

Method TestEvidence()
{
	For format = "YYYY-MM-DD", "DD.MM.YYYY", "YYYYMMDD", "1234.56" {
		Do ..AssertEvidence([{"value": "11/03/2026", "arrived": "2026-11-03T15:00:00Z"}], format, "n/a", 0, "a source format that is no order format ("_format_")")
	}
	Do ..AssertEvidence([{"value": "10/16/2026", "arrived": "2026-12-20T12:00:00Z"}], "MM/DD/YYYY", "oneway", 0, "a day above 12 is evidence")
	Do ..AssertEvidence([{"value": "16/10/2026", "arrived": "2026-12-20T12:00:00Z"}], "DD/MM/YYYY", "oneway", 0, "also day first")
	Do ..AssertEvidence([{"value": "11/03/2026", "arrived": "2026-12-20T12:00:00Z"}, {"value": "11/13/2026", "arrived": "2026-12-20T12:00:00Z"}, {"value": "11/03/2026", "arrived": "2026-12-20T12:00:00Z"}], "MM/DD/YYYY", "oneway", 2, "one value with a day above 12 is evidence for the set, and the two-way values are counted")
	Do ..AssertEvidence([{"value": "11/03/2026", "arrived": "2026-11-03T15:00:00Z"}, {"value": "11/04/2026", "arrived": "2026-11-04T01:00:00Z"}, {"value": "11/05/2026", "arrived": "2026-11-05T23:59:59Z"}], "MM/DD/YYYY", "arrival", 3, "each value matches its own arrival")
	Do ..AssertEvidence([{"value": "11/03/2026", "arrived": "2026-11-03T15:00:00Z"}, {"value": "11/04/2026", "arrived": "2026-11-09T01:00:00Z"}], "MM/DD/YYYY", "none", 2, "one value that does not match its own arrival leaves the set without evidence")
	Do ..AssertEvidence([{"value": "03/11/2026", "arrived": "2026-11-03T15:00:00Z"}], "DD/MM/YYYY", "arrival", 1, "day first: 03/11/2026 matches an arrival on November 3")
	Do ..AssertEvidence([{"value": "03/11/2026", "arrived": "2026-11-03T15:00:00Z"}], "MM/DD/YYYY", "none", 1, "and month first reads it as March 11, which does not")
	// The tolerance edges: one day either side of the UTC date, at the last second and the first second of a day.
	For case = $ListBuild("2026-11-02T23:59:59Z", "arrival"), $ListBuild("2026-11-02T00:00:00Z", "arrival"), $ListBuild("2026-11-03T00:00:00Z", "arrival"), $ListBuild("2026-11-03T23:59:59Z", "arrival"), $ListBuild("2026-11-04T00:00:00Z", "arrival"), $ListBuild("2026-11-04T23:59:59Z", "arrival"), $ListBuild("2026-11-01T23:59:59Z", "none"), $ListBuild("2026-11-01T00:00:00Z", "none"), $ListBuild("2026-11-05T00:00:00Z", "none"), $ListBuild("2026-11-05T23:59:59Z", "none") {
		Do ..AssertEvidence([{"value": "11/03/2026", "arrived": ($List(case, 1))}], "MM/DD/YYYY", $List(case, 2), 1, "11/03/2026 arrived "_$List(case, 1))
	}
	// U-249 Condition 2: an evening press in the Americas writes the 3rd while the header says the 4th (UTC).
	Do ..AssertEvidence([{"value": "11/03/2026", "arrived": "2026-11-04T02:00:00Z"}], "MM/DD/YYYY", "arrival", 1, "the instance date is the 3rd and the UTC date the 4th")
	// Q1 ruled (a): a value whose month equals its day reads as one date, so it chooses nothing and needs nothing.
	Do ..AssertEvidence([{"value": "11/11/2026", "arrived": "2026-11-11T15:00:00Z"}, {"value": "11/11/2026", "arrived": "2026-11-11T15:00:00Z"}, {"value": "11/11/2026", "arrived": "2026-11-11T15:00:00Z"}], "MM/DD/YYYY", "same", 3, "three values that read as one date")
	Do ..AssertEvidence([{"value": "11/11/2026", "arrived": "2026-01-01T00:00:00Z"}], "MM/DD/YYYY", "same", 1, "also when the arrival does not match")
	Do ..AssertEvidence([{"value": "11/11/2026", "arrived": "2026-11-04T02:00:00Z"}, {"value": "03/05/2026", "arrived": "2026-11-04T02:00:00Z"}], "MM/DD/YYYY", "none", 2, "a same-date value does not make evidence for a value whose readings differ")
	Do ..AssertEvidence([{"value": "11/11/2026", "arrived": "2026-01-01T00:00:00Z"}, {"value": "11/03/2026", "arrived": "2026-11-03T15:00:00Z"}], "MM/DD/YYYY", "arrival", 2, "and a value whose readings differ and that matches is the evidence of a mixed set")
	// An arrival that cannot be read never matches.
	For arrived = "", "garbage", "2026-11-03", "2026-11-03T15:00:00", "2026-13-45T00:00:00Z", "2026-11-03 15:00:00" {
		Do ..AssertEvidence([{"value": "11/03/2026", "arrived": (arrived)}], "MM/DD/YYYY", "none", 1, "the arrival '"_arrived_"' never matches")
	}
	Do ..AssertEvidence([{"value": "11/03/2026"}], "MM/DD/YYYY", "none", 1, "a value with no arrival never matches")
	// A value that does not read in the source format is not counted.
	Do ..AssertEvidence([{"value": "2026/10/16", "arrived": "2026-11-03T15:00:00Z"}, {"value": "11/03/2026", "arrived": "2026-11-03T15:00:00Z"}], "MM/DD/YYYY", "arrival", 1, "a value in another format is left out")
}

/// Asserts the evidence and the two-way count of the values in the format.
Method AssertEvidence(values As %DynamicArray, format As %String, expected As %String, twoWay As %Integer, label As %String) [ Private ]
{
	Set got = ##class(OcuTalon.Fix.Kind.RepairResend).Evidence(values, format, .count)
	Do $$$AssertEquals(got_"|"_count, expected_"|"_twoWay, label_": "_expected_" with "_twoWay_" two-way")
}

Method TestStaticScan()
{
	For class = "OcuTalon.Fix.Reformat", "OcuTalon.Fix.Kind.RepairResend" {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Source).Text(class, .text), class_" has source")
		Do $$$AssertTrue($Length(text) > 1000, class_" source is read")
		For pattern = ..#XECUTE, "@", "\$ZF\(", "\$ClassMethod\(", "\$Method\(", "\$Property\(" {
			Do $$$AssertNotTrue(##class(OcuTalon.Test.Bridge.Source).Matches(text, pattern), class_" has no "_pattern_" in its code")
		}
	}
	Set sample = $Char(9)_"Xecute ""Set x=""_value"_$Char(10)_$Char(9)_"Set y = @name"
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Source).Matches(sample, ..#XECUTE) && ##class(OcuTalon.Test.Bridge.Source).Matches(sample, "@"), "the scan is first shown to flag an Xecute and an indirection")
	Do $$$AssertNotTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"// Xecute is never used @ all", ..#XECUTE_"|@"), "and to pass a comment line")
	Do $$$AssertNotTrue(##class(OcuTalon.Test.Bridge.Source).Matches($Char(9)_"ClassMethod Execute(incident As OcuTalon.Data.Incident) As %Status", ..#XECUTE), "and a method named Execute, which is no Xecute")
}

}
