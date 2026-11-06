/// Tests of the slot type dailyCost of OcuTalon.Msg.Catalog (Story 33.2; AD-32): US dollars of 0 or more, always with two decimals, where the
/// type cost has the tiers of the UX's Formats rule. The texts come from OcuTalon.Test.Msg.DailyCostCatalog, a renderer with a catalog class of
/// its own, so that no product key is needed. Every expected text is written out here. Safe on a slot.
///   - TestTwoDecimals: zero, whole dollars, cents, a sum over a thousand (no separator) and a very small amount all have two decimals;
///   - TestRounding: an amount rounds to the cent, half up;
///   - TestDiffersFromCost: the same amounts under the type cost have the tiers, so the type is not a synonym;
///   - TestRefused: a negative amount, a string, a missing slot and a null are refused with the key and the slot named, and no text;
///   - TestChannels: the web page and the message channels give the same text.
Class OcuTalon.Test.Msg.DailyCost Extends %UnitTest.TestCase
{

/// The renderer under test.
Parameter RENDERER = "OcuTalon.Test.Msg.DailyCostCatalog";

/// Zero, whole dollars, cents, a sum over a thousand and a very small amount have two decimals and nothing else.
Method TestTwoDecimals()
{
	Set cases = $ListBuild($ListBuild(0, "$0.00"), $ListBuild(1, "$1.00"), $ListBuild(12, "$12.00"), $ListBuild(0.4, "$0.40"), $ListBuild(0.07, "$0.07"), $ListBuild(3.5, "$3.50"), $ListBuild(1234.5, "$1234.50"), $ListBuild(100000, "$100000.00"), $ListBuild(0.00001, "$0.00"), $ListBuild(0.0049, "$0.00"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set text = ..Render("test.daily", $List(case, 1), .sc)
		Do $$$AssertStatusOK(sc, $List(case, 1)_" renders")
		Do $$$AssertEquals(text, "Cost "_$List(case, 2)_".", $List(case, 1)_" is "_$List(case, 2))
	}
}

/// An amount rounds to the cent, half up, so 0.005 is a cent and 0.0049 is none.
Method TestRounding()
{
	Set cases = $ListBuild($ListBuild(0.005, "$0.01"), $ListBuild(0.0049, "$0.00"), $ListBuild(0.994, "$0.99"), $ListBuild(0.995, "$1.00"), $ListBuild(12.346, "$12.35"), $ListBuild(12.344, "$12.34"), $ListBuild(9.999, "$10.00"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Do $$$AssertEquals(..Render("test.daily", $List(case, 1)), "Cost "_$List(case, 2)_".", $List(case, 1)_" rounds to "_$List(case, 2))
	}
}

/// The type cost shows the tiers of the Formats rule for the amounts where they differ, and dailyCost never does.
Method TestDiffersFromCost()
{
	Set cases = $ListBuild($ListBuild(0.00001, "<$0.0001", "$0.00"), $ListBuild(0.005, "$0.0050", "$0.01"), $ListBuild(0.123, "$0.123", "$0.12"), $ListBuild(0, "<$0.0001", "$0.00"), $ListBuild(2.5, "$2.50", "$2.50"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Do $$$AssertEquals(..Render("test.tiered", $List(case, 1)), "Cost "_$List(case, 2)_".", $List(case, 1)_" under cost: "_$List(case, 2))
		Do $$$AssertEquals(..Render("test.daily", $List(case, 1)), "Cost "_$List(case, 3)_".", $List(case, 1)_" under dailyCost: "_$List(case, 3))
	}
}

/// A negative amount, a string, a missing slot and a null are refused: no text, and an error that names the key and the slot.
Method TestRefused()
{
	Set bad = $ListBuild($ListBuild("a negative amount", "{""cost"": -0.01}"), $ListBuild("a negative whole amount", "{""cost"": -1}"), $ListBuild("a string", "{""cost"": ""3""}"), $ListBuild("a missing slot", "{}"), $ListBuild("a null", "{""cost"": null}"), $ListBuild("an object", "{""cost"": {""a"": 1}}"), $ListBuild("a boolean", "{""cost"": true}"))
	Set position = 0
	While $ListNext(bad, position, case) {
		Set text = ##class(OcuTalon.Test.Msg.DailyCostCatalog).Render("test.daily", $List(case, 2), "telegram", .sc)
		Do $$$AssertStatusNotOK(sc, $List(case, 1)_" is refused")
		Do $$$AssertEquals(text, "", $List(case, 1)_": there is no text")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "test.daily", $List(case, 1)_": the error names the key")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ("slot "_$Char(39)_"cost"_$Char(39)), $List(case, 1)_": and the slot")
	}
	Set text = ##class(OcuTalon.Test.Msg.DailyCostCatalog).Render("test.daily", {"cost": -2}, "telegram", .sc)
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "negative", "a negative amount says so")
}

/// The web page and the message channels give the same text.
Method TestChannels()
{
	For channel = "web", "phone", "mailbox", "telegram" {
		Set text = ##class(OcuTalon.Test.Msg.DailyCostCatalog).Render("test.daily", {"cost": 4.2}, channel, .sc)
		Do $$$AssertStatusOK(sc, channel_" renders")
		Do $$$AssertEquals(text, "Cost $4.20.", channel_": the same text")
	}
}

/// --- helpers ---
/// The text of the key for the amount on the web channel.
ClassMethod Render(key As %String, amount As %Numeric, Output sc As %Status) As %String [ Private ]
{
	Quit $ClassMethod(..#RENDERER, "Render", key, {"cost": (amount)}, "web", .sc)
}

}
