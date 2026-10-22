/// The bridge's clock (AD-2, AD-18, AD-20). The bridge cannot name OcuTalon.Data.Time, so it keeps its own copy of what the contract
/// needs: times are stored and sent as UTC strings, YYYY-MM-DDThh:mm:ssZ, so that string order is time order, and a day is a date
/// in the instance zone, the zone of the process (every production job inherits the container's TZ). Test.Bridge.Time compares
/// ToLocal with OcuTalon.Data.Time.ToLocal across both daylight-saving changes of 2025.
///   - NowUtc: the current UTC time;
///   - ToLocal and LocalDate: a UTC time as a local time, and as a local date (YYYY-MM-DD);
///   - DayStartUtc and DayEndUtc: the UTC times of the first instant of a local date and of the next local date, so a day lasts 23,
///     24 or 25 hours; a date whose midnight does not exist (a daylight-saving change at midnight) starts at its first instant;
///   - MsSince: whole milliseconds from a UTC timestamp, in the form of Ens.DataType.UTC, to now.
/// Each returns "" for an unreadable input.
Class OcuTalon.Bridge.Time
{

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

/// The local date, YYYY-MM-DD, of a UTC time, or "" for an unreadable time.
ClassMethod LocalDate(utc As %String) As %String
{
	Quit $Piece(..ToLocal(utc), "T", 1)
}

/// The UTC time, YYYY-MM-DDThh:mm:ssZ, of the first instant of the local date YYYY-MM-DD, or "" for an unreadable date.
ClassMethod DayStartUtc(day As %String) As %String
{
	If day '? 4N1"-"2N1"-"2N Quit ""
	Set days = $ZDateH(day, 3, , , , , , , "")
	If days = "" Quit ""
	Set utc = ""
	Try {
		Set utc = $Translate($ZDateTime($ZDateTime(days_",0", -3), 3, 1), " ", "T")_"Z"
	} Catch exception {
		Set utc = ""
	}
	Quit utc
}

/// The UTC time of the start of the local date after YYYY-MM-DD, which is the end of that date, or "" for an unreadable date.
ClassMethod DayEndUtc(day As %String) As %String
{
	If day '? 4N1"-"2N1"-"2N Quit ""
	Set days = $ZDateH(day, 3, , , , , , , "")
	If days = "" Quit ""
	Set next = ""
	Try {
		Set next = $ZDate(days + 1, 3)
	} Catch exception {
		Set next = ""
	}
	Quit ..DayStartUtc(next)
}

/// The whole milliseconds from a UTC timestamp, YYYY-MM-DD hh:mm:ss or YYYY-MM-DD hh:mm:ss.fff, to now; 0 for a timestamp that
/// lies ahead of the clock. Returns "" for an empty or unreadable timestamp. The timestamp is read as UTC whatever the process zone.
ClassMethod MsSince(timestamp As %String) As %Integer
{
	If timestamp '? 4N1"-"2N1"-"2N1" "2N1":"2N1":"2N.1(1"."1.N) Quit ""
	Set days = $ZDateH($Piece(timestamp, " ", 1), 3, , , , , , , "")
	Set seconds = $ZTimeH($Piece(timestamp, " ", 2), 1, "")
	If (days = "") || (seconds = "") Quit ""
	Set now = $ZTimeStamp
	Set elapsed = ((+now - days) * 86400 + ($Piece(now, ",", 2) - seconds)) * 1000
	Quit $Select(elapsed < 0: 0, 1: $Number(elapsed, 0))
}

}
