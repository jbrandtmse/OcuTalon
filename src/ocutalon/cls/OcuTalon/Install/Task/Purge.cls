/// The daily purge task (AD-27). It calls the Purge(daysToKeep) of every area through the registry.
/// DaysToKeep is a task property: the Tasks step writes it when it creates the task, and a value changed
/// in the Task Manager is kept.
Class OcuTalon.Install.Task.Purge Extends %SYS.Task.Definition
{

Parameter TaskName = "OcuTalon purge";

/// The number of days of records to keep.
Property DaysToKeep As %Integer [ InitialExpression = 90 ];

Method OnTask() As %Status
{
	Quit ##class(OcuTalon.Install.Registry).Purge(..DaysToKeep)
}

}
