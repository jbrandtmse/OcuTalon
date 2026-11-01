/// The chat turn of the recent_activity tool (Story 5.13, the Integration AC; AD-7, AD-10, AD-28). THIS TEST RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with
/// demo mode on, through Test.Watch.Case, and fresh: the running ChatAgent keeps the toolset it started with. The message goes through WebChatIn to the real
/// Conversation, the real Decide and the real ChatAgent, against the CI mock (PointKeys). The scenario recent-activity, with its countdown armed at 1, answers the
/// triage request with tellnow, the Chat agent's first request with a call of recent_activity and its second with a reply that says that everything is fine.
///   - TestEarlierFailureInTheChat: session S has the records of the demo path (Test.Tools.RecentActivity.Demo, poisoned, last active two minutes ago so that the
///     quiet close leaves the incident alone) and asks "What was that failure earlier?". The Turn is done with no fallback and untainted; its one tool step is
///     "Reading recent activity", ok; the Chat agent's second request carries the tool result with the count 50, the element OrderDate, the approval answered on
///     web, 50 that went through, the state resolved and no ZZPOISON; and the reply holds no all-clear while the rest of it is kept.
/// After the test the countdown is cleared, and the turns of the run's sessions are removed with their decisions.
Class OcuTalon.Test.Tools.RecentActivityTurn Extends OcuTalon.Test.Watch.Case
{

Parameter SESSIONPREFIX = "zzrecturn";

/// The marker of the scenario, and the message that carries it.
Parameter MARKER = "recent-activity";

Parameter ASK = "What was that failure earlier? [[mock:recent-activity]]";

/// The first two sentences of the scenario's last reply; the third is the all-clear that the guard removes.
Parameter KEPT = "Earlier, 50 orders failed on the OrdersFromPartner item because of OrderDate. You approved the fix on the web, and all 50 went through.";

/// The longest to wait for a turn through the mock, in seconds.
Parameter WAIT = 90;

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Test.Contract.Mock).Arm(..#MARKER, "")
	Quit ##super(testname)
}

Method OnAfterAllTests() As %Status
{
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	Quit ##super()
}

Method TestEarlierFailureInTheChat()
{
	If '..Ready() Quit
	If '..PointKeys() Quit
	Set session = ..Session("earlier")
	Do ..Watch(session)
	Set ..Refs = ..Refs_","_##class(OcuTalon.Test.Tools.RecentActivity).Demo(session, 1, 120, .incident, .request, .times)
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).Arm(..#MARKER, 1), "the countdown of "_..#MARKER_" is armed at 1")
	Set clientId = "zzr"_..Number_"earlier"
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Do $$$AssertStatusOK(..Send(session, clientId, ..#ASK, .output), "the message is accepted by WebChatIn")
	Set row = ..WaitDone(session, clientId)
	If '$IsObject(row) || (row.State '= "done") {
		Do $$$AssertTrue(0, "the Turn is done within "_..#WAIT_" seconds")
		Quit
	}
	Set ..ItemIds = ..ItemIds_$ListBuild(row.ItemId)
	Do $$$AssertEquals(row.State_"|"_row.FallbackReason_"|"_row.ReplyCatalogKey_"|"_row.Tainted, "done|||0", "the Turn is done, with no fallback, and untainted")
	Do $$$AssertEquals($Extract(row.ReplyText, 1, $Length(..#KEPT)), ..#KEPT, "the reply keeps the sentences about the incident")
	Do ..AssertNoAllClear(row.ReplyText)
	Do ..AssertToolStep(row)
	Do ..AssertToolResult(mark)
}

/// Asserts that the text holds no phrase of the guard's two lists, ignoring case.
Method AssertNoAllClear(text As %String) [ Private ]
{
	Set phrases = $ListFromString($Parameter("OcuTalon.Checks.ReplyGuard", "RESERVED")_","_$Parameter("OcuTalon.Checks.ReplyGuard", "BANNED"))
	Set position = 0
	While $ListNext(phrases, position, phrase) {
		Do $$$AssertNotTrue($ZConvert(text, "L") [ $ZConvert(phrase, "L"), "the reply does not say '"_phrase_"'")
	}
}

/// Asserts that the turn decision has exactly one tool step, "Reading recent activity", ok.
Method AssertToolStep(row As OcuTalon.Data.Turn) [ Private ]
{
	Set steps = ##class(OcuTalon.Test.Agent.RunnerFixture).StepsOf(row.TurnDecisionRef)
	Set tools = 0
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		If step.kind '= "tool" Continue
		Set tools = tools + 1
		Do $$$AssertEquals(step.label_"|"_step.status, "Reading recent activity|ok", "the tool step is Reading recent activity, ok")
		Do $$$AssertTrue(step.summary [ "recent_activity", "and its summary names recent_activity: "_$Extract(step.summary, 1, 120))
	}
	Do $$$AssertEquals(tools, 1, "the turn decision has exactly one tool step")
}

/// Asserts that the Chat agent made two requests since the mark and that the second carries the tool result of the demo path's records.
Method AssertToolResult(mark As %Integer) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries), "the mock's log is read")
	Set chat = []
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.path = "/v1/messages") && ((","_##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(entry)_",") [ ",recent_activity,") Do chat.%Push(entry)
	}
	Do $$$AssertEquals(chat.%Size(), 2, "the Chat agent made two requests, and both offer recent_activity")
	If chat.%Size() '= 2 Quit
	Set results = ##class(OcuTalon.Test.Agent.RunnerFixture).ToolResults(chat.%Get(1))
	Do $$$AssertEquals($ListLength(results), 1, "the second request carries one tool result")
	If $ListLength(results) '= 1 Quit
	Set text = $List(results, 1)
	Do $$$AssertTrue(text '[ "ZZPOISON", "the tool result holds no ZZPOISON")
	Set answer = ""
	Try {
		Set answer = {}.%FromJSON(text)
	} Catch exception {
		Set answer = ""
	}
	Do $$$AssertTrue($IsObject(answer), "the tool result is a JSON object: "_$Extract(text, 1, 200))
	If '$IsObject(answer) Quit
	Do $$$AssertEquals(answer.incidents.%Size(), 1, "with one incident")
	If answer.incidents.%Size() '= 1 Quit
	Set one = answer.incidents.%Get(0)
	Do $$$AssertEquals(one.count_"|"_one.element_"|"_one.state_"|"_one.item, "50|OrderDate|resolved|OrdersFromPartner", "the count, the element, the state and the item")
	Set approval = one.approvals.%Get(0)
	Do $$$AssertEquals(approval.answer_"|"_approval.channel_"|"_approval.fix.wentThrough_"|"_approval.fix.finished, "approved|web|50|1", "the approval answered on web, and the 50 that went through")
}

}
