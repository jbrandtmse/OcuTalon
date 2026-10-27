/// Tests of Demo.Guide (Story 4.2; matrix rows 1 to 14; Story 4.7 adds the trace target, the run total and the variant rule; AD-12, AD-15): Compute derives the guide from the session's fixture rows
/// through Data.Ownership, with a fixed clock and the Telegram seam of Test.Demo.GuideProbe. The clock is 2030-01-01T12:00:00Z.
/// TestTelegramCountsAsOff and TestBlankEqualsCompute use the real Guide. Every session is a fixture session (zzguide<n>), removed after
/// its test (Fixture.Clean); demo.mode, onlineDemo and ^OcuTalonTest("TelegramIncluded") are saved before the tests and put back after them.
Class OcuTalon.Test.Demo.Guide Extends %UnitTest.TestCase
{

Parameter NS = "OCUORDERS";

Parameter PROD = "OcuTalon.Demo.Orders.Production";

/// The run's number.
Property Number As %Integer;

Property SavedModeFound As %Boolean;

Property SavedModeValue As %String(MAXLEN = 1000);

Property SavedModeUpdatedAt As %String(MAXLEN = 20);

Property SavedOnline As %String;

Property SavedTelegramDefined As %Boolean;

Property SavedTelegram As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("DemoGuide", "n"))
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set ..SavedModeFound = found, ..SavedModeValue = value, ..SavedModeUpdatedAt = updatedAt
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..SavedTelegramDefined = ''$Data(^OcuTalonTest("TelegramIncluded"), telegram)
	Set ..SavedTelegram = $Get(telegram)
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, ##class(OcuTalon.Data.Time).NowUtc())
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("GuideProbe")
	Set ^OcuTalonTest("GuideProbe", "now") = ..At(0)
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Kill ^OcuTalonTest("GuideProbe")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("GuideProbe")
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..SavedModeFound, ..SavedModeValue, ..SavedModeUpdatedAt)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	If ..SavedTelegramDefined {
		Set ^OcuTalonTest("TelegramIncluded") = ..SavedTelegram
	} Else {
		Kill ^OcuTalonTest("TelegramIncluded")
	}
	Quit $SYSTEM.Status.OK()
}

/// Row 1: a session with no rows is epoch 1, step 1, nothing done, Break the feed unavailable (not_watching) and unpaired; Blank
/// exports the same JSON.
Method TestBlank()
{
	Set ref = ..NewSession()
	Set view = ..View(ref)
	Do ..Assert(view, "blank", {"epoch": 1, "done": "00000", "step": 1, "finished": 0, "active": 0, "reason": "not_watching", "stage": "", "startedAt": "", "variant": "unpaired", "telegramRow": 0})
	Do ##class(OcuTalon.Test.Demo.GuideProbe).Compute(ref).%JSONExportToString(.computed)
	Do ##class(OcuTalon.Test.Demo.GuideProbe).Blank().%JSONExportToString(.blank)
	Do $$$AssertEquals(computed, blank, "Blank() exports the same JSON as Compute of a session with no rows")
	Do $$$AssertEquals(view.steps.%Size(), 5, "five steps")
	Set ^OcuTalonTest("GuideProbe", "telegram") = 1
	Do ##class(OcuTalon.Test.Demo.GuideProbe).Compute(ref).%JSONExportToString(.computed)
	Do ##class(OcuTalon.Test.Demo.GuideProbe).Blank().%JSONExportToString(.blank)
	Do $$$AssertEquals(computed, blank, "and with Telegram on, where the Telegram row shows: "_blank)
}

/// Row 1 with the real Guide: Blank() equals Compute of a fresh fixture session.
Method TestBlankEqualsCompute()
{
	Kill ^OcuTalonTest("GuideProbe")
	Set ref = ..NewSession()
	Do ##class(OcuTalon.Demo.Guide).Compute(ref).%JSONExportToString(.computed)
	Do ##class(OcuTalon.Demo.Guide).Blank().%JSONExportToString(.blank)
	Do $$$AssertEquals(computed, blank, "Blank() equals Compute of a fresh session")
}

/// Row 2: an Orders production check of the session (namespace in any case) is step 1 and makes Break the feed available; a check
/// of another production, of another namespace or of another session is not.
Method TestStepOne()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set a = ..NewSession()
	Set b = ..NewSession()
	Do $ClassMethod(fixture, "Check", a, "ocuorders", ..#PROD)
	Do ..Assert(..View(a), "an Orders check in lower case", {"done": "10000", "step": 2, "active": 1, "reason": ""})
	Do ..Assert(..View(b), "another session's check does not count", {"done": "00000", "active": 0, "reason": "not_watching"})
	Set c = ..NewSession()
	Do $ClassMethod(fixture, "Check", c, "OCUORDERS", "Zz.Other.Production")
	Do $ClassMethod(fixture, "Check", c, "ZZNS", ..#PROD)
	Do ..Assert(..View(c), "a check of another production or namespace does not count", {"done": "00000", "active": 0, "reason": "not_watching"})
}

/// Row 3: a pending or a fired reminder is step 2; a cancelled one alone, or another session's, is not.
Method TestStepTwo()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set a = ..NewSession()
	Set b = ..NewSession()
	Set c = ..NewSession()
	Set d = ..NewSession()
	Do $ClassMethod(fixture, "Reminder", a)
	Do $ClassMethod(fixture, "Reminder", b, , "fired")
	Do $ClassMethod(fixture, "Reminder", c, , "cancelled")
	Do ..Assert(..View(a), "a pending reminder", {"done": "01000"})
	Do ..Assert(..View(b), "a fired reminder", {"done": "01000"})
	Do ..Assert(..View(c), "a cancelled reminder alone", {"done": "00000"})
	Do ..Assert(..View(d), "another session's reminders", {"done": "00000"})
}

/// Row 4: a noticed Orders incident of the session at or after the window start is step 3; an unnoticed one, one on another
/// production, another session's, one noticed before the window and an instance one with onlineDemo 1 do not count. An instance
/// Orders incident counts on a local install while the session watches Orders.
Method TestStepThree()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set a = ..NewSession()
	Do $ClassMethod(fixture, "Check", a, ..#NS, ..#PROD)
	Do ..Assert(..View(a), "a watch and no incident", {"done": "10000"})
	Do $ClassMethod(fixture, "Incident", a, ..At(-10), ..#NS, ..#PROD)
	Do ..Assert(..View(a), "a noticed Orders incident", {"done": "10100", "step": 2})

	Set b = ..NewSession()
	Set other = ..NewSession()
	Do $ClassMethod(fixture, "Check", b, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "Incident", b, "", ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "Incident", b, ..At(-10), ..#NS, "Zz.Other.Production")
	Do $ClassMethod(fixture, "Incident", other, ..At(-10), ..#NS, ..#PROD)
	Do ..Assert(..View(b), "unnoticed, other production and other session's incidents", {"done": "10000"})

	Set c = ..NewSession()
	Do $ClassMethod(fixture, "Check", c, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "BreakFeedRun", c, "sent", ..At(-100))
	Do $ClassMethod(fixture, "Incident", c, ..At(-500), ..#NS, ..#PROD)
	Do ..Assert(..View(c), "an incident noticed before the run started", {"done": "10000"})

	Set d = ..NewSession()
	Do $ClassMethod(fixture, "Check", d, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "Incident", "instance", ..At(-10), ..#NS, ..#PROD)
	Do ..Assert(..View(d), "an instance Orders incident on a local install", {"done": "10100"})
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..Assert(..View(d), "an instance Orders incident with onlineDemo 1", {"done": "10000"})
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
}

/// Row 5: step 4 is done when the run incident has a request that is approved, rejected, executing, done or failed; requests that
/// are only pending, expired or cancelled leave it open.
Method TestStepFour()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	For state = "approved", "rejected", "executing", "done", "failed" {
		Set ref = ..IncidentSession()
		Set incident = ..IncidentOf(ref)
		Do $ClassMethod(fixture, "Approval", ref, incident, state)
		Do ..Assert(..View(ref), state_" request", {"done": "10110"})
	}
	For state = "pending", "expired", "cancelled" {
		Set ref = ..IncidentSession()
		Set incident = ..IncidentOf(ref)
		Do $ClassMethod(fixture, "Approval", ref, incident, state)
		Do ..Assert(..View(ref), state_" request", {"done": "10100"})
	}
}

/// Row 6: the trace-opened marker is step 5.
Method TestStepFive()
{
	Set ref = ..NewSession()
	Do ##class(OcuTalon.Test.Data.Fixture).GuideState(ref, 1, "", 1)
	Do ..Assert(..View(ref), "the trace marker", {"done": "00001", "epoch": 1, "step": 1})
}

/// Row 7: the variant is the run incident's rejected, fallback or no_fix; otherwise paired when Telegram is on and the session is
/// paired, else unpaired (none and expired alike). The real Guide gives unpaired with Telegram included and a pairing.
Method TestVariant()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	For variant = "rejected", "fallback", "no_fix" {
		Set ref = ..IncidentSession(variant)
		Do ..Assert(..View(ref), variant, {"variant": (variant)})
	}
	For variant = "fix", "expired", "" {
		Set ref = ..IncidentSession(variant)
		Do ..Assert(..View(ref), "open variant '"_variant_"' with Telegram off", {"variant": "unpaired"})
	}
	Set ^OcuTalonTest("GuideProbe", "telegram") = 1
	Set paired = ..IncidentSession("expired")
	Do $ClassMethod(fixture, "Pairing", paired)
	Set unpaired = ..IncidentSession("expired")
	Do ..Assert(..View(paired), "expired, Telegram on, paired", {"variant": "paired"})
	Do ..Assert(..View(unpaired), "expired, Telegram on, unpaired", {"variant": "unpaired"})
	Set rejected = ..IncidentSession("rejected")
	Do $ClassMethod(fixture, "Pairing", rejected)
	Do ..Assert(..View(rejected), "rejected wins over paired", {"variant": "rejected"})
}

/// Row 7 and 8 with the real Guide: Telegram counts as off until Story 10.3, so a pairing with Telegram included gives unpaired and
/// no Telegram row.
Method TestTelegramCountsAsOff()
{
	Kill ^OcuTalonTest("GuideProbe")
	Do ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(1)
	Set paired = ..IncidentSession("expired")
	Do ##class(OcuTalon.Test.Data.Fixture).Pairing(paired)
	Set view = ..Export(##class(OcuTalon.Demo.Guide).Compute(paired))
	Do $$$AssertEquals(view.step4Variant, "unpaired", "a paired session with Telegram included is unpaired")
	Set bare = ..NewSession()
	Set view = ..Export(##class(OcuTalon.Demo.Guide).Compute(bare))
	Do $$$AssertEquals(view.telegramRow, 0, "and the Telegram row is off")
}

/// Row 8: the Telegram row shows while Telegram is on, the session is unpaired and step 1 is not done.
Method TestTelegramRow()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ^OcuTalonTest("GuideProbe", "telegram") = 1
	Set bare = ..NewSession()
	Set paired = ..NewSession()
	Set watching = ..NewSession()
	Do $ClassMethod(fixture, "Pairing", paired)
	Do $ClassMethod(fixture, "Check", watching, ..#NS, ..#PROD)
	Do ..Assert(..View(bare), "unpaired, not watching", {"telegramRow": 1})
	Do ..Assert(..View(paired), "paired", {"telegramRow": 0})
	Do ..Assert(..View(watching), "watching", {"telegramRow": 0})
	Set ^OcuTalonTest("GuideProbe", "telegram") = 0
	Do ..Assert(..View(bare), "Telegram off", {"telegramRow": 0})
}

/// Row 9: finished needs step 5, an approved request and the incident resolved (or closed with no open variant); a rejection, a
/// fallback or a no-fix notice, a fixing incident, an incident closed after a rejection and a missing trace marker keep it open.
Method TestFinished()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set resolved = ..Finishing("resolved", "fix", "approved", 1)
	Do ..Assert(..View(resolved), "resolved with an approved fix and the trace", {"finished": 1, "done": "10111"})
	Set closed = ..Finishing("closed", "fix", "done", 1)
	Do ..Assert(..View(closed), "closed with no open variant", {"finished": 1})
	Set failed = ..Finishing("resolved", "fix", "failed", 1)
	Do ..Assert(..View(failed), "a failed fix that resolved", {"finished": 1})
	Do ..Assert(..View(..Finishing("resolved", "fix", "approved", 0)), "no trace marker", {"finished": 0, "done": "10110"})
	Do ..Assert(..View(..Finishing("resolved", "rejected", "rejected", 1)), "a rejection", {"finished": 0})
	Do ..Assert(..View(..Finishing("resolved", "fallback", "pending", 1)), "a fallback notice", {"finished": 0})
	Do ..Assert(..View(..Finishing("resolved", "no_fix", "pending", 1)), "a no-fix notice", {"finished": 0})
	Do ..Assert(..View(..Finishing("fixing", "fix", "executing", 1)), "while fixing", {"finished": 0})
	Do ..Assert(..View(..Finishing("closed", "rejected", "rejected", 1)), "closed after a rejection", {"finished": 0})
	Do ..Assert(..View(..Finishing("closed", "expired", "expired", 1)), "closed after an expiry", {"finished": 0})
	For variant = "rejected", "fallback", "no_fix", "expired" {
		Do ..Assert(..View(..Finishing("closed", variant, "done", 1)), "closed after "_variant_" with an approved fix", {"finished": 0})
	}
	Do ..Assert(..View(..Finishing("resolved", "fix", "pending", 1)), "no approved request", {"finished": 0})
}

/// Row 10: the step is the lowest step not done, 5 when all are done; after a rejection, a fallback or a no-fix notice a 5 becomes
/// 4, so that step 4 stays current.
Method TestCurrentStep()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ref = ..NewSession()
	Do ..Assert(..View(ref), "nothing done", {"step": 1})
	Do $ClassMethod(fixture, "Check", ref, ..#NS, ..#PROD)
	Do ..Assert(..View(ref), "step 1 done", {"step": 2})
	Do $ClassMethod(fixture, "Reminder", ref)
	Do ..Assert(..View(ref), "steps 1 and 2 done", {"step": 3})
	Set incident = $ClassMethod(fixture, "Incident", ref, ..At(-10), ..#NS, ..#PROD)
	Do ..Assert(..View(ref), "steps 1 to 3 done", {"step": 4})
	Do $ClassMethod(fixture, "Approval", ref, incident, "approved")
	Do ..Assert(..View(ref), "steps 1 to 4 done", {"step": 5})
	Do $ClassMethod(fixture, "GuideState", ref, 1, "", 1)
	Do ..Assert(..View(ref), "all done", {"step": 5, "done": "11111"})

	For variant = "rejected", "fallback", "no_fix" {
		Set clamped = ..Finishing("open", variant, "rejected", 1)
		Do $ClassMethod(fixture, "Reminder", clamped)
		Do ..Assert(..View(clamped), "all steps done after "_variant, {"step": 4, "done": "11111"})
	}
}

/// Row 11: Break the feed is unavailable (incident_in_progress) while the watched Orders incident is open (any variant),
/// awaiting approval or fixing, and available once it is resolved or closed.
Method TestBusyIncident()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	For state = "open", "awaiting_approval", "fixing" {
		For variant = "fix", "rejected" {
			Set ref = ..IncidentSession(variant, state)
			Do ..Assert(..View(ref), state_" with variant "_variant, {"active": 0, "reason": "incident_in_progress"})
		}
	}
	For state = "resolved", "closed" {
		Set ref = ..IncidentSession("fix", state)
		Do ..Assert(..View(ref), state_" incident", {"active": 1, "reason": ""})
	}
}

/// Row 12: the stages of the latest run (started at T0) with no Orders incident noticed since T0: waiting at 89 s, still_waiting at
/// 90 s and 179 s (both unavailable), no_notice at 180 s (available); sending at 10 s; notice_arrived with an incident; an unreadable
/// StartedAt counts as older than 180 s.
Method TestRunStages()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set cases = $ListBuild($ListBuild(89, "sent", "waiting", 0), $ListBuild(90, "sent", "still_waiting", 0), $ListBuild(179, "sent", "still_waiting", 0), $ListBuild(180, "sent", "no_notice", 1), $ListBuild(10, "sending", "sending", 0))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set ref = ..NewSession()
		Do $ClassMethod(fixture, "Check", ref, ..#NS, ..#PROD)
		Do $ClassMethod(fixture, "BreakFeedRun", ref, $List(case, 2), ..At(-$List(case, 1)))
		Set label = $List(case, 1)_" s, "_$List(case, 2)
		Do ..Assert(..View(ref), label, {"stage": ($List(case, 3)), "active": ($List(case, 4)), "reason": ($Select($List(case, 4): "", 1: "incident_in_progress")), "startedAt": (..At(-$List(case, 1)))})
	}
	Set noticed = ..NewSession()
	Do $ClassMethod(fixture, "Check", noticed, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "BreakFeedRun", noticed, "sent", ..At(-30))
	Do $ClassMethod(fixture, "Incident", noticed, ..At(-30), ..#NS, ..#PROD, {"State": "resolved"})
	Do ..Assert(..View(noticed), "a notice at the run start", {"stage": "notice_arrived", "startedAt": (..At(-30)), "active": 1})
	Set unreadable = ..NewSession()
	Do $ClassMethod(fixture, "Check", unreadable, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "BreakFeedRun", unreadable, "sent", "zz not a time")
	Do ..Assert(..View(unreadable), "an unreadable StartedAt", {"stage": "no_notice", "active": 1})
	Set none = ..NewSession()
	Do $ClassMethod(fixture, "Check", none, ..#NS, ..#PROD)
	Do ..Assert(..View(none), "no run", {"stage": "", "startedAt": "", "active": 1})
}

/// Row 13: after a resolved incident, a new run started after its notice leaves steps 3 and 4 open and the guide unfinished until a
/// new incident is noticed; step 5 keeps its marker.
Method TestSecondRun()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ref = ..Finishing("resolved", "fix", "approved", 1)
	Do ..Assert(..View(ref), "the first run is finished", {"finished": 1, "done": "10111"})
	Do $ClassMethod(fixture, "BreakFeedRun", ref, "sent", ..At(-5))
	Do ..Assert(..View(ref), "a second run without a notice", {"finished": 0, "done": "10001", "stage": "waiting"})
	Do $ClassMethod(fixture, "Incident", ref, ..At(-2), ..#NS, ..#PROD)
	Do ..Assert(..View(ref), "the new notice", {"done": "10101", "stage": "notice_arrived"})
}

/// Row 14: after Run again (epoch 2, RunStartedAt after the last notice) steps 3 to 5 are open, the watch and the reminder still
/// count and no stage is reported for a run from before the epoch; a 60 s old run still blocks (incident_in_progress) and stops
/// blocking from 180 s.
Method TestRunAgain()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ref = ..Finishing("resolved", "fix", "approved", 0, -900)
	Do $ClassMethod(fixture, "Reminder", ref)
	Do $ClassMethod(fixture, "BreakFeedRun", ref, "sent", ..At(-60))
	Do $ClassMethod(fixture, "GuideState", ref, 2, ..At(-30), 0)
	Do ..Assert(..View(ref), "run again", {"epoch": 2, "done": "11000", "finished": 0, "stage": "", "startedAt": "", "active": 0, "reason": "incident_in_progress", "step": 3})

	Set old = ..Finishing("resolved", "fix", "approved", 0, -900)
	Do $ClassMethod(fixture, "BreakFeedRun", old, "sent", ..At(-180))
	Do $ClassMethod(fixture, "GuideState", old, 2, ..At(-30), 0)
	Do ..Assert(..View(old), "run again with a 180 s old run", {"epoch": 2, "stage": "", "active": 1, "reason": ""})
}

/// Row 12, the stage precedence (QA): a notice outranks the 180 s wait and a batch still sending, and a batch still marked sending
/// stops blocking at 180 s like any other: sending at 100 s is sending (unavailable), sending at 200 s is no_notice (available),
/// a run 200 s old with a notice since its start is notice_arrived, and so is a run still sending with a notice.
Method TestStagePrecedence()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set sending = ..NewSession()
	Do $ClassMethod(fixture, "Check", sending, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "BreakFeedRun", sending, "sending", ..At(-100))
	Do ..Assert(..View(sending), "sending at 100 s", {"stage": "sending", "active": 0, "reason": "incident_in_progress"})
	Set stale = ..NewSession()
	Do $ClassMethod(fixture, "Check", stale, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "BreakFeedRun", stale, "sending", ..At(-200))
	Do ..Assert(..View(stale), "sending at 200 s", {"stage": "no_notice", "active": 1, "reason": ""})
	Set late = ..NewSession()
	Do $ClassMethod(fixture, "Check", late, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "BreakFeedRun", late, "sent", ..At(-200))
	Do $ClassMethod(fixture, "Incident", late, ..At(-150), ..#NS, ..#PROD, {"State": "resolved"})
	Do ..Assert(..View(late), "a notice in a run 200 s old", {"stage": "notice_arrived", "active": 1, "reason": "", "startedAt": (..At(-200))})
	Set early = ..NewSession()
	Do $ClassMethod(fixture, "Check", early, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "BreakFeedRun", early, "sending", ..At(-20))
	Do $ClassMethod(fixture, "Incident", early, ..At(-10), ..#NS, ..#PROD, {"State": "resolved"})
	Do ..Assert(..View(early), "a notice in a run still sending", {"stage": "notice_arrived", "active": 1})
}

/// Row 14 (QA): a run of the current epoch (it started after Run again) reports its stage and starts the window, so an incident
/// noticed after Run again but before the run does not count for steps 3 and 4, and one noticed since the run does.
Method TestRunInsideTheEpoch()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ref = ..NewSession()
	Do $ClassMethod(fixture, "Check", ref, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "GuideState", ref, 2, ..At(-60), 0)
	Do $ClassMethod(fixture, "BreakFeedRun", ref, "sent", ..At(-20))
	Do ..Assert(..View(ref), "a run after Run again", {"epoch": 2, "done": "10000", "stage": "waiting", "startedAt": (..At(-20)), "active": 0, "reason": "incident_in_progress"})
	Set before = $ClassMethod(fixture, "Incident", ref, ..At(-40), ..#NS, ..#PROD, {"State": "resolved"})
	Do $ClassMethod(fixture, "Approval", ref, before, "approved")
	Do ..Assert(..View(ref), "an incident noticed after Run again but before the run", {"done": "10000", "stage": "waiting", "finished": 0})
	Do $ClassMethod(fixture, "Incident", ref, ..At(-10), ..#NS, ..#PROD, {"State": "resolved"})
	Do ..Assert(..View(ref), "an incident noticed since the run", {"done": "10100", "stage": "notice_arrived", "active": 1})
}

/// Row 14 (QA): a notice that came after the latest run started, before Run again, ends that run's wait: Break the feed is
/// available at 60 s although steps 3 to 5 are open and no stage is reported.
Method TestRunAgainAfterTheNotice()
{
	Set ref = ..Finishing("resolved", "fix", "approved", 0, -50)
	Do ##class(OcuTalon.Test.Data.Fixture).BreakFeedRun(ref, "sent", ..At(-60))
	Do ##class(OcuTalon.Test.Data.Fixture).GuideState(ref, 2, ..At(-30), 0)
	Do ..Assert(..View(ref), "Run again after the run's notice", {"epoch": 2, "done": "10000", "stage": "", "startedAt": "", "active": 1, "reason": "", "finished": 0})
}

/// Rows 4, 5 and 11 (QA): an instance incident of the watched production, with its instance request, counts for the watching session
/// on a local install (steps 3 and 4 done, Break the feed busy while it is open) and for nobody with onlineDemo 1.
Method TestInstanceIncident()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ref = ..NewSession()
	Do $ClassMethod(fixture, "Check", ref, ..#NS, ..#PROD)
	Set incident = $ClassMethod(fixture, "Incident", "instance", ..At(-10), ..#NS, ..#PROD, {"State": "open"})
	Do $ClassMethod(fixture, "Approval", "instance", incident, "approved")
	Do ..Assert(..View(ref), "local install", {"done": "10110", "active": 0, "reason": "incident_in_progress"})
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..Assert(..View(ref), "onlineDemo 1", {"done": "10000", "active": 1, "reason": ""})
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
}

/// Story 4.7 row 10: trace is the trace session of the run's noticed incident ({TraceHeaderId, $Namespace}); it is absent with no
/// incident, for an incident noticed before the run, for an empty or 0 TraceHeaderId, and in a blank session's JSON.
Method TestTrace()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set none = ..NewSession()
	Do $ClassMethod(fixture, "Check", none, ..#NS, ..#PROD)
	Set view = ..View(none)
	Do $$$AssertEquals(view.%IsDefined("trace"), 0, "no incident: no trace")
	Do $$$AssertEquals(view.%IsDefined("run"), 0, "and no run")

	Set ref = ..NewSession()
	Do $ClassMethod(fixture, "Check", ref, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "Incident", ref, ..At(-10), ..#NS, ..#PROD, {"TraceHeaderId": 4321})
	Set view = ..View(ref)
	Do $$$AssertEquals(view.trace.traceHeaderId, 4321, "the run's incident: traceHeaderId")
	Do $$$AssertEquals(view.trace.traceNamespace, $Namespace, "and the current namespace")

	Set before = ..NewSession()
	Do $ClassMethod(fixture, "Check", before, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "BreakFeedRun", before, "sent", ..At(-100))
	Do $ClassMethod(fixture, "Incident", before, ..At(-500), ..#NS, ..#PROD, {"TraceHeaderId": 4321})
	Do $$$AssertEquals(..View(before).%IsDefined("trace"), 0, "an incident noticed before the run: no trace")

	Set empty = ..NewSession()
	Do $ClassMethod(fixture, "Check", empty, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "Incident", empty, ..At(-10), ..#NS, ..#PROD, {"TraceHeaderId": ""})
	Do $$$AssertEquals(..View(empty).%IsDefined("trace"), 0, "an empty TraceHeaderId: no trace")
	Set zero = ..NewSession()
	Do $ClassMethod(fixture, "Check", zero, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "Incident", zero, ..At(-10), ..#NS, ..#PROD, {"TraceHeaderId": 0})
	Do $$$AssertEquals(..View(zero).%IsDefined("trace"), 0, "a TraceHeaderId of 0: no trace")

	Set blank = ..NewSession()
	Do ##class(OcuTalon.Test.Demo.GuideProbe).Compute(blank).%JSONExportToString(.computed)
	Do ##class(OcuTalon.Test.Demo.GuideProbe).Blank().%JSONExportToString(.blankJson)
	Do $$$AssertEquals(computed, blankJson, "a blank session's JSON equals Blank()'s")
}

/// Story 4.7 row 11: run is the Ownership.RunCost total since RunStartedAt, present only while finished: decisions, input plus
/// output tokens, the cost and the models' display names. An empty RunStartedAt counts the whole session.
Method TestRunTotal()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set open = ..IncidentSession()
	Do $$$AssertEquals(..View(open).%IsDefined("run"), 0, "not finished: no run")

	Set ref = ..RunSession(..At(-300))
	Set view = ..View(ref)
	Do $$$AssertEquals(view.finished, 1, "finished")
	Do $$$AssertEquals(view.run.decisions, 2, "decisions since RunStartedAt")
	Do $$$AssertEquals(view.run.tokens, 9850, "input plus output tokens, the earlier row not counted")
	Do $$$AssertEquals(+view.run.costUSD, 0.0041, "cost")
	Do $$$AssertEquals(view.run.models.%Size(), 1, "one model")
	Do $$$AssertEquals(view.run.models.%Get(0), "Claude Haiku 5.5", "named by its display name")

	Set whole = ..RunSession("")
	Set view = ..View(whole)
	Do $$$AssertEquals(view.run.decisions, 3, "an empty RunStartedAt: every decision")
	Do $$$AssertEquals(view.run.tokens, 10350, "and every usage row")
}

/// Story 4.7 row 11 (QA): run.models lists the display names of the run's models in the order of their first use, once each, and
/// an id with no display name as it is; a row before RunStartedAt names no model.
Method TestRunTotalModels()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ref = ..RunSession(..At(-300))
	Set sonnet = $ClassMethod(fixture, "Decision", ref, "decide", ..At(-40))
	Do $ClassMethod(fixture, "Usage", sonnet, ref, {"InputTokens": 10, "OutputTokens": 5, "CostUSD": 0.0001, "Model": "claude-sonnet-5-5", "RecordedAt": (..At(-40))})
	Set again = $ClassMethod(fixture, "Decision", ref, "decide", ..At(-30))
	Do $ClassMethod(fixture, "Usage", again, ref, {"InputTokens": 10, "OutputTokens": 5, "CostUSD": 0.0001, "Model": "claude-haiku-5-5", "RecordedAt": (..At(-30))})
	Set other = $ClassMethod(fixture, "Decision", ref, "decide", ..At(-20))
	Do $ClassMethod(fixture, "Usage", other, ref, {"InputTokens": 10, "OutputTokens": 5, "CostUSD": 0.0001, "Model": "zz-model-9", "RecordedAt": (..At(-20))})
	Set earlier = $ClassMethod(fixture, "Decision", ref, "decide", ..At(-2000))
	Do $ClassMethod(fixture, "Usage", earlier, ref, {"InputTokens": 1, "OutputTokens": 1, "CostUSD": 0.0001, "Model": "zz-before", "RecordedAt": (..At(-2000))})
	Set view = ..View(ref)
	Do $$$AssertEquals(view.finished, 1, "finished")
	Do $$$AssertEquals(view.run.models.%ToJSON(), "[""Claude Haiku 5.5"",""Claude Sonnet 5.5"",""zz-model-9""]", "in the order of first use, each once, an unnamed id as it is, the earlier row's model not listed")
}

/// Story 4.7 row 12 (DW-215): the open variant counts only while the incident is open or closed. In another state step 4 shows
/// paired or unpaired, and finished never comes with a variant of VARIANTS or with step 4.
Method TestVariantFollowsState()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	For state = "resolved", "awaiting_approval", "fixing" {
		Do ..Assert(..View(..Finishing(state, "rejected", "pending", 0)), state_" with a stale rejected variant", {"variant": "unpaired"})
	}
	Set awaiting = ..Finishing("awaiting_approval", "rejected", "pending", 0)
	Do $ClassMethod(fixture, "Reminder", awaiting)
	Do ..Assert(..View(awaiting), "awaiting approval with the other steps done", {"variant": "unpaired", "step": 4, "finished": 0})

	Set resolved = ..Finishing("resolved", "rejected", "approved", 1)
	Do $ClassMethod(fixture, "Reminder", resolved)
	Do ..Assert(..View(resolved), "resolved with a stale variant, an approved fix and the trace", {"finished": 1, "step": 5, "variant": "unpaired"})

	Set closed = ..Finishing("closed", "rejected", "rejected", 1)
	Do $ClassMethod(fixture, "Reminder", closed)
	Do ..Assert(..View(closed), "closed after a rejection", {"variant": "rejected", "finished": 0, "step": 4, "done": "11111"})

	For state = "open", "awaiting_approval", "fixing", "resolved", "closed" {
		For variant = "fix", "rejected", "fallback", "no_fix", "expired" {
			For approval = "approved", "rejected", "pending" {
				Set ref = ..Finishing(state, variant, approval, 1)
				Do $ClassMethod(fixture, "Reminder", ref)
				Set view = ..View(ref)
				If view.finished {
					Do $$$AssertEquals($ListFind($ListFromString(##class(OcuTalon.Demo.Guide).#VARIANTS), view.step4Variant), 0, state_"/"_variant_"/"_approval_": finished has no variant")
					Do $$$AssertEquals(view.step, 5, state_"/"_variant_"/"_approval_": finished is step 5")
				}
			}
		}
	}
}

/// A finished session: a watch, a reminder, a resolved incident with a trace session, an approved fix and the trace marker, with
/// RunStartedAt runStartedAt; two decisions after 300 s before the clock (one with a usage row of 9000 input and 850 output tokens,
/// $0.0041, claude-haiku-5-5) and one decision with a usage row of 400 and 100 tokens, $0.0005, 1000 s before it.
Method RunSession(runStartedAt As %String) As %String [ Private ]
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ref = ..NewSession()
	Do $ClassMethod(fixture, "Check", ref, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "Reminder", ref)
	Set incident = $ClassMethod(fixture, "Incident", ref, ..At(-10), ..#NS, ..#PROD, {"State": "resolved", "TraceHeaderId": 4321})
	Do $ClassMethod(fixture, "Approval", ref, incident, "approved")
	Do $ClassMethod(fixture, "GuideState", ref, 1, runStartedAt, 1)
	Set first = $ClassMethod(fixture, "Decision", ref, "decide", ..At(-100))
	Do $ClassMethod(fixture, "Usage", first, ref, {"InputTokens": 9000, "OutputTokens": 850, "CostUSD": 0.0041, "RecordedAt": (..At(-100))})
	Do $ClassMethod(fixture, "Decision", ref, "decide", ..At(-50))
	Set early = $ClassMethod(fixture, "Decision", ref, "decide", ..At(-1000))
	Do $ClassMethod(fixture, "Usage", early, ref, {"InputTokens": 400, "OutputTokens": 100, "CostUSD": 0.0005, "RecordedAt": (..At(-1000))})
	Quit ref
}

/// A session with a watch, a noticed Orders incident (state, openVariant) and a request (approvalState, "pending" and so on); the
/// trace marker when trace is 1. Returns the session's Ref.
Method Finishing(state As %String, variant As %String, approvalState As %String, trace As %Boolean, noticed As %Integer = -10) As %String [ Private ]
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ref = ..IncidentSession(variant, state, noticed)
	Do $ClassMethod(fixture, "Approval", ref, ..IncidentOf(ref), approvalState)
	If trace Do $ClassMethod(fixture, "GuideState", ref, 1, "", 1)
	Quit ref
}

/// A session with an Orders watch and an Orders incident noticed that many seconds from the clock (10 s before it), with the open
/// variant and the state.
Method IncidentSession(variant As %String = "fix", state As %String = "open", noticed As %Integer = -10) As %String [ Private ]
{
	Set ref = ..NewSession()
	Do ##class(OcuTalon.Test.Data.Fixture).Check(ref, ..#NS, ..#PROD)
	Do ##class(OcuTalon.Test.Data.Fixture).Incident(ref, ..At(noticed), ..#NS, ..#PROD, {"State": (state), "OpenVariant": (variant)})
	Quit ref
}

/// The Ref of the session's newest Orders incident.
Method IncidentOf(ref As %String) As %String [ Private ]
{
	Set incident = ##class(OcuTalon.Data.Ownership).NewestIncident(ref, ..#NS, ..#PROD, "", .sc)
	Quit incident.Ref
}

/// A new fixture session, which Fixture.Clean removes.
Method NewSession() As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Session("zzguide"_..Number)
}

/// The view of the session through the probe, as an object of the exported JSON.
Method View(ref As %String) As %DynamicObject [ Private ]
{
	Quit ..Export(##class(OcuTalon.Test.Demo.GuideProbe).Compute(ref))
}

ClassMethod Export(payload As %RegisteredObject) As %DynamicObject [ Private ]
{
	Do payload.%JSONExportToString(.json)
	Quit ##class(%DynamicObject).%FromJSON(json)
}

/// Asserts each member of expected against the view: epoch (runEpoch), done (the five steps' flags as digits), step, finished,
/// active, reason, stage and startedAt (breakFeed), variant (step4Variant) and telegramRow.
Method Assert(view As %DynamicObject, label As %String, expected As %DynamicObject) [ Private ]
{
	Set done = ""
	For i = 0:1:view.steps.%Size() - 1 {
		Set done = done_$Select(view.steps.%Get(i).done: 1, 1: 0)
	}
	Set actual = {"epoch": (view.runEpoch), "done": (done), "step": (view.step), "finished": (''view.finished), "active": (''view.breakFeed.active), "reason": (view.breakFeed.reason), "stage": (view.breakFeed.stage), "startedAt": (view.breakFeed.startedAt), "variant": (view.step4Variant), "telegramRow": (''view.telegramRow)}
	Set iterator = expected.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		Do $$$AssertEquals(actual.%Get(key), value, label_": "_key)
	}
}

/// The UTC time that many seconds after the fixed clock, 2030-01-01T12:00:00Z.
ClassMethod At(offset As %Integer) As %String
{
	Set horolog = $ZDateTimeH("2030-01-01 12:00:00", 3, 1)
	Set seconds = $Piece(horolog, ",", 1) * 86400 + $Piece(horolog, ",", 2) + offset
	Quit $Translate($ZDateTime((seconds \ 86400)_","_(seconds # 86400), 3, 1), " ", "T")_"Z"
}

}
