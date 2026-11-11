/// Tests of the SaveSettings command in OcuTalon.Core.SettingsOps (Story 33.2; AD-1, AD-17, AD-19). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI
/// ONLY (Rule 21): it writes and removes Setting rows of the check thresholds and the digest. The tests drive a shadow instance of
/// OcuTalon.Test.Core.SettingsOpsProbe, whose audit write is a recording seam (nothing reaches the IRIS audit log; Test.Core.SettingsAudit reads
/// that back), and whose BridgeCurrent, BridgeCheck and BridgeSet stand in for Bridge.Settings. Every text and every list is written out here, never read from
/// SettingsOps.
///   - TestThresholdsSaved: two changed values of five are written and audited with the acting user, the session and the channel web;
///     the other three rows are not written;
///   - TestNothingChanged: the values the section already has write nothing and audit nothing, and the answer is done;
///   - TestOnlyChangedValuesAreAudited: a second save that changes one value of five audits that one;
///   - TestRefusedValues: a non-number, a value out of its range, a decimal, a boolean, null, an array and a value that holds "@{" refuse the
///     save and name the field; nothing is written and nothing is audited;
///   - TestRefusedFieldsAreAllNamed: every refused field of a save is named;
///   - TestUnknownAndMissingFields: a body that lacks a field or adds one, a body that is not an object, an unknown section and the demo mode
///     section are refused with nothing written;
///   - TestDigestSection: the digest time and channels are validated, and channels are stored in their fixed order;
///   - TestAllOrNothingAudit and TestAllOrNothingApply: a failed audit write or a failed row write at each of the five positions rolls every
///     value back and writes no row, and answers not_audited or failed;
///   - TestBridgeSaved: the bridge double sees every Check before the first Set, and each Set has its audit entry with the replaced value;
///   - TestBridgeRefused, TestBridgeStub: a Check that refuses a value refuses the section and sets nothing; a Check that answers "not
///     implemented" gives not_built and sets and audits nothing on the double; on the real instance (U-177 exception, Contest Planner, 2026-11-05) the built bridge
///     settings save and apply an accepted value, refuse a value off the allow-list with nothing changed, and every value is put back;
///   - TestBridgeSetFails, TestBridgeSetThrows, TestBridgeAuditFails: a failure, or a Set that throws, puts the earlier values back and audits that;
///   - TestBridgeUnchangedValueIsSkipped: a value equal to the bridge's current one is not checked, set or audited;
///   - TestAllowList: every key of every section is on the allow-list;
///   - TestValues: the page's body has the three section rows, the bridge values, the providers, the zone and the prices (Story 18.3: the four prices of each
///     model of a supported provider that has a Price row, read from the row), no key material, and reads the rows and not the per-process cache.
/// The Setting rows of the seven keys are saved before the tests and put back after them, and so is the probe's global.
Class OcuTalon.Test.Core.SettingsSave Extends %UnitTest.TestCase
{

/// The probe under test.
Parameter PROBE = "OcuTalon.Test.Core.SettingsOpsProbe";

/// A 22-character Ref for the command's SessionRef.
Parameter REF = "zzsession0123456789abc";

/// The five threshold keys with their defaults, as "name|key|default".
Parameter THRESHOLDS = "diskFreePercent|checks.thresholds.diskFreePercent|10,journalFreePercent|checks.thresholds.journalFreePercent|10,licenseUsePercent|checks.thresholds.licenseUsePercent|90,queueMessages|checks.thresholds.queueMessages|100,queueWaitMinutes|checks.thresholds.queueWaitMinutes|10";

/// The keys that the tests write.
Parameter KEYS = "digest.time,digest.channels,checks.thresholds.diskFreePercent,checks.thresholds.journalFreePercent,checks.thresholds.licenseUsePercent,checks.thresholds.queueMessages,checks.thresholds.queueWaitMinutes";

Method OnBeforeAllTests() As %Status
{
	Kill ^OcuTalonTest("SettingsSave")
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Set ^OcuTalonTest("SettingsSave", "saved", key) = $ListBuild(row.Value, row.UpdatedAt)
	}
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Do ..Clear()
	Do ..Reset()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clear()
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		If $Data(^OcuTalonTest("SettingsSave", "saved", key), saved) {
			Set row = ##class(OcuTalon.Data.Setting).%New()
			Set row.Key = key, row.Value = $List(saved, 1), row.UpdatedAt = $List(saved, 2)
			Do row.%Save()
		}
	}
	Kill ^OcuTalonTest("SettingsSave")
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Quit $$$OK
}

/// Two of the five values change: two rows are written (the other three still hold their defaults and have no row), each with its own audit
/// entry that has the six members of the Settings shape, as JSON strings, with the stored value before the change, and the answer is done.
Method TestThresholdsSaved()
{
	Do ..Reset()
	Set result = ..Save("check-thresholds", {"diskFreePercent": 15, "journalFreePercent": "10", "licenseUsePercent": 90, "queueMessages": 250, "queueWaitMinutes": 10})
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the save is carried out")
	Do $$$AssertEquals(..Row("checks.thresholds.diskFreePercent"), "15", "the first changed value is written")
	Do $$$AssertEquals(..Row("checks.thresholds.queueMessages"), "250", "the second changed value is written")
	Do $$$AssertEquals(..Row("checks.thresholds.journalFreePercent")_"|"_..Row("checks.thresholds.licenseUsePercent")_"|"_..Row("checks.thresholds.queueWaitMinutes"), "||", "the three unchanged values have no row")
	Do $$$AssertEquals(..Audits(), 2, "two audit entries are written, one for each changed value")
	Set first = ..AuditData(1)
	Do $$$AssertEquals(first.setting_"|"_first.from_"|"_first.to, "checks.thresholds.diskFreePercent|10|15", "the first entry has the key, the default it replaced and the new value")
	Set second = ..AuditData(2)
	Do $$$AssertEquals(second.setting_"|"_second.from_"|"_second.to, "checks.thresholds.queueMessages|100|250", "the second entry has its own")
	Do $$$AssertEquals(first.irisUser_"|"_first.sessionRef_"|"_first.channel, "zzadmin|"_..#REF_"|web", "the entry names the acting user, the session and the channel web")
	Do $$$AssertEquals(first.%Size(), 6, "and has exactly the six members")
	Set types = ""
	For name = "setting", "from", "to", "irisUser", "sessionRef", "channel" Set types = types_$Select(types = "": "", 1: ",")_first.%GetTypeOf(name)
	Do $$$AssertEquals(types, "string,string,string,string,string,string", "every member is a JSON string")
	Set body = ##class(OcuTalon.Core.SettingsOps).Values()
	Do $$$AssertEquals(body.sections.%Get("check-thresholds").diskFreePercent_"|"_body.sections.%Get("check-thresholds").queueMessages, "15|250", "the page's values show the saved ones at once")
}

/// The values that the section already has: no row, no audit entry, and the answer is done. A second save of the same values changes nothing either.
Method TestNothingChanged()
{
	Do ..Reset()
	Set same = {"diskFreePercent": 10, "journalFreePercent": 10, "licenseUsePercent": 90, "queueMessages": 100, "queueWaitMinutes": 10}
	Set result = ..Save("check-thresholds", same)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the defaults are done")
	Do $$$AssertEquals(..Rows(), 0, "no row is written")
	Do $$$AssertEquals(..Audits(), 0, "and no audit entry")
	Do ..Reset()
	Do $$$AssertEquals(..Save("check-thresholds", {"diskFreePercent": 11, "journalFreePercent": 10, "licenseUsePercent": 90, "queueMessages": 100, "queueWaitMinutes": 10}).Outcome, "done", "one change is saved")
	Do ..Reset()
	Set result = ..Save("check-thresholds", {"diskFreePercent": 11, "journalFreePercent": 10, "licenseUsePercent": 90, "queueMessages": 100, "queueWaitMinutes": 10})
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the same values again are done")
	Do $$$AssertEquals(..Audits(), 0, "and write no audit entry")
	Do $$$AssertEquals(..Row("checks.thresholds.diskFreePercent"), "11", "the stored value stays")
}

/// A second save changes one value of five: one entry, whose from is the value stored by the first save.
Method TestOnlyChangedValuesAreAudited()
{
	Do ..Reset()
	Do ..Save("check-thresholds", {"diskFreePercent": 15, "journalFreePercent": 20, "licenseUsePercent": 95, "queueMessages": 250, "queueWaitMinutes": 30})
	Do $$$AssertEquals(..Audits(), 5, "five changes, five entries")
	Do ..Reset()
	Set result = ..Save("check-thresholds", {"diskFreePercent": 15, "journalFreePercent": 20, "licenseUsePercent": 96, "queueMessages": 250, "queueWaitMinutes": 30})
	Do $$$AssertEquals(result.Outcome, "done", "the second save is done")
	Do $$$AssertEquals(..Audits(), 1, "one entry")
	Set data = ..AuditData(1)
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "checks.thresholds.licenseUsePercent|95|96", "for the one that changed, with the stored value as from")
}

/// Each refused kind of value is refused with the field named, nothing is written and nothing is audited.
Method TestRefusedValues()
{
	Set cases = $ListBuild("""abc""", "0", "101", "-5", "5.5", """5.5""", """1e2""", """ 7""", "true", "null", "[1]", "{""a"": 1}", """@{env:KEY}""", """12@{""", "1000000000000", """""")
	Set position = 0
	While $ListNext(cases, position, json) {
		Do ..Reset()
		Do ..Clear()
		Set result = ..SaveText("check-thresholds", "{""diskFreePercent"": "_json_", ""journalFreePercent"": 10, ""licenseUsePercent"": 90, ""queueMessages"": 250, ""queueWaitMinutes"": 10}")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", json_" is refused")
		Do $$$AssertEquals(result.Data, "{""fields"":[""diskFreePercent""]}", json_": the field is named")
		Do $$$AssertEquals(..Rows(), 0, json_": nothing is written, though queueMessages was fine")
		Do $$$AssertEquals(..Audits(), 0, json_": nothing is audited")
	}
	Do ..Reset()
	Set changes = {"diskFreePercent": 15, "journalFreePercent": 10, "licenseUsePercent": 90, "queueMessages": 100, "queueWaitMinutes": 10}
	Set changes.queueMessages = 1000001
	Do $$$AssertEquals(..Save("check-thresholds", changes).Outcome, "refused", "queueMessages over 1000000 is refused")
	Set changes.queueMessages = 1000000
	Do $$$AssertEquals(..Save("check-thresholds", changes).Outcome, "done", "1000000 is the largest queue backlog")
	Set changes.licenseUsePercent = 100
	Set changes.diskFreePercent = 1
	Do $$$AssertEquals(..Save("check-thresholds", changes).Outcome, "done", "1 and 100 are the ends of a percent")
}

/// Every refused field is named, in the section's order.
Method TestRefusedFieldsAreAllNamed()
{
	Do ..Reset()
	Do ..Clear()
	Set result = ..Save("check-thresholds", {"diskFreePercent": 0, "journalFreePercent": 10, "licenseUsePercent": "x", "queueMessages": 100, "queueWaitMinutes": "@{a}"})
	Do $$$AssertEquals(result.Data, "{""fields"":[""diskFreePercent"",""licenseUsePercent"",""queueWaitMinutes""]}", "the three refused fields are named")
	Do $$$AssertEquals(..Rows()_"|"_..Audits(), "0|0", "nothing is written or audited")
}

/// A missing field is named; an extra field, a body that is not an object, an unknown section and the demo mode section (which SetDemoMode
/// switches) are refused with no field named; nothing is written.
Method TestUnknownAndMissingFields()
{
	Do ..Reset()
	Do ..Clear()
	Set result = ..Save("check-thresholds", {"diskFreePercent": 15, "journalFreePercent": 10, "licenseUsePercent": 90, "queueMessages": 250})
	Do $$$AssertEquals(result.Outcome_"|"_result.Data, "refused|{""fields"":[""queueWaitMinutes""]}", "a missing field is refused and named")
	Set result = ..Save("check-thresholds", {"diskFreePercent": 15, "journalFreePercent": 10, "licenseUsePercent": 90, "queueMessages": 250, "queueWaitMinutes": 10, "zzExtra": 1})
	Do $$$AssertEquals(result.Outcome_"|"_result.Data, "refused|{""fields"":[]}", "an extra field is refused and not echoed")
	Set result = ..SaveText("check-thresholds", "[1, 2]")
	Do $$$AssertEquals(result.Outcome_"|"_result.Data, "refused|{""fields"":[]}", "an array is refused")
	Set result = ..SaveText("check-thresholds", "not json")
	Do $$$AssertEquals(result.Outcome, "refused", "text that is not JSON is refused")
	Set result = ..SaveText("check-thresholds", "")
	Do $$$AssertEquals(result.Outcome, "refused", "an empty body is refused")
	Set result = ..Save("zz-section", {"a": 1})
	Do $$$AssertEquals(result.Outcome, "refused", "an unknown section is refused")
	Set result = ..Save("models", {})
	Do $$$AssertEquals(result.Outcome, "refused", "a section that has no fields yet is refused")
	Set result = ..Save("demo-mode", {"demoMode": true})
	Do $$$AssertEquals(result.Outcome, "refused", "demo mode is not saved by SaveSettings")
	Do $$$AssertEquals(..Rows()_"|"_..Audits()_"|"_$Get(^OcuTalonTest("SettingsOpsProbe", "calls")), "0|0|", "nothing was written, audited or run")
}

/// The digest's time is HH:MM, its channels a non-empty list of web, phone and telegram with no repeat, stored in the fixed order.
Method TestDigestSection()
{
	Do ..Reset()
	Do ..Clear()
	For time = "24:00", "8:00", "08:60", "0800", "", "ab:cd" {
		Set result = ..Save("daily-digest", {"time": (time), "channels": "web,phone,telegram"})
		Do $$$AssertEquals(result.Outcome_"|"_result.Data, "refused|{""fields"":[""time""]}", "the time '"_time_"' is refused")
	}
	For channels = "", "web,web", "email", "web,", ",web", "web;phone", "WEB", "web,phone,telegram,phone" {
		Set result = ..Save("daily-digest", {"time": "08:00", "channels": (channels)})
		Do $$$AssertEquals(result.Outcome_"|"_result.Data, "refused|{""fields"":[""channels""]}", "the channels '"_channels_"' are refused")
	}
	Do $$$AssertEquals(..Rows()_"|"_..Audits(), "0|0", "nothing was written")
	Set result = ..Save("daily-digest", {"time": "23:59", "channels": "telegram,web"})
	Do $$$AssertEquals(result.Outcome, "done", "a valid save is done")
	Do $$$AssertEquals(..Row("digest.time")_"|"_..Row("digest.channels"), "23:59|web,telegram", "the time is stored and the channels in their fixed order")
	Do $$$AssertEquals(..Audits(), 2, "two entries")
	Set data = ..AuditData(2)
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "digest.channels|web,phone,telegram|web,telegram", "from is the default of an absent row")
	Do ..Reset()
	Set result = ..Save("daily-digest", {"time": "23:59", "channels": "web,telegram"})
	Do $$$AssertEquals(..Audits(), 0, "the same values again audit nothing")
}

/// A failed audit write at each of the five positions: not_audited, no row is left, and the audit was asked for up to that position only.
Method TestAllOrNothingAudit()
{
	For at = 1:1:5 {
		Do ..Reset()
		Do ..Clear()
		Set ^OcuTalonTest("SettingsOpsProbe", "answer", "auditAt") = at
		Set result = ..Save("check-thresholds", {"diskFreePercent": 11, "journalFreePercent": 11, "licenseUsePercent": 91, "queueMessages": 101, "queueWaitMinutes": 11})
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "the audit at "_at_" fails: not_audited")
		Do $$$AssertEquals(..Rows(), 0, "audit failed at "_at_": every value is rolled back")
		Do $$$AssertEquals(..Audits(), at, "audit failed at "_at_": the entries stop there")
		Do $$$AssertEquals($TLEVEL, 0, "no transaction is left open")
	}
}

/// A failed row write at each of the five positions: failed, no row is left, and no later value was tried.
Method TestAllOrNothingApply()
{
	For at = 1:1:5 {
		Do ..Reset()
		Do ..Clear()
		Set ^OcuTalonTest("SettingsOpsProbe", "answer", "applyAt") = at
		Set result = ..Save("check-thresholds", {"diskFreePercent": 11, "journalFreePercent": 11, "licenseUsePercent": 91, "queueMessages": 101, "queueWaitMinutes": 11})
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "the write at "_at_" fails: failed")
		Do $$$AssertEquals(..Rows(), 0, "write failed at "_at_": every value is rolled back")
		Do $$$AssertEquals($Get(^||OcuTalonSettingsOpsProbe("n", "apply")), at, "write failed at "_at_": no later value was tried")
		Do $$$AssertEquals($TLEVEL, 0, "no transaction is left open")
	}
	Do ..Reset()
	Do ..Clear()
	Do ..Save("check-thresholds", {"diskFreePercent": 12, "journalFreePercent": 10, "licenseUsePercent": 90, "queueMessages": 100, "queueWaitMinutes": 10})
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "applyAt") = 2
	Set result = ..Save("check-thresholds", {"diskFreePercent": 13, "journalFreePercent": 13, "licenseUsePercent": 90, "queueMessages": 100, "queueWaitMinutes": 10})
	Do $$$AssertEquals(result.Outcome, "failed", "a failure on a save over a stored value fails")
	Do $$$AssertEquals(..Row("checks.thresholds.diskFreePercent"), "12", "the earlier value of the row is back, not the first write")
}

/// A bridge section with the double: every Check comes before the first Set; each Set has its audit entry, whose from is what the double replaced.
Method TestBridgeSaved()
{
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "DecisionTokenBudget") = "4000"
	Set result = ..Save("budgets", {"DecisionTokenBudget": 5000, "DailyCostCapUSD": "7.50"})
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the budgets are saved")
	Set order = ""
	For i = 1:1:$Get(^OcuTalonTest("SettingsOpsProbe", "bridge")) Set order = order_$Select(order = "": "", 1: ",")_^OcuTalonTest("SettingsOpsProbe", "bridge", i)
	Do $$$AssertEquals(order, "check,check,set,set", "both Checks come before the first Set")
	Do $$$AssertEquals(^OcuTalonTest("SettingsOpsProbe", "bridge", 1, "what")_"|"_^OcuTalonTest("SettingsOpsProbe", "bridge", 3, "what")_"|"_^OcuTalonTest("SettingsOpsProbe", "bridge", 4, "what"), "DecisionTokenBudget=5000|DecisionTokenBudget=5000|DailyCostCapUSD=7.50", "with the names and values")
	Do $$$AssertEquals(..Audits(), 2, "two entries")
	Set first = ..AuditData(1)
	Do $$$AssertEquals(first.setting_"|"_first.from_"|"_first.to_"|"_first.channel, "DecisionTokenBudget|4000|5000|web", "the first entry has the value that Set replaced")
	Set second = ..AuditData(2)
	Do $$$AssertEquals(second.setting_"|"_second.from_"|"_second.to, "DailyCostCapUSD||7.50", "and the second has an empty from")
	Do $$$AssertEquals(..Rows(), 0, "no Setting row is written by a bridge section")
	Do ..Reset()
	Set result = ..Save("time-zone", {"InstanceZone": "Europe/Paris"})
	Do $$$AssertEquals(result.Outcome, "done", "the zone is saved")
	Do $$$AssertEquals(^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "InstanceZone"), "Europe/Paris", "through Set")
}

/// A Check that refuses one value refuses the section with that field named: no Set, no entry.
Method TestBridgeRefused()
{
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "check") = "error:DailyCostCapUSD"
	Set result = ..Save("budgets", {"DecisionTokenBudget": 5000, "DailyCostCapUSD": "abc"})
	Do $$$AssertEquals(result.Outcome_"|"_result.Data, "refused|{""fields"":[""DailyCostCapUSD""]}", "the refused value is named")
	Do $$$AssertEquals($Get(^||OcuTalonSettingsOpsProbe("n", "set")), "", "no Set was called")
	Do $$$AssertEquals(..Audits(), 0, "and no entry was written")
	Do ..Reset()
	Set result = ..Save("budgets", {"DecisionTokenBudget": "@{env:X}", "DailyCostCapUSD": "1"})
	Do $$$AssertEquals(result.Outcome_"|"_result.Data, "refused|{""fields"":[""DecisionTokenBudget""]}", "a value with @{ is refused before Check")
	Do $$$AssertEquals($Get(^OcuTalonTest("SettingsOpsProbe", "bridge")), "", "and Check is not asked")
}

/// U-177 one-time exception (Contest Planner ruling of 2026-11-05, Story 17.4, IG-2's conditions): with the double's stub answer (code 5003) the save is not_built and
/// nothing is set or audited. On the bare instance of the real operation the built bridge settings now answer: an accepted value is saved and applied (done), and a value that
/// is off the allow-list is refused with the field named and nothing changed. The test puts back every value that it wrote, and a check at its end re-reads the token
/// budget, the daily cap and the zone and finds the originals.
Method TestBridgeStub()
{
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "check") = "stub"
	Set result = ..Save("budgets", {"DecisionTokenBudget": 5000, "DailyCostCapUSD": "7.50"})
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_built", "a Check that is not implemented gives not_built")
	Do $$$AssertEquals($Get(^||OcuTalonSettingsOpsProbe("n", "set"))_"|"_..Audits(), "|0", "nothing is set or audited")
	Set bridge = "OcuTalon.Bridge.Settings"
	Set values = $ClassMethod(bridge, "Values")
	Set originals = values.%Get("DecisionTokenBudget")_"|"_values.%Get("DailyCostCapUSD")_"|"_##class(OcuTalon.Bridge.Time).Zone()
	Set bare = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Core.SettingsOps", .sc)
	Do $$$AssertStatusOK(sc, "the real operation is made")
	Try {
		Set cases = $ListBuild(
			$ListBuild("budgets", {"DecisionTokenBudget": 5000, "DailyCostCapUSD": "7.50"}.%ToJSON(), "1|done", "5000|7.5|"_$Piece(originals, "|", 3)),
			$ListBuild("time-zone", {"InstanceZone": "Europe/Paris"}.%ToJSON(), "1|done", "5000|7.5|Europe/Paris"),
			$ListBuild("budgets", {"DecisionTokenBudget": 100001, "DailyCostCapUSD": "7.50"}.%ToJSON(), "0|refused", "5000|7.5|Europe/Paris"),
			$ListBuild("time-zone", {"InstanceZone": "Mars/Olympus"}.%ToJSON(), "0|refused", "5000|7.5|Europe/Paris"))
		Set position = 0
		While $ListNext(cases, position, case) {
			Set slug = $List(case, 1)
			Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
			Set command.Slug = slug, command.ActingUser = "zzadmin", command.SessionRef = ..#REF, command.Origin = "web_admin"
			Set command.Changes = $List(case, 2)
			Set sc = bare.OnMessage(command, .result)
			Do $$$AssertStatusOK(sc, slug_": the status is OK")
			Do $$$AssertEquals(result.Ok_"|"_result.Outcome, $List(case, 3), slug_": "_$List(case, 3))
			Set now = $ClassMethod(bridge, "Values")
			Do $$$AssertEquals(now.%Get("DecisionTokenBudget")_"|"_now.%Get("DailyCostCapUSD")_"|"_##class(OcuTalon.Bridge.Time).Zone(), $List(case, 4), slug_": the bridge holds "_$List(case, 4))
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do $ClassMethod(bridge, "Set", "DecisionTokenBudget", $Piece(originals, "|", 1))
	Do $ClassMethod(bridge, "Set", "DailyCostCapUSD", $Piece(originals, "|", 2))
	Do $ClassMethod(bridge, "Set", "InstanceZone", $Piece(originals, "|", 3))
	Do ##class(OcuTalon.Bridge.Time).Apply()
	Set values = $ClassMethod(bridge, "Values")
	Do $$$AssertEquals(values.%Get("DecisionTokenBudget")_"|"_values.%Get("DailyCostCapUSD")_"|"_##class(OcuTalon.Bridge.Time).Zone(), originals, "the token budget, the daily cap and the zone are the originals again")
}

/// A Set that fails on the second value: the first is Set back, and both the first value and its put-back have an entry.
Method TestBridgeSetFails()
{
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "DecisionTokenBudget") = "4000"
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "setAt") = 2
	Set result = ..Save("budgets", {"DecisionTokenBudget": 5000, "DailyCostCapUSD": "7.50"})
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "the failed Set is failed")
	Do $$$AssertEquals(^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "DecisionTokenBudget"), "4000", "the first value is back")
	Do $$$AssertEquals(..Audits(), 2, "the first change and its put-back have an entry each")
	Set back = ..AuditData(2)
	Do $$$AssertEquals(back.setting_"|"_back.from_"|"_back.to, "DecisionTokenBudget|5000|4000", "the put-back goes from the new value to the old one")
}

/// A Set that throws on the second value: the first is Set back with an entry for the put-back, and the answer is failed.
Method TestBridgeSetThrows()
{
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "DecisionTokenBudget") = "4000"
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "throwAt") = 2
	Set result = ..Save("budgets", {"DecisionTokenBudget": 5000, "DailyCostCapUSD": "7.50"})
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "the Set that threw is failed")
	Do $$$AssertEquals(^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "DecisionTokenBudget"), "4000", "the first value is back")
	Do $$$AssertEquals(..Audits(), 2, "the first change and its put-back have an entry each")
}

/// A value that equals the bridge's current one is no change: it is not checked, set or audited.
Method TestBridgeUnchangedValueIsSkipped()
{
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "DecisionTokenBudget") = "5000"
	Set result = ..Save("budgets", {"DecisionTokenBudget": 5000, "DailyCostCapUSD": "7.50"})
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the budgets are saved")
	Do $$$AssertEquals(..Audits(), 1, "one entry, for the value that changed")
	Do $$$AssertEquals(^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "DailyCostCapUSD"), "7.50", "which is the one that was set")
	Do $$$AssertEquals($Get(^||OcuTalonSettingsOpsProbe("n", "set")), 1, "and the only Set")
}

/// An audit write that fails after a Set: that value is Set back and the answer is not_audited.
Method TestBridgeAuditFails()
{
	Do ..Reset()
	Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "DecisionTokenBudget") = "4000"
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "auditAt") = 1
	Set result = ..Save("budgets", {"DecisionTokenBudget": 5000, "DailyCostCapUSD": "7.50"})
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "the failed audit is not_audited")
	Do $$$AssertEquals(^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "DecisionTokenBudget"), "4000", "the value is back")
	Do $$$AssertEquals($Get(^||OcuTalonSettingsOpsProbe("n", "set")), 2, "the second value was never set (one Set and one put-back)")
}

/// Every key that a section writes is on the allow-list, and every key on it but demo.mode is in a section (the email section writes email.address and email.owner).
Method TestAllowList()
{
	Set allowed = $ListFromString($Parameter(..#PROBE, "ALLOWLIST"))
	Set found = ""
	Set iterator = ##class(OcuTalon.Core.SettingsOps).Sections().%GetIterator()
	While iterator.%GetNext(, .section) {
		If section.kind = "email" Set found = found_$ListBuild("email.address", "email.owner")
		Set fields = section.fields.%GetIterator()
		While fields.%GetNext(, .field) {
			If field.%IsDefined("key") {
				Do $$$AssertTrue($ListFind(allowed, field.key), field.key_" is on the allow-list")
				Set found = found_$ListBuild(field.key)
			}
		}
	}
	Set position = 0
	While $ListNext(allowed, position, key) {
		Do $$$AssertTrue($ListFind(found, key), key_" is in a section")
	}
}

/// The page's body: the three sections with their values, then the bridge values, the providers and the zone; it reads the rows and not the
/// per-process cache, and holds no key material.
Method TestValues()
{
	Do ..Clear()
	Set body = ##class(OcuTalon.Core.SettingsOps).Values()
	Set keys = ""
	Set iterator = body.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(keys, "sections,bridge,providers,instanceZone,prices", "the body's keys")
	Set keys = ""
	Set iterator = body.sections.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Do $$$AssertEquals(keys, "daily-digest,check-thresholds,demo-mode,channels", "the sections that hold values, the channels last (not on the online demo)")
	Set channels = body.sections.channels
	Set shape = ""
	Set iterator = channels.%GetIterator()
	While iterator.%GetNext(.key, , .type) {
		Set shape = shape_$Select(shape = "": "", 1: ",")_key_":"_type
	}
	Do $$$AssertEquals(shape, "address:string,incoming:string,outgoing:string,user:string,passwordSet:boolean", "the channels hold the address, both servers, the user name and whether a password is set")
	Do $$$AssertEquals(body.sections.%Get("check-thresholds").%ToJSON(), "{""diskFreePercent"":10,""journalFreePercent"":10,""licenseUsePercent"":90,""queueMessages"":100,""queueWaitMinutes"":10}", "an absent row reads as the default, as a number")
	Do $$$AssertEquals(body.sections.%Get("daily-digest").%ToJSON(), "{""time"":""08:00"",""channels"":""web,phone,telegram""}", "the digest defaults")
	Do $$$AssertEquals(body.sections.%Get("demo-mode").%GetTypeOf("demoMode"), "boolean", "demoMode is a boolean")
	Do $$$AssertEquals(body.%GetTypeOf("bridge")_"|"_body.%GetTypeOf("providers")_"|"_body.%GetTypeOf("instanceZone")_"|"_body.%GetTypeOf("prices"), "object|array|string|object", "the bridge parts have their types")
	Set listed = 0
	Set iterator = body.prices.%GetIterator()
	While iterator.%GetNext(.model, .one) {
		Set row = ##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen(model)
		Do $$$AssertTrue($IsObject(row), "the price entry of "_model_" has a Price row")
		If '$IsObject(row) Continue
		Set listed = listed + 1
		Set wanted = {"input": (+row.InputPerMTok), "output": (+row.OutputPerMTok), "cacheRead": (+row.CacheReadPerMTok), "cacheWrite": (+row.CacheWritePerMTok)}
		Do $$$AssertEquals(one.%ToJSON(), wanted.%ToJSON(), "the four prices of "_model_" are the row's, as numbers")
	}
	Do $$$AssertTrue(listed > 0, "control: the stack has priced models")
	Do $$$AssertEquals(body.prices.%IsDefined("gpt-5.4-mini")_"|"_body.prices.%IsDefined("gemini-3.1-pro-preview"), "0|0", "the models of providers that are not supported have no entry")
	Do $$$AssertTrue($ZConvert(body.%ToJSON(), "L") '[ "secret", "the body has no secret")
	Do $$$AssertTrue($ZConvert(body.%ToJSON(), "L") '[ "apikey", "and no API key")
	Do ..Save("check-thresholds", {"diskFreePercent": 33, "journalFreePercent": 10, "licenseUsePercent": 90, "queueMessages": 100, "queueWaitMinutes": 10})
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get("checks.thresholds.diskFreePercent"), "33", "the cache of this process now holds 33")
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen("checks.thresholds.diskFreePercent")
	Set row.Value = "44"
	Do row.%Save()
	Do $$$AssertEquals(##class(OcuTalon.Core.SettingsOps).Values().sections.%Get("check-thresholds").diskFreePercent, 44, "the body reads the row, whatever a cache holds")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get("checks.thresholds.diskFreePercent"), "33", "which the cache did not")
	Set row.Value = "zz"
	Do row.%Save()
	Do $$$AssertEquals(##class(OcuTalon.Core.SettingsOps).Values().sections.%Get("check-thresholds").diskFreePercent, 10, "a stored value that is not a whole number reads as the default")
}

/// --- helpers ---
/// Clears the probe's globals.
Method Reset() [ Private ]
{
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe
}

/// Deletes the rows of the seven keys.
Method Clear() [ Private ]
{
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		Do ##class(OcuTalon.Data.Setting).KeyIndexDelete(key)
	}
}

/// The stored value of the key, "" when there is no row.
Method Row(key As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	Quit $Select($IsObject(row): row.Value, 1: "")
}

/// The number of rows of the seven keys.
Method Rows() As %Integer [ Private ]
{
	Set count = 0
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		If ##class(OcuTalon.Data.Setting).KeyIndexExists(key) Set count = count + 1
	}
	Quit count
}

/// The number of audit writes that the probe saw, counted outside the transactions that roll the probe's own record back.
Method Audits() As %Integer [ Private ]
{
	Quit +$Get(^||OcuTalonSettingsOpsProbe("n", "audit"))
}

/// The data of the nth audit write that the probe saw.
Method AuditData(nth As %Integer) As %DynamicObject [ Private ]
{
	Set count = 0
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("SettingsOpsProbe", "calls", n))
		Quit:n=""
		If ^OcuTalonTest("SettingsOpsProbe", "calls", n) = "audit" {
			Set count = count + 1
			If count = nth Quit
		}
	}
	Quit {}.%FromJSON($Get(^OcuTalonTest("SettingsOpsProbe", "calls", n, "data"), "{}"))
}

/// A SaveSettings of the section with the changes (a dynamic object), from web_admin for zzadmin, sent to the probe.
Method Save(slug As %String, changes As %DynamicObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	Quit ..SaveText(slug, changes.%ToJSON())
}

/// A SaveSettings of the section with the text as its changes.
Method SaveText(slug As %String, text As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = slug
	Set command.Changes = text
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = ..#REF
	Set command.Origin = "web_admin"
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

}
