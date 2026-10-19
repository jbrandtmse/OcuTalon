/// The Web step: OcuTalon's four web applications and the trace role (AD-13, AD-24). The first three share one
/// sign-in group.
///   - /ocutalon: dispatched by OcuTalon.Web.Public.Shell, password authentication, serving the built Angular
///     files from the durable csp/ocutalon-web/ folder;
///   - /ocutalon/api: OcuTalon.Web.Api, the REST surface;
///   - /ocutalon/trace/ocutalon: the Visual Trace portal pages of OCUTALON, restricted to AD-24's seven classes;
///   - /ocutalon/public: OcuTalon.Web.Public.Status, unauthenticated and outside the sign-in group.
/// The applications are structural (AD-19): every start rewrites each one to exactly these properties, with
/// Modify, never delete and create, so nothing attached to an application is lost. The OCUORDERS trace
/// application is the Demo step's, built from TraceApp, and exists only with demo mode on.
/// The bundle lives in csp/ocutalon-web/, not in csp/ocutalon/, which the non-Health image's default application
/// /csp/ocutalon serves without sign-in (DW-5); every start removes OcuTalon's own files from the old folder.
Class OcuTalon.Install.Step.Web Extends OcuTalon.Install.Step
{

/// The role of the trace applications' users (AD-24).
Parameter TRACEROLE = "OcuTalonTraceViewer";

/// The sign-in group that /ocutalon, /ocutalon/api and the trace applications share (AD-13).
Parameter GROUP = "OcuTalon";

/// The classes that a trace application may serve: S7's seven. Nothing else of the portal is reachable.
Parameter PERMITTED = "1(1""%CSP.Broker"",1""EnsPortal.VisualTrace"",1""EnsPortal.SVG.VisualTrace"",1""EnsPortal.VisualTraceLegend"",1""EnsPortal.SVG.TraceLegend"",1""EnsPortal.MessageContents"",1""EnsPortal.MessageViewer"")";

/// The durable folder that holds the built Angular files, below the data directory.
Parameter BUNDLEFOLDER = "csp/ocutalon-web/";

/// The default application's folder below the data directory, which the non-Health image's /csp/ocutalon serves
/// without sign-in: OcuTalon's own files are removed from it, and nothing else is.
Parameter OLDBUNDLEFOLDER = "csp/ocutalon/";

/// The roles that /ocutalon and /ocutalon/api grant to every signed-in user, in MatchRoles form. They are the
/// merge file's roles of the code, data and private databases, so OcuTalonUser holds no database resource itself.
Parameter APPLICATIONROLES = ":%DB_OCUTALON_CODE:%DB_OCUTALON_DATA:%DB_OCUTALON_PRIVATE";

/// The text that marks an index.html as OcuTalon's.
Parameter OCUTALONMARKER = "<base href=""/ocutalon/"">";

/// The top-level files of a bundle that carry a content hash.
Parameter STALEFILES = "^(main|chunk|polyfills|styles)-[A-Za-z0-9]+\.(js|css)(\.map)?$";

/// The application's name, in lower case, is appended to this for each trace application.
Parameter TRACEPREFIX = "/ocutalon/trace/";

/// The step: refuses a missing bundle, removes OcuTalon's files from the old bundle folder, writes the four
/// applications, then grants the trace role its SQL privilege in this namespace.
ClassMethod Run() As %Status
{
	Set sc = ..Prepare($SYSTEM.Util.DataDirectory())
	If $SYSTEM.Status.IsError(sc) Quit sc
	Do ..Definitions(.apps)
	Set name = ""
	For {
		Set name = $Order(apps(name))
		Quit:name=""
		Kill props
		Merge props = apps(name)
		Set sc = ..Apply(name, .props)
		If $SYSTEM.Status.IsError(sc) Quit
	}
	If $SYSTEM.Status.IsError(sc) Quit sc
	Quit ..GrantTraceSql()
}

/// The step's work on the files of a data directory: the new bundle folder must hold index.html, and then the
/// old bundle folder loses OcuTalon's files.
ClassMethod Prepare(dataDirectory As %String) As %Status
{
	Set dataDirectory = ##class(%File).NormalizeDirectory(dataDirectory)
	Set sc = ..BundleCheck(dataDirectory_..#BUNDLEFOLDER)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Quit ..RemoveOldBundle(dataDirectory_..#OLDBUNDLEFOLDER, dataDirectory_..#BUNDLEFOLDER)
}

/// The trace role holds exactly: Use on %Ens_Portal, %Ens_MessageTrace, %Ens_MessageHeader and
/// %Ens_MessageContent, and Read on the OCUTALON data and code databases, never the private database. Its SQL
/// SELECT on Ens.MessageHeader is GrantTraceSql's. The OCUORDERS grants are the Demo step's.
ClassMethod Grants() As %DynamicArray
{
	Quit [{"role":"OcuTalonTraceViewer","resource":"%Ens_Portal","permission":"U"},{"role":"OcuTalonTraceViewer","resource":"%Ens_MessageTrace","permission":"U"},{"role":"OcuTalonTraceViewer","resource":"%Ens_MessageHeader","permission":"U"},{"role":"OcuTalonTraceViewer","resource":"%Ens_MessageContent","permission":"U"},{"role":"OcuTalonTraceViewer","resource":"%DB_OCUTALON_DATA","permission":"R"},{"role":"OcuTalonTraceViewer","resource":"%DB_OCUTALON_CODE","permission":"R"}]
}

/// apps(name, key) = the value, for each application of this step, with every key that Security.Applications
/// is given (Modify keeps a key that is not passed, so all of them are passed). The CORS allow-list is passed
/// empty, so a list added by hand is removed at the next start.
/// CSPZENEnabled is 1 for all four: with it off, build 154 does not reach the dispatch class of a signed-in
/// request, and answers an empty page or a 404.
ClassMethod Definitions(Output apps) As %Status
{
	Kill apps
	Do ..Common(.shell, "OCUTALON", "/ocutalon/")
	Set shell("DispatchClass") = "OcuTalon.Web.Public.Shell"
	Set shell("Path") = $SYSTEM.Util.DataDirectory()_..#BUNDLEFOLDER
	Set shell("ServeFiles") = 3
	Set shell("MatchRoles") = ..#APPLICATIONROLES
	Set shell("PermittedClasses") = ""
	Set shell("CSPZENEnabled") = 1
	Merge apps("/ocutalon") = shell

	Do ..Common(.api, "OCUTALON", "/ocutalon/")
	Set api("DispatchClass") = "OcuTalon.Web.Api"
	Set api("Path") = ""
	Set api("ServeFiles") = 0
	Set api("MatchRoles") = ..#APPLICATIONROLES
	Set api("PermittedClasses") = ""
	Set api("CSPZENEnabled") = 1
	Merge apps("/ocutalon/api") = api

	Set name = ..TraceApp("OCUTALON", .trace)
	Merge apps(name) = trace

	Do ..Common(.public, "OCUTALON", "/ocutalon/public/")
	Set public("AutheEnabled") = 64
	Set public("GroupById") = ""
	Set public("DispatchClass") = "OcuTalon.Web.Public.Status"
	Set public("Path") = ""
	Set public("ServeFiles") = 0
	Set public("MatchRoles") = ""
	Set public("PermittedClasses") = ""
	Set public("CSPZENEnabled") = 1
	Merge apps("/ocutalon/public") = public
	Quit $SYSTEM.Status.OK()
}

/// The trace application of a namespace: its name, /ocutalon/trace/<namespace in lower case>, and props with
/// the properties of AD-24 and S7. It has no application roles and no dispatch class, serves the ZEN pages,
/// and is in the same sign-in group as the other applications. The Demo step builds the OCUORDERS one from it.
ClassMethod TraceApp(namespace As %String, Output props) As %String
{
	Kill props
	Set name = ..#TRACEPREFIX_$ZConvert(namespace, "L")
	Do ..Common(.props, namespace, name_"/")
	Set props("DispatchClass") = ""
	Set props("Path") = ""
	Set props("ServeFiles") = 1
	Set props("MatchRoles") = ""
	Set props("PermittedClasses") = ..#PERMITTED
	Set props("CSPZENEnabled") = 1
	Quit name
}

/// The properties that the applications share.
ClassMethod Common(Output props, namespace As %String, cookiePath As %String) [ Private ]
{
	Kill props
	Set props("NameSpace") = namespace
	Set props("Enabled") = 1
	Set props("AutheEnabled") = 32
	Set props("GroupById") = ..#GROUP
	Set props("SessionScope") = 2
	Set props("Timeout") = 28800
	Set props("CookiePath") = cookiePath
	Set props("LoginPage") = ""
	Set props("InbndWebServicesEnabled") = 0
	Set props("IsNameSpaceDefault") = 0
	Set props("AutoCompile") = 0
	Set props("CorsAllowlist") = ""
}

/// Creates the application, or modifies the one that exists, to hold props. Runs in %SYS.
ClassMethod Apply(name As %String, ByRef props) As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Applications).Exists(name) {
		Quit ##class(Security.Applications).Modify(name, .props)
	}
	Quit ##class(Security.Applications).Create(name, .props)
}

/// The bundle folder must hold index.html: otherwise the error names the path that is missing.
ClassMethod BundleCheck(dir As %String) As %Status
{
	Set index = ##class(%File).NormalizeDirectory(dir)_"index.html"
	If '##class(%File).Exists(index) {
		Quit $SYSTEM.Status.Error(5001, "The web bundle is missing: "_index_" does not exist; build the image from a tree where npm --prefix web run build has run")
	}
	Quit $SYSTEM.Status.OK()
}

/// Removes OcuTalon's own files from the old bundle folder, only when its index.html is OcuTalon's (it holds
/// <base href="/ocutalon/">). It deletes index.html, 3rdpartylicenses.txt, the top-level scripts and stylesheets
/// named main-, chunk-, polyfills- and styles-<hash>, and each file under assets/ whose relative path is also in
/// newDir, then each folder left empty. It never deletes oldDir itself or any other file. A missing folder, or an
/// index.html that isn't OcuTalon's, removes nothing. A file that can't be deleted gives an error status that
/// names it. index.html goes last: it is the marker, so a run that stopped early is repeated by the next start.
ClassMethod RemoveOldBundle(oldDir As %String, newDir As %String) As %Status
{
	Set oldDir = ##class(%File).NormalizeDirectory(oldDir)
	Set newDir = ##class(%File).NormalizeDirectory(newDir)
	Set index = oldDir_"index.html"
	If '##class(%File).Exists(index) Quit $SYSTEM.Status.OK()
	Set stream = ##class(%Stream.FileBinary).%New()
	Set sc = stream.LinkToFile(index)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set head = stream.Read(32000)
	Kill stream
	If head '[ ..#OCUTALONMARKER Quit $SYSTEM.Status.OK()

	Set sc = $SYSTEM.Status.OK()
	Set licenses = oldDir_"3rdpartylicenses.txt"
	If ##class(%File).Exists(licenses) Set sc = ..DeleteFile(licenses)
	If $SYSTEM.Status.IsOK(sc) {
		Set sc = ..Entries(oldDir, 0, .files)
		Set i = ""
		For {
			Set i = $Order(files(i), 1, entry)
			Quit:i=""
			If $SYSTEM.Status.IsError(sc) Quit
			If $Match(##class(%File).GetFilename($List(entry, 1)), ..#STALEFILES) Set sc = ..DeleteFile($List(entry, 1))
		}
	}
	If $SYSTEM.Status.IsOK(sc), ##class(%File).DirectoryExists(oldDir_"assets") {
		Set sc = ..RemoveAssets(oldDir_"assets", newDir_"assets")
	}
	If $SYSTEM.Status.IsOK(sc) Set sc = ..DeleteFile(index)
	Quit sc
}

/// Deletes each file of oldAssets whose relative path is also in newAssets, and each folder that is empty after
/// that, oldAssets included.
ClassMethod RemoveAssets(oldAssets As %String, newAssets As %String) As %Status [ Private ]
{
	Set oldAssets = ##class(%File).NormalizeDirectory(oldAssets)
	Set newAssets = ##class(%File).NormalizeDirectory(newAssets)
	Set sc = ..Entries(oldAssets, 1, .entries)
	Set i = ""
	For {
		Set i = $Order(entries(i), 1, entry)
		Quit:i=""
		If $SYSTEM.Status.IsError(sc) Quit
		Set path = $List(entry, 1)
		Set name = ##class(%File).GetFilename(path)
		If $List(entry, 2) = "D" {
			Set sc = ..RemoveAssets(path, newAssets_name)
		} ElseIf ##class(%File).Exists(newAssets_name) {
			Set sc = ..DeleteFile(path)
		}
	}
	If $SYSTEM.Status.IsOK(sc) {
		Kill entries
		Set sc = ..Entries(oldAssets, 1, .entries)
		If $SYSTEM.Status.IsOK(sc), '$Data(entries), '##class(%File).RemoveDirectory(oldAssets) {
			Set sc = $SYSTEM.Status.Error(5001, "The old bundle folder "_oldAssets_" could not be removed")
		}
	}
	Quit sc
}

/// entries(n) = $ListBuild(full path, type) for the files of a folder, and its folders when includeDirs is 1,
/// read in full before the caller changes the folder.
ClassMethod Entries(dir As %String, includeDirs As %Boolean, Output entries) As %Status [ Private ]
{
	Kill entries
	Set rows = ##class(%ResultSet).%New("%File:FileSet")
	Set sc = rows.Execute(dir, "*", "Name", includeDirs)
	Set count = 0
	While $SYSTEM.Status.IsOK(sc) && rows.Next() {
		Set count = count + 1
		Set entries(count) = $ListBuild(rows.Get("Name"), rows.Get("Type"))
	}
	Quit sc
}

/// Deletes one file, or gives an error status that names it.
ClassMethod DeleteFile(file As %String) As %Status [ Private ]
{
	If '##class(%File).Delete(file) Quit $SYSTEM.Status.Error(5001, "The old bundle file "_file_" could not be deleted")
	Quit $SYSTEM.Status.OK()
}

/// Grants the trace role SQL SELECT on Ens.MessageHeader in the current namespace, which the Contents tab of
/// the message viewer needs (S7). Does nothing when the role already holds it.
ClassMethod GrantTraceSql(role As %String = {..#TRACEROLE}) As %Status
{
	If $SYSTEM.SQL.Security.CheckPrivilege(role, 1, "Ens.MessageHeader", "s") = 1 Quit $SYSTEM.Status.OK()
	Quit $SYSTEM.SQL.Security.GrantPrivilege("SELECT", "Ens.MessageHeader", "TABLE", role)
}

}
