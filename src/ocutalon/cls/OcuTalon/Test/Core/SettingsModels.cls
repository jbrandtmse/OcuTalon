/// Tests of the models section and of the model test in OcuTalon.Core.SettingsOps (Story 18.3; AD-1, AD-8, AD-17, AD-19). THIS CLASS RUNS IN THROWAWAY STACKS AND
/// IN CI ONLY (Rule 21): it writes the Price rows of the two Anthropic models and puts them back. The tests drive a shadow instance of
/// OcuTalon.Test.Core.SettingsOpsProbe, whose audit write is a recording seam and whose BridgeCurrent, BridgeCheckModel, BridgeSetModel, BridgeSetPrice and BridgeTest
/// stand in for Bridge.Settings (the price tests of the rollback pass SetPrice through to the real Price rows). Every text and every list is written out here, never
/// read from SettingsOps.
///   - TestModelChange: a changed first model is checked, then set, and audited as TriageAgent.model with the provider/model form;
///   - TestSecondModel: a second model is set with second 1 and audited as TriageAgent.secondModel, and clearing it sets both empty and audits "" as the new value;
///   - TestModelRefused: a model that is refused names the agent, or <Agent>.second for a second model, and nothing is set or audited;
///   - TestPriceChange: only the changed prices are set, each audited as price.<model>.<key>, with the number forms of the audit;
///   - TestPriceRefusedRollsBack: a price that SetPrice refuses (the real one) rolls back the price of the model before it, names prices.<model>, and sets and audits
///     nothing, a model change in the same body included; the same with a double that refuses;
///   - TestBadBody: an agent or a model missing or extra, a non-string, a non-number, a "@{", and a body that is not {agents, prices} are refused with the offending names,
///     and nothing is checked, set or audited;
///   - TestOrder: every CheckModel comes before the first SetPrice, and every SetPrice before the first SetModel;
///   - TestSetFailsLate: a SetModel that fails after a price and an earlier model were written puts both back, newest first, and audits each put-back; the answer is failed;
///   - TestAuditFailsLate: a failed audit entry puts back what was written and answers not_audited;
///   - TestUnchangedValuesAreSkipped: values equal to the current ones are neither checked, set nor audited, and a price equal as a number is the same;
///   - TestStub: a CheckModel that answers "not implemented" gives not_built and sets nothing;
///   - TestModelTest: the model test answers tested with the answer as JSON, refused with the field agent for a refused agent, and failed for an error.
///   - TestRealModelTestWait: the real BridgeTest (Test.Core.SettingsOpsNoReply stands in for the wait on Decide) answers reason timeout for an expired wait, sends the
///     request to Decide for TESTWAIT seconds, fails on a failed send and refuses an agent that TestRequest refuses.
Class OcuTalon.Test.Core.SettingsModels Extends %UnitTest.TestCase
{

/// The probe under test.
Parameter PROBE = "OcuTalon.Test.Core.SettingsOpsProbe";

/// A 22-character Ref for the command's SessionRef.
Parameter REF = "zzsession0123456789abc";

/// The two models whose Price rows the tests write: the models of the supported provider's table.
Parameter MODELS = "claude-haiku-5-5,claude-sonnet-5-5";

/// The properties of a Price row, in the order of its list.
Parameter PROPERTIES = "InputPerMTok,OutputPerMTok,CacheReadPerMTok,CacheWritePerMTok,LongThresholdTokens,LongInputPerMTok,LongOutputPerMTok";

Method OnBeforeAllTests() As %Status
{
	Kill ^OcuTalonTest("SettingsModels")
	Set models = $ListFromString(..#MODELS)
	Set position = 0
	While $ListNext(models, position, model) {
		If ##class(OcuTalon.Bridge.Data.Price).ModelIndexExists(model) {
			Set row = ##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen(model)
			Set saved = ""
			Set properties = $ListFromString(..#PROPERTIES)
			Set at = 0
			While $ListNext(properties, at, property) {
				Set saved = saved_$ListBuild($Property(row, property))
			}
			Set ^OcuTalonTest("SettingsModels", "saved", model) = saved
		}
	}
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe
	Do ..SeedPrices()
	Do ..SeedDoubles()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Set models = $ListFromString(..#MODELS)
	Set position = 0
	While $ListNext(models, position, model) {
		If '$Data(^OcuTalonTest("SettingsModels", "saved", model), saved) {
			If ##class(OcuTalon.Bridge.Data.Price).ModelIndexExists(model) Do ##class(OcuTalon.Bridge.Data.Price).ModelIndexDelete(model)
			Continue
		}
		Set row = ##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen(model)
		Set properties = $ListFromString(..#PROPERTIES)
		For i = 1:1:$ListLength(properties) {
			Set $Property(row, $List(properties, i)) = $List(saved, i)
		}
		Do row.%Save()
	}
	Kill ^OcuTalonTest("SettingsModels"), ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe
	Quit $$$OK
}

/// A first model change: CheckModel, then SetModel with second 0, and one audit entry in the provider/model form.
Method TestModelChange()
{
	Set body = ..Body()
	Do body.agents.TriageAgent.%Set("model", "claude-sonnet-5-5")
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the save is done")
	Do $$$AssertEquals(..Calls(), "checkModel|TriageAgent|anthropic|claude-sonnet-5-5|0;setModel|TriageAgent|anthropic|claude-sonnet-5-5|0", "TriageAgent is checked, then set: nothing else")
	Do $$$AssertEquals(..Audits(), 1, "one audit entry")
	Set data = ..AuditData(1)
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "TriageAgent.model|anthropic/claude-haiku-5-5|anthropic/claude-sonnet-5-5", "it names the agent's model and both forms")
	Do $$$AssertEquals(data.irisUser_"|"_data.sessionRef_"|"_data.channel, "zzadmin|"_..#REF_"|web", "the acting user, the session and the channel web")
	Do $$$AssertEquals(..Bridge("TriageAgent.model"), "claude-sonnet-5-5", "the model is set")
}

/// A second model is set with second 1 and audited as secondModel ("" when there is none); clearing sets both empty.
Method TestSecondModel()
{
	Set body = ..Body()
	Do body.agents.TriageAgent.%Set("secondProvider", "anthropic")
	Do body.agents.TriageAgent.%Set("secondModel", "claude-sonnet-5-5")
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the second model is saved")
	Do $$$AssertEquals(..Calls(), "checkModel|TriageAgent|anthropic|claude-sonnet-5-5|1;setModel|TriageAgent|anthropic|claude-sonnet-5-5|1", "checked and set with second 1")
	Set data = ..AuditData(1)
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "TriageAgent.secondModel||anthropic/claude-sonnet-5-5", "audited as secondModel, with no model before")
	Do ..Reset()
	Do ..SeedDoubles()
	Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "TriageAgent.secondProvider") = "anthropic"
	Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "TriageAgent.secondModel") = "claude-sonnet-5-5"
	Set result = ..Save(..Body())
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "clearing the second model is saved")
	Do $$$AssertEquals(..Calls(), "checkModel|TriageAgent|||1;setModel|TriageAgent|||1", "both are empty, with second 1: the clear form")
	Set data = ..AuditData(1)
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "TriageAgent.secondModel|anthropic/claude-sonnet-5-5|", "the audit entry has an empty new value")
}

/// A refused model names the agent, or <Agent>.second, and changes nothing.
Method TestModelRefused()
{
	Set body = ..Body()
	Do body.agents.TriageAgent.%Set("model", "claude-sonnet-5-5")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "checkModel") = "error:TriageAgent"
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "0|refused|{""fields"":[""TriageAgent""]}", "the refused first model names TriageAgent")
	Do $$$AssertEquals($Piece(..Calls(), ";", 2), "", "no SetModel")
	Do $$$AssertEquals(..Audits(), 0, "and no audit entry")
	Do $$$AssertEquals(..Bridge("TriageAgent.model"), "claude-haiku-5-5", "the model stays")
	Do ..Reset()
	Do ..SeedDoubles()
	Do body.agents.TriageAgent.%Set("secondProvider", "anthropic")
	Do body.agents.TriageAgent.%Set("secondModel", "claude-sonnet-5-5")
	Do body.agents.ChatAgent.%Set("model", "claude-sonnet-5-5")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "checkModel") = "error"
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Data, "{""fields"":[""TriageAgent"",""TriageAgent.second"",""ChatAgent""]}", "every refused model is named, a second model as <Agent>.second")
	Do $$$AssertEquals(..Audits()_"|"_..Count("setModel")_"|"_..Count("setPrice"), "0|0|0", "nothing is set or audited")
	Do ..Reset()
	Do ..SeedDoubles()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "checkModel") = "error:TriageAgent.second"
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Data, "{""fields"":[""TriageAgent.second""]}", "a second model refused alone is named alone")
}

/// Only the changed prices are set, each with its audit entry in the number form of the audit (a zero before the point).
Method TestPriceChange()
{
	Set body = ..Body()
	Do body.prices.%Get("claude-haiku-5-5").%Set("input", "1.25")
	Do body.prices.%Get("claude-haiku-5-5").%Set("cacheRead", 0.05)
	Do body.prices.%Get("claude-sonnet-5-5").%Set("output", "20")
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "the save is done")
	Do $$$AssertEquals(..Calls(), "setPrice|claude-haiku-5-5|{""input"":""1.25"",""cacheRead"":0.05};setPrice|claude-sonnet-5-5|{""output"":""20""}", "the changed prices only, as given, one SetPrice for each model")
	Do $$$AssertEquals(..Audits(), 3, "one audit entry for each changed price")
	Set data = ..AuditData(1)
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "price.claude-haiku-5-5.input|1|1.25", "the first")
	Set data = ..AuditData(2)
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "price.claude-haiku-5-5.cacheRead|0.1|0.05", "the second, with a zero before the point")
	Set data = ..AuditData(3)
	Do $$$AssertEquals(data.setting_"|"_data.from_"|"_data.to, "price.claude-sonnet-5-5.output|15|20", "the third")
	Do $$$AssertEquals(..Bridge("price.claude-haiku-5-5.input")_"|"_..Bridge("price.claude-sonnet-5-5.output"), "1.25|20", "the double holds them")
}

/// A price that SetPrice refuses rolls back the price written before it, names prices.<model>, and writes no audit entry and no SetModel, whatever else the body changes.
Method TestPriceRefusedRollsBack()
{
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "pass") = "prices"
	Set body = ..Body()
	Do body.agents.TriageAgent.%Set("model", "claude-sonnet-5-5")
	Do body.prices.%Get("claude-haiku-5-5").%Set("input", "2")
	Do body.prices.%Get("claude-sonnet-5-5").%Set("input", "-1")
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "0|refused|{""fields"":[""prices.claude-sonnet-5-5""]}", "the real SetPrice refuses a negative price: the model is named")
	Do $$$AssertEquals(..PriceRow("claude-haiku-5-5", "InputPerMTok"), 1, "the first model keeps its price: the transaction rolled back")
	Do $$$AssertEquals(..PriceRow("claude-sonnet-5-5", "InputPerMTok"), 3, "the second keeps its price")
	Do $$$AssertEquals(..Audits(), 0, "no audit entry")
	Do $$$AssertEquals(..Count("setModel"), 0, "and no SetModel")
	Do $$$AssertEquals($TLevel, 0, "no transaction is left open")
	Do ..Reset()
	Do ..SeedDoubles()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "setPrice") = "error:claude-sonnet-5-5"
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Data, "{""fields"":[""prices.claude-sonnet-5-5""]}", "a double that refuses the second model's price gives the same refusal")
	Do $$$AssertEquals(..Audits()_"|"_..Count("setModel"), "0|0", "and no audit entry or SetModel")
	Do $$$AssertEquals(..Count("setPrice"), 2, "both SetPrice calls were made")
}

/// A body that is not the shape is refused with the offending names, and nothing is checked, set or audited.
Method TestBadBody()
{
	Set cases = $ListBuild("agentMissing", "agentExtra", "memberMissing", "memberExtra", "numberProvider", "placeholder", "priceMissing", "priceExtra", "priceKeyMissing", "priceNull", "priceArray", "pricePlaceholder", "topExtra", "noPrices", "agentsArray")
	Set names = $ListBuild("DiagnosisAgent", "SpyAgent", "ChatAgent", "TriageAgent", "TriageAgent", "ChatAgent", "prices.claude-sonnet-5-5", "prices.zz-model", "prices.claude-haiku-5-5", "prices.claude-haiku-5-5", "prices.claude-haiku-5-5", "prices.claude-sonnet-5-5", "extra", "prices", "agents")
	For i = 1:1:$ListLength(cases) {
		Do ..Reset()
		Do ..SeedDoubles()
		Set case = $List(cases, i)
		Set body = ..Body()
		If case = "agentMissing" Do body.agents.%Remove("DiagnosisAgent")
		If case = "agentExtra" Do body.agents.%Set("SpyAgent", {"provider": "anthropic", "model": "claude-haiku-5-5", "secondProvider": "", "secondModel": ""})
		If case = "memberMissing" Do body.agents.ChatAgent.%Remove("secondModel")
		If case = "memberExtra" Do body.agents.TriageAgent.%Set("key", "x")
		If case = "numberProvider" Do body.agents.TriageAgent.%Set("provider", 5, "number")
		If case = "placeholder" Do body.agents.ChatAgent.%Set("model", "@{env:ANTHROPIC_API_KEY}")
		If case = "priceMissing" Do body.prices.%Remove("claude-sonnet-5-5")
		If case = "priceExtra" Do body.prices.%Set("zz-model", {"input": 1, "output": 1, "cacheRead": 1, "cacheWrite": 1})
		If case = "priceKeyMissing" Do body.prices.%Get("claude-haiku-5-5").%Remove("cacheWrite")
		If case = "priceNull" Do body.prices.%Get("claude-haiku-5-5").%Set("input", "", "null")
		If case = "priceArray" Do body.prices.%Get("claude-haiku-5-5").%Set("output", [1])
		If case = "pricePlaceholder" Do body.prices.%Get("claude-sonnet-5-5").%Set("input", "@{env:X}")
		If case = "topExtra" Do body.%Set("extra", 1)
		If case = "noPrices" Do body.%Remove("prices")
		If case = "agentsArray" Do body.%Set("agents", [])
		Set result = ..Save(body)
		Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", case_": refused")
		Set fields = {}.%FromJSON(result.Data).fields
		Set found = 0
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(, .field) {
			If field = $List(names, i) Set found = 1
		}
		Do $$$AssertTrue(found, case_": names "_$List(names, i)_" in "_result.Data)
		Do $$$AssertEquals(..Calls()_"|"_..Audits(), "|0", case_": nothing was checked, set or audited")
	}
	Do ..Reset()
	Set result = ..SaveText("not json")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", "text that is not JSON is refused")
	Set result = ..SaveText("[1]")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|refused", "and so is an array")
}

/// Every CheckModel runs before the first SetPrice, and every SetPrice before the first SetModel.
Method TestOrder()
{
	Set body = ..Body()
	Do body.agents.TriageAgent.%Set("model", "claude-sonnet-5-5")
	Do body.agents.DiagnosisAgent.%Set("model", "claude-haiku-5-5")
	Do body.agents.ChatAgent.%Set("secondProvider", "anthropic")
	Do body.agents.ChatAgent.%Set("secondModel", "claude-sonnet-5-5")
	Do body.prices.%Get("claude-haiku-5-5").%Set("output", "6")
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Outcome, "done", "the save is done")
	Set kinds = ""
	Set n = ""
	For {
		Set n = $Order(^||OcuTalonSettingsOpsProbe("models", n))
		Quit:n=""
		Set kinds = kinds_$ListBuild($Piece(^||OcuTalonSettingsOpsProbe("models", n), "|", 1))
	}
	Do $$$AssertEquals($ListToString(kinds), "checkModel,checkModel,checkModel,setPrice,setModel,setModel,setModel", "three checks, then the price, then three sets")
	Do $$$AssertEquals(..Audits(), 4, "four audit entries: the price, then the three models")
	Do $$$AssertEquals(..AuditData(1).setting, "price.claude-haiku-5-5.output", "the price is audited first")
	Do $$$AssertEquals(..AuditData(2).setting_","_..AuditData(3).setting_","_..AuditData(4).setting, "TriageAgent.model,DiagnosisAgent.model,ChatAgent.secondModel", "then each model in the order of the page")
}

/// A SetModel that fails after a price and an earlier model were written puts both back, newest first, and audits each put-back.
Method TestSetFailsLate()
{
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "setModelAt") = 2
	Set body = ..Body()
	Do body.agents.TriageAgent.%Set("model", "claude-sonnet-5-5")
	Do body.agents.DiagnosisAgent.%Set("model", "claude-haiku-5-5")
	Do body.prices.%Get("claude-haiku-5-5").%Set("input", "2")
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "the save failed")
	Do $$$AssertEquals(..Calls(), "checkModel|TriageAgent|anthropic|claude-sonnet-5-5|0;checkModel|DiagnosisAgent|anthropic|claude-haiku-5-5|0;setPrice|claude-haiku-5-5|{""input"":""2""};setModel|TriageAgent|anthropic|claude-sonnet-5-5|0;setModel|DiagnosisAgent|anthropic|claude-haiku-5-5|0;setModel|TriageAgent|anthropic|claude-haiku-5-5|0;setPrice|claude-haiku-5-5|{""input"":1}", "the earlier model is put back first, then the price")
	Do $$$AssertEquals(..Bridge("TriageAgent.model")_"|"_..Bridge("DiagnosisAgent.model")_"|"_..Bridge("price.claude-haiku-5-5.input"), "claude-haiku-5-5|claude-sonnet-5-5|1", "every value is as it was")
	Do $$$AssertEquals(..Audits(), 4, "the price, the first model, and the put-back of each")
	Set list = ""
	For i = 1:1:4 Set list = list_$ListBuild(..AuditData(i).setting_"="_..AuditData(i).from_">"_..AuditData(i).to)
	Do $$$AssertEquals($ListToString(list, ";"), "price.claude-haiku-5-5.input=1>2;TriageAgent.model=anthropic/claude-haiku-5-5>anthropic/claude-sonnet-5-5;TriageAgent.model=anthropic/claude-sonnet-5-5>anthropic/claude-haiku-5-5;price.claude-haiku-5-5.input=2>1", "each put-back is audited with from and to swapped")
	Do ..Reset()
	Do ..SeedDoubles()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "setModelThrowAt") = 1
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "a SetModel that throws fails the save too")
	Do $$$AssertEquals(..Bridge("price.claude-haiku-5-5.input"), 1, "and the price is put back")
}

/// A failed audit entry puts back what was written and answers not_audited.
Method TestAuditFailsLate()
{
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "auditAt") = 2
	Set body = ..Body()
	Do body.agents.TriageAgent.%Set("model", "claude-sonnet-5-5")
	Do body.prices.%Get("claude-haiku-5-5").%Set("input", "2")
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "the second audit entry failed")
	Do $$$AssertEquals(..Bridge("TriageAgent.model")_"|"_..Bridge("price.claude-haiku-5-5.input"), "claude-haiku-5-5|1", "the model and the price are put back")
	Do ..Reset()
	Do ..SeedDoubles()
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "auditAt") = 1
	Set body = ..Body()
	Do body.prices.%Get("claude-haiku-5-5").%Set("input", "2")
	Do body.prices.%Get("claude-haiku-5-5").%Set("output", "6")
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_audited", "the first of two price audit entries failed")
	Do $$$AssertEquals(..Bridge("price.claude-haiku-5-5.input")_"|"_..Bridge("price.claude-haiku-5-5.output"), "1|5", "both prices are put back, the one after the failed entry included")
}

/// A value that equals the current one is neither checked, set nor audited; a price that is the same number is the same.
Method TestUnchangedValuesAreSkipped()
{
	Set result = ..Save(..Body())
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "1|done", "a body equal to the current values is done")
	Do $$$AssertEquals(..Calls()_"|"_..Audits(), "|0", "and does nothing")
	Set body = ..Body()
	Do body.prices.%Get("claude-haiku-5-5").%Set("input", "1.0")
	Do body.prices.%Get("claude-haiku-5-5").%Set("output", "5.00")
	Do body.prices.%Get("claude-haiku-5-5").%Set("cacheRead", ".10")
	Do body.agents.ChatAgent.%Set("model", "claude-sonnet-5-5")
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Outcome, "done", "one change among equal values is done")
	Do $$$AssertEquals(..Calls(), "checkModel|ChatAgent|anthropic|claude-sonnet-5-5|0;setModel|ChatAgent|anthropic|claude-sonnet-5-5|0", "only the changed model: the equal numbers are not prices to set")
}

/// A CheckModel that answers "not implemented" gives not_built and sets nothing.
Method TestStub()
{
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "checkModel") = "stub"
	Set body = ..Body()
	Do body.agents.TriageAgent.%Set("model", "claude-sonnet-5-5")
	Do body.prices.%Get("claude-haiku-5-5").%Set("input", "2")
	Set result = ..Save(body)
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_built", "not built")
	Do $$$AssertEquals(..Count("setModel")_"|"_..Count("setPrice")_"|"_..Audits(), "0|0|0", "nothing is set or audited")
}

/// The model test: tested with the answer as JSON; refused with the field agent; failed for an error; and it writes and audits nothing.
Method TestModelTest()
{
	Set result = ..SendTest("TriageAgent")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "1|tested|{""answered"":true,""seconds"":0.5,""reason"":""""}", "an answered test")
	Do $$$AssertEquals(..Calls(), "test|TriageAgent", "the double saw the agent")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "test") = "timeout"
	Set result = ..SendTest("ChatAgent")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "1|tested|{""answered"":false,""seconds"":45,""reason"":""timeout""}", "a test that timed out")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "test") = "refused"
	Set result = ..SendTest("NoSuchAgent")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "0|refused|{""fields"":[""agent""]}", "a refused agent")
	Set ^OcuTalonTest("SettingsOpsProbe", "answer", "test") = "error"
	Set result = ..SendTest("TriageAgent")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "an error")
	Do $$$AssertEquals(..Audits(), 0, "no audit entry for any test")
}

/// The real BridgeTest (Test.Core.SettingsOpsNoReply stands in for the wait on Decide): an expired wait, an OK status with no response, answers reason timeout; the
/// request goes to Decide for TESTWAIT seconds and is a model test request; a send that fails fails the test; an agent that TestRequest refuses is refused.
Method TestRealModelTestWait()
{
	Kill ^||OcuTalonSettingsOpsNoReply
	Set result = ..SendTestVia("TriageAgent", "OcuTalon.Test.Core.SettingsOpsNoReply")
	Set answer = $Select(result.Data '= "": {}.%FromJSON(result.Data), 1: {})
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_answer.answered_"|"_answer.reason, "1|tested|0|timeout", "a wait that expires answers reason timeout: "_result.Data)
	Set sent = $Get(^||OcuTalonSettingsOpsNoReply("sent"))
	Do $$$AssertEquals($Piece(sent, "|", 1)_"|"_$Piece(sent, "|", 3), "Decide|"_##class(OcuTalon.Core.SettingsOps).#TESTWAIT, "the request went to Decide for the wait")
	Do $$$AssertEquals($Extract($Piece(sent, "|", 2), 1, 5), "test.", "and it is a model test request")
	Set ^||OcuTalonSettingsOpsNoReply("mode") = "error"
	Set result = ..SendTestVia("TriageAgent", "OcuTalon.Test.Core.SettingsOpsNoReply")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|failed", "a send that fails fails the test")
	Kill ^||OcuTalonSettingsOpsNoReply
	Set result = ..SendTestVia("NoSuchAgent", "OcuTalon.Test.Core.SettingsOpsNoReply")
	Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Data, "0|refused|{""fields"":[""agent""]}", "an agent that TestRequest refuses is refused")
	Do $$$AssertEquals($Data(^||OcuTalonSettingsOpsNoReply("sent")), 0, "and nothing was sent")
	Kill ^||OcuTalonSettingsOpsNoReply
}

/// --- helpers ---
/// Clears the probe's globals.
Method Reset() [ Private ]
{
	Kill ^OcuTalonTest("SettingsOpsProbe"), ^||OcuTalonSettingsOpsProbe
}

/// The two Price rows with the prices the tests expect: haiku 1, 5, 0.1, 1.25 and sonnet 3, 15, 0.3, 3.75, with no long tier.
Method SeedPrices() [ Private ]
{
	Set models = $ListFromString(..#MODELS)
	Set values = $ListBuild($ListBuild(1, 5, 0.1, 1.25), $ListBuild(3, 15, 0.3, 3.75))
	For i = 1:1:2 {
		Set model = $List(models, i)
		Set row = $Select(##class(OcuTalon.Bridge.Data.Price).ModelIndexExists(model): ##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen(model), 1: ##class(OcuTalon.Bridge.Data.Price).%New())
		Set row.Model = model
		Set row.InputPerMTok = $List($List(values, i), 1)
		Set row.OutputPerMTok = $List($List(values, i), 2)
		Set row.CacheReadPerMTok = $List($List(values, i), 3)
		Set row.CacheWritePerMTok = $List($List(values, i), 4)
		Set row.LongThresholdTokens = 0
		Set row.LongInputPerMTok = 0
		Set row.LongOutputPerMTok = 0
		Do row.%Save()
	}
}

/// The probe's current values: the first model of TriageAgent and ChatAgent is Haiku, DiagnosisAgent's is Sonnet, no agent has a second model, and the prices are those of SeedPrices.
Method SeedDoubles() [ Private ]
{
	Set agents = $ListBuild("TriageAgent", "DiagnosisAgent", "ChatAgent")
	For i = 1:1:3 {
		Set agent = $List(agents, i)
		Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", agent_".provider") = "anthropic"
		Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", agent_".model") = $Select(agent = "DiagnosisAgent": "claude-sonnet-5-5", 1: "claude-haiku-5-5")
		Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", agent_".secondProvider") = ""
		Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", agent_".secondModel") = ""
	}
	Set models = $ListFromString(..#MODELS)
	Set values = $ListBuild($ListBuild(1, 5, 0.1, 1.25), $ListBuild(3, 15, 0.3, 3.75))
	Set keys = $ListBuild("input", "output", "cacheRead", "cacheWrite")
	For i = 1:1:2 {
		For j = 1:1:4 {
			Set ^OcuTalonTest("SettingsOpsProbe", "bridgeValue", "price."_$List(models, i)_"."_$List(keys, j)) = $List($List(values, i), j)
		}
	}
}

/// The body that equals the probe's current values.
Method Body() As %DynamicObject [ Private ]
{
	Set body = {"agents": {}, "prices": {}}
	Set agents = $ListBuild("TriageAgent", "DiagnosisAgent", "ChatAgent")
	For i = 1:1:3 {
		Set agent = $List(agents, i)
		Do body.agents.%Set(agent, {"provider": "anthropic", "model": (..Bridge(agent_".model")), "secondProvider": "", "secondModel": ""})
	}
	Set models = $ListFromString(..#MODELS)
	For i = 1:1:2 {
		Set model = $List(models, i)
		Set prices = {}
		For key = "input", "output", "cacheRead", "cacheWrite" {
			Do prices.%Set(key, +..Bridge("price."_model_"."_key), "number")
		}
		Do body.prices.%Set(model, prices)
	}
	Quit body
}

/// The probe's stored current value of the name.
Method Bridge(name As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("SettingsOpsProbe", "bridgeValue", name))
}

/// A property of the model's Price row.
Method PriceRow(model As %String, property As %String) As %Numeric [ Private ]
{
	Quit +$Property(##class(OcuTalon.Bridge.Data.Price).ModelIndexOpen(model), property)
}

/// The calls of the model seams, in order, joined by ";".
Method Calls() As %String [ Private ]
{
	Set text = ""
	Set n = ""
	For {
		Set n = $Order(^||OcuTalonSettingsOpsProbe("models", n))
		Quit:n=""
		Set text = text_$Select(text = "": "", 1: ";")_^||OcuTalonSettingsOpsProbe("models", n)
	}
	Quit text
}

/// The number of calls of the kind (checkModel, setModel, setPrice or test).
Method Count(kind As %String) As %Integer [ Private ]
{
	Set count = 0
	Set n = ""
	For {
		Set n = $Order(^||OcuTalonSettingsOpsProbe("models", n))
		Quit:n=""
		If $Piece(^||OcuTalonSettingsOpsProbe("models", n), "|", 1) = kind Set count = count + 1
	}
	Quit count
}

/// The number of audit writes that the probe saw.
Method Audits() As %Integer [ Private ]
{
	Quit +$Get(^||OcuTalonSettingsOpsProbe("n", "audit"))
}

/// The data of the nth audit write that the probe saw.
Method AuditData(nth As %Integer) As %DynamicObject [ Private ]
{
	Set count = 0
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("SettingsOpsProbe", "calls", n))
		Quit:n=""
		If ^OcuTalonTest("SettingsOpsProbe", "calls", n) = "audit" {
			Set count = count + 1
			If count = nth Quit
		}
	}
	Quit {}.%FromJSON($Get(^OcuTalonTest("SettingsOpsProbe", "calls", n, "data"), "{}"))
}

/// A SaveSettings of the models section with the body, from web_admin for zzadmin, sent to the probe.
Method Save(body As %DynamicObject) As OcuTalon.Msg.CommandResult [ Private ]
{
	Quit ..SaveText(body.%ToJSON())
}

/// A SaveSettings of the models section with the text as its changes.
Method SaveText(text As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = "models"
	Set command.Changes = text
	Set command.ActingUser = "zzadmin"
	Set command.SessionRef = ..#REF
	Set command.Origin = "web_admin"
	Quit ..Send(command)
}

/// A TestModel of the agent from web_admin, sent to the probe.
Method SendTest(agent As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Quit ..SendTestVia(agent, ..#PROBE)
}

/// A TestModel of the agent carried out by a shadow instance of the class.
Method SendTestVia(agent As %String, class As %String) As OcuTalon.Msg.CommandResult [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.TestModel).%New()
	Set command.Agent = agent
	Set command.SessionRef = ..#REF
	Set command.Origin = "web_admin"
	Quit ..Send(command, class)
}

/// Sends the command to a shadow instance of the class (the probe unless given) and answers its CommandResult.
Method Send(command As OcuTalon.Msg.Command, class As %String = "") As OcuTalon.Msg.CommandResult [ Private ]
{
	If class = "" Set class = ..#PROBE
	Set probe = ##class(Ens.Host).GetShadowInstance("class||"_class, .sc)
	Do $$$AssertStatusOK(sc, "the probe is made")
	Set sc = probe.OnMessage(command, .result)
	Do $$$AssertStatusOK(sc, "the status is OK")
	Quit result
}

}
