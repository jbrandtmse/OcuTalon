/// End-to-end tests of the route of an untrusted item and of a notification over the running production (Story 2.7; AD-1, AD-14,
/// AD-22, AD-26, AD-30, AD-32, AD-33). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs the running
/// OcuTalon.Production, which a slot never has. Where the production does not run, every test fails with that reason, so that a
/// broken start can never give a green shard. A message is sent from a SimMailboxIn host, created in this process with
/// Ens.Director.CreateBusinessService and given the session's TraceRef as its SuperSession, to the item under test, and the
/// tests wait up to WAIT seconds for what the route leaves: Delivery rows, live events and message headers. A throwaway has no
/// model key, so the real Decide answers an Item with its fallback no_key (one Decision row of kind decide, tellnow, with a
/// DecisionRef, and a decision event) and Intake keeps that answer; the unit tests of OcuTalon.Test.Core.Intake cover every
/// other answer.
///   - TestUntrustedItemReachesTheWebChat: a mail Item goes to Decide, and Intake sends the fallback ItemDecision (no_key, with
///     the decision's Ref) to OutcomeRouter, which sends a Notification to Notify, which sends it to WebChatOut. The session has
///     one tell-now card with notice.tellNowFallback's text, the reason and the DecisionRef, one decision event and one
///     notification event, every hop is in the session's SuperSession, and there is no Turn row and no chat.message event
///     (NFR-14);
///   - TestEachOutcomeThroughTheRouter: ItemDecisions of each outcome, with and without a CatalogKey, sent into OutcomeRouter:
///     ignore leaves nothing, digest goes to DigestStore, tellnow and act each leave a card;
///   - TestEvalItemWritesNoDeliveryOrEvent: an Item owned by eval reaches EvalSink and nothing else, and leaves no Delivery row
///     and no live event (AD-22); the decide row that the real Decide records for it (owner eval) is adopted for the clean-up;
///   - TestReplyRecordsItsDeliveryOnly: an Outbound sent to Notify reaches WebChatOut, which records its Delivery row and
///     publishes no notification event.
/// The guard, the fixture sessions, the run's number (^OcuTalonTest("RoutingProduction","n")) and the clean-up are those of
/// Test.Core.InProduction; the clean-up also removes the Delivery rows of the fixture sessions and the decide rows that the tests
/// adopt.
Class OcuTalon.Test.Core.RoutingProduction Extends OcuTalon.Test.Core.InProduction
{

/// The start of the user name of each fixture session.
Parameter SESSIONPREFIX = "zzprodroute";

/// Seconds to wait for what a route leaves.
Parameter WAIT = 20;

/// Seconds to wait to be sure that a route left nothing.
Parameter QUIET = 4;

/// A mail Item from Dana with the subject Invoice is decided by the real Decide as the fallback no_key (one Decision row of
/// kind decide, owned by the session, which the clean-up adopts), and the card it makes reaches the web chat: one Delivery row
/// with the text of notice.tellNowFallback and the row's Ref as its DecisionRef, one decision event, one notification event with
/// the same card and decision, every hop in the session's SuperSession and in the Item's trace session, and no Turn row and no
/// chat.message event.
Method TestUntrustedItemReachesTheWebChat()
{
	If '..Guard() Quit
	Set session = ..Session("item")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set item = ..Item(session)
	Do $$$AssertStatusOK(..SendTo("Intake", item, trace), "the Item is sent from a SimMailboxIn host to Intake")
	Set card = ..WaitCard(session)
	If '$IsObject(card) {
		Do $$$AssertTrue(0, "a card reached the web chat within "_..#WAIT_" seconds")
		Quit
	}
	Set decide = ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexOpen(item.ItemId, "decide")
	Do $$$AssertTrue($IsObject(decide), "Decide recorded one decision of kind decide for the Item")
	If '$IsObject(decide) Quit
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Adopt(decide)
	Do $$$AssertEquals(decide.OwnerRef_"|"_decide.Outcome_"|"_decide.Fallback_"|"_decide.FallbackReason, session_"|tellnow|1|no_key", "the decision is the session's fallback no_key, a tell now")
	Do $$$AssertEquals(card.Kind_"|"_card.Channel_"|"_card.FallbackReason_"|"_card.DecisionRef_"|"_card.ApprovalRef, "tellnow|web|no_key|"_decide.Ref_"|", "one tell-now card, a fallback with the reason no_key and the decision's Ref")
	Do $$$AssertEquals(card.Text, "zz Dana: Invoice"_$Char(10)_"Why now: no model key is set", "with the text of notice.tellNowFallback: the summary, then the words of the reason")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 1, "the session has one card")
	Set decisions = ..WaitEvents(session, "decision", 1)
	Do $$$AssertEquals(decisions.%Size(), 1, "one decision event is published")
	If decisions.%Size() = 1 Do $$$AssertEquals(decisions.%Get(0).payload.ref, decide.Ref, "for the Item's decision")
	Set events = ..WaitEvents(session, "notification", 1)
	Do $$$AssertEquals(events.%Size(), 1, "one notification event is published")
	If events.%Size() = 1 {
		Set payload = events.%Get(0).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.kind_"|"_payload.text_"|"_payload.whyNow_"|"_payload.fallbackReason, card.ChannelMessageId_"|tellnow|zz Dana: Invoice|Why now: no model key is set|no_key", "carrying the card")
		Do $$$AssertEquals(payload.decisionRef_"|"_payload.decision.ref, decide.Ref_"|"_decide.Ref, "and the decision")
	}
	Do ..WaitHops(trace, "Notify", "WebChatOut", 1)
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set item1 = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "SimMailboxIn", "Intake")
	Do $$$AssertEquals(item1.%Size(), 1, "one Item request header goes from SimMailboxIn to Intake, in the session's SuperSession")
	Set requests = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Intake", "Decide")
	Do $$$AssertEquals(requests.%Size(), 1, "one request goes from Intake to Decide (an item with the fallback never runs a turn)")
	If requests.%Size() = 1 {
		Set body = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(requests.%Get(0).bodyId)
		Do $$$AssertEquals(body.Kind_"|"_body.Provenance_"|"_body.ItemId_"|"_body.OwnerRef_"|"_body.Summary_"|"_body.Channel, "decide|untrusted|"_item.ItemId_"|"_session_"|zz Dana: Invoice|mailbox", "a decide request for the untrusted Item, with its summary")
		Do $$$AssertEquals(body.TraceRef_"|"_requests.%Get(0).sessionId_"|"_body.ThreadSessionId, trace_"|"_item1.%Get(0).sessionId_"|"_item1.%Get(0).sessionId, "in the session's trace, the Item's trace session and thread (AD-26)")
	}
	For hop = "Intake>OutcomeRouter", "OutcomeRouter>Notify", "Notify>WebChatOut" {
		Set found = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, $Piece(hop, ">", 1), $Piece(hop, ">", 2))
		Do $$$AssertEquals(found.%Size(), 1, "one request goes from "_$Piece(hop, ">", 1)_" to "_$Piece(hop, ">", 2)_", in the session's SuperSession")
		If found.%Size() = 1 Do $$$AssertEquals(found.%Get(0).sessionId, item1.%Get(0).sessionId, "in the Item's trace session")
	}
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "OutcomeRouter", "Notify")
	If sent.%Size() = 1 {
		Set notification = ##class(OcuTalon.Msg.Notification).%OpenId(sent.%Get(0).bodyId)
		Do $$$AssertEquals(notification.CatalogKey_"|"_notification.Slots_"|"_notification.DecisionRef, "notice.tellNowFallback|{""whatHappened"":""zz Dana: Invoice"",""reason"":""no_key""}|"_decide.Ref, "the Notification is notice.tellNowFallback with the summary and the reason, and the decision")
	}
	Set routed = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Intake", "OutcomeRouter")
	If routed.%Size() = 1 {
		Set decision = ##class(OcuTalon.Msg.ItemDecision).%OpenId(routed.%Get(0).bodyId)
		Do $$$AssertEquals(decision.ItemId_"|"_decision.OwnerRef_"|"_decision.Outcome_"|"_decision.Fallback_"|"_decision.FallbackReason_"|"_decision.DecisionRef, item.ItemId_"|"_session_"|tellnow|1|no_key|"_decide.Ref, "the ItemDecision is the fallback, with the decision's Ref")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Intake", "Conversation").%Size() + ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Intake", "Notify").%Size(), 0, "Intake sends nothing to Conversation or Notify")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Turns(session).Count(), 0, "no Turn row is made")
	Do $$$AssertEquals(..WaitEvents(session, "chat.message", 0).%Size(), 0, "and no chat.message event is published")
}

/// ItemDecisions sent into OutcomeRouter: an ignore leaves nothing (no request leaves the router); a digest goes to DigestStore
/// and leaves no card; a tell now and an act each leave one card with the summary and the first reason line of the session's own
/// Decision row, or with the two lines of the CatalogKey they carry.
Method TestEachOutcomeThroughTheRouter()
{
	If '..Guard() Quit
	For outcome = "ignore", "digest", "tellnow", "act" {
		For keyed = 0, 1 {
			Set label = outcome_$Select(keyed: " with a CatalogKey", 1: "")
			Set session = ..Session("out"_outcome_keyed)
			Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
			Set decisionRef = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", , {"Outcome": (outcome), "Reasons": ("zz first."_$Char(10)_"zz second.")})
			Set ..Refs = ..Refs_","_decisionRef
			Set decision = ##class(OcuTalon.Msg.ItemDecision).%New()
			Set decision.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
			Set decision.OwnerRef = session
			Set decision.Channel = "mailbox"
			Set decision.Summary = "zz Dana: Invoice"
			Set decision.DecisionRef = decisionRef
			Set decision.Outcome = outcome
			If keyed {
				Set decision.CatalogKey = "watch.productionStopped"
				Set decision.Slots = "{""production"":""Orders"",""time"":""2026-10-16T18:12:00Z""}"
			}
			Do $$$AssertStatusOK(..SendTo("OutcomeRouter", decision, trace), label_": the ItemDecision is sent to OutcomeRouter")
			If (outcome = "tellnow") || (outcome = "act") {
				Set card = ..WaitCard(session)
				If '$IsObject(card) {
					Do $$$AssertTrue(0, label_": a card reached the web chat within "_..#WAIT_" seconds")
					Continue
				}
				Do $$$AssertEquals(card.Kind_"|"_card.DecisionRef_"|"_card.FallbackReason, "tellnow|"_decisionRef_"|", label_": one tell-now card with the decision")
				If keyed {
					Do $$$AssertEquals($Piece(card.Text, $Char(10), 2), "Why now: you asked me to watch the Orders production.", label_": the key's own Why now line")
				} Else {
					Do $$$AssertEquals(card.Text, "zz Dana: Invoice"_$Char(10)_"Why now: zz first.", label_": the summary and the first reason line")
				}
				Do ..WaitHops(trace, "Notify", "WebChatOut", 1)
				Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
				Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "OutcomeRouter", "Notify").%Size(), 1, label_": one Notification goes from OutcomeRouter to Notify")
				Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "OutcomeRouter", "DigestStore").%Size(), 0, label_": and none to DigestStore")
			} ElseIf outcome = "digest" {
				Do ..WaitHops(trace, "OutcomeRouter", "DigestStore", 1)
				Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
				Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "OutcomeRouter", "DigestStore")
				Do $$$AssertEquals(sent.%Size(), 1, label_": the ItemDecision goes to DigestStore")
				If sent.%Size() = 1 Do $$$AssertEquals(sent.%Get(0).bodyClass, "OcuTalon.Msg.ItemDecision", label_": unchanged")
				Do $$$AssertTrue(..Processed(trace), label_": the router has handled the ItemDecision")
				Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
				Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "OutcomeRouter", "Notify").%Size(), 0, label_": and nothing goes to Notify")
				Do $$$AssertEquals(..Deliveries(session).Count(), 0, label_": no card is made")
			} Else {
				Do $$$AssertTrue(..Processed(trace), label_": the router has handled the ItemDecision")
				Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
				Set outgoing = 0
				For i = 0:1:headers.%Size() - 1 {
					If headers.%Get(i).source = "OutcomeRouter" Set outgoing = outgoing + 1
				}
				Do $$$AssertEquals(outgoing, 0, label_": the router sends nothing")
				Do $$$AssertEquals(..Deliveries(session).Count(), 0, label_": no card is made")
			}
		}
	}
}

/// An Item owned by eval goes through Intake to EvalSink and nowhere else: no request to OutcomeRouter, Notify or WebChatOut,
/// no Delivery row for the owner eval or the session whose trace the host used, and no live event on that session's stream. The
/// stub EvalSink answers an error status, which the route ignores. The real Decide records its decide row for the Item (owner
/// eval), which the test adopts, so that the clean-up leaves no Decision row behind.
Method TestEvalItemWritesNoDeliveryOrEvent()
{
	If '..Guard() Quit
	Set session = ..Session("eval")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set item = ..Item("eval")
	Set item.SourceItemId = "zzevalcase"
	Set before = ..Count("eval")
	Do $$$AssertStatusOK(..SendTo("Intake", item, trace), "the Item of the owner eval is sent to Intake")
	Do ..WaitHops(trace, "Intake", "EvalSink", 1)
	Hang ..#QUIET
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set sink = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Intake", "EvalSink")
	Do $$$AssertEquals(sink.%Size(), 1, "the ItemDecision goes from Intake to EvalSink")
	If sink.%Size() = 1 {
		Set decision = ##class(OcuTalon.Msg.ItemDecision).%OpenId(sink.%Get(0).bodyId)
		Do $$$AssertEquals(decision.OwnerRef_"|"_decision.SourceItemId_"|"_decision.ItemId, "eval|zzevalcase|"_item.ItemId, "for the owner eval, with the case id")
	}
	For target = "OutcomeRouter", "Notify", "WebChatOut", "SimPhoneOut", "TelegramOut", "DigestStore" {
		Set found = 0
		For i = 0:1:headers.%Size() - 1 {
			If (headers.%Get(i).target = target) && (headers.%Get(i).type = 1) Set found = found + 1
		}
		Do $$$AssertEquals(found, 0, "nothing is sent to "_target)
	}
	Set decide = ##class(OcuTalon.Bridge.Data.Decision).ItemIdKindIndexOpen(item.ItemId, "decide")
	Do $$$AssertTrue($IsObject(decide), "Decide recorded its decision for the Item of the owner eval, which the clean-up removes")
	If $IsObject(decide) Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Adopt(decide)
	Do $$$AssertEquals(..Count("eval"), before, "no Delivery row for the owner eval")
	Do $$$AssertEquals(..Deliveries(session).Count(), 0, "and none for the session")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(session), 0, "no live event on the session's stream")
}

/// An Outbound sent to Notify reaches WebChatOut, which records its Delivery row for the session (the web, no ChannelMessageId, its
/// DecisionRef) and publishes no notification event; Notify sends it nowhere else while Telegram is not included.
Method TestReplyRecordsItsDeliveryOnly()
{
	If '..Guard() Quit
	Set session = ..Session("reply")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set outbound = ##class(OcuTalon.Msg.Outbound).%New()
	Set outbound.SessionRef = session
	Set outbound.OriginChannel = "web"
	Set outbound.Text = "zz a reply"
	Set outbound.DecisionRef = "ZzReplyDecision"
	Do $$$AssertStatusOK(..SendTo("Notify", outbound, trace), "the Outbound is sent to Notify")
	Do ..WaitDeliveries(session, 1)
	Set rows = ..Deliveries(session)
	Do $$$AssertEquals(rows.Count(), 1, "one Delivery row is recorded")
	If rows.Count() = 1 {
		Set row = rows.GetAt(1)
		Do $$$AssertEquals(row.OwnerRef_"|"_row.Channel_"|"_row.ChannelMessageId_"|"_row.Kind_"|"_row.Text_"|"_row.DecisionRef, session_"|web||||ZzReplyDecision", "the reply's row: the web, its DecisionRef, no message id, kind or text")
	}
	Do $$$AssertTrue(##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "Notify", "WebChatOut", 1, ..#WAIT), "WebChatOut has handled the Outbound")
	Do $$$AssertEquals(..WaitEvents(session, "notification", 0).%Size(), 0, "and published no notification event")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Notify", "WebChatOut").%Size(), 1, "Notify sends it to WebChatOut")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "Notify", "TelegramOut").%Size(), 0, "and not to TelegramOut")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentNotices(session, 10).Count(), 0, "the row is not a card of the chat")
}

/// --- helpers ---
/// An untrusted mail Item of the owner from "zz Dana" with the subject Invoice.
Method Item(owner As %String) As OcuTalon.Msg.Item [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SessionRef = owner
	Set item.Channel = "mailbox"
	Set item.Provenance = "untrusted"
	Set item.Sender = "zz Dana"
	Set item.Subject = "Invoice"
	Set item.Text = "zz body"
	Quit item
}

/// Sends the message to the item from a SimMailboxIn host created in this process, with the SuperSession given.
Method SendTo(target As %String, message As %Library.Persistent, superSession As %String) As %Status [ Private ]
{
	Set sc = ##class(Ens.Director).CreateBusinessService("SimMailboxIn", .service)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set service.%SuperSession = superSession
	Quit service.SendRequestAsync(target, message)
}

/// The session's newest card once there is one, opened afresh; after WAIT seconds, "".
Method WaitCard(session As %String) As OcuTalon.Data.Delivery [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	Set card = ""
	For {
		Set rows = ##class(OcuTalon.Data.Ownership).RecentNotices(session, 1)
		If rows.Count() = 1 Set card = rows.GetAt(1)
		If $IsObject(card) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit card
}

/// Waits until the session has count Delivery rows or WAIT seconds have passed.
Method WaitDeliveries(session As %String, count As %Integer) [ Private ]
{
	Do ##class(OcuTalon.Test.Core.Observe).WaitDeliveries(session, count, ..#WAIT)
}

/// 1 once the router has handled the ItemDecision that a SimMailboxIn host sent it in the SuperSession, so that what it sent on
/// has been sent; 0 after WAIT seconds.
Method Processed(trace As %String) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).WaitProcessed(trace, "SimMailboxIn", "OutcomeRouter", 1, ..#WAIT)
}

/// Waits until count requests have gone from the source item to the target item in the SuperSession, or WAIT seconds have
/// passed.
Method WaitHops(trace As %String, source As %String, target As %String, count As %Integer) [ Private ]
{
	Set end = $ZHorolog + ..#WAIT
	For {
		Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
		If (##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, source, target).%Size() >= count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
}

/// The events of the type on the session's stream, once there are count of them or WAIT seconds have passed (with count 0, now).
Method WaitEvents(session As %String, type As %String, count As %Integer) As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(session, type, count, $Select(count > 0: ..#WAIT, 1: 0))
}

/// The Delivery rows of the session, whatever their kind, in the order they were recorded (the test reads the table directly,
/// as a test may).
Method Deliveries(session As %String) As %ListOfObjects [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
}

/// The number of Delivery rows of the owner.
Method Count(owner As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).DeliveryCount(owner)
}

}
