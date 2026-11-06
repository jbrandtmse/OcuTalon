/// Tests of the bridge's settings values, in process (Story 17.4; AD-18, AD-19, AD-20): Values, Check, Set, SetPrice, TestRequest and TestAnswer of
/// OcuTalon.Bridge.Settings, and Budget.Unmark. They need the active production's System Default Settings, as the other in-process tests of the bridge do.
/// Every test puts back what it wrote: the System Default Settings rows of Decide that it touched (RunnerFixture.RememberDefault and RestoreDefaults),
/// the Price rows (a snapshot by value), the capped marks of the days it used, and, through the base, the InstanceZone row and the process zone.
///   - TestCheckRefusals: Check refuses each value of the "Refused value" row (a placeholder, a negative or fractional budget, a budget above 100000, a cap
///     with three decimals or above 10000, text, an unknown zone, a folder, a path with .., a name of 65 characters) and each name outside the allow-list
///     (TimerSeconds included), with a reason that holds no value, and it accepts the bounds; Set with the same arguments writes nothing: the Decide rows, the
///     capped mark and the process zone are as they were;
///   - TestSetAndValues: Set of each name returns the earlier value in old as a string, stores a number as its canonical text (7.50 as 7.5), and Values shows
///     the three values as strings and, for the three agents, {provider, model, secondProvider, secondModel} from AgentRunner.ResolveModel and
///     Providers.ProviderOf; the JSON of Values holds no key and no placeholder; the bridge timer is unchanged;
///   - TestPutBack: Set(name, old) puts each value back, so that old passes Check;
///   - TestUnmark: Budget.Unmark removes the mark of a day once, under the lock of MarkCapped, and refuses a day that is no date; Set of the cap
///     removes today's mark when the cap is 0 or above the spend and leaves it when the cap is at or below the spend;
///   - TestSetPrice, TestSetPriceRefused: SetPrice merges the given prices into an existing row, returns all seven earlier values in old, and a refused call
///     (an unknown model or key, an empty object, a negative, non-numeric, placeholder or five-decimal price) leaves the row as it was;
///   - TestRequestShape: TestRequest builds the request of each agent's kind with provenance untrusted, owner instance, channel system, a fresh session, an
///     ItemId of "test." and 17 characters of a reference, and the fixed texts; IsTest names it; an unknown agent or a placeholder is refused;
///   - TestAnswerShapes: TestAnswer of an answer, a fallback, a busy reply, no response and a response with a fallback and no reason, and the rounding of
///     the seconds.
Class OcuTalon.Test.Bridge.SettingsValues Extends OcuTalon.Test.Bridge.ZoneCase
{

Parameter SETTINGS = "OcuTalon.Bridge.Settings";

Parameter FIXTURE = "OcuTalon.Test.Agent.RunnerFixture";

/// The System Default Settings rows of Decide before the test (RunnerFixture.RememberDefault), to be put back.
Property Saved As %List;

/// The Price rows before the test, as a list of $ListBuild(Model, ...seven values), to be put back.
Property Prices As %List;

/// The days whose capped mark the test used, to be removed.
Property Days As %List;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	Set ..Prices = ..PriceRows()
	Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = ##super(testname)
	If ..Saved '= "" Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "RestoreDefaults", ..Saved), "the System Default Settings rows are put back")
	Set ..Saved = ""
	Do ..PutPriceRows(..Prices)
	Set ..Prices = ""
	Set position = 0
	While $ListNext(..Days, position, day) {
		Kill ^OcuTalonBP.UsageCapped(day)
	}
	Set ..Days = ""
	Quit sc
}

/// Check refuses what is off the allow-list or the bounds, without echoing it, and accepts the bounds; Set refuses the same and writes nothing.
Method TestCheckRefusals()
{
	Set class = ..#SETTINGS
	Set long = $Translate($Justify("", 65), " ", "A")
	Set cases = $ListBuild(
		$ListBuild("DecisionTokenBudget", "@{env:X}"), $ListBuild("DecisionTokenBudget", "-1"), $ListBuild("DecisionTokenBudget", "1.5"),
		$ListBuild("DecisionTokenBudget", "100001"), $ListBuild("DecisionTokenBudget", "abc"), $ListBuild("DecisionTokenBudget", "1e3"), $ListBuild("DecisionTokenBudget", ""),
		$ListBuild("DecisionTokenBudget", "1234567"), $ListBuild("DecisionTokenBudget", " 5"),
		$ListBuild("DailyCostCapUSD", "@{env:X}"), $ListBuild("DailyCostCapUSD", "-1"), $ListBuild("DailyCostCapUSD", "7.555"),
		$ListBuild("DailyCostCapUSD", "10000.01"), $ListBuild("DailyCostCapUSD", "abc"), $ListBuild("DailyCostCapUSD", "1e2"), $ListBuild("DailyCostCapUSD", ""),
		$ListBuild("DailyCostCapUSD", "123456"),
		$ListBuild("InstanceZone", "@{env:X}"), $ListBuild("InstanceZone", "Mars/Olympus"), $ListBuild("InstanceZone", "America"),
		$ListBuild("InstanceZone", "../etc"), $ListBuild("InstanceZone", long),
		$ListBuild("TimerSeconds", "60"), $ListBuild("Nope", "1"), $ListBuild("", "1"), $ListBuild("@{env:X}", "1"))
	Do ..Remember("DecisionTokenBudget")
	Do ..Remember("DailyCostCapUSD")
	Set before = ..Snapshot()
	Set position = 0
	While $ListNext(cases, position, case) {
		Set name = $List(case, 1)
		Set value = $List(case, 2)
		Set label = "'"_$Extract(name, 1, 20)_"' = '"_$Extract(value, 1, 20)_"'"
		Set sc = $ClassMethod(class, "Check", name, value)
		Do $$$AssertTrue($$$ISERR(sc), "Check refuses "_label)
		If $$$ISERR(sc) && ($Length(value) > 1) {
			Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) '[ value, "and the reason holds no value: "_label)
		}
		Set old = "x"
		Set sc = $ClassMethod(class, "Set", name, value, .old)
		Do $$$AssertTrue($$$ISERR(sc), "Set refuses "_label)
		Do $$$AssertEquals(old, "", "and old is empty: "_label)
	}
	Do $$$AssertEquals(..Snapshot(), before, "the Decide rows, the capped mark and the process zone are as they were")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Bridge.Time", "Zone"), "", "and the instance zone is still empty")
	Set accepted = $ListBuild(
		$ListBuild("DecisionTokenBudget", "0"), $ListBuild("DecisionTokenBudget", "100000"), $ListBuild("DecisionTokenBudget", "007"), $ListBuild("DailyCostCapUSD", "0"),
		$ListBuild("DailyCostCapUSD", "10000"), $ListBuild("DailyCostCapUSD", "7.5"), $ListBuild("DailyCostCapUSD", "7.50"), $ListBuild("DailyCostCapUSD", "0.01"),
		$ListBuild("InstanceZone", ""), $ListBuild("InstanceZone", "Europe/Berlin"), $ListBuild("InstanceZone", "America/Argentina/Buenos_Aires"))
	Set position = 0
	While $ListNext(accepted, position, case) {
		Do $$$AssertStatusOK($ClassMethod(class, "Check", $List(case, 1), $List(case, 2)), "Check accepts "_$List(case, 1)_" = '"_$List(case, 2)_"'")
	}
	Do $$$AssertEquals(..Snapshot(), before, "and Check changes nothing")
}

/// Set returns the earlier value, stores the canonical text, and Values shows it.
Method TestSetAndValues()
{
	Set class = ..#SETTINGS
	Set production = ##class(Ens.Director).GetActiveProductionName()
	Do ..Remember("DecisionTokenBudget")
	Do ..Remember("DailyCostCapUSD")
	Set timer = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("TimerSeconds", production, "Decide")
	Set was = $ClassMethod(class, "Values")
	Do $$$AssertEquals(was.%GetTypeOf("DecisionTokenBudget")_"|"_was.%GetTypeOf("DailyCostCapUSD")_"|"_was.%GetTypeOf("InstanceZone"), "string|string|string", "Values holds the three values as strings")
	Set wasBudget = was.%Get("DecisionTokenBudget")
	Set wasCap = was.%Get("DailyCostCapUSD")

	Do $$$AssertStatusOK($ClassMethod(class, "Set", "DecisionTokenBudget", "5000", .old), "the budget is 5000")
	Do $$$AssertEquals(old, wasBudget, "old is the earlier budget, as text")
	Do $$$AssertStatusOK($ClassMethod(class, "Set", "DailyCostCapUSD", "7.50", .old), "the cap is 7.50")
	Do $$$AssertEquals(old, wasCap, "old is the earlier cap, as text")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("DailyCostCapUSD", production, "Decide"), "7.5", "the number is stored as its canonical text")
	Do $$$AssertStatusOK($ClassMethod(class, "Set", "DailyCostCapUSD", "0.50", .old), "the cap is 0.50")
	Do $$$AssertEquals(old, "7.5", "old is 7.5")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("DailyCostCapUSD", production, "Decide"), "0.5", "0.50 is stored as 0.5, with its zero")
	Do $$$AssertStatusOK($ClassMethod(class, "Set", "InstanceZone", "Pacific/Kiritimati", .old), "the zone is Pacific/Kiritimati")
	Do $$$AssertEquals(old, "", "old is the earlier zone, empty")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Bridge.Time", "Zone"), "Pacific/Kiritimati", "Time.Zone reads it")

	Set values = $ClassMethod(class, "Values")
	Do $$$AssertEquals(values.%Get("DecisionTokenBudget")_"|"_values.%Get("DailyCostCapUSD")_"|"_values.%Get("InstanceZone"), "5000|0.5|Pacific/Kiritimati", "Values shows the three values")
	Do $$$AssertEquals(values.%GetTypeOf("agents"), "object", "and the agents")
	Set agents = values.%Get("agents")
	Set names = ""
	Set iterator = agents.%GetIterator()
	While iterator.%GetNext(.agent, .one) {
		Set names = names _ $ListBuild(agent)
		Set model = ##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(agent, production)
		Set retryItem = ##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("RetryItem", production, agent)
		Set second = $Select(retryItem = "": "", 1: ##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(retryItem, production))
		Do $$$AssertEquals(one.%GetTypeOf("provider")_one.%GetTypeOf("model")_one.%GetTypeOf("secondProvider")_one.%GetTypeOf("secondModel"), "stringstringstringstring", agent_": four strings")
		Do $$$AssertEquals(one.%Get("model"), model, agent_": the model is the runner's")
		Do $$$AssertTrue(model '= "", agent_": it has a model")
		Do $$$AssertEquals(one.%Get("provider"), ##class(OcuTalon.Bridge.Providers).ProviderOf(model), agent_": the provider is the row that lists the model")
		Do $$$AssertEquals(one.%Get("provider"), "anthropic", agent_": and it is anthropic here")
		Do $$$AssertEquals(one.%Get("secondModel")_"|"_one.%Get("secondProvider"), second_"|"_##class(OcuTalon.Bridge.Providers).ProviderOf(second), agent_": the second pair follows RetryItem")
	}
	Do $$$AssertEquals($ListToString(names), "TriageAgent,DiagnosisAgent,ChatAgent", "the three first runner items, in order")
	Set json = values.%ToJSON()
	Do $$$AssertTrue(($Find(json, "sk-") = 0) && ($Find(json, "AIza") = 0) && ($Find(json, "@{") = 0), "the JSON holds no key and no placeholder")
	Do $$$AssertEquals(##class(OcuTalon.Bridge.Ext.Accessor).ValueFor("TimerSeconds", production, "Decide"), timer, "the bridge timer is unchanged")
}

/// Set(name, old) puts each value back.
Method TestPutBack()
{
	Set class = ..#SETTINGS
	Do ..Remember("DecisionTokenBudget")
	Do ..Remember("DailyCostCapUSD")
	Set before = $ClassMethod(class, "Values")
	Set text = before.%Get("DecisionTokenBudget")_"|"_before.%Get("DailyCostCapUSD")_"|"_before.%Get("InstanceZone")
	For case = $ListBuild("DecisionTokenBudget", "250"), $ListBuild("DailyCostCapUSD", "12.25"), $ListBuild("InstanceZone", "Europe/Berlin") {
		Set name = $List(case, 1)
		Do $$$AssertStatusOK($ClassMethod(class, "Set", name, $List(case, 2), .old), name_" is changed")
		Do $$$AssertStatusOK($ClassMethod(class, "Check", name, old), name_": old passes Check")
		Do $$$AssertStatusOK($ClassMethod(class, "Set", name, old, .again), name_" is put back with old")
		Do $$$AssertEquals(again, $List(case, 2), name_": and old of that is the value that was put back")
	}
	Set after = $ClassMethod(class, "Values")
	Do $$$AssertEquals(after.%Get("DecisionTokenBudget")_"|"_after.%Get("DailyCostCapUSD")_"|"_after.%Get("InstanceZone"), text, "all three values are as they were")
}

/// Unmark removes a mark once, and Set of the cap removes today's mark only when the cap is 0 or above the spend.
Method TestUnmark()
{
	Set budget = "OcuTalon.Bridge.Budget"
	Set day = "2001-06-07"
	Set ..Days = ..Days _ $ListBuild(day)
	Set ^OcuTalonBP.UsageCapped(day) = "2001-06-07T01:00:00Z"
	Do $$$AssertEquals($ClassMethod(budget, "Unmark", day), 1, "Unmark removes the mark of a day")
	Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(day)), 0, "the mark is gone")
	Do $$$AssertEquals($ClassMethod(budget, "Unmark", day), 0, "and a second call removes nothing")
	Do $$$AssertEquals($ClassMethod(budget, "Unmark", "2001-02-30"), 0, "a day that is no date is refused")
	Do $$$AssertEquals($ClassMethod(budget, "Unmark", "abc"), 0, "so is text")

	Set today = $ClassMethod("OcuTalon.Bridge.Time", "LocalDate", $ClassMethod("OcuTalon.Bridge.Time", "NowUtc"))
	Set ..Days = ..Days _ $ListBuild(today)
	Do ..Remember("DailyCostCapUSD")
	Set ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "AddUsage", ref, "claude-haiku-5-5", "", "", "", "", 1, $ClassMethod("OcuTalon.Bridge.Time", "NowUtc"), "instance"), "a Usage row of today costs 1")
	Set spent = $ClassMethod(budget, "State").%Get("spent")
	Do $$$AssertTrue(spent '< 1, "the day's spend is at least 1: "_spent)
	Set below = (spent * 100 \ 1) / 100
	Set above = ((spent * 100 \ 1) + 2) / 100
	Set cases = $ListBuild($ListBuild(above, 0), $ListBuild(below, 1), $ListBuild(0, 0))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set cap = $FNumber($List(case, 1), "", 2)
		Set ^OcuTalonBP.UsageCapped(today) = $ClassMethod("OcuTalon.Bridge.Time", "NowUtc")
		Do $$$AssertStatusOK($ClassMethod(..#SETTINGS, "Set", "DailyCostCapUSD", cap), "the cap is "_cap_" with a spend of "_spent)
		Do $$$AssertEquals($Data(^OcuTalonBP.UsageCapped(today)) > 0, $List(case, 2), "the mark of today "_$Select($List(case, 2): "stays", 1: "is gone")_" (cap "_cap_" against "_spent_")")
	}
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Bridge_Data.Usage WHERE DecisionRef = ?", ref)
}

/// SetPrice merges the given prices into an existing row and returns all seven earlier values. The row is read by SQL, which reads what is stored.
Method TestSetPrice()
{
	Set class = ..#SETTINGS
	Set model = "claude-haiku-5-5"
	Set earlier = ..PriceSql(model)
	Do $$$AssertTrue(earlier '= "", "the row of "_model_" exists")
	If earlier = "" Quit
	Set sc = $ClassMethod(class, "SetPrice", model, {"input": 0.2, "output": 1}, .old)
	Do $$$AssertStatusOK(sc, "the input and output prices are changed")
	Do $$$AssertEquals(old.%Size(), 7, "old holds seven values")
	Do $$$AssertEquals(old.input_"|"_old.output_"|"_old.cacheRead_"|"_old.cacheWrite_"|"_old.longInput_"|"_old.longOutput_"|"_old.longThresholdTokens, earlier, "and they are the earlier ones")
	Do $$$AssertEquals($Piece(..PriceSql(model), "|", 1, 2), ".2|1", "the two prices are the new ones, as stored")
	Do $$$AssertEquals($Piece(..PriceSql(model), "|", 3, 7), $Piece(earlier, "|", 3, 7), "and the keys that were left out keep their values")
	Set sc = $ClassMethod(class, "SetPrice", model, {"cacheRead": "0.0125", "longThresholdTokens": 200000, "longInput": 0.4}, .again)
	Do $$$AssertStatusOK(sc, "numeric text, the threshold and a long price are accepted")
	Do $$$AssertEquals(again.input_"|"_again.output, ".2|1", "old holds the values as they stood")
	Set stored = ..PriceSql(model)
	Do $$$AssertEquals($Piece(stored, "|", 3)_"|"_$Piece(stored, "|", 5)_"|"_$Piece(stored, "|", 7), ".0125|.4|200000", "the new values are stored")
	Set sc = $ClassMethod(class, "SetPrice", "claude-sonnet-5-5", {"input": 2}, .sonnet)
	Do $$$AssertStatusOK(sc, "a model without a long tier takes a price")
	Do $$$AssertEquals(sonnet.longThresholdTokens_"|"_sonnet.longInput_"|"_sonnet.longOutput, "0|0|0", "and its old shows no long tier as 0")
}

/// A refused SetPrice leaves the row as it was.
Method TestSetPriceRefused()
{
	Set class = ..#SETTINGS
	Set model = "claude-haiku-5-5"
	Set before = ..PriceSql(model)
	Do $$$AssertTrue(before '= "", "the row of "_model_" exists")
	Set cases = $ListBuild(
		$ListBuild(model, "{}"), $ListBuild(model, "{""input"":-1}"), $ListBuild(model, "{""input"":""@{x}""}"), $ListBuild(model, "{""input"":0.12345}"),
		$ListBuild(model, "{""bogus"":1}"), $ListBuild(model, "{""input"":1,""bogus"":1}"), $ListBuild(model, "{""input"":""abc""}"), $ListBuild(model, "{""input"":10000.5}"),
		$ListBuild(model, "{""longThresholdTokens"":-5}"), $ListBuild(model, "{""longThresholdTokens"":1.5}"), $ListBuild(model, "{""longThresholdTokens"":10000001}"),
		$ListBuild(model, "{""longInput"":0}"), $ListBuild(model, "{""longOutput"":0}"), $ListBuild("claude-sonnet-5-5", "{""longThresholdTokens"":1000}"),
				$ListBuild(model, "{""input"":true}"), $ListBuild(model, "{""input"":null}"), $ListBuild(model, "{""input"":{""a"":1}}"),
		$ListBuild("no-such-model", "{""input"":1}"), $ListBuild("@{x}", "{""input"":1}"), $ListBuild("", "{""input"":1}"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set old = "x"
		Set sc = $ClassMethod(class, "SetPrice", $List(case, 1), {}.%FromJSON($List(case, 2)), .old)
		Do $$$AssertTrue($$$ISERR(sc), "refused: "_$List(case, 1)_" "_$List(case, 2))
		Do $$$AssertTrue($IsObject(old) && (old.%Size() = 0), "and old is empty: "_$List(case, 2))
		If $$$ISERR(sc) Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) '[ "abc", "and the reason holds no value")
	}
	Set sc = $ClassMethod(class, "SetPrice", model, "", .old)
	Do $$$AssertTrue($$$ISERR(sc), "prices that are no object are refused")
	Do $$$AssertEquals(..PriceSql(model), before, "the row is byte-equal after the refusals")
}

/// The request of each agent.
Method TestRequestShape()
{
	Set class = ..#SETTINGS
	For case = $ListBuild("TriageAgent", "decide"), $ListBuild("DiagnosisAgent", "diagnose"), $ListBuild("ChatAgent", "turn") {
		Set agent = $List(case, 1)
		Set sc = $ClassMethod(class, "TestRequest", agent, .request)
		Do $$$AssertStatusOK(sc, agent_": the request is built")
		If '$IsObject(request) Continue
		Do $$$AssertEquals(request.Kind_"|"_request.Provenance_"|"_request.OwnerRef_"|"_request.Channel_"|"_request.SessionMode, $List(case, 2)_"|untrusted|instance|system|fresh", agent_": kind, provenance, owner, channel and mode")
		Do $$$AssertTrue(request.ItemId ? 1"test."17(1AN,1"-",1"_"), agent_": the ItemId is test. and 17 characters of a reference")
		Do $$$AssertEquals($Length(request.ItemId), 22, agent_": and fits the 22 characters of a reference")
		Do $$$AssertEquals(request.Input_"|"_request.Summary, ..Text("TESTINPUT")_"|"_..Text("TESTSUMMARY"), agent_": the fixed texts")
		Do $$$AssertEquals(request.DecisionRef_"|"_request.RetryOf_"|"_request.SeedText_"|"_request.Compact, "|||0", agent_": no decision, retry, seed or flag")
		Do $$$AssertTrue($ClassMethod(class, "IsTest", request), agent_": IsTest names it")
		Set second = ""
		Do $ClassMethod(class, "TestRequest", agent, .second)
		Do $$$AssertTrue($IsObject(second) && (second.ItemId '= request.ItemId), agent_": a second request has another ItemId")
		Set request.ItemId = $Extract(##class(OcuTalon.Bridge.Ids).NewRef(), 1, 22)
		Do $$$AssertNotTrue($ClassMethod(class, "IsTest", request), agent_": a request with an ordinary reference is not a test")
	}
	Do $$$AssertNotTrue($ClassMethod(class, "IsTest", ""), "no request is not a test")
	For agent = "Chat", "ChatAgentRetry", "", "@{env:X}", "triageagent" {
		Set request = "x"
		Set sc = $ClassMethod(class, "TestRequest", agent, .request)
		Do $$$AssertTrue($$$ISERR(sc), "refused: '"_agent_"'")
		Do $$$AssertEquals(request, "", "and request is empty")
	}
}

/// The answer of each response.
Method TestAnswerShapes()
{
	Set class = ..#SETTINGS
	Set decision = ##class(OcuTalon.Bridge.Msg.DecisionResponse).%New()
	Set answer = $ClassMethod(class, "TestAnswer", decision, 1234)
	Do $$$AssertEquals(answer.%ToJSON(), "{""answered"":true,""seconds"":1.2,""reason"":""""}", "a decision that is no fallback is an answer, in 1.2 seconds")
	Set decision.Fallback = 1
	Set decision.FallbackReason = "refusal"
	Set answer = $ClassMethod(class, "TestAnswer", decision, 40)
	Do $$$AssertEquals(answer.%ToJSON(), "{""answered"":false,""seconds"":0.1,""reason"":""refusal""}", "a fallback gives its reason, and 40 ms is at least 0.1 seconds")
	Set decision.FallbackReason = ""
	Do $$$AssertEquals($ClassMethod(class, "TestAnswer", decision, 2000).reason, "error", "a fallback with no reason is error")
	Set reply = ##class(OcuTalon.Bridge.Msg.Reply).%New()
	Set answer = $ClassMethod(class, "TestAnswer", reply, 1550)
	Do $$$AssertEquals(answer.answered_"|"_answer.seconds_"|"_answer.reason, "1|1.6|", "a reply is an answer, and 1550 ms rounds to 1.6")
	Set answer = $ClassMethod(class, "TestAnswer", ##class(OcuTalon.Bridge.Msg.Reply).NewBusy(), 100)
	Do $$$AssertEquals(answer.answered_"|"_answer.reason, "0|error", "a busy reply is error")
	Set answer = $ClassMethod(class, "TestAnswer", "", 100)
	Do $$$AssertEquals(answer.answered_"|"_answer.reason, "0|error", "no response is error")
	Set answer = $ClassMethod(class, "TestAnswer", "", "")
	Do $$$AssertEquals(answer.seconds, 0, "no duration is 0 seconds")
	Do $$$AssertEquals($ClassMethod(class, "TestAnswer", decision, 0).seconds, 0, "and neither is a duration of 0")
	Do $$$AssertEquals(answer.%GetTypeOf("answered")_"|"_answer.%GetTypeOf("seconds")_"|"_answer.%GetTypeOf("reason"), "boolean|number|string", "the types are boolean, number and string")
}

/// --- helpers ---
/// A parameter of OcuTalon.Bridge.Settings.
ClassMethod Text(name As %String) As %String [ Private ]
{
	Quit $Parameter(..#SETTINGS, name)
}

/// Remembers the System Default Settings row of the setting of Decide, once, for OnAfterOneTest.
Method Remember(setting As %String) [ Private ]
{
	Set saved = ..Saved
	Do $ClassMethod(..#FIXTURE, "RememberDefault", .saved, "Decide", setting)
	Set ..Saved = saved
}

/// The state that a refused call must not change, as one text: the System Default Settings rows of the production, the capped mark of today and the process zone.
ClassMethod Snapshot() As %String [ Private ]
{
	Set state = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, SettingValue FROM Ens_Config.DefaultSettings ORDER BY ID")
	While result.%Next() {
		Set state = state _ $Char(10) _ result.%GetData(1) _ "=" _ result.%GetData(2)
	}
	Set today = $ClassMethod("OcuTalon.Bridge.Time", "LocalDate", $ClassMethod("OcuTalon.Bridge.Time", "NowUtc"))
	Quit state _ $Char(10) _ "mark=" _ $Data(^OcuTalonBP.UsageCapped(today)) _ " zone=" _ ..CurrentZone()
}

/// The seven stored values of the Price row of the model (input, output, cache read, cache write, long input, long output, long threshold), read by SQL, as one text joined
/// by |, or "" when there is no row.
ClassMethod PriceSql(model As %String) As %String [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT InputPerMTok, OutputPerMTok, CacheReadPerMTok, CacheWritePerMTok, LongInputPerMTok, LongOutputPerMTok, LongThresholdTokens FROM OcuTalon_Bridge_Data.Price WHERE Model = ?", model)
	If 'result.%Next() Quit ""
	Set text = ""
	For column = 1:1:7 Set text = text _ $Select(column = 1: "", 1: "|") _ result.%GetData(column)
	Quit text
}

/// Every Price row, as a list of $ListBuild(Model, seven values).
ClassMethod PriceRows() As %List
{
	Set rows = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM OcuTalon_Bridge_Data.Price ORDER BY ID")
	While result.%Next() {
		Set row = ##class(OcuTalon.Bridge.Data.Price).%OpenId(result.%GetData(1))
		Set rows = rows _ $ListBuild($ListBuild(row.Model, row.InputPerMTok, row.OutputPerMTok, row.CacheReadPerMTok, row.CacheWritePerMTok, row.LongThresholdTokens, row.LongInputPerMTok, row.LongOutputPerMTok))
	}
	Quit rows
}

/// Writes the rows of PriceRows back as they were, by model.
ClassMethod PutPriceRows(rows As %List)
{
	Set position = 0
	While $ListNext(rows, position, one) {
		Set row = ##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen($List(one, 1))
		If '$IsObject(row) Set row = ##class(OcuTalon.Bridge.Data.Price).%New(), row.Model = $List(one, 1)
		Set row.InputPerMTok = $List(one, 2), row.OutputPerMTok = $List(one, 3), row.CacheReadPerMTok = $List(one, 4), row.CacheWritePerMTok = $List(one, 5)
		Set row.LongThresholdTokens = $List(one, 6), row.LongInputPerMTok = $List(one, 7), row.LongOutputPerMTok = $List(one, 8)
		Do row.%Save()
	}
}

}
