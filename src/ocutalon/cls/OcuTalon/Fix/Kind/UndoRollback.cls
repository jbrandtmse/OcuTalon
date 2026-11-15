/// The fix kind that undoes a rollback (AD-16; Story 23.3): it puts back the value that rollback_setting replaced, the change's new value. The user asks for it in the chat
/// (propose_fix; ASKED 1) and the diagnosis never names it (DIAGNOSED 0, CATEGORY empty). It extends RollbackSetting, as ResumeItem extends SuspendItem, and it never moves the
/// incident's state (MOVES 0), so it may be asked for on a closed incident (ASKEDSTATES).
///   - AskedParameters sets the parameter change from the incident's rollback that is still to undo (Fix.Run RolledBack: the newest done rollback_setting that changed its setting,
///     with no done undo_rollback after it); with none it refuses with NOTHINGTOUNDO. So there is one undo for each rollback, and an undo is never itself undone.
///   - DryRun refuses as RollbackSetting does, but a change need not be in the window, and it requires that the change is the rollback still to undo (NOTHINGTOUNDO). An undo is
///     offered only while the rollback is the setting's latest change: a later change of the same setting, or a current value that is not the one that the rollback restored,
///     refuses with CHANGEDAGAIN. Its answer is {"item", "field", "before" (the restored value), "after" (the value the setting will have)}.
///   - When the rolled-back change came from a System Default Setting (its Source is not production), the rollback added an item-level value and the undo takes that stored setting
///     out, so that the inherited value applies again; it never writes a copy of the new value at item level, and its dry run's After is the inherited value. Otherwise the undo
///     writes the new value as the stored setting. Lane A.
Class OcuTalon.Fix.Kind.UndoRollback Extends OcuTalon.Fix.Kind.RollbackSetting
{

Parameter NAME = "undo_rollback";

Parameter CATEGORY;

Parameter DIAGNOSED = 0;

Parameter ASKED = 1;

Parameter MOVES = 0;

Parameter ASKEDSTATES = "open,resolved,closed";

Parameter UNDO = 1;

/// The change of the incident's rollback that is still to undo, for a request that the chat asks for. An error status with the NOTHINGTOUNDO reason when there is none.
ClassMethod AskedParameters(incident As OcuTalon.Data.Incident, ByRef parameters As %DynamicObject) As %Status
{
	Set ref = ##class(OcuTalon.Fix.Run).RolledBack(incident.Ref)
	If ref = "" Quit $$$ERROR($$$GeneralError, ..#NOTHINGTOUNDO)
	Set parameters = {"change": (ref)}
	Quit $$$OK
}

/// The dry run of the undo (see the class description).
ClassMethod DryRun(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, Output targets As %String, Output dryRun As %DynamicObject) As %Status
{
	Set targets = ""
	Set dryRun = ""
	Set sc = ..CheckParameters(parameters, "")
	If $$$ISERR(sc) Quit sc
	Set why = ..Undoable(incident, parameters, .row)
	If why '= "" Quit $$$ERROR($$$GeneralError, why)
	Set sc = ..Current(incident, row, .current)
	If $$$ISERR(sc) Quit sc
	Set targets = row.%Id()
	Set dryRun = {}
	Do dryRun.%Set("item", row.Item, "string")
	Do dryRun.%Set("field", row.Setting, "string")
	Do dryRun.%Set("before", current, "string")
	Do dryRun.%Set("after", ..After(row, incident), "string")
	Quit $$$OK
}

/// The reason that the change can't be undone, "" when it can, and the SettingChange row in row: the refusals of Vetted (no window), the rollback still to undo (NOTHINGTOUNDO),
/// a later change of the setting and a current value that is not the restored one (CHANGEDAGAIN).
ClassMethod Undoable(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, Output row As OcuTalon.Data.SettingChange) As %String
{
	Set why = ..Vetted(incident, parameters, 0, .row)
	If why '= "" Quit why
	If ##class(OcuTalon.Fix.Run).RolledBack(incident.Ref) '= row.Ref Quit ..#NOTHINGTOUNDO
	If ..ChangedLater(row) Quit ..Reason(..#CHANGEDAGAIN, incident, row)
	Set sc = ..Current(incident, row, .current)
	If $$$ISERR(sc) Quit $SYSTEM.Status.GetOneErrorText(sc)
	If current '= ..Expected(row) Quit ..Reason(..#CHANGEDAGAIN, incident, row)
	Quit ""
}

/// 1 when the setting of the change was changed again after the rollback: a row of the same item, target and setting detected after the change, other than the one the rollback made
/// itself (the first row that goes from the change's new value back to its old one).
ClassMethod ChangedLater(row As OcuTalon.Data.SettingChange) As %Boolean
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT OldValue, NewValue FROM OcuTalon_Data.SettingChange WHERE Namespace = ? AND Production = ? AND Item = ? AND Target = ? AND Setting = ? AND DetectedAt > ? ORDER BY DetectedAt, ID", row.Namespace, row.Production, row.Item, row.Target, row.Setting, row.DetectedAt)
	If result.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, result.%SQLCODE, result.%Message))
	Set skipped = 0
	While result.%Next() {
		If 'skipped && (result.%GetData(1) = row.NewValue) && (result.%GetData(2) = row.OldValue) {
			Set skipped = 1
			Continue
		}
		Return 1
	}
	Quit 0
}

/// The value that the undo leaves the setting with, as the dry run's After shows it: the change's new value. For a change of a System Default Setting that is the value the item
/// inherits again once its stored setting is taken out.
ClassMethod After(row As OcuTalon.Data.SettingChange, incident As OcuTalon.Data.Incident) As %String
{
	Quit row.NewValue
}

/// The value that the setting must have now for the undo to act: the value that the rollback restored, the change's old value.
ClassMethod Expected(row As OcuTalon.Data.SettingChange) As %String
{
	Quit row.OldValue
}

/// The value that the undo leaves the setting with.
ClassMethod Restored(row As OcuTalon.Data.SettingChange) As %String
{
	Quit row.NewValue
}

/// The test of Recheck and Execute over the target, as RollbackSetting's, with the undo's own refusals and plan entry.
ClassMethod Plan(incident As OcuTalon.Data.Incident, parameters As %DynamicObject, targets As %String, Output plan As %DynamicArray, Output skipped As %DynamicArray) As %Status [ Private ]
{
	Set plan = []
	Set skipped = []
	Set sc = ..CheckParameters(parameters, "")
	If $$$ISERR(sc) Quit sc
	Set id = +targets
	Set why = ..Undoable(incident, parameters, .row)
	If (why = "") && (row.%Id() '= id) Set why = ..#NOTFOUND
	If why '= "" {
		Do skipped.%Push({"id": (id), "reason": (why)})
		Quit $$$OK
	}
	Set entry = ..Entry(id, incident, row)
	If row.Source '= "production" {
		Do entry.%Set("remove", 1, "number")
	}
	Do plan.%Push(entry)
	Quit $$$OK
}

}
