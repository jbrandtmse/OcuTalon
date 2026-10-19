/// The bridge's own installer. It loads and runs without IPM and without any other OcuTalon package,
/// so the bridge can be installed alone from src/bridge/ (AD-2).
/// The after-start script's registry calls Run() as its first step.
Class OcuTalon.Bridge.Installer
{

/// Prepares what the bridge needs in the current namespace: it registers the audit events of OcuTalon.Bridge.Audit.
/// Returns an error naming the namespace when it is not an Interoperability namespace.
ClassMethod Run() As %Status
{
	If '##class(%Library.EnsembleMgr).IsEnsembleNamespace($Namespace) {
		Quit $$$ERROR($$$GeneralError, "Namespace "_$Namespace_" is not an Interoperability namespace")
	}
	Quit ..RegisterAudit()
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
