/// Tests of the Memory area's install step (Story 19.2; AD-21, AD-23). They need neither the Python package nor the image: the folders are temporary,
/// and the step is run against them. A test restores the category and the configuration row to what the instance had before it ran.
///   - TestRun: Run() creates the category OcuTalon.Memory.Embedder (2 active workers, 1 default) and the row OcuTalonMemory (class, 384), and a second Run()
///     changes nothing and leaves one row; a changed category and a changed row are put back to the declared values;
///   - TestModelFolderRule: ModelFolder() is the named variable's value when it is set and not empty, otherwise the manager directory's fastembed/;
///   - TestPresentFolder: a folder that holds the model is left alone: no download is attempted, no warning, no new file, on a first run and on a second;
///   - TestHasModel: a snapshot needs the model file, the tokenizer and the three configuration files;
///   - TestDownloadImpossible: a folder that cannot be made gives one warning with the underlying error's text, the step is OK, and nothing is made.
Class OcuTalon.Test.Memory.Install Extends %UnitTest.TestCase
{

Parameter CATEGORY = "OcuTalon.Memory.Embedder";

Parameter CONFIG = "OcuTalonMemory";

Method OnBeforeAllTests() As %Status
{
	Kill ^||OcuTalonTestMemoryInstall
	Set ^||OcuTalonTestMemoryInstall("category") = ##class(OcuTalon.Test.Memory.Fixture).CategoryExists(..#CATEGORY)
	If ^||OcuTalonTestMemoryInstall("category") {
		Do ##class(OcuTalon.Test.Memory.Fixture).CategoryProperties(..#CATEGORY, .properties)
		Set ^||OcuTalonTestMemoryInstall("category", "MaxActiveWorkers") = properties("MaxActiveWorkers")
		Set ^||OcuTalonTestMemoryInstall("category", "DefaultWorkers") = properties("DefaultWorkers")
	}
	Set ^||OcuTalonTestMemoryInstall("config") = ##class(%Embedding.Config).%ExistsId(..#CONFIG)
	If ^||OcuTalonTestMemoryInstall("config") {
		Set row = ##class(%Embedding.Config).%OpenId(..#CONFIG)
		Set ^||OcuTalonTestMemoryInstall("config", "Configuration") = row.Configuration
		Set ^||OcuTalonTestMemoryInstall("config", "EmbeddingClass") = row.EmbeddingClass
		Set ^||OcuTalonTestMemoryInstall("config", "VectorLength") = row.VectorLength
		Set ^||OcuTalonTestMemoryInstall("config", "Description") = row.Description
	}
	Quit $$$OK
}

/// Puts the category and the row back as they were: removed when the instance had none, otherwise set to its values.
Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	If ^||OcuTalonTestMemoryInstall("category") {
		Do ##class(OcuTalon.Install.Step.Memory).EnsureCategory(..#CATEGORY, ^||OcuTalonTestMemoryInstall("category", "MaxActiveWorkers"), ^||OcuTalonTestMemoryInstall("category", "DefaultWorkers"))
	} Else {
		Set state("category") = 1
	}
	If '^||OcuTalonTestMemoryInstall("config") {
		Set state("config") = 1
	} Else {
		Set statement = ##class(%SQL.Statement).%New()
		Do statement.%Prepare("UPDATE %Embedding.Config SET Configuration = ?, EmbeddingClass = ?, VectorLength = ?, Description = ? WHERE Name = ?", 1)
		Do statement.%Execute(^||OcuTalonTestMemoryInstall("config", "Configuration"), ^||OcuTalonTestMemoryInstall("config", "EmbeddingClass"), ^||OcuTalonTestMemoryInstall("config", "VectorLength"), ^||OcuTalonTestMemoryInstall("config", "Description"), ..#CONFIG)
	}
	Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
	Kill ^||OcuTalonTestMemoryInstall
	Quit $$$OK
}

Method TestRun()
{
	Set folder = ..FolderWithModel()
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Memory).Run(folder), "Run() succeeds")
	Do $$$AssertEquals($ListLength(##class(OcuTalon.Install.Step).TakeWarnings()), 0, "with no warning")
	Do ..AssertDeclared("after the first run")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Memory).Run(folder), "a second Run() succeeds")
	Do ..AssertDeclared("after the second run")

	Do ##class(OcuTalon.Install.Step.Memory).EnsureCategory(..#CATEGORY, 5, 3)
	Set statement = ##class(%SQL.Statement).%New()
	Do statement.%Prepare("UPDATE %Embedding.Config SET Description = ? WHERE Name = ?", 1)
	Do statement.%Execute("changed", ..#CONFIG)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Memory).Run(folder), "Run() after a change succeeds")
	Do ..AssertDeclared("and puts the declared values back")
	Do ..RemoveFolder(folder)
}

Method TestModelFolderRule()
{
	Set variable = ##class(OcuTalon.Memory.Embedder).#FOLDERVARIABLE
	Do $$$AssertEquals(##class(OcuTalon.Memory.Embedder).ModelFolder(), $Select($SYSTEM.Util.GetEnviron(variable) '= "": $SYSTEM.Util.GetEnviron(variable), 1: $SYSTEM.Util.ManagerDirectory() _ "fastembed/"), "the rule's own variable is used when it is set, else the manager directory's fastembed/")
	Do $$$AssertEquals(##class(OcuTalon.Memory.Embedder).ModelFolder("OCUTALON_ZZ_UNSET_VARIABLE"), $SYSTEM.Util.ManagerDirectory() _ "fastembed/", "a variable that is not set gives the manager directory's fastembed/")
	Do $$$AssertEquals(##class(OcuTalon.Memory.Embedder).ModelFolder("PATH"), $SYSTEM.Util.GetEnviron("PATH"), "a variable that is set and not empty gives its value")
	Do $$$AssertTrue($Extract(##class(OcuTalon.Memory.Embedder).ModelFolder("OCUTALON_ZZ_UNSET_VARIABLE"), *) = "/", "and the manager directory's folder ends with a slash")
}

Method TestPresentFolder()
{
	Set folder = ..FolderWithModel()
	Set before = ..Listing(folder)
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertTrue(##class(OcuTalon.Memory.Embedder).HasModel(folder), "the folder holds the model")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Memory).EnsureModel(folder), 0, "no download is attempted for it")
	For run = 1, 2 {
		Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Memory).Run(folder), "Run " _ run _ " succeeds")
		Do $$$AssertEquals($ListLength(##class(OcuTalon.Install.Step).TakeWarnings()), 0, "with no warning")
		Do $$$AssertEquals(..Listing(folder), before, "and no file added to the folder")
	}
	Do ..RemoveFolder(folder)
}

Method TestHasModel()
{
	Set folder = ..FolderWithModel()
	Set snapshots = folder _ ##class(OcuTalon.Memory.Embedder).#MODELDIR _ "/snapshots/zz1/"
	Do $$$AssertTrue(##class(OcuTalon.Memory.Embedder).HasModel(folder), "a snapshot with every file of the model is a model")
	Do ##class(%File).Delete(snapshots _ "config.json")
	Do $$$AssertTrue('##class(OcuTalon.Memory.Embedder).HasModel(folder), "a snapshot without a configuration file is not")
	Do ..RemoveFolder(folder)
	Set folder = ..FolderWithModel()
	Set snapshots = folder _ ##class(OcuTalon.Memory.Embedder).#MODELDIR _ "/snapshots/zz1/"
	Do ##class(%File).Delete(snapshots _ "tokenizer.json")
	Do $$$AssertTrue('##class(OcuTalon.Memory.Embedder).HasModel(folder), "a snapshot without the tokenizer is not")
	Do ..RemoveFolder(folder)
	Do $$$AssertTrue('##class(OcuTalon.Memory.Embedder).HasModel(folder), "a folder that does not exist holds none")
	Do $$$AssertTrue('##class(OcuTalon.Memory.Embedder).HasModel(""), "and neither does an empty name")
}

Method TestDownloadImpossible()
{
	Set folder = "/dev/null/zz-memory-model/"
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Memory).Run(folder), "a folder that cannot be made is not a failure of the step")
	Set warnings = ##class(OcuTalon.Install.Step).TakeWarnings()
	Do $$$AssertEquals($ListLength(warnings), 1, "it is one warning")
	Do $$$AssertTrue($ListGet(warnings, 1) '= "", "which carries the underlying error's text: " _ $ListGet(warnings, 1))
	Do $$$AssertTrue('##class(%File).DirectoryExists(folder), "and nothing is made")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Memory).EnsureModel(folder), 1, "a download was attempted for a folder that holds no model")
	Do ##class(OcuTalon.Install.Step).TakeWarnings()
}

/// Asserts the category and the row have the declared values.
Method AssertDeclared(when As %String) [ Private ]
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).CategoryProperties(..#CATEGORY, .properties), "the category exists " _ when)
	Do $$$AssertEquals($Get(properties("MaxActiveWorkers")), 2, "with 2 active workers " _ when)
	Do $$$AssertEquals($Get(properties("DefaultWorkers")), 1, "and 1 default worker " _ when)
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM %Embedding.Config WHERE Name = '" _ ..#CONFIG _ "'")
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 1, "one configuration row " _ when)
	Set row = ##class(%Embedding.Config).%OpenId(..#CONFIG)
	Do $$$AssertEquals(row.EmbeddingClass, "OcuTalon.Memory.Embedding", "of the embedding class " _ when)
	Do $$$AssertEquals(row.VectorLength, 384, "with 384 dimensions " _ when)
	Do $$$AssertEquals(row.Description, ##class(OcuTalon.Memory.Embedding).#CONFIGDESCRIPTION, "and the description " _ when)
	Set configuration = {}.%FromJSON(row.Configuration)
	Do $$$AssertEquals(configuration.modelName, ##class(OcuTalon.Memory.Embedder).#MODEL, "and the model " _ when)
}

/// A temporary folder with a snapshot of the model whose files are placeholders: the model, the tokenizer and the three configuration files.
ClassMethod FolderWithModel() As %String
{
	Set temporary = ##class(%File).TempFilename("d")
	Do ##class(%File).Delete(temporary)
	Set folder = temporary _ "/"
	Set snapshot = folder _ ##class(OcuTalon.Memory.Embedder).#MODELDIR _ "/snapshots/zz1/"
	Do ##class(%File).CreateDirectoryChain(snapshot)
	For name = "model.onnx", "tokenizer.json", "config.json", "tokenizer_config.json", "special_tokens_map.json" {
		Set stream = ##class(%Stream.FileBinary).%New()
		Do stream.LinkToFile(snapshot _ name)
		Do stream.Write("zz")
		Do stream.%Save()
	}
	Quit folder
}

ClassMethod RemoveFolder(folder As %String)
{
	Do ##class(%File).RemoveDirectoryTree(folder)
}

/// The files and folders under the folder, as one text.
ClassMethod Listing(folder As %String) As %String
{
	Set text = ""
	Set rs = ##class(%ResultSet).%New("%File:FileSet")
	Do rs.Execute(folder, "*", "Name", 1)
	While rs.Next() {
		Set text = text _ rs.Get("Name") _ "|"
		If rs.Get("Type") = "D" Set text = text _ ..Listing(rs.Get("Name"))
	}
	Quit text
}

}
