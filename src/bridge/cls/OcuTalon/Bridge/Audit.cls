/// The only writer of the IRIS audit log, for the bridge and for OcuTalon (AD-17). It declares OcuTalon's
/// user-defined audit events; OcuTalon.Bridge.Installer registers them, and nothing here changes instance-wide auditing.
Class OcuTalon.Bridge.Audit
{

/// The source of every OcuTalon audit event.
Parameter SOURCE = "OcuTalon";

/// The event types. Each event is named OcuTalon/<type>/<type>.
Parameter TYPES = "Action,Approval,Pairing,Settings,MCP,Tool";

/// The names of the six events, as "OcuTalon/<type>/<type>", in the order of TYPES.
ClassMethod Events() As %List
{
	Set events = ""
	Set types = $ListFromString(..#TYPES)
	Set position = 0
	While $ListNext(types, position, type) {
		Set events = events _ $ListBuild(..#SOURCE_"/"_type_"/"_type)
	}
	Quit events
}

/// Writes one audit entry of the given type, with data as the entry's event data and description cut at 128 bytes.
/// The data is written as given: this method neither redacts it nor adds anything, so the caller puts in what AD-17 asks
/// of every entry's data (the acting user, their role, the SessionRef and the channel) and leaves out any key, token or
/// password.
/// A type that is not in TYPES is refused with an error status that names it. Otherwise the status is that of
/// $SYSTEM.Security.Audit: a success when the entry is written, and 0, which is not a success, when the event is not
/// registered (measured on build 154). The entry can take about a minute to be readable in %SYS.Audit.
ClassMethod Write(type As %String, data As %DynamicObject, description As %String = "") As %Status
{
	If '$ListFind($ListFromString(..#TYPES), type) {
		Quit $SYSTEM.Status.Error(5001, "'"_type_"' is not an OcuTalon audit type")
	}
	If '$IsObject(data) || ($ClassName(data) '= "%Library.DynamicObject") {
		Quit $SYSTEM.Status.Error(5001, "The audit data must be a dynamic object")
	}
	Quit $SYSTEM.Security.Audit(..#SOURCE, type, type, data.%ToJSON(), description)
}

}
