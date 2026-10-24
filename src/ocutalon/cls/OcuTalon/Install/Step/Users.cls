/// The Users step: the accounts of an install (AD-23, AD-24).
///   - The service user, SERVICEUSER, has login disabled, holds exactly the role SERVICEROLE and has a random password. A role and a user
///     cannot share a name, so the role has its own. The disabled login and the role are structural (AD-19), rewritten at every start; the
///     random password is seed, made when the user is created and never changed.
///   - On a local install (the online-demo flag is off) the README account: user "ocutalon" is created once, with the published password,
///     holding the three OcuTalon roles, a non-expiring password and no forced change. It is seed (AD-19): created when absent and never
///     changed afterwards, so a password changed as the README says survives every start and upgrade.
///   - On the online demo (the flag is on) the two published accounts of the public settings (AD-24): the demo account and the read-only
///     account, with their published password, exact roles and flags, and their Visual Trace page size pinned. They are structural, rewritten
///     at every start, and the step manages only an account that it made (its FullName is MARKER). The README account is never made there,
///     and one that exists is disabled, because the README publishes its password. With the flag off again, every account that the step
///     made for the online demo is disabled, never deleted, because its password is published.
/// The flag and the accounts are read only through OcuTalon.Data.Public.Settings (AD-19). The published settings are all checked before
/// anything is applied (PublicAccounts), so a refusal of them changes nothing. A refusal by the instance itself, such as a password that
/// its policy rejects, is the status of that call with the key named, and leaves what was applied before it. The step also declares the two
/// roles that hold no resource of their own: the applications grant the database access (AD-13).
Class OcuTalon.Install.Step.Users Extends OcuTalon.Install.Step
{

/// The README account's name.
Parameter USER = "ocutalon";

/// The published password, which the README says how to change.
Parameter PASSWORD = "ocutalon";

/// The roles of the README account. OcuTalonTraceViewer is declared by the Web step.
Parameter ROLES = "OcuTalonUser,OcuTalonAdmin,OcuTalonTraceViewer";

/// The service user: login disabled and a random password (AD-24).
Parameter SERVICEUSER = "OcuTalonService";

/// The service user's role. Its resources are the declarations of the Tools area.
Parameter SERVICEROLE = "OcuTalonServiceRole";

/// The roles of the online demo's account.
Parameter DEMOROLES = "OcuTalonUser,OcuTalonTraceViewer";

/// The roles of the online demo's read-only account.
Parameter READONLYROLES = "OcuTalonTraceViewer";

/// The Visual Trace page size that the public accounts are pinned to (AD-24, AD-26).
Parameter TRACEPAGESIZE = 100;

/// The FullName of an account that this step made for the online demo. The step manages no other account.
Parameter MARKER = "OcuTalon online-demo account";

/// The namespaces whose Visual Trace settings the public accounts are pinned in, each where it exists.
Parameter TRACENAMESPACES = "OCUTALON,OCUORDERS";

ClassMethod Run() As %Status
{
	Quit ..Accounts(..#USER)
}

/// OcuTalonUser and OcuTalonAdmin hold no resource.
ClassMethod Grants() As %DynamicArray
{
	Quit [{"role":"OcuTalonUser","resource":"","permission":""},{"role":"OcuTalonAdmin","resource":"","permission":""}]
}

/// The accounts of a start, in the order that makes a refusal change nothing:
///   1. the online-demo flag, read through Settings.Get (an error status fails the step);
///   2. flag on: the four account keys, all validated (PublicAccounts);
///   3. the service user (EnsureService);
///   4. flag off: every account made for the online demo disabled (DisablePublic), then the README account, readmeUser, as Ensure makes it;
///   5. flag on: the two public accounts (EnsurePublic), their page size pins (PinTrace), and the README account disabled when it exists.
ClassMethod Accounts(readmeUser As %String) As %Status
{
	Set flag = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo", .sc)
	If $$$ISERR(sc) Quit sc
	Set online = (flag = 1)
	If online {
		Set sc = ..PublicAccounts(readmeUser, .accounts)
		If $$$ISERR(sc) Quit sc
	}
	Set sc = ..EnsureService()
	If $$$ISERR(sc) Quit sc
	If 'online {
		Set sc = ..DisablePublic()
		If $$$ISERR(sc) Quit sc
		Quit ..Ensure(readmeUser, ..#PASSWORD, ..#ROLES)
	}
	For i = 1:1:accounts {
		Set name = $List(accounts(i), 1)
		Set key = $List(accounts(i), 4)_"' and '"_$List(accounts(i), 5)
		Set sc = ..EnsurePublic(name, $List(accounts(i), 2), $List(accounts(i), 3))
		If $$$ISERR(sc) Quit
		Set sc = ..PinTrace(name)
		If $$$ISERR(sc) Quit
	}
	If $$$ISERR(sc) Quit ..Fail("public settings '"_key_"' (account '"_name_"')", sc)
	Quit ..DisableReadme(readmeUser)
}

/// Creates the account when it does not exist, holding the comma list of roles, with PasswordNeverExpires 1,
/// ChangePassword 0, AccountNeverExpires 1 and Enabled 1. An account that exists is left exactly as it is:
/// password, roles and flags. Runs in %SYS.
ClassMethod Ensure(user As %String, password As %String, roles As %String) As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(user) Quit $SYSTEM.Status.OK()
	Quit ##class(Security.Users).Create(user, roles, password, "OcuTalon README account", "OCUTALON", "", "", 0, 1, "Created by the OcuTalon installer; the README says how to change the password.", 1, "", "", , 1, 1)
}

/// The service user: created once with login disabled, holding exactly the role, and a random password of 44 characters that nothing
/// reads (seed). A user that exists gets Enabled 0, exactly the role and no escalation role, and keeps its password. Runs in %SYS. The
/// role must exist.
ClassMethod EnsureService(user As %String = {..#SERVICEUSER}, role As %String = {..#SERVICEROLE}) As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(user) {
		Kill properties
		Set properties("Enabled") = 0
		Set properties("Roles") = role
		Set properties("EscalationRoles") = ""
		Set sc = ##class(Security.Users).Modify(user, .properties)
	} Else {
		Set sc = ##class(Security.Users).Create(user, role, ..NewPassword(), "OcuTalon service user", "OCUTALON", "", "", 0, 0, "Created by the OcuTalon installer; login is disabled.", 1, "", "", , 1, 1)
	}
	If $$$ISERR(sc) Quit ..Fail("service user '"_user_"' with role '"_role_"'", sc)
	Quit sc
}

/// A random password of 44 characters: 32 random bytes in Base64 with no line breaks.
ClassMethod NewPassword() As %String
{
	Quit $SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(32), 1)
}

/// A published account: created, or modified, to hold the password, exactly the roles and no escalation role, FullName MARKER, Enabled 1,
/// ChangePassword 0, PasswordNeverExpires 1 and AccountNeverExpires 1. An existing account that this step did not make (another FullName) is refused and
/// left as it is. Runs in %SYS.
ClassMethod EnsurePublic(name As %String, password As %String, roles As %String) As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(name, .user) {
		If user.FullName '= ..#MARKER Quit ..Refuse("the account '"_name_"' exists and the installer did not make it, so it is left as it is")
		Kill properties
		Set properties("Password") = password
		Set properties("Roles") = roles
		Set properties("EscalationRoles") = ""
		Set properties("FullName") = ..#MARKER
		Set properties("Enabled") = 1
		Set properties("ChangePassword") = 0
		Set properties("PasswordNeverExpires") = 1
		Set properties("AccountNeverExpires") = 1
		Quit ##class(Security.Users).Modify(name, .properties)
	}
	Quit ##class(Security.Users).Create(name, roles, password, ..#MARKER, "OCUTALON", "", "", 0, 1, "Published online-demo account; the installer rewrites it at every start.", 1, "", "", , 1, 1)
}

/// Pins the account's Visual Trace page size to TRACEPAGESIZE in each namespace of TRACENAMESPACES that exists (AD-24, AD-26): the viewer
/// reads ^EnsPortal.Settings(user, "VisualTrace", "ItemsPerPage"). It is idempotent, so a caller that makes one of those namespaces after
/// this step can call it again for the accounts.
ClassMethod PinTrace(name As %String) As %Status
{
	Set sc = $SYSTEM.Status.OK()
	Set namespaces = $ListFromString(..#TRACENAMESPACES)
	Set position = 0
	While $ListNext(namespaces, position, namespace) {
		If '##class(%SYS.Namespace).Exists(namespace) Continue
		Try {
			Set ^|namespace|EnsPortal.Settings(name, "VisualTrace", "ItemsPerPage") = ..#TRACEPAGESIZE
		} Catch exception {
			Set sc = $SYSTEM.Status.AppendStatus(sc, ..Refuse("the page size of '"_name_"' could not be pinned in "_namespace_": "_$SYSTEM.Status.GetErrorText(exception.AsStatus())))
		}
	}
	Quit sc
}

/// The published accounts as accounts = their count and accounts(n) = $ListBuild(name, password, roles, key of the name, key of the
/// password), validated before
/// anything is applied: every name and password is set, the two names differ without regard to case, no name is the service user, the
/// README account or a role, and no name is an existing account that this step did not make. A refusal names the key or the clash. The values
/// come only through Settings.Get.
ClassMethod PublicAccounts(readmeUser As %String, Output accounts) As %Status [ Private ]
{
	Kill accounts
	Set accounts = 0
	For kind = "demo", "readonly" {
		Set nameKey = kind_"User"
		Set passwordKey = kind_"Password"
		Set name = ##class(OcuTalon.Data.Public.Settings).Get(nameKey, .sc)
		If $$$ISOK(sc) Set password = ##class(OcuTalon.Data.Public.Settings).Get(passwordKey, .sc)
		If $$$ISERR(sc) Quit
		If name = "" Set sc = ..Refuse("public setting '"_nameKey_"' is empty, and the online demo needs it") Quit
		If password = "" Set sc = ..Refuse("public setting '"_passwordKey_"' is empty, and the online demo needs it") Quit
		Set accounts = accounts + 1
		Set accounts(accounts) = $ListBuild(name, password, $Select(kind = "demo": ..#DEMOROLES, 1: ..#READONLYROLES), nameKey, passwordKey)
	}
	If $$$ISERR(sc) Quit sc
	If $ZConvert($List(accounts(1), 1), "L") = $ZConvert($List(accounts(2), 1), "L") {
		Quit ..Refuse("public settings '"_$List(accounts(1), 4)_"' and '"_$List(accounts(2), 4)_"' name the same account '"_$List(accounts(1), 1)_"'")
	}
	For i = 1, 2 {
		Set name = $List(accounts(i), 1)
		Set key = $List(accounts(i), 4)
		If $ZConvert(name, "L") = $ZConvert(..#SERVICEUSER, "L") {
			Set sc = ..Refuse("public setting '"_key_"' names the service user '"_..#SERVICEUSER_"'")
		} ElseIf $ZConvert(name, "L") = $ZConvert(readmeUser, "L") {
			Set sc = ..Refuse("public setting '"_key_"' names the README account '"_readmeUser_"'")
		} ElseIf ..RoleExists(name) {
			Set sc = ..Refuse("public setting '"_key_"' names the role '"_name_"', and a role and a user cannot share a name")
		} ElseIf ..Foreign(name) {
			Set sc = ..Refuse("public setting '"_key_"' names the account '"_name_"', which exists and which the installer did not make")
		}
		If $$$ISERR(sc) Quit
	}
	Quit sc
}

/// 1 when a role of the name exists. Runs in %SYS.
ClassMethod RoleExists(name As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ''##class(Security.Roles).Exists(name)
}

/// 1 when an account of the name exists and this step did not make it (its FullName is not MARKER). Runs in %SYS.
ClassMethod Foreign(name As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If '##class(Security.Users).Exists(name, .user) Quit 0
	Quit (user.FullName '= ..#MARKER)
}

/// Disables the README account when it exists and is enabled (Disable). The online demo publishes its accounts on the splash screen, so
/// the README's published password must not sign in there.
ClassMethod DisableReadme(readmeUser As %String) As %Status [ Private ]
{
	Quit ..Disable(readmeUser, "The README account '"_readmeUser_"' exists on an online-demo instance and was disabled, because the README publishes its password")
}

/// Disables every account that this step made for the online demo (its FullName is MARKER) and that is enabled (Disable), because with
/// the flag off its published password must not sign in. No account is deleted. Runs in %SYS.
ClassMethod DisablePublic() As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Users WHERE FullName = ?", ..#MARKER)
	If result.%SQLCODE < 0 Quit ..Refuse("the online-demo accounts could not be listed: "_result.%Message)
	Set names = ""
	While result.%Next() {
		Set names = names _ $ListBuild(result.%GetData(1))
	}
	Set sc = $SYSTEM.Status.OK()
	Set position = 0
	While $ListNext(names, position, name) {
		Set sc = ..Disable(name, "The online-demo account '"_name_"' was disabled, because the online-demo flag is off and its password is published")
		If $$$ISERR(sc) Quit
	}
	Quit sc
}

/// Disables the account when it exists and is enabled, leaving its roles, password and name as they are, and warns with the text; an account
/// that is already disabled gives no warning. Runs in %SYS.
ClassMethod Disable(user As %String, warning As %String) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If '##class(Security.Users).Exists(user, .object) Quit $SYSTEM.Status.OK()
	If 'object.Enabled Quit $SYSTEM.Status.OK()
	Kill properties
	Set properties("Enabled") = 0
	Set sc = ##class(Security.Users).Modify(user, .properties)
	If $$$ISERR(sc) Quit ..Fail("the account '"_user_"'", sc)
	Do ..Warn(warning)
	Quit sc
}

/// An error status that names this step and what failed.
ClassMethod Refuse(text As %String) As %Status [ Private ]
{
	Quit $SYSTEM.Status.Error(5001, $ClassName()_": "_text)
}

/// The status of an operation with the step and what failed in front of its own text.
ClassMethod Fail(what As %String, sc As %Status) As %Status [ Private ]
{
	Quit $SYSTEM.Status.AppendStatus(..Refuse(what), sc)
}

}
