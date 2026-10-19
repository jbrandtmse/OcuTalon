/// The Web step: OcuTalon's three web applications, in one sign-in group, and the trace role (AD-13, AD-24).
///   - /ocutalon: dispatched by OcuTalon.Web.Public.Shell, password authentication, serving the built Angular
///     files from the durable csp/ocutalon/ folder;
///   - /ocutalon/api: OcuTalon.Web.Api, the REST surface;
///   - /ocutalon/trace/ocutalon: the Visual Trace portal pages of OCUTALON, restricted to AD-24's seven classes.
/// The applications are structural (AD-19): every start rewrites each one to exactly these properties, with
/// Modify, never delete and create, so nothing attached to an application is lost. The OCUORDERS trace
/// application is the Demo step's, built from TraceApp, and exists only with demo mode on.
Class OcuTalon.Install.Step.Web Extends OcuTalon.Install.Step
{

/// The role of the trace applications' users (AD-24).
Parameter TRACEROLE = "OcuTalonTraceViewer";

/// The sign-in group that /ocutalon, /ocutalon/api and the trace applications share (AD-13).
Parameter GROUP = "OcuTalon";

/// The classes that a trace application may serve: S7's seven. Nothing else of the portal is reachable.
Parameter PERMITTED = "1(1""%CSP.Broker"",1""EnsPortal.VisualTrace"",1""EnsPortal.SVG.VisualTrace"",1""EnsPortal.VisualTraceLegend"",1""EnsPortal.SVG.TraceLegend"",1""EnsPortal.MessageContents"",1""EnsPortal.MessageViewer"")";

/// The roles that /ocutalon and /ocutalon/api grant to every signed-in user, in MatchRoles form. They are the
/// merge file's roles of the code, data and private databases, so OcuTalonUser holds no database resource itself.
Parameter APPLICATIONROLES = ":%DB_OCUTALON_CODE:%DB_OCUTALON_DATA:%DB_OCUTALON_PRIVATE";

/// The application's name, in lower case, is appended to this for each trace application.
Parameter TRACEPREFIX = "/ocutalon/trace/";

/// The step: refuses a missing bundle, writes the three applications, then grants the trace role its SQL
/// privilege in this namespace.
ClassMethod Run() As %Status
{
	Set sc = ..BundleCheck($SYSTEM.Util.DataDirectory()_"csp/ocutalon/")
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
/// CSPZENEnabled is 1 for all three: with it off, build 154 does not reach the dispatch class of a signed-in
/// request, and answers an empty page or a 404.
ClassMethod Definitions(Output apps) As %Status
{
	Kill apps
	Do ..Common(.shell, "OCUTALON", "/ocutalon/")
	Set shell("DispatchClass") = "OcuTalon.Web.Public.Shell"
	Set shell("Path") = $SYSTEM.Util.DataDirectory()_"csp/ocutalon/"
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

/// The properties that the three applications share.
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

/// Grants the trace role SQL SELECT on Ens.MessageHeader in the current namespace, which the Contents tab of
/// the message viewer needs (S7). Does nothing when the role already holds it.
ClassMethod GrantTraceSql(role As %String = {..#TRACEROLE}) As %Status
{
	If $SYSTEM.SQL.Security.CheckPrivilege(role, 1, "Ens.MessageHeader", "s") = 1 Quit $SYSTEM.Status.OK()
	Quit $SYSTEM.SQL.Security.GrantPrivilege("SELECT", "Ens.MessageHeader", "TABLE", role)
}

}
