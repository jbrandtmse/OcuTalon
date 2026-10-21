/// Tests of the Users step (matrix row 16): the account is seed (AD-19). The fixture's user and roles are
/// created in OnBeforeAllTests and removed in OnAfterAllTests; the real README account is never touched. The fixture's number
/// comes from ^OcuTalonTest("Users","n"), which is never reset, so no two runs share a fixture name.
Class OcuTalon.Test.Install.Users Extends %UnitTest.TestCase
{

/// The fixture's number, from a counter that Clean leaves alone: the user is ZzUsers<n> and the roles are ZzUsers<n>RoleA and
/// ZzUsers<n>RoleB.
Property Number As %Integer;

Property User As %String;

Property Roles As %String;

Method OnBeforeAllTests() As %Status
{
	Do ..Clean()
	Set ..Number = $Increment(^OcuTalonTest("Users", "n"))
	Set ..User = "ZzUsers"_..Number
	Set ..Roles = "ZzUsers"_..Number_"RoleA,ZzUsers"_..Number_"RoleB"
	Quit ..CreateRoles()
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
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
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(user) Do ##class(Security.Users).Delete(user)
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
	Do ..ClearNodes()
	New $Namespace
	Set $Namespace = "%SYS"
	Set statement = ##class(%SQL.Statement).%New()
	Do statement.%Prepare("SELECT Name FROM Security.Users WHERE Name %STARTSWITH 'ZzUsers'")
	Set result = statement.%Execute()
	While result.%Next() {
		Do ##class(Security.Users).Delete(result.%GetData(1))
	}
	Do statement.%Prepare("SELECT Name FROM Security.Roles WHERE Name %STARTSWITH 'ZzUsers'")
	Set result = statement.%Execute()
	While result.%Next() {
		Do ##class(Security.Roles).Delete(result.%GetData(1))
	}
}

}
