/// Live tests of the pairing path of TelegramIn against the CI mock (Story 12.4; FR-15, FR-18, FR-19, FR-9, AD-1, AD-4, AD-14, AD-17,
/// AD-32, DW-486). THESE TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), like OcuTalon.Test.Channel.LiveCase, which they extend:
/// TelegramIn and TelegramOut run on the production against the mock, the Telegram seam is 1 and demo mode is on (a test fails with that
/// reason when it is not). Each test makes fixture sessions (zztgpair...) that watch nothing, stores their codes as the web route does
/// (Pairing.StoreCode with the code's hash), queues updates through the mock's /updates, and waits until TelegramIn has handled them (the
/// kept offset). The fixture chat ids are 840177341xx. Each test ends with Ending, on every path.
///   - TestPairs: a valid code pairs the chat with the session (the chat's row, the used mark, the Pair command, the linked audit entry,
///     the pairing event and /state), the chat gets the one confirmation, no store holds the code, the chat id or the name, and the guide
///     follows the pairing and the page's Unpair;
///   - TestNameOnlyWhilePaired: a paired chat keeps its name through later messages with no name (a pairing update too) and takes a new one, and a chat that is
///     not paired never keeps a name, also after a code that links nothing, and its next update clears a name left on its row;
///   - TestNoPairWithoutACode: a bare /start, a /start of spaces and a group chat's /start submit no Pair.
Class OcuTalon.Test.Channel.TelegramPair Extends OcuTalon.Test.Channel.LiveCase
{

/// The longest, in seconds, to wait for an effect of a handled update.
Parameter WAIT = 10;

/// The confirmation's text, the oracle of the catalog's pairing.paired.
Parameter CONFIRMATION = "You're paired with your OcuTalon session; notifications, reminders and approval requests will arrive here (send /stop to unpair).";

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
	Do ..Chat("84017734101,84017734102,84017734103,84017734104,84017734105")
	Do ..DropChats("84017734101,84017734102,84017734103,84017734104,84017734105")
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

/// Stores a new code for the session as the web route does (its hash, valid for 600 s); the code is code and its hash is hash.
Method NewCode(session As %String, Output hash As %String) As %String [ Private ]
{
	Set code = "zzpair"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set hash = ##class(OcuTalon.Data.Pairing).HashCode(code)
	Set expires = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)
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

}
