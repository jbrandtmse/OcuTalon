/// Telegram's inbound service, a stub (AD-14, AD-29). The production keeps TelegramIn disabled until the Telegram
/// epic, which implements it; Included() is the switch that the Telegram installer step reads (AD-23). Until then it
/// answers "not implemented".
Class OcuTalon.Channel.Telegram.In Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

/// Marks an item that is not built yet. The owner deletes this parameter and the stub handler when it builds the item;
/// Story 11.5's release check refuses an enabled item whose class still has it.
Parameter STUB = 1;

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Quit $$$ERROR($$$NotImplemented)
}

/// 1 when this release includes Telegram: only when the test-only global ^OcuTalonTest("TelegramIncluded") is 1,
/// which OcuTalon.Test classes set and the judges' install never does. Otherwise 0.
ClassMethod Included() As %Boolean
{
	Quit $Get(^OcuTalonTest("TelegramIncluded")) = 1
}

}
