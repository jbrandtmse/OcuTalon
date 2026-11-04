/// Reads each kind of settings change back from the IRIS audit log (Story 33.2; AD-17, AD-19). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): it writes real Settings entries, so instance-wide auditing and OcuTalon's events must be on, as a clean install leaves them. A
/// shadow instance of OcuTalon.Test.Core.SettingsOpsProbe carries the commands out with the real Bridge.Audit.Record behind its audit seam, with the
/// Demo step and the two Bridge.Settings calls stood in for. An entry is found by the fresh session Ref of its command, and each is polled for with
/// Test.Bridge.AuditLog.Wait and a limit of 180 seconds, because IRIS can show an entry late.
///   - TestThresholdAudited: a threshold save writes one Settings entry for the changed value, with the six members of the shape;
///   - TestDigestKeyAudited: a digest key save writes its entry;
///   - TestBridgeValueAudited: a bridge value (through the double) writes its entry, with the value that Set replaced;
///   - TestDemoModeAudited: a SetDemoMode from web_admin writes its entry, with the channel web;
///   - TestUnchangedWritesNoEntry: a save that changes nothing writes no entry, after a later entry has shown that the log is read.
/// The Setting rows of the keys, the demo.mode row and the probe's globals are put back after the tests.
Class OcuTalon.Test.Core.SettingsAudit Extends %UnitTest.TestCase
{

/// The probe that carries the commands out.
Parameter PROBE = "OcuTalon.Test.Core.SettingsOpsProbe";

/// How long to wait for an entry, in seconds.
Parameter SECONDS = 180;

/// The keys that the tests write.
Parameter KEYS = "digest.time,digest.channels,checks.thresholds.diskFreePercent,checks.thresholds.journalFreePercent,checks.thresholds.licenseUsePercent,checks.thresholds.queueMessages,checks.thresholds.queueWaitMinutes";

/// 1 when the demo.mode row existed before the tests.
Property Found As %Boolean;

Property SavedValue As %String(MAXLEN = 1000);

Property SavedUpdatedAt As %String(MAXLEN = 20);

Method OnBeforeAllTests() As %Status
{
	Kill ^OcuTalonTest("SettingsAudit")
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set ..Found = found, ..SavedValue = value, ..SavedUpdatedAt = updatedAt
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Set ^OcuTalonTest("SettingsAudit", "saved", key) = $ListBuild(row.Value, row.UpdatedAt)
	}
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "record"
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..Found, ..SavedValue, ..SavedUpdatedAt)
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(key)
		If $Data(^OcuTalonTest("SettingsAudit", "saved", key), saved) {
			Set row = ##class(OcuTalon.Data.Setting).%New()
			Set row.Key = key, row.Value = $List(saved, 1), row.UpdatedAt = $List(saved, 2)
			Do row.%Save()
		}
	}
	Kill ^OcuTalonTest("SettingsAudit")
	Quit $$$OK
}

/// A threshold save: one Settings entry for the one value that changed.
Method TestThresholdAudited()
{
	Do ..Clear()
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set since = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set result = ..Save("check-thresholds", {"diskFreePercent": 12, "journalFreePercent": 10, "licenseUsePercent": 90, "queueMessages": 100, "queueWaitMinutes": 10}, ref)
	Do $$$AssertEquals(result.Outcome, "done", "the save is done")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(since, "OcuTalon", "Settings", "", ref, "", 1, ..#SECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one Settings entry is in the audit log")
	If entries.%Size() < 1 Quit
	Set data = entries.%Get(0).data
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "checks.thresholds.diskFreePercent|10|12", "it has the key, the old value and the new one")
	Do $$$AssertEquals(data.irisUser_"|"_data.sessionRef_"|"_data.channel, "zzadmin|"_ref_"|web", "the user, the session and the channel web")
	Do $$$AssertEquals(entries.%Get(0).description, "Setting checks.thresholds.diskFreePercent changed", "and the description")
}

/// A digest key save: its entry, with the key and both values.
Method TestDigestKeyAudited()
{
	Do ..Clear()
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set since = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set result = ..Save("daily-digest", {"time": "07:30", "channels": "web,phone,telegram"}, ref)
	Do $$$AssertEquals(result.Outcome, "done", "the save is done")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(since, "OcuTalon", "Settings", "", ref, "", 1, ..#SECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one entry, for the time (the channels did not change)")
	If entries.%Size() < 1 Quit
	Set data = entries.%Get(0).data
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to_"|"_data.channel, "digest.time|08:00|07:30|web", "digest.time, from its default to 07:30, channel web")
}

/// A bridge value through the double: its entry has the value that Set replaced.
Method TestBridgeValueAudited()
{
	Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "DailyCostCapUSD") = "3"
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set since = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set result = ..Save("budgets", {"DecisionTokenBudget": "9000", "DailyCostCapUSD": "4"}, ref)
	Do $$$AssertEquals(result.Outcome, "done", "the save is done")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(since, "OcuTalon", "Settings", "", ref, "", 2, ..#SECONDS)
	Do $$$AssertEquals(entries.%Size(), 2, "two entries, one for each bridge value")
	If entries.%Size() < 2 Quit
	Set first = entries.%Get(0).data
	Set second = entries.%Get(1).data
	Do $$$AssertEquals(first.setting_"|"_first.from_"|"_first.to, "DecisionTokenBudget||9000", "the first value")
	Do $$$AssertEquals(second.setting_"|"_second.from_"|"_second.to, "DailyCostCapUSD|3|4", "the second value, with the one that Set replaced")
}

/// A SetDemoMode from web_admin: the entry has the channel web, and the step stand-in ran after the write.
Method TestDemoModeAudited()
{
	Do ##class(OcuTalon.Test.Demo.Step).Put("0", "2000-01-01T00:00:00Z")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set since = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set command = ##class(OcuTalon.Msg.Command.SetDemoMode).%New()
	Set command.DemoMode = 1
	Set command.Origin = "web_admin"
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = ref
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Do $$$AssertStatusOK(probe.OnMessage(command, .result), "the status is OK")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|on", "demo mode is on")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(since, "OcuTalon", "Settings", "", ref, "", 1, ..#SECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one entry is in the audit log")
	If entries.%Size() < 1 Quit
	Set data = entries.%Get(0).data
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to_"|"_data.channel_"|"_data.irisUser, "demo.mode|0|1|web|zzadmin", "demo.mode, 0 to 1, the channel web, the acting user")
}

/// A save that changes nothing writes no entry: after it, a save that does change a value shows its one entry, and the earlier session has none.
Method TestUnchangedWritesNoEntry()
{
	Do ..Clear()
	Set quiet = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set loud = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set since = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do $$$AssertEquals(..Save("check-thresholds", {"diskFreePercent": 10, "journalFreePercent": 10, "licenseUsePercent": 90, "queueMessages": 100, "queueWaitMinutes": 10}, quiet).Outcome, "done", "the unchanged save is done")
	Do $$$AssertEquals(..Save("check-thresholds", {"diskFreePercent": 10, "journalFreePercent": 10, "licenseUsePercent": 90, "queueMessages": 100, "queueWaitMinutes": 11}, loud).Outcome, "done", "the changed save is done")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(since, "OcuTalon", "Settings", "", loud, "", 1, ..#SECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "the changed save has its entry")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(since, "OcuTalon", "Settings", "", quiet)
	Do $$$AssertEquals(entries.%Size(), 0, "and the unchanged one has none")
}

/// --- helpers ---
/// Deletes the rows of the keys.
Method Clear() [ Private ]
{
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(key)
	}
}

/// A SaveSettings of the section from web_admin for zzadmin and the session Ref, sent to the probe.
Method Save(slug As %String, changes As %DynamicObject, ref As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = slug
	Set command.Changes = changes.%ToJSON()
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = ref
	Set command.Origin = "web_admin"
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

}
