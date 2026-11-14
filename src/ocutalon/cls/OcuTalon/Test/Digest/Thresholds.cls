/// Tests of the check thresholds and of the Digest installer step (Stories 17.5 and 17.6; AD-19, AD-24): the five checks.thresholds.* settings are seeded with the
/// defaults of Checks.Coverage and agree with the section of Core.SettingsOps, an upgrade keeps a value an admin changed, Build uses an admin value once
/// the 60-second cache has expired, and the step declares no grant. The settings are written the way Lane B writes them: Data.Setting Set is what
/// SettingsOps calls; every value is put back.
///   - TestDigestSeeds (Story 17.6): the step also seeds digest.time ("08:00"), the six seeds with the thresholds, and a value an admin changed is kept; the
///     seed agrees with the default of Core.SettingsOps. It seeds no digest.channels row: the default lives in Core.SettingsOps, and the digest reads it when
///     no value is saved;
///   - TestAddsSeeds: with the five rows removed, Run seeds each key with its default; the rows are put back after the test;
///   - TestUpgradeKeeps: a value saved before Run is the value after it;
///   - TestDefaultsAgree: Checks.Coverage THRESHOLDS equals the defaults, keys and bounds of the check-thresholds section of SettingsOps;
///   - TestAdminValue: licenseUsePercent 95 makes 91% in use pass, 91% fails at the default, and the new value is used once the cache has expired;
///   - TestNoGrant: the step declares no grant, and the generated list of grants has no entry from it;
///   - TestOrder: Digest runs after Demo in the registry.
Class OcuTalon.Test.Digest.Thresholds Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Digest.CoverageProbe";

Parameter STEP = "OcuTalon.Install.Step.Digest";

Parameter PREFIX = "checks.thresholds.";

/// The names of the five thresholds, comma-separated.
Parameter NAMES = "diskFreePercent,journalFreePercent,licenseUsePercent,queueMessages,queueWaitMinutes";

/// The stored value of each key before the test, as ^||ThresholdsTest(key) = $ListBuild(existed, value).
Method OnBeforeAllTests() As %Status
{
	Kill ^||ThresholdsTest
	For i = 1:1:5 {
		Set key = ..#PREFIX_$Piece(..#NAMES, ",", i)
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		Set ^||ThresholdsTest(key) = $ListBuild($IsObject(row), $Select($IsObject(row): row.Value, 1: ""))
	}
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..PutBack()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do $ClassMethod(..#PROBE, "Reset")
	Do ..PutBack()
	Quit $$$OK
}

/// Puts each stored value back as it was before the class began; a key that had no row keeps the seeded default, which a start writes anyway.
Method PutBack()
{
	Set key = ""
	For {
		Set key = $Order(^||ThresholdsTest(key), 1, was)
		Quit:key=""
		If $List(was, 1) {
			Do ##class(OcuTalon.Data.Setting).Set(key, $List(was, 2))
		} Else {
			Do ##class(OcuTalon.Data.Setting).Set(key, $Piece(..Default(key), "=", 2))
		}
	}
}

/// The "name=default" pair of THRESHOLDS for a key.
ClassMethod Default(key As %String) As %String
{
	Set pairs = $ListFromString($Parameter("OcuTalon.Checks.Coverage", "THRESHOLDS"))
	Set position = 0
	While $ListNext(pairs, position, pair) {
		If ..#PREFIX_$Piece(pair, "=", 1) = key Quit
	}
	Quit pair
}

Method TestDigestSeeds()
{
	Set keys = $ListBuild("digest.time", "digest.channels")
	Set was = ""
	Set position = 0
	While $ListNext(keys, position, key) {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		Set was = was_$ListBuild($ListBuild($IsObject(row), $Select($IsObject(row): row.Value, 1: "")))
		If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
		Kill ^||OcuTalon.Setting(key)
	}
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "the step runs with no digest row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexOpen("digest.time").Value, "08:00", "digest.time is 08:00")
	Do $$$AssertEquals($IsObject(##class(OcuTalon.Data.Setting).KeyIndexOpen("digest.channels")), 0, "the step seeds no digest.channels row")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Digest.Process", "Seeds").%ToJSON(), "{""digest.time"":""08:00""}", "the digest's seeds are digest.time alone")
	Set section = ##class(OcuTalon.Core.SettingsOps).Section("daily-digest")
	Do $$$AssertTrue($IsObject(section), "the settings have the daily-digest section")
	Set compared = 0
	If $IsObject(section) {
		Set iterator = section.fields.%GetIterator()
		While iterator.%GetNext(, .field) {
			If field.key = "digest.time" {
				Do $$$AssertEquals($ClassMethod("OcuTalon.Digest.Process", "Seeds").%Get(field.key), field.default, field.key_": the seed is the section's default")
				Set compared = compared + 1
			}
			If field.key = "digest.channels" {
				Set defaults = $ListFromString(field.default)
				Set names = $ListBuild("web", "phone", "telegram", "email")
				Set at = 0
				While $ListNext(names, at, name) {
					Do $$$AssertEquals(##class(OcuTalon.Core.Rule.Functions).DigestNamed(name), ''$ListFind(defaults, name), field.key_": with no row, Notify's rule names "_name_" exactly when the section's default does")
				}
				Set compared = compared + 1
			}
		}
	}
	Do $$$AssertEquals(compared, 2, "both digest keys are compared with the section's defaults")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set("digest.time", "07:30"), "an admin saves 07:30")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "the step runs again, as at an upgrade")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexOpen("digest.time").Value, "07:30", "the changed value is kept")
	Set position = 0
	Set n = 0
	While $ListNext(keys, position, key) {
		Set n = n + 1
		If $List($List(was, n), 1) {
			Do ##class(OcuTalon.Data.Setting).Set(key, $List($List(was, n), 2))
		} Else {
			Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
			If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
		}
		Kill ^||OcuTalon.Setting(key)
	}
}

Method TestAddsSeeds()
{
	For i = 1:1:5 {
		Set key = ..#PREFIX_$Piece(..#NAMES, ",", i)
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
		Kill ^||OcuTalon.Setting(key)
	}
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "the step runs with no threshold row")
	Set expected = $ListBuild(10, 10, 90, 100, 10)
	For i = 1:1:5 {
		Set key = ..#PREFIX_$Piece(..#NAMES, ",", i)
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		Do $$$AssertTrue($IsObject(row), key_" has a row")
		If $IsObject(row) {
			Do $$$AssertEquals(row.Value, $List(expected, i), key_" is its default")
		}
	}
	Set seeds = $ClassMethod("OcuTalon.Checks.Coverage", "Thresholds")
	Do $$$AssertEquals(seeds.%ToJSON(), "{""checks.thresholds.diskFreePercent"":""10"",""checks.thresholds.journalFreePercent"":""10"",""checks.thresholds.licenseUsePercent"":""90"",""checks.thresholds.queueMessages"":""100"",""checks.thresholds.queueWaitMinutes"":""10""}", "the seeds are the five defaults")
}

Method TestUpgradeKeeps()
{
	Set key = ..#PREFIX_"licenseUsePercent"
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set(key, "95"), "an admin saves 95")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Run"), "the step runs again, as at an upgrade")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexOpen(key).Value, 95, "the changed value is kept")
	Set before = ##class(OcuTalon.Data.Setting).KeyIndexOpen(..#PREFIX_"queueMessages").Value
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Seeds).Defaults({"checks.thresholds.queueMessages": "7"}), "Seeds.Defaults is OK for a key that has a row")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).KeyIndexOpen(..#PREFIX_"queueMessages").Value, before, "and leaves its value alone")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Install.Seeds).Defaults("not an object"), "and it refuses anything but an object")
}

Method TestDefaultsAgree()
{
	Set section = ##class(OcuTalon.Core.SettingsOps).Section("check-thresholds")
	Do $$$AssertTrue($IsObject(section), "SettingsOps has the section")
	Set fields = section.fields
	Do $$$AssertEquals(fields.%Size(), 5, "of five fields")
	Set iterator = fields.%GetIterator()
	While iterator.%GetNext(, .field) {
		Do $$$AssertEquals(..#PREFIX_field.name, field.key, field.name_": the key is the prefix and the name")
		Do $$$AssertEquals($Piece(..Default(field.key), "=", 2), field.default, field.name_": the default of Checks.Coverage is the section's")
	}
	Do $$$AssertEquals($Parameter("OcuTalon.Checks.Coverage", "KEYPREFIX"), ..#PREFIX, "and the prefix")
}

/// licenseUsePercent 95 is used by Build once the cache has expired.
Method TestAdminValue()
{
	Set key = ..#PREFIX_"licenseUsePercent"
	Do ##class(OcuTalon.Data.Setting).Set(key, "90")
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzthresholds")
	Set vitals = $ClassMethod(..#PROBE, "Healthy")
	Set vitals.license.usePercent = 91
	Do $ClassMethod(..#PROBE, "Feed", vitals)
	Do $ClassMethod(..#PROBE, "Build", session, "2030-06-01T11:50:00Z", "2030-06-01T12:00:00Z", .rows)
	Do $$$AssertEquals(rows.%Get(3).result, "failed", "at the default of 90, 91% in use fails")
	Do ##class(OcuTalon.Data.Setting).Set(key, "95")
	Kill ^||OcuTalon.Setting(key)
	Do $ClassMethod(..#PROBE, "Build", session, "2030-06-01T11:50:00Z", "2030-06-01T12:00:00Z", .rows)
	Do $$$AssertEquals(rows.%Get(3).result, "passed", "at 95 it passes")
	Set cached = ^||OcuTalon.Setting(key)
	Do ##class(OcuTalon.Data.Setting).Set(key, "80")
	Set ^||OcuTalon.Setting(key) = cached
	Do $ClassMethod(..#PROBE, "Build", session, "2030-06-01T11:50:00Z", "2030-06-01T12:00:00Z", .rows)
	Do $$$AssertEquals(rows.%Get(3).result, "passed", "within the cache the old value is read")
	Set expired = ^||OcuTalon.Setting(key)
	Set $List(expired, 3) = $ZHorolog - ##class(OcuTalon.Data.Setting).#CACHESECONDS - 1
	Set ^||OcuTalon.Setting(key) = expired
	Do $ClassMethod(..#PROBE, "Build", session, "2030-06-01T11:50:00Z", "2030-06-01T12:00:00Z", .rows)
	Do $$$AssertEquals(rows.%Get(3).result_"|"_rows.%Get(3).finding, "failed|91% in use", "after the cache has expired the new value, 80, is used")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(session)
	Do $ClassMethod(..#PROBE, "Reset")
}

Method TestNoGrant()
{
	Set grants = $ClassMethod(..#STEP, "Grants")
	Do $$$AssertEquals(grants.%Size(), 0, "the Digest step declares no grant")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Registry).Declared("Grants", .entries), "the grants of every area are read")
	Set found = 0
	Set n = ""
	For {
		Set n = $Order(entries(n))
		Quit:n=""
		Set entry = entries(n)
		If entries(n, "area") = ..#STEP Set found = found + 1
		Do $$$AssertTrue((entry.permission '[ "U") || (entry.resource '= "%Admin_Operate"), "no grant of %Admin_Operate:U ("_entry.role_" "_entry.resource_")")
	}
	Do $$$AssertEquals(found, 0, "and none comes from the Digest area")
}

Method TestOrder()
{
	Set order = ##class(OcuTalon.Install.Registry).Order()
	Do $$$AssertEquals($ListFind(order, "Digest"), $ListFind(order, "Demo") + 1, "Digest runs right after Demo")
}

}
