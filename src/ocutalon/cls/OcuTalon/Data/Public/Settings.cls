/// The only reader and writer of the public settings global, ^OcuTalonPublic, which lives in OCUTALON_PUBLIC.
/// Every other class and script reaches the global through this one (AD-19).
/// The class sits in a package that is mapped to the public database, so it references only $SYSTEM.Status
/// and ObjectScript functions (AD-3).
Class OcuTalon.Data.Public.Settings
{

/// The fixed keys that can be read and written. Times are UTC ISO 8601 with "Z".
Parameter KEYS = "onlineDemo,demoUser,demoPassword,readonlyUser,readonlyPassword,resetIntervalHours,resetAnchor,lastReset,lastResetKind,proxyAddress,connectionCap,connectionReserve,messageAllowance";

/// The readiness key: read with Get, written only by ClearReady and SetReady.
Parameter READY = "ready";

/// The name of the global, without the caret: what a mapping names (the Demo step maps it into OCUORDERS, AD-3).
Parameter GLOBALNAME = "OcuTalonPublic";

/// Returns the stored value of a fixed key, or of "ready". No default is applied: a key that was never set,
/// or was removed, reads as "". Any other key gives an error status in sc and "".
ClassMethod Get(key As %String, Output sc As %Status) As %String
{
	Set sc = $SYSTEM.Status.OK()
	If (key '= ..#READY) && '..IsFixedKey(key) {
		Set sc = ..RefusedKey(key)
		Quit ""
	}
	Quit $Get(^OcuTalonPublic(key))
}

/// Stores the value of a fixed key. "" removes the key. "ready" and any other key are refused with an error
/// status that names the key, and nothing is stored.
ClassMethod Set(key As %String, value As %String) As %Status
{
	If '..IsFixedKey(key) Quit ..RefusedKey(key)
	If value = "" {
		Kill ^OcuTalonPublic(key)
	} Else {
		Set ^OcuTalonPublic(key) = value
	}
	Quit $SYSTEM.Status.OK()
}

/// Removes readiness. Called first at every start.
ClassMethod ClearReady() As %Status
{
	Kill ^OcuTalonPublic(..#READY)
	Quit $SYSTEM.Status.OK()
}

/// Stores readiness (1). Called last in a start, after every step has run.
ClassMethod SetReady() As %Status
{
	Set ^OcuTalonPublic(..#READY) = 1
	Quit $SYSTEM.Status.OK()
}

/// The next scheduled reset after now, as UTC ISO 8601 with "Z": the first moment of the form
/// resetAnchor + k * resetIntervalHours (k >= 0) that is later than now. now defaults to the current UTC time.
/// Returns "" when there is no anchor, the interval is empty, zero, negative or not a number,
/// or a time cannot be read. It reads only the anchor and the interval, so the last reset and its kind never move the schedule (AD-25).
ClassMethod NextReset(now As %String = "") As %String
{
	Set anchor = $Get(^OcuTalonPublic("resetAnchor"))
	Set interval = $Get(^OcuTalonPublic("resetIntervalHours"))
	If (anchor = "") || (interval = "") || '$IsValidNum(interval) Quit ""
	Set step = interval * 3600 \ 1
	If step < 1 Quit ""
	Set from = ..ToSeconds(anchor)
	Set at = ..ToSeconds($Select(now = "": ..UtcNow(), 1: now))
	If (from = "") || (at = "") Quit ""
	Set next = $Select(at < from: from, 1: from + ((at - from \ step + 1) * step))
	Quit ..FromSeconds(next)
}

/// The seconds that the reset soon rule counts: reset soon is 0 < SecondsToReset <= RESETSOONSECONDS.
Parameter RESETSOONSECONDS = 300;

/// The whole seconds from now to NextReset(now), or "" when there is no next reset or now cannot be read.
/// now defaults to the current UTC time.
ClassMethod SecondsToReset(now As %String = "") As %Integer
{
	If now = "" Set now = ..UtcNow()
	Set next = ..NextReset(now)
	If next = "" Quit ""
	Set at = ..ToSeconds(now)
	If at = "" Quit ""
	Quit ..ToSeconds(next) - at
}

/// 1 when the next reset is at most RESETSOONSECONDS away and still ahead; 0 otherwise, also with no next reset.
/// The banner of the page and the sign-in notice of the splash share this one rule.
ClassMethod ResetSoon(now As %String = "") As %Boolean
{
	Set seconds = ..SecondsToReset(now)
	Quit (seconds '= "") && (seconds > 0) && (seconds <= ..#RESETSOONSECONDS)
}

/// 1 when key is one of the fixed keys, matched as a whole name.
ClassMethod IsFixedKey(key As %String) As %Boolean [ Private ]
{
	Quit (key '= "") && ''$ListFind($ListFromString(..#KEYS), key)
}

ClassMethod RefusedKey(key As %String) As %Status [ Private ]
{
	Quit $SYSTEM.Status.Error(5001, "Public setting '"_key_"' is not one of the fixed keys")
}

/// The current time in UTC, ISO 8601 with "Z".
ClassMethod UtcNow() As %String [ Private ]
{
	Quit $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T")_"Z"
}

/// Seconds since the horolog epoch for a UTC time of exactly the form YYYY-MM-DDThh:mm:ssZ with a real date and time
/// (the rule of the Public step's time variables). "" for anything else; it never throws.
ClassMethod ToSeconds(utc As %String) As %Integer
{
	If utc '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" Quit ""
	Try {
		Set horolog = $ZDateTimeH($Translate($Extract(utc, 1, 19), "T", " "), 3, 1, , , , , , , "")
	} Catch {
		Set horolog = ""
	}
	If horolog = "" Quit ""
	Quit $Piece(horolog, ",", 1) * 86400 + $Piece(horolog, ",", 2)
}

/// The UTC time, to the second and with "Z", of a number of seconds since the horolog epoch.
ClassMethod FromSeconds(seconds As %Integer) As %String
{
	Quit $Translate($ZDateTime((seconds \ 86400)_","_(seconds # 86400), 3, 1), " ", "T")_"Z"
}

/// A UTC time moved by a number of seconds (negative moves it back); "" for a time ToSeconds cannot read or a result that
/// is not a time.
ClassMethod Shift(utc As %String, seconds As %Integer) As %String
{
	Set total = ..ToSeconds(utc)
	If total = "" Quit ""
	Try {
		Set shifted = ..FromSeconds(total + seconds)
	} Catch {
		Set shifted = ""
	}
	Quit shifted
}

}
