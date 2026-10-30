/// Tests of Core.Allowance, the online demo's message and email limits (Story 16.9; AD-20, FR-40). They use fixture sessions and set
/// the instance-wide public settings onlineDemo and messageAllowance for their run, which OnAfterAllTests puts back, so they run in a
/// throwaway stack (the CI shards, the warm stack), never on a slot. The window arithmetic is
/// shown with seeded AllowanceTimes (entries a known number of seconds old), so no test waits for an hour.
///   - TestAllowedUnderTheLimit: rows 1 and 3 of the matrix: below the limit a call returns 1, "" and 0 and appends now, oldest first;
///   - TestTheFiftyFirstIsRefused: the 51st message is refused with retryAt (the oldest entry plus 3600 s) and the first-refusal flag,
///     AllowanceUntil is that retryAt, the refused Turn is recorded (state refused, the channel, the text, no ClientId, no decision), it
///     is not queued and not in RecentTurns, a second refusal of the window has the same retryAt, no flag and another Turn;
///   - TestMixedChannelsCountTogether: web, guide and telegram calls are one count;
///   - TestTelegramFixtureIsRefusedTheSameWay (AC 2): a telegram call at the limit is refused with the telegram Turn and the flag;
///   - TestNewWindow: after the oldest entry has left the window a message is allowed, and the next refusal is a first refusal again;
///   - TestFlagOffAllowsAndWritesNothing, TestNoRowAllowsAndRecordsNothing, TestBusyLockRefusesWithNoRetryAt, TestFailedSaveRollsBack:
///     rows 6, 7 and 8;
///   - TestRefundGivesBackTheNewestEntry: row 9, with the row's lock free afterwards;
///   - TestLimitReadsThePublicSetting, TestUntil, TestNotices: the settings reading, the end of a window and the two notifications;
///   - TestTimeReadsForms: the forms and the refusals of Observe.TimeReads, which the card tests rely on;
///   - TestNoticeOnAnotherDay: a retryAt on another day reads "on <day> at HH:MM ET", the form that the card tests accept beside the clock alone;
///   - TestMailAllowed: the email limit at 19, 20 and 21, outgoing rows and old rows ignored, the flag off;
///   - TestConversationNamesNoAllowance: Conversation never refers to the allowance, by its full or its short name, or to TryConsume
///     (AD-20);
///   - QA (Story 16.9): TestMailAllowedFailedReadIsNotAnAllowance (a count that cannot be read is an error and 0, never an allowance),
///     TestNoticeCarriesTheConfiguredLimit (the notice's limit is the setting's value) and TestOnlyTheNewestEntriesCountWhenTheLimitDrops
///     (a lowered limit keeps the newest entries, so retryAt is not the oldest entry's).
/// The run's number is n from ^OcuTalonTest("Allowance","n") (never reset); the fixture sessions are Test.Data.Fixture's, with the turns
/// that TryConsume recorded adopted for the clean-up.
Class OcuTalon.Test.Core.Allowance Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture sessions of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The public settings before the tests, as onlineDemo|messageAllowance; each "" when it was absent.
Property Saved As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("Allowance", "n"))
	Set ..Refs = ""
	Set ..Saved = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")_"|"_##class(OcuTalon.Data.Public.Settings).Get("messageAllowance")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ##class(OcuTalon.Data.Public.Settings).Set("messageAllowance", "")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", $Piece(..Saved, "|", 1))
	Do ##class(OcuTalon.Data.Public.Settings).Set("messageAllowance", $Piece(..Saved, "|", 2))
	If ..Refs '= "" {
		Set all = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Refs, ..Refs)
		Do ##class(OcuTalon.Test.Data.Fixture).Clean(all)
	}
	Kill ^OcuTalonTest("Allowance", "job")
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ##class(OcuTalon.Data.Public.Settings).Set("messageAllowance", "")
	Quit $SYSTEM.Status.OK()
}

/// Rows 1 and 3: below the limit a call allows the message, with an empty retryAt and no first refusal, and appends now to the
/// session's AllowanceTimes, oldest first, in UTC to the second; no Turn is recorded.
Method TestAllowedUnderTheLimit()
{
	Set ref = ..Session("allowed")
	For i = 1:1:5 {
		Set retryAt = "zz", first = "zz"
		Set before = ##class(OcuTalon.Data.Time).NowUtc()
		Set allowed = ##class(OcuTalon.Core.Allowance).TryConsume(ref, "web", "zz message "_i, .retryAt, .first)
		Do $$$AssertEquals(allowed_"|"_retryAt_"|"_first, "1||0", "message "_i_" is allowed, with no retryAt and no first refusal")
	}
	Set times = ..Times(ref)
	Do $$$AssertEquals($ListLength(times), 5, "five entries are kept")
	Do $$$AssertTrue(..Shaped(times) && ..Ordered(times), "UTC times to the second, oldest first")
	Do $$$AssertEquals(..TurnCount(ref), 0, "no Turn is recorded")
	Do $$$AssertEquals(..Row(ref).AllowanceUntil, "", "and no window is open")
}

/// The 50 and 51 boundary: 49 entries leave room for one more, which is allowed; then the next is refused with retryAt, the first
/// refusal, a window and a refused Turn. A second refusal of the window repeats the retryAt with no flag and adds a Turn.
Method TestTheFiftyFirstIsRefused()
{
	Set ref = ..Session("fiftyfirst")
	Do ..Seed(ref, 49, 1000)
	Set oldest = $List(..Times(ref), 1)
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).TryConsume(ref, "web", "zz the fiftieth", .retryAt, .first), 1, "the 50th message is allowed")
	Do $$$AssertEquals($ListLength(..Times(ref)), 50, "and 50 entries are kept")
	Do $$$AssertEquals(..TurnCount(ref), 0, "with no Turn")

	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Set allowed = ##class(OcuTalon.Core.Allowance).TryConsume(ref, "web", "zz the fifty-first", .retryAt, .first)
	Set expected = ##class(OcuTalon.Data.Time).AddSeconds(oldest, 3600)
	Do $$$AssertEquals(allowed, 0, "the 51st message is refused")
	Do $$$AssertEquals(retryAt, expected, "retryAt is the oldest entry plus 3600 seconds")
	Do $$$AssertEquals(first, 1, "and it is the first refusal of the window")
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.AllowanceUntil, retryAt, "the session's AllowanceUntil is the retryAt")
	Do $$$AssertEquals($ListLength(row.AllowanceTimes), 50, "a refusal adds no entry")
	Do $$$AssertEquals(..TurnCount(ref), 1, "one refused Turn is recorded")
	Set turn = ..Turns(ref).GetAt(1)
	Do $$$AssertEquals(turn.State_"|"_turn.Channel_"|"_turn.Text, "refused|web|zz the fifty-first", "in the state refused, with its channel and text")
	Do $$$AssertEquals(turn.ClientId_"|"_turn.TriageDecisionRef_"|"_turn.TurnDecisionRef_"|"_turn.ReplyText, "|||", "with no ClientId, no decision and no reply")
	Do $$$AssertTrue(turn.Ref ? 22(1AN,1"-",1"_") && (turn.ItemId ? 22(1AN,1"-",1"_")) && (turn.Ref '= turn.ItemId), "with a new Ref and ItemId")
	Do $$$AssertTrue((turn.CreatedAt = before) || (turn.CreatedAt ] before), "created now: "_turn.CreatedAt)
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnQueue(ref).Count(), 0, "it is not in the turn queue")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentTurns(ref, 100).Count(), 0, "and not in the chat's turns")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).LastRepliedTurn(ref), "", "and no reply turn")

	Set allowed = ##class(OcuTalon.Core.Allowance).TryConsume(ref, "web", "zz the fifty-second", .again, .firstAgain)
	Do $$$AssertEquals(allowed_"|"_again_"|"_firstAgain, "0|"_retryAt_"|0", "a second refusal has the same retryAt and no first-refusal flag")
	Do $$$AssertEquals(..TurnCount(ref), 2, "and records another refused Turn")
	Do $$$AssertEquals(..Row(ref).AllowanceUntil, retryAt, "the window is unchanged")
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).Until(ref), retryAt, "and open until the retryAt")
}

/// Web chat, guide prompts and Telegram share one count: with the limit at 6, two web calls, two from the guide (channel web too) and
/// two Telegram calls are 6 messages, and the 7th, from any channel, is refused.
Method TestMixedChannelsCountTogether()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("messageAllowance", 6)
	Set ref = ..Session("mixed")
	For channel = "web", "telegram", "web", "web", "telegram", "web" {
		Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).TryConsume(ref, channel, "zz "_channel, .retryAt, .first), 1, "a "_channel_" message is allowed")
	}
	Do $$$AssertEquals($ListLength(..Times(ref)), 6, "six entries are kept")
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).TryConsume(ref, "telegram", "zz seventh", .retryAt, .first), 0, "the 7th message is refused, whatever its channel")
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).Limit(), 6, "the limit is the public setting")
}

/// AC 2: a fixture call with channel telegram at the limit is refused as a web call is: its Turn has channel telegram, the window's
/// first refusal is flagged, and a later telegram refusal of the window is not. No Telegram code is involved.
Method TestTelegramFixtureIsRefusedTheSameWay()
{
	Set ref = ..Session("telegram")
	Do ..Seed(ref, 50, 500)
	Set oldest = $List(..Times(ref), 1)
	Set allowed = ##class(OcuTalon.Core.Allowance).TryConsume(ref, "telegram", "zz from telegram", .retryAt, .first)
	Do $$$AssertEquals(allowed_"|"_first_"|"_retryAt, "0|1|"_##class(OcuTalon.Data.Time).AddSeconds(oldest, 3600), "refused, as the first refusal, with the retryAt")
	Set turn = ..Turns(ref).GetAt(1)
	Do $$$AssertEquals(turn.State_"|"_turn.Channel_"|"_turn.Text_"|"_turn.ClientId, "refused|telegram|zz from telegram|", "the refused Turn is a telegram one, with no ClientId")
	Set allowed = ##class(OcuTalon.Core.Allowance).TryConsume(ref, "telegram", "zz again", .again, .first)
	Do $$$AssertEquals(allowed_"|"_first_"|"_again, "0|0|"_retryAt, "the next one is refused without the flag")
	Do $$$AssertEquals(..TurnCount(ref), 2, "with its own Turn")
}

/// Row 5: once the oldest entry has left the window a message is allowed again; the next refusal is a first refusal of a new window
/// with a new retryAt. The elapsed time is shown by moving the entries (and the window of the first refusal) back.
Method TestNewWindow()
{
	Set ref = ..Session("newwindow")
	Do ..Seed(ref, 50, 3580)
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).TryConsume(ref, "web", "zz one", .retryAt, .first), 0, "refused inside the window")
	Do $$$AssertEquals(first, 1, "as a first refusal")
	Set ended = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -2)
	Do ..Seed(ref, 50, 3640, ended)
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).Until(ref), "", "the window has ended")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).TryConsume(ref, "web", "zz two", .retryAt, .first), 1, "a message is allowed again")
	Do $$$AssertEquals(retryAt_"|"_first, "|0", "with no retryAt")
	Set times = ..Times(ref)
	Do $$$AssertTrue(($ListLength(times) < 50) && ($ListLength(times) >= 1), "the entries that left the window are dropped and the new one is kept: "_$ListLength(times))
	Do $$$AssertTrue('(before ] $List(times, $ListLength(times))), "the new one, at the time of the call or later, is the last: "_$List(times, $ListLength(times)))

	Do ..Seed(ref, 50, 100, ended)
	Set allowed = ##class(OcuTalon.Core.Allowance).TryConsume(ref, "web", "zz three", .later, .first)
	Do $$$AssertEquals(allowed_"|"_first, "0|1", "the next refusal is a first refusal again")
	Do $$$AssertTrue(later ] retryAt, "with a later retryAt than before the window ended: "_later)
	Do $$$AssertEquals(..Row(ref).AllowanceUntil, later, "recorded as the window's end")
	Do $$$AssertEquals(..TurnCount(ref), 2, "two refused Turns, one for each window")
}

/// Row 6: with the flag off (absent, 0 or empty) every call allows, with an empty retryAt and no first refusal; no row is written
/// (the session keeps its 50 entries and no window) and no Turn is made.
Method TestFlagOffAllowsAndWritesNothing()
{
	Set ref = ..Session("flagoff")
	Do ..Seed(ref, 50, 500)
	Set before = ..Times(ref)
	For flag = "", 0 {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", flag)
		For i = 1:1:3 {
			Set retryAt = "zz", first = "zz"
			Set allowed = ##class(OcuTalon.Core.Allowance).TryConsume(ref, "web", "zz message", .retryAt, .first)
			Do $$$AssertEquals(allowed_"|"_retryAt_"|"_first, "1||0", "flag '"_flag_"': allowed, nothing to retry")
		}
	}
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.AllowanceTimes, before, "the entries are untouched")
	Do $$$AssertEquals(row.AllowanceUntil, "", "and no window is opened")
	Do $$$AssertEquals(..TurnCount(ref), 0, "no Turn is recorded")
	Do ##class(OcuTalon.Core.Allowance).Refund(ref)
	Do $$$AssertEquals(..Row(ref).AllowanceTimes, before, "Refund gives nothing back with the flag off")
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).MailAllowed(ref, ##class(OcuTalon.Data.Time).NowUtc(), .mailRetry, .sc), 1, "and the email limit is off")
}

/// Row 7: a session with no row (and an empty Ref) is allowed and nothing is recorded; the channel services check the row first.
Method TestNoRowAllowsAndRecordsNothing()
{
	Set unknown = "zzallowance"_..Number_"norow"
	For ref = unknown, "" {
		Set retryAt = "zz", first = "zz"
		Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).TryConsume(ref, "web", "zz nobody", .retryAt, .first), 1, "'"_ref_"': allowed")
		Do $$$AssertEquals(retryAt_"|"_first, "|0", "with no retryAt and no flag")
	}
	Do $$$AssertEquals(..TurnCount(unknown), 0, "no Turn is recorded")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexExists(unknown), 0, "and no row is made")
}

/// Row 8: another job holds the session's row lock: TryConsume waits about LOCKWAIT seconds, then answers 0 with an empty retryAt and
/// no flag, and records nothing; the other job lets go and the next call is allowed.
Method TestBusyLockRefusesWithNoRetryAt()
{
	Set ref = ..Session("busy")
	Do ..Seed(ref, 50, 500)
	Set id = ..Row(ref).%Id()
	Set before = ..Times(ref)
	Kill ^OcuTalonTest("Allowance", "job", "hold")
	Job ##class(OcuTalon.Test.Core.Allowance).Hold(id, "hold")
	Do ..WaitFor($Name(^OcuTalonTest("Allowance", "job", "hold", "ready")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("Allowance", "job", "hold", "ready")), 1, "another job holds the row's lock")
	Set started = $ZHorolog
	Set allowed = ##class(OcuTalon.Core.Allowance).TryConsume(ref, "web", "zz busy", .retryAt, .first)
	Set waited = $ZHorolog - started
	Do $$$AssertEquals(allowed_"|"_retryAt_"|"_first, "0||0", "the message is refused with no retryAt and no flag")
	Do $$$AssertTrue((waited >= (##class(OcuTalon.Core.Allowance).#LOCKWAIT - 0.5)) && (waited < (##class(OcuTalon.Core.Allowance).#LOCKWAIT + 5)), "after about "_##class(OcuTalon.Core.Allowance).#LOCKWAIT_" seconds: "_waited)
	Set ^OcuTalonTest("Allowance", "job", "hold", "release") = 1
	Do ..WaitFor($Name(^OcuTalonTest("Allowance", "job", "hold", "done")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("Allowance", "job", "hold", "done")), 1, "the other job lets go")
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.AllowanceTimes_"|"_row.AllowanceUntil, before_"|", "nothing was recorded on the row")
	Do $$$AssertEquals(..TurnCount(ref), 0, "and no Turn")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Trace).LockFree(id), 1, "the row's lock is free")
}

/// Row 8, a failed save: a refused message whose Turn cannot be saved (a channel over the property's length) rolls back, so
/// the call answers 0 with an empty retryAt, no flag, no window, no Turn and no open transaction, and holds no lock.
Method TestFailedSaveRollsBack()
{
	Set ref = ..Session("rollback")
	Do ..Seed(ref, 50, 500)
	Set id = ..Row(ref).%Id()
	Set level = $TLevel
	Set allowed = ##class(OcuTalon.Core.Allowance).TryConsume(ref, $Justify("", 40), "zz too long a channel", .retryAt, .first)
	Do $$$AssertEquals(allowed_"|"_retryAt_"|"_first, "0||0", "refused with no retryAt and no flag")
	Do $$$AssertEquals($TLevel, level, "no transaction is left open")
	Set row = ..Row(ref)
	Do $$$AssertEquals(row.AllowanceUntil, "", "no window was recorded")
	Do $$$AssertEquals(..TurnCount(ref), 0, "and no Turn")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Trace).LockFree(id), 1, "the row's lock is free")
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).TryConsume(ref, "web", "zz fine", .retryAt, .first), 0, "the next message is refused normally")
	Do $$$AssertEquals(first, 1, "as the first refusal")
}

/// Row 9: Refund removes the newest entry, so that a message whose send failed does not count; with the flag off, for an unknown
/// session and for a session with no entry it does nothing and never throws.
Method TestRefundGivesBackTheNewestEntry()
{
	Set ref = ..Session("refund")
	Do ..Seed(ref, 3, 600)
	Set three = ..Times(ref)
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).TryConsume(ref, "web", "zz fourth", .retryAt, .first), 1, "a message is allowed")
	Do $$$AssertEquals($ListLength(..Times(ref)), 4, "four entries")
	Do ##class(OcuTalon.Core.Allowance).Refund(ref)
	Do $$$AssertEquals(..Times(ref), three, "Refund removes the newest one")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Trace).LockFree(..Row(ref).%Id()), 1, "and leaves the row's lock free for another job")
	Do ##class(OcuTalon.Core.Allowance).Refund(ref)
	Do ##class(OcuTalon.Core.Allowance).Refund(ref)
	Do ##class(OcuTalon.Core.Allowance).Refund(ref)
	Do $$$AssertEquals(..Times(ref), "", "and every one in turn, down to none")
	Do ##class(OcuTalon.Core.Allowance).Refund(ref)
	Do ##class(OcuTalon.Core.Allowance).Refund("zzallowance"_..Number_"norow")
	Do ##class(OcuTalon.Core.Allowance).Refund("")
	Do $$$AssertEquals(..Times(ref), "", "Refund of an empty list, an unknown session and an empty Ref do nothing")
}

/// Limit() is the public setting messageAllowance when it is a whole number of 1 or more, otherwise 50.
Method TestLimitReadsThePublicSetting()
{
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).Limit(), 50, "an absent setting is 50")
	For value = 1, 7, 50, 120, "12", "007" {
		Do ##class(OcuTalon.Data.Public.Settings).Set("messageAllowance", value)
		Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).Limit(), +value, "'"_value_"' is read as "_+value)
	}
	For value = 0, -3, "abc", "2.5", "1e2", " 7", "7 ", "0x10", "00", "5,0" {
		Do ##class(OcuTalon.Data.Public.Settings).Set("messageAllowance", value)
		Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).Limit(), 50, "'"_value_"' counts as 50")
	}
}

/// Until(ref, now) is AllowanceUntil only while it is later than now; it is "" for no window, a window that ended or ends now, and a
/// session with no row, and it does not look at the flag.
Method TestUntil()
{
	Set ref = ..Session("until")
	Set now = "2030-06-15T10:00:00Z"
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).Until(ref, now), "", "no window")
	Set row = ..Row(ref)
	Set row.AllowanceUntil = "2030-06-15T10:00:01Z"
	Do $$$AssertStatusOK(row.%Save(), "a window ends a second after now")
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).Until(ref, now), "2030-06-15T10:00:01Z", "it is open")
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).Until(ref, "2030-06-15T10:00:01Z"), "", "and over at the retryAt itself")
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).Until(ref, "2030-06-15T10:00:02Z"), "", "and after it")
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).Until("zzallowance"_..Number_"norow", now), "", "a session with no row has none")
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).Until("", now), "", "nor an empty Ref")
}

/// The two notifications: kind allowance with the catalog key and the slots (the limit as a number, the UTC time and the install
/// link), for the session; nothing is rendered.
Method TestNotices()
{
	Set notice = ##class(OcuTalon.Core.Allowance).Notice("zzref", "2030-06-15T10:00:00Z")
	Do $$$AssertEquals(notice.SessionRef_"|"_notice.Kind_"|"_notice.CatalogKey, "zzref|allowance|conversation.sessionAllowance", "the session notice")
	Set slots = {}.%FromJSON(notice.Slots)
	Do $$$AssertEquals(slots.%GetTypeOf("limit")_"|"_slots.limit_"|"_slots.time_"|"_slots.readmeLink, "number|50|2030-06-15T10:00:00Z|https://github.com/jbrandtmse/OcuTalon#install-it-yourself", "with the limit, the time and the install link")
	Do $$$AssertEquals(slots.%Size(), 3, "and nothing else")
	Set capped = ##class(OcuTalon.Core.Allowance).DailyCapNotice("zzref", "2030-06-16T04:00:00Z")
	Do $$$AssertEquals(capped.SessionRef_"|"_capped.Kind_"|"_capped.CatalogKey, "zzref|allowance|conversation.dailyCap", "the daily-cap notice")
	Set slots = {}.%FromJSON(capped.Slots)
	Do $$$AssertEquals(slots.time_"|"_slots.readmeLink_"|"_slots.%Size(), "2030-06-16T04:00:00Z|https://github.com/jbrandtmse/OcuTalon#install-it-yourself|2", "with the time and the install link")
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("conversation.sessionAllowance", notice.Slots, "web", "2030-06-15T09:00:00Z", 1, .sc)
	Do $$$AssertStatusOK(sc, "the catalog renders the session notice")
	Set clock = ##class(OcuTalon.Data.Time).ForMessage("2030-06-15T10:00:00Z", "2030-06-15T09:00:00Z")
	Do $$$AssertEquals(text, "You've used this session's 50 messages for the hour. You can send more at "_clock_" ET, or install OcuTalon yourself to keep going: https://github.com/jbrandtmse/OcuTalon#install-it-yourself", "as the UX's text, in instance time and ET")
}

/// The email limit: with fewer than 20 incoming emails in the past hour MailAllowed allows; with 20 it refuses and retryAt is the
/// oldest plus 3600 s; outgoing rows and rows older than the hour are not counted; the flag off lifts the limit.
Method TestMailAllowed()
{
	Set ref = ..Session("mail")
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	For i = 1:1:19 Do ..Mail(ref, "in", ##class(OcuTalon.Data.Time).AddSeconds(now, -3000 + i))
	For i = 1:1:5 Do ..Mail(ref, "out", ##class(OcuTalon.Data.Time).AddSeconds(now, -100 - i))
	Do ..Mail(ref, "in", ##class(OcuTalon.Data.Time).AddSeconds(now, -3601))
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).MailAllowed(ref, now, .retryAt, .sc), 1, "19 incoming emails: allowed (outgoing and old rows are not counted)")
	Do $$$AssertEquals(retryAt, "", "with no retryAt")
	Do $$$AssertStatusOK(sc, "and no error")
	Set oldest = ##class(OcuTalon.Data.Time).AddSeconds(now, -3000 + 1)
	Do ..Mail(ref, "in", ##class(OcuTalon.Data.Time).AddSeconds(now, -10))
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).MailAllowed(ref, now, .retryAt, .sc), 0, "20 incoming emails: refused")
	Do $$$AssertEquals(retryAt, ##class(OcuTalon.Data.Time).AddSeconds(oldest, 3600), "retryAt is the oldest email plus 3600 seconds")
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).MailAllowed(ref, ##class(OcuTalon.Data.Time).AddSeconds(oldest, 3600), .later, .sc), 1, "allowed again at the retryAt")
	Do ..Mail(ref, "in", ##class(OcuTalon.Data.Time).AddSeconds(now, -5))
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).MailAllowed(ref, now, .retryAt, .sc), 0, "and still refused with 21")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Set retryAt = "zz"
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).MailAllowed(ref, now, .retryAt, .sc), 1, "the flag off: no limit")
	Do $$$AssertEquals(retryAt, "", "with no retryAt")
	Set other = ..Session("mailother")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).MailAllowed(other, now, .retryAt, .sc), 1, "another session's emails are not counted")
}

/// Matrix row 17, the error handling (QA): a count that cannot be read is an error status and the result is 0 with an empty retryAt,
/// never an allowance (a failed read must not let an email through). A read needs a session's Ref, so an empty Ref and the literal
/// instance make it fail. With the flag off nothing is read, so the same calls allow with an OK status.
Method TestMailAllowedFailedReadIsNotAnAllowance()
{
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	For ref = "", "instance" {
		Set retryAt = "zz"
		Set allowed = ##class(OcuTalon.Core.Allowance).MailAllowed(ref, now, .retryAt, .sc)
		Do $$$AssertEquals(allowed, 0, "'"_ref_"': a count that cannot be read does not allow the email")
		Do $$$AssertStatusNotOK(sc, "'"_ref_"': and the status says that the read failed")
		Do $$$AssertEquals(retryAt, "", "'"_ref_"': with no retryAt")
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Set retryAt = "zz"
	Do $$$AssertEquals(##class(OcuTalon.Core.Allowance).MailAllowed("", now, .retryAt, .sc), 1, "with the flag off the same call allows")
	Do $$$AssertStatusOK(sc, "with an OK status")
	Do $$$AssertEquals(retryAt, "", "and no retryAt")
}

/// The limit in the notice is the setting's value, not the start value (QA): with messageAllowance at 7 the session notice carries the
/// number 7 and the catalog renders "7 messages". The daily-cap notice carries no limit.
Method TestNoticeCarriesTheConfiguredLimit()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("messageAllowance", 7)
	Set notice = ##class(OcuTalon.Core.Allowance).Notice("zzref", "2030-06-15T10:00:00Z")
	Set slots = {}.%FromJSON(notice.Slots)
	Do $$$AssertEquals(slots.%GetTypeOf("limit")_"|"_slots.limit, "number|7", "the slot is the number 7")
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("conversation.sessionAllowance", notice.Slots, "web", "2030-06-15T09:00:00Z", 1, .sc)
	Do $$$AssertStatusOK(sc, "the catalog renders it")
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).TimeReads(text, "You've used this session's 7 messages for the hour. You can send more ", " ET, or install OcuTalon yourself to keep going: https://github.com/jbrandtmse/OcuTalon#install-it-yourself", "2030-06-15T10:00:00Z") '= "", "as 7 messages, at the notice's time: "_text)
}

/// A retryAt on another day than the reading reads with its day, as "on <day> at HH:MM ET" and not "at <day> at HH:MM ET", whatever the
/// time of day and the instance zone: the clock that renders is fixed, two days before the retryAt. Observe.TimeReads, which the
/// tests of the cards use to hold at any time of day, tells that form from the clock alone and takes no other.
Method TestNoticeOnAnotherDay()
{
	Set retryAt = "2030-06-17T10:00:00Z"
	Set notice = ##class(OcuTalon.Core.Allowance).Notice("zzref", retryAt)
	Set text = ##class(OcuTalon.Msg.Catalog).RenderAt("conversation.sessionAllowance", notice.Slots, "web", "2030-06-15T09:00:00Z", 1, .sc)
	Do $$$AssertStatusOK(sc, "the catalog renders the notice")
	Set head = "You've used this session's 50 messages for the hour. You can send more "
	Set tail = " ET, or install OcuTalon yourself to keep going: https://github.com/jbrandtmse/OcuTalon#install-it-yourself"
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads(text, head, tail, retryAt), "otherday", "the time carries its day: "_text)
	Set day = ##class(OcuTalon.Data.Time).ForMessage(retryAt, "2030-06-15T09:00:00Z")
	Do $$$AssertEquals(text, head_"on "_day_tail, "as 'on <day> at HH:MM', not 'at <day> at HH:MM': "_text)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads(head_"at "_day_tail, head, tail, retryAt), "", "and the helper does not take 'at <day> at HH:MM' for it")
	Set clock = $Extract(##class(OcuTalon.Data.Time).ToLocal(retryAt), 12, 16)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads(head_"at "_clock_tail, head, tail, retryAt), "sameday", "while the clock alone is the same-day form")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads(head_"at "_clock_"1"_tail, head, tail, retryAt), "", "and a clock that is not the time's is no form of it")
}

/// Observe.TimeReads reads the clock alone and the clock with the time's own weekday or date, in the joined form ("at ..." and
/// "on <day> at ...") and in the form that follows its head directly, and takes no text whose head, tail, clock or day is not the
/// one asked for. The expected weekday and date are worked out here from the time's local date, apart from Data.Time.ForMessage.
Method TestTimeReadsForms()
{
	Set utc = "2030-06-17T10:00:00Z"
	Set local = ##class(OcuTalon.Data.Time).ToLocal(utc)
	Set clock = $Extract(local, 12, 16)
	Set weekday = $Piece(##class(OcuTalon.Data.Time).#WEEKDAYS, ",", $ZDate($ZDateH($Piece(local, "T", 1), 3), 10) + 1)
	Set date = $Piece(##class(OcuTalon.Data.Time).#MONTHS, ",", +$Extract(local, 6, 7))_" "_(+$Extract(local, 9, 10))
	Set head = "until ", tail = " ET."
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads(head_"on "_date_" at "_clock_tail, head, tail, utc), "otherday", "its date reads as another day")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads(head_"on "_date_", "_$Extract(local, 1, 4)_" at "_clock_tail, head, tail, utc), "otherday", "its date with its year reads as another day")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads(head_clock_tail, head, tail, utc, 0), "sameday", "joined 0: the clock follows the head")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads(head_weekday_" at "_clock_tail, head, tail, utc, 0), "otherday", "joined 0: its weekday follows the head")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads(head_"on Oct 9 at "_clock_tail, head, tail, utc), "", "a date that is not its own is no form of it")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads(head_$Select(weekday = "Saturday": "Sunday", 1: "Saturday")_" at "_clock_tail, head, tail, utc, 0), "", "nor is a weekday that is not its own")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads(head_"at "_clock_tail, head, tail, utc, 0), "", "joined 0 takes no 'at' before the clock")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads("since "_clock_tail, head, tail, utc, 0), "", "another head is no form")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads(head_clock_" XT.", head, tail, utc, 0), "", "another tail of the same length is no form")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads("until", head, tail, utc, 0), "", "a text shorter than its head and tail is no form")
	Set other = $Extract(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).AddSeconds(utc, 3600)), 12, 16)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads(head_other_tail, head, tail, utc, 0), "", "the clock of another time is no form of it")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).TimeReads(head_"on "_date_" at "_other_tail, head, tail, utc), "", "nor is it with its day")
}

/// The rolling hour keeps the newest entries when the limit has been lowered below the number held (QA): with 8 entries and a limit
/// of 5 the 9th message is refused, retryAt is the fourth entry (the oldest of the newest five) plus 3600 s, and the row keeps those
/// five. Keeping the oldest five would give the first entry's time and leave a session blocked for too long.
Method TestOnlyTheNewestEntriesCountWhenTheLimitDrops()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("messageAllowance", 5)
	Set ref = ..Session("lowered")
	Do ..Seed(ref, 8, 3000)
	Set held = ..Times(ref)
	Set allowed = ##class(OcuTalon.Core.Allowance).TryConsume(ref, "web", "zz after the limit dropped", .retryAt, .first)
	Do $$$AssertEquals(allowed_"|"_first, "0|1", "the message is refused as the first refusal")
	Do $$$AssertEquals(retryAt, ##class(OcuTalon.Data.Time).AddSeconds($List(held, 4), 3600), "retryAt is the oldest of the newest five plus 3600 seconds")
	Do $$$AssertEquals(..Times(ref), $List(held, 4, 8), "and the row keeps the newest five")
}

/// AC 1: Conversation never refers to the allowance, whose answer WebChatIn alone uses (AD-20).
Method TestConversationNamesNoAllowance()
{
	Set definition = ##class(%Dictionary.ClassDefinition).%OpenId("OcuTalon.Core.Conversation")
	Do $$$AssertTrue($IsObject(definition), "Conversation has a class definition")
	Set found = 0, scanned = 0
	For i = 1:1:definition.Methods.Count() {
		Set method = definition.Methods.GetAt(i)
		Do method.Implementation.Rewind()
		While 'method.Implementation.AtEnd {
			Set code = method.Implementation.Read(30000)
			Set scanned = scanned + 1
			If (code [ "Core.Allowance") || (code [ "##class(Allowance)") || (code [ "TryConsume") Set found = found + 1
		}
	}
	Do $$$AssertTrue(scanned > 10, "the scan reads the methods of Conversation: "_scanned)
	Do $$$AssertEquals(found, 0, "none of them names the allowance")
}

/// --- helpers ---
/// A fixture session; its Ref is kept for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzallowance"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The session's row, read from disk.
Method Row(ref As %String) As OcuTalon.Data.Session [ Private ]
{
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do row.%Reload()
	Quit row
}

/// The session's AllowanceTimes.
Method Times(ref As %String) As %List [ Private ]
{
	Quit ..Row(ref).AllowanceTimes
}

/// Gives the session count entries, one second apart, the oldest being oldestAge seconds old (the newest is then oldestAge - count + 1
/// seconds old); until, when given, is the session's AllowanceUntil, otherwise it is emptied.
Method Seed(ref As %String, count As %Integer, oldestAge As %Integer, until As %String = "") [ Private ]
{
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set times = ""
	For i = 0:1:count - 1 Set times = times_$ListBuild(##class(OcuTalon.Data.Time).AddSeconds(now, i - oldestAge))
	Set row = ..Row(ref)
	Set row.AllowanceTimes = times
	Set row.AllowanceUntil = until
	Do $$$AssertStatusOK(row.%Save(), "the session holds "_count_" entries")
}

/// A SimMessage of the mailbox, in the direction given, created at the time.
Method Mail(ref As %String, direction As %String, createdAt As %String) [ Private ]
{
	Do ##class(OcuTalon.Test.Data.Fixture).SimMessage(ref, {"Kind": "mailbox", "Direction": (direction), "CreatedAt": (createdAt), "Subject": "zz mail"})
}

/// The turns of the session, oldest first.
Method Turns(ref As %String) As %ListOfObjects [ Private ]
{
	Quit ##class(OcuTalon.Data.Ownership).Turns(ref)
}

/// The number of turns of the session.
Method TurnCount(ref As %String) As %Integer [ Private ]
{
	Quit ..Turns(ref).Count()
}

/// 1 when every entry of the list is a UTC time to the second.
Method Shaped(times As %List) As %Boolean [ Private ]
{
	Set position = 0
	While $ListNext(times, position, entry) {
		If entry '? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z" Quit
	}
	Quit (position = 0)
}

/// 1 when the list is in time order.
Method Ordered(times As %List) As %Boolean [ Private ]
{
	Set previous = ""
	Set position = 0
	While $ListNext(times, position, entry) {
		If previous ] entry Quit
		Set previous = entry
	}
	Quit (position = 0)
}

/// Waits up to seconds for the global node named by ref to hold a value.
ClassMethod WaitFor(ref As %String, seconds As %Integer) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While ('$Data(@ref)) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

/// The job body of the holder: takes the row's lock, says so, keeps it until released, lets go and says so.
ClassMethod Hold(id As %String, key As %String)
{
	Set sc = ##class(OcuTalon.Data.Session).%LockId(id, 0, 5)
	If $SYSTEM.Status.IsError(sc) Quit
	Set ^OcuTalonTest("Allowance", "job", key, "ready") = 1
	Set deadline = $ZHorolog + 60
	While '$Get(^OcuTalonTest("Allowance", "job", key, "release")) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Do ##class(OcuTalon.Data.Session).%UnlockId(id)
	Set ^OcuTalonTest("Allowance", "job", key, "done") = 1
}

}
