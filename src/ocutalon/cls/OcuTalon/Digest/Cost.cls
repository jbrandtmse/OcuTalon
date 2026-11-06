/// The model cost that a digest reports (AD-18, AD-20, AD-32; Story 17.6): the cost of the previous day, from midnight to midnight in the instance zone.
/// It sums OcuTalon.Bridge.Data.Usage.CostUSD over the rows whose OwnerRef is the session or instance (what the session spent, and what the instance
/// spent for it) and never eval (the evaluation's rows), and whose RecordedAt is at or after yesterday's midnight and before today's midnight. The two
/// midnights are local times that OcuTalon.Data.Time.FromLocal converts to UTC, so the day is the local day whatever the zone of the process, and a
/// daylight-saving day is 23 or 25 hours long. Lane A.
Class OcuTalon.Digest.Cost
{

/// The owner of the costs that no session owns.
Parameter INSTANCE = "instance";

/// Yesterday's cost in US dollars as a number (0 when nothing was spent), for the session, with now as the current UTC time (the default is the clock).
/// The status is an error when now cannot be read or the rows cannot be summed; the cost is then 0 and must not be used.
ClassMethod Yesterday(sessionRef As %String, now As %String = "", Output sc As %Status) As %Numeric
{
	Set sc = $$$OK
	Set total = 0
	Try {
		Set from = ..Midnight($Select($Get(now) = "": ##class(OcuTalon.Data.Time).NowUtc(), 1: now), -1)
		Set to = ..Midnight($Select($Get(now) = "": ##class(OcuTalon.Data.Time).NowUtc(), 1: now), 0)
		If (from = "") || (to = "") $$$ThrowStatus($SYSTEM.Status.Error(5001, "OcuTalon.Digest.Cost cannot read the time '"_$Extract($Get(now), 1, 40)_"': it is YYYY-MM-DDThh:mm:ssZ in UTC"))
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT SUM(CostUSD) FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef IN (?, ?) AND RecordedAt >= ? AND RecordedAt < ?", $Get(sessionRef), ..#INSTANCE, from, to)
		If result.%SQLCODE < 0 $$$ThrowStatus($SYSTEM.Status.Error(5001, "Summing the cost failed: "_result.%Message))
		If result.%Next() Set total = +result.%GetData(1)
	} Catch exception {
		Set sc = exception.AsStatus()
		Set total = 0
	}
	Quit total
}

/// The UTC time of the local midnight that starts the local day of now moved by days whole days (0 is today's, -1 yesterday's). "" for a time that
/// cannot be read.
ClassMethod Midnight(now As %String, days As %Integer) As %String
{
	Set local = ##class(OcuTalon.Data.Time).ToLocal(now)
	If local = "" Quit ""
	Set date = $ZDate($ZDateH($Piece(local, "T", 1), 3) + days, 3)
	Quit ##class(OcuTalon.Data.Time).FromLocal(date_"T00:00:00")
}

}
