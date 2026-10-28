/// The Fix area (AD-23, AD-24): it declares the grants of the service user's role from the registered fix kinds, and it runs no step. A kind declares the IRIS
/// privileges it needs as its class parameter RESOURCES (OcuTalon.Fix.Kind), in IRIS's role-resource form resource:permission[,resource:permission...] (Consistency
/// Conventions: Tool resources). The Roles step composes them into the role OcuTalonServiceRole, which the Users step gives to the service user, and the Roles step refuses a
/// forbidden resource such as %Ens_MessageEditResend. It is not in the registry's order, so it only declares.
Class OcuTalon.Install.Step.Fix Extends OcuTalon.Install.Step
{

/// The service user's role gets a grant for each resource that a registered fix kind declares.
ClassMethod Grants() As %DynamicArray
{
	Quit ..GrantsOf(##class(OcuTalon.Fix.Kind).Classes())
}

/// The grants of the service role for a list of kind classes: one {"role","resource","permission"} for each pair that a kind's RESOURCES declares, each
/// pair once. A malformed value throws a status that names the kind.
ClassMethod GrantsOf(kinds As %List) As %DynamicArray
{
	Set role = ##class(OcuTalon.Install.Step.Users).#SERVICEROLE
	Set grants = []
	Set position = 0
	While $ListNext(kinds, position, kind) {
		Set pairs = ##class(OcuTalon.Install.Step.Tools).Parse($Parameter(kind, "RESOURCES"), kind)
		Set iterator = pairs.%GetIterator()
		While iterator.%GetNext(, .pair) {
			If $Data(seen(pair.resource, pair.permission)) Continue
			Set seen(pair.resource, pair.permission) = ""
			Do grants.%Push({"role": (role), "resource": (pair.resource), "permission": (pair.permission)})
		}
	}
	Quit grants
}

}
