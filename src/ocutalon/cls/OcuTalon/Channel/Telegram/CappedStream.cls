/// A temporary binary stream that holds at most Limit bytes (Story 26.2; AD-14): Api.Download hands it to the HTTP request as the response stream, so that a file download
/// is cut off at the limit whatever the reported size says. A Write that would take it over Limit stores nothing, sets Exceeded and throws, which ends the read of the response.
Class OcuTalon.Channel.Telegram.CappedStream Extends %Stream.TmpBinary
{

/// The most bytes that the stream takes.
Property Limit As %Integer [ InitialExpression = 0, Transient ];

/// 1 once a write went over Limit.
Property Exceeded As %Boolean [ InitialExpression = 0, Transient ];

Method Write(data As %String = "") As %Status
{
	If ..Size + $Length(data) > ..Limit {
		Set ..Exceeded = 1
		Throw ##class(%Exception.General).%New("The download is over its limit")
	}
	Quit ##super(data)
}

}
