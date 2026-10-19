/// TelegramOut, the business operation that sends a message to the paired Telegram chat (AD-14). A stub until the Telegram epic (Story 12.6): it answers "not implemented", and the production keeps it disabled.
Class OcuTalon.Channel.Telegram.Out Extends Ens.BusinessOperation
{

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnMessage(pRequest As %Library.Persistent, Output pResponse As %Library.Persistent) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

}
