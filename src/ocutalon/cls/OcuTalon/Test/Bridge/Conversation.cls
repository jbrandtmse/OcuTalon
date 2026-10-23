/// Tests of the linked conversation in the runner and its adapter, in this process (Story 1.8; AD-3, AD-6, AD-7, AD-9, AD-10). THIS CLASS RUNS IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21), like Test.Bridge.Runner: the requests go to the CI mock, so the test needs the CI override's
/// environment and the mock's request log, and where it has neither it fails with the reason and builds no provider. The runner host is a
/// shadow, ZzRunner (Test.Bridge.Runner NewRunner), so no production item is touched, and the requests run through the real AgentRunner.OnMessage,
/// so that they reach Adapter.Agent Answer. Every turn has its own conversation (a new OwnerRef) unless the test is about one conversation, which
/// then uses one OwnerRef for all its turns. The mock's log shows what each request carried: the messages (the history before the turn's input),
/// the cap and the effort.
///   - TestFirstAndNextTurn: a user's first turn creates a link, (owner, ZzRunner), that names a saved AI session, and SessionRotated is 0; the next
///     turn of the owner keeps the same link and session, carries the first exchange before its input in the logged request, and the saved session
///     then holds both exchanges;
///   - TestThrowawayKinds: decide, diagnose and an untrusted turn, with the SessionMode empty and with fresh and a SeedText, for a new owner and for
///     an owner with a link, make no link and save no session; the link and the saved session of the owner stay as they were, and each request
///     carries its note and its input, with no seed and no history;
///   - TestFailedChat: a provider failure on a linked owner leaves the link and the saved session's data as they were, and on a first turn leaves no
///     link and no session; the failure Reply is the one of Story 1.6;
///   - TestTaintedTurn: a turn that the probe tool taints is answered with Tainted 1 and saves nothing: the link and the saved session's data of the
///     linked owner stay, and a tainted first turn makes no link and no session;
///   - TestFresh: SessionMode fresh with a SeedText and a SystemNote moves the link to a new session and sets SessionRotated; the logged first
///     request has exactly one message, from the user, with the seed, a blank line, the note, a blank line and the input; the old session's row stays; a
///     fresh turn of an owner with no link creates the link; a continue turn sends the note and ignores the seed;
///   - TestFreshFailsOrTainted: a fresh turn that fails, or is tainted, leaves the link as it was and SessionRotated 0;
///   - TestChatInput: ChatInput (pure) for every combination of an empty and a set SeedText, SystemNote and Input, seeded and not;
///   - TestNoSessionKept: after a linked turn the adapter's agent holds no Session, the linked id opens as a session that no agent has attached, and
///     the next turn opens it with the composed config (the logged cap and effort); a decide leaves no Session either;
///   - TestFirstStepCountsHistory: the estimate of the first model step is the base of the call (the system prompt and the tool catalog) plus the input
///     that Chat gets (the seed and the note of a fresh turn included) plus, for a session opened from the link, the JSON of its stored history (AD-9);
///   - TestEmptyOwner: a user's turn with an empty OwnerRef is refused with an error that names OwnerRef, and nothing reaches the mock;
///   - TestLockReleased: the conversation lock is free after a turn that completed, one that failed, one that was tainted and one whose session could
///     not be opened (a link that names a session that is gone);
///   - TestLockReleasedOnException: an exception inside the linked turn (a runner whose adapter raises in Converse) comes back as an error status with
///     no reply, and the lock is free, the agent holds no Session, the context is over, no link was made and nothing reached the mock;
///   - TestSaveProblem: a link that cannot be saved (an OwnerRef over the length of the column) is one warning that names the runner, the OwnerRef and
///     the DecisionRef, changes nothing of the reply, leaves SessionRotated 0, and the conversation lock free;
///   - TestLockHeldFromOpenToSave (QA): a runner whose adapter notes, at the open or creation of the AI session, right before Chat, right before the
///     save and when the agent's Session is cleared, whether another process can take the conversation lock (Test.Bridge.ZzLockSpyAdapter) shows the
///     lock held at each of them (the session is cleared before the lock is released), for a first turn, a continue turn, a fresh turn and a failed one
///     (which never reaches the save), and free after each;
///   - TestOwnersAreSeparate (QA): two owners of the same runner have conversations of their own: each request carries its owner's exchange and not
///     the other's, the links name different sessions, and each saved session holds only its owner's words;
///   - TestResumedTurnCountsItsOwnUsage (QA): the Usage row of a turn on a resumed session counts that turn alone (one request), so that the rows of
///     the two turns add up to the counters of the saved session, which GetStats() restores on the open (AD-20);
///   - TestResumeFollowsTheRunner: after the runner's Model setting and agent class change, the owner's next turn resumes the saved session with the
///     runner's model and its agent's system prompt, and its reply and Usage row name the model that was sent (AD-7, AD-20).
/// Every test removes the AI sessions it saved (and the links that name them) and the Usage rows that ZzRunner wrote.
Class OcuTalon.Test.Bridge.Conversation Extends %UnitTest.TestCase
{

/// The config name of the shadow runner, which is the agent of its links.
Parameter AGENT = "ZzRunner";

/// The runner test class, whose helpers make the shadow runner.
Parameter RUNNERTEST = "OcuTalon.Test.Bridge.Runner";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

/// The probe agent, whose tool taints the turn (the scenario context-probe).
Parameter PROBEAGENT = "OcuTalon.Test.Bridge.ProbeAgent";

/// The cap of the composed session config, in tokens.
Parameter CAP = 8000;

/// A model of the Anthropic family other than the agents' own, with a Price row (Bridge.Installer), for TestResumeFollowsTheRunner.
Parameter OTHERMODEL = "claude-sonnet-5-5";

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.ConversationLink WHERE Agent = ?", ..#AGENT)
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE Agent = ?", ..#AGENT)
	Quit $$$OK
}

/// A user's first turn makes the link of its owner, and the next turn of the owner opens the same saved session with the first exchange in it.
Method TestFirstAndNextTurn()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set usage = ..UsageRows()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertEquals(..LinkOf(owner), "", "a new owner has no link")

	Set one = ..NewTurn("[[mock:recall-tell]] My build server is called ORION-7.", owner)
	Do $$$AssertStatusOK(..Send(host, one, .first, .loggedOne), "the first turn is answered")
	Do $$$AssertEquals(first.Text_"|"_first.FailureText_"|"_first.Busy_"|"_first.Tainted, "Noted.||0|0", "with the text of the mock and no failure, Busy or taint")
	Do $$$AssertEquals(first.SessionRotated, 0, "a first turn is not a rotation: SessionRotated is 0")
	Set id = ..LinkOf(owner)
	Do $$$AssertTrue(id '= "", "the link of (owner, ZzRunner) exists and names a session: "_id)
	Do $$$AssertTrue(##class(%AI.Agent.Session).%ExistsId(id), "which is a saved AI session")
	Do $$$AssertEquals(..Links(owner), 1, "the owner has one link")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Messages(loggedOne.%Get(0)), "user:"_one.Input, "the first request carries the input alone")

	Set two = ..NewTurn("[[mock:recall-ask]] What is my build server called?", owner)
	Do $$$AssertStatusOK(..Send(host, two, .next, .loggedTwo), "the next turn is answered")
	Do $$$AssertEquals(next.Text, "Your build server is called ORION-7.", "with the text of the mock")
	Do $$$AssertEquals(next.SessionRotated, 0, "SessionRotated is 0 for a continue turn")
	Do $$$AssertEquals(..LinkOf(owner), id, "the link names the same session")
	Do $$$AssertEquals(..Links(owner), 1, "and the owner still has one link")
	Do $$$AssertEquals(loggedTwo.%Size(), 1, "the next turn made one model request")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Messages(loggedTwo.%Get(0)), "user:"_one.Input_$Char(1)_"assistant:Noted."_$Char(1)_"user:"_two.Input, "which carries the first exchange, the user's words and the reply, before the input of the second")
	Set saved = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionExport(id)
	For piece = one.ItemId, "Noted.", two.ItemId, "Your build server is called ORION-7." {
		Do $$$AssertTrue(saved [ piece, "the saved session now holds '"_piece_"'")
	}
	Do $$$AssertEquals(..UsageRows() - usage, 2, "one Usage row was written for each turn")
}

/// decide, diagnose and an untrusted turn run in a session that is never saved or linked, for an owner with no link and for an owner with one:
/// no link comes of them, the link and the saved session of the owner stay as they were, and the untrusted request carries no history.
Method TestThrowawayKinds()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set cases = $ListBuild($ListBuild("decide", "user"), $ListBuild("diagnose", "untrusted"), $ListBuild("turn", "untrusted"))

	// an owner with no link: with the SessionMode empty, and with fresh and a SeedText, which only a linked turn sends
	Set stranger = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set position = 0
	While $ListNext(cases, position, case) {
		For mode = "", "fresh" {
			Set label = $List(case, 1)_" ("_$List(case, 2)_", SessionMode '"_mode_"')"
			Set request = ..NewTurn("[[mock:recall-tell]] Say something.", stranger, , $List(case, 1), $List(case, 2), mode, $Select(mode = "fresh": "A recap that a throwaway request never sends.", 1: ""))
			Set sc = ..Send(host, request, .reply, .logged)
			Do $$$AssertStatusOK(sc, label_" is answered for an owner with no link")
			Set seen = $Select($IsObject(reply): reply.Text_"|"_reply.SessionRotated, 1: "none")
			Do $$$AssertEquals(seen, "Noted.|0", label_" with the text of the mock and no rotation: "_seen_" "_$Select($IsObject(reply): $Extract(reply.FailureText, 1, 300), 1: "")_" "_$SYSTEM.Status.GetErrorText(sc))
			Do $$$AssertEquals(logged.%Size(), 1, label_" made one model request")
			If logged.%Size() = 1 Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Messages(logged.%Get(0)), "user:"_request.Input, label_" carries its input alone: the seed of a fresh request is not sent")
			Do $$$AssertEquals(..LinkOf(stranger), "", label_" makes no link")
			Do $$$AssertEquals(host.Adapter.Agent.Session, "", label_" leaves no Session on the agent")
		}
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark(), mark, "and saves no AI session")

	// an owner with a link
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set tell = ..NewTurn("[[mock:recall-tell]] My build server is called ORION-7.", owner)
	Do $$$AssertStatusOK(..Send(host, tell, .told), "a user's turn makes the link of an owner")
	Set id = ..LinkOf(owner)
	Do $$$AssertTrue(id '= "", "the owner has a link: "_id)
	Set export = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionExport(id)
	Do $$$AssertTrue(export [ tell.ItemId, "whose saved session holds the user's words")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set position = 0
	While $ListNext(cases, position, case) {
		For mode = "", "fresh" {
			Set label = $List(case, 1)_" ("_$List(case, 2)_", SessionMode '"_mode_"')"
			Set request = ..NewTurn("[[mock:recall-tell]] Say something else.", owner, , $List(case, 1), $List(case, 2), mode, "A recap that a throwaway request never sends.", "A note for the throwaway request.")
			Do $$$AssertStatusOK(..Send(host, request, .reply, .logged), label_" is answered for the owner with a link")
			Do $$$AssertEquals($Select($IsObject(reply): reply.SessionRotated, 1: "none"), 0, label_" is no rotation")
			Do $$$AssertEquals(logged.%Size(), 1, label_" made one model request")
			Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Messages(logged.%Get(0)), "user:"_request.SystemNote_$Char(10, 10)_request.Input, label_" carries its note and its input alone: no seed, no history of the conversation")
			Do $$$AssertEquals(..LinkOf(owner), id, label_" leaves the link as it was")
			Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionExport(id), export, label_" leaves the saved session as it was")
		}
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark(), mark, "and saves no AI session")
}

/// A provider failure (the scenario provider-error) saves nothing: for a linked owner the link and the saved session's data are as they were, for
/// a first turn there is no link and no saved session. The reply is the failure Reply of Story 1.6: status OK, the provider's text as FailureText,
/// no Text.
Method TestFailedChat()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(..Send(host, ..NewTurn("[[mock:recall-tell]] My build server is called ORION-7.", owner), .told), "a user's turn makes the link of an owner")
	Set id = ..LinkOf(owner)
	Set export = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionExport(id)
	Do $$$AssertTrue((id '= "") && (export '= ""), "the link names a session with a history: "_id)
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set request = ..NewTurn("[[mock:provider-error]] Fail this.", owner)
	Do $$$AssertStatusOK(..Send(host, request, .failed, .logged), "a failing turn of the linked owner gives status OK")
	Do ..AssertFailureReply(failed, "the linked owner's")
	Do $$$AssertEquals(logged.%Size(), 1, "the failing request reached the mock once")
	Do $$$AssertEquals(logged.%Get(0).status, 500, "and was answered with the provider's failure")
	Do $$$AssertEquals(..LinkOf(owner), id, "the link is as it was")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionExport(id), export, "and so is the saved session's data")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark(), mark, "no AI session was saved")

	Set first = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ..NewTurn("[[mock:provider-error]] Fail this first.", first)
	Do $$$AssertStatusOK(..Send(host, request, .failed), "a failing first turn gives status OK")
	Do ..AssertFailureReply(failed, "the first turn's")
	Do $$$AssertEquals(..LinkOf(first), "", "it made no link")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark(), mark, "and saved no AI session")
	Do $$$AssertEquals(host.Adapter.Agent.Session, "", "and the agent holds no Session")
}

/// A turn that the probe tool taints (the scenario context-probe) is answered with Tainted 1 and is never saved: for a linked owner the link and the
/// saved session's data are as they were, and for a first turn there is no link and no saved session (AD-10 3a; the late Chat of a timed-out turn is
/// the same case).
Method TestTaintedTurn()
{
	If ..Guard() Quit
	Set host = ..NewHost(..#PROBEAGENT)
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(..Send(host, ..NewTurn("[[mock:recall-tell]] My build server is called ORION-7.", owner), .told), "an untainted turn of the probe agent makes the link of an owner")
	Do $$$AssertEquals(told.Tainted, 0, "and is not tainted")
	Set id = ..LinkOf(owner)
	Set export = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionExport(id)
	Do $$$AssertTrue((id '= "") && (export '= ""), "the link names a session with a history: "_id)
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set request = ..NewTurn("[[mock:context-probe]] Run the probe.", owner)
	Do $$$AssertStatusOK(..Send(host, request, .tainted, .logged), "a turn that the probe tool taints is answered")
	Do $$$AssertEquals(tainted.Tainted_"|"_tainted.Text_"|"_tainted.SessionRotated, "1|The probe ran.|0", "with Tainted 1 and the text of the scenario")
	Do $$$AssertEquals(logged.%Size(), 2, "the turn made the tool request and the one after the tool")
	Do $$$AssertEquals(..LinkOf(owner), id, "the link is as it was")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionExport(id), export, "and so is the saved session's data: the tool result is not in the stored history")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark(), mark, "no AI session was saved")

	Set first = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(..Send(host, ..NewTurn("[[mock:context-probe]] Run the probe first.", first), .tainted), "a tainted first turn is answered")
	Do $$$AssertEquals(tainted.Tainted, 1, "with Tainted 1")
	Do $$$AssertEquals(..LinkOf(first), "", "it made no link")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark(), mark, "and saved no AI session")
}

/// SessionMode fresh moves the link to a new session that starts with the seed. The logged first request has exactly one message, from the user, whose
/// text is the seed, a blank line, the note, a blank line and the input; the reply says SessionRotated; the old session's row stays (it waits for
/// the purge of Story 30.2). A fresh turn of an owner with no link creates the link and says SessionRotated too, and a continue turn sends its note
/// and ignores its seed.
Method TestFresh()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set tell = ..NewTurn("[[mock:recall-tell]] My build server is called ORION-7.", owner)
	Do $$$AssertStatusOK(..Send(host, tell, .told), "a user's turn makes the link of an owner")
	Set old = ..LinkOf(owner)
	Do $$$AssertTrue(old '= "", "the owner has a link: "_old)

	Set seed = "Earlier, the user said that the build server is called ORION-7."
	Set note = "The user opened a new topic."
	Set request = ..NewTurn("[[mock:recall-ask]] What is it called?", owner, , "turn", "user", "fresh", seed, note)
	Do $$$AssertStatusOK(..Send(host, request, .fresh, .logged), "a fresh turn is answered")
	Do $$$AssertEquals(fresh.Text_"|"_fresh.SessionRotated, "Your build server is called ORION-7.|1", "with the text of the mock and SessionRotated 1")
	Set new = ..LinkOf(owner)
	Do $$$AssertTrue((new '= "") && (new '= old), "the link now names a new session: "_new_" (it named "_old_")")
	Do $$$AssertEquals(..Links(owner), 1, "and the owner still has one link")
	Do $$$AssertEquals(logged.%Size(), 1, "the fresh turn made one model request")
	Set expected = seed_$Char(10, 10)_note_$Char(10, 10)_request.Input
	Do $$$AssertEquals(logged.%Get(0).request.messages.%Size(), 1, "whose messages are exactly one")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Messages(logged.%Get(0)), "user:"_expected, "from the user, with the seed, a blank line, the note, a blank line and the input")
	Do $$$AssertTrue(##class(%AI.Agent.Session).%ExistsId(old), "the old session's row still exists")
	Set saved = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionExport(new)
	Do $$$AssertTrue((saved [ request.ItemId) && (saved [ "Your build server is called ORION-7."), "the new session holds the fresh turn and its reply")
	Do $$$AssertTrue(saved '[ tell.ItemId, "and not the old exchange: the seed is the recap")

	// a continue turn sends its note, and ignores its seed
	Set request = ..NewTurn("[[mock:recall-tell]] And again.", owner, , "turn", "user", "continue", "A recap that a continue turn ignores.", "The user is back.")
	Do $$$AssertStatusOK(..Send(host, request, .again, .loggedAgain), "a continue turn with a seed and a note is answered")
	Do $$$AssertEquals(again.SessionRotated, 0, "SessionRotated is 0")
	Do $$$AssertEquals(..LinkOf(owner), new, "and the link stays")
	Set sent = ##class(OcuTalon.Test.Agent.RunnerFixture).Messages(loggedAgain.%Get(0))
	Do $$$AssertTrue(sent [ ("user:The user is back."_$Char(10, 10)_request.Input), "the note travels before the input")
	Do $$$AssertTrue(sent '[ "A recap that a continue turn ignores.", "and the seed is not sent")
	Do $$$AssertTrue(sent [ expected, "the history of the conversation is before it")

	// a fresh turn of an owner with no link creates the link
	Set stranger = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ..NewTurn("[[mock:recall-tell]] Start here.", stranger, , "turn", "user", "fresh", seed)
	Do $$$AssertStatusOK(..Send(host, request, .first, .loggedFirst), "a fresh turn of an owner with no link is answered")
	Do $$$AssertEquals(first.SessionRotated, 1, "with SessionRotated 1: the link was created for the new session")
	Do $$$AssertTrue(..LinkOf(stranger) '= "", "the link exists")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Messages(loggedFirst.%Get(0)), "user:"_seed_$Char(10, 10)_request.Input, "and the request holds the seed and the input")
}

/// A fresh turn that fails, and one that is tainted, leave the link where it was and say SessionRotated 0: the new session has no id until it is
/// saved, and it is saved only after a completed Chat that is not tainted.
Method TestFreshFailsOrTainted()
{
	If ..Guard() Quit
	Set seed = "Earlier, the user said that the build server is called ORION-7."
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(..Send(host, ..NewTurn("[[mock:recall-tell]] My build server is called ORION-7.", owner), .told), "a user's turn makes the link of an owner")
	Set id = ..LinkOf(owner)
	Set export = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionExport(id)
	Do $$$AssertTrue((id '= "") && (export '= ""), "the link names a session with a history: "_id)
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set request = ..NewTurn("[[mock:provider-error]] Fail this.", owner, , "turn", "user", "fresh", seed)
	Do $$$AssertStatusOK(..Send(host, request, .failed, .logged), "a fresh turn that fails gives status OK")
	Do ..AssertFailureReply(failed, "the fresh turn's")
	Do $$$AssertEquals(failed.SessionRotated, 0, "SessionRotated is 0")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Messages(logged.%Get(0)), "user:"_seed_$Char(10, 10)_request.Input, "the failing request did carry the seed")
	Do $$$AssertEquals(..LinkOf(owner), id, "the link is unchanged")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionExport(id), export, "and so is the saved session")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark(), mark, "and no new session was saved")

	Set probe = ..NewHost(..#PROBEAGENT)
	Set request = ..NewTurn("[[mock:context-probe]] Run the probe.", owner, , "turn", "user", "fresh", seed)
	Do $$$AssertStatusOK(..Send(probe, request, .tainted), "a fresh turn that the probe tool taints is answered")
	Do $$$AssertEquals(tainted.Tainted_"|"_tainted.SessionRotated, "1|0", "with Tainted 1 and SessionRotated 0")
	Do $$$AssertEquals(..LinkOf(owner), id, "the link is unchanged")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionExport(id), export, "and so is the saved session")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark(), mark, "and no new session was saved")
}

/// ChatInput (pure) joins the parts that are set with a blank line, in the order seed, note, input; with seeded 0 the seed is left out. Every
/// combination of an empty and a set SeedText, SystemNote and Input is tried, each with seeded 0 and 1.
Method TestChatInput()
{
	Set blank = $Char(10, 10)
	Set count = 0
	For seed = "", "Recap." {
		For note = "", "Note." {
			For input = "", "Input." {
				For seeded = 0, 1 {
					Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
					Set request.SeedText = seed
					Set request.SystemNote = note
					Set request.Input = input
					Set parts = ""
					If seeded && (seed '= "") Set parts = parts _ $ListBuild(seed)
					If note '= "" Set parts = parts _ $ListBuild(note)
					If input '= "" Set parts = parts _ $ListBuild(input)
					Set expected = ""
					Set position = 0
					While $ListNext(parts, position, part) {
						Set expected = expected _ $Select(expected = "": "", 1: blank) _ part
					}
					Set actual = ##class(OcuTalon.Bridge.Adapter.Agent).ChatInput(request, seeded)
					Set count = count + 1
					Do $$$AssertEquals(actual, expected, "ChatInput of seed '"_seed_"', note '"_note_"', input '"_input_"', seeded "_seeded_" is "_$ListLength(parts)_" part(s)")
				}
			}
		}
	}
	Do $$$AssertEquals(count, 16, "all 16 combinations were tried")
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.SeedText = "Recap."
	Set request.SystemNote = "Note."
	Set request.Input = "Input."
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Adapter.Agent).ChatInput(request), "Note."_blank_"Input.", "seeded is 0 by default")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Adapter.Agent).ChatInput(request, 1), "Recap."_blank_"Note."_blank_"Input.", "and the order is seed, note, input")
	Set request.SeedText = ""
	Set request.SystemNote = ""
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Adapter.Agent).ChatInput(request, 1), "Input.", "a request with neither a seed nor a note sends its input as it is")
}

/// No session object outlives a request: after a linked turn the adapter's agent holds no Session, and the linked id opens as an object that no
/// agent has attached. The next turn opens it with the composed config, so the logged request has the cap of 8,000 tokens and the effort of the
/// adapter, with the history before the input. A decide leaves no Session on the agent either.
Method TestNoSessionKept()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set one = ..NewTurn("[[mock:recall-tell]] My build server is called ORION-7.", owner)
	Do $$$AssertStatusOK(..Send(host, one, .first, .loggedOne), "a linked turn is answered")
	Do $$$AssertTrue($IsObject(host.Adapter.Agent), "the adapter built its agent")
	Do $$$AssertEquals(host.Adapter.Agent.Session, "", "which holds no Session after the turn")
	Set id = ..LinkOf(owner)
	Do $$$AssertEquals(..Attached(id), 0, "%OpenId of the linked id gives an object that is not attached to an agent")
	Do $$$AssertEquals(loggedOne.%Get(0).maxTokens, ..#CAP, "the first request has the cap of "_..#CAP)
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Effort(loggedOne.%Get(0)), "low", "and the effort low")

	Set two = ..NewTurn("[[mock:recall-ask]] What is my build server called?", owner)
	Do $$$AssertStatusOK(..Send(host, two, .next, .loggedTwo), "the next turn is answered")
	Do $$$AssertEquals(host.Adapter.Agent.Session, "", "the agent holds no Session after it either")
	Do $$$AssertEquals(..Attached(id), 0, "and the session is still not attached to any agent")
	Do $$$AssertEquals(loggedTwo.%Get(0).maxTokens, ..#CAP, "the resumed session still sends its cap of "_..#CAP_": it was opened with the composed config")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Effort(loggedTwo.%Get(0)), "low", "and its effort low")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Messages(loggedTwo.%Get(0)), "user:"_one.Input_$Char(1)_"assistant:Noted."_$Char(1)_"user:"_two.Input, "with the history before the input")

	Set stranger = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(..Send(host, ..NewTurn("[[mock:recall-tell]] Say something.", stranger, , "decide", "untrusted"), .decided), "a decide is answered")
	Do $$$AssertEquals(host.Adapter.Agent.Session, "", "and leaves no Session on the agent")
}

/// The estimate of the first model step counts what the first request carries (AD-9): the system prompt and the tool catalog of the agent, the input that
/// Chat gets (ChatInput: for a fresh turn the seed and the note too) and, for a session that was opened from the link, the JSON of its stored history,
/// which grows with the conversation. A new session counts no history.
Method TestFirstStepCountsHistory()
{
	If ..Guard() Quit
	Set buffer = "OcuTalon.Bridge.Adapter.StepBuffer"
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set one = ..NewTurn("[[mock:recall-tell]] My build server is called ORION-7.", owner)
	Do $$$AssertStatusOK(..Send(host, one, .first), "turn 1 is answered")
	Set base = $Length(host.Adapter.Agent.SystemPrompt) + $Length(host.Adapter.Agent.ToolManager.%Discover().%ToJSON())
	Do $$$AssertTrue(base > 0, "the base of the estimates is measured: "_base)
	Set estimate1 = ..FirstEstimate(first)
	Do $$$AssertEquals(estimate1, $ClassMethod(buffer, "Tokens", base + $Length(one.Input)), "turn 1 counts the base and its input, and no history")

	Set history = ..HistoryChars(host, ..LinkOf(owner))
	Do $$$AssertTrue(history > 0, "the saved session holds a history: "_history_" characters of JSON")
	Set two = ..NewTurn("[[mock:recall-ask]] What is my build server called?", owner)
	Do $$$AssertStatusOK(..Send(host, two, .next), "turn 2 is answered")
	Set estimate2 = ..FirstEstimate(next)
	Do $$$AssertEquals(estimate2, $ClassMethod(buffer, "Tokens", base + $Length(two.Input) + history), "turn 2 counts the base, its input and the stored history")
	Do $$$AssertTrue(estimate2 > estimate1, "so its estimate is larger: "_estimate2_" against "_estimate1)

	Set seed = "Earlier, the user said that the build server is called ORION-7."
	Set note = "The user opened a new topic."
	Set three = ..NewTurn("[[mock:recall-tell]] A fresh start.", owner, , "turn", "user", "fresh", seed, note)
	Do $$$AssertStatusOK(..Send(host, three, .fresh), "a fresh turn is answered")
	Set expected = $Length(##class(OcuTalon.Bridge.Adapter.Agent).ChatInput(three, 1))
	Do $$$AssertTrue(expected > $Length(three.Input), "the input that Chat gets is longer than the request's Input: "_expected)
	Do $$$AssertEquals(..FirstEstimate(fresh), $ClassMethod(buffer, "Tokens", base + expected), "a fresh turn counts the input that Chat gets, the seed and the note included, and no history")
}

/// A user's turn with an empty OwnerRef has no conversation to link: the runner refuses it with an error that names OwnerRef, sends nothing to the
/// mock, makes no link and leaves no context.
Method TestEmptyOwner()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set request = ..NewTurn("[[mock:recall-tell]] Say something.", "")
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set sessions = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set usage = ..UsageRows()
	Set links = ..LinkRows()
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusNotOK(sc, "a user's turn with an empty OwnerRef is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "OwnerRef", "with an error that names OwnerRef: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertTrue('$IsObject(reply), "and no reply")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Do $$$AssertEquals(entries.%Size(), 0, "nothing reached the mock")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "no context is left")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark(), sessions, "no session was made")
	Do $$$AssertEquals(..UsageRows(), usage, "and no Usage row was written")
	Do $$$AssertEquals(..LinkRows(), links, "and no link row")
	// a decide with an empty owner is not linked, so the runner does not refuse it for that
	Set decide = ..NewTurn("[[mock:recall-tell]] Say something.", "", , "decide", "untrusted")
	Do $$$AssertStatusOK(..Send(host, decide, .answered), "a decide with an empty OwnerRef is answered: only a linked turn needs an owner")
}

/// The conversation lock is released on every path of a linked turn, in the order the spec gives (the session is released first). A second process
/// finds it free after a turn that completed, one that failed, one that was tainted, and one whose session could not be opened (the link names a
/// session that is gone, which is an error status), and also while no turn runs.
Method TestLockReleased()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set probe = ..NewHost(..#PROBEAGENT)
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertEquals(..LockFree(owner), 1, "control: a second process takes a lock that nobody holds")
	Do $$$AssertStatusOK(..Send(host, ..NewTurn("[[mock:recall-tell]] My build server is called ORION-7.", owner)), "a turn that completes is answered")
	Do $$$AssertEquals(..LockFree(owner), 1, "the lock is free after it")
	Do $$$AssertStatusOK(..Send(host, ..NewTurn("[[mock:provider-error]] Fail this.", owner)), "a turn that fails is answered")
	Do $$$AssertEquals(..LockFree(owner), 1, "the lock is free after it")
	Do $$$AssertStatusOK(..Send(probe, ..NewTurn("[[mock:context-probe]] Run the probe.", owner)), "a turn that is tainted is answered")
	Do $$$AssertEquals(..LockFree(owner), 1, "the lock is free after it")

	Set lost = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Data.ConversationLink).Point(lost, ..#AGENT, "999999"), "a link is made to name a session that does not exist")
	Set sc = ..Send(host, ..NewTurn("[[mock:recall-tell]] Say something.", lost), .reply)
	Do $$$AssertStatusNotOK(sc, "a turn whose session cannot be opened keeps its error status")
	Do $$$AssertTrue('$IsObject(reply), "and has no reply")
	Do $$$AssertEquals(..LockFree(lost), 1, "the lock is free after it")
	Do $$$AssertEquals(..LinkOf(lost), "999999", "and the link is as it was")
	Do $$$AssertEquals(host.Adapter.Agent.Session, "", "the agent holds no Session")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "and the context is over")
}

/// An exception inside the linked turn (the adapter of OcuTalon.Test.Bridge.ZzThrowRunner raises in Converse, after the session is made) is not
/// caught by Converse: it comes back as an error status with no reply, and the runner still releases the session and then the lock, and ends the
/// context. A second process finds the lock free, the agent holds no Session, no link was made and nothing reached the mock.
Method TestLockReleasedOnException()
{
	If ..Guard() Quit
	Set host = $ClassMethod(..#RUNNERTEST, "NewRunner", "OcuTalon.Agent.Chat", "low", , , "OcuTalon.Test.Bridge.ZzThrowRunner")
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ..NewTurn("[[mock:recall-tell]] Say something.", owner)
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set sc = host.OnMessage(request, .reply)
	Do $$$AssertStatusNotOK(sc, "an exception inside the linked turn comes back as an error status")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "Converse raised", "which holds the exception's text: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertTrue('$IsObject(reply), "and no reply")
	Do $$$AssertEquals(..LockFree(owner), 1, "the conversation lock is free")
	Do $$$AssertTrue($IsObject(host.Adapter.Agent), "the adapter built its agent")
	Do $$$AssertEquals(host.Adapter.Agent.Session, "", "which holds no Session")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "the context is over")
	Do $$$AssertEquals(..LinkOf(owner), "", "no link was made")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Do $$$AssertEquals(entries.%Size(), 0, "and nothing reached the mock")
}

/// A link that cannot be saved (an OwnerRef over the 22 characters of the column) does not change the reply: the session is saved, Point fails, and
/// one warning names the runner, the OwnerRef and the DecisionRef. A fresh turn says SessionRotated 0 then, because the link does not name the new
/// session.
Method TestSaveProblem()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = $Translate($Justify("", 30), " ", "x")
	Set request = ..NewTurn("[[mock:recall-tell]] Say something.", owner, , "turn", "user", "fresh", "A recap.")
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Do $$$AssertStatusOK(..Send(host, request, .reply), "a turn whose link cannot be saved is answered")
	Do $$$AssertEquals($Select($IsObject(reply): reply.Text_"|"_reply.SessionRotated_"|"_reply.FailureText, 1: "none"), "Noted.|0|", "with its text, SessionRotated 0 and no failure")
	Do $$$AssertEquals(..LinkOf(owner), "", "no link exists")
	Set warnings = ##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Adapter.Agent", "SaveLinked", $ListBuild(..#AGENT, owner, request.DecisionRef))
	Do $$$AssertEquals(warnings, 1, "one warning names the runner, the OwnerRef and the DecisionRef")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, "OcuTalon.Bridge.Adapter.Agent", "SaveLinked"), 1, "and it is the only one of the save")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Context).Active(), 0, "the context is over")
	Do $$$AssertEquals(..LockFree(owner), 1, "and the conversation lock is free")
}

/// The conversation lock is held at the three points of a linked turn that the spec names (AD-6): from the open of the AI session (OpenSession for a
/// continue turn, NewSession for a first or a fresh one), through Chat, to the save. The runner here is Test.Bridge.ZzLockSpyRunner, whose adapter asks
/// another process, at each of those points, whether it can take the lock, and the lock is free again when the turn is over. A turn that fails never
/// reaches the save.
Method TestLockHeldFromOpenToSave()
{
	If ..Guard() Quit
	Set host = $ClassMethod(..#RUNNERTEST, "NewRunner", "OcuTalon.Agent.Chat", "low", , , "OcuTalon.Test.Bridge.ZzLockSpyRunner")
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set host.Adapter.SpyOwner = owner
	Do $$$AssertEquals(..LockFree(owner), 1, "control: nobody holds the lock before the first turn")

	Do $$$AssertStatusOK(..Send(host, ..NewTurn("[[mock:recall-tell]] My build server is called ORION-7.", owner), .first), "a first turn is answered")
	Do $$$AssertEquals(host.Adapter.Noted(), "new=1,converse=1,save=1,release=1,release=0", "the lock is held when the session is created, before Chat and before the save, and when the session is released; Answer clears it once more after the lock is gone")
	Do $$$AssertEquals(..LockFree(owner), 1, "and free after the turn")

	Do host.Adapter.Forget()
	Do $$$AssertStatusOK(..Send(host, ..NewTurn("[[mock:recall-ask]] What is my build server called?", owner), .next), "a continue turn is answered")
	Do $$$AssertEquals(host.Adapter.Noted(), "open=1,converse=1,save=1,release=1,release=0", "the lock is held when the linked session is opened, before Chat and before the save, and when the session is released")
	Do $$$AssertEquals(..LockFree(owner), 1, "and free after the turn")

	Do host.Adapter.Forget()
	Do $$$AssertStatusOK(..Send(host, ..NewTurn("[[mock:recall-tell]] A fresh start.", owner, , "turn", "user", "fresh", "Earlier, the user said that the build server is called ORION-7."), .fresh), "a fresh turn is answered")
	Do $$$AssertEquals(fresh.SessionRotated, 1, "with SessionRotated 1")
	Do $$$AssertEquals(host.Adapter.Noted(), "new=1,converse=1,save=1,release=1,release=0", "the lock is held when the new session is created, before Chat and before the save, and when the session is released")
	Do $$$AssertEquals(..LockFree(owner), 1, "and free after the turn")

	Do host.Adapter.Forget()
	Do $$$AssertStatusOK(..Send(host, ..NewTurn("[[mock:provider-error]] Fail this.", owner), .failed), "a turn that fails is answered")
	Do $$$AssertEquals(host.Adapter.Noted(), "open=1,converse=1,release=1,release=0", "the lock is held when the session is opened, before Chat and when the session is released, and the save is never reached")
	Do $$$AssertEquals(..LockFree(owner), 1, "the lock is free after it")
}

/// Two owners of the same runner have conversations of their own (AD-6: the link is keyed by the owner and the agent). Each request carries its owner's
/// exchange and not the other's, the links name different sessions, and each saved session holds the words of its owner only.
Method TestOwnersAreSeparate()
{
	If ..Guard() Quit
	Set fixture = ..#FIXTURE
	Set host = ..NewHost()
	Set ownerA = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ownerB = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set tellA = ..NewTurn("[[mock:recall-tell]] My build server is called ORION-7.", ownerA)
	Set tellB = ..NewTurn("[[mock:recall-tell]] My laptop is called ZEBRA-3.", ownerB)
	Do $$$AssertStatusOK(..Send(host, tellA, .a1), "owner A's first turn is answered")
	Do $$$AssertStatusOK(..Send(host, tellB, .b1, .loggedB1), "owner B's first turn is answered")
	Do $$$AssertEquals(loggedB1.%Size(), 1, "owner B's first turn made one model request")
	If loggedB1.%Size() = 1 Do $$$AssertEquals($ClassMethod(fixture, "Messages", loggedB1.%Get(0)), "user:"_tellB.Input, "which carries B's input alone: A's conversation is not B's")
	Set idA = ..LinkOf(ownerA)
	Set idB = ..LinkOf(ownerB)
	Do $$$AssertTrue((idA '= "") && (idB '= "") && (idA '= idB), "the two links name two sessions: "_idA_" and "_idB)

	Set askA = ..NewTurn("[[mock:recall-ask]] What is my build server called?", ownerA)
	Set askB = ..NewTurn("[[mock:recall-tell]] And what else?", ownerB)
	Do $$$AssertStatusOK(..Send(host, askA, .a2, .loggedA2), "owner A's next turn is answered")
	Do $$$AssertStatusOK(..Send(host, askB, .b2, .loggedB2), "owner B's next turn is answered")
	Do $$$AssertEquals(loggedA2.%Size(), 1, "owner A's next turn made one model request")
	If loggedA2.%Size() = 1 Do $$$AssertEquals($ClassMethod(fixture, "Messages", loggedA2.%Get(0)), "user:"_tellA.Input_$Char(1)_"assistant:Noted."_$Char(1)_"user:"_askA.Input, "A's request carries A's exchange before its input, and nothing of B's")
	Do $$$AssertEquals(loggedB2.%Size(), 1, "owner B's next turn made one model request")
	If loggedB2.%Size() = 1 Do $$$AssertEquals($ClassMethod(fixture, "Messages", loggedB2.%Get(0)), "user:"_tellB.Input_$Char(1)_"assistant:Noted."_$Char(1)_"user:"_askB.Input, "B's request carries B's exchange before its input, and nothing of A's")
	Do $$$AssertEquals(..LinkOf(ownerA), idA, "A's link still names A's session")
	Do $$$AssertEquals(..LinkOf(ownerB), idB, "and B's link B's")
	Set savedA = $ClassMethod(fixture, "SessionExport", idA)
	Set savedB = $ClassMethod(fixture, "SessionExport", idB)
	Do $$$AssertTrue((savedA [ tellA.ItemId) && (savedA [ askA.ItemId) && (savedA '[ tellB.ItemId) && (savedA '[ askB.ItemId), "A's saved session holds A's two turns and none of B's")
	Do $$$AssertTrue((savedB [ tellB.ItemId) && (savedB [ askB.ItemId) && (savedB '[ tellA.ItemId) && (savedB '[ askA.ItemId), "and B's holds B's two turns and none of A's")
}

/// The Usage row of a turn on a resumed session counts that turn alone (AD-20): the stats of an opened session are restored, not zero, and the call is
/// counted from the reading taken after the open. Each turn has one request, and the rows of the two turns add up to the counters of the saved
/// session, which another open of it reads (GetStats() restores them).
Method TestResumedTurnCountsItsOwnUsage()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(..Send(host, ..NewTurn("[[mock:recall-tell]] My build server is called ORION-7.", owner), .first), "turn 1 is answered")
	Do $$$AssertStatusOK(..Send(host, ..NewTurn("[[mock:recall-ask]] What is my build server called?", owner), .next), "turn 2 is answered")
	Set rows = ..UsageOf(owner)
	Do $$$AssertEquals($ListLength(rows), 2, "the owner has one Usage row for each turn")
	If $ListLength(rows) = 2 {
		Set one = ##class(OcuTalon.Bridge.Data.Usage).%OpenId($List(rows, 1))
		Set two = ##class(OcuTalon.Bridge.Data.Usage).%OpenId($List(rows, 2))
		Do $$$AssertEquals(one.RequestCount_"|"_two.RequestCount, "1|1", "each row counts one model request: the second turn does not count the first")
		Set stats = ..SessionStats(host, ..LinkOf(owner))
		Do $$$AssertTrue($IsObject(stats), "the saved session's counters are read")
		If $IsObject(stats) {
			Do $$$AssertEquals(stats.%Get("total_interactions"), one.RequestCount + two.RequestCount, "the interactions of the session are the requests of the two rows")
			Do $$$AssertEquals(+stats.%Get("total_prompt_tokens") + stats.%Get("total_cache_read_tokens") + stats.%Get("total_cache_creation_tokens"), one.InputTokens + two.InputTokens, "its input tokens are the input tokens of the two rows")
			Do $$$AssertEquals(+stats.%Get("total_completion_tokens"), one.OutputTokens + two.OutputTokens, "and its output tokens the output tokens of the two rows")
		}
	}
}

/// A resumed conversation runs on the runner as it is now (AD-7): the owner's first turn is answered by ZzRunner on the Chat agent and its model; then
/// ZzRunner runs the probe agent with the Model setting OTHERMODEL, and the owner's next turn opens the same saved session, carries the first exchange,
/// sends that model, and its reply and Usage row name the model that was sent; the saved session then holds that model and the system prompt that a new
/// session of the probe agent holds (AI Hub stores the prompt of the session as it attached it).
Method TestResumeFollowsTheRunner()
{
	If ..Guard() Quit
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set first = ..NewHost()
	Set one = ..NewTurn("[[mock:recall-tell]] My build server is called ORION-7.", owner)
	Do $$$AssertStatusOK(..Send(first, one, , .loggedOne), "the first turn is answered by the runner as it was")
	Set id = ..LinkOf(owner)
	Do $$$AssertTrue(id '= "", "and is saved and linked: "_id)
	Do $$$AssertEquals(loggedOne.%Size(), 1, "it made one model request")
	If (id = "") || (loggedOne.%Size() '= 1) Quit
	Do $$$AssertTrue(loggedOne.%Get(0).model '= ..#OTHERMODEL, "control: with a model other than "_..#OTHERMODEL_": "_loggedOne.%Get(0).model)
	Set chatPrompt = ..Stored(id, "SystemPrompt")

	Set changed = ..NewHost(..#PROBEAGENT)
	Set changed.Adapter.Model = ..#OTHERMODEL
	Set stranger = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(..Send(changed, ..NewTurn("[[mock:recall-tell]] Say something.", stranger)), "a new conversation of the changed runner is answered")
	Set probePrompt = ..Stored(..LinkOf(stranger), "SystemPrompt")
	Do $$$AssertTrue((probePrompt '= "") && (probePrompt '= chatPrompt), "control: its saved session holds a system prompt other than the Chat agent's")
	Set two = ..NewTurn("[[mock:recall-ask]] What is my build server called?", owner)
	Do $$$AssertStatusOK(..Send(changed, two, .next, .loggedTwo), "the owner's next turn is answered by the changed runner")
	Do $$$AssertEquals(loggedTwo.%Size(), 1, "it made one model request")
	If loggedTwo.%Size() '= 1 Quit
	Set sent = loggedTwo.%Get(0)
	Do $$$AssertEquals(..LinkOf(owner), id, "the next turn resumed the same saved session")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Messages(sent), "user:"_one.Input_$Char(1)_"assistant:Noted."_$Char(1)_"user:"_two.Input, "with the first exchange before its input")
	Do $$$AssertEquals(sent.model, ..#OTHERMODEL, "it sends the runner's model now, not the one the session was created with")
	Do $$$AssertEquals($Select($IsObject(next): next.Model, 1: "none"), sent.model, "the reply, from its Usage row, names the model that was sent")
	Do $$$AssertEquals(..Stored(id, "Model"), ..#OTHERMODEL, "the saved session now holds the runner's model")
	Do $$$AssertTrue(..Stored(id, "SystemPrompt") = probePrompt, "and the system prompt of the runner's agent")
}

/// A property of the saved AI session with the id, as it is stored (the object is not attached and is released before the method returns), or "".
ClassMethod Stored(id As %String, property As %String) As %String [ Private ]
{
	Set session = ##class(%AI.Agent.Session).%OpenId(id)
	Quit $Select($IsObject(session): $Property(session, property), 1: "")
}

/// --- helpers ---
/// A runner host (Test.Bridge.Runner NewRunner) named ZzRunner for the agent class, with the effort low and the provider of the CI mock. The
/// scenario of a request is picked by the marker in its input.
ClassMethod NewHost(agentClass As %String = "OcuTalon.Agent.Chat") As OcuTalon.Bridge.Operation.AgentRunner [ Private ]
{
	Quit $ClassMethod(..#RUNNERTEST, "NewRunner", agentClass, "low")
}

/// A request for the runner: the kind (a turn) with the provenance (user), the input with " (test <ref>)" appended, so that the mock's log finds it
/// by the reference (ItemId), the owner, the session mode, the seed and the note. ref is the reference. It has a DecisionRef of its own, because
/// Decide allocates it before the runner is asked.
ClassMethod NewTurn(input As %String, owner As %String, Output ref As %String, kind As %String = "turn", provenance As %String = "user", mode As %String = "", seed As %String = "", note As %String = "") As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = kind
	Set request.Provenance = provenance
	Set request.ItemId = ref
	Set request.DecisionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set request.OwnerRef = owner
	Set request.Channel = "system"
	Set request.Summary = "Test "_ref
	Set request.Input = input_" (test "_ref_")"
	Set request.SessionMode = mode
	Set request.SeedText = seed
	Set request.SystemNote = note
	Quit request
}

/// Sends the request through the host's OnMessage and returns the status; reply is the runner's Reply (or ""), and logged holds the entries of the
/// mock's log for the requests that carry the reference of the request.
Method Send(host As OcuTalon.Bridge.Operation.AgentRunner, request As OcuTalon.Bridge.Msg.Request, Output reply As OcuTalon.Bridge.Msg.Reply, Output logged As %DynamicArray) As %Status [ Private ]
{
	Set logged = []
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set sc = host.OnMessage(request, .reply)
	If $$$ISOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries)) Set logged = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, request.ItemId)
	Quit sc
}

/// The estimate of the first model step of the reply (its first step record).
ClassMethod FirstEstimate(reply As OcuTalon.Bridge.Msg.Reply) As %Integer [ Private ]
{
	Quit ##class(%DynamicAbstractObject).%FromJSON(reply.Steps).%Get(0).estimatedTokens
}

/// The length of the JSON of the stored history of the saved session (GetContext), read through the host's adapter, which does not keep the session.
Method HistoryChars(host As OcuTalon.Bridge.Operation.AgentRunner, id As %String) As %Integer [ Private ]
{
	Do host.Adapter.OpenSession(id, .session)
	Set chars = $Length(session.GetContext().%ToJSON())
	Set session = ""
	Set host.Adapter.Agent.Session = ""
	Quit chars
}

/// The ids of the Usage rows that ZzRunner wrote for the owner, oldest first, as a list.
ClassMethod UsageOf(owner As %String) As %List [ Private ]
{
	Set ids = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Bridge_Data.Usage WHERE Agent = ? AND OwnerRef = ? ORDER BY ID", ..#AGENT, owner)
	While result.%Next() {
		Set ids = ids _ $ListBuild(result.%GetData(1))
	}
	Quit ids
}

/// The counters of the saved AI session with the id (GetStats(), restored by the open), read through the host's adapter, which does not keep the
/// session.
Method SessionStats(host As OcuTalon.Bridge.Operation.AgentRunner, id As %String) As %DynamicObject [ Private ]
{
	Set stats = ""
	Do host.Adapter.OpenSession(id, .session)
	If $IsObject(session) Set stats = session.GetStats()
	Set session = ""
	Set host.Adapter.Agent.Session = ""
	Quit stats
}

/// The id of the AI session that the link of the owner and ZzRunner names, or "".
ClassMethod LinkOf(owner As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, ..#AGENT)
}

/// The number of link rows of the owner.
ClassMethod Links(owner As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ConversationLink WHERE OwnerRef = ?", owner)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The number of link rows of ZzRunner.
ClassMethod LinkRows() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.ConversationLink WHERE Agent = ?", ..#AGENT)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The number of Usage rows that ZzRunner wrote.
ClassMethod UsageRows() As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Usage WHERE Agent = ?", ..#AGENT)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// 1 when %OpenId of the session id gives an object that is attached to an agent. The object is released before the method returns.
ClassMethod Attached(id As %String) As %Boolean [ Private ]
{
	Set session = ##class(%AI.Agent.Session).%OpenId(id)
	Quit $IsObject(session) && session.IsAttached()
}

/// Asserts that the Reply is the failure Reply of Story 1.6: a provider failure as FailureText, no text, not tainted, not rotated, not Busy.
Method AssertFailureReply(reply As OcuTalon.Bridge.Msg.Reply, label As %String) [ Private ]
{
	If '$IsObject(reply) {
		Do $$$AssertTrue(0, label_" runner answers with a Reply")
		Quit
	}
	Do $$$AssertTrue(reply.FailureText [ "ProviderError", label_" FailureText holds the provider's error: "_$Extract(reply.FailureText, 1, 200))
	Do $$$AssertEquals(reply.Text_"|"_reply.FinishReason_"|"_reply.SessionRotated_"|"_reply.Busy, "||0|0", label_" Reply has no text or finish reason, and is not rotated or Busy")
}

/// 1 when a second process takes the conversation lock of (owner, agent: ZzRunner unless another is given) at once, and releases it. The lock is
/// incremental, so a process that holds it takes it again: only another job tells whether it is free. Test.Bridge.ZzLockSpyAdapter and
/// Test.Bridge.Link ask it too.
ClassMethod LockFree(owner As %String, agent As %String = {..#AGENT}) As %Boolean
{
	Set token = $Increment(^IRIS.Temp.ZzConversation)
	Job ##class(OcuTalon.Test.Bridge.Conversation).TryLock(owner, agent, token)
	Set deadline = $ZHorolog + 30
	While '$Data(^IRIS.Temp.ZzConversation(token)) && ($ZHorolog < deadline) {
		Hang 0.1
	}
	Set free = $Get(^IRIS.Temp.ZzConversation(token))
	Kill ^IRIS.Temp.ZzConversation(token)
	Quit free
}

/// The job of LockFree: tries the lock without waiting, releases it when it has it, and reports through ^IRIS.Temp.ZzConversation(token).
ClassMethod TryLock(owner As %String, agent As %String, token As %Integer)
{
	Lock +^OcuTalonBP.Conv(owner, agent):0
	Set got = $Test
	If got Lock -^OcuTalonBP.Conv(owner, agent)
	Set ^IRIS.Temp.ZzConversation(token) = got
}

/// 1 when the test must not run: the environment is not the CI override's, and the test fails with the reason.
Method Guard() As %Boolean [ Private ]
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).GuardReason()
	If reason = "" Quit 0
	Do $$$AssertTrue(0, reason)
	Quit 1
}

}
