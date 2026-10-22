/// Tests of the agent steps in Visual Trace, through the running production and the CI mock (Story 1.5; AD-6, AD-9, AD-26, AD-30, AD-31).
/// THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): it needs OcuTalon.Production running after the Production step, the CI
/// override's environment (the mock's base URL and OCUTALON_MOCK_KEY_HEADER=1) and the mock's request log, and fails every test with the
/// reason where it does not have them, sending nothing. CI starts with no model key on purpose, so OnBeforeAllTests points the Config Store
/// entry of each runner at the non-secret CI variable OCUTALON_MOCK_KEY_HEADER, and then puts the test agent behind ChatAgent: it changes
/// the AgentClass and the AgentAllowList setting of ChatAgent in the stored configuration of the production (Test.Agent.RunnerFixture.UseAgent)
/// and updates the running production, which is the only way to put a test agent behind Decide (its runners are fixed, and an item
/// setting of the production definition beats a System Default Setting). The class definition of the production is not touched.
/// OnAfterAllTests puts both back, on every path.
///   - TestSwapKeepsDefinition: while the test agent runs behind ChatAgent, the stored setting says so, the allow-list names it, ChatAgent
///     has its job, and the XData of the production class is as it was;
///   - TestTwoTools: a user's turn through Decide whose test agent reads a note and a card makes five AgentStep messages for the DecisionRef
///     (model, tool, model, tool, model) in Position order, with the labels of the tools, summaries that hold the tools' names, inputs and
///     results, increasing estimates, the 1 s that the first request waited, and the totals; every header is from Decide to AgentSteps in the
///     session of the decision and of the answer and in the caller's super session, after the runner's reply and before the answer's, in the
///     order of the Positions, each completed; the answer has no Steps;
///   - TestRedacted: a turn whose tools get, return and fail with a model key, an access token, a password, a chat id and a display name:
///     none of the ten values is in any step, in the runner's Reply (Steps and XML), in the event log or in what the key scan names; each key
///     shows [redacted]; the failed card call is a step with the status error and its error text, redacted;
///   - TestDecideStep: an untrusted decide request to Triage's default script leaves one model step in the decision's session, and Decide
///     sends only to the runner, the timer, AgentSteps and its caller.
/// Added by the QA stage of Story 1.5 (AD-4, AD-9, AD-31):
///   - TestRedactedText: a turn whose tools answer TEXT, as the product's tools do (the scenario steps-secrets-text), and whose card tool
///     fails with a JSON body: none of the 14 fake secrets is in any step, in the runner's Reply (Steps and XML), in the event log or in
///     what the key scan names, and [redacted] stands in the place of each, counted in the two steps;
///   - OnAfterOneTest also deletes the AgentStep messages of the test's decisions, once AgentSteps has handled them.
Class OcuTalon.Test.Agent.Steps Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The runner whose agent is swapped.
Parameter RUNNER = "ChatAgent";

/// The test agent.
Parameter AGENT = "OcuTalon.Test.Bridge.StepsAgent";

/// The super session of the turns of the tests, as a channel service would set it (AD-26).
Parameter SUPER = "zzsuper-e1s5";

/// The ceiling, in seconds, of the wait for the step headers to be Completed.
Parameter WAITSECONDS = 60;

/// Why the set-up failed, or "" when the test agent runs behind ChatAgent.
Property Reason As %String(MAXLEN = 1000);

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// What ChatAgent had of the two settings (UseAgent), or "" while it is not swapped.
Property Saved As %DynamicObject;

/// The text of the XData of the production class when the test began.
Property DefinitionText As %String(MAXLEN = "");

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

Method OnBeforeAllTests() As %Status
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set ..Reason = $ClassMethod(fixture, "ReadyReason")
	If ..Reason '= "" Quit $$$OK
	Set ..DefinitionText = ..XDataText()
	Set ..Pointed = 1
	Set sc = $ClassMethod(fixture, "PointKeys")
	If $$$ISERR(sc) {
		Set ..Reason = "the entries of the runners cannot be pointed at the CI mock key variable: " _ $SYSTEM.Status.GetErrorText(sc)
		Quit $$$OK
	}
	Set sc = $ClassMethod(fixture, "UseAgent", ..#RUNNER, ..#AGENT, .saved)
	Set ..Saved = saved
	If $$$ISERR(sc) Set ..Reason = "the test agent cannot be put behind " _ ..#RUNNER _ ": " _ $SYSTEM.Status.GetErrorText(sc)
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
	Quit $$$OK
}

/// Puts ChatAgent's settings and the entries of the runners back, whatever happened before. The stored settings of ChatAgent are put
/// back even when the production has stopped (the update of the running production then fails, and so does the status); the entries of
/// the runners need the running production. The status is the first error.
Method OnAfterAllTests() As %Status
{
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set sc = $$$OK
	If $IsObject(..Saved) {
		Set sc = $ClassMethod(fixture, "RestoreAgent", ..#RUNNER, ..Saved)
		If $$$ISOK(sc) Set ..Saved = ""
	}
	If ..Pointed && $ClassMethod(fixture, "Running") {
		Set restored = $ClassMethod(fixture, "RestoreKeys")
		If $$$ISOK(restored) Set ..Pointed = 0
		If $$$ISOK(sc) Set sc = restored
	}
	Quit sc
}

/// While the test agent runs behind ChatAgent: the stored AgentClass is the test agent, the allow-list names it, ChatAgent has a job, and
/// the XData of the production class is as the test found it (the swap is in the stored configuration only).
Method TestSwapKeepsDefinition()
{
	If ..Failed() Quit
	Set production = ..#PRODUCTION _ "||" _ ..#RUNNER
	Do $$$AssertEquals(##class(Ens.Director).GetAdapterSettingValue(production, "AgentClass"), ..#AGENT, "the AgentClass of ChatAgent is the test agent")
	Do $$$AssertEquals(##class(Ens.Director).GetAdapterSettingValue(production, "AgentAllowList"), ..#AGENT, "and its allow-list names it")
	Do $$$AssertEquals($ListLength($ClassMethod("OcuTalon.Test.Agent.RunnerFixture", "Jobs", ..#RUNNER)), 1, "ChatAgent runs, with one job")
	Do $$$AssertTrue(..XDataText() = ..DefinitionText, "the XData of the production class is as it was found")
	Do $$$AssertTrue(..XDataText() [ "OcuTalon.Agent.Chat", "and it still names the product's Chat agent")
}

/// A user's turn through Decide with two read-only tool calls. The steps are five AgentStep messages in the trace session of the caller.
Method TestTwoTools()
{
	If ..Failed() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:steps-two-tools]] Read the note and the card.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set sc = $ClassMethod(fixture, "Run", request, .answer, .session, ..#SUPER)
	Do $$$AssertStatusOK(sc, "Decide answers the turn")
	If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(answer.Text, "The CI mock read the note and the card.", "the text is the last reply of the scenario")
	Set row = $ClassMethod(fixture, "DecisionOf", ref, "turn")
	If '$IsObject(row) {
		Do $$$AssertTrue(0, "a row of kind turn is recorded")
		Quit
	}
	Set steps = $ClassMethod(fixture, "StepsOf", answer.DecisionRef)
	Do $$$AssertEquals(steps.%Size(), 5, "five AgentStep messages exist for the DecisionRef")
	If steps.%Size() '= 5 Quit
	Set kinds = ""
	Set positions = ""
	For i = 0:1:4 {
		Set kinds = kinds _ $Select(i = 0: "", 1: ",") _ steps.%Get(i).kind
		Set positions = positions _ $Select(i = 0: "", 1: ",") _ steps.%Get(i).position
	}
	Do $$$AssertEquals(positions, "1,2,3,4,5", "their Positions are 1 to 5")
	Do $$$AssertEquals(kinds, "model,tool,model,tool,model", "and they are model, tool, model, tool, model")
	Set note = steps.%Get(1)
	Set card = steps.%Get(3)
	Do $$$AssertEquals(note.label, "Reading the test note", "the first tool step has the label of its class")
	Do $$$AssertEquals(card.label, "Reading the test card", "and the second the label of its tool's name")
	For part = "zz_steps_note", "status", "All systems normal." {
		Do $$$AssertTrue(note.summary [ part, "the note step's summary holds '" _ part _ "': " _ note.summary)
	}
	For part = "zz_steps_card", "ops", "On call: ops" {
		Do $$$AssertTrue(card.summary [ part, "the card step's summary holds '" _ part _ "': " _ card.summary)
	}
	Do $$$AssertEquals(note.status_"|"_card.status, "ok|ok", "both tool steps are ok")
	Do $$$AssertTrue((note.estimatedTokens > 0) && (card.estimatedTokens > 0), "and have an estimate: " _ note.estimatedTokens _ " and " _ card.estimatedTokens)
	Do $$$AssertTrue(note.durationMs '< 200, "the note step lasts at least 200 ms, as the tool hangs 0.25 s: " _ note.durationMs)
	Set first = steps.%Get(0)
	Set second = steps.%Get(2)
	Set third = steps.%Get(4)
	Do $$$AssertEquals(first.label_"|"_second.label_"|"_third.label, "Model request 1|Model request 2|Model request 3", "the model steps are numbered")
	Do $$$AssertTrue((first.estimatedTokens > 0) && (first.estimatedTokens < second.estimatedTokens) && (second.estimatedTokens < third.estimatedTokens), "their estimates are above 0 and grow: " _ first.estimatedTokens _ ", " _ second.estimatedTokens _ ", " _ third.estimatedTokens)
	Do $$$AssertTrue(first.summary [ "an estimate", "and say that they are estimates")
	Do $$$AssertTrue(first.durationMs '< 1000, "the first request lasted at least the 1 s that the mock waited: " _ first.durationMs)
	Do $$$AssertEquals(first.status_"|"_second.status_"|"_third.status, "ok|ok|ok", "and are ok")

	Do $$$AssertEquals(row.AgentStepCount_"|"_answer.AgentStepCount, "5|5", "the decision and the answer carry AgentStepCount 5")
	Do $$$AssertEquals(answer.Steps, "", "and the answer has no Steps: Decide sent them")

	// The trace. AgentSteps handles the steps while Decide answers, so the test waits for them to be Completed before it reads them.
	Do $$$AssertTrue(..WaitStepsDone(session, 5), "the five step headers are Completed within the ceiling")
	Set headers = ..HeadersOf(session)
	Set stepHeaders = ..HeadersWith(headers, "OcuTalon.Bridge.Msg.AgentStep")
	Do $$$AssertEquals(stepHeaders.%Size(), 5, "five headers carry an AgentStep in the session of the request")
	Set runnerId = ""
	Set answerId = ""
	Set iterator = headers.%GetIterator()
	While iterator.%GetNext(, .header) {
		If (header.source = "ChatAgent") && (header.bodyClass = "OcuTalon.Bridge.Msg.Reply") Set runnerId = header.id
		If (header.source = "Decide") && (header.target = "ApprovalStartIn") && (header.bodyClass = "OcuTalon.Bridge.Msg.Reply") Set answerId = header.id
	}
	Do $$$AssertTrue((runnerId '= "") && (answerId '= ""), "the session holds the runner's reply and Decide's answer: " _ runnerId _ " and " _ answerId)
	Set previous = runnerId
	Set position = 0
	Set iterator = stepHeaders.%GetIterator()
	While iterator.%GetNext(, .header) {
		Set position = position + 1
		Set label = "step header " _ position
		Do $$$AssertEquals(header.source _ ">" _ header.target, "Decide>AgentSteps", label _ " is from Decide to AgentSteps")
		Do $$$AssertEquals(header.session, session, label _ " is in the session of the request")
		Do $$$AssertEquals(header.super, ..#SUPER, label _ " has the caller's super session")
		Do $$$AssertEquals(header.status, 9, label _ " is Completed")
		Do $$$AssertEquals(header.bodyId, steps.%Get(position - 1).id, label _ " carries the message with Position " _ position _ ": the ids follow the Positions")
		Do $$$AssertTrue(header.id > previous, label _ " comes after " _ $Select(position = 1: "the runner's reply", 1: "the step before it"))
		Set previous = header.id
	}
	Do $$$AssertTrue((answerId '= "") && (previous < answerId), "the last step comes before Decide's answer")
	Do $$$AssertEquals(row.TraceSessionId, session, "the Decision row's TraceSessionId is the session of the steps")
	Do $$$AssertEquals(row.TraceSessionId, $ClassMethod(fixture, "SessionOf", answer), "which is the session of the answer's header")
	Do $$$AssertEquals($ClassMethod(fixture, "Targets", $ClassMethod(fixture, "Headers", session, "Decide")), "AgentSteps,ApprovalStartIn,ChatAgent,Ens.Alarm", "Decide sent only to the runner, the timer, AgentSteps and its caller")
	Set outside = 0
	Set iterator = steps.%GetIterator()
	While iterator.%GetNext(, .step) {
		Set outside = outside + ..HeadersOfBody("OcuTalon.Bridge.Msg.AgentStep", step.id, session)
	}
	Do $$$AssertEquals(outside, 0, "and no step has a header in another session")
}

/// A turn whose tools get secrets, return secrets and fail naming two of them. None of the ten values reaches the trace.
Method TestRedacted()
{
	If ..Failed() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set note = "OcuTalon.Test.Bridge.StepsNote"
	Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:steps-secrets]] Read the secret note.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(fixture, "EventMark")
	Set sc = $ClassMethod(fixture, "Run", request, .answer, .session, ..#SUPER)
	Do $$$AssertStatusOK(sc, "Decide answers the turn, though a tool failed")
	If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(answer.Text, "The CI mock read the secret note.", "the text is the last reply of the scenario")
	Set steps = $ClassMethod(fixture, "StepsOf", answer.DecisionRef)
	Do $$$AssertEquals(steps.%Size(), 5, "five AgentStep messages exist")
	If steps.%Size() '= 5 Quit
	Set noteStep = steps.%Get(1)
	Set cardStep = steps.%Get(3)
	Do $$$AssertEquals(noteStep.status, "ok", "the note step is ok")
	Do $$$AssertEquals(cardStep.status, "error", "the card step, whose tool failed, is an error")
	Do $$$AssertTrue(cardStep.summary [ "is locked", "its summary holds the error text: " _ cardStep.summary)
	Do $$$AssertTrue(cardStep.summary [ "[redacted]", "with the secrets in it replaced")
	Set kinds = $ListBuild("apiKey", "accessToken", "password", "chatId", "displayName")
	Set position = 0
	While $ListNext(kinds, position, kind) {
		Do $$$AssertTrue(noteStep.summary [ ("""" _ kind _ """:""[redacted]"""), "the note step shows [redacted] for " _ kind)
		Do $$$AssertTrue(cardStep.summary [ ("""" _ kind _ """:""[redacted]"""), "and the card step does too")
	}
	Set headers = $ClassMethod(fixture, "Headers", session, "ChatAgent")
	Set runner = $ClassMethod(fixture, "HeaderTo", headers, "Decide")
	Set reply = $Select($IsObject(runner): ##class(OcuTalon.Bridge.Msg.Reply).%OpenId(runner.bodyId), 1: "")
	Do $$$AssertTrue($IsObject(reply), "ChatAgent sent Decide a Reply")
	If $IsObject(reply) Do $$$AssertTrue(reply.Steps [ "[redacted]", "it carries the steps, redacted")
	For kind = "apiKey", "accessToken", "password", "chatId", "displayName" {
		For where = "arg", "result" {
			Set value = $ClassMethod(note, "Secret", kind, where)
			Do $$$AssertEquals($ClassMethod(fixture, "LeakPlaces", value, steps, reply, mark), "", "the " _ kind _ " " _ where _ " is in no agent step, not in the runner's Reply (its Steps and its XML), in no event-log row since the test began and in nothing that the key scan names")
		}
	}
}

/// A turn whose tools answer text and fail with a JSON body (the scenario steps-secrets-text), through Decide and the running production.
/// The product's tools return a %String, which AI Hub gives the audit policy as a JSON string; the redactor has to look inside it. Controls
/// first: the fixtures hold the 14 values that the test looks for. Then none of them is in any step, in the runner's Reply, in the event
/// log or in what the key scan names, and [redacted] stands in the place of each: nine times in the text step (five keys and four secrets
/// in a line of free text) and five times in the error of the card step.
Method TestRedactedText()
{
	If ..Failed() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set note = "OcuTalon.Test.Bridge.StepsNote"
	Set values = $ClassMethod(note, "TextValues")
	Do $$$AssertEquals($ClassMethod(fixture, "TextControlsMissing"), "", "control: the fixtures hold the 14 fake secrets that the test looks for")

	Set request = $ClassMethod(fixture, "NewRequest", "turn", "user", "[[mock:steps-secrets-text]] Read the secret report.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set mark = $ClassMethod(fixture, "EventMark")
	Set sc = $ClassMethod(fixture, "Run", request, .answer, .session, ..#SUPER)
	Do $$$AssertStatusOK(sc, "Decide answers the turn, though a tool failed")
	If '$IsObject(answer) || 'answer.%IsA("OcuTalon.Bridge.Msg.Reply") {
		Do $$$AssertTrue(0, "the answer is a Reply")
		Quit
	}
	Do $$$AssertEquals(answer.Text, "The CI mock read the secret report.", "the text is the last reply of the scenario")
	Set steps = $ClassMethod(fixture, "StepsOf", answer.DecisionRef)
	Do $$$AssertEquals(steps.%Size(), 5, "five AgentStep messages exist")
	If steps.%Size() '= 5 Quit
	Set textStep = steps.%Get(1)
	Set cardStep = steps.%Get(3)
	Do $$$AssertEquals(textStep.label_"|"_textStep.status, "Reading the test report|ok", "the text step has the label of its class and is ok")
	Do $$$AssertEquals(cardStep.label_"|"_cardStep.status, "Reading the test card|error", "the card step is an error")
	Do $$$AssertTrue(cardStep.summary [ "was refused", "its summary holds the error text: " _ cardStep.summary)
	Do $$$AssertEquals($Length(textStep.summary, "[redacted]") - 1, 9, "the text step shows [redacted] nine times: " _ textStep.summary)
	Do $$$AssertEquals($Length(cardStep.summary, "[redacted]") - 1, 5, "and the card step five times: " _ cardStep.summary)
	Set headers = $ClassMethod(fixture, "Headers", session, "ChatAgent")
	Set runner = $ClassMethod(fixture, "HeaderTo", headers, "Decide")
	Set reply = $Select($IsObject(runner): ##class(OcuTalon.Bridge.Msg.Reply).%OpenId(runner.bodyId), 1: "")
	Do $$$AssertTrue($IsObject(reply), "ChatAgent sent Decide a Reply")
	Set position = 0
	While $ListNext(values, position, value) {
		Do $$$AssertEquals($ClassMethod(fixture, "LeakPlaces", value, steps, reply, mark), "", "'" _ $Extract(value, 1, 22) _ "...' is in no agent step, not in the runner's Reply (its Steps and its XML), in no event-log row since the test began and in nothing that the key scan names")
	}
}

/// An untrusted decide request to Triage's default script: one model step in the decision's session. TriageAgent is not swapped.
Method TestDecideStep()
{
	If ..Failed() Quit
	Set fixture = "OcuTalon.Test.Agent.RunnerFixture"
	Set request = $ClassMethod(fixture, "NewRequest", "decide", "untrusted", "Triage this item.", .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Set sc = $ClassMethod(fixture, "Run", request, .response, .session)
	Do $$$AssertStatusOK(sc, "Decide answers the decide request")
	If '$IsObject(response) || 'response.%IsA("OcuTalon.Bridge.Msg.DecisionResponse") {
		Do $$$AssertTrue(0, "the answer is a DecisionResponse")
		Quit
	}
	Set steps = $ClassMethod(fixture, "StepsOf", response.DecisionRef)
	Do $$$AssertEquals(steps.%Size(), 1, "one AgentStep exists for the DecisionRef")
	If steps.%Size() = 1 {
		Set step = steps.%Get(0)
		Do $$$AssertEquals(step.position_"|"_step.kind_"|"_step.label_"|"_step.status, "1|model|Model request 1|ok", "a model step at Position 1")
		Do $$$AssertTrue(step.estimatedTokens > 0, "with an estimate: " _ step.estimatedTokens)
		Do $$$AssertTrue(step.summary [ "an estimate", "that says it is an estimate")
	}
	Set headers = $ClassMethod(fixture, "Headers", session, "Decide")
	Do $$$AssertEquals($ClassMethod(fixture, "Targets", headers), "AgentSteps,ApprovalStartIn,Ens.Alarm,TriageAgent", "Decide sent to the runner, the timer, AgentSteps and its caller")
	Set stepHeader = $ClassMethod(fixture, "HeaderTo", headers, "AgentSteps")
	If $IsObject(stepHeader) {
		Do $$$AssertEquals(stepHeader.bodyClass, "OcuTalon.Bridge.Msg.AgentStep", "the header to AgentSteps carries an AgentStep")
		Set row = $ClassMethod(fixture, "DecisionOf", ref, "decide")
		Do $$$AssertTrue($IsObject(row) && (row.TraceSessionId = session), "in the session of the decision's row")
	} Else {
		Do $$$AssertTrue(0, "a header to AgentSteps exists")
	}
	// The clean-up of the tests that make steps (QA): DeleteSteps removes the step and leaves the row of the decision.
	Do $$$AssertEquals($ClassMethod(fixture, "StepsOf", response.DecisionRef).%Size(), 1, "the step exists before DeleteSteps")
	Do $ClassMethod(fixture, "DeleteSteps", ref)
	Do $$$AssertEquals($ClassMethod(fixture, "StepsOf", response.DecisionRef).%Size(), 0, "DeleteSteps removes the AgentStep messages of the item's decision")
	Do $$$AssertTrue($IsObject($ClassMethod(fixture, "DecisionOf", ref, "decide")), "and not the decision's row")
}

/// --- helpers ---
/// 1 when the set-up failed: the test fails with the reason and sends nothing.
Method Failed() As %Boolean [ Private ]
{
	If ..Reason = "" Quit 0
	Do $$$AssertTrue(0, ..Reason)
	Quit 1
}

/// The text of the XData of the production class.
ClassMethod XDataText() As %String [ Private ]
{
	Set xdata = ##class(%Dictionary.XDataDefinition).%OpenId(..#PRODUCTION _ "||ProductionDefinition")
	If '$IsObject(xdata) Quit ""
	Set text = ""
	Do xdata.Data.Rewind()
	While 'xdata.Data.AtEnd {
		Set text = text _ xdata.Data.Read(30000)
	}
	Quit text
}

/// Every header of the session, oldest first, as a dynamic array of {"id","source","target","bodyClass","bodyId","session","super","status"}.
ClassMethod HeadersOf(session As %Integer) As %DynamicArray [ Private ]
{
	Set headers = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SourceConfigName, TargetConfigName, MessageBodyClassName, MessageBodyId, SessionId, SuperSession, Status FROM Ens.MessageHeader WHERE SessionId = ? ORDER BY ID", session)
	While result.%Next() {
		Do headers.%Push({"id": (result.%GetData(1)), "source": (result.%GetData(2)), "target": (result.%GetData(3)), "bodyClass": (result.%GetData(4)), "bodyId": (result.%GetData(5)), "session": (result.%GetData(6)), "super": (result.%GetData(7)), "status": (result.%GetData(8))})
	}
	Quit headers
}

/// The headers of the array whose body is of the class, in order.
ClassMethod HeadersWith(headers As %DynamicArray, bodyClass As %String) As %DynamicArray [ Private ]
{
	Set found = []
	Set iterator = headers.%GetIterator()
	While iterator.%GetNext(, .header) {
		If header.bodyClass = bodyClass Do found.%Push(header)
	}
	Quit found
}

/// Waits, polling, until the session holds the number of AgentStep headers that are Completed (status 9), or the ceiling passes. 1 when
/// it holds them.
ClassMethod WaitStepsDone(session As %Integer, count As %Integer) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + ..#WAITSECONDS
	While 1 {
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = ? AND Status = 9", session, "OcuTalon.Bridge.Msg.AgentStep")
		Do result.%Next()
		Set done = result.%GetData(1)
		If (done '< count) || ($ZHorolog > deadline) Quit
		Hang 0.5
	}
	Quit done '< count
}

/// The number of headers of the message body that are not in the session.
ClassMethod HeadersOfBody(bodyClass As %String, bodyId As %String, session As %Integer) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName = ? AND MessageBodyId = ? AND SessionId <> ?", bodyClass, bodyId, session)
	Do result.%Next()
	Quit result.%GetData(1)
}

}
