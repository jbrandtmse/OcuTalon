Include Ensemble

/// TelegramIn, the inbound service of the Telegram channel (Stories 12.2 to 12.5; AD-14, AD-18, AD-19, AD-5). An Ens.InboundAdapter service whose
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
///     Pairing.RecordChat. Everything else is confirmed and ignored.
///   - The chat's name is the update's chat.first_name (the from object is never read) and is kept only while the chat is paired
///     (DW-486, AD-4): a later update of a paired chat keeps the stored name when it has none of its own, and a chat that is not paired
///     is recorded with no name, so its next update clears a name that an unpair left on its row (SessionOps.Unlink keeps it, DW-520).
///   - The command of a private message is its text up to the first white space (a button press has none and is not answered, Story 12.7).
///     Each reply is one pairing Notification by the chat row's Ref, with a catalog key and no slots, sent to Notify; this class never
///     calls sendMessage (AD-1). The chat is recorded first, with the name rule above, and the command then runs with the row's Ref:
///       - pair: the text is "/start " and a code (Story 12.4). The code is hashed with Pairing.HashCode and Msg.Command.Pair
///         {CodeHash, ChatRef} is submitted through Commands.Submit with origin telegram. The outcome paired is answered pairing.paired,
///         for the session; every other outcome, and a refused or failed Submit, is answered pairing.badCode and a chat that is not paired
///         is recorded again with no name. The code is never put in a message, a log text or any other store.
///       - start: a bare /start (also with white space only) and /help, from any chat, are answered pairing.start.
///       - stop: /stop submits Msg.Command.Unpair {ChatRef} with origin telegram. On unpaired the chat is recorded again with no name
///         (SessionOps.Unlink keeps one, DW-520) and answered pairing.stopped, for the session it left; on not_paired it is any other
///         message; after a failed or refused Submit there is one warning and no reply.
///       - any other message (a sticker too, and every other command): a chat that is not paired takes Pairing.TakeReplySlot and, when it
///         gets the slot (once a minute), is answered pairing.notPaired. A paired chat's text, when it is not empty once trimmed, is the
///         user's turn (Story 12.6, below); a paired chat's message with no text gets no turn and no reply.
///     A reply to a chat that is not paired has no SessionRef: such a chat reaches no session and no model.
///   - A turn takes the steps of WebChatIn.Accept (AD-20, AD-26, AD-30) for the session that the chat was paired with when its row was
///     read: the session's row must exist (else one warning and nothing sent); Allowance.TryConsume is asked with the channel telegram.
///     A refusal queues nothing and calls no model: with a retryAt, and on the first refusal of the window only, Notify gets the
///     allowance Notice (kind allowance, for the session, in a trace session of its own under the session's TraceRef); with no retryAt
///     (the row was busy) there is one warning. Trace.Join then gives the session's thread of the day, which is the service's %SessionId,
///     with the session's TraceRef as its %SuperSession (a failed Join is one warning and the turn is traced on its own). One Msg.Item
///     goes to Conversation with a new ItemId, the session's SessionRef, channel telegram, provenance user, the text as sent, no ClientId
///     and FromGuide 0: no chat id and no name is in it. When the day had no thread, Trace.Started records the thread that the send gave,
///     or none when the send failed. A send that fails gives the allowance entry back (Allowance.Refund) and is one warning. Afterwards
///     %SessionId and %SuperSession are "" again and the job's session id is cleared, so that the next update of the same poll answer,
///     its messages and its event-log rows, is traced on its own. The reply is Conversation's: it goes to Notify, and this class sends none.
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

Parameter LOGLOOKUP = "TelegramIn could not look up a chat's row, so it kept no name.";

Parameter LOGPAIR = "TelegramIn could not submit a pairing: ";

Parameter LOGREPLY = "TelegramIn could not send the pairing reply to Notify: ";

Parameter LOGSTOP = "TelegramIn could not submit an unpair, so the chat got no reply: ";

Parameter LOGSTOPOUTCOME = "TelegramIn's unpair did not succeed, so the chat got no reply; the outcome was: ";

Parameter LOGNOSESSION = "TelegramIn dropped a paired chat's message: the chat's session has no session row.";

Parameter LOGBUSYALLOWANCE = "TelegramIn dropped a paired chat's message: the session's allowance could not be asked.";

Parameter LOGNOTICE = "TelegramIn could not send the allowance notice to Notify: ";

Parameter LOGJOIN = "TelegramIn could not join the session's trace thread, so this turn is traced on its own: ";

Parameter LOGSTARTED = "TelegramIn could not record the session's trace thread, so the next turn starts another: ";

Parameter LOGSEND = "TelegramIn could not send a paired chat's message to Conversation, and gave its allowance entry back: ";

/// The item that takes every turn's Item.
Parameter TARGET = "Conversation";

/// The item that takes the allowance notice and the pairing replies.
Parameter NOTIFY = "Notify";

/// The channel of the Items this service sends: one of Msg.Enum CHANNEL.
Parameter CHANNEL = "telegram";

/// The text that starts a pairing message: the command and one space, then the code.
Parameter STARTPREFIX = "/start ";

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

/// Only a message or a button press of a private chat is handled. The chat is recorded with the name that the Boundaries of Story 12.4
/// give it; the command of a message then goes on to its branch (a button press has none).
Method HandleUpdate(update As %DynamicObject) [ Private ]
{
	Set chat = ""
	Set message = ""
	If update.%GetTypeOf("message") = "object" {
		Set message = update.message
		Set chat = message.chat
	} ElseIf update.%GetTypeOf("callback_query") = "object" {
		If update."callback_query".%GetTypeOf("message") = "object" Set chat = update."callback_query".message.chat
	}
	If '$IsObject(chat) || (chat.%GetTypeOf("type") '= "string") || (chat.type '= "private") Quit
	Set command = ..Command(message, .payload)
	Set text = $Select($IsObject(message) && (message.%GetTypeOf("text") = "string"): message.text, 1: "")
	Set updateName = $Select(chat.%GetTypeOf("first_name") = "string": chat."first_name", 1: "")
	Do ..Row(chat.id, .sessionRef, .storedName)
	If (payload = "") && (sessionRef = "") {
		Set name = ""
	} ElseIf updateName '= "" {
		Set name = updateName
	} ElseIf sessionRef '= "" {
		Set name = storedName
	} Else {
		Set name = ""
	}
	Set ref = ##class(OcuTalon.Data.Pairing).RecordChat(chat.id, name, .sc)
	If $SYSTEM.Status.IsError(sc) {
		$$$LOGWARNING(..#LOGCHAT_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
		Quit
	}
	If command = "pair" {
		Do ..Pair(ref, chat.id, payload)
	} ElseIf command = "start" {
		Do ..Reply(ref, "pairing.start", "")
	} ElseIf command = "stop" {
		Do ..Stop(ref, chat.id, sessionRef)
	} ElseIf command = "other" {
		Do ..Other(ref, sessionRef, text)
	}
}

/// The command of a private message, by its text up to the first white space: "pair" for "/start " and a code (payload is the code, once
/// trimmed of white space), "start" for a bare /start (also with white space only) and for /help, "stop" for /stop, and "other" for
/// every other message, one with no text and every other command. "" for no message (a button press). payload is "" unless "pair".
Method Command(message As %DynamicObject, Output payload As %String) As %String [ Private ]
{
	Set payload = ""
	If '$IsObject(message) Quit ""
	If message.%GetTypeOf("text") '= "string" Quit "other"
	Set text = message.text
	Set word = $Piece($Translate(text, $Char(9, 10, 13), "   "), " ", 1)
	If word = "/start" {
		Set rest = $ZStrip($Extract(text, $Length(word) + 1, *), "<>W")
		If rest = "" Quit "start"
		If $Extract(text, 1, $Length(..#STARTPREFIX)) '= ..#STARTPREFIX Quit "other"
		Set payload = rest
		Quit "pair"
	}
	If word = "/help" Quit "start"
	If word = "/stop" Quit "stop"
	Quit "other"
}

/// The chat's row before it is recorded, read-only, with the lookup that RecordChat makes: its SessionRef and DisplayName, both "" for a
/// chat with no row.
Method Row(chatId As %String, Output sessionRef As %String, Output displayName As %String) [ Private ]
{
	Set sessionRef = "", displayName = ""
	Set found = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 SessionRef, DisplayName FROM OcuTalon_Data.Pairing WHERE ChatId = ? ORDER BY ID", chatId)
	If found.%SQLCODE < 0 {
		$$$LOGWARNING(..#LOGLOOKUP)
		Quit
	}
	If found.%Next() {
		Set sessionRef = found.%Get("SessionRef")
		Set displayName = found.%Get("DisplayName")
	}
}

/// Submits the Pair command for a code. The chat's id and name stay in its row, and the code only in this method's hash. The outcome
/// paired is answered pairing.paired for the session; after any other outcome, and after a refused or failed Submit, the chat is
/// answered pairing.badCode, and a chat that is not paired is recorded again with no name.
Method Pair(ref As %String, chatId As %String, payload As %String) [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.Pair).%New()
	Set command.CodeHash = ##class(OcuTalon.Data.Pairing).HashCode(payload)
	Set command.ChatRef = ref
	Set outcome = ..Outcome(command, ..#LOGPAIR)
	If outcome = "paired" {
		Set chat = ##class(OcuTalon.Data.Pairing).Chat(ref)
		Do ..Reply(ref, "pairing.paired", $Select($IsObject(chat): chat.SessionRef, 1: ""))
		Quit
	}
	Do ..Forget(ref, chatId)
	Do ..Reply(ref, "pairing.badCode", "")
}

/// Submits the Unpair command of a chat's /stop (origin telegram, by the row's Ref). unpaired is answered pairing.stopped for the session
/// that the chat left, and the chat is recorded again with no name; not_paired is any other message of a chat that is not paired (also when
/// the row was read as paired and an unpair came first); a refused or failed Submit is one warning and no reply.
Method Stop(ref As %String, chatId As %String, sessionRef As %String) [ Private ]
{
	Set command = ##class(OcuTalon.Msg.Command.Unpair).%New()
	Set command.ChatRef = ref
	Set outcome = ..Outcome(command, ..#LOGSTOP)
	If outcome = "unpaired" {
		Do ..Forget(ref, chatId)
		Do ..Reply(ref, "pairing.stopped", sessionRef)
	} ElseIf outcome = "not_paired" {
		Do ..Other(ref, "", "")
	} ElseIf outcome '= "" {
		$$$LOGWARNING(..#LOGSTOPOUTCOME_##class(OcuTalon.Channel.Telegram.Api).Safe(outcome))
	}
}

/// Submits a chat's command with origin telegram and returns its CommandResult's Outcome, or "" after a refused or failed Submit, which
/// is logged as one warning: the log parameter, then the status text or the exception's name.
Method Outcome(command As OcuTalon.Msg.Command, log As %String) As %String [ Private ]
{
	Set outcome = ""
	Try {
		Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "telegram", .result)
		If $SYSTEM.Status.IsError(sc) {
			$$$LOGWARNING(log_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
		} ElseIf $IsObject(result) {
			Set outcome = result.Outcome
		}
	} Catch exception {
		$$$LOGWARNING(log_##class(OcuTalon.Channel.Telegram.Api).Safe(exception.Name))
	}
	Quit outcome
}

/// Any other message: a chat that was not paired when its row was read takes its reply slot and, when it gets it (once a minute), is
/// answered pairing.notPaired. A paired chat's text, when it is not empty once trimmed, is the user's turn; with no text it gets nothing.
Method Other(ref As %String, sessionRef As %String, text As %String) [ Private ]
{
	If sessionRef '= "" {
		If $ZStrip(text, "<>WC") '= "" Do ..Turn(sessionRef, text)
		Quit
	}
	If ##class(OcuTalon.Data.Pairing).TakeReplySlot(ref) Do ..Reply(ref, "pairing.notPaired", "")
}

/// A paired chat's text as the session's turn, in the steps of WebChatIn.Accept (see the class comment). The service's %SessionId and
/// %SuperSession are "" again, and the job's session id, which the event log reads, is cleared, when the method ends,
/// also after an exception, which it then raises to the caller.
Method Turn(sessionRef As %String, text As %String) [ Private ]
{
	Set thrown = ""
	Try {
		Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(sessionRef)
		If '$IsObject(session) {
			$$$LOGWARNING(..#LOGNOSESSION)
		} ElseIf '..Allowed(sessionRef, ..#CHANNEL, text, .retryAt, .firstRefusal) {
			If retryAt = "" {
				$$$LOGWARNING(..#LOGBUSYALLOWANCE)
			} ElseIf firstRefusal {
				Do ..Notice(session, retryAt)
			}
		} Else {
			Set now = ##class(OcuTalon.Data.Time).NowUtc()
			Set thread = ##class(OcuTalon.Core.Trace).Join(sessionRef, .joinSc, now)
			If $SYSTEM.Status.IsError(joinSc) $$$LOGWARNING(..#LOGJOIN_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(joinSc)))
			Set ..%SessionId = thread
			Set ..%SuperSession = session.TraceRef
			Set sc = $$$OK
			Try {
				Set item = ##class(OcuTalon.Msg.Item).%New()
				Set item.ItemId = ##class(OcuTalon.Bridge.Ids).NewRef()
				Set item.SessionRef = sessionRef
				Set item.Channel = ..#CHANNEL
				Set item.Provenance = "user"
				Set item.Text = text
				Set item.FromGuide = 0
				Set sc = ..SendTurn(item)
			} Catch exception {
				Set sc = exception.AsStatus()
			}
			If $SYSTEM.Status.IsOK(joinSc) && (thread = "") {
				Set startedSc = ##class(OcuTalon.Core.Trace).Started(sessionRef, $Select($SYSTEM.Status.IsOK(sc): ..%SessionId, 1: ""), now)
				If $SYSTEM.Status.IsError(startedSc) $$$LOGWARNING(..#LOGSTARTED_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(startedSc)))
			}
			If $SYSTEM.Status.IsError(sc) {
				Do ..Refund(sessionRef)
				$$$LOGWARNING(..#LOGSEND_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
			}
		}
	} Catch exception {
		Set thrown = exception
	}
	Set ..%SessionId = ""
	Set ..%SuperSession = ""
	Kill $$$JobSessionId
	If $IsObject(thrown) Throw thrown
}

/// Sends Notify the session's allowance notice, in a trace session of its own under the session's TraceRef (AD-26). A failure is one
/// warning and goes no further.
Method Notice(session As OcuTalon.Data.Session, retryAt As %String) [ Private ]
{
	Set sc = $$$OK
	Try {
		Set ..%SessionId = ""
		Set ..%SuperSession = session.TraceRef
		Set sc = ..Notify(##class(OcuTalon.Core.Allowance).Notice(session.Ref, retryAt))
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) $$$LOGWARNING(..#LOGNOTICE_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
}

/// The one send of a turn's Item to Conversation, asynchronously. Private; a test subclass overrides it.
Method SendTurn(item As OcuTalon.Msg.Item) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#TARGET, item)
}

/// The one send to Notify, asynchronously. Private; a test subclass overrides it.
Method Notify(notification As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	Quit ..SendRequestAsync(..#NOTIFY, notification)
}

/// The one give-back of the allowance, for a message whose send failed. Private; a test subclass overrides it to record the call.
Method Refund(sessionRef As %String) [ Private ]
{
	Do ##class(OcuTalon.Core.Allowance).Refund(sessionRef)
}

/// The one call of the allowance. Private; a test subclass overrides it to refuse.
Method Allowed(sessionRef As %String, channel As %String, text As %String, Output retryAt As %String, Output firstRefusal As %Boolean) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Core.Allowance).TryConsume(sessionRef, channel, text, .retryAt, .firstRefusal)
}

/// A chat whose row holds no session is recorded again with no name (AD-4), which clears a name that an unpair left on it.
Method Forget(ref As %String, chatId As %String) [ Private ]
{
	Set chat = ##class(OcuTalon.Data.Pairing).Chat(ref)
	If $IsObject(chat) && (chat.SessionRef = "") {
		Set chat = ""
		Do ##class(OcuTalon.Data.Pairing).RecordChat(chatId, "", .sc)
		If $SYSTEM.Status.IsError(sc) $$$LOGWARNING(..#LOGCHAT_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
	}
}

/// The one reply: a pairing Notification with the catalog key and no slots, for the chat row's Ref and the session (or ""), sent to
/// Notify, which routes it to TelegramOut by ChatRef.
Method Reply(ref As %String, key As %String, sessionRef As %String) [ Private ]
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = sessionRef
	Set notification.ChatRef = ref
	Set notification.Kind = "pairing"
	Set notification.CatalogKey = key
	Set notification.Slots = "{}"
	Set sc = ..SendRequestAsync("Notify", notification)
	If $SYSTEM.Status.IsError(sc) $$$LOGWARNING(..#LOGREPLY_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
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
