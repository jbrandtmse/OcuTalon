/// Tests of the values that OcuTalon.Data.Setting.Get returns (QA, Story 0.4, AD-19): a value that looks false or
/// numeric is still a value, and the default argument is optional. Only an absent or an empty value gives the default.
/// The fixture keys are zz.<n>.<name>, with n from ^OcuTalonTest("SettingValues","n"), which is never reset. Their rows and
/// cache entries are removed in OnBeforeAllTests and again in OnAfterAllTests.
Class OcuTalon.Test.Data.SettingValues Extends %UnitTest.TestCase
{

/// The names of the fixture keys.
Parameter NAMES = "zero,leading,word,decimal,absent";

/// The fixture's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("SettingValues", "n"))
	Do ..Clean()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit $$$OK
}

/// A value of "0", "007", "false" or "0.50" is returned as it was seeded, on the read that loads the cache and on the
/// read that serves it from the cache; none of them is taken for an empty value.
Method TestValuesThatLookFalseOrNumericAreValues()
{
	Set values("zero") = "0"
	Set values("leading") = "007"
	Set values("word") = "false"
	Set values("decimal") = "0.50"
	Set name = ""
	For {
		Set name = $Order(values(name), 1, value)
		Quit:name=""
		Set key = ..FixtureKey(name)
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Seed(key, value), "the key "_key_" is seeded with '"_value_"'")
		Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(key, "default"), value, "'"_value_"' is read from the row")
		Do $$$AssertTrue($Data(^||OcuTalon.Setting(key)), "the value is cached")
		Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(key, "default"), value, "'"_value_"' is read from the cache")
	}
}

/// The default argument is optional and gives an empty string for an absent key.
Method TestDefaultIsOptional()
{
	Set key = ..FixtureKey("absent")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(key), "", "an absent key gives an empty string when no default is passed")
	Do $$$AssertEquals(##class(OcuTalon.Data.Setting).Get(key, "0"), "0", "an absent key gives a default of 0")
	Do $$$AssertTrue('##class(OcuTalon.Data.Setting).KeyIndexExists(key), "reading an absent key writes no row")
}

/// The fixture key of a name.
Method FixtureKey(name As %String) As %String [ Private ]
{
	Quit "zz."_..Number_"."_name
}

/// Removes the rows and the cache entries of the fixture keys.
Method Clean() [ Private ]
{
	Set names = $ListFromString(..#NAMES)
	Set position = 0
	While $ListNext(names, position, name) {
		Set key = ..FixtureKey(name)
		If ##class(OcuTalon.Data.Setting).KeyIndexExists(key, .id) Do ##class(OcuTalon.Data.Setting).%DeleteId(id)
		Kill ^||OcuTalon.Setting(key)
	}
}

}
