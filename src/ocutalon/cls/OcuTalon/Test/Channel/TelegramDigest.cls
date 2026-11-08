/// Live tests of the Telegram digest and its Got it button (Story 17.6; AD-14, AD-19, AD-32, UX-DR143, FR-20, FR-35). THESE TESTS RUN IN THROWAWAY STACKS AND IN CI
/// ONLY (Rule 21), against the CI mock and its dummy token, like OcuTalon.Test.Channel.LiveCase, which they extend: BeginPairing starts TelegramIn and TelegramOut with
/// the Telegram seam on. The chats are paired through the real /start path, a Notification goes straight to TelegramOut (the running item), and a press is a
/// callback_query update that the mock hands to TelegramIn. The digests are composed by a shadow instance of OcuTalon.Test.Digest.ProcessProbe from fed check rows, so
/// that TelegramOut renders the Slots that Digest makes.
///   - TestDigestMessage: a digest Notification is one plain-text message (no parse_mode, no reply_markup) whose lines are, in order, the greeting, the vital signs, what was
///     checked and the reserved sentence, one coverage line for each row ("Passed:", "Failed:", "Not checked:"), what needs the user, what was saved for later and the cost
///     "Yesterday's cost: $0.04." (the session's 0.042 plus whatever the instance's rows of yesterday add); it records one Delivery row of the kind digest;
///   - TestQuietAndLimits: a quiet digest has at most 150 words, and a digest with 201 open entries (200 Decisions and a failed row) is one message of at most 4096
///     characters that names five of them and ends the list with "And 196 more on the OcuTalon page.";
///   - TestLongDigestSplits: a demo-sized session's digest (eight watched entries and three open Decisions) is one message of at most 4096 characters; the digest of a
///     session with 200 watched entries is sent as several messages in order, each of at most 4096 characters and cut at line breaks only: every line of every message is
///     one whole rendered piece of the digest, each piece is there once, the coverage lines are in the order of the rows, the greeting comes first and the cost
///     last, and the Delivery row records the last message;
///   - TestRenderError: a digest with a part that cannot be rendered sends nothing and returns the error;
///   - TestGotItButton: a tell-now message with a DecisionRef carries one inline button "Got it" whose callback data is gotit:<DecisionRef>, and one with no DecisionRef carries
///     none;
///   - TestGotItPairedChat: the press from the paired chat submits one GotIt command, origin telegram, with the Ref, the channel telegram and the session, and is answered with no
///     text;
///   - TestGotItOtherChat: the same data pressed in another paired chat, in a chat that is not paired, for a Ref the session has no message for, in a chat other than the one of
///     the session's message, and for a message of the pressing chat whose Ref is not a reference, submits nothing, and each press is still answered;
///   - TestHandledEdit: a handled Notification edits the tell-now message in place to its text, a blank line and "Marked as handled at <time>", with no reply_markup, once; a
///     handled Notification with no marker or no message edits nothing and logs one warning, and a repeated one edits nothing and logs none.
///   - TestGotItEdits (Story 12.12): the press of Got it under a tell-now message whose Decision is the session's runs through TelegramIn, SessionOps, Notify and
///     TelegramOut: the message is edited once to its text, a blank line and "Marked as handled at <time>" (the marker's time) with no reply_markup, the Handled row
///     holds the Ref, the session and the channel telegram, and a second press sends no Notification, edits nothing more and adds no row.
/// The fixture chats are 84017734160 to 84017734172, and the fixture sessions zztgdig....
Class OcuTalon.Test.Channel.TelegramDigest Extends OcuTalon.Test.Channel.LiveCase
{

/// The fixture chat ids.
Parameter CHATS = "84017734160,84017734161,84017734162,84017734163,84017734164,84017734165,84017734166,84017734167,84017734168,84017734169,84017734170,84017734171,84017734172";

Parameter PROBE = "OcuTalon.Test.Digest.ProcessProbe";

/// The reason why every test fails, or "".
Property Missing As %String(MAXLEN = 400);

/// The digest.channels row before the class (ProcessProbe ForgetChannels).
Property ChannelsWas As %List;

/// 1 while BeginPairing has run and EndPairing has not.
Property Begun As %Boolean [ InitialExpression = 0 ];

/// The Refs of the rows a test made, comma-separated, for Fixture.Clean.
Property Refs As %String(MAXLEN = "") [ Private ];

/// The ids of the Handled rows a test made, comma-separated.
Property Marked As %String(MAXLEN = "") [ Private ];

/// The Refs of the sessions whose digest rows a test made, comma-separated.
Property Digests As %String(MAXLEN = "") [ Private ];

/// The presses sent so far, for their ids.
Property Presses As %Integer [ InitialExpression = 0, Private ];

Method OnBeforeAllTests() As %Status
{
	Set ..ChannelsWas = $ClassMethod(..#PROBE, "ForgetChannels")
	Set ..Missing = ..BeginPairing(..#CHATS)
	Set ..Begun = (..Missing = "")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do $ClassMethod(..#PROBE, "PutChannelsBack", ..ChannelsWas)
	Set sc = $$$OK
	If ..Begun {
		Set ..Begun = 0
		Set sc = $SYSTEM.Status.AppendStatus(sc, ..EndPairing())
		If '..WaitJobs("TelegramIn", 0) Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "TelegramIn still has a job after the class"))
	}
	Quit sc
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Marked = ""
	Set ..Digests = ""
	Do $ClassMethod(..#PROBE, "Reset")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Tidy()
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

/// Removes what the test made, on every path: the digest rows, the markers, then the fixture rows.
Method Tidy() [ Private ]
{
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#PROBE, "Clean", ..Digests)
	For i = 1:1:$Length(..Marked, ",") {
		If $Piece(..Marked, ",", i) '= "" Do ##class(OcuTalon.Data.Handled).%DeleteId($Piece(..Marked, ",", i))
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Set ..Marked = ""
	Set ..Digests = ""
}

Method Keep(ref As %String) [ Private ]
{
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
}

/// A session paired with the chat through the real /start path, with the confirmation that the chat gets waited for; the session's Ref.
Method Paired(chatId As %String, name As %String, Output chatRef As %String) As %String [ Private ]
{
	Set session = ..NewSession("zztgdig")
	Do $$$AssertTrue(..PairChat(chatId, name, session), "chat "_chatId_" is paired with its session")
	Do ..ChatRow(chatId, .chatRef)
	Do $$$AssertEquals(..TextsAfter(chatId, 1).%Size(), 1, "the chat got its confirmation")
	Set ..Digests = ..Digests_$Select(..Digests = "": "", 1: ",")_session
	Quit session
}

/// The press of the button whose data is data, under a message of the chat; TelegramIn has handled it when this returns.
Method Press(chatId As %String, name As %String, data As %String) [ Private ]
{
	Set ..Presses = ..Presses + 1
	Do ..Send(..ButtonPress(chatId, name, 1, data, "zzdigest"_..Presses))
	Do $$$AssertTrue(..Handled(), "TelegramIn handled the press of "_chatId)
}

/// A tell-now Notification for the session whose DecisionRef is decisionRef.
ClassMethod TellNow(session As %String, decisionRef As %String) As OcuTalon.Msg.Notification [ Private ]
{
	Set message = ##class(OcuTalon.Msg.Notification).%New()
	Set message.SessionRef = session
	Set message.Kind = "tellnow"
	Set message.CatalogKey = "notice.tellNow"
	Set message.Slots = {"whatHappened": "zz Disk almost full", "reason": "you asked to hear about disk space"}.%ToJSON()
	Set message.DecisionRef = decisionRef
	Quit message
}

/// The Telegram text of the tell-now Notification.
ClassMethod TellNowText() As %String [ Private ]
{
	Quit ##class(OcuTalon.Msg.Catalog).Render("notice.tellNow", {"whatHappened": "zz Disk almost full", "reason": "you asked to hear about disk space"}.%ToJSON(), "telegram")
}

/// Sends the Notification to the running TelegramOut and returns the status.
Method ToOut(notice As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Quit $ClassMethod(..#FIXTURE, "Send", "TelegramOut", notice, .response)
}

/// A digest Notification for the session, made by the probe from the fed rows (an array of {result, entry, finding, checkedAt}).
Method DigestNotice(session As %String, watched As %DynamicArray) As OcuTalon.Msg.Notification [ Private ]
{
	Do $ClassMethod(..#PROBE, "Reset")
	Do $ClassMethod(..#PROBE, "Feed", watched)
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	Set compose = ##class(OcuTalon.Digest.Msg.Compose).%New()
	Set compose.SessionRef = session
	Set compose.Kind = "scheduled"
	Set compose.DueAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set compose.WindowEnd = compose.DueAt
	Set compose.WindowStart = ##class(OcuTalon.Data.Time).AddSeconds(compose.WindowEnd, -86400)
	Kill response
	Do $$$AssertStatusOK(host.OnRequest(compose, .response), "the Compose is handled")
	Set record = $ClassMethod(..#PROBE, "Record", "notice", 1)
	Set notice = ##class(OcuTalon.Msg.Notification).%New()
	Set notice.SessionRef = $List(record, 1)
	Set notice.Kind = "digest"
	Set notice.CatalogKey = $List(record, 3)
	Set notice.DecisionRef = $List(record, 4)
	Set notice.Slots = $List(record, 5)
	Quit notice
}

Method Watched(result As %String, entry As %String, finding As %String = "") As %DynamicObject [ Private ]
{
	Quit {"result": (result), "entry": (entry), "finding": (finding), "checkedAt": (##class(OcuTalon.Data.Time).NowUtc())}
}

/// The number of words of a text.
ClassMethod Words(text As %String) As %Integer [ Private ]
{
	Set text = $Translate(text, $Char(10, 13, 9), "   ")
	Set count = 0
	For i = 1:1:$Length(text, " ") {
		If $Piece(text, " ", i) '= "" Set count = count + 1
	}
	Quit count
}

/// The number of Notifications that SessionOps has sent Notify in the SuperSession trace.
ClassMethod Notices(trace As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "SessionOps", "Notify").%Size()
}

/// The telegram Delivery rows of the session (see Rows), once they are want or after seconds (whichever is first).
Method WaitRows(session As %String, want As %String, seconds As %Numeric = 20) As %String [ Private ]
{
	Set deadline = $ZHorolog + seconds
	For {
		Set found = ..Rows(session)
		If (found = want) || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit found
}

/// The telegram Delivery rows of the session other than its pairing notice, as "<kind>|<ChannelMessageId>", oldest first, comma-separated.
Method Rows(session As %String) As %String [ Private ]
{
	Set found = ""
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		If (row.Channel = "telegram") && (row.Kind '= "pairing") Set found = found _ $Select(found = "": "", 1: ",") _ row.Kind_"|"_row.ChannelMessageId
	}
	Quit found
}

/// The bodies of the GotIt commands of the message headers after the mark, each as {ref, channel, sessionRef, origin}.
ClassMethod GotItBodies(mark As %Integer) As %DynamicArray [ Private ]
{
	Set found = []
	Set seen = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = ? ORDER BY ID", mark, "OcuTalon.Msg.Command.GotIt")
	While result.%Next() {
		Set id = result.%GetData(1)
		If $ListFind(seen, id) Continue
		Set seen = seen _ $ListBuild(id)
		Set body = ##class(OcuTalon.Msg.Command.GotIt).%OpenId(id)
		If $IsObject(body) Do found.%Push({"ref": (body.Ref), "channel": (body.Channel), "sessionRef": (body.SessionRef), "origin": (body.Origin)})
	}
	Quit found
}

/// The number of warnings of TelegramOut after the log mark that hold the text.
Method Warned(mark As %Integer, text As %String) As %Integer [ Private ]
{
	Set told = 0, position = 0
	Set rows = $ClassMethod(..#FIXTURE, "EventRows", mark, "TelegramOut")
	While $ListNext(rows, position, row) {
		If ($Extract(row, 1, 2) = "3:") && ($Find(row, text) > 0) Set told = told + 1
	}
	Quit told
}

/// A handled marker for the Decision of the session, marked at the time.
Method Mark(decisionRef As %String, session As %String, at As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Data.Handled).%New()
	Set row.Ref = decisionRef
	Set row.SessionRef = session
	Set row.HandledAt = at
	Set row.Channel = "web"
	Do $$$AssertStatusOK(row.%Save(), "the Decision is marked handled")
	Set ..Marked = ..Marked_$Select(..Marked = "": "", 1: ",")_row.%Id()
}

Method TestDigestMessage()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734160
		Set session = ..Paired(chatId, "Zqdigest", .chatRef)
		Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set instance = ##class(OcuTalon.Digest.Cost).Yesterday(##class(OcuTalon.Bridge.Ids).NewRef(), ##class(OcuTalon.Data.Time).NowUtc(), .sc)
		Do $$$AssertStatusOK(sc, "the cost that other rows add (the instance's) is read")
		Set cost = {}
		Do cost.%Set("cost", 0.042 + instance, "number")
		Set yesterday = $ZDate($ZDateH($Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()), "T", 1), 3) - 1, 3)
		Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Usage(ref, session, {"CostUSD": 0.042, "RecordedAt": (##class(OcuTalon.Data.Time).FromLocal(yesterday_"T12:00:00"))}))
		Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", ##class(OcuTalon.Data.Time).NowUtc(), {"Summary": "Partner support: invoice question", "Outcome": "tellnow"}))
		Set notice = ..DigestNotice(session, [(..Watched("passed", "Orders production")), (..Watched("failed", "Billing source", "5 messages queued")), (..Watched("not_checked", "Mail source"))])
		Set sends = ..CallsOf("sendMessage").%Size()
		Do $$$AssertStatusOK(..ToOut(notice), "the digest is sent to TelegramOut")
		Set found = ..TextsAfter(chatId, 1)
		Do $$$AssertEquals(..CallsOf("sendMessage").%Size(), sends + 1, "one sendMessage goes out")
		Set call = ..CallsOf("sendMessage").%Get(sends)
		Do $$$AssertEquals(call.params.%IsDefined("parse_mode")_"|"_call.params.%IsDefined("reply_markup")_"|"_call.params."chat_id", "0|0|"_chatId, "it is plain text for the chat, with no parse mode and no button")
		Set text = call.params.text
		Set at = 0
		For piece = "Good ", "Your IRIS system is healthy: up 3 days, databases 60% full, journal space fine, license use 20%.", "I checked the Orders production, the Billing source and the Mail source.", "Not everything: Billing source and Mail source. Everything else I checked passed.", "Passed: Orders production (", "Failed: Billing source (5 messages queued, ", "Not checked: Mail source (", "2 things need you: Billing source: 5 messages queued; Partner support: invoice question.", "Nothing was saved for later.", ##class(OcuTalon.Msg.Catalog).Render("digest.cost", cost, "telegram") {
			Set found = $Find(text, piece, at)
			Do $$$AssertTrue(found > at, "the text holds '"_$Extract(piece, 1, 40)_"' after the one before it")
			If found > at Set at = found
		}
		Do $$$AssertTrue(text '[ "*", "and holds no Markdown")
		Do $$$AssertTrue($Length(text, $Char(10)) >= 15, "each piece is on its own line")
		Do $$$AssertEquals(..Rows(session), "digest|"_chatRef_":"_..LastMessageId(chatId), "one Delivery row of the kind digest records the message")
	} Catch ex {
		Do $$$AssertTrue(0, "the digest test failed: "_..Safe(ex))
	}
}

/// The message_id that the mock gave the last sendMessage to the chat id. The mock counts the message ids of sendMessage and editMessageText
/// together, so an edit made earlier in the run moves the ids of the sends after it.
Method LastMessageId(chatId As %String) As %String [ Private ]
{
	Set id = "", count = 0
	Set iterator = ##class(OcuTalon.Test.Contract.Mock).Calls().%GetIterator()
	While iterator.%GetNext(, .call) {
		If (call.method '= "sendMessage") && (call.method '= "editMessageText") Continue
		Set count = count + 1
		If (call.method = "sendMessage") && (call.params."chat_id" = chatId) Set id = count
	}
	Quit id
}

Method TestQuietAndLimits()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734161
		Set session = ..Paired(chatId, "Zqquiet", .chatRef)
		Set notice = ..DigestNotice(session, [(..Watched("passed", "Orders production"))])
		Set sends = ..CallsOf("sendMessage").%Size()
		Do $$$AssertStatusOK(..ToOut(notice), "the quiet digest is sent")
		Do $$$AssertEquals(..CallsOf("sendMessage").%Size(), sends + 1, "as one message")
		Set text = ..CallsOf("sendMessage").%Get(sends).params.text
		Do $$$AssertTrue(text [ "Everything I checked passed.", "it gives the all-clear")
		Do $$$AssertTrue(..Words(text) <= 150, "and has at most 150 words: "_..Words(text))
		Set busy = ..Paired(84017734162, "Zqbusy", .busyRef)
		For i = 1:1:200 {
			Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Decision(busy, "decide", ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -i), {"Summary": ("zz Mail with a longer subject line number "_i_" from a partner"), "Outcome": "tellnow"}))
		}
		Set notice = ..DigestNotice(busy, [(..Watched("failed", "Billing source", "5 messages queued"))])
		Set sends = ..CallsOf("sendMessage").%Size()
		Do $$$AssertStatusOK(..ToOut(notice), "the digest of 201 open items is sent")
		Do $$$AssertEquals(..CallsOf("sendMessage").%Size(), sends + 1, "as one message")
		Set text = ..CallsOf("sendMessage").%Get(sends).params.text
		Do $$$AssertTrue($Length(text) <= 4096, "of at most 4096 characters: "_$Length(text))
		Do $$$AssertTrue(text [ "201 things need you: Billing source: 5 messages queued; zz Mail with a longer subject line number 1 from a partner; ", "five of them are named")
		Do $$$AssertTrue(text [ "And 196 more on the OcuTalon page.", "and the rest are counted")
	} Catch ex {
		Do $$$AssertTrue(0, "the limits test failed: "_..Safe(ex))
	}
}

Method TestLongDigestSplits()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734170
		Set small = ..Paired(chatId, "Zqsmall", .smallRef)
		For i = 1:1:3 {
			Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Decision(small, "decide", ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -i), {"Summary": ("zz Mail number "_i_" from a partner"), "Outcome": "tellnow"}))
		}
		Set watched = []
		For i = 1:1:8 {
			Do watched.%Push(..Watched($Select(i = 3: "failed", 1: "passed"), "zz Entry "_i, $Select(i = 3: "5 messages queued", 1: "")))
		}
		Set notice = ..DigestNotice(small, watched)
		Set sends = ..CallsOf("sendMessage").%Size()
		Do $$$AssertStatusOK(..ToOut(notice), "the demo-sized digest is sent")
		Do $$$AssertEquals(..CallsOf("sendMessage").%Size(), sends + 1, "a demo-sized session's digest is one message")
		Do $$$AssertTrue($Length(..CallsOf("sendMessage").%Get(sends).params.text) <= 4096, "of at most 4096 characters")
		Set chatId = 84017734171
		Set big = ..Paired(chatId, "Zqbig", .bigRef)
		Set watched = []
		For i = 1:1:200 {
			Do watched.%Push(..Watched($Select(i # 7 = 0: "failed", 1: "passed"), "zz E"_i, $Select(i # 7 = 0: "5 messages queued", 1: "")))
		}
		Set notice = ..DigestNotice(big, watched)
		Set slots = {}.%FromJSON(notice.Slots)
		Set expected = 0
		For list = "parts", "lines" {
			Set iterator = $Property(slots, list).%GetIterator()
			While iterator.%GetNext(, .element) {
				Set text = ##class(OcuTalon.Msg.Catalog).Render(element.key, element.slots, "telegram", .sc)
				Do $$$AssertStatusOK(sc, element.key_" renders")
				Set expected = expected + 1
				Set hash = $SYSTEM.Encryption.SHA1Hash(text)
				Set want(hash) = $Get(want(hash)) + 1
				If list = "lines" Set lines = $Get(lines) + 1, lineHash(lines) = hash
				If list = "parts" Set:'$Data(firstHash) firstHash = hash Set lastHash = hash
			}
		}
		Do $$$AssertEquals(lines, 205, "control: the 200 rows and the five vital signs give 205 coverage lines")
		Set sends = ..CallsOf("sendMessage").%Size()
		Do $$$AssertStatusOK(..ToOut(notice), "the digest of 200 watched entries is sent")
		Set messages = ..CallsOf("sendMessage").%Size() - sends
		Do $$$AssertTrue(messages >= 2, "as several messages: "_messages)
		Set seen = 0
		For n = sends:1:..CallsOf("sendMessage").%Size() - 1 {
			Set call = ..CallsOf("sendMessage").%Get(n)
			Do $$$AssertEquals(call.params."chat_id", chatId, "message "_(n - sends + 1)_" goes to the paired chat")
			Do $$$AssertTrue($Length(call.params.text) <= 4096, "message "_(n - sends + 1)_" has at most 4096 characters: "_$Length(call.params.text))
			For i = 1:1:$Length(call.params.text, $Char(10)) {
				Set line = $Piece(call.params.text, $Char(10), i)
				Set seen = seen + 1
				Set hash = $SYSTEM.Encryption.SHA1Hash(line)
				Set got(hash) = $Get(got(hash)) + 1
				Set position(hash) = $Get(position(hash), seen)
			}
		}
		Do $$$AssertEquals(seen, expected, "the messages hold exactly as many lines as the digest has pieces")
		Set wrong = 0, order = 1, last = 0
		Set hash = ""
		For {
			Set hash = $Order(want(hash), 1, count)
			Quit:hash=""
			If $Get(got(hash)) '= count Set wrong = wrong + 1
		}
		Do $$$AssertEquals(wrong, 0, "every piece is one whole line of the messages, as often as the digest has it: no line is lost, repeated or cut")
		For i = 1:1:lines {
			If $Get(position(lineHash(i))) <= last Set order = 0
			Set last = $Get(position(lineHash(i)))
		}
		Do $$$AssertTrue(order, "and the coverage lines follow each other in the order of the rows")
		Do $$$AssertEquals($Get(position(firstHash))_"|"_$Get(position(lastHash)), "1|"_seen, "the greeting opens the first message and the cost ends the last")
		Set smallId = $Piece(..Rows(small), ":", 2), bigId = $Piece(..Rows(big), ":", 2)
		Do $$$AssertEquals(..Rows(big), "digest|"_bigRef_":"_bigId, "one Delivery row of the kind digest records a message of the chat")
		Do $$$AssertTrue((smallId ? 1.N) && (bigId ? 1.N) && (bigId - smallId >= (messages + 1)), "which is the last message: its id follows the small digest's by the confirmation and every message")
	} Catch ex {
		Do $$$AssertTrue(0, "the split test failed: "_..Safe(ex))
	}
}

Method TestRenderError()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734163
		Set session = ..Paired(chatId, "Zqbad", .chatRef)
		Set notice = ##class(OcuTalon.Msg.Notification).%New()
		Set notice.SessionRef = session
		Set notice.Kind = "digest"
		Set notice.Slots = {"parts": [{"key": "digest.greetingMorning", "slots": {}}, {"key": "digest.noSuchKey", "slots": {}}], "lines": [], "rows": []}.%ToJSON()
		Set sends = ..CallsOf("sendMessage").%Size()
		Do $$$AssertStatusNotOK(..ToOut(notice), "a part that cannot be rendered is an error")
		Do $$$AssertEquals(..CallsOf("sendMessage").%Size(), sends, "and nothing is sent")
		Do $$$AssertEquals(..Rows(session), "", "and no row is recorded")
	} Catch ex {
		Do $$$AssertTrue(0, "the render-error test failed: "_..Safe(ex))
	}
}

Method TestGotItButton()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734164
		Set session = ..Paired(chatId, "Zqbutton", .chatRef)
		Set decisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Do $$$AssertStatusOK(..ToOut(..TellNow(session, decisionRef)), "a tell-now Notification with a DecisionRef is sent")
		Set keyboard = ..KeyboardTo(chatId)
		Do $$$AssertTrue($IsObject(keyboard), "the message carries a keyboard")
		If $IsObject(keyboard) {
			Set buttons = keyboard."inline_keyboard"
			Do $$$AssertEquals(buttons.%Size()_"|"_buttons.%Get(0).%Size(), "1|1", "of one row with one button")
			Set button = buttons.%Get(0).%Get(0)
			Do $$$AssertEquals(button.text_"|"_button."callback_data", "Got it|gotit:"_decisionRef, "labelled Got it, with the action and the Ref of the Decision")
			Do $$$AssertEquals($Length(decisionRef), 22, "the Ref is 22 characters")
		}
		Do $$$AssertEquals(..Rows(session), "tellnow|"_chatRef_":"_..LastMessageId(chatId), "and the message has its row")
		Set sends = ..CallsOf("sendMessage").%Size()
		Do $$$AssertStatusOK(..ToOut(..TellNow(session, "")), "a tell-now Notification with no DecisionRef is sent")
		Do $$$AssertEquals(..CallsOf("sendMessage").%Size(), sends + 1, "it reaches the chat")
		Do $$$AssertEquals(..CallsOf("sendMessage").%Get(sends).params.%IsDefined("reply_markup"), 0, "with no button")
	} Catch ex {
		Do $$$AssertTrue(0, "the Got it button test failed: "_..Safe(ex))
	}
}

Method TestGotItPairedChat()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734165
		Set session = ..Paired(chatId, "Zqgotit", .chatRef)
		Set decisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Do $$$AssertStatusOK(..ToOut(..TellNow(session, decisionRef)), "a tell-now Notification is sent")
		Set mark = ..HeaderMark()
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(chatId, "Zqgotit", "gotit:"_decisionRef)
		Set found = ..WaitAnswers(answers, 1)
		Do $$$AssertEquals(found.%Size(), 1, "one answerCallbackQuery")
		If found.%Size() = 1 {
			Do $$$AssertEquals(found.%Get(0)."callback_query_id", "zzdigest"_..Presses, "of the press")
			Do $$$AssertEquals(found.%Get(0).%IsDefined("text")_"|"_+found.%Get(0)."show_alert", "0|0", "with no text and no alert")
		}
		Set commands = ..GotItBodies(mark)
		Do $$$AssertEquals(commands.%Size(), 1, "one GotIt command is submitted")
		If commands.%Size() = 1 {
			Set command = commands.%Get(0)
			Do $$$AssertEquals(command.ref_"|"_command.channel_"|"_command.sessionRef_"|"_command.origin, decisionRef_"|telegram|"_session_"|telegram", "with the Ref, the channel telegram, the session and the origin telegram")
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the Got it test failed: "_..Safe(ex))
	}
}

Method TestGotItOtherChat()
{
	If '..Go() Quit
	Try {
		Set chatA = 84017734166
		Set chatB = 84017734167
		Set session = ..Paired(chatA, "Zqowner", .refA)
		Set other = ..Paired(chatB, "Zqother", .refB)
		Set decisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Do $$$AssertStatusOK(..ToOut(..TellNow(session, decisionRef)), "a tell-now Notification is sent to the first session's chat")
		Set unpaired = 84017734168
		Do ..DropChats(unpaired)
		Do ..Send(..PrivateMessage(unpaired, "Zqstranger", "hello"))
		Do $$$AssertTrue(..Handled(), "TelegramIn handled a message of a chat that is not paired")
		Set mark = ..HeaderMark()
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(chatB, "Zqother", "gotit:"_decisionRef)
		Do ..Press(unpaired, "Zqstranger", "gotit:"_decisionRef)
		Do ..Press(chatA, "Zqowner", "gotit:"_##class(OcuTalon.Bridge.Ids).NewRef())
		Set elsewhere = ##class(OcuTalon.Bridge.Ids).NewRef()
		Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Delivery(session, {"Channel": "telegram", "ChannelMessageId": (refB_":7"), "DecisionRef": (elsewhere)}))
		Do ..Press(chatA, "Zqowner", "gotit:"_elsewhere)
		Set notRef = "notaref"
		Do ..Keep(##class(OcuTalon.Test.Data.Fixture).Delivery(session, {"Channel": "telegram", "ChannelMessageId": (refA_":8"), "DecisionRef": (notRef)}))
		Do ..Press(chatA, "Zqowner", "gotit:"_notRef)
		Set found = ..WaitAnswers(answers, 5)
		Do $$$AssertEquals(found.%Size(), 5, "each of the five presses is answered")
		Set texts = ""
		Set iterator = found.%GetIterator()
		While iterator.%GetNext(, .answer) {
			Set texts = texts_answer.%IsDefined("text")
		}
		Do $$$AssertEquals(texts, "00000", "with no text")
		Do $$$AssertEquals(..GotItBodies(mark).%Size(), 0, "and none submits a command: another paired chat, an unpaired chat, a Ref with no message, a message in another chat, a message of the pressing chat whose Ref is not a reference")
	} Catch ex {
		Do $$$AssertTrue(0, "the other-chat test failed: "_..Safe(ex))
	}
}

Method TestHandledEdit()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734169
		Set session = ..Paired(chatId, "Zqhandled", .chatRef)
		Set decisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Do $$$AssertStatusOK(..ToOut(..TellNow(session, decisionRef)), "a tell-now Notification is sent")
		Set messageId = ..LastMessageId(chatId)
		Set handled = ##class(OcuTalon.Msg.Notification).%New()
		Set handled.SessionRef = session
		Set handled.Kind = "handled"
		Set handled.DecisionRef = decisionRef
		Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set edits = ..EditsTo(chatId).%Size()
		Do $$$AssertStatusOK(..ToOut(handled), "a handled Notification with no marker is sent")
		Do $$$AssertEquals(..EditsTo(chatId).%Size(), edits, "it edits nothing")
		Do $$$AssertEquals(..Warned(mark, "did not edit a handled notice's message"), 1, "and logs one warning")
		Set at = ##class(OcuTalon.Data.Time).NowUtc()
		Do ..Mark(decisionRef, session, at)
		Do $$$AssertStatusOK(..ToOut(handled), "the same Notification is sent once the Decision is marked")
		Set edited = ..EditsTo(chatId)
		Do $$$AssertEquals(edited.%Size(), edits + 1, "the message is edited once")
		If edited.%Size() = edits + 1 {
			Set params = edited.%Get(edits)
			Set expected = ..TellNowText()_$Char(10, 10)_##class(OcuTalon.Msg.Catalog).Render("handled.marked", {"time": (at)}, "telegram")
			Do $$$AssertEquals(params.text, expected, "to its text, a blank line and 'Marked as handled at <time>'")
			Do $$$AssertEquals(params."message_id"_"|"_params."chat_id"_"|"_params.%IsDefined("reply_markup"), messageId_"|"_chatId_"|0", "in place, with no reply_markup, so the button is gone")
		}
		Do $$$AssertEquals(..Rows(session), "tellnow|"_chatRef_":"_messageId_",handled|"_chatRef_":"_messageId, "the edit records a row of the kind handled")
		Do $$$AssertStatusOK(..ToOut(handled), "a second handled Notification is sent")
		Do $$$AssertEquals(..EditsTo(chatId).%Size(), edits + 1, "the first edit stays: nothing more is edited")
		Do $$$AssertEquals(..Warned(mark, "did not edit a handled notice's message"), 1, "and the repeat logs no further warning")
		Set lost = ##class(OcuTalon.Msg.Notification).%New()
		Set lost.SessionRef = session
		Set lost.Kind = "handled"
		Set lost.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Do $$$AssertStatusOK(..ToOut(lost), "a handled Notification for a Ref the chat has no message for is sent")
		Do $$$AssertEquals(..EditsTo(chatId).%Size(), edits + 1, "it edits nothing")
		Do $$$AssertEquals(..Warned(mark, "did not edit a handled notice's message"), 1, "and logs one warning")
	} Catch ex {
		Do $$$AssertTrue(0, "the handled test failed: "_..Safe(ex))
	}
}

/// The press of Got it under a tell-now message whose Decision is the session's marks the notice handled and edits the message once; a second press
/// is answered, sends no Notification and changes nothing.
Method TestGotItEdits()
{
	If '..Go() Quit
	Try {
		Set chatId = 84017734172
		Set session = ..Paired(chatId, "Zqgotitedit", .chatRef)
		Set decisionRef = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", ##class(OcuTalon.Data.Time).NowUtc(), {"Outcome": "tellnow"})
		Do ..Keep(decisionRef)
		Do $$$AssertStatusOK(..ToOut(..TellNow(session, decisionRef)), "a tell-now Notification for the session's own Decision is sent")
		Set messageId = ..LastMessageId(chatId)
		Set edits = ..EditsTo(chatId).%Size()
		Set total = ..CallsOf("editMessageText").%Size()
		Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
		Set notices = ..Notices(trace)
		Do ..Press(chatId, "Zqgotitedit", "gotit:"_decisionRef)
		Do $$$AssertEquals(..Notices(trace), notices + 1, "the press sends one Notification from SessionOps to Notify")
		Do ..WaitCalls("editMessageText", total + 1)
		Set edited = ..EditsTo(chatId)
		Do $$$AssertEquals(edited.%Size(), edits + 1, "the message is edited once")
		Set row = ##class(OcuTalon.Data.Handled).RefIndexOpen(decisionRef)
		Do $$$AssertTrue($IsObject(row), "a Handled row exists")
		If $IsObject(row) {
			Set ..Marked = ..Marked_$Select(..Marked = "": "", 1: ",")_row.%Id()
			Do $$$AssertEquals(row.Ref_"|"_row.SessionRef_"|"_row.Channel, decisionRef_"|"_session_"|telegram", "it holds the Ref, the session and the channel telegram")
			If edited.%Size() = edits + 1 {
				Set params = edited.%Get(edits)
				Set expected = ..TellNowText()_$Char(10, 10)_##class(OcuTalon.Msg.Catalog).Render("handled.marked", {"time": (##class(OcuTalon.Data.Handled).Marked(decisionRef))}, "telegram")
				Do $$$AssertEquals(params.text, expected, "the edit is the text, a blank line and 'Marked as handled at <time>' with the marker's time")
				Do $$$AssertEquals(params."message_id"_"|"_params."chat_id"_"|"_params.%IsDefined("reply_markup"), messageId_"|"_chatId_"|0", "in place, with no reply_markup, so the button is gone")
			}
		}
		Set want = "tellnow|"_chatRef_":"_messageId_",handled|"_chatRef_":"_messageId
		Do $$$AssertEquals(..WaitRows(session, want), want, "the message has its tell-now and its handled row")
		Set answers = ..CallsOf("answerCallbackQuery").%Size()
		Do ..Press(chatId, "Zqgotitedit", "gotit:"_decisionRef)
		Do $$$AssertEquals(..WaitCalls("answerCallbackQuery", answers + 1).%Size(), answers + 1, "the second press is answered")
		Do $$$AssertEquals(..Notices(trace), notices + 1, "a second press sends no Notification")
		Do $$$AssertEquals(..EditsTo(chatId).%Size(), edits + 1, "a second press edits nothing more")
		Set count = 0
		Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Handled WHERE Ref = ?", decisionRef)
		If rows.%Next() Set count = rows.%GetData(1)
		Do $$$AssertEquals(count, 1, "and the Decision still has one Handled row")
	} Catch ex {
		Do $$$AssertTrue(0, "the Got it edit test failed: "_..Safe(ex))
	}
}

}
