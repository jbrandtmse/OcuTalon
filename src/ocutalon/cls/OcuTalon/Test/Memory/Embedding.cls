/// Tests of OcuTalon.Memory.Embedding and the worker behind it (Story 19.2; AD-6, AD-21). They need the Python package fastembed and the baked model
/// folder, so they run only on OcuTalon's Docker image (a throwaway stack or CI) and record one named skip elsewhere. Each test makes the category
/// OcuTalon.Memory.Embedder and the configuration row OcuTalonMemory when the install has not, and removes only what it made.
///   - TestDimensions: a vector of 384 DOUBLE values;
///   - TestIdentityWithAiHub: for the three texts of the matrix (ASCII; an accented Latin letter and CJK characters; over 256 word pieces), the vector of every chunk
///     that AI Hub's FastEmbed stored equals the vector of the same text from this class, every component within 1e-6;
///   - TestRunsInAWorker: Embed runs its work in a worker of the category OcuTalon.Memory.Embedder, not in the calling process;
///   - TestFolderArgument: the worker embeds from a folder other than the process's FASTEMBED_CACHE_DIR (a copy of the baked one), sets the variable to
///     it inside itself, and returns the same vector; the work item then removes the worker's model for the copy and puts its variable back;
///   - TestSqlConsumers: SELECT EMBEDDING(text, 'OcuTalonMemory') and an embedding column of a fixture class return the same vector as Embed;
///   - TestInvalidConfig: IsValidConfig refuses another model and another dimension, and the configuration table refuses such a row;
///   - TestWorkerFailure: a missing model folder and an unknown work item come back as an error status at once, and the caller embeds afterwards;
///   - TestInputForms: a dynamic object is embedded as its JSON text, and an empty text embeds as a vector of 384 values;
///   - TestSubmitTimeout: a work item that is not done within its timeout (one that waits 10 seconds, with a timeout of 1) comes back as an error
///     status that says so, at the timeout and not when the work is done, and the caller embeds afterwards;
///   - TestModelLoadsOnce: a worker keeps the one model object across embeds (the object's Python identity does not change);
///   - TestModelKeptAcrossCalls: across separate calls of Submit, a worker that embedded before does not load the model again.
Class OcuTalon.Test.Memory.Embedding Extends %UnitTest.TestCase
{

Parameter TOLERANCE = 0.000001;

Method OnBeforeAllTests() As %Status
{
	Kill ^||OcuTalonTestMemory
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit $$$OK
	Set sc = ##class(OcuTalon.Test.Memory.Fixture).Prepare(.state)
	Merge ^||OcuTalonTestMemory = state
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Merge state = ^||OcuTalonTestMemory
	Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
	Kill ^||OcuTalonTestMemory
	Quit $$$OK
}

/// 1 on the image; otherwise records the skip.
Method OnImage() As %Boolean [ Private ]
{
	If ##class(OcuTalon.Test.Memory.Fixture).OnImage() Quit 1
	Do $$$AssertSkipped("Not OcuTalon's image: " _ ##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE _ " does not exist on this instance (a slot or a developer instance)")
	Quit 0
}

Method TestDimensions()
{
	If '..OnImage() Quit
	Set sc = ##class(OcuTalon.Memory.Embedding).Embed(##class(OcuTalon.Test.Memory.Fixture).Matrix(1), .vector)
	Do $$$AssertStatusOK(sc, "the text is embedded")
	Do $$$AssertTrue($IsVector(vector), "the result is a vector")
	Do $$$AssertEquals($VOP("length", vector), 384, "of 384 values")
	Do $$$AssertEquals($VOP("type", vector), "double", "of type double")
	Set same = ##class(OcuTalon.Memory.Embedding).Embedding(##class(OcuTalon.Test.Memory.Fixture).Matrix(1), ##class(OcuTalon.Test.Memory.Embedding).Config())
	Do $$$AssertTrue(##class(OcuTalon.Test.Memory.Fixture).Distance(vector, same) < 0.000000001, "Embedding, the interface method, returns the same vector")
}

Method TestIdentityWithAiHub()
{
	If '..OnImage() Quit
	Set table = "OcuTalonKB.ZzMid", suffix = "ZzMid"
	Try {
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).CreateTable(table, suffix), "the test table is made")
		For n = 1:1:3 {
			Set texts(n) = ##class(OcuTalon.Test.Memory.Fixture).Matrix(n)
		}
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).HubFill(table, .texts), "AI Hub's FastEmbed embeds the three texts")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).HubRows(table, .rows), "and the rows are read")
		Set count = 0
		Set n = ""
		For {
			Set n = $Order(rows(n))
			Quit:n=""
			Set count = count + 1
			Set sc = ##class(OcuTalon.Memory.Embedding).Embed(rows(n), .vector)
			Do $$$AssertStatusOK(sc, "chunk " _ n _ " is embedded")
			If $SYSTEM.Status.IsError(sc) Continue
			Set distance = ##class(OcuTalon.Test.Memory.Fixture).Distance(vector, rows(n, "vector"))
			Do $$$AssertTrue(distance <= ..#TOLERANCE, "chunk " _ n _ " equals AI Hub's vector within 1e-6, to " _ distance)
		}
		Do $$$AssertTrue(count >= 3, "at least one chunk per text: " _ count)
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the identity check ran")
	}
	Do ##class(OcuTalon.Test.Memory.Fixture).DropTable(table, suffix)
}

Method TestRunsInAWorker()
{
	If '..OnImage() Quit
	Set sc = ##class(OcuTalon.Memory.Embedding).Embed(##class(OcuTalon.Test.Memory.Fixture).Matrix(1), .vector, .job)
	Do $$$AssertStatusOK(sc, "Embed finishes")
	Do $$$AssertTrue(job '= "", "and reports the job that ran it")
	Do $$$AssertTrue(job '= $Job, "which is not the calling process")
	Do $$$AssertTrue(##class(OcuTalon.Test.Memory.Fixture).WorkerInCategory(job, ##class(OcuTalon.Memory.Embedder).#CATEGORY), "and is a worker of the category " _ ##class(OcuTalon.Memory.Embedder).#CATEGORY)
	Do $$$AssertEquals($VOP("length", vector), 384, "and returns the 384 values")
}

Method TestFolderArgument()
{
	If '..OnImage() Quit
	Set copy = $SYSTEM.Util.ManagerDirectory() _ "zz-memory-embed-copy-" _ $Job _ "/"
	Try {
		Set text = ##class(OcuTalon.Test.Memory.Fixture).Matrix(2)
		Do $$$AssertEquals(##class(OcuTalon.Test.Memory.Fixture).CopyBaked(copy), 0, "the baked folder is copied under the manager directory")
		Do $$$AssertTrue(copy '= ##class(OcuTalon.Memory.Embedder).ModelFolder(), "which is not the folder of the process's variable")
		Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed(text, .baked), "the text is embedded from the baked folder")
		Set sc = ##class(OcuTalon.Memory.Embedder).Submit("##class(OcuTalon.Test.Memory.Fixture).EmbedFromFolder", ##class(OcuTalon.Memory.Embedder).#TIMEOUT, .result, text, copy)
		Do $$$AssertStatusOK(sc, "and from the copy, in a worker")
		Do $$$AssertEquals($Get(result("variable")), copy, "whose FASTEMBED_CACHE_DIR is the copy")
		Set fromCopy = ##class(OcuTalon.Test.Memory.Fixture).ToVector($Get(result("vector")))
		Do $$$AssertEquals($VOP("length", fromCopy), 384, "with 384 values")
		Do $$$AssertTrue(##class(OcuTalon.Test.Memory.Fixture).Distance(baked, fromCopy) < 0.000000001, "equal to the vector from the baked folder")
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the folder argument check ran")
	}
	Do ##class(OcuTalon.Test.Memory.Fixture).RemoveCopy(copy)
}

Method TestSqlConsumers()
{
	If '..OnImage() Quit
	Set text = ##class(OcuTalon.Test.Memory.Fixture).Matrix(2)
	Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed(text, .direct), "the text is embedded")
	Set statement = ##class(%SQL.Statement).%New()
	Do $$$AssertStatusOK(statement.%Prepare("SELECT EMBEDDING(?, 'OcuTalonMemory')", 1), "EMBEDDING() prepares")
	Set result = statement.%Execute(text)
	Do $$$AssertTrue(result.%SQLCODE >= 0, "and runs")
	Do $$$AssertTrue(result.%Next(), "and returns a row")
	Set viaSql = ##class(OcuTalon.Test.Memory.Fixture).ToVector(result.%GetData(1))
	Do $$$AssertTrue(##class(OcuTalon.Test.Memory.Fixture).Distance(direct, viaSql) < 0.000000001, "the SQL function returns the same vector")

	Set class = "OcuTalon.Test.Memory.ZzEmbedded", globalName = "OcuTalonP.ZzMemoryEmbedded"
	Try {
		Set source = ##class(%Stream.TmpCharacter).%New()
		Do source.WriteLine("Class " _ class _ " Extends %Persistent")
		Do source.WriteLine("{")
		Do source.WriteLine("Parameter DEFAULTGLOBAL = ""^" _ globalName _ """;")
		Do source.WriteLine("Property Text As %String(MAXLEN = 2000);")
		Do source.WriteLine("Property Vec As %Library.Embedding(MODEL = ""OcuTalonMemory"", SOURCE = ""Text"");")
		Do source.WriteLine("}")
		Do source.Rewind()
		Do $$$AssertStatusOK($SYSTEM.OBJ.LoadStream(source, "ck-d"), "the fixture class with an embedding column compiles")
		Set row = $ClassMethod(class, "%New")
		Set row.Text = text
		Do $$$AssertStatusOK(row.%Save(), "a row is saved, which computes its embedding")
		Do $$$AssertTrue(##class(OcuTalon.Test.Memory.Fixture).Distance(direct, row.Vec) < 0.000000001, "the embedding column holds the same vector")
		Set row = ""
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the embedding column check ran")
	}
	If ##class(%Dictionary.CompiledClass).%ExistsId(class) Do $ClassMethod(class, "%DeleteExtent")
	Do $SYSTEM.OBJ.Delete(class, "-d")
	Kill @("^" _ globalName _ "D"), @("^" _ globalName _ "I"), @("^" _ globalName _ "S")
}

Method TestInvalidConfig()
{
	Set model = "sentence-transformers/all-MiniLM-L6-v2"
	Do $$$AssertTrue(##class(OcuTalon.Memory.Embedding).IsValidConfig({"modelName": (model), "dimensions": 384}, .message), "AllMiniLM-L6-v2 with 384 is valid")
	Do $$$AssertTrue(##class(OcuTalon.Memory.Embedding).IsValidConfig({"modelName": (model)}, .message), "and so is the model alone")
	Do $$$AssertTrue('##class(OcuTalon.Memory.Embedding).IsValidConfig({"modelName": "BAAI/bge-small-en-v1.5", "dimensions": 384}, .message), "another model is not valid")
	Do $$$AssertTrue(message '= "", "and says which setting")
	Set message = ""
	Do $$$AssertTrue('##class(OcuTalon.Memory.Embedding).IsValidConfig({"modelName": (model), "dimensions": 768}, .message), "another dimension is not valid")
	Do $$$AssertTrue(message '= "", "and says which setting")
	Do $$$AssertTrue('##class(OcuTalon.Memory.Embedding).IsValidConfig({}, .message), "no model is not valid")
	Set name = "OcuTalonZzMemoryBad"
	Set statement = ##class(%SQL.Statement).%New()
	Do statement.%Prepare("INSERT INTO %Embedding.Config (Name, Configuration, EmbeddingClass, VectorLength) VALUES (?, ?, ?, ?)", 1)
	Set result = statement.%Execute(name, {"modelName": "BAAI/bge-small-en-v1.5"}.%ToJSON(), "OcuTalon.Memory.Embedding", 384)
	Do $$$AssertTrue(result.%SQLCODE < 0, "the configuration table refuses a row for another model")
	Do $$$AssertTrue('##class(%Embedding.Config).%ExistsId(name), "and keeps no row")
	If ##class(%Embedding.Config).%ExistsId(name) Do ##class(%Embedding.Config).%DeleteId(name)
}

Method TestWorkerFailure()
{
	If '..OnImage() Quit
	Set text = ##class(OcuTalon.Test.Memory.Fixture).Matrix(1)
	Set folder = $SYSTEM.Util.ManagerDirectory() _ "zz-memory-no-model/"
	Do ##class(%File).RemoveDirectoryTree(folder)
	Set started = $ZHorolog
	Set sc = ##class(OcuTalon.Memory.Embedder).Submit("Embed", ##class(OcuTalon.Memory.Embedder).#TIMEOUT, .result, text, folder)
	Do $$$AssertStatusNotOK(sc, "a folder with no model is an error status")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "holds no", "and says that the folder holds no model: " _ $SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertTrue($ZHorolog - started < 30, "which comes back at once, with no network try")
	Do $$$AssertTrue('##class(%File).DirectoryExists(folder), "and makes no folder")
	Set sc = ##class(OcuTalon.Memory.Embedder).Submit("NoSuchWorkItem", ##class(OcuTalon.Memory.Embedder).#TIMEOUT, .result)
	Do $$$AssertStatusNotOK(sc, "an unknown work item is an error status")
	Set sc = ##class(OcuTalon.Memory.Embedding).Embed(text, .vector)
	Do $$$AssertStatusOK(sc, "and the caller embeds afterwards")
	Do $$$AssertEquals($VOP("length", vector), 384, "with 384 values")
	Set thrown = 0
	Try {
		Do ##class(OcuTalon.Memory.Embedding).Embedding(text, {"modelName": "other"}.%ToJSON())
	} Catch {
		Set thrown = 1
	}
	Do $$$AssertTrue(thrown, "Embedding throws for a configuration that is not valid")
}

Method TestInputForms()
{
	If '..OnImage() Quit
	Set object = {"owner": "Lee", "topic": "the Results partner"}
	Set vector = ##class(OcuTalon.Memory.Embedding).Embedding(object, ##class(OcuTalon.Test.Memory.Embedding).Config())
	Do $$$AssertTrue($IsVector(vector), "a dynamic object is embedded")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed(object.%ToJSON(), .fromText), "and so is its JSON text")
	Do $$$AssertTrue(##class(OcuTalon.Test.Memory.Fixture).Distance(vector, fromText) < 0.000000001, "the object's vector is its JSON text's vector")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed("Lee the Results partner", .words), "the words of the object")
	Do $$$AssertTrue(##class(OcuTalon.Test.Memory.Fixture).Distance(vector, words) > 0.001, "are another text, so the equality above is not one vector for every input")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed("", .empty), "an empty text is embedded")
	Do $$$AssertEquals($VOP("length", empty), 384, "as 384 values")
	Do $$$AssertTrue(##class(OcuTalon.Test.Memory.Fixture).Distance(empty, fromText) > 0.001, "which differ from the vector of a text")
}

Method TestSubmitTimeout()
{
	If '..OnImage() Quit
	Set text = ##class(OcuTalon.Test.Memory.Fixture).Matrix(1)
	Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed(text, .expected), "a worker has the model loaded")
	Set started = $ZHorolog
	Set sc = ##class(OcuTalon.Memory.Embedder).Submit("##class(OcuTalon.Test.Memory.Fixture).Slow", 1, .result, 10)
	Set waited = $ZHorolog - started
	Do $$$AssertStatusNotOK(sc, "a work item that waits 10 seconds, with a timeout of 1 second, comes back as an error status")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "did not finish within 1 seconds", "which says that it did not finish in time: " _ $SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertTrue(waited < 8, "at the timeout, not when the work is done (the wait was " _ waited _ " s)")
	Do $$$AssertStatusOK(##class(OcuTalon.Memory.Embedding).Embed(text, .vector), "and the caller embeds afterwards")
	Do $$$AssertTrue(##class(OcuTalon.Test.Memory.Fixture).Distance(vector, expected) < 0.000000001, "with the same vector")
}

Method TestModelLoadsOnce()
{
	If '..OnImage() Quit
	Set sc = ##class(OcuTalon.Test.Memory.Fixture).WorkerLoads(##class(OcuTalon.Test.Memory.Fixture).Matrix(1), ##class(OcuTalon.Memory.Embedder).ModelFolder(), .info)
	Do $$$AssertStatusOK(sc, "a worker embeds the text three times")
	If $SYSTEM.Status.IsError(sc) Quit
	Do $$$AssertTrue(info("job") '= $Job, "in a worker, not in the calling process")
	Do $$$AssertTrue(info("id", 1) '= "", "after the first embed the worker holds a model for the folder")
	Do $$$AssertEquals(info("id", 2), info("id", 1), "the second embed uses the same model object")
	Do $$$AssertEquals(info("id", 3), info("id", 1), "and so does the third")
}

Method TestModelKeptAcrossCalls()
{
	If '..OnImage() Quit
	Set text = ##class(OcuTalon.Test.Memory.Fixture).Matrix(1)
	Set folder = ##class(OcuTalon.Memory.Embedder).ModelFolder()
	Set again = 0
	For call = 1:1:10 {
		Set sc = ##class(OcuTalon.Memory.Embedder).Submit("Embed", ##class(OcuTalon.Memory.Embedder).#TIMEOUT, .result, text, folder)
		Do $$$AssertStatusOK(sc, "call " _ call _ " embeds")
		If $SYSTEM.Status.IsError(sc) Quit
		Set job = $Get(result("job"))
		If $Data(seen(job)) {
			Set again = again + 1
			Do $$$AssertEquals($Get(result("loaded")), 0, "call " _ call _ " runs in worker " _ job _ ", which embedded before, and does not load the model again")
		}
		Set seen(job) = 1
	}
	Do $$$AssertTrue(again > 0, "a worker ran more than one of the ten calls: " _ again)
}

/// The configuration text of the OcuTalonMemory row.
ClassMethod Config() As %String
{
	Quit {"modelName": (##class(OcuTalon.Memory.Embedder).#MODEL), "dimensions": (##class(OcuTalon.Memory.Embedder).#DIMENSIONS)}.%ToJSON()
}

}
