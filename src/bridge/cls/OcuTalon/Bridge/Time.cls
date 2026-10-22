/// The bridge's clock (AD-2, AD-18). The bridge cannot name OcuTalon.Data.Time, so it keeps its own copy of the one
/// line that the contract needs: times are stored and sent as UTC strings, YYYY-MM-DDThh:mm:ssZ, so that string order
/// is time order.
Class OcuTalon.Bridge.Time
{

/// The current time in UTC, YYYY-MM-DDThh:mm:ssZ, whatever the process zone.
ClassMethod NowUtc() As %String
{
	Quit $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T")_"Z"
}

}
