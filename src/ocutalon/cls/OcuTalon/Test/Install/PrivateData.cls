/// Tests of the private-data check that ends every start (AD-3, AD-23): it passes on OCUTALON with its
/// mappings, and it fails, naming the global, for a private-prefix global planted in OCUTALON_DATA and for a
/// namespace without the private mappings. The planted globals are removed after each test and again in
/// OnAfterAllTests, and the fixture classes are deleted in both OnBeforeAllTests and OnAfterAllTests.
Class OcuTalon.Test.Install.PrivateData Extends %UnitTest.TestCase
{

/// The globals that the tests plant straight into the data database, without the caret.
Parameter PLANTED = "OcuTalonP.ZzPlanted,OcuTalonBP.ZzPlanted,AI.Agent.SessionZzPlanted,IRIS.IF.ZzPlanted";

/// The fixture classes that the tests compile: a class with a private default global, one with a global that
/// is not private, and a subclass of the check that exposes its mapping confirmation.
Parameter FIXTURES = "OcuTalon.Test.Install.ZzPrivateFixture,OcuTalon.Test.Install.ZzPublicFixture,OcuTalon.Test.Install.ZzPrivateProbe";

Method OnBeforeAllTests() As %Status
{
	Do ..RemoveFixtures()
	Do ..Unplant()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..RemoveFixtures()
	Do ..Unplant()
	Quit $SYSTEM.Status.OK()
}

/// Given OCUTALON with its mappings, the check passes.
Method TestPasses()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).Run(), "the private-data check passes")
}

/// A private-prefix global in OCUTALON_DATA fails the check, which names it.
Method TestPlantedGlobalFails()
{
	Set planted = $ListFromString(..#PLANTED)
	Set position = 0
	While $ListNext(planted, position, global) {
		Do ..Plant(global)
		Set sc = ##class(OcuTalon.Install.Step.PrivateData).Run()
		Do ..Unplant()
		Do $$$AssertStatusNotOK(sc, "the check fails for ^"_global)
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ ("^"_global), "the error names ^"_global)
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).Run(), "the check passes again once they are removed")
}

/// A compiled OcuTalon class with a private default global is found by the check, a class whose global is not
/// private is not, and the check still passes.
Method TestPrivateStorageGlobals()
{
	Set class = "OcuTalon.Test.Install.ZzPrivateFixture"
	Set public = "OcuTalon.Test.Install.ZzPublicFixture"
	Do ..RemoveFixtures()
	Set sc = ..Compile(class, ..FixtureText(class, "^OcuTalonP.ZzFixture"))
	If $$$ISOK(sc) Set sc = ..Compile(public, ..FixtureText(public, "^OcuTalonZzPublic"))
	Do $$$AssertStatusOK(sc, "the fixture classes compile")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).StorageGlobals(.storage), "the storage globals are read")
	Do $$$AssertTrue($Data(storage("OcuTalonP.ZzFixtureD")), "the fixture's data global is listed")
	Do $$$AssertTrue($Data(storage("OcuTalonP.ZzFixtureI")), "the fixture's index global is listed")
	Do $$$AssertTrue('$Data(storage("OcuTalonZzPublicD")), "a global without a private prefix is not")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).Run(), "the check passes with the fixtures compiled")
	Do $SYSTEM.OBJ.Delete(class, "-d")
	Do $SYSTEM.OBJ.Delete(public, "-d")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).StorageGlobals(.storage), "the storage globals are read again")
	Do $$$AssertTrue('$Data(storage("OcuTalonP.ZzFixtureD")), "the fixture's global is gone with its class")
}

/// Given a namespace without OCUTALON's private mappings, the mapping confirmation fails and names the private
/// database. Given OCUTALON it passes. The check is reached through a subclass, because its method is private.
Method TestMappingMismatchFails()
{
	Set probe = "OcuTalon.Test.Install.ZzPrivateProbe"
	Do $SYSTEM.OBJ.Delete(probe, "-d")
	Set text = "Class "_probe_" Extends OcuTalon.Install.Step.PrivateData"_$Char(10)_"{"_$Char(10)_"ClassMethod CheckIn(namespace As %String) As %Status"_$Char(10)_"{"_$Char(10)_$Char(9)_"Quit ..Check(namespace, .storage)"_$Char(10)_"}"_$Char(10)_"}"
	Do $$$AssertStatusOK(..Compile(probe, text), "the probe class compiles")
	Do $$$AssertStatusOK($ClassMethod(probe, "CheckIn", $Namespace), "the mappings of "_$Namespace_" pass")
	Set sc = $ClassMethod(probe, "CheckIn", "USER")
	Do $$$AssertStatusNotOK(sc, "a namespace without the private mappings fails")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "not to OCUTALON_PRIVATE", "the error names the private database")
	Do $SYSTEM.OBJ.Delete(probe, "-d")
}

/// The source of a persistent class with the given default global.
ClassMethod FixtureText(class As %String, defaultGlobal As %String) As %String [ Private ]
{
	Quit "Class "_class_" Extends %Persistent"_$Char(10)_"{"_$Char(10)_"Parameter DEFAULTGLOBAL = """_defaultGlobal_""";"_$Char(10)_"Property Name As %String;"_$Char(10)_"}"
}

/// Creates a class from its source text and compiles it.
ClassMethod Compile(class As %String, text As %String) As %Status [ Private ]
{
	Set sc = ##class(%Compiler.UDL.TextServices).SetTextFromString($Namespace, class, text, $Char(10))
	If $$$ISOK(sc) Set sc = $SYSTEM.OBJ.Compile(class, "ck-d")
	Quit sc
}

ClassMethod RemoveFixtures() [ Private ]
{
	Set fixtures = $ListFromString(..#FIXTURES)
	Set position = 0
	While $ListNext(fixtures, position, class) {
		Do $SYSTEM.OBJ.Delete(class, "-d")
	}
}

/// The reference of the data database: the directory where an unmapped global of this namespace lives.
ClassMethod DataReference() As %String [ Private ]
{
	Quit "^^"_$Piece(##class(%SYS.Namespace).GetGlobalDest($Namespace, "^OcuTalonZzUnmapped"), "^", 2)
}

ClassMethod Plant(global As %String) [ Private ]
{
	Set @("^|"""_..DataReference()_"""|"_global) = 1
}

ClassMethod Unplant() [ Private ]
{
	Set reference = "^|"""_..DataReference()_"""|"
	Set planted = $ListFromString(..#PLANTED)
	Set position = 0
	While $ListNext(planted, position, global) {
		Kill @(reference_global)
	}
}

}
