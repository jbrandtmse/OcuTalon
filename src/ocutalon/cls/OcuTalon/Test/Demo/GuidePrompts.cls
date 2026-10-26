/// Tests of the two guide-prompt scenarios of the CI mock (Story 4.4; matrix row 17; AD-22): a Chat turn whose input is exactly the demo guide's
/// prompt for step 1 or step 2 is answered by the scenario that ci/mock/scenarios/B/ keys by that text, selected by the prompt and not by a marker or the
/// mock key, with the scenario's reply and no fallback. THESE TESTS RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), as Test.Tools.Reminders does: they
/// need OcuTalon.Production running after the Production step, the CI override's environment (the mock's base URL and OCUTALON_MOCK_KEY_HEADER=1) and the
/// mock's request log, and they fail with the reason where they do not have them. OnBeforeAllTests points the Config Store entry of each runner at the
/// non-secret CI variable OCUTALON_MOCK_KEY_HEADER (RunnerFixture.PointKeys); OnAfterAllTests puts the entries back (RunnerFixture.RestoreKeys), on every path.
/// Every turn is sent through Decide (RunnerFixture.Run) with an owner of its own (a new Ref), so the tool that the second scenario calls answers that no
/// session owns the turn and changes nothing: no reminder is set.
///   - TestWatchPrompt: "Watch the Orders production and only tell me if something needs me." (guide-watch): the mock logged one request for the turn,
///     selected by prompt, scenario guide-watch; the answer is a Reply with the scenario's text, not a fallback;
///   - TestReminderPrompt: "Remind me in 1 minute to stretch." (guide-reminder): the mock logged two requests, each selected by prompt with the scenario
///     guide-reminder; the first answers the call of set_reminder, the second carries its tool_result; the answer is the scenario's second reply, not a fallback.
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

/// "Watch the Orders production and only tell me if something needs me." (matrix row 17; scenario guide-watch). The mock selects the scenario by the prompt,
/// which the turn's input holds, and answers with its one reply, which is the turn's reply.
Method TestWatchPrompt()
{
	If '..Ready() Quit
	Set sc = ..Turn(..#PROMPTWATCH, .answer, .requests)
	Do ..AssertAnswer(sc, answer, "The CI mock answered the guide's watch prompt.")
	Do ..AssertRequests(requests, "guide-watch", 1)
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

/// Sends a user turn with exactly the text through Decide (RunnerFixture.Run), with an owner of its own, and reads the mock's log for it: answer is the Reply
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
