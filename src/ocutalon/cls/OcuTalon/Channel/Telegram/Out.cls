/// TelegramOut, the outbound operation of the Telegram channel (Stories 12.2 and 12.6; AD-14, AD-19, AD-28, AD-32, UX-DR108, UX-DR136). It
/// sends the text of an OcuTalon.Msg.Outbound or an OcuTalon.Msg.Notification to a chat through OcuTalon.Channel.Telegram.Api:
///   - the chat is the Pairing chat row of the message's ChatRef when it has one (every pairing notice), else the session's live pairing
///     (Ownership.Pairing of the SessionRef). An owner that is not a session is dropped with one warning. No chat sends nothing: one
///     warning that names neither a Ref nor an id, and the status is OK;
///   - an Outbound's text is its Text, else the catalog rendering of its CatalogKey for the channel telegram. When it has a CheckKey
///     whose sentence is not "", the text is followed by a blank line and the sentence (below). A Notification of the kinds tellnow,
///     incident, approval, result, reminder, allowance and pairing is sent as the rendering of its CatalogKey; any other kind (answered,
///     status, digest, fallback) sends nothing and records no row. A render error is returned and nothing is sent;
///   - the check sentence mirrors web/src/app/shared/check-sentence.ts (AD-28): checks.allPassed, checks.everythingElsePassed and
///     checks.nothingWatched give the catalog text, and checks.notEverything and checks.notEverythingRestPassed are rendered with
///     whatFailed, built from the CheckRows (result, entry, finding, checkedAt): every row that did not pass and has an entry, the failed
///     rows first, each group in row order, as "{entry} ({finding}, at {time})" with the finding's first letter in lower case and an
///     empty part left out, joined with "; ". The time is Data.Time.ForMessage of checkedAt, with " ET" on the online demo, and "at"
///     becomes "on" before a dated time, as the catalog renderer does. When no row is left, or the key is any other, or the sentence
///     cannot be rendered, the sentence is "" (one warning for the last two) and the reply goes alone. Only the key can say that
///     everything passed;
///   - the text goes as plain text, exactly as written, with no parse mode and no entities, as sendMessage parts of at most 4,096
///     UTF-16 units (Api.Split), in order. A 429 waits retry_after seconds (at least 1) and sends the same part again, at most TRIES
///     tries for one part, and a part that was sent is never sent twice. Any other failure is an error status with a safe text, and the
///     parts already sent stay sent;
///   - a message with a SessionRef, once every part is sent, records one Delivery row of channel telegram (Delivery.Record) whose
///     message id is "<ChatRef>:<message_id of the last part>" (the id is "" when the answer had none). A message with no SessionRef
///     records none. A failed Record is one warning and the status stays OK, because the message is never sent again.
/// Buttons and the edit in place of an answered request come with Story 12.7. The token is never held here (AD-19), and no log text holds
/// a chat id, a name or a message text.
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

Parameter LOGRECORD = "TelegramOut sent a message but could not record its delivery: ";

Parameter LOGCHECK = "TelegramOut sent a reply without its check sentence: ";

/// The notification kinds that the chat gets (the kinds that the simulated phone shows, and allowance and pairing).
Parameter KINDS = "tellnow,incident,approval,result,reminder,allowance,pairing";

/// The check keys whose catalog text is the whole sentence.
Parameter PLAINKEYS = "checks.allPassed,checks.everythingElsePassed,checks.nothingWatched";

/// The check keys whose text names what failed, in its whatFailed slot.
Parameter FAILEDKEYS = "checks.notEverything,checks.notEverythingRestPassed";

/// The separator of the rows in whatFailed.
Parameter SEPARATOR = "; ";

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

/// A reply: its text, or the rendering of its catalog key, goes to the chat, followed by the check sentence when there is one.
Method OnOutbound(request As OcuTalon.Msg.Outbound, Output response As Ens.Response) As %Status
{
	Set response = ""
	Set sc = ..Target(request.ChatRef, request.SessionRef, .chatRef, .chatId)
	If (chatId = "") || $SYSTEM.Status.IsError(sc) Quit sc
	Set text = request.Text
	If (text = "") && (request.CatalogKey '= "") {
		Set text = ##class(OcuTalon.Msg.Catalog).Render(request.CatalogKey, request.Slots, ..#TEXTCHANNEL, .sc)
		If $SYSTEM.Status.IsError(sc) Quit sc
	}
	Set sentence = ..CheckSentence(request.CheckKey, request.CheckRows)
	If sentence '= "" Set text = text_$Char(10, 10)_sentence
	Quit ..Deliver(request.SessionRef, chatRef, chatId, text, "", "", request.DecisionRef)
}

/// A notification of a kind the chat gets: the rendering of its catalog key goes to the chat. Any other kind sends nothing.
Method OnNotification(request As OcuTalon.Msg.Notification, Output response As Ens.Response) As %Status
{
	Set response = ""
	If '$ListFind($ListFromString(..#KINDS), request.Kind) Quit $$$OK
	Set sc = ..Target(request.ChatRef, request.SessionRef, .chatRef, .chatId)
	If (chatId = "") || $SYSTEM.Status.IsError(sc) Quit sc
	Set text = ##class(OcuTalon.Msg.Catalog).Render(request.CatalogKey, request.Slots, ..#TEXTCHANNEL, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Quit ..Deliver(request.SessionRef, chatRef, chatId, text, request.ApprovalRef, request.Kind, request.DecisionRef)
}

/// The chat of a message: the chat row of its ChatRef when it has one, else the live pairing of its SessionRef (an owner that is not a
/// session is dropped with one warning). chatId is "" when there is no chat, and then one warning has been logged and the status is OK.
Method Target(ownerChatRef As %String, sessionRef As %String, Output chatRef As %String, Output chatId As %String) As %Status [ Private ]
{
	Set chatRef = "", chatId = ""
	Set row = ""
	If ownerChatRef '= "" {
		Set row = ##class(OcuTalon.Data.Pairing).Chat(ownerChatRef)
	} ElseIf sessionRef '= "" {
		If '..IsSession(sessionRef) Quit $$$OK
		Set row = ##class(OcuTalon.Data.Ownership).Pairing(sessionRef, .sc)
		If $SYSTEM.Status.IsError(sc) Quit sc
	}
	If '$IsObject(row) {
		$$$LOGWARNING(..#LOGNOCHAT)
		Quit $$$OK
	}
	Set chatRef = row.Ref
	Set chatId = row.ChatId
	Quit $$$OK
}

/// Sends the text to the chat and, for a message with a SessionRef, records its Delivery row. A failed Record is one warning only.
Method Deliver(sessionRef As %String, chatRef As %String, chatId As %String, text As %String, approvalRef As %String, kind As %String, decisionRef As %String) As %Status [ Private ]
{
	Set sc = ..Send(chatId, text, .messageId, .sent)
	If $SYSTEM.Status.IsError(sc) || 'sent || (sessionRef = "") Quit sc
	Do ..Recorded(sessionRef, chatRef_":"_messageId, approvalRef, kind, decisionRef)
	Quit $$$OK
}

/// The Delivery row of a message that was sent. A failure is one warning, since the message is never sent again.
Method Recorded(sessionRef As %String, channelMessageId As %String, approvalRef As %String, kind As %String, decisionRef As %String) [ Private ]
{
	Set sc = $$$OK
	Try {
		Set sc = ##class(OcuTalon.Data.Delivery).Record(sessionRef, "telegram", channelMessageId, approvalRef, kind, "", decisionRef)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) $$$LOGWARNING(..#LOGRECORD_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
}

/// The check sentence of a reply (see the class comment): "" for no key, for no row to name and, with one warning, for any other key or
/// a sentence that cannot be rendered.
Method CheckSentence(key As %String, rowsJson As %String) As %String [ Private ]
{
	If key = "" Quit ""
	Set sentence = ""
	Set sc = $$$OK
	Try {
		If $ListFind($ListFromString(..#PLAINKEYS), key) {
			Set sentence = ##class(OcuTalon.Msg.Catalog).Render(key, "", ..#TEXTCHANNEL, .sc)
		} ElseIf $ListFind($ListFromString(..#FAILEDKEYS), key) {
			Set failed = ..WhatFailed(rowsJson)
			If failed '= "" Set sentence = ##class(OcuTalon.Msg.Catalog).Render(key, {"whatFailed": (failed)}.%ToJSON(), ..#TEXTCHANNEL, .sc)
		} Else {
			Set sc = $SYSTEM.Status.Error(5001, "the check key is not one that gives a sentence")
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) {
		$$$LOGWARNING(..#LOGCHECK_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
		Quit ""
	}
	Quit sentence
}

/// What did not pass, as one text: every row (a JSON array) whose result is not passed and that has an entry, the failed rows first and
/// then the others, each group in row order, as "{entry} ({finding}, at {time})", joined with "; ". "" when no row is left or the rows
/// cannot be read.
Method WhatFailed(rowsJson As %String) As %String [ Private ]
{
	If rowsJson = "" Quit ""
	Set rows = ""
	Try {
		Set rows = ##class(%DynamicAbstractObject).%FromJSON(rowsJson)
	} Catch {
		Set rows = ""
	}
	If '$IsObject(rows) || 'rows.%IsA("%Library.DynamicArray") Quit ""
	Set onlineDemo = +##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set failed = "", other = ""
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(, .row) {
		If '$IsObject(row) || 'row.%IsA("%Library.DynamicObject") Continue
		If row.result = "passed" Continue
		Set entry = ..Field(row, "entry")
		If entry = "" Continue
		Set finding = ..Field(row, "finding")
		Set finding = $ZConvert($Extract(finding), "L")_$Extract(finding, 2, *)
		Set clock = ..Field(row, "checkedAt")
		Set dated = 0
		If clock '= "" {
			Set clock = ##class(OcuTalon.Data.Time).ForMessage(clock)
			Set dated = (clock '= "") && (clock '? 2N1":"2N)
			If clock '= "" Set clock = clock_$Select(onlineDemo: " ET", 1: "")
		}
		Set detail = ""
		Set at = $Select(dated: "on ", 1: "at ")
		If (finding '= "") && (clock '= "") {
			Set detail = finding_", "_at_clock
		} ElseIf finding '= "" {
			Set detail = finding
		} ElseIf clock '= "" {
			Set detail = at_clock
		}
		Set named = $Select(detail = "": entry, 1: entry_" ("_detail_")")
		If row.result = "failed" {
			Set failed = failed_$ListBuild(named)
		} Else {
			Set other = other_$ListBuild(named)
		}
	}
	Quit $ListToString(failed_other, ..#SEPARATOR)
}

/// A row's string field, trimmed of white space at both ends; "" for anything that is not a string.
Method Field(row As %DynamicObject, name As %String) As %String [ Private ]
{
	If row.%GetTypeOf(name) '= "string" Quit ""
	Quit $ZStrip(row.%Get(name), "<>W")
}

/// The text to the chat as sendMessage parts, in order. The status is the first failure. messageId is the Bot API message_id of the last
/// part that was sent ("" when its answer had none), and sent is the number of parts that were sent.
Method Send(chatId As %String, text As %String, Output messageId As %String, Output sent As %Integer) As %Status
{
	Set messageId = "", sent = 0
	Set parts = ##class(OcuTalon.Channel.Telegram.Api).Split(text)
	Set sc = $$$OK
	Set position = 0
	While $ListNext(parts, position, part) {
		If part = "" Continue
		Set sc = ..SendPart(chatId, part, .messageId)
		If $SYSTEM.Status.IsError(sc) Quit
		Set sent = sent + 1
	}
	Quit sc
}

/// One part, as a numeric chat_id and plain text. A 429 waits and sends the same part again, TRIES tries at most.
Method SendPart(chatId As %String, part As %String, Output messageId As %String) As %Status [ Private ]
{
	Set messageId = ""
	For try = 1:1:..#TRIES {
		Set params = {}
		Do params.%Set("chat_id", chatId, "number")
		Do params.%Set("text", part, "string")
		Set answer = ##class(OcuTalon.Channel.Telegram.Api).Call(..ApiBase, ..SSLConfig, "sendMessage", params, ..#SENDSECONDS, .httpStatus, .sc)
		If $SYSTEM.Status.IsError(sc) Quit
		If (httpStatus = 200) && +answer.ok {
			Set sc = $$$OK
			If $IsObject(answer.result) && (answer.result.%GetTypeOf("message_id") = "number") Set messageId = answer.result."message_id"
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
