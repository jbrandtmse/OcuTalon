/// End-to-end tests of the trace thread over the running production (Story 2.9; AD-26, AD-4, AD-29). THIS CLASS RUNS IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the running OcuTalon.Production, which a slot never has, and it changes the
/// running configuration of the production for the length of the class. Where the production does not run, every test fails with
/// that reason (Guard).
/// Until Stories 1.3 and 1.5 build the real Decide and AgentSteps (Epic 11 removes this switch), Decide is a stub that answers an
/// error status. So OnBeforeAllTests swaps the running item Decide to Test.Core.DecideDouble, through Ens.Config.Production and
/// Ens.Director.UpdateProduction, and OnAfterAllTests puts back the class and the settings the item had, even after a failure. The
/// double, as a production item, answers in the thread it was called in and sends two OcuTalon.Bridge.Msg.AgentStep messages for
/// each decision it makes. Each test records the double's decisions (DecideDouble.Record), so that they carry the thread as their
/// TraceSessionId.
///   - TestTwoTurnsOneThread: two messages of one session on one day are two turns, answered by the double, whose Items are in one
///     trace session T: the first Item's own id. The Session row holds T and today; every header of the session's SuperSession is in
///     T, and T holds, for each turn, its two requests to Decide with their two responses, the agent steps of every decision and
///     the Outbound to Notify. The decisions the double wrote have T as their TraceSessionId, and the Turns keep the positions of
///     their Item headers (the second after the first, and both what Core.Trace.Position says afterwards);
///   - TestNewThreadAfterMidnight: with the Session row's day set to yesterday, the next message starts a new thread, its own Item's
///     id, which the row then holds with today, and everything of that turn is in it;
///   - TestStubFallsBackAfterTheRestore: with Decide put back, a turn falls back through the stub (the reason unusable), and the
///     double is swapped in again for the tests after it.
/// Both thread tests also check that every session id among the headers of the run is the ID of a header whose SessionId is itself.
/// The guard, the fixture sessions, the run's number (^OcuTalonTest("ThreadProduction","n")), the sending and the clean-up are those
/// of Test.Core.InProduction; the clean-up also removes the turns that Conversation made with their events, the decisions the
/// double wrote, and the double's records.
Class OcuTalon.Test.Core.ThreadProduction Extends OcuTalon.Test.Core.InProduction
{

/// The start of the user name of each fixture session.
Parameter SESSIONPREFIX = "zzprodthread";

/// Seconds to wait for a turn to be done, and for the item after it.
Parameter WAIT = 30;

/// The class that replaces Decide while the class runs.
Parameter DOUBLE = "OcuTalon.Test.Core.DecideDouble";

/// The item that is swapped.
Parameter ITEM = "Decide";

/// The seconds that UpdateProduction waits for the item's jobs.
Parameter UPDATEWAIT = 30;

/// 1 while the Decide item is the double.
Property Swapped As %Boolean [ InitialExpression = 0 ];

/// The class of the Decide item before the swap.
Property OriginalClass As %String(MAXLEN = 220);

/// The settings of the Decide item before the swap, as a JSON array of {target, name, value}.
Property OriginalSettings As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set status = ##super()
	Set ..Swapped = 0
	If ..Missing '= "" Quit status
	Set sc = ..UseDouble(1)
	If $SYSTEM.Status.IsError(sc) Set ..Missing = "The item Decide could not be swapped to the double: "_$SYSTEM.Status.GetErrorText(sc)
	Quit status
}

Method OnAfterAllTests() As %Status
{
	Set restored = $SYSTEM.Status.OK()
	If ..Swapped Set restored = ..UseDouble(0)
	For i = 1:1:$Length(..Sessions, ",") {
		Set session = $Piece(..Sessions, ",", i)
		If session = "" Continue
		Set written = ##class(OcuTalon.Test.Core.DecideDouble).Written(session)
		If written '= "" Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_written
		Do ##class(OcuTalon.Test.Core.DecideDouble).Clear(session)
	}
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	Set status = ##super()
	Quit $Select($SYSTEM.Status.IsError(restored): restored, 1: status)
}

/// Two messages on one day: both Items are in the trace session of the first (T), with everything the turns do.
Method TestTwoTurnsOneThread()
{
	If '..Guard() Quit
	Set session = ..Session("two")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Do ##class(OcuTalon.Test.Core.DecideDouble).Record(session, 1)
	Set first = ..Turn(session, "two1", "zz first of the day")
	Set second = ..Turn(session, "two2", "zz second of the day")
	If '$IsObject(first) || '$IsObject(second) Quit
	Do $$$AssertEquals(first.ReplyText_"|"_second.ReplyText, "zz reply to zz first of the day|zz reply to zz second of the day", "both turns are answered by the double")

	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set items = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "WebChatIn", "Conversation")
	Do $$$AssertEquals(items.%Size(), 2, "two Item headers go from WebChatIn to Conversation")
	If items.%Size() '= 2 Quit
	Set thread = items.%Get(0).id
	Do $$$AssertEquals(items.%Get(0).sessionId, thread, "the first Item starts the thread: its session is its own ID")
	Do $$$AssertEquals(items.%Get(1).sessionId, thread, "the second Item is in that thread")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, thread_"|"_##class(OcuTalon.Core.Trace).Day(), "the Session row holds the thread and today")
	Set strays = 0
	For i = 0:1:headers.%Size() - 1 {
		If headers.%Get(i).sessionId '= thread Set strays = strays + 1
	}
	Do $$$AssertEquals(strays, 0, "every one of the "_headers.%Size()_" headers of the session's SuperSession is in the thread")
	Do $$$AssertEquals(first.TraceHeaderId_"|"_second.TraceHeaderId, items.%Get(0).id_"|"_items.%Get(1).id, "the Turns' trace targets are their Item headers")

	Set inThread = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(thread)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(inThread, 1, "Conversation", "Decide").%Size(), 4, "the thread holds two requests to Decide for each turn")
	Set requests = ##class(OcuTalon.Test.Data.Fixture).Between(inThread, 1, "Conversation", "Decide")
	Set superOK = 0
	For i = 0:1:requests.%Size() - 1 {
		If requests.%Get(i).superSession = trace Set superOK = superOK + 1
	}
	Do $$$AssertEquals(superOK, 4, "each with the TraceRef as its SuperSession")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(inThread, 2, "Decide", "Conversation").%Size(), 4, "and their four responses")
	Set steps = ##class(OcuTalon.Test.Data.Fixture).Between(inThread, 1, "Decide", "AgentSteps")
	Do $$$AssertTrue(steps.%Size() >= 4, "and the agent steps: "_steps.%Size()_" requests to AgentSteps, at least two for each turn")
	Set written = ##class(OcuTalon.Test.Core.DecideDouble).Written(session)
	Do $$$AssertEquals($Length(written, ","), 4, "the double wrote four decisions")
	For i = 1:1:$Length(written, ",") {
		Set decisionRef = $Piece(written, ",", i)
		Set count = 0
		For j = 0:1:steps.%Size() - 1 {
			If ##class(OcuTalon.Bridge.Msg.AgentStep).%OpenId(steps.%Get(j).bodyId).DecisionRef = decisionRef Set count = count + 1
		}
		Do $$$AssertTrue(count >= 2, "decision "_i_" has "_count_" agent steps in the thread")
		Set decision = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(decisionRef)
		Do $$$AssertEquals($IsObject(decision) && (decision.TraceSessionId = thread), 1, "and its TraceSessionId is the thread")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(inThread, 1, "Conversation", "Notify").%Size(), 2, "the thread holds one Outbound to Notify for each turn")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(inThread, 1, "Notify", "WebChatOut").%Size(), 2, "and Notify's send to WebChatOut")
	Do ..AssertRealSessions(headers, thread)

	Do $$$AssertEquals(first.TraceItemIndex_"|"_first.TraceItemIndexNoEvents, "1|1", "the first Item header is the first item of its session")
	Do $$$AssertTrue(second.TraceItemIndex > first.TraceItemIndex, "the second turn's position is after the first's: "_second.TraceItemIndex)
	Do $$$AssertStatusOK(##class(OcuTalon.Core.Trace).Position(second.TraceHeaderId, .withEvents, .withoutEvents), "Position reads the second Item header")
	Do $$$AssertEquals(second.TraceItemIndex_"|"_second.TraceItemIndexNoEvents, withEvents_"|"_withoutEvents, "and gives the positions the Turn kept")
	Do $$$AssertTrue(second.TraceItemIndexNoEvents <= second.TraceItemIndex, "without the event rows the position is no larger")
}

/// With the row's day set to yesterday the next message starts a new thread: the second turn's Item is in a session of its own, the
/// row holds it with today, and all that the second turn does is in it, while the first turn's headers stay in the first.
Method TestNewThreadAfterMidnight()
{
	If '..Guard() Quit
	Set session = ..Session("midnight")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Do ##class(OcuTalon.Test.Core.DecideDouble).Record(session, 1)
	Set first = ..Turn(session, "mid1", "zz before midnight")
	If '$IsObject(first) Quit
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Set thread1 = row.ThreadSessionId
	Do $$$AssertEquals(row.ThreadDay, ##class(OcuTalon.Core.Trace).Day(), "the first thread is today's")
	Set row.ThreadDay = $ZDate($ZDateH(row.ThreadDay, 3) - 1, 3)
	Do $$$AssertStatusOK(row.%Save(), "the row's day is set to yesterday")
	Set second = ..Turn(session, "mid2", "zz after midnight")
	If '$IsObject(second) Quit

	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set items = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "WebChatIn", "Conversation")
	Do $$$AssertEquals(items.%Size(), 2, "two Item headers go from WebChatIn to Conversation")
	If items.%Size() '= 2 Quit
	Set thread2 = items.%Get(1).id
	Do $$$AssertEquals(items.%Get(0).sessionId_"|"_items.%Get(1).sessionId, thread1_"|"_thread2, "the Items are in two threads")
	Do $$$AssertEquals(thread1 '= thread2, 1, "the second Item starts a new thread, its own ID")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do $$$AssertEquals(row.ThreadSessionId_"|"_row.ThreadDay, thread2_"|"_##class(OcuTalon.Core.Trace).Day(), "the row holds the new thread and today")
	Set inFirst = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(thread1)
	Set inSecond = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(thread2)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(inSecond, 1, "Conversation", "Decide").%Size(), 2, "the new thread holds the second turn's two requests to Decide")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(inSecond, 1, "Conversation", "Notify").%Size(), 1, "and its Outbound")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(inFirst, 1, "Conversation", "Decide").%Size(), 2, "the first thread keeps the first turn's two")
	Set mixed = 0
	For i = 0:1:inFirst.%Size() - 1 {
		If inFirst.%Get(i).id >= thread2 Set mixed = mixed + 1
	}
	For i = 0:1:inSecond.%Size() - 1 {
		If inSecond.%Get(i).id < thread2 Set mixed = mixed + 1
	}
	Do $$$AssertEquals(mixed, 0, "no header of the second turn is in the first thread, and none of the first in the second")
	Do ..AssertRealSessions(headers, thread1)
	Do ..AssertRealSessions(inSecond, thread2)
	Do $$$AssertEquals(second.TraceItemIndex, 1, "the new thread's first Item header is its first item")
}

/// With Decide put back, a turn falls back through the stub, which answers an error status (the fallback unusable); then the
/// double is swapped in again.
Method TestStubFallsBackAfterTheRestore()
{
	If '..Guard() Quit
	Set session = ..Session("stub")
	Try {
		Do $$$AssertStatusOK(..UseDouble(0), "the item Decide is the real one again")
		Set row = ..Turn(session, "stub1", "zz through the stub")
		If $IsObject(row) Do $$$AssertEquals(row.ReplyCatalogKey_"|"_row.FallbackReason_"|"_row.ReplyText, "conversation.turnFallback|unusable|", "the turn falls back: the stub answers an error status")
	} Catch exception {
		Do $$$AssertTrue(0, "the test threw: "_exception.DisplayString())
	}
	Do $$$AssertStatusOK(..UseDouble(1), "the double is swapped in again")
}

/// --- helpers ---
/// Sends the message and waits for its turn to be done and for the Outbound to reach WebChatOut; the turn, or "" with a failed
/// assertion.
Method Turn(session As %String, name As %String, text As %String) As OcuTalon.Data.Turn [ Private ]
{
	Set clientId = "zzc"_..Number_name
	Do $$$AssertStatusOK(..Send(session, clientId, text, .output), "the message "_name_" is accepted")
	Set row = ..WaitDone(session, clientId)
	If '$IsObject(row) || (row.State '= "done") {
		Do $$$AssertTrue(0, "the turn "_name_" is done within "_..#WAIT_" seconds")
		Quit ""
	}
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set count = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "Conversation", "Notify").%Size()
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "Notify", "WebChatOut", count, ..#WAIT), "WebChatOut has handled the Outbound of the turn "_name)
	Quit row
}

/// Every session id among the headers (an array of header objects as Fixture.Headers gives them) and the extra session is the ID of
/// a header whose SessionId is itself.
Method AssertRealSessions(headers As %DynamicArray, extra As %String) [ Private ]
{
	Kill seen
	Set seen(extra) = ""
	For i = 0:1:headers.%Size() - 1 {
		Set seen(headers.%Get(i).sessionId) = ""
	}
	Set session = ""
	For {
		Set session = $Order(seen(session))
		Quit:session=""
		Set header = ##class(Ens.MessageHeader).%OpenId(session)
		Do $$$AssertEquals($IsObject(header) && (header.SessionId = session), 1, "session "_session_" is the ID of a header whose SessionId is itself")
	}
}

/// Swaps the Decide item between the double (on) and the class and settings it had (off) in the production's configuration, then
/// updates the running production.
Method UseDouble(on As %Boolean) As %Status [ Private ]
{
	If +on = ..Swapped Quit $SYSTEM.Status.OK()
	Set production = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
	If '$IsObject(production) Quit $SYSTEM.Status.Error(5001, "There is no configuration of the production "_..#PRODUCTION)
	Set item = production.FindItemByConfigName(..#ITEM)
	If '$IsObject(item) Quit $SYSTEM.Status.Error(5001, "The production has no item "_..#ITEM)
	If on {
		Set ..OriginalClass = item.ClassName
		Set settings = []
		For i = 1:1:item.Settings.Count() {
			Do settings.%Push({"target": (item.Settings.GetAt(i).Target), "name": (item.Settings.GetAt(i).Name), "value": (item.Settings.GetAt(i).Value)})
		}
		Set ..OriginalSettings = settings.%ToJSON()
		Set item.ClassName = ..#DOUBLE
		Do item.Settings.Clear()
	} Else {
		Set item.ClassName = ..OriginalClass
		Do item.Settings.Clear()
		Set settings = ##class(%DynamicArray).%FromJSON(..OriginalSettings)
		For i = 0:1:settings.%Size() - 1 {
			Set setting = ##class(Ens.Config.Setting).%New()
			Set setting.Target = settings.%Get(i).target
			Set setting.Name = settings.%Get(i).name
			Set setting.Value = settings.%Get(i).value
			Do item.Settings.Insert(setting)
		}
	}
	Set sc = production.%Save()
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set ..Swapped = +on
	Quit ##class(Ens.Director).UpdateProduction(..#UPDATEWAIT)
}

}
