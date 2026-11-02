/// The server side of "leaving the page frees its place" that needs no production (Story 16.4, acceptance criteria 1 and 2; AD-4, AD-24).
///   - TestOnlineFlagChangesOnlyTheTimeout: the Web step's applications with the online-demo flag on and with it off differ in the Timeout of
///     the four sign-in-group applications and in nothing else (so the story adds no role, no grant, no event class and no permitted class
///     under the flag), and /ocutalon/public keeps its Timeout;
///   - TestNoProductClassEndsASessionOnTimeout: no class of the product defines OnTimeout, OnEndSession or OnLogout, the CSP session
///     callbacks, so that a CSP session that ends (a closed page, the idle cap, the timeout) ends nothing else and no CSP session's end can
///     reach an OcuTalon session. The probe of the tests (Test.Web.LogoutProbe) does define one, which shows the query can find it.
/// TestOnlineFlagChangesOnlyTheTimeout sets the public setting onlineDemo to 0 and then to 1 while it reads the definitions, which makes the
/// instance the online demo for that moment, and puts it back, also after a failure; the class needs no production and changes no
/// application.
Class OcuTalon.Test.Web.LeavingThePage Extends %UnitTest.TestCase
{

/// Definitions and the OCUORDERS trace application with the flag on and with it off differ only in Timeout; the four sign-in-group
/// applications differ in it (120 against 28800), /ocutalon/public does not, and no other key differs or is missing on either side.
Method TestOnlineFlagChangesOnlyTheTimeout()
{
	Set saved = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set error = ""
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Definitions(.off), "Definitions with the flag off")
		Set orders = ##class(OcuTalon.Install.Step.Web).TraceApp("OCUORDERS", .offOrders)
		Merge off(orders) = offOrders
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Web).Definitions(.on), "Definitions with the flag on")
		Do ##class(OcuTalon.Install.Step.Web).TraceApp("OCUORDERS", .onOrders)
		Merge on(orders) = onOrders

		Set other = "", timeouts = ""
		Set name = ""
		For {
			Set name = $Order(on(name))
			Quit:name=""
			Set key = ""
			For {
				Set key = $Order(on(name, key))
				Quit:key=""
				If '$Data(off(name, key)) Set other = other_$Select(other = "": "", 1: ", ")_name_" gains "_key Continue
				If on(name, key) = off(name, key) Continue
				If key = "Timeout" {
					Set timeouts = timeouts_$ListBuild(name_"="_on(name, key)_"/"_off(name, key))
				} Else {
					Set other = other_$Select(other = "": "", 1: ", ")_name_"."_key
				}
			}
		}
		Set name = ""
		For {
			Set name = $Order(off(name))
			Quit:name=""
			Set key = ""
			For {
				Set key = $Order(off(name, key))
				Quit:key=""
				If '$Data(on(name, key)) Set other = other_$Select(other = "": "", 1: ", ")_name_" loses "_key
			}
		}
		Do $$$AssertEquals(other, "", "nothing but a Timeout differs between the flag on and off: "_other)
		Do $$$AssertEquals($ListLength(timeouts), 4, "four applications differ in Timeout")
		For each = "/ocutalon", "/ocutalon/api", "/ocutalon/trace/ocutalon", orders {
			Do $$$AssertTrue($ListFind(timeouts, each_"=120/28800") > 0, each_" has 120 with the flag on and 28800 with it off")
		}
		Do $$$AssertEquals(on("/ocutalon/public", "Timeout")_"|"_off("/ocutalon/public", "Timeout"), "28800|28800", "/ocutalon/public keeps 28800 either way")
	} Catch exception {
		Set error = exception.DisplayString()
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", saved)
	Do $$$AssertEquals(error, "", "the checks ran without an error")
}

/// No class of the product (OcuTalon.*, the tests of OcuTalon.Test.* apart) defines OnTimeout, OnEndSession or OnLogout; the tests' probe
/// does, and the query finds it.
Method TestNoProductClassEndsASessionOnTimeout()
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT parent, Name FROM %Dictionary.MethodDefinition WHERE Name IN ('OnTimeout', 'OnEndSession', 'OnLogout') AND parent LIKE 'OcuTalon.%'")
	Do $$$AssertEquals(rs.%SQLCODE, 0, "the class dictionary is read")
	Set product = "", tests = ""
	While rs.%Next() {
		Set one = rs.%Get("parent")_"."_rs.%Get("Name")
		If $Extract(rs.%Get("parent"), 1, 14) = "OcuTalon.Test." {
			Set tests = tests_$ListBuild(one)
		} Else {
			Set product = product_$Select(product = "": "", 1: ", ")_one
		}
	}
	Do $$$AssertEquals(product, "", "no product class defines a CSP session callback: "_product)
	Do $$$AssertTrue($ListFind(tests, "OcuTalon.Test.Web.LogoutProbe.OnLogout") > 0, "control: the tests' own probe defines OnLogout, so the query finds a callback")
}

}
