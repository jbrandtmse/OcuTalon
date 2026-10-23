/// Tests of the request-size precheck and the compaction flag, through the running production and the CI mock (Story 1.9; AD-6, AD-8, AD-19, AD-20, NFR-3).
/// THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs OcuTalon.Production running after the Production step, the CI override's environment
/// (the mock's base URL and OCUTALON_MOCK_KEY_HEADER=1) and the mock's request log, and fails with the reason where it does not have them. Each request goes
/// through ApprovalStartIn to Decide, as a caller of Decide will send it (Test.Agent.RunnerFixture.Run). CI starts with no model key on purpose, so the first
/// test points the Config Store entry of each runner at the non-secret CI variable OCUTALON_MOCK_KEY_HEADER, and OnAfterAllTests puts the entries back. Every
/// user turn has an owner of its own (a new Ref) unless the test is about one conversation. Test.Bridge.Decide pins the rows that need no production.
///   - TestTooLarge: turn 1 of owner A, with 8,000 characters of input, is answered. Decide's RequestTokenLimit row is then put between the estimate of A's
///     turn 2 without its history (the same input for a new owner B) and with it, and Decide is started again. A's turn 2 is answered with a too_large
///     fallback Reply (every guarantee of a fallback holds) and a Decision row with too_large; Decide sent no request to ChatAgent, nothing reached the mock,
///     no Usage row was written, and the link and the saved session's data are as they were; B's turn, of the same size without the history, is answered;
///   - TestCompactFlag: a user turn with about 170,000 characters of input (an estimate between 40,000 and 100,000 tokens) is sent to ChatAgent with Compact 1,
///     a short user turn with Compact 0; the long turn is sent as it is, answered with the chat script's text, and the mock logged one request that carries the
///     whole input; the Usage row of the long turn records a largest request above 40,000 tokens and under 100,000.
/// OnAfterOneTest puts back what a test changed, also when it failed: the Decision, Usage and AgentStep rows of its items, the System Default Settings row it wrote
/// (Decide's RequestTokenLimit) with the item it restarted, and the AI sessions it saved with the links that name them.
Class OcuTalon.Test.Agent.RequestSize Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

/// The runner item of the conversations, which is the agent of their links.
Parameter RUNNER = "ChatAgent";

/// The text of recall-ask.json, and of recall-tell.json.
Parameter ASKTEXT = "Your build server is called ORION-7.";

Parameter TELLTEXT = "Noted.";

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

/// The System Default Settings rows before the test touched them (RunnerFixture.RememberDefault), to be put back.
Property SavedRows As %List;

/// 1 when the test wrote Decide's row and started Decide again.
Property DecideChanged As %Boolean [ InitialExpression = 0 ];

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).DeleteSteps(itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	Set running = ##class(OcuTalon.Test.Agent.RunnerFixture).Running()
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..SavedRows)
	Set ..SavedRows = ""
	If ..DecideChanged && running {
		Set ..DecideChanged = 0
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).Restart(..#PRODUCTION_"||Decide")
	}
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
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

/// A request whose estimate is above the request-size limit is never sent (AC1, AC2). Owner A's turn 1 has 8,000 characters of input and is answered, so the
/// stored history of A's conversation is a few thousand tokens. The limit is then set one token below the estimate of A's turn 2, which counts that history, and
/// above the estimate of B's turn, the same input for an owner with no history (the sizes come from EstimateTokens at run time, so that no constant hides a
/// change of the agent's prompt). A's turn 2 gets a too_large fallback Reply, with every guarantee of a fallback in the answer, its XML and the Decision row;
/// Decide sent nothing to ChatAgent (its headers go to ApprovalStartIn only), and nothing reached the mock, read once ChatAgent has handled everything sent to
/// it; no Usage row exists for it; the link and the saved session's data are as they were. B's turn is answered with the text of the mock, and its Decision row
/// is not a fallback.
Method TestTooLarge()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set mock = ..#MOCK
	Set ownerA = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ownerB = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set filler = $Translate($Justify("", 8000), " ", "a")
	Set one = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] "_filler, .ref1, ownerA)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref1)
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", one, .first), "turn 1 of owner A is answered")
	Do $$$AssertEquals($Select($IsObject(first): first.Fallback_"|"_first.Text, 1: "none"), "0|"_..#TELLTEXT, "with the text of recall-tell, no fallback")
	Set id = ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(ownerA, ..#RUNNER)
	Do $$$AssertTrue(id '= "", "A's link names a saved session: "_id)
	Set export = $ClassMethod(fixture, "SessionExport", id)
	Do $$$AssertTrue(export [ ref1, "the saved session's data is read, and holds turn 1")

	Set twoA = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-ask]] What is my build server called?", .ref2, ownerA)
	Set twoB = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-ask]] What is my build server called?", .ref3, ownerB)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref2, ref3)
	Set with = ##class(OcuTalon.Bridge.Process.Decide).EstimateTokens(twoA, ..#RUNNER)
	Set without = ##class(OcuTalon.Bridge.Process.Decide).EstimateTokens(twoB, ..#RUNNER)
	Do $$$AssertTrue(with - without > 1500, "A's turn 2 counts the 8,000 characters of history: "_with_" tokens against "_without_" for B's turn")
	Set limit = with - 1
	Do $$$AssertTrue(limit '< without, "so the limit "_limit_" is between them")
	Do ..Put("Decide", "RequestTokenLimit", limit)
	Set ..DecideChanged = 1
	Do $$$AssertStatusOK($ClassMethod(fixture, "Restart", ..#PRODUCTION_"||Decide"), "Decide is started again with a RequestTokenLimit of "_limit)

	Set mark = $ClassMethod(mock, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", twoA, .answer, .session), "A's turn 2 is answered")
	Set row = $ClassMethod(fixture, "DecisionOf", ref2, "turn")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", answer, row, "turn", "too_large"), "", "a tellnow fallback Reply with the reason too_large, in the answer, its XML and the row")
	Do $$$AssertEquals($Select($IsObject(row): row.FallbackReason, 1: "none"), "too_large", "the Decision row has the reason too_large")
	Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
	Do $$$AssertEquals($ClassMethod(fixture, "Targets", headers), "ApprovalStartIn", "Decide sent no runner request and no timer, only its answer")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", headers, ..#RUNNER), 0, "so there is no header to ChatAgent")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Drain", ..#RUNNER), "ChatAgent answered a request of its own, so it had handled everything sent to it before")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Do $$$AssertEquals($ClassMethod(fixture, "FindRequests", entries, ref2).%Size(), 0, "nothing reached the mock")
	Do $$$AssertEquals($ClassMethod(fixture, "UsageIds", "ItemId", ref2).%Size(), 0, "and no Usage row was written")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(ownerA, ..#RUNNER), id, "A's link is as it was")
	Do $$$AssertEquals($ClassMethod(fixture, "SessionExport", id), export, "and so is the saved session's data")

	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", twoB, .answerB, .sessionB), "B's turn, with no history, is answered")
	Do $$$AssertEquals($Select($IsObject(answerB): answerB.Fallback_"|"_answerB.Text, 1: "none"), "0|"_..#ASKTEXT, "with the text of recall-ask and no fallback")
	Set rowB = $ClassMethod(fixture, "DecisionOf", ref3, "turn")
	Do $$$AssertEquals($Select($IsObject(rowB): rowB.Fallback_"|"_rowB.FallbackReason, 1: "none"), "0|", "whose Decision row records no fallback")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", $ClassMethod(fixture, "Headers", sessionB, "Decide"), ..#RUNNER), 1, "Decide sent ChatAgent one request for it")
}

/// A turn above 40,000 tokens and within the limit is flagged for compaction and sent as it is (AC3). A user turn with about 170,000 characters of input has an
/// estimate between 40,000 and 100,000 tokens; its request to ChatAgent (the message that Decide sent, read from its header) has Compact 1, and a short user turn's
/// has Compact 0. The long turn is answered with the text of the chat script, and the mock logged one request that carries the whole input, so the flag changed
/// nothing in what is sent. Its Usage row records a largest request above 40,000 tokens and under 100,000.
Method TestCompactFlag()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set mock = ..#MOCK
	Set filler = $Translate($Justify("", 170000), " ", "a")
	Set long = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] "_filler, .refLong)
	Set short = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] Say hello.", .refShort)
	Set ..ItemIds = ..ItemIds _ $ListBuild(refLong, refShort)
	Set estimate = ##class(OcuTalon.Bridge.Process.Decide).EstimateTokens(long, ..#RUNNER)
	Do $$$AssertTrue((estimate > 40000) && (estimate < 100000), "control: the long turn is estimated between 40,000 and 100,000 tokens: "_estimate)

	Set mark = $ClassMethod(mock, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", long, .answer, .session), "the long turn is answered")
	Do $$$AssertEquals($Select($IsObject(answer): answer.Fallback_"|"_answer.Text, 1: "none"), "0|"_..#TELLTEXT, "with the text of the chat script and no fallback")
	Do $$$AssertEquals(..SentCompact(session), 1, "the request that Decide sent to ChatAgent has Compact 1")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Set requests = $ClassMethod(fixture, "FindRequests", entries, refLong)
	Do $$$AssertEquals(requests.%Size(), 1, "the mock logged one request for it")
	If requests.%Size() = 1 Do $$$AssertEquals($ClassMethod(fixture, "Messages", requests.%Get(0)), "user:"_long.Input, "which carries the whole input, as it was written")
	Set ids = $ClassMethod(fixture, "UsageIds", "ItemId", refLong)
	Do $$$AssertEquals(ids.%Size(), 1, "one Usage row was written")
	If ids.%Size() = 1 {
		Set usage = ##class(OcuTalon.Bridge.Data.Usage).%OpenId(ids.%Get(0))
		Do $$$AssertTrue((usage.LargestRequestTokens > 40000) && (usage.LargestRequestTokens < 100000), "its largest request is above 40,000 tokens and under 100,000: "_usage.LargestRequestTokens)
	}

	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", short, .answerShort, .sessionShort), "the short turn is answered")
	Do $$$AssertEquals($Select($IsObject(answerShort): answerShort.Fallback_"|"_answerShort.Text, 1: "none"), "0|"_..#TELLTEXT, "with the same text")
	Do $$$AssertEquals(..SentCompact(sessionShort), 0, "the request that Decide sent to ChatAgent has Compact 0")
}

/// --- helpers ---
/// The Compact flag of the request that Decide sent to ChatAgent in the session: the message body of the header to ChatAgent, or "none" when there is none.
ClassMethod SentCompact(session As %Integer) As %String [ Private ]
{
	Set header = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderTo(##class(OcuTalon.Test.Agent.RunnerFixture).Headers(session, "Decide"), ..#RUNNER)
	If '$IsObject(header) Quit "none"
	Set sent = ##class(OcuTalon.Bridge.Msg.Request).%OpenId(header.bodyId)
	Quit $Select($IsObject(sent): sent.Compact, 1: "none")
}

/// 1 when the production runs with every item in the CI override's environment and the entries of the runners are pointed at the mock key variable. Otherwise the
/// test fails with the reason, and quits. The entries are put back by OnAfterAllTests. Today's day mark is removed first, so that no earlier class leaves the day
/// capped.
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

/// Writes the System Default Settings row of the setting of the item, remembering the row that was there once, for OnAfterOneTest (RememberDefault).
Method Put(item As %String, setting As %String, value As %String) [ Private ]
{
	Set saved = ..SavedRows
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RememberDefault(.saved, item, setting)
	Set ..SavedRows = saved
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).PutDefault(item, setting, value), "the setting "_setting_" of "_item_" is '"_value_"'")
}

}
