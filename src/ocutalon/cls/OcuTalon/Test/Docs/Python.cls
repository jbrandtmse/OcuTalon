/// Tests of where Python may appear in OcuTalon (Story 19.6; AD-6, AD-21, Conventions "Python"; DW-792). They read class sources the way Test.Bridge.CodeRules
/// does (Test.Bridge.Source: comment lines are not code):
///   - TestPythonOnlyInTheWorkers: no class outside the tests holds a reference to Python in a code line (a Language = python method, %SYS.Python or $SYSTEM.Python)
///     except OcuTalon.Memory.Embedder and OcuTalon.Docs.Extractor, the two worker classes;
///   - TestNoEvalOrExec: neither worker class builds or runs Python source: no eval and no exec in a code line;
///   - TestResources: every file below src/ocutalon/python that the image holds is ASCII and builds or runs no Python source (no eval( and no exec( ), and the
///     two resources are there. Off the image the class records one named skip for this test.
Class OcuTalon.Test.Docs.Python Extends %UnitTest.TestCase
{

/// The two classes that may reference Python.
Parameter WORKERS = "OcuTalon.Memory.Embedder,OcuTalon.Docs.Extractor";

/// The folder of the resources in the image, and the two resources.
Parameter RESOURCEFOLDER = "/opt/ocutalon/src/ocutalon/python/";

Parameter RESOURCES = "ocutalon_extract.py,ocutalon_memory.py";

/// A call of Python's eval or exec: the word, then an opening parenthesis or a quote (builtins.eval("..."), "eval").
Parameter EVALEXEC = "(?<![A-Za-z0-9_$])(eval|exec)(?![A-Za-z0-9_])";

/// The compiled classes of OcuTalon outside the tests, as a list.
ClassMethod ProductClasses() As %List
{
	Set list = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name LIKE 'OcuTalon.%' AND Name NOT LIKE 'OcuTalon.Test.%' ORDER BY Name")
	While result.%Next() {
		Set list = list _ $ListBuild(result.%GetData(1))
	}
	Quit list
}

Method TestPythonOnlyInTheWorkers()
{
	Set classes = ..ProductClasses()
	Do $$$AssertTrue($ListLength(classes) > 100, "the product classes are listed (" _ $ListLength(classes) _ ")")
	Set pattern = ##class(OcuTalon.Test.Bridge.CodeRules).#PYTHON
	Set found = ""
	Set position = 0
	While $ListNext(classes, position, class) {
		If $SYSTEM.Status.IsError(##class(OcuTalon.Test.Bridge.Source).Text(class, .text)) Continue
		If ##class(OcuTalon.Test.Bridge.Source).Matches(text, pattern) Set found = found _ $ListBuild(class)
	}
	Set expected = $ListFromString(..#WORKERS, ",")
	Set position = 0
	While $ListNext(expected, position, class) {
		Do $$$AssertTrue($ListFind(found, class) > 0, class _ " is a worker class and references Python")
	}
	Set position = 0
	While $ListNext(found, position, class) {
		Do $$$AssertTrue($ListFind(expected, class) > 0, class _ " references Python and is one of the two worker classes")
	}
}

Method TestNoEvalOrExec()
{
	Set workers = $ListFromString(..#WORKERS, ",")
	Set position = 0
	While $ListNext(workers, position, class) {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Source).Text(class, .text), class _ " has source")
		Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.Source).Matches(text, ..#EVALEXEC), 0, class _ " calls neither eval nor exec")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.Source).Matches("	Set x = builtins.eval(""1"")", ..#EVALEXEC), 1, "control: a builtins.eval call is flagged")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.Source).Matches("	// builtins.eval is not used", ..#EVALEXEC), 0, "and a comment is not")
}

Method TestResources()
{
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
		Quit
	}
	Set resources = $ListFromString(..#RESOURCES, ",")
	Set position = 0
	While $ListNext(resources, position, name) {
		Do $$$AssertTrue(##class(%File).Exists(..#RESOURCEFOLDER _ name), name _ " is in the image")
	}
	Set found = 0
	Set file = $ZSearch(..#RESOURCEFOLDER _ "*.py")
	While file '= "" {
		Set found = found + 1
		Set stream = ##class(%Stream.FileBinary).%New()
		Do stream.LinkToFile(file)
		Set data = stream.Read(stream.Size)
		Set ascii = 1
		For i = 1:1:$Length(data) {
			If $Ascii(data, i) > 127 Set ascii = 0 Quit
		}
		Do $$$AssertTrue(ascii, file _ " is ASCII")
		Do $$$AssertEquals($Locate(data, "(?<![A-Za-z0-9_])(eval|exec)\("), 0, file _ " builds and runs no Python source")
		Set file = $ZSearch("")
	}
	Do $$$AssertEquals(found, $ListLength(resources), "the folder holds exactly the resources")
}

}
