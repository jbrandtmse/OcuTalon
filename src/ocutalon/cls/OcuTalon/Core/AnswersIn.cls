/// AnswersIn, the adapterless service that receives the answer to an approval request from a channel (AD-11). A stub until Epic 6: it answers "not implemented".
Class OcuTalon.Core.AnswersIn Extends Ens.BusinessService
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
