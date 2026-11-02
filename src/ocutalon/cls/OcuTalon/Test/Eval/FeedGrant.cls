/// Tests of the one grant of the evaluation set's test feed and of what a failed install leaves behind (Story 9.9; AD-22, AD-24, CON-3). THIS CLASS RUNS IN
/// THROWAWAY STACKS AND IN CI ONLY: Test.Eval.Feed.Fixture makes the feed's namespace, database, resource and grant only where the evaluation folder is
/// mounted, and a test here that finds it missing fails with the fixture's refusal. Each test removes the feed first and removes it again at its end,
/// and OnAfterAllTests removes it once more, so no test depends on another test, on the order of the tests or on an earlier run, and the stack is left as
/// it was found. The tests read the security objects themselves, not the fixture's own report of them.
///   - TestGrantIsLeastPrivilege: while the feed exists the service role has gained Read on the feed's resource and nothing else (no other resource, no
///     granted role, no write or use permission), the resource grants no public permission, the service role is the only role besides the database's own
///     that holds it, and the service user may read it, but neither write nor use it; after Remove the role's Resources are what they were;
///   - TestRemoveTakesBackAFailedInstall: an Install that fails after it made the grant (the production cannot be loaded) leaves the namespace and the
///     grant, and Remove then leaves nothing of the feed, the grant included;
///   - TestInstallOverAFailedInstall: after such a failed Install the next Install succeeds, so that a killed run's leftover is removed first, and the
///     service role holds the grant;
///   - TestInstallRefusedCreatesNothing: with no feed in the stack, Install of a folder that does not exist is refused, and so is Install of an existing
///     folder where the evaluation set is not mounted (UNMOUNTED), and neither makes anything of the feed or changes the service role;
///   - TestRemoveRevokesFirst: a Remove that fails before the namespace (STUCK) has still taken the grant back, and Remove of the feed then leaves
///     nothing.
Class OcuTalon.Test.Eval.FeedGrant Extends %UnitTest.TestCase
{

/// The fixture of the test feed.
Parameter FIXTURE = "OcuTalon.Test.Eval.Feed.Fixture";

/// The fixture whose Install makes everything but the production, and returns OK.
Parameter BARE = "OcuTalon.Test.Eval.Feed.BareFixture";

/// The fixture whose Install fails when it loads the production, after the grant.
Parameter BROKEN = "OcuTalon.Test.Eval.Feed.BrokenFixture";

/// The fixture whose removal fails before the namespace.
Parameter STUCK = "OcuTalon.Test.Eval.Feed.StuckFixture";

/// The fixture whose mount of the evaluation set does not exist.
Parameter UNMOUNTED = "OcuTalon.Test.Eval.Feed.UnmountedFixture";

/// Removes the feed, so that a test that failed halfway leaves nothing in the stack. The status is the removal's.
Method OnAfterAllTests() As %Status
{
	Quit $ClassMethod(..#FIXTURE, "Remove")
}

/// While the feed exists (BARE installs everything but the production) the service role holds Read on the feed's resource and nothing more than it
/// held before: its Resources gain exactly RESOURCE:R, it was granted no role, and the service user holds the roles it held. The resource has no
/// public permission, the roles that hold it are the service role (Read) and the database's own role (named as the resource), the service user may
/// read it and may neither write nor use it. After Remove the resource is gone and the Resources of the service role are what they were.
Method TestGrantIsLeastPrivilege()
{
	Set fixture = ..#FIXTURE, bare = ..#BARE
	Set resource = $Parameter(fixture, "RESOURCE")
	Set role = ##class(OcuTalon.Install.Step.Users).#SERVICEROLE
	Do $$$AssertStatusOK($ClassMethod(fixture, "Remove"), "a leftover of the feed is removed")
	Set before = ..Security()
	Do $$$AssertEquals(before.resource, 0, "before Install the resource of the feed does not exist")
	Do $$$AssertStatusOK($ClassMethod(bare, "Install"), "Install succeeds in a throwaway")
	Set after = ..Security()
	Do $$$AssertEquals(after.resource, 1, "the resource exists while the feed does")
	Do $$$AssertEquals(after.publicPermission, "", "and it grants no public permission")
	Do $$$AssertEquals(..Sorted(after.roleResources), ..Sorted(before.roleResources_","_resource_":R"), "the Resources of the service role gained Read on the resource and nothing else")
	Do $$$AssertEquals(after.grantedRoles, before.grantedRoles, "the service role was granted no role")
	Do $$$AssertEquals(after.userRoles, before.userRoles, "and the service user holds the roles it held")
	Do $$$AssertEquals(after.holders, role_":R", "the service role, with Read, is the only role besides the database's own that holds the resource")
	Do $$$AssertEquals(after.read, 1, "the service user may read the resource")
	Do $$$AssertEquals(after.write, 0, "but not write it")
	Do $$$AssertEquals(after.use, 0, "and not use it")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Remove"), "Remove succeeds")
	Set gone = ..Security()
	Do $$$AssertEquals(gone.resource, 0, "after Remove the resource is gone")
	Do $$$AssertEquals(..Sorted(gone.roleResources), ..Sorted(before.roleResources), "and the Resources of the service role are what they were before the feed")
}

/// An Install that fails after it made the grant (BROKEN cannot load its production) leaves the namespace and the grant. Remove of the feed then
/// succeeds and leaves nothing: Leftovers is empty, the resource is gone and the Resources of the service role are what they were.
Method TestRemoveTakesBackAFailedInstall()
{
	Set fixture = ..#FIXTURE, broken = ..#BROKEN
	Do $$$AssertStatusOK($ClassMethod(fixture, "Remove"), "a leftover of the feed is removed")
	Set before = ..Security()
	Set sc = $ClassMethod(broken, "Install")
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertStatusNotOK(sc, "Install fails when the production cannot be loaded")
	Do $$$AssertTrue(text [ $Parameter(broken, "PRODUCTION"), "and the failure is the load of the production: "_text)
	Set left = $ListFromString($ClassMethod(fixture, "Leftovers"))
	Do $$$AssertTrue($ListFind(left, "namespace") && $ListFind(left, "grant"), "the failed Install left the namespace and the grant, so that there is something to take back: "_$ListToString(left))
	Do $$$AssertStatusOK($ClassMethod(fixture, "Remove"), "Remove succeeds")
	Do $$$AssertEquals($ClassMethod(fixture, "Leftovers"), "", "and nothing of the feed is left, the grant included")
	Set gone = ..Security()
	Do $$$AssertEquals(gone.resource, 0, "the resource is gone")
	Do $$$AssertEquals(..Sorted(gone.roleResources), ..Sorted(before.roleResources), "and the Resources of the service role are what they were before the feed")
}

/// After an Install that failed and left the feed half made, the next Install succeeds: it removed the leftover first, so the Resources of the service
/// role are what they were plus RESOURCE:R. Remove then leaves nothing.
Method TestInstallOverAFailedInstall()
{
	Set fixture = ..#FIXTURE, bare = ..#BARE, broken = ..#BROKEN
	Set resource = $Parameter(fixture, "RESOURCE")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Remove"), "a leftover of the feed is removed")
	Set before = ..Security()
	Do $$$AssertStatusNotOK($ClassMethod(broken, "Install"), "Install fails when the production cannot be loaded")
	Do $$$AssertTrue($ListFind($ListFromString($ClassMethod(fixture, "Leftovers")), "grant"), "and leaves the grant")
	Do $$$AssertStatusOK($ClassMethod(bare, "Install"), "the next Install succeeds over the leftover")
	Set after = ..Security()
	Do $$$AssertEquals(..Sorted(after.roleResources), ..Sorted(before.roleResources_","_resource_":R"), "the Resources of the service role hold the grant, with nothing else new")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Remove"), "Remove succeeds")
	Do $$$AssertEquals($ClassMethod(fixture, "Leftovers"), "", "and nothing of the feed is left")
	Do $$$AssertEquals(..Sorted(..Security().roleResources), ..Sorted(before.roleResources), "the Resources of the service role are what they were before the feed")
}

/// Install refuses where no throwaway's evaluation folder is mounted and makes nothing, starting from a stack with no feed: Install of a folder that does
/// not exist returns the refusal, and so does Install of an existing folder (the mount itself) by UNMOUNTED, whose mount does not exist, so the folder
/// given can only narrow the guard. After each, nothing of the feed exists and the Resources of the service role are what they were.
Method TestInstallRefusedCreatesNothing()
{
	Set fixture = ..#FIXTURE, unmounted = ..#UNMOUNTED
	Set refusal = $Parameter(fixture, "REFUSAL")
	Set mount = ##class(OcuTalon.Eval.In).#FOLDER
	Set missing = ##class(%File).NormalizeDirectory("/tmp/zz-eval-feedgrant-"_##class(OcuTalon.Bridge.Ids).NewRef())
	Do $$$AssertStatusOK($ClassMethod(fixture, "Remove"), "a leftover of the feed is removed")
	Set before = ..Security()
	Do $$$AssertTrue(##class(%File).DirectoryExists(mount), "the evaluation folder is mounted in this stack")
	Do $$$AssertNotTrue(##class(%File).DirectoryExists(missing) || ##class(%File).DirectoryExists($ClassMethod(unmounted, "Mount")), "and the folders that stand in for a missing mount do not exist")
	Set sc = $ClassMethod(fixture, "Install", missing)
	Do $$$AssertStatusNotOK(sc, "Install of a folder that does not exist is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ refusal, "with the reason: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals($ClassMethod(fixture, "Leftovers"), "", "and nothing of the feed was made")
	Do $$$AssertEquals(..Sorted(..Security().roleResources), ..Sorted(before.roleResources), "and the Resources of the service role are what they were")
	Set sc = $ClassMethod(unmounted, "Install", mount)
	Do $$$AssertStatusNotOK(sc, "Install of an existing folder is refused where the evaluation set is not mounted")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ refusal, "with the reason: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals($ClassMethod(fixture, "Leftovers"), "", "and nothing of the feed was made")
	Do $$$AssertEquals(..Sorted(..Security().roleResources), ..Sorted(before.roleResources), "and the Resources of the service role are what they were")
}

/// Remove takes the grant back first, so that it is gone even when a later step fails: after BARE has installed the feed, Remove by STUCK, whose removal
/// stops before the namespace, returns an error and leaves the namespace and the resource but not the grant, and the Resources of the service role are
/// what they were. Remove of the feed then leaves nothing.
Method TestRemoveRevokesFirst()
{
	Set fixture = ..#FIXTURE, bare = ..#BARE, stuck = ..#STUCK
	Do $$$AssertStatusOK($ClassMethod(fixture, "Remove"), "a leftover of the feed is removed")
	Set before = ..Security()
	Do $$$AssertStatusOK($ClassMethod(bare, "Install"), "Install succeeds in a throwaway")
	Do $$$AssertTrue($ListFind($ListFromString($ClassMethod(fixture, "Leftovers")), "grant"), "the service role holds the grant while the feed exists")
	Do $$$AssertStatusNotOK($ClassMethod(stuck, "Remove"), "a Remove that stops before the namespace returns an error")
	Set left = $ListFromString($ClassMethod(fixture, "Leftovers"))
	Do $$$AssertTrue($ListFind(left, "namespace") && $ListFind(left, "resource"), "and leaves the namespace and the resource: "_$ListToString(left))
	Do $$$AssertNotTrue($ListFind(left, "grant"), "but not the grant")
	Do $$$AssertEquals(..Sorted(..Security().roleResources), ..Sorted(before.roleResources), "the Resources of the service role are what they were before the feed")
	Do $$$AssertStatusOK($ClassMethod(fixture, "Remove"), "Remove of the feed succeeds")
	Do $$$AssertEquals($ClassMethod(fixture, "Leftovers"), "", "and nothing of the feed is left")
}

/// The security state that the grant touches, read in %SYS, where only system classes resolve, so the names are read first and no other method of this
/// class is called there. resource is 1 when the feed's resource exists; publicPermission is its public permission ("" for none); holders are the roles
/// that hold it except the database's own role (named as the resource), as Role:Permission and ";"-separated; roleResources are the Resources of the service
/// role and grantedRoles its granted roles; userRoles are the roles of the service user; read, write and use are 1 or 0 for what the service user may do
/// on the resource.
ClassMethod Security() As %DynamicObject [ Private ]
{
	Set resource = $Parameter(..#FIXTURE, "RESOURCE")
	Set role = ##class(OcuTalon.Install.Step.Users).#SERVICEROLE
	Set user = ##class(OcuTalon.Install.Step.Users).#SERVICEUSER
	Set state = {"resource": 0, "publicPermission": "", "holders": "", "roleResources": "", "grantedRoles": "", "userRoles": "", "read": 0, "write": 0, "use": 0}
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	If ##class(Security.Resources).Exists(resource) {
		Set state.resource = 1
		Kill props
		If $$$ISOK(##class(Security.Resources).Get(resource, .props)) Set state.publicPermission = $Get(props("PublicPermission"))
		If $$$ISOK(##class(Security.Resources).InUse(resource, .inUse, .roles, .databases, .applications, 1)) {
			Set position = 0, holders = ""
			While $ListNext($Get(roles), position, holder) {
				If $Piece(holder, ":", 1) = resource Continue
				Set holders = holders_$Select(holders = "": "", 1: ";")_holder
			}
			Set state.holders = holders
		}
		Set state.read = +$SYSTEM.Security.CheckUserPermission(user, resource, "R")
		Set state.write = +$SYSTEM.Security.CheckUserPermission(user, resource, "W")
		Set state.use = +$SYSTEM.Security.CheckUserPermission(user, resource, "U")
	}
	Kill props
	If $$$ISOK(##class(Security.Roles).Get(role, .props)) {
		Set state.roleResources = $Get(props("Resources"))
		Set state.grantedRoles = $Get(props("GrantedRoles"))
	}
	Kill props
	If $$$ISOK(##class(Security.Users).Get(user, .props)) Set state.userRoles = $Get(props("Roles"))
	Quit state
}

/// The comma-separated items of the list, each once, in order.
ClassMethod Sorted(list As %String) As %String [ Private ]
{
	Kill items
	For i = 1:1:$Length(list, ",") {
		Set item = $Piece(list, ",", i)
		If item '= "" Set items(item) = ""
	}
	Set text = "", item = ""
	For {
		Set item = $Order(items(item))
		If item = "" Quit
		Set text = text_$Select(text = "": "", 1: ",")_item
	}
	Quit text
}

}
