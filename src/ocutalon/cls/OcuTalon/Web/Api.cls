/// The REST surface of OcuTalon at /ocutalon/api (AD-13): JSON, versioned under /v1, one CSP session shared
/// with /ocutalon and the trace applications.
///   - GET /v1/state is the snapshot and GET /v1/events the poll (AD-12); POST /v1/session/end signs out; POST /v1/messages
///     takes the page's message, {clientId, text, fromGuide}, hands it to WebChatIn through the production (AD-1, AD-30) and
///     answers 202 {clientId} (a repeat of a clientId included) or 400 bad_message for any other body. Every other
///     route of the release answers 501 not_built until its story ships, and the pairing routes answer 404 while
///     Telegram is not included. The two routes that name a record (approvals/:ref/answer, incidents/:ref/dismiss)
///     answer 404 first for a ref the session can't see. The snapshot also tells the page who is signed in, which mode
///     the instance runs in (onlineDemo, demoMode), the display names of the models its agents use, the Telegram block
///     and the active status conditions.
///   - A request without a session is answered 401 signed_out with no WWW-Authenticate header, so that no browser
///     opens its own password prompt; the public superclass OcuTalon.Web.Public.ApiBase does that, because the
///     answer comes before any role exists. A signed-in user without the OcuTalon user role is answered 403
///     no_role, and the session stays open for the trace applications.
///   - A state-changing call (any method but GET, HEAD and OPTIONS) needs Content-Type: application/json, the
///     header X-OcuTalon-Request: 1 and an Origin that is the request's own origin (AD-13).
///   - No call takes a SessionRef from the client (AD-4): the session is the one that OcuTalon.Data.Ownership.SessionRef
///     resolves from the CSP session, and every record is read through Ownership.
///   - Every error is {"error": {"code", "message"}} in plain English.
Class OcuTalon.Web.Api Extends OcuTalon.Web.Public.ApiBase
{

Parameter UseSession = 1;

Parameter HandleCorsRequest = 0;

Parameter HTTP501NOTIMPLEMENTED = "501 Not Implemented";

/// The most entries the snapshot's chat holds: the newest, oldest first (DW-65).
Parameter CHATMAX = 100;

Parameter MESSAGEBADCURSOR = "The after and afterInstance values must be whole numbers of zero or more.";

Parameter MESSAGENOTJSON = "OcuTalon refused this request because it wasn't sent as JSON.";

Parameter MESSAGENOHEADER = "OcuTalon refused this request because it didn't come from the OcuTalon page.";

Parameter MESSAGEWRONGORIGIN = "OcuTalon refused this request because it came from another site.";

Parameter MESSAGEBADMESSAGE = "A message needs a clientId and some text.";

Parameter MESSAGENOTFOUND = "OcuTalon has nothing at this address.";

Parameter MESSAGENOTALLOWED = "This address doesn't accept that kind of request.";

Parameter MESSAGESERVERERROR = "Something went wrong inside OcuTalon. Try again.";

Parameter MESSAGENOTBUILT = "This part of OcuTalon isn't built yet.";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/v1/state" Method="GET" Call="State"/>
<Route Url="/v1/events" Method="GET" Call="Events"/>
<Route Url="/v1/messages" Method="POST" Call="Messages"/>
<Route Url="/v1/approvals/:ref/answer" Method="POST" Call="AnswerApproval"/>
<Route Url="/v1/incidents/:ref/dismiss" Method="POST" Call="DismissIncident"/>
<Route Url="/v1/demo/break-feed" Method="POST" Call="NotBuilt"/>
<Route Url="/v1/mailbox/incoming" Method="POST" Call="NotBuilt"/>
<Route Url="/v1/mailbox/samples/:name" Method="POST" Call="NotBuilt"/>
<Route Url="/v1/guide/markers" Method="POST" Call="NotBuilt"/>
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

/// POST /v1/approvals/:ref/answer: 404 not_found for a request the session can't see (Ownership.Approval), and 501
/// not_built for one it can see, until the story that answers requests ships.
ClassMethod AnswerApproval(ref As %String) As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set row = ##class(OcuTalon.Data.Ownership).Approval(ref, sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	If '$IsObject(row) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
}

/// POST /v1/incidents/:ref/dismiss: 404 not_found for an incident the session can't see (Ownership.Incident), and 501
/// not_built for one it can see, until the story that dismisses incidents ships.
ClassMethod DismissIncident(ref As %String) As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set row = ##class(OcuTalon.Data.Ownership).Incident(ref, sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	If '$IsObject(row) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
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
/// and the rail (read through Ownership: the chat holds the newest CHATMAX of the session's turns and visible noticed
/// incidents merged by time, oldest first; the rail its pending approval requests, checks, pending reminders and newest
/// decisions), the signed-in user (the session row's, never the client's), the booleans onlineDemo and demoMode, models:
/// the display names of the triage, diagnosis and chat agents' models, telegram: whether the release includes Telegram
/// and the session's pairing, and status: the active status conditions. instanceStream is the stream reported as
/// instance: Live.Publish's instance stream unless the caller names another. A read that fails throws.
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
	Quit body
}

/// The chat: the newest CHATMAX of the session's turns and its visible noticed incidents, as live items ({"type",
/// "payload"}), oldest first. Both reads are newest first and at most CHATMAX, so the newest CHATMAX of the two together
/// are among them. They are merged by time (a turn's CreatedAt, an incident's NoticedAt), a turn before an incident of the
/// same time, then by row ID; the merge is walked from its newest end and the entries kept are pushed oldest first.
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
	For i = 1:1:rows.Count() Do rail.approvals.%Push(..PayloadObject(##class(OcuTalon.Live.Payload.Approval).FromRow(rows.GetAt(i))))
	Set rows = ##class(OcuTalon.Data.Ownership).Checks(sessionRef, .sc)
	Do ..Check(sc)
	For i = 1:1:rows.Count() Do rail.checks.%Push(..PayloadObject(..CheckView(rows.GetAt(i))))
	Set rows = ##class(OcuTalon.Data.Ownership).Reminders(sessionRef, .sc)
	Do ..Check(sc)
	For i = 1:1:rows.Count() Do rail.reminders.%Push(..PayloadObject(##class(OcuTalon.Live.Payload.Reminder).FromRow(rows.GetAt(i))))
	Set rows = ##class(OcuTalon.Data.Ownership).Decisions(sessionRef, 20, .sc)
	Do ..Check(sc)
	For i = 1:1:rows.Count() Do rail.decisions.%Push(..PayloadObject(##class(OcuTalon.Live.Payload.Decision).FromRow(rows.GetAt(i))))
	Quit rail
}

/// The check payload of a background check row. Live.Payload.Check is Lane A's, so this builds it without a FromRow
/// of its own until the story that publishes the check event adds one. stopped has no source in the row, and the
/// trace is the latest run's, in the watched production's namespace.
ClassMethod CheckView(row As OcuTalon.Data.BackgroundCheck) As OcuTalon.Live.Payload.Check [ Private ]
{
	Set payload = ##class(OcuTalon.Live.Payload.Check).%New()
	Set payload.Ref = row.Ref
	Set payload.Kind = row.Kind
	Set payload.Namespace = row.Namespace
	Set payload.Production = row.Production
	Set payload.DisplayName = row.DisplayName
	Set payload.NextDueAt = row.NextDueAt
	Set payload.LastRunAt = row.LastRunAt
	Set payload.Result = row.Result
	Set payload.Finding = row.Finding
	If row.LastRunHeaderId '= "" {
		Set payload.TraceHeaderId = row.LastRunHeaderId
		Set payload.TraceNamespace = row.Namespace
	}
	Quit payload
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
	Quit {"epoch": (session.Epoch), "events": (events)}
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

/// Writes the status line and the error body {"error": {"code", "message"}}. status is the number, 400 to 501.
ClassMethod Fail(status As %Integer, code As %String, message As %String) As %Status
{
	Set %response.ContentType = ..#CONTENTTYPE
	Set %response.Status = $Case(status,
		400: ..#HTTP400BADREQUEST,
		401: ..#HTTP401UNAUTHORIZED,
		403: ..#HTTP403FORBIDDEN,
		404: ..#HTTP404NOTFOUND,
		405: ..#HTTP405METHODNOTALLOWED,
		500: ..#HTTP500INTERNALSERVERERROR,
		501: ..#HTTP501NOTIMPLEMENTED,
		: status)
	Write ..ErrorBody(code, message).%ToJSON()
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
