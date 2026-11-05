/// Tests of the private-data check that ends every start (AD-3, AD-23): it passes on OCUTALON with its
/// mappings, and it fails, naming the global, for a private-prefix global planted in OCUTALON_DATA, for a
/// namespace without the private mappings and for a storage global that does not resolve to OCUTALON_PRIVATE.
/// The planted globals are removed after each test and again in OnAfterAllTests, and the fixture classes are
/// deleted in both OnBeforeAllTests and OnAfterAllTests. From step 3 (Story 34.1) the check also covers the memory and
/// document globals and the knowledge-base tables (schema OcuTalonKB): a table with the private DEFAULTGLOBAL passes and one
/// without it fails and is named; the two tables the tests create are dropped after every test whatever its outcome, so no
/// knowledge-base table is left to change the globals the other tests list.
Class OcuTalon.Test.Install.PrivateData Extends %UnitTest.TestCase
{

/// The globals that the tests plant straight into the data database, without the caret.
Parameter PLANTED = "OcuTalonP.ZzPlanted,OcuTalonBP.ZzPlanted,AI.Agent.SessionZzPlanted,IRIS.IF.ZzPlanted";

/// The fixture classes that the tests compile: a class with a private default global, one with a global that
/// is not private, a subclass of the check that exposes its mapping confirmation, and a subclass whose
/// storage globals name a global of the data database.
Parameter FIXTURES = "OcuTalon.Test.Install.ZzPrivateFixture,OcuTalon.Test.Install.ZzPublicFixture,OcuTalon.Test.Install.ZzPrivateProbe,OcuTalon.Test.Install.ZzStorageProbe";

/// The knowledge-base tables that TestKnowledgeBaseTables creates: one with the private DEFAULTGLOBAL, one without it.
Parameter KBTABLES = "OcuTalonKB.Zz341,OcuTalonKB.Zz341Bad";

Method OnBeforeAllTests() As %Status
{
	Do ..DropKnowledgeBaseTables()
	Do ..RemoveFixtures()
	Do ..Unplant()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ..DropKnowledgeBaseTables()
	Do ..RemoveFixtures()
	Do ..Unplant()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Do ..DropKnowledgeBaseTables()
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

/// Given the step 3 tables, the check lists their private globals, and its prefixes and mapping samples still hold ^IRIS.IF.*.
Method TestStep3Globals()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).StorageGlobals(.storage), "the storage globals are read")
	Do $$$AssertEquals($Get(storage("OcuTalonP.MemoryD")), "OcuTalon.Data.Memory", "the memory data global is listed with its class")
	Do $$$AssertEquals($Get(storage("OcuTalonP.DocumentD")), "OcuTalon.Data.Document", "the document data global is listed with its class")
	Do $$$AssertTrue($Data(storage("OcuTalonP.DocumentS")), "the document stream global is listed")
	Do $$$AssertTrue($ListFind($ListFromString(##class(OcuTalon.Install.Step.PrivateData).#PREFIXES), "IRIS.IF."), "the data database scan still looks for ^IRIS.IF.*")
	Do $$$AssertTrue($ListFind($ListFromString(##class(OcuTalon.Install.Step.PrivateData).#SAMPLES), "IRIS.IF.Zz"), "the mapping sample for ^IRIS.IF.* is still checked")
}

/// A knowledge-base table made with the private DEFAULTGLOBAL has its globals listed and passes the check. One made without it
/// fails the check, which names its class and its global.
Method TestKnowledgeBaseTables()
{
	Do ..DropKnowledgeBaseTables()
	Set good = "OcuTalonKB.Zz341"
	Set bad = "OcuTalonKB.Zz341Bad"
	Set sc = ..CreateTable(good, "WITH %CLASSPARAMETER DEFAULTGLOBAL = '^OcuTalonP.KBZz341'")
	Do $$$AssertStatusOK(sc, "the table with the private DEFAULTGLOBAL is created")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).StorageGlobals(.storage), "the storage globals are read")
	Set listed = 0
	Set outside = 0
	Set global = ""
	For {
		Set global = $Order(storage(global))
		Quit:global=""
		If storage(global) '= good Continue
		Set listed = listed + 1
		If $Extract(global, 1, 15) '= "OcuTalonP.KBZz3" Set outside = outside + 1
	}
	Do $$$AssertTrue(listed >= 4, "the knowledge-base table lists its data, index and id globals and its storage indexes ("_listed_")")
	Do $$$AssertEquals(outside, 0, "every global of the private knowledge-base table is under ^OcuTalonP.KBZz341")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).Run(), "the check passes with a private knowledge-base table")
	Set sc = ..CreateTable(bad, "")
	Do $$$AssertStatusOK(sc, "the table without the DEFAULTGLOBAL is created")
	Set sc = ##class(OcuTalon.Install.Step.PrivateData).Run()
	Do $$$AssertStatusNotOK(sc, "the check fails for a knowledge-base table whose globals are not private")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue(text [ bad, "the error names the class")
	Do ##class(OcuTalon.Install.Step.PrivateData).StorageGlobals(.storage)
	Set global = ""
	Set named = 0
	For {
		Set global = $Order(storage(global))
		Quit:global=""
		If (storage(global) = bad) && (text [ ("^"_global)) Set named = 1
	}
	Do $$$AssertTrue(named, "the error names a global of the table")
	Do ..DropKnowledgeBaseTables()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).Run(), "the check passes again once the tables are dropped")
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
	Set sc = $ClassMethod(probe, "CheckIn", "%SYS")
	Do $$$AssertStatusNotOK(sc, "a namespace without the private mappings fails")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "not to OCUTALON_PRIVATE", "the error names the private database")
	Do $SYSTEM.OBJ.Delete(probe, "-d")
}

/// Given OCUTALON, a storage global that resolves outside OCUTALON_PRIVATE fails the check from Run(), which
/// names it. The global comes from a subclass whose StorageGlobals() lists a global of the data database.
Method TestStorageGlobalMismatchFails()
{
	Set probe = "OcuTalon.Test.Install.ZzStorageProbe"
	Do $SYSTEM.OBJ.Delete(probe, "-d")
	Set text = "Class "_probe_" Extends OcuTalon.Install.Step.PrivateData"_$Char(10)_"{"_$Char(10)_"ClassMethod StorageGlobals(Output storage) As %Status"_$Char(10)_"{"_$Char(10)_$Char(9)_"Kill storage"_$Char(10)_$Char(9)_"Set storage(""OcuTalonZzNotPrivate"") = """_probe_""""_$Char(10)_$Char(9)_"Quit $SYSTEM.Status.OK()"_$Char(10)_"}"_$Char(10)_"}"
	Do $$$AssertStatusOK(..Compile(probe, text), "the storage probe compiles")
	Set sc = $ClassMethod(probe, "Run")
	Do $$$AssertStatusNotOK(sc, "a storage global outside OCUTALON_PRIVATE fails the check")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "^OcuTalonZzNotPrivate", "the error names the storage global")
	Do $SYSTEM.OBJ.Delete(probe, "-d")
}

/// Creates a knowledge-base table by DDL, with the given trailing clause (the private DEFAULTGLOBAL or nothing).
ClassMethod CreateTable(table As %String, clause As %String) As %Status [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "CREATE TABLE "_table_" (id VARCHAR(64) NOT NULL, text VARCHAR(1000), PRIMARY KEY (id)) "_clause)
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "Creating "_table_" failed: "_result.%Message)
	Quit $SYSTEM.Status.OK()
}

/// Drops both knowledge-base tables if they exist; dropping a table removes its globals.
ClassMethod DropKnowledgeBaseTables() [ Private ]
{
	Set tables = $ListFromString(..#KBTABLES)
	Set position = 0
	While $ListNext(tables, position, table) {
		Do ##class(%SQL.Statement).%ExecDirect(, "DROP TABLE IF EXISTS "_table)
		Do $SYSTEM.OBJ.Delete(table, "-d")
	}
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
