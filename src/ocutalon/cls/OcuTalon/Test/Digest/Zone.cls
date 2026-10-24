/// Tests that pin the times of the digest area to UTC in a process whose zone is not UTC (Story 1.12; AD-18). A throwaway's IRIS runs in
/// UTC, where a time taken from the local clock reads the same as one taken from the UTC clock, so these tests give the process a zone first (the zone
/// base, OcuTalon.Test.Bridge.ZoneCase, puts back the one it had) and call the code in process. They need no production.
///   - TestKeptTimeIsUtc: the RecordedAt that DigestStore gives a kept item is UTC to the second, between the clock before and after the call, in four zones;
///   - TestSinceIsUtc: Item.Since compares the time it is given with the stored times as UTC, in four zones: the rows an hour either side of the time
///     and the time itself give the same answer in each;
///   - TestPurgeCutoffIsUtc: Item.Purge moves the UTC date back, not the local one: a row an hour either side of the cutoff is kept or deleted rightly in
///     a zone that is ahead of UTC by 14 hours and in one that is behind it by 11, so that in at least one of them the local date is not the UTC date.
/// Every row has a Ref that begins with zzDigest, like those of OcuTalon.Test.Digest.Store, and the rows are deleted before the class and after every test.
Class OcuTalon.Test.Digest.Zone Extends OcuTalon.Test.Bridge.ZoneCase
{

/// The class whose helpers make the Refs, the decisions and the times.
Parameter STORE = "OcuTalon.Test.Digest.Store";

Method OnBeforeAllTests() As %Status
{
	Do $ClassMethod(..#STORE, "Clean")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do $ClassMethod(..#STORE, "Clean")
	Quit sc
}

/// DigestStore stamps the item it keeps with the UTC time of the save, whatever the zone of the process.
Method TestKeptTimeIsUtc()
{
	Set zones = $ListBuild("America/New_York", "Asia/Kolkata", "Pacific/Kiritimati", "Pacific/Pago_Pago")
	Set position = 0
	While $ListNext(zones, position, zone) {
		Do $SYSTEM.Process.TimeZone(zone)
		Set label = zone_": "
		Set now = ##class(OcuTalon.Data.Time).NowUtc()
		Do $$$AssertTrue(##class(OcuTalon.Data.Time).ToLocal(now) '= $Extract(now, 1, 19), label_"control: the clock of the process is not UTC")
		Set host = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Digest.Store", .sc)
		Do $$$AssertTrue($IsObject(host), label_"a shadow instance of DigestStore is made")
		If '$IsObject(host) Continue
		Set itemId = $ClassMethod(..#STORE, "NewRef")
		Set decision = $ClassMethod(..#STORE, "Decision", itemId, $ClassMethod(..#STORE, "NewRef"))
		Kill response
		Set before = ##class(OcuTalon.Data.Time).NowUtc()
		Set sc = host.OnMessage(decision, .response)
		Set after = ##class(OcuTalon.Data.Time).NowUtc()
		Do $$$AssertStatusOK(sc, label_"the decision is kept")
		Set stored = $ClassMethod(..#STORE, "Stored", itemId)
		Do $$$AssertTrue(stored '= "", label_"the row is found")
		If stored = "" Continue
		Do $$$AssertTrue(stored.recordedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", label_"its RecordedAt is UTC to the second: "_stored.recordedAt)
		Do $$$AssertTrue((before '] stored.recordedAt) && (stored.recordedAt '] after), label_"and lies between the UTC clock before the call ("_before_") and after it ("_after_")")
	}
}

/// Since reads the time it is given as UTC: the rows at an hour either side of it and at it give the same answer in every zone.
Method TestSinceIsUtc()
{
	Set zones = $ListBuild("America/New_York", "Asia/Kolkata", "Pacific/Kiritimati", "Pacific/Pago_Pago")
	Set position = 0
	While $ListNext(zones, position, zone) {
		Do $SYSTEM.Process.TimeZone(zone)
		Set label = zone_": "
		Set now = ##class(OcuTalon.Data.Time).NowUtc()
		Do $$$AssertTrue(##class(OcuTalon.Data.Time).ToLocal(now) '= $Extract(now, 1, 19), label_"control: the clock of the process is not UTC")
		Set a = $ClassMethod(..#STORE, "NewRef")
		Set since = $ClassMethod(..#STORE, "AgoUtc", 2 * 86400)
		Set early = ..Add(a, $ClassMethod(..#STORE, "NewRef"), $ClassMethod(..#STORE, "AgoUtc", 2 * 86400 + 3600))
		Set at = ..Add(a, $ClassMethod(..#STORE, "NewRef"), since)
		Set late = ..Add(a, $ClassMethod(..#STORE, "NewRef"), $ClassMethod(..#STORE, "AgoUtc", 2 * 86400 - 3600))
		Do $$$AssertStatusOK(##class(OcuTalon.Digest.Data.Item).Since(a, since, .items), label_"Since is OK")
		Do $$$AssertEquals($ClassMethod(..#STORE, "ItemIdsOf", items), late.ItemId_" "_at.ItemId, label_"from the UTC time: the row an hour later and the row at it, not the row an hour earlier")
	}
}

/// Purge moves the UTC date back by the day count: the row an hour older than the cutoff is deleted and the row an hour newer is kept, in a zone ahead of
/// UTC by 14 hours and in one behind it by 11. The two zones are not on the UTC date at the same time of day, so at any time one of them has a local date that is
/// not the UTC date (the control).
Method TestPurgeCutoffIsUtc()
{
	Set apart = 0
	Set zones = $ListBuild("Pacific/Kiritimati", "Pacific/Pago_Pago")
	Set position = 0
	While $ListNext(zones, position, zone) {
		Do $SYSTEM.Process.TimeZone(zone)
		Set label = zone_": "
		Set now = ##class(OcuTalon.Data.Time).NowUtc()
		If $Piece(##class(OcuTalon.Data.Time).ToLocal(now), "T", 1) '= $Piece(now, "T", 1) Set apart = apart + 1
		Set a = $ClassMethod(..#STORE, "NewRef")
		Set beyond = ..Add(a, $ClassMethod(..#STORE, "NewRef"), $ClassMethod(..#STORE, "AgoUtc", 30 * 86400 + 3600))
		Set within = ..Add(a, $ClassMethod(..#STORE, "NewRef"), $ClassMethod(..#STORE, "AgoUtc", 30 * 86400 - 3600))
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Digest).Purge(30), label_"Purge(30) is OK")
		Do $$$AssertEquals($ClassMethod(..#STORE, "CountItem", beyond.ItemId), 0, label_"the item of 30 days and an hour ago is gone")
		Do $$$AssertEquals($ClassMethod(..#STORE, "CountItem", within.ItemId), 1, label_"the item of 30 days less an hour ago is kept")
	}
	Do $$$AssertTrue(apart '< 1, "control: in one of the two zones the local date is not the UTC date, so a purge by the local date would show")
}

/// Saves a row for the session and item recorded at the time (OcuTalon.Test.Digest.Store's NewRow), asserts that it is saved, and returns it.
Method Add(sessionRef As %String, itemId As %String, recordedAt As %String) As OcuTalon.Digest.Data.Item
{
	Set row = ##class(OcuTalon.Test.Digest.Store).NewRow(sessionRef, itemId, recordedAt, .sc)
	Do $$$AssertStatusOK(sc, "a fixture row is saved")
	Quit row
}

}
