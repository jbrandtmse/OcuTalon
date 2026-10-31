/// A Checks process whose reads and sends are under test control (test only; Story 5.6). Test.Checks.Runs calls OnRequest of a shadow instance of it, in its
/// own process, so that a Tick runs the real handlers over fixture rows and the production is never read. It is not an item of any production.
///   - Read (the reader's seam) answers per production from the process-private global ^||ChecksProbe("read", production), a JSON object
///     {"outcome", "state", "rows", "disabled", "stoppedAt", "throw", "delete"}: the outcome and the state it gives, the rows (an array of reader rows) it gives,
///     the names of the disabled items (an array, [] by default) and the recorded stop time (a string, "" by default) it gives, the text of the error
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
///   - FixRunSweep (Story 7.5) gives the FixResults in Swept (none by default, so that a Tick never sweeps the fix runs of a stack) or throws the text in SweepThrows. SendFixResult cannot reach
///     IncidentManager from a shadow instance, so it records {approvalRef, sessionId, superSession} in Sent and answers OK, or an error for a request that FailFix names (comma-separated Refs).
///   - SendFinding (Story 30.4) cannot reach Intake from a shadow instance, so it keeps {itemId, sessionRef, channel, provenance, text, sender, subject,
///     catalogKey, slots, sessionId, superSession} in ^||ChecksProbe("findings", n) (FindingItems reads them) and answers OK, or an error for an item whose Text holds one of
///     the texts that FailFindings set (comma-separated; the finding of one display name or item name), or throws when FailFindings asked for it. Reset clears them.
///   - Order lists each send in order, "quiet:<incident Ref>" for SendQuiet and "fix:<approval Ref>" for SendFixResult and "finding:<catalog key>" for SendFinding, so that a test can tell that the quiet sweep came first. Quieted keeps its shape.
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

/// The FixResults that FixRunSweep gives, in order (a %ListOfObjects), and the text of the error that it throws instead when it is not empty.
Property Swept As %ListOfObjects [ Transient ];

Property SweepThrows As %String(MAXLEN = "") [ Transient ];

/// The sends of SendFixResult in order, each {approvalRef, sessionId, superSession}, and the Refs of the requests whose send answers an error, comma-separated.
Property Sent As %DynamicArray [ Transient ];

Property FailFix As %String(MAXLEN = "") [ Transient ];

/// Each send in order, as text.
Property Order As %DynamicArray [ Transient ];

Method Read(namespace As %String, production As %String, from As %String, limit As %Integer, Output rows As %DynamicArray, Output state As %String, Output disabled As %DynamicArray, Output stoppedAt As %String) As %String [ Private ]
{
	Set rows = []
	Set state = ""
	Set disabled = []
	Set stoppedAt = ""
	Set ^||ChecksProbe("calls", $Increment(^||ChecksProbe("calls"))) = $ListBuild(namespace, production, from, limit)
	Set text = $Get(^||ChecksProbe("read", production))
	If text = "" Quit "not_current"
	Set spec = ##class(%DynamicObject).%FromJSON(text)
	If spec.delete '= "" {
		If ##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(spec.delete, .id) Do ##class(OcuTalon.Data.BackgroundCheck).%DeleteId(id)
	}
	If spec.throw '= "" $$$ThrowStatus($SYSTEM.Status.Error(5001, spec.throw))
	If spec.rows '= "" Set rows = spec.rows
	If spec.disabled '= "" Set disabled = spec.disabled
	Set stoppedAt = spec.stoppedAt
	Set state = spec.state
	Quit spec.outcome
}

Method SendQuiet(command As OcuTalon.Msg.IncidentCommand, Output answer As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Set answer = ""
	If '$IsObject(..Quieted) Set ..Quieted = []
	Do ..Quieted.%Push({"incidentRef": (command.IncidentRef), "verb": (command.Verb), "origin": (command.Origin), "sessionRef": (command.SessionRef), "superSession": (..%SuperSession), "sessionId": (..%SessionId)})
	Do ..Ordered("quiet:"_command.IncidentRef)
	If (..FailQuiet = "*") || $ListFind($ListFromString(..FailQuiet), command.IncidentRef) Quit $SYSTEM.Status.Error(5001, "The send of closeQuiet is refused")
	If $ListFind($ListFromString(..SilentQuiet), command.IncidentRef) Quit $$$OK
	Set answer = ##class(OcuTalon.Msg.CommandResult).%New()
	Quit $$$OK
}

/// Gives Swept (none when it is empty), or throws SweepThrows.
Method FixRunSweep() As %ListOfObjects [ Private ]
{
	If ..SweepThrows '= "" $$$ThrowStatus($SYSTEM.Status.Error(5001, ..SweepThrows))
	Quit $Select($IsObject(..Swept): ..Swept, 1: ##class(%ListOfObjects).%New())
}

/// Records the send with the session and the SuperSession it was made in, and answers OK, or an error for a request that FailFix names.
Method SendFixResult(result As OcuTalon.Fix.Msg.FixResult) As %Status [ Private ]
{
	If '$IsObject(..Sent) Set ..Sent = []
	Do ..Sent.%Push({"approvalRef": (result.ApprovalRef), "sessionId": (..%SessionId), "superSession": (..%SuperSession)})
	Do ..Ordered("fix:"_result.ApprovalRef)
	If $ListFind($ListFromString(..FailFix), result.ApprovalRef) Quit $SYSTEM.Status.Error(5001, "The send of the result of "_result.ApprovalRef_" is refused")
	Quit $$$OK
}

/// Keeps the item with the session and the SuperSession it was sent in, and answers OK, or an error (or throws, when FailFindings says so) for an item whose Text
/// holds a text of FailFindings.
Method SendFinding(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	Set ^||ChecksProbe("findings", $Increment(^||ChecksProbe("findings"))) = {"itemId": (item.ItemId), "sessionRef": (item.SessionRef), "channel": (item.Channel), "provenance": (item.Provenance), "text": (item.Text), "sender": (item.Sender), "subject": (item.Subject), "catalogKey": (item.CatalogKey), "slots": (item.Slots), "sessionId": (..%SessionId), "superSession": (..%SuperSession)}.%ToJSON()
	Do ..Ordered("finding:"_item.CatalogKey)
	Set position = 0
	Set fails = $ListFromString($Get(^||ChecksProbe("failFindings")))
	While $ListNext(fails, position, text) {
		If (text '= "") && (item.Text [ text) {
			If $Get(^||ChecksProbe("failThrow")) Throw ##class(%Exception.StatusException).CreateFromStatus($SYSTEM.Status.Error(5001, "The send of the finding threw"))
			Return $SYSTEM.Status.Error(5001, "The send of the finding is refused")
		}
	}
	Quit $$$OK
}

/// Adds the text to Order.
Method Ordered(text As %String) [ Private ]
{
	If '$IsObject(..Order) Set ..Order = []
	Do ..Order.%Push(text)
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

/// The findings that SendFinding kept, in order, as a dynamic array of {itemId, sessionRef, channel, provenance, text, sender, subject, catalogKey, slots,
/// sessionId, superSession}.
ClassMethod FindingItems() As %DynamicArray
{
	Set findings = []
	Set n = ""
	For {
		Set n = $Order(^||ChecksProbe("findings", n), 1, json)
		Quit:n=""
		Do findings.%Push(##class(%DynamicAbstractObject).%FromJSON(json))
	}
	Quit findings
}

/// Makes SendFinding answer an error, or throw when throw is 1, for an item whose Text holds one of the texts (comma-separated).
ClassMethod FailFindings(texts As %String, throw As %Boolean = 0)
{
	Set ^||ChecksProbe("failFindings") = texts
	Set ^||ChecksProbe("failThrow") = +throw
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
