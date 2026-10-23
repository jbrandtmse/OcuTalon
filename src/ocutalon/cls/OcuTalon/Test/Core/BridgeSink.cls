/// Tests of BridgeSink (Story 2.6; AD-31, AD-33), which turns the bridge's decision.recorded and turn.step events into live
/// events. The tests call OnEvent directly, with fixture rows from Test.Data.Fixture, and read the session's stream.
///   - TestDecisionRecordedPublishesTheDecision: a decide and a turn decision of a session each give one decision event with
///     every field of Decision.FromRow;
///   - TestEvalAndInstancePublishNothing, TestAnotherSessionsDecisionPublishesNothing: a decision of eval, of instance or of
///     another session is published nowhere;
///   - TestBadPayloadsPublishNothing: an empty or unknown ref, a payload that is not an object, approval.*, budget.capped and
///     an unknown type publish nothing;
///   - TestTurnStepForTheRunningTurn, TestTurnStepWithNoRunningTurn, TestTurnStepOfAnotherItem: turn.step carries the running
///     turn's Ref, the decision's Ref and the trimmed label, and only for the running turn of the item the bridge context is for;
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

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Set ..Number = $Increment(^OcuTalonTest("BridgeSink", "n"))
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Set ..Refs = ""
	Set ..LogMark = ..LastLog()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceClass IN (?, ?)", ..LogMark, "OcuTalon.Core.BridgeSink", "OcuTalon.Test.Core.BridgeSinkProbe")
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

/// An empty or unknown ref, a payload that is not an object, the approval and budget events, which are not built yet, and a
/// type the sink does not know publish nothing.
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

/// A stream whose lock another job holds does not hold OnEvent up: it returns OK after about a second, which tells the
/// sink's own wait from Publish's five seconds, publishes nothing and logs a warning. Once the job releases the lock the
/// same event publishes.
Method TestNeverWaitsMoreThanASecond()
{
	Set session = ..Session("lock")
	Set decision = ##class(OcuTalon.Test.Data.Fixture).Decision(session)
	Set turn = ##class(OcuTalon.Test.Data.Fixture).Turn(session, "2030-01-01T10:00:01Z", "running")
	Set ..Refs = ..Refs_","_decision_","_turn
	Kill ^OcuTalonTest("BridgeSink", "hold", session)
	Job ##class(OcuTalon.Test.Core.BridgeSink).Hold(session)
	Do ..WaitFor($Name(^OcuTalonTest("BridgeSink", "hold", session, "ready")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("BridgeSink", "hold", session, "ready")), 1, "another job holds the stream's lock")
	For case = "decision.recorded", "turn.step" {
		Set payload = $Select(case = "turn.step": {"decisionRef": "ZzSinkDecision", "label": "Asking the model"}, 1: {"ref": (decision)})
		Set start = $ZHorolog
		Set sc = ..Sink(case, session, payload)
		Set elapsed = $ZHorolog - start
		Do $$$AssertStatusOK(sc, case_": OnEvent returns OK")
		Do $$$AssertTrue((elapsed >= 0.9) && (elapsed <= 4), case_": it waited about a second, not five: "_$FNumber(elapsed, "", 2)_" s")
	}
	Do $$$AssertEquals(..Warnings(), 2, "one warning is logged for each dropped event")
	Set ^OcuTalonTest("BridgeSink", "hold", session, "release") = 1
	Do ..WaitFor($Name(^OcuTalonTest("BridgeSink", "hold", session, "done")), 60)
	Do $$$AssertEquals($Get(^OcuTalonTest("BridgeSink", "hold", session, "done")), 1, "the job releases the lock")
	Do $$$AssertEquals(..Events(session).%Size(), 0, "nothing was published while it was held")
	Do $$$AssertStatusOK(..Sink("decision.recorded", session, {"ref": (decision)}), "the same event, once the lock is free: OnEvent returns OK")
	Do $$$AssertEquals(..Events(session).%Size(), 1, "publishes")
}

/// OnEvent returns OK for every type, owner and payload there is, including the ones that cannot be published; for an event
/// that fails to publish (an open transaction), where it logs a warning; and for a handler that throws, where it logs a warning
/// too.
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
	For type = "decision.recorded", "turn.step" {
		Do $$$AssertStatusOK($ClassMethod("OcuTalon.Test.Core.BridgeSinkProbe", "OnEvent", type, session, {"ref": (decision), "label": "zz label"}), "a handler that throws: "_type_" returns OK")
	}
	Do $$$AssertEquals(..Warnings(mark), 2, "and a warning is logged for each")
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
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceClass IN (?, ?)", mark, "OcuTalon.Core.BridgeSink", "OcuTalon.Test.Core.BridgeSinkProbe")
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

/// The job body of TestNeverWaitsMoreThanASecond: holds the stream's lock until released, then ends.
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
