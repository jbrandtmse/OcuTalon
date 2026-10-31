Include Ensemble

/// Live tests of TelegramIn against the CI mock (Story 12.2; FR-19, FR-21, AD-14, AD-19, AD-5, DW-422). THESE TESTS RUN IN THROWAWAY
/// STACKS AND IN CI ONLY (Rule 21), like OcuTalon.Test.Channel.LiveCase, which they extend: each test enables TelegramIn on the running
/// production, against the mock and its dummy token, and ends with Cleanup (the item stopped and its Enabled row put back, both Telegram
/// marks put back, the fixture chats deleted, the mock reset). Fixture chat ids are 7001 and 83xx only.
///   - TestStart: the state becomes on with the bot's name, the calls are getMe and then getUpdates with timeout 5, the two allowed update
///     kinds and no offset, and StateBody says on and the name;
///   - TestStop: a stop during an open long poll returns OK within 10 s, leaves no job and records off;
///   - TestOffsetNode (DW-422): the offset that BotApi.SetOffset sets is carried by the first poll, only the update at it is handled, and
///     the node moves to the next id, which the next poll carries;
///   - TestRestartLosesNothing: an update handled before a stop is not handled again, one queued while stopped is handled once;
///   - TestAlreadyHandled: an update below the kept offset is skipped and the offset stays;
///   - TestPrivateOnly (FR-19): only the private message and the private press make a chat row, with no session and no name, with no
///     reply, no message header and no audit entry;
///   - TestRejected (FR-21): a 401 for getMe records rejected with no name, makes no other call (also past the retry time of a
///     failure), logs it without the token, and the state stays rejected after a stop;
///   - TestRejectedWhilePolling: a 404 for getUpdates once the item polls is a rejection too: the state becomes rejected, no poll
///     follows, and the state stays rejected after a stop;
///   - TestUsesItsApiBase: TelegramIn calls the base of its ApiBase row, not the environment variable: with the row at a closed
///     loopback port the mock sees no call, a warning says that a call failed, and the state does not become on;
///   - TestStartFailureRetries: a 500 for getMe is no rejection: one warning, getMe again after 5 seconds, and then the state is on;
///   - TestUpdatesBusy: a 429 for getUpdates delays the next poll by its retry_after and logs one warning;
///   - TestUpdatesBusyNoRetryAfter (QA): a 429 for getUpdates with no retry_after delays the next poll by 5 seconds;
///   - TestUpdatesFailureRetries (QA): a 500 for getUpdates is no rejection and no pause: one warning, the next poll after 5 seconds,
///     and the state stays on;
///   - TestRecordChatFailure (QA): a private update whose chat id RecordChat refuses logs one warning that names no id, is still
///     confirmed, and does not stop the update after it; it deletes any 8331 row before and after.
Class OcuTalon.Test.Channel.TelegramIn Extends OcuTalon.Test.Channel.LiveCase
{

/// The bot name of the mock's getMe default.
Parameter BOT = "ocutalon_ci_bot";

/// A scripted update's chat (telegram-private-update).
Parameter SCRIPTED = 7001;

/// The state and the bot's name in StateBody's telegram block, as "state|name".
Method TelegramBlock(session As OcuTalon.Data.Session) As %String [ Private ]
{
	Set telegram = ##class(OcuTalon.Web.Api).StateBody(session).telegram
	Quit telegram.state_"|"_telegram.botUserName
}

/// The state becomes on with the bot's name before the first poll; the first calls are getMe and getUpdates.
Method TestStart()
{
	If '..ReadyLive() Quit
	Try {
		Set session = ..FixtureSession("zztgin")
		Do ##class(OcuTalon.Data.StatusMark).RecordTelegram("rejected", "")
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Do $$$AssertTrue(..WaitState("on", 20), "the state becomes on")
		Set state = ##class(OcuTalon.Data.StatusMark).TelegramState(.bot)
		Do $$$AssertEquals(state_"|"_bot, "on|"_..#BOT, "with the bot's user name from getMe")
		Set polls = ..WaitCalls("getUpdates", 1, 20)
		Do $$$AssertTrue(polls.%Size() >= 1, "TelegramIn polls")
		Set calls = ##class(OcuTalon.Test.Contract.Mock).Calls()
		Do $$$AssertTrue(calls.%Size() >= 2, "the mock lists the calls")
		If calls.%Size() >= 2 {
			Do $$$AssertEquals(calls.%Get(0).method_"|"_calls.%Get(1).method, "getMe|getUpdates", "the first calls are getMe, then getUpdates")
			Set params = calls.%Get(1).params
			Do $$$AssertEquals(params.timeout, 5, "getUpdates waits 5 seconds")
			Do $$$AssertEquals(params."allowed_updates".%ToJSON(), "[""message"",""callback_query""]", "and asks for messages and button presses only")
			Do $$$AssertEquals(params.%IsDefined("offset"), 0, "with no offset when none is kept")
		}
		Do $$$AssertEquals(..TelegramBlock(session), "on|"_..#BOT, "StateBody says on and the bot's name")
	} Catch ex {
		Do $$$AssertTrue(0, "the start test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// A stop during an open long poll is done within 10 s, leaves no job, and records off.
Method TestStop()
{
	If '..ReadyLive() Quit
	Try {
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Do $$$AssertTrue(..WaitState("on", 20), "the state becomes on")
		Do $$$AssertTrue(..WaitCalls("getUpdates", 1, 20).%Size() >= 1, "a long poll is open")
		Hang 1
		Set start = $ZHorolog
		Set sc = ##class(Ens.Director).EnableConfigItem("TelegramIn", 0, 1)
		Set seconds = $ZHorolog - start
		Do $$$AssertStatusOK(sc, "the stop returns OK")
		Do $$$AssertTrue(seconds < 10, "within 10 seconds: "_$Justify(seconds, 0, 1))
		Do $$$AssertEquals($ListLength(##class(OcuTalon.Test.Agent.RunnerFixture).Jobs("TelegramIn")), 0, "no TelegramIn job remains")
		Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).TelegramState(.bot)_"|"_bot, "off|", "the state is off, with no name")
	} Catch ex {
		Do $$$AssertTrue(0, "the stop test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// DW-422: the kept offset is the node BotApi reads.
Method TestOffsetNode()
{
	If '..ReadyLive() Quit
	Try {
		Do ..Chat("7001,8301,8302")
		Do ..DropChats("7001,8301,8302")
		Do ##class(OcuTalon.Test.Channel.BotApi).SetOffset(3)
		Do $$$AssertTrue(..QueueUpdates([(..PrivateMessage(7001)), (..PrivateMessage(8301)), (..PrivateMessage(8302))]), "three updates, ids 1 to 3, are queued")
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Do $$$AssertTrue(..WaitOffset(4), "the kept offset becomes 4")
		Set polls = ..WaitCalls("getUpdates", 2, 20)
		Do $$$AssertTrue(polls.%Size() >= 2, "TelegramIn polls again")
		If polls.%Size() >= 2 {
			Do $$$AssertEquals(polls.%Get(0).params.offset, 3, "the first poll carries the offset that was set")
			Do $$$AssertEquals(polls.%Get(1).params.offset, 4, "the next poll carries the node's new value")
		}
		Do $$$AssertEquals(..ChatRows(7001)_"|"_..ChatRows(8301)_"|"_..ChatRows(8302), "0|0|1", "only update 3 is handled")
	} Catch ex {
		Do $$$AssertTrue(0, "the offset test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// A handled update is not handled again after a restart, and one queued while the item was stopped is handled once.
Method TestRestartLosesNothing()
{
	If '..ReadyLive() Quit
	Try {
		Do ..Chat("8311,8312")
		Do ..DropChats("8311,8312")
		Do $$$AssertTrue(..QueueUpdates([(..PrivateMessage(8311))]), "update A is queued")
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Do $$$AssertTrue(..WaitOffset(2), "update A is handled and the offset is 2")
		Do $$$AssertEquals(..ChatRows(8311), 1, "A made its chat row")
		Do $$$AssertStatusOK(..StopItems(), "TelegramIn is stopped")
		Do ..DropChats("8311")
		Do $$$AssertTrue(..QueueUpdates([(..PrivateMessage(8312))]), "update B is queued while the item is stopped")
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled again")
		Do $$$AssertTrue(..WaitOffset(3), "B is handled and the offset moves past it")
		Do $$$AssertEquals(..ChatRows(8312), 1, "B made its chat row, once")
		Hang 2
		Do $$$AssertEquals(..ChatRows(8311), 0, "A is not handled again")
		Do $$$AssertEquals(##class(OcuTalon.Test.Channel.BotApi).Offset(), 3, "the offset stays past B")
	} Catch ex {
		Do $$$AssertTrue(0, "the restart test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// An update below the kept offset is skipped.
Method TestAlreadyHandled()
{
	If '..ReadyLive() Quit
	Try {
		Do ..Chat(..#SCRIPTED)
		Do ..DropChats(..#SCRIPTED)
		Do ##class(OcuTalon.Test.Channel.BotApi).SetOffset(2)
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-private-update"}), "the scripted private update (id 1) is queued")
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Do $$$AssertTrue(..WaitCalls("getUpdates", 2, 20).%Size() >= 2, "the scripted update was answered and TelegramIn polled again")
		Do $$$AssertEquals(..ChatRows(..#SCRIPTED), 0, "no chat row appears for the skipped update")
		Do $$$AssertEquals(##class(OcuTalon.Test.Channel.BotApi).Offset(), 2, "and the offset stays 2")
	} Catch ex {
		Do $$$AssertTrue(0, "the already-handled test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// FR-19: only private messages and private presses are handled, and handling them records the chat, with nothing else.
Method TestPrivateOnly()
{
	If '..ReadyLive() Quit
	Try {
		Set ids = "8321,8322,8323,8324,8325"
		Do ..Chat(ids)
		Do ..DropChats(ids)
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Do $$$AssertTrue(..WaitState("on", 20), "the state becomes on")
		Do $$$AssertTrue(..WaitCalls("getUpdates", 1, 20).%Size() >= 1, "a poll is open")
		Set headers = ..HeaderMark()
		Set audit = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
		Set batch = []
		Do batch.%Push({"message": {"chat": {"id": 8321, "type": "group"}, "text": "zz group"}})
		Do batch.%Push({"channel_post": {"chat": {"id": 8322, "type": "channel"}, "text": "zz channel"}})
		Do batch.%Push({"callback_query": {"id": "zz1", "data": "zz", "message": {"message_id": 1, "chat": {"id": 8323, "type": "group"}}}})
		Do batch.%Push(..PrivateMessage(8324))
		Do batch.%Push({"callback_query": {"id": "zz2", "data": "zz", "message": {"message_id": 2, "chat": {"id": 8325, "type": "private"}}}})
		Do $$$AssertTrue(..QueueUpdates(batch), "five updates are queued in one batch")
		Do $$$AssertTrue(..WaitOffset(6), "the offset is past all five")
		Do $$$AssertEquals(..ChatRows(8321)_"|"_..ChatRows(8322)_"|"_..ChatRows(8323), "0|0|0", "the group, channel and group-press updates make no chat row")
		Do $$$AssertEquals(..ChatRows(8324)_"|"_..ChatRows(8325), "1|1", "the private message and the private press make one each")
		For id = 8324, 8325 {
			Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT SessionRef, DisplayName FROM OcuTalon_Data.Pairing WHERE ChatId = ?", id)
			Do result.%Next()
			Do $$$AssertEquals(result.%GetData(1)_"|"_result.%GetData(2), "|", "the row of "_id_" holds no session and no name")
		}
		Do $$$AssertEquals(..CallsOf("sendMessage").%Size(), 0, "no reply is sent")
		Do $$$AssertEquals(..HeadersFrom(headers, "TelegramIn"), 0, "TelegramIn sends no message")
		Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(audit, "OcuTalon").%Size(), 0, "and no audit entry is written")
	} Catch ex {
		Do $$$AssertTrue(0, "the private-only test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// FR-21: getMe answers 401, so Telegram stays off for that start and the state is rejected.
Method TestRejected()
{
	If '..ReadyLive() Quit
	Try {
		Set session = ..FixtureSession("zztgin")
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-getme-rejected"}), "a rejected getMe is queued")
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Do $$$AssertTrue(..WaitState("rejected", 20), "the state becomes rejected")
		Set state = ##class(OcuTalon.Data.StatusMark).TelegramState(.bot)
		Do $$$AssertEquals(state_"|"_bot, "rejected|", "with an empty name")
		Hang ##class(OcuTalon.Channel.Telegram.In).#RETRYSECONDS + 2
		Set calls = ##class(OcuTalon.Test.Contract.Mock).Calls()
		Do $$$AssertEquals(calls.%Size(), 1, "past the retry time of a failure the only call is still one call")
		Do $$$AssertEquals(calls.%Get(0).method, "getMe", "and it is getMe")
		Do $$$AssertEquals(..TelegramBlock(session), "rejected|", "StateBody says rejected")
		Do $$$AssertEquals(..Warnings(log, "rejected the bot token", "until the next start"), 1, "one warning says that Telegram rejected the token and stays off until the next start")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(log, ..Token), 0, "no log row holds the token")
		Do $$$AssertStatusOK(..StopItems(), "TelegramIn is stopped")
		Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).TelegramState(.bot)_"|"_bot, "rejected|", "after the stop the state is still rejected")
	} Catch ex {
		Do $$$AssertTrue(0, "the rejected test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// A getMe that fails with a 500 is not a rejection: the state is not rejected, a warning is logged, and getMe is tried again after 5 seconds.
Method TestStartFailureRetries()
{
	If '..ReadyLive() Quit
	Try {
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Do ##class(OcuTalon.Data.StatusMark).RecordTelegram("rejected", "")
		Set failed = {"status": 500, "body": {"ok": false, "error_code": 500, "description": "Internal Server Error"}}
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "getMe", "replies": [(failed)]}), "a 500 for getMe is queued")
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Do $$$AssertTrue(..WaitState("on", 30), "the state becomes on after the retry, so the 500 was not a rejection")
		Set tries = ..CallsOf("getMe")
		Do $$$AssertTrue(tries.%Size() >= 2, "getMe was called again")
		If tries.%Size() >= 2 {
			Set gap = ..Epoch(tries.%Get(1).ts) - ..Epoch(tries.%Get(0).ts)
			Do $$$AssertTrue(gap >= 4.9, "the second getMe is at least 5 seconds after the first: "_$Justify(gap, 0, 2))
		}
		Do $$$AssertEquals(..Warnings(log, "could not complete a call"), 1, "one warning says that a call failed")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(log, ..Token), 0, "no log row holds the token")
	} Catch ex {
		Do $$$AssertTrue(0, "the start-failure test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// A 429 for getUpdates delays the next poll by its retry_after.
Method TestUpdatesBusy()
{
	If '..ReadyLive() Quit
	Try {
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Do $$$AssertTrue(..WaitState("on", 20), "the state becomes on")
		Do $$$AssertTrue(..WaitCalls("getUpdates", 1, 20).%Size() >= 1, "a poll is open")
		Set queuedAt = ..EpochNow()
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-updates-busy"}), "a 429 with retry_after 3 is queued while the poll is open")
		Set next = ..NextPollAfter(queuedAt)
		Do $$$AssertTrue(next '= "", "TelegramIn polls again")
		If next '= "" Do $$$AssertTrue((..Epoch(next) - queuedAt) >= 3, "at least 3 seconds after the 429: "_$Justify(..Epoch(next) - queuedAt, 0, 2))
		Do $$$AssertEquals(..Warnings(log, "asked TelegramIn to wait"), 1, "one warning says that Telegram asked it to wait")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(log, ..Token), 0, "no log row holds the token")
	} Catch ex {
		Do $$$AssertTrue(0, "the busy test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// The Epoch of the first getUpdates call that the mock logged after the time, or "" when none comes within 20 seconds.
Method NextPollAfter(queuedAt As %Numeric) As %String [ Private ]
{
	Set next = ""
	Set deadline = $ZHorolog + 20
	For {
		Set polls = ..CallsOf("getUpdates")
		For i = 0:1:polls.%Size() - 1 {
			If ..Epoch(polls.%Get(i).ts) > queuedAt Set next = polls.%Get(i).ts  Quit
		}
		If (next '= "") || ($ZHorolog >= deadline) Quit
		Hang 0.25
	}
	Quit next
}

/// The number of warnings (event type 3) of the item since the mark whose text holds both phrases.
Method Warnings(log As %Integer, first As %String, second As %String = "") As %Integer [ Private ]
{
	Set rows = ##class(OcuTalon.Test.Agent.RunnerFixture).EventRows(log, "TelegramIn")
	Set told = 0, position = 0
	While $ListNext(rows, position, row) {
		If ($Extract(row, 1, 2) = "3:") && ($Find(row, first) > 0) && ((second = "") || ($Find(row, second) > 0)) Set told = told + 1
	}
	Quit told
}

/// A 429 for getUpdates with no retry_after: the wait is RETRYSECONDS, 5 seconds.
Method TestUpdatesBusyNoRetryAfter()
{
	If '..ReadyLive() Quit
	Try {
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Do $$$AssertTrue(..WaitState("on", 20), "the state becomes on")
		Do $$$AssertTrue(..WaitCalls("getUpdates", 1, 20).%Size() >= 1, "a poll is open")
		Set queuedAt = ..EpochNow()
		Set busy = {"status": 429, "body": {"ok": false, "error_code": 429, "description": "Too Many Requests"}}
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "getUpdates", "replies": [(busy)]}), "a 429 with no retry_after is queued while the poll is open")
		Set next = ..NextPollAfter(queuedAt)
		Do $$$AssertTrue(next '= "", "TelegramIn polls again")
		If next '= "" Do $$$AssertTrue((..Epoch(next) - queuedAt) >= 4.9, "at least 5 seconds after the 429: "_$Justify(..Epoch(next) - queuedAt, 0, 2))
		Do $$$AssertEquals(..Warnings(log, "asked TelegramIn to wait", "waits 5 seconds"), 1, "one warning says that Telegram asked it to wait 5 seconds")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(log, ..Token), 0, "no log row holds the token")
	} Catch ex {
		Do $$$AssertTrue(0, "the busy-without-retry_after test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// A 500 for getUpdates is no rejection and no pause: one warning, another poll after 5 seconds, and the state stays on.
Method TestUpdatesFailureRetries()
{
	If '..ReadyLive() Quit
	Try {
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Do $$$AssertTrue(..WaitState("on", 20), "the state becomes on")
		Do $$$AssertTrue(..WaitCalls("getUpdates", 1, 20).%Size() >= 1, "a poll is open")
		Set queuedAt = ..EpochNow()
		Set failed = {"status": 500, "body": {"ok": false, "error_code": 500, "description": "Internal Server Error"}}
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "getUpdates", "replies": [(failed)]}), "a 500 for getUpdates is queued while the poll is open")
		Set next = ..NextPollAfter(queuedAt)
		Do $$$AssertTrue(next '= "", "TelegramIn polls again")
		If next '= "" Do $$$AssertTrue((..Epoch(next) - queuedAt) >= 4.9, "at least 5 seconds after the 500: "_$Justify(..Epoch(next) - queuedAt, 0, 2))
		Do $$$AssertEquals(..Warnings(log, "could not complete a call", "HTTP 500"), 1, "one warning says that a call failed, with its status")
		Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).TelegramState(.bot)_"|"_bot, "on|"_..#BOT, "the state stays on, with the name")
		Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).Get("telegramPaused"), "", "and no pause is recorded")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(log, ..Token), 0, "no log row holds the token")
	} Catch ex {
		Do $$$AssertTrue(0, "the getUpdates-failure test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// A private update whose chat id RecordChat refuses (not a whole number): one warning with no id, the update is confirmed, and the
/// update after it is handled.
Method TestRecordChatFailure()
{
	If '..ReadyLive() Quit
	Do ..DropBadChats()
	Try {
		Do ..Chat("8332")
		Do ..DropChats("8332")
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Do $$$AssertTrue(..WaitState("on", 20), "the state becomes on")
		Do $$$AssertTrue(..WaitCalls("getUpdates", 1, 20).%Size() >= 1, "a poll is open")
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Set batch = []
		Do batch.%Push({"message": {"chat": {"id": 8331.5, "type": "private"}, "text": "zz bad id"}})
		Do batch.%Push(..PrivateMessage(8332))
		Do $$$AssertTrue(..QueueUpdates(batch), "an update with a chat id of 8331.5 and a good one are queued")
		Do $$$AssertTrue(..WaitOffset(3), "both are confirmed, so the offset is 3")
		Do $$$AssertEquals(..ChatRows(8332), 1, "the update after the bad one made its chat row")
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Pairing WHERE ChatId %STARTSWITH '8331'")
		Do result.%Next()
		Do $$$AssertEquals(result.%GetData(1), 0, "the bad id made no chat row")
		Do $$$AssertEquals(..Warnings(log, "could not record a chat"), 1, "one warning says that a chat was not recorded")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(log, "8331.5"), 0, "and no log row holds the id")
	} Catch ex {
		Do $$$AssertTrue(0, "the record-chat-failure test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
	Do ..DropBadChats()
}

/// Deletes every Pairing row whose chat id starts with 8331, the bad id of TestRecordChatFailure, whatever form a defect stored it in.
ClassMethod DropBadChats() [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Pairing WHERE ChatId %STARTSWITH '8331'")
}

/// A 404 for getUpdates once TelegramIn polls is a rejection: the state becomes rejected, no poll follows, and a stop keeps it.
Method TestRejectedWhilePolling()
{
	If '..ReadyLive() Quit
	Try {
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Do $$$AssertTrue(..WaitState("on", 20), "the state becomes on")
		Do $$$AssertTrue(..WaitCalls("getUpdates", 1, 20).%Size() >= 1, "a poll is open")
		Set missing = {"status": 404, "body": {"ok": false, "error_code": 404, "description": "Not Found"}}
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"method": "getUpdates", "replies": [(missing)]}), "a 404 for getUpdates is queued while the poll is open")
		Do $$$AssertTrue(..WaitState("rejected", 20), "the state becomes rejected")
		Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).TelegramState(.bot)_"|"_bot, "rejected|", "with an empty name")
		Set polls = ..CallsOf("getUpdates").%Size()
		Hang ##class(OcuTalon.Channel.Telegram.In).#RETRYSECONDS + 2
		Do $$$AssertEquals(..CallsOf("getUpdates").%Size(), polls, "no poll follows, also past the retry time of a failure")
		Do $$$AssertEquals(..Warnings(log, "rejected the bot token", "until the next start"), 1, "one warning says that Telegram rejected the token")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(log, ..Token), 0, "no log row holds the token")
		Do $$$AssertStatusOK(..StopItems(), "TelegramIn is stopped")
		Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).TelegramState(.bot)_"|"_bot, "rejected|", "after the stop the state is still rejected")
	} Catch ex {
		Do $$$AssertTrue(0, "the rejected-while-polling test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
}

/// TelegramIn calls the base of its own ApiBase row, not OCUTALON_TELEGRAM_API_BASE: with the row at a closed loopback port the mock
/// sees no call, a warning says that a call failed, and the state does not become on. The row is put back after the item is stopped.
Method TestUsesItsApiBase()
{
	If '..ReadyLive() Quit
	Set rows = ""
	Try {
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).RememberDefault(.rows, "TelegramIn", "ApiBase")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).PutDefault("TelegramIn", "ApiBase", "http://127.0.0.1:1"), "TelegramIn's ApiBase row names a closed loopback port")
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Set deadline = $ZHorolog + 20
		While (..Warnings(log, "could not complete a call") = 0) && ($ZHorolog < deadline) {
			Hang 0.25
		}
		Do $$$AssertTrue(..Warnings(log, "could not complete a call") >= 1, "a warning says that a call failed")
		Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls().%Size(), 0, "and the mock, which the variable names, sees no call")
		Do $$$AssertTrue(##class(OcuTalon.Data.StatusMark).TelegramState() '= "on", "the state does not become on")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(log, ..Token), 0, "no log row holds the token")
	} Catch ex {
		Do $$$AssertTrue(0, "the ApiBase test failed: "_..Safe(ex))
	}
	Do ..Cleanup()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(rows), "the ApiBase row is put back")
}

}
