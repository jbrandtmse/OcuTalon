/// ReminderOps, the business operation that sets, lists and cancels reminders (AD-5). A stub until Epic 8: it answers "not implemented".
Class OcuTalon.Schedule.ReminderOps Extends Ens.BusinessOperation
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
