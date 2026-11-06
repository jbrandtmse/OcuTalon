/// The bridge's clock (AD-2, AD-18, AD-20). The bridge cannot name OcuTalon.Data.Time, so it keeps its own copy of what the contract
/// needs: times are stored and sent as UTC strings, YYYY-MM-DDThh:mm:ssZ, so that string order is time order, and a day is a date
/// in the instance zone, the zone of the process (every production job inherits the container's TZ). Test.Bridge.Time compares
/// ToLocal with OcuTalon.Data.Time.ToLocal across both daylight-saving changes of 2025.
///   - NowUtc: the current UTC time;
///   - ToLocal and LocalDate: a UTC time as a local time, and as a local date (YYYY-MM-DD);
///   - DayStartUtc and DayEndUtc: the UTC times of the first instant of a local date and of the next local date, so a day lasts 23,
///     24 or 25 hours; a date whose midnight does not exist (a daylight-saving change at midnight) starts at its first instant;
///   - MsSince: whole milliseconds from a UTC timestamp, in the form of Ens.DataType.UTC, to now;
///   - PlusSeconds: a UTC time moved by a whole number of seconds, which the approval expiry (AD-11) uses;
///   - SecondsUntil: the whole seconds, rounded down, from now to a UTC time, negative for a time in the past, which a re-armed
///     approval timer reads (AD-5). Ens.Util.Time.SecondsUntil reads a time that ends in Z as local time, so the bridge never calls it;
///   - DaysCutoff: the day check and UTC cutoff of a purge, which Bridge.Purge and the host's purges share (AD-27, DW-371): now moved back a whole number of days, at least 1.
///   - Zone, CheckZone, SetZone and Apply: the instance zone's single run-time source (AD-18). The source is the IANA name in the Decide host
///     setting InstanceZone, empty for the container's TZ. Zone reads it (through Ext.Accessor.ValueFor; "" when it cannot be read), CheckZone
///     refuses a name that is not "" or an IANA zone name (letters, digits, /, _, - and + only, so no dot and no @{, at most 64 characters) that names a file under
///     /usr/share/zoneinfo, SetZone writes it (Settings.WriteRow) after CheckZone passes, and Apply makes the process convert in the zone when the
///     name changed since the process last applied one. ToLocal, LocalDate, DayStartUtc and DayEndUtc call Apply first, so every job that converts
///     follows a change with no restart, and a day ends at midnight in the zone. Apply keeps, in the process-private global ^||OcuTalon.Bridge.Time,
///     the name it last applied and the zone the process inherited, which $SYSTEM.Process.TimeZone returned at the first apply (-1 is ""); it calls
///     Process.TimeZone only on a change, puts the inherited zone back when the name becomes "", and does nothing in a process that never applied a
///     zone and reads "". It never sets $ZTIMEZONE and uses no Python.
/// Each returns "" for an unreadable input, except DaysCutoff, which returns an error status.
Class OcuTalon.Bridge.Time
{

/// The instance zone's name as the setting InstanceZone of Decide holds it: an IANA zone name, or "" for the container's TZ (and when the
/// setting cannot be read).
ClassMethod Zone() As %String
{
	Quit ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("InstanceZone")
}

/// OK when the name is "" (the container's TZ) or an IANA zone name: 1 to 64 characters of letters, digits, / _ - and + only (so no dot, no ..
/// and no @{), that names a file, not a folder, under ZONEINFO. Otherwise an error whose plain-English reason never holds the name. It changes nothing.
ClassMethod CheckZone(name As %String) As %Status
{
	Set name = $Get(name)
	If name = "" Quit $$$OK
	If name [ "@{" Quit $$$ERROR($$$GeneralError, "The time zone is refused: a setting takes a plain value and never a placeholder")
	If '$Match(name, "^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*\z") || ($Length(name) > 64) {
		Quit $$$ERROR($$$GeneralError, "The time zone must be empty (the container's own) or a name such as Europe/Berlin of at most 64 characters")
	}
	Set path = ..#ZONEINFO_name
	If '##class(%File).Exists(path) || ##class(%File).DirectoryExists(path) {
		Quit $$$ERROR($$$GeneralError, "The time zone is not one that this system knows: it must name a zone file such as Europe/Berlin")
	}
	Quit $$$OK
}

/// Stores the instance zone, an IANA zone name or "" for the container's TZ, in the Decide host setting InstanceZone (Settings.WriteRow, read
/// back), after CheckZone passes; nothing is written when it does not. Every job follows with its next conversion (Apply).
ClassMethod SetZone(name As %String) As %Status
{
	Set name = $Get(name)
	Set sc = ..CheckZone(name)
	If $$$ISERR(sc) Quit sc
	Set production = ##class(Ens.Director).GetActiveProductionName()
	If production = "" Quit $$$ERROR($$$GeneralError, "No production is active, so the time zone cannot be changed")
	Quit ##class(OcuTalon.Bridge.Settings).WriteRow(production, "Decide", "InstanceZone", name, ##class(OcuTalon.Bridge.Settings).#SETTINGROW)
}

/// Makes this process convert in the instance zone when the zone changed since the process last applied one. It reads Zone and compares it
/// with the name this process last applied, kept in ^||OcuTalon.Bridge.Time:
///   - never applied and the zone is "": nothing;
///   - never applied: the first apply, which keeps the zone the process inherited ($SYSTEM.Process.TimeZone returns it; -1 is "");
///   - the name is the one last applied: nothing;
///   - the name is "": the inherited zone is put back;
///   - otherwise the new name is applied.
/// A name that CheckZone refuses (a value written by hand) counts as "", so that Process.TimeZone is never given a name that it would
/// silently read as UTC.
ClassMethod Apply()
{
	Set name = ..Zone()
	Set known = $Data(^||OcuTalon.Bridge.Time("applied"))
	If known {
		If name = ^||OcuTalon.Bridge.Time("applied") Quit
	} ElseIf name = "" {
		Quit
	}
	Set zone = $Select($$$ISOK(..CheckZone(name)): name, 1: "")
	If 'known {
		If zone = "" Quit
		Set inherited = $SYSTEM.Process.TimeZone(zone)
		Set ^||OcuTalon.Bridge.Time("inherited") = $Select(inherited = -1: "", 1: inherited)
	} Else {
		Do $SYSTEM.Process.TimeZone($Select(zone = "": ^||OcuTalon.Bridge.Time("inherited"), 1: zone))
	}
	Set ^||OcuTalon.Bridge.Time("applied") = name
}

/// The folder of the zone files.
Parameter ZONEINFO = "/usr/share/zoneinfo/";

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
	Do ..Apply()
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
	Do ..Apply()
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

/// The UTC time, YYYY-MM-DDThh:mm:ssZ, that lies the whole number of seconds (negative for earlier) after the UTC time. Returns "" for an
/// empty or unreadable time, for a count of seconds that is not a whole number, and for a result outside the calendar.
ClassMethod PlusSeconds(utc As %String, seconds As %Integer) As %String
{
	If utc '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" Quit ""
	If seconds '? .1"-"1.N Quit ""
	Set days = $ZDateH($Piece(utc, "T", 1), 3, , , , , , , "")
	Set time = $ZTimeH($Piece($Piece(utc, "T", 2), "Z", 1), 1, "")
	If (days = "") || (time = "") Quit ""
	Set total = days * 86400 + time + seconds
	If total < 0 Quit ""
	Set whole = total \ 86400
	Set result = ""
	Try {
		Set result = $ZDate(whole, 3)_"T"_$ZTime(total - (whole * 86400), 1)_"Z"
	} Catch exception {
		Set result = ""
	}
	Quit result
}

/// The whole seconds, rounded down, from now to the UTC time YYYY-MM-DDThh:mm:ssZ: negative when the time is in the past. Returns "" for
/// an empty or unreadable time. The time is read as UTC whatever the process zone.
ClassMethod SecondsUntil(utc As %String) As %Integer
{
	If utc '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" Quit ""
	Set days = $ZDateH($Piece(utc, "T", 1), 3, , , , , , , "")
	Set time = $ZTimeH($Piece($Piece(utc, "T", 2), "Z", 1), 1, "")
	If (days = "") || (time = "") Quit ""
	Set now = $ZTimeStamp
	Set delta = (days - +now) * 86400 + (time - $Piece(now, ",", 2))
	Set whole = delta \ 1
	If whole > delta Set whole = whole - 1
	Quit whole
}

/// The cutoff of a purge (AD-27, DW-371): the UTC time now, YYYY-MM-DDThh:mm:ssZ (default NowUtc), moved back daysToKeep whole days by date
/// arithmetic on the UTC date, so the time of day is kept. daysToKeep must be a whole number of at least 1: anything else ("", 0, -1, 1.5,
/// abc, 00) is an error status that names the caller, and so is a now that is given and unreadable; cutoff is "" then. Otherwise the result
/// is OK, and cutoff is "" when it falls before the first date of the calendar, which means nothing is old enough to purge. A caller deletes
/// nothing on an error, and nothing older than an empty cutoff.
ClassMethod DaysCutoff(daysToKeep As %String, caller As %String, Output cutoff As %String, now As %String = "") As %Status
{
	Set cutoff = ""
	If (daysToKeep '? 1.N) || (+daysToKeep < 1) {
		Quit $SYSTEM.Status.Error(5001, caller_" needs a whole number of days, at least 1, not '"_$Extract(daysToKeep, 1, 40)_"'")
	}
	If now = "" Set now = ..NowUtc()
	Set days = ""
	If now ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" {
		Set time = $ZTimeH($Piece($Piece(now, "T", 2), "Z", 1), 1, "")
		If time '= "" Set days = $ZDateH($Piece(now, "T", 1), 3, , , , , , , "")
	}
	If days = "" Quit $SYSTEM.Status.Error(5001, caller_" needs a UTC time, YYYY-MM-DDThh:mm:ssZ, not '"_$Extract(now, 1, 40)_"'")
	Set day = days - daysToKeep
	If day >= 0 Set cutoff = $ZDate(day, 3)_"T"_$Piece(now, "T", 2)
	Quit $SYSTEM.Status.OK()
}

}
