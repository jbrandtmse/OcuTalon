/// Tests of the running Decide item (Stories 1.3 and 1.4; AD-6, AD-7, AD-9, AD-20, AD-26, AD-30). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY
/// (Rule 21): it needs OcuTalon.Production running after the Production step, the CI override's environment (the mock's base URL and
/// OCUTALON_MOCK_KEY_HEADER=1) and the mock's request log, and fails with the reason where it does not have them. Each request goes
/// through ApprovalStartIn to Decide, as a caller of Decide will send it (Test.Agent.RunnerFixture.Send). CI starts with no model
/// key on purpose, so the first test points the Config Store entry of each runner at the non-secret CI variable
/// OCUTALON_MOCK_KEY_HEADER, and OnAfterAllTests puts the entries back (Test.Agent.RunnerFixture.PointKeys and RestoreKeys).
/// The rows that Test.Bridge.Decide pins in process (the filter, the sink, the concurrent save, the bad settings) are not repeated.
///   - TestDecision: an untrusted decide request gets a DecisionResponse with a new DecisionRef, the digest of the default script
///     and its reason, and the Payload of the reply; the row holds the same, with the session of the response as TraceSessionId;
///     the runner's request carries the DecisionRef; the timer's Timeout is 60; Decide sends only the runner request, the timer
///     request and (Story 1.5) the one agent step of the runner's reply to AgentSteps, and answers only its caller;
///   - TestLowConfidence: act with a confidence of 0.12 is recorded and answered as it is;
///   - TestUserRule: a user's digest and ignore become tellnow with the code-written line first, a user's act stays, and an
///     untrusted ignore stays;
///   - TestRepeat: the same ItemId again gets the recorded decision, with no request to the mock or the runner and no second row;
///   - TestTurn: a user's turn gets the mock's final text with the outcome tellnow and its DecisionRef, one row of kind turn, the
///     rendered input as the text of a user-role message in every logged request and in no tool_result block; the same item again
///     is refused with an error that names the item and the DecisionRef, and nothing is sent;
///   - TestDiagnoseNeedsReplyClass: a diagnose request is refused, naming DiagnosisAgent and ReplyClass, and nothing is sent;
///   - TestReplyFallbacks (Story 1.6, since TestUnusableEndsWithError): the five markers refusal, max-tokens, empty, provider-error and
///     invalid-reply are answered with fallbacks;
///   - TestTimer (Story 1.7): with a TimerSeconds row of 12, a reply that comes after 18 s is answered with a timeout fallback 11 to 17 s after
///     the send; the row has the ref of the runner's request and empty token totals, the late reply's header is discarded, and TriageAgent still
///     writes its Usage row;
///   - TestRefused: a message of another class gets "not implemented" (5003, inside the error that ends the process) and a
///     request of an unknown kind an error that names the field, and nothing is sent;
///   - TestTraceFields: the XML of the recorded DecisionResponse holds Outcome, Reasons, Confidence, Fallback and FallbackReason,
///     and the row's TraceSessionId is the session of the response's header.
/// Added by Story 1.4 (the usage and the cost of each call; the scenarios usage-decide and usage-turn give the mock's replies a fixed
/// usage):
///   - TestUsageDecide: an untrusted decide request through Decide leaves one Usage row for its DecisionRef, written by TriageAgent with
///     the counts and the cost of the one request (input 3,800 with 2,000 read from the cache and 600 written to it); the runner's Reply
///     carries them with its step count and its wall time; the Decision row and the DecisionResponse carry the same, with a duration
///     at least the runner's; and the XML of the DecisionResponse, which Visual Trace shows, holds the eight names with the values;
///   - TestUsageTurn: a user's turn of two requests and one tool call has one row, the Reply and the answer with the sums, the largest
///     request of the last one and a step count of two requests plus the tool call;
///   - TestCostOfFailedTurn: a turn whose Chat fails after it spent tokens (the tool loop stalls) has one Usage row, and since Story 1.6 a
///     fallback Decision row, with the model steps of the call as AgentSteps;
///   - TestTimer and TestRepeat also pin that the reply that comes after the timer is counted (one row for the DecisionRef of the
///     runner's request), and that a repeated item is answered with the recorded totals and writes no new row.
/// Added by Story 1.5 (the agent steps; the largest request of DW-77):
///   - TestDecision also pins the one AgentStep of the decision, in its session, sent from Decide to AgentSteps;
///   - TestRepeat and TestTimer also pin that a repeated request and a late reply send no AgentStep;
///   - TestCostOfFailedTurn now pins a largest request above 0 for the call that threw, the largest estimate of its requests (and, since
///     Story 1.6, that the failed call sent its model steps as AgentSteps).
/// Added by Story 1.6 (AD-6, AD-8, AD-20, AD-26, AD-28, AD-30, AD-31; U-16):
///   - TestReplyFallbacks: an untrusted decide with each of the markers refusal, max-tokens, empty, provider-error and invalid-reply is
///     answered with a tellnow fallback of the reason refusal, cut_off, empty, error and invalid, with no reasons, confidence or payload;
///     the row holds the same, with the DecisionRef of the runner's request and the totals of its Usage row; the XML shows Fallback and
///     FallbackReason; Decide sends only to TriageAgent, Ens.Alarm, AgentSteps (when the reply had steps) and its caller; and the
///     TriageAgent header of the provider error is Completed and its Reply holds the provider's text as FailureText;
///   - TestTurnFallbackIsReplyOnly: a user's refused turn is a fallback Reply with no text, host data, steps, failure text or finish
///     reason, and the refused text is in no field of it;
///   - TestRunnerErrorIsFallback: a runner that ends with an error status (ChatAgent with a model that no ModelFamily row matches) gives
///     an error fallback Reply at once, through OnError, with nothing sent to the mock;
///   - TestPrechecks: a token budget of 1, and a daily cap reached, are fallbacks (budget, daily_cap) that are never sent, with one
///     budget.capped event, and each row and answer carries the time Decide took (DurationMs);
///   - TestBadBudgetSettings: budget settings that their datatypes refuse (DecisionTokenBudget, DailyCostCapUSD and GatewaySpendUSD,
///     Decide started again) count as off: a decide is sent and answered as usual, and Precheck logs one warning for each (AC8);
///   - TestDailyCapBothPaths: the gateway's 403 and the precheck both give daily_cap, the day is marked once, and the host sink got one
///     budget.capped and three decision.recorded;
///   - OnAfterOneTest puts back every System Default Settings row, item setting and model family that a test changed, kills today's
///     day mark and ^OcuTalonTest("ProbeSink"), and starts Decide and ChatAgent again where the test changed them.
/// Added by the QA stage of Story 1.6 (AD-8, AD-20, AD-26, AD-30):
///   - every live fallback test asserts all the guarantees of a fallback in one call (RunnerFixture.FallbackProblems: the class of the
///     answer, tellnow, Fallback, the reason, no reasons, confidence or payload, and for a Reply no text, host data, steps, failure text,
///     finish reason or flag; the XML with all three of Outcome, Fallback and FallbackReason; and the row), where it asserted only some;
///   - TestPrechecks and TestDailyCapBothPaths read the mock's log for "nothing was sent" only after the runner has handled everything
///     sent to it (AssertNotSent, RunnerFixture.Drain), because a request that Decide sent by mistake reaches the mock after Decide has
///     answered; TestPrechecks has a control (the same decide with the budget off reaches the mock once);
///   - TestPrechecks pins the daily_cap precheck path alone (decision.recorded, then one budget.capped, with the row and the mark in
///     place), and TestDailyCapBothPaths reads the sink's calls after each path, so that the one budget.capped is not the work of a
///     single path;
///   - TestReplyFallbacks reads the AgentStep messages of each marker's call instead of inferring them from the targets;
///   - TestCostOfFailedTurn compares each AgentStep of the failed turn with the step that the runner buffered (both read), so that a step
///     that Decide drops or sends twice is seen.
/// Added by Story 1.7 (AD-5, AD-6, AD-8, AD-9, AD-20, DW-56; FR-4, NFR-23):
///   - TestApplyTimer: Timeouts.Apply(20) writes Decide's TimerSeconds row, merges the block into every runner's entry (the api_key, base_url and
///     custom_headers stay), starts Decide and the runners in new jobs, and the next decide's timer is 20 s; a held request then ends as a
///     timeout fallback before the timer, because AI Hub's attempts of 5 s end first, and the runner's Reply holds "operation timed out";
///   - TestApplyActiveProduction (QA): Timeouts.Apply with no production names the active production: the same row, entries and new jobs;
///   - TestRateLimitedResent: a rate limit is sent again with back-off until an attempt succeeds (overloaded armed 2, rate-limited armed 3), with
///     the one DecisionRef, the steps of the attempts added, a duration that runs across the back-offs, and no warning;
///   - TestRateLimitedUntilTimer: a rate limit that does not end is sent again at least 4 times, 1 s, 2 s and 4 s apart, and ends as rate_limited
///     12 to 16 s after the send, with the timer at 15 s and a second for the hops outside Decide;
///   - TestRateLimitedThenHeld: the timer that Decide sets at a re-send ends the decision when the re-sent request is held: a rate_limited fallback
///     10 to 16 s after the send with a TimerSeconds row of 12, two requests with one DecisionRef, the late reply discarded and its Usage row written;
///   - TestLongRetryAfterCapped: a Retry-After of 30 waits only the back-off cap of the entry's retry block, so the reply comes in 1.5 to 10 s.
///   OnAfterOneTest puts the timer back (RunnerFixture.RestoreTimer) and clears the countdowns that the test armed.
/// TestRunSessionIsItsOwn pins the session that RunnerFixture.Run returns: with another message to Decide between a mark and the send,
/// it is the session of the header that carries the request, not that of the first header to Decide after the mark.
/// OnAfterOneTest deletes the rows its test made (Decision, Usage and, since the QA stage of Story 1.5, the AgentStep messages, once
/// AgentSteps has handled them), puts back the timer a test changed through Timeouts.Apply (and the TimerSeconds row that a test wrote), starts
/// Decide again if the test changed it, and waits until TriageAgent has answered the late request. Every wait is a poll with a generous ceiling.
/// Added by Story 1.8 (AD-6): a user's turn is linked to a conversation, so each such turn saves an AI session and a link; each of these turns
/// has an owner of its own (RunnerFixture.NewRequest), and OnAfterOneTest deletes the sessions saved since the test began and the links that name
/// them (RunnerFixture.DropSince). WaitForAnswer moved to RunnerFixture, which Test.Agent.Conversation shares. The conversations themselves are
/// pinned in Test.Agent.Conversation and Test.Bridge.Conversation.
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

/// The final text of usage-turn.json.
Parameter USAGETURNTEXT = "The CI mock reports the usage of two requests.";

/// The steps of the turn of usage-turn.json: its two model requests plus the call of list_productions, which ChatAgent does not
/// have (measured in Story 1.4: total_tool_calls counts it, and the call gets the result "Tool not found").
Parameter USAGETURNSTEPS = 3;

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

/// 1 when the test wrote the TimerSeconds row and started Decide again.
Property DecideChanged As %Boolean [ InitialExpression = 0 ];

/// The session of a request whose late reply the test waits for, or "".
Property LateSession As %Integer;

/// What RunnerFixture.UseTimer saved when the test changed the timer through Timeouts.Apply, to be put back (RestoreTimer), or "".
Property TimerSaved As %List;

/// The countdowns of the mock that the test armed, as a list of markers, to be cleared.
Property Armed As %List;

/// The System Default Settings rows before the test touched them (Test.Agent.RunnerFixture.SnapshotDefault), to be put back.
Property SavedRows As %List;

/// What the stored configuration of the production had of the item settings that the test changed, as a dynamic array of
/// {"item","saved"} (Test.Agent.RunnerFixture.UseItemSetting), to be put back.
Property Swaps As %DynamicArray;

/// 1 when the test changed ChatAgent (its Model row), which OnAfterOneTest starts again.
Property ChatChanged As %Boolean [ InitialExpression = 0 ];

/// The default model family before the test took it out, $ListBuild(Family, ModelPrefix, CapKey, EffortKey), or "".
Property FamilySaved As %List;

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark): a user's turn is linked to a conversation, so it saves an
/// AI session and a link (Story 1.8), which OnAfterOneTest deletes (RunnerFixture.DropSince).
Property SessionMark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..Armed, position, marker) {
		Do ##class(OcuTalon.Test.Contract.Mock).Arm(marker, "")
	}
	Set ..Armed = ""
	If ..LateSession '= "" {
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).WaitForAnswer(..LateSession, "TriageAgent")
		Set ..LateSession = ""
	}
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).DeleteSteps(itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Set running = ##class(OcuTalon.Test.Agent.RunnerFixture).Running()
	If $IsObject(..Swaps) {
		For i = ..Swaps.%Size() - 1:-1:0 {
			Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreItemSetting(..Swaps.%Get(i).item, ..Swaps.%Get(i).saved)
		}
		Set ..Swaps = ""
	}
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..SavedRows)
	Set ..SavedRows = ""
	If ..FamilySaved '= "" {
		Set family = ##class(OcuTalon.Bridge.Data.ModelFamily).%New()
		Set family.Family = $List(..FamilySaved, 1), family.ModelPrefix = $List(..FamilySaved, 2), family.CapKey = $List(..FamilySaved, 3), family.EffortKey = $List(..FamilySaved, 4)
		Do family.%Save()
		Set ..FamilySaved = ""
	}
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	Kill ^OcuTalonTest("ProbeSink")
	If ..TimerSaved '= "" {
		Set restored = ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreTimer(..TimerSaved)
		Set ..TimerSaved = ""
		If $$$ISERR(restored) Do $$$AssertStatusOK(restored, "the timer is put back for the next test")
	}
	If ..DecideChanged && running {
		Set ..DecideChanged = 0
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).Restart(..#PRODUCTION_"||Decide")
	}
	If ..ChatChanged && running {
		Set ..ChatChanged = 0
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).Restart(..#PRODUCTION_"||ChatAgent")
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
	Do $$$AssertEquals(targets, "AgentSteps,ApprovalStartIn,Ens.Alarm,TriageAgent", "Decide sends only to TriageAgent, Ens.Alarm, AgentSteps and its caller: "_targets)
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
	Set steps = $ClassMethod(fixture, "StepsOf", response.DecisionRef)
	Do $$$AssertEquals(steps.%Size(), 1, "one AgentStep exists for the DecisionRef")
	Set stepHeader = ..HeaderTo(headers, "AgentSteps")
	If $IsObject(stepHeader) && (steps.%Size() = 1) {
		Do $$$AssertEquals(stepHeader.bodyClass_"|"_stepHeader.bodyId, "OcuTalon.Bridge.Msg.AgentStep|"_steps.%Get(0).id, "Decide sent it to AgentSteps, in this session")
		Do $$$AssertEquals(steps.%Get(0).position_"|"_steps.%Get(0).kind, "1|model", "it is the model step at Position 1")
	} Else {
		Do $$$AssertTrue(0, "a header to AgentSteps carries the step")
	}
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
	Do $$$AssertTrue(first.InputTokens > 0, "the first answer counts the tokens of the call: "_first.InputTokens)
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Totals(second), ##class(OcuTalon.Test.Agent.RunnerFixture).Totals(first), "and the answer carries the totals of the recorded decision, the first answer's")
	Set recorded = $ClassMethod(fixture, "DecisionOf", ref, "decide")
	Do $$$AssertTrue($IsObject(recorded) && (recorded.InputTokens > 0), "the recorded row holds them")
	If $IsObject(recorded) Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Totals(second), ##class(OcuTalon.Test.Agent.RunnerFixture).Totals(recorded), "and the answer carries exactly the totals of the recorded row")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).UsageIds("ItemId", ref).%Size(), 1, "the call left one Usage row")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Do $$$AssertEquals(entries.%Size(), 0, "the mock got no request")
	Set targets = ..Targets($ClassMethod(fixture, "Headers", secondSession, "Decide"))
	Do $$$AssertEquals(targets, "ApprovalStartIn", "Decide sent nothing but the answer in the second session: "_targets)
	Set steps = $ClassMethod(fixture, "StepsOf", first.DecisionRef)
	Do $$$AssertEquals(steps.%Size(), 1, "and no step: the recorded decision still has the one step of the first request")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", ref)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "and the table holds one row for the item")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).UsageIds("ItemId", ref).%Size(), 1, "and still one Usage row: the repeat wrote none")
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

/// An untrusted decide request for each of the five markers (refusal, max-tokens, empty, provider-error, invalid-reply) is answered with a
/// DecisionResponse that is a fallback (tellnow, Fallback true and, in turn, refusal, cut_off, empty, error, invalid), with no reasons,
/// confidence or payload; the row holds the same, with the DecisionRef of the runner's request and the totals of its Usage row; the XML
/// of the answer shows Fallback and FallbackReason; Decide sends only to TriageAgent, Ens.Alarm, AgentSteps (when the reply had steps)
/// and its caller; and for provider-error the TriageAgent header is Completed and its Reply holds the provider's text as FailureText.
Method TestReplyFallbacks()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set cases = $ListBuild($ListBuild("refusal", "refusal", 1, "The CI mock refuses this request."), $ListBuild("max-tokens", "cut_off", 1, "This reply stops at the output cap"), $ListBuild("empty", "empty", 1, ""), $ListBuild("provider-error", "error", 0, ""), $ListBuild("invalid-reply", "invalid", 1, "maybe"))
	For i = 1:1:$ListLength(cases) {
		Set case = $List(cases, i)
		Set marker = $List(case, 1)
		Set reason = $List(case, 2)
		Set steps = $List(case, 3)
		Set refused = $List(case, 4)
		Set label = marker_": "
		Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "[[mock:"_marker_"]] Triage this item.", .ref)
		Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
		Set mark = $ClassMethod(mock, "LogMark")
		Set sc = ..Run(request, .response, .session)
		Do $$$AssertStatusOK(sc, label_"Decide answers the request")
		If '$IsObject(response) || 'response.%IsA("OcuTalon.Bridge.Msg.DecisionResponse") {
			Do $$$AssertTrue(0, label_"the answer is a DecisionResponse")
			Continue
		}
		Do $$$AssertEquals(response.Outcome_"|"_response.Fallback_"|"_response.FallbackReason, "tellnow|1|"_reason, label_"the answer is a tellnow fallback with the reason "_reason)
		Do $$$AssertEquals(response.Reasons_"|"_response.Confidence_"|"_response.Payload, "||", label_"with no reasons, confidence or payload")
		Set row = $ClassMethod(fixture, "DecisionOf", ref, "decide")
		If '$IsObject(row) {
			Do $$$AssertTrue(0, label_"a row is recorded")
			Continue
		}
		Do $$$AssertEquals(row.Outcome_"|"_row.Fallback_"|"_row.FallbackReason_"|"_row.Reasons_"|"_row.Confidence_"|"_row.Payload, "tellnow|1|"_reason_"|||", label_"the row holds the same, and no reasons, confidence or payload")
		Do $$$AssertEquals(row.Ref, response.DecisionRef, label_"the row has the DecisionRef of the answer")
		Do $$$AssertEquals(row.TraceSessionId, session, label_"in the session of the request")
		Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", response, row, "decide", reason), "", label_"every guarantee of a fallback holds in the answer, its XML and the row")

		Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
		Set expected = $Select(steps: "AgentSteps,", 1: "")_"ApprovalStartIn,Ens.Alarm,TriageAgent"
		Do $$$AssertEquals(..Targets(headers), expected, label_"Decide sends only to "_expected)
		Do $$$AssertEquals(..CountTo(headers, "TriageAgent"), 1, label_"and sends the runner one request, never a second")
		Set runner = ..HeaderTo(headers, "TriageAgent")
		Set sent = $Select($IsObject(runner): ##class(OcuTalon.Bridge.Msg.Request).%OpenId(runner.bodyId), 1: "")
		Do $$$AssertTrue($IsObject(sent), label_"the runner's request is read")
		If $IsObject(sent) {
			Do $$$AssertEquals(row.Ref, sent.DecisionRef, label_"the row's Ref is the DecisionRef of the runner's request")
			Set stored = $ClassMethod(fixture, "StepsOf", sent.DecisionRef)
			Do $$$AssertEquals(stored.%Size(), steps, label_"AgentSteps holds "_steps_" step(s) of the call, read from the AgentStep messages and not taken from the targets")
			Do $$$AssertEquals(..CountTo(headers, "AgentSteps"), stored.%Size(), label_"with one header to AgentSteps for each")
			Set ids = $ClassMethod(fixture, "UsageIds", "DecisionRef", sent.DecisionRef)
			Do $$$AssertEquals(ids.%Size(), steps, label_"the runner wrote "_steps_" Usage row")
			If ids.%Size() = 1 {
				Set usage = ##class(OcuTalon.Bridge.Data.Usage).%OpenId(ids.%Get(0))
				Do $$$AssertEquals(row.InputTokens_"|"_row.OutputTokens_"|"_row.CostUSD_"|"_row.Model, usage.InputTokens_"|"_usage.OutputTokens_"|"_usage.CostUSD_"|"_usage.Model, label_"the row has the totals of the Usage row")
				Do $$$AssertTrue(row.InputTokens > 0, label_"which hold tokens: "_row.InputTokens)
			} Else {
				Do $$$AssertEquals(row.InputTokens_row.OutputTokens_row.CostUSD_row.Model, "", label_"and with no Usage row the totals are empty")
			}
		}
		Do $$$AssertEquals($ClassMethod(fixture, "Totals", response), $ClassMethod(fixture, "Totals", row), label_"the answer carries the totals of the row")
		Do $$$AssertStatusOK(response.XMLExportToString(.xml), label_"the answer is exported as XML")
		Do $$$AssertTrue(xml [ "<Fallback>true</Fallback>", label_"the XML shows <Fallback>true</Fallback>")
		Do $$$AssertTrue(xml [ ("<FallbackReason>"_reason_"</FallbackReason>"), label_"and <FallbackReason>"_reason_"</FallbackReason>")
		If refused '= "" Do $$$AssertTrue(xml '[ refused, label_"and none of the model's text")
		Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), label_"the mock's log is read")
		Do $$$AssertTrue($ClassMethod(fixture, "FindRequests", entries, ref).%Size() >= 1, label_"the request reached the mock")
		If marker = "provider-error" {
			Set back = ..HeaderTo($ClassMethod(fixture, "Headers", session, "TriageAgent"), "Decide")
			Set reply = $Select($IsObject(back): ##class(OcuTalon.Bridge.Msg.Reply).%OpenId(back.bodyId), 1: "")
			Do $$$AssertTrue($IsObject(reply), label_"TriageAgent sent Decide a Reply")
			If $IsObject(reply) Do $$$AssertTrue(reply.FailureText [ "CI mock: the provider failed.", label_"whose FailureText holds the provider's text: "_$Extract(reply.FailureText, 1, 200))
			Do $$$AssertEquals(..AnswerStatus(session, "TriageAgent"), "Completed", label_"and whose header is Completed")
		}
	}
}

/// The timer fires (AD-6, AD-8; row "The timer fires (live)"). The TimerSeconds row of Decide is written directly, with Decide started again and
/// the runners' entries kept at the derivation of 60 (so a reply held for 18 s is not stopped by AI Hub: the timer is the only thing that ends the wait,
/// which under the derived values happens only when a timer is changed outside Timeouts.Apply). The runners' sessions compose timeout_ms 7000
/// from the row (Adapter.Agent.TimeoutMs), which does not stop a request in flight (S2); the test needs that. A decide with the scenario
/// decide-late, whose reply comes after 18 s, gets a timeout fallback DecisionResponse 11 to 17 s after it was sent, never an error. The row has the DecisionRef
/// of the runner's request, a duration of 11 to 17 s and empty token totals, because the late call had not finished when the timer fired. The late
/// reply is discarded (its header is Discarded and no AgentStep is sent), and TriageAgent still writes its Usage row for the ref, which
/// Usage.Totals counts.
Method TestTimer()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Do ..Put("Decide", "TimerSeconds", 12)
	Set ..DecideChanged = 1
	Do $$$AssertStatusOK($ClassMethod(fixture, "Restart", ..#PRODUCTION_"||Decide"), "Decide is started again with a TimerSeconds of 12")
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "[[mock:decide-late]] Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set started = $ZHorolog
	Set sc = ..Run(request, .response, .session)
	Set elapsed = $ZHorolog - started
	Set ..LateSession = session
	Do $$$AssertStatusOK(sc, "Decide answers: the timer is no error")
	If '$IsObject(response) || 'response.%IsA("OcuTalon.Bridge.Msg.DecisionResponse") {
		Do $$$AssertTrue(0, "the answer is a DecisionResponse")
		Quit
	}
	Do $$$AssertTrue((elapsed '< 11) && (elapsed < 17), "the answer comes 11 to 17 s after the send, with the timer at 12 s and the reply at 18 s: "_$Number(elapsed, 1)_" s")
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "decide")
	Do $$$AssertTrue($IsObject(row), "a row is recorded")
	If '$IsObject(row) Quit
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", response, row, "decide", "timeout"), "", "a timeout fallback with every guarantee, in the answer, its XML and the row")
	Set runner = ..HeaderTo($ClassMethod(fixture, "Headers", session, "Decide"), "TriageAgent")
	Set sent = $Select($IsObject(runner): ##class(OcuTalon.Bridge.Msg.Request).%OpenId(runner.bodyId), 1: "")
	Do $$$AssertTrue($IsObject(sent) && (sent.DecisionRef '= ""), "the runner's request carries a DecisionRef")
	If '$IsObject(sent) Quit
	Do $$$AssertEquals(row.Ref, sent.DecisionRef, "the row has the DecisionRef of the runner's request")
	Do $$$AssertTrue((row.DurationMs '< 11000) && (row.DurationMs < 17000), "its duration is that of the timer: "_row.DurationMs)
	Do $$$AssertEquals(response.DurationMs, row.DurationMs, "and the answer holds the same")
	Do $$$AssertEquals($ClassMethod(fixture, "Totals", row, 0), "||||||0", "its token totals, cost and model are empty and it has no steps: the late call had not finished")
	Do $$$AssertEquals(..CountTo($ClassMethod(fixture, "Headers", session, "Decide"), "TriageAgent"), 1, "Decide sent the runner one request")
	Do $$$AssertTrue(..WaitForStatus(session, "TriageAgent", "Discarded"), "TriageAgent answers the late request and Decide discards the reply, within the ceiling")
	Do $$$AssertEquals(..AnswerStatus(session, "TriageAgent"), "Discarded", "the late reply's header is marked discarded")
	Do $$$AssertEquals(..CountTo($ClassMethod(fixture, "Headers", session, "Decide"), "AgentSteps"), 0, "no step is sent for the late reply")
	Do $$$AssertEquals($ClassMethod(fixture, "StepsOf", sent.DecisionRef).%Size(), 0, "and no AgentStep exists for it")
	Set ids = $ClassMethod(fixture, "UsageIds", "DecisionRef", sent.DecisionRef)
	Do $$$AssertEquals(ids.%Size(), 1, "TriageAgent wrote one Usage row for the ref: the reply that came after the timer is counted")
	If ids.%Size() = 1 {
		Set usage = ##class(OcuTalon.Bridge.Data.Usage).%OpenId(ids.%Get(0))
		Do $$$AssertEquals(usage.Agent_"|"_usage.ItemId_"|"_usage.Kind, "TriageAgent|"_ref_"|decide", "written by TriageAgent for the item and kind of the request")
		Do $$$AssertTrue((usage.RequestCount = 1) && (usage.InputTokens > 0) && (usage.OutputTokens > 0), "with the request and the tokens of the late reply")
		Set totals = ##class(OcuTalon.Bridge.Data.Usage).Totals(sent.DecisionRef)
		Do $$$AssertEquals(totals.inputTokens, usage.InputTokens, "and Usage.Totals counts it")
	}
	Do $$$AssertEquals($ClassMethod(fixture, "DecisionOf", ref, "decide").Ref, sent.DecisionRef, "the decision is still the one row, answered at the timer")
}

/// Timeouts.Apply changes the timer of the running production (AD-5, AD-8, AD-19; the rows "Apply (live)" and "A held request (live)"). After Apply(20)
/// on OcuTalon.Production: the TimerSeconds row of Decide is 20; every runner's entry has a request timeout of 5 and the retry block with an
/// attempt timeout of 5, and its api_key, base_url and custom_headers as before; Decide and the three runners run in new jobs; and the next
/// decide's timer has a Timeout of 20. A decide whose reply is held (held-past-timer, 120 s) then ends as a timeout fallback DecisionResponse 4
/// to 20 s after the send, because AI Hub's attempts of 5 s each end first (Task 0 (c): two attempts and 0.5 s of back-off, about 10.5 s); the
/// runner's Reply to Decide holds "operation timed out", and Decide sent the runner one request. OnAfterOneTest puts the timer back.
Method TestApplyTimer()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set items = $ListBuild("Decide", "TriageAgent", "DiagnosisAgent", "ChatAgent")
	Set names = $ListBuild("OcuTalonTriage", "OcuTalonDiagnosis", "OcuTalonChat")
	Set position = 0
	While $ListNext(items, position, item) {
		Set jobs(item) = $ClassMethod(fixture, "Jobs", item)
		Do $$$AssertTrue(jobs(item) '= "", item_" has a job before")
	}
	Set position = 0
	While $ListNext(names, position, name) {
		Set was(name) = {}.%FromJSON(##class(OcuTalon.Test.Install.Provider).EntryJson(name))
	}
	Set sc = $ClassMethod(fixture, "UseTimer", 20, .saved)
	Set ..TimerSaved = saved
	Do $$$AssertStatusOK(sc, "Timeouts.Apply(20) changes the timer, and the items run again")
	Set id = ..#PRODUCTION_"||Decide||*||TimerSeconds"
	Do $$$AssertTrue(##class(Ens.Config.DefaultSettings).%ExistsId(id), "the TimerSeconds row of Decide exists")
	If ##class(Ens.Config.DefaultSettings).%ExistsId(id) Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue, 20, "and is 20")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("TimerSeconds", ..#PRODUCTION, "Decide"), 20, "which is the timer that Decide reads")
	Set position = 0
	While $ListNext(names, position, name) {
		Set now = {}.%FromJSON(##class(OcuTalon.Test.Install.Provider).EntryJson(name))
		Set label = name_": "
		Do $$$AssertEquals(now."http_config"."request_timeout_secs", 5, label_"the request timeout is 5")
		Set retry = now."http_config".%Get("retry")
		Do $$$AssertEquals($Select($IsObject(retry): retry.%ToJSON(), 1: "none"), "{""max_retries"":1,""attempt_timeout_secs"":5,""initial_backoff_ms"":500,""max_backoff_ms"":2000}", label_"and the whole retry block has an attempt timeout of 5")
		Do $$$AssertEquals(now."api_key"_"|"_now.%Get("base_url"), was(name)."api_key"_"|"_was(name).%Get("base_url"), label_"the api_key and the base_url are as before")
		Do $$$AssertEquals(now."http_config".%Get("custom_headers").%ToJSON(), was(name)."http_config".%Get("custom_headers").%ToJSON(), label_"and so are the custom_headers")
		Do $$$AssertEquals(now."model_provider", was(name)."model_provider", label_"and the provider")
	}
	Set position = 0
	While $ListNext(items, position, item) {
		Set after = $ClassMethod(fixture, "Jobs", item)
		Set shared = 0
		Set at = 0
		While $ListNext(after, at, job) {
			If $ListFind(jobs(item), job) Set shared = 1
		}
		Do $$$AssertTrue((after '= "") && 'shared, item_" runs in a new job after the restart")
	}

	// the next decide uses the new timer
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Do $$$AssertStatusOK(..Run(request, .response, .session), "a decide is answered")
	Set alarm = ..HeaderTo($ClassMethod(fixture, "Headers", session, "Decide"), "Ens.Alarm")
	Set timer = $Select($IsObject(alarm): ##class(Ens.AlarmRequest).%OpenId(alarm.bodyId), 1: "")
	Do $$$AssertEquals($Select($IsObject(timer): timer.Timeout, 1: ""), 20, "its timer has a Timeout of 20 seconds")

	// a held request ends before the timer
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "[[mock:held-past-timer]] Triage this item.", .held)
	Set ..ItemIds = ..ItemIds _ $ListBuild(held)
	Set started = $ZHorolog
	Set sc = ..Run(request, .response, .session)
	Set elapsed = $ZHorolog - started
	Do $$$AssertStatusOK(sc, "Decide answers the held request")
	Do $$$AssertTrue((elapsed '< 4) && (elapsed < 20), "4 to 20 s after the send, before the timer of 20 s: "_$Number(elapsed, 1)_" s")
	Set row = $ClassMethod(fixture, "DecisionOf", held, "decide")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", response, row, "decide", "timeout"), "", "a timeout fallback with every guarantee, in the answer, its XML and the row")
	Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
	Do $$$AssertEquals(..CountTo(headers, "TriageAgent"), 1, "Decide sent TriageAgent one request")
	Set back = ..HeaderTo($ClassMethod(fixture, "Headers", session, "TriageAgent"), "Decide")
	Set reply = $Select($IsObject(back): ##class(OcuTalon.Bridge.Msg.Reply).%OpenId(back.bodyId), 1: "")
	Do $$$AssertTrue($IsObject(reply), "TriageAgent sent Decide a Reply")
	If $IsObject(reply) Do $$$AssertTrue(reply.FailureText [ "operation timed out", "whose FailureText holds the provider's timeout: "_$Extract(reply.FailureText, 1, 200))
}

/// Timeouts.Apply with no production changes the timer of the active production (AD-5, AD-8; an empty production means the active one). After
/// Apply(25): the TimerSeconds row of OcuTalon.Production's Decide is 25, the entry of each runner has a request timeout of 7 and the retry block with
/// an attempt timeout of 7 ((25 - 10) \ 2), and Decide runs in a new job. OnAfterOneTest puts the timer back.
Method TestApplyActiveProduction()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set rows = ""
	Do $ClassMethod(fixture, "RememberDefault", .rows, "Decide", "TimerSeconds")
	Set previous = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("TimerSeconds", ..#PRODUCTION, "Decide")
	Set ..TimerSaved = $ListBuild(rows, previous)
	Do $$$AssertEquals(##class(Ens.Director).GetActiveProductionName(), ..#PRODUCTION, "control: the active production is "_..#PRODUCTION)
	Set decide = $ClassMethod(fixture, "Jobs", "Decide")
	Set sc = ##class(OcuTalon.Bridge.Timeouts).Apply(25)
	Do $$$AssertStatusOK(sc, "Timeouts.Apply(25) with no production changes the timer of the active production, and the items run again")
	Set id = ..#PRODUCTION_"||Decide||*||TimerSeconds"
	Do $$$AssertTrue(##class(Ens.Config.DefaultSettings).%ExistsId(id), "the TimerSeconds row of its Decide exists")
	If ##class(Ens.Config.DefaultSettings).%ExistsId(id) Do $$$AssertEquals(##class(Ens.Config.DefaultSettings).%OpenId(id).SettingValue, 25, "and is 25")
	Set names = $ListBuild("OcuTalonTriage", "OcuTalonDiagnosis", "OcuTalonChat")
	Set position = 0
	While $ListNext(names, position, name) {
		Set now = {}.%FromJSON(##class(OcuTalon.Test.Install.Provider).EntryJson(name))
		Set retry = now."http_config".%Get("retry")
		Do $$$AssertEquals(now."http_config"."request_timeout_secs"_"|"_$Select($IsObject(retry): retry.%ToJSON(), 1: "none"), "7|{""max_retries"":1,""attempt_timeout_secs"":7,""initial_backoff_ms"":500,""max_backoff_ms"":2000}", name_": the request timeout is 7 and the whole retry block has an attempt timeout of 7")
	}
	Set after = $ClassMethod(fixture, "Jobs", "Decide")
	Set shared = 0
	Set at = 0
	While $ListNext(after, at, job) {
		If $ListFind(decide, job) Set shared = 1
	}
	Do $$$AssertTrue((after '= "") && 'shared, "Decide runs in a new job after the restart")
}

/// A rate limit is sent again until an attempt succeeds (AD-8, FR-4, NFR-23; the row "A re-send succeeds (live)"). A user's turn with
/// overloaded:<key> armed 2 (529, 529, then 200) is answered with the text "Answered after the overload.", with no fallback and ToolsRun 0: ChatAgent got 3
/// requests, all with the one DecisionRef; the mock's log holds 529, 529, 200, the second request at least 1 s after the first and the third at
/// least 2 s after the second; the answer's AgentStepCount is the sum of the three runner replies'; the answer's DurationMs is the row's, which is
/// 3000 or more across the back-offs of 1 s and 2 s; and Decide logged no warning. Another turn with
/// rate-limited:<key> armed 3 (AI Hub sends each 429 again once) logs 429, 429, 429, 200, and Decide sent 2 requests.
Method TestRateLimitedResent()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	For case = $ListBuild("overloaded", 2, "Answered after the overload.", "529,529,200", 3), $ListBuild("rate-limited", 3, "Answered after the rate limit.", "429,429,429,200", 2) {
		Set name = $List(case, 1)
		Set label = name_": "
		Set marker = name_":"_##class(OcuTalon.Bridge.Ids).NewRef()
		Do ..Arm(marker, $List(case, 2))
		Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:"_marker_"]] Say hello.", .ref)
		Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
		Set mark = $ClassMethod(mock, "LogMark")
		Set logMark = $ClassMethod(fixture, "EventMark")
		Set sc = ..Run(request, .answer, .session)
		Do $$$AssertStatusOK(sc, label_"Decide answers the turn")
		If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
			Do $$$AssertTrue(0, label_"the answer is a Reply")
			Continue
		}
		Do $$$AssertEquals(answer.Text_"|"_answer.Fallback_"|"_answer.FallbackReason_"|"_answer.ToolsRun, $List(case, 3)_"|0||0", label_"the text of the successful attempt, no fallback, and ToolsRun 0: no tool ran (AC6)")
		Set row = $ClassMethod(fixture, "DecisionOf", ref, "turn")
		Do $$$AssertTrue($IsObject(row) && (row.Fallback = 0) && (row.FallbackReason = "") && (row.Ref = answer.DecisionRef), label_"the row is no fallback, and has the DecisionRef of the answer")
		If '$IsObject(row) Continue
		Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
		Set requests = 0
		Set refs = ""
		Set iterator = headers.%GetIterator()
		While iterator.%GetNext(, .header) {
			If header.target '= "ChatAgent" Continue
			Set requests = requests + 1
			Set sent = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(header.bodyId)
			Set refs = refs _ $ListBuild($Select($IsObject(sent): sent.DecisionRef, 1: ""))
		}
		Do $$$AssertEquals(requests, $List(case, 5), label_"Decide sent ChatAgent "_$List(case, 5)_" requests")
		Set same = 1
		Set position = 0
		While $ListNext(refs, position, one) {
			If one '= answer.DecisionRef Set same = 0
		}
		Do $$$AssertTrue(same && (answer.DecisionRef '= ""), label_"all with the one DecisionRef, the answer's")
		Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), label_"the mock's log is read")
		Set logged = $ClassMethod(fixture, "FindRequests", entries, marker)
		Set statuses = ""
		Set iterator = logged.%GetIterator()
		While iterator.%GetNext(, .entry) {
			Set statuses = statuses _ $Select(statuses = "": "", 1: ",") _ entry.status
		}
		Do $$$AssertEquals(statuses, $List(case, 4), label_"the log holds "_$List(case, 4)_" for the marker")
		If (name = "overloaded") && (logged.%Size() '< 3) {
			Do $$$AssertTrue(..Millis(logged.%Get(1).ts) - ..Millis(logged.%Get(0).ts) '< 1000, label_"the second request comes at least 1 s after the first")
			Do $$$AssertTrue(..Millis(logged.%Get(2).ts) - ..Millis(logged.%Get(1).ts) '< 2000, label_"and the third at least 2 s after the second")
		}
		Do $$$AssertEquals(answer.DurationMs, row.DurationMs, label_"the answer carries the duration of the decision, not that of the last attempt")
		If name = "overloaded" Do $$$AssertTrue(row.DurationMs '< 3000, label_"which runs from the start of the first attempt, across the back-offs of 1 s and 2 s: "_row.DurationMs)
		Set sum = 0
		Set back = $ClassMethod(fixture, "Headers", session, "ChatAgent")
		Set iterator = back.%GetIterator()
		While iterator.%GetNext(, .header) {
			If header.target '= "Decide" Continue
			Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%OpenId(header.bodyId)
			If $IsObject(reply) Set sum = sum + reply.AgentStepCount
		}
		Do $$$AssertEquals(answer.AgentStepCount_"|"_row.AgentStepCount, sum_"|"_sum, label_"the answer's step count is the sum of the runner replies': "_sum)
		Do $$$AssertTrue(sum > 0, label_"which counts the model request of the successful attempt")
		Do $$$AssertEquals(..WarningRows(logMark, "Decide"), 0, label_"Decide logged no warning: a re-send is no fault")
	}
}

/// A rate limit that does not end is sent again until the timer fires (AD-8, FR-4; the row "The re-sends run out (live)"). After Apply(15), a
/// user's turn with overloaded:<key> not armed (always 529) is answered with a rate_limited fallback Reply 12 to 16 s after the send (the timer of
/// 15 s on Decide's clock, and up to a second for the hops before Decide begins and after it answers, on a slower host): Decide kept
/// sending until the timer. It sent at least 4 requests, each a 529 in the mock's log (AI Hub never sends a 529 again), the re-sends coming at least
/// 1 s, 2 s and then 4 s after the failure before them (the back-off, which the last re-send keeps a second before the timer).
Method TestRateLimitedUntilTimer()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set sc = $ClassMethod(fixture, "UseTimer", 15, .saved)
	Set ..TimerSaved = saved
	Do $$$AssertStatusOK(sc, "Timeouts.Apply(15) changes the timer")
	Set marker = "overloaded:"_##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:"_marker_"]] Say hello.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(mock, "LogMark")
	Set started = $ZHorolog
	Set sc = ..Run(request, .answer, .session)
	Set elapsed = $ZHorolog - started
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	Do $$$AssertTrue((elapsed '< 12) && (elapsed < 16), "12 to 16 s after the send, the timer of 15 s and the hops outside Decide: "_$Number(elapsed, 1)_" s")
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "turn")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", answer, row, "turn", "rate_limited"), "", "a rate_limited fallback Reply with every guarantee, in the answer, its XML and the row")
	Do $$$AssertEquals($Select($IsObject(answer): answer.ToolsRun, 1: ""), 0, "that says that no tool ran")
	Set sent = ..CountTo($ClassMethod(fixture, "Headers", session, "Decide"), "ChatAgent")
	Do $$$AssertTrue(sent '< 4, "Decide sent ChatAgent at least 4 requests: "_sent)
	Do $ClassMethod(fixture, "Drain", "ChatAgent")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Set logged = $ClassMethod(fixture, "FindRequests", entries, marker)
	Do $$$AssertEquals(logged.%Size(), sent, "the log holds one entry for each request Decide sent: "_logged.%Size())
	Set all529 = 1
	Set iterator = logged.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.status '= 529 Set all529 = 0
	}
	Do $$$AssertTrue(all529, "and each is a 529")
	Set gaps = $ListBuild(1000, 2000, 4000)
	For i = 1:1:3 {
		If logged.%Size() > i Do $$$AssertTrue(..Millis(logged.%Get(i).ts) - ..Millis(logged.%Get(i - 1).ts) '< $List(gaps, i), "re-send "_i_" comes at least "_($List(gaps, i) / 1000)_" s after the failure before it: "_(..Millis(logged.%Get(i).ts) - ..Millis(logged.%Get(i - 1).ts))_" ms")
	}
}

/// The timer that Decide sets at a re-send ends the decision (AD-6, AD-8, FR-4; the timer after "the re-sends run out"). The TimerSeconds row of
/// Decide is written directly, 12, with Decide started again and the runners' entries kept at the derivation of 60, so that AI Hub's attempts of
/// 25 s do not end the wait: only a timer can (the sessions' timeout_ms of 7000, from the row, does not stop a request in flight, S2). A decide
/// with overloaded-then-held:<key> armed 1 gets a 529 at once and, after a back-off of 1 s, a re-sent request that the mock holds for 18 s. The timer of the re-send is set for the whole seconds left of the 12 (10 or 9), so it fires at 11 to 12 s
/// and the answer is a rate_limited fallback DecisionResponse (the retries ran out) 10 to 16 s after the send, not about 19 s, when the held reply
/// comes: the window keeps 3 s from the held reply and 4 s from the timer for a slow host. Decide sent TriageAgent two requests with the one DecisionRef,
/// the second at least 1 s after the first in the mock's log (a 529, then a 200); the late reply is discarded, and TriageAgent still writes its
/// Usage row, which Usage.Totals counts.
Method TestRateLimitedThenHeld()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	Do ..Put("Decide", "TimerSeconds", 12)
	Set ..DecideChanged = 1
	Do $$$AssertStatusOK($ClassMethod(fixture, "Restart", ..#PRODUCTION_"||Decide"), "Decide is started again with a TimerSeconds of 12")
	Set marker = "overloaded-then-held:"_##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Arm(marker, 1)
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "[[mock:"_marker_"]] Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(mock, "LogMark")
	Set started = $ZHorolog
	Set sc = ..Run(request, .response, .session)
	Set elapsed = $ZHorolog - started
	Set ..LateSession = session
	Do $$$AssertStatusOK(sc, "Decide answers: the timer is no error")
	If '$IsObject(response) || 'response.%IsA("OcuTalon.Bridge.Msg.DecisionResponse") {
		Do $$$AssertTrue(0, "the answer is a DecisionResponse")
		Quit
	}
	Do $$$AssertTrue((elapsed '< 10) && (elapsed < 16), "the answer comes 10 to 16 s after the send, when the timer of the re-send fires and not when the held reply comes at about 19 s: "_$Number(elapsed, 1)_" s")
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "decide")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", response, row, "decide", "rate_limited"), "", "a rate_limited fallback with every guarantee, in the answer, its XML and the row")
	Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
	Do $$$AssertEquals(..CountTo(headers, "TriageAgent"), 2, "Decide sent TriageAgent two requests: the first and the re-send")
	Set refs = ""
	Set iterator = headers.%GetIterator()
	While iterator.%GetNext(, .header) {
		If header.target '= "TriageAgent" Continue
		Set sent = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(header.bodyId)
		Set refs = refs _ $ListBuild($Select($IsObject(sent): sent.DecisionRef, 1: ""))
	}
	Do $$$AssertTrue(($ListLength(refs) = 2) && ($List(refs, 1) '= "") && ($List(refs, 1) = $List(refs, 2)), "both with the one DecisionRef")
	If $IsObject(row) Do $$$AssertEquals(row.Ref, $List(refs, 1), "which is the row's")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Set logged = $ClassMethod(fixture, "FindRequests", entries, marker)
	Set statuses = ""
	Set iterator = logged.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set statuses = statuses _ $Select(statuses = "": "", 1: ",") _ entry.status
	}
	Do $$$AssertEquals(statuses, "529,200", "the log holds a 529, then the held 200 for the marker")
	If logged.%Size() = 2 Do $$$AssertTrue(..Millis(logged.%Get(1).ts) - ..Millis(logged.%Get(0).ts) '< 1000, "the re-send comes at least 1 s after the failure")

	// the late reply is discarded, and its Usage row is written
	Set deadline = $ZHorolog + ..#WAITSECONDS
	While ($ClassMethod(fixture, "Headers", session, "TriageAgent").%Size() < 2) && ($ZHorolog < deadline) {
		Hang 1
	}
	Do $$$AssertEquals($ClassMethod(fixture, "Headers", session, "TriageAgent").%Size(), 2, "TriageAgent answers the held request too, within the ceiling")
	Do $$$AssertTrue(..WaitForStatus(session, "TriageAgent", "Discarded", 1), "and Decide discards that reply")
	Set ids = $ClassMethod(fixture, "UsageIds", "DecisionRef", $List(refs, 1))
	Do $$$AssertEquals(ids.%Size(), 1, "TriageAgent wrote one Usage row for the ref: the held attempt is counted, the 529 wrote none")
	If ids.%Size() = 1 Do $$$AssertTrue(##class(OcuTalon.Bridge.Data.Usage).Totals($List(refs, 1)).inputTokens > 0, "and Usage.Totals counts its tokens")
}

/// A long Retry-After waits only the back-off cap (AD-8, S18; AC5; the row "A long Retry-After (live)"): a user's turn with long-retry-after:<key>
/// armed 1 (a 429 with Retry-After 30) is answered with "Answered after a capped wait." 1.5 to 10 s after the send, through a runner whose entry
/// the Provider step wrote (the test has the step write the entries again first, and starts the runners with them). The log holds 429, then 200,
/// and Decide sent one request.
Method TestLongRetryAfterCapped()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	// the entries are those the Provider step writes: an earlier test may have merged a block of its own into them, so the step writes them again
	// and the runners start again with them (the entries point at the mock key variable, as for every test of the class)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Provider).Run(), "the Provider step writes the entries and the rows again")
	Do $$$AssertStatusOK($ClassMethod(fixture, "PointKeys"), "and the runners start again with the entries behind the mock key variable")
	Set marker = "long-retry-after:"_##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Arm(marker, 1)
	Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:"_marker_"]] Say hello.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(mock, "LogMark")
	Set started = $ZHorolog
	Set sc = ..Run(request, .answer, .session)
	Set elapsed = $ZHorolog - started
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	Do $$$AssertEquals($Select($IsObject(answer): answer.Text_"|"_answer.Fallback, 1: "none"), "Answered after a capped wait.|0", "with the text of the second reply, and no fallback")
	Do $$$AssertTrue((elapsed '< 1.5) && (elapsed < 10), "1.5 to 10 s after the send, not 30: "_$Number(elapsed, 1)_" s")
	Do $$$AssertEquals(..CountTo($ClassMethod(fixture, "Headers", session, "Decide"), "ChatAgent"), 1, "Decide sent ChatAgent one request")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Set statuses = ""
	Set iterator = $ClassMethod(fixture, "FindRequests", entries, marker).%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set statuses = statuses _ $Select(statuses = "": "", 1: ",") _ entry.status
	}
	Do $$$AssertEquals(statuses, "429,200", "the log holds 429, then 200")
}

/// An untrusted decide request with the fixed usage of the scenario usage-decide (one request: 1,200 prompt tokens, 2,000 read from the
/// cache, 600 written to it, 300 output tokens; the reply comes after 1 s). The runner writes one Usage row for the DecisionRef, and its
/// Reply carries the same counts, the cost, the model, a step count of 1 and the wall time of the call. Decide puts the totals on the
/// Decision row and on the DecisionResponse, with a duration of its own that is at least the runner's. The XML of the DecisionResponse
/// holds the eight names.
Method TestUsageDecide()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "[[mock:usage-decide]] Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set sc = ..Run(request, .response, .session)
	Do $$$AssertStatusOK(sc, "Decide answers the decide request")
	If '$IsObject(response) || 'response.%IsA("OcuTalon.Bridge.Msg.DecisionResponse") {
		Do $$$AssertTrue(0, "the answer is a DecisionResponse")
		Quit
	}
	Set ids = ##class(OcuTalon.Test.Agent.RunnerFixture).UsageIds("DecisionRef", response.DecisionRef)
	Do $$$AssertEquals(ids.%Size(), 1, "one Usage row exists for the DecisionRef of the answer")
	If ids.%Size() '= 1 Quit
	Set usage = ##class(OcuTalon.Bridge.Data.Usage).%OpenId(ids.%Get(0))
	Do $$$AssertEquals(usage.ItemId_"|"_usage.Kind_"|"_usage.OwnerRef_"|"_usage.Channel, ref_"|decide|instance|system", "the row has the item, kind, owner and channel of the request")
	Do $$$AssertEquals(usage.Agent_"|"_usage.Model, "TriageAgent|claude-haiku-5-5", "the agent that ran, and its model")
	Do $$$AssertEquals(usage.RequestCount, 1, "one model request")
	Do $$$AssertEquals(usage.InputTokens, 3800, "InputTokens adds the prompt 1,200, the cache read 2,000 and the cache write 600")
	Do $$$AssertEquals(usage.OutputTokens_"|"_usage.CacheReadTokens_"|"_usage.CacheWriteTokens, "300|2000|600", "and the output, cache-read and cache-write tokens are the reported ones")
	Do $$$AssertEquals(usage.LargestRequestTokens, 3800, "the largest request is the one request")
	Do $$$AssertEquals(usage.CostUSD, .000365, "priced from the Price row of the model: 120 + 20 + 75 + 150 micro-dollars")
	Do $$$AssertEquals(usage.Estimated, 0, "and not an estimate")
	Do $$$AssertTrue(usage.RecordedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "RecordedAt is a UTC time: "_usage.RecordedAt)

	Set runner = ..HeaderTo($ClassMethod(fixture, "Headers", session, "TriageAgent"), "Decide")
	Set reply = $Select($IsObject(runner): ##class(OcuTalon.Bridge.Msg.Reply).%OpenId(runner.bodyId), 1: "")
	Do $$$AssertTrue($IsObject(reply), "TriageAgent sent Decide a Reply")
	If $IsObject(reply) {
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Totals(reply, 0), "3800|300|2000|600|.000365|claude-haiku-5-5|1", "the runner's Reply carries the counts, the cost, the model and one step")
		Do $$$AssertTrue(reply.DurationMs >= 1000, "its DurationMs is the wall time of the call, at least the 1 s of the mock: "_reply.DurationMs)
	}
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "decide")
	Do $$$AssertTrue($IsObject(row), "the Decision row is recorded")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Totals(row, 0), "3800|300|2000|600|.000365|claude-haiku-5-5|1", "the row holds the same counts, cost, model and step count")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Totals(response, 0), "3800|300|2000|600|.000365|claude-haiku-5-5|1", "and so does the DecisionResponse")
	Do $$$AssertTrue((row.DurationMs '< $Select($IsObject(reply): reply.DurationMs, 1: 1000)) && (row.DurationMs < 60000), "the row's DurationMs is at least the runner's and under 60,000: "_row.DurationMs)
	Do $$$AssertEquals(response.DurationMs, row.DurationMs, "and the DecisionResponse holds the same")

	Do $$$AssertStatusOK(response.XMLExportToString(.xml), "the DecisionResponse is exported as XML")
	For pair = "InputTokens=3800", "OutputTokens=300", "CacheReadTokens=2000", "CacheWriteTokens=600", "CostUSD=.000365", "Model=claude-haiku-5-5", "AgentStepCount=1", "DurationMs="_row.DurationMs {
		Set name = $Piece(pair, "=", 1)
		Do $$$AssertTrue(xml [ ("<"_name_">"_$Piece(pair, "=", 2)_"</"_name_">"), "the XML holds <"_name_"> with its value: "_$Piece(pair, "=", 2))
	}
}

/// A user's turn with the scenario usage-turn: a request that asks for a tool ChatAgent does not have, and a final text (1,000 prompt
/// tokens and 512 written to the cache, then 1,100 prompt tokens and 512 read from it). One Usage row holds the sums of the two requests
/// and the largest request, which is the larger of the last one and the estimate of the first (since Story 5.1 the estimate of Chat's first request is the larger). The Reply of the runner, the Decision row and the answer hold them, with a step count
/// of the two requests plus the tool call.
Method TestUsageTurn()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:usage-turn]] What is going on in my productions?", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set sc = ..Run(request, .answer, .session)
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(answer.Text, ..#USAGETURNTEXT, "the text is the final text of the scenario")
	Set ids = ##class(OcuTalon.Test.Agent.RunnerFixture).UsageIds("DecisionRef", answer.DecisionRef)
	Do $$$AssertEquals(ids.%Size(), 1, "one Usage row exists for the DecisionRef of the answer: the turn is one Chat call")
	If ids.%Size() '= 1 Quit
	Set usage = ##class(OcuTalon.Bridge.Data.Usage).%OpenId(ids.%Get(0))
	Do $$$AssertEquals(usage.Agent_"|"_usage.Kind_"|"_usage.ItemId, "ChatAgent|turn|"_ref, "the row is ChatAgent's, for the turn")
	Do $$$AssertEquals(usage.RequestCount, 2, "two model requests")
	Do $$$AssertEquals(usage.InputTokens, 3124, "InputTokens: prompt 1,000 + 1,100, cache read 512 and cache write 512")
	Do $$$AssertEquals(usage.OutputTokens_"|"_usage.CacheReadTokens_"|"_usage.CacheWriteTokens, "130|512|512", "OutputTokens 50 + 80, and the cache counts")
	#; The larger of the last request's measured input (prompt 1,100 and cache read 512) and the estimate of the first request, which is Chat's
	#; system prompt, its tool schemas and the input: the estimate passes the measured 1,612 once Chat's toolsets are the reminder and watch tools.
	Set largest = 1612
	Set first = ""
	Set iterator = $ClassMethod(fixture, "StepsOf", answer.DecisionRef).%GetIterator()
	While iterator.%GetNext(, .step) {
		If (first = "") && (step.kind = "model") Set first = +step.estimatedTokens
	}
	Do $$$AssertTrue(first > 0, "the first model step has an estimate: "_first)
	If first > largest Set largest = first
	Do $$$AssertEquals(usage.LargestRequestTokens, largest, "the largest request is the larger of the last one (prompt 1,100 and cache read 512: 1,612) and the estimate of the first ("_first_")")
	Do $$$AssertEquals(usage.CostUSD, .000344, "the cost is that of the sums at the Price row of the model")
	Set expected = "3124|130|512|512|.000344|claude-haiku-5-5|"_..#USAGETURNSTEPS
	Set runner = ..HeaderTo($ClassMethod(fixture, "Headers", session, "ChatAgent"), "Decide")
	Set reply = $Select($IsObject(runner): ##class(OcuTalon.Bridge.Msg.Reply).%OpenId(runner.bodyId), 1: "")
	Do $$$AssertTrue($IsObject(reply), "ChatAgent sent Decide a Reply")
	If $IsObject(reply) Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Totals(reply, 0), expected, "the runner's Reply carries the sums and a step count of the two requests plus the tool call")
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "turn")
	Do $$$AssertTrue($IsObject(row), "the turn's Decision row is recorded")
	If $IsObject(row) Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Totals(row, 0), expected, "it holds the same")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Totals(answer, 0), expected, "and so does the answer")
	Do $$$AssertTrue(answer.DurationMs > 0, "with a duration: "_answer.DurationMs)
}

/// A user's turn whose Chat reaches its loop limit (the scenario tool-loop asks for a tool that ChatAgent does not have, again and again)
/// is a fallback and not an error: the answer is a Reply with no text, the outcome tellnow, Fallback true and the reason unusable, and a
/// turn row says the same. The Usage row of the call is unchanged by the fallback: one row, written by ChatAgent, with the requests and
/// tokens of the call. The model steps of the call are AgentSteps of the DecisionRef, in the session of the decision.
Method TestCostOfFailedTurn()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:tool-loop]] Loop on the tool.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set sc = ..Run(request, .answer, .session)
	Do $$$AssertStatusOK(sc, "Decide answers the turn that fails in the loop")
	If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(answer.Text_"|"_answer.Outcome_"|"_answer.Fallback_"|"_answer.FallbackReason, "|tellnow|1|unusable", "with no text, tellnow, Fallback and the reason unusable")
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "turn")
	Do $$$AssertTrue($IsObject(row), "a Decision row is recorded")
	If $IsObject(row) Do $$$AssertEquals(row.Outcome_"|"_row.Fallback_"|"_row.FallbackReason_"|"_row.Reasons_row.Payload, "tellnow|1|unusable|", "that says the same")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", answer, row, "turn", "unusable"), "", "every guarantee of a fallback holds in the answer, its XML and the row")
	Set ids = ##class(OcuTalon.Test.Agent.RunnerFixture).UsageIds("ItemId", ref)
	Do $$$AssertEquals(ids.%Size(), 1, "one Usage row exists for the item: the call that threw is counted")
	If ids.%Size() '= 1 Quit
	Set usage = ##class(OcuTalon.Bridge.Data.Usage).%OpenId(ids.%Get(0))
	Do $$$AssertEquals(usage.Agent_"|"_usage.Kind, "ChatAgent|turn", "it is ChatAgent's, for the turn")
	Do $$$AssertTrue(usage.RequestCount > 0, "with the requests that were made: "_usage.RequestCount)
	Do $$$AssertTrue(usage.InputTokens > 0, "and their tokens: "_usage.InputTokens)
	Do $$$AssertTrue(usage.LargestRequestTokens > 0, "the largest request is the largest estimate of the requests, because the call returned no response to measure: " _ usage.LargestRequestTokens)
	Do $$$AssertEquals(usage.CacheReadTokens_"|"_usage.CacheWriteTokens, "0|0", "the mock's default usage has no cache tokens")
	Do $$$AssertEquals(usage.CostUSD, $Number((usage.InputTokens * 0.1 + (usage.OutputTokens * 0.5)) / 1000000, 6), "and the cost is priced at 0.10 a million input tokens and 0.50 a million output tokens, below the long tier: "_usage.CostUSD)
	Do $$$AssertEquals(answer.InputTokens_"|"_answer.OutputTokens_"|"_answer.CostUSD_"|"_answer.Model, usage.InputTokens_"|"_usage.OutputTokens_"|"_usage.CostUSD_"|"_usage.Model, "the answer carries the totals of the row")
	Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
	Set runner = ..HeaderTo(headers, "ChatAgent")
	Set sent = $Select($IsObject(runner): ##class(OcuTalon.Bridge.Msg.Request).%OpenId(runner.bodyId), 1: "")
	If '$IsObject(sent) {
		Do $$$AssertTrue(0, "a header to ChatAgent carries the request")
		Quit
	}
	Do $$$AssertEquals(answer.DecisionRef, sent.DecisionRef, "the DecisionRef of the answer is that of the runner's request")
	Set steps = $ClassMethod(fixture, "StepsOf", sent.DecisionRef)
	Do $$$AssertTrue(steps.%Size() > 0, "the model steps of the call are AgentSteps of the DecisionRef: "_steps.%Size())
	Set positions = ""
	For i = 0:1:steps.%Size() - 1 {
		Set positions = positions _ $Select(i = 0: "", 1: ",") _ steps.%Get(i).position
	}
	Set expectedPositions = ""
	For i = 1:1:steps.%Size() {
		Set expectedPositions = expectedPositions _ $Select(i = 1: "", 1: ",") _ i
	}
	Do $$$AssertEquals(positions, expectedPositions, "from Position 1, in order")
	Do $$$AssertEquals(..Targets(headers), "AgentSteps,ApprovalStartIn,ChatAgent,Ens.Alarm", "Decide sent them to AgentSteps, and nothing else but the runner request, the timer and its answer")
	Do $$$AssertEquals(..CountTo(headers, "AgentSteps"), steps.%Size(), "one header to AgentSteps for each step")
	// what the runner buffered, read from its Reply, against what AgentSteps holds, read from the AgentStep messages
	Set back = ..HeaderTo($ClassMethod(fixture, "Headers", session, "ChatAgent"), "Decide")
	Set reply = $Select($IsObject(back): ##class(OcuTalon.Bridge.Msg.Reply).%OpenId(back.bodyId), 1: "")
	Do $$$AssertTrue($IsObject(reply), "ChatAgent sent Decide a Reply")
	If $IsObject(reply) {
		Set buffered = ##class(%Library.DynamicAbstractObject).%FromJSON(reply.Steps)
		Do $$$AssertEquals(steps.%Size(), buffered.%Size(), "AgentSteps holds exactly the steps that the runner buffered: "_buffered.%Size())
		Set common = $Select(steps.%Size() < buffered.%Size(): steps.%Size(), 1: buffered.%Size())
		For i = 0:1:common - 1 {
			Do $$$AssertEquals(steps.%Get(i).kind_"|"_steps.%Get(i).label, buffered.%Get(i).kind_"|"_buffered.%Get(i).label, "AgentStep "_(i + 1)_" is the runner's step "_(i + 1)_": the same kind and label")
		}
	}
	Do $$$AssertEquals(..CountTo(headers, "ChatAgent"), 1, "and one request to ChatAgent, never a second")
	If $IsObject(row) Do $$$AssertTrue(row.AgentStepCount '< steps.%Size(), "and the row's step count is at least their number: "_row.AgentStepCount)
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

/// Run returns the session of the header that carries the request it sent, never that of the first header addressed to Decide after
/// a mark: another message to Decide between the mark and the send, as the discarded response of an earlier decision's Ens.Alarm
/// timer is, must not be taken for the call's own. A message of another class stands in for it: Decide refuses it in a session of its
/// own. SessionOf counts only the headers after the mark it is given.
Method TestRunSessionIsItsOwn()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(fixture, "HeaderMark")
	Set stray = ##class(Ens.StringRequest).%New("x")
	Do $$$AssertStatusNotOK($ClassMethod(fixture, "Send", "Decide", stray, .none), "an unrelated message to Decide, sent after the mark, is refused")
	Set straySession = $ClassMethod(fixture, "SessionOf", stray)
	Do $$$AssertTrue(straySession '= "", "its header has a session of its own: "_straySession)
	Set sc = $ClassMethod(fixture, "Run", request, .response, .session, "", mark)
	Do $$$AssertStatusOK(sc, "Decide answers the request sent after it")
	If '$IsObject(response) || 'response.%IsA("OcuTalon.Bridge.Msg.DecisionResponse") {
		Do $$$AssertTrue(0, "the answer is a DecisionResponse")
		Quit
	}
	Do $$$AssertTrue(session '= straySession, "Run does not return the session of the unrelated message")
	Do $$$AssertTrue($ClassMethod(fixture, "SessionSince", mark, "Decide") '= session, "and a lookup by the mark would not have: the first header to Decide after it is another message's")
	Do $$$AssertEquals($ClassMethod(fixture, "SessionOf", request, $ClassMethod(fixture, "HeaderMark")), "", "SessionOf counts only the headers after the mark it is given, so none carries the request after the send")
	Do $$$AssertEquals(session, $ClassMethod(fixture, "SessionOf", response), "it returns the session that holds the answer")
	Do $$$AssertEquals(..CountTo($ClassMethod(fixture, "Headers", session, "Decide"), "TriageAgent"), 1, "which holds the request to TriageAgent")
	Do $$$AssertEquals(..CountTo($ClassMethod(fixture, "Headers", straySession, "Decide"), "TriageAgent"), 0, "and the session of the unrelated message holds none")
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "decide")
	Do $$$AssertTrue($IsObject(row) && (row.TraceSessionId = session), "the Decision row's TraceSessionId is that session")
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

/// A user's turn whose reply the provider refused is answered with a fallback Reply and nothing else: Text, HostData, Steps, FailureText
/// and FinishReason are empty, Fallback is true and the reason is refusal, and the refused text is in no field of the answer, the XML
/// that Visual Trace shows included. No check row, tool or approval follows: Decide sends only to the runner, the timer, AgentSteps and
/// its caller.
Method TestTurnFallbackIsReplyOnly()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:refusal]] Say something.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set sc = ..Run(request, .answer, .session)
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(answer.Fallback_"|"_answer.FallbackReason_"|"_answer.Outcome, "1|refusal|tellnow", "the answer is a refusal fallback")
	Do $$$AssertEquals(answer.Text_"|"_answer.HostData_"|"_answer.Steps_"|"_answer.FailureText_"|"_answer.FinishReason, "||||", "with no text, host data, steps, failure text or finish reason")
	Do $$$AssertEquals(answer.Tainted_"|"_answer.SessionRotated_"|"_answer.ToolsRun_"|"_answer.SessionBroken_"|"_answer.Busy, "0|0|0|0|0", "and no flag set")
	Do $$$AssertStatusOK(answer.XMLExportToString(.xml), "the answer is exported as XML")
	Do $$$AssertTrue(xml '[ "The CI mock refuses this request.", "the refused text is in no field of it")
	Do $$$AssertTrue(xml [ "<Fallback>true</Fallback>", "the XML shows Fallback true")
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "turn")
	Do $$$AssertTrue($IsObject(row), "a turn row is recorded")
	If $IsObject(row) {
		Do $$$AssertEquals(row.Outcome_"|"_row.Fallback_"|"_row.FallbackReason_"|"_row.Reasons_"|"_row.Confidence_"|"_row.Payload, "tellnow|1|refusal|||", "that says the same and keeps no text")
		Do $$$AssertEquals(answer.DecisionRef, row.Ref, "with the DecisionRef of the answer")
	}
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", answer, row, "turn", "refusal"), "", "every guarantee of a fallback holds in the answer, its XML (the reason too) and the row")
	Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
	Do $$$AssertEquals(..Targets(headers), "AgentSteps,ApprovalStartIn,ChatAgent,Ens.Alarm", "Decide sent only to the runner, the timer, AgentSteps and its caller")
	Do $$$AssertEquals(..CountTo(headers, "ChatAgent"), 1, "with one request to the runner, never a second")
}

/// A runner that ends its call with an error status instead of a Reply: the Model of ChatAgent is one that no ModelFamily row matches (the
/// test takes the default family out for it, since its empty prefix matches every model), so the session cannot be configured and nothing is
/// sent. Ens calls OnError and then OnResponse: the answer is an error fallback Reply, it comes in well under the timer, nothing reached
/// the mock, and the row says the same. The row and the family are put back and ChatAgent is restarted.
Method TestRunnerErrorIsFallback()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	Do ..TakeOutDefaultFamily()
	Do ..Put("ChatAgent", "Model", "zz-no-such-model")
	Set ..ChatChanged = 1
	Do $$$AssertStatusOK($ClassMethod(fixture, "Restart", ..#PRODUCTION_"||ChatAgent"), "ChatAgent is started again with the model")
	Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", "Hello there.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(mock, "LogMark")
	Set started = $ZHorolog
	Set sc = ..Run(request, .answer, .session)
	Set elapsed = $ZHorolog - started
	Do $$$AssertStatusOK(sc, "Decide answers the turn, though the runner ended with an error status")
	Do $$$AssertTrue(elapsed < 10, "and does so at once, in under 10 s, not after its timer of 60 s: "_$Number(elapsed, 1)_" s")
	If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(answer.Fallback_"|"_answer.FallbackReason_"|"_answer.Outcome_"|"_answer.Text, "1|error|tellnow|", "an error fallback with no text")
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "turn")
	Do $$$AssertTrue($IsObject(row), "a row is recorded")
	If $IsObject(row) Do $$$AssertEquals(row.Outcome_"|"_row.Fallback_"|"_row.FallbackReason_"|"_row.TraceSessionId, "tellnow|1|error|"_session, "that says the same, in the session of the request")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", answer, row, "turn", "error"), "", "every guarantee of a fallback holds in the answer, its XML and the row")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Do $$$AssertEquals($ClassMethod(fixture, "FindRequests", entries, ref).%Size(), 0, "nothing reached the mock")
	Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
	Do $$$AssertEquals(..Targets(headers), "ApprovalStartIn,ChatAgent,Ens.Alarm", "Decide sent only the runner request, the timer and its answer")
	Do $$$AssertEquals(..CountTo(headers, "ChatAgent"), 1, "with one request to the runner, never a second")
	Do $$$AssertEquals(..ErrorHeaders(session, "ChatAgent"), 1, "the runner's answer was an error response, which OnError turned into the fallback")
}

/// The prechecks are never sent (AC2). A token budget of 1 (Decide started again, since the setting is read at its start) gives budget for a
/// decide and a turn; a cap of 1 with a gateway spend of 1 for today gives daily_cap, with one budget.capped event (owner instance, the
/// day) that comes after decision.recorded, with the row and the mark in place, from this path alone. For each, the answer, its XML and the
/// row carry every guarantee of a fallback (RunnerFixture.FallbackProblems), Decide sent nothing but its answer (no runner request and no
/// timer), and no request with the ref reached the mock: that is read after the runner has handled every message sent to it
/// (RunnerFixture.Drain), so that a request of Decide's could not arrive after the read. A control shows that the same decide goes through
/// to the mock once the budget is off, so that the budget alone kept the decides above from it.
Method TestPrechecks()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set today = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())

	// the token budget
	Do ..Put("Decide", "DecisionTokenBudget", 1)
	Set ..DecideChanged = 1
	Do $$$AssertStatusOK($ClassMethod(fixture, "Restart", ..#PRODUCTION_"||Decide"), "Decide is started again with a token budget of 1")
	For kind = "decide", "turn" {
		Set provenance = $Select(kind = "turn": "user", 1: "untrusted")
		Set runner = $Select(kind = "turn": "ChatAgent", 1: "TriageAgent")
		Set label = "a "_kind_" over the token budget: "
		Set request = $ClassMethod(fixture, "NewRequest", kind, provenance, "Triage this item.", .ref)
		Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
		Set mark = $ClassMethod(mock, "LogMark")
		Set sc = ..Run(request, .answer, .session)
		Do $$$AssertStatusOK(sc, label_"it is answered")
		Set row = $ClassMethod(fixture, "DecisionOf", ref, kind)
		Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", answer, row, kind, "budget"), "", label_"a tellnow fallback with the reason budget, in the answer, its XML and the row")
		Set took = $Select($IsObject(row) && $IsObject(answer): row.DurationMs_"|"_answer.DurationMs, 1: "|none")
		Do $$$AssertTrue(($Piece(took, "|") '= "") && ($Piece(took, "|") = $Piece(took, "|", 2)), label_"the row and the answer carry the time Decide took (DurationMs): "_took)
		Do $$$AssertEquals(..Targets($ClassMethod(fixture, "Headers", session, "Decide")), "ApprovalStartIn", label_"Decide sent no runner request and no timer, only its answer")
		Do ..AssertNotSent(runner, mark, ref, label)
	}
	Do ..Put("Decide", "DecisionTokenBudget", 0)
	Do $$$AssertStatusOK($ClassMethod(fixture, "Restart", ..#PRODUCTION_"||Decide"), "Decide is started again with the budget off")

	// the control: the same decide with the budget off is sent to the mock
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "Triage this item.", .control)
	Set ..ItemIds = ..ItemIds _ $ListBuild(control)
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = ..Run(request, .answer, .session)
	Do $$$AssertStatusOK(sc, "control: the same decide with the budget off is answered")
	Do $$$AssertEquals($Select($IsObject(answer): answer.Fallback, 1: "none"), 0, "control: with a decision and no fallback")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "control: the mock's log is read")
	Do $$$AssertEquals($ClassMethod(fixture, "FindRequests", entries, control).%Size(), 1, "control: its request reached the mock, so only the budget kept the decides above from it")

	// the daily cap
	Do ..SwapSink()
	Do ..Put("Decide", "DailyCostCapUSD", 1)
	Do ..Put("Decide", "GatewaySpendUSD", 1)
	Do ..Put("Decide", "GatewaySpendDate", today)
	Set label = "a decide with the day's cap reached: "
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = ..Run(request, .answer, .session)
	Do $$$AssertStatusOK(sc, label_"it is answered")
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "decide")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", answer, row, "decide", "daily_cap"), "", label_"a tellnow fallback with the reason daily_cap, in the answer, its XML and the row")
	Set took = $Select($IsObject(row) && $IsObject(answer): row.DurationMs_"|"_answer.DurationMs, 1: "|none")
	Do $$$AssertTrue(($Piece(took, "|") '= "") && ($Piece(took, "|") = $Piece(took, "|", 2)), label_"the row and the answer carry the time Decide took (DurationMs): "_took)
	Do $$$AssertEquals(..Targets($ClassMethod(fixture, "Headers", session, "Decide")), "ApprovalStartIn", label_"Decide sent no runner request and no timer, only its answer")
	Do ..AssertNotSent("TriageAgent", mark, ref, label)
	Set calls = $ClassMethod(fixture, "SinkCalls")
	Do $$$AssertEquals(..EventTypes(calls), "decision.recorded,budget.capped", label_"this path alone fired decision.recorded and then one budget.capped")
	If calls.%Size() = 2 {
		Do $$$AssertEquals(calls.%Get(0).rowExists, 1, label_"decision.recorded came after the row was saved")
		Do $$$AssertEquals(calls.%Get(1).ownerRef_"|"_calls.%Get(1).payload_"|"_calls.%Get(1).markExists, "instance|{""day"":"""_today_"""}|1", label_"budget.capped has the owner instance and the day, and came after the mark was set")
	}
	Do $$$AssertTrue($Data(^OcuTalonBP.UsageCapped(today)) > 0, label_"and the day is marked")
}

/// Budget settings that their datatypes refuse count as off, and Precheck names each one (AC8; DW-76). The System Default Settings rows of
/// DecisionTokenBudget (abc), DailyCostCapUSD (abc) and GatewaySpendUSD (x) are written by SQL, as a hand edit or an import could write
/// them, and Decide is started again, so that each new instance of Decide gets them and must still be saved before OnRequest: a decide is
/// sent to the mock and answered with a decision, not a fallback, and Precheck logs one warning that names each setting.
Method TestBadBudgetSettings()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	Do ..Put("Decide", "DecisionTokenBudget", "abc")
	Do ..Put("Decide", "DailyCostCapUSD", "abc")
	Do ..Put("Decide", "GatewaySpendUSD", "x")
	Set ..DecideChanged = 1
	Do $$$AssertStatusOK($ClassMethod(fixture, "Restart", ..#PRODUCTION_"||Decide"), "Decide is started again with the three settings")
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(mock, "LogMark")
	Set logMark = $ClassMethod(fixture, "EventMark")
	Set sc = ..Run(request, .answer, .session)
	Do $$$AssertStatusOK(sc, "a decide is answered though the three settings are not numbers: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals($Select($IsObject(answer): answer.%ClassName(1)_"|"_answer.Fallback, 1: "none"), "OcuTalon.Bridge.Msg.DecisionResponse|0", "with a decision, not a fallback: the settings count as off")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Do $$$AssertEquals($ClassMethod(fixture, "FindRequests", entries, ref).%Size(), 1, "the request was sent to the model")
	For setting = "DecisionTokenBudget", "DailyCostCapUSD", "GatewaySpendUSD" {
		Do $$$AssertEquals($ClassMethod(fixture, "Warnings", logMark, "OcuTalon.Bridge.Process.Decide", "Precheck", $ListBuild("The setting "_setting_" of Decide")), 1, "Precheck logged one warning that names "_setting)
	}
}

/// Both paths to daily_cap mark the day once (AC3; U-16). With the cap off and the day unmarked, and Decide's host sink swapped to the probe
/// sink in its shared mode: a decide with [[mock:daily-cap]] (the gateway's HTTP 403) gets daily_cap after one call of the runner and marks the
/// day; a decide on Triage's default script then gets daily_cap from the precheck and sends nothing; so does a user's turn. The sink's calls
/// are read after each step, so that the count is the work of the path that has just run and not of one path alone: after the 403, decision.recorded
/// and one budget.capped; after the decide and the turn of the precheck, one decision.recorded each and no second budget.capped. The budget.capped
/// has the owner instance and the day, and came after the first row was saved and the mark was set. Every fallback carries all its guarantees
/// (RunnerFixture.FallbackProblems), and what the precheck did not send is read from the mock's log after the runner has handled every
/// message sent to it (RunnerFixture.Drain). The path of the precheck alone fires its own budget.capped: TestPrechecks.
Method TestDailyCapBothPaths()
{
	If '..Prepare() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set mock = "OcuTalon.Test.Contract.Mock"
	Set today = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())
	Do ..Put("Decide", "DailyCostCapUSD", 0)
	Do ..SwapSink()
	Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(today)), 0, "the day is not marked")
	Do $$$AssertEquals(..EventTypes($ClassMethod(fixture, "SinkCalls")), "", "and the sink has had no call")

	// the gateway's 403
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "[[mock:daily-cap]] Triage this item.", .first)
	Set ..ItemIds = ..ItemIds _ $ListBuild(first)
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = ..Run(request, .answer, .session)
	Do $$$AssertStatusOK(sc, "the decide that the gateway refuses is answered")
	Set row = $ClassMethod(fixture, "DecisionOf", first, "decide")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", answer, row, "decide", "daily_cap"), "", "with a tellnow fallback with the reason daily_cap, in the answer, its XML and the row")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Do $$$AssertEquals($ClassMethod(fixture, "FindRequests", entries, first).%Size(), 1, "the runner called the gateway once, and AI Hub did not send the refused request again")
	Do $$$AssertTrue($Data(^OcuTalonBP.UsageCapped(today)) > 0, "and the day is marked")
	Do $$$AssertEquals(..Targets($ClassMethod(fixture, "Headers", session, "Decide")), "ApprovalStartIn,Ens.Alarm,TriageAgent", "Decide sent the runner request and the timer, and no step: the call failed at its first request")
	Do $$$AssertEquals(..EventTypes($ClassMethod(fixture, "SinkCalls")), "decision.recorded,budget.capped", "the 403's fallback alone fired decision.recorded and then one budget.capped")

	// the precheck, for a decide and for a turn
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "Triage this item.", .second)
	Set ..ItemIds = ..ItemIds _ $ListBuild(second)
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = ..Run(request, .answer, .session)
	Do $$$AssertStatusOK(sc, "the next decide is answered")
	Set row = $ClassMethod(fixture, "DecisionOf", second, "decide")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", answer, row, "decide", "daily_cap"), "", "from the precheck: a tellnow fallback with the reason daily_cap, in the answer, its XML and the row")
	Do $$$AssertEquals(..Targets($ClassMethod(fixture, "Headers", session, "Decide")), "ApprovalStartIn", "Decide sent only its answer")
	Do ..AssertNotSent("TriageAgent", mark, second, "the decide of the precheck: ")
	Do $$$AssertEquals(..EventTypes($ClassMethod(fixture, "SinkCalls")), "decision.recorded,budget.capped,decision.recorded", "the precheck's fallback fired decision.recorded and no second budget.capped")
	Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", "What is going on?", .third)
	Set ..ItemIds = ..ItemIds _ $ListBuild(third)
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = ..Run(request, .answer, .session)
	Do $$$AssertStatusOK(sc, "a user's turn is answered")
	Set row = $ClassMethod(fixture, "DecisionOf", third, "turn")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", answer, row, "turn", "daily_cap"), "", "with a daily_cap fallback Reply: tellnow, no text, no host data, in the answer, its XML and the row")
	Do $$$AssertEquals(..Targets($ClassMethod(fixture, "Headers", session, "Decide")), "ApprovalStartIn", "Decide sent only its answer")
	Do ..AssertNotSent("ChatAgent", mark, third, "the turn of the precheck: ")

	// the events
	Set calls = $ClassMethod(fixture, "SinkCalls")
	Do $$$AssertEquals(..EventTypes(calls), "decision.recorded,budget.capped,decision.recorded,decision.recorded", "the sink got decision.recorded, budget.capped once, and decision.recorded twice more")
	If calls.%Size() '< 2 {
		Do $$$AssertEquals(calls.%Get(0).rowExists, 1, "the first decision.recorded came after the row was saved")
		Do $$$AssertEquals(calls.%Get(1).ownerRef_"|"_calls.%Get(1).payload_"|"_calls.%Get(1).markExists, "instance|{""day"":"""_today_"""}|1", "budget.capped has the owner instance and the day, and came after the mark was set")
	}
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State().capped, 1, "and Budget.State reports the cap reached")
}

/// --- helpers ---
/// 1 when the production runs with every item in the CI override's environment and the entries of the runners are pointed at the
/// mock key variable. Otherwise the test fails with the reason, and quits. The entries are put back by OnAfterAllTests. Today's day
/// mark is removed first, so that no earlier class leaves the day capped.
Method Prepare() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).ReadyReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	If '..Pointed {
		Set ..Pointed = 1
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).PointKeys()
		Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
		If $$$ISERR(sc) Quit 0
	}
	Quit 1
}

/// Sends the request to Decide and waits for the answer. response is the answer (or ""), and session is the session of the
/// request, which holds every header of the call (Test.Agent.RunnerFixture.Run).
Method Run(request As OcuTalon.Bridge.Msg.Request, Output response As %Persistent, Output session As %Integer) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).Run(request, .response, .session)
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

/// The targets of the headers, sorted and comma-separated (Test.Agent.RunnerFixture.Targets).
ClassMethod Targets(headers As %DynamicArray) As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).Targets(headers)
}

/// The first header of the array that is addressed to the target, or "" (Test.Agent.RunnerFixture.HeaderTo).
ClassMethod HeaderTo(headers As %DynamicArray, target As %String) As %DynamicObject [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderTo(headers, target)
}

/// The status of the first header that the item sent in the session (the newest with newest 1), as its display name, or "" when there
/// is none.
ClassMethod AnswerStatus(session As %Integer, source As %String, newest As %Boolean = 0) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Status FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ? ORDER BY ID"_$Select(newest: " DESC", 1: ""), session, source)
	If 'result.%Next() Quit ""
	Set status = result.%GetData(1)
	If status '? 1.N Quit status
	Quit $Piece(##class(Ens.DataType.MessageStatus).#DISPLAYLIST, ",", status + 1)
}

/// Waits, up to WAITSECONDS, until the first header that the item sent in the session (the newest with newest 1) has the status (its
/// display name). 1 when it has. The wait is a poll once a second.
ClassMethod WaitForStatus(session As %Integer, source As %String, status As %String, newest As %Boolean = 0) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + ..#WAITSECONDS
	While (..AnswerStatus(session, source, newest) '= status) && ($ZHorolog < deadline) {
		Hang 1
	}
	Quit ..AnswerStatus(session, source, newest) = status
}

/// The number of headers in the array that are addressed to the target (Test.Agent.RunnerFixture.CountTo).
ClassMethod CountTo(headers As %DynamicArray, target As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).CountTo(headers, target)
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

/// Arms the countdown of the mock for the marker (Test.Contract.Mock.Arm) with the number of requests that get its first reply, and remembers the
/// marker, so that OnAfterOneTest clears it.
Method Arm(marker As %String, remaining As %Integer) [ Private ]
{
	Set ..Armed = ..Armed _ $ListBuild(marker)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).Arm(marker, remaining), "the countdown of "_marker_" is armed with "_remaining)
}

/// A time of the log (ts, UTC ISO 8601 to the millisecond: 2026-10-23T05:57:33.411Z) in milliseconds since the day count began, for differences.
ClassMethod Millis(ts As %String) As %Integer [ Private ]
{
	Set date = $Piece(ts, "T", 1)
	Set time = $Piece($Piece(ts, "T", 2), "Z", 1)
	Set seconds = $Piece(time, ":", 3)
	Quit ($ZDateH(date, 3) * 86400000) + ($Piece(time, ":", 1) * 3600000) + ($Piece(time, ":", 2) * 60000) + ($Piece(seconds, ".", 1) * 1000) + $Piece(seconds, ".", 2)
}

/// The number of warnings (type 3) that the item logged after the event-log mark (RunnerFixture.EventMark, WarningRows).
ClassMethod WarningRows(mark As %Integer, item As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).WarningRows(mark, item)
}

/// Puts the System Default Settings row of the setting of the item (Test.Agent.RunnerFixture.PutDefault) and remembers the row that was
/// there, once, for OnAfterOneTest (RememberDefault).
Method Put(item As %String, setting As %String, value As %String) [ Private ]
{
	Set saved = ..SavedRows
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RememberDefault(.saved, item, setting)
	Set ..SavedRows = saved
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).PutDefault(item, setting, value), "the setting "_setting_" of "_item_" is '"_value_"'")
}

/// Swaps the host sink of Decide for the probe sink, in the stored configuration of the production, and turns on the probe's shared mode
/// (^OcuTalonTest("ProbeSink","shared")), so that the calls that Decide's own job makes can be read from this process. OnAfterOneTest puts
/// the setting back and kills ^OcuTalonTest("ProbeSink").
Method SwapSink() [ Private ]
{
	Kill ^OcuTalonTest("ProbeSink")
	Set ^OcuTalonTest("ProbeSink", "shared") = 1
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).UseItemSetting("Decide", "Host", "HostSinkClass", "OcuTalon.Test.Bridge.ProbeSink", .saved)
	Do $$$AssertStatusOK(sc, "Decide's host sink is the probe sink, in its shared mode")
	If '$IsObject(..Swaps) Set ..Swaps = []
	If $IsObject(saved) Do ..Swaps.%Push({"item": "Decide", "saved": (saved)})
}

/// Takes the default model family (the row with the empty prefix, which matches every model) out of the table, for a test that needs a
/// model that no family matches; OnAfterOneTest puts it back.
Method TakeOutDefaultFamily() [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Bridge_Data.ModelFamily WHERE Family = ?", "default")
	If 'result.%Next() Quit
	Set row = ##class(OcuTalon.Bridge.Data.ModelFamily).%OpenId(result.%GetData(1))
	Set ..FamilySaved = $ListBuild(row.Family, row.ModelPrefix, row.CapKey, row.EffortKey)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Data.ModelFamily).%DeleteId(row.%Id()), "the default model family is taken out for the test")
}

/// Asserts that no request with the ref reached the mock since the mark, read once the runner has handled every message sent to it
/// (RunnerFixture.Drain). A request that Decide sends when it should not has a header to the runner at once, but it reaches the mock after
/// the runner has taken it up; a read of the log right after Decide's answer can come before that, and would pass. With the runner drained,
/// the request has arrived or never will.
Method AssertNotSent(runner As %String, mark As %Integer, ref As %String, label As %String) [ Private ]
{
	Set mock = "OcuTalon.Test.Contract.Mock"
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Drain(runner), label_runner_" answered a request of its own, so it had handled everything sent to it before")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), label_"the mock's log is read")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, ref).%Size(), 0, label_"no request with the reference reached the mock")
}

/// The types of the calls of the sink (RunnerFixture.SinkCalls), in order, comma-separated.
ClassMethod EventTypes(calls As %DynamicArray) As %String [ Private ]
{
	Set types = ""
	For i = 0:1:calls.%Size() - 1 {
		Set types = types _ $Select(i = 0: "", 1: ",") _ calls.%Get(i).type
	}
	Quit types
}

/// The number of headers in the session sent by the item whose response is an error.
ClassMethod ErrorHeaders(session As %Integer, source As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ? AND SourceConfigName = ? AND IsError = 1", session, source)
	Do result.%Next()
	Quit result.%GetData(1)
}

}
