/// Tests of what the Docker image holds for the documents (Story 34.2; AD-21, AD-23): the three Python packages at their pins in IRIS's Python,
/// the embedding model in a root-owned read-only folder named by FASTEMBED_CACHE_DIR, each package's licence files, and the notices file.
/// It tests the image, so it runs only where the image's version file /opt/ocutalon/version exists (a throwaway stack or CI); on a developer
/// instance or a slot it records one named skip. The build's licence gate and the model's offline embed are measured by the Docker test
/// checks and by Task 0 (b) (evidence 34-2-task0-image.md).
///   - TestImage: FASTEMBED_CACHE_DIR is /opt/fastembed; the folder holds models--Qdrant--all-MiniLM-L6-v2-onnx with a model.onnx of more
///     than 80 MB; a file cannot be created in the folder or in the model's folder; importlib.metadata.version gives 0.9.0, 0.11.10 and 1.1.2;
///     the dist-info of each package lists a licence file that exists; /opt/ocutalon/THIRD-PARTY-NOTICES exists and the IRIS user cannot write it.
Class OcuTalon.Test.Web.DocumentsImage Extends %UnitTest.TestCase
{

Parameter VERSIONFILE = "/opt/ocutalon/version";

Parameter MODELDIR = "models--Qdrant--all-MiniLM-L6-v2-onnx";

Parameter NOTICES = "/opt/ocutalon/THIRD-PARTY-NOTICES";

/// The packages, each as distribution name | version | dist-info folder.
Parameter PACKAGES = "fastembed|0.9.0|fastembed-0.9.0.dist-info,pdfplumber|0.11.10|pdfplumber-0.11.10.dist-info,python-docx|1.1.2|python_docx-1.1.2.dist-info";

Method TestImage()
{
	If '##class(%File).Exists(..#VERSIONFILE) {
		Do $$$AssertSkipped("Not OcuTalon's image: "_..#VERSIONFILE_" does not exist on this instance (a slot or a developer instance)")
		Quit
	}
	Set folder = $SYSTEM.Util.GetEnviron("FASTEMBED_CACHE_DIR")
	Do $$$AssertEquals(folder, "/opt/fastembed", "FASTEMBED_CACHE_DIR names /opt/fastembed")
	Set model = ##class(%File).NormalizeDirectory(folder)_..#MODELDIR
	Do $$$AssertTrue(##class(%File).DirectoryExists(model), "the folder holds "_..#MODELDIR)
	Set glob = ##class(%SYS.Python).Import("glob")
	Set os = ##class(%SYS.Python).Import("os")
	Set found = glob.glob(model_"/snapshots/*/model.onnx")
	Do $$$AssertEquals(found."__len__"(), 1, "its snapshot holds one model.onnx")
	If found."__len__"() = 1 Do $$$AssertTrue(os.path.getsize(found."__getitem__"(0)) > 80000000, "which is more than 80 MB")
	For where = folder, model {
		Do $$$AssertEquals(..CanCreate(where), 0, "no file can be created in "_where)
	}
	Do $$$AssertEquals(..CanCreate(..#NOTICES), 0, "the notices file cannot be rewritten")
	Do $$$AssertTrue(##class(%File).Exists(..#NOTICES), ..#NOTICES_" exists")
	Set metadata = ##class(%SYS.Python).Import("importlib.metadata")
	Set site = ##class(%File).NormalizeDirectory($SYSTEM.Util.InstallDirectory())_"mgr/python/"
	Set packages = $ListFromString(..#PACKAGES, ",")
	Set position = 0
	While $ListNext(packages, position, package) {
		Set name = $Piece(package, "|", 1), info = site_$Piece(package, "|", 3)
		Do $$$AssertEquals(metadata.version(name), $Piece(package, "|", 2), name_" is installed at its pin")
		Do $$$AssertTrue(##class(%File).DirectoryExists(info), name_" has "_$Piece(package, "|", 3))
		Do $$$AssertTrue(..LicenceFile(info) '= "", name_" lists a licence file that exists: "_..LicenceFile(info))
	}
}

/// 1 when a file can be created at the path (a folder: a new file in it; a file: the file written), else 0. A file made here is removed.
ClassMethod CanCreate(path As %String) As %Boolean [ Private ]
{
	Set target = $Select(##class(%File).DirectoryExists(path): ##class(%File).NormalizeDirectory(path)_"zz-write-test", 1: path)
	Set existed = ##class(%File).Exists(target)
	Set created = 0
	Try {
		Open target:("AWN"):0
		If $Test {
			Set created = 1
			Close target
		}
	} Catch {
		Set created = 0
	}
	If 'existed && ##class(%File).Exists(target) Do ##class(%File).Delete(target)
	Quit created
}

/// The first file of the dist-info folder, or else of its licenses folder, whose name starts with LICENSE, LICENCE or COPYING and that exists;
/// "" when there is none.
ClassMethod LicenceFile(info As %String) As %String [ Private ]
{
	Set found = ..FirstIn(##class(%File).NormalizeDirectory(info))
	If found = "" Set found = ..FirstIn(##class(%File).NormalizeDirectory(info_"/licenses"))
	Quit found
}

/// The first file of the directory whose name starts with LICENSE, LICENCE or COPYING, else "".
ClassMethod FirstIn(directory As %String) As %String [ Private ]
{
	Set found = ""
	Set rs = ##class(%ResultSet).%New("%File:FileSet")
	Set sc = rs.Execute(directory, "*", , 0)
	If $SYSTEM.Status.IsError(sc) Quit ""
	While rs.Next() && (found = "") {
		If (rs.Get("Type") = "F") && $Match($ZConvert(##class(%File).GetFilename(rs.Get("Name")), "U"), "(LICENSE|LICENCE|COPYING).*") && ##class(%File).Exists(rs.Get("Name")) {
			Set found = rs.Get("Name")
		}
	}
	Quit found
}

}
