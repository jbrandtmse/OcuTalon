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
/// or a time cannot be read.
ClassMethod NextReset(now As %String = "") As %String
{
	Set anchor = $Get(^OcuTalonPublic("resetAnchor"))
	Set interval = $Get(^OcuTalonPublic("resetIntervalHours"))
	If (anchor = "") || (interval = "") || '$IsValidNum(interval) Quit ""
	Set step = interval * 3600 \ 1
	If step < 1 Quit ""
	Try {
		Set from = ..ToSeconds(anchor)
		Set at = $Select(now = "": ..ToSeconds(..UtcNow()), 1: ..ToSeconds(now))
	} Catch {
		Return ""
	}
	Set next = $Select(at < from: from, 1: from + ((at - from \ step + 1) * step))
	Quit ..FromSeconds(next)
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

/// Seconds since the horolog epoch for a UTC ISO 8601 time. Fractions of a second and the "Z" are dropped.
ClassMethod ToSeconds(time As %String) As %Integer [ Private ]
{
	Set horolog = $ZDateTimeH($Translate($Extract(time, 1, 19), "T", " "), 3, 1)
	Quit $Piece(horolog, ",", 1) * 86400 + $Piece(horolog, ",", 2)
}

ClassMethod FromSeconds(seconds As %Integer) As %String [ Private ]
{
	Quit $Translate($ZDateTime((seconds \ 86400)_","_(seconds # 86400), 3, 1), " ", "T")_"Z"
}

}
