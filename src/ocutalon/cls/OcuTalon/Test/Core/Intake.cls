/// Tests of Intake (Story 2.7; AD-6, AD-10, AD-14, AD-22, AD-26, AD-30). Safe on a slot: no production runs there, so the tests
/// call OnRequest on shadow instances of OcuTalon.Test.Core.IntakeProbe, which hands each request to Decide to
/// OcuTalon.Test.Core.DecideDouble and keeps its answer until the test delivers it, the way the framework would, and records every
/// other send with its message. The real Interoperability path is the job of OcuTalon.Test.Core.RoutingProduction. Every text and
/// every field is written out here, never read from Intake.
///   - TestDecideRequest: the decide request of a mail Item has every field, the summaries of mail and text Items are written the
///     way the spec words them and cut at 80 characters, and the trace is the Item's;
///   - TestEachOutcomeSendsOneItemDecision: whatever Decide decided, one ItemDecision with every field goes to OutcomeRouter, with
///     the CatalogKey and Slots of the Item copied, and only an act runs a turn first;
///   - TestActRunsAnUntrustedFreshTurn: an act sends an untrusted, fresh turn with no seed, and the ItemDecision after the turn's
///     answer, a turn error, a turn answer of another class and a turn send that fails included;
///   - TestEvalGoesToEvalSinkOnly, TestInstanceGoesToOutcomeRouter: the owner decides where the ItemDecision goes;
///   - TestDecideFailureIsAFallback: an error status, a failed send, no answer, an answer of another class and an unknown outcome
///     give the fallback tellnow with no DecisionRef; a fallback answer keeps its reason, or unusable for an unknown one;
///   - TestRefusedItems: a message that is not an Item, user provenance, no ItemId, no owner and no content send nothing and log a
///     warning;
///   - TestNeverTouchesTheConversation: no send to Conversation or Notify, no Turn row, no live event, and no call of the catalog,
///     of SendRequestSync or of Live.Publish in Intake's source;
///   - TestCallbackFailureSendsTheFallback: a failure inside the class, in OnRequest or in an answer, still sends the one
///     ItemDecision, a second answer sends no second one, and an error that the framework hands OnError with no completion key
///     stays an error.
/// The fixture sessions come from Test.Data.Fixture, and the Decision rows that the double records are removed with them. The
/// run's number is n from ^OcuTalonTest("Intake","n") (never reset); the probe records the calls of the run under
/// ^OcuTalonTest("IntakeProbe", n), and the double's scripts and records are removed for each owner, and so are the lines that
/// the probes logged (the failures that the tests make them log).
Class OcuTalon.Test.Core.Intake Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The number of the newest row of the event log when the run began: what the probes log after it is removed with the run.
Property LogMark As %Integer;

/// The owners (sessions, eval and instance) whose double scripts the run made, comma-separated.
Property Owners As %String(MAXLEN = "");

/// The thread (trace session id) that the probes run in.
Parameter THREAD = 4242;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("Intake", "n"))
	Set ..Refs = ""
	Set ..Owners = ""
	Set ..LogMark = ..LastLog()
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("IntakeProbe", ..Number)
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	For i = 1:1:$Length(..Owners, ",") {
		If $Piece(..Owners, ",", i) = "" Continue
		Set written = ##class(OcuTalon.Test.Core.DecideDouble).Written($Piece(..Owners, ",", i))
		If written '= "" Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_written
	}
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Bridge.Context).End()
	For i = 1:1:$Length(..Owners, ",") {
		If $Piece(..Owners, ",", i) '= "" Do ##class(OcuTalon.Test.Core.DecideDouble).Clear($Piece(..Owners, ",", i))
	}
	Kill ^OcuTalonTest("IntakeProbe", ..Number)
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND UPPER(SourceClass) = 'OCUTALON.TEST.CORE.INTAKEPROBE'", ..LogMark)
	Quit $SYSTEM.Status.OK()
}

/// The decide request of a mail Item: untrusted, every field from the Item, the summary "{Sender}: {Subject}", the owner
/// session's TraceRef as the trace and the instance's own session as the thread. A SuperSession on the inbound header is kept.
/// The owner instance has no TraceRef.
Method TestDecideRequest()
{
	Set session = ..Session("request")
	Set item = ..Item(session)
	Set probe = ..NewProbe()
	Do $$$AssertStatusOK(probe.OnRequest(item, .response), "the Item is taken")
	Do $$$AssertEquals(..Calls(), 1, "one send")
	Do $$$AssertEquals(..Call(1, "target")_"|"_..Call(1, "class")_"|"_..Call(1, "key")_"|"_..Call(1, "required"), "Decide|OcuTalon.Bridge.Msg.Request|decide|1", "a Request to Decide, the key decide, an answer required")
	Do $$$AssertEquals(..Call(1, "kind")_"|"_..Call(1, "provenance"), "decide|untrusted", "the kind decide and the Item's provenance")
	Do $$$AssertEquals(..Call(1, "input"), ##class(OcuTalon.Agent.Input).Render(item), "the input is Agent.Input.Render of the Item")
	Do $$$AssertEquals(..Call(1, "itemId")_"|"_..Call(1, "ownerRef")_"|"_..Call(1, "channel"), item.ItemId_"|"_session_"|mailbox", "the ItemId, the owner and the channel")
	Do $$$AssertEquals(..Call(1, "summary"), "Dana: Invoice", "the summary is the sender and the subject")
	Do $$$AssertEquals(..Call(1, "traceRef"), ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef, "the trace is the owner session's TraceRef")
	Do $$$AssertEquals(..Call(1, "threadSessionId"), ..#THREAD, "the thread is the instance's trace session")
	Do $$$AssertEquals(..Call(1, "sessionMode")_"|"_..Call(1, "seedText"), "|", "no session mode and no seed")
	Do $$$AssertEquals(..Call(1, "sessionId")_"|"_..Call(1, "superSession"), ..#THREAD_"|"_##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef, "and the instance sent it in the item's trace session, under the owner's TraceRef")

	Kill ^OcuTalonTest("IntakeProbe", ..Number)
	Set probe = ..NewProbe()
	Set probe.%SuperSession = "ZzSuper"_..Number
	Do probe.OnRequest(..Item(session), .response)
	Do $$$AssertEquals(..Call(1, "traceRef")_"|"_..Call(1, "superSession"), "ZzSuper"_..Number_"|ZzSuper"_..Number, "a SuperSession on the inbound header is kept")

	Kill ^OcuTalonTest("IntakeProbe", ..Number)
	Do ..Own("instance")
	Set probe = ..NewProbe()
	Do probe.OnRequest(..Item("instance"), .response)
	Do $$$AssertEquals(..Call(1, "ownerRef")_"|"_..Call(1, "traceRef"), "instance|", "an instance owner has no trace of its own")

	Set long = $Translate($Justify("", 100), " ", "a")
	Set cases = $ListBuild($ListBuild("Dana", "Invoice", "zz body", "Dana: Invoice"), $ListBuild("Dana", "", "zz body", "Dana"), $ListBuild("", "Invoice", "zz body", "Invoice"))
	Set cases = cases_$ListBuild($ListBuild("", "", "zz first line"_$Char(10)_"second line", "zz first line"), $ListBuild("", "", "zz crlf"_$Char(13, 10)_"second", "zz crlf"))
	Set cases = cases_$ListBuild($ListBuild("  ", $Char(9)_"  ", "  "_$Char(10)_"  zz padded"_$Char(10)_"x", "zz padded"), $ListBuild("", "", long, $Extract(long, 1, 79)_$Char(8230)))
	Set cases = cases_$ListBuild($ListBuild($Extract(long, 1, 50), $Extract(long, 1, 50), "zz body", $Extract($Extract(long, 1, 50)_": "_$Extract(long, 1, 50), 1, 79)_$Char(8230)), $ListBuild("Dana", "Invoice"_$Char(10)_"second line", "zz body", "Dana: Invoice"))
	Set cases = cases_$ListBuild($ListBuild("", "", $Extract(long, 1, 81), $Extract(long, 1, 79)_$Char(8230)), $ListBuild("", "", $Extract(long, 1, 80), $Extract(long, 1, 80)))
	Set position = 0
	Set number = 0
	While $ListNext(cases, position, case) {
		Set number = number + 1
		Kill ^OcuTalonTest("IntakeProbe", ..Number)
		Set item = ..Item(session, {"Sender": ($List(case, 1)), "Subject": ($List(case, 2)), "Text": ($List(case, 3))})
		Do ..NewProbe().OnRequest(item, .response)
		Do $$$AssertEquals(..Call(1, "summary"), $List(case, 4), "summary "_number_" is written as the spec words it")
		Do $$$AssertEquals($Length(..Call(1, "summary")) <= 80, 1, "summary "_number_" is at most 80 characters")
	}
}

/// Whatever Decide decides, one ItemDecision goes to OutcomeRouter, asynchronously and with no answer, with the Item's ItemId,
/// SourceItemId, owner, channel, CatalogKey and Slots, the request's Summary and Decide's DecisionRef and outcome, Fallback 0 and
/// no reason. Only an act runs the turn first (the next test); no outcome sends anything else.
Method TestEachOutcomeSendsOneItemDecision()
{
	For outcome = "ignore", "digest", "tellnow", "act" {
		Set session = ..Session("out"_outcome)
		Do ##class(OcuTalon.Test.Core.DecideDouble).Record(session, 1)
		Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "decide", $ListBuild(outcome))
		Set slots = "{""production"":""Orders"",""time"":""2026-10-16T18:12:00Z""}"
		Set item = ..Item(session, {"SourceItemId": "zzcase7", "CatalogKey": "watch.productionStopped", "Slots": (slots)})
		Set probe = ..NewProbe()
		Do probe.OnRequest(item, .response)
		Do ..Pump(probe)
		Set decisions = ..Sent("OutcomeRouter")
		Do $$$AssertEquals($ListLength(decisions), 1, outcome_": one ItemDecision goes to OutcomeRouter")
		If $ListLength(decisions) '= 1 Continue
		Set n = $List(decisions, 1)
		Set ref = $Piece(##class(OcuTalon.Test.Core.DecideDouble).Written(session), ",", 1)
		Do $$$AssertEquals(..Call(n, "class")_"|"_..Call(n, "key")_"|"_..Call(n, "required"), "OcuTalon.Msg.ItemDecision||0", outcome_": an ItemDecision, asynchronous, with no answer")
		Do $$$AssertEquals(..Call(n, "itemId")_"|"_..Call(n, "sourceItemId")_"|"_..Call(n, "ownerRef")_"|"_..Call(n, "channel"), item.ItemId_"|zzcase7|"_session_"|mailbox", outcome_": the Item's ItemId, SourceItemId, owner and channel")
		Do $$$AssertEquals(..Call(n, "summary"), "Dana: Invoice", outcome_": the request's summary")
		Do $$$AssertEquals(..Call(n, "decisionRef")_"|"_..Call(n, "outcome")_"|"_..Call(n, "fallback")_"|"_..Call(n, "fallbackReason"), ref_"|"_outcome_"|0|", outcome_": Decide's DecisionRef and outcome, and no fallback")
		Do $$$AssertTrue(ref ? 22(1AN,1"-",1"_"), outcome_": the DecisionRef is a Ref")
		Do $$$AssertEquals(..Call(n, "catalogKey")_"|"_..Call(n, "slots"), "watch.productionStopped|"_slots, outcome_": the CatalogKey and Slots are copied as they are")
		Do $$$AssertEquals($ListLength(..Sent("Decide", "decide")), 1, outcome_": one decide request")
		Do $$$AssertEquals($ListLength(..Sent("Decide", "turn")), $Select(outcome = "act": 1, 1: 0), outcome_": "_$Select(outcome = "act": "the one turn of an act", 1: "no turn"))
		Do $$$AssertEquals(..Calls(), $Select(outcome = "act": 3, 1: 2), outcome_": and no other send")
	}
	Set session = ..Session("outplain")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "decide", $ListBuild("tellnow"))
	Do ..Pump(..Started(..Item(session)))
	Set n = $List(..Sent("OutcomeRouter"), 1)
	Do $$$AssertEquals(..Call(n, "catalogKey")_"|"_..Call(n, "slots")_"|"_..Call(n, "sourceItemId"), "||", "an Item with no CatalogKey, Slots or SourceItemId gives an ItemDecision with none")
}

/// An act runs a turn request before the ItemDecision: Decide gets a Request with the Kind turn, the provenance untrusted, the
/// SessionMode fresh and no SeedText, with the other fields of the decide request (the key turn, an answer required). The
/// ItemDecision follows the turn's answer, whatever it is: a reply, an error status, an answer of another class, and a send that
/// fails. It carries the decide's DecisionRef, not the turn's.
Method TestActRunsAnUntrustedFreshTurn()
{
	Set session = ..Session("act")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Record(session, 1)
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "decide", $ListBuild("act"))
	Set item = ..Item(session)
	Set probe = ..NewProbe()
	Do probe.OnRequest(item, .response)
	Do $$$AssertEquals(..Calls(), 1, "before Decide answers, only the decide request is sent")
	Do $$$AssertEquals(probe.Deliver(1), 1, "the decide answer arrives")
	Do $$$AssertEquals(..Calls(), 2, "the turn request is the second send, and no ItemDecision is sent yet")
	Do $$$AssertEquals(..Call(2, "target")_"|"_..Call(2, "class")_"|"_..Call(2, "key")_"|"_..Call(2, "required"), "Decide|OcuTalon.Bridge.Msg.Request|turn|1", "a Request to Decide, the key turn, an answer required")
	Do $$$AssertEquals(..Call(2, "kind")_"|"_..Call(2, "provenance")_"|"_..Call(2, "sessionMode")_"|"_..Call(2, "seedText"), "turn|untrusted|fresh|", "an untrusted turn in a fresh session, with no seed")
	Do $$$AssertEquals(..Call(2, "itemId")_"|"_..Call(2, "summary")_"|"_..Call(2, "ownerRef")_"|"_..Call(2, "channel"), item.ItemId_"|Dana: Invoice|"_session_"|mailbox", "the Item's ids, summary and channel")
	Do $$$AssertEquals(..Call(2, "traceRef")_"|"_..Call(2, "threadSessionId")_"|"_..Call(2, "input"), ..Call(1, "traceRef")_"|"_..#THREAD_"|"_..Call(1, "input"), "and the trace, the thread and the input of the decide request")
	Do $$$AssertEquals(probe.Deliver(1), 1, "the turn's answer arrives")
	Do $$$AssertEquals(..Calls(), 3, "the ItemDecision is sent after it")
	Do $$$AssertEquals(..Call(3, "target")_"|"_..Call(3, "outcome")_"|"_..Call(3, "fallback"), "OutcomeRouter|act|0", "an act, to OutcomeRouter")
	Set written = ##class(OcuTalon.Test.Core.DecideDouble).Written(session)
	Do $$$AssertEquals($Length(written, ","), 2, "the double recorded a decision for the decide and one for the turn")
	Do $$$AssertEquals(..Call(3, "decisionRef"), $Piece(written, ",", 1), "the ItemDecision carries the decide's DecisionRef")
	Do $$$AssertEquals(probe.Deliver(), 0, "and nothing else is pending")

	Set cases = $ListBuild("error", "wrong", "fallback:timeout", "failedsend")
	Set position = 0
	While $ListNext(cases, position, case) {
		Kill ^OcuTalonTest("IntakeProbe", ..Number)
		Set other = ..Session("act"_position)
		Do ##class(OcuTalon.Test.Core.DecideDouble).Script(other, "decide", $ListBuild("act"))
		Do ##class(OcuTalon.Test.Core.DecideDouble).Script(other, "turn", $ListBuild(case))
		Set probe = ..NewProbe()
		If case = "failedsend" Set probe.FailKey = "turn"
		Do probe.OnRequest(..Item(other), .response)
		Do ..Pump(probe)
		Set label = "a turn "_case
		Do $$$AssertEquals($ListLength(..Sent("Decide", "turn")), 1, label_": the turn request is sent")
		Set decisions = ..Sent("OutcomeRouter")
		Do $$$AssertEquals($ListLength(decisions), 1, label_": the ItemDecision is still sent, once")
		If $ListLength(decisions) = 1 Do $$$AssertTrue($List(decisions, 1) > $List(..Sent("Decide", "turn"), 1), label_": after the turn request")
		If $ListLength(decisions) = 1 Do $$$AssertEquals(..Call($List(decisions, 1), "outcome")_"|"_..Call($List(decisions, 1), "fallback"), "act|0", label_": still an act")
	}

	Kill ^OcuTalonTest("IntakeProbe", ..Number)
	Set other = ..Session("actorder")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(other, "decide", $ListBuild("act"))
	Set probe = ..NewProbe()
	Do probe.OnRequest(..Item(other), .response)
	Do probe.Deliver(1)
	Do $$$AssertEquals($ListLength(..Sent("OutcomeRouter")), 0, "an act's ItemDecision waits for the turn's answer")
}

/// An Item owned by eval: the ItemDecision of every outcome goes to EvalSink and to nothing else, an act's turn included (the
/// evaluation runs the same pipeline), and nothing goes to OutcomeRouter, Notify or Conversation.
Method TestEvalGoesToEvalSinkOnly()
{
	Do ..Own("eval")
	For outcome = "ignore", "digest", "tellnow", "act" {
		Kill ^OcuTalonTest("IntakeProbe", ..Number)
		Do ##class(OcuTalon.Test.Core.DecideDouble).Script("eval", "decide", $ListBuild(outcome))
		Set item = ..Item("eval", {"SourceItemId": "zzevalcase"})
		Do ..Pump(..Started(item))
		Set sink = ..Sent("EvalSink")
		Do $$$AssertEquals($ListLength(sink), 1, outcome_": one ItemDecision goes to EvalSink")
		If $ListLength(sink) = 1 {
			Set n = $List(sink, 1)
			Do $$$AssertEquals(..Call(n, "class")_"|"_..Call(n, "required")_"|"_..Call(n, "ownerRef")_"|"_..Call(n, "sourceItemId")_"|"_..Call(n, "outcome"), "OcuTalon.Msg.ItemDecision|0|eval|zzevalcase|"_outcome, outcome_": an ItemDecision of the evaluation owner, with the case id")
		}
		For target = "OutcomeRouter", "Notify", "Conversation" {
			Do $$$AssertEquals($ListLength(..Sent(target)), 0, outcome_": nothing goes to "_target)
		}
		Do $$$AssertEquals(..Calls(), $Select(outcome = "act": 3, 1: 2), outcome_": decide, "_$Select(outcome = "act": "turn, ", 1: "")_"and the one ItemDecision")
	}
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script("eval", "decide", $ListBuild("error"))
	Kill ^OcuTalonTest("IntakeProbe", ..Number)
	Do ..Pump(..Started(..Item("eval")))
	Set sink = ..Sent("EvalSink")
	Do $$$AssertEquals($ListLength(sink)_"|"_$ListLength(..Sent("OutcomeRouter")), "1|0", "the fallback of an evaluation item also goes to EvalSink only")
}

/// An Item owned by instance: the ItemDecision goes to OutcomeRouter, which routes it, and not to EvalSink.
Method TestInstanceGoesToOutcomeRouter()
{
	Do ..Own("instance")
	For outcome = "ignore", "digest", "tellnow", "act" {
		Kill ^OcuTalonTest("IntakeProbe", ..Number)
		Do ##class(OcuTalon.Test.Core.DecideDouble).Script("instance", "decide", $ListBuild(outcome))
		Set item = ..Item("instance")
		Do ..Pump(..Started(item))
		Set routed = ..Sent("OutcomeRouter")
		Do $$$AssertEquals($ListLength(routed), 1, outcome_": one ItemDecision goes to OutcomeRouter")
		If $ListLength(routed) = 1 Do $$$AssertEquals(..Call($List(routed, 1), "ownerRef")_"|"_..Call($List(routed, 1), "outcome"), "instance|"_outcome, outcome_": for the instance owner")
		Do $$$AssertEquals($ListLength(..Sent("EvalSink")), 0, outcome_": and none to EvalSink")
	}
}

/// What Decide answers that is not a usable DecisionResponse is the fallback: tellnow, Fallback 1, the reason unusable and no
/// DecisionRef, for an error status, a send that fails, no answer, an answer of another class and an unknown outcome. A fallback
/// answer keeps its DecisionRef and its reason, whatever outcome it carries, and the reason unusable when it is not one of
/// Msg.Enum FALLBACKREASON; a non-fallback answer has no reason. No fallback runs a turn.
Method TestDecideFailureIsAFallback()
{
	Set session = ..Session("fallback")
	Set cases = $ListBuild("error", "wrong", "reply", "zzunknown", "send", "none")
	Set position = 0
	While $ListNext(cases, position, case) {
		Kill ^OcuTalonTest("IntakeProbe", ..Number)
		Set item = ..Item(session)
		Set label = "a decide answer '"_case_"'"
		Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "decide", $ListBuild(case))
		Set probe = ..NewProbe()
		If case = "send" Set probe.FailTarget = "Decide"
		If case = "none" {
			Do probe.OnResponse(item, , "", "", "decide")
		} Else {
			Do probe.OnRequest(item, .response)
			Do ..Pump(probe)
		}
		Set routed = ..Sent("OutcomeRouter")
		Do $$$AssertEquals($ListLength(routed), 1, label_": one ItemDecision is sent")
		If $ListLength(routed) = 1 {
			Set n = $List(routed, 1)
			Do $$$AssertEquals(..Call(n, "outcome")_"|"_..Call(n, "fallback")_"|"_..Call(n, "fallbackReason")_"|"_..Call(n, "decisionRef"), "tellnow|1|unusable|", label_": the fallback tellnow, Fallback 1, unusable, no DecisionRef")
			Do $$$AssertEquals(..Call(n, "itemId")_"|"_..Call(n, "ownerRef")_"|"_..Call(n, "summary"), item.ItemId_"|"_session_"|Dana: Invoice", label_": with the Item's ids and the summary")
		}
		Do $$$AssertEquals($ListLength(..Sent("Decide", "turn")), 0, label_": and no turn")
	}

	Set cases = $ListBuild($ListBuild("refusal", "tellnow", "refusal"), $ListBuild("zz_unknown", "tellnow", "unusable"), $ListBuild("budget", "act", "budget"), $ListBuild("timeout", "ignore", "timeout"), $ListBuild("", "digest", "unusable"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Kill ^OcuTalonTest("IntakeProbe", ..Number)
		Set item = ..Item(session)
		Set label = "a fallback answer with the reason '"_$List(case, 1)_"' and the outcome "_$List(case, 2)
		Set answer = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
		Set answer.DecisionRef = "ZzFallbackRef"_position
		Set answer.Outcome = $List(case, 2)
		Set answer.Fallback = 1
		Set answer.FallbackReason = $List(case, 1)
		Do ..NewProbe().OnResponse(item, , "", answer, "decide")
		Set routed = ..Sent("OutcomeRouter")
		Do $$$AssertEquals($ListLength(routed), 1, label_": one ItemDecision is sent")
		If $ListLength(routed) = 1 {
			Set n = $List(routed, 1)
			Do $$$AssertEquals(..Call(n, "outcome")_"|"_..Call(n, "fallback")_"|"_..Call(n, "fallbackReason")_"|"_..Call(n, "decisionRef"), "tellnow|1|"_$List(case, 3)_"|ZzFallbackRef"_position, label_": tellnow, Fallback 1, the reason "_$List(case, 3)_" and the answer's DecisionRef")
		}
		Do $$$AssertEquals($ListLength(..Sent("Decide", "turn")), 0, label_": no turn runs, even for an act")
	}

	Kill ^OcuTalonTest("IntakeProbe", ..Number)
	Set answer = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
	Set answer.DecisionRef = "ZzNotAFallback"
	Set answer.Outcome = "digest"
	Set answer.FallbackReason = "refusal"
	Do ..NewProbe().OnResponse(..Item(session), , "", answer, "decide")
	Set n = $List(..Sent("OutcomeRouter"), 1)
	Do $$$AssertEquals(..Call(n, "outcome")_"|"_..Call(n, "fallback")_"|"_..Call(n, "fallbackReason")_"|"_..Call(n, "decisionRef"), "digest|0||ZzNotAFallback", "a reason on an answer that is not a fallback is dropped")
}

/// Nothing is sent, and one warning is logged (naming the Item's ItemId and channel when it is an Item), for a message that is not an Item, user provenance, an empty provenance, no ItemId,
/// no owner, and an Item with no text, no subject and no sender (white space only). An Item with a sender only, or a subject
/// only, is taken.
Method TestRefusedItems()
{
	Set session = ..Session("refused")
	Set mark = ..LastLog()
	Set cases = $ListBuild("not an Item|it is not an Item", "user provenance|provenance is 'user', not untrusted", "no provenance|not untrusted", "no ItemId|no ItemId", "no owner|no owner", "no content|no text, subject or sender")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $Piece(case, "|", 1)
		Set item = ..Item(session)
		If label = "not an Item" Set item = ##class(Ens.StringRequest).%New("zz")
		If label = "user provenance" Set item.Provenance = "user"
		If label = "no provenance" Set item.Provenance = ""
		If label = "no ItemId" Set item.ItemId = ""
		If label = "no owner" Set item.SessionRef = ""
		If label = "no content" {
			Set item.Text = "  "_$Char(10)
			Set item.Sender = " "
			Set item.Subject = $Char(9)
		}
		Set before = ..Warnings(mark)
		Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), label_": the status is OK")
		Set after = ..Warnings(mark, .text)
		Do $$$AssertEquals(after - before, 1, label_": one warning is logged")
		Do $$$AssertEquals($Extract(text, 1, 24), "Intake refused an item: ", label_": it says an item was refused")
		Do $$$AssertTrue(text [ $Piece(case, "|", 2), label_": and why: "_text)
		If (label '= "not an Item") && (item.ItemId '= "") Do $$$AssertTrue(text [ (" (ItemId "_item.ItemId_", channel mailbox)"), label_": and which Item it was: "_text)
		Do $$$AssertEquals(..Calls(), 0, label_": nothing is sent")
	}
	Set total = ..Warnings(mark)
	Do $$$AssertEquals(total, $ListLength(cases), "one warning for each refused message")
	Set item = ..Item(session, {"Text": "", "Subject": ""})
	Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), "an Item with a sender only is taken")
	Set item = ..Item(session, {"Text": "", "Sender": ""})
	Do $$$AssertStatusOK(..NewProbe().OnRequest(item, .response), "an Item with a subject only is taken")
	Do $$$AssertEquals(..Calls(), 2, "each sends its decide request")
	Do $$$AssertEquals(..Warnings(mark), total, "and neither logs a warning")
	Do ..RemoveWarnings(mark)
}

/// Intake never sends to Conversation or Notify, writes no Turn row and publishes no live event, for any owner and outcome, and
/// its source never calls SendRequestSync (AD-6), renders through the catalog (AD-32), publishes (Live.Publish) or names the Turn
/// row; the scan is only trusted if it finds the asynchronous send.
Method TestNeverTouchesTheConversation()
{
	Set session = ..Session("never")
	Set before = ##class(OcuTalon.Live.Publish).LastSeq(session)
	For outcome = "ignore", "digest", "tellnow", "act", "error" {
		Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "decide", $ListBuild(outcome))
		Do ..Pump(..Started(..Item(session)))
	}
	Do ..Own("eval")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script("eval", "decide", $ListBuild("act"))
	Do ..Pump(..Started(..Item("eval")))
	Set targets = ""
	For n = 1:1:..Calls() {
		If '$Find(","_targets_",", ","_..Call(n, "target")_",") Set targets = targets_$Select(targets = "": "", 1: ",")_..Call(n, "target")
	}
	Do $$$AssertEquals(targets, "Decide,OutcomeRouter,EvalSink", "the only targets are Decide, OutcomeRouter and EvalSink")
	Do $$$AssertEquals($ListLength(..Sent("Conversation"))_"|"_$ListLength(..Sent("Notify")), "0|0", "nothing goes to Conversation or Notify")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Turns(session).Count(), 0, "the session has no Turn row")
	Do $$$AssertEquals(##class(OcuTalon.Live.Publish).LastSeq(session), before, "and its stream holds no new event")

	Set rules = $ListBuild("SendRequestSync", "OcuTalon.Msg.Catalog", "OcuTalon.Live.Publish", "OcuTalon.Data.Turn")
	Set definition = ##class(%Dictionary.ClassDefinition).%OpenId("OcuTalon.Core.Intake")
	Set async = 0
	Kill found
	For i = 1:1:definition.Methods.Count() {
		Set method = definition.Methods.GetAt(i)
		Do method.Implementation.Rewind()
		While 'method.Implementation.AtEnd {
			Set code = method.Implementation.Read(30000)
			If code [ "SendRequestAsync" Set async = async + 1
			Set position = 0
			While $ListNext(rules, position, rule) {
				If code [ rule Set found(rule) = $Get(found(rule))_" "_method.Name
			}
		}
	}
	Do $$$AssertTrue(async > 0, "the scan sees the asynchronous send")
	Set position = 0
	While $ListNext(rules, position, rule) {
		Do $$$AssertEquals($Get(found(rule)), "", "no method of Intake uses "_rule)
	}
}

/// A failure inside the class still sends the one ItemDecision: the fallback, once, when Decided throws in an answer or inside
/// OnRequest (a decide request that cannot be sent, and Decided throwing then); an answer that comes after the ItemDecision went
/// sends no second one; and an error that the framework hands OnError with no completion key stays an error, while one with a
/// key is kept for OnResponse.
Method TestCallbackFailureSendsTheFallback()
{
	Set session = ..Session("callback")
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "decide", $ListBuild("act"))
	Set probe = ..NewProbe()
	Set probe.ThrowIn = "decided"
	Do probe.OnRequest(..Item(session), .response)
	Do ..Pump(probe)
	Set routed = ..Sent("OutcomeRouter")
	Do $$$AssertEquals($ListLength(routed), 1, "one ItemDecision is sent")
	If $ListLength(routed) = 1 {
		Set n = $List(routed, 1)
		Do $$$AssertEquals(..Call(n, "outcome")_"|"_..Call(n, "fallback")_"|"_..Call(n, "fallbackReason")_"|"_..Call(n, "decisionRef"), "tellnow|1|unusable|", "the fallback tellnow")
	}
	Do $$$AssertEquals($ListLength(..Sent("Decide", "turn")), 0, "and no turn")
	Do $$$AssertEquals(probe.Deliver(), 0, "nothing is pending")

	Kill ^OcuTalonTest("IntakeProbe", ..Number)
	Set probe = ..NewProbe()
	Set probe.FailTarget = "Decide"
	Set probe.ThrowIn = "decided"
	Do $$$AssertStatusOK(probe.OnRequest(..Item(session), .response), "a decide request that cannot be sent, and Decided throwing then, is handled in OnRequest")
	Set routed = ..Sent("OutcomeRouter")
	Do $$$AssertEquals($ListLength(routed), 1, "one ItemDecision is sent")
	If $ListLength(routed) = 1 {
		Set n = $List(routed, 1)
		Do $$$AssertEquals(..Call(n, "outcome")_"|"_..Call(n, "fallback")_"|"_..Call(n, "fallbackReason")_"|"_..Call(n, "decisionRef"), "tellnow|1|unusable|", "the fallback tellnow")
	}

	Kill ^OcuTalonTest("IntakeProbe", ..Number)
	Do ##class(OcuTalon.Test.Core.DecideDouble).Script(session, "decide", $ListBuild("tellnow"))
	Set item = ..Item(session)
	Set probe = ..Started(item)
	Do ..Pump(probe)
	Do $$$AssertEquals($ListLength(..Sent("OutcomeRouter")), 1, "an answered item sends its ItemDecision")
	Do probe.OnResponse(item, , "", "", "decide")
	Do $$$AssertEquals($ListLength(..Sent("OutcomeRouter")), 1, "and a second answer sends no second one")

	Set probe = ..NewProbe()
	Set error = $SYSTEM.Status.Error(5001, "zz framework failed")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorText(probe.OnError("", , "", error, "")), $SYSTEM.Status.GetErrorText(error), "an error with no completion key stays an error")
	Do $$$AssertStatusOK(probe.OnError("", , "", error, "decide"), "an error with a key is handled")
}

/// --- helpers ---
/// A fixture session; its Ref is kept for the clean-up and the double's scripts are cleared.
Method Session(name As %String) As %String [ Private ]
{
	Kill ^OcuTalonTest("IntakeProbe", ..Number)
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzintake"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Do ..Own(ref)
	Quit ref
}

/// Remembers an owner whose double scripts and records the run clears, and clears them now.
Method Own(owner As %String) [ Private ]
{
	Do ##class(OcuTalon.Test.Core.DecideDouble).Clear(owner)
	If '$Find(","_..Owners_",", ","_owner_",") Set ..Owners = ..Owners_$Select(..Owners = "": "", 1: ",")_owner
}

/// A shadow instance of the probe, in the run's records, in the thread THREAD.
Method NewProbe() As OcuTalon.Test.Core.IntakeProbe [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Core.IntakeProbe", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of the probe is made")
	Set probe.RunNumber = ..Number
	Set probe.%SessionId = ..#THREAD
	Quit probe
}

/// A probe that has taken the Item.
Method Started(item As OcuTalon.Msg.Item) As OcuTalon.Test.Core.IntakeProbe [ Private ]
{
	Set probe = ..NewProbe()
	Do $$$AssertStatusOK(probe.OnRequest(item, .response), "the Item is taken")
	Quit probe
}

/// An untrusted mail Item of the channel mailbox from Dana, subject Invoice, with a new ItemId; fields, an object of property
/// names and values, is set after those.
Method Item(owner As %String, fields As %DynamicObject = "") As OcuTalon.Msg.Item [ Private ]
{
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set item.SessionRef = owner
	Set item.Channel = "mailbox"
	Set item.Provenance = "untrusted"
	Set item.Sender = "Dana"
	Set item.Subject = "Invoice"
	Set item.Text = "zz body"
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Set $Property(item, name) = value
		}
	}
	Quit item
}

/// Hands the kept answers of the probe to its callbacks until none is left.
Method Pump(probe As OcuTalon.Test.Core.IntakeProbe) [ Private ]
{
	For round = 1:1:50 {
		If 'probe.Deliver() Quit
	}
}

/// The number of calls the probes recorded.
Method Calls() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("IntakeProbe", ..Number))
}

/// One field of one recorded call.
Method Call(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("IntakeProbe", ..Number, n, field))
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

/// The number of the newest row of the event log.
Method LastLog() As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).LastLog()
}

/// The number of warnings that Intake logged for a refused item after the row mark (the event log names the class of the
/// instance); text is the newest one's text.
Method Warnings(mark As %Integer, Output text As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "OnRequest", "Intake refused an item")
}

/// Removes the warnings for a refused item that were logged after the row mark.
Method RemoveWarnings(mark As %Integer) [ Private ]
{
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "OnRequest", "Intake refused an item")
}

}
