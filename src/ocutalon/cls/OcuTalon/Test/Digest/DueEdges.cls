/// QA tests of the edges of the Digest item's due rule and of its second gate (Story 17.6; AD-1, AD-5, AD-18, DW-649, DW-651, Q5). Safe on a slot: no production
/// runs, the tests call OnRequest on shadow instances of OcuTalon.Test.Digest.ProcessProbe, and the process zone is America/New_York. Every time is written as a
/// local time and converted through Data.Time FromLocal. digest.time is 08:00 and digest.channels has no row while the class runs.
///   - TestTickAtTheDueTime: a tick at exactly digest.time is due for that day, and one a second earlier is due for the day before;
///   - TestCreatedAtTheDueTime (DW-651): a session created at exactly the due time gets no digest for it (the due time must be later than CreatedAt), while one
///     created a second earlier does;
///   - TestKeyHeldSendsNothing (Q5 (a)): a Compose whose IdempotencyKey a Sent row of the session holds ends OK with no Notification and no new Sent row, while a
///     Compose of another key goes;
///   - TestKeyHeldBySentRowQueuesNothing (Q5 (a)): a SendDigest whose IdempotencyKey only a Sent row of the session holds (no Compose body, as after the
///     message purge) is answered Ok and queues nothing, while one of a new key queues one Compose;
///   - TestScheduledCoveredSendsNothing (AD-18): a scheduled Compose whose DueAt a scheduled Sent row covers (equal or later) ends OK with no Notification and no
///     new Sent row, while one for a later due time goes.
Class OcuTalon.Test.Digest.DueEdges Extends OcuTalon.Test.Bridge.ZoneCase
{

Parameter PROBE = "OcuTalon.Test.Digest.ProcessProbe";

Parameter ZONE = "America/New_York";

/// The Refs of the fixture sessions of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The digest.time row before the class: $ListBuild(existed, value).
Property SavedTime As %List;

/// The onlineDemo key before the class.
Property SavedOnline As %String;

/// The digest.channels row before the class (ProcessProbe ForgetChannels).
Property ChannelsWas As %List;

Method OnBeforeAllTests() As %Status
{
	Set ..ChannelsWas = $ClassMethod(..#PROBE, "ForgetChannels")
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen("digest.time")
	Set ..SavedTime = $ListBuild($IsObject(row), $Select($IsObject(row): row.Value, 1: ""))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do $SYSTEM.Process.TimeZone(..#ZONE)
	Do $ClassMethod(..#PROBE, "Reset")
	Do ##class(OcuTalon.Data.Setting).Set("digest.time", "08:00")
	Kill ^||OcuTalon.Setting("digest.time")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do $ClassMethod(..#PROBE, "Clean", ..Refs)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Do $ClassMethod(..#PROBE, "Reset")
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Do $ClassMethod(..#PROBE, "PutChannelsBack", ..ChannelsWas)
	If $List(..SavedTime, 1) {
		Do ##class(OcuTalon.Data.Setting).Set("digest.time", $List(..SavedTime, 2))
	} Else {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen("digest.time")
		If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
	}
	Kill ^||OcuTalon.Setting("digest.time")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $$$OK
}

Method Utc(local As %String) As %String
{
	Quit ##class(OcuTalon.Data.Time).FromLocal(local)
}

/// A fixture session created at the local time.
Method Session(createdLocal As %String) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzedge")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set row.CreatedAt = ..Utc(createdLocal)
	Set row.ResumeHash = ""
	Do $$$AssertStatusOK(row.%Save(), "the session is saved")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A shadow instance of the probe whose own channels are web and whose Schedule works for the sessions.
Method Host(sessions As %String = "") As OcuTalon.Test.Digest.ProcessProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	Set host.Only = sessions
	Set host.OwnChannels = "web"
	Quit host
}

Method Tick(host As OcuTalon.Test.Digest.ProcessProbe, tickLocal As %String)
{
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = ..Utc(tickLocal)
	Kill response
	Do $$$AssertStatusOK(host.OnRequest(tick, .response), "the tick of "_tickLocal_" is handled")
}

/// A Sent row of the session: kind, due time and key as given.
Method SentRow(session As %String, kind As %String, dueAt As %String, key As %String)
{
	Set row = ##class(OcuTalon.Digest.Data.Sent).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = session
	Set row.Kind = kind
	Set row.DueAt = dueAt
	Set row.IdempotencyKey = key
	Set row.SentAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set row.WindowStart = ##class(OcuTalon.Data.Time).AddSeconds(row.SentAt, -86400)
	Set row.CatalogKey = "checks.nothingWatched"
	Set row.Slots = "{}"
	Do $$$AssertStatusOK(row.%Save(), "a "_kind_" Sent row is written")
}

Method SentRows(session As %String) As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ?", session)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// Handles a Compose of the session, with its window ending now, on a host; the status.
Method Handle(session As %String, kind As %String, dueAt As %String, key As %String) As %Status
{
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#PROBE, "Feed", [])
	Set host = ..Host()
	Set compose = ##class(OcuTalon.Digest.Msg.Compose).%New()
	Set compose.SessionRef = session
	Set compose.Kind = kind
	Set compose.DueAt = dueAt
	Set compose.IdempotencyKey = key
	Set compose.WindowEnd = ##class(OcuTalon.Data.Time).NowUtc()
	Set compose.WindowStart = ##class(OcuTalon.Data.Time).AddSeconds(compose.WindowEnd, -86400)
	Kill response
	Quit host.OnRequest(compose, .response)
}

Method TestTickAtTheDueTime()
{
	Do $$$AssertEquals($ClassMethod("OcuTalon.Digest.Process", "DueFor", ..Utc("2030-06-03T08:00:00")), ..Utc("2030-06-03T08:00:00"), "a tick at exactly 08:00 is due for that day")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Digest.Process", "DueFor", ..Utc("2030-06-03T07:59:59")), ..Utc("2030-06-02T08:00:00"), "and one a second earlier is due for the day before")
	Set ref = ..Session("2030-06-03T07:30:00")
	Set host = ..Host(ref)
	Do ..Tick(host, "2030-06-03T08:00:00")
	Set composes = $ClassMethod(..#PROBE, "Composes")
	Do $$$AssertEquals(composes.%Size(), 1, "a session created before it gets a Compose at the tick of exactly 08:00")
	If composes.%Size() = 1 Do $$$AssertEquals(composes.%Get(0).dueAt, ..Utc("2030-06-03T08:00:00"), "due at 08:00")
}

Method TestCreatedAtTheDueTime()
{
	Set atDue = ..Session("2030-06-03T08:00:00")
	Set before = ..Session("2030-06-03T07:59:59")
	Set host = ..Host(atDue_","_before)
	Do ..Tick(host, "2030-06-03T08:01:00")
	Set composes = $ClassMethod(..#PROBE, "Composes")
	Do $$$AssertEquals(composes.%Size(), 1, "one session is queued: the one created a second before the time")
	If composes.%Size() = 1 Do $$$AssertEquals(composes.%Get(0).session, before, "not the one created at exactly the time")
	Do ..Tick(host, "2030-06-04T08:01:00")
	Set composes = $ClassMethod(..#PROBE, "Composes", 1)
	Do $$$AssertEquals(composes.%Size(), 2, "tomorrow's tick queues both")
}

Method TestKeyHeldSendsNothing()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzedge")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Do ..SentRow(ref, "requested", "", "key-one")
	Do $$$AssertStatusOK(..Handle(ref, "requested", "", "key-one"), "a Compose whose key a Sent row holds is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 0, "it sends no Notification")
	Do $$$AssertEquals(..SentRows(ref), 1, "and writes no Sent row")
	Do $$$AssertStatusOK(..Handle(ref, "requested", "", "key-two"), "a Compose of another key is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 1, "it sends its digest")
	Do $$$AssertEquals(..SentRows(ref), 2, "and writes its Sent row")
}

Method TestKeyHeldBySentRowQueuesNothing()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzedge")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Do ..SentRow(ref, "requested", "", "key-sent")
	Set host = ..Host()
	For key = "key-sent", "key-new" {
		Set command = ##class(OcuTalon.Msg.Command.SendDigest).%New()
		Set command.SessionRef = ref
		Set command.IdempotencyKey = key
		Kill response
		Do $$$AssertStatusOK(host.OnRequest(command, .response), key_": the SendDigest is handled")
		Do $$$AssertEquals($Select($IsObject($Get(response)): response.Ok_"|"_response.Outcome, 1: ""), "1|sending", key_": it is answered Ok, sending")
	}
	Set composes = $ClassMethod(..#PROBE, "Composes")
	Do $$$AssertEquals(composes.%Size(), 1, "a key that only a Sent row holds (its Compose body purged) queues nothing; a new key queues one Compose")
	If composes.%Size() = 1 Do $$$AssertEquals(composes.%Get(0).key, "key-new", "the one of the new key")
}

Method TestScheduledCoveredSendsNothing()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzedge")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set due = ..Utc("2030-06-03T08:00:00")
	Do ..SentRow(ref, "scheduled", due, "")
	Do $$$AssertStatusOK(..Handle(ref, "scheduled", due, ""), "a scheduled Compose for the covered due time is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 0, "it sends no Notification")
	Do $$$AssertStatusOK(..Handle(ref, "scheduled", ##class(OcuTalon.Data.Time).AddSeconds(due, -86400), ""), "one for an earlier due time is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 0, "it sends none either")
	Do $$$AssertEquals(..SentRows(ref), 1, "and no Sent row is written")
	Do $$$AssertStatusOK(..Handle(ref, "scheduled", ##class(OcuTalon.Data.Time).AddSeconds(due, 86400), ""), "one for a later due time is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 1, "it sends its digest")
	Do $$$AssertEquals(..SentRows(ref), 2, "and writes its Sent row")
}

}
