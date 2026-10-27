/// A Checks process whose reads and sends are under test control (test only; Story 5.6). Test.Checks.Runs calls OnRequest of a shadow instance of it, in its
/// own process, so that a Tick runs the real handlers over fixture rows and the production is never read. It is not an item of any production.
///   - Read (the reader's seam) answers per production from the process-private global ^||ChecksProbe("read", production), a JSON object
///     {"outcome", "state", "rows", "throw", "delete"}: the outcome and the state it gives, the rows (an array of reader rows) it gives, the text of the error
///     it throws instead, and the Ref of a check row it deletes first (a watch that is stopped while the check is running). A production with no entry
///     answers not_current. Each call is kept in ^||ChecksProbe("calls", n) as a $ListBuild of namespace, production, from and limit (Calls reads them).
///     A shadow instance has no reachable production, and the reader needs one.
///   - SendQuiet (the closeQuiet seam) cannot reach IncidentManager from a shadow instance, so it records {incidentRef, verb, origin, sessionRef,
///     superSession, sessionId} in Quieted and answers OK with a CommandResult, an error for an incident that FailQuiet names (comma-separated Refs, or
///     * for all), or OK with no answer, as a wait that ran out gives, for an incident that SilentQuiet names.
///   - Due and Quiet keep only the Refs that the test lists in Only and OnlyIncidents (after the product's own selection, so that its rules still run),
///     because a warm stack holds other rows that a Tick must never touch.
///   - KIND is zzprobe, so that Due selects only the rows of that Kind and a real Checks (Kind production) never runs a row of these tests.
///   - Quiet records the time it was given in SweptAt, then selects against QuietAt when that is set (a time that only the probe's tests reach), else against
///     the time it was given.
///   - Unclosed throws when FailUnclosed is set, as a failed read of the incidents does; a real failure of that read needs a database fault.
Class OcuTalon.Test.Checks.Probe Extends OcuTalon.Checks.Process
{

/// The Kind of the rows that Due selects.
Parameter KIND = "zzprobe";

/// The Refs of the checks that Due keeps, comma-separated.
Property Only As %String(MAXLEN = "") [ Transient ];

/// The Refs of the incidents that Quiet keeps, comma-separated.
Property OnlyIncidents As %String(MAXLEN = "") [ Transient ];

/// The time that Quiet selects against, as a UTC stamp, or "" for the time it is given.
Property QuietAt As %String [ Transient ];

/// The time that Quiet was last given, "" before the first sweep.
Property SweptAt As %String [ Transient ];

/// The commands that SendQuiet recorded, in order.
Property Quieted As %DynamicArray [ Transient ];

/// The Refs of the incidents whose SendQuiet answers an error, comma-separated, or * for every one.
Property FailQuiet As %String(MAXLEN = "") [ Transient ];

/// The Refs of the incidents whose SendQuiet answers OK with no answer (IncidentManager did not answer in time), comma-separated.
Property SilentQuiet As %String(MAXLEN = "") [ Transient ];

/// 1 to make the read of the incidents throw.
Property FailUnclosed As %Boolean [ InitialExpression = 0, Transient ];

Method Read(namespace As %String, production As %String, from As %String, limit As %Integer, Output rows As %DynamicArray, Output state As %String) As %String [ Private ]
{
	Set rows = []
	Set state = ""
	Set ^||ChecksProbe("calls", $Increment(^||ChecksProbe("calls"))) = $ListBuild(namespace, production, from, limit)
	Set text = $Get(^||ChecksProbe("read", production))
	If text = "" Quit "not_current"
	Set spec = ##class(%DynamicObject).%FromJSON(text)
	If spec.delete '= "" {
		If ##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(spec.delete, .id) Do ##class(OcuTalon.Data.BackgroundCheck).%DeleteId(id)
	}
	If spec.throw '= "" $$$ThrowStatus($SYSTEM.Status.Error(5001, spec.throw))
	If spec.rows '= "" Set rows = spec.rows
	Set state = spec.state
	Quit spec.outcome
}

Method SendQuiet(command As OcuTalon.Msg.IncidentCommand, Output answer As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set answer = ""
	If '$IsObject(..Quieted) Set ..Quieted = []
	Do ..Quieted.%Push({"incidentRef": (command.IncidentRef), "verb": (command.Verb), "origin": (command.Origin), "sessionRef": (command.SessionRef), "superSession": (..%SuperSession), "sessionId": (..%SessionId)})
	If (..FailQuiet = "*") || $ListFind($ListFromString(..FailQuiet), command.IncidentRef) Quit $SYSTEM.Status.Error(5001, "The send of closeQuiet is refused")
	If $ListFind($ListFromString(..SilentQuiet), command.IncidentRef) Quit $$$OK
	Set answer = ##class(OcuTalon.Msg.CommandResult).%New()
	Quit $$$OK
}

Method Due(tickAt As %String) As %DynamicArray [ Private ]
{
	Set kept = []
	Set iterator = ##super(tickAt).%GetIterator()
	While iterator.%GetNext(, .row) {
		If $ListFind($ListFromString(..Only), row.ref) Do kept.%Push(row)
	}
	Quit kept
}

Method Quiet(now As %String) As %DynamicArray [ Private ]
{
	Set kept = []
	Set ..SweptAt = now
	Set iterator = $Select(..QuietAt '= "": ##super(..QuietAt), 1: ##super(now)).%GetIterator()
	While iterator.%GetNext(, .incident) {
		If $ListFind($ListFromString(..OnlyIncidents), incident.ref) Do kept.%Push(incident)
	}
	Quit kept
}

Method Unclosed(row As %DynamicObject, onlineDemo As %Boolean) As %String [ Private ]
{
	If ..FailUnclosed $$$ThrowStatus($SYSTEM.Status.Error(5001, "The incidents are refused"))
	Quit ##super(row, onlineDemo)
}

/// The reads that Read recorded, in order, as a dynamic array of {namespace, production, from, limit}.
ClassMethod Calls() As %DynamicArray
{
	Set calls = []
	Set n = ""
	For {
		Set n = $Order(^||ChecksProbe("calls", n), 1, call)
		Quit:n=""
		Do calls.%Push({"namespace": ($List(call, 1)), "production": ($List(call, 2)), "from": ($List(call, 3)), "limit": ($List(call, 4))})
	}
	Quit calls
}

/// Sets what Read answers for the production (spec is a dynamic object, see the class description).
ClassMethod Feed(production As %String, spec As %DynamicObject)
{
	Set ^||ChecksProbe("read", production) = spec.%ToJSON()
}

/// Forgets the feeds and the recorded reads.
ClassMethod Reset()
{
	Kill ^||ChecksProbe
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
