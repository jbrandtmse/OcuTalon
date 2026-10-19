/// Tests of the Users step (matrix row 16): the account is seed (AD-19). The fixture's user and roles are
/// created in OnBeforeAllTests and removed in OnAfterAllTests; the real README account is never touched.
Class OcuTalon.Test.Install.Users Extends %UnitTest.TestCase
{

/// The fixture's number: the user is ZzUsers<n> and the roles are ZzUsers<n>RoleA and ZzUsers<n>RoleB.
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

/// The first call creates the account with the README account's flags; the roles are the given ones.
Method TestEnsureCreates()
{
	Do ..Remove(..User)
	Do $$$AssertEquals(..Account(..User), "<none>", "no fixture account to begin with")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Users).Ensure(..User, "Zz-pw-first-1", ..Roles), "Ensure creates the account")
	Set account = ..Account(..User)
	Do $$$AssertEquals($Piece(account, "|", 1), 1, "Enabled")
	Do $$$AssertEquals($Piece(account, "|", 2), 0, "ChangePassword")
	Do $$$AssertEquals($Piece(account, "|", 3), 1, "PasswordNeverExpires")
	Do $$$AssertEquals($Piece(account, "|", 4), 1, "AccountNeverExpires")
	Do $$$AssertEquals($Piece(account, "|", 5), ..Roles, "the roles")
	Do $$$AssertTrue($Piece(account, "|", 6) '= "", "the account has a password hash")
}

/// A second call, with another password and other roles, changes nothing: hash, salt, roles and flags.
Method TestEnsureKeepsAnExistingAccount()
{
	Do ..Remove(..User)
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.Users).Ensure(..User, "Zz-pw-first-1", ..Roles), "Ensure creates the account")
	Set before = ..Account(..User)
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

/// --- fixtures ---
/// Enabled|ChangePassword|PasswordNeverExpires|AccountNeverExpires|Roles|hash and salt of the password, or "<none>".
Method Account(user As %String) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If '##class(Security.Users).Exists(user, .object) Quit "<none>"
	Set roles = ""
	For i = 1:1:object.Roles.Count() {
		Set roles = roles_$Select(roles = "": "", 1: ",")_object.Roles.GetAt(i)
	}
	Quit object.Enabled_"|"_object.ChangePassword_"|"_object.PasswordNeverExpires_"|"_object.AccountNeverExpires_"|"_roles_"|"_object.Password_object.Salt
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

/// Deletes every fixture user and role that an earlier run may have left, and the fixture's nodes.
ClassMethod Clean() [ Private ]
{
	Kill ^OcuTalonTest("Users")
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
