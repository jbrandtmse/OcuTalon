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
///   - TestNeverFailsItsCaller: OnEvent returns OK for every type, owner and payload, and for a handler that throws;
///   - TestBudgetCappedSendsToEachActiveSessionOnce, TestDailyCapFallbackSendsToThatSessionOnce, TestDailyCapSendsNothingWithTheFlagOff,
///     TestDailyCapWaitsAtMostASecondForABusyRow, TestFailedDailyCapSendIsRetried, TestBudgetCappedBadInputsSendNothing (Story 16.9,
///     AD-20, AD-31): budget.capped and a session's daily_cap fallback in decision.recorded send the daily-cap Notification to the open
///     sessions with activity, once a day each, never with the flag off; they run on Test.Core.BridgeSinkNoticeProbe, which records the
///     notices instead of sending them.
///   - TestToolCallNoticeKinds, TestToolCallServerForm, TestToolCallInputsLine, TestToolCallInputsVisible, TestToolCallUnreadableInputs,
///     TestToolCallCancelledOnlyForARemovedServer, TestToolCallNoticesOnlyForReplayableSessionRows,
///     TestHeldBeforeUpdateSaysWhy, TestHeldReasonIsCatalogOnly, TestToolCallNoticeFailureIsLogged (Story 31.5, AD-31, AD-32, U-212,
///     DW-454): a replayable tool_call request of a session sends its approval, answered and result notices beside the approval event
///     (the key from the row's AnsweredAction and Result, the server form of the request when the ToolSource names an MCP server,
///     the inputs as an array of {name, value}, one member per top-level member, never cut and with the whole arguments redacted first; a
///     cancelled request of an MCP server that has no row any more sends answered.canceled and its approval event carries the server and
///     cancelledAt, any other cancellation sends nothing), a fix, a setting, an old held row and any other owner send none, an old
///     held row's fallback Decision sends the one result notice with the bridge's reason (and the approval event carries it) or, for
///     any other line, toolCall.failed with no reason, and a failed or throwing send is one warning; they run on the probe.
/// DW-300: the check rows that the approval tests seed are due a day ahead (the Check helper asserts it), and Events counts only the type
/// that a caller names, so that a heartbeat tick cannot run a row or add a check event in the middle of a test.
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
	Kill ^OcuTalonTest("BridgeSinkNotice")
	Set ..Number = $Increment(^OcuTalonTest("BridgeSink", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("BridgeSinkNotice")
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
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceClass IN (?, ?, ?, ?)", ..LogMark, "OcuTalon.Core.BridgeSink", "OcuTalon.Test.Core.BridgeSinkProbe", "OcuTalon.Test.Core.BridgeSinkRefusedProbe", "OcuTalon.Test.Core.BridgeSinkNoticeProbe")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Kill ^OcuTalonTest("BridgeSink", "hold")
	Kill ^OcuTalonTest("BridgeSinkNotice")
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
	Set ..Refs = ..Refs_","_..Check(a, "ZZNS", production)
	Set ..Refs = ..Refs_","_..Check(b, "ZZNS", production)
	Set ..Refs = ..Refs_","_..Check(c, "ZZNS", "Zz.Sink"_..Number_".Other")
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", production, {"TraceHeaderId": 777})
	Set request = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", incident)
	Set unnoticed = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", "", "ZZNS", production)
	Set unnoticedRequest = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", unnoticed)
	Set ..Refs = ..Refs_","_incident_","_request_","_unnoticed_","_unnoticedRequest

	Do $$$AssertStatusOK(..Sink("approval.raised", "instance", {"ref": (request)}), "approval.raised: OnEvent returns OK")
	For session = a, b {
		Set events = ..Events(session, "approval")
		Do $$$AssertEquals(events.%Size(), 1, "a watching session gets one event")
		If events.%Size() = 0 Continue
		Do $$$AssertEquals(events.%Get(0).type_"|"_events.%Get(0).payload.ref_"|"_events.%Get(0).payload.incidentRef, "approval|"_request_"|"_incident, "an approval event for the request and its incident")
		Do $$$AssertEquals(events.%Get(0).payload.traceHeaderId_"|"_events.%Get(0).payload.traceNamespace, "777|"_$Namespace, "which carries the incident's trace target for that recipient")
	}
	Do $$$AssertEquals(..Events(c, "approval").%Size(), 0, "a session that watches another production gets none")
	Do $$$AssertEquals(..Holding(request), 2, "two events hold the request")
	Do $$$AssertStatusOK(..Sink("approval.expired", "instance", {"ref": (request)}), "approval.expired: OnEvent returns OK")
	Do $$$AssertEquals(..Events(a, "approval").%Size()_"|"_..Events(b, "approval").%Size()_"|"_..Events(c, "approval").%Size(), "2|2|0", "each watching session gets the next event too")

	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertStatusOK(..Sink("approval.raised", "instance", {"ref": (request)}), "with onlineDemo on: OnEvent returns OK")
	Do $$$AssertEquals(..Events(a, "approval").%Size()_"|"_..Events(b, "approval").%Size()_"|"_..Events(c, "approval").%Size(), "2|2|0", "nobody receives it")
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
	Set ..Refs = ..Refs_","_..Check(a, "ZZNS", production)
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
	Do $$$AssertEquals(..Events(a, "approval").%Size(), 0, "and the watching session's stream is empty")

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
	Set ..Refs = ..Refs_","_..Check(session, "ZZNS", production)
	Set own = ##class(OcuTalon.Test.Data.Fixture).Approval(session)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , "ZZNS", production)
	Set instance = ##class(OcuTalon.Test.Data.Fixture).Approval("instance", incident)
	Set ..Refs = ..Refs_","_own_","_incident_","_instance

	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do $$$AssertStatusOK(..Sink("approval.raised", session, {"ref": (own)}), "the session's own request: OnEvent returns OK")
	Set events = ..Events(session, "approval")
	Do $$$AssertEquals(events.%Size(), 1, "it is published to the session")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).type_"|"_events.%Get(0).payload.ref_"|"_events.%Get(0).payload.state, "approval|"_own_"|pending", "as an approval event for the request")
	Do $$$AssertStatusOK(..Sink("approval.raised", "instance", {"ref": (instance)}), "an instance request of the watched production: OnEvent returns OK")
	Do $$$AssertEquals(..Holding(instance), 0, "no event holds it")
	Do $$$AssertEquals(..Events(session, "approval").%Size(), 1, "and the session's stream gained nothing")
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
	Set ..Refs = ..Refs_","_..Check(a, "ZZNS", production)_","_..Check(b, "ZZNS", production)
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
	Do $$$AssertEquals(..Events(solo, "approval").%Size(), 1, "publishes")

	Do ..HoldStream(a)
	Set mark = ..LastLog()
	Set start = $ZHorolog
	Set sc = ..Sink("approval.raised", "instance", {"ref": (request)})
	Set elapsed = $ZHorolog - start
	Do $$$AssertStatusOK(sc, "an instance request with one watcher's stream held: OnEvent returns OK")
	Do $$$AssertTrue((elapsed >= 0.9) && (elapsed <= 4), "it waited about a second for that one stream, not five: "_$FNumber(elapsed, "", 2)_" s")
	Do $$$AssertEquals(..Events(a, "approval").%Size(), 0, "the watcher whose stream is held drops the event")
	Do $$$AssertEquals(..Events(b, "approval").%Size(), 1, "the other watcher still gets its event")
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

/// budget.capped {day} from owner instance (Story 16.9, matrix row 13): with the flag set, every open session with activity gets the
/// daily-cap Notification once, whatever its kind of activity (a Turn, a refused one included, a Break the feed run or an answered
/// request), with the end of the day as its time and the install link, and its DailyCapDay becomes the day. A session with no activity
/// and an ended one (no ResumeHash) get nothing. The same event again sends nothing, and the next day sends again. The sessions the
/// event goes to are the test's own: the real read of the active sessions, cut down to the test's fixtures, so that no other session of
/// the instance is written.
Method TestBudgetCappedSendsToEachActiveSessionOnce()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set day = "2030-06-15"
	Set resets = ##class(OcuTalon.Bridge.Time).DayEndUtc(day)
	Set withTurn = ..Visitor("capturn")
	Set withRun = ..Visitor("caprun")
	Set withAnswer = ..Visitor("capanswer")
	Set idle = ..Visitor("capidle")
	Set ended = ..Session("capended")
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Turn(withTurn, , "refused", "zz refused")
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).BreakFeedRun(withRun)
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Approval(withAnswer, "", "approved", ##class(OcuTalon.Data.Time).NowUtc(), {"AnsweredAt": (##class(OcuTalon.Data.Time).NowUtc()), "AnsweredAction": "approve"})
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Turn(ended, , "done", "zz it ended")
	Do $$$AssertEquals(..Notices(idle), 0, "nothing was sent to begin with")
	Set found = ##class(OcuTalon.Data.Ownership).ActiveVisitors(.visitorsSc)
	Do $$$AssertStatusOK(visitorsSc, "the read of the active sessions works")
	Set ours = $ListBuild(withTurn, withRun, withAnswer, idle, ended), active = "", position = 0
	While $ListNext(found, position, ref) {
		If $ListFind(ours, ref) Set active = active_$ListBuild(ref)
	}
	Do $$$AssertEquals($ListLength(active), 3, "the read finds the three sessions with activity")
	Do $$$AssertEquals($ListFind(active, idle) + $ListFind(active, ended), 0, "and neither the idle session nor the ended one")
	Set ^OcuTalonTest("BridgeSinkNotice", "visitors") = active
	Set before = ..Events(withTurn).%Size() + ..Events(withRun).%Size() + ..Events(withAnswer).%Size()
	Do $$$AssertStatusOK(..NoticeSink("budget.capped", "instance", {"day": (day)}), "OnEvent returns OK")
	Do $$$AssertEquals(..Events(withTurn).%Size() + ..Events(withRun).%Size() + ..Events(withAnswer).%Size(), before, "budget.capped publishes no event on their streams: the message goes through the Notice seam only")
	For session = withTurn, withRun, withAnswer {
		Do $$$AssertEquals(..Notices(session), 1, "a session with activity gets one notice")
		Set n = ..NoticeOf(session)
		Do $$$AssertEquals(..NoticeCall(n, "kind")_"|"_..NoticeCall(n, "catalogKey"), "allowance|conversation.dailyCap", "of kind allowance with the daily-cap key")
		Set slots = {}.%FromJSON(..NoticeCall(n, "slots"))
		Do $$$AssertEquals(slots.time_"|"_slots.readmeLink_"|"_slots.%Size(), resets_"|"_##class(OcuTalon.Core.Allowance).#INSTALLLINK_"|2", "with the end of the day and the install link")
		Do $$$AssertEquals(..DayOf(session), day, "and its DailyCapDay is the day")
	}
	Do $$$AssertEquals(..Notices(idle)_"|"_..DayOf(idle), "0|", "a session with no activity gets nothing")
	Do $$$AssertEquals(..Notices(ended)_"|"_..DayOf(ended), "0|", "and neither does an ended session")
	Do $$$AssertStatusOK(..NoticeSink("budget.capped", "instance", {"day": (day)}), "the same event again: OnEvent returns OK")
	Do $$$AssertEquals(..Notices(withTurn)_..Notices(withRun)_..Notices(withAnswer), "111", "it sends nothing more: once a day")
	Do $$$AssertStatusOK(..NoticeSink("budget.capped", "instance", {"day": "2030-06-16"}), "the next day's event: OnEvent returns OK")
	Do $$$AssertEquals(..Notices(withTurn)_..Notices(withRun)_..Notices(withAnswer), "222", "it sends again")
	Do $$$AssertEquals(..DayOf(withTurn), "2030-06-16", "and moves the day")
	Do $$$AssertEquals(..Warnings(), 0, "none of it logs a warning")
}

/// decision.recorded for a session's daily_cap fallback (matrix rows 13 to 15): the decision event is published as before, and an
/// open session that has not had the message that day gets it, with the end of the local day of the decision; a second fallback of
/// the day sends nothing, a fallback of the next day sends again, and a decision that is no daily_cap fallback or belongs to an ended
/// session sends nothing.
Method TestDailyCapFallbackSendsToThatSessionOnce()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set session = ..Visitor("fallback")
	Set ended = ..Session("fallbackended")
	Set recorded = "2030-06-15T12:00:00Z"
	Set day = ##class(OcuTalon.Bridge.Time).LocalDate(recorded)
	Set first = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", recorded, {"Fallback": 1, "FallbackReason": "daily_cap"})
	Set second = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "turn", recorded, {"Fallback": 1, "FallbackReason": "daily_cap"})
	Set timeout = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", recorded, {"Fallback": 1, "FallbackReason": "timeout"})
	Set plain = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", recorded)
	Set theirs = ##class(OcuTalon.Test.Data.Fixture).Decision(ended, "decide", recorded, {"Fallback": 1, "FallbackReason": "daily_cap"})
	Set nextDay = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", "2030-06-16T12:00:00Z", {"Fallback": 1, "FallbackReason": "daily_cap"})
	Set ..Refs = ..Refs_","_first_","_second_","_timeout_","_plain_","_theirs_","_nextDay
	For ref = timeout, plain {
		Do $$$AssertStatusOK(..NoticeSink("decision.recorded", session, {"ref": (ref)}), "a decision that is no daily_cap fallback: OnEvent returns OK")
	}
	Do $$$AssertEquals(..Notices(session), 0, "it sends no notice")
	Do $$$AssertEquals(..Events(session, "decision").%Size(), 2, "and publishes the decision events as before")

	Do $$$AssertStatusOK(..NoticeSink("decision.recorded", session, {"ref": (first)}), "a daily_cap fallback: OnEvent returns OK")
	Do $$$AssertEquals(..Holding(first), 1, "its decision event is published")
	Do $$$AssertEquals(..Notices(session), 1, "and the session gets the daily-cap notice")
	Set slots = {}.%FromJSON(..NoticeCall(..NoticeOf(session), "slots"))
	Do $$$AssertEquals(slots.time, ##class(OcuTalon.Bridge.Time).DayEndUtc(day), "with the end of the decision's local day")
	Do $$$AssertEquals(..DayOf(session), day, "and its DailyCapDay is that day")
	Do $$$AssertStatusOK(..NoticeSink("decision.recorded", session, {"ref": (second)}), "a second fallback that day: OnEvent returns OK")
	Do $$$AssertEquals(..Notices(session), 1, "sends nothing more")
	Do $$$AssertEquals(..Holding(second), 1, "though its decision event is published")
	Do $$$AssertStatusOK(..NoticeSink("decision.recorded", session, {"ref": (nextDay)}), "a fallback of the next day: OnEvent returns OK")
	Do $$$AssertEquals(..Notices(session), 2, "sends again")

	Do $$$AssertStatusOK(..NoticeSink("decision.recorded", ended, {"ref": (theirs)}), "an ended session's fallback: OnEvent returns OK")
	Do $$$AssertEquals(..Notices(ended)_"|"_..DayOf(ended), "0|", "it sends nothing and records no day")
	Do $$$AssertEquals(..Warnings(), 0, "none of it logs a warning")
}

/// AC 6: with the flag off a capped day shows the local banner only. budget.capped and a daily_cap fallback send nothing, record no
/// day and log nothing.
Method TestDailyCapSendsNothingWithTheFlagOff()
{
	Set session = ..Visitor("flagoff")
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Turn(session)
	Set fallback = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", "2030-06-15T12:00:00Z", {"Fallback": 1, "FallbackReason": "daily_cap"})
	Set ..Refs = ..Refs_","_fallback
	For flag = "", 0 {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", flag)
		Do $$$AssertStatusOK(..NoticeSink("budget.capped", "instance", {"day": "2030-06-15"}), "flag '"_flag_"', budget.capped: OnEvent returns OK")
		Do $$$AssertStatusOK(..NoticeSink("decision.recorded", session, {"ref": (fallback)}), "flag '"_flag_"', the fallback: OnEvent returns OK")
	}
	Do $$$AssertEquals(..Notices(session)_"|"_..DayOf(session), "0|", "no notice is sent and no day is recorded")
	Do $$$AssertEquals(..Holding(fallback), 2, "the decision events are published as before")
	Do $$$AssertEquals(..Warnings(), 0, "and nothing is logged")
}

/// A session row whose lock another job holds does not hold OnEvent up: it gives up after about a second (LOCKWAIT) with one warning
/// and sends nothing; the next fallback, once the lock is free, sends the message.
Method TestDailyCapWaitsAtMostASecondForABusyRow()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set session = ..Visitor("busyrow")
	Set id = ##class(OcuTalon.Data.Session).RefIndexOpen(session).%Id()
	Set first = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", "2030-06-15T12:00:00Z", {"Fallback": 1, "FallbackReason": "daily_cap"})
	Set second = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "turn", "2030-06-15T12:00:00Z", {"Fallback": 1, "FallbackReason": "daily_cap"})
	Set ..Refs = ..Refs_","_first_","_second
	Kill ^OcuTalonTest("Allowance", "job", "sinkhold")
	Job ##class(OcuTalon.Test.Core.Allowance).Hold(id, "sinkhold")
	Do ..WaitFor($Name(^OcuTalonTest("Allowance", "job", "sinkhold", "ready")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("Allowance", "job", "sinkhold", "ready")), 1, "another job holds the session row's lock")
	Set mark = ..LastLog()
	Set start = $ZHorolog
	Set sc = ..NoticeSink("decision.recorded", session, {"ref": (first)})
	Set elapsed = $ZHorolog - start
	Do $$$AssertStatusOK(sc, "OnEvent returns OK")
	Do $$$AssertTrue((elapsed >= 0.9) && (elapsed <= 4), "it waited about a second, not five: "_$FNumber(elapsed, "", 2)_" s")
	Do $$$AssertEquals(..Warnings(mark), 1, "one warning is logged")
	Do $$$AssertEquals(..Notices(session)_"|"_..DayOf(session), "0|", "nothing was sent and no day was recorded")
	Set ^OcuTalonTest("Allowance", "job", "sinkhold", "release") = 1
	Do ..WaitFor($Name(^OcuTalonTest("Allowance", "job", "sinkhold", "done")), 60)
	Kill ^OcuTalonTest("Allowance", "job", "sinkhold")
	Do $$$AssertStatusOK(..NoticeSink("decision.recorded", session, {"ref": (second)}), "the next fallback, with the lock free: OnEvent returns OK")
	Do $$$AssertEquals(..Notices(session), 1, "sends the message")
}

/// A notice that cannot be sent (it answers an error or throws) is one warning that names the failure; DailyCapDay is taken back, so
/// that the next fallback of the day tries again and sends it.
Method TestFailedDailyCapSendIsRetried()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set session = ..Visitor("failsend")
	Set first = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "decide", "2030-06-15T12:00:00Z", {"Fallback": 1, "FallbackReason": "daily_cap"})
	Set second = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "turn", "2030-06-15T12:00:00Z", {"Fallback": 1, "FallbackReason": "daily_cap"})
	Set ..Refs = ..Refs_","_first_","_second
	Set ^OcuTalonTest("BridgeSinkNotice", "failNotice") = 1
	Set mark = ..LastLog()
	Do $$$AssertStatusOK(..NoticeSink("decision.recorded", session, {"ref": (first)}), "a notice that fails: OnEvent returns OK")
	Do $$$AssertEquals(..Notices(session), 1, "the send was tried")
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "DailyCap", ##class(OcuTalon.Core.BridgeSink).#ERRORDAILYCAP)
	Do $$$AssertEquals(count, 1, "one warning says that the daily-cap message could not be sent: "_text)
	Do $$$AssertTrue($Find(text, "zz the probe's notice fails") > 0, "and why")
	Do $$$AssertEquals(..DayOf(session), "", "the day was taken back")
	Kill ^OcuTalonTest("BridgeSinkNotice", "failNotice")
	Do $$$AssertStatusOK(..NoticeSink("decision.recorded", session, {"ref": (second)}), "the next fallback: OnEvent returns OK")
	Do $$$AssertEquals(..Notices(session), 2, "tries again and sends it")
	Do $$$AssertEquals(..DayOf(session), ##class(OcuTalon.Bridge.Time).LocalDate("2030-06-15T12:00:00Z"), "and records the day")

	Set third = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "turn", "2030-06-16T12:00:00Z", {"Fallback": 1, "FallbackReason": "daily_cap"})
	Set ..Refs = ..Refs_","_third
	Set ^OcuTalonTest("BridgeSinkNotice", "throwNotice") = 1
	Set mark = ..LastLog()
	Do $$$AssertStatusOK(..NoticeSink("decision.recorded", session, {"ref": (third)}), "a notice that throws: OnEvent returns OK")
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "DailyCap", ##class(OcuTalon.Core.BridgeSink).#ERRORDAILYCAP)
	Do $$$AssertEquals(count, 1, "one warning says that the daily-cap message could not be sent: "_text)
	Do $$$AssertEquals(..DayOf(session), ##class(OcuTalon.Bridge.Time).LocalDate("2030-06-15T12:00:00Z"), "and the day is taken back to the one before")
}

/// budget.capped with a day that is not YYYY-MM-DD, a missing day, a payload that is not an object, or an owner that is a session
/// sends nothing; a day of that form that is no date is one warning and sends nothing; a failed read of the sessions is one warning
/// that names the event, and sends nothing.
Method TestBudgetCappedBadInputsSendNothing()
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set session = ..Visitor("capbad")
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Data.Fixture).Turn(session)
	Set ^OcuTalonTest("BridgeSinkNotice", "visitors") = $ListBuild(session)
	Set mark = ..LastLog()
	For payload = {"day": "2030-6-1"}, {"day": ""}, {"day": 20300615}, {}, [], "text", "" {
		Do $$$AssertStatusOK(..NoticeSink("budget.capped", "instance", payload), "budget.capped with "_$Select($IsObject(payload): payload.%ToJSON(), 1: "'"_payload_"'")_": OnEvent returns OK")
	}
	Do $$$AssertStatusOK(..NoticeSink("budget.capped", session, {"day": "2030-06-15"}), "from a session's owner: OnEvent returns OK")
	Do $$$AssertStatusOK(..NoticeSink("budget.capped", "eval", {"day": "2030-06-15"}), "from eval: OnEvent returns OK")
	Do $$$AssertEquals(..Notices(session)_"|"_..DayOf(session), "0|", "none of them sends a notice")
	Do $$$AssertEquals(..Warnings(mark), 0, "and none of them reaches the daily-cap message: a day of another form logs nothing")
	Set mark = ..LastLog()
	Do $$$AssertStatusOK(..NoticeSink("budget.capped", "instance", {"day": "2030-13-45"}), "a day of the right form that is no date: OnEvent returns OK")
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "DailyCap", ##class(OcuTalon.Core.BridgeSink).#ERRORDAILYCAP)
	Do $$$AssertEquals(count, 1, "one warning says that the day is no date: "_text)
	Do $$$AssertEquals(..Notices(session)_"|"_..DayOf(session), "0|", "and nothing is sent")
	Set mark = ..LastLog()
	Kill ^OcuTalonTest("BridgeSinkNotice", "visitors")
	Set ^OcuTalonTest("BridgeSinkNotice", "failVisitors") = 1
	Do $$$AssertStatusOK(..NoticeSink("budget.capped", "instance", {"day": "2030-06-15"}), "a failed read of the sessions: OnEvent returns OK")
	Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Capped", ##class(OcuTalon.Core.BridgeSink).#ERRORVISITORS)
	Do $$$AssertEquals(count, 1, "one warning says what could not be read: "_text)
	Do $$$AssertTrue($Find(text, "budget.capped") > 0, "and it names the event")
	Do $$$AssertEquals(..Notices(session), 0, "and nothing is sent")
}

/// A tool_call request of a session that the bridge can replay sends its notices, built from the row as read (Story 31.5, U-212). The
/// key of an answer comes from AnsweredAction, not from the state (the row is already done), and each type publishes its approval event
/// as before.
Method TestToolCallNoticeKinds()
{
	Set session = ..Session("toolkinds")
	Set ref = ..ToolRow(session, "pending")
	Set answeredAt = "2030-01-01T10:05:00Z"
	Do ..Fire(session, "approval.raised", ref)
	Do $$$AssertEquals(..Calls(), 1, "approval.raised sends one notice")
	Do ..ExpectNotice(1, session, ref, "approval", "toolCall.request", "inputs,tool", "raised")
	Do $$$AssertEquals(..Slot(1, "tool")_"|"_..Inputs(1), "zz_send|[{""name"":""to"",""value"":""\""ops\""""}]", "with the tool and its inputs")
	Do $$$AssertEquals(..Events(session, "approval").%Size(), 1, "and publishes its approval event")

	Do ..Change(ref, {"State": "done", "AnsweredAction": "approve", "AnsweredChannel": "phone", "AnsweredAt": (answeredAt)})
	Do ..Fire(session, "approval.answered", ref)
	Do ..ExpectNotice(2, session, ref, "answered", "answered.approved", "channel,time", "approved")
	Do $$$AssertEquals(..Slot(2, "channel")_"|"_..Slot(2, "time"), "phone|"_answeredAt, "the channel and time of the answer, whatever the state")
	Do ..Change(ref, {"State": "rejected", "AnsweredAction": "reject", "AnsweredChannel": "telegram"})
	Do ..Fire(session, "approval.answered", ref)
	Do ..ExpectNotice(3, session, ref, "answered", "answered.rejected", "channel,time", "rejected")
	Do $$$AssertEquals(..Slot(3, "channel"), "telegram", "from the channel that answered")
	Do ..Change(ref, {"AnsweredAction": ""})
	Do ..Fire(session, "approval.answered", ref)
	Do $$$AssertEquals(..Calls(), 3, "an answered event for a row with no action sends nothing")

	Do ..Change(ref, {"State": "expired"})
	Do ..Fire(session, "approval.expired", ref)
	Do ..ExpectNotice(4, session, ref, "answered", "answered.expired", "time", "expired")
	Do $$$AssertEquals(..Slot(4, "time"), "2030-01-02T09:00:00Z", "with the request's ExpiresAt")

	Set finishedAt = "2030-01-01T10:06:00Z"
	Set n = 4
	For result = "done", "failed", "interrupted" {
		Do ..Change(ref, {"State": "done", "Result": (result), "FinishedAt": (finishedAt)})
		Do ..Fire(session, "approval.result", ref)
		Set n = n + 1
		Do ..ExpectNotice(n, session, ref, "result", $Select(result = "done": "toolCall.done", 1: "toolCall.failed"), "time,tool", "result "_result)
		Do $$$AssertEquals(..Slot(n, "tool")_"|"_..Slot(n, "time"), "zz_send|"_finishedAt, "result "_result_": the tool and when it finished")
	}
	Do ..Change(ref, {"Result": ""})
	Do ..Fire(session, "approval.result", ref)
	Do ..Change(ref, {"Result": "done", "FinishedAt": ""})
	Do ..Fire(session, "approval.result", ref)
	Do $$$AssertEquals(..Calls(), n, "a result event for a row with no Result, or no FinishedAt, sends nothing")
	Do ..Fire(session, "approval.cancelled", ref)
	Do $$$AssertEquals(..Calls(), n, "approval.cancelled sends nothing")
	Do $$$AssertEquals(..Events(session, "approval").%Size(), 1 + 3 + 1 + 3 + 2 + 1, "and every event published its approval event")
	Do $$$AssertEquals(..Warnings(), 0, "none of it logs a warning")
}

/// U-212 (1): the request names the MCP server of the held call when the ToolSource does, in any case of the prefix and in the attach
/// form; a class source and a bare prefix name none (toolCall.request, no server slot).
Method TestToolCallServerForm()
{
	Set session = ..Session("toolserver")
	Set n = 0
	For source = "mcp:zzserver", "MCP:zzserver", "mcp:remote:@{config:AI.MCP.OcuTalon_zzdocs}", "OcuTalon.Test.Bridge.ZzReplayTool", "mcp:" {
		Set server = $Case(source, "mcp:zzserver": "zzserver", "MCP:zzserver": "zzserver", "mcp:remote:@{config:AI.MCP.OcuTalon_zzdocs}": "zzdocs", : "")
		Set ref = ..ToolRow(session, "pending", {"ToolSource": (source)})
		Do ..Fire(session, "approval.raised", ref)
		Set n = n + 1
		Do ..ExpectNotice(n, session, ref, "approval", $Select(server '= "": "toolCall.requestOnServer", 1: "toolCall.request"), $Select(server '= "": "inputs,server,tool", 1: "inputs,tool"), source)
		Do $$$AssertEquals(..Slot(n, "server"), server, "the source "_source_" names the server '"_server_"'")
	}
	Do $$$AssertEquals(..Calls(), 5, "one notice for each")
}

/// The inputs of a notice are an array of {name, value}: one member per top-level member of the arguments, in the stored order, the value its JSON text
/// (JSON's short escapes written as \uXXXX), never cut; the whole arguments are redacted first, so a key rule masks a value; no arguments give an
/// empty array.
Method TestToolCallInputsLine()
{
	Set session = ..Session("toolinputs")
	Set long = ""
	For i = 1:1:500 Set long = long_"0123456789"
	Do ..ExpectInputs(session, "{""note"":"""_long_""",""n"":2}", [{"name": "note", "value": (""""_long_"""")}, {"name": "n", "value": "2"}], "a 5,000-character value is whole")
	Do $$$AssertEquals($Length(..Inputs(1)), $Length([{"name": "note", "value": (""""_long_"""")}, {"name": "n", "value": "2"}].%ToJSON()), "and the notice holds all of it")
	Do ..ExpectInputs(session, "{""id"":""T-1"",""n"":2,""ok"":true,""none"":null,""obj"":{""a"":[1,2]},""z"":""last""}", [{"name": "id", "value": ("""T-1""")}, {"name": "n", "value": "2"}, {"name": "ok", "value": "true"}, {"name": "none", "value": "null"}, {"name": "obj", "value": ("{""a"":[1,2]}")}, {"name": "z", "value": ("""last""")}], "each top-level member is a line, in the stored order, with its JSON text")
	Do ..ExpectInputs(session, "{""api_key"":""abc123"",""q"":""x""}", [{"name": "api_key", "value": ("""[redacted]""")}, {"name": "q", "value": ("""x""")}], "a key rule masks a value: the whole object is redacted first")
	Do $$$AssertTrue(..Inputs(..Calls()) '[ "abc123", "and the secret is nowhere in the slot")
	Do ..ExpectInputs(session, "{""password"":""zz-secret"",""cfg"":{""token"":""zz-secret-2""}}", [{"name": "password", "value": ("""[redacted]""")}, {"name": "cfg", "value": ("{""token"":""[redacted]""}")}], "a nested key is masked too")
	Do ..ExpectInputs(session, "{""note"":""a\nApprove: b"",""t"":""x\ty"",""q"":""say \""hi\"" a\\b""}", [{"name": "note", "value": ("""a\u000AApprove: b""")}, {"name": "t", "value": ("""x\u0009y""")}, {"name": "q", "value": ("""say \""hi\"" a\\b""")}], "a line break and a tab show as \uXXXX on one line, while \"" and \\ stay")
	Do ..ExpectInputs(session, "", [], "no arguments give an empty array")
	Do ..ExpectInputs(session, "{}", [], "an empty object gives an empty array")
	Do ..ExpectInputs(session, $Char(10)_"  ", [], "arguments of white space only give an empty array")
	Do $$$AssertEquals(..Warnings(), 0, "none of it logs a warning")
}

/// Arguments that can't be read send no notice and log one warning that names the request's Ref (fail closed): text that is not JSON, a JSON array or string, and a
/// text the redactor can't check (nested deeper than it reads).
Method TestToolCallUnreadableInputs()
{
	Set session = ..Session("toolunread")
	Set deep = ""
	For i = 1:1:150 Set deep = deep_"{""a"":"
	Set deep = deep_"1"
	For i = 1:1:150 Set deep = deep_"}"
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Redact).Text(deep), ##class(OcuTalon.Bridge.Redact).#UNCHECKED, "the fixture text is one that the redactor can't check")
	Set n = 0
	For arguments = "not json", "[1]", """x""", "42", deep {
		Set ref = ..ToolRow(session, "pending", {"ToolArguments": (arguments)})
		Set mark = ..LastLog()
		Do ..Fire(session, "approval.raised", ref)
		Do $$$AssertEquals(..Calls(), 0, "arguments '"_$Extract(arguments, 1, 20)_"' send no notice")
		Set count = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "ToolNoticeOf", ##class(OcuTalon.Core.BridgeSink).#ERRORTOOLNOTICE)
		Do $$$AssertEquals(count, 1, "and log one warning")
		Do $$$AssertTrue($Find(text, ref) > 0, "that names the request's Ref: "_text)
	}
	Do $$$AssertEquals(..Events(session, "approval").%Size(), 5, "while each approval event is published as before")
}

/// The one test of V10 (Story 21.10): an input that holds a zero-width space, U+202E, U+E0041, U+2028, CR LF and a tab shows, on the web and on Telegram, as the one line
/// with each of them written as \uXXXX, and neither text holds any of those characters.
Method TestToolCallInputsVisible()
{
	Set session = ..Session("toolvisible")
	Set note = "a"_$Char(8203)_"b"_$Char(8238)_"c"_$Char(56128,56385)_"d"_$Char(8232)_"e"_$Char(13,10)_"f"_$Char(9)_"g h"
	Set arguments = {"note": (note)}.%ToJSON()
	Set ref = ..ToolRow(session, "pending", {"ToolSource": "mcp:remote:@{config:AI.MCP.OcuTalon_zzvis}", "ToolArguments": (arguments)})
	Do ..Fire(session, "approval.raised", ref)
	Do $$$AssertEquals(..Calls(), 1, "the request sends one notice")
	Set key = ..NoticeCall(1, "catalogKey")
	Set slots = ..NoticeCall(1, "slots")
	Set line = "note: ""a\u200Bb\u202Ec\uDB40\uDC41d\u2028e\u000D\u000Af\u0009g h"""
	For channel = "web", "telegram" {
		Set text = ##class(OcuTalon.Msg.Catalog).Render(key, slots, channel, .sc)
		Do $$$AssertStatusOK(sc, channel_": the notice renders")
		Do $$$AssertEquals($Length(text, line) - 1, 1, channel_": the one line is there once")
		Do $$$AssertEquals($Length(text, $Char(10)), 5, channel_": and the text has the five lines of the request, so no input started a line of its own")
		For code = 8203, 8238, 8232, 13, 9 {
			Do $$$AssertTrue(text '[ $Char(code), channel_": no character U+"_$ZHex(code)_" is in the text")
		}
		Do $$$AssertTrue(text '[ $Char(56128, 56385), channel_": nor the tag character")
		Do $$$AssertTrue(text '[ $Char(56128), channel_": nor a half of it")
	}
}

/// approval.cancelled (Story 21.10): a replayable MCP call whose server has no Mcp.Server row any more sends answered.canceled {time, server} and its approval event carries
/// server and cancelledAt, the one time of the sink's clock; with the server still registered, a call of a developer's tool or an unnamed server it sends nothing and the event has no
/// cancelledAt.
Method TestToolCallCancelledOnlyForARemovedServer()
{
	Set session = ..Session("toolcancel")
	Set ref = ..ToolRow(session, "cancelled", {"ToolSource": "mcp:remote:@{config:AI.MCP.OcuTalon_zzgone}"})
	Set ^OcuTalonTest("BridgeSinkNotice", "registered", "zzgone") = 0
	Do ..Fire(session, "approval.cancelled", ref)
	Do $$$AssertEquals(..Calls(), 1, "a cancel whose server is gone sends one notice")
	Do ..ExpectNotice(1, session, ref, "answered", "answered.canceled", "server,time", "cancelled")
	Do $$$AssertEquals(..Slot(1, "server"), "zzgone", "that names the server")
	Set time = ..Slot(1, "time")
	Do $$$AssertTrue(time ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "and the time of the sink's clock: "_time)
	Set events = ..Events(session, "approval")
	Set payload = events.%Get(events.%Size() - 1).payload
	Do $$$AssertEquals(payload.state_"|"_payload.server_"|"_payload.cancelledAt, "cancelled|zzgone|"_time, "the approval event carries the server and the same time")
	Do $$$AssertEquals(..Warnings(), 0, "and nothing is logged")

	Set ^OcuTalonTest("BridgeSinkNotice", "registered", "zzgone") = 1
	Do ..Fire(session, "approval.cancelled", ref)
	Do $$$AssertEquals(..Calls(), 1, "with the server still registered it sends nothing more")
	Set events = ..Events(session, "approval")
	Set payload = events.%Get(events.%Size() - 1).payload
	Do $$$AssertEquals(payload.state_"|"_payload.server_"|"_payload.%Get("cancelledAt"), "cancelled|zzgone|", "and the event has the server but no cancelledAt")

	Set plain = ..ToolRow(session, "cancelled")
	Do ..Fire(session, "approval.cancelled", plain)
	Do $$$AssertEquals(..Calls(), 1, "a call of a developer's tool sends nothing")
	Set events = ..Events(session, "approval")
	Set payload = events.%Get(events.%Size() - 1).payload
	Do $$$AssertEquals(payload.%Get("server")_"|"_payload.%Get("cancelledAt"), "|", "and its event has neither member")
	Set bare = ..ToolRow(session, "cancelled", {"ToolSource": "mcp:"})
	Do ..Fire(session, "approval.cancelled", bare)
	Do $$$AssertEquals(..Calls(), 1, "an MCP source with no server sends nothing")
	Set unreplayable = ..ToolRow(session, "cancelled", {"ToolSource": "mcp:remote:@{config:AI.MCP.OcuTalon_zzgone}", "Runner": ""})
	Set ^OcuTalonTest("BridgeSinkNotice", "registered", "zzgone") = 0
	Do ..Fire(session, "approval.cancelled", unreplayable)
	Do $$$AssertEquals(..Calls(), 1, "a held call that can't be replayed sends nothing")
	Do $$$AssertEquals(..Warnings(), 0, "and nothing is logged")
}

/// A request that is not a replayable tool_call of a session that exists sends no notice, though its approval event is published as
/// before: a fix, a setting, a held call with an empty ToolSource or Runner, the owners instance, eval and a Ref with no session,
/// and another session's request.
Method TestToolCallNoticesOnlyForReplayableSessionRows()
{
	Set session = ..Session("toolonly")
	Set other = ..Session("toolother")
	Set noSession = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set fix = ##class(OcuTalon.Test.Data.Fixture).Approval(session, , "pending")
	Set setting = ..ToolRow(session, "pending", {"Kind": "setting"})
	Set noSource = ..ToolRow(session, "pending", {"ToolSource": ""})
	Set noRunner = ..ToolRow(session, "pending", {"Runner": ""})
	Set instance = ..ToolRow("instance", "pending")
	Set eval = ..ToolRow("eval", "pending")
	Set lost = ..ToolRow(noSession, "pending")
	Set theirs = ..ToolRow(other, "pending")
	Set ..Refs = ..Refs_","_fix
	Do ..Change(fix, {"ToolSource": "OcuTalon.Test.Bridge.ZzReplayTool", "Runner": "ChatAgent", "ToolName": "zz_send"})
	Set sent = 0
	Set types = $ListBuild("approval.raised", "approval.answered", "approval.expired", "approval.cancelled", "approval.result")
	For row = fix, setting, noSource, noRunner, theirs {
		Do ..Change(row, {"AnsweredAction": "approve", "AnsweredChannel": "phone", "AnsweredAt": "2030-01-01T10:05:00Z", "Result": "done", "FinishedAt": "2030-01-01T10:06:00Z"})
		Set position = 0
		While $ListNext(types, position, type) {
			Do ..Fire(session, type, row)
		}
	}
	For owner = "instance", "eval", noSession {
		Set row = $Case(owner, "instance": instance, "eval": eval, : lost)
		Do ..Change(row, {"AnsweredAction": "approve", "AnsweredChannel": "phone", "AnsweredAt": "2030-01-01T10:05:00Z", "Result": "done", "FinishedAt": "2030-01-01T10:06:00Z"})
		Set position = 0
		While $ListNext(types, position, type) {
			Do ..Fire(owner, type, row)
		}
	}
	Do $$$AssertEquals(..Calls(), 0, "no notice was sent for any of them")
	Do $$$AssertEquals(..Events(session, "approval").%Size(), 4 * 5, "while the session's own four requests published their approval events as before (the other session's is not its)")
	Do $$$AssertEquals(..Warnings(), 0, "and nothing is logged")
}

/// DW-454: an approved call held before ToolSource and Runner existed is closed failed by Decide, and approval.result sends nothing for
/// it. Its fallback Decision then sends the one result notice with the bridge's reason (DecisionRef set, no buttons), and the approval
/// event carries that reason. An empty reason, or a row that is not failed, sends nothing.
Method TestHeldBeforeUpdateSaysWhy()
{
	Set session = ..Session("toolheld")
	Set sentence = $Parameter("OcuTalon.Bridge.Process.Decide", "HELDBEFOREUPDATE")
	Set finishedAt = "2030-01-01T10:06:00Z"
	Set fields = {"ToolSource": "", "Result": "failed", "FinishedAt": (finishedAt)}
	For variant = "source", "runner" {
		Kill ^OcuTalonTest("BridgeSinkNotice")
		Set row = ..ToolRow(session, "failed", $Select(variant = "source": fields, 1: {"Runner": "", "Result": "failed", "FinishedAt": (finishedAt)}))
		Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "tool", finishedAt, {"ItemId": (row), "Fallback": 1, "FallbackReason": "error", "Reasons": (sentence)})
		Set ..Refs = ..Refs_","_decision
		Set before = ..Events(session, "approval").%Size()
		Do ..Fire(session, "approval.result", row)
		Do $$$AssertEquals(..Calls(), 0, variant_": approval.result sends nothing for the old held row")
		Do $$$AssertEquals(..Events(session, "approval").%Size(), before + 1, variant_": its approval event is published as before")
		Do $$$AssertStatusOK(..NoticeSink("decision.recorded", session, {"ref": (decision)}), variant_": decision.recorded: OnEvent returns OK")
		Do $$$AssertEquals(..Calls(), 1, variant_": exactly one notice is sent")
		Do ..ExpectNotice(1, session, row, "result", "toolCall.failedWithReason", "reason,tool", variant, decision)
		Do $$$AssertEquals(..Slot(1, "tool")_"|"_..Slot(1, "reason"), "zz_send|"_sentence, variant_": with the tool and the bridge's sentence")
		Set events = ..Events(session, "approval")
		Do $$$AssertEquals(events.%Size(), before + 2, variant_": one more approval event is published")
		Set payload = events.%Get(events.%Size() - 1).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.state_"|"_payload.reason, row_"|failed|"_sentence, variant_": for the request, failed, with the reason")
		Do $$$AssertEquals(events.%Get(events.%Size() - 2).payload.reason, "", variant_": the result event had none")
	}

	Kill ^OcuTalonTest("BridgeSinkNotice")
	Set before = ..Events(session, "approval").%Size()
	For case = "empty", "notFailed", "replayable", "plain", "decide", "fix", "noSession" {
		Set owner = $Select(case = "noSession": ##class(OcuTalon.Bridge.Ids).NewRef(), 1: session)
		Set row = $Case(case, "notFailed": ..ToolRow(owner, "approved", {"ToolSource": ""}), "replayable": ..ToolRow(owner, "failed", {"Result": "failed", "FinishedAt": (finishedAt)}), "fix": ..ToolRow(owner, "failed", {"Kind": "fix", "ToolSource": "", "Result": "failed", "FinishedAt": (finishedAt)}), : ..ToolRow(owner, "failed", fields))
		Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, $Select(case = "decide": "decide", 1: "tool"), finishedAt, {"ItemId": (row), "Fallback": ($Select(case = "plain": 0, 1: 1)), "Reasons": ($Select(case = "empty": "", 1: sentence))})
		Set ..Refs = ..Refs_","_decision
		Do $$$AssertStatusOK(..NoticeSink("decision.recorded", owner, {"ref": (decision)}), case_": a decision that does not describe an old held failure: OnEvent returns OK")
	}
	Do $$$AssertEquals(..Calls(), 0, "no reason, a row that is not failed, a replayable row, no fallback, another decision kind, a fix row and an owner with no session send nothing")
	Do $$$AssertEquals(..Events(session, "approval").%Size(), before, "and publish no approval event")
	Do $$$AssertEquals(..Warnings(), 0, "and log nothing")
}

/// U-212 (3): a reason in a notice is only ever one of the bridge's, never raw error text. A fallback Decision whose first Reasons line
/// is raw error text sends toolCall.failed with the tool and the time only, and publishes no approval event.
Method TestHeldReasonIsCatalogOnly()
{
	Set session = ..Session("toolraw")
	Set raw = "ERROR #5002: ObjectScript error: <UNDEFINED>zRun+3^Zz.Tool"
	Set finishedAt = "2030-01-01T10:06:00Z"
	Set row = ..ToolRow(session, "failed", {"ToolSource": "", "Result": "failed", "FinishedAt": (finishedAt)})
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "tool", finishedAt, {"ItemId": (row), "Fallback": 1, "Reasons": (raw_$Char(10)_"second line")})
	Set ..Refs = ..Refs_","_decision
	Do $$$AssertStatusOK(..NoticeSink("decision.recorded", session, {"ref": (decision)}), "decision.recorded: OnEvent returns OK")
	Do $$$AssertEquals(..Calls(), 1, "one notice is sent")
	Do ..ExpectNotice(1, session, row, "result", "toolCall.failed", "time,tool", "raw reason", decision)
	Do $$$AssertEquals(..Slot(1, "tool")_"|"_..Slot(1, "time"), "zz_send|"_finishedAt, "with the tool and when it finished")
	Do $$$AssertTrue(..NoticeCall(1, "slots") '[ "ERROR", "no slot holds the raw text")
	Do $$$AssertEquals(..Events(session, "approval").%Size(), 0, "and no approval event is published")
	Do $$$AssertEquals(..Holding("ERROR #5002", "approval"), 0, "so no approval payload holds the raw text")
}

/// A notice that cannot be sent is one warning that names the event and the request, from a failed status and from a throw alike, for a
/// tool call's request and for an old held call's reason. OnEvent still returns OK and the approval event is still published.
Method TestToolCallNoticeFailureIsLogged()
{
	Set session = ..Session("toolfail")
	Set ref = ..ToolRow(session, "pending")
	Set count = 0
	For mode = "failNotice", "throwNotice" {
		Kill ^OcuTalonTest("BridgeSinkNotice")
		Set ^OcuTalonTest("BridgeSinkNotice", mode) = 1
		Set mark = ..LastLog()
		Do $$$AssertStatusOK(..NoticeSink("approval.raised", session, {"ref": (ref)}), mode_": OnEvent returns OK")
		Set found = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "ToolNotice", ##class(OcuTalon.Core.BridgeSink).#ERRORTOOLNOTICE)
		Do $$$AssertEquals(found, 1, mode_": one warning: "_text)
		Do $$$AssertTrue($Find(text, "approval.raised") && $Find(text, ref), mode_": it names the event and the request")
		Set count = count + 1
		Do $$$AssertEquals(..Events(session, "approval").%Size(), count, mode_": the approval event is still published")
	}

	Set sentence = $Parameter("OcuTalon.Bridge.Process.Decide", "HELDBEFOREUPDATE")
	Set finishedAt = "2030-01-01T10:06:00Z"
	Set held = ..ToolRow(session, "failed", {"ToolSource": "", "Result": "failed", "FinishedAt": (finishedAt)})
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(session, "tool", finishedAt, {"ItemId": (held), "Fallback": 1, "Reasons": (sentence)})
	Set ..Refs = ..Refs_","_decision
	For mode = "failNotice", "throwNotice" {
		Kill ^OcuTalonTest("BridgeSinkNotice")
		Set ^OcuTalonTest("BridgeSinkNotice", mode) = 1
		Set mark = ..LastLog()
		Set before = ..Events(session, "approval").%Size()
		Do $$$AssertStatusOK(..NoticeSink("decision.recorded", session, {"ref": (decision)}), "held "_mode_": OnEvent returns OK")
		Set found = ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "HeldNotice", ##class(OcuTalon.Core.BridgeSink).#ERRORTOOLNOTICE)
		Do $$$AssertEquals(found, 1, "held "_mode_": one warning: "_text)
		Do $$$AssertTrue($Find(text, "decision.recorded") && $Find(text, held), "held "_mode_": it names the event and the request")
		Do $$$AssertEquals(..Events(session, "approval").%Size(), before + 1, "held "_mode_": the reason event is still published")
	}
}

/// --- helpers ---
/// A fixture session, recorded for the clean-up.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzsink"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A fixture session that is open (it has a resume hash) and so can be sent the daily-cap message; recorded for the clean-up.
Method Visitor(name As %String) As %String [ Private ]
{
	Set ref = ..Session(name)
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set row.ResumeHash = ##class(OcuTalon.Data.Session).Hash("zzsink"_..Number_name)
	Do $$$AssertStatusOK(row.%Save(), "the session "_name_" is open")
	Quit ref
}

/// A tool_call request of the owner that the bridge can replay (tool zz_send with the arguments {"to":"ops"}, a class as its ToolSource and a
/// runner), recorded for the clean-up; fields, an object of property names and values, is set after the defaults.
Method ToolRow(owner As %String, state As %String, fields As %DynamicObject = "") As %String [ Private ]
{
	Set row = {"Kind": "tool_call", "ToolName": "zz_send", "ToolArguments": ("{""to"":""ops""}"), "ToolSource": "OcuTalon.Test.Bridge.ZzReplayTool", "Runner": "ChatAgent", "DryRun": ""}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.key, .value) {
			Do row.%Set(key, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Approval(owner, , state, , row)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// Sets the properties of the request's row (an object of names and values) and saves it.
Method Change(ref As %String, fields As %DynamicObject) [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Set iterator = fields.%GetIterator()
	While iterator.%GetNext(.key, .value) {
		Set $Property(row, key) = value
	}
	Do $$$AssertStatusOK(row.%Save(), "the request is changed")
}

/// OnEvent of the probe for the approval.* type of the request, which must return OK.
Method Fire(owner As %String, type As %String, ref As %String) [ Private ]
{
	Do $$$AssertStatusOK(..NoticeSink(type, owner, {"ref": (ref)}), type_": OnEvent returns OK")
}

/// The number of notices that the probe recorded.
Method Calls() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("BridgeSinkNotice", "calls"))
}

/// The inputs slot of a recorded notice, as JSON text.
Method Inputs(n As %Integer) As %String [ Private ]
{
	Quit ..Slot(n, "inputs").%ToJSON()
}

/// Raises a request of the session with the arguments and checks that its notice (the newest) holds exactly the inputs.
Method ExpectInputs(session As %String, arguments As %String, expected As %DynamicArray, label As %String) [ Private ]
{
	Set before = ..Calls()
	Set ref = ..ToolRow(session, "pending", {"ToolArguments": (arguments)})
	Do ..Fire(session, "approval.raised", ref)
	Do $$$AssertEquals(..Calls(), before + 1, label_": one notice is sent")
	Do $$$AssertEquals(..Inputs(before + 1), expected.%ToJSON(), label)
}

/// A slot of a recorded notice.
Method Slot(n As %Integer, name As %String) As %String [ Private ]
{
	Set slots = ..NoticeCall(n, "slots")
	Quit $Select(slots = "": "", 1: {}.%FromJSON(slots).%Get(name))
}

/// Checks the recorded notice n: it is for the session and the request, of the kind and with the key, has exactly the slots (names,
/// comma-separated and sorted), no IncidentRef and the DecisionRef given ("" for none).
Method ExpectNotice(n As %Integer, session As %String, ref As %String, kind As %String, key As %String, slotNames As %String, label As %String, decisionRef As %String = "") [ Private ]
{
	Do $$$AssertEquals(..NoticeCall(n, "sessionRef")_"|"_..NoticeCall(n, "approvalRef")_"|"_..NoticeCall(n, "incidentRef"), session_"|"_ref_"|", label_": for the session and the request, with no incident")
	Do $$$AssertEquals(..NoticeCall(n, "kind")_"|"_..NoticeCall(n, "catalogKey"), kind_"|"_key, label_": of kind "_kind_" with the key "_key)
	Do $$$AssertEquals($Select(..NoticeCall(n, "slots") = "": "<no notice>", 1: ..Keys({}.%FromJSON(..NoticeCall(n, "slots")))), slotNames, label_": with the slots "_slotNames)
	Do $$$AssertEquals(..NoticeCall(n, "decisionRef"), decisionRef, label_": and "_$Select(decisionRef = "": "no decision", 1: "the decision's Ref"))
}

/// OnEvent of the sink that records its notices (Test.Core.BridgeSinkNoticeProbe).
Method NoticeSink(type As %String, owner As %String, payload As %RegisteredObject) As %Status [ Private ]
{
	Quit $ClassMethod("OcuTalon.Test.Core.BridgeSinkNoticeProbe", "OnEvent", type, owner, payload)
}

/// The number of notices that the probe recorded for the session.
Method Notices(session As %String) As %Integer [ Private ]
{
	Set count = 0
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("BridgeSinkNotice", "calls", n))
		Quit:n=""
		If ^OcuTalonTest("BridgeSinkNotice", "calls", n, "sessionRef") = session Set count = count + 1
	}
	Quit count
}

/// The number of the newest notice that the probe recorded for the session, "" for none.
Method NoticeOf(session As %String) As %Integer [ Private ]
{
	Set found = ""
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("BridgeSinkNotice", "calls", n))
		Quit:n=""
		If ^OcuTalonTest("BridgeSinkNotice", "calls", n, "sessionRef") = session Set found = n
	}
	Quit found
}

/// One field of one recorded notice.
Method NoticeCall(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("BridgeSinkNotice", "calls", n, field))
}

/// The session's DailyCapDay, read from disk.
Method DayOf(session As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
	Do row.%Reload()
	Quit row.DailyCapDay
}

/// OnEvent of the real sink.
Method Sink(type As %String, owner As %String, payload As %RegisteredObject) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.BridgeSink).OnEvent(type, owner, payload)
}

/// The events of the session's stream, in order, as an array of envelopes; with a type, only the events of that type, so that a
/// heartbeat tick that publishes a check event in the middle of a test cannot change a count (DW-300).
Method Events(session As %String, type As %String = "") As %DynamicArray [ Private ]
{
	Set events = ##class(OcuTalon.Live.Event).Since(session, 0, 200, "session")
	If type = "" Quit events
	Set found = []
	For i = 0:1:events.%Size() - 1 {
		If events.%Get(i).type = type Do found.%Push(events.%Get(i))
	}
	Quit found
}

/// A production check of the session that no heartbeat tick can run: it is due a day ahead (DW-300), and the row's NextDueAt is
/// asserted to be more than 23 hours from now. Returns the row's Ref.
Method Check(session As %String, namespace As %String, production As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, namespace, production, {"NextDueAt": (##class(OcuTalon.Test.Watch.Case).Ahead())})
	Set due = ##class(OcuTalon.Data.Time).Seconds(##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref).NextDueAt)
	Do $$$AssertTrue(due > (##class(OcuTalon.Data.Time).Seconds(##class(OcuTalon.Data.Time).NowUtc()) + (23 * 3600)), "the check row of "_production_" is due more than 23 hours from now, so no heartbeat tick runs it")
	Quit ref
}

/// The number of events of any stream whose payload holds the text; with a type, only the events of that type.
Method Holding(text As %String, type As %String = "") As %Integer [ Private ]
{
	If type '= "" {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Live.Event WHERE Payload [ ? AND Type = ?", text, type)
		Do result.%Next()
		Quit +result.%GetData(1)
	}
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
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceClass IN (?, ?, ?, ?)", mark, "OcuTalon.Core.BridgeSink", "OcuTalon.Test.Core.BridgeSinkProbe", "OcuTalon.Test.Core.BridgeSinkRefusedProbe", "OcuTalon.Test.Core.BridgeSinkNoticeProbe")
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
