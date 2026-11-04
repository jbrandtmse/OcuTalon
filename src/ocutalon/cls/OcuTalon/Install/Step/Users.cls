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
/// The password guard (AD-13, AD-24), flag on: a password-validation routine of the instance, OcuTalonPasswordGuard in %SYS, which the
/// step generates at every start from the published accounts and sets as the instance's PasswordValidationRoutine, before it writes the
/// public accounts' passwords. For a public account (the name compared in lower case, with or without the domain that IRIS appends when
/// multiple domains are enabled) it allows only the published password, held as a salted SHA-512 hash and never in clear; for every other
/// name it allows any password. Each start's routine is first saved, compiled and checked (the name in capitals with the published password
/// passes, with another password fails) under the staging name GUARDSTAGE, and only then written over the live routine, checked again, and
/// set; a failure refuses the step with the setting as it was, and a failure in staging also leaves the live routine as it was. A setting
/// that names another routine refuses the step, with nothing changed. With the flag off no guard exists: the step clears the setting when
/// it names this guard, deletes the routine (and a staging routine left over), and warns once, only when it removed something; another
/// routine is never touched.
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

/// The password guard's routine, in %SYS.
Parameter GUARDROUTINE = "OcuTalonPasswordGuard";

/// The password guard's entry, as the instance's PasswordValidationRoutine names it.
Parameter GUARDENTRY = "Check^OcuTalonPasswordGuard";

/// The routine in %SYS that a start's guard is written to and checked under before it replaces the live one; deleted afterwards.
Parameter GUARDSTAGE = "OcuTalonPasswordGuardNew";

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
///   3. flag on: the instance's password-validation routine is "" or the guard's (CheckGuard);
///   4. the service user (EnsureService);
///   5. flag off: the guard removed (Unguard), every account made for the online demo disabled (DisablePublic), then the README account,
///      readmeUser, as Ensure makes it;
///   6. flag on: the guard written and set (Guard), the two public accounts (EnsurePublic), their page size pins (PinTrace), and the
///      README account disabled when it exists.
ClassMethod Accounts(readmeUser As %String) As %Status
{
	Set flag = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo", .sc)
	If $$$ISERR(sc) Quit sc
	Set online = (flag = 1)
	If online {
		Set sc = ..PublicAccounts(readmeUser, .accounts)
		If $$$ISERR(sc) Quit sc
		Set sc = ..CheckGuard()
		If $$$ISERR(sc) Quit sc
	}
	Set sc = ..EnsureService()
	If $$$ISERR(sc) Quit sc
	If 'online {
		Set sc = ..Unguard()
		If $$$ISERR(sc) Quit sc
		Set sc = ..DisablePublic()
		If $$$ISERR(sc) Quit sc
		Quit ..Ensure(readmeUser, ..#PASSWORD, ..#ROLES)
	}
	Set sc = ..Guard(.accounts)
	If $$$ISERR(sc) Quit sc
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

/// Refuses the step, naming the routine, when the instance's PasswordValidationRoutine is another routine than the guard's: it is
/// someone else's, and the installer neither replaces nor removes it. "" and the guard's entry pass. Runs in %SYS.
ClassMethod CheckGuard() As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set current = ..Validation(.sc)
	If $$$ISERR(sc) Quit ..Fail("the instance's password-validation routine", sc)
	If (current = "") || (current = ..#GUARDENTRY) Quit $SYSTEM.Status.OK()
	Quit ..Refuse("the instance's password-validation routine is '"_current_"', which is not the online demo's password guard, so the guard cannot be installed and nothing is changed")
}

/// The instance's PasswordValidationRoutine. Runs in %SYS.
ClassMethod Validation(Output sc As %Status) As %String [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill properties
	Set sc = ##class(Security.System).Get(, .properties)
	Quit $Get(properties("PasswordValidationRoutine"))
}

/// Sets the instance's PasswordValidationRoutine; "" clears it. Runs in %SYS.
ClassMethod SetValidation(value As %String) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill properties
	Set properties("PasswordValidationRoutine") = value
	Quit ##class(Security.System).Modify(, .properties)
}

/// Generates the guard for the accounts (accounts(n) as PublicAccounts builds them), writes and checks it under GUARDSTAGE, then writes the
/// same source over GUARDROUTINE, checks that, and only then sets it as the instance's PasswordValidationRoutine when it is not already.
/// The staging routine is deleted afterwards, whatever happened. A failure refuses the step and leaves the setting as it was, and a failure
/// in staging leaves the live routine as it was too: a routine that throws, or a setting that names a missing routine, would refuse every
/// password change of the instance, so a setting that already names the guard never comes to name a routine that was not checked. Runs
/// in %SYS.
ClassMethod Guard(ByRef accounts) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Try {
		Set source = ..GuardSource(.accounts)
		Set sc = ..WriteGuard(..#GUARDSTAGE, source)
		If $$$ISOK(sc) Set sc = ..CheckGuardRoutine(..#GUARDSTAGE, .accounts)
		If $$$ISOK(sc) Set sc = ..WriteGuard(..#GUARDROUTINE, source)
		If $$$ISOK(sc) Set sc = ..CheckGuardRoutine(..#GUARDROUTINE, .accounts)
		If $$$ISOK(sc), ..Validation() '= ..#GUARDENTRY Set sc = ..SetValidation(..#GUARDENTRY)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Try {
		If ##class(%Routine).Exists(..#GUARDSTAGE_".mac") Do ##class(%Routine).Delete(..#GUARDSTAGE_".mac", 0)
	} Catch {
	}
	If $$$ISERR(sc) Quit ..Fail("the password guard "_..#GUARDROUTINE, sc)
	Quit sc
}

/// The guard's source lines as a list. For each public account it holds the lower-cased name, a fresh random salt and the Base64 SHA-512
/// of salt and published password, and no password in clear. Check(user, password) lower-cases the user and takes the name both as it
/// is and before its last "@" (the domain that IRIS appends when multiple domains are enabled); for a public account's name it returns 1
/// only when the hash matches and otherwise an error status, and for every other name 1. It calls nothing but $SYSTEM and ObjectScript's
/// own functions, and switches no namespace.
ClassMethod GuardSource(ByRef accounts) As %List [ Private ]
{
	Set lines = $ListBuild(..#GUARDROUTINE_" ; generated by "_$ClassName()_" at every online-demo start; do not edit", $Char(9)_"Quit")
	Set lines = lines _ $ListBuild("Check(user,password) Public {", $Char(9)_"Set user = $ZConvert(user, ""L"")")
	Set lines = lines _ $ListBuild($Char(9)_"Set bare = $Select(user [ ""@"": $Piece(user, ""@"", 1, $Length(user, ""@"") - 1), 1: user)")
	For i = 1:1:accounts {
		Set name = ..Quoted($ZConvert($List(accounts(i), 1), "L"))
		Set salt = ..NewPassword()
		Set hash = ..Digest(salt, $List(accounts(i), 2))
		Set lines = lines _ $ListBuild($Char(9)_"If (user = "_name_") || (bare = "_name_") {")
		Set lines = lines _ $ListBuild($Char(9, 9)_"If $SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(512, $ZConvert("_..Quoted(salt)_"_password, ""O"", ""UTF8"")), 1) = "_..Quoted(hash)_" Quit 1")
		Set lines = lines _ $ListBuild($Char(9, 9)_"Quit $SYSTEM.Status.Error(5001, ""The password of this account cannot be changed"")", $Char(9)_"}")
	}
	Quit lines _ $ListBuild($Char(9)_"Quit 1", "}")
}

/// Saves the source lines as the routine (name without its .mac) and compiles it with -d. Runs in %SYS.
ClassMethod WriteGuard(name As %String, source As %List) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set routine = ##class(%Routine).%New(name_".mac")
	Set position = 0
	While $ListNext(source, position, line) {
		Do routine.WriteLine(line)
	}
	Set sc = routine.Save()
	If $$$ISERR(sc) Quit sc
	Quit ..CompileQuietly(routine)
}

/// Compiles the routine with -d. The compile still prints one empty line, which goes to the null device so that the start log keeps none.
ClassMethod CompileQuietly(routine As %Routine) As %Status [ Private ]
{
	Set original = $IO
	Set device = $Select($ZVersion(1) = 2: "//./nul", 1: "/dev/null")
	Set opened = 0
	Try {
		Open device:"WNS":2
		If $Test Set opened = 1
	} Catch {
		Set opened = 0
	}
	Try {
		If opened Use device
		Set sc = routine.Compile("-d")
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If opened {
		Use original
		Close device
	}
	Quit sc
}

/// The answer of the generated routine (name without its .mac) for each account: 1 for the name in capitals with the published password,
/// and an error status for that name with the published password and a character added. Runs in %SYS.
ClassMethod CheckGuardRoutine(routine As %String, ByRef accounts) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set sc = $SYSTEM.Status.OK()
	For i = 1:1:accounts {
		Set name = $List(accounts(i), 1)
		Set password = $List(accounts(i), 2)
		If $$Check^@(routine)($ZConvert(name, "U"), password) '= 1 {
			Set sc = ..Refuse("the generated routine "_routine_" refuses the published password of '"_name_"'")
		} ElseIf '$SYSTEM.Status.IsError($$Check^@(routine)($ZConvert(name, "U"), password_"x")) {
			Set sc = ..Refuse("the generated routine "_routine_" allows another password for '"_name_"'")
		}
		If $$$ISERR(sc) Quit
	}
	Quit sc
}

/// The Base64 SHA-512 of the salt and the password, as the generated routine computes it.
ClassMethod Digest(salt As %String, password As %String) As %String [ Private ]
{
	Quit $SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(512, $ZConvert(salt_password, "O", "UTF8")), 1)
}

/// The text as an ObjectScript string literal.
ClassMethod Quoted(text As %String) As %String [ Private ]
{
	Quit """"_$Replace(text, """", """""")_""""
}

/// The flag is off: clears the instance's PasswordValidationRoutine only when it is the guard's entry, then deletes the guard routine and
/// a staging routine left over when they exist, and warns once, only when it removed something. Another routine is never touched. Runs in
/// %SYS.
ClassMethod Unguard() As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set removed = 0
	Set current = ..Validation(.sc)
	If $$$ISERR(sc) Quit ..Fail("the instance's password-validation routine", sc)
	If current = ..#GUARDENTRY {
		Set sc = ..SetValidation("")
		If $$$ISERR(sc) Quit ..Fail("the password guard "_..#GUARDROUTINE, sc)
		Set removed = 1
	}
	For routine = ..#GUARDROUTINE, ..#GUARDSTAGE {
		If '##class(%Routine).Exists(routine_".mac") Continue
		Set sc = ##class(%Routine).Delete(routine_".mac", 0)
		If $$$ISERR(sc) Quit
		Set removed = 1
	}
	If $$$ISERR(sc) Quit ..Fail("the password guard "_..#GUARDROUTINE, sc)
	If removed Do ..Warn("The online-demo password guard "_..#GUARDROUTINE_" was removed, because the online-demo flag is off")
	Quit $SYSTEM.Status.OK()
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
