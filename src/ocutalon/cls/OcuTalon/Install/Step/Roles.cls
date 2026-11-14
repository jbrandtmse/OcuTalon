/// Composes every OcuTalon role from the Grants() of all the areas (AD-23, AD-24): per role, the union of
/// the declared permissions on each resource. The role is created, or modified to hold exactly that set and no
/// granted roles, so a start rewrites the roles and no area overwrites another's grants. Roles are structural
/// (AD-19). A declaration of a forbidden resource (FORBIDDEN), or of a resource that the instance does not have, fails the step before any
/// role is touched.
///   - Assign(userName, role, grant, .changed, actingUser, sessionRef, channel), Refusal(userName, role) and Holders(.users) are the run-time role calls of
///     Settings > Roles (AD-24, step 6). They are admin-only, refuse on the online demo, and work in %SYS in the caller's job, which needs %Admin_Secure:USE.
Class OcuTalon.Install.Step.Roles Extends OcuTalon.Install.Step
{

/// Every role name starts with this.
Parameter ROLEPREFIX = "OcuTalon";

/// The resources that no OcuTalon role holds (AD-24), a comma list matched whole and without regard to case.
Parameter FORBIDDEN = "%All,%Development,%Ens_MessageEditResend,%Ens_MessageDiscard,%Ens_ProductionRun,%Ens_ProductionConfig,%Ens_WorkflowConfig";

ClassMethod Run() As %Status
{
	Set sc = ..Compose(.roles)
	If $$$ISERR(sc) Quit sc
	Quit ..Apply(.roles)
}

/// The only roles Assign grants or removes (AD-24), a comma list matched whole and without regard to case; the spelling here is what is written.
Parameter ASSIGNABLE = "OcuTalonApprover,OcuTalonViewer";

/// The SQL-watch user of AD-18, refused as a managed account even before it exists.
Parameter SQLREADER = "OcuTalonSqlReader";

/// IRIS's own accounts, a comma list in lower case. Assign refuses these and every name that starts with _ or %, because the unauthenticated web
/// applications run as UnknownUser.
Parameter SYSTEMUSERS = "unknownuser,_system,superuser,admin,cspsystem,iam,_ensemble,_public,hs_services";

/// The longest IRIS user name.
Parameter MAXUSERNAME = 160;

/// The reason Assign would refuse the call, as one code, or "" when it would not: online_demo, role (not in ASSIGNABLE), user_unknown (empty, longer than
/// MAXUSERNAME or not an IRIS user), user_system (one of SYSTEMUSERS, or a name that starts with _ or %, checked before the user is looked up) or user_managed (the
/// service, Workflow and SQL-watch users and the online demo's and read-only accounts, by name and whether or not they exist, or an account whose FullName is Users
/// MARKER). The README account is not managed.
/// It changes nothing and reads %SYS only to find the user.
ClassMethod Refusal(userName As %String, role As %String) As %String
{
	If +##class(OcuTalon.Data.Public.Settings).Get("onlineDemo") = 1 Quit "online_demo"
	If ..Assignable($Get(role)) = "" Quit "role"
	Set name = $Get(userName)
	If $IsObject(name) || (name = "") || ($Length(name) > ..#MAXUSERNAME) Quit "user_unknown"
	Set lower = $ZConvert(name, "L")
	If $ListFind($ListFromString(..#SYSTEMUSERS), lower) || ($Extract(name) = "_") || ($Extract(name) = "%") Quit "user_system"
	Set managed = $ListBuild(##class(OcuTalon.Install.Step.Users).#SERVICEUSER, ##class(OcuTalon.Bridge.Approval).#WORKFLOWUSER, ..#SQLREADER)
	Set managed = managed _ $ListBuild(##class(OcuTalon.Data.Public.Settings).Get("demoUser"), ##class(OcuTalon.Data.Public.Settings).Get("readonlyUser"))
	Set hit = 0
	Set position = 0
	While $ListNext(managed, position, account) {
		If (account '= "") && ($ZConvert(account, "L") = lower) Set hit = 1
	}
	If hit Quit "user_managed"
	If '..UserKnown(name, .fullName) Quit "user_unknown"
	If fullName = ##class(OcuTalon.Install.Step.Users).#MARKER Quit "user_managed"
	Quit ""
}

/// Grants (grant 1) or removes (grant 0) one role of an existing IRIS user (AD-24, step 6); changed is 1 when the user's roles changed and 0 when the user already
/// was in that state. In order: Refusal (an error 5001 that names the code and the role or user, nothing changed; a job without %Admin_Secure:USE cannot enter
/// %SYS to look the user up, and gets the next error), the %Admin_Secure:USE check (an error that names %Admin_Secure), then the change in %SYS with the allowlist's spelling of the role, then one IRIS audit entry of type Settings through
/// Bridge.Audit (setting roles.<userName>, from and to the user's OcuTalon roles as sorted comma lists, irisUser actingUser or the caller's $Username, sessionRef
/// and channel). A user already in the requested state changes nothing and writes no entry. When the entry cannot be written the role change is put back and
/// the error is returned (with the put-back's own error appended when that fails too). Audit is the one seam for the entry.
ClassMethod Assign(userName As %String, role As %String, grant As %Boolean, Output changed As %Boolean, actingUser As %String = "", sessionRef As %String = "", channel As %String = "system") As %Status
{
	Set changed = 0
	Set code = ""
	Set denied = $$$OK
	Try {
		Set code = ..Refusal($Get(userName), $Get(role))
	} Catch exception {
		Set denied = ..RequirePrivilege()
		If $$$ISOK(denied) Throw exception
	}
	If $$$ISERR(denied) Quit denied
	If code '= "" Quit $SYSTEM.Status.Error(5001, "Refused (" _ code _ "): " _ ..Subject(code, $Get(userName), $Get(role)))
	Set sc = ..RequirePrivilege()
	If $$$ISERR(sc) Quit sc
	Set role = ..Assignable(role)
	Set grant = ''$Get(grant)
	Set sc = ..Switch(userName, role, grant, .before, .after)
	If $$$ISERR(sc) Quit sc
	If before = after Quit $SYSTEM.Status.OK()
	Set data = {}
	Do data.%Set("setting", "roles." _ userName, "string")
	Do data.%Set("from", before, "string")
	Do data.%Set("to", after, "string")
	Do data.%Set("irisUser", $Select(actingUser '= "": actingUser, 1: $Username), "string")
	Do data.%Set("sessionRef", sessionRef, "string")
	Do data.%Set("channel", channel, "string")
	Set sc = ..Audit(data)
	If $$$ISERR(sc) {
		Set undone = ..Switch(userName, role, 'grant)
		If $$$ISERR(undone) Quit $SYSTEM.Status.AppendStatus(sc, undone)
		Quit sc
	}
	Set changed = 1
	Quit $SYSTEM.Status.OK()
}

/// The one audit write of Assign: an entry of type Settings through the one writer of product code. A test subclass overrides it.
ClassMethod Audit(data As %DynamicObject) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Audit).Record("Settings", data)
}

/// Lists the users who hold an OcuTalon role (AD-24, step 6) in users, a %DynamicArray of {user, roles, managed}: the OcuTalon roles each holds, sorted, and
/// managed, which is true for an account that Refusal(user, "OcuTalonViewer") answers user_managed or user_system for. The array is sorted by the user name in lower case, then by name. It
/// refuses on the online demo and needs %Admin_Secure:USE; it runs in %SYS.
ClassMethod Holders(Output users As %DynamicArray) As %Status
{
	Set users = []
	If +##class(OcuTalon.Data.Public.Settings).Get("onlineDemo") = 1 Quit $SYSTEM.Status.Error(5001, "Refused (online_demo): roles are not listed on the online demo")
	Set sc = ..RequirePrivilege()
	If $$$ISERR(sc) Quit sc
	Set sc = ..Collect(.found)
	If $$$ISERR(sc) Quit sc
	Set key = ""
	For {
		Set key = $Order(found(key))
		Quit:key=""
		Set name = ""
		For {
			Set name = $Order(found(key, name))
			Quit:name=""
			Set code = ..Refusal(name, "OcuTalonViewer")
			Set row = {}
			Do row.%Set("user", name, "string")
			Set list = []
			For i = 1:1:$Length(found(key, name), ",") Do list.%Push($Piece(found(key, name), ",", i))
			Do row.%Set("roles", list)
			Do row.%Set("managed", (code = "user_managed") || (code = "user_system"), "boolean")
			Do users.%Push(row)
		}
	}
	Quit $SYSTEM.Status.OK()
}

/// The allowlist's spelling of the role, or "" when the role is not in ASSIGNABLE.
ClassMethod Assignable(role As %String) As %String [ Private ]
{
	If $IsObject(role) || (role = "") Quit ""
	Set found = ""
	Set position = 0
	Set list = $ListFromString(..#ASSIGNABLE)
	While $ListNext(list, position, allowed) {
		If $ZConvert(allowed, "L") = $ZConvert(role, "L") Set found = allowed
	}
	Quit found
}

/// The refusal's subject: the role for a role refusal, the user for a user refusal.
ClassMethod Subject(code As %String, userName As %String, role As %String) As %String [ Private ]
{
	If code = "role" Quit "role " _ $Extract(role, 1, 64) _ " is not one of " _ ..#ASSIGNABLE
	If code = "online_demo" Quit "roles are not changed on the online demo"
	Quit "user " _ $Extract(userName, 1, 64) _ " " _ $Case(code, "user_unknown": "is not an IRIS user", "user_system": "is an IRIS system account", : "is managed by OcuTalon")
}

/// An error that names %Admin_Secure when the job does not hold %Admin_Secure:USE, else OK.
ClassMethod RequirePrivilege() As %Status [ Private ]
{
	If $SYSTEM.Security.Check("%Admin_Secure", "USE") Quit $SYSTEM.Status.OK()
	Quit $SYSTEM.Status.Error(5001, "Roles can be changed only in a job that holds %Admin_Secure:USE")
}

/// 1 when the IRIS user exists; fullName is its FullName. Runs in %SYS for the one call.
ClassMethod UserKnown(userName As %String, Output fullName As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set fullName = ""
	If '##class(Security.Users).Exists(userName, .user) Quit 0
	Set fullName = user.FullName
	Quit 1
}

/// The OcuTalon roles in a comma list of roles, as a sorted comma list.
ClassMethod OcuTalonRoles(roles As %String) As %String [ Private ]
{
	Kill held
	Set prefix = $ZConvert(..#ROLEPREFIX, "L")
	For i = 1:1:$Length(roles, ",") {
		Set role = $Piece(roles, ",", i)
		If $ZConvert($Extract(role, 1, $Length(prefix)), "L") = prefix Set held(role) = ""
	}
	Set list = ""
	Set role = ""
	For {
		Set role = $Order(held(role))
		Quit:role=""
		Set list = list _ $Select(list = "": "", 1: ",") _ role
	}
	Quit list
}

/// Adds (grant 1) or removes (grant 0) the role of the user, and answers the OcuTalon roles the user held before and after, as sorted comma lists. Nothing
/// is written when the user already is in the requested state.
ClassMethod Switch(userName As %String, role As %String, grant As %Boolean, Output before As %String, Output after As %String) As %Status [ Private ]
{
	Set (before, after) = ""
	Set sc = ..RolesOf(userName, .current)
	If $$$ISERR(sc) Quit sc
	Set before = ..OcuTalonRoles(current)
	Set after = before
	Set held = ''$ListFind($ListFromString($ZConvert(current, "L")), $ZConvert(role, "L"))
	If grant = held Quit $SYSTEM.Status.OK()
	Set sc = ..Change(userName, role, grant)
	If $$$ISERR(sc) Quit sc
	Set sc = ..RolesOf(userName, .current)
	If $$$ISERR(sc) Quit sc
	Set after = ..OcuTalonRoles(current)
	Quit $SYSTEM.Status.OK()
}

/// The user's directly granted roles as a comma list. Runs in %SYS for the one call.
ClassMethod RolesOf(userName As %String, Output roles As %String) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set roles = ""
	Set sc = ##class(Security.Users).Get(userName, .properties)
	If $$$ISOK(sc) Set roles = $Get(properties("Roles"))
	Quit sc
}

/// Adds or removes the one role of the user. Runs in %SYS for the one call.
ClassMethod Change(userName As %String, role As %String, grant As %Boolean) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set names = role
	If grant Quit ##class(Security.Users).AddRoles(userName, .names)
	Quit ##class(Security.Users).RemoveRoles(userName, .names)
}

/// found(lower-case name, name) = the user's sorted OcuTalon roles, for every IRIS user who holds one.
ClassMethod Collect(Output found) As %Status [ Private ]
{
	Kill found
	Set sc = ..Listing(.rows)
	If $$$ISERR(sc) Quit sc
	Set name = ""
	For {
		Set name = $Order(rows(name))
		Quit:name=""
		Set held = ..OcuTalonRoles(rows(name))
		If held '= "" Set found($ZConvert(name, "L"), name) = held
	}
	Quit $SYSTEM.Status.OK()
}

/// rows(name) = the directly granted roles of every IRIS user. Runs in %SYS for the one query.
ClassMethod Listing(Output rows) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Kill rows
	Set result = ##class(%ResultSet).%New("Security.Users:List")
	Set sc = result.Execute("*", "*")
	If $$$ISERR(sc) Quit sc
	While result.Next() {
		Set rows(result.Get("Name")) = result.Get("Roles")
	}
	Quit $SYSTEM.Status.OK()
}

/// roles(role, resource) = the union of the permissions declared for it, in the order R, W, U.
/// roles(role) is set for every declared role, including one declared without a resource. It changes nothing, so the security overview
/// (OcuTalon.Install.SecurityOverview) reads the same composition that Run applies.
ClassMethod Compose(Output roles) As %Status
{
	Kill roles
	Set sc = ##class(OcuTalon.Install.Registry).Declared("Grants", .grants)
	If $$$ISERR(sc) Quit sc
	Set n = ""
	For {
		Set n = $Order(grants(n))
		Quit:n=""
		Set sc = ..Add(.roles, grants(n), grants(n, "area"))
		If $$$ISERR(sc) Quit
	}
	Quit sc
}

/// Adds one declaration to roles, or returns an error that names the area.
ClassMethod Add(ByRef roles, grant As %DynamicObject, area As %String) As %Status [ Private ]
{
	Set role = grant.role
	Set resource = grant.resource
	Set permission = $ZConvert(grant.permission, "U")
	If ($Extract(role, 1, $Length(..#ROLEPREFIX)) '= ..#ROLEPREFIX) || ($Translate(role, ",:") '= role) {
		Quit $SYSTEM.Status.Error(5001, area_" Grants(): role '"_role_"' must start with "_..#ROLEPREFIX_" and hold no comma or colon")
	}
	If '$Data(roles(role)) Set roles(role) = ""
	If resource = "" Quit $SYSTEM.Status.OK()
	If $Translate(resource, ",:") '= resource {
		Quit $SYSTEM.Status.Error(5001, area_" Grants(): resource '"_resource_"' of role '"_role_"' holds a comma or colon")
	}
	If $ListFind($ListFromString($ZConvert(..#FORBIDDEN, "U")), $ZConvert(resource, "U")) {
		Quit $SYSTEM.Status.Error(5001, area_" Grants(): role '"_role_"' may not hold the forbidden resource '"_resource_"' (AD-24)")
	}
	If (permission = "") || ($Translate(permission, "RWU") '= "") {
		Quit $SYSTEM.Status.Error(5001, area_" Grants(): permission '"_grant.permission_"' on '"_resource_"' for role '"_role_"' is not made of R, W and U")
	}
	If '..ResourceExists(resource) {
		Quit $SYSTEM.Status.Error(5001, area_" Grants(): resource '"_resource_"' of role '"_role_"' does not exist on this instance")
	}
	Set held = $Get(roles(role, resource))_permission
	Set roles(role, resource) = $Select(held [ "R": "R", 1: "")_$Select(held [ "W": "W", 1: "")_$Select(held [ "U": "U", 1: "")
	Quit $SYSTEM.Status.OK()
}

/// 1 when the instance has the resource. Runs in %SYS.
ClassMethod ResourceExists(resource As %String) As %Boolean [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ''##class(Security.Resources).Exists(resource)
}

/// Creates each role, or modifies it to hold exactly the resources composed for it and no granted roles.
ClassMethod Apply(ByRef roles) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set sc = $SYSTEM.Status.OK()
	Set role = ""
	For {
		Set role = $Order(roles(role))
		Quit:role=""
		Set resources = ""
		Set resource = ""
		For {
			Set resource = $Order(roles(role, resource))
			Quit:resource=""
			Set resources = resources_$Select(resources = "": "", 1: ",")_resource_":"_roles(role, resource)
		}
		If ##class(Security.Roles).Exists(role) {
			Kill properties
			Set properties("Resources") = resources
			Set properties("GrantedRoles") = ""
			Set sc = ##class(Security.Roles).Modify(role, .properties)
		} Else {
			Set sc = ##class(Security.Roles).Create(role, "OcuTalon role", resources, "")
		}
		If $$$ISERR(sc) Quit
	}
	Quit sc
}

}
