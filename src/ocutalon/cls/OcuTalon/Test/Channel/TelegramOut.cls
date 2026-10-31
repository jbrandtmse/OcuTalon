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
///   - TestNotification: a Notification for a chat sends the catalog rendering, and a render error sends nothing;
///   - TestNoChat: a ChatRef with no chat row, or none, sends nothing, logs one warning that names neither, and is OK.
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

/// AD-32: a Notification for a chat is rendered from its catalog key; a render error sends nothing.
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
	} Catch ex {
		Do $$$AssertTrue(0, "the notification test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// A ChatRef with no chat row, and no ChatRef: no call, one warning that names neither, and OK.
Method TestNoChat()
{
	If '..ReadyLive() Quit
	Try {
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
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
