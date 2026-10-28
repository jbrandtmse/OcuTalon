/// A session event class for the tests that records OnLogout in the process-private global ^||OcuTalonLogoutProbe, so a
/// test can see that a stand-in CSP session was logged out. The product never refers to it.
Class OcuTalon.Test.Web.LogoutProbe Extends %CSP.SessionEvents [ ProcedureBlock ]
{

ClassMethod OnLogout() As %Status
{
	Set ^||OcuTalonLogoutProbe = $Get(^||OcuTalonLogoutProbe) + 1
	Quit $SYSTEM.Status.OK()
}

}
