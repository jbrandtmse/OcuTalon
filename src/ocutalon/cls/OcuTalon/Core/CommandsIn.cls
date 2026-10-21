/// CommandsIn, the adapterless service that receives every command (AD-1); OcuTalon.Core.Commands.Submit is the way in. A stub until Story 2.3: it answers "not implemented".
Class OcuTalon.Core.CommandsIn Extends Ens.BusinessService
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
