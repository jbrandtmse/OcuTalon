/// OcuTalon.Channel.Telegram.Out with its seams under test control (test only; Story 17.10). It is not an item of any production, and the product never
/// refers to it. A test makes a shadow instance and calls OnNotification as the framework would. It overrides:
///   - Send records each text and markup, in order, as ^||TelegramProbe("sent", n) = $ListBuild(text, markup as JSON or ""), and answers one sent part with
///     the message id 1, so that nothing leaves the process;
///   - Target gives a fixed chat (the Ref TGPROBECHAT and the id 84017734199) and reads no Pairing row;
///   - Recorded writes no Delivery row.
Class OcuTalon.Test.Digest.TelegramOutProbe Extends OcuTalon.Channel.Telegram.Out
{

/// Forgets what the probe recorded.
ClassMethod Reset()
{
	Kill ^||TelegramProbe
}

/// The number of texts sent.
ClassMethod Count() As %Integer
{
	Quit +$Get(^||TelegramProbe("sent"))
}

/// The text of the nth send.
ClassMethod TextOf(n As %Integer) As %String
{
	Quit $ListGet($Get(^||TelegramProbe("sent", n)), 1)
}

/// The markup of the nth send, as JSON, or "" for none.
ClassMethod MarkupOf(n As %Integer) As %String
{
	Quit $ListGet($Get(^||TelegramProbe("sent", n)), 2)
}

Method Send(chatId As %String, text As %String, Output messageId As %String, Output sent As %Integer, markup As %DynamicObject = "", limit As %Integer = "", Output lastText As %String) As %Status
{
	Set n = $Increment(^||TelegramProbe("sent"))
	Set ^||TelegramProbe("sent", n) = $ListBuild(text, $Select($IsObject(markup): markup.%ToJSON(), 1: ""))
	Set messageId = 1, sent = 1, lastText = text
	Quit $$$OK
}

Method Target(ownerChatRef As %String, sessionRef As %String, Output chatRef As %String, Output chatId As %String) As %Status [ Private ]
{
	Set chatRef = "TGPROBECHAT", chatId = "84017734199"
	Quit $$$OK
}

Method Recorded(sessionRef As %String, channelMessageId As %String, approvalRef As %String, kind As %String, decisionRef As %String, text As %String = "") As %Status [ Private ]
{
	Quit $$$OK
}

}
