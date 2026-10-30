/// The arithmetic of IncidentManager's grouping and settle rule (pure; AD-5, AD-15, AD-19). It holds nothing: the incident and group rows are the state.
///   - Pattern is the error pattern that makes two failures the same cause (with the item): the error text with each run of digits replaced by #,
///     each run of white space collapsed to one space and the ends trimmed, so a date or an id that differs between messages stays in one group while a
///     name does not.
///   - Values gives the settle settings (Data.Setting keys watch.settleQuietSeconds and watch.settleMaxSeconds); a value that is not a positive whole
///     number gives the default.
///   - Wait says how long the settle rule still runs: it ends when LastAt is quiet seconds ago or FirstAt is max seconds ago, whichever comes first.
///   - Alarm gives the seconds of the waiter's next alarm: the wait, at most LONGESTALARM, because only two business processes hold a timer longer than two
///     minutes (AD-5). The waiter re-reads the rows on each wake, so a longer wait is several alarms.
///   - Quiet says whether an incident has been quiet for longer than a number of seconds: 1 when lastAt is more than that before now, 0 when it is not or a
///     stamp is not one (IncidentManager's closeQuiet).
///   - Hold gives a group's Seen set after a batch, and which of the batch's keys were new. A key already in the set is never counted again.
///   - Window gives the keys of a Seen set that one dry-run ask covers (Story 7.6): those after the ask's from mark up to and including its to mark. The first ask
///     has no from mark and starts at the first key; a window with no end, or one that ends before it starts, holds no key.
/// A stamp is UTC, YYYY-MM-DDTHH:MM:SSZ, as the failures of a batch carry it.
Class OcuTalon.Watch.Settle
{

/// The settings keys and their defaults, in seconds.
Parameter QUIETKEY = "watch.settleQuietSeconds";

Parameter MAXKEY = "watch.settleMaxSeconds";

Parameter QUIETDEFAULT = 10;

Parameter MAXDEFAULT = 30;

/// The most keys that a group's Seen set holds: its newest failures. The poller re-sends at most the last poll's failures (Mark MAXFAILURES per
/// production), so this is two polls' worth.
Parameter SEENMAX = 1000;

/// The longest alarm of the settle waiter, in seconds (AD-5: two minutes).
Parameter LONGESTALARM = 120;

/// The error pattern of an error text (see the class description).
ClassMethod Pattern(text As %String) As %String
{
	Set pattern = ""
	Set last = ""
	Set white = $Char(9, 10, 11, 12, 13, 32)
	For i = 1:1:$Length($Get(text)) {
		Set char = $Extract(text, i)
		If char ? 1N {
			If last '= "digit" Set pattern = pattern_"#"
			Set last = "digit"
		} ElseIf $Find(white, char) {
			If last '= "white" Set pattern = pattern_" "
			Set last = "white"
		} Else {
			Set pattern = pattern_char
			Set last = ""
		}
	}
	Quit $ZStrip(pattern, "<>", " ")
}

/// The settle settings in seconds: quiet and max, each the Data.Setting value when it is a positive whole number, else the default.
ClassMethod Values(Output quiet As %Integer, Output max As %Integer)
{
	Set quiet = ..Positive(##class(OcuTalon.Data.Setting).Get(..#QUIETKEY, ..#QUIETDEFAULT), ..#QUIETDEFAULT)
	Set max = ..Positive(##class(OcuTalon.Data.Setting).Get(..#MAXKEY, ..#MAXDEFAULT), ..#MAXDEFAULT)
}

/// The value as a number when it is a positive whole number, else the default.
ClassMethod Positive(value As %String, default As %Integer) As %Integer [ Private ]
{
	Quit $Select(($Get(value) ? 1.N) && (+value > 0): +value, 1: default)
}

/// The seconds that the settle rule still has to run: 0 when it has ended (now is quiet or more after lastAt, or max or more after firstAt, or a stamp is
/// not one), else the whole seconds until the earlier of lastAt + quiet and firstAt + max, at least 1.
ClassMethod Wait(firstAt As %String, lastAt As %String, now As %String, quiet As %Integer, max As %Integer) As %Integer
{
	Set first = ..Seconds($Get(firstAt))
	Set last = ..Seconds($Get(lastAt))
	Set current = ..Seconds($Get(now))
	If (first = "") || (last = "") || (current = "") Quit 0
	Set end = $Select((last + quiet) < (first + max): last + quiet, 1: first + max)
	Quit $Select(current '< end: 0, 1: end - current)
}

/// 1 when lastAt is more than seconds before now (both stamps), 0 when it is that or less or when a stamp cannot be read.
ClassMethod Quiet(lastAt As %String, now As %String, seconds As %Integer) As %Boolean
{
	Set last = ..Seconds($Get(lastAt))
	Set current = ..Seconds($Get(now))
	If (last = "") || (current = "") Quit 0
	Quit ((current - last) > seconds)
}

/// The seconds of the waiter's next alarm for a wait of seconds: the wait, at most LONGESTALARM.
ClassMethod Alarm(seconds As %Integer) As %Integer
{
	Quit $Select(seconds > ..#LONGESTALARM: ..#LONGESTALARM, 1: seconds)
}

/// A stamp (UTC to the second, as OcuTalon.Data.Time gives it) as seconds since the start of the IRIS calendar, "" when it is not a stamp. The deadline of a
/// wait (Fix.Executor) is read with it, as the settle rule is.
ClassMethod Seconds(stamp As %String) As %Integer
{
	If stamp '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" Quit ""
	Set seconds = ""
	Try {
		Set horolog = $ZDateTimeH($Extract($Translate(stamp, "T", " "), 1, 19), 3, 1)
		Set seconds = ($Piece(horolog, ",", 1) * 86400) + $Piece(horolog, ",", 2)
	} Catch {
		Set seconds = ""
	}
	Quit seconds
}

/// The Seen set after a batch: seen (comma-separated, oldest first) followed by the keys (comma-separated, in order) that it does not hold, cut to
/// its newest SEENMAX keys. fresh is those new keys, comma-separated in order; a key twice in keys is new once.
ClassMethod Hold(seen As %String, keys As %String, Output fresh As %String) As %String
{
	Set fresh = ""
	Set seen = $Get(seen)
	For i = 1:1:$Length(seen, ",") {
		If $Piece(seen, ",", i) '= "" Set known($Piece(seen, ",", i)) = ""
	}
	For i = 1:1:$Length($Get(keys), ",") {
		Set key = $Piece(keys, ",", i)
		If (key = "") || $Data(known(key)) Continue
		Set known(key) = ""
		Set fresh = fresh_$Select(fresh = "": "", 1: ",")_key
	}
	If fresh = "" Quit seen
	Set all = seen_$Select(seen = "": "", 1: ",")_fresh
	Set count = $Length(all, ",")
	Quit $Select(count > ..#SEENMAX: $Piece(all, ",", count - ..#SEENMAX + 1, count), 1: all)
}

/// The keys of seen (comma-separated, oldest first) after the key from up to and including the key to, comma-separated, in order. from empty, or not in seen,
/// starts at the first key. to empty, not in seen, or not after the start gives "": an ask with no end covers nothing.
ClassMethod Window(seen As %String, from As %String, to As %String) As %String
{
	Set seen = $Get(seen)
	Set from = $Get(from)
	Set to = $Get(to)
	Set count = $Length(seen, ",")
	Set start = 1
	Set end = ""
	Set foundFrom = ""
	For i = 1:1:count {
		Set key = $Piece(seen, ",", i)
		If key = "" Continue
		If (from '= "") && (key = from) && (foundFrom = "") Set foundFrom = i
		If (to '= "") && (key = to) && (end = "") Set end = i
	}
	If foundFrom '= "" Set start = foundFrom + 1
	If (end = "") || (end < start) Quit ""
	Quit $Piece(seen, ",", start, end)
}

}
