/// The REST surface of OcuTalon at /ocutalon/api (AD-13): JSON, versioned under /v1, one CSP session shared
/// with /ocutalon and the trace applications.
///   - GET /v1/state is the snapshot and GET /v1/events the poll (AD-12); POST /v1/session/end signs out; POST /v1/messages
///     takes the page's message, {clientId, text, fromGuide}, hands it to WebChatIn through the production (AD-1, AD-30) and
///     answers 202 {clientId} (a repeat of a clientId included) or 400 bad_message for any other body. Every other
///     route of the release that no story has shipped answers 501 not_built, and the pairing routes answer 404 while
///     Telegram is not included. POST /v1/mailbox/incoming and /v1/mailbox/samples/:name simulate an incoming email: with demo
///     mode off both answer 404 not_found before anything else is read. The first takes {from, subject, body} (strings; from
///     optional, at most 1000 characters with the subject; the body at most SimMailboxIn's BODYMAX): a blank subject or body is 400 bad_email with its field error (the
///     subject first), and any other bad body is 400 bad_email with the general text; the second takes the name of a sample
///     (newsletter, partner-notice, suspicious-request, else 404 not_found) and does not read the body. Both hand SimMailboxIn
///     (through the production, AD-1) a Channel.SimMailbox.Mail for the CSP session's session and answer 202 {"ref"}; a session
///     that can't be read and any failure are 500 server_error. POST /v1/guide/markers takes {marker: trace_opened | run_again}, writes that UI-only marker of the
///     session's GuideState, refreshes the guide and answers 200 with the guide view (404 not_found with demo mode off, 400
///     bad_marker for any other body). POST /v1/demo/break-feed presses Break the feed: with demo mode off the answer is 404 not_found
///     before anything else, the body is not read, and the session is the CSP session's; BreakFeedIn (Demo.BreakFeedIn, through the
///     production) answers 200 {"state":"sent","startedAt"}, or 409 {"error":{"code","message"}} with the code not_watching or
///     incident_in_progress and its plain-English hint when the press is not available (nothing is sent then); a session that
///     can't be read and any other failure are 500 server_error. Both routes that name a record (approvals/:ref/answer, incidents/:ref/dismiss)
///     answer 404 first for a ref the session can't see.
///     POST /v1/approvals/:ref/answer takes {action: approve | reject, channel: web | phone} (any other body is 400 bad_answer; the
///     Telegram channel enters through AnswersIn only) and goes through AnswersIn to AnswerOps (AD-11): 200 {"result":"done","approval"},
///     409 already_answered or expired (the error beside the request's "approval" payload), 403 not_allowed, 404 not_found and 400 bad_answer.
///     POST /v1/incidents/:ref/dismiss (AD-1, AD-15) never reads the body and submits a Dismiss command for the CSP session through
///     Commands.Submit (origin web_user): 200 {"result":"done"}, 409 not_dismissible (the owner's refusal), 501 not_built for a stub
///     owner, 404 not_found and 500 server_error.
///     The snapshot also tells the page who is signed in, which mode
///     the instance runs in (onlineDemo, demoMode), the display names of the models its agents use, the Telegram block
///     and the active status conditions, and, last and only while demo mode is on, the simulated phone, the simulated mailbox
///     and the guide that Demo.Guide.Compute derives.
///   - A request without a session is answered 401 signed_out with no WWW-Authenticate header, so that no browser
///     opens its own password prompt; the public superclass OcuTalon.Web.Public.ApiBase does that, because the
///     answer comes before any role exists. A signed-in user without the OcuTalon user role is answered 403
///     no_role, and the session stays open for the trace applications.
///   - A state-changing call (any method but GET, HEAD and OPTIONS) needs Content-Type: application/json, the
///     header X-OcuTalon-Request: 1 and an Origin that is the request's own origin (AD-13).
///   - No call takes a SessionRef from the client (AD-4): the session is the one that OcuTalon.Data.Ownership.SessionRef
///     resolves from the CSP session, and every record is read through Ownership.
///   - Every payload object of /state and /events that carries traceHeaderId and traceNamespace also carries traceUrl, the path
///     of its trace in Visual Trace for the signed-in user, when a trace application serves its namespace (Web.TraceLink, AD-26).
///   - Every error is {"error": {"code", "message"}} in plain English.
Class OcuTalon.Web.Api Extends OcuTalon.Web.Public.ApiBase
{

Parameter UseSession = 1;

Parameter HandleCorsRequest = 0;

Parameter HTTP501NOTIMPLEMENTED = "501 Not Implemented";

/// The most entries the snapshot's chat holds: the newest, oldest first (DW-65).
Parameter CHATMAX = 100;

/// The most simulated-phone messages the snapshot's phone holds: the newest, oldest first.
Parameter PHONEMAX = 100;

/// The most simulated-mailbox emails the snapshot's mailbox holds: the newest, oldest first.
Parameter MAILMAX = 100;

Parameter MESSAGEBADCURSOR = "The after and afterInstance values must be whole numbers of zero or more.";

Parameter MESSAGENOTJSON = "OcuTalon refused this request because it wasn't sent as JSON.";

Parameter MESSAGENOHEADER = "OcuTalon refused this request because it didn't come from the OcuTalon page.";

Parameter MESSAGEWRONGORIGIN = "OcuTalon refused this request because it came from another site.";

Parameter MESSAGEBADMESSAGE = "A message needs a clientId and some text.";

Parameter MESSAGEEMPTYSUBJECT = "Enter a subject.";

Parameter MESSAGEEMPTYBODY = "Enter a body.";

Parameter MESSAGEBADEMAIL = "An email needs a subject and a body. From and subject can be at most 1000 characters, and the body at most 10000.";

Parameter MESSAGEBADMARKER = "A guide marker must be trace_opened or run_again.";

Parameter MESSAGENOTWATCHING = "Ask OcuTalon to watch the Orders production first (step 1).";

Parameter MESSAGEINCIDENTINPROGRESS = "Finish the current Orders incident first: approve or reject its fix, or dismiss the incident.";

Parameter MESSAGENOTFOUND = "OcuTalon has nothing at this address.";

Parameter MESSAGENOTAPPROVER = "Only an approver for resends can answer this request.";

Parameter MESSAGENOTAPPROVERTOOL = "Only an approver can answer this request.";

Parameter MESSAGEBADANSWER = "An answer needs an action, approve or reject, and a channel, web or phone.";

Parameter MESSAGENOTALLOWED = "This address doesn't accept that kind of request.";

Parameter MESSAGESERVERERROR = "Something went wrong inside OcuTalon. Try again.";

Parameter MESSAGENOTBUILT = "This part of OcuTalon isn't built yet.";

Parameter MESSAGENOTDISMISSIBLE = "OcuTalon can't dismiss this incident now. Nothing was changed.";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/v1/state" Method="GET" Call="State"/>
<Route Url="/v1/events" Method="GET" Call="Events"/>
<Route Url="/v1/messages" Method="POST" Call="Messages"/>
<Route Url="/v1/approvals/:ref/answer" Method="POST" Call="AnswerApproval"/>
<Route Url="/v1/incidents/:ref/dismiss" Method="POST" Call="DismissIncident"/>
<Route Url="/v1/demo/break-feed" Method="POST" Call="BreakFeed"/>
<Route Url="/v1/mailbox/incoming" Method="POST" Call="MailboxIncoming"/>
<Route Url="/v1/mailbox/samples/:name" Method="POST" Call="MailboxSample"/>
<Route Url="/v1/guide/markers" Method="POST" Call="GuideMarkers"/>
<Route Url="/v1/session/end" Method="POST" Call="EndSession"/>
<Route Url="/v1/pairing/code" Method="POST" Call="Pairing"/>
<Route Url="/v1/pairing" Method="DELETE" Call="Pairing"/>
</Routes>
}

/// Every request, before the route is matched: the role check first, then the browser envelope. A refusal
/// writes its error and stops the dispatch.
ClassMethod OnPreDispatch(url As %String, method As %String, ByRef continue As %Boolean) As %Status
{
	If '##class(OcuTalon.Web.Public.Shell).HasRole() {
		Set continue = 0
		Quit ..Fail(403, "no_role", ##class(OcuTalon.Web.Public.Login).#ERRORNOROLE)
	}
	Set code = ..EnvelopeError(%request.Method, %request.ContentType, %request.GetCgiEnv("HTTP_X_OCUTALON_REQUEST"), %request.GetCgiEnv("HTTP_ORIGIN"), %request.GetCgiEnv("HTTP_HOST"), %request.Secure)
	If code '= "" {
		Set continue = 0
		Quit ..Fail(403, code, ..EnvelopeMessage(code))
	}
	Quit $SYSTEM.Status.OK()
}

/// The error body for 404, 405 and 500; the cause of a 500 is logged, never sent. Every other status is the
/// superclass's.
ClassMethod ReportHttpStatusCode(pHttpStatus, pSC As %Status = {$$$OK}) As %Status
{
	Set status = +pHttpStatus
	If status = 404 Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If status = 405 Quit ..Fail(405, "method_not_allowed", ..#MESSAGENOTALLOWED)
	If status = 500 Quit ..ServerError(pSC)
	Quit ##super(pHttpStatus, pSC)
}

/// The 500 answer: the cause is written to the console log, never sent.
ClassMethod ServerError(sc As %Status = {$$$OK}) As %Status [ Private ]
{
	If $SYSTEM.Status.IsError(sc) {
		Try {
			Do ##class(%SYS.System).WriteToConsoleLog("OcuTalon.Web.Api: "_$Translate($SYSTEM.Status.GetErrorText(sc), $Char(13, 10), "  "), 0, 1)
		} Catch {
		}
	}
	Quit ..Fail(500, "server_error", ..#MESSAGESERVERERROR)
}

/// GET /v1/state
ClassMethod State() As %Status
{
	Set session = ..CurrentSession(.sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Do ..StateBody(session).%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// GET /v1/events?after=<sessionSeq>&afterInstance=<instanceSeq>
ClassMethod Events() As %Status
{
	Set after = %request.Get("after")
	Set afterInstance = %request.Get("afterInstance")
	If '..IsCursor(after) || '..IsCursor(afterInstance) {
		Quit ..Fail(400, "bad_cursor", ..#MESSAGEBADCURSOR)
	}
	Set session = ..CurrentSession(.sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Do ..EventsBody(session, +after, +afterInstance).%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// POST /v1/session/end: signs the user out. The CSP session ends together with every application of the sign-in group
/// (Logout(1) with EndSession), and the answer is 204 with no body. The browser envelope was checked before the route.
ClassMethod EndSession() As %Status
{
	Do %session.Logout(1)
	Set %session.EndSession = 1
	Set %response.Status = ..#HTTP204NOCONTENT
	Quit $SYSTEM.Status.OK()
}

/// POST /v1/messages: the page's message. The body is a JSON object with a clientId (a string of 1 to 128 characters), a text
/// (a string with a non-space character) and fromGuide (true only when it is the JSON true); anything else, a body that is not
/// a JSON object included, is 400 bad_message and nothing is sent. The session is the one that Ownership.SessionRef resolves
/// (AD-4): a sessionRef in the body is ignored. A valid body is handed to WebChatIn (Post) and answers 202 {"clientId"}, a
/// clientId that the session already used included. A session that can't be read, a production that can't take the message
/// and an error of WebChatIn are 500 server_error.
ClassMethod Messages() As %Status
{
	If '..MessageBody(.clientId, .text, .fromGuide) Quit ..Fail(400, "bad_message", ..#MESSAGEBADMESSAGE)
	Set session = ..CurrentSession(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set post = ##class(OcuTalon.Channel.WebChat.Post).%New()
	Set post.SessionRef = session.Ref
	Set post.ClientId = clientId
	Set post.Text = text
	Set post.FromGuide = fromGuide
	Set sc = ..Post(post, .output)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set %response.ContentType = ..#CONTENTTYPE
	Set %response.Status = ..#HTTP202ACCEPTED
	Write {"clientId": (clientId)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// The fields of the request body, and 1 when it is a valid message: see Messages. Otherwise 0, with the fields empty.
ClassMethod MessageBody(Output clientId As %String, Output text As %String, Output fromGuide As %Boolean) As %Boolean [ Private ]
{
	Set (clientId, text) = ""
	Set fromGuide = 0
	Try {
		Set body = ##class(%DynamicAbstractObject).%FromJSON(..BodyText())
	} Catch {
		Set body = ""
	}
	If '$IsObject(body) || 'body.%IsA("%Library.DynamicObject") Quit 0
	If (body.%GetTypeOf("clientId") '= "string") || (body.%GetTypeOf("text") '= "string") Quit 0
	Set id = body.clientId, message = body.text
	If ($Length(id) < 1) || ($Length(id) > 128) || ($ZStrip(message, "<>WC") = "") Quit 0
	Set clientId = id
	Set text = message
	Set fromGuide = (body.%GetTypeOf("fromGuide") = "boolean") && body.fromGuide
	Quit 1
}

/// The request body as text, "" when there is none. The CSP server hands the body over as the bytes that were sent (this class
/// leaves CONVERTINPUTSTREAM at 0), and the page sends JSON in UTF-8, so a binary body is decoded from UTF-8; a character body
/// is already text. A body longer than the longest string throws, which MessageBody answers as a bad body.
ClassMethod BodyText() As %String [ Private ]
{
	Set content = %request.Content
	If '$IsObject(content) Quit ""
	Do content.Rewind()
	Set raw = ""
	While 'content.AtEnd {
		Set raw = raw_content.Read(32000)
	}
	If content.IsCharacter() Quit raw
	Quit $ZConvert(raw, "I", "UTF8")
}

/// Hands the input (a Channel.WebChat.Post) to WebChatIn: the service is created in this process and takes the input with
/// ProcessInput, so that the message enters the production through its business service (AD-1). output is the service's
/// answer. An error status means the message did not reach the production.
ClassMethod Post(input As %RegisteredObject, Output output As %String) As %Status [ Private ]
{
	Set output = ""
	Set sc = ##class(Ens.Director).CreateBusinessService("WebChatIn", .service)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Quit service.ProcessInput(input, .output)
}

/// Hands the input (a Demo.Press) to BreakFeedIn: the service is created in this process and takes the input with ProcessInput, so
/// that the press enters the production through its business service (AD-1). output is the service's JSON answer. An error status
/// means the press failed.
ClassMethod Press(input As %RegisteredObject, Output output As %String) As %Status [ Private ]
{
	Set output = ""
	Set sc = ##class(Ens.Director).CreateBusinessService("BreakFeedIn", .service)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Quit service.ProcessInput(input, .output)
}

/// POST /v1/demo/break-feed: see the class comment. The order is demo mode off (404), a session that can't be read (500), the press
/// (BreakFeedIn), an inactive or refused press (409, code = the reason), a sent one (200) and any other failure (500).
ClassMethod BreakFeed() As %Status
{
	If '##class(OcuTalon.Demo.Guide).DemoOn() Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set session = ..CurrentSession(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set input = ##class(OcuTalon.Demo.Press).%New()
	Set input.SessionRef = session.Ref
	Set sc = ..Press(input, .output)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set answer = ##class(%DynamicAbstractObject).%FromJSON(output)
		Set outcome = answer.outcome
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If outcome = "inactive" {
		If answer.reason = "not_watching" Quit ..Fail(409, "not_watching", ..#MESSAGENOTWATCHING)
		If answer.reason = "incident_in_progress" Quit ..Fail(409, "incident_in_progress", ..#MESSAGEINCIDENTINPROGRESS)
	}
	If outcome '= "sent" Quit ..ServerError($SYSTEM.Status.Error(5001, "BreakFeedIn answered an outcome that the route doesn't know"))
	Set %response.ContentType = ..#CONTENTTYPE
	Write {"state": (answer.state), "startedAt": (answer.startedAt)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// Hands the input (a Channel.SimMailbox.Mail) to SimMailboxIn: the service is created in this process and takes the input with
/// ProcessInput, so that the email enters the production through its business service (AD-1). output is the service's JSON
/// answer. An error status means the email was not recorded and sent.
ClassMethod Mail(input As %RegisteredObject, Output output As %String) As %Status [ Private ]
{
	Set output = ""
	Set sc = ##class(Ens.Director).CreateBusinessService("SimMailboxIn", .service)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Quit service.ProcessInput(input, .output)
}

/// POST /v1/mailbox/incoming: see the class comment. The order is demo mode off (404), the body (400 bad_email), a session that
/// can't be read (500), SimMailboxIn (through the production; an error is 500) and the answer 202 {"ref"}. A sessionRef in the
/// body is ignored (AD-4).
ClassMethod MailboxIncoming() As %Status
{
	If '##class(OcuTalon.Demo.Guide).DemoOn() Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If '..MailBody(.from, .subject, .body, .message) Quit ..Fail(400, "bad_email", message)
	Set session = ..CurrentSession(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set mail = ##class(OcuTalon.Channel.SimMailbox.Mail).%New()
	Set mail.SessionRef = session.Ref
	Set mail.Sender = from
	Set mail.Subject = subject
	Set mail.Text = body
	Quit ..MailAccepted(mail)
}

/// POST /v1/mailbox/samples/:name: with demo mode off, or for a name that is not a sample, 404 not_found before the body or the
/// session is read; otherwise SimMailboxIn gets the sample's name and the answer is 202 {"ref"}.
ClassMethod MailboxSample(name As %String = "") As %Status
{
	If '##class(OcuTalon.Demo.Guide).DemoOn() Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If '##class(OcuTalon.Channel.SimMailbox.In).IsSample(name) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set session = ..CurrentSession(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set mail = ##class(OcuTalon.Channel.SimMailbox.Mail).%New()
	Set mail.SessionRef = session.Ref
	Set mail.Sample = name
	Quit ..MailAccepted(mail)
}

/// Hands the mail to SimMailboxIn and answers 202 {"ref"} from the service's output; an error, or an output that is not a JSON
/// object with a ref, is 500 server_error.
ClassMethod MailAccepted(mail As OcuTalon.Channel.SimMailbox.Mail) As %Status [ Private ]
{
	Set sc = ..Mail(mail, .output)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set answer = ##class(%DynamicAbstractObject).%FromJSON(output)
		Set ref = answer.ref
		If (answer.%GetTypeOf("ref") '= "string") || (ref = "") Set sc = $SYSTEM.Status.Error(5001, "SimMailboxIn answered no ref")
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set %response.ContentType = ..#CONTENTTYPE
	Set %response.Status = ..#HTTP202ACCEPTED
	Write {"ref": (ref)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// The fields of the request body, and 1 when it is a valid email: a JSON object whose from, subject and body are strings (a
/// missing one is empty), from and subject at most 1000 characters, the body at most Channel.SimMailbox.In's BODYMAX, subject and body not blank (blank is empty after stripping
/// white space and control characters). Otherwise 0, with the fields empty and message the plain-English reason: the subject's
/// field error first, then the body's, and the general text for any other bad body.
ClassMethod MailBody(Output from As %String, Output subject As %String, Output body As %String, Output message As %String) As %Boolean [ Private ]
{
	Set (from, subject, body) = ""
	Set message = ..#MESSAGEBADEMAIL
	Try {
		Set object = ##class(%DynamicAbstractObject).%FromJSON(..BodyText())
	} Catch {
		Set object = ""
	}
	If '$IsObject(object) || 'object.%IsA("%Library.DynamicObject") Quit 0
	Set valid = 1
	For name = "from", "subject", "body" {
		Set type = object.%GetTypeOf(name)
		If (type '= "string") && (type '= "unassigned") Set valid = 0
	}
	If 'valid Quit 0
	Set sender = $Select(object.%GetTypeOf("from") = "string": object.from, 1: "")
	Set title = $Select(object.%GetTypeOf("subject") = "string": object.subject, 1: "")
	Set text = $Select(object.%GetTypeOf("body") = "string": object.body, 1: "")
	If ($Length(sender) > 1000) || ($Length(title) > 1000) || ($Length(text) > ##class(OcuTalon.Channel.SimMailbox.In).#BODYMAX) Quit 0
	If $ZStrip(title, "<>WC") = "" {
		Set message = ..#MESSAGEEMPTYSUBJECT
		Quit 0
	}
	If $ZStrip(text, "<>WC") = "" {
		Set message = ..#MESSAGEEMPTYBODY
		Quit 0
	}
	Set from = sender, subject = title, body = text
	Quit 1
}

/// POST /v1/approvals/:ref/answer: see the class comment. The order is the session (Ownership.SessionRef), the request's visibility
/// (Ownership.Approval: 404 not_found for a request the session can't see or a cancelled one, whatever the body), the body
/// (400 bad_answer) and AnswersIn.FromPage, whose AnswerResult is mapped by AnswerResponse. The visibility row is released before
/// the answer, so that AnswerResponse reads the answered row afresh. An error status of the session, the read or AnswersIn is 500
/// server_error.
ClassMethod AnswerApproval(ref As %String) As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set row = ##class(OcuTalon.Data.Ownership).Approval(ref, sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(row) || (row.State = "cancelled") Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If '..AnswerBody(.action, .channel) Quit ..Fail(400, "bad_answer", ..#MESSAGEBADANSWER)
	Set kind = row.Kind
	Kill row
	Set sc = ##class(OcuTalon.Core.AnswersIn).FromPage(ref, action, channel, .result, .answeringRef)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "AnswersIn answered no result"))
	Quit ..AnswerResponse(ref, kind, sessionRef, result)
}

/// The action and channel of the request body, and 1 when it is valid: a JSON object whose action is the string approve or reject
/// and whose channel is the string web or phone (other members are ignored). Otherwise 0, with both empty.
ClassMethod AnswerBody(Output action As %String, Output channel As %String) As %Boolean [ Private ]
{
	Set (action, channel) = ""
	Try {
		Set body = ##class(%DynamicAbstractObject).%FromJSON(..BodyText())
	} Catch {
		Set body = ""
	}
	If '$IsObject(body) || 'body.%IsA("%Library.DynamicObject") Quit 0
	If (body.%GetTypeOf("action") '= "string") || (body.%GetTypeOf("channel") '= "string") Quit 0
	If '$ListFind($ListBuild("approve", "reject"), body.action) || '$ListFind($ListBuild("web", "phone"), body.channel) Quit 0
	Set action = body.action
	Set channel = body.channel
	Quit 1
}

/// The answer of the route for AnswersIn's result:
///   - done: 200 {"result":"done","approval"}, the request re-read through Ownership;
///   - already_answered: 409 with the catalog's late-press text of the winner and the request's payload, naming the answerer
///     when the install is local and the row's AnsweredBy is not the signed-in user (compared without case);
///   - expired: 409 with the catalog's expired text at the row's ExpiresAt and the payload;
///   - not_found: 404; not_allowed: 403 (the approver text of the request's kind); bad_answer: 400;
///   - anything else, and any failed read or render: 500 server_error.
ClassMethod AnswerResponse(ref As %String, kind As %String, sessionRef As %String, result As OcuTalon.Core.Msg.AnswerResult) As %Status [ Private ]
{
	Set code = result.Result
	If code = "not_found" Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If code = "not_allowed" Quit ..Fail(403, "not_allowed", $Select(kind = "fix": ..#MESSAGENOTAPPROVER, 1: ..#MESSAGENOTAPPROVERTOOL))
	If code = "bad_answer" Quit ..Fail(400, "bad_answer", ..#MESSAGEBADANSWER)
	If '$ListFind($ListBuild("done", "already_answered", "expired"), code) {
		Quit ..ServerError($SYSTEM.Status.Error(5001, "AnswerOps answered a result that the route doesn't know: "_code))
	}
	Set row = ##class(OcuTalon.Data.Ownership).Approval(ref, sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(row) Quit ..ServerError($SYSTEM.Status.Error(5001, "The answered request can't be read again"))
	Set approval = ..PayloadObject(##class(OcuTalon.Live.Payload.Approval).FromRow(row, sessionRef))
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Do ##class(OcuTalon.Web.TraceLink).Add(approval, .viewer)
	If code = "done" {
		Set %response.ContentType = ..#CONTENTTYPE
		Write {"result": "done", "approval": (approval)}.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	If code = "expired" {
		Set key = "answered.expired"
		Set slots = {"time": (row.ExpiresAt)}
	} Else {
		Set named = ('+##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")) && (row.AnsweredBy '= "") && ($ZConvert(row.AnsweredBy, "U") '= $ZConvert($Username, "U"))
		Set key = "answered.already"_$Select(result.WinnerAction = "reject": "Rejected", 1: "Approved")_$Select(named: "By", 1: "")
		Set slots = {"channel": (result.WinnerChannel), "time": (result.WinnerAt), "user": (row.AnsweredBy)}
	}
	Set message = ##class(OcuTalon.Msg.Catalog).Render(key, slots, "web", .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Quit ..Fail(409, code, message, approval)
}

/// POST /v1/incidents/:ref/dismiss (Story 6.4; AD-1, AD-4, AD-15): the dismissal of an incident, which the route submits and never
/// decides. It never reads the body, and the session is the CSP session's. In order:
///   - the session (Ownership.SessionRef) and the incident's visibility (Ownership.Incident): a failed read is 500 server_error, and an
///     incident the session can't see is 404 not_found, before anything is submitted;
///   - Commands.Submit of an OcuTalon.Msg.Command.Dismiss (the incident's Ref, the session's Ref) with origin web_user, which reaches
///     IncidentManager through CommandsIn, synchronously; an error status is 500 server_error;
///   - the answer: Ok is 200 {"result":"done"}; not_built is 501 not_built; not_found is 404; failed, unknown_command and not_allowed are
///     500 server_error; any other outcome is the owner's refusal, 409 not_dismissible with the owner's Message, else MESSAGENOTDISMISSIBLE.
ClassMethod DismissIncident(ref As %String) As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set row = ##class(OcuTalon.Data.Ownership).Incident(ref, sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(row) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set command = ##class(OcuTalon.Msg.Command.Dismiss).%New()
	Set command.IncidentRef = row.Ref
	Set command.SessionRef = sessionRef
	Kill row
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	If result.Ok {
		Set %response.ContentType = ..#CONTENTTYPE
		Write {"result": "done"}.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	Set outcome = result.Outcome
	If outcome = "not_built" Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
	If outcome = "not_found" Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If $ListFind($ListBuild("failed", "unknown_command", "not_allowed"), outcome) {
		Quit ..ServerError($SYSTEM.Status.Error(5001, "The dismissal was answered "_outcome))
	}
	Quit ..Fail(409, "not_dismissible", $Select(result.Message '= "": result.Message, 1: ..#MESSAGENOTDISMISSIBLE))
}

/// POST /v1/guide/markers: the page's UI-only marker (AD-1). With demo mode off the answer is 404 not_found before the body is
/// read. The body is a JSON object whose marker is the string trace_opened or run_again; anything else is 400 bad_marker and
/// nothing is written. A valid marker is written to the signed-in session's GuideState (trace_opened sets the flag, run_again
/// starts the next epoch), the guide is refreshed (a guide.state event follows a change) and the answer is 200 with the guide
/// view that /state carries, with its trace URL. A session that can't be read, a marker that can't be written and a refresh that fails are 500
/// server_error.
ClassMethod GuideMarkers() As %Status
{
	If '##class(OcuTalon.Demo.Guide).DemoOn() Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If '..MarkerBody(.marker) Quit ..Fail(400, "bad_marker", ..#MESSAGEBADMARKER)
	Set session = ..CurrentSession(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If marker = "trace_opened" {
		Set sc = ##class(OcuTalon.Data.GuideState).TraceOpened(session.Ref)
	} Else {
		Set sc = ##class(OcuTalon.Data.GuideState).RunAgain(session.Ref)
	}
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set sc = ##class(OcuTalon.Live.Publish).RefreshGuide(session.Ref, .guide)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(guide) Quit ..ServerError($SYSTEM.Status.Error(5001, "The guide could not be computed"))
	Set answer = ..PayloadObject(guide)
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Do ##class(OcuTalon.Web.TraceLink).Add(answer, .viewer)
	Set %response.ContentType = ..#CONTENTTYPE
	Write answer.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// The marker of the request body, and 1 when it is a valid one: a JSON object whose marker is the string trace_opened or
/// run_again (other members are ignored). Otherwise 0, with the marker empty.
ClassMethod MarkerBody(Output marker As %String) As %Boolean [ Private ]
{
	Set marker = ""
	Try {
		Set body = ##class(%DynamicAbstractObject).%FromJSON(..BodyText())
	} Catch {
		Set body = ""
	}
	If '$IsObject(body) || 'body.%IsA("%Library.DynamicObject") Quit 0
	If body.%GetTypeOf("marker") '= "string" Quit 0
	Set value = body.marker
	If (value '= "trace_opened") && (value '= "run_again") Quit 0
	Set marker = value
	Quit 1
}

/// Every route whose story hasn't shipped: 501 not_built. arg is the route's :ref or :name.
ClassMethod NotBuilt(arg As %String = "") As %Status
{
	Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
}

/// The pairing routes: 404 while the release doesn't include Telegram, otherwise 501 until Story 10.3.
ClassMethod Pairing() As %Status
{
	If '##class(OcuTalon.Channel.Telegram.In).Included() Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
}

/// The snapshot of a session, keys in this order: the version, the instance zone, the session's epoch, each stream's
/// last Seq (read before any section, so that every change after the cursors is an event the page will apply), the chat
/// and the rail (read through Ownership: the chat holds the newest CHATMAX of the session's turns, visible noticed
/// incidents and web notice cards merged by time, oldest first; the rail its pending approval requests, checks, pending
/// reminders and newest decisions), the signed-in user (the session row's, never the client's), the booleans onlineDemo and demoMode, models:
/// the display names of the triage, diagnosis and chat agents' models, telegram: whether the release includes Telegram
/// and the session's pairing, status: the active status conditions, and, only while demo mode is on, phone: the session's
/// newest PHONEMAX simulated-phone messages, oldest first, mailbox: the session's newest MAILMAX simulated-mailbox emails,
/// oldest first, each the mailbox payload plus, when the session has a decide decision of the email's Item, the member
/// decision (its payload), and last guide: the guide that Demo.Guide.Compute derives.
/// instanceStream is the stream reported as instance: Live.Publish's instance stream unless the caller names another. A read that fails throws.
ClassMethod StateBody(session As OcuTalon.Data.Session, instanceStream As %String = {##class(OcuTalon.Live.Publish).#INSTANCE}) As %DynamicObject
{
	Set streams = {
		"session": (##class(OcuTalon.Live.Publish).LastSeq(session.Ref)),
		"instance": (##class(OcuTalon.Live.Publish).LastSeq(instanceStream))
	}
	Set sessionRef = session.Ref
	Set chat = ..ChatItems(sessionRef)
	Set rail = ..RailBody(sessionRef)
	Set pairing = ##class(OcuTalon.Data.Ownership).Pairing(sessionRef, .sc)
	Do ..Check(sc)

	Set body = {
		"version": (..Version()),
		"instanceZone": (##class(OcuTalon.Data.Time).Zone()),
		"epoch": (session.Epoch),
		"streams": (streams),
		"chat": (chat),
		"rail": (rail),
		"user": (session.IrisUser)
	}
	Do body.%Set("onlineDemo", ##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1, "boolean")
	Do body.%Set("demoMode", ##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Install.Step.Demo).#MODEKEY) = "1", "boolean")
	Set body.models = {
		"triage": (..ModelName(..ResolveModel("TriageAgent"))),
		"diagnosis": (..ModelName(..ResolveModel("DiagnosisAgent"))),
		"chat": (..ModelName(..ResolveModel("ChatAgent")))
	}
	Set telegram = {"included": false, "state": "off", "botUserName": "", "paired": false, "displayName": "", "pausedUntil": ""}
	Do telegram.%Set("included", ##class(OcuTalon.Channel.Telegram.In).Included(), "boolean")
	If $IsObject(pairing) {
		Do telegram.%Set("paired", 1, "boolean")
		Set telegram.displayName = pairing.DisplayName
	}
	Set body.telegram = telegram
	Set body.status = ##class(OcuTalon.Live.Payload.Status).Active(sessionRef)
	If body.demoMode {
		Set rows = ##class(OcuTalon.Data.Ownership).RecentPhone(sessionRef, ..#PHONEMAX, .sc)
		Do ..Check(sc)
		Set phone = []
		For i = rows.Count():-1:1 Do phone.%Push(..PayloadObject(##class(OcuTalon.Live.Payload.Phone).FromRow(rows.GetAt(i))))
		Set body.phone = phone
		Set body.mailbox = ..MailboxItems(sessionRef)
		Set body.guide = ..PayloadObject(##class(OcuTalon.Demo.Guide).Compute(sessionRef))
	}
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Do ##class(OcuTalon.Web.TraceLink).Add(body, .viewer)
	Quit body
}

/// The simulated mailbox: the session's newest MAILMAX emails, oldest first, each the Mailbox payload object plus decision when
/// the session has a decide decision for the email's ItemId. A read that fails throws.
ClassMethod MailboxItems(sessionRef As %String) As %DynamicArray [ Private ]
{
	Set rows = ##class(OcuTalon.Data.Ownership).RecentMail(sessionRef, ..#MAILMAX, .sc)
	Do ..Check(sc)
	Set mailbox = []
	For i = rows.Count():-1:1 {
		Set row = rows.GetAt(i)
		Set entry = ..PayloadObject(##class(OcuTalon.Live.Payload.Mailbox).FromRow(row))
		If row.ItemId '= "" {
			Set decision = ##class(OcuTalon.Data.Ownership).DecisionOfItem(row.ItemId, sessionRef, .sc)
			Do ..Check(sc)
			If $IsObject(decision) Set entry.decision = ..PayloadObject(##class(OcuTalon.Live.Payload.Decision).FromRow(decision))
		}
		Do mailbox.%Push(entry)
	}
	Quit mailbox
}

/// The chat: the newest CHATMAX of the session's turns, its visible noticed incidents and its web notice cards (the tell-now
/// and reminder cards that WebChatOut kept, DW-62), as live items ({"type", "payload"}), oldest first. The three reads are
/// newest first and at most CHATMAX, so the newest CHATMAX of the three together are among them. They are merged by time (a
/// turn's CreatedAt, an incident's NoticedAt, a card's RecordedAt), at the same time a turn before an incident before a
/// card, then by row ID; the merge is walked from its newest end and the entries kept are pushed oldest first.
ClassMethod ChatItems(sessionRef As %String) As %DynamicArray [ Private ]
{
	Kill merged
	Set turns = ##class(OcuTalon.Data.Ownership).RecentTurns(sessionRef, ..#CHATMAX, .sc)
	Do ..Check(sc)
	For i = 1:1:turns.Count() {
		Set turn = turns.GetAt(i)
		Set merged("T"_turn.CreatedAt, 0, turn.%Id()) = {"type": "chat.message", "payload": (..PayloadObject(##class(OcuTalon.Live.Payload.ChatMessage).FromRow(turn)))}
	}
	Set incidents = ##class(OcuTalon.Data.Ownership).RecentIncidents(sessionRef, ..#CHATMAX, .sc)
	Do ..Check(sc)
	For i = 1:1:incidents.Count() {
		Set incident = incidents.GetAt(i)
		Set merged("T"_incident.NoticedAt, 1, incident.%Id()) = {"type": "incident", "payload": (..PayloadObject(##class(OcuTalon.Live.Payload.Incident).FromRow(incident)))}
	}
	Set notices = ##class(OcuTalon.Data.Ownership).RecentNotices(sessionRef, ..#CHATMAX, .sc)
	Do ..Check(sc)
	For i = 1:1:notices.Count() {
		Set notice = notices.GetAt(i)
		Set merged("T"_notice.RecordedAt, 2, notice.%Id()) = {"type": "notification", "payload": (..PayloadObject(##class(OcuTalon.Live.Payload.Notification).FromRow(notice)))}
	}
	Kill newest
	Set kept = 0
	Set time = ""
	For {
		Set time = $Order(merged(time), -1)
		Quit:(time="")||(kept>=..#CHATMAX)
		Set rank = ""
		For {
			Set rank = $Order(merged(time, rank), -1)
			Quit:(rank="")||(kept>=..#CHATMAX)
			Set id = ""
			For {
				Set id = $Order(merged(time, rank, id), -1, item)
				Quit:(id="")||(kept>=..#CHATMAX)
				Set kept = kept + 1
				Set newest(kept) = item
			}
		}
	}
	Set chat = []
	For i = kept:-1:1 Do chat.%Push(newest(i))
	Quit chat
}

/// The rail: the session's pending approval requests, its background checks, its pending reminders and its 20 newest
/// decisions, each as the payload object of its type.
ClassMethod RailBody(sessionRef As %String) As %DynamicObject [ Private ]
{
	Set rail = {"approvals": [], "checks": [], "reminders": [], "decisions": []}
	Set rows = ##class(OcuTalon.Data.Ownership).Approvals(sessionRef, .sc)
	Do ..Check(sc)
	For i = 1:1:rows.Count() Do rail.approvals.%Push(..PayloadObject(##class(OcuTalon.Live.Payload.Approval).FromRow(rows.GetAt(i), sessionRef)))
	Set rows = ##class(OcuTalon.Data.Ownership).Checks(sessionRef, .sc)
	Do ..Check(sc)
	For i = 1:1:rows.Count() Do rail.checks.%Push(..PayloadObject(##class(OcuTalon.Live.Payload.Check).FromRow(rows.GetAt(i))))
	Set rows = ##class(OcuTalon.Data.Ownership).Reminders(sessionRef, .sc)
	Do ..Check(sc)
	For i = 1:1:rows.Count() Do rail.reminders.%Push(..PayloadObject(##class(OcuTalon.Live.Payload.Reminder).FromRow(rows.GetAt(i))))
	Set rows = ##class(OcuTalon.Data.Ownership).Decisions(sessionRef, 20, .sc)
	Do ..Check(sc)
	For i = 1:1:rows.Count() Do rail.decisions.%Push(..PayloadObject(##class(OcuTalon.Live.Payload.Decision).FromRow(rows.GetAt(i))))
	Quit rail
}

/// The JSON object a payload object exports, the same shape the live event stores.
ClassMethod PayloadObject(payload As %RegisteredObject) As %DynamicObject [ Private ]
{
	Do ..Check(payload.%JSONExportToString(.json))
	Quit ##class(%DynamicObject).%FromJSON(json)
}

/// The session that the CSP session resolves to, opened. sc is an error status when the session can't be resolved or
/// opened, which the route answers as a 500.
ClassMethod CurrentSession(Output sc As %Status) As OcuTalon.Data.Session [ Private ]
{
	Set ref = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ""
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	If '$IsObject(session) {
		Set sc = $SYSTEM.Status.Error(5001, "The session could not be opened")
		Quit ""
	}
	Quit session
}

/// Throws the error of a status that is not OK.
ClassMethod Check(sc As %Status) [ Private ]
{
	If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
}

/// The display name of a model id: "Claude Haiku 5.5" for claude-haiku-5-5 and "Claude Sonnet 5.5" for
/// claude-sonnet-5-5. Any other id is returned as it is, and "" stays "". The table is Live.Payload.Decision's.
ClassMethod ModelName(id As %String) As %String
{
	Quit ##class(OcuTalon.Live.Payload.Decision).ModelName(id)
}

/// The model that an agent's runner item of the production uses (AD-7), "" when none resolves.
ClassMethod ResolveModel(item As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Bridge.Operation.AgentRunner).ResolveModel(item, ##class(OcuTalon.Install.Step.Production).#PRODUCTION)
}

/// The events after the two cursors: the session's own stream first, then the instance stream, each in Seq order
/// and at most MAXEVENTS long, with the session's epoch. instanceStream is the stream served as instance:
/// Live.Publish's instance stream unless the caller names another.
ClassMethod EventsBody(session As OcuTalon.Data.Session, after As %Integer, afterInstance As %Integer, instanceStream As %String = {##class(OcuTalon.Live.Publish).#INSTANCE}) As %DynamicObject
{
	Set events = ##class(OcuTalon.Live.Event).Since(session.Ref, after, ##class(OcuTalon.Live.Event).#MAXEVENTS, "session")
	Set instance = ##class(OcuTalon.Live.Event).Since(instanceStream, afterInstance, ##class(OcuTalon.Live.Event).#MAXEVENTS, "instance")
	Set iterator = instance.%GetIterator()
	While iterator.%GetNext(, .event) {
		Do events.%Push(event)
	}
	Set body = {"epoch": (session.Epoch), "events": (events)}
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Do ##class(OcuTalon.Web.TraceLink).Add(body, .viewer)
	Quit body
}

/// The code of the first browser-envelope rule that the request breaks, "" when it keeps them all. GET, HEAD and
/// OPTIONS are exempt. Otherwise the rules apply in this order:
///   - not_json: the Content-Type isn't application/json (parameters such as the charset are allowed);
///   - no_request_header: X-OcuTalon-Request isn't 1;
///   - wrong_origin: Origin isn't the request's own origin, the scheme and Host of the request, compared without
///     regard to case. secure is 1 for an HTTPS connection.
ClassMethod EnvelopeError(method As %String, contentType As %String, header As %String, origin As %String, host As %String, secure As %Boolean) As %String
{
	If $ListFind($ListBuild("GET", "HEAD", "OPTIONS"), $ZConvert(method, "U")) Quit ""
	If $ZConvert($ZStrip($Piece(contentType, ";", 1), "<>W"), "L") '= "application/json" Quit "not_json"
	If $ZStrip(header, "<>W") '= 1 Quit "no_request_header"
	Set expected = $Select(secure: "https", 1: "http")_"://"_host
	If (origin = "") || ($ZConvert($ZStrip(origin, "<>W"), "L") '= $ZConvert(expected, "L")) Quit "wrong_origin"
	Quit ""
}

/// Writes the status line and the error body {"error": {"code", "message"}}, followed by "approval" when a payload object is given.
/// status is the number, 400 to 501.
ClassMethod Fail(status As %Integer, code As %String, message As %String, approval As %DynamicObject = "") As %Status
{
	Set %response.ContentType = ..#CONTENTTYPE
	Set %response.Status = $Case(status,
		400: ..#HTTP400BADREQUEST,
		401: ..#HTTP401UNAUTHORIZED,
		403: ..#HTTP403FORBIDDEN,
		404: ..#HTTP404NOTFOUND,
		405: ..#HTTP405METHODNOTALLOWED,
		409: ..#HTTP409CONFLICT,
		500: ..#HTTP500INTERNALSERVERERROR,
		501: ..#HTTP501NOTIMPLEMENTED,
		: status)
	Set body = ..ErrorBody(code, message)
	If $IsObject(approval) Set body.approval = approval
	Write body.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// The version of the installed IPM module, "" where IPM or the module is absent.
ClassMethod Version() As %String
{
	Set version = ""
	Try {
		Set version = $ClassMethod("%IPM.Storage.Module", "NameOpen", "ocutalon").VersionString
	} Catch {
		Set version = ""
	}
	Quit version
}

/// The error object of a code and message.
ClassMethod ErrorBody(code As %String, message As %String) As %DynamicObject [ Private ]
{
	Quit {"error": {"code": (code), "message": (message)}}
}

/// The text that goes with an envelope error code.
ClassMethod EnvelopeMessage(code As %String) As %String [ Private ]
{
	Quit $Case(code, "not_json": ..#MESSAGENOTJSON, "no_request_header": ..#MESSAGENOHEADER, : ..#MESSAGEWRONGORIGIN)
}

/// 1 when value is a whole number of zero or more, in at most 15 digits.
ClassMethod IsCursor(value As %String) As %Boolean [ Private ]
{
	Quit (value ? 1.15N)
}

}
