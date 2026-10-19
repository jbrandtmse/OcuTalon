/// NoticesIn, the adapterless service that receives the notifications that the bridge sends (AD-32). A stub until Epic 2: it answers "not implemented".
Class OcuTalon.Core.NoticesIn Extends Ens.BusinessService
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
