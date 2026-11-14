/// Tests of Decide that need no production and no mock (Story 1.3; AD-6, AD-7, AD-20, AD-31): the pure and the in-process rows of
/// the I/O matrix. They drive the class methods that the business process itself calls, in particular Conclude, which OnResponse
/// calls, with the probe filter and the probe sink of this package. Nothing is sent. Every test removes the Decision rows it made
/// and kills the process-private globals ^||ZzProbeFilter and ^||ZzProbeSink.
///   - TestRefusedRequests: Admit gives "not implemented" (5003) for a foreign message class, and an error that names the field for a
///     kind, provenance, ItemId, OwnerRef or Input that is missing or unknown; a request of kind tool (Story 30.3) is admitted with
///     provenance user and the Ref of an approval request as its ItemId and no Input, and refused naming the Provenance or the ItemId;
///   - TestToolRequest (Story 30.3, rows 4a and 9): a tool request goes to the Runner of the approval row it names, with no precheck, no
///     probe and no ReplyClass; a reply without a failure records the outcome act and a repeat is answered from the row with no send; a
///     failure reply records a fallback with the reason error and is never sent again; a row with no runner is closed failed, a missing
///     row and a fix row are left alone, and each is answered with a fallback;
///   - TestToolFailureReasons (Story 30.7, DW-470, rows 14 to 16): a failed replay whose failure text is the provider's no-key error and whose
///     Reply says the call did not run (ToolsRun 0) records a fallback with the reason no_key and the sentence REPLAYNOKEY as its Reasons; one
///     whose provider object could not be built (the AI Hub provider object that the runner's BuildAgent makes from its settings, PROVIDERTEXT)
///     records the reason error and the sentence REPLAYPROVIDER; the same texts with ToolsRun 1 (a tool's own error), a provider error that is
///     neither, a failure of the context (a bridge text with ToolsRun 0) and a failure with no Reply stay error with no reasons;
///   - TestToolRowHeldBeforeAnUpdate (Story 30.3, row 9, owner decision U-170): an approved tool_call row with an empty ToolSource, and one with
///     an empty Runner, is closed failed through FinishExecution and never sent to a runner (the tool runs 0 times); the fallback Decision row
///     carries a plain-English reason (HELDBEFOREUPDATE) that holds no class name, no code and no status text;
///   - TestBadSettings: CheckSettings names TimerSeconds (0, 11, 111, x), ReplyFilterClass (missing, not an extension class) and
///     ReplyClass (missing, not a JSON class; a diagnose request with none);
///   - TestReplyCheck: a JSON object, also inside one code fence, passes; an outcome that is not one of OUTCOME, no reason, a blank
///     reason, no confidence, a confidence over 1, an extra field, text that is not JSON, an array and an empty text fail; and
///     Conclude records nothing for a reply that fails;
///   - TestFilter: the filter runs once on each model-written text (each reason; a turn's text) and not on the code-written line;
///   - TestFilterBlanks: a decision with no reason left once filtered, and a turn with no text left, are refused with no row and no
///     event; a reason that the filter blanks while another stays is dropped from the row;
///   - TestSink: decision.recorded is fired after the commit with the owner and exactly {"ref":<Ref>}; an error, an exception and a
///     sink class that is no extension (also one that has an OnEvent) are logged as a warning and sent no event, and the decision
///     stands;
///   - TestConcurrentSave: a row that another call saved first answers, with no second row and no event, and a turn refuses;
///   - TestRecord: a save refused by the unique index on (ItemId, Kind) answers from the row that won, and a turn row refuses;
///   - TestLostRace: a row that another call saves after Conclude's check for an existing row, and before its own save, answers,
///     with no second row and no event;
///   - TestConcludeChecksFilter: Conclude refuses a filter class that is no ReplyFilter, with no row and no event;
///   - TestUserRule: a user's ignore and digest become tellnow with the code-written line first; a user's act and tellnow and every
///     untrusted outcome stay;
///   - TestConfidence: 0.12 stays 0.12 and 0.123 is recorded as 0.12, and the confidence never changes the outcome;
///   - TestResponseFromRow: the answer for a recorded decide row, and the refusal for a turn row;
///   - TestOnResponseUsesItsSettings and TestOnRequestUsesItsSettings: the business process hands its own ReplyFilterClass,
///     HostSinkClass, TimerSeconds and session to the class methods, on a Decide instance of the test with no production started;
///   - TestRecordedAtIsUtc: RecordedAt is a UTC time whatever the zone of the process.
/// Added by QA (Story 1.3):
///   - TestUserRule also pins that the user rule is for decide requests only (a user's diagnose reply keeps ignore and digest);
///   - TestReplyCheck also refuses a missing, null or wrong-case outcome and a null, string or negative confidence, and accepts
///     the confidences 0 and 1;
///   - TestReasonLines: a line break inside a model reason becomes a space, so that a reason is one line of the row and cannot add
///     a line of its own, such as a forged copy of the code-written line of the user rule; the Payload keeps the reasons as filtered;
///   - TestTurnKeepsReply: the answer to a turn is a clone of the runner's Reply, with only the Text filtered and the DecisionRef and
///     the outcome set; the runner's own Reply is not changed;
///   - TestSaveFailure: a row that cannot be saved for another reason than the (ItemId, Kind) race is no answer: no response, no
///     event, no row;
///   - TestOnRequestAnswersRecorded: OnRequest answers a recorded decide or diagnose item from its row before it checks any
///     setting or sends anything, and refuses a recorded turn naming the item and the Ref.
/// Added by Story 1.4 (AD-20, AD-26, AD-31):
///   - TestTotals: Conclude puts the sums of the Usage rows of its DecisionRef on the Decision row and on the answer, a decide's and a
///     turn's: the four token counts, the cost, the model (the reply's that answered since Story 17.2, else the newest row's), the step count of the runner's reply and the duration it
///     is given; with no row the token fields, cost and model are empty, and with a row of unknown cost the cost is empty;
///   - TestTurnKeepsReply now takes the totals and the model from the Usage rows, and every other field from the runner's reply;
///   - TestResponseFromRow also pins that an answer built from a recorded row carries the row's totals;
///   - TestFireEventTypes: FireEvent sends decision.recorded with {"ref"} by default, and the given type with the given payload, and logs
///     a failure with the sink, the event and the subject.
/// Added by Story 1.5 (AD-9, AD-26, AD-30):
///   - TestStepMessages: StepMessages builds one AgentStep for each record of the reply's Steps, with the DecisionRef given, the Position
///     of the record in the array, and its kind, label, summary, duration, status and estimate; a reply with no Steps, with white space
///     and with a reply of another class gets none and no warning; Steps that is not a JSON array, and a record that is not an object, get
///     none (or skip the record) and one warning that names the DecisionRef and not the content; Conclude's answer to a turn has no Steps;
///   - TestTurnKeepsReply also pins that the answer to a turn does not carry the runner's Steps, and the runner's own Reply keeps them.
/// Added by the QA stage of Story 1.5 (AD-9, AD-31; the "Problems" clause of the sending):
///   - TestEmitStepsFails: steps whose sends fail (the messages are invalid, so the send fails in the validation of the message and sends
///     nothing, whatever the production is doing) give one warning for each, which names the DecisionRef, the step and the codes of the
///     error and holds nothing of the content that the status echoes (a password and a Bearer token), not even redacted; EmitSteps raises
///     nothing, and OnResponse still answers the turn and records its row.
/// Added by Story 1.6 (AD-8, AD-20, AD-26, AD-28, AD-30, AD-31; DW-76):
///   - TestReplyCheck and TestFilterBlanks now pin that a reply which fails its check, and a reply which the filter leaves nothing of, are
///     recorded as fallbacks with the reason invalid, and no longer end with an error status;
///   - TestConcludeFallbacks: Conclude of a refusal, a cut-off, an empty and an unusable turn, a reply that fails its check, a filter that
///     leaves nothing, a failure text and no Reply at all gives status OK and one row with Fallback true, the reason and no reasons,
///     confidence or payload; one decision.recorded after the save; a decide or diagnose gets the DecisionResponse of the row, and a turn
///     gets a new Reply that holds no text, host data, steps, failure text or finish reason (the refused text is in no field of it) but
///     the DecisionRef, the totals and the runner's Tainted;
///   - TestOnErrorFallback: OnError keeps the runner's error status for the key reply and returns OK, and OnResponse then records an
///     error fallback (or the reason of the status text); another key keeps its status; a failure Reply is classified by its FailureText;
///   - TestFallbackRace: a fallback for an item that has a row, or that another call saves first, answers with that row and fires nothing;
///   - TestMarkCappedWiring: RecordFallback with daily_cap fires decision.recorded and then budget.capped (the row and the mark in place,
///     outside any transaction), a second item fires decision.recorded only, any other reason no budget.capped, and the failing sink is
///     a warning; Conclude with the gateway's 403 marks the day too;
///   - TestPrecheckLogs: Precheck logs one warning for each fault that Budget.State names, naming it and redacted, and one for a
///     DecisionTokenBudget that is not a whole number of 0 or more, which counts as 0;
///   - TestPrecheckOrder (QA): Precheck with the real facts, in every combination of a missing key (the ProviderConfig of TriageAgent), a day
///     that is capped (the mark), an estimate over the budget and an estimate over the request-size limit, gives no_key before daily_cap
///     before budget before too_large; and a cap reached by the gateway's spend, not by the mark, is daily_cap before budget too;
///   - TestEstimateTokens: a budget is over only above the estimate, and 0 is off (what the estimate counts: Story 1.9, below);
///   - TestOnRequestPrecheck: OnRequest records a request that fails a precheck as a fallback and answers it from OnRequest, with the
///     settings checked first;
///   - TestStepsBeforeReplyClass: OnResponse handles the steps of the reply before it reads the runner's ReplyClass, so a reply whose
///     ReplyClass cannot be read still has its steps handled before the error.
/// Added by Story 1.7 (AD-5, AD-6, AD-8, AD-9, AD-20, DW-56):
///   - TestBadSettings and TestOnRequestUsesItsSettings: the shortest timer is 12 (11 and 1 are refused, 12 and 110 pass);
///   - TestOnResponseUsesItsSettings: the timer's key is no longer an error: it records a timeout fallback for the DecisionRef of the process
///     and answers the caller;
///   - TestTimerFallback: OnResponse for the key timer, for a decide and for a turn, with no re-send and with one: a row with the process's
///     DecisionRef and session, timeout and then rate_limited, a DecisionResponse or a fallback Reply that sets no runner flag, the totals of the
///     Usage rows and the steps of the earlier attempts, a duration from the start of the process, and one decision.recorded;
///   - TestResendDelay: ResendDelay is pure: 1, 2, 4 and 8 seconds of back-off (RESENDFIRST doubled up to RESENDMAX), cut so that the last
///     re-send keeps a second before the timer, and 0 for every reason but rate_limited, a tool that ran and less than 2 seconds left;
///   - TestResendPrecheck: OnResponse for the key resend prechecks the request again: no_key, budget and daily_cap are recorded as fallbacks
///     with nothing sent (the day is marked capped), and so is a timer with less than a second left, which records rate_limited;
///   - TestResendWiring: OnResponse wires the re-send, with the timers and sends of the process recorded (Test.Bridge.ZzDecide): the back-off
///     timer and the steps added to StepCount for a rate limit, the timer left out when under 2 s remain, and the clone, the runner, the
///     counter and the timer of the key resend;
///   - TestStepMessages and TestEmitStepsFails: the Positions start after the steps already sent (offset, StepsSent), also for a second
///     EmitSteps of the same decision;
///   - TestConcludeFallbacks and TestOnErrorFallback: a fallback Reply carries the runner's ToolsRun as it carries Tainted, and a rate limit
///     after a tool ran falls back at once;
///   - TestResendBoundary: the key resend sends with 1.8 s of the timer left, with a timer of 1 s, and records rate_limited at once with 0.5 s left;
///   - TestStepPositionsAcrossResends: the steps of a rate-limited reply are sent before the back-off, numbered after those already sent, and
///     StepsSent and StepCount count them; a record that is no object keeps its slot, its warning names its Position, and no Position repeats;
///   - TestStepsAcrossAttempts: the row and the answer hold the steps of the earlier attempts (StepCount) plus the last reply's, the sums of the
///     Usage rows of the ref and a duration from the start of the process, for a usable turn, a fallback after a tool ran and a decide request.
/// Added by Story 1.8 (AD-6, AD-8, AD-20, AD-30):
///   - TestBusyRelayed: OnResponse answers a runner Reply whose Busy is 1 with a new Reply from NewBusy (Busy 1 and nothing else, status OK), with
///     no row, no event and no state kept; OnRequest answers a user's turn whose conversation lock another process holds with the same Busy after
///     the lock's 2 seconds, before the DecisionRef, the precheck, a row or a send, while an untrusted turn of the same owner, and a decide or
///     diagnose request, are never probed; Held is 0 once the lock is free;
///   - TestSessionBroken: Broken (pure) is 1 for a user's turn whose failure text holds "Invalid input" in any case, and 0 for an untrusted turn, a
///     decide, a diagnose request and any other text; Conclude and OnResponse answer such a user's turn with an error fallback Reply whose
///     SessionBroken is 1, and the untrusted turn and the decide with the same text with the reason error and no SessionBroken;
///   - TestFallbackMovesNothing (Story 17.8): RecordFallback carries the runner's Tainted and ToolsRun, sets neither when there is no runner reply, always
///     answers SessionRotated 0 and moves no link, whatever the runner's reply says, and sets SessionBroken only when told; a usable answer is a clone that
///     keeps the other flags and carries the SessionRotated of Decide, not the runner's;
///   - TestAdmitSessionMode: Admit accepts a SessionMode of "", continue and fresh, for a turn and for the other kinds, and refuses any other
///     value, Fresh and a trailing space included, with an error that names SessionMode;
///   - TestConcludeFallbacks and AssertFallback: a fallback Reply carries SessionRotated 0 (a reply with SessionRotated 1 is not carried), and
///     carries SessionBroken and Busy as the case says.
/// Added by Story 17.8 (AD-6, AD-8: only Decide moves a conversation's link; DW-726, DW-729, DW-730):
///   - TestPointLink: PointLink moves the link by the compare-and-set for an accepted fresh turn, an accepted continue turn (no move in place, a move to a
///     fork or a retry's session), the first link, and moves nothing for a tainted reply, a reply that names no session, an unlinked request, a lost
///     compare-and-set (one warning) and a Point that fails (one warning), with SessionRotated as the Always rule gives it;
///   - TestConcludeAccepts: a usable reply moves the link through Conclude and through OnResponse of the recorder, a refused one and a late one do not, and
///     the answer carries no session field;
///   - TestRetryWiring (extended): the retry of a linked continue turn is a fresh turn whose SeedText is the recap of the first HistoryCount stored
///     messages, and a fresh turn keeps its own SeedText.
/// Added by Story 1.9 (AD-6, AD-8, AD-19, AD-20, NFR-3):
///   - TestEstimateTokens: RequestSize.AgentChars of Triage and Chat is the system prompt of the live agent, of Diagnosis that and the JSON of the
///     Watch toolset's tools, and 0 with an error status for a class that does not exist; the estimate of a decide, a diagnose, an untrusted turn, a
///     user turn with no link and a user fresh turn with a seed and a note is the agent part plus the input that Chat gets, with the seed counted
///     only on the user fresh turn; a linked turn that continues also counts the stored history of its session, which RequestSize.HistoryChars reads
///     without the session being opened, and an untrusted, a fresh and a decide request of the same owner count none; a budget is over only above the
///     estimate;
///   - TestPrecheckOrder: also pins too_large after budget, the estimate that Precheck gives back, and Classify's order for the fact tooLarge;
///   - TestRequestLimitSetting: RequestTokenLimit is a host setting of Decide with the initial value 100000, and its limit is 100000 for an empty value,
///     the whole number from 1 to 100000 that is given, and 100000 with one warning that names the setting for 0, a negative number, text and a number
///     above 100000, so it is never off and never above 100000;
///   - TestOnRequestPrecheck and TestResendPrecheck: a decide, a user turn and a re-send whose estimate is above the limit record a too_large fallback
///     and send nothing, no runner request and no timer;
///   - TestCompactFlag: the request that Decide sends carries Compact 1 exactly for a turn estimated above 40,000 tokens (a user turn and an untrusted
///     turn, any SessionMode), also on the re-send, and 0 for a turn at 40,000, a decide, a diagnose and a turn whose caller set the flag;
///   - Added by Story 30.1 (AD-6, AD-8, AD-20): TestTimerFor (the timer of a flagged turn that continues its conversation is TimerSeconds plus 20, at most
///     110, in OnRequest and the re-send; every other request keeps TimerSeconds), TestFlaggedBound (a flagged turn that continues is judged too_large on
///     the characters the runner will send after compaction, the stored history counted as the least of itself and 80,000) and TestRequestLimit (the
///     shared normalization of RequestTokenLimit);
///   - TestResendTooLargeSendsNothing: the key resend of a decide and of a user turn whose estimate is above the limit sends no request and sets no timer
///     (the recorder shows it), leaves Resends at 0 and records a too_large fallback with one decision.recorded; at the limit it sends;
///   - TestRequestLimitThroughOnRequest: the limit that OnRequest and the key resend apply is the one the setting row gives (an empty row, 5000 and the
///     invalid 0, -1, abc, 1.5 and 100001 as 100000 with one warning that names RequestTokenLimit), so a decide one token above it sends nothing.
/// Added by Story 17.2 (AD-6, AD-8, DW-647, DW-650; lead rulings U-281 and U-282), with the recorder (Test.Bridge.ZzDecide) for the second-model retry:
///   - TestToolsReadOnlyMcp (Story 22.8, DW-724): ToolsReadOnly also asks the McpServersClass setting (here the fixture Test.Bridge.ZzReadOnlyServers, put in the stored
///     configuration of Decide and put back) for each server it lists: all of them read-only is 1, one that is not 0, a list that errors, throws or is no array is 0, an
///     entry with no server name is 0, a ToolsReadOnly that throws is 0, a class that is not usable is 0, no server leaves the answer as it was, and a runner whose tools
///     are not read-only stays 0;
///   - TestRetryAfterTimerMcp (QA, AC 4 through the timer): with the real ToolsReadOnly, a decide whose timer fired is retried while the one listed server says read-only, and falls back
///     with timeout, sending nothing, when that server says otherwise or throws;
///   - TestRetryable, TestRetrySeconds, TestToolsReadOnly, TestToolsetsReadOnly: the pure rules: which reasons are retried, T2 = min(timer, 110 - T1) and 0
///     under 12, and the read-only tools of an agent, each clause of that rule on its own toolset (Test.Bridge.ZzReadOnly*); a timed-out turn is not retried (R2);
///   - TestHeldRetryOf (DW-650 a, b, c, d) and TestSentRequestRetryOf: a retry skips the conversation-lock probe only for the same runner and ItemId; a RetryOf
///     that a client sets skips nothing and is cleared on every send and re-send;
///   - TestRetryWiring: the retry's request, timer and answer; one row, the Model of the reply that answered, the sums of both attempts, the retry's own reason
///     on a second failure, and no re-send after the retry's rate limit;
///   - TestRetryAfterResendRanOut: a key resend with no time left sends the retry instead of recording rate_limited;
///   - TestRetryNeverCases, TestRetryNoSecondModel, TestRetryAfterTimer, TestRetrySkipped, TestRetryBadItem, TestRetryNoKey, TestRetryEstimate: what is never
///     retried, release 1's fallback with no second model, the timer that fired, no time left, a RetryItem that is not usable, a missing key, and the estimate.
/// The System Default Settings rows that the tests put in place are put back by OnAfterOneTest, and so is today's day mark.
/// Every test removes the Usage rows it made, and the AI sessions it saved with the links that name them. The base class, OcuTalon.Test.Bridge.ZoneCase,
/// puts the process zone back after every test.
Class OcuTalon.Test.Bridge.Decide Extends OcuTalon.Test.Bridge.ZoneCase
{

/// A usable reply of Triage's default script.
Parameter DIGEST = "{""outcome"":""digest"",""reasons"":[""The CI mock keeps this item for the digest.""],""confidence"":0.5}";

Parameter FILTER = "OcuTalon.Test.Bridge.ProbeFilter";

Parameter SINK = "OcuTalon.Test.Bridge.ProbeSink";

Parameter REPLYCLASS = "OcuTalon.Bridge.Msg.DecisionPayload";

/// The failure texts that AI Hub raised on build 154 (Story 1.6, Task 0; the same as in Test.Bridge.Fallback).
Parameter DAILYCAP = "ERROR <%AICore>ProviderError: Provider 'anthropic' error: API error: Authentication failed: daily cost cap reached";

Parameter OVERLOADED = "ERROR <%AICore>ProviderError: Provider 'anthropic' error: Rate limit exceeded: CI mock: overloaded.";

Parameter LOOP = "ERROR <%AICore>LoopDetected: Agentic loop stalled: no new evidence from tool results after 4 assessment(s)";

Parameter MAXITERATIONS = "ERROR <%AICore>MaxIterationsReached: Max iterations (4) reached without a final response";

/// The failure text of a conversation history that the provider rejects, as AI Hub raised it on build 154 (Story 1.8, Task 0 (c): the scenario
/// invalid-input answers HTTP 400).
Parameter INVALIDINPUT = "ERROR <%AICore>ProviderError: Provider 'anthropic' error: Invalid input: CI mock: messages: the stored conversation is not valid input.";

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

/// The DecisionRefs of the Usage rows that the test made.
Property UsageRefs As %List;

/// The values (DecisionRefs and fake secrets) whose event-log rows the test wrote or provoked, to be deleted again.
Property LogNeedles As %List;

/// The System Default Settings rows before the test touched them (Test.Agent.RunnerFixture.SnapshotDefault), to be put back.
Property SavedRows As %List;

/// 1 when the test may have set the mark of today's day, which OnAfterOneTest removes.
Property DayMarked As %Boolean [ InitialExpression = 0 ];

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark): OnAfterOneTest deletes the sessions saved after it and the links that
/// name them.
Property SessionMark As %Integer;

/// 1 after UseNoServers put Decide's McpServersClass to the fixture; OnAfterOneTest then puts SavedServers back.
Property ServersSwapped As %Boolean [ InitialExpression = 0 ];

/// The McpServersClass value of Decide before UseNoServers changed it.
Property SavedServers As %String(MAXLEN = "");

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Do ..RemoveToolRows()
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Set position = 0
	While $ListNext(..UsageRefs, position, ref) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ?", ref)
	}
	Set ..UsageRefs = ""
	Set position = 0
	While $ListNext(..LogNeedles, position, needle) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE Text [ ?", needle)
	}
	Set ..LogNeedles = ""
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..SavedRows)
	Set ..SavedRows = ""
	If ..ServersSwapped {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Gate).StoreDecideSetting("McpServersClass", ..SavedServers), "McpServersClass is put back")
		Set ..ServersSwapped = 0
		Set ..SavedServers = ""
	}
	If ..DayMarked {
		Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
		Set ..DayMarked = 0
	}
	Kill ^||ZzProbeFilter, ^||ZzProbeSink
	Quit sc
}

/// Admit: a message of another class gives 5003; a kind, provenance, ItemId, OwnerRef or Input that is missing or unknown gives an
/// error that names the field; a usable request is admitted. A request of kind tool needs provenance user and a Ref as its ItemId, and
/// no Input.
Method TestRefusedRequests()
{
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Admit(##class(Ens.StringRequest).%New("x"))
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "a message of another class gets 5003")
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Admit("")
	Do $$$AssertEquals($SYSTEM.Status.GetErrorCodes(sc), 5003, "so does no message at all")
	Set tool = ..NewToolRequest(##class(OcuTalon.Bridge.Ids).NewRef())
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.Decide).Admit(tool), "a tool request of provenance user with a Ref as its ItemId and no Input is admitted")
	Set tool.Provenance = "untrusted"
	Do ..AssertNamed(tool, "Provenance", "a tool request of untrusted provenance")
	Set tool = ..NewToolRequest("not-a-ref")
	Do ..AssertNamed(tool, "ItemId", "a tool request whose ItemId is no Ref")
	Set tool = ..NewToolRequest(##class(OcuTalon.Bridge.Ids).NewRef())
	Set tool.OwnerRef = ""
	Do ..AssertNamed(tool, "OwnerRef", "a tool request with no OwnerRef")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.Decide).Admit(..NewRequest("decide")), "a decide request is admitted")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.Decide).Admit(..NewRequest("turn", "user")), "and so is a user's turn")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.Decide).Admit(..NewRequest("diagnose")), "and a diagnose request")

	Set request = ..NewRequest("zz")
	Do ..AssertNamed(request, "Kind", "a kind outside REQUESTKIND")
	Set request = ..NewRequest("decide", "zz")
	Do ..AssertNamed(request, "Provenance", "a provenance outside PROVENANCE")
	Set request = ..NewRequest("decide")
	Set request.ItemId = ""
	Do ..AssertNamed(request, "ItemId", "an empty ItemId")
	Set request = ..NewRequest("decide")
	Set request.OwnerRef = ""
	Do ..AssertNamed(request, "OwnerRef", "an empty OwnerRef")
	Set request = ..NewRequest("decide")
	Set request.Input = " "_$Char(9, 10, 13)_" "
	Do ..AssertNamed(request, "Input", "an Input of white space only")
	Set request.Input = ""
	Do ..AssertNamed(request, "Input", "an empty Input")
}

/// Story 30.3, rows 4a and 9: the tool request (the replay of an approved call) in Decide, with the recorder (Test.Bridge.ZzDecide) for the sends and
/// the timers and the probe sink for the events. Fixture approval rows are saved and deleted by the test.
///   - A tool_call row that names the runner ZzRunner: the request goes to ZzRunner with the key reply, once, and one timer; no precheck runs (a
///     request limit of one token and a decision budget of one would otherwise record a fallback), no ReplyClass is read and no probe is made.
///   - A reply with no FailureText records one Decision row of kind tool, the outcome act, no reasons and no fallback, fires decision.recorded and
///     answers a Reply (DecisionRef, Outcome act, no text); the same request again is answered from the row and sends nothing.
///   - A reply with a FailureText (also one that reads like a rate limit, which is not sent again although the timer leaves time for a re-send, and
///     one that reads like the daily cap, which does not mark the day) records a fallback with the reason error and answers a Reply with Fallback 1.
///   - A row with no runner: the approved row is closed failed through FinishExecution (approval.result fires), and the answer is a fallback with
///     the reason error, recorded like any fallback, with no send. A missing row and a fix row are answered the same way and are not changed.
Method TestToolRequest()
{
	Set class = "OcuTalon.Bridge.Process.Decide"
	Kill ^||ZzDecideCalls, ^||ZzProbeSink
	Set ref = ..ToolRow("zz_replay_send", "ZzRunner", "approved")
	Set recorder = ..ToolRecorder()
	Set recorder.DecisionTokenBudget = 1
	Set recorder.RequestTokenLimit = 1
	Set request = ..NewToolRequest(ref)
	Do $$$AssertEquals($ClassMethod(class, "RunnerFor", "tool", request), "ZzRunner", "RunnerFor gives the Runner of the row for kind tool")
	Set sc = recorder.OnRequest(request, .response)
	Do $$$AssertStatusOK(sc, "OnRequest takes the tool request")
	Do $$$AssertEquals(response, "", "it does not answer yet")
	Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer"), "1|1", "one send and one timer")
	Do $$$AssertEquals($ListGet($Get(^||ZzDecideCalls("send", 1)), 1)_"|"_$ListGet($Get(^||ZzDecideCalls("send", 1)), 4)_"|"_$ListGet($Get(^||ZzDecideCalls("send", 1)), 5), "ZzRunner|reply|"_ref, "the send goes to the row's Runner with the key reply, for the Ref")
	Do $$$AssertEquals($ListGet($Get(^||ZzDecideCalls("send", 1)), 7), 0, "its Compact flag is 0")
	Do $$$AssertEquals(..Rows(ref), 0, "no precheck recorded a fallback, though the limits are one token")
	Do $$$AssertEquals(..SinkTypes(), "", "and no event fired")

	Set callRequest = request.%ConstructClone()
	Set callRequest.DecisionRef = recorder.DecisionRef
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.ToolsRun = 1
	Set sc = recorder.OnResponse(request, .response, callRequest, reply, "reply")
	Do $$$AssertStatusOK(sc, "OnResponse takes the runner's reply")
	Set row = ..RowOf(ref, "tool")
	Do $$$AssertTrue($IsObject(row), "a Decision row of kind tool records it")
	If $IsObject(row) Do $$$AssertEquals(row.Outcome_"|"_row.Fallback_"|"_row.Reasons_"|"_row.Payload_"|"_row.ItemId, "act|0|||"_ref, "with the outcome act, no fallback, no reasons and no payload")
	Do $$$AssertEquals(..SinkTypes(), "decision.recorded", "decision.recorded is fired")
	Do $$$AssertTrue($IsObject(response) && response.%IsA("OcuTalon.Bridge.Msg.Reply"), "the answer is a Reply")
	If $IsObject(response) && $IsObject(row) Do $$$AssertEquals(response.DecisionRef_"|"_response.Outcome_"|"_response.Fallback_"|"_response.Text_"|"_response.FailureText_"|"_response.Steps, row.Ref_"|act|0|||", "of the row, with no text, failure text or steps")

	Kill ^||ZzDecideCalls, ^||ZzProbeSink
	Set again = ..ToolRecorder()
	Set sc = again.OnRequest(request, .answered)
	Do $$$AssertStatusOK(sc, "the same request again is answered")
	Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer")_"|"_..SinkTypes(), "0|0|", "from the row: nothing is sent, no timer is set and no event fires")
	If $IsObject(answered) && $IsObject(row) Do $$$AssertEquals(answered.DecisionRef_"|"_answered.Outcome, row.Ref_"|act", "with the recorded row's Reply")
	Do $$$AssertEquals(..Rows(ref), 1, "and there is still one row")

	// a failure reply is a fallback with the reason error, and is never sent again
	For failure = "ZZ tool failure", $Parameter(class, "RATELIMITTEXT"), $Parameter(class, "DAILYCAPTEXT") {
		Set one = ..ToolRow("zz_replay_throw", "ZzRunner", "failed")
		Set requestOne = ..NewToolRequest(one)
		Kill ^||ZzDecideCalls, ^||ZzProbeSink
		Set processOne = ..ToolRecorder()
		Set processOne.%TimeCreated = ..Ago(3)
		Do $$$AssertStatusOK(processOne.OnRequest(requestOne, .nothing), "(failure '"_failure_"') the request is sent")
		Set callOne = requestOne.%ConstructClone()
		Set callOne.DecisionRef = processOne.DecisionRef
		Set failed = ##class(OcuTalon.Bridge.Msg.Reply).%New()
		Set failed.FailureText = failure
		Set failed.ToolsRun = 0
		Do $$$AssertStatusOK(processOne.OnResponse(requestOne, .out, callOne, failed, "reply"), "(failure '"_failure_"') OnResponse takes the failure reply")
		Set rowOne = ..RowOf(one, "tool")
		If $IsObject(rowOne) Do $$$AssertEquals(rowOne.Fallback_"|"_rowOne.FallbackReason_"|"_rowOne.Outcome, "1|error|tellnow", "(failure '"_failure_"') a fallback with the reason error")
		Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer"), "1|1", "(failure '"_failure_"') nothing was sent again and no resend timer was set")
		If $IsObject(out) Do $$$AssertEquals(out.Fallback_"|"_out.FallbackReason, "1|error", "(failure '"_failure_"') and the answer says so")
	}
	Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))), 0, "a tool's own error text did not mark the day as capped")

	// a failure while the row is still approved: the run never started, so no Decision row stands in the way of a later replay
	Set unstarted = ..ToolRow("zz_replay_send", "ZzRunner", "approved")
	Set requestUnstarted = ..NewToolRequest(unstarted)
	Kill ^||ZzDecideCalls, ^||ZzProbeSink
	Set processUnstarted = ..ToolRecorder()
	Do $$$AssertStatusOK(processUnstarted.OnRequest(requestUnstarted, .nothing), "(never started) the request is sent")
	Set callUnstarted = requestUnstarted.%ConstructClone()
	Set callUnstarted.DecisionRef = processUnstarted.DecisionRef
	Set refused = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set refused.FailureText = "ZZ the lock was not taken"
	Do $$$AssertStatusOK(processUnstarted.OnResponse(requestUnstarted, .refusal, callUnstarted, refused, "reply"), "(never started) OnResponse takes the refusal")
	Do $$$AssertEquals(..Rows(unstarted), 0, "(never started) no Decision row is recorded")
	Do $$$AssertEquals(..SinkTypes(), "", "(never started) and no event fires")
	Do $$$AssertTrue($IsObject(refusal) && (refusal.FailureText = "ZZ the lock was not taken"), "(never started) the answer is a Reply that holds the failure text")
	Kill ^||ZzDecideCalls
	Set again = ..ToolRecorder()
	Do $$$AssertStatusOK(again.OnRequest(requestUnstarted, .nothing), "(never started) the same request again is taken")
	Do $$$AssertEquals(..Calls("send"), 1, "(never started) and it is sent to the runner again")

	// row 9: no runner
	Set noRunner = ..ToolRow("zz_replay_send", "", "approved")
	Set missing = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set fix = ..ToolRow("", "", "approved", "fix")
	Set fixText = ..ToolRowText(fix)
	For target = noRunner, missing, fix {
		Kill ^||ZzDecideCalls, ^||ZzProbeSink
		Set ..ItemIds = ..ItemIds _ $ListBuild(target)
		Set label = $Select(target = noRunner: "(a) an approved tool_call with no Runner", target = missing: "(b) a Ref with no row", 1: "(b) a fix row")
		Set process = ..ToolRecorder()
		Set sc = process.OnRequest(..NewToolRequest(target), .fallback)
		Do $$$AssertStatusOK(sc, label_": OnRequest answers")
		Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer"), "0|0", label_": nothing is sent and no timer is set")
		If $IsObject(fallback) Do $$$AssertEquals(fallback.Fallback_"|"_fallback.FallbackReason, "1|error", label_": a fallback with the reason error")
		Set rowOf = ..RowOf(target, "tool")
		Do $$$AssertTrue($IsObject(rowOf), label_": recorded like any fallback")
	}
	Do $$$AssertEquals(..ToolRowState(noRunner), "failed|failed", "(a) the row is closed failed through FinishExecution")
	Do $$$AssertTrue(..SinkTypes() [ "decision.recorded", "and the decision was recorded")
	Do $$$AssertEquals(..ToolRowText(fix), fixText, "(b) the fix row is unchanged")
	Do ..RemoveToolRows()
}

/// Story 30.7, DW-470 (rows 14 to 16): the reason and the Reasons of the fallback Decision row of a failed replay. The failure text of the no-key case
/// is the one that Task 0 measured (the runner fails in BuildAgent, the call does not run, ToolsRun 0); so is the text of a provider object that cannot be
/// built (an unknown provider name; BuildAgent, ToolsRun 0), the endpoint that REPLAYPROVIDER names. An unreachable provider fails no replay (Task 0: the
/// replay makes no provider request, so the tool ran), so no sentence is made for it.
Method TestToolFailureReasons()
{
	Set class = "OcuTalon.Bridge.Process.Decide"
	Set sentence = $Parameter(class, "REPLAYNOKEY")
	Do $$$AssertEquals(sentence, "No model key is set, so the approved call did not run. Nothing was changed.", "the sentence is the agreed one")
	Do $$$AssertTrue(sentence '[ "ERROR", "and it holds no code, class name or status text")
	Set provider = $Parameter(class, "REPLAYPROVIDER")
	Do $$$AssertEquals(provider, "The model provider could not be reached, so the approved call did not run. Nothing was changed.", "the provider sentence is the agreed one (U-214)")
	Do $$$AssertTrue(provider '[ "ERROR", "and it holds no code, class name or status text")
	Set noProvider = "ERROR <%AICore>ProviderCreateFailed: Failed to create provider 'zznope'    > ERROR <%AICore>ProviderNotFound: LLM provider not found: zznope"
	Set noStore = "ERROR <%AICore>ProviderConfigError: PROVIDERCONFIG is invalid    > ERROR <%AICore>SettingLookupFailed: SettingStore lookup failed for @{config:zz.missing.key}"
	Set noKey = "ERROR <%AICore>ProviderConfigError: PROVIDERCONFIG is invalid    > ERROR <%AICore>InternalError: Internal AI-Core error: @{env:ZZ_UNSET_VARIABLE} has no value and no :-fallback was given"
	Set cases = $ListBuild(
		$ListBuild("no key, the call did not run", noKey, 0, 1, "1|no_key|" _ sentence),
		$ListBuild("no key text from a tool that ran", noKey, 1, 1, "1|error|"),
		$ListBuild("a tool's own error", "ZZ tool failure", 1, 1, "1|error|"),
		$ListBuild("a provider error that is not the no-key one", "Connection refused", 0, 1, "1|error|"),
		$ListBuild("the provider object cannot be built", noProvider, 0, 1, "1|error|" _ provider),
		$ListBuild("that text from a tool that ran", noProvider, 1, 1, "1|error|"),
		$ListBuild("a Config Store entry that is missing", noStore, 0, 1, "1|error|"),
		$ListBuild("a context failure before the call", "The bridge context could not begin", 0, 1, "1|error|"),
		$ListBuild("a runner error with the no-key text and no Reply at all", noKey, "", 0, "1|error|"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = "(" _ $List(case, 1) _ ")"
		Set ref = ..ToolRow("zz_replay_throw", "ZzRunner", "failed")
		Set request = ..NewToolRequest(ref)
		Kill ^||ZzDecideCalls, ^||ZzProbeSink
		Set process = ..ToolRecorder()
		Set process.%TimeCreated = ..Ago(3)
		Do $$$AssertStatusOK(process.OnRequest(request, .nothing), label _ " the request is sent")
		Set call = request.%ConstructClone()
		Set call.DecisionRef = process.DecisionRef
		Set reply = ""
		If $List(case, 4) {
			Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
			Set reply.FailureText = $List(case, 2)
			Set reply.ToolsRun = $List(case, 3)
		} Else {
			Set process.RunnerError = $SYSTEM.Status.Error(5001, $List(case, 2))
		}
		Do $$$AssertStatusOK(process.OnResponse(request, .out, call, reply, "reply"), label _ " OnResponse takes the reply")
		Set row = ..RowOf(ref, "tool")
		Do $$$AssertTrue($IsObject(row), label _ " a Decision row of kind tool records it")
		If $IsObject(row) Do $$$AssertEquals(row.Fallback _ "|" _ row.FallbackReason _ "|" _ row.Reasons, $List(case, 5), label _ " the fallback, its reason and its Reasons")
		If $IsObject(row) Do $$$AssertEquals(row.Outcome, "tellnow", label _ " with the outcome tellnow")
		If $IsObject(out) Do $$$AssertEquals(out.Fallback _ "|" _ out.FallbackReason, "1|" _ $Piece($List(case, 5), "|", 2), label _ " and the answer says the same reason")
		Do $$$AssertEquals(..Calls("send"), 1, label _ " nothing was sent again")
	}
	Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))), 0, "no failure marked the day as capped")
	Do ..RemoveToolRows()
}

/// Story 30.3, row 9 (owner decision U-170): an approved tool_call row that was held before ToolSource and Runner existed, with either one empty,
/// is closed failed and is never sent to a runner. The person sees the reason in the Reasons of the fallback Decision row: plain English, with no
/// class name, no `%`, no `#` or ERROR code and no status text. A row with both set is still sent, and an executing row with nothing set is not closed
/// and its fallback Decision row holds no reason.
Method TestToolRowHeldBeforeAnUpdate()
{
	Set class = "OcuTalon.Bridge.Process.Decide"
	Set expected = $Parameter(class, "HELDBEFOREUPDATE")
	Do $$$AssertTrue((expected [ "held before an update") && (expected [ "ask again"), "the reason says the request was held before an update and to ask again")
	Set noSource = ..ToolRow("zz_replay_send", "ZzRunner", "approved", "tool_call", "")
	Set noRunner = ..ToolRow("zz_replay_send", "", "approved", "tool_call", "OcuTalon.Test.Bridge.ZzReplayTool")
	Set neither = ..ToolRow("zz_replay_send", "", "approved", "tool_call", "")
	Set complete = ..ToolRow("zz_replay_send", "ZzRunner", "approved")
	Set running = ..ToolRow("zz_replay_send", "", "executing", "tool_call", "")
	For target = noSource, noRunner, neither, complete, running {
		Kill ^||ZzDecideCalls, ^||ZzProbeSink
		Set label = $Select(target = noSource: "(ToolSource empty)", target = noRunner: "(Runner empty)", target = neither: "(both empty)", target = running: "(executing, both empty)", 1: "(both set)")
		Set process = ..ToolRecorder()
		Set sc = process.OnRequest(..NewToolRequest(target), .answer)
		Do $$$AssertStatusOK(sc, label_" OnRequest answers")
		Set row = ..RowOf(target, "tool")
		If target = complete {
			Do $$$AssertEquals(..Calls("send"), 1, label_" the request is sent to the runner")
			Do $$$AssertEquals($Piece(..ToolRowState(target), "|", 1), "approved", label_" and the row is left approved")
			Continue
		}
		Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer"), "0|0", label_" no runner is sent the request, so the call runs 0 times, and no timer is set")
		If target = running {
			Do $$$AssertEquals($Piece(..ToolRowState(target), "|", 1), "executing", label_" a row that is not approved is left as it is")
			If $IsObject(row) Do $$$AssertEquals(row.Reasons, "", label_" and its fallback Decision row holds no reason")
			Continue
		}
		Do $$$AssertEquals(..ToolRowState(target), "failed|failed", label_" the row is failed")
		Do $$$AssertTrue($IsObject(answer) && (answer.Fallback = 1) && (answer.FallbackReason = "error"), label_" the answer is a fallback with the reason error")
		If $IsObject(answer) Do $$$AssertEquals(answer.Reasons, expected, label_" and Decide's answer, which the trace shows, carries the reason")
		Do $$$AssertTrue($IsObject(row), label_" a Decision row of kind tool records it")
		If '$IsObject(row) Continue
		Set reason = row.Reasons
		Do $$$AssertEquals(reason, expected, label_" the reason the person sees is the plain-English text")
		Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason_"|"_row.Payload, "1|error|", label_" a fallback with the reason error and no payload")
		For fragment = "OcuTalon", "%", "#", "ERROR", "Error", "<", "5001" {
			Do $$$AssertTrue(reason '[ fragment, label_" the reason holds no '"_fragment_"'")
		}
		// a repeat is answered from the row, and the row still holds the reason
		Kill ^||ZzDecideCalls
		Set repeat = ..ToolRecorder()
		Do $$$AssertStatusOK(repeat.OnRequest(..NewToolRequest(target), .again), label_" the same request again is answered")
		Do $$$AssertEquals(..Calls("send"), 0, label_" from the row, with no send")
		Do $$$AssertTrue($IsObject(again) && (again.Fallback = 1) && (again.FallbackReason = "error"), label_" with the same fallback")
		Do $$$AssertEquals(..RowOf(target, "tool").Reasons, expected, label_" and the row still holds the reason")
	}
	Do $$$AssertEquals(..Rows(complete), 0, "a row with both set records no Decision row at OnRequest")
	Do ..RemoveToolRows()
}

/// A request of kind tool for the Ref, as the approval hold sends it: provenance user, no Input.
Method NewToolRequest(ref As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "tool"
	Set request.Provenance = "user"
	Set request.ItemId = ref
	Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.Channel = "system"
	Set request.Summary = "zz_replay_send"
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Quit request
}

/// A Decide for the tool test: the recorder with the settings of a runner-less process, and the probe sink as its host sink.
Method ToolRecorder() As OcuTalon.Test.Bridge.ZzDecide [ Private ]
{
	Set recorder = ..NewRecorder()
	Set recorder.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set recorder.HostSinkClass = ..#SINK
	Set recorder.TimerSeconds = 60
	Set recorder.%SessionId = 4301
	Quit recorder
}

/// Saves an approval row in the state (a tool_call of the tool, the runner and the source, or a fix) with no hold, and tracks it for RemoveToolRows.
Method ToolRow(name As %String, runner As %String, state As %String, kind As %String = "tool_call", source As %String = "OcuTalon.Test.Bridge.ZzReplayTool") As %String [ Private ]
{
	Set row = ##class(OcuTalon.Test.Bridge.ApprovalRows).NewRow(kind, name, "{}", source, runner)
	Set sc = ##class(OcuTalon.Test.Bridge.ApprovalRows).Save(row, state, 3600, , .ref)
	If ref '= "" Set ^||ZzToolRows(ref) = ""
	Do $$$AssertStatusOK(sc, "the fixture "_kind_" row is saved, "_state)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Quit ref
}

/// "<State>|<Result>" of the approval row of the Ref.
ClassMethod ToolRowState(ref As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Quit $Select($IsObject(row): row.State_"|"_row.Result, 1: "<no row>")
}

/// The state, result and finish time of the approval row of the Ref, as one text.
ClassMethod ToolRowText(ref As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
	Quit $Select($IsObject(row): row.State_"|"_row.Result_"|"_row.FinishedAt_"|"_row.ToolName_"|"_row.Runner, 1: "<no row>")
}

/// Deletes the fixture approval rows of ToolRow.
ClassMethod RemoveToolRows() [ Private ]
{
	Set ref = ""
	For {
		Set ref = $Order(^||ZzToolRows(ref))
		Quit:ref=""
		Set row = ##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(ref)
		If $IsObject(row) Do ##class(OcuTalon.Bridge.Data.ApprovalRequest).%DeleteId(row.%Id())
	}
	Kill ^||ZzToolRows
}

/// CheckSettings names the setting: TimerSeconds outside 12 to 110 or not a whole number, a ReplyFilterClass that is missing or
/// does not extend its base, and a ReplyClass that is missing or is not a compiled JSON class. A turn needs no ReplyClass, and a
/// diagnose request whose DiagnosisAgent names none is refused.
Method TestBadSettings()
{
	Set filter = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set class = "OcuTalon.Bridge.Process.Decide"
	Do $$$AssertStatusOK($ClassMethod(class, "CheckSettings", "decide", "TriageAgent", ..#REPLYCLASS, filter, 60), "the default settings pass")
	Do $$$AssertStatusOK($ClassMethod(class, "CheckSettings", "decide", "TriageAgent", ..#REPLYCLASS, filter, 12), "a timer of 12 passes")
	Do $$$AssertStatusOK($ClassMethod(class, "CheckSettings", "decide", "TriageAgent", ..#REPLYCLASS, filter, 110), "and so does a timer of 110")
	Do $$$AssertStatusOK($ClassMethod(class, "CheckSettings", "turn", "ChatAgent", "", filter, 60), "a turn needs no ReplyClass")
	For timer = 0, 1, 11, 111, "x", "", "60.5", -1 {
		Set sc = $ClassMethod(class, "CheckSettings", "decide", "TriageAgent", ..#REPLYCLASS, filter, timer)
		Do $$$AssertStatusNotOK(sc, "a timer of '"_timer_"' is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "TimerSeconds", "and the error names TimerSeconds: "_$SYSTEM.Status.GetErrorText(sc))
	}
	For bad = "", "OcuTalon.Test.Bridge.ZzNoSuchFilter", "OcuTalon.Bridge.Ext.HostSink" {
		Set sc = $ClassMethod(class, "CheckSettings", "turn", "ChatAgent", "", bad, 60)
		Do $$$AssertStatusNotOK(sc, "a ReplyFilterClass of '"_bad_"' is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ReplyFilterClass", "and the error names ReplyFilterClass: "_$SYSTEM.Status.GetErrorText(sc))
	}
	For bad = "OcuTalon.Test.Bridge.ZzNoSuchReply", "OcuTalon.Bridge.Ext.ReplyFilter" {
		Set sc = $ClassMethod(class, "CheckSettings", "decide", "TriageAgent", bad, filter, 60)
		Do $$$AssertStatusNotOK(sc, "a ReplyClass of '"_bad_"' is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ReplyClass", "and the error names ReplyClass: "_$SYSTEM.Status.GetErrorText(sc))
	}
	Set sc = $ClassMethod(class, "CheckSettings", "diagnose", "DiagnosisAgent", "", filter, 60)
	Do $$$AssertStatusNotOK(sc, "a diagnose request is refused when DiagnosisAgent has no ReplyClass")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ "DiagnosisAgent") && (text [ "ReplyClass"), "and the error names DiagnosisAgent and ReplyClass: "_text)
	Do $$$AssertEquals($ClassMethod(class, "RunnerFor", "decide"), "TriageAgent", "decide goes to TriageAgent")
	Do $$$AssertEquals($ClassMethod(class, "RunnerFor", "diagnose"), "DiagnosisAgent", "diagnose goes to DiagnosisAgent")
	Do $$$AssertEquals($ClassMethod(class, "RunnerFor", "turn"), "ChatAgent", "and turn goes to ChatAgent")
}

/// CheckReply: one JSON object that DecisionPayload accepts passes, also inside one code fence; every other text fails with an
/// error that names the reply check. Conclude records nothing for a reply that fails.
Method TestReplyCheck()
{
	Set fence = $Char(96, 96, 96)
	Set good = ..#DIGEST
	Do ..AssertReply(good, 1, "valid JSON")
	Do ..AssertReply("  "_$Char(10)_good_$Char(13, 10), 1, "valid JSON in white space")
	Do ..AssertReply(fence_"json"_$Char(10)_good_$Char(10)_fence, 1, "valid JSON inside a json code fence")
	Do ..AssertReply(fence_$Char(13, 10)_good_$Char(13, 10)_fence, 1, "valid JSON inside a plain code fence")
	Do ..AssertReply("{""outcome"":""maybe"",""reasons"":[""r""],""confidence"":0.5}", 0, "an outcome that is not one of OUTCOME")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[],""confidence"":0.5}", 0, "no reason")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":["" "",""""],""confidence"":0.5}", 0, "only blank reasons")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[""r""]}", 0, "no confidence")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[""r""],""confidence"":1.5}", 0, "a confidence over 1")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[""r""],""confidence"":0.5,""extra"":1}", 0, "an extra field")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":""r"",""confidence"":0.5}", 0, "reasons that are a string")
	Do ..AssertReply("Not JSON at all.", 0, "text that is not JSON")
	Do ..AssertReply("[1,2]", 0, "a JSON array")
	Do ..AssertReply(good_" and more text", 0, "JSON followed by text")
	Do ..AssertReply(good_good, 0, "two objects")
	Do ..AssertReply("", 0, "an empty text")
	Do ..AssertReply("   ", 0, "a text of white space")
	Do ..AssertReply(fence_"json"_$Char(10)_good, 0, "a code fence that is not closed")
	Do ..AssertReply("{""reasons"":[""r""],""confidence"":0.5}", 0, "no outcome")
	Do ..AssertReply("{""outcome"":null,""reasons"":[""r""],""confidence"":0.5}", 0, "a null outcome")
	Do ..AssertReply("{""outcome"":""Ignore"",""reasons"":[""r""],""confidence"":0.5}", 0, "an outcome in the wrong case")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[""r""],""confidence"":null}", 0, "a null confidence")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[""r""],""confidence"":""high""}", 0, "a confidence that is a string")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[""r""],""confidence"":-0.1}", 0, "a negative confidence")
	Do ..AssertReply("{""outcome"":""ignore"",""reasons"":[""r""],""confidence"":0}", 1, "a confidence of 0")
	Do ..AssertReply("{""outcome"":""tellnow"",""reasons"":[""r"",""""],""confidence"":1}", 1, "a confidence of 1, and a blank reason beside a real one")

	Set request = ..NewRequest("decide")
	Set reply = ..NewReply("{""outcome"":""maybe"",""reasons"":[""r""],""confidence"":0.5}")
	Set sc = ..Conclude(request, reply, .response)
	Do $$$AssertStatusOK(sc, "Conclude records a reply that fails the check as a fallback")
	Do $$$AssertEquals(response.Outcome_"|"_response.Fallback_"|"_response.FallbackReason, "tellnow|1|invalid", "tellnow, Fallback and the reason invalid")
	Do $$$AssertEquals(response.Reasons_response.Confidence_response.Payload, "", "with no reasons, confidence or payload, so that the model's text is kept nowhere")
	Do $$$AssertEquals(..Rows(request.ItemId), 1, "and records one row")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason_"|"_row.Outcome, "1|invalid|tellnow", "that holds the same")
	Set request = ..NewRequest("decide")
	Set sc = ..Conclude(request, ..NewReply(good, "refusal"), .response)
	Do $$$AssertStatusOK(sc, "Conclude records a reply that the provider ended with a refusal as a fallback")
	Do $$$AssertEquals(response.Fallback_"|"_response.FallbackReason, "1|refusal", "with the reason refusal")
	Set request = ..NewRequest("decide")
	Set sc = ..Conclude(request, ..NewReply(good, "max_tokens"), .response)
	Do $$$AssertStatusOK(sc, "and one that it cut off at the output cap")
	Do $$$AssertEquals(response.Fallback_"|"_response.FallbackReason, "1|cut_off", "with the reason cut_off")
	Set request = ..NewRequest("turn", "user")
	Set sc = ..Conclude(request, ..NewReply(" "_$Char(10), "end_turn"), .response)
	Do $$$AssertStatusOK(sc, "Conclude records an empty turn reply as a fallback")
	Do $$$AssertEquals(response.Fallback_"|"_response.FallbackReason, "1|empty", "with the reason empty")
	Do $$$AssertEquals(..Rows(request.ItemId), 1, "and records one row for it")
	Set request = ..NewRequest("turn", "user")
	Set sc = ..Conclude(request, ..NewReply(" "_$Char(10)), .response)
	Do $$$AssertStatusOK(sc, "an empty turn reply with no finish reason is a fallback too")
	Do $$$AssertEquals(response.Fallback_"|"_response.FallbackReason, "1|unusable", "with the reason unusable")
}

/// The filter runs once on each model-written text: every reason of a decide reply, and a turn's text. It does not run on the
/// code-written line of the user rule. The row, the Payload and the response hold the filtered text.
Method TestFilter()
{
	Set json = "{""outcome"":""ignore"",""reasons"":[""First reason."",""Second reason.""],""confidence"":0.9}"
	Set request = ..NewRequest("decide")
	Set sc = ..Conclude(request, ..NewReply(json), .response, ..#FILTER)
	Do $$$AssertStatusOK(sc, "an untrusted decide reply is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeFilter), 2, "the filter ran once for each of the two reasons")
	Do $$$AssertEquals($Get(^||ZzProbeFilter(1)), "First reason.", "first on the first reason, as the model wrote it")
	Do $$$AssertEquals($Get(^||ZzProbeFilter(2)), "Second reason.", "then on the second")
	Set expected = "[f] First reason."_$Char(10)_"[f] Second reason."
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals(row.Reasons, expected, "the row holds the filtered reasons, one per line")
	Do $$$AssertEquals(response.Reasons, expected, "and so does the response")
	Do $$$AssertEquals(row.Payload, "{""outcome"":""ignore"",""reasons"":[""[f] First reason."",""[f] Second reason.""],""confidence"":0.9}", "and the Payload")
	Do $$$AssertEquals(response.Payload, row.Payload, "which the response repeats")

	Kill ^||ZzProbeFilter
	Set request = ..NewRequest("decide", "user")
	Set sc = ..Conclude(request, ..NewReply(json), .response, ..#FILTER)
	Do $$$AssertStatusOK(sc, "a user's decide reply is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeFilter), 2, "the filter ran for the two model reasons only, not for the code-written line")
	Do $$$AssertEquals(response.Outcome, "tellnow", "the outcome is tellnow")
	Do $$$AssertEquals(response.Reasons, ##class(OcuTalon.Bridge.Process.Decide).#USERANSWERED_$Char(10)_expected, "the code-written line comes first and is not filtered")

	Kill ^||ZzProbeFilter
	Set request = ..NewRequest("turn", "user")
	Set sc = ..Conclude(request, ..NewReply("Everything is fine."), .response, ..#FILTER)
	Do $$$AssertStatusOK(sc, "a turn reply is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeFilter), 1, "the filter ran once on the text of the turn")
	Do $$$AssertEquals($Get(^||ZzProbeFilter(1)), "Everything is fine.", "on the text as the model wrote it")
	Do $$$AssertEquals(response.Text, "[f] Everything is fine.", "and the answer holds the filtered text")
	Set row = ..RowOf(request.ItemId, "turn")
	Do $$$AssertEquals(row.Outcome, "tellnow", "the turn row is tellnow")
	Do $$$AssertEquals(row.Reasons_row.Confidence_row.Payload, "", "with no reasons, confidence or payload")
	Do $$$AssertEquals(response.DecisionRef, row.Ref, "and the answer carries its Ref")
	Do $$$AssertEquals(response.Outcome, "tellnow", "and the outcome tellnow")
}

/// decision.recorded: one call after the save with the request's OwnerRef and exactly {"ref":<Ref>}, outside any transaction and
/// with the row in place. An error status, an exception and a class that is no host sink are logged as a warning that names the
/// class and the Ref, and never fail Conclude; the row stands and the answer is given.
Method TestSink()
{
	Set request = ..NewRequest("decide")
	Set request.OwnerRef = "ZzOwner"
	Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response, , ..#SINK)
	Do $$$AssertStatusOK(sc, "the decision is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "the sink got one call")
	Set call = $Get(^||ZzProbeSink(1))
	Do $$$AssertEquals($List(call, 1), "decision.recorded", "of decision.recorded")
	Do $$$AssertEquals($List(call, 2), "ZzOwner", "with the OwnerRef of the request")
	Do $$$AssertEquals($List(call, 3), "{""ref"":"""_response.DecisionRef_"""}", "and exactly the Ref of the row as its payload")
	Do $$$AssertEquals($List(call, 4), 0, "outside any transaction")
	Do $$$AssertEquals($List(call, 5), 1, "with the row already saved")

	For mode = "error", "throw" {
		Kill ^||ZzProbeSink
		Set ^||ZzProbeSink("mode") = mode
		Set request = ..NewRequest("decide")
		Set mark = ..LogMark()
		Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response, , ..#SINK)
		Do $$$AssertStatusOK(sc, "in "_mode_" mode the decision is recorded and Conclude is OK")
		Do $$$AssertTrue($IsObject(response) && (response.DecisionRef '= ""), "the answer is given")
		Do $$$AssertEquals(..Rows(request.ItemId), 1, "and the row stands")
		Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "the sink was called once")
		Do ..AssertWarning(mark, ..#SINK, response.DecisionRef, mode)
	}
	For bad = "%Library.String", "OcuTalon.Test.Bridge.ZzNoSuchSink", "OcuTalon.Test.Bridge.ProbeNotASink" {
		Kill ^||ZzProbeSink
		Set request = ..NewRequest("decide")
		Set mark = ..LogMark()
		Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response, , bad)
		Do $$$AssertStatusOK(sc, "with the sink class "_bad_" the decision is recorded and Conclude is OK")
		Do $$$AssertEquals(..Rows(request.ItemId), 1, "and the row stands")
		Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "no event is sent")
		Do ..AssertWarning(mark, bad, response.DecisionRef, "bad class "_bad)
	}
}

/// A row that another call saved first for the item and kind answers, with no second row and no event. The row of a turn has no
/// reply text, so a second turn is refused with an error that names the item and the Ref.
Method TestConcurrentSave()
{
	Kill ^||ZzProbeSink
	Set request = ..NewRequest("decide")
	Set first = ##class(OcuTalon.Bridge.Data.Decision).%New()
	Set first.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set first.Kind = "decide"
	Set first.ItemId = request.ItemId
	Set first.OwnerRef = "instance"
	Set first.Outcome = "act"
	Set first.Reasons = "The first call won."
	Set first.Confidence = 0.31
	Set first.Payload = "{""outcome"":""act""}"
	Do $$$AssertStatusOK(first.%Save(), "another call saved its row first")
	Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response, , ..#SINK)
	Do $$$AssertStatusOK(sc, "Conclude answers")
	Do $$$AssertEquals(response.DecisionRef, first.Ref, "with the row that exists")
	Do $$$AssertEquals(response.Outcome_"|"_response.Reasons_"|"_response.Confidence, "act|The first call won.|.31", "and its outcome, reasons and confidence")
	Do $$$AssertEquals(..Rows(request.ItemId), 1, "no second row is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and no event is sent")

	Set request = ..NewRequest("turn", "user")
	Set row = ##class(OcuTalon.Bridge.Data.Decision).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Kind = "turn"
	Set row.ItemId = request.ItemId
	Set row.OwnerRef = "instance"
	Set row.Outcome = "tellnow"
	Do $$$AssertStatusOK(row.%Save(), "a turn row exists")
	Set sc = ..Conclude(request, ..NewReply("A second answer."), .response, , ..#SINK)
	Do $$$AssertStatusNotOK(sc, "a second turn is refused")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ request.ItemId) && (text [ row.Ref), "with an error that names the item and the Ref: "_text)
	Do $$$AssertEquals(response, "", "and gives no answer")
	Do $$$AssertEquals(..Rows(request.ItemId), 1, "no second row is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and no event is sent")
}

/// The user rule: for a decide request with provenance user, ignore and digest become tellnow, the first reason line is the code-
/// written sentence, and the Payload keeps the model's own outcome. A user's act and tellnow, and every outcome of an untrusted
/// item, stay as the model gave them. Row and answer agree.
Method TestUserRule()
{
	Set sentence = ##class(OcuTalon.Bridge.Process.Decide).#USERANSWERED
	Set reason = "The CI mock gives its reason."
	For provenance = "user", "untrusted" {
		For outcome = "ignore", "digest", "tellnow", "act" {
			Set request = ..NewRequest("decide", provenance)
			Set json = "{""outcome"":"""_outcome_""",""reasons"":["""_reason_"""],""confidence"":0.4}"
			Set sc = ..Conclude(request, ..NewReply(json), .response)
			Set label = provenance_" "_outcome
			Do $$$AssertStatusOK(sc, label_" is recorded")
			Set row = ..RowOf(request.ItemId, "decide")
			Set changed = (provenance = "user") && ((outcome = "ignore") || (outcome = "digest"))
			Set expectedOutcome = $Select(changed: "tellnow", 1: outcome)
			Set expectedReasons = $Select(changed: sentence_$Char(10), 1: "")_reason
			Do $$$AssertEquals(row.Outcome, expectedOutcome, label_": the row holds "_expectedOutcome)
			Do $$$AssertEquals(response.Outcome, expectedOutcome, label_": and so does the answer")
			Do $$$AssertEquals(row.Reasons, expectedReasons, label_": the reasons "_$Select(changed: "start with the code-written line", 1: "are the model's"))
			Do $$$AssertEquals(response.Reasons, expectedReasons, label_": in the answer too")
			Do $$$AssertTrue(row.Payload [ ("""outcome"":"""_outcome_""""), label_": the Payload keeps the model's own outcome")
			Do $$$AssertEquals(row.Confidence, .4, label_": the confidence is the model's")
		}
	}
	Set request = ..NewRequest("turn", "user")
	Do $$$AssertStatusOK(..Conclude(request, ..NewReply("A turn."), .response), "a user's turn is recorded")
	Do $$$AssertEquals(..RowOf(request.ItemId, "turn").Reasons, "", "and the user rule adds no line to its row")
	For outcome = "ignore", "digest" {
		Set request = ..NewRequest("diagnose", "user")
		Set json = "{""outcome"":"""_outcome_""",""reasons"":["""_reason_"""],""confidence"":0.4}"
		Set sc = ..Conclude(request, ..NewReply(json), .response)
		Do $$$AssertStatusOK(sc, "a user's diagnose reply of "_outcome_" is recorded")
		Set row = ..RowOf(request.ItemId, "diagnose")
		If '$IsObject(row) || '$IsObject(response) {
			Do $$$AssertTrue(0, "a user's diagnose reply of "_outcome_" is recorded and answered")
			Continue
		}
		Do $$$AssertEquals(row.Outcome_"|"_response.Outcome, outcome_"|"_outcome, "the user rule is for decide requests only: a user's diagnose request keeps "_outcome)
		Do $$$AssertEquals(row.Reasons_"|"_response.Reasons, reason_"|"_reason, "and has no code-written line")
	}
}

/// The confidence is recorded rounded to two decimals, in the row and in the answer, and never changes the outcome: 0.12 stays
/// 0.12, 0.123 becomes 0.12, 0 and 1 stay, and a confidence of 0.12 still acts.
Method TestConfidence()
{
	For confidence = "0.12", "0.123", "0.125", "0", "1" {
		Set request = ..NewRequest("decide")
		Set json = "{""outcome"":""act"",""reasons"":[""r""],""confidence"":"_confidence_"}"
		Set sc = ..Conclude(request, ..NewReply(json), .response)
		Do $$$AssertStatusOK(sc, "a confidence of "_confidence_" is recorded")
		Set expected = $Number(confidence, 2)
		Set row = ..RowOf(request.ItemId, "decide")
		Do $$$AssertEquals(row.Confidence, expected, "the row holds "_expected)
		Do $$$AssertEquals(response.Confidence, expected, "and so does the answer")
		Do $$$AssertEquals(row.Outcome_"|"_response.Outcome, "act|act", "and the outcome stays act")
	}
	Set request = ..NewRequest("decide")
	Do $$$AssertStatusOK(..Conclude(request, ..NewReply("{""outcome"":""act"",""reasons"":[""r""],""confidence"":0.123}"), .response), "0.123 is recorded")
	Do $$$AssertTrue(..RowOf(request.ItemId, "decide").Payload [ "0.123", "the Payload keeps the confidence the model gave")
}

/// ResponseFromRow gives a DecisionResponse with the row's values for a decide row, and refuses a turn row.
Method TestResponseFromRow()
{
	Set request = ..NewRequest("decide")
	Set request.Summary = "A summary line."
	Do $$$AssertStatusOK(..Conclude(request, ..NewReply(..#DIGEST), .made), "a decide reply is recorded")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals(row.Kind_"|"_row.ItemId_"|"_row.OwnerRef_"|"_row.Summary, "decide|"_request.ItemId_"|instance|A summary line.", "the row holds the Kind, ItemId, OwnerRef and Summary of the request")
	Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason, "0|", "and no fallback")
	Do $$$AssertTrue(row.RecordedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "RecordedAt is a UTC time: "_row.RecordedAt)
	Do $$$AssertEquals(row.TraceSessionId, 4242, "TraceSessionId is the session that Conclude was given")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.Decide).ResponseFromRow(row, .response), "the answer for the row is built")
	Do $$$AssertTrue($IsObject(response) && response.%IsA("OcuTalon.Bridge.Msg.DecisionResponse"), "a DecisionResponse")
	Do $$$AssertEquals(response.DecisionRef_"|"_response.Outcome_"|"_response.Reasons_"|"_response.Confidence_"|"_response.Fallback_"|"_response.FallbackReason, row.Ref_"|digest|The CI mock keeps this item for the digest.|.5|0|", "with the values of the row")
	Do $$$AssertEquals(response.Payload, ..#DIGEST, "and its Payload")
	Do $$$AssertEquals(response.DecisionRef, made.DecisionRef, "the answer is the one that Conclude gave")
	Do $$$AssertEquals(response.Payload, made.Payload, "with the same Payload")
	Do $$$AssertEquals(row.Ref ? 22(1AN,1"-",1"_"), 1, "the Ref is 22 characters")

	Set request = ..NewRequest("turn", "user")
	Do $$$AssertStatusOK(..Conclude(request, ..NewReply("Hello."), .made), "a turn is recorded")
	Set row = ..RowOf(request.ItemId, "turn")
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).ResponseFromRow(row, .response)
	Do $$$AssertStatusNotOK(sc, "a turn row gives no answer")
	Do $$$AssertTrue(($SYSTEM.Status.GetErrorText(sc) [ request.ItemId) && ($SYSTEM.Status.GetErrorText(sc) [ row.Ref), "and an error that names the item and the Ref")

	Set request = ..NewRequest("diagnose")
	Set ref = ..NewUsageRef()
	Do ..AddUsage(ref, "claude-haiku-5-5", 3800, 300, 2000, 600, .000365)
	Set reply = ..NewReply(..#DIGEST)
	Set reply.AgentStepCount = 3
	Do $$$AssertStatusOK(..ConcludeWith(request, ref, reply, 987, .made), "a diagnose reply with a Usage row is recorded")
	Set row = ..RowOf(request.ItemId, "diagnose")
	Do $$$AssertEquals(..Totals(row), "3800|300|2000|600|.000365|claude-haiku-5-5|3|987", "its row holds the totals")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.Decide).ResponseFromRow(row, .response), "the answer for the row is built")
	Do $$$AssertEquals(..Totals(response), "3800|300|2000|600|.000365|claude-haiku-5-5|3|987", "and carries the totals of the row")
	Do $$$AssertEquals(..Totals(made), ..Totals(response), "as the answer that Conclude gave does")
}

/// Story 19.4 (AD-31): a turn's reply text goes to the filter with the reply's HostData as its second argument, and the HostData passes to the answer
/// unchanged; the decide and diagnose filter calls get none. ProbeFilter keeps the hostData of each call in ^||ZzProbeFilter(<call>, "hostData").
Method TestFilterGetsHostData()
{
	Kill ^||ZzProbeFilter
	Set hostData = "{""citations"":[{""documentRef"":""zzdoc1"",""document"":""Runbook"",""section"":""Rotating"",""passage"":""Step one."",""chunkIndex"":1}]}"
	Set request = ..NewRequest("turn", "user")
	Set reply = ..NewReply("Step one.")
	Set reply.HostData = hostData
	Set sc = ..Conclude(request, reply, .response, ..#FILTER)
	Do $$$AssertStatusOK(sc, "a turn reply that carries HostData is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeFilter), 1, "the filter ran once on the text of the turn")
	Do $$$AssertEquals($Get(^||ZzProbeFilter(1, "hostData")), hostData, "and got the reply's HostData as its second argument")
	Do $$$AssertEquals(response.HostData, hostData, "which the answer carries unchanged")
	Kill ^||ZzProbeFilter
	Set request = ..NewRequest("turn", "user")
	Set sc = ..Conclude(request, ..NewReply("No data."), .response, ..#FILTER)
	Do $$$AssertEquals($Get(^||ZzProbeFilter(1, "hostData"), "unset"), "", "a turn reply with no HostData hands the filter an empty second argument")
	Kill ^||ZzProbeFilter
	Set request = ..NewRequest("decide")
	Set reply = ..NewReply("{""outcome"":""ignore"",""reasons"":[""One reason.""],""confidence"":0.9}")
	Set reply.HostData = hostData
	Set sc = ..Conclude(request, reply, .response, ..#FILTER)
	Do $$$AssertEquals($Get(^||ZzProbeFilter(1)), "One reason.", "a decide reply's reason is filtered")
	Do $$$AssertEquals($Get(^||ZzProbeFilter(1, "hostData"), "unset"), "", "with no hostData: only a turn's text gets the reply's HostData")
	Kill ^||ZzProbeFilter
}

/// A decision with no reason left once the filter has run, and a turn with no text left, are not answers: Conclude records each as a
/// fallback with the reason invalid, for a user's item too, with one decision.recorded and no model text. A reason that the filter
/// blanks while another stays is dropped from the row.
Method TestFilterBlanks()
{
	Set json = "{""outcome"":""ignore"",""reasons"":[""Gone {blank}"",""Gone too {blank}""],""confidence"":0.9}"
	For provenance = "untrusted", "user" {
		Kill ^||ZzProbeSink
		Set request = ..NewRequest("decide", provenance)
		Set sc = ..Conclude(request, ..NewReply(json), .response, ..#FILTER, ..#SINK)
		Set label = "a "_provenance_" decide reply whose reasons the filter blanks"
		Do $$$AssertStatusOK(sc, label_" is recorded as a fallback")
		Do $$$AssertEquals(response.Outcome_"|"_response.Fallback_"|"_response.FallbackReason, "tellnow|1|invalid", label_" is answered tellnow with the reason invalid")
		Do $$$AssertEquals(response.Reasons_response.Confidence_response.Payload, "", label_" keeps no reason, confidence or payload")
		Do $$$AssertEquals(..Rows(request.ItemId), 1, label_" records one row")
		Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, label_" sends one event, decision.recorded")
	}
	Kill ^||ZzProbeSink
	Set request = ..NewRequest("turn", "user")
	Set sc = ..Conclude(request, ..NewReply("Gone {blank}"), .response, ..#FILTER, ..#SINK)
	Do $$$AssertStatusOK(sc, "a turn reply that the filter blanks is recorded as a fallback")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason_"|"_response.Text, 1: "none"), "1|invalid|", "with the reason invalid and no text")
	Do $$$AssertEquals(..Rows(request.ItemId), 1, "records one row")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "and sends one event")

	Set request = ..NewRequest("decide")
	Set json = "{""outcome"":""ignore"",""reasons"":[""Kept."",""Gone {blank}""],""confidence"":0.9}"
	Set sc = ..Conclude(request, ..NewReply(json), .response, ..#FILTER)
	Do $$$AssertStatusOK(sc, "a reply with one reason that the filter keeps is recorded")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals(row.Reasons, "[f] Kept.", "and the row holds the reason that is left")
	Do $$$AssertEquals(response.Reasons, "[f] Kept.", "and so does the answer")
	Do $$$AssertEquals(row.Fallback, 0, "it is no fallback")
}

/// The reply class of a diagnosis (Story 5.4, AD-31): Decide filters each property that the class names in its FILTERED parameter (every text of the model:
/// cause, fixSummary, elementAtFault, each evidence reference, the two noun forms and the three fix parameters, through dotted names and a list) once, after
/// the reasons and before the payload is checked again. The row's Payload holds the filtered texts, and a cause or a noun form that the filter blanks makes
/// the reply invalid (a fallback with no payload). The probe filter's prefix also changes a repair reply's field and formats, which the fix kind refuses when the
/// payload is checked again (Story 7.1), so the stored, filtered payload is that of a partner_outage reply. A reply class without FILTERED (DecisionPayload) is filtered as before: reasons only.
Method TestFilterDiagnosis()
{
	Set diagnosis = "OcuTalon.Watch.Msg.DiagnosisPayload"
	Set input = ##class(OcuTalon.Watch.EvidencePack).Input({"format": "ocutalon.evidencePack/1", "sample": {"headerId": 1, "bodyClass": "OcuTalon.Demo.Orders.PartnerOrder", "body": {"OrderNumber": "A-1", "OrderDate": "10/16/2026", "Sku": "S", "Quantity": "1"}}})
	Set json = "{""outcome"":""act"",""causeCategory"":""data_format_change"",""elementAtFault"":""OrderDate"",""evidence"":[""h1""],""fixKind"":""repair_resend"",""fixParameters"":{""field"":""OrderDate"",""sourceFormat"":""MM/DD/YYYY"",""targetFormat"":""YYYY-MM-DD""},""cause"":""Cause A."",""fixSummary"":""fix B"",""itemNoun"":{""one"":""order"",""other"":""orders""},""reasons"":[""Reason R.""],""confidence"":0.9}"
	Kill ^||ZzProbeFilter
	Set request = ..NewRequest("diagnose")
	Set request.Input = input
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ##class(OcuTalon.Bridge.Ids).NewRef(), ..NewReply(json), diagnosis, ..#FILTER, "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
	Do $$$AssertStatusOK(sc, "a diagnosis reply is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeFilter), 10, "the filter ran once on the reason and once on each of the nine texts of the payload")
	Set seen = ""
	For i = 1:1:10 Set seen = seen _ $Select(i = 1: "", 1: "|") _ $Get(^||ZzProbeFilter(i))
	Do $$$AssertEquals(seen, "Reason R.|Cause A.|fix B|OrderDate|h1|order|orders|OrderDate|MM/DD/YYYY|YYYY-MM-DD", "in the order of FILTERED, each as the model wrote it")
	Do $$$AssertEquals(response.Fallback_"|"_response.FallbackReason_"|"_response.Payload, "1|invalid|", "the probe's prefix changes the field and the formats, so the check after filtering refuses them: a fallback with the reason invalid and no payload")
	Do $$$AssertEquals(..RowOf(request.ItemId, "diagnose").Fallback, 1, "and the row is the fallback")

	Kill ^||ZzProbeFilter
	Set outage = "{""outcome"":""act"",""causeCategory"":""partner_outage"",""elementAtFault"":""OrderDate"",""evidence"":[""h1""],""cause"":""Cause A."",""itemNoun"":{""one"":""order"",""other"":""orders""},""reasons"":[""Reason R.""],""confidence"":0.9}"
	Set request = ..NewRequest("diagnose")
	Set request.Input = input
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ##class(OcuTalon.Bridge.Ids).NewRef(), ..NewReply(outage), diagnosis, ..#FILTER, "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
	Do $$$AssertStatusOK(sc, "a partner_outage diagnosis reply is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeFilter), 6, "the filter ran once on the reason and once on each of the five texts that the payload holds")
	Set seen = ""
	For i = 1:1:6 Set seen = seen _ $Select(i = 1: "", 1: "|") _ $Get(^||ZzProbeFilter(i))
	Do $$$AssertEquals(seen, "Reason R.|Cause A.|OrderDate|h1|order|orders", "in the order of FILTERED, each as the model wrote it")
	Set row = ..RowOf(request.ItemId, "diagnose")
	Do $$$AssertEquals(row.Fallback, 0, "it is no fallback")
	Set stored = {}.%FromJSON(row.Payload)
	Do $$$AssertEquals(stored.cause, "[f] Cause A.", "the stored Payload holds the filtered cause")
	Do $$$AssertEquals(stored.elementAtFault_"|"_stored.evidence.%Get(0)_"|"_stored.itemNoun.one_"|"_stored.itemNoun.other, "[f] OrderDate|[f] h1|[f] order|[f] orders", "the filtered element, evidence and noun forms")
	Do $$$AssertEquals(stored.reasons.%Get(0), "[f] Reason R.", "and the filtered reason")
	Do $$$AssertEquals(response.Payload, row.Payload, "which the response repeats")

	Kill ^||ZzProbeFilter
	Set request = ..NewRequest("diagnose")
	Set request.Input = input
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ##class(OcuTalon.Bridge.Ids).NewRef(), ..NewReply($Replace(outage, "Cause A.", "Gone {blank}")), diagnosis, ..#FILTER, "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
	Do $$$AssertStatusOK(sc, "a diagnosis whose cause the filter blanks is recorded")
	Do $$$AssertEquals(response.Fallback_"|"_response.FallbackReason_"|"_response.Payload, "1|invalid|", "as a fallback with the reason invalid and no payload")
	Do $$$AssertEquals(..RowOf(request.ItemId, "diagnose").Fallback, 1, "the row is the fallback")

	Kill ^||ZzProbeFilter
	Set request = ..NewRequest("diagnose")
	Set request.Input = input
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ##class(OcuTalon.Bridge.Ids).NewRef(), ..NewReply($Replace(outage, """one"":""order""", """one"":""Gone {blank}""")), diagnosis, ..#FILTER, "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
	Do $$$AssertStatusOK(sc, "a diagnosis whose noun form the filter blanks is recorded")
	Do $$$AssertEquals(response.Fallback_"|"_response.FallbackReason, "1|invalid", "as a fallback with the reason invalid")

	Kill ^||ZzProbeFilter
	Set request = ..NewRequest("decide")
	Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response, ..#FILTER)
	Do $$$AssertStatusOK(sc, "a decide reply of a class without FILTERED is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeFilter), 1, "the filter ran on its one reason only")
}

/// The lost save race: another call saves its row for the item and kind after Conclude's check for an existing row and before
/// Conclude's own save (the stand-in request ProbeRaceRequest saves it when Conclude reads its Summary). Conclude answers with the
/// row that won, records no second row and fires no event.
Method TestLostRace()
{
	Kill ^||ZzProbeSink
	Set template = ..NewRequest("decide")
	Set request = ##class(OcuTalon.Test.Bridge.ProbeRaceRequest).%New()
	Set request.Kind = "decide", request.Provenance = "untrusted", request.ItemId = template.ItemId, request.OwnerRef = "instance", request.Summary = template.Summary
	Set request.Competitor = ..NewRow(template.ItemId, "decide", "act")
	Set request.Competitor.Reasons = "The other call won the race."
	Set request.Competitor.Confidence = 0.31
	Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response, , ..#SINK)
	Do $$$AssertTrue(request.Raced && $$$ISOK(request.RaceStatus), "the other call saved its row inside Conclude, after the check for an existing row")
	Do $$$AssertStatusOK(sc, "Conclude answers")
	Do $$$AssertEquals($Select($IsObject(response): response.DecisionRef_"|"_response.Outcome_"|"_response.Reasons, 1: ""), request.Competitor.Ref_"|act|The other call won the race.", "with the row that won")
	Do $$$AssertEquals(..Rows(template.ItemId), 1, "no second row is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and no event is sent")
}

/// Conclude checks the filter class itself, so that a direct caller cannot record unfiltered text: a class that does not extend
/// OcuTalon.Bridge.Ext.ReplyFilter ends Conclude with an error that names ReplyFilterClass, with no row and no event.
Method TestConcludeChecksFilter()
{
	Kill ^||ZzProbeSink
	Set request = ..NewRequest("decide")
	Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response, "OcuTalon.Bridge.Ext.HostSink", ..#SINK)
	Do $$$AssertStatusNotOK(sc, "a filter class that is no ReplyFilter ends Conclude with an error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ReplyFilterClass", "that names ReplyFilterClass: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(response, "", "it gives no answer")
	Do $$$AssertEquals(..Rows(request.ItemId)_"|"_(+$Get(^||ZzProbeSink)), "0|0", "and records no row and sends no event")
}

/// Record saves a row for a new item. A row for an item that another call recorded first is refused by the unique index on
/// (ItemId, Kind): nothing is saved, and the answer is the row that won; for a turn row it is the error that names the item and
/// the Ref.
Method TestRecord()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set request = ..NewRequest("decide")
	Set first = ..NewRow(request.ItemId, "decide", "act")
	Set first.Reasons = "The first call won."
	Set first.Confidence = 0.31
	Do $$$AssertStatusOK($ClassMethod(decide, "Record", first, .saved, .response), "a row for a new item is recorded")
	Do $$$AssertEquals(saved, 1, "and saved")
	Set late = ..NewRow(request.ItemId, "decide", "digest")
	Set sc = $ClassMethod(decide, "Record", late, .saved, .response)
	Do $$$AssertStatusOK(sc, "a row for an item that has one is answered, not failed")
	Do $$$AssertEquals(saved, 0, "and not saved")
	Do $$$AssertTrue($IsObject(response), "the answer is an object")
	If $IsObject(response) {
		Do $$$AssertEquals(response.DecisionRef_"|"_response.Outcome_"|"_response.Reasons_"|"_response.Confidence, first.Ref_"|act|The first call won.|.31", "it is the row that won")
	}
	Do $$$AssertEquals(..Rows(request.ItemId), 1, "and the table holds one row for the item")

	Set request = ..NewRequest("turn", "user")
	Set firstTurn = ..NewRow(request.ItemId, "turn", "tellnow")
	Do $$$AssertStatusOK($ClassMethod(decide, "Record", firstTurn, .saved, .response), "a turn row for a new item is recorded")
	Set lateTurn = ..NewRow(request.ItemId, "turn", "tellnow")
	Set sc = $ClassMethod(decide, "Record", lateTurn, .saved, .response)
	Do $$$AssertStatusNotOK(sc, "a second turn row is refused")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ request.ItemId) && (text [ firstTurn.Ref), "with an error that names the item and the Ref: "_text)
	Do $$$AssertEquals(saved_"|"_response, "0|", "and nothing is saved or answered")
	Do $$$AssertEquals(..Rows(request.ItemId), 1, "and the table holds one row for the turn")
}

/// OnResponse hands the item's own settings to Conclude: a Decide instance whose ReplyFilterClass and HostSinkClass are the probes
/// filters the turn's text once, fires decision.recorded once and records its own session; with the timer's key it records a timeout
/// fallback for the DecisionRef that the process holds, in its own session, and answers the caller (TestTimerFallback pins the rest).
/// No production is started: a turn needs no ReplyClass.
Method TestOnResponseUsesItsSettings()
{
	Set process = ..NewProcess()
	Set process.ReplyFilterClass = ..#FILTER
	Set process.HostSinkClass = ..#SINK
	Set process.%SessionId = 4243
	Set request = ..NewRequest("turn", "user")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ref
	Set sc = process.OnResponse(request, .response, sent, ..NewReply("Everything is fine."), "reply")
	Do $$$AssertStatusOK(sc, "the runner's reply is concluded")
	Do $$$AssertEquals(+$Get(^||ZzProbeFilter), 1, "the filter class of the item ran once")
	Do $$$AssertEquals($Select($IsObject(response): response.Text, 1: ""), "[f] Everything is fine.", "and the answer holds the filtered text")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "the sink class of the item got one call")
	Set row = ..RowOf(request.ItemId, "turn")
	Do $$$AssertTrue($IsObject(row), "a row is recorded")
	If $IsObject(row) {
		Do $$$AssertEquals(row.Ref, ref, "with the DecisionRef of the runner's request")
		Do $$$AssertEquals(row.TraceSessionId, 4243, "and the session of the process")
	}
	Set process.TimerSeconds = 12
	Set later = ..NewRequest("turn", "user")
	Set laterRef = ..NewUsageRef()
	Set process.DecisionRef = laterRef
	Set sc = process.OnResponse(later, .response, later.%ConstructClone(), "", "timer")
	Do $$$AssertStatusOK(sc, "the timer's key is not an error: it records a fallback")
	Do $$$AssertEquals($Select($IsObject(response): response.%ClassName(1)_"|"_response.Fallback_"|"_response.FallbackReason_"|"_response.DecisionRef, 1: "none"), "OcuTalon.Bridge.Msg.Reply|1|timeout|"_laterRef, "a timeout fallback Reply with the DecisionRef of the process")
	Set row = ..RowOf(later.ItemId, "turn")
	Do $$$AssertTrue($IsObject(row), "and a row is recorded")
	If $IsObject(row) Do $$$AssertEquals(row.Ref_"|"_row.FallbackReason_"|"_row.TraceSessionId, laterRef_"|timeout|4243", "with that DecisionRef, the reason and the session of the process")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 2, "the sink class of the item got a second call")
}

/// OnResponse sends the steps of the runner's reply before it reads the ReplyClass setting of the runner (DW-83), so that a reply whose
/// ReplyClass cannot be read still shows its steps: here a request whose kind names no runner, so that the read fails, and a reply whose
/// Steps is not a JSON array, which StepMessages reports in one warning that names the DecisionRef. OnResponse ends with the error that
/// names the ReplyClass setting, after the warning. No production needs to run.
Method TestStepsBeforeReplyClass()
{
	Set process = ..NewProcess()
	Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set process.HostSinkClass = "OcuTalon.Bridge.Ext.HostSink"
	Set request = ..NewRequest("zz")
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..LogNeedles = ..LogNeedles _ $ListBuild(sent.DecisionRef)
	Set reply = ..NewReply("{}")
	Set reply.Steps = "not a JSON array"
	Set mark = ..LogMark()
	Set sc = process.OnResponse(request, .response, sent, reply, "reply")
	Do $$$AssertStatusNotOK(sc, "a reply whose ReplyClass cannot be read ends with an error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ReplyClass", "that names the ReplyClass setting: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(..WarningsOf(mark, sent.DecisionRef), 1, "and its steps were handled first: StepMessages warned once about the Steps of the DecisionRef")
	Do $$$AssertEquals(..Rows(request.ItemId), 0, "no row is recorded")
}

/// OnRequest hands the item's own TimerSeconds and ReplyFilterClass to the settings check: a value outside 12 to 110, and a filter
/// class that is no filter, refuse a turn before anything is sent or recorded. No production is started.
Method TestOnRequestUsesItsSettings()
{
	Set process = ..NewProcess()
	Set request = ..NewRequest("turn", "user")
	For timer = 0, 11, 111 {
		Set process.TimerSeconds = timer
		Set sc = process.OnRequest(request, .response)
		Do $$$AssertStatusNotOK(sc, "a TimerSeconds of "_timer_" refuses the request")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "TimerSeconds", "with an error that names it: "_$SYSTEM.Status.GetErrorText(sc))
		Do $$$AssertEquals(response, "", "and gives no answer")
	}
	Set process.TimerSeconds = 60
	Set process.ReplyFilterClass = "OcuTalon.Test.Bridge.ZzNoSuchFilter"
	Set sc = process.OnRequest(request, .response)
	Do $$$AssertStatusNotOK(sc, "a ReplyFilterClass that is no filter refuses the request")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ReplyFilterClass", "with an error that names it: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(..Rows(request.ItemId), 0, "and no row is recorded")
}

/// A model reason is one line of the row. A line break inside it (CR LF, CR, LF, vertical tab, form feed, NEL or a Unicode line or
/// paragraph separator) becomes a space and the white space and control characters at its ends are trimmed, so that a reason
/// cannot add a line of its own, such as a forged copy of the code-written line of the user rule; a reason of control characters
/// only is dropped. The Payload keeps the reasons as the filter gave them.
Method TestReasonLines()
{
	Set sentence = ##class(OcuTalon.Bridge.Process.Decide).#USERANSWERED
	Set lf = $Char(10)
	Set cr = $Char(13)
	Set body = {"outcome": "act", "confidence": 0.8}
	Set body.reasons = [("First"_lf_"line"), ("Second"_cr_lf_"line"), ("Third"_cr_"line"), "  padded  ", ("Fourth"_lf_sentence)]
	Set json = body.%ToJSON()
	Set expected = "First line"_lf_"Second line"_lf_"Third line"_lf_"padded"_lf_"Fourth "_sentence
	Set request = ..NewRequest("decide")
	Do $$$AssertStatusOK(..Conclude(request, ..NewReply(json), .response), "a reply with line breaks inside its reasons is recorded")
	Set row = ..RowOf(request.ItemId, "decide")
	If '$IsObject(row) || '$IsObject(response) {
		Do $$$AssertTrue(0, "the reply is recorded and answered")
		Quit
	}
	Do $$$AssertEquals(row.Reasons, expected, "each reason is one line of the row, its line breaks are spaces and its ends are trimmed")
	Do $$$AssertEquals($Length(row.Reasons, lf), 5, "five reasons are five lines")
	Do $$$AssertEquals($Find(lf_row.Reasons_lf, lf_sentence_lf), 0, "and no line is the code-written sentence of the user rule, which a reason tried to forge")
	Do $$$AssertEquals(response.Reasons, expected, "the answer holds the same lines")
	Do $$$AssertTrue(row.Payload [ "First\nline", "the Payload keeps the line break of the reason as the model wrote it")
	Set request = ..NewRequest("decide", "user")
	Set body.outcome = "ignore"
	Do $$$AssertStatusOK(..Conclude(request, ..NewReply(body.%ToJSON()), .response), "a user's reply with the same reasons is recorded")
	Set row = ..RowOf(request.ItemId, "decide")
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "the user's reply is recorded")
		Quit
	}
	Do $$$AssertEquals(row.Reasons, sentence_lf_expected, "the code-written line is the first of the lines, and only the code wrote it")
	Do $$$AssertEquals($Length(row.Reasons, lf), 6, "one line more than the five reasons")
	Set body = {"outcome": "act", "confidence": 0.8}
	Set body.reasons = [("Fifth"_$Char(8232)_sentence), ("Sixth"_$Char(133)_"line"), ("Seventh"_$Char(11, 12)_"line"), ("Eighth"_$Char(8233)_"line"), ($Char(7, 9))]
	Set request = ..NewRequest("decide")
	Do $$$AssertStatusOK(..Conclude(request, ..NewReply(body.%ToJSON()), .response), "a reply whose reasons hold the other line breaks, and a reason of control characters only, is recorded")
	Set row = ..RowOf(request.ItemId, "decide")
	Set reasons = $Select($IsObject(row): row.Reasons, 1: "")
	Do $$$AssertEquals(reasons, "Fifth "_sentence_lf_"Sixth line"_lf_"Seventh  line"_lf_"Eighth line", "NEL, VT, FF and the Unicode line and paragraph separators are spaces too, and the reason of control characters is dropped")
	Do $$$AssertEquals($Find(lf_reasons_lf, lf_sentence_lf), 0, "so no line is the code-written sentence")
}

/// The answer to a turn is a clone of the runner's Reply: its Text is filtered and its DecisionRef and Outcome are set, and every
/// other field that the runner set (the taint flag of AD-10, the session and tool flags, the host data, the finish reason and the step
/// count) reaches the caller. The token counts and the cost are those of the decision, the sums of its Usage rows, not the runner's own, and the model
/// is the reply's that answered (Story 17.2). The runner's own Reply is not changed.
Method TestTurnKeepsReply()
{
	Set request = ..NewRequest("turn", "user")
	Set ref = ..NewUsageRef()
	Do ..AddUsage(ref, "zz-model-of-the-rows", 777, 88, 9, 10, .0042)
	Set reply = ..NewReply("Everything is fine.", "end_turn")
	Set reply.Tainted = 1
	Set reply.SessionRotated = 1
	Set reply.SessionId = "42"
	Set reply.SessionFrom = "41"
	Set reply.HistoryCount = 2
	Set reply.ToolsRun = 1
	Set reply.HostData = "{""rows"":[1]}"
	Set reply.Model = "claude-haiku-5-5"
	Set reply.InputTokens = 123
	Set reply.OutputTokens = 45
	Set reply.AgentStepCount = 4
	Set reply.Steps = "[{""kind"":""model"",""label"":""Model request 1"",""summary"":""zz"",""durationMs"":1,""status"":""ok"",""estimatedTokens"":2}]"
	Set sc = ..ConcludeWith(request, ref, reply, 250, .response, ..#FILTER)
	Do $$$AssertStatusOK(sc, "a turn reply with the runner's flags and totals is recorded")
	If '$IsObject(response) {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertTrue(response.%IsA("OcuTalon.Bridge.Msg.Reply"), "the answer is a Reply")
	Do $$$AssertEquals(response.Text, "[f] Everything is fine.", "its Text is the filtered text")
	Do $$$AssertEquals(response.Tainted_"|"_response.SessionRotated_"|"_response.ToolsRun, "1|0|1", "the taint and tools-run flags of the runner reach the caller, and SessionRotated is Decide's: 0, because a tainted reply moves nothing")
	Do $$$AssertEquals(response.SessionId_"|"_response.SessionFrom_"|"_response.HistoryCount, "||", "and the answer names no session")
	Do $$$AssertEquals(response.HostData_"|"_response.FinishReason, "{""rows"":[1]}|end_turn", "and so do the host data and the finish reason")
	Do $$$AssertEquals(..Totals(response), "777|88|9|10|.0042|claude-haiku-5-5|4|250", "the token counts and the cost are the sums of the Usage rows of the decision, the model the reply's that answered, the step count the runner's, the duration the one given")
	Set row = ..RowOf(request.ItemId, "turn")
	Do $$$AssertTrue($IsObject(row), "the turn is recorded")
	If $IsObject(row) {
		Do $$$AssertEquals(response.DecisionRef_"|"_response.Outcome, row.Ref_"|tellnow", "with the DecisionRef of its row and the outcome tellnow")
		Do $$$AssertEquals(..Totals(row), ..Totals(response), "and its row holds the same totals")
	}
	Do $$$AssertEquals(reply.Text_"|"_reply.Outcome_"|"_reply.DecisionRef, "Everything is fine.||", "the runner's own Reply is not changed")
	Do $$$AssertEquals(reply.InputTokens_"|"_reply.OutputTokens_"|"_reply.Model_"|"_reply.AgentStepCount, "123|45|claude-haiku-5-5|4", "not even its totals")
	Do $$$AssertEquals(reply.SessionRotated_"|"_reply.SessionId_"|"_reply.SessionFrom_"|"_reply.HistoryCount, "1|42|41|2", "or its session fields")
	Do $$$AssertEquals(response.Steps, "", "the answer does not carry the runner's Steps: Decide has sent them as messages")
	Do $$$AssertTrue(reply.Steps [ "Model request 1", "and the runner's own Reply keeps them")
}

/// StepMessages: one AgentStep for each record of the reply's Steps, in order. Steps that is empty, white space or missing gives none
/// and no warning; Steps that is no JSON array, and a record that is no object, give a warning that names the DecisionRef and never the
/// content. The answer to a turn has no Steps.
Method TestStepMessages()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set steps = [{"kind": "model", "label": "Model request 1", "summary": "About 100 tokens sent (an estimate). Reply: 0 characters of text, 1 tool calls.", "durationMs": 1001, "status": "ok", "estimatedTokens": 100}, {"kind": "tool", "label": "Reading the test note", "summary": "zz_steps_note. Inputs: {}. Result: {}. About 1 tokens added to the next request (an estimate).", "durationMs": 252, "status": "error", "estimatedTokens": 1}]
	Set reply = ..NewReply("Everything is fine.")
	Set reply.Steps = steps.%ToJSON()
	Set mark = ..LogMark()
	Set messages = $ClassMethod(decide, "StepMessages", ref, reply)
	Do $$$AssertEquals(messages.Count(), 2, "two records give two messages")
	If messages.Count() = 2 {
		Set first = messages.GetAt(1)
		Set second = messages.GetAt(2)
		Do $$$AssertEquals(first.%ClassName(1), "OcuTalon.Bridge.Msg.AgentStep", "each is an AgentStep")
		Do $$$AssertEquals(first.DecisionRef_"|"_first.Position_"|"_first.StepKind_"|"_first.Label_"|"_first.DurationMs_"|"_first.Status_"|"_first.EstimatedTokens, ref_"|1|model|Model request 1|1001|ok|100", "the first has the DecisionRef, Position 1 and the fields of the first record")
		Do $$$AssertEquals(first.Summary, "About 100 tokens sent (an estimate). Reply: 0 characters of text, 1 tool calls.", "and its summary")
		Do $$$AssertEquals(second.DecisionRef_"|"_second.Position_"|"_second.StepKind_"|"_second.Label_"|"_second.DurationMs_"|"_second.Status_"|"_second.EstimatedTokens, ref_"|2|tool|Reading the test note|252|error|1", "the second has Position 2 and the fields of the second record")
		Do $$$AssertEquals(second.Summary, "zz_steps_note. Inputs: {}. Result: {}. About 1 tokens added to the next request (an estimate).", "and its summary")
	}
	Do $$$AssertEquals(..WarningsOf(mark, ref), 0, "and there is no warning")
	Set messages = $ClassMethod(decide, "StepMessages", ref, reply, 3)
	Do $$$AssertEquals(messages.Count(), 2, "with an offset of 3 there are the same two messages")
	If messages.Count() = 2 Do $$$AssertEquals(messages.GetAt(1).Position_"|"_messages.GetAt(2).Position_"|"_messages.GetAt(1).StepKind_"|"_messages.GetAt(2).StepKind, "4|5|model|tool", "numbered 4 and 5: they follow the 3 steps of the earlier attempts")
	Set messages = $ClassMethod(decide, "StepMessages", ref, reply, 0)
	If messages.Count() = 2 Do $$$AssertEquals(messages.GetAt(1).Position_"|"_messages.GetAt(2).Position, "1|2", "and an offset of 0 is the same as none")

	For text = "", " ", $Char(10, 9), "[]" {
		Set reply.Steps = text
		Set messages = $ClassMethod(decide, "StepMessages", ref, reply)
		Do $$$AssertEquals(messages.Count(), 0, "Steps '" _ $Translate(text, $Char(10, 9), "  ") _ "' gives no message")
	}
	Set messages = $ClassMethod(decide, "StepMessages", ref, "")
	Do $$$AssertEquals(messages.Count(), 0, "no reply gives none")
	Set messages = $ClassMethod(decide, "StepMessages", ref, ##class(OcuTalon.Bridge.Msg.AgentStep).%New())
	Do $$$AssertEquals(messages.Count(), 0, "and neither does a message of another class")
	Do $$$AssertEquals(..WarningsOf(mark, ref), 0, "none of them is a problem")

	For text = "{", "[{""kind"":""zzstepcontent""", "{""kind"":""zzstepcontent""}", "zzstepcontent", """zzstepcontent""", "17" {
		Set reply.Steps = text
		Set before = ..WarningsOf(mark, ref)
		Set messages = $ClassMethod(decide, "StepMessages", ref, reply)
		Do $$$AssertEquals(messages.Count(), 0, "Steps '" _ text _ "' gives no message")
		Do $$$AssertEquals(..WarningsOf(mark, ref) - before, 1, "and one warning that names the DecisionRef")
	}
	Do $$$AssertEquals(..LogRowsHolding(mark, "zzstepcontent"), 0, "no warning holds the content of the Steps")

	Set reply.Steps = "[{""kind"":""model"",""label"":""L"",""summary"":""S"",""durationMs"":1,""status"":""ok"",""estimatedTokens"":2}, ""zzstepcontent"", 5, null, {""kind"":""tool"",""label"":""M"",""summary"":""T"",""durationMs"":3,""status"":""ok"",""estimatedTokens"":4}]"
	Set before = ..WarningsOf(mark, ref)
	Set messages = $ClassMethod(decide, "StepMessages", ref, reply)
	Do $$$AssertEquals(messages.Count(), 2, "records that are no object are skipped: two messages")
	If messages.Count() = 2 Do $$$AssertEquals(messages.GetAt(1).Position_"|"_messages.GetAt(2).Position, "1|5", "the Position is the place in the array")
	Do $$$AssertEquals(..WarningsOf(mark, ref) - before, 3, "with one warning for each of them")

	Set request = ..NewRequest("turn", "user")
	Set reply = ..NewReply("Everything is fine.")
	Set reply.Steps = steps.%ToJSON()
	Do $$$AssertStatusOK(..ConcludeWith(request, ..NewUsageRef(), reply, 1, .response), "a turn whose reply has Steps is concluded")
	Do $$$AssertEquals($Select($IsObject(response): response.Steps, 1: "none"), "", "its answer has no Steps")
	Do $$$AssertEquals(reply.Steps, steps.%ToJSON(), "and the runner's Reply keeps them")
}

/// EmitSteps with sends that fail. The records are valid JSON, but a field of each is not a number, so the message is invalid and the send
/// fails in the validation of the message, before any header or queue entry: nothing reaches AgentSteps, with the production running or
/// not. The status of the failed send echoes the value that failed, as the validation error of a real send does, so the warning holds the
/// codes of the error and not its text: the value is a password in the first record and a Bearer token in the second, and neither is in a
/// warning. Each warning names the DecisionRef and the step.
/// (The platform logs the same status itself, as an error of Ens.MessageHeader.NewRequestMessage, with the echoed value. That row is not
/// the step code's: the records that the runner returns are redacted at their source, so a real status echoes no secret, and the value
/// is planted here only to show what the warnings of EmitSteps do with a status that holds one.)
/// EmitSteps raises nothing, and OnResponse answers the turn all the same and records its row.
Method TestEmitStepsFails()
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).RunningReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason _ ", so the status of a failed send echoes the value that failed")
		Quit
	}
	Set process = ..NewProcess()
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set password = "zzhunter2-" _ ##class(OcuTalon.Bridge.Ids).NewRef()
	Set bearer = "zzbearer-" _ ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..LogNeedles = ..LogNeedles _ $ListBuild(ref, password, bearer)
	Set steps = [{"kind": "tool", "label": "Reading the test note", "summary": "zz_steps_note. Inputs: {}. Result: {}. About 1 tokens added to the next request (an estimate).", "durationMs": ("password=" _ password), "status": "ok", "estimatedTokens": 1}, {"kind": "tool", "label": "Reading the test card", "summary": "zz_steps_card. Inputs: {}. Result: {}. About 1 tokens added to the next request (an estimate).", "durationMs": 3, "status": "ok", "estimatedTokens": ("Bearer " _ bearer)}]
	Set reply = ..NewReply("Everything is fine.")
	Set reply.Steps = steps.%ToJSON()
	Set mark = ..LogMark()
	Set raised = ""
	Try {
		Do process.EmitSteps(ref, reply)
	} Catch exception {
		Set raised = exception.DisplayString()
	}
	Do $$$AssertEquals(raised, "", "EmitSteps raises nothing when the sends fail")
	Do $$$AssertEquals(process.StepsSent, 2, "and it counts the two records, so that the Positions of a later attempt run on from 3")
	Do $$$AssertEquals(..EmitWarnings(mark, ref), 2, "and logs one warning for each step that was not sent")
	Do $$$AssertEquals(..EmitWarnings(mark, ref, "Step 1 of the decision " _ ref _ " was not sent to AgentSteps"), 1, "the first names the step, the DecisionRef and AgentSteps")
	Do $$$AssertEquals(..EmitWarnings(mark, ref, "Step 2 of the decision " _ ref _ " was not sent to AgentSteps"), 1, "and so does the second")
	Do $$$AssertEquals(..EmitWarnings(mark, ref, "(error codes "), 2, "each names the codes of its error")
	Do $$$AssertEquals(..EmitWarnings(mark, ref, "password") + ..EmitWarnings(mark, ref, "Bearer") + ..EmitWarnings(mark, ref, "[redacted]"), 0, "and none holds the content of its step: not the value that its status echoes, not even redacted")
	Do $$$AssertEquals(..EmitWarnings(mark, ref, password), 0, "the password is in no warning of EmitSteps")
	Do $$$AssertEquals(..EmitWarnings(mark, ref, bearer), 0, "nor the Bearer token")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Msg.AgentStep WHERE DecisionRef = ?", ref)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 0, "and no AgentStep was saved for the DecisionRef")

	// a second attempt of the same decision numbers its steps from StepsSent + 1
	Set markLater = ..LogMark()
	Do process.EmitSteps(ref, reply)
	Do $$$AssertEquals(process.StepsSent, 4, "a second EmitSteps of the decision counts its two records too")
	Do $$$AssertEquals(..EmitWarnings(markLater, ref, "Step 3 of the decision " _ ref _ " was not sent to AgentSteps") + ..EmitWarnings(markLater, ref, "Step 4 of the decision " _ ref _ " was not sent to AgentSteps"), 2, "and numbers them 3 and 4: the Positions run on across the attempts")

	Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set process.HostSinkClass = "OcuTalon.Bridge.Ext.HostSink"
	Set process.%SessionId = 4244
	Set request = ..NewRequest("turn", "user")
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..LogNeedles = ..LogNeedles _ $ListBuild(sent.DecisionRef)
	Set sc = process.OnResponse(request, .response, sent, reply, "reply")
	Do $$$AssertStatusOK(sc, "the reply is concluded though its steps were not sent")
	Do $$$AssertEquals($Select($IsObject(response): response.Text_"|"_response.Steps, 1: "none"), "Everything is fine.|", "and the answer is the text, with no Steps")
	Set row = ..RowOf(request.ItemId, "turn")
	Do $$$AssertTrue($IsObject(row), "a row is recorded")
	If $IsObject(row) Do $$$AssertEquals(row.Ref, sent.DecisionRef, "with the DecisionRef of the runner's request")
	Do $$$AssertEquals(..EmitWarnings(mark, sent.DecisionRef), 2, "and its two steps are two warnings too")
	Do $$$AssertEquals(..EmitWarnings(mark, sent.DecisionRef, password) + ..EmitWarnings(mark, sent.DecisionRef, bearer), 0, "and neither the password nor the Bearer token is in them")
}

/// Conclude puts the totals of the decision on the Decision row and on the answer, for a decide and for a turn (AD-20, AD-26): the
/// sums of the Usage rows of its DecisionRef in InputTokens, OutputTokens, CacheReadTokens, CacheWriteTokens and CostUSD, the Model of the
/// reply that answered when it holds one (Story 17.2: after a second-model retry the newest Usage row can be a late first attempt's) and else of the
/// newest row, the AgentStepCount of the runner's reply, and the DurationMs it is given. A decision with no Usage row and a reply with no model has empty
/// token fields, cost and model, and one with a row of unknown cost has an empty cost. The reply's own token counts and cost are never used.
Method TestTotals()
{
	For kind = "decide", "turn" {
		Set request = ..NewRequest(kind, $Select(kind = "turn": "user", 1: "untrusted"))
		Set ref = ..NewUsageRef()
		Do ..AddUsage(ref, "claude-haiku-5-5", 3800, 300, 2000, 600, .000365)
		Do ..AddUsage(ref, "claude-sonnet-5-5", 1200, 50, 0, 100, .0123)
		Do ..AddUsage(..NewUsageRef(), "claude-haiku-5-5", 99999, 99999, 99999, 99999, 9)
		Set reply = ..NewReply($Select(kind = "turn": "Everything is fine.", 1: ..#DIGEST))
		Set reply.AgentStepCount = 5
		Set reply.InputTokens = 1
		Set reply.CostUSD = 1
		Set reply.Model = "zz-model-of-the-reply"
		Do $$$AssertStatusOK(..ConcludeWith(request, ref, reply, 1234, .response), "a "_kind_" with two Usage rows is recorded")
		Set row = ..RowOf(request.ItemId, kind)
		If '$IsObject(row) || '$IsObject(response) {
			Do $$$AssertTrue(0, "the "_kind_" is recorded and answered")
			Continue
		}
		Set expected = "5000|350|2000|700|.012665|zz-model-of-the-reply|5|1234"
		Do $$$AssertEquals(..Totals(row), expected, "the "_kind_" row holds the sums of the Usage rows, the model of the reply that answered (not the newest row's), the runner's step count and the duration")
		Do $$$AssertEquals(..Totals(response), expected, "and so does the answer")
	}

	Set request = ..NewRequest("decide")
	Set reply = ..NewReply(..#DIGEST)
	Set reply.AgentStepCount = 5
	Set reply.InputTokens = 1
	Do $$$AssertStatusOK(..ConcludeWith(request, ..NewUsageRef(), reply, 1234, .response), "a decide with no Usage row is recorded")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals(..Totals(row), "||||||5|1234", "its row has empty token fields, cost and model, and the step count and the duration")
	Do $$$AssertEquals(..Totals(response), "||||||5|1234", "and so does the answer")

	Set request = ..NewRequest("turn", "user")
	Do $$$AssertStatusOK(..ConcludeWith(request, ..NewUsageRef(), ..NewReply("Hello."), "", .response), "a turn with no Usage row and no duration is recorded")
	Do $$$AssertEquals(..Totals(..RowOf(request.ItemId, "turn")), "|||||||", "its row has nothing but empty fields")
	Do $$$AssertEquals(..Totals(response), "|||||||", "and so does the answer")

	Set request = ..NewRequest("decide")
	Set ref = ..NewUsageRef()
	Do ..AddUsage(ref, "claude-haiku-5-5", 100, 10, 0, 0, .0001)
	Do ..AddUsage(ref, "zz-unpriced", 200, 20, 5, 6, "")
	Do $$$AssertStatusOK(..ConcludeWith(request, ref, ..NewReply(..#DIGEST), 10, .response), "a decide with a Usage row of unknown cost is recorded")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals(..Totals(row), "300|30|5|6||zz-unpriced||10", "its cost is empty, never the sum of the others, and the other fields are the sums")
	Do $$$AssertEquals(..Totals(response), "300|30|5|6||zz-unpriced||10", "and so is the answer's")
}

/// FireEvent sends decision.recorded with {"ref"} when it is given no type, and the type with the payload it is given; the warning of a
/// sink that fails names the sink, the event and the subject (the day, for budget.capped). It returns 1 when the sink took the event.
Method TestFireEventTypes()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Kill ^||ZzProbeSink
	Do $$$AssertEquals($ClassMethod(decide, "FireEvent", ..#SINK, "ZzOwner", "ref1"), 1, "an event with no type is delivered")
	Set call = $Get(^||ZzProbeSink(1))
	Do $$$AssertEquals($List(call, 1)_"|"_$List(call, 2)_"|"_$List(call, 3), "decision.recorded|ZzOwner|{""ref"":""ref1""}", "it is decision.recorded with the Ref as its payload")
	Do $$$AssertEquals($ClassMethod(decide, "FireEvent", ..#SINK, "ZzOwner", "ref2", "approval.raised"), 1, "an event with a type and no payload is delivered")
	Set call = $Get(^||ZzProbeSink(2))
	Do $$$AssertEquals($List(call, 1)_"|"_$List(call, 3), "approval.raised|{""ref"":""ref2""}", "it has that type and the Ref as its payload")
	Kill ^||ZzProbeSink
	Kill ^OcuTalonBP.UsageCapped("2001-02-03")
	Set payload = ##class(OcuTalon.Bridge.Ext.HostSink).BudgetCappedPayload("2001-02-03")
	Do $$$AssertEquals($ClassMethod(decide, "FireEvent", ..#SINK, "instance", "2001-02-03", "budget.capped", payload), 1, "budget.capped with its payload is delivered")
	Set call = $Get(^||ZzProbeSink(1))
	Do $$$AssertEquals($List(call, 1)_"|"_$List(call, 2)_"|"_$List(call, 3), "budget.capped|instance|{""day"":""2001-02-03""}", "with the owner and the payload it was given")
	Do $$$AssertEquals($List(call, 4)_"|"_$List(call, 5)_"|"_$List(call, 6), "0||0", "outside any transaction, with no ref and no mark")

	For mode = "error", "throw" {
		Kill ^||ZzProbeSink
		Set ^||ZzProbeSink("mode") = mode
		Set mark = ..LogMark()
		Do $$$AssertEquals($ClassMethod(decide, "FireEvent", ..#SINK, "instance", "2001-02-03", "budget.capped", payload), 0, "in "_mode_" mode the event is not delivered")
		Do ..AssertWarning(mark, ..#SINK, "2001-02-03", "budget.capped in "_mode_" mode", "budget.capped")
	}
	Kill ^||ZzProbeSink
	Set mark = ..LogMark()
	Do $$$AssertEquals($ClassMethod(decide, "FireEvent", "OcuTalon.Test.Bridge.ProbeNotASink", "instance", "2001-02-03", "budget.capped", payload), 0, "a class that is no host sink gets no event")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and the probe heard nothing")
	Do ..AssertWarning(mark, "OcuTalon.Test.Bridge.ProbeNotASink", "2001-02-03", "budget.capped to a class that is no sink", "budget.capped")
}

/// A decision whose row cannot be saved is no answer: Conclude ends with the save error, gives no response, fires no event and
/// records no row for the item. Here another row already holds the new Ref (RefIndex is unique); the race on (ItemId, Kind) is
/// TestRecord's.
Method TestSaveFailure()
{
	Kill ^||ZzProbeSink
	Set taken = ..NewRequest("decide")
	Set first = ..NewRow(taken.ItemId, "decide", "act")
	Do $$$AssertStatusOK(first.%Save(), "a row holds a Ref")
	Set request = ..NewRequest("decide")
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, first.Ref, ..NewReply(..#DIGEST), ..#REPLYCLASS, "OcuTalon.Bridge.Ext.ReplyFilter", ..#SINK, 4242, .response)
	Do $$$AssertStatusNotOK(sc, "a decision whose Ref is taken ends with the save error")
	Do $$$AssertEquals(response, "", "it gives no answer")
	Do $$$AssertEquals(..Rows(request.ItemId), 0, "it records no row for the item")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "and sends no event")
	Do $$$AssertEquals(..Rows(taken.ItemId), 1, "the row that holds the Ref is as it was")
	Set late = ..NewRow(request.ItemId, "decide", "digest")
	Set late.Ref = first.Ref
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Record(late, .saved, .response)
	Do $$$AssertStatusNotOK(sc, "Record returns the save error when no row of the item and kind exists")
	Do $$$AssertEquals(saved_"|"_response, "0|", "and saved nothing and answered nothing")
}

/// OnRequest answers an item that has a decision from its row, before it checks any setting or sends anything: for a decide request
/// and for a diagnose request (an answer from a row needs no ReplyClass). A recorded
/// turn is refused with an error that names the item and the Ref. The process of the test has a ReplyFilterClass that is no
/// filter, so that a request that went on to the settings check would be refused (the last case shows it); no production is
/// started and nothing is sent.
Method TestOnRequestAnswersRecorded()
{
	Set process = ..NewProcess()
	Set process.ReplyFilterClass = "OcuTalon.Test.Bridge.ZzNoSuchFilter"
	Set process.TimerSeconds = 60
	For kind = "decide", "diagnose" {
		Set request = ..NewRequest(kind)
		Set row = ..NewRow(request.ItemId, kind, "act")
		Set row.Reasons = "The recorded reason."
		Set row.Confidence = 0.31
		Set row.Payload = "{""outcome"":""act""}"
		Do $$$AssertStatusOK(row.%Save(), "a "_kind_" row is recorded")
		Set sc = process.OnRequest(request, .response)
		Do $$$AssertStatusOK(sc, "a "_kind_" request for a recorded item is answered, not refused")
		If '$IsObject(response) {
			Do $$$AssertTrue(0, "the "_kind_" answer is a DecisionResponse")
			Continue
		}
		Do $$$AssertEquals(response.DecisionRef_"|"_response.Outcome_"|"_response.Reasons_"|"_response.Confidence_"|"_response.Payload, row.Ref_"|act|The recorded reason.|.31|{""outcome"":""act""}", "from the row: its Ref, outcome, reasons, confidence and Payload")
	}
	Set request = ..NewRequest("turn", "user")
	Set row = ..NewRow(request.ItemId, "turn", "tellnow")
	Do $$$AssertStatusOK(row.%Save(), "a turn row is recorded")
	Set sc = process.OnRequest(request, .response)
	Do $$$AssertStatusNotOK(sc, "a turn request for a recorded item is refused")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ request.ItemId) && (text [ row.Ref), "with an error that names the item and the Ref: "_text)
	Do $$$AssertEquals(response, "", "and gives no answer")
	Set request = ..NewRequest("turn", "user")
	Set sc = process.OnRequest(request, .response)
	Do $$$AssertStatusNotOK(sc, "while a turn request for an item with no decision goes on to the settings check and is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "ReplyFilterClass", "for the filter class of this process: "_$SYSTEM.Status.GetErrorText(sc))
}

/// RecordedAt is a UTC time in the stored form whatever the zone of the process: a row recorded in America/New_York holds a time
/// between two readings that were taken in the process's own zone.
Method TestRecordedAtIsUtc()
{
	Set request = ..NewRequest("decide")
	Try {
		Do $SYSTEM.Process.TimeZone("")
		Set before = ##class(OcuTalon.Bridge.Time).NowUtc()
		Do $SYSTEM.Process.TimeZone("America/New_York")
		Set sc = ..Conclude(request, ..NewReply(..#DIGEST), .response)
		Do $SYSTEM.Process.TimeZone("")
		Set after = ##class(OcuTalon.Bridge.Time).NowUtc()
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Do $$$AssertStatusOK(sc, "a decision is recorded in America/New_York")
	Set recorded = ..RowOf(request.ItemId, "decide").RecordedAt
	Do $$$AssertTrue(recorded ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "RecordedAt is a UTC time: "_recorded)
	Do $$$AssertTrue((before ']] recorded) && (recorded ']] after), "and lies between the readings "_before_" and "_after_": "_recorded)
}

/// Conclude of every kind of unusable request or reply records a fallback and answers it (AD-8, AD-20, AD-26, AD-28, AD-31). For each:
/// status OK; one row with the outcome tellnow, Fallback true and the reason, no reasons, confidence or payload, the DecisionRef given and
/// the totals of its Usage rows; one decision.recorded after the save, outside any transaction; and the answer: a DecisionResponse of the row
/// for a decide or diagnose request, and for a turn a new Reply that holds no text, host data, steps, failure text or finish reason, with
/// the model's refused text in no field of it, but the DecisionRef, the totals and the runner's Tainted and ToolsRun, with SessionRotated 0.
Method TestConcludeFallbacks()
{
	Set json = ..#DIGEST
	// the finish reasons
	Do ..AssertFallback("a decide refusal", ..NewRequest("decide"), ..NewReply(json, "refusal"), "", "refusal")
	Do ..AssertFallback("a diagnose refusal", ..NewRequest("diagnose"), ..NewReply(json, "refusal"), "", "refusal")
	Do ..AssertFallback("a decide cut-off", ..NewRequest("decide"), ..NewReply(json, "max_tokens"), "", "cut_off")
	Set reply = ..NewReply("zzrefusedtext I cannot help with that.", "refusal")
	Set reply.Tainted = 1
	Set reply.HostData = "{""rows"":[1]}"
	Set reply.Steps = "[{""kind"":""model"",""label"":""Model request 1"",""summary"":""zz"",""durationMs"":1,""status"":""ok"",""estimatedTokens"":2}]"
	Set reply.SessionRotated = 1
	Set reply.ToolsRun = 1
	Set reply.AgentStepCount = 3
	Do ..AssertFallback("a turn refusal", ..NewRequest("turn", "user"), reply, "", "refusal")
	Set reply = ..NewReply("A cut zzrefusedtext reply that stops at the cap and", "max_tokens")
	Do ..AssertFallback("a turn cut-off", ..NewRequest("turn", "user"), reply, "", "cut_off")
	// an empty text
	Do ..AssertFallback("an empty turn", ..NewRequest("turn", "user"), ..NewReply(" "_$Char(10), "end_turn"), "", "empty")
	Do ..AssertFallback("an empty decide", ..NewRequest("decide"), ..NewReply("", "end_turn"), "", "empty")
	Do ..AssertFallback("an empty turn from a provider that reports no finish reason", ..NewRequest("turn", "user"), ..NewReply(""), "", "unusable")
	// invalid
	Do ..AssertFallback("a decide reply that fails its check", ..NewRequest("decide"), ..NewReply("{""outcome"":""maybe"",""reasons"":[""zzrefusedtext""],""confidence"":0.5}", "end_turn"), "", "invalid")
	Do ..AssertFallback("a decide reply that is no JSON", ..NewRequest("decide"), ..NewReply("Not JSON at all, zzrefusedtext."), "", "invalid")
	Set blanks = "{""outcome"":""ignore"",""reasons"":[""Gone {blank}"",""Gone too {blank}""],""confidence"":0.9}"
	Do ..AssertFallback("a decide reply that the filter leaves nothing of", ..NewRequest("decide"), ..NewReply(blanks, "end_turn"), "", "invalid", ..#FILTER)
	Do ..AssertFallback("a user's decide reply that the filter leaves nothing of", ..NewRequest("decide", "user"), ..NewReply(blanks, "end_turn"), "", "invalid", ..#FILTER)
	Do ..AssertFallback("a turn that the filter leaves nothing of", ..NewRequest("turn", "user"), ..NewReply("Gone {blank} zzrefusedtext", "end_turn"), "", "invalid", ..#FILTER)
	// the failure of the runner
	Set failed = ..NewReply("")
	Set failed.FailureText = ..#MAXITERATIONS
	Set failed.Steps = "[{""kind"":""model"",""label"":""Model request 1"",""summary"":""zz"",""durationMs"":1,""status"":""ok"",""estimatedTokens"":2}]"
	Set failed.Tainted = 1
	Set failed.AgentStepCount = 8
	Do ..AssertFallback("a turn whose Chat reached the maximum of iterations", ..NewRequest("turn", "user"), failed, ..#MAXITERATIONS, "unusable")
	Do ..AssertFallback("a decide whose Chat stalled in a loop", ..NewRequest("decide"), ..NewReply(""), ..#LOOP, "unusable")
	Do ..AssertFallback("a failure with a reply that is a usable text", ..NewRequest("turn", "user"), ..NewReply("Everything is fine."), "ERROR <%AICore>ProviderError: Provider 'anthropic' error: API error: [api_error] zz", "error")
	Do ..AssertFallback("a rate limit", ..NewRequest("decide"), ..NewReply(""), ..#OVERLOADED, "rate_limited")
	Set failed = ..NewReply("")
	Set failed.FailureText = ..#OVERLOADED
	Set failed.ToolsRun = 1
	Do ..AssertFallback("a rate limit after a tool ran", ..NewRequest("turn", "user"), failed, ..#OVERLOADED, "rate_limited")
	Do ..AssertFallback("a provider timeout", ..NewRequest("turn", "user"), ..NewReply(""), "ERROR <%AICore>ProviderError: Provider 'anthropic' error: operation timed out", "timeout")
	Do ..AssertFallback("a missing key found by the runner", ..NewRequest("decide"), ..NewReply(""), "ERROR <%AICore>InternalError: Internal AI-Core error: @{env:ANTHROPIC_API_KEY} has no value and no :-fallback was given", "no_key")
	// no Reply at all
	Do ..AssertFallback("no reply at all", ..NewRequest("decide"), "", "", "error")
	Do ..AssertFallback("a reply of another class", ..NewRequest("turn", "user"), ##class(Ens.StringResponse).%New("x"), "", "error")
}

/// OnError keeps the runner's error status for the key reply and returns OK, so that Ens calls OnResponse, which classifies the failure and
/// records the fallback; the error of any other key keeps its status. A failure Reply is classified by its FailureText, and an error status
/// wins over a Reply.
Method TestOnErrorFallback()
{
	Set process = ..NewProcess()
	Set process.ReplyFilterClass = ..#FILTER
	Set process.HostSinkClass = ..#SINK
	Set process.%SessionId = 4245
	Set request = ..NewRequest("turn", "user")
	Set ref = ..NewUsageRef()
	Do ..AddUsage(ref, "claude-haiku-5-5", 3800, 300, 2000, 600, .000365)
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ref
	Set bad = $$$ERROR($$$GeneralError, "ERROR <%AICore>ProviderCreateFailed: Failed to create provider zz")
	Do $$$AssertStatusOK(process.RunnerError, "no runner error is kept at first")
	Set sc = process.OnError(request, .response, sent, bad, "timer")
	Do $$$AssertStatusNotOK(sc, "the error of another key keeps its status")
	Do $$$AssertStatusOK(process.RunnerError, "and keeps nothing")
	Set sc = process.OnError(request, .response, sent, bad, "zz")
	Do $$$AssertStatusNotOK(sc, "so does the error of an unknown key")
	Set sc = process.OnError(request, .response, sent, bad, "reply")
	Do $$$AssertStatusOK(sc, "OnError returns OK for the key reply, so that Ens calls OnResponse")
	Do $$$AssertStatusNotOK(process.RunnerError, "and keeps the runner's error status")
	Kill ^||ZzProbeSink
	Set sc = process.OnResponse(request, .response, sent, "", "reply")
	Do $$$AssertStatusOK(sc, "OnResponse records the failure")
	Do $$$AssertStatusOK(process.RunnerError, "and clears the error it kept")
	Do $$$AssertTrue($IsObject(response) && response.%IsA("OcuTalon.Bridge.Msg.Reply"), "a turn is answered with a Reply")
	If $IsObject(response) {
		Do $$$AssertEquals(response.Outcome_"|"_response.Fallback_"|"_response.FallbackReason_"|"_response.Text, "tellnow|1|error|", "an error fallback, with no text")
		Do $$$AssertEquals(response.DecisionRef, ref, "with the DecisionRef of the runner's request")
		Do $$$AssertEquals(..Totals(response), "3800|300|2000|600|.000365|claude-haiku-5-5|0|"_response.DurationMs, "and the totals of its Usage rows, no steps and its duration")
	}
	Set row = ..RowOf(request.ItemId, "turn")
	Do $$$AssertTrue($IsObject(row), "the row is recorded")
	If $IsObject(row) Do $$$AssertEquals(row.Outcome_"|"_row.Fallback_"|"_row.FallbackReason_"|"_row.TraceSessionId, "tellnow|1|error|4245", "with the fallback, the reason and the session of the process")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "and one decision.recorded")

	// the reason is that of the status text
	Set texts = $ListBuild(..#OVERLOADED, "ERROR <%AICore>ProviderError: Provider 'anthropic' error: operation timed out", ..#MAXITERATIONS, "ERROR <%AICore>InternalError: Internal AI-Core error: @{env:ANTHROPIC_API_KEY} has no value and no :-fallback was given")
	Set reasons = $ListBuild("rate_limited", "timeout", "unusable", "no_key")
	For i = 1:1:$ListLength(texts) {
		Set request = ..NewRequest("decide")
		Set sent = request.%ConstructClone()
		Set sent.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Do process.OnError(request, .response, sent, $$$ERROR($$$GeneralError, $List(texts, i)), "reply")
		Set sc = process.OnResponse(request, .response, sent, "", "reply")
		Do $$$AssertStatusOK(sc, "a runner error with the text of "_$List(reasons, i)_" is recorded")
		Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason, 1: "none"), "1|"_$List(reasons, i), "as a fallback with the reason "_$List(reasons, i))
	}

	// a failure Reply, and the error that wins over a Reply
	Set request = ..NewRequest("turn", "user")
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set failed = ..NewReply("")
	Set failed.FailureText = ..#LOOP
	Set failed.Tainted = 1
	Set sc = process.OnResponse(request, .response, sent, failed, "reply")
	Do $$$AssertStatusOK(sc, "the failure Reply of a runner is recorded")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason_"|"_response.Tainted_"|"_response.FailureText, 1: "none"), "1|unusable|1|", "as an unusable fallback that carries the taint and not the failure text")
	Set request = ..NewRequest("turn", "user")
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do process.OnError(request, .response, sent, $$$ERROR($$$GeneralError, "zz failed"), "reply")
	Set sc = process.OnResponse(request, .response, sent, ..NewReply("Everything is fine."), "reply")
	Do $$$AssertStatusOK(sc, "an error status and a Reply together are recorded")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason_"|"_response.Text, 1: "none"), "1|error|", "the error wins: the Reply's text is not an answer")

	// a rate limit after a tool ran is not sent again: the fallback is recorded at once, and carries the flag
	Set request = ..NewRequest("turn", "user")
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set failed = ..NewReply("")
	Set failed.FailureText = ..#OVERLOADED
	Set failed.ToolsRun = 1
	Set failed.AgentStepCount = 2
	Set sc = process.OnResponse(request, .response, sent, failed, "reply")
	Do $$$AssertStatusOK(sc, "the failure Reply of a rate limit after a tool ran is recorded at once")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason_"|"_response.ToolsRun_"|"_response.AgentStepCount, 1: "none"), "1|rate_limited|1|2", "as a rate_limited fallback that says a tool ran, with the steps of the attempt")
	Do $$$AssertEquals(process.Resends, 0, "and Decide sent nothing again")
}

/// A fallback for an item that already has a row answers with that row and fires nothing, also when the other call saves its row inside
/// RecordFallback, after its check and before its own save. The row of a turn is refused, naming the item and the Ref.
Method TestFallbackRace()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Kill ^||ZzProbeSink
	Set request = ..NewRequest("decide")
	Set first = ..NewRow(request.ItemId, "decide", "act")
	Set first.Reasons = "The first call won."
	Set first.Confidence = 0.31
	Do $$$AssertStatusOK(first.%Save(), "another call saved its row first")
	Set sc = $ClassMethod(decide, "RecordFallback", request, ##class(OcuTalon.Bridge.Ids).NewRef(), "error", "", ..#SINK, 4242, .response)
	Do $$$AssertStatusOK(sc, "a fallback for the item answers")
	Do $$$AssertEquals($Select($IsObject(response): response.DecisionRef_"|"_response.Outcome_"|"_response.Fallback_"|"_response.Reasons, 1: "none"), first.Ref_"|act|0|The first call won.", "with the row that exists")
	Do $$$AssertEquals(..Rows(request.ItemId)_"|"_(+$Get(^||ZzProbeSink)), "1|0", "records no second row and fires no event")

	Set request = ..NewRequest("turn", "user")
	Set row = ..NewRow(request.ItemId, "turn", "tellnow")
	Do $$$AssertStatusOK(row.%Save(), "a turn row exists")
	Set sc = $ClassMethod(decide, "RecordFallback", request, ##class(OcuTalon.Bridge.Ids).NewRef(), "error", "", ..#SINK, 4242, .response)
	Do $$$AssertStatusNotOK(sc, "a fallback for a turn that has a row is refused")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue((text [ request.ItemId) && (text [ row.Ref), "naming the item and the Ref: "_text)
	Do $$$AssertEquals(response, "", "with no answer")
	Do $$$AssertEquals(..Rows(request.ItemId)_"|"_(+$Get(^||ZzProbeSink)), "1|0", "and no second row or event")

	For kind = "decide", "turn" {
		Set template = ..NewRequest(kind, $Select(kind = "turn": "user", 1: "untrusted"))
		Set race = ##class(OcuTalon.Test.Bridge.ProbeRaceRequest).%New()
		Set race.Kind = kind, race.Provenance = template.Provenance, race.ItemId = template.ItemId, race.OwnerRef = "instance", race.Summary = template.Summary
		Set race.Competitor = ..NewRow(template.ItemId, kind, "act")
		Set race.Competitor.Reasons = "The other call won the race."
		Set sc = $ClassMethod(decide, "RecordFallback", race, ##class(OcuTalon.Bridge.Ids).NewRef(), "refusal", "", ..#SINK, 4242, .response)
		Do $$$AssertTrue(race.Raced && $$$ISOK(race.RaceStatus), "the other "_kind_" call saved its row inside RecordFallback")
		If kind = "decide" {
			Do $$$AssertStatusOK(sc, "the fallback answers")
			Do $$$AssertEquals($Select($IsObject(response): response.DecisionRef_"|"_response.Outcome_"|"_response.Fallback_"|"_response.Reasons, 1: "none"), race.Competitor.Ref_"|act|0|The other call won the race.", "with the row that won")
		} Else {
			Do $$$AssertStatusNotOK(sc, "the fallback of a turn is refused, as the row of a turn has no reply text")
		}
		Do $$$AssertEquals(..Rows(template.ItemId)_"|"_(+$Get(^||ZzProbeSink)), "1|0", "no second "_kind_" row is recorded and no event is fired")
	}
}

/// The day is capped once, by the fallback that records daily_cap (AD-20; U-16): RecordFallback fires decision.recorded and then budget.capped
/// (owner instance, {"day"}), outside any transaction, with the row saved before the first and the mark set before the second. A second
/// item with daily_cap fires decision.recorded only, as does any other reason. Conclude with the gateway's 403 does the same, and a sink
/// that fails is a warning that leaves the mark and the answer.
Method TestMarkCappedWiring()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set today = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())
	Set ..DayMarked = 1
	Kill ^OcuTalonBP.UsageCapped(today)
	Kill ^||ZzProbeSink
	Set first = ..NewRequest("decide")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = $ClassMethod(decide, "RecordFallback", first, ref, "daily_cap", "", ..#SINK, 4242, .response)
	Do $$$AssertStatusOK(sc, "a daily_cap fallback is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 2, "the sink got two calls")
	Set one = $Get(^||ZzProbeSink(1))
	Set two = $Get(^||ZzProbeSink(2))
	Do $$$AssertEquals($List(one, 1)_"|"_$List(one, 2)_"|"_$List(one, 3), "decision.recorded|instance|{""ref"":"""_ref_"""}", "the first is decision.recorded with the Ref of the row")
	Do $$$AssertEquals($List(one, 4)_"|"_$List(one, 5)_"|"_$List(one, 6), "0|1|", "outside any transaction, with the row saved and the day not yet marked")
	Do $$$AssertEquals($List(two, 1)_"|"_$List(two, 2)_"|"_$List(two, 3), "budget.capped|instance|{""day"":"""_today_"""}", "the second is budget.capped with the owner instance and the day")
	Do $$$AssertEquals($List(two, 4)_"|"_$List(two, 5)_"|"_$List(two, 6)_"|"_$List(two, 7), "0||1|0", "outside any transaction, with the mark in place and its lock released")
	Do $$$AssertEquals(..RowOf(first.ItemId, "decide").FallbackReason, "daily_cap", "the row is the daily_cap fallback")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason, 1: "none"), "1|daily_cap", "and so is the answer")

	Set second = ..NewRequest("turn", "user")
	Set ref2 = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = $ClassMethod(decide, "RecordFallback", second, ref2, "daily_cap", "", ..#SINK, 4242, .response)
	Do $$$AssertStatusOK(sc, "a second daily_cap fallback is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 3, "it fires one event more")
	Do $$$AssertEquals($List($Get(^||ZzProbeSink(3)), 1), "decision.recorded", "decision.recorded only: the day is marked once")

	Set third = ..NewRequest("decide")
	Set sc = $ClassMethod(decide, "RecordFallback", third, ##class(OcuTalon.Bridge.Ids).NewRef(), "error", "", ..#SINK, 4242, .response)
	Do $$$AssertStatusOK(sc, "a fallback with another reason is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 4, "it fires one event more")
	Do $$$AssertEquals($List($Get(^||ZzProbeSink(4)), 1), "decision.recorded", "decision.recorded and no budget.capped")
	Kill ^OcuTalonBP.UsageCapped(today)
	Kill ^||ZzProbeSink
	Set fourth = ..NewRequest("decide")
	Set sc = $ClassMethod(decide, "RecordFallback", fourth, ##class(OcuTalon.Bridge.Ids).NewRef(), "error", "", ..#SINK, 4242, .response)
	Do $$$AssertEquals(+$Get(^||ZzProbeSink)_"|"_$Data(^OcuTalonBP.UsageCapped(today)), "1|0", "an error fallback does not mark the day")

	// the gateway's 403 through Conclude
	Kill ^||ZzProbeSink
	Set request = ..NewRequest("turn", "user")
	Set sc = ..ConcludeWith(request, ##class(OcuTalon.Bridge.Ids).NewRef(), ..NewReply(""), 1, .response, , ..#SINK, ..#DAILYCAP)
	Do $$$AssertStatusOK(sc, "Conclude with the gateway's 403 records a fallback")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason, 1: "none"), "1|daily_cap", "daily_cap")
	Do $$$AssertEquals($List($Get(^||ZzProbeSink(1)), 1)_"|"_$List($Get(^||ZzProbeSink(2)), 1)_"|"_(+$Get(^||ZzProbeSink)), "decision.recorded|budget.capped|2", "with decision.recorded and then budget.capped")
	Do $$$AssertTrue($Data(^OcuTalonBP.UsageCapped(today)) > 0, "and the day is marked")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Budget).State().capped, 1, "so that Budget.State reports the cap reached")

	// a sink that fails
	For mode = "error", "throw" {
		Kill ^OcuTalonBP.UsageCapped(today)
		Kill ^||ZzProbeSink
		Set ^||ZzProbeSink("mode") = mode
		Set mark = ..LogMark()
		Set request = ..NewRequest("decide")
		Set sc = $ClassMethod(decide, "RecordFallback", request, ##class(OcuTalon.Bridge.Ids).NewRef(), "daily_cap", "", ..#SINK, 4242, .response)
		Do $$$AssertStatusOK(sc, "in "_mode_" mode the fallback is recorded and answered")
		Do $$$AssertEquals(..Rows(request.ItemId), 1, "the row stands")
		Do $$$AssertTrue($Data(^OcuTalonBP.UsageCapped(today)) > 0, "and so does the mark")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Process.Decide", "FireEvent", $ListBuild(..#SINK, "decision.recorded")), 1, "one warning names the sink and decision.recorded")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Process.Decide", "FireEvent", $ListBuild(..#SINK, "budget.capped", today)), 1, "and one the sink, budget.capped and the day")
	}
}

/// Precheck logs one warning for each fault that Budget.State names (DW-76), naming it and redacted, and one for a DecisionTokenBudget that
/// is not a whole number of 0 or more, which counts as 0. TriageAgent has a key for the test (an inline configuration that names PATH).
Method TestPrecheckLogs()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Do ..PutKey("TriageAgent")
	Do ..Unmark()
	Do ..Put("Decide", "DailyCostCapUSD", 1)
	Do ..Put("Decide", "GatewaySpendUSD", "")
	Do ..Put("Decide", "GatewaySpendDate", "")
	Set now = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set ref = ..NewUsageRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).AddUsage(ref, "zz-unpriced", 10, 5, 0, 0, "", now, "instance"), "a Usage row of today with no cost is saved")
	Set request = ..NewRequest("decide")
	Set mark = ..LogMark()
	Set reason = $ClassMethod(decide, "Precheck", request, "TriageAgent", 0)
	Do $$$AssertEquals(reason, "", "a request with a key, under the cap and with no budget passes")
	Do $$$AssertEquals(..PrecheckWarnings(mark, ""), 1, "one warning comes from Precheck")
	Do $$$AssertEquals(..PrecheckWarnings(mark, "zz-unpriced"), 1, "and it names the model")
	Set fake = "zzfakebearer0123456789"
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).AddUsage(ref, "zz Bearer "_fake, 10, 5, 0, 0, "", now, "instance"), "a model whose name holds a Bearer token is saved")
	Do ..Put("Decide", "GatewaySpendUSD", "x")
	Set mark = ..LogMark()
	Set reason = $ClassMethod(decide, "Precheck", request, "TriageAgent", 0)
	Do $$$AssertEquals(reason, "", "still no fallback: the cap fails open")
	Do $$$AssertEquals(..PrecheckWarnings(mark, ""), 3, "three faults give three warnings: two models and the gateway's spend")
	Do $$$AssertEquals(..PrecheckWarnings(mark, "GatewaySpendUSD"), 1, "one names GatewaySpendUSD")
	Do $$$AssertEquals(..PrecheckWarnings(mark, "zz-unpriced"), 1, "and one the first model")
	Do $$$AssertEquals(..LogRowsHolding(mark, fake), 0, "none holds the fake token: they are redacted")
	Do ..Put("Decide", "GatewaySpendUSD", "")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).AddUsage(ref, "claude-haiku-5-5", 10, 5, 0, 0, 2, now, "instance"), "a priced Usage row above the cap is saved")
	Set mark = ..LogMark()
	Do $$$AssertEquals($ClassMethod(decide, "Precheck", request, "TriageAgent", 0), "daily_cap", "the spend that can be read reaches the cap")
	Do $$$AssertEquals(..PrecheckWarnings(mark, ""), 2, "and the two faults of the models are still logged")

	// the token budget
	Do ..Unmark()
	Do ..Put("Decide", "DailyCostCapUSD", 0)
	For bad = -1, "abc", "1.5", "5e1", "1,000", " 7" {
		Set mark = ..LogMark()
		Do $$$AssertEquals($ClassMethod(decide, "Precheck", request, "TriageAgent", bad), "", "a token budget of '"_bad_"' counts as 0, which is off")
		Do $$$AssertEquals(..PrecheckWarnings(mark, "DecisionTokenBudget"), 1, "with one warning that names DecisionTokenBudget")
		Do $$$AssertEquals(..PrecheckWarnings(mark, ""), 1, "and no other")
	}
	Set estimate = $ClassMethod(decide, "EstimateTokens", request, "TriageAgent")
	For good = "", 0, "0", estimate, "00"_estimate, 1000000 {
		Set mark = ..LogMark()
		Do $$$AssertEquals($ClassMethod(decide, "Precheck", request, "TriageAgent", good), "", "a token budget of '"_good_"' passes this small request")
		Do $$$AssertEquals(..PrecheckWarnings(mark, ""), 0, "with no warning")
	}
}

/// Precheck applies its four facts in AD-8's order, no_key then daily_cap then budget then too_large, whichever of them hold. Each fact is made true by
/// what makes it true in the running system, not handed to Classify: a missing key is a ProviderConfig of TriageAgent with no api_key, a
/// capped day is the day's mark, a budget that is over is a token budget of 1 against a request of several hundred tokens, and a size that is
/// over is a request-size limit one token below the estimate (a limit at the estimate is not over). Every one of the 16 combinations gives the reason
/// of the first fact that holds, and the one combination with none gives ""; the estimate that Precheck works out is given back; a cap reached
/// by the gateway's spend alone (no mark) comes before the budget too. Classify (pure) puts tooLarge after overBudget and before a timer that
/// fired. The rows and the mark are put back by OnAfterOneTest.
Method TestPrecheckOrder()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set today = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())
	Do ..Put("Decide", "DailyCostCapUSD", 0)
	Do ..Put("Decide", "GatewaySpendUSD", "")
	Do ..Put("Decide", "GatewaySpendDate", "")
	Set request = ..NewRequest("decide")
	Set estimate = $ClassMethod(decide, "EstimateTokens", request, "TriageAgent", "", .sc)
	Do $$$AssertStatusOK(sc, "the estimate of the request is worked out: "_estimate)
	Do $$$AssertTrue(estimate > 1, "control: the request is more than 1 token, so a budget of 1 is over and 0 is off, and a limit one token below the estimate is below it")
	For key = 1, 0 {
		For capped = 0, 1 {
			For over = 0, 1 {
				For large = 0, 1 {
					If key {
						Do ..PutKey("TriageAgent")
					} Else {
						Do ..Put("TriageAgent", "ProviderConfig", "{}")
					}
					Do ..Unmark()
					If capped Set ^OcuTalonBP.UsageCapped(today) = ##class(OcuTalon.Bridge.Time).NowUtc()
					Set expected = $Select('key: "no_key", capped: "daily_cap", over: "budget", large: "too_large", 1: "")
					Set label = "a request with "_$Select(key: "a key", 1: "no key")_", "_$Select(capped: "the day capped", 1: "the day open")_", "_$Select(over: "an estimate over the budget", 1: "the budget off")_" and "_$Select(large: "an estimate over the limit", 1: "the limit at the estimate")
					Set reason = $ClassMethod(decide, "Precheck", request, "TriageAgent", over, $Select(large: estimate - 1, 1: estimate), .estimated)
					Do $$$AssertEquals(reason, expected, label_" gives '"_expected_"'")
					Do $$$AssertEquals(estimated, estimate, label_" gives back the estimate")
				}
			}
		}
	}

	// the cap reached by the gateway's spend, with no mark
	Do ..Unmark()
	Do ..Put("Decide", "DailyCostCapUSD", 1)
	Do ..Put("Decide", "GatewaySpendUSD", 1)
	Do ..Put("Decide", "GatewaySpendDate", today)
	Do ..PutKey("TriageAgent")
	Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(today)), 0, "control: the day has no mark")
	Do $$$AssertEquals($ClassMethod(decide, "Precheck", request, "TriageAgent", 1, estimate - 1), "daily_cap", "a cap reached by the gateway's spend comes before an estimate over the budget and the limit")
	Do $$$AssertEquals($ClassMethod(decide, "Precheck", request, "TriageAgent", 0), "daily_cap", "and is daily_cap alone")
	Do ..Put("TriageAgent", "ProviderConfig", "{}")
	Do $$$AssertEquals($ClassMethod(decide, "Precheck", request, "TriageAgent", 1, estimate - 1), "no_key", "and a missing key comes before all of them")

	// Classify is pure: the fact tooLarge gives too_large, after overBudget and before a timer that fired
	Do $$$AssertEquals($ClassMethod(decide, "Classify", {"tooLarge": 1}), "too_large", "tooLarge alone gives too_large")
	Do $$$AssertEquals($ClassMethod(decide, "Classify", {"tooLarge": 1, "timedOut": 1, "failure": "x"}), "too_large", "tooLarge comes before a timer that fired and a failure")
	Do $$$AssertEquals($ClassMethod(decide, "Classify", {"tooLarge": 1, "overBudget": 1}), "budget", "overBudget comes before tooLarge")
	Do $$$AssertEquals($ClassMethod(decide, "Classify", {"tooLarge": 1, "capped": 1, "noKey": 1}), "no_key", "and so do capped and noKey")
	Do $$$AssertEquals($ClassMethod(decide, "Classify", {"tooLarge": 0, "timedOut": 1}), "timeout", "a tooLarge that is false changes nothing")
}

/// The estimate counts what the first model request of the runner carries (Story 1.9; AD-6, AD-20), at 4 characters a token and rounded up: the system
/// prompt and the tool schemas of the runner's agent (RequestSize.AgentChars), the stored history of a linked turn that continues
/// (RequestSize.HistoryChars) and the input that Chat gets (Adapter.Agent ChatInput).
///   - The agent part: AgentChars of Triage is the length of the system prompt of the live agent, of Chat that and the JSON of the Reminders, Watching, Persona, Memory and Email
///     toolsets' tools, of Diagnosis that and the JSON of the Watch toolset's tools (a little less than the live tool catalog, which adds a status to each tool),
///     and of a class that does not exist it is 0 with an error status;
///   - the estimate of a decide, a diagnose, an untrusted turn, a user turn with no link and a user fresh turn with a seed and a note is the agent
///     part plus the length of ChatInput, the seed counting on the user fresh turn only, also when the AgentClass setting of the runner gives the class;
///   - the history: a user turn that continues the conversation of a link counts the stored size of the session that the link names, and an untrusted
///     turn, a fresh turn, a decide and a turn of an owner with no link count none; HistoryChars is the size of the stored ContextData, 0 for no id
///     and for an id that has no session;
///   - a budget is over only above the estimate, and 0 is off.
Method TestEstimateTokens()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set size = "OcuTalon.Bridge.RequestSize"
	Set triageClass = "OcuTalon.Agent.Triage"
	Set diagnosisClass = "OcuTalon.Agent.Diagnosis"
	Set chatClass = "OcuTalon.Agent.Chat"

	// the agent part
	Set triage = $ClassMethod(size, "AgentChars", triageClass, .sc)
	Do $$$AssertStatusOK(sc, "AgentChars of Triage is worked out")
	Do ..LiveSizes(triageClass, .prompt, .catalog)
	Do $$$AssertEquals(triage, prompt, "Triage: the length of the system prompt of the live agent, "_prompt_", and no tool")
	Set chat = $ClassMethod(size, "AgentChars", chatClass, .sc)
	Do $$$AssertStatusOK(sc, "AgentChars of Chat is worked out")
	Do ..LiveSizes(chatClass, .prompt, .catalog)
	Set reminders = $Length(##class(OcuTalon.Tools.Reminders).%New().%Discover().%Get("tools").%ToJSON())
	Do $$$AssertTrue(reminders > 500, "the JSON of the three Reminders tools is measured: "_reminders)
	Set watching = $Length(##class(OcuTalon.Tools.Watching).%New().%Discover().%Get("tools").%ToJSON())
	Do $$$AssertTrue(watching > 500, "the JSON of the Watching tools is measured: "_watching)
	Set persona = $Length(##class(OcuTalon.Tools.Persona).%New().%Discover().%Get("tools").%ToJSON())
	Do $$$AssertTrue(persona > 200, "the JSON of the Persona tool is measured: "_persona)
	Set memory = $Length(##class(OcuTalon.Tools.Memory).%New().%Discover().%Get("tools").%ToJSON())
	Do $$$AssertTrue(memory > 500, "the JSON of the four Memory tools is measured: "_memory)
	Set email = $Length(##class(OcuTalon.Tools.Email).%New().%Discover().%Get("tools").%ToJSON())
	Do $$$AssertTrue(email > 200, "the JSON of the Email tool is measured: "_email)
	Set chatTools = reminders + watching + persona + memory + email
	Do $$$AssertEquals(chat, prompt + chatTools, "Chat: the system prompt of the live agent, "_prompt_", and the JSON of the Reminders, Watching, Persona, Memory and Email toolsets' tools, "_chatTools)
	Do $$$AssertTrue((catalog '< chatTools) && ((catalog - chatTools) < (catalog \ 10)), "which is within a tenth of the live tool catalog, "_catalog)
	Set diagnosis = $ClassMethod(size, "AgentChars", diagnosisClass, .sc)
	Do $$$AssertStatusOK(sc, "AgentChars of Diagnosis is worked out")
	Do ..LiveSizes(diagnosisClass, .prompt, .catalog)
	Set tools = $Length(##class(OcuTalon.Tools.Watch).%New().%Discover().%Get("tools").%ToJSON())
	Do $$$AssertTrue(tools > 500, "the JSON of the three Watch tools is measured: "_tools)
	Do $$$AssertEquals(diagnosis, prompt + tools, "Diagnosis: the system prompt of the live agent, "_prompt_", and the JSON of the Watch toolset's tools, "_tools)
	Do $$$AssertTrue((catalog '< tools) && ((catalog - tools) < (catalog \ 10)), "which is within a tenth of the live tool catalog, "_catalog)
	Set missing = $ClassMethod(size, "AgentChars", "OcuTalon.Zz.NoSuchAgent", .sc)
	Do $$$AssertEquals(missing, 0, "a class that does not exist counts 0")
	Do $$$AssertStatusNotOK(sc, "with an error status")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OcuTalon.Zz.NoSuchAgent", "that names the class: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals($ClassMethod(size, "AgentChars", "", .sc), 0, "so does no class")
	Do $$$AssertStatusNotOK(sc, "with an error status too")
	Set forms = $ClassMethod(size, "AgentChars", "OcuTalon.Test.Bridge.ZzToolsets", .sc)
	Do $$$AssertStatusOK(sc, "a class with no INSTRUCTIONS block and a TOOLSETS with white space, an empty name and a URI is read without an error")
	Do $$$AssertEquals(forms, tools, "and counts the tools of the Watch toolset alone: no prompt, and nothing for the URI")

	// the input is counted in tokens, rounded up
	For n = 0:1:8 {
		Set request = ..NewRequest("decide")
		Set request.Input = $Justify("", n)
		Do $$$AssertEquals($ClassMethod(decide, "EstimateTokens", request, "TriageAgent", triageClass, .sc), (triage + n + 3) \ 4, "an input of "_n_" characters is counted with the agent part, rounded up")
		Do $$$AssertStatusOK(sc, "and the estimate is worked out")
	}

	// the kinds
	Set request = ..NewRequest("decide")
	Set request.SystemNote = "A code-written note."
	Do ..AssertEstimate(request, "TriageAgent", triageClass, 0, "a decide")
	Set request.SeedText = "A recap of the conversation so far, which only a user's fresh turn sends."
	Do ..AssertEstimate(request, "TriageAgent", triageClass, 0, "a decide that carries a seed")
	Set request = ..NewRequest("diagnose")
	Do ..AssertEstimate(request, "DiagnosisAgent", diagnosisClass, 0, "a diagnose")
	Set untrusted = ..NewRequest("turn", "untrusted")
	Set untrusted.SystemNote = "A code-written note."
	Set untrusted.SeedText = "A recap that an untrusted turn never sends."
	Set untrusted.SessionMode = "fresh"
	Do ..AssertEstimate(untrusted, "ChatAgent", chatClass, 0, "an untrusted fresh turn")
	Set continued = ..NewRequest("turn", "user")
	Set continued.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set continued.SeedText = "A recap that a turn that continues ignores."
	Do ..AssertEstimate(continued, "ChatAgent", chatClass, 0, "a user turn with no link")
	Set fresh = ..NewRequest("turn", "user")
	Set fresh.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set fresh.SessionMode = "fresh"
	Set fresh.SeedText = "Earlier, the user said that the build server is called ORION-7."
	Set fresh.SystemNote = "The user opened a new topic."
	Do ..AssertEstimate(fresh, "ChatAgent", chatClass, 1, "a user fresh turn with a seed and a note")
	Set withSeed = $ClassMethod(decide, "EstimateTokens", fresh, "ChatAgent", chatClass)
	Set fresh.SessionMode = ""
	Do ..AssertEstimate(fresh, "ChatAgent", chatClass, 0, "the same turn when it continues (no seed)")
	Do $$$AssertTrue(withSeed > $ClassMethod(decide, "EstimateTokens", fresh, "ChatAgent", chatClass), "which is smaller than the fresh turn that sends the seed")

	// the history of a linked turn that continues
	Set history = 8000
	Set id = ..NewSession(history)
	Do $$$AssertTrue(id '= "", "a saved AI session with "_history_" characters of stored history: "_id)
	Do $$$AssertEquals($ClassMethod(size, "HistoryChars", id), history, "HistoryChars is the size of its stored history")
	Do $$$AssertEquals($ClassMethod(size, "HistoryChars", ""), 0, "0 for no id")
	Do $$$AssertEquals($ClassMethod(size, "HistoryChars", id + 1000000), 0, "and for an id that has no session")
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Data.ConversationLink).Point(owner, "ChatAgent", id), "a link names the session for (owner, ChatAgent)")
	Set linked = ..NewRequest("turn", "user")
	Set linked.OwnerRef = owner
	Set expected = $ClassMethod("OcuTalon.Bridge.Adapter.StepBuffer", "Tokens", chat + history + $Length(##class(OcuTalon.Bridge.Adapter.Agent).ChatInput(linked, 0)))
	Do $$$AssertEquals($ClassMethod(decide, "EstimateTokens", linked, "ChatAgent", chatClass), expected, "a user turn of the owner counts the agent part, the stored history and the input")
	Do $$$AssertEquals($ClassMethod(decide, "EstimateTokens", linked, "ChatAgent"), expected, "also with the AgentClass setting of the runner")
	Set others = ..NewRequest("turn", "untrusted")
	Set others.OwnerRef = owner
	Do ..AssertEstimate(others, "ChatAgent", chatClass, 0, "an untrusted turn of the owner (no history)")
	Set others = ..NewRequest("turn", "user")
	Set others.OwnerRef = owner
	Set others.SessionMode = "fresh"
	Set others.SeedText = "A recap."
	Do ..AssertEstimate(others, "ChatAgent", chatClass, 1, "a fresh turn of the owner (no history)")
	Set others = ..NewRequest("decide", "user")
	Set others.OwnerRef = owner
	Do ..AssertEstimate(others, "TriageAgent", triageClass, 0, "a decide of the owner (no history)")
	Set others = ..NewRequest("turn", "user")
	Set others.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..AssertEstimate(others, "ChatAgent", chatClass, 0, "a user turn of an owner with no link (no history)")
	Do $$$AssertEquals($ClassMethod(decide, "EstimateTokens", linked, "TriageAgent", chatClass), $ClassMethod("OcuTalon.Bridge.Adapter.StepBuffer", "Tokens", chat + $Length(##class(OcuTalon.Bridge.Adapter.Agent).ChatInput(linked, 0))), "the same turn asked of a runner that has no link of the owner counts no history: the link is read for the runner")

	// a budget is over only above the estimate
	Do ..PutKey("TriageAgent")
	Do ..Unmark()
	Do ..Put("Decide", "DailyCostCapUSD", 0)
	Set request = ..NewRequest("decide")
	Set request.Input = "Triage this item."
	Set estimate = $ClassMethod(decide, "EstimateTokens", request, "TriageAgent")
	Do $$$AssertEquals(estimate, (triage + $Length(request.Input) + 3) \ 4, "the estimate of the request is the agent part and the input: "_estimate)
	Do $$$AssertEquals($ClassMethod(decide, "Precheck", request, "TriageAgent", estimate), "", "a budget at the estimate is not over")
	Do $$$AssertEquals($ClassMethod(decide, "Precheck", request, "TriageAgent", estimate - 1), "budget", "a budget one token below it is")
	Do $$$AssertEquals($ClassMethod(decide, "Precheck", request, "TriageAgent", 1), "budget", "so is a budget of 1")
	Do $$$AssertEquals($ClassMethod(decide, "Precheck", request, "TriageAgent", 0), "", "a budget of 0 is off")
	Set request.SeedText = $Justify("", 400)
	Do $$$AssertEquals($ClassMethod(decide, "Precheck", request, "TriageAgent", estimate), "", "a seed on a decide changes nothing: it is never sent")

	// an agent part that cannot be read counts 0, and Precheck logs one warning that names the runner
	Set request = ..NewRequest("decide")
	Set unreadable = $ClassMethod(decide, "EstimateTokens", request, "ZzNoSuchRunner", "", .sc)
	Do $$$AssertStatusNotOK(sc, "the AgentClass of an item that is not in the production cannot be read")
	Do $$$AssertEquals(unreadable, $ClassMethod("OcuTalon.Bridge.Adapter.StepBuffer", "Tokens", $Length(request.Input)), "the agent part then counts 0: only the input is counted")
	Set mark = ..LogMark()
	Do $ClassMethod(decide, "Precheck", request, "ZzNoSuchRunner", 0, "", .estimated)
	Do $$$AssertEquals(estimated, unreadable, "Precheck gives back the same estimate")
	Do $$$AssertEquals(..PrecheckWarnings(mark, "ZzNoSuchRunner"), 1, "and logs one warning that names the runner")
	Set unreadable = $ClassMethod(decide, "EstimateTokens", request, "TriageAgent", "OcuTalon.Zz.NoSuchAgent", .sc)
	Do $$$AssertStatusNotOK(sc, "an agent class that is not compiled gives an error status too")
	Do $$$AssertEquals(unreadable, $ClassMethod("OcuTalon.Bridge.Adapter.StepBuffer", "Tokens", $Length(request.Input)), "and counts 0 for the agent part")
}

/// RequestTokenLimit (Story 1.9; AD-8, AD-19, NFR-3) is a host setting of Decide in the category Bridge, with the initial value 100000 (MAXREQUESTTOKENS).
/// The limit that the precheck applies is the whole number from 1 to 100000 that the setting holds; for an empty value it is 100000 with no warning;
/// for 0, a negative number, text and a number above 100000 it is 100000 with one warning that names RequestTokenLimit, so it is never off and never above
/// 100000. A value that is not made of digits is held as "" (AssignOneSetting, as for DecisionTokenBudget), and the precheck gets the text as it is
/// written (SettingText). The limit is read from the requests at the edge: a request whose estimate is the limit passes, and one token more is too_large.
Method TestRequestLimitSetting()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set agentChars = $ClassMethod("OcuTalon.Bridge.RequestSize", "AgentChars", "OcuTalon.Agent.Triage")
	Do $$$AssertEquals($Parameter(decide, "MAXREQUESTTOKENS"), 100000, "the largest limit is 100000")
	Do $$$AssertEquals($Parameter(decide, "COMPACTTOKENS"), 40000, "and a turn is flagged above 40000")
	Do $$$AssertTrue($ListFind($ListFromString($Parameter(decide, "SETTINGS")), "RequestTokenLimit:Bridge"), "RequestTokenLimit is a setting of the category Bridge")
	Do $$$AssertEquals(..NewProcess().RequestTokenLimit, 100000, "its initial value is 100000")
	Do ..PutKey("TriageAgent")
	Do ..Unmark()
	Do ..Put("Decide", "DailyCostCapUSD", 0)
	Do ..Put("Decide", "GatewaySpendUSD", "")
	Do ..Put("Decide", "GatewaySpendDate", "")
	Set cases = $ListBuild($ListBuild("", 100000, 0), $ListBuild("5000", 5000, 0), $ListBuild("100000", 100000, 0), $ListBuild("0", 100000, 1), $ListBuild("-1", 100000, 1), $ListBuild("abc", 100000, 1), $ListBuild("100001", 100000, 1), $ListBuild("1.5", 100000, 1))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set value = $List(case, 1)
		Set limit = $List(case, 2)
		Set label = "RequestTokenLimit '"_value_"': "
		Do ..Put("Decide", "RequestTokenLimit", value)
		Set process = ..NewProcess()
		Do $$$AssertStatusOK(process.AssignOneSetting("RequestTokenLimit", value, "RequestTokenLimit"), label_"the setting is assigned")
		Set text = process.SettingText("RequestTokenLimit")
		If value ? 1.N {
			Do $$$AssertEquals(process.RequestTokenLimit, +value, label_"the process holds the number")
		} ElseIf value '= "" {
			Do $$$AssertEquals(process.RequestTokenLimit, "", label_"a value that is not made of digits is held as an empty value")
			Do $$$AssertEquals(text, value, label_"and the precheck gets the text as it is written")
		}
		Set request = ..RequestOfTokens("decide", "untrusted", limit, agentChars)
		Set mark = ..LogMark()
		Do $$$AssertEquals($ClassMethod(decide, "EstimateTokens", request, "TriageAgent"), limit, label_"control: the request is "_limit_" tokens")
		Do $$$AssertEquals($ClassMethod(decide, "Precheck", request, "TriageAgent", 0, text), "", label_"a request at "_limit_" tokens passes")
		Do $$$AssertEquals(..PrecheckWarnings(mark, "RequestTokenLimit"), $List(case, 3), label_"with "_$Select($List(case, 3): "one warning that names the setting", 1: "no warning"))
		Set request = ..RequestOfTokens("decide", "untrusted", limit + 1, agentChars)
		Set mark = ..LogMark()
		Do $$$AssertEquals($ClassMethod(decide, "Precheck", request, "TriageAgent", 0, text), "too_large", label_"a request at "_(limit + 1)_" tokens is too_large")
		Do $$$AssertEquals(..PrecheckWarnings(mark, "RequestTokenLimit"), $List(case, 3), label_"again with "_$Select($List(case, 3): "one warning", 1: "no warning"))
	}

	// the smallest limit, and the warning keeps the text out of the log when it holds a secret
	Do $$$AssertEquals($ClassMethod(decide, "Precheck", ..NewRequest("decide"), "TriageAgent", 0, "1"), "too_large", "a limit of 1 is a limit: any request is over it")
	Do $$$AssertEquals($ClassMethod(decide, "Precheck", ..NewRequest("decide"), "TriageAgent", 0, "001"), "too_large", "also written with leading zeros")
	Set fake = "zzfakebearer0123456789"
	Set mark = ..LogMark()
	Do $$$AssertEquals($ClassMethod(decide, "Precheck", ..NewRequest("decide"), "TriageAgent", 0, "Bearer "_fake), "", "a limit that is text counts as 100000")
	Do $$$AssertEquals(..PrecheckWarnings(mark, "RequestTokenLimit"), 1, "with one warning")
	Do $$$AssertEquals(..LogRowsHolding(mark, fake), 0, "which holds no Bearer token: it is redacted")
}

/// The limit that OnRequest applies comes from the setting row, also for a value that is not a number (Story 1.9; AD-8, AD-19, NFR-3). Each case writes the
/// System Default Settings row of Decide's RequestTokenLimit and assigns the value to a recorder as the host does (AssignOneSetting). OnRequest then sends a
/// decide estimated at the limit (one request to TriageAgent and one timer) and answers a decide one token above it with a too_large DecisionResponse,
/// sending nothing and setting no timer, and so does the key resend of that decide. The limit is the whole number from 1 to 100000 that the row holds
/// (5000); it is 100000 for an empty row, with no warning, and for 0, -1, abc, 1.5 and 100001, with one warning that names RequestTokenLimit at each
/// precheck, so it is never off and never above 100000.
Method TestRequestLimitThroughOnRequest()
{
	Set size = "OcuTalon.Bridge.RequestSize"
	Set agentChars = $ClassMethod(size, "AgentChars", "OcuTalon.Agent.Triage")
	Set cases = $ListBuild($ListBuild("", 100000, 0), $ListBuild("5000", 5000, 0), $ListBuild("0", 100000, 1), $ListBuild("-1", 100000, 1), $ListBuild("abc", 100000, 1), $ListBuild("1.5", 100000, 1), $ListBuild("100001", 100000, 1))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set value = $List(case, 1)
		Set limit = $List(case, 2)
		Set warnings = $List(case, 3)
		Set label = "RequestTokenLimit '"_value_"': "
		Do ..PutKey("TriageAgent")
		Do ..Unmark()
		Do ..Put("Decide", "DailyCostCapUSD", 0)
		Do ..Put("Decide", "GatewaySpendUSD", "")
		Do ..Put("Decide", "GatewaySpendDate", "")
		Do ..Put("Decide", "RequestTokenLimit", value)
		For over = 0, 1 {
			Set request = ..RequestOfTokens("decide", "untrusted", limit + over, agentChars)
			Set what = "a decide of "_(limit + over)_" tokens"
			Kill ^||ZzDecideCalls, ^||ZzProbeSink
			Set process = ..NewRecorder()
			Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
			Set process.HostSinkClass = ..#SINK
			Set process.TimerSeconds = 60
			Set process.DecisionTokenBudget = 0
			Set process.%SessionId = 4256
			Do $$$AssertStatusOK(process.AssignOneSetting("RequestTokenLimit", value, "RequestTokenLimit"), label_"the setting is assigned")
			Set mark = ..LogMark()
			Set response = ""
			Set sc = process.OnRequest(request, .response)
			Do $$$AssertStatusOK(sc, label_what_" is answered by OnRequest")
			Do $$$AssertEquals(..RecorderWarnings(mark, "RequestTokenLimit"), warnings, label_what_" gets "_$Select(warnings: "one warning that names the setting", 1: "no warning"))
			If 'over {
				Do $$$AssertEquals(response, "", label_what_" is at the limit: nothing is answered yet")
				Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer")_"|"_..Rows(request.ItemId), "1|1|0", label_what_" is sent to its runner, with one timer and no row")
				Continue
			}
			Set row = ..RowOf(request.ItemId, "decide")
			Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).FallbackProblems(response, row, "decide", "too_large"), "", label_what_" is one token above the limit: a tellnow fallback with the reason too_large")
			Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer"), "0|0", label_what_" is not sent, and no timer is set")

			// the key resend of the same decide
			Kill ^||ZzDecideCalls, ^||ZzProbeSink
			Set resender = ..NewRecorder()
			Set resender.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
			Set resender.HostSinkClass = ..#SINK
			Set resender.TimerSeconds = 60
			Set resender.DecisionTokenBudget = 0
			Set resender.%SessionId = 4256
			Set resender.%TimeCreated = ..Ago(3)
			Set resender.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
			Do $$$AssertStatusOK(resender.AssignOneSetting("RequestTokenLimit", value, "RequestTokenLimit"), label_"the setting is assigned to the process of the re-send")
			Set request = ..RequestOfTokens("decide", "untrusted", limit + 1, agentChars)
			Set mark = ..LogMark()
			Set again = ""
			Do $$$AssertStatusOK(resender.OnResponse(request, .again, "", "", "resend"), label_"the key resend is answered")
			Set row = ..RowOf(request.ItemId, "decide")
			Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).FallbackProblems(again, row, "decide", "too_large"), "", label_"the re-send of a decide of "_(limit + 1)_" tokens is a too_large fallback too")
			Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer")_"|"_resender.Resends, "0|0|0", label_"and sends nothing")
			Do $$$AssertEquals(..RecorderWarnings(mark, "RequestTokenLimit"), warnings, label_"with "_$Select(warnings: "one warning that names the setting", 1: "no warning"))
		}
		Do ..RestoreRows()
	}
}

/// The request that Decide sends to a runner carries the flag Compact (Story 1.9; AD-6, AD-20), set by Decide alone: 1 exactly when the request is a turn
/// (a user's or an untrusted one, any SessionMode) whose estimate is above 40000 tokens, and 0 for every other request, whatever the caller set. The
/// first send and the re-send build the request in the same place. With the recorder (Test.Bridge.ZzDecide) the sent request's flag is its seventh
/// member: a user turn at 40000 tokens gets 0, one at 40001 gets 1, a decide and a diagnose at 50000 get 0, an untrusted turn at 50000 gets 1, and a short
/// user turn whose caller set Compact to 1 gets 0; the request itself is not changed; the re-send of the turn at 40001 carries 1 and that of the decide 0.
Method TestCompactFlag()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set size = "OcuTalon.Bridge.RequestSize"
	Do ..PutKey("TriageAgent")
	Do ..PutKey("DiagnosisAgent")
	Do ..PutKey("ChatAgent")
	Do ..Put("DiagnosisAgent", "ReplyClass", ..#REPLYCLASS)
	Do ..Unmark()
	Do ..Put("Decide", "DailyCostCapUSD", 0)
	Do ..Put("Decide", "GatewaySpendUSD", "")
	Do ..Put("Decide", "GatewaySpendDate", "")
	Set chars("TriageAgent") = $ClassMethod(size, "AgentChars", "OcuTalon.Agent.Triage")
	Set chars("DiagnosisAgent") = $ClassMethod(size, "AgentChars", "OcuTalon.Agent.Diagnosis")
	Set chars("ChatAgent") = $ClassMethod(size, "AgentChars", "OcuTalon.Agent.Chat")
	Set cases = $ListBuild(
		$ListBuild("turn", "user", "ChatAgent", 40000, 0, 0),
		$ListBuild("turn", "user", "ChatAgent", 40001, 0, 1),
		$ListBuild("decide", "untrusted", "TriageAgent", 50000, 0, 0),
		$ListBuild("diagnose", "untrusted", "DiagnosisAgent", 50000, 0, 0),
		$ListBuild("turn", "untrusted", "ChatAgent", 50000, 0, 1),
		$ListBuild("turn", "user", "ChatAgent", 0, 1, 0))
	Set position = 0
	Set number = 0
	While $ListNext(cases, position, case) {
		Set number = number + 1
		Set kind = $List(case, 1)
		Set runner = $List(case, 3)
		Set tokens = $List(case, 4)
		Set label = "a "_$List(case, 2)_" "_kind_" of "_$Select(tokens: tokens_" tokens", 1: "a few tokens")_$Select($List(case, 5): " whose caller set Compact to 1", 1: "")_": "
		If tokens {
			Set request = ..RequestOfTokens(kind, $List(case, 2), tokens, chars(runner))
		} Else {
			Set request = ..NewRequest(kind, $List(case, 2))
			Set request.Input = "Say hello."
		}
		If kind = "turn" Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set request.Compact = $List(case, 5)
		Kill ^||ZzDecideCalls, ^||ZzProbeSink
		Set process = ..NewRecorder()
		Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
		Set process.HostSinkClass = ..#SINK
		Set process.TimerSeconds = 60
		Set process.DecisionTokenBudget = 0
		Set process.RequestTokenLimit = 100000
		Set process.%SessionId = 4254
		Set sc = process.OnRequest(request, .response)
		Do $$$AssertStatusOK(sc, label_"OnRequest sends the request")
		Do $$$AssertEquals(response, "", label_"and answers nothing yet")
		Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer"), "1|1", label_"it sent one request to the runner and set the timer")
		Set call = $Get(^||ZzDecideCalls("send", 1))
		Do $$$AssertEquals($ListGet(call, 1)_"|"_$ListGet(call, 2)_"|"_$ListGet(call, 4)_"|"_$ListGet(call, 5), runner_"|"_process.DecisionRef_"|reply|"_request.ItemId, label_"to its runner, with the DecisionRef of the process")
		Do $$$AssertEquals($ListGet(call, 7), $List(case, 6), label_"the sent request's Compact is "_$List(case, 6))
		Do $$$AssertEquals(request.Compact_"|"_request.DecisionRef, $List(case, 5)_"|", label_"and the request itself is not changed")
		If number = 2 {
			Set long = request
			Set longProcess = process
		}
		If number = 3 {
			Set decided = request
			Set decideProcess = process
		}
	}

	// the re-send builds the request in the same place
	Do ..AssertResendFlag(longProcess, long, 1, "the turn at 40001 tokens")
	Do ..AssertResendFlag(decideProcess, decided, 0, "the decide at 50000 tokens")
}

/// The key resend of the recorder's process for the request sends one request to the runner, whose Compact is the flag expected; the request itself is not
/// changed.
Method AssertResendFlag(process As OcuTalon.Test.Bridge.ZzDecide, request As OcuTalon.Bridge.Msg.Request, flag As %Boolean, label As %String) [ Private ]
{
	Kill ^||ZzDecideCalls
	Set process.%TimeCreated = ..Ago(3)
	Set response = ""
	Set sc = process.OnResponse(request, .response, "", "", "resend")
	Do $$$AssertStatusOK(sc, "the re-send of "_label_" is answered with status OK")
	Do $$$AssertEquals(..Calls("send"), 1, "and sends one request")
	Do $$$AssertEquals($ListGet($Get(^||ZzDecideCalls("send", 1)), 7), flag, "whose Compact is "_flag)
	Do $$$AssertEquals(request.DecisionRef, "", "the request itself is not changed by it either")
}

/// OnRequest records a request that fails a precheck as a fallback and answers it itself, with no runner request and no timer; the settings
/// are checked first, and an item that has a decision is answered from its row. No production is started. A decide and a user turn whose estimate
/// is above the request-size limit (Story 1.9) are answered with a too_large fallback: a DecisionResponse, or a Reply with no text and no flag, with one
/// decision.recorded, and the recorder (Test.Bridge.ZzDecide) shows that nothing was sent and no timer was set.
Method TestOnRequestPrecheck()
{
	Do ..PutKey("TriageAgent")
	Do ..Put("ChatAgent", "ProviderConfig", "{}")
	Do ..Unmark()
	Do ..Put("Decide", "DailyCostCapUSD", 0)
	Set process = ..NewProcess()
	Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set process.HostSinkClass = ..#SINK
	Set process.TimerSeconds = 60
	Set process.DecisionTokenBudget = 1
	Set process.%SessionId = 4246
	Set request = ..NewRequest("decide")
	Kill ^||ZzProbeSink
	Set sc = process.OnRequest(request, .response)
	Do $$$AssertStatusOK(sc, "a request over the token budget is answered by OnRequest")
	Do $$$AssertEquals($Select($IsObject(response): response.%ClassName(1)_"|"_response.Outcome_"|"_response.Fallback_"|"_response.FallbackReason, 1: "none"), "OcuTalon.Bridge.Msg.DecisionResponse|tellnow|1|budget", "with a DecisionResponse that is a fallback with the reason budget")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertTrue($IsObject(row), "the row is recorded")
	If $IsObject(row) Do $$$AssertEquals(row.FallbackReason_"|"_row.TraceSessionId_"|"_row.AgentStepCount, "budget|4246|0", "with the reason, the session of the process and no steps")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "and one decision.recorded")
	Set sc = process.OnRequest(request, .again)
	Do $$$AssertStatusOK(sc, "the same item again is answered from its row")
	Do $$$AssertEquals($Select($IsObject(again): again.DecisionRef, 1: ""), $Select($IsObject(row): row.Ref, 1: ""), "with the same DecisionRef")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, "and no second event")

	Set process.DecisionTokenBudget = 0
	Set request = ..NewRequest("turn", "user")
	Set sc = process.OnRequest(request, .response)
	Do $$$AssertStatusOK(sc, "a turn with no key for ChatAgent is answered by OnRequest")
	Do $$$AssertEquals($Select($IsObject(response): response.%ClassName(1)_"|"_response.Fallback_"|"_response.FallbackReason_"|"_response.Text, 1: "none"), "OcuTalon.Bridge.Msg.Reply|1|no_key|", "with a Reply that is a no_key fallback and has no text")

	Set process.TimerSeconds = 0
	Set process.DecisionTokenBudget = 1
	Set request = ..NewRequest("turn", "user")
	Set sc = process.OnRequest(request, .response)
	Do $$$AssertStatusNotOK(sc, "a Decide with a bad setting is an error, not a fallback, although this turn also fails the no-key and the budget prechecks")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "TimerSeconds", "that names the setting: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(..Rows(request.ItemId), 0, "and records no row")

	// an estimate over the request-size limit: too_large, after the key and the budget, and nothing is sent
	Do ..PutKey("TriageAgent")
	Do ..PutKey("ChatAgent")
	Do ..Put("DiagnosisAgent", "ReplyClass", ..#REPLYCLASS)
	For case = $ListBuild("decide", "untrusted", "TriageAgent"), $ListBuild("turn", "user", "ChatAgent") {
		Set kind = $List(case, 1)
		Set runner = $List(case, 3)
		Set label = "a "_kind_" over the limit: "
		Kill ^||ZzDecideCalls, ^||ZzProbeSink
		Set recorder = ..NewRecorder()
		Set recorder.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
		Set recorder.HostSinkClass = ..#SINK
		Set recorder.TimerSeconds = 60
		Set recorder.DecisionTokenBudget = 0
		Set recorder.%SessionId = 4255
		Set request = ..NewRequest(kind, $List(case, 2))
		If kind = "turn" Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set estimate = $ClassMethod("OcuTalon.Bridge.Process.Decide", "EstimateTokens", request, runner)
		Set recorder.RequestTokenLimit = estimate
		Set response = ""
		Set sc = recorder.OnRequest(request, .passed)
		Do $$$AssertStatusOK(sc, label_"control: with the limit at the estimate, "_estimate_" tokens, OnRequest sends it")
		Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer")_"|"_..Rows(request.ItemId), "1|1|0", label_"control: one request to the runner, one timer and no row")
		Kill ^||ZzDecideCalls, ^||ZzProbeSink
		Set recorder.RequestTokenLimit = estimate - 1
		Set sc = recorder.OnRequest(request, .response)
		Do $$$AssertStatusOK(sc, label_"with the limit one token below the estimate OnRequest answers")
		Do $$$AssertEquals($Select($IsObject(response): response.%ClassName(1), 1: "none"), $Select(kind = "turn": "OcuTalon.Bridge.Msg.Reply", 1: "OcuTalon.Bridge.Msg.DecisionResponse"), label_"with a "_$Select(kind = "turn": "Reply", 1: "DecisionResponse"))
		Set row = ..RowOf(request.ItemId, kind)
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).FallbackProblems(response, row, kind, "too_large"), "", label_"a tellnow fallback with the reason too_large, in the answer, its XML and the row")
		If (kind = "turn") && $IsObject(response) Do $$$AssertEquals(response.Text_"|"_response.Tainted_"|"_response.ToolsRun_"|"_response.SessionRotated_"|"_response.SessionBroken_"|"_response.Busy, "|0|0|0|0|0", label_"the Reply has no text and sets no flag")
		Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer"), "0|0", label_"nothing is sent and no timer is set")
		Do $$$AssertEquals(..SinkTypes(), "decision.recorded", label_"one decision.recorded")
		Set recorder.RequestTokenLimit = 1
		Set request = ..NewRequest(kind, $List(case, 2))
		If kind = "turn" Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set recorder.DecisionTokenBudget = 1
		Kill ^||ZzProbeSink
		Set sc = recorder.OnRequest(request, .response)
		Do $$$AssertEquals($Select($IsObject(response): response.FallbackReason, 1: "none"), "budget", label_"a request that is also over the budget takes budget: too_large comes after it")
	}
}

/// OnResponse for the key timer records a fallback for the DecisionRef that the process holds, and answers the caller (AD-6, AD-8, AD-20):
/// timeout when Decide has sent nothing again, rate_limited when it has (Resends above 0), for a decide and for a turn. The row has the
/// DecisionRef and the session of the process and the totals of the Usage rows of the ref when the timer fired, the steps of the earlier
/// attempts (StepCount) and a duration from the start of the process; the answer is a DecisionResponse, or a fallback Reply that sets no
/// flag of a runner (there is none), carries the same totals and holds nothing of a runner; one decision.recorded is sent; and the process
/// keeps its state (Resends, StepCount).
Method TestTimerFallback()
{
	For kind = "decide", "turn" {
		For resends = 0, 1, 3 {
			Set reason = $Select(resends > 0: "rate_limited", 1: "timeout")
			Set label = "a "_kind_" whose timer fired after "_resends_" re-sends: "
			Kill ^||ZzProbeSink
			Set process = ..NewProcess()
			Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
			Set process.HostSinkClass = ..#SINK
			Set process.%SessionId = 4248
			Set process.%TimeCreated = ..Ago(5)
			Set process.TimerSeconds = 60
			Set process.Resends = resends
			Set process.StepCount = 2
			Set ref = ..NewUsageRef()
			Set process.DecisionRef = ref
			Do ..AddUsage(ref, "claude-haiku-5-5", 3800, 300, 2000, 600, .000365)
			Set request = ..NewRequest(kind, $Select(kind = "turn": "user", 1: "untrusted"))
			Set response = ""
			Set sc = process.OnResponse(request, .response, request.%ConstructClone(), "", "timer")
			Do $$$AssertStatusOK(sc, label_"the timer's key is answered with status OK")
			Set row = ..RowOf(request.ItemId, kind)
			If '$IsObject(row) || '$IsObject(response) {
				Do $$$AssertTrue(0, label_"a row is recorded and an answer is given")
				Continue
			}
			Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).FallbackProblems(response, row, kind, reason), "", label_"every guarantee of a fallback holds with the reason "_reason_", in the answer, its XML and the row")
			Do $$$AssertEquals(row.Ref_"|"_row.TraceSessionId, ref_"|4248", label_"the row has the DecisionRef and the session of the process")
			Do $$$AssertEquals(..Totals(response), ..Totals(row), label_"the answer carries the totals of the row")
			Do $$$AssertEquals($Piece(..Totals(row), "|", 1, 7), "3800|300|2000|600|.000365|claude-haiku-5-5|2", label_"the totals of the Usage rows of the ref, and the 2 steps of the earlier attempts")
			Do $$$AssertTrue((row.DurationMs '< 5000) && (row.DurationMs < 60000), label_"the duration runs from the start of the process: "_row.DurationMs)
			Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, label_"one event is sent")
			Set call = $Get(^||ZzProbeSink(1))
			Do $$$AssertEquals($List(call, 1)_"|"_$List(call, 3), "decision.recorded|{""ref"":"""_ref_"""}", label_"decision.recorded for the ref")
			If kind = "turn" Do $$$AssertEquals(response.Tainted_"|"_response.ToolsRun_"|"_response.SessionRotated_"|"_response.SessionBroken_"|"_response.Busy, "0|0|0|0|0", label_"the Reply sets no flag of a runner")
			Do $$$AssertEquals(process.Resends_"|"_process.StepCount, resends_"|2", label_"and Decide keeps its state")
		}
	}
	// a request that has a row already is answered with the row, and nothing is recorded twice
	Kill ^||ZzProbeSink
	Set process = ..NewProcess()
	Set process.HostSinkClass = ..#SINK
	Set request = ..NewRequest("decide")
	Set first = ..NewRow(request.ItemId, "decide", "act")
	Do $$$AssertStatusOK(first.%Save(), "a decide that another call recorded first")
	Set process.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set response = ""
	Set sc = process.OnResponse(request, .response, request.%ConstructClone(), "", "timer")
	Do $$$AssertStatusOK(sc, "its timer's key is answered")
	Do $$$AssertEquals($Select($IsObject(response): response.DecisionRef_"|"_response.Outcome, 1: "none"), first.Ref_"|act", "with the row that won")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink)_"|"_..Rows(request.ItemId), "0|1", "and no second row and no event")
	Do $$$AssertStatusNotOK(process.OnResponse(request, .response, request.%ConstructClone(), "", "zz"), "any other key but timer, resend and reply is an error")
}

/// TimerFor (Story 30.1; AD-5, AD-20, NFR-3): the timer of an attempt is TimerSeconds, and TimerSeconds plus 20 seconds, at most 110, for a request that is
/// flagged and continues its conversation (a user turn that is not fresh and whose owner has a link that names a session). An unflagged turn, a first turn,
/// a fresh turn, an untrusted turn and a decide keep TimerSeconds. OnRequest sets that timer, and the key resend counts the time left from the same total.
Method TestTimerFor()
{
	Set id = ..NewSession(1000)
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Data.ConversationLink).Point(owner, "ChatAgent", id), "a link names a session for (owner, ChatAgent)")
	Set continues = ..NewRequest("turn", "user")
	Set continues.OwnerRef = owner
	Set first = ..NewRequest("turn", "user")
	Set first.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set fresh = ..NewRequest("turn", "user")
	Set fresh.OwnerRef = owner
	Set fresh.SessionMode = "fresh"
	Set untrusted = ..NewRequest("turn", "untrusted")
	Set untrusted.OwnerRef = owner
	Set decide = ..NewRequest("decide", "user")
	Set decide.OwnerRef = owner
	Set process = ..NewRecorder()
	For timer = 60, 100, 110 {
		Set process.TimerSeconds = timer
		Set grown = $Select(timer + 20 > 110: 110, 1: timer + 20)
		Do $$$AssertEquals(process.TimerFor(continues, 1), grown, "TimerSeconds "_timer_": a flagged turn that continues gets "_grown_" seconds")
		Do $$$AssertEquals(process.TimerFor(continues, 0), timer, "TimerSeconds "_timer_": an unflagged turn that continues keeps "_timer)
		Do $$$AssertEquals(process.TimerFor(first, 1), timer, "TimerSeconds "_timer_": a flagged first turn keeps "_timer)
		Do $$$AssertEquals(process.TimerFor(fresh, 1), timer, "TimerSeconds "_timer_": a flagged fresh turn keeps "_timer)
		Do $$$AssertEquals(process.TimerFor(untrusted, 1), timer, "TimerSeconds "_timer_": a flagged untrusted turn keeps "_timer)
		Do $$$AssertEquals(process.TimerFor(decide, 1), timer, "TimerSeconds "_timer_": a decide keeps "_timer)
	}
	Do $$$AssertEquals($Parameter("OcuTalon.Bridge.Compaction", "SUMMARIZERSECONDS"), 20, "the summarizer's seconds are 20")

	// OnRequest sets the timer of the flagged turn that continues, and the re-send counts from the same total
	Do ..PutKey("ChatAgent")
	Do ..Unmark()
	Do ..Put("Decide", "DailyCostCapUSD", 0)
	Do ..Put("Decide", "GatewaySpendUSD", "")
	Do ..Put("Decide", "GatewaySpendDate", "")
	Set long = ..NewSession(170000)
	Set longOwner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Data.ConversationLink).Point(longOwner, "ChatAgent", long), "a link names a session of 170,000 characters")
	Set cases = $ListBuild($ListBuild("a flagged turn that continues", longOwner, 80), $ListBuild("an unflagged turn that continues", owner, 60), $ListBuild("a flagged first turn", "", 60))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $List(case, 1)_": "
		Set request = ..NewRequest("turn", "user")
		Set request.OwnerRef = $Select($List(case, 2) = "": ##class(OcuTalon.Bridge.Ids).NewRef(), 1: $List(case, 2))
		If $List(case, 1) [ "first" Set request.Input = $Translate($Justify("", 170000), " ", "a")
		Kill ^||ZzDecideCalls, ^||ZzProbeSink
		Set process = ..NewRecorder()
		Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
		Set process.HostSinkClass = ..#SINK
		Set process.TimerSeconds = 60
		Set process.DecisionTokenBudget = 0
		Set process.RequestTokenLimit = 100000
		Set process.%SessionId = 4254
		Do $$$AssertStatusOK(process.OnRequest(request, .response), label_"OnRequest sends the request")
		Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer"), "1|1", label_"one send and one timer")
		Do $$$AssertEquals($ListGet($Get(^||ZzDecideCalls("send", 1)), 7), +(($List(case, 3) = 80) || ($List(case, 1) [ "first")), label_"the sent request's Compact")
		Do $$$AssertEquals($List(^||ZzDecideCalls("timer", 1), 1)_"|"_$List(^||ZzDecideCalls("timer", 1), 2), $List(case, 3)_"|timer", label_"the timer is "_$List(case, 3)_" seconds")

		// the key resend: the seconds left are counted from the same total
		Kill ^||ZzDecideCalls
		Set process.%TimeCreated = ..Ago(3)
		Set process.DecisionRef = request.DecisionRef
		Set response = ""
		Do $$$AssertStatusOK(process.OnResponse(request, .response, "", "", "resend"), label_"the key resend is answered")
		Set left = $List($Get(^||ZzDecideCalls("timer", 1)), 1)
		Do $$$AssertTrue((left '> ($List(case, 3) - 3)) && (left '< ($List(case, 3) - 4)), label_"it sets the timer for the seconds left of "_$List(case, 3)_": "_left)
	}
}

/// The limit that a flagged turn is judged on (Story 30.1; AD-8, AD-20, NFR-3): a turn that is flagged (its estimate is above 40,000 tokens) and continues
/// a linked conversation is too_large only when the request that the runner will send after compaction would pass the limit: its characters with the stored
/// history counted as the least of the history and 80,000 characters. Every other request keeps the full estimate, and the estimate that Precheck gives
/// back (the flag and the token budget) is the full one.
Method TestFlaggedBound()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set agent = $ClassMethod("OcuTalon.Bridge.RequestSize", "AgentChars", "OcuTalon.Agent.Chat")
	Set seedChars = $Parameter("OcuTalon.Bridge.Compaction", "SEEDCHARS")
	Do ..PutKey("ChatAgent")
	Do ..Unmark()
	Do ..Put("Decide", "DailyCostCapUSD", 0)
	Do ..Put("Decide", "GatewaySpendUSD", "")
	Do ..Put("Decide", "GatewaySpendDate", "")
	// $ListBuild(label, history characters (0 for no link), input characters, session mode, limit, reason expected)
	Set cases = $ListBuild(
		$ListBuild("a history of 170,000 characters and a short input", 170000, 100, "", 41000, ""),
		$ListBuild("the same with the limit below the bound", 170000, 100, "", 21000, "too_large"),
		$ListBuild("a history of 60,000 characters (below the seed) and an input of 110,000", 60000, 110000, "", 41000, "too_large"),
		$ListBuild("the same with a limit that holds the full estimate", 60000, 110000, "", 60000, ""),
		$ListBuild("a history of 100,000 and an input of 170,000: the seed and the input pass", 100000, 170000, "", 41000, "too_large"),
		$ListBuild("an owner with no link and an input of 170,000", 0, 170000, "", 41000, "too_large"),
		$ListBuild("a fresh turn of an owner with a history of 170,000, short", 170000, 100, "fresh", 41000, ""),
		$ListBuild("a fresh turn of an owner with a history of 170,000 and an input of 170,000", 170000, 170000, "fresh", 41000, "too_large"),
		$ListBuild("a turn that is not flagged (a short history and input) under a small limit", 8000, 100, "", 1000, "too_large"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set label = $List(case, 1)_": "
		Set request = ..NewRequest("turn", "user")
		Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		If $List(case, 2) Do ##class(OcuTalon.Bridge.Data.ConversationLink).Point(request.OwnerRef, "ChatAgent", ..NewSession($List(case, 2)))
		Set request.Input = $Translate($Justify("", $List(case, 3)), " ", "a")
		Set request.SessionMode = $List(case, 4)
		Set full = $ClassMethod(decide, "EstimateTokens", request, "ChatAgent", , .sc, .history, .chars)
		Set reason = $ClassMethod(decide, "Precheck", request, "ChatAgent", 0, $List(case, 5), .estimate)
		Do $$$AssertEquals(estimate, full, label_"the estimate that Precheck gives back is the full one: "_full)
		Set flagged = full > 40000
		Set bound = $Select(flagged: ##class(OcuTalon.Bridge.Adapter.StepBuffer).Tokens(chars - history + $Select(history < seedChars: history, 1: seedChars)), 1: full)
		Do $$$AssertEquals(reason, $Select(bound > $List(case, 5): "too_large", 1: ""), label_"too_large exactly when the bound, "_bound_" tokens, passes the limit "_$List(case, 5))
		Do $$$AssertEquals(reason, $List(case, 6), label_"the reason is '"_$List(case, 6)_"'")
	}
	Do $$$AssertEquals($ClassMethod(decide, "EstimateTokens", ..NewRequest("decide"), "TriageAgent", , , .none, .noneChars), $ClassMethod("OcuTalon.Bridge.Adapter.StepBuffer", "Tokens", noneChars), "EstimateTokens gives the characters of the whole estimate")
	Do $$$AssertEquals(none, 0, "and no history for a decide")
}

/// RequestLimit (Story 30.1) is the one normalization of the RequestTokenLimit text, for Precheck and the runner: a whole number from 1 to 100000 is the
/// limit, an empty text is 100000 with no warning, any other text is 100000 with a warning that names the setting. It is pure.
Method TestRequestLimit()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set cases = $ListBuild($ListBuild("", 100000, 0), $ListBuild("5000", 5000, 0), $ListBuild("100000", 100000, 0), $ListBuild("1", 1, 0), $ListBuild("0", 100000, 1), $ListBuild("-1", 100000, 1), $ListBuild("abc", 100000, 1), $ListBuild("100001", 100000, 1), $ListBuild("1.5", 100000, 1))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set limit = $ClassMethod(decide, "RequestLimit", $List(case, 1), .warning)
		Do $$$AssertEquals(limit, $List(case, 2), "RequestLimit '"_$List(case, 1)_"' is "_$List(case, 2))
		Do $$$AssertEquals(warning '= "", $List(case, 3), "with "_$Select($List(case, 3): "a warning", 1: "no warning"))
		If $List(case, 3) Do $$$AssertTrue(warning [ "RequestTokenLimit", "that names the setting")
	}
	Do $$$AssertEquals($ClassMethod(decide, "RequestLimit"), 100000, "no argument is 100000")
}

/// ResendDelay is pure (AD-8, FR-4, NFR-23). For rate_limited with no tool run: 1, 2, 4 and 8 seconds for 0, 1, 2 and 3 re-sends so far, and 8
/// beyond; with less than 2000 ms left, 0; the delay is cut to (ms left - 1000) \ 1000, so that the last re-send keeps a second before the timer.
/// Every other reason, a tool that ran and a missing argument give 0.
Method TestResendDelay()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set expected = $ListBuild(1, 2, 4, 8, 8, 8)
	Set resends = $ListBuild(0, 1, 2, 3, 4, 9)
	For i = 1:1:$ListLength(resends) {
		Do $$$AssertEquals($ClassMethod(decide, "ResendDelay", "rate_limited", 0, $List(resends, i), 60000), $List(expected, i), "after "_$List(resends, i)_" re-sends with 60000 ms left the back-off is "_$List(expected, i))
	}
	Do $$$AssertEquals($ClassMethod(decide, "ResendDelay", "rate_limited", 0, 0, 1999), 0, "with 1999 ms left there is no re-send")
	Do $$$AssertEquals($ClassMethod(decide, "ResendDelay", "rate_limited", 0, 0, 2000), 1, "with 2000 ms left the first back-off of 1 s fits")
	Do $$$AssertEquals($ClassMethod(decide, "ResendDelay", "rate_limited", 0, 0, 2500), 1, "and so it does with 2500")
	Do $$$AssertEquals($ClassMethod(decide, "ResendDelay", "rate_limited", 0, 0, 0), 0, "with nothing left there is none")
	Do $$$AssertEquals($ClassMethod(decide, "ResendDelay", "rate_limited", 0, 3, 5000), 4, "a back-off of 8 s is cut to 4 with 5000 ms left, so that the re-send keeps a second")
	Do $$$AssertEquals($ClassMethod(decide, "ResendDelay", "rate_limited", 0, 2, 3000), 2, "4 is cut to 2 with 3000 ms left")
	Do $$$AssertEquals($ClassMethod(decide, "ResendDelay", "rate_limited", 0, 1, 3000), 2, "and 2 is not cut")
	Do $$$AssertEquals($ClassMethod(decide, "ResendDelay", "rate_limited", 0, 6, 120000), 8, "the back-off never passes RESENDMAX with a lot of time left")
	Do $$$AssertEquals($ClassMethod(decide, "ResendDelay", "rate_limited", 1, 0, 60000), 0, "a tool that ran is never sent again")
	Do $$$AssertEquals($ClassMethod(decide, "ResendDelay", "rate_limited", "1", 3, 60000), 0, "whatever the re-sends so far")
	For reason = "error", "timeout", "", "no_key", "daily_cap", "budget", "too_large", "refusal", "cut_off", "empty", "invalid", "unusable" {
		Do $$$AssertEquals($ClassMethod(decide, "ResendDelay", reason, 0, 0, 60000), 0, "the reason '"_reason_"' is not sent again")
	}
	Do $$$AssertEquals($ClassMethod(decide, "ResendDelay", "rate_limited"), 0, "no other argument gives 0")

	// the last re-send keeps at least a second before the timer, and the delay is a whole number of seconds
	Set bad = ""
	For left = 2000:500:61000 {
		For sent = 0:1:12 {
			Set delay = $ClassMethod(decide, "ResendDelay", "rate_limited", 0, sent, left)
			If (delay '? 1.N) || (delay < 1) || (delay > 8) || ((left - (delay * 1000)) < 1000) Set bad = bad _ $ListBuild(left_"/"_sent_"="_delay)
		}
	}
	Do $$$AssertEquals($ListToString(bad, " "), "", "with 2000 ms or more left every delay is a whole number of 1 to 8 seconds that leaves a second")
}

/// OnResponse for the key resend prechecks the request again with the token budget and the request-size limit of OnRequest (AD-8, AD-20): a missing key,
/// a token budget that the estimate is over, a daily cap that is reached and a request-size limit that the estimate is over are recorded as fallbacks
/// (no_key, budget, daily_cap, too_large) and nothing is sent, and the day is marked capped, once, by the daily_cap one. With less than a second of the timer left it records rate_limited and sends nothing. In
/// each case Resends is unchanged and the row carries the steps of the earlier attempts. (A re-send that passes sends a request, which only a
/// production can do: Test.Agent.Decide.TestRateLimitedResent.)
Method TestResendPrecheck()
{
	Set today = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())
	Set cases = $ListBuild("no_key", "budget", "daily_cap", "too_large", "rate_limited")
	For i = 1:1:$ListLength(cases) {
		Set reason = $List(cases, i)
		Set label = "a re-send that is "_reason_": "
		Do ..PutKey("TriageAgent")
		Do ..Unmark()
		Do ..Put("Decide", "DailyCostCapUSD", 0)
		Do ..Put("Decide", "GatewaySpendUSD", "")
		Do ..Put("Decide", "GatewaySpendDate", "")
		Kill ^||ZzProbeSink
		Set process = ..NewProcess()
		Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
		Set process.HostSinkClass = ..#SINK
		Set process.%SessionId = 4249
		Set process.%TimeCreated = ..Ago(3)
		Set process.TimerSeconds = 60
		Set process.DecisionTokenBudget = 0
		Set process.RequestTokenLimit = 100000
		Set process.StepCount = 3
		Set ref = ..NewUsageRef()
		Set process.DecisionRef = ref
		If reason = "no_key" Do ..Put("TriageAgent", "ProviderConfig", "{}")
		If reason = "budget" Set process.DecisionTokenBudget = 1
		If reason = "too_large" Set process.RequestTokenLimit = 1
		If reason = "daily_cap" {
			Do ..Put("Decide", "DailyCostCapUSD", 1)
			Do ..Put("Decide", "GatewaySpendUSD", 1)
			Do ..Put("Decide", "GatewaySpendDate", today)
			Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(today)), 0, label_"control: the day is not marked yet")
		}
		If reason = "rate_limited" {
			Set process.TimerSeconds = 12
			Set process.%TimeCreated = ..Ago(20)
		}
		Set request = ..NewRequest("decide")
		Set response = ""
		Set sc = process.OnResponse(request, .response, "", "", "resend")
		Do $$$AssertStatusOK(sc, label_"it is answered with status OK, and nothing is sent: a send from this process would be an error")
		Set row = ..RowOf(request.ItemId, "decide")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).FallbackProblems(response, row, "decide", reason), "", label_"a tellnow fallback with that reason, in the answer, its XML and the row")
		If $IsObject(row) Do $$$AssertEquals(row.Ref_"|"_row.AgentStepCount_"|"_row.TraceSessionId, ref_"|3|4249", label_"with the DecisionRef of the process, the steps of the earlier attempts and its session")
		Do $$$AssertEquals(process.Resends, 0, label_"and Resends is unchanged")
		If reason = "daily_cap" {
			Do $$$AssertTrue($Data(^OcuTalonBP.UsageCapped(today)) > 0, label_"the day is marked capped")
			Do $$$AssertEquals(..SinkTypes(), "decision.recorded,budget.capped", label_"with decision.recorded and then one budget.capped")
		} Else {
			Do $$$AssertEquals(..SinkTypes(), "decision.recorded", label_"one decision.recorded")
		}
		Do ..RestoreRows()
	}
}

/// A re-send whose estimate is above the request-size limit sends nothing (Story 1.9; AD-1, AD-8, AD-20, NFR-3), for a decide and for a user turn. With the
/// recorder (Test.Bridge.ZzDecide) the key resend of a process whose limit is the estimate sends one request to the runner and sets one timer (Resends 1,
/// no row, nothing answered); with the limit one token below the estimate it sends no request and sets no timer, leaves Resends at 0, records a tellnow
/// fallback with the reason too_large for the DecisionRef of the process (every guarantee of a fallback, in the answer, its XML and the row), answers with
/// a DecisionResponse or a Reply with no text, and fires one decision.recorded.
Method TestResendTooLargeSendsNothing()
{
	For case = $ListBuild("decide", "untrusted", "TriageAgent"), $ListBuild("turn", "user", "ChatAgent") {
		Set kind = $List(case, 1)
		Set runner = $List(case, 3)
		Set label = "the re-send of a "_$List(case, 2)_" "_kind_": "
		Do ..PutKey(runner)
		Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set request = ..NewRequest(kind, $List(case, 2))
		If kind = "turn" Set request.OwnerRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set estimate = $ClassMethod("OcuTalon.Bridge.Process.Decide", "EstimateTokens", request, runner)

		// the limit at the estimate: the request is sent again
		Set process = ..ResendRecorder(60, 3, ref)
		Set process.RequestTokenLimit = estimate
		Set response = ""
		Set sc = process.OnResponse(request, .response, "", "", "resend")
		Do $$$AssertStatusOK(sc, label_"control: with the limit at the estimate, "_estimate_" tokens, the key resend is answered with status OK")
		Do $$$AssertEquals(response, "", label_"control: and nothing is answered")
		Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer")_"|"_process.Resends_"|"_..Rows(request.ItemId), "1|1|1|0", label_"control: one request is sent to the runner and one timer is set, with no row")

		// one token below the estimate: nothing is sent
		Set process = ..ResendRecorder(60, 3, ref)
		Set process.RequestTokenLimit = estimate - 1
		Set response = ""
		Set sc = process.OnResponse(request, .response, "", "", "resend")
		Do $$$AssertStatusOK(sc, label_"with the limit one token below the estimate the key resend is answered with status OK")
		Set row = ..RowOf(request.ItemId, kind)
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).FallbackProblems(response, row, kind, "too_large"), "", label_"a tellnow fallback with the reason too_large, in the answer, its XML and the row")
		If $IsObject(row) Do $$$AssertEquals(row.Ref_"|"_row.TraceSessionId, ref_"|4253", label_"the row has the DecisionRef and the session of the process")
		If (kind = "turn") && $IsObject(response) Do $$$AssertEquals(response.Text_"|"_response.Tainted_"|"_response.ToolsRun_"|"_response.SessionRotated_"|"_response.SessionBroken_"|"_response.Busy, "|0|0|0|0|0", label_"the Reply has no text and sets no flag")
		Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer")_"|"_process.Resends, "0|0|0", label_"no request is sent, no timer is set and Resends is unchanged")
		Do $$$AssertEquals(..SinkTypes(), "decision.recorded", label_"one decision.recorded")
		Do ..RestoreRows()
	}
}

/// OnResponse wires the re-send (AD-8, AD-9, FR-4), with the timers and the sends of the process recorded instead of made (Test.Bridge.ZzDecide):
///   - the key reply with a rate limit, no tool run and time left adds the attempt's steps to StepCount and sets the back-off as a timer with the
///     key resend and no controlled key: 1 s before the first re-send, 4 s after two. It answers nothing, records no row and sends nothing;
///   - the same reply with less than 2 s of the timer left is concluded at once as a rate_limited fallback, with no timer;
///   - the key resend, with a precheck that passes, sends a clone of the request that carries the DecisionRef of the process to the runner of
///     the kind (TriageAgent for a decide request) with the key reply, adds 1 to Resends and sets the timer for the whole seconds left with the
///     key timer and the default controlled keys; the request itself is not changed, and nothing is answered.
Method TestResendWiring()
{
	For case = $ListBuild(0, "1|resend|"), $ListBuild(2, "4|resend|") {
		Set resends = $List(case, 1)
		Set label = "after "_resends_" re-sends: "
		Kill ^||ZzDecideCalls
		Set process = ..NewRecorder()
		Set process.TimerSeconds = 60
		Set process.%TimeCreated = ..Ago(1)
		Set process.Resends = resends
		Set process.StepCount = 1
		Set request = ..NewRequest("turn", "user")
		Set sent = request.%ConstructClone()
		Set sent.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
		Set failed = ..NewReply("")
		Set failed.FailureText = ..#OVERLOADED
		Set failed.AgentStepCount = 2
		Set response = ""
		Set sc = process.OnResponse(request, .response, sent, failed, "reply")
		Do $$$AssertStatusOK(sc, label_"a rate limit with no tool run and time left is answered with status OK")
		Do $$$AssertEquals(response, "", label_"and nothing is answered yet")
		Do $$$AssertEquals(process.StepCount_"|"_process.Resends, "3|"_resends, label_"the 2 steps of the attempt are added to the 1 of the earlier ones, and nothing is sent again yet")
		Do $$$AssertEquals(..Calls("timer")_"|"_..CallOf("timer", 1), "1|"_$List(case, 2), label_"one timer is set: the back-off, the key resend and no controlled key")
		Do $$$AssertEquals(..Calls("send"), 0, label_"and nothing is sent")
		Do $$$AssertEquals(..Rows(request.ItemId), 0, label_"and no row is recorded")
	}

	// with less than 2 s of the timer left the reply is concluded at once
	Kill ^||ZzDecideCalls, ^||ZzProbeSink
	Set process = ..NewRecorder()
	Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set process.HostSinkClass = ..#SINK
	Set process.%SessionId = 4250
	Set process.TimerSeconds = 60
	Set process.%TimeCreated = ..Ago(59)
	Set request = ..NewRequest("turn", "user")
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set failed = ..NewReply("")
	Set failed.FailureText = ..#OVERLOADED
	Set response = ""
	Set sc = process.OnResponse(request, .response, sent, failed, "reply")
	Do $$$AssertStatusOK(sc, "a rate limit with under 2 s of the timer left is concluded")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason, 1: "none"), "1|rate_limited", "as a rate_limited fallback")
	Do $$$AssertEquals(..Calls("timer")_"|"_..Calls("send")_"|"_..Rows(request.ItemId), "0|0|1", "with no timer, no send and one row")

	// the key resend
	Do ..PutKey("TriageAgent")
	Do ..Unmark()
	Do ..Put("Decide", "DailyCostCapUSD", 0)
	Do ..Put("Decide", "GatewaySpendUSD", "")
	Do ..Put("Decide", "GatewaySpendDate", "")
	Kill ^||ZzDecideCalls
	Set process = ..NewRecorder()
	Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set process.HostSinkClass = ..#SINK
	Set process.%SessionId = 4251
	Set process.TimerSeconds = 60
	Set process.%TimeCreated = ..Ago(3.5)
	Set process.DecisionTokenBudget = 0
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set process.DecisionRef = ref
	Set request = ..NewRequest("decide")
	Set response = ""
	Set sc = process.OnResponse(request, .response, "", "", "resend")
	Do $$$AssertStatusOK(sc, "the key resend is answered with status OK")
	Do $$$AssertEquals(response, "", "and nothing is answered")
	Do $$$AssertEquals(process.Resends, 1, "Resends is 1")
	Do $$$AssertEquals(..Calls("send")_"|"_..CallOf("send", 1), "1|TriageAgent|"_ref_"|1|reply|"_request.ItemId_"||0", "one request is sent to TriageAgent with the DecisionRef of the process, a response required and the key reply, and its Compact flag 0")
	Do $$$AssertEquals(request.DecisionRef, "", "and it is a clone: the request itself is not changed")
	Set timer = $Get(^||ZzDecideCalls("timer", 1))
	Do $$$AssertEquals(..Calls("timer"), 1, "one timer is set")
	Do $$$AssertTrue(($List(timer, 1) '< 55) && ($List(timer, 1) '> 56) && ($List(timer, 1) = (+$List(timer, 1) \ 1)), "for the whole seconds left of the 60, 3.5 of them gone: "_$List(timer, 1))
	Do $$$AssertEquals($List(timer, 2)_"|"_$List(timer, 3), "timer|*", "with the key timer and the default controlled keys")
	Do $$$AssertEquals(..Rows(request.ItemId), 0, "and no row is recorded")
	Do ..RestoreRows()
}

/// The key resend sends the request again only with at least a whole second of the timer left (AD-8, FR-4): with 1.8 s left it sends and sets a
/// timer of 1 s (Resends 1, one send, no row), and with 0.5 s left it records rate_limited at once and sends and sets nothing (Resends 0). The
/// time left is the process's TimerSeconds minus the time since the process began, so the two cases sit on either side of the second. A process
/// whose start cannot be read has no time left: its key resend records rate_limited at once, and a rate-limited reply with no tool run is concluded
/// as a fallback with no timer, because Decide never sends again on a time it cannot measure.
Method TestResendBoundary()
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set process = ..ResendRecorder(12, 10.2, ref)
	Set request = ..NewRequest("decide")
	Set response = ""
	Set sc = process.OnResponse(request, .response, "", "", "resend")
	Do $$$AssertStatusOK(sc, "the key resend with 1.8 s left is answered with status OK")
	Do $$$AssertEquals(response, "", "and nothing is answered")
	Do $$$AssertEquals(process.Resends_"|"_..Calls("send")_"|"_..Calls("timer")_"|"_..Rows(request.ItemId), "1|1|1|0", "the request is sent once, Resends is 1, one timer is set and no row is recorded")
	Set timer = $Get(^||ZzDecideCalls("timer", 1))
	Do $$$AssertEquals($ListGet(timer, 1)_"|"_$ListGet(timer, 2)_"|"_$ListGet(timer, 3), "1|timer|*", "the timer is the 1 whole second that is left, with the key timer and the default controlled keys")
	Do ..RestoreRows()

	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set process = ..ResendRecorder(12, 11.5, ref)
	Set request = ..NewRequest("decide")
	Set response = ""
	Set sc = process.OnResponse(request, .response, "", "", "resend")
	Do $$$AssertStatusOK(sc, "the key resend with 0.5 s left is answered with status OK")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).FallbackProblems(response, row, "decide", "rate_limited"), "", "a rate_limited fallback with every guarantee, in the answer, its XML and the row")
	If $IsObject(row) Do $$$AssertEquals(row.Ref, ref, "with the DecisionRef of the process")
	Do $$$AssertEquals(process.Resends_"|"_..Calls("send")_"|"_..Calls("timer"), "0|0|0", "nothing is sent, no timer is set and Resends is unchanged")
	Do ..RestoreRows()

	// a start that cannot be read: nothing is left
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set process = ..ResendRecorder(12, 0, ref)
	Set process.%TimeCreated = ""
	Set request = ..NewRequest("decide")
	Set response = ""
	Set sc = process.OnResponse(request, .response, "", "", "resend")
	Do $$$AssertStatusOK(sc, "the key resend of a process whose start cannot be read is answered with status OK")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).FallbackProblems(response, row, "decide", "rate_limited"), "", "as a rate_limited fallback with every guarantee, in the answer, its XML and the row")
	Do $$$AssertEquals(process.Resends_"|"_..Calls("send")_"|"_..Calls("timer"), "0|0|0", "with nothing sent and no timer set")
	Do ..RestoreRows()
	Set process = ..NewRecorder()
	Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set process.HostSinkClass = "OcuTalon.Bridge.Ext.HostSink"
	Set process.%SessionId = 4254
	Set process.TimerSeconds = 60
	Set process.%TimeCreated = ""
	Set request = ..NewRequest("turn", "user")
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set failed = ..NewReply("")
	Set failed.FailureText = ..#OVERLOADED
	Kill ^||ZzDecideCalls
	Set response = ""
	Set sc = process.OnResponse(request, .response, sent, failed, "reply")
	Do $$$AssertStatusOK(sc, "a rate limit with no tool run, for a process whose start cannot be read, is concluded")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason, 1: "none"), "1|rate_limited", "as a rate_limited fallback")
	Do $$$AssertEquals(..Calls("timer")_"|"_..Calls("send")_"|"_..Rows(request.ItemId), "0|0|1", "with no back-off timer, no send and one row")
}

/// The steps, the totals and the duration of a decision are those of all its attempts (AD-9, AD-20; the row "A re-send succeeds (live)", where the
/// attempts that failed have no steps). OnResponse for the key reply hands the StepCount that the process holds, the AgentStepCount of its earlier
/// attempts, to Conclude: the row and the answer hold StepCount plus the last reply's AgentStepCount, for a usable turn and for a fallback after a
/// tool ran (a rate limit that is not sent again), with the sums of the Usage rows of the ref, one for each attempt that spent tokens, and a duration
/// from the start of the process. Conclude does the same for a decide request given the steps of the earlier attempts. The process keeps its state.
Method TestStepsAcrossAttempts()
{
	Set expected = "5000|350|2000|700|.012665|claude-sonnet-5-5|5"
	For case = $ListBuild("a usable turn", 0, "Everything is fine."), $ListBuild("a rate limit after a tool ran", 1, "") {
		Set label = $List(case, 1)_" after 2 steps of earlier attempts: "
		Kill ^||ZzProbeSink
		Set process = ..NewProcess()
		Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
		Set process.HostSinkClass = ..#SINK
		Set process.%SessionId = 4252
		Set process.%TimeCreated = ..Ago(5)
		Set process.TimerSeconds = 60
		Set process.Resends = 2
		Set process.StepCount = 2
		Set request = ..NewRequest("turn", "user")
		Set ref = ..NewUsageRef()
		Do ..AddUsage(ref, "claude-haiku-5-5", 3800, 300, 2000, 600, .000365)
		Do ..AddUsage(ref, "claude-sonnet-5-5", 1200, 50, 0, 100, .0123)
		Set sent = request.%ConstructClone()
		Set sent.DecisionRef = ref
		Set reply = ..NewReply($List(case, 3))
		Set reply.AgentStepCount = 3
		If $List(case, 2) {
			Set reply.FailureText = ..#OVERLOADED
			Set reply.ToolsRun = 1
		}
		Set response = ""
		Set sc = process.OnResponse(request, .response, sent, reply, "reply")
		Do $$$AssertStatusOK(sc, label_"the runner's reply is concluded")
		Set row = ..RowOf(request.ItemId, "turn")
		If '$IsObject(row) || '$IsObject(response) {
			Do $$$AssertTrue(0, label_"a row is recorded and an answer is given")
			Continue
		}
		Do $$$AssertEquals(row.Ref_"|"_row.Fallback_"|"_row.FallbackReason, ref_"|"_$List(case, 2)_"|"_$Select($List(case, 2): "rate_limited", 1: ""), label_"the row has the DecisionRef of the runner's request, and is a fallback only for the rate limit")
		Do $$$AssertEquals($Piece(..Totals(row), "|", 1, 7), expected, label_"its steps are the 2 of the earlier attempts and the 3 of the last reply, with the sums of both Usage rows")
		Do $$$AssertEquals($Piece(..Totals(response), "|", 1, 7), expected, label_"and so are the answer's")
		Do $$$AssertTrue((row.DurationMs '< 5000) && (row.DurationMs < 60000), label_"the duration runs from the start of the process: "_row.DurationMs)
		Do $$$AssertEquals(response.DurationMs, row.DurationMs, label_"and the answer carries the same")
		Do $$$AssertEquals(process.StepCount_"|"_process.Resends, "2|2", label_"the process keeps its state")
		Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, label_"one event is sent")
	}

	// a decide request: Conclude adds the steps of the earlier attempts to the reply's
	Set request = ..NewRequest("decide")
	Set ref = ..NewUsageRef()
	Set reply = ..NewReply(..#DIGEST)
	Set reply.AgentStepCount = 3
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ref, reply, ..#REPLYCLASS, "OcuTalon.Bridge.Ext.ReplyFilter", "OcuTalon.Bridge.Ext.HostSink", 4252, .response, 4321, "", 2)
	Do $$$AssertStatusOK(sc, "a decide with 2 steps of earlier attempts is concluded")
	Set row = ..RowOf(request.ItemId, "decide")
	If $IsObject(row) && $IsObject(response) {
		Do $$$AssertEquals(..Totals(row), "||||||5|4321", "its row holds 5 steps: the 2 of the earlier attempts and the 3 of the reply, and the duration given")
		Do $$$AssertEquals(..Totals(response), "||||||5|4321", "and so does the answer")
	} Else {
		Do $$$AssertTrue(0, "a row is recorded and an answer is given")
	}
}

/// The Positions of a decision's steps run on across its attempts (AD-9): OnResponse for the key reply sends each step record of the runner's reply to
/// AgentSteps, numbered after the steps already sent (StepsSent), and then weighs the re-send. With the sends of the process recorded (Test.Bridge.ZzDecide),
/// a rate-limited reply with two step records (a reply with steps and no tool, which only an in-process reply can be) sends the Positions 1 and 2 and sets
/// the back-off timer; the reply of the next attempt, with one record, sends the Position 3. StepsSent and StepCount are 2 after the first and 3 after the
/// second. A third reply whose records are a number and a step sends that step as Position 5, warns that Step 4 is not a step record, and leaves
/// StepsSent at 5, so that a later attempt cannot repeat a Position. Nothing is answered.
Method TestStepPositionsAcrossResends()
{
	Kill ^||ZzDecideCalls
	Set process = ..NewRecorder()
	Set process.TimerSeconds = 60
	Set process.%TimeCreated = ..Ago(1)
	Set request = ..NewRequest("turn", "user")
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set one = "{""kind"":""model"",""label"":""Model request"",""summary"":""A step."",""durationMs"":5,""status"":""ok"",""estimatedTokens"":10}"
	Set sentSoFar = 0
	For attempt = 1, 2 {
		Set label = "attempt "_attempt_": "
		Set records = $Select(attempt = 1: 2, 1: 1)
		Set failed = ..NewReply("")
		Set failed.FailureText = ..#OVERLOADED
		Set failed.AgentStepCount = records
		Set failed.Steps = $Select(attempt = 1: "["_one_","_one_"]", 1: "["_one_"]")
		Set response = ""
		Set sc = process.OnResponse(request, .response, sent, failed, "reply")
		Do $$$AssertStatusOK(sc, label_"the rate-limited reply is answered with status OK")
		Do $$$AssertEquals(response, "", label_"and nothing is answered")
		Do $$$AssertEquals(..Calls("send"), sentSoFar + records, label_"each step record is sent: "_(sentSoFar + records)_" sends in all")
		Set positions = ""
		Set targets = ""
		For n = sentSoFar + 1:1:sentSoFar + records {
			Set call = $Get(^||ZzDecideCalls("send", n))
			Set targets = targets _ $Select(targets = "": "", 1: ",") _ $List(call, 1)
			Set positions = positions _ $Select(positions = "": "", 1: ",") _ $ListGet(call, 6)
		}
		Do $$$AssertEquals(targets, $Select(attempt = 1: "AgentSteps,AgentSteps", 1: "AgentSteps"), label_"to AgentSteps")
		Do $$$AssertEquals(positions, $Select(attempt = 1: "1,2", 1: "3"), label_"with the Positions that follow the steps sent before")
		Do $$$AssertEquals(process.StepsSent_"|"_process.StepCount, (sentSoFar + records)_"|"_(sentSoFar + records), label_"StepsSent and StepCount count them")
		Do $$$AssertEquals(..Calls("timer")_"|"_..CallOf("timer", attempt), attempt_"|1|resend|", label_"one back-off timer is set for each attempt, with the key resend and no controlled key")
		Set sentSoFar = sentSoFar + records
	}
	// a record that is no object keeps its slot: the warning names it by its Position, and StepsSent is the Position of the last step sent
	Set mark = ..LogMark()
	Set failed = ..NewReply("")
	Set failed.FailureText = ..#OVERLOADED
	Set failed.AgentStepCount = 1
	Set failed.Steps = "[7,"_one_"]"
	Do $$$AssertStatusOK(process.OnResponse(request, .response, sent, failed, "reply"), "attempt 3: a reply whose first record is no object is answered with status OK")
	Do $$$AssertEquals(..Calls("send")_"|"_$ListGet($Get(^||ZzDecideCalls("send", 4)), 6), "4|5", "attempt 3: its one step is sent with the Position of its slot, 5")
	Do $$$AssertEquals(process.StepsSent, 5, "and StepsSent is that Position, so the next attempt starts at 6 and no Position repeats")
	// the event log names the class of the process ($classname()), the recorder's here
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, process.%ClassName(1), "StepMessages", $ListBuild(sent.DecisionRef, "Step 4 of the decision "_sent.DecisionRef_" is not a step record")), 1, "the skipped record is a warning that names it by its Position, 4")
	Do $$$AssertEquals(..Rows(request.ItemId), 0, "no row is recorded")
}

/// A Busy answer (Story 1.8; AD-6, AD-20, AD-31). OnResponse answers a runner Reply whose Busy is 1 with a new Reply from NewBusy: Busy 1 and nothing
/// else, status OK, with no Decision row, no event and no state kept, although nothing in it is usable. OnRequest probes the conversation lock of a user's
/// turn, (OwnerRef, ChatAgent), before the DecisionRef, the precheck and a row: while another process holds it, the answer is the same Busy reply after the
/// lock's 2 seconds, and nothing else happens (the precheck would otherwise end this turn in a no_key fallback, as ChatAgent has no key here). An untrusted turn
/// of the same owner (its SessionMode fresh or not), and a decide or diagnose request, are never probed, and Held is 0 once the lock is free.
Method TestBusyRelayed()
{
	Set class = "OcuTalon.Bridge.Msg.Reply"
	Set process = ..NewProcess()
	Set process.ReplyFilterClass = ..#FILTER
	Set process.HostSinkClass = ..#SINK
	Set process.%SessionId = 4260
	Kill ^||ZzProbeSink, ^||ZzProbeFilter
	Set request = ..NewRequest("turn", "user")
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set busy = ##class(OcuTalon.Bridge.Msg.Reply).NewBusy()
	Do $$$AssertEquals(busy.Busy_"|"_busy.Text_"|"_busy.DecisionRef_"|"_busy.Fallback_"|"_busy.FailureText, "1|||0|", "NewBusy is a Reply with Busy 1 and nothing else set")
	Set sc = process.OnResponse(request, .response, sent, busy, "reply")
	Do $$$AssertStatusOK(sc, "the runner's Busy reply is answered, never with an error status")
	Do $$$AssertTrue($IsObject(response) && response.%IsA(class), "the answer is a Reply")
	If $IsObject(response) {
		Do $$$AssertTrue(response '= busy, "a new one, not the runner's")
		Do $$$AssertEquals(response.Busy, 1, "with Busy 1")
		Do $$$AssertEquals(response.Text_"|"_response.DecisionRef_"|"_response.Outcome_"|"_response.FallbackReason_"|"_response.FailureText_"|"_response.Steps_"|"_response.HostData, "||||||", "and no text, DecisionRef, outcome, reason, failure text, steps or host data")
		Do $$$AssertEquals(response.Fallback_"|"_response.Tainted_"|"_response.ToolsRun_"|"_response.SessionRotated_"|"_response.SessionBroken, "0|0|0|0|0", "it is not a fallback and carries no other flag")
	}
	Do $$$AssertEquals(..Rows(request.ItemId), 0, "no Decision row is recorded")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "no event is sent")
	Do $$$AssertEquals(+$Get(^||ZzProbeFilter), 0, "and the filter did not run")
	Do $$$AssertStatusOK(process.RunnerError, "no runner error is kept")
	Do $$$AssertEquals(process.Resends_"|"_process.StepCount_"|"_process.StepsSent, "0|0|0", "and the process keeps no state of a re-send")

	// the probe of OnRequest, with the lock held by another process
	Do ..Put("ChatAgent", "ProviderConfig", "{}")
	Do ..Unmark()
	Do ..Put("Decide", "DailyCostCapUSD", 0)
	Set process = ..NewProcess()
	Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set process.HostSinkClass = ..#SINK
	Set process.TimerSeconds = 60
	Set process.DecisionTokenBudget = 0
	Set process.%SessionId = 4261
	Kill ^||ZzProbeSink
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set turn = ..NewRequest("turn", "user")
	Set turn.OwnerRef = owner
	Set untrusted = ..NewRequest("turn", "untrusted")
	Set untrusted.OwnerRef = owner
	Set freshUntrusted = ..NewRequest("turn", "untrusted")
	Set freshUntrusted.OwnerRef = owner
	Set freshUntrusted.SessionMode = "fresh"
	Set freshUntrusted.SeedText = "A recap that an untrusted turn never gets."
	Set decide = ..NewRequest("decide", "user")
	Set decide.OwnerRef = owner
	Set diagnose = ..NewRequest("diagnose", "user")
	Set diagnose.OwnerRef = owner
	Set stranger = ..NewRequest("turn", "user")
	Do $$$AssertTrue(..StartHolder(owner, "ChatAgent"), "another process holds the conversation lock of (owner, ChatAgent)")
	Try {
		Set logMark = ..LogMark()
		Set started = $ZHorolog
		Set sc = process.OnRequest(turn, .response)
		Set elapsed = $ZHorolog - started
		Do $$$AssertStatusOK(sc, "OnRequest answers a user's turn whose conversation is held")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).WarningRows(logMark, , "OcuTalon.Bridge.Process.Decide"), 0, "a Busy refusal logs no warning")
		Do $$$AssertEquals($Select($IsObject(response): response.%ClassName(1)_"|"_response.Busy_"|"_response.Fallback_"|"_response.DecisionRef_"|"_response.Text, 1: "none"), class_"|1|0||", "with a Busy Reply: not a fallback, no DecisionRef, no text")
		Do $$$AssertTrue((elapsed '< 1.9) && (elapsed < 6), "after the 2 seconds of the lock: "_$Number(elapsed, 2)_" s")
		Do $$$AssertEquals(..Rows(turn.ItemId), 0, "no row is recorded, although the precheck would have recorded a no_key fallback")
		Do $$$AssertEquals(+$Get(^||ZzProbeSink), 0, "no event is sent")
		Do $$$AssertEquals(process.DecisionRef, "", "and no DecisionRef was allocated")

		Set started = $ZHorolog
		Set sc = process.OnRequest(untrusted, .response)
		Set elapsed = $ZHorolog - started
		Do $$$AssertStatusOK(sc, "OnRequest answers an untrusted turn of the same owner")
		Do $$$AssertEquals($Select($IsObject(response): response.%ClassName(1)_"|"_response.Busy_"|"_response.Fallback_"|"_response.FallbackReason, 1: "none"), class_"|0|1|no_key", "not as Busy: it is not probed, so the precheck ends it in a no_key fallback")
		Do $$$AssertTrue(elapsed < 1.5, "and it did not wait: "_$Number(elapsed, 2)_" s")

		Set started = $ZHorolog
		Set sc = process.OnRequest(freshUntrusted, .response)
		Set elapsed = $ZHorolog - started
		Do $$$AssertStatusOK(sc, "OnRequest answers an untrusted turn of the same owner that asks for a fresh session")
		Do $$$AssertEquals($Select($IsObject(response): response.%ClassName(1)_"|"_response.Busy_"|"_response.Fallback_"|"_response.FallbackReason, 1: "none"), class_"|0|1|no_key", "not as Busy either: the SessionMode makes no turn a conversation")
		Do $$$AssertTrue(elapsed < 1.5, "and it did not wait: "_$Number(elapsed, 2)_" s")

		Do $$$AssertEquals(##class(OcuTalon.Bridge.Process.Decide).Held(decide, "ChatAgent"), 0, "Held is 0 for a decide request of the same owner, even against the held lock of (owner, ChatAgent)")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Process.Decide).Held(diagnose, "ChatAgent"), 0, "and for a diagnose request")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Process.Decide).Held(untrusted, "ChatAgent"), 0, "and for an untrusted turn")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Process.Decide).Held(freshUntrusted, "ChatAgent"), 0, "and for an untrusted turn with the SessionMode fresh")
		Set started = $ZHorolog
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Process.Decide).Held(stranger, "ChatAgent"), 0, "Held is 0 for a user's turn of an owner whose conversation is free")
		Do $$$AssertTrue($ZHorolog - started < 1.5, "at once")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Process.Decide).Held(turn, "ChatAgent"), 1, "and 1 for the user's turn whose conversation is held")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do $$$AssertTrue(..StopHolder(owner), "the other process released the lock")
	Set started = $ZHorolog
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Process.Decide).Held(turn, "ChatAgent"), 0, "Held is 0 once the lock is free")
	Set sc = process.OnRequest(turn, .response)
	Do $$$AssertStatusOK(sc, "OnRequest answers the same turn again")
	Do $$$AssertEquals($Select($IsObject(response): response.%ClassName(1)_"|"_response.Busy_"|"_response.Fallback_"|"_response.FallbackReason, 1: "none"), class_"|0|1|no_key", "now past the probe: a no_key fallback, recorded")
	Do $$$AssertEquals(..Rows(turn.ItemId), 1, "with its row")
	Do $$$AssertTrue($ZHorolog - started < 3, "and without waiting")
}

/// SessionBroken (Story 1.8; AD-8). Broken is pure: 1 for a turn with provenance user whose failure text holds "Invalid input", in any case; 0 for an
/// untrusted turn, a decide, a diagnose request, any other text and no text. Conclude and OnResponse answer a user's turn whose failure holds it with
/// an error fallback Reply (the reason stays error) whose SessionBroken is 1; an untrusted turn and a decide with the same text get the reason error
/// and no SessionBroken (a DecisionResponse has none).
Method TestSessionBroken()
{
	Set class = "OcuTalon.Bridge.Process.Decide"
	Set text = ..#INVALIDINPUT
	Do $$$AssertEquals($Parameter(class, "INVALIDINPUTTEXT"), "Invalid input", "the text that marks a rejected history is 'Invalid input'")
	Set user = ..NewRequest("turn", "user")
	Do $$$AssertEquals($ClassMethod(class, "Broken", user, text), 1, "the failure text that AI Hub raised marks a user's turn")
	Do $$$AssertEquals($ClassMethod(class, "Broken", user, "x error: INVALID INPUT: y"), 1, "in upper case too")
	Do $$$AssertEquals($ClassMethod(class, "Broken", user, "x error: invalid input"), 1, "and in lower case")
	Do $$$AssertEquals($ClassMethod(class, "Broken", user, ""), 0, "no text marks nothing")
	Do $$$AssertEquals($ClassMethod(class, "Broken", user, ..#OVERLOADED), 0, "nor does a rate limit")
	Do $$$AssertEquals($ClassMethod(class, "Broken", user, "ERROR <%AICore>ProviderError: Provider 'anthropic' error: invalid_input"), 0, "nor does a look-alike")
	Do $$$AssertEquals($ClassMethod(class, "Broken", ..NewRequest("turn", "untrusted"), text), 0, "an untrusted turn is never broken")
	Do $$$AssertEquals($ClassMethod(class, "Broken", ..NewRequest("decide", "user"), text), 0, "nor is a decide")
	Do $$$AssertEquals($ClassMethod(class, "Broken", ..NewRequest("diagnose", "user"), text), 0, "nor a diagnose request")
	Do $$$AssertEquals($ClassMethod(class, "Broken", "", text), 0, "nor no request")

	Do ..AssertFallback("a user's turn whose stored history the provider rejects", ..NewRequest("turn", "user"), ..NewReply(""), text, "error", , 1)
	Do ..AssertFallback("the same with the failure Reply of the runner", ..NewRequest("turn", "user"), ..FailedReply(text), text, "error", , 1)
	Do ..AssertFallback("an untrusted turn with the same text", ..NewRequest("turn", "untrusted"), ..NewReply(""), text, "error")
	Do ..AssertFallback("a decide with the same text", ..NewRequest("decide", "user"), ..NewReply(""), text, "error")
	Do ..AssertFallback("a diagnose request with the same text", ..NewRequest("diagnose", "untrusted"), ..NewReply(""), text, "error")
	Do ..AssertFallback("a user's turn with another failure", ..NewRequest("turn", "user"), ..NewReply(""), "ERROR <%AICore>ProviderError: Provider 'anthropic' error: API error: [api_error] zz", "error")

	// the wiring: OnResponse takes the failure from the runner's Reply
	Set process = ..NewProcess()
	Set process.ReplyFilterClass = ..#FILTER
	Set process.HostSinkClass = ..#SINK
	Set process.%SessionId = 4262
	Set request = ..NewRequest("turn", "user")
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = process.OnResponse(request, .response, sent, ..FailedReply(text), "reply")
	Do $$$AssertStatusOK(sc, "OnResponse answers a failure Reply that holds the rejection")
	Do $$$AssertEquals($Select($IsObject(response): response.%ClassName(1)_"|"_response.Fallback_"|"_response.FallbackReason_"|"_response.SessionBroken_"|"_response.Busy, 1: "none"), "OcuTalon.Bridge.Msg.Reply|1|error|1|0", "with an error fallback Reply that says SessionBroken")
	Do $$$AssertEquals($Select($IsObject(..RowOf(request.ItemId, "turn")): ..RowOf(request.ItemId, "turn").FallbackReason, 1: "none"), "error", "the row is recorded like any fallback, with the reason error")
	Do $$$AssertEquals(process.Resends, 0, "and Decide did not send again")
	Set later = ..NewRequest("turn", "untrusted")
	Set sent = later.%ConstructClone()
	Set sent.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = process.OnResponse(later, .response, sent, ..FailedReply(text), "reply")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason_"|"_response.SessionBroken, 1: "none"), "1|error|0", "an untrusted turn with the same failure: the reason error and no SessionBroken")
}

/// A fallback moves no link (Story 17.8; AD-6, AD-8), so RecordFallback always answers SessionRotated 0, whatever the runner's reply says, and carries the
/// runner's Tainted and ToolsRun. A fallback with no runner reply (a precheck, or the timer) sets none of them; SessionBroken is set only when RecordFallback
/// is told (Broken). A usable answer is a clone of the runner's reply and keeps the other flags, with the SessionRotated of Decide and no session fields.
Method TestFallbackMovesNothing()
{
	Set class = "OcuTalon.Bridge.Process.Decide"
	Set sink = "OcuTalon.Bridge.Ext.HostSink"
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set s1 = ..NewSession(10)
	Set s2 = ..NewSession(10)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Data.ConversationLink).Point(owner, "ChatAgent", s1), "a link names the session S1 for (owner, ChatAgent)")
	Set request = ..NewRequest("turn", "user")
	Set request.OwnerRef = owner
	Set request.SessionMode = "fresh"
	Set reply = ..NewReply("zzrefusedtext I cannot help with that.", "refusal")
	Set reply.SessionRotated = 1
	Set reply.SessionId = s2
	Set reply.SessionFrom = s1
	Set reply.Tainted = 1
	Set reply.ToolsRun = 1
	Set sc = $ClassMethod(class, "RecordFallback", request, ##class(OcuTalon.Bridge.Ids).NewRef(), "refusal", reply, sink, 4263, .response)
	Do $$$AssertStatusOK(sc, "a refusal of a fresh turn is recorded")
	Do $$$AssertEquals(response.SessionRotated_"|"_response.Tainted_"|"_response.ToolsRun_"|"_response.SessionBroken_"|"_response.Busy, "0|1|1|0|0", "the fallback Reply carries Tainted and ToolsRun of the runner's reply, SessionRotated 0, and says neither SessionBroken nor Busy")
	Do $$$AssertEquals(response.SessionId_"|"_response.SessionFrom_"|"_response.HistoryCount, "||", "and names no session")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, "ChatAgent"), s1, "the link still names S1: a fallback moves nothing")

	Set request = ..NewRequest("turn", "user")
	Set reply = ..NewReply("zzrefusedtext I cannot help with that.", "refusal")
	Set sc = $ClassMethod(class, "RecordFallback", request, ##class(OcuTalon.Bridge.Ids).NewRef(), "refusal", reply, sink, 4263, .response)
	Do $$$AssertEquals(response.SessionRotated, 0, "a reply that rotated nothing carries 0")

	Set request = ..NewRequest("turn", "user")
	Set sc = $ClassMethod(class, "RecordFallback", request, ##class(OcuTalon.Bridge.Ids).NewRef(), "timeout", "", sink, 4263, .response)
	Do $$$AssertEquals(response.SessionRotated_"|"_response.Tainted_"|"_response.ToolsRun_"|"_response.SessionBroken_"|"_response.Busy, "0|0|0|0|0", "a fallback with no runner reply sets none of the flags")
	Set request = ..NewRequest("turn", "user")
	Set sc = $ClassMethod(class, "RecordFallback", request, ##class(OcuTalon.Bridge.Ids).NewRef(), "error", "", sink, 4263, .response, , , 1)
	Do $$$AssertEquals(response.SessionBroken_"|"_response.SessionRotated, "1|0", "SessionBroken is set when RecordFallback is told that the history was rejected, with no runner reply")
	Set request = ..NewRequest("turn", "user")
	Set reply = ..NewReply("zzrefusedtext I cannot help with that.", "refusal")
	Set reply.SessionRotated = 1
	Set sc = $ClassMethod(class, "RecordFallback", request, ##class(OcuTalon.Bridge.Ids).NewRef(), "error", reply, sink, 4263, .response, , , 1)
	Do $$$AssertEquals(response.SessionBroken_"|"_response.SessionRotated, "1|0", "SessionBroken is carried with SessionRotated 0")

	// the other kinds answer with a DecisionResponse of the row, which has no such flag
	Set request = ..NewRequest("decide", "user")
	Set sc = $ClassMethod(class, "RecordFallback", request, ##class(OcuTalon.Bridge.Ids).NewRef(), "refusal", reply, sink, 4263, .response)
	Do $$$AssertStatusOK(sc, "a decide fallback with such a reply is recorded")
	Do $$$AssertEquals($Select($IsObject(response): response.%ClassName(1), 1: "none"), "OcuTalon.Bridge.Msg.DecisionResponse", "and answered with a DecisionResponse")

	// a usable answer is a clone of the runner's reply
	Set request = ..NewRequest("turn", "user")
	Set reply = ..NewReply("Everything is fine.", "end_turn")
	Set reply.SessionRotated = 1
	Set reply.Tainted = 1
	Set reply.ToolsRun = 1
	Set reply.SessionBroken = 1
	Set sc = ..Conclude(request, reply, .response)
	Do $$$AssertStatusOK(sc, "a usable turn is concluded")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.SessionRotated_"|"_response.Tainted_"|"_response.ToolsRun_"|"_response.SessionBroken_"|"_response.Busy, 1: "none"), "0|0|1|1|1|0", "the answer is a clone that keeps the other flags of the runner's reply, and its SessionRotated is Decide's: 0, because the reply is tainted and moved nothing")
}

/// A turn of the owner for the link tests: a user's turn of the owner with the session mode (empty means continue) and a DecisionRef of its own.
Method PointRequest(owner As %String, mode As %String = "", provenance As %String = "user") As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ..NewRequest("turn", provenance)
	Set request.OwnerRef = owner
	Set request.SessionMode = mode
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Quit request
}

/// A runner's usable reply that names the session it saved (SessionId) and the session the link named when it began (SessionFrom).
ClassMethod PointReply(id As %String, from As %String) As OcuTalon.Bridge.Msg.Reply [ Private ]
{
	Set reply = ..NewReply("An answer.", "end_turn")
	Set reply.SessionId = id
	Set reply.SessionFrom = from
	Quit reply
}

/// PointLink (Story 17.8; AD-6, AD-8), the one place where a link moves, for the first runner ChatAgent: the compare-and-set expects SessionFrom.
///   - an accepted fresh turn moves the link to the new session and says SessionRotated; so does a continue turn that began from a session and names another
///     (a compaction fork, a retry's session);
///   - a continue turn that saved into the session it opened (SessionId is SessionFrom) points nothing and says 0;
///   - the first link of a conversation is created, and says 0 for a continue turn and 1 for a fresh one;
///   - a tainted reply, a reply that names no session and a request that is not a user's turn move nothing;
///   - a link that no longer names SessionFrom is not moved: one warning that names the runner, the OwnerRef and the DecisionRef, status OK, and 0;
///   - a link row that another process holds the lock of makes Point fail: one warning, an error status, 0, and the link as it was. Once the lock is let
///     go the same call moves it.
Method TestPointLink()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set link = "OcuTalon.Bridge.Data.ConversationLink"
	Set agent = "ChatAgent"
	// an accepted fresh turn
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set s1 = ..NewSession(10)
	Set s2 = ..NewSession(10)
	Set s3 = ..NewSession(10)
	Set s4 = ..NewSession(10)
	Do $$$AssertStatusOK($ClassMethod(link, "Point", owner, agent, s1), "the link names S1")
	Set request = ..PointRequest(owner, "fresh")
	Set reply = ..PointReply(s2, s1)
	Set sc = $ClassMethod(decide, "PointLink", request, agent, reply, .rotated)
	Do $$$AssertStatusOK(sc, "PointLink of an accepted fresh turn is OK")
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent)_"|"_rotated, s2_"|1", "the link names the new session S2, and the turn rotated")
	Do $$$AssertEquals(reply.SessionId_"|"_reply.SessionFrom_"|"_reply.SessionRotated, s2_"|"_s1_"|0", "the reply is not changed")

	// a continue turn that saved into the session it opened
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $ClassMethod(link, "Point", owner, agent, s1)
	Set request = ..PointRequest(owner)
	Set sc = $ClassMethod(decide, "PointLink", request, agent, ..PointReply(s1, s1), .rotated)
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent)_"|"_rotated, s1_"|0", "an accepted continue turn that saved in place: the link names S1, no rotation")
	Do $ClassMethod(link, "Point", owner, agent, s3)
	Set sc = $ClassMethod(decide, "PointLink", request, agent, ..PointReply(s1, s1), .rotated)
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent), s3, "and it points nothing: a link that was elsewhere stays where it was")

	// a continue turn that names another session: a fork or a retry's session
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $ClassMethod(link, "Point", owner, agent, s1)
	Set sc = $ClassMethod(decide, "PointLink", ..PointRequest(owner), agent, ..PointReply(s2, s1), .rotated)
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent)_"|"_rotated, s2_"|1", "a continue turn that began from S1 and names S2 moves the link, and rotated")

	// the first link of a conversation
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = $ClassMethod(decide, "PointLink", ..PointRequest(owner), agent, ..PointReply(s1, ""), .rotated)
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent)_"|"_rotated, s1_"|0", "the first link of a continue turn is created, with no rotation")
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set sc = $ClassMethod(decide, "PointLink", ..PointRequest(owner, "fresh"), agent, ..PointReply(s1, ""), .rotated)
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent)_"|"_rotated, s1_"|1", "the first link of a fresh turn is created, and rotated")

	// nothing to accept
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $ClassMethod(link, "Point", owner, agent, s1)
	Set tainted = ..PointReply(s2, s1)
	Set tainted.Tainted = 1
	Set sc = $ClassMethod(decide, "PointLink", ..PointRequest(owner, "fresh"), agent, tainted, .rotated)
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent)_"|"_rotated, s1_"|0", "a tainted reply moves nothing")
	Set sc = $ClassMethod(decide, "PointLink", ..PointRequest(owner, "fresh"), agent, ..PointReply("", s1), .rotated)
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent)_"|"_rotated, s1_"|0", "a reply that names no session moves nothing")
	Set sc = $ClassMethod(decide, "PointLink", ..PointRequest(owner, "fresh", "untrusted"), agent, ..PointReply(s2, s1), .rotated)
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent)_"|"_rotated, s1_"|0", "an untrusted turn is not linked: nothing moves")
	Set decision = ..NewRequest("decide", "user")
	Set decision.OwnerRef = owner
	Set sc = $ClassMethod(decide, "PointLink", decision, agent, ..PointReply(s2, s1), .rotated)
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent)_"|"_rotated, s1_"|0", "and neither is a decide request")

	// a lost compare-and-set
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $ClassMethod(link, "Point", owner, agent, s4)
	Set request = ..PointRequest(owner, "fresh")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set sc = $ClassMethod(decide, "PointLink", request, agent, ..PointReply(s2, s1), .rotated)
	Do $$$AssertStatusOK(sc, "a link that no longer names SessionFrom is no error")
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent)_"|"_rotated, s4_"|0", "it stays where it is, with no rotation")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, decide, "PointLink", $ListBuild(agent, owner, request.DecisionRef)), 1, "one warning names the runner, the OwnerRef and the DecisionRef")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, decide, "PointLink"), 1, "and it is the only one")

	// a Point that fails: the link row is locked by another process
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $ClassMethod(link, "Point", owner, agent, s1)
	Do $ClassMethod(link, "OwnerRefAgentIndexExists", owner, agent, .rowId)
	Set request = ..PointRequest(owner, "fresh")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Conversation).StartRowHolder(rowId), "another process holds the lock of the link row")
	Set sc = $ClassMethod(decide, "PointLink", request, agent, ..PointReply(s2, s1), .rotated)
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Conversation).StopRowHolder(rowId), "the other process lets the row go")
	Do $$$AssertStatusNotOK(sc, "the move fails")
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent)_"|"_rotated, s1_"|0", "the link names S1 still, with no rotation")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, decide, "PointLink", $ListBuild(agent, owner, request.DecisionRef, "is not moved")), 1, "one warning names the runner, the OwnerRef and the DecisionRef")
	Set sc = $ClassMethod(decide, "PointLink", request, agent, ..PointReply(s2, s1), .rotated)
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent)_"|"_rotated, s2_"|1", "once the row is free the same call moves the link")
}

/// Conclude is Decide's acceptance of a reply (Story 17.8): after it records the row of a linked turn's usable reply, the link of (OwnerRef, ChatAgent) names the
/// session the reply names. The answer carries the rotation of the move and none of the session fields, and the runner's own reply is not changed. A refused
/// reply, a timer's fallback (the late reply is discarded by the framework) and a reply for an item that already has a row move nothing. The same through OnResponse
/// of the recorder, whose runner is the first runner of the request. A move that fails (the link row is locked) leaves the answer as it is.
Method TestConcludeAccepts()
{
	Set link = "OcuTalon.Bridge.Data.ConversationLink"
	Set agent = "ChatAgent"
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set s1 = ..NewSession(10)
	Set s2 = ..NewSession(10)
	Set s3 = ..NewSession(10)
	Set s4 = ..NewSession(10)
	Do $$$AssertStatusOK($ClassMethod(link, "Point", owner, agent, s1), "the link names S1")

	// through Conclude
	Set request = ..PointRequest(owner)
	Set reply = ..PointReply(s2, s1)
	Set reply.HistoryCount = 2
	Set sc = ..Conclude(request, reply, .response)
	Do $$$AssertStatusOK(sc, "a usable reply is concluded")
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent), s2, "the link names the session of the reply, S2")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.SessionRotated_"|"_response.SessionId_"|"_response.SessionFrom_"|"_response.HistoryCount, 1: "none"), "0|1|||", "the answer says SessionRotated and holds no session field")
	Do $$$AssertEquals(reply.SessionId_"|"_reply.SessionFrom_"|"_reply.HistoryCount_"|"_reply.DecisionRef, s2_"|"_s1_"|2|", "and the runner's own reply is not changed")

	// a refused reply moves nothing
	Set request = ..PointRequest(owner)
	Set refused = ..PointReply(s3, s2)
	Set refused.FinishReason = "refusal"
	Set sc = ..Conclude(request, refused, .response)
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent), s2, "a refused reply leaves the link on S2")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason_"|"_response.SessionRotated, 1: "none"), "1|refusal|0", "and its fallback says SessionRotated 0")

	// the item has a row already: the reply is not the decision's answer
	Set again = ..PointReply(s3, s2)
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ##class(OcuTalon.Bridge.Ids).NewRef(), again, ..#REPLYCLASS, "OcuTalon.Bridge.Ext.ReplyFilter", "OcuTalon.Bridge.Ext.HostSink", 4242, .response)
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent), s2, "a usable reply for an item that another call already decided moves nothing")

	// through OnResponse of the recorder
	Set process = ..RetryProcess(60, "", agent)
	Set request = ..PointRequest(owner)
	Set sc = process.OnRequest(request, .response)
	Do $$$AssertStatusOK(sc, "OnRequest sends the turn to ChatAgent")
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = process.DecisionRef
	Set sc = process.OnResponse(request, .response, sent, ..PointReply(s3, s2), "reply")
	Do $$$AssertStatusOK(sc, "the usable reply is answered")
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent), s3, "the link names S3")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.SessionRotated_"|"_response.SessionId, 1: "none"), "0|1|", "the answer says SessionRotated and names no session")
	Do ..RestoreRows()

	// the timer fired: Decide records the fallback, and the late reply moves nothing
	Set process = ..RetryProcess(60, "", agent)
	Set request = ..PointRequest(owner)
	Set sc = process.OnRequest(request, .response)
	Set sc = process.OnResponse(request, .response, "", "", "timer")
	Do $$$AssertStatusOK(sc, "the timer's fallback is answered")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason_"|"_response.SessionRotated, 1: "none"), "1|timeout|0", "a timeout fallback with SessionRotated 0")
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent), s3, "the link still names S3")
	Do ..RestoreRows()

	// the retry's usable reply is accepted as well, and it moves the link of the first runner
	Set process = ..RetryProcess(60, agent_"Retry", agent)
	Set request = ..PointRequest(owner)
	Set sc = process.OnRequest(request, .response)
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = process.DecisionRef
	Set sc = process.OnResponse(request, .response, sent, ..NewReply("The CI mock refuses this request.", "refusal"), "reply")
	Do $$$AssertEquals(process.RetryRunner_"|"_$ClassMethod(link, "SessionOf", owner, agent), agent_"Retry|"_s3, "a refusal is retried on the retry runner and the link still names S3")
	Set sc = process.OnResponse(request, .response, sent, ..PointReply(s4, s3), "reply")
	Do $$$AssertStatusOK(sc, "the retry's reply is answered")
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent)_"|"_$ClassMethod(link, "SessionOf", owner, agent_"Retry"), s4_"|", "the link of the first runner names S4, and the retry runner has none")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.SessionRotated, 1: "none"), "0|1", "and the answer says SessionRotated")
	Do ..RestoreRows()

	// a move that fails does not fail the answer: the link row is locked by another process
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $ClassMethod(link, "Point", owner, agent, s1)
	Do $ClassMethod(link, "OwnerRefAgentIndexExists", owner, agent, .rowId)
	Set request = ..PointRequest(owner)
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Conversation).StartRowHolder(rowId), "another process holds the lock of the link row")
	Set sc = ..Conclude(request, ..PointReply(s2, s1), .response)
	Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Conversation).StopRowHolder(rowId), "the other process lets the row go")
	Do $$$AssertStatusOK(sc, "the usable reply is still concluded")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.SessionRotated_"|"_(response.Text '= ""), 1: "none"), "0|0|1", "and answered with its text and SessionRotated 0")
	Do $$$AssertEquals($ClassMethod(link, "SessionOf", owner, agent), s1, "while the link names S1 still")
	Do ..RestoreRows()
}

/// Admit refuses a SessionMode other than "", continue and fresh (Request SESSIONMODES; Story 1.8; AD-6), naming SessionMode, for every kind: a mode that
/// is misspelt can never continue a session that should have rotated. The match is exact.
Method TestAdmitSessionMode()
{
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Msg.Request).#SESSIONMODES, "continue,fresh", "the modes are continue and fresh; an empty mode means continue")
	Set cases = $ListBuild($ListBuild("turn", "user"), $ListBuild("turn", "untrusted"), $ListBuild("decide", "user"), $ListBuild("diagnose", "untrusted"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set kind = $List(case, 1)
		Set provenance = $List(case, 2)
		For mode = "", "continue", "fresh" {
			Set request = ..NewRequest(kind, provenance)
			Set request.SessionMode = mode
			Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Process.Decide).Admit(request), "a "_provenance_" "_kind_" with the SessionMode '"_mode_"' is admitted")
		}
		For mode = "Fresh", "FRESH", "x", "continue ", " fresh", "restart" {
			Set request = ..NewRequest(kind, provenance)
			Set request.SessionMode = mode
			Do ..AssertNamed(request, "SessionMode", "a "_provenance_" "_kind_" with the SessionMode '"_mode_"'")
		}
	}
}

/// Retryable (Story 17.2; AD-8, lead ruling R2) is pure. The nine reasons timeout, rate_limited, error, refusal, cut_off, empty, invalid, unusable and
/// no_key are retried; daily_cap, budget, too_large, an empty reason and an unknown one never are; a reply in which a tool ran, a SessionBroken turn and a
/// request of kind tool never are either. A timer that fired leaves it unknown whether a tool ran: a turn is not retried then (R2), and a decide or
/// diagnose request only when every tool of its agent is read-only.
Method TestRetryable()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	For reason = "timeout", "rate_limited", "error", "refusal", "cut_off", "empty", "invalid", "unusable", "no_key" {
		Do $$$AssertEquals($ClassMethod(decide, "Retryable", reason, 0, 0, "decide"), 1, reason_" is retried")
		Do $$$AssertEquals($ClassMethod(decide, "Retryable", reason, 0, 0, "diagnose"), 1, reason_" is retried for a diagnose request")
		Do $$$AssertEquals($ClassMethod(decide, "Retryable", reason, 0, 0, "turn"), 1, reason_" is retried for a turn")
		Do $$$AssertEquals($ClassMethod(decide, "Retryable", reason, 1, 0, "decide"), 0, reason_" is not retried when a tool ran")
		Do $$$AssertEquals($ClassMethod(decide, "Retryable", reason, 0, 1, "turn"), 0, reason_" is not retried for a SessionBroken turn")
		Do $$$AssertEquals($ClassMethod(decide, "Retryable", reason, 0, 0, "tool"), 0, reason_" is not retried for a request of kind tool")
	}
	For reason = "daily_cap", "budget", "too_large", "", "zz", "Refusal" {
		Do $$$AssertEquals($ClassMethod(decide, "Retryable", reason, 0, 0, "decide"), 0, "'"_reason_"' is never retried")
	}
	Do $$$AssertEquals($ClassMethod(decide, "Retryable", "timeout", 0, 0, "turn", 1, 1), 0, "a timed-out turn is not retried, although the timeout is a retried reason (R2)")
	Do $$$AssertEquals($ClassMethod(decide, "Retryable", "rate_limited", 0, 0, "turn", 1, 1), 0, "nor a turn whose timer fired after a re-send")
	Do $$$AssertEquals($ClassMethod(decide, "Retryable", "timeout", 0, 0, "decide", 1, 1), 1, "a timed-out decide request whose tools are all read-only is retried")
	Do $$$AssertEquals($ClassMethod(decide, "Retryable", "timeout", 0, 0, "diagnose", 1, 1), 1, "and so is a diagnose request")
	Do $$$AssertEquals($ClassMethod(decide, "Retryable", "timeout", 0, 0, "decide", 1, 0), 0, "a timed-out decide request with a tool that can change state is not")
	Do $$$AssertEquals($ClassMethod(decide, "Retryable", "timeout", 0, 0, "diagnose", 1, 0), 0, "nor a diagnose request")
	Do $$$AssertEquals($ClassMethod(decide, "Retryable", "timeout", 0, 0, "turn", 0, 0), 1, "a timeout that a reply reported (the timer did not fire) is retried for a turn")
}

/// RetrySeconds (AD-8, DW-647) is pure: T2 is the least of the timer and 110 - T1, or 0 when that is under 12.
Method TestRetrySeconds()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	For case = $ListBuild(60, 60, 50), $ListBuild(100, 100, 0), $ListBuild(80, 12, 12), $ListBuild(80, 60, 30), $ListBuild(98, 60, 12), $ListBuild(99, 60, 0), $ListBuild(12, 12, 12), $ListBuild(110, 110, 0), $ListBuild("", 100, 100), $ListBuild(0, 110, 110), $ListBuild(20, 100, 90) {
		Do $$$AssertEquals($ClassMethod(decide, "RetrySeconds", $List(case, 1), $List(case, 2)), $List(case, 3), "RetrySeconds(T1 "_$List(case, 1)_", timer "_$List(case, 2)_") is "_$List(case, 3))
	}
	Do $$$AssertTrue($ClassMethod(decide, "RetrySeconds", 60, 60) + 60 '> $Parameter(decide, "MAXTIMER"), "the two attempts of a decision stay within MAXTIMER")
}

/// ToolsReadOnly (R2): the Triage agent has no tool and Diagnosis has only the read-only watch tools, so both count as read-only; Chat has tools that
/// change state (reminders, watches); a runner without an agent class and one with a toolset that names a URI are not. No MCP server is listed (UseNoServers).
Method TestToolsReadOnly()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Do ..UseNoServers()
	Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "TriageAgent"), 1, "Triage has no tool")
	Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "DiagnosisAgent"), 1, "Diagnosis has only read-only watch tools")
	Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "TriageAgentRetry"), 1, "and so do their retry runners")
	Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "ChatAgent"), 0, "Chat has tools that change state")
	Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "ZzNoSuchRunner"), 0, "an item that is not in the production is not known to be read-only")
	Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", ""), 0, "and neither is no item at all")
}

/// Puts the McpServersClass setting of Decide to the fixture ZzReadOnlyServers listing no server (Test.Bridge.Gate StoreDecideSetting), so that the real ToolsReadOnly
/// does not depend on the OcuTalon.Mcp.Server rows of the namespace. OnAfterOneTest puts the value back, also after a test that ended in an error.
Method UseNoServers() [ Private ]
{
	If '..ServersSwapped {
		Set ..SavedServers = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("McpServersClass")
		Set ..ServersSwapped = 1
	}
	Kill ^||ZzReadOnlyServers
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Gate).StoreDecideSetting("McpServersClass", "OcuTalon.Test.Bridge.ZzReadOnlyServers"), "McpServersClass lists no MCP server")
}

/// ToolsReadOnly and the MCP servers (Story 22.8, DW-724): the McpServersClass setting of Decide is put to the fixture ZzReadOnlyServers in the stored configuration
/// of the production (the production names OcuTalon.Mcp.Attach, which a System Default Settings row would not override) and put back at the end.
Method TestToolsReadOnlyMcp()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set fixture = "OcuTalon.Test.Bridge.ZzReadOnlyServers"
	Set saved = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("McpServersClass", , , .sc)
	Do $$$AssertStatusOK(sc, "the McpServersClass setting is read")
	If $$$ISERR(sc) Quit
	Kill ^||ZzReadOnlyServers
	Try {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Gate).StoreDecideSetting("McpServersClass", fixture), "McpServersClass is the fixture")
		Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("McpServersClass"), fixture, "and the accessor reads it")
		Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "TriageAgent"), 1, "a fixture that lists no server leaves Triage read-only")
		Do $$$AssertEquals($ClassMethod(decide, "McpServersReadOnly"), 1, "and with no server listed, the MCP part is 1 (the retry rule as before)")
		Set ^||ZzReadOnlyServers("servers") = "[""zzone"",""zztwo""]"
		Set ^||ZzReadOnlyServers("ro", "zzone") = 1
		Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "TriageAgent"), 0, "a listed server that does not say 1 makes it 0 (zztwo says nothing)")
		Set ^||ZzReadOnlyServers("ro", "zztwo") = 1
		Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "TriageAgent"), 1, "every listed server read-only: 1")
		Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "DiagnosisAgent"), 1, "also for Diagnosis")
		Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "ChatAgent"), 0, "a runner whose tools change state stays 0, whatever the servers say")
		Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "ZzNoSuchRunner"), 0, "and so does an item that is not in the production")
		Set ^||ZzReadOnlyServers("ro", "zzone") = 0
		Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "TriageAgent"), 0, "the first of two servers that is not read-only: 0")
		Set ^||ZzReadOnlyServers("ro", "zzone") = 1
		Set ^||ZzReadOnlyServers("throws") = "zztwo"
		Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "TriageAgent"), 0, "a ToolsReadOnly that throws: 0")
		Kill ^||ZzReadOnlyServers("throws")
		For mode = "error", "throw", "text", "noname" {
			Set ^||ZzReadOnlyServers("mode") = mode
			Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "TriageAgent"), 0, "Servers in the mode "_mode_": 0")
		}
		Kill ^||ZzReadOnlyServers("mode")
		Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "TriageAgent"), 1, "control: the fixture as it was is 1 again")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Gate).StoreDecideSetting("McpServersClass", "OcuTalon.Test.Bridge.ZzNoSuchServers"), "McpServersClass names a class that does not exist")
		Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "TriageAgent"), 0, "which is 0")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Gate).StoreDecideSetting("McpServersClass", "OcuTalon.Bridge.Ext.HostSink"), "McpServersClass names a class that does not extend the base")
		Do $$$AssertEquals($ClassMethod(decide, "ToolsReadOnly", "TriageAgent"), 0, "which is 0 too")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Kill ^||ZzReadOnlyServers
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Gate).StoreDecideSetting("McpServersClass", saved), "McpServersClass is put back")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("McpServersClass"), saved, "and the accessor reads the production's class again")
}

/// ToolsetsReadOnly (R2), one clause at a time, on toolsets of one tool each (Test.Bridge.ZzReadOnlyTool): a safe, read-only tool with no per-call
/// classification is read-only, and so is no toolset; a read-only tool classified risky, a safe read-only tool with a Classify method, a toolset named by a URI
/// and a name that is no compiled class are not, and one such toolset in a list makes the whole list not read-only.
Method TestToolsetsReadOnly()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set safe = "OcuTalon.Test.Bridge.ZzReadOnlySafe"
	Do $$$AssertEquals($ClassMethod(decide, "ToolsetsReadOnly", ""), 1, "no toolset is no tool, so read-only")
	Do $$$AssertEquals($ClassMethod(decide, "ToolsetsReadOnly", safe), 1, "control: a safe, read-only tool with no per-call classification is read-only")
	Do $$$AssertEquals($ClassMethod(decide, "ToolsetsReadOnly", " "_safe_" , ,"), 1, "and so is the same list with white space and empty names")
	Do $$$AssertEquals($ClassMethod(decide, "ToolsetsReadOnly", "OcuTalon.Test.Bridge.ZzReadOnlyRisky"), 0, "a read-only tool classified risky is not read-only")
	Do $$$AssertEquals($ClassMethod(decide, "ToolsetsReadOnly", "OcuTalon.Test.Bridge.ZzReadOnlyHooked"), 0, "a safe read-only tool whose Classify method decides per call is not read-only")
	Do $$$AssertEquals($ClassMethod(decide, "ToolsetsReadOnly", safe_",mcp:docs"), 0, "a toolset named by a URI has unknown tools, so the list is not read-only")
	Do $$$AssertEquals($ClassMethod(decide, "ToolsetsReadOnly", safe_",OcuTalon.Test.Bridge.ZzNoSuchToolset"), 0, "nor is a list with a name that is no compiled class")
	Do $$$AssertEquals($ClassMethod(decide, "ToolsetsReadOnly", safe_",OcuTalon.Test.Bridge.ZzReadOnlyRisky"), 0, "one toolset that is not read-only makes the list not read-only")
}

/// Held with a RetryOf (Story 17.2; DW-650 a, b and d): with another process holding the conversation lock of (owner, ChatAgent), a retry request that
/// carries RetryOf ChatAgent and the ItemId the caller vouches for is not held (a); the same request without RetryOf waits (b); a RetryOf that names another
/// runner, another ItemId or no ItemId (what OnRequest passes) waits (d). OnRequest ignores the RetryOf of a request it is given: it is answered Busy.
Method TestHeldRetryOf()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set turn = ..NewRequest("turn", "user")
	Set turn.OwnerRef = owner
	Set retry = ##class(OcuTalon.Bridge.Process.Decide).RetryRequest(turn, ##class(OcuTalon.Bridge.Ids).NewRef(), 0, "ChatAgent")
	Do $$$AssertEquals(retry.RetryOf_"|"_retry.ItemId, "ChatAgent|"_turn.ItemId, "RetryRequest keeps the ItemId and sets RetryOf to the first runner")
	Do $$$AssertEquals(turn.RetryOf, "", "and the request itself is not changed")
	Do ..Put("ChatAgent", "ProviderConfig", "{}")
	Do ..Unmark()
	Do $$$AssertTrue(..StartHolder(owner, "ChatAgent"), "another process holds the conversation lock of (owner, ChatAgent)")
	Try {
		Set started = $ZHorolog
		Do $$$AssertEquals($ClassMethod(decide, "Held", retry, "ChatAgent", turn.ItemId), 0, "(a) a retry for the same conversation and ItemId is not held")
		Do $$$AssertTrue($ZHorolog - started < 1.5, "and it did not wait for the lock")
		Do $$$AssertEquals($ClassMethod(decide, "Held", turn, "ChatAgent", turn.ItemId), 1, "(b) the request without RetryOf is held, even with the ItemId")
		Do $$$AssertEquals($ClassMethod(decide, "Held", turn, "ChatAgent"), 1, "also without an ItemId")
		Set other = ..NewRequest("turn", "user")
		Set other.OwnerRef = owner
		Set elsewhere = ##class(OcuTalon.Bridge.Process.Decide).RetryRequest(other, "", 0, "TriageAgent")
		Do $$$AssertEquals($ClassMethod(decide, "Held", elsewhere, "ChatAgent", other.ItemId), 1, "(d) a RetryOf that names another runner is held")
		Do $$$AssertEquals($ClassMethod(decide, "Held", retry, "ChatAgent", other.ItemId), 1, "(d) a RetryOf for another ItemId is held")
		Do $$$AssertEquals($ClassMethod(decide, "Held", retry, "ChatAgent"), 1, "and one that the caller does not vouch for (OnRequest passes no ItemId) is held")
		Do $$$AssertEquals($ClassMethod(decide, "Held", retry, "ChatAgent", ""), 1, "an empty ItemId vouches for nothing")

		// (c) OnRequest ignores the RetryOf of the request it is given
		Set process = ..NewProcess()
		Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
		Set process.HostSinkClass = ..#SINK
		Set process.TimerSeconds = 60
		Set process.%SessionId = 4271
		Set process.DecisionTokenBudget = 0
		Set sc = process.OnRequest(retry, .response)
		Do $$$AssertStatusOK(sc, "OnRequest answers a request whose RetryOf a client set")
		Do $$$AssertEquals($Select($IsObject(response): response.%ClassName(1)_"|"_response.Busy_"|"_response.Fallback, 1: "none"), "OcuTalon.Bridge.Msg.Reply|1|0", "(c) with Busy: the RetryOf skipped nothing")
		Do $$$AssertEquals(..Rows(turn.ItemId), 0, "and no row is recorded")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do $$$AssertTrue(..StopHolder(owner), "the holder is stopped")
	Do $$$AssertEquals($ClassMethod(decide, "Held", turn, "ChatAgent"), 0, "Held is 0 again once the lock is free")
}

/// SentRequest clears a RetryOf that the request carries, on every first send and on every re-send, and RetryRequest is the one place that sets it. With
/// the recorder (Test.Bridge.ZzDecide), the request that OnRequest sends has an empty RetryOf, although the request it was given had one.
Method TestSentRequestRetryOf()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set request = ..NewRequest("decide")
	Set request.RetryOf = "TriageAgent"
	Set sent = $ClassMethod(decide, "SentRequest", request, "ref", 10)
	Do $$$AssertEquals(sent.RetryOf_"|"_request.RetryOf, "|TriageAgent", "SentRequest clears RetryOf on the clone and leaves the request as it is")
	Set retry = $ClassMethod(decide, "RetryRequest", request, "ref", 10, "TriageAgent")
	Do $$$AssertEquals(retry.RetryOf_"|"_retry.DecisionRef_"|"_retry.ItemId, "TriageAgent|ref|"_request.ItemId, "RetryRequest sets it again on the retry's clone, with the DecisionRef and the ItemId")

	Set process = ..RetryProcess(60, "")
	Set sc = process.OnRequest(request, .response)
	Do $$$AssertStatusOK(sc, "OnRequest sends the request")
	Do $$$AssertEquals(..Calls("send"), 1, "one request is sent")
	Do $$$AssertEquals($Get(^||ZzDecideCalls("send", 1, "retryOf"), "none"), "", "its RetryOf is empty, whatever the request carried")
	Do $$$AssertEquals(process.FirstSeconds, 60, "and the first attempt's timer is kept")

	// the re-send
	Kill ^||ZzDecideCalls
	Set process.%TimeCreated = ..Ago(3)
	Set sc = process.OnResponse(request, .response, "", "", "resend")
	Do $$$AssertStatusOK(sc, "the key resend is answered with status OK")
	Do $$$AssertEquals(..Calls("send"), 1, "and sends the request again")
	Do $$$AssertEquals($Get(^||ZzDecideCalls("send", 1, "retryOf"), "none"), "", "with an empty RetryOf")
	Do ..RestoreRows()
}

/// The second-model retry through OnRequest and OnResponse, with the recorder (Test.Bridge.ZzDecide; Story 17.2, AD-8, DW-647, DW-650):
///   - a decide request is sent to TriageAgent, and its refused reply is not recorded: the same request goes once to TriageAgentRetry with the DecisionRef of the
///     decision, the same ItemId, RetryOf TriageAgent, the key reply, and a timer of 50 seconds (T1 60, T2 = min(60, 110 - 60)); no row and no answer yet;
///   - the retry's usable reply is the decision: one row, not a fallback, whose Model is the Model of the reply that answered although a later Usage row of the
///     first attempt is the newest, and whose steps are those of both attempts; nothing else is sent, and no timer is set after the retry's;
///   - the retry's refusal is a fallback with the retry's reason (error here, not the first attempt's refusal), with one row and no second request.
Method TestRetryWiring()
{
	Set process = ..RetryProcess(60)
	Set request = ..NewRequest("decide")
	Set sc = process.OnRequest(request, .response)
	Do $$$AssertStatusOK(sc, "OnRequest sends the request to the first runner")
	Do $$$AssertEquals(..Calls("send")_"|"_$ListGet($Get(^||ZzDecideCalls("send", 1)), 1)_"|"_..Calls("timer")_"|"_process.FirstSeconds, "1|TriageAgent|1|60", "one request goes to TriageAgent, with one timer, and T1 is 60")
	Set ref = process.DecisionRef
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ref
	Set refused = ..NewReply("The CI mock refuses this request.", "refusal")
	Set refused.AgentStepCount = 1
	Set sc = process.OnResponse(request, .response, sent, refused, "reply")
	Do $$$AssertStatusOK(sc, "the refused reply is answered with status OK")
	Do $$$AssertEquals(response, "", "and nothing is answered yet")
	Do $$$AssertEquals(..Rows(request.ItemId), 0, "no row is recorded")
	Do $$$AssertEquals(..Calls("send"), 2, "a second request is sent")
	Set call = $Get(^||ZzDecideCalls("send", 2))
	Do $$$AssertEquals($List(call, 1)_"|"_$List(call, 2)_"|"_$List(call, 3)_"|"_$List(call, 4)_"|"_$List(call, 5), "TriageAgentRetry|"_ref_"|1|reply|"_request.ItemId, "to the retry runner, with the DecisionRef and the ItemId, a response required and the key reply")
	Do $$$AssertEquals($Get(^||ZzDecideCalls("send", 2, "retryOf")), "TriageAgent", "and RetryOf the first runner")
	Set timer = $Get(^||ZzDecideCalls("timer", 2))
	Do $$$AssertEquals(..Calls("timer")_"|"_$List(timer, 1)_"|"_$List(timer, 2), "2|50|timer", "with a timer of 50 seconds: the least of 60 and 110 - 60")
	Do $$$AssertEquals(process.RetryRunner_"|"_process.StepCount, "TriageAgentRetry|1", "the retry is recorded and the steps of the first attempt are added")
	Do $$$AssertEquals(request.RetryOf, "", "the request itself is not changed")

	// the retry answers: the Model is the answering reply's, not the newest Usage row's
	Do ..AddUsage(ref, "claude-sonnet-5-5", 100, 20, 0, 0, .001)
	Do ..AddUsage(ref, "claude-haiku-5-5", 300, 40, 0, 0, .002)
	Set answer = ..NewReply(..#DIGEST, "end_turn")
	Set answer.Model = "claude-sonnet-5-5"
	Set answer.AgentStepCount = 2
	Set sc = process.OnResponse(request, .response, sent, answer, "reply")
	Do $$$AssertStatusOK(sc, "the retry's reply is answered with status OK")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertTrue($IsObject(row) && $IsObject(response), "one row is recorded and the caller is answered")
	If $IsObject(row) && $IsObject(response) {
		Do $$$AssertEquals(row.Fallback_"|"_row.Outcome_"|"_row.Ref, "0|digest|"_ref, "the row is the decision of the retry, under the DecisionRef")
		Do $$$AssertEquals(row.Model, "claude-sonnet-5-5", "its Model is the Model of the reply that answered, not the newest Usage row's (the first attempt's)")
		Do $$$AssertEquals(row.InputTokens_"|"_row.OutputTokens_"|"_row.AgentStepCount, "400|60|3", "and its totals are the sums of both attempts' Usage rows and steps")
		Do $$$AssertEquals(response.Fallback_"|"_response.Model, "0|claude-sonnet-5-5", "the answer carries the same")
	}
	Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer"), "2|2", "nothing else was sent and no timer was set after the retry's reply")
	Do ..RestoreRows()

	// the retry fails too: the fallback carries the retry's reason
	Set process = ..RetryProcess(60)
	Set request = ..NewRequest("decide")
	Set sc = process.OnRequest(request, .response)
	Set ref = process.DecisionRef
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = ref
	Set sc = process.OnResponse(request, .response, sent, ..NewReply("The CI mock refuses this request.", "refusal"), "reply")
	Do $$$AssertEquals(..Calls("send"), 2, "again the retry is sent")
	Set failed = ..FailedReply("ERROR <%AICore>ProviderError: Provider 'anthropic' error: CI mock: the provider failed.")
	Set sc = process.OnResponse(request, .response, sent, failed, "reply")
	Do $$$AssertStatusOK(sc, "the retry's failure is answered with status OK")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals($Select($IsObject(row): row.Fallback_"|"_row.FallbackReason_"|"_row.Reasons, 1: "no row"), "1|error|", "the fallback carries the retry's reason: error, not the first attempt's refusal")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).FallbackProblems(response, row, "decide", "error"), "", "with every guarantee of a fallback")
	Do $$$AssertEquals(..Rows(request.ItemId)_"|"_..Calls("send"), "1|2", "one row, and no third request")
	Do ..RestoreRows()

	// the retry's rate limit is not sent again, and no back-off timer is set: the reply goes to the fallback at once
	Set process = ..RetryProcess(60)
	Set request = ..NewRequest("decide")
	Set sc = process.OnRequest(request, .response)
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = process.DecisionRef
	Set sc = process.OnResponse(request, .response, sent, ..NewReply("", "refusal"), "reply")
	Do $$$AssertEquals(..Calls("send"), 2, "the retry is sent (an empty reply is retried)")
	Set limited = ..FailedReply(..#OVERLOADED)
	Set sc = process.OnResponse(request, .response, sent, limited, "reply")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals($Select($IsObject(row): row.Fallback_"|"_row.FallbackReason, 1: "no row"), "1|rate_limited", "the retry's rate limit is a rate_limited fallback")
	Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer")_"|"_process.Resends, "2|2|0", "with no back-off timer, no third request and no re-send")
	Do ..RestoreRows()

	// a linked continue turn: the retry is a fresh turn whose SeedText is the recap of the first HistoryCount stored messages (Story 17.8, DW-726)
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set stored = ..NewMessagesSession($ListBuild("FIRSTQUESTION", "FIRSTANSWER", "SECONDQUESTION", "REFUSEDTEXT"))
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Data.ConversationLink).Point(owner, "ChatAgent", stored), "a link names a stored conversation of four messages for (owner, ChatAgent)")
	Set cut = ##class(OcuTalon.Bridge.Compaction).Seed(##class(OcuTalon.Bridge.RequestSize).StoredMessages(stored, 2))
	Set whole = ##class(OcuTalon.Bridge.Compaction).Seed(##class(OcuTalon.Bridge.RequestSize).StoredMessages(stored))
	Do $$$AssertTrue((cut [ "FIRSTQUESTION") && (cut [ "FIRSTANSWER") && (cut '[ "SECONDQUESTION") && (cut '[ "REFUSEDTEXT"), "the seed of the first two messages holds the first exchange and nothing after it")
	Do $$$AssertTrue(whole [ "REFUSEDTEXT", "(control: the seed of all four holds the refusal)")
	For case = 1, 2 {
		Set process = ..RetryProcess(60, "ChatAgentRetry", "ChatAgent")
		Set request = ..PointRequest(owner)
		Set request.Input = "The next question."
		Set sc = process.OnRequest(request, .response)
		Set sent = request.%ConstructClone()
		Set sent.DecisionRef = process.DecisionRef
		Set refused = ..NewReply("The CI mock refuses this request.", "refusal")
		If case = 1 Set refused.HistoryCount = 2
		Set sc = process.OnResponse(request, .response, sent, refused, "reply")
		Do $$$AssertEquals(..Calls("send"), 2, "case "_case_": the retry is sent")
		Do $$$AssertEquals($Get(^||ZzDecideCalls("send", 2, "retryOf"))_"|"_$Get(^||ZzDecideCalls("send", 2, "mode")), "ChatAgent|fresh", "case "_case_": to the retry runner as a fresh turn, naming the first runner")
		Do $$$AssertEquals($Get(^||ZzDecideCalls("send", 2, "seed")), $Select(case = 1: cut, 1: whole), "case "_case_": whose SeedText is the recap of "_$Select(case = 1: "the first 2 stored messages, the count of the first reply", 1: "the whole stored history, since the reply holds no count"))
		Do $$$AssertEquals(request.SessionMode_"|"_request.SeedText, "|", "case "_case_": the request itself is not changed")
		Do ..RestoreRows()
	}

	// a fresh turn keeps its own SeedText
	Set process = ..RetryProcess(60, "ChatAgentRetry", "ChatAgent")
	Set request = ..PointRequest(owner, "fresh")
	Set request.SeedText = "A recap of my own."
	Set sc = process.OnRequest(request, .response)
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = process.DecisionRef
	Set refused = ..NewReply("The CI mock refuses this request.", "refusal")
	Set refused.HistoryCount = 2
	Set sc = process.OnResponse(request, .response, sent, refused, "reply")
	Do $$$AssertEquals($Get(^||ZzDecideCalls("send", 2, "mode"))_"|"_$Get(^||ZzDecideCalls("send", 2, "seed")), "fresh|A recap of my own.", "a fresh turn is retried with its own SeedText")
	Do ..RestoreRows()
}

/// What is never retried (AD-8): the failure of a daily cap, a reply in which a tool ran, and a SessionBroken turn fall back at once, with no request to the
/// retry runner, although the runner has a retry runner; the prechecks (a token budget of 1, a request-size limit of 1, a day that is capped) fall back
/// from OnRequest with nothing sent. A second attempt is never made after the retry: the retry's reply goes to the fallback.
Method TestRetryNeverCases()
{
	Set today = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())
	For case = 1, 2 {
		Set label = $Select(case = 1: "the gateway's daily cap", 1: "a tool that ran")
		Set expected = $Select(case = 1: "daily_cap", 1: "refusal")
		Set process = ..RetryProcess(60)
		Set request = ..NewRequest("decide")
		Set sc = process.OnRequest(request, .response)
		Set sent = request.%ConstructClone()
		Set sent.DecisionRef = process.DecisionRef
		If case = 1 {
			Set reply = ..FailedReply(..#DAILYCAP)
		} Else {
			Set reply = ..NewReply("x", "refusal")
			Set reply.ToolsRun = 1
		}
		Set sc = process.OnResponse(request, .response, sent, reply, "reply")
		Set row = ..RowOf(request.ItemId, "decide")
		Do $$$AssertEquals($Select($IsObject(row): row.Fallback_"|"_row.FallbackReason, 1: "no row"), "1|"_expected, label_" is a fallback with the reason "_expected)
		Do $$$AssertEquals(..Calls("send"), 1, label_": no request reached the retry runner")
		Do ..RestoreRows()
	}

	// a SessionBroken turn
	Do ..Put("ChatAgent", "RetryItem", "ChatAgentRetry")
	Set process = ..NewRecorder()
	Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set process.HostSinkClass = ..#SINK
	Set process.%SessionId = 4272
	Set process.TimerSeconds = 60
	Set process.FirstSeconds = 60
	Set process.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Kill ^||ZzDecideCalls
	Set request = ..NewRequest("turn", "user")
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = process.DecisionRef
	Set sc = process.OnResponse(request, .response, sent, ..FailedReply(..#INVALIDINPUT), "reply")
	Do $$$AssertEquals($Select($IsObject(response): response.Fallback_"|"_response.FallbackReason_"|"_response.SessionBroken, 1: "none"), "1|error|1", "a user's turn whose history the provider rejects is a SessionBroken fallback")
	Do $$$AssertEquals(..Calls("send"), 0, "and is not retried")
	Do ..RestoreRows()

	// the prechecks
	For case = $ListBuild("budget", "budget"), $ListBuild("too_large", "too_large"), $ListBuild("daily_cap", "daily_cap") {
		Set process = ..RetryProcess(60)
		If $List(case, 1) = "budget" Set process.DecisionTokenBudget = 1
		If $List(case, 1) = "too_large" Set process.RequestTokenLimit = 1
		If $List(case, 1) = "daily_cap" Set ^OcuTalonBP.UsageCapped(today) = ##class(OcuTalon.Bridge.Time).NowUtc()
		Set request = ..NewRequest("decide")
		Set sc = process.OnRequest(request, .response)
		Do $$$AssertStatusOK(sc, $List(case, 1)_": OnRequest answers")
		Set row = ..RowOf(request.ItemId, "decide")
		Do $$$AssertEquals($Select($IsObject(row): row.Fallback_"|"_row.FallbackReason, 1: "no row"), "1|"_$List(case, 2), $List(case, 1)_": a fallback with that reason")
		Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer"), "0|0", $List(case, 1)_": nothing is sent and no timer is set")
		Do ..RestoreRows()
	}
}

/// The retry of a linked turn goes through Held with the ItemId of the decision (DW-650 a, through TryRetry): with another process holding the conversation lock
/// of (owner, ChatAgent), a refused reply of the user's turn is still retried, the retry request goes to ChatAgentRetry with RetryOf ChatAgent, and the caller is
/// not answered Busy.
Method TestRetryTurnSkipsHeld()
{
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set process = ..RetryProcess(60, "ChatAgentRetry", "ChatAgent")
	Set process.FirstSeconds = 60
	Set process.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ..NewRequest("turn", "user")
	Set request.OwnerRef = owner
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = process.DecisionRef
	Do $$$AssertTrue(..StartHolder(owner, "ChatAgent"), "another process holds the conversation lock of (owner, ChatAgent)")
	Try {
		Set sc = process.OnResponse(request, .response, sent, ..NewReply("The CI mock refuses this request.", "refusal"), "reply")
		Do $$$AssertStatusOK(sc, "the refused reply is answered with status OK")
		Do $$$AssertEquals(response, "", "the caller is not answered Busy, and not yet")
		Do $$$AssertEquals(..Calls("send"), 1, "the retry request is sent")
		Set call = $Get(^||ZzDecideCalls("send", 1))
		Do $$$AssertEquals($List(call, 1)_"|"_$Get(^||ZzDecideCalls("send", 1, "retryOf")), "ChatAgentRetry|ChatAgent", "to the retry runner, with RetryOf the first runner")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Do $$$AssertTrue(..StopHolder(owner), "the holder is stopped")
	Do ..RestoreRows()
}

/// With no RetryItem setting (what the install leaves), every unusable reply falls back as in release 1: no second request, whatever the reason.
Method TestRetryNoSecondModel()
{
	For failure = "", ..#OVERLOADED, ..#LOOP {
		Set process = ..RetryProcess(60, "")
		Set request = ..NewRequest("decide")
		Set sc = process.OnRequest(request, .response)
		Set sent = request.%ConstructClone()
		Set sent.DecisionRef = process.DecisionRef
		Set reply = $Select(failure = "": ..NewReply("x", "refusal"), 1: ..FailedReply(failure))
		If failure = ..#OVERLOADED Set process.%TimeCreated = ..Ago(59)
		Set sc = process.OnResponse(request, .response, sent, reply, "reply")
		Set row = ..RowOf(request.ItemId, "decide")
		Do $$$AssertEquals($Select($IsObject(row): row.Fallback_"|"_row.FallbackReason, 1: "no row"), "1|"_$Select(failure = "": "refusal", failure = ..#OVERLOADED: "rate_limited", 1: "unusable"), "the reply falls back with its own reason")
		Do $$$AssertEquals(..Calls("send"), 1, "and only the first runner was sent a request")
		Do ..RestoreRows()
	}
}

/// The timer that fired (R2): a decide request whose timer fires is retried when every tool of its agent is read-only (Triage has none), with the timer of the retry
/// at 50 seconds; a turn whose timer fires falls back with timeout as in release 1 and is not retried, because it is unknown whether a tool ran. The timer of the
/// retry itself ends the decision with timeout, whatever the first attempt's re-sends were. No MCP server is listed (UseNoServers).
Method TestRetryAfterTimer()
{
	Do ..UseNoServers()
	Set process = ..RetryProcess(60)
	Set process.FirstSeconds = 60
	Set process.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ..NewRequest("decide")
	Set sc = process.OnResponse(request, .response, "", "", "timer")
	Do $$$AssertStatusOK(sc, "the timer of a decide request is answered with status OK")
	Do $$$AssertEquals(response, "", "and answers nothing yet")
	Do $$$AssertEquals(..Rows(request.ItemId)_"|"_..Calls("send"), "0|1", "no row, and the request goes once to the retry runner")
	Do $$$AssertEquals($ListGet($Get(^||ZzDecideCalls("send", 1)), 1)_"|"_$Get(^||ZzDecideCalls("send", 1, "retryOf")), "TriageAgentRetry|TriageAgent", "to TriageAgentRetry with RetryOf TriageAgent")
	Set timer = $Get(^||ZzDecideCalls("timer", 1))
	Do $$$AssertEquals($List(timer, 1)_"|"_$List(timer, 2)_"|"_$List(timer, 3), "50|timer|*", "with a timer of 50 whose default controlled keys discard the late reply of the first attempt")
	// the retry's own timer
	Set process.Resends = 2
	Set sc = process.OnResponse(request, .response, "", "", "timer")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals($Select($IsObject(row): row.Fallback_"|"_row.FallbackReason, 1: "no row"), "1|timeout", "the retry's timer is a timeout fallback, although the first attempt was re-sent")
	Do $$$AssertEquals($ListGet($Get(^||ZzDecideCalls("send", 1)), 2)_"|"_$Select($IsObject(row): row.Ref, 1: "no row"), process.DecisionRef_"|"_process.DecisionRef, "the row of that fallback has the DecisionRef that the retry request carried, so a late retry finds the decision recorded (Adapter.Agent RetryIsLate)")
	Do $$$AssertEquals(..Calls("send"), 1, "and no second request is sent")
	Do ..RestoreRows()

	// a decide request whose agent has a tool that can change state is not retried either
	Set ^||ZzDecideReadOnly = 0
	Set process = ..RetryProcess(60)
	Set process.FirstSeconds = 60
	Set process.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ..NewRequest("decide")
	Set sc = process.OnResponse(request, .response, "", "", "timer")
	Kill ^||ZzDecideReadOnly
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals($Select($IsObject(row): row.Fallback_"|"_row.FallbackReason, 1: "no row"), "1|timeout", "a timed-out decide request whose agent can change state falls back with timeout")
	Do $$$AssertEquals(..Calls("send"), 0, "and nothing is sent")
	Do ..RestoreRows()

	// a turn, even when every tool of its agent is read-only (what the rule of R2 says of the turn itself)
	Set ^||ZzDecideReadOnly = 1
	Do ..Put("ChatAgent", "RetryItem", "ChatAgentRetry")
	Set process = ..NewRecorder()
	Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set process.HostSinkClass = ..#SINK
	Set process.%SessionId = 4273
	Set process.TimerSeconds = 60
	Set process.FirstSeconds = 60
	Set process.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Kill ^||ZzDecideCalls
	Set request = ..NewRequest("turn", "user")
	Set sc = process.OnResponse(request, .response, "", "", "timer")
	Kill ^||ZzDecideReadOnly
	Do $$$AssertStatusOK(sc, "the timer of a turn is answered with status OK")
	Set row = ..RowOf(request.ItemId, "turn")
	Do $$$AssertEquals($Select($IsObject(row): row.Fallback_"|"_row.FallbackReason, 1: "no row"), "1|timeout", "a turn whose timer fired falls back with timeout")
	Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer"), "0|0", "and nothing is sent")
	Do ..RestoreRows()

	// a diagnose request whose agent has only read-only tools is retried too
	Set process = ..RetryProcess(60, "")
	Do ..PutKey("DiagnosisAgentRetry")
	Do ..Put("DiagnosisAgent", "RetryItem", "DiagnosisAgentRetry")
	Set process.FirstSeconds = 60
	Set process.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ..NewRequest("diagnose")
	Set sc = process.OnResponse(request, .response, "", "", "timer")
	Do $$$AssertEquals($ListGet($Get(^||ZzDecideCalls("send", 1)), 1)_"|"_$Get(^||ZzDecideCalls("send", 1, "retryOf")), "DiagnosisAgentRetry|DiagnosisAgent", "a diagnose request goes to DiagnosisAgentRetry")
	Do ..RestoreRows()
}

/// Story 22.8 (QA), AC 4 through the timer, with the real ToolsReadOnly (the recorder's hook is not set): the McpServersClass of Decide is put to the fixture
/// ZzReadOnlyServers in the stored configuration of the production and back. A decide request whose timer fired and whose agent has no tool (Triage) is retried
/// while every listed server says that its tools are read-only; once one listed server says otherwise, or its answer throws, it falls back with timeout and nothing is sent.
Method TestRetryAfterTimerMcp()
{
	Set fixture = "OcuTalon.Test.Bridge.ZzReadOnlyServers"
	Set saved = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("McpServersClass", , , .sc)
	Do $$$AssertStatusOK(sc, "the McpServersClass setting is read")
	If $$$ISERR(sc) Quit
	Kill ^||ZzReadOnlyServers, ^||ZzDecideReadOnly
	Try {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Gate).StoreDecideSetting("McpServersClass", fixture), "McpServersClass is the fixture")
		Set ^||ZzReadOnlyServers("servers") = "[""zzone""]"
		For case = $ListBuild("decide", 0), $ListBuild("decide", 1), $ListBuild("decide", 2) {
			Set kind = $List(case, 1), state = $List(case, 2)
			Set label = "a "_kind_" request whose timer fired, "_$Select(state = 0: "with a listed server that is not read-only", state = 1: "with a listed server that says read-only", 1: "with a listed server whose answer throws")_": "
			Kill ^||ZzReadOnlyServers("ro"), ^||ZzReadOnlyServers("throws")
			If state = 1 Set ^||ZzReadOnlyServers("ro", "zzone") = 1
			If state = 2 Set ^||ZzReadOnlyServers("ro", "zzone") = 1, ^||ZzReadOnlyServers("throws") = "zzone"
			Set process = ..RetryProcess(60)
			Set process.FirstSeconds = 60
			Set process.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
			Set request = ..NewRequest(kind)
			Set response = ""
			Set sc = process.OnResponse(request, .response, "", "", "timer")
			Do $$$AssertStatusOK(sc, label_"the timer is answered with status OK")
			If state = 1 {
				Do $$$AssertEquals(..Rows(request.ItemId)_"|"_..Calls("send"), "0|1", label_"no row, and the request goes once to the retry runner")
				Do $$$AssertEquals($ListGet($Get(^||ZzDecideCalls("send", 1)), 1)_"|"_$Get(^||ZzDecideCalls("send", 1, "retryOf")), "TriageAgentRetry|TriageAgent", label_"to TriageAgentRetry")
			} Else {
				Set row = ..RowOf(request.ItemId, kind)
				Do $$$AssertEquals($Select($IsObject(row): row.Fallback_"|"_row.FallbackReason, 1: "no row"), "1|timeout", label_"it falls back with timeout")
				Do $$$AssertEquals(..Calls("send"), 0, label_"and nothing is sent")
			}
			Do ..RestoreRows()
		}
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the test runs without an exception")
	}
	Kill ^||ZzReadOnlyServers
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Gate).StoreDecideSetting("McpServersClass", saved), "McpServersClass is put back")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("McpServersClass"), saved, "and the accessor reads the production's class again")
}

/// A rate limit that outlasts the re-sends (Story 17.2): the key resend that finds less than a second of the timer left records rate_limited in release 1; with a
/// second model it sends the request to the retry runner instead, with a timer of the seconds that the split leaves (T1 12, T2 12). With no RetryItem the same
/// resend is release 1's fallback (TestResendBoundary).
Method TestRetryAfterResendRanOut()
{
	Do ..PutKey("TriageAgentRetry")
	Do ..Put("TriageAgent", "RetryItem", "TriageAgentRetry")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set process = ..ResendRecorder(12, 11.5, ref)
	Set process.FirstSeconds = 12
	Set request = ..NewRequest("decide")
	Set response = ""
	Set sc = process.OnResponse(request, .response, "", "", "resend")
	Do $$$AssertStatusOK(sc, "the key resend with 0.5 s left is answered with status OK")
	Do $$$AssertEquals(response, "", "and answers nothing yet")
	Do $$$AssertEquals(..Rows(request.ItemId)_"|"_process.Resends_"|"_process.RetryRunner, "0|0|TriageAgentRetry", "no row is recorded, Resends stays 0 and the retry is recorded")
	Set call = $Get(^||ZzDecideCalls("send", 1))
	Do $$$AssertEquals(..Calls("send")_"|"_$List(call, 1)_"|"_$List(call, 2)_"|"_$Get(^||ZzDecideCalls("send", 1, "retryOf")), "1|TriageAgentRetry|"_ref_"|TriageAgent", "one request goes to TriageAgentRetry with the DecisionRef and RetryOf TriageAgent")
	Set timer = $Get(^||ZzDecideCalls("timer", 1))
	Do $$$AssertEquals(..Calls("timer")_"|"_$List(timer, 1)_"|"_$List(timer, 2), "1|12|timer", "with a timer of 12")
	Do ..RestoreRows()
}

/// No time left (DW-647): with TimerSeconds 100, T2 is 10, under the shortest timer, so the retry is not sent: the fallback keeps the first reason and its
/// reasons are RETRYSKIPPED. With a timer of 98 (T2 12) it is sent.
Method TestRetrySkipped()
{
	Set process = ..RetryProcess(100)
	Set request = ..NewRequest("decide")
	Set sc = process.OnRequest(request, .response)
	Do $$$AssertEquals(process.FirstSeconds, 100, "T1 is 100")
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = process.DecisionRef
	Set sc = process.OnResponse(request, .response, sent, ..NewReply("The CI mock refuses this request.", "refusal"), "reply")
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals($Select($IsObject(row): row.Fallback_"|"_row.FallbackReason_"|"_row.Reasons, 1: "no row"), "1|refusal|"_##class(OcuTalon.Bridge.Process.Decide).#RETRYSKIPPED, "the fallback keeps the first attempt's reason and says that the second model was not tried")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Process.Decide).#RETRYSKIPPED, "The second model was not tried, because too little time was left within the decision's 110-second limit.", "in the words the lead ruled (U-281)")
	Do $$$AssertEquals(..Calls("send"), 1, "and no request reached the retry runner")
	If $IsObject(response) && $IsObject(row) Do $$$AssertEquals(response.Reasons, row.Reasons, "the answer carries the reasons")
	Do ..RestoreRows()

	Set process = ..RetryProcess(98)
	Set request = ..NewRequest("decide")
	Set sc = process.OnRequest(request, .response)
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = process.DecisionRef
	Set sc = process.OnResponse(request, .response, sent, ..NewReply("The CI mock refuses this request.", "refusal"), "reply")
	Do $$$AssertEquals(..Calls("send"), 2, "with a timer of 98 the retry is sent")
	Set timer = $Get(^||ZzDecideCalls("timer", 2))
	Do $$$AssertEquals($List(timer, 1), 12, "with a timer of 12")
	Do ..RestoreRows()
}

/// A RetryItem that is not usable gives one warning that names the setting, and the request falls back as in release 1: an item that is not in the production, a
/// disabled one, one that is not an agent runner, the runner itself and, for a decide request, a retry runner whose ReplyClass is refused.
Method TestRetryBadItem()
{
	For value = "ZzNoSuchItem", "AgentSteps", "TriageAgent", "ApprovalHold" {
		Set process = ..RetryProcess(60, value)
		Set request = ..NewRequest("decide")
		Set sc = process.OnRequest(request, .response)
		Set sent = request.%ConstructClone()
		Set sent.DecisionRef = process.DecisionRef
		Set mark = ..LogMark()
		Set sc = process.OnResponse(request, .response, sent, ..NewReply("The CI mock refuses this request.", "refusal"), "reply")
		Set row = ..RowOf(request.ItemId, "decide")
		Do $$$AssertEquals($Select($IsObject(row): row.Fallback_"|"_row.FallbackReason, 1: "no row"), "1|refusal", "RetryItem '"_value_"': the request falls back as in release 1")
		Do $$$AssertEquals(..Calls("send"), 1, "RetryItem '"_value_"': no second request")
		Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Test.Bridge.ZzDecide", "RetryItemOf", $ListBuild("RetryItem", value)), 1, "RetryItem '"_value_"': one warning names the setting and the value")
		Do ..RestoreRows()
	}
	// a disabled retry runner: a System Default Settings row of Enabled 0 for TriageAgentRetry, which RetryItemProblem reads before the item's own Enabled
	Do ..Put("TriageAgentRetry", "Enabled", 0)
	Set process = ..RetryProcess(60)
	Set request = ..NewRequest("decide")
	Set sc = process.OnRequest(request, .response)
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = process.DecisionRef
	Set mark = ..LogMark()
	Set sc = process.OnResponse(request, .response, sent, ..NewReply("The CI mock refuses this request.", "refusal"), "reply")
	Do $$$AssertEquals(..Calls("send"), 1, "a disabled retry runner is not used")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Test.Bridge.ZzDecide", "RetryItemOf", $ListBuild("RetryItem", "TriageAgentRetry", "disabled")), 1, "and one warning names the setting and says it is disabled")
	Do ..RestoreRows()
	// a ReplyClass that is refused: the diagnose runner's retry for a decide request would take DiagnosisPayload, which is a %JSON.Adaptor class, so use
	// the Chat retry runner, which has none
	Set process = ..RetryProcess(60, "ChatAgentRetry")
	Set request = ..NewRequest("decide")
	Set sc = process.OnRequest(request, .response)
	Set sent = request.%ConstructClone()
	Set sent.DecisionRef = process.DecisionRef
	Set mark = ..LogMark()
	Set sc = process.OnResponse(request, .response, sent, ..NewReply("The CI mock refuses this request.", "refusal"), "reply")
	Do $$$AssertEquals(..Calls("send"), 1, "a retry runner with no ReplyClass is not used for a decide request")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Test.Bridge.ZzDecide", "RetryItemOf", $ListBuild("RetryItem", "ChatAgentRetry")), 1, "and one warning names the setting")
	Do ..RestoreRows()
}

/// A missing key (no_key): the first runner has no key and the retry runner has one, so OnRequest sends the request to the retry runner; with neither
/// key the fallback is no_key and nothing is sent.
Method TestRetryNoKey()
{
	Set process = ..RetryProcess(60)
	Do ..Put("TriageAgent", "ProviderConfig", "{}")
	Set request = ..NewRequest("decide")
	Set sc = process.OnRequest(request, .response)
	Do $$$AssertStatusOK(sc, "OnRequest with no key on the first runner is answered with status OK")
	Do $$$AssertEquals(response, "", "and answers nothing yet")
	Do $$$AssertEquals(..Rows(request.ItemId)_"|"_..Calls("send"), "0|1", "no row, and one request is sent")
	Do $$$AssertEquals($ListGet($Get(^||ZzDecideCalls("send", 1)), 1)_"|"_$Get(^||ZzDecideCalls("send", 1, "retryOf")), "TriageAgentRetry|TriageAgent", "to the retry runner, with RetryOf the first runner")
	Set timer = $Get(^||ZzDecideCalls("timer", 1))
	Do $$$AssertEquals($List(timer, 1)_"|"_$List(timer, 2), "60|timer", "with a timer of 60: no time was used by the first attempt, which was never sent")
	Do ..RestoreRows()

	Set process = ..RetryProcess(60)
	Do ..Put("TriageAgent", "ProviderConfig", "{}")
	Do ..Put("TriageAgentRetry", "ProviderConfig", "{}")
	Set request = ..NewRequest("decide")
	Set sc = process.OnRequest(request, .response)
	Set row = ..RowOf(request.ItemId, "decide")
	Do $$$AssertEquals($Select($IsObject(row): row.Fallback_"|"_row.FallbackReason, 1: "no row"), "1|no_key", "with neither key the fallback is no_key")
	Do $$$AssertEquals(..Calls("send")_"|"_..Calls("timer"), "0|0", "and nothing is sent")
	Do ..RestoreRows()
}

/// The estimate of the retry of a linked continue turn (Stories 17.2 and 17.8): the retry is a fresh turn whose SeedText carries the recap of the stored history, so
/// Decide counts the agent part and the input that Chat gets with the seed, and no stored history; a RetryOf that the request carries by itself changes nothing.
Method TestRetryEstimate()
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set long = ""
	For i = 1:1:8 {
		Set long = long _ $ListBuild($Translate($Justify("", 5000), " ", "a"))
	}
	Set stored = ..NewMessagesSession(long)
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Data.ConversationLink).Point(owner, "ChatAgent", stored), "a link names a stored history of 8 long messages for (owner, ChatAgent)")
	Set turn = ..NewRequest("turn", "user")
	Set turn.OwnerRef = owner
	Set full = $ClassMethod(decide, "EstimateTokens", turn, "ChatAgent", , .sc, .fullHistory)
	Do $$$AssertTrue(fullHistory > 40000, "the first runner's estimate counts the whole stored history: "_fullHistory_" characters")
	Set retry = $ClassMethod(decide, "RetryRequest", turn, ##class(OcuTalon.Bridge.Ids).NewRef(), 0, "ChatAgent")
	Do $$$AssertTrue((retry.SessionMode = "fresh") && (retry.SeedText '= ""), "the retry is a fresh turn with a seed")
	Set retried = $ClassMethod(decide, "EstimateTokens", retry, "ChatAgentRetry", , .sc, .retryHistory, .retryChars)
	Do $$$AssertEquals(retryHistory, 0, "the retry's estimate counts no stored history")
	Set agentChars = $ClassMethod("OcuTalon.Bridge.RequestSize", "AgentChars", "OcuTalon.Agent.Chat")
	Do $$$AssertEquals(retried, ##class(OcuTalon.Bridge.Adapter.StepBuffer).Tokens(agentChars + $Length(##class(OcuTalon.Bridge.Adapter.Agent).ChatInput(retry, 1))), "it is the agent part and the input that Chat gets, the seed included")
	Do $$$AssertTrue(retried < full, "so the retry's estimate is smaller: "_retried_" against "_full)
	Set carried = turn.%ConstructClone()
	Set carried.RetryOf = "ChatAgent"
	Do $$$AssertEquals($ClassMethod(decide, "EstimateTokens", carried, "ChatAgent", , .sc, .carriedHistory), full, "a RetryOf that the request carries does not shorten the estimate of the first attempt")
}

/// --- helpers ---
/// A recorder (Test.Bridge.ZzDecide) for the second-model retry (Story 17.2): runner (TriageAgent) and its Retry item have a model key, the RetryItem of runner
/// names retry (none when retry is empty), the daily cap and the token budget are off, the request-size limit is 100,000, the day is not marked, and TimerSeconds is
/// timer. The rows it puts are put back by RestoreRows (and OnAfterOneTest). The calls of an earlier recorder are forgotten.
Method RetryProcess(timer As %Integer = 60, retry As %String = "TriageAgentRetry", runner As %String = "TriageAgent") As OcuTalon.Test.Bridge.ZzDecide [ Private ]
{
	Do ..PutKey(runner)
	Do ..PutKey(runner_"Retry")
	If retry '= "" Do ..Put(runner, "RetryItem", retry)
	Do ..Unmark()
	Do ..Put("Decide", "DailyCostCapUSD", 0)
	Do ..Put("Decide", "GatewaySpendUSD", "")
	Do ..Put("Decide", "GatewaySpendDate", "")
	Kill ^||ZzDecideCalls, ^||ZzProbeSink, ^||ZzProbeFilter
	Set process = ..NewRecorder()
	Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set process.HostSinkClass = ..#SINK
	Set process.%SessionId = 4270
	Set process.TimerSeconds = timer
	Set process.DecisionTokenBudget = 0
	Set process.RequestTokenLimit = 100000
	Quit process
}

/// Asserts that the estimate of the request (Decide EstimateTokens) is the agent part of the class plus the input that Chat gets (ChatInput, with the seed when
/// seeded is 1), in tokens, with the class given and with the AgentClass setting of the runner; and that the agent part could be read.
Method AssertEstimate(request As OcuTalon.Bridge.Msg.Request, runner As %String, agentClass As %String, seeded As %Boolean, label As %String) [ Private ]
{
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Set chars = $ClassMethod("OcuTalon.Bridge.RequestSize", "AgentChars", agentClass) + $Length(##class(OcuTalon.Bridge.Adapter.Agent).ChatInput(request, seeded))
	Set expected = $ClassMethod("OcuTalon.Bridge.Adapter.StepBuffer", "Tokens", chars)
	Do $$$AssertEquals($ClassMethod(decide, "EstimateTokens", request, runner, agentClass, .sc), expected, label_": "_chars_" characters are "_expected_" tokens, with the seed "_$Select(seeded: "counted", 1: "left out"))
	Do $$$AssertStatusOK(sc, label_": the agent part could be read")
	Do $$$AssertEquals($ClassMethod(decide, "EstimateTokens", request, runner), expected, label_": and so it is with the AgentClass setting of "_runner)
}

/// A request of the kind and provenance whose estimate is exactly the tokens for an agent part of agentChars characters: its input is 4 x tokens - agentChars
/// characters, with no seed, no note and no history.
Method RequestOfTokens(kind As %String, provenance As %String, tokens As %Integer, agentChars As %Integer) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ..NewRequest(kind, provenance)
	Set request.Input = $Translate($Justify("", 4 * tokens - agentChars), " ", "a")
	Quit request
}

/// The length of the system prompt (prompt) and of the tool catalog as JSON (catalog) of a live agent of the class, built with a placeholder key that sends nothing
/// (the pattern of Test.Agent.RunnerFixture SessionExport), the way the runner's adapter builds it (%Init).
Method LiveSizes(class As %String, Output prompt As %Integer, Output catalog As %Integer) [ Private ]
{
	Set agent = $ClassMethod(class, "%New", ##class(%AI.Provider).Create("anthropic", {"api_key": "ocutalon-estimate-reader"}))
	Do $$$AssertStatusOK(agent.%Init(), "a live agent of "_class_" is built")
	Set prompt = $Length(agent.SystemPrompt)
	Set catalog = $Length(agent.ToolManager.%Discover().%ToJSON())
}

/// Saves an AI session whose stored history is chars characters long, built without an agent, and returns its id. OnAfterOneTest deletes it, and the link that names it.
ClassMethod NewSession(chars As %Integer) As %String [ Private ]
{
	Set session = ##class(%AI.Agent.Session).%New()
	Do session.ContextData.Write($Translate($Justify("", chars), " ", "a"))
	If $$$ISERR(session.%Save()) Quit ""
	Quit session.%Id()
}

/// Saves an AI session that stores the messages as a full export (a user message, then an assistant message, and so on; the texts are the list), built without
/// an agent, and returns its id. OnAfterOneTest deletes it, and the link that names it.
ClassMethod NewMessagesSession(texts As %List) As %String [ Private ]
{
	Set messages = []
	Set position = 0
	Set role = "user"
	While $ListNext(texts, position, text) {
		Do messages.%Push({"role": (role), "content": (text)})
		Set role = $Select(role = "user": "assistant", 1: "user")
	}
	Set session = ##class(%AI.Agent.Session).%New()
	Do session.ContextData.Write({"version": 1, "messages": (messages)}.%ToJSON())
	If $$$ISERR(session.%Save()) Quit ""
	Quit session.%Id()
}

/// A recorder (Test.Bridge.ZzDecide) for the key resend, for a process that began the number of seconds ago with that TimerSeconds, whose precheck
/// passes: TriageAgent has a model key, the daily cap and the token budget are off, the request-size limit is 100,000 and the day is not marked. The rows
/// it puts are put back by RestoreRows (and OnAfterOneTest). The calls of an earlier recorder are forgotten.
Method ResendRecorder(timer As %Integer, ago As %Numeric, ref As %String) As OcuTalon.Test.Bridge.ZzDecide [ Private ]
{
	Do ..PutKey("TriageAgent")
	Do ..Unmark()
	Do ..Put("Decide", "DailyCostCapUSD", 0)
	Do ..Put("Decide", "GatewaySpendUSD", "")
	Do ..Put("Decide", "GatewaySpendDate", "")
	Kill ^||ZzDecideCalls, ^||ZzProbeSink
	Set process = ..NewRecorder()
	Set process.ReplyFilterClass = "OcuTalon.Bridge.Ext.ReplyFilter"
	Set process.HostSinkClass = ..#SINK
	Set process.%SessionId = 4253
	Set process.TimerSeconds = timer
	Set process.%TimeCreated = ..Ago(ago)
	Set process.DecisionTokenBudget = 0
	Set process.RequestTokenLimit = 100000
	Set process.DecisionRef = ref
	Quit process
}

/// A Decide that records its timers and its sends (Test.Bridge.ZzDecide), never started or saved.
ClassMethod NewRecorder() As OcuTalon.Test.Bridge.ZzDecide [ Private ]
{
	Quit ##class(OcuTalon.Test.Bridge.ZzDecide).%New("Decide")
}

/// The number of timers ("timer") or sends ("send") that the recorder made.
ClassMethod Calls(kind As %String) As %Integer [ Private ]
{
	Quit +$Get(^||ZzDecideCalls(kind))
}

/// The nth timer or send of the recorder, its arguments joined with a bar.
ClassMethod CallOf(kind As %String, n As %Integer) As %String [ Private ]
{
	Quit $ListToString($Get(^||ZzDecideCalls(kind, n)), "|")
}

/// A UTC time the number of seconds ago, as the process stores %TimeCreated.
ClassMethod Ago(seconds As %Numeric) As %String [ Private ]
{
	Set now = $ZTimeStamp
	Set day = +now
	Set time = $Piece(now, ",", 2) - seconds
	While time < 0 {
		Set time = time + 86400
		Set day = day - 1
	}
	Quit $ZDateTime(day_","_time, 3, 1, 3)
}

/// The types of the events that the probe sink got in this process, in order, comma-separated.
ClassMethod SinkTypes() As %String [ Private ]
{
	Set types = ""
	For n = 1:1:+$Get(^||ZzProbeSink) {
		Set types = types _ $Select(types = "": "", 1: ",") _ $List($Get(^||ZzProbeSink(n)), 1)
	}
	Quit types
}

/// Puts back the System Default Settings rows that the test put, so that the next case starts from the same rows.
Method RestoreRows() [ Private ]
{
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..SavedRows)
	Set ..SavedRows = ""
	Do ..Unmark()
}

/// A Decide instance for the in-process tests: it is never started or saved. Its settings are those of the Decide item of the
/// active production (Ens.Host's initConfig), so a test sets every setting that it relies on.
ClassMethod NewProcess() As OcuTalon.Bridge.Process.Decide [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Process.Decide).%New("Decide")
}

/// An unsaved Decision row of the item and kind with a new Ref, OwnerRef instance and the outcome.
ClassMethod NewRow(itemId As %String, kind As %String, outcome As %String) As OcuTalon.Bridge.Data.Decision [ Private ]
{
	Set row = ##class(OcuTalon.Bridge.Data.Decision).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.Kind = kind
	Set row.ItemId = itemId
	Set row.OwnerRef = "instance"
	Set row.Outcome = outcome
	Quit row
}

/// A request of the kind and provenance with a fresh ItemId, which the test deletes the rows of afterwards.
Method NewRequest(kind As %String, provenance As %String = "untrusted") As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = provenance
	Set request.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = "instance"
	Set request.Summary = "Test "_request.ItemId
	Set request.Input = "Triage this item."
	Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
	Quit request
}

/// A runner's failure Reply: no text, and the failure text as the runner's FailureText.
ClassMethod FailedReply(failure As %String) As OcuTalon.Bridge.Msg.Reply [ Private ]
{
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.FailureText = failure
	Quit reply
}

/// Starts a process that holds the conversation lock of (owner, agent) (Hold), and waits up to 30 seconds until it holds it. 1 when it does. Each
/// StartHolder is paired with a StopHolder of the owner on every path. TestBusyRelayed and Test.Bridge.Link use it.
ClassMethod StartHolder(owner As %String, agent As %String) As %Boolean
{
	Kill ^IRIS.Temp.ZzDecideStop(owner), ^IRIS.Temp.ZzDecideHeld(owner)
	Job ##class(OcuTalon.Test.Bridge.Decide).Hold(owner, agent)
	Set deadline = $ZHorolog + 30
	While '$Data(^IRIS.Temp.ZzDecideHeld(owner)) && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Quit ''$Data(^IRIS.Temp.ZzDecideHeld(owner))
}

/// Tells the process of StartHolder for the owner to release the lock and end, and waits up to 30 seconds until it has. 1 when it has (also when no
/// such process runs). Its marks are removed either way.
ClassMethod StopHolder(owner As %String) As %Boolean
{
	Set ^IRIS.Temp.ZzDecideStop(owner) = 1
	Set deadline = $ZHorolog + 30
	While $Data(^IRIS.Temp.ZzDecideHeld(owner)) && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Set stopped = '$Data(^IRIS.Temp.ZzDecideHeld(owner))
	Kill ^IRIS.Temp.ZzDecideStop(owner), ^IRIS.Temp.ZzDecideHeld(owner)
	Quit stopped
}

/// The job of StartHolder: holds the conversation lock of (owner, agent) until StopHolder says stop, reporting through
/// ^IRIS.Temp.ZzDecideHeld(owner) while it holds it. It gives up after 60 seconds on its own.
ClassMethod Hold(owner As %String, agent As %String)
{
	Lock +^OcuTalonBP.Conv(owner, agent):5
	If '$Test Quit
	Set ^IRIS.Temp.ZzDecideHeld(owner) = $Job
	Set deadline = $ZHorolog + 60
	While '$Data(^IRIS.Temp.ZzDecideStop(owner)) && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Lock -^OcuTalonBP.Conv(owner, agent)
	Kill ^IRIS.Temp.ZzDecideHeld(owner)
}

/// A runner's reply with the text, and the finish reason if one is given.
ClassMethod NewReply(text As %String, finishReason As %String = "") As OcuTalon.Bridge.Msg.Reply [ Private ]
{
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set reply.Text = text
	Set reply.FinishReason = finishReason
	Quit reply
}

/// Conclude for the request, with a Ref of its own, the reply check against DecisionPayload, the filter and the sink (the do-
/// nothing bases by default) and the trace session 4242.
ClassMethod Conclude(request As OcuTalon.Bridge.Msg.Request, reply As OcuTalon.Bridge.Msg.Reply, Output response, filter As %String = "OcuTalon.Bridge.Ext.ReplyFilter", sink As %String = "OcuTalon.Bridge.Ext.HostSink") As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ##class(OcuTalon.Bridge.Ids).NewRef(), reply, ..#REPLYCLASS, filter, sink, 4242, .response)
}

/// Conclude as the helper above does, for a DecisionRef that the test chose (the Usage rows of the decision carry it) and with the
/// duration that Decide measured, and the failure text of the runner, if any. response is the answer.
ClassMethod ConcludeWith(request As OcuTalon.Bridge.Msg.Request, ref As %String, reply As OcuTalon.Bridge.Msg.Reply, durationMs As %Integer, Output response, filter As %String = "OcuTalon.Bridge.Ext.ReplyFilter", sink As %String = "OcuTalon.Bridge.Ext.HostSink", failure As %String = "") As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Process.Decide).Conclude(request, ref, reply, ..#REPLYCLASS, filter, sink, 4242, .response, durationMs, failure)
}

/// A new DecisionRef for Usage rows, which the test deletes the rows of afterwards.
Method NewUsageRef() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..UsageRefs = ..UsageRefs _ $ListBuild(ref)
	Quit ref
}

/// Saves a Usage row of the DecisionRef (Test.Agent.RunnerFixture.AddUsage).
Method AddUsage(ref As %String, model As %String, input As %Integer, completion As %Integer, cacheRead As %Integer, cacheWrite As %Integer, cost As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).AddUsage(ref, model, input, completion, cacheRead, cacheWrite, cost), "a Usage row of "_model_" is saved")
}

/// The eight total fields of a Decision row or an answer, in the order of Result: InputTokens, OutputTokens, CacheReadTokens,
/// CacheWriteTokens, CostUSD, Model, AgentStepCount and DurationMs, joined by | (Test.Agent.RunnerFixture.Totals).
ClassMethod Totals(object As %RegisteredObject) As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).Totals(object)
}

/// The number of Decision rows of the item.
ClassMethod Rows(itemId As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The Decision row of the item and kind, or "" (Test.Agent.RunnerFixture.DecisionOf, which needs no production).
ClassMethod RowOf(itemId As %String, kind As %String) As OcuTalon.Bridge.Data.Decision [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).DecisionOf(itemId, kind)
}

/// Asserts that Admit refuses the request with an error that names the field.
Method AssertNamed(request As OcuTalon.Bridge.Msg.Request, field As %String, label As %String) [ Private ]
{
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).Admit(request)
	Do $$$AssertStatusNotOK(sc, label_" is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ field, "and the error names "_field_": "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertNotTrue($SYSTEM.Status.GetErrorCodes(sc) = 5003, "and it is not the 'not implemented' error")
}

/// Asserts that CheckReply passes (pass is 1) or fails with an error that names the reply check (pass is 0) for the text.
Method AssertReply(text As %String, pass As %Boolean, label As %String) [ Private ]
{
	Set sc = ##class(OcuTalon.Bridge.Process.Decide).CheckReply(text, ..#REPLYCLASS, .payload)
	If pass {
		Do $$$AssertStatusOK(sc, label_" passes")
		Do $$$AssertTrue($IsObject(payload), label_" gives the payload")
		Quit
	}
	Do $$$AssertStatusNotOK(sc, label_" fails")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "reply check", label_" fails with an error that names the reply check")
	Do $$$AssertEquals(payload, "", label_" gives no payload")
}

/// The number of warnings of Decide's EmitSteps after the mark that name the DecisionRef and hold the needle, if one is given.
ClassMethod EmitWarnings(mark As %Integer, ref As %String, needle As %String = "") As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Process.Decide", "EmitSteps", $ListBuild(ref, needle))
}

/// The number of warnings of Decide's StepMessages after the mark that name the DecisionRef.
ClassMethod WarningsOf(mark As %Integer, ref As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Process.Decide", "StepMessages", $ListBuild(ref))
}

/// The number of event-log rows after the mark whose text holds the value (Test.Agent.RunnerFixture.LogRowsHolding).
ClassMethod LogRowsHolding(mark As %Integer, value As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).LogRowsHolding(mark, value)
}

/// The highest id of the event log (Test.Agent.RunnerFixture.EventMark).
ClassMethod LogMark() As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
}

/// Asserts that the event log holds, after the mark, one warning (type 3) of Decide's FireEvent whose text names the class, the
/// Ref and, when given, the event. Outside a production job its ConfigName is empty (measured in Story 1.3).
Method AssertWarning(mark As %Integer, class As %String, ref As %String, label As %String, event As %String = "") [ Private ]
{
	Set found = ##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Process.Decide", "FireEvent", $ListBuild(class, ref, event))
	Do $$$AssertEquals(found, 1, label_": one warning names "_class_" and the Ref")
}

/// Conclude of the request and reply (and the runner's failure text, if one is given), with a Usage row of the decision, and the
/// assertions that every fallback shares: status OK; one row with the outcome tellnow, Fallback true, the reason expected and no reasons,
/// confidence or payload; the totals of the decision; one decision.recorded, after the save and outside any transaction; and an answer
/// that holds none of the model's refused text (the marker zzrefusedtext), is a new Reply with nothing but the verdict, the totals and the
/// flags of the runner's reply (Tainted and ToolsRun; SessionRotated 0, SessionBroken as broken says, and never Busy) for a turn, and a
/// DecisionResponse of the row otherwise.
Method AssertFallback(label As %String, request As OcuTalon.Bridge.Msg.Request, reply As %RegisteredObject, failure As %String, expected As %String, filter As %String = "OcuTalon.Bridge.Ext.ReplyFilter", broken As %Boolean = 0) [ Private ]
{
	Kill ^||ZzProbeSink, ^||ZzProbeFilter
	Set ref = ..NewUsageRef()
	Do ..AddUsage(ref, "claude-haiku-5-5", 3800, 300, 2000, 600, .000365)
	Set isReply = $IsObject(reply) && reply.%IsA("OcuTalon.Bridge.Msg.Reply")
	Set before = $Select(isReply: reply.Text_"|"_reply.FinishReason_"|"_reply.Steps_"|"_reply.HostData_"|"_reply.FailureText_"|"_reply.Tainted, 1: "")
	Set sc = ..ConcludeWith(request, ref, reply, 987, .response, filter, ..#SINK, failure)
	Do $$$AssertStatusOK(sc, label_": Conclude records a fallback")
	Set row = ..RowOf(request.ItemId, request.Kind)
	If '$IsObject(row) || '$IsObject(response) {
		Do $$$AssertTrue(0, label_": a row is recorded and an answer is given")
		Quit
	}
	Set steps = $Select(isReply: reply.AgentStepCount, 1: 0)
	Do $$$AssertEquals(row.Outcome_"|"_row.Fallback_"|"_row.FallbackReason, "tellnow|1|"_expected, label_": the row is a tellnow fallback with the reason "_expected)
	Do $$$AssertEquals(row.Reasons_"|"_row.Confidence_"|"_row.Payload, "||", label_": it holds no reasons, confidence or payload")
	Do $$$AssertEquals(row.Ref_"|"_row.TraceSessionId, ref_"|4242", label_": with the DecisionRef given and the session")
	Do $$$AssertEquals(..Totals(row), "3800|300|2000|600|.000365|claude-haiku-5-5|"_steps_"|987", label_": and the totals of the decision")
	Do $$$AssertEquals(..Totals(response), ..Totals(row), label_": the answer carries the same totals")
	Do $$$AssertEquals(response.DecisionRef_"|"_response.Outcome_"|"_response.Fallback_"|"_response.FallbackReason, row.Ref_"|tellnow|1|"_expected, label_": and the verdict of the row")
	Do $$$AssertEquals(response.Reasons_"|"_response.Confidence, "|", label_": with no reasons or confidence")
	Do $$$AssertEquals(+$Get(^||ZzProbeSink), 1, label_": one event is sent")
	Set call = $Get(^||ZzProbeSink(1))
	Do $$$AssertEquals($List(call, 1)_"|"_$List(call, 3)_"|"_$List(call, 4)_"|"_$List(call, 5), "decision.recorded|{""ref"":"""_ref_"""}|0|1", label_": it is decision.recorded, sent after the save and outside any transaction")
	Do $$$AssertStatusOK(response.XMLExportToString(.xml), label_": the answer is exported as XML")
	Do $$$AssertTrue(xml [ "<Fallback>true</Fallback>", label_": the XML shows Fallback true")
	Do $$$AssertTrue(xml [ ("<FallbackReason>"_expected_"</FallbackReason>"), label_": and the reason")
	Do $$$AssertTrue(xml '[ "zzrefusedtext", label_": the model's refused text is in no field of the answer")
	If request.Kind = "turn" {
		Do $$$AssertTrue(response.%IsA("OcuTalon.Bridge.Msg.Reply"), label_": a turn is answered with a Reply")
		Do $$$AssertEquals(response.Text_"|"_response.HostData_"|"_response.Steps_"|"_response.FailureText_"|"_response.FinishReason, "||||", label_": with no text, host data, steps, failure text or finish reason")
		Do $$$AssertEquals(response.SessionRotated_"|"_response.SessionBroken_"|"_response.Busy, "0|"_(+broken)_"|0", label_": SessionRotated is 0 whatever the runner's reply says, SessionBroken is Decide's ("_(+broken)_") and the answer is not Busy")
		Do $$$AssertEquals(response.Tainted_"|"_response.ToolsRun, $Select(isReply: +reply.Tainted_"|"_+reply.ToolsRun, 1: "0|0"), label_": but the taint and the tools-run flag of the runner's reply (none when there is no reply)")
		If $IsObject(reply) Do $$$AssertTrue(response '= reply, label_": it is a new Reply, not the runner's")
		If isReply Do $$$AssertEquals(reply.Text_"|"_reply.FinishReason_"|"_reply.Steps_"|"_reply.HostData_"|"_reply.FailureText_"|"_reply.Tainted, before, label_": and the runner's own Reply is not changed")
	} Else {
		Do $$$AssertTrue(response.%IsA("OcuTalon.Bridge.Msg.DecisionResponse"), label_": a decide or diagnose request is answered with a DecisionResponse")
		Do $$$AssertEquals(response.Payload, "", label_": with no payload")
	}
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

/// Gives the runner item a model key for the test: an inline provider configuration whose api_key names PATH, which is set in this process.
Method PutKey(item As %String) [ Private ]
{
	Do ..Put(item, "ProviderConfig", "{""api_key"":""@{env:PATH}""}")
}

/// Removes the mark of today's day, and again when the test is over.
Method Unmark() [ Private ]
{
	Set ..DayMarked = 1
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
}

/// The number of warnings of a recorder's Precheck (Test.Bridge.ZzDecide, a subclass of Decide) after the mark that hold the needle: a class method logs under the
/// class of the instance that calls it, so the recorder's warnings are those of ZzDecide.
ClassMethod RecorderWarnings(mark As %Integer, needle As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Test.Bridge.ZzDecide", "Precheck", $ListBuild(needle))
}

/// The number of warnings of Decide's Precheck after the mark that hold the needle.
ClassMethod PrecheckWarnings(mark As %Integer, needle As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Process.Decide", "Precheck", $ListBuild(needle))
}

}
