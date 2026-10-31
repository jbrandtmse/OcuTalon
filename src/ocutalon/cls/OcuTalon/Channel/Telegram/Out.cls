/// TelegramOut, the outbound operation of the Telegram channel (Story 12.2; AD-14, AD-19, AD-32, UX-DR108, UX-DR136). It sends the text of
/// an OcuTalon.Msg.Outbound or an OcuTalon.Msg.Notification that names a chat by ChatRef, through OcuTalon.Channel.Telegram.Api:
///   - the text is the Outbound's Text, else the catalog rendering of its CatalogKey for the channel telegram; a Notification's text is
///     the rendering of its CatalogKey. A render error is returned and nothing is sent;
///   - the chat is the ChatId of the Pairing chat row of the ChatRef. A ChatRef with no chat row, or none, sends nothing: one warning
///     that names neither a Ref nor an id, and the status is OK;
///   - the text goes as plain text, exactly as written, with no parse mode and no entities, as sendMessage parts of at most 4,096
///     UTF-16 units (Api.Split), in order. A 429 waits retry_after seconds (at least 1) and sends the same part again, at most TRIES
///     tries for one part, and a part that was sent is never sent twice. Any other failure is an error status with a safe text, and the
///     parts already sent stay sent.
/// Routing by SessionRef, Delivery rows and the message kinds come with Stories 12.6 and 12.7. The token is never held here (AD-19).
Class OcuTalon.Channel.Telegram.Out Extends OcuTalon.Channel.Operation
{

Parameter SETTINGS = "ApiBase:Telegram,SSLConfig:Telegram";

/// The base of the Bot API (the Telegram step writes the row at every start).
Property ApiBase As %String(MAXLEN = 200) [ InitialExpression = {##class(OcuTalon.Channel.Telegram.Api).#PUBLICBASE} ];

/// The client SSL configuration for an https base.
Property SSLConfig As %String(MAXLEN = 128) [ InitialExpression = {##class(OcuTalon.Channel.Telegram.Api).#SSLCONFIG} ];

/// The tries for one part when Telegram answers 429.
Parameter TRIES = 5;

/// The read timeout of one sendMessage, in seconds.
Parameter SENDSECONDS = 15;

/// The channel of the catalog text.
Parameter TEXTCHANNEL = "telegram";

Parameter LOGNOTASESSION = "TelegramOut dropped a message: its owner is not a session: ";

Parameter LOGPUBLISH = "TelegramOut could not publish an event: ";

Parameter LOGNOCHAT = "TelegramOut sent nothing: the message names no known Telegram chat.";

XData MessageMap
{
<MapItems>
<MapItem MessageType="OcuTalon.Msg.Outbound">
<Method>OnOutbound</Method>
</MapItem>
<MapItem MessageType="OcuTalon.Msg.Notification">
<Method>OnNotification</Method>
</MapItem>
</MapItems>
}

/// A reply: its text, or the rendering of its catalog key, goes to the chat.
Method OnOutbound(request As OcuTalon.Msg.Outbound, Output response As Ens.Response) As %Status
{
	Set response = ""
	Set text = request.Text
	If (text = "") && (request.CatalogKey '= "") {
		Set text = ##class(OcuTalon.Msg.Catalog).Render(request.CatalogKey, request.Slots, ..#TEXTCHANNEL, .sc)
		If $SYSTEM.Status.IsError(sc) Quit sc
	}
	Quit ..Deliver(request.ChatRef, text)
}

/// A notification: the rendering of its catalog key goes to the chat.
Method OnNotification(request As OcuTalon.Msg.Notification, Output response As Ens.Response) As %Status
{
	Set response = ""
	Set text = ##class(OcuTalon.Msg.Catalog).Render(request.CatalogKey, request.Slots, ..#TEXTCHANNEL, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Quit ..Deliver(request.ChatRef, text)
}

/// Sends the text to the chat of the ChatRef; with no such chat it logs one warning and sends nothing.
Method Deliver(chatRef As %String, text As %String) As %Status [ Private ]
{
	Set row = ##class(OcuTalon.Data.Pairing).Chat(chatRef)
	If '$IsObject(row) {
		$$$LOGWARNING(..#LOGNOCHAT)
		Quit $$$OK
	}
	Quit ..Send(row.ChatId, text)
}

/// The text to the chat as sendMessage parts, in order. The status is the first failure.
Method Send(chatId As %String, text As %String) As %Status
{
	Set parts = ##class(OcuTalon.Channel.Telegram.Api).Split(text)
	Set sc = $$$OK
	Set position = 0
	While $ListNext(parts, position, part) {
		If part = "" Continue
		Set sc = ..SendPart(chatId, part)
		If $SYSTEM.Status.IsError(sc) Quit
	}
	Quit sc
}

/// One part, as a numeric chat_id and plain text. A 429 waits and sends the same part again, TRIES tries at most.
Method SendPart(chatId As %String, part As %String) As %Status [ Private ]
{
	For try = 1:1:..#TRIES {
		Set params = {}
		Do params.%Set("chat_id", chatId, "number")
		Do params.%Set("text", part, "string")
		Set answer = ##class(OcuTalon.Channel.Telegram.Api).Call(..ApiBase, ..SSLConfig, "sendMessage", params, ..#SENDSECONDS, .httpStatus, .sc)
		If $SYSTEM.Status.IsError(sc) Quit
		If (httpStatus = 200) && +answer.ok {
			Set sc = $$$OK
			Quit
		}
		Set sc = $SYSTEM.Status.Error(5001, ##class(OcuTalon.Channel.Telegram.Api).Failure("sendMessage", httpStatus, answer))
		If (httpStatus '= 429) || (try = ..#TRIES) Quit
		Set wait = 1
		If $IsObject(answer.parameters) && (answer.parameters.%GetTypeOf("retry_after") = "number") && (answer.parameters."retry_after" > 1) Set wait = answer.parameters."retry_after"
		Hang wait
	}
	Quit sc
}

}
