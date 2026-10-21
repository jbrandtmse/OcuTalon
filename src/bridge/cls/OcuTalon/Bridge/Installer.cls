/// The bridge's own installer. It loads and runs without IPM and without any other OcuTalon package,
/// so the bridge can be installed alone from src/bridge/ (AD-2).
/// The after-start script's registry calls Run() as its first step.
Class OcuTalon.Bridge.Installer
{

/// Prepares what the bridge needs in the current namespace: it registers the audit events of OcuTalon.Bridge.Audit and
/// writes the three model families of OcuTalon.Bridge.Data.ModelFamily (AD-7).
/// Returns an error naming the namespace when it is not an Interoperability namespace.
ClassMethod Run() As %Status
{
	If '##class(%Library.EnsembleMgr).IsEnsembleNamespace($Namespace) {
		Quit $$$ERROR($$$GeneralError, "Namespace "_$Namespace_" is not an Interoperability namespace")
	}
	Set sc = ..RegisterAudit()
	If $$$ISERR(sc) Quit sc
	Quit ..SeedModelFamilies()
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

/// Creates each of OcuTalon.Bridge.Audit.Events() that is missing, enabled, and enables each one that is disabled.
/// The events are structural: they are re-enabled at every start. Instance-wide auditing is never changed.
ClassMethod RegisterAudit() As %Status
{
	Quit ..AuditEvents(1)
}

/// Fails, naming the first of OcuTalon.Bridge.Audit.Events() that is missing or disabled. Changes nothing.
ClassMethod CheckAudit() As %Status
{
	Quit ..AuditEvents(0)
}

/// The class's only method that switches to %SYS (AD-3): registers (create is true) or checks (create is false) the audit events.
ClassMethod AuditEvents(create As %Boolean) As %Status [ Private ]
{
	Set events = ##class(OcuTalon.Bridge.Audit).Events()
	New $Namespace
	Set $Namespace = "%SYS"
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
