/// Tests of OcuTalon.Install.Step.Roles Assign, Refusal and Holders (Story 25.4; AD-3, AD-17, AD-24; Planner ruling V3 and C1). THROWAWAY STACKS AND CI ONLY (Rule 21):
/// they create and delete security users and roles. Test.Core.AnswersInWebRoles.Reason refuses everything else (the demo host, a user's instance, an IPM test run and a
/// slot), and the setup then fails with the reason before anything is made. The fixture users have the prefix ZzRolesA and are removed before and after the run; the fixture
/// roles OcuTalonApprover and OcuTalonViewer are created, with no resources, only when the instance has none, and only those are removed again.
///   - TestRoleRefused: each role that is not on the allowlist (the admin, user, trace-viewer and webhook roles, a per-kind approver role, %All, %Manager, an unknown
///     name) is refused with an error that names it, and the user's role set and the audit log are unchanged;
///   - TestManagedUserRefused: the service, Workflow and SQL-watch users, the public demo and read-only accounts, and an account whose FullName is the installer's
///     marker are refused (user_managed) with the same checks;
///   - TestSystemUserRefused (C1): UnknownUser, _SYSTEM, SuperUser, a name that starts with % and one that starts with _ are refused (user_system);
///   - TestHoldersListsSystemAccountAsManaged (C1): Holders lists an account with a system name that already holds an OcuTalon role, with managed true;
///   - TestUnknownUserRefused: an unknown user, an empty name and a name of 161 characters are refused (user_unknown);
///   - TestNoPrivilege: a job logged in as a fixture admin, who holds no %Admin_Secure:USE, gets an error that names %Admin_Secure from Assign and Holders and changes nothing;
///   - TestOnlineDemo: with the online-demo flag set, Assign, Refusal and Holders refuse and nothing changes;
///   - TestGrantAndRemove: a grant and a removal each change the roles (changed 1) and write one Settings entry (read back by polling) with the setting roles.<user>,
///     the OcuTalon roles before and after, the acting admin, the session and the channel; the same call again changes nothing (changed 0) and writes no entry; a role name
///     in another case is written with the allowlist's spelling; the README account is assignable;
///   - TestAuditFailurePutsTheRoleBack: when the entry cannot be written the role change is put back and Assign answers the error;
///   - TestHolders: it lists the users who hold an OcuTalon role, sorted without regard to case, with only their OcuTalon roles, sorted, and managed set.
Class OcuTalon.Test.Install.RolesAssign Extends %UnitTest.TestCase
{

/// The fixture users' prefix: users with it are deleted before and after the run.
Parameter USER = "ZzRolesA";

/// The roles of the allowlist that the run makes when the instance has none.
Parameter FIXTUREROLES = "OcuTalonApprover,OcuTalonViewer";

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 300);

/// The fixture roles that this run created, comma-separated.
Property Created As %String;

/// The public settings before a test.
Property SavedOnline As %String;

Property SavedDemo As %String;

Property SavedReadonly As %String;

Method OnBeforeAllTests() As %Status
{
	Set running = ##class(Ens.Director).IsProductionRunning(.name)
	Set ..Missing = ##class(OcuTalon.Test.Core.AnswersInWebRoles).Reason($SYSTEM.Util.GetEnviron("OCUTALON_MODEL_BASE_URL"), $SYSTEM.Util.GetEnviron("OCUTALON_MOCK_KEY_HEADER"), running, $Get(name))
	If ..Missing '= "" Quit $SYSTEM.Status.Error(5001, ..Missing)
	Set ..Created = ""
	Do ..Clean()
	Set ..Created = ..EnsureRoles()
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	If ..Missing '= "" Quit $$$OK
	Do ..Clean()
	Do ..DropRoles(..Created)
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("RolesAssign")
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..SavedDemo = ##class(OcuTalon.Data.Public.Settings).Get("demoUser")
	Set ..SavedReadonly = ##class(OcuTalon.Data.Public.Settings).Get("readonlyUser")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 0)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(OcuTalon.Data.Public.Settings).Set("demoUser", ..SavedDemo)
	Do ##class(OcuTalon.Data.Public.Settings).Set("readonlyUser", ..SavedReadonly)
	Kill ^OcuTalonTest("RolesAssign")
	If ..Missing = "" Do ..Clean()
	Quit $$$OK
}

Method TestRoleRefused()
{
	If '..Guard() Quit
	Set user = ..NewUser("r", "OcuTalonUser")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set before = ..RoleSet(user)
	For role = "OcuTalonAdmin", "OcuTalonUser", "OcuTalonTraceViewer", "OcuTalonWebhook", "OcuTalonApprover_resend", "OcuTalonApprover_tool", "%All", "%Manager", "ZzNoSuchRole", "" {
		Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(user, role, 1, .changed)
		Do $$$AssertStatusNotOK(sc, "'"_role_"' is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "(role)", "'"_role_"': the error names the refusal code")
		If role '= "" Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ role, "'"_role_"': the error names the role")
		Do $$$AssertEquals(changed, 0, "'"_role_"': changed is 0")
		Do $$$AssertEquals(##class(OcuTalon.Install.Step.Roles).Refusal(user, role), "role", "'"_role_"': Refusal says role")
		Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(user, role, 0, .changed)
		Do $$$AssertStatusNotOK(sc, "'"_role_"' is refused for a removal too")
	}
	Do $$$AssertEquals(..RoleSet(user), before, "the user's role set is unchanged")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Settings", "Settings", user).%Size(), 0, "and no audit entry was written")
}

Method TestManagedUserRefused()
{
	If '..Guard() Quit
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set marked = ..NewUser("m", "OcuTalonUser", ##class(OcuTalon.Install.Step.Users).#MARKER)
	Set demo = ..NewUser("d", "OcuTalonUser")
	Set readonly = ..NewUser("o", "OcuTalonUser")
	Do ##class(OcuTalon.Data.Public.Settings).Set("demoUser", demo)
	Do ##class(OcuTalon.Data.Public.Settings).Set("readonlyUser", readonly)
	Set names = $ListBuild(##class(OcuTalon.Install.Step.Users).#SERVICEUSER, ##class(OcuTalon.Bridge.Approval).#WORKFLOWUSER, ##class(OcuTalon.Install.Step.Roles).#SQLREADER, marked, demo, readonly, $ZConvert(demo, "U"))
	Set position = 0
	While $ListNext(names, position, name) {
		Set before = ..RoleSet(name)
		Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(name, "OcuTalonViewer", 1, .changed)
		Do $$$AssertStatusNotOK(sc, name_" is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "(user_managed)", name_": the error names the code")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ name, name_": and the user")
		Do $$$AssertEquals(changed, 0, name_": changed is 0")
		Do $$$AssertEquals(##class(OcuTalon.Install.Step.Roles).Refusal(name, "OcuTalonApprover"), "user_managed", name_": Refusal says user_managed")
		Do $$$AssertEquals(..RoleSet(name), before, name_": its role set is unchanged")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Settings").%Size(), 0, "no Settings entry was written")
}

Method TestSystemUserRefused()
{
	If '..Guard() Quit
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	For name = "UnknownUser", "_SYSTEM", "SuperUser", "Admin", "CSPSystem", "IAM", "_Ensemble", "_PUBLIC", "HS_Services", "unknownuser", "%x", "_zz", "%Zz" {
		Set before = ..RoleSet(name)
		Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(name, "OcuTalonViewer", 1, .changed)
		Do $$$AssertStatusNotOK(sc, name_" is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "(user_system)", name_": the error names the code")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ name, name_": and the user")
		Do $$$AssertEquals(changed, 0, name_": changed is 0")
		Do $$$AssertEquals(##class(OcuTalon.Install.Step.Roles).Refusal(name, "OcuTalonViewer"), "user_system", name_": Refusal says user_system")
		Do $$$AssertEquals(..RoleSet(name), before, name_": its role set is unchanged")
		If ..RoleSet(name) '= before Do ..RemoveRole(name, "OcuTalonViewer")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Settings").%Size(), 0, "no Settings entry was written")
}

Method TestUnknownUserRefused()
{
	If '..Guard() Quit
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	For name = "ZzRolesANoSuchUser", "", $Translate($Justify("", 161), " ", "z") {
		Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(name, "OcuTalonViewer", 1, .changed)
		Do $$$AssertStatusNotOK(sc, "'"_$Extract(name, 1, 30)_"' is refused")
		Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "(user_unknown)", "the error names the code")
		Do $$$AssertEquals(changed, 0, "changed is 0")
		Do $$$AssertEquals(##class(OcuTalon.Install.Step.Roles).Refusal(name, "OcuTalonViewer"), "user_unknown", "Refusal says user_unknown")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Settings").%Size(), 0, "no Settings entry was written")
}

Method TestNoPrivilege()
{
	If '..Guard() Quit
	Set target = ..NewUser("t", "OcuTalonUser")
	Set admin = ..NewUser("p", "OcuTalonUser,OcuTalonAdmin"_..AppRoles())
	Set before = ..RoleSet(target)
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set run = $Name(^OcuTalonTest("RolesAssign", "job"))
	Kill @run
	Job ##class(OcuTalon.Test.Install.RolesAssign).Probe(admin, target)
	Set finished = ##class(OcuTalon.Test.Agent.RunnerFixture).WaitFor($Name(@run@("done")), 60)
	Do $$$AssertTrue(finished, "the job reports")
	Do $$$AssertEquals($Get(@run@("error")), "", "and threw nothing: "_$Get(@run@("error")))
	Do $$$AssertEquals($Get(@run@("login")), 1, "control: the job logged in as the fixture admin")
	Do $$$AssertEquals($Get(@run@("privilege")), 0, "control: the job holds no %Admin_Secure:USE")
	Do $$$AssertEquals($Get(@run@("assign")), 1, "Assign is an error")
	Do $$$AssertTrue($Get(@run@("assignText")) [ "%Admin_Secure", "that names %Admin_Secure")
	Do $$$AssertEquals($Get(@run@("changed")), 0, "changed is 0")
	Do $$$AssertEquals($Get(@run@("holders")), 1, "Holders is an error")
	Do $$$AssertTrue($Get(@run@("holdersText")) [ "%Admin_Secure", "that names %Admin_Secure")
	Do $$$AssertEquals(..RoleSet(target), before, "the target's role set is unchanged")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Settings", "Settings", target).%Size(), 0, "and no audit entry was written")
}

/// The job: logs in as the user (no password) and calls Assign and Holders, reporting under ^OcuTalonTest("RolesAssign", "job").
ClassMethod Probe(user As %String, target As %String)
{
	Set run = $Name(^OcuTalonTest("RolesAssign", "job"))
	Try {
		Set @run@("login") = $SYSTEM.Security.Login(user)
		Set @run@("privilege") = +$SYSTEM.Security.Check("%Admin_Secure", "USE")
		Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(target, "OcuTalonViewer", 1, .changed)
		Set @run@("assign") = $SYSTEM.Status.IsError(sc)
		Set @run@("assignText") = $SYSTEM.Status.GetErrorText(sc)
		Set @run@("changed") = +$Get(changed)
		Set sc = ##class(OcuTalon.Install.Step.Roles).Holders(.users)
		Set @run@("holders") = $SYSTEM.Status.IsError(sc)
		Set @run@("holdersText") = $SYSTEM.Status.GetErrorText(sc)
	} Catch exception {
		Set @run@("error") = exception.DisplayString()
	}
	Set @run@("done") = 1
}

Method TestOnlineDemo()
{
	If '..Guard() Quit
	Set user = ..NewUser("o", "OcuTalonUser")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set before = ..RoleSet(user)
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(user, "OcuTalonViewer", 1, .changed)
	Do $$$AssertStatusNotOK(sc, "Assign refuses on the online demo")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "(online_demo)", "naming the code")
	Do $$$AssertEquals(changed, 0, "changed is 0")
	Do $$$AssertEquals(##class(OcuTalon.Install.Step.Roles).Refusal(user, "OcuTalonViewer"), "online_demo", "Refusal says online_demo")
	Set sc = ##class(OcuTalon.Install.Step.Roles).Holders(.users)
	Do $$$AssertStatusNotOK(sc, "Holders refuses on the online demo")
	Do $$$AssertEquals(..RoleSet(user), before, "the role set is unchanged")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Settings", "Settings", user).%Size(), 0, "and no entry was written")
}

Method TestGrantAndRemove()
{
	If '..Guard() Quit
	Set user = ..NewUser("g", "OcuTalonUser")
	Set session = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(user, "OcuTalonViewer", 1, .changed, "zzadmin", session, "web")
	Do $$$AssertStatusOK(sc, "a grant is OK")
	Do $$$AssertEquals(changed, 1, "and changes the roles")
	Do $$$AssertTrue($ListFind($ListFromString(..RoleSet(user)), "OcuTalonViewer"), "the user holds the role (GetUserRecursedRoleSet)")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", user)
	Do $$$AssertEquals(entries.%Size(), 1, "one Settings entry names the user")
	Set data = entries.%Get(0).data
	Do $$$AssertEquals(data.setting, "roles."_user, "the setting is roles.<user>")
	Do $$$AssertEquals(data.from, "OcuTalonUser", "from the roles before")
	Do $$$AssertEquals(data.to, "OcuTalonUser,OcuTalonViewer", "to the roles after")
	Do $$$AssertEquals(data.irisUser, "zzadmin", "naming the acting admin")
	Do $$$AssertEquals(data.sessionRef, session, "the session")
	Do $$$AssertEquals(data.channel, "web", "and the channel")

	Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(user, "OcuTalonViewer", 1, .changed, "zzadmin", session, "web")
	Do $$$AssertStatusOK(sc, "the same grant again is OK")
	Do $$$AssertEquals(changed, 0, "and changes nothing")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Settings", "Settings", user).%Size(), 1, "and writes no second entry")

	Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(user, "ocutalonapprover", 1, .changed, "zzadmin", session, "web")
	Do $$$AssertStatusOK(sc, "a role in another case is OK")
	Do $$$AssertEquals(changed, 1, "and changes the roles")
	Do $$$AssertEquals(..OcuTalonRoles(user), "OcuTalonApprover,OcuTalonUser,OcuTalonViewer", "with the allowlist's spelling")

	Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(user, "OcuTalonViewer", 0, .changed, "zzadmin", session, "web")
	Do $$$AssertStatusOK(sc, "a removal is OK")
	Do $$$AssertEquals(changed, 1, "and changes the roles")
	Do $$$AssertEquals(..OcuTalonRoles(user), "OcuTalonApprover,OcuTalonUser", "the viewer role is gone and the others stay")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", user, "", 3)
	Do $$$AssertEquals(entries.%Size(), 3, "each of the three changes wrote one entry")
	Do $$$AssertEquals(entries.%Get(2).data.from_"|"_entries.%Get(2).data.to, "OcuTalonApprover,OcuTalonUser,OcuTalonViewer|OcuTalonApprover,OcuTalonUser", "the removal's entry")

	Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(user, "OcuTalonViewer", 0, .changed, "zzadmin", session, "web")
	Do $$$AssertEquals(changed, 0, "a removal of a role that is not held changes nothing")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Settings", "Settings", user).%Size(), 3, "and writes no entry")

	Set sc = ##class(OcuTalon.Install.Step.Roles).Assign(user, "OcuTalonViewer", 1, .changed)
	Do $$$AssertStatusOK(sc, "a grant with no acting user is OK")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Settings", "Settings", user, "", 4)
	Do $$$AssertEquals(entries.%Get(3).data.irisUser, $Username, "and names the caller")
	Do $$$AssertEquals(entries.%Get(3).data.channel, "system", "on the channel system")

	Set readme = ##class(OcuTalon.Install.Step.Users).#USER
	Set code = ##class(OcuTalon.Install.Step.Roles).Refusal(readme, "OcuTalonViewer")
	Do $$$AssertTrue((code '= "user_managed") && (code '= "user_system"), "the README account is not managed or a system account: "_code)
}

Method TestAuditFailurePutsTheRoleBack()
{
	If '..Guard() Quit
	Set user = ..NewUser("f", "OcuTalonUser")
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Set before = ..RoleSet(user)
	Set sc = ##class(OcuTalon.Test.Install.ZzRolesAuditFails).Assign(user, "OcuTalonViewer", 1, .changed, "zzadmin")
	Do $$$AssertStatusNotOK(sc, "a grant whose entry cannot be written is an error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "audit write failed", "that is the audit's")
	Do $$$AssertEquals(changed, 0, "changed is 0")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("RolesAssign", "auditCalls")), 1, "the entry was tried once")
	Do $$$AssertEquals(..RoleSet(user), before, "and the role is back off the user")
	Do ##class(OcuTalon.Install.Step.Roles).Assign(user, "OcuTalonViewer", 1, .changed, "zzadmin")
	Set before = ..RoleSet(user)
	Set sc = ##class(OcuTalon.Test.Install.ZzRolesAuditFails).Assign(user, "OcuTalonViewer", 0, .changed, "zzadmin")
	Do $$$AssertStatusNotOK(sc, "a removal whose entry cannot be written is an error")
	Do $$$AssertEquals(..RoleSet(user), before, "and the role is back on the user")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Settings", "Settings", user).%Size(), 1, "only the entry of the one real grant exists")
}

Method TestHolders()
{
	If '..Guard() Quit
	Set b = ..NewUser("b", "OcuTalonViewer,OcuTalonApprover")
	Set a = ..NewUser("a", "OcuTalonUser")
	Set none = ..NewUser("n", "%DB_OCUTALON_DATA")
	Set managed = ..NewUser("m", "OcuTalonUser", ##class(OcuTalon.Install.Step.Users).#MARKER)
	Set sc = ##class(OcuTalon.Install.Step.Roles).Holders(.users)
	Do $$$AssertStatusOK(sc, "Holders is OK")
	Set found = ""
	Set order = ""
	Set position = 0
	For i = 0:1:users.%Size() - 1 {
		Set row = users.%Get(i)
		Do $$$AssertEquals(row.%GetTypeOf("managed"), "boolean", row.user_": managed is a boolean")
		Do $$$AssertEquals(row.%GetTypeOf("roles"), "array", row.user_": roles is an array")
		For j = 0:1:row.roles.%Size() - 1 {
			Do $$$AssertEquals($Extract(row.roles.%Get(j), 1, 8), "OcuTalon", row.user_": every role listed is an OcuTalon role")
		}
		Set order = order_$Select(order = "": "", 1: $Char(1))_$ZConvert(row.user, "L")
		If $Extract(row.user, 1, $Length(..#USER)) = ..#USER Set found(row.user) = row
	}
	Set sorted = 1
	Set previous = ""
	For i = 1:1:$Length(order, $Char(1)) {
		Set one = $Piece(order, $Char(1), i)
		If (previous '= "") && (one ] previous = 0) && (one '= previous) Set sorted = 0
		Set previous = one
	}
	Do $$$AssertTrue(sorted, "the users are sorted without regard to case")
	Do $$$AssertEquals($Data(found(a)), 1, "the user with an OcuTalon role is listed")
	Do $$$AssertEquals(found(a).roles.%ToJSON(), "[""OcuTalonUser""]", "with its OcuTalon roles")
	Do $$$AssertEquals(found(a).managed, 0, "not managed")
	Do $$$AssertEquals(found(b).roles.%ToJSON(), "[""OcuTalonApprover"",""OcuTalonViewer""]", "a user's roles are sorted")
	Do $$$AssertEquals($Data(found(none)), 0, "a user with no OcuTalon role is not listed")
	Do $$$AssertEquals(found(managed).managed, 1, "an account that the installer made is managed")
	Do $$$AssertTrue($Order(found(a)) = b, "and the fixture users come in name order")
}

Method TestHoldersListsSystemAccountAsManaged()
{
	If '..Guard() Quit
	Set system = "_"_..#USER_"sys"
	Set sc = ..CreateUser(system, "OcuTalonViewer")
	Do $$$AssertStatusOK(sc, "the fixture user with a system name is created")
	Set sc = ##class(OcuTalon.Install.Step.Roles).Holders(.users)
	Do $$$AssertStatusOK(sc, "Holders is OK")
	Set managed = ""
	For i = 0:1:users.%Size() - 1 {
		If users.%Get(i).user = system Set managed = users.%Get(i).managed
	}
	Do $$$AssertEquals(managed, 1, "an account with a system name that holds an OcuTalon role is listed as managed")
}

/// --- helpers ---
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// Creates the fixture user ZzRolesA<suffix> with the roles (a comma list) and, when given, the FullName; returns its name.
Method NewUser(suffix As %String, roles As %String, fullName As %String = "OcuTalon test fixture") As %String [ Private ]
{
	Set user = ..#USER_suffix
	Set sc = ..CreateUser(user, roles, fullName)
	Do $$$AssertStatusOK(sc, "the fixture user "_user_" is created")
	Quit user
}

ClassMethod CreateUser(user As %String, roles As %String, fullName As %String = "OcuTalon test fixture") As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"
	If ##class(Security.Users).Exists(user) Do ##class(Security.Users).Delete(user)
	Set password = "Zz"_$SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(18))_"xY!9"
	Quit ##class(Security.Users).Create(user, roles, password, fullName, , , , 0, 1)
}

/// The user's recursed role set as a sorted comma list ("" for a user that does not exist).
ClassMethod RoleSet(user As %String) As %String [ Private ]
{
	Set sc = $SYSTEM.Security.GetUserRecursedRoleSet(user, .roles)
	If $SYSTEM.Status.IsError(sc) Quit ""
	Quit ..Sorted(roles)
}

ClassMethod Sorted(roles As %String) As %String [ Private ]
{
	Kill held
	For i = 1:1:$Length(roles, ",") {
		If $Piece(roles, ",", i) '= "" Set held($Piece(roles, ",", i)) = ""
	}
	Set list = "", role = ""
	For {
		Set role = $Order(held(role))
		Quit:role=""
		Set list = list_$Select(list = "": "", 1: ",")_role
	}
	Quit list
}

/// The OcuTalon roles of the user's recursed role set, sorted.
ClassMethod OcuTalonRoles(user As %String) As %String [ Private ]
{
	Set roles = ..RoleSet(user)
	Set list = ""
	For i = 1:1:$Length(roles, ",") {
		If $Extract($Piece(roles, ",", i), 1, 8) = "OcuTalon" Set list = list_$Select(list = "": "", 1: ",")_$Piece(roles, ",", i)
	}
	Quit list
}

/// The application roles of Install.Step.Web (APPLICATIONROLES, a MatchRoles form, ":role:role"), as ",role,role": the database roles that a web request's job holds
/// and that the job of TestNoPrivilege needs to write its report.
ClassMethod AppRoles() As %String
{
	Set roles = ""
	Set spec = ##class(OcuTalon.Install.Step.Web).#APPLICATIONROLES
	For i = 1:1:$Length(spec, ":") {
		If $Piece(spec, ":", i) '= "" Set roles = roles_","_$Piece(spec, ":", i)
	}
	Quit roles
}

/// Takes the role off an IRIS account if it holds it, so that a refusal that failed leaves a system account as it was.
ClassMethod RemoveRole(user As %String, role As %String) [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	If '##class(Security.Users).Exists(user) Quit
	Set names = role
	Do ##class(Security.Users).RemoveRoles(user, .names)
}

/// Makes each role of FIXTUREROLES that the instance does not have, with no resources; returns the names that it made.
ClassMethod EnsureRoles() As %String
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set made = ""
	For i = 1:1:$Length(..#FIXTUREROLES, ",") {
		Set role = $Piece(..#FIXTUREROLES, ",", i)
		If '##class(Security.Roles).Exists(role) {
			If $$$ISOK(##class(Security.Roles).Create(role, "OcuTalon test fixture", "")) Set made = made_$Select(made = "": "", 1: ",")_role
		}
	}
	Quit made
}

/// Deletes the roles (a comma list), which are the ones that this run made.
ClassMethod DropRoles(roles As %String)
{
	New $Namespace
	Set $Namespace = "%SYS"
	For i = 1:1:$Length(roles, ",") {
		If $Piece(roles, ",", i) '= "" Do ##class(Security.Roles).Delete($Piece(roles, ",", i))
	}
}

/// Deletes the fixture users of every run.
ClassMethod Clean() [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM Security.Users WHERE Name %STARTSWITH ? OR Name %STARTSWITH ?", ..#USER, "_"_..#USER)
	While result.%Next() {
		Do ##class(Security.Users).Delete(result.%GetData(1))
	}
}

}
