Include Ensemble

/// TelegramIn, the inbound service of the Telegram channel (Story 12.2; AD-14, AD-18, AD-19, AD-5). An Ens.InboundAdapter service whose
/// CallInterval is 1 second in the production: each run makes at most one Bot API call, so a 5-second long poll follows the one before it.
/// Included() is the switch that the Telegram installer step reads (AD-23); the step also writes the ApiBase row from
/// OCUTALON_TELEGRAM_API_BASE at every start, and the SSL step makes the client SSL configuration that SSLConfig names.
///   - The token comes only from the environment, through OcuTalon.Channel.Telegram.Api, on every call. This class never holds, logs or
///     records it.
///   - OnInit makes no network call and records the Telegram state off. A run that has not started yet calls getMe: the answer's user
///     name is recorded with the state on before the first poll. Only a 401 or 404 means that Telegram rejected the token: the state is
///     rejected, the log says so without the token, and the item stays off until the next start. Any other failure is a warning and
///     another try after RETRYSECONDS. OnTearDown records off, unless the state this job recorded is rejected.
///   - Then each run makes one getUpdates call (timeout POLLSECONDS, read timeout POLLSECONDS plus READMARGIN, inside the 10 seconds of an
///     item stop), with the offset of the node $$$EnsStaticAppData("TelegramIn", "offset") when it has one. The node is read before every
///     poll and written after each handled update: an update below it is skipped, and an update that cannot be handled is logged and
///     confirmed. No other copy of the offset exists (AD-5).
///   - Only an update of a private chat, a message or a button press, is handled, and handling it records the chat through
///     Pairing.RecordChat with no name. Everything else is confirmed and ignored; the from name of an update is not stored.
///   - A 409 pauses the item PAUSESECONDS: the time is written to StatusMark.Record("telegramPaused", until), which is the one truth of
///     the pause and is read before every poll, so a restart honours it. Its warning carries Telegram's description, which says whether
///     another process polls the bot or a webhook is set. A getUpdates answered 200 deletes the mark. A 429 waits
///     retry_after seconds, or RETRYSECONDS. Every other answer is a warning and another try after RETRYSECONDS.
///   - OnProcessInput always returns OK and logs only warnings. No text it logs holds the token, a chat id or a name (AD-14).
Class OcuTalon.Channel.Telegram.In Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

Parameter SETTINGS = "ApiBase:Telegram,SSLConfig:Telegram";

/// The base of the Bot API (the Telegram step writes the row at every start).
Property ApiBase As %String(MAXLEN = 200) [ InitialExpression = {##class(OcuTalon.Channel.Telegram.Api).#PUBLICBASE} ];

/// The client SSL configuration for an https base.
Property SSLConfig As %String(MAXLEN = 128) [ InitialExpression = {##class(OcuTalon.Channel.Telegram.Api).#SSLCONFIG} ];

/// The seconds that a getUpdates waits for an update.
Parameter POLLSECONDS = 5;

/// The seconds beyond the poll that the HTTP read waits.
Parameter READMARGIN = 3;

/// The seconds of a pause after a 409.
Parameter PAUSESECONDS = 300;

/// The seconds to wait after a failure.
Parameter RETRYSECONDS = 5;

/// The status mark of the pause (AD-12).
Parameter PAUSEMARK = "telegramPaused";

Parameter LOGREJECTED = "Telegram rejected the bot token, so Telegram stays off until the next start.";

Parameter LOGFAILED = "TelegramIn could not complete a call: ";

Parameter LOGRECORD = "TelegramIn could not record its state: ";

Parameter LOGBUSY = "Telegram asked TelegramIn to wait before polling again; it waits ";

Parameter LOGPAUSE = "Telegram refused getUpdates with a conflict (another process polls the bot, or a webhook is set), so TelegramIn pauses until ";

Parameter LOGCHAT = "TelegramIn could not record a chat: ";

Parameter LOGUPDATE = "TelegramIn could not handle an update, and confirmed it: ";

/// 1 once getMe has answered and the state on is recorded.
Property Started As %Boolean [ InitialExpression = 0 ];

/// 1 when Telegram rejected the token at this start.
Property Rejected As %Boolean [ InitialExpression = 0 ];

/// The state this job recorded: off, on or rejected.
Property Recorded As %String [ InitialExpression = "off" ];

/// The time ($ZHorolog) before which no call is made after a failure or a 429.
Property RetryAt As %Numeric [ InitialExpression = 0 ];

Method OnInit() As %Status
{
	Set ..Started = 0
	Set ..Rejected = 0
	Set ..RetryAt = 0
	Set ..Recorded = "off"
	Do ..Record("off", "")
	Quit $$$OK
}

Method OnTearDown() As %Status
{
	If ..Recorded '= "rejected" Do ..Record("off", "")
	Quit $$$OK
}

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
	Set pOutput = ""
	Try {
		Do ..Run()
	} Catch exception {
		$$$LOGWARNING(..#LOGFAILED_##class(OcuTalon.Channel.Telegram.Api).Safe(exception.Name))
		Set ..RetryAt = $ZHorolog + ..#RETRYSECONDS
	}
	Quit $$$OK
}

/// Records the Telegram state with no user name; a failure is a warning.
Method Record(state As %String, botUserName As %String) [ Private ]
{
	Set recorded = ##class(OcuTalon.Data.StatusMark).RecordTelegram(state, botUserName)
	If $SYSTEM.Status.IsError(recorded) $$$LOGWARNING(..#LOGRECORD_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(recorded)))
}

/// One run: nothing while rejected, paused or waiting; otherwise getMe when not started, else one getUpdates.
Method Run() [ Private ]
{
	If ..Rejected Quit
	If ..RetryAt > $ZHorolog Quit
	If ..Paused() Quit
	If '..Started {
		Do ..Start()
	} Else {
		Do ..Poll()
	}
}

/// 1 when the pause mark names a time after now.
Method Paused() As %Boolean [ Private ]
{
	Set until = ##class(OcuTalon.Data.StatusMark).Get(..#PAUSEMARK)
	If until = "" Quit 0
	Set left = ##class(OcuTalon.Data.Time).Seconds(until)
	Set now = ##class(OcuTalon.Data.Time).Seconds(##class(OcuTalon.Data.Time).NowUtc())
	Quit (left '= "") && (now '= "") && (left > now)
}

/// The Bot API call of this item, with its two host settings.
Method Call(method As %String, params As %DynamicObject, Output httpStatus As %Integer, Output sc As %Status) As %DynamicObject [ Private ]
{
	Quit ##class(OcuTalon.Channel.Telegram.Api).Call(..ApiBase, ..SSLConfig, method, params, ..#POLLSECONDS + ..#READMARGIN, .httpStatus, .sc)
}

/// getMe: the bot's user name is recorded with the state on; 401 or 404 is a rejection; any other failure waits and tries again.
Method Start() [ Private ]
{
	Set answer = ..Call("getMe", {}, .httpStatus, .sc)
	If $SYSTEM.Status.IsError(sc) {
		Do ..Failed($SYSTEM.Status.GetErrorText(sc))
		Quit
	}
	If ..Rejection(httpStatus) Quit
	If (httpStatus '= 200) || '+answer.ok || ('$IsObject(answer.result)) || (answer.result.%GetTypeOf("username") '= "string") {
		Do ..Failed(##class(OcuTalon.Channel.Telegram.Api).Failure("getMe", httpStatus, answer))
		Quit
	}
	Set recorded = ##class(OcuTalon.Data.StatusMark).RecordTelegram("on", answer.result.username)
	If $SYSTEM.Status.IsError(recorded) {
		$$$LOGWARNING(..#LOGRECORD_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(recorded)))
		Set ..RetryAt = $ZHorolog + ..#RETRYSECONDS
		Quit
	}
	Set ..Recorded = "on"
	Set ..Started = 1
}

/// One getUpdates call and the handling of its answer.
Method Poll() [ Private ]
{
	Set params = {"allowed_updates": ["message", "callback_query"]}
	Do params.%Set("timeout", ..#POLLSECONDS, "number")
	Set offset = ..Kept()
	If offset '= "" Do params.%Set("offset", offset, "number")
	Set answer = ..Call("getUpdates", params, .httpStatus, .sc)
	If $SYSTEM.Status.IsError(sc) {
		Do ..Failed($SYSTEM.Status.GetErrorText(sc))
		Quit
	}
	If ..Rejection(httpStatus) Quit
	If (httpStatus = 200) && +answer.ok && $IsObject(answer.result) {
		Do ##class(OcuTalon.Data.StatusMark).Record(..#PAUSEMARK, "")
		Do ..Handle(answer.result)
		Quit
	}
	If httpStatus = 409 {
		Do ..Pause(answer)
		Quit
	}
	If httpStatus = 429 {
		Set wait = ..#RETRYSECONDS
		If $IsObject(answer.parameters) && (answer.parameters.%GetTypeOf("retry_after") = "number") && (answer.parameters."retry_after" > 0) Set wait = answer.parameters."retry_after"
		$$$LOGWARNING(..#LOGBUSY_wait_" seconds.")
		Set ..RetryAt = $ZHorolog + wait
		Quit
	}
	Do ..Failed(##class(OcuTalon.Channel.Telegram.Api).Failure("getUpdates", httpStatus, answer))
}

/// A 401 or a 404 means that Telegram rejected the token: the state is rejected and the item stays off until the next start. 1 for them.
Method Rejection(httpStatus As %Integer) As %Boolean [ Private ]
{
	If (httpStatus '= 401) && (httpStatus '= 404) Quit 0
	Set ..Rejected = 1
	Set ..Recorded = "rejected"
	Set recorded = ##class(OcuTalon.Data.StatusMark).RecordTelegram("rejected", "")
	If $SYSTEM.Status.IsError(recorded) $$$LOGWARNING(..#LOGRECORD_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(recorded)))
	$$$LOGWARNING(..#LOGREJECTED)
	Quit 1
}

/// A warning for a failed call, and the wait before the next one.
Method Failed(text As %String) [ Private ]
{
	$$$LOGWARNING(..#LOGFAILED_##class(OcuTalon.Channel.Telegram.Api).Safe(text))
	Set ..RetryAt = $ZHorolog + ..#RETRYSECONDS
}

/// A 409: the pause mark is set PAUSESECONDS ahead, and the warning carries Telegram's description of the conflict.
Method Pause(answer As %DynamicObject) [ Private ]
{
	Set until = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), ..#PAUSESECONDS)
	Set recorded = ##class(OcuTalon.Data.StatusMark).Record(..#PAUSEMARK, until)
	If $SYSTEM.Status.IsError(recorded) {
		$$$LOGWARNING(..#LOGRECORD_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(recorded)))
		Set ..RetryAt = $ZHorolog + ..#PAUSESECONDS
		Quit
	}
	$$$LOGWARNING(..#LOGPAUSE_until_" (UTC). "_##class(OcuTalon.Channel.Telegram.Api).Failure("getUpdates", 409, answer))
}

/// Handles the updates of an answer in order: one below the kept offset is skipped, the others are handled, and each handled update
/// moves the kept offset past its id.
Method Handle(updates As %DynamicArray) [ Private ]
{
	Set iterator = updates.%GetIterator()
	While iterator.%GetNext(, .update) {
		If '$IsObject(update) || (update.%GetTypeOf("update_id") '= "number") Continue
		Set id = update."update_id"
		If id '? 1.N Continue
		Set offset = ..Kept()
		If (offset '= "") && (id < offset) Continue
		Try {
			Do ..HandleUpdate(update)
		} Catch exception {
			$$$LOGWARNING(..#LOGUPDATE_##class(OcuTalon.Channel.Telegram.Api).Safe(exception.Name))
		}
		Do ..Keep(id + 1)
	}
}

/// Only a message or a button press of a private chat is handled; handling it records the chat, with no name.
Method HandleUpdate(update As %DynamicObject) [ Private ]
{
	Set chat = ""
	If update.%GetTypeOf("message") = "object" {
		Set chat = update.message.chat
	} ElseIf update.%GetTypeOf("callback_query") = "object" {
		If update."callback_query".%GetTypeOf("message") = "object" Set chat = update."callback_query".message.chat
	}
	If '$IsObject(chat) || (chat.%GetTypeOf("type") '= "string") || (chat.type '= "private") Quit
	Do ##class(OcuTalon.Data.Pairing).RecordChat(chat.id, "", .sc)
	If $SYSTEM.Status.IsError(sc) $$$LOGWARNING(..#LOGCHAT_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
}

/// The offset that the item keeps: the last handled update_id plus 1, or "" when there is none.
ClassMethod Kept() As %String [ Private ]
{
	Quit $Get($$$EnsStaticAppData("TelegramIn", "offset"))
}

/// Keeps the offset.
Method Keep(offset As %Integer) [ Private ]
{
	Set $$$EnsStaticAppData("TelegramIn", "offset") = offset
}

/// 1 when this release includes Telegram: only when the test-only global ^OcuTalonTest("TelegramIncluded") is 1,
/// which OcuTalon.Test classes set and the judges' install never does. Otherwise 0.
ClassMethod Included() As %Boolean
{
	Quit $Get(^OcuTalonTest("TelegramIncluded")) = 1
}

}
