/// Test of the shared Orders-definition fixture (Story 9.6, DW-385; QA). WARM-SAFE: it reads class definitions only, touches no definition, no production and no
/// table. OcuTalon.Test.Watch.OrdersDefinition is the one place that puts the credential-named settings and the plain note into the saved Orders definition,
/// for Test.Watch.Evidence and Test.Eval.Record. The behaviour of the helper is pinned by those two classes (they assert on the settings it puts and removes);
/// this class pins the other half of the criterion, that no private copy of the fixture is left in either of them.
///   - TestNoPrivateCopy: Test.Watch.Evidence and Test.Eval.Record define no method FixtureSettings or DefinedSettings, and none of their own methods builds an
///     Ens.Config.Setting (the object the copy inserted), under any name;
///   - TestHelperIsNotATest: the helper is not a %UnitTest.TestCase and has no method named Test..., so it is never run as a test; it has Put and Defined;
///   - TestNamesAreTheHelpers: the credential names and the note name that the two classes use are the helper's own parameters, so the two cannot drift.
Class OcuTalon.Test.Eval.SharedFixture Extends %UnitTest.TestCase
{

/// The shared helper.
Parameter HELPER = "OcuTalon.Test.Watch.OrdersDefinition";

/// The classes that used to hold a private copy, comma-separated.
Parameter USERS = "OcuTalon.Test.Watch.Evidence,OcuTalon.Test.Eval.Record";

Method TestNoPrivateCopy()
{
	For i = 1:1:$Length(..#USERS, ",") {
		Set class = $Piece(..#USERS, ",", i)
		Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(class), class_" is compiled")
		For name = "FixtureSettings", "DefinedSettings" {
			Do $$$AssertTrue('##class(%Dictionary.CompiledMethod).%ExistsId(class_"||"_name), class_" defines no method "_name)
		}
		Set own = 0, building = ""
		Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledMethod WHERE parent = ? AND Origin = ?", class, class)
		While result.%Next() {
			Set own = own + 1
			Set method = ##class(%Dictionary.CompiledMethod).%OpenId(class_"||"_result.%Get("Name"))
			If '$IsObject(method) Continue
			Do method.Implementation.Rewind()
			Set code = method.Implementation.Read(3000000)
			If code [ "Ens.Config.Setting" Set building = building_" "_result.%Get("Name")
		}
		Do $$$AssertTrue(own > 5, class_" has its own methods, so the scan can find something (a control): "_own)
		Do $$$AssertEquals(building, "", class_": no method of its own builds an Ens.Config.Setting")
	}
}

Method TestHelperIsNotATest()
{
	Set helper = ..#HELPER
	Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(helper), "the helper is compiled")
	Do $$$AssertTrue('$ClassMethod(helper, "%Extends", "%UnitTest.TestCase"), "it is not a %UnitTest.TestCase")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM %Dictionary.CompiledMethod WHERE parent = ? AND Name %STARTSWITH 'Test'", helper)
	Do result.%Next()
	Do $$$AssertEquals(+result.%GetData(1), 0, "and none of its methods is named Test...")
	For name = "Put", "Defined" {
		Do $$$AssertTrue(##class(%Dictionary.CompiledMethod).%ExistsId(helper_"||"_name), "it has the method "_name)
	}
}

Method TestNamesAreTheHelpers()
{
	Set helper = ..#HELPER
	Do $$$AssertTrue($Parameter(helper, "CREDENTIALS") '= "", "the helper names the credential settings: "_$Parameter(helper, "CREDENTIALS"))
	Do $$$AssertTrue($Parameter(helper, "NOTE") '= "", "and the plain note: "_$Parameter(helper, "NOTE"))
	Do $$$AssertEquals($Parameter("OcuTalon.Test.Eval.Record", "CREDENTIALS"), $Parameter(helper, "CREDENTIALS"), "Test.Eval.Record uses the helper's credential names")
	Do $$$AssertEquals($Parameter("OcuTalon.Test.Eval.Record", "NOTE"), $Parameter(helper, "NOTE"), "and its note name")
	Do $$$AssertEquals($Parameter("OcuTalon.Test.Eval.Record", "ORDERSITEM"), $Parameter(helper, "ITEM"), "and its item")
	Do $$$AssertEquals($Parameter("OcuTalon.Test.Watch.Evidence", "NOTE"), $Parameter(helper, "NOTE"), "Test.Watch.Evidence uses the helper's note name")
}

}
