/// End-to-end tests of the turn pipeline over the running production (Story 2.4; AD-1, AD-14, AD-26, AD-30). THIS CLASS RUNS
/// IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the running OcuTalon.Production, which a slot never has. Where the
/// production does not run, every test fails with that reason, so that a broken start can never give a green shard. A message
/// goes through Ens.Director.CreateBusinessService("WebChatIn") and ProcessInput, as the REST surface sends it, to the real
/// Conversation and the Decide of Epic 0, which answers an error status until Lane A builds it (Story 1.3). So every turn ends
/// in the fallback unusable; the unit tests of OcuTalon.Test.Core.ConversationTurns cover every other reply shape.
///   - TestTurnThroughProduction: a message becomes a Turn that reaches done within 20 seconds with the text, the ClientId,
///     the ItemId, the Item's header as the trace target and the fallback key and reason; the session's stream holds the
///     three chat.message events; the Item, the two Decide requests (decide and turn, in the Item's trace session) and the
///     one Outbound to Notify are all in the session's SuperSession (the TraceRef);
///   - TestRepeatQueuesNothing: a second message with the same clientId is accepted as a duplicate and queues nothing;
///   - TestTurnsRunInOrder: three messages are three turns that run one after another, in the order they were posted, each
///     with one done event;
///   - TestReconcileResumesTurns: a running turn and two queued turns are run, in order, by Install.Step.Web.Reconcile(),
///     each with one reply.
/// The fixture sessions come from Test.Data.Fixture. The run's number is n from ^OcuTalonTest("ConversationProduction","n")
/// (never reset). OnAfterAllTests removes the run's headers, bodies and event-log rows by the TraceRefs of its sessions
/// (Fixture.RemoveMessages), its turns and events, and its fixture rows.
Class OcuTalon.Test.Core.ConversationProduction Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// Seconds to wait for a turn to be done.
Parameter WAIT = 20;

/// The run's number.
Property Number As %Integer;

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 200);

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the fixture sessions of the run, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The SuperSessions of the run's messages.
Property Supers As %DynamicArray;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Number = $Increment(^OcuTalonTest("ConversationProduction", "n"))
	Set ..Refs = ""
	Set ..Sessions = ""
	Set ..Supers = []
	Set ..Missing = ""
	If '##class(Ens.Director).IsProductionRunning(.name) {
		Set ..Missing = "No production runs in "_$Namespace_": this class runs in throwaways and CI only (Rule 21)"
	} ElseIf name '= ..#PRODUCTION {
		Set ..Missing = "The production that runs is "_name_", not "_..#PRODUCTION
	}
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	If ..Missing = "" Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Supers)
	Do ..AdoptTurns()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Quit $SYSTEM.Status.OK()
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
	Do $$$AssertEquals(..States(events), "queued,running,done", "the stream holds the three stages, once each")
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
	Do $$$AssertEquals(..States(events), "queued,running,done", "and its three events")
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
}

/// --- helpers ---
/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// A fixture session; its Ref is kept for the clean-up, and its TraceRef is a SuperSession of the run.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzprodconv"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Do ..Supers.%Push(##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef)
	Quit ref
}

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
	Set end = $ZHorolog + ..#WAIT
	For {
		Set found = []
		Set events = ##class(OcuTalon.Live.Event).Since(session, 0, 200, "session")
		Set iterator = events.%GetIterator()
		While iterator.%GetNext(, .event) {
			If event.type = "chat.message" Do found.%Push(event)
		}
		If (found.%Size() >= count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit found
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

/// The states of the events, comma-separated.
Method States(events As %DynamicArray) As %String [ Private ]
{
	Set states = ""
	For i = 0:1:events.%Size() - 1 {
		Set states = states_$Select(states = "": "", 1: ",")_events.%Get(i).payload.state
	}
	Quit states
}

/// Adds the turns of the fixture sessions that Conversation made to the refs of the run, recorded for Fixture.Clean.
Method AdoptTurns() [ Private ]
{
	For i = 1:1:$Length(..Sessions, ",") {
		Set session = $Piece(..Sessions, ",", i)
		If session = "" Continue
		Set turns = ##class(OcuTalon.Data.Ownership).Turns(session, .sc)
		For j = 1:1:turns.Count() {
			Set ref = ##class(OcuTalon.Test.Data.Fixture).Adopt(turns.GetAt(j))
			If ('$Find(","_..Refs_",", ","_ref_",")) Set ..Refs = ..Refs_","_ref
		}
	}
}

}
