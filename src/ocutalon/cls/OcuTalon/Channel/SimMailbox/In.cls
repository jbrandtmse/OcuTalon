/// SimMailboxIn, the adapterless service through which a simulated email arrives (AD-14). A stub until Epic 4: it answers "not implemented".
Class OcuTalon.Channel.SimMailbox.In Extends Ens.BusinessService
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
