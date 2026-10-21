/// EvalIn, the adapterless service that feeds evaluation cases into the product path (AD-22). A stub until Epic 9: it answers "not implemented". The production keeps it disabled; the Production install step enables it only when OCUTALON_EVAL is 1.
Class OcuTalon.Eval.In Extends Ens.BusinessService
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
