/// The fix kind that suspends an item of the incident's production (AD-16; Story 23.2): it disables the item, so that it stops taking messages, and it is undone by its
/// subclass ResumeItem. The user asks for it in the chat (propose_fix; ASKED 1) and the diagnosis never names it (DIAGNOSED 0). The one parameter is item, the name of an
/// item of the incident's production; the target is that item's Ens.Config.Item id (TARGETTYPE item), a single one.
///   - DryRun reads the production's items through Watch.Reader.Items and changes nothing. It refuses, with a plain reason, on the online demo (ONLINESHARED: every visitor
///     shares the Orders production), for an item of OcuTalon's own production (OWNPRODUCTION), for a name that is not an item of the production, and for an item that already
///     is in the state the kind leaves. Its answer is {"item", "before", "after"}, the item's state before and after as "enabled" and "disabled".
///   - Recheck and Execute (Story 7.3) read the item again from the approved row's target: it passes only if the id still names the item and its state still is the dry run's
///     before; else it is skipped with a plain reason that names the item. Execute makes the change through Fix.Executor.InProduction, which holds the one namespace switch of
///     the executor and calls Ens.Director.EnableConfigItem there; its result is {"changed": the items changed, "skipped": [{"id", "reason"}], "unreached": [{"id", "code"}]}.
///   - The kind needs %Ens_ConfigItemRun:U. An online-demo install does not grant it to the service role (ONLINEGRANT 0, AD-24), so the kind could not run there even if
///     the ONLINESHARED check were bypassed. Lane A.
Class OcuTalon.Fix.Kind.SuspendItem Extends OcuTalon.Fix.Kind
{

Parameter NAME = "suspend_item";

Parameter PARAMETERS = "item";

Parameter RESOURCES = "%Ens_ConfigItemRun:U";

Parameter TARGETTYPE = "item";

Parameter DIAGNOSED = 0;

Parameter ASKED = 1;

Parameter ONLINEGRANT = 0;

/// 1 when the kind enables the item (ResumeItem), 0 when it disables it.
Parameter ENABLE = 0;

Parameter NOTALLOWED = "OcuTalon isn't allowed to suspend or resume items in that production";

Parameter NOSTART = "OcuTalon couldn't change the item";

Parameter NOREAD = "OcuTalon couldn't read the items of that production";

/// The reason of a dry run on the online demo, and of one for an item of OcuTalon's own production.
Parameter ONLINESHARED = "On the online demo every visitor shares the Orders production, so OcuTalon doesn't suspend or resume its items there; on your own install it can";

Parameter OWNPRODUCTION = "OcuTalon doesn't suspend or resume the items of its own production";

/// The base's schema check: the parameter item is a string that is not blank.
ClassMethod CheckParameters(parameters As %DynamicObject, fields As %DynamicArray) As %Status
{
	Quit ##super(parameters, fields)
}

/// The item's id as the dry run's target, and the dry run {"item", "before", "after"} (see the class description). An error status that says why when the parameters
/// don't pass CheckParameters, the kind is refused here (Refusal), the production can't be read, the name is no item of it or the item already is in the state the kind leaves.
ClassMethod DryRun(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, Output targets As %String, Output dryRun As %DynamicObject) As %Status
{
	Set targets = ""
	Set dryRun = ""
	Set sc = ..CheckParameters(parameters, "")
	If $$$ISERR(sc) Quit sc
	Set why = ..Refusal(incident)
	If why '= "" Quit $$$ERROR($$$GeneralError, why)
	Set sc = ..ItemsOf(incident, .items)
	If $$$ISERR(sc) Quit sc
	Set name = parameters.%Get("item")
	Set item = ..ItemNamed(items, name)
	If '$IsObject(item) Quit $$$ERROR($$$GeneralError, name_" is not an item of "_..ProductionName(incident))
	If item.enabled = ..#ENABLE Quit $$$ERROR($$$GeneralError, name_" is already "_..State(item.enabled))
	Set targets = item.id
	Set dryRun = {"item": (item.name), "before": (..State(item.enabled)), "after": (..State(..#ENABLE))}
	Quit $$$OK
}

/// "enabled" for 1 and "disabled" for 0.
ClassMethod State(enabled As %Boolean) As %String [ Private ]
{
	Quit $Select(enabled: "enabled", 1: "disabled")
}

/// The reason that this kind is not offered for the incident: the online demo (ONLINESHARED) or OcuTalon's own production (OWNPRODUCTION); "" otherwise.
ClassMethod Refusal(incident As OcuTalon.Data.Incident) As %String
{
	If ##class(OcuTalon.Watch.Reader).OnlineDemo() Quit ..#ONLINESHARED
	If incident.Production = ##class(OcuTalon.Install.Step.Production).#PRODUCTION Quit ..#OWNPRODUCTION
	Quit ""
}

/// Re-checks the item of an approved request before it is changed (see the class description): passed holds the target when it passes, skipped holds {"id", "reason"} when it
/// does not. It changes nothing. An error status when the parameters don't pass CheckParameters or the production can't be read.
ClassMethod Recheck(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output passed As %String, Output skipped As %DynamicArray) As %Status
{
	Set passed = ""
	Set skipped = []
	Set sc = ..Plan(incident, parameters, targets, .plan, .skipped)
	If $$$ISERR(sc) Quit sc
	If plan.%Size() > 0 Set passed = targets
	Quit $$$OK
}

/// Changes the item of the target through Fix.Executor.InProduction (see the class description). The target is read again by the same test as Recheck, so that an item that
/// changed since the re-check is skipped. result is {"changed", "skipped", "unreached"}. An error status when the production can't be read.
ClassMethod Execute(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output result As %DynamicObject, run As OcuTalon.Data.FixRun = "") As %Status
{
	Set result = {"changed": 0, "skipped": [], "unreached": []}
	Set sc = ..Plan(incident, parameters, targets, .plan, .skipped)
	If $$$ISERR(sc) Quit sc
	Set result.skipped = skipped
	If plan.%Size() = 0 Quit $$$OK
	Do ##class(OcuTalon.Fix.Executor).InProduction(incident.Namespace, plan, run, .changed, .changeSkipped, .unreached)
	Set result.changed = changed
	Set result.unreached = unreached
	Set iterator = changeSkipped.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Do result.skipped.%Push(entry)
	}
	Quit $$$OK
}

/// The test of Recheck and Execute over the target: plan holds {"id", "action" (disable or enable), "item", "production"} when the target passes, skipped {"id", "reason"} when
/// it does not. An error status when the parameters don't pass CheckParameters or the production can't be read.
ClassMethod Plan(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output plan As %DynamicArray, Output skipped As %DynamicArray) As %Status [ Private ]
{
	Set plan = []
	Set skipped = []
	Set sc = ..CheckParameters(parameters, "")
	If $$$ISERR(sc) Quit sc
	Set id = +targets
	Set name = parameters.%Get("item")
	Set why = ..Refusal(incident)
	If why '= "" {
		Do skipped.%Push({"id": (id), "reason": (why)})
		Quit $$$OK
	}
	Set sc = ..ItemsOf(incident, .items)
	If $$$ISERR(sc) Quit sc
	Set item = ""
	Set iterator = items.%GetIterator()
	While iterator.%GetNext(, .each) {
		If each.id = id Set item = each
	}
	If '$IsObject(item) || ("k"_item.name '= ("k"_name)) {
		Do skipped.%Push({"id": (id), "reason": (name_" is no longer in the production")})
	} ElseIf item.enabled = ..#ENABLE {
		Do skipped.%Push({"id": (id), "reason": (name_" changed since the dry run")})
	} Else {
		Do plan.%Push({"id": (id), "action": ($Select(..#ENABLE: "enable", 1: "disable")), "item": (name), "production": (incident.Production)})
	}
	Quit $$$OK
}

}
