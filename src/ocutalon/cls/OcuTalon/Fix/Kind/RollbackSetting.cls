/// The fix kind that puts back a setting that changed just before an incident's failures (AD-16, AD-24; Story 23.3): it writes the change's old value as the failing item's own
/// stored setting, for the change's target (Host or Adapter). The diagnosis offers it for a setting_change (DIAGNOSED 1, CATEGORY setting_change), and its subclass UndoRollback,
/// which the user asks for in the chat, puts back the value that the rollback replaced. The one parameter is change, the Ref of a Data.SettingChange row; the target is that row's
/// id (TARGETTYPE setting), a single one.
///   - DryRun reads the setting through Watch.Reader.Settings and changes nothing. It refuses, with a plain reason, in this order: the online demo (ONLINESHARED: it has no setting
///     history and no grant), OcuTalon's own production (OWNPRODUCTION), a Ref that is no row of the incident's production (NOTFOUND), a change that is not in the window before
///     the incident's first failure (NOTINWINDOW), a change that is not on a failing item (OTHERITEM), a secret (SECRET) and a value that is empty or over VALUEMAX characters
///     (VALUES). Then a current value that is not the change's new value is refused (CHANGEDAGAIN). Its answer is {"item", "field" (the setting), "before" (the current value), "after"
///     (the old value)}.
///   - Recheck and Execute (Story 7.3) read the row and the current value again from the approved row's target through Plan, so that a change that moved since the dry run is skipped
///     with the CHANGEDAGAIN reason. Execute makes the change through Fix.Executor.InProduction, which holds the one namespace switch of the executor: it reads the effective value
///     again there, sets the stored setting and updates the production. No System Default Setting row, class or other item is ever edited. When the update fails after the
///     definition was saved, InProduction writes the earlier value back and updates again: the entry is then unreached as refused, and nothing was changed; if that fails too, the
///     entry is unreached as notapplied with the production's error as its reason (the run reads result.settingSavedNotApplied). Its result is {"changed", "skipped",
///     "unreached"}.
///   - The kind needs %Ens_ProductionConfig:W, which an online-demo install does not grant to the service role (ONLINEGRANT 0, AD-24). Lane A.
Class OcuTalon.Fix.Kind.RollbackSetting Extends OcuTalon.Fix.Kind
{

Parameter NAME = "rollback_setting";

Parameter PARAMETERS = "change";

Parameter RESOURCES = "%Ens_ProductionConfig:W";

Parameter TARGETTYPE = "setting";

Parameter CATEGORY = "setting_change";

Parameter DIAGNOSED = 1;

Parameter ASKED = 0;

Parameter ONLINEGRANT = 0;

Parameter MOVES = 1;

/// The longest value, in characters, that the kind puts back.
Parameter VALUEMAX = 1000;

Parameter NOTALLOWED = "OcuTalon isn't allowed to change settings in that production";

Parameter ONLINESHARED = "On the online demo every visitor shares the Orders production, so OcuTalon doesn't change its settings there; on your own install it can";

Parameter OWNPRODUCTION = "OcuTalon doesn't change the settings of its own production";

Parameter NOTFOUND = "That setting change is not one OcuTalon recorded for this production";

Parameter NOTINWINDOW = "That setting change is not from the 24 hours before the failures began";

Parameter OTHERITEM = "That setting change is not on {item}, the item that failed";

Parameter SECRET = "{setting} holds a secret, so OcuTalon doesn't put it back";

Parameter VALUES = "OcuTalon puts back only values of 1 to 1,000 characters, so it can't put {setting} on {target} back";

Parameter CHANGEDAGAIN = "{setting} on {target} changed again since then";

Parameter NOSTART = "OcuTalon couldn't change the setting";

Parameter NOREAD = "OcuTalon couldn't read the settings of that production";

Parameter NOTHINGTOUNDO = "There is no rollback of that setting to undo";

/// The base's schema check: the parameter change is a string that is not blank.
ClassMethod CheckParameters(parameters As %DynamicObject, fields As %DynamicArray) As %Status
{
	Quit ##super(parameters, fields)
}

/// The row's id as the dry run's target, and the dry run (see the class description). An error status that says why when the parameters don't pass CheckParameters, the kind is
/// refused (Vetted), the settings can't be read or the current value is not the one that the kind expects.
ClassMethod DryRun(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, Output targets As %String, Output dryRun As %DynamicObject) As %Status
{
	Set targets = ""
	Set dryRun = ""
	Set sc = ..CheckParameters(parameters, "")
	If $$$ISERR(sc) Quit sc
	Set why = ..Vetted(incident, parameters, 1, .row)
	If why '= "" Quit $$$ERROR($$$GeneralError, why)
	Set sc = ..Current(incident, row, .current)
	If $$$ISERR(sc) Quit sc
	Set expect = ..Expected(row)
	If current '= expect Quit $$$ERROR($$$GeneralError, ..Reason(..#CHANGEDAGAIN, incident, row))
	Set targets = row.%Id()
	Set dryRun = {}
	Do dryRun.%Set("item", row.Item, "string")
	Do dryRun.%Set("field", row.Setting, "string")
	Do dryRun.%Set("before", current, "string")
	Do dryRun.%Set("after", ..Restored(row), "string")
	Quit $$$OK
}

/// The value that the setting must have now for the kind to act: the change's new value.
ClassMethod Expected(row As OcuTalon.Data.SettingChange) As %String
{
	Quit row.NewValue
}

/// The value that the kind leaves the setting with: the change's old value.
ClassMethod Restored(row As OcuTalon.Data.SettingChange) As %String
{
	Quit row.OldValue
}

/// The reason that this kind is not offered for the incident: the online demo (ONLINESHARED) or OcuTalon's own production (OWNPRODUCTION); "" otherwise.
ClassMethod Refusal(incident As OcuTalon.Data.Incident) As %String
{
	If ##class(OcuTalon.Watch.Reader).OnlineDemo() Quit ..#ONLINESHARED
	If incident.Production = ##class(OcuTalon.Install.Step.Production).#PRODUCTION Quit ..#OWNPRODUCTION
	Quit ""
}

/// The reason that the change named by the parameters can't be put back, "" when it can (see the class description for the order), and the SettingChange row in row. With window
/// 0 the change need not be in the window before the first failure (an undo asks for the rollback's change, which is).
ClassMethod Vetted(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, window As %Boolean, Output row As OcuTalon.Data.SettingChange) As %String
{
	Set row = ""
	Set why = ..Refusal(incident)
	If why '= "" Quit why
	Set row = ##class(OcuTalon.Data.SettingChange).RefIndexOpen(parameters.%Get("change"))
	If '$IsObject(row) || (row.Namespace '= incident.Namespace) || (row.Production '= incident.Production) {
		Set row = ""
		Quit ..#NOTFOUND
	}
	If window && '(##class(OcuTalon.Watch.SettingCause).InTime(row.DetectedAt, incident.FirstAt) && '(##class(OcuTalon.Watch.SettingCause).Oldest(row.Namespace, row.Production) ] row.DetectedAt)) Quit ..#NOTINWINDOW
	If '$ListFind(##class(OcuTalon.Watch.SettingCause).FailingItems(incident), row.Item) Quit ..Reason(..#OTHERITEM, incident, row)
	If row.Credential Quit ..Reason(..#SECRET, incident, row)
	If (row.OldValue = "") || (row.NewValue = "") || ($Length(row.OldValue) > ..#VALUEMAX) || ($Length(row.NewValue) > ..#VALUEMAX) Quit ..Reason(..#VALUES, incident, row)
	Quit ""
}

/// The reason text with {item} (the first failing item), {setting} and {target} (the change's item) filled in.
ClassMethod Reason(text As %String, incident As OcuTalon.Data.Incident, row As OcuTalon.Data.SettingChange) As %String
{
	Set failing = ##class(OcuTalon.Watch.SettingCause).FailingItems(incident)
	Set item = $Select($ListLength(failing) > 0: $List(failing, 1), 1: "")
	Set text = $Replace(text, "{item}", item)
	If $IsObject(row) {
		Set text = $Replace(text, "{setting}", row.Setting)
		Set text = $Replace(text, "{target}", row.Item)
	}
	Quit text
}

/// The effective value of the change's setting now, read through Watch.Reader.Settings, in current ("" when the item has no such setting), and in default the value that the item
/// would have if its stored setting were taken out (the System Default Setting that applies, else the class's default; "" when there is none). An error status that is the kind's
/// NOREAD when the production can't be read.
ClassMethod Current(incident As OcuTalon.Data.Incident, row As OcuTalon.Data.SettingChange, Output current As %String, Output default As %String) As %Status
{
	Set current = ""
	Set default = ""
	Set outcome = ##class(OcuTalon.Watch.Reader).Settings(incident.Namespace, incident.Production, 2, , .marks, .settings)
	If outcome '= "read" Quit $$$ERROR($$$GeneralError, ..#NOREAD)
	Set iterator = settings.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.item = row.Item) && (entry.target = row.Target) && (entry.setting = row.Setting) {
			Set current = entry.value
			Set default = entry.%Get("default")
			Quit
		}
	}
	Quit $$$OK
}

/// Re-checks the change of an approved request before it is made (see the class description): passed holds the target when it passes, skipped holds {"id", "reason"} when it does
/// not. It changes nothing. An error status when the parameters don't pass CheckParameters or the production can't be read.
ClassMethod Recheck(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output passed As %String, Output skipped As %DynamicArray) As %Status
{
	Set passed = ""
	Set skipped = []
	Set sc = ..Plan(incident, parameters, targets, .plan, .skipped)
	If $$$ISERR(sc) Quit sc
	If plan.%Size() > 0 Set passed = targets
	Quit $$$OK
}

/// Changes the setting of the target through Fix.Executor.InProduction (see the class description). The target is read again by the same test as Recheck, so that a change that
/// moved since the re-check is skipped. result is {"changed", "skipped", "unreached"}. An error status when the production can't be read.
ClassMethod Execute(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output result As %DynamicObject, run As OcuTalon.Data.FixRun = "") As %Status
{
	Set result = {"changed": 0, "skipped": [], "unreached": []}
	Set sc = ..Plan(incident, parameters, targets, .plan, .skipped, run)
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

/// The test of Recheck and Execute over the target: plan holds one entry {"id", "setting", "target", "item", "production", "expect", "value"} (and "remove" 1 for an undo that takes
/// the stored setting out) when the target passes, skipped {"id", "reason"} when it does not. An error status when the parameters don't pass CheckParameters or the production
/// can't be read. run is the FixRun of Execute ("" for Recheck); a subclass that has a value to hold the run to reads the approved request through it.
ClassMethod Plan(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output plan As %DynamicArray, Output skipped As %DynamicArray, run As OcuTalon.Data.FixRun = "") As %Status [ Private ]
{
	Set plan = []
	Set skipped = []
	Set sc = ..CheckParameters(parameters, "")
	If $$$ISERR(sc) Quit sc
	Set id = +targets
	Set why = ..Vetted(incident, parameters, 1, .row)
	If (why = "") && (row.%Id() '= id) Set why = ..#NOTFOUND
	If why '= "" {
		Do skipped.%Push({"id": (id), "reason": (why)})
		Quit $$$OK
	}
	Set sc = ..Current(incident, row, .current)
	If $$$ISERR(sc) Quit sc
	If current '= ..Expected(row) {
		Do skipped.%Push({"id": (id), "reason": (..Reason(..#CHANGEDAGAIN, incident, row))})
		Quit $$$OK
	}
	Do plan.%Push(..Entry(id, incident, row))
	Quit $$$OK
}

/// The plan entry of the change (see Plan).
ClassMethod Entry(id As %String, incident As OcuTalon.Data.Incident, row As OcuTalon.Data.SettingChange) As %DynamicObject [ Private ]
{
	Set entry = {"id": (id), "setting": (row.Setting), "target": (row.Target), "item": (row.Item), "production": (incident.Production)}
	Do entry.%Set("expect", ..Expected(row), "string")
	Do entry.%Set("value", ..Restored(row), "string")
	Quit entry
}

/// The CHANGEDAGAIN reason for a setting and the item it is on, as the executor gives it for a change that moved after the re-check.
ClassMethod ChangedAgain(setting As %String, item As %String) As %String
{
	Quit $Replace($Replace(..#CHANGEDAGAIN, "{setting}", setting), "{target}", item)
}

}
