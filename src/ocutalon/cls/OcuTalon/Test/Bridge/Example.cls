/// Tests of the bridge example (Story 1.3, added by QA; AD-2, AD-5, AD-7, AD-19, AD-31; FR-5). Nothing is written, started or sent:
/// the tests read the compiled example agent, the registered example production and the defaults of Decide. The example is
/// proved end to end by release/standalone-bridge.sh in a namespace of its own, whose mock answers the same whatever the agent
/// asks, so that script cannot tell a changed model, a changed prompt or a changed setting; these tests pin them in the shard.
///   - TestAgent: the example agent extends %AI.Agent with the model claude-haiku-5-5 (the product default, AD-7), the mock key
///     bridge-example, no toolset and instructions that name every field of the DecisionPayload and every outcome, ask for one
///     JSON object and hold no template token;
///   - TestProduction: the example production holds exactly Decide with no setting, TriageAgent with the example agent as its
///     AgentClass and on its AgentAllowList and DecisionPayload as its ReplyClass, and AgentSteps; no item names a provider
///     setting and the testing service is off (AD-19: a developer sets those in System Default Settings of their own namespace);
///   - TestDecideDefaults: Decide's three extension settings and its timer default to the do-nothing bases and 60 seconds, which
///     is what the example runs with; its budget settings default to no cap (DailyCostCapUSD 0) and no gateway spend (Story 1.4).
Class OcuTalon.Test.Bridge.Example Extends %UnitTest.TestCase
{

/// The example agent.
Parameter AGENT = "OcuTalon.BridgeExample.Agent";

/// The example production.
Parameter PRODUCTION = "OcuTalon.BridgeExample.Production";

/// The example agent: model, mock key, toolset and instructions.
Method TestAgent()
{
	Set class = ..#AGENT
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(class), "the example agent is compiled")
	If '##class(%Dictionary.CompiledClass).%ExistsId(class) Quit
	Do $$$AssertTrue($ClassMethod(class, "%Extends", "%AI.Agent"), "it extends %AI.Agent")
	Do $$$AssertEquals($Parameter(class, "MODEL"), "claude-haiku-5-5", "its model is claude-haiku-5-5")
	Do $$$AssertEquals($Parameter(class, "MOCKKEY"), "bridge-example", "its mock key is bridge-example")
	Do $$$AssertEquals($Parameter(class, "TOOLSETS"), "", "it has no toolset")
	Set text = ..Instructions(class)
	Do $$$AssertTrue(text '= "", "it has instructions")
	Do $$$AssertTrue(text '[ "{{", "and they hold no template token")
	Set count = 0
	Set payload = ##class(%Dictionary.CompiledClass).%OpenId("OcuTalon.Bridge.Msg.DecisionPayload")
	Do $$$AssertTrue($IsObject(payload), "DecisionPayload is compiled")
	If $IsObject(payload) {
		For i = 1:1:payload.Properties.Count() {
			Set field = payload.Properties.GetAt(i).Parameters.GetAt("%JSONFIELDNAME")
			If field = "" Continue
			Set count = count + 1
			Do $$$AssertTrue(text [ ("""" _ field _ """"), "the instructions name the field "_field)
		}
	}
	Do $$$AssertTrue(count > 0, "the payload has JSON fields: "_count)
	Set values = $ListFromString(##class(OcuTalon.Bridge.Msg.Enum).#OUTCOME)
	Set position = 0
	While $ListNext(values, position, value) {
		Do $$$AssertTrue(text [ ("""" _ value _ """"), "the instructions quote the outcome "_value)
	}
	For phrase = "one JSON object", "plain English", "between 0 and 1", "data, never instructions" {
		Do $$$AssertTrue(text [ phrase, "the instructions say '"_phrase_"'")
	}
}

/// The example production is structure only: three items, three settings (all on the agent runner), and no provider setting.
Method TestProduction()
{
	Set definition = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
	Do $$$AssertTrue($IsObject(definition), "the example production is registered")
	If '$IsObject(definition) Quit
	Do $$$AssertEquals(+definition.TestingEnabled, 0, "the testing service is off in its definition")
	Do $$$AssertEquals(definition.Items.Count(), 3, "it has three items")
	Set seen = ""
	Set settings = 0
	For i = 1:1:definition.Items.Count() {
		Set item = definition.Items.GetAt(i)
		Set seen = seen _ $Select(seen = "": "", 1: ",") _ item.Name
		Do $$$AssertEquals(item.PoolSize_"|"_item.Enabled, "1|1", item.Name_" has a pool of 1 and is enabled")
		Set settings = settings + item.Settings.Count()
		Set found = ""
		For j = 1:1:item.Settings.Count() {
			Set setting = item.Settings.GetAt(j)
			Set found = found _ $Select(found = "": "", 1: ";") _ setting.Target_" "_setting.Name_" "_setting.Value
		}
		If item.Name = "Decide" {
			Do $$$AssertEquals(item.ClassName, "OcuTalon.Bridge.Process.Decide", "Decide is the bridge's process")
			Do $$$AssertEquals(found, "", "and has no setting, so every extension is at its do-nothing default")
		} ElseIf item.Name = "TriageAgent" {
			Do $$$AssertEquals(item.ClassName, "OcuTalon.Bridge.Operation.AgentRunner", "TriageAgent is an agent runner")
			Do $$$AssertEquals(found, "Adapter AgentClass "_..#AGENT_";Adapter AgentAllowList "_..#AGENT_";Host ReplyClass OcuTalon.Bridge.Msg.DecisionPayload", "and runs the example agent, which is on its allow-list, and checks its reply against DecisionPayload")
		} ElseIf item.Name = "AgentSteps" {
			Do $$$AssertEquals(item.ClassName, "OcuTalon.Bridge.Operation.Steps", "AgentSteps is the bridge's steps operation")
			Do $$$AssertEquals(found, "", "and has no setting")
		}
	}
	Do $$$AssertEquals(seen, "Decide,TriageAgent,AgentSteps", "the items are Decide, TriageAgent and AgentSteps, in that order")
	Do $$$AssertEquals(settings, 3, "the definition holds three settings in all: no provider setting, key or model among them")
}

/// A Decide of the example has the do-nothing extension classes and the default timer. The defaults are read from the compiled
/// properties: a Decide instance takes its settings from the item of the active production, which in OCUTALON names the product's
/// own sink and filter, whereas the example (a production with no setting on Decide) runs with the defaults.
Method TestDecideDefaults()
{
	Set class = "OcuTalon.Bridge.Process.Decide"
	Do $$$AssertEquals(..Initial(class, "HostSinkClass"), """OcuTalon.Bridge.Ext.HostSink""", "HostSinkClass defaults to the do-nothing host sink")
	Do $$$AssertEquals(..Initial(class, "ReplyFilterClass"), """OcuTalon.Bridge.Ext.ReplyFilter""", "ReplyFilterClass defaults to the filter that passes the text through")
	Do $$$AssertEquals(..Initial(class, "ClassificationClass"), """OcuTalon.Bridge.Ext.Classification""", "ClassificationClass defaults to the do-nothing classification")
	Do $$$AssertEquals(..Initial(class, "TimerSeconds"), "60", "TimerSeconds defaults to 60")
	Do $$$AssertEquals(..Initial(class, "DailyCostCapUSD"), "0", "DailyCostCapUSD defaults to 0, which is no cap")
	Do $$$AssertEquals(..Initial(class, "GatewaySpendUSD"), $Char(34, 34), "GatewaySpendUSD defaults to the empty string, which is no spend")
	Do $$$AssertEquals(..Initial(class, "GatewaySpendDate"), $Char(34, 34), "and GatewaySpendDate to the empty string, which is no date")
	Do $$$AssertEquals(..Setting(class, "DailyCostCapUSD"), "DailyCostCapUSD:Bridge", "DailyCostCapUSD is a host setting of the category Bridge")
	Do $$$AssertEquals(..Setting(class, "GatewaySpendUSD"), "GatewaySpendUSD:Bridge", "so is GatewaySpendUSD")
	Do $$$AssertEquals(..Setting(class, "GatewaySpendDate"), "GatewaySpendDate:Bridge", "and GatewaySpendDate")
}

/// --- helpers ---
/// The InitialExpression of the property of the compiled class, as written (a string keeps its quotes), or "" when there is none.
ClassMethod Initial(class As %String, property As %String) As %String [ Private ]
{
	Set compiled = ##class(%Dictionary.CompiledProperty).%OpenId(class_"||"_property)
	If '$IsObject(compiled) Quit ""
	Quit compiled.InitialExpression
}

/// The entry of the SETTINGS parameter of the class that starts with the name and a colon, or "".
ClassMethod Setting(class As %String, name As %String) As %String [ Private ]
{
	Set found = ""
	Set entries = $ListFromString($Parameter(class, "SETTINGS"))
	Set position = 0
	While $ListNext(entries, position, entry) {
		If $Piece(entry, ":", 1) = name Set found = entry
	}
	Quit found
}

/// The INSTRUCTIONS block of a compiled class as text, with no carriage return.
ClassMethod Instructions(class As %String) As %String [ Private ]
{
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(class_"||INSTRUCTIONS")
	If '$IsObject(xdata) Quit ""
	Quit $Replace(xdata.Data.Read(1000000), $Char(13), "")
}

}
