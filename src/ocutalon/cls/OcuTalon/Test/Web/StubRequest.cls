/// A request object for tests that call a dispatch class directly. %CSP.Request keeps the setter of its
/// Application property private to the CSP server and its subclasses, so a test cannot name the web application
/// a request belongs to; this subclass can.
Class OcuTalon.Test.Web.StubRequest Extends %CSP.Request
{

/// A request that belongs to the web application whose name (with its closing slash) is application.
ClassMethod Make(application As %String) As OcuTalon.Test.Web.StubRequest
{
	Set request = ..%New()
	Set request.Application = application
	Quit request
}

/// A request with the parts that the API's browser-envelope check reads: the method, the Content-Type, the values
/// of the X-OcuTalon-Request, Origin and Host headers (empty means the header is absent), and whether the
/// connection is HTTPS. ContentType and Secure have setters that only this subclass may call.
ClassMethod MakeCall(application As %String, method As %String, contentType As %String = "", header As %String = "", origin As %String = "", host As %String = "", secure As %Boolean = 0) As OcuTalon.Test.Web.StubRequest
{
	Set request = ..Make(application)
	Set request.Method = method
	Set request.ContentType = contentType
	Set request.Secure = secure
	If header '= "" Set request.CgiEnvs("HTTP_X_OCUTALON_REQUEST") = header
	If origin '= "" Set request.CgiEnvs("HTTP_ORIGIN") = origin
	If host '= "" Set request.CgiEnvs("HTTP_HOST") = host
	Quit request
}

}
