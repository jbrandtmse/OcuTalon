/// A Checks process whose queue-backlog reads are under test control (test only; Story 23.7). Test.Checks.Queues calls OnRequest of a shadow instance of it, in
/// its own process, so that a Tick runs the real RunQueues over fixture rows and no namespace is read. It extends Test.Checks.Probe, so the sends of the findings are kept
/// as the Probe keeps them (FindingItems), and it is not an item of any production.
///   - QUEUEKIND is zzqueues, so that QueueDue selects only the rows of that Kind and a real Checks (Kind queues) never runs a row of these tests; QueueDue keeps
///     only the Refs that the test lists in Only, as Probe's Due does.
///   - ReadEntries answers from the process-private global ^||ChecksProbe("entries"): the JSON array of {"namespace", "production", "displayName"} that FeedEntries
///     set, an empty list when none was set, or the throw of the JSON object {"throw": text}. Each call counts in EntryCalls.
///   - ReadQueues answers per namespace from ^||ChecksProbe("queues", namespace): the JSON object {"outcome" (read by default), "queues" (an array, or "" as the reader gives
///     for a queue read that failed), "throw" (the text of the error it throws instead), "delete" (the Ref of a check row it deletes first: a watch that is stopped while
///     the check is running)} that FeedQueues set. A namespace with no entry answers not_current. Each call is kept
///     in ^||ChecksProbe("queueCalls", n) as a $ListBuild of namespace and production (QueueCalls reads them).
///   - Reset (Probe's) clears all of it.
Class OcuTalon.Test.Checks.QueueProbe Extends OcuTalon.Test.Checks.Probe
{

Parameter QUEUEKIND = "zzqueues";

/// The queue-backlog rows that QueueDue keeps are the Refs listed in Only (the Probe's property).
Method QueueDue(tickAt As %String) As %DynamicArray [ Private ]
{
	Set kept = []
	Set iterator = ##super(tickAt).%GetIterator()
	While iterator.%GetNext(, .row) {
		If $ListFind($ListFromString(..Only), row.ref) Do kept.%Push(row)
	}
	Quit kept
}

Method ReadEntries() As %DynamicArray [ Private ]
{
	Do $Increment(^||ChecksProbe("entryCalls"))
	Set text = $Get(^||ChecksProbe("entries"))
	If text = "" Quit []
	Set spec = ##class(%DynamicAbstractObject).%FromJSON(text)
	If spec.%IsA("%Library.DynamicObject") && (spec.throw '= "") $$$ThrowStatus($SYSTEM.Status.Error(5001, spec.throw))
	Quit spec
}

Method ReadQueues(namespace As %String, production As %String, Output queues As %DynamicArray) As %String [ Private ]
{
	Set queues = []
	Set ^||ChecksProbe("queueCalls", $Increment(^||ChecksProbe("queueCalls"))) = $ListBuild(namespace, production)
	Set text = $Get(^||ChecksProbe("queues", namespace))
	If text = "" Quit "not_current"
	Set spec = ##class(%DynamicAbstractObject).%FromJSON(text)
	If spec.delete '= "" {
		If ##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(spec.delete, .id) Do ##class(OcuTalon.Data.BackgroundCheck).%DeleteId(id)
	}
	If spec.throw '= "" $$$ThrowStatus($SYSTEM.Status.Error(5001, spec.throw))
	Set queues = spec.queues
	Quit $Select(spec.outcome '= "": spec.outcome, 1: "read")
}

/// Sets what ReadEntries gives: a dynamic array of {"namespace", "production", "displayName"}, or an object {"throw": text}.
ClassMethod FeedEntries(entries As %DynamicAbstractObject)
{
	Set ^||ChecksProbe("entries") = entries.%ToJSON()
}

/// Sets what ReadQueues gives for the namespace (spec is a dynamic object, see the class description).
ClassMethod FeedQueues(namespace As %String, spec As %DynamicObject)
{
	Set ^||ChecksProbe("queues", namespace) = spec.%ToJSON()
}

/// The number of ReadEntries calls.
ClassMethod EntryCalls() As %Integer
{
	Quit +$Get(^||ChecksProbe("entryCalls"))
}

/// The ReadQueues calls, in order, as a dynamic array of {namespace, production}.
ClassMethod QueueCalls() As %DynamicArray
{
	Set calls = []
	Set n = ""
	For {
		Set n = $Order(^||ChecksProbe("queueCalls", n), 1, call)
		Quit:n=""
		Do calls.%Push({"namespace": ($List(call, 1)), "production": ($List(call, 2))})
	}
	Quit calls
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
