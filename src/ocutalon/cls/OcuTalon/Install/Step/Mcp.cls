/// The Mcp area (AD-3, AD-21, AD-23, AD-24): the IRIS resource of each registered MCP server, OcuTalon_MCP_<server>, and the service role's
/// Use permission on it. It runs no step. It is the only code that reaches %SYS for an MCP server.
///   - Grant(server) and Revoke(server) are the one fixed entry point of OcuTalon.Mcp.Ops. Each takes a server name and nothing else, builds the
///     resource name itself, and refuses (an error, nothing changed) a name that does not match OcuTalon.Mcp.Server NAMEPATTERN. Grant creates the
///     resource, with no public permission, and adds OcuTalon_MCP_<server>:U to the role OcuTalonServiceRole; Revoke removes that pair and deletes
///     that resource. Both touch no other resource and no other pair of the role, and neither grants a security-administration privilege.
///   - Grants() declares, at every start, the pair of each Mcp.Server row whose resource exists, because the Roles step rewrites the role. A row whose
///     resource is missing is skipped with a warning, so a start never fails. On an online-demo install it declares none.
Class OcuTalon.Install.Step.Mcp Extends OcuTalon.Install.Step
{

/// Every MCP server resource starts with this, followed by the server's name.
Parameter RESOURCEPREFIX = "OcuTalon_MCP_";

/// The permission the service role holds on the resource.
Parameter PERMISSION = "U";

ClassMethod Grants() As %DynamicArray
{
	Set grants = []
	If +##class(OcuTalon.Data.Public.Settings).Get("onlineDemo") = 1 Quit grants
	Set role = ##class(OcuTalon.Install.Step.Users).#SERVICEROLE
	Try {
		Set statement = ##class(%SQL.Statement).%New()
		Set sc = statement.%Prepare("SELECT Name FROM OcuTalon_Mcp.Server ORDER BY Name")
		If $$$ISOK(sc) {
			Set result = statement.%Execute()
			If result.%SQLCODE < 0 Set sc = $$$ERROR($$$SQLError, result.%SQLCODE, result.%Message)
		}
		If $$$ISERR(sc) {
			Do ..Warn("The Mcp area could not read the MCP servers, so it declares no grant: " _ $SYSTEM.Status.GetOneStatusText(sc))
			Quit
		}
		While result.%Next() {
			Set resource = ..ResourceOf(result.%Get("Name"), .problem)
			If $$$ISERR(problem) {
				Do ..Warn("The Mcp area skips an MCP server whose name is not valid")
				Continue
			}
			If '..ResourceExists(resource) {
				Do ..Warn("The Mcp area skips the resource " _ resource _ ", which does not exist")
				Continue
			}
			Do grants.%Push({"role": (role), "resource": (resource), "permission": (..#PERMISSION)})
		}
	} Catch exception {
		Do ..Warn("The Mcp area could not declare its grants: " _ $SYSTEM.Status.GetOneStatusText(exception.AsStatus()))
	}
	Quit grants
}

/// Makes the resource of the server and gives the service role the Use permission on it. A name that fails NAMEPATTERN is an error and changes
/// nothing. A resource that already exists is left as it is, and an existing pair on the resource is set to the Use permission, so it can be called
/// again.
ClassMethod Grant(server As %String) As %Status
{
	Set resource = ..ResourceOf($Get(server), .sc)
	If $$$ISERR(sc) Quit sc
	Quit ..Change(resource, 1)
}

/// Takes the Use permission on the server's resource from the service role and deletes the resource. A name that fails NAMEPATTERN is an error and
/// changes nothing. A resource or a pair that is already gone is not an error.
ClassMethod Revoke(server As %String) As %Status
{
	Set resource = ..ResourceOf($Get(server), .sc)
	If $$$ISERR(sc) Quit sc
	Quit ..Change(resource, 0)
}

/// The name of the resource of the server: OcuTalon_MCP_ and the name. sc is an error, and the result empty, for a name that is not a string that
/// matches OcuTalon.Mcp.Server NAMEPATTERN.
ClassMethod ResourceOf(server As %String, Output sc As %Status) As %String
{
	Set sc = $SYSTEM.Status.OK()
	If $IsObject(server) || '$Match(server, ##class(OcuTalon.Mcp.Server).#NAMEPATTERN) {
		Set sc = $SYSTEM.Status.Error(5001, "An MCP server's name is a letter followed by up to 39 letters, digits or underscores, so no resource was changed")
		Quit ""
	}
	Quit ..#RESOURCEPREFIX _ server
}

/// The role's Resources property (resource:permission pairs, comma-separated) with the pair of the resource set to the Use permission (on) or taken
/// away (off); every other pair is kept as it is, in its place, and a pair that is already as wanted leaves the text as it was.
ClassMethod WithPair(current As %String, resource As %String, on As %Boolean) As %String
{
	Set wanted = ""
	Set found = 0
	For i = 1:1:$Length(current, ",") {
		Set pair = $Piece(current, ",", i)
		If pair = "" Continue
		If $Piece(pair, ":", 1) = resource {
			If 'on Continue
			Set found = 1
			Set pair = resource _ ":" _ ..#PERMISSION
		}
		Set wanted = wanted _ $Select(wanted = "": "", 1: ",") _ pair
	}
	If on && 'found Set wanted = wanted _ $Select(wanted = "": "", 1: ",") _ resource _ ":" _ ..#PERMISSION
	Quit wanted
}

/// 1 when the instance has the resource. Switches to %SYS for the one call and uses no method of this class there.
ClassMethod ResourceExists(resource As %String) As %Boolean [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Quit ''##class(Security.Resources).Exists(resource)
}

/// Creates the resource and the role's pair (on), or removes the pair and the resource (off), only for a resource that ResourceOf built. On, a resource
/// that this call created is deleted again when the role cannot be changed.
ClassMethod Change(resource As %String, on As %Boolean) As %Status [ Private ]
{
	Set role = ##class(OcuTalon.Install.Step.Users).#SERVICEROLE
	If on {
		Set made = 0
		Set sc = ..MakeResource(resource, .made)
		If $$$ISERR(sc) Quit sc
		Set sc = ..SetPair(role, resource, 1)
		If $$$ISERR(sc) && made Do ..DropResource(resource)
		Quit sc
	}
	Set sc = ..SetPair(role, resource, 0)
	If $$$ISERR(sc) Quit sc
	Quit ..DropResource(resource)
}

/// Sets or removes the resource's pair on the role. A missing role is an error when the pair is to be added, and nothing to do when it is to be removed.
ClassMethod SetPair(role As %String, resource As %String, on As %Boolean) As %Status [ Private ]
{
	Set sc = ..RoleResources(role, .current, .exists)
	If $$$ISERR(sc) Quit sc
	If 'exists {
		If 'on Quit $SYSTEM.Status.OK()
		Quit $SYSTEM.Status.Error(5001, "The role " _ role _ " does not exist, so no MCP server resource was granted")
	}
	Set wanted = ..WithPair(current, resource, on)
	If wanted = current Quit $SYSTEM.Status.OK()
	Quit ..SetRoleResources(role, wanted)
}

/// The %SYS calls below switch to %SYS, make one Security call and return; none uses a method of this class there.
/// Creates the resource with no public permission when it does not exist; made is 1 when this call created it.
ClassMethod MakeResource(resource As %String, Output made As %Boolean) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set made = 0
	If ##class(Security.Resources).Exists(resource) Quit $SYSTEM.Status.OK()
	Set sc = ##class(Security.Resources).Create(resource, "OcuTalon MCP server tool access", "")
	Set made = $$$ISOK(sc)
	Quit sc
}

/// Deletes the resource when it exists.
ClassMethod DropResource(resource As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	If '##class(Security.Resources).Exists(resource) Quit $SYSTEM.Status.OK()
	Quit ##class(Security.Resources).Delete(resource)
}

/// The Resources property of the role (resource:permission pairs, comma-separated) and whether the role exists.
ClassMethod RoleResources(role As %String, Output resources As %String, Output exists As %Boolean) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Set resources = ""
	Set exists = ''##class(Security.Roles).Exists(role)
	If 'exists Quit $SYSTEM.Status.OK()
	Kill properties
	Set sc = ##class(Security.Roles).Get(role, .properties)
	Set resources = $Get(properties("Resources"))
	Quit sc
}

/// Sets the Resources property of the role.
ClassMethod SetRoleResources(role As %String, resources As %String) As %Status [ Private ]
{
	New $NAMESPACE
	Set $NAMESPACE = "%SYS"
	Kill properties
	Set properties("Resources") = resources
	Quit ##class(Security.Roles).Modify(role, .properties)
}

}
