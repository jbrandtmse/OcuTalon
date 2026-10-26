/// Tests of the pure classes of Story 5.2's failure reading, OcuTalon.Watch.ErrorText and OcuTalon.Watch.Mark (AD-5, AD-15; DW-35). They need no production and
/// no namespace, so they run anywhere, a slot included.
///   - TestSentence: the error's own sentence of the measured wrapper text (the line break and the nested "  > " line are dropped), of a plain "ERROR #5001:"
///     text, of text with no prefix (trimmed), of a long one (cut to 1000 characters) and of an empty or undefined one;
///   - TestNormal and TestShift: a stored time is made a stamp with three fractional digits, a text that is not a time is "", and a stamp moves by whole seconds
///     across a minute, a day and a year;
///   - TestStart: the start of a reading is the later of the mark (less the overlap) and the earliest CreatedAt, either of them alone, or the poll time
///     when neither is known;
///   - TestFresh: the failures of the Seen set are dropped, a header and a log row with the same number are different failures, the order is kept and the
///     cap holds;
///   - TestNext: MarkAt is the newest time taken and never goes back, and Seen holds the failures read that were taken (now or before) and whose time is
///     inside the overlap before MarkAt, in the order read;
///   - TestFailedAt: a stamp as the batch carries it.
Class OcuTalon.Test.Watch.Mark Extends %UnitTest.TestCase
{

Parameter SENTENCE = "OcuTalon.Watch.ErrorText";

Parameter MARK = "OcuTalon.Watch.Mark";

Method TestSentence()
{
	Set own = "The order date was not in the expected format. Expected YYYY-MM-DD, got '10/16/2026'."
	Set measured = "ERROR <Ens>ErrBPTerminated: Terminating BP OrdersFromPartner # due to error: ERROR #5001: "_own_$Char(13, 10)_"  > ERROR #5001: "_own
	Do $$$AssertEquals($ClassMethod(..#SENTENCE, "Sentence", measured), own, "the measured wrapper gives the error's own sentence")
	Do $$$AssertEquals($ClassMethod(..#SENTENCE, "Sentence", "ERROR <Ens>ErrBPTerminated: Terminating BP Item 7 due to error: ERROR #5001: "_own_" > not nested "), own_" > not nested", "a line that is not a nested one stays; the ends are trimmed")
	Do $$$AssertEquals($ClassMethod(..#SENTENCE, "Sentence", "ERROR #5001: "_own), own, "a plain ERROR #5001: text loses its prefix")
	Do $$$AssertEquals($ClassMethod(..#SENTENCE, "Sentence", "ERROR <Ens>ErrGeneral: "_own), own, "so does an ERROR <Ens>Name: prefix")
	Do $$$AssertEquals($ClassMethod(..#SENTENCE, "Sentence", "  "_own_"  "), own, "a text with no prefix is trimmed")
	Do $$$AssertEquals($ClassMethod(..#SENTENCE, "Sentence", own_$Char(10)_"second line"), own, "a text stops at its first line break")
	Do $$$AssertEquals($ClassMethod(..#SENTENCE, "Sentence", own_"  > nested"), own, "and at a nested line")
	Do $$$AssertEquals($ClassMethod(..#SENTENCE, "Sentence", "ERROR #5001: ERROR #5001: "_own), own, "and a repeated prefix is dropped")
	Do $$$AssertEquals($ClassMethod(..#SENTENCE, "Sentence", "due to error: "_own), "due to error: "_own, "the wrapper is cut only when the text holds Terminating BP")
	Set long = $Justify("", 1500)
	Set long = $Translate(long, " ", "x")
	Set cut = $ClassMethod(..#SENTENCE, "Sentence", "ERROR #5001: "_long)
	Do $$$AssertEquals($Length(cut), 1000, "a long text is cut to 1000 characters")
	Do $$$AssertEquals($ClassMethod(..#SENTENCE, "Sentence", ""), "", "an empty text gives an empty sentence")
	Do $$$AssertEquals($ClassMethod(..#SENTENCE, "Sentence"), "", "and an undefined one too")
}

Method TestNormal()
{
	Do $$$AssertEquals($ClassMethod(..#MARK, "Normal", "2026-10-25 22:46:48.801"), "2026-10-25 22:46:48.801", "a stamp stays")
	Do $$$AssertEquals($ClassMethod(..#MARK, "Normal", "2026-10-25 22:46:48"), "2026-10-25 22:46:48.000", "whole seconds get three digits")
	Do $$$AssertEquals($ClassMethod(..#MARK, "Normal", "2026-10-25 22:46:48.8"), "2026-10-25 22:46:48.800", "one digit is padded")
	Do $$$AssertEquals($ClassMethod(..#MARK, "Normal", "2026-10-25 22:46:48.801234"), "2026-10-25 22:46:48.801", "six digits are cut")
	Do $$$AssertEquals($ClassMethod(..#MARK, "Normal", "2026-10-25T22:46:48Z"), "2026-10-25 22:46:48.000", "a UTC time of the product is read too")
	For text = "", "yesterday", "2026-10-25", "2026-10-25 22:46", "2026-10-25 22:46:48.8.1", "2026-10-25 22:46:48.x" {
		Do $$$AssertEquals($ClassMethod(..#MARK, "Normal", text), "", "'"_text_"' is not a time")
	}
}

Method TestShift()
{
	Set shift = "Shift"
	Do $$$AssertEquals($ClassMethod(..#MARK, shift, "2026-10-25 22:46:48.801", -2), "2026-10-25 22:46:46.801", "two seconds before; the fraction stays")
	Do $$$AssertEquals($ClassMethod(..#MARK, shift, "2026-10-25 22:46:48.801", 2), "2026-10-25 22:46:50.801", "two seconds after")
	Do $$$AssertEquals($ClassMethod(..#MARK, shift, "2026-10-25 22:00:01.000", -2), "2026-10-25 21:59:59.000", "across the hour")
	Do $$$AssertEquals($ClassMethod(..#MARK, shift, "2026-10-26 00:00:01.500", -2), "2026-10-25 23:59:59.500", "across midnight")
	Do $$$AssertEquals($ClassMethod(..#MARK, shift, "2027-01-01 00:00:00.000", -1), "2026-12-31 23:59:59.000", "across the year")
	Do $$$AssertEquals($ClassMethod(..#MARK, shift, "2028-03-01 00:00:00.000", -1), "2028-02-29 23:59:59.000", "across a leap day")
	Do $$$AssertEquals($ClassMethod(..#MARK, shift, "nothing", -2), "", "a text that is not a time stays empty")
}

Method TestStart()
{
	Set start = "Start"
	Set poll = "2026-10-25 23:00:00.000"
	Do $$$AssertEquals($ClassMethod(..#MARK, start, "2026-10-25 22:46:48.801", "2026-10-25T22:00:00Z", poll), "2026-10-25 22:46:46.801", "a mark later than CreatedAt: the mark less the overlap")
	Do $$$AssertEquals($ClassMethod(..#MARK, start, "2026-10-25 22:46:48.801", "2026-10-25T22:46:48Z", poll), "2026-10-25 22:46:48.000", "CreatedAt later than the mark less the overlap: CreatedAt")
	Do $$$AssertEquals($ClassMethod(..#MARK, start, "2026-10-25 21:00:00.000", "2026-10-25T22:00:00Z", poll), "2026-10-25 22:00:00.000", "a re-watch after a gap: CreatedAt, not the old mark")
	Do $$$AssertEquals($ClassMethod(..#MARK, start, "", "2026-10-25T22:00:00Z", poll), "2026-10-25 22:00:00.000", "no mark: CreatedAt, as a stamp")
	Do $$$AssertEquals($ClassMethod(..#MARK, start, "2026-10-25 22:46:48.801", "", poll), "2026-10-25 22:46:46.801", "no CreatedAt: the mark less the overlap")
	Do $$$AssertEquals($ClassMethod(..#MARK, start, "", "", poll), poll, "neither: the poll time")
	Do $$$AssertEquals($ClassMethod(..#MARK, start, "", "not a time", poll), poll, "a CreatedAt that is not a time counts as none")
}

Method TestFresh()
{
	Set rows = ..Rows("h1,h2,l2,h3,l4,h5")
	Set fresh = $ClassMethod(..#MARK, "Fresh", rows, "h2,l4")
	Do $$$AssertEquals(..Keys(fresh), "h1,l2,h3,h5", "the failures of Seen are dropped, the order is kept, and l2 is not h2")
	Do $$$AssertEquals(..Keys($ClassMethod(..#MARK, "Fresh", rows)), "h1,h2,l2,h3,l4,h5", "no Seen drops nothing")
	Do $$$AssertEquals(..Keys($ClassMethod(..#MARK, "Fresh", rows, "h1", 3)), "h2,l2,h3", "the cap takes the first failures that are new")
	Do $$$AssertEquals(..Keys($ClassMethod(..#MARK, "Fresh", rows, "", 0)), "", "a cap of 0 takes none")
	Set many = []
	For i = 1:1:$Parameter(..#MARK, "MAXFAILURES") + 20 {
		Do many.%Push({"kind": "header", "headerId": (i), "logId": "", "at": "2026-10-25 22:46:48.801"})
	}
	Do $$$AssertEquals($ClassMethod(..#MARK, "Fresh", many).%Size(), $Parameter(..#MARK, "MAXFAILURES"), "the default cap is MAXFAILURES")
	Do $$$AssertEquals($Parameter(..#MARK, "MAXFAILURES"), 500, "and that is 500")
}

Method TestNext()
{
	Set rows = []
	Do rows.%Push({"kind": "header", "headerId": 1, "logId": "", "at": "2026-10-25 22:46:40.000"})
	Do rows.%Push({"kind": "header", "headerId": 2, "logId": "", "at": "2026-10-25 22:46:47.500"})
	Do rows.%Push({"kind": "error", "headerId": "", "logId": 9, "at": "2026-10-25 22:46:48.100"})
	Do rows.%Push({"kind": "header", "headerId": 3, "logId": "", "at": "2026-10-25 22:46:48.801"})
	Do $ClassMethod(..#MARK, "Next", "2026-10-25 22:46:40.000", "h1", rows, [(rows.%Get(1)), (rows.%Get(2))], .markAt, .seen)
	Do $$$AssertEquals(markAt, "2026-10-25 22:46:48.100", "MarkAt is the newest time taken")
	Do $$$AssertEquals(seen, "h2,l9", "Seen holds the taken failures inside the overlap (22:46:46.100 on), in the order read; h1 is outside it")
	Do $ClassMethod(..#MARK, "Next", "2026-10-25 22:50:00.000", "", rows, [(rows.%Get(0))], .markAt, .seen)
	Do $$$AssertEquals(markAt, "2026-10-25 22:50:00.000", "MarkAt never goes back")
	Do $$$AssertEquals(seen, "", "and a failure outside the overlap of the mark is not kept")
	Do $ClassMethod(..#MARK, "Next", "", "", rows, rows, .markAt, .seen)
	Do $$$AssertEquals(markAt, "2026-10-25 22:46:48.801", "with no mark yet, the newest time taken")
	Do $$$AssertEquals(seen, "h2,l9,h3", "and the taken failures of the last two seconds")
	Do $ClassMethod(..#MARK, "Next", "2026-10-25 22:46:47.000", "h2", rows, [(rows.%Get(3))], .markAt, .seen)
	Do $$$AssertEquals(markAt, "2026-10-25 22:46:48.801", "the mark moves up to the failure taken")
	Do $$$AssertEquals(seen, "h2,h3", "and the old Seen failure that is still inside the overlap stays, with the new one")
}

Method TestFailedAt()
{
	Do $$$AssertEquals($ClassMethod(..#MARK, "FailedAt", "2026-10-25 22:46:48.801"), "2026-10-25T22:46:48Z", "UTC to the second, as the product writes it")
	Do $$$AssertEquals($ClassMethod(..#MARK, "FailedAt", "2026-10-25 22:46:48"), "2026-10-25T22:46:48Z", "whole seconds too")
	Do $$$AssertEquals($ClassMethod(..#MARK, "FailedAt", "nothing"), "", "a text that is not a time gives nothing")
}

/// A dynamic array of header failures for the keys: hN a header, lN a log row.
ClassMethod Rows(keys As %String) As %DynamicArray [ Private ]
{
	Set rows = []
	For i = 1:1:$Length(keys, ",") {
		Set key = $Piece(keys, ",", i)
		Set number = $Extract(key, 2, *)
		Do rows.%Push({"kind": ($Select($Extract(key) = "h": "header", 1: "error")), "headerId": ($Select($Extract(key) = "h": number, 1: "")), "logId": ($Select($Extract(key) = "l": number, 1: "")), "at": "2026-10-25 22:46:48.801"})
	}
	Quit rows
}

/// The keys of the failures, comma-separated.
ClassMethod Keys(failures As %DynamicArray) As %String [ Private ]
{
	Set keys = ""
	Set iterator = failures.%GetIterator()
	While iterator.%GetNext(, .failure) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_$ClassMethod(..#MARK, "Key", failure)
	}
	Quit keys
}

}
