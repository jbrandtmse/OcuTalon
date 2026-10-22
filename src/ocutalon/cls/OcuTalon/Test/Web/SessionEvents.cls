/// Tests of the session events of /ocutalon (Story 2.2; AD-4): the sign-in attaches the user's durable session when the
/// user holds the role, does nothing without it, and answers OK even when the attach fails, because an error status from
/// OnLogin neither logs the user out nor shows the sign-in page. The role is passed to AttachFor, which OnLogin calls with
/// Shell.HasRole(). The session row that the test may create for the running user is removed by Test.Data.Fixture.Clean.
Class OcuTalon.Test.Web.SessionEvents Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

/// A failed attach (no CSP session) still answers OK and creates no row; without the role nothing is attached or
/// created; with the role the user's durable session is recorded in the CSP session.
Method TestAttachForAlwaysAnswersOK()
{
	New %session
	Set before = ..Count()
	Set %session = ""
	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(1), "a failed attach still answers OK")
	Do $$$AssertEquals(..Count(), before, "and creates no session row")

	Set %session = ##class(%CSP.Session).%New("ZzSessionEvents", 0)
	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(0), "without the role it answers OK")
	Do $$$AssertEquals($Get(%session.Data("OcuTalon.SessionRef")), "", "attaches nothing")
	Do $$$AssertEquals(..Count(), before, "and creates no session row")

	Do $$$AssertStatusOK(##class(OcuTalon.Web.SessionEvents).AttachFor(1), "with the role it answers OK")
	Set ref = $Get(%session.Data("OcuTalon.SessionRef"))
	Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Do $$$AssertTrue($IsObject(row), "and the user's durable session is recorded in the CSP session")
	If $IsObject(row) {
		Do $$$AssertEquals($ZConvert(row.IrisUser, "U"), $ZConvert($Username, "U"), "it is the signed-in user's")
		If before = 0 Do ##class(OcuTalon.Test.Data.Fixture).Adopt(row)
	}
	Do $$$AssertEquals(..Count(), $Select(before = 0: 1, 1: before), "one row for the user")
}

/// The session rows of the running IRIS user, matched without regard to case.
ClassMethod Count() As %Integer [ Private ]
{
	Set statement = ##class(%SQL.Statement).%New()
	Set sc = statement.%Prepare("SELECT COUNT(*) FROM OcuTalon_Data.Session WHERE IrisUser = ?")
	Set result = statement.%Execute($Username)
	Do result.%Next()
	Quit result.%GetData(1)
}

}
