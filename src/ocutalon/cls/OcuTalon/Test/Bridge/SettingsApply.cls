/// Tests that the bridge's settings apply to the next decision of the running production, with no restart (Story 17.4; AD-5, AD-8, AD-18, AD-19, AD-20). THEY RUN
/// IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): they need OcuTalon.Production running with its runner items and the CI override's environment, and the CI mock,
/// which every request goes to; no real provider, key or network is used. Every decide is sent to Decide as a test sends it (Test.Agent.RunnerFixture.Run), and
/// Decide runs in its own job, which reads the values as they are written now. OnAfterOneTest puts back, as the other live tests do: the mock's countdowns, the rows
/// of the requests, the System Default Settings rows that a test wrote (RunnerFixture RememberDefault), the InstanceZone row and the process zone (Test.Bridge.ZoneCase),
/// the Price rows, the capped marks of the days that are today in the test's zones (UnmarkBothDays) and the items that were started again.
///   - TestBudgetNextDecision: Set of DecisionTokenBudget to 1 gives the next decide the fallback budget, with no restart and no request to the mock; Set back to 0
///     gives an answer;
///   - TestCapBelowSpendThenOff: with a fixture Usage row of today that costs 1, Set of the cap to 0.5 makes Budget.State report it and capped, the next decide
///     is the fallback daily_cap and marks the day; Set of the cap to 0 removes the mark, State is not capped, and the next decide is answered;
///   - TestCapRaised: a cap raised above the day's spend removes the mark, and the next decide is answered;
///   - TestZoneMovesTheCapDay: with two zones 25 hours apart and a fixture Usage row inside the day of one and outside the day of the other, the decide is the
///     fallback daily_cap in the first zone and is answered in the second, and State's resetsAt is local midnight of each;
///   - TestPriceAppliesToLaterRows: SetPrice between two decides leaves the first decide's Usage rows at their cost, prices the later rows at the new rates, and each
///     Decision's cost is the sum of its rows;
///   - TestModelTestEachAgent: TestRequest for each of the three agents, sent to Decide, is answered (TestAnswer: answered, no reason), makes one request to the
///     mock with no sampling parameter, and its Usage rows are owned by instance; neither the answer nor the request holds a key;
///   - TestModelTestIsAConnectionTest (DW-771): the test of a decide or diagnose runner passes on any non-empty reply, whatever the runner's reply class says.
///     The diagnosis Test passes on a reply that fails DiagnosisPayload (the marker invalid-reply, and the fixed input as built, which the mock's diagnosis.json
///     answers with a tool call and then a diagnosis that the check refuses), as the triage Test does; each makes its mock requests on the agent's model with no
///     sampling parameter, records a Decision row without outcome text (Fallback 0, tellnow, no reasons, confidence or payload) and its Usage under instance. An
///     empty reply is still the answer 0 with the reason empty. The same diagnose request with an ordinary ItemId is the fallback invalid;
///   - TestModelTestNotRetried: with a second model named, a model test whose first attempt is refused is a fallback with the reason refusal after exactly one mock
///     request, and the same request with an ordinary ItemId is retried (two requests);
///   - TestRestartKeepsValues: the three values, a price and a model survive the installer, the Public, Provider and Production steps' seeding;
///   - TestIntegrationSettingsOps (Rule 1): a SaveSettings for budgets and time-zone, submitted as the web route submits it (origin web_admin), is done, the values
///     are applied and audited with from = old, and the next decide falls back with budget.
Class OcuTalon.Test.Bridge.SettingsApply Extends OcuTalon.Test.Core.InProduction
{

Parameter SESSIONPREFIX = "zzapply";

/// Seconds to wait for a turn through the mock.
Parameter WAIT = 90;

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

Parameter MOCK = "OcuTalon.Test.Contract.Mock";

Parameter SETTINGS = "OcuTalon.Bridge.Settings";

Parameter ZONECASE = "OcuTalon.Test.Bridge.ZoneCase";

Parameter VALUES = "OcuTalon.Test.Bridge.SettingsValues";

/// The model of the first model's price tests, and of the default agents.
Parameter HAIKU = "claude-haiku-5-5";

/// The second model.
Parameter SECOND = "claude-sonnet-5-5";

/// A zone 11 hours behind UTC, and one 14 hours ahead: 25 hours apart.
Parameter ZONEBEHIND = "Pacific/Pago_Pago";

Parameter ZONEAHEAD = "Pacific/Kiritimati";

/// How long to wait for an audit entry, in seconds.
Parameter AUDITSECONDS = 180;

/// 1 while the entries of the runners are pointed at the CI mock key variable.
Property Pointed As %Boolean [ InitialExpression = 0 ];

/// The ItemIds of the requests that the test made.
Property ItemIds As %List;

/// The DecisionRefs of the fixture Usage rows that the test saved.
Property UsageRefs As %List;

/// The countdowns of the mock that the test armed, as a list of markers, to be cleared.
Property Armed As %List;

/// The System Default Settings rows before the test touched them (RunnerFixture RememberDefault), to be put back.
Property SavedRows As %List;

/// The items to start again after the rows are put back.
Property Restarts As %List;

/// The InstanceZone row before the test (ZoneCase ForgetZoneRow), and the process zone.
Property ZoneRow As %List;

Property SavedZone As %String;

/// The Price rows before the test (SettingsValues PriceRows).
Property Prices As %List;

/// The key variable as the test found it, $ListBuild(variable, was set, value), or "".
Property Env As %List;

/// The mark of the saved AI sessions when the test began (RunnerFixture SessionMark).
Property SessionMark As %Integer;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..SessionMark = $ClassMethod(..#FIXTURE, "SessionMark")
	Set ..SavedZone = $ClassMethod(..#ZONECASE, "CurrentZone")
	Set ..ZoneRow = $ClassMethod(..#ZONECASE, "ForgetZoneRow")
	Kill ^||OcuTalon.Bridge.Time
	Set ..Prices = $ClassMethod(..#VALUES, "PriceRows")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set fixture = ..#FIXTURE
	If ..Missing = "" {
		Set position = 0
		While $ListNext(..Armed, position, marker) {
			Do $ClassMethod(..#MOCK, "Arm", marker, "")
		}
		Set ..Armed = ""
		Do $ClassMethod(fixture, "DropSince", ..SessionMark)
		Set position = 0
		While $ListNext(..ItemIds, position, itemId) {
			Do $ClassMethod(fixture, "DeleteSteps", itemId)
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Decision WHERE ItemId = ?", itemId)
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE ItemId = ?", itemId)
		}
		Set ..ItemIds = ""
		Set position = 0
		While $ListNext(..UsageRefs, position, ref) {
			Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ?", ref)
		}
		Set ..UsageRefs = ""
		Do $ClassMethod(fixture, "RestoreDefaults", ..SavedRows)
		Set ..SavedRows = ""
		Do $ClassMethod(..#VALUES, "PutPriceRows", ..Prices)
		Set position = 0
		While $ListNext(..Restarts, position, item) {
			Do $ClassMethod(fixture, "Restart", ..#PRODUCTION_"||"_item)
		}
		Set ..Restarts = ""
	}
	If ..Env '= "" {
		If $List(..Env, 2) {
			Do $ClassMethod("OcuTalon.Test.Agent.KeyScan", "SetEnv", $List(..Env, 1), $List(..Env, 3))
		} Else {
			Do $ClassMethod("OcuTalon.Test.Agent.KeyScan", "UnsetEnv", $List(..Env, 1))
		}
		Set ..Env = ""
	}
	Do $ClassMethod(..#ZONECASE, "RestoreZoneRow", ..ZoneRow)
	Kill ^||OcuTalon.Bridge.Time
	Do $ClassMethod(..#ZONECASE, "PutZone", ..SavedZone)
	Do ..UnmarkBothDays()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Set ..Refs = ##class(OcuTalon.Test.Data.Fixture).AdoptTurns(..Sessions, ..Refs)
	If ..Pointed && $ClassMethod(..#FIXTURE, "Running") {
		Set ..Pointed = 0
		Do $ClassMethod(..#FIXTURE, "RestoreKeys", ..Runners())
	}
	Quit ##super()
}

/// A new token budget applies to the next decision of the running Decide job: the fallback budget, with nothing sent to the mock, and no restart.
Method TestBudgetNextDecision()
{
	If '..Prepare() Quit
	Set class = ..#SETTINGS
	Do ..Remember("Decide", "DecisionTokenBudget")
	Set was = $ClassMethod(class, "Values").%Get("DecisionTokenBudget")
	Do $$$AssertStatusOK($ClassMethod(class, "Set", "DecisionTokenBudget", "1", .old), "the token budget is 1")
	Do $$$AssertEquals(old, was, "old is the earlier text")
	Do $$$AssertEquals($ClassMethod(class, "Values").%Get("DecisionTokenBudget"), "1", "Values shows it")
	Set request = ..Ask("decide", "Triage this item.", .ref)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Run", request, .answer, .session), "Decide answers the decide with no restart")
	Set row = $ClassMethod(..#FIXTURE, "DecisionOf", ref, "decide")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "FallbackProblems", answer, row, "decide", "budget"), "", "it is the fallback budget, in the answer, its XML and the row")
	Do ..AssertSent("TriageAgent", mark, 0, "over the budget: ")
	Do $$$AssertStatusOK($ClassMethod(class, "Set", "DecisionTokenBudget", "0", .old), "the token budget is 0 again")
	Do $$$AssertEquals(old, "1", "old is 1")
	Set request = ..Ask("decide", "Triage this item.", .ref)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Run", request, .answer, .session), "Decide answers the next decide")
	Do $$$AssertEquals($Select($IsObject(answer): answer.Fallback, 1: "none"), 0, "and it is no fallback")
	Do ..AssertSent("TriageAgent", mark, 1, "with the budget off: ")
}

/// A cap below the day's spend, then off: the fallback daily_cap with its mark, and no fallback once the cap is off.
Method TestCapBelowSpendThenOff()
{
	If '..Prepare() Quit
	Set class = ..#SETTINGS
	Set today = ..Today()
	Do ..Remember("Decide", "DailyCostCapUSD")
	Do ..AddSpend(1, $ClassMethod("OcuTalon.Bridge.Time", "NowUtc"))
	Do $$$AssertStatusOK($ClassMethod(class, "Set", "DailyCostCapUSD", "0.5"), "the cap is 0.5, below the day's spend")
	Set state = ##class(OcuTalon.Bridge.Budget).State()
	Do $$$AssertEquals(+state.cap_"|"_state.capped, ".5|1", "Budget.State reports the cap and capped")
	Set request = ..Ask("decide", "Triage this item.", .ref)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Run", request, .answer, .session), "Decide answers the decide")
	Set row = $ClassMethod(..#FIXTURE, "DecisionOf", ref, "decide")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "FallbackProblems", answer, row, "decide", "daily_cap"), "", "it is the fallback daily_cap")
	Do ..AssertSent("TriageAgent", mark, 0, "over the cap: ")
	Do $$$AssertTrue($Data(^OcuTalonBP.UsageCapped(today)) > 0, "and the day is marked")
	Do $$$AssertStatusOK($ClassMethod(class, "Set", "DailyCostCapUSD", "0", .old), "the cap is turned off")
	Do $$$AssertEquals(old, "0.5", "old is 0.5")
	Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(today)), 0, "the mark is gone")
	Set state = ##class(OcuTalon.Bridge.Budget).State()
	Do $$$AssertEquals(+state.cap_"|"_state.capped, "0|0", "State reports no cap and not capped")
	Set request = ..Ask("decide", "Triage this item.", .ref)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Run", request, .answer, .session), "Decide answers the next decide")
	Do $$$AssertEquals($Select($IsObject(answer): answer.Fallback, 1: "none"), 0, "and it is answered")
	Do ..AssertSent("TriageAgent", mark, 1, "with the cap off: ")
}

/// A cap raised above the day's spend removes the mark, and the next decide is answered.
Method TestCapRaised()
{
	If '..Prepare() Quit
	Set class = ..#SETTINGS
	Set today = ..Today()
	Do ..Remember("Decide", "DailyCostCapUSD")
	Do ..AddSpend(1, $ClassMethod("OcuTalon.Bridge.Time", "NowUtc"))
	Do $$$AssertStatusOK($ClassMethod(class, "Set", "DailyCostCapUSD", "0.5"), "the cap is 0.5, below the day's spend")
	Set request = ..Ask("decide", "Triage this item.", .ref)
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Run", request, .answer, .session), "Decide answers the decide")
	Do $$$AssertEquals($Select($IsObject(answer): answer.FallbackReason, 1: "none"), "daily_cap", "it is the fallback daily_cap")
	Do $$$AssertTrue($Data(^OcuTalonBP.UsageCapped(today)) > 0, "and the day is marked")
	Set spent = ##class(OcuTalon.Bridge.Budget).State().spent
	Set raised = $FNumber(spent + 4, "", 2)
	Do $$$AssertStatusOK($ClassMethod(class, "Set", "DailyCostCapUSD", raised, .old), "the cap is raised to "_raised_", above the spend "_spent)
	Do $$$AssertEquals(old, "0.5", "old is 0.5")
	Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(today)), 0, "the mark is gone")
	Set state = ##class(OcuTalon.Bridge.Budget).State()
	Do $$$AssertEquals(+state.cap_"|"_state.capped, +raised_"|0", "State reports the new cap and not capped")
	Set request = ..Ask("decide", "Triage this item.", .ref)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Run", request, .answer, .session), "Decide answers the next decide")
	Do $$$AssertEquals($Select($IsObject(answer): answer.Fallback, 1: "none"), 0, "and it is answered")
	Do ..AssertSent("TriageAgent", mark, 1, "under the raised cap: ")
}

/// The cap's day is the day of the instance zone: a spend inside the day of one zone and outside the day of a zone 25 hours away counts in the first only.
Method TestZoneMovesTheCapDay()
{
	If '..Prepare() Quit
	Set class = ..#SETTINGS
	Set time = "OcuTalon.Bridge.Time"
	Do ..Remember("Decide", "DailyCostCapUSD")
	Set starts = ""
	For zone = ..#ZONEBEHIND, ..#ZONEAHEAD {
		Do $$$AssertStatusOK($ClassMethod(class, "Set", "InstanceZone", zone), "the instance zone is "_zone)
		Set starts = starts _ $ListBuild($ClassMethod(time, "DayStartUtc", $ClassMethod(time, "LocalDate", $ClassMethod(time, "NowUtc"))))
	}
	Set behindFirst = ($List(starts, 1) '] $List(starts, 2))
	Set first = $Select(behindFirst: ..#ZONEBEHIND, 1: ..#ZONEAHEAD)
	Set second = $Select(behindFirst: ..#ZONEAHEAD, 1: ..#ZONEBEHIND)
	Set earlier = $Select(behindFirst: $List(starts, 1), 1: $List(starts, 2))
	Set at = $ClassMethod(time, "PlusSeconds", earlier, 1)
	Do $$$AssertTrue(at '= "", "a Usage row is placed at "_at_", the first second of the day that starts first")
	Do ..AddSpend(1, at)
	Do $$$AssertStatusOK($ClassMethod(class, "Set", "DailyCostCapUSD", "0.5"), "the cap is 0.5")

	Do $$$AssertStatusOK($ClassMethod(class, "Set", "InstanceZone", first), "the zone is "_first)
	Do ..UnmarkBothDays()
	Set state = ##class(OcuTalon.Bridge.Budget).State()
	Do $$$AssertEquals(state.resetsAt, $ClassMethod(time, "DayEndUtc", $ClassMethod(time, "LocalDate", $ClassMethod(time, "NowUtc"))), "resetsAt is the end of the day of "_first)
	Do $$$AssertEquals($Piece(state.resetsAt, "T", 2), $Select(first = ..#ZONEAHEAD: "10:00:00Z", 1: "11:00:00Z"), "which is its local midnight")
	Set request = ..Ask("decide", "Triage this item.", .ref)
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Run", request, .answer, .session), "Decide answers the decide in "_first)
	Do $$$AssertEquals($Select($IsObject(answer): answer.FallbackReason, 1: "none"), "daily_cap", "the row is inside the day of "_first_", so the decide is the fallback daily_cap")
	Set firstEnd = state.resetsAt

	Do $$$AssertStatusOK($ClassMethod(class, "Set", "InstanceZone", second), "the zone is "_second)
	Do ..UnmarkBothDays()
	Set state = ##class(OcuTalon.Bridge.Budget).State()
	Do $$$AssertEquals(state.resetsAt, $ClassMethod(time, "DayEndUtc", $ClassMethod(time, "LocalDate", $ClassMethod(time, "NowUtc"))), "resetsAt is the end of the day of "_second)
	Do $$$AssertEquals($Piece(state.resetsAt, "T", 2), $Select(second = ..#ZONEAHEAD: "10:00:00Z", 1: "11:00:00Z"), "which is its local midnight")
	Do $$$AssertTrue(state.resetsAt '= firstEnd, "and not the end of the day of "_first)
	Do $$$AssertEquals(state.capped, 0, "the row is outside the day of "_second_", so the day is not capped")
	Set request = ..Ask("decide", "Triage this item.", .ref)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Run", request, .answer, .session), "Decide answers the decide in "_second)
	Do $$$AssertEquals($Select($IsObject(answer): answer.Fallback, 1: "none"), 0, "and answers it")
	Do ..AssertSent("TriageAgent", mark, 1, "in "_second_": ")
}

/// A price edit between two decides: the earlier rows keep their cost, the later rows are priced at the new rates, and each decision's cost is the sum of its rows.
Method TestPriceAppliesToLaterRows()
{
	If '..Prepare() Quit
	Set class = ..#SETTINGS
	Set fixture = ..#FIXTURE
	Set request = ..Ask("decide", "Triage this item.", .first)
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", request, .answer, .session), "the first decide is answered")
	Set firstRef = $Select($IsObject(answer): answer.DecisionRef, 1: "")
	Set rowsBefore = ..UsageOf(firstRef)
	Do $$$AssertTrue(rowsBefore '= "", "its Usage rows are recorded")
	Set costBefore = ..CostSum(firstRef)
	Set sc = $ClassMethod(class, "SetPrice", ..#HAIKU, {"input": 0.2, "output": 1}, .old)
	Do $$$AssertStatusOK(sc, "the prices of "_..#HAIKU_" are changed")
	Do $$$AssertEquals(old.%Size(), 7, "old holds seven values")
	Do $$$AssertEquals(..CostSum(firstRef), costBefore, "the rows of the first decide keep their cost")
	Do $$$AssertEquals(..UsageOf(firstRef), rowsBefore, "and everything else of them")
	Set request = ..Ask("decide", "Triage this item.", .second)
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", request, .answer, .session), "the second decide is answered")
	Set secondRef = $Select($IsObject(answer): answer.DecisionRef, 1: "")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT InputTokens, OutputTokens, CacheReadTokens, CacheWriteTokens, CostUSD FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ? ORDER BY ID", secondRef)
	Set checked = 0
	While result.%Next() {
		Set checked = checked + 1
		Set prompt = result.%GetData(1) - result.%GetData(3) - result.%GetData(4)
		Set expected = $Number(((prompt * 0.2) + (result.%GetData(3) * old.cacheRead) + (result.%GetData(4) * old.cacheWrite) + (result.%GetData(2) * 1)) / 1000000, 6)
		Do $$$AssertEquals(result.%GetData(5), expected, "a later row is priced at 0.2 and 1: "_expected)
	}
	Do $$$AssertTrue(checked '< 1, "the later decide has Usage rows: "_checked)
	For ref = firstRef, secondRef {
		Set row = ##class(OcuTalon.Bridge.Data.Decision).RefIndexOpen(ref)
		Do $$$AssertTrue($IsObject(row), "the Decision row of "_ref_" exists")
		If $IsObject(row) Do $$$AssertEquals(row.CostUSD, ..CostSum(ref), "its cost is the sum of its rows")
	}
	Do $$$AssertTrue(..CostSum(secondRef) '= costBefore, "the two decisions cost different amounts under different prices")
}

/// The model test of each agent, sent to Decide. The request is the one TestRequest builds; the diagnosis and chat requests get the mock marker of a one-reply
/// scenario in front of the fixed input, so that each test is one mock request: the default scripts of those two agents take a tool call first (chat.json and
/// diagnosis.json).
Method TestModelTestEachAgent()
{
	If '..Prepare() Quit
	Set class = ..#SETTINGS
	Set fixture = ..#FIXTURE
	For agent = "TriageAgent", "DiagnosisAgent", "ChatAgent" {
		Set label = agent_": "
		Do $$$AssertStatusOK($ClassMethod(class, "TestRequest", agent, .request), label_"the test request is built")
		Set marker = $Select(agent = "DiagnosisAgent": "diagnosis-unknown", agent = "ChatAgent": "recall-tell", 1: "")
		If marker '= "" Set request.Input = "[[mock:"_marker_"]] "_request.Input
		Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
		Set mark = $ClassMethod(..#MOCK, "LogMark")
		Set started = $ZHorolog
		Set sc = $ClassMethod(fixture, "Run", request, .response, .session)
		Set millis = ($ZHorolog - started * 1000) \ 1
		Do $$$AssertStatusOK(sc, label_"Decide answers it")
		Set answer = $ClassMethod(class, "TestAnswer", response, millis)
		Do $$$AssertEquals(answer.answered_"|"_answer.reason, "1|", label_"the model answered: "_answer.%ToJSON())
		Do $$$AssertTrue((answer.seconds > 0) && (answer.seconds < 30), label_"in "_answer.seconds_" seconds")
		Do $$$AssertStatusOK($ClassMethod(fixture, "Drain", agent), label_"the runner is drained")
		Do $$$AssertStatusOK($ClassMethod(..#MOCK, "LogSince", mark, .entries), label_"the mock's log is read")
		Set chosen = ##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(agent, ##class(Ens.Director).GetActiveProductionName())
		Set sent = 0
		Set onModel = 0
		Set sampling = 0
		Set iterator = entries.%GetIterator()
		While iterator.%GetNext(, .entry) {
			If (entry.method = "POST") && (entry.path = "/v1/messages") {
				Set sent = sent + 1
				If entry.model = chosen Set onModel = onModel + 1
				If entry.request.%IsDefined("temperature") || entry.request.%IsDefined("top_p") || entry.request.%IsDefined("top_k") Set sampling = 1
			}
		}
		Do $$$AssertEquals(sent_"|"_onModel_"|"_sampling, "1|1|0", label_"one request reached the mock, for the agent's model "_chosen_", with no sampling parameter")
		Set ref = response.DecisionRef
		Set owners = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*), SUM(CASE WHEN OwnerRef = 'instance' THEN 1 ELSE 0 END) FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ?", ref)
		Do owners.%Next()
		Do $$$AssertTrue(owners.%GetData(1) '< 1, label_"its Usage rows are recorded: "_owners.%GetData(1))
		Do $$$AssertEquals(owners.%GetData(2), owners.%GetData(1), label_"and all are owned by instance")
		Set json = answer.%ToJSON()_request.Input_request.Summary
		Do $$$AssertTrue(($Find(json, "sk-") = 0) && ($Find(json, "AIza") = 0) && ($Find(json, "@{") = 0), label_"the answer and the request hold no key")
	}
}

/// The settings model Test is a connection test for a decide or diagnose runner (DW-771; the Conventions row "Settings model Test"): any non-empty reply is an
/// answer, and the reply is never checked against the runner's ReplyClass.
Method TestModelTestIsAConnectionTest()
{
	If '..Prepare() Quit
	Set fixture = ..#FIXTURE
	Do ..Connect("DiagnosisAgent", "invalid-reply", "diagnosis, a reply that fails DiagnosisPayload: ", 0, 1, .response, .request)
	Do ..Connect("TriageAgent", "invalid-reply", "triage, a reply that fails DecisionPayload: ", 0, 1, .response, .request)
	Do ..Connect("DiagnosisAgent", "", "diagnosis, the fixed input as built: ", 0, "", .response, .request)
	Do ..Connect("DiagnosisAgent", "empty", "diagnosis, an empty reply: ", 0, 1, .response, .request)
	Do ..Connect("DiagnosisAgent", "invalid-reply", "not a test, the same diagnose request with an ordinary ItemId: ", 1, 1, .response, .request)
	Set row = $ClassMethod(fixture, "DecisionOf", request.ItemId, request.Kind)
	Do $$$AssertTrue($IsObject(row), "the ordinary request has a Decision row")
	If $IsObject(row) Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason_"|"_row.Payload, "1|invalid|", "it is the fallback invalid, with no payload")
}

/// One request of the agent's own kind from TestRequest, with the mock marker in front of its input when there is one and a fresh ordinary ItemId when ordinary
/// is 1, sent to Decide; label says which. The mock took requests mock requests (all when it is empty), every one for the agent's model and with no sampling
/// parameter. A test request that is answered records a Decision row that holds no model text, and its Usage is owned by instance; an empty reply is the answer
/// 0 with the reason empty after one request; an ordinary request is the fallback invalid. response and request are the answer and the request sent.
Method Connect(agent As %String, marker As %String, label As %String, ordinary As %Boolean, requests As %Integer, Output response As %Persistent, Output request As OcuTalon.Bridge.Msg.Request) [ Private ]
{
	Set class = ..#SETTINGS
	Set fixture = ..#FIXTURE
	Do $$$AssertStatusOK($ClassMethod(class, "TestRequest", agent, .request), label_"the test request is built")
	If marker '= "" Set request.Input = "[[mock:"_marker_"]] "_request.Input
	If ordinary Set request.ItemId = $ClassMethod("OcuTalon.Bridge.Ids", "NewRef")
	Do $$$AssertEquals($ClassMethod(class, "IsTest", request), 'ordinary, label_"IsTest says "_('ordinary))
	Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set started = $ZHorolog
	Set sc = $ClassMethod(fixture, "Run", request, .response, .session)
	Set millis = ($ZHorolog - started * 1000) \ 1
	Do $$$AssertStatusOK(sc, label_"Decide answers it")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Drain", agent), label_"the runner is drained")
	Do $$$AssertStatusOK($ClassMethod(..#MOCK, "LogSince", mark, .entries), label_"the mock's log is read")
	Set chosen = ##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(agent, ##class(Ens.Director).GetActiveProductionName())
	Set sent = 0
	Set onModel = 0
	Set sampling = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.path = "/v1/messages") {
			Set sent = sent + 1
			If entry.model = chosen Set onModel = onModel + 1
			If entry.request.%IsDefined("temperature") || entry.request.%IsDefined("top_p") || entry.request.%IsDefined("top_k") Set sampling = 1
		}
	}
	If requests '= "" Do $$$AssertEquals(sent, requests, label_requests_" request(s) reached the mock")
	Do $$$AssertTrue(sent '< 1, label_"at least one request reached the mock: "_sent)
	Do $$$AssertEquals(onModel_"|"_sampling, sent_"|0", label_"every request was for the agent's model "_chosen_", with no sampling parameter")
	Set answer = $ClassMethod(class, "TestAnswer", response, millis)
	If ordinary {
		Do $$$AssertEquals(response.Fallback_"|"_response.FallbackReason, "1|invalid", label_"the answer is the fallback invalid")
		Quit
	}
	If marker = "empty" {
		Do $$$AssertEquals(answer.answered_"|"_answer.reason, "0|empty", label_"an empty reply is not an answer: "_answer.%ToJSON())
		Quit
	}
	Do $$$AssertEquals(answer.answered_"|"_answer.reason, "1|", label_"the model answered: "_answer.%ToJSON())
	Set row = $ClassMethod(fixture, "DecisionOf", request.ItemId, request.Kind)
	Do $$$AssertTrue($IsObject(row), label_"one Decision row is recorded")
	If $IsObject(row) Do $$$AssertEquals(row.Fallback_"|"_row.FallbackReason_"|"_row.Outcome_"|"_row.Reasons_"|"_row.Confidence_"|"_row.Payload, "0||tellnow|||", label_"and it holds no model text")
	Set owners = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*), SUM(CASE WHEN OwnerRef = 'instance' THEN 1 ELSE 0 END) FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ?", response.DecisionRef)
	Do owners.%Next()
	Do $$$AssertTrue(owners.%GetData(1) '< 1, label_"its Usage rows are recorded: "_owners.%GetData(1))
	Do $$$AssertEquals(owners.%GetData(2), owners.%GetData(1), label_"and all are owned by instance")
}

/// A model test is never retried on the second model; the same request with an ordinary ItemId is.
Method TestModelTestNotRetried()
{
	If '..Prepare() Quit
	Set class = ..#SETTINGS
	Set fixture = ..#FIXTURE
	Do ..Put("TriageAgent", "RetryItem", "TriageAgentRetry")
	Do ..Put("TriageAgentRetry", "Model", ..#SECOND)
	Set ..Restarts = ..Restarts _ $ListBuild("TriageAgentRetry")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Restart", ..#PRODUCTION_"||TriageAgentRetry"), "TriageAgentRetry is started again with the second model")
	Set values = $ClassMethod(class, "Values").agents.TriageAgent
	Do $$$AssertEquals(values.secondProvider_"|"_values.secondModel, "anthropic|"_..#SECOND, "Values names the second model")

	Do ..Arm("retry-refusal", 1)
	Do $$$AssertStatusOK($ClassMethod(class, "TestRequest", "TriageAgent", .request), "the test request is built")
	Set request.Input = "[[mock:retry-refusal]] "_request.Input
	Set ..ItemIds = ..ItemIds _ $ListBuild(request.ItemId)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Set started = $ZHorolog
	Set sc = $ClassMethod(fixture, "Run", request, .response, .session)
	Set millis = ($ZHorolog - started * 1000) \ 1
	Do $$$AssertStatusOK(sc, "Decide answers the model test")
	Set answer = $ClassMethod(class, "TestAnswer", response, millis)
	Do $$$AssertEquals(answer.answered_"|"_answer.reason, "0|refusal", "the first model's refusal is the answer: "_answer.%ToJSON())
	Do ..AssertSent("TriageAgent", mark, 1, "the model test, the first model: ", ..#HAIKU)
	Do ..AssertSent("TriageAgentRetry", mark, 0, "the model test, the second model: ", ..#SECOND)
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", $ClassMethod(fixture, "Headers", session, "Decide"), "TriageAgentRetry"), 0, "Decide sent nothing to the retry runner")

	Do ..Arm("retry-refusal", 1)
	Do $$$AssertStatusOK($ClassMethod(class, "TestRequest", "TriageAgent", .ordinary), "the same request is built")
	Set ordinary.Input = "[[mock:retry-refusal]] "_ordinary.Input
	Set ordinary.ItemId = $ClassMethod("OcuTalon.Bridge.Ids", "NewRef")
	Set ..ItemIds = ..ItemIds _ $ListBuild(ordinary.ItemId)
	Do $$$AssertNotTrue($ClassMethod(class, "IsTest", ordinary), "with an ordinary ItemId it is no test")
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Run", ordinary, .response, .session), "Decide answers it")
	Do $$$AssertEquals($ClassMethod(fixture, "CountTo", $ClassMethod(fixture, "Headers", session, "Decide"), "TriageAgentRetry"), 1, "Decide sent the retry to the second model")
	Do ..AssertSent("TriageAgentRetry", mark, 1, "the ordinary request, the second model: ", ..#SECOND)
}

/// The three values, a price and a model survive a restart and an upgrade: the installer, the Public, Provider and Production steps seed none of them again.
Method TestRestartKeepsValues()
{
	If '..Prepare() Quit
	Set class = ..#SETTINGS
	Set production = ..#PRODUCTION
	Do ..Remember("Decide", "DecisionTokenBudget")
	Do ..Remember("Decide", "DailyCostCapUSD")
	Do ..Remember("TriageAgent", "Model")
	Set ..Restarts = ..Restarts _ $ListBuild("TriageAgent")
	Do ..UseKeyVariable()
	Do $$$AssertStatusOK($ClassMethod(class, "Set", "DecisionTokenBudget", "5000"), "the budget is 5000")
	Do $$$AssertStatusOK($ClassMethod(class, "Set", "DailyCostCapUSD", "7.50"), "the cap is 7.50")
	Do $$$AssertStatusOK($ClassMethod(class, "Set", "InstanceZone", "Pacific/Kiritimati"), "the zone is Pacific/Kiritimati")
	Do $$$AssertStatusOK($ClassMethod(class, "SetPrice", ..#HAIKU, {"input": 0.2}), "the input price of "_..#HAIKU_" is 0.2")
	Do $$$AssertStatusOK($ClassMethod(class, "SetModel", "TriageAgent", "anthropic", ..#SECOND, 0, .oldModel), "TriageAgent runs on "_..#SECOND)
	Set before = ..Kept()
	Do $$$AssertEquals($ClassMethod(class, "Values").%Get("DecisionTokenBudget")_"|"_$ClassMethod(class, "Values").%Get("DailyCostCapUSD")_"|"_$ClassMethod(class, "Values").%Get("InstanceZone"), "5000|7.5|Pacific/Kiritimati", "Values shows the three values")
	Do $$$AssertStatusOK(##class(OcuTalon.Bridge.Installer).Run(), "the bridge installer runs")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Public).Run(), "the Public step runs")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Public).Ready(), "and sets readiness again")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Provider).Run(), "the Provider step runs")
	Set ..Pointed = 0
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Production).SeedModels(production), "the Production step seeds the models")
	Do $$$AssertEquals(..Kept(), before, "every value, the price row, the entry's provider and the Model row are unchanged")
	Set values = $ClassMethod(class, "Values")
	Do $$$AssertEquals(values.%Get("DecisionTokenBudget")_"|"_values.%Get("DailyCostCapUSD")_"|"_values.%Get("InstanceZone"), "5000|7.5|Pacific/Kiritimati", "and Values shows them")
	Do $$$AssertEquals(values.agents.TriageAgent.model, ..#SECOND, "TriageAgent still runs on the second model")
}

/// A SaveSettings for budgets and time-zone, submitted as Web.Api.SaveSection submits it, with Lane B's SettingsOps unchanged.
Method TestIntegrationSettingsOps()
{
	If '..Prepare() Quit
	Set class = ..#SETTINGS
	Do ..Remember("Decide", "DecisionTokenBudget")
	Do ..Remember("Decide", "DailyCostCapUSD")
	Set was = $ClassMethod(class, "Values")
	Set wasBudget = was.%Get("DecisionTokenBudget")
	Set wasCap = was.%Get("DailyCostCapUSD")
	Set wasZone = was.%Get("InstanceZone")
	Set ref = ..Session("integration")
	Set since = ##class(OcuTalon.Test.Bridge.AuditLog).Now()

	Set result = ..Submit("budgets", {"DecisionTokenBudget": 1, "DailyCostCapUSD": "0.5"}, ref)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the budgets save is done")
	Set result = ..Submit("time-zone", {"InstanceZone": "Pacific/Kiritimati"}, ref)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the time-zone save is done")
	Set values = ##class(OcuTalon.Core.SettingsOps).Values()
	Do $$$AssertEquals(values.bridge.DecisionTokenBudget_"|"_values.bridge.DailyCostCapUSD_"|"_values.bridge.InstanceZone_"|"_values.instanceZone, "1|0.5|Pacific/Kiritimati|Pacific/Kiritimati", "SettingsOps.Values shows the three values")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(since, "OcuTalon", "Settings", "", ref, "", 3, ..#AUDITSECONDS)
	Do $$$AssertEquals(entries.%Size(), 3, "one Settings entry is in the audit log for each value")
	Set seen = ""
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		Set data = entry.data
		Set seen = seen _ $ListBuild(data.setting_"|"_data.from_"|"_data.to)
	}
	Do $$$AssertTrue($ListFind(seen, "DecisionTokenBudget|"_wasBudget_"|1"), "the budget entry has from = the value Set replaced")
	Do $$$AssertTrue($ListFind(seen, "DailyCostCapUSD|"_wasCap_"|0.5"), "the cap entry has from = the value Set replaced")
	Do $$$AssertTrue($ListFind(seen, "InstanceZone|"_wasZone_"|Pacific/Kiritimati"), "the zone entry has from = the value Set replaced")

	Set request = ..Ask("decide", "Triage this item.", .itemRef)
	Set mark = $ClassMethod(..#MOCK, "LogMark")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Run", request, .answer, .session), "Decide answers the decide")
	Set row = $ClassMethod(..#FIXTURE, "DecisionOf", itemRef, "decide")
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "FallbackProblems", answer, row, "decide", "budget"), "", "the next decide falls back with budget")
	Do ..AssertSent("TriageAgent", mark, 0, "over the budget: ")

	Set today = ..Today()
	Do $ClassMethod("OcuTalon.Bridge.Budget", "MarkCapped")
	Do $$$AssertTrue($Data(^OcuTalonBP.UsageCapped(today)) > 0, "today is marked as capped")
	Set result = ..Submit("budgets", {"DecisionTokenBudget": 1, "DailyCostCapUSD": "9000"}, ref)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a cap raised above the spend is done")
	Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(today)), 0, "and the production job removed the mark")

	Set result = ..Submit("budgets", {"DecisionTokenBudget": (wasBudget), "DailyCostCapUSD": (wasCap)}, ref)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the budgets are put back the same way")
	Set result = ..Submit("time-zone", {"InstanceZone": (wasZone)}, ref)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "and so is the zone")
	Set now = $ClassMethod(class, "Values")
	Do $$$AssertEquals(now.%Get("DecisionTokenBudget")_"|"_now.%Get("DailyCostCapUSD")_"|"_now.%Get("InstanceZone"), wasBudget_"|"_wasCap_"|"_wasZone, "and Values shows the earlier values")
}

/// --- helpers ---
/// Sets the key variable of Anthropic in this process to a text that is no key, so that CheckModel finds the key set; OnAfterOneTest puts the variable back. The runner
/// jobs never see it.
Method UseKeyVariable() [ Private ]
{
	Set scan = "OcuTalon.Test.Agent.KeyScan"
	Set variable = "ANTHROPIC_API_KEY"
	If ..Env = "" Set ..Env = $ListBuild(variable, $ClassMethod(scan, "HasEnv", variable), $SYSTEM.Util.GetEnviron(variable))
	Do $ClassMethod(scan, "SetEnv", variable, "ocutalon-zz-not-a-key")
}

/// 1 when the production runs with every item in the CI override's environment and the entries of the runners are pointed at the mock key variable.
Method Prepare() As %Boolean [ Private ]
{
	If '..Guard() Quit 0
	Set reason = $ClassMethod(..#FIXTURE, "ReadyReason")
	If reason '= "" {
		Do $$$AssertTrue(0, reason)
		Quit 0
	}
	Kill ^OcuTalonBP.UsageCapped(..Today())
	If '..Pointed {
		Set ..Pointed = 1
		Set sc = $ClassMethod(..#FIXTURE, "PointKeys", ..Runners())
		Do $$$AssertStatusOK(sc, "the entries of the runners are pointed at the CI mock key variable")
		If $$$ISERR(sc) Quit 0
	}
	Quit 1
}

/// The first runner items and the retry runner items, comma-separated.
ClassMethod Runners() As %String [ Private ]
{
	Quit $Parameter(..#FIXTURE, "RUNNERS")_","_$Parameter(..#FIXTURE, "RETRYRUNNERS")
}

/// Today's date in the instance zone.
ClassMethod Today() As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Time).LocalDate(##class(OcuTalon.Bridge.Time).NowUtc())
}

/// Removes the capped mark of the days that are today in the two zones of the test (whatever the process zone is now).
Method UnmarkBothDays() [ Private ]
{
	Set now = ##class(OcuTalon.Bridge.Time).NowUtc()
	Kill ^OcuTalonBP.UsageCapped(##class(OcuTalon.Bridge.Time).LocalDate(now))
	Kill ^OcuTalonBP.UsageCapped($Piece(now, "T", 1))
	Kill ^OcuTalonBP.UsageCapped($Piece(##class(OcuTalon.Bridge.Time).PlusSeconds(now, -39600), "T", 1))
	Kill ^OcuTalonBP.UsageCapped($Piece(##class(OcuTalon.Bridge.Time).PlusSeconds(now, 50400), "T", 1))
}

/// Remembers the System Default Settings row of the setting of the item, once, for OnAfterOneTest.
Method Remember(item As %String, setting As %String) [ Private ]
{
	Set saved = ..SavedRows
	Do $ClassMethod(..#FIXTURE, "RememberDefault", .saved, item, setting)
	Set ..SavedRows = saved
}

/// Puts the System Default Settings row of the setting of the item (RunnerFixture PutDefault) and remembers the row that was there.
Method Put(item As %String, setting As %String, value As %String) [ Private ]
{
	Do ..Remember(item, setting)
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "PutDefault", item, setting, value), "the setting "_setting_" of "_item_" is '"_value_"'")
}

/// Arms the countdown of the mock for the marker with the number of requests that get its first reply, and remembers the marker for OnAfterOneTest.
Method Arm(marker As %String, remaining As %Integer) [ Private ]
{
	Set ..Armed = ..Armed _ $ListBuild(marker)
	Do $$$AssertStatusOK($ClassMethod(..#MOCK, "Arm", marker, remaining), "the countdown of "_marker_" is armed with "_remaining)
}

/// An untrusted request of the kind with the text, whose ItemId is cleaned up after the test.
Method Ask(kind As %String, text As %String, Output ref As %String) As OcuTalon.Bridge.Msg.Request [ Private ]
{
	Set request = $ClassMethod(..#FIXTURE, "NewRequest", kind, "untrusted", text, .ref)
	Set ..ItemIds = ..ItemIds _ $ListBuild(ref)
	Quit request
}

/// Saves a fixture Usage row that costs the amount, recorded at the UTC time, owned by instance, under a DecisionRef of its own that OnAfterOneTest deletes.
Method AddSpend(cost As %Numeric, recordedAt As %String) [ Private ]
{
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set ..UsageRefs = ..UsageRefs _ $ListBuild(ref)
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "AddUsage", ref, ..#HAIKU, 1000, 100, 0, 0, cost, recordedAt, "instance"), "a Usage row of "_cost_" is saved at "_recordedAt)
}

/// Asserts the number of requests to /v1/messages that the mock took since the mark (those for the model, when one is given), read once the runner has
/// handled everything sent to it (RunnerFixture Drain).
Method AssertSent(runner As %String, mark As %Integer, expected As %Integer, label As %String, model As %String = "") [ Private ]
{
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Drain", runner), label_runner_" has handled everything sent to it")
	Do $$$AssertStatusOK($ClassMethod(..#MOCK, "LogSince", mark, .entries), label_"the mock's log is read")
	Set sent = 0
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.method = "POST") && (entry.path = "/v1/messages") && ((model = "") || (entry.model = model)) Set sent = sent + 1
	}
	Do $$$AssertEquals(sent, expected, label_expected_" request(s) reached the mock")
}

/// The Usage rows of the DecisionRef, as one text.
ClassMethod UsageOf(ref As %String) As %String [ Private ]
{
	Set text = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Model, InputTokens, OutputTokens, CacheReadTokens, CacheWriteTokens, CostUSD FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ? ORDER BY ID", ref)
	While result.%Next() {
		For column = 1:1:7 Set text = text _ "|" _ result.%GetData(column)
		Set text = text _ $Char(10)
	}
	Quit text
}

/// The sum of the CostUSD of the Usage rows of the DecisionRef, to 6 decimals.
ClassMethod CostSum(ref As %String) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT SUM(CostUSD) FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ?", ref)
	Do result.%Next()
	Quit $Number(result.%GetData(1), 6)
}

/// The values and rows that a restart or an upgrade must not change, as one text: the Decide rows of the three values, the Price row of the first model,
/// the Model row of TriageAgent and its entry's provider and placeholder.
ClassMethod Kept() As %String [ Private ]
{
	Set text = ""
	For setting = "DecisionTokenBudget", "DailyCostCapUSD", "InstanceZone" {
		Set text = text _ setting _ "=" _ ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor(setting, ..#PRODUCTION, "Decide") _ ";"
	}
	Set row = ##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen(..#HAIKU)
	Set text = text _ "price=" _ row.InputPerMTok _ "|" _ row.OutputPerMTok _ "|" _ row.CacheReadPerMTok _ ";"
	Set text = text _ "model=" _ ##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel("TriageAgent", ..#PRODUCTION) _ ";"
	Do ##class(OcuTalon.Bridge.ConfigStore).Details("OcuTalonTriage", .details)
	Set text = text _ "entry=" _ details."model_provider" _ "|" _ details."api_key"
	Quit text
}

/// Submits a SaveSettings command of the section as Web.Api.SaveSection does (origin web_admin), with the fixture session's Ref; the result.
Method Submit(slug As %String, changes As %DynamicObject, sessionRef As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = slug
	Set command.Changes = changes.%ToJSON()
	Set command.ActingUser = $USERNAME
	Set command.SessionRef = sessionRef
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
	Do $$$AssertStatusOK(sc, slug_": the command is submitted")
	Quit result
}

}
