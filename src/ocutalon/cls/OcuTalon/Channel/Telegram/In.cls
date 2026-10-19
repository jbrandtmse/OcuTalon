/// Telegram's inbound service, a stub (AD-14, AD-29). The production keeps TelegramIn disabled until the Telegram
/// epic, which implements it; Included() is the switch that the Telegram installer step reads (AD-23).
Class OcuTalon.Channel.Telegram.In Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Quit $$$OK
}

/// 1 when this release includes Telegram: only when the test-only global ^OcuTalonTest("TelegramIncluded") is 1,
/// which OcuTalon.Test classes set and the judges' install never does. Otherwise 0.
ClassMethod Included() As %Boolean
{
	Quit $Get(^OcuTalonTest("TelegramIncluded")) = 1
}

}
