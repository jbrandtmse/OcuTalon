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
///   - TestLearnedLines (Story 41.15): the learned saves of a reply follow it, after its check sentence when there is one, as the ruled line for each entry (one trailing full stop removed, a long fact cut to 200
///     characters with an ellipsis), one per line after a blank line; markup is sent as written with no parse_mode; a reply that already says "I'll remember" adds nothing;
///   - TestSummary (Story 23.6; AC 14): a summary Notification is one plain-text message to the paired chat with the stored summary's lines and the markup of the
///     cause, the evidence and the sample error as it is, no parse_mode and no buttons; a missing summary sends nothing;
///   - TestSummaryBuilt (QA; AC 14): the summary that Watch.Summary.Build makes of an incident whose cause, fix and sample error hold markup (the sample error longer than a notice's
///     error summary) is one plain-text message, with no parse mode, whose text shows the markup as it came and the sample error cut to the notice's length;
///   - TestOtherKinds: a Notification of kind status or fallback sends nothing and records no row, where one of kind tellnow does;
///   - TestButtons (Story 12.7; AC1): an incident notice and a later approval request with an ApprovalRef go as one sendMessage whose
///     reply_markup holds the Approve and Reject buttons with callback data approve:<Ref> and reject:<Ref>; a 5,000-character request notice
///     goes in parts of at most 3,840 units with the buttons on the last part only; the Delivery row records the Ref and the last part's
///     text, the redacted text with no chat id, name or Telegram user name (a stored text that the redactor cannot check is "");
///   - TestNoButtons: an incident with no ApprovalRef, and the kinds tellnow, result (also with a Ref), reminder and an Outbound, go with
///     no reply_markup and a Delivery row with no text;
///   - TestEditApproved, TestEditOnlineDemo (AC3): an answered notification edits the request's message in place: editMessageText with
///     the chat, the message_id, the stored text, a blank line and the status, and no reply_markup; the row of the kind answered holds the
///     same id and Ref and no text; on the online demo the status ends " ET.";
///   - TestEditOnce: a second answered notification edits nothing (the first answer stays), and an answered notification for a request with
///     no telegram row, or a row with no text, edits nothing and logs one warning;
///   - TestRejectedFollowUp: a rejection from Telegram of a fix edits the message and then sends the follow-up as a new message, whose
///     row is of the kind answered with no Ref; a rejection from the web chat, or one with no IncidentRef, only edits;
///   - TestEditRateLimited, TestEditElsewhere, TestEditWarnings (QA): a 429 on the edit is sent again after its retry_after and edits the
///     message once; a request answered on the web chat or the phone, with a name, or expired, is edited with that answer's status and
///     gets no follow-up; every edit that cannot be made (no row, no chat row, no message id, a failed edit) is one warning that names no
///     Ref, chat id, chat or message text;
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

/// Story 41.15, AD-21, AD-28: the learned saves of a reply follow it, and its check sentence when there is one, as lines of plain text. The exact sent text is the reply, a blank line, then the ruled line for each entry
/// (the stored text with one trailing full stop removed, cut to 200 characters with an ellipsis), one per line; markup is sent as written with no parse_mode; a reply that already says "I'll remember" adds nothing; and
/// an Outbound with no entry is the reply alone.
Method TestLearnedLines()
{
	If '..ReadyLive() Quit
	Try {
		Set session = ..NewSessionRef()
		Set chatId = 8645
		Set ref = ..PairedChat(chatId, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Set blank = $Char(10, 10)
		Set ellipsis = $Char(8230)
		Set line = "I'll remember this: ""{fact}"". You can tell me to forget it."

		Set message = ..ForSession(session, "Noted.")
		Set message.Learned = [{"memoryRef": "zzm1", "text": "The Results partner's contact is Lee."}].%ToJSON()
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", message, .response), "(a) a reply with one learned entry is sent")
		Set calls = ..SentTo(chatId)
		Do $$$AssertEquals(calls.%Size(), 1, "as one message")
		If calls.%Size() = 1 {
			Set params = calls.%Get(0).params
			Do $$$AssertEquals(params.text, "Noted."_blank_"I'll remember this: ""The Results partner's contact is Lee"". You can tell me to forget it.", "the reply, a blank line, and the ruled line with one full stop removed")
			Do $$$AssertEquals(params.%IsDefined("parse_mode")_"|"_params.%IsDefined("entities"), "0|0", "plain text: no parse_mode and no entities")
		}

		Set message = ..ForSession(session, "Noted again.")
		Set message.Learned = [{"memoryRef": "zzm1", "text": "<b>Lee</b> & *co* [x](y)"}, {"memoryRef": "zzm2", "text": "Second fact"}].%ToJSON()
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", message, .response), "(b) markup in the facts, and two entries")
		Set calls = ..SentTo(chatId)
		Do $$$AssertEquals(calls.%Size(), 2, "it adds one more message")
		If calls.%Size() = 2 {
			Do $$$AssertEquals(calls.%Get(1).params.text, "Noted again."_blank_$Replace(line, "{fact}", "<b>Lee</b> & *co* [x](y)")_$Char(10)_$Replace(line, "{fact}", "Second fact"), "the markup is sent as written and the lines are in order, one per line")
			Do $$$AssertEquals(calls.%Get(1).params.%IsDefined("parse_mode"), 0, "with no parse_mode")
		}

		Set long = $Translate($Justify("", 300), " ", "c")
		Set message = ..ForSession(session, "Noted long.")
		Set message.Learned = [{"memoryRef": "zzm3", "text": (long)}].%ToJSON()
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", message, .response), "(c) a 300-character fact")
		Set calls = ..SentTo(chatId)
		Do $$$AssertEquals(calls.%Size(), 3, "it adds one more message")
		If calls.%Size() = 3 Do $$$AssertEquals(calls.%Get(2).params.text, "Noted long."_blank_$Replace(line, "{fact}", $Extract(long, 1, 199)_ellipsis), "is cut to 199 characters and an ellipsis")

		Set message = ..ForSession(session, "I'll remember that Lee is the contact.")
		Set message.Learned = [{"memoryRef": "zzm1", "text": "Lee is the contact."}].%ToJSON()
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", message, .response), "(d) a reply that already says it")
		Set calls = ..SentTo(chatId)
		Do $$$AssertEquals(calls.%Size(), 4, "it adds one more message")
		If calls.%Size() = 4 Do $$$AssertEquals(calls.%Get(3).params.text, "I'll remember that Lee is the contact.", "adds nothing")

		Set message = ..ForSession(session, "Done.")
		Set message.Learned = "[]"
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", message, .response), "(e) a reply with no entry")
		Set calls = ..SentTo(chatId)
		Do $$$AssertEquals(calls.%Size(), 5, "it adds one more message")
		If calls.%Size() = 5 Do $$$AssertEquals(calls.%Get(4).params.text, "Done.", "goes alone")

		Set now = ##class(OcuTalon.Data.Time).NowUtc()
		Set recent = ##class(OcuTalon.Data.Time).AddSeconds(now, -120)
		Set message = ..WithChecks(session, "checks.allPassed", [{"result": "passed", "entry": "Alpha", "finding": "", "checkedAt": (recent)}])
		Set message.Learned = [{"memoryRef": "zzm1", "text": "Lee is the contact."}].%ToJSON()
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", message, .response), "(f) a reply with a check sentence and an entry")
		Set calls = ..SentTo(chatId)
		Do $$$AssertEquals(calls.%Size(), 6, "it adds one more message")
		If calls.%Size() = 6 Do $$$AssertEquals(calls.%Get(5).params.text, "zz reply"_blank_"Everything I checked passed."_blank_$Replace(line, "{fact}", "Lee is the contact"), "the check sentence comes first, then the line")
	} Catch ex {
		Do $$$AssertTrue(0, "the learned-lines test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// An incident summary (Story 23.6; AC 14): a Notification of kind summary goes to the session's paired chat as one plain-text message, whose text is
/// OcuTalon.Watch.Summary.Text(IncidentRef, "telegram"): the stored summary's lines with the markup of the cause, the evidence and the sample error left as it is,
/// with no parse_mode, no entities and no reply_markup (no Approve or Reject), and a Delivery row of the kind summary with no text. A summary that is missing sends
/// nothing and is an error.
Method TestSummary()
{
	If '..ReadyLive() Quit
	Set incident = ""
	Try {
		Set chatId = 8631
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(chatId, session)
		Set parts = [{"key": "summary.title", "slots": {"count": 50, "itemNoun": {"one": "order", "other": "orders"}, "production": "Orders"}}, {"key": "summary.cause", "slots": {"cause": "The partner sent <b>x</b> and *y* in the date."}}, {"key": "summary.evidence", "slots": {"evidence": "OrderDate was <i>16/10/2026</i> and _z_ [a](b)"}}, {"key": "summary.sampleError", "slots": {"error": "Field `OrderDate` was not a date."}}, {"key": "summary.messages", "slots": {"failed": 50, "resent": 50, "completed": 50, "failedAgain": 0, "skipped": 0}}]
		Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(session, , , , {"State": "closed", "ClosedAt": (##class(OcuTalon.Data.Time).NowUtc()), "Summary": ({"parts": (parts), "lines": []}.%ToJSON())})
		Set expected = "Incident summary: 50 orders failed in Orders."
			_$Char(10)_"Cause: The partner sent <b>x</b> and *y* in the date."
			_$Char(10)_"Evidence: OrderDate was <i>16/10/2026</i> and _z_ [a](b)."
			_$Char(10)_"Sample error: Field `OrderDate` was not a date."
			_$Char(10)_"Messages: 50 failed, 50 resent, 50 completed, 0 failed again, 0 skipped."
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set notice = ##class(OcuTalon.Msg.Notification).%New()
		Set notice.SessionRef = session
		Set notice.Kind = "summary"
		Set notice.CatalogKey = "summary.title"
		Set notice.Slots = "{}"
		Set notice.IncidentRef = incident
		Set notice.DecisionRef = ..NewRef()
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", notice, .response), "the summary is sent")
		Set calls = ..SentTo(chatId)
		Do $$$AssertEquals(calls.%Size(), 1, "one sendMessage")
		If calls.%Size() = 1 {
			Set params = calls.%Get(0).params
			Do $$$AssertEquals(params.text, expected, "the text is the stored summary's lines, exactly as written")
			Do $$$AssertEquals(params.text, ##class(OcuTalon.Watch.Summary).Text(incident, "telegram"), "and Watch.Summary.Text for Telegram")
			Do $$$AssertEquals(params.%IsDefined("parse_mode")_"|"_params.%IsDefined("entities")_"|"_params.%IsDefined("reply_markup"), "0|0|0", "with no parse_mode, no entities and no buttons")
		}
		Do $$$AssertEquals(..Rows(session), "summary||"_ref_":"_..LastId(chatId), "the Delivery row is of the kind summary, with no approval Ref")
		Set rows = ..TelegramRows(session)
		Do $$$AssertEquals(rows.Count()_"|"_rows.GetAt(1).Text, "1|", "and keeps no text")
		Set bare = ##class(OcuTalon.Test.Data.Fixture).Incident(session, , , , {"State": "closed"})
		Set missing = ##class(OcuTalon.Msg.Notification).%New()
		Set missing.SessionRef = session
		Set missing.Kind = "summary"
		Set missing.CatalogKey = "summary.title"
		Set missing.Slots = "{}"
		Set missing.IncidentRef = bare
		Do $$$AssertStatusNotOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", missing, .response), "an incident with no summary is an error")
		Do $$$AssertEquals(..SentTo(chatId).%Size(), 1, "and nothing more is sent")
		Do ##class(OcuTalon.Test.Data.Fixture).Clean(bare)
	} Catch ex {
		Do $$$AssertTrue(0, "the summary test failed: "_..Safe(ex))
	}
	If incident '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(incident)
	Do ..Cleanup()
}

/// AC 14 (QA), Telegram: an incident whose rows hold markup is summarized by Watch.Summary.Build (Test.Watch.Summary.Built), and the message that TelegramOut sends is
/// plain text (no parse_mode, no entities, no buttons) that shows the cause and the sample error as they came: the markup literally, the sample error cut to an incident
/// notice's length, one line each.
Method TestSummaryBuilt()
{
	If '..ReadyLive() Quit
	Set incident = ""
	Try {
		Set chatId = 8632
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(chatId, session)
		Set incident = ##class(OcuTalon.Test.Watch.Summary).Built(session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set notice = ##class(OcuTalon.Msg.Notification).%New()
		Set notice.SessionRef = session
		Set notice.Kind = "summary"
		Set notice.CatalogKey = "summary.title"
		Set notice.Slots = "{}"
		Set notice.IncidentRef = incident
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", notice, .response), "the built summary is sent")
		Set calls = ..SentTo(chatId)
		Do $$$AssertEquals(calls.%Size(), 1, "one sendMessage")
		If calls.%Size() = 1 {
			Set params = calls.%Get(0).params
			Set cut = ##class(OcuTalon.Test.Watch.Summary).CutLine()
			Do $$$AssertTrue($Length(cut) '> $Parameter("OcuTalon.Watch.ErrorText", "SUMMARYMAX"), "the cut is no longer than a notice's error summary")
			Do $$$AssertTrue(params.text [ ($Char(10)_"Cause: The partner sent <b>x</b> and *y*."_$Char(10)), "the cause shows its markup literally")
			Do $$$AssertTrue(params.text [ ($Char(10)_"Sample error: "_cut_$Char(10)), "and the sample error is the cut, with its markup: "_cut)
			Do $$$AssertTrue(params.text '[ ##class(OcuTalon.Test.Watch.Summary).#LONGMARKUP, "the whole sample error is not in the message")
			Do $$$AssertEquals(params.%IsDefined("parse_mode")_"|"_params.%IsDefined("entities")_"|"_params.%IsDefined("reply_markup"), "0|0|0", "with no parse_mode, no entities and no buttons")
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the built summary test failed: "_..Safe(ex))
	}
	If incident '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(incident)
	Do ..Cleanup()
}

/// A Notification of a kind that has no Telegram form (status, fallback) sends nothing and records no row; a tellnow one before
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
		For kind = "status", "fallback" {
			Set notice = ..TellNow(session, "zz Disk almost full")
			Set notice.Kind = kind
			Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", notice, .response), "a Notification of kind "_kind_" is sent")
		}
		Do $$$AssertEquals(..SentTo(8604).%Size(), 1, "neither reaches the chat")
		Do $$$AssertEquals(..Rows(session), row, "and none records a row")
	} Catch ex {
		Do $$$AssertTrue(0, "the other-kinds test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// The Ref of a new approval request (22 characters).
ClassMethod NewRef() As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Ids).NewRef()
}

/// The telegram Delivery rows of the session, oldest first, as a list of Delivery objects.
Method TelegramRows(session As %String) As %ListOfObjects [ Private ]
{
	Set found = ##class(%ListOfObjects).%New()
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	For i = 1:1:rows.Count() {
		If rows.GetAt(i).Channel = "telegram" Do found.Insert(rows.GetAt(i))
	}
	Quit found
}

/// An incident Notification for the session with the incident.withFix slots, the Ref of its request and the kind.
ClassMethod Request(session As %String, approvalRef As %String, kind As %String = "incident", key As %String = "incident.withFix") As OcuTalon.Msg.Notification [ Private ]
{
	Quit ..Notification(session, kind, key, ..FixtureSlots(key), approvalRef)
}

/// An answered Notification for the request: the catalog key and slots, with the incident Ref when given.
ClassMethod Answered(session As %String, approvalRef As %String, key As %String, slots As %DynamicObject, incidentRef As %String = "") As OcuTalon.Msg.Notification [ Private ]
{
	Quit ..Notification(session, "answered", key, slots, approvalRef, incidentRef)
}

/// AC1, U-218: the buttons go on the last part of a request notice, and its Delivery row keeps the Ref and the redacted last part.
Method TestButtons()
{
	If '..ReadyLive() Quit
	Try {
		Set chatId = 8620
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(chatId, session)
		Set result = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.Pairing SET DisplayName = ? WHERE Ref = ?", "Zqbuttonname", ref)
		Do $$$AssertEquals(result.%SQLCODE, 0, "the fixture chat has a name")
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Set first = ..NewRef(), later = ..NewRef(), long = ..NewRef()

		Set notice = ..Request(session, first)
		Set expected = ##class(OcuTalon.Msg.Catalog).Render("incident.withFix", notice.Slots, "telegram")
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", notice, .response), "(a) an incident notice with an ApprovalRef is sent")
		Set calls = ..SentTo(chatId)
		Do $$$AssertEquals(calls.%Size(), 1, "as one sendMessage")
		Set id1 = ..LastId(chatId)
		If calls.%Size() = 1 {
			Do $$$AssertEquals(calls.%Get(0).params.text, expected, "with the catalog text")
			Do $$$AssertEquals(calls.%Get(0).params."reply_markup".%ToJSON(), {"inline_keyboard": [[{"text": "Approve", "callback_data": ("approve:"_first)}, {"text": "Reject", "callback_data": ("reject:"_first)}]]}.%ToJSON(), "and exactly the Approve and Reject buttons, whose data is the action and the request's Ref")
		}

		Set notice = ..Request(session, later, "approval", "incident.laterRequest")
		Set expectedLater = ##class(OcuTalon.Msg.Catalog).Render("incident.laterRequest", notice.Slots, "telegram")
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", notice, .response), "(b) a later request of kind approval is sent")
		Set calls = ..SentTo(chatId)
		Do $$$AssertEquals(calls.%Size(), 2, "as one more sendMessage")
		Set id2 = ..LastId(chatId)
		If calls.%Size() = 2 Do $$$AssertEquals(calls.%Get(1).params."reply_markup".%ToJSON(), {"inline_keyboard": [[{"text": "Approve", "callback_data": ("approve:"_later)}, {"text": "Reject", "callback_data": ("reject:"_later)}]]}.%ToJSON(), "with its own buttons")

		Set words = ""
		While $Length(words) < 5000 {
			Set words = words _ "word" _ $Length(words) _ " "
		}
		Set words = $Extract(words, 1, 4999) _ "x"
		Set notice = ..Notification(session, "approval", "notice.tellNow", {"whatHappened": (words), "reason": "you asked to hear about disk space, password=zzhunter2"}, long)
		Set expectedLong = ##class(OcuTalon.Msg.Catalog).Render("notice.tellNow", notice.Slots, "telegram", .sc)
		Do $$$AssertStatusOK(sc, "(c) the 5,000-character notice renders")
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", notice, .response), "the 5,000-character request notice is sent")
		Set all = ..SentTo(chatId)
		Set parts = [], count = 0
		For i = 2:1:all.%Size() - 1 {
			Do parts.%Push(all.%Get(i))
		}
		Set count = parts.%Size()
		Do $$$AssertTrue(count >= 2, "it goes in two parts or more")
		Set joined = "", longest = 0, marked = 0, lastMarked = 0
		For i = 0:1:count - 1 {
			Set params = parts.%Get(i).params
			Set joined = joined _ params.text
			If $Length(params.text) > longest Set longest = $Length(params.text)
			If params.%IsDefined("reply_markup") {
				Set marked = marked + 1
				If i = (count - 1) Set lastMarked = 1
			}
		}
		Do $$$AssertTrue(longest <= 3840, "each part is 3,840 UTF-16 units or fewer")
		Do $$$AssertEquals(joined, expectedLong, "and the parts together are the rendered text")
		Do $$$AssertEquals(marked_"|"_lastMarked, "1|1", "only the last part has the buttons")
		Set lastText = $Select(count: parts.%Get(count - 1).params.text, 1: "")

		Set rows = ..TelegramRows(session)
		Do $$$AssertEquals(rows.Count(), 3, "(d) three telegram Delivery rows, one for each notice")
		If rows.Count() = 3 {
			Do $$$AssertEquals(rows.GetAt(1).Kind_"|"_rows.GetAt(1).ApprovalRef_"|"_rows.GetAt(1).ChannelMessageId, "incident|"_first_"|"_ref_":"_id1, "the first row has the Ref and the message id")
			Do $$$AssertEquals(rows.GetAt(2).Kind_"|"_rows.GetAt(2).ApprovalRef_"|"_rows.GetAt(2).ChannelMessageId, "approval|"_later_"|"_ref_":"_id2, "the second too, of kind approval")
			Do $$$AssertEquals(rows.GetAt(3).ApprovalRef, long, "the third has the Ref of the long notice")
			Do $$$AssertEquals(rows.GetAt(1).Text, ##class(OcuTalon.Bridge.Redact).Text(expected), "the first row's Text is the redacted text that was sent")
			Do $$$AssertEquals(rows.GetAt(2).Text, ##class(OcuTalon.Bridge.Redact).Text(expectedLater), "the second row's too")
			Do $$$AssertEquals(rows.GetAt(3).Text, ##class(OcuTalon.Bridge.Redact).Text(lastText), "the third row's Text is the redacted text of the last part only")
			Do $$$AssertTrue($Find(lastText, "password=zzhunter2") > 0, "control: the last part that was sent holds a password")
			Do $$$AssertEquals(($Find(rows.GetAt(3).Text, "zzhunter2") > 0)_"|"_($Find(rows.GetAt(3).Text, "password=[redacted]") > 0), "0|1", "the third row's Text holds it redacted, not as sent")
			For i = 1:1:3 {
				Set text = rows.GetAt(i).Text
				Do $$$AssertTrue(text '= "", "row "_i_" has a stored text")
				Do $$$AssertEquals(($Find(text, chatId) > 0)_"|"_($Find(text, "Zqbuttonname") > 0)_"|"_($Find(text, "Zqfrom") > 0)_"|"_($Find(text, "zqfromuser") > 0), "0|0|0|0", "row "_i_"'s text holds no chat id, no chat name and no Telegram user name")
			}
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the buttons test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// Story 21.10 (V4, V8, V9): a tool call's request whose text is over 4,096 units is one message with no buttons: its head, a line break and the line of toolCall.inputsTooLong,
/// at most 3,840 units, the head cut after a line break where it can be; its Delivery row keeps the Ref and the text, and an answered.canceled notification then edits it in place.
Method TestToolCallTooLong()
{
	If '..ReadyLive() Quit
	Try {
		Set chatId = 8630
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(chatId, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Set line = "The inputs are too long to show here. See them on your OcuTalon page before you approve."
		Set big = ""
		For i = 1:1:500 Set big = big_"0123456789"
		Set approval = ..NewRef()
		Set slots = {"tool": "zz_t", "server": "zzS", "inputs": [{"name": "note", "value": (""""_big_"""")}]}
		Set rendered = ##class(OcuTalon.Msg.Catalog).Render("toolCall.requestOnServer", slots, "telegram")
		Do $$$AssertTrue($Length(rendered) > 4096, "the request renders to more than 4,096 units: "_$Length(rendered))
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..Notification(session, "approval", "toolCall.requestOnServer", slots, approval), .response), "it is sent")
		Set calls = ..SentTo(chatId)
		Do $$$AssertEquals(calls.%Size(), 1, "as one sendMessage")
		Set messageId = ..LastId(chatId)
		Set head = $Piece(rendered, $Char(10), 1, 3)
		If calls.%Size() = 1 {
			Set params = calls.%Get(0).params
			Do $$$AssertEquals(params.%IsDefined("reply_markup"), 0, "with no reply_markup: no Approve and no Reject")
			Do $$$AssertEquals(params.text, head_$Char(10)_line, "its text is the head, a line break and the line")
			Do $$$AssertTrue($Extract(params.text, 1, 15) = "Run zz_t on zzS", "the head starts with the request")
			Do $$$AssertTrue($Length(params.text) '> 3840, "and it is 3,840 units or fewer")
		}
		Set rows = ..TelegramRows(session)
		Do $$$AssertEquals(rows.Count(), 1, "one Delivery row")
		If rows.Count() = 1 {
			Do $$$AssertEquals(rows.GetAt(1).Kind_"|"_rows.GetAt(1).ApprovalRef_"|"_rows.GetAt(1).ChannelMessageId, "approval|"_approval_"|"_ref_":"_messageId, "of kind approval with the Ref and the message id")
			Do $$$AssertEquals(rows.GetAt(1).Text, ##class(OcuTalon.Bridge.Redact).Text(head_$Char(10)_line), "and the text that was sent")
		}
		Set time = ##class(OcuTalon.Data.Time).NowUtc()
		Set cancel = {"time": (time), "server": "zzS"}
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..Answered(session, approval, "answered.canceled", cancel), .response), "an answered.canceled notification is sent")
		Set edits = ..EditsTo(chatId)
		Do $$$AssertEquals(edits.%Size(), 1, "it edits the message once")
		If edits.%Size() = 1 {
			Do $$$AssertEquals(edits.%Get(0).text, ##class(OcuTalon.Bridge.Redact).Text(head_$Char(10)_line)_$Char(10, 10)_##class(OcuTalon.Msg.Catalog).Render("answered.canceled", cancel, "telegram"), "in place: the stored text, a blank line and the status")
			Do $$$AssertEquals(edits.%Get(0).%IsDefined("reply_markup"), 0, "with no keyboard")
			Do $$$AssertEquals(edits.%Get(0)."message_id", +messageId, "of that message")
		}
		Do $$$AssertEquals(..SentTo(chatId).%Size(), 1, "and nothing else is sent")

		Set many = []
		For i = 1:1:60 Do many.%Push({"name": ("n"_i), "value": (""""_$Extract(big, 1, 90)_"""")})
		Set slots = {"tool": "zz_t", "inputs": (many)}
		Set rendered = ##class(OcuTalon.Msg.Catalog).Render("toolCall.request", slots, "telegram")
		Do $$$AssertTrue($Length(rendered) > 4096, "a request of 60 inputs renders to more than 4,096 units: "_$Length(rendered))
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..Notification(session, "approval", "toolCall.request", slots, ..NewRef()), .response), "it is sent")
		Set calls = ..SentTo(chatId)
		Do $$$AssertEquals(calls.%Size(), 2, "as one more sendMessage")
		If calls.%Size() = 2 {
			Set text = calls.%Get(1).params.text
			Do $$$AssertEquals(calls.%Get(1).params.%IsDefined("reply_markup"), 0, "with no buttons")
			Do $$$AssertEquals($Piece(text, $Char(10), $Length(text, $Char(10))), line, "ending with the line")
			Do $$$AssertTrue($Length(text) '> 3840, "at most 3,840 units")
			Set cut = $Piece(text, $Char(10), 1, $Length(text, $Char(10)) - 1)
			Do $$$AssertEquals(cut, $Piece(rendered, $Char(10), 1, $Length(cut, $Char(10))), "the head is lines of the request, cut after a line break")
			Do $$$AssertTrue($Length(cut, $Char(10)) > 8, "and it holds many inputs: "_$Length(cut, $Char(10)))
			Do $$$AssertTrue($Length(cut) + 1 + $Length(line) '> 3840, "it fits")
			Do $$$AssertTrue($Length($Piece(rendered, $Char(10), 1, $Length(cut, $Char(10)) + 1)) + 1 + $Length(line) > 3840, "and one more line would not")
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the too-long test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// Story 21.10 (V4, V8, V10): a tool call's request of exactly 4,096 units is shown whole, with Approve and Reject on the last part as any message with buttons, and an input
/// that holds invisible characters shows as the one escaped line.
Method TestToolCallFits()
{
	If '..ReadyLive() Quit
	Try {
		Set chatId = 8631
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(chatId, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Set note = "a"_$Char(8203)_"b"_$Char(8238)_"c"_$Char(56128,56385)_"d"_$Char(8232)_"e"_$Char(13,10)_"f"_$Char(9)_"g h"
		Set line = "note: ""a\u200Bb\u202Ec\uDB40\uDC41d\u2028e\u000D\u000Af\u0009g h"""
		Set approval = ..NewRef()
		Set slots = {"tool": "zz_t", "server": "zzS", "inputs": [{"name": "note", "value": (""""_note_"""")}, {"name": "p1", "value": ("""""")}, {"name": "p2", "value": ("""""")}, {"name": "p3", "value": ("""""")}, {"name": "p4", "value": ("""""")}]}
		Set base = $Length(##class(OcuTalon.Msg.Catalog).Render("toolCall.requestOnServer", slots, "telegram"))
		Set extra = 4096 - base
		For n = 1:1:4 {
			Set pad = ""
			For i = 1:1:$Select(n = 4: extra - (3 * (extra \ 4)), 1: extra \ 4) Set pad = pad_"p"
			Do slots.inputs.%Set(n, {"name": ("p"_n), "value": (""""_pad_"""")})
		}
		Set rendered = ##class(OcuTalon.Msg.Catalog).Render("toolCall.requestOnServer", slots, "telegram")
		Do $$$AssertEquals($Length(rendered), 4096, "the request renders to exactly 4,096 units")
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..Notification(session, "approval", "toolCall.requestOnServer", slots, approval), .response), "it is sent")
		Set calls = ..SentTo(chatId)
		Do $$$AssertTrue(calls.%Size() '< 2, "in two parts or more, as every message with buttons that is over 3,840 units: "_calls.%Size())
		Set joined = "", marked = 0, lastMarked = 0, longest = 0
		For i = 0:1:calls.%Size() - 1 {
			Set params = calls.%Get(i).params
			Set joined = joined_$Select(i = 0: "", 1: $Char(10))_params.text
			If $Length(params.text) > longest Set longest = $Length(params.text)
			If params.%IsDefined("reply_markup") {
				Set marked = marked + 1
				If i = (calls.%Size() - 1) Set lastMarked = 1
			}
		}
		Do $$$AssertTrue(longest '> 3840, "each part is 3,840 units or fewer")
		Do $$$AssertEquals(joined, rendered, "the parts together are the whole request")
		Do $$$AssertEquals(marked_"|"_lastMarked, "1|1", "only the last part has the buttons")
		Do $$$AssertEquals(calls.%Get(calls.%Size() - 1).params."reply_markup".%ToJSON(), {"inline_keyboard": [[{"text": "Approve", "callback_data": ("approve:"_approval)}, {"text": "Reject", "callback_data": ("reject:"_approval)}]]}.%ToJSON(), "Approve and Reject")
		Do $$$AssertEquals($Length(joined, line) - 1, 1, "the sent text holds the escaped line once")
		For code = 8203, 8238, 8232, 13, 9 {
			Do $$$AssertTrue(joined '[ $Char(code), "and no character U+"_$ZHex(code))
		}
		Do $$$AssertTrue(joined '[ $Char(56128), "nor a tag character")
		Set rows = ..TelegramRows(session)
		Do $$$AssertEquals(rows.Count(), 1, "one Delivery row")
		If rows.Count() = 1 Do $$$AssertEquals(rows.GetAt(1).ApprovalRef, approval, "with the request's Ref")
	} Catch ex {
		Do $$$AssertTrue(0, "the fits test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// Story 21.10 (V8): the cut is for a tool call's request only: a request of any other key or kind that is over 4,096 units still splits at 3,840 units with Approve and Reject on the last part.
Method TestLongFixRequestUnchanged()
{
	If '..ReadyLive() Quit
	Try {
		Set chatId = 8632
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(chatId, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Set words = ""
		While $Length(words) < 5000 {
			Set words = words _ "word" _ $Length(words) _ " "
		}
		Set words = $Extract(words, 1, 4999) _ "x"
		Set n = 0
		For kind = "incident", "approval" {
			Set approval = ..NewRef()
			Set notice = ..Notification(session, kind, "notice.tellNow", {"whatHappened": (words), "reason": "you asked to hear about disk space"}, approval)
			Set expected = ##class(OcuTalon.Msg.Catalog).Render("notice.tellNow", notice.Slots, "telegram", .sc)
			Do $$$AssertStatusOK(sc, kind_": the long request renders")
			Do $$$AssertTrue($Length(expected) > 4096, kind_": it is over 4,096 units")
			Set before = ..SentTo(chatId).%Size()
			Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", notice, .response), kind_": it is sent")
			Set all = ..SentTo(chatId)
			Set count = all.%Size() - before
			Do $$$AssertTrue(count '< 2, kind_": in two parts or more: "_count)
			Set joined = "", marked = 0, lastMarked = 0, longest = 0
			For i = before:1:all.%Size() - 1 {
				Set params = all.%Get(i).params
				Set joined = joined_params.text
				If $Length(params.text) > longest Set longest = $Length(params.text)
				If params.%IsDefined("reply_markup") {
					Set marked = marked + 1
					If i = (all.%Size() - 1) Set lastMarked = 1
				}
			}
			Do $$$AssertTrue(longest '> 3840, kind_": each part is 3,840 units or fewer")
			Do $$$AssertEquals(joined, expected, kind_": the parts together are the rendered text")
			Do $$$AssertEquals(marked_"|"_lastMarked, "1|1", kind_": the last part, and only it, has the buttons")
			Do $$$AssertEquals(all.%Get(all.%Size() - 1).params."reply_markup".%ToJSON(), {"inline_keyboard": [[{"text": "Approve", "callback_data": ("approve:"_approval)}, {"text": "Reject", "callback_data": ("reject:"_approval)}]]}.%ToJSON(), kind_": Approve and Reject")
			Do $$$AssertTrue($Find(joined, "The inputs are too long") = 0, kind_": and it has no line about inputs")
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the long-request test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// AC1: only a request notice with an ApprovalRef has buttons; the other notices keep a row with no text.
Method TestNoButtons()
{
	If '..ReadyLive() Quit
	Try {
		Set chatId = 8621
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(chatId, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Set requests(1) = ..Request(session, "")
		Set requests(2) = ..TellNow(session, "zz Disk almost full")
		Set requests(3) = ..Notification(session, "result", "result.allThrough", ..FixtureSlots("result.allThrough"), ..NewRef())
		Set requests(4) = ..Notification(session, "reminder", "reminder.due", ..FixtureSlots("reminder.due"))
		For n = 1:1:4 {
			Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", requests(n), .response), "a "_requests(n).Kind_" notification is sent ("_requests(n).CatalogKey_$Select(requests(n).ApprovalRef = "": ", no Ref", 1: ", with a Ref")_")")
		}
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..Outbound(ref, "zz reply"), .response), "an Outbound is sent")
		Set calls = ..SentTo(chatId)
		Do $$$AssertEquals(calls.%Size(), 5, "five sendMessage calls")
		Set marked = 0
		Set iterator = calls.%GetIterator()
		While iterator.%GetNext(, .call) {
			If call.params.%IsDefined("reply_markup") Set marked = marked + 1
		}
		Do $$$AssertEquals(marked, 0, "none has a reply_markup")
		Set rows = ..TelegramRows(session)
		Do $$$AssertEquals(rows.Count(), 4, "the four notifications have a Delivery row")
		Set texts = ""
		For i = 1:1:rows.Count() Set texts = texts _ rows.GetAt(i).Text
		Do $$$AssertEquals(texts, "", "and none keeps a text")
	} Catch ex {
		Do $$$AssertTrue(0, "the no-buttons test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// Sends the request notice for the Ref and returns its message id ("" when the send failed).
Method SendRequest(chatId As %String, session As %String, approvalRef As %String) As %String [ Private ]
{
	Set sc = $ClassMethod("OcuTalon.Test.Agent.RunnerFixture", "Send", "TelegramOut", ..Request(session, approvalRef), .response)
	Do $$$AssertStatusOK(sc, "the request notice is sent")
	Quit $Select($$$ISOK(sc): ..LastId(chatId), 1: "")
}

/// AC3: an answered notification edits the request's message in place.
Method TestEditApproved()
{
	If '..ReadyLive() Quit
	Try {
		Set chatId = 8622
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(chatId, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set approval = ..NewRef()
		Set messageId = ..SendRequest(chatId, session, approval)
		Set sent = ..SentTo(chatId).%Get(0).params.text
		Set time = ##class(OcuTalon.Data.Time).NowUtc()
		Set status = "Approved from Telegram at "_..Shown(time)_"."
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Answered(session, approval, "answered.approved", {"channel": "telegram", "time": (time)}), .response), "an answered.approved notification is sent")
		Set edits = ..EditsTo(chatId)
		Do $$$AssertEquals(edits.%Size(), 1, "one editMessageText")
		If edits.%Size() = 1 {
			Set params = edits.%Get(0)
			Do $$$AssertEquals(params."chat_id"_"|"_params."message_id"_"|"_params.%GetTypeOf("chat_id")_"|"_params.%GetTypeOf("message_id"), chatId_"|"_messageId_"|number|number", "of the message in its chat, with numeric ids")
			Do $$$AssertEquals(params.text, sent_$Char(10, 10)_status, "the text is the notice, a blank line and the status")
			Do $$$AssertEquals(params.%IsDefined("reply_markup"), 0, "with no reply_markup, which removes the buttons")
		}
		Do $$$AssertEquals(..SentTo(chatId).%Size(), 1, "and nothing else is sent")
		Set rows = ..TelegramRows(session)
		Do $$$AssertEquals(rows.Count(), 2, "the request's row and one more")
		If rows.Count() = 2 {
			Do $$$AssertEquals(rows.GetAt(2).Kind_"|"_rows.GetAt(2).ApprovalRef_"|"_rows.GetAt(2).ChannelMessageId, "answered|"_approval_"|"_ref_":"_messageId, "the new row is of kind answered, with the same id and Ref")
			Do $$$AssertEquals(rows.GetAt(2).Text, "", "and keeps no text")
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the edit test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// AC3: on the online demo the status ends with ET.
Method TestEditOnlineDemo()
{
	If '..ReadyLive() Quit
	Set settings = "OcuTalon.Data.Public.Settings"
	Set savedDemo = $ClassMethod(settings, "Get", "onlineDemo")
	Try {
		Set chatId = 8623
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(chatId, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set approval = ..NewRef()
		Do $ClassMethod(settings, "Set", "onlineDemo", 1)
		Set messageId = ..SendRequest(chatId, session, approval)
		Set sent = ..SentTo(chatId).%Get(0).params.text
		Set time = ##class(OcuTalon.Data.Time).NowUtc()
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Answered(session, approval, "answered.approved", {"channel": "telegram", "time": (time)}), .response), "an answered.approved notification is sent")
		Do $ClassMethod(settings, "Set", "onlineDemo", savedDemo)
		Set edits = ..EditsTo(chatId)
		Do $$$AssertEquals(edits.%Size(), 1, "one editMessageText")
		If edits.%Size() = 1 Do $$$AssertEquals(edits.%Get(0).text, sent_$Char(10, 10)_"Approved from Telegram at "_##class(OcuTalon.Data.Time).ForMessage(time)_" ET.", "the status ends with ET")
	} Catch ex {
		Do $$$AssertTrue(0, "the online-demo edit test failed: "_..Safe(ex))
	}
	Do $ClassMethod(settings, "Set", "onlineDemo", savedDemo)
	Do ..Cleanup()
}

/// AC3: the first answer stays; a request with nothing to edit logs one warning.
Method TestEditOnce()
{
	If '..ReadyLive() Quit
	Try {
		Set chatId = 8624
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(chatId, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Set approval = ..NewRef()
		Set messageId = ..SendRequest(chatId, session, approval)
		Set time = ##class(OcuTalon.Data.Time).NowUtc()
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..Answered(session, approval, "answered.approved", {"channel": "telegram", "time": (time)}), .response), "the first answered notification is sent")
		Do $$$AssertEquals(..EditsTo(chatId).%Size(), 1, "it edits the message")
		Set log = $ClassMethod(fixture, "EventMark")
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..Answered(session, approval, "answered.expired", {"time": (time)}), .response), "(a) a second answered notification for the Ref is sent")
		Do $$$AssertEquals(..EditsTo(chatId).%Size(), 1, "it edits nothing: the first answer stays")
		Do $$$AssertEquals(..Warned(log, "did not edit an answered request"), 0, "and logs no warning")
		Do $$$AssertEquals(..TelegramRows(session).Count(), 2, "and records no row")

		Set other = ..NewRef()
		Set log = $ClassMethod(fixture, "EventMark")
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..Answered(session, other, "answered.approved", {"channel": "telegram", "time": (time)}), .response), "(b) an answered notification for a Ref with no telegram row is sent")
		Do $$$AssertEquals(..EditsTo(chatId).%Size(), 1, "it edits nothing")
		Do $$$AssertEquals(..Warned(log, "did not edit an answered request"), 1, "with one warning")

		Set bare = ..NewRef()
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(session, "telegram", ref_":999", bare, "incident"), "(c) a telegram row with no stored text is recorded")
		Set log = $ClassMethod(fixture, "EventMark")
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..Answered(session, bare, "answered.approved", {"channel": "telegram", "time": (time)}), .response), "an answered notification for its Ref is sent")
		Do $$$AssertEquals(..EditsTo(chatId).%Size(), 1, "it edits nothing")
		Do $$$AssertEquals(..Warned(log, "did not edit an answered request"), 1, "with one warning")
	} Catch ex {
		Do $$$AssertTrue(0, "the edit-once test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// AC2: a rejection from Telegram of a fix gets the follow-up; any other rejection only edits.
Method TestRejectedFollowUp()
{
	If '..ReadyLive() Quit
	Try {
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(8625, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Set time = ##class(OcuTalon.Data.Time).NowUtc()
		Set shown = ..Shown(time)
		Set incident = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set cases = $ListBuild($ListBuild("telegram", incident, "Rejected from Telegram at "_shown_". Nothing was changed.", 1, "answered.rejected", ""), $ListBuild("web", incident, "Rejected from the web chat at "_shown_". Nothing was changed.", 0, "answered.rejected", ""), $ListBuild("telegram", "", "Rejected from Telegram at "_shown_". Nothing was changed.", 0, "answered.rejected", ""), $ListBuild("telegram", incident, "Rejected by sam from Telegram at "_shown_". Nothing was changed.", 1, "answered.rejectedBy", "sam"))
		For n = 1:1:4 {
			Set case = $List(cases, n)
			Set approval = ..NewRef()
			Set messageId = ..SendRequest(8625, session, approval)
			Set sent = ..SentTo(8625).%Get(..SentTo(8625).%Size() - 1).params.text
			Set before = ..SentTo(8625).%Size()
			Set edits = ..EditsTo(8625).%Size()
			Set slots = {"channel": ($List(case, 1)), "time": (time)}
			If $List(case, 6) '= "" Do slots.%Set("user", $List(case, 6))
			Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..Answered(session, approval, $List(case, 5), slots, $List(case, 2)), .response), "(case "_n_") a "_$List(case, 5)_" notification from "_$List(case, 1)_$Select($List(case, 2) = "": " with no incident", 1: "")_" is sent")
			Set all = ..EditsTo(8625)
			Do $$$AssertEquals(all.%Size(), edits + 1, "it edits the message once")
			If all.%Size() = (edits + 1) Do $$$AssertEquals(all.%Get(edits).text, sent_$Char(10, 10)_$List(case, 3), "with the rejected status")
			Set after = ..SentTo(8625)
			Do $$$AssertEquals(after.%Size(), before + $List(case, 4), "and "_$Select($List(case, 4): "sends one new message", 1: "sends nothing"))
			If $List(case, 4) && (after.%Size() = (before + 1)) Do $$$AssertEquals(after.%Get(before).params.text, "Fix rejected. Nothing was changed. The incident stays open on your OcuTalon page.", "the follow-up")
		}
		Set rows = ..TelegramRows(session)
		Set followUps = 0, answered = 0
		For i = 1:1:rows.Count() {
			If (rows.GetAt(i).Kind = "answered") && (rows.GetAt(i).ApprovalRef = "") Set followUps = followUps + 1
			If (rows.GetAt(i).Kind = "answered") && (rows.GetAt(i).ApprovalRef '= "") Set answered = answered + 1
			If rows.GetAt(i).Kind = "answered" Do $$$AssertEquals(rows.GetAt(i).Text, "", "an answered row keeps no text")
		}
		Do $$$AssertEquals(followUps_"|"_answered, "2|4", "two follow-up rows with no Ref, and four answered rows with theirs")
	} Catch ex {
		Do $$$AssertTrue(0, "the follow-up test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// AC3: a failed edit is one warning and records no row; a rejection from Telegram of a fix still gets the follow-up.
Method TestEditFails()
{
	If '..ReadyLive() Quit
	Try {
		Set chatId = 8626
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(chatId, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Set time = ##class(OcuTalon.Data.Time).NowUtc()
		Set failed = {"status": 400, "body": {"ok": false, "error_code": 400, "description": "Bad Request: message to edit not found"}}
		Set incident = ##class(OcuTalon.Bridge.Ids).NewRef()
		For n = 1:1:2 {
			Set approval = ..NewRef()
			Set messageId = ..SendRequest(chatId, session, approval)
			Set before = ..SentTo(chatId).%Size()
			Set edits = ..EditsTo(chatId).%Size()
			Set rowsBefore = ..TelegramRows(session).Count()
			Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "editMessageText", "replies": [(failed)]}), "(case "_n_") a 400 for the edit is queued")
			Set log = $ClassMethod(fixture, "EventMark")
			Set key = $Select(n = 1: "answered.approved", 1: "answered.rejected")
			Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..Answered(session, approval, key, {"channel": "telegram", "time": (time)}, $Select(n = 1: "", 1: incident)), .response), "the "_key_" notification returns OK")
			Do $$$AssertEquals(..EditsTo(chatId).%Size(), edits + 1, "the edit was tried once")
			Do $$$AssertEquals(..Warned(log, "could not edit a message"), 1, "with one warning")
			Do $$$AssertEquals(..SentTo(chatId).%Size(), before + (n = 2), $Select(n = 1: "and nothing is sent", 1: "and only the rejected follow-up is sent"))
			Do $$$AssertEquals(..TelegramRows(session).Count(), rowsBefore + (n = 2), $Select(n = 1: "and no row is recorded", 1: "and only the follow-up's row is recorded"))
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the failed-edit test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// The rows of the event log after the mark whose item is TelegramOut and whose text holds any of the values (a list); a log text must
/// hold no Ref, chat id or message text (AD-4).
Method Naming(mark As %Integer, values As %List) As %Integer [ Private ]
{
	Set found = 0, position = 0
	Set rows = ##class(OcuTalon.Test.Agent.RunnerFixture).EventRows(mark, "TelegramOut")
	While $ListNext(rows, position, row) {
		Set at = 0
		Set one = 0
		While $ListNext(values, at, value) {
			If (value '= "") && ($Find(row, value) > 0) Set one = 1
		}
		Set found = found + one
	}
	Quit found
}

/// AC3 (Retries): a 429 on the edit waits and sends the same edit again, and the request's message is edited once.
Method TestEditRateLimited()
{
	If '..ReadyLive() Quit
	Try {
		Set chatId = 8627
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(chatId, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set approval = ..NewRef()
		Set messageId = ..SendRequest(chatId, session, approval)
		Set sent = ..SentTo(chatId).%Get(0).params.text
		Set limited = {"status": 429, "body": {"ok": false, "error_code": 429, "description": "Too Many Requests: retry after 1", "parameters": {"retry_after": 1}}}
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "editMessageText", "replies": [(limited)]}), "a 429 with retry_after 1 is queued for the edit")
		Set time = ##class(OcuTalon.Data.Time).NowUtc()
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Send("TelegramOut", ..Answered(session, approval, "answered.approved", {"channel": "telegram", "time": (time)}), .response), "an answered.approved notification returns OK")
		Set calls = []
		Set iterator = ..CallsOf("editMessageText").%GetIterator()
		While iterator.%GetNext(, .call) {
			If call.params."chat_id" = chatId Do calls.%Push(call)
		}
		Do $$$AssertEquals(calls.%Size(), 2, "the edit was sent twice")
		If calls.%Size() = 2 {
			Do $$$AssertEquals(calls.%Get(0).params.text = calls.%Get(1).params.text, 1, "with the same text")
			Do $$$AssertEquals(calls.%Get(1).params.text, sent_$Char(10, 10)_"Approved from Telegram at "_..Shown(time)_".", "which is the notice and the status")
			Set gap = ..Epoch(calls.%Get(1).ts) - ..Epoch(calls.%Get(0).ts)
			Do $$$AssertTrue(gap >= 0.95, "the second is at least a second after the first: "_$Justify(gap, 0, 2))
		}
		Set rows = ..TelegramRows(session)
		Do $$$AssertEquals(rows.Count(), 2, "the request's row and one answered row")
		If rows.Count() = 2 Do $$$AssertEquals(rows.GetAt(2).Kind_"|"_rows.GetAt(2).ApprovalRef, "answered|"_approval, "the row is of the kind answered, with the Ref")
		Do $$$AssertEquals(..Warned(log, "could not edit a message"), 0, "and the retry is no warning")
		Do $$$AssertEquals(..SentTo(chatId).%Size(), 1, "and nothing else is sent")
	} Catch ex {
		Do $$$AssertTrue(0, "the rate-limited edit test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// AC3: a request answered on any channel, or expired, is edited with the status of that answer, and only a Telegram rejection of a fix
/// gets a follow-up.
Method TestEditElsewhere()
{
	If '..ReadyLive() Quit
	Try {
		Set chatId = 8628
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(chatId, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Set time = ##class(OcuTalon.Data.Time).NowUtc()
		Set incident = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set cases = $ListBuild($ListBuild("answered.approved", {"channel": "web", "time": (time)}.%ToJSON()), $ListBuild("answered.approved", {"channel": "phone", "time": (time)}.%ToJSON()), $ListBuild("answered.rejected", {"channel": "web", "time": (time)}.%ToJSON()), $ListBuild("answered.approvedBy", {"user": "sam", "channel": "web", "time": (time)}.%ToJSON()), $ListBuild("answered.expired", {"time": (time)}.%ToJSON()))
		For n = 1:1:$ListLength(cases) {
			Set case = $List(cases, n)
			Set key = $List(case, 1), slots = {}.%FromJSON($List(case, 2))
			Set status = ##class(OcuTalon.Msg.Catalog).Render(key, slots.%ToJSON(), "telegram", .sc)
			Do $$$AssertStatusOK(sc, "(case "_n_") "_key_" renders")
			Set approval = ..NewRef()
			Set messageId = ..SendRequest(chatId, session, approval)
			Set sent = ..SentTo(chatId).%Get(..SentTo(chatId).%Size() - 1).params.text
			Set before = ..SentTo(chatId).%Size()
			Set edits = ..EditsTo(chatId).%Size()
			Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..Answered(session, approval, key, slots, incident), .response), "(case "_n_") a "_key_" notification is sent")
			Set all = ..EditsTo(chatId)
			Do $$$AssertEquals(all.%Size(), edits + 1, "it edits the message once")
			If all.%Size() = (edits + 1) {
				Do $$$AssertEquals(all.%Get(edits).text, sent_$Char(10, 10)_status, "with the notice, a blank line and "_status)
				Set rows = ..TelegramRows(session)
				Set stored = rows.GetAt(rows.Count()).ChannelMessageId
				Do $$$AssertEquals(all.%Get(edits)."message_id", +$Piece(stored, ":", 2), "of the request's own message, as its first row recorded it")
			}
			Do $$$AssertEquals(..SentTo(chatId).%Size(), before, "and sends nothing new, with an incident set too")
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the edit-elsewhere test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// AD-4 and the edit's contract: every edit that cannot be made is one warning, the status is OK, and no log text holds a Ref, a chat id
/// or a message text.
Method TestEditWarnings()
{
	If '..ReadyLive() Quit
	Try {
		Set chatId = 8629
		Set session = ..NewSessionRef()
		Set ref = ..PairedChat(chatId, session)
		Do $$$AssertStatusOK(..StartItems("TelegramOut"), "TelegramOut is enabled")
		Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
		Set time = ##class(OcuTalon.Data.Time).NowUtc()
		Set slots = {"channel": "telegram", "time": (time)}
		Set stored = "zzstored text of the request"
		Set values = $ListBuild(chatId, stored, "zzghostchatref")
		Set approvals = ""
		// (1) a Ref with no telegram row; (2) a row whose chat has no chat row; (3) a row with no message id.
		Set none = ..NewRef(), noChat = ..NewRef(), noId = ..NewRef()
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(session, "telegram", "zzghostchatref:77", noChat, "incident", stored), "(2) a row of a chat that has no chat row is recorded")
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Delivery).Record(session, "telegram", ref_":", noId, "incident", stored), "(3) a row with no message id is recorded")
		Set cases = $ListBuild($ListBuild(none, "no row"), $ListBuild(noChat, "no chat row"), $ListBuild(noId, "no message id"))
		For n = 1:1:3 {
			Set approval = $List($List(cases, n), 1)
			Set log = $ClassMethod(fixture, "EventMark")
			Set edits = ..EditsTo(chatId).%Size()
			Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..Answered(session, approval, "answered.approved", slots), .response), "("_n_") an answered notification with "_$List($List(cases, n), 2)_" returns OK")
			Do $$$AssertEquals(..EditsTo(chatId).%Size(), edits, "it edits nothing")
			Do $$$AssertEquals(..Warned(log, "did not edit an answered request"), 1, "with one warning")
			Do $$$AssertEquals(..Naming(log, values_$ListBuild(approval, ref)), 0, "that names no Ref, chat id, chat or message text")
		}
		Set rows = ..TelegramRows(session)
		Do $$$AssertEquals(rows.Count(), 2, "and no answered row was recorded")
		// (4) a failed edit.
		Set approval = ..NewRef()
		Set messageId = ..SendRequest(chatId, session, approval)
		Set sent = ..SentTo(chatId).%Get(0).params.text
		Set failed = {"status": 400, "body": {"ok": false, "error_code": 400, "description": "Bad Request: message to edit not found"}}
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "editMessageText", "replies": [(failed)]}), "(4) a 400 for the edit is queued")
		Set log = $ClassMethod(fixture, "EventMark")
		Do $$$AssertStatusOK($ClassMethod(fixture, "Send", "TelegramOut", ..Answered(session, approval, "answered.approved", slots), .response), "the notification returns OK")
		Do $$$AssertEquals(..Warned(log, "could not edit a message"), 1, "a failed edit is one warning")
		Do $$$AssertEquals(..Naming(log, values_$ListBuild(approval, ref, $Extract(sent, 1, 40))), 0, "that names no Ref, chat id, chat or message text")
	} Catch ex {
		Do $$$AssertTrue(0, "the edit-warnings test failed: "_..Safe(ex))
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
