/// The answer of OcuTalon.Web.Hook to a request that arrives before the application's role is in force (Story 35.3, AD-13): an OPTIONS request, which the web
/// server and CSP dispatch as a login. The status is 404 with no body and no Allow header, so the hook answers every method but POST alike (OnHandleOptionsRequest answers the same).
/// A request of that kind runs as a user with no roles, which can read OCUTALON_PUBLIC and not the code database, so the class that answers it lives in the
/// public package and references only %CSP and its own package (AD-3). OcuTalon.Web.Hook extends it and so inherits Login without its own routine being
/// read before the role applies.
Class OcuTalon.Web.Public.HookBase Extends %CSP.REST [ Abstract ]
{

/// A request that needs a login: 404, the status line only.
ClassMethod Login(skipheader As %Boolean = 1) As %Status
{
	Set %response.OutputSessionToken = 0
	Set %response.ContentType = ""
	Set %response.Status = ..#HTTP404NOTFOUND
	Quit %response.WriteHTTPHeader()
}

/// An OPTIONS request that reaches the dispatch (or the login, which asks the same): 404 with no body and no Allow header, whatever the path.
ClassMethod OnHandleOptionsRequest(url As %String) As %Status
{
	Set %response.ContentType = ""
	Set %response.Status = ..#HTTP404NOTFOUND
	Quit $SYSTEM.Status.OK()
}

}
