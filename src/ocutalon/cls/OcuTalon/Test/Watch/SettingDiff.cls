/// Tests of the setting history that need no other namespace (Story 36.1; AD-5, AD-15, AD-27): OcuTalon.Watch.SettingHistory's Diff, Due, Record and Purge, and
/// the two tables, over fixture rows of the namespace ZZNS and the production Zz.Production (and Zz.Other), which they remove again. The live Tick over the
/// Orders production is Test.Watch.SettingHistory's.
///   - TestDiff: a setting that is added, removed, given another value or kept the same; an item that is added or removed gives one change for each of its settings,
///     with a blank old or new value;
///   - TestFirstSnapshot: the first snapshot of a production gives no change; a changed second gives a new snapshot and one change for each difference, dated at the
///     Tick, with the new snapshot's Ref; a same second only updates the marks and CheckedAt of the newest row;
///   - TestSecretEntries: a secret setting differs when its hash does, and its two values are blank; the same hash is no difference; a Credentials reference
///     is diffed as a plain value;
///   - TestSettingEntries: Reader.SettingEntry keeps the ID of a Credentials reference, whether it is named Credentials or is marked a reference by its editor
///     context under another name (SOAPCredentials), and blanks a secret value, giving it a hash that is kept while the value is the same;
///   - TestDue: no snapshot, a start mark that differs (a restart), a counter that differs or is gone, and an hour since the last check each make the settings
///     due; the same marks and a check under an hour old do not;
///   - TestPurge: through Install.Step.Watch.Purge(90), changes detected and snapshots taken 91 days ago are gone, those of 89 days stay, and the newest snapshot of a
///     watched production stays however old (a production that is not watched keeps nothing older than 90 days); a day count that is not a whole number of at least 1 is an error and deletes nothing.
Class OcuTalon.Test.Watch.SettingDiff Extends %UnitTest.TestCase
{

Parameter HISTORY = "OcuTalon.Watch.SettingHistory";

Parameter NAMESPACE = "ZZNS";

Parameter PRODUCTION = "Zz.Production";

Parameter OTHER = "Zz.Other";

Parameter UNWATCHED = "Zz.Unwatched";

Parameter GONE = "Zz.Gone";

Property Refs As %String(MAXLEN = "");

Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ..Drop()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Drop()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Quit $$$OK
}

/// Deletes the history rows of the namespace.
ClassMethod Drop()
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SettingChange WHERE Namespace = ?", ..#NAMESPACE)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.SettingSnapshot WHERE Namespace = ?", ..#NAMESPACE)
}

/// One entry of a settings array, the shape of Reader.Settings'.
ClassMethod Entry(item As %String, setting As %String, value As %String, source As %String = "production", credential As %Boolean = 0, hash As %String = "", target As %String = "Host") As %DynamicObject
{
	Quit {"item": (item), "target": (target), "setting": (setting), "value": (value), "source": (source), "credential": (+credential), "hash": (hash)}
}

/// The changes of Diff as lines "item/setting old>new source credential", in order, joined by ";".
ClassMethod Lines(changes As %DynamicArray) As %String
{
	Set text = ""
	Set iterator = changes.%GetIterator()
	While iterator.%GetNext(, .change) {
		Set text = text_$Select(text = "": "", 1: ";")_change.item_"/"_change.setting_" "_change.oldValue_">"_change.newValue_" "_change.source_" "_change.credential
	}
	Quit text
}

Method TestDiff()
{
	Set before = [(..Entry("A", "Same", "1")), (..Entry("A", "Changed", "1")), (..Entry("A", "Removed", "x", "class")), (..Entry("B", "One", "1")), (..Entry("B", "Two", "2"))]
	Set after = [(..Entry("A", "Same", "1")), (..Entry("A", "Changed", "2", "default")), (..Entry("A", "Added", "y")), (..Entry("C", "One", "1")), (..Entry("C", "Two", "2"))]
	Set changes = $ClassMethod(..#HISTORY, "Diff", before, after)
	Do $$$AssertEquals(..Lines(changes), "A/Changed 1>2 default 0;A/Added >y production 0;C/One >1 production 0;C/Two >2 production 0;A/Removed x> class 0;B/One 1> production 0;B/Two 2> production 0", "added, removed and changed settings, and the settings of an item that is added or removed, one change each; the unchanged setting none")
	Do $$$AssertEquals($ClassMethod(..#HISTORY, "Diff", before, before).%Size(), 0, "the same settings differ in nothing")
	Do $$$AssertEquals($ClassMethod(..#HISTORY, "Diff", [], after).%Size(), 5, "against nothing, every setting is an addition")
	Set sameValueOtherSource = [(..Entry("A", "Same", "1", "default"))]
	Do $$$AssertEquals($ClassMethod(..#HISTORY, "Diff", [(..Entry("A", "Same", "1"))], sameValueOtherSource).%Size(), 0, "a setting whose value is the same is no change, whatever its source")
	Set targets = $ClassMethod(..#HISTORY, "Diff", [(..Entry("A", "S", "1", , , , "Host"))], [(..Entry("A", "S", "1", , , , "Adapter"))])
	Do $$$AssertEquals(..Lines(targets), "A/S >1 production 0;A/S 1> production 0", "the same name on the other target is another setting")
}

Method TestSecretEntries()
{
	Set one = ##class(OcuTalon.Data.Webhook).HashSecret("zz secret")
	Set again = ##class(OcuTalon.Data.Webhook).HashSecret("zz secret")
	Do $$$AssertNotEquals(one, again, "the same secret hashed twice gives two strings, because each has a salt of its own")
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).Matches(one, "zz secret") && ##class(OcuTalon.Data.Webhook).Matches(again, "zz secret"), "and each matches the secret: Reader.Settings keeps the old hash for a secret that matches it")
	Set other = ##class(OcuTalon.Data.Webhook).HashSecret("another")
	Set before = [(..Entry("A", "ApiKey", "", "production", 1, one))]
	Do $$$AssertEquals($ClassMethod(..#HISTORY, "Diff", before, [(..Entry("A", "ApiKey", "", "production", 1, one))]).%Size(), 0, "a secret setting whose hash is as it was is no change")
	Set changes = $ClassMethod(..#HISTORY, "Diff", before, [(..Entry("A", "ApiKey", "", "production", 1, other))])
	Do $$$AssertEquals(..Lines(changes), "A/ApiKey > production 1", "a secret setting whose hash differs is one change, with both values blank and Credential 1")
	Do $$$AssertEquals(changes.%ToJSON() [ one, 0, "the change holds neither hash")
	Do $$$AssertEquals(changes.%ToJSON() [ other, 0, "not the new one")
	Set added = $ClassMethod(..#HISTORY, "Diff", [], [(..Entry("A", "ApiKey", "", "production", 1, one))])
	Do $$$AssertEquals(..Lines(added), "A/ApiKey > production 1", "a secret setting that is added is blank on both sides")
	Set removed = $ClassMethod(..#HISTORY, "Diff", before, [])
	Do $$$AssertEquals(..Lines(removed), "A/ApiKey > production 1", "and so is one that is removed")
	Set reference = $ClassMethod(..#HISTORY, "Diff", [(..Entry("A", "Credentials", "ZzCredA"))], [(..Entry("A", "Credentials", "ZzCredB"))])
	Do $$$AssertEquals(..Lines(reference), "A/Credentials ZzCredA>ZzCredB production 0", "a Credentials reference is a plain value, diffed with its IDs")
}

/// A snapshot row of the namespace and the production, taken that many seconds before now, with the marks; the settings are an empty array.
Method Snapshot(production As %String, ageSeconds As %Integer, counter As %String = "1", started As %String = "start|1") As OcuTalon.Data.SettingSnapshot
{
	Set at = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -ageSeconds)
	Set row = ##class(OcuTalon.Data.SettingSnapshot).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Namespace = ..#NAMESPACE
	Set row.Production = production
	Set row.TakenAt = at
	Set row.CheckedAt = at
	Set row.Counter = counter
	Set row.Started = started
	Do row.Settings.Write("[]")
	Do $$$AssertStatusOK(row.%Save(), "a fixture snapshot is saved")
	Quit row
}

/// A change row of the namespace, detected that many seconds before now.
Method Change(production As %String, ageSeconds As %Integer) As OcuTalon.Data.SettingChange
{
	Set row = ##class(OcuTalon.Data.SettingChange).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Namespace = ..#NAMESPACE
	Set row.Production = production
	Set row.Item = "A"
	Set row.Target = "Host"
	Set row.Setting = "S"
	Set row.Source = "production"
	Set row.DetectedAt = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -ageSeconds)
	Do $$$AssertStatusOK(row.%Save(), "a fixture change is saved")
	Quit row
}

ClassMethod Snapshots(production As %String) As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SettingSnapshot WHERE Namespace = ? AND Production = ?", ..#NAMESPACE, production)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

ClassMethod ChangeRows(production As %String) As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SettingChange WHERE Namespace = ? AND Production = ?", ..#NAMESPACE, production)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

Method TestFirstSnapshot()
{
	Set marks = {"counter": "3", "started": "start|1"}
	Set first = [(..Entry("A", "S", "1")), (..Entry("A", "T", "2"))]
	Set at = ##class(OcuTalon.Data.Time).NowUtc()
	Set changes = $ClassMethod(..#HISTORY, "Record", ..#NAMESPACE, ..#PRODUCTION, at, "", marks, first)
	Do $$$AssertEquals(changes.%Size(), 0, "a first snapshot has no change")
	Do $$$AssertEquals(..Snapshots(..#PRODUCTION)_"|"_..ChangeRows(..#PRODUCTION), "1|0", "one snapshot and no change row are written")
	Set newest = ##class(OcuTalon.Data.SettingSnapshot).%OpenId(##class(OcuTalon.Data.SettingSnapshot).Newest(..#NAMESPACE, ..#PRODUCTION))
	Do $$$AssertEquals(newest.TakenAt_"|"_newest.CheckedAt_"|"_newest.Counter_"|"_newest.Started, at_"|"_at_"|3|start|1", "it holds the time and the marks")
	Do $$$AssertEquals(newest.Settings.Read(100000), first.%ToJSON(), "and the settings")
	Set later = ##class(OcuTalon.Data.Time).AddSeconds(at, 60)
	Set same = $ClassMethod(..#HISTORY, "Record", ..#NAMESPACE, ..#PRODUCTION, later, newest, {"counter": "4", "started": "start|1"}, first)
	Do $$$AssertEquals(same.%Size(), 0, "the same settings give no change")
	Do $$$AssertEquals(..Snapshots(..#PRODUCTION)_"|"_..ChangeRows(..#PRODUCTION), "1|0", "and no new row")
	Set refreshed = ##class(OcuTalon.Data.SettingSnapshot).%OpenId(newest.%Id())
	Do $$$AssertEquals(refreshed.TakenAt_"|"_refreshed.CheckedAt_"|"_refreshed.Counter, at_"|"_later_"|4", "only the marks and CheckedAt of the newest row are updated, in place")
	Set second = [(..Entry("A", "S", "2")), (..Entry("A", "U", "3"))]
	Set evenLater = ##class(OcuTalon.Data.Time).AddSeconds(at, 120)
	Set changes = $ClassMethod(..#HISTORY, "Record", ..#NAMESPACE, ..#PRODUCTION, evenLater, refreshed, {"counter": "5", "started": "start|1"}, second)
	Do $$$AssertEquals(..Lines(changes), "A/S 1>2 production 0;A/U >3 production 0;A/T 2> production 0", "different settings give one change for each difference")
	Do $$$AssertEquals(..Snapshots(..#PRODUCTION)_"|"_..ChangeRows(..#PRODUCTION), "2|3", "a new snapshot and three change rows are written")
	Set newest = ##class(OcuTalon.Data.SettingSnapshot).%OpenId(##class(OcuTalon.Data.SettingSnapshot).Newest(..#NAMESPACE, ..#PRODUCTION))
	Do $$$AssertEquals(newest.TakenAt_"|"_newest.Counter, evenLater_"|5", "the new snapshot is the newest")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SettingChange WHERE Namespace = ? AND Production = ? AND DetectedAt = ? AND SnapshotRef = ?", ..#NAMESPACE, ..#PRODUCTION, evenLater, newest.Ref)
	Do rs.%Next()
	Do $$$AssertEquals(+rs.%GetData(1), 3, "each change is dated at the Tick and names the new snapshot")
}

Method TestSettingEntries()
{
	Set reader = "OcuTalon.Watch.Reader"
	Set named = $ClassMethod(reader, "SettingEntry", {"item": "A", "target": "Adapter", "setting": "Credentials", "value": "ZzCredA", "source": "production", "reference": 0})
	Do $$$AssertEquals(named.value_"|"_named.credential_"|"_named.hash, "ZzCredA|0|", "a setting named Credentials keeps its ID, is no secret and has no hash")
	Set lower = $ClassMethod(reader, "SettingEntry", {"item": "A", "target": "Adapter", "setting": "credentials", "value": "ZzCredA", "source": "production", "reference": 0})
	Do $$$AssertEquals(lower.value_"|"_lower.credential, "ZzCredA|0", "in any case")
	Set marked = $ClassMethod(reader, "SettingEntry", {"item": "A", "target": "Adapter", "setting": "SOAPCredentials", "value": "ZzCredB", "source": "class", "reference": 1})
	Do $$$AssertEquals(marked.value_"|"_marked.credential_"|"_marked.hash_"|"_marked.source, "ZzCredB|0||class", "a setting that the editor context marks as a reference keeps its ID under any name")
	Set unmarked = $ClassMethod(reader, "SettingEntry", {"item": "A", "target": "Adapter", "setting": "SOAPCredentials", "value": "ZzCredB", "source": "class", "reference": 0})
	Do $$$AssertEquals(unmarked.value_"|"_unmarked.credential, "|1", "while the same name without the mark is a secret value, blank")
	Set secret = $ClassMethod(reader, "SettingEntry", {"item": "A", "target": "Host", "setting": "ApiKey", "value": "zz-secret", "source": "production", "reference": 0})
	Do $$$AssertEquals(secret.value_"|"_secret.credential, "|1", "a secret value is blank and marked")
	Do $$$AssertTrue(##class(OcuTalon.Data.Webhook).Matches(secret.hash, "zz-secret"), "and its hash matches the value")
	Set salts = {}
	Do salts.%Set($ClassMethod(reader, "SaltKey", "A", "Host", "ApiKey"), secret.hash)
	Set again = $ClassMethod(reader, "SettingEntry", {"item": "A", "target": "Host", "setting": "ApiKey", "value": "zz-secret", "source": "production", "reference": 0}, salts)
	Do $$$AssertEquals(again.hash, secret.hash, "the same value with the earlier hash in salts keeps that hash")
	Set other = $ClassMethod(reader, "SettingEntry", {"item": "A", "target": "Host", "setting": "ApiKey", "value": "zz-other", "source": "production", "reference": 0}, salts)
	Do $$$AssertTrue((other.hash '= secret.hash) && ##class(OcuTalon.Data.Webhook).Matches(other.hash, "zz-other"), "another value gets a new hash")
	Set plain = $ClassMethod(reader, "SettingEntry", {"item": "A", "target": "Host", "setting": "RetryInterval", "value": "5", "source": "class", "reference": 0})
	Do $$$AssertEquals(plain.value_"|"_plain.credential_"|"_plain.hash, "5|0|", "any other setting keeps its value")
}

Method TestDue()
{
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set last = ..Snapshot(..#PRODUCTION, 0, "5", "start|1")
	Set marks = {"counter": "5", "started": "start|1"}
	Do $$$AssertEquals($ClassMethod(..#HISTORY, "Due", "", marks, now), 1, "a production with no snapshot is due")
	Do $$$AssertEquals($ClassMethod(..#HISTORY, "Due", last, marks, ##class(OcuTalon.Data.Time).AddSeconds(last.CheckedAt, 60)), 0, "the same marks and a check a minute old: not due")
	Do $$$AssertEquals($ClassMethod(..#HISTORY, "Due", last, marks, ##class(OcuTalon.Data.Time).AddSeconds(last.CheckedAt, 3599)), 0, "also 3599 seconds after the check")
	Do $$$AssertEquals($ClassMethod(..#HISTORY, "Due", last, marks, ##class(OcuTalon.Data.Time).AddSeconds(last.CheckedAt, 3600)), 1, "3600 seconds after it: due")
	Do $$$AssertEquals($ClassMethod(..#HISTORY, "Due", last, {"counter": "6", "started": "start|1"}, now), 1, "a counter that moved: due")
	Do $$$AssertEquals($ClassMethod(..#HISTORY, "Due", last, {"counter": "", "started": "start|1"}, now), 1, "a counter that is gone: due")
	Do $$$AssertEquals($ClassMethod(..#HISTORY, "Due", last, {"counter": "5", "started": "start|2"}, now), 1, "a start mark that differs (a restart): due")
	Do $$$AssertEquals($ClassMethod(..#HISTORY, "Due", last, marks, ""), 1, "a Tick time that is not a time: due")
	Set gone = ..Snapshot(..#OTHER, 0, "", "start|1")
	Do $$$AssertEquals($ClassMethod(..#HISTORY, "Due", gone, {"counter": "", "started": "start|1"}, ##class(OcuTalon.Data.Time).AddSeconds(gone.CheckedAt, 60)), 0, "a counter that was never there and still is not is no difference")
	Do $$$AssertEquals($ClassMethod(..#HISTORY, "Due", gone, {"counter": "0", "started": "start|1"}, ##class(OcuTalon.Data.Time).AddSeconds(gone.CheckedAt, 60)), 1, "but a counter that appears is")
}

Method TestPurge()
{
	Set session = ##class(OcuTalon.Test.Data.Fixture).Session("zzsettingdiff")
	Set ..Refs = session
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(session, ..#NAMESPACE, ..#PRODUCTION)
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(session, ..#NAMESPACE, ..#OTHER)
	Set day = 86400
	Do ..Snapshot(..#PRODUCTION, 95 * day)
	Do ..Snapshot(..#PRODUCTION, 91 * day)
	Do ..Snapshot(..#OTHER, 91 * day)
	Do ..Snapshot(..#OTHER, 89 * day)
	Do ..Snapshot(..#UNWATCHED, 91 * day)
	Do ..Snapshot(..#UNWATCHED, 89 * day)
	Do ..Snapshot(..#GONE, 95 * day)
	Do ..Change(..#PRODUCTION, 91 * day)
	Do ..Change(..#PRODUCTION, 89 * day)
	Set bad = ##class(OcuTalon.Install.Step.Watch).Purge(0)
	Do $$$AssertStatusNotOK(bad, "a day count of 0 is an error")
	Do $$$AssertEquals(..Snapshots(..#PRODUCTION)_..Snapshots(..#OTHER)_..Snapshots(..#UNWATCHED)_..Snapshots(..#GONE)_..ChangeRows(..#PRODUCTION), "22212", "and nothing is deleted")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Watch).Purge(90), "the Watch area's purge runs")
	Do $$$AssertEquals(..ChangeRows(..#PRODUCTION), 1, "the change of 91 days is gone and the change of 89 days stays")
	Do $$$AssertEquals(..Snapshots(..#PRODUCTION), 1, "of a watched production's snapshots of 95 and 91 days, the newest stays however old it is")
	Set kept = ##class(OcuTalon.Data.SettingSnapshot).%OpenId(##class(OcuTalon.Data.SettingSnapshot).Newest(..#NAMESPACE, ..#PRODUCTION))
	Do $$$AssertTrue(kept.TakenAt ] ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -93 * day), "and it is the newer of the two")
	Do $$$AssertEquals(..Snapshots(..#OTHER), 1, "of another watched production's snapshots of 91 and 89 days, the old one is gone")
	Set newer = ##class(OcuTalon.Data.SettingSnapshot).%OpenId(##class(OcuTalon.Data.SettingSnapshot).Newest(..#NAMESPACE, ..#OTHER))
	Do $$$AssertTrue(newer.TakenAt ] ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -90 * day), "and the one of 89 days stays")
	Do $$$AssertEquals(..Snapshots(..#UNWATCHED), 1, "a production that is not watched keeps only what is under 90 days old")
	Set rest = ##class(OcuTalon.Data.SettingSnapshot).%OpenId(##class(OcuTalon.Data.SettingSnapshot).Newest(..#NAMESPACE, ..#UNWATCHED))
	Do $$$AssertTrue(rest.TakenAt ] ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -90 * day), "the one of 89 days")
	Do $$$AssertEquals(..Snapshots(..#GONE), 0, "and a production that is not watched has no snapshot kept as its newest, however old")
}

}
