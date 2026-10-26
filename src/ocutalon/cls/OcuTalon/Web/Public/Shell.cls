/// The dispatch class of the application /ocutalon (AD-13): sign-in, the user-role check and the built Angular
/// files, in one class, because on build 154 a password-only application that serves built files answers
/// 404 before sign-in, and a dispatched application never shows its LoginPage.
///   - A request without a session reaches Login(): one of the five sign-in images is streamed, and anything else
///     is answered with the sign-in page (OcuTalon.Web.Public.Login). No other file is served.
///   - A signed-in request is first checked for the role OcuTalonUser: without it the CSP session ends and the
///     sign-in page shows the no-role message. With it, GET serves the files of the application's Path, and
///     only those, through %CSP.StreamServer, index.html with its own Content-Security-Policy and no caching.
///   - On the online demo the sign-in hook (OcuTalon.Web.SessionEvents) may record a refusal in the CSP session, under REFUSALKEY, as
///     $ListBuild(state, until). A signed-in request that finds it ends the CSP session at once, as the no-role request does, and
///     is answered with the sign-in page in that state (Login.Show, the splash's field error for "addressLimit").
///   - The POST that signs in is answered with a redirect to the same URL and query, so the page that was asked
///     for is the page that loads.
/// The class lives in OCUTALON_PUBLIC and references only %CSP and its own package (AD-3).
Class OcuTalon.Web.Public.Shell Extends %CSP.REST
{

Parameter UseSession = 1;

Parameter CONTENTTYPE = "text/html";

/// The role that opens the application after sign-in.
Parameter ROLE = "OcuTalonUser";

/// The key of the CSP session's data that holds a sign-in refusal, $ListBuild(state, until): the sign-in hook writes it and
/// OnPreDispatch reads it, so the key lives in this public class, which the hook may name (AD-3).
Parameter REFUSALKEY = "OcuTalon.Refused";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/" Method="GET" Call="Index"/>
<Route Url="/(.*)" Method="GET" Call="File"/>
<Route Url="/(.*)" Method="POST" Call="Redirect"/>
</Routes>
}

/// Every request is dispatched: the role check is OnPreDispatch's. The default check needs Read on the data
/// database, which a user without the role does not hold.
ClassMethod AccessCheck(Output authorized As %Boolean = 0) As %Status
{
	Set authorized = 1
	Quit $SYSTEM.Status.OK()
}

/// A request without a session: a sign-in image, or the sign-in page.
ClassMethod Login(skipheader As %Boolean = 1) As %Status
{
	If ##class(OcuTalon.Web.Public.Login).IsSignInImage(..RelativePath()) {
		Set %request.Data("FILE", 1) = %request.URL
		Set served = ##class(%CSP.StreamServer).OnPreHTTP()
		Set sc = %response.WriteHTTPHeader()
		If $SYSTEM.Status.IsError(sc) Quit sc
		If served Quit ##class(%CSP.StreamServer).OnPage()
		Quit $SYSTEM.Status.OK()
	}
	Quit ##class(OcuTalon.Web.Public.Login).Show("")
}

/// A signed-in request without the role ends the session and gets the no-role sign-in page. With the role, a refusal that the
/// sign-in hook recorded ends the session the same way and gets the sign-in page in the refusal's state, with its time.
ClassMethod OnPreDispatch(url As %String, method As %String, ByRef continue As %Boolean) As %Status
{
	If ..HasRole() {
		Set marker = $Get(%session.Data(..#REFUSALKEY))
		If marker = "" Quit $SYSTEM.Status.OK()
		Set continue = 0
		Do %session.Logout(1)
		Set %session.EndSession = 1
		Set %request.Data("Error:FullURL", 1) = ..FullUrl()
		Quit ##class(OcuTalon.Web.Public.Login).Show($List(marker, 1), 0, $ListGet(marker, 2))
	}
	Set continue = 0
	Do %session.Logout(1)
	Set %session.EndSession = 1
	Set %request.Data("Error:FullURL", 1) = ..FullUrl()
	Quit ##class(OcuTalon.Web.Public.Login).Show("norole", 0)
}

/// GET /
ClassMethod Index() As %Status
{
	Quit ..Serve("index.html")
}

/// GET /<path>
ClassMethod File(path As %String) As %Status
{
	Quit ..Serve(path)
}

/// POST /<path>: the sign-in form's target, answered with a redirect to the page that was asked for.
ClassMethod Redirect(path As %String) As %Status
{
	Set %response.Status = "303 See Other"
	Do %response.SetHeader("Location", ..FullUrl())
	Quit $SYSTEM.Status.OK()
}

/// Streams one file of the application's Path. index.html gets the page policy (script-src 'self') and
/// Cache-Control: no-cache; a missing file, a directory and a path that leaves the folder answer 404. A name
/// that the folder lacks is not served from IRIS's /csp/broker/ either, where the stream server looks next.
ClassMethod Serve(path As %String) As %Status
{
	If (path [ "..") || ($Extract(path) = "/") || (path [ "\") {
		Set %response.Status = ..#HTTP404NOTFOUND
		Quit $SYSTEM.Status.OK()
	}
	Set %request.Data("FILE", 1) = %request.Application_path
	If '##class(%CSP.StreamServer).OnPreHTTP() {
		If %response.Status '= ..#HTTP304NOTMODIFIED Set %response.Status = ..#HTTP404NOTFOUND
		Quit $SYSTEM.Status.OK()
	}
	If $ZConvert($Translate(%stream.Filename, "\", "/"), "L") [ "/csp/broker/" {
		Set %stream = ""
		Set %response.Status = ..#HTTP404NOTFOUND
		Set %response.ContentType = ..#CONTENTTYPE
		Quit $SYSTEM.Status.OK()
	}
	If path = "index.html" {
		Do %response.SetHeader("Content-Security-Policy", "script-src 'self'")
		Do %response.SetHeader("Cache-Control", "no-cache")
		Set %response.Expires = -1
	}
	Quit ##class(%CSP.StreamServer).OnPage()
}

/// 1 when the signed-in user holds the OcuTalon user role.
ClassMethod HasRole() As %Boolean
{
	Quit (","_$Roles_",") [ (","_..#ROLE_",")
}

/// The path of the request below the application, "" for the application itself.
ClassMethod RelativePath() As %String [ Private ]
{
	Quit $Extract(%request.URL, $Length(%request.Application) + 1, *)
}

/// The request's URL with its query string, on one line.
ClassMethod FullUrl() As %String [ Private ]
{
	Set query = $Get(%request.CgiEnvs("QUERY_STRING"))
	Quit $Translate(%request.URL_$Select(query '= "": "?"_query, 1: ""), $Char(13, 10))
}

}
