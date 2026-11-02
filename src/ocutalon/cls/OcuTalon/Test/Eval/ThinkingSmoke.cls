/// The thinking-history smoke test (Story 30.1; AD-20, AD-22): a conversation of three turns, each in a job of its own, with the thinking rule of Claude 5.5
/// forced, a change of the tool list between the turns, and a compaction through the guarded path. It checks what S2 measured once (a resumed, summarized
/// and tool-changed conversation passes, because AI Hub never sends thinking blocks back) on the model that the release candidate will run.
///   - The forcing. ZzSmokeAdapter adds extra_params.thinking {"type": "adaptive", "block_binding": {"prefix_mismatch_behavior": "error"}} to the session
///     config of every session of the runner ZzSmoke, and the provider settings carry the header anthropic-beta: thinking-binding-controls-2026-08-01.
///     The form is the Claude API reference's (inference): S2's notes do not say how S2 forced the rule.
///   - The turns. Turn 1 runs on OcuTalon.Agent.Chat and calls a tool; turn 2 on ZzSmokeChat (the reminder tools alone, so that its tool names differ
///     from turn 1's) and calls a tool; turn 3 is flagged for compaction (Compact 1) and runs on Chat again, so that the runner summarizes turn 1 through
///     ForkAndSummarize, keeps turn 2 whole, and reopens the fork. The owner is eval, which no cap or session total counts, and the runner is named
///     ZzSmoke. Its link, its AI sessions and its Usage rows are removed before and after.
///   - The providers. On the CI mock (the environment of a throwaway) the provider settings are Test.Bridge.Runner ProviderConfig plus the header. On the
///     real model they are the Config Store entry of ChatAgent as it is stored (Bridge.ConfigStore Details, with its key placeholder, never expanded here)
///     plus the header. The test never reads or prints a key.
///   - The checks (Run). Every turn is answered with a text and no failure; turn 3 is compacted through the guarded path (one compaction Usage row, a
///     reply with SessionRotated 1, no compaction warning, a linked session that starts with the summary). On the mock the log adds: every chat request
///     carries thinking.block_binding.prefix_mismatch_behavior error and the header anthropic-beta, no logged assistant message holds a thinking block, the
///     tool names of turn 2 differ from turn 1's, and one summarizer request was made. A problem is a short fixed line; no problem names a reply text or a
///     setting.
///   - Print writes the CHK line that eval/run.sh reads: CHK|smoke|passed|<problems> or CHK|smoke|failed|<problems>, the number of problems and nothing else.
/// THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): TestOnTheMock needs the CI override's environment and the mock's log. eval/run.sh
/// --release-candidate calls Print(Run(.problems)) on the real model, after the attempts. A failed smoke is recorded in the result and does not change the verdict.
///   - TestOnTheMock: the smoke passes on the mock;
///   - TestPrint: the CHK line for a pass and for a failure.
Class OcuTalon.Test.Eval.ThinkingSmoke Extends %UnitTest.TestCase
{

/// The config name of the shadow runner, which is the agent of its link.
Parameter RUNNER = "ZzSmoke";

/// The owner of the conversation: eval, which no cap or session total counts (AD-20).
Parameter OWNER = "eval";

/// The class of the runner whose adapter forces the thinking rule.
Parameter RUNNERCLASS = "OcuTalon.Test.Eval.ZzSmokeRunner";

/// The agent of turns 1 and 3, and that of turn 2 (the reminder tools alone).
Parameter CHAT = "OcuTalon.Agent.Chat";

Parameter CHATREMINDERS = "OcuTalon.Test.Eval.ZzSmokeChat";

/// The provider header that the thinking-binding controls need, and its value.
Parameter BETAHEADER = "anthropic-beta";

Parameter BETAVALUE = "thinking-binding-controls-2026-08-01";

/// The most seconds that a turn may take.
Parameter TURNSECONDS = 300;

/// The temporary global of the turns' results.
Parameter RESULTS = "^IRIS.Temp.ZzSmoke";

/// The smoke passes on the CI mock: three turns in three jobs, the thinking rule forced on every request, a tool change and a compaction through the
/// guarded path.
Method TestOnTheMock()
{
	Set reason = ##class(OcuTalon.Test.Agent.RunnerFixture).GuardReason()
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit
	}
	Set passed = ..Run(.problems)
	Set listed = ""
	For i = 0:1:problems.%Size() - 1 {
		Set listed = listed _ " [" _ problems.%Get(i) _ "]"
	}
	Do $$$AssertTrue(passed, "the smoke passes:"_listed)
	Do $$$AssertEquals(problems.%Size(), 0, "with no problem")
}

/// Print writes one CHK line: the verdict and the number of problems, and nothing of any reply.
Method TestPrint()
{
	Set ^||OcuTalonSmoke("problems") = 0
	Do $$$AssertEquals(..Line(1), "CHK|smoke|passed|0", "a pass")
	Set ^||OcuTalonSmoke("problems") = 3
	Do $$$AssertEquals(..Line(0), "CHK|smoke|failed|3", "a failure with the number of its problems")
	Kill ^||OcuTalonSmoke
	Do $$$AssertEquals(..Line(0), "CHK|smoke|failed|0", "and a failure that left no count")
}

/// The CHK line of a result, as Print writes it.
ClassMethod Line(passed As %Boolean) As %String
{
	Quit "CHK|smoke|"_$Select(passed: "passed", 1: "failed")_"|"_+$Get(^||OcuTalonSmoke("problems"))
}

/// Writes the CHK line of a result of Run (see the class description), for eval/run.sh.
ClassMethod Print(passed As %Boolean)
{
	Write !, ..Line(passed)
}

/// Runs the smoke and returns 1 when it passed. problems is a dynamic array of short fixed lines, one for each thing that failed; it is empty on a pass.
/// The number of problems is kept for Print in this process.
ClassMethod Run(Output problems As %DynamicArray) As %Boolean
{
	Set problems = []
	Try {
		Do ..Smoke(problems)
	} Catch exception {
		Do problems.%Push("the smoke raised "_$Piece(exception.Name, " ", 1)_" "_exception.Code)
	}
	Set ^||OcuTalonSmoke("problems") = problems.%Size()
	Quit problems.%Size() = 0
}

/// The work of Run: the three turns and their checks, with the link, the sessions and the Usage rows removed before and after.
ClassMethod Smoke(problems As %DynamicArray) [ Private ]
{
	Set mock = (##class(OcuTalon.Test.Agent.RunnerFixture).GuardReason() = "")
	Set config = ..ProviderConfigText(mock, .why)
	If config = "" {
		Do problems.%Push(why)
		Quit
	}
	Do ..Remove()
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).SessionMark()
	Set logMark = $Select(mock: ##class(OcuTalon.Test.Contract.Mock).LogMark(), 1: 0)
	Set eventMark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set token = $Increment(@(..#RESULTS))
	Kill @(..#RESULTS)@(token)
	Set refs = ""
	Try {
		Set inputs = ..Inputs(mock)
		Set agents = $ListBuild(..#CHAT, ..#CHATREMINDERS, ..#CHAT)
		For turn = 1:1:3 {
			Set request = ..NewTurn($List(inputs, turn), turn = 3)
			Set refs = refs _ $ListBuild(request.ItemId)
			Set requests(turn) = request
			Job ..TurnJob(token, turn, $List(agents, turn), request.ItemId, request.DecisionRef, request.Input, request.Compact, config)
			If '..Wait(token, turn) {
				Do problems.%Push("turn "_turn_" did not finish in "_..#TURNSECONDS_" seconds")
				Quit
			}
			Set result(turn) = {}.%FromJSON(@(..#RESULTS)@(token, turn))
			Do ..CheckTurn(problems, turn, result(turn))
		}
		If problems.%Size() = 0 {
			Do ..CheckJobs(problems, .result)
			Do ..CheckCompaction(problems, config, requests(3), result(3), eventMark)
			If mock Do ..CheckLog(problems, logMark, .requests)
		}
	} Catch exception {
		Do problems.%Push("a check raised "_$Piece(exception.Name, " ", 1)_" "_exception.Code)
	}
	Kill @(..#RESULTS)@(token)
	Do ##class(OcuTalon.Test.Agent.RunnerFixture).DropSince(mark)
	Do ..Remove()
	Set position = 0
	While $ListNext(refs, position, ref) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", ref)
	}
}

/// The inputs of the three turns: with a marker for the CI mock, in plain words for the real model.
ClassMethod Inputs(mock As %Boolean) As %List [ Private ]
{
	If mock Quit $ListBuild("[[mock:reminder-list]] Please list my reminders.", "[[mock:reminder-list]] List them again, please.", "[[mock:recall-tell]] Thank you. In one sentence, what did we do?")
	Quit $ListBuild("Please list my reminders with your tools.", "List my reminders again with your tools, please.", "Thank you. In one sentence, what did we do?")
}

/// A turn of the owner for the runner, with the input given (the references of the item and of the decision make it findable in the mock's log).
/// The flagged one has Compact 1, as Decide flags a turn above its threshold.
ClassMethod NewTurn(input As %String, flagged As %Boolean, itemId As %String = "", decisionRef As %String = "") As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = ##class(OcuTalon.Bridge.Msg.Request).%New()
	Set request.Kind = "turn"
	Set request.Provenance = "user"
	Set request.ItemId = $Select(itemId '= "": itemId, 1: ##class(OcuTalon.Bridge.Ids).NewRef())
	Set request.DecisionRef = $Select(decisionRef '= "": decisionRef, 1: ##class(OcuTalon.Bridge.Ids).NewRef())
	Set request.OwnerRef = ..#OWNER
	Set request.Channel = "system"
	Set request.Summary = "Smoke "_request.ItemId
	Set request.Input = $Select(itemId '= "": input, 1: input_" (smoke "_request.ItemId_")")
	Set request.Compact = flagged
	Quit request
}

/// The provider settings of the shadow runner as JSON text, with the beta header added, or "" with the reason in why. On the mock they are
/// Test.Bridge.Runner ProviderConfig; on the real model the Config Store entry of ChatAgent as stored (the key placeholder is kept and never expanded).
ClassMethod ProviderConfigText(mock As %Boolean, Output why As %String) As %String [ Private ]
{
	Set why = ""
	If mock {
		Set settings = {}.%FromJSON(##class(OcuTalon.Test.Bridge.Runner).ProviderConfig())
	} Else {
		Set setting = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("ProviderConfig", "", "ChatAgent", .sc, "Adapter")
		Set entry = $Select($$$ISOK(sc): ##class(OcuTalon.Bridge.ConfigStore).EntryOf(setting), 1: "")
		If entry = "" {
			Set why = "the provider settings of ChatAgent are not a Config Store entry"
			Quit ""
		}
		Set sc = ##class(OcuTalon.Bridge.ConfigStore).Details(entry, .settings)
		If $$$ISERR(sc) || '$IsObject(settings) {
			Set why = "the Config Store entry of ChatAgent cannot be read"
			Quit ""
		}
	}
	Set http = settings."http_config"
	If '$IsObject(http) Set http = {}
	Set headers = http."custom_headers"
	If '$IsObject(headers) Set headers = {}
	Do headers.%Set(..#BETAHEADER, ..#BETAVALUE)
	Do http.%Set("custom_headers", headers)
	Do settings.%Set("http_config", http)
	Quit settings.%ToJSON()
}

/// The shadow runner of the smoke for the agent class, with the provider settings, whose adapter forces the thinking rule.
ClassMethod NewHost(agentClass As %String, config As %String) As OcuTalon.Bridge.Operation.AgentRunner [ Private ]
{
	Quit ##class(OcuTalon.Test.Bridge.Runner).NewRunner(agentClass, "low", config, ..#RUNNER, ..#RUNNERCLASS)
}

/// The job of one turn: answers the request (the item, the decision, the input and the flag, which were made by NewTurn) on a host of its own and
/// leaves the result in the temporary global for the token and the number, last (it is the sign that the job is done): {job, status, text, failure,
/// rotated, tainted, error}.
ClassMethod TurnJob(token As %Integer, number As %Integer, agentClass As %String, itemId As %String, decisionRef As %String, input As %String, flagged As %Boolean, config As %String)
{
	Set out = {"job": ($Job), "status": 0, "text": "", "failure": "", "rotated": 0, "tainted": 0, "error": ""}
	Try {
		Set request = ..NewTurn(input, flagged, itemId, decisionRef)
		Set host = ..NewHost(agentClass, config)
		Set sc = host.OnMessage(request, .reply)
		Do out.%Set("status", +$SYSTEM.Status.IsOK(sc), "number")
		If $$$ISERR(sc) Do out.%Set("error", "status")
		If $IsObject(reply) {
			Set out.text = reply.Text
			Set out.failure = reply.FailureText
			Do out.%Set("rotated", +reply.SessionRotated, "number")
			Do out.%Set("tainted", +reply.Tainted, "number")
		}
	} Catch exception {
		Set out.error = $Piece(exception.Name, " ", 1)_" "_exception.Code
	}
	Set @(..#RESULTS)@(token, number) = out.%ToJSON()
}

/// Waits until the result of the turn's job is there, at most TURNSECONDS. 1 when it is.
ClassMethod Wait(token As %Integer, number As %Integer) As %Boolean [ Private ]
{
	Set deadline = $ZHorolog + ..#TURNSECONDS
	While '$Data(@(..#RESULTS)@(token, number)) && ($ZHorolog < deadline) {
		Hang 0.5
	}
	Quit $Data(@(..#RESULTS)@(token, number)) > 0
}

/// A turn is usable: its job ran and answered, with a text and no failure.
ClassMethod CheckTurn(problems As %DynamicArray, turn As %Integer, result As %DynamicObject) [ Private ]
{
	If result.error '= "" Do problems.%Push("turn "_turn_" failed: "_result.error)
	If 'result.status Do problems.%Push("turn "_turn_" was refused")
	If result.failure '= "" Do problems.%Push("turn "_turn_" came back as a failure")
	If $ZStrip(result.text, "*WC") = "" Do problems.%Push("turn "_turn_" has no text")
	If result.tainted Do problems.%Push("turn "_turn_" was tainted")
}

/// The three turns ran in three jobs, none of them this process.
ClassMethod CheckJobs(problems As %DynamicArray, result) [ Private ]
{
	Kill seen
	For turn = 1:1:3 {
		Set job = result(turn).job
		If (job = "") || (job = $Job) || $Data(seen(job)) Do problems.%Push("turn "_turn_" did not run in a job of its own")
		Set seen(job) = ""
	}
}

/// Turn 3 went through the guarded compaction: one compaction Usage row, SessionRotated 1, no compaction warning, and a linked session that starts with
/// the summary (a system message).
ClassMethod CheckCompaction(problems As %DynamicArray, config As %String, request As OcuTalon.Bridge.Msg.Request, result As %DynamicObject, eventMark As %Integer) [ Private ]
{
	Set rows = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ? AND Agent = 'compaction'", request.DecisionRef)
	Do rows.%Next()
	If rows.%GetData(1) '= 1 Do problems.%Push("turn 3 has "_rows.%GetData(1)_" compaction Usage rows, not 1")
	If result.rotated '= 1 Do problems.%Push("turn 3 was not rotated by a compaction")
	Set warnings = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 3 AND SourceMethod = 'CompactWarning'", eventMark)
	Do warnings.%Next()
	If warnings.%GetData(1) Do problems.%Push("turn 3 fell back to the seeded session ("_warnings.%GetData(1)_" compaction warnings)")
	Set id = ##class(OcuTalon.Bridge.Data.ConversationLink).SessionOf(..#OWNER, ..#RUNNER)
	Set host = ..NewHost(..#CHAT, config)
	Do host.Adapter.BuildAgent()
	Set context = ""
	If id '= "" {
		Do host.Adapter.OpenSession(id, .session)
		If $IsObject(session) Set context = session.GetContext()
		Set session = ""
		Set host.Adapter.Agent.Session = ""
	}
	If '$IsObject(context) || (##class(OcuTalon.Bridge.Compaction).SummaryChars(context) = 0) Do problems.%Push("the linked session does not start with the summary")
}

/// The mock's log of the smoke: every chat request carries the forced thinking rule and the beta header and sends no thinking block back, the tool names
/// of turn 2 differ from turn 1's, and exactly one summarizer request was made.
ClassMethod CheckLog(problems As %DynamicArray, logMark As %Integer, ByRef requests) [ Private ]
{
	Do ##class(OcuTalon.Test.Contract.Mock).LogSince(logMark, .entries)
	Set summarizers = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.path = "/v1/messages") && ($Extract(entry.scenario, 1, 7) = "summary") Set summarizers = summarizers + 1
	}
	If summarizers '= 1 Do problems.%Push("the mock saw "_summarizers_" summarizer requests, not 1")
	For turn = 1:1:3 {
		Set chat = ..OwnRequests(entries, requests(turn).ItemId)
		If 'chat.%Size() Do problems.%Push("the mock logged no chat request of turn "_turn)
		For i = 0:1:chat.%Size() - 1 {
			Set logged = chat.%Get(i)
			Set thinking = logged.request.thinking
			If '$IsObject(thinking) || '$IsObject(thinking."block_binding") || (thinking."block_binding"."prefix_mismatch_behavior" '= "error") Do problems.%Push("a request of turn "_turn_" lacks thinking.block_binding.prefix_mismatch_behavior error")
			If '##class(OcuTalon.Test.Agent.RunnerFixture).Has(logged.%Get("headerNames"), ..#BETAHEADER) Do problems.%Push("a request of turn "_turn_" lacks the header "_..#BETAHEADER)
			If ..HasThinkingBlock(logged.request.messages) Do problems.%Push("a request of turn "_turn_" sends a thinking block back")
		}
		If turn = 1 Set names(1) = $Select(chat.%Size(): ##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(chat.%Get(0)), 1: "")
		If turn = 2 Set names(2) = $Select(chat.%Size(): ##class(OcuTalon.Test.Agent.RunnerFixture).ToolNames(chat.%Get(0)), 1: "")
	}
	If $Get(names(1)) = $Get(names(2)) Do problems.%Push("the tool names of turn 2 do not differ from turn 1's")
}

/// The chat requests of the turn in the log: the model requests that are not summarizer requests and whose newest user message that has text holds the
/// reference of the turn (a later turn's request carries the earlier turns in its history, and a summarizer request their transcript).
ClassMethod OwnRequests(entries As %DynamicArray, ref As %String) As %DynamicArray [ Private ]
{
	Set found = []
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method '= "POST") || (entry.path '= "/v1/messages") || ($Extract(entry.scenario, 1, 7) = "summary") Continue
		If ..NewestUserText(entry.request.messages) [ ref Do found.%Push(entry)
	}
	Quit found
}

/// The text of the newest user message that has text of its own (a message of tool_result blocks has none), or "".
ClassMethod NewestUserText(messages As %DynamicArray) As %String [ Private ]
{
	For i = messages.%Size() - 1:-1:0 {
		Set message = messages.%Get(i)
		If message.role '= "user" Continue
		Set text = ""
		If message.%GetTypeOf("content") = "string" {
			Set text = message.content
		} ElseIf message.%GetTypeOf("content") = "array" {
			Set blocks = message.content.%GetIterator()
			While blocks.%GetNext(, .block) {
				If $IsObject(block) && (block.%GetTypeOf("text") = "string") Set text = text _ block.text
			}
		}
		If $ZStrip(text, "*WC") '= "" Quit
	}
	Quit $Get(text)
}

/// 1 when an assistant message of the list holds a thinking or redacted_thinking block.
ClassMethod HasThinkingBlock(messages As %DynamicArray) As %Boolean [ Private ]
{
	If '$IsObject(messages) Quit 0
	Set has = 0
	Set iterator = messages.%GetIterator()
	While iterator.%GetNext(, .message) {
		If (message.role '= "assistant") || (message.%GetTypeOf("content") '= "array") Continue
		Set blocks = message.content.%GetIterator()
		While blocks.%GetNext(, .block) {
			If $IsObject(block) && ((block.type = "thinking") || (block.type = "redacted_thinking")) Set has = 1
		}
	}
	Quit has
}

/// Removes the link of the owner and the runner, the AI sessions it names and the Usage rows of the runner.
ClassMethod Remove() [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SessionId FROM OcuTalon_Bridge_Data.ConversationLink WHERE OwnerRef = ? AND Agent = ?", ..#OWNER, ..#RUNNER)
	While result.%Next() {
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.ConversationLink WHERE ID = ?", result.%GetData(1))
		Do ##class(%AI.Agent.Session).%DeleteId(result.%GetData(2))
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE Agent = ?", ..#RUNNER)
}

}
