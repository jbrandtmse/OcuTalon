/// Tests of the turn pipeline of Conversation (Story 2.4; AD-6, AD-8, AD-10, AD-12, AD-30, AD-32). Safe on a slot: no
/// production runs there, so the tests call OnRequest on shadow instances of OcuTalon.Test.Core.ConversationProbe, which hands
/// each request to Decide to OcuTalon.Test.Core.DecideDouble and keeps its answer until the test delivers it, the way the
/// framework would. A RunTurns request that the probe records goes to a new probe, as the framework starts a new instance for
/// it. The real Interoperability path is the job of OcuTalon.Test.Core.ConversationProduction, and the sweep of OnRequest
/// with an empty SessionRef is tested there only, because it re-queues every session's running turns. Every text and every
/// sentence is written out here, never read from Conversation or the catalog.
///   - TestTurnRows: the Turn goes from queued to running to done and keeps the message, the reply as sent and both DecisionRefs;
///   - TestDecideThenTurn: Decide gets a decide request and then a turn request, each with the ids and Summary, the thread and
///     the SuperSession; one Outbound goes to Notify with the origin channel;
///   - TestStagesPublished: chat.message is published when the turn is queued, when the decision lands and when the reply lands;
///   - TestStagesInOrder: a turn that waits behind another is published as queued, and as running and done only once it runs;
///   - TestEveryTriageOutcomeRuns: whatever the attention decision was, the turn request is sent and the turn has one reply;
///   - TestSecondMessageWaits: a message sent during a turn is its own turn that starts after the first is done (NFR-6);
///   - TestBusyRequeues, TestBrokenRetriedFresh, TestTaintedNextFresh: the reply shapes of AD-6 and AD-10;
///   - TestBrokenRetryIsANewItem (DW-112; AD-20): the retry after a broken session is a new Decide call under RetryItemId of the
///     turn's ItemId, which the double, recording like Decide, accepts because the broken attempt's row is under the turn's own;
///   - TestPositionFailureNeverStopsTurn (Story 2.9; AD-26): an Item whose position in the trace cannot be worked out is one
///     warning, and the turn is still taken, with both positions empty;
///   - TestTakeKeepsTheItemsPosition (QA): an Item whose header is in a session of a trace keeps the header's position in Visual
///     Trace's item list, with and without the event rows, on the Turn and on every chat.message of the turn;
///   - TestRetryItemIdIsTheSpecifiedDerivation (QA): RetryItemId is the first 22 characters of the base64url form of the SHA-256 of
///     the ItemId and /retry, checked against values worked out outside IRIS, so the derivation is the same on every run;
///   - TestBrokenRetryAfterATaintedTurn (QA; DW-112): a turn that is fresh only because the turn before it was tainted still sends
///     its first request under its own ItemId, so that its retry after a broken session is a new Item and not the first request again;
///   - TestRecapFromTurnRows: the recap is written from the Turn rows;
///   - TestToolNoteNamesTheFinishedCalls, TestToolNoteIsTheSameOnEveryAsk, TestToolNoteReadFailureNeverStopsTurn (Story 31.2; AD-30):
///     the turn request's SystemNote names the session's approved tool calls that finished in the turn's window, done or failed,
///     with the time, once and never with their arguments; it is the same on a Busy retry, a broken retry and a fresh turn after a
///     taint; a failed read gives an empty note and the turn still runs; TestToolNoteCarriesPastAFallback: a turn that ended in a
///     fallback closes no window, so its calls are named again in the next turn's note;
///   - TestEveryFallbackReason: the 12 reasons, an error status and an answer of the wrong class give the fallback sentences;
///   - TestDuplicateItemDropped, TestUntrustedItemRefused: an Item is taken once, and only when it is trusted;
///   - TestStaleAnswerDropped: the answer of an instance that a later attempt replaced changes nothing;
///   - TestSendFailuresNeverStrandTurn: a send that fails ends the turn with a fallback, and a failed Notify never stops it.
///   - TestBeginFailureEndsTurn, TestCallbackFailureEndsTurn: a failure inside the class ends the turn with the fallback;
///   - TestItemOfCarriesTheRow, TestSummaryCut: the Item that Decide's input is rendered from, and the Summary of a request;
///   - TestTaintReadFailureStartsFresh: a failed read of the last replied turn starts the next turn fresh;
///   - TestReconcileWithoutProduction: with no production running, Reconcile answers OK;
///   - TestFrameworkErrorStaysAnError: an error that the framework hands OnError with no completion key stays an error;
///   - TestTurnJoinsItsItemSession: a turn that a RunTurns request starts sends its requests and its Outbound in its own Item's
///     trace session, which is its thread (AD-26);
///   - TestFinishingOrder: three queued turns start in the order of the messages, and each is saved done, then its done event is
///     published, then its Outbound goes to Notify, then the RunTurns request for the next queued turn goes to Conversation;
///   - TestDecisionOnChatMessage, TestOutboundCarriesTheDecision (Story 2.6): with the double recording its decisions, chat.message
///     carries the shown decision and the turn's cost (the triage decision while the turn runs and after it is done, the reply
///     decision of a fallback), and the Outbound carries the shown decision's Ref;
///   - TestCheckRowsFromRender, TestCheckKeyWithoutRows, TestStubRenderAddsNothing, TestNoCheckRowsWithoutResults: the check
///     key and rows that Checks.Render makes for a reply's HostData are on the Turn, the Outbound and chat.message, a key with no
///     rows included; the seam is the call of Checks.Render and the real stub adds nothing, and a fallback, bad JSON, HostData
///     with no checks and a failing Render add none;
///   - TestBusyAndBrokenRepliesAreNotChecked: a busy reply and a broken session with check results in their HostData are never
///     given to Render, so the answer that ends the turn is the only one that can leave a key or rows;
///   - TestSourcesCarried, TestSourcesShape, TestSourcesNotOnFallbacks, TestNeverBoth (Story 20.2): the citations and memories of a usable
///     reply's HostData are on the Turn, the Outbound and chat.message, with the check rows still carried; a malformed entry, bad JSON and a
///     wrong shape add nothing and at most 5 of each are kept; a busy, a broken and a fallback reply carry none; and a reply
///     that cites a document never says the none-line, through the real reply guard, while a reply without citations keeps it and carries none;
///   - TestLearnedCarried, TestLearnedShape, TestLearnedNotOnFallbacks, TestLearnedSaid (Story 41.15): the learned entries of a usable reply's HostData are on the Turn (JSON, at most 3, malformed entries dropped) and the
///     Outbound, and the done chat.message carries the entries to show ({memoryRef, fact}) unless the reply already says "I'll remember", in which case the Turn still keeps them; a busy, a broken and a fallback reply carry none;
///   - TestAnswerForNonRunningTurnDropped: an answer for a turn that is no longer running changes nothing, whatever its Attempt;
///   - TestDecideAnswerOfAnotherClassStillRuns: a decide answer that is not a DecisionResponse keeps no DecisionRef and the turn
///     runs on;
///   - TestSourceKeepsToItsBoundaries: Conversation and WebChatIn never call SendRequestSync (AD-6) or render through the catalog
///     (AD-32), and Conversation never asks the allowance (AD-20), which the tests that replace the seams can't see;
///   - TestTurnKeepsItsChannel: a message from another channel keeps its channel through the Turn, both Decide requests, the Outbound
///     and the events, and two such messages with no ClientId are two turns;
///   - TestTaintedFallbackNextFresh: a fallback reply keeps the Tainted flag of the reply, so the next turn is fresh;
///   - TestPublishFailureNeverStopsTurn: a chat.message that cannot be published never stops the turn;
///   - TestDroppedItemIsLogged: each dropped Item is logged as one warning, and a re-delivery is dropped silently;
///   - TestTeardownRemovesProbeLogRows (QA, Story 6.4; DW-105): the teardown's delete (RemoveProbeLog) removes the probe's event log rows
///     written after the mark, and keeps the rows of another class and the probe's row written before the mark.
/// The fixture sessions come from Test.Data.Fixture, and the turns that Conversation makes are adopted after each test, so
/// Fixture.Clean removes them with the events of the streams. The run's number is n from ^OcuTalonTest("ConversationTurns",
/// "n") (never reset); the probe records the calls of the run under ^OcuTalonTest("ConversationProbe", n), and the double's
/// scripts and records are removed for each fixture session. The event log rows that the probe wrote during the run (SourceClass
/// OcuTalon.Test.Core.ConversationProbe, after the log's newest row at the start) are deleted in OnAfterAllTests.
Class OcuTalon.Test.Core.ConversationTurns Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the fixture sessions of the run, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The number of recorded calls that Pump has looked at.
Property Handled As %Integer;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

/// The number of the newest row of the event log when the run began.
Property LogMark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("ConversationTurns", "n"))
	Set ..Refs = ""
	Set ..Sessions = ""
	Set ..LogMark = ..LastLog()
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Set ..Handled = 0
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) = "" Continue
		Set written = ##class(OcuTalon.Test.Core.DecideDouble).Written($Piece(..Sessions, ",", i))
		If written '= "" Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_written
	}
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(OcuTalon.Test.Core.DecideDouble).Clear($Piece(..Sessions, ",", i))
	}
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ..RemoveProbeLog(..LogMark)
	Quit $SYSTEM.Status.OK()
}

/// The teardown's delete (DW-105): the event log rows after the row mark whose SourceClass is the probe's. Rows of any other class,
/// and rows up to the mark, stay. Returns the number of rows deleted.
Method RemoveProbeLog(mark As %Integer) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND SourceClass = ?", mark, "OcuTalon.Test.Core.ConversationProbe")
	Quit result.%ROWCOUNT
}

/// The teardown removes the probe's event log rows (DW-105; AC11): of the rows written after a mark, the two of the probe's class
/// are deleted by RemoveProbeLog and the one of another class stays; a row of the probe's class written before the mark stays. The
/// test counts only the rows that it wrote (this method's, after the log's newest row at its start) and removes them itself (Rule 19).
Method TestTeardownRemovesProbeLogRows()
{
	Set probe = "OcuTalon.Test.Core.ConversationProbe", other = "OcuTalon.Test.Core.ConversationTurns", method = "TestTeardownRemovesProbeLogRows"
	Set start = ..LastLog()
	Do ##class(Ens.Util.Log).LogWarning(probe, method, "zz before the mark")
	Set mark = ..LastLog()
	Do ##class(Ens.Util.Log).LogWarning(probe, method, "zz after the mark 1")
	Do ##class(Ens.Util.Log).LogWarning(probe, method, "zz after the mark 2")
	Do ##class(Ens.Util.Log).LogWarning(other, method, "zz after the mark, another class")
	Do $$$AssertEquals(..CountLog(mark, probe, method), 2, "two probe rows are written after the mark")
	Do $$$AssertTrue(..RemoveProbeLog(mark) >= 2, "the teardown's delete removes them")
	Do $$$AssertEquals(..CountLog(mark, probe, method), 0, "no probe row after the mark remains")
	Do $$$AssertEquals(..CountLog(mark, other, method), 1, "the row of another class after the mark stays")
	Do $$$AssertEquals(..CountLog(start, probe, method), 1, "the probe's row written before the mark stays")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE SourceMethod = ? AND SourceClass IN (?, ?)", method, probe, other)
	// A test can't watch its own teardown, so the two hooks are read: the mark is taken at the start, and the delete runs at the end.
	Do $$$AssertTrue(..ImplementationOf("OnBeforeAllTests") [ "..LogMark = ..LastLog()", "OnBeforeAllTests takes the log mark")
	Do $$$AssertTrue(..ImplementationOf("OnAfterAllTests") [ "..RemoveProbeLog(..LogMark)", "OnAfterAllTests deletes the probe's rows after that mark")
}

/// The code of a method of this class, as its class definition holds it ("" for none).
Method ImplementationOf(name As %String) As %String [ Private ]
{
	Set definition = ##class(%Dictionary.MethodDefinition).%OpenId($ClassName()_"||"_name)
	If '$IsObject(definition) Quit ""
	Do definition.Implementation.Rewind()
	Set code = ""
	While 'definition.Implementation.AtEnd {
		Set code = code_definition.Implementation.Read(30000)
	}
	Quit code
}

/// The number of event log rows after the mark of the source class and method.
Method CountLog(mark As %Integer, class As %String, method As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND SourceClass = ? AND SourceMethod = ?", mark, class, method)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// A message becomes a Turn that is queued, started at once (running, Attempt 1) and, when Decide has answered both requests,
/// done with the message, the reply as it was sent, and both DecisionRefs. The row keeps the channel, FromGuide and ClientId.
Method TestTurnRows()
{
	Set session = ..Session("rows")
	Set text = "zz first line"_$Char(10)_"second line"
	Set item = ..Item(session, text, "zzc"_..Number_"rows")
	Set item.FromGuide = 1
	Set probe = ..NewProbe()
	Do $$$AssertStatusOK(probe.OnRequest(item, .response), "the Item is taken")
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"rows")
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "a Turn was queued")
		Quit
	}
	Do $$$AssertEquals(row.State_"|"_row.Attempt, "running|1", "the head of the queue is started at once")
	Do $$$AssertEquals(row.ItemId, item.ItemId, "the Turn keeps the ItemId")
	Do $$$AssertEquals(row.ClientId_"|"_row.Channel_"|"_row.FromGuide, "zzc"_..Number_"rows|web|1", "and the ClientId, the channel and FromGuide")
	Do $$$AssertEquals(row.Text, text, "and the message as it was written")
	Do $$$AssertTrue(row.CreatedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "and CreatedAt, in UTC to the second: "_row.CreatedAt)
	Do $$$AssertEquals(row.TriageDecisionRef_row.TurnDecisionRef_row.ReplyText_row.ReplyCatalogKey_row.FallbackReason, "", "no decision and no reply yet")
	Set probes(1) = probe
	Do ..Pump(.probes)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"rows")
	Do $$$AssertEquals(row.State_"|"_row.Attempt, "done|1", "the turn is done")
	Do $$$AssertEquals(row.ReplyText, "zz reply to zz first line", "the reply is kept as it was sent")
	Do $$$AssertEquals(row.ReplyCatalogKey_row.FallbackReason, "", "and it is not a fallback")
	Do $$$AssertEquals(row.Tainted, 0, "and not tainted")
	Do $$$AssertTrue(row.TriageDecisionRef ? 22(1AN,1"-",1"_"), "the triage DecisionRef is kept: "_row.TriageDecisionRef)
	Do $$$AssertTrue(row.TurnDecisionRef ? 22(1AN,1"-",1"_"), "the reply DecisionRef is kept: "_row.TurnDecisionRef)
	Do $$$AssertTrue(row.TriageDecisionRef '= row.TurnDecisionRef, "and they are two decisions")
	Do $$$AssertEquals(..Turns(session).Count(), 1, "the session has the one Turn")
}

/// Decide gets a decide request and then a turn request. Both carry provenance user, the ItemId, the Summary (the first
/// line), the owner, the TraceRef, the channel and the thread (ThreadSessionId is the session of the instance), and the turn
/// request continues the conversation. Both were sent in the trace session of the turn. One Outbound goes to Notify.
Method TestDecideThenTurn()
{
	Set session = ..Session("decide")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set item = ..Item(session, "  zz what is on my list"_$Char(10)_"and more", "zzc"_..Number_"decide")
	Set probe = ..NewProbe()
	Set probe.%SessionId = 4242
	Do probe.OnRequest(item, .response)
	Set probes(1) = probe
	Do ..Pump(.probes)
	Set decides = ..Sent("Decide")
	Do $$$AssertEquals($ListLength(decides), 2, "Decide gets two requests")
	Do $$$AssertEquals(..Call($List(decides, 1), "kind")_"|"_..Call($List(decides, 2), "kind"), "decide|turn", "decide first, then turn")
	Set render = ##class(OcuTalon.Agent.Input).Render(..Item(session, item.Text, item.ClientId, item.ItemId))
	Set renderStart = ##class(OcuTalon.Agent.Input).Render(..Item(session, item.Text, item.ClientId, item.ItemId), "", {"sessionStart": 1})
	For i = 1:1:2 {
		Set n = $List(decides, i)
		Set kind = ..Call(n, "kind")
		Do $$$AssertEquals(..Call(n, "provenance"), "user", kind_": provenance user")
		Do $$$AssertEquals(..Call(n, "itemId"), item.ItemId, kind_": the ItemId")
		Do $$$AssertEquals(..Call(n, "summary"), "zz what is on my list", kind_": the Summary is the first line")
		Do $$$AssertEquals(..Call(n, "ownerRef"), session, kind_": the owner is the session")
		Do $$$AssertEquals(..Call(n, "traceRef"), trace, kind_": the TraceRef")
		Do $$$AssertEquals(..Call(n, "channel"), "web", kind_": the channel")
		Do $$$AssertEquals(..Call(n, "threadSessionId"), 4242, kind_": ThreadSessionId is the session of the instance")
		Do $$$AssertEquals(..Call(n, "sessionId"), 4242, kind_": sent in that trace session")
		Do $$$AssertEquals(..Call(n, "superSession"), trace, kind_": and under the session's TraceRef")
		Do $$$AssertEquals(..Call(n, "input"), $Select(kind = "turn": renderStart, 1: render), kind_": the input is what Agent.Input renders (the turn of a session start with sessionStart)")
		Do $$$AssertEquals(..Call(n, "required"), 1, kind_": with an answer required")
	}
	Do $$$AssertEquals(..Call($List(decides, 1), "sessionMode"), "", "the decide request names no session mode")
	Do $$$AssertEquals(..Call($List(decides, 2), "sessionMode")_"|"_..Call($List(decides, 2), "seedText"), "continue|", "the turn request continues the conversation")
	Set sent = ..Sent("Notify")
	Do $$$AssertEquals($ListLength(sent), 1, "one Outbound goes to Notify")
	Set n = $List(sent, 1)
	Do $$$AssertEquals(..Call(n, "class"), "OcuTalon.Msg.Outbound", "it is an Outbound")
	Do $$$AssertEquals(..Call(n, "sessionRef")_"|"_..Call(n, "originChannel"), session_"|web", "for the session, with the turn's channel as the origin")
	Do $$$AssertEquals(..Call(n, "text"), "zz reply to zz what is on my list", "carrying the reply as sent")
	Do $$$AssertEquals(..Call(n, "catalogKey")_..Call(n, "slots"), "", "and no catalog key")
	Do $$$AssertEquals(..Call(n, "required"), 0, "with no answer required")
	Do $$$AssertEquals($ListLength(..Sent("Conversation")), 0, "no RunTurns goes to Conversation: no turn is queued")
}

/// chat.message is published when the turn is queued, when the decision lands and when the reply lands, each the full view
/// of the row at that stage: queued with the text and no reply, running with the same, done with the reply as sent.
Method TestStagesPublished()
{
	Set session = ..Session("stages")
	Set item = ..Item(session, "zz stages", "zzc"_..Number_"stages")
	Set probe = ..NewProbe()
	Do probe.OnRequest(item, .response)
	Set events = ..ChatEvents(session)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(events), "queued", "one event when the Item is taken, with the state queued")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"stages").State, "running", "although the row is already running")
	Do $$$AssertEquals(probe.Deliver(1), 1, "the decision answer arrives")
	Set events = ..ChatEvents(session)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(events), "queued,running", "the second event is published when the decision lands")
	Do $$$AssertEquals(probe.Deliver(), 1, "the reply arrives")
	Set events = ..ChatEvents(session)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(events), "queued,running,done", "the third is published when the reply lands")
	Set ref = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"stages").Ref
	For i = 0:1:2 {
		Set payload = events.%Get(i).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.clientId_"|"_payload.channel_"|"_payload.text, ref_"|zzc"_..Number_"stages|web|zz stages", "event "_(i + 1)_": the ref, clientId, channel and text")
	}
	Do $$$AssertEquals(events.%Get(0).payload.replyText_"|"_events.%Get(1).payload.replyText, "|", "the first two have no reply")
	Do $$$AssertEquals(events.%Get(2).payload.replyText, "zz reply to zz stages", "the last has the reply as sent")
	Do $$$AssertEquals(events.%Get(2).payload.catalogKey_events.%Get(2).payload.fallbackReason, "", "and no fallback")
}

/// A turn that waits behind another has its events in order: queued when it is saved, running when its decision lands, done
/// when its reply lands, with the first turn's events between them.
Method TestStagesInOrder()
{
	Set session = ..Session("order")
	Set probe = ..NewProbe()
	Do probe.OnRequest(..Item(session, "zz holder", "zzc"_..Number_"orderfirst"), .response)
	Set other = ..NewProbe()
	Do other.OnRequest(..Item(session, "zz waits", "zzc"_..Number_"ordersecond"), .response)
	Set ref = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"ordersecond").Ref
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(..ChatEvents(session, ref)), "queued", "the waiting turn is published as queued")
	Set probes(1) = probe
	Set probes(2) = other
	Do probe.Deliver(1)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(..ChatEvents(session, ref)), "queued", "it stays queued while the first turn runs")
	Do ..Pump(.probes)
	Set events = ..ChatEvents(session, ref)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(events), "queued,running,done", "then it is running when its decision lands and done when its reply lands")
	Do $$$AssertEquals(events.%Get(2).payload.replyText, "zz reply to zz waits", "the last one has the reply as sent")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(..ChatEvents(session)), "queued,queued,running,done,running,done", "the stream holds both queued events, the first turn's other two, and then the second turn's")
}

/// Whatever the attention decision was, the turn request is sent after it and the turn has one reply and one done event: the
/// four outcomes, a fallback, and an error status. The DecisionRef is kept only for a DecisionResponse.
Method TestEveryTriageOutcomeRuns()
{
	Set answers = $ListBuild("tellnow", "act", "ignore", "digest", "fallback:budget", "fallback:no_key", "error")
	Set position = 0
	While $ListNext(answers, position, answer) {
		Set session = ..Session("triage"_$Translate(answer, ":_", "__"))
		Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "decide", $ListBuild(answer))
		Set clientId = "zzc"_..Number_"t"_$Translate(answer, ":_", "__")
		Set probe = ..NewProbe()
		Do probe.OnRequest(..Item(session, "zz triage "_answer, clientId), .response)
		Set probes(1) = probe
		Do ..Pump(.probes)
		Kill probes
		Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId)
		Set label = "after "_answer
		Do $$$AssertEquals(row.State, "done", label_": the turn is done")
		Do $$$AssertEquals($ListLength(..Sent("Decide", "turn")), 1, label_": the turn request was sent")
		Do $$$AssertEquals($ListLength(..SentFor("Notify", session)), 1, label_": one Outbound")
		Do $$$AssertEquals(row.ReplyText, "zz reply to zz triage "_answer, label_": the reply is the model's")
		Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(..ChatEvents(session)), "queued,running,done", label_": the three stages")
		If answer = "error" {
			Do $$$AssertEquals(row.TriageDecisionRef, "", label_": no decision to keep")
		} Else {
			Do $$$AssertTrue(row.TriageDecisionRef ? 22(1AN,1"-",1"_"), label_": the decision is kept")
		}
		Kill ^OcuTalonTest("ConversationProbe", ..Number)
		Set ..Handled = 0
	}
}

/// A message sent while a turn runs is its own turn: it is queued, starts only when the first is done, and carries its own
/// ItemId and Summary, while the first turn's requests carry nothing of it (NFR-6).
Method TestSecondMessageWaits()
{
	Set session = ..Session("mid")
	Set first = ..Item(session, "zz alpha message", "zzc"_..Number_"alpha")
	Set second = ..Item(session, "zz bravo message", "zzc"_..Number_"bravo")
	Set p1 = ..NewProbe()
	Do p1.OnRequest(first, .response)
	Do $$$AssertEquals($ListLength(..Sent("Decide", "decide")), 1, "the first turn's decide request is sent")
	Set p2 = ..NewProbe()
	Do p2.OnRequest(second, .response)
	Set row2 = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"bravo")
	Do $$$AssertEquals(row2.State_"|"_row2.Attempt, "queued|0", "the second message is queued, not started")
	Do $$$AssertEquals($ListLength(..Sent("Decide", "decide")), 1, "and nothing of it has reached Decide")
	Set probes(1) = p1
	Set probes(2) = p2
	Do ..Pump(.probes)
	Set row2 = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"bravo")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"alpha").State_"|"_row2.State, "done|done", "both turns are done")
	Set decides = ..Sent("Decide")
	Do $$$AssertEquals($ListLength(decides), 4, "Decide got four requests")
	Set order = ""
	For i = 1:1:4 {
		Set order = order_$Select(order = "": "", 1: ",")_..Call($List(decides, i), "kind")_":"_$Select(..Call($List(decides, i), "itemId") = first.ItemId: "alpha", 1: "bravo")
	}
	Do $$$AssertEquals(order, "decide:alpha,turn:alpha,decide:bravo,turn:bravo", "the second turn starts after the first is done")
	For i = 1:1:4 {
		Set n = $List(decides, i)
		Set mine = (i <= 2)
		Set label = ..Call(n, "kind")_" of "_$Select(mine: "alpha", 1: "bravo")
		Do $$$AssertEquals(..Call(n, "itemId"), $Select(mine: first.ItemId, 1: second.ItemId), label_": its own ItemId")
		Do $$$AssertEquals(..Call(n, "summary"), $Select(mine: "zz alpha message", 1: "zz bravo message"), label_": its own Summary")
		If mine {
			Set input = ..Call(n, "input")
			Set at = $Find(input, $Parameter("OcuTalon.Agent.Input", "NOTESOPENING"))
			If at Set input = $Piece($Extract(input, at, *), $Char(10, 10), 2, *)
			Do $$$AssertTrue(..Call(n, "summary")_input_..Call(n, "seedText") '[ "bravo", label_": nothing of the second message")
			Do $$$AssertTrue(..Call(n, "itemId") '= second.ItemId, label_": not the second ItemId")
		}
	}
	Set notified = ..Sent("Notify")
	Do $$$AssertEquals($ListLength(notified), 2, "two Outbounds, one for each message")
	Do $$$AssertEquals(..Call($List(notified, 1), "text")_"|"_..Call($List(notified, 2), "text"), "zz reply to zz alpha message|zz reply to zz bravo message", "in the order of the messages")
}

/// Busy waits 3 seconds (a timer) and sends the turn request again, up to 5 times; the sixth Busy is the fallback
/// rate_limited. An error status falls back at once, with no wait.
Method TestBusyRequeues()
{
	Set cases = $ListBuild("busy|1|2|reply", "busy,busy,busy,busy,busy|5|6|reply", "busy,busy,busy,busy,busy,busy|5|6|rate_limited", "error|0|1|unusable")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set answers = $Piece(case, "|", 1)
		Set waits = $Piece(case, "|", 2)
		Set requests = $Piece(case, "|", 3)
		Set expected = $Piece(case, "|", 4)
		Set session = ..Session("busy"_$Length(answers, ",")_$Extract(answers, 1, 1))
		Set label = "after "_answers
		Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "turn", $ListFromString(answers))
		Set clientId = "zzc"_..Number_"b"_$Length(answers, ",")_$Extract(answers, 1, 1)
		Set probe = ..NewProbe()
		Do probe.OnRequest(..Item(session, "zz busy", clientId), .response)
		Set probes(1) = probe
		Do ..Pump(.probes)
		Kill probes
		Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId)
		Do $$$AssertEquals($ListLength(..Sent("wait")), waits, label_": waits")
		Do $$$AssertEquals($ListLength(..Sent("Decide", "turn")), requests, label_": turn requests")
		For i = 1:1:$ListLength(..Sent("wait")) {
			Do $$$AssertEquals(..Call($List(..Sent("wait"), i), "seconds")_"|"_..Call($List(..Sent("wait"), i), "key"), "3|busy", label_": wait "_i_" is 3 seconds with the key busy")
		}
		Do $$$AssertEquals(row.State, "done", label_": the turn is done")
		If expected = "reply" {
			Do $$$AssertEquals(row.ReplyText, "zz reply to zz busy", label_": the reply as sent")
			Do $$$AssertEquals(row.ReplyCatalogKey, "", label_": not a fallback")
		} Else {
			Do $$$AssertEquals(row.ReplyCatalogKey_"|"_row.FallbackReason_"|"_row.ReplyText, "conversation.turnFallback|"_expected_"|", label_": the fallback "_expected)
		}
		Do $$$AssertEquals($ListLength(..Sent("Notify")), 1, label_": one Outbound")
		Kill ^OcuTalonTest("ConversationProbe", ..Number)
		Set ..Handled = 0
	}
}

/// SessionBroken: the turn request is sent once more, fresh, with the recap that code wrote from the earlier turns. A second
/// SessionBroken is the fallback with the reply's reason.
Method TestBrokenRetriedFresh()
{
	Set session = ..Session("broken")
	Set probe = ..NewProbe()
	Do probe.OnRequest(..Item(session, "zz earlier question", "zzc"_..Number_"brokenfirst"), .response)
	Set probes(1) = probe
	Do ..Pump(.probes)
	Kill probes
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Set ..Handled = 0
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "turn", $ListBuild("broken", "reply"))
	Set probe = ..NewProbe()
	Do probe.OnRequest(..Item(session, "zz the question", "zzc"_..Number_"brokensecond"), .response)
	Set probes(1) = probe
	Do ..Pump(.probes)
	Kill probes
	Set turns = ..Sent("Decide", "turn")
	Do $$$AssertEquals($ListLength(turns), 2, "the turn request was sent twice")
	Do $$$AssertEquals(..Call($List(turns, 1), "sessionMode"), "continue", "first it continues the conversation")
	Do $$$AssertEquals(..Call($List(turns, 2), "sessionMode"), "fresh", "then it asks for a fresh session")
	Do $$$AssertEquals(..Call($List(turns, 2), "seedText"), ..Header()_$Char(10)_"User: zz earlier question"_$Char(10)_"OcuTalon: zz reply to zz earlier question", "with the recap of the earlier turn")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"brokensecond").ReplyText, "zz reply to zz the question", "the second answer is the reply")
	Do $$$AssertEquals($ListLength(..Sent("Notify")), 1, "and there is one Outbound")
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Set ..Handled = 0
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "turn", $ListBuild("broken", "broken"))
	Set probe = ..NewProbe()
	Do probe.OnRequest(..Item(session, "zz again", "zzc"_..Number_"brokenthird"), .response)
	Set probes(1) = probe
	Do ..Pump(.probes)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"brokenthird")
	Do $$$AssertEquals($ListLength(..Sent("Decide", "turn")), 2, "a second SessionBroken is not retried again")
	Do $$$AssertEquals(row.ReplyCatalogKey_"|"_row.FallbackReason_"|"_row.ReplyText, "conversation.turnFallback|error|", "it is the fallback with the reply's reason")
}

/// DW-112: with the double recording its decisions, as Decide does (one turn decision per ItemId, so it refuses a second turn
/// request of the same ItemId), a broken session and then a reply: the third Decide call is a turn request, fresh, under
/// RetryItemId of the turn's ItemId, which is a Ref of its own; the turn is done with the reply and keeps its ItemId; its
/// TurnDecisionRef is the third answer's; and there are two turn Decision rows: the turn's own ItemId with the fallback error
/// and the derived one. A second broken answer is still the fallback, and the retry's request carries the derived ItemId again
/// when Decide was busy.
Method TestBrokenRetryIsANewItem()
{
	Set session = ..Session("brokenretry")
	Set double = "OcuTalon.Test.Core.DecideDouble"
	Do $ClassMethod(double, "Record", session, 1)
	Do $ClassMethod(double, "Script", session, "turn", $ListBuild("broken", "reply"))
	Set item = ..Item(session, "zz the question", "zzc"_..Number_"brokenretry")
	Set probe = ..NewProbe()
	Do probe.OnRequest(item, .response)
	Set probes(1) = probe
	Do ..Pump(.probes)
	Kill probes
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"brokenretry")
	Set retry = ##class(OcuTalon.Core.Conversation).RetryItemId(row.ItemId)
	Set decides = ..Sent("Decide")
	Do $$$AssertEquals($ListLength(decides), 3, "Decide gets three requests: the decide, the turn and its retry")
	If $ListLength(decides) '= 3 Quit
	Set third = $List(decides, 3)
	Do $$$AssertEquals(..Call(third, "kind")_"|"_..Call(third, "sessionMode"), "turn|fresh", "the third is a turn request, fresh")
	Do $$$AssertEquals(..Call(third, "itemId"), retry, "under the retry's ItemId")
	Do $$$AssertTrue(retry ? 22(1AN,1"-",1"_"), "which is a Ref: "_retry)
	Do $$$AssertTrue(retry '= row.ItemId, "and not the turn's own")
	Do $$$AssertEquals(..Call($List(decides, 2), "itemId")_"|"_..Call($List(decides, 1), "itemId"), row.ItemId_"|"_row.ItemId, "while the first two carried the turn's ItemId")
	Do $$$AssertEquals(retry, ##class(OcuTalon.Core.Conversation).RetryItemId(row.ItemId), "RetryItemId is the same on every call")
	Do $$$AssertEquals(row.State_"|"_row.ReplyText_"|"_row.ReplyCatalogKey, "done|zz reply to zz the question|", "the turn is done with the reply")
	Do $$$AssertEquals(row.ItemId, item.ItemId, "and keeps its own ItemId")
	Set written = $ClassMethod(double, "Written", session)
	Do $$$AssertEquals($Length(written, ","), 3, "the double wrote three decisions: the triage, the broken attempt and the retry")
	Do $$$AssertEquals(row.TurnDecisionRef, $Piece(written, ",", 3), "the turn's TurnDecisionRef is the third answer's")
	Set broken = ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexOpen(row.ItemId, "turn")
	Set derived = ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexOpen(retry, "turn")
	Do $$$AssertTrue($IsObject(broken) && $IsObject(derived), "there is a turn decision under the turn's ItemId and one under the retry's")
	If '$IsObject(broken) || '$IsObject(derived) Quit
	Do $$$AssertEquals(broken.Fallback_"|"_broken.FallbackReason_"|"_broken.Ref, "1|error|"_$Piece(written, ",", 2), "the broken attempt keeps its row, the fallback error")
	Do $$$AssertEquals(derived.Fallback_"|"_derived.Ref, "0|"_row.TurnDecisionRef, "and the retry has its own")
	Do $$$AssertEquals($ListLength(..Sent("Notify")), 1, "there is one Outbound")

	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Set ..Handled = 0
	Set other = ..Session("brokenbusy")
	Do $ClassMethod(double, "Record", other, 1)
	Do $ClassMethod(double, "Script", other, "turn", $ListBuild("broken", "busy", "reply"))
	Set item = ..Item(other, "zz busy after the retry", "zzc"_..Number_"brokenbusy")
	Set probe = ..NewProbe()
	Do probe.OnRequest(item, .response)
	Set probes(1) = probe
	Do ..Pump(.probes)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(other, "zzc"_..Number_"brokenbusy")
	Set retry = ##class(OcuTalon.Core.Conversation).RetryItemId(row.ItemId)
	Set turns = ..Sent("Decide", "turn")
	Do $$$AssertEquals($ListLength(turns), 3, "a retry that was busy is asked again: three turn requests")
	If $ListLength(turns) '= 3 Quit
	Do $$$AssertEquals(..Call($List(turns, 1), "itemId")_"|"_..Call($List(turns, 2), "itemId")_"|"_..Call($List(turns, 3), "itemId"), row.ItemId_"|"_retry_"|"_retry, "the first under the turn's ItemId, the retry and the ask after its busy answer under the derived one")
	Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz busy after the retry", "the turn is done with the reply")

	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Set ..Handled = 0
	Set twice = ..Session("brokentwice")
	Do $ClassMethod(double, "Record", twice, 1)
	Do $ClassMethod(double, "Script", twice, "turn", $ListBuild("broken", "broken"))
	Set probe = ..NewProbe()
	Do probe.OnRequest(..Item(twice, "zz twice", "zzc"_..Number_"brokentwice"), .response)
	Set probes(1) = probe
	Do ..Pump(.probes)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(twice, "zzc"_..Number_"brokentwice")
	Do $$$AssertEquals(row.ReplyCatalogKey_"|"_row.FallbackReason_"|"_row.ReplyText, "conversation.turnFallback|error|", "a second broken answer is the fallback with the reply's reason")
	Do $$$AssertEquals($ListLength(..Sent("Decide", "turn")), 2, "after one retry only")
}

/// An Item whose header has no ID (so its position in the trace cannot be worked out) is taken all the same: the Turn exists and
/// is queued, both positions are empty, and one warning that starts with LOGPOSITION is logged by Locate.
Method TestPositionFailureNeverStopsTurn()
{
	Set session = ..Session("nopos")
	Set mark = ..LastLog()
	Set probe = ..NewProbe()
	Set probe.%PrimaryRequestHeader = ##class(Ens.MessageHeader).%New()
	Do $$$AssertStatusOK(probe.OnRequest(..Item(session, "zz no position", "zzc"_..Number_"nopos"), .response), "the Item is taken")
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"nopos")
	Do $$$AssertTrue($IsObject(row), "and has a Turn")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(row.TraceHeaderId_"|"_row.TraceItemIndex_"|"_row.TraceItemIndexNoEvents, "||", "with no header ID and no position")
	Set start = ##class(OcuTalon.Core.Conversation).#LOGPOSITION
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Locate", start), 1, "one warning says the position could not be worked out: "_text)
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Locate", start)
}

/// An Item whose header sits in a session of a trace keeps the header's position in Visual Trace's item list. The session holds
/// a header from ZzA to ZzB, an event of ZzB (which is on the diagram once that header is) and then the Item's header, so the Item
/// is the 3rd item with the event row and the 2nd without. The Turn keeps both, and so does every chat.message of the turn. The
/// stand-in headers carry a SuperSession of the test and are removed with their log rows.
Method TestTakeKeepsTheItemsPosition()
{
	Set session = ..Session("position")
	Set super = "zzconv"_..Number_"position"
	Try {
		Set first = ##class(OcuTalon.Test.Data.Fixture).Header(super, "", "2030-05-01 10:00:00.100", "ZzA", "ZzB", .sc)
		Do $$$AssertStatusOK(sc, "a stand-in header ZzA to ZzB starts a session")
		Set item = ##class(OcuTalon.Test.Data.Fixture).Header(super, first, "2030-05-01 10:00:00.300", "WebChatIn", "Conversation", .sc)
		Do $$$AssertStatusOK(sc, "and the Item's stand-in header is in it")
		Set log = ##class(Ens.Util.Log).%New()
		Set log.SessionId = first
		Set log.TimeLogged = "2030-05-01 10:00:00.200"
		Set log.ConfigName = "ZzB"
		Set log.MessageId = first
		Set log.Type = 4
		Set log.Text = "zz event"
		Do $$$AssertStatusOK(log.%Save(), "an event of ZzB between the two headers")
		Set probe = ..NewProbe()
		Set probe.%PrimaryRequestHeader = ##class(Ens.MessageHeader).%OpenId(item)
		Do $$$AssertStatusOK(probe.OnRequest(..Item(session, "zz where am I", "zzc"_..Number_"position"), .response), "the Item is taken")
		Set probes(1) = probe
		Do ..Pump(.probes)
		Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"position")
		Do $$$AssertEquals(row.State, "done", "and the turn runs")
		Do $$$AssertEquals(row.TraceHeaderId_"|"_row.TraceItemIndex_"|"_row.TraceItemIndexNoEvents, item_"|3|2", "the Turn keeps its header and the 3rd place with the event row, the 2nd without")
		Set events = ..ChatEvents(session)
		Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(events), "queued,running,done", "the three stages are published")
		For i = 0:1:events.%Size() - 1 {
			Set payload = events.%Get(i).payload
			Do $$$AssertEquals(payload.traceHeaderId_"|"_payload.traceItemIndex_"|"_payload.traceItemIndexNoEvents, item_"|3|2", payload.state_": chat.message carries the target and both places")
		}
	} Catch exception {
		Do $$$AssertTrue(0, "the test threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages([(super)])
}

/// RetryItemId is the first 22 characters of the base64url form (+/ become -_, no =) of the SHA-256 of the ItemId followed by
/// /retry. The values are worked out outside IRIS (Python's hashlib and base64), among them ones whose base64 form has a + or a /
/// in its first 22 characters, so the derivation is the specified one and the same on every run.
Method TestRetryItemIdIsTheSpecifiedDerivation()
{
	Set expected = $ListBuild("zzitem1", "tOUZ_BAv_nSFoITJIUXOek", "zzitem2", "bXnxIpvgekRAwiau3yaWY1", "zzitem4", "npYm0f6kL-YJEPENhqKbTI", "zzvec5", "uKr35bCzo1_7fqsgU8-0du", "AbCdEfGhIjKlMnOpQrStUv", "8u2XEqVk0OqNUwZuhvqK0u")
	For i = 1:2:$ListLength(expected) {
		Set itemId = $List(expected, i)
		Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).RetryItemId(itemId), $List(expected, i + 1), "the retry of "_itemId)
	}
	Do $$$AssertNotEquals(##class(OcuTalon.Core.Conversation).RetryItemId("zzitem1"), ##class(OcuTalon.Core.Conversation).RetryItemId("zzitem2"), "two ItemIds have two retries")
}

/// DW-112 and a tainted turn: the turn after a tainted reply is fresh, but that is not a retry. Its first request is under the
/// turn's own ItemId; when the provider rejects the history, the retry is under the derived one, a different Item, which the double
/// (recording, as Decide does) accepts. A retry under the same ItemId as the first request would be refused.
Method TestBrokenRetryAfterATaintedTurn()
{
	Set session = ..Session("taintbroken")
	Set double = "OcuTalon.Test.Core.DecideDouble"
	Do $ClassMethod(double, "Record", session, 1)
	Do $ClassMethod(double, "Script", session, "turn", $ListBuild("tainted", "broken", "reply"))
	For i = 1:1:2 {
		Set probe = ..NewProbe()
		Do probe.OnRequest(..Item(session, "zz message "_i, "zzc"_..Number_"taintbroken"_i), .response)
		Kill probes
		Set probes(1) = probe
		Do ..Pump(.probes)
	}
	Set second = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"taintbroken2")
	Set retry = ##class(OcuTalon.Core.Conversation).RetryItemId(second.ItemId)
	Set turns = ..Sent("Decide", "turn")
	Do $$$AssertEquals($ListLength(turns), 3, "three turn requests: the tainted turn's, the next turn's and its retry")
	If $ListLength(turns) '= 3 Quit
	Do $$$AssertEquals(..Call($List(turns, 2), "sessionMode")_"|"_..Call($List(turns, 3), "sessionMode"), "fresh|fresh", "the next turn's request is fresh because of the taint, and so is the retry")
	Do $$$AssertEquals(..Call($List(turns, 2), "itemId"), second.ItemId, "the next turn's first request is under its own ItemId")
	Do $$$AssertEquals(..Call($List(turns, 3), "itemId"), retry, "and its retry under the derived one")
	Do $$$AssertEquals(second.State_"|"_second.ReplyText, "done|zz reply to zz message 2", "the turn is done with the retry's reply")
	Set broken = ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexOpen(second.ItemId, "turn")
	Do $$$AssertEquals($IsObject(broken) && broken.Fallback, 1, "the broken attempt keeps its fallback row under the turn's own ItemId")
}

/// After a tainted reply the next turn is fresh, with a recap of the Turn rows that holds the user's text and the reply as
/// sent and nothing of the tool result; the turn after an untainted one continues.
Method TestTaintedNextFresh()
{
	Set session = ..Session("tainted")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "turn", $ListBuild("tainted", "reply", "reply"))
	For i = 1:1:3 {
		Set probe = ..NewProbe()
		Do probe.OnRequest(..Item(session, "zz message "_i, "zzc"_..Number_"taint"_i), .response)
		Kill probes
		Set probes(1) = probe
		Do ..Pump(.probes)
	}
	Set first = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"taint1")
	Do $$$AssertEquals(first.Tainted, 1, "the tainted reply is marked on its Turn")
	Do $$$AssertEquals(first.ReplyText, "zz reply to zz message 1", "and kept as sent")
	Set turns = ..Sent("Decide", "turn")
	Do $$$AssertEquals($ListLength(turns), 3, "three turn requests")
	Do $$$AssertEquals(..Call($List(turns, 1), "sessionMode"), "continue", "the first turn continues")
	Do $$$AssertEquals(..Call($List(turns, 2), "sessionMode"), "fresh", "the turn after a tainted one is fresh")
	Set seed = ..Call($List(turns, 2), "seedText")
	Do $$$AssertEquals(seed, ..Header()_$Char(10)_"User: zz message 1"_$Char(10)_"OcuTalon: zz reply to zz message 1", "its recap holds the user's text and the reply as sent")
	Do $$$AssertTrue(seed '[ "tool result", "and nothing of the tool result")
	Do $$$AssertEquals(..Call($List(turns, 3), "sessionMode")_"|"_..Call($List(turns, 3), "seedText"), "continue|", "the turn after an untainted one continues")
}

/// The recap is written from the session's done turns before the turn: the latest 20, each side cut at 2,000 characters
/// with the cut mark, a fallback as the no-answer line, and nothing from the turn itself or later ones.
Method TestRecapFromTurnRows()
{
	Set session = ..Session("recap")
	Kill refs
	For i = 1:1:23 {
		Set text = "zz question "_i
		If i = 3 Set text = $Translate($Justify("", 2100), " ", "q")
		Set refs(i) = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:"_$Extract(100 + i, 2, 3)_"Z", $Select(i = 22: "running", i = 23: "queued", 1: "done"), text, "zzc"_..Number_"r"_i)
		Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(refs(i))
		If i = 5 {
			Set row.ReplyCatalogKey = "conversation.turnFallback"
			Set row.FallbackReason = "timeout"
		} ElseIf i = 4 {
			Set row.ReplyText = $Translate($Justify("", 2001), " ", "r")
		} Else {
			Set row.ReplyText = "zz answer "_i
		}
		Set row.TurnDecisionRef = "zzdecision"
		Do row.%Save()
	}
	Set recap = ##class(OcuTalon.Core.Conversation).Recap(session, refs(22))
	Set lines = $ListFromString(recap, $Char(10))
	Do $$$AssertEquals($ListLength(lines), 41, "the header and 20 turns of two lines")
	Do $$$AssertEquals($List(lines, 1), ..Header(), "the header")
	Do $$$AssertEquals($List(lines, 2), "User: zz question 2", "the 20 latest done turns before the current one start at the second")
	Do $$$AssertEquals($List(lines, 3), "OcuTalon: zz answer 2", "each reply as sent")
	Do $$$AssertEquals($List(lines, 40), "User: zz question 21", "and end with the last done turn")
	Do $$$AssertEquals($List(lines, 41), "OcuTalon: zz answer 21", "with its reply")
	Do $$$AssertEquals($List(lines, 4), "User: "_$Translate($Justify("", 1999), " ", "q")_$Char(8230), "a user text of 2,100 characters is cut to 2,000 with the cut mark")
	Do $$$AssertEquals($List(lines, 7), "OcuTalon: "_$Translate($Justify("", 1999), " ", "r")_$Char(8230), "and so is a reply of 2,001 characters")
	Do $$$AssertEquals($List(lines, 9), "OcuTalon: (OcuTalon couldn't answer this message.)", "a fallback has the no-answer line")
	Do $$$AssertTrue(recap '[ "question 22", "the current turn is not in it")
	Do $$$AssertTrue(recap '[ "question 23", "nor is a later one")
	Do $$$AssertTrue(recap '[ ("question 1"_$Char(10)), "nor is the turn before the latest 20")
	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).Recap(session, refs(1)), "", "a first turn has no recap")
	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).Recap(session, "zzunknown"), recap, "a turn that is not found leaves every done turn before it: the same latest 20")
	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).Recap("", refs(22)), "", "an empty session has none")

	Set tool = ..Session("recaptool")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(tool, "turn", $ListBuild("tainted"))
	Set probe = ..NewProbe()
	Do probe.OnRequest(..Item(tool, "zz tool question", "zzc"_..Number_"recaptool"), .response)
	Set probes(1) = probe
	Do ..Pump(.probes)
	Set next = ##class(OcuTalon.Test.Data.Fixture).Turn(tool, "2999-01-01T00:00:00Z", "queued", "zz next question", "zzc"_..Number_"recapnext")
	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).Recap(tool, next), ..Header()_$Char(10)_"User: zz tool question"_$Char(10)_"OcuTalon: zz reply to zz tool question", "the recap after a tainted reply holds the user's text and the reply as sent, and nothing of the tool result (HostData)")
}

/// The turn request's SystemNote (AD-30): one line for each approved tool call of the session that finished in the turn's window
/// (the previous Turn's CreatedAt, this Turn's CreatedAt] on FinishedAt, oldest first, with its tool, done (State done) or failed
/// (State failed, Result failed or interrupted) and its time in the instance zone. Another session's call, an instance call, a fix
/// request, a call with no FinishedAt, a call before the window, on its lower bound or after its upper bound is not in it, and nothing
/// of a call's arguments is. Every finished call is in exactly one turn's note (ToolNote of each turn of the session). The decide
/// request carries no note, and a turn with no call in its window has an empty one.
Method TestToolNoteNamesTheFinishedCalls()
{
	Set session = ..Session("toolnote")
	Set other = ..Session("toolnoteother")
	Set p1 = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2026-01-01T10:00:00Z", "done", "zz first", "zzc"_..Number_"tn1")
	Set p2 = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2026-01-01T11:00:00Z", "done", "zz second", "zzc"_..Number_"tn2")
	// The state is the one Core.Allowance records for a refused message (Conversation may not reference Allowance, so it holds the word):
	// if Allowance ever renames it, this turn is no longer refused to ToolNote and the note below goes red.
	Do ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2026-01-01T11:40:00Z", $Parameter("OcuTalon.Core.Allowance", "REFUSED"), "zz turned away", "zzc"_..Number_"tnr")
	Set live = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2026-01-01T12:00:00Z", "queued", "zz third", "zzc"_..Number_"tn3")
	Do ..Finished(session, "done", "2026-01-01T09:00:00Z", "zz_early")
	Do ..Finished(session, "done", "2026-01-01T10:00:00Z", "zz_on_first")
	Do ..Finished(session, "done", "2026-01-01T10:30:00Z", "zz_middle")
	Do ..Finished(session, "failed", "2026-01-01T11:00:00Z", "zz_on_second")
	Do ..Finished(session, "done", "2026-01-01T11:30:00Z", "zz_send")
	Do ..Finished(session, "done", "2026-01-01T11:35:00Z", "zz_{time}x")
	Do ..Finished(session, "failed", "2026-01-01T11:45:00Z", "zz_boom", "failed")
	Do ..Finished(session, "failed", "2026-01-01T12:00:00Z", "zz_cut", "interrupted")
	Do ..Finished(session, "done", "2026-01-01T12:00:01Z", "zz_later")
	Do ..Finished(other, "done", "2026-01-01T11:30:00Z", "zz_theirs")
	Do ..Finished("instance", "done", "2026-01-01T11:30:00Z", "zz_instance")
	Do ..Kept(##class(OcuTalon.Test.Data.Fixture).Approval(session, , "done", , {"Kind": "fix", "Result": "done", "FinishedAt": "2026-01-01T11:30:00Z"}))
	Do ..Kept(##class(OcuTalon.Test.Data.Fixture).Approval(session, , "executing", , {"Kind": "tool_call", "ToolName": "zz_running", "ToolArguments": (..Arguments())}))
	Set run = ##class(OcuTalon.Core.Msg.RunTurns).%New()
	Set run.SessionRef = session
	Set probe = ..NewProbe()
	Do $$$AssertStatusOK(probe.OnRequest(run, .response), "a RunTurns request starts the third turn")
	Set probes(1) = probe
	Do ..Pump(.probes)
	Do $$$AssertEquals(##class(OcuTalon.Data.Turn).RefIndexOpen(live).State, "done", "the turn is done")
	Set notes = ..Notes(session, "turn")
	Do $$$AssertEquals($ListLength(notes), 1, "one turn request")
	Set now = "2026-01-01T12:00:00Z"
	Set expected = ..NoteOf($ListBuild("- zz_send: done at "_..At("2026-01-01T11:30:00Z", now), "- zz_{time}x: done at "_..At("2026-01-01T11:35:00Z", now), "- zz_boom: failed at "_..At("2026-01-01T11:45:00Z", now), "- zz_cut: failed at "_..At("2026-01-01T12:00:00Z", now)))
	Do $$$AssertEquals($List(notes, 1), expected, "its note names the four calls that finished in the window, oldest first: the upper bound is in, the lower one is not, a refused turn between opens no window of its own, and a tool name that holds {time} is written as it is")
	Do $$$AssertTrue($List(notes, 1) '[ "zzSECRETARGS", "and holds no tool arguments")
	Do $$$AssertEquals($List(..Notes(session, "decide"), 1), "", "the decide request carries no note")

	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).ToolNote(##class(OcuTalon.Data.Turn).RefIndexOpen(p1)), ..NoteOf($ListBuild("- zz_early: done at "_..At("2026-01-01T09:00:00Z", "2026-01-01T10:00:00Z"), "- zz_on_first: done at "_..At("2026-01-01T10:00:00Z", "2026-01-01T10:00:00Z"))), "the first turn's window has no lower bound, and a call on its upper bound is in it")
	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).ToolNote(##class(OcuTalon.Data.Turn).RefIndexOpen(p2)), ..NoteOf($ListBuild("- zz_middle: done at "_..At("2026-01-01T10:30:00Z", "2026-01-01T11:00:00Z"), "- zz_on_second: failed at "_..At("2026-01-01T11:00:00Z", "2026-01-01T11:00:00Z"))), "the second turn's note holds the calls after the first turn's CreatedAt, up to its own")
	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).ToolNote(##class(OcuTalon.Data.Turn).RefIndexOpen(live)), $List(notes, 1), "a turn's note is the same when it is worked out again")

	Set empty = ..Session("toolnoteempty")
	Do ##class(OcuTalon.Test.Data.Fixture).Turn(empty, "2026-01-01T12:00:00Z", "queued", "zz nothing", "zzc"_..Number_"tn4")
	Set run.SessionRef = empty
	Set probe = ..NewProbe()
	Do probe.OnRequest(run, .response)
	Kill probes
	Set probes(1) = probe
	Do ..Pump(.probes)
	Do $$$AssertEquals($List(..Notes(empty, "turn"), 1), "", "a turn with no finished call in its window has an empty note")
}

/// The note is the same each time Ask runs for the turn: on a Busy answer's second request (the turn continues), on the request
/// after a broken session (fresh, with the recap) and on a turn that is fresh because the turn before it was tainted.
Method TestToolNoteIsTheSameOnEveryAsk()
{
	Set cases = $ListBuild("continue|busy,reply|2", "fresh after broken|broken,reply|2", "fresh after taint|reply|1")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $Piece(case, "|", 1)
		Set session = ..Session("sameask"_position)
		Set previous = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2026-01-01T10:00:00Z", "done", "zz earlier", "zzc"_..Number_"sa"_position_"p")
		If $Piece(case, "|", 1) = "fresh after taint" {
			Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(previous)
			Set row.Tainted = 1
			Set row.TurnDecisionRef = "zzdecision"
			Do row.%Save()
		}
		Do ..Finished(session, "done", "2026-01-01T11:00:00Z", "zz_once")
		Do ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2026-01-01T12:00:00Z", "queued", "zz now", "zzc"_..Number_"sa"_position_"n")
		Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "turn", $ListFromString($Piece(case, "|", 2), ","))
		Set run = ##class(OcuTalon.Core.Msg.RunTurns).%New()
		Set run.SessionRef = session
		Set probe = ..NewProbe()
		Do probe.OnRequest(run, .response)
		Kill probes
		Set probes(1) = probe
		Do ..Pump(.probes)
		Set notes = ..Notes(session, "turn")
		Do $$$AssertEquals($ListLength(notes), $Piece(case, "|", 3), label_": the turn request is asked "_$Piece(case, "|", 3)_" time(s)")
		Set expected = ..NoteOf($ListBuild("- zz_once: done at "_..At("2026-01-01T11:00:00Z", "2026-01-01T12:00:00Z")))
		For i = 1:1:$ListLength(notes) {
			Do $$$AssertEquals($List(notes, i), expected, label_": request "_i_" carries the note")
		}
		Set turns = ..Sent("Decide", "turn")
		Do $$$AssertEquals(..Call($List(turns, $ListLength(turns)), "sessionMode"), $Select($Piece(case, "|", 1) = "continue": "continue", 1: "fresh"), label_": the last request is "_$Select($Piece(case, "|", 1) = "continue": "a continue", 1: "a fresh")_" turn")
	}
}

/// A note that cannot be worked out never stops the turn: the read of the finished calls fails (the turn has no CreatedAt, so its
/// window has no end), the error is logged by ToolNote, the note is empty and the turn is done with its reply.
Method TestToolNoteReadFailureNeverStopsTurn()
{
	Set session = ..Session("toolnotefail")
	Do ..Finished(session, "done", "2026-01-01T11:00:00Z", "zz_unread")
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "", "queued", "zz no window", "zzc"_..Number_"tnf")
	Set mark = ..LastLog()
	Set run = ##class(OcuTalon.Core.Msg.RunTurns).%New()
	Set run.SessionRef = session
	Set probe = ..NewProbe()
	Do probe.OnRequest(run, .response)
	Set probes(1) = probe
	Do ..Pump(.probes)
	Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(ref)
	Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz no window", "the turn is done with its reply")
	Do $$$AssertEquals($List(..Notes(session, "turn"), 1), "", "the note is empty")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND SourceMethod = ?", mark, "ToolNote")
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "and the failed read is logged once")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND SourceMethod = ?", mark, "ToolNote")

	Set mark = ..LastLog()
	Set stray = ##class(OcuTalon.Data.Turn).%New()
	Set stray.Ref = "zzstray"_..Number
	Set stray.SessionRef = session
	Set stray.CreatedAt = "2030-01-01T00:00:00Z"
	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).ToolNote(stray), "", "a turn that is not among its session's turns gives an empty note")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND SourceMethod = ?", mark, "ToolNote")
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "and that is logged once")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND SourceMethod = ?", mark, "ToolNote")
}

/// A turn that ended in a fallback got no answer from the model, so it closes no window: the calls of its window are named again in
/// the note of the next turn, and a turn after an answered one starts its window there.
Method TestToolNoteCarriesPastAFallback()
{
	Set session = ..Session("toolnotefallback")
	Set f1 = ..Turned(session, "2026-01-01T10:00:00Z", "no_key", "fb1")
	Set a2 = ..Turned(session, "2026-01-01T11:00:00Z", "", "fb2")
	Set f3 = ..Turned(session, "2026-01-01T11:30:00Z", "timeout", "fb3")
	Set a4 = ..Turned(session, "2026-01-01T12:00:00Z", "", "fb4")
	Do ..Finished(session, "done", "2026-01-01T09:30:00Z", "zz_before_fallback")
	Do ..Finished(session, "done", "2026-01-01T10:30:00Z", "zz_after_fallback")
	Do ..Finished(session, "failed", "2026-01-01T11:15:00Z", "zz_after_answer", "failed")
	Do ..Finished(session, "done", "2026-01-01T11:45:00Z", "zz_after_timeout")
	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).ToolNote(##class(OcuTalon.Data.Turn).RefIndexOpen(f1)), ..NoteOf($ListBuild("- zz_before_fallback: done at "_..At("2026-01-01T09:30:00Z", "2026-01-01T10:00:00Z"))), "the turn that fell back was given the call")
	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).ToolNote(##class(OcuTalon.Data.Turn).RefIndexOpen(a2)), ..NoteOf($ListBuild("- zz_before_fallback: done at "_..At("2026-01-01T09:30:00Z", "2026-01-01T11:00:00Z"), "- zz_after_fallback: done at "_..At("2026-01-01T10:30:00Z", "2026-01-01T11:00:00Z"))), "and the next turn names it again, with the call after the fallback")
	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).ToolNote(##class(OcuTalon.Data.Turn).RefIndexOpen(f3)), ..NoteOf($ListBuild("- zz_after_answer: failed at "_..At("2026-01-01T11:15:00Z", "2026-01-01T11:30:00Z"))), "a window starts at the answered turn before it")
	Do $$$AssertEquals(##class(OcuTalon.Core.Conversation).ToolNote(##class(OcuTalon.Data.Turn).RefIndexOpen(a4)), ..NoteOf($ListBuild("- zz_after_answer: failed at "_..At("2026-01-01T11:15:00Z", "2026-01-01T12:00:00Z"), "- zz_after_timeout: done at "_..At("2026-01-01T11:45:00Z", "2026-01-01T12:00:00Z"))), "a timeout fallback closes no window either")
}

/// A done Turn of the session created at the time, with the fallback reason when one is given (FallbackReason and the fallback key).
Method Turned(session As %String, createdAt As %String, reason As %String, tag As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Turn(session, createdAt, "done", "zz "_tag, "zzc"_..Number_tag)
	If reason '= "" {
		Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(ref)
		Set row.FallbackReason = reason
		Set row.ReplyCatalogKey = ##class(OcuTalon.Core.Conversation).#FALLBACKKEY
		Do $$$AssertStatusOK(row.%Save(), "the turn "_tag_" ended in the fallback "_reason)
	}
	Quit ref
}

/// A tool_call request row of the owner that finished at the time: State state, Result done unless result is given, and ToolArguments
/// that a note must never hold. Its Ref joins the Refs that OnAfterAllTests cleans.
Method Finished(owner As %String, state As %String, finishedAt As %String, tool As %String, result As %String = "done") As %String [ Private ]
{
	Quit ..Kept(##class(OcuTalon.Test.Data.Fixture).Approval(owner, , state, , {"Kind": "tool_call", "ToolName": (tool), "Result": (result), "FinishedAt": (finishedAt), "ToolArguments": (..Arguments())}))
}

/// The Ref of a fixture row, which joins the Refs that OnAfterAllTests cleans.
Method Kept(ref As %String) As %String [ Private ]
{
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// The arguments of a seeded tool call: a value that a note must never hold.
Method Arguments() As %String [ Private ]
{
	Quit "{""secret"":""zzSECRETARGS""}"
}

/// The SystemNote of each request of the kind that Decide's double received for the session, as a list, in order.
Method Notes(session As %String, kind As %String) As %List [ Private ]
{
	Set list = ""
	Set seen = ##class(OcuTalon.Test.Core.DecideDouble).Seen(session)
	For i = 0:1:seen.%Size() - 1 {
		Set one = seen.%Get(i)
		If one.kind = kind Set list = list_$ListBuild(one.systemNote)
	}
	Quit list
}

/// The time of a call in the note of a turn created at now, as Time.ForMessage gives it.
Method At(utc As %String, now As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Time).ForMessage(utc, now)
}

/// A note as the spec words it: the first line, then the lines, each after a line feed.
Method NoteOf(lines As %List) As %String [ Private ]
{
	Set note = "Approved tool calls that finished since the last message, as OcuTalon recorded them (not their output):"
	For i = 1:1:$ListLength(lines) Set note = note_$Char(10)_$List(lines, i)
	Quit note
}

/// Each of the 12 fallback reasons, an error status and an answer of the wrong class, as the turn's answer: the Outbound, the
/// row and the last chat.message carry the catalog key conversation.turnFallback and the reason, and the catalog renders the
/// sentence for the web chat. A reason that is not in the enumeration is unusable.
Method TestEveryFallbackReason()
{
	Set oracle = $ListBuild("timeout|the model didn't answer within the time allowed", "empty|the model's reply was empty", "cut_off|the model's reply was cut off", "refusal|the model declined to answer", "error|the model returned an error", "rate_limited|the model was too busy to answer", "budget|this would have gone over the token budget", "too_large|this request would have been too large to send", "daily_cap|today's cost limit has been reached", "no_key|no model key is set", "invalid|the model's reply couldn't be used", "unusable|the model's reply couldn't be used")
	Do $$$AssertEquals($ListLength(oracle), 12, "all 12 reasons are tried")
	Set cases = ""
	Set position = 0
	While $ListNext(oracle, position, pair) {
		Set cases = cases_$ListBuild("fallback:"_$Piece(pair, "|", 1)_"|"_$Piece(pair, "|", 1)_"|"_$Piece(pair, "|", 2))
	}
	Set generic = "the model's reply couldn't be used"
	Set cases = cases_$ListBuild("error|unusable|"_generic, "wrong|unusable|"_generic, "fallback:zzbogus|unusable|"_generic, "fallback:|unusable|"_generic)
	Set position = 0
	While $ListNext(cases, position, case) {
		Set answer = $Piece(case, "|", 1)
		Set reason = $Piece(case, "|", 2)
		Set phrase = $Piece(case, "|", 3)
		Set key = $Translate(answer, ":_", "__")
		Set session = ..Session("fb"_key)
		Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "turn", $ListBuild(answer))
		Set clientId = "zzc"_..Number_"fb"_key
		Set probe = ..NewProbe()
		Do probe.OnRequest(..Item(session, "zz fallback", clientId), .response)
		Set probes(1) = probe
		Do ..Pump(.probes)
		Kill probes
		Set label = "answer '"_answer_"'"
		Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId)
		Do $$$AssertEquals(row.State_"|"_row.ReplyCatalogKey_"|"_row.FallbackReason_"|"_row.ReplyText, "done|conversation.turnFallback|"_reason_"|", label_": the row")
		Set sent = ..SentFor("Notify", session)
		Do $$$AssertEquals($ListLength(sent), 1, label_": one Outbound")
		Set n = $List(sent, 1)
		Do $$$AssertEquals(..Call(n, "catalogKey"), "conversation.turnFallback", label_": the catalog key")
		Do $$$AssertEquals(..Call(n, "slots"), "{""fallbackReason"":"""_reason_"""}", label_": the slot")
		Do $$$AssertEquals(..Call(n, "text"), "", label_": no text of its own")
		Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(..Call(n, "catalogKey"), ..Call(n, "slots"), "web", "2026-10-22T10:00:00Z", 0, .sc)
		Do $$$AssertStatusOK(sc, label_": the catalog renders it")
		Do $$$AssertEquals(text, "I couldn't answer that: "_phrase_". Nothing was changed.", label_": the sentence for the web chat")
		Set events = ..ChatEvents(session)
		Set last = events.%Get(events.%Size() - 1).payload
		Do $$$AssertEquals(last.state_"|"_last.catalogKey_"|"_last.fallbackReason_"|"_last.replyText, "done|conversation.turnFallback|"_reason_"|", label_": the last chat.message")
		Kill ^OcuTalonTest("ConversationProbe", ..Number)
		Set ..Handled = 0
	}
}

/// The same ItemId twice (a re-delivery) makes one Turn; the same ClientId in the same session under a new ItemId (a race past
/// WebChatIn's check) makes no second Turn; another session with that ClientId has its own Turn.
Method TestDuplicateItemDropped()
{
	Set a = ..Session("dupa")
	Set b = ..Session("dupb")
	Set item = ..Item(a, "zz once", "zzc"_..Number_"dup")
	Set probe = ..NewProbe()
	Do $$$AssertStatusOK(probe.OnRequest(item, .response), "the Item is taken")
	Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), "the same Item again is not an error")
	Do $$$AssertEquals(..Turns(a).Count(), 1, "a re-delivered Item makes no second Turn")
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(a, "zz twice", "zzc"_..Number_"dup"), .response), "the same ClientId in a new Item is not an error")
	Do $$$AssertEquals(..Turns(a).Count(), 1, "the same ClientId in the same session makes no second Turn")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnByClient(a, "zzc"_..Number_"dup").Text, "zz once", "the first message stands")
	Do $$$AssertEquals($ListLength(..Sent("Decide", "decide")), 1, "only one turn started")
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(b, "zz other session", "zzc"_..Number_"dup"), .response), "another session sends the same ClientId")
	Do $$$AssertEquals(..Turns(b).Count(), 1, "it has its own Turn")
	Do $$$AssertEquals(..Turns(a).Count(), 1, "and the first session still has one")
}

/// An Item that is not user provenance, or has no ItemId, no text or no Session row, is dropped: the status is OK, no Turn is
/// made, nothing is sent and nothing is published. The warnings that the drops log are removed.
Method TestUntrustedItemRefused()
{
	Set session = ..Session("untrusted")
	Set mark = ..LastLog()
	Set cases = $ListBuild("untrusted provenance", "no ItemId", "no text", "text of spaces", "no session", "unknown session")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set item = ..Item(session, "zz untrusted", "zzc"_..Number_"u"_position)
		If case = "untrusted provenance" Set item.Provenance = "untrusted"
		If case = "no ItemId" Set item.ItemId = ""
		If case = "no text" Set item.Text = ""
		If case = "text of spaces" Set item.Text = "  "_$Char(9)_" "
		If case = "no session" Set item.SessionRef = ""
		If case = "unknown session" Set item.SessionRef = "zzunknownsession"_..Number
		Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), case_": the status is OK")
		Do $$$AssertEquals(..Turns(session).Count(), 0, case_": no Turn is made")
		Do $$$AssertEquals(..Calls(), 0, case_": nothing is sent")
		Do $$$AssertEquals(..ChatEvents(session).%Size(), 0, case_": nothing is published")
	}
	Do $$$AssertStatusNotOK(..NewProbe().OnRequest(##class(Ens.StringRequest).%New("zz"), .response), "a request that is neither an Item nor a RunTurns is an error")
	Do $$$AssertEquals(..Turns(session).Count(), 0, "and changes nothing")
	Do ..RemoveWarnings(mark)
}

/// An answer of an instance whose Attempt was replaced is dropped: a sweep puts the running turn back in its queue, the next
/// instance starts it again, and the first instance's answers change nothing: no event, no request, no Outbound. The turn has
/// one reply, from the second attempt.
Method TestStaleAnswerDropped()
{
	Set session = ..Session("stale")
	Set clientId = "zzc"_..Number_"stale"
	Set first = ..NewProbe()
	Do first.OnRequest(..Item(session, "zz stale", clientId), .response)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId)
	Do $$$AssertEquals(row.State_"|"_row.Attempt, "running|1", "the first instance started the turn")
	Set row.State = "queued"
	Do $$$AssertStatusOK(row.%Save(), "a sweep puts the turn back in its queue")
	Set run = ##class(OcuTalon.Core.Msg.RunTurns).%New()
	Set run.SessionRef = session
	Set second = ..NewProbe()
	Do second.OnRequest(run, .response)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId)
	Do $$$AssertEquals(row.State_"|"_row.Attempt, "running|2", "the second instance started it again")
	Set before = ..Calls()
	Set events = ..ChatEvents(session).%Size()
	Do $$$AssertEquals(first.Deliver(), 1, "the first instance's decision answer arrives")
	Do $$$AssertEquals(..Calls(), before, "and it sends nothing")
	Do $$$AssertEquals(..ChatEvents(session).%Size(), events, "publishes nothing")
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId)
	Do $$$AssertEquals(row.State_"|"_row.Attempt_"|"_row.TriageDecisionRef, "running|2|", "and changes nothing in the row")
	Set probes(1) = second
	Do ..Pump(.probes)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId)
	Do $$$AssertEquals(row.State_"|"_row.Attempt, "done|2", "the second instance finishes the turn")
	Do $$$AssertEquals($ListLength(..SentFor("Notify", session)), 1, "with one Outbound")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(..ChatEvents(session)), "queued,running,done", "and one done event")
	Do $$$AssertEquals($ListLength(..Sent("Decide", "turn")), 1, "and one turn request")
	Do first.OnResponse("", , "", ##class(Ens.StringResponse).%New("zz"), "turn")
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId)
	Do $$$AssertEquals(row.State_"|"_row.Attempt_"|"_row.ReplyText, "done|2|zz reply to zz stale", "an answer that arrives after the turn is done changes nothing")
	Do $$$AssertEquals($ListLength(..SentFor("Notify", session)), 1, "and sends no second Outbound")
}

/// A send that fails ends the turn with the fallback unusable and never leaves it running: Decide not reachable, and Notify
/// not reachable (the turn is still done, with its event and its next turn started).
Method TestSendFailuresNeverStrandTurn()
{
	Set session = ..Session("sendfail")
	Set probe = ..NewProbe()
	Set probe.FailTarget = "Decide"
	Do probe.OnRequest(..Item(session, "zz no decide", "zzc"_..Number_"nodecide"), .response)
	Set probes(1) = probe
	Do ..Pump(.probes)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"nodecide")
	Do $$$AssertEquals(row.State_"|"_row.ReplyCatalogKey_"|"_row.FallbackReason, "done|conversation.turnFallback|unusable", "Decide not reachable: the fallback unusable")
	Do $$$AssertEquals($ListLength(..SentFor("Notify", session)), 1, "with one Outbound")
	Kill probes
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Set ..Handled = 0
	Set probe = ..NewProbe()
	Set probe.FailTarget = "Notify"
	Do probe.OnRequest(..Item(session, "zz no notify", "zzc"_..Number_"nonotify"), .response)
	Set second = ..Item(session, "zz queued behind", "zzc"_..Number_"behind")
	Set other = ..NewProbe()
	Do other.OnRequest(second, .response)
	Set probes(1) = probe
	Set probes(2) = other
	Do ..Pump(.probes)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"nonotify")
	Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz no notify", "Notify not reachable: the turn is still done with its reply")
	Set behind = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"behind")
	Do $$$AssertEquals(behind.State, "done", "and the next turn still ran")
}

/// A failure inside Begin (the trace step throws) ends the turn at once with the fallback unusable, never leaving it running:
/// nothing reaches Decide, one Outbound goes to Notify, and the session's next message runs.
Method TestBeginFailureEndsTurn()
{
	Set session = ..Session("beginfail")
	Set probe = ..NewProbe()
	Set probe.ThrowIn = "join"
	Do $$$AssertStatusOK(probe.OnRequest(..Item(session, "zz begin fails", "zzc"_..Number_"beginfail"), .response), "the Item is taken")
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"beginfail")
	Do $$$AssertEquals(row.State_"|"_row.ReplyCatalogKey_"|"_row.FallbackReason, "done|conversation.turnFallback|unusable", "the turn is done with the fallback unusable")
	Do $$$AssertEquals($ListLength(..Sent("Decide")), 0, "nothing reached Decide")
	Do $$$AssertEquals($ListLength(..SentFor("Notify", session)), 1, "one Outbound went to Notify")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(..ChatEvents(session)), "queued,done", "and the stream holds queued and done")
	Set next = ..NewProbe()
	Do next.OnRequest(..Item(session, "zz after the failure", "zzc"_..Number_"afterfail"), .response)
	Set probes(1) = next
	Do ..Pump(.probes)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"afterfail")
	Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz after the failure", "the session's next message runs")
}

/// A failure inside the handling of an answer (the decision answer's handling throws) ends the turn with the fallback
/// unusable, and the turn request is never sent.
Method TestCallbackFailureEndsTurn()
{
	Set session = ..Session("callbackfail")
	Set probe = ..NewProbe()
	Set probe.ThrowIn = "decided"
	Do probe.OnRequest(..Item(session, "zz callback fails", "zzc"_..Number_"callbackfail"), .response)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"callbackfail")
	Do $$$AssertEquals(row.State, "running", "the turn waits for the decision")
	Do $$$AssertEquals(probe.Deliver(), 1, "the decision answer arrives and its handling throws")
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"callbackfail")
	Do $$$AssertEquals(row.State_"|"_row.ReplyCatalogKey_"|"_row.FallbackReason, "done|conversation.turnFallback|unusable", "the turn is done with the fallback unusable")
	Do $$$AssertEquals($ListLength(..Sent("Decide", "turn")), 0, "no turn request was sent")
	Do $$$AssertEquals($ListLength(..SentFor("Notify", session)), 1, "one Outbound went to Notify")
}

/// The Item that Conversation renders Decide's input from carries what the row holds: the ItemId, the session, the channel,
/// provenance user, the text, FromGuide and the ClientId.
Method TestItemOfCarriesTheRow()
{
	Set session = ..Session("itemof")
	Set item = ..Item(session, "zz round trip"_$Char(10)_"second line", "zzc"_..Number_"itemof")
	Set item.FromGuide = 1
	Set probe = ..NewProbe()
	Do probe.OnRequest(item, .response)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, item.ClientId)
	Set built = probe.ItemFor(row)
	Do $$$AssertEquals(built.ItemId_"|"_built.SessionRef_"|"_built.Channel_"|"_built.Provenance, item.ItemId_"|"_session_"|web|user", "the ids, the channel and provenance user")
	Do $$$AssertEquals(built.Text, item.Text, "the text as it was written")
	Do $$$AssertEquals(built.FromGuide_"|"_built.ClientId, "1|"_item.ClientId, "FromGuide and the ClientId")
}

/// The Summary of a request is the first line of the text without its leading white space, and a line over 80 characters is
/// cut to 79 characters and the cut mark, so that it fits the 80 characters of Request.Summary.
Method TestSummaryCut()
{
	Set conversation = "OcuTalon.Core.Conversation"
	Set mark = $Char(8230)
	Set a80 = $Translate($Justify("", 80), " ", "a")
	Set a79 = $Translate($Justify("", 79), " ", "a")
	Do $$$AssertEquals($ClassMethod(conversation, "Summary", a80), a80, "a first line of 80 characters is kept whole")
	Do $$$AssertEquals($ClassMethod(conversation, "Summary", a80_"b"), a79_mark, "81 characters are cut to 79 and the cut mark")
	Do $$$AssertEquals($Length($ClassMethod(conversation, "Summary", a80_a80_a80)), 80, "a long line is 80 characters with the mark")
	Do $$$AssertEquals($ClassMethod(conversation, "Summary", $Char(10)_"  "_$Char(13)_"zz hello"_$Char(10)_"more"), "zz hello", "leading line breaks and spaces are dropped, and the first line is taken")
	Do $$$AssertEquals($ClassMethod(conversation, "Summary", "zz one"_$Char(13)_"zz two"), "zz one", "a carriage return ends the line")
	Do $$$AssertEquals($ClassMethod(conversation, "Summary", ""), "", "no text, no Summary")
}

/// A read of the last replied turn that fails counts as tainted, so the next turn starts fresh; a session with no replied turn
/// continues.
Method TestTaintReadFailureStartsFresh()
{
	Set probe = ..NewProbe()
	Do $$$AssertEquals(probe.FreshAfter(""), 1, "a read that fails (no session) starts the next turn fresh")
	Set session = ..Session("taintread")
	Do $$$AssertEquals(probe.FreshAfter(session), 0, "a session with no replied turn continues")
}

/// With no production running, Reconcile answers OK (the next start reconciles). Where a production runs (a throwaway), the
/// test is skipped, because Reconcile then sweeps every session.
Method TestReconcileWithoutProduction()
{
	If ##class(Ens.Director).IsProductionRunning() {
		Do $$$AssertSkipped("A production runs in "_$Namespace_": Reconcile then sweeps, which ConversationProduction tests")
		Quit
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Core.Conversation).Reconcile(), "with no production running, Reconcile answers OK")
}

/// An error that the framework hands OnError with no completion key (OnRequest failed, or the framework did) stays an error,
/// so that the framework logs it and ends the instance, and it is not kept as an answer error. An answer's error (its call's
/// key) answers OK and is kept for the OnResponse call that follows.
Method TestFrameworkErrorStaysAnError()
{
	Set probe = ..NewProbe()
	Set error = $SYSTEM.Status.Error(5001, "zz the request failed")
	Set sc = probe.OnError("", , "", error, "")
	Do $$$AssertStatusNotOK(sc, "an error with no completion key stays an error")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorText(sc), $SYSTEM.Status.GetErrorText(error), "the same error")
	Do $$$AssertStatusOK(probe.CallError, "and it is not kept as an answer error")
	Set sc = probe.OnError("", , "", error, "decide")
	Do $$$AssertStatusOK(sc, "an answer's error answers OK")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorText(probe.CallError), $SYSTEM.Status.GetErrorText(error), "and is kept for OnResponse")
}

/// A turn that an instance of another trace session starts (a RunTurns request, as after the turn before it) sends its decide
/// and turn requests and its Outbound in the session of its own Item's header, which is also the requests' ThreadSessionId
/// (AD-26). The Item's header is a stand-in saved by the test and deleted afterwards.
Method TestTurnJoinsItsItemSession()
{
	Set session = ..Session("join")
	Set header = ##class(Ens.MessageHeader).%New()
	Do $$$AssertStatusOK(header.%Save(), "a stand-in Item header is saved")
	Set header.SessionId = header.%Id()
	Do $$$AssertStatusOK(header.%Save(), "in a session of its own")
	Try {
		Set ref = ##class(OcuTalon.Test.Data.Fixture).Turn(session, , "queued", "zz joins its item", "zzc"_..Number_"join")
		Set row = ##class(OcuTalon.Data.Turn).RefIndexOpen(ref)
		Set row.TraceHeaderId = header.%Id()
		Do $$$AssertStatusOK(row.%Save(), "the queued turn's trace target is that header")
		Set probe = ..NewProbe()
		Set probe.%SessionId = header.SessionId + 4242
		Set run = ##class(OcuTalon.Core.Msg.RunTurns).%New()
		Set run.SessionRef = session
		Do $$$AssertStatusOK(probe.OnRequest(run, .response), "a RunTurns request in another trace session starts the turn")
		Set probes(1) = probe
		Do ..Pump(.probes)
		Do $$$AssertEquals(##class(OcuTalon.Data.Turn).RefIndexOpen(ref).State, "done", "the turn is done")
		Set decides = ..Sent("Decide")
		Do $$$AssertEquals($ListLength(decides), 2, "Decide gets the decide and the turn request")
		For i = 1:1:$ListLength(decides) {
			Set n = $List(decides, i)
			Do $$$AssertEquals(..Call(n, "sessionId")_"|"_..Call(n, "threadSessionId"), header.SessionId_"|"_header.SessionId, ..Call(n, "kind")_": sent in the Item's session, which is its thread")
		}
		Set sent = ..SentFor("Notify", session)
		Do $$$AssertEquals($ListLength(sent), 1, "one Outbound goes to Notify")
		If $ListLength(sent) = 1 Do $$$AssertEquals(..Call($List(sent, 1), "sessionId"), header.SessionId, "in the Item's session too")
	} Catch exception {
		Do $$$AssertTrue(0, "the test threw: "_exception.DisplayString())
	}
	Do ##class(Ens.MessageHeader).%DeleteId(header.%Id())
}

/// Three messages in a row are three turns that start one after another, in the order of the messages, and each finishes in
/// AD-30's order. The probe records, at each send, the state of the instance's Turn and how many done events of it the stream
/// holds: the turn request goes out while the turn runs with no done event; the Outbound goes out with the row saved done and
/// its done event published; the RunTurns request for the next queued turn goes out after the Outbound.
Method TestFinishingOrder()
{
	Set session = ..Session("finishorder")
	Kill itemIds
	For i = 1:1:3 {
		Set item = ..Item(session, "zz finishing "_i, "zzc"_..Number_"finish"_i)
		Set itemIds(i) = item.ItemId
		Set probe = ..NewProbe()
		Do probe.OnRequest(item, .response)
		Set probes(i) = probe
	}
	Do ..Pump(.probes)
	Set turns = ..Sent("Decide", "turn")
	Do $$$AssertEquals($ListLength(turns), 3, "three turn requests")
	Set order = ""
	For i = 1:1:3 {
		Set n = $List(turns, i)
		Set order = order_$Select(order = "": "", 1: ",")_$Select(..Call(n, "itemId") = itemIds(1): 1, ..Call(n, "itemId") = itemIds(2): 2, ..Call(n, "itemId") = itemIds(3): 3, 1: "?")
		Do $$$AssertEquals(..Call(n, "turnState")_"|"_..Call(n, "doneEvents"), "running|0", "turn request "_i_" goes out while its turn runs, with no done event")
	}
	Do $$$AssertEquals(order, "1,2,3", "the turns start in the order of the messages")
	Set notices = ..Sent("Notify")
	Set runs = ..Sent("Conversation")
	Do $$$AssertEquals($ListLength(notices)_"|"_$ListLength(runs), "3|2", "three Outbounds, and a RunTurns request after each of the first two turns")
	For i = 1:1:3 {
		Set notice = $List(notices, i)
		Do $$$AssertEquals(..Call(notice, "turnState")_"|"_..Call(notice, "doneEvents"), "done|1", "Outbound "_i_" goes out with the row saved done and its done event published")
	}
	For i = 1:1:2 {
		Set run = $List(runs, i)
		Do $$$AssertEquals(..Call(run, "class")_"|"_..Call(run, "sessionRef"), "OcuTalon.Core.Msg.RunTurns|"_session, "RunTurns request "_i_" is for the session")
		Do $$$AssertTrue(run > $List(notices, i), "and goes out after Outbound "_i)
		Do $$$AssertEquals(..Call(run, "turnState")_"|"_..Call(run, "doneEvents"), "done|1", "once its turn is done and its event published")
	}
}

/// An answer for a turn that is not running changes nothing, whatever its Attempt: the old instance's decision answer
/// arrives after a sweep put the turn back in its queue (same Attempt, state queued), and a duplicate of the reply arrives for
/// a turn that is already done (the instance's own Attempt, state done).
Method TestAnswerForNonRunningTurnDropped()
{
	Set session = ..Session("notrunning")
	Set clientId = "zzc"_..Number_"notrunning"
	Set old = ..NewProbe()
	Do old.OnRequest(..Item(session, "zz queued again", clientId), .response)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId)
	Do $$$AssertEquals(row.State_"|"_row.Attempt, "running|1", "the instance started the turn")
	Set row.State = "queued"
	Do $$$AssertStatusOK(row.%Save(), "a sweep puts the turn back in its queue before another instance starts it")
	Set calls = ..Calls()
	Set events = ..ChatEvents(session).%Size()
	Do $$$AssertEquals(old.Deliver(), 1, "the old instance's decision answer arrives")
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId)
	Do $$$AssertEquals(row.State_"|"_row.Attempt_"|"_row.TriageDecisionRef, "queued|1|", "the queued turn is not changed")
	Do $$$AssertEquals(..Calls(), calls, "nothing is sent")
	Do $$$AssertEquals(..ChatEvents(session).%Size(), events, "and nothing is published")

	Set other = ..Session("lateanswer")
	Set finished = ..NewProbe()
	Do finished.OnRequest(..Item(other, "zz answered once", "zzc"_..Number_"lateanswer"), .response)
	Set probes(1) = finished
	Do ..Pump(.probes)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(other, "zzc"_..Number_"lateanswer")
	Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz answered once", "another turn is done")
	Set calls = ..Calls()
	Set events = ..ChatEvents(other).%Size()
	Set late = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set late.Text = "zz late duplicate"
	Set late.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do finished.OnResponse("", , "", late, "turn")
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(other, "zzc"_..Number_"lateanswer")
	Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz answered once", "a duplicate reply for the done turn leaves its reply as it was")
	Do $$$AssertTrue(row.TurnDecisionRef '= late.DecisionRef, "and its reply decision")
	Do $$$AssertEquals(..Calls(), calls, "it sends no second Outbound")
	Do $$$AssertEquals(..ChatEvents(other).%Size(), events, "and publishes no second done event")
}

/// A decide answer that is not a DecisionResponse, a string response or a Reply, keeps no DecisionRef, and the turn still gets
/// its turn request, one reply and its three stages.
Method TestDecideAnswerOfAnotherClassStillRuns()
{
	For answer = "wrong", "reply" {
		Set session = ..Session("decideclass"_answer)
		Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "decide", $ListBuild(answer))
		Set clientId = "zzc"_..Number_"dc"_answer
		Set probe = ..NewProbe()
		Do probe.OnRequest(..Item(session, "zz decide class", clientId), .response)
		Kill probes
		Set probes(1) = probe
		Do ..Pump(.probes)
		Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId)
		Set label = "a decide answer '"_answer_"'"
		Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz decide class", label_": the turn is done with the model's reply")
		Do $$$AssertEquals(row.TriageDecisionRef, "", label_": no decision is kept")
		Do $$$AssertEquals($ListLength(..Sent("Decide", "turn")), 1, label_": the turn request is sent")
		Do $$$AssertEquals($ListLength(..SentFor("Notify", session)), 1, label_": one Outbound")
		Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(..ChatEvents(session)), "queued,running,done", label_": the three stages")
		Kill ^OcuTalonTest("ConversationProbe", ..Number)
		Set ..Handled = 0
	}
}

/// The source of every method of Conversation and WebChatIn keeps to the boundaries that the tests, which replace the send seam
/// and the allowance, can't see: neither calls SendRequestSync, so a slow model call never blocks a process (AD-6); neither
/// renders text through the catalog, because a producer sends the key and its slots (AD-32); and Conversation never calls the
/// allowance, which WebChatIn alone asks (AD-20). The scan is only trusted if it finds each class's asynchronous send.
Method TestSourceKeepsToItsBoundaries()
{
	Set rules = $ListBuild("OcuTalon.Core.Conversation|SendRequestSync", "OcuTalon.Core.Conversation|OcuTalon.Msg.Catalog", "OcuTalon.Core.Conversation|OcuTalon.Core.Allowance", "OcuTalon.Channel.WebChat.In|SendRequestSync", "OcuTalon.Channel.WebChat.In|OcuTalon.Msg.Catalog")
	For class = "OcuTalon.Core.Conversation", "OcuTalon.Channel.WebChat.In" {
		Kill found
		Set async = 0
		Set definition = ##class(%Dictionary.ClassDefinition).%OpenId(class)
		If '$IsObject(definition) {
			Do $$$AssertTrue(0, class_" has a class definition")
			Continue
		}
		For i = 1:1:definition.Methods.Count() {
			Set method = definition.Methods.GetAt(i)
			Do method.Implementation.Rewind()
			While 'method.Implementation.AtEnd {
				Set code = method.Implementation.Read(30000)
				If code [ "SendRequestAsync" Set async = async + 1
				Set position = 0
				While $ListNext(rules, position, rule) {
					If ($Piece(rule, "|", 1) = class) && (code [ $Piece(rule, "|", 2)) Set found($Piece(rule, "|", 2)) = $Get(found($Piece(rule, "|", 2)))_" "_method.Name
				}
			}
		}
		Do $$$AssertTrue(async > 0, class_": the scan sees its asynchronous send")
		Set position = 0
		While $ListNext(rules, position, rule) {
			If $Piece(rule, "|", 1) '= class Continue
			Do $$$AssertEquals($Get(found($Piece(rule, "|", 2))), "", class_": no method uses "_$Piece(rule, "|", 2))
		}
	}
}

/// A message that comes from another channel (telegram, with no ClientId) keeps its channel everywhere: the Turn, both Decide
/// requests, the Outbound's origin and every event; and a second such message is its own turn, because an empty ClientId is
/// never a duplicate.
Method TestTurnKeepsItsChannel()
{
	Set session = ..Session("channel")
	Set first = ..Item(session, "zz from telegram one", "")
	Set first.Channel = "telegram"
	Set second = ..Item(session, "zz from telegram two", "")
	Set second.Channel = "telegram"
	Set p1 = ..NewProbe()
	Do p1.OnRequest(first, .response)
	Set p2 = ..NewProbe()
	Do p2.OnRequest(second, .response)
	Do $$$AssertEquals(..Turns(session).Count(), 2, "two messages with no ClientId are two turns")
	Set probes(1) = p1
	Set probes(2) = p2
	Do ..Pump(.probes)
	Set rows = ..Turns(session)
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		Do $$$AssertEquals(row.State_"|"_row.Channel_"|"_row.ClientId, "done|telegram|", "turn "_i_": done, on the telegram channel, with no ClientId")
	}
	Set decides = ..Sent("Decide")
	Do $$$AssertEquals($ListLength(decides), 4, "four requests reach Decide")
	For i = 1:1:$ListLength(decides) {
		Do $$$AssertEquals(..Call($List(decides, i), "channel"), "telegram", "request "_i_" names the telegram channel")
	}
	Set notices = ..SentFor("Notify", session)
	Do $$$AssertEquals($ListLength(notices), 2, "two Outbounds")
	For i = 1:1:$ListLength(notices) {
		Do $$$AssertEquals(..Call($List(notices, i), "originChannel"), "telegram", "Outbound "_i_" has the telegram origin")
	}
	Set events = ..ChatEvents(session)
	Do $$$AssertEquals(events.%Size(), 6, "six events")
	For i = 0:1:events.%Size() - 1 {
		Do $$$AssertEquals(events.%Get(i).payload.channel, "telegram", "event "_(i + 1)_" shows the telegram channel")
	}
}

/// A fallback reply that carries Tainted (a tool ran, then the model's reply was cut off) is marked tainted like any reply, so the
/// next turn starts fresh with a recap that shows the fallback as the no-answer line and nothing of the tool result.
Method TestTaintedFallbackNextFresh()
{
	Set session = ..Session("taintedfallback")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "turn", $ListBuild("taintedfallback:cut_off", "reply"))
	For i = 1:1:2 {
		Set probe = ..NewProbe()
		Do probe.OnRequest(..Item(session, "zz message "_i, "zzc"_..Number_"tf"_i), .response)
		Kill probes
		Set probes(1) = probe
		Do ..Pump(.probes)
	}
	Set first = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"tf1")
	Do $$$AssertEquals(first.State_"|"_first.Tainted_"|"_first.ReplyCatalogKey_"|"_first.FallbackReason, "done|1|conversation.turnFallback|cut_off", "the fallback reply is marked tainted")
	Do $$$AssertTrue(first.TurnDecisionRef ? 22(1AN,1"-",1"_"), "and keeps its reply decision: "_first.TurnDecisionRef)
	Set turns = ..Sent("Decide", "turn")
	Do $$$AssertEquals($ListLength(turns), 2, "two turn requests")
	Do $$$AssertEquals(..Call($List(turns, 1), "sessionMode"), "continue", "the first continues")
	Do $$$AssertEquals(..Call($List(turns, 2), "sessionMode"), "fresh", "the turn after the tainted fallback is fresh")
	Set seed = ..Call($List(turns, 2), "seedText")
	Do $$$AssertEquals(seed, ..Header()_$Char(10)_"User: zz message 1"_$Char(10)_"OcuTalon: (OcuTalon couldn't answer this message.)", "its recap shows the fallback as the no-answer line")
	Do $$$AssertTrue(seed '[ "tool result", "and nothing of the tool result")
}

/// A chat.message that cannot be published never stops the turn. Publish refuses inside an open transaction, so the whole turn
/// runs inside one that is rolled back at the end, and the results are read before the rollback: the turn is done with its reply,
/// the Outbound goes to Notify, and the stream holds no event.
Method TestPublishFailureNeverStopsTurn()
{
	Set session = ..Session("publishfail")
	Set clientId = "zzc"_..Number_"publishfail"
	Set item = ..Item(session, "zz publish fails", clientId)
	Set probe = ..NewProbe()
	Set probes(1) = probe
	Set error = "", opened = 0
	TSTART
	Try {
		Set opened = $TLevel
		Set sc = probe.OnRequest(item, .response)
		Do ..Pump(.probes)
		Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId)
		Set result = $Select($IsObject(row): row.State_"|"_row.ReplyText, 1: "no Turn")
		Set notices = $ListLength(..SentFor("Notify", session))
		Set events = ..ChatEvents(session).%Size()
	} Catch exception {
		Set error = exception.DisplayString()
	}
	If $TLevel > 0 TROLLBACK
	Do $$$AssertEquals(error, "", "the turn raises no error")
	Do $$$AssertTrue(opened > 0, "the turn ran inside an open transaction")
	Do $$$AssertStatusOK($Get(sc), "the Item is taken")
	Do $$$AssertEquals($Get(events), 0, "no chat.message could be published")
	Do $$$AssertEquals($Get(result), "done|zz reply to zz publish fails", "and the turn is still done with its reply")
	Do $$$AssertEquals($Get(notices), 1, "and its Outbound still goes to Notify")
	Do $$$AssertEquals(..Turns(session).Count(), 0, "the rollback left no Turn")
}

/// Each Item that Conversation drops is logged as one warning that names the cause; an Item that is taken, and a re-delivery or a
/// repeated ClientId, are not: those are dropped silently. The warnings that the test made are removed.
Method TestDroppedItemIsLogged()
{
	Set session = ..Session("logged")
	Set mark = ..LastLog()
	Set cases = $ListBuild("untrusted provenance|provenance is 'untrusted'", "no ItemId|no ItemId", "no text|no text", "no session|no session")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $Piece(case, "|", 1)
		Set item = ..Item(session, "zz logged", "zzc"_..Number_"l"_position)
		If label = "untrusted provenance" Set item.Provenance = "untrusted"
		If label = "no ItemId" Set item.ItemId = ""
		If label = "no text" Set item.Text = ""
		If label = "no session" Set item.SessionRef = ""
		Set before = ..Warnings(mark)
		Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), label_": the status is OK")
		Set after = ..Warnings(mark, .text)
		Do $$$AssertEquals(after - before, 1, label_": one warning is logged")
		Do $$$AssertEquals($Extract(text, 1, 30), "Conversation dropped an item: ", label_": it says an item was dropped")
		Do $$$AssertTrue(text [ $Piece(case, "|", 2), label_": and why: "_text)
	}
	Set item = ..Item(session, "zz silent", "zzc"_..Number_"silent")
	Set before = ..Warnings(mark)
	Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), "a valid Item is taken")
	Do $$$AssertEquals(..Warnings(mark), before, "and logs no warning")
	Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), "the same Item again is dropped")
	Do $$$AssertStatusOK(..NewProbe().OnRequest(..Item(session, "zz same client", item.ClientId), .response), "so is a new Item with the same ClientId")
	Do $$$AssertEquals(..Warnings(mark), before, "both silently")
	Do ..RemoveWarnings(mark)
}

/// With the double recording its decisions (triage: act, $0.0003; reply: $0.0005), chat.message carries the shown decision and
/// the turn's cost. While the turn runs it has the triage decision with its own cost; once it is done it has the triage decision
/// and the cost of both; a fallback reply's done message has the reply decision. The message queued before any decision has
/// neither.
Method TestDecisionOnChatMessage()
{
	Set session = ..Session("shown")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Record(session, 1)
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "decide", $ListBuild("act"))
	Set probe = ..NewProbe()
	Do probe.OnRequest(..Item(session, "zz shown", "zzc"_..Number_"shown"), .response)
	Do probe.Deliver(1)
	Do probe.Deliver()
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"shown")
	Set events = ..ChatEvents(session)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(events), "queued,running,done", "the three stages are published")
	Do $$$AssertEquals(events.%Get(0).payload.%IsDefined("decision")_"|"_events.%Get(0).payload.%IsDefined("turnCost"), "0|0", "queued: no decision and no cost")
	Set running = events.%Get(1).payload
	Do $$$AssertEquals(running.decision.ref_"|"_running.decision.kind_"|"_running.decision.outcome, row.TriageDecisionRef_"|decide|act", "running: the triage decision")
	Do $$$AssertEquals(+running.turnCost.costUSD_"|"_+running.turnCost.inputTokens_"|"_+running.turnCost.outputTokens, ".0003|1084|312", "with its own cost")
	Set done = events.%Get(2).payload
	Do $$$AssertEquals(done.decision.ref_"|"_done.decision.kind, row.TriageDecisionRef_"|decide", "done: still the triage decision")
	Do $$$AssertEquals(+done.decision.confidence_"|"_done.decision.reasons_"|"_done.decision.model, ".9|zz reason one"_$Char(10)_"zz reason two|Claude Haiku 5.5", "with the reasons, the confidence and the model's name")
	Do $$$AssertEquals(+done.turnCost.costUSD_"|"_+done.turnCost.inputTokens_"|"_+done.turnCost.outputTokens, ".0008|2168|624", "and the cost of both decisions")
	Do $$$AssertEquals(done.%IsDefined("checkKey")_"|"_done.%IsDefined("checks"), "0|0", "no check key and no check rows")

	Set second = ..Session("shownfallback")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Record(second, 1)
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(second, "decide", $ListBuild("digest"))
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(second, "turn", $ListBuild("fallback:timeout"))
	Set probe = ..NewProbe()
	Do probe.OnRequest(..Item(second, "zz shown fallback", "zzc"_..Number_"shownfallback"), .response)
	Do probe.Deliver(1)
	Set events = ..ChatEvents(second)
	Do $$$AssertEquals(events.%Get(1).payload.decision.outcome, "digest", "a running turn shows its triage decision")
	Do probe.Deliver()
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(second, "zzc"_..Number_"shownfallback")
	Set done = ..ChatEvents(second).%Get(2).payload
	Do $$$AssertEquals(row.ReplyCatalogKey '= "", 1, "the reply is a fallback")
	Do $$$AssertTrue((row.TriageDecisionRef '= "") && (row.TurnDecisionRef '= "") && (row.TriageDecisionRef '= row.TurnDecisionRef), "with two decisions")
	Do $$$AssertEquals(done.decision.ref_"|"_done.decision.kind_"|"_done.decision.fallback_"|"_done.decision.fallbackReason, row.TurnDecisionRef_"|turn|1|timeout", "the done message shows the reply decision")
	Do $$$AssertEquals(+done.turnCost.costUSD, .0008, "with the cost of both decisions")
}

/// The Outbound carries the Ref of the decision the turn shows: the triage decision of a reply, the reply decision of a fallback,
/// and, when the double wrote no row, the Ref the answers carried.
Method TestOutboundCarriesTheDecision()
{
	Set session = ..Session("outbound")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Record(session, 1)
	Set probe = ..NewProbe()
	Do probe.OnRequest(..Item(session, "zz outbound", "zzc"_..Number_"outbound"), .response)
	Set probes(1) = probe
	Do ..Pump(.probes)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"outbound")
	Set sent = ..SentFor("Notify", session)
	Do $$$AssertEquals($ListLength(sent), 1, "one Outbound")
	Do $$$AssertTrue(row.TriageDecisionRef '= row.TurnDecisionRef, "the turn has two decisions")
	Do $$$AssertEquals(..Call($List(sent, 1), "decisionRef"), row.TriageDecisionRef, "a reply: the triage decision's Ref")
	Do $$$AssertEquals(..Call($List(sent, 1), "checkKey")_..Call($List(sent, 1), "checkRows"), "", "and no check key or rows")

	Set second = ..Session("outboundfallback")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(second, "turn", $ListBuild("fallback:budget"))
	Set probe = ..NewProbe()
	Do probe.OnRequest(..Item(second, "zz outbound fallback", "zzc"_..Number_"outboundfallback"), .response)
	Kill probes
	Set probes(1) = probe
	Do ..Pump(.probes)
	Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(second, "zzc"_..Number_"outboundfallback")
	Set sent = ..SentFor("Notify", second)
	Do $$$AssertEquals($ListLength(sent), 1, "one Outbound for the fallback")
	Do $$$AssertEquals(..Call($List(sent, 1), "catalogKey"), "conversation.turnFallback", "it is the fallback's")
	Do $$$AssertTrue((row.TurnDecisionRef '= "") && (row.TriageDecisionRef '= row.TurnDecisionRef), "the turn has two decision Refs, and the double wrote no row")
	Do $$$AssertEquals(..Call($List(sent, 1), "decisionRef"), row.TurnDecisionRef, "a fallback: the reply decision's Ref")
}

/// A reply whose HostData holds checks goes to Checks.Render (here the probe's stand-in, which records the results it was given
/// and returns a key and two rows): the key and the rows are on the Turn, on the Outbound and on the done chat.message, and not
/// on the messages before it.
Method TestCheckRowsFromRender()
{
	Set rows = "[{""result"":""passed"",""entry"":""Orders production"",""finding"":"""",""checkedAt"":""2030-01-01T10:00:00Z""},{""result"":""failed"",""entry"":""Warehouse queue"",""finding"":""zz 12 messages waiting"",""checkedAt"":""2030-01-01T10:01:00Z""}]"
	Set row = ..Finish("render", "checks", $ListBuild("checks.everythingElsePassed", rows), , .session)
	Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz render", "the turn ends normally with its reply")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("ConversationProbe", ..Number, "rendered")), 1, "Render was called once")
	Do $$$AssertEquals($Get(^OcuTalonTest("ConversationProbe", ..Number, "rendered", 1)), "[{""zz"":""result""}]", "with the checks of the HostData, unread")
	Do $$$AssertEquals(row.CheckKey, "checks.everythingElsePassed", "the Turn keeps the key")
	Do $$$AssertEquals(row.CheckRows, ##class(%DynamicAbstractObject).%FromJSON(rows).%ToJSON(), "and the rows, as JSON")
	Set sent = ..SentFor("Notify", session)
	Do $$$AssertEquals(..Call($List(sent, 1), "checkKey"), "checks.everythingElsePassed", "the Outbound carries the key")
	Do $$$AssertEquals(..Call($List(sent, 1), "checkRows"), row.CheckRows, "and the rows")
	Set events = ..ChatEvents(session)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(events), "queued,running,done", "the three stages are published")
	Do $$$AssertEquals(events.%Get(1).payload.%IsDefined("checkKey")_"|"_events.%Get(1).payload.%IsDefined("checks"), "0|0", "running: no key and no rows")
	Set done = events.%Get(2).payload
	Do $$$AssertEquals(done.checkKey_"|"_done.checks.%Size(), "checks.everythingElsePassed|2", "done: the key and two rows")
	Set first = done.checks.%Get(0), second = done.checks.%Get(1)
	Do $$$AssertEquals(first.result_"|"_first.entry_"|"_first.%IsDefined("finding")_"|"_first.checkedAt, "passed|Orders production|0|2030-01-01T10:00:00Z", "the first row, with no finding")
	Do $$$AssertEquals(second.result_"|"_second.entry_"|"_second.finding_"|"_second.checkedAt, "failed|Warehouse queue|zz 12 messages waiting|2030-01-01T10:01:00Z", "the second row, with its finding")
}

/// A key that Render makes with no rows (checks.nothingWatched) is kept on its own: the Turn has the key and no rows, and the
/// Outbound and the done chat.message carry the key with no rows.
Method TestCheckKeyWithoutRows()
{
	Set row = ..Finish("keyonly", "checks", $ListBuild("checks.nothingWatched", "[]"), , .session)
	Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz keyonly", "the turn ends normally with its reply")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("ConversationProbe", ..Number, "rendered")), 1, "Render was called once")
	Do $$$AssertEquals(row.CheckKey_"|"_row.CheckRows, "checks.nothingWatched|", "the Turn keeps the key, with no rows")
	Set sent = ..SentFor("Notify", session)
	Do $$$AssertEquals(..Call($List(sent, 1), "checkKey")_"|"_..Call($List(sent, 1), "checkRows"), "checks.nothingWatched|", "the Outbound carries the key, with no rows")
	Set done = ..ChatEvents(session).%Get(2).payload
	Do $$$AssertEquals(done.checkKey_"|"_done.%IsDefined("checks"), "checks.nothingWatched|0", "done: the key, with no rows")
}

/// With the real Render, which is a stub, a reply with checks gets no key and no rows: nothing is on the Turn, the Outbound or
/// chat.message, and the turn ends normally. The seam RenderChecks is the call of Checks.Render with the results and the rows, the
/// one part of the path that the stub's empty answer cannot show.
Method TestStubRenderAddsNothing()
{
	Set method = ##class(%Dictionary.MethodDefinition).%OpenId("OcuTalon.Core.Conversation||RenderChecks")
	Set code = ""
	If $IsObject(method) {
		Do method.Implementation.Rewind()
		Set code = method.Implementation.Read(30000)
	}
	Do $$$AssertEquals($ZStrip(code, "<>WC"), "Quit ##class(OcuTalon.Checks.Render).Render(results, .rows)", "the seam calls Checks.Render with the results and the rows")
	Set row = ..Finish("stub", "checks", , , .session)
	Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz stub", "the turn ends normally with its reply")
	Do $$$AssertEquals(row.CheckKey_row.CheckRows, "", "no key and no rows on the Turn")
	Set sent = ..SentFor("Notify", session)
	Do $$$AssertEquals(..Call($List(sent, 1), "checkKey")_..Call($List(sent, 1), "checkRows"), "", "none on the Outbound")
	Set done = ..ChatEvents(session).%Get(2).payload
	Do $$$AssertEquals(done.%IsDefined("checkKey")_"|"_done.%IsDefined("checks"), "0|0", "none on chat.message")
}

/// A fallback reply whose HostData holds checks, a reply whose HostData is not JSON, one whose HostData has no checks, and one
/// whose Render fails, get no key and no rows, though Render would have made some: the first never reaches Render, the next two
/// are not checks, and an error in Render adds nothing. Each turn ends normally.
Method TestNoCheckRowsWithoutResults()
{
	Set render = $ListBuild("checks.allPassed", "[{""result"":""passed"",""entry"":""zz"",""finding"":"""",""checkedAt"":""2030-01-01T10:00:00Z""}]")
	Set cases = $ListBuild("checksfallback:timeout|a fallback reply", "badjson|bad JSON", "nochecks|HostData with no checks", "checks|a Render that fails")
	Set mark = ..LastLog()
	Set position = 0
	While $ListNext(cases, position, case) {
		Set answer = $Piece(case, "|", 1), label = $Piece(case, "|", 2)
		Set row = ..Finish("none"_position, answer, render, $Select(label = "a Render that fails": "render", 1: ""), .session)
		Do $$$AssertEquals(row.State, "done", label_": the turn ends normally")
		Do $$$AssertEquals(+$Get(^OcuTalonTest("ConversationProbe", ..Number, "rendered")), 0, label_": Render makes nothing for it")
		Do $$$AssertEquals(row.CheckKey_row.CheckRows, "", label_": no key and no rows on the Turn")
		Set sent = ..SentFor("Notify", session)
		Do $$$AssertEquals(..Call($List(sent, 1), "checkKey")_..Call($List(sent, 1), "checkRows"), "", label_": none on the Outbound")
		Set done = ..ChatEvents(session).%Get(2).payload
		Do $$$AssertEquals(done.%IsDefined("checkKey")_"|"_done.%IsDefined("checks"), "0|0", label_": none on chat.message")
		If $Piece(answer, ":", 1) = "checksfallback" {
			Do $$$AssertTrue(row.ReplyCatalogKey '= "", label_": the reply is a fallback")
		} Else {
			Do $$$AssertEquals(row.ReplyText, "zz reply to zz none"_position, label_": the reply is the model's")
		}
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = ? AND Text %STARTSWITH ?", mark, "Checked", "Conversation added no check results")
	Do result.%Next()
	Do $$$AssertEquals(+result.%GetData(1), 2, "bad JSON and the failing Render are each logged as one warning, the others are not")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = ? AND Text %STARTSWITH ?", mark, "Checked", "Conversation added no check results")
}

/// A busy reply and a session-broken reply whose HostData holds check results are not read for checks: the turn asks again and
/// ends with the answer that follows, which has none, so it gets no key and no rows, and Render is never given the earlier
/// answer's results. The turn request was sent twice in each case, so the busy and the broken branch did run.
Method TestBusyAndBrokenRepliesAreNotChecked()
{
	Set render = $ListBuild("checks.allPassed", "[{""result"":""passed"",""entry"":""zz"",""finding"":"""",""checkedAt"":""2030-01-01T10:00:00Z""}]")
	Set cases = $ListBuild("busychecks,reply|a busy reply", "brokenchecks,reply|a broken session")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set answers = $Piece(case, "|", 1), label = $Piece(case, "|", 2)
		Set row = ..Finish("sofar"_position, answers, render, , .session)
		Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz sofar"_position, label_": the turn ends with the answer that follows")
		Do $$$AssertEquals($ListLength(..Sent("Decide", "turn")), 2, label_": the turn request was sent again")
		Do $$$AssertEquals(+$Get(^OcuTalonTest("ConversationProbe", ..Number, "rendered")), 0, label_": Render is given nothing")
		Do $$$AssertEquals(row.CheckKey_row.CheckRows, "", label_": no key and no rows on the Turn")
		Set sent = ..SentFor("Notify", session)
		Do $$$AssertEquals(..Call($List(sent, 1), "checkKey")_..Call($List(sent, 1), "checkRows"), "", label_": none on the Outbound")
		Set events = ..ChatEvents(session)
		Set done = events.%Get(events.%Size() - 1).payload
		Do $$$AssertEquals(done.state_"|"_done.replyText, "done|"_row.ReplyText, label_": the newest chat.message is the done one")
		Do $$$AssertEquals(done.%IsDefined("checkKey")_"|"_done.%IsDefined("checks"), "0|0", label_": none on chat.message")
	}
}

/// A usable reply whose HostData holds citations, memories and checks: the Turn keeps the citations and the memories (JSON), the
/// Outbound sent to Notify and the done chat.message carry them, the check rows are still carried, and the messages before the reply
/// have none.
Method TestSourcesCarried()
{
	Set rows = "[{""result"":""passed"",""entry"":""Orders production"",""finding"":"""",""checkedAt"":""2030-01-01T10:00:00Z""}]"
	Set citations = [(..Citation(1, "Rotating the certificate")), (..Citation(2, "Checking the expiry"))]
	Set memories = [(..Memory(1))]
	Set hostData = {"checks": [{"zz": "result"}], "citations": (citations), "memories": (memories)}.%ToJSON()
	Set row = ..Finish("srcs", "reply", $ListBuild("checks.everythingElsePassed", rows), , .session, hostData)
	Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz srcs", "the turn ends normally with its reply")
	Do $$$AssertEquals(row.Citations, citations.%ToJSON(), "the Turn keeps both citations, as JSON")
	Do $$$AssertEquals(row.Memories, memories.%ToJSON(), "and the memory")
	Do $$$AssertEquals(row.CheckKey, "checks.everythingElsePassed", "the check key is still kept")
	Set sent = ..SentFor("Notify", session)
	Do $$$AssertEquals(..Call($List(sent, 1), "citations"), row.Citations, "the Outbound carries the citations")
	Do $$$AssertEquals(..Call($List(sent, 1), "memories"), row.Memories, "and the memories")
	Do $$$AssertEquals(..Call($List(sent, 1), "checkRows"), row.CheckRows, "and the check rows")
	Set events = ..ChatEvents(session)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(events), "queued,running,done", "the three stages are published")
	Do $$$AssertEquals(events.%Get(1).payload.%IsDefined("citations")_"|"_events.%Get(1).payload.%IsDefined("memories"), "0|0", "running: none")
	Set done = events.%Get(2).payload
	Do $$$AssertEquals(done.citations.%Size()_"|"_done.memories.%Size()_"|"_done.checks.%Size(), "2|1|1", "done: two citations, one memory and the check row")
	Set first = done.citations.%Get(0), second = done.citations.%Get(1)
	Do $$$AssertEquals(first.documentRef_"|"_first.document_"|"_first.section_"|"_first.passage_"|"_first.chunkIndex, "zzdoc1|Results runbook|Rotating the certificate|zz passage 1|1", "the first citation, every field")
	Do $$$AssertEquals(second.section_"|"_second.chunkIndex, "Checking the expiry|2", "the second citation")
	Set memory = done.memories.%Get(0)
	Do $$$AssertEquals(memory.memoryRef_"|"_memory.text_"|"_memory.savedAt, "zzmem1|zz remembered 1|2030-01-01T10:00:00Z", "the memory, every field")
	Set state = ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(row)
	Do state.%JSONExportToString(.json)
	Do $$$AssertEquals({}.%FromJSON(json).citations.%Size(), 2, "the payload built from the row (what /v1/state lists) holds the citations")
}

/// What HostData may hold: bad JSON, a value that is not an object, members that are not arrays and entries of the wrong shape add
/// nothing, a valid entry among bad ones is kept, no more than 5 of each are kept, a section of "" is a valid entry, and the check rows
/// are rendered whatever the sources hold. Each turn ends normally; bad JSON is one warning.
Method TestSourcesShape()
{
	Set rows = "[{""result"":""passed"",""entry"":""Orders production"",""finding"":"""",""checkedAt"":""2030-01-01T10:00:00Z""}]"
	Set seven = []
	For i = 1:1:7 Do seven.%Push(..Citation(i, "Section "_i))
	Set sevenMemories = []
	For i = 1:1:7 Do sevenMemories.%Push(..Memory(i))
	Set noSection = ..Citation(1, "")
	Set noChunk = ..Citation(2, "A")
	Do noChunk.%Remove("chunkIndex")
	Set textChunk = ..Citation(3, "A")
	Do textChunk.%Set("chunkIndex", "3")
	Set badSection = ..Citation(4, "A")
	Do badSection.%Set("section", 5)
	Set noPassage = ..Citation(5, "A")
	Do noPassage.%Remove("passage")
	Set numberText = ..Memory(2)
	Do numberText.%Set("text", 5)
	Set noSaved = ..Memory(3)
	Do noSaved.%Remove("savedAt")
	Set extra = ..Citation(6, "B")
	Do extra.%Set("zz", "extra member")
	// name | HostData | citations kept | memories kept
	Set cases = $ListBuild(
		$ListBuild("badjson", "{""checks"": [{", 0, 0),
		$ListBuild("array", "[1,2]", 0, 0),
		$ListBuild("notarrays", {"citations": "x", "memories": {"a": 1}}.%ToJSON(), 0, 0),
		$ListBuild("emptyarrays", {"citations": [], "memories": []}.%ToJSON(), 0, 0),
		$ListBuild("nonobjects", {"citations": [1, "x", null, [1]], "memories": [true, "x"]}.%ToJSON(), 0, 0),
		$ListBuild("badentries", {"citations": [(noChunk), (textChunk), (badSection), (noPassage)], "memories": [(numberText), (noSaved)]}.%ToJSON(), 0, 0),
		$ListBuild("onevalid", {"citations": [(noChunk), (noSection), (noPassage)], "memories": [(numberText), (..Memory(1))]}.%ToJSON(), 1, 1),
		$ListBuild("seven", {"citations": (seven), "memories": (sevenMemories)}.%ToJSON(), 5, 5),
		$ListBuild("extramember", {"citations": [(extra)]}.%ToJSON(), 1, 0))
	Set mark = ..LastLog()
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $List(case, 1)
		Set row = ..Finish("shape"_position, "reply", $ListBuild("checks.everythingElsePassed", rows), , .session, $List(case, 2))
		Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz shape"_position, label_": the turn ends normally with its reply")
		Set kept = $Select(row.Citations = "": 0, 1: {}.%FromJSON("{""a"":"_row.Citations_"}").a.%Size())
		Set keptMemories = $Select(row.Memories = "": 0, 1: {}.%FromJSON("{""a"":"_row.Memories_"}").a.%Size())
		Do $$$AssertEquals(kept_"|"_keptMemories, $List(case, 3)_"|"_$List(case, 4), label_": the entries kept")
		Set sent = ..SentFor("Notify", session)
		Do $$$AssertEquals(..Call($List(sent, 1), "citations")_"|"_..Call($List(sent, 1), "memories"), row.Citations_"|"_row.Memories, label_": the Outbound carries what the Turn keeps")
		Set done = ..ChatEvents(session).%Get(2).payload
		Do $$$AssertEquals($Select(done.%IsDefined("citations"): done.citations.%Size(), 1: 0)_"|"_$Select(done.%IsDefined("memories"): done.memories.%Size(), 1: 0), $List(case, 3)_"|"_$List(case, 4), label_": and chat.message")
		If label = "badjson" {
			Do $$$AssertEquals(row.CheckKey, "", label_": the check rows are not made from bad JSON")
		} ElseIf (label = "onevalid") || (label = "seven") || (label = "extramember") {
			Do $$$AssertEquals(row.CheckKey, "", label_": HostData without checks has no check key")
		}
	}
	Set row = ..Finish("shapechecks", "reply", $ListBuild("checks.everythingElsePassed", rows), , .session, {"checks": [{"zz": "result"}], "citations": [(..Citation(1, "A"))]}.%ToJSON())
	Do $$$AssertEquals(row.CheckKey_"|"_(row.CheckRows '= ""), "checks.everythingElsePassed|1", "with sources the check key and rows are still made")
	Do $$$AssertEquals(row.Citations, [(..Citation(1, "A"))].%ToJSON(), "and the citation is kept")
	Set cut = ..Finish("shapecut", "reply", , , .session, {"citations": [(extra)]}.%ToJSON())
	Do $$$AssertEquals(cut.Citations, [(..Citation(6, "B"))].%ToJSON(), "a member outside the shape is cut away")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = ? AND Text %STARTSWITH ?", mark, "Sourced", "Conversation added no citations or memories")
	Do result.%Next()
	Do $$$AssertEquals(+result.%GetData(1), 1, "bad JSON is one warning, the other shapes are not")
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = ? AND Text %STARTSWITH ?", mark, "Sourced", "Conversation added no citations or memories")
}

/// A usable reply whose HostData holds learned saves (Story 41.15): the Turn keeps the entries (JSON), the Outbound sent to Notify carries them as they are, and the done chat.message carries the entries to show, {memoryRef, fact},
/// with the fact shaped; the messages before the reply have none, and the reply text is the guarded text, byte for byte.
Method TestLearnedCarried()
{
	Set learned = [(..Learned(1)), {"memoryRef": "zzlrn2", "text": "Lee is the contact."}]
	Set hostData = {"learned": (learned)}.%ToJSON()
	Set row = ..Finish("lrn", "reply", , , .session, hostData)
	Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz lrn", "the turn ends normally with its reply, as the guard left it")
	Do $$$AssertEquals(row.Learned, learned.%ToJSON(), "the Turn keeps both entries, as JSON")
	Set sent = ..SentFor("Notify", session)
	Do $$$AssertEquals(..Call($List(sent, 1), "learned"), row.Learned, "the Outbound carries them")
	Do $$$AssertEquals(..Call($List(sent, 1), "text"), row.ReplyText, "and the reply text unchanged")
	Set events = ..ChatEvents(session)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(events), "queued,running,done", "the three stages are published")
	Do $$$AssertEquals(events.%Get(0).payload.%IsDefined("learned")_"|"_events.%Get(1).payload.%IsDefined("learned"), "0|0", "queued and running: none")
	Set done = events.%Get(2).payload
	Do $$$AssertEquals(done.replyText, row.ReplyText, "done: the reply text is the guarded text")
	Do $$$AssertEquals(done.learned.%ToJSON(), [{"memoryRef": "zzlrn1", "fact": "zz learned fact 1"}, {"memoryRef": "zzlrn2", "fact": "Lee is the contact"}].%ToJSON(), "done: the entries to show, {memoryRef, fact}, with one trailing full stop removed")
	Set state = ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(row)
	Do state.%JSONExportToString(.json)
	Do $$$AssertEquals({}.%FromJSON(json).learned.%Size(), 2, "the payload built from the row (what /v1/state lists) holds them")
}

/// What HostData may hold for learned: bad JSON, a value that is not an object, a member that is not an array and entries of the wrong shape add nothing, a valid entry among bad ones is kept, at most 3 are kept,
/// and a member outside the shape is cut away. Each turn ends normally.
Method TestLearnedShape()
{
	Set badRef = ..Learned(2)
	Do badRef.%Set("memoryRef", 5)
	Set noText = ..Learned(3)
	Do noText.%Remove("text")
	Set numberText = ..Learned(4)
	Do numberText.%Set("text", 5)
	Set extra = ..Learned(5)
	Do extra.%Set("zz", "extra member")
	Set five = []
	For i = 1:1:5 Do five.%Push(..Learned(i))
	// name | HostData | the entries kept, as JSON ("" for none)
	Set cases = $ListBuild(
		$ListBuild("badjson", "{""learned"": [{", ""),
		$ListBuild("array", "[1,2]", ""),
		$ListBuild("notarray", {"learned": "x"}.%ToJSON(), ""),
		$ListBuild("anobject", {"learned": {"memoryRef": "a", "text": "b"}}.%ToJSON(), ""),
		$ListBuild("empty", {"learned": []}.%ToJSON(), ""),
		$ListBuild("nonobjects", {"learned": [1, "x", null, [1]]}.%ToJSON(), ""),
		$ListBuild("badentries", {"learned": [(badRef), (noText), (numberText)]}.%ToJSON(), ""),
		$ListBuild("onevalid", {"learned": [(badRef), (noText), (..Learned(1))]}.%ToJSON(), [(..Learned(1))].%ToJSON()),
		$ListBuild("five", {"learned": (five)}.%ToJSON(), [(..Learned(1)), (..Learned(2)), (..Learned(3))].%ToJSON()),
		$ListBuild("extramember", {"learned": [(extra)]}.%ToJSON(), [(..Learned(5))].%ToJSON()))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $List(case, 1)
		Set row = ..Finish("lrnshape"_position, "reply", , , .session, $List(case, 2))
		Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|zz reply to zz lrnshape"_position, label_": the turn ends normally with its reply")
		Do $$$AssertEquals(row.Learned, $List(case, 3), label_": the entries kept")
		Set sent = ..SentFor("Notify", session)
		Do $$$AssertEquals(..Call($List(sent, 1), "learned"), row.Learned, label_": the Outbound carries what the Turn keeps")
		Set done = ..ChatEvents(session).%Get(2).payload
		Do $$$AssertEquals($Select(done.%IsDefined("learned"): done.learned.%Size(), 1: 0), $Select(row.Learned = "": 0, 1: {}.%FromJSON("{""a"":"_row.Learned_"}").a.%Size()), label_": and chat.message")
	}
}

/// A busy reply, a broken session and a fallback whose HostData holds learned saves carry none (Story 41.15).
Method TestLearnedNotOnFallbacks()
{
	Set hostData = {"learned": [(..Learned(1))]}.%ToJSON()
	Set cases = $ListBuild("busy,reply|a busy reply", "broken,reply|a broken session", "fallback:timeout|a fallback")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set answers = $Piece(case, "|", 1), label = $Piece(case, "|", 2)
		Set row = ..Finish("nolrn"_position, answers, , , .session, hostData)
		Do $$$AssertEquals(row.State, "done", label_": the turn ends")
		Do $$$AssertEquals(row.Learned, "", label_": no learned entry on the Turn")
		Set sent = ..SentFor("Notify", session)
		Do $$$AssertEquals(..Call($List(sent, 1), "learned"), "", label_": none on the Outbound")
		Set events = ..ChatEvents(session)
		Set done = events.%Get(events.%Size() - 1).payload
		Do $$$AssertEquals(done.state_"|"_done.%IsDefined("learned"), "done|0", label_": none on the done chat.message")
	}
}

/// A reply that already says "I'll remember" (Story 41.15): the Turn and the Outbound keep the entries, the reply text is not changed, and chat.message and the payload of the row carry no learned entry to show. A reply
/// that does not say it, with the same entries, has them, as a control.
Method TestLearnedSaid()
{
	Set hostData = {"learned": [(..Learned(1))]}.%ToJSON()
	Set said = "I'll remember that zz learned fact 1."
	Set row = ..Finish("lrnsaid", "reply", , , .session, hostData, said)
	Do $$$AssertEquals(row.State_"|"_row.ReplyText, "done|"_said, "the turn ends with the reply, unchanged")
	Do $$$AssertEquals(row.Learned, [(..Learned(1))].%ToJSON(), "the Turn still keeps the entry")
	Set sent = ..SentFor("Notify", session)
	Do $$$AssertEquals(..Call($List(sent, 1), "learned"), row.Learned, "and the Outbound carries it")
	Do $$$AssertEquals(..Call($List(sent, 1), "text"), said, "with the reply text unchanged")
	Set done = ..ChatEvents(session).%Get(2).payload
	Do $$$AssertEquals(done.replyText_"|"_done.%IsDefined("learned"), said_"|0", "the done chat.message has no learned entry: nothing to announce")
	Set state = ##class(OcuTalon.Live.Payload.ChatMessage).FromRow(row)
	Do state.%JSONExportToString(.json)
	Do $$$AssertEquals({}.%FromJSON(json).%IsDefined("learned"), 0, "and the payload built from the row (what /v1/state lists) has none")
	Set row = ..Finish("lrnsaid2", "reply", , , .session, hostData, "I will remember "_$Char(8217)_"that")
	Do $$$AssertEquals(..ChatEvents(session).%Get(2).payload.%IsDefined("learned"), 0, "'I will remember' says it too")
	Set row = ..Finish("lrnsaid3", "reply", , , .session, hostData, "Noted.")
	Do $$$AssertEquals(..ChatEvents(session).%Get(2).payload.learned.%Size(), 1, "control: a reply that does not say it carries the entry to show")
}

/// A busy reply, a broken session and a fallback whose HostData holds citations and memories carry none: the first two are asked
/// again and the answer that follows has none, and the fallback ends the turn without reading them.
Method TestSourcesNotOnFallbacks()
{
	Set hostData = {"citations": [(..Citation(1, "A"))], "memories": [(..Memory(1))]}.%ToJSON()
	Set cases = $ListBuild("busy,reply|a busy reply", "broken,reply|a broken session", "fallback:timeout|a fallback")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set answers = $Piece(case, "|", 1), label = $Piece(case, "|", 2)
		Set row = ..Finish("nosrc"_position, answers, , , .session, hostData)
		Do $$$AssertEquals(row.State, "done", label_": the turn ends")
		Do $$$AssertEquals(row.Citations_row.Memories, "", label_": no citations or memories on the Turn")
		Set sent = ..SentFor("Notify", session)
		Do $$$AssertEquals(..Call($List(sent, 1), "citations")_..Call($List(sent, 1), "memories"), "", label_": none on the Outbound")
		Set events = ..ChatEvents(session)
		Set done = events.%Get(events.%Size() - 1).payload
		Do $$$AssertEquals(done.state_"|"_done.%IsDefined("citations")_"|"_done.%IsDefined("memories"), "done|0|0", label_": none on the done chat.message")
	}
}

/// DW-721 (U-280), through the real reply guard that Decide runs: a reply whose text says "None of your documents cover that." and
/// whose HostData holds citations is stored without the sentence and carries the citations; a reply with the sentence and no citations
/// keeps it and carries none.
Method TestNeverBoth()
{
	Set none = "None of your documents cover that."
	Set hostData = {"citations": [(..Citation(1, "Rotating the certificate"))]}.%ToJSON()
	Set row = ..Finish("both", "reply", , , .session, hostData, "Rotate it from the Certificates page. "_none, 1)
	Do $$$AssertEquals(row.ReplyText, "Rotate it from the Certificates page.", "with citations the stored reply lacks the sentence")
	Do $$$AssertEquals(row.ReplyText '[ none, 1, "and never holds it")
	Do $$$AssertEquals(row.Citations, {}.%FromJSON(hostData).citations.%ToJSON(), "and the citations are carried")
	Set done = ..ChatEvents(session).%Get(2).payload
	Do $$$AssertEquals(done.replyText_"|"_done.citations.%Size(), "Rotate it from the Certificates page.|1", "chat.message shows the filtered text with the citation")

	Set row = ..Finish("nocite", "reply", , , .session, "{""zz"": ""tool result""}", none, 1)
	Do $$$AssertEquals(row.ReplyText, none, "without citations the sentence stays as sent")
	Do $$$AssertEquals(row.Citations_row.Memories, "", "and nothing is carried")
	Set done = ..ChatEvents(session).%Get(2).payload
	Do $$$AssertEquals(done.replyText_"|"_done.%IsDefined("citations"), none_"|0", "chat.message shows the sentence and no citation")

	Set row = ..Finish("emptycite", "reply", , , .session, "{""citations"": []}", none, 1)
	Do $$$AssertEquals(row.ReplyText_"|"_row.Citations, none_"|", "an empty citations array leaves the sentence and carries nothing")
}

/// --- helpers ---
/// Runs a message of a new session to its end, with the turn answers scripted (answer is one answer, or several separated by
/// commas, given in turn), and returns the turn. render, when it is not "", is what the probe's Render stand-in returns
/// ($ListBuild(key, rowsJSON)); throwIn is set on the probe. The session is returned in session. hostData, when it is not "", is the
/// HostData of the first reply the double makes, with text as its text when that is not "" and the real reply guard applied to it when
/// filter is 1 (DecideDouble SetReply).
Method Finish(name As %String, answer As %String, render As %List = "", throwIn As %String = "", Output session As %String, hostData As %String = "", text As %String = "", filter As %Boolean = 0) As OcuTalon.Data.Turn [ Private ]
{
	Set session = ..Session(name)
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "turn", $ListFromString(answer))
	If hostData '= "" Do ##class(OcuTalon.Test.Core.DecideDouble).SetReply(session, hostData, text, filter)
	If render '= "" Set ^OcuTalonTest("ConversationProbe", ..Number, "render") = render
	Set probe = ..NewProbe()
	Set probe.ThrowIn = throwIn
	Do probe.OnRequest(..Item(session, "zz "_name, "zzc"_..Number_name), .response)
	Set probes(1) = probe
	Do ..Pump(.probes)
	Quit ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_name)
}

/// A fixture session; its Ref is kept for the clean-up and the double's scripts are cleared.
Method Session(name As %String) As %String [ Private ]
{
	Kill ^OcuTalonTest("ConversationProbe", ..Number)
	Set ..Handled = 0
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzconv"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Do ##class(OcuTalon.Test.Core.DecideDouble).Clear(ref)
	Quit ref
}

/// A shadow instance of the probe, in the run's records, with a session of its own.
Method NewProbe() As OcuTalon.Test.Core.ConversationProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.ConversationProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.RunNumber = ..Number
	Quit probe
}

/// An Item of the web channel: user provenance, a new ItemId unless one is given.
Method Item(session As %String, text As %String, clientId As %String, itemId As %String = "") As OcuTalon.Msg.Item [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = $Select(itemId '= "": itemId, 1: ##class(OcuTalon.Bridge.Ids).NewRef())
	Set item.SessionRef = session
	Set item.Channel = "web"
	Set item.Provenance = "user"
	Set item.Text = text
	Set item.ClientId = clientId
	Quit item
}

/// Hands every kept answer of every probe to its callbacks, and every RunTurns request that a probe recorded to a new probe,
/// until no work is left. probes(n) are the probes with answers to deliver; new probes are added.
Method Pump(ByRef probes) [ Private ]
{
	For round = 1:1:200 {
		Set work = 0
		Set i = ""
		For {
			Set i = $Order(probes(i))
			Quit:i=""
			Set work = work + probes(i).Deliver()
		}
		Set limit = ..Calls()
		For n = ..Handled + 1:1:limit {
			If (..Call(n, "target") = "Conversation") && (..Call(n, "class") = "OcuTalon.Core.Msg.RunTurns") {
				Set run = ##class(OcuTalon.Core.Msg.RunTurns).%New()
				Set run.SessionRef = ..Call(n, "sessionRef")
				Set probe = ..NewProbe()
				Set probes($Order(probes(""), -1) + 1) = probe
				Do $$$AssertStatusOK(probe.OnRequest(run, .response), "the RunTurns request is handled by a new instance")
				Set work = work + 1
			}
		}
		Set ..Handled = limit
		If 'work Quit
	}
}

/// The number of calls the probes recorded.
Method Calls() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("ConversationProbe", ..Number))
}

/// One field of one recorded call.
Method Call(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("ConversationProbe", ..Number, n, field))
}

/// The numbers of the calls to the target, as a list; with kind only the Decide requests of that kind.
Method Sent(target As %String, kind As %String = "") As %List [ Private ]
{
	Set list = ""
	For n = 1:1:..Calls() {
		If ..Call(n, "target") '= target Continue
		If (kind '= "") && (..Call(n, "kind") '= kind) Continue
		Set list = list_$ListBuild(n)
	}
	Quit list
}

/// The numbers of the calls to the target for the session (an Outbound's sessionRef).
Method SentFor(target As %String, session As %String) As %List [ Private ]
{
	Set list = ""
	For n = 1:1:..Calls() {
		If (..Call(n, "target") = target) && (..Call(n, "sessionRef") = session) Set list = list_$ListBuild(n)
	}
	Quit list
}

/// A citation of the document "Results runbook" under the section; its document ref, passage and chunk index follow the number.
Method Citation(number As %Integer, section As %String) As %DynamicObject [ Private ]
{
	Quit {"documentRef": ("zzdoc"_number), "document": "Results runbook", "section": (section), "passage": ("zz passage "_number), "chunkIndex": (number)}
}

/// A learned entry made from the number (Story 41.15).
Method Learned(number As %Integer) As %DynamicObject [ Private ]
{
	Quit {"memoryRef": ("zzlrn"_number), "text": ("zz learned fact "_number)}
}

/// A memory made from the number.
Method Memory(number As %Integer) As %DynamicObject [ Private ]
{
	Quit {"memoryRef": ("zzmem"_number), "text": ("zz remembered "_number), "savedAt": "2030-01-01T10:00:00Z"}
}

/// The session's turns, as Ownership reads them.
Method Turns(session As %String) As %ListOfObjects [ Private ]
{
	Set turns = ##class(OcuTalon.Data.Ownership).Turns(session, .sc)
	Do $$$AssertStatusOK(sc, "the turns are read")
	Quit turns
}

/// The chat.message events of the session's stream, in order, as an array; with ref only those of that turn.
Method ChatEvents(session As %String, ref As %String = "") As %DynamicArray [ Private ]
{
	Set found = []
	Set events = ##class(OcuTalon.Live.Event).Since(session, 0, 200, "session")
	Set iterator = events.%GetIterator()
	While iterator.%GetNext(, .event) {
		If (event.type = "chat.message") && ((ref = "") || (event.payload.ref = ref)) Do found.%Push(event)
	}
	Quit found
}

/// The number of the newest row of the event log, 0 when it is empty.
Method LastLog() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of warnings that Conversation logged for a dropped Item after the row mark (the event log names the class of the
/// instance, here the probe); text is the newest one's text.
Method Warnings(mark As %Integer, Output text As %String) As %Integer [ Private ]
{
	Set text = ""
	Set count = 0
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = ? AND Text %STARTSWITH ? ORDER BY ID", mark, "Take", "Conversation dropped an item")
	While result.%Next() {
		Set count = count + 1
		Set text = result.%Get("Text")
	}
	Quit count
}

/// Removes the warnings for a dropped Item that were logged after the row mark.
Method RemoveWarnings(mark As %Integer) [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = ? AND Text %STARTSWITH ?", mark, "Take", "Conversation dropped an item")
}

/// The first line of every recap, as the spec words it.
Method Header() As %String [ Private ]
{
	Quit "This conversation so far, as OcuTalon recorded it (the user's messages and OcuTalon's replies as sent):"
}

}
