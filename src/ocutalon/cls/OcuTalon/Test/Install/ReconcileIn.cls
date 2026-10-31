/// Tests of OcuTalon.Install.ReconcileIn (Story 15.2; AD-5, AD-23). The decision of one poll is a pure class method, so nothing here
/// starts a production or reconciles.
///   - TestNext: a start made by the Production step is skipped, and so is a reconcile that ran; items that do not run give "wait" until
///     WAITWARNSECONDS have passed, then one "warn" and "wait" again; no missing item gives "run".
Class OcuTalon.Test.Install.ReconcileIn Extends %UnitTest.TestCase
{

Method TestNext()
{
	Set item = "OcuTalon.Install.ReconcileIn"
	Set limit = $Parameter(item, "WAITWARNSECONDS")
	Do $$$AssertEquals(limit, 60, "the warning comes after 60 s")

	Do $$$AssertEquals($ClassMethod(item, "Next", 1, 0, "", 0, 0), "skip", "a start made by the Production step is skipped")
	Do $$$AssertEquals($ClassMethod(item, "Next", 1, 0, "Decide", 500, 0), "skip", "also with items missing, however long it waited")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 1, "", 0, 0), "skip", "a reconcile that ran is not repeated")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 1, "Decide", 500, 1), "skip", "also with items missing")

	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "Decide", 0, 0), "wait", "an item that does not run gives wait")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "Decide,Checks", limit - 1, 0), "wait", "also just under the limit")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "OcuTalon.Production is not running", 5, 0), "wait", "and a production that does not run")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "Decide", limit, 0), "warn", "at the limit the first poll warns")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "Decide", limit + 30, 0), "warn", "and so does any later poll before the warning was logged")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "Decide", limit + 30, 1), "wait", "after the warning it waits again")

	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "", 0, 0), "run", "nothing missing gives run")
	Do $$$AssertEquals($ClassMethod(item, "Next", 0, 0, "", limit + 30, 1), "run", "also after a warning")
}

}
