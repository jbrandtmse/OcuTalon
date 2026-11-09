/// Changes the instance zone, the digest time and the digest channels on the running production and watches them apply, with no restart and
/// audited (Story 18.2; AD-17, AD-18, AD-19, AD-32; AC 1 to 4). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the running
/// OcuTalon.Production, and where that does not run every test fails with that reason (Test.Core.InProduction).
/// TestSavesApplyAtRunTime saves the three values the way the Settings page does (Commands.Submit, origin web_admin, one SaveSettings for Time zone and
/// one for Daily digest) and then, without restarting anything:
///   - a reminder Notification that is sent to the SimPhoneOut item (through a service, as Test.Core.RoutingProduction sends) gives a phone message whose
///     time is in the new zone, at once, because no setting of the zone is cached;
///   - after the 60 seconds that Data.Setting.Get may cache a value, a session whose CreatedAt is before the new due time and after the due time of the
///     values held before gets one scheduled digest, from the Ticks that the test sends through Checks: its DueAt is the new digest.time read in the new
///     zone, it went to web only, and its kind digest Delivery rows are on web only;
///   - a SendDigest that is submitted the way Api.SendDigest submits it (origin web_admin) gives one requested digest, again on web only;
///   - a digest Notification that is sent to the Notify item reaches the chosen channels the session has (web), not the phone that demo mode adds;
///   - three Settings entries (InstanceZone, digest.time and digest.channels) are read back from the IRIS audit log, and the start time of the
///     production is the one it had.
/// The session of the digest is made once the cache window has passed, so that no Tick of the production can schedule it under a value held before. The
/// run restores InstanceZone, digest.time, digest.channels, demo mode and the process zone as it found them; demo mode is turned on for the run through the
/// demo.mode row, whatever the stack has.
Class OcuTalon.Test.Core.SettingsRunTime Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzsettingsrt";

/// The seconds that Data.Setting.Get caches a value, plus one.
Parameter CACHEWINDOW = 61;

/// The seconds, from the saves, within which the scheduled digest must be sent.
Parameter WATCH = 75;

/// The seconds to wait for a message, a Delivery row or an audit entry.
Parameter WAIT = 20;

/// The key of the digest time and of the digest channels.
Parameter TIMEKEY = "digest.time";

Parameter CHANNELSKEY = "digest.channels";

/// The InstanceZone row of Decide before the run (ZoneCase ForgetZoneRow).
Property ZoneRow As %List;

/// The zone of the process before the run: -1 or "" for none (PutZone puts either back).
Property ProcessZone As %String;

/// The demo.mode row before the run.
Property DemoFound As %Boolean;

Property DemoValue As %String;

Property DemoUpdatedAt As %String;

/// The rows of digest.time and digest.channels before the run: $ListBuild(existed, value, updatedAt).
Property TimeRow As %List;

Property ChannelsRow As %List;

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	Set ..ProcessZone = ##class(OcuTalon.Test.Bridge.ZoneCase).CurrentZone()
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set ..DemoFound = found, ..DemoValue = value, ..DemoUpdatedAt = updatedAt
	Set ..TimeRow = ..RowOf(..#TIMEKEY)
	Set ..ChannelsRow = ..RowOf(..#CHANNELSKEY)
	Set ..ZoneRow = ##class(OcuTalon.Test.Bridge.ZoneCase).ForgetZoneRow()
	Kill ^||OcuTalon.Bridge.Time
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Bridge.ZoneCase).RestoreZoneRow(..ZoneRow)
	Kill ^||OcuTalon.Bridge.Time
	Do ##class(OcuTalon.Test.Bridge.ZoneCase).PutZone(..ProcessZone)
	If ..Missing = "" {
		Do ##class(OcuTalon.Test.Demo.Step).PutBack(..DemoFound, ..DemoValue, ..DemoUpdatedAt)
		Do ..PutRow(..#TIMEKEY, ..TimeRow)
		Do ..PutRow(..#CHANNELSKEY, ..ChannelsRow)
		Do $ClassMethod("OcuTalon.Test.Digest.ProcessProbe", "Clean", ..Sessions)
	}
	Quit ##super()
}

/// The row of the key as $ListBuild(existed, value, updatedAt).
Method RowOf(key As %String) As %List [ Private ]
{
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	Quit $Select($IsObject(row): $ListBuild(1, row.Value, row.UpdatedAt), 1: $ListBuild(0, "", ""))
}

/// Puts the row of the key back as RowOf found it (written again, or deleted), and drops this process's cache entry.
Method PutRow(key As %String, state As %List) [ Private ]
{
	Kill ^||OcuTalon.Setting(key)
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
	If '$List(state, 1) {
		If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
		Quit
	}
	If '$IsObject(row) {
		Set row = ##class(OcuTalon.Data.Setting).%New()
		Set row.Key = key
	}
	Set row.Value = $List(state, 2)
	Set row.UpdatedAt = $List(state, 3)
	Do row.%Save()
}

Method TestSavesApplyAtRunTime()
{
	If '..Guard() Quit
	Set time = "OcuTalon.Data.Time"
	Set started = $Get(^Ens.Runtime("StartTime"))
	Do $$$AssertTrue(started '= "", "control: the running production has a start time")

	// Demo mode is on for the run; the values held before are a digest time and channels that differ from the ones saved below.
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, ##class(OcuTalon.Data.Time).NowUtc())
	Set now0 = $ClassMethod(time, "NowUtc")
	Set oldOffset = $ClassMethod(time, "Seconds", $ClassMethod(time, "ToLocal", now0) _ "Z") - $ClassMethod(time, "Seconds", now0)
	Set baseline = $Extract($ClassMethod(time, "ToLocal", $ClassMethod(time, "AddSeconds", now0, -46800)), 12, 16)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set(..#TIMEKEY, baseline), "the digest time held before is " _ baseline)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set(..#CHANNELSKEY, "web,phone"), "the digest channels held before are web,phone")

	// The new values: a zone with a fixed offset that differs from the one in force and in which now is at least two hours into the local day (so that
	// the digest time, 2 hours before now, is on today's local date whatever the wall clock), and a digest time that is 2 hours before now in that zone.
	Set candidates = $ListBuild($ListBuild("Asia/Kolkata", 19800), $ListBuild("Asia/Kathmandu", 20700), $ListBuild("Asia/Tokyo", 32400), $ListBuild("Asia/Dubai", 14400), $ListBuild("America/Sao_Paulo", -10800), $ListBuild("Pacific/Honolulu", -36000))
	Set zone = "", offset = 0, position = 0
	While $ListNext(candidates, position, candidate) {
		If ($List(candidate, 2) '= oldOffset) && ((($ClassMethod(time, "Seconds", now0) + $List(candidate, 2)) # 86400) >= 7320) {
			Set zone = $List(candidate, 1), offset = $List(candidate, 2)
			Quit
		}
	}
	Do $$$AssertNotEquals(zone, "", "control: a zone is found in which now is at least two hours into the local day")
	If zone = "" Quit
	Set dueNew = $Extract($ClassMethod(time, "AddSeconds", now0, -7200), 1, 17) _ "00Z"
	Set newTime = $Extract($ClassMethod(time, "AddSeconds", dueNew, offset), 12, 16)
	Set backdated = $ClassMethod(time, "AddSeconds", dueNew, -60)
	Do $$$AssertNotEquals(newTime, baseline, "the new digest time differs from the one held before")

	Set admin = ..Session("admin")
	Set since = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set zoneSaved = ..Save(admin, "time-zone", {"InstanceZone": (zone)})
	Set digestSaved = ..Save(admin, "daily-digest", {"time": (newTime), "channels": "web"})
	Set start = $ZHorolog
	Do $$$AssertEquals(zoneSaved _ digestSaved, "11", "the two saves are accepted")
	Do $$$AssertEquals($Get(^Ens.Runtime("StartTime")), started, "no restart: the start time of the production is the same after the saves")

	// The zone reaches a production job at once.
	Set slotTime = $ClassMethod(time, "NowUtc")
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = admin
	Set notification.Kind = "reminder"
	Set notification.CatalogKey = "reminder.late"
	Set notification.Slots = {"time": (slotTime), "text": "zz settings run time"}.%ToJSON()
	Do $$$AssertStatusOK(..SendTo("SimPhoneOut", notification, admin), "the reminder is sent to SimPhoneOut")
	Set expected = "Reminder (late; it was due at " _ $Extract($ClassMethod(time, "AddSeconds", slotTime, offset), 12, 16) _ "): zz settings run time."
	Do $$$AssertEquals(..WaitPhoneText(admin), expected, "the phone message shows the time in " _ zone)
	Do $$$AssertEquals($ClassMethod(time, "Zone"), zone, "Data.Time.Zone() of this process names the saved zone")
	Do $$$AssertEquals($ClassMethod(time, "ToLocal", "2026-01-15T12:00:00Z"), $Translate($ClassMethod(time, "AddSeconds", "2026-01-15T12:00:00Z", offset), "Z"), "and its ToLocal converts in it")

	Do ..HangUntil(start + ..#CACHEWINDOW)

	// The scheduled digest of a session that is due under the new values and not under the values held before.
	Set session = ..Session("digest")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Set row.CreatedAt = backdated
	Do $$$AssertStatusOK(row.%Save(), "the session of the digest is backdated to " _ backdated)
	Set row = ""
	Set sent = ..TickUntilSent(session, 1, start + ..#WATCH)
	Do $$$AssertTrue(sent >= 1, "a scheduled digest is sent within " _ ..#WATCH _ " seconds of the saves: " _ ($ZHorolog - start) _ " seconds")
	Do $$$AssertEquals(..SentCount(session), 1, "one digest is sent")
	Set digestRow = ..SentRow(session)
	Do $$$AssertEquals($Select($IsObject(digestRow): digestRow.kind_"|"_digestRow.dueAt_"|"_digestRow.channels, 1: "none"), "scheduled|" _ dueNew _ "|web", "it is the scheduled digest, due at the new digest.time (" _ newTime _ " in " _ zone _ "), and went to web")
	Do $$$AssertEquals($Select($IsObject(digestRow): $Extract($ClassMethod(time, "AddSeconds", digestRow.dueAt, offset), 12, 19), 1: ""), newTime _ ":00", "whose clock in " _ zone _ " reads the new digest.time")
	Do $$$AssertEquals(..WaitDelivered(session, "web=1"), "web=1", "its kind digest Delivery rows are on web only, with none on phone")

	// A SendDigest, submitted the way Api.SendDigest submits it.
	Set command = ##class(OcuTalon.Msg.Command.SendDigest).%New()
	Set command.SessionRef = session
	Set command.IdempotencyKey = "web-digest-" _ $SYSTEM.Util.CreateGUID()
	Do $$$AssertStatusOK(##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result), "the SendDigest is submitted with origin web_admin")
	Do $$$AssertEquals($Select($IsObject($Get(result)): result.Ok_"|"_result.Outcome, 1: "none"), "1|sending", "and answered sending")
	Do $$$AssertEquals(..WaitSentCount(session, 2), 2, "it gives one requested digest after the scheduled one")
	Set digestRow = ..SentRow(session)
	Do $$$AssertEquals($Select($IsObject(digestRow): digestRow.kind_"|"_digestRow.channels, 1: "none"), "requested|web", "the newest is the requested one, sent to web")
	Do $$$AssertEquals(..WaitDelivered(session, "web=2"), "web=2", "its kind digest Delivery rows are on web only again")

	// A digest Notification sent to Notify, once the cache window has passed, reaches the chosen channel the session has, not the phone.
	Set digest = ##class(OcuTalon.Msg.Notification).%New()
	Set digest.SessionRef = admin
	Set digest.Kind = "digest"
	Set digest.CatalogKey = "checks.nothingWatched"
	Set digest.Slots = {"parts": [], "lines": [], "rows": []}.%ToJSON()
	Do $$$AssertStatusOK(..SendTo("Notify", digest, admin), "a digest is sent to Notify")
	Do $$$AssertEquals(..WaitDelivered(admin, "web=1"), "web=1", "its kind digest Delivery rows are on web only, with none on phone")

	// The audit log.
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(since, "OcuTalon", "Settings", "", admin, "", 3, ..#WAIT)
	Set seen = ""
	For i = 0:1:entries.%Size() - 1 {
		Set data = entries.%Get(i).data
		If $IsObject(data) Set seen(data.setting) = data.to
	}
	Do $$$AssertEquals($Get(seen("InstanceZone")) _ "|" _ $Get(seen("digest.time")) _ "|" _ $Get(seen("digest.channels")), zone _ "|" _ newTime _ "|web", "three Settings entries are read back from the audit log, with the saved values")
	Do $$$AssertEquals($Get(^Ens.Runtime("StartTime")), started, "no restart: the start time of the production is unchanged at the end")
}

/// Submits a SaveSettings of the section the way Api.SaveSection does (origin web_admin); 1 for an accepted save, else 0.
Method Save(session As %String, slug As %String, changes As %DynamicObject) As %Boolean [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = slug
	Set command.Changes = changes.%ToJSON()
	Set command.ActingUser = $Username
	Set command.SessionRef = session
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
	Do $$$AssertStatusOK(sc, slug _ " is submitted with origin web_admin")
	Set ok = $SYSTEM.Status.IsOK(sc) && $IsObject($Get(result)) && result.Ok
	If 'ok Do $$$AssertTrue(0, slug _ " was refused: " _ $Select($IsObject($Get(result)): result.Outcome _ " " _ result.Data, 1: "no result"))
	Quit ok
}

/// Sends the message to the item from a SimMailboxIn host, created in this process with the session's TraceRef as its SuperSession.
Method SendTo(target As %String, message As %Library.Persistent, session As %String) As %Status [ Private ]
{
	Set sc = ##class(Ens.Director).CreateBusinessService("SimMailboxIn", .service)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set service.%SuperSession = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Quit service.SendRequestAsync(target, message)
}

/// The text of the session's newest phone message once there is one, after WAIT seconds "".
Method WaitPhoneText(session As %String) As %String [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	Set text = ""
	For {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Text FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = 'phone' AND Direction = 'out' ORDER BY ID DESC", session)
		If rs.%Next() Set text = rs.%Get("Text")
		If (text '= "") || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit text
}

/// The kind digest Delivery rows of the session by channel, as channel=count joined by commas in channel order, once they equal wanted or after WAIT
/// seconds (then as they are). A short pause at the end lets a row on a channel that should have none appear.
Method WaitDelivered(session As %String, wanted As %String) As %String [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set found = ..Delivered(session)
		If (found = wanted) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Hang 2
	Quit ..Delivered(session)
}

Method Delivered(session As %String) As %String [ Private ]
{
	Set text = ""
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Channel, COUNT(*) AS N FROM OcuTalon_Data.Delivery WHERE OwnerRef = ? AND Kind = 'digest' GROUP BY Channel ORDER BY Channel", session)
	While rs.%Next() {
		Set text = text _ $Select(text = "": "", 1: ",") _ $ZConvert(rs.%Get("Channel"), "L") _ "=" _ rs.%Get("N")
	}
	Quit text
}

/// Hangs until $ZHorolog reaches the mark.
Method HangUntil(mark As %Numeric) [ Private ]
{
	For {
		Set left = mark - $ZHorolog
		If left <= 0 Quit
		Hang $Select(left > 5: 5, 1: left)
	}
}

/// Sends a Tick through Checks every 2 seconds until the session has count Sent rows or $ZHorolog reaches the deadline; the number of rows.
Method TickUntilSent(session As %String, count As %Integer, deadline As %Numeric) As %Integer [ Private ]
{
	For {
		Set tick = ##class(OcuTalon.Msg.Tick).%New()
		Set tick.TickAt = ##class(OcuTalon.Data.Time).NowUtc()
		Do $ClassMethod("OcuTalon.Test.Agent.RunnerFixture", "Send", "Checks", tick, .response)
		Set found = ..SentCount(session)
		If (found >= count) || ($ZHorolog > deadline) Quit
		Hang 2
	}
	Quit found
}

Method SentCount(session As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ?", session)
	Do rs.%Next()
	Quit rs.%GetData(1)
}

/// The count of Sent rows once it reaches count, or after WAIT seconds.
Method WaitSentCount(session As %String, count As %Integer) As %Integer [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set found = ..SentCount(session)
		If (found >= count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
}

/// The newest Sent row of the session, as {kind, dueAt, channels}, or "".
Method SentRow(session As %String) As %DynamicObject [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Kind, DueAt, Channels FROM OcuTalon_Digest_Data.Sent WHERE SessionRef = ? ORDER BY SentAt DESC, ID DESC", session)
	If 'rs.%Next() Quit ""
	Quit {"kind": (rs.%Get("Kind")), "dueAt": (rs.%Get("DueAt")), "channels": (rs.%Get("Channels"))}
}

}
