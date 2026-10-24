/// The Tools area (AD-23, AD-24): it declares the grants of the service user's role from the built-in tools, and it runs no step. A tool
/// declares the IRIS privileges it needs as the class parameter RESOURCES<NAME> of its tool class, else RESOURCES (Consistency Conventions:
/// Tool resources), in IRIS's role-resource form resource:permission[,resource:permission...]. The Roles step composes the declarations of
/// every toolset of OcuTalon.Tools into the role OcuTalonServiceRole, which the Users step gives to the service user, and the gate checks
/// the service user against the same parameters. A tool that declares nothing needs nothing.
Class OcuTalon.Install.Step.Tools Extends OcuTalon.Install.Step
{

/// The package whose toolsets are the built-in tools.
Parameter TOOLPACKAGE = "OcuTalon.Tools.";

/// The parameter of a tool class that holds its resources.
Parameter PARAMETER = "RESOURCES";

/// The service user's role: the role alone, and a grant for each resource that a built-in tool declares.
ClassMethod Grants() As %DynamicArray
{
	Quit ..GrantsOf(..Toolsets())
}

/// The class names of the built-in toolsets, sorted: every compiled, non-abstract subclass of %AI.ToolSet in the package OcuTalon.Tools.
ClassMethod Toolsets() As %List
{
	Set toolsets = ""
	Set sc = $$GetAllDerivedClasses^%occLibrary("%AI.ToolSet", .derived)
	If $$$ISERR(sc) Quit toolsets
	Set prefix = ..#TOOLPACKAGE
	Set name = ""
	For {
		Set name = $Order(derived(name))
		Quit:name=""
		If $Extract(name, 1, $Length(prefix)) '= prefix Continue
		If '##class(%Dictionary.CompiledClass).%ExistsId(name) Continue
		If $$$comClassKeyGet(name, $$$cCLASSabstract) Continue
		Set toolsets = toolsets _ $ListBuild(name)
	}
	Quit toolsets
}

/// The grants of the service role for a list of toolset classes: the entry that declares the role alone, then one
/// {"role","resource","permission"} for each pair that a tool of a toolset declares, each pair once. Each tool of a toolset is read from
/// its discovery, as the provider class and the name, and its pairs are Parse of its RESOURCES parameter. A malformed value throws a status
/// that names the class and the tool.
ClassMethod GrantsOf(toolsets As %List) As %DynamicArray
{
	Set role = ##class(OcuTalon.Install.Step.Users).#SERVICEROLE
	Set grants = [{"role": (role), "resource": "", "permission": ""}]
	Set position = 0
	While $ListNext(toolsets, position, toolset) {
		Set tools = $ClassMethod(toolset, "%New").%Discover().tools
		Set iterator = tools.%GetIterator()
		While iterator.%GetNext(, .tool) {
			Set value = ##class(OcuTalon.Bridge.Adapter.StepBuffer).ToolParameter(tool.provider, tool.name, ..#PARAMETER)
			Set pairs = ..Parse(value, tool.provider _ " " _ tool.name)
			Set pairIterator = pairs.%GetIterator()
			While pairIterator.%GetNext(, .pair) {
				If $Data(seen(pair.resource, pair.permission)) Continue
				Set seen(pair.resource, pair.permission) = ""
				Do grants.%Push({"role": (role), "resource": (pair.resource), "permission": (pair.permission)})
			}
		}
	}
	Quit grants
}

/// The pairs of a RESOURCES value as a dynamic array of {"resource","permission"}: resource:permission[,resource:permission...], where the
/// permission is one or more of R, W and U. An empty value gives []. A pair without a colon, with an empty or spaced resource, or with a
/// permission that is empty or holds another character throws a status that names where (the class and the tool, or the caller's own words).
ClassMethod Parse(value As %String, where As %String) As %DynamicArray
{
	Set pairs = []
	If value = "" Quit pairs
	For i = 1:1:$Length(value, ",") {
		Set pair = $Piece(value, ",", i)
		Set resource = $Piece(pair, ":", 1)
		Set permission = $Piece(pair, ":", 2)
		If ($Length(pair, ":") '= 2) || (resource = "") || ($ZStrip(resource, "*W") '= resource) {
			$$$ThrowStatus($SYSTEM.Status.Error(5001, where_" RESOURCES: '"_pair_"' in '"_value_"' is not resource:permission with a resource name"))
		}
		If (permission = "") || ($Translate(permission, "RWU") '= "") {
			$$$ThrowStatus($SYSTEM.Status.Error(5001, where_" RESOURCES: the permission of '"_pair_"' in '"_value_"' is not made of R, W and U"))
		}
		Do pairs.%Push({"resource": (resource), "permission": (permission)})
	}
	Quit pairs
}

}
