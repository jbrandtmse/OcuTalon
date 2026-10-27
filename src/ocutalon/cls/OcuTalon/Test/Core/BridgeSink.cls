/// Tests of BridgeSink (Stories 2.6 and 2.8; AD-31, AD-33), which turns the bridge's decision.recorded, turn.step and
/// approval.* events into live events. The tests call OnEvent directly, with fixture rows from Test.Data.Fixture, and read the
/// session's stream.
///   - TestDecisionRecordedPublishesTheDecision: a decide and a turn decision of a session each give one decision event with
///     every field of Decision.FromRow;
///   - TestDecisionOfATurnPublishesTheTurnsTarget (Story 2.13, DW-129): the decision of a chat turn's Item is published with the
///     turn's header and item indexes, and any other decision with its TraceSessionId and no index;
///   - TestEvalAndInstancePublishNothing, TestAnotherSessionsDecisionPublishesNothing: a decision of eval, of instance or of
///     another session is published nowhere;
///   - TestBadPayloadsPublishNothing: an empty or unknown ref, a payload that is not an object, an approval.* event for a
///     ref that is no request, budget.capped and an unknown type publish nothing;
///   - TestApprovalEventsPublishTheRequest, TestApprovalOwnersThatPublishNothing: each of the five approval.* types gives one
///     approval event with Approval.FromRow's fields on the owning session's stream (the incident's trace target included, for the
///     recipient it is published to), and a request of eval, of another session or that does not exist is published nowhere;
///   - TestInstanceApprovalReachesEveryWatcher, TestFailedWatcherReadIsLoud (DW-68): an instance request reaches each session
///     that watches its incident's production and no other, none with onlineDemo on or for an unnoticed incident; a failed
///     read of the recipients logs one warning and publishes nothing, and nobody watching logs nothing;
///   - TestAFailedRecipientReadDoesNotStopTheOthers: a recipient whose read fails logs one warning naming the event, the request and
///     the recipient, and the next recipient still gets its event;
///   - TestOnlineDemoStillPublishesASessionsOwnRequest: with onlineDemo on, a session's own request is published to it, as the
///     demo's approval step needs, and an instance request still is not;
///   - TestApprovalNeverWaitsMoreThanASecond: an approval event waits about a second for a busy stream, as every event does; of
///     two watchers of an instance request, the one whose stream is free still gets its event;
///   - TestTurnStepForTheRunningTurn, TestTurnStepWithNoRunningTurn, TestTurnStepOfAnotherItem, TestTurnStepOfARetry (DW-128):
///     turn.step carries the running turn's Ref, the decision's Ref and the trimmed label, and only for the running turn of the
///     item the bridge context is for, or for the SessionBroken retry of that turn (Conversation.RetryItemId of its ItemId);
///   - TestNeverWaitsMoreThanASecond: a stream whose lock another job holds drops the event after about a second;
///   - TestNeverFailsItsCaller: OnEvent returns OK for every type, owner and payload, and for a handler that throws.
/// Every row comes from Test.Data.Fixture, and each test removes its own rows by Ref. The events are read from the fixture
/// session's own stream, or, for the owners that have no stream here, searched by the decision's Ref in every event's payload,
/// so that a concurrent event of another test cannot disturb the result. The warnings that BridgeSink logs are removed.
Class OcuTalon.Test.Core.BridgeSink Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The number of the newest row of the event log when the test began.
Property LogMark As %Integer;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Number = $Increment(^OcuTalonTest("BridgeSink", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Set ..Refs = ""
	Set ..LogMark = ..LastLog()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(OcuTalon.Bridge.Context).End()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceClass IN (?, ?, ?)", ..LogMark, "OcuTalon.Core.BridgeSink", "OcuTalon.Test.Core.BridgeSinkProbe", "OcuTalon.Test.Core.BridgeSinkRefusedProbe")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("BridgeSink", "hold")
	Quit $SYSTEM.Status.OK()
}

/// decision.recorded for a decision of the session publishes one decision event on its stream with every field of the row:
/// the outcome, the reasons, the confidence, the fallback flag and reason, the four token counts, the cost, the model's display
/// name, the agent steps and the duration, the Ref, the trace target, the item and its summary. A decision of kind turn is
/// published the same way.
Method TestDecisionRecordedPublishesTheDecision()
{
	Set session = ..Session("decision")
	Set item = "ZzSinkItem"_..Number
	Set triage = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", "2030-01-01T10:00:00Z", {"ItemId": (item), "Summary": "zz summary of the item", "Outcome": "act", "Reasons": "zz reason one\nzz reason two", "Confidence": 0.92, "Fallback": 1, "FallbackReason": "timeout", "InputTokens": 1084, "OutputTokens": 312, "CacheReadTokens": 20, "CacheWriteTokens": 4, "CostUSD": 0.0003, "Model": "claude-haiku-5-5", "AgentStepCount": 3, "DurationMs": 3400, "TraceSessionId": 4321})
	Set reply = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "turn", "2030-01-01T10:00:05Z", {"ItemId": (item), "Outcome": "digest", "Model": "claude-sonnet-5-5"})
	Set ..Refs = ..Refs_","_triage_","_reply
	Do $$$AssertEquals(..Events(session).%Size(), 0, "the stream is empty to begin with")

	Do $$$AssertEquals(..Holding(triage), 0, "no event holds the decision's Ref before it is published")
	Do $$$AssertStatusOK(..Sink("decision.recorded", session, {"ref": (triage)}), "OnEvent returns OK")
	Do $$$AssertEquals(..Holding(triage), 1, "the search finds the event that holds the decision's Ref")
	Set events = ..Events(session)
	Do $$$AssertEquals(events.%Size(), 1, "one event is published")
	Set event = events.%Get(0)
	Do $$$AssertEquals(event.type, "decision", "of type decision")
	Set payload = event.payload
	Do $$$AssertEquals(payload.ref_"|"_payload.kind_"|"_payload.itemId_"|"_payload.itemSummary, triage_"|decide|"_item_"|zz summary of the item", "the ref, the kind, the item and its summary")
	Do $$$AssertEquals(payload.outcome_"|"_payload.reasons, "act|zz reason one"_$Char(10)_"zz reason two", "the outcome and the reasons, one per line")
	Do $$$AssertEquals(+payload.confidence_"|"_payload.fallback_"|"_payload.fallbackReason, ".92|1|timeout", "the confidence, the fallback flag and its reason")
	Do $$$AssertEquals(payload.%GetTypeOf("fallback"), "boolean", "the flag is a boolean")
	Do $$$AssertEquals(+payload.inputTokens_"|"_+payload.outputTokens_"|"_+payload.cacheReadTokens_"|"_+payload.cacheWriteTokens, "1084|312|20|4", "the four token counts")
	Do $$$AssertEquals(+payload.costUSD_"|"_payload.model, ".0003|Claude Haiku 5.5", "the cost and the model's display name")
	Do $$$AssertEquals(+payload.agentStepCount_"|"_+payload.durationMs, "3|3400", "the agent steps and the duration")
	Do $$$AssertEquals(payload.traceHeaderId_"|"_payload.traceNamespace, "4321|"_$Namespace, "the trace target is the decision's TraceSessionId in this namespace")
	Do $$$AssertEquals(payload.recordedAt, "2030-01-01T10:00:00Z", "when it was recorded")

	Do $$$AssertStatusOK(..Sink("decision.recorded", session, {"ref": (reply)}), "a turn decision: OnEvent returns OK")
	Set events = ..Events(session)
	Do $$$AssertEquals(events.%Size(), 2, "a second event is published")
	Set payload = events.%Get(1).payload
	Do $$$AssertEquals(events.%Get(1).type_"|"_payload.ref_"|"_payload.kind_"|"_payload.outcome_"|"_payload.model, "decision|"_reply_"|turn|digest|Claude Sonnet 5.5", "for the turn decision too, whatever its kind")
}

/// decision.recorded for the decision of a chat turn's Item publishes the turn's target (DW-129): the turn's TraceHeaderId and
/// its two item indexes, in place of the decision's TraceSessionId. A decision of an Item that is no turn, and a turn with no
/// header, publish the decision's TraceSessionId and no index. The target is the same as the one `/state` serves for the
/// decision, since both are Decision.FromRow.
Method TestDecisionOfATurnPublishesTheTurnsTarget()
{
	Set session = ..Session("turntarget")
	Set turnRef = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:00Z")
	Set headless = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:01Z")
	Set turn = ##class(OcuTalon.Data.Turn).RefIndexOpen(turnRef)
	Set turn.TraceHeaderId = 9001
	Set turn.TraceItemIndex = 46
	Set turn.TraceItemIndexNoEvents = 30
	Do $$$AssertStatusOK(turn.%Save(), "the turn has its header and positions")
	Set ofTurn = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", "2030-01-01T10:00:02Z", {"ItemId": (turn.ItemId), "TraceSessionId": 4321})
	Set ofHeadless = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", "2030-01-01T10:00:03Z", {"ItemId": (##class(OcuTalon.Data.Turn).RefIndexOpen(headless).ItemId), "TraceSessionId": 4322})
	Set ofItem = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", "2030-01-01T10:00:04Z", {"TraceSessionId": 4323})
	Set ..Refs = ..Refs_","_turnRef_","_headless_","_ofTurn_","_ofHeadless_","_ofItem

	Do $$$AssertStatusOK(..Sink("decision.recorded", session, {"ref": (ofTurn)}), "the turn's decision: OnEvent returns OK")
	Do $$$AssertStatusOK(..Sink("decision.recorded", session, {"ref": (ofHeadless)}), "a turn with no header: OnEvent returns OK")
	Do $$$AssertStatusOK(..Sink("decision.recorded", session, {"ref": (ofItem)}), "an Item that is no turn: OnEvent returns OK")
	Set events = ..Events(session)
	Do $$$AssertEquals(events.%Size(), 3, "each is published once")
	Set payload = events.%Get(0).payload
	Do $$$AssertEquals(payload.ref_"|"_payload.traceHeaderId_"|"_payload.traceNamespace_"|"_payload.traceItemIndex_"|"_payload.traceItemIndexNoEvents, ofTurn_"|9001|"_$Namespace_"|46|30", "the turn's decision carries the turn's target and positions, not its TraceSessionId 4321")
	Set expected = ##class(OcuTalon.Live.Payload.Decision).FromRow(##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(ofTurn))
	Do expected.%JSONExportToString(.json)
	Do $$$AssertEquals(payload.%ToJSON(), json, "and the payload is Decision.FromRow's, member for member")
	Set payload = events.%Get(1).payload
	Do $$$AssertEquals(payload.ref_"|"_payload.traceHeaderId_"|"_payload.%IsDefined("traceItemIndex")_payload.%IsDefined("traceItemIndexNoEvents"), ofHeadless_"|4322|00", "a turn with no header: the decision's TraceSessionId and no position")
	Set payload = events.%Get(2).payload
	Do $$$AssertEquals(payload.ref_"|"_payload.traceHeaderId_"|"_payload.%IsDefined("traceItemIndex")_payload.%IsDefined("traceItemIndexNoEvents"), ofItem_"|4323|00", "an Item that is no turn: the decision's TraceSessionId and no position")
}

/// A decision of owner eval or instance is published nowhere, whoever the event names as the owner: no event of any stream
/// holds its Ref.
Method TestEvalAndInstancePublishNothing()
{
	Set session = ..Session("owners")
	Set eval = ##class(OcuTalon.Test.Data.Fixture).Decision("eval")
	Set instance = ##class(OcuTalon.Test.Data.Fixture).Decision("instance")
	Set ..Refs = ..Refs_","_eval_","_instance
	For owner = "eval", "instance", session {
		Do $$$AssertStatusOK(..Sink("decision.recorded", owner, {"ref": (eval)}), "OnEvent returns OK for the eval decision, owner "_owner)
		Do $$$AssertStatusOK(..Sink("decision.recorded", owner, {"ref": (instance)}), "and for the instance decision, owner "_owner)
	}
	Do $$$AssertEquals(..Holding(eval), 0, "no event holds the eval decision's Ref")
	Do $$$AssertEquals(..Holding(instance), 0, "no event holds the instance decision's Ref")
	Do $$$AssertEquals(..Events(session).%Size(), 0, "and the session's stream is empty")
}

/// The event names the session as the owner of a decision that belongs to another session: nothing is published.
Method TestAnotherSessionsDecisionPublishesNothing()
{
	Set mine = ..Session("mine")
	Set theirs = ..Session("theirs")
	Set theirDecision = ##class(OcuTalon.Test.Data.Fixture).Decision(theirs)
	Set ..Refs = ..Refs_","_theirDecision
	Do $$$AssertStatusOK(..Sink("decision.recorded", mine, {"ref": (theirDecision)}), "OnEvent returns OK")
	Do $$$AssertEquals(..Holding(theirDecision), 0, "no event holds the other session's decision")
	Do $$$AssertEquals(..Events(mine).%Size(), 0, "and the session's stream is empty")
	Do $$$AssertStatusOK(..Sink("decision.recorded", theirs, {"ref": (theirDecision)}), "the real owner's event returns OK")
	Do $$$AssertEquals(..Events(theirs).%Size(), 1, "and publishes on the owner's stream")
	Do $$$AssertEquals(..Events(mine).%Size(), 0, "never on the other's")
}

/// An empty or unknown ref, a payload that is not an object, an approval event for a ref that is no request, the budget
/// event, which does nothing, and a type the sink does not know publish nothing.
Method TestBadPayloadsPublishNothing()
{
	Set session = ..Session("bad")
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(session)
	Set ..Refs = ..Refs_","_decision
	For payload = {}, {"ref": ""}, {"ref": "zzunknown"}, {"ref": 5}, {"ref": {"a": 1}}, {"ref": (decision_"' OR '1'='1")}, [], "text", 42, "" {
		Do $$$AssertStatusOK(..Sink("decision.recorded", session, payload), "decision.recorded with "_$Select($IsObject(payload): payload.%ToJSON(), 1: "'"_payload_"'")_" returns OK")
	}
	For type = "approval.raised", "approval.answered", "approval.expired", "approval.cancelled", "approval.result" {
		Do $$$AssertStatusOK(..Sink(type, session, {"ref": (decision)}), type_" returns OK")
	}
	Do $$$AssertStatusOK(..Sink("budget.capped", session, {"day": "2030-01-01"}), "budget.capped returns OK")
	Do $$$AssertStatusOK(..Sink("budget.capped", "instance", {"day": "2030-01-01"}), "also for the owner instance")
	Do $$$AssertStatusOK(..Sink("zz.unknown", session, {"ref": (decision)}), "an unknown type returns OK")
	Do $$$AssertStatusOK(..Sink("", session, {"ref": (decision)}), "so does an empty type")
	Do $$$AssertEquals(..Holding(decision), 0, "no event holds the decision's Ref")
	Do $$$AssertEquals(..Events(session).%Size(), 0, "and the session's stream is empty")
}

/// Each of the five approval.* types, for a pending fix request of the session, publishes one approval event on its stream
/// with the fields of Approval.FromRow; once the row's state changes, the next event carries the new state. A request with no
/// incident carries no trace target, and a request of an incident with a TraceHeaderId carries the incident's target, as
/// Approval.FromRow builds it for the recipient.
Method TestApprovalEventsPublishTheRequest()
{
	Set session = ..Session("approval")
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval(session, , "pending", "2030-01-01T10:00:00Z")
	Set ..Refs = ..Refs_","_request
	Do $$$AssertEquals(..Events(session).%Size(), 0, "the stream is empty to begin with")
	Set types = $ListBuild("approval.raised", "approval.answered", "approval.expired", "approval.cancelled", "approval.result")
	Set position = 0
	Set count = 0
	While $ListNext(types, position, type) {
		Do $$$AssertStatusOK(..Sink(type, session, {"ref": (request)}), type_": OnEvent returns OK")
		Set count = count + 1
		Set events = ..Events(session)
		Do $$$AssertEquals(events.%Size(), count, type_" publishes one event")
		Set event = events.%Get(count - 1)
		Set payload = event.payload
		Do $$$AssertEquals(event.type_"|"_payload.ref_"|"_payload.kind_"|"_payload.state_"|"_payload.incidentRef, "approval|"_request_"|fix|pending|", "an approval event for the request, its kind and its state")
		Do $$$AssertEquals(+payload.dryRun.affected_"|"_payload.dryRun.itemNoun.one_"|"_payload.dryRun.itemNoun.other, "4|order|orders", "with the dry run's count and noun")
		Do $$$AssertEquals(payload.raisedAt_"|"_payload.expiresAt, "2030-01-01T10:00:00Z|2030-01-02T09:00:00Z", "when it was raised and when it expires")
	}
	Set expected = ##class(OcuTalon.Live.Payload.Approval).FromRow(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request), session)
	Do expected.%JSONExportToString(.json)
	Do $$$AssertEquals(..Events(session).%Get(0).payload.%ToJSON(), json, "the payload is Approval.FromRow's, member for member")
	Do $$$AssertEquals(..Events(session).%Get(0).payload.%IsDefined("traceHeaderId"), 0, "a request with no incident carries no trace target")

	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(session, , , , {"TraceHeaderId": 888})
	Set traced = ##class(OcuTalon.Test.Data.Fixture).Approval(session, incident, "pending", "2030-01-01T10:00:01Z")
	Set ..Refs = ..Refs_","_incident_","_traced
	Do $$$AssertStatusOK(..Sink("approval.raised", session, {"ref": (traced)}), "a request of an incident with a trace: OnEvent returns OK")
	Set events = ..Events(session)
	Do $$$AssertEquals(events.%Size(), count + 1, "it publishes one event")
	Set payload = events.%Get(count).payload
	Do $$$AssertEquals(payload.ref_"|"_payload.incidentRef_"|"_payload.traceHeaderId_"|"_payload.traceNamespace, traced_"|"_incident_"|888|"_$Namespace, "which carries the incident's trace target")
	Set expected = ##class(OcuTalon.Live.Payload.Approval).FromRow(##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(traced), session)
	Do expected.%JSONExportToString(.json)
	Do $$$AssertEquals(payload.%ToJSON(), json, "and is Approval.FromRow's for the recipient, member for member")
	Set count = count + 1

	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(request)
	Set row.State = "approved"
	Do $$$AssertStatusOK(row.%Save(), "the request is approved")
	Do $$$AssertStatusOK(..Sink("approval.answered", session, {"ref": (request)}), "the next event: OnEvent returns OK")
	Set events = ..Events(session)
	Do $$$AssertEquals(events.%Size(), count + 1, "it publishes one more event")
	Do $$$AssertEquals(events.%Get(count).payload.state, "approved", "which carries the new state")
}

/// The owner eval, an owner that names another session's request, an unknown ref, an empty ref and a payload that is not an
/// object publish nothing and return OK; the real owner's event publishes.
Method TestApprovalOwnersThatPublishNothing()
{
	Set mine = ..Session("mine")
	Set theirs = ..Session("theirs")
	Set theirRequest = ##class(OcuTalon.Test.Data.Fixture).Approval(theirs)
	Set evalRequest = ##class(OcuTalon.Test.Data.Fixture).Approval("eval")
	Set ..Refs = ..Refs_","_theirRequest_","_evalRequest
	For owner = "eval", mine, "instance", "", "zz" {
		Do $$$AssertStatusOK(..Sink("approval.raised", owner, {"ref": (evalRequest)}), "the eval request, owner '"_owner_"': OnEvent returns OK")
	}
	Do $$$AssertStatusOK(..Sink("approval.raised", mine, {"ref": (theirRequest)}), "another session's request: OnEvent returns OK")
	Do $$$AssertStatusOK(..Sink("approval.raised", "instance", {"ref": (theirRequest)}), "a session's request under the owner instance: OnEvent returns OK")
	Do $$$AssertStatusOK(..Sink("approval.raised", "eval", {"ref": (theirRequest)}), "a session's request under the owner eval: OnEvent returns OK")
	For payload = {"ref": "zzunknown"}, {"ref": ""}, {}, {"ref": 5}, {"ref": {"a": 1}}, [], "text", 42, "" {
		Do $$$AssertStatusOK(..Sink("approval.raised", mine, payload), "approval.raised with "_$Select($IsObject(payload): payload.%ToJSON(), 1: "'"_payload_"'")_" returns OK")
	}
	Do $$$AssertEquals(..Holding(evalRequest), 0, "no event holds the eval request")
	Do $$$AssertEquals(..Holding(theirRequest), 0, "no event holds the other session's request")
	Do $$$AssertEquals(..Events(mine).%Size()_"|"_..Events(theirs).%Size(), "0|0", "and no stream has an event")
	Do $$$AssertStatusOK(..Sink("approval.raised", theirs, {"ref": (theirRequest)}), "the real owner's event returns OK")
	Do $$$AssertEquals(..Events(theirs).%Size(), 1, "and publishes on the owner's stream")
	Do $$$AssertEquals(..Events(mine).%Size(), 0, "never on the other's")
	Do $$$AssertEquals(..Warnings(), 0, "none of it logs a warning")
}

/// An instance request of a noticed incident reaches each session that watches the incident's production (DW-68), one event
/// each and none to a session that watches another production. With onlineDemo on, or for an unnoticed incident, nobody
/// receives it.
Method TestInstanceApprovalReachesEveryWatcher()
{
	Set a = ..Session("watcha")
	Set b = ..Session("watchb")
	Set c = ..Session("watchc")
	Set production = "Zz.Sink"_..Number_".Watched"
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", production)
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(b, "ZZNS", production)
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(c, "ZZNS", "Zz.Sink"_..Number_".Other")
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", production, {"TraceHeaderId": 777})
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", incident)
	Set unnoticed = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", "", "ZZNS", production)
	Set unnoticedRequest = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", unnoticed)
	Set ..Refs = ..Refs_","_incident_","_request_","_unnoticed_","_unnoticedRequest

	Do $$$AssertStatusOK(..Sink("approval.raised", "instance", {"ref": (request)}), "approval.raised: OnEvent returns OK")
	For session = a, b {
		Set events = ..Events(session)
		Do $$$AssertEquals(events.%Size(), 1, "a watching session gets one event")
		If events.%Size() = 0 Continue
		Do $$$AssertEquals(events.%Get(0).type_"|"_events.%Get(0).payload.ref_"|"_events.%Get(0).payload.incidentRef, "approval|"_request_"|"_incident, "an approval event for the request and its incident")
		Do $$$AssertEquals(events.%Get(0).payload.traceHeaderId_"|"_events.%Get(0).payload.traceNamespace, "777|"_$Namespace, "which carries the incident's trace target for that recipient")
	}
	Do $$$AssertEquals(..Events(c).%Size(), 0, "a session that watches another production gets none")
	Do $$$AssertEquals(..Holding(request), 2, "two events hold the request")
	Do $$$AssertStatusOK(..Sink("approval.expired", "instance", {"ref": (request)}), "approval.expired: OnEvent returns OK")
	Do $$$AssertEquals(..Events(a).%Size()_"|"_..Events(b).%Size()_"|"_..Events(c).%Size(), "2|2|0", "each watching session gets the next event too")

	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertStatusOK(..Sink("approval.raised", "instance", {"ref": (request)}), "with onlineDemo on: OnEvent returns OK")
	Do $$$AssertEquals(..Events(a).%Size()_"|"_..Events(b).%Size()_"|"_..Events(c).%Size(), "2|2|0", "nobody receives it")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")

	Do $$$AssertStatusOK(..Sink("approval.raised", "instance", {"ref": (unnoticedRequest)}), "an unnoticed incident's request: OnEvent returns OK")
	Do $$$AssertEquals(..Holding(unnoticedRequest), 0, "no event holds it")
	Do $$$AssertEquals(..Warnings(), 0, "none of it logs a warning")
}

/// A recipients read that fails logs one warning that names the event, the request and the incident, and publishes nothing,
/// and OnEvent returns OK (DW-68). An incident that no session watches logs nothing and publishes nothing.
Method TestFailedWatcherReadIsLoud()
{
	Set a = ..Session("loud")
	Set production = "Zz.Sink"_..Number_".Loud"
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", production)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", production)
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", incident)
	Set lonelyIncident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", "Zz.Sink"_..Number_".Nobody")
	Set lonelyRequest = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", lonelyIncident)
	Set ..Refs = ..Refs_","_incident_","_request_","_lonelyIncident_","_lonelyRequest

	Set mark = ..LastLog()
	Do $$$AssertStatusOK($ClassMethod("OcuTalon.Test.Core.BridgeSinkProbe", "OnEvent", "approval.raised", "instance", {"ref": (request)}), "a failed read: OnEvent returns OK")
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Approved", ##class(OcuTalon.Core.BridgeSink).#ERRORRECIPIENTS)
	Do $$$AssertEquals(count, 1, "it logs one warning that starts with ERRORRECIPIENTS")
	Do $$$AssertTrue($Find(text, "approval.raised") && $Find(text, request) && $Find(text, incident) && $Find(text, "zz the watchers could not be read"), "naming the event, the request, the incident and the status: "_text)
	Do $$$AssertEquals(..Warnings(mark), 1, "and no other warning")
	Do $$$AssertEquals(..Holding(request), 0, "no event holds the request")
	Do $$$AssertEquals(..Events(a).%Size(), 0, "and the watching session's stream is empty")

	Set mark = ..LastLog()
	Do $$$AssertStatusOK(..Sink("approval.raised", "instance", {"ref": (lonelyRequest)}), "an incident that nobody watches: OnEvent returns OK")
	Do $$$AssertEquals(..Warnings(mark), 0, "it logs nothing")
	Do $$$AssertEquals(..Holding(lonelyRequest), 0, "and publishes nothing")
}

/// A recipient whose read of the request fails (the owner eval, which Ownership refuses) logs one warning that names the event,
/// the request and the recipient, and the next recipient still gets its event.
Method TestAFailedRecipientReadDoesNotStopTheOthers()
{
	Set session = ..Session("refused")
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval(session)
	Set ..Refs = ..Refs_","_request

	Set mark = ..LastLog()
	Do $$$AssertStatusOK($ClassMethod("OcuTalon.Test.Core.BridgeSinkRefusedProbe", "OnEvent", "approval.raised", session, {"ref": (request)}), "OnEvent returns OK")
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Approved", ##class(OcuTalon.Core.BridgeSink).#ERRORFAILED)
	Do $$$AssertEquals(count, 1, "it logs one warning that starts with ERRORFAILED")
	Do $$$AssertTrue($Find(text, "approval.raised") && $Find(text, request) && $Find(text, "recipient eval"), "naming the event, the request and the recipient: "_text)
	Do $$$AssertEquals(..Warnings(mark), 1, "and no other warning")
	Set events = ..Events(session)
	Do $$$AssertEquals(events.%Size(), 1, "the next recipient gets its event")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.ref, request, "for the request")
}

/// With onlineDemo on, the session's own request is published to the session (the online demo's approval step is its own request),
/// while an instance request of a watched production is published to nobody.
Method TestOnlineDemoStillPublishesASessionsOwnRequest()
{
	Set session = ..Session("demo")
	Set production = "Zz.Sink"_..Number_".Demo"
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(session, "ZZNS", production)
	Set own = ##class(OcuTalon.Test.Data.Fixture).Approval(session)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", production)
	Set instance = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", incident)
	Set ..Refs = ..Refs_","_own_","_incident_","_instance

	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertStatusOK(..Sink("approval.raised", session, {"ref": (own)}), "the session's own request: OnEvent returns OK")
	Set events = ..Events(session)
	Do $$$AssertEquals(events.%Size(), 1, "it is published to the session")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).type_"|"_events.%Get(0).payload.ref_"|"_events.%Get(0).payload.state, "approval|"_own_"|pending", "as an approval event for the request")
	Do $$$AssertStatusOK(..Sink("approval.raised", "instance", {"ref": (instance)}), "an instance request of the watched production: OnEvent returns OK")
	Do $$$AssertEquals(..Holding(instance), 0, "no event holds it")
	Do $$$AssertEquals(..Events(session).%Size(), 1, "and the session's stream gained nothing")
	Do $$$AssertEquals(..Warnings(), 0, "none of it logs a warning")
}

/// An approval event waits for a busy stream as long as any other event, about a second and not Publish's five (AD-31): a session
/// whose stream another job holds drops the event with one warning, and the same event publishes once the lock is free. Of two
/// watchers of an instance request, the one whose stream is free still gets its event while the other drops it.
Method TestApprovalNeverWaitsMoreThanASecond()
{
	Set solo = ..Session("lockedsolo")
	Set a = ..Session("lockeda")
	Set b = ..Session("lockedb")
	Set production = "Zz.Sink"_..Number_".Locked"
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Check(a, "ZZNS", production)_","_##class(OcuTalon.Test.Data.Fixture).Check(b, "ZZNS", production)
	Set own = ##class(OcuTalon.Test.Data.Fixture).Approval(solo)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", production)
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", incident)
	Set ..Refs = ..Refs_","_own_","_incident_","_request

	Do ..HoldStream(solo)
	Set mark = ..LastLog()
	Set start = $ZHorolog
	Set sc = ..Sink("approval.raised", solo, {"ref": (own)})
	Set elapsed = $ZHorolog - start
	Do $$$AssertStatusOK(sc, "a session's request on a held stream: OnEvent returns OK")
	Do $$$AssertTrue((elapsed >= 0.9) && (elapsed <= 4), "it waited about a second, not five: "_$FNumber(elapsed, "", 2)_" s")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Publish", ##class(OcuTalon.Core.BridgeSink).#ERRORPUBLISH), 1, "one warning says that the event could not be published: "_text)
	Do $$$AssertEquals(..Warnings(mark), 1, "and no other warning")
	Do $$$AssertEquals(..Holding(own), 0, "nothing was published while the stream was held")
	Do ..ReleaseStream(solo)
	Do $$$AssertStatusOK(..Sink("approval.raised", solo, {"ref": (own)}), "the same event, once the lock is free: OnEvent returns OK")
	Do $$$AssertEquals(..Events(solo).%Size(), 1, "publishes")

	Do ..HoldStream(a)
	Set mark = ..LastLog()
	Set start = $ZHorolog
	Set sc = ..Sink("approval.raised", "instance", {"ref": (request)})
	Set elapsed = $ZHorolog - start
	Do $$$AssertStatusOK(sc, "an instance request with one watcher's stream held: OnEvent returns OK")
	Do $$$AssertTrue((elapsed >= 0.9) && (elapsed <= 4), "it waited about a second for that one stream, not five: "_$FNumber(elapsed, "", 2)_" s")
	Do $$$AssertEquals(..Events(a).%Size(), 0, "the watcher whose stream is held drops the event")
	Do $$$AssertEquals(..Events(b).%Size(), 1, "the other watcher still gets its event")
	Do $$$AssertEquals(..Warnings(mark), 1, "and one warning is logged")
	Do ..ReleaseStream(a)
}

/// turn.step for a session with a running turn publishes one turn.step event with the running turn's Ref, the decision's Ref
/// and the trimmed label, and nothing else of the step.
Method TestTurnStepForTheRunningTurn()
{
	Set session = ..Session("step")
	Set queued = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:02Z", "queued")
	Set running = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:01Z", "running")
	Set ..Refs = ..Refs_","_queued_","_running
	Set payload = {"decisionRef": "ZzSinkDecision", "label": "  Checking the Orders production \n", "tokens": 12, "args": "secret"}
	Do $$$AssertStatusOK(..Sink("turn.step", session, payload), "OnEvent returns OK")
	Set events = ..Events(session)
	Do $$$AssertEquals(events.%Size(), 1, "one event is published")
	Set event = events.%Get(0)
	Do $$$AssertEquals(event.type, "turn.step", "of type turn.step")
	Do $$$AssertEquals(event.payload.turnRef_"|"_event.payload.decisionRef_"|"_event.payload.label, running_"|ZzSinkDecision|Checking the Orders production", "the running turn's Ref, the decision's Ref and the trimmed label")
	Do $$$AssertEquals(..Keys(event.payload), "decisionRef,label,turnRef", "and no other member of the step")
}

/// No event is published when the session has no turn, only a queued or a done turn, or the label is empty, blank, missing or
/// not a string.
Method TestTurnStepWithNoRunningTurn()
{
	Set session = ..Session("nostep")
	Set marker = "ZzSinkDecision"_..Number_"nostep"
	Do $$$AssertStatusOK(..Sink("turn.step", session, {"decisionRef": (marker), "label": "Asking the model"}), "no turn: OnEvent returns OK")
	Do $$$AssertEquals(..Events(session).%Size(), 0, "and publishes nothing")
	Set queued = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:02Z", "queued")
	Set done = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:01Z", "done")
	Set ..Refs = ..Refs_","_queued_","_done
	Do $$$AssertStatusOK(..Sink("turn.step", session, {"decisionRef": (marker), "label": "Asking the model"}), "a queued and a done turn: OnEvent returns OK")
	Do $$$AssertEquals(..Events(session).%Size(), 0, "and publishes nothing")
	Set running = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:03Z", "running")
	Set ..Refs = ..Refs_","_running
	For payload = {"decisionRef": (marker), "label": ""}, {"decisionRef": (marker), "label": (" "_$Char(9)_$Char(10))}, {"decisionRef": (marker)}, {"decisionRef": (marker), "label": 5}, {"decisionRef": (marker), "label": ["a"]}, [], "text", "" {
		Do $$$AssertStatusOK(..Sink("turn.step", session, payload), "a running turn and a bad label: OnEvent returns OK")
	}
	Do $$$AssertEquals(..Events(session).%Size(), 0, "none of them publishes")
	Do $$$AssertStatusOK(..Sink("turn.step", ..Session("other"), {"decisionRef": (marker), "label": "Asking the model"}), "the label of another session with no running turn: OnEvent returns OK")
	Do $$$AssertEquals(..Events(session).%Size(), 0, "and the running turn's session sees nothing of it")
	Do $$$AssertStatusOK(..Sink("turn.step", "instance", {"decisionRef": (marker), "label": "Asking the model"}), "the owner instance: OnEvent returns OK")
	Do $$$AssertStatusOK(..Sink("turn.step", "eval", {"decisionRef": (marker), "label": "Asking the model"}), "the owner eval: OnEvent returns OK")
	Do $$$AssertEquals(..Holding(marker), 0, "no event of any stream holds the step")
}

/// With a bridge context active, a step of another item than the running turn's (an untrusted Intake turn of the same
/// session) publishes nothing, a step of the turn's own item publishes, and after End the step publishes again.
Method TestTurnStepOfAnotherItem()
{
	Set session = ..Session("item")
	Set turn = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:01Z", "running")
	Set ..Refs = ..Refs_","_turn
	Set itemId = ##class(OcuTalon.Data.Turn).RefIndexOpen(turn).ItemId
	Set payload = {"decisionRef": "ZzSinkDecision", "label": "Reading the failed message"}

	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(..Request("ZzSinkOtherItem"_..Number)), "a context for another item begins")
	Do $$$AssertStatusOK(..Sink("turn.step", session, payload), "OnEvent returns OK")
	Do $$$AssertEquals(..Events(session).%Size(), 0, "a step of another item publishes nothing")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(..Request(itemId)), "a context for the turn's own item begins")
	Do $$$AssertStatusOK(..Sink("turn.step", session, payload), "OnEvent returns OK")
	Set events = ..Events(session)
	Do $$$AssertEquals(events.%Size(), 1, "a step of the turn's own item publishes")
	Do $$$AssertEquals(events.%Get(0).payload.turnRef, turn, "for the running turn")
	Do ##class(OcuTalon.Bridge.Context).End()
	Do $$$AssertStatusOK(..Sink("turn.step", session, payload), "after End, OnEvent returns OK")
	Do $$$AssertEquals(..Events(session).%Size(), 2, "and with no context the running turn alone decides")
}

/// With a bridge context active for the SessionBroken retry of the running turn (the ItemId that Conversation.RetryItemId gives),
/// a step publishes one turn.step with the turn's Ref; a context for the retry of another item publishes nothing.
Method TestTurnStepOfARetry()
{
	Set session = ..Session("retry")
	Set turn = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:01Z", "running")
	Set ..Refs = ..Refs_","_turn
	Set itemId = ##class(OcuTalon.Data.Turn).RefIndexOpen(turn).ItemId
	Set payload = {"decisionRef": "ZzSinkDecision", "label": "Reading the failed message"}

	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(..Request(##class(OcuTalon.Core.Conversation).RetryItemId("ZzSinkOtherItem"_..Number))), "a context for the retry of another item begins")
	Do $$$AssertStatusOK(..Sink("turn.step", session, payload), "OnEvent returns OK")
	Do $$$AssertEquals(..Events(session).%Size(), 0, "a step of another item's retry publishes nothing")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Context).Begin(..Request(##class(OcuTalon.Core.Conversation).RetryItemId(itemId))), "a context for the turn's retry begins")
	Do $$$AssertStatusOK(..Sink("turn.step", session, payload), "OnEvent returns OK")
	Set events = ..Events(session)
	Do $$$AssertEquals(events.%Size(), 1, "a step of the turn's retry publishes one event")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.turnRef, turn, "with the running turn's Ref")
	Do ##class(OcuTalon.Bridge.Context).End()
}

/// A stream whose lock another job holds does not hold OnEvent up: it returns OK after about a second, which tells the
/// sink's own wait from Publish's five seconds, publishes nothing and logs a warning. Once the job releases the lock the
/// same event publishes.
Method TestNeverWaitsMoreThanASecond()
{
	Set session = ..Session("lock")
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(session)
	Set turn = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:01Z", "running")
	Set ..Refs = ..Refs_","_decision_","_turn
	Do ..HoldStream(session)
	For case = "decision.recorded", "turn.step" {
		Set payload = $Select(case = "turn.step": {"decisionRef": "ZzSinkDecision", "label": "Asking the model"}, 1: {"ref": (decision)})
		Set start = $ZHorolog
		Set sc = ..Sink(case, session, payload)
		Set elapsed = $ZHorolog - start
		Do $$$AssertStatusOK(sc, case_": OnEvent returns OK")
		Do $$$AssertTrue((elapsed >= 0.9) && (elapsed <= 4), case_": it waited about a second, not five: "_$FNumber(elapsed, "", 2)_" s")
	}
	Do $$$AssertEquals(..Warnings(), 2, "one warning is logged for each dropped event")
	Do ..ReleaseStream(session)
	Do $$$AssertEquals(..Events(session).%Size(), 0, "nothing was published while it was held")
	Do $$$AssertStatusOK(..Sink("decision.recorded", session, {"ref": (decision)}), "the same event, once the lock is free: OnEvent returns OK")
	Do $$$AssertEquals(..Events(session).%Size(), 1, "publishes")
}

/// OnEvent returns OK for every type, owner and payload there is, including the ones that cannot be published; for an event
/// that fails to publish (an open transaction), where it logs a warning; for a handler that throws, where it logs a warning
/// too; and for an approval event whose recipients can't be read, where it logs one.
Method TestNeverFailsItsCaller()
{
	Set session = ..Session("never")
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(session)
	Set turn = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:01Z", "running")
	Set ..Refs = ..Refs_","_decision_","_turn
	Set types = $ListFromString("turn.step,decision.recorded,approval.raised,approval.answered,approval.expired,approval.cancelled,approval.result,budget.capped,zz.unknown,")
	Set owners = $ListBuild(session, "instance", "eval", "", "zz", ##class(OcuTalon.Bridge.Ids).NewRef())
	Set calls = 0, failures = 0
	Set t = 0
	While $ListNext(types, t, type) {
		Set o = 0
		While $ListNext(owners, o, owner) {
			For i = 1:1:9 {
				Set calls = calls + 1
				If $SYSTEM.Status.IsError(..Sink(type, owner, ..Payload(i, decision))) Set failures = failures + 1
			}
		}
	}
	Do $$$AssertEquals(calls, 10 * 6 * 9, "every combination of 10 types, 6 owners and 9 payloads was tried")
	Do $$$AssertEquals(failures, 0, "none of them failed its caller")
	Set before = ..Events(session).%Size()

	Set mark = ..LastLog()
	TSTART
	Set sc = ..Sink("decision.recorded", session, {"ref": (decision)})
	Set inTransaction = ..Warnings(mark)
	TROLLBACK
	Do $$$AssertStatusOK(sc, "inside an open transaction, where Publish refuses, OnEvent returns OK")
	Do $$$AssertEquals(inTransaction, 1, "and logs a warning")
	Do $$$AssertEquals(..Events(session).%Size(), before, "and publishes nothing")

	Set mark = ..LastLog()
	For type = "decision.recorded", "turn.step", "approval.raised" {
		Do $$$AssertStatusOK($ClassMethod("OcuTalon.Test.Core.BridgeSinkProbe", "OnEvent", type, session, {"ref": (decision), "label": "zz label"}), "a handler that throws or a read that fails: "_type_" returns OK")
	}
	Do $$$AssertEquals(..Warnings(mark), 3, "and a warning is logged for each")
	Do $$$AssertEquals(..Events(session).%Size(), before, "with nothing published")
}

/// --- helpers ---
/// A fixture session, recorded for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzsink"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// OnEvent of the real sink.
Method Sink(type As %String, owner As %String, payload As %RegisteredObject) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.BridgeSink).OnEvent(type, owner, payload)
}

/// The events of the session's stream, in order, as an array of envelopes.
Method Events(session As %String) As %DynamicArray [ Private ]
{
	Quit ##class(OcuTalon.Live.Event).Since(session, 0, 200, "session")
}

/// The number of events of any stream whose payload holds the text.
Method Holding(text As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Live.Event WHERE Payload [ ?", text)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The members of the object, sorted and comma-separated.
ClassMethod Keys(object As %DynamicObject) As %String [ Private ]
{
	Kill keys
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys(key) = ""
	}
	Set list = ""
	Set key = ""
	For {
		Set key = $Order(keys(key))
		Quit:key=""
		Set list = list_$Select(list = "": "", 1: ",")_key
	}
	Quit list
}

/// The i-th payload of the matrix of TestNeverFailsItsCaller: empty, a full one, members of the wrong type, and values that are
/// not objects.
Method Payload(i As %Integer, decision As %String) [ Private ]
{
	If i = 1 Quit {}
	If i = 2 Quit {"ref": (decision), "decisionRef": (decision), "label": "zz label"}
	If i = 3 Quit {"ref": 5}
	If i = 4 Quit {"ref": {"a": 1}}
	If i = 5 Quit {"label": ["x"]}
	If i = 6 Quit []
	If i = 7 Quit "text"
	If i = 8 Quit 42
	Quit ""
}

/// A request for the item, to begin a bridge context.
Method Request(itemId As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.ItemId = itemId
	Quit request
}

/// The number of the newest row of the event log, 0 when it is empty.
Method LastLog() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM Ens_Util.Log")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of warnings that BridgeSink logged after the row mark (the test's own by default). The event log names the class
/// that the call ran on, so the probe's calls are counted too.
Method Warnings(mark As %Integer = "") As %Integer [ Private ]
{
	If mark = "" Set mark = ..LogMark
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceClass IN (?, ?, ?)", mark, "OcuTalon.Core.BridgeSink", "OcuTalon.Test.Core.BridgeSinkProbe", "OcuTalon.Test.Core.BridgeSinkRefusedProbe")
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// Waits up to seconds for the global node named by ref to hold a value.
ClassMethod WaitFor(ref As %String, seconds As %Integer) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While ('$Data(@ref)) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

/// Another job takes the stream's lock and holds it until ReleaseStream; this returns once the job holds it.
Method HoldStream(stream As %String) [ Private ]
{
	Kill ^OcuTalonTest("BridgeSink", "hold", stream)
	Job ##class(OcuTalon.Test.Core.BridgeSink).Hold(stream)
	Do ..WaitFor($Name(^OcuTalonTest("BridgeSink", "hold", stream, "ready")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("BridgeSink", "hold", stream, "ready")), 1, "another job holds the lock of the stream "_stream)
}

/// Lets the job that HoldStream started release the stream's lock, and returns once it has.
Method ReleaseStream(stream As %String) [ Private ]
{
	Set ^OcuTalonTest("BridgeSink", "hold", stream, "release") = 1
	Do ..WaitFor($Name(^OcuTalonTest("BridgeSink", "hold", stream, "done")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("BridgeSink", "hold", stream, "done")), 1, "the job lets go of the stream "_stream)
}

/// The job body of HoldStream: holds the stream's lock until released, then ends.
ClassMethod Hold(stream As %String)
{
	Lock +^OcuTalonP.LiveEventC(stream):5
	If '$Test Quit
	Set ^OcuTalonTest("BridgeSink", "hold", stream, "ready") = 1
	Set deadline = $ZHorolog + 60
	While '$Get(^OcuTalonTest("BridgeSink", "hold", stream, "release")) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Lock -^OcuTalonP.LiveEventC(stream)
	Set ^OcuTalonTest("BridgeSink", "hold", stream, "done") = 1
}

}
