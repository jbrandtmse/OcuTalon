Include Ensemble

/// TelegramIn, the inbound service of the Telegram channel (Stories 12.2 to 12.5, 12.7 and 17.6; AD-14, AD-18, AD-19, AD-5). An Ens.InboundAdapter service whose
/// CallInterval is 1 second in the production: each run makes at most one Bot API call, so a 5-second long poll follows the one before it.
/// Included() is the switch that the Telegram installer step reads (AD-23): this release includes Telegram, and only a test can turn
/// that off. The step also writes the ApiBase row from OCUTALON_TELEGRAM_API_BASE at every start, and the SSL step makes the client SSL configuration that SSLConfig names.
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
///   - The command of a private message is its text up to the first white space (a button press has none).
///     Each reply is one pairing Notification by the chat row's Ref, with a catalog key and the slots of that key (none for the pairing keys), sent to Notify; this class never
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
///         user's turn (Story 12.6, below); a paired chat's document or photo is a file turn (the file bullet below); a paired chat's other
///         message with no text (a sticker, a blank message) gets no turn and no reply.
///     A reply to a chat that is not paired has no SessionRef: such a chat reaches no session and no model.
///   - A button press of a private chat (Story 12.7; AD-11, AD-32) is recorded like a message, and its data is split at the first ":" into
///     the action and the request's Ref. AnswersIn.FromTelegram(Ref, action, the chat row's Ref) is called synchronously with the chat's
///     Ref, never its id, and the press is then answered once with answerCallbackQuery {callback_query_id, text, show_alert}, the text
///     being Catalog.Render for the channel telegram (the one render outside an *Out operation, AD-32) of the code it gave:
///       - approved: press.approved, or no text when the answer has no count slot (a request with no dry run); rejected: press.rejected;
///       - already_answered: answered.alreadyApproved, or answered.alreadyRejected when the winner rejected, and expired: answered.expired,
///         both with show_alert, as are not_paired and not_visible (press.notPairedChat) and unknown (press.unavailable);
///       - not_allowed, an error status of FromTelegram and a render error answer with no text and show_alert false, with one warning.
///     A press makes no Turn, calls no model and sends no chat message, and a failed answerCallbackQuery is one warning.
///   - The Got it press (Story 17.6): the action gotit and the Ref of a tell-now notice (the Ref of its Decision). Msg.Command.GotIt {Ref, Channel
///     telegram, SessionRef} is submitted through Commands.Submit with origin telegram only when all of these hold: the chat row is paired (it has a
///     session), the Ref is a reference, the paired session has a telegram Delivery row for that Ref (Ownership.DeliveryByRef), and the chat of that row's
///     message id is the pressing chat. Any other press submits nothing. Every Got it press is answered with answerCallbackQuery and no text, so the
///     press adds no text of its own; a failed Submit is one warning.
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
///   - A paired chat's file (Story 26.2; FR-54, AD-14, AD-21): a message with a document object or a photo array is handled by File, in this order, and each step that refuses
///     answers one pairing Notification (files.* keys) and goes no further. (1) On the online demo (public setting onlineDemo 1) nothing is fetched and the chat is answered
///     files.offOnDemo. (2) The size that the update reports (the document's, or the largest photo size's) over Core.Files FILEMAX is refused with files.tooLarge before any call.
///     (3) While Core.Files.Readable() is 0 (Agent.Input READSFILES), nothing is fetched or stored and the chat is answered files.noReader, which is Core.Files' reply to a file turn
///     with no reader, so that the web chat and Telegram do not differ. A part with no file_id is files.unreadable with the reason of Docs.Extract.Reason("failed"). (4) Turn checks the
///     session row and the allowance as for a text turn (the caption is the text), so that a message the allowance refuses costs no download (DW-1340). (5) getFile for the file_id (the
///     last, largest photo size), then Api.Download of the file_path it answers, which stops at FILEMAX bytes and at DOWNLOADSECONDS; a failure of either is one warning (no URL, path or
///     token) and files.unreadable with the reason of Docs.Extract.Reason("failed"); a download over the limit is files.tooLarge. (6) Core.Files.Store with channel telegram, the
///     document's file_name (a photo has none), which refuses too_large, empty or wrong_type as files.tooLarge or files.unreadable with Core.Files' reasons. A refusal in steps 5 and 6
///     gives the allowance entry back. (7) Turn sends the same untrusted Item as the web route: the caption is its Text, and Core.Files.SetItem sets the four file fields. A stored file
///     whose Item is not sent (a failed send) is discarded. The download address holds the token, so it is built only by Api.Download and is never logged.
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

Parameter LOGFETCH = "TelegramIn could not fetch a paired chat's file: ";

Parameter LOGSTORE = "TelegramIn could not store a paired chat's file: ";

Parameter LOGPRESS = "TelegramIn could not hand a button press to the answer rule, so it answered the press with no text: ";

Parameter LOGPRESSANSWER = "TelegramIn could not answer a button press: ";

Parameter LOGPRESSTEXT = "TelegramIn could not render the answer to a button press, so it answered with no text: ";

Parameter LOGGOTIT = "TelegramIn could not submit a Got it press: ";

Parameter LOGNOTALLOWED = "TelegramIn's chat may not answer this kind of request, so the button press was answered with no text.";

/// The item that takes every turn's Item.
Parameter TARGET = "Conversation";

/// The item that takes the allowance notice and the pairing replies.
Parameter NOTIFY = "Notify";

/// The channel of the Items this service sends: one of Msg.Enum CHANNEL.
Parameter CHANNEL = "telegram";

/// The action in the callback data of the Got it button of a tell-now message.
Parameter GOTITACTION = "gotit";

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
/// give it; the command of a message then goes on to its branch, and a button press is answered (Press).
Method HandleUpdate(update As %DynamicObject) [ Private ]
{
	Set chat = ""
	Set message = ""
	Set query = ""
	If update.%GetTypeOf("message") = "object" {
		Set message = update.message
		Set chat = message.chat
	} ElseIf update.%GetTypeOf("callback_query") = "object" {
		Set query = update."callback_query"
		If query.%GetTypeOf("message") = "object" Set chat = query.message.chat
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
	If $IsObject(query) {
		Do ..Press(ref, query)
	} ElseIf command = "pair" {
		Do ..Pair(ref, chat.id, payload)
	} ElseIf command = "start" {
		Do ..Reply(ref, "pairing.start", "")
	} ElseIf command = "stop" {
		Do ..Stop(ref, chat.id, sessionRef)
	} ElseIf command = "other" {
		Do ..Other(ref, sessionRef, text, message)
	}
}

/// The answer to a button press of a private chat (the Boundaries of Story 12.7): the press's data is split at the first ":" into the
/// action and the request's Ref, FromTelegram answers the request for the chat row's Ref, and the press is answered once. A hand-over
/// that fails, a code with no text to show and a text that cannot be rendered answer with no text and show_alert false.
Method Press(chatRef As %String, query As %DynamicObject) [ Private ]
{
	Set data = $Select(query.%GetTypeOf("data") = "string": query.data, 1: "")
	Set action = $Piece(data, ":", 1)
	Set approvalRef = $Piece(data, ":", 2, *)
	If action = ..#GOTITACTION {
		Do ..GotIt(chatRef, approvalRef)
		Do ..AnswerPress(query, "", 0)
		Quit
	}
	Set code = "unknown", slots = {}
	Set sc = $$$OK
	Try {
		Set sc = ##class(OcuTalon.Core.AnswersIn).FromTelegram(approvalRef, action, chatRef, .code, .slots)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Set text = "", alert = 0
	If $SYSTEM.Status.IsError(sc) {
		$$$LOGWARNING(..#LOGPRESS_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
	} Else {
		If code = "approved" Do ..FixSlots(chatRef, approvalRef, slots)
		Set text = ..PressText(code, slots, .alert)
	}
	Do ..AnswerPress(query, text, alert)
}

/// Submits the Got it command of a press when the press is allowed (see the class comment): the chat is paired, the Ref is a reference, and the
/// paired session's telegram Delivery row for the Ref belongs to the pressing chat. Any other press submits nothing.
Method GotIt(chatRef As %String, decisionRef As %String) [ Private ]
{
	Set chat = ##class(OcuTalon.Data.Pairing).Chat(chatRef)
	If '$IsObject(chat) || (chat.SessionRef = "") || '##class(OcuTalon.Bridge.Approval).IsRef(decisionRef) || '##class(OcuTalon.Bridge.Approval).IsRef(chat.SessionRef) Quit
	Set row = ##class(OcuTalon.Data.Ownership).DeliveryByRef(decisionRef, ..#CHANNEL, chat.SessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) || '$IsObject(row) || ($Piece(row.ChannelMessageId, ":", 1) '= chatRef) Quit
	Set command = ##class(OcuTalon.Msg.Command.GotIt).%New()
	Set command.Ref = decisionRef
	Set command.Channel = ..#CHANNEL
	Set command.SessionRef = chat.SessionRef
	Do ..Outcome(command, ..#LOGGOTIT)
}

/// Answers a button press once with answerCallbackQuery: the text when there is one, and show_alert. A failed answer is one warning.
Method AnswerPress(query As %DynamicObject, text As %String, alert As %Boolean) [ Private ]
{
	Set id = $Select((query.%GetTypeOf("id") = "string") || (query.%GetTypeOf("id") = "number"): query.id, 1: "")
	If id = "" {
		$$$LOGWARNING(..#LOGPRESSANSWER_"the press has no id.")
		Quit
	}
	Set params = {}
	Do params.%Set("callback_query_id", id, "string")
	If text '= "" Do params.%Set("text", text, "string")
	Do params.%Set("show_alert", alert, "boolean")
	Set answer = ..Call("answerCallbackQuery", params, .httpStatus, .sc)
	If $SYSTEM.Status.IsError(sc) {
		$$$LOGWARNING(..#LOGPRESSANSWER_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
	} ElseIf '((httpStatus = 200) && +answer.ok) {
		$$$LOGWARNING(..#LOGPRESSANSWER_##class(OcuTalon.Channel.Telegram.Api).Failure("answerCallbackQuery", httpStatus, answer))
	}
}

/// Adds to the slots of an approved press the fix kind of its request (fixKind) and, from its dry run, the item a suspend or resume changes (item) and the item a reroute sends
/// the messages to (to), for the pressing chat's paired session (Story 23.2). A request that can't be read adds nothing, and PressText then shows no text for a kind it can't name.
Method FixSlots(chatRef As %String, approvalRef As %String, slots As %DynamicObject) [ Private ]
{
	Try {
		Set chat = ##class(OcuTalon.Data.Pairing).Chat(chatRef)
		If '$IsObject(chat) || (chat.SessionRef = "") Quit
		Set row = ##class(OcuTalon.Data.Ownership).Approval(approvalRef, chat.SessionRef, .sc)
		If '$IsObject(row) || (row.FixKind = "") Quit
		Do slots.%Set("fixKind", row.FixKind, "string")
		Set dry = ##class(OcuTalon.Live.Payload.Approval).FromRow(row).DryRun
		If $IsObject(dry) {
			If dry.Item '= "" Do slots.%Set("item", dry.Item, "string")
			If dry.To '= "" Do slots.%Set("to", dry.To, "string")
		}
	} Catch {
	}
}

/// The text of the answer to a press, from the code and slots that FromTelegram gave; alert is 1 for a refusal, which stays until it is
/// dismissed. "" (with alert 0) when the code shows no text: approved with no count, not_allowed (one warning) and a render error (one warning).
Method PressText(code As %String, slots As %DynamicObject, Output alert As %Boolean) As %String [ Private ]
{
	Set alert = 0
	Set key = ""
	Set use = {}
	If code = "approved" {
		Set kind = slots.%Get("fixKind")
		If (kind = "suspend_item") || (kind = "resume_item") {
			If slots.%Get("item") = "" Quit ""
			Set key = $Select(kind = "suspend_item": "press.approvedSuspend", 1: "press.approvedResume"), use = {"item": (slots.item)}
		} ElseIf kind = "reroute" {
			If (slots.%GetTypeOf("count") '= "number") || (slots.%Get("to") = "") Quit ""
			Set key = "press.approvedReroute", use = {"count": (slots.count), "itemNoun": (slots.itemNoun), "to": (slots.to)}
		} ElseIf kind = "partner_warning" {
			Set key = "press.approvedPartner"
		} Else {
			If slots.%GetTypeOf("count") '= "number" Quit ""
			Set key = "press.approved", use = slots
		}
	} ElseIf code = "rejected" {
		Set key = "press.rejected"
	} ElseIf code = "already_answered" {
		Set key = $Select(slots.action = "reject": "answered.alreadyRejected", 1: "answered.alreadyApproved")
		Set use = {"channel": (slots.channel), "time": (slots.time)}
		Set alert = 1
	} ElseIf code = "expired" {
		Set key = "answered.expired"
		Set use = {"time": (slots.time)}
		Set alert = 1
	} ElseIf (code = "not_paired") || (code = "not_visible") {
		Set key = "press.notPairedChat"
		Set alert = 1
	} ElseIf code = "not_allowed" {
		$$$LOGWARNING(..#LOGNOTALLOWED)
		Quit ""
	} Else {
		Set key = "press.unavailable"
		Set alert = 1
	}
	Set text = ""
	Set sc = $$$OK
	Try {
		Set text = ##class(OcuTalon.Msg.Catalog).Render(key, use.%ToJSON(), "telegram", .sc)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) || (text = "") {
		$$$LOGWARNING(..#LOGPRESSTEXT_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
		Set alert = 0
		Quit ""
	}
	Quit text
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
/// answered pairing.notPaired. A paired chat's document or photo is a file turn (File); its text, when it is not empty once trimmed, is the user's turn; with neither it gets nothing.
Method Other(ref As %String, sessionRef As %String, text As %String, message As %DynamicObject = "") [ Private ]
{
	If sessionRef '= "" {
		If ..HasFile(message) {
			Do ..File(ref, sessionRef, message)
		} ElseIf $ZStrip(text, "<>WC") '= "" {
			Do ..Turn(sessionRef, text)
		}
		Quit
	}
	If ##class(OcuTalon.Data.Pairing).TakeReplySlot(ref) Do ..Reply(ref, "pairing.notPaired", "")
}

/// 1 when the message carries a document object or a photo array with a size in it.
Method HasFile(message As %DynamicObject) As %Boolean [ Private ]
{
	If '$IsObject(message) Quit 0
	If message.%GetTypeOf("document") = "object" Quit 1
	Quit (message.%GetTypeOf("photo") = "array") && (message.photo.%Size() > 0)
}

/// A paired chat's document or photo (see the class comment): the steps in order, and the refusals as pairing Notifications.
Method File(ref As %String, sessionRef As %String, message As %DynamicObject) [ Private ]
{
	If ..OnlineDemo() {
		Do ..Reply(ref, "files.offOnDemo", sessionRef)
		Quit
	}
	Set document = (message.%GetTypeOf("document") = "object")
	Set part = $Select(document: message.document, 1: message.photo.%Get(message.photo.%Size() - 1))
	If '$IsObject(part) Set part = {}
	If (part.%GetTypeOf("file_size") = "number") && (part."file_size" > ##class(OcuTalon.Core.Files).#FILEMAX) {
		Do ..Refuse(ref, sessionRef, ##class(OcuTalon.Core.Files).#TOOLARGE, part."file_size")
		Quit
	}
	Set name = $Select(document && (part.%GetTypeOf("file_name") = "string"): part."file_name", 1: "")
	If '..Readable() {
		Do ..Reply(ref, "files.noReader", sessionRef, {"name": (..NoReaderName(name, document))})
		Quit
	}
	If part.%GetTypeOf("file_id") '= "string" {
		Do ..Refuse(ref, sessionRef, "failed")
		Quit
	}
	Set caption = $Select(message.%GetTypeOf("caption") = "string": message.caption, 1: "")
	Do ..Turn(sessionRef, caption, {"ref": (ref), "fileId": (part."file_id"), "name": (name)})
}

/// The file of a paired chat's upload ({ref, fileId, name}, see Turn) fetched (Fetch) and stored (Core.Files.Store, channel telegram, the upload's name), as the {ref, name, mediaType,
/// size} that Store answers; or "" with the code of the refusal and its size: too_large with the size (a download cut off at the limit), wrong_type or empty with the stream's size, and
/// failed after one warning (a fetch or a store that failed).
Method Stored(sessionRef As %String, upload As %DynamicObject, Output code As %String, Output size As %Integer) As %DynamicObject [ Private ]
{
	Set code = "failed"
	Set stored = ""
	Set stream = ..Fetch(upload.fileId, .size)
	If '$IsObject(stream) {
		If size > 0 Set code = ##class(OcuTalon.Core.Files).#TOOLARGE
		Quit ""
	}
	Set size = 0
	Set refusal = ##class(OcuTalon.Core.Files).Store(sessionRef, ..#CHANNEL, upload.name, stream, .stored, .sc)
	If $SYSTEM.Status.IsError(sc) {
		$$$LOGWARNING(..#LOGSTORE_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
		Quit ""
	}
	If refusal '= "" {
		Set code = refusal
		Set size = stream.Size
		Quit ""
	}
	If '$IsObject(stored) Quit ""
	Set code = ""
	Quit stored
}

/// The name that the no-reader reply gives the file: the document's own safe name, else photo.jpg for a photo (the name Store gives it) and file for a document with none (Store would name
/// it by the type its bytes show, which is not known before the download; the web route always has a name).
ClassMethod NoReaderName(name As %String, document As %Boolean) As %String [ Private ]
{
	Set safe = ##class(OcuTalon.Core.Files).SafeName(name)
	Quit $Select(safe '= "": safe, document: "file", 1: "photo.jpg")
}

/// The bytes of the file with the file_id, through getFile and Api.Download, as a stream, or "" after one warning (size is then the limit plus 1 when the download was cut off at the
/// limit, else 0). No warning holds the download address, the file path or the token.
Method Fetch(fileId As %String, Output size As %Integer) As %Stream.Object [ Private ]
{
	Set size = 0
	Set stream = ""
	If fileId = "" {
		$$$LOGWARNING(..#LOGFETCH_"the update names no file.")
		Quit ""
	}
	Set answer = ..Call("getFile", {"file_id": (fileId)}, .httpStatus, .sc)
	If $SYSTEM.Status.IsError(sc) {
		$$$LOGWARNING(..#LOGFETCH_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
		Quit ""
	}
	If '((httpStatus = 200) && +answer.ok && $IsObject(answer.result) && (answer.result.%GetTypeOf("file_path") = "string")) {
		$$$LOGWARNING(..#LOGFETCH_##class(OcuTalon.Channel.Telegram.Api).Failure("getFile", httpStatus, answer))
		Quit ""
	}
	Set stream = ##class(OcuTalon.Channel.Telegram.Api).Download(..ApiBase, ..SSLConfig, answer.result."file_path", ..#POLLSECONDS + ..#READMARGIN, .httpStatus, .sc, .tooLarge)
	If tooLarge Set size = ##class(OcuTalon.Channel.Telegram.Api).#DOWNLOADMAX + 1
	If $SYSTEM.Status.IsError(sc) || '$IsObject(stream) {
		If 'tooLarge $$$LOGWARNING(..#LOGFETCH_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
		Quit ""
	}
	Quit stream
}

/// The refusal of a file as the pairing Notification of its key: too_large is files.tooLarge with the size as Core.Files writes it; wrong_type and empty are files.unreadable with Core.Files'
/// reasons; any other code (failed) is files.unreadable with the reason of Docs.Extract for failed.
Method Refuse(ref As %String, sessionRef As %String, code As %String, size As %Integer = 0) [ Private ]
{
	If code = ##class(OcuTalon.Core.Files).#TOOLARGE {
		Do ..Reply(ref, "files.tooLarge", sessionRef, {"size": (##class(OcuTalon.Core.Files).SizeText(size))})
		Quit
	}
	Set reason = $Case(code, ##class(OcuTalon.Core.Files).#WRONGTYPE: ##class(OcuTalon.Core.Files).#REASONWRONGTYPE, ##class(OcuTalon.Core.Files).#EMPTY: ##class(OcuTalon.Core.Files).#REASONEMPTY, : ##class(OcuTalon.Docs.Extract).Reason("failed"))
	Do ..Reply(ref, "files.unreadable", sessionRef, {"reason": (reason)})
}

/// 1 when the online-demo flag is set: a file is then never fetched. Private; a test subclass overrides it.
Method OnlineDemo() As %Boolean [ Private ]
{
	Quit (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
}

/// 1 when Core.Files says that a sent file can be read (Agent.Input READSFILES). Private; a test subclass overrides it.
Method Readable() As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Core.Files).Readable()
}

/// A paired chat's text as the session's turn, in the steps of WebChatIn.Accept (see the class comment). The service's %SessionId and
/// %SuperSession are "" again, and the job's session id, which the event log reads, is cleared, when the method ends,
/// also after an exception, which it then raises to the caller. With upload (a paired chat's file: {ref, the chat row's Ref; fileId; name}, from File) the text is the caption, and only
/// after the allowance took the message is the file fetched and stored (Stored), so that a message the allowance refuses, or one with no session row, costs no download (DW-1340). A
/// file that Stored refuses is answered to the chat (Refuse), gives the allowance entry back (Refund) and sends no Item; a stored one makes the Item untrusted with the four file fields
/// (Core.Files.SetItem), and the stored file is discarded on every path that sends no Item.
Method Turn(sessionRef As %String, text As %String, upload As %DynamicObject = "") [ Private ]
{
	Set thrown = ""
	Set sent = 0
	Set file = ""
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
			If $IsObject(upload) {
				Set file = ..Stored(sessionRef, upload, .code, .size)
				If '$IsObject(file) {
					Do ..Refuse(upload.ref, sessionRef, code, size)
					Do ..Refund(sessionRef)
					Quit
				}
			}
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
				Set item.Provenance = $Select($IsObject(file): "untrusted", 1: "user")
				Set item.Text = text
				Set item.FromGuide = 0
				If $IsObject(file) Do ##class(OcuTalon.Core.Files).SetItem(item, file)
				Set sc = ..SendTurn(item)
			} Catch exception {
				Set sc = exception.AsStatus()
			}
			Set sent = $SYSTEM.Status.IsOK(sc)
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
	If $IsObject(file) && 'sent Do ##class(OcuTalon.Core.Files).Discard(file.ref, sessionRef)
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

/// The one reply: a pairing Notification with the catalog key and its slots (a dynamic object; none for a pairing key), for the chat row's Ref and the session (or ""), sent to
/// Notify, which routes it to TelegramOut by ChatRef.
Method Reply(ref As %String, key As %String, sessionRef As %String, slots As %DynamicObject = "") [ Private ]
{
	Set notification = ##class(OcuTalon.Msg.Notification).%New()
	Set notification.SessionRef = sessionRef
	Set notification.ChatRef = ref
	Set notification.Kind = "pairing"
	Set notification.CatalogKey = key
	Set notification.Slots = $Select($IsObject(slots): slots.%ToJSON(), 1: "{}")
	Set sc = ..Notify(notification)
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

/// 1: this release includes Telegram. The test-only global ^OcuTalonTest("TelegramIncluded") can turn it off, and only when it is 0;
/// OcuTalon.Test classes set it and the judges' install never does. Any other value, or none, leaves it 1.
ClassMethod Included() As %Boolean
{
	Quit $Get(^OcuTalonTest("TelegramIncluded")) '= 0
}

}
