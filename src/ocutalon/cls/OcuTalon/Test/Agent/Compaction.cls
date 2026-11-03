/// Tests of the compaction of a long conversation through the running production and the CI mock (Story 30.1; AD-5, AD-6, AD-8, AD-20, NFR-3).
/// THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), like Test.Agent.RequestSize: it needs OcuTalon.Production running after the Production step,
/// the CI override's environment and the mock's request log, and fails with the reason where it does not have them. Each request goes through ApprovalStartIn
/// to Decide, as a caller of Decide will send it (Test.Agent.RunnerFixture.Run), and the first test points the Config Store entry of each runner at the
/// non-secret CI variable (as RequestSize does). Test.Bridge.Compaction pins the rows that need no production.
///   - TestGrowsIntoCompaction (AC 1, AC 3): an owner's turn 1 has about 170,000 characters; turn 2 is short and continues the conversation, with nothing older to
///     summarize; turn 3 is short too, and is flagged with turn 1 older: it is answered from a compacted session (the request that Decide sent has Compact 1,
///     a compaction Usage row with Estimated 1 has its DecisionRef, the reply is rotated), every Usage row of the conversation has a largest request under
///     100,000 tokens, and every request that the mock logged for turn 3 is under 100,000 tokens. The alarm that Decide set is 60 seconds for turn 1 (no link) and
///     80 for turns 2 and 3 (flagged, and continuing) under TimerSeconds 60;
///   - TestHistoryOverTheLimit (AC 2, DW-125): an owner whose stored history alone passes RequestTokenLimit (turn 1 saved at the default limit, then a row of 41,000
///     and Decide started again) sends a short turn: it is answered, not too_large, and every request that the mock logged for it is at most 41,000 tokens; a
///     turn of another owner whose input alone passes the limit still takes too_large and reaches no runner.
/// OnAfterOneTest puts back what a test changed, also when it failed: the Decision, Usage and AgentStep rows of its items and owners, the System Default
/// Settings row it wrote (Decide's RequestTokenLimit) with the item it restarted, and the AI sessions it saved with the links that name them.
Class OcuTalon.Test.Agent.Compaction Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

/// The runner item of the conversations, which is the agent of their links.
Parameter RUNNER = "ChatAgent";

/// The text of recall-tell.json.
Parameter TELLTEXT = "Noted.";

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

/// The ItemIds of the requests that the test made, and the owners of its conversations.
Property ItemIds As %List;

Property Owners As %List;

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
	Set position = 0
	While $ListNext(..Owners, position, owner) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ?", owner)
	}
	Set ..Owners = ""
	Set running = ##class(OcuTalon.Test.Agent.RunnerFixture).Running()
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreDefaults(..SavedRows)
	Set ..SavedRows = ""
	If ..DecideChanged && running {
		Set ..DecideChanged = 0
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Agent.RunnerFixture).Restart(..#PRODUCTION_"||Decide"), "Decide is started again with the settings it had")
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

/// A conversation grows through Decide until a turn is flagged with older history (AC 1), and the alarm of a flagged turn that continues is 80 seconds (AC 3).
Method TestGrowsIntoCompaction()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set mock = ..#MOCK
	Set timer = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("TimerSeconds", ..#PRODUCTION, "Decide")
	Do $$$AssertEquals(timer, 60, "control: Decide's TimerSeconds is 60")
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Owners = ..Owners _ $ListBuild(owner)
	Set filler = $Translate($Justify("", 170000), " ", "a")
	Set one = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] "_filler, .ref1, owner)
	Set two = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] A short second thing.", .ref2, owner)
	Set three = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] A short third thing.", .ref3, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref1, ref2, ref3)

	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", one, .first, .session1), "turn 1 is answered")
	Do $$$AssertEquals($Select($IsObject(first): first.Fallback_"|"_first.Text, 1: "none"), "0|"_..#TELLTEXT, "with the text of the chat script and no fallback")
	Do $$$AssertEquals(..SentCompact(session1), 1, "turn 1 is flagged (about 42,500 tokens)")
	Do $$$AssertEquals(..Alarm(session1), 60, "and its alarm is 60 seconds: it has no conversation to continue")

	Set mark2 = $ClassMethod(mock, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", two, .second, .session2), "turn 2 is answered")
	Do $$$AssertEquals($Select($IsObject(second): second.Fallback_"|"_second.Text, 1: "none"), "0|"_..#TELLTEXT, "with the same text")
	Do $$$AssertEquals(..SentCompact(session2), 1, "turn 2 is flagged: its stored history is about 42,500 tokens")
	Do $$$AssertEquals(..Alarm(session2), 80, "and its alarm is 80 seconds: it continues the conversation")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark2, .entries2), "the mock's log is read")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.Compaction).Summarizers(entries2).%Size(), 0, "there was nothing older to summarize: no summarizer request")
	Do $$$AssertEquals($ClassMethod(fixture, "UsageIds", "DecisionRef", second.DecisionRef).%Size(), 1, "and one Usage row, the chat's")

	Set mark3 = $ClassMethod(mock, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", three, .third, .session3), "turn 3 is answered")
	Do $$$AssertEquals($Select($IsObject(third): third.Fallback_"|"_third.Text_"|"_third.SessionRotated, 1: "none"), "0|"_..#TELLTEXT_"|1", "from the compacted session, with the text of the chat script, no fallback and SessionRotated 1")
	Do $$$AssertEquals(..SentCompact(session3), 1, "the request that Decide sent has Compact 1")
	Do $$$AssertEquals(..Alarm(session3), 80, "and its alarm is 80 seconds")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark3, .entries3), "the mock's log is read")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.Compaction).Summarizers(entries3).%Size(), 1, "the mock logged one summarizer request")
	Set row = $ClassMethod(fixture, "DecisionOf", ref3, "turn")
	Set ids = $ClassMethod(fixture, "UsageIds", "DecisionRef", $Select($IsObject(row): row.Ref, 1: third.DecisionRef))
	Do $$$AssertEquals(ids.%Size(), 2, "two Usage rows carry the DecisionRef: the chat's and the compaction's")
	Set estimated = 0
	For i = 0:1:ids.%Size() - 1 {
		Set usage = ##class(OcuTalon.Bridge.Data.Usage).%OpenId(ids.%Get(i))
		If usage.Agent = "compaction" Set estimated = estimated + usage.Estimated
	}
	Do $$$AssertEquals(estimated, 1, "one of them is a compaction row with Estimated 1")
	Set summed = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*), MAX(LargestRequestTokens) FROM OcuTalon_Bridge_Data.Usage WHERE OwnerRef = ?", owner)
	Do summed.%Next()
	Do $$$AssertEquals(summed.%GetData(1), 4, "the conversation has four Usage rows: three chat calls and the compaction")
	Do $$$AssertTrue(summed.%GetData(2) < 100000, "and none has a largest request of 100,000 tokens or more: "_summed.%GetData(2))
	Set requests = $ClassMethod(fixture, "FindRequests", entries3, ref3)
	Do $$$AssertEquals(requests.%Size(), 1, "the mock logged one chat request for turn 3")
	If requests.%Size() = 1 {
		Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Compaction).RequestTokens(requests.%Get(0), "OcuTalon.Agent.Chat") < 100000, "which is under 100,000 tokens: "_##class(OcuTalon.Test.Bridge.Compaction).RequestTokens(requests.%Get(0), "OcuTalon.Agent.Chat"))
		Do $$$AssertTrue(requests.%Get(0).%ToJSON() '[ "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "and holds none of turn 1's filler")
	}
	Do $$$AssertEquals($Select($IsObject(row): row.Fallback, 1: "none"), 0, "the Decision row records no fallback")
}

/// A stored history that alone passes RequestTokenLimit no longer sticks the conversation (AC 2, DW-125).
Method TestHistoryOverTheLimit()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Set mock = ..#MOCK
	Set owner = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..Owners = ..Owners _ $ListBuild(owner)
	Set filler = $Translate($Justify("", 170000), " ", "a")
	Set one = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] "_filler, .ref1, owner)
	Set two = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] A short question.", .ref2, owner)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref1, ref2)
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", one, .first), "turn 1 is answered at the default limit")
	Do $$$AssertEquals($Select($IsObject(first): first.Fallback_"|"_first.Text, 1: "none"), "0|"_..#TELLTEXT, "with the text of the chat script")
	Set id = ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, ..#RUNNER)
	Do $$$AssertTrue(id '= "", "the owner's link names a saved session: "_id)
	Do $$$AssertTrue(##class(OcuTalon.Bridge.RequestSize).HistoryChars(id) > 164000, "whose stored history alone passes 41,000 tokens")

	Do ..Put("Decide", "RequestTokenLimit", 41000)
	Set ..DecideChanged = 1
	Do $$$AssertStatusOK($ClassMethod(fixture, "Restart", ..#PRODUCTION_"||Decide"), "Decide is started again with a RequestTokenLimit of 41000")
	Set mark = $ClassMethod(mock, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", two, .second, .session2), "the short turn is answered")
	Do $$$AssertEquals($Select($IsObject(second): second.Fallback_"|"_second.FailureText_"|"_second.Text, 1: "none"), "0||"_..#TELLTEXT, "it is not a too_large fallback: it has the text of the chat script")
	Set row = $ClassMethod(fixture, "DecisionOf", ref2, "turn")
	Do $$$AssertEquals($Select($IsObject(row): row.Fallback_"|"_row.FallbackReason, 1: "none"), "0|", "and its Decision row records no fallback")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", $ClassMethod(fixture, "Headers", session2, "Decide"), ..#RUNNER), 1, "Decide sent ChatAgent one request for it")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries), "the mock's log is read")
	Set requests = $ClassMethod(fixture, "FindRequests", entries, ref2)
	Do $$$AssertTrue(requests.%Size() > 0, "the mock logged the turn's request")
	For i = 0:1:requests.%Size() - 1 {
		Do $$$AssertTrue(##class(OcuTalon.Test.Bridge.Compaction).RequestTokens(requests.%Get(i), "OcuTalon.Agent.Chat") '> 41000, "every request that the mock logged for it is at most 41,000 tokens: "_##class(OcuTalon.Test.Bridge.Compaction).RequestTokens(requests.%Get(i), "OcuTalon.Agent.Chat"))
	}
	Do $$$AssertNotEquals(##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(owner, ..#RUNNER), id, "the conversation moved to a session of its own")

	// a turn whose input alone passes the limit is still too_large, and reaches no runner
	Set other = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set big = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:recall-tell]] "_$Translate($Justify("", 4 * 41000 + 400), " ", "a"), .ref3, other)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref3)
	Set mark = $ClassMethod(mock, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", big, .answer, .session3), "the turn with the large input is answered")
	Set bigRow = $ClassMethod(fixture, "DecisionOf", ref3, "turn")
	Do $$$AssertEquals($ClassMethod(fixture, "FallbackProblems", answer, bigRow, "turn", "too_large"), "", "with a too_large fallback Reply, in the answer, its XML and the row")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", $ClassMethod(fixture, "Headers", session3, "Decide"), ..#RUNNER), 0, "Decide sent no request to ChatAgent")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Drain", ..#RUNNER), "ChatAgent handled everything sent to it")
	Do $$$AssertStatusOK($ClassMethod(mock, "LogSince", mark, .entries2), "the mock's log is read")
	Do $$$AssertEquals($ClassMethod(fixture, "FindRequests", entries2, ref3).%Size(), 0, "and nothing of it reached the mock")
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

/// The Timeout in seconds of the alarm that Decide set in the session, or "none".
ClassMethod Alarm(session As %Integer) As %String [ Private ]
{
	Set alarm = ##class(OcuTalon.Test.Agent.RunnerFixture).HeaderTo(##class(OcuTalon.Test.Agent.RunnerFixture).Headers(session, "Decide"), "Ens.Alarm")
	If '$IsObject(alarm) Quit "none"
	Set timer = ##class(Ens.AlarmRequest).%OpenId(alarm.bodyId)
	Quit $Select($IsObject(timer): timer.Timeout, 1: "none")
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
