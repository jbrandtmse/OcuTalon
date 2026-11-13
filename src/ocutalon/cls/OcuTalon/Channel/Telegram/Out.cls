/// TelegramOut, the outbound operation of the Telegram channel (Stories 12.2, 12.6, 12.7 and 17.6; AD-14, AD-19, AD-28, AD-32, UX-DR108, UX-DR136, UX-DR143). It
/// sends the text of an OcuTalon.Msg.Outbound or an OcuTalon.Msg.Notification to a chat through OcuTalon.Channel.Telegram.Api:
///   - the chat is the Pairing chat row of the message's ChatRef when it has one (every pairing notice), else the session's live pairing
///     (Ownership.Pairing of the SessionRef). An owner that is not a session is dropped with one warning. No chat sends nothing: one
///     warning that names neither a Ref nor an id, and the status is OK;
///   - an Outbound's text is its Text, else the catalog rendering of its CatalogKey for the channel telegram. When it has a CheckKey
///     whose sentence is not "", the text is followed by a blank line and the sentence (below). A Notification of the kinds tellnow,
///     incident, approval, result, reminder, allowance and pairing is sent as the rendering of its CatalogKey; the kinds answered and
///     handled are the edit in place (below); the kind digest is a plain-text message (below); any other kind (status, fallback) sends
///     nothing and records no row. A render error is returned and nothing is sent;
///   - the check sentence mirrors web/src/app/shared/check-sentence.ts (AD-28): checks.allPassed, checks.everythingElsePassed and
///     checks.nothingWatched give the catalog text, and checks.notEverything and checks.notEverythingRestPassed are rendered with
///     whatFailed, built from the CheckRows (result, entry, finding, checkedAt): every row that did not pass and has an entry, the failed
///     rows first, each group in row order, as "{entry} ({finding}, at {time})" with the finding's first letter in lower case and an
///     empty part left out, joined with "; ". The time is Data.Time.ForMessage of checkedAt, with " ET" on the online demo, and "at"
///     becomes "on" before a dated time, as the catalog renderer does. When no row is left, or the key is any other, or the sentence
///     cannot be rendered, the sentence is "" (one warning for the last two) and the reply goes alone. Only the key can say that
///     everything passed;
///   - the learned saves (Story 41.15, AD-21, AD-28): after the reply and its check sentence, an Outbound whose Learned entries OcuTalon.Memory.Learned
///     shows (Lines, for the channel telegram: one catalog line per entry, none when the reply text already says "I'll remember" or "I will remember")
///     goes on with a blank line and the lines, one per line, as plain text like the rest;
///   - the text goes as plain text, exactly as written, with no parse mode and no entities, as sendMessage parts of at most 4,096
///     UTF-16 units (Api.Split), in order. A 429 waits retry_after seconds (at least 1) and sends the same part again, at most TRIES
///     tries for one part, and a part that was sent is never sent twice. Any other failure is an error status with a safe text, and the
///     parts already sent stay sent;
///   - a message with a SessionRef, once every part is sent, records one Delivery row of channel telegram (Delivery.Record) whose
///     message id is "<ChatRef>:<message_id of the last part>" (just "<ChatRef>:" when that answer had no message_id). A message with
///     no SessionRef records none. A failed Record is one warning and the status stays OK, because the message is never sent again;
///   - a digest (Story 17.6): a Notification of the kind digest is a plain-text message, which goes as one message when it fits and otherwise as several, cut
///     at line breaks (Api.Split; a single line longer than a message is cut at the limit) and sent in order. Its Slots hold parts, lines and rows; every
///     {key, slots} of the parts and of the lines is rendered through Catalog.Render for the channel telegram, and nothing else is
///     added. The pieces go in this order, each on its own line, with no Markdown: the parts up to and including the checked part and its
///     reserved sentence, one coverage line for each row of lines, and then the needs-you parts, the saved-for-later part and the cost. It
///     records one Delivery row of the kind digest, whose message is the last one sent. A piece that cannot be rendered is an error and nothing is sent;
///   - a summary (Story 23.6): a Notification of the kind summary is a plain-text message like a digest, with the text of OcuTalon.Watch.Summary.Text(IncidentRef,
///     "telegram", .sc): the incident's stored summary, one catalog line per part, sent exactly as written with no parse mode and no buttons, as one message when it
///     fits and otherwise cut at line breaks (Api.Split). A summary that cannot be read or rendered is an error and nothing is sent;
///   - the Got it button (Story 17.6): a Notification of the kind tellnow that has a DecisionRef is sent with one inline button, the
///     catalog key button.gotIt, whose callback data is "gotit:<DecisionRef>", in the reply_markup of its last part only. It is split like a
///     message with the Approve and Reject buttons, and its Delivery row keeps the last part's text (redacted) and its DecisionRef, which
///     the edit of a handled notice needs;
///   - buttons (AD-32): a Notification of the kind incident or approval whose ApprovalRef is not "" is sent with the inline buttons
///     "Approve" and "Reject" (the catalog keys button.approve and button.reject) in the reply_markup of its last part only, whose
///     callback data is "approve:<ApprovalRef>" and "reject:<ApprovalRef>". Such a message is split at BUTTONLIMIT units, so that the
///     status of an edit always fits. A label that cannot be rendered is an error and nothing is sent. Its Delivery row also records
///     the ApprovalRef and the last part's text, which the edit needs: OcuTalon.Bridge.Redact.Text of it, or "" when the redactor
///     returns UNCHECKED. The text holds no chat id and no name, because a notice is rendered from the catalog and the notification's
///     slots. A row with no ApprovalRef and every row of kind answered keep the text "";
///   - the edit in place: a Notification of the kind answered finds the session's newest telegram Delivery row of its ApprovalRef
///     (Ownership.DeliveryFor). With no row, or a row with no stored text or no message id, nothing is sent and there is one warning.
///     When that row is of the kind answered, nothing is sent: the first answer stays. Otherwise editMessageText replaces the message
///     in its own chat with the stored text, a blank line and the rendering of the notification's CatalogKey, and sends no
///     reply_markup, which removes the buttons; a 429 is retried as a sendMessage part is. The edit records a Delivery row of the kind
///     answered with the same message id and ApprovalRef and the text "". A failed edit is one warning, the status stays OK and no
///     row is recorded. After the edit (or the failed edit) of a rejection from Telegram (answered.rejected or answered.rejectedBy, the slot channel
///     telegram, an IncidentRef) press.rejectedFollowUp goes to the same chat as a new message, whose row is of the kind answered with
///     no ApprovalRef. A result is a new message like any other;
///   - the edit of a handled notice (Story 17.6): a Notification of the kind handled finds the session's newest telegram Delivery row of its
///     DecisionRef (Delivery.FindByRef's row, Ownership.DeliveryByRef) and the time it was marked (Data.Handled Marked). With no row, no
///     stored text, no message id or no marker, nothing is sent and there is one warning. When that row is of the kind handled, nothing is
///     sent: the first edit stays. Otherwise editMessageText replaces the message in its own chat with the stored text, a blank line and the
///     catalog text handled.marked with the time, and sends no reply_markup, which removes the button. The edit records a Delivery row of the
///     kind handled with the same message id and DecisionRef and the text "". A failed edit is one warning, the status stays OK and no row
///     is recorded.
/// The token is never held here (AD-19), and no log text holds a chat id, a name or a message text.
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

Parameter LOGNOEDIT = "TelegramOut did not edit an answered request's message: no stored message with its text was found.";

Parameter LOGEDIT = "TelegramOut could not edit a message: ";

Parameter LOGNOHANDLED = "TelegramOut did not edit a handled notice's message: no stored message with its text, or no handled marker, was found.";

/// The notification kinds that the chat gets as a new message (answered and handled edit a message instead).
Parameter KINDS = "tellnow,incident,approval,result,reminder,allowance,pairing,digest,summary";

/// The notification kinds whose message carries the Approve and Reject buttons when it has an approval Ref.
Parameter BUTTONKINDS = "incident,approval";

/// The notification kinds whose message carries the Got it button when it has a decision Ref, and the catalog key of the button.
Parameter GOTITKINDS = "tellnow";

Parameter GOTITKEY = "button.gotIt";

/// The action in the callback data of the Got it button: "gotit:<DecisionRef>".
Parameter GOTITACTION = "gotit";

/// The catalog key of the text that replaces the button of a handled notice.
Parameter HANDLEDKEY = "handled.marked";

/// The most UTF-16 units of a message with buttons: the Bot API's 4,096 less a reserve, so that the edited text always fits.
Parameter BUTTONLIMIT = 3840;

/// The catalog keys of the button labels.
Parameter APPROVEKEY = "button.approve";

Parameter REJECTKEY = "button.reject";

/// The catalog keys of a rejection whose follow-up the chat gets, and the follow-up's key.
Parameter REJECTEDKEYS = "answered.rejected,answered.rejectedBy";

Parameter FOLLOWUPKEY = "press.rejectedFollowUp";

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
	Set lines = ##class(OcuTalon.Memory.Learned).Lines(request.Learned, request.Text, ..#TEXTCHANNEL)
	If lines.%Size() Set text = text_$Char(10, 10)_..Joined(lines)
	Quit ..Deliver(request.SessionRef, chatRef, chatId, text, "", "", request.DecisionRef)
}

/// The lines of a dynamic array of text, one per line (LF).
ClassMethod Joined(lines As %DynamicArray) As %String [ Private ]
{
	Set joined = ""
	Set iterator = lines.%GetIterator()
	While iterator.%GetNext(, .line) {
		Set joined = joined_$Select(joined = "": "", 1: $Char(10))_line
	}
	Quit joined
}

/// A notification of a kind the chat gets: the rendering of its catalog key goes to the chat, with the buttons for a request. An
/// answered notification edits the request's message. Any other kind sends nothing.
Method OnNotification(request As OcuTalon.Msg.Notification, Output response As Ens.Response) As %Status
{
	Set response = ""
	If request.Kind = "answered" Quit ..EditAnswered(request)
	If request.Kind = "handled" Quit ..EditHandled(request)
	If '$ListFind($ListFromString(..#KINDS), request.Kind) Quit $$$OK
	Set sc = ..Target(request.ChatRef, request.SessionRef, .chatRef, .chatId)
	If (chatId = "") || $SYSTEM.Status.IsError(sc) Quit sc
	If request.Kind = "digest" {
		Set text = ##class(OcuTalon.Channel.DigestText).Text(request.Slots, ..#TEXTCHANNEL, .sc)
	} ElseIf request.Kind = "summary" {
		Set text = ##class(OcuTalon.Watch.Summary).Text(request.IncidentRef, ..#TEXTCHANNEL, .sc)
	} Else {
		Set text = ##class(OcuTalon.Msg.Catalog).Render(request.CatalogKey, request.Slots, ..#TEXTCHANNEL, .sc)
	}
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set markup = ""
	If $ListFind($ListFromString(..#BUTTONKINDS), request.Kind) && (request.ApprovalRef '= "") {
		Set markup = ..Keyboard(request.ApprovalRef, .sc)
		If $SYSTEM.Status.IsError(sc) Quit sc
	} ElseIf $ListFind($ListFromString(..#GOTITKINDS), request.Kind) && (request.DecisionRef '= "") {
		Set markup = ..GotItKeyboard(request.DecisionRef, .sc)
		If $SYSTEM.Status.IsError(sc) Quit sc
	}
	Quit ..Deliver(request.SessionRef, chatRef, chatId, text, request.ApprovalRef, request.Kind, request.DecisionRef, markup)
}

/// The inline keyboard of a request's notice: one row with the Approve and Reject buttons, whose callback data is the action and the
/// request's Ref (never a sequential number). The status is an error when a label cannot be rendered.
Method Keyboard(approvalRef As %String, Output sc As %Status) As %DynamicObject [ Private ]
{
	Set approve = ##class(OcuTalon.Msg.Catalog).Render(..#APPROVEKEY, "", ..#TEXTCHANNEL, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ""
	Set reject = ##class(OcuTalon.Msg.Catalog).Render(..#REJECTKEY, "", ..#TEXTCHANNEL, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ""
	Quit {"inline_keyboard": [[{"text": (approve), "callback_data": ("approve:"_approvalRef)}, {"text": (reject), "callback_data": ("reject:"_approvalRef)}]]}
}

/// The inline keyboard of a tell-now notice: one row with the Got it button, whose callback data is the action and the notice's Ref (the Ref of its
/// Decision, 22 random characters). The status is an error when the label cannot be rendered.
Method GotItKeyboard(decisionRef As %String, Output sc As %Status) As %DynamicObject [ Private ]
{
	Set label = ##class(OcuTalon.Msg.Catalog).Render(..#GOTITKEY, "", ..#TEXTCHANNEL, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ""
	Quit {"inline_keyboard": [[{"text": (label), "callback_data": (..#GOTITACTION_":"_decisionRef)}]]}
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

/// Sends the text to the chat and, for a message with a SessionRef, records its Delivery row. A message with buttons (markup is an object)
/// keeps the last part's text in its row. A failed Record is one warning only.
Method Deliver(sessionRef As %String, chatRef As %String, chatId As %String, text As %String, approvalRef As %String, kind As %String, decisionRef As %String, markup As %DynamicObject = "") As %Status [ Private ]
{
	Set sc = ..Send(chatId, text, .messageId, .sent, markup, $Select($IsObject(markup): ..#BUTTONLIMIT, 1: ""), .lastText)
	If $SYSTEM.Status.IsError(sc) || 'sent || (sessionRef = "") Quit sc
	Set kept = ""
	If $IsObject(markup) {
		Set kept = ##class(OcuTalon.Bridge.Redact).Text(lastText)
		If kept = ##class(OcuTalon.Bridge.Redact).#UNCHECKED Set kept = ""
	}
	Do ..Recorded(sessionRef, chatRef_":"_messageId, approvalRef, kind, decisionRef, kept)
	Quit $$$OK
}

/// The Delivery row of a message that was sent. A failure is one warning, since the message is never sent again.
Method Recorded(sessionRef As %String, channelMessageId As %String, approvalRef As %String, kind As %String, decisionRef As %String, text As %String = "") As %Status [ Private ]
{
	Set sc = $$$OK
	Try {
		Set sc = ##class(OcuTalon.Data.Delivery).Record(sessionRef, "telegram", channelMessageId, approvalRef, kind, text, decisionRef)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) $$$LOGWARNING(..#LOGRECORD_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
	Quit sc
}

/// An answered notification: the request's message is edited in place (see the class comment). The status is an error only when the
/// status text cannot be rendered or the follow-up cannot be sent.
Method EditAnswered(request As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	If '..IsSession(request.SessionRef) Quit $$$OK
	Set row = ##class(OcuTalon.Data.Ownership).DeliveryFor(request.ApprovalRef, "telegram", request.SessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	If $IsObject(row) && (row.Kind = "answered") Quit $$$OK
	Set chatRef = $Piece($Select($IsObject(row): row.ChannelMessageId, 1: ""), ":", 1)
	Set messageId = $Piece($Select($IsObject(row): row.ChannelMessageId, 1: ""), ":", 2, *)
	Set chat = $Select(chatRef '= "": ##class(OcuTalon.Data.Pairing).Chat(chatRef), 1: "")
	If '$IsObject(row) || (row.Text = "") || (messageId '? 1.N) || '$IsObject(chat) {
		$$$LOGWARNING(..#LOGNOEDIT)
		Quit $$$OK
	}
	Set status = ##class(OcuTalon.Msg.Catalog).Render(request.CatalogKey, request.Slots, ..#TEXTCHANNEL, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set chatId = chat.ChatId
	Set params = {}
	Do params.%Set("chat_id", chatId, "number")
	Do params.%Set("message_id", messageId, "number")
	Do params.%Set("text", row.Text_$Char(10, 10)_status, "string")
	Set sc = ..Post("editMessageText", params, .answer)
	If $SYSTEM.Status.IsError(sc) {
		$$$LOGWARNING(..#LOGEDIT_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
		If ..FollowUp(request) Quit ..SendFollowUp(request.SessionRef, chatRef, chatId, request.DecisionRef)
		Quit $$$OK
	}
	Do ..Recorded(request.SessionRef, row.ChannelMessageId, request.ApprovalRef, "answered", request.DecisionRef)
	If ..FollowUp(request) Quit ..SendFollowUp(request.SessionRef, chatRef, chatId, request.DecisionRef)
	Quit $$$OK
}

/// A handled notification: the notice's message is edited in place (see the class comment). The status is an error only when the catalog text cannot be
/// rendered or the delivery rows cannot be read.
Method EditHandled(request As OcuTalon.Msg.Notification) As %Status [ Private ]
{
	If '..IsSession(request.SessionRef) Quit $$$OK
	Set row = ##class(OcuTalon.Data.Ownership).DeliveryByRef(request.DecisionRef, "telegram", request.SessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	If $IsObject(row) && (row.Kind = "handled") Quit $$$OK
	Set chatRef = $Piece($Select($IsObject(row): row.ChannelMessageId, 1: ""), ":", 1)
	Set messageId = $Piece($Select($IsObject(row): row.ChannelMessageId, 1: ""), ":", 2, *)
	Set chat = $Select(chatRef '= "": ##class(OcuTalon.Data.Pairing).Chat(chatRef), 1: "")
	Set marked = ##class(OcuTalon.Data.Handled).Marked(request.DecisionRef)
	If '$IsObject(row) || (row.Text = "") || (messageId '? 1.N) || '$IsObject(chat) || (marked = "") {
		$$$LOGWARNING(..#LOGNOHANDLED)
		Quit $$$OK
	}
	Set status = ##class(OcuTalon.Msg.Catalog).Render(..#HANDLEDKEY, {"time": (marked)}, ..#TEXTCHANNEL, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set params = {}
	Do params.%Set("chat_id", chat.ChatId, "number")
	Do params.%Set("message_id", messageId, "number")
	Do params.%Set("text", row.Text_$Char(10, 10)_status, "string")
	Set sc = ..Post("editMessageText", params, .answer)
	If $SYSTEM.Status.IsError(sc) {
		$$$LOGWARNING(..#LOGEDIT_##class(OcuTalon.Channel.Telegram.Api).Safe($SYSTEM.Status.GetErrorText(sc)))
		Quit $$$OK
	}
	Do ..Recorded(request.SessionRef, row.ChannelMessageId, "", "handled", request.DecisionRef)
	Quit $$$OK
}

/// 1 when the answered notification is a rejection from Telegram of a fix (an incident is set): the chat then gets a follow-up.
Method FollowUp(request As OcuTalon.Msg.Notification) As %Boolean [ Private ]
{
	If '$ListFind($ListFromString(..#REJECTEDKEYS), request.CatalogKey) || (request.IncidentRef = "") Quit 0
	Set slots = ""
	Try {
		Set slots = ##class(%DynamicAbstractObject).%FromJSON(request.Slots)
	} Catch {
		Set slots = ""
	}
	Quit $IsObject(slots) && (slots.%GetTypeOf("channel") = "string") && (slots.channel = "telegram")
}

/// The rejected follow-up as a new message to the chat; its row is of the kind answered with no ApprovalRef.
Method SendFollowUp(sessionRef As %String, chatRef As %String, chatId As %String, decisionRef As %String) As %Status [ Private ]
{
	Set text = ##class(OcuTalon.Msg.Catalog).Render(..#FOLLOWUPKEY, "", ..#TEXTCHANNEL, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Quit ..Deliver(sessionRef, chatRef, chatId, text, "", "answered", decisionRef)
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
/// part that was sent ("" when its answer had none), and sent is the number of parts that were sent. markup (a dynamic object, or "")
/// is the reply_markup of the last part only, limit the most units of a part ("" for the Bot API's), and lastText the text of the last
/// part that was sent.
Method Send(chatId As %String, text As %String, Output messageId As %String, Output sent As %Integer, markup As %DynamicObject = "", limit As %Integer = "", Output lastText As %String) As %Status
{
	Set messageId = "", sent = 0, lastText = ""
	Set parts = $Select(limit = "": ##class(OcuTalon.Channel.Telegram.Api).Split(text), 1: ##class(OcuTalon.Channel.Telegram.Api).Split(text, limit))
	Set sc = $$$OK
	Set position = 0
	Set number = 0
	Set count = $ListLength(parts)
	While $ListNext(parts, position, part) {
		Set number = number + 1
		If part = "" Continue
		Set sc = ..SendPart(chatId, part, .messageId, $Select(number = count: markup, 1: ""))
		If $SYSTEM.Status.IsError(sc) Quit
		Set sent = sent + 1
		Set lastText = part
	}
	Quit sc
}

/// One part, as a numeric chat_id and plain text, with the reply_markup when markup is an object.
Method SendPart(chatId As %String, part As %String, Output messageId As %String, markup As %DynamicObject = "") As %Status [ Private ]
{
	Set messageId = ""
	Set params = {}
	Do params.%Set("chat_id", chatId, "number")
	Do params.%Set("text", part, "string")
	If $IsObject(markup) Do params.%Set("reply_markup", markup)
	Set sc = ..Post("sendMessage", params, .answer)
	If $SYSTEM.Status.IsOK(sc) && $IsObject(answer.result) && (answer.result.%GetTypeOf("message_id") = "number") Set messageId = answer.result."message_id"
	Quit sc
}

/// One Bot API call (sendMessage or editMessageText). A 429 waits and makes the same call again, TRIES tries at most. answer is the
/// parsed answer of the last try.
Method Post(method As %String, params As %DynamicObject, Output answer As %DynamicObject) As %Status [ Private ]
{
	For try = 1:1:..#TRIES {
		Set answer = ##class(OcuTalon.Channel.Telegram.Api).Call(..ApiBase, ..SSLConfig, method, params, ..#SENDSECONDS, .httpStatus, .sc)
		If $SYSTEM.Status.IsError(sc) Quit
		If (httpStatus = 200) && +answer.ok {
			Set sc = $$$OK
			Quit
		}
		Set sc = $SYSTEM.Status.Error(5001, ##class(OcuTalon.Channel.Telegram.Api).Failure(method, httpStatus, answer))
		If (httpStatus '= 429) || (try = ..#TRIES) Quit
		Set wait = 1
		If $IsObject(answer.parameters) && (answer.parameters.%GetTypeOf("retry_after") = "number") && (answer.parameters."retry_after" > 1) Set wait = answer.parameters."retry_after"
		Hang wait
	}
	Quit sc
}

}
