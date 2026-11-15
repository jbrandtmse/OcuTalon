/// The setting change behind an incident (AD-15, Story 23.3; Lane A): the production's SettingChange rows from the 24 hours before the first failure, the change that a
/// setting_change diagnosis names, the gap between the two and the cause slot of the incident's notice. It reads rows and writes nothing, and it enters no namespace.
///   - A row is in the window when it is of the incident's namespace and production, FirstAt - WINDOWSECONDS <= DetectedAt <= FirstAt, and DetectedAt is not before the TakenAt
///     of the production's oldest snapshot: a production's first snapshot records no change, and a change that the oldest snapshot recorded itself is still listed once the purge
///     has removed the snapshots before it. Window gives those rows newest first, as {"ref", "item", "target", "setting", "oldValue", "newValue", "source", "credential",
///     "detectedAt"}. A secret row has blank values and credential 1. Nothing names who made a change.
///   - AddTo puts the window into an evidence pack as settingChanges: at most MAXCHANGES rows, newest first, as {"item", "target", "setting", "oldValue", "newValue", "source",
///     "credential", "detectedAt"}, each value cut to MAXVALUE characters with its own note, and settingChangesNote when rows were left out. For a recorded snapshot it applies
///     the window's time rule to the snapshot's settingChanges, against the pack's firstAt. The values are the watched production's data: they are redacted like a message
///     body and sit in the pack after the line that calls the pack data, never instructions.
///   - Named is the newest row of the window whose setting is the element of the diagnosis, on a failing item first. GapMinutes is whole minutes, rounded half up. CauseSlot is
///     the structured cause of incident.settingChangeCause, rendered by the catalog.
///   - IsSetting, RollbackSlots, UndoSlots, ResultKey, ResultSlots, Names and the summary keys are the notice and summary texts of the two setting kinds (Fix.Kind.RollbackSetting and
///     UndoRollback), which Notice and Summary call, so that the kinds' texts live here and the two classes only delegate.
Class OcuTalon.Watch.SettingCause
{

/// The most rows that the pack lists.
Parameter MAXCHANGES = 10;

/// The most characters of a value that the pack shows.
Parameter MAXVALUE = 500;

/// The length of the window before the first failure, in seconds.
Parameter WINDOWSECONDS = 86400;

/// The notes of a cut, for the model only, in ASCII.
Parameter CHANGESNOTE = "[cut by OcuTalon: {shown} of {total} setting changes shown]";

Parameter VALUENOTE = "[cut by OcuTalon: {shown} of {total} characters shown]";

/// The catalog keys of the setting kinds' notices.
Parameter KEYROLLBACKREQUEST = "incident.rollbackRequest";

Parameter KEYUNDOREQUEST = "incident.undoRollbackRequest";

Parameter KEYRESTORED = "result.settingRestored";

Parameter KEYUNDONE = "result.rollbackUndone";

Parameter KEYCHANGEDSINCE = "result.settingChangedSince";

Parameter KEYNOTCHANGED = "result.itemNotChanged";

Parameter KEYSAVEDNOTAPPLIED = "result.settingSavedNotApplied";

Parameter KEYSUMMARYROLLBACK = "summary.requestedRollback";

Parameter KEYSUMMARYUNDO = "summary.requestedUndoRollback";

Parameter KEYSUMMARYRESTORED = "summary.settingRestored";

Parameter KEYSUMMARYUNDONE = "summary.rollbackUndone";

Parameter KEYSUMMARYNOTCHANGED = "summary.settingNotChanged";

/// The TakenAt of the oldest snapshot of the production in the namespace, "" when it has none.
ClassMethod Oldest(namespace As %String, production As %String) As %String
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 TakenAt FROM OcuTalon_Data.SettingSnapshot WHERE Namespace = ? AND Production = ? ORDER BY ID", $Get(namespace), $Get(production))
	If result.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, result.%SQLCODE, result.%Message))
	Quit $Select(result.%Next(): result.%GetData(1), 1: "")
}

/// The start of the window before firstAt, "" when firstAt is not a time.
ClassMethod WindowStart(firstAt As %String) As %String
{
	Quit ##class(OcuTalon.Data.Time).AddSeconds(firstAt, -..#WINDOWSECONDS)
}

/// 1 when the time of a change is in the window before firstAt (see the class description), without the test of the oldest snapshot. Pure.
ClassMethod InTime(detectedAt As %String, firstAt As %String) As %Boolean
{
	Set start = ..WindowStart($Get(firstAt))
	If (start = "") || (##class(OcuTalon.Data.Time).Seconds($Get(detectedAt)) = "") Quit 0
	Quit '(start ] detectedAt) && '(detectedAt ] firstAt)
}

/// The window's rows newest first (see the class description) into rows, a dynamic array. Empty on the online demo, whose history is off, and for a firstAt that is not a time.
ClassMethod Window(namespace As %String, production As %String, firstAt As %String, Output rows As %DynamicArray)
{
	Set rows = []
	If ##class(OcuTalon.Watch.Reader).OnlineDemo() Quit
	Set start = ..WindowStart($Get(firstAt))
	If start = "" Quit
	Set oldest = ..Oldest(namespace, production)
	If oldest = "" Quit
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.SettingChange WHERE Namespace = ? AND Production = ? AND DetectedAt >= ? AND DetectedAt <= ? AND DetectedAt >= ? ORDER BY DetectedAt DESC, ID DESC", $Get(namespace), $Get(production), start, firstAt, oldest)
	If result.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, result.%SQLCODE, result.%Message))
	Set count = 0
	While result.%Next() {
		Set ids($Increment(count)) = result.%GetData(1)
	}
	For i = 1:1:count {
		Set row = ##class(OcuTalon.Data.SettingChange).%OpenId(ids(i))
		If $IsObject(row) Do rows.%Push(..Entry(row))
	}
}

/// The row of a SettingChange as the window gives it.
ClassMethod Entry(row As OcuTalon.Data.SettingChange) As %DynamicObject
{
	Set entry = {"ref": (row.Ref), "item": (row.Item), "target": (row.Target), "setting": (row.Setting)}
	Set secret = +row.Credential
	Do entry.%Set("oldValue", $Select(secret: "", 1: row.OldValue), "string")
	Do entry.%Set("newValue", $Select(secret: "", 1: row.NewValue), "string")
	Set entry.source = row.Source
	Do entry.%Set("credential", secret, "boolean")
	Set entry.detectedAt = row.DetectedAt
	Quit entry
}

/// Puts the pack's settingChanges and settingChangesNote in (see the class description). source is the incident of a live pack, or the reader snapshot of a recorded one. A pack
/// with no change in its window gets neither key.
ClassMethod AddTo(pack As %DynamicObject, source)
{
	Set rows = []
	If source.%IsA("OcuTalon.Data.Incident") {
		Do ..Window(source.Namespace, source.Production, source.FirstAt, .rows)
	} ElseIf $IsObject(source.settingChanges) && source.settingChanges.%IsA("%Library.DynamicArray") {
		Set list = []
		Set iterator = source.settingChanges.%GetIterator()
		While iterator.%GetNext(, .entry) {
			If $IsObject(entry) && ..InTime(entry.detectedAt, pack.firstAt) Do list.%Push(entry)
		}
		Set rows = ..Newest(list)
	}
	Set total = rows.%Size()
	If total = 0 Quit
	Set shown = $Select(total > ..#MAXCHANGES: ..#MAXCHANGES, 1: total)
	Set changes = []
	For i = 0:1:shown - 1 {
		Do changes.%Push(..Cut(rows.%Get(i)))
	}
	Set pack.settingChanges = changes
	If total > shown Set pack.settingChangesNote = $Replace($Replace(..#CHANGESNOTE, "{shown}", shown), "{total}", total)
}

/// The entries of the array, newest first by detectedAt (the order of the array decides between equal times).
ClassMethod Newest(list As %DynamicArray) As %DynamicArray [ Private ]
{
	Set sorted = []
	Set count = list.%Size()
	For i = 1:1:count {
		Set at = list.%Get(i - 1).detectedAt
		Set key = at _ "|" _ $Justify(count - i, 6)
		Set order(key) = list.%Get(i - 1)
	}
	Set key = ""
	For {
		Set key = $Order(order(key), -1)
		If key = "" Quit
		Do sorted.%Push(order(key))
	}
	Quit sorted
}

/// The pack's form of one row: no Ref, the values cut to MAXVALUE characters (each with its note) and redacted as one JSON object.
ClassMethod Cut(row As %DynamicObject) As %DynamicObject [ Private ]
{
	Set entry = {"item": (row.item), "target": (row.target), "setting": (row.setting)}
	Do entry.%Set("oldValue", ..CutValue(row.oldValue), "string")
	Do entry.%Set("newValue", ..CutValue(row.newValue), "string")
	Set entry.source = row.source
	Do entry.%Set("credential", +row.credential, "boolean")
	Set entry.detectedAt = row.detectedAt
	Set copy = ""
	Try {
		Set copy = ##class(%Library.DynamicAbstractObject).%FromJSON(##class(OcuTalon.Bridge.Redact).Text(entry.%ToJSON()))
	} Catch {
		Set copy = ""
	}
	Quit $Select($IsObject(copy): copy, 1: {})
}

/// The value cut to MAXVALUE characters, with the note of the cut after it when it was longer.
ClassMethod CutValue(value As %String) As %String [ Private ]
{
	Set value = $Get(value)
	If $Length(value) '> ..#MAXVALUE Quit value
	Quit $Extract(value, 1, ..#MAXVALUE) _ $Char(10) _ $Replace($Replace(..#VALUENOTE, "{shown}", ..#MAXVALUE), "{total}", $Length(value))
}

/// The items that failed in the incident, from its failure groups, as a list.
ClassMethod FailingItems(incident As OcuTalon.Data.Incident) As %List
{
	Set items = ""
	Set groups = ##class(OcuTalon.Data.FailureGroup).OfIncident(incident.Ref)
	For i = 1:1:groups.Count() {
		If groups.GetAt(i).ItemName '= "" Set items = items _ $ListBuild(groups.GetAt(i).ItemName)
	}
	Quit items
}

/// The newest row of the incident's window whose setting is the element (matched exactly), on a failing item first, in row; 1 when there is one.
ClassMethod Named(incident As OcuTalon.Data.Incident, element As %String, Output row As %DynamicObject) As %Boolean
{
	Set row = ""
	If $Get(element) = "" Quit 0
	Do ..Window(incident.Namespace, incident.Production, incident.FirstAt, .rows)
	Set failing = ..FailingItems(incident)
	Set found = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.setting '= element Continue
		If '$IsObject(found) Set found = entry
		If $ListFind(failing, entry.item) {
			Set found = entry
			Quit
		}
	}
	If '$IsObject(found) Quit 0
	Set row = found
	Quit 1
}

/// The gap from the change (detectedAt) to the first failure (firstAt) in whole minutes, rounded half up; "" when either is not a time. A change that is not before the
/// first failure gives 0. Pure.
ClassMethod GapMinutes(detectedAt As %String, firstAt As %String) As %Integer
{
	Set from = ##class(OcuTalon.Data.Time).Seconds($Get(detectedAt))
	Set to = ##class(OcuTalon.Data.Time).Seconds($Get(firstAt))
	If (from = "") || (to = "") Quit ""
	If to '> from Quit 0
	Quit (to - from + 30) \ 60
}

/// The change that the incident names (SettingChangeRef), as a SettingChange row, or "".
ClassMethod Change(incident As OcuTalon.Data.Incident) As OcuTalon.Data.SettingChange
{
	If incident.SettingChangeRef = "" Quit ""
	Quit ##class(OcuTalon.Data.SettingChange).RefIndexOpen(incident.SettingChangeRef)
}

/// The cause slot of the incident's notice into slot, {"setting", "target" (the item), "time" (when the change was detected), "minutes"}; "" when the incident names no change.
ClassMethod CauseSlot(incident As OcuTalon.Data.Incident, Output slot As %DynamicObject) As %Boolean
{
	Set slot = ""
	Set row = ..Change(incident)
	If '$IsObject(row) Quit 0
	Set minutes = ..GapMinutes(row.DetectedAt, incident.FirstAt)
	If minutes = "" Quit 0
	Set slot = {"setting": (row.Setting), "target": (row.Item), "time": (row.DetectedAt), "minutes": (+minutes)}
	Quit 1
}

/// 1 when the request parameters (JSON text or a dynamic object) are those of a setting kind: an object whose only key is change.
ClassMethod IsSetting(parameters As %String = "") As %Boolean
{
	If '$IsObject(parameters) {
		If parameters = "" Quit 0
		Try {
			Set parameters = {}.%FromJSON(parameters)
		} Catch {
			Set parameters = ""
		}
	}
	If '$IsObject(parameters) || 'parameters.%IsA("%Library.DynamicObject") Quit 0
	Quit parameters.%IsDefined("change") && (parameters.%Size() = 1)
}

/// 1 when the fix kind is one that a setting_change diagnosis may name and that acts on a setting (rollback_setting).
ClassMethod Offers(kind As %String) As %Boolean
{
	Set class = ##class(OcuTalon.Fix.Kind).ForName($Get(kind))
	Quit (class '= "") && ($Parameter(class, "TARGETTYPE") = "setting") && ''$Parameter(class, "DIAGNOSED")
}

/// The slots of incident.rollbackRequest into slots (the incident's common slots), from the request's dry run: setting, target (the item), before and after, and cause, the
/// structured cause slot (CauseSlot). An error status when the dry run lacks one of them or the incident names no change.
ClassMethod RollbackSlots(incident As OcuTalon.Data.Incident, dryRun As %DynamicObject, slots As %DynamicObject) As %Status
{
	If '$IsObject($Get(dryRun)) Quit $SYSTEM.Status.Error(5001, "The dry run of incident "_incident.Ref_" is not an object")
	If '..CauseSlot(incident, .cause) Quit $SYSTEM.Status.Error(5001, "The incident "_incident.Ref_" names no setting change")
	Set setting = ..Text(dryRun.field)
	Set target = ..Text(dryRun.item)
	Set before = ..Text(dryRun.before)
	Set after = ..Text(dryRun.after)
	If (setting = "") || (target = "") || (before = "") || (after = "") Quit $SYSTEM.Status.Error(5001, "The dry run of incident "_incident.Ref_" has no item, field, before or after")
	Do slots.%Set("cause", cause)
	Do slots.%Set("setting", setting, "string")
	Do slots.%Set("target", target, "string")
	Do slots.%Set("before", before, "string")
	Do slots.%Set("after", after, "string")
	Quit $$$OK
}

/// The slots of incident.undoRollbackRequest from the request's dry run: setting, target, before and after. "" with the reason in sc when the dry run lacks one of them.
ClassMethod UndoSlots(dryRun As %DynamicObject, incident As OcuTalon.Data.Incident, Output sc As %Status) As %DynamicObject
{
	Set sc = $$$OK
	If '$IsObject($Get(dryRun)) {
		Set sc = $SYSTEM.Status.Error(5001, "The dry run of incident "_incident.Ref_" is not an object")
		Quit ""
	}
	Set setting = ..Text(dryRun.field)
	Set target = ..Text(dryRun.item)
	Set before = ..Text(dryRun.before)
	Set after = ..Text(dryRun.after)
	If (setting = "") || (target = "") || (before = "") || (after = "") {
		Set sc = $SYSTEM.Status.Error(5001, "The dry run of incident "_incident.Ref_" has no item, field, before or after")
		Quit ""
	}
	Set slots = {}
	Do slots.%Set("setting", setting, "string")
	Do slots.%Set("target", target, "string")
	Do slots.%Set("before", before, "string")
	Do slots.%Set("after", after, "string")
	Quit slots
}

/// The catalog key of the result of a setting kind's run (the kind is the class's NAME): the restore or the undo when the run changed the setting, result.settingSavedNotApplied
/// when the setting was saved and the production could not apply it and the earlier value could not be put back (Unreached above 0, with the production's error as the reason),
/// result.settingChangedSince when it was skipped because the setting changed again (the reason ends as the kind's CHANGEDAGAIN does), else result.itemNotChanged. Pure.
ClassMethod ResultKey(kind As %String, result As OcuTalon.Fix.Msg.FixResult) As %String
{
	If +result.Completed > 0 Quit $Select(kind = ##class(OcuTalon.Fix.Kind.UndoRollback).#NAME: ..#KEYUNDONE, 1: ..#KEYRESTORED)
	If +result.Unreached > 0 Quit ..#KEYSAVEDNOTAPPLIED
	Set tail = $Piece(##class(OcuTalon.Fix.Kind.RollbackSetting).#CHANGEDAGAIN, "}", *)
	If (+result.Skipped > 0) && (tail '= "") && ($Extract(result.Reason, *-$Length(tail)+1, *) = tail) Quit ..#KEYCHANGEDSINCE
	Quit ..#KEYNOTCHANGED
}

/// 1 when the key is one of ResultKey's.
ClassMethod IsResultKey(key As %String) As %Boolean
{
	Quit ''$ListFind($ListBuild(..#KEYRESTORED, ..#KEYUNDONE, ..#KEYCHANGEDSINCE, ..#KEYSAVEDNOTAPPLIED), $Get(key))
}

/// The slots of a setting kind's result key: setting, target and after (the restore and the undo), setting and target (settingChangedSince), setting, target and reason
/// (settingSavedNotApplied). extra is what IncidentManager ResultExtra gives and reason the result's reason. "" with the reason in sc when one is missing.
ClassMethod ResultSlots(key As %String, extra As %DynamicObject, Output sc As %Status, reason As %String = "") As %DynamicObject
{
	Set sc = $$$OK
	Set setting = ..Text(extra.setting)
	Set target = ..Text(extra.target)
	Set after = ..Text(extra.after)
	Set reason = ..Text(reason)
	Set plain = (key = ..#KEYCHANGEDSINCE) || (key = ..#KEYSAVEDNOTAPPLIED)
	If (setting = "") || (target = "") || ('plain && (after = "")) || ((key = ..#KEYSAVEDNOTAPPLIED) && (reason = "")) {
		Set sc = $SYSTEM.Status.Error(5001, "The result of a setting kind has no setting, target, value or reason")
		Quit ""
	}
	Set slots = {}
	Do slots.%Set("setting", setting, "string")
	Do slots.%Set("target", target, "string")
	If 'plain Do slots.%Set("after", after, "string")
	If key = ..#KEYSAVEDNOTAPPLIED Do slots.%Set("reason", reason, "string")
	Quit slots
}

/// The setting and the item of a setting kind's request, from its stored dry run (field and item), in setting and target; 1 when both are there.
ClassMethod Names(request As OcuTalon.Bridge.Data.ApprovalRequest, Output setting As %String, Output target As %String) As %Boolean
{
	Set setting = ""
	Set target = ""
	Try {
		Set dryRun = {}.%FromJSON(request.DryRun)
		Set setting = ..Text(dryRun.%Get("field"))
		Set target = ..Text(dryRun.%Get("item"))
	} Catch {
		Set setting = ""
		Set target = ""
	}
	Quit (setting '= "") && (target '= "")
}

/// The catalog key of the summary line of a setting kind's request being raised, and of its run's end (Watch.Summary): the first for the kind's name, the second for the run.
ClassMethod SummaryRequestKey(kind As %String) As %String
{
	Quit $Select(kind = ##class(OcuTalon.Fix.Kind.UndoRollback).#NAME: ..#KEYSUMMARYUNDO, 1: ..#KEYSUMMARYROLLBACK)
}

/// The key of the line for the end of a setting kind's run, and "" (no line) for a run whose setting was saved but could not be applied, which the summary has no text for.
ClassMethod SummaryRunKey(kind As %String, run As OcuTalon.Data.FixRun) As %String
{
	If (+run.Completed = 0) && (+run.Unreached > 0) Quit ""
	If +run.Completed = 0 Quit ..#KEYSUMMARYNOTCHANGED
	Quit $Select(kind = ##class(OcuTalon.Fix.Kind.UndoRollback).#NAME: ..#KEYSUMMARYUNDONE, 1: ..#KEYSUMMARYRESTORED)
}

/// The text of a slot value: trimmed, "" when it is not a string or a number.
ClassMethod Text(value As %String) As %String [ Private ]
{
	Quit $ZStrip($Get(value), "<>W")
}

}
