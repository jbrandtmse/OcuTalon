/// Checks, the business process that runs the background checks on every heartbeat (AD-18). A stub until Epic 5: it answers "not implemented".
Class OcuTalon.Checks.Process Extends Ens.BusinessProcess
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
