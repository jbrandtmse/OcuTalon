/// Tests of the Users step (matrix row 16, and Story 3.1): the README account is seed (AD-19); the service user is login-disabled with a random
/// seed password; on the online demo the two published accounts are structural and the README account is disabled. The fixture's user and
/// roles are created in OnBeforeAllTests and removed in OnAfterAllTests; the real README account is never touched, and the real service user
/// and its role are removed again when the tests made them. The fixture's number comes from ^OcuTalonTest("Users","n"), which is never reset,
/// so no two runs share a fixture name. The five public keys are saved before each test and restored after it, and the real service user,
/// which some tests change by hand, is put right again after each test. The instance's password-validation setting and the password guard
/// routine are saved before each test and put back after it (Test.Install.PasswordGuard), and the control user ZzUsers<n>Ctl and the
/// foreign routine ZzForeign are removed.
/// Story 3.8 adds, for the password guard of the online demo (AD-13, AD-24):
///   - TestGuardWithFlagOn: the guard is set, holds no password in clear, and refuses a password change of either public account by
///     Security.Users.Modify and by a sign-in request, while a user that is not public changes its password the same way;
///   - TestInstallerWritesAChangedPassword: a changed published password is written by the installer, and the guard then refuses the old one;
///   - TestNoGuardWithFlagOff: no guard locally, and the flag turned off removes the guard with one warning;
///   - TestForeignGuardIsRefused: another routine is refused with the flag on, and never touched with the flag off.
///   - TestGuardDecidesByNameAndPassword: the routine's own answers, by name (any case, with or without a domain) and password, and for
///     names that are not public;
///   - TestFlagOffRemovesALeftoverGuardRoutine: a routine left without the setting is deleted with the flag off, with one warning;
///   - TestFailedGuardLeavesTheSetting: a guard that fails its check refuses the step and leaves the setting as it was, with no routine
///     written;
///   - TestFailedGuardKeepsTheLiveGuard: on a later start, a guard that fails its check leaves the guard that is set exactly as it was.
/// They set and restore the security settings of the instance: throwaways and CI only.
Class OcuTalon.Test.Install.Users Extends %UnitTest.TestCase
{

/// The step under test.
Parameter STEP = "OcuTalon.Install.Step.Users";

/// The public keys that a test sets, in the order of Saved.
Parameter KEYS = "onlineDemo,demoUser,demoPassword,readonlyUser,readonlyPassword";

/// The step with a list of namespaces for the page size pin that names one that does not exist, and a known NewPassword.
Parameter PINS = "OcuTalon.Test.Install.ZzUsersPins";

/// The fixture's number, from a counter that Clean leaves alone: the user is ZzUsers<n> and the roles are ZzUsers<n>RoleA and
/// ZzUsers<n>RoleB.
Property Number As %Integer;

Property User As %String;

Property Roles As %String;

/// The fixture README account, and the fixture demo and read-only accounts.
Property Readme As %String;

Property Demo As %String;

Property Ro As %String;

/// The control user, who is not public.
Property Ctl As %String;

/// The password-validation setting and the guard routine before a test (Test.Install.PasswordGuard.State).
Property GuardState As %List;

/// The same, as the class found them in OnBeforeAllTests: OnAfterAllTests puts them back and checks them.
Property GuardBaseline As %List;

/// The values of the public keys before a test, as a list in the order of KEYS.
Property Saved As %List;

/// 1 when the real service user, or the real service role, existed before any test ran: one that a test made is removed again.
Property ServiceUserBefore As %Boolean;

Property ServiceRoleBefore As %Boolean;

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("Users", "n"))
	Set ..User = "ZzUsers"_..Number
	Set ..Roles = "ZzUsers"_..Number_"RoleA,ZzUsers"_..Number_"RoleB"
	Set ..Readme = "ZzUsers"_..Number_"Readme"
	Set ..Demo = "ZzUsers"_..Number_"Demo"
	Set ..Ro = "ZzUsers"_..Number_"Ro"
	Set ..Ctl = "ZzUsers"_..Number_"Ctl"
	Set ..GuardBaseline = ##class(OcuTalon.Test.Install.PasswordGuard).State()
	Set ..ServiceUserBefore = ..UserExists($Parameter(..#STEP, "SERVICEUSER"))
	Set ..ServiceRoleBefore = ..RoleExists($Parameter(..#STEP, "SERVICEROLE"))
	Set sc = ..CreateRoles()
	If $$$ISOK(sc), '..ServiceRoleBefore Set sc = ..CreateRole($Parameter(..#STEP, "SERVICEROLE"))
	Quit sc
}

Method OnAfterAllTests() As %Status
{
	Set guard = "OcuTalon.Test.Install.PasswordGuard"
	If $ListValid(..GuardBaseline) Do $ClassMethod(guard, "Restore", ..GuardBaseline)
	Do ..Clean()
	If '..ServiceUserBefore Do ..Remove($Parameter(..#STEP, "SERVICEUSER"))
	If '..ServiceRoleBefore Do ..RemoveRole($Parameter(..#STEP, "SERVICEROLE"))
	If $ListValid(..GuardBaseline) {
		Set leak = $ClassMethod(guard, "Leak", ..GuardBaseline)
		If leak '= "" Quit $SYSTEM.Status.Error(5001, "The class left the password guard changed: "_leak)
	}
	Quit $SYSTEM.Status.OK()
}

/// Saves the public keys and clears the fixture accounts, so that a test starts from nothing.
Method OnBeforeOneTest(testname As %String) As %Status
{
	Set saved = ""
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	While $ListNext(keys, position, key) {
		Set saved = saved _ $ListBuild(##class(OcuTalon.Data.Public.Settings).Get(key))
	}
	Set ..Saved = saved
	Set ..GuardState = ##class(OcuTalon.Test.Install.PasswordGuard).State()
	Do ..ClearAccounts()
	Quit $SYSTEM.Status.OK()
}

/// Puts the password-validation setting and the guard routine back first, and asserts that they are as the test found them. Then puts the
/// public keys back, a key that was not set removed, puts the real service user right when it exists (a test that changed it by hand and
/// stopped early leaves it so), and removes the fixture accounts.
Method OnAfterOneTest(testname As %String) As %Status
{
	Set guard = "OcuTalon.Test.Install.PasswordGuard"
	Do $ClassMethod(guard, "Restore", ..GuardState)
	Do ..RemoveForeign()
	Do $$$AssertEquals($ClassMethod(guard, "Leak", ..GuardState), "", "the test left the password-validation setting and the guard routine as it found them")
	Set keys = $ListFromString(..#KEYS)
	Set position = 0
	Set index = 0
	While $ListNext(keys, position, key) {
		Set index = index + 1
		Do ##class(OcuTalon.Data.Public.Settings).Set(key, $ListGet(..Saved, index))
	}
	If ..UserExists($Parameter(..#STEP, "SERVICEUSER")) Do $ClassMethod(..#STEP, "EnsureService")
	Do ..ClearAccounts()
	Quit $SYSTEM.Status.OK()
}

/// The first call creates the account with the README account's flags; the roles are the given ones. The account is read
/// again until its password hash is there, for up to about 2 seconds: the create is read back, not assumed to be visible at once.
/// The hash is binary and is told by its length, never by a field of the line, which a "|" in the hash would cut.
Method TestEnsureCreates()
{
	Do ..Remove(..User)
	Do $$$AssertEquals(..Account(..User), "<none>", "no fixture account to begin with")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Users).Ensure(..User, "Zz-pw-first-1", ..Roles), "Ensure creates the account")
	Set account = ..Account(..User, 1)
	Do $$$AssertEquals($Piece(account, "|", 1), 1, "Enabled")
	Do $$$AssertEquals($Piece(account, "|", 2), 0, "ChangePassword")
	Do $$$AssertEquals($Piece(account, "|", 3), 1, "PasswordNeverExpires")
	Do $$$AssertEquals($Piece(account, "|", 4), 1, "AccountNeverExpires")
	Do $$$AssertEquals($Piece(account, "|", 5), ..Roles, "the roles")
	Do $$$AssertTrue($Piece(account, "|", 6) > 0, "the account has a password hash: its length is "_$Piece(account, "|", 6))
}

/// A second call, with another password and other roles, changes nothing: hash, salt, roles and flags. The account just
/// created is read back with the same wait as in TestEnsureCreates.
Method TestEnsureKeepsAnExistingAccount()
{
	Do ..Remove(..User)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Users).Ensure(..User, "Zz-pw-first-1", ..Roles), "Ensure creates the account")
	Set before = ..Account(..User, 1)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Users).Ensure(..User, "Zz-pw-second-2", $Piece(..Roles, ",", 1)), "Ensure on an existing account succeeds")
	Do $$$AssertEquals(..Account(..User), before, "password hash, salt, roles and flags are unchanged")
	Do ..SetFlags(..User, 0, 1, 0)
	Set changed = ..Account(..User)
	Do $$$AssertNotEquals(changed, before, "the flags were changed by hand")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Users).Ensure(..User, "Zz-pw-third-3", ..Roles), "Ensure again")
	Do $$$AssertEquals(..Account(..User), changed, "a change made by hand survives Ensure")
}

/// A password that the instance refuses is a failure status, and no account is left behind.
Method TestEnsureReportsAFailure()
{
	Do ..Remove(..User)
	Set sc = ##class(OcuTalon.Install.Step.Users).Ensure(..User, "x", ..Roles)
	Do $$$AssertStatusNotOK(sc, "Ensure fails for a password that does not meet the instance's pattern")
	Do $$$AssertEquals(..Account(..User), "<none>", "no account was created")
}

/// The fixture's nodes are cleared and the counter is not: after ClearNodes a node the class left is gone and the counter
/// holds this run's number, so the next run's number is a new one.
Method TestClearKeepsTheCounter()
{
	Set probe = "ZzProbe"_..Number
	Set ^OcuTalonTest("Users", probe) = 1
	Do ..ClearNodes()
	Do $$$AssertEquals($Data(^OcuTalonTest("Users", probe)), 0, "a node of the class is cleared")
	Do $$$AssertEquals($Get(^OcuTalonTest("Users", "n")), ..Number, "the counter keeps this run's number")
}

/// Clean, which both hooks call, removes the fixture's account and keeps the counter: after it the account is gone and the
/// counter holds this run's number, so no later run reuses this run's fixture name. The fixture roles that Clean removes are
/// created again, so the tests in any order find them.
Method TestCleanKeepsTheCounter()
{
	Do ..Remove(..User)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Users).Ensure(..User, "Zz-pw-clean-1", ..Roles), "Ensure creates the account")
	Do $$$AssertNotEquals(..Account(..User), "<none>", "the account exists before Clean")
	Do ..Clean()
	Do $$$AssertEquals(..Account(..User), "<none>", "Clean removes the fixture account")
	Do $$$AssertEquals($Get(^OcuTalonTest("Users", "n")), ..Number, "Clean keeps the counter, so no later run reuses this run's fixture name")
	Do $$$AssertStatusOK(..CreateRoles(), "the fixture roles are created again")
}

/// The step declares the two roles that hold no resource, and publishes the README account's name, password and roles.
Method TestDeclarations()
{
	Set users = "OcuTalon.Install.Step.Users"
	Do $$$AssertEquals($Parameter(users, "USER"), "ocutalon", "the README account")
	Do $$$AssertEquals($Parameter(users, "PASSWORD"), "ocutalon", "the published password")
	Do $$$AssertEquals($Parameter(users, "ROLES"), "OcuTalonUser,OcuTalonAdmin,OcuTalonTraceViewer", "the three roles")
	Set grants = $ClassMethod(users, "Grants")
	Do $$$AssertEquals(grants.%Size(), 2, "two declarations")
	Do $$$AssertEquals(grants.%Get(0).role, "OcuTalonUser", "OcuTalonUser")
	Do $$$AssertEquals(grants.%Get(0).resource, "", "OcuTalonUser holds no resource")
	Do $$$AssertEquals(grants.%Get(1).role, "OcuTalonAdmin", "OcuTalonAdmin")
	Do $$$AssertEquals(grants.%Get(1).resource, "", "OcuTalonAdmin holds no resource")
	Do $$$AssertEquals($Parameter(users, "SERVICEUSER"), "OcuTalonService", "the service user")
	Do $$$AssertEquals($Parameter(users, "SERVICEROLE"), "OcuTalonServiceRole", "the service user's role")
	Do $$$AssertEquals($Parameter(users, "DEMOROLES"), "OcuTalonUser,OcuTalonTraceViewer", "the demo account's roles")
	Do $$$AssertEquals($Parameter(users, "READONLYROLES"), "OcuTalonTraceViewer", "the read-only account's role")
	Do $$$AssertEquals($Parameter(users, "TRACEPAGESIZE"), 100, "the pinned page size")
	Do $$$AssertEquals($Parameter(users, "MARKER"), "OcuTalon online-demo account", "the marker of the accounts the step made, which a kept volume holds")
	Do $$$AssertEquals($Parameter(users, "TRACENAMESPACES"), "OCUTALON,OCUORDERS", "the namespaces of the page size pin")
}

/// The account line keeps the hash apart from its length: the hash and the salt are binary, so either may hold "|" and the hash
/// may begin with it, and the line tells a hash that begins with the delimiter from an empty one.
Method TestAccountLineKeepsAPipeHash()
{
	Set hash = "|"_$Translate($Justify("", 63), " ", "x")
	Set line = ..Line(1, 0, 1, 1, "r", hash, "|s")
	Do $$$AssertEquals($Piece(line, "|", 6), 64, "a hash that begins with the delimiter reports its length")
	Do $$$AssertEquals($Piece(line, "|", 7, $Length(line, "|")), hash_"|s", "the hash and the salt follow, whole")
	Do $$$AssertEquals($Piece(..Line(1, 0, 1, 1, "r", "", "salt"), "|", 6), 0, "an empty hash reports the length 0")
}

/// Matrix row 1: the service user is made with login disabled, no forced change, a password and an account that never expire, exactly
/// the role, and the password that NewPassword makes (TestNewPassword pins that it is random): the step with a known NewPassword gives the
/// user that password. The user and the role are fixtures (EnsureService takes both), so the real service user is not touched.
Method TestServiceUserIsCreated()
{
	Set service = "ZzUsers"_..Number_"Svc"
	Set role = $Piece(..Roles, ",", 1)
	Do $$$AssertEquals(..Account(service), "<none>", "no fixture service user to begin with")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "EnsureService", service, role), "EnsureService creates the user")
	Set first = ..Account(service, 1)
	Do $$$AssertEquals($Piece(first, "|", 1), 0, "Enabled is 0: login is disabled")
	Do $$$AssertEquals($Piece(first, "|", 2), 0, "ChangePassword")
	Do $$$AssertEquals($Piece(first, "|", 3), 1, "PasswordNeverExpires")
	Do $$$AssertEquals($Piece(first, "|", 4), 1, "AccountNeverExpires")
	Do $$$AssertEquals($Piece(first, "|", 5), role, "exactly the role")
	Do $$$AssertTrue($Piece(first, "|", 6) > 0, "the account has a password hash: its length is "_$Piece(first, "|", 6))
	Do $$$AssertTrue('..PasswordOk(service, $Parameter(..#STEP, "PASSWORD")), "the README's published password is not the service user's")
	Do ..Remove(service)
	Do $$$AssertStatusOK($ClassMethod(..#PINS, "EnsureService", service, role), "the step with a known NewPassword makes the user again")
	Do ..Account(service, 1)
	Do $$$AssertTrue(..PasswordOk(service, $ClassMethod(..#PINS, "NewPassword")), "the user's password is the one that NewPassword makes")
}

/// The generator of the service user's password: 44 characters, and every call another one.
Method TestNewPassword()
{
	Set first = $ClassMethod(..#STEP, "NewPassword")
	Set second = $ClassMethod(..#STEP, "NewPassword")
	Do $$$AssertEquals($Length(first), 44, "a password has 44 characters")
	Do $$$AssertEquals($Length(second), 44, "and so has the next")
	Do $$$AssertNotEquals(first, second, "and the next is another one")
}

/// Matrix row 2: a service user that was enabled by hand and given another role and an escalation role is disabled again, holds exactly the
/// role and no escalation role, and its password hash is the one it had (seed).
Method TestServiceUserDriftIsRepaired()
{
	Set service = "ZzUsers"_..Number_"Svc"
	Set role = $Piece(..Roles, ",", 1)
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "EnsureService", service, role), "EnsureService creates the user")
	Set before = ..Account(service, 1)
	Do ..SetProperty(service, "Enabled", 1)
	Do ..SetProperty(service, "Roles", ..Roles)
	Do ..SetProperty(service, "EscalationRoles", $Piece(..Roles, ",", 2))
	Set drifted = ..Account(service)
	Do $$$AssertEquals($Piece(drifted, "|", 1), 1, "the user was enabled by hand")
	Do $$$AssertEquals(..SortedRoles(drifted), ..Roles, "and given the other role")
	Do $$$AssertEquals(..EscalationRoles(service), $Piece(..Roles, ",", 2), "and an escalation role")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "EnsureService", service, role), "EnsureService runs again")
	Set after = ..Account(service)
	Do $$$AssertEquals($Piece(after, "|", 1), 0, "Enabled is 0 again")
	Do $$$AssertEquals($Piece(after, "|", 5), role, "and the roles are exactly the role")
	Do $$$AssertEquals(..EscalationRoles(service), "", "and it has no escalation role")
	Do $$$AssertEquals($Piece(after, "|", 6, $Length(after, "|")), $Piece(before, "|", 6, $Length(before, "|")), "the password hash and salt are unchanged")
}

/// Matrix row 8: with the flag off, Accounts makes the README account, with the three roles and the flags of the seed, and the service user,
/// and no public account even when their keys are set. The README account is seed: one disabled by hand stays as it is.
Method TestReadmeAccountWithFlagOff()
{
	Do ..SetPublic(0, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Accounts", ..Readme), "Accounts runs with the flag off")
	Set readme = ..Account(..Readme, 1)
	Do $$$AssertEquals($Piece(readme, "|", 1), 1, "the README account is enabled")
	Do $$$AssertEquals($Piece(readme, "|", 2), 0, "ChangePassword")
	Do $$$AssertEquals($Piece(readme, "|", 3), 1, "PasswordNeverExpires")
	Do $$$AssertEquals($Piece(readme, "|", 4), 1, "AccountNeverExpires")
	Do $$$AssertEquals(..SortedRoles(readme), ..Sorted($Parameter(..#STEP, "ROLES")), "the three roles")
	Do $$$AssertEquals(..Account(..Demo), "<none>", "no demo account is made")
	Do $$$AssertEquals(..Account(..Ro), "<none>", "and no read-only account")
	Do $$$AssertEquals($Data(^|"OCUTALON"|EnsPortal.Settings(..Demo)), 0, "and no page size is pinned")
	Set service = ..Account($Parameter(..#STEP, "SERVICEUSER"), 1)
	Do $$$AssertEquals($Piece(service, "|", 1), 0, "the service user is made, with login disabled")
	Do $$$AssertEquals(..SortedRoles(service), $Parameter(..#STEP, "SERVICEROLE"), "and exactly the service role")

	Do ..SetProperty(..Readme, "Enabled", 0)
	Set disabled = ..Account(..Readme)
	Do ..SetProperty($Parameter(..#STEP, "SERVICEUSER"), "Enabled", 1)
	Do ..SetProperty($Parameter(..#STEP, "SERVICEUSER"), "Roles", ..Roles)
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Accounts", ..Readme), "Accounts runs again")
	Do $$$AssertEquals(..Account(..Readme), disabled, "the README account is seed: a change by hand stays")
	Do $$$AssertEquals(..Account($Parameter(..#STEP, "SERVICEUSER")), service, "and the service user, enabled by hand with other roles, is put right with its password hash unchanged")
}

/// Matrix row 9: with the flag on, Accounts makes the two published accounts with exactly their roles and flags and their published
/// passwords, pins their Visual Trace page size to 100 in OCUTALON and OCUORDERS, leaves them no write access to the database of the page
/// settings, makes no README account, and disables one that exists (roles and password unchanged) with a warning that names it. A role and an
/// escalation role added by hand, a changed password, changed flags and a changed page size are put back at the next run.
Method TestPublicAccountsWithFlagOn()
{
	Set step = ..#STEP
	Set demoRoles = "OcuTalonTraceViewer,OcuTalonUser"
	Set readonlyRoles = "OcuTalonTraceViewer"
	Do $$$AssertEquals(..Sorted($Parameter(step, "DEMOROLES")), demoRoles, "the demo account's roles are the trace role and the user role")
	Do $$$AssertEquals(..Sorted($Parameter(step, "READONLYROLES")), readonlyRoles, "and the read-only account's the trace role")
	Do $$$AssertTrue(##class(%SYS.Namespace).Exists("OCUORDERS"), "OCUORDERS exists on the stack, so the page size is pinned there too")

	Do ..SetPublic(0, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "Accounts makes the README account with the flag off")
	Set readmeBefore = ..Account(..Readme, 1)
	Do $$$AssertEquals($Piece(readmeBefore, "|", 1), 1, "the README account is enabled")

	Do ..SetPublic(1, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $ClassMethod("OcuTalon.Install.Step", "TakeWarnings")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "Accounts runs with the flag on")
	Set warnings = $ClassMethod("OcuTalon.Install.Step", "TakeWarnings")
	Do $$$AssertTrue($ListToString(warnings) [ ..Readme, "the step warns, naming the README account")
	Set serviceHash = ..Account($Parameter(step, "SERVICEUSER"), 1)

	Set readmeAfter = ..Account(..Readme)
	Do $$$AssertEquals($Piece(readmeAfter, "|", 1), 0, "the README account is disabled")
	Do $$$AssertEquals($Piece(readmeAfter, "|", 2, $Length(readmeAfter, "|")), $Piece(readmeBefore, "|", 2, $Length(readmeBefore, "|")), "and its flags, roles and password are unchanged")
	Do $$$AssertTrue(..PasswordOk(..Readme, "ocutalon"), "its published password is unchanged, so it is the disabled flag that stops the sign-in")

	Set accounts = $ListBuild($ListBuild(..Demo, "Zz-demo-pw-1", demoRoles), $ListBuild(..Ro, "Zz-ro-pw-1", readonlyRoles))
	Do ..AssertPublic(accounts, "after the first run")

	#; Drift: a role added by hand, a changed password, changed flags, a changed page size, and the README account enabled again.
	Do ..SetProperty(..Demo, "Roles", $Parameter(step, "DEMOROLES")_",OcuTalonAdmin")
	Do ..SetProperty(..Demo, "EscalationRoles", "OcuTalonAdmin")
	Do ..SetProperty(..Demo, "Password", "Zz-other-pw-9")
	Do ..SetProperty(..Demo, "Enabled", 0)
	Do ..SetProperty(..Demo, "ChangePassword", 1)
	Do ..SetProperty(..Ro, "PasswordNeverExpires", 0)
	Do ..SetProperty(..Ro, "AccountNeverExpires", 0)
	Do ..SetProperty(..Ro, "Roles", "OcuTalonTraceViewer,OcuTalonAdmin")
	Set ^|"OCUTALON"|EnsPortal.Settings(..Demo, "VisualTrace", "ItemsPerPage") = 40
	Set ^|"OCUORDERS"|EnsPortal.Settings(..Ro, "VisualTrace", "ItemsPerPage") = 20
	Do ..SetProperty(..Readme, "Enabled", 1)
	Do ..SetProperty($Parameter(step, "SERVICEUSER"), "Enabled", 1)
	Do ..SetProperty($Parameter(step, "SERVICEUSER"), "Roles", ..Roles)
	Do $$$AssertEquals(..SortedRoles(..Account(..Demo)), ..Sorted($Parameter(step, "DEMOROLES")_",OcuTalonAdmin"), "the demo account was given OcuTalonAdmin by hand")
	Do $$$AssertEquals(..EscalationRoles(..Demo), "OcuTalonAdmin", "and as an escalation role")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "Accounts runs again")
	Do ..AssertPublic(accounts, "after the second run")
	Do $$$AssertEquals($Piece(..Account(..Readme), "|", 1), 0, "the README account is disabled again")
	Do $$$AssertEquals(..Account($Parameter(step, "SERVICEUSER")), serviceHash, "the service user, enabled by hand with other roles, is put right by the second run with its password hash unchanged")
}

/// Matrix rows 8 and 9: with the flag on, Accounts makes no README account where there is none (it is made only on a local install), and
/// still makes the two published accounts.
Method TestNoReadmeAccountWithFlagOn()
{
	Do ..SetPublic(1, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertEquals(..Account(..Readme), "<none>", "there is no README account to begin with")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Accounts", ..Readme), "Accounts runs with the flag on")
	Do $$$AssertEquals(..Account(..Readme), "<none>", "and makes no README account")
	Do $$$AssertEquals($Piece(..Account(..Demo), "|", 1), 1, "the demo account is made")
	Do $$$AssertEquals($Piece(..Account(..Ro), "|", 1), 1, "and the read-only account")
}

/// Matrix row 10: with the flag on, an empty name or password, two names that differ only in case, the service user's name, the README
/// account's name, and the name of an account that the installer did not make (_SYSTEM) each fail the step with a status that names the key
/// or the clash. No account is created or changed: the fixture accounts do not exist, _SYSTEM keeps its password, the service user is as it
/// was, and no page size is pinned.
Method TestPublicAccountsRefused()
{
	Set step = ..#STEP
	Set service = $Parameter(step, "SERVICEUSER")
	Do $$$AssertStatusOK($ClassMethod(step, "Ensure", ..Readme, "Zz-readme-pw-1", $Parameter(step, "ROLES")), "the fixture README account exists")
	Set systemBefore = ..Account("_SYSTEM")
	Set serviceBefore = ..Account(service)
	Set cases = ""
	Set cases = cases _ $ListBuild($ListBuild("", "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1", "demoUser"))
	Set cases = cases _ $ListBuild($ListBuild(..Demo, "", ..Ro, "Zz-ro-pw-1", "demoPassword"))
	Set cases = cases _ $ListBuild($ListBuild(..Demo, "Zz-demo-pw-1", "", "Zz-ro-pw-1", "readonlyUser"))
	Set cases = cases _ $ListBuild($ListBuild(..Demo, "Zz-demo-pw-1", ..Ro, "", "readonlyPassword"))
	Set cases = cases _ $ListBuild($ListBuild(..Demo, "Zz-demo-pw-1", $ZConvert(..Demo, "U"), "Zz-ro-pw-1", "same account"))
	Set cases = cases _ $ListBuild($ListBuild(service, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1", "service user"))
	Set cases = cases _ $ListBuild($ListBuild(..Demo, "Zz-demo-pw-1", $ZConvert(service, "L"), "Zz-ro-pw-1", "service user"))
	Set cases = cases _ $ListBuild($ListBuild(..Readme, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1", "README account"))
	Set cases = cases _ $ListBuild($ListBuild(..Demo, "Zz-demo-pw-1", $ZConvert(..Readme, "U"), "Zz-ro-pw-1", "README account"))
	Set cases = cases _ $ListBuild($ListBuild(..Demo, "Zz-demo-pw-1", $Piece($Parameter(step, "DEMOROLES"), ",", 1), "Zz-ro-pw-1", "names the role"))
	Set cases = cases _ $ListBuild($ListBuild(..Demo, "Zz-demo-pw-1", "_SYSTEM", "Zz-ro-pw-1", "did not make"))
	Set position = 0
	While $ListNext(cases, position, case) {
		Do ..SetPublic(1, $List(case, 1), $List(case, 2), $List(case, 3), $List(case, 4))
		Set sc = $ClassMethod(step, "Accounts", ..Readme)
		Set text = $SYSTEM.Status.GetErrorText(sc)
		Set label = $List(case, 5)_" ("_$List(case, 1)_" / "_$List(case, 3)_")"
		Do $$$AssertStatusNotOK(sc, "Accounts fails for "_label)
		Do $$$AssertTrue(text [ $List(case, 5), "and the error names '"_$List(case, 5)_"': "_text)
		Do $$$AssertTrue(text [ "OcuTalon.Install.Step.Users", "and the step")
	}
	Do $$$AssertEquals(..Account(..Demo), "<none>", "no demo account was made")
	Do $$$AssertEquals(..Account(..Ro), "<none>", "no read-only account was made")
	Do $$$AssertEquals(..Account("_SYSTEM"), systemBefore, "_SYSTEM keeps its password, roles and flags")
	Do $$$AssertEquals(..Account(service), serviceBefore, "the service user is as it was, or still absent")
	Do $$$AssertEquals($Piece(..Account(..Readme), "|", 1), 1, "and the README account is still enabled")
	Do $$$AssertEquals($Data(^|"OCUTALON"|EnsPortal.Settings(..Demo)), 0, "no page size is pinned")
	Do $$$AssertEquals($Data(^|"OCUTALON"|EnsPortal.Settings(..Ro)), 0, "for either account")
	Do ..SetPublic(1, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "control: valid keys pass")
}

/// A refusal by the instance itself is the status of that call with the user or the key named: a service user named like a role (a role and
/// a user cannot share a name), and a published password that the instance's policy rejects (two characters). No account is made.
Method TestApplyFailuresNameTheUserAndTheKey()
{
	Set step = ..#STEP
	Set service = $Piece(..Roles, ",", 1)
	Set sc = $ClassMethod(step, "EnsureService", service, $Piece(..Roles, ",", 2))
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertStatusNotOK(sc, "EnsureService fails for a user named like a role")
	Do $$$AssertTrue((text [ service) && (text [ "OcuTalon.Install.Step.Users"), "and the error names the user and the step")
	Do $$$AssertEquals(..Account(service), "<none>", "and no user is made")

	Do ..SetPublic(1, ..Demo, "ab", ..Ro, "Zz-ro-pw-1")
	Set sc = $ClassMethod(step, "Accounts", ..Readme)
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertStatusNotOK(sc, "Accounts fails for a password of two characters")
	Do $$$AssertTrue((text [ "demoUser") && (text [ "demoPassword") && (text [ ..Demo), "and the error names the two keys and the account: "_text)
	Do $$$AssertEquals(..Account(..Demo), "<none>", "and the account is not made")
}

/// The error column of row 8: the status of Ensure is returned by Accounts, not swallowed. The README account is named like a role, which the
/// instance refuses (a role and a user cannot share a name).
Method TestFailureOfEnsureIsReturned()
{
	Set step = ..#STEP
	Do ..SetPublic(0, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Set readmeUser = $Piece(..Roles, ",", 2)
	Set sc = $ClassMethod(step, "Accounts", readmeUser)
	Do $$$AssertStatusNotOK(sc, "Accounts returns the failure of Ensure for the README name "_readmeUser)
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "control: Accounts runs for a README name that is not a role")
}

/// Run is the step of a start: with the flag off it puts the service user right, as Accounts does, and leaves the README account. A README
/// account that the test made is removed again.
Method TestRunIsTheStep()
{
	Set step = ..#STEP
	Set service = $Parameter(step, "SERVICEUSER")
	Set readme = $Parameter(step, "USER")
	Set readmeBefore = ..UserExists(readme)
	Do ..SetPublic(0, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "Accounts makes the service user")
	Set expected = ..Account(service, 1)
	Do ..SetProperty(service, "Enabled", 1)
	Do ..SetProperty(service, "Roles", ..Roles)
	Do $$$AssertStatusOK($ClassMethod(step, "Run"), "Run runs with the flag off")
	Do $$$AssertEquals(..Account(service), expected, "the service user is disabled again, holds exactly its role and keeps its password hash")
	Do $$$AssertTrue(..UserExists(readme), "and the README account is there")
	If 'readmeBefore Do ..Remove(readme)
}

/// The online-demo flag and the accounts come from the public settings, never from the environment (AD-19): the step's source does not read it.
Method TestNoEnvironment()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Bridge.Source).Text(..#STEP, .text), "the step has source")
	Do $$$AssertTrue(text [ "ClassMethod Accounts", "control: the text is the step's source")
	Do $$$AssertNotTrue($ZConvert(text, "L") [ "getenviron", "the Users step holds no GetEnviron")
}

/// Matrix row 10 ("no account is created or changed"): the service user is included. The real service user is enabled by hand and given other
/// roles, and a refused run leaves it so, because the checks run before the service user is applied; a run that is not refused puts it right.
Method TestRefusalLeavesADriftedServiceUserAlone()
{
	Set step = ..#STEP
	Set service = $Parameter(step, "SERVICEUSER")
	Do ..SetPublic(0, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "Accounts makes the service user right")
	Set right = ..Account(service, 1)
	Do ..SetProperty(service, "Enabled", 1)
	Do ..SetProperty(service, "Roles", ..Roles)
	Set drifted = ..Account(service)
	Do $$$AssertNotEquals(drifted, right, "the service user was changed by hand")

	Do ..SetPublic(1, ..Demo, "", ..Ro, "Zz-ro-pw-1")
	Set sc = $ClassMethod(step, "Accounts", ..Readme)
	Do $$$AssertStatusNotOK(sc, "Accounts refuses an empty demo password")
	Do $$$AssertEquals(..Account(service), drifted, "and the service user is as the hand left it: enabled, with the other roles")
	Do $$$AssertEquals(..Account(..Demo), "<none>", "and no public account is made")

	Do ..SetPublic(0, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "a run that is not refused follows")
	Do $$$AssertEquals(..Account(service), right, "and puts the service user right again")
}

/// Rows 8 and 9: only the flag 1 is on. A flag that was never set, 0, and any other value read as off: Accounts makes the README account and
/// the service user, and makes no public account and pins no page size, although the public accounts' keys are set.
Method TestOnlyOneTurnsTheFlagOn()
{
	Set step = ..#STEP
	Set values = $ListBuild("", 0, "yes", "true", 2)
	Set position = 0
	While $ListNext(values, position, value) {
		Do ..ClearAccounts()
		Do ..SetPublic(value, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
		Set label = "the flag '"_value_"'"
		Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), label_": Accounts runs")
		Do $$$AssertEquals($Piece(..Account(..Readme), "|", 1), 1, label_" is off: the README account is made, enabled")
		Do $$$AssertEquals(..Account(..Demo), "<none>", label_": no demo account is made")
		Do $$$AssertEquals(..Account(..Ro), "<none>", label_": and no read-only account")
		Do $$$AssertEquals($Data(^|"OCUTALON"|EnsPortal.Settings(..Demo)), 0, label_": and no page size is pinned")
	}
	Do ..ClearAccounts()
	Do ..SetPublic(1, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "control: the flag 1 runs")
	Do $$$AssertEquals($Piece(..Account(..Demo), "|", 1), 1, "and makes the demo account")
	Do $$$AssertEquals(..Account(..Readme), "<none>", "and no README account")
}

/// Row 9: the step warns when it disables the README account, and not again on a later start where the account is already disabled.
Method TestADisabledReadmeAccountIsNotWarnedAboutAgain()
{
	Set step = ..#STEP
	Do ..SetPublic(0, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "Accounts makes the README account with the flag off")
	Do ..SetPublic(1, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $ClassMethod("OcuTalon.Install.Step", "TakeWarnings")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "the first run with the flag on")
	Set warnings = $ClassMethod("OcuTalon.Install.Step", "TakeWarnings")
	Do $$$AssertTrue($ListValid(warnings) && ($ListToString(warnings) [ ..Readme), "disables the README account and warns, naming it")
	Do $$$AssertEquals($Piece(..Account(..Readme), "|", 1), 0, "the README account is disabled")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "the next run with the flag on")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Install.Step", "TakeWarnings"), "", "gives no warning: the account is already disabled")
	Do $$$AssertEquals($Piece(..Account(..Readme), "|", 1), 0, "and it stays disabled")
}

/// The flag turned off again on a kept volume: every account that the step made for the online demo is disabled, with a warning that names
/// it, and keeps its roles, flags, password and marker; no account is deleted, and the README account that the run makes is enabled. A later
/// run with the flag off warns no more, and the flag on again puts the published accounts back.
Method TestFlagOffDisablesThePublicAccounts()
{
	Set step = ..#STEP
	Do ..SetPublic(1, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "Accounts makes the published accounts with the flag on")
	Set accounts = $ListBuild($ListBuild(..Demo, "Zz-demo-pw-1", ..Account(..Demo, 1)), $ListBuild(..Ro, "Zz-ro-pw-1", ..Account(..Ro, 1)))
	Do ..SetPublic(0, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $ClassMethod("OcuTalon.Install.Step", "TakeWarnings")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "Accounts runs with the flag off")
	Set warnings = $ListToString($ClassMethod("OcuTalon.Install.Step", "TakeWarnings"))
	Set position = 0
	While $ListNext(accounts, position, account) {
		Set name = $List(account, 1)
		Set before = $List(account, 3)
		Set after = ..Account(name)
		Do $$$AssertEquals($Piece(before, "|", 1), 1, name_" was enabled with the flag on")
		Do $$$AssertEquals($Piece(after, "|", 1), 0, name_" is disabled with the flag off, and not deleted")
		Do $$$AssertEquals($Piece(after, "|", 2, $Length(after, "|")), $Piece(before, "|", 2, $Length(before, "|")), name_" keeps its flags, roles and password")
		Do $$$AssertTrue(..PasswordOk(name, $List(account, 2)), name_" keeps its published password, so it is the disabled flag that stops the sign-in")
		Do $$$AssertEquals(..FullName(name), $Parameter(step, "MARKER"), name_" keeps its marker")
		Do $$$AssertTrue(warnings [ name, "the step warns, naming "_name_": "_warnings)
	}
	Do $$$AssertEquals($Piece(..Account(..Readme), "|", 1), 1, "the README account that the run makes is enabled")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "the next run with the flag off")
	Do $$$AssertEquals($ClassMethod("OcuTalon.Install.Step", "TakeWarnings"), "", "gives no warning: the accounts are already disabled")
	Do ..SetPublic(1, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(step, "Accounts", ..Readme), "the flag on again")
	Do ..AssertPublic($ListBuild($ListBuild(..Demo, "Zz-demo-pw-1", "OcuTalonTraceViewer,OcuTalonUser"), $ListBuild(..Ro, "Zz-ro-pw-1", "OcuTalonTraceViewer")), "with the flag on again")
}

/// Row 10, where the account is written: EnsurePublic rewrites only an account that the step made (its FullName is the marker). An account
/// that the step did not make keeps its password, roles, flags and name. The control makes the account the step's own and rewrites it.
Method TestEnsurePublicRefusesAForeignAccount()
{
	Set step = ..#STEP
	Set name = ..Demo
	Do $$$AssertStatusOK($ClassMethod(step, "Ensure", name, "Zz-foreign-pw-1", ..Roles), "an account the step did not make exists under the public name")
	Set before = ..Account(name, 1)
	Set foreignName = ..FullName(name)
	Set sc = $ClassMethod(step, "EnsurePublic", name, "Zz-demo-pw-1", $Parameter(step, "DEMOROLES"))
	Set text = $SYSTEM.Status.GetErrorText(sc)
	Do $$$AssertStatusNotOK(sc, "EnsurePublic refuses it")
	Do $$$AssertTrue((text [ name) && (text [ "OcuTalon.Install.Step.Users"), "and the error names the account and the step: "_text)
	Do $$$AssertEquals(..Account(name), before, "its roles, flags, password hash and salt are as they were")
	Do $$$AssertTrue(..PasswordOk(name, "Zz-foreign-pw-1"), "and it keeps its password")
	Do $$$AssertEquals(..FullName(name), foreignName, "and its name")

	Do ..Remove(name)
	Do $$$AssertStatusOK($ClassMethod(step, "EnsurePublic", name, "Zz-demo-pw-1", $Parameter(step, "DEMOROLES")), "control: it makes the account when there is none")
	Do $$$AssertStatusOK($ClassMethod(step, "EnsurePublic", name, "Zz-demo-pw-2", $Parameter(step, "DEMOROLES")), "and rewrites an account that it made")
	Do $$$AssertTrue(..PasswordOk(name, "Zz-demo-pw-2"), "with the new password")
	Do $$$AssertEquals(..FullName(name), $Parameter(step, "MARKER"), "and its marker")
}

/// Task step 5: the page size is pinned in each namespace of TRACENAMESPACES that exists, and a name in the list that is no namespace is
/// skipped without an error (an install that has no OCUORDERS). The fixture step lists a missing namespace first and then OCUTALON, and
/// leaves OCUORDERS out, so the pin of a namespace that is not in the list would show too.
Method TestPinSkipsANamespaceThatDoesNotExist()
{
	Set pins = ..#PINS
	Do $$$AssertEquals($Parameter(pins, "TRACENAMESPACES"), "ZZNOSUCHNAMESPACE,OCUTALON", "the fixture step names a missing namespace, then OCUTALON")
	Do $$$AssertNotTrue(##class(%SYS.Namespace).Exists("ZZNOSUCHNAMESPACE"), "that namespace does not exist")
	Do $$$AssertStatusOK($ClassMethod(pins, "PinTrace", ..Demo), "PinTrace skips it without an error")
	Do $$$AssertEquals($Get(^|"OCUTALON"|EnsPortal.Settings(..Demo, "VisualTrace", "ItemsPerPage")), $Parameter(..#STEP, "TRACEPAGESIZE"), "and pins the namespace that exists")
	Do $$$AssertEquals($Data(^|"OCUORDERS"|EnsPortal.Settings(..Demo)), 0, "and pins no namespace that is not in the list")
}

/// Matrix row 9: with the flag on, Accounts sets the guard as the literal Check^OcuTalonPasswordGuard, and the routine's source holds
/// neither published password. For each public account, a Modify to another password is refused and the password is unchanged, and so is
/// a sign-in request with the old and the new password with the name in capitals. A user that is not public changes its password with the
/// same request, as the control.
Method TestGuardWithFlagOn()
{
	Set guard = "OcuTalon.Test.Install.PasswordGuard"
	Set accounts = $ListBuild($ListBuild(..Demo, "Zz-demo-pw-1"), $ListBuild(..Ro, "Zz-ro-pw-1"))
	Do ..SetPublic(1, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Accounts", ..Readme), "Accounts runs with the flag on")
	Do $$$AssertEquals($ClassMethod(guard, "Setting"), "Check^OcuTalonPasswordGuard", "the instance's password-validation routine is the guard")
	Set source = $ClassMethod(guard, "Source")
	Do $$$AssertTrue(source '= "", "the guard routine exists and has source")
	Do $$$AssertNotTrue(source [ "Zz-demo-pw-1", "the source holds no demo password")
	Do $$$AssertNotTrue(source [ "Zz-ro-pw-1", "and no read-only password")
	Do $$$AssertTrue(source [ $ZConvert(..Demo, "L"), "the source holds the demo account's name in lower case")
	Set position = 0
	While $ListNext(accounts, position, account) {
		Set name = $List(account, 1)
		Set password = $List(account, 2)
		Set sc = $ClassMethod(guard, "TryPassword", name, "Zz-other-pw-9")
		Do $$$AssertStatusNotOK(sc, name_": Security.Users.Modify to another password is refused")
		Do $$$AssertTrue($ClassMethod(guard, "PasswordOk", name, password), name_" keeps its published password")
		Do $$$AssertStatusOK($ClassMethod(guard, "TryPassword", name, password), name_": the published password itself is allowed")
		Set status = $ClassMethod(guard, "SignInChange", $ZConvert(name, "U"), password, "Zz-other-pw-9")
		Do $$$AssertTrue(status > 0, name_": the sign-in request is answered, status "_status)
		Do $$$AssertTrue($ClassMethod(guard, "PasswordOk", name, password), name_": a sign-in change with the name in capitals leaves the published password")
		Do $$$AssertNotTrue($ClassMethod(guard, "PasswordOk", name, "Zz-other-pw-9"), name_" does not have the new password")
	}
	Do $$$AssertStatusOK(..MakeControl("Zz-ctl-pw-1"), "the control user is made")
	Set status = $ClassMethod(guard, "SignInChange", $ZConvert(..Ctl, "U"), "Zz-ctl-pw-1", "Zz-ctl-pw-2")
	Do $$$AssertTrue(status > 0, "the sign-in request of the control is answered, status "_status)
	Do $$$AssertTrue($ClassMethod(guard, "PasswordOk", ..Ctl, "Zz-ctl-pw-2"), "control: a user that is not public changes its password with the same request, the name in capitals")
	Do $$$AssertStatusOK($ClassMethod(guard, "TryPassword", ..Ctl, "Zz-ctl-pw-3"), "control: and by Security.Users.Modify")
	Do $$$AssertTrue($ClassMethod(guard, "PasswordOk", ..Ctl, "Zz-ctl-pw-3"), "control: the password is the new one")
}

/// The generated routine's own answer (Check^OcuTalonPasswordGuard, as IRIS calls it): a public account gets 1 only for its published
/// password, whatever the case of the name and also with a domain after it (as IRIS passes the name when multiple domains are enabled);
/// the other account's published password, an empty password and the password with a character added are refused; and a name that is not
/// public (one that extends or shortens a public name, with or without a domain, or an empty one) gets 1 for any password.
Method TestGuardDecidesByNameAndPassword()
{
	Set guard = "OcuTalon.Test.Install.PasswordGuard"
	Set accounts = $ListBuild($ListBuild(..Demo, "Zz-demo-pw-1", "Zz-ro-pw-1"), $ListBuild(..Ro, "Zz-ro-pw-1", "Zz-demo-pw-1"))
	Do ..SetPublic(1, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Accounts", ..Readme), "Accounts runs with the flag on")
	Set position = 0
	While $ListNext(accounts, position, account) {
		Set name = $List(account, 1)
		Set password = $List(account, 2)
		Set mixed = $ZConvert($Extract(name, 1, 4), "U")_$Extract(name, 5, *)
		Do $$$AssertStatusOK($ClassMethod(guard, "Check", name, password), name_": its published password is allowed")
		Do $$$AssertStatusOK($ClassMethod(guard, "Check", $ZConvert(name, "U"), password), name_": and with the name in capitals")
		Do $$$AssertStatusOK($ClassMethod(guard, "Check", mixed, password), name_": and with the name in mixed case")
		Do $$$AssertStatusNotOK($ClassMethod(guard, "Check", name, password_"x"), name_": the published password with a character added is refused")
		Do $$$AssertStatusNotOK($ClassMethod(guard, "Check", $ZConvert(name, "U"), password_"x"), name_": also with the name in capitals")
		Do $$$AssertStatusNotOK($ClassMethod(guard, "Check", mixed, "Zz-other-pw-9"), name_": another password with the name in mixed case is refused")
		Do $$$AssertStatusNotOK($ClassMethod(guard, "Check", name, ""), name_": an empty password is refused")
		Do $$$AssertStatusNotOK($ClassMethod(guard, "Check", name, $List(account, 3)), name_": the other account's published password is refused")
		Do $$$AssertStatusNotOK($ClassMethod(guard, "Check", $ZConvert(name, "L")_"@zzdomain", "Zz-other-pw-9"), name_"@zzdomain, the name with a domain, is refused another password")
		Do $$$AssertStatusOK($ClassMethod(guard, "Check", $ZConvert(name, "U")_"@ZZDOMAIN", password), name_" with a domain is allowed its published password")
		Do $$$AssertStatusOK($ClassMethod(guard, "Check", name_"x", "Zz-other-pw-9"), name_"x is not public, so any password is allowed")
		Do $$$AssertStatusOK($ClassMethod(guard, "Check", name_"x@zzdomain", "Zz-other-pw-9"), name_"x with a domain is not public either")
		Do $$$AssertStatusOK($ClassMethod(guard, "Check", $Extract(name, 1, *-1), ""), $Extract(name, 1, *-1)_" is not public either")
	}
	Do $$$AssertStatusOK($ClassMethod(guard, "Check", ..Ctl, "Zz-ctl-pw-9"), "the control user is not public")
	Do $$$AssertStatusOK($ClassMethod(guard, "Check", "", "Zz-ctl-pw-9"), "and an empty name is not public")
}

/// Matrix row 10: after row 9, the published passwords are changed in the settings and Accounts runs again. It is OK, each account holds the
/// new password, and the guard refuses the old one: the guard is written before the passwords.
Method TestInstallerWritesAChangedPassword()
{
	Set guard = "OcuTalon.Test.Install.PasswordGuard"
	Do ..SetPublic(1, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Accounts", ..Readme), "Accounts runs with the first passwords")
	Do ..SetPublic(1, ..Demo, "Zz-demo-pw-2", ..Ro, "Zz-ro-pw-2")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Accounts", ..Readme), "Accounts runs again with other published passwords")
	Do $$$AssertTrue($ClassMethod(guard, "PasswordOk", ..Demo, "Zz-demo-pw-2"), "the demo account holds the new password")
	Do $$$AssertTrue($ClassMethod(guard, "PasswordOk", ..Ro, "Zz-ro-pw-2"), "the read-only account holds the new password")
	Do $$$AssertStatusNotOK($ClassMethod(guard, "TryPassword", ..Demo, "Zz-demo-pw-1"), "the guard now refuses the old demo password")
	Do $$$AssertStatusNotOK($ClassMethod(guard, "TryPassword", ..Ro, "Zz-ro-pw-1"), "and the old read-only password")
	Do $$$AssertTrue($ClassMethod(guard, "PasswordOk", ..Demo, "Zz-demo-pw-2"), "the demo account keeps the new password")
}

/// Matrix row 11: with the flag off, Accounts leaves the setting "" and writes no routine. After a flag-on run, the first flag-off run clears
/// the setting, deletes the routine and warns once of it; the second warns of nothing.
Method TestNoGuardWithFlagOff()
{
	Set guard = "OcuTalon.Test.Install.PasswordGuard"
	Set routine = $Parameter(..#STEP, "GUARDROUTINE")
	Do $ClassMethod(guard, "Restore", $ListBuild("", 0, ""))
	Do ..SetPublic(0, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Accounts", ..Readme), "Accounts runs with the flag off")
	Do $$$AssertEquals($ClassMethod(guard, "Setting"), "", "the setting is empty")
	Do $$$AssertNotTrue($ListGet($ClassMethod(guard, "State"), 2), "and no guard routine exists")

	Do ..SetPublic(1, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Accounts", ..Readme), "Accounts runs with the flag on")
	Do $$$AssertEquals($ClassMethod(guard, "Setting"), "Check^OcuTalonPasswordGuard", "the guard is set")
	Do $$$AssertTrue($ListGet($ClassMethod(guard, "State"), 2), "and its routine exists")

	Do ..SetPublic(0, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $ClassMethod("OcuTalon.Install.Step", "TakeWarnings")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Accounts", ..Readme), "the first run with the flag off")
	Do $$$AssertEquals($ClassMethod(guard, "Setting"), "", "clears the setting")
	Do $$$AssertNotTrue($ListGet($ClassMethod(guard, "State"), 2), "and deletes the routine")
	Do $$$AssertEquals(..Warned(routine), 1, "and warns once of the guard")

	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Accounts", ..Readme), "the second run with the flag off")
	Do $$$AssertEquals(..Warned(routine), 0, "warns of no guard")
}

/// With the flag off, a guard routine that is left without the setting (an interrupted start) is deleted all the same, with one warning,
/// and the setting stays "".
Method TestFlagOffRemovesALeftoverGuardRoutine()
{
	Set guard = "OcuTalon.Test.Install.PasswordGuard"
	Set routine = $Parameter(..#STEP, "GUARDROUTINE")
	Do $ClassMethod(guard, "Restore", $ListBuild("", 0, ""))
	Do $$$AssertStatusOK($ClassMethod(guard, "Write", routine_" ; a leftover, for a test"_$Char(10)_$Char(9)_"Quit"_$Char(10)), "a guard routine exists")
	Do $$$AssertEquals($ClassMethod(guard, "Setting"), "", "and the setting is empty")
	Do $$$AssertTrue($ListGet($ClassMethod(guard, "State"), 2), "the routine is there before the step")
	Do ..SetPublic(0, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $ClassMethod("OcuTalon.Install.Step", "TakeWarnings")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Accounts", ..Readme), "Accounts runs with the flag off")
	Do $$$AssertNotTrue($ListGet($ClassMethod(guard, "State"), 2), "the leftover routine is deleted")
	Do $$$AssertEquals($ClassMethod(guard, "Setting"), "", "and the setting is still empty")
	Do $$$AssertEquals(..Warned(routine), 1, "with one warning")
}

/// Matrix row 12: another routine in the setting. With the flag on, Accounts is refused, naming it, with no public account made and the
/// setting unchanged. With the flag off, the setting is unchanged and there is no warning.
Method TestForeignGuardIsRefused()
{
	Set guard = "OcuTalon.Test.Install.PasswordGuard"
	Set foreign = "ZzOther^ZzForeign"
	Do $ClassMethod(guard, "Restore", $ListBuild("", 0, ""))
	Do $$$AssertStatusOK(..MakeForeign(), "the foreign routine exists")
	Do $$$AssertStatusOK($ClassMethod(guard, "SetSetting", foreign), "the instance's password-validation routine is another routine")
	Do ..SetPublic(1, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Set sc = $ClassMethod(..#STEP, "Accounts", ..Readme)
	Do $$$AssertStatusNotOK(sc, "Accounts with the flag on is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ foreign, "and the error names the routine: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals(..Account(..Demo), "<none>", "no demo account is made")
	Do $$$AssertEquals(..Account(..Ro), "<none>", "and no read-only account")
	Do $$$AssertEquals($ClassMethod(guard, "Setting"), foreign, "the setting is unchanged")
	Do $$$AssertNotTrue($ListGet($ClassMethod(guard, "State"), 2), "and no guard routine is written")
	Do $$$AssertTrue($ClassMethod(guard, "RoutineExists", "ZzForeign"), "and the foreign routine still exists")

	Do ..SetPublic(0, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $ClassMethod("OcuTalon.Install.Step", "TakeWarnings")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Accounts", ..Readme), "Accounts with the flag off runs")
	Do $$$AssertEquals($ClassMethod(guard, "Setting"), foreign, "the setting is unchanged")
	Do $$$AssertTrue($ClassMethod(guard, "RoutineExists", "ZzForeign"), "and the foreign routine still exists")
	Do $$$AssertEquals(..Warned("ZzForeign,"_$Parameter(..#STEP, "GUARDROUTINE")), 0, "and nothing is warned of either routine")
}

/// A guard that fails its check refuses the step: the demo account's name holds a line feed, which the routine's writer drops, so the
/// generated routine does not match the name and allows it another password. The instance's password-validation setting stays as it was,
/// no guard routine is written (it is checked under the staging name first, which is deleted), and no public account is made.
Method TestFailedGuardLeavesTheSetting()
{
	Set guard = "OcuTalon.Test.Install.PasswordGuard"
	Do $ClassMethod(guard, "Restore", $ListBuild("", 0, ""))
	Do ..SetPublic(1, ..Demo_$Char(10)_"x", "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Set sc = $ClassMethod(..#STEP, "Accounts", ..Readme)
	Do $$$AssertStatusNotOK(sc, "Accounts is refused when the guard fails its check")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "the password guard", "by the guard: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals($ClassMethod(guard, "Setting"), "", "the setting is as it was")
	Do $$$AssertNotTrue($ClassMethod(guard, "RoutineExists", $Parameter(..#STEP, "GUARDROUTINE")), "no guard routine is written")
	Do $$$AssertNotTrue($ClassMethod(guard, "RoutineExists", $Parameter(..#STEP, "GUARDSTAGE")), "and no staging routine is left")
	Do $$$AssertEquals(..Account(..Ro), "<none>", "and no read-only account is made")
}

/// A later start whose new guard fails its check (the demo account's name with a line feed, as above) leaves the guard that an earlier start
/// set exactly as it was: the setting and the live routine's source. The live guard still refuses another password for the demo account
/// and allows any for a user that is not public, so the instance's other password changes keep working. No staging routine is left.
Method TestFailedGuardKeepsTheLiveGuard()
{
	Set guard = "OcuTalon.Test.Install.PasswordGuard"
	Do ..SetPublic(1, ..Demo, "Zz-demo-pw-1", ..Ro, "Zz-ro-pw-1")
	Do $$$AssertStatusOK($ClassMethod(..#STEP, "Accounts", ..Readme), "an earlier start sets the guard")
	Set before = $ClassMethod(guard, "State")
	Do $$$AssertEquals($List(before, 1), "Check^OcuTalonPasswordGuard", "the guard is set before the later start")
	Do ..SetPublic(1, ..Demo_$Char(10)_"x", "Zz-demo-pw-2", ..Ro, "Zz-ro-pw-2")
	Set sc = $ClassMethod(..#STEP, "Accounts", ..Readme)
	Do $$$AssertStatusNotOK(sc, "the later start is refused")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "the password guard", "by the guard: "_$SYSTEM.Status.GetErrorText(sc))
	Do $$$AssertEquals($ClassMethod(guard, "Leak", before), "", "the setting and the live routine are as the earlier start left them")
	Do $$$AssertStatusNotOK($ClassMethod(guard, "Check", ..Demo, "Zz-other-pw-9"), "the live guard still refuses the demo account another password")
	Do $$$AssertStatusOK($ClassMethod(guard, "Check", ..Ctl, "Zz-ctl-pw-9"), "and allows any password for a user that is not public")
	Do $$$AssertTrue($ClassMethod(guard, "PasswordOk", ..Demo, "Zz-demo-pw-1"), "the demo account keeps the password of the earlier start")
	Do $$$AssertNotTrue($ClassMethod(guard, "RoutineExists", $Parameter(..#STEP, "GUARDSTAGE")), "no staging routine is left")
}

/// --- fixtures ---
/// Enabled|ChangePassword|PasswordNeverExpires|AccountNeverExpires|Roles|length of the hash|hash and salt of the password, or
/// "<none>". The hash and the salt are binary and come last, so a "|" in them does not move the fields before them.
/// With wait set, the account is opened again (the handle is killed, then Exists runs again) up to 20 times, 0.1 second apart,
/// until its password hash is not empty; the last read is the answer.
Method Account(user As %String, wait As %Boolean = 0) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set attempts = $Select(wait: 20, 1: 1)
	For attempt = 1:1:attempts {
		Kill object
		If '##class(Security.Users).Exists(user, .object) Quit
		If (object.Password '= "") || (attempt = attempts) Quit
		Hang 0.1
	}
	If '$IsObject($Get(object)) Quit "<none>"
	Set roles = ""
	For i = 1:1:object.Roles.Count() {
		Set roles = roles_$Select(roles = "": "", 1: ",")_object.Roles.GetAt(i)
	}
	Quit ..Line(object.Enabled, object.ChangePassword, object.PasswordNeverExpires, object.AccountNeverExpires, roles, object.Password, object.Salt)
}

/// The account line of Account, from the account's flags, its roles (a comma list), and its hash and salt.
ClassMethod Line(enabled, changePassword, neverExpires, accountNeverExpires, roles As %String, hash As %String, salt As %String) As %String [ Private ]
{
	Quit enabled_"|"_changePassword_"|"_neverExpires_"|"_accountNeverExpires_"|"_roles_"|"_$Length(hash)_"|"_hash_salt
}

/// Asserts, for each of the published accounts $ListBuild(name, password, sorted roles), that it holds exactly its roles and no escalation
/// role, is enabled, has
/// neither a forced change nor an expiry, carries the installer's marker, has its published password (and not another), has its page size
/// pinned to 100 in OCUTALON and in OCUORDERS, and that it cannot write the database that holds the page settings in either namespace.
Method AssertPublic(accounts As %List, when As %String) [ Private ]
{
	Set pinned = $Parameter(..#STEP, "TRACEPAGESIZE")
	Set position = 0
	While $ListNext(accounts, position, account) {
		Set name = $List(account, 1)
		Set line = ..Account(name, 1)
		Do $$$AssertEquals(..SortedRoles(line), $List(account, 3), name_" holds exactly its roles "_when)
		Do $$$AssertEquals(..EscalationRoles(name), "", name_" holds no escalation role "_when)
		Do $$$AssertEquals($Piece(line, "|", 1, 4), "1|0|1|1", name_" is enabled, with no forced change and no expiry "_when)
		Do $$$AssertEquals(..FullName(name), $Parameter(..#STEP, "MARKER"), name_" carries the installer's marker "_when)
		Do $$$AssertTrue(..PasswordOk(name, $List(account, 2)), name_" has its published password "_when)
		Do $$$AssertTrue('..PasswordOk(name, "Zz-other-pw-9"), name_" does not have another password "_when)
		For namespace = "OCUTALON", "OCUORDERS" {
			Do $$$AssertEquals($Get(^|namespace|EnsPortal.Settings(name, "VisualTrace", "ItemsPerPage")), pinned, name_"'s page size is pinned to "_pinned_" in "_namespace_" "_when)
			Set resource = ..SettingsResource(namespace)
			Do $$$AssertTrue(resource '= "", "the database of the page settings of "_namespace_" has the resource "_resource)
			Do $$$AssertEquals(+$SYSTEM.Security.CheckUserPermission(name, resource, "W"), 0, name_" cannot write "_resource_" "_when)
		}
	}
}

/// The number of the step's warnings since the last TakeWarnings that contain any of the comma-separated texts. The warnings are taken.
ClassMethod Warned(texts As %String) As %Integer [ Private ]
{
	Set warnings = ##class(OcuTalon.Install.Step).TakeWarnings()
	Set count = 0
	Set position = 0
	While $ListValid(warnings) && $ListNext(warnings, position, warning) {
		Set found = 0
		For i = 1:1:$Length(texts, ",") {
			If warning [ $Piece(texts, ",", i) Set found = 1
		}
		Set count = count + found
	}
	Quit count
}

/// The control user ZzUsers<n>Ctl, who is not public, with the password: enabled, no forced change, and the user role. Runs in %SYS.
Method MakeControl(password As %String) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ##class(Security.Users).Create(..Ctl, "OcuTalonUser", password, "OcuTalon test fixture", "OCUTALON", "", "", 0, 1, "Created by a test; the test deletes it.", 1, "", "", , 1, 1)
}

/// The routine ZzForeign in %SYS with the entry ZzOther, which allows every password. Runs in %SYS.
ClassMethod MakeForeign() As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set routine = ##class(%Routine).%New("ZzForeign.mac")
	Do routine.WriteLine("ZzForeign ; a test fixture, another password-validation routine")
	Do routine.WriteLine($Char(9)_"Quit")
	Do routine.WriteLine("ZzOther(user,password) Public {")
	Do routine.WriteLine($Char(9)_"Quit 1")
	Do routine.WriteLine("}")
	Set sc = routine.Save()
	If $$$ISOK(sc) Set sc = routine.Compile("-d")
	Quit sc
}

/// Deletes the routine ZzForeign when it exists. Runs in %SYS.
ClassMethod RemoveForeign() [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(%Routine).Exists("ZzForeign.mac") Do ##class(%Routine).Delete("ZzForeign.mac", 0)
}

/// The public keys, set through the accessor.
Method SetPublic(flag As %String, demoUser As %String, demoPassword As %String, readonlyUser As %String, readonlyPassword As %String) [ Private ]
{
	Set accessor = "OcuTalon.Data.Public.Settings"
	Do $$$AssertStatusOK($ClassMethod(accessor, "Set", "onlineDemo", flag), "onlineDemo is "_flag)
	Do $ClassMethod(accessor, "Set", "demoUser", demoUser)
	Do $ClassMethod(accessor, "Set", "demoPassword", demoPassword)
	Do $ClassMethod(accessor, "Set", "readonlyUser", readonlyUser)
	Do $ClassMethod(accessor, "Set", "readonlyPassword", readonlyPassword)
}

/// The resource of the database that ^EnsPortal.Settings resolves to in the namespace.
ClassMethod SettingsResource(namespace As %String) As %String [ Private ]
{
	Set directory = $Piece(##class(%SYS.Namespace).GetGlobalDest(namespace, "^EnsPortal.Settings"), "^", 2)
	New $Namespace
	Set $Namespace = "%SYS"
	Set database = ##class(SYS.Database).%OpenId(directory)
	Quit $Select($IsObject(database): database.ResourceName, 1: "")
}

/// 1 when the password is the user's current one (Test.Install.PasswordGuard.PasswordOk).
ClassMethod PasswordOk(user As %String, password As %String) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Test.Install.PasswordGuard).PasswordOk(user, password)
}

/// The escalation roles of a user as a comma list. Runs in %SYS.
ClassMethod EscalationRoles(user As %String) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Do ##class(Security.Users).Get(user, .properties)
	Quit $Get(properties("EscalationRoles"))
}

ClassMethod FullName(user As %String) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If '##class(Security.Users).Exists(user, .object) Quit ""
	Quit object.FullName
}

/// The roles of an account line as a comma list in sorted order.
ClassMethod SortedRoles(line As %String) As %String [ Private ]
{
	Quit ..Sorted($Piece(line, "|", 5))
}

/// A comma list in sorted order.
ClassMethod Sorted(list As %String) As %String [ Private ]
{
	Set items = $ListFromString(list)
	Set position = 0
	While $ListNext(items, position, item) {
		Set sorted(item) = ""
	}
	Set result = ""
	Set item = ""
	For {
		Set item = $Order(sorted(item))
		Quit:item=""
		Set result = result_$Select(result = "": "", 1: ",")_item
	}
	Quit result
}

/// Sets one property of a user. Runs in %SYS.
ClassMethod SetProperty(user As %String, property As %String, value As %String) [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set properties(property) = value
	Do ##class(Security.Users).Modify(user, .properties)
}

ClassMethod UserExists(user As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ''##class(Security.Users).Exists(user)
}

ClassMethod RoleExists(role As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ''##class(Security.Roles).Exists(role)
}

ClassMethod CreateRole(role As %String) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ##class(Security.Roles).Create(role, "OcuTalon test fixture", "")
}

ClassMethod RemoveRole(role As %String) [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Roles).Exists(role) Do ##class(Security.Roles).Delete(role)
}

/// Removes the fixture README, demo, read-only and service accounts and the page size nodes of every fixture name.
Method ClearAccounts() [ Private ]
{
	Do ..Remove(..Readme)
	Do ..Remove(..Demo)
	Do ..Remove(..Ro)
	Do ..Remove("ZzUsers"_..Number_"Svc")
	Do ..Remove(..Ctl)
	Do ..ClearNodes()
	Do ..ClearPins()
}

/// Kills the page size settings of every fixture name in OCUTALON and in OCUORDERS.
ClassMethod ClearPins() [ Private ]
{
	Do ##class(OcuTalon.Test.Install.PasswordGuard).ClearPins("ZzUsers")
}

Method SetFlags(user As %String, enabled As %Boolean, changePassword As %Boolean, neverExpires As %Boolean) [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set properties("Enabled") = enabled
	Set properties("ChangePassword") = changePassword
	Set properties("PasswordNeverExpires") = neverExpires
	Do ##class(Security.Users).Modify(user, .properties)
}

Method CreateRoles() As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set sc = $SYSTEM.Status.OK()
	Set list = $ListFromString(..Roles)
	Set position = 0
	While $ListNext(list, position, role) {
		Set sc = ##class(Security.Roles).Create(role, "OcuTalon test fixture", "")
		If $SYSTEM.Status.IsError(sc) Quit
	}
	Quit sc
}

Method Remove(user As %String) [ Private ]
{
	Do ##class(OcuTalon.Test.Install.PasswordGuard).RemoveUser(user)
}

/// Kills every node of the class's test global but the counter n.
ClassMethod ClearNodes() [ Private ]
{
	Set node = ""
	For {
		Set node = $Order(^OcuTalonTest("Users", node))
		Quit:node=""
		If node '= "n" Kill ^OcuTalonTest("Users", node)
	}
}

/// Deletes every fixture user and role that an earlier run may have left, and the fixture's nodes but the counter.
ClassMethod Clean() [ Private ]
{
	Do ..RemoveForeign()
	Do ..ClearNodes()
	Do ..ClearPins()
	Do ##class(OcuTalon.Test.Install.PasswordGuard).RemoveUsers("ZzUsers")
	New $Namespace
	Set $Namespace = "%SYS"
	Set statement = ##class(%SQL.Statement).%New()
	Do statement.%Prepare("SELECT Name FROM Security.Roles WHERE Name %STARTSWITH 'ZzUsers'")
	Set result = statement.%Execute()
	While result.%Next() {
		Do ##class(Security.Roles).Delete(result.%GetData(1))
	}
}

}
