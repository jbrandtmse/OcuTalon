/// Tests of the running Decide item (Story 1.3; AD-6, AD-7, AD-20, AD-26, AD-30). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): it needs OcuTalon.Production running after the Production step, the CI override's environment (the mock's base URL and
/// OCUTALON_MOCK_KEY_HEADER=1) and the mock's request log, and fails with the reason where it does not have them. Each request goes
/// through ApprovalStartIn to Decide, as a caller of Decide will send it (Test.Agent.RunnerFixture.Send). CI starts with no model
/// key on purpose, so the first test points the Config Store entry of each runner at the non-secret CI variable
/// OCUTALON_MOCK_KEY_HEADER, and OnAfterAllTests puts the entries back (Test.Agent.RunnerFixture.PointKeys and RestoreKeys).
/// The rows that Test.Bridge.Decide pins in process (the filter, the sink, the concurrent save, the bad settings) are not repeated.
///   - TestDecision: an untrusted decide request gets a DecisionResponse with a new DecisionRef, the digest of the default script
///     and its reason, and the Payload of the reply; the row holds the same, with the session of the response as TraceSessionId;
///     the runner's request carries the DecisionRef; the timer's Timeout is 60; Decide sends only the runner request and the timer
///     request, and answers only its caller;
///   - TestLowConfidence: act with a confidence of 0.12 is recorded and answered as it is;
///   - TestUserRule: a user's digest and ignore become tellnow with the code-written line first, a user's act stays, and an
///     untrusted ignore stays;
///   - TestRepeat: the same ItemId again gets the recorded decision, with no request to the mock or the runner and no second row;
///   - TestTurn: a user's turn gets the mock's final text with the outcome tellnow and its DecisionRef, one row of kind turn, the
///     rendered input as the text of a user-role message in every logged request and in no tool_result block; the same item again
///     is refused with an error that names the item and the DecisionRef, and nothing is sent;
///   - TestDiagnoseNeedsReplyClass: a diagnose request is refused, naming DiagnosisAgent and ReplyClass, and nothing is sent;
///   - TestUnusableEndsWithError: a reply that fails the check, and a runner error, end with an error status and record nothing;
///   - TestTimer: with TimerSeconds 2, a reply that comes after 6 s ends with an error that names the timer and TriageAgent, and no
///     row is recorded, before or after the late reply, whose header is discarded;
///   - TestRefused: a message of another class gets "not implemented" (5003, inside the error that ends the process) and a
///     request of an unknown kind an error that names the field, and nothing is sent;
///   - TestTraceFields: the XML of the recorded DecisionResponse holds Outcome, Reasons, Confidence, Fallback and FallbackReason,
///     and the row's TraceSessionId is the session of the response's header.
/// OnAfterOneTest deletes the rows its test made and the TimerSeconds row, starts Decide again if the test changed it, and waits
/// until TriageAgent has answered the late request. Every wait is a poll with a generous ceiling.
Class OcuTalon.Test.Agent.Decide Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The longest to wait for a late reply to reach Decide, in seconds. A ceiling, not a delay: the wait polls once a second.
Parameter WAITSECONDS = 120;

/// The first reason line of a user's decide request whose outcome was ignore or digest.
Parameter USERANSWERED = "The outcome was changed because a message the user writes is always answered.";

/// The final text of chat.json.
Parameter CHATTEXT = "The CI mock looked at the productions.";

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

/// 1 when the test wrote the TimerSeconds row and started Decide again.
Property DecideChanged As %Boolean [ InitialExpression = 0 ];

/// The session of a request whose late reply the test waits for, or "".
Property LateSession As %Integer;

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..LateSession '= "" {
		Do ..WaitForAnswer(..LateSession, "TriageAgent")
		Set ..LateSession = ""
	}
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Do ##class(Ens.Config.DefaultSettings).%DeleteId(..#PRODUCTION_"||Decide||*||TimerSeconds")
	If ..DecideChanged && ##class(OcuTalon.Test.Agent.RunnerFixture).Running() {
		Set ..DecideChanged = 0
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).Restart(..#PRODUCTION_"||Decide")
	}
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If ..Pointed && ##class(OcuTalon.Test.Agent.RunnerFixture).Running() {
		Set ..Pointed = 0
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreKeys()
	}
	Quit $$$OK
}

/// An untrusted decide request gets the decision of Triage's default script.
Method TestDecision()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = ..Run(request, .response, .session)
	Do $$$AssertStatusOK(sc, "Decide answers the decide request")
	If '$IsObject(response) || 'response.%IsA("OcuTalon.Bridge.Msg.DecisionResponse") {
		Do $$$AssertTrue(0, "the answer is a DecisionResponse")
		Quit
	}
	Do $$$AssertTrue(response.DecisionRef ? 22(1AN,1"-",1"_"), "the DecisionRef is a new 22-character reference: "_response.DecisionRef)
	Do $$$AssertEquals(response.Outcome, "digest", "the outcome is the digest of the default script")
	Do $$$AssertEquals(response.Reasons, "The CI mock keeps this item for the digest.", "with the reason of the mock")
	Do $$$AssertEquals(response.Confidence, .5, "and its confidence")
	Do $$$AssertEquals(response.Fallback_"|"_response.FallbackReason, "0|", "and no fallback")
	Do $$$AssertEquals(response.Payload, $Parameter(fixture, "TRIAGETEXT"), "the Payload is the reply's JSON")
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "decide")
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "one row is recorded for the item")
		Quit
	}
	Do $$$AssertEquals(row.Ref, response.DecisionRef, "the row has the DecisionRef of the answer")
	Do $$$AssertEquals(row.Kind_"|"_row.ItemId_"|"_row.OwnerRef_"|"_row.Summary, "decide|"_ref_"|instance|Test "_ref, "and the Kind, ItemId, OwnerRef and Summary of the request")
	Do $$$AssertEquals(row.Outcome_"|"_row.Reasons_"|"_row.Confidence_"|"_row.Fallback_"|"_row.FallbackReason, "digest|The CI mock keeps this item for the digest.|.5|0|", "and the same decision")
	Do $$$AssertEquals(row.Payload, response.Payload, "and the same Payload")
	Do $$$AssertEquals(row.TraceSessionId, $ClassMethod(fixture, "SessionOf", response), "TraceSessionId is the session of the response header")
	Do $$$AssertEquals(row.TraceSessionId, session, "which is the session of the request")
	Do $$$AssertTrue(row.RecordedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "RecordedAt is a UTC time: "_row.RecordedAt)

	Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
	Set targets = ..Targets(headers)
	Do $$$AssertEquals(targets, "ApprovalStartIn,Ens.Alarm,TriageAgent", "Decide sends only to TriageAgent, Ens.Alarm and its caller: "_targets)
	Set runner = ..HeaderTo(headers, "TriageAgent")
	Set alarm = ..HeaderTo(headers, "Ens.Alarm")
	If $IsObject(runner) {
		Do $$$AssertEquals(runner.bodyClass, "OcuTalon.Bridge.Msg.Request", "the runner gets a Request")
		Set sent = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(runner.bodyId)
		Do $$$AssertTrue($IsObject(sent) && (sent.DecisionRef = response.DecisionRef), "that carries the DecisionRef of the answer")
		Do $$$AssertTrue($IsObject(sent) && (sent.ItemId = ref) && (sent.Kind = "decide"), "and the item and kind of the request")
	} Else {
		Do $$$AssertTrue(0, "a header to TriageAgent exists")
	}
	If $IsObject(alarm) {
		Do $$$AssertEquals(alarm.bodyClass, "Ens.AlarmRequest", "the timer is an Ens.AlarmRequest")
		Set timer = ##class(Ens.AlarmRequest).%OpenId(alarm.bodyId)
		Do $$$AssertEquals($Select($IsObject(timer): timer.Timeout, 1: ""), 60, "with a Timeout of 60 seconds")
	} Else {
		Do $$$AssertTrue(0, "a header to Ens.Alarm exists")
	}
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Do $$$AssertEquals($ClassMethod(fixture, "FindRequests", entries, ref).%Size(), 1, "the mock got one model request for the item")
}

/// A reply of act with a confidence of 0.12 is recorded and answered as it is: the confidence never changes the outcome.
Method TestLowConfidence()
{
	If '..Prepare() Quit
	Set response = ..Case("untrusted", "decide-act-low-confidence", .row)
	If '$IsObject(response) || '$IsObject(row) Quit
	Do $$$AssertEquals(response.Outcome_"|"_response.Confidence, "act|.12", "the answer is act with 0.12")
	Do $$$AssertEquals(row.Outcome_"|"_row.Confidence, "act|.12", "and so is the row")
	Do $$$AssertEquals(response.Reasons, "The CI mock asks for an action.", "with the reason of the mock")
}

/// For a user's item, ignore and digest become tellnow with the code-written line first; a user's act and every untrusted outcome
/// stay.
Method TestUserRule()
{
	If '..Prepare() Quit
	Set sentence = ..#USERANSWERED
	Set response = ..Case("user", "", .row)
	If $IsObject(response) && $IsObject(row) {
		Do $$$AssertEquals(response.Outcome_"|"_row.Outcome, "tellnow|tellnow", "a user's digest becomes tellnow, in the answer and the row")
		Do $$$AssertEquals(row.Reasons, sentence_$Char(10)_"The CI mock keeps this item for the digest.", "with the code-written line first and the reason of the mock after it")
		Do $$$AssertEquals(response.Reasons, row.Reasons, "also in the answer")
		Do $$$AssertTrue(row.Payload [ """outcome"":""digest""", "and the Payload keeps the model's own outcome")
	}
	Set response = ..Case("user", "decide-ignore", .row)
	If $IsObject(response) && $IsObject(row) {
		Do $$$AssertEquals(response.Outcome_"|"_row.Outcome, "tellnow|tellnow", "a user's ignore becomes tellnow")
		Do $$$AssertEquals(row.Reasons, sentence_$Char(10)_"The CI mock ignores this item.", "with the code-written line first")
		Do $$$AssertTrue(row.Payload [ """outcome"":""ignore""", "and the Payload keeps the model's own outcome")
	}
	Set response = ..Case("user", "decide-act-low-confidence", .row)
	If $IsObject(response) && $IsObject(row) {
		Do $$$AssertEquals(response.Outcome_"|"_row.Outcome_"|"_row.Confidence, "act|act|.12", "a user's act stays act, with its confidence")
		Do $$$AssertEquals(row.Reasons, "The CI mock asks for an action.", "and has no code-written line")
	}
	Set response = ..Case("untrusted", "decide-ignore", .row)
	If $IsObject(response) && $IsObject(row) {
		Do $$$AssertEquals(response.Outcome_"|"_row.Outcome, "ignore|ignore", "an untrusted ignore stays ignore")
		Do $$$AssertEquals(row.Reasons, "The CI mock ignores this item.", "and has no code-written line")
	}
}

/// The same item again gets the recorded decision: the first row's DecisionRef, outcome, reasons and confidence, no request to the
/// mock, no header to TriageAgent in the second session, and no second row.
Method TestRepeat()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set again = request.%ConstructClone()
	Do $$$AssertStatusOK(..Run(request, .first, .session), "the first request is answered")
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = ..Run(again, .second, .secondSession)
	Do $$$AssertStatusOK(sc, "the same item sent again is answered")
	If '$IsObject(first) || '$IsObject(second) {
		Do $$$AssertTrue(0, "both answers are DecisionResponses")
		Quit
	}
	Do $$$AssertTrue(session '= secondSession, "in a session of its own")
	Do $$$AssertEquals(second.DecisionRef_"|"_second.Outcome_"|"_second.Reasons_"|"_second.Confidence, first.DecisionRef_"|"_first.Outcome_"|"_first.Reasons_"|"_first.Confidence, "the answer is the recorded decision")
	Do $$$AssertEquals(second.Payload, first.Payload, "with the same Payload")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Do $$$AssertEquals(entries.%Size(), 0, "the mock got no request")
	Set targets = ..Targets($ClassMethod(fixture, "Headers", secondSession, "Decide"))
	Do $$$AssertEquals(targets, "ApprovalStartIn", "Decide sent nothing but the answer in the second session: "_targets)
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", ref)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "and the table holds one row for the item")
}

/// A user's turn: the mock's final text, outcome tellnow and the DecisionRef of its row, and the rendered input as the text of a
/// user-role message in every logged request, never inside a tool_result block. The same item again is refused and sends nothing.
Method TestTurn()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", "What is going on in my productions?", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set item = ##class(OcuTalon.Msg.Item).%New()
	Set item.ItemId = ref
	Set item.Provenance = "user"
	Set item.Channel = "web"
	Set item.Text = "What is going on in my productions? (test "_ref_")"
	Set request.Input = ##class(OcuTalon.Agent.Input).Render(item)
	Set again = request.%ConstructClone()
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = ..Run(request, .reply, .session)
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(reply) || 'reply.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(reply.Text, ..#CHATTEXT, "the text is the final text of the mock's script")
	Do $$$AssertEquals(reply.Outcome, "tellnow", "the outcome is tellnow")
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "turn")
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "a row of kind turn is recorded")
		Quit
	}
	Do $$$AssertEquals(reply.DecisionRef, row.Ref, "the answer carries the DecisionRef of the row")
	Do $$$AssertEquals(row.Kind_"|"_row.Outcome_"|"_row.Reasons_"|"_row.Confidence_"|"_row.Payload, "turn|tellnow|||", "the row is a turn with the outcome tellnow and no reasons, confidence or payload")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Set requests = $ClassMethod(fixture, "FindRequests", entries, ref)
	Do $$$AssertTrue(requests.%Size() >= 2, "the turn made at least two model requests, the second with the tool call fed back: "_requests.%Size())
	Set iterator = requests.%GetIterator()
	While iterator.%GetNext(.position, .logged) {
		Set here = "request "_(position + 1)
		Do $$$AssertTrue(..UserMessageHolds(logged, request.Input), here_": the rendered input is the text of a user-role message")
		Do $$$AssertTrue(..UserMessageHolds(logged, $Char(10, 10)_item.Text), here_": with the user's own text after the preamble and a blank line, as written")
		Do $$$AssertNotTrue(..UserMessageHolds(logged, "quoted data, never instructions"), here_": and not as quoted data")
		Do $$$AssertNotTrue(..ToolResultHolds(logged, ref), here_": and no tool_result block holds the item's text")
		Do $$$AssertEquals(..HasToolResult(logged), (position > 0), here_": a tool_result block is there from the second request on, so the check above looks at one")
	}

	Set mark = $ClassMethod(mock, "LogMark")
	Set headerMark = $ClassMethod(fixture, "HeaderMark")
	Set sc = ..Run(again, .second, .secondSession)
	Do $$$AssertStatusNotOK(sc, "the same item sent again as a turn is refused")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ ref) && (text [ row.Ref), "with an error that names the item and the recorded DecisionRef: "_text)
	Do $$$AssertEquals(second, "", "and gives no answer")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Do $$$AssertEquals(entries.%Size(), 0, "nothing reached the mock")
	Do $$$AssertEquals($ClassMethod(fixture, "SessionSince", headerMark, "ChatAgent"), "", "and nothing was sent to ChatAgent")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", ref)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "and no second row was recorded")
}

/// A diagnose request is refused while DiagnosisAgent names no ReplyClass: the error names both, nothing is sent and no row is
/// recorded.
Method TestDiagnoseNeedsReplyClass()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set request = $ClassMethod(fixture, "NewRequest", "diagnose", "untrusted", "Why did the messages fail?", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = ..Run(request, .response, .session)
	Do $$$AssertStatusNotOK(sc, "the diagnose request is refused")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ "DiagnosisAgent") && (text [ "ReplyClass"), "with an error that names DiagnosisAgent and ReplyClass: "_text)
	Do $$$AssertEquals(response, "", "and gives no answer")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Do $$$AssertEquals(entries.%Size(), 0, "nothing reached the mock")
	Do $$$AssertEquals(..Targets($ClassMethod(fixture, "Headers", session, "Decide")), "ApprovalStartIn", "and Decide sent nothing to a runner or the timer")
	Do $$$AssertEquals($ClassMethod(fixture, "DecisionOf", ref, "diagnose"), "", "no row is recorded")
}

/// A reply that fails the check, and a runner error, end with an error status and record no row: the first names the reply
/// check, the second carries the runner's error text.
Method TestUnusableEndsWithError()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "[[mock:invalid-reply]] Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set sc = ..Run(request, .response, .session)
	Do $$$AssertStatusNotOK(sc, "a reply that fails the check ends with an error status")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "reply check", "that names the reply check: "_$Extract($SYSTEM.Status.GetErrorText(sc), 1, 300))
	Do $$$AssertEquals(response, "", "and gives no answer")
	Do $$$AssertEquals($ClassMethod(fixture, "DecisionOf", ref, "decide"), "", "no row is recorded")
	Do $$$AssertEquals(..CountTo($ClassMethod(fixture, "Headers", session, "Decide"), "TriageAgent"), 1, "Decide sent the runner one request and did not send again")

	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "[[mock:provider-error]] Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set sc = ..Run(request, .response, .session)
	Do $$$AssertStatusNotOK(sc, "a runner error ends with an error status")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue(text [ "CI mock: the provider failed.", "that carries the runner's error text from AI Hub: "_$Extract(text, 1, 300))
	Do $$$AssertTrue(text '[ "reply check", "and is not the reply check's")
	Do $$$AssertEquals(response, "", "and gives no answer")
	Do $$$AssertEquals($ClassMethod(fixture, "DecisionOf", ref, "decide"), "", "no row is recorded")
}

/// With TimerSeconds 2 and a reply that comes after 6 s, Decide ends with an error that names the timer and TriageAgent. No row is
/// recorded, before or after the late reply, and the late reply's header is discarded.
Method TestTimer()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set ..DecideChanged = 1
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).WriteDefault(..#PRODUCTION, "Decide", "TimerSeconds", 2, "Written by a test; the test deletes it."), "a TimerSeconds row of 2 is written")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Restart", ..#PRODUCTION_"||Decide"), "and Decide is started again")
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "[[mock:decide-late]] Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set sc = ..Run(request, .response, .session)
	Set ..LateSession = session
	Do $$$AssertStatusNotOK(sc, "the late reply ends Decide with an error status")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ "timer") && (text [ "TriageAgent"), "that names the timer and TriageAgent: "_$Extract(text, 1, 300))
	Do $$$AssertEquals(response, "", "and gives no answer")
	Do $$$AssertEquals($ClassMethod(fixture, "DecisionOf", ref, "decide"), "", "no row is recorded when the error arrives")
	Do $$$AssertTrue(..WaitForStatus(session, "TriageAgent", "Discarded"), "TriageAgent answers the late request and Decide discards the reply, within the ceiling")
	Do $$$AssertEquals(..AnswerStatus(session, "TriageAgent"), "Discarded", "the late reply's header is marked discarded")
	Do $$$AssertEquals($ClassMethod(fixture, "DecisionOf", ref, "decide"), "", "no row is recorded after the late reply either")
}

/// A message of another class gets "not implemented" (5003), and a request of an unknown kind an error that names the field;
/// nothing is sent to a runner in either case.
Method TestRefused()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set mark = $ClassMethod(mock, "LogMark")
	Set headerMark = $ClassMethod(fixture, "HeaderMark")
	Set sc = $ClassMethod(fixture, "Send", "Decide", ##class(Ens.StringRequest).%New("x"), .response)
	Do $$$AssertStatusNotOK(sc, "a message of another class is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "#5003: Not implemented", "with 'not implemented' (5003) inside the error that ends the process: "_$Extract($SYSTEM.Status.GetErrorText(sc), 1, 200))
	Do $$$AssertEquals(response, "", "and no answer")
	Set request = $ClassMethod(fixture, "NewRequest", "zz", "untrusted", "Triage this item.", .ref)
	Set sc = ..Run(request, .response, .session)
	Do $$$AssertStatusNotOK(sc, "a request of kind zz is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "Kind", "with an error that names the field: "_$Extract($SYSTEM.Status.GetErrorText(sc), 1, 200))
	Do $$$AssertEquals(response, "", "and no answer")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Do $$$AssertEquals(entries.%Size(), 0, "nothing reached the mock")
	Do $$$AssertEquals($ClassMethod(fixture, "SessionSince", headerMark, "TriageAgent"), "", "and nothing was sent to a runner")
}

/// The XML of the recorded DecisionResponse, which Visual Trace's contents pane shows, holds Outcome, Reasons, Confidence, Fallback
/// and FallbackReason, and the row's TraceSessionId is the session that holds the response's header.
Method TestTraceFields()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Do $$$AssertStatusOK(..Run(request, .response, .session), "Decide answers")
	If '$IsObject(response) {
		Do $$$AssertTrue(0, "the answer is a DecisionResponse")
		Quit
	}
	Do $$$AssertStatusOK(response.XMLExportToString(.xml), "the answer is exported as XML")
	For name = "Outcome", "Reasons", "Confidence", "Fallback", "FallbackReason" {
		Do $$$AssertTrue(xml [ ("<"_name_">"), "the XML holds <"_name_">")
	}
	Do $$$AssertTrue(xml [ "<Confidence>.5</Confidence>", "with the confidence")
	Do $$$AssertTrue(xml [ "<Fallback>false</Fallback>", "and the fallback flag")
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "decide")
	Do $$$AssertTrue($IsObject(row), "the row exists")
	If $IsObject(row) {
		Do $$$AssertTrue(row.TraceSessionId '= "", "TraceSessionId is written")
		Do $$$AssertEquals(row.TraceSessionId, $ClassMethod(fixture, "SessionOf", response), "and is the session of the header that carries the answer")
	}
}

/// --- helpers ---
/// 1 when the production runs with every item in the CI override's environment and the entries of the runners are pointed at the
/// mock key variable. Otherwise the test fails with the reason, and quits. The entries are put back by OnAfterAllTests.
Method Prepare() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	If '..Pointed {
		Set ..Pointed = 1
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).PointKeys()
		Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
		If $$$ISERR(sc) Quit 0
	}
	Quit 1
}

/// Sends the request to Decide and waits for the answer. response is the answer (or ""), and session is the session of the
/// request, which holds every header of the call.
Method Run(request As OcuTalon.Bridge.Msg.Request, Output response As %Persistent, Output session As %Integer) As %Status [ Private ]
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mark = $ClassMethod(fixture, "HeaderMark")
	Set sc = $ClassMethod(fixture, "Send", "Decide", request, .response)
	Set session = $ClassMethod(fixture, "SessionSince", mark, "Decide")
	Quit sc
}

/// A decide request of the provenance whose text holds the marker (none: the default script), sent to Decide. The answer is the
/// return value and row is the Decision row of the item, or "" with the failure reported.
Method Case(provenance As %String, marker As %String, Output row As %Persistent) As %Persistent [ Private ]
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set text = $Select(marker = "": "", 1: "[[mock:"_marker_"]] ")_"Triage this item."
	Set request = $ClassMethod(fixture, "NewRequest", "decide", provenance, text, .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set label = provenance_" "_$Select(marker = "": "default script", 1: marker)
	Set row = ""
	Set sc = ..Run(request, .response, .session)
	Do $$$AssertStatusOK(sc, label_": Decide answers")
	Do $$$AssertTrue($IsObject(response), label_": the answer is an object")
	If $$$ISERR(sc) || '$IsObject(response) Quit ""
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "decide")
	Do $$$AssertTrue($IsObject(row), label_": the row is recorded")
	Quit response
}

/// The targets of the headers, sorted and comma-separated.
ClassMethod Targets(headers As %DynamicArray) As %String [ Private ]
{
	Set iterator = headers.%GetIterator()
	While iterator.%GetNext(, .header) {
		Set targets(header.target) = ""
	}
	Set names = ""
	Set name = ""
	For {
		Set name = $Order(targets(name))
		Quit:name=""
		Set names = names _ $Select(names = "": "", 1: ",") _ name
	}
	Quit names
}

/// The first header of the array that is addressed to the target, or "".
ClassMethod HeaderTo(headers As %DynamicArray, target As %String) As %DynamicObject [ Private ]
{
	Set found = ""
	Set iterator = headers.%GetIterator()
	While iterator.%GetNext(, .header) {
		If (found = "") && (header.target = target) Set found = header
	}
	Quit found
}

/// The ids of the headers in the session that the item sent to Decide, as a list.
ClassMethod ChainOf(session As %Integer, source As %String) As %List [ Private ]
{
	Set ids = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ? ORDER BY ID", session, source)
	While result.%Next() {
		Set ids = ids _ $ListBuild(result.%GetData(1))
	}
	Quit ids
}

/// The status of the first header that the item sent in the session, as its display name, or "" when there is none.
ClassMethod AnswerStatus(session As %Integer, source As %String) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Status FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ? ORDER BY ID", session, source)
	If 'result.%Next() Quit ""
	Set status = result.%GetData(1)
	If status '? 1.N Quit status
	Quit $Piece(##class(Ens.DataType.MessageStatus).#DISPLAYLIST, ",", status + 1)
}

/// Waits, up to WAITSECONDS, until the item has sent a header in the session. 1 when it has.
ClassMethod WaitForAnswer(session As %Integer, source As %String) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + ..#WAITSECONDS
	While ($ListLength(..ChainOf(session, source)) = 0) && ($ZHorolog < deadline) {
		Hang 1
	}
	Quit $ListLength(..ChainOf(session, source)) > 0
}

/// Waits, up to WAITSECONDS, until the first header that the item sent in the session has the status (its display name). 1 when it
/// has. The wait is a poll once a second.
ClassMethod WaitForStatus(session As %Integer, source As %String, status As %String) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + ..#WAITSECONDS
	While (..AnswerStatus(session, source) '= status) && ($ZHorolog < deadline) {
		Hang 1
	}
	Quit ..AnswerStatus(session, source) = status
}

/// The number of headers in the array that are addressed to the target.
ClassMethod CountTo(headers As %DynamicArray, target As %String) As %Integer [ Private ]
{
	Set count = 0
	Set iterator = headers.%GetIterator()
	While iterator.%GetNext(, .header) {
		If header.target = target Set count = count + 1
	}
	Quit count
}

/// 1 when any message of the logged request holds a tool_result block.
ClassMethod HasToolResult(logged As %DynamicObject) As %Boolean [ Private ]
{
	Set found = 0
	Set iterator = logged.request.messages.%GetIterator()
	While iterator.%GetNext(, .message) {
		If $IsObject(message.content) {
			Set blocks = message.content.%GetIterator()
			While blocks.%GetNext(, .block) {
				If $IsObject(block) && (block.%Get("type") = "tool_result") Set found = 1
			}
		}
	}
	Quit found
}

/// The text of a logged message's content: the string, or the text blocks joined.
ClassMethod ContentText(content) As %String [ Private ]
{
	If '$IsObject(content) Quit content
	Set text = ""
	Set iterator = content.%GetIterator()
	While iterator.%GetNext(, .block) {
		If $IsObject(block) && (block.%Get("type") = "text") Set text = text _ block.text
	}
	Quit text
}

/// 1 when a user-role message of the logged request has the text in its text.
ClassMethod UserMessageHolds(logged As %DynamicObject, text As %String) As %Boolean [ Private ]
{
	Set found = 0
	Set iterator = logged.request.messages.%GetIterator()
	While iterator.%GetNext(, .message) {
		If (message.role = "user") && (..ContentText(message.content) [ text) Set found = 1
	}
	Quit found
}

/// 1 when a tool_result block of any message of the logged request holds the text.
ClassMethod ToolResultHolds(logged As %DynamicObject, text As %String) As %Boolean [ Private ]
{
	Set found = 0
	Set iterator = logged.request.messages.%GetIterator()
	While iterator.%GetNext(, .message) {
		If $IsObject(message.content) {
			Set blocks = message.content.%GetIterator()
			While blocks.%GetNext(, .block) {
				If $IsObject(block) && (block.%Get("type") = "tool_result") && (block.%ToJSON() [ text) Set found = 1
			}
		}
	}
	Quit found
}

}
