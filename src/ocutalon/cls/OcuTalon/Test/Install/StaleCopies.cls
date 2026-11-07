/// Tests of OcuTalon.Install.Ipm:RemoveStaleCopies, the early Reload step that removes the stale copies of the Python distributions that
/// requirements.txt pins, so that IPM's pip step (--target keeps every top-level item that exists) installs the pinned ones (Story 19.8, DW-829;
/// AD-23). Each test builds its own folder zz-stale-<n> under the temporary directory, with a root that holds requirements.txt and a target
/// that holds the distributions, calls the step on them and removes the folder, so no other state is touched. The root pins requests 2.34.2,
/// typing_extensions 4.16.0, charset-normalizer 3.5.2 and protobuf 7.36.2.
///   - TestStaleFolderPackage, TestPinnedAlready, TestBothVersions, TestSingleFileModule, TestTopLevelNativeFile: what goes for a stale
///     distribution (its folder or file items, its dist-info, and for a module file its __pycache__ files) and what stays;
///   - TestSharedFolder, TestNotPinned, TestBinAndOutside, TestNoRecord: the guards (a folder another distribution lists, a name that is no pin, bin/
///     and a path out of the target, a dist-info without RECORD);
///   - TestNoRequirements, TestBypass, TestBadInput: the cases that remove nothing and never throw;
///   - TestPinsAreRead, TestVersionSpelling, TestQuotedRecordField: the pins come from the file, 2025.01.31 and 2025.1.31 are one version, and a quoted
///     CSV field is read;
///   - TestStepLines, TestIdempotent: one STEP line for each replaced distribution, and a second call removes and writes nothing;
///   - TestSymlinkOutside: a link out of the target is not followed, and a copy that could not be removed is retried by the next call.
Class OcuTalon.Test.Install.StaleCopies Extends %UnitTest.TestCase
{

/// The folder of the running test: root/ holds requirements.txt, mgr/python/ is the target.
Property Base As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Base = ##class(%File).NormalizeDirectory(##class(%SYS.System).TempDirectory() _ "/zz-stale-" _ $Job _ "-" _ $Increment(^||OcuTalonStale))
	Do ##class(%File).RemoveDirectoryTree(..Base)
	Do ##class(%File).CreateDirectoryChain(..Base _ "root")
	Do ##class(%File).CreateDirectoryChain(..Target())
	Do ..Put(..Base _ "root/requirements.txt", "# pins" _ $Char(10) _ $Char(10) _ "requests==2.34.2" _ $Char(10) _ "typing_extensions==4.16.0" _ $Char(10) _ "charset-normalizer==3.5.2" _ $Char(10) _ "protobuf==7.36.2" _ $Char(10))
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Base '= "" Do ##class(%File).RemoveDirectoryTree(..Base)
	Quit $$$OK
}

/// The target folder: <mgr>/python/ of the fixture.
Method Target() As %String
{
	Quit ..Base _ "mgr/python/"
}

/// Writes text to the file path, with its folders.
Method Put(path As %String, text As %String = "x")
{
	Do ##class(%File).CreateDirectoryChain(##class(%File).GetDirectory(path))
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(path)
	Do stream.Write(text)
	Do stream.%Save()
}

/// Makes the distribution name-version in the target: the files of paths (a list of RECORD paths; a path that starts with ../ or / is only written
/// to RECORD), and its dist-info folder with METADATA and, unless record is 0, RECORD. A path may be given as a quoted CSV field already (a
/// leading double quote).
Method Dist(name As %String, version As %String, paths As %List = "", record As %Boolean = 1)
{
	Set info = name _ "-" _ version _ ".dist-info"
	Do ..Put(..Target() _ info _ "/METADATA", "Name: " _ name)
	Set lines = "", pointer = 0
	While $ListNext(paths, pointer, path) {
		Set file = $Select($Extract(path) = """": $Replace($Extract(path, 2, $Length(path) - 1), """""", """"), 1: path)
		If $Extract(file, 1, 3) '= "../", $Extract(file) '= "/" Do ..Put(..Target() _ file)
		Set lines = lines _ path _ ",sha256=x,1" _ $Char(10)
	}
	If record Do ..Put(..Target() _ info _ "/RECORD", lines _ info _ "/RECORD,," _ $Char(10))
}

/// 1 when the item (a file or a folder) exists in the target.
Method Has(item As %String) As %Boolean
{
	Quit ##class(%File).Exists(..Target() _ item) || ##class(%File).DirectoryExists(..Target() _ item)
}

/// Runs RemoveStaleCopies on the fixture and returns what it wrote, without the line breaks at its ends; sc is its status.
Method Run(bypass As %String = 0, ByRef sc As %Status, root As %String, target As %String) As %String
{
	If '$Data(root) Set root = ..Base _ "root"
	If '$Data(target) Set target = ..Target()
	Set io = $IO
	Set file = ..Base _ "out.txt"
	Open file:"NWS":5
	Use file
	Set sc = ##class(OcuTalon.Install.Ipm).RemoveStaleCopies(root, bypass, target)
	Use io
	Close file
	Set stream = ##class(%Stream.FileCharacter).%New()
	Do stream.LinkToFile(file)
	Set text = ""
	While 'stream.AtEnd {
		Set line = $ZStrip(stream.ReadLine(), "<>W")
		If line '= "" Set text = text _ $Select(text = "": "", 1: $Char(10)) _ line
	}
	Quit text
}

/// An older requests beside the folder it installed, with an unrecorded file inside: the folder and the dist-info go.
Method TestStaleFolderPackage()
{
	Do ..Dist("requests", "2.31.0", $ListBuild("requests/__init__.py", "requests/api.py"))
	Do ..Put(..Target() _ "requests/__pycache__/x.pyc")
	Set out = ..Run(, .sc)
	Do $$$AssertStatusOK(sc, "returns OK")
	Do $$$AssertEquals(..Has("requests"), 0, "the stale folder, with its unrecorded __pycache__ file, is gone")
	Do $$$AssertEquals(..Has("requests-2.31.0.dist-info"), 0, "the stale dist-info is gone")
	Do $$$AssertEquals(out, "STEP Python replaced requests 2.31.0 with 2.34.2", "it writes one STEP line")
}

/// The pinned version is left as it is, and nothing is written.
Method TestPinnedAlready()
{
	Do ..Dist("requests", "2.34.2", $ListBuild("requests/__init__.py"))
	Set out = ..Run(, .sc)
	Do $$$AssertEquals(..Has("requests/__init__.py"), 1, "the pinned folder stays")
	Do $$$AssertEquals(..Has("requests-2.34.2.dist-info"), 1, "the pinned dist-info stays")
	Do $$$AssertEquals(out, "", "nothing is written")
}

/// The stale and the pinned dist-info of one name beside one folder (IPM's copy and pip's dist-info): the stale dist-info and the folder go,
/// the pinned dist-info stays.
Method TestBothVersions()
{
	Do ..Dist("requests", "2.31.0", $ListBuild("requests/__init__.py"))
	Do ..Dist("requests", "2.34.2", $ListBuild("requests/__init__.py"))
	Do ..Run(, .sc)
	Do $$$AssertEquals(..Has("requests"), 0, "the folder of the old copy is gone")
	Do $$$AssertEquals(..Has("requests-2.31.0.dist-info"), 0, "the stale dist-info is gone")
	Do $$$AssertEquals(..Has("requests-2.34.2.dist-info"), 1, "the pinned dist-info stays")
}

/// A single-file module goes with its own __pycache__ files and not with another module's.
Method TestSingleFileModule()
{
	Do ..Dist("typing_extensions", "4.12.2", $ListBuild("typing_extensions.py", "__pycache__/typing_extensions.cpython-312.pyc"))
	Do ..Put(..Target() _ "__pycache__/other.cpython-312.pyc")
	Do ..Run(, .sc)
	Do $$$AssertEquals(..Has("typing_extensions.py"), 0, "the module file is gone")
	Do $$$AssertEquals(..Has("__pycache__/typing_extensions.cpython-312.pyc"), 0, "its compiled file is gone")
	Do $$$AssertEquals(..Has("typing_extensions-4.12.2.dist-info"), 0, "the stale dist-info is gone")
	Do $$$AssertEquals(..Has("__pycache__/other.cpython-312.pyc"), 1, "another module's compiled file stays")
	Do $$$AssertEquals(..Has("__pycache__"), 1, "and so does __pycache__")
}

/// A top-level native file that RECORD names goes with the folder.
Method TestTopLevelNativeFile()
{
	Set native = "81d243bd2c585b0f4821__mypyc.cpython-312-x86_64-linux-gnu.so"
	Do ..Dist("charset_normalizer", "2.1.1", $ListBuild("charset_normalizer/__init__.py", native))
	Do ..Run(, .sc)
	Do $$$AssertEquals(..Has("charset_normalizer"), 0, "the folder is gone")
	Do $$$AssertEquals(..Has(native), 0, "the top-level native file is gone")
	Do $$$AssertEquals(..Has("charset_normalizer-2.1.1.dist-info"), 0, "the stale dist-info is gone")
}

/// A folder that another distribution lists too (a namespace folder) stays, and the stale dist-info goes.
Method TestSharedFolder()
{
	Do ..Dist("protobuf", "5.0.0", $ListBuild("google/protobuf/message.py"))
	Do ..Dist("googleapis_common_protos", "1.0", $ListBuild("google/api/annotations.py"))
	Do ..Run(, .sc)
	Do $$$AssertEquals(..Has("google/api/annotations.py"), 1, "the shared folder google/ stays with the other distribution's file")
	Do $$$AssertEquals(..Has("google/protobuf/message.py"), 1, "and so does the stale distribution's file in it")
	Do $$$AssertEquals(..Has("protobuf-5.0.0.dist-info"), 0, "the stale dist-info is gone")
	Do $$$AssertEquals(..Has("googleapis_common_protos-1.0.dist-info"), 1, "the other distribution's dist-info stays")
}

/// A name that is no pin is untouched, at any version.
Method TestNotPinned()
{
	Do ..Dist("oras", "0.2.25", $ListBuild("oras/provider.py"))
	Do ..Dist("jsonschema", "4.0", $ListBuild("jsonschema/__init__.py"))
	Set out = ..Run(, .sc)
	Do $$$AssertEquals(..Has("oras/provider.py") && ..Has("oras-0.2.25.dist-info"), 1, "oras stays")
	Do $$$AssertEquals(..Has("jsonschema/__init__.py") && ..Has("jsonschema-4.0.dist-info"), 1, "jsonschema stays")
	Do $$$AssertEquals(out, "", "nothing is written")
}

/// bin/ stays, and a RECORD path out of the target is never followed.
Method TestBinAndOutside()
{
	Do ..Put(..Base _ "x", "outside")
	Do ..Dist("charset_normalizer", "2.1.1", $ListBuild("charset_normalizer/__init__.py", "bin/normalizer", "../../x", "/etc/zz-stale-absolute"))
	Do ..Run(, .sc)
	Do $$$AssertEquals(..Has("charset_normalizer"), 0, "the stale folder is gone")
	Do $$$AssertEquals(..Has("bin/normalizer"), 1, "bin/normalizer stays")
	Do $$$AssertEquals(##class(%File).DirectoryExists(..Target()), 1, "the target folder stays (the ../ path is not followed)")
	Do $$$AssertEquals(##class(%File).Exists(..Base _ "x"), 1, "the file that the ../ path names, outside the target, stays")
}

/// A stale dist-info without a RECORD is left whole: nothing says which files are its.
Method TestNoRecord()
{
	Do ..Dist("requests", "2.31.0", $ListBuild("requests/__init__.py"), 0)
	Do ..Run(, .sc)
	Do $$$AssertEquals(..Has("requests/__init__.py"), 1, "the folder stays")
	Do $$$AssertEquals(..Has("requests-2.31.0.dist-info"), 1, "the dist-info stays")
}

/// A root without requirements.txt removes nothing (the image path).
Method TestNoRequirements()
{
	Do ##class(%File).Delete(..Base _ "root/requirements.txt")
	Do ..Dist("requests", "2.31.0", $ListBuild("requests/__init__.py"))
	Set out = ..Run(, .sc)
	Do $$$AssertStatusOK(sc, "returns OK")
	Do $$$AssertEquals(..Has("requests/__init__.py") && ..Has("requests-2.31.0.dist-info"), 1, "nothing is removed")
	Do $$$AssertEquals(out, "", "nothing is written")
}

/// IPM's -bypass-py-deps flag (1) removes nothing; 0 is the default and removes.
Method TestBypass()
{
	Do ..Dist("requests", "2.31.0", $ListBuild("requests/__init__.py"))
	Do ..Run(1, .sc)
	Do $$$AssertEquals(..Has("requests/__init__.py") && ..Has("requests-2.31.0.dist-info"), 1, "with the flag 1 nothing is removed")
	Do ..Run("0", .sc)
	Do $$$AssertEquals(..Has("requests"), 0, "with the flag 0 the stale copy is removed")
}

/// A missing target, an empty root and a root that does not exist return OK and remove nothing.
Method TestBadInput()
{
	Do ..Dist("requests", "2.31.0", $ListBuild("requests/__init__.py"))
	Do ..Run(, .sc, , ..Base _ "no-such-folder/")
	Do $$$AssertStatusOK(sc, "a missing target returns OK")
	Do ..Run(, .sc, "")
	Do $$$AssertStatusOK(sc, "an empty root returns OK")
	Do ..Run(, .sc, ..Base _ "no-such-root")
	Do $$$AssertStatusOK(sc, "a missing root returns OK")
	Do $$$AssertEquals(..Has("requests/__init__.py") && ..Has("requests-2.31.0.dist-info"), 1, "nothing is removed")
	Set sc = ##class(OcuTalon.Install.Ipm).RemoveStaleCopies()
	Do $$$AssertStatusOK(sc, "called with no arguments it returns OK")
}

/// The pins come from the file: a name that no code lists is replaced when the file pins it.
Method TestPinsAreRead()
{
	Do ..Put(..Base _ "root/requirements.txt", "zz-widget==2.0  # comment" _ $Char(13, 10) _ "other[extra]==1.0 ; python_version < '4'" _ $Char(10) _ "-r more.txt" _ $Char(10))
	Do ..Dist("zz_widget", "1.0", $ListBuild("zz_widget/__init__.py"))
	Do ..Dist("other", "0.5", $ListBuild("other.py"))
	Do ..Dist("requests", "2.31.0", $ListBuild("requests/__init__.py"))
	Set out = ..Run(, .sc)
	Do $$$AssertEquals(..Has("zz_widget"), 0, "a name that only the file pins is replaced")
	Do $$$AssertEquals(..Has("other.py"), 0, "a pin with an extra and a marker is read")
	Do $$$AssertEquals(..Has("requests/__init__.py"), 1, "requests is no pin of this file, so it stays")
	Do $$$AssertEquals(out, "STEP Python replaced other 0.5 with 1.0" _ $Char(10) _ "STEP Python replaced zz_widget 1.0 with 2.0", "each replaced distribution has its STEP line")
}

/// 2025.01.31 and 2025.1.31 are one version: a pinned copy is not replaced because of the spelling of its version.
Method TestVersionSpelling()
{
	Do ..Put(..Base _ "root/requirements.txt", "certifi==2025.01.31" _ $Char(10))
	Do ..Dist("certifi", "2025.1.31", $ListBuild("certifi/__init__.py"))
	Set out = ..Run(, .sc)
	Do $$$AssertEquals(..Has("certifi/__init__.py") && ..Has("certifi-2025.1.31.dist-info"), 1, "the copy stays")
	Do $$$AssertEquals(out, "", "nothing is written")
}

/// A RECORD path in double quotes (it holds a comma) is read as one field.
Method TestQuotedRecordField()
{
	Do ..Dist("requests", "2.31.0", $ListBuild("requests/__init__.py", """odd,name.py"""))
	Do ..Run(, .sc)
	Do $$$AssertEquals(..Has("odd,name.py"), 0, "the file with a comma in its name is gone")
	Do $$$AssertEquals(..Has("requests"), 0, "and so is the folder")
}

/// Two stale distributions give two STEP lines, each with its versions, and the line follows the removal.
Method TestStepLines()
{
	Do ..Dist("requests", "2.31.0", $ListBuild("requests/__init__.py"))
	Do ..Dist("typing_extensions", "4.12.2", $ListBuild("typing_extensions.py"))
	Set out = ..Run(, .sc)
	Do $$$AssertEquals(out, "STEP Python replaced requests 2.31.0 with 2.34.2" _ $Char(10) _ "STEP Python replaced typing_extensions 4.12.2 with 4.16.0", "one STEP line for each replaced distribution")
}

/// A top-level item that is a symbolic link to a folder outside the target is never followed: the folder stays, and so does the stale
/// dist-info with no STEP line, so that a later call retries; once the link is gone, the next call replaces the copy.
Method TestSymlinkOutside()
{
	Do ..Dist("requests", "2.31.0", $ListBuild("requests/__init__.py"))
	Do ##class(%File).RemoveDirectoryTree(..Target() _ "requests")
	Do ..Put(..Base _ "outside/keep.py")
	Do $$$AssertEquals($ZF(-100, "/SHELL", "ln", "-s", ..Base _ "outside", ..Target() _ "requests"), 0, "a link named requests points out of the target")
	Set out = ..Run(, .sc)
	Do $$$AssertEquals(##class(%File).Exists(..Base _ "outside/keep.py"), 1, "the folder outside the target stays")
	Do $$$AssertEquals(..Has("requests-2.31.0.dist-info"), 1, "the stale dist-info stays, so the next call retries")
	Do $$$AssertEquals(out, "", "no STEP line is written for a copy that was not replaced")
	Do $$$AssertEquals($ZF(-100, "/SHELL", "rm", "-f", ..Target() _ "requests"), 0, "the link is removed")
	Set out = ..Run(, .sc)
	Do $$$AssertEquals(..Has("requests-2.31.0.dist-info"), 0, "the next call removes the stale dist-info")
	Do $$$AssertEquals(out, "STEP Python replaced requests 2.31.0 with 2.34.2", "and writes its STEP line")
}

/// A second call finds nothing stale: it writes nothing and changes nothing.
Method TestIdempotent()
{
	Do ..Dist("requests", "2.31.0", $ListBuild("requests/__init__.py"))
	Do ..Dist("charset_normalizer", "3.5.2", $ListBuild("charset_normalizer/__init__.py"))
	Set first = ..Run(, .sc)
	Do $$$AssertEquals(first, "STEP Python replaced requests 2.31.0 with 2.34.2", "the first call replaces the stale copy")
	Do $$$AssertEquals(..Has("requests-2.31.0.dist-info"), 0, "and removes its dist-info")
	Do ..Put(..Target() _ "requests/__init__.py", "the pinned copy that pip puts in its place")
	Set out = ..Run(, .sc)
	Do $$$AssertEquals(out, "", "the second call writes nothing")
	Do $$$AssertEquals(..Has("requests/__init__.py"), 1, "and removes nothing")
	Do $$$AssertEquals(..Has("charset_normalizer/__init__.py") && ..Has("charset_normalizer-3.5.2.dist-info"), 1, "a distribution at its pin stays")
}

}
