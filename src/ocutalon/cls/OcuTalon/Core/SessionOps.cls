/// SessionOps, the business operation that carries out the session commands (AD-1, AD-4). A stub until Epic 2: it answers "not implemented".
Class OcuTalon.Core.SessionOps Extends Ens.BusinessOperation
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
