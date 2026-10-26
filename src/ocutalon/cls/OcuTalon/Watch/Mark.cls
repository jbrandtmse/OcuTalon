/// The arithmetic of FailurePoller's reading (pure; AD-5, AD-15): where a production's reading starts, which of the failures that the reader
/// gave are new, and the mark to keep. It holds nothing: the mark itself is the row of OcuTalon.Data.WatchMark, and the poller is its only writer.
///   - A stamp is a time as IRIS stores it, UTC, YYYY-MM-DD HH:MM:SS.sss, so that string order is time order. Normal makes one from a stored time
///     that has fewer or more fractional digits.
///   - Start is the stamp the reading starts from: the later of the mark's start (MarkAt less OVERLAP seconds) and the earliest watch's CreatedAt,
///     or the poll time when neither is known. The overlap re-reads the failures whose time IRIS assigned just before its write committed.
///   - Fresh drops the failures of the Seen set and caps what is left at MAXFAILURES, in the order read.
///   - Next gives the mark after a poll that took failures: MarkAt is the newest time taken, and Seen holds the failures read whose time is still
///     inside the overlap before it and that were already batched (earlier or now). A failure is h<header id> or l<log id> (Key).
///   - FailedAt is a stamp as the batch carries it: YYYY-MM-DDTHH:MM:SSZ.
/// A failure of the reader is a dynamic object with at least kind, headerId, logId and at (see OcuTalon.Watch.Reader.Failures).
Class OcuTalon.Watch.Mark
{

/// The most failures that one production gives to one poll.
Parameter MAXFAILURES = 500;

/// The seconds that a reading starts before the mark.
Parameter OVERLAP = 2;

/// The stamp of a stored time: whole seconds with exactly three fractional digits, or "" when the text is not a time of that kind. A "T" between
/// the date and the clock and a trailing "Z" are accepted.
ClassMethod Normal(stored As %String) As %String
{
	Set text = $ZStrip($Translate($Get(stored), "TZ", "  "), "<>W")
	Set whole = $Piece(text, ".", 1)
	Set fraction = $Piece(text, ".", 2)
	If '(whole ? 4N1"-"2N1"-"2N1" "2N1":"2N1":"2N) || ($Length(text, ".") > 2) || (fraction '= "" && (fraction '? 1.N)) Quit ""
	Quit whole_"."_$Extract(fraction_"000", 1, 3)
}

/// The stamp of a CreatedAt (UTC, YYYY-MM-DDTHH:MM:SSZ); "" when it is not one.
ClassMethod FromCreated(created As %String) As %String
{
	If $Get(created) '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" Quit ""
	Quit ..Normal(created)
}

/// The stamp seconds later (negative: earlier), whole seconds; "" for a stamp that is not one.
ClassMethod Shift(stamp As %String, seconds As %Integer) As %String
{
	Set stamp = ..Normal(stamp)
	If stamp = "" Quit ""
	Set horolog = $ZDateTimeH($Piece(stamp, ".", 1), 3, 1)
	Set total = ($Piece(horolog, ",", 1) * 86400) + $Piece(horolog, ",", 2) + seconds
	Quit $ZDateTime((total \ 86400)_","_(total # 86400), 3, 1)_"."_$Piece(stamp, ".", 2)
}

/// The stamp that the reading starts from: the later of Shift(markAt, OVERLAP) and the CreatedAt as a stamp, or the poll time (polledAt, a
/// stamp) when neither is known. markAt is the mark as stored, "" when there is none; created is the earliest CreatedAt of the watches, "" when
/// none has one.
ClassMethod Start(markAt As %String, created As %String, polledAt As %String) As %String
{
	Set fromMark = $Select($Get(markAt) = "": "", 1: ..Shift(markAt, -..#OVERLAP))
	Set fromCreated = ..FromCreated($Get(created))
	If (fromMark = "") && (fromCreated = "") Quit ..Normal($Get(polledAt))
	Quit $Select(fromMark = "": fromCreated, fromCreated = "": fromMark, fromMark ] fromCreated: fromMark, 1: fromCreated)
}

/// The key of a failure of the reader: h<header id> for a message header, l<log id> for a log row.
ClassMethod Key(failure As %DynamicObject) As %String
{
	Quit $Select(failure.kind = "header": "h"_failure.headerId, 1: "l"_failure.logId)
}

/// The new failures among rows (a dynamic array in the reader's order): those whose key is not in seen (comma-separated), at most limit
/// (MAXFAILURES when empty), in the same order.
ClassMethod Fresh(rows As %DynamicArray, seen As %String = "", limit As %Integer = "") As %DynamicArray
{
	If limit = "" Set limit = ..#MAXFAILURES
	Set fresh = []
	For i = 1:1:$Length(seen, ",") {
		If $Piece(seen, ",", i) '= "" Set known($Piece(seen, ",", i)) = ""
	}
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .failure) {
		If fresh.%Size() '< limit Quit
		If $Data(known(..Key(failure))) Continue
		Do fresh.%Push(failure)
	}
	Quit fresh
}

/// The mark after a poll that took the failures in taken (a dynamic array, in order, not empty): markAt, the later of the old mark and the
/// newest time taken, and seen, the failures of rows (all that the reader gave) that are in oldSeen or in taken and whose time is not before
/// Shift(markAt, OVERLAP), comma-separated in the order of rows.
ClassMethod Next(oldMarkAt As %String, oldSeen As %String, rows As %DynamicArray, taken As %DynamicArray, Output markAt As %String, Output seen As %String)
{
	Set markAt = ..Normal($Get(oldMarkAt))
	Set iterator = taken.%GetIterator()
	While iterator.%GetNext(, .failure) {
		Set known(..Key(failure)) = ""
		Set at = ..Normal(failure.at)
		If at ] markAt Set markAt = at
	}
	For i = 1:1:$Length($Get(oldSeen), ",") {
		If $Piece(oldSeen, ",", i) '= "" Set known($Piece(oldSeen, ",", i)) = ""
	}
	Set floor = ..Shift(markAt, -..#OVERLAP)
	Set seen = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .failure) {
		Set key = ..Key(failure)
		If '$Data(known(key)) Continue
		If floor ] ..Normal(failure.at) Continue
		Set seen = seen_$Select(seen = "": "", 1: ",")_key
	}
}

/// A stamp as a batch carries it: YYYY-MM-DDTHH:MM:SSZ, UTC to the second; "" for a time that is not a stamp.
ClassMethod FailedAt(stamp As %String) As %String
{
	Set stamp = ..Normal(stamp)
	If stamp = "" Quit ""
	Quit $Translate($Piece(stamp, ".", 1), " ", "T")_"Z"
}

}
