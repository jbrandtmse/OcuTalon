/// End-to-end tests of the turn pipeline over the running production (Story 2.4; AD-1, AD-14, AD-26, AD-30). THIS CLASS RUNS
/// IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the running OcuTalon.Production, which a slot never has. Where the
/// production does not run, every test fails with that reason, so that a broken start can never give a green shard. A message
/// goes through Ens.Director.CreateBusinessService("WebChatIn") and ProcessInput, as the REST surface sends it, to the real
/// Conversation and the Decide of Epic 0, which answers an error status until Lane A builds it (Story 1.3). So every turn ends
/// in the fallback unusable; the unit tests of OcuTalon.Test.Core.ConversationTurns cover every other reply shape.
///   - TestTurnThroughProduction: a message becomes a Turn that reaches done within 20 seconds with the text, the ClientId,
///     the ItemId, the Item's header as the trace target and the fallback key and reason; the session's stream holds the
///     three chat.message events; the Item, the two Decide requests (decide and turn, in the Item's trace session) and the
///     one Outbound to Notify are all in the session's SuperSession (the TraceRef). The Outbound goes on through Notify to
///     WebChatOut, which leaves one Delivery row for the web with the reply's DecisionRef and no ChannelMessageId, and
///     publishes no notification event (Story 2.7);
///   - TestRepeatQueuesNothing: a second message with the same clientId is accepted as a duplicate and queues nothing;
///   - TestTurnsRunInOrder: three messages are three turns that run one after another, in the order they were posted, each
///     with one done event, and each turn's requests and Outbound are in its own Item's trace session (AD-26), and each
///     Outbound leaves one reply Delivery row;
///   - TestReconcileResumesTurns: a running turn and two queued turns are run, in order, by Install.Step.Web.Reconcile(),
///     each with one reply, and every RunTurns request is in the session's SuperSession (AD-26);
///   - TestReconcileResumesEverySession: the same sweep resumes the turns of three sessions at once (one with a running and a
///     queued turn, one with a lone running turn, one with a lone queued turn), each turn with one reply, and the sweep's
///     RunTurns request for each session is in that session's SuperSession, while the sweep request itself is in none.
/// Before a reconcile a test checks that no other session has a queued or running turn, and after each test the turns of the
/// run's sessions that are not done are removed, so that no test runs another's turns. The guard, the fixture sessions, the
/// run's number (^OcuTalonTest("ConversationProduction","n")) and the clean-up are those of Test.Core.InProduction; the clean-up
/// also removes the turns that Conversation made, with their events, and the Delivery rows that WebChatOut made for the
/// fixture sessions.
Class OcuTalon.Test.Core.ConversationProduction Extends OcuTalon.Test.Core.InProduction
{

/// The start of the user name of each fixture session.
Parameter SESSIONPREFIX = "zzprodconv";

/// Seconds to wait for a turn to be done.
Parameter WAIT = 20;

/// After each test, the turns of the run's sessions that are not done are removed, so that a test that failed leaves no turn
/// for the next test's sweep to run; an instance that still runs one of them finds no row and changes nothing.
Method OnAfterOneTest() As %Status
{
	Set refs = ""
	For i = 1:1:$Length(..Sessions, ",") {
		Set session = $Piece(..Sessions, ",", i)
		If session = "" Continue
		Set queue = ##class(OcuTalon.Data.Ownership).TurnQueue(session, .sc)
		For j = 1:1:queue.Count() {
			Set refs = refs_$Select(refs = "": "", 1: ",")_##class(OcuTalon.Test.Data.Fixture).Adopt(queue.GetAt(j))
		}
	}
	If refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(refs)
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	Quit ##super()
}

/// A message goes through WebChatIn and the turn is done within 20 seconds with the fallback unusable (the stub Decide answers an
/// error status). The Turn keeps the text, the ClientId, the ItemId, the Item's header as the trace target, the key and the
/// reason. The stream holds queued, running and done, once each. The Item, both Decide requests and the Outbound carry the
/// session's TraceRef as SuperSession, and both Decide requests name the Item's session as their thread.
Method TestTurnThroughProduction()
{
	If '..Guard() Quit
	Set session = ..Session("turn")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set clientId = "zzc"_..Number_"turn"
	Set text = "zz hello from the production"_$Char(10)_"second line"
	Set sc = ..Send(session, clientId, text, .output)
	Do $$$AssertStatusOK(sc, "the message is accepted by WebChatIn")
	Do $$$AssertEquals(output, "{""accepted"":1,""duplicate"":0}", "as a new message")
	Set row = ..WaitDone(session, clientId)
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "a Turn was made")
		Quit
	}
	Do $$$AssertEquals(row.State, "done", "the turn reaches done within "_..#WAIT_" seconds")
	Do $$$AssertEquals(row.Text_"|"_row.ClientId_"|"_row.Channel_"|"_row.FromGuide, text_"|"_clientId_"|web|0", "it keeps the text, the ClientId, the channel and FromGuide")
	Do $$$AssertTrue(row.ItemId ? 22(1AN,1"-",1"_"), "and the ItemId: "_row.ItemId)
	Do $$$AssertEquals(row.ReplyCatalogKey_"|"_row.FallbackReason_"|"_row.ReplyText, "conversation.turnFallback|unusable|", "the stub Decide gives the fallback unusable")
	Do $$$AssertEquals(row.Attempt_"|"_row.Tainted_"|"_row.TriageDecisionRef_"|"_row.TurnDecisionRef, "1|0||", "started once, with no decision to keep")
	Set events = ..WaitEvents(session, 3)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(events), "queued,running,done", "the stream holds the three stages, once each")
	If events.%Size() = 3 {
		Set last = events.%Get(2).payload
		Do $$$AssertEquals(last.ref_"|"_last.clientId_"|"_last.text_"|"_last.catalogKey_"|"_last.fallbackReason_"|"_last.replyText, row.Ref_"|"_clientId_"|"_text_"|conversation.turnFallback|unusable|", "and the last one is the turn as stored")
		Do $$$AssertEquals(last.traceHeaderId_"|"_last.traceNamespace, row.TraceHeaderId_"|"_$Namespace, "with the trace target")
	}
	Do ..WaitNotices(trace, 1)
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set items = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "WebChatIn", "Conversation")
	Do $$$AssertEquals(items.%Size(), 1, "one Item request header goes from WebChatIn to Conversation, in the session's SuperSession")
	If items.%Size() '= 1 Quit
	Set item = items.%Get(0)
	Do $$$AssertEquals(item.bodyClass, "OcuTalon.Msg.Item", "its body is the Item")
	Do $$$AssertEquals(row.TraceHeaderId, item.id, "the Turn's trace target is the Item's header")
	Set decides = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Conversation", "Decide")
	Do $$$AssertEquals(decides.%Size(), 2, "two requests go from Conversation to Decide")
	If decides.%Size() = 2 {
		Set kinds = ""
		For i = 0:1:1 {
			Set header = decides.%Get(i)
			Set body = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(header.bodyId)
			Set kinds = kinds_$Select(kinds = "": "", 1: ",")_body.Kind
			Do $$$AssertEquals(header.superSession, trace, body.Kind_": in the session's SuperSession")
			Do $$$AssertEquals(header.sessionId, item.sessionId, body.Kind_": in the Item's trace session")
			Do $$$AssertEquals(body.ThreadSessionId, item.sessionId, body.Kind_": ThreadSessionId is the Item's session")
			Do $$$AssertEquals(body.ItemId_"|"_body.OwnerRef_"|"_body.TraceRef_"|"_body.Channel_"|"_body.Provenance, row.ItemId_"|"_session_"|"_trace_"|web|user", body.Kind_": the ids, the channel and provenance user")
			Do $$$AssertEquals(body.Summary, "zz hello from the production", body.Kind_": the Summary is the first line")
		}
		Do $$$AssertEquals(kinds, "decide,turn", "decide first, then turn")
	}
	Set notices = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Conversation", "Notify")
	Do $$$AssertEquals(notices.%Size(), 1, "one Outbound goes from Conversation to Notify")
	If notices.%Size() = 1 {
		Set outbound = ##class(OcuTalon.Msg.Outbound).%OpenId(notices.%Get(0).bodyId)
		Do $$$AssertEquals(notices.%Get(0).superSession, trace, "in the session's SuperSession")
		Do $$$AssertEquals(outbound.SessionRef_"|"_outbound.OriginChannel_"|"_outbound.CatalogKey_"|"_outbound.Slots_"|"_outbound.Text, session_"|web|conversation.turnFallback|{""fallbackReason"":""unusable""}|", "carrying the key and the slots")
	}
	Do ..WaitDeliveries(session, 1)
	Do $$$AssertTrue(..Handled(trace, 1), "WebChatOut has handled the Outbound")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Notify", "WebChatOut").%Size(), 1, "the Outbound goes on from Notify to WebChatOut, in the session's SuperSession")
	Set deliveries = ..Deliveries(session)
	Do $$$AssertEquals(deliveries.Count(), 1, "WebChatOut leaves one Delivery row for the session")
	If deliveries.Count() = 1 {
		Set delivery = deliveries.GetAt(1)
		Do $$$AssertEquals(delivery.OwnerRef_"|"_delivery.Channel_"|"_delivery.ChannelMessageId_"|"_delivery.Kind_"|"_delivery.Text_"|"_delivery.DecisionRef, session_"|web||||", "it is the reply's row: the web, no message id, no kind or text, and the reply's DecisionRef (none for the stub Decide)")
	}
	Do $$$AssertEquals(..Notifications(session), 0, "and no notification event is published for a reply")
}

/// A second message with the same clientId answers as a duplicate: no second Turn, no second Item request, no second set of
/// events.
Method TestRepeatQueuesNothing()
{
	If '..Guard() Quit
	Set session = ..Session("repeat")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set clientId = "zzc"_..Number_"repeat"
	Do $$$AssertStatusOK(..Send(session, clientId, "zz once", .output), "the first message is accepted")
	Set row = ..WaitDone(session, clientId)
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "a Turn was made")
		Quit
	}
	Set sc = ..Send(session, clientId, "zz twice", .output)
	Do $$$AssertStatusOK(sc, "the repeat is accepted")
	Do $$$AssertEquals(output, "{""accepted"":1,""duplicate"":1}", "as a duplicate")
	Hang 2
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Turns(session).Count(), 1, "the session still has one Turn")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "WebChatIn", "Conversation").%Size(), 1, "and one Item request header")
	Set events = ..WaitEvents(session, 3)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).States(events), "queued,running,done", "and its three events")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId).Text, "zz once", "the first message stands")
}

/// Three messages in a row are three turns that run one after another: the turn requests reach Decide in the order the
/// messages were posted, and each turn has one done event.
Method TestTurnsRunInOrder()
{
	If '..Guard() Quit
	Set session = ..Session("order")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Kill itemIds
	For i = 1:1:3 {
		Do $$$AssertStatusOK(..Send(session, "zzc"_..Number_"order"_i, "zz message "_i, .output), "message "_i_" is accepted")
	}
	For i = 1:1:3 {
		Set row = ..WaitDone(session, "zzc"_..Number_"order"_i)
		If '$IsObject(row) {
			Do $$$AssertTrue(0, "a Turn was made for message "_i)
			Continue
		}
		Do $$$AssertEquals(row.State, "done", "turn "_i_" is done")
		Set itemIds(i) = row.ItemId
		Do $$$AssertEquals(row.Attempt, 1, "turn "_i_" started once")
	}
	Set events = ..WaitEvents(session, 9)
	For i = 1:1:3 {
		Set ref = ##class(OcuTalon.Data.Ownership).TurnByClient(session, "zzc"_..Number_"order"_i).Ref
		Set count = 0
		For j = 0:1:events.%Size() - 1 {
			If (events.%Get(j).payload.ref = ref) && (events.%Get(j).payload.state = "done") Set count = count + 1
		}
		Do $$$AssertEquals(count, 1, "turn "_i_" has one done event")
	}
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set decides = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Conversation", "Decide")
	Do $$$AssertEquals(decides.%Size(), 6, "six requests reach Decide")
	Set order = ""
	For i = 0:1:decides.%Size() - 1 {
		Set body = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(decides.%Get(i).bodyId)
		If body.Kind = "turn" Set order = order_$Select(order = "": "", 1: ",")_body.ItemId
	}
	Do $$$AssertEquals(order, $Get(itemIds(1))_","_$Get(itemIds(2))_","_$Get(itemIds(3)), "the turn requests come in the order of the messages")
	Set sequence = ""
	For i = 0:1:decides.%Size() - 1 {
		Set body = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(decides.%Get(i).bodyId)
		For n = 1:1:3 {
			If body.ItemId = $Get(itemIds(n)) Set sequence = sequence_$Select(sequence = "": "", 1: ",")_n_body.Kind
		}
	}
	Do $$$AssertEquals(sequence, "1decide,1turn,2decide,2turn,3decide,3turn", "and no turn starts before the one before it is done")
	Do ..WaitNotices(trace, 3)
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set items = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "WebChatIn", "Conversation")
	Kill sessionOf
	Set itemSessions = ""
	For i = 0:1:items.%Size() - 1 {
		Set sessionOf(##class(OcuTalon.Msg.Item).%OpenId(items.%Get(i).bodyId).ItemId) = items.%Get(i).sessionId
		Set itemSessions = itemSessions_$Select(itemSessions = "": "", 1: ",")_items.%Get(i).sessionId
	}
	For i = 0:1:decides.%Size() - 1 {
		Set body = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(decides.%Get(i).bodyId)
		Set own = $Get(sessionOf(body.ItemId))
		Do $$$AssertEquals(decides.%Get(i).sessionId_"|"_body.ThreadSessionId, own_"|"_own, body.Kind_" of message "_(i \ 2 + 1)_": in its own Item's trace session, which is its thread (AD-26)")
	}
	Set notices = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Conversation", "Notify")
	Set noticeSessions = ""
	For i = 0:1:notices.%Size() - 1 {
		Set noticeSessions = noticeSessions_$Select(noticeSessions = "": "", 1: ",")_notices.%Get(i).sessionId
	}
	Do $$$AssertEquals(noticeSessions, itemSessions, "each Outbound is in its own turn's Item session, in order")
	Do ..WaitDeliveries(session, 3)
	Do $$$AssertTrue(..Handled(trace, 3), "WebChatOut has handled the three Outbounds")
	Do $$$AssertEquals(..Deliveries(session).Count(), 3, "and each leaves one Delivery row")
	Do $$$AssertEquals(..Notifications(session), 0, "with no notification event")
}

/// A turn left running and two queued turns of a session are run by the reconcile, in order, each with one reply: Reconcile
/// sends the sweep through WebChatIn, which puts the running turn back in its queue.
Method TestReconcileResumesTurns()
{
	If '..Guard() Quit
	Set session = ..Session("reconcile")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set first = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:01Z", "running", "zz resume 1", "zzc"_..Number_"resume1", 1)
	Set second = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:02Z", "queued", "zz resume 2", "zzc"_..Number_"resume2")
	Set third = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:03Z", "queued", "zz resume 3", "zzc"_..Number_"resume3")
	Do $$$AssertEquals(..Elsewhere(session), "", "no other session has a queued or running turn for the sweep to run")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Reconcile(), "the Web step reconciles")
	Kill itemIds
	For i = 1:1:3 {
		Set row = ..WaitDone(session, "zzc"_..Number_"resume"_i)
		If '$IsObject(row) {
			Do $$$AssertTrue(0, "turn "_i_" exists")
			Continue
		}
		Do $$$AssertEquals(row.State, "done", "turn "_i_" is done")
		Do $$$AssertEquals(row.ReplyCatalogKey_"|"_row.FallbackReason, "conversation.turnFallback|unusable", "turn "_i_" has the fallback reply")
		Set itemIds(i) = row.ItemId
		Do $$$AssertEquals(row.Attempt, $Select(i = 1: 2, 1: 1), "turn "_i_" started "_$Select(i = 1: "again", 1: "once"))
	}
	Set events = ..WaitEvents(session, 6)
	For i = 1:1:3 {
		Set ref = $Select(i = 1: first, i = 2: second, 1: third)
		Set count = 0
		For j = 0:1:events.%Size() - 1 {
			If (events.%Get(j).payload.ref = ref) && (events.%Get(j).payload.state = "done") Set count = count + 1
		}
		Do $$$AssertEquals(count, 1, "turn "_i_" has one done event")
	}
	Do ..WaitNotices(trace, 3)
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set decides = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Conversation", "Decide")
	Set order = ""
	For i = 0:1:decides.%Size() - 1 {
		Set body = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(decides.%Get(i).bodyId)
		If body.Kind = "turn" Set order = order_$Select(order = "": "", 1: ",")_body.ItemId
	}
	Do $$$AssertEquals(order, $Get(itemIds(1))_","_$Get(itemIds(2))_","_$Get(itemIds(3)), "one turn request each, in order")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Conversation", "Notify").%Size(), 3, "and one Outbound each")
	Do $$$AssertEquals(..RunTurnsIn(trace), 3, "the sweep's RunTurns request and the two that start the next turn are all in the session's SuperSession")
}

/// One reconcile resumes the turns of every session that has one: session A holds a running and a queued turn, session B a lone
/// running turn and session C a lone queued turn. Every turn reaches done with the fallback reply, a turn that was running on its
/// second attempt and the others on their first, with one done event and one Outbound each.
Method TestReconcileResumesEverySession()
{
	If '..Guard() Quit
	Set a = ..Session("sweepa")
	Set b = ..Session("sweepb")
	Set c = ..Session("sweepc")
	Kill sessions, turns
	Set sessions(1) = a, sessions(2) = b, sessions(3) = c
	Set turns(1) = $ListBuild(1, "sweepa1", 2)
	Set turns(2) = $ListBuild(1, "sweepa2", 1)
	Set turns(3) = $ListBuild(2, "sweepb1", 2)
	Set turns(4) = $ListBuild(3, "sweepc1", 1)
	Do ##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-01-01T10:00:01Z", "running", "zz sweep a1", "zzc"_..Number_"sweepa1", 1)
	Do ##class(OcuTalon.Test.Data.Fixture).Turn(a, "2030-01-01T10:00:02Z", "queued", "zz sweep a2", "zzc"_..Number_"sweepa2")
	Do ##class(OcuTalon.Test.Data.Fixture).Turn(b, "2030-01-01T10:00:03Z", "running", "zz sweep b1", "zzc"_..Number_"sweepb1", 1)
	Do ##class(OcuTalon.Test.Data.Fixture).Turn(c, "2030-01-01T10:00:04Z", "queued", "zz sweep c1", "zzc"_..Number_"sweepc1")
	Do $$$AssertEquals(..Elsewhere(a_","_b_","_c), "", "no other session has a queued or running turn for the sweep to run")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Reconcile(), "the Web step reconciles")
	For i = 1:1:4 {
		Set owner = $List(turns(i), 1)
		Set label = "turn "_$List(turns(i), 2)
		Set row = ..WaitDone(sessions(owner), "zzc"_..Number_$List(turns(i), 2))
		If '$IsObject(row) {
			Do $$$AssertTrue(0, label_" exists")
			Continue
		}
		Do $$$AssertEquals(row.State_"|"_row.ReplyCatalogKey_"|"_row.FallbackReason, "done|conversation.turnFallback|unusable", label_": done with the fallback reply")
		Do $$$AssertEquals(row.Attempt, $List(turns(i), 3), label_": started "_$Select($List(turns(i), 3) = 2: "again", 1: "once"))
	}
	For owner = 1:1:3 {
		Set expected = $Select(owner = 1: 2, 1: 1)
		Set events = ..WaitEvents(sessions(owner), expected * 2)
		Set done = 0
		For j = 0:1:events.%Size() - 1 {
			If events.%Get(j).payload.state = "done" Set done = done + 1
		}
		Do $$$AssertEquals(done, expected, "session "_$Char(64 + owner)_" has one done event for each of its "_expected_" turns")
		Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(sessions(owner)).TraceRef
		Do ..WaitNotices(trace, expected)
		Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
		Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Conversation", "Notify").%Size(), expected, "session "_$Char(64 + owner)_" has one Outbound for each of its turns")
		Do $$$AssertEquals(..RunTurnsIn(trace), expected, "session "_$Char(64 + owner)_": the sweep's RunTurns request"_$Select(expected = 2: " and the one that starts its second turn are", 1: " is")_" in its SuperSession (AD-26)")
		Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "WebChatIn", "Conversation").%Size(), 0, "session "_$Char(64 + owner)_": and the sweep request itself, which is for every session, is not")
	}
}

/// --- helpers ---
/// Sends a message of the page through WebChatIn, created in this process as the REST surface creates it; output is the
/// service's answer.
Method Send(session As %String, clientId As %String, text As %String, Output output As %String) As %Status [ Private ]
{
	Set output = ""
	Set post = ##class(OcuTalon.Channel.WebChat.Post).%New()
	Set post.SessionRef = session
	Set post.ClientId = clientId
	Set post.Text = text
	Set sc = ##class(Ens.Director).CreateBusinessService("WebChatIn", .service)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Quit service.ProcessInput(post, .output)
}

/// The Turn of the clientId once it is done, opened afresh; after WAIT seconds, the Turn as it is, or "" when there is none.
Method WaitDone(session As %String, clientId As %String) As OcuTalon.Data.Turn [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	Set row = ""
	For {
		Kill row
		Set row = ##class(OcuTalon.Data.Ownership).TurnByClient(session, clientId)
		If $IsObject(row) && (row.State = "done") Quit
		If $ZHorolog > end Quit
		Hang 0.25
	}
	Quit row
}

/// The chat.message events of the session's stream, once there are count of them or WAIT seconds have passed.
Method WaitEvents(session As %String, count As %Integer) As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(session, "chat.message", count, ..#WAIT)
}

/// Waits until count requests have gone from Conversation to Notify in the SuperSession, or WAIT seconds have passed:
/// Conversation sends the Outbound after it saves the turn and publishes its last event, so neither signals it.
Method WaitNotices(trace As %String, count As %Integer) [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
		Set found = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Conversation", "Notify").%Size()
		If (found >= count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
}

/// Waits until the session has count Delivery rows or WAIT seconds have passed: the Outbound reaches WebChatOut after the turn is
/// done.
Method WaitDeliveries(session As %String, count As %Integer) [ Private ]
{
	Do ##class(OcuTalon.Test.Core.Observe).WaitDeliveries(session, count, ..#WAIT)
}

/// 1 once WebChatOut has handled count Outbounds that Notify sent it in the SuperSession, so that what it would publish has been
/// published; 0 after WAIT seconds.
Method Handled(trace As %String, count As %Integer) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "Notify", "WebChatOut", count, ..#WAIT)
}

/// The Delivery rows of the session, whatever their kind, in the order they were recorded (the test reads the table directly,
/// as a test may).
Method Deliveries(session As %String) As %ListOfObjects [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
}

/// The number of notification events on the session's stream.
Method Notifications(session As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(session, "notification").%Size()
}

/// The sessions, other than the given ones (comma-separated Refs), that have a queued or running turn, comma-separated: a
/// sweep would run their turns too.
Method Elsewhere(mine As %String) As %String [ Private ]
{
	Set others = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT %EXACT(SessionRef) AS Owner FROM OcuTalon_Data.Turn WHERE State IN ('queued', 'running')")
	While result.%Next() {
		Set owner = result.%Get("Owner")
		If '$Find(","_mine_",", ","_owner_",") Set others = others_$Select(others = "": "", 1: ",")_owner
	}
	Quit others
}

/// The number of RunTurns requests that Conversation sent itself in the SuperSession.
Method RunTurnsIn(trace As %String) As %Integer [ Private ]
{
	Set runs = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "Conversation", "Conversation")
	Set count = 0
	For i = 0:1:runs.%Size() - 1 {
		If runs.%Get(i).bodyClass = "OcuTalon.Core.Msg.RunTurns" Set count = count + 1
	}
	Quit count
}

}
