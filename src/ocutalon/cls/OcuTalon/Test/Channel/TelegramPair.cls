/// Live tests of the pairing path of TelegramIn against the CI mock (Stories 12.4 and 12.5; FR-15, FR-18, FR-19, FR-9, AD-1, AD-4, AD-14,
/// AD-17, AD-27, AD-32, DW-486). THESE TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), like OcuTalon.Test.Channel.LiveCase, which they extend:
/// TelegramIn and TelegramOut run on the production against the mock, the Telegram seam is 1 and demo mode is on (a test fails with that
/// reason when it is not). Each test makes fixture sessions (zztgpair...) that watch nothing, stores their codes as the web route does
/// (Pairing.StoreCode with the code's hash), queues updates through the mock's /updates, and waits until TelegramIn has handled them (the
/// kept offset). The fixture chat ids are 840177341xx. Each test ends with Ending, on every path.
///   - TestPairs: a valid code pairs the chat with the session (the chat's row, the used mark, the Pair command, the linked audit entry,
///     the pairing event and /state), the chat gets the one confirmation, no store holds the code, the chat id or the name, and the guide
///     follows the pairing and the page's Unpair;
///   - TestNameOnlyWhilePaired: a paired chat keeps its name through later messages with no name (a pairing update too) and takes a new one, gets no
///     reply to its other messages (the bad-code reply for a code, the start text for /help), and a chat that is
///     not paired never keeps a name, also after a code that links nothing, and its next update clears a name left on its row;
///   - TestNoPairWithoutACode: a bare /start, a /start of spaces and a group chat's /start submit no Pair;
///   - TestBadCodes (Story 12.5): an unknown, an expired, a used and a reset code each get the bad-code reply, link nothing, publish no
///     event and leave a rejected audit entry that holds no Telegram identity;
///   - TestStrangerReplies: a bare /start and /help get the start text, any other message from a chat that is not paired gets the
///     not-paired text once a minute only (the reply slot), reaches no session or model, and leaves a row with no session, no name and no
///     code, which the Core area's Purge removes once old;
///   - TestStop: /stop unpairs from the chat (the Unpair command, the audit entry, the event, the name cleared, the reply), and the
///     page's Unpair tells the chat;
///   - TestOneLivePairing: a chat that pairs with another session leaves the first, and a session that pairs a second chat drops the
///     first one, which is treated as unpaired from then on.
Class OcuTalon.Test.Channel.TelegramPair Extends OcuTalon.Test.Channel.LiveCase
{

/// The longest, in seconds, to wait for an effect of a handled update.
Parameter WAIT = 10;

/// The confirmation's text, the oracle of the catalog's pairing.paired.
Parameter CONFIRMATION = "You're paired with your OcuTalon session; notifications, reminders and approval requests will arrive here (send /stop to unpair).";

/// The catalog's texts, the oracles of pairing.badCode, pairing.start, pairing.notPaired, pairing.stopped, pairing.unpairedFromPage and
/// pairing.otherChatPaired.
Parameter BAD = "That code didn't work. Open the OcuTalon page and scan the QR code there for a new one.";

Parameter START = "This is OcuTalon, an assistant that runs inside InterSystems IRIS. To use it here, open your OcuTalon page and scan the QR code there; that pairs this chat with your session.";

Parameter NOTPAIRED = "This chat isn't paired yet. Open your OcuTalon page and scan the QR code there.";

Parameter STOPPED = "Unpaired. This chat won't get OcuTalon messages anymore. Scan the QR code on the OcuTalon page to pair again.";

Parameter FROMPAGE = "Unpaired from the OcuTalon page. Scan the QR code there to pair again.";

Parameter OTHERCHAT = "Another Telegram chat was paired with this OcuTalon session, so this chat is no longer paired.";

/// The updates queued so far (the mock numbers them from 1 after the reset, and TelegramIn keeps the id of the last handled plus 1).
Property Sent As %Integer [ InitialExpression = 0, Private ];

/// 1 once the Telegram seam is set by Begin.
Property Seam As %Boolean [ InitialExpression = 0, Private ];

/// The seam as Begin found it.
Property WasIncluded As %Boolean [ Private ];

/// The Refs of the fixture sessions, as a list: their code rows are deleted by Ending.
Property Sessions As %List [ Private ];

/// The unique text of the event-log probe, removed by Ending.
Property Probe As %String [ Private ];

/// The start of every test: the live guard, demo mode, the seam, both items on, and a long poll open. 1 when the test may go on; when a
/// step fails, the test is failed and ended here.
Method Begin() As %Boolean [ Private ]
{
	If '..ReadyLive() Quit 0
	Set ..Sent = 0
	Set ..Sessions = ""
	Set ..Probe = ""
	Set ..WasIncluded = ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(1)
	Set ..Seam = 1
	If '##class(OcuTalon.Core.Rule.Functions).DemoOn() {
		Do $$$AssertTrue(0, "demo mode is not on, and the guide of the pairing is read in demo mode")
		Do ..Ending()
		Quit 0
	}
	Set ids = "84017734101,84017734102,84017734103,84017734104,84017734105,84017734106,84017734107,84017734108,84017734109,84017734120,84017734121,84017734122,84017734123,84017734124"
	Do ..Chat(ids)
	Do ..DropChats(ids)
	Set started = ..StartItems("TelegramOut,TelegramIn")
	Do $$$AssertStatusOK(started, "TelegramOut and TelegramIn are enabled")
	Set on = $$$ISOK(started) && ..WaitState("on", 20)
	Do $$$AssertTrue(on, "the Telegram state becomes on")
	Set polling = on && (..WaitCalls("getUpdates", 1, 20).%Size() >= 1)
	Do $$$AssertTrue(polling, "a long poll is open")
	If 'polling {
		Do ..Ending()
		Quit 0
	}
	Quit 1
}

/// The end of every test, on every path: Cleanup, then the probe row and the code rows of the fixture sessions deleted, and the seam back.
Method Ending() [ Private ]
{
	Do ..Cleanup()
	Try {
		If ..Probe '= "" Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Text [ ?", ..Probe)
		For i = 1:1:$ListLength(..Sessions) {
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Pairing WHERE CodeSessionRef = ?", $List(..Sessions, i))
		}
	} Catch {
	}
	Set ..Probe = ""
	Set ..Sessions = ""
	If ..Seam Do ##class(OcuTalon.Test.Data.Fixture).SetTelegramIncluded(..WasIncluded)
	Set ..Seam = 0
}

/// A fixture session that watches nothing, and its Ref.
Method NewSession() As %String [ Private ]
{
	Set session = ..FixtureSession("zztgpair")
	Set ..Sessions = ..Sessions _ $ListBuild(session.Ref)
	Quit session.Ref
}

/// Stores a new code for the session as the web route does (its hash, valid for lifetime seconds, 600 by default; a negative lifetime
/// stores an expired code); the code is code and its hash is hash.
Method NewCode(session As %String, Output hash As %String, lifetime As %Integer = 600) As %String [ Private ]
{
	Set code = "zzpair"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set hash = ##class(OcuTalon.Data.Pairing).HashCode(code)
	Set expires = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), lifetime)
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Pairing).StoreCode(session, hash, expires), "the session's code is stored as its hash")
	Quit code
}

/// Queues one update and counts it.
Method Send(update As %DynamicObject) [ Private ]
{
	Set batch = []
	Do batch.%Push(update)
	Do $$$AssertTrue(..QueueUpdates(batch), "an update is queued")
	Set ..Sent = ..Sent + 1
}

/// 1 when TelegramIn has handled every queued update.
Method Handled() As %Boolean [ Private ]
{
	Quit ..WaitOffset(..Sent + 1, 20)
}

/// The chat's row: 1 when there is one, with its Ref, SessionRef and DisplayName.
Method ChatRow(chatId As %String, Output ref As %String, Output sessionRef As %String, Output name As %String) As %Boolean [ Private ]
{
	Set ref = "", sessionRef = "", name = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Ref, SessionRef, DisplayName FROM OcuTalon_Data.Pairing WHERE ChatId = ? ORDER BY ID", chatId)
	If 'result.%Next() Quit 0
	Set ref = result.%GetData(1), sessionRef = result.%GetData(2), name = result.%GetData(3)
	Quit 1
}

/// 1 when the chat's row is linked to the session within WAIT seconds.
Method WaitLinked(chatId As %String, session As %String) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + ..#WAIT
	For {
		Do ..ChatRow(chatId, , .linked)
		If (linked = session) || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit linked = session
}

/// The Notification bodies that TelegramIn sent to Notify after the mark, in order.
Method Notifications(mark As %Integer) As %DynamicArray [ Private ]
{
	Set found = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'TelegramIn' AND TargetConfigName = 'Notify' AND MessageBodyClassName = 'OcuTalon.Msg.Notification' ORDER BY ID", mark)
	While result.%Next() {
		Set body = ##class(OcuTalon.Msg.Notification).%OpenId(result.%GetData(1))
		If $IsObject(body) Do found.%Push({"kind": (body.Kind), "catalogKey": (body.CatalogKey), "chatRef": (body.ChatRef), "sessionRef": (body.SessionRef), "slots": (body.Slots)})
	}
	Quit found
}

/// The texts that the mock received for the chat: once there are count of them (or WAIT seconds pass), and 1 s more for any extra one.
Method TextsAfter(chatId As %String, count As %Integer) As %DynamicArray [ Private ]
{
	Set deadline = $ZHorolog + ..#WAIT
	For {
		If (..TextsTo(chatId).%Size() >= count) || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Hang 1
	Quit ..TextsTo(chatId)
}

/// Asserts that the chat's texts, after count of them, are exactly the expected ones.
Method AssertTexts(chatId As %String, expected As %DynamicArray, message As %String) [ Private ]
{
	Set texts = ..TextsAfter(chatId, expected.%Size())
	Do $$$AssertEquals(texts.%ToJSON(), expected.%ToJSON(), message)
}

/// Pairs the chat with the session by a new code: 1 when the chat's row is linked to the session.
Method PairChat(chatId As %String, name As %String, session As %String) As %Boolean [ Private ]
{
	Set code = ..NewCode(session)
	Do ..Send(..PrivateMessage(chatId, name, "/start "_code))
	Do $$$AssertTrue(..Handled(), "TelegramIn handled the pairing of "_chatId)
	Set linked = ..WaitLinked(chatId, session)
	Do $$$AssertTrue(linked, "the chat "_chatId_" is paired with its session")
	Quit linked
}

/// The pairing events on the session's stream, in order.
Method PairingEvents(session As %String) As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(session, "pairing")
}

/// Asserts the events of the session's stream after the first skip: their paired flags and display names, as "paired:name" in order.
Method AssertEventsSince(session As %String, skip As %Integer, expected As %String, message As %String) [ Private ]
{
	Set wanted = $Length(expected, ",")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "pairing", skip + wanted, ..#WAIT)
	Set seen = ""
	For i = skip:1:events.%Size() - 1 {
		Set seen = seen _ $Select(seen = "": "", 1: ",") _ events.%Get(i).payload.paired _ ":" _ events.%Get(i).payload.displayName
	}
	Do $$$AssertEquals(seen, expected, message)
}

/// The "change:reason:channel" of each Pairing audit entry since the mark that names the session, in order, comma-separated; it waits for count.
Method AuditOf(mark As %String, session As %String, count As %Integer) As %String [ Private ]
{
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Pairing", "Pairing", session, "", count, ..#WAIT)
	Set seen = ""
	For i = 0:1:entries.%Size() - 1 {
		Set data = entries.%Get(i).data
		Set seen = seen _ $Select(seen = "": "", 1: ",") _ data.change _ ":" _ data.reason _ ":" _ data.channel
	}
	Quit seen
}

/// The Outcome of each CommandResult body after the header mark, in order, comma-separated.
Method Outcomes(mark As %Integer) As %String [ Private ]
{
	Set seen = "", done = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = 'OcuTalon.Msg.CommandResult' ORDER BY ID", mark)
	While result.%Next() {
		If $ListFind(done, result.%GetData(1)) Continue
		Set done = done _ $ListBuild(result.%GetData(1))
		Set body = ##class(OcuTalon.Msg.CommandResult).%OpenId(result.%GetData(1))
		If $IsObject(body) Set seen = seen _ $Select(seen = "": "", 1: ",") _ body.Outcome
	}
	Quit seen
}

/// The newest guide.state payload on the session's stream, or "".
Method Guide(session As %String) As %DynamicObject [ Private ]
{
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "guide.state")
	If events.%Size() = 0 Quit ""
	Quit events.%Get(events.%Size() - 1).payload
}

/// Waits until the newest guide.state payload of the session has the variant; the payload ("" when none came).
Method WaitGuide(session As %String, variant As %String) As %DynamicObject [ Private ]
{
	Set deadline = $ZHorolog + ..#WAIT
	For {
		Set guide = ..Guide(session)
		If ($IsObject(guide) && (guide."step4Variant" = variant)) || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit guide
}

/// A valid code pairs the chat with the session; the chat is told once; nothing leaks; the guide follows the pairing and the unpair.
Method TestPairs()
{
	If '..Begin() Quit
	Try {
		Set chatId = 84017734101
		Set name = "Zqdana"
		Set session = ..NewSession()
		Set code = ..NewCode(session, .hash)
		Set before = ##class(OcuTalon.Demo.Guide).Compute(session)
		Do $$$AssertEquals(before.TelegramRow_"|"_before.Step4Variant, "1|unpaired", "before the pairing the guide has the Telegram row and the unpaired variant")
		Set headers = ..HeaderMark()
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set live = ..LiveMark()
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set ..Probe = "zzprobe-"_##class(OcuTalon.Bridge.Ids).NewRef()
		Do ##class(Ens.Util.Log).LogInfo("OcuTalon.Test.Channel.TelegramPair", "TestPairs", ..Probe)

		Do ..Send(..PrivateMessage(chatId, name, "/start "_code))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled the update")
		Do $$$AssertTrue(..WaitLinked(chatId, session), "within WAIT seconds the chat's row is linked to the session")
		Do ..ChatRow(chatId, .chatRef, .linked, .stored)
		Do $$$AssertEquals(stored, name, "and holds the chat's name")
		Set codeRow = ##class(OcuTalon.Data.Pairing).ForCode(hash)
		Do $$$AssertTrue($IsObject(codeRow) && (codeRow.CodeUsedAt '= ""), "the code row is marked used")

		Set pairs = ..PairBodies(headers)
		Do $$$AssertEquals(pairs.%Size(), 1, "since the mark there is exactly one Pair body")
		If pairs.%Size() = 1 Do $$$AssertEquals(pairs.%Get(0).codeHash_"|"_pairs.%Get(0).chatRef_"|"_pairs.%Get(0).origin, hash_"|"_chatRef_"|telegram", "it holds the code's hash, the row's Ref and the origin telegram")
		Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(audit, "OcuTalon", "Pairing", "Pairing", session, "", 1, ..#WAIT)
		Do $$$AssertEquals(entries.%Size(), 1, "one Pairing audit entry names the session")
		If entries.%Size() = 1 Do $$$AssertEquals(entries.%Get(0).data.change_"|"_entries.%Get(0).data.sessionRef_"|"_entries.%Get(0).data.channel, "linked|"_session_"|telegram", "it is linked, for the session, on telegram")
		Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "pairing", 1, ..#WAIT)
		Do $$$AssertEquals(events.%Size(), 1, "one pairing event reaches the session's stream")
		If events.%Size() > 0 Do $$$AssertEquals(events.%Get(0).payload.paired_"|"_events.%Get(0).payload.displayName, "1|"_name, "paired, with the chat's name")
		Set telegram = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(session)).telegram
		Do $$$AssertEquals(telegram.paired_"|"_telegram.displayName, "1|"_name, "/state reports it paired, with the chat's name")

		Set deadline = $ZHorolog + ..#WAIT
		For {
			Set texts = ..TextsTo(chatId)
			If (texts.%Size() >= 1) || ($ZHorolog >= deadline) Quit
			Hang 0.25
		}
		Hang 1
		Set texts = ..TextsTo(chatId)
		Do $$$AssertEquals(texts.%Size(), 1, "the chat gets exactly one message")
		If texts.%Size() > 0 Do $$$AssertEquals(texts.%Get(0), ..#CONFIRMATION, "and it is the confirmation")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("pairing.paired", "", "telegram"), ..#CONFIRMATION, "which is the catalog's pairing.paired")
		Set notices = ..Notifications(headers)
		Do $$$AssertEquals(notices.%Size(), 1, "TelegramIn sent exactly one Notification to Notify")
		If notices.%Size() = 1 {
			Set notice = notices.%Get(0)
			Do $$$AssertEquals(notice.kind_"|"_notice.catalogKey_"|"_notice.chatRef_"|"_notice.sessionRef, "pairing|pairing.paired|"_chatRef_"|"_session, "it is a pairing notice by the row's Ref, for the session")
			Do $$$AssertEquals(notice.slots, "{}", "with no slots")
		}

		Set headerText = ..RowsText("SELECT * FROM Ens.MessageHeader WHERE ID > ?", headers)
		Set bodyText = ..Bodies(headers)
		Set liveOthers = ..RowsText("SELECT Payload FROM OcuTalon_Live.Event WHERE %ID > ? AND Stream <> '"_session_"'", live)
		Set liveOwn = ..RowsText("SELECT Payload FROM OcuTalon_Live.Event WHERE %ID > ? AND Stream = '"_session_"'", live)
		Set everything = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(audit).%ToJSON()
		Do $$$AssertTrue($Find(headerText, "TelegramIn") && $Find(bodyText, hash), "the header scan reads TelegramIn's headers, and the bodies hold the code's hash")
		Do $$$AssertTrue($Find(liveOwn, name), "the session's own pairing event holds the name")
		Do $$$AssertTrue($Find(everything, session), "the audit scan reads the pairing's entry")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(log, ..Probe), 1, "the event-log scan finds its probe")
		For place = "a message header|"_headerText, "a message body|"_bodyText, "a live event of another stream|"_liveOthers, "an audit entry|"_everything {
			For value = "the code|"_code, "the chat id|"_chatId, "the name|"_name {
				Do $$$AssertNotTrue($Find($Piece(place, "|", 2, *), $Piece(value, "|", 2)), $Piece(place, "|", 1)_" holds "_$Piece(value, "|", 1))
			}
		}
		For value = "the code|"_code, "the chat id|"_chatId, "the name|"_name {
			Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(log, $Piece(value, "|", 2)), 0, "the event log holds "_$Piece(value, "|", 1))
		}
		Do $$$AssertNotTrue($Find(liveOwn, code) || $Find(liveOwn, chatId), "the session's own events hold neither the code nor the chat id")

		Set guide = ..WaitGuide(session, "paired")
		Do $$$AssertTrue($IsObject(guide), "a guide.state event follows the pairing")
		If $IsObject(guide) Do $$$AssertEquals(guide."step4Variant"_"|"_+guide."telegramRow", "paired|0", "it has the paired variant and no Telegram row")
		Set command = ##class(OcuTalon.Msg.Command.Unpair).%New()
		Set command.SessionRef = session
		Do $$$AssertStatusOK(##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result), "the page's Unpair is submitted")
		Do $$$AssertEquals(result.Outcome, "unpaired", "and answers unpaired")
		Set guide = ..WaitGuide(session, "unpaired")
		Do $$$AssertTrue($IsObject(guide), "a later guide.state event follows the unpair")
		If $IsObject(guide) Do $$$AssertEquals(guide."step4Variant"_"|"_+guide."telegramRow", "unpaired|1", "it has the unpaired variant and the Telegram row")
	} Catch ex {
		Do $$$AssertTrue(0, "the pairing test failed: "_..Safe(ex))
	}
	Do ..Ending()
}

/// DW-486 and AD-4: a name is kept only while the chat is paired.
Method TestNameOnlyWhilePaired()
{
	If '..Begin() Quit
	Try {
		Set paired = 84017734104
		Set session = ..NewSession()
		Set code = ..NewCode(session, .hash)
		Do ..Send(..PrivateMessage(paired, "Zqdana", "/start "_code))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled the pairing update")
		Do $$$AssertTrue(..WaitLinked(paired, session), "the chat is paired")

		Do ..Send(..PrivateMessage(paired, "", "zz later"))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled a message with no name")
		Do ..ChatRow(paired, , .linked, .stored)
		Do $$$AssertEquals(linked_"|"_stored, session_"|Zqdana", "(a) the paired chat keeps its session and its name")
		Do ..Send(..PrivateMessage(paired, "Zqnew", "zz again"))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled a message with a new name")
		Do ..ChatRow(paired, , .linked, .stored)
		Do $$$AssertEquals(linked_"|"_stored, session_"|Zqnew", "(b) the new name replaces it, and the session stays")
		Do ..Send(..PrivateMessage(paired, "", "/start zzNoSuchCode0000000001"))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled a code with no name from the paired chat")
		Do ..ChatRow(paired, , .linked, .stored)
		Do $$$AssertEquals(linked_"|"_stored, session_"|Zqnew", "(c) a pairing update with no name keeps the paired chat's name and session")
		Do ..AssertTexts(paired, [(..#CONFIRMATION), (..#BAD)], "a paired chat gets the confirmation and the bad-code reply, and no reply to its other messages")
		Do ..Send(..PrivateMessage(paired, "", "/help"))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled a /help from the paired chat")
		Do ..AssertTexts(paired, [(..#CONFIRMATION), (..#BAD), (..#START)], "and the start text for /help, whatever the chat's state")

		Set stranger = 84017734102
		Set headers = ..HeaderMark()
		Do ..Send(..PrivateMessage(stranger, "Zqstranger", "zz hello"))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled a hello from a chat that is not paired")
		Do $$$AssertTrue(..ChatRow(stranger, , .linked, .stored), "(a) the chat has a row")
		Do $$$AssertEquals(linked_"|"_stored, "|", "with no session and no name")
		Do $$$AssertEquals(..PairBodies(headers).%Size(), 0, "and no Pair body was sent")

		Set live = ..LiveMark()
		Set wrong = "zzNoSuchCode0000000000"
		Do ..Send(..PrivateMessage(stranger, "Zqstranger", "/start "_wrong))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled a code that no session has")
		Set pairs = ..PairBodies(headers)
		Do $$$AssertEquals(pairs.%Size(), 1, "(b) one Pair body was sent")
		If pairs.%Size() = 1 Do $$$AssertEquals(pairs.%Get(0).codeHash, ##class(OcuTalon.Data.Pairing).HashCode(wrong), "with the hash of that code")
		Do ..ChatRow(stranger, , .linked, .stored)
		Do $$$AssertEquals(linked_"|"_stored, "|", "nothing is linked and the row holds no name")
		Do $$$AssertEquals($Length(..RowsText("SELECT Type FROM OcuTalon_Live.Event WHERE %ID > ? AND Type = 'pairing'", live)), 0, "and no pairing event was published")

		Do ##class(OcuTalon.Data.Pairing).RecordChat(stranger, "Zqleft", .sc)
		Do $$$AssertStatusOK(sc, "a name is left on the row of a chat that is not paired, as SessionOps.Unlink leaves one (DW-520)")
		Do ..ChatRow(stranger, , .linked, .stored)
		Do $$$AssertEquals(linked_"|"_stored, "|Zqleft", "the row holds that name and no session")
		Do ..Send(..PrivateMessage(stranger, "", "zz after"))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled a message with no name from that chat")
		Do ..ChatRow(stranger, , .linked, .stored)
		Do $$$AssertEquals(linked_"|"_stored, "|", "(d) the chat's next update clears the name left on its row")
	} Catch ex {
		Do $$$AssertTrue(0, "the name test failed: "_..Safe(ex))
	}
	Do ..Ending()
}

/// A bare /start, a /start of spaces and a group chat's /start submit no Pair.
Method TestNoPairWithoutACode()
{
	If '..Begin() Quit
	Try {
		Set session = ..NewSession()
		Set code = ..NewCode(session, .hash)
		Set headers = ..HeaderMark()
		Do ..Send(..PrivateMessage(84017734103, "Zqbare", "/start"))
		Do ..Send(..PrivateMessage(84017734103, "Zqbare", "/start    "))
		Do ..Send(..PrivateMessage(84017734105, "Zqgroup", "/start "_code, "group"))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled the three updates")
		Do $$$AssertEquals(..PairBodies(headers).%Size(), 0, "no Pair body was sent")
		Set codeRow = ##class(OcuTalon.Data.Pairing).ForCode(hash)
		Do $$$AssertTrue($IsObject(codeRow) && (codeRow.CodeUsedAt = ""), "the code row is not marked used")
		Do $$$AssertEquals(..ChatRows(84017734105), 0, "the group chat has no row")
		Do ..ChatRow(84017734103, , .linked, .stored)
		Do $$$AssertEquals(linked_"|"_stored, "|", "the private chat is recorded with no session and no name")
	} Catch ex {
		Do $$$AssertTrue(0, "the no-code test failed: "_..Safe(ex))
	}
	Do ..Ending()
}

/// AC1: a code that is unknown, expired, used or from before a reset gets the bad-code reply; nothing is linked, no event is published,
/// and the rejected audit entries hold no Telegram identity.
Method TestBadCodes()
{
	If '..Begin() Quit
	Try {
		Set chatId = 84017734106
		Set paired = 84017734107
		Set s1 = ..NewSession()
		Set s2 = ..NewSession()
		Set s3 = ..NewSession()
		Set code1 = ..NewCode(s1, .hash1)
		Set code2 = ..NewCode(s2, .hash2, -1)
		Set code3 = ..NewCode(s3, .hash3)
		Do ..Send(..PrivateMessage(paired, "Zqpaired", "/start "_code1))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled the pairing of chat 107")
		Do $$$AssertTrue(..WaitLinked(paired, s1), "chat 107 is paired with S1, and its code is used")
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Pairing WHERE CodeSessionRef = ?", s3)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Session WHERE Ref = ?", s3)
		Hang 1
		Set headers = ..HeaderMark()
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set live = ..LiveMark()
		Set never = "zzNoSuchCode0000000002"

		Do ..Send(..PrivateMessage(chatId, "Zqbad", "/start "_never))
		Do ..Send(..PrivateMessage(chatId, "Zqbad", "/start "_code2))
		Do ..Send(..PrivateMessage(chatId, "Zqbad", "/start "_code1))
		Do ..Send(..PrivateMessage(chatId, "Zqbad", "/start "_code3))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled the four codes")
		Do ..AssertTexts(chatId, [(..#BAD), (..#BAD), (..#BAD), (..#BAD)], "(a) to (d) the chat gets the bad-code reply four times")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("pairing.badCode", "", "telegram"), ..#BAD, "which is the catalog's pairing.badCode")
		Do $$$AssertTrue(..ChatRow(chatId, .chatRef, .linked, .stored), "the chat has a row")
		Do $$$AssertEquals(linked_"|"_stored, "|", "with no session and no name")
		Do ..ChatRow(paired, , .linked)
		Do $$$AssertEquals(linked, s1, "chat 107 is still paired with S1")
		Do $$$AssertEquals(..PairBodies(headers).%Size(), 4, "four Pair bodies were sent")
		Do $$$AssertEquals($Length(..RowsText("SELECT Type FROM OcuTalon_Live.Event WHERE %ID > ? AND Type = 'pairing'", live)), 0, "no pairing event reached any stream")
		Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(audit, "OcuTalon", "Pairing", "Pairing", "", "", 4, ..#WAIT)
		Set seen = ""
		For i = 0:1:entries.%Size() - 1 {
			Set seen = seen _ $Select(seen = "": "", 1: ",") _ entries.%Get(i).data.change _ ":" _ entries.%Get(i).data.reason _ ":" _ entries.%Get(i).data.channel
		}
		Do $$$AssertEquals(seen, "rejected:unknown:telegram,rejected:expired:telegram,rejected:used:telegram,rejected:unknown:telegram", "four rejected Pairing entries on telegram, with the reasons unknown, expired, used and unknown")
		Set holding = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(audit, , , , chatId).%Size() + ##class(OcuTalon.Test.Bridge.AuditLog).Entries(audit, , , , "Zqbad").%Size()
		Do $$$AssertEquals(holding, 0, "no audit entry since the mark holds the chat id or the name")
		Set notices = ..Notifications(headers)
		Do $$$AssertEquals(notices.%Size(), 4, "TelegramIn sent four Notifications to Notify")
		For i = 0:1:notices.%Size() - 1 {
			Set notice = notices.%Get(i)
			Do $$$AssertEquals(notice.kind_"|"_notice.catalogKey_"|"_notice.chatRef_"|"_notice.sessionRef_"|"_notice.slots, "pairing|pairing.badCode|"_chatRef_"||{}", "notice "_(i + 1)_" is pairing.badCode by the row's Ref, with no session and no slots")
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the bad-codes test failed: "_..Safe(ex))
	}
	Do ..Ending()
}

/// AC2 and AC3: the start text, the not-paired text once a minute, no session or model, a row of nothing but the chat, and the purge.
Method TestStrangerReplies()
{
	If '..Begin() Quit
	Try {
		Set stranger = 84017734108
		Set paired = 84017734109
		Set session = ..NewSession()
		Do $$$AssertTrue(..PairChat(paired, "Zqkept", session), "chat 109 is paired with a session")
		Set headers = ..HeaderMark()
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		For text = "/start", "/help", "zz hello", "zz again", "/stop" {
			Do ..Send(..PrivateMessage(stranger, "Zqstranger", text))
		}
		Do $$$AssertTrue(..Handled(), "TelegramIn handled the five messages")
		Do ..AssertTexts(stranger, [(..#START), (..#START), (..#NOTPAIRED)], "the chat gets the start text twice and the not-paired text once: the reply slot is taken for the rest")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("pairing.start", "", "telegram"), ..#START, "the start text is the catalog's pairing.start")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("pairing.notPaired", "", "telegram"), ..#NOTPAIRED, "the not-paired text is the catalog's pairing.notPaired")
		Set unpairs = ..PairBodies(headers, "Unpair")
		Do $$$AssertEquals(unpairs.%Size(), 1, "since the mark there is exactly one Unpair body")
		Do ..ChatRow(stranger, .ref, .linked, .stored)
		If unpairs.%Size() = 1 Do $$$AssertEquals(unpairs.%Get(0).origin_"|"_unpairs.%Get(0).chatRef_"|"_unpairs.%Get(0).sessionRef, "telegram|"_ref_"|", "from origin telegram, by the row's Ref, with no session")
		Do $$$AssertEquals(..Outcomes(headers), "not_paired", "and it was answered not_paired")
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ChatId, Ref, CreatedAt, SeenAt, ReplySlotAt, SessionRef, DisplayName, CodeSessionRef, CodeHash, CodeExpiresAt, CodeUsedAt FROM OcuTalon_Data.Pairing WHERE ChatId = ?", stranger)
		Do $$$AssertTrue(result.%Next(), "the chat's row exists")
		For column = 1:1:5 {
			Do $$$AssertTrue(result.%GetData(column) '= "", "the row holds "_result.%GetMetadata().columns.GetAt(column).colName)
		}
		For column = 6:1:11 {
			Do $$$AssertEquals(result.%GetData(column), "", "the row holds no "_result.%GetMetadata().columns.GetAt(column).colName)
		}

		Set back = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -61)
		Do $$$AssertEquals(##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.Pairing SET ReplySlotAt = ? WHERE ChatId = ?", back, stranger).%SQLCODE, 0, "the chat's reply slot is set 61 s back")
		Set sticker = ..PrivateMessage(stranger, "Zqstranger")
		Do sticker.message.%Remove("text")
		Do sticker.message.%Set("sticker", {"file_id": "zzsticker"})
		Do ..Send(sticker)
		Do $$$AssertTrue(..Handled(), "TelegramIn handled a message with no text")
		Do ..AssertTexts(stranger, [(..#START), (..#START), (..#NOTPAIRED), (..#NOTPAIRED)], "it gets the not-paired text again")
		Do $$$AssertEquals(##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.Pairing SET ReplySlotAt = ? WHERE ChatId = ?", back, stranger).%SQLCODE, 0, "the chat's reply slot is set 61 s back again")
		Do ..Send(..PrivateMessage(stranger, "Zqstranger", "/stop"))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled a /stop with the reply slot free")
		Do ..AssertTexts(stranger, [(..#START), (..#START), (..#NOTPAIRED), (..#NOTPAIRED), (..#NOTPAIRED)], "a /stop answered not_paired gets the not-paired text when the slot is free")
		Do $$$AssertEquals(..Outcomes(headers), "not_paired,not_paired", "both Unpair commands were answered not_paired")
		Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(audit, "OcuTalon", "Pairing").%Size(), 0, "the two not_paired unpairs wrote no audit entry")
		Set notices = ..Notifications(headers)
		Do $$$AssertEquals(notices.%Size(), 5, "TelegramIn sent five Notifications")
		Set keys = ""
		For i = 0:1:notices.%Size() - 1 {
			Set notice = notices.%Get(i)
			Set keys = keys _ $Select(keys = "": "", 1: ",") _ notice.catalogKey
			Do $$$AssertEquals(notice.kind_"|"_notice.chatRef_"|"_notice.sessionRef_"|"_notice.slots, "pairing|"_ref_"||{}", "notice "_(i + 1)_" is by the row's Ref, with no session and no slots")
		}
		Do $$$AssertEquals(keys, "pairing.start,pairing.start,pairing.notPaired,pairing.notPaired,pairing.notPaired", "they are pairing.start twice and pairing.notPaired three times")
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND TargetConfigName = 'Conversation'", headers)
		Do result.%Next()
		Do $$$AssertEquals(+result.%GetData(1), 0, "no request header reaches Conversation")
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TargetConfigName FROM Ens.MessageHeader WHERE ID > ? AND Type = 1 AND SourceConfigName IN ('TelegramIn', 'Notify', 'CommandsIn', 'TelegramOut')", headers)
		Set found = ""
		While result.%Next() {
			If '$ListFind(found, result.%GetData(1)) Set found = found _ $ListBuild(result.%GetData(1))
		}
		Do $$$AssertTrue($ListLength(found) = 3 && $ListFind(found, "Notify") && $ListFind(found, "SessionOps") && $ListFind(found, "TelegramOut"), "the requests of the chat's path go only to Notify, SessionOps and TelegramOut (found "_$ListToString(found)_")")

		Set old = "2001-01-01T00:00:00Z"
		Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.Pairing SET SeenAt = ?, CreatedAt = ? WHERE ChatId IN (?, ?)", old, old, stranger, paired)
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Core).Purge(3650), "the Core area's Purge runs")
		Do $$$AssertEquals(..ChatRows(stranger), 0, "the aged row with no session is gone")
		Do $$$AssertEquals(..ChatRows(paired), 1, "the aged row with a session stays")
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Pairing WHERE CodeSessionRef = ?", session)
		Do result.%Next()
		Do $$$AssertEquals(+result.%GetData(1), 1, "and so does the session's unaged code row")
	} Catch ex {
		Do $$$AssertTrue(0, "the stranger test failed: "_..Safe(ex))
	}
	Do ..Ending()
}

/// AC4: /stop unpairs from the chat, and the page's Unpair tells the chat.
Method TestStop()
{
	If '..Begin() Quit
	Try {
		Set chatId = 84017734120
		Set s1 = ..NewSession()
		Do $$$AssertTrue(..PairChat(chatId, "Zqstop", s1), "chat 120 is paired with S1")
		Set headers = ..HeaderMark()
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set before = ..PairingEvents(s1).%Size()
		Do ..Send(..PrivateMessage(chatId, "Zqstop", "/stop"))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled /stop")
		Set unpairs = ..PairBodies(headers, "Unpair")
		Do ..ChatRow(chatId, .ref, .linked, .stored)
		Do $$$AssertEquals(unpairs.%Size(), 1, "there is one Unpair body")
		If unpairs.%Size() = 1 Do $$$AssertEquals(unpairs.%Get(0).origin_"|"_unpairs.%Get(0).chatRef_"|"_unpairs.%Get(0).sessionRef, "telegram|"_ref_"|", "from origin telegram, by the row's Ref, with no session")
		Do $$$AssertEquals(linked_"|"_stored, "|", "the row has no session and no name")
		Do $$$AssertEquals(..AuditOf(audit, s1, 1), "unlinked:stop:telegram", "one unlinked audit entry for S1, reason stop, channel telegram")
		Do ..AssertEventsSince(s1, before, "0:", "one pairing event with paired 0 reaches S1's stream")
		Set telegram = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(s1)).telegram
		Do $$$AssertEquals(+telegram.paired, 0, "/state reports S1 not paired")
		Do ..AssertTexts(chatId, [(..#CONFIRMATION), (..#STOPPED)], "the chat got the confirmation and the stopped text")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("pairing.stopped", "", "telegram"), ..#STOPPED, "which is the catalog's pairing.stopped")
		Set notices = ..Notifications(headers)
		Do $$$AssertEquals(notices.%Size(), 1, "TelegramIn sent one Notification")
		If notices.%Size() = 1 {
			Set notice = notices.%Get(0)
			Do $$$AssertEquals(notice.kind_"|"_notice.catalogKey_"|"_notice.chatRef_"|"_notice.sessionRef_"|"_notice.slots, "pairing|pairing.stopped|"_ref_"|"_s1_"|{}", "it is pairing.stopped, by the row's Ref, for the session the chat left")
		}

		Set page = 84017734121
		Set s2 = ..NewSession()
		Do $$$AssertTrue(..PairChat(page, "Zqpage", s2), "chat 121 is paired with S2")
		Set headers = ..HeaderMark()
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set before = ..PairingEvents(s2).%Size()
		Set command = ##class(OcuTalon.Msg.Command.Unpair).%New()
		Set command.SessionRef = s2
		Do $$$AssertStatusOK(##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result), "the page's Unpair is submitted")
		Do $$$AssertEquals(result.Outcome, "unpaired", "and answers unpaired")
		Do ..AssertTexts(page, [(..#CONFIRMATION), (..#FROMPAGE)], "the chat got the confirmation and the from-page text")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("pairing.unpairedFromPage", "", "telegram"), ..#FROMPAGE, "which is the catalog's pairing.unpairedFromPage")
		Do $$$AssertEquals(..AuditOf(audit, s2, 1), "unlinked:page:web", "one unlinked audit entry for S2, reason page, channel web")
		Do ..AssertEventsSince(s2, before, "0:", "one pairing event with paired 0 reaches S2's stream")
		Do $$$AssertEquals(..Notifications(headers).%Size(), 0, "TelegramIn sent no Notification for it")
	} Catch ex {
		Do $$$AssertTrue(0, "the stop test failed: "_..Safe(ex))
	}
	Do ..Ending()
}

/// AC5: a chat keeps at most one live pairing: a chat that pairs with another session leaves the first, and a session that pairs a
/// second chat drops the first chat, which is treated as unpaired from then on.
Method TestOneLivePairing()
{
	If '..Begin() Quit
	Try {
		Set a = ..NewSession()
		Set b = ..NewSession()
		Set mover = 84017734122
		Do $$$AssertTrue(..PairChat(mover, "Zqmover", a), "chat 122 is paired with A")
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set beforeA = ..PairingEvents(a).%Size()
		Set beforeB = ..PairingEvents(b).%Size()
		Do $$$AssertTrue(..PairChat(mover, "Zqmover", b), "chat 122 then pairs with B")
		Do ..ChatRow(mover, , .linked)
		Do $$$AssertEquals(linked_"|"_..ChatRows(mover), b_"|1", "its row is linked to B and is its only row")
		Do ..AssertEventsSince(a, beforeA, "0:", "one pairing event with paired 0 reaches A's stream")
		Do ..AssertEventsSince(b, beforeB, "1:Zqmover", "one with paired 1 reaches B's")
		Set telegram = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(a)).telegram
		Do $$$AssertEquals(+telegram.paired, 0, "/state reports A not paired")
		Do $$$AssertEquals(..AuditOf(audit, a, 1), "unlinked:moved:telegram", "A has an unlinked entry, reason moved")
		Do $$$AssertEquals(..AuditOf(audit, b, 1), "linked:code:telegram", "B has a linked entry")
		Do ..AssertTexts(mover, [(..#CONFIRMATION), (..#CONFIRMATION)], "the chat got the confirmation twice and no unpair notice: it moved itself")

		Set first = 84017734123
		Set second = 84017734124
		Do $$$AssertTrue(..PairChat(first, "Zqfirst", a), "chat 123 is paired with A")
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set beforeA = ..PairingEvents(a).%Size()
		Do $$$AssertTrue(..PairChat(second, "Zqsecond", a), "chat 124 is paired with A")
		Do ..ChatRow(first, , .linked)
		Do $$$AssertEquals(linked, "", "chat 123 has no session")
		Do ..ChatRow(second, .secondRef)
		Set own = ##class(OcuTalon.Data.Ownership).Pairing(a, .sc)
		Do $$$AssertEquals($Select($IsObject(own): own.Ref, 1: ""), secondRef, "A's pairing is chat 124's row")
		Do ..AssertEventsSince(a, beforeA, "0:,1:Zqsecond", "A's stream got a pairing event with paired 0, then one with paired 1 and the new name")
		Set telegram = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(a)).telegram
		Do $$$AssertEquals(+telegram.paired_"|"_telegram.displayName, "1|Zqsecond", "/state reports A paired, with the new name")
		Do $$$AssertEquals(..AuditOf(audit, a, 2), "unlinked:other_chat:telegram,linked:code:telegram", "A has an unlinked entry, reason other_chat, and a linked one")
		Do ..Send(..PrivateMessage(first, "", "zz still here"))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled a message from chat 123")
		Do ..AssertTexts(first, [(..#CONFIRMATION), (..#OTHERCHAT), (..#NOTPAIRED)], "chat 123 got the confirmation, the other-chat notice and then the not-paired text")
		Do $$$AssertEquals(##class(OcuTalon.Msg.Catalog).Render("pairing.otherChatPaired", "", "telegram"), ..#OTHERCHAT, "the notice is the catalog's pairing.otherChatPaired")
		Do ..ChatRow(first, , .linked, .stored)
		Do $$$AssertEquals(linked_"|"_stored, "|", "chat 123's row holds no session and no name")
	} Catch ex {
		Do $$$AssertTrue(0, "the one-live-pairing test failed: "_..Safe(ex))
	}
	Do ..Ending()
}

}
