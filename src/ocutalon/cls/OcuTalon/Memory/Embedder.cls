/// The worker side of the memory embeddings (AD-6, AD-21): the Python package fastembed 0.9.0, driven through %SYS.Python from ObjectScript,
/// runs only inside a %SYSTEM.WorkMgr worker of the category OcuTalon.Memory.Embedder (at most 2 active workers), never in the calling process.
/// This is the one class of the area that references %SYS.Python; the callers (OcuTalon.Memory.Embedding, the install step and the tools) call
/// Submit, which queues a work item and holds no Python.
///   - ModelFolder() is the one rule for the model folder: the IRIS process's FASTEMBED_CACHE_DIR when it is set and not empty (the image: /opt/fastembed),
///     otherwise the manager directory's fastembed/ folder (an IPM install downloads the model there).
///   - Embed(text, folder) is the work item that embeds one text. It sets FASTEMBED_CACHE_DIR to the folder inside the worker before the model's first
///     use, loads the model once per worker process with the folder as the package's cache_dir and local_files_only (a missing model fails at once, with
///     no network try), and returns the vector in %result("vector").
///   - Download(folder) is the work item that downloads the model into the folder, with the call that the image's build makes.
/// A work item returns an error %Status when the package or the model is missing or the folder holds no model; Submit returns that status, or an error
/// when the item does not finish within its timeout, and never throws.
Class OcuTalon.Memory.Embedder
{

/// The WorkMgr category of the workers (AD-6): created by the Memory install step.
Parameter CATEGORY = "OcuTalon.Memory.Embedder";

/// The most active workers of the category, and the workers a work group asks for by default (about 220 MB each).
Parameter MAXACTIVEWORKERS = 2;

Parameter DEFAULTWORKERS = 1;

/// The model's name in the Python package, its Hugging Face source and its folder in a cache.
Parameter MODEL = "sentence-transformers/all-MiniLM-L6-v2";

Parameter SOURCE = "Qdrant/all-MiniLM-L6-v2-onnx";

Parameter MODELDIR = "models--Qdrant--all-MiniLM-L6-v2-onnx";

/// The files that a download fetches (the pattern list of the image's build), and the files that a usable snapshot holds.
Parameter PATTERNS = "config.json,tokenizer.json,tokenizer_config.json,special_tokens_map.json,*.onnx";

Parameter SNAPSHOTFILES = "model.onnx,tokenizer.json,config.json,tokenizer_config.json,special_tokens_map.json";

Parameter DIMENSIONS = 384;

/// The environment variable that names the model folder.
Parameter FOLDERVARIABLE = "FASTEMBED_CACHE_DIR";

/// Seconds that a caller waits for an embedding, and for a download.
Parameter TIMEOUT = 120;

Parameter DOWNLOADTIMEOUT = 600;

/// The attribute of the Python sys module that holds the loaded models of the worker process, one per folder.
Parameter CACHEATTRIBUTE = "ocutalon_memory_models";

/// The folder that holds the model, by the one rule above. variable names the environment variable; only a test passes another.
ClassMethod ModelFolder(variable As %String = {..#FOLDERVARIABLE}) As %String
{
	Set folder = $SYSTEM.Util.GetEnviron(variable)
	If folder '= "" Quit folder
	Quit $SYSTEM.Util.ManagerDirectory() _ "fastembed/"
}

/// 1 when the folder holds the model: a snapshot of the model's folder with every file that the package loads.
ClassMethod HasModel(folder As %String) As %Boolean
{
	If folder = "" Quit 0
	Set snapshots = ##class(%File).NormalizeDirectory(folder) _ ..#MODELDIR _ "/snapshots/"
	Set found = 0
	Set entry = $ZSearch(snapshots _ "*")
	While entry '= "" {
		Set complete = ##class(%File).DirectoryExists(entry)
		Set files = $ListFromString(..#SNAPSHOTFILES, ",")
		Set position = 0
		While complete && $ListNext(files, position, name) {
			If '##class(%File).Exists(##class(%File).NormalizeDirectory(entry) _ name) Set complete = 0
		}
		If complete Set found = 1 Quit
		Set entry = $ZSearch("")
	}
	Quit found
}

/// Queues one work item of this class to the category and waits for it at most timeout seconds. The work item's %result nodes come back in
/// result. Returns the work item's status, or an error status when no group could be made, the item could not be queued or it did not finish in
/// time. Never throws.
ClassMethod Submit(entry As %String, timeout As %Integer, Output result, args... As %String) As %Status
{
	Kill result
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set queue = $SYSTEM.WorkMgr.%New("", 1, ..#CATEGORY)
		If queue = "" {
			Set sc = $SYSTEM.Status.Error(5001, "No work group of category " _ ..#CATEGORY _ " could be made: " _ $SYSTEM.Status.GetErrorText($Get(%objlasterror)))
		} Else {
			Set sc = queue.Queue("##class(" _ $ClassName() _ ")." _ entry, args...)
			If $SYSTEM.Status.IsOK(sc) {
				If 'queue.WaitOne(timeout, .workStatus, .workArgs, .workResult) {
					Set sc = $SYSTEM.Status.Error(5001, "The work item " _ entry _ " did not finish within " _ timeout _ " seconds")
				} ElseIf $SYSTEM.Status.IsError(workStatus) {
					Set sc = workStatus
				} Else {
					Merge result = workResult
				}
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The work item that embeds one text: %result("vector") is the vector as the Python list's text, %result("job") the worker's $JOB and
/// %result("variable") the worker's FASTEMBED_CACHE_DIR once the model's folder is set.
ClassMethod Embed(text As %String, folder As %String) As %Status
{
	Kill %result
	Set sc = $SYSTEM.Status.OK()
	If '..HasModel(folder) Quit $SYSTEM.Status.Error(5001, "The model folder " _ folder _ " holds no " _ ..#MODELDIR)
	Try {
		Set builtins = ##class(%SYS.Python).Import("builtins")
		Set sys = ##class(%SYS.Python).Import("sys")
		Do ##class(%SYS.Python).Import("os").environ."__setitem__"(..#FOLDERVARIABLE, folder)
		If 'builtins.hasattr(sys, ..#CACHEATTRIBUTE) Do builtins.setattr(sys, ..#CACHEATTRIBUTE, builtins.dict())
		Set models = builtins.getattr(sys, ..#CACHEATTRIBUTE)
		If 'models."__contains__"(folder) {
			Set make = builtins.eval("lambda package, folder: package.TextEmbedding('" _ ..#MODEL _ "', cache_dir=folder, local_files_only=True)", builtins.dict())
			Do models."__setitem__"(folder, make."__call__"(##class(%SYS.Python).Import("fastembed"), folder))
		}
		Set batch = builtins.list()
		Do batch.append(text)
		Set values = builtins.list(models."__getitem__"(folder).embed(batch))."__getitem__"(0).tolist()
		Set %result("vector") = builtins.str(values)
		Set %result("job") = $Job
		Set %result("variable") = $SYSTEM.Util.GetEnviron(..#FOLDERVARIABLE)
	} Catch exception {
		Kill %result
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The work item that downloads the model into the folder (made when missing) with the call of the image's build: huggingface_hub's snapshot_download
/// of the source repository with the pattern list, with the image build's telemetry setting (set before the package is imported). %result("job")
/// is the worker's $JOB.
ClassMethod Download(folder As %String) As %Status
{
	Kill %result
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set builtins = ##class(%SYS.Python).Import("builtins")
		Do ##class(%SYS.Python).Import("os").environ."__setitem__"("HF_HUB_DISABLE_TELEMETRY", "1")
		Set hub = ##class(%SYS.Python).Import("huggingface_hub")
		Set made = ##class(%File).DirectoryExists(folder)
		If 'made Set made = ##class(%File).CreateDirectoryChain(folder)
		If 'made {
			Set sc = $SYSTEM.Status.Error(5001, "The model folder " _ folder _ " could not be made")
		} Else {
			Set patterns = builtins.list()
			Set list = $ListFromString(..#PATTERNS, ",")
			Set position = 0
			While $ListNext(list, position, pattern) {
				Do patterns.append(pattern)
			}
			Set download = builtins.eval("lambda hub, folder, patterns: hub.snapshot_download('" _ ..#SOURCE _ "', cache_dir=folder, allow_patterns=patterns)", builtins.dict())
			Do download."__call__"(hub, folder, patterns)
			Set %result("job") = $Job
		}
	} Catch exception {
		Kill %result
		Set sc = exception.AsStatus()
	}
	Quit sc
}

}
