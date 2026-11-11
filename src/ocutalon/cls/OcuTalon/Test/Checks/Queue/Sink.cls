/// The queue test feed's sink (Story 23.7): takes one request at a time and, while the global ^OcuTalonTest.QueueHold is set in its namespace, waits before it
/// finishes the request, at most WAITSECONDS for each, so that the requests behind it stay in its queue. It reads and calls nothing outside this package.
Class OcuTalon.Test.Checks.Queue.Sink Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

/// The longest the sink keeps one request while it is held, in seconds.
Parameter WAITSECONDS = 120;

Method OnMessage(pRequest As Ens.StringRequest, Output pResponse As Ens.Response) As %Status
{
	Set end = $ZHorolog + ..#WAITSECONDS
	While $Get(^OcuTalonTest.QueueHold) && ($ZHorolog < end) {
		Hang 0.2
	}
	Quit $$$OK
}

}
