/// A Fix.Run whose seams are under test control (test only; Story 7.5). Fix.Run is all class methods, so the probe keeps what a test feeds it in the process-private global
/// ^||FixRunProbe, and Test.Fix.Executor calls Interrupt and Sweep on this class. It is not an item of any production.
///   - Unended keeps only the runs of the incidents that Narrow names (comma-separated Refs; none when it is empty), after the product's own selection, because a warm stack holds other
///     rows that a Sweep must never touch.
///   - Started gives the stamp that StartIs sets, "" when none is set (the production's start time is then not known).
///   - Statuses gives, for the run of the request (its ApprovalRef), the copies that Feed set: a JSON object {copy header id: {"status", "error", "target", "at"}}, with the outcome
///     Feed gave (read by default), or throws when ReadThrows named the request; for a request that Feed names nowhere it is the product's read. Reads counts the calls.
///   - Close gives an error for the Refs that FailClose names (comma-separated), throws for those that ThrowClose names, else the product's FinishExecution; Closed lists each call that it was
///     given, "<Ref>|<result>". UnendedThrows makes Unended throw.
///   - WriteAudit records the data of each entry in Audits and writes nothing, or throws for the Refs that AuditThrows names (comma-separated), recording nothing.
///   - Statuses also spoils the run in memory for the Refs that SpoilSave names (comma-separated): its IncidentRef is then longer than a FixRun holds, so the save of the run's end fails.
Class OcuTalon.Test.Fix.RunProbe Extends OcuTalon.Fix.Run
{

/// Narrows Unended to the runs of the incidents (comma-separated Refs).
ClassMethod Narrow(refs As %String)
{
	Set ^||FixRunProbe("only") = refs
}

/// The stamp that Started gives; "" for none.
ClassMethod StartIs(stamp As %String)
{
	Set ^||FixRunProbe("started") = stamp
}

/// The copies that Statuses gives for the request (statuses is a dynamic object by the copies' header ids) and the outcome it gives with them.
ClassMethod Feed(approvalRef As %String, statuses As %DynamicObject, outcome As %String = "read")
{
	Set ^||FixRunProbe("statuses", approvalRef) = statuses.%ToJSON()
	Set ^||FixRunProbe("outcome", approvalRef) = outcome
}

/// Makes the read of the request's copies throw.
ClassMethod ReadThrows(approvalRef As %String)
{
	Set ^||FixRunProbe("throw", approvalRef) = 1
}

/// The Refs whose Close gives an error (comma-separated).
ClassMethod FailClose(refs As %String)
{
	Set ^||FixRunProbe("failClose") = refs
}

/// The Refs whose Close throws (comma-separated).
ClassMethod ThrowClose(refs As %String)
{
	Set ^||FixRunProbe("throwClose") = refs
}

/// The Refs whose run is spoiled in memory by Statuses, so that the save of its end fails (comma-separated).
ClassMethod SpoilSave(refs As %String)
{
	Set ^||FixRunProbe("spoilSave") = refs
}

/// The Refs whose audit write throws (comma-separated).
ClassMethod AuditThrows(refs As %String)
{
	Set ^||FixRunProbe("auditThrows") = refs
}

/// Makes Unended throw, as a read of the runs that fails.
ClassMethod UnendedThrows()
{
	Set ^||FixRunProbe("unendedThrows") = 1
}

/// The calls of Statuses so far.
ClassMethod Reads() As %Integer
{
	Quit +$Get(^||FixRunProbe("reads"))
}

/// The calls of Close, in order, as a dynamic array of "<Ref>|<result>".
ClassMethod Closed() As %DynamicArray
{
	Quit ..List("closed")
}

/// The data of the entries that WriteAudit recorded, in order, as a dynamic array of dynamic objects.
ClassMethod Audits() As %DynamicArray
{
	Set audits = []
	Set n = ""
	For {
		Set n = $Order(^||FixRunProbe("audits", n), 1, json)
		Quit:n=""
		Do audits.%Push({}.%FromJSON(json))
	}
	Quit audits
}

/// Forgets everything that was fed and recorded.
ClassMethod Reset()
{
	Kill ^||FixRunProbe
}

ClassMethod Unended() As %List
{
	If $Get(^||FixRunProbe("unendedThrows")) Throw ##class(%Exception.General).%New("Probe", 5001, , "The runs could not be read")
	Set kept = ""
	Set position = 0
	Set ids = ##super()
	While $ListNext(ids, position, id) {
		Set run = ##class(OcuTalon.Data.FixRun).%OpenId(id)
		If $IsObject(run) && $ListFind($ListFromString($Get(^||FixRunProbe("only"))), run.IncidentRef) Set kept = kept _ $ListBuild(id)
	}
	Quit kept
}

ClassMethod Started() As %String
{
	Quit $Get(^||FixRunProbe("started"))
}

ClassMethod Statuses(incident As OcuTalon.Data.Incident, run As OcuTalon.Data.FixRun, Output statuses As %DynamicObject) As %String
{
	Set ^||FixRunProbe("reads") = +$Get(^||FixRunProbe("reads")) + 1
	Set ref = run.ApprovalRef
	If $Get(^||FixRunProbe("throw", ref)) Throw ##class(%Exception.General).%New("Probe", 5001, , "The read threw")
	If $ListFind($ListFromString($Get(^||FixRunProbe("spoilSave"))), ref) Set run.IncidentRef = $Justify("", 40)
	If '$Data(^||FixRunProbe("statuses", ref)) Quit ##super(incident, run, .statuses)
	Set statuses = {}.%FromJSON(^||FixRunProbe("statuses", ref))
	Quit ^||FixRunProbe("outcome", ref)
}

ClassMethod Close(ref As %String, result As %String) As %Status
{
	Set ^||FixRunProbe("closed", $Increment(^||FixRunProbe("closed"))) = ref_"|"_result
	If $ListFind($ListFromString($Get(^||FixRunProbe("throwClose"))), ref) Throw ##class(%Exception.General).%New("Probe", 5001, , "The close of "_ref_" threw")
	If $ListFind($ListFromString($Get(^||FixRunProbe("failClose"))), ref) Quit $SYSTEM.Status.Error(5001, "The close of "_ref_" is refused")
	Quit ##super(ref, result)
}

ClassMethod WriteAudit(data As %DynamicObject) As %Status
{
	If $ListFind($ListFromString($Get(^||FixRunProbe("auditThrows"))), data.approvalRef) Throw ##class(%Exception.General).%New("Probe", 5001, , "The audit write of "_data.approvalRef_" threw")
	Set ^||FixRunProbe("audits", $Increment(^||FixRunProbe("audits"))) = data.%ToJSON()
	Quit $$$OK
}

/// The recorded lines of the kind, in order, as a dynamic array of text.
ClassMethod List(kind As %String) As %DynamicArray [ Private ]
{
	Set list = []
	Set n = ""
	For {
		Set n = $Order(^||FixRunProbe(kind, n), 1, line)
		Quit:n=""
		Do list.%Push(line)
	}
	Quit list
}

}
