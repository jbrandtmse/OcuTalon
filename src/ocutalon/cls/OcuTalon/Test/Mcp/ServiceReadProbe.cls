/// A test double of OcuTalon.Mcp.ServiceRead (Story 28.3): the same two tools, except that the caller comes from the process-private global ^||OcuTalonMcpCaller instead of $Username, and the
/// reads can be failed or watched. It records, in process-private globals, whether a bridge context was active whenever the caller was asked for (^||OcuTalonMcpActive, the largest value seen),
/// whether the ownership reads ran (^||OcuTalonMcpRead), and fails the read that ^||OcuTalonMcpUnread names (checks, incidents or session: a failed read or lookup; checks-throw or incidents-throw: a read that throws). Test.Mcp.ServiceTools calls it. It is no test case.
Class OcuTalon.Test.Mcp.ServiceReadProbe Extends OcuTalon.Mcp.ServiceRead
{

ClassMethod Caller() As %String [ Private ]
{
	Set active = +##class(OcuTalon.Bridge.Context).Active()
	If active > +$Get(^||OcuTalonMcpActive) Set ^||OcuTalonMcpActive = active
	Quit $Get(^||OcuTalonMcpCaller)
}

ClassMethod Lookup(irisUser As %String, Output sc As %Status) As %String [ Private ]
{
	If $Get(^||OcuTalonMcpUnread) = "session" {
		Set sc = $SYSTEM.Status.Error(5001, "The double fails the session lookup")
		Quit ""
	}
	Quit ##super(irisUser, .sc)
}

ClassMethod Results(owner As %String, Output results As %DynamicArray) As %DynamicObject [ Private ]
{
	Set ^||OcuTalonMcpRead = +$Get(^||OcuTalonMcpRead) + 1
	If $Get(^||OcuTalonMcpUnread) = "checks-throw" Throw ##class(%Exception.General).%New("probe", 5001, , "the double throws in the read of the checks")
	If $Get(^||OcuTalonMcpUnread) = "checks" {
		Set results = []
		Quit {"ok": false, "message": "the double fails the read of the checks"}
	}
	Quit ##super(owner, .results)
}

ClassMethod ReadIncidents(owner As %String, Output rows As %ListOfObjects, Output sc As %Status) [ Private ]
{
	Set ^||OcuTalonMcpRead = +$Get(^||OcuTalonMcpRead) + 1
	If $Get(^||OcuTalonMcpUnread) = "incidents-throw" Throw ##class(%Exception.General).%New("probe", 5001, , "the double throws in the read of the incidents")
	If $Get(^||OcuTalonMcpUnread) = "incidents" {
		Set rows = ##class(%ListOfObjects).%New()
		Set sc = $SYSTEM.Status.Error(5001, "The double fails the read of the incidents")
		Quit
	}
	Do ##super(owner, .rows, .sc)
}

}
