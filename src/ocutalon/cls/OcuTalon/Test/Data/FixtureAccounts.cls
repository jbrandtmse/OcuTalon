/// Tests of the real IRIS accounts that Test.Data.Fixture makes (Story 0.38; ChatSession, SetAccount, GiveRole and Clean): an orphaned account that a test leaves behind is a security smell,
/// so the accounts are recorded under ^OcuTalonTest("Fixture", "users", <name>) BEFORE they are made and Clean drops them on every path, a test that fails included. Safe on a slot: it makes and removes
/// only its own accounts (ZzFxa...) and its own role (ZzFxaRole). No role is ever given to an account that the fixture did not make.
///   - TestChatSessionMakesARealAccount: the account exists with the roles asked for, the session row names it, Core.Access reads it (may chat for OcuTalonUser, not for a viewer), it is recorded with the session's
///     Ref, and Clean(Ref) drops the account, the row and the record;
///   - TestFailedTestLeavesNoAccount: a test body that makes sessions and then fails (an exception, as a test method that errors) is cleaned by the one call that a class makes in its teardown, and neither
///     account is left; an account whose session row could not be saved (a Ref that is taken: the account was already made) is recorded with no Ref and every Clean drops it;
///   - TestCleanOnlyTakesItsOwnRefs: Clean(Refs) drops the accounts of those sessions and leaves the account of another session, which a later Clean drops;
///   - TestCleanDropsAccountOfADeletedRow: an account whose session row was deleted first is still dropped;
///   - TestRolesTheFixtureMadeAreDropped: a role that the instance did not have is made for the account and removed with the last account, and a role that the instance had stays.
Class OcuTalon.Test.Data.FixtureAccounts Extends %UnitTest.TestCase
{

/// The first characters of the names of the accounts that the tests make.
Parameter NAME = "ZzFxa";

/// A role that the instance does not have, made and removed by the fixture.
Parameter ROLE = "ZzFxaRole";

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

Method TestChatSessionMakesARealAccount()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ref = $ClassMethod(fixture, "ChatSession", ..#NAME_"real", "OcuTalonUser", .user)
	Do $$$AssertTrue($ClassMethod(fixture, "AccountExists", user), "the account "_user_" exists")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(ref).IrisUser, user, "the session row names it")
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).RolesOf(user, .roles) && (roles = "OcuTalonUser"), "it holds the role OcuTalonUser")
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(user), 1, "and Core.Access lets it chat")
	Do $$$AssertEquals($Get(^OcuTalonTest("Fixture", "users", user)), ref, "it is recorded with the session's Ref")
	Set viewerRef = $ClassMethod(fixture, "ChatSession", ..#NAME_"viewer", "OcuTalonViewer", .viewer)
	Do $$$AssertEquals(##class(OcuTalon.Core.Access).MayChat(viewer), 0, "an account that holds the viewer role may not")
	Do $ClassMethod(fixture, "Clean", ref)
	Do $$$AssertEquals($ClassMethod(fixture, "AccountExists", user), 0, "Clean drops the account")
	Do $$$AssertEquals($Data(^OcuTalonTest("Fixture", "users", user)), 0, "and its record")
	Do $$$AssertEquals($IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(ref)), 0, "and its session row")
	Do $$$AssertEquals($ClassMethod(fixture, "AccountExists", viewer), 1, "while the other session's account stays until its own Clean")
	Do $ClassMethod(fixture, "Clean", viewerRef)
	Do $$$AssertEquals($ClassMethod(fixture, "AccountExists", viewer), 0, "and goes with it")
}

Method TestFailedTestLeavesNoAccount()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set refs = ""
	Set failed = 0
	Try {
		Set first = $ClassMethod(fixture, "ChatSession", ..#NAME_"failone", "OcuTalonUser", .one)
		Set refs = first
		Set second = $ClassMethod(fixture, "ChatSession", ..#NAME_"failtwo", "OcuTalonUser", .two)
		Set refs = refs_","_second
		Throw ##class(%Exception.General).%New("zz the test failed after it made its sessions", 5001, , "zz the test failed")
	} Catch exception {
		Set failed = 1
	}
	Do $$$AssertEquals(failed, 1, "the simulated test failed after it made two sessions with two accounts")
	Do $$$AssertEquals($ClassMethod(fixture, "AccountExists", one)_$ClassMethod(fixture, "AccountExists", two), "11", "both accounts exist at that moment")
	Do $ClassMethod(fixture, "Clean", refs)
	Do $$$AssertEquals($ClassMethod(fixture, "AccountExists", one)_$ClassMethod(fixture, "AccountExists", two), "00", "the clean-up of the class's teardown leaves neither account behind")
	Do $$$AssertEquals($ClassMethod(fixture, "Accounts"), "", "and nothing is left recorded")
	// A session row that cannot be saved (its Ref is taken) after the account was made: the account is recorded with no Ref, so that any Clean drops it.
	Set taken = $ClassMethod(fixture, "ChatSession", ..#NAME_"taken", "OcuTalonUser", .holder)
	Set thrown = 0
	Try {
		Do $ClassMethod(fixture, "ChatSession", ..#NAME_"dup", "OcuTalonUser", .orphan, taken)
	} Catch exception {
		Set thrown = 1
	}
	Do $$$AssertEquals(thrown, 1, "a ChatSession whose session row cannot be saved throws")
	Set orphan = $Select($Data(orphan): orphan, 1: $Piece($ClassMethod(fixture, "Accounts"), ",", 2))
	Do $$$AssertTrue($ClassMethod(fixture, "AccountExists", orphan), "the account that was already made exists: "_orphan)
	Do $$$AssertEquals($Data(^OcuTalonTest("Fixture", "users", orphan)), 1, "and it is recorded")
	Do $ClassMethod(fixture, "Clean", taken)
	Do $$$AssertEquals($ClassMethod(fixture, "AccountExists", orphan)_$ClassMethod(fixture, "AccountExists", holder), "00", "a Clean of the other session's Ref drops it too, and the holder's")
	Do $$$AssertEquals($ClassMethod(fixture, "Accounts"), "", "and nothing is left recorded")
}

Method TestCleanOnlyTakesItsOwnRefs()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set a = $ClassMethod(fixture, "ChatSession", ..#NAME_"owna", "OcuTalonUser", .userA)
	Set b = $ClassMethod(fixture, "ChatSession", ..#NAME_"ownb", "OcuTalonUser", .userB)
	Do $ClassMethod(fixture, "Clean", a)
	Do $$$AssertEquals($ClassMethod(fixture, "AccountExists", userA)_$ClassMethod(fixture, "AccountExists", userB), "01", "Clean(A) drops A's account and leaves B's")
	Do $ClassMethod(fixture, "Clean")
	Do $$$AssertEquals($ClassMethod(fixture, "AccountExists", userB), 0, "a Clean of everything drops B's account")
}

Method TestCleanDropsAccountOfADeletedRow()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ref = $ClassMethod(fixture, "ChatSession", ..#NAME_"gone", "OcuTalonUser", .user)
	Do ##class(OcuTalon.Data.Session).RefIndexDelete(ref)
	Do $$$AssertEquals($IsObject(##class(OcuTalon.Data.Session).RefIndexOpen(ref)), 0, "the session row was deleted first")
	Do $ClassMethod(fixture, "Clean")
	Do $$$AssertEquals($ClassMethod(fixture, "AccountExists", user), 0, "the account is dropped all the same")
}

Method TestRolesTheFixtureMadeAreDropped()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Do $$$AssertEquals(..RoleExists(..#ROLE), 0, "the instance has no role "_..#ROLE)
	Do $$$AssertEquals(..RoleExists("OcuTalonUser"), 1, "and has OcuTalonUser")
	Set ref = $ClassMethod(fixture, "ChatSession", ..#NAME_"role", "OcuTalonUser,"_..#ROLE, .user)
	Do $$$AssertEquals(..RoleExists(..#ROLE), 1, "the fixture made the role for the account")
	Do $ClassMethod(fixture, "Clean", ref)
	Do $$$AssertEquals(..RoleExists(..#ROLE), 0, "and removed it with the last account")
	Do $$$AssertEquals(..RoleExists("OcuTalonUser"), 1, "a role that the instance had stays")
}

/// 1 when the instance has the role.
ClassMethod RoleExists(role As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ''##class(Security.Roles).Exists(role)
}

}
