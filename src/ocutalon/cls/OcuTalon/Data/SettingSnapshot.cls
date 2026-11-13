/// One snapshot of the settings of a watched production (AD-15, Story 36.1; Lane A). SettingHistory is its only writer and Purge its only deleter. The
/// newest row of a production also holds the last values seen: the production-change counter (Counter), the production's start mark (Started) and the
/// time of the last check (CheckedAt), which SettingHistory updates in place when a check finds the content the same. Settings is a JSON array of
/// {"item", "target", "setting", "value", "source", "credential", "hash"}: a setting that references an Ens.Config.Credentials entry keeps its ID, and a
/// secret value is never kept, only a salted hash that tells a later read that it changed. The hash never leaves this table. No column names who made a change.
Class OcuTalon.Data.SettingSnapshot Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.SettingSnap";

/// The status code of a %DeleteId whose row is already gone ($$$DeleteObjectNotFound).
Parameter NOTFOUND [ Final ] = 5810;

/// The public reference: 22 base64url characters from OcuTalon.Bridge.Ids.NewRef(). Compared exactly.
Property Ref As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The namespace of the watched production. Compared exactly.
Property Namespace As %String(COLLATION = "EXACT", MAXLEN = 128);

/// The watched production class. Compared exactly.
Property Production As %String(COLLATION = "EXACT", MAXLEN = 128);

/// When the snapshot was taken, UTC to the second.
Property TakenAt As %String(MAXLEN = 20);

/// When the settings were last checked against the production, UTC to the second.
Property CheckedAt As %String(MAXLEN = 20);

/// The namespace's production-change counter when the settings were read, "" when it had none.
Property Counter As %String(MAXLEN = 40);

/// The production's start mark when the settings were read: its start time and check sum, joined by "|".
Property Started As %String(MAXLEN = 128);

/// The settings, as a JSON array, in a stream that is stored uncompressed (SettingStream), so that a scan of the globals can find the hash in it.
Property Settings As OcuTalon.Data.SettingStream;

Index RefIndex On Ref [ Unique ];

Index ProductionIndex On (Namespace, Production);

/// The ID of the newest snapshot of the production in the namespace, or "".
ClassMethod Newest(namespace As %String, production As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM OcuTalon_Data.SettingSnapshot WHERE Namespace = ? AND Production = ? ORDER BY ID DESC", $Get(namespace), $Get(production))
	If result.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$SQLError, result.%SQLCODE, result.%Message))
	Quit $Select(result.%Next(): result.%GetData(1), 1: "")
}

/// Deletes the snapshots taken before the purge cutoff, Bridge.Time.DaysCutoff(daysToKeep), except the newest snapshot of each watched production
/// (FailurePoller Watched), so that a production's history never starts again as a first snapshot. daysToKeep must be a whole number of at least 1:
/// anything else is an error status and nothing is deleted, and an empty cutoff (nothing is old enough) deletes nothing. A row that is already gone is not
/// an error. Returns OK when no old row is left, else the first error.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Set sc = ##class(OcuTalon.Bridge.Time).DaysCutoff($Get(daysToKeep), "OcuTalon.Data.SettingSnapshot.Purge", .cutoff)
	If $$$ISERR(sc) || (cutoff = "") Quit sc
	Try {
		Set iterator = ##class(OcuTalon.Watch.FailurePoller).Watched().%GetIterator()
		While iterator.%GetNext(, .entry) {
			Set newest = ..Newest(entry.namespace, entry.production)
			If newest '= "" Set keep(newest) = ""
		}
	} Catch exception {
		Return exception.AsStatus()
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.SettingSnapshot WHERE TakenAt < ?", cutoff)
	If result.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, result.%SQLCODE, result.%Message)
	Set count = 0
	While result.%Next() {
		If '$Data(keep(result.%GetData(1))) Set ids($Increment(count)) = result.%GetData(1)
	}
	Set sc = $$$OK
	Set n = ""
	For {
		Set n = $Order(ids(n), 1, id)
		Quit:n=""
		Set one = ..%DeleteId(id)
		If $$$ISERR(one) && '$SYSTEM.Status.Equals(one, ..#NOTFOUND) && $$$ISOK(sc) Set sc = one
	}
	Quit sc
}

Storage Default
{
<Data name="SettingSnapshotDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>Namespace</Value>
</Value>
<Value name="4">
<Value>Production</Value>
</Value>
<Value name="5">
<Value>TakenAt</Value>
</Value>
<Value name="6">
<Value>CheckedAt</Value>
</Value>
<Value name="7">
<Value>Counter</Value>
</Value>
<Value name="8">
<Value>Started</Value>
</Value>
<Value name="9">
<Value>Settings</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.SettingSnapD</DataLocation>
<DefaultData>SettingSnapshotDefaultData</DefaultData>
<IdLocation>^OcuTalonP.SettingSnapD</IdLocation>
<IndexLocation>^OcuTalonP.SettingSnapI</IndexLocation>
<StreamLocation>^OcuTalonP.SettingSnapS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
