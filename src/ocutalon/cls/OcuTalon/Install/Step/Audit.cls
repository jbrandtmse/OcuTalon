/// The Audit step: confirms that OcuTalon's audit events are registered and enabled, and reports whether instance-wide auditing is on
/// (AD-17, AD-23).
///   - OcuTalon.Bridge.Installer registers the events in its own step, which runs first; this step fails the start, naming the event,
///     when one is missing or disabled.
///   - IRIS writes none of OcuTalon's entries while instance-wide auditing is off, and reports nothing, so the step reads the setting
///     (Installer.InstanceAuditing, a read only) and records on, off or unknown (the read failed) in the status mark MARK, only when the
///     value differs from the stored one, so the mark's RecordedAt says since when it holds. When it is off, or cannot be read, the step
///     warns (Warn). A mark that cannot be written is a warning too. A warning never fails the start; OcuTalon never changes the setting.
Class OcuTalon.Install.Step.Audit Extends OcuTalon.Install.Step
{

/// The status mark that holds whether instance-wide auditing is on: on, off or unknown.
Parameter MARK = "instanceAuditing";

/// The class whose InstanceAuditing reads the setting. A test subclass names a class whose read fails, because the real read cannot.
Parameter INSTALLER = "OcuTalon.Bridge.Installer";

/// The class whose Get and Record keep the mark. A test subclass names a class whose Record fails, because the real one cannot.
Parameter MARKS = "OcuTalon.Data.StatusMark";

/// Fails when an audit event is missing or disabled. Otherwise it records the state of instance-wide auditing and warns when it is off or
/// unknown, and returns OK.
ClassMethod Run() As %Status
{
	Set sc = ##class(OcuTalon.Bridge.Installer).CheckAudit()
	If $$$ISERR(sc) Quit sc
	Set sc = $ClassMethod(..#INSTALLER, "InstanceAuditing", .enabled)
	If $$$ISERR(sc) {
		Set state = "unknown"
		Do ..Warn("could not read whether instance-wide auditing is on: " _ $SYSTEM.Status.GetErrorText(sc))
	} ElseIf enabled {
		Set state = "on"
	} Else {
		Set state = "off"
		Do ..Warn("instance-wide auditing is off, so IRIS writes none of OcuTalon's audit entries; OcuTalon does not change this setting: an administrator turns it on in the Management Portal (System Administration > Security > Auditing > Enable Auditing)")
	}
	If $ClassMethod(..#MARKS, "Get", ..#MARK) = state Quit $$$OK
	Set sc = $ClassMethod(..#MARKS, "Record", ..#MARK, state)
	If $$$ISERR(sc) Do ..Warn("could not record the instance-wide auditing status (" _ state _ "): " _ $SYSTEM.Status.GetErrorText(sc))
	Quit $$$OK
}

}
