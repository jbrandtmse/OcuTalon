/// Composes every OcuTalon role from the Grants() of all the areas (AD-23, AD-24): per role, the union of
/// the declared permissions on each resource. The role is created, or modified to hold exactly that set and no
/// granted roles, so a start rewrites the roles and no area overwrites another's grants. Roles are structural
/// (AD-19). A declaration of a forbidden resource (FORBIDDEN) fails the step before any role is touched.
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

/// roles(role, resource) = the union of the permissions declared for it, in the order R, W, U.
/// roles(role) is set for every declared role, including one declared without a resource.
ClassMethod Compose(Output roles) As %Status [ Private ]
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
	Set held = $Get(roles(role, resource))_permission
	Set roles(role, resource) = $Select(held [ "R": "R", 1: "")_$Select(held [ "W": "W", 1: "")_$Select(held [ "U": "U", 1: "")
	Quit $SYSTEM.Status.OK()
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
