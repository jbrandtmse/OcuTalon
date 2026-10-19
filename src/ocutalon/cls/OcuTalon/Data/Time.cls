/// The only converter of times outside the bridge (AD-18). Times are stored and sent as UTC strings,
/// YYYY-MM-DDThh:mm:ssZ, so that string order is time order; they are rendered in the instance zone through ToLocal.
/// The instance zone is the TZ environment variable of the process.
Class OcuTalon.Data.Time
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

/// The instance zone: the TZ environment variable of the process, or UTC when TZ is unset.
ClassMethod Zone() As %String
{
	Set zone = $SYSTEM.Util.GetEnviron("TZ")
	Quit $Select(zone = "": "UTC", 1: zone)
}

}
