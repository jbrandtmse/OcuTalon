/// Rule-based tests of OcuTalon.Production (Story 0.6, matrix row 1), written from the architecture spine and not from the
/// item oracle of OcuTalon.Test.Install.Production, so that a lane or a pool size that the oracle and the definition get
/// wrong together still fails here. Nothing starts, stops or updates a production, and nothing is written.
///   - TestSingleDefinitionBlock: the class holds exactly one XData block, ProductionDefinition (AD-29);
///   - TestLanesFollowThePackageSplit: every item sits in the region of the lane that owns its class by AD-29's package
///     split (the Workflow operation and the two routers by the ownership table), the routers by the package of their
///     rule class, and the runners by the package of their agent class;
///   - TestDisabledItems: TelegramIn, TelegramOut and EvalIn are disabled in the definition (AD-29, AD-23);
///   - TestPoolSizes: an adapterless business service has pool size 0, and every other item has a pool of at least 1;
///   - TestRoutingRules: the two routers are routing engines whose rule classes are rule definitions for the routing engine.
Class OcuTalon.Test.Install.ProductionRules Extends %UnitTest.TestCase
{

/// The production under test.
Parameter PRODUCTION = "OcuTalon.Production";

/// The items the definition always disables, comma-separated: the Telegram items are switched on by the Telegram step and
/// EvalIn by its System Default Setting (AD-23, AD-22).
Parameter DISABLED = "EvalIn,TelegramIn,TelegramOut";

/// The class holds one XData block, and it is the production definition.
Method TestSingleDefinitionBlock()
{
	Set class = ##class(%Dictionary.CompiledClass).%OpenId(..#PRODUCTION)
	Do $$$AssertTrue($IsObject(class), "the production class is compiled")
	If '$IsObject(class) Quit
	Set names = ""
	For i = 1:1:class.XDatas.Count() {
		Set names = names _ $Select(names = "": "", 1: ",") _ class.XDatas.GetAt(i).Name
	}
	Do $$$AssertEquals(names, "ProductionDefinition", "the production class holds the one block ProductionDefinition")
}

/// Every item sits between the markers of the lane that owns its class: by the package of its class, by the ownership table
/// for the stock classes, by the package of the rule class for a router and by the package of the agent class for a runner.
Method TestLanesFollowThePackageSplit()
{
	Do ..Regions(.laneOf)
	Set production = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
	Do $$$AssertTrue($IsObject(production), "the compiled production exists")
	If '$IsObject(production) Quit
	Set lanes = ""
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		Set name = item.Name
		Set class = item.ClassName
		Set expected = ..LaneOfClass(class)
		If expected = "" {
			Set expected = $Case(name, "OcuTalonApprovals": "A", "OutcomeRouter": "B", "Notify": "B", : "")
		}
		Do $$$AssertTrue(expected '= "", name_": the lane of "_class_" is known from the package split or the ownership table")
		Do $$$AssertEquals($Get(laneOf(name)), expected, name_" sits in the region of lane "_expected)
		Set lanes = lanes _ $Select($Get(laneOf(name)) = "": "", 1: $Get(laneOf(name)))
		For j = 1:1:item.Settings.Count() {
			Set setting = item.Settings.GetAt(j)
			If setting.Name = "BusinessRuleName" {
				Do $$$AssertEquals(..LaneOfClass(setting.Value), expected, name_": its rule class "_setting.Value_" belongs to the same lane")
			}
			If setting.Name = "AgentClass" {
				Do $$$AssertEquals(..LaneOfClass(setting.Value), expected, name_": its agent class "_setting.Value_" belongs to the same lane")
			}
		}
	}
	Do $$$AssertTrue(lanes [ "A", "lane A has items")
	Do $$$AssertTrue(lanes [ "B", "lane B has items")
	Set found = 0
	Set name = ""
	For {
		Set name = $Order(laneOf(name))
		Quit:name=""
		Set found = found + 1
	}
	Do $$$AssertEquals(found, production.Items.Count(), "the markers' regions hold exactly the items of the compiled production")
}

/// TelegramIn, TelegramOut and EvalIn are disabled in the definition. A release cut may disable more items, each in its
/// lane's region (AD-29); the item oracle of OcuTalon.Test.Install.Production pins the flag of every item.
Method TestDisabledItems()
{
	Set production = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
	If '$IsObject(production) Do $$$AssertTrue(0, "the compiled production exists") Quit
	Kill off
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		If 'item.Enabled Set off(item.Name) = ""
	}
	Set missing = ""
	For i = 1:1:$Length(..#DISABLED, ",") {
		Set name = $Piece(..#DISABLED, ",", i)
		If '$Data(off(name)) Set missing = missing _ " " _ name
	}
	Do $$$AssertEquals(missing, "", "TelegramIn, TelegramOut and EvalIn are disabled")
}

/// An adapterless business service has pool size 0 (no job); every other item has a pool of at least 1.
Method TestPoolSizes()
{
	Set production = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
	If '$IsObject(production) Do $$$AssertTrue(0, "the compiled production exists") Quit
	Set adapterless = 0
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		Set class = item.ClassName
		Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(class), item.Name_": "_class_" is compiled")
		Set service = $ClassMethod(class, "%Extends", "Ens.BusinessService")
		If service && ($Parameter(class, "ADAPTER") = "") {
			Set adapterless = adapterless + 1
			Do $$$AssertEquals(item.PoolSize, 0, item.Name_" is an adapterless service with pool size 0")
		} Else {
			Do $$$AssertTrue(item.PoolSize >= 1, item.Name_" has a pool of at least 1: "_item.PoolSize)
		}
	}
	Do $$$AssertTrue(adapterless > 0, "the production holds adapterless services: "_adapterless)
}

/// OutcomeRouter and Notify are routing engines; the rule class of each extends Ens.Rule.Definition for the routing engine.
Method TestRoutingRules()
{
	Set production = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
	If '$IsObject(production) Do $$$AssertTrue(0, "the compiled production exists") Quit
	Set routers = 0
	For i = 1:1:production.Items.Count() {
		Set item = production.Items.GetAt(i)
		If '$ListFind($ListBuild("OutcomeRouter", "Notify"), item.Name) Continue
		Set routers = routers + 1
		Do $$$AssertEquals(item.ClassName, "EnsLib.MsgRouter.RoutingEngine", item.Name_" is a routing engine")
		Set rule = ""
		For j = 1:1:item.Settings.Count() {
			If item.Settings.GetAt(j).Name = "BusinessRuleName" Set rule = item.Settings.GetAt(j).Value
		}
		Set expectedRule = $Select(item.Name = "OutcomeRouter": "OcuTalon.Core.Rule.Outcome", 1: "OcuTalon.Core.Rule.Notify")
		Do $$$AssertEquals(rule, expectedRule, item.Name_" names its rule class "_expectedRule)
		Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(rule), rule_" is compiled")
		Do $$$AssertTrue($ClassMethod(rule, "%Extends", "Ens.Rule.Definition"), rule_" extends Ens.Rule.Definition")
		Do $$$AssertEquals($Parameter(rule, "RuleAssistClass"), "EnsLib.MsgRouter.RuleAssist", rule_" is a rule definition for the routing engine")
	}
	Do $$$AssertEquals(routers, 2, "the production holds the two routers")
}

/// --- helpers ---
/// The lane that AD-29's package split gives a class of OcuTalon, or "" for any other class. Lane A is tested first because
/// OcuTalon.Channel.Telegram belongs to it and sits inside Lane B's OcuTalon.Channel.
ClassMethod LaneOfClass(class As %String) As %String [ Private ]
{
	Set laneA = $ListBuild("OcuTalon.Bridge.", "OcuTalon.BridgeExample.", "OcuTalon.Agent.", "OcuTalon.Tools.", "OcuTalon.Watch.", "OcuTalon.Fix.", "OcuTalon.Checks.", "OcuTalon.Digest.", "OcuTalon.Memory.", "OcuTalon.Docs.", "OcuTalon.Mcp.", "OcuTalon.Eval.", "OcuTalon.Channel.Telegram.")
	Set laneB = $ListBuild("OcuTalon.Web.", "OcuTalon.Channel.", "OcuTalon.Core.", "OcuTalon.Schedule.", "OcuTalon.Demo.", "OcuTalon.Live.", "OcuTalon.Msg.", "OcuTalon.Data.")
	If ..StartsWithAny(class, laneA) Quit "A"
	If ..StartsWithAny(class, laneB) Quit "B"
	Quit ""
}

/// 1 when the text starts with any prefix of the list.
ClassMethod StartsWithAny(text As %String, prefixes As %List) As %Boolean [ Private ]
{
	Set position = 0
	While $ListNext(prefixes, position, prefix) {
		If $Extract(text, 1, $Length(prefix)) = prefix Return 1
	}
	Quit 0
}

/// The lane of each item, from the markers of the definition text: laneOf(item name) = "A" or "B", and "" for an item
/// outside both regions.
ClassMethod Regions(ByRef laneOf) [ Private ]
{
	Kill laneOf
	Set xdata = ##class(%Dictionary.CompiledXData).%OpenId(..#PRODUCTION_"||ProductionDefinition")
	If '$IsObject(xdata) Quit
	Set text = $Replace(xdata.Data.Read(1000000), $Char(13), "")
	Set lane = ""
	For i = 1:1:$Length(text, $Char(10)) {
		Set line = $ZStrip($Piece(text, $Char(10), i), "<>W")
		If line = "<!-- lane A: begin -->" Set lane = "A" Continue
		If line = "<!-- lane B: begin -->" Set lane = "B" Continue
		If (line = "<!-- lane A: end -->") || (line = "<!-- lane B: end -->") Set lane = "" Continue
		If $Extract(line, 1, 6) = "<Item " {
			Set laneOf($Piece($Piece(line, " Name=""", 2), """", 1)) = lane
		}
	}
}

}
