/// Tests of the agent heartbeat's names and stubs (Story 39.1; AD-18, AD-19, AD-33): the BeatNow message has exactly its contract and shares the
/// Ens.MessageBody extent, the stubs of OcuTalon.Checks.Beat do nothing (they return OK or "", write no HeartbeatBeat row and send nothing), and the
/// setting names, defaults and caps are the spine's. The tests need no production (warm).
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
	Set ref = "zzbeatstub"_$Job_$ZHorolog
	Set before = ..Rows("")
	Do $$$AssertStatusOK($ClassMethod(..#BEAT, "RunDue", "2030-06-01T12:00:00Z"), "RunDue is OK")
	Do $$$AssertStatusOK($ClassMethod(..#BEAT, "RunNow", ref), "RunNow is OK")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "Snapshot", ref, "2030-06-01T12:00:00Z"), "", "Snapshot is empty")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "Key", "x"), "", "Key is empty")
	Do $$$AssertEquals(..Rows(ref), 0, "no HeartbeatBeat row is made for the fixture ref")
	Do $$$AssertEquals(..Rows(""), before, "and the table holds as many rows as before")
}

Method TestSettingNames()
{
	Set ref = "zzbeatname"
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "interval"), "person.zzbeatname.heartbeat.interval", "a known name gives its key")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "zz"), "", "an unknown name gives empty")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, ""), "", "so does an empty name")
	Do $$$AssertEquals($ClassMethod(..#BEAT, "SettingKey", ref, "on,interval"), "", "and a list of names")
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
}

/// The number of HeartbeatBeat rows of the session Ref, or of all sessions when ref is empty.
Method Rows(ref As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.HeartbeatBeat WHERE ? = '' OR SessionRef = ?", ref, ref)
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
