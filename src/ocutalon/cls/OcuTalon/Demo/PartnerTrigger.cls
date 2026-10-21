/// PartnerTrigger, the business operation that makes the simulated partner send its orders (AD-14). A stub until Epic 4: it answers "not implemented".
Class OcuTalon.Demo.PartnerTrigger Extends Ens.BusinessOperation
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
