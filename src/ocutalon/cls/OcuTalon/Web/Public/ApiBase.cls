/// The answer of OcuTalon.Web.Api to a request without a session (AD-13): 401 signed_out, as the API's error body,
/// with no WWW-Authenticate header, so that no browser opens its own password prompt.
/// A request without a session runs as a user with no roles, which can read OCUTALON_PUBLIC and not the code
/// database, so the class that answers it lives in the public package and references only %CSP, dynamic objects
/// and its own package (AD-3). OcuTalon.Web.Api extends it and so inherits Login without its own routine being
/// read before sign-in.
Class OcuTalon.Web.Public.ApiBase Extends %CSP.REST [ Abstract ]
{

Parameter CONTENTTYPE = "application/json";

Parameter CHARSET = "utf-8";

Parameter MESSAGESIGNEDOUT = "You were signed out. Sign in again to continue.";

/// A request without a session: 401 signed_out, with no WWW-Authenticate header.
ClassMethod Login(skipheader As %Boolean = 1) As %Status
{
	Set %response.OutputSessionToken = 0
	Set %response.CharSet = ..#CHARSET
	Set %response.ContentType = ..#CONTENTTYPE
	Set %response.Status = ..#HTTP401UNAUTHORIZED
	Set sc = %response.WriteHTTPHeader()
	If $SYSTEM.Status.IsError(sc) Quit sc
	Write {"error": {"code": "signed_out", "message": (..#MESSAGESIGNEDOUT)}}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

}
