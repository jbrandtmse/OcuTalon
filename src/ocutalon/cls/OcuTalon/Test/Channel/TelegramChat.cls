Include Ensemble

/// Live tests of a paired Telegram chat's conversation and notifications over the running production and the CI mock (Story 12.6; FR-15, FR-20,
/// FR-24, FR-25, FR-34, FR-40, NFR-6, AD-4, AD-14, AD-20, AD-26, AD-28, AD-30, AD-32, DW-30, DW-295). THESE TESTS RUN IN THROWAWAY STACKS AND IN
/// CI ONLY (Rule 21), like OcuTalon.Test.Channel.LiveCase, which they extend. NEEDS: the running OcuTalon.Production and the CI mock with its
/// dummy token, the Telegram seam (set and put back by LiveCase.BeginPairing) and demo mode on. Where any is missing, every test fails with the
/// reason. OnBeforeAllTests points the runners' keys at the mock (as Test.Schedule.ReminderChat does) and runs BeginPairing for the fixture
/// chats 84017734130 to 84017734136; OnAfterAllTests runs EndPairing first (the turns of the fixture sessions are settled while the keys
/// still point at the mock, then adopted and removed with their Decision rows; its status, the items' stop and the mock's reset, is part
/// of the class's status), then puts the keys back and removes the AI sessions that the turns saved. A fixture session (zztgchat...) is paired with its chat
/// through the real /start path (LiveCase.PairChat). The mock numbers its default sendMessage answers 1, 2, 3, ... after its reset, so a
/// message's id is its position among the sendMessage calls.
///   - TestTurn: a paired chat's text is a turn. In one poll answer, the paired chat asks "Is everything OK?" with the scenario
///     checks-false-all-clear armed and an unpaired chat says hello. One Item goes from TelegramIn to Conversation (channel telegram,
///     provenance user, the text as sent, no ClientId, no chat id and no name; the header's SessionId is the session's thread and its
///     SuperSession the session's TraceRef), the Turn of channel telegram is done, chat.message says so, Notify sends the reply to WebChatOut
///     and TelegramOut, and the chat gets the reply followed by the check sentence of the key checks.nothingWatched and never an all-clear.
///     The telegram Delivery row holds <ChatRef>:<message_id of the reply>. The stranger gets the not-paired text, and its Notification's header
///     has no SuperSession and a session of its own: TelegramIn clears %SessionId and %SuperSession after a turn;
///   - TestRefused: with onlineDemo 1 and the session's window full, two messages are refused with a refused Turn each, no Item and no model
///     request; one allowance Notification (no ChatRef) goes to Notify, which sends it to WebChatOut and TelegramOut and not to SimPhoneOut; the
///     chat gets exactly one text for it and the web chat one allowance card; onlineDemo and the window are put back on every path;
///   - TestQueued: a message that arrives while a turn runs is queued, starts after the first is done, reaches the model as the user's own
///     message (never inside a tool result), and the chat gets the replies in order;
///   - TestNotices: one notification at a time for every Watch incident and result key and six Core keys: the chat's text is the simulated
///     phone's (or the phone-channel rendering for the two allowance keys, which the phone does not get), each has its telegram Delivery row
///     with the kind, the approval Ref and <ChatRef>:<message_id>, and an answered notification, once TelegramOut has handled it, has sent
///     nothing;
///   - TestEmptyTurn: a paired chat's messages with no text (a sticker, a photo with a caption) and one of white space only make no Item to
///     Conversation, no Turn, no Notification and no text to the chat;
///   - TestNoIdentity: after a Telegram turn, a pairing and two notices, no header, body, agent step, event-log row or audit entry holds the
///     chat's id or name, and no live event holds the chat's id; only the Pairing row holds both.
Class OcuTalon.Test.Channel.TelegramChat Extends OcuTalon.Test.Channel.LiveCase
{

/// The fixture chat ids.
Parameter CHATS = "84017734130,84017734131,84017734132,84017734133,84017734134,84017734135,84017734136";

/// The longest, in seconds, to wait for a turn.
Parameter WAITTURN = 90;

/// The question that the scenario checks-false-all-clear answers.
Parameter ASK = "Is everything OK? [[mock:checks-false-all-clear]]";

/// The first message of TestQueued, which selects the scenario telegram-turn-held.
Parameter HELD = "zz first [[mock:telegram-turn-held]]";

/// The reply of the held scenario's Chat request.
Parameter HELDREPLY = "The CI mock answers the first Telegram message.";

/// The reason why every test fails, or "".
Property Missing As %String(MAXLEN = 400);

/// 1 while the runners' keys point at the CI mock.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// 1 while BeginPairing has run and EndPairing has not.
Property Begun As %Boolean [ InitialExpression = 0 ];

/// The mark of the saved AI sessions when the class began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set ..Missing = ##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()
	If ..Missing '= "" Quit $$$OK
	Set ..Pointed = 1
	Set pointed = ##class(OcuTalon.Test.Agent.RunnerFixture).PointKeys()
	If $$$ISERR(pointed) {
		Set ..Missing = "The entries of the runners could not be pointed at the CI mock key variable: " _ $SYSTEM.Status.GetErrorText(pointed)
		Quit $$$OK
	}
	Set ..Missing = ..BeginPairing(..#CHATS)
	Set ..Begun = (..Missing = "")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Set sc = $$$OK
	Do ##class(OcuTalon.Test.Contract.Mock).Arm("checks-false-all-clear", "")
	Do ##class(OcuTalon.Test.Contract.Mock).Arm("telegram-turn-held", "")
	If ..Begun {
		Set ..Begun = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ..EndPairing())
		If '..WaitJobs("TelegramIn", 0) Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "TelegramIn still has a job after the class"))
	}
	If ..Pointed {
		Set ..Pointed = 0
		Set restored = ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys()
		Set sc = $SYSTEM.Status.AppendStatus(sc, restored)
		If '##class(OcuTalon.Test.Agent.RunnerFixture).KeysAre(##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER) {
			Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The entries of the runners do not hold the placeholder of the Provider step after the restore"))
		}
		If '##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords() {
			Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The runners did not record the restored keys"))
		}
	}
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Test.Contract.Mock).Arm("checks-false-all-clear", "")
	Do ##class(OcuTalon.Test.Contract.Mock).Arm("telegram-turn-held", "")
	Quit $$$OK
}

/// 1 when the class is set up; otherwise the test fails with the reason.
Method Go() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// A fixture session (zztgchat...) that the chat is paired with through the real /start path: its Ref, and the chat row's Ref.
Method Paired(chatId As %String, name As %String, Output chatRef As %String) As %String [ Private ]
{
	Set session = ..NewSession("zztgchat")
	Do $$$AssertTrue(..PairChat(chatId, name, session), "chat "_chatId_" is paired with its session")
	Do ..ChatRow(chatId, .chatRef)
	Quit session
}

/// The Items from TelegramIn to Conversation after the mark, once there are count of them or after the seconds.
Method WaitItems(mark As %Integer, count As %Integer, seconds As %Numeric = 20) As %DynamicArray [ Private ]
{
	Set deadline = $ZHorolog + seconds
	For {
		Set items = ..Items(mark)
		If (items.%Size() >= count) || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit items
}

/// The session's Turn of the Item once it has the state (done, running or queued), or the Turn as it is after the seconds ("" if none). The
/// row is reloaded on every read, because a Turn that this process holds open is not read again from disk by an open.
Method WaitTurn(itemId As %String, session As %String, state As %String, seconds As %Numeric = {..#WAITTURN}) As OcuTalon.Data.Turn [ Private ]
{
	Set deadline = $ZHorolog + seconds
	For {
		Set turn = ##class(OcuTalon.Data.Ownership).TurnOfItem(itemId, session)
		If $IsObject(turn) Do turn.%Reload()
		If ($IsObject(turn) && (turn.State = state)) || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit turn
}

/// The position of the last sendMessage to the chat with this text among all the sendMessage calls: the message_id that the mock gave it.
/// "" when there is none.
Method IdOf(chatId As %String, text As %String) As %String [ Private ]
{
	Set id = "", count = 0
	Set iterator = ..CallsOf("sendMessage").%GetIterator()
	While iterator.%GetNext(, .call) {
		Set count = count + 1
		If (call.params."chat_id" = chatId) && (call.params.text = text) Set id = count
	}
	Quit id
}

/// The Delivery rows of the session of the channel as "<kind>|<approval>|<ChannelMessageId>", oldest first, comma-separated; the rows of
/// kind skip (when given) are left out.
Method Rows(session As %String, channel As %String, skip As %String = "") As %String [ Private ]
{
	Set found = ""
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		If (row.Channel = channel) && ((skip = "") || (row.Kind '= skip)) Set found = found _ $Select(found = "": "", 1: ",") _ row.Kind_"|"_row.ApprovalRef_"|"_row.ChannelMessageId
	}
	Quit found
}

/// The number of Delivery rows of the session of the channel and kind (any kind for "*"), once there are count of them or after the seconds.
Method WaitRows(session As %String, channel As %String, kind As %String, count As %Integer, seconds As %Numeric = 20) As %Integer [ Private ]
{
	Set deadline = $ZHorolog + seconds
	For {
		Set found = 0
		Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
		For i = 1:1:rows.Count() {
			If (rows.GetAt(i).Channel = channel) && ((kind = "*") || (rows.GetAt(i).Kind = kind)) Set found = found + 1
		}
		If (found >= count) || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit found
}

/// The targets that Notify sent a body of the class to, for the body ids (a $List) after the header mark: sorted, comma-separated.
Method TargetsOf(mark As %Integer, class As %String, ids As %List) As %String [ Private ]
{
	Kill targets
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TargetConfigName, MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'Notify' AND MessageBodyClassName = ? ORDER BY ID", mark, class)
	While result.%Next() {
		If $ListFind(ids, result.%GetData(2)) Set targets(result.%GetData(1)) = ""
	}
	Set out = "", target = ""
	For {
		Set target = $Order(targets(target))
		If target = "" Quit
		Set out = out _ $Select(out = "": "", 1: ",") _ target
	}
	Quit out
}

/// The ids of the Outbound bodies of the session that Notify sent after the header mark, as a $List.
Method OutboundIds(mark As %Integer, session As %String) As %List [ Private ]
{
	Set ids = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'Notify' AND MessageBodyClassName = 'OcuTalon.Msg.Outbound'", mark)
	While result.%Next() {
		Set id = result.%GetData(1)
		If $ListFind(ids, id) Continue
		Set body = ##class(OcuTalon.Msg.Outbound).%OpenId(id)
		If $IsObject(body) && (body.SessionRef = session) Set ids = ids _ $ListBuild(id)
	}
	Quit ids
}

/// A Notification of the kind for the session: the catalog key, the slots (a dynamic object) and the approval Ref.
ClassMethod Notification(session As %String, kind As %String, key As %String, slots As %DynamicObject, approvalRef As %String = "") As OcuTalon.Msg.Notification [ Private ]
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = session
	Set notification.Kind = kind
	Set notification.CatalogKey = key
	Set notification.Slots = slots.%ToJSON()
	Set notification.ApprovalRef = approvalRef
	Quit notification
}

/// Sends the Notification to Notify through a host service, under the session's TraceRef (the pattern of Test.Demo.SimPhoneOut.TestThroughNotify).
Method ToNotify(notification As OcuTalon.Msg.Notification, trace As %String) As %Boolean [ Private ]
{
	Set sc = ##class(Ens.Director).CreateBusinessService("SimMailboxIn", .service)
	If $$$ISOK(sc) {
		Set service.%SuperSession = trace
		Set sc = service.SendRequestAsync("Notify", notification)
	}
	Do $$$AssertStatusOK(sc, "the "_notification.CatalogKey_" Notification is sent to Notify")
	Quit $$$ISOK(sc)
}

/// The JSON XData block of a class, as a dynamic object (Test.Msg.Catalog's Fixtures, or the Entries of a catalog class).
ClassMethod XData(class As %String, name As %String) As %DynamicObject [ Private ]
{
	Set definition = ##class(%Dictionary.XDataDefinition).%OpenId(class_"||"_name)
	If '$IsObject(definition) Quit {}
	Quit {}.%FromJSON(definition.Data)
}

/// Gives the session's allowance window Limit() entries within its hour, so that the next message is refused (full = 1), or empties it.
Method Fill(session As %String, full As %Boolean) [ Private ]
{
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set times = ""
	If full {
		For i = 0:1:##class(OcuTalon.Core.Allowance).Limit() - 1 Set times = times _ $ListBuild(##class(OcuTalon.Data.Time).AddSeconds(now, i - 3000))
	}
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Set row.AllowanceTimes = times
	Set row.AllowanceUntil = ""
	Do $$$AssertStatusOK(row.%Save(), "the session's window "_$Select(full: "is full", 1: "is emptied"))
}

/// A paired chat's text is the session's turn; the reply and the check sentence reach the chat (AC1, DW-295).
Method TestTurn()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734130
		Set stranger = 84017734131
		Set session = ..Paired(chatId, "Zqchat", .chatRef)
		Do ..ChatRow(stranger, .strangerRef)
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).Arm("checks-false-all-clear", 1), "the scenario checks-false-all-clear is armed at 1")
		Set mark = ..HeaderMark()
		Set batch = [(..PrivateMessage(chatId, "Zqchat", ..#ASK)), (..PrivateMessage(stranger, "Zqstranger", "zz hello"))]
		Do $$$AssertTrue(..QueueUpdates(batch), "two updates are queued for one poll answer")
		Set ..Sent = ..Sent + 2
		Do $$$AssertTrue(..Handled(), "TelegramIn handled both")
		Do ..ChatRow(stranger, .strangerRef)

		Set items = ..WaitItems(mark, 1)
		Do $$$AssertEquals(items.%Size(), 1, "one Item goes from TelegramIn to Conversation")
		If items.%Size() '= 1 Quit
		Set item = items.%Get(0)
		Do $$$AssertEquals(item.sessionRef_"|"_item.channel_"|"_item.provenance_"|"_item.fromGuide_"|"_item.clientId, session_"|telegram|user|0|", "it is the session's, of channel telegram and provenance user, with FromGuide 0 and no ClientId")
		Do $$$AssertEquals(item.text, ..#ASK, "its text is the message as sent")
		Do $$$AssertTrue(item.itemId '= "", "and it has an ItemId")
		Do $$$AssertNotTrue($Find(item.xml, chatId) || $Find(item.xml, "Zqchat"), "its body holds neither the chat id nor the name")
		Set turn = ..WaitTurn(item.itemId, session, "done")
		Do $$$AssertTrue($IsObject(turn), "the Item made a Turn")
		If '$IsObject(turn) Quit
		Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
		Do $$$AssertTrue(row.ThreadSessionId '= "", "the session has a trace thread for the day")
		Do $$$AssertEquals(item.sessionId_"|"_item.superSession, row.ThreadSessionId_"|"_row.TraceRef, "the header's SessionId is the session's thread and its SuperSession the session's TraceRef")
		Do $$$AssertEquals(turn.State_"|"_turn.Channel_"|"_turn.FallbackReason, "done|telegram|", "the Turn of the session is done, of channel telegram, with no fallback")
		Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "chat.message", 1, 15)
		Set seen = ""
		For i = 0:1:events.%Size() - 1 {
			If events.%Get(i).payload.channel = "telegram" Set seen = seen _ events.%Get(i).payload.state _ ","
		}
		Do $$$AssertTrue($Find(seen, "done,"), "a chat.message event on the session's stream has channel telegram: "_seen)

		Set nothing = ##class(OcuTalon.Msg.Catalog).Render("checks.nothingWatched", "", "telegram")
		Do $$$AssertEquals(turn.CheckKey, "checks.nothingWatched", "the session watches nothing, so the check key is checks.nothingWatched")
		Set expected = turn.ReplyText _ $Char(10, 10) _ nothing
		Set texts = ..TextsAfter(chatId, 2)
		Do $$$AssertEquals(texts.%ToJSON(), [(##class(OcuTalon.Test.Channel.TelegramPair).#CONFIRMATION), (expected)].%ToJSON(), "the chat's texts are the confirmation, then the reply and the check sentence")
		Do $$$AssertNotTrue($Find(expected, "Everything I checked passed."), "the reply holds no all-clear")
		Set ids = ..OutboundIds(mark, session)
		Do $$$AssertEquals(..TargetsOf(mark, "OcuTalon.Msg.Outbound", ids), "TelegramOut,WebChatOut", "Notify sends the reply to WebChatOut and TelegramOut")
		Do $$$AssertEquals(..Rows(session, "telegram", "pairing"), "||"_chatRef_":"_..IdOf(chatId, expected), "the telegram Delivery row of the reply holds <ChatRef>:<message_id>")
		Do $$$AssertEquals(..WaitRows(session, "web", "", 1), 1, "and WebChatOut has the reply's row")

		Set texts = ..TextsAfter(stranger, 1)
		Do $$$AssertEquals(texts.%ToJSON(), [(##class(OcuTalon.Test.Channel.TelegramPair).#NOTPAIRED)].%ToJSON(), "the unpaired chat gets the not-paired text")
		Set notices = ..Notifications(mark)
		Set found = 0
		For i = 0:1:notices.%Size() - 1 {
			If notices.%Get(i).chatRef '= strangerRef Continue
			Set found = found + 1
			Do $$$AssertEquals(notices.%Get(i).superSession, "", "its Notification's header has no SuperSession")
			Do $$$AssertTrue((notices.%Get(i).sessionId '= "") && (notices.%Get(i).sessionId '= row.ThreadSessionId), "and a session of its own, not the session's thread")
		}
		Do $$$AssertEquals(found, 1, "TelegramIn sent one Notification for the unpaired chat")
	} Catch ex {
		Do $$$AssertTrue(0, "the turn test failed: "_..Safe(ex))
	}
}

/// A message over the allowance queues nothing and the first refusal gives one notice to the web chat and the paired chat (AC2).
Method TestRefused()
{
	If '..Go() Quit
	Set settings = "OcuTalon.Data.Public.Settings"
	Set saved = $ClassMethod(settings, "Get", "onlineDemo")
	Set session = ""
	Try {
		Set chatId = 84017734132
		Set session = ..Paired(chatId, "Zqrefused", .chatRef)
		Do $ClassMethod(settings, "Set", "onlineDemo", 1)
		Do ..Fill(session, 1)
		Set mark = ..HeaderMark()
		Set log = ##class(OcuTalon.Test.Contract.Mock).LogMark()
		Do ..Send(..PrivateMessage(chatId, "", "zz over the limit"))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled the first message over the limit")
		Set texts = ..TextsAfter(chatId, 2)
		Do $$$AssertEquals(texts.%Size(), 2, "the chat gets the confirmation and exactly one text more")
		Set notices = ..Notifications(mark)
		Do $$$AssertEquals(notices.%Size(), 1, "one Notification goes from TelegramIn to Notify")
		If notices.%Size() = 1 {
			Set notice = notices.%Get(0)
			Do $$$AssertEquals(notice.kind_"|"_notice.catalogKey_"|"_notice.sessionRef_"|"_notice.chatRef, "allowance|conversation.sessionAllowance|"_session_"|", "it is the allowance notice of the session, with no ChatRef")
			Set expected = ##class(OcuTalon.Msg.Catalog).Render(notice.catalogKey, notice.slots, "telegram", .sc)
			Do $$$AssertStatusOK(sc, "the catalog renders it for Telegram")
			If texts.%Size() = 2 Do $$$AssertEquals(texts.%Get(1), expected, "the chat's text is that rendering")
			Do $$$AssertEquals(..TargetsOf(mark, "OcuTalon.Msg.Notification", $ListBuild(notice.id)), "TelegramOut,WebChatOut", "Notify sends it to WebChatOut and TelegramOut, and not to SimPhoneOut")
		}
		Do ..Send(..PrivateMessage(chatId, "", "zz still over"))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled the second message over the limit")
		Set texts = ..TextsAfter(chatId, 2)
		Do $$$AssertEquals(texts.%Size(), 2, "the second refusal adds no text")
		Do $$$AssertEquals(..Notifications(mark).%Size(), 1, "and no second Notification")
		Do $$$AssertEquals(..WaitRows(session, "web", "allowance", 1), 1, "the web chat has one allowance card")
		Set turns = ##class(OcuTalon.Data.Ownership).Turns(session)
		Do $$$AssertEquals(turns.Count(), 2, "the session has two Turns")
		For i = 1:1:turns.Count() {
			Set turn = turns.GetAt(i)
			Do $$$AssertEquals(turn.State_"|"_turn.Channel_"|"_turn.TriageDecisionRef_"|"_turn.TurnDecisionRef, "refused|telegram||", "turn "_i_" is refused, of channel telegram, with no decision")
		}
		Do $$$AssertEquals(..Items(mark).%Size(), 0, "no Item goes to Conversation")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(log, .entries), "the mock's log is read")
		Set requests = 0
		Set iterator = entries.%GetIterator()
		While iterator.%GetNext(, .entry) {
			If entry.path = "/v1/messages" Set requests = requests + 1
		}
		Do $$$AssertEquals(requests, 0, "and no model is called")
	} Catch ex {
		Do $$$AssertTrue(0, "the refused test failed: "_..Safe(ex))
	}
	Do $ClassMethod(settings, "Set", "onlineDemo", saved)
	If session '= "" {
		Try {
			Do ..Fill(session, 0)
		} Catch {
		}
	}
}

/// A message that arrives while a turn runs queues behind it and reaches the model as the user's own message (AC3).
Method TestQueued()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734133
		Set session = ..Paired(chatId, "Zqqueued", .chatRef)
		Set second = "zz second while the first runs"
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).Arm("telegram-turn-held", 1), "the scenario telegram-turn-held is armed at 1")
		Set mark = ..HeaderMark()
		Set log = ##class(OcuTalon.Test.Contract.Mock).LogMark()
		Do ..Send(..PrivateMessage(chatId, "", ..#HELD))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled the first message")
		Set items = ..WaitItems(mark, 1)
		Do $$$AssertEquals(items.%Size(), 1, "one Item goes to Conversation")
		If items.%Size() '= 1 Quit
		Set first = ..WaitTurn(items.%Get(0).itemId, session, "running", 20)
		Do $$$AssertEquals($Select($IsObject(first): first.State, 1: ""), "running", "the first Turn is running")
		Do ..Send(..PrivateMessage(chatId, "", second))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled the second message")
		Set items = ..WaitItems(mark, 2)
		Do $$$AssertEquals(items.%Size(), 2, "a second Item goes to Conversation")
		If items.%Size() '= 2 Quit
		Set two = ..WaitTurn(items.%Get(1).itemId, session, "queued", 10)
		Do $$$AssertEquals($Select($IsObject(two): two.State, 1: ""), "queued", "the second Turn is queued")
		If $IsObject(first) {
			Do first.%Reload()
			Do $$$AssertEquals(first.State, "running", "while the first is still running")
		}
		Set first = ..WaitTurn(items.%Get(0).itemId, session, "done")
		Set two = ..WaitTurn(items.%Get(1).itemId, session, "done")
		Do $$$AssertEquals($Select($IsObject(first): first.State, 1: "")_"|"_$Select($IsObject(two): two.State, 1: ""), "done|done", "both Turns reach done, the second after the first")
		If '$IsObject(first) || '$IsObject(two) Quit
		Do $$$AssertEquals(first.ReplyText, ..#HELDREPLY, "the first reply is the scenario's")

		Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(log, .entries), "the mock's log is read")
		Set own = [], leaked = 0
		Set iterator = entries.%GetIterator()
		While iterator.%GetNext(, .entry) {
			If (entry.method '= "POST") || (entry.path '= "/v1/messages") Continue
			Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(entry)
			Set position = 0
			While $ListNext(results, position, one) {
				If $Find(one, second) Set leaked = leaked + 1
			}
			Set messages = $ListFromString(##class(OcuTalon.Test.Agent.RunnerFixture).Messages(entry), $Char(1))
			Set newest = ""
			For i = $ListLength(messages):-1:1 {
				Set message = $List(messages, i)
				If ($Extract(message, 1, 5) = "user:") && ($Length(message) > 5) {
					Set newest = $Extract(message, 6, *)
					Quit
				}
			}
			If $Extract(newest, *-$Length(second)-1, *) = ($Char(10, 10)_second) Do own.%Push(entry)
		}
		Do $$$AssertTrue(own.%Size() >= 2, "the second turn made model requests whose newest user message is its Agent.Input text")
		Do $$$AssertEquals(leaked, 0, "no tool result of any request holds the second message")
		If own.%Size() > 0 Do $$$AssertTrue($ListLength(##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(own.%Get(own.%Size() - 1))) >= 1, "the last of them carries a tool result")
		Set texts = ..TextsAfter(chatId, 3)
		Do $$$AssertEquals(texts.%ToJSON(), [(##class(OcuTalon.Test.Channel.TelegramPair).#CONFIRMATION), (first.ReplyText), (two.ReplyText)].%ToJSON(), "the chat's texts are the confirmation, the first reply and the second reply, in order")
	} Catch ex {
		Do $$$AssertTrue(0, "the queued test failed: "_..Safe(ex))
	}
}

/// Every notice reaches the chat as the simulated phone shows it, with its Delivery row (AC4, AC5).
Method TestNotices()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734134
		Set session = ..Paired(chatId, "Zqnotices", .chatRef)
		Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
		Set fixtures = ..XData("OcuTalon.Test.Msg.Catalog", "Fixtures")
		Set keys = ""
		Set entries = ..XData("OcuTalon.Msg.Catalog.Watch", "Entries")
		Set iterator = entries.%GetIterator()
		While iterator.%GetNext(.key) {
			If ($Extract(key, 1, 9) = "incident.") || ($Extract(key, 1, 7) = "result.") Set keys = keys _ $ListBuild(key)
		}
		Do $$$AssertEquals($ListLength(keys), 12, "there are 12 Watch notice keys")
		For core = "notice.tellNow", "notice.tellNowFallback", "reminder.due", "reminder.late", "conversation.sessionAllowance", "conversation.dailyCap" Set keys = keys _ $ListBuild(core)
		Set expectedRows = "", approvals = 0, position = 0, phones = 0
		While $ListNext(keys, position, key) {
			Set fixture = fixtures.%Get(key)
			If '$IsObject(fixture) {
				Do $$$AssertTrue(0, key_" has a fixture")
				Continue
			}
			Set kind = $Case($Piece(key, ".", 1), "incident": $Select(key = "incident.laterRequest": "approval", 1: "incident"), "result": "result", "notice": "tellnow", "reminder": "reminder", : "allowance")
			Set approval = ""
			If (kind = "incident") || (kind = "approval") {
				Set approvals = approvals + 1
				Set approval = "zzappr"_approvals
			}
			Set before = ..CallsOf("sendMessage").%Size()
			Set phoneBefore = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 100).Count()
			If '..ToNotify(..Notification(session, kind, key, fixture.slots, approval), trace) Continue
			Set calls = ..WaitCalls("sendMessage", before + 1, 20)
			If calls.%Size() < (before + 1) {
				Do $$$AssertTrue(0, key_" reached the chat")
				Continue
			}
			Set call = calls.%Get(before)
			Do $$$AssertEquals(call.params."chat_id", chatId, key_" went to the paired chat")
			Set text = call.params.text
			If kind = "allowance" {
				Set phoneText = ##class(OcuTalon.Msg.Catalog).Render(key, fixture.slots.%ToJSON(), "phone")
				Do $$$AssertEquals(text, phoneText, key_" is the catalog's text for the phone channel")
			} Else {
				Set phones = phones + 1
				Set deadline = $ZHorolog + 20
				For {
					Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(session, 100)
					If (rows.Count() > phoneBefore) || ($ZHorolog >= deadline) Quit
					Hang 0.25
				}
				Do $$$AssertEquals(rows.Count(), phoneBefore + 1, key_" reached the simulated phone")
				If rows.Count() > phoneBefore Do $$$AssertEquals(text, rows.GetAt(1).Text, key_": the chat's text is the phone's")
			}
			If key = "incident.withFix" {
				Do $$$AssertTrue($Find(text, ##class(OcuTalon.Data.Time).ForMessage(fixture.slots.time)) && '$Find(text, fixture.slots.time), "incident.withFix shows its time in the instance zone, not as UTC")
				Do $$$AssertTrue($Find(text, "Approve?"), "and asks Approve?")
			}
			Set expectedRows = expectedRows _ $Select(expectedRows = "": "", 1: ",") _ kind_"|"_approval_"|"_chatRef_":"_(before + 1)
		}
		Do $$$AssertEquals(..Rows(session, "telegram", "pairing"), expectedRows, "the telegram Delivery rows have each notice's kind, its approval Ref and <ChatRef>:<message_id>")
		Do $$$AssertEquals($Length(expectedRows, ","), 18, "there are 18 of them")

		Set before = ..CallsOf("sendMessage").%Size()
		Set answered = fixtures.%Get("answered.approved")
		If ..ToNotify(..Notification(session, "answered", "answered.approved", answered.slots, "zzappr1"), trace) {
			Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "Notify", "TelegramOut", 19, 30), "TelegramOut has handled all 19 notifications, the answered one included")
			Do $$$AssertEquals(..CallsOf("sendMessage").%Size(), before, "an answered Notification sends no sendMessage")
		}
		Do $$$AssertEquals(..Rows(session, "telegram", "pairing"), expectedRows, "and records no telegram row")
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentPhone(session, 100).Count(), phones, "the phone got none of the allowance notices")
		Do $$$AssertTrue(..WaitRows(session, "web", "*", 19, 30) >= 19, "WebChatOut has handled all 19 notifications, so that nothing is left to write when the test ends")
	} Catch ex {
		Do $$$AssertTrue(0, "the notices test failed: "_..Safe(ex))
	}
}

/// A paired chat's message with no text, and one of white space only, make no turn (the Boundaries' "A turn").
Method TestEmptyTurn()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734136
		Set session = ..Paired(chatId, "Zqempty", .chatRef)
		Do $$$AssertEquals(..TextsAfter(chatId, 1).%Size(), 1, "the chat got its confirmation")
		Set mark = ..HeaderMark()
		Set sticker = ..PrivateMessage(chatId, "Zqempty")
		Do sticker.message.%Remove("text")
		Set sticker.message.sticker = {"file_id": "zzsticker", "emoji": "zz"}
		Do ..Send(sticker)
		Set photo = ..PrivateMessage(chatId, "Zqempty")
		Do photo.message.%Remove("text")
		Set photo.message.photo = [{"file_id": "zzphoto", "width": 1, "height": 1}]
		Set photo.message.caption = "zz a caption is no turn"
		Do ..Send(photo)
		Do ..Send(..PrivateMessage(chatId, "", "   "))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled all three")
		Hang 1
		Do $$$AssertEquals(..Items(mark).%Size(), 0, "no Item goes to Conversation")
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Turns(session).Count(), 0, "the session has no Turn")
		Do $$$AssertEquals(..Notifications(mark).%Size(), 0, "TelegramIn sends no Notification")
		Do $$$AssertEquals(..TextsTo(chatId).%Size(), 1, "and the chat gets no text beyond its confirmation")
	} Catch ex {
		Do $$$AssertTrue(0, "the empty-turn test failed: "_..Safe(ex))
	}
}

/// No Telegram identity outside the Pairing row (AC6).
Method TestNoIdentity()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734135
		Set name = "Zqhidden"
		Set headers = ..HeaderMark()
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set live = ..LiveMark()
		Set session = ..Paired(chatId, name, .chatRef)
		Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
		Set ..Probe = "zzprobe-"_##class(OcuTalon.Bridge.Ids).NewRef()_" "_chatId_" "_name
		Do ##class(Ens.Util.Log).LogInfo("OcuTalon.Test.Channel.TelegramChat", "TestNoIdentity", ..Probe)
		Set text = "zz a quiet turn"
		Do ..Send(..PrivateMessage(chatId, name, text))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled the message")
		Set items = ..WaitItems(headers, 1)
		Do $$$AssertEquals(items.%Size(), 1, "the message made one Item")
		If items.%Size() '= 1 Quit
		Set turn = ..WaitTurn(items.%Get(0).itemId, session, "done")
		Do $$$AssertEquals($Select($IsObject(turn): turn.State, 1: ""), "done", "its Turn is done")
		If '$IsObject(turn) Quit
		Set fixtures = ..XData("OcuTalon.Test.Msg.Catalog", "Fixtures")
		Do ..ToNotify(..Notification(session, "tellnow", "notice.tellNow", fixtures.%Get("notice.tellNow").slots), trace)
		Do ..ToNotify(..Notification(session, "reminder", "reminder.due", fixtures.%Get("reminder.due").slots), trace)
		Set texts = ..TextsAfter(chatId, 4)
		Do $$$AssertEquals(texts.%Size(), 4, "the chat got the confirmation, the reply and two notices")
		Do $$$AssertTrue(..WaitRows(session, "web", "*", 3, 30) >= 3, "WebChatOut has handled the reply and both notices")

		Set steps = ""
		For ref = turn.TriageDecisionRef, turn.TurnDecisionRef {
			If ref '= "" Set steps = steps _ ##class(OcuTalon.Test.Agent.RunnerFixture).StepsOf(ref).%ToJSON()
		}
		Set places = {}
		Set places.headers = ..RowsText("SELECT * FROM Ens.MessageHeader WHERE ID > ?", headers)
		Set places.bodies = ..Bodies(headers)
		Set places.steps = steps
		Set places.audit = ##class(OcuTalon.Test.Bridge.AuditLog).Entries(audit).%ToJSON()
		Do $$$AssertTrue($Find(places.headers, "TelegramIn") && $Find(places.bodies, text), "the header scan reads TelegramIn's headers, and the bodies hold the turn's text")
		Do $$$AssertTrue(steps '= "", "the agent steps of the turn's decisions are read")
		Do $$$AssertTrue($Find(places.audit, session), "the audit scan reads the pairing's entry")
		Set liveText = ..RowsText("SELECT Payload FROM OcuTalon_Live.Event WHERE %ID > ?", live)
		Do $$$AssertTrue($Find(liveText, text), "the live-event scan reads the turn's chat.message")
		Do $$$AssertNotTrue($Find(liveText, chatId), "the live events hold no chat id (the name goes to the session's own page, AD-4)")
		For value = "the chat id|"_chatId, "the name|"_name {
			For place = "headers", "bodies", "steps", "audit" {
				Do $$$AssertNotTrue($Find(places.%Get(place), $Piece(value, "|", 2)), "the "_place_" hold no "_$Piece(value, "|", 1))
			}
			Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(log, $Piece(value, "|", 2)), 1, "the event log holds "_$Piece(value, "|", 1)_" only in the probe, which the scan finds")
		}
		Set stored = ##class(OcuTalon.Data.Pairing).Chat(chatRef)
		Do $$$AssertTrue($IsObject(stored) && (stored.ChatId = chatId) && (stored.DisplayName = name), "the Pairing row holds both")
	} Catch ex {
		Do $$$AssertTrue(0, "the no-identity test failed: "_..Safe(ex))
	}
}

}
