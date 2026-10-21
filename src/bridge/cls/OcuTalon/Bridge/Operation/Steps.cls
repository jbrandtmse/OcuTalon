/// AgentSteps, the business operation that records the agent steps of a turn for Visual Trace (AD-6). A stub until
/// Story 1.5: it answers "not implemented".
Class OcuTalon.Bridge.Operation.Steps Extends Ens.BusinessOperation
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
