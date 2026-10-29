/// Tests of OcuTalon.Core.SessionOps over a shadow instance of Test.Core.SessionOpsProbe, which captures the audit data and the
/// Notifications instead of writing and sending them (Story 10.3; AD-1, AD-4, AD-12, AD-14, AD-17, AD-32). Safe on a slot: no production is
/// needed. The pairing events are read from Live.Event, and the Pairing and Session rows are made with Test.Data.Fixture and the real
/// Data.Pairing methods, so what the operation links is what Ownership, Notify and the guide read. The chat ids are made from the run's number,
/// from ^OcuTalonTest("SessionOps","n") (never reset); every row is removed with Fixture.Clean, and ^OcuTalonTest("TelegramIncluded") is put back.
///   - TestPairValidCode: the chat is linked, the code marked used, one linked audit entry (the session's user, session, channel telegram, no
///     chat id and no name), one pairing event with the chat's name, no notice;
///   - TestPairUnknownCode, TestPairExpiredCode, TestPairUsedCode, TestPairCodeOfAGoneSession, TestPairUnknownChat: nothing is linked, the
///     code stays as it was, and each outcome is audited as rejected with its reason;
///   - TestPairRepeatChangesNothing: a used code repeated by the chat that is on its session is paired, with no audit and no event;
///   - TestPairChatMoves and TestPairSecondChat: the unlinks come first with their audit entries, events and (for a second chat only) the
///     notice, then the link; TestNotifyReadsTheNotice routes that notice through the Notify rule, with Included 1 and 0;
///   - TestPairUsedCodeAfterItsExpiry: the used check comes before the expiry check: a used code that has since expired is still paired for
///     the chat that used it (nothing written), and used_code, not expired_code, for another chat;
///   - TestPairSameChatNewCode: a chat that is already on the session and sends the session's new code is paired again, not a second
///     chat: no unlink, no notice, one linked entry and a second paired event;
///   - TestPairMoveOntoASessionWithAChat: a chat that moves onto a session that has another chat drops that chat as well: moved (no notice)
///     and other_chat (with the notice), then linked, in that order;
///   - TestPairAuditFails: no linked entry, no link, the code unused, a warning;
///   - TestPairAuditFailsAfterADrop: when the linked entry fails after a second chat dropped the first, neither chat is linked, the code is
///     unused, the dropped chat was told at the drop, and the same code pairs once the entry can be written;
///   - TestUnpairStop, TestUnpairNotPaired, TestPageUnpair, TestPageUnpairNothingPaired, TestCrossSessionUnpair: the Unpair rows;
///   - TestUnpairOriginsAuditTheirChannel: an Unpair from web_user, web_admin, timer and system is audited on web, web, system and system;
///   - TestUnlinkApi: the signature that Story 16.4 calls, its no-ops and its refusals before any change;
///   - TestUnlinkSignature: the compiled signature of Unlink, the stable API of Story 16.4: a public instance method with its six
///     parameters in order, the notice key defaulting to "", and the status as its return;
///   - TestUnlinkStandsWhenTheSideEffectsFail: a failed audit entry or notice is a warning and the chat is unlinked;
///   - TestEndSessionStaysNotBuilt and TestOtherMessagesAreRefused.
Class OcuTalon.Test.Core.SessionOps Extends %UnitTest.TestCase
{

/// The probe, a subclass of the operation.
Parameter PROBE = "OcuTalon.Test.Core.SessionOpsProbe";

/// The Notify rule.
Parameter NOTIFYRULE = "OcuTalon.Core.Rule.Notify";

/// The run's number.
Property Number As %Integer;

/// The count of chats made, for their chat ids.
Property Chats As %Integer [ InitialExpression = 0 ];

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The value of ^OcuTalonTest("TelegramIncluded") before the run, "" when it was absent.
Property SavedIncluded As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("SessionOps", "n"))
	Set ..Refs = ""
	Set ..SavedIncluded = $Get(^OcuTalonTest("TelegramIncluded"))
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	If ..SavedIncluded = "" {
		Kill ^OcuTalonTest("TelegramIncluded")
	} Else {
		Set ^OcuTalonTest("TelegramIncluded") = ..SavedIncluded
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
}

/// A code of an unused session and a chat that are unpaired: Pair links the chat to the session and marks the code used. It writes one
/// linked audit entry (reason code) naming the session's IRIS user, the session and channel telegram, whose data holds neither the chat
/// id nor the name, and publishes one pairing event to the session with the chat's name. No Notification is sent. The CommandResult is
/// Ok 1, outcome paired.
Method TestPairValidCode()
{
	Set probe = ..Probe()
	Set session = ..Session("valid")
	Set chatId = ..NextChatId()
	Set chat = ##class(OcuTalon.Data.Pairing).RecordChat(chatId, "Dana", .sc)
	Do ..KeepChat(chat)
	Set code = ..Code(session, .hash)
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Set result = ..Pair(probe, hash, chat)
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|paired", "Ok 1, paired")
	Set row = ##class(OcuTalon.Data.Pairing).Chat(chat)
	Do $$$AssertEquals(row.SessionRef, session, "the chat is on the session")
	Do $$$AssertTrue((before '] row.SeenAt) && (row.SeenAt '] after), "SeenAt is the time of the link")
	Set used = ##class(OcuTalon.Data.Pairing).ForCode(hash)
	Do $$$AssertTrue((before '] used.CodeUsedAt) && (used.CodeUsedAt '] after), "the code is marked used now: "_used.CodeUsedAt)
	Do $$$AssertEquals(..AuditSummary(probe), "linked/code/"_session_"/telegram", "one linked audit entry (code) for the session on telegram")
	Set data = probe.Audits.%Get(0)
	Do $$$AssertEquals(data.irisUser, ..User("valid"), "it names the session's IRIS user")
	Do $$$AssertTrue(data.%ToJSON() '[ chatId, "it holds no chat id")
	Do $$$AssertTrue((data.%ToJSON() '[ "Dana") && (data.%ToJSON() '[ code) && (data.%ToJSON() '[ hash), "no name, no code and no hash")
	Do $$$AssertEquals(..EventSummary(session), "true:Dana", "one pairing event: paired, with the chat's name")
	Do $$$AssertEquals(probe.Notices.Count(), 0, "no Notification")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Pairing(session, .sc).Ref, chat, "Ownership.Pairing reads the chat")
}

/// A hash that matches no code row links nothing, and is audited as rejected (reason unknown) with no session and the job's user.
Method TestPairUnknownCode()
{
	Set probe = ..Probe()
	Set chat = ..NewChat("Dana")
	Set result = ..Pair(probe, ##class(OcuTalon.Data.Pairing).HashCode("zz-nocode-"_..Number), chat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|unknown_code", "Ok 0, unknown_code")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, "", "nothing is linked")
	Do $$$AssertEquals(..AuditSummary(probe), "rejected/unknown//telegram", "one rejected entry (unknown), with no session")
	Do $$$AssertEquals(probe.Audits.%Get(0).irisUser, $Username, "by the job's user")
	Do $$$AssertEquals(probe.Notices.Count(), 0, "no Notification")
}

/// A code whose expiry is now or past links nothing: expired_code, audited as rejected (expired) with the code's session, and the code
/// row is unchanged.
Method TestPairExpiredCode()
{
	Set probe = ..Probe()
	Set session = ..Session("expired")
	Set chat = ..NewChat("Dana")
	Set past = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -5)
	Do ..Code(session, .hash, past)
	Set result = ..Pair(probe, hash, chat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|expired_code", "Ok 0, expired_code")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, "", "nothing is linked")
	Do $$$AssertEquals(..AuditSummary(probe), "rejected/expired/"_session_"/telegram", "one rejected entry (expired) for the code's session")
	Set row = ##class(OcuTalon.Data.Pairing).ForCode(hash)
	Do $$$AssertEquals(row.CodeUsedAt_"|"_row.CodeExpiresAt, "|"_past, "the code row is unchanged")
	Do $$$AssertEquals(..EventSummary(session), "", "no event")
	Set atNow = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Code(session, .nowHash, atNow)
	Set result = ..Pair(probe, nowHash, chat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|expired_code", "a code that expires at this second is expired too")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef_"|"_##class(OcuTalon.Data.Pairing).ForCode(nowHash).CodeUsedAt, "|", "and it links nothing and stays unused")
}

/// A used code that another chat sends links nothing: used_code, audited as rejected (used) with the code's session, and the code row is
/// unchanged. The chat that used it is not the sender.
Method TestPairUsedCode()
{
	Set probe = ..Probe()
	Set session = ..Session("used")
	Set first = ..NewChat("Dana")
	Set second = ..NewChat("Sam")
	Set code = ..Code(session, .hash)
	Do $$$AssertEquals(..Pair(probe, hash, first).Outcome, "paired", "control: the first chat uses the code")
	Set usedAt = ##class(OcuTalon.Data.Pairing).ForCode(hash).CodeUsedAt
	Set probe = ..Probe()
	Set result = ..Pair(probe, hash, second)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|used_code", "Ok 0, used_code")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(second).SessionRef, "", "the second chat is not linked")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(first).SessionRef, session, "and the first still is")
	Do $$$AssertEquals(..AuditSummary(probe), "rejected/used/"_session_"/telegram", "one rejected entry (used) for the code's session")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).ForCode(hash).CodeUsedAt, usedAt, "the code row is unchanged")
	Do $$$AssertEquals(probe.Notices.Count(), 0, "no Notification")
}

/// A code whose session has no Session row counts as unknown_code: rejected (unknown) with no session.
Method TestPairCodeOfAGoneSession()
{
	Set probe = ..Probe()
	Set chat = ..NewChat("Dana")
	Set gone = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Code(gone, .hash)
	Set result = ..Pair(probe, hash, chat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|unknown_code", "Ok 0, unknown_code")
	Do $$$AssertEquals(..AuditSummary(probe), "rejected/unknown//telegram", "rejected (unknown), with no session")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).ForCode(hash).CodeUsedAt, "", "the code is unused")
}

/// A ChatRef that matches no chat row (unknown, a code row's Ref, or a case-changed Ref) links nothing: unknown_chat, rejected
/// (unknown_chat) with no session, and the code stays unused.
Method TestPairUnknownChat()
{
	Set session = ..Session("nochat")
	Set chat = ..NewChat("Dana")
	Set changed = $Select($ZConvert(chat, "U") '= chat: $ZConvert(chat, "U"), 1: $ZConvert(chat, "L"))
	Do ..Code(session, .hash)
	Set codeRef = ##class(OcuTalon.Data.Pairing).ForCode(hash).Ref
	For ref = ##class(OcuTalon.Bridge.Ids).NewRef(), codeRef, changed, "" {
		Set probe = ..Probe()
		Set result = ..Pair(probe, hash, ref)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|unknown_chat", "Ok 0, unknown_chat")
		Do $$$AssertEquals(..AuditSummary(probe), "rejected/unknown_chat//telegram", "rejected (unknown_chat), with no session")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).ForCode(hash).CodeUsedAt, "", "the code is unused")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, "", "the chat is unlinked")
	Do $$$AssertEquals(..EventSummary(session), "", "no event")
}

/// A chat that is already on the session and sends the session's used code again gets paired and nothing changes: no audit entry, no
/// event, no Notification, and the row and the code keep their marks.
Method TestPairRepeatChangesNothing()
{
	Set probe = ..Probe()
	Set session = ..Session("repeat")
	Set chat = ..NewChat("Dana")
	Do ..Code(session, .hash)
	Do $$$AssertEquals(..Pair(probe, hash, chat).Outcome, "paired", "control: the first Pair")
	Set usedAt = ##class(OcuTalon.Data.Pairing).ForCode(hash).CodeUsedAt
	Set seenAt = ##class(OcuTalon.Data.Pairing).Chat(chat).SeenAt
	Set probe = ..Probe()
	Hang 1.1
	Set result = ..Pair(probe, hash, chat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|paired", "Ok 1, paired")
	Do $$$AssertEquals(probe.Audits.%Size(), 0, "no audit entry")
	Do $$$AssertEquals(probe.Notices.Count(), 0, "no Notification")
	Do $$$AssertEquals(..EventSummary(session), "true:Dana", "and still the one event of the first Pair")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).ForCode(hash).CodeUsedAt_"|"_##class(OcuTalon.Data.Pairing).Chat(chat).SeenAt, usedAt_"|"_seenAt, "the marks are unchanged")
}

/// The used check comes before the expiry check: a used code that has since expired is still paired for the chat that used it, with no
/// audit entry (a re-sent start changes nothing), and it is used_code, not expired_code, for another chat.
Method TestPairUsedCodeAfterItsExpiry()
{
	Set probe = ..Probe()
	Set session = ..Session("usedexpired")
	Set first = ..NewChat("Dana")
	Set second = ..NewChat("Sam")
	Do ..Code(session, .hash)
	Do $$$AssertEquals(..Pair(probe, hash, first).Outcome, "paired", "control: the first chat uses the code")
	Set row = ##class(OcuTalon.Data.Pairing).ForCode(hash)
	Set row.CodeExpiresAt = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -60)
	Do row.%Save()
	Set row = ""
	Set probe = ..Probe()
	Set result = ..Pair(probe, hash, first)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|paired", "the chat that used the code is paired again, though the code has expired")
	Do $$$AssertEquals(probe.Audits.%Size(), 0, "with no audit entry")
	Set result = ..Pair(probe, hash, second)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|used_code", "another chat gets used_code, not expired_code")
	Do $$$AssertEquals(..AuditSummary(probe), "rejected/used/"_session_"/telegram", "audited as rejected (used)")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(second).SessionRef, "", "and is not linked")
}

/// A chat on session 1 that sends session 2's code moves: it is on session 2, session 1 gets an unlinked entry (moved) and a not-paired
/// event, then session 2 gets the linked entry and the paired event, in that order. No Notification is sent: the chat gets the pair reply.
Method TestPairChatMoves()
{
	Set probe = ..Probe()
	Set first = ..Session("moveone")
	Set second = ..Session("movetwo")
	Set chat = ..NewChat("Dana")
	Do ..Code(first, .h1)
	Do ..Code(second, .h2)
	Do $$$AssertEquals(..Pair(probe, h1, chat).Outcome, "paired", "control: the chat pairs with session 1")
	Set probe = ..Probe()
	Set result = ..Pair(probe, h2, chat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|paired", "Ok 1, paired")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, second, "the chat is on session 2")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Pairing(first, .sc), "", "and session 1 has no pairing")
	Do $$$AssertEquals(..AuditSummary(probe), "unlinked/moved/"_first_"/telegram;linked/code/"_second_"/telegram", "unlinked (moved) for session 1, then linked (code) for session 2")
	Do $$$AssertEquals(..EventSummary(first), "true:Dana,false:", "session 1: paired, then not paired")
	Do $$$AssertEquals(..EventSummary(second), "true:Dana", "session 2: paired")
	Do $$$AssertEquals(probe.Notices.Count(), 0, "no Notification")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).ForCode(h2).CodeUsedAt '= "", 1, "the code of session 2 is used")
}

/// A second chat that sends the code of a session that has a chat takes the session: the first chat is unlinked with an unlinked entry
/// (other_chat), a Notification {session, the first chat's ChatRef, kind pairing, pairing.otherChatPaired, {}} and a not-paired event,
/// then the second is linked with the linked entry and a paired event with its name.
Method TestPairSecondChat()
{
	Set probe = ..Probe()
	Set session = ..Session("second")
	Set one = ..NewChat("Dana")
	Set two = ..NewChat("Sam")
	Do ..Code(session, .h1)
	Do $$$AssertEquals(..Pair(probe, h1, one).Outcome, "paired", "control: the first chat pairs")
	Do ..Code(session, .h2)
	Set probe = ..Probe()
	Set result = ..Pair(probe, h2, two)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|paired", "Ok 1, paired")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(one).SessionRef_"|"_##class(OcuTalon.Data.Pairing).Chat(two).SessionRef, "|"_session, "the first chat is unlinked and the second is linked")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Pairing(session, .sc).Ref, two, "Ownership.Pairing reads the second")
	Do $$$AssertEquals(..AuditSummary(probe), "unlinked/other_chat/"_session_"/telegram;linked/code/"_session_"/telegram", "unlinked (other_chat), then linked (code)")
	Do $$$AssertEquals(probe.Notices.Count(), 1, "one Notification")
	Set notice = probe.Notices.GetAt(1)
	Do $$$AssertEquals(notice.SessionRef_"|"_notice.ChatRef_"|"_notice.Kind_"|"_notice.CatalogKey_"|"_notice.Slots, session_"|"_one_"|pairing|pairing.otherChatPaired|{}", "it names the first chat's ChatRef and the key")
	Do $$$AssertEquals(..EventSummary(session), "true:Dana,false:,true:Sam", "events: paired, not paired, paired with the second name")
}

/// A chat that is already on the session and sends the session's new, unused code is paired again, and it is not a second chat: nothing is
/// unlinked, no Notification is sent, one linked entry is written, the new code is marked used, and a second paired event follows (never a
/// not-paired one).
Method TestPairSameChatNewCode()
{
	Set probe = ..Probe()
	Set session = ..Session("samechat")
	Set chat = ..NewChat("Dana")
	Do ..Code(session, .h1)
	Do $$$AssertEquals(..Pair(probe, h1, chat).Outcome, "paired", "control: the chat pairs")
	Do ..Code(session, .h2)
	Set probe = ..Probe()
	Set result = ..Pair(probe, h2, chat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|paired", "Ok 1, paired")
	Do $$$AssertEquals(..AuditSummary(probe), "linked/code/"_session_"/telegram", "one linked entry and no unlinked entry")
	Do $$$AssertEquals(probe.Notices.Count(), 0, "no Notification: the chat is not a second chat")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, session, "the chat is on the session")
	Do $$$AssertNotEquals(##class(OcuTalon.Data.Pairing).ForCode(h2).CodeUsedAt, "", "the new code is marked used")
	Do $$$AssertEquals(..EventSummary(session), "true:Dana,true:Dana", "events: paired, then paired again, never not paired")
}

/// A chat on session 1 that sends the code of session 2, which has another chat, moves and takes the session: session 1 gets an unlinked
/// entry (moved) with no notice, session 2 an unlinked entry (other_chat) and the notice for the chat it lost and for no other, then the
/// linked entry, in that order; the events follow the entries, and the lost chat is unlinked.
Method TestPairMoveOntoASessionWithAChat()
{
	Set probe = ..Probe()
	Set from = ..Session("movefrom")
	Set onto = ..Session("moveonto")
	Set mover = ..NewChat("Dana")
	Set holder = ..NewChat("Sam")
	Do ..Code(from, .h1)
	Do ..Code(onto, .h2)
	Do $$$AssertEquals(..Pair(probe, h1, mover).Outcome, "paired", "control: the mover is on session 1")
	Do $$$AssertEquals(..Pair(probe, h2, holder).Outcome, "paired", "control: the holder is on session 2")
	Do ..Code(onto, .h3)
	Set probe = ..Probe()
	Set result = ..Pair(probe, h3, mover)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|paired", "Ok 1, paired")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(mover).SessionRef_"|"_##class(OcuTalon.Data.Pairing).Chat(holder).SessionRef, onto_"|", "the mover is on session 2 and the holder is unlinked")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Pairing(from, .sc), "", "and session 1 has no pairing")
	Do $$$AssertEquals(..AuditSummary(probe), "unlinked/moved/"_from_"/telegram;unlinked/other_chat/"_onto_"/telegram;linked/code/"_onto_"/telegram", "unlinked (moved), unlinked (other_chat), then linked (code)")
	Do $$$AssertEquals(probe.Notices.Count(), 1, "one Notification")
	Set notice = probe.Notices.GetAt(1)
	Do $$$AssertEquals(notice.SessionRef_"|"_notice.ChatRef_"|"_notice.CatalogKey, onto_"|"_holder_"|pairing.otherChatPaired", "for the holder, and none for the mover")
	Do $$$AssertEquals(..EventSummary(from), "true:Dana,false:", "session 1: paired, then not paired")
	Do $$$AssertEquals(..EventSummary(onto), "true:Sam,false:,true:Dana", "session 2: the holder, not paired, then the mover")
}

/// The Notification of a second chat goes through the Notify rule: with Telegram included it goes to TelegramOut alone, otherwise
/// nowhere (AD-14).
Method TestNotifyReadsTheNotice()
{
	Set probe = ..Probe()
	Set session = ..Session("notify")
	Set one = ..NewChat("Dana")
	Set two = ..NewChat("Sam")
	Do ..Code(session, .h1)
	Do ..Pair(probe, h1, one)
	Do ..Code(session, .h2)
	Set probe = ..Probe()
	Do ..Pair(probe, h2, two)
	Do $$$AssertEquals(probe.Notices.Count(), 1, "control: one Notification")
	Set notice = probe.Notices.GetAt(1)
	Set ^OcuTalonTest("TelegramIncluded") = 1
	Do $$$AssertEquals(..Route(..#NOTIFYRULE, notice), "send:TelegramOut:", "with Telegram included: TelegramOut alone")
	Set ^OcuTalonTest("TelegramIncluded") = 0
	Do $$$AssertEquals(..Route(..#NOTIFYRULE, notice), "", "with Telegram not included: no target")
	Set probe = ..Probe()
	Do ..Unlink(probe, session, "", "page", "web", "pairing.unpairedFromPage")
	Set notice = probe.Notices.GetAt(1)
	Set ^OcuTalonTest("TelegramIncluded") = 1
	Do $$$AssertEquals(..Route(..#NOTIFYRULE, notice), "send:TelegramOut:", "the page notice, Telegram included: TelegramOut alone")
	Set ^OcuTalonTest("TelegramIncluded") = 0
	Do $$$AssertEquals(..Route(..#NOTIFYRULE, notice), "", "and not included: no target")
}

/// When the linked entry can't be written nothing links: failed (Ok 0), the chat unlinked, the code unused, no event, and a warning.
Method TestPairAuditFails()
{
	Set probe = ..Probe()
	Set probe.AuditAnswer = "linked"
	Set session = ..Session("auditfails")
	Set chat = ..NewChat("Dana")
	Do ..Code(session, .hash)
	Set warnings = ..Logged("the linked audit entry was not written")
	Set result = ..Pair(probe, hash, chat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "Ok 0, failed")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, "", "the chat is not linked")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).ForCode(hash).CodeUsedAt, "", "the code is unused")
	Do $$$AssertEquals(..EventSummary(session), "", "no event")
	Do $$$AssertEquals(..Logged("the linked audit entry was not written"), warnings + 1, "a warning was logged")
	Set probe.AuditAnswer = ""
	Do $$$AssertEquals(..Pair(probe, hash, chat).Outcome, "paired", "and the same code pairs once the entry can be written")
}

/// When the linked entry can't be written after a second chat dropped the first, nothing links: failed (Ok 0), neither chat is linked,
/// the code is unused, and the dropped chat has been told (its notice was sent when it was dropped). The same code pairs the second chat
/// once the entry can be written.
Method TestPairAuditFailsAfterADrop()
{
	Set probe = ..Probe()
	Set session = ..Session("dropfails")
	Set one = ..NewChat("Dana")
	Set two = ..NewChat("Sam")
	Do ..Code(session, .h1)
	Do $$$AssertEquals(..Pair(probe, h1, one).Outcome, "paired", "control: the first chat pairs")
	Do ..Code(session, .h2)
	Set probe = ..Probe()
	Set probe.AuditAnswer = "linked"
	Set result = ..Pair(probe, h2, two)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "Ok 0, failed")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(one).SessionRef_"|"_##class(OcuTalon.Data.Pairing).Chat(two).SessionRef, "|", "neither chat is linked")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).ForCode(h2).CodeUsedAt, "", "the code is unused")
	Do $$$AssertEquals(probe.Notices.Count(), 1, "the dropped chat was told when it was dropped")
	Set probe.AuditAnswer = ""
	Do $$$AssertEquals(..Pair(probe, h2, two).Outcome, "paired", "the same code pairs the second chat once the entry can be written")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(two).SessionRef, session, "and it is linked")
}

/// /stop from Telegram: the chat's session is unlinked: Ok 1, unpaired, an unlinked entry (stop, channel telegram), a not-paired event
/// and no Notification. The chat row stays, with no session.
Method TestUnpairStop()
{
	Set probe = ..Probe()
	Set session = ..Session("stop")
	Set chat = ..NewChat("Dana")
	Do ..Code(session, .hash)
	Do ..Pair(probe, hash, chat)
	Set row = ##class(OcuTalon.Data.Pairing).Chat(chat)
	Set row.SeenAt = "2020-01-01T00:00:00Z"
	Do row.%Save()
	Set row = ""
	Set probe = ..Probe()
	Set result = ..Unpair(probe, "telegram", "", chat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|unpaired", "Ok 1, unpaired")
	Do $$$AssertEquals(..AuditSummary(probe), "unlinked/stop/"_session_"/telegram", "one unlinked entry (stop) on telegram")
	Do $$$AssertTrue(##class(OcuTalon.Data.Pairing).Chat(chat).SeenAt ] "2020-01-01T00:00:00Z", "the unlink touches SeenAt, so that the purge counts the chat as seen")
	Do $$$AssertEquals(..EventSummary(session), "true:Dana,false:", "events: paired, then not paired")
	Do $$$AssertEquals(probe.Notices.Count(), 0, "no Notification")
	Set row = ##class(OcuTalon.Data.Pairing).Chat(chat)
	Do $$$AssertTrue($IsObject(row) && (row.SessionRef = ""), "the chat row stays, with no session")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Pairing(session, .sc), "", "and the session has no pairing")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).ForCode(hash).CodeUsedAt '= "", 1, "the used code stays used")
}

/// /stop from a chat that is unpaired or unknown: Ok 0, not_paired; no change, no audit entry, no event.
Method TestUnpairNotPaired()
{
	Set probe = ..Probe()
	Set chat = ..NewChat("Dana")
	For ref = chat, ##class(OcuTalon.Bridge.Ids).NewRef(), "" {
		Set result = ..Unpair(probe, "telegram", "", ref)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_paired", "Ok 0, not_paired")
	}
	Do $$$AssertEquals(probe.Audits.%Size()_"|"_probe.Notices.Count(), "0|0", "no audit entry and no Notification")
}

/// The page's Unpair (origin web_user, the session, no ChatRef) unlinks the session's chat: Ok 1, unpaired, an unlinked entry (page,
/// channel web), the Notification pairing.unpairedFromPage with the chat's ChatRef and a not-paired event.
Method TestPageUnpair()
{
	Set probe = ..Probe()
	Set session = ..Session("page")
	Set chat = ..NewChat("Dana")
	Do ..Code(session, .hash)
	Do ..Pair(probe, hash, chat)
	Set probe = ..Probe()
	Set result = ..Unpair(probe, "web_user", session, "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|unpaired", "Ok 1, unpaired")
	Do $$$AssertEquals(..AuditSummary(probe), "unlinked/page/"_session_"/web", "one unlinked entry (page) on web")
	Do $$$AssertEquals(probe.Notices.Count(), 1, "one Notification")
	Set notice = probe.Notices.GetAt(1)
	Do $$$AssertEquals(notice.SessionRef_"|"_notice.ChatRef_"|"_notice.Kind_"|"_notice.CatalogKey_"|"_notice.Slots, session_"|"_chat_"|pairing|pairing.unpairedFromPage|{}", "pairing.unpairedFromPage with the chat's ChatRef")
	Do $$$AssertEquals(..EventSummary(session), "true:Dana,false:", "events: paired, then not paired")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, "", "the chat is unlinked")
}

/// The page's Unpair with nothing paired: Ok 0, not_paired; no change, no audit entry, no Notification, no event.
Method TestPageUnpairNothingPaired()
{
	Set probe = ..Probe()
	Set session = ..Session("pagenone")
	Set result = ..Unpair(probe, "web_user", session, "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_paired", "Ok 0, not_paired")
	Do $$$AssertEquals(probe.Audits.%Size()_"|"_probe.Notices.Count()_"|"_..EventSummary(session), "0|0|", "no audit entry, no Notification and no event")
}

/// An Unpair from each origin that CommandsIn routes to SessionOps besides telegram unlinks the session's chat and audits it on the
/// origin's channel: web_user and web_admin on web, timer and system on system.
Method TestUnpairOriginsAuditTheirChannel()
{
	Set origins = $ListBuild($ListBuild("web_user", "web"), $ListBuild("web_admin", "web"), $ListBuild("timer", "system"), $ListBuild("system", "system"))
	For i = 1:1:$ListLength(origins) {
		Set origin = $List($List(origins, i), 1), channel = $List($List(origins, i), 2)
		Set probe = ..Probe()
		Set session = ..Session("origin"_i)
		Set chat = ..NewChat("Dana")
		Do ..Code(session, .hash)
		Do $$$AssertEquals(..Pair(probe, hash, chat).Outcome, "paired", "control: the chat is paired for "_origin)
		Set probe = ..Probe()
		Set result = ..Unpair(probe, origin, session, "")
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|unpaired", origin_": Ok 1, unpaired")
		Do $$$AssertEquals(..AuditSummary(probe), "unlinked/page/"_session_"/"_channel, origin_": one unlinked entry on "_channel)
	}
}

/// An Unpair whose ChatRef is the chat of another session unpairs nothing of either: not_paired, and the other session's pairing stays.
Method TestCrossSessionUnpair()
{
	Set probe = ..Probe()
	Set mine = ..Session("crossmine")
	Set other = ..Session("crossother")
	Set otherChat = ..NewChat("Sam")
	Set myChat = ..NewChat("Dana")
	Do ..Code(other, .h2)
	Do ..Pair(probe, h2, otherChat)
	Set probe = ..Probe()
	Set result = ..Unpair(probe, "web_user", mine, otherChat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_paired", "an unpaired session naming another session's chat: not_paired")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(otherChat).SessionRef, other, "the other pairing stays")
	Do ..Code(mine, .h1)
	Do ..Pair(probe, h1, myChat)
	Set probe = ..Probe()
	Set result = ..Unpair(probe, "web_user", mine, otherChat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_paired", "a paired session naming another session's chat: not_paired")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(otherChat).SessionRef_"|"_##class(OcuTalon.Data.Pairing).Chat(myChat).SessionRef, other_"|"_mine, "both pairings stay")
	Do $$$AssertEquals(probe.Audits.%Size()_"|"_probe.Notices.Count(), "0|0", "no audit entry and no Notification")
	Set result = ..Unpair(probe, "web_user", mine, myChat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|unpaired", "naming its own chat unpairs it")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(otherChat).SessionRef, other, "and the other pairing still stays")
	Set result = ..Unpair(probe, "telegram", "", myChat)
	Do $$$AssertEquals(result.Outcome, "not_paired", "a /stop from the chat that is no longer paired: not_paired")
}

/// Unlink is the public API (Story 16.4): for a paired session it clears the link, writes an unlinked entry with the reason and channel,
/// publishes a not-paired event and reports changed 1; the second call is OK with changed 0 and nothing. A channel outside Msg.Enum CHANNEL, an
/// empty session and an empty reason are an error before any change. A ChatRef that is not the session's chat changes nothing. A notice key
/// sends the notice with the dropped chat's ChatRef.
Method TestUnlinkApi()
{
	Set probe = ..Probe()
	Set session = ..Session("api")
	Set chat = ..NewChat("Dana")
	Do ..Code(session, .hash)
	Do ..Pair(probe, hash, chat)
	Set probe = ..Probe()
	Set sc = probe.Unlink(session, "", "session_end", "bogus", "", .changed)
	Do $$$AssertStatusNotOK(sc, "a channel outside the enumeration is an error")
	Do $$$AssertEquals(changed, 0, "changed 0")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, session, "and nothing changed")
	Do $$$AssertStatusNotOK(probe.Unlink("", "", "session_end", "web", "", .changed), "an empty session is an error")
	Do $$$AssertStatusNotOK(probe.Unlink(session, "", "", "web", "", .changed), "an empty reason is an error")
	Do $$$AssertEquals(probe.Audits.%Size(), 0, "no audit entry so far")
	Set sc = probe.Unlink(session, ##class(OcuTalon.Bridge.Ids).NewRef(), "session_end", "web", "", .changed)
	Do $$$AssertStatusOK(sc, "another chat's Ref is OK")
	Do $$$AssertEquals(changed, 0, "with nothing changed")
	Set sc = probe.Unlink(session, "", "session_end", "web", "", .changed)
	Do $$$AssertStatusOK(sc, "the first call is OK")
	Do $$$AssertEquals(changed, 1, "changed 1")
	Do $$$AssertEquals(..AuditSummary(probe), "unlinked/session_end/"_session_"/web", "one unlinked entry (session_end) on web")
	Do $$$AssertEquals(..EventSummary(session), "true:Dana,false:", "events: paired, then not paired")
	Do $$$AssertEquals(probe.Notices.Count(), 0, "no notice without a key")
	Set sc = probe.Unlink(session, "", "session_end", "web", "", .changed)
	Do $$$AssertStatusOK(sc, "the second call is OK")
	Do $$$AssertEquals(changed, 0, "changed 0")
	Do $$$AssertEquals(probe.Audits.%Size(), 1, "and writes nothing more")
	Do $$$AssertEquals(..EventSummary(session), "true:Dana,false:", "no event")
	Do ..Code(session, .again)
	Do ..Pair(probe, again, chat)
	Set probe = ..Probe()
	Set sc = probe.Unlink(session, chat, "session_end", "system", "pairing.unpairedFromPage", .changed)
	Do $$$AssertEquals(changed_"|"_probe.Notices.Count()_"|"_probe.Notices.GetAt(1).ChatRef, "1|1|"_chat, "with a key and the chat's own Ref: unlinked, and one notice with the ChatRef")
}

/// Unlink is the stable API that Story 16.4's End calls: a public instance method (not a class method, not private) whose parameters are
/// sessionRef, chatRef, reason, channel, noticeKey (default "") and the output changed, in that order, and whose return is a status.
Method TestUnlinkSignature()
{
	Set method = ##class(%Dictionary.CompiledMethod).%OpenId("OcuTalon.Core.SessionOps||Unlink")
	Do $$$AssertTrue($IsObject(method), "Unlink is compiled")
	If '$IsObject(method) Quit
	Do $$$AssertEquals(method.ClassMethod_"|"_method.Private, "0|0", "a public instance method")
	Do $$$AssertEquals(method.FormalSpec, "sessionRef:%String,chatRef:%String,reason:%String,channel:%String,noticeKey:%String="""",*changed:%Boolean", "the six parameters in order, noticeKey defaulting to the empty string, changed an output")
	Do $$$AssertTrue($ListFind($ListBuild("%Status", "%Library.Status"), method.ReturnType) > 0, "returning a status: "_method.ReturnType)
}

/// An unlink stands when its audit entry, its notice or both fail: the chat is unlinked, Ok, and a warning is logged for each.
Method TestUnlinkStandsWhenTheSideEffectsFail()
{
	Set session = ..Session("stands")
	Set chat = ..NewChat("Dana")
	Set probe = ..Probe()
	Do ..Code(session, .hash)
	Do ..Pair(probe, hash, chat)
	Set probe = ..Probe()
	Set probe.AuditAnswer = "unlinked"
	Set probe.NoticeAnswer = "error"
	Set auditWarnings = ..Logged("the unlinked audit entry of session "_session)
	Set noticeWarnings = ..Logged("the notice pairing.unpairedFromPage of session "_session)
	Set result = ..Unpair(probe, "web_user", session, "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|unpaired", "Ok 1, unpaired")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, "", "the chat is unlinked")
	Do $$$AssertEquals(..Logged("the unlinked audit entry of session "_session), auditWarnings + 1, "a warning for the audit entry")
	Do $$$AssertEquals(..Logged("the notice pairing.unpairedFromPage of session "_session), noticeWarnings + 1, "a warning for the notice")
	Do $$$AssertEquals(..EventSummary(session), "true:Dana,false:", "and the event was published")
}

/// EndSession keeps answering the error status NotImplemented (code 5003), so CommandsIn answers not_built, until Story 16.4.
Method TestEndSessionStaysNotBuilt()
{
	Set probe = ..Probe()
	Set command = ##class(OcuTalon.Msg.Command.EndSession).%New()
	Set command.Origin = "web_user"
	Set command.SessionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusNotOK(sc, "an error status")
	Do $$$AssertTrue($ListFind($ListFromString($SYSTEM.Status.GetErrorCodes(sc)), 5003) > 0, "of code 5003")
}

/// A message that is no command, or another command, is refused with an error status that is not code 5003.
Method TestOtherMessagesAreRefused()
{
	Set probe = ..Probe()
	For message = ##class(Ens.StringRequest).%New("x"), ##class(OcuTalon.Msg.Command.SetDemoMode).%New() {
		Set sc = probe.OnMessage(message, .result)
		Do $$$AssertStatusNotOK(sc, $ClassName(message)_" is refused")
		Do $$$AssertTrue($ListFind($ListFromString($SYSTEM.Status.GetErrorCodes(sc)), 5003) = 0, "with a status that is not 5003")
	}
}

/// --- helpers ---
/// A shadow instance of the probe.
Method Probe() As OcuTalon.Test.Core.SessionOpsProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Quit probe
}

/// The IRIS user of the fixture session of the name.
Method User(name As %String) As %String [ Private ]
{
	Quit "zzsessops"_..Number_name
}

/// A fixture session of the name, recorded for the clean-up. Returns its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session(..User(name))
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The next chat id of the run.
Method NextChatId() As %String [ Private ]
{
	Set ..Chats = ..Chats + 1
	Quit "71"_..Number_"0"_..Chats
}

/// A chat row with the name, recorded for the clean-up. Returns its ChatRef.
Method NewChat(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Data.Pairing).RecordChat(..NextChatId(), name, .sc)
	Do ..KeepChat(ref)
	Quit ref
}

/// Records the chat row for the clean-up.
Method KeepChat(chat As %String) [ Private ]
{
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_##class(OcuTalon.Test.Data.Fixture).Adopt(##class(OcuTalon.Data.Pairing).Chat(chat))
}

/// Stores a new code for the session, which expires in ten minutes unless expires says otherwise, and records its row for the clean-up.
/// Returns the code, which only the test holds, and its hash in hash.
Method Code(session As %String, Output hash As %String, expires As %String = "") As %String [ Private ]
{
	Set code = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set hash = ##class(OcuTalon.Data.Pairing).HashCode(code)
	Set expires = $Select(expires = "": ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600), 1: expires)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Pairing).StoreCode(session, hash, expires), "a code is stored")
	Set row = ##class(OcuTalon.Data.Pairing).ForCode(hash)
	If $IsObject(row) Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	Quit code
}

/// Sends a Pair to the probe and returns its CommandResult.
Method Pair(probe As OcuTalon.Test.Core.SessionOpsProbe, hash As %String, chat As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.Pair).%New()
	Set command.Origin = "telegram"
	Set command.CodeHash = hash
	Set command.ChatRef = chat
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

/// Sends an Unpair to the probe and returns its CommandResult.
Method Unpair(probe As OcuTalon.Test.Core.SessionOpsProbe, origin As %String, session As %String, chat As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.Unpair).%New()
	Set command.Origin = origin
	Set command.SessionRef = session
	Set command.ChatRef = chat
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

/// Calls Unlink on the probe and asserts that the status is OK.
Method Unlink(probe As OcuTalon.Test.Core.SessionOpsProbe, session As %String, chat As %String, reason As %String, channel As %String, key As %String) [ Private ]
{
	Set sc = probe.Unlink(session, chat, reason, channel, key, .changed)
	Do $$$AssertStatusOK(sc, "Unlink is OK")
}

/// The probe's audit entries as "change/reason/sessionRef/channel", joined by ";".
Method AuditSummary(probe As OcuTalon.Test.Core.SessionOpsProbe) As %String [ Private ]
{
	Set summary = ""
	For i = 0:1:probe.Audits.%Size() - 1 {
		Set data = probe.Audits.%Get(i)
		Set summary = summary_$Select(summary = "": "", 1: ";")_data.change_"/"_data.reason_"/"_data.sessionRef_"/"_data.channel
	}
	Quit summary
}

/// The pairing events of the session's stream as "paired:displayName", joined by ",".
Method EventSummary(session As %String) As %String [ Private ]
{
	Set events = ##class(OcuTalon.Live.Event).Since(session, 0)
	Set summary = ""
	For i = 0:1:events.%Size() - 1 {
		Set event = events.%Get(i)
		If event.type '= "pairing" Continue
		Set summary = summary_$Select(summary = "": "", 1: ",")_$Select(event.payload.paired: "true", 1: "false")_":"_event.payload.displayName
	}
	Quit summary
}

/// The number of Event Log warnings whose text contains the text.
Method Logged(text As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE Type = 3 AND Text [ ?", text)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The rule's answer for the document, as "send:<targets>:" or "" (the way Test.Core.Routing drives a rule): the rule is evaluated over a
/// shadow routing engine that holds the document.
Method Route(rule As %String, document As %RegisteredObject) As %String [ Private ]
{
	Set engine = ##class(Ens.Host).GetShadowInstance("class||EnsLib.MsgRouter.RoutingEngine", .sc)
	If '$IsObject(engine) Quit "ERROR "_$SYSTEM.Status.GetErrorText(sc)
	Set engine.Document = document
	Set engine.MsgClass = $ClassName(document)
	Set engine.Source = "zzsource"
	Set sc = ##class(Ens.Rule.RuleDefinition).EvaluateRulesEx(rule, 0, engine, "", .return, .reason, 1, "e")
	If $SYSTEM.Status.IsError(sc) Quit "ERROR "_$SYSTEM.Status.GetErrorText(sc)
	Quit $Get(return)
}

}
