/// A temporary binary stream that holds at most Limit bytes (Story 26.2; AD-14): Api.Download hands it to the HTTP request as the response stream, so that a file download
/// is cut off at the limit whatever the reported size says. A Write that would take it over Limit stores nothing, sets Exceeded and throws, which ends the read of the response. A Write
/// after Deadline (a $ZHorolog; 0 for none) stores nothing, sets Late and throws the same way, so that a body that trickles in cannot hold the reading job past the deadline (DW-1341):
/// each read still waits at most the request's Timeout, so the whole read ends at most one Timeout after the deadline.
Class OcuTalon.Channel.Telegram.CappedStream Extends %Stream.TmpBinary
{

/// The most bytes that the stream takes.
Property Limit As %Integer [ InitialExpression = 0, Transient ];

/// 1 once a write went over Limit.
Property Exceeded As %Boolean [ InitialExpression = 0, Transient ];

/// The $ZHorolog after which a Write throws; 0 for none.
Property Deadline As %Numeric [ InitialExpression = 0, Transient ];

/// 1 once a write came after Deadline.
Property Late As %Boolean [ InitialExpression = 0, Transient ];

Method Write(data As %String = "") As %Status
{
	If ..Size + $Length(data) > ..Limit {
		Set ..Exceeded = 1
		Throw ##class(%Exception.General).%New("The download is over its limit")
	}
	If (..Deadline > 0) && ($ZHorolog > ..Deadline) {
		Set ..Late = 1
		Throw ##class(%Exception.General).%New("The download is over its time")
	}
	Quit ##super(data)
}

}
