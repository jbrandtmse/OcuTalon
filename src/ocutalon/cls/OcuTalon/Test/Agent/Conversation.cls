/// Tests of the conversations that survive restarts, through the running production and the CI mock (Story 1.8; AD-3, AD-5, AD-6, AD-7, AD-8, AD-20,
/// AD-30). THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs OcuTalon.Production running after the Production step, the CI override's
/// environment (the mock's base URL and OCUTALON_MOCK_KEY_HEADER=1) and the mock's request log, and fails with the reason where it does not have them. Each
/// request goes through ApprovalStartIn to Decide, as a caller of Decide will send it (Test.Agent.RunnerFixture.Run), or straight to ChatAgent (Send). CI starts
/// with no model key on purpose, so the first test points the Config Store entry of each runner at the non-secret CI variable OCUTALON_MOCK_KEY_HEADER, and
/// OnAfterAllTests puts the entries back. Every user turn has an owner of its own (a new Ref) unless the test is about one conversation, which then uses one
/// OwnerRef for all its turns. Test.Bridge.Conversation pins the rows that need no production.
///   - TestRestart: with ChatAgent's Effort row at low, turn 1 (recall-tell) says "My build server is called ORION-7" and Install.Step.Production.Start
///     restarts the production; ChatAgent's jobs after share none with those before; turn 2 (recall-ask) is answered with the text of recall-ask, and its
///     first logged request carries turn 1's user text, the fact included, and its reply, in that order, before turn 2's input; both turns' requests have the
///     cap of 8,000 tokens and the effort low; ^AI.Agent.SessionD and ^OcuTalonBP.ConvLinkD resolve to the private database, whose folder is under the manager
///     directory and which holds the session's row and the link's row;
///   - TestBusyWhileHeld: while the test holds the conversation lock of (owner, ChatAgent), a user's turn is answered with a Busy Reply 2 to 5 seconds after the
///     send, with nothing else set, no Decision row, no request to ChatAgent and no step; an untrusted turn of the same owner is answered at once, not Busy,
///     with no history in its request; and, with the lock released, the same user turn sent again with the same ItemId is answered, with its row;
///   - TestBusyAfterTimedOutTurn: with Decide's TimerSeconds row at 12, a turn whose reply comes after 18 seconds (turn-late) is answered with a timeout
///     fallback; the next turn, sent as soon as that is answered, is Busy, because the late Chat still holds the conversation; once ChatAgent has answered
///     the late request, a third turn is answered and carries the late exchange (turn 1's input and the late reply), which the late Chat saved;
///   - TestRunnerBusy: with the lock held by the test, a linked turn sent straight to ChatAgent gets a Busy Reply after about 2 seconds, writes no Usage row and
///     sends nothing to the mock; sent again with the lock released, it is answered, with a Usage row;
///   - TestResendReopens: turn 2 with overloaded:<key> armed 1 is answered after Decide sent ChatAgent two requests, and the two logged requests have equal
///     messages: the history of turn 1, then turn 2's input once;
///   - TestSessionBroken: turn 2 with invalid-input is an error fallback with SessionBroken 1, and the link and the saved session's data stay as they were; an
///     untrusted turn with invalid-input is an error fallback with no SessionBroken; turn 3, with a new ItemId, SessionMode fresh and a SeedText, is answered
///     with SessionRotated 1, the link moved, and one user message in its request.
/// OnAfterOneTest puts back what a test changed, also when it failed: the conversation locks it held, the countdowns it armed, the Decision, Usage and AgentStep
/// rows of its items, the System Default Settings rows it wrote (ChatAgent's Effort, Decide's TimerSeconds) with the items it restarted, and the AI sessions
/// it saved with the links that name them.
Class OcuTalon.Test.Agent.Conversation Extends %UnitTest.TestCase
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

/// The text of turn-late.json.
Parameter LATETEXT = "The CI mock answers this turn late.";

/// The cap of the composed session config, in tokens.
Parameter CAP = 8000;

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

/// The conversation locks that the test holds, as a list of $ListBuild(owner, agent), one for each hold (Hold).
Property Held As %List;

/// The countdowns of the mock that the test armed, as a list of markers, to be cleared.
Property Armed As %List;

/// The System Default Settings rows before the test touched them (RunnerFixture.RememberDefault), to be put back.
Property SavedRows As %List;

/// 1 when the test wrote the TimerSeconds row and started Decide again.
Property DecideChanged As %Boolean [ InitialExpression = 0 ];

/// 1 when the test wrote the Effort row and started ChatAgent again.
Property ChatChanged As %Boolean [ InitialExpression = 0 ];

/// The session of a request whose late Chat the test waits for, or "".
Property LateSession As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set position = 0
	While $ListNext(..Held, position, hold) {
		Do ##class(OcuTalon.Bridge.Data.ConversationLink).Unlock($List(hold, 1), $List(hold, 2))
	}
	Set ..Held = ""
	Set position = 0
	While $ListNext(..Armed, position, marker) {
		Do ##class(OcuTalon.Test.Contract.Mock).Arm(marker, "")
	}
	Set ..Armed = ""
	If ..LateSession '= "" {
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).WaitForAnswer(..LateSession, ..#RUNNER)
		Set ..LateSession = ""
	}
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
	If ..ChatChanged && running {
		Set ..ChatChanged = 0
		Do ##class(OcuTalon.Test.Agent.RunnerFixture).Restart(..#PRODUCTION_"||"_..#RUNNER)
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

/// A user told OcuTalon a fact in one turn, and the production restarts before the next turn: no runner job keeps anything in memory, and the next turn's first
/// request still carries the earlier conversation, the cap of 8,000 tokens and the effort of the runner's setting, because the session is opened with the composed
/// config from the private database on the durable volume.
Method TestRestart()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set mock = ..#MOCK
	Do ..PutEffort("low")
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set tell = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] My build server is called ORION-7.", .ref1, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref1)
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = $ClassMethod(fixture, "Run", tell, .first, .session1)
	Do $$$AssertStatusOK(sc, "turn 1 is answered")
	Do $$$AssertEquals($Select($IsObject(first): first.Text_"|"_first.Fallback_"|"_first.SessionRotated, 1: "none"), ..#TELLTEXT_"|0|0", "with the text of recall-tell, no fallback and no rotation")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Set one = $ClassMethod(fixture, "FindRequests", entries, ref1)
	Do $$$AssertEquals(one.%Size(), 1, "turn 1 made one model request")
	If one.%Size() = 1 Do ..AssertConfig(one.%Get(0), "turn 1")
	Set id = ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, ..#RUNNER)
	Do $$$AssertTrue(id '= "", "the link of (owner, ChatAgent) names a saved session: "_id)
	Set before = $ClassMethod(fixture, "Jobs", ..#RUNNER)
	Do $$$AssertTrue($ListLength(before) > 0, "ChatAgent has jobs before the restart: "_$ListToString(before, ","))

	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).Start(), "Install.Step.Production.Start restarts the production and waits until every item runs again")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Production).NotRunning(), "", "every item runs")
	Set after = $ClassMethod(fixture, "Jobs", ..#RUNNER)
	Do $$$AssertTrue($ListLength(after) > 0, "ChatAgent has jobs after it: "_$ListToString(after, ","))
	Set shared = ""
	Set position = 0
	While $ListNext(after, position, job) {
		If $ListFind(before, job) Set shared = shared _ $ListBuild(job)
	}
	Do $$$AssertEquals($ListToString(shared, ","), "", "and none of them is a job from before: nothing is kept in memory")

	Set ask = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-ask]] What is my build server called?", .ref2, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref2)
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = $ClassMethod(fixture, "Run", ask, .second, .session2)
	Do $$$AssertStatusOK(sc, "turn 2 is answered after the restart")
	Do $$$AssertEquals($Select($IsObject(second): second.Text_"|"_second.Fallback_"|"_second.SessionRotated, 1: "none"), ..#ASKTEXT_"|0|0", "with the text of recall-ask")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read again")
	Set two = $ClassMethod(fixture, "FindRequests", entries, ref2)
	Do $$$AssertEquals(two.%Size(), 1, "turn 2 made one model request")
	If two.%Size() = 1 {
		Set sent = $ClassMethod(fixture, "Messages", two.%Get(0))
		Do $$$AssertEquals(sent, "user:"_tell.Input_$Char(1)_"assistant:"_..#TELLTEXT_$Char(1)_"user:"_ask.Input, "its first request carries turn 1's user text, the fact included, and its reply, in that order, before turn 2's input")
		Do $$$AssertTrue(sent [ "ORION-7", "the fact is in it")
		Do ..AssertConfig(two.%Get(0), "turn 2")
	}
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, ..#RUNNER), id, "the link still names the same session")

	// where the conversation is kept
	Set private = ..PrivateDirectory()
	Set manager = ##class(%File).NormalizeDirectory($SYSTEM.Util.ManagerDirectory())
	Do $$$AssertTrue((private '= "") && ($Extract(private, 1, $Length(manager)) = manager), "the folder of OCUTALON_PRIVATE, "_private_", is under the manager directory, "_manager)
	For global = "AI.Agent.SessionD", "OcuTalonBP.ConvLinkD" {
		Set dest = ##class(%SYS.Namespace).GetGlobalDest("OCUTALON", "^"_global)
		Do $$$AssertEquals($Piece(dest, "^", 1)_"|"_##class(%File).NormalizeDirectory($Piece(dest, "^", 2)), "|"_private, "^"_global_" resolves to OCUTALON_PRIVATE: "_dest)
	}
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Data.ConversationLink).OwnerRefAgentIndexExists(owner, ..#RUNNER, .linkId), "the link has a row")
	Set reference = "^|""^^"_private_"""|"
	Do $$$AssertTrue($Data(@(reference_"AI.Agent.SessionD("_id_")")), "the private database holds the session's row")
	Do $$$AssertTrue($Data(@(reference_"OcuTalonBP.ConvLinkD("_linkId_")")), "and the link's row")
}

/// While another turn holds the conversation (the test holds the lock of (owner, ChatAgent)), Decide refuses a user's turn after the lock's 2 seconds with a Busy
/// Reply: nothing else is set, there is no Decision row, no request to ChatAgent and no step, and it is not a fallback or an error. An untrusted turn of the same
/// owner is never refused this way. With the lock released, the same user turn sent again with the same ItemId is answered, with its row.
Method TestBusyWhileHeld()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set mock = ..#MOCK
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertTrue(..Hold(owner), "the test holds the conversation lock of (owner, ChatAgent)")
	Set turn = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] A turn while the conversation is held.", .ref, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(mock, "LogMark")
	Set logMark = $ClassMethod(fixture, "EventMark")
	Set started = $ZHorolog
	Set sc = $ClassMethod(fixture, "Run", turn, .busy, .session)
	Set elapsed = $ZHorolog - started
	Do $$$AssertStatusOK(sc, "Decide answers the held turn: busy is no error")
	Do $$$AssertEquals($ClassMethod(fixture, "WarningRows", logMark, "Decide"), 0, "Decide logged no warning for it")
	Do ..AssertBusy(busy, "the held turn's answer")
	Do $$$AssertTrue((elapsed '< 2) && (elapsed < 5), "it comes 2 to 5 s after the send: "_$Number(elapsed, 1)_" s")
	Do $$$AssertEquals($Select($IsObject($ClassMethod(fixture, "DecisionOf", ref, "turn")): 1, 1: 0), 0, "no Decision row is recorded")
	Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
	Do $$$AssertEquals($ClassMethod(fixture, "Targets", headers), "ApprovalStartIn", "Decide sent only its answer: no request to ChatAgent, no timer and no step")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Do $$$AssertEquals($ClassMethod(fixture, "FindRequests", entries, ref).%Size(), 0, "nothing reached the mock")

	Set untrusted = $ClassMethod(fixture, "NewRequest", "turn", "untrusted", "[[mock:recall-tell]] An untrusted turn of the same owner.", .refU, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(refU)
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = $ClassMethod(fixture, "Run", untrusted, .answer, .sessionU)
	Do $$$AssertStatusOK(sc, "the untrusted turn of the same owner is answered")
	Do $$$AssertEquals($Select($IsObject(answer): answer.Busy_"|"_answer.Fallback_"|"_answer.Text, 1: "none"), "0|0|"_..#TELLTEXT, "not as Busy, with the text of the mock")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read again")
	Set requests = $ClassMethod(fixture, "FindRequests", entries, refU)
	Do $$$AssertEquals(requests.%Size(), 1, "it made one model request")
	If requests.%Size() = 1 Do $$$AssertEquals($ClassMethod(fixture, "Messages", requests.%Get(0)), "user:"_untrusted.Input, "which carries its input alone: no history")

	Do ..Release(owner)
	Set again = turn.%ConstructClone()
	Set sc = $ClassMethod(fixture, "Run", again, .answered, .session2)
	Do $$$AssertStatusOK(sc, "the same user turn sent again with the same ItemId is answered")
	Do $$$AssertEquals($Select($IsObject(answered): answered.Busy_"|"_answered.Fallback_"|"_answered.Text, 1: "none"), "0|0|"_..#TELLTEXT, "with the text of the mock, not Busy")
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "turn")
	Do $$$AssertTrue($IsObject(row), "and a Decision row")
	If $IsObject(row) && $IsObject(answered) Do $$$AssertEquals(row.Ref, answered.DecisionRef, "whose Ref is the answer's DecisionRef")
}

/// A turn whose Chat outlives Decide's timer keeps the conversation (AD-6; Story 1.7's second question). With Decide's TimerSeconds row at 12, written
/// directly with Decide started again, turn 1 (turn-late: the reply comes after 18 s) gets a timeout fallback. Turn 2, sent as soon as turn 1 is answered, is
/// Busy, because the late Chat holds the lock until it has saved. After ChatAgent has answered the late request, turn 3 is answered, and its first request
/// carries turn 1's input and the late reply, which the late Chat saved.
Method TestBusyAfterTimedOutTurn()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set mock = ..#MOCK
	Do ..Put("Decide", "TimerSeconds", 12)
	Set ..DecideChanged = 1
	Do $$$AssertStatusOK($ClassMethod(fixture, "Restart", ..#PRODUCTION_"||Decide"), "Decide is started again with a TimerSeconds of 12")
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set late = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:turn-late]] Answer this turn late.", .ref1, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref1)
	Set started = $ZHorolog
	Set sc = $ClassMethod(fixture, "Run", late, .first, .session1)
	Set elapsed = $ZHorolog - started
	Set ..LateSession = session1
	Do $$$AssertStatusOK(sc, "turn 1 is answered: the timer is no error")
	Do $$$AssertTrue((elapsed '< 11) && (elapsed < 17), "11 to 17 s after the send, with the timer at 12 s and the reply at 18 s: "_$Number(elapsed, 1)_" s")
	Set row = $ClassMethod(fixture, "DecisionOf", ref1, "turn")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", first, row, "turn", "timeout"), "", "turn 1 is a timeout fallback, with every guarantee of a fallback")

	Set next = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] A turn while the late Chat runs.", .ref2, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref2)
	Set started = $ZHorolog
	Set sc = $ClassMethod(fixture, "Run", next, .busy, .session2)
	Set elapsed = $ZHorolog - started
	Do $$$AssertStatusOK(sc, "turn 2 is answered")
	Do ..AssertBusy(busy, "turn 2's answer")
	Do $$$AssertTrue((elapsed '< 2) && (elapsed < 6), "after the 2 s of the lock: "_$Number(elapsed, 1)_" s")
	Do $$$AssertEquals($Select($IsObject($ClassMethod(fixture, "DecisionOf", ref2, "turn")): 1, 1: 0), 0, "turn 2 has no Decision row")

	Do $$$AssertTrue($ClassMethod(fixture, "WaitForAnswer", session1, ..#RUNNER), "ChatAgent answers the late request, within the ceiling")
	Set ..LateSession = ""
	Set third = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-ask]] What did I ask earlier?", .ref3, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref3)
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = $ClassMethod(fixture, "Run", third, .answer, .session3)
	Do $$$AssertStatusOK(sc, "turn 3 is answered")
	Do $$$AssertEquals($Select($IsObject(answer): answer.Busy_"|"_answer.Fallback_"|"_answer.Text, 1: "none"), "0|0|"_..#ASKTEXT, "not Busy, with the text of recall-ask")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Set requests = $ClassMethod(fixture, "FindRequests", entries, ref3)
	Do $$$AssertEquals(requests.%Size(), 1, "turn 3 made one model request")
	If requests.%Size() = 1 Do $$$AssertEquals($ClassMethod(fixture, "Messages", requests.%Get(0)), "user:"_late.Input_$Char(1)_"assistant:"_..#LATETEXT_$Char(1)_"user:"_third.Input, "which carries turn 1's input and the late reply that the late Chat saved, before turn 3's input")
}

/// A linked turn sent straight to ChatAgent, with the conversation lock held by the test, gets a Busy Reply after about 2 seconds: the runner takes the lock with
/// the same wait, and refuses with NewBusy when it cannot. It writes no Usage row and sends nothing to the mock. Sent again with the lock released, it is answered
/// and writes its row.
Method TestRunnerBusy()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set mock = ..#MOCK
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertTrue(..Hold(owner), "the test holds the conversation lock of (owner, ChatAgent)")
	Set turn = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] A turn sent straight to the runner.", .ref, owner)
	Set turn.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(mock, "LogMark")
	Set logMark = $ClassMethod(fixture, "EventMark")
	Set started = $ZHorolog
	Set sc = $ClassMethod(fixture, "Send", ..#RUNNER, turn, .busy)
	Set elapsed = $ZHorolog - started
	Do $$$AssertStatusOK(sc, "the runner answers: busy is no error")
	Do $$$AssertEquals($ClassMethod(fixture, "WarningRows", logMark, ..#RUNNER), 0, "the runner logged no warning for it")
	Do ..AssertBusy(busy, "the runner's answer")
	Do $$$AssertTrue((elapsed '< 1.9) && (elapsed < 6), "after about 2 s: "_$Number(elapsed, 1)_" s")
	Do $$$AssertEquals($ClassMethod(fixture, "UsageIds", "ItemId", ref).%Size(), 0, "no Usage row is written")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Do $$$AssertEquals($ClassMethod(fixture, "FindRequests", entries, ref).%Size(), 0, "and nothing reached the mock")

	Do ..Release(owner)
	Set again = turn.%ConstructClone()
	Set sc = $ClassMethod(fixture, "Send", ..#RUNNER, again, .answered)
	Do $$$AssertStatusOK(sc, "sent again with the lock released, the turn is answered by the runner")
	Do $$$AssertEquals($Select($IsObject(answered): answered.Busy_"|"_answered.Text, 1: "none"), "0|"_..#TELLTEXT, "with the text of the mock, not Busy")
	Do $$$AssertEquals($ClassMethod(fixture, "UsageIds", "ItemId", ref).%Size(), 1, "and one Usage row")
}

/// A turn that Decide sends again after a rate limit reopens the same saved history (AD-8; Story 1.7's first question): the first attempt fails and saves
/// nothing, and the runner's job for the second opens the session from the database. Turn 2 carries overloaded:<key> with its countdown armed at 1: the mock
/// answers its first request 529 and its second 200. Decide sent ChatAgent two requests, and the two logged requests have the same messages: the history of
/// turn 1, then turn 2's input once.
Method TestResendReopens()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set mock = ..#MOCK
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set tell = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] My build server is called ORION-7.", .ref1, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref1)
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", tell, .first, .session1), "turn 1 is answered")
	Do $$$AssertEquals($Select($IsObject(first): first.Text, 1: "none"), ..#TELLTEXT, "with the text of recall-tell")

	Set marker = "overloaded:"_##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Arm(marker, 1)
	Set again = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:"_marker_"]] Say it again after the overload.", .ref2, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref2)
	Set mark = $ClassMethod(mock, "LogMark")
	Set sc = $ClassMethod(fixture, "Run", again, .second, .session2)
	Do $$$AssertStatusOK(sc, "turn 2 is answered")
	Do $$$AssertEquals($Select($IsObject(second): second.Fallback_"|"_second.Text, 1: "none"), "0|Answered after the overload.", "after the rate limit, with the text of the second reply of overloaded")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", $ClassMethod(fixture, "Headers", session2, "Decide"), ..#RUNNER), 2, "Decide sent ChatAgent two requests")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Set requests = $ClassMethod(fixture, "FindRequests", entries, ref2)
	Do $$$AssertEquals(requests.%Size(), 2, "the mock logged two requests for turn 2")
	If requests.%Size() = 2 {
		Do $$$AssertEquals(requests.%Get(0).status_"|"_requests.%Get(1).status, "529|200", "a 529, then a 200")
		Set expected = "user:"_tell.Input_$Char(1)_"assistant:"_..#TELLTEXT_$Char(1)_"user:"_again.Input
		Do $$$AssertEquals($ClassMethod(fixture, "Messages", requests.%Get(0)), expected, "the first attempt carried the history, then turn 2's input once")
		Do $$$AssertEquals($ClassMethod(fixture, "Messages", requests.%Get(1)), expected, "and the second the same messages: the history was reopened, not grown by the failed attempt")
		Do $$$AssertEquals(requests.%Get(1).request.messages.%ToJSON(), requests.%Get(0).request.messages.%ToJSON(), "the two requests have equal messages")
	}
}

/// A conversation history that the provider rejects ("Invalid input", the scenario invalid-input) on a user's turn is reported, never repaired (AD-8). Turn 2 is
/// an error fallback with SessionBroken 1, and the link and the saved session's data stay as they were. An untrusted turn with the same marker is an error
/// fallback with no SessionBroken. Turn 3, with a new ItemId, SessionMode fresh and a SeedText, is answered with SessionRotated 1: the link has moved, and its
/// request holds one user message.
Method TestSessionBroken()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set mock = ..#MOCK
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set tell = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] My build server is called ORION-7.", .ref1, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref1)
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", tell, .first, .session1), "turn 1 is answered")
	Set id = ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, ..#RUNNER)
	Set export = $ClassMethod(fixture, "SessionExport", id)
	Do $$$AssertTrue((id '= "") && (export [ ref1), "the link names a saved session that holds turn 1: "_id)

	Set broken = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:invalid-input]] Break the conversation.", .ref2, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref2)
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", broken, .answer, .session2), "turn 2 is answered")
	Set row = $ClassMethod(fixture, "DecisionOf", ref2, "turn")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", answer, row, "turn", "error"), "", "turn 2 is an error fallback, with every guarantee of a fallback")
	Do $$$AssertEquals($Select($IsObject(answer): answer.SessionBroken_"|"_answer.Busy_"|"_answer.SessionRotated, 1: "none"), "1|0|0", "with SessionBroken 1")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, ..#RUNNER), id, "the link is as it was")
	Do $$$AssertEquals($ClassMethod(fixture, "SessionExport", id), export, "and so is the saved session's data: the history is not repaired")

	Set untrusted = $ClassMethod(fixture, "NewRequest", "turn", "untrusted", "[[mock:invalid-input]] Break it as untrusted.", .refU, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(refU)
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", untrusted, .other, .sessionU), "the untrusted turn is answered")
	Set rowU = $ClassMethod(fixture, "DecisionOf", refU, "turn")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", other, rowU, "turn", "error"), "", "it is an error fallback, with every guarantee of a fallback")
	Do $$$AssertEquals($Select($IsObject(other): other.SessionBroken, 1: "none"), 0, "with no SessionBroken")

	Set fresh = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-ask]] What is my build server called?", .ref3, owner)
	Set fresh.SessionMode = "fresh"
	Set fresh.SeedText = "Earlier the user said that the build server is called ORION-7."
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref3)
	Set mark = $ClassMethod(mock, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", fresh, .third, .session3), "turn 3 is answered")
	Do $$$AssertEquals($Select($IsObject(third): third.Text_"|"_third.Fallback_"|"_third.SessionRotated_"|"_third.SessionBroken, 1: "none"), ..#ASKTEXT_"|0|1|0", "with the text of recall-ask and SessionRotated 1")
	Set moved = ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, ..#RUNNER)
	Do $$$AssertTrue((moved '= "") && (moved '= id), "the link has moved to a new session: "_moved_" (it named "_id_")")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Set requests = $ClassMethod(fixture, "FindRequests", entries, ref3)
	Do $$$AssertEquals(requests.%Size(), 1, "turn 3 made one model request")
	If requests.%Size() = 1 {
		Do $$$AssertEquals(requests.%Get(0).request.messages.%Size(), 1, "whose messages are one")
		Do $$$AssertEquals($ClassMethod(fixture, "Messages", requests.%Get(0)), "user:"_fresh.SeedText_$Char(10, 10)_fresh.Input, "a user message with the seed, a blank line and the input")
	}
	Do $$$AssertTrue(##class(%AI.Agent.Session).%ExistsId(id), "the old session's row still exists")
}

/// --- helpers ---
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

/// The folder of the private database, OCUTALON_PRIVATE, with a trailing slash, as the configuration holds it ("" when it cannot be read). The configuration
/// is read in %SYS.
ClassMethod PrivateDirectory() As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set sc = ##class(Config.Databases).Get("OCUTALON_PRIVATE", .properties)
	Quit $Select($$$ISOK(sc): ##class(%File).NormalizeDirectory($Get(properties("Directory"))), 1: "")
}

/// Writes the System Default Settings row of the setting of the item, remembering the row that was there once, for OnAfterOneTest (RememberDefault).
Method Put(item As %String, setting As %String, value As %String) [ Private ]
{
	Set saved = ..SavedRows
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RememberDefault(.saved, item, setting)
	Set ..SavedRows = saved
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).PutDefault(item, setting, value), "the setting "_setting_" of "_item_" is '"_value_"'")
}

/// Gives ChatAgent the effort for the test and starts it again, so that its sessions are composed with it. The Chat agent declares no EFFORT, so without a
/// value the effort half of the config could not fail. OnAfterOneTest puts the row back and starts ChatAgent again.
Method PutEffort(effort As %String) [ Private ]
{
	Do ..Put(..#RUNNER, "Effort", effort)
	Set ..ChatChanged = 1
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Restart(..#PRODUCTION_"||"_..#RUNNER), ..#RUNNER_" is started again with the effort "_effort)
}

/// Arms the countdown of the mock for the marker with the number of requests that get its first reply, and remembers it, so that OnAfterOneTest clears it.
Method Arm(marker As %String, remaining As %Integer) [ Private ]
{
	Set ..Armed = ..Armed _ $ListBuild(marker)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).Arm(marker, remaining), "the countdown of "_marker_" is armed with "_remaining)
}

/// Takes the conversation lock of (owner, ChatAgent) in this process, without waiting, and remembers the hold, so that OnAfterOneTest releases it on every path.
/// 1 when it is taken.
Method Hold(owner As %String) As %Boolean [ Private ]
{
	If '##class(OcuTalon.Bridge.Data.ConversationLink).Lock(owner, ..#RUNNER, 0) Quit 0
	Set ..Held = ..Held _ $ListBuild($ListBuild(owner, ..#RUNNER))
	Quit 1
}

/// Releases one hold of the conversation lock of (owner, ChatAgent) that Hold took.
Method Release(owner As %String) [ Private ]
{
	Set kept = ""
	Set released = 0
	Set position = 0
	While $ListNext(..Held, position, hold) {
		If 'released && ($List(hold, 1) = owner) && ($List(hold, 2) = ..#RUNNER) {
			Set released = 1
			Do ##class(OcuTalon.Bridge.Data.ConversationLink).Unlock(owner, ..#RUNNER)
		} Else {
			Set kept = kept _ $ListBuild(hold)
		}
	}
	Set ..Held = kept
	Do $$$AssertTrue(released, "the test releases the conversation lock")
}

/// Asserts that the answer is a Busy Reply and nothing else: Busy 1, no DecisionRef, text, failure text, steps or host data, and not a fallback.
Method AssertBusy(answer As %RegisteredObject, label As %String) [ Private ]
{
	If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, label_" is a Reply")
		Quit
	}
	Do $$$AssertEquals(answer.Busy, 1, label_" has Busy 1")
	Do $$$AssertEquals(answer.DecisionRef_"|"_answer.Text_"|"_answer.FailureText_"|"_answer.Steps_"|"_answer.HostData_"|"_answer.Outcome_"|"_answer.FallbackReason, "||||||", label_" has no DecisionRef, text, failure text, steps, host data, outcome or reason")
	Do $$$AssertEquals(answer.Fallback_"|"_answer.Tainted_"|"_answer.SessionRotated_"|"_answer.SessionBroken_"|"_answer.ToolsRun, "0|0|0|0|0", label_" is not a fallback and sets no other flag")
}

/// Asserts that the logged request has the cap and the effort of the composed session config: 8,000 tokens and the effort low.
Method AssertConfig(logged As %DynamicObject, label As %String) [ Private ]
{
	Do $$$AssertEquals(logged.maxTokens, ..#CAP, label_": the request has a cap of "_..#CAP)
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Effort(logged), "low", label_": and the effort low")
}

}
