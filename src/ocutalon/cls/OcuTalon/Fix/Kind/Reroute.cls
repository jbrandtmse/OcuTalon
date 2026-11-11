/// The fix kind that reroutes an incident's failed messages to another item of its production (AD-16; Story 23.2): each message is resent as a copy to the item the user
/// names, and the originals are never changed. The user asks for it in the chat (propose_fix; ASKED 1) and the diagnosis never names it (DIAGNOSED 0). The one parameter is
/// target, the name of an item of the incident's production.
///   - DryRun reads the incident's failed messages of its scope over its failure groups' whole Seen (Fix.Kind.Failed with whole 1: a chat ask moves no window marks), less those
///     an earlier run resent, and the production's items (Watch.Reader.Items). The target must be an item of the production, enabled, a business process or a business operation,
///     and not the item the messages failed at; the dry run refuses otherwise, with a plain reason. A message is a target when it is of the incident's scope, still in the status
///     Error and sent to the same item as the lowest-numbered one (from); every other failed message, and every failure Seen no longer lists, counts as affected and left out. The
///     answer is {"affected", "resend", "leftOut", "itemNoun", "from", "to", "example"}: the counts, the item the messages are at, the item they would go to, and the header id
///     of the first target. With no failed message it gives no targets and no dry run, and no error.
///   - Recheck and Execute (Story 7.3) take their targets from the approved row and read them again like RepairResend, with no field test, and the target item must still be enabled
///     (else every target is skipped). Execute resends a copy of each target that passes to the target item through Fix.Executor.Resend, which holds the one namespace switch of the
///     executor; the copies are registered on the run, so that they are waited for and attributed to it (FixRun.CopyOf). Lane A.
Class OcuTalon.Fix.Kind.Reroute Extends OcuTalon.Fix.Kind
{

Parameter NAME = "reroute";

Parameter PARAMETERS = "target";

Parameter RESOURCES = "%Ens_MessageResend:U";

Parameter DIAGNOSED = 0;

Parameter ASKED = 1;

Parameter NOTALLOWED = "OcuTalon isn't allowed to resend messages in that production";

/// The base's schema check: the parameter target is a string that is not blank.
ClassMethod CheckParameters(parameters As %DynamicObject, fields As %DynamicArray) As %Status
{
	Quit ##super(parameters, fields)
}

/// The targets and the dry run (see the class description). An error status that says why when the parameters don't pass CheckParameters, the production can't be read, the
/// target is not a valid item to reroute to or it is the item the messages are at.
ClassMethod DryRun(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, Output targets As %String, Output dryRun As %DynamicObject) As %Status
{
	Set targets = ""
	Set dryRun = ""
	Set sc = ..CheckParameters(parameters, "")
	If $$$ISERR(sc) Quit sc
	Set sc = ..Valid(incident, parameters.%Get("target"), .why, .code)
	If $$$ISERR(sc) Quit sc
	If why '= "" Quit $$$ERROR($$$GeneralError, why)
	Set sc = ..Failed(incident, 1, .scoped, .unlisted, .classes, .arrived, .origin)
	If $$$ISERR(sc) Quit sc
	Set first = $Order(scoped(""))
	If first = "" Quit $$$OK
	Set to = parameters.%Get("target")
	Set from = $List(origin(first), 2)
	If "k"_from = ("k"_to) Quit $$$ERROR($$$GeneralError, "The failed messages were already sent to "_to)
	Set affected = unlisted
	Set id = ""
	For {
		Set id = $Order(scoped(id))
		Quit:id=""
		Set affected = affected + 1
		If "k"_$List(origin(id), 2) '= ("k"_from) Continue
		Set targets = targets _ $Select(targets = "": "", 1: ",") _ id
	}
	Set resend = $Length(targets, ",")
	Set dryRun = {"affected": (affected), "resend": (resend), "leftOut": (affected - resend), "itemNoun": (..ItemNounOf(incident, classes(first))), "from": (from), "to": (to)}
	Do dryRun.%Set("example", first, "string")
	Quit $$$OK
}

/// OK, with why "" when the item of the name is a valid target to reroute to: an item of the incident's production, enabled, a business process or operation; else why holds the
/// plain reason and code is missing, disabled or service. An error status when the production can't be read.
ClassMethod Valid(incident As OcuTalon.Data.Incident, name As %String, Output why As %String, Output code As %String) As %Status [ Private ]
{
	Set why = ""
	Set code = ""
	Set sc = ..ItemsOf(incident, .items)
	If $$$ISERR(sc) Quit sc
	Set item = ..ItemNamed(items, name)
	If '$IsObject(item) {
		Set why = name_" is not an item of "_..ProductionName(incident)
		Set code = "missing"
	} ElseIf 'item.enabled {
		Set why = name_" is disabled"
		Set code = "disabled"
	} ElseIf (item.businessType '= "process") && (item.businessType '= "operation") {
		Set why = name_" is a business service, which can't take rerouted messages"
		Set code = "service"
	}
	Quit $$$OK
}

/// Re-checks the targets (comma-separated header ids, ascending) of an approved request before any copy is made (see the class description): passed holds the ids that still
/// are targets, skipped the others as {"id", "reason"}. It changes nothing. An error status when the parameters don't pass CheckParameters or the failed messages or the items
/// can't be read.
ClassMethod Recheck(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output passed As %String, Output skipped As %DynamicArray) As %Status
{
	Set passed = ""
	Set skipped = []
	Set sc = ..Plan(incident, parameters, targets, .plan, .skipped)
	If $$$ISERR(sc) Quit sc
	Set iterator = plan.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set passed = passed _ $Select(passed = "": "", 1: ",") _ entry.id
	}
	Quit $$$OK
}

/// Resends a copy of each of the targets (those that passed Recheck) to the target item through Fix.Executor.Resend and registers each copy on run. The targets are read again by the
/// same test as Recheck. result is {"resent": the copies made, "skipped": [{"id", "reason"}], "unreached": [{"id", "code"}]}, as RepairResend gives it. An error status when the
/// failed messages or the items can't be read.
ClassMethod Execute(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output result As %DynamicObject, run As OcuTalon.Data.FixRun = "") As %Status
{
	Set result = {"resent": 0, "skipped": [], "unreached": []}
	Set sc = ..Plan(incident, parameters, targets, .plan, .skipped)
	If $$$ISERR(sc) Quit sc
	Set result.skipped = skipped
	If plan.%Size() = 0 Quit $$$OK
	Do ##class(OcuTalon.Fix.Executor).Resend(incident.Namespace, plan, run, .resent, .resendSkipped, .unreached)
	Set result.resent = resent
	Set result.unreached = unreached
	Set iterator = resendSkipped.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Do result.skipped.%Push(entry)
	}
	Quit $$$OK
}

/// The test of Recheck and Execute over the targets: plan holds {"id", "target"} for each target that passes, skipped {"id", "reason"} for each that does not, both in target
/// order. When the target item is no longer a valid item every target is skipped with that reason. An error status when the parameters don't pass CheckParameters, the
/// incident has no failure group or the failed messages or the items can't be read.
ClassMethod Plan(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output plan As %DynamicArray, Output skipped As %DynamicArray) As %Status [ Private ]
{
	Set plan = []
	Set skipped = []
	Set sc = ..CheckParameters(parameters, "")
	If $$$ISERR(sc) Quit sc
	Set to = parameters.%Get("target")
	Set sc = ..Valid(incident, to, .why, .code)
	If $$$ISERR(sc) Quit sc
	If code = "disabled" Set why = to_" is no longer enabled"
	Set sc = ..Targeted(incident, targets, .found)
	If $$$ISERR(sc) Quit sc
	For i = 1:1:$Length(targets, ",") {
		Set id = +$Piece(targets, ",", i)
		If why '= "" {
			Do skipped.%Push({"id": (id), "reason": (why)})
			Continue
		}
		If '$Data(found(id)) {
			Do skipped.%Push({"id": (id), "reason": (..MessageReason("missing", id))})
			Continue
		}
		Set failure = found(id)
		Set code = ..Standing(failure, incident)
		If code = "" Set code = $Select($IsObject(failure.resentBy) && (failure.resentBy.%Size() > 0): "resent", 1: "")
		If code '= "" {
			Do skipped.%Push({"id": (id), "reason": (..MessageReason(code, id))})
			Continue
		}
		Do plan.%Push({"id": (id), "target": (to)})
	}
	Quit $$$OK
}

}
