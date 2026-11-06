/// DocumentOps (AD-21, AD-33; Lane A): the business operation that keeps the documents a session or an install has added. An adapterless
/// operation, like WatchOps. THIS CLASS IS A STUB until Story 19.4: it carries STUB and answers "not implemented" (code 5003) to every
/// message, writes no row and sends nothing. The item is disabled in the production.
/// The contract it will keep (spine AD-21, "Documents (step 3)"):
///   - it answers OcuTalon.Msg.Command.AddDocument and OcuTalon.Msg.Command.RemoveDocument from CommandsIn, synchronously, with a CommandResult;
///   - it alone writes OcuTalon.Data.Document, one row for each document, and indexes the text asynchronously;
///   - it is the single publisher of the document live event (OcuTalon.Live.Payload.Document).
Class OcuTalon.Docs.Ops Extends Ens.BusinessOperation
{

/// Marks an item that is not built yet (Story 19.4).
Parameter STUB = 1;

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
