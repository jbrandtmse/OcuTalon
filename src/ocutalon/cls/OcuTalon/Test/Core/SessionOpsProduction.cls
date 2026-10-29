/// End-to-end tests of SessionOps over the running production (Story 10.3; AD-1, AD-4, AD-12, AD-14, AD-17, AD-26, AD-32, AD-33). THEY RUN
/// IN THROWAWAY STACKS AND IN CI ONLY (InProduction). A fixture TelegramIn, this test process, submits Pair and Unpair through
/// Commands.Submit with the origin telegram (and the origin web_user for the page's Unpair), the way Lane A's service will; CommandsIn
/// sends them to the real SessionOps; and the tests read what the real consumers see: the audit log, the live events, Notify's
/// TelegramPaired, /state's Telegram block and the demo guide. ^OcuTalonTest("TelegramIncluded") stays 0 whenever a notice is sent
/// (a Notification that reaches Notify with Telegram included is queued for the disabled TelegramOut), and the telegramState mark is put back.
///   - TestPairAndStopThroughTheProduction: a Pair links the chat (Ok 1, paired), writes one linked Pairing audit entry that names the
///     session's user, the session and telegram and holds no chat id and no name, and publishes the pairing event; then, with Telegram
///     included and state on, TelegramPaired, /state and the guide read the session as paired; /stop unlinks it with an unlinked entry (stop),
///     an event, no notice, and the three read it as unpaired; with the state off they count it as unpaired;
///   - TestRejectedPairsAreAudited: an unknown, an expired and a used code link nothing and each writes a rejected entry (unknown with no
///     session, expired and used with the code's session); the CommandResult says which;
///   - TestPageUnpairSendsTheNotice: a web_user Unpair unlinks the chat with an unlinked entry (page, web), the event, and one Notification
///     from SessionOps to Notify that names the chat's ChatRef and pairing.unpairedFromPage, which Notify routes nowhere while Telegram is
///     not included;
///   - TestEndThroughTheProduction (Story 16.4): the page's EndSession (origin web_user) for a session with two real reminders, a real
///     watch of the Orders production, two pending approval requests and a pairing: both reminders are cancelled through the real ReminderOps
///     (their waiters end), the watch row is deleted through the real WatchOps (with a CheckChanged Stopped 1 to Checks), both requests are
///     cancelled through Approval.Cancel (an Approval entry cancelled each), the pairing is unlinked (one unlinked entry, session_end, web, and
///     one pairing event), no Notification is sent, the resume hash is cleared and the answer is ended; another session's rows are untouched;
///   - TestEndAgainChangesNothing: a repeat of EndSession answers ended and sends, audits and publishes nothing;
///   - TestEndWithAHeldReminderFails: a reminder row that another process holds makes End answer failed after it unlinked, stopped and
///     cancelled all the rest, with the resume hash kept so that the session stays resumable, and once the row is free the same End cancels
///     it, clears the hash and answers ended.
/// The reminders, the watches and the waiters that the tests make are removed in OnAfterAllTests.
Class OcuTalon.Test.Core.SessionOpsProduction Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzsessprod";

/// The longest to wait for an event, in seconds.
Parameter EVENTSECONDS = 20;

/// The Refs of the reminders that the run made, comma-separated, for the clean-up.
Property Reminders As %String(MAXLEN = "");

/// The count of chats made, for their chat ids.
Property Chats As %Integer [ InitialExpression = 0 ];

/// The value of ^OcuTalonTest("TelegramIncluded") before the run, "" when it was absent.
Property SavedIncluded As %String;

/// The telegramState mark before the run.
Property SavedMark As %String(MAXLEN = 1000);

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	Set ..SavedIncluded = $Get(^OcuTalonTest("TelegramIncluded"))
	Set ..SavedMark = ##class(OcuTalon.Data.StatusMark).Get("telegramState")
	Set ^OcuTalonTest("TelegramIncluded") = 0
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	For i = 1:1:$Length(..Reminders, ",") {
		If $Piece(..Reminders, ",", i) '= "" Do ##class(OcuTalon.Test.Schedule.ReminderFixture).Remove($Piece(..Reminders, ",", i))
	}
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?", $Piece(..Sessions, ",", i))
	}
	If ..SavedIncluded = "" {
		Kill ^OcuTalonTest("TelegramIncluded")
	} Else {
		Set ^OcuTalonTest("TelegramIncluded") = ..SavedIncluded
	}
	Do ##class(OcuTalon.Data.StatusMark).Record("telegramState", ..SavedMark)
	Quit ##super()
}

/// A Pair from a fixture TelegramIn, in the real production: the chat is linked, the code is used, and one linked Pairing audit entry
/// is written (the session's IRIS user, the session, channel telegram, no chat id and no name), and S's stream gets one pairing event. With
/// Telegram included and the state on, Notify's TelegramPaired, /state and Guide.Compute read the session as paired. /stop (Unpair from
/// the chat, origin telegram) unlinks it: an unlinked entry (stop), an event, no Notification, and the three read it as unpaired. With the
/// state off, the guide counts the pairing as off.
Method TestPairAndStopThroughTheProduction()
{
	If '..Guard() Quit
	Set session = ..Session("a")
	Set ns = ##class(OcuTalon.Install.Step.Demo).#NAMESPACE, production = ##class(OcuTalon.Install.Step.Demo).#PRODUCTION
	Do ##class(OcuTalon.Test.Data.Fixture).Check(session, ns, production)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(session, ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -10), ns, production, {"State": "open", "OpenVariant": "expired"})
	Set ..Refs = ..Refs_","_incident
	Set chatId = ..NextChatId()
	Set chat = ##class(OcuTalon.Data.Pairing).RecordChat(chatId, "Dana", .sc)
	Do ..KeepChat(chat)
	Set code = ..Code(session, .hash)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set headerMark = ..HeaderMark()
	Set result = ..Submit("Pair", "telegram", "", hash, chat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|paired", "Pair is Ok 1, paired")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, session, "the chat is linked to the session")
	Do $$$AssertNotEquals(##class(OcuTalon.Data.Pairing).ForCode(hash).CodeUsedAt, "", "the code is marked used")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Pairing", "Pairing", session, "", 1, ..#EVENTSECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one Pairing audit entry names the session")
	If entries.%Size() = 1 {
		Set entry = entries.%Get(0)
		Do $$$AssertEquals(entry.data.change_"|"_entry.data.reason_"|"_entry.data.irisUser_"|"_entry.data.sessionRef_"|"_entry.data.channel, "linked|code|"_..User("a")_"|"_session_"|telegram", "linked, code, the session's user and session, on telegram")
		Set text = entry.data.%ToJSON()_entry.description
		Do $$$AssertTrue((text '[ chatId) && (text '[ "Dana") && (text '[ code) && (text '[ hash), "and it holds no chat id, no name, no code and no hash")
	}
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "pairing", 1, ..#EVENTSECONDS)
	Do $$$AssertEquals(events.%Size(), 1, "one pairing event reaches the session's stream")
	If events.%Size() > 0 Do $$$AssertEquals(events.%Get(0).payload.paired_"|"_events.%Get(0).payload.displayName, "1|Dana", "paired, with the chat's name")
	Do $$$AssertEquals(..HopsSince(headerMark, "SessionOps", "Notify"), 0, "no Notification was sent")

	Do ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(1)
	Do ##class(OcuTalon.Data.StatusMark).RecordTelegram("on", "ocutalon_ci_bot")
	Do $$$AssertEquals(##class(OcuTalon.Core.Rule.Functions).TelegramPaired(session), 1, "Notify's TelegramPaired reads the session as paired")
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(session))
	Do $$$AssertEquals(body.telegram.included_"|"_body.telegram.state_"|"_body.telegram.botUserName_"|"_body.telegram.paired_"|"_body.telegram.displayName, "1|on|ocutalon_ci_bot|1|Dana", "/state reports it paired, with the chat's name")
	Set view = ##class(OcuTalon.Demo.Guide).Compute(session)
	Do $$$AssertEquals(view.Step4Variant_"|"_view.TelegramRow, "paired|0", "the guide reads it as paired, with no Telegram row")

	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set headerMark = ..HeaderMark()
	Set result = ..Submit("Unpair", "telegram", "", "", chat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|unpaired", "/stop is Ok 1, unpaired")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Pairing", "Pairing", session, "", 1, ..#EVENTSECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one Pairing audit entry names the session")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.change_"|"_entries.%Get(0).data.reason_"|"_entries.%Get(0).data.channel, "unlinked|stop|telegram", "unlinked, stop, on telegram")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "pairing", 2, ..#EVENTSECONDS)
	Do $$$AssertEquals(events.%Size(), 2, "a second pairing event follows")
	If events.%Size() = 2 Do $$$AssertEquals(events.%Get(1).payload.paired, 0, "not paired")
	Do $$$AssertEquals(..HopsSince(headerMark, "SessionOps", "Notify"), 0, "and no Notification was sent")
	Do $$$AssertEquals(##class(OcuTalon.Core.Rule.Functions).TelegramPaired(session), 0, "TelegramPaired reads it as unpaired")
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(session))
	Do $$$AssertEquals(body.telegram.paired_"|"_body.telegram.displayName, "0|", "/state reports it unpaired")
	Set view = ##class(OcuTalon.Demo.Guide).Compute(session)
	Do $$$AssertEquals(view.Step4Variant, "unpaired", "the guide reads it as unpaired")
	Set bare = ..Session("bare")
	Set view = ##class(OcuTalon.Demo.Guide).Compute(bare)
	Do $$$AssertEquals(view.TelegramRow, 1, "an unpaired session that is not watching gets the Telegram row")

	Set code = ..Code(session, .again)
	Do $$$AssertEquals(..Submit("Pair", "telegram", "", again, chat).Outcome, "paired", "control: a new code pairs the chat again")
	Do ##class(OcuTalon.Data.StatusMark).RecordTelegram("off", "")
	Do $$$AssertEquals(##class(OcuTalon.Demo.Guide).Compute(session).Step4Variant, "unpaired", "with the state off the guide counts the pairing as off")
	Do $$$AssertEquals(##class(OcuTalon.Demo.Guide).Compute(bare).TelegramRow, 0, "and shows no Telegram row")
	Do ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(0)
}

/// An unknown, an expired and a used code link nothing, each writes a rejected entry, and the CommandResult says which: unknown_code (the
/// entry has no session), expired_code and used_code (the entry names the code's session).
Method TestRejectedPairsAreAudited()
{
	If '..Guard() Quit
	Set session = ..Session("a")
	Set chat = ..NewChat("Dana")
	Set other = ..NewChat("Sam")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set result = ..Submit("Pair", "telegram", "", ##class(OcuTalon.Data.Pairing).HashCode("zz-nocode-"_..Number), chat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|unknown_code", "an unknown code: Ok 0, unknown_code")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Pairing", "Pairing", "", "", 1, ..#EVENTSECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one Pairing entry")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.change_"|"_entries.%Get(0).data.reason_"|"_entries.%Get(0).data.sessionRef_"|"_entries.%Get(0).data.channel, "rejected|unknown||telegram", "rejected, unknown, no session, telegram")
	Set past = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -5)
	Do ..Code(session, .expired, past)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set result = ..Submit("Pair", "telegram", "", expired, chat)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|expired_code", "an expired code: Ok 0, expired_code")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Pairing", "Pairing", session, "", 1, ..#EVENTSECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one Pairing entry names the session")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.change_"|"_entries.%Get(0).data.reason, "rejected|expired", "rejected, expired")
	Do ..Code(session, .good)
	Do $$$AssertEquals(..Submit("Pair", "telegram", "", good, chat).Outcome, "paired", "control: a good code pairs")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set result = ..Submit("Pair", "telegram", "", good, other)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|used_code", "a used code: Ok 0, used_code")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Pairing", "Pairing", session, "", 1, ..#EVENTSECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one Pairing entry names the session")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.change_"|"_entries.%Get(0).data.reason, "rejected|used", "rejected, used")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(other).SessionRef, "", "the second chat is not linked")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, session, "and the first still is")
}

/// The page's Unpair (origin web_user) in the real production: Ok 1, unpaired; the unlinked entry (page, web); the event; and one
/// Notification from SessionOps to Notify that carries the chat's ChatRef and pairing.unpairedFromPage. Telegram is not included, so Notify
/// sends it nowhere: no header goes from Notify to TelegramOut.
Method TestPageUnpairSendsTheNotice()
{
	If '..Guard() Quit
	Set session = ..Session("a")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set chat = ..NewChat("Dana")
	Do ..Code(session, .hash)
	Do $$$AssertEquals(..Submit("Pair", "telegram", "", hash, chat).Outcome, "paired", "control: the chat is paired")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set headerMark = ..HeaderMark()
	Set result = ..Submit("Unpair", "web_user", session, "", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|unpaired", "the page's Unpair is Ok 1, unpaired")
	Do $$$AssertEquals(##class(OcuTalon.Data.Pairing).Chat(chat).SessionRef, "", "the chat is unlinked")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Pairing", "Pairing", session, "", 1, ..#EVENTSECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one Pairing entry names the session")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.change_"|"_entries.%Get(0).data.reason_"|"_entries.%Get(0).data.channel, "unlinked|page|web", "unlinked, page, on web")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "pairing", 2, ..#EVENTSECONDS)
	Do $$$AssertEquals(events.%Size(), 2, "two pairing events: paired, then not paired")
	Do ..WaitHops(trace, "SessionOps", "Notify", 1)
	Do $$$AssertEquals(..HopsSince(headerMark, "SessionOps", "Notify"), 1, "control: the query that finds no Notification for a pair and a /stop finds this one")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "SessionOps", "Notify")
	Do $$$AssertEquals(sent.%Size(), 1, "one Notification goes from SessionOps to Notify, in the session's SuperSession")
	If sent.%Size() = 1 {
		Set notification = ##class(OcuTalon.Msg.Notification).%OpenId(sent.%Get(0).bodyId)
		Do $$$AssertEquals(notification.SessionRef_"|"_notification.ChatRef_"|"_notification.Kind_"|"_notification.CatalogKey_"|"_notification.Slots, session_"|"_chat_"|pairing|pairing.unpairedFromPage|{}", "it names the ChatRef and the key, and holds no text")
	}
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "SessionOps", "Notify", 1, ..#EVENTSECONDS), "Notify has handled the Notification")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Notify", "TelegramOut").%Size(), 0, "Notify sent it nowhere, because Telegram is not included")
}

/// EndSession through the production (Story 16.4; AD-1, AD-4, AD-11, AD-17, AD-33): session A has two real reminders, a real watch of the
/// Orders production, two pending approval requests and a pairing, and a resume hash; session B has one of each. The page's EndSession for
/// A (origin web_user) is Ok 1, ended. A's reminders are cancelled with their waiters ended (ReminderOps), its watch row is deleted with a
/// CheckChanged that says stopped (WatchOps), both requests are cancelled with an Approval entry cancelled each (Approval.Cancel, on web,
/// naming the session), its chat is unlinked with one unlinked entry (session_end, web) and one pairing event, no Notification is sent
/// anywhere, and its resume hash is "". B's reminder is pending, its watch exists, its request is pending, its chat is linked, its hash
/// is kept, and no audit entry or event names B.
Method TestEndThroughTheProduction()
{
	If '..Ready() Quit
	Set a = ..Populate("ea", 2, 2)
	Set b = ..Populate("eb", 1, 1)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set headerMark = ..HeaderMark()
	Set result = ..Submit("EndSession", "web_user", a.session, "", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|ended", "EndSession is Ok 1, ended: "_result.Message)
	For i = 0:1:a.reminders.%Size() - 1 {
		Set ref = a.reminders.%Get(i)
		Do $$$AssertEquals(##class(OcuTalon.Data.Reminder).RefIndexOpen(ref).State, "cancelled", "A's reminder "_(i + 1)_" is cancelled")
		Do $$$AssertTrue(##class(OcuTalon.Test.Schedule.ReminderFixture).WaitEnded(ref, ..#WAIT), "and its waiter has ended")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Checks(a.session).Count(), 0, "A's watch row is deleted")
	Do ..WaitHops(a.trace, "WatchOps", "Checks", 2)
	Do $$$AssertEquals(..StoppedChanges(a.trace), 1, "and WatchOps told Checks that it stopped, once")
	For i = 0:1:a.approvals.%Size() - 1 {
		Set ref = a.approvals.%Get(i)
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref).State, "cancelled", "A's request "_(i + 1)_" is cancelled")
		Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Approval", "Approval", ref, "", 1, ..#EVENTSECONDS)
		Do $$$AssertEquals(entries.%Size(), 1, "with one Approval entry")
		If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.change_"|"_entries.%Get(0).data.sessionRef_"|"_entries.%Get(0).data.channel_"|"_entries.%Get(0).data.irisUser, "cancelled|"_a.session_"|web|"_..User("ea"), "cancelled, naming the session, on web, by the session's user")
	}
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Pairing", "Pairing", a.session, "", 1, ..#EVENTSECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "one Pairing entry names A")
	If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.change_"|"_entries.%Get(0).data.reason_"|"_entries.%Get(0).data.channel, "unlinked|session_end|web", "unlinked, session_end, on web")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Pairing(a.session, .sc), "", "A has no pairing")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(a.session, "pairing", 1, ..#EVENTSECONDS).%Size(), 1, "and one pairing event")
	Do $$$AssertEquals(..HopsSince(headerMark, "SessionOps", "Notify"), 0, "no Notification was sent")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(a.session).ResumeHash, "", "A's resume hash is cleared")

	Do $$$AssertEquals(##class(OcuTalon.Data.Reminder).RefIndexOpen(b.reminders.%Get(0)).State, "pending", "B's reminder is pending")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Checks(b.session).Count(), 1, "B's watch exists")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(b.approvals.%Get(0)).State, "pending", "B's request is pending")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Pairing(b.session, .sc).SessionRef, b.session, "B's chat is linked")
	Do $$$AssertNotEquals(##class(OcuTalon.Data.Session).RefIndexOpen(b.session).ResumeHash, "", "B keeps its resume hash")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "", "", b.session).%Size(), 0, "no audit entry names B")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(b.session, "pairing").%Size(), 0, "and B got no pairing event")
}

/// A repeat of EndSession answers Ok 1, ended and changes nothing: no command goes to ReminderOps or WatchOps, no audit entry names the
/// session, no event is published, no Notification is sent, and the rows stay as the first End left them.
Method TestEndAgainChangesNothing()
{
	If '..Ready() Quit
	Set a = ..Populate("ag", 1, 1)
	Set first = ..Submit("EndSession", "web_user", a.session, "", "")
	Do $$$AssertEquals(first.Ok_"|"_first.Outcome, "1|ended", "control: the first End is ended: "_first.Message)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(a.session, "pairing", 1, ..#EVENTSECONDS).%Size(), 1, "one pairing event so far")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set headerMark = ..HeaderMark()
	Set again = ..Submit("EndSession", "web_user", a.session, "", "")
	Do $$$AssertEquals(again.Ok_"|"_again.Outcome, "1|ended", "the repeat is Ok 1, ended")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "", "", a.session).%Size(), 0, "no audit entry names the session")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(a.session, "pairing").%Size(), 1, "and no event was published")
	Do $$$AssertEquals(..HopsSince(headerMark, "SessionOps", "ReminderOps")_"|"_..HopsSince(headerMark, "SessionOps", "WatchOps")_"|"_..HopsSince(headerMark, "SessionOps", "Notify"), "0|0|0", "SessionOps sent nothing to ReminderOps, WatchOps or Notify")
	Do $$$AssertEquals(##class(OcuTalon.Data.Reminder).RefIndexOpen(a.reminders.%Get(0)).State, "cancelled", "the reminder stays cancelled")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(a.approvals.%Get(0)).State, "cancelled", "and the request")
}

/// A reminder row that another process holds (concurrency 4, past the ReminderOps job's lock timeout) makes End answer Ok 0, failed, after
/// every other step ran: the chat is unlinked, the watch is stopped, the other reminder and the request are cancelled, the resume hash is
/// cleared; the held reminder is still pending. Once the row is free, the same End cancels it and answers ended.
Method TestEndWithAHeldReminderFails()
{
	If '..Ready() Quit
	Set a = ..Populate("hd", 2, 1)
	Set held = ##class(OcuTalon.Data.Reminder).RefIndexOpen(a.reminders.%Get(0), 4)
	Do $$$AssertTrue($IsObject(held), "the test holds the first reminder's row")
	Set result = ..Submit("EndSession", "web_user", a.session, "", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "End answers Ok 0, failed: "_result.Message)
	Do $$$AssertEquals(held.State, "pending", "the held reminder is still pending")
	Set held = ""
	Do $$$AssertEquals(##class(OcuTalon.Data.Reminder).RefIndexOpen(a.reminders.%Get(1)).State, "cancelled", "the other reminder is cancelled")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Checks(a.session).Count(), 0, "the watch is stopped")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(a.approvals.%Get(0)).State, "cancelled", "the request is cancelled")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Pairing(a.session, .sc), "", "the chat is unlinked")
	Do $$$AssertNotEquals(##class(OcuTalon.Data.Session).RefIndexOpen(a.session).ResumeHash, "", "the resume hash is kept: the session stays resumable")
	Set again = ..Submit("EndSession", "web_user", a.session, "", "")
	Do $$$AssertEquals(again.Ok_"|"_again.Outcome, "1|ended", "with the row free, End is ended: "_again.Message)
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(a.session).ResumeHash, "", "and the resume hash is cleared")
	Do $$$AssertEquals(##class(OcuTalon.Data.Reminder).RefIndexOpen(a.reminders.%Get(0)).State, "cancelled", "and the first reminder is cancelled")
}

/// --- helpers ---
/// 1 when the test may run: Guard, and the Orders production that the real watch needs (Test.Watch.Case.Reason). Otherwise it fails with
/// the reason, and the test quits.
Method Ready() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	Set reason = ##class(OcuTalon.Test.Watch.Case).Reason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Quit 1
}

/// A fixture session of the name with real state: reminders real reminders (set through ReminderFixture, due in an hour), a real watch of
/// the Orders production (a StartWatch through Commands.Submit), approvals pending fixture requests, a pairing, and a resume hash. Returns
/// {session, trace, reminders: [Ref], approvals: [Ref]}. The rows are recorded for the clean-up.
Method Populate(name As %String, reminders As %Integer, approvals As %Integer) As %DynamicObject [ Private ]
{
	Set session = ..Session(name)
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Set trace = row.TraceRef
	Set row.ResumeHash = ##class(OcuTalon.Data.Session).Hash(..User(name))
	Do $$$AssertStatusOK(row.%Save(), "the session "_name_" holds a resume hash")
	Set row = ""
	Set found = {"session": (session), "trace": (trace), "reminders": [], "approvals": []}
	For i = 1:1:reminders {
		Set made = ##class(OcuTalon.Test.Schedule.ReminderFixture).Set(session, "zz "_name_" "_i, 3600 + i)
		Do $$$AssertEquals(made.ok_"|"_made.outcome, "1|set", "a real reminder "_i_" of "_name_" is set")
		Set ..Reminders = ..Reminders_$Select(..Reminders = "": "", 1: ",")_made.ref
		Do found.reminders.%Push(made.ref)
	}
	Set start = ##class(OcuTalon.Msg.Command.StartWatch).%New()
	Set start.SessionRef = session
	Set start.Namespace = ##class(OcuTalon.Install.Step.Demo).#NAMESPACE
	Set start.Production = ##class(OcuTalon.Install.Step.Demo).#PRODUCTION
	Set start.DisplayName = "Orders"
	Do $$$AssertStatusOK(##class(OcuTalon.Core.Commands).Submit(start, "web_user", .started), "a real watch of "_name_" is started")
	Do $$$AssertEquals(started.Ok_"|"_started.Outcome, "1|started", "and it says started: "_started.Message)
	For i = 1:1:approvals {
		Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(session)
		Set ..Refs = ..Refs_","_ref
		Do found.approvals.%Push(ref)
	}
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Pairing(session, "Dana "_name)
	Quit found
}

/// The number of CheckChanged messages from WatchOps to Checks, in the trace session, that say stopped.
Method StoppedChanges(trace As %String) As %Integer [ Private ]
{
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "WatchOps", "Checks")
	Set stopped = 0
	For i = 0:1:sent.%Size() - 1 {
		Set body = ##class(OcuTalon.Checks.Msg.CheckChanged).%OpenId(sent.%Get(i).bodyId)
		If $IsObject(body) && body.Stopped Set stopped = stopped + 1
	}
	Quit stopped
}

/// The IRIS user of the fixture session of the name (InProduction.Session builds it from the prefix, the run's number and the name).
Method User(name As %String) As %String [ Private ]
{
	Quit ..#SESSIONPREFIX_..Number_name
}

/// The next chat id of the run.
Method NextChatId() As %String [ Private ]
{
	Set ..Chats = ..Chats + 1
	Quit "74"_..Number_"0"_..Chats
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

/// Stores a new code for the session (expiring in ten minutes unless expires says otherwise) and records its row for the clean-up.
/// Returns the code, which only the test holds, and its hash in hash.
Method Code(session As %String, Output hash As %String, expires As %String = "") As %String [ Private ]
{
	Set code = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set hash = ##class(OcuTalon.Data.Pairing).HashCode(code)
	Set expires = $Select(expires = "": ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600), 1: expires)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Pairing).StoreCode(session, hash, expires), "a code is stored")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_##class(OcuTalon.Test.Data.Fixture).Adopt(##class(OcuTalon.Data.Pairing).ForCode(hash))
	Quit code
}

/// Submits the command of the verb (Pair, Unpair or EndSession) through Commands.Submit, as the fixture TelegramIn or the page does, and
/// returns the CommandResult. A Pair takes the hash and the chat, an Unpair the session (for the page) and the chat.
Method Submit(verb As %String, origin As %String, session As %String, hash As %String, chat As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = $ClassMethod("OcuTalon.Msg.Command."_verb, "%New")
	Set command.SessionRef = session
	If verb = "Pair" Set command.CodeHash = hash
	If (verb = "Pair") || (verb = "Unpair") Set command.ChatRef = chat
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, origin, .result)
	Do $$$AssertStatusOK(sc, "Submit returns OK")
	Quit result
}

/// The largest message header id so far, 0 when there is none.
Method HeaderMark() As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens.MessageHeader")
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The number of requests from the source item to the target item whose header is newer than the mark, in any session: a Pair and a
/// /stop carry no session, so their headers are in no session's trace.
Method HopsSince(mark As %Integer, source As %String, target As %String) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = ? AND TargetConfigName = ?", mark, source, target)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The number of requests from the source item to the target item in the trace session of the session.
Method Hops(trace As %String, source As %String, target As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, source, target).%Size()
}

/// Waits up to WAIT seconds until count requests have gone from the source item to the target item.
Method WaitHops(trace As %String, source As %String, target As %String, count As %Integer) [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		If (..Hops(trace, source, target) >= count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
}

}
