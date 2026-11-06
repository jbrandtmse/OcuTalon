/// MemoryOps (AD-21, AD-33; Lane A): the business operation that keeps a session's memories. An adapterless operation, like WatchOps.
/// THIS CLASS IS A STUB until Story 19.3: it carries STUB and answers "not implemented" (code 5003) to every message, writes no row and
/// sends nothing. The item is disabled in the production.
/// The contract it will keep (spine AD-21, "Memory (step 3)"):
///   - it answers OcuTalon.Msg.Command.SaveMemory and OcuTalon.Msg.Command.ForgetMemory from CommandsIn with a CommandResult (from
///     Epic 41 also PinMemory and UnpinMemory);
///   - it alone writes OcuTalon.Data.Memory; reads go through OcuTalon.Memory.Search and OcuTalon.Memory.List;
///   - a memory holds at most 2,000 characters and is owned by the session that saved it.
Class OcuTalon.Memory.Ops Extends Ens.BusinessOperation
{

/// Marks an item that is not built yet (Story 19.3).
Parameter STUB = 1;

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
