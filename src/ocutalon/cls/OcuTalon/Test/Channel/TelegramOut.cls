/// Live tests of TelegramOut against the CI mock (Story 12.2; FR-20, AD-14, AD-32, UX-DR108, UX-DR136). THESE TESTS RUN IN THROWAWAY
/// STACKS AND IN CI ONLY (Rule 21), like OcuTalon.Test.Channel.LiveCase, which they extend: each test enables TelegramOut on the running
/// production and sends its messages through RunnerFixture.Send, and ends with Cleanup. A test reads only the sendMessage calls whose
/// chat_id it made (85xx and 86xx), because a warm stack may hold messages that other tests queued for TelegramOut.
///   - TestPlainText: the text goes byte for byte as a numeric chat_id and plain text, with no parse_mode and no entities, also with
///     characters beyond ASCII;
///   - TestSplitAtLineBreaks: a text over 4,096 characters is sent in order as parts cut at line breaks, and the parts joined with a
///     line feed are the text;
///   - TestSplitOneLongLine: a line with no break is cut at the limit, and a surrogate pair at the limit is not split;
///   - TestRateLimited: a 429 is retried after its retry_after, and after five 429s for one part the status is an error with a safe text
///     while the parts already sent stay sent;
///   - TestSentThenLimited: part 1 is sent once, part 2 is limited and sent again;
///   - TestOtherFailure: a failure other than a 429 (a 403) is an error status with a safe text, and the part is not sent again;
///   - TestNotification: a Notification for a chat sends the catalog rendering, and a render error sends nothing; an Outbound with a
///     catalog key and no text sends the catalog rendering too;
///   - TestBySession (Story 12.6): a Notification or an Outbound with a SessionRef and no ChatRef goes to the session's paired chat and
///     records a telegram Delivery row of the session with <ChatRef>:<message_id> (and the reply's DecisionRef), and a session with no
///     pairing, or an owner that is not a session, sends nothing and returns OK with one warning and no row;
///   - TestLongNotice (DW-30): a rendered notice of 5,000 characters goes in parts of at most 4,096 that together are the text, with one
///     Delivery row that holds the id of the last part;
///   - TestCheckSentence (DW-295): the sentence of a reply's check key follows the reply after a blank line, built from the rows as the page
///     builds it (the failed rows first, the finding in lower case, the time and the at/on rule); an all-clear key, a key with no row to
///     name and an unknown key are as the Boundaries say; with the online demo on the time is followed by " ET"; a row with an entry only,
///     one with a time and no finding, one with no entry, and CheckRows that are not a JSON array give the literal forms of the Boundaries;
///     checks.notEverything with a failed row names it with nothing after, and checks.everythingElsePassed gives its catalog text;
///   - TestOtherKinds: a Notification of kind status, digest or fallback sends nothing and records no row, where one of kind tellnow does;
///   - TestNoChat: a ChatRef with no chat row, or none, sends nothing, logs one warning that names neither, and is OK. It first sends one
///     message of its own and waits for it, so that messages queued before the test have been handled before it counts.
Class OcuTalon.Test.Channel.TelegramOut Extends OcuTalon.Test.Channel.LiveCase
{

/// The text that the plain-text test sends: the characters that Markdown and HTML would treat as markup.
Parameter MARKUP = "a*b_c [x](y) `z` <b>&amp; 1.5! #t";

/// A chat row of the chat id, made now and deleted by Cleanup; the ChatRef.
Method MakeChat(chatId As %String) As %String [ Private ]
{
	Do ..Chat(chatId)
	Do ..DropChats(chatId)
	Set ref = ##class(OcuTalon.Data.Pairing).RecordChat(chatId, "", .sc)
	Do $$$AssertStatusOK(sc, "the fixture chat "_chatId_" has a row")
	Quit ref
}

/// The sendMessage calls whose chat_id is the id, in order.
Method SentTo(chatId As %String) As %DynamicArray [ Private ]
{
	Set found = []
	Set iterator = ..CallsOf("sendMessage").%GetIterator()
	While iterator.%GetNext(, .call) {
		If call.params."chat_id" = chatId Do found.%Push(call)
	}
	Quit found
}

/// An Outbound for the chat with the text.
ClassMethod Outbound(chatRef As %String, text As %String) As OcuTalon.Msg.Outbound [ Private ]
{
	Set message = ##class(OcuTalon.Msg.Outbound).%New()
	Set message.ChatRef = chatRef
	Set message.Text = text
	Quit message
}

/// The texts of calls, as a list.
ClassMethod Texts(calls As %DynamicArray) As %List [ Private ]
{
	Set texts = ""
	Set iterator = calls.%GetIterator()
	While iterator.%GetNext(, .call) {
		Set texts = texts _ $ListBuild(call.params.text)
	}
	Quit texts
}

/// The longest text of a list of texts.
ClassMethod Longest(texts As %List) As %Integer [ Private ]
{
	Set longest = 0
	Set position = 0
	While $ListNext(texts, position, text) {
		If $Length(text) > longest Set longest = $Length(text)
	}
	Quit longest
}

/// A fixture session (zztgout...) and its Ref; DropSessions removes it with its rows.
Method NewSessionRef() As %String [ Private ]
{
	Quit ..FixtureSession("zztgout").Ref
}

/// The chat row of the chat id, given to the session by SQL (a fixture row only); the ChatRef.
Method PairedChat(chatId As %String, session As %String) As %String [ Private ]
{
	Set ref = ..MakeChat(chatId)
	Set result = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.Pairing SET SessionRef = ? WHERE Ref = ?", session, ref)
	Do $$$AssertEquals(result.%SQLCODE, 0, "the fixture chat "_chatId_" is paired with the session")
	Quit ref
}

/// The message_id that the mock gave the last sendMessage to the chat id: the number of the call among all the sendMessage calls since
/// the reset (the mock counts them from 1). "" when there is none.
Method LastId(chatId As %String) As %String [ Private ]
{
	Set id = "", count = 0
	Set iterator = ..CallsOf("sendMessage").%GetIterator()
	While iterator.%GetNext(, .call) {
		Set count = count + 1
		If call.params."chat_id" = chatId Set id = count
	}
	Quit id
}

/// The telegram Delivery rows of the session as "<kind>|<approval>|<ChannelMessageId>", oldest first, comma-separated.
Method Rows(session As %String) As %String [ Private ]
{
	Set found = ""
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		If row.Channel = "telegram" Set found = found _ $Select(found = "": "", 1: ",") _ row.Kind_"|"_row.ApprovalRef_"|"_row.ChannelMessageId
	}
	Quit found
}

/// The number of warnings of TelegramOut after the log mark that hold the text.
Method Warned(mark As %Integer, text As %String) As %Integer [ Private ]
{
	Set told = 0, position = 0
	Set rows = ##class(OcuTalon.Test.Agent.RunnerFixture).EventRows(mark, "TelegramOut")
	While $ListNext(rows, position, row) {
		If ($Extract(row, 1, 2) = "3:") && ($Find(row, text) > 0) Set told = told + 1
	}
	Quit told
}

/// An Outbound for the session, with no ChatRef.
ClassMethod ForSession(session As %String, text As %String) As OcuTalon.Msg.Outbound [ Private ]
{
	Set message = ##class(OcuTalon.Msg.Outbound).%New()
	Set message.SessionRef = session
	Set message.Text = text
	Quit message
}

/// A tell-now Notification for the session, with no ChatRef.
ClassMethod TellNow(session As %String, whatHappened As %String) As OcuTalon.Msg.Notification [ Private ]
{
	Set message = ##class(OcuTalon.Msg.Notification).%New()
	Set message.SessionRef = session
	Set message.Kind = "tellnow"
	Set message.CatalogKey = "notice.tellNow"
	Set message.Slots = {"whatHappened": (whatHappened), "reason": "you asked to hear about disk space"}.%ToJSON()
	Quit message
}

/// An Outbound reply for the session with the check key and rows (a dynamic array, or "" for none).
ClassMethod WithChecks(session As %String, key As %String, rows As %DynamicArray) As OcuTalon.Msg.Outbound [ Private ]
{
	Set message = ..ForSession(session, "zz reply")
	Set message.CheckKey = key
	If $IsObject(rows) Set message.CheckRows = rows.%ToJSON()
	Quit message
}

/// The time of a check row as the sentence shows it: the instance-zone message time, with " ET" on the online demo; dated is 1 when it
/// carries a weekday or a date.
ClassMethod Shown(utc As %String, Output dated As %Boolean) As %String [ Private ]
{
	Set formatted = ##class(OcuTalon.Data.Time).ForMessage(utc)
	Set dated = (formatted '? 2N1":"2N)
	Quit formatted _ $Select(+##class(OcuTalon.Data.Public.Settings).Get("onlineDemo"): " ET", 1: "")
}

/// The time of a check row as the sentence shows it before any " ET": "at " and the message time, or "on " and the dated message time.
ClassMethod When(utc As %String) As %String [ Private ]
{
	Set clock = ##class(OcuTalon.Data.Time).ForMessage(utc)
	Quit $Select(clock '? 2N1":"2N: "on ", 1: "at ") _ clock
}

/// FR-20: plain text, exactly as written.
Method TestPlainText()
{
	If '..ReadyLive() Quit
	Try {
		Set ref = ..MakeChat(8501)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Outbound(ref, ..#MARKUP), .response)
		Do $$$AssertStatusOK(sc, "the message is sent")
		Set calls = ..SentTo(8501)
		Do $$$AssertEquals(calls.%Size(), 1, "one sendMessage")
		If calls.%Size() = 1 {
			Set params = calls.%Get(0).params
			Do $$$AssertEquals(params."chat_id", 8501, "to chat 8501")
			Do $$$AssertEquals(params.%GetTypeOf("chat_id"), "number", "as a JSON number")
			Do $$$AssertEquals(params.text, ..#MARKUP, "with the text byte for byte")
			Do $$$AssertEquals(params.%IsDefined("parse_mode")_"|"_params.%IsDefined("entities"), "0|0", "and no parse_mode or entities")
		}
		Set ref2 = ..MakeChat(8509)
		Set accents = "caf"_$Char(233)_" "_$Char(8364)_"100 "_$Char(55357, 56832)
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Outbound(ref2, accents), .response)
		Do $$$AssertStatusOK(sc, "a text beyond ASCII is sent")
		Set calls = ..SentTo(8509)
		Do $$$AssertEquals(calls.%Size(), 1, "one sendMessage")
		If calls.%Size() = 1 Do $$$AssertEquals(calls.%Get(0).params.text, accents, "with the text as written")
	} Catch ex {
		Do $$$AssertTrue(0, "the plain-text test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// UX-DR136: a text of over 9,000 characters is cut at line breaks.
Method TestSplitAtLineBreaks()
{
	If '..ReadyLive() Quit
	Try {
		Set ref = ..MakeChat(8502)
		Set text = ""
		For i = 1:1:101 {
			Set line = "L"_i_" "
			Set text = text _ $Select(i = 1: "", 1: $Char(10)) _ line _ $Extract($Translate($Justify("", 89), " ", "x"), 1, 89 - $Length(line))
		}
		Do $$$AssertTrue($Length(text) > 9000, "the text is over 9,000 characters")
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Outbound(ref, text), .response), "the message is sent")
		Set calls = ..SentTo(8502)
		Set texts = ..Texts(calls)
		Do $$$AssertEquals(calls.%Size(), 3, "three parts")
		Do $$$AssertTrue(..Longest(texts) <= 4096, "each is 4,096 characters or fewer")
		Do $$$AssertEquals($ListToString(texts, $Char(10)), text, "in order, and joined with a line feed they are the text")
		Set whole = 1, position = 0
		While $ListNext(texts, position, part) {
			For i = 1:1:$Length(part, $Char(10)) {
				If $Length($Piece(part, $Char(10), i)) '= 89 Set whole = 0
			}
		}
		Do $$$AssertEquals(whole, 1, "each part is cut at a line break")
	} Catch ex {
		Do $$$AssertTrue(0, "the split test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// UX-DR136: a long line is cut at the limit, and a surrogate pair is not split.
Method TestSplitOneLongLine()
{
	If '..ReadyLive() Quit
	Try {
		Set plain = ..MakeChat(8503)
		Set paired = ..MakeChat(8504)
		Set line = $Translate($Justify("", 9000), " ", "a")
		Set pair = $Char(55357, 56832)
		Set straddle = $Translate($Justify("", 4095), " ", "a")_pair_$Translate($Justify("", 5000), " ", "b")
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Outbound(plain, line), .response), "the long line is sent")
		Set texts = ..Texts(..SentTo(8503))
		Do $$$AssertEquals($ListLength(texts), 3, "three parts")
		Set lengths = ""
		Set position = 0
		While $ListNext(texts, position, part) {
			Set lengths = lengths _ $ListBuild($Length(part))
		}
		Do $$$AssertEquals($ListToString(lengths, "|"), "4096|4096|808", "cut at the limit")
		Do $$$AssertEquals($ListToString(texts, ""), line, "the parts joined with nothing are the line")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Outbound(paired, straddle), .response), "the text with the pair at the limit is sent")
		Set texts = ..Texts(..SentTo(8504))
		Do $$$AssertTrue(..Longest(texts) <= 4096, "each part is 4,096 units or fewer")
		Do $$$AssertEquals($ListToString(texts, ""), straddle, "the parts joined with nothing are the text")
		Do $$$AssertEquals($Length($ListGet(texts, 1)), 4095, "the first part stops before the pair, so that it stays whole")
	} Catch ex {
		Do $$$AssertTrue(0, "the long-line test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// UX-DR108: a 429 is retried after its retry_after, at most five tries for a part.
Method TestRateLimited()
{
	If '..ReadyLive() Quit
	Try {
		Set ref = ..MakeChat(8505)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-rate-limited"}), "a 429 with retry_after 2 is queued")
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Outbound(ref, "zz limited once"), .response)
		Do $$$AssertStatusOK(sc, "the operation returns OK")
		Set calls = ..SentTo(8505)
		Do $$$AssertEquals(calls.%Size(), 2, "two sendMessage calls")
		If calls.%Size() = 2 {
			Do $$$AssertEquals(calls.%Get(0).params.text_"|"_calls.%Get(1).params.text, "zz limited once|zz limited once", "with the same text")
			Set gap = ..Epoch(calls.%Get(1).ts) - ..Epoch(calls.%Get(0).ts)
			Do $$$AssertTrue(gap >= 1.95, "the second is at least 2 seconds after the first: "_$Justify(gap, 0, 2))
		}
		// Five 429s for the second part: the first part (a 200) stays sent, and the status is an error.
		Set ref2 = ..MakeChat(8506)
		Set limited = {"status": 429, "body": {"ok": false, "error_code": 429, "description": "Too Many Requests: retry after 1", "parameters": {"retry_after": 1}}}
		Set replies = [{"status": 200, "body": {"ok": true, "result": {"message_id": 1, "date": 0, "chat": {"id": 8506, "type": "private"}, "text": "part"}}}]
		For i = 1:1:5 Do replies.%Push(limited)
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "sendMessage", "replies": (replies)}), "a 200 and five 429s are queued")
		Set text = $Translate($Justify("", 3000), " ", "a")_$Char(10)_$Translate($Justify("", 3000), " ", "b")
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Outbound(ref2, text), .response)
		Do $$$AssertStatusNotOK(sc, "after five 429s for one part the status is an error")
		Set message = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertEquals($Find(message, ..Token), 0, "whose text holds no token")
		Do $$$AssertTrue($Find(message, "429") > 0, "and says what Telegram answered")
		Set calls = ..SentTo(8506)
		Do $$$AssertEquals(calls.%Size(), 6, "the first part was sent once and the second five times")
		If calls.%Size() = 6 {
			Set first = calls.%Get(0).params.text, second = calls.%Get(1).params.text
			Do $$$AssertEquals(($Extract(first, 1) = "a")_"|"_($Extract(second, 1) = "b"), "1|1", "part 1 first, then part 2")
			Set same = 1
			For i = 2:1:5 If calls.%Get(i).params.text '= second Set same = 0
			Do $$$AssertEquals(same, 1, "every retry sends the same part 2, and part 1 is not sent again")
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the rate-limit test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// UX-DR108: a 429 on the second part resends that part only.
Method TestSentThenLimited()
{
	If '..ReadyLive() Quit
	Try {
		Set ref = ..MakeChat(8601)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-sent-then-limited"}), "a 200 and then a 429 with retry_after 1 are queued")
		Set one = $Translate($Justify("", 3000), " ", "a")
		Set two = $Translate($Justify("", 3000), " ", "b")
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Outbound(ref, one_$Char(10)_two), .response)
		Do $$$AssertStatusOK(sc, "the operation returns OK")
		Set calls = ..SentTo(8601)
		Do $$$AssertEquals(calls.%Size(), 3, "three calls")
		If calls.%Size() = 3 {
			Do $$$AssertEquals(calls.%Get(0).params.text = one, 1, "part 1 first")
			Do $$$AssertEquals(calls.%Get(1).params.text = two, 1, "then part 2")
			Do $$$AssertEquals(calls.%Get(2).params.text = two, 1, "and part 2 again, never part 1")
			Set gap = ..Epoch(calls.%Get(2).ts) - ..Epoch(calls.%Get(1).ts)
			Do $$$AssertTrue(gap >= 0.95, "at least a second later: "_$Justify(gap, 0, 2))
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the second-part test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// A failure other than a 429 is not retried: one call, and an error status with a safe text that names the status.
Method TestOtherFailure()
{
	If '..ReadyLive() Quit
	Try {
		Set ref = ..MakeChat(8510)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set blocked = {"status": 403, "body": {"ok": false, "error_code": 403, "description": "Forbidden: bot was blocked by the user"}}
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "sendMessage", "replies": [(blocked)]}), "a 403 is queued")
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Outbound(ref, "zz blocked"), .response)
		Do $$$AssertStatusNotOK(sc, "the status is an error")
		Set message = $SYSTEM.Status.GetErrorText(sc)
		Do $$$AssertEquals($Find(message, ..Token), 0, "whose text holds no token")
		Do $$$AssertTrue($Find(message, "403") > 0, "and says what Telegram answered")
		Do $$$AssertEquals(..SentTo(8510).%Size(), 1, "the part was sent once, not again")
	} Catch ex {
		Do $$$AssertTrue(0, "the other-failure test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// AD-32: a Notification for a chat is rendered from its catalog key; a render error sends nothing. An Outbound with a catalog key and no
/// text is rendered the same way.
Method TestNotification()
{
	If '..ReadyLive() Quit
	Try {
		Set ref = ..MakeChat(8508)
		Set message = ##class(OcuTalon.Msg.Notification).%New()
		Set message.ChatRef = ref
		Set message.Kind = "pairing"
		Set message.CatalogKey = "pairing.paired"
		Set expected = ##class(OcuTalon.Msg.Catalog).Render("pairing.paired", "", "telegram", .sc)
		Do $$$AssertStatusOK(sc, "the catalog renders the key")
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", message, .response), "the notification is sent")
		Set calls = ..SentTo(8508)
		Do $$$AssertEquals(calls.%Size(), 1, "one sendMessage")
		If calls.%Size() = 1 Do $$$AssertEquals(calls.%Get(0).params.text, expected, "with the catalog text for Telegram")
		Set bad = ##class(OcuTalon.Msg.Notification).%New()
		Set bad.ChatRef = ref
		Set bad.Kind = "pairing"
		Set bad.CatalogKey = "zz.noSuchKey"
		Do $$$AssertStatusNotOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", bad, .response), "a key that cannot be rendered is an error status")
		Do $$$AssertEquals(..SentTo(8508).%Size(), 1, "and nothing more is sent")
		Set reply = ..Outbound(ref, "")
		Set reply.CatalogKey = "pairing.paired"
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", reply, .response), "an Outbound with a catalog key and no text is sent")
		Set calls = ..SentTo(8508)
		Do $$$AssertEquals(calls.%Size(), 2, "as one more sendMessage")
		If calls.%Size() = 2 Do $$$AssertEquals(calls.%Get(1).params.text, expected, "with the catalog text for Telegram")
	} Catch ex {
		Do $$$AssertTrue(0, "the notification test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// AD-14, AD-4: a message with a SessionRef and no ChatRef goes to the session's paired chat and records its Delivery row; a session with
/// no pairing and an owner that is not a session send nothing.
Method TestBySession()
{
	If '..ReadyLive() Quit
	Try {
		Set session = ..NewSessionRef()
		Set unpaired = ..NewSessionRef()
		Set ref = ..PairedChat(8601, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Set notice = ..TellNow(session, "zz Disk almost full")
		Set expected = ##class(OcuTalon.Msg.Catalog).Render("notice.tellNow", notice.Slots, "telegram")
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", notice, .response), "(a) a tellnow Notification with a SessionRef and no ChatRef is sent")
		Set calls = ..SentTo(8601)
		Do $$$AssertEquals(calls.%Size(), 1, "it reaches the session's chat")
		If calls.%Size() = 1 Do $$$AssertEquals(calls.%Get(0).params.text, expected, "as the catalog's text for Telegram")
		Set first = "tellnow||"_ref_":"_..LastId(8601)
		Do $$$AssertEquals(..Rows(session), first, "and records one telegram Delivery row of the session, of kind tellnow, with <ChatRef>:<message_id>")

		Set reply = ..ForSession(session, "zz reply by session")
		Set reply.DecisionRef = "zzdecision8601"
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", reply, .response), "(b) an Outbound with a SessionRef and no ChatRef is sent")
		Set calls = ..SentTo(8601)
		Do $$$AssertEquals(calls.%Size(), 2, "it reaches the same chat")
		If calls.%Size() = 2 Do $$$AssertEquals(calls.%Get(1).params.text, "zz reply by session", "with its text")
		Do $$$AssertEquals(..Rows(session), first_",||"_ref_":"_..LastId(8601), "and records a second row, of kind empty, with the second message's id")
		Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
		Do $$$AssertEquals($Select(rows.Count(): rows.GetAt(rows.Count()).DecisionRef, 1: ""), "zzdecision8601", "and the reply's DecisionRef")

		Set log = $ClassMethod(fixture, "EventMark")
		Set before = ..CallsOf("sendMessage").%Size()
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..ForSession(unpaired, "zz nobody"), .response), "(c) an Outbound for a session with no pairing is OK")
		Do $$$AssertEquals(..Warned(log, "names no known Telegram chat"), 1, "with one no-chat warning")
		Do $$$AssertEquals(..Rows(unpaired), "", "and no row")
		Set instances = ##class(OcuTalon.Test.Core.Observe).DeliveryCount("instance")
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..ForSession("instance", "zz nobody"), .response), "(d) an Outbound for the owner instance is OK")
		Do $$$AssertEquals(..Warned(log, "its owner is not a session"), 1, "with one not-a-session warning")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).DeliveryCount("instance"), instances, "and no row")
		Do $$$AssertEquals(..CallsOf("sendMessage").%Size(), before, "neither sent anything")
	} Catch ex {
		Do $$$AssertTrue(0, "the by-session test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// DW-30: a rendered notice over 4,096 characters goes in parts of at most 4,096 that together are the text; the row holds the last id.
Method TestLongNotice()
{
	If '..ReadyLive() Quit
	Try {
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(8602, session)
		Set words = ""
		While $Length(words) < 5000 {
			Set words = words _ "word" _ $Length(words) _ " "
		}
		Set words = $Extract(words, 1, 5000)
		Set words = $Extract(words, 1, 4999) _ "x"
		Set notice = ..TellNow(session, words)
		Set expected = ##class(OcuTalon.Msg.Catalog).Render("notice.tellNow", notice.Slots, "telegram", .sc)
		Do $$$AssertStatusOK(sc, "the catalog renders the long notice")
		Do $$$AssertTrue($Length(expected) > 5000, "the rendered notice is over 5,000 characters")
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", notice, .response), "the notice is sent")
		Set calls = ..SentTo(8602)
		Set texts = ..Texts(calls)
		Do $$$AssertTrue(calls.%Size() >= 2, "it goes in two parts or more")
		Do $$$AssertTrue(..Longest(texts) <= 4096, "each part is 4,096 UTF-16 units or fewer")
		Do $$$AssertEquals($ListToString(texts, ""), expected, "and the parts together are the rendered text")
		Do $$$AssertEquals(..Rows(session), "tellnow||"_ref_":"_..LastId(8602), "one Delivery row holds the id of the last part")
	} Catch ex {
		Do $$$AssertTrue(0, "the long-notice test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// DW-295, AD-28: the check sentence follows the reply, built from the key and the rows as the page builds it.
Method TestCheckSentence()
{
	If '..ReadyLive() Quit
	Set settings = "OcuTalon.Data.Public.Settings"
	Set savedDemo = $ClassMethod(settings, "Get", "onlineDemo")
	Try {
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(8603, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Set now = ##class(OcuTalon.Data.Time).NowUtc()
		Set recent = ##class(OcuTalon.Data.Time).AddSeconds(now, -120)
		Set old = ##class(OcuTalon.Data.Time).AddSeconds(now, -3 * 86400)
		Set rest = ##class(OcuTalon.Msg.Catalog).Render("checks.everythingElsePassed", "", "telegram")
		Set blank = $Char(10, 10)

		Set rows = [{"result": "passed", "entry": "Alpha", "finding": "", "checkedAt": (recent)}, {"result": "not_checked", "entry": "Beta", "finding": "Not run yet", "checkedAt": ""}, {"result": "failed", "entry": "Gamma", "finding": "Stopped", "checkedAt": (recent)}]
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..WithChecks(session, "checks.notEverythingRestPassed", rows), .response), "(a) a reply with checks.notEverythingRestPassed is sent")
		Set shown = ..Shown(recent, .dated)
		Set calls = ..SentTo(8603)
		Do $$$AssertEquals(calls.%Size(), 1, "as one message")
		If calls.%Size() = 1 Do $$$AssertEquals(calls.%Get(0).params.text, "zz reply"_blank_"Not everything: Gamma (stopped, "_$Select(dated: "on ", 1: "at ")_shown_"); Beta (not run yet). "_rest, "the failed row comes first, with its time, then the other; the passed row is not named")

		Set rows = [{"result": "failed", "entry": "Gamma", "finding": "Stopped", "checkedAt": (old)}, {"result": "passed", "entry": "Alpha", "finding": "", "checkedAt": (recent)}]
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..WithChecks(session, "checks.notEverythingRestPassed", rows), .response), "(b) the same with a failure checked three days ago")
		Set shown = ..Shown(old, .dated)
		Do $$$AssertTrue(dated, "its time carries a weekday")
		Set calls = ..SentTo(8603)
		If calls.%Size() = 2 Do $$$AssertEquals(calls.%Get(1).params.text, "zz reply"_blank_"Not everything: Gamma (stopped, on "_shown_"). "_rest, "the sentence says on and the dated time")

		Set rows = [{"result": "passed", "entry": "Alpha", "finding": "", "checkedAt": (recent)}, {"result": "passed", "entry": "Beta", "finding": "", "checkedAt": (recent)}]
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..WithChecks(session, "checks.allPassed", rows), .response), "(c) a reply with checks.allPassed is sent")
		Set calls = ..SentTo(8603)
		If calls.%Size() = 3 Do $$$AssertEquals(calls.%Get(2).params.text, "zz reply"_blank_"Everything I checked passed.", "the all-clear is the catalog text, from the key")

		Set rows = [{"result": "passed", "entry": "Alpha", "finding": "", "checkedAt": (recent)}]
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..WithChecks(session, "checks.notEverything", rows), .response), "(d) a reply with checks.notEverything and only a passed row is sent")
		Set calls = ..SentTo(8603)
		If calls.%Size() = 4 Do $$$AssertEquals(calls.%Get(3).params.text, "zz reply", "it goes alone: the rows never make an all-clear")

		Set log = $ClassMethod(fixture, "EventMark")
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..WithChecks(session, "checks.nope", rows), .response), "(e) a reply with an unknown check key is sent")
		Set calls = ..SentTo(8603)
		If calls.%Size() = 5 Do $$$AssertEquals(calls.%Get(4).params.text, "zz reply", "it goes alone")
		Do $$$AssertEquals(..Warned(log, "without its check sentence"), 1, "with one warning")

		Set rows = [{"result": "failed", "entry": "Gamma", "finding": "Stopped", "checkedAt": (recent)}]
		Do $ClassMethod(settings, "Set", "onlineDemo", 1)
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..WithChecks(session, "checks.notEverythingRestPassed", rows), .response), "(f) a reply on the online demo is sent")
		Do $ClassMethod(settings, "Set", "onlineDemo", savedDemo)
		Set calls = ..SentTo(8603)
		If calls.%Size() = 6 Do $$$AssertEquals(calls.%Get(5).params.text, "zz reply"_blank_"Not everything: Gamma (stopped, "_..When(recent)_" ET). "_rest, "the time is followed by ET")

		Set rows = [{"result": "failed", "entry": "Delta", "finding": "", "checkedAt": ""}, {"result": "failed", "entry": "Epsilon", "finding": "", "checkedAt": (recent)}, {"result": "failed", "entry": "", "finding": "Orphan", "checkedAt": (recent)}, {"result": "failed", "entry": "Zeta", "finding": "Broke", "checkedAt": ""}]
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..WithChecks(session, "checks.notEverythingRestPassed", rows), .response), "(g) a reply whose rows have an entry only, a time only, no entry and a finding only is sent")
		Set calls = ..SentTo(8603)
		If calls.%Size() = 7 Do $$$AssertEquals(calls.%Get(6).params.text, "zz reply"_blank_"Not everything: Delta; Epsilon ("_..When(recent)_"); Zeta (broke). "_rest, "an entry alone is named, a time alone follows at or on, a row with no entry is left out")

		For bad = "not json", "{}" {
			Set reply = ..WithChecks(session, "checks.notEverythingRestPassed", "")
			Set reply.CheckRows = bad
			Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", reply, .response), "(h) a reply whose CheckRows are '"_bad_"' is sent")
			Set calls = ..SentTo(8603)
			If calls.%Size() > 7 Do $$$AssertEquals(calls.%Get(calls.%Size() - 1).params.text, "zz reply", "it goes alone")
		}

		Set rows = [{"result": "failed", "entry": "Gamma", "finding": "Stopped", "checkedAt": (recent)}, {"result": "not_checked", "entry": "Beta", "finding": "Not run yet", "checkedAt": ""}]
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..WithChecks(session, "checks.notEverything", rows), .response), "(i) a reply with checks.notEverything and a failed row is sent")
		Set calls = ..SentTo(8603)
		If calls.%Size() = 10 Do $$$AssertEquals(calls.%Get(9).params.text, "zz reply"_blank_"Not everything: Gamma (stopped, "_..When(recent)_"); Beta (not run yet).", "nothing passed: the sentence names what failed and claims nothing else")

		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..WithChecks(session, "checks.everythingElsePassed", rows), .response), "(j) a reply with checks.everythingElsePassed is sent")
		Set calls = ..SentTo(8603)
		If calls.%Size() = 11 Do $$$AssertEquals(calls.%Get(10).params.text, "zz reply"_blank_"Everything else I checked passed.", "the key's catalog text, as the page gives it")
		Do $$$AssertEquals(..SentTo(8603).%Size(), 11, "all eleven replies were sent")
		Do $$$AssertEquals($Length(..Rows(session), ","), 11, "and every one of the eleven replies has its Delivery row")
	} Catch ex {
		Do $$$AssertTrue(0, "the check-sentence test failed: "_..Safe(ex))
	}
	Do $ClassMethod(settings, "Set", "onlineDemo", savedDemo)
	Do ..Cleanup()
}

/// A Notification of a kind that has no Telegram form (status, digest, fallback) sends nothing and records no row; a tellnow one before
/// them does, so that the silence is not a broken path.
Method TestOtherKinds()
{
	If '..ReadyLive() Quit
	Try {
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(8604, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..TellNow(session, "zz Disk almost full"), .response), "a tellnow Notification is sent")
		Do $$$AssertEquals(..SentTo(8604).%Size(), 1, "it reaches the chat")
		Set row = "tellnow||"_ref_":"_..LastId(8604)
		Do $$$AssertEquals(..Rows(session), row, "and has its row")
		For kind = "status", "digest", "fallback" {
			Set notice = ..TellNow(session, "zz Disk almost full")
			Set notice.Kind = kind
			Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", notice, .response), "a Notification of kind "_kind_" is sent")
		}
		Do $$$AssertEquals(..SentTo(8604).%Size(), 1, "none of the three reaches the chat")
		Do $$$AssertEquals(..Rows(session), row, "and none records a row")
	} Catch ex {
		Do $$$AssertTrue(0, "the other-kinds test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// A ChatRef with no chat row, and no ChatRef: no call, one warning that names neither, and OK.
Method TestNoChat()
{
	If '..ReadyLive() Quit
	Try {
		Set probe = ..MakeChat(8511)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Outbound(probe, "zz drain"), .response), "a message of the test is sent first, so that any queued before it are handled")
		Do $$$AssertEquals(..SentTo(8511).%Size(), 1, "and it reached the Bot API")
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set before = ..CallsOf("sendMessage").%Size()
		Set unknown = "zznochat1234567"
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Outbound(unknown, "zz nobody"), .response), "a ChatRef with no row is OK")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Outbound("", "zz nobody"), .response), "no ChatRef is OK")
		Do $$$AssertEquals(..CallsOf("sendMessage").%Size(), before, "no call is made")
		Set rows = ##class(OcuTalon.Test.Agent.RunnerFixture).EventRows(log, "TelegramOut")
		Set told = 0, names = 0, position = 0
		While $ListNext(rows, position, row) {
			If ($Extract(row, 1, 2) = "3:") && ($Find(row, "names no known Telegram chat") > 0) Set told = told + 1
			If $Find(row, unknown) > 0 Set names = names + 1
		}
		Do $$$AssertEquals(told, 2, "one warning for each message")
		Do $$$AssertEquals(names, 0, "and no warning names the Ref")
	} Catch ex {
		Do $$$AssertTrue(0, "the no-chat test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

}
