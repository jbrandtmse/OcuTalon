/// Tests of the heartbeat command of OcuTalon.Core.SettingsOps (Story 39.2; AD-1, AD-17, AD-19, FR-63) over a shadow instance of
/// Test.Core.SettingsOpsProbe, which takes the audit entry through the WriteAudit seam instead of the real log. Safe on a slot: no production is
/// needed. The expected texts are written out here, never read from SettingsOps. The fixture sessions are made with Test.Data.Fixture; the public
/// setting onlineDemo is saved and put back; every per-person key of a fixture session, every fixture row and then the sessions' HeartbeatBeat rows (after the
/// sessions, so that no Tick makes one again) are removed in OnAfterAllTests.
///   - TestSaveAccepted, TestAllDay, TestAcceptedChecklists: an accepted SetHeartbeat answers saved, writes one audit entry and the five keys;
///   - TestBadOn, TestBadInterval, TestBadHours, TestBadChecklist: the refusals write and audit nothing;
///   - TestAuditNamesChangedKeysOnly, TestAuditFirstAndWithoutText, TestFixedStrings: the audit entry names only the changed keys, comes before
///     the keys, and never holds the checklist's text; every new string of the story is compared whole;
///   - TestNoSession, TestKeyWriteFails: no session and a failed key write change no key;
///   - TestHeartbeatRead: the read, with defaults, the online demo's sample, saved values, the row's view, another session's row and a row of a
///     Ref that differs only in case, and the cache;
///   - TestAppliesWithinSixtySeconds: Checks.Beat.Values reads the saved values at once in the writing process and after the cache window in another;
///   - TestPersonKeysAreGuarded: the guarded write accepts the five heartbeat keys of a 22-character Ref and nothing else of the family.
Class OcuTalon.Test.Core.SettingsHeartbeat Extends %UnitTest.TestCase
{

/// The probe, a subclass of the operation.
Parameter PROBE = "OcuTalon.Test.Core.SettingsOpsProbe";

/// The names of the five keys, in order.
Parameter NAMES = "on,interval,from,to,checklist";

/// The Refs of the fixture sessions of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Set ..Number = $Increment(^OcuTalonTest("SettingsHeartbeat", "n"))
	Set ..Refs = ""
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

/// Every test starts off the online demo, so a test that threw while the flag was set does not change the next one.
Method OnBeforeOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	For i = 1:1:$Length(..Refs, ",") {
		Set ref = $Piece(..Refs, ",", i)
		If ref '= "" Do ##class(OcuTalon.Core.SettingsOps).ForgetPerson(ref)
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	For i = 1:1:$Length(..Refs, ",") {
		Set ref = $Piece(..Refs, ",", i)
		If ref '= "" Do ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexDelete(ref)
	}
	Do ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexDelete(..CaseRef())
	Kill ^OcuTalonTest("SettingsOpsProbe")
	Quit $SYSTEM.Status.OK()
}

/// An accepted save: Ok 1, saved, the card's text and the values as JSON; the five keys hold them; one audit entry holds the setting heartbeat,
/// the changed keys from their old to their new form (the defaults are the old form of a person with no keys), the session's IRIS user, the
/// session and the channel web.
Method TestSaveAccepted()
{
	Do ..Reset()
	Set session = ..Session("accept")
	Set text = "a"_$Char(10)_"b"
	Set result = ..Send(session, "1", "60", "07:15", "21:45", text)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|saved", "Ok 1, saved")
	Do $$$AssertEquals(result.Message, "Saved. Applies within a minute. Recorded in the audit log.", "with the card's text")
	Do $$$AssertEquals(result.Data, "{""on"":1,""interval"":60,""from"":""07:15"",""to"":""21:45"",""checklist"":""a\nb""}", "and the saved values")
	Do $$$AssertEquals(..Keys(session), "1|60|07:15|21:45|"_text, "the five keys hold the values")
	Do $$$AssertEquals(..Audits(), 1, "one audit entry")
	Set data = ..AuditData(1)
	Do $$$AssertEquals(data.%ToJSON(), "{""setting"":""heartbeat"",""from"":""interval=30; from=08:00; to=20:00; checklist=0 characters"",""to"":""interval=60; from=07:15; to=21:45; checklist=3 characters"",""irisUser"":"""_..User("accept")_""",""sessionRef"":"""_session_""",""channel"":""web""}", "the entry has the one shape of its type")
	Set result = ..Send(session, "0", "60", "07:15", "21:45", text)
	Do $$$AssertEquals(result.Outcome, "saved", "a second save is saved")
	Do $$$AssertEquals(..Keys(session), "0|60|07:15|21:45|"_text, "and the keys hold the new values")
	Do $$$AssertEquals(..AuditData(2).from_"|"_..AuditData(2).to, "on=1|on=0", "its entry names the one key that changed")
}

/// Both hours empty is all day: it is accepted and both keys are stored empty (rows with an empty value), and the same hours twice are accepted
/// too (from equal to is all day for Checks).
Method TestAllDay()
{
	Do ..Reset()
	Set session = ..Session("allday")
	Set result = ..Send(session, "1", "30", "", "", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|saved", "Ok 1, saved")
	Do $$$AssertEquals(..Keys(session), "1|30|||", "all five keys exist; from, to and the checklist are empty")
	Do $$$AssertEquals(##class(OcuTalon.Checks.Beat).Values(session).from_"|"_##class(OcuTalon.Checks.Beat).Values(session).to, "|", "Checks.Beat.Values reads all day")
	Set result = ..Send(session, "1", "30", "08:00", "08:00", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|saved", "from equal to is accepted")
}

/// A checklist of emoji, with CRLF line breaks, of exactly 1,000 characters (also 998 letters and one emoji: 1,000 as $Length counts), or empty is
/// accepted and stored exactly.
Method TestAcceptedChecklists()
{
	Do ..Reset()
	Set session = ..Session("lists")
	Set emoji = "Check "_$Char(55357, 56842)_$Char(10)_"Be brief."
	Set crlf = "one"_$Char(13, 10)_"two"_$Char(13, 10)
	Set long = $Translate($Justify("", 1000), " ", "x")
	Set units = $Translate($Justify("", 998), " ", "x")_$Char(55357, 56842)
	Set texts = $ListBuild(emoji, crlf, long, units, "")
	For i = 1:1:$ListLength(texts) {
		Set result = ..Send(session, "1", "30", "", "", $List(texts, i))
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|saved", "checklist "_i_" is saved")
		Do $$$AssertEquals(..Key(session, "checklist"), $List(texts, i), "checklist "_i_" is stored exactly")
	}
	Do $$$AssertEquals($Length(long), 1000, "the long checklist has 1,000 characters")
}

/// Values for on other than "0" and "1" are refused with the generic text; nothing is written or audited.
Method TestBadOn()
{
	Do ..Reset()
	Set session = ..Session("badon")
	For on = "", "true", "2", "01", " 1", "1 ", "-1", "yes" {
		Set result = ..Send(session, on, "30", "", "", "")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|bad_on", "on '"_on_"': Ok 0, bad_on")
		Do $$$AssertEquals(result.Message, "Couldn't save. Nothing was changed.", "on '"_on_"': the generic text")
	}
	Do $$$AssertEquals(..KeyCount(session), 0, "no key is written")
	Do $$$AssertEquals(..Audits(), 0, "and nothing is audited")
}

/// An interval that is not one of 30, 60, 120, 240, 480 and 1440, or is not a canonical number, is refused with the generic text.
Method TestBadInterval()
{
	Do ..Reset()
	Set session = ..Session("badinterval")
	For interval = "15", "45", "2880", "", "0", "-30", "030", "30.0", "3e1", " 30", "30 ", "abc", "60,120" {
		Set result = ..Send(session, "1", interval, "", "", "")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|bad_interval", "interval '"_interval_"': Ok 0, bad_interval")
		Do $$$AssertEquals(result.Message, "Couldn't save. Nothing was changed.", "interval '"_interval_"': the generic text")
	}
	Do $$$AssertEquals(..KeyCount(session), 0, "no key is written")
	Do $$$AssertEquals(..Audits(), 0, "and nothing is audited")
	For interval = 30, 60, 120, 240, 480, 1440 {
		Set result = ..Send(session, "1", interval, "", "", "")
		Do $$$AssertEquals(result.Outcome, "saved", "interval "_interval_" is saved")
	}
}

/// Hours that are not both empty or both HH:MM on a quarter hour are refused with the generic text.
Method TestBadHours()
{
	Do ..Reset()
	Set session = ..Session("badhours")
	Set cases = $ListBuild($ListBuild("07:10", "20:00"), $ListBuild("08:00", "07:10"), $ListBuild("24:00", "20:00"), $ListBuild("08:00", "24:00"), $ListBuild("7:15", "20:00"), $ListBuild("08:00", "8:15"), $ListBuild("07:15", ""), $ListBuild("", "20:00"), $ListBuild("08:60", "20:00"), $ListBuild("08:00 ", "20:00"), $ListBuild("08:00", "20:00"_$Char(10)), $ListBuild("08.00", "20:00"), $ListBuild("08:00:00", "20:00"), $ListBuild("ab:cd", "ef:gh"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set result = ..Send(session, "1", "30", $List(case, 1), $List(case, 2), "")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|bad_hours", "hours '"_$List(case, 1)_"' to '"_$List(case, 2)_"': Ok 0, bad_hours")
		Do $$$AssertEquals(result.Message, "Couldn't save. Nothing was changed.", "hours '"_$List(case, 1)_"' to '"_$List(case, 2)_"': the generic text")
	}
	Do $$$AssertEquals(..KeyCount(session), 0, "no key is written")
	Do $$$AssertEquals(..Audits(), 0, "and nothing is audited")
	For hours = "00:00", "00:15", "07:30", "12:45", "23:45" {
		Set result = ..Send(session, "1", "30", hours, "23:00", "")
		Do $$$AssertEquals(result.Outcome, "saved", "from "_hours_" is saved")
	}
}

/// A checklist that is too long (also 999 letters and one emoji: 1,000 code points but 1,001 as $Length counts), holds {{ or @{ or holds a control
/// character other than a line break is refused with the card's text.
Method TestBadChecklist()
{
	Do ..Reset()
	Set session = ..Session("badlist")
	Set texts = $ListBuild($Translate($Justify("", 1001), " ", "x"), "a {{x}} b", "a @{env:X} b", "a"_$Char(9)_"b", "a"_$Char(7)_"b", "a"_$Char(127)_"b", "a"_$Char(133)_"b", "a"_$Char(0)_"b", $Translate($Justify("", 999), " ", "x")_$Char(55357, 56842))
	For i = 1:1:$ListLength(texts) {
		Set result = ..Send(session, "1", "30", "", "", $List(texts, i))
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|bad_checklist", "text "_i_": Ok 0, bad_checklist")
		Do $$$AssertEquals(result.Message, "Use up to 1,000 characters, without {{ or @{.", "text "_i_": the card's text")
	}
	Do $$$AssertEquals(..KeyCount(session), 0, "no key is written")
	Do $$$AssertEquals(..Audits(), 0, "and nothing is audited")
}

/// The entry's from and to name only the keys that changed, in the order on, interval, from, to, checklist; a save that changes nothing writes an
/// entry with both empty; the old form of a person with no keys is the default of the install, which is off on the online demo.
Method TestAuditNamesChangedKeysOnly()
{
	Do ..Reset()
	Set session = ..Session("changed")
	Set result = ..Send(session, "1", "30", "08:00", "20:00", "")
	Do $$$AssertEquals(result.Outcome, "saved", "the defaults are saved")
	Do $$$AssertEquals(..AuditData(1).from_"|"_..AuditData(1).to, "|", "nothing changed: both are empty")
	Set result = ..Send(session, "1", "30", "", "", "")
	Do $$$AssertEquals(..AuditData(2).from_"|"_..AuditData(2).to, "from=08:00; to=20:00|from=; to=", "all day: the hours are named, the new form is empty")
	Set result = ..Send(session, "0", "1440", "", "", "zz")
	Do $$$AssertEquals(..AuditData(3).from_"|"_..AuditData(3).to, "on=1; interval=30; checklist=0 characters|on=0; interval=1440; checklist=2 characters", "three keys, in order")
	Do ..Reset()
	Set other = ..Session("changeddemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set result = ..Send(other, "1", "30", "08:00", "20:00", "")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertEquals(result.Outcome, "saved", "a save on the online demo is saved")
	Do $$$AssertEquals(..AuditData(1).from_"|"_..AuditData(1).to, "on=0|on=1", "its old form is off")
}

/// The audit entry is written before the keys: when it can't be written no key is written, the answer is not_audited with the generic text and an
/// error is logged; a thrown audit write is an error answer. The entry's JSON never holds the checklist's text.
Method TestAuditFirstAndWithoutText()
{
	Do ..Reset()
	Set session = ..Session("auditfirst")
	Set text = "zzsecretchecklist {nothing}"
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "error"
	Set logged = ..Logged("The Settings audit entry could not be written", 2)
	Set result = ..Send(session, "0", "60", "09:00", "17:00", text)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "Ok 0, not_audited")
	Do $$$AssertEquals(result.Message, "Couldn't save. Nothing was changed.", "with the generic text")
	Do $$$AssertEquals(..KeyCount(session), 0, "no key is written")
	Do $$$AssertEquals(..Logged("The Settings audit entry could not be written", 2), logged + 1, "and one error is logged")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "audit") = "throw"
	Set result = ..Send(session, "0", "60", "09:00", "17:00", text)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "an audit write that throws: Ok 0, failed")
	Do $$$AssertEquals(..KeyCount(session), 0, "and no key is written")
	Kill ^OcuTalonTest("SettingsOpsProbe", "answer", "audit")
	Set result = ..Send(session, "0", "60", "09:00", "17:00", text)
	Do $$$AssertEquals(result.Outcome, "saved", "an accepted save is saved")
	Do $$$AssertEquals(..Audits(), 3, "the probe took the three attempts' entries")
	Set data = ..AuditData(3)
	Do $$$AssertEquals(data.%ToJSON() [ "zzsecretchecklist", 0, "the accepted entry holds no part of the checklist's text")
	Do $$$AssertEquals(data.to, "on=0; interval=60; from=09:00; to=17:00; checklist=27 characters", "it holds the checklist's length")
	Do $$$AssertEquals(..Key(session, "checklist"), text, "and the key holds the text")
}

/// Every new string of the story is compared whole: the saved sentence, the checklist refusal, the generic refusal, the online demo's sample and the
/// audit forms.
Method TestFixedStrings()
{
	Do $$$AssertEquals($Parameter("OcuTalon.Core.SettingsOps", "MESSAGEHEARTBEATSAVED"), "Saved. Applies within a minute. Recorded in the audit log.", "the saved sentence")
	Do $$$AssertEquals($Parameter("OcuTalon.Core.SettingsOps", "MESSAGEBADCHECKLIST"), "Use up to 1,000 characters, without {{ or @{.", "the checklist refusal")
	Do $$$AssertEquals($Parameter("OcuTalon.Core.SettingsOps", "MESSAGENOTSAVED"), "Couldn't save. Nothing was changed.", "the generic refusal")
	Do $$$AssertEquals(##class(OcuTalon.Core.SettingsOps).SampleChecklist(), "Tell me if an Orders incident is still open or waiting for my approval."_$Char(10)_"Remind me of anything due in the next hour."_$Char(10)_"Ignore everything else.", "the sample checklist: three lines")
	Set values = {"on": 1, "interval": 30, "from": "08:00", "to": "20:00", "checklist": ($Translate($Justify("", 120), " ", "x"))}
	Do $$$AssertEquals(##class(OcuTalon.Core.SettingsOps).HeartbeatAuditForm(values, $ListBuild("on", "interval", "from", "to", "checklist")), "on=1; interval=30; from=08:00; to=20:00; checklist=120 characters", "the audit form of five changed keys")
	Do $$$AssertEquals(##class(OcuTalon.Core.SettingsOps).HeartbeatAuditForm(values, $ListBuild("checklist", "on")), "on=1; checklist=120 characters", "the audit form of two keys is in key order")
	Do $$$AssertEquals(##class(OcuTalon.Core.SettingsOps).HeartbeatAuditForm(values, ""), "", "the audit form of no change is empty")
}

/// A command with no session, or a session with no row, is refused and nothing is written or audited.
Method TestNoSession()
{
	Do ..Reset()
	For session = "", ##class(OcuTalon.Bridge.Ids).NewRef() {
		Set result = ..Send(session, "1", "60", "", "", "zz")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|no_session", "session '"_session_"': Ok 0, no_session")
		Do $$$AssertEquals(result.Message, "Couldn't save. Nothing was changed.", "session '"_session_"': the generic text")
		Do $$$AssertEquals(..KeyCount(session), 0, "session '"_session_"': nothing is written")
	}
	Do $$$AssertEquals(..Audits(), 0, "and nothing is audited")
}

/// When the write of the second key fails the transaction is rolled back: the answer is failed with the generic text, an error is logged, and the keys
/// hold the values from before. The audit entry is written first, so the failed save leaves its entry.
Method TestKeyWriteFails()
{
	Do ..Reset()
	Set session = ..Session("keyfail")
	Set result = ..Send(session, "0", "60", "07:15", "21:45", "zz first")
	Do $$$AssertEquals(result.Outcome, "saved", "a heartbeat is saved first, off so that no Tick runs it")
	Set before = ..Keys(session)
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "apply") = "second"
	Kill ^OcuTalonTest("SettingsOpsProbe", "applies")
	Set logged = ..Logged("zz apply failed", 2)
	Set result = ..Send(session, "0", "120", "", "", "zz second")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "Ok 0, failed")
	Do $$$AssertEquals(result.Message, "Couldn't save. Nothing was changed.", "with the generic text")
	Do $$$AssertEquals(..Keys(session), before, "the first key was rolled back: the keys are as they were")
	Do $$$AssertEquals($TLevel, 0, "and no transaction is left open")
	Do $$$AssertEquals(..Logged("zz apply failed", 2), logged + 1, "and one error is logged")
	Do $$$AssertEquals(..Audits(), 2, "and the audit entry of the failed save was written before the keys")
}

/// The read: the install's defaults for a session with no keys (on, 30, 08:00 to 20:00, no checklist, no sample); the online demo's off, 30 and the
/// unsaved sample, with no key written; the saved values, read from the rows and never from the cache; the public view of the person's own
/// HeartbeatBeat row, with none of its private fields; no other session's row and no row of a Ref that differs only in case; an error status, with the
/// settings, when the row can't be read.
Method TestHeartbeatRead()
{
	Do ..Reset()
	Set session = ..Session("read")
	Set heartbeat = ##class(OcuTalon.Core.SettingsOps).Heartbeat(session, .sc)
	Do $$$AssertStatusOK(sc, "the read of a session with no keys has no error")
	Do $$$AssertEquals(heartbeat.%ToJSON(), "{""on"":true,""interval"":30,""from"":""08:00"",""to"":""20:00"",""checklist"":"""",""sample"":false}", "the defaults, with no member of a row")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set heartbeat = ##class(OcuTalon.Core.SettingsOps).Heartbeat(session, .sc)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertEquals(heartbeat.on_"|"_heartbeat.interval_"|"_heartbeat.from_"|"_heartbeat.to_"|"_heartbeat.sample, "0|30|08:00|20:00|1", "the online demo: off, 30 minutes, the sample")
	Do $$$AssertEquals(heartbeat.%GetTypeOf("on")_"|"_heartbeat.%GetTypeOf("sample"), "boolean|boolean", "on and sample are booleans")
	Do $$$AssertEquals(heartbeat.checklist, "Tell me if an Orders incident is still open or waiting for my approval."_$Char(10)_"Remind me of anything due in the next hour."_$Char(10)_"Ignore everything else.", "with the three-line sample")
	Do $$$AssertEquals(..KeyCount(session), 0, "and no key is written")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..Send(session, "1", "60", "", "", "")
	Set heartbeat = ##class(OcuTalon.Core.SettingsOps).Heartbeat(session, .sc)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do $$$AssertEquals(heartbeat.checklist_"|"_heartbeat.sample, "|0", "a saved empty checklist is not replaced by the sample")
	// The saved values, and the cache: another process's older entries do not show.
	Set text = "Look at Orders."_$Char(10)_"Be brief."
	Do ..Send(session, "0", "240", "06:30", "22:15", text)
	For name = "on", "interval", "from", "to", "checklist" {
		Set ^||OcuTalon.Setting(##class(OcuTalon.Checks.Beat).SettingKey(session, name)) = $ListBuild("zzstale", 1, $ZHorolog)
	}
	Set heartbeat = ##class(OcuTalon.Core.SettingsOps).Heartbeat(session, .sc)
	Do $$$AssertEquals(heartbeat.on_"|"_heartbeat.interval_"|"_heartbeat.from_"|"_heartbeat.to_"|"_heartbeat.checklist_"|"_heartbeat.sample, "0|240|06:30|22:15|"_text_"|0", "the saved values, read from the rows and not from the cache")
	// The row's public view.
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(session)
	If '$IsObject(row) {
		Set row = ##class(OcuTalon.Data.HeartbeatBeat).%New()
		Set row.SessionRef = session
	}
	Set row.NextDueAt = "2030-01-01T10:30:00Z"
	Set row.LastBeatAt = "2030-01-01T10:00:00Z"
	Set row.LastItemId = "zzItemIdPrivate"
	Set row.LastOutcome = "act"
	Set row.LastFallback = 1
	Set row.LastCostUSD = 0.0012
	Set row.LastDecisionRef = "zzDecisionRefPrivate"
	Set row.LastTraceSessionId = 77
	Set row.LastSkipAt = "2030-01-01T09:30:00Z"
	Set row.LastSkipReason = "hours"
	Set row.LastRunNowAt = "2030-01-01T09:45:00Z"
	Set row.BackoffUntil = "2030-01-01T14:00:00Z"
	Set row.LastSnapshotKey = "zzSnapshotKeyPrivate"
	Set row.LastQuietKey = "zzQuietKeyPrivate"
	Do $$$AssertStatusOK(row.%Save(), "the person's row is made")
	Set heartbeat = ##class(OcuTalon.Core.SettingsOps).Heartbeat(session, .sc)
	Do $$$AssertStatusOK(sc, "the read has no error")
	Set values = ##class(OcuTalon.Checks.Beat).Values(session)
	Set status = ##class(OcuTalon.Live.Payload.Heartbeat).FromRow(row, values).%JSONExportToString(.expectedJson)
	Do $$$AssertStatusOK(status, "control: the event's view of the row exports")
	Set expected = {}.%FromJSON(expectedJson)
	Set iterator = expected.%GetIterator()
	While iterator.%GetNext(.name, .value) {
		Do $$$AssertEquals(heartbeat.%Get(name), value, "the member "_name_" is the event's")
	}
	Do $$$AssertEquals(heartbeat.traceHeaderId_"|"_heartbeat.traceNamespace_"|"_heartbeat.lastFallback, "77|"_$Namespace_"|1", "the trace and the fallback flag")
	Set json = heartbeat.%ToJSON()
	For private = session, "zzItemIdPrivate", "zzDecisionRefPrivate", "zzSnapshotKeyPrivate", "zzQuietKeyPrivate" {
		Do $$$AssertEquals(json [ private, 0, "the answer does not hold '"_private_"'")
	}
	Do $$$AssertEquals(heartbeat.checklist_"|"_heartbeat.sample, text_"|0", "it holds the checklist and sample false")
	// Another session's row is not read.
	Set second = ..Session("readother")
	Set heartbeat = ##class(OcuTalon.Core.SettingsOps).Heartbeat(second, .sc)
	Do $$$AssertEquals(heartbeat.%IsDefined("lastBeatAt")_"|"_heartbeat.%IsDefined("traceHeaderId"), "0|0", "another session's row is not read")
	// A Ref that differs only in case is another Ref.
	Set mixed = ..CaseRef(), upper = $ZConvert(mixed, "U")
	Do $$$AssertTrue(mixed '= upper, "control: the two Refs differ in case")
	Set case = ##class(OcuTalon.Data.HeartbeatBeat).%New()
	Set case.SessionRef = upper
	Set case.LastOutcome = "act"
	Do $$$AssertStatusOK(case.%Save(), "a row of the upper-case Ref is made")
	Set found = ##class(OcuTalon.Data.Ownership).Heartbeat(mixed, .sc)
	Do $$$AssertEquals($IsObject(found), 0, "the mixed-case Ref reads no row of the upper-case Ref")
	Set found = ##class(OcuTalon.Data.Ownership).Heartbeat(upper, .sc)
	Do $$$AssertEquals($IsObject(found), 1, "and the exact Ref reads it")
	// A read that fails still returns the settings.
	Set heartbeat = ##class(OcuTalon.Core.SettingsOps).Heartbeat("", .sc)
	Do $$$AssertStatusNotOK(sc, "a read of no session has an error status")
	Do $$$AssertEquals(heartbeat.on_"|"_heartbeat.interval, "1|30", "and still returns the settings")
	Do ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexDelete(upper)
}

/// The saved values apply within 60 seconds: CACHESECONDS is 60, Checks.Beat.Values (the consumer) reads the new values at once in the writing
/// process, and in another process once its cache entry is 60 seconds old.
Method TestAppliesWithinSixtySeconds()
{
	Do ..Reset()
	Set session = ..Session("applies")
	Do $$$AssertEquals($Parameter("OcuTalon.Data.Setting", "CACHESECONDS"), 60, "the cache window is 60 seconds")
	Set values = ##class(OcuTalon.Checks.Beat).Values(session)
	Do $$$AssertEquals(values.interval_"|"_values.checklist, "30|", "Values reads the defaults first (and caches the misses)")
	Set result = ..Send(session, "0", "120", "09:00", "17:00", "zz applies")
	Do $$$AssertEquals(result.Outcome, "saved", "the heartbeat is saved, off so that no Tick runs it")
	Set values = ##class(OcuTalon.Checks.Beat).Values(session)
	Do $$$AssertEquals((+values.on)_"|"_values.interval_"|"_values.from_"|"_values.to_"|"_values.checklist, "0|120|09:00|17:00|zz applies", "the writing process reads the new values at once")
	Set key = ##class(OcuTalon.Checks.Beat).SettingKey(session, "interval")
	Set ^||OcuTalon.Setting(key) = $ListBuild("30", 1, $ZHorolog - 30)
	Do $$$AssertEquals(##class(OcuTalon.Checks.Beat).Values(session).interval, 30, "another process's entry that is 30 seconds old is still read")
	Set ^||OcuTalon.Setting(key) = $ListBuild("30", 1, $ZHorolog - 60)
	Do $$$AssertEquals(##class(OcuTalon.Checks.Beat).Values(session).interval, 120, "another process's entry that is 60 seconds old is read again")
}

/// The guarded write accepts the five heartbeat keys of a 22-character Ref and nothing else of the person.<ref> family.
Method TestPersonKeysAreGuarded()
{
	Do ..Reset()
	Set ref = ..Session("guard")
	Set probe = ..Probe()
	For name = "on", "interval", "from", "to", "checklist" {
		Do $$$AssertStatusOK(probe.Guarded("person."_ref_".heartbeat."_name, "zz"), "person.<ref>.heartbeat."_name_" is accepted")
	}
	Do $$$AssertEquals(..KeyCount(ref), 5, "and written")
	Do $$$AssertStatusOK(##class(OcuTalon.Core.SettingsOps).ForgetPerson(ref), "the keys are removed")
	Set refused = $ListBuild("person."_ref_".heartbeat.zz", "person."_ref_".heartbeat.", "person.short.heartbeat.on", "person."_ref_".heartbeat.on.x", "person."_ref_"heartbeat.on", "person.."_ref_".heartbeat.on", "person."_ref_"x.heartbeat.on", "heartbeat.on", "person."_$Extract(ref, 1, 21)_".heartbeat.on", "zz.key")
	For i = 1:1:$ListLength(refused) {
		Do $$$AssertStatusNotOK(probe.Guarded($List(refused, i), "zz"), "'"_$List(refused, i)_"' is refused")
	}
	Do $$$AssertEquals(..KeyCount(ref), 0, "and nothing is written")
}

/// --- helpers ---
/// Clears the probe's global.
Method Reset() [ Private ]
{
	Kill ^OcuTalonTest("SettingsOpsProbe")
}

/// A shadow instance of the probe.
Method Probe() As OcuTalon.Test.Core.SettingsOpsProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Quit probe
}

/// A Ref with lower-case letters, for the case test; it names no session.
ClassMethod CaseRef() As %String [ Private ]
{
	Quit "zzCaseHeartbeat0000aa"_"b"
}

/// The IRIS user of the fixture session of the name.
Method User(name As %String) As %String [ Private ]
{
	Quit "zzheartbeat"_..Number_name
}

/// A fixture session of the name, recorded for the clean-up. Returns its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session(..User(name))
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// Sends a SetHeartbeat with the values to the probe and returns its CommandResult.
Method Send(sessionRef As %String, on As %String, interval As %String, from As %String, to As %String, checklist As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SetHeartbeat).%New()
	Set command.Origin = "web_user"
	Set command.SessionRef = sessionRef
	Set command.On = on
	Set command.Interval = interval
	Set command.From = from
	Set command.To = to
	Set command.Checklist = checklist
	Set sc = ..Probe().OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

/// The number of audit entries the probe took.
Method Audits() As %Integer [ Private ]
{
	Set count = 0
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("SettingsOpsProbe", "calls", n))
		If n = "" Quit
		If ^OcuTalonTest("SettingsOpsProbe", "calls", n) = "audit" Set count = count + 1
	}
	Quit count
}

/// The data of the probe's nth audit entry.
Method AuditData(n As %Integer) As %DynamicObject [ Private ]
{
	Set count = 0
	Set call = ""
	For {
		Set call = $Order(^OcuTalonTest("SettingsOpsProbe", "calls", call))
		If call = "" Quit
		If ^OcuTalonTest("SettingsOpsProbe", "calls", call) '= "audit" Continue
		Set count = count + 1
		If count = n Quit
	}
	Quit {}.%FromJSON($Get(^OcuTalonTest("SettingsOpsProbe", "calls", call, "data"), "{}"))
}

/// The value of the session's heartbeat key of the name as its row holds it, "(none)" when there is no row.
ClassMethod Key(sessionRef As %String, name As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(##class(OcuTalon.Checks.Beat).SettingKey(sessionRef, name))
	Quit $Select($IsObject(row): row.Value, 1: "(none)")
}

/// The five heartbeat values of the session, as on|interval|from|to|checklist.
ClassMethod Keys(sessionRef As %String) As %String [ Private ]
{
	Quit ..Key(sessionRef, "on")_"|"_..Key(sessionRef, "interval")_"|"_..Key(sessionRef, "from")_"|"_..Key(sessionRef, "to")_"|"_..Key(sessionRef, "checklist")
}

/// The number of the session's heartbeat keys that have a row.
ClassMethod KeyCount(sessionRef As %String) As %Integer [ Private ]
{
	Set count = 0
	For i = 1:1:5 {
		If ##class(OcuTalon.Data.Setting).KeyIndexExists(##class(OcuTalon.Checks.Beat).SettingKey(sessionRef, $Piece(..#NAMES, ",", i))) Set count = count + 1
	}
	Quit count
}

/// The number of Event Log rows of the type (3 a warning, 2 an error) whose text contains the text.
ClassMethod Logged(text As %String, type As %Integer = 3) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Type = ? AND Text [ ?", type, text)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

}
