/// The Checks process of the source-run tests (Story 22.11), the QueueProbe pattern: Test.Checks.Probe with the source seams of Checks.Process replaced, so that a test runs a Tick over
/// fixture source rows and feeds the answers of the polls to OnResponse with no production, no Decide and no MCP server.
///   - SOURCEKIND is zzsources, a kind that no real Checks runs, so a fixture row is never polled by the production's own Checks item;
///   - SendPoll records the request and the completion key it was sent with (Polls) and sends nothing, or answers an error status when FailPolls says so;
///   - SourceClass gives read-only unless FeedClass says otherwise for the server and tool;
///   - StopNotice records the notice (Stops) and sends none;
///   - RealSeams 1 gives SourceClass and StopNotice back their real bodies (the classification row of the tool, and Mcp.Ops through OPSCLASS, which here is Test.Mcp.OpsProbe);
///   - PollsOff follows the real online-demo reading unless the property Demo is 1 or 0.
/// The records live in ^||ChecksProbe, which Reset (of Probe) clears with the others.
Class OcuTalon.Test.Mcp.SourceProbe Extends OcuTalon.Test.Checks.Probe
{

Parameter SOURCEKIND = "zzsources";

Parameter OPSCLASS = "OcuTalon.Test.Mcp.OpsProbe";

/// 1 to run the real SourceClass and StopNotice of Checks.Process.
Property RealSeams As %Boolean [ InitialExpression = 0, Transient ];

/// "" to follow the real online-demo setting, else 1 or 0.
Property Demo As %String [ Transient ];

Method PollsOff() As %Boolean [ Private ]
{
	If ..Demo '= "" Quit +..Demo
	Quit ##super()
}

Method SendPoll(request As OcuTalon.Bridge.Msg.Request, key As %String) As %Status [ Private ]
{
	Set ^||ChecksProbe("polls", $Increment(^||ChecksProbe("polls"))) = {"key": (key), "kind": (request.Kind), "provenance": (request.Provenance), "itemId": (request.ItemId), "ownerRef": (request.OwnerRef), "channel": (request.Channel), "summary": (request.Summary), "traceRef": (request.TraceRef), "input": (request.Input), "sessionId": (..%SessionId)}.%ToJSON()
	If $Get(^||ChecksProbe("failPolls")) Quit $SYSTEM.Status.Error(5001, "The send of the poll is refused")
	Quit $$$OK
}

Method SourceClass(server As %String, tool As %String) As %String [ Private ]
{
	If ..RealSeams Quit ##super(server, tool)
	Quit $Get(^||ChecksProbe("class", server _ "|" _ tool), "read-only")
}

Method StopNotice(row As %DynamicObject, time As %String) [ Private ]
{
	If ..RealSeams {
		Do ##super(row, time)
		Quit
	}
	Set ^||ChecksProbe("stops", $Increment(^||ChecksProbe("stops"))) = {"ref": (row.ref), "source": (row.displayName), "tool": (row.tool), "server": (row.server), "time": (time)}.%ToJSON()
}

/// The polls that SendPoll recorded, in order.
ClassMethod Polls() As %DynamicArray
{
	Set polls = []
	Set n = ""
	For {
		Set n = $Order(^||ChecksProbe("polls", n), 1, json)
		Quit:n=""
		Do polls.%Push(##class(%DynamicAbstractObject).%FromJSON(json))
	}
	Quit polls
}

/// The stop notices that StopNotice recorded, in order.
ClassMethod Stops() As %DynamicArray
{
	Set stops = []
	Set n = ""
	For {
		Set n = $Order(^||ChecksProbe("stops", n), 1, json)
		Quit:n=""
		Do stops.%Push(##class(%DynamicAbstractObject).%FromJSON(json))
	}
	Quit stops
}

/// Makes SourceClass answer the classification for the server and tool.
ClassMethod FeedClass(server As %String, tool As %String, classification As %String)
{
	Set ^||ChecksProbe("class", server _ "|" _ tool) = classification
}

/// Makes SendPoll answer an error status (on 1) or succeed (on 0).
ClassMethod FailPolls(on As %Boolean)
{
	Set ^||ChecksProbe("failPolls") = +on
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
