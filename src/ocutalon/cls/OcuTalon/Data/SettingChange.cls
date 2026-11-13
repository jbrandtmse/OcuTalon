/// One difference between two snapshots of a watched production's settings (AD-15, Story 36.1; Lane A): a setting of an item that was added, removed or
/// given another value. SettingHistory is its only writer and Purge its only deleter. A row names the item, the target (Host or Adapter), the setting
/// and the two values, and no one who made the change. A setting that references an Ens.Config.Credentials entry keeps both IDs; a secret value is
/// never kept, so its row has both values blank and Credential 1. DetectedAt is the time of the check that saw the difference, not of the change itself.
Class OcuTalon.Data.SettingChange Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.SettingChange";

/// The status code of a %DeleteId whose row is already gone ($$$DeleteObjectNotFound).
Parameter NOTFOUND [ Final ] = 5810;

/// The public reference: 22 base64url characters from OcuTalon.Bridge.Ids.NewRef(). Compared exactly.
Property Ref As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The Ref of the SettingSnapshot that holds the new values. Compared exactly.
Property SnapshotRef As %String(COLLATION = "EXACT", MAXLEN = 22);

/// The namespace of the watched production. Compared exactly.
Property Namespace As %String(COLLATION = "EXACT", MAXLEN = 128);

/// The watched production class. Compared exactly.
Property Production As %String(COLLATION = "EXACT", MAXLEN = 128);

/// The item whose setting differs. Compared exactly.
Property Item As %String(COLLATION = "EXACT", MAXLEN = 256);

/// Host or Adapter.
Property Target As %String(MAXLEN = 32);

/// The setting's name. Compared exactly.
Property Setting As %String(COLLATION = "EXACT", MAXLEN = 256);

/// The value before, "" when the setting or the item was not there, and for a secret value.
Property OldValue As %String(MAXLEN = 2000);

/// The value after, "" when the setting or the item is gone, and for a secret value.
Property NewValue As %String(MAXLEN = 2000);

/// Where the new value (the old one when the setting is gone) comes from: production, default (a System Default Setting) or class.
Property Source As %String(MAXLEN = 16);

/// 1 when the setting's value is a secret, whose two values are blank here.
Property Credential As %Boolean [ InitialExpression = 0 ];

/// When the check that saw the difference ran, UTC to the second.
Property DetectedAt As %String(MAXLEN = 20);

Index RefIndex On Ref [ Unique ];

Index ProductionIndex On (Namespace, Production, DetectedAt);

Index DetectedIndex On DetectedAt;

/// Deletes the rows detected before the purge cutoff, Bridge.Time.DaysCutoff(daysToKeep): rows detected at or after it stay.
/// daysToKeep must be a whole number of at least 1: anything else is an error status and nothing is deleted, and an empty cutoff (nothing is old enough) deletes nothing. A row that is already gone is not an error. Returns OK when no old row is left, else the first error.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Set sc = ##class(OcuTalon.Bridge.Time).DaysCutoff($Get(daysToKeep), "OcuTalon.Data.SettingChange.Purge", .cutoff)
	If $$$ISERR(sc) || (cutoff = "") Quit sc
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Data.SettingChange WHERE DetectedAt < ?", cutoff)
	If result.%SQLCODE < 0 Quit $$$ERROR($$$SQLError, result.%SQLCODE, result.%Message)
	Set count = 0
	While result.%Next() {
		Set ids($Increment(count)) = result.%GetData(1)
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
<Data name="SettingChangeDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ref</Value>
</Value>
<Value name="3">
<Value>SnapshotRef</Value>
</Value>
<Value name="4">
<Value>Namespace</Value>
</Value>
<Value name="5">
<Value>Production</Value>
</Value>
<Value name="6">
<Value>Item</Value>
</Value>
<Value name="7">
<Value>Target</Value>
</Value>
<Value name="8">
<Value>Setting</Value>
</Value>
<Value name="9">
<Value>OldValue</Value>
</Value>
<Value name="10">
<Value>NewValue</Value>
</Value>
<Value name="11">
<Value>Source</Value>
</Value>
<Value name="12">
<Value>Credential</Value>
</Value>
<Value name="13">
<Value>DetectedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.SettingChangeD</DataLocation>
<DefaultData>SettingChangeDefaultData</DefaultData>
<IdLocation>^OcuTalonP.SettingChangeD</IdLocation>
<IndexLocation>^OcuTalonP.SettingChangeI</IndexLocation>
<StreamLocation>^OcuTalonP.SettingChangeS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
