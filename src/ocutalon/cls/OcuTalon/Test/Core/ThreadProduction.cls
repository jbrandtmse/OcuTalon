/// End-to-end tests of the trace thread over the running production (Story 2.9; AD-26, AD-4, AD-8, AD-9, AD-22, AD-29). THIS CLASS RUNS IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the running OcuTalon.Production and the CI mock, which a slot never has. Where they are
/// missing, every test fails with that reason (Guard). The real Decide and the real runners answer: the runners' keys point at the mock for the whole
/// class and are put back at its end (a failed restore fails the class), and the mock scripts the model. A message goes through WebChatIn to the real
/// Conversation; the unmarked messages of the thread tests get the triage answer of A/triage.json and the Chat answer of A/chat.json (a
/// list_productions call, then the reply "The CI mock looked at the productions.").
///   - TestTwoTurnsOneThread: two messages of one session on one day are two turns, answered by the real Decide with the mock's reply, whose Items
///     are in one trace session T: the first Item's own id. The Session row holds T and today; every header of the session's SuperSession is in
///     T, and T holds, for each turn, its two requests to Decide with their two responses and the Outbound to Notify, every request of T with the
///     session's TraceRef as its SuperSession. Each turn's agent steps are the runner's (a model step, the list_productions tool step and a model
///     step) in T, and its triage and turn Decision rows have T as their TraceSessionId, with a decision event each. The Turns keep the positions
///     of their Item headers (the second after the first, and both what Core.Trace.Position says afterwards);
///   - TestNewThreadAfterMidnight: with the Session row's day set to yesterday, the next message starts a new thread, its own Item's id, which the
///     row then holds with today, and everything of that turn is in it;
///   - TestBrokenRetryThroughTheProduction (DW-112; AD-8): the marker scenario thread-broken-retry, armed through Mock.Arm, answers the turn's
///     triage request and its first Chat request with the 400 "Invalid input" and then the retried turn with its text. The turn is retried through the running production as a
///     new Decide call under RetryItemId of the turn's ItemId, in the day's thread, and gets the scenario's text; the mock's log holds the 400 and
///     the retry's request.
/// Both thread tests also check that every session id among the headers of the run is the ID of a header whose SessionId is itself.
/// The guard, the fixture sessions, the run's number (^OcuTalonTest("ThreadProduction","n")), the sending and the clean-up are those of
/// Test.Core.InProduction; OnAfterOneTest removes the turns the tests made with their Decision, AgentStep and Usage rows (also those of a retry's
/// ItemId and the broken attempt's Decision row), the countdown of the marker, and the AI sessions the turns saved.
Class OcuTalon.Test.Core.ThreadProduction Extends OcuTalon.Test.Core.InProduction
{

/// The start of the user name of each fixture session.
Parameter SESSIONPREFIX = "zzprodthread";

/// Seconds to wait for a turn to be done, and for the item after it.
Parameter WAIT = 60;

/// The reply of A/chat.json after its list_productions call.
Parameter REPLY = "The CI mock looked at the productions.";

/// The text of the second reply of A/thread-broken-retry.json.
Parameter RETRYREPLY = "The CI mock answered the retried turn.";

/// The number of requests that thread-broken-retry's countdown answers with the 400: the turn's triage request and its first Chat request, which
/// carry the marker; the retry's Chat request, which carries it too, then gets the scenario's second reply.
Parameter ARMED = 2;

/// 1 while the runners' keys point at the CI mock.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The marker whose countdown a test armed, or "".
Property Armed As %String;

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set sc = ##super()
	If ..Missing '= "" Quit sc
	Set ..Missing = ##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()
	If ..Missing '= "" Quit sc
	Set ..Pointed = 1
	Set pointed = ##class(OcuTalon.Test.Agent.RunnerFixture).PointKeys()
	If $$$ISERR(pointed) Set ..Missing = "The entries of the runners could not be pointed at the CI mock key variable: " _ $SYSTEM.Status.GetErrorText(pointed)
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Set sc = $$$OK
	If ..Pointed {
		Set ..Pointed = 0
		Set restored = ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys()
		Set sc = $SYSTEM.Status.AppendStatus(sc, restored)
		If '##class(OcuTalon.Test.Agent.RunnerFixture).KeysAre(##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER) {
			Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The entries of the runners do not hold the placeholder of the Provider step after the restore"))
		}
		If '##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords() {
			Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The runners did not record the restored keys"))
		}
	}
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	Quit $SYSTEM.Status.AppendStatus(sc, ##super())
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	If ..Missing = "" Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Missing '= "" Quit $$$OK
	If ..Armed '= "" {
		Do ##class(OcuTalon.Test.Contract.Mock).Arm(..Armed, "")
		Set ..Armed = ""
	}
	For i = 1:1:$Length(..Sessions, ",") {
		Set session = $Piece(..Sessions, ",", i)
		If session = "" Continue
		Do ..RemoveRetries(session)
		Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveTurns(session)
	}
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	Quit $$$OK
}

/// Two messages on one day: both Items are in the trace session of the first (T), with everything the turns do.
Method TestTwoTurnsOneThread()
{
	If '..Guard() Quit
	Set session = ..Session("two")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set first = ..Turn(session, "two1", "zz first of the day")
	Set second = ..Turn(session, "two2", "zz second of the day")
	If '$IsObject(first) || '$IsObject(second) Quit
	Do $$$AssertEquals(first.ReplyText_"|"_second.ReplyText, ..#REPLY_"|"_..#REPLY, "both turns are answered by the real Decide with the mock's reply")

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
	Set unmarked = ""
	For i = 0:1:inThread.%Size() - 1 {
		Set header = inThread.%Get(i)
		If (header.type = 1) && (header.superSession '= trace) Set unmarked = unmarked_" "_header.id_":"_header.source_">"_header.target
	}
	Do $$$AssertEquals(unmarked, "", "every request of the thread carries the TraceRef as its SuperSession: the Items, the decide and turn requests, the agent steps and the replies")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(inThread, 2, "Decide", "Conversation").%Size(), 4, "and their four responses")
	Do ..AssertTurnRecords(session, thread, first, 2)
	Do ..AssertTurnRecords(session, thread, second, 4)
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
	Set first = ..Turn(session, "mid1", "zz before midnight")
	If '$IsObject(first) Quit
	Do $$$AssertEquals(first.ReplyText, ..#REPLY, "the first turn is answered by the real Decide with the mock's reply")
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Set thread1 = row.ThreadSessionId
	Do $$$AssertEquals(row.ThreadDay, ##class(OcuTalon.Core.Trace).Day(), "the first thread is today's")
	Set row.ThreadDay = $ZDate($ZDateH(row.ThreadDay, 3) - 1, 3)
	Do $$$AssertStatusOK(row.%Save(), "the row's day is set to yesterday")
	Set second = ..Turn(session, "mid2", "zz after midnight")
	If '$IsObject(second) Quit
	Do $$$AssertEquals(second.ReplyText, ..#REPLY, "and so is the second")

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
	Do ..AssertTurnRecords(session, thread1, first, 2)
	Do ..AssertTurnRecords(session, thread2, second, 4)
	Do $$$AssertEquals(second.TraceItemIndex, 1, "the new thread's first Item header is its first item")
}

/// DW-112 through the running production: the marker scenario thread-broken-retry (A/thread-broken-retry.json), armed for ARMED requests, answers
/// the turn's triage request and its first Chat request with the 400 "Invalid input", which breaks the turn's session; Conversation then asks again as a new Decide call under
/// RetryItemId of the turn's ItemId, in the day's thread with the TraceRef as SuperSession (a request under the turn's own ItemId would be refused,
/// as Decide refuses it), and the retried turn gets the scenario's second reply. The turn is done with that text and keeps its own ItemId, the
/// broken attempt keeps its fallback row, and the mock's log holds the 400 and the retry's request.
Method TestBrokenRetryThroughTheProduction()
{
	If '..Guard() Quit
	Set session = ..Session("broken")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set label = "thread-broken-retry:"_..Number
	Set ..Armed = label
	Do $$$AssertStatusOK($ClassMethod(mock, "Arm", label, ..#ARMED), "the countdown of "_label_" is armed for "_..#ARMED_" requests")
	Set mark = $ClassMethod(mock, "LogMark")
	Set row = ..Turn(session, "broken1", "zz broken then fine [[mock:"_label_"]]")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|"_..#RETRYREPLY, "the turn is done with the scenario's text, the retry's")
	Set retry = ##class(OcuTalon.Core.Conversation).RetryItemId(row.ItemId)
	Do $$$AssertTrue(retry '= row.ItemId, "the retry's ItemId is not the turn's")
	Set thread = ##class(OcuTalon.Data.Session).RefIndexOpen(session).ThreadSessionId
	Set requests = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(thread), 1, "Conversation", "Decide")
	Do $$$AssertEquals(requests.%Size(), 3, "the day's thread holds three requests to Decide: the decide, the turn and its retry")
	Set superOK = 0
	Set itemIds = ""
	For i = 0:1:requests.%Size() - 1 {
		If requests.%Get(i).superSession = trace Set superOK = superOK + 1
		Set body = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(requests.%Get(i).bodyId)
		If $IsObject(body) && (body.Kind = "turn") Set itemIds = itemIds_$ListBuild(body.ItemId)
	}
	Do $$$AssertEquals(superOK, requests.%Size(), "each with the TraceRef as its SuperSession")
	Do $$$AssertEquals($ListLength(itemIds), 2, "Decide got two turn requests")
	If $ListLength(itemIds) = 2 Do $$$AssertEquals($List(itemIds, 1)_"|"_$List(itemIds, 2), row.ItemId_"|"_retry, "the first under the turn's own ItemId, the retry under the derived one")
	Set broken = ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexOpen(row.ItemId, "turn")
	Set derived = ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexOpen(retry, "turn")
	Do $$$AssertTrue($IsObject(broken) && $IsObject(derived), "there is a turn decision under the turn's own ItemId and one under the retry's")
	If $IsObject(broken) && $IsObject(derived) {
		Do $$$AssertEquals(broken.Fallback_"|"_broken.FallbackReason, "1|error", "the broken attempt keeps its fallback row")
		Do $$$AssertEquals(derived.Fallback_"|"_derived.Ref_"|"_derived.TraceSessionId, "0|"_row.TurnDecisionRef_"|"_thread, "the retry's decision is the turn's, in the thread")
	}
	Set logged = $ClassMethod(mock, "LogSince", mark, .entries)
	Do $$$AssertStatusOK(logged, "the mock's log is read")
	Set bad = 0, good = 0
	If $$$ISOK(logged) {
		Set iterator = entries.%GetIterator()
		While iterator.%GetNext(, .entry) {
			If entry.scenario '= "thread-broken-retry" Continue
			If entry.status = 400 Set bad = bad + 1
			If entry.status = 200 Set good = good + 1
		}
	}
	Do $$$AssertEquals(bad, ..#ARMED, "the mock's log holds the 400 of the scenario for each armed request (the triage request and the turn's first Chat request)")
	Do $$$AssertEquals(good, 1, "and the one request of the retry that got its text")
	Do $$$AssertStatusOK($ClassMethod(mock, "Arm", label, ""), "the countdown is cleared")
	Set ..Armed = ""
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

/// The records of a done turn of the session in the thread: the steps of its turn decision are the runner's (a model step, the list_productions
/// tool step and a model step, with their headers in the thread), and its triage and turn Decision rows have the thread as their TraceSessionId and
/// each one decision event on the session's stream, which holds expected decision events once the turn's two are published (the wait is a poll).
Method AssertTurnRecords(session As %String, thread As %Integer, row As OcuTalon.Data.Turn, expected As %Integer) [ Private ]
{
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).StepProblems(row.TurnDecisionRef, thread, $ListBuild("Listing the productions"), $ListBuild("list_productions")), "", "the steps of the turn are right, in the thread")
	Set all = ##class(OcuTalon.Test.Core.Observe).Events(session, "decision", expected, ..#WAIT)
	For ref = row.TriageDecisionRef, row.TurnDecisionRef {
		Set decision = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(ref)
		Do $$$AssertEquals($IsObject(decision) && (decision.TraceSessionId = thread), 1, "decision "_ref_" has the thread as its TraceSessionId")
		Set events = 0
		For i = 0:1:all.%Size() - 1 {
			If all.%Get(i).payload.ref = ref Set events = events + 1
		}
		Do $$$AssertEquals(events, 1, "and one decision event")
	}
}

/// Removes what a retry left that the turn rows do not name: the AgentStep and Usage rows of the ItemId of each turn of the session and of its retry,
/// and the turn Decision rows under those ItemIds (a broken attempt's included), which are adopted for the clean-up.
Method RemoveRetries(session As %String) [ Private ]
{
	Set turns = ##class(OcuTalon.Data.Ownership).Turns(session, .sc)
	Set refs = ""
	For j = 1:1:turns.Count() {
		Set itemId = turns.GetAt(j).ItemId
		For one = itemId, ##class(OcuTalon.Core.Conversation).RetryItemId(itemId) {
			Do ##class(OcuTalon.Test.Agent.RunnerFixture).DeleteSteps(one)
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", one)
			Set decision = ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexOpen(one, "turn")
			If $IsObject(decision) && (decision.OwnerRef = session) Set refs = refs_$Select(refs = "": "", 1: ",")_##class(OcuTalon.Test.Data.Fixture).Adopt(decision)
		}
	}
	If refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(refs)
}

}
