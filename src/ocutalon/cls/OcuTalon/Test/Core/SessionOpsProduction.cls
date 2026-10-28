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
///   - TestEndSessionStaysNotBuilt: EndSession is not_built.
Class OcuTalon.Test.Core.SessionOpsProduction Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzsessprod";

/// The longest to wait for an event, in seconds.
Parameter EVENTSECONDS = 20;

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
	Hang 2
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Notify", "TelegramOut").%Size(), 0, "Notify sent it nowhere, because Telegram is not included")
}

/// EndSession keeps answering not_built until Story 16.4.
Method TestEndSessionStaysNotBuilt()
{
	If '..Guard() Quit
	Set session = ..Session("a")
	Set result = ..Submit("EndSession", "web_user", session, "", "")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_built", "EndSession is Ok 0, not_built")
}

/// --- helpers ---
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
