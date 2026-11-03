/// Integration tests of Lane A's Telegram scenarios against the CI mock's Bot API side (Story 12.1; FR-22, AD-22, NFR-11, DW-370).
/// THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): the CI override points OCUTALON_TELEGRAM_API_BASE at the mock and
/// sets a dummy TELEGRAM_BOT_TOKEN. Every test first asks OcuTalon.Test.Contract.Mock.TelegramMissingReason and
/// OcuTalon.Test.Channel.BotApi.PollerReason (no live TelegramIn job, because a reset or a call would take its updates). When either
/// gives a reason, the test fails with it and sends nothing. Every test starts and ends with BotApi.Reset(), which leaves the mock's Bot
/// API side empty and no kept offset. No test writes the token to a log, an assertion text or a status. The guard (Ready, Finish and Safe)
/// is OcuTalon.Test.Channel.LiveCase's.
///   - TestUpdateScenarios: telegram-private-update, telegram-group-update and telegram-button-update, each queued as replies through
///     the control endpoint, answer getUpdates with their one update;
///   - TestReplyScenarios: telegram-conflict answers getUpdates 409, and telegram-rate-limited answers the first sendMessage 429 with
///     retry_after 2 and the second the 200 default;
///   - TestCallsAndLog: the calls read back in order with their methods and parameters, and the mock's log holds each Bot API path as
///     /bot[redacted]/<method> with the token's length and never the token;
///   - TestResetClearsKeptOffset: after a reset through the helper, a new update with id 1 comes back from getUpdates;
///   - TestPollerCheck: PollerReason names an item that has a live job, and Reset refuses for that item, clearing and sending nothing
///     (that it is empty for TelegramIn is every test's precondition, which Ready() asserts).
Class OcuTalon.Test.Channel.TelegramMock Extends OcuTalon.Test.Channel.LiveCase
{

/// Each update scenario, queued as replies, answers getUpdates with its one update.
Method TestUpdateScenarios()
{
	If '..Ready() Quit
	Try {
		For name = "telegram-private-update", "telegram-group-update", "telegram-button-update" {
			Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": (name)}), name_" is queued as replies")
			Set answer = ##class(OcuTalon.Test.Contract.Mock).BotCall(..Token, "getUpdates", {"offset": 0, "timeout": 0}.%ToJSON())
			Set update = answer.result.%Get(0)
			Do $$$AssertEquals(answer.ok_"|"_answer.result.%Size()_"|"_update."update_id", "1|1|1", name_": getUpdates answers 200 with its one update")
			If name = "telegram-private-update" {
				Do $$$AssertEquals(update.message.chat.type_"|"_(update.message.text '= ""), "private|1", name_": a text message in a private chat")
			} ElseIf name = "telegram-group-update" {
				Do $$$AssertEquals(update.message.chat.type_"|"_(update.message.text '= ""), "group|1", name_": a text message in a group chat")
			} Else {
				Do $$$AssertEquals(update."callback_query".message.chat.type_"|"_update."callback_query".data_"|"_$IsObject(update.message), "private|ocutalon-ci-unknown-press|0", name_": a callback query from a private chat that names no request")
			}
			Do $$$AssertStatusOK(##class(OcuTalon.Test.Channel.BotApi).Reset(), "reset between scenarios")
		}
	} Catch ex {
		Do $$$AssertTrue(0, "a Bot API call failed: "_..Safe(ex))
	}
	Do ..Finish()
}

/// The 409 for getUpdates, and the 429 for the first sendMessage and the 200 default for the second.
Method TestReplyScenarios()
{
	If '..Ready() Quit
	Try {
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-conflict"}), "telegram-conflict is queued")
		Set answer = ##class(OcuTalon.Test.Channel.BotApi).BotReply(..Token, "getUpdates", {"offset": 0, "timeout": 0}.%ToJSON(), .code)
		Do $$$AssertEquals(code_"|"_answer.ok_"|"_answer."error_code"_"|"_($Extract(answer.description, 1, 8)), "409|0|409|Conflict", "getUpdates answers 409 with a description that starts with Conflict")

		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-rate-limited"}), "telegram-rate-limited is queued")
		Set body = {"chat_id": 42, "text": "zz rate limited"}.%ToJSON()
		Set answer = ##class(OcuTalon.Test.Channel.BotApi).BotReply(..Token, "sendMessage", body, .code)
		Do $$$AssertEquals(code_"|"_answer.ok_"|"_answer."error_code"_"|"_answer.parameters."retry_after", "429|0|429|2", "the first sendMessage answers 429 with retry_after 2")
		Set answer = ##class(OcuTalon.Test.Contract.Mock).BotCall(..Token, "sendMessage", body)
		Do $$$AssertEquals(answer.ok, 1, "the second sendMessage gets the 200 default")
	} Catch ex {
		Do $$$AssertTrue(0, "a Bot API call failed: "_..Safe(ex))
	}
	Do ..Finish()
}

/// The calls read back in order, and the log holds the token's length only.
Method TestCallsAndLog()
{
	If '..Ready() Quit
	Set mock = "OcuTalon.Test.Contract.Mock"
	Try {
		Set mark = $ClassMethod(mock, "LogMark")
		Do $$$AssertTrue($ClassMethod(mock, "Control", "replies", {"scenario": "telegram-private-update"}), "an update scenario is queued")
		Do $$$AssertTrue($ClassMethod(mock, "Control", "replies", {"scenario": "telegram-rate-limited"}), "and a reply scenario")
		Set text = "zz telegram "_##class(OcuTalon.Bridge.Ids).NewRef()
		Set body = {"chat_id": 42, "text": (text)}.%ToJSON()
		Set answer = $ClassMethod(mock, "BotCall", ..Token, "getMe", "")
		Do $$$AssertEquals(answer.ok, 1, "getMe answers")
		Set answer = $ClassMethod(mock, "BotCall", ..Token, "getUpdates", {"offset": 0, "timeout": 0}.%ToJSON())
		Do $$$AssertEquals(answer.result.%Size(), 1, "getUpdates answers with the scenario's update")
		Set answer = ##class(OcuTalon.Test.Channel.BotApi).BotReply(..Token, "sendMessage", body, .code)
		Do $$$AssertEquals(code, 429, "the first sendMessage is limited")
		Set answer = $ClassMethod(mock, "BotCall", ..Token, "sendMessage", body)
		Do $$$AssertEquals(answer.ok, 1, "the second sendMessage is answered")
		Set calls = $ClassMethod(mock, "Calls")
		Do $$$AssertEquals(calls.%Size(), 4, "the mock lists the four calls")
		If calls.%Size() = 4 {
			Do $$$AssertEquals(calls.%Get(0).method_"|"_calls.%Get(1).method_"|"_calls.%Get(2).method_"|"_calls.%Get(3).method, "getMe|getUpdates|sendMessage|sendMessage", "in order")
			Do $$$AssertEquals(calls.%Get(1).params.offset_"|"_calls.%Get(1).params.timeout, "0|0", "getUpdates with its parameters")
			Do $$$AssertEquals(calls.%Get(2).params.text_"|"_calls.%Get(2).params."chat_id"_"|"_calls.%Get(3).params.text, text_"|42|"_text, "and both sendMessage calls with theirs")
		}
		For wait = 1:1:25 {
			Do $ClassMethod(mock, "LogSince", mark, .entries)
			Set seen = 0, holds = 0
			Set iterator = entries.%GetIterator()
			While iterator.%GetNext(, .entry) {
				If $Extract(entry.path, 1, 5) = "/bot[" Set seen = seen + 1
			}
			If seen >= 4 Quit
			Hang 0.2
		}
		Set seen = 0, holds = 0
		Set iterator = entries.%GetIterator()
		While iterator.%GetNext(, .entry) {
			If $Find(entry.%ToJSON(), ..Token) Set holds = 1
			If $Extract(entry.path, 1, 5) '= "/bot[" Continue
			Set seen = seen + 1
			Do $$$AssertEquals(entry.path_"|"_entry.tokenLength, "/bot[redacted]/"_$Piece("getMe,getUpdates,sendMessage,sendMessage", ",", seen)_"|"_$Length(..Token), "Bot API line "_seen_" has the masked path of its call's method and the token's length")
		}
		Do $$$AssertEquals(seen, 4, "the log holds the four calls")
		Do $$$AssertEquals(holds, 0, "and no line of the log holds the token")
	} Catch ex {
		Do $$$AssertTrue(0, "a Bot API call failed: "_..Safe(ex))
	}
	Do ..Finish()
}

/// DW-370: a reset through the helper clears the kept offset, so the next update (id 1) is not confirmed away.
Method TestResetClearsKeptOffset()
{
	If '..Ready() Quit
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set helper = "OcuTalon.Test.Channel.BotApi"
	Try {
		Do $$$AssertTrue($ClassMethod(mock, "Control", "updates", [{"message": {"chat": {"id": 42}, "text": "zz one"}}, {"message": {"chat": {"id": 42}, "text": "zz two"}}]), "two updates are queued")
		Set answer = $ClassMethod(mock, "BotCall", ..Token, "getUpdates", {"offset": 0, "timeout": 0}.%ToJSON())
		Do $$$AssertEquals(answer.result.%Size()_"|"_answer.result.%Get(0)."update_id"_"|"_answer.result.%Get(1)."update_id", "2|1|2", "getUpdates at offset 0 returns the ids 1 and 2")
		Do $ClassMethod(helper, "SetOffset", 3)
		Do $$$AssertEquals($ClassMethod(helper, "Offset"), 3, "the kept offset stands at 3, after ids up to 2")
		Do $$$AssertStatusOK($ClassMethod(helper, "Reset"), "the helper resets")
		Do $$$AssertEquals($ClassMethod(helper, "Offset"), "", "and has cleared the kept offset")
		Do $$$AssertTrue($ClassMethod(mock, "Control", "updates", [{"message": {"chat": {"id": 42}, "text": "zz three"}}]), "one update is queued, with id 1")
		Set offset = $ClassMethod(helper, "Offset")
		Set request = $Select(offset = "": {"timeout": 0}, 1: {"offset": (offset), "timeout": 0})
		Set answer = $ClassMethod(mock, "BotCall", ..Token, "getUpdates", request.%ToJSON())
		Do $$$AssertEquals(answer.result.%Size()_"|"_answer.result.%Get(0)."update_id"_"|"_answer.result.%Get(0).message.text, "1|1|zz three", "getUpdates with the offset the helper left returns the new update")
	} Catch ex {
		Do $$$AssertTrue(0, "a Bot API call failed: "_..Safe(ex))
	}
	Do ..Finish()
}

/// DW-370: the poller check. TelegramIn has no live job here; Decide has one in a running production, and the helper refuses for it.
Method TestPollerCheck()
{
	If '..Ready() Quit
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set helper = "OcuTalon.Test.Channel.BotApi"
	Try {
		Set reason = $ClassMethod(helper, "PollerReason", "Decide")
		If reason = "" {
			Do $$$AssertTrue(0, "Decide has no live job in this stack, so the production is not running and the refusal cannot be shown")
		} Else {
			Do $$$AssertTrue($Find(reason, "Decide") > 0, "an item with a live job gives a reason that names it")
			Do $ClassMethod(helper, "SetOffset", 5)
			Do $$$AssertTrue($ClassMethod(mock, "Control", "updates", [{"message": {"chat": {"id": 42}, "text": "zz kept"}}]), "an update is queued")
			Set status = $ClassMethod(helper, "Reset", "Decide")
			Do $$$AssertStatusNotOK(status, "Reset refuses while the poller item has a live job")
			Do $$$AssertTrue($Find($SYSTEM.Status.GetErrorText(status), "Decide") > 0, "and the refusal names the item")
			Do $$$AssertEquals($ClassMethod(helper, "Offset"), 5, "it cleared no offset")
			Set answer = $ClassMethod(mock, "BotCall", ..Token, "getUpdates", {"offset": 0, "timeout": 0}.%ToJSON())
			Do $$$AssertEquals(answer.result.%Size()_"|"_answer.result.%Get(0).message.text, "1|zz kept", "and reset nothing: the queued update is still there")
		}
	} Catch ex {
		Do $$$AssertTrue(0, "a Bot API call failed: "_..Safe(ex))
	}
	Do ..Finish()
}

}
