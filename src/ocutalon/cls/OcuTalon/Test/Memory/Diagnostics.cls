/// The operator diagnostics of the embedder print no secret (Story 19.3, QA; DW-793, approved on the condition that none prints a key, a token or the value of an
/// environment variable; a folder path is fine). Test.Memory.Install:TestDiagnosticsHoldNoSecret scans the install step's warning for a folder that cannot be
/// made and the embedder's error for a folder with no model. This class scans the other messages that a caller of OcuTalon.Memory.Embedder.Submit can read, with
/// the scanner of that test (its Leaks, shown there to flag planted secrets of each kind, and its Secrets, the environment of the process):
///   - TestSubmitTimeout: the status of a work item that does not finish in time ("did not finish within N seconds");
///   - TestUnknownWorkItem: the status of a work item that the class does not have;
///   - TestModelThatCannotLoad: the status of a worker whose model folder holds the files of a model that cannot be loaded, so that the message is the one of the
///     Python layer and not one of OcuTalon's own words.
/// Each message must be an error status that says something, and hold no name of a secret from Leaks. THEY NEED OcuTalon's Docker image (the work category and the Python package are on the image only) and record
/// a named skip elsewhere. They make no network call and leave no state: the temporary folder of the third is removed.
Class OcuTalon.Test.Memory.Diagnostics Extends %UnitTest.TestCase
{

Parameter INSTALL = "OcuTalon.Test.Memory.Install";

/// 1 on the image; otherwise records the skip.
Method OnImage() As %Boolean [ Private ]
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit 1
	Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
	Quit 0
}

/// Asserts that the status is an error with a text, and that the text holds no secret. what names the case.
Method AssertQuiet(sc As %Status, what As %String) [ Private ]
{
	Do ..Secrets(.secrets)
	Do $$$AssertTrue($Data(secrets) > 0, "the environment of the process is read (" _ what _ ")")
	Do $$$AssertTrue($SYSTEM.Status.IsError(sc), what _ " is an error status")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertTrue(text '= "", what _ " has a text: " _ $Extract(text, 1, 160))
	Do $$$AssertEquals($ClassMethod(..#INSTALL, "Leaks", text, .secrets), "", what _ " prints no key, token or variable value")
}

/// The environment of the process, as secrets(name) = value (see Test.Memory.Install).
Method Secrets(Output secrets) [ Private ]
{
	Do $ClassMethod(..#INSTALL, "Secrets", .secrets)
}

Method TestSubmitTimeout()
{
	If '..OnImage() Quit
	Set sc = ##class(OcuTalon.Memory.Embedder).Submit("##class(OcuTalon.Test.Memory.Fixture).Slow", 1, .result, 3)
	Do ..AssertQuiet(sc, "the status of a work item that is too slow")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "did not finish within 1 seconds", "which says that it did not finish in time: " _ $SYSTEM.Status.GetErrorText(sc))
}

Method TestUnknownWorkItem()
{
	If '..OnImage() Quit
	Set sc = ##class(OcuTalon.Memory.Embedder).Submit("NoSuchWorkItem", ##class(OcuTalon.Memory.Embedder).#TIMEOUT, .result)
	Do ..AssertQuiet(sc, "the status of a work item that does not exist")
}

Method TestModelThatCannotLoad()
{
	If '..OnImage() Quit
	Set folder = $ClassMethod(..#INSTALL, "FolderWithModel")
	Do $$$AssertTrue(##class(OcuTalon.Memory.Embedder).HasModel(folder), "a folder that holds the files of a model is made")
	Set sc = ##class(OcuTalon.Memory.Embedder).Submit("Embed", ##class(OcuTalon.Memory.Embedder).#TIMEOUT, .result, "a text", folder)
	Do $ClassMethod(..#INSTALL, "RemoveFolder", folder)
	Do ..AssertQuiet(sc, "the status of a worker whose model cannot be loaded")
	Do $$$AssertTrue('##class(%File).DirectoryExists(folder), "and the temporary folder is removed")
	Set sc = ##class(OcuTalon.Memory.Embedding).Embed("the worker still embeds afterwards", .vector)
	Do $$$AssertStatusOK(sc, "a worker embeds with the model of the image afterwards")
}

}
