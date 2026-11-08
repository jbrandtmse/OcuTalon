/// The worker side of the PDF and Word text extraction (AD-6, AD-21): the Python packages pdfplumber 0.11.10 and python-docx 1.1.2, driven by the resource
/// ocutalon_extract.py (src/ocutalon/python, in the manager directory's python folder, imported with %SYS.Python.Import), run only inside a %SYSTEM.WorkMgr
/// worker of the category OcuTalon.Docs.Extractor (one worker), never in the calling process. With OcuTalon.Memory.Embedder it is one of the two classes that
/// reference %SYS.Python; the caller side is OcuTalon.Docs.Extract, which queues Read through Submit (OcuTalon.Memory.Worker) and holds no Python.
///   - Read(path, limit, maxUnpacked, pageMarker) is the work item. It imports the resource, calls its extract() on the file and copies the answer into
///     %result: ok (1 or 0), then text, cut (1 or 0) and markers for a text, or reason and detail for a file that cannot be read; job is the worker's $JOB.
///   - A Python exception is an error status (the caller reports it as the reason failed), never a throw.
///   - A timeout stops the busy worker (STOPONTIMEOUT), so that one slow file cannot hold the one worker.
Class OcuTalon.Docs.Extractor Extends OcuTalon.Memory.Worker
{

/// The WorkMgr category of the worker (AD-6): created by the Memory install step.
Parameter CATEGORY = "OcuTalon.Docs.Extractor";

Parameter MAXACTIVEWORKERS = 1;

Parameter DEFAULTWORKERS = 1;

Parameter STOPONTIMEOUT = 1;

/// The Python resource (src/ocutalon/python/ocutalon_extract.py).
Parameter RESOURCE = "ocutalon_extract";

ClassMethod Read(path As %String, limit As %Integer, maxUnpacked As %Integer, pageMarker As %String) As %Status
{
	Kill %result
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set answer = ##class(%SYS.Python).Import(..#RESOURCE).extract(path, limit, maxUnpacked, pageMarker)
		Set ok = ..Flag(answer.get("ok", 0))
		Set %result("ok") = ok
		If ok {
			Set %result("text") = answer.get("text", "")
			Set %result("cut") = ..Flag(answer.get("cut", 0))
			Set %result("markers") = answer.get("markers", "")
		} Else {
			Set %result("reason") = answer.get("reason", "")
			Set %result("detail") = answer.get("detail", "")
		}
		Set %result("job") = $Job
	} Catch exception {
		Kill %result
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// 1 for a Python true value as ObjectScript receives it (1 or the word True), else 0.
ClassMethod Flag(value) As %Boolean [ CodeMode = expression ]
{
(value = 1) || ($ZConvert(value, "L") = "true")
}

}
