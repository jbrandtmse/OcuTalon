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
///   - TestRecapFromTurnRows: the recap is written from the Turn rows;
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
///   - TestAnswerForNonRunningTurnDropped: an answer for a turn that is no longer running changes nothing, whatever its Attempt;
///   - TestDecideAnswerOfAnotherClassStillRuns: a decide answer that is not a DecisionResponse keeps no DecisionRef and the turn
///     runs on;
///   - TestSourceKeepsToItsBoundaries: Conversation and WebChatIn never call SendRequestSync (AD-6) or render through the catalog
///     (AD-32), and Conversation never asks the allowance (AD-20), which the tests that replace the seams can't see;
///   - TestTurnKeepsItsChannel: a message from another channel keeps its channel through the Turn, both Decide requests, the Outbound
///     and the events, and two such messages with no ClientId are two turns;
///   - TestTaintedFallbackNextFresh: a fallback reply keeps the Tainted flag of the reply, so the next turn is fresh;
///   - TestPublishFailureNeverStopsTurn: a chat.message that cannot be published never stops the turn;
///   - TestDroppedItemIsLogged: each dropped Item is logged as one warning, and a re-delivery is dropped silently.
/// The fixture sessions come from Test.Data.Fixture, and the turns that Conversation makes are adopted after each test, so
/// Fixture.Clean removes them with the events of the streams. The run's number is n from ^OcuTalonTest("ConversationTurns",
/// "n") (never reset); the probe records the calls of the run under ^OcuTalonTest("ConversationProbe", n), and the double's
/// scripts and records are removed for each fixture session.
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

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("ConversationTurns", "n"))
	Set ..Refs = ""
	Set ..Sessions = ""
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
	Quit $SYSTEM.Status.OK()
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
		Do $$$AssertEquals(..Call(n, "input"), render, kind_": the input is what Agent.Input renders")
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
			Do $$$AssertTrue(..Call(n, "summary")_..Call(n, "input")_..Call(n, "seedText") '[ "bravo", label_": nothing of the second message")
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

/// Each of the 12 fallback reasons, an error status and an answer of the wrong class, as the turn's answer: the Outbound, the
/// row and the last chat.message carry the catalog key conversation.turnFallback and the reason, and the catalog renders the
/// sentence for the web chat. A reason that is not in the enumeration is unusable.
Method TestEveryFallbackReason()
{
	Set oracle = $ListBuild("timeout|the model didn't answer within 60 seconds", "empty|the model's reply was empty", "cut_off|the model's reply was cut off", "refusal|the model declined to answer", "error|the model returned an error", "rate_limited|the model was busy and retries ran out", "budget|this would have gone over the token budget", "too_large|this request would have been too large to send", "daily_cap|today's cost limit has been reached", "no_key|no model key is set", "invalid|the model's reply couldn't be used", "unusable|the model's reply couldn't be used")
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

/// --- helpers ---
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
