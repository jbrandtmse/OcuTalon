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

/// The last second that Seconds counts: 9999-12-31T23:59:59Z, Horolog day 2980013.
Parameter LASTSECOND = 257473209599;

/// The current time in UTC, YYYY-MM-DDThh:mm:ssZ, whatever the process zone.
ClassMethod NowUtc() As %String
{
	Quit $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T")_"Z"
}

/// A UTC time, YYYY-MM-DDThh:mm:ssZ, as whole seconds on one fixed scale: the seconds since the start of Horolog day 0
/// (1840-12-31). The scale ignores the process zone and daylight-saving time, so a difference of two results is the real
/// number of seconds between the two times, and (seconds \ 60) is the clock minute. Returns "" for an empty or unreadable
/// time, and for a date outside 1840-12-31 to 9999-12-31.
ClassMethod Seconds(utc As %String) As %String
{
	If $Get(utc) '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" Quit ""
	Try {
		Set horolog = $ZDateTimeH($Translate($Extract(utc, 1, 19), "T", " "), 3, 1)
	} Catch {
		Set horolog = ""
	}
	If horolog = "" Quit ""
	Quit ($Piece(horolog, ",", 1) * 86400) + $Piece(horolog, ",", 2)
}

/// A UTC time, YYYY-MM-DDThh:mm:ssZ, that is the given number of seconds (whole; negative goes back) after utc. Returns ""
/// when utc is empty or unreadable (Seconds), when seconds is not a number, and when the result falls outside 1840-12-31
/// to 9999-12-31. A fraction of a second is cut off.
ClassMethod AddSeconds(utc As %String, seconds As %Numeric) As %String
{
	Set base = ..Seconds($Get(utc))
	If base = "" Quit ""
	If '$IsValidNum($Get(seconds)) Quit ""
	Set total = base + ($Get(seconds) \ 1)
	If (total < 0) || (total > ..#LASTSECOND) Quit ""
	Quit $Translate($ZDateTime((total \ 86400) _ "," _ (total # 86400), 3, 1), " ", "T") _ "Z"
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

/// A local time, exactly YYYY-MM-DDThh:mm:ss with no zone, read in the instance zone (the zone of the process), as the UTC time
/// YYYY-MM-DDThh:mm:ssZ: the only local-to-UTC converter (AD-18). The conversion is $ZDateTime(<local Horolog>, -3). A local time
/// that the zone skips (the hour a daylight-saving change leaves out) is read one hour later: 02:30 on the spring-forward day in
/// America/New_York is 03:30 EDT, 07:30:00Z. A local time that the zone has twice (the hour a daylight-saving change repeats) is
/// read at its first instant: 01:30 on the fall-back day in America/New_York is 05:30:00Z. Returns "" for an empty or unreadable
/// value (an impossible date or hour included), for any other form, and for a result outside the range that Seconds counts.
ClassMethod FromLocal(local As %String) As %String
{
	If $Get(local) '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N Quit ""
	Set utc = ""
	Try {
		Set horolog = $ZDateTimeH($Translate(local, "T", " "), 3, 1)
		If horolog '= "" {
			Set utc = $Translate($ZDateTime($ZDateTime(horolog, -3), 3, 1), " ", "T") _ "Z"
		}
	} Catch {
		Set utc = ""
	}
	If ..Seconds(utc) = "" Quit ""
	Quit utc
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
