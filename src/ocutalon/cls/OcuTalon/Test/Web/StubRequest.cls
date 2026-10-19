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

}
