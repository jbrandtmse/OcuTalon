/// The contract of an installer step (AD-23). A class under OcuTalon.Install.Step.<Area> extends this class,
/// and the registry (OcuTalon.Install.Registry) discovers it. These methods do nothing by default, so an
/// area overrides only what it declares:
///   - Run() is the step itself, called once per start in the registry's fixed order, if the area is in the order;
///   - Grants() declares roles and what they hold, which the Roles step composes;
///   - Reconcile() re-arms the area's waiters and rows, which the Reconcile step calls;
///   - Tasks() declares scheduled tasks, which the Tasks step creates once;
///   - Purge() removes the area's old records for the purge task (AD-27).
/// Warn(text) and TakeWarnings() are shared helpers that an area calls and never overrides: Warn records a warning of the
/// running step, which the registry prints after the step's own line as WARN <step> <text>; outside the registry the
/// warnings stay with the caller until it takes them with TakeWarnings().
Class OcuTalon.Install.Step [ Abstract ]
{

/// The step itself. A failure stops the start before the ready marker is written.
ClassMethod Run() As %Status
{
	Quit $SYSTEM.Status.OK()
}

/// The role grants of the area, as a dynamic array of {"role","resource","permission"}.
/// Role names start with "OcuTalon". An empty resource declares the role alone. The permission is
/// any of "R", "W" and "U".
ClassMethod Grants() As %DynamicArray
{
	Quit []
}

/// Re-arms the area's waiters and rows after a start or an upgrade. Idempotent.
ClassMethod Reconcile() As %Status
{
	Quit $SYSTEM.Status.OK()
}

/// The scheduled tasks of the area, as a dynamic array of
/// {"name","taskClass","description","task":{<%SYS.Task property>:value},"settings":{<task property>:value}}.
/// Task names start with "OcuTalon". The Tasks step creates each task once and leaves an existing one alone.
ClassMethod Tasks() As %DynamicArray
{
	Quit []
}

/// Removes the area's records older than daysToKeep days.
ClassMethod Purge(daysToKeep As %Integer) As %Status
{
	Quit $SYSTEM.Status.OK()
}

/// Records one warning line of the running step, in a process-private global; a carriage return or a line feed in the text
/// becomes a space. A step that succeeds and has something to say calls this and returns OK. The registry takes the lines
/// after each step and writes them; code that runs a step on its own takes them with TakeWarnings.
ClassMethod Warn(text As %String)
{
	Set ^||OcuTalonStepWarnings($Increment(^||OcuTalonStepWarnings)) = $Translate(text, $Char(13, 10), "  ")
}

/// The recorded warning lines in the order they were recorded, as a list ("" when there are none), and clears them.
ClassMethod TakeWarnings() As %List
{
	Set lines = ""
	Set n = ""
	For {
		Set n = $Order(^||OcuTalonStepWarnings(n), 1, line)
		Quit:n=""
		Set lines = lines _ $ListBuild(line)
	}
	Kill ^||OcuTalonStepWarnings
	Quit lines
}

}
