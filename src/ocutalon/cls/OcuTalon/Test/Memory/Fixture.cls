/// What the Memory area's tests share (Story 19.2). Not a test case.
///   - OnImage(): 1 on OcuTalon's Docker image (its version file exists), the only place with the Python package, the baked model folder and AI Hub's
///     FastEmbed offline; a slot or a developer instance records a named skip instead.
///   - Prepare(.state) / Restore(.state): the WorkMgr category OcuTalon.Memory.Embedder and the %Embedding.Config row OcuTalonMemory exist for a test
///     run. Prepare makes whichever is missing, through the install step's own methods, and records in state what it made; Restore removes only that,
///     so a test never removes what the install made.
///   - CreateTable / DropTable: an AI Hub vector-store table with AI Hub's exact columns and a private DEFAULTGLOBAL under ^OcuTalonP. (AD-21), and its
///     _Config table; DropTable removes both and their globals.
///   - HubFill(table, .texts): AI Hub's FastEmbed (from the process's FASTEMBED_CACHE_DIR) embeds each texts(n) into the table as the document t<n>;
///     HubRows(table, .rows) reads back rows(n) = the chunk's text and rows(n, "vector") = its vector, in the order of source and id.
///   - ToVector(value) / ToString(vector): the vector of a value that is a $VECTOR already or the text of one (a display value of a vector column), and the
///     comma-separated text of a vector's values.
///   - Matrix(n): the three texts of the identity checks (ASCII; an accented Latin letter and CJK characters, authored with $Char; over 256 word pieces).
///   - Distance(a, b): the largest absolute difference of two vectors' components.
///   - WorkerInCategory(job, category): 1 when the WorkMgr worker process with that $JOB belongs to the category (WorkMgr keeps it in ^IRIS.WorkQueue).
///   - WorkerLoads(text, folder, .info): queues LoadsInOneWorker to a worker of the category; the worker embeds the text three times through
///     OcuTalon.Memory.Embedder:Embed and info("id", n) is the Python identity of the model object it holds for the folder after the n-th embed, so a test
///     sees whether the model is loaded once per worker process;
///   - Slow(seconds): a work item that only waits, so a test sees a work item that does not finish within its timeout;
///   - EmbedFromFolder(text, folder): a work item that embeds through OcuTalon.Memory.Embedder:Embed from a folder of the test's own, returns Embed's
///     %result, then removes the worker's model for that folder and puts the worker's FASTEMBED_CACHE_DIR back, so the worker keeps nothing of the test;
///   - PutVariable(environ, previous): puts a worker's FASTEMBED_CACHE_DIR back to previous (removed when previous is empty);
///   - CopyBaked(copy) / RemoveCopy(copy): a copy of the process's FASTEMBED_CACHE_DIR folder (a status of the copy command, 0 when made) and its removal.
Class OcuTalon.Test.Memory.Fixture
{

/// The image's version file, as the install step reads it.
Parameter VERSIONFILE As COSEXPRESSION = "##class(OcuTalon.Install.Step.Demo).#VERSIONFILE";

ClassMethod OnImage() As %Boolean
{
	Quit ##class(%File).Exists(..#VERSIONFILE)
}

ClassMethod Prepare(Output state) As %Status
{
	Kill state
	Set category = ##class(OcuTalon.Memory.Embedder).#CATEGORY
	If '..CategoryExists(category) {
		Set sc = ##class(OcuTalon.Install.Step.Memory).EnsureCategory(category, ##class(OcuTalon.Memory.Embedder).#MAXACTIVEWORKERS, ##class(OcuTalon.Memory.Embedder).#DEFAULTWORKERS)
		If $SYSTEM.Status.IsError(sc) Quit sc
		Set state("category") = 1
	}
	If '##class(%Embedding.Config).%ExistsId(##class(OcuTalon.Memory.Embedding).#CONFIGNAME) {
		Set sc = ##class(OcuTalon.Install.Step.Memory).EnsureConfig()
		If $SYSTEM.Status.IsError(sc) Quit sc
		Set state("config") = 1
	}
	Quit $SYSTEM.Status.OK()
}

/// The category's properties in properties(<name>) (Config.WorkQueues is in %SYS).
ClassMethod CategoryProperties(name As %String, Output properties) As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ##class(Config.WorkQueues).Get(name, .properties)
}

/// 1 when the WorkMgr category exists (Config.WorkQueues is in %SYS).
ClassMethod CategoryExists(name As %String) As %Boolean
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ##class(Config.WorkQueues).Exists(name)
}

ClassMethod Restore(ByRef state)
{
	If $Get(state("config")) {
		Set statement = ##class(%SQL.Statement).%New()
		Do statement.%Prepare("DELETE FROM %Embedding.Config WHERE Name = ?", 1)
		Do statement.%Execute(##class(OcuTalon.Memory.Embedding).#CONFIGNAME)
	}
	If $Get(state("category")) {
		New $Namespace
		Set $Namespace = "%SYS"
		Do ##class(Config.WorkQueues).Delete(##class(OcuTalon.Memory.Embedder).#CATEGORY)
	}
	Kill state
}

/// Makes the table and its _Config table, with the globals ^OcuTalonP.KB<suffix> and ^OcuTalonP.KB<suffix>Config.
ClassMethod CreateTable(table As %String, suffix As %String) As %Status
{
	Do ..DropTable(table, suffix)
	Set columns = "id VARCHAR(64) NOT NULL, text VARCHAR(32000) NOT NULL, vector VECTOR(DOUBLE, 384) NOT NULL, metadata VARCHAR(32000), source VARCHAR(512), PRIMARY KEY (id)"
	Set sql = "CREATE TABLE " _ table _ " (" _ columns _ ") WITH %CLASSPARAMETER DEFAULTGLOBAL = '^OcuTalonP.KB" _ suffix _ "'"
	Set result = ##class(%SQL.Statement).%ExecDirect(, sql)
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "CREATE TABLE " _ table _ ": " _ result.%Message)
	Set sql = "CREATE TABLE " _ table _ "_Config (model_name VARCHAR(255) NOT NULL, dimensions INTEGER NOT NULL) WITH %CLASSPARAMETER DEFAULTGLOBAL = '^OcuTalonP.KB" _ suffix _ "Config'"
	Set result = ##class(%SQL.Statement).%ExecDirect(, sql)
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "CREATE TABLE " _ table _ "_Config: " _ result.%Message)
	Quit $SYSTEM.Status.OK()
}

ClassMethod DropTable(table As %String, suffix As %String)
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DROP TABLE IF EXISTS " _ table _ "_Config")
	Do ##class(%SQL.Statement).%ExecDirect(, "DROP TABLE IF EXISTS " _ table)
	Kill @("^OcuTalonP.KB" _ suffix), @("^OcuTalonP.KB" _ suffix _ "Config")
}

ClassMethod Matrix(n As %Integer) As %String
{
	If n = 1 Quit "the Results partner's contact is Lee"
	If n = 2 Quit "Caf" _ $Char(233) _ " meeting with the " _ $Char(26085, 26412) _ " " _ $Char(27721, 35486) _ " team about r" _ $Char(233) _ "sum" _ $Char(233) _ "s"
	Set text = ""
	For i = 1:1:60 {
		Set text = text _ "Partner " _ i _ " asked about invoices and delivery dates, then sent the reminder " _ (i * 7) _ " to the warehouse. "
	}
	Quit text
}

/// AI Hub's FastEmbed embeds each texts(n) into the table (made by CreateTable) as the document t<n>.
ClassMethod HubFill(table As %String, ByRef texts) As %Status
{
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set embedding = ##class(%AI.RAG.Embedding.FastEmbed).Create()
		Set store = ##class(%AI.RAG.VectorStore.IRIS).%New()
		Set store.Schema = $Piece(table, ".", 1)
		Set store.TableName = table
		Set store.Dimensions = 384
		Set store.ModelName = "AllMiniLML6V2"
		$$$ThrowOnError(store.Build())
		Set base = ##class(%AI.RAG.KnowledgeBase).%New("memory_test", "Memory test")
		$$$ThrowOnError(base.Build(embedding, store))
		Set n = ""
		For {
			Set n = $Order(texts(n), 1, text)
			Quit:n=""
			Set metadata = {}
			Do metadata.%Set("source", "t" _ n)
			$$$ThrowOnError(base.AddDocument(text, metadata))
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// rows(n) = the chunk text and rows(n, "vector") = the vector of the n-th row of the table, in the order of source and id.
ClassMethod HubRows(table As %String, Output rows) As %Status
{
	Kill rows
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT text, vector FROM " _ table _ " ORDER BY source, id")
	If result.%SQLCODE < 0 Quit $SYSTEM.Status.Error(5001, "SELECT from " _ table _ ": " _ result.%Message)
	Set n = 0
	While result.%Next() {
		Set n = n + 1
		Set rows(n) = result.%GetData(1)
		Set rows(n, "vector") = ..ToVector(result.%GetData(2))
	}
	Quit $SYSTEM.Status.OK()
}

/// The vector of a value that is a $VECTOR already, or the text of one.
ClassMethod ToVector(value) As %Vector
{
	If $IsVector(value) Quit value
	Quit $VOP("fromstring", $ZStrip(value, "*W", "[]"), "double", ",", 3)
}

/// The values of a vector as comma-separated text, which TO_VECTOR(text, DOUBLE, n) reads.
ClassMethod ToString(vector As %Vector) As %String
{
	Set text = ""
	For i = 1:1:$VOP("length", vector) {
		Set text = text _ $Select(i > 1: ",", 1: "") _ $VECTOR(vector, i)
	}
	Quit text
}

/// The largest absolute difference of the components of two vectors of the same length.
ClassMethod Distance(a As %Vector, b As %Vector) As %Double
{
	Set largest = 0
	For i = 1:1:$VOP("length", a) {
		Set difference = $ZAbs($VECTOR(a, i) - $VECTOR(b, i))
		If difference > largest Set largest = difference
	}
	Quit largest
}

/// 1 when the WorkMgr worker process with that $JOB belongs to the category: WorkMgr keeps ^IRIS.WorkQueue("Worker", <manager>, <worker $JOB>)
/// as the category's name with a suffix.
ClassMethod WorkerInCategory(job As %Integer, category As %String) As %Boolean
{
	If job = "" Quit 0
	Set found = 0
	Set manager = ""
	For {
		Set manager = $Order(^IRIS.WorkQueue("Worker", manager))
		Quit:manager=""
		If $Data(^IRIS.WorkQueue("Worker", manager, job), value) # 2 && (value [ category) Set found = 1 Quit
	}
	Quit found
}

/// Queues LoadsInOneWorker to a worker of the category OcuTalon.Memory.Embedder and waits for it: info("job") is the worker's $JOB and info("id", n) the
/// Python id() of the model object that the worker holds for the folder after its n-th embed (n = 1 to 3).
ClassMethod WorkerLoads(text As %String, folder As %String, Output info) As %Status
{
	Kill info
	Quit ##class(OcuTalon.Memory.Embedder).Submit("##class(OcuTalon.Test.Memory.Fixture).LoadsInOneWorker", 120, .info, text, folder)
}

/// The work item of WorkerLoads: %result("job") and %result("id", n) as above.
ClassMethod LoadsInOneWorker(text As %String, folder As %String) As %Status
{
	Kill %result
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set builtins = ##class(%SYS.Python).Import("builtins")
		Set sys = ##class(%SYS.Python).Import("sys")
		For n = 1:1:3 {
			Set sc = ##class(OcuTalon.Memory.Embedder).Embed(text, folder)
			$$$ThrowOnError(sc)
			Set models = builtins.getattr(sys, ##class(OcuTalon.Memory.Embedder).#CACHEATTRIBUTE)
			Set id(n) = builtins.id(models."__getitem__"(folder))
		}
		Kill %result
		Set %result("job") = $Job
		For n = 1:1:3 {
			Set %result("id", n) = id(n)
		}
	} Catch exception {
		Kill %result
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The work item that waits seconds and returns OK.
ClassMethod Slow(seconds As %Integer) As %Status
{
	Hang seconds
	Quit $SYSTEM.Status.OK()
}

/// The work item that embeds the text from the folder, as EmbedFromFolder above says.
ClassMethod EmbedFromFolder(text As %String, folder As %String) As %Status
{
	Set environ = ##class(%SYS.Python).Import("os").environ
	Set previous = $SYSTEM.Util.GetEnviron(##class(OcuTalon.Memory.Embedder).#FOLDERVARIABLE)
	Set sc = ##class(OcuTalon.Memory.Embedder).Embed(text, folder)
	Merge kept = %result
	Set builtins = ##class(%SYS.Python).Import("builtins")
	Set sys = ##class(%SYS.Python).Import("sys")
	If builtins.hasattr(sys, ##class(OcuTalon.Memory.Embedder).#CACHEATTRIBUTE) {
		Do builtins.getattr(sys, ##class(OcuTalon.Memory.Embedder).#CACHEATTRIBUTE).pop(folder, "")
	}
	Do ..PutVariable(environ, previous)
	Kill %result
	Merge %result = kept
	Quit sc
}

/// Puts the worker's FASTEMBED_CACHE_DIR back to previous, or removes it when previous is empty.
ClassMethod PutVariable(environ, previous As %String)
{
	Set variable = ##class(OcuTalon.Memory.Embedder).#FOLDERVARIABLE
	If previous '= "" {
		Do environ."__setitem__"(variable, previous)
	} Else {
		Do environ.pop(variable, "")
	}
}

/// Copies the baked folder (the process's FASTEMBED_CACHE_DIR) to copy; returns the copy command's exit status.
ClassMethod CopyBaked(copy As %String) As %Integer
{
	Do ..RemoveCopy(copy)
	Quit $ZF(-100, "/SHELL", "cp", "-r", $SYSTEM.Util.GetEnviron(##class(OcuTalon.Memory.Embedder).#FOLDERVARIABLE), copy)
}

/// Removes a copy of the baked folder: the copy keeps the read-only modes of the original, so the owner may write again before it is removed.
ClassMethod RemoveCopy(copy As %String)
{
	If '##class(%File).DirectoryExists(copy) Quit
	Do $ZF(-100, "/SHELL", "chmod", "-R", "u+w", copy)
	Do ##class(%File).RemoveDirectoryTree(copy)
}

}
