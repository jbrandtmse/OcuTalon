/// Tests of when the Digest item queues a digest (Story 17.6; AD-1, AD-5, AD-18, DW-649, DW-651). Safe on a slot: no production runs, the tests call OnRequest on
/// shadow instances of OcuTalon.Test.Digest.ProcessProbe, which saves each Compose it would send to itself and records it, and the process zone is
/// America/New_York. Every time is written as a local time and converted through Data.Time FromLocal. digest.time is 08:00 unless a test sets it.
///   - TestCreatedBefore (DW-651): a session created before today's digest.time gets one scheduled Compose at the tick after it, whose DueAt is that time,
///     and the next tick queues none;
///   - TestCreatedAfter (DW-651): a session created after today's time gets none today, however late the tick, and one at the first tick after tomorrow's time;
///   - TestCatchUpOnce: ticks that stopped across digest.time for two days give one Compose when they resume, for the latest time, and no later tick
///     repeats it, also after the digest is sent and its Compose body is gone;
///   - TestQueuedNotRepeated: a scheduled Compose that waits for its answer from Decide (no Sent row yet) keeps the next tick from queuing a second one;
///   - TestRequestedAndScheduled (DW-649): a SendDigest from web_admin answers Ok at once, queues a requested Compose with an empty DueAt, and the
///     scheduled digest of the same day is still queued, with a window that starts at the requested digest's SentAt;
///   - TestDaylightSaving: on the spring-forward and the fall-back day the due time is the one that FromLocal gives, and a tick before the time
///     is due for the day before;
///   - TestBadTime: a digest.time that is not a time of day means 08:00;
///   - TestLock: a second job that holds the lock of the session's digest keeps the tick from queuing a Compose, and the next tick queues it once the lock
///     is free;
///   - TestLockRecheck: a job that holds the lock writes a scheduled Sent row for the due time before it lets go: the tick that waited for the lock checks
///     again under it and queues nothing (the probe's record of the two checks shows the first found nothing and the second found the row);
///   - TestOnlineDemoSkipped (DW-874; AD-18 as amended 2026-11-07): on the online demo the scheduled run queues no Compose for any session, the one with a resume
///     hash (a visitor) and the one without (ended) alike, while on a local install both get one; a visitor's SendDigest (origin tool) on the online demo still
///     queues one requested Compose with an empty DueAt and is answered Ok and sending;
///   - TestTickResendsNothing (Story 21.7): the tick, on the online demo as on a local install, sends nothing for a Sent row that names a missed channel (a
///     row written before Notify became the one route): Digest has no direct send to a channel's item, so the row is left as it is.
Class OcuTalon.Test.Digest.Due Extends OcuTalon.Test.Bridge.ZoneCase
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
	Do ..SetTime("08:00")
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

Method SetTime(value As %String)
{
	Do ##class(OcuTalon.Data.Setting).Set("digest.time", value)
	Kill ^||OcuTalon.Setting("digest.time")
}

/// A fixture session created at the local time.
Method Session(createdLocal As %String, resumeHash As %String = "") As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzdue")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set row.CreatedAt = ##class(OcuTalon.Data.Time).FromLocal(createdLocal)
	Set row.ResumeHash = resumeHash
	Do $$$AssertStatusOK(row.%Save(), "the session is saved")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A shadow instance of the probe that works for the sessions.
Method Host(sessions As %String) As OcuTalon.Test.Digest.ProcessProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	Set host.Only = sessions
	Quit host
}

/// A Tick at the local time, handled by the host.
Method Tick(host As OcuTalon.Test.Digest.ProcessProbe, tickLocal As %String)
{
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = ##class(OcuTalon.Data.Time).FromLocal(tickLocal)
	Kill response
	Do $$$AssertStatusOK(host.OnRequest(tick, .response), "the tick of "_tickLocal_" is handled")
}

Method Utc(local As %String) As %String
{
	Quit ##class(OcuTalon.Data.Time).FromLocal(local)
}

Method TestCreatedBefore()
{
	Set ref = ..Session("2030-06-03T07:30:00")
	Set host = ..Host(ref)
	Do ..Tick(host, "2030-06-03T08:01:00")
	Set composes = $ClassMethod(..#PROBE, "Composes")
	Do $$$AssertEquals(composes.%Size(), 1, "one Compose is queued at the tick after digest.time")
	If composes.%Size() = 1 {
		Set compose = composes.%Get(0)
		Do $$$AssertEquals(compose.session_"|"_compose.kind_"|"_compose.dueAt_"|"_compose.key, ref_"|scheduled|"_..Utc("2030-06-03T08:00:00")_"|", "it is scheduled, due at today's 08:00, with no key")
		Do $$$AssertEquals(compose.windowStart, ##class(OcuTalon.Data.Time).AddSeconds(compose.windowEnd, -86400), "and its window is the 24 hours before it was queued")
	}
	Do ..Tick(host, "2030-06-03T08:02:00")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "compose"), 1, "the next tick queues none")
}

Method TestCreatedAfter()
{
	Set ref = ..Session("2030-06-03T08:30:00")
	Set host = ..Host(ref)
	Do ..Tick(host, "2030-06-03T08:31:00")
	Do ..Tick(host, "2030-06-03T15:00:00")
	Do ..Tick(host, "2030-06-03T23:59:00")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "compose"), 0, "a session created after today's time gets none today")
	Do ..Tick(host, "2030-06-04T08:01:00")
	Set composes = $ClassMethod(..#PROBE, "Composes")
	Do $$$AssertEquals(composes.%Size(), 1, "and one at the tick after tomorrow's time")
	If composes.%Size() = 1 Do $$$AssertEquals(composes.%Get(0).dueAt, ..Utc("2030-06-04T08:00:00"), "due at tomorrow's 08:00")
}

Method TestCatchUpOnce()
{
	Set ref = ..Session("2030-06-01T06:00:00")
	Set host = ..Host(ref)
	Do ..Tick(host, "2030-06-03T10:00:00")
	Set composes = $ClassMethod(..#PROBE, "Composes")
	Do $$$AssertEquals(composes.%Size(), 1, "ticks that resume after two days queue one Compose")
	If composes.%Size() = 1 Do $$$AssertEquals(composes.%Get(0).dueAt, ..Utc("2030-06-03T08:00:00"), "for the latest 08:00")
	Do ..Tick(host, "2030-06-03T10:01:00")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "compose"), 1, "no later tick repeats it")
	Do $$$AssertStatusOK(host.DeliverCompose(1), "the Compose is handled")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 1, "and one digest is sent")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Msg.Compose WHERE SessionRef = ?", ref)
	Do ..Tick(host, "2030-06-03T10:02:00")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "compose"), 1, "and the sent row alone keeps the next tick from queuing another")
	Do ..Tick(host, "2030-06-04T08:05:00")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "compose"), 2, "while the next day's time queues the next one")
}

Method TestQueuedNotRepeated()
{
	Set ref = ..Session("2030-06-03T07:30:00")
	Set host = ..Host(ref)
	Do ..Tick(host, "2030-06-03T08:01:00")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "compose"), 1, "the first tick queues a Compose")
	Do ..Tick(host, "2030-06-03T08:02:00")
	Do ..Tick(host, "2030-06-03T08:03:00")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "compose"), 1, "a Compose that is queued and not sent keeps the next ticks from queuing another")
	Set sent = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ?", ref)
	Do sent.%Next()
	Do $$$AssertEquals(sent.%GetData(1), 0, "and there is no Sent row yet")
}

Method TestRequestedAndScheduled()
{
	Set ref = ..Session("2030-06-03T06:00:00")
	Set host = ..Host(ref)
	Set command = ##class(OcuTalon.Msg.Command.SendDigest).%New()
	Set command.SessionRef = ref
	Set command.Origin = "web_admin"
	Kill response
	Do $$$AssertStatusOK(host.OnRequest(command, .response), "the SendDigest is handled")
	Do $$$AssertTrue($IsObject(response), "and answered")
	If $IsObject(response) Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Message, "1|sending|"_$Parameter(..#PROBE, "MESSAGESENDING"), "Ok at once, sending, with the fixed message")
	Set composes = $ClassMethod(..#PROBE, "Composes")
	Do $$$AssertEquals(composes.%Size(), 1, "one Compose is queued")
	If composes.%Size() = 1 Do $$$AssertEquals(composes.%Get(0).kind_"|"_composes.%Get(0).dueAt, "requested|", "requested, with an empty DueAt")
	Do $$$AssertStatusOK(host.DeliverCompose(1), "it is handled")
	Set newest = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 SentAt, Kind, DueAt FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ? ORDER BY SentAt DESC", ref)
	Do newest.%Next()
	Do $$$AssertEquals(newest.%Get("Kind")_"|"_newest.%Get("DueAt"), "requested|", "the Sent row is requested with an empty DueAt")
	Set sentAt = newest.%Get("SentAt")
	Do ..Tick(host, "2030-06-03T08:01:00")
	Set composes = $ClassMethod(..#PROBE, "Composes", 1)
	Do $$$AssertEquals(composes.%Size(), 1, "the scheduled digest of the day is still queued")
	If composes.%Size() = 1 {
		Do $$$AssertEquals(composes.%Get(0).kind_"|"_composes.%Get(0).dueAt, "scheduled|"_..Utc("2030-06-03T08:00:00"), "scheduled, due at 08:00")
		Do $$$AssertEquals(composes.%Get(0).windowStart, sentAt, "and its window starts at the SentAt of the requested digest")
	}
}

Method TestDaylightSaving()
{
	Do ..SetTime("02:30")
	Set ref = ..Session("2030-03-01T00:00:00")
	Set host = ..Host(ref)
	Do ..Tick(host, "2030-03-10T09:00:00")
	Set composes = $ClassMethod(..#PROBE, "Composes")
	Do $$$AssertEquals(composes.%Size(), 1, "on the spring-forward day a tick after the time queues a Compose")
	If composes.%Size() = 1 Do $$$AssertEquals(composes.%Get(0).dueAt, "2030-03-10T07:30:00Z", "due at 03:30 EDT, the hour that the zone skips read one hour later")
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#PROBE, "Clean", ref)
	Do $$$AssertEquals($ClassMethod("OcuTalon.Digest.Process", "DueFor", ..Utc("2030-03-10T01:00:00")), "2030-03-09T07:30:00Z", "a tick before the time is due for the day before: 02:30 EST is 07:30Z")
	Do ..SetTime("08:00")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Digest.Process", "DueFor", ..Utc("2030-11-03T07:00:00")), "2030-11-02T12:00:00Z", "on the fall-back day a tick at 07:00 is due for the day before: 08:00 EDT is 12:00Z, 25 hours earlier than the 08:00 EST of the day")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Digest.Process", "DueFor", ..Utc("2030-11-03T08:01:00")), "2030-11-03T13:00:00Z", "and one at 08:01 is due for the day: 08:00 EST is 13:00Z")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Digest.Process", "DueFor", ..Utc("2030-03-10T07:00:00")), "2030-03-09T13:00:00Z", "on the spring-forward day a tick at 07:00 is due for the day before: 08:00 EST is 13:00Z")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Digest.Process", "DueFor", ..Utc("2030-03-10T08:01:00")), "2030-03-10T12:00:00Z", "and one at 08:01 is due for the day: 08:00 EDT is 12:00Z, 23 hours later")
}

Method TestBadTime()
{
	For value = "25:00", "8:00", "abc", "07:61", "" {
		Do ..SetTime(value)
		Do $$$AssertEquals($ClassMethod("OcuTalon.Digest.Process", "ClockTime"), "08:00", "'"_value_"' means 08:00")
	}
	Do ..SetTime("07:45")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Digest.Process", "ClockTime"), "07:45", "a time of day is used")
}

Method TestLock()
{
	Set ref = ..Session("2030-06-03T07:30:00")
	Set host = ..Host(ref)
	Job ##class(OcuTalon.Test.Digest.ProcessProbe).Hold(ref, 4)::5
	Do $$$AssertTrue($Test, "the job that holds the lock starts")
	Set end = $ZHorolog + 5
	While '$ClassMethod(..#PROBE, "Held", ref) && ($ZHorolog < end) {
		Hang 0.1
	}
	Do $$$AssertTrue($ClassMethod(..#PROBE, "Held", ref), "the lock is held by the other job")
	Do ..Tick(host, "2030-06-03T08:01:00")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "compose"), 0, "a tick that cannot take the lock queues no Compose")
	Set end = $ZHorolog + 10
	While $ClassMethod(..#PROBE, "Held", ref) && ($ZHorolog < end) {
		Hang 0.2
	}
	Do $$$AssertTrue('$ClassMethod(..#PROBE, "Held", ref), "the other job lets go")
	Do ..Tick(host, "2030-06-03T08:02:00")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "compose"), 1, "and the next tick queues the Compose")
}

Method TestLockRecheck()
{
	Set ref = ..Session("2030-06-03T07:30:00")
	Set host = ..Host(ref)
	Job ##class(OcuTalon.Test.Digest.ProcessProbe).Hold(ref, 0.8, ..Utc("2030-06-03T08:00:00"))::5
	Do $$$AssertTrue($Test, "the job that holds the lock starts")
	Set end = $ZHorolog + 5
	While '$ClassMethod(..#PROBE, "Held", ref) && ($ZHorolog < end) {
		Hang 0.05
	}
	Do $$$AssertTrue($ClassMethod(..#PROBE, "Held", ref), "the lock is held by the other job")
	Do ..Tick(host, "2030-06-03T08:01:00")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "compose"), 0, "a tick that waits for the lock and finds the time covered when it has it queues no Compose")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Record", "covered", 1)_"|"_$ClassMethod(..#PROBE, "Record", "covered", 2)_"|"_$ClassMethod(..#PROBE, "Count", "covered"), "0|1|2", "the time was not covered before the lock and was under it: the check under the lock is what held the tick back")
	Set sent = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ? AND Kind = 'scheduled' AND DueAt = ?", ref, ..Utc("2030-06-03T08:00:00"))
	Do sent.%Next()
	Do $$$AssertEquals(sent.%GetData(1), 1, "the digest of the job that held the lock is the one for that time")
	Set end = $ZHorolog + 10
	While $ClassMethod(..#PROBE, "Held", ref) && ($ZHorolog < end) {
		Hang 0.2
	}
	Do $$$AssertTrue('$ClassMethod(..#PROBE, "Held", ref), "the other job lets go")
}

Method TestOnlineDemoSkipped()
{
	Set ended = ..Session("2030-06-03T07:30:00")
	Set visitor = ..Session("2030-06-03T07:30:00", ##class(OcuTalon.Bridge.Ids).NewRef())
	Set host = ..Host(ended_","_visitor)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..Tick(host, "2030-06-03T08:01:00")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "compose"), 0, "on the online demo the tick after digest.time queues no Compose, for a visitor or an ended session")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Do ..Tick(host, "2030-06-03T08:01:00")
	Set composes = $ClassMethod(..#PROBE, "Composes")
	Do $$$AssertEquals(composes.%Size(), 2, "on a local install both sessions get one")
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#PROBE, "Clean", ended_","_visitor)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set command = ##class(OcuTalon.Msg.Command.SendDigest).%New()
	Set command.SessionRef = visitor
	Set command.Origin = "tool"
	Kill response
	Do $$$AssertStatusOK(host.OnRequest(command, .response), "a visitor's SendDigest is handled on the online demo")
	Do $$$AssertTrue($IsObject(response), "and answered")
	If $IsObject(response) Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Message, "1|sending|"_$Parameter(..#PROBE, "MESSAGESENDING"), "Ok at once, sending, with the fixed message")
	Set composes = $ClassMethod(..#PROBE, "Composes")
	Do $$$AssertEquals(composes.%Size(), 1, "one Compose is queued")
	If composes.%Size() = 1 Do $$$AssertEquals(composes.%Get(0).session_"|"_composes.%Get(0).kind_"|"_composes.%Get(0).dueAt, visitor_"|requested|", "for the visitor, requested, with an empty DueAt")
}

Method TestTickResendsNothing()
{
	Set visitor = ..Session("2030-06-03T07:30:00", ##class(OcuTalon.Bridge.Ids).NewRef())
	Set host = ..Host(visitor)
	Set host.%SessionId = $Parameter(..#PROBE, "TRACESESSION")
	Set sent = ##class(OcuTalon.Digest.Data.Sent).%New()
	Set sent.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sent.SessionRef = visitor
	Set sent.Kind = "requested"
	Set sent.SentAt = ..Utc("2030-06-03T07:45:00")
	Set sent.CatalogKey = "checks.everythingElsePassed"
	Set sent.Slots = "{""parts"":[],""lines"":[]}"
	Set sent.Failed = "web"
	Set sent.Attempts = 0
	Do $$$AssertStatusOK(sent.%Save(), "a digest that missed the web channel is stored")
	Set id = sent.%Id()
	For online = 1, 0 {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", online)
		Do ..Tick(host, "2030-06-03T08:01:00")
		Set again = ##class(OcuTalon.Digest.Data.Sent).%OpenId(id)
		Do $$$AssertEquals($ClassMethod(..#PROBE, "Count", "notice"), 0, "online demo "_online_": no Notification is sent again")
		Do $$$AssertEquals(again.Channels_"|"_again.Failed_"|"_again.Attempts, "|web|0", "online demo "_online_": and the Sent row is left as it was")
	}
}

}
