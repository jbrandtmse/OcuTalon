Include Ensemble

/// The setting history of the watched productions (AD-15, AD-18, Story 36.1; Lane A): what changed in a production's settings, so that an incident can name
/// the change that came just before its failures. Checks calls Watch from each Tick, and the Watch area's purge calls Purge.
///   - Watch visits each watched production (FailurePoller Watched) and reads the marks through Reader.Settings: the namespace's production-change counter
///     (Interoperability's ^IRIS.Temp.EnsProdModCounter, which moves when a saved production definition or System Default Setting changes while that production runs,
///     is lost at an IRIS restart and killed when the production stops) and the production's start mark (^Ens.Runtime StartTime and CheckSum). The settings are read, and
///     a snapshot is taken, only when the production has no snapshot, a mark differs from the one on its newest snapshot (a missing counter counts as a value of its
///     own), or the newest snapshot was last checked an hour or more ago (the safety net for a change the counter does not show). When the settings are the same as
///     the newest snapshot's, only that row's marks and CheckedAt are updated in place; otherwise a new SettingSnapshot is written with one SettingChange for each
///     difference (none for the production's first snapshot), in one transaction, DetectedAt being the Tick's time. A change is therefore dated at the first Tick
///     that reads it: for a saved definition or System Default Setting, the first after it while the production runs; for a change the counter does not show (a
///     recompiled class default, a service-registry value), the hourly check; for one made while the production was stopped, the first Tick after the start or the
///     hourly check while it is stopped, whichever is earlier.
///   - A snapshot only reads: it saves nothing, updates no production and writes nothing to Ens.Config, so the counter does not move because of it. Reader is the only
///     class that enters the watched namespace. A secret value never leaves the Reader; its change shows only through a salted hash kept in the snapshot, and its
///     change row has both values blank (Reader.Settings, Data.SettingSnapshot).
///   - The history is off on the online demo, where every visitor shares the Orders production: Watch returns at once.
///   - Diff compares two settings arrays (pure); Purge removes the old rows of both tables (Data.SettingChange, Data.SettingSnapshot).
/// Watch never throws: a production whose read fails is skipped for the Tick, with one redacted warning that carries no setting value.
Class OcuTalon.Watch.SettingHistory
{

/// How long a production may go unchecked, in seconds, before its settings are read whatever the marks say.
Parameter SAFETYSECONDS = 3600;

/// The longest value kept in a change row, in characters.
Parameter VALUEMAX = 2000;

Parameter LOGPRODUCTION = "SettingHistory could not read the settings of ";

Parameter LOGWATCHED = "SettingHistory could not list the watched productions: ";

/// Checks the settings of every watched production at the Tick's time tickAt (see the class description). Always OK.
ClassMethod Watch(tickAt As %String) As %Status
{
	Try {
		If ##class(OcuTalon.Watch.Reader).OnlineDemo() Quit
		Set iterator = ##class(OcuTalon.Watch.FailurePoller).Watched().%GetIterator()
		While iterator.%GetNext(, .entry) {
			Try {
				Do ..Check(entry.namespace, entry.production, tickAt)
			} Catch exception {
				$$$LOGWARNING(..#LOGPRODUCTION_entry.production_" in "_entry.namespace_": "_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
			}
		}
	} Catch exception {
		$$$LOGWARNING(..#LOGWATCHED_##class(OcuTalon.Bridge.Redact).Text(exception.DisplayString()))
	}
	Quit $$$OK
}

/// One production's check (see the class description). An error is the caller's warning.
ClassMethod Check(namespace As %String, production As %String, tickAt As %String) [ Private ]
{
	Set id = ##class(OcuTalon.Data.SettingSnapshot).Newest(namespace, production)
	Set last = $Select(id '= "": ##class(OcuTalon.Data.SettingSnapshot).%OpenId(id), 1: "")
	If ##class(OcuTalon.Watch.Reader).Settings(namespace, production, 0, , .marks) '= "read" Quit
	If '..Due(last, marks, tickAt) Quit
	If ##class(OcuTalon.Watch.Reader).Settings(namespace, production, 1, ..Salts(last), .marks, .after) '= "read" Quit
	Do ..Record(namespace, production, tickAt, last, marks, after)
}

/// 1 when the settings of a production are to be read: it has no snapshot (last is ""), a mark of the newest snapshot (last) differs from marks, or the
/// newest snapshot was last checked SAFETYSECONDS or more before tickAt (Stale). A missing counter ("") is a value of its own (pure).
ClassMethod Due(last As OcuTalon.Data.SettingSnapshot, marks As %DynamicObject, tickAt As %String) As %Boolean
{
	If '$IsObject(last) Quit 1
	If (last.Counter '= marks.counter) || (last.Started '= marks.started) Quit 1
	Quit ..Stale(last.CheckedAt, tickAt)
}

/// The earlier hashes of the secret settings of the snapshot (last), for Reader.Settings: a dynamic object of Reader.SaltKey to hash; {} without a snapshot.
ClassMethod Salts(last As OcuTalon.Data.SettingSnapshot) As %DynamicObject
{
	Set salts = {}
	If '$IsObject(last) Quit salts
	Set iterator = ##class(%Library.DynamicAbstractObject).%FromJSON(last.Settings).%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.credential Do salts.%Set(##class(OcuTalon.Watch.Reader).SaltKey(entry.item, entry.target, entry.setting), entry.hash)
	}
	Quit salts
}

/// Keeps the settings (after, the shape of Reader.Settings' settings) read at the Tick's time tickAt, with the marks, against the newest snapshot (last, or ""
/// for a production's first). The differences are Diff(last's settings, after), none for a first snapshot. With none, last's marks and CheckedAt are
/// updated in place; otherwise a new SettingSnapshot is saved with one SettingChange for each difference, DetectedAt being tickAt, all in one transaction.
/// Gives the differences, a dynamic array. An error is thrown, with nothing saved.
ClassMethod Record(namespace As %String, production As %String, tickAt As %String, last As OcuTalon.Data.SettingSnapshot, marks As %DynamicObject, after As %DynamicArray) As %DynamicArray
{
	Set changes = $Select($IsObject(last): ..Diff(##class(%Library.DynamicAbstractObject).%FromJSON(last.Settings), after), 1: [])
	If $IsObject(last) && (changes.%Size() = 0) {
		Set last.Counter = marks.counter
		Set last.Started = marks.started
		Set last.CheckedAt = tickAt
		$$$ThrowOnError(last.%Save())
		Quit changes
	}
	Set snapshot = ##class(OcuTalon.Data.SettingSnapshot).%New()
	Set snapshot.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set snapshot.Namespace = namespace
	Set snapshot.Production = production
	Set snapshot.TakenAt = tickAt
	Set snapshot.CheckedAt = tickAt
	Set snapshot.Counter = marks.counter
	Set snapshot.Started = marks.started
	Do snapshot.Settings.Write(after.%ToJSON())
	TStart
	Try {
		$$$ThrowOnError(snapshot.%Save())
		Set iterator = changes.%GetIterator()
		While iterator.%GetNext(, .change) {
			Set row = ##class(OcuTalon.Data.SettingChange).%New()
			Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
			Set row.SnapshotRef = snapshot.Ref
			Set row.Namespace = namespace
			Set row.Production = production
			Set row.Item = change.item
			Set row.Target = change.target
			Set row.Setting = change.setting
			Set row.OldValue = $Extract(change.oldValue, 1, ..#VALUEMAX)
			Set row.NewValue = $Extract(change.newValue, 1, ..#VALUEMAX)
			Set row.Source = change.source
			Set row.Credential = change.credential
			Set row.DetectedAt = tickAt
			$$$ThrowOnError(row.%Save())
		}
		TCommit
	} Catch exception {
		TRollback 1
		Throw exception
	}
	Quit changes
}

/// 1 when the time checkedAt is SAFETYSECONDS or more before tickAt, or either is not a time (pure).
ClassMethod Stale(checkedAt As %String, tickAt As %String) As %Boolean
{
	Set checked = ##class(OcuTalon.Data.Time).Seconds($Get(checkedAt))
	Set now = ##class(OcuTalon.Data.Time).Seconds($Get(tickAt))
	If (checked = "") || (now = "") Quit 1
	Quit (now - checked) '< ..#SAFETYSECONDS
}

/// The differences between two arrays of settings (the shape of Reader.Settings' settings): a dynamic array of {"item", "target", "setting", "oldValue",
/// "newValue", "source", "credential"}, one for each setting that is only in after (oldValue ""), only in before (newValue "") or has another value. A secret
/// setting (credential 1) differs when its hash does, and its two values are "" (pure).
ClassMethod Diff(before As %DynamicArray, after As %DynamicArray) As %DynamicArray
{
	Set changes = []
	Kill old, seen
	Set iterator = before.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set old(entry.item, entry.target, entry.setting) = entry
	}
	Set iterator = after.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set seen(entry.item, entry.target, entry.setting) = ""
		If '$Data(old(entry.item, entry.target, entry.setting), earlier) {
			Do changes.%Push(..Change("", entry))
		} Else {
			If (entry.credential '= earlier.credential) || (entry.hash '= earlier.hash) || (entry.value '= earlier.value) Do changes.%Push(..Change(earlier, entry))
		}
	}
	Set iterator = before.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If '$Data(seen(entry.item, entry.target, entry.setting)) Do changes.%Push(..Change(entry, ""))
	}
	Quit changes
}

/// One change of Diff: from the entry earlier to the entry later, either of which may be "" (the setting was not there). The row names the later entry's
/// source, the earlier one's when the setting is gone.
ClassMethod Change(earlier As %DynamicObject, later As %DynamicObject) As %DynamicObject [ Private ]
{
	Set base = $Select($IsObject(later): later, 1: earlier)
	If '$IsObject(earlier) Set earlier = {"value": "", "credential": 0}
	If '$IsObject(later) Set later = {"value": "", "credential": 0}
	Set secret = (earlier.credential || later.credential)
	Quit {"item": (base.item), "target": (base.target), "setting": (base.setting), "oldValue": ($Select(secret: "", 1: earlier.value)), "newValue": ($Select(secret: "", 1: later.value)), "source": (base.source), "credential": (+secret)}
}

/// Removes the setting snapshots and the setting changes older than daysToKeep days, and keeps the newest snapshot of each watched production (see
/// Data.SettingSnapshot Purge and Data.SettingChange Purge). Both run whatever the other returned; the result is the first error.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Set changes = ##class(OcuTalon.Data.SettingChange).Purge(daysToKeep)
	Set snapshots = ##class(OcuTalon.Data.SettingSnapshot).Purge(daysToKeep)
	If $SYSTEM.Status.IsError(changes) Quit changes
	Quit snapshots
}

}
