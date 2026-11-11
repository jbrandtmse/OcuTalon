Include Ensemble

/// The fixture of the queue-backlog test feed (Story 23.7; AD-22): it installs OcuTalon.Test.Checks.Queue in a namespace of its own, holds and releases the sink, fills its queue,
/// reads it and removes everything it made. It is the evaluation set's feed fixture with its own names (OcuTalon.Test.Eval.Feed.Fixture is fully parameterised by NAMESPACE,
/// DATABASE, RESOURCE, PRODUCTION and CODEPACKAGE), so Install, Remove and Leftovers are its, with the same guard and the same single grant.
///   - THROWAWAYS ONLY. Install refuses, writes nothing and names the reason unless the folder of the evaluation set (Mount) exists, which only docker/tests/compose.throwaway.yml
///     mounts. The grant it makes, Read on RESOURCE added to the Resources of the service role and nothing else, is taken out again by Remove. Nothing in the product's install,
///     the judges' compose file or the demo host names it.
///   - Hold sets the global ^OcuTalonTest.QueueHold in the feed's namespace and Release clears it; Fill(count) sends count requests to the source; Queued() is the number of requests in the
///     sink's queue (messages in the status Queued whose target is the sink); Snapshot() is the feed's state as a JSON text: the count of headers by status, the enabled flag and the
///     state of each item, and the production's state.
///   - The code that runs in the feed's namespace calls no OcuTalon class outside this package.
Class OcuTalon.Test.Checks.Queue.Fixture Extends OcuTalon.Test.Eval.Feed.Fixture
{

Parameter NAMESPACE = "QUEUEFEED";

Parameter DATABASE = "QUEUEFEED_DATA";

Parameter RESOURCE = "%DB_QUEUEFEED_DATA";

Parameter PRODUCTION = "OcuTalon.Test.Checks.Queue.Production";

Parameter CODEPACKAGE = "OcuTalon.Test.Checks.Queue";

/// The item that takes the requests and holds the queue, and the service that sends them.
Parameter SINK = "QueueSink";

Parameter SOURCE = "QueueIn";

/// Makes the sink keep every request it is given, from now on.
ClassMethod Hold()
{
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Set ^OcuTalonTest.QueueHold = 1
}

/// Lets the sink go on: the requests in its queue are taken one after the other.
ClassMethod Release()
{
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Kill ^OcuTalonTest.QueueHold
}

/// Sends count requests to the source, each in a session of its own. The status is the first send that failed.
ClassMethod Fill(count As %Integer) As %Status
{
	Set sc = $$$OK
	Try {
		New $NAMESPACE
		Set $NAMESPACE = ..#NAMESPACE
		$$$ThrowOnError(##class(Ens.Director).CreateBusinessService(..#SOURCE, .service))
		For i = 1:1:count {
			Set request = ##class(Ens.StringRequest).%New()
			Set request.StringValue = "zz queue "_i
			$$$ThrowOnError(service.ProcessInput(request))
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The number of requests in the sink's queue: the headers in the status Queued whose target is the sink.
ClassMethod Queued() As %Integer
{
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE Status = ? AND TargetConfigName = ?", $$$eMessageStatusQueued, ..#SINK)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The feed's state as a JSON text: {"headers": {"<status>": count}, "items": {"<item>": {"enabled", "status"}}, "production": "<state>"}, with the members in name order.
ClassMethod Snapshot() As %String
{
	New $NAMESPACE
	Set $NAMESPACE = ..#NAMESPACE
	Set headers = {}
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Status, COUNT(*) FROM Ens.MessageHeader GROUP BY Status ORDER BY Status")
	While rs.%Next() {
		Do headers.%Set(rs.%GetData(1), +rs.%GetData(2), "number")
	}
	Set items = {}
	Kill names
	Set item = ""
	For {
		Set item = $Order($$$ConfigRoot(item))
		Quit:item=""
		If item = "%Production" Continue
		Set names(item) = ""
	}
	Set item = ""
	For {
		Set item = $Order(names(item))
		Quit:item=""
		Do items.%Set(item, {"enabled": (''$Get($$$ConfigIsEnabled(item))), "status": ($$$GetHostMonitor(item, "%Status"))})
	}
	Do ##class(Ens.Director).GetProductionStatus(.name, .state)
	Set production = $Get(state)
	Quit {"headers": (headers), "items": (items), "production": (production)}.%ToJSON()
}

}
