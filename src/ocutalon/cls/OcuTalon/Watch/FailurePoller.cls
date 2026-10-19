/// FailurePoller, the service that picks up new failures of the watched production (AD-15). A stub until Epic 5: it has no
/// adapter and no pool yet, and answers "not implemented"; its owner adds the polling adapter.
Class OcuTalon.Watch.FailurePoller Extends Ens.BusinessService
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
