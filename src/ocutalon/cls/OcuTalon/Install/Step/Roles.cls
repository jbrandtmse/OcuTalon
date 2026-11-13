/// Composes every OcuTalon role from the Grants() of all the areas (AD-23, AD-24): per role, the union of
/// the declared permissions on each resource. The role is created, or modified to hold exactly that set and no
/// granted roles, so a start rewrites the roles and no area overwrites another's grants. Roles are structural
/// (AD-19). A declaration of a forbidden resource (FORBIDDEN), or of a resource that the instance does not have, fails the step before any
/// role is touched.
///   - Assign(userName, role, grant, .changed) and Holders(.users) are the run-time role calls of Settings > Roles (AD-24, step 6): stubs until Story 26.4, which answer
///     "not implemented" (5003) and change and read nothing.
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

/// Grants (grant 1) or removes (grant 0) one role of an existing IRIS user (AD-24, step 6); changed is 1 when the user's roles changed and 0 when the user already
/// was in that state. It is admin-only, works from an allowlist of exactly OcuTalonApprover and OcuTalonViewer, refuses every other role, every % role and the
/// installer-managed accounts with an error that names what it refused, writes one IRIS audit entry for each assignment and removal, and runs in %SYS in the
/// caller's job, which needs %Admin_Secure:USE.
/// A stub until Story 26.4: it answers "not implemented" (5003), sets changed to 0 and changes nothing.
ClassMethod Assign(userName As %String, role As %String, grant As %Boolean, Output changed As %Boolean) As %Status
{
	Set changed = 0
	Quit $$$ERROR($$$NotImplemented)
}

/// Lists the users who hold an OcuTalon role (AD-24, step 6) in users, a %DynamicArray of {user, roles} with the OcuTalon roles each holds, sorted. It runs in
/// %SYS in the caller's job, which needs %Admin_Secure:USE.
/// A stub until Story 26.4: it answers "not implemented" (5003), sets users to [] and reads nothing.
ClassMethod Holders(Output users As %DynamicArray) As %Status
{
	Set users = []
	Quit $$$ERROR($$$NotImplemented)
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
