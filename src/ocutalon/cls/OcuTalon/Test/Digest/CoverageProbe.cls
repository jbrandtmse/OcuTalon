/// Checks.Coverage with its three seams under test control (test only; Story 17.5). Test.Digest.Coverage calls Build of this class, so that the
/// vital signs, the live read of a production and the heartbeat gaps come from the process-private global ^||CoverageProbe and no production, file or
/// volume is read. It is not an item of any production.
///   - Vitals gives the object that Feed set (Healthy by default), or throws when Break set a throw;
///   - Read answers per production from ^||CoverageProbe("read", production), a JSON object {"outcome", "state", "rows", "disabled", "stoppedAt",
///     "errored", "queues", "throw"}: a production with no entry answers read, running, with nothing found; "errored" and "queues" given as a
///     string leave the output a string (an unread queue); each call is kept in Calls;
///   - Gaps gives the array that Gaps set ([] by default);
///   - Mark gives the text that FeedMark set, and MailOwner the Ref that FeedOwner set ("" for none; Story 22.5); Mark throws when ^||CoverageProbe("markError") is 1.
Class OcuTalon.Test.Digest.CoverageProbe Extends OcuTalon.Checks.Coverage
{

ClassMethod Vitals(namespaces As %List, fromUtc As %String, toUtc As %String) As %DynamicObject [ Private ]
{
	Do $Increment(^||CoverageProbe("vitalsCalls"))
	Set ^||CoverageProbe("namespaces") = $ListToString($Get(namespaces), ",")
	If $Get(^||CoverageProbe("vitalsThrow")) Throw ##class(%Exception.General).%New("CoverageProbe", 5001, , "The vital signs are refused")
	Quit ##class(%DynamicObject).%FromJSON($Get(^||CoverageProbe("vitals"), ..Healthy().%ToJSON()))
}

ClassMethod Read(namespace As %String, production As %String, from As %String, limit As %Integer, Output rows As %DynamicArray, Output state As %String, Output disabled As %DynamicArray, Output stoppedAt As %String, Output errored As %DynamicArray, Output queues As %DynamicArray) As %String [ Private ]
{
	Set ^||CoverageProbe("calls", $Increment(^||CoverageProbe("calls"))) = $ListBuild(namespace, production, from, limit)
	Set rows = []
	Set state = "running"
	Set disabled = []
	Set stoppedAt = ""
	Set errored = []
	Set queues = []
	Set text = $Get(^||CoverageProbe("read", production))
	If text = "" Quit "read"
	Set spec = ##class(%DynamicObject).%FromJSON(text)
	If spec.throw '= "" Throw ##class(%Exception.General).%New("CoverageProbe", 5001, , spec.throw)
	If spec.rows '= "" Set rows = spec.rows
	If spec.state '= "" Set state = spec.state
	If spec.%IsDefined("state") && (spec.state = "") Set state = ""
	If spec.disabled '= "" Set disabled = spec.disabled
	Set stoppedAt = spec.stoppedAt
	If spec.errored '= "" Set errored = spec.errored
	If spec.queues '= "" Set queues = spec.queues
	Quit $Select(spec.outcome '= "": spec.outcome, 1: "read")
}

ClassMethod Gaps(fromUtc As %String, toUtc As %String) As %DynamicArray [ Private ]
{
	Quit ##class(%DynamicObject).%FromJSON($Get(^||CoverageProbe("gaps"), "[]"))
}

ClassMethod Mark() As %String [ Private ]
{
	If $Get(^||CoverageProbe("markError")) = 1 Throw ##class(%Exception.General).%New("CoverageProbe", 5001, , "The mark is refused")
	Quit $Get(^||CoverageProbe("mark"))
}

ClassMethod MailOwner() As %String [ Private ]
{
	Quit $Get(^||CoverageProbe("owner"))
}

/// Sets the value of the mark emailPoll that Mark gives (the text of the JSON {at, ok, reason, lastOkAt}, or any other text).
ClassMethod FeedMark(text As %String)
{
	Set ^||CoverageProbe("mark") = text
}

/// Sets the session that owns the mailbox, as MailOwner gives it.
ClassMethod FeedOwner(sessionRef As %String)
{
	Set ^||CoverageProbe("owner") = sessionRef
}

/// Healthy readings of the five signs: 3 days up, one database with 40% of its volume free and no maximum, a journal volume 50% free, a license 20%
/// in use and no severe line.
ClassMethod Healthy() As %DynamicObject
{
	Quit {"instance": {"outcome": "read", "upSeconds": 259500}, "databases": [{"name": "OCUTALON_DATA", "directory": "/zz/ocutalon_data/", "volumeFreePercent": 40, "maxBlocks": 0, "outcome": "read"}], "journal": {"outcome": "read", "directory": "/zz/journal/", "freePercent": 50}, "license": {"outcome": "read", "units": 10, "consumed": 2, "usePercent": 20}, "systemLog": {"outcome": "read", "count": 0}}
}

/// Sets what Vitals gives.
ClassMethod Feed(vitals As %DynamicObject)
{
	Set ^||CoverageProbe("vitals") = vitals.%ToJSON()
}

/// Makes Vitals throw.
ClassMethod Break(on As %Boolean = 1)
{
	Set ^||CoverageProbe("vitalsThrow") = +on
}

/// Sets what Read answers for the production (spec is a dynamic object, see the class description).
ClassMethod FeedRead(production As %String, spec As %DynamicObject)
{
	Set ^||CoverageProbe("read", production) = spec.%ToJSON()
}

/// Sets what Gaps gives: an array of {"start", "end", "missed"}.
ClassMethod FeedGaps(gaps As %DynamicArray)
{
	Set ^||CoverageProbe("gaps") = gaps.%ToJSON()
}

/// The reads that Read recorded, in order, as an array of {namespace, production, from, limit}.
ClassMethod Calls() As %DynamicArray
{
	Set calls = []
	Set n = ""
	For {
		Set n = $Order(^||CoverageProbe("calls", n), 1, call)
		Quit:n=""
		Do calls.%Push({"namespace": ($List(call, 1)), "production": ($List(call, 2)), "from": ($List(call, 3)), "limit": ($List(call, 4))})
	}
	Quit calls
}

/// The namespaces that Vitals was last given, comma-separated.
ClassMethod Namespaces() As %String
{
	Quit $Get(^||CoverageProbe("namespaces"))
}

/// Forgets every feed and record.
ClassMethod Reset()
{
	Kill ^||CoverageProbe
}

}
