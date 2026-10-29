/// A product setting that no bridge class reads (AD-19). Read through Get, which keeps a 60-second per-process cache. Lane B.
Class OcuTalon.Data.Setting Extends %Persistent
{

/// The private global of the class's data and indexes, from src/short-names.tsv (AD-3).
Parameter DEFAULTGLOBAL = "^OcuTalonP.Setting";

/// How long Get keeps a value in the per-process cache (AD-19).
Parameter CACHESECONDS = 60;

/// The key of the new sessions per client address per hour, online demo (Web.SessionEvents; seeded by Install.Step.Web).
Parameter ADDRESSLIMITKEY = "onlineDemo.sessionsPerAddress";

/// The seeded value of ADDRESSLIMITKEY: new sessions per client address per hour, online demo.
Parameter ADDRESSLIMITSEED = 5;

/// The key; unique. Product keys are dotted, such as digest.time.
Property Key As %String(MAXLEN = 128);

/// The value.
Property Value As %String(MAXLEN = 1000);

/// When the value was last written, UTC to the second.
Property UpdatedAt As %String(MAXLEN = 20);

Index KeyIndex On Key [ Unique ];

/// The value of a setting, or default when the key is empty, absent or its value is empty.
/// A public key (Public.Settings KEYS or READY) is read from Public.Settings.Get, uncached. Any other key is read
/// from its row through a per-process cache for CACHESECONDS seconds:
/// ^||OcuTalon.Setting(key) = $ListBuild(value, present, $ZHorolog).
ClassMethod Get(key As %String, default As %String = "") As %String
{
	If key = "" Quit default
	If ..IsPublic(key) {
		Set value = ##class(OcuTalon.Data.Public.Settings).Get(key)
		Quit $Select(value = "": default, 1: value)
	}
	Set cached = $Get(^||OcuTalon.Setting(key))
	If (cached = "") || (($ZHorolog - $ListGet(cached, 3)) >= ..#CACHESECONDS) {
		Set row = ..KeyIndexOpen(key)
		Set cached = $ListBuild($Select($IsObject(row): row.Value, 1: ""), $IsObject(row), $ZHorolog)
		Set ^||OcuTalon.Setting(key) = cached
	}
	Quit $Select($ListGet(cached, 1) = "": default, 1: $ListGet(cached, 1))
}

/// Writes a value only when the key is absent, and drops this process's cache entry for it.
/// An empty key is refused with an error status, and so is a public key, which the status names.
ClassMethod Seed(key As %String, value As %String) As %Status
{
	Set sc = ..Refusal(key, "seeded")
	If $$$ISERR(sc) Quit sc
	Kill ^||OcuTalon.Setting(key)
	If ..KeyIndexExists(key) Quit $SYSTEM.Status.OK()
	Quit ..Upsert(key, value)
}

/// Writes a value, creating the row or replacing its value, with UpdatedAt as the time of the write, and drops this
/// process's cache entry for the key (other processes read the new value when their entries expire, within CACHESECONDS).
/// An empty key is refused with an error status, and so is a public key, which the status names. OcuTalon.Core.SettingsOps
/// is its only caller: it is the run-time writer API of AD-19, and SettingsOps checks the key against its allow-list first.
ClassMethod Set(key As %String, value As %String) As %Status
{
	Set sc = ..Refusal(key, "written")
	If $$$ISERR(sc) Quit sc
	Kill ^||OcuTalon.Setting(key)
	Quit ..Upsert(key, value)
}

/// The error status that refuses an empty key or a public key, and OK for any other key; verb ("seeded" or "written") ends the
/// public key's refusal.
ClassMethod Refusal(key As %String, verb As %String) As %Status [ Private ]
{
	If key = "" Quit $SYSTEM.Status.Error(5001, "A setting key must not be empty")
	If ..IsPublic(key) Quit $SYSTEM.Status.Error(5001, "Setting '"_key_"' is a public setting and is not "_verb_" here")
	Quit $SYSTEM.Status.OK()
}

/// Saves the row of the key with the value and the time now, creating the row when it is absent.
ClassMethod Upsert(key As %String, value As %String) As %Status [ Private ]
{
	Set row = ..KeyIndexOpen(key)
	If '$IsObject(row) {
		Set row = ..%New()
		Set row.Key = key
	}
	Set row.Value = value
	Set row.UpdatedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Quit row.%Save()
}

/// 1 when key is one of the public settings' fixed keys or its readiness key.
ClassMethod IsPublic(key As %String) As %Boolean [ Private ]
{
	Quit (key = ##class(OcuTalon.Data.Public.Settings).#READY) || ''$ListFind($ListFromString(##class(OcuTalon.Data.Public.Settings).#KEYS), key)
}

Storage Default
{
<Data name="SettingDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Key</Value>
</Value>
<Value name="3">
<Value>Value</Value>
</Value>
<Value name="4">
<Value>UpdatedAt</Value>
</Value>
</Data>
<DataLocation>^OcuTalonP.SettingD</DataLocation>
<DefaultData>SettingDefaultData</DefaultData>
<IdLocation>^OcuTalonP.SettingD</IdLocation>
<IndexLocation>^OcuTalonP.SettingI</IndexLocation>
<StreamLocation>^OcuTalonP.SettingS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
