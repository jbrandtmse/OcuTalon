/// The contract of an installer step (AD-23). A class under OcuTalon.Install.Step.<Area> extends this class,
/// and the registry (OcuTalon.Install.Registry) discovers it. Every method does nothing by default, so an
/// area overrides only what it declares:
///   - Run() is the step itself, called once per start in the registry's fixed order, if the area is in the order;
///   - Grants() declares roles and what they hold, which the Roles step composes;
///   - Reconcile() re-arms the area's waiters and rows, which the Reconcile step calls;
///   - Tasks() declares scheduled tasks, which the Tasks step creates once;
///   - Purge() removes the area's old records for the purge task (AD-27).
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

}
