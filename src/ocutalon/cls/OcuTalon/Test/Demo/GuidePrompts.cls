/// Tests of the guide-prompt scenarios of the CI mock (Story 4.4; matrix row 17; Story 11.7; AD-22 as amended by U-194): a request whose input holds the
/// demo guide's exact prompt for step 1 or step 2 (followed by the turn's ref, which RunnerFixture.NewRequest adds) is answered by the scenario that
/// ci/mock/scenarios/B/ keys by that text and by the mock key of the agent that sends it: the Chat turn by guide-watch or guide-reminder (mockkey chat)
/// and the Triage decision by guide-watch-triage or guide-reminder-triage (mockkey triage). The mock finds the prompt contained in the message and
/// selects by the prompt, not by a marker or the default script of the mock key. THESE TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), as
/// Test.Tools.Reminders does: they
/// need OcuTalon.Production running after the Production step, the CI override's environment (the mock's base URL and OCUTALON_MOCK_KEY_HEADER=1) and the
/// mock's request log, and they fail with the reason where they do not have them. OnBeforeAllTests points the Config Store entry of each runner at the
/// non-secret CI variable OCUTALON_MOCK_KEY_HEADER (RunnerFixture.PointKeys); OnAfterAllTests puts the entries back (RunnerFixture.RestoreKeys), on every path.
/// Every turn is sent through Decide (RunnerFixture.Run) with an owner of its own (a new Ref), so a tool that a scenario calls answers that no
/// session owns the turn and changes nothing: no check row and no reminder is written.
///   - TestWatchPrompt: "Watch the Orders production and only tell me if something needs me." (guide-watch): the mock logged two Chat requests for the
///     turn, selected by prompt, scenario guide-watch; the first answers the call of start_watch, the second carries its tool_result; the answer is a
///     Reply with the scenario's second reply, not a fallback;
///   - TestReminderPrompt: "Remind me in 1 minute to stretch." (guide-reminder): the mock logged two requests, each selected by prompt with the scenario
///     guide-reminder; the first answers the call of set_reminder, the second carries its tool_result; the answer is the scenario's second reply, not a fallback;
///   - TestWatchPromptTriage and TestReminderPromptTriage: a decide request of provenance user holding the prompt is one request, selected by prompt with
///     the scenario guide-watch-triage or guide-reminder-triage, and its Decision row (kind decide) is outcome act with no fallback.
/// OnAfterOneTest removes the Decision, Usage and AgentStep rows of the turns (by ItemId) and the AI sessions the turns saved.
Class OcuTalon.Test.Demo.GuidePrompts Extends %UnitTest.TestCase
{

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

/// The exact prompt of step 1.
Parameter PROMPTWATCH = "Watch the Orders production and only tell me if something needs me.";

/// The exact prompt of step 2.
Parameter PROMPTREMINDER = "Remind me in 1 minute to stretch.";

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 400);

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The mark of the saved AI sessions when the test began (RunnerFixture.SessionMark).
Property SessionMark As %Integer;

/// The ItemIds of the turns that the test made.
Property ItemIds As %List;

Method OnBeforeAllTests() As %Status
{
	Set ..Missing = $ClassMethod(..#FIXTURE, "ReadyReason")
	If ..Missing '= "" Quit $$$OK
	Set ..Pointed = 1
	Set sc = $ClassMethod(..#FIXTURE, "PointKeys")
	If $$$ISERR(sc) Set ..Missing = "The entries of the runners could not be pointed at the CI mock key variable: "_$SYSTEM.Status.GetErrorText(sc)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Set sc = $$$OK
	If ..Pointed {
		Set ..Pointed = 0
		Set sc = $ClassMethod(..#FIXTURE, "RestoreKeys")
		Set placeholder = ##class(OcuTalon.Install.Step.Provider).#KEYPLACEHOLDER
		If '$ClassMethod(..#FIXTURE, "KeysAre", placeholder) Set sc = $SYSTEM.Status.AppendStatus(sc, $SYSTEM.Status.Error(5001, "The entries of the runners do not hold the placeholder of the Provider step after the restore"))
	}
	Quit sc
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Set ..ItemIds = ""
	If ..Missing = "" Set ..SessionMark = $ClassMethod(..#FIXTURE, "SessionMark")
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Set position = 0
	While $ListNext(..ItemIds, position, itemId) {
		Do $ClassMethod(..#FIXTURE, "DeleteSteps", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
	}
	Set ..ItemIds = ""
	If ..Missing = "" && $ClassMethod(..#FIXTURE, "Running") Do $ClassMethod(..#FIXTURE, "DropSince", ..SessionMark)
	Quit sc
}

/// "Watch the Orders production and only tell me if something needs me." (matrix row 17; scenario guide-watch). The mock selects the scenario by the prompt
/// and the Chat mock key, which the turn's input and request hold. The first reply calls start_watch for Orders, so the model's second request carries the
/// tool_result of that call, and the second reply is the turn's reply. The turn's owner is no session, so the tool answers that and writes no check row.
Method TestWatchPrompt()
{
	If '..Ready() Quit
	Set before = ..CheckCount()
	Set sc = ..Turn(..#PROMPTWATCH, .answer, .requests)
	Do ..AssertAnswer(sc, answer, "I'll watch the Orders production and stay quiet unless something needs you.")
	Do ..AssertRequests(requests, "guide-watch", 2)
	If requests.%Size() = 2 {
		Set second = requests.%Get(1)
		Do $$$AssertEquals(..ToolNameOf(second, "start_watch"), "start_watch", "the second request holds the call of start_watch")
		Do $$$AssertEquals($ListLength($ClassMethod(..#FIXTURE, "ToolResults", second)), 1, "and carries one tool_result, the answer to it")
	}
	Do $$$AssertEquals(..CheckCount(), before, "the turn wrote no check row: no session owns it")
}

/// The watch prompt as a decide request (scenario guide-watch-triage; DW-307): one request, selected by the prompt, and an act decision with no fallback.
Method TestWatchPromptTriage()
{
	If '..Ready() Quit
	Do ..AssertTriage(..#PROMPTWATCH, "guide-watch-triage")
}

/// "Remind me in 1 minute to stretch." (matrix row 17; scenario guide-reminder). The mock selects the scenario by the prompt; the first reply calls set_reminder
/// with the text stretch and 60 seconds, so the model's second request carries the tool_result of that call, and the second reply is the turn's reply.
Method TestReminderPrompt()
{
	If '..Ready() Quit
	Set before = ..ReminderCount()
	Set sc = ..Turn(..#PROMPTREMINDER, .answer, .requests)
	Do ..AssertAnswer(sc, answer, "The CI mock set the reminder.")
	Do ..AssertRequests(requests, "guide-reminder", 2)
	If requests.%Size() = 2 {
		Set second = requests.%Get(1)
		Do $$$AssertEquals(..ToolInputOf(second, "set_reminder"), "stretch|60", "the second request holds the call of set_reminder with the text and the delay of the scenario")
		Do $$$AssertEquals($ListLength($ClassMethod(..#FIXTURE, "ToolResults", second)), 1, "and carries one tool_result, the answer to it")
	}
	Do $$$AssertEquals(..ReminderCount(), before, "the turn set no reminder: no session owns it")
}

/// The reminder prompt as a decide request (scenario guide-reminder-triage; DW-307): one request, selected by the prompt, and an act decision with no fallback.
Method TestReminderPromptTriage()
{
	If '..Ready() Quit
	Do ..AssertTriage(..#PROMPTREMINDER, "guide-reminder-triage")
}

/// --- helpers ---
/// 1 when the production runs with every item in the CI override's environment and the entries of the runners are pointed at the mock key variable. Otherwise
/// the test fails with the reason, and quits. Today's day mark is removed first, so that no earlier class leaves the day capped.
Method Ready() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc()))
	Quit 1
}

/// Sends a user turn whose input is the text followed by the turn's ref (RunnerFixture.NewRequest) through Decide (RunnerFixture.Run), with an owner of its
/// own, and reads the mock's log for it: answer is the Reply
/// and requests the entries of the mock's log for the turn, in order. The turn's ItemId is remembered for OnAfterOneTest.
Method Turn(text As %String, Output answer As %Persistent, Output requests As %DynamicArray) As %Status [ Private ]
{
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", "turn", "user", text, .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .answer, .session)
	Set requests = []
	Set logged = $ClassMethod(..#MOCK, "LogSince", mark, .entries)
	If $$$ISOK(logged) {
		Set requests = $ClassMethod(..#FIXTURE, "FindRequests", entries, ref)
	} ElseIf $$$ISOK(sc) {
		Set sc = logged
	} Else {
		Set sc = $SYSTEM.Status.AppendStatus(sc, logged)
	}
	Quit sc
}

/// Sends the prompt as a decide request of provenance user through Decide (RunnerFixture.Run) and reads the mock's log: one request, selected by the prompt
/// with the scenario, and the Decision row of the request (kind decide) is outcome act, no fallback and no fallback reason.
Method AssertTriage(prompt As %String, scenario As %String) [ Private ]
{
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", "decide", "user", prompt, .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set sc = $ClassMethod(..#FIXTURE, "Run", request, .answer, .session)
	Do $$$AssertStatusOK(sc, "Decide answers the request")
	Set logged = $ClassMethod(..#MOCK, "LogSince", mark, .entries)
	Do $$$AssertStatusOK(logged, "the mock's log can be read")
	If $$$ISERR(logged) Quit
	Do ..AssertRequests($ClassMethod(..#FIXTURE, "FindRequests", entries, ref), scenario, 1)
	Set row = $ClassMethod(..#FIXTURE, "DecisionOf", ref, "decide")
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "the request has a Decision row of kind decide")
		Quit
	}
	Do $$$AssertEquals(row.Outcome_"|"_row.Fallback_"|"_row.FallbackReason, "act|0|", "the decision is act, and not a fallback")
}

/// The number of rows of the BackgroundCheck table.
Method CheckCount() As %Integer [ Private ]
{
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BackgroundCheck")
	Do rows.%Next()
	Quit rows.%GetData(1)
}

/// The name of the first call of the tool that a logged request carries in its messages, or "".
Method ToolNameOf(logged As %DynamicObject, tool As %String) As %String [ Private ]
{
	Set messages = logged.request.messages
	For m = 0:1:messages.%Size() - 1 {
		Set message = messages.%Get(m)
		If message.%GetTypeOf("content") '= "array" Continue
		Set iterator = message.content.%GetIterator()
		While iterator.%GetNext(, .block) {
			If (block.type = "tool_use") && (block.name = tool) Return block.name
		}
	}
	Quit ""
}

/// The text and the delaySeconds ("stretch|60") of the input of the first call of the tool that a logged request carries in its messages, or "".
Method ToolInputOf(logged As %DynamicObject, tool As %String) As %String [ Private ]
{
	Set messages = logged.request.messages
	For m = 0:1:messages.%Size() - 1 {
		Set message = messages.%Get(m)
		If message.%GetTypeOf("content") '= "array" Continue
		Set iterator = message.content.%GetIterator()
		While iterator.%GetNext(, .block) {
			If (block.type = "tool_use") && (block.name = tool) Return block.input.text_"|"_block.input.delaySeconds
		}
	}
	Quit ""
}

/// The number of rows of the Reminder table.
Method ReminderCount() As %Integer [ Private ]
{
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Reminder")
	Do rows.%Next()
	Quit rows.%GetData(1)
}

/// The answer of Decide is a Reply with the scenario's text, and no fallback.
Method AssertAnswer(sc As %Status, answer As %Persistent, text As %String) [ Private ]
{
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(answer.Text, text, "the reply is the text of the scenario")
	Do $$$AssertEquals(answer.Fallback_"|"_answer.FailureText, "0|", "and not a fallback")
}

/// The mock logged count requests for the turn, and each was selected by the prompt, with the scenario of the name: not by a marker or the mock key, and not
/// a failed selection.
Method AssertRequests(requests As %DynamicArray, scenario As %String, count As %Integer) [ Private ]
{
	Do $$$AssertEquals(requests.%Size(), count, "the mock logged "_count_" request(s) for the turn")
	For i = 0:1:requests.%Size() - 1 {
		Set entry = requests.%Get(i)
		Do $$$AssertEquals(entry.selectedBy, "prompt", "request "_(i + 1)_" was selected by the prompt")
		Do $$$AssertEquals(entry.scenario, scenario, "request "_(i + 1)_" got the scenario "_scenario)
	}
}

}
