Include Ensemble

/// SlackOut, the outbound operation of the Slack channel (Story 27.2; AD-14, AD-19, AD-24, AD-26, AD-32, NFR-11, R8). It posts the reply to a Slack turn to the member whose
/// direct message made the turn, with the Web API method chat.postMessage, and nothing else: no other Slack method is called, no Notification is ever sent (the message
/// map names OcuTalon.Msg.Outbound only), and nothing here opens a WebSocket or uses socket mode.
///   - Slack must be on (Channel.Slack.In On), else the status is the error ERROROFF and nothing is sent. The operation has no setting: the base of the API is read from
///     OCUTALON_SLACK_API_BASE (default https://slack.com/api, http(s)://host[:port][/path]) and the token from SLACK_BOT_TOKEN, each with $SYSTEM.Util.GetEnviron at the
///     moment of the call. The token is sent in the Authorization header only and is kept nowhere: not in a property, a setting, a row, a global, a message, a trace entry, a
///     log line or a status text, and every error text goes through Safe, which strips the exact token and then runs the bridge's redactor;
///   - the owner must be a session, else one warning and the status is OK. The recipient is the session's linked member (Data.SlackLink MemberFor): chat.postMessage with
///     channel set to the member id posts into the app's direct-message conversation with that member. A session with no link sends nothing: one warning, LOGNOMEMBER,
///     and the status is OK. The member id, the team id and Slack's direct-message channel id are in no log line, status text, trace entry or Delivery row;
///   - the text is exactly the text that Telegram sends for the reply (Channel.ReplyText for the channel slack), cut into parts of at most LIMIT UTF-16 units at line
///     breaks (Telegram.Api Split); each part has & < > written as &amp; &lt; &gt; and goes as one post with mrkdwn false, unfurl_links false and unfurl_media false,
///     in order, as plain text;
///   - a post is made with a new %Net.HttpRequest, with no redirect, a read timeout of SENDSECONDS and, for an https base, the client SSL configuration. It succeeded when
///     the HTTP status is 200 and the answer's ok is true. HTTP 429 waits the Retry-After header's seconds (1 when it is missing, not a whole number or below 1) and sends the
///     same part again, at most TRIES tries for one part; a wait over MAXWAIT seconds is not taken and the post fails with ERRORWAIT. Any other failure is at once an error
///     status: ERRORREACH when there was no answer, else ERRORREFUSED with the HTTP status and Slack's error code (letters, digits and the underscore, 64 characters at
///     most, else "none"). A part that was sent is never sent again, and the parts after a failed part are not sent;
///   - when the reply was sent whole, one Delivery row of channel slack (Delivery.Record) holds "<link Ref>:<ts>", the link's Ref and the ts that Slack answered for the
///     last part (empty after the colon when it is not of the form seconds.digits); it holds no text and no Slack id. A failed Record is one warning, LOGRECORD, and the
///     status stays OK, because the reply is never sent again. A check sentence that could not be built is left out, with one warning, LOGCHECK.
/// The text of every error and warning is fixed: a slot of it holds only an HTTP status, a whole number of seconds, Slack's error code or a fixed reason word.
Class OcuTalon.Channel.Slack.Out Extends OcuTalon.Channel.Operation
{

/// The environment variable that overrides the base of the Web API (CI sets it to its mock).
Parameter BASEVARIABLE = "OCUTALON_SLACK_API_BASE";

/// The public Web API, the default base.
Parameter PUBLICBASE = "https://slack.com/api";

/// The method that is called.
Parameter METHOD = "chat.postMessage";

/// The channel of the catalog text: Telegram's plain text.
Parameter TEXTCHANNEL = "slack";

/// The most UTF-16 units of one post (Slack's recommendation).
Parameter LIMIT = 4000;

/// The tries for one part when Slack answers 429.
Parameter TRIES = 5;

/// The most seconds that one wait for Retry-After is taken; the job of the operation is held while it waits.
Parameter MAXWAIT = 30;

/// The read timeout of one post, in seconds.
Parameter SENDSECONDS = 15;

/// What a Slack error code looks like, and what a message time (ts) looks like.
Parameter CODEPATTERN = "^[A-Za-z0-9_]{1,64}$";

Parameter TSPATTERN = "^[0-9]{1,12}\.[0-9]{1,8}$";

Parameter LOGNOTASESSION = "SlackOut dropped a message: its owner is not a session: ";

Parameter LOGPUBLISH = "SlackOut could not publish an event: ";

Parameter ERROROFF = "Slack is off, so SlackOut sends nothing.";

Parameter LOGNOMEMBER = "SlackOut found no linked Slack member for this session, so the reply went only to the web chat.";

Parameter ERRORBASE = "OCUTALON_SLACK_API_BASE must be http(s)://host[:port][/path].";

Parameter ERRORREACH = "OcuTalon could not reach Slack, so the reply was not sent to Slack.";

Parameter ERRORREFUSED = "Slack did not take the reply (HTTP {status}, error {code}), so it was not sent to Slack.";

Parameter ERRORWAIT = "Slack asked OcuTalon to wait {seconds} seconds, longer than the 30 it waits, so the reply was not sent to Slack.";

Parameter LOGRECORD = "SlackOut sent the reply but could not record its delivery: {reason}";

Parameter LOGCHECK = "SlackOut sent the reply without its check sentence: {reason}";

/// The fixed reasons of LOGRECORD and LOGCHECK.
Parameter REASONRECORD = "the row was not saved";

Parameter REASONCHECK = "the sentence could not be built";

XData MessageMap
{
<MapItems>
<MapItem MessageType="OcuTalon.Msg.Outbound">
<Method>OnOutbound</Method>
</MapItem>
</MapItems>
}

/// A reply to a Slack turn: its text goes to the session's linked member as chat.postMessage parts (see the class comment).
Method OnOutbound(request As OcuTalon.Msg.Outbound, Output response As Ens.Response) As %Status
{
	Set response = ""
	If '##class(OcuTalon.Channel.Slack.In).On() Quit $SYSTEM.Status.Error(5001, ..#ERROROFF)
	If '..IsSession(request.SessionRef) Quit $$$OK
	Set member = ##class(OcuTalon.Data.SlackLink).MemberFor(request.SessionRef, .linkRef)
	If member = "" {
		$$$LOGWARNING(..#LOGNOMEMBER)
		Quit $$$OK
	}
	Set text = ##class(OcuTalon.Channel.ReplyText).Text(request, ..#TEXTCHANNEL, .sc, .warning)
	If $SYSTEM.Status.IsError(sc) Quit $SYSTEM.Status.Error(5001, ..Safe($SYSTEM.Status.GetErrorText(sc)))
	If warning '= "" $$$LOGWARNING($Replace(..#LOGCHECK, "{reason}", ..#REASONCHECK))
	Set sc = ..Send(member, text, .ts, .sent)
	Kill member
	If $SYSTEM.Status.IsError(sc) || 'sent Quit sc
	Do ..Recorded(request.SessionRef, linkRef, ts, request.DecisionRef)
	Quit $$$OK
}

/// The text to the member as chat.postMessage parts, in order. The status is the first failure, and the parts after it are not sent. ts is the message time that Slack
/// answered for the last part that was sent, and sent the number of parts that were sent.
Method Send(member As %String, text As %String, Output ts As %String, Output sent As %Integer) As %Status [ Private ]
{
	Set ts = "", sent = 0
	Set parts = ##class(OcuTalon.Channel.Telegram.Api).Split(text, ..#LIMIT)
	Set sc = $$$OK
	Set position = 0
	While $ListNext(parts, position, part) {
		Set sc = ..Post(member, ..Escaped(part), .ts)
		If $SYSTEM.Status.IsError(sc) Quit
		Set sent = sent + 1
	}
	Quit sc
}

/// The text with & < > written as the entities that Slack reads them as (& first).
ClassMethod Escaped(text As %String) As %String [ Private ]
{
	Set text = $Replace($Get(text), "&", "&amp;")
	Set text = $Replace(text, "<", "&lt;")
	Quit $Replace(text, ">", "&gt;")
}

/// One part as one post, with the 429 loop (see the class comment). ts is the message time of the answer that took it.
Method Post(member As %String, text As %String, Output ts As %String) As %Status [ Private ]
{
	Set ts = ""
	Set sc = $$$OK
	For try = 1:1:..#TRIES {
		Set answer = ..Call(member, text, .httpStatus, .retryAfter, .sc)
		If $SYSTEM.Status.IsError(sc) Quit
		If (httpStatus = 200) && $IsObject(answer) && (answer.%GetTypeOf("ok") = "boolean") && answer.ok {
			If (answer.%GetTypeOf("ts") = "string") && $Match(answer.ts, ..#TSPATTERN) Set ts = answer.ts
			Set sc = $$$OK
			Quit
		}
		Set refused = $SYSTEM.Status.Error(5001, ..Safe(..Refused(httpStatus, answer)))
		If httpStatus '= 429 {
			Set sc = refused
			Quit
		}
		Set wait = $Select($Match(retryAfter, "^[0-9]{1,9}$") && (+retryAfter >= 1): +retryAfter, 1: 1)
		If wait > ..#MAXWAIT {
			Set sc = $SYSTEM.Status.Error(5001, $Replace(..#ERRORWAIT, "{seconds}", wait))
			Quit
		}
		Set sc = refused
		If try < ..#TRIES Hang wait
	}
	Quit sc
}

/// The text of a refusal: the HTTP status and Slack's error code (letters, digits and underscores, up to 64 of them), "none" when the answer has none.
ClassMethod Refused(httpStatus As %Integer, answer As %DynamicObject) As %String [ Private ]
{
	Set code = "none"
	If $IsObject($Get(answer)) && (answer.%GetTypeOf("error") = "string") && $Match(answer.error, ..#CODEPATTERN) Set code = answer.error
	Quit $Replace($Replace(..#ERRORREFUSED, "{status}", +$Get(httpStatus)), "{code}", code)
}

/// One call of chat.postMessage, with a new request, no redirect and the token in the Authorization header only. The JSON body is written as UTF-8 bytes in raw mode, so that
/// the request's charset table does not encode it a second time. The answer is the parsed JSON body, "" when it is not a
/// JSON object; httpStatus is the HTTP status of the answer and retryAfter the text of its Retry-After header. sc is an error status, with a fixed text, when the
/// base is not valid, no token is set, or no answer came.
Method Call(member As %String, text As %String, Output httpStatus As %Integer, Output retryAfter As %String, Output sc As %Status) As %DynamicObject [ Private ]
{
	Set httpStatus = "", retryAfter = ""
	Set sc = $$$OK
	Set answer = ""
	Try {
		Set sc = ##class(OcuTalon.Channel.Telegram.Api).Endpoint(..Base(), .server, .port, .https, .prefix)
		If $SYSTEM.Status.IsError(sc) {
			Set sc = $SYSTEM.Status.Error(5001, ..#ERRORBASE)
			Quit
		}
		Set token = ..Token()
		If token = "" {
			Set sc = $SYSTEM.Status.Error(5001, ..#ERROROFF)
			Quit
		}
		Set request = ##class(%Net.HttpRequest).%New()
		Set request.Server = server
		Set request.Port = port
		Set request.FollowRedirect = 0
		Set request.Timeout = ..#SENDSECONDS
		If https {
			Set request.Https = 1
			Set request.SSLConfiguration = ##class(OcuTalon.Channel.Telegram.Api).#SSLCONFIG
		}
		Set request.ContentType = "application/json; charset=utf-8"
		Set request.WriteRawMode = 1
		Do request.SetHeader("Authorization", "Bearer "_token)
		Set body = {}
		Do body.%Set("channel", member, "string")
		Do body.%Set("text", text, "string")
		Do body.%Set("mrkdwn", 0, "boolean")
		Do body.%Set("unfurl_links", 0, "boolean")
		Do body.%Set("unfurl_media", 0, "boolean")
		Do request.EntityBody.Write($ZConvert(body.%ToJSON(), "O", "UTF8"))
		Set post = request.Post(prefix_"/"_..#METHOD)
		Kill token
		Set response = request.HttpResponse
		If $SYSTEM.Status.IsError(post) || '$IsObject(response) {
			Set sc = $SYSTEM.Status.Error(5001, ..#ERRORREACH)
			Quit
		}
		Set httpStatus = response.StatusCode
		Set retryAfter = response.GetHeader("RETRY-AFTER")
		Try {
			Set answer = {}.%FromJSON(response.Data)
		} Catch {
			Set answer = ""
		}
		If '$IsObject(answer) || ($ClassName(answer) '= "%Library.DynamicObject") Set answer = ""
	} Catch exception {
		Set answer = ""
		Set sc = $SYSTEM.Status.Error(5001, ..#ERRORREACH)
	}
	Quit answer
}

/// The bot token: the environment variable that Channel.Slack.In reads, read at each call and never kept.
ClassMethod Token() As %String [ Private ]
{
	Quit $SYSTEM.Util.GetEnviron(##class(OcuTalon.Channel.Slack.In).#TOKENVARIABLE)
}

/// The base of the Web API: OCUTALON_SLACK_API_BASE, else the public one. Read at each call.
ClassMethod Base() As %String [ Private ]
{
	Set base = $SYSTEM.Util.GetEnviron(..#BASEVARIABLE)
	Quit $Select(base = "": ..#PUBLICBASE, 1: base)
}

/// The Delivery row of a reply that was sent: "<link Ref>:<ts>", no text. A failure is one warning, since the reply is never sent again.
Method Recorded(sessionRef As %String, linkRef As %String, ts As %String, decisionRef As %String) As %Status [ Private ]
{
	Set sc = $$$OK
	Try {
		Set sc = ##class(OcuTalon.Data.Delivery).Record(sessionRef, "slack", linkRef_":"_ts, "", "", "", decisionRef)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) $$$LOGWARNING($Replace(..#LOGRECORD, "{reason}", ..#REASONRECORD))
	Quit sc
}

/// The text with the exact bot token replaced, and then with every sensitive value replaced by the bridge's redactor. The redactor does not recognise the CI dummy token,
/// so the exact value is replaced first.
ClassMethod Safe(text As %String) As %String
{
	Set text = $Get(text)
	Set token = ..Token()
	If token '= "" Set text = $Replace(text, token, "[redacted]")
	Quit ##class(OcuTalon.Bridge.Redact).Text(text)
}

}
