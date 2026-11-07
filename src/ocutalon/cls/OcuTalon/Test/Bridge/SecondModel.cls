/// Tests of the second-model retry over the running production (Story 17.2; AD-6, AD-8, AD-19, AD-20, AD-22, DW-647, DW-650; lead rulings U-281 and U-282).
/// THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), against the CI mock: they need OcuTalon.Production running with its six runner items and the CI
/// override's environment. The entries of the six runners are pointed at the mock key variable (Test.Agent.RunnerFixture PointKeys and RestoreKeys with the
/// retry runners), a test names a second model by two System Default Settings rows (the RetryItem of the first runner and the Model of the retry runner, here
/// claude-sonnet-5-5), and OnAfterOneTest deletes every row a test wrote (Test.Bridge.SettingsStubs expects no RetryItem row anywhere), puts back the agent
/// of a retry runner that a test swapped, starts the changed items again, waits for the late replies of the first attempts, and removes the decisions, usage rows, steps and AI sessions of the test. The countdown of
/// the mock (POST /_mock/countdown) is armed at 1 for the retry scenarios, so that the first attempt gets the first reply and the retry the second.
///   - TestRetryAnswers: a decide request whose first attempt is refused, cut off, empty, a provider error, held past the timer (T 12) or rate limited late (T 12)
///     is answered by the second model: one runner request each, the same DecisionRef, the retry's RetryOf, one row and one answer, the Model of the second
///     model and the sums of the Usage rows and steps; the mock saw the second model's model with the cap in its family's key;
///   - TestRetryFails: the same cases with a retry that fails too give release 1's fallback with the retry's reason (the one-reply scenarios, decide-late, overloaded,
///     and retry-refusal-then-error for the retry's own reason), with one row, one answer and no second retry;
///   - TestNeverRetried: a token budget of 1, a day that is capped, a request-size limit of 1 and the gateway's 403 fall back with no request to the retry runner;
///   - TestRetryBudgetOwnEstimate (DW-855): a first attempt whose estimate fits DecisionTokenBudget and is refused is not retried when the retry's own estimate (its runner
///     reads a larger agent) is above the budget: one request to the first runner, none to the retry runner, the fallback reason budget;
///   - TestNoSecondModel: with no RetryItem a refusal is release 1's fallback after one runner request;
///   - TestDiagnosisRetried: a diagnose request is retried on DiagnosisAgentRetry;
///   - TestRetriedTurnKeepsTheConversation: a user's turn that is refused is answered by the second model in a session seeded with the messages the first attempt
///     began with, neither the seed nor the next turn holds the refused exchange (DW-726), and the next turn carries the retried exchange; a turn whose timer fires
///     is not retried (R2), and its late first attempt still saves its conversation;
///   - TestLateFreshTurnMovesNothing (Story 17.8, DW-730): a fresh turn that takes the timeout fallback and finishes late saves its session and moves nothing, so
///     the link still names the session the user saw and the next turn's history is that session's, without the late exchange;
///   - TestRetryOfFromTheWebIsIgnored (DW-650 c): a RetryOf in the body of POST /v1/messages is dropped, and a request with a RetryOf sent to Decide waits for the
///     conversation lock, so the request that reaches ChatAgent has none;
///   - TestIntegrationWebChat (Rule 1): a message through WebChatIn to the real Conversation and Decide, with a second model on ChatAgent and a refused first
///     attempt, is answered by the second model with no fallback, and the next message is answered with that exchange in its history and none of the refused one.
Class OcuTalon.Test.Bridge.SecondModel Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzsecond";

/// Seconds to wait for a turn through the mock.
Parameter WAIT = 90;

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

/// The second model.
Parameter SECOND = "claude-sonnet-5-5";

/// The reason line of the second model's decide reply (ci/mock/scenarios/A/retry-*.json).
Parameter SECONDREASON = "The CI mock answers on the second model.";

/// The text of the second model's turn reply (retry-chat.json).
Parameter SECONDTEXT = "The second model answers the turn.";

/// The recorded evaluation snapshot, as mounted in a throwaway.
Parameter SNAPSHOT = "/opt/ocutalon/eval/orders-date-format/snapshot.json";

/// The longest to wait for a late reply to reach its runner, in seconds.
Parameter LATESECONDS = 120;

/// 1 while the entries of the six runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

/// The countdowns of the mock that the test armed, as a list of markers, to be cleared.
Property Armed As %List;

/// The System Default Settings rows before the test touched them (RunnerFixture RememberDefault), to be put back.
Property SavedRows As %List;

/// The items to start again after the rows are put back.
Property Restarts As %List;

/// What RunnerFixture UseAgent saved of TriageAgentRetry when a test swapped its agent (an object with allowListSet), for OnAfterOneTest to put back; anything
/// else means that no agent is swapped.
Property SavedAgent As %DynamicObject;

/// The replies that a test leaves late, as a list of $ListBuild(session, runner item) to wait for.
Property Late As %List;

/// The mark of the saved AI sessions when the test began (RunnerFixture SessionMark).
Property SessionMark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set fixture = ..#FIXTURE
	Set position = 0
	While $ListNext(..Armed, position, marker) {
		Do $ClassMethod(..#MOCK, "Arm", marker, "")
	}
	Set ..Armed = ""
	Set position = 0
	While $ListNext(..Late, position, one) {
		Do $ClassMethod(fixture, "WaitForAnswer", $List(one, 1), $List(one, 2))
	}
	Set ..Late = ""
	Do $ClassMethod(fixture, "DropSince", ..SessionMark)
	If $IsObject(..SavedAgent) && ..SavedAgent.%IsDefined("allowListSet") {
		Do $$$AssertStatusOK($ClassMethod(fixture, "RestoreAgent", "TriageAgentRetry", ..SavedAgent), "TriageAgentRetry's agent is put back")
		Set ..SavedAgent = ""
	}
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do $ClassMethod(fixture, "DeleteSteps", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Do $ClassMethod(fixture, "RestoreDefaults", ..SavedRows)
	Set ..SavedRows = ""
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	Set position = 0
	While $ListNext(..Restarts, position, item) {
		Do $ClassMethod(fixture, "Restart", ..#PRODUCTION_"||"_item)
	}
	Set ..Restarts = ""
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	If ..Pointed && $ClassMethod(..#FIXTURE, "Running") {
		Set ..Pointed = 0
		Do $ClassMethod(..#FIXTURE, "RestoreKeys", ..Runners())
	}
	Quit ##super()
}

/// A decide request whose first attempt gets the first reply of a retry scenario is answered by the second model: one request to each runner with the
/// same DecisionRef and the retry's RetryOf, one row and one answer, the second model's Model and the sums of the Usage rows and steps. The timeout
/// case (T 12, the first reply held for 20 s) is answered by the retry some 12 s after the send, and the late reply of the first attempt is discarded
/// but still writes its Usage row under the DecisionRef. The rate-limit case (T 12, a 529 after 10.5 s) is retried too.
Method TestRetryAnswers()
{
	If '..Prepare() Quit
	Do ..UseSecondModel("Triage")
	For marker = "retry-refusal", "retry-max-tokens", "retry-empty", "retry-provider-error" {
		Do ..Arm(marker, 1)
		Set request = ..Ask("decide", "[[mock:"_marker_"]] Triage this item.", .ref)
		Set mark = $ClassMethod(..#MOCK, "LogMark")
		Set sc = $ClassMethod(..#FIXTURE, "Run", request, .response, .session)
		Do $$$AssertStatusOK(sc, marker_": Decide answers")
		Do ..AssertAnswered(marker_": ", request, response, session, mark)
	}

	// the timer fires on a held first reply
	Do ..UseTimer(12)
	Do ..Arm("retry-held", 1)
	Set request = ..Ask("decide", "[[mock:retry-held]] Triage this item.", .ref)
	Set started = $ZHorolog
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .response, .session)
	Set elapsed = $ZHorolog - started
	Set ..Late = ..Late _ $ListBuild($ListBuild(session, "TriageAgent"))
	Do $$$AssertStatusOK(sc, "retry-held: Decide answers")
	Do $$$AssertTrue((elapsed '< 11) && (elapsed < 20), "retry-held: the retry answers some 12 seconds after the send, the timer of the first attempt: "_$Number(elapsed, 1)_" s")
	Do ..AssertAnswered("retry-held: ", request, response, session)
	Set row = $ClassMethod(..#FIXTURE, "DecisionOf", request.ItemId, "decide")
	Do $$$AssertTrue(..WaitLate(session, "TriageAgent"), "retry-held: TriageAgent answers the late request")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "UsageIds", "DecisionRef", row.Ref).%Size(), 2, "retry-held: and the late first attempt's Usage row lands under the DecisionRef")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "CountTo", $ClassMethod(..#FIXTURE, "Headers", session, "Decide"), "AgentSteps"), 1, "retry-held: only the retry's step was sent: the late reply is discarded")

	// a rate limit that ends after the re-sends have no time left
	Do ..Arm("retry-overloaded-late", 1)
	Set request = ..Ask("decide", "[[mock:retry-overloaded-late]] Triage this item.", .ref)
	Set started = $ZHorolog
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .response, .session)
	Set elapsed = $ZHorolog - started
	Set ..Late = ..Late _ $ListBuild($ListBuild(session, "TriageAgent"))
	Do $$$AssertStatusOK(sc, "retry-overloaded-late: Decide answers")
	Do $$$AssertTrue(elapsed < 40, "retry-overloaded-late: within the two timers: "_$Number(elapsed, 1)_" s")
	Do ..AssertAnswered("retry-overloaded-late: ", request, response, session)
}

/// The same cases with a retry that fails too give release 1's fallback, with the last attempt's reason: the one-reply scenarios fail twice (refusal, cut_off, empty, error, invalid),
/// and retry-refusal-then-error fails the retry with error although the first attempt was refused. A held first reply and a held retry (decide-late, T 12) end at
/// the second timer with timeout, and an overload that does not end (overloaded) with rate_limited after one retry request, which is never sent again. Each case is one row
/// and one answer, with one request to the retry runner and no tool, fix or approval.
Method TestRetryFails()
{
	If '..Prepare() Quit
	Do ..UseSecondModel("Triage")
	For case = $ListBuild("refusal", "refusal", 0), $ListBuild("max-tokens", "cut_off", 0), $ListBuild("empty", "empty", 0), $ListBuild("provider-error", "error", 0), $ListBuild("invalid-reply", "invalid", 0), $ListBuild("retry-refusal-then-error", "error", 1) {
		Set marker = $List(case, 1)
		Set reason = $List(case, 2)
		If $List(case, 3) Do ..Arm(marker, 1)
		Set request = ..Ask("decide", "[[mock:"_marker_"]] Triage this item.", .ref)
		Set sc = $ClassMethod(..#FIXTURE, "Run", request, .response, .session)
		Do $$$AssertStatusOK(sc, marker_": Decide answers")
		Do ..AssertFellBack(marker_": ", request, response, session, reason, 1)
	}

	// held past both timers
	Do ..UseTimer(12)
	Set request = ..Ask("decide", "[[mock:decide-late]] Triage this item.", .ref)
	Set started = $ZHorolog
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .response, .session)
	Set elapsed = $ZHorolog - started
	Set ..Late = ..Late _ $ListBuild($ListBuild(session, "TriageAgent"), $ListBuild(session, "TriageAgentRetry"))
	Do $$$AssertStatusOK(sc, "decide-late: Decide answers")
	Do $$$AssertTrue((elapsed '< 22) && (elapsed < 32), "decide-late: the retry's timer ends it some 24 seconds after the send: "_$Number(elapsed, 1)_" s")
	Do ..AssertFellBack("decide-late: ", request, response, session, "timeout", 1)

	// an overload that does not end
	Set request = ..Ask("decide", "[[mock:overloaded]] Triage this item.", .ref)
	Set started = $ZHorolog
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .response, .session)
	Set elapsed = $ZHorolog - started
	Do $$$AssertStatusOK(sc, "overloaded: Decide answers")
	Do $$$AssertTrue(elapsed < 32, "overloaded: within the two timers: "_$Number(elapsed, 1)_" s")
	Do ..AssertFellBack("overloaded: ", request, response, session, "rate_limited", 1)
}

/// What is never retried: a token budget of 1, a day that is capped, a request-size limit of 1 and the gateway's 403 fall back with the reason of release 1, and no
/// request goes to the retry runner (and none to the first runner for the three prechecks).
Method TestNeverRetried()
{
	If '..Prepare() Quit
	Do ..UseSecondModel("Triage")
	Set today = ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())

	Do ..Put("Decide", "DecisionTokenBudget", 1)
	Do ..UseDecideRestart()
	Set request = ..Ask("decide", "Triage this item.", .ref)
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "budget: Decide answers")
	Do ..AssertFellBack("budget: ", request, response, session, "budget", 0)
	Do $$$AssertEquals(..SentTo(session, "TriageAgent"), 0, "budget: and nothing reached the first runner either")
	Do ..Put("Decide", "DecisionTokenBudget", 0)

	Do ..Put("Decide", "RequestTokenLimit", 1)
	Do ..UseDecideRestart()
	Set request = ..Ask("decide", "Triage this item.", .ref)
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "too_large: Decide answers")
	Do ..AssertFellBack("too_large: ", request, response, session, "too_large", 0)
	Do $$$AssertEquals(..SentTo(session, "TriageAgent"), 0, "too_large: and nothing reached the first runner either")
	Do ..Put("Decide", "RequestTokenLimit", 100000)
	Do ..UseDecideRestart()

	Set ^OcuTalonBP.UsageCapped(today) = ##class(OcuTalon.Bridge.Time).NowUtc()
	Set request = ..Ask("decide", "Triage this item.", .ref)
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "daily_cap (precheck): Decide answers")
	Do ..AssertFellBack("daily_cap (precheck): ", request, response, session, "daily_cap", 0)
	Do $$$AssertEquals(..SentTo(session, "TriageAgent"), 0, "daily_cap (precheck): and nothing reached the first runner either")
	Kill ^OcuTalonBP.UsageCapped(today)

	Set request = ..Ask("decide", "[[mock:daily-cap]] Triage this item.", .ref)
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "daily_cap (gateway 403): Decide answers")
	Do ..AssertFellBack("daily_cap (gateway 403): ", request, response, session, "daily_cap", 0)
	Do $$$AssertEquals(..SentTo(session, "TriageAgent"), 1, "daily_cap (gateway 403): the first runner was asked once")
}

/// DecisionTokenBudget is checked again for the second-model retry, on the retry's own estimate (DW-855; AD-8, the guide's DecisionTokenBudget row). The retry runner
/// reads the larger Chat agent (RunnerFixture UseAgent, put back by OnAfterOneTest), so the retry's estimate is above the first attempt's. The budget is the first attempt's estimate: the first attempt
/// fits it, is sent and is refused (retry-refusal), and the retry is never sent, so the fallback reason is budget (the retry's precheck) with one request to the first runner
/// and none to the retry runner. The estimates are worked out here with Decide's own methods, and the test asserts that the retry's is the larger, so a setup that makes
/// them equal fails here and not by chance.
Method TestRetryBudgetOwnEstimate()
{
	If '..Prepare() Quit
	Set decide = "OcuTalon.Bridge.Process.Decide"
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "UseAgent", "TriageAgentRetry", "OcuTalon.Agent.Chat", .saved), "the retry runner reads the Chat agent")
	Set ..SavedAgent = $Get(saved)
	Do ..UseSecondModel("Triage")
	Do ..Arm("retry-refusal", 1)
	Set request = ..Ask("decide", "[[mock:retry-refusal]] Triage this item.", .ref)
	Set first = $ClassMethod(decide, "EstimateTokens", request, "TriageAgent")
	Set second = $ClassMethod(decide, "EstimateTokens", $ClassMethod(decide, "RetryRequest", request, "ref", 0, "TriageAgent", ""), "TriageAgentRetry")
	Do $$$AssertTrue((first > 0) && (second > first), "the retry's own estimate is above the first attempt's: "_first_" and "_second)
	If '((first > 0) && (second > first)) Quit
	Do ..Put("Decide", "DecisionTokenBudget", first)
	Do ..UseDecideRestart()
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "Decide answers")
	Do ..AssertFellBack("retry over budget: ", request, response, session, "budget", 0)
	Do $$$AssertEquals(..SentTo(session, "TriageAgent"), 1, "retry over budget: the first attempt fitted the budget and was sent once")
	Do $$$AssertEquals(..SentTo(session, "TriageAgentRetry"), 0, "retry over budget: and the retry, whose own estimate is above the budget, was never sent")
}

/// With no RetryItem (what the install leaves; the test writes the empty row itself, so a row that another run left cannot decide it) a refused reply is
/// release 1's fallback after one runner request, and Decide never touches the retry runner.
Method TestNoSecondModel()
{
	If '..Prepare() Quit
	Do ..Put("TriageAgent", "RetryItem", "")
	Set request = ..Ask("decide", "[[mock:refusal]] Triage this item.", .ref)
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "Decide answers")
	Do ..AssertFellBack("no RetryItem: ", request, response, session, "refusal", 0)
	Do $$$AssertEquals(..SentTo(session, "TriageAgent"), 1, "exactly one runner request reached the first runner")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "Targets", $ClassMethod(..#FIXTURE, "Headers", session, "Decide")), "AgentSteps,ApprovalStartIn,Ens.Alarm,TriageAgent", "and Decide sent nothing to the retry runner")
}

/// A diagnose request is retried on DiagnosisAgentRetry: the first attempt fails with a provider error and the retry's reply is the usable diagnosis, which the row and
/// the answer carry with the second model.
Method TestDiagnosisRetried()
{
	If '..Prepare() Quit
	Set pack = "OcuTalon.Watch.EvidencePack"
	If '##class(%File).Exists(..#SNAPSHOT) {
		Do $$$AssertTrue(0, "the recorded snapshot is at "_..#SNAPSHOT_": this class runs in a throwaway, which mounts eval/ read-only")
		Quit
	}
	Do ..UseSecondModel("Diagnosis")
	Do $$$AssertStatusOK($ClassMethod(pack, "Load", ..#SNAPSHOT, .snapshot), "the snapshot is loaded")
	Do $$$AssertStatusOK($ClassMethod(pack, "Build", snapshot, .built), "the pack is built from it")
	If '$IsObject($Get(built)) Quit
	Do ..Arm("retry-diagnosis", 1)
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", "diagnose", "untrusted", $ClassMethod(pack, "Input", built)_" [[mock:retry-diagnosis]]", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "Decide answers the diagnose request")
	If '$IsObject(response) || 'response.%IsA("OcuTalon.Bridge.Msg.DecisionResponse") {
		Do $$$AssertTrue(0, "the answer is a DecisionResponse")
		Quit
	}
	Do $$$AssertEquals(response.Fallback_"|"_response.FallbackReason_"|"_response.Model, "0||"_..#SECOND, "the diagnosis is usable and the second model's")
	Set payload = {}.%FromJSON(response.Payload)
	Do $$$AssertEquals(payload.causeCategory_"|"_payload.elementAtFault_"|"_payload.fixKind, "data_format_change|OrderDate|repair_resend", "it names the data-format change")
	Set row = $ClassMethod(..#FIXTURE, "DecisionOf", ref, "diagnose")
	Do $$$AssertTrue($IsObject(row), "one row is recorded")
	If $IsObject(row) Do $$$AssertEquals(row.Payload_"|"_row.Outcome_"|"_row.Model, response.Payload_"|act|"_..#SECOND, "which holds the same payload, the outcome act and the second model")
	Set headers = $ClassMethod(..#FIXTURE, "Headers", session, "Decide")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "CountTo", headers, "DiagnosisAgent")_"|"_$ClassMethod(..#FIXTURE, "CountTo", headers, "DiagnosisAgentRetry"), "1|1", "one request went to each runner")
	Set retried = ..RequestsTo(session, "DiagnosisAgentRetry")
	Do $$$AssertEquals($ListToString(retried, ";"), "DiagnosisAgent|"_$Piece($List(retried, 1), "|", 2)_"|"_ref, "the retry request names the first runner and carries the item")
	Do $$$AssertEquals(..RowCount(ref, "diagnose"), 1, "and there is one row")
}

/// A user's turn through Decide with a second model on ChatAgent. The first turn tells ChatAgent a fact. The second is refused by the first attempt
/// (retry-chat, armed at 1): the retry runs in a new session seeded with the stored conversation and answers, the Reply is no fallback and has SessionRotated 1, and the
/// link now names the retry's session. The third turn's request carries the seed, the retried exchange and its own input. Then, with T 12, a turn whose first attempt is
/// held past the timer (retry-chat-held) is not retried (R2): a timeout fallback after one request, and no request to ChatAgentRetry; the late first attempt still
/// saves into the conversation it opened.
Method TestRetriedTurnKeepsTheConversation()
{
	If '..Prepare() Quit
	Do ..UseSecondModel("Chat")
	Set fixture = ..#FIXTURE
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set one = $ClassMethod(fixture, "NewRequest", "turn", "user", "My build server is called ORION-7.", .ref1, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref1)
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", one, .told, .session1), "the first turn is answered")
	Do $$$AssertEquals($Select($IsObject(told): told.Text_"|"_told.Fallback, 1: "none"), "The CI mock looked at the productions.|0", "by ChatAgent, with the text of its default script")
	Set s1 = ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, "ChatAgent")
	Do $$$AssertTrue(s1 '= "", "the link names the session S1: "_s1)
	Set refusal = "The CI mock refuses this request."
	Set seed = ##class(OcuTalon.Bridge.Compaction).Seed(##class(OcuTalon.Bridge.RequestSize).StoredMessages(s1))
	Do $$$AssertTrue((seed [ "ORION-7") && (seed '[ refusal), "the seed of S1 as the turn finds it holds the first turn only: "_$Translate($Extract(seed, 1, 300), $Char(10), "~"))

	Do ..Arm("retry-chat", 1)
	Set two = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:retry-chat]] What is my build server called?", .ref2, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref2)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set sc = $ClassMethod(fixture, "Run", two, .answer, .session2)
	Do $$$AssertStatusOK(sc, "the second turn is answered")
	Do $$$AssertEquals($Select($IsObject(answer): answer.Text_"|"_answer.Fallback_"|"_answer.SessionRotated_"|"_answer.Model, 1: "none"), ..#SECONDTEXT_"|0|1|"_..#SECOND, "by the second model: no fallback, SessionRotated 1: "_$Select($IsObject(answer): answer.Text_"|"_answer.Fallback_"|"_answer.FallbackReason_"|"_answer.SessionRotated_"|"_answer.Model, 1: "none"))
	Set row = $ClassMethod(fixture, "DecisionOf", ref2, "turn")
	Do $$$AssertEquals($Select($IsObject(row): row.Fallback_"|"_row.Model, 1: "no row"), "0|"_..#SECOND, "one row records the second model")
	Do $$$AssertEquals(..RowCount(ref2, "turn"), 1, "and it is the only row")
	Set headers = $ClassMethod(fixture, "Headers", session2, "Decide")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", headers, "ChatAgent")_"|"_$ClassMethod(fixture, "CountTo", headers, "ChatAgentRetry"), "1|1", "one request went to each runner")
	Set retried = ..RequestsTo(session2, "ChatAgentRetry")
	Do $$$AssertEquals($ListToString(retried, ";"), "ChatAgent|"_$Piece($List(retried, 1), "|", 2)_"|"_ref2, "the retry request names the first runner and carries the item")
	Do $ClassMethod(..#MOCK, "LogSince", mark, .entries)
	Set logged = $ClassMethod(fixture, "FindRequests", entries, ref2)
	Do $$$AssertEquals(logged.%Size(), 2, "the mock saw two model requests for the turn")
	// the first attempt completed (a refusal is an answer), so it saved its exchange into S1, and the retry's seed is cut before it (DW-726)
	Set stored = ##class(OcuTalon.Bridge.Compaction).Seed(##class(OcuTalon.Bridge.RequestSize).StoredMessages(s1))
	Do $$$AssertTrue((stored [ "ORION-7") && (stored [ refusal), "S1 holds the first turn and the refused exchange: "_$Translate($Extract(stored, 1, 300), $Char(10), "~"))
	If logged.%Size() = 2 {
		Set firstMessages = $ClassMethod(fixture, "Messages", logged.%Get(0))
		Do $$$AssertTrue(($Extract(firstMessages, 1, $Length("user:"_one.Input)) = ("user:"_one.Input)) && ($Extract(firstMessages, $Length(firstMessages) - $Length("user:"_two.Input) + 1, $Length(firstMessages)) = ("user:"_two.Input)), "the first carried the conversation of S1 and the input: "_firstMessages)
		Do $$$AssertEquals($ClassMethod(fixture, "Messages", logged.%Get(1)), "user:"_seed_$Char(10, 10)_two.Input, "and the retry's one user message is the seed of the stored first exchange, a blank line and the input: a new session: "_$ClassMethod(fixture, "Messages", logged.%Get(1)))
		Do $$$AssertTrue($ClassMethod(fixture, "Messages", logged.%Get(1)) '[ refusal, "with no refused text in it")
		Do $$$AssertEquals($Length($ClassMethod(fixture, "Messages", logged.%Get(1)), ref2) - 1, 1, "and the input once")
		Do $$$AssertEquals(logged.%Get(0).model_"|"_logged.%Get(1).model, "claude-haiku-5-5|"_..#SECOND, "on the first model and then the second")
	}
	Set s2 = ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, "ChatAgent")
	Do $$$AssertTrue((s2 '= "") && (s2 '= s1), "the link names the retry's session S2: "_s2)
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, "ChatAgentRetry"), "", "and no link names ChatAgentRetry")

	Set three = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] And what else?", .ref3, owner)
	Set answerText = $Select($IsObject(answer): answer.Text, 1: "")
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref3)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", three, .next, .session3), "the third turn is answered")
	Do $ClassMethod(..#MOCK, "LogSince", mark, .entries)
	Set logged = $ClassMethod(fixture, "FindRequests", entries, ref3)
	Do $$$AssertEquals(logged.%Size(), 1, "with one model request")
	If logged.%Size() = 1 {
		Do $$$AssertEquals($ClassMethod(fixture, "Messages", logged.%Get(0)), "user:"_seed_$Char(10, 10)_two.Input_$Char(1)_"assistant:"_answerText_$Char(1)_"user:"_three.Input, "which carries the seed, the retried exchange and its own input: "_$ClassMethod(fixture, "Messages", logged.%Get(0)))
		Do $$$AssertTrue($ClassMethod(fixture, "Messages", logged.%Get(0)) '[ refusal, "and no refused text")
	}
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, "ChatAgent"), s2, "and the link still names S2")

	// a turn whose timer fires is not retried
	Do ..UseTimer(12)
	Do ..Arm("retry-chat-held", 1)
	Set four = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:retry-chat-held]] Take your time.", .ref4, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref4)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set started = $ZHorolog
	Set sc = $ClassMethod(fixture, "Run", four, .held, .session4)
	Set elapsed = $ZHorolog - started
	Set ..Late = ..Late _ $ListBuild($ListBuild(session4, "ChatAgent"))
	Do $$$AssertStatusOK(sc, "the held turn is answered")
	Do $$$AssertTrue((elapsed '< 11) && (elapsed < 20), "when the timer fires: "_$Number(elapsed, 1)_" s")
	Set row = $ClassMethod(fixture, "DecisionOf", ref4, "turn")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", held, row, "turn", "timeout"), "", "a timeout fallback with every guarantee, as in release 1")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", $ClassMethod(fixture, "Headers", session4, "Decide"), "ChatAgent")_"|"_$ClassMethod(fixture, "CountTo", $ClassMethod(fixture, "Headers", session4, "Decide"), "ChatAgentRetry"), "1|0", "after one request, none to the retry runner: it is unknown whether a tool ran (R2)")
	// U-282: the mock received exactly one request for the turn's marker, so no second request was sent to any model
	Do $ClassMethod(..#MOCK, "LogSince", mark, .entries)
	Set logged = $ClassMethod(fixture, "FindRequests", entries, ref4)
	Do $$$AssertEquals(logged.%Size(), 1, "the mock received exactly one model request for the timed-out turn")
	If logged.%Size() = 1 Do $$$AssertEquals(logged.%Get(0).model, "claude-haiku-5-5", "on the first model, none on the second")
	Do $$$AssertTrue(..WaitLate(session4, "ChatAgent"), "the late first attempt is answered")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, "ChatAgent"), s2, "and the link still names S2, where the late attempt saved its exchange")
}

/// DW-730 (AD-6, AD-8), live: with no second model, a fresh turn whose first attempt is held past the timer (retry-chat-held, T 12) takes the timeout fallback; the
/// late attempt then saves its session, which nothing names. The link still names the session S1 that the user saw, and the owner's next turn is answered from S1
/// with its history alone, without the late exchange.
Method TestLateFreshTurnMovesNothing()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set one = $ClassMethod(fixture, "NewRequest", "turn", "user", "My build server is called ORION-7.", .ref1, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref1)
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", one, .told, .session1), "the first turn is answered")
	Set s1 = ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, "ChatAgent")
	Do $$$AssertTrue(s1 '= "", "the link names the session S1: "_s1)

	Do ..UseTimer(12)
	Do ..Arm("retry-chat-held", 1)
	Set fresh = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:retry-chat-held]] A fresh start.", .ref2, owner)
	Set fresh.SessionMode = "fresh"
	Set fresh.SeedText = "Earlier, the user said that the build server is called ORION-7."
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref2)
	Set sessions = $ClassMethod(fixture, "SessionMark")
	Set started = $ZHorolog
	Set sc = $ClassMethod(fixture, "Run", fresh, .held, .session2)
	Set elapsed = $ZHorolog - started
	Set ..Late = ..Late _ $ListBuild($ListBuild(session2, "ChatAgent"))
	Do $$$AssertStatusOK(sc, "the held turn is answered")
	Do $$$AssertTrue((elapsed '< 11) && (elapsed < 20), "when the timer fires: "_$Number(elapsed, 1)_" s")
	Set row = $ClassMethod(fixture, "DecisionOf", ref2, "turn")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", held, row, "turn", "timeout"), "", "a timeout fallback with every guarantee")
	Do $$$AssertEquals($Select($IsObject(held): held.SessionRotated, 1: "none"), 0, "that rotated nothing")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", $ClassMethod(fixture, "Headers", session2, "Decide"), "ChatAgentRetry"), 0, "and no request went to a retry runner")
	Do $$$AssertTrue(..WaitLate(session2, "ChatAgent"), "the late attempt is answered")
	Do $$$AssertEquals($ClassMethod(fixture, "SessionMark") - sessions, 1, "it saved its session")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, "ChatAgent"), s1, "and the link still names S1")

	Do ..UseTimer(60)
	Set three = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] And what else?", .ref3, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref3)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", three, .next, .session3), "the next turn is answered")
	Do $ClassMethod(..#MOCK, "LogSince", mark, .entries)
	Set logged = $ClassMethod(fixture, "FindRequests", entries, ref3)
	Do $$$AssertEquals(logged.%Size(), 1, "with one model request")
	If logged.%Size() = 1 {
		Set messages = $ClassMethod(fixture, "Messages", logged.%Get(0))
		Do $$$AssertTrue(($Extract(messages, 1, $Length("user:"_one.Input)) = ("user:"_one.Input)) && ($Extract(messages, $Length(messages) - $Length("user:"_three.Input) + 1, $Length(messages)) = ("user:"_three.Input)), "whose history is S1's, the first turn before the input: "_messages)
		Do $$$AssertTrue(messages [ ("assistant:"_told.Text), "with the reply of the first turn")
		Do $$$AssertTrue((messages '[ ref2) && (messages '[ "A fresh start.") && (messages '[ fresh.SeedText), "and nothing of the late fresh turn or its seed")
	}
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, "ChatAgent"), s1, "and the link still names S1")
}

/// DW-650 (c): a retryOf in the body of POST /v1/messages is dropped by the handler, and a request with a RetryOf that is sent to Decide waits for the conversation lock.
/// With another process holding the lock of (session, ChatAgent), the message through the real handler and a request straight to Decide with RetryOf ChatAgent are both
/// held: no request reaches ChatAgent while the lock is held (the straight request is answered Busy), and when it is let go the message is answered, with a request to
/// ChatAgent whose RetryOf is empty.
Method TestRetryOfFromTheWebIsIgnored()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set session = ..SessionOfUser()
	Set holder = "OcuTalon.Test.Bridge.Decide"
	Do $$$AssertTrue($ClassMethod(holder, "StartHolder", session, "ChatAgent"), "another process holds the conversation lock of (session, ChatAgent)")
	Set mark = $ClassMethod(fixture, "HeaderMark")

	// a request straight to Decide with a RetryOf
	Set direct = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] Straight to Decide.", .ref, session)
	Set direct.RetryOf = "ChatAgent"
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set sc = $ClassMethod(fixture, "Send", "Decide", direct, .busy)
	Do $$$AssertStatusOK(sc, "Decide answers the request that carries a RetryOf")
	Do $$$AssertEquals($Select($IsObject(busy): busy.%ClassName(1)_"|"_busy.Busy_"|"_busy.Fallback, 1: "none"), "OcuTalon.Bridge.Msg.Reply|1|0", "with Busy: the RetryOf skipped nothing")
	Do $$$AssertEquals(..RowCount(ref, "turn"), 0, "and recorded no row")

	// the message through the real handler
	Set csp = ##class(%CSP.Session).%New("ZzSecondModelWeb", 0)
	Set csp.Data("OcuTalon.SessionRef") = session
	Set clientId = "zzsecond"_..Number
	Set json = "{""clientId"":"""_clientId_""",""text"":""[[mock:recall-tell]] Through the web."",""retryOf"":""ChatAgent"",""RetryOf"":""ChatAgent"",""fromGuide"":false}"
	Set body = ..PostMessage(csp, json, .response)
	Do $$$AssertEquals(response.Status, "202 Accepted", "the handler accepts the message: "_body)
	Set started = $ZHorolog
	Hang 8
	Do $$$AssertEquals($ListLength(..ChatRequestsOf(mark, session)), 0, "no request reaches ChatAgent while the lock is held: the turn waits")
	Do $$$AssertTrue($ClassMethod(holder, "StopHolder", session), "the lock is let go")
	Set row = ..WaitDone(session, clientId)
	Do $$$AssertTrue($IsObject(row) && (row.State = "done"), "the message is answered once the lock is free: "_$Select($IsObject(row): row.State_"|"_row.FallbackReason_"|"_row.ItemId, 1: "no turn")_" after "_$Number($ZHorolog - started, 1)_" s")
	If $IsObject(row) Do $$$AssertEquals(row.FallbackReason, "", "with no fallback")
	Set retries = ..ChatRequestsOf(mark, session)
	Do $$$AssertTrue($ListLength(retries) '< 1, "a request reached ChatAgent: "_..ChatOwners(mark))
	Do $$$AssertEquals($ListToString(retries, ""), "", "and its RetryOf is empty")
	If $IsObject(row) Set ..ItemIds = ..ItemIds _ $ListBuild(row.ItemId)

	// QA: with the lock free, a request straight to Decide that carries a RetryOf is sent without it, whatever the client put there (SentRequest), and ChatAgent
	// answers it as a first attempt
	Set again = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] Straight to Decide, lock free.", .refAgain, session)
	Set again.RetryOf = "ChatAgent"
	Set ..ItemIds = ..ItemIds _ $ListBuild(refAgain)
	Set markAgain = $ClassMethod(fixture, "HeaderMark")
	Set sc = $ClassMethod(fixture, "Send", "Decide", again, .answered)
	Do $$$AssertStatusOK(sc, "Decide answers the request that carries a RetryOf once the lock is free")
	Do $$$AssertEquals($Select($IsObject(answered): answered.%ClassName(1)_"|"_answered.Busy_"|"_answered.Fallback_"|"_(answered.Text '= ""), 1: "none"), "OcuTalon.Bridge.Msg.Reply|0|0|1", "with the answer of ChatAgent: not Busy, no fallback, a text")
	Set sentAgain = ..ChatRequestsOf(markAgain, session)
	Do $$$AssertEquals($ListLength(sentAgain)_"|"_$ListToString(sentAgain, ""), "1|", "one request reached ChatAgent, and its RetryOf is empty")
}

/// Rule 1: a message through WebChatIn to the real Conversation and Decide, with a second model on ChatAgent. The first attempt is refused (retry-chat, armed at 1), so the
/// Turn is done with the second model's reply and no fallback; the next message of the session is answered with that exchange in its history.
Method TestIntegrationWebChat()
{
	If '..Prepare() Quit
	Do ..UseSecondModel("Chat")
	Set session = ..Session("chat")
	// the triage request of the message carries the marker too, and takes the first reply: the countdown covers it and the first attempt of the turn
	Do ..Arm("retry-chat", 2)
	Set clientId = "zzsecond"_..Number_"a"
	Do $$$AssertStatusOK(..Send(session, clientId, "[[mock:retry-chat]] What is my build server called? zz17first", .output), "the message is accepted by WebChatIn")
	Set row = ..WaitDone(session, clientId)
	If '$IsObject(row) || (row.State '= "done") {
		Do $$$AssertTrue(0, "the Turn is done within "_..#WAIT_" seconds")
		Quit
	}
	Set ..ItemIds = ..ItemIds _ $ListBuild(row.ItemId)
	Do $$$AssertEquals(row.State_"|"_row.FallbackReason, "done|", "the Turn is done and no fallback")
	Do $$$AssertEquals(row.ReplyText, ..#SECONDTEXT, "with the second model's reply")
	Set decision = ..DecisionByRef(row.TurnDecisionRef)
	Do $$$AssertEquals($Select($IsObject(decision): decision.Fallback_"|"_decision.Model_"|"_decision.Kind, 1: "no row"), "0|"_..#SECOND_"|turn", "the decision of the Turn is the second model's: "_row.TurnDecisionRef_" "_$Select($IsObject(decision): decision.Fallback_"|"_decision.Model_"|"_decision.Kind, 1: "no row"))
	If $IsObject(decision) Set ..ItemIds = ..ItemIds _ $ListBuild(decision.ItemId)

	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set clientId = "zzsecond"_..Number_"b"
	Do $$$AssertStatusOK(..Send(session, clientId, "[[mock:recall-tell]] And what else? zz17next", .output), "the next message is accepted")
	Set next = ..WaitDone(session, clientId)
	If '$IsObject(next) || (next.State '= "done") {
		Do $$$AssertTrue(0, "the next Turn is done within "_..#WAIT_" seconds")
		Quit
	}
	Set ..ItemIds = ..ItemIds _ $ListBuild(next.ItemId)
	Do $$$AssertEquals(next.State_"|"_next.FallbackReason, "done|", "the next Turn is done and no fallback")
	Do $ClassMethod(..#MOCK, "LogSince", mark, .entries)
	Set logged = $ClassMethod(..#FIXTURE, "FindRequests", entries, "zz17next")
	Set held = 0
	Set refused = 0
	Set repeated = 0
	Set iterator = logged.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set messages = $ClassMethod(..#FIXTURE, "Messages", entry)
		If (messages [ "zz17first") && (messages [ ("assistant:"_..#SECONDTEXT)) && (messages [ "zz17next") Set held = held + 1
		If messages [ "The CI mock refuses this request." Set refused = refused + 1
		If $Length(messages, "zz17first") > 2 Set repeated = repeated + 1
	}
	Do $$$AssertEquals(held, 1, "one model request of the next turn holds the first message, the second model's reply and the new message in its history ("_logged.%Size()_" requests carry the new message)")
	Do $$$AssertEquals(refused_"|"_repeated, "0|0", "none holds the refused exchange, and none holds the first message twice (DW-726)")
}

/// --- helpers ---
/// A fixture session for the user of the test run, the one that the REST handler resolves (as Test.Web.Api does); its Ref and TraceRef are kept for the clean-up.
Method SessionOfUser() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Do ..Supers.%Push(##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef)
	Quit ref
}

/// The runner items of the production, the three first runners and their retry runners, comma-separated.
ClassMethod Runners() As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).#RUNNERS_","_##class(OcuTalon.Test.Agent.RunnerFixture).#RETRYRUNNERS
}

/// 1 when the production runs with every item in the CI override's environment and the entries of the six runners are pointed at the mock key variable.
Method Prepare() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	Set reason = $ClassMethod(..#FIXTURE, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	If '..Pointed {
		Set ..Pointed = 1
		Set sc = $ClassMethod(..#FIXTURE, "PointKeys", ..Runners())
		Do $$$AssertStatusOK(sc, "the entries of the six runners are pointed at the CI mock key variable")
		If $$$ISERR(sc) Quit 0
	}
	Quit 1
}

/// Names the second model of the agent (Triage, Diagnosis or Chat): the RetryItem row of its first runner and the Model row of its retry runner, which is
/// started again so that its agent is built with the model. OnAfterOneTest puts the rows back and starts the retry runner again.
Method UseSecondModel(agent As %String) [ Private ]
{
	Set item = agent_"Agent"
	Set retry = item_"Retry"
	Do ..Put(item, "RetryItem", retry)
	Do ..Put(retry, "Model", ..#SECOND)
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Restart", ..#PRODUCTION_"||"_retry), retry_" is started again with the second model")
	Set ..Restarts = ..Restarts _ $ListBuild(retry)
}

/// Puts the System Default Settings row of the setting of the item (RunnerFixture PutDefault) and remembers the row that was there, once, for OnAfterOneTest.
Method Put(item As %String, setting As %String, value As %String) [ Private ]
{
	Set saved = ..SavedRows
	Do $ClassMethod(..#FIXTURE, "RememberDefault", .saved, item, setting)
	Set ..SavedRows = saved
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "PutDefault", item, setting, value), "the setting "_setting_" of "_item_" is '"_value_"'")
}

/// Decide's timer is the seconds (the TimerSeconds row, Decide started again), as Test.Agent.Decide.TestTimer does; the entries keep the block of 60.
Method UseTimer(seconds As %Integer) [ Private ]
{
	Do ..Put("Decide", "TimerSeconds", seconds)
	Do ..UseDecideRestart()
}

/// Starts Decide again, so that it takes the rows it was given, and again after the test.
Method UseDecideRestart() [ Private ]
{
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Restart", ..#PRODUCTION_"||Decide"), "Decide is started again")
	If '$ListFind(..Restarts, "Decide") Set ..Restarts = ..Restarts _ $ListBuild("Decide")
}

/// Arms the countdown of the mock for the marker with the number of requests that get its first reply, and remembers the marker for OnAfterOneTest.
Method Arm(marker As %String, remaining As %Integer) [ Private ]
{
	Set ..Armed = ..Armed _ $ListBuild(marker)
	Do $$$AssertStatusOK($ClassMethod(..#MOCK, "Arm", marker, remaining), "the countdown of "_marker_" is armed with "_remaining)
}

/// An untrusted request of the kind with the text, whose ItemId is cleaned up after the test.
Method Ask(kind As %String, text As %String, Output ref As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", kind, "untrusted", text, .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Quit request
}

/// Waits until the runner has answered every request that Decide sent it in the session (RunnerFixture WaitForAnswer). 1 when it has.
ClassMethod WaitLate(session As %Integer, runner As %String) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).WaitForAnswer(session, runner)
}

/// The Decision row with the Ref, or "".
ClassMethod DecisionByRef(ref As %String) As OcuTalon.Bridge.Data.Decision [ Private ]
{
	If ref = "" Quit ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Bridge_Data.Decision WHERE Ref = ?", ref)
	If 'result.%Next() Quit ""
	Quit ##class(OcuTalon.Bridge.Data.Decision).%OpenId(result.%GetData(1))
}

/// The number of Decision rows of the item and kind.
ClassMethod RowCount(itemId As %String, kind As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ? AND Kind = ?", itemId, kind)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The number of requests that Decide sent the runner in the session.
ClassMethod SentTo(session As %Integer, runner As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Agent.RunnerFixture).CountTo(##class(OcuTalon.Test.Agent.RunnerFixture).Headers(session, "Decide"), runner)
}

/// The requests that Decide sent the target in the session, as a list of "<RetryOf>|<DecisionRef>|<ItemId>".
ClassMethod RequestsTo(session As %Integer, target As %String) As %List [ Private ]
{
	Set found = ""
	Set headers = ##class(OcuTalon.Test.Agent.RunnerFixture).Headers(session, "Decide")
	Set iterator = headers.%GetIterator()
	While iterator.%GetNext(, .header) {
		If header.target '= target Continue
		Set body = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(header.bodyId)
		If $IsObject(body) Set found = found _ $ListBuild(body.RetryOf_"|"_body.DecisionRef_"|"_body.ItemId)
	}
	Quit found
}

/// Asserts that a decide request was answered by the second model: a usable DecisionResponse with the reason of the retry scenarios, one row of the DecisionRef with
/// the Model of the second model, one request to each runner with the retry's RetryOf and the DecisionRef of the first, and only the targets of a decision: no tool,
/// fix or approval. With a log mark (the mark before the send; the first attempt's reply has come by then) the row holds the sums of the Usage rows of the
/// DecisionRef, and the mock's log shows the first attempt on the first model and the retry on the second with the cap in its family's key and no sampling parameter
/// (the mock refuses them). A case whose first attempt is still running when the retry answers passes no mark: its late Usage row and request come after the row.
Method AssertAnswered(label As %String, request As OcuTalon.Bridge.Msg.Request, response As %Persistent, session As %Integer, mark As %Integer = "") [ Private ]
{
	Set fixture = ..#FIXTURE
	If '$IsObject(response) || 'response.%IsA("OcuTalon.Bridge.Msg.DecisionResponse") {
		Do $$$AssertTrue(0, label_"the answer is a DecisionResponse")
		Quit
	}
	Do $$$AssertEquals(response.Fallback_"|"_response.FallbackReason_"|"_response.Outcome_"|"_response.Reasons, "0||digest|"_..#SECONDREASON, label_"the answer is the second model's decision, no fallback")
	Set row = $ClassMethod(fixture, "DecisionOf", request.ItemId, "decide")
	Do $$$AssertTrue($IsObject(row), label_"a row is recorded")
	If '$IsObject(row) Quit
	Do $$$AssertEquals(..RowCount(request.ItemId, "decide"), 1, label_"exactly one row")
	Do $$$AssertEquals(row.Ref_"|"_row.Model_"|"_row.Fallback, response.DecisionRef_"|"_..#SECOND_"|0", label_"under the DecisionRef of the answer, with the second model")
	Do $$$AssertEquals($ClassMethod(fixture, "Totals", response), $ClassMethod(fixture, "Totals", row), label_"and the answer carries the totals of the row")
	Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", headers, "TriageAgent")_"|"_$ClassMethod(fixture, "CountTo", headers, "TriageAgentRetry"), "1|1", label_"one request went to each runner")
	Do $$$AssertEquals($ClassMethod(fixture, "Targets", headers), $Select($ClassMethod(fixture, "CountTo", headers, "AgentSteps"): "AgentSteps,", 1: "")_"ApprovalStartIn,Ens.Alarm,TriageAgent,TriageAgentRetry", label_"and Decide sent only the runner requests, the timer and the steps: no tool, fix or approval")
	Set first = ..RequestsTo(session, "TriageAgent")
	Set second = ..RequestsTo(session, "TriageAgentRetry")
	Do $$$AssertEquals($ListLength(first)_"|"_$ListLength(second), "1|1", label_"read from the messages")
	If ($ListLength(first) = 1) && ($ListLength(second) = 1) {
		Do $$$AssertEquals($List(first, 1), "|"_row.Ref_"|"_request.ItemId, label_"the first request has no RetryOf")
		Do $$$AssertEquals($List(second, 1), "TriageAgent|"_row.Ref_"|"_request.ItemId, label_"the retry names the first runner, with the same DecisionRef and ItemId")
	}
	If mark = "" Quit
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT SUM(InputTokens), SUM(OutputTokens), SUM(RequestCount), COUNT(*), SUM(CostUSD) FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ?", row.Ref)
	Do result.%Next()
	Do $$$AssertTrue(result.%GetData(4) '< 1, label_"the runners wrote Usage rows under the DecisionRef: "_result.%GetData(4))
	Do $$$AssertEquals(row.InputTokens_"|"_row.OutputTokens_"|"_row.AgentStepCount, result.%GetData(1)_"|"_result.%GetData(2)_"|"_result.%GetData(3), label_"and the row holds the sums of their tokens and requests")
	Do $$$AssertEquals(row.CostUSD, $Number(result.%GetData(5), 6), label_"and the sum of their cost")
	Do $ClassMethod(..#MOCK, "LogSince", mark, .entries)
	Set logged = $ClassMethod(fixture, "FindRequests", entries, request.ItemId)
	Set models = ""
	Set cap = 1
	Set sampling = 0
	Set iterator = logged.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set models = models _ $ListBuild(entry.model)
		If (entry.model = ..#SECOND) && (entry.maxTokens '= 8000) Set cap = 0
		If entry.request.%IsDefined("temperature") || entry.request.%IsDefined("top_p") || entry.request.%IsDefined("top_k") Set sampling = 1
	}
	Do $$$AssertTrue($ListFind(models, ..#SECOND) && $ListFind(models, "claude-haiku-5-5"), label_"the mock saw the first attempt on the first model and the retry on the second: "_$ListToString(models, ","))
	Do $$$AssertEquals(cap_"|"_sampling, "1|0", label_"the retry carries the cap of 8000 in max_tokens, and no request sets a sampling parameter")
}

/// Asserts that a decide request fell back with the reason, as release 1 records it: a tellnow DecisionResponse with every guarantee of a fallback (RunnerFixture
/// FallbackProblems), one row, and, with retried 1, one request to each runner (the retry was sent once, never twice) and only the targets of a decision; with retried 0,
/// no request to the retry runner.
Method AssertFellBack(label As %String, request As OcuTalon.Bridge.Msg.Request, response As %Persistent, session As %Integer, reason As %String, retried As %Boolean) [ Private ]
{
	Set fixture = ..#FIXTURE
	Set row = $ClassMethod(fixture, "DecisionOf", request.ItemId, "decide")
	Do $$$AssertTrue($IsObject(row), label_"a row is recorded")
	If '$IsObject(row) Quit
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", response, row, "decide", reason), "", label_"a tellnow fallback with the reason "_reason_" and every guarantee, in the answer, its XML and the row")
	Do $$$AssertEquals(..RowCount(request.ItemId, "decide"), 1, label_"exactly one row")
	Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", headers, "TriageAgentRetry"), +retried, label_$Select(retried: "the retry was sent once", 1: "no request went to the retry runner"))
	Set targets = $ClassMethod(fixture, "Targets", headers)
	For forbidden = "FixExecutor", "OcuTalonApprovals", "ApprovalHold", "Notify", "WebChatOut" {
		Do $$$AssertEquals($ListFind($ListFromString(targets), forbidden), 0, label_"nothing was sent to "_forbidden)
	}
}

/// The OwnerRefs of the requests that Decide sent ChatAgent since the header mark, comma-separated (for a failure message).
ClassMethod ChatOwners(mark As %Integer) As %String [ Private ]
{
	Set owners = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND TargetConfigName = 'ChatAgent' AND MessageBodyClassName = 'OcuTalon.Bridge.Msg.Request' ORDER BY ID", mark)
	While result.%Next() {
		Set body = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(result.%GetData(1))
		If $IsObject(body) Set owners = owners _ $Select(owners = "": "", 1: ",") _ body.OwnerRef_"/"_body.Kind
	}
	Quit owners
}

/// The RetryOf values of the requests (one for each) that Decide sent ChatAgent for the owner since the header mark, as a list.
ClassMethod ChatRequestsOf(mark As %Integer, owner As %String) As %List [ Private ]
{
	Set found = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND SourceConfigName = 'Decide' AND TargetConfigName = 'ChatAgent' AND MessageBodyClassName = 'OcuTalon.Bridge.Msg.Request' ORDER BY ID", mark)
	While result.%Next() {
		Set body = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(result.%GetData(1))
		If $IsObject(body) && (body.OwnerRef = owner) Set found = found _ $ListBuild(body.RetryOf)
	}
	Quit found
}

/// Calls Messages of the real handler (OcuTalon.Web.Api) with a stand-in request whose body is json and the given CSP session, and returns the body that it wrote.
Method PostMessage(session As %CSP.Session, json As %String, Output response) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", json)
	Set %response = ##class(%CSP.Response).%New()
	Set %session = session
	Set %response.ContentType = ""
	Set body = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Api", "Messages")
	Set response = %response
	Do $$$AssertStatusOK(sc, "Messages returns OK")
	Quit body
}

}
