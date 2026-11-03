/// Tests of the agent heartbeat's names and stubs (Story 39.1; AD-18, AD-19, AD-33): the BeatNow message has exactly its contract and shares the
/// Ens.MessageBody extent, the stubs of OcuTalon.Checks.Beat do nothing (they return OK or "", write no HeartbeatBeat row and send nothing), and the
/// setting names, defaults and caps are the spine's, the checklist cap being the length of Setting.Value. The tests need no production (warm).
/// A HeartbeatBeat row keeps all 15 fields through a save and a reopen, with the defaults of an empty row, in the private global
/// ^OcuTalonP.HeartbeatBeat; a second row of the same SessionRef is refused and leaves the first untouched; SettingKey takes a name only exactly as KEYS lists it.
Class OcuTalon.Test.Checks.Beat Extends OcuTalon.Test.Contract
{

Parameter BEAT = "OcuTalon.Checks.Beat";

Method TestBeatNowContract()
{
	Do ..AssertContract("Contracts")
	Do ..AssertMessageExtent("Contracts")
}

Method TestStubsDoNothing()
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set before = ..Rows("")
	Do $$$AssertStatusOK($ClassMethod(..#BEAT, "RunDue", "2030-06-01T12:00:00Z"), "RunDue is OK")
	Do $$$AssertStatusOK($ClassMethod(..#BEAT, "RunNow", ref), "RunNow is OK")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "Snapshot", ref, "2030-06-01T12:00:00Z"), "", "Snapshot is empty")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "Key", "x"), "", "Key is empty")
	Do $$$AssertEquals(..Rows(ref), 0, "no HeartbeatBeat row is made for the fixture ref")
	Do $$$AssertEquals(..Rows(""), before, "and the table holds as many rows as before")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.HeartbeatBeat WHERE SessionRef = ?", ref)
}

Method TestSettingNames()
{
	Set ref = "zzbeatname"
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "interval"), "person.zzbeatname.heartbeat.interval", "a known name gives its key")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "zz"), "", "an unknown name gives empty")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, ""), "", "so does an empty name")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "on,interval"), "", "and a list of names")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "ON"), "", "a name in another case is unknown")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "int"), "", "so is a part of a name")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "interval "), "", "and a name with a space after it")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "interval,"), "", "and with a comma after it")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", "zzother", "on"), "person.zzother.heartbeat.on", "each session has its own key")
	Set keys = $ListFromString($Parameter(..#BEAT, "KEYS"))
	Set position = 0
	While $ListNext(keys, position, name) {
		Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, name), "person.zzbeatname.heartbeat."_name, "the key of "_name)
	}
	Do $$$AssertEquals($Parameter(..#BEAT, "KEYS"), "on,interval,from,to,checklist", "the keys")
	Do $$$AssertEquals($Parameter(..#BEAT, "INTERVALS"), "30,60,120,240,480,1440", "the intervals")
	Do $$$AssertEquals($Parameter(..#BEAT, "DEFAULTON"), 1, "on by default")
	Do $$$AssertEquals($Parameter(..#BEAT, "DEFAULTONDEMO"), 0, "and off on the online demo")
	Do $$$AssertEquals($Parameter(..#BEAT, "DEFAULTINTERVAL"), 30, "the default interval")
	Do $$$AssertEquals($Parameter(..#BEAT, "DEFAULTFROM"), "08:00", "the default start of the window")
	Do $$$AssertEquals($Parameter(..#BEAT, "DEFAULTTO"), "20:00", "the default end of the window")
	Do $$$AssertEquals($Parameter(..#BEAT, "CHECKLISTMAX"), 1000, "the checklist cap")
	Set value = ##class(%Dictionary.CompiledProperty).%OpenId("OcuTalon.Data.Setting||Value")
	Do $$$AssertEquals($Select($IsObject(value): value.Parameters.GetAt("MAXLEN"), 1: ""), $Parameter(..#BEAT, "CHECKLISTMAX"), "which is the length of Setting.Value (AD-19)")
}

Method TestHeartbeatBeatRowAndUniqueness()
{
	Set first = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set second = ##class(OcuTalon.Bridge.Ids).NewRef()
	Try {
		Set row = ##class(OcuTalon.Data.HeartbeatBeat).%New()
		Set row.SessionRef = first
		Set row.NextDueAt = "2030-06-01T12:30:00Z"
		Set row.LastBeatAt = "2030-06-01T12:00:00Z"
		Set row.LastItemId = "item-ref"
		Set row.LastOutcome = "item"
		Set row.LastFallback = 1
		Set row.LastCostUSD = 0.012346
		Set row.LastDecisionRef = "decision-ref"
		Set row.LastTraceSessionId = 4242
		Set row.LastSkipAt = "2030-06-01T11:00:00Z"
		Set row.LastSkipReason = "quiet_hours"
		Set row.LastRunNowAt = "2030-06-01T11:30:00Z"
		Set row.BackoffUntil = "2030-06-01T13:00:00Z"
		Set row.LastSnapshotKey = "snapshot-key"
		Set row.LastQuietKey = "quiet-key"
		Do $$$AssertStatusOK(row.%Save(), "a row with all 15 fields is saved")
		Set id = row.%Id()
		Kill row
		Set row = ..Open(first)
		Do $$$AssertTrue($IsObject(row), "and found again by its SessionRef")
		If $IsObject(row) {
			Do $$$AssertEquals(row.NextDueAt_"|"_row.LastBeatAt_"|"_row.LastItemId_"|"_row.LastOutcome_"|"_row.LastFallback_"|"_row.LastCostUSD_"|"_row.LastDecisionRef_"|"_row.LastTraceSessionId, "2030-06-01T12:30:00Z|2030-06-01T12:00:00Z|item-ref|item|1|.012346|decision-ref|4242", "the first eight fields come back")
			Do $$$AssertEquals(row.LastSkipAt_"|"_row.LastSkipReason_"|"_row.LastRunNowAt_"|"_row.BackoffUntil_"|"_row.LastSnapshotKey_"|"_row.LastQuietKey, "2030-06-01T11:00:00Z|quiet_hours|2030-06-01T11:30:00Z|2030-06-01T13:00:00Z|snapshot-key|quiet-key", "and so do the other six")
		}
		Do $$$AssertTrue($Data(^OcuTalonP.HeartbeatBeatD(id)), "the row is in the private data global ^OcuTalonP.HeartbeatBeatD")
		Do $$$AssertEquals($Data(^OcuTalon.HeartbeatBeatD) + $Data(^OcuTalon.Data.HeartbeatBeatD), 0, "and in no default global")

		// a second row of the same SessionRef is refused; another SessionRef is accepted
		Set duplicate = ##class(OcuTalon.Data.HeartbeatBeat).%New()
		Set duplicate.SessionRef = first
		Set duplicate.NextDueAt = "2031-01-01T00:00:00Z"
		Do $$$AssertStatusNotOK(duplicate.%Save(), "a second row of the same SessionRef is refused")
		Do $$$AssertEquals(..Rows(first), 1, "so the session still has one row")
		Set row = ..Open(first)
		Do $$$AssertEquals(row.NextDueAt, "2030-06-01T12:30:00Z", "and the first row is untouched")
		Set other = ##class(OcuTalon.Data.HeartbeatBeat).%New()
		Set other.SessionRef = second
		Do $$$AssertStatusOK(other.%Save(), "a row of another SessionRef is saved")
		Set other = ..Open(second)
		Do $$$AssertEquals(other.LastFallback_"|"_other.NextDueAt_"|"_other.LastTraceSessionId, "0||", "and an empty row has fallback 0 and empty times")
	} Catch exception {
		Do $$$AssertTrue(0, "no exception: "_exception.DisplayString())
	}
	Kill row, duplicate, other
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.HeartbeatBeat WHERE SessionRef IN (?, ?)", first, second)
	Do $$$AssertEquals(..Rows(first) + ..Rows(second), 0, "the fixture rows are removed")
}

/// The HeartbeatBeat row of the session Ref, found by SQL (so that the test does not rely on the unique index), or "".
Method Open(ref As %String) As OcuTalon.Data.HeartbeatBeat
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM OcuTalon_Data.HeartbeatBeat WHERE SessionRef = ? ORDER BY ID", ref)
	If result.%Next() Quit ##class(OcuTalon.Data.HeartbeatBeat).%OpenId(result.%GetData(1))
	Quit ""
}

/// The number of HeartbeatBeat rows of the session Ref, or of all sessions when ref is empty.
Method Rows(ref As %String) As %Integer
{
	If ref = "" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.HeartbeatBeat")
	} Else {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.HeartbeatBeat WHERE SessionRef = ?", ref)
	}
	Do result.%Next()
	Quit +result.%GetData(1)
}

XData Contracts [ MimeType = application/json ]
{
{
 "OcuTalon.Checks.Msg.BeatNow": {
  "super": "Ens.Request",
  "props": {
   "SessionRef": "%String(MAXLEN=22)",
   "RequestedAt": "%String(MAXLEN=20)"
  }
 }
}
}

}
