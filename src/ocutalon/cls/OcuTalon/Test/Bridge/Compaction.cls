/// Tests of the runner's compaction of a long conversation (Story 30.1; AD-6, AD-7, AD-8, AD-10, AD-20), in this process. THIS CLASS RUNS IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21), like Test.Bridge.Conversation: the requests go to the CI mock, so the test needs the CI override's
/// environment and the mock's request log, and where it has neither it fails with the reason and builds no provider. The runner host is a shadow,
/// ZzRunner (Test.Bridge.Runner NewRunner), and its requests run through the real AgentRunner.OnMessage, so that they reach Adapter.Agent Answer.
/// Each test builds the conversation of an owner of its own through the runner: turn 1 is long (about 170,000 characters of filler), turn 2 is
/// a turn that calls a tool, and turn 3 is flagged (Compact 1). The mock's log shows what each request carried. A summarizer request is a
/// logged request whose scenario is a summary one; the log keeps the size of its system text (the compaction prompt) and not the text.
///   - TestGuardedCompaction (row 1): one summarizer request with the low effort and the transcript of turn 1; turn 3 starts from the summary,
///     then turn 2's messages, and holds none of turn 1; one compaction Usage row with the estimated costs; the reply names the fork and the link
///     names the original until Decide accepts the reply (Story 17.8), then the fork; the original session is kept; SessionRotated 1;
///   - TestHistoryCountAcrossCompaction (QA of Story 17.8, DW-746): HistoryCount of the compacted turn is the original's whole count, and the turn after the accepted
///     compaction counts the fork's history the same way GetContext() and the stored messages do;
///   - TestNothingOlder (row 2), TestNotCompactable (row 8): no summarizer request, no compaction row;
///   - TestSummarizerOffSchema, TestCheckFails, TestReopenFails, TestSummarizerRateLimited (rows 3 to 5): the seeded fallback, one warning, never a
///     FailureText;
///   - TestSummarizerOverLimit, TestHistoryOverLimit, TestFirstRequestOverLimit (rows 6 and 7): the over-the-limit guards;
///   - TestAfterTheSwitch (row 9): a tainted Chat, a Chat that fails and an exception after the fork was saved: the link stays on the original session;
///   - TestLateCompactionMovesNothing (Story 17.8, DW-730): a compacted turn that finishes after its timer saves the fork and leaves the link on the original
///     session, as does the timer's fallback, and the next accepted turn opens the original;
///   - TestFourIterations (row 10): the fourth request of a tool loop after a compaction stays under 100,000 tokens;
///   - TestCutRules, TestCheckRules, TestSeedRules, TestSettingsRules, TestSizes, TestUsageEstimate (row 11): the pure rules.
/// Every test removes the AI sessions it saved (and the links that name them), the Usage rows it wrote and the settings rows it put.
Class OcuTalon.Test.Bridge.Compaction Extends %UnitTest.TestCase
{

/// The config name of the shadow runner, which is the agent of its links.
Parameter AGENT = "ZzRunner";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

/// The chat agent of the runner, with the tools of the product.
Parameter CHAT = "OcuTalon.Agent.Chat";

/// The agent of the tool-loop test, whose tool answers a text of the asked length.
Parameter RESULTAGENT = "OcuTalon.Test.Tools.ZzResultAgent";

/// The gate's agent, whose tool zz_gate_read answers text from outside (the scenario gate-read) and so taints the turn.
Parameter GATEAGENT = "OcuTalon.Test.Bridge.ZzGateAgent";

/// The length of turn 1 in characters: about 42,500 tokens.
Parameter LONG = 170000;

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

/// The highest Usage id when the test began.
Property UsageMark As %Integer;

/// The snapshots of the settings rows that the test put (RunnerFixture.RememberDefault).
Property Saved As %List;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SessionMark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM OcuTalon_Bridge_Data.Usage")
	Do result.%Next()
	Set ..UsageMark = +result.%GetData(1)
	Set ..Saved = ""
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Kill ^||ZzReopenOnly
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..Saved)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.ConversationLink WHERE Agent = ?", ..#AGENT)
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(..SessionMark)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ID > ?", ..UsageMark)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE Summary = ?", $Parameter("OcuTalon.Test.Bridge.Conversation", "LATEMARK"))
	Quit $$$OK
}

/// Row 1: a flagged turn that continues its conversation is compacted through the guarded path. Turn 1 is long, turn 2 calls a tool, and
/// turn 3 is flagged: the summarizer is asked once, with the low effort and the transcript of turn 1; turn 3 is answered from the fork, whose
/// first message is turn 2's user message, with none of turn 1's filler; one compaction Usage row prices the summarizer's request.
Method TestGuardedCompaction()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Build(host, owner, "[[mock:recall-tell]] ", .two)
	Set old = ..LinkOf(owner)
	Set context = ..ContextOf(host, old)
	Set k = ##class(OcuTalon.Bridge.Compaction).Cut(context, .older)
	Do $$$AssertEquals(k, 4, "the cut keeps turn 2's four messages: the user's, the call, the result and the answer")
	Set systemChars = two.%Get(0).request.system.chars

	Set eventMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set request = ..Flagged("[[mock:recall-tell]] And a third thing.", owner)
	Do $$$AssertStatusOK(..Go(host, request, .reply, .entries, 0), "the flagged turn is answered")
	Set summaries = ..Summarizers(entries)
	Do $$$AssertEquals(summaries.%Size(), 1, "exactly one summarizer request is logged")
	Set summary = summaries.%Get(0)
	Do $$$AssertEquals(summary.selectedBy_"|"_summary.request.system.chars, "summarizer|"_$Length(##class(OcuTalon.Bridge.Compaction).Prompt()), "it is a summarizer request whose system text is the compaction prompt")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Effort(summary), "low", "asked with the low effort")
	Do $$$AssertTrue(summary.request.messages.%ToJSON() [ "FILLERONE", "whose transcript holds turn 1's text")
	Do $$$AssertEquals(summary.request.messages.%ToJSON() [ "reminder-list", 0, "and none of turn 2, which is kept whole")

	Set chat = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, request.ItemId)
	Do $$$AssertEquals(chat.%Size(), 1, "turn 3 made one model request")
	Set sent = chat.%Get(0)
	Set messages = ##class(OcuTalon.Test.Agent.RunnerFixture).Messages(sent)
	Do $$$AssertTrue($Piece(messages, $Char(1), 1) [ "user:[[mock:reminder-list]]", "it starts with turn 2's user message (the summary is in the system text)")
	Do $$$AssertEquals(sent.request.%ToJSON() [ "FILLERONE", 0, "and holds none of turn 1's filler")
	Do $$$AssertTrue(sent.request.system.chars - systemChars > 100, "the system text carries the summary: "_systemChars_" characters before, "_sent.request.system.chars_" now")
	Do $$$AssertEquals(reply.Text_"|"_reply.FailureText_"|"_reply.SessionRotated_"|"_reply.Tainted, "Noted.||0|0", "the reply is usable, and SessionRotated is 0: only Decide sets it")
	Set fork = reply.SessionId
	Do $$$AssertTrue((fork '= "") && (fork '= old) && (reply.SessionFrom = old), "the reply names the fork, and the original as the session it began from: "_old_" then "_fork)
	Do $$$AssertEquals(..LinkOf(owner), old, "the link still names the original session before Decide accepts the reply")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Runner).Accept(request, reply, ..#AGENT), "Decide accepts the reply")
	Do $$$AssertEquals(reply.SessionRotated, 1, "SessionRotated is 1")
	Do $$$AssertEquals(..LinkOf(owner), fork, "and the link names the fork")
	Do $$$AssertTrue(##class(%AI.Agent.Session).%ExistsId(old), "the original session is kept for the purge")
	Do $$$AssertEquals(..Warnings(eventMark), 0, "a compaction that worked logs no warning")

	Set rows = ##class(OcuTalon.Test.Agent.RunnerFixture).UsageIds("DecisionRef", request.DecisionRef)
	Do $$$AssertEquals(rows.%Size(), 2, "two Usage rows carry the DecisionRef: the summarizer's and the chat's")
	Set row = ..CompactionRow(request)
	If $IsObject(row) {
		Set input = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Tokens($Length(##class(OcuTalon.Bridge.Compaction).Prompt()) + ##class(OcuTalon.Bridge.Compaction).TranscriptChars(older))
		Set output = ##class(OcuTalon.Bridge.Adapter.StepBuffer).Tokens(##class(OcuTalon.Bridge.Compaction).SummaryChars(..ContextOf(host, fork)))
		Do $$$AssertEquals(row.Estimated_"|"_row.RequestCount_"|"_row.Kind_"|"_row.OwnerRef_"|"_row.Channel_"|"_row.ItemId, "1|1|turn|"_owner_"|system|"_request.ItemId, "the row is an estimate of one request, with the request's kind, owner, channel and item")
		Do $$$AssertEquals(row.InputTokens_"|"_row.LargestRequestTokens_"|"_row.OutputTokens, input_"|"_input_"|"_output, "its input is the prompt and the transcript, and its output the stored summary")
		Do $$$AssertTrue(output > 0, "the summary is not empty")
		Set cost = ##class(OcuTalon.Bridge.Data.Price).CostFor(row.Model, input, 0, 0, output, input, 1)
		Do $$$AssertTrue(cost '= "", "the model has a price: "_row.Model)
		Do $$$AssertEquals(row.CostUSD, cost, "and the cost is Price.CostFor of the estimate")
		Do $$$AssertEquals(+##class(OcuTalon.Bridge.Data.Usage).Totals(request.DecisionRef).rows, 2, "Usage.Totals counts both rows")
	}
}

/// DW-746 (AD-6, AD-8), the compacted case: HistoryCount counts the messages that the opened session held before the compaction, which is the whole stored history
/// of the original session (the compaction saves a fork and leaves the original as it was), and the turn after an accepted compaction opens the fork, whose
/// stored history (a summary-based export that holds fewer messages than the original did) is counted the same by GetContext(), the stored messages and the reply's
/// HistoryCount, so that a retry's seed is cut at the turn boundary of either.
Method TestHistoryCountAcrossCompaction()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Build(host, owner, "[[mock:recall-tell]] ", .two)
	Do $$$AssertStatusOK(..Go(host, ..Plain("[[mock:recall-tell]] One more thing.", owner), .extra), "turn 3 is answered, so that more is older than the last turn")
	Set old = ..LinkOf(owner)
	Set stored = "OcuTalon.Bridge.RequestSize"
	Set original = $ClassMethod(stored, "StoredMessages", old)
	Do $$$AssertEquals(..ContextOf(host, old).%Size(), original.%Size(), "the original session: GetContext() and the stored history count the same, "_original.%Size()_" messages")

	Set request = ..Flagged("[[mock:recall-tell]] And a fourth thing.", owner)
	Do $$$AssertStatusOK(..Go(host, request, .reply, .entries), "the flagged turn is answered and accepted")
	Do $$$AssertEquals(..Summarizers(entries).%Size(), 1, "it was compacted: one summarizer request")
	Do $$$AssertEquals($Select($IsObject(reply): reply.HistoryCount, 1: "none"), original.%Size(), "its HistoryCount is the original's whole count, taken before the compaction")
	Set fork = ..LinkOf(owner)
	Do $$$AssertTrue((fork '= "") && (fork '= old), "the link names the fork: "_fork)
	Do $$$AssertEquals($ClassMethod(stored, "StoredMessages", old, reply.HistoryCount).%ToJSON(), original.%ToJSON(), "and the first HistoryCount stored messages of the original are all it held")

	Set forked = $ClassMethod(stored, "StoredMessages", fork)
	Do $$$AssertTrue((forked.%Size() > 0) && (forked.%Size() < original.%Size() + 2), "the fork stores a history that the compaction shortened: "_forked.%Size()_" messages against the original's "_original.%Size()_" and the turn's 2")
	Do $$$AssertEquals(..ContextOf(host, fork).%Size(), forked.%Size(), "GetContext() of the fork and the stored history count the same messages")
	Set next = ..Plain("[[mock:recall-tell]] And what is next?", owner)
	Do $$$AssertStatusOK(..Go(host, next, .nextReply, .nextEntries, 0), "the next turn is answered")
	Do $$$AssertEquals($Select($IsObject(nextReply): nextReply.HistoryCount_"|"_nextReply.SessionFrom, 1: "none"), forked.%Size()_"|"_fork, "its HistoryCount is the fork's stored count, and it began from the fork")
	Do $$$AssertEquals($ClassMethod(stored, "StoredMessages", fork, nextReply.HistoryCount).%ToJSON(), forked.%ToJSON(), "and the first HistoryCount stored messages are what the fork held before the turn")
}

/// Row 2: an owner with one saved turn has nothing older to summarize, so a flagged turn within the limit is sent as it is.
Method TestNothingOlder()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(..Go(host, ..Plain("[[mock:recall-tell]] My build server is ORION-7.", owner), .first, .e1))
	Set old = ..LinkOf(owner)
	Set eventMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set request = ..Flagged("[[mock:recall-tell]] And another thing.", owner)
	Do $$$AssertStatusOK(..Go(host, request, .reply, .entries), "the flagged turn is answered")
	Do $$$AssertEquals(..Summarizers(entries).%Size(), 0, "no summarizer request is logged")
	Do $$$AssertTrue($IsObject(..CompactionRow(request)) = 0, "and no compaction row is written")
	Do $$$AssertEquals(..LinkOf(owner), old, "the link is unchanged")
	Set chat = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, request.ItemId)
	Do $$$AssertEquals(chat.%Size(), 1, "one model request")
	Do $$$AssertEquals($Length(##class(OcuTalon.Test.Agent.RunnerFixture).Messages(chat.%Get(0)), $Char(1)), 3, "it carries the first exchange and the input, as it is")
	Do $$$AssertEquals(reply.Text_"|"_reply.SessionRotated, "Noted.|0", "the reply is usable and not rotated")
	Do $$$AssertEquals(..Warnings(eventMark), 0, "no warning")
}

/// Row 3: a summarizer that answers off the schema (AD-20) makes ForkAndSummarize throw. The turn runs in a new AI session seeded with the
/// stored texts, saved and linked after the Chat; one compaction row with no output; one warning; never a FailureText.
Method TestSummarizerOffSchema()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Build(host, owner, "[[mock:recall-tell]] [[mock:summary-off-schema]] ")
	Set old = ..LinkOf(owner)
	Set sessions = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set eventMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set request = ..Flagged("[[mock:recall-tell]] And a third thing.", owner)
	Do $$$AssertStatusOK(..Go(host, request, .reply, .entries), "the flagged turn is answered")
	Do $$$AssertEquals(..Summarizers(entries).%Size(), 1, "one summarizer request is logged")
	Do ..AssertSeeded(host, owner, request, reply, entries, old, eventMark, "step: the summarizer's request")
	Do ..AssertThrownRow(request)
}

/// Row 4: a fork whose history starts at a tool result is refused (Compaction.Check), never saved or linked. The seam (ZzCutAdapter) asks for
/// that cut.
Method TestCheckFails()
{
	If ..Guard() Quit
	Set host = ##class(OcuTalon.Test.Bridge.Runner).NewRunner(..#CHAT, "low", "", ..#AGENT, "OcuTalon.Test.Bridge.ZzCutRunner")
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Build(host, owner, "[[mock:recall-tell]] ")
	Set old = ..LinkOf(owner)
	Set sessions = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set eventMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set request = ..Flagged("[[mock:recall-tell]] And a third thing.", owner)
	Do $$$AssertStatusOK(..Go(host, request, .reply, .entries), "the flagged turn is answered")
	Do $$$AssertEquals(..Summarizers(entries).%Size(), 1, "the summarizer was asked once")
	Do ..AssertSeeded(host, owner, request, reply, entries, old, eventMark, "step: the check of the fork")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark() - sessions, 1, "one AI session was saved: the seeded one, and never the fork")
}

/// Row 4 (reopen): a fork that is saved but cannot be opened again is never linked. The turn runs in the seeded session, the original stays
/// linked until the Chat completes, and the fork stays saved and unlinked for the purge. The seam (ZzReopenAdapter) refuses the reopen.
Method TestReopenFails()
{
	If ..Guard() Quit
	Set host = ##class(OcuTalon.Test.Bridge.Runner).NewRunner(..#CHAT, "low", "", ..#AGENT, "OcuTalon.Test.Bridge.ZzReopenRunner")
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Build(host, owner, "[[mock:recall-tell]] ")
	Set old = ..LinkOf(owner)
	Set ^||ZzReopenOnly = old
	Set sessions = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set eventMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set request = ..Flagged("[[mock:recall-tell]] And a third thing.", owner)
	Do $$$AssertStatusOK(..Go(host, request, .reply, .entries), "the flagged turn is answered")
	Do $$$AssertEquals(..Summarizers(entries).%Size(), 1, "the summarizer was asked once")
	Do ..AssertSeeded(host, owner, request, reply, entries, old, eventMark, "step: opening the fork again")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark() - sessions, 2, "two AI sessions were saved: the fork, which stays unlinked, and the seeded one")
}

/// Row 5: a rate-limited summarizer (HTTP 429) is asked exactly once, because the summarizer's retry block allows no retry.
Method TestSummarizerRateLimited()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Build(host, owner, "[[mock:recall-tell]] [[mock:summary-rate-limited]] ")
	Set old = ..LinkOf(owner)
	Set eventMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set request = ..Flagged("[[mock:recall-tell]] And a third thing.", owner)
	Do $$$AssertStatusOK(..Go(host, request, .reply, .entries), "the flagged turn is answered")
	Do $$$AssertEquals(..Summarizers(entries).%Size(), 1, "exactly one summarizer request is logged: no retry")
	Do ..AssertSeeded(host, owner, request, reply, entries, old, eventMark, "step: the summarizer's request")
	Do ..AssertThrownRow(request)
}

/// Row 6: a summarizer request that, by estimate, would pass the request-size limit is not made (AD-8, NFR-3): no call, no row, the seed.
Method TestSummarizerOverLimit()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Build(host, owner, "[[mock:recall-tell]] ")
	Set old = ..LinkOf(owner)
	Do ..PutLimit(41000)
	Set eventMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set request = ..Flagged("[[mock:recall-tell]] And a third thing.", owner)
	Do $$$AssertStatusOK(..Go(host, request, .reply, .entries), "the flagged turn is answered")
	Do $$$AssertEquals(..Summarizers(entries).%Size(), 0, "no summarizer request is logged")
	Do $$$AssertEquals($IsObject(..CompactionRow(request)), 0, "and no compaction row is written")
	Do ..AssertSeeded(host, owner, request, reply, entries, old, eventMark, "step: the size of the summarizer's request")
	Set chat = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, request.ItemId)
	For i = 0:1:chat.%Size() - 1 {
		Do $$$AssertTrue(..RequestTokens(chat.%Get(i), ..#CHAT) '> 41000, "every logged request is at most 41,000 tokens")
	}
}

/// Row 7 (DW-125): a stored history that alone passes the limit, with nothing older, is replaced by a seed with each side cut at 2,000
/// characters, so that no request goes over the limit.
Method TestHistoryOverLimit()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(..Go(host, ..Plain("[[mock:recall-tell]] "_..Filler("FILLERONE", ..#LONG), owner), .first, .e1), "turn 1 is answered")
	Set old = ..LinkOf(owner)
	Do ..PutLimit(41000)
	Set eventMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set request = ..Flagged("[[mock:recall-tell]] A short question.", owner)
	Do $$$AssertStatusOK(..Go(host, request, .reply, .entries), "the short flagged turn is answered")
	Do $$$AssertEquals(..Summarizers(entries).%Size(), 0, "no summarizer request: there is nothing older")
	Do ..AssertSeeded(host, owner, request, reply, entries, old, eventMark, "step: the size of the request")
	Set chat = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, request.ItemId)
	For i = 0:1:chat.%Size() - 1 {
		Do $$$AssertTrue(..RequestTokens(chat.%Get(i), ..#CHAT) '> 41000, "every logged request is at most 41,000 tokens")
	}
}

/// Row 7 (the fork): a fork whose first request would still pass the limit is never linked. Turn 1 is short and turn 2, the kept turn, is
/// long: the summarizer's request fits, the fork that keeps turn 2 does not, so the turn is seeded and no request passes the limit.
Method TestFirstRequestOverLimit()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK(..Go(host, ..Plain("[[mock:recall-tell]] "_..Filler("FILLERONE", 3000), owner), .first, .e1), "turn 1 is answered")
	Do $$$AssertStatusOK(..Go(host, ..Plain("[[mock:recall-tell]] "_..Filler("FILLERTWO", ..#LONG), owner), .second, .e2), "turn 2 is answered")
	Set old = ..LinkOf(owner)
	Do ..PutLimit(41000)
	Set sessions = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set eventMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set request = ..Flagged("[[mock:recall-tell]] A short question.", owner)
	Do $$$AssertStatusOK(..Go(host, request, .reply, .entries), "the flagged turn is answered")
	Do $$$AssertEquals(..Summarizers(entries).%Size(), 1, "the summarizer was asked once: its request fits")
	Do ..AssertSeeded(host, owner, request, reply, entries, old, eventMark, "step: the size of the first request")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark() - sessions, 1, "one AI session was saved: the seeded one, and never the fork")
	Set chat = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, request.ItemId)
	For i = 0:1:chat.%Size() - 1 {
		Do $$$AssertTrue(..RequestTokens(chat.%Get(i), ..#CHAT) '> 41000, "every logged request is at most 41,000 tokens")
	}
}

/// Row 8: Compact 1 on a request that is not a turn that continues its conversation compacts nothing: an untrusted turn, a fresh turn, a
/// decide request and an owner's first turn.
Method TestNotCompactable()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Build(host, owner, "[[mock:recall-tell]] ")
	Set old = ..LinkOf(owner)
	Set stranger = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set cases = $ListBuild($ListBuild("an untrusted turn", owner, "turn", "untrusted", ""), $ListBuild("a fresh turn", owner, "turn", "user", "fresh"), $ListBuild("a decide request", owner, "decide", "user", ""), $ListBuild("an owner's first turn", stranger, "turn", "user", ""))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set request = ##class(OcuTalon.Test.Bridge.Conversation).NewTurn("[[mock:recall-tell]] A short question.", $List(case, 2), , $List(case, 3), $List(case, 4), $List(case, 5), $Select($List(case, 5) = "fresh": "A recap of the earlier turns.", 1: ""))
		Set request.Compact = 1
		Do $$$AssertStatusOK(..Go(host, request, .reply, .entries), $List(case, 1)_" is answered")
		Do $$$AssertEquals(..Summarizers(entries).%Size(), 0, $List(case, 1)_" makes no summarizer request")
		Do $$$AssertEquals($IsObject(..CompactionRow(request)), 0, "and no compaction row")
	}
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.Usage).Totals("none").rows, 0, "(control: the totals of a ref with no row are empty)")
	Do $$$AssertTrue(##class(%AI.Agent.Session).%ExistsId(old), "the owner's session is still there")
}

/// Row 9: after the switch the fork is saved, and the link is not touched (Story 17.8). A tainted Chat saves nothing more, a Chat that fails gives the usual
/// failure reply, and an exception leaves the lock free; in each the link still names the original session, the reply names no session and has SessionRotated
/// 0, and the fork, which nothing names, is the newest saved session and holds none of the turn.
Method TestAfterTheSwitch()
{
	If ..Guard() Quit
	Set labels = $ListBuild("tainted", "failed", "exception")
	For which = 1:1:3 {
		Set label = $List(labels, which)
		Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
		If which = 1 {
			Set host = ##class(OcuTalon.Test.Bridge.Runner).NewRunner(..#GATEAGENT, "low")
			Set text = "[[mock:gate-read]] Read the partner's text."
		} ElseIf which = 2 {
			Set host = ..NewHost()
			Set text = "[[mock:provider-error]] A question."
		} Else {
			Set host = ..NewHost()
			Set text = "[[mock:recall-tell]] A question."
		}
		Do ..BuildPlain(host, owner)
		If which = 3 Set host = ##class(OcuTalon.Test.Bridge.Runner).NewRunner(..#CHAT, "low", "", ..#AGENT, "OcuTalon.Test.Bridge.ZzThrowRunner")
		Set old = ..LinkOf(owner)
		Set sessions = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
		Set request = ..Flagged(text, owner)
		Set sc = ..Go(host, request, .reply, .entries)
		Set fork = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
		Do $$$AssertEquals(..LinkOf(owner), old, label_": the link still names the original session")
		Do $$$AssertEquals(fork - sessions, 1, label_": the fork was saved, and nothing names it: "_fork)
		Do $$$AssertEquals(..Summarizers(entries).%Size(), 1, label_": the summarizer was asked once")
		Do $$$AssertTrue($IsObject(..CompactionRow(request)), label_": the compaction row was written")
		Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.Conversation).LockFree(owner, ..#AGENT), 1, label_": the lock is free")
		If which = 1 {
			Do $$$AssertStatusOK(sc, label_": answered")
			Do $$$AssertEquals(reply.Tainted_"|"_reply.SessionRotated_"|"_reply.SessionId, "1|0|", label_": the reply is tainted, not rotated, and names no session")
			Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionExport(fork) [ request.ItemId, 0, label_": the tainted turn is not in the fork")
		} ElseIf which = 2 {
			Do $$$AssertStatusOK(sc, label_": answered")
			Do $$$AssertTrue(reply.FailureText [ "ProviderError", label_": the failure reply of the provider: "_$Extract(reply.FailureText, 1, 200))
			Do $$$AssertEquals(reply.Text_"|"_reply.SessionRotated_"|"_reply.SessionId, "|0|", label_": no text, SessionRotated 0, and no session named")
			Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).SessionExport(fork) [ request.ItemId, 0, label_": the failed turn is not in the fork")
		} Else {
			Do $$$AssertStatusNotOK(sc, label_": an error status, as for any exception")
		}
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.ConversationLink WHERE Agent = ?", ..#AGENT)
	}
}

/// DW-730 (AD-6, AD-8), the compacted case, in process: a flagged turn that finishes after its timer saves its fork and names it, but Decide never accepts the
/// reply, so the link names the original session S1 after the turn and after the timer's fallback, and the owner's next accepted turn opens S1 and not the
/// fork.
Method TestLateCompactionMovesNothing()
{
	If ..Guard() Quit
	Set host = ..NewHost()
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Build(host, owner, "[[mock:recall-tell]] ", .two)
	Set s1 = ..LinkOf(owner)
	Set request = ..Flagged("[[mock:recall-tell]] And a third thing.", owner)
	Do $$$AssertStatusOK(..Go(host, request, .reply, .entries, 0), "the flagged turn finishes late")
	Do $$$AssertEquals(..Summarizers(entries).%Size(), 1, "it was compacted: one summarizer request")
	Do $$$AssertTrue($IsObject(reply) && (reply.SessionId '= "") && (reply.SessionId '= s1) && (reply.SessionFrom = s1), "its reply names the fork F, and S1 as the session it began from")
	Do $$$AssertEquals(..LinkOf(owner), s1, "the link names S1")
	Set conversation = "OcuTalon.Test.Bridge.Conversation"
	Do $$$AssertStatusOK($ClassMethod(conversation, "TimerFallback", request, request.DecisionRef, .fallback), "the timer's fallback is recorded")
	Do $$$AssertEquals($Select($IsObject(fallback): fallback.Fallback_"|"_fallback.FallbackReason_"|"_fallback.SessionRotated, 1: "none"), "1|timeout|0", "the timer's fallback is recorded with SessionRotated 0")
	Do $$$AssertEquals(..LinkOf(owner), s1, "the link still names S1 after the timer's fallback")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Data.Decision).RefIndexExists(request.DecisionRef), 1, "(the decision is recorded)")

	Set next = ..Plain("[[mock:recall-tell]] And what is next?", owner)
	Do $$$AssertStatusOK(..Go(host, next, .nextReply, .nextEntries), "the owner's next turn is answered and accepted")
	Set chat = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(nextEntries, next.ItemId)
	Do $$$AssertEquals(chat.%Size(), 1, "with one model request")
	If chat.%Size() = 1 {
		Set messages = ##class(OcuTalon.Test.Agent.RunnerFixture).Messages(chat.%Get(0))
		Do $$$AssertTrue(messages [ "FILLERONE", "which carries S1's whole history, turn 1's filler included, as the fork's summary replaced it")
		Do $$$AssertEquals(messages [ request.ItemId, 0, "and nothing of the late turn")
	}
	Do $$$AssertEquals(..LinkOf(owner), s1, "and the link still names S1")
}

/// Row 10 (DW-130): after a compaction the four requests of a tool loop whose results are 40,000 characters each stay under 100,000 tokens,
/// and the first is at most 40,000. Without compaction the fourth request of the same conversation passes 100,000.
Method TestFourIterations()
{
	If ..Guard() Quit
	Set tokens = ""
	For compact = 1, 0 {
		Set host = ##class(OcuTalon.Test.Bridge.Runner).NewRunner(..#RESULTAGENT, "low")
		Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
		Do $$$AssertStatusOK(..Go(host, ..Plain("[[mock:recall-tell]] "_..Filler("FILLERONE", ..#LONG), owner), .first, .e1), "turn 1 is answered")
		Do $$$AssertStatusOK(..Go(host, ..Plain("[[mock:recall-tell]] "_..Filler("FILLERTWO", 140000), owner), .second, .e2), "turn 2 is answered")
		Set request = ..Plain("[[mock:compaction-loop]] Read the long results.", owner)
		Set request.Compact = compact
		Do $$$AssertStatusOK(..Go(host, request, .reply, .entries), "turn 3 is answered, compact "_compact)
		Set chat = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, request.ItemId)
		Do $$$AssertEquals(chat.%Size(), 4, "turn 3 made four model requests, compact "_compact_" ("_chat.%Size()_" logged, text '"_$Extract(reply.Text, 1, 80)_"')")
		Do $$$AssertEquals(reply.FailureText, "", "with no failure, compact "_compact_": "_$Extract(reply.FailureText, 1, 300))
		If chat.%Size() = 4 {
			If compact {
				Do $$$AssertTrue(..RequestTokens(chat.%Get(0), ..#RESULTAGENT) '> 40000, "the first request is at most 40,000 tokens: "_..RequestTokens(chat.%Get(0), ..#RESULTAGENT))
				For i = 0:1:3 {
					Do $$$AssertTrue(..RequestTokens(chat.%Get(i), ..#RESULTAGENT) < 100000, "request "_(i + 1)_" is under 100,000 tokens: "_..RequestTokens(chat.%Get(i), ..#RESULTAGENT))
				}
			} Else {
				Do $$$AssertTrue(..RequestTokens(chat.%Get(3), ..#RESULTAGENT) '< 100000, "(control) without compaction the fourth request passes 100,000 tokens: "_..RequestTokens(chat.%Get(3), ..#RESULTAGENT))
			}
		}
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.ConversationLink WHERE Agent = ?", ..#AGENT)
	}
}

/// Row 11: Cut, the older messages and the size of the transcript.
Method TestCutRules()
{
	Set compaction = "OcuTalon.Bridge.Compaction"
	Set tool = [{"role":"user","content":"u2"},{"role":"assistant","content":null,"tool_calls":[{"id":"t1","name":"x","arguments":"{}"}]},{"role":"tool","tool_call_id":"t1","content":"r"},{"role":"assistant","content":"a2"}]
	Set context = [{"role":"system","content":"s"},{"role":"user","content":"u1"},{"role":"assistant","content":"a1"}]
	For i = 0:1:tool.%Size() - 1 {
		Do context.%Push(tool.%Get(i))
	}
	Set k = $ClassMethod(compaction, "Cut", context, .older)
	Do $$$AssertEquals(k_"|"_older.%Size(), "4|3", "the last user turn is kept whole: k 4, and the system message, turn 1's two messages are older")
	Do $$$AssertEquals(older.%Get(0).role_older.%Get(2).role, "systemassistant", "older holds the messages before the cut, in order")
	Do $$$AssertEquals($ClassMethod(compaction, "TranscriptChars", older), $Length(older.%ToJSON()), "TranscriptChars is the length of their JSON")
	Set k = $ClassMethod(compaction, "Cut", [{"role":"user","content":"u1"},{"role":"assistant","content":"a1"}], .older)
	Do $$$AssertEquals(k_"|"_older.%Size(), "0|0", "nothing older: k 0 and no older message")
	Set k = $ClassMethod(compaction, "Cut", [{"role":"system","content":"s"},{"role":"user","content":"u1"},{"role":"assistant","content":"a1"}], .older)
	Do $$$AssertEquals(k_"|"_older.%Size(), "0|0", "only a system message before the last user turn: nothing to summarize")
	Set k = $ClassMethod(compaction, "Cut", [{"role":"assistant","content":"a1"}], .older)
	Do $$$AssertEquals(k, 0, "no user message: 0")
	Set k = $ClassMethod(compaction, "Cut", [{"role":"user","content":"u1"},{"role":"assistant","content":"a1"},{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"r"}]}], .older)
	Do $$$AssertEquals(k, 0, "a user message made of tool_result blocks is a tool result, not a user turn")
	Do $$$AssertEquals($ClassMethod(compaction, "Cut", "", .older)_"|"_older.%Size(), "0|0", "something that is not an array: 0")
	Do $$$AssertEquals($ClassMethod(compaction, "TranscriptChars", ""), 0, "TranscriptChars of nothing is 0")
}

/// Row 11: the check of a fork.
Method TestCheckRules()
{
	Set compaction = "OcuTalon.Bridge.Compaction"
	Set good = [{"role":"system","content":"summary"},{"role":"system","content":"log"},{"role":"user","content":"u"},{"role":"assistant","content":null,"tool_calls":[{"id":"t1","name":"x","arguments":"{}"}]},{"role":"tool","tool_call_id":"t1","content":"r"},{"role":"assistant","content":"a"}]
	Do $$$AssertEquals($ClassMethod(compaction, "Check", good), 1, "a fork that starts with a user message and keeps its results after their calls passes")
	Do $$$AssertEquals($ClassMethod(compaction, "Check", [{"role":"user","content":"u"},{"role":"assistant","content":"a"}]), 1, "so does one with no system message")
	Do $$$AssertEquals($ClassMethod(compaction, "Check", [{"role":"system","content":"summary"},{"role":"tool","tool_call_id":"t1","content":"r"},{"role":"assistant","content":"a"}]), 0, "a tool result first fails")
	Do $$$AssertEquals($ClassMethod(compaction, "Check", [{"role":"assistant","content":"a"},{"role":"user","content":"u"}]), 0, "an assistant message first fails")
	Do $$$AssertEquals($ClassMethod(compaction, "Check", [{"role":"user","content":"u"},{"role":"tool","tool_call_id":"t1","content":"r"},{"role":"assistant","content":null,"tool_calls":[{"id":"t1","name":"x","arguments":"{}"}]}]), 0, "a result before its call fails")
	Do $$$AssertEquals($ClassMethod(compaction, "Check", [{"role":"user","content":"u"},{"role":"assistant","content":null,"tool_calls":[{"id":"t1","name":"x","arguments":"{}"}]},{"role":"tool","tool_call_id":"t2","content":"r"}]), 0, "an orphan result (no call has its id) fails")
	Do $$$AssertEquals($ClassMethod(compaction, "Check", [{"role":"user","content":"u"},{"role":"assistant","content":null,"tool_calls":[{"id":"t1","name":"x","arguments":"{}"}]},{"role":"tool","content":"r"}]), 0, "a result with no call id fails")
	Do $$$AssertEquals($ClassMethod(compaction, "Check", [{"role":"user","content":"u"},{"role":"assistant","content":[{"type":"tool_use","name":"x","input":{}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"r"}]}]), 0, "a tool_use block with no id answers no result, so the result fails")
	Do $$$AssertEquals($ClassMethod(compaction, "Check", [{"role":"user","content":"u"},{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"x","input":{}}]},{"role":"user","content":[{"type":"tool_result","content":"r"}]}]), 0, "a tool_result block with no tool_use_id fails")
	Do $$$AssertEquals($ClassMethod(compaction, "Check", [{"role":"system","content":"summary"}]), 0, "a history of system messages only fails")
	Do $$$AssertEquals($ClassMethod(compaction, "Check", []), 0, "an empty history fails")
	Do $$$AssertEquals($ClassMethod(compaction, "Check", ""), 0, "something that is not an array fails")
}

/// Row 11: the seed of the fallback.
Method TestSeedRules()
{
	Set compaction = "OcuTalon.Bridge.Compaction"
	Set head = $Parameter(compaction, "SEEDHEAD")
	Set part = $Parameter(compaction, "SEEDPART")
	Set max = $Parameter(compaction, "SEEDCHARS")
	Do $$$AssertEquals($ClassMethod(compaction, "Seed", []), "", "the seed of no texts is empty")
	Do $$$AssertEquals($ClassMethod(compaction, "Seed", [{"role":"system","content":"s"}]), "", "and so is that of system messages only")
	Do $$$AssertEquals($ClassMethod(compaction, "Seed", ""), "", "and that of something that is not an array")
	Set context = [{"role":"system","content":"a summary of tools"},{"role":"user","content":"What is up?"},{"role":"assistant","content":null,"tool_calls":[{"id":"t1","name":"secret_tool","arguments":"{}"}]},{"role":"tool","tool_call_id":"t1","content":"TOOLRESULTTEXT"},{"role":"assistant","content":"All is well."}]
	Set seed = $ClassMethod(compaction, "Seed", context)
	Do $$$AssertEquals(seed, head_$Char(10)_"User: What is up?"_$Char(10)_"Assistant: All is well.", "the head line, then a line for each user and assistant text, in order")
	Do $$$AssertEquals((seed [ "TOOLRESULTTEXT") + (seed [ "secret_tool") + (seed [ "summary"), 0, "no tool call, tool result or system text is quoted")
	// a text over the part limit is cut
	Set long = $Translate($Justify("", part + 500), " ", "x")
	Set seed = $ClassMethod(compaction, "Seed", [{"role":"user","content":(long)},{"role":"assistant","content":(long)}])
	Set lines = $Length(seed, $Char(10))
	Do $$$AssertEquals(lines, 3, "two texts are two lines after the head")
	Do $$$AssertEquals($Length($Piece(seed, $Char(10), 2)) _ "|" _ $Length($Piece(seed, $Char(10), 3)), ($Length("User: ") + part) _ "|" _ ($Length("Assistant: ") + part), "each side is cut to the part limit")
	Do $$$AssertEquals($Extract($Piece(seed, $Char(10), 2), $Length($Piece(seed, $Char(10), 2))), $Char(8230), "and ends with the cut mark")
	// the newest exchanges are kept, the oldest dropped
	Set context = []
	For i = 1:1:25 {
		Do context.%Push({"role":"user","content":("question "_i)})
		Do context.%Push({"role":"assistant","content":("answer "_i)})
	}
	Set seed = $ClassMethod(compaction, "Seed", context)
	Do $$$AssertEquals($Piece(seed, $Char(10), 2), "User: question 6", "of 25 exchanges the newest 20 are kept: the first is 6")
	Do $$$AssertEquals($Piece(seed, $Char(10), $Length(seed, $Char(10))), "Assistant: answer 25", "and the last is the newest")
	// the whole seed is bounded, and the oldest lines go first
	Set context = []
	For i = 1:1:25 {
		Do context.%Push({"role":"user","content":($Translate($Justify("", part), " ", "u")_i)})
		Do context.%Push({"role":"assistant","content":($Translate($Justify("", part), " ", "a")_i)})
	}
	Set seed = $ClassMethod(compaction, "Seed", context)
	Do $$$AssertTrue($Length(seed) '> max, "a seed of long texts is at most "_max_" characters: "_$Length(seed))
	Do $$$AssertTrue($Length(seed) > max - 2 * part, "and it keeps as many of the newest lines as fit")
	Do $$$AssertEquals($Extract($Piece(seed, $Char(10), $Length(seed, $Char(10))), 1, 11), "Assistant: ", "ending with a reply")
	Do $$$AssertTrue($Length(seed, $Char(10)) - 1 < 40, "and the oldest lines are left out: fewer than the 40 lines of 20 exchanges")
}

/// Row 11: the settings of the summarizer.
Method TestSettingsRules()
{
	Set compaction = "OcuTalon.Bridge.Compaction"
	Set settings = {"model_provider": "anthropic", "api_key": "KEYPLACEHOLDER", "base_url": "http://mock:8080/v1/", "http_config": {"custom_headers": {"x-ocutalon-mockkey": "chat"}, "request_timeout_secs": 25, "retry": {"max_retries": 1, "attempt_timeout_secs": 25}}, "extra_config": {"other": 1}}
	Set before = settings.%ToJSON()
	Set out = $ClassMethod(compaction, "SummarizerSettings", settings)
	Do $$$AssertEquals(settings.%ToJSON(), before, "the settings that are passed in are not changed")
	Do $$$AssertEquals(out."extra_config"."output_config".effort, "low", "extra_config.output_config.effort is low")
	Do $$$AssertEquals(out."extra_config".other, 1, "the other keys of extra_config stay")
	Do $$$AssertEquals(out."http_config"."request_timeout_secs", 20, "the request timeout is 20 seconds")
	Do $$$AssertEquals(out."http_config".retry.%ToJSON(), "{""max_retries"":0,""attempt_timeout_secs"":20,""initial_backoff_ms"":500,""max_backoff_ms"":2000}", "the retry block is whole, with no retry")
	Do $$$AssertEquals(out."http_config"."custom_headers"."x-ocutalon-mockkey"_"|"_out."api_key"_"|"_out."base_url"_"|"_out."model_provider", "chat|KEYPLACEHOLDER|http://mock:8080/v1/|anthropic", "the runner's other settings are kept")
	For key = "temperature", "top_p", "top_k" {
		Do $$$AssertEquals(out.%IsDefined(key) + out."extra_config".%IsDefined(key) + out."http_config".%IsDefined(key), 0, "no sampling key "_key)
	}
	Set bare = $ClassMethod(compaction, "SummarizerSettings", {"api_key": "K"})
	Do $$$AssertEquals(bare."extra_config"."output_config".effort_"|"_bare."http_config".retry."max_retries"_"|"_bare."api_key", "low|0|K", "settings with no http_config or extra_config get both blocks")
}

/// Row 11: the sizes that the Usage row is estimated from.
Method TestSizes()
{
	Set compaction = "OcuTalon.Bridge.Compaction"
	Set context = [{"role":"system","content":"abc"},{"role":"system","content":"defg"},{"role":"user","content":"hijklm"},{"role":"system","content":"zzzzzzzz"}]
	Do $$$AssertEquals($ClassMethod(compaction, "SummaryChars", context), 7, "SummaryChars adds the system messages at the head")
	Do $$$AssertEquals($ClassMethod(compaction, "SummaryChars", [{"role":"user","content":"x"}]), 0, "and is 0 without any")
	Do $$$AssertEquals($ClassMethod(compaction, "SummaryChars", ""), 0, "or for something that is not an array")
}

/// The Usage row of a summarizer request (Usage.FromEstimate): an estimate priced at the model, with the request's identity.
Method TestUsageEstimate()
{
	Set request = ##class(OcuTalon.Test.Bridge.Conversation).NewTurn("Hello.", "owner-estimate", .ref)
	Set model = $Parameter("OcuTalon.Agent.Chat", "MODEL")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Data.Usage).FromEstimate(request, model, 4001, 0, .row), "a row is built")
	Do $$$AssertEquals(row.Agent_"|"_row.Estimated_"|"_row.RequestCount_"|"_row.InputTokens_"|"_row.OutputTokens_"|"_row.LargestRequestTokens_"|"_row.CacheReadTokens_"|"_row.CacheWriteTokens, "compaction|1|1|1001|0|1001|0|0", "an estimate of one request, 4,001 characters in (1,001 tokens) and none out")
	Do $$$AssertEquals(row.DecisionRef_"|"_row.ItemId_"|"_row.Kind_"|"_row.OwnerRef_"|"_row.Channel_"|"_row.Model, request.DecisionRef_"|"_ref_"|turn|owner-estimate|system|"_model, "with the identity of the request")
	Do $$$AssertEquals(row.CostUSD, ##class(OcuTalon.Bridge.Data.Price).CostFor(model, 1001, 0, 0, 0, 1001, 1), "priced by Price.CostFor")
	Do $$$AssertTrue(row.RecordedAt '= "", "with the time it was recorded")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Data.Usage).FromEstimate(request, "no-such-model", 400, 80, .unpriced), "a row for a model with no price is built")
	Do $$$AssertEquals(unpriced.CostUSD_"|"_unpriced.OutputTokens, "|20", "its cost is empty, never 0, and its output counts 80 characters")
	Do $$$AssertStatusNotOK(##class(OcuTalon.Bridge.Data.Usage).FromEstimate("", model, 1, 1, .none), "no request, no row")
}

/// --- helpers ---
/// Builds the conversation of the owner: turn 1 (the text starts with the prefix and holds about 170,000 characters of filler) and turn 2 (a turn
/// that calls a tool). two is the log of turn 2's requests, for the size of the system text.
Method Build(host As OcuTalon.Bridge.Operation.AgentRunner, owner As %String, prefix As %String, Output two As %DynamicArray)
{
	Do $$$AssertStatusOK(..Go(host, ..Plain(prefix_..Filler("FILLERONE", ..#LONG), owner), .first, .e1), "turn 1 is answered")
	Do $$$AssertEquals(first.FailureText, "", "turn 1 has no failure: "_first.FailureText)
	Do ..SecondTurn(host, owner, .two)
}

/// Turn 2 of a conversation: a short turn that calls a tool (the scenario reminder-list).
Method SecondTurn(host As OcuTalon.Bridge.Operation.AgentRunner, owner As %String, Output two As %DynamicArray)
{
	Set request = ..Plain("[[mock:reminder-list]] List my reminders.", owner)
	Do $$$AssertStatusOK(..Go(host, request, .second, .entries), "turn 2 is answered")
	Set two = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, request.ItemId)
}

/// The same conversation with a short turn 1 (the gate and the failure tests need a history, not a long one): a long turn 1 on the gate's
/// agent or a failing chat is not the point.
Method BuildPlain(host As OcuTalon.Bridge.Operation.AgentRunner, owner As %String)
{
	Do $$$AssertStatusOK(..Go(host, ..Plain("[[mock:recall-tell]] "_..Filler("FILLERONE", 3000), owner), .first, .e1), "turn 1 is answered")
	Do $$$AssertStatusOK(..Go(host, ..Plain("[[mock:recall-tell]] The second thing.", owner), .second, .e2), "turn 2 is answered")
}

/// The asserts of a seeded fallback (rows 3 to 7): the turn runs in a new AI session whose first request is the seed and then the input;
/// the reply is usable and rotated, and the new session is saved and linked; the original is kept; one warning that names the step;
/// never a FailureText.
Method AssertSeeded(host As OcuTalon.Bridge.Operation.AgentRunner, owner As %String, request As OcuTalon.Bridge.Msg.Request, reply As OcuTalon.Bridge.Msg.Reply, entries As %DynamicArray, old As %String, eventMark As %Integer, needle As %String)
{
	Set chat = ##class(OcuTalon.Test.Agent.RunnerFixture).FindRequests(entries, request.ItemId)
	Do $$$AssertEquals(chat.%Size(), 1, "the seeded turn made one model request")
	If chat.%Size() '= 1 Quit
	Set messages = ##class(OcuTalon.Test.Agent.RunnerFixture).Messages(chat.%Get(0))
	Do $$$AssertEquals($Length(messages, $Char(1)), 1, "whose only message is the seed and the input")
	Set text = $Piece(messages, ":", 2, 100000)
	Set seedHead = $Parameter("OcuTalon.Bridge.Compaction", "SEEDHEAD")
	Do $$$AssertEquals($Extract(text, 1, $Length(seedHead)), seedHead, "it starts with the head line of the seed")
	Do $$$AssertTrue(text [ "User: [[mock:recall-tell]]", "the seed quotes the first turn, cut at the part limit")
	Do $$$AssertTrue($Length($Piece(text, $Char(10), 2)) '> $Length("User: ") + $Parameter("OcuTalon.Bridge.Compaction", "SEEDPART"), "and cut: the first user line is at most the part limit")
	Do $$$AssertTrue($Find(text, request.Input) > $Length(seedHead), "and the input of the turn follows it")
	Do $$$AssertEquals(reply.Text_"|"_reply.FailureText_"|"_reply.SessionRotated_"|"_reply.Tainted, "Noted.||1|0", "the reply is usable, with no FailureText, and SessionRotated is 1")
	Set new = ..LinkOf(owner)
	Do $$$AssertTrue((new '= "") && (new '= old), "the link names the new session: "_old_" then "_new)
	Do $$$AssertTrue(##class(%AI.Agent.Session).%ExistsId(old), "the original session is kept for the purge")
	Do $$$AssertTrue(##class(OcuTalon.Test.Agent.RunnerFixture).SessionExport(new) [ request.ItemId, "the new session holds the turn")
	Do $$$AssertEquals(..Warnings(eventMark), 1, "one warning")
	Set warning = ..WarningText(eventMark)
	Do $$$AssertTrue((warning [ needle) && (warning [ owner) && (warning [ request.DecisionRef), "that names the step, the OwnerRef and the DecisionRef: "_warning)
	For i = 0:1:chat.%Size() - 1 {
		Do $$$AssertTrue(..RequestTokens(chat.%Get(i), ..#CHAT) < 100000, "every logged request is under 100,000 tokens")
	}
}

/// The asserts of a summarizer request that threw (rows 3 and 5): its compaction Usage row exists, an estimate of one request with no output.
Method AssertThrownRow(request As OcuTalon.Bridge.Msg.Request)
{
	Set row = ..CompactionRow(request)
	Do $$$AssertTrue($IsObject(row), "the thrown request got its compaction row")
	If $IsObject(row) Do $$$AssertEquals(row.OutputTokens_"|"_row.Estimated_"|"_row.RequestCount, "0|1|1", "an estimate of one request, with no output")
}

/// The number of warnings that the compaction logged after the event-log mark (the method CompactWarning of the adapter, whatever the
/// class of the adapter is).
ClassMethod Warnings(mark As %Integer) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = ?", mark, "CompactWarning")
	Do result.%Next()
	Quit result.%GetData(1)
}

/// The text of the first warning of the compaction after the mark, with the step as "step: <name>".
ClassMethod WarningText(mark As %Integer) As %String
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = ? ORDER BY ID", mark, "CompactWarning")
	If 'result.%Next() Quit ""
	Set text = result.%GetData(1)
	Quit "step: "_$Piece($Piece(text, " failed at ", 2), " (", 1)_" | "_text
}

/// The compaction Usage row of the request (the row of its DecisionRef whose Agent is compaction), or "".
ClassMethod CompactionRow(request As OcuTalon.Bridge.Msg.Request) As OcuTalon.Bridge.Data.Usage
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ? AND Agent = 'compaction'", request.DecisionRef)
	If 'result.%Next() Quit ""
	Quit ##class(OcuTalon.Bridge.Data.Usage).%OpenId(result.%GetData(1))
}

/// A turn for the runner (Test.Bridge.Conversation NewTurn) of the owner, with the input as given.
ClassMethod Plain(input As %String, owner As %String) As OcuTalon.Bridge.Msg.Request
{
	Quit ##class(OcuTalon.Test.Bridge.Conversation).NewTurn(input, owner)
}

/// The same turn, flagged for compaction as Decide flags it (Compact 1).
ClassMethod Flagged(input As %String, owner As %String) As OcuTalon.Bridge.Msg.Request
{
	Set request = ..Plain(input, owner)
	Set request.Compact = 1
	Quit request
}

/// Sends the request through the host's OnMessage and returns the status; reply is the runner's Reply (or ""), and entries holds every line of the
/// mock's log written during the call, the summarizer's requests included. With accept 1 (the default) the reply is then accepted as Decide would accept an
/// on-time one (Test.Bridge.Runner Accept), which moves the link to the session the reply names; with accept 0 the link is where the runner left it.
ClassMethod Go(host As OcuTalon.Bridge.Operation.AgentRunner, request As OcuTalon.Bridge.Msg.Request, Output reply As OcuTalon.Bridge.Msg.Reply, Output entries As %DynamicArray, accept As %Boolean = 1) As %Status
{
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set sc = host.OnMessage(request, .reply)
	Do $ClassMethod(..#MOCK, "LogSince", mark, .entries)
	If accept && $$$ISOK(sc) Do ##class(OcuTalon.Test.Bridge.Runner).Accept(request, reply, ..#AGENT)
	Quit sc
}

/// The entries of the log that are summarizer requests: model requests answered by a summary scenario.
ClassMethod Summarizers(entries As %DynamicArray) As %DynamicArray
{
	Set found = []
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.path = "/v1/messages") && ($Extract(entry.scenario, 1, 7) = "summary") Do found.%Push(entry)
	}
	Quit found
}

/// The estimated size of a logged request in tokens, at four characters a token: its messages and the system prompt and tool schemas of the
/// agent class (RequestSize.AgentChars), because the log keeps the size of the system text and the names of the tools only.
ClassMethod RequestTokens(logged As %DynamicObject, agentClass As %String) As %Integer
{
	Set agent = ##class(OcuTalon.Bridge.RequestSize).AgentChars(agentClass)
	Quit ##class(OcuTalon.Bridge.Adapter.StepBuffer).Tokens($Length(logged.request.messages.%ToJSON()) + agent)
}

/// The history of the saved AI session (GetContext), read through the host's adapter, which does not keep the session.
ClassMethod ContextOf(host As OcuTalon.Bridge.Operation.AgentRunner, id As %String) As %DynamicArray
{
	Set context = ""
	Do host.Adapter.BuildAgent()
	Do host.Adapter.OpenSession(id, .session)
	If $IsObject(session) Set context = session.GetContext()
	Set session = ""
	Set host.Adapter.Agent.Session = ""
	Quit context
}

/// Puts the row of Decide's RequestTokenLimit (System Default Settings) at the value, to be put back after the test.
Method PutLimit(value As %Integer)
{
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RememberDefault(.saved, "Decide", "RequestTokenLimit")
	Set ..Saved = $Get(saved)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).PutDefault("Decide", "RequestTokenLimit", value), "RequestTokenLimit is "_value)
}

/// The text of the given number of characters: the word and a space, over and over.
ClassMethod Filler(word As %String, chars As %Integer) As %String
{
	Set text = word_" "
	While $Length(text) < chars {
		Set text = text_text
	}
	Quit $Extract(text, 1, chars)
}

ClassMethod NewHost(agentClass As %String = {..#CHAT}) As OcuTalon.Bridge.Operation.AgentRunner
{
	Quit ##class(OcuTalon.Test.Bridge.Conversation).NewHost(agentClass)
}

ClassMethod LinkOf(owner As %String) As %String
{
	Quit ##class(OcuTalon.Test.Bridge.Conversation).LinkOf(owner)
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
