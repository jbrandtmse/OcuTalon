/// The only converter of times outside the bridge (AD-18). Times are stored and sent as UTC strings,
/// YYYY-MM-DDThh:mm:ssZ, so that string order is time order; they are rendered in the instance zone through ToLocal,
/// and a time inside message text is formatted by ForMessage, the only place that formats a date for a message.
/// The instance zone is the TZ environment variable of the process.
Class OcuTalon.Data.Time
{

/// The English weekday names, Sunday first, so that the output does not depend on the locale.
Parameter WEEKDAYS = "Sunday,Monday,Tuesday,Wednesday,Thursday,Friday,Saturday";

/// The English short month names, so that the output does not depend on the locale.
Parameter MONTHS = "Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec";

/// The current time in UTC, YYYY-MM-DDThh:mm:ssZ, whatever the process zone.
ClassMethod NowUtc() As %String
{
	Quit $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T")_"Z"
}

/// A UTC time, YYYY-MM-DDThh:mm:ssZ, as local YYYY-MM-DDThh:mm:ss in the instance zone, daylight-saving time included.
/// Returns "" for an empty or unreadable time.
ClassMethod ToLocal(utc As %String) As %String
{
	If utc '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" Quit ""
	Set horolog = $ZDateTimeH(utc, 3, 7, , , , , , , "")
	If horolog = "" Quit ""
	Quit $Translate($ZDateTime(horolog, 3, 1), " ", "T")
}

/// A UTC time as message text, in the instance zone, relative to the local date of now (UTC, default NowUtc()):
/// "14:12" on the same local date, "Thursday at 14:12" from 1 to 6 days before or after, "Oct 9 at 14:12" from 7 days on,
/// and "Dec 30, 2025 at 10:00" in another year. The local date decides, not the distance in hours. The text has no zone
/// suffix: the online demo's " ET" is the renderer's. Returns "" for an unreadable utc or an unreadable non-empty now.
ClassMethod ForMessage(utc As %String, now As %String = "") As %String
{
	Set local = ..ToLocal(utc)
	If local = "" Quit ""
	Set nowLocal = ..ToLocal($Select(now = "": ..NowUtc(), 1: now))
	If nowLocal = "" Quit ""
	Set days = $ZDateH($Piece(local, "T", 1), 3)
	Set daysNow = $ZDateH($Piece(nowLocal, "T", 1), 3)
	Set clock = $Extract(local, 12, 16)
	Set apart = days - daysNow
	If apart = 0 Quit clock
	If $Select(apart < 0: -apart, 1: apart) < 7 Quit $Piece(..#WEEKDAYS, ",", $ZDate(days, 10) + 1)_" at "_clock
	Set date = $Piece(..#MONTHS, ",", +$Extract(local, 6, 7))_" "_(+$Extract(local, 9, 10))
	If $Extract(local, 1, 4) '= $Extract(nowLocal, 1, 4) Set date = date_", "_$Extract(local, 1, 4)
	Quit date_" at "_clock
}

/// The instance zone: the TZ environment variable of the process, or UTC when TZ is unset.
ClassMethod Zone() As %String
{
	Set zone = $SYSTEM.Util.GetEnviron("TZ")
	Quit $Select(zone = "": "UTC", 1: zone)
}

}
