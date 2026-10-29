Include Ensemble

/// Tests of StatusMonitor (Story 2.10; AD-12, AD-18, AD-33), the one publisher of the status live event (Story 16.9 adds the allowance
/// statuses, which it publishes on each session's own stream). They drive a shadow
/// instance of Test.Core.StatusMonitorProbe, which takes the keys and the budget that the test sets and publishes on a private
/// stream, so that they run on a slot with no production and publish nothing on the instance stream:
///   - TestFirstRunPublishesNothing: the first run only remembers the state, whatever it is;
///   - TestChangePublishesTheChangedConditions: a change publishes the full view of exactly the conditions that changed, in the
///     catalog's order, and a run with nothing changed publishes nothing;
///   - TestSlotChangeAndClear: a change of the slots publishes, and a clear publishes the condition with active false and no slots;
///   - TestTelegramPausePublishes (Story 10.3, AD-12): a telegramPaused mark recorded for a time in the future makes the next run publish one
///     status event telegramPaused, active, with that time; a run after the pause has ended publishes it inactive with no slots; nothing in
///     between. The test records the mark and puts it back;
///   - TestRefusedPublishIsPublishedAtTheNextRun: a publish that is refused (inside an open transaction, or to a stream that is
///     no stream) leaves the run returning OK with a warning, and the change is published at the next run;
///   - TestFailingReadingReturnsOK: a reading that throws gives OK with a warning and publishes nothing;
///   - TestFirstRunThatReadsIsTheSilentOne (QA): the silent run is the first one that reads, so a first run whose reading throws
///     leaves nothing remembered and the next run that reads only remembers, with the conditions that hold, before a change publishes;
///   - TestEventsBodyServesWhatItPublishes (an Integration AC): Web.Api.EventsBody, with the private stream as the instance
///     stream, serves what the monitor published, as the page polls it;
///   - TestAllowancePublishesOnTheSessionsStream (Story 16.9, AD-12): a session whose allowance window opens gets one status event
///     allowance, active, with the limit and the end of the window, on its own stream, when the next run sees it; a run after the
///     window has ended publishes the clear (active false, no slots) once; nothing in between, and nothing on the instance stream;
///   - TestAllowanceFirstRunOnlyRemembers: the first run publishes nothing for a window that is open, and a clear follows when it ends;
///   - TestAllowanceOnlyOnTheOnlineDemoAndFailedReadRemembersNothing: with the flag off nothing is read or published, and a failed
///     read of the held sessions is one warning that remembers nothing, so the next run publishes;
///   - TestProductSeams: the monitor's own seams, as the production job runs them, publish on the instance stream and read the
///     three agents' keys and the budget as Status.Readings gives them (Test.Core.StatusMonitorSeamProbe; nothing is published).
/// The private stream is the stream of a fixture session, zzstatmon<n>; its events and counter are removed before and after, and so
/// are the warnings that the probe logged.
Class OcuTalon.Test.Core.StatusMonitor Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Ref of the fixture session whose stream is the private stream.
Property Stream As %String;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

/// The number of the newest row of the event log when the test began.
Property LogMark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("StatusMonitor", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Set ..Stream = ##class(OcuTalon.Data.Session).ForUser("zzstatmon"_..Number, .sc).Ref
	Do ..ClearStream()
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Quit sc
}

Method OnAfterOneTest() As %Status
{
	If $TLevel > 0 TROLLBACK
	Do ..ClearStream()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "OnProcessInput", "StatusMonitor could not")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ..Clean()
	Quit $SYSTEM.Status.OK()
}

/// The first run publishes nothing, with a key missing and the cap reached or not; the second run, with the same state, neither.
Method TestFirstRunPublishesNothing()
{
	Set probe = ..Probe()
	Set probe.KeysReading = ..Keys(0)
	Set probe.BudgetReading = ..Budget(1, 20, "2026-10-24T04:00:00Z")
	Do $$$AssertStatusOK(probe.OnProcessInput($$$NULLOREF, .output), "the first run returns OK")
	Do $$$AssertEquals(..Events().%Size(), 0, "it published nothing, though two conditions hold")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(..Stream), 0, "and the stream's counter did not move")
	Do $$$AssertStatusOK(probe.OnProcessInput($$$NULLOREF, .output), "the second run returns OK")
	Do $$$AssertEquals(..Events().%Size(), 0, "with the state as it was, it publishes nothing")

	Set clean = ..Probe()
	Set clean.KeysReading = ..Keys(1)
	Set clean.BudgetReading = ..Budget(0, 0, "")
	Do $$$AssertStatusOK(clean.OnProcessInput($$$NULLOREF, .output), "a first run with nothing active returns OK")
	Do $$$AssertEquals(..Events().%Size(), 0, "and publishes nothing either")
}

/// A change publishes the full view of the conditions that changed, in the catalog's order; a run without a change publishes nothing.
Method TestChangePublishesTheChangedConditions()
{
	Set probe = ..Probe()
	Set probe.KeysReading = ..Keys(1)
	Set probe.BudgetReading = ..Budget(0, 0, "")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..Events().%Size(), 0, "the first run remembers the state")

	Set probe.KeysReading = ..Keys(0)
	Do $$$AssertStatusOK(probe.OnProcessInput($$$NULLOREF, .output), "a key goes missing: the run returns OK")
	Set events = ..Events()
	Do $$$AssertEquals(events.%Size(), 1, "one event is published")
	Do $$$AssertEquals(events.%Get(0).type_"|"_events.%Get(0).payload.%ToJSON(), "status|{""condition"":""noModelKey"",""active"":true}", "the full view of noModelKey, active, with no slots")
	Do $$$AssertEquals(events.%Get(0).stream_"|"_events.%Get(0).seq, "session|1", "it is event 1 of the stream")
	Do $$$AssertEquals(events.%Get(0).ts ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", 1, "stamped in UTC")

	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..Events().%Size(), 1, "the same state again: nothing more is published")

	Set probe.KeysReading = ..Keys(1)
	Set probe.BudgetReading = ..Budget(1, 20, "2026-10-24T04:00:00Z")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set events = ..Events()
	Do $$$AssertEquals(events.%Size(), 3, "two conditions changed: two more events")
	Do $$$AssertEquals(events.%Get(1).payload.%ToJSON(), "{""condition"":""dailyCap"",""active"":true,""slots"":{""cap"":20,""time"":""2026-10-24T04:00:00Z""}}", "dailyCap comes first, as the catalog orders it, with its slots")
	Do $$$AssertEquals(events.%Get(2).payload.%ToJSON(), "{""condition"":""noModelKey"",""active"":false}", "then noModelKey, cleared, with no slots")
	Do $$$AssertEquals(events.%Get(1).seq_events.%Get(2).seq, "23", "in Seq order")

	Set probe.KeysReading = ..Keys(0)
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set events = ..Events()
	Do $$$AssertEquals(events.%Size(), 4, "only noModelKey changed: one more event")
	Do $$$AssertEquals(events.%Get(3).payload.condition_"|"_events.%Get(3).payload.active, "noModelKey|1", "it is noModelKey, active again")
}

/// A changed slot publishes the condition with the new slots, and a clear publishes it with active false and no slots.
Method TestSlotChangeAndClear()
{
	Set probe = ..Probe()
	Set probe.KeysReading = ..Keys(1)
	Set probe.BudgetReading = ..Budget(1, 20, "2026-10-24T04:00:00Z")
	Do probe.OnProcessInput($$$NULLOREF, .output)

	Set probe.BudgetReading = ..Budget(1, 20, "2026-10-25T04:00:00Z")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set events = ..Events()
	Do $$$AssertEquals(events.%Size(), 1, "the reset time moved: one event")
	Do $$$AssertEquals(events.%Get(0).payload.slots.time_"|"_events.%Get(0).payload.active, "2026-10-25T04:00:00Z|1", "dailyCap with the new time")

	Set probe.BudgetReading = ..Budget(1, 30, "2026-10-25T04:00:00Z")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set events = ..Events()
	Do $$$AssertEquals(events.%Size(), 2, "the cap changed: one more event")
	Do $$$AssertEquals(+events.%Get(1).payload.slots.cap, 30, "with the new cap")

	Set probe.BudgetReading = ..Budget(0, 30, "2026-10-25T04:00:00Z")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set events = ..Events()
	Do $$$AssertEquals(events.%Size(), 3, "the cap lifted: one more event")
	Do $$$AssertEquals(events.%Get(2).payload.%ToJSON(), "{""condition"":""dailyCap"",""active"":false}", "dailyCap with active false and no slots")

	Set probe.BudgetReading = ..Budget(0, 30, "2026-10-26T04:00:00Z")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..Events().%Size(), 3, "a new reset time on a condition that doesn't hold publishes nothing")
}

/// A telegramPaused mark for a time in the future: the next run publishes telegramPaused, active, with Time = the mark. A run with the same
/// state publishes nothing. Once the time has passed the next run publishes it inactive, with no slots. The mark is put back afterwards.
Method TestTelegramPausePublishes()
{
	Set saved = ##class(OcuTalon.Data.StatusMark).Get("telegramPaused")
	Try {
		Do ##class(OcuTalon.Data.StatusMark).Record("telegramPaused", "")
		Set probe = ..Probe()
		Set probe.KeysReading = ..Keys(1)
		Set probe.BudgetReading = ..Budget(0, 0, "")
		Do probe.OnProcessInput($$$NULLOREF, .output)
		Do $$$AssertEquals(..Telegram().%Size(), 0, "the first run remembers the state, with no pause")
		Set until = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)
		Do $$$AssertStatusOK(##class(OcuTalon.Data.StatusMark).Record("telegramPaused", until), "a pause is recorded")
		Do $$$AssertStatusOK(probe.OnProcessInput($$$NULLOREF, .output), "the next run returns OK")
		Set events = ..Telegram()
		Do $$$AssertEquals(events.%Size(), 1, "one telegramPaused event is published")
		If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.%ToJSON(), "{""condition"":""telegramPaused"",""active"":true,""slots"":{""time"":"""_until_"""}}", "active, with the time of the pause")
		Do probe.OnProcessInput($$$NULLOREF, .output)
		Do $$$AssertEquals(..Telegram().%Size(), 1, "a run with the same state publishes nothing")
		Do ##class(OcuTalon.Data.StatusMark).Record("telegramPaused", ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -60))
		Do probe.OnProcessInput($$$NULLOREF, .output)
		Set events = ..Telegram()
		Do $$$AssertEquals(events.%Size(), 2, "after the pause has ended the next run publishes it again")
		If events.%Size() = 2 Do $$$AssertEquals(events.%Get(1).payload.%ToJSON(), "{""condition"":""telegramPaused"",""active"":false}", "inactive, with no slots")
		Do probe.OnProcessInput($$$NULLOREF, .output)
		Do $$$AssertEquals(..Telegram().%Size(), 2, "and then nothing more")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "no exception")
	}
	Do ##class(OcuTalon.Data.StatusMark).Record("telegramPaused", saved)
}

/// A publish that is refused leaves the run returning OK with a warning and the change unremembered, so the next run publishes it.
Method TestRefusedPublishIsPublishedAtTheNextRun()
{
	Set probe = ..Probe()
	Set probe.KeysReading = ..Keys(1)
	Set probe.BudgetReading = ..Budget(0, 0, "")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set probe.KeysReading = ..Keys(0)

	TSTART
	Set sc = probe.OnProcessInput($$$NULLOREF, .output)
	Set inTransaction = ##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "OnProcessInput", ##class(OcuTalon.Core.StatusMonitor).#LOGPUBLISH)
	TROLLBACK
	Do $$$AssertStatusOK(sc, "inside an open transaction, where Publish refuses: the run returns OK")
	Do $$$AssertEquals(inTransaction, 1, "and one warning says that the event could not be published: "_text)
	Do $$$AssertEquals(..Events().%Size(), 0, "nothing was published")

	Do $$$AssertStatusOK(probe.OnProcessInput($$$NULLOREF, .output), "the next run returns OK")
	Set events = ..Events()
	Do $$$AssertEquals(events.%Size(), 1, "it publishes the change")
	Do $$$AssertEquals(events.%Get(0).payload.condition_"|"_events.%Get(0).payload.active, "noModelKey|1", "noModelKey, active")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..Events().%Size(), 1, "and once it is published it is remembered")

	Set refusing = ..Probe()
	Set refusing.KeysReading = ..Keys(1)
	Set refusing.BudgetReading = ..Budget(0, 0, "")
	Do refusing.OnProcessInput($$$NULLOREF, .output)
	Set refusing.KeysReading = ..Keys(0)
	Set refusing.StreamRef = "not a stream"
	Do $$$AssertStatusOK(refusing.OnProcessInput($$$NULLOREF, .output), "a stream that Publish refuses: the run returns OK")
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "OnProcessInput", ##class(OcuTalon.Core.StatusMonitor).#LOGPUBLISH)
	Do $$$AssertEquals(count, 1, "outside a transaction too, one warning says that the event could not be published: "_text)
	Set refusing.StreamRef = ..Stream
	Do refusing.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..Events().%Size(), 2, "and the change is published once the stream is good")
}

/// A reading that throws gives OK, a warning and no event; the next good run compares with the state before it.
Method TestFailingReadingReturnsOK()
{
	Set probe = ..Probe()
	Set probe.KeysReading = ..Keys(1)
	Set probe.BudgetReading = ..Budget(0, 0, "")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set probe.ThrowReading = 1
	Do $$$AssertStatusOK(probe.OnProcessInput($$$NULLOREF, .output), "a reading that throws: the run returns OK")
	Do $$$AssertEquals(..Events().%Size(), 0, "nothing is published")
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "OnProcessInput", ##class(OcuTalon.Core.StatusMonitor).#LOGRUN)
	Do $$$AssertEquals(count, 1, "one warning says that the status could not be read: "_text)
	Set probe.ThrowReading = 0
	Set probe.KeysReading = ..Keys(0)
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..Events().%Size(), 1, "the next good run publishes the change")
}

/// The silent run is the first one that reads: a first run whose reading throws remembers nothing, so the next run that reads
/// only remembers (the conditions that hold publish nothing), and a change after that publishes.
Method TestFirstRunThatReadsIsTheSilentOne()
{
	Set probe = ..Probe()
	Set probe.KeysReading = ..Keys(0)
	Set probe.BudgetReading = ..Budget(1, 20, "2026-10-24T04:00:00Z")
	Set probe.ThrowReading = 1
	Do $$$AssertStatusOK(probe.OnProcessInput($$$NULLOREF, .output), "a first run whose reading throws returns OK")
	Do $$$AssertEquals(..Events().%Size(), 0, "and publishes nothing")
	Set probe.ThrowReading = 0
	Do $$$AssertStatusOK(probe.OnProcessInput($$$NULLOREF, .output), "the next run returns OK")
	Do $$$AssertEquals(..Events().%Size(), 0, "it is the first run that reads, so it only remembers, though two conditions hold")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(..Stream), 0, "and the stream's counter did not move")
	Set probe.KeysReading = ..Keys(1)
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set events = ..Events()
	Do $$$AssertEquals(events.%Size(), 1, "a change after it publishes: one event")
	Do $$$AssertEquals(events.%Get(0).payload.%ToJSON(), "{""condition"":""noModelKey"",""active"":false}", "noModelKey, cleared, with no slots")
}

/// Web.Api.EventsBody serves what the monitor published, with the private stream as the instance stream, as the page polls it.
Method TestEventsBodyServesWhatItPublishes()
{
	Set consumer = ##class(OcuTalon.Data.Session).ForUser("zzstatmonconsumer"_..Number, .sc)
	Set probe = ..Probe()
	Set probe.KeysReading = ..Keys(1)
	Set probe.BudgetReading = ..Budget(0, 0, "")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set probe.KeysReading = ..Keys(0)
	Set probe.BudgetReading = ..Budget(1, 20, "2026-10-24T04:00:00Z")
	Do probe.OnProcessInput($$$NULLOREF, .output)

	Set body = ##class(OcuTalon.Web.Api).EventsBody(consumer, 0, 0, ..Stream)
	Do $$$AssertEquals(body.events.%Size(), 2, "the poll holds the two events")
	Set first = body.events.%Get(0)
	Set second = body.events.%Get(1)
	Do $$$AssertEquals(first.stream_"|"_first.type_"|"_first.seq, "instance|status|1", "the first is a status event of the instance stream")
	Do $$$AssertEquals(first.payload.condition_"|"_first.payload.active, "dailyCap|1", "dailyCap, active")
	Do $$$AssertEquals(+first.payload.slots.cap_"|"_first.payload.slots.time, "20|2026-10-24T04:00:00Z", "with its slots")
	Do $$$AssertEquals(second.stream_"|"_second.type_"|"_second.seq, "instance|status|2", "the second follows")
	Do $$$AssertEquals(second.payload.%ToJSON(), "{""condition"":""noModelKey"",""active"":true}", "noModelKey, active")
	Set body = ##class(OcuTalon.Web.Api).EventsBody(consumer, 0, 1, ..Stream)
	Do $$$AssertEquals(body.events.%Size(), 1, "a poll from the first event's cursor holds the second only")
}

/// The seams the production job runs: Stream is the instance stream and Readings are Status.Readings. Nothing is published.
Method TestProductSeams()
{
	Set job = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.StatusMonitorSeamProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the seam probe is made")
	Do $$$AssertEquals(job.StreamName(), ##class(OcuTalon.Live.Publish).#INSTANCE, "the job publishes on the instance stream")
	Do $$$AssertEquals(job.StreamName(), "instance", "which is named instance")
	Do job.ReadingsOf(.keys, .budget)
	Do ##class(OcuTalon.Live.Payload.Status).Readings(.expectedKeys, .expectedBudget)
	Do $$$AssertEquals($IsObject($Get(keys)) && $IsObject($Get(budget)), 1, "the job reads a keys object and a budget object")
	Do $$$AssertEquals($Get(keys) '= "" && keys.%IsDefined("ChatAgent"), 1, "the keys name the agents")
	Do $$$AssertEquals($Get(keys) '= "" && (keys.%ToJSON() = expectedKeys.%ToJSON()), 1, "the keys are the agents' Keys.Status readings, as Status.Readings gives them")
	Do $$$AssertEquals($Get(budget) '= "" && (budget.%ToJSON() = expectedBudget.%ToJSON()), 1, "and the budget is Budget.State(), as Status.Readings gives it")
}

/// A session whose allowance window opens gets one status event, allowance, active, with the limit and the end of the window, on its
/// own stream at the next run; the same window again publishes nothing; once it has ended the next run publishes the clear (active
/// false, no slots) once and nothing after; the instance stream (the private stream here) gets no allowance event. Another session
/// that has no window gets nothing.
Method TestAllowancePublishesOnTheSessionsStream()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set mine = ##class(OcuTalon.Data.Session).ForUser("zzstatmon"_..Number_"mine", .sc)
	Set other = ##class(OcuTalon.Data.Session).ForUser("zzstatmon"_..Number_"other", .sc)
	Set probe = ..Probe()
	Set probe.KeysReading = ..Keys(1)
	Set probe.BudgetReading = ..Budget(0, 0, "")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..SessionEvents(mine.Ref).%Size(), 0, "the first run publishes nothing")

	Set until = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)
	Set mine.AllowanceUntil = until
	Do $$$AssertStatusOK(mine.%Save(), "the session's window opens")
	Set probe.HeldReading = $ListBuild(mine.Ref)
	Do $$$AssertStatusOK(probe.OnProcessInput($$$NULLOREF, .output), "the next run returns OK")
	Set events = ..SessionEvents(mine.Ref)
	Do $$$AssertEquals(events.%Size(), 1, "one event is published on the session's stream")
	Do $$$AssertEquals(events.%Get(0).type_"|"_events.%Get(0).stream, "status|session", "a status event")
	Do $$$AssertEquals(events.%Get(0).payload.%ToJSON(), "{""condition"":""allowance"",""active"":true,""slots"":{""limit"":"_##class(OcuTalon.Core.Allowance).Limit()_",""time"":"""_until_"""}}", "the full view: active, with the limit and the end of the window")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..SessionEvents(mine.Ref).%Size(), 1, "the same window again: nothing more")
	Do $$$AssertEquals(..SessionEvents(other.Ref).%Size(), 0, "another session gets nothing")
	Do $$$AssertEquals(..Events().%Size(), 0, "and the instance stream gets no allowance event")

	Set mine.AllowanceUntil = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -1)
	Do $$$AssertStatusOK(mine.%Save(), "the window ends")
	Set probe.HeldReading = ""
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set events = ..SessionEvents(mine.Ref)
	Do $$$AssertEquals(events.%Size(), 2, "the next run publishes the clear")
	Do $$$AssertEquals(events.%Get(1).payload.%ToJSON(), "{""condition"":""allowance"",""active"":false}", "active false and no slots")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..SessionEvents(mine.Ref).%Size(), 2, "and nothing after it")

	Set mine.AllowanceUntil = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)
	Do mine.%Save()
	Set probe.HeldReading = $ListBuild(mine.Ref)
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..SessionEvents(mine.Ref).%Size(), 3, "a window that opens again is published again")
}

/// The first run publishes nothing for a window that is already open, it only remembers, so that the run after the window ends
/// publishes the clear.
Method TestAllowanceFirstRunOnlyRemembers()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set mine = ##class(OcuTalon.Data.Session).ForUser("zzstatmon"_..Number_"first", .sc)
	Set mine.AllowanceUntil = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)
	Do $$$AssertStatusOK(mine.%Save(), "the session's window is open")
	Set probe = ..Probe()
	Set probe.KeysReading = ..Keys(1)
	Set probe.BudgetReading = ..Budget(0, 0, "")
	Set probe.HeldReading = $ListBuild(mine.Ref)
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..SessionEvents(mine.Ref).%Size(), 0, "the first run, and a second run with the same window, publish nothing")
	Set mine.AllowanceUntil = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -1)
	Do mine.%Save()
	Set probe.HeldReading = ""
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set events = ..SessionEvents(mine.Ref)
	Do $$$AssertEquals(events.%Size(), 1, "the run after the window ended publishes one event")
	Do $$$AssertEquals(events.%Get(0).payload.%ToJSON(), "{""condition"":""allowance"",""active"":false}", "the clear")
}

/// With the flag off the monitor reads and publishes no allowance status, whatever the sessions hold; a failed read of the held
/// sessions is one warning and remembers nothing, so the run that reads again publishes the change.
Method TestAllowanceOnlyOnTheOnlineDemoAndFailedReadRemembersNothing()
{
	Set mine = ##class(OcuTalon.Data.Session).ForUser("zzstatmon"_..Number_"flag", .sc)
	Set probe = ..Probe()
	Set probe.KeysReading = ..Keys(1)
	Set probe.BudgetReading = ..Budget(0, 0, "")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set mine.AllowanceUntil = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), 600)
	Do $$$AssertStatusOK(mine.%Save(), "the session has an open window")
	Set probe.HeldReading = $ListBuild(mine.Ref)
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Do $$$AssertEquals(..SessionEvents(mine.Ref).%Size(), 0, "with the flag off nothing is published")

	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set probe.FailHeld = 1
	Do $$$AssertStatusOK(probe.OnProcessInput($$$NULLOREF, .output), "a failed read of the held sessions: the run returns OK")
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "AllowanceTick", ##class(OcuTalon.Core.StatusMonitor).#LOGALLOWANCE)
	Do $$$AssertEquals(count, 1, "one warning says that the allowance status could not be published: "_text)
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "AllowanceTick", ##class(OcuTalon.Core.StatusMonitor).#LOGALLOWANCE)
	Do $$$AssertEquals(..SessionEvents(mine.Ref).%Size(), 0, "and nothing is published")
	Set probe.FailHeld = 0
	Do probe.OnProcessInput($$$NULLOREF, .output)
	Set events = ..SessionEvents(mine.Ref)
	Do $$$AssertEquals(events.%Size(), 1, "the run that reads again publishes the window")
	Do $$$AssertEquals(events.%Get(0).payload.active, 1, "as active")
}

/// The status events of a session's own stream, as the page's envelopes.
Method SessionEvents(ref As %String) As %DynamicArray [ Private ]
{
	Set found = []
	Set events = ##class(OcuTalon.Live.Event).Since(ref, 0, 200, "session")
	For i = 0:1:events.%Size() - 1 {
		If events.%Get(i).type = "status" Do found.%Push(events.%Get(i))
	}
	Quit found
}

/// A shadow instance of the probe, with the private stream.
Method Probe() As OcuTalon.Test.Core.StatusMonitorProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.StatusMonitorProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.StreamRef = ..Stream
	Quit probe
}

/// The keys reading with every agent at value.
ClassMethod Keys(value As %Boolean) As %DynamicObject [ Private ]
{
	Quit {"TriageAgent": (value), "DiagnosisAgent": (value), "ChatAgent": (value)}
}

/// The budget reading: capped or not, with the cap and the next reset.
ClassMethod Budget(capped As %Boolean, cap As %Numeric, resetsAt As %String) As %DynamicObject [ Private ]
{
	Set budget = {"spent": (cap), "cap": (cap), "resetsAt": (resetsAt)}
	Do budget.%Set("capped", capped, "boolean")
	Quit budget
}

/// The events of the private stream, as the page's envelopes.
Method Events() As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Live.Event).Since(..Stream, 0, 200, "session")
}

/// The telegramPaused events of the private stream, as the page's envelopes.
Method Telegram() As %DynamicArray [ Private ]
{
	Set found = []
	Set events = ..Events()
	For i = 0:1:events.%Size() - 1 {
		If events.%Get(i).payload.condition = "telegramPaused" Do found.%Push(events.%Get(i))
	}
	Quit found
}

/// Removes the events and the counter of the private stream.
Method ClearStream() [ Private ]
{
	Do ..ClearOf(..Stream)
}

/// Removes the events and the counter of a stream.
ClassMethod ClearOf(stream As %String) [ Private ]
{
	If stream = "" Quit
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Live.Event WHERE Stream = ?", stream)
	Kill ^OcuTalonP.LiveEventC(stream)
}

/// Deletes the fixture sessions with their events and counters.
ClassMethod Clean() [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Ref FROM OcuTalon_Data.Session WHERE IrisUser %STARTSWITH 'zzstatmon'")
	While result.%Next() {
		Do ..ClearOf(result.%Get("Ref"))
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.Session WHERE IrisUser %STARTSWITH 'zzstatmon'")
}

}
