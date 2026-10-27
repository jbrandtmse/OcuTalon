/// Tests of Live.Publish.RefreshGuide and its hook in Publish (Story 4.2; matrix row 15; AD-12, AD-33), the one publisher of guide.state,
/// with the real Demo.Guide, fixture sessions (zzguiderefresh<n>) and the real clock:
///   - TestHookPublishesOnChange: after a trigger event of a session whose view is not the blank one, exactly one guide.state follows,
///     a repeat with the same view publishes none, a changed view publishes one more, and a view that went back to the blank one is
///     published too (the base is the stream's latest guide.state);
///   - TestEachTriggerType: each of AD-12's seven trigger types, named in the test, does it;
///   - TestEachTriggerTypeOnlyOnChange and TestNonTriggerTypes (QA): each trigger type publishes only on a change, and none of the eight
///     other types triggers a refresh;
///   - TestNoRefresh: none for a non-trigger type, with demo mode off, on a stream that is no session's, for the instance stream (called
///     directly, so that nothing is published on it) and for a session whose view equals the blank one;
///   - TestHeldLock: with the guide lock held by another job, Publish answers OK with its event committed and logs one warning;
///   - TestHeldLockCallerWait: the caller's lock wait bounds the refresh too, so BridgeSink's 1 s (AD-31) is not stretched to 5 s;
///   - TestEventsBodyServesTheGuide (an Integration AC): Web.Api.EventsBody serves the guide.state the hook published, as the page polls it.
/// demo.mode is saved before the tests and put back after them.
Class OcuTalon.Test.Live.GuideRefresh Extends %UnitTest.TestCase
{

Parameter NS = "OCUORDERS";

Parameter PROD = "OcuTalon.Demo.Orders.Production";

/// The run's number.
Property Number As %Integer;

Property SavedModeFound As %Boolean;

Property SavedModeValue As %String(MAXLEN = 1000);

Property SavedModeUpdatedAt As %String(MAXLEN = 20);

/// The newest row of the event log when the test began.
Property LogMark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("GuideRefresh", "n"))
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set ..SavedModeFound = found, ..SavedModeValue = value, ..SavedModeUpdatedAt = updatedAt
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, ##class(OcuTalon.Data.Time).NowUtc())
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Publish", ##class(OcuTalon.Live.Publish).#LOGGUIDE)
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..SavedModeFound, ..SavedModeValue, ..SavedModeUpdatedAt)
	Quit $SYSTEM.Status.OK()
}

/// A trigger event follows by exactly one guide.state when the view changed against the stream's latest guide.state, and by none when
/// it did not.
Method TestHookPublishesOnChange()
{
	Set ref = ..NewSession()
	Set check = ##class(OcuTalon.Test.Data.Fixture).Check(ref, ..#NS, ..#PROD)
	Do ..Trigger(ref, "reminder")
	Set events = ..GuideEvents(ref)
	Do $$$AssertEquals(events.%Size(), 1, "one guide.state follows the first trigger event of a watching session")
	Set payload = events.%Get(0).payload
	Do $$$AssertEquals(payload.step_"|"_payload.steps.%Get(0).done_"|"_payload.breakFeed.active, "2|1|1", "it is the computed view: step 2, step 1 done, Break the feed active")
	Do ..Trigger(ref, "reminder")
	Do $$$AssertEquals(..GuideEvents(ref).%Size(), 1, "the same view again publishes none")

	Do ##class(OcuTalon.Test.Data.Fixture).Reminder(ref)
	Do ..Trigger(ref, "reminder")
	Set events = ..GuideEvents(ref)
	Do $$$AssertEquals(events.%Size(), 2, "a changed view publishes one more")
	Do $$$AssertEquals(events.%Get(1).payload.step, 3, "with step 3 current")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(check)
	Set remaining = ##class(OcuTalon.Data.Ownership).ReminderSetOrFired(ref, .sc)
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(remaining.Ref)
	Do ..Trigger(ref, "reminder")
	Set events = ..GuideEvents(ref)
	Do $$$AssertEquals(events.%Size(), 3, "a view that went back to the blank one is published too")
	Do ##class(OcuTalon.Demo.Guide).Blank().%JSONExportToString(.blank)
	Do $$$AssertEquals(events.%Get(2).payload.%ToJSON(), blank, "and it is the blank view")
}

/// Each of AD-12's seven trigger types, named here rather than read from GUIDETRIGGERS, is followed by a guide.state when the view
/// changed, and GUIDETRIGGERS holds seven types.
Method TestEachTriggerType()
{
	Set types = $ListBuild("chat.message", "incident", "approval", "check", "reminder", "pairing", "breakfeed.progress")
	Set triggers = $ListFromString(##class(OcuTalon.Live.Publish).#GUIDETRIGGERS)
	Do $$$AssertEquals($ListLength(triggers), 7, "there are seven trigger types")
	Set position = 0
	While $ListNext(types, position, type) {
		Do $$$AssertTrue($ListFind(triggers, type), type_" is a trigger type")
		Set ref = ..NewSession()
		Do ##class(OcuTalon.Test.Data.Fixture).Check(ref, ..#NS, ..#PROD)
		Do ..Trigger(ref, type)
		Do $$$AssertEquals(..GuideEvents(ref).%Size(), 1, type_" is followed by one guide.state")
	}
}

/// Each of the seven trigger types publishes only on a change (QA): a second event of the same type with the same view is followed
/// by none, and one more follows once the view changed.
Method TestEachTriggerTypeOnlyOnChange()
{
	Set types = $ListFromString(##class(OcuTalon.Live.Publish).#GUIDETRIGGERS)
	Set position = 0
	While $ListNext(types, position, type) {
		Set ref = ..NewSession()
		Do ##class(OcuTalon.Test.Data.Fixture).Check(ref, ..#NS, ..#PROD)
		Do ..Trigger(ref, type)
		Do ..Trigger(ref, type)
		Do $$$AssertEquals(..GuideEvents(ref).%Size(), 1, type_": the same view again publishes none")
		Do ##class(OcuTalon.Test.Data.Fixture).Reminder(ref)
		Do ..Trigger(ref, type)
		Do ..Trigger(ref, type)
		Do $$$AssertEquals(..GuideEvents(ref).%Size(), 2, type_": a changed view publishes one more, once")
	}
}

/// No other event type refreshes the guide (QA): every type of the event table that is neither a trigger nor guide.state is published on
/// a session whose view differs from the blank one, and none is followed by a guide.state.
Method TestNonTriggerTypes()
{
	Set triggers = $ListFromString(##class(OcuTalon.Live.Publish).#GUIDETRIGGERS)
	Set pairs = $ListFromString(##class(OcuTalon.Live.Publish).#TYPES)
	Set ref = ..NewSession()
	Do ##class(OcuTalon.Test.Data.Fixture).Check(ref, ..#NS, ..#PROD)
	Set checked = 0, position = 0
	While $ListNext(pairs, position, pair) {
		Set type = $Piece(pair, ":", 1)
		If $ListFind(triggers, type) || (type = "guide.state") Continue
		Do ..Trigger(ref, type)
		Set checked = checked + 1
	}
	Do $$$AssertEquals(checked, 8, "eight types are neither a trigger nor guide.state")
	Do $$$AssertEquals(..GuideEvents(ref).%Size(), 0, "none of them is followed by a guide.state")
	Do ..Trigger(ref, "reminder")
	Do $$$AssertEquals(..GuideEvents(ref).%Size(), 1, "while a trigger on the same session is")
}

/// No guide.state follows a non-trigger type, a trigger with demo mode off, an event of a stream that is no session's or the instance
/// stream, or a session whose view is the blank one.
Method TestNoRefresh()
{
	Set ref = ..NewSession()
	Do ##class(OcuTalon.Test.Data.Fixture).Check(ref, ..#NS, ..#PROD)
	Set status = ##class(OcuTalon.Live.Payload.Status).%New()
	Set status.Condition = "noModelKey"
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(ref, "status", status), "a non-trigger event is published")
	Do $$$AssertEquals(..GuideEvents(ref).%Size(), 0, "none follows a non-trigger type")

	Do ##class(OcuTalon.Test.Demo.Step).Put(0, ##class(OcuTalon.Data.Time).NowUtc())
	Do ..Trigger(ref, "reminder")
	Do $$$AssertEquals(..GuideEvents(ref).%Size(), 0, "none follows a trigger with demo mode off")
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).RefreshGuide(ref, .guide), "RefreshGuide with demo mode off")
	Do $$$AssertEquals(guide, "", "it computes nothing")
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, ##class(OcuTalon.Data.Time).NowUtc())

	Set stranger = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).RefreshGuide(stranger, .guide), "RefreshGuide of a stream that is no session's")
	Do $$$AssertEquals(guide, "", "it computes nothing")
	Set payload = ##class(OcuTalon.Live.Payload.Reminder).%New()
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(stranger, "reminder", payload), "a trigger event on a stream that is no session's")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(stranger, "guide.state").%Size(), 0, "none follows it")
	Do ..DropStream(stranger)

	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).RefreshGuide(##class(OcuTalon.Live.Publish).#INSTANCE, .guide), "RefreshGuide of the instance stream")
	Do $$$AssertEquals(guide, "", "it computes nothing")

	Set blank = ..NewSession()
	Do ..Trigger(blank, "reminder")
	Do $$$AssertEquals(..GuideEvents(blank).%Size(), 0, "none follows for a session whose view is the blank one")
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).RefreshGuide(blank, .guide), "RefreshGuide of a blank session")
	Do $$$AssertEquals($IsObject(guide), 1, "it outputs the computed view even when nothing is published")
}

/// With the guide lock held by another job, Publish answers OK, its event is committed and one warning is logged; nothing is
/// published for the guide.
Method TestHeldLock()
{
	Set ref = ..NewSession()
	Do ##class(OcuTalon.Test.Data.Fixture).Check(ref, ..#NS, ..#PROD)
	Kill ^OcuTalonTest("GuideRefresh", "hold", ref)
	Job ##class(OcuTalon.Test.Live.GuideRefresh).Holder(ref)
	Do ..WaitFor($Name(^OcuTalonTest("GuideRefresh", "hold", ref, "ready")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("GuideRefresh", "hold", ref, "ready")), 1, "another job holds the guide lock")
	Set payload = ##class(OcuTalon.Live.Payload.Reminder).%New()
	Set sc = ##class(OcuTalon.Live.Publish).Publish(ref, "reminder", payload, .seq)
	Set ^OcuTalonTest("GuideRefresh", "hold", ref, "release") = 1
	Do $$$AssertStatusOK(sc, "Publish answers OK")
	Do $$$AssertEquals(seq, 1, "its event is committed")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(ref), 1, "the counter moved")
	Set warnings = ##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "Publish", ##class(OcuTalon.Live.Publish).#LOGGUIDE)
	Do $$$AssertEquals(warnings, 1, "one warning is logged: "_text)
	Do $$$AssertEquals(..GuideEvents(ref).%Size(), 0, "no guide.state was published")
	Do ..WaitFor($Name(^OcuTalonTest("GuideRefresh", "hold", ref, "done")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("GuideRefresh", "hold", ref, "done")), 1, "the holder ended")
	Kill ^OcuTalonTest("GuideRefresh", "hold", ref)
	Do ..Trigger(ref, "reminder")
	Do $$$AssertEquals(..GuideEvents(ref).%Size(), 1, "the next trigger publishes once the lock is free")
}

/// A caller's lock wait bounds the refresh too (AD-31: BridgeSink waits on no lock for longer than one second): with the guide lock
/// held by another job, an approval published with a 1 s wait answers OK in under 3 s, its event committed and one warning logged.
Method TestHeldLockCallerWait()
{
	Set ref = ..NewSession()
	Do ##class(OcuTalon.Test.Data.Fixture).Check(ref, ..#NS, ..#PROD)
	Kill ^OcuTalonTest("GuideRefresh", "hold", ref)
	Job ##class(OcuTalon.Test.Live.GuideRefresh).Holder(ref)
	Do ..WaitFor($Name(^OcuTalonTest("GuideRefresh", "hold", ref, "ready")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("GuideRefresh", "hold", ref, "ready")), 1, "another job holds the guide lock")
	Set start = $ZHorolog
	Set sc = ##class(OcuTalon.Live.Publish).Publish(ref, "approval", ##class(OcuTalon.Live.Payload.Approval).%New(), .seq, 1)
	Set elapsed = $ZHorolog - start
	Set ^OcuTalonTest("GuideRefresh", "hold", ref, "release") = 1
	Do $$$AssertStatusOK(sc, "Publish answers OK")
	Do $$$AssertEquals(seq, 1, "its event is committed")
	Do $$$AssertTrue(elapsed < 3, "the refresh waited no longer than the caller's 1 s: "_elapsed_" s in all")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, "Publish", ##class(OcuTalon.Live.Publish).#LOGGUIDE), 1, "one warning is logged: "_$Get(text))
	Do ..WaitFor($Name(^OcuTalonTest("GuideRefresh", "hold", ref, "done")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("GuideRefresh", "hold", ref, "done")), 1, "the holder ended")
	Kill ^OcuTalonTest("GuideRefresh", "hold", ref)
}

/// Integration: Web.Api.EventsBody, as the page polls it, serves the guide.state that the hook published.
Method TestEventsBodyServesTheGuide()
{
	Set ref = ..NewSession()
	Set instance = ..NewSession()
	Do ##class(OcuTalon.Test.Data.Fixture).Check(ref, ..#NS, ..#PROD)
	Do ..Trigger(ref, "reminder")
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set body = ##class(OcuTalon.Web.Api).EventsBody(session, 0, 0, instance)
	Set served = ""
	Set iterator = body.events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If event.type = "guide.state" Set served = event
	}
	Do $$$AssertEquals($IsObject(served), 1, "EventsBody serves a guide.state")
	Do $$$AssertEquals(served.stream, "session", "on the session's stream")
	Do ##class(OcuTalon.Demo.Guide).Compute(ref).%JSONExportToString(.computed)
	Do $$$AssertEquals(served.payload.%ToJSON(), computed, "with Compute's view")
}

/// Publishes an event of the type, with an empty payload, on the session's stream.
Method Trigger(ref As %String, type As %String) [ Private ]
{
	Set payload = $ClassMethod(##class(OcuTalon.Live.Publish).PayloadClass(type), "%New")
	Do $$$AssertStatusOK(##class(OcuTalon.Live.Publish).Publish(ref, type, payload), type_" is published")
}

/// The guide.state events of the session's stream.
Method GuideEvents(ref As %String) As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(ref, "guide.state")
}

/// Removes the events and the counter of a stream that is no session's.
Method DropStream(stream As %String) [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("DELETE FROM OcuTalon_Live.Event WHERE Stream = ?")
	Do statement.%Execute(stream)
	Kill ^OcuTalonP.LiveEventC(stream)
}

/// A new fixture session, which Fixture.Clean removes.
Method NewSession() As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Session("zzguiderefresh"_..Number)
}

/// The job body of TestHeldLock: takes the session's guide lock and holds it until released.
ClassMethod Holder(ref As %String)
{
	If '##class(OcuTalon.Data.GuideState).Lock(ref, 5) Quit
	Set ^OcuTalonTest("GuideRefresh", "hold", ref, "ready") = 1
	Set deadline = $ZHorolog + 60
	While '$Get(^OcuTalonTest("GuideRefresh", "hold", ref, "release")) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Do ##class(OcuTalon.Data.GuideState).Unlock(ref)
	Set ^OcuTalonTest("GuideRefresh", "hold", ref, "done") = 1
}

/// Waits up to seconds for the global node named by ref to hold a value.
ClassMethod WaitFor(ref As %String, seconds As %Integer) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While '$Data(@ref) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

}
