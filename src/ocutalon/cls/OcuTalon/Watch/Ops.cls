/// WatchOps, the business operation that starts and stops watches of a production (AD-15). A stub until Epic 5: it answers "not implemented".
Class OcuTalon.Watch.Ops Extends Ens.BusinessOperation
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
