/// Live tests of the 409 pause of TelegramIn against the CI mock and the production's own StatusMonitor (Story 12.2; FR-22, AD-12, AD-14,
/// AD-18). THESE TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), like OcuTalon.Test.Channel.LiveCase, which they extend, and they follow
/// OcuTalon.Test.Schedule.Stalled: StateBody's status members, and the status events that StatusMonitor's job publishes on the instance
/// stream after InstanceSeq. A test stands in for elapsed time by moving the telegramPaused mark. Each test waits for StatusMonitor's job to
/// pass its silent first run, and, after its Cleanup, for its own clear, so that no telegramPaused event lands in a later test's window.
///   - TestPause409: a 409 sets the mark 300 s ahead within 2 s, no getUpdates follows in 4 s, one warning names the pause and its time,
///     StateBody holds telegramPaused active with that time, and StatusMonitor publishes the onset;
///   - TestResumeSucceeds: no poll before the mark's time, the first 200 deletes the mark, StateBody holds no telegramPaused, and StatusMonitor
///     publishes the clear with no telegramPaused event between the onset and the clear;
///   - TestResumeMeetsAnother409: the first poll after the mark gets a queued 409, and the mark is 300 s ahead again;
///   - TestRestartHonoursPause (QA): an item started while the mark is still ahead makes no call at all, not even getMe, until the
///     mark's time, and then starts and deletes the mark with the first 200.
Class OcuTalon.Test.Channel.TelegramPause Extends OcuTalon.Test.Channel.LiveCase
{

/// The mark of the pause.
Parameter MARK = "telegramPaused";

/// The number of telegramPaused events with a Seq above from and below to.
ClassMethod Count(from As %Integer, to As %Integer) As %Integer [ Private ]
{
	Set count = 0
	Set events = ..Events(from)
	Set iterator = events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If event.seq < to Set count = count + 1
	}
	Quit count
}

/// The telegramPaused members of StateBody's status array.
ClassMethod Members(session As OcuTalon.Data.Session) As %DynamicArray [ Private ]
{
	Set members = []
	Set iterator = ##class(OcuTalon.Web.Api).StateBody(session).status.%GetIterator()
	While iterator.%GetNext(, .condition) {
		If condition.condition = "telegramPaused" Do members.%Push(condition)
	}
	Quit members
}

/// The seconds that a UTC time is ahead of now (negative when it is behind).
ClassMethod Ahead(utc As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Data.Time).Seconds(utc) - ##class(OcuTalon.Data.Time).Seconds(##class(OcuTalon.Data.Time).NowUtc())
}

/// Starts TelegramIn, waits until a long poll is open, and queues the 409; returns the time of the queueing. 0 when the item did not start.
Method StartAndConflict() As %Numeric [ Private ]
{
	Set sc = ..StartItems("TelegramIn")
	Do $$$AssertStatusOK(sc, "TelegramIn is enabled")
	If $$$ISERR(sc) Quit 0
	Do $$$AssertTrue(..WaitState("on", 20), "the state becomes on")
	Do $$$AssertTrue(..WaitCalls("getUpdates", 1, 20).%Size() >= 1, "a long poll is open")
	Set queuedAt = ..EpochNow()
	Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-conflict"}), "a 409 is queued while the poll is open")
	Quit queuedAt
}

/// The ending of a pause test: the usual Cleanup, and then the wait for the test's own clear.
Method Ending(since As %Integer) [ Private ]
{
	Do ..Cleanup()
	Do $$$AssertTrue(..WaitClear(since), "StatusMonitor has published the clear of the test's pause")
}

/// FR-22: a 409 pauses for 5 minutes, records the time, logs it, and turns on telegramPaused for /state and StatusMonitor.
Method TestPause409()
{
	If '..ReadyLive() Quit
	Set since = ..InstanceSeq()
	Try {
		Set session = ..FixtureSession("zztgpause")
		Set log = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
		Do $$$AssertTrue(..WaitMonitor(), "StatusMonitor's job is past its silent first run")
		Set since = ..InstanceSeq()
		Set queuedAt = ..StartAndConflict()
		Do $$$AssertTrue(queuedAt > 0, "the conflict is queued")
		Do $$$AssertTrue(..WaitMark(..#MARK, 1, 2), "within 2 seconds the pause mark is set")
		Set mark = ##class(OcuTalon.Data.StatusMark).Get(..#MARK)
		Do $$$AssertTrue($ZAbs(..Ahead(mark) - 300) <= 5, "it is a UTC time 300 seconds ahead, within 5: "_..Ahead(mark))
		Set polls = ..CallsOf("getUpdates").%Size()
		Hang 4
		Do $$$AssertEquals(..CallsOf("getUpdates").%Size(), polls, "no getUpdates follows in the next 4 seconds")
		Set rows = ##class(OcuTalon.Test.Agent.RunnerFixture).EventRows(log, "TelegramIn")
		Set told = 0, position = 0
		While $ListNext(rows, position, row) {
			If ($Extract(row, 1, 2) = "3:") && ($Find(row, "pauses until "_mark) > 0) && ($Find(row, "terminated by other getUpdates request") > 0) Set told = told + 1
		}
		Do $$$AssertEquals(told, 1, "one warning names the pause, its time and Telegram's description of the conflict")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(log, ..Token), 0, "no log row holds the token")
		Set members = ..Members(session)
		Do $$$AssertEquals(members.%Size(), 1, "StateBody holds one telegramPaused member")
		Set expected = {"condition": "telegramPaused", "active": true, "slots": {"time": (mark)}}.%ToJSON()
		If members.%Size() = 1 Do $$$AssertEquals(members.%Get(0).%ToJSON(), expected, "active, with the mark's time")
		Set onset = ..WaitEvent(since, 1)
		Do $$$AssertTrue(onset > 0, "StatusMonitor publishes the onset within 30 seconds")
		If onset > 0 {
			Set events = ..Events(since)
			If events.%Size() '= 0 Do $$$AssertEquals(events.%Get(0).payload.%ToJSON(), expected, "with the mark's time as its payload")
		}
	} Catch ex {
		Do $$$AssertTrue(0, "the pause test failed: "_..Safe(ex))
	}
	Do ..Ending(since)
}

/// FR-22: the pause has run out, so the poll succeeds, the mark is deleted and StatusMonitor publishes the clear.
Method TestResumeSucceeds()
{
	If '..ReadyLive() Quit
	Set since = ..InstanceSeq()
	Try {
		Set session = ..FixtureSession("zztgpause")
		Do $$$AssertTrue(..WaitMonitor(), "StatusMonitor's job is past its silent first run")
		Set since = ..InstanceSeq()
		Do $$$AssertTrue(..StartAndConflict() > 0, "the conflict is queued")
		Do $$$AssertTrue(..WaitMark(..#MARK, 1, 5), "the pause mark is set")
		Set onset = ..WaitEvent(since, 1)
		Do $$$AssertTrue(onset > 0, "StatusMonitor has published the onset")
		Set until = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 2)
		Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).Record(..#MARK, until), "the mark is moved to 2 seconds ahead")
		Set polls = ..CallsOf("getUpdates").%Size()
		Do $$$AssertTrue(..WaitMark(..#MARK, 0, 15), "the first 200 deletes the mark")
		Set after = ..CallsOf("getUpdates")
		Do $$$AssertTrue(after.%Size() > polls, "TelegramIn polled again")
		If after.%Size() > polls {
			Do $$$AssertTrue(..Epoch(after.%Get(polls).ts) >= (##class(OcuTalon.Data.Time).Seconds(until) - 0.05), "and not before the mark's time")
		}
		Do $$$AssertEquals(..Members(session).%Size(), 0, "StateBody holds no telegramPaused")
		Set clear = ..WaitEvent(onset, 0)
		Do $$$AssertTrue(clear > 0, "StatusMonitor publishes the clear within 30 seconds")
		If clear > 0 Do $$$AssertEquals(..Count(onset, clear), 0, "with no telegramPaused event between the onset and the clear")
	} Catch ex {
		Do $$$AssertTrue(0, "the resume test failed: "_..Safe(ex))
	}
	Do ..Ending(since)
}

/// FR-22: the first poll after the mark gets another 409, so the pause is 5 minutes again.
Method TestResumeMeetsAnother409()
{
	If '..ReadyLive() Quit
	Set since = ..InstanceSeq()
	Try {
		Do $$$AssertTrue(..WaitMonitor(), "StatusMonitor's job is past its silent first run")
		Set since = ..InstanceSeq()
		Do $$$AssertTrue(..StartAndConflict() > 0, "the conflict is queued")
		Do $$$AssertTrue(..WaitMark(..#MARK, 1, 5), "the pause mark is set")
		Set until = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 2)
		Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).Record(..#MARK, until), "the mark is moved to 2 seconds ahead")
		Do $$$AssertTrue(##class(OcuTalon.Test.Contract.Mock).Control("replies", {"scenario": "telegram-conflict"}), "another 409 is queued during the pause")
		Set polls = ..CallsOf("getUpdates").%Size()
		Set deadline = $ZHorolog + 15
		For {
			Set mark = ##class(OcuTalon.Data.StatusMark).Get(..#MARK)
			If (mark '= until) || ($ZHorolog >= deadline) Quit
			Hang 0.25
		}
		Do $$$AssertTrue(mark '= until, "the mark was written again")
		Do $$$AssertTrue($ZAbs(..Ahead(mark) - 300) <= 5, "it is 300 seconds ahead again: "_..Ahead(mark))
		Set after = ..CallsOf("getUpdates")
		Do $$$AssertEquals(after.%Size(), polls + 1, "exactly one poll was made, and it got the 409")
		If after.%Size() > polls {
			Do $$$AssertTrue(..Epoch(after.%Get(polls).ts) >= (##class(OcuTalon.Data.Time).Seconds(until) - 0.05), "after the mark's time, not during the pause")
		}
		Hang 3
		Do $$$AssertEquals(..CallsOf("getUpdates").%Size(), polls + 1, "and no poll follows")
	} Catch ex {
		Do $$$AssertTrue(0, "the re-pause test failed: "_..Safe(ex))
	}
	Do ..Ending(since)
}

/// FR-22: a restart honours the pause. The mark is ahead when the item starts, so it makes no call, getMe included, before the mark's time.
Method TestRestartHonoursPause()
{
	If '..ReadyLive() Quit
	Set since = ..InstanceSeq()
	Try {
		Do $$$AssertTrue(..WaitMonitor(), "StatusMonitor's job is past its silent first run")
		Set since = ..InstanceSeq()
		Set until = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 8)
		Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).Record(..#MARK, until), "the mark is 8 seconds ahead before the item starts")
		Do $$$AssertStatusOK(..StartItems("TelegramIn"), "TelegramIn is enabled")
		Hang 3
		Do $$$AssertEquals(##class(OcuTalon.Test.Contract.Mock).Calls().%Size(), 0, "3 seconds after the start the mock has seen no call at all")
		Do $$$AssertEquals(##class(OcuTalon.Data.StatusMark).TelegramState(.bot)_"|"_bot, "off|", "and the state is still off")
		Do $$$AssertTrue(..WaitState("on", 20), "after the mark's time the state becomes on")
		Set first = ##class(OcuTalon.Test.Contract.Mock).Calls()
		Do $$$AssertTrue(first.%Size() > 0, "the mock has seen calls")
		If first.%Size() > 0 {
			Do $$$AssertEquals(first.%Get(0).method, "getMe", "the first is getMe")
			Do $$$AssertTrue(..Epoch(first.%Get(0).ts) >= (##class(OcuTalon.Data.Time).Seconds(until) - 0.05), "and not before the mark's time")
		}
		Do $$$AssertTrue(..WaitMark(..#MARK, 0, 15), "the first 200 deletes the mark")
	} Catch ex {
		Do $$$AssertTrue(0, "the restart-pause test failed: "_..Safe(ex))
	}
	Do ..Ending(since)
}

}
