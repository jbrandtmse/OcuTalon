/// The bridge's own installer. It loads and runs without IPM and without any other OcuTalon package,
/// so the bridge can be installed alone from src/bridge/ (AD-2).
/// The after-start script's registry calls Run() as its first step.
Class OcuTalon.Bridge.Installer
{

/// Prepares what the bridge needs in the current namespace: it registers the audit events of OcuTalon.Bridge.Audit, sets up the
/// approvals' Workflow role and user (SetUpApprovals, AD-11), writes the three model families of OcuTalon.Bridge.Data.ModelFamily (AD-7)
/// and the prices of the two Claude models of OcuTalon.Bridge.Data.Price that the product ships (AD-19, AD-20).
/// Returns an error naming the namespace when it is not an Interoperability namespace.
ClassMethod Run() As %Status
{
	If '##class(%Library.EnsembleMgr).IsEnsembleNamespace($Namespace) {
		Quit $$$ERROR($$$GeneralError, "Namespace "_$Namespace_" is not an Interoperability namespace")
	}
	Set sc = ..RegisterAudit()
	If $$$ISERR(sc) Quit sc
	Set sc = ..SetUpApprovals()
	If $$$ISERR(sc) Quit sc
	Set sc = ..SeedModelFamilies()
	If $$$ISERR(sc) Quit sc
	Quit ..SeedPrices()
}

/// The model families that the bridge writes, each a $ListBuild(Family, ModelPrefix, CapKey, EffortKey) (AD-7). The longest
/// ModelPrefix that a model starts with selects the family. Only the Anthropic family takes an effort; the default family
/// takes the cap only, until a story tests another family's own field.
ClassMethod ModelFamilies() As %List
{
	Quit $ListBuild(
		$ListBuild("anthropic", "claude-", "max_tokens", "extra_params.output_config.effort"),
		$ListBuild("gpt-5", "gpt-5", "extra_params.max_completion_tokens", ""),
		$ListBuild("default", "", "max_tokens", ""))
}

/// Writes the rows of ModelFamilies(), by Family: a row that exists gets the values again, and a row of another family is
/// left alone. The three rows are structural (AD-19): they are rewritten at every start.
ClassMethod SeedModelFamilies() As %Status
{
	Set families = ..ModelFamilies()
	Set position = 0
	While $ListNext(families, position, family) {
		Set name = $List(family, 1)
		If ##class(OcuTalon.Bridge.Data.ModelFamily).FamilyIndexExists(name, .id) {
			Set row = ##class(OcuTalon.Bridge.Data.ModelFamily).%OpenId(id, , .sc)
			If $$$ISERR(sc) Return sc
		} Else {
			Set row = ##class(OcuTalon.Bridge.Data.ModelFamily).%New()
			Set row.Family = name
		}
		Set row.ModelPrefix = $List(family, 2)
		Set row.CapKey = $List(family, 3)
		Set row.EffortKey = $List(family, 4)
		Set sc = row.%Save()
		If $$$ISERR(sc) Return sc
	}
	Quit $$$OK
}

/// The prices that the bridge seeds, each a $ListBuild(Model, InputPerMTok, OutputPerMTok, CacheReadPerMTok, CacheWritePerMTok,
/// LongThresholdTokens, LongInputPerMTok, LongOutputPerMTok), in US dollars per million tokens (AD-19, FR-2). The cache-write
/// rate is the 5-minute rate, 1.25 times the input price, the only one AI Hub writes; the cache-read rate is 0.1 times the input
/// price. Claude Haiku 5.5 has a long tier above 100,000 tokens, and Claude Sonnet 5.5 has none, so its base rates apply at every size.
ClassMethod Prices() As %List
{
	Quit $ListBuild(
		$ListBuild("claude-haiku-5-5", 0.1, 0.5, 0.01, 0.125, 100000, 0.5, 2.5),
		$ListBuild("claude-sonnet-5-5", 2, 10, 0.2, 2.5, "", "", ""))
}

/// Creates the rows of Prices() that no row has the Model of. A row that exists is left alone, whatever it holds: the prices are
/// seed values (AD-19), so an admin's edit survives every start, and a deleted row is created again.
ClassMethod SeedPrices() As %Status
{
	Set prices = ..Prices()
	Set position = 0
	While $ListNext(prices, position, price) {
		If ##class(OcuTalon.Bridge.Data.Price).ModelIndexExists($List(price, 1)) Continue
		Set row = ##class(OcuTalon.Bridge.Data.Price).%New()
		Set row.Model = $List(price, 1)
		Set row.InputPerMTok = $List(price, 2)
		Set row.OutputPerMTok = $List(price, 3)
		Set row.CacheReadPerMTok = $List(price, 4)
		Set row.CacheWritePerMTok = $List(price, 5)
		Set row.LongThresholdTokens = $List(price, 6)
		Set row.LongInputPerMTok = $List(price, 7)
		Set row.LongOutputPerMTok = $List(price, 8)
		Set sc = row.%Save()
		If $$$ISERR(sc) Return sc
	}
	Quit $$$OK
}

/// Creates each of OcuTalon.Bridge.Audit.Events() that is missing, enabled, and enables each one that is disabled.
/// The events are structural: they are re-enabled at every start. Instance-wide auditing is never changed.
ClassMethod RegisterAudit() As %Status
{
	Quit ..InSystem("audit")
}

/// Fails, naming the first of OcuTalon.Bridge.Audit.Events() that is missing or disabled. Changes nothing.
ClassMethod CheckAudit() As %Status
{
	Quit ..InSystem("check")
}

/// Reads whether instance-wide auditing is on (Security.System AuditEnabled of SYSTEM): enabled is 1 or 0. It is a read only, and OcuTalon
/// never changes the setting (AD-17). When IRIS audit is off it writes none of OcuTalon's entries. An error status, with enabled empty, when
/// the setting cannot be read.
ClassMethod InstanceAuditing(Output enabled As %Boolean) As %Status
{
	Quit ..InSystem("auditing", .enabled)
}

/// Sets up what approvals need in the current namespace (AD-11, AD-24), at every start and on its own:
///   - the Workflow role Approval WORKFLOWROLE exists;
///   - the Workflow user Approval WORKFLOWUSER exists and is active, because only active members get tasks;
///   - that user is a member of the role and every other member is removed from it, so the Workflow inbox can't answer for a person;
///   - the IRIS user of the same name exists with login disabled, no roles and no escalation roles (InSystem).
/// It deletes no Workflow user, role or membership that is not the role's own: a developer's namespace may hold other Workflow users for
/// another production, and only the role's membership decides who receives its tasks.
ClassMethod SetUpApprovals() As %Status
{
	Set role = ##class(OcuTalon.Bridge.Approval).#WORKFLOWROLE
	Set user = ##class(OcuTalon.Bridge.Approval).#WORKFLOWUSER
	If '##class(EnsLib.Workflow.RoleDefinition).%ExistsId(role) {
		Set sc = ##class(EnsLib.Workflow.RoleDefinition).CreateRole(role)
		If $$$ISERR(sc) Quit ..Fail("the Workflow role "_role, sc)
	}
	If ##class(EnsLib.Workflow.UserDefinition).%ExistsId(user) {
		Set definition = ##class(EnsLib.Workflow.UserDefinition).%OpenId(user, , .sc)
		If $$$ISERR(sc) Quit ..Fail("the Workflow user "_user, sc)
		If 'definition.IsActive {
			Set definition.IsActive = 1
			Set sc = definition.%Save()
			If $$$ISERR(sc) Quit ..Fail("the Workflow user "_user, sc)
		}
	} Else {
		Set sc = ##class(EnsLib.Workflow.UserDefinition).CreateUser(user, "OcuTalon approvals")
		If $$$ISERR(sc) Quit ..Fail("the Workflow user "_user, sc)
	}
	Set members = ""
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT UserName FROM EnsLib_Workflow.RoleMembership WHERE RoleName = ?", role)
	If result.%SQLCODE < 0 Quit ..Fail("the members of the Workflow role "_role, $SYSTEM.Status.Error(5001, "SQLCODE "_result.%SQLCODE_" "_result.%Message))
	While result.%Next() {
		Set members = members _ $ListBuild(result.%Get("UserName"))
	}
	Set position = 0
	While $ListNext(members, position, member) {
		If member = user Continue
		Set sc = ##class(EnsLib.Workflow.RoleDefinition).RemoveUserFromRole(role, member)
		If $$$ISERR(sc) Quit
	}
	If $$$ISERR(sc) Quit ..Fail("the Workflow role "_role, sc)
	If '$ListFind(members, user) {
		Set sc = ##class(EnsLib.Workflow.RoleDefinition).AddUserToRole(role, user)
		If $$$ISERR(sc) Quit ..Fail("the Workflow role "_role, sc)
	}
	Quit ..InSystem("login")
}

/// An error status that names what could not be set up and the reason.
ClassMethod Fail(what As %String, sc As %Status) As %Status [ Private ]
{
	Quit $SYSTEM.Status.Error(5001, "The bridge installer could not set up "_what_": "_$SYSTEM.Status.GetErrorText(sc))
}

/// The class's only method that switches to %SYS (AD-3, AD-17). The action is one of:
///   - audit: registers each of OcuTalon.Bridge.Audit.Events() and enables each one that is disabled;
///   - check: fails for the first of them that is missing or disabled and changes nothing;
///   - auditing: reads instance-wide auditing into enabled (1 or 0) and changes nothing;
///   - login: makes the IRIS user of Approval WORKFLOWUSER, with login disabled, no roles, no escalation roles and a random password
///     of 44 characters that nothing reads. A user that exists gets Enabled 0, no roles and no escalation role, and keeps its password.
///     The user holds the name, so an account made later under it cannot sign in to the Workflow inbox.
/// Only Security classes and $SYSTEM are used after the switch, because the bridge's classes are not mapped to %SYS.
ClassMethod InSystem(action As %String, Output enabled As %Boolean) As %Status [ Private ]
{
	Set enabled = ""
	Set home = $Namespace
	Set events = ##class(OcuTalon.Bridge.Audit).Events()
	Set user = ##class(OcuTalon.Bridge.Approval).#WORKFLOWUSER
	New $Namespace
	Set $Namespace = "%SYS"
	If action = "auditing" {
		Set sc = ##class(Security.System).Get("SYSTEM", .system)
		If $$$ISERR(sc) Quit sc
		Set enabled = $Select($Get(system("AuditEnabled")): 1, 1: 0)
		Quit $$$OK
	}
	If action = "login" {
		If ##class(Security.Users).Exists(user) {
			Kill properties
			Set properties("Enabled") = 0
			Set properties("Roles") = ""
			Set properties("EscalationRoles") = ""
			Set sc = ##class(Security.Users).Modify(user, .properties)
		} Else {
			Set password = $SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(32), 1)
			Set sc = ##class(Security.Users).Create(user, "", password, "OcuTalon Workflow user", home, "", "", 0, 0, "Created by the OcuTalon bridge installer; login is disabled.", 1, "", "", , 1, 1)
		}
		If $$$ISERR(sc) Quit $SYSTEM.Status.Error(5001, "The bridge installer could not set up the login of the Workflow user "_user_": "_$SYSTEM.Status.GetErrorText(sc))
		Quit sc
	}
	Set create = (action = "audit")
	Set position = 0
	While $ListNext(events, position, name) {
		Kill event, properties
		Set exists = ##class(Security.Events).Exists(name, , , .event)
		If exists && event.Enabled Continue
		If 'create {
			Return $$$ERROR($$$GeneralError, "Audit event "_name_$Select(exists: " is disabled", 1: " is not registered"))
		}
		If exists {
			Set properties("Enabled") = 1
			Set sc = ##class(Security.Events).Modify(name, , , .properties)
		} Else {
			Set sc = ##class(Security.Events).Create(name, , , "OcuTalon audit event "_name, 1, 0)
		}
		If $$$ISERR(sc) Return sc
	}
	Quit $$$OK
}

}
