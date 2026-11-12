/// The REST surface of OcuTalon at /ocutalon/api (AD-13): JSON, versioned under /v1, one CSP session shared
/// with /ocutalon and the trace applications.
///   - GET /v1/state is the snapshot and GET /v1/events the poll (AD-12); POST /v1/session/end signs out; POST /v1/messages
///     takes the page's message, {clientId, text, fromGuide}, hands it to WebChatIn through the production (AD-1, AD-30) and
///     answers 202 {clientId} (a repeat of a clientId included) or 400 bad_message for any other body. Every other
///     route of the release that no story has shipped answers 501 not_built. The pairing routes answer 404 not_found while Telegram
///     is not included (OcuTalon.Channel.Telegram.In.Included), before anything else is read; otherwise POST /v1/pairing/code
///     makes a pairing code for the CSP session's session and answers 200 {"code","expiresAt"} (the code is 22 characters, valid for
///     10 minutes, stored only as its hash and replacing the session's earlier code), or 409 not_available when the recorded
///     Telegram state is not on or a pause is set; DELETE /v1/pairing never reads the body and submits an Unpair command for the
///     CSP session through Commands.Submit (origin web_user): 200 {"result":"done"}, also when nothing was paired, 501 not_built for
///     a stub owner and 500 server_error. POST /v1/mailbox/incoming and /v1/mailbox/samples/:name simulate an incoming email: with demo
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
///     Commands.Submit (origin web_user): 200 {"result":"done"}, 409 not_dismissible (IncidentManager's not_allowed, the owner's refusal
///     of a dismissal that the incident's state or its approval request forbids), 501 not_built for a stub owner, 404 not_found and 500
///     server_error.
///     POST /v1/decisions/:ref/got-it (Story 18.4; AD-1, AD-14) marks the session's own tell-now notice as handled: the body {"channel":"phone"}
///     (exactly) is the Simulated phone's press, any other body is the web chat's; it submits a GotIt command through Commands.Submit (origin web_user)
///     and answers 200 {"result":"done","handledAt"} (a second press too, with the first handledAt), 404 not_found for a Decision the session
///     can't see or that is not tell-now (nothing is submitted), 501 not_built and 500 server_error.
///     The settings routes (Story 33.2; AD-13, AD-19) are for OcuTalonAdmin only, and the check is the whole name of the role in $Roles, never %All: a
///     call to /v1/settings or below it from a user without the role is 403 not_admin, answered before the browser envelope, the body and the
///     route. GET /v1/settings answers SettingsOps.Values: {"sections", "bridge", "providers", "instanceZone", "prices"}. Each POST /v1/settings/<section>
///     (budgets, models, daily-digest, time-zone, check-thresholds, demo-mode, channels) takes the section's fields as a JSON
///     object of field to value, submits one SaveSettings command (a SetDemoMode for demo-mode) with origin web_admin, the IRIS user of the call and
///     the CSP session's Ref (AD-4), and answers: Ok 200 {"result":"done","sections"}; a refused value, a missing or unknown field or a body that is not an object 400
///     bad_settings with "fields", the names of the refused fields; not_built 501; step_failed (the demo step failed after the value was written)
///     409 demo_step_failed; not_audited, failed and any other outcome or status 500 server_error.
///     POST /v1/settings/channels (Stories 21.2, 21.6 and 21.3; AD-1, AD-19) connects the mailbox: SaveChannels takes {address, incoming, outgoing, user, signIn,
///     clientId, password, clientSecret}; outgoing, signIn (password, google or microsoft; default password), clientId, password and clientSecret are optional (an absent
///     or empty password or clientSecret keeps the stored one), and the body may not hold origin. With the online demo on it answers 409 not_available
///     (MESSAGENOTAVAILABLE) before it reads the body. A password or clientSecret of more than 256 characters, or that is not a string, is 400 bad_settings naming it and
///     nothing is offered; every other non-empty one is offered to SecretHandoff (in memory; the REST process stores nothing) and only the reference
///     secret://handoff/<name> goes in the SaveSettings command's body, so no secret is in any command, message or log. The body also gets origin, the http or https
///     origin of the request (PageOrigin), from which SettingsOps makes the OAuth2 redirection endpoint. After the submit returns, whatever it answered, every untaken
///     secret is discarded. The answers are those of Answer, with not_available 409.
///     POST /v1/settings/channels/sign-in (Story 21.3; AD-1) takes exactly {"action": "start"|"check"} (anything else is 400 bad_settings with fields ["action"]) and
///     submits one MailSignIn (origin web_admin, the IRIS user of the call, the CSP session's Ref, PageOrigin): start answers 200 {"result":"started","url"}, the address
///     that opens IRIS's authorization flow in a new tab, and check 200 {"result":"checked","signedIn"}; a client that is not registered is 400 bad_settings with
///     fields ["signIn"]; on the online demo it is 409 not_available before the body is read; any other outcome or status is 500 server_error.
///     POST /v1/settings/models takes {"agents", "prices"} (SettingsOps' models section); POST /v1/settings/models/test takes exactly {"agent": string} and submits one
///     TestModel (origin web_admin): Ok 200 {"answered", "seconds", "reason"}; a bad body or an agent that is refused 400 bad_settings with fields ["agent"]; any
///     other outcome or status 500 server_error.
///     POST /v1/settings/daily-digest/send never reads the body and submits one SendDigest (origin web_admin, the CSP session's Ref, a fresh
///     IdempotencyKey): Ok 202 {"result":"sending"}; an error status, no result or any other outcome 500 server_error.
///     The snapshot also tells the page who is signed in, whether that user holds OcuTalonAdmin (admin), which mode
///     the instance runs in (onlineDemo, demoMode), the display names of the models its agents use, the Telegram block
///     and the active status conditions, then, only while demo mode is on, the simulated phone, the simulated mailbox
///     and the guide that Demo.Guide.Compute derives, and, on the online demo only, idleSeconds: the page's idle cap,
///     traceAccount: the read-only Visual Trace account, and the reset fields (resetSoon in status, nextReset last).
///     POST /v1/session/end signs out: on a local install only the CSP session ends; on the online demo it submits an EndSession
///     command for the session (SessionOps.End, through CommandsIn), expires the resume cookie and then signs out, 204; a failed
///     End is 500 server_error, which neither expires the cookie nor signs out, so the session stays resumable (EndSession).
///   - The heartbeat routes (Epic 39; AD-1, AD-4, AD-12, AD-13, AD-19, AD-26; FR-63, FR-66), beside the persona routes, for the CSP session's session
///     only (a sessionRef in a body is ignored). GET /v1/heartbeat answers 200 with SettingsOps.Heartbeat: the person's settings and the public view of
///     their HeartbeatBeat row (the view of the heartbeat event), with traceUrl, the checklist, sample (true only for the online demo's unsaved sample),
///     today ({"checkIns","costUSD"}: the session's heartbeat check-ins and their cost in the daily cap's day), lastFallbackReason (only after a fallback beat)
///     and onlineDemo (boolean); a read that fails is 500 server_error. PUT /v1/heartbeat takes {on (boolean), interval (number), from, to, checklist (strings)} and submits a
///     SetHeartbeat (origin web_user): Ok 200 {"result":"done","message","on","interval","from","to","checklist"} as saved; a body of another shape 400
///     bad_heartbeat and a checklist over the limit 400 bad_checklist, before anything is submitted; bad_on, bad_interval, bad_hours and bad_checklist
///     400 with SettingsOps' message; not_built 501; any other outcome 500 not_saved with the owner's message. POST /v1/heartbeat/run never reads the
///     body and submits a RunHeartbeat (CommandsIn sends it to Checks as a BeatNow): Ok 202 {"result":"sent"}; cooldown, cap, nokey, empty and backoff
///     409 {"error":{"code","message"}} with availableAt beside it when Checks gave one; not_built 501; anything else 500 server_error.
///   - The memory routes (Epic 41; AD-1, AD-4, AD-13, AD-21), for the CSP session's session only, every record read through Ownership: POST /v1/decisions/:ref/noise
///     marks one of the session's own notices as noise. The body is read only for the channel: the exact body {"channel":"phone"} means phone, and any other
///     body or none means web. A decision the session can't see is 404 not_found before anything is submitted; MarkNoise (origin web_user, through
///     Commands.Submit) answers 200 {"result":"done","markedAt"} (a repeat included), 409 too_old when the notice's item is no longer kept, 404 not_found
///     for a decision that cannot be marked, 501 not_built for a stub owner and 500 server_error. GET /v1/memory/precedents answers 200
///     {"precedents":[...]}, the session's own answers newest first, at most 100, each {ref, answeredAt, channel, answeredChannel, summary, outcome,
///     answer}, and never a seeded row. DELETE /v1/memory/precedents/:ref forgets one of them (ForgetPrecedent, origin web_user): 200 {"result":"done"},
///     404 not_found first for a row the session can't see, 501 and 500 as above. GET /v1/memory/notes?day=today|yesterday (today when the day is
///     missing) answers 200 {"day","date","lines"}, with date the instance-zone date YYYY-MM-DD and lines the daily note's lines; any other day is 404 not_found.
///   - The memory item routes (Epic 41, second part; AD-1, AD-4, AD-13, AD-21), for the CSP session's session only: GET /v1/memory/items answers 200
///     {"items":[{ref, text, savedAt, source, pinned}],"total"}. A blank q reads the session's newest 20 memories and their count through Ownership (the signed-in
///     user has no SQL privilege and no search service, AD-13); otherwise q (trimmed and cut at 2,000 characters) is searched by a SearchMemory (a read verb,
///     origin web_user, through SubmitMemory) that MemoryOps answers with the best 5 of the session's own memories, total the number of items. A failed read or search
///     is 500 server_error; a search that has no answer in time is 503 search_busy.
///     (Story 41.13) GET /v1/memory/pinned answers 200 {"items":[{ref, text, savedAt, source, pinned}],"used"}: the session's pinned memories, newest pin first, and the tokens of
///     their core-memory block, both from one ListPinnedMemories (a read verb, origin web_user, through SubmitMemory) that MemoryOps answers; no answer in time is 503 search_busy,
///     anything else that fails 500 server_error. Every 503 search_busy carries the header Retry-After (SEARCHRETRYAFTER seconds). On the online demo a search past the message
///     allowance is 429 allowance with the messages route's body (retryAt, limit), and nothing was searched; the list and the pinned read never count.
///     POST and DELETE /v1/memory/:ref/pin submit PinMemory and UnpinMemory, and DELETE /v1/memory/items/:ref submits ForgetMemory, each with
///     origin web_user through SubmitMemory: Ok is 200 {"result":"done"}; not_found 404; over_cap 409 (a pin or an unpin; 500 for a forget); not_built 501; anything else 500
///     server_error. MemoryOps matches the ref to the session's own rows, so another session's ref is 404 not_found and the row is kept.
///   - The documents routes (Story 34.2; GET and POST /v1/documents, DELETE /v1/documents/:ref) are OcuTalon.Web.Documents', forwarded by
///     the map at the end of the URL map.
///   - The usage route (Story 37.2; GET /v1/usage?days=1|7|30) is OcuTalon.Web.Usage's, forwarded by its own map: the CSP session's own token and cost
///     buckets by local day, agent, channel, model and Estimated, with the request-size limit.
///   - The history routes (Story 25.2; GET /v1/history/decisions?outcome=&channel=&day=&fallback=&page= and GET /v1/history/incidents?page=) are OcuTalon.Web.History's, forwarded
///     by its own map: the CSP session's own decisions, filtered and paged, and the incidents it sees, paged, with the stored summary as text.
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

Parameter HTTP429TOOMANYREQUESTS = "429 Too Many Requests";

/// The most entries the snapshot's chat holds: the newest, oldest first (DW-65).
Parameter CHATMAX = 100;

/// The most simulated-phone messages the snapshot's phone holds: the newest, oldest first.
Parameter PHONEMAX = 100;

/// The most simulated-mailbox emails the snapshot's mailbox holds: the newest, oldest first.
Parameter MAILMAX = 100;

/// The most precedents that GET /v1/memory/precedents lists: the newest.
Parameter PRECEDENTSMAX = 100;

Parameter MESSAGEBADCURSOR = "The after and afterInstance values must be whole numbers of zero or more.";

Parameter MESSAGENOTJSON = "OcuTalon refused this request because it wasn't sent as JSON.";

Parameter MESSAGENOHEADER = "OcuTalon refused this request because it didn't come from the OcuTalon page.";

Parameter MESSAGEWRONGORIGIN = "OcuTalon refused this request because it came from another site.";

Parameter MESSAGEBADMESSAGE = "A message needs a clientId and some text.";

/// The message of the 429 allowance of POST /messages; {limit} is the session's message allowance.
Parameter MESSAGEALLOWANCE = "You've used this session's {limit} messages for the hour.";

/// The message of the 429 email_limit of the mailbox routes.
Parameter MESSAGEEMAILLIMIT = "You've simulated 20 emails this hour.";

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

/// The message of the 403 not_admin of every settings call.
Parameter MESSAGENOTADMIN = "Only OcuTalon admins can open settings.";

/// The message of the 400 bad_settings of a save.
Parameter MESSAGEBADSETTINGS = "Couldn't save. Nothing was changed.";

/// The 409 message of an email save on the online demo (Public text P2).
Parameter MESSAGENOTAVAILABLE = "Email can't be connected on the online demo. Nothing was changed.";

/// The most characters of a mailbox password that the route offers.
Parameter PASSWORDMAX = 256;

/// The message of the 409 demo_step_failed of a demo mode save; {v} is on or off.
Parameter MESSAGEDEMOSTEPFAILED = "Demo mode is set to {v}, but the switch didn't finish. OcuTalon tries again at its next start.";

Parameter MESSAGENOTDISMISSIBLE = "OcuTalon can't dismiss this incident now. Nothing was changed.";

/// The message of the 409 too_old of the noise route.
Parameter MESSAGETOOOLD = "This notice is too old to mark as noise. Nothing was changed.";

/// The message of the 409 over_cap of the pin route.
Parameter MESSAGEOVERCAP = "That would go over the 1,000-token limit. Unpin something first.";

/// The most characters of the search text of GET /v1/memory/items: the length of Data.Memory's Text.
Parameter MEMORYQUERYMAX = 2000;

/// The most memories that a list of GET /v1/memory/items returns.
Parameter MEMORYLISTMAX = 20;

/// The message of the 503 search_busy of the memory search: the search has no answer in time.
Parameter MESSAGESEARCHBUSY = "Search is busy right now. Try again in a moment.";

/// The seconds that the Retry-After header of a 503 search_busy names.
Parameter SEARCHRETRYAFTER = 5;

/// The status line of a 503 answer.
Parameter HTTP503SERVICEUNAVAILABLE = "503 Service Unavailable";

/// The longest Ref of a memory (Data.Memory); a longer one names no memory.
Parameter MEMORYREFMAX = 22;

/// The message of the 409 not_available of the code route while Telegram is not on.
Parameter MESSAGETELEGRAMOFF = "Telegram isn't on in this OcuTalon, so no pairing code was made.";

/// The message of the 409 not_available of the code route while Telegram is paused.
Parameter MESSAGETELEGRAMPAUSED = "Telegram is paused, so no pairing code was made. Try again when the pause ends.";

/// The seconds a pairing code stays valid.
Parameter CODESECONDS = 600;

/// The messages of the 409 answers of POST /v1/heartbeat/run; {time} is the time of availableAt as the catalog shows a message time (Data.Time.ForMessage,
/// with " ET" on the online demo), and a dated time turns the "at" before it into "on".
Parameter MESSAGERUNCOOLDOWN = "You can run it again at {time}.";

Parameter MESSAGERUNCAP = "Today's cost limit has been reached.";

Parameter MESSAGERUNNOKEY = "No model key is set.";

Parameter MESSAGERUNEMPTY = "Your checklist is empty.";

Parameter MESSAGERUNBACKOFF = "The last beat failed, so the next one waits until {time}.";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/v1/state" Method="GET" Call="State"/>
<Route Url="/v1/events" Method="GET" Call="Events"/>
<Route Url="/v1/messages" Method="POST" Call="Messages"/>
<Route Url="/v1/approvals/:ref/answer" Method="POST" Call="AnswerApproval"/>
<Route Url="/v1/incidents/:ref/dismiss" Method="POST" Call="DismissIncident"/>
<Route Url="/v1/decisions/:ref/got-it" Method="POST" Call="GotIt"/>
<Route Url="/v1/demo/break-feed" Method="POST" Call="BreakFeed"/>
<Route Url="/v1/mailbox/incoming" Method="POST" Call="MailboxIncoming"/>
<Route Url="/v1/mailbox/samples/:name" Method="POST" Call="MailboxSample"/>
<Route Url="/v1/guide/markers" Method="POST" Call="GuideMarkers"/>
<Route Url="/v1/session/end" Method="POST" Call="EndSession"/>
<Route Url="/v1/pairing/code" Method="POST" Call="Pairing"/>
<Route Url="/v1/pairing" Method="DELETE" Call="Pairing"/>
<Route Url="/v1/persona" Method="GET" Call="GetPersona"/>
<Route Url="/v1/persona" Method="PUT" Call="PutPersona"/>
<Route Url="/v1/heartbeat" Method="GET" Call="GetHeartbeat"/>
<Route Url="/v1/heartbeat" Method="PUT" Call="PutHeartbeat"/>
<Route Url="/v1/heartbeat/run" Method="POST" Call="RunHeartbeat"/>
<Route Url="/v1/decisions/:ref/noise" Method="POST" Call="MarkNoise"/>
<Route Url="/v1/memory/precedents" Method="GET" Call="Precedents"/>
<Route Url="/v1/memory/precedents/:ref" Method="DELETE" Call="ForgetPrecedent"/>
<Route Url="/v1/memory/notes" Method="GET" Call="Notes"/>
<Route Url="/v1/memory/items" Method="GET" Call="MemoryItems"/>
<Route Url="/v1/memory/pinned" Method="GET" Call="PinnedMemories"/>
<Route Url="/v1/memory/:ref/pin" Method="POST" Call="PinMemory"/>
<Route Url="/v1/memory/:ref/pin" Method="DELETE" Call="UnpinMemory"/>
<Route Url="/v1/memory/items/:ref" Method="DELETE" Call="ForgetMemory"/>
<Route Url="/v1/settings" Method="GET" Call="Settings"/>
<Route Url="/v1/settings/models" Method="POST" Call="SaveModels"/>
<Route Url="/v1/settings/models/test" Method="POST" Call="TestModel"/>
<Route Url="/v1/settings/budgets" Method="POST" Call="SaveBudgets"/>
<Route Url="/v1/settings/channels" Method="POST" Call="SaveChannels"/>
<Route Url="/v1/settings/channels/sign-in" Method="POST" Call="SignInMail"/>
<Route Url="/v1/settings/daily-digest" Method="POST" Call="SaveDailyDigest"/>
<Route Url="/v1/settings/daily-digest/send" Method="POST" Call="SendDigest"/>
<Route Url="/v1/settings/time-zone" Method="POST" Call="SaveTimeZone"/>
<Route Url="/v1/settings/check-thresholds" Method="POST" Call="SaveCheckThresholds"/>
<Route Url="/v1/settings/demo-mode" Method="POST" Call="SaveDemoMode"/>
<Map Prefix="/v1/documents" Forward="OcuTalon.Web.Documents"/>
<Map Prefix="/v1/usage" Forward="OcuTalon.Web.Usage"/>
<Map Prefix="/v1/history" Forward="OcuTalon.Web.History"/>
</Routes>
}

/// The request bodies larger than Web.BodyLimit's default that a route takes (Web.BodyLimit): POST /v1/documents takes a file in base64, up to
/// OcuTalon.Web.Documents' BODYMAX (Test.Web.DocumentsApi TestBodyBounds pins the two equal). The forwarded class declares
/// the same route with the remainder of the path.
XData BodyBounds [ MimeType = application/json ]
{
[
{"method": "POST", "url": "/v1/documents", "bytes": 13985112}
]
}

/// Every request, before the route is matched: the role check first, then, for /v1/settings and below it, the admin check, then the browser
/// envelope, then the body size (Web.BodyLimit). A refusal writes its error and stops the dispatch.
ClassMethod OnPreDispatch(url As %String, method As %String, ByRef continue As %Boolean) As %Status
{
	If '..HasUserRole() {
		Set continue = 0
		Quit ..Fail(403, "no_role", ##class(OcuTalon.Web.Public.Login).#ERRORNOROLE)
	}
	If ..IsSettingsUrl(url) && '..IsAdmin() {
		Set continue = 0
		Quit ..Fail(403, "not_admin", ..#MESSAGENOTADMIN)
	}
	Set code = ..EnvelopeError(%request.Method, %request.ContentType, %request.GetCgiEnv("HTTP_X_OCUTALON_REQUEST"), %request.GetCgiEnv("HTTP_ORIGIN"), %request.GetCgiEnv("HTTP_HOST"), %request.Secure)
	If code '= "" {
		Set continue = 0
		Quit ..Fail(403, code, ..EnvelopeMessage(code))
	}
	If ##class(OcuTalon.Web.BodyLimit).TooLarge($classname(), url, method) {
		Set continue = 0
		Quit ..Fail(##class(OcuTalon.Web.BodyLimit).#HTTP413CONTENTTOOLARGE, "body_too_large", ##class(OcuTalon.Web.BodyLimit).#MESSAGEBODYTOOLARGE)
	}
	Quit $SYSTEM.Status.OK()
}

/// 1 when the signed-in user holds the OcuTalon user role. A test subclass overrides it.
ClassMethod HasUserRole() As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Web.Public.Shell).HasRole()
}

/// The roles of the signed-in user. A test subclass overrides it.
ClassMethod Roles() As %String [ Private ]
{
	Quit $Roles
}

/// 1 when the signed-in user holds OcuTalonAdmin, by its whole name; %All does not count (AD-19), because a holder of %All could grant itself the role.
ClassMethod IsAdmin() As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Core.Admin).Held(..Roles())
}

/// 1 when the URL (below the application) is /v1/settings or below it.
ClassMethod IsSettingsUrl(url As %String) As %Boolean [ Private ]
{
	Set path = $ZConvert($Piece($Get(url), "?", 1), "L")
	Quit (path = "/v1/settings") || ($Extract(path, 1, $Length("/v1/settings/")) = "/v1/settings/")
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
/// On a local or IPM install that is all it does (the durable session stays). On the online demo (onlineDemo on) Sign out ends the
/// OcuTalon session too (AD-4, AD-1): the route resolves the CSP session's session (Ownership.SessionRef) and submits an EndSession
/// command for it through Commands.Submit (origin web_user), which reaches SessionOps.End through CommandsIn, synchronously.
///   - Ok: the resume cookie is expired (SessionEvents.ResumeCookie, the same name and path as the sign-in's), the CSP session signs
///     out, and the answer is 204.
///   - not_built: 501 not_built. Any other outcome or status: 500 server_error, with no cookie change and no sign-out, so the
///     session stays resumable.
///   - A CSP session that no OcuTalon session resolves for (the attach failed at sign-in): the sign-out alone, and 204, with no
///     command.
ClassMethod EndSession() As %Status
{
	If ##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1 {
		Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
		If $SYSTEM.Status.IsOK(sc) {
			Set command = ##class(OcuTalon.Msg.Command.EndSession).%New()
			Set command.SessionRef = sessionRef
			Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
			If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
			If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
			If result.Outcome = "not_built" Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
			If 'result.Ok Quit ..ServerError($SYSTEM.Status.Error(5001, "The session end was answered "_result.Outcome))
			Do ##class(OcuTalon.Web.SessionEvents).ResumeCookie("", ##class(OcuTalon.Web.SessionEvents).#EXPIREDDATE)
		}
	}
	Do %session.Logout(1)
	Set %session.EndSession = 1
	Set %response.Status = ..#HTTP204NOCONTENT
	Quit $SYSTEM.Status.OK()
}

/// POST /v1/messages: the page's message. The body is a JSON object with a clientId (a string of 1 to 128 characters), a text
/// (a string with a non-space character) and fromGuide (true only when it is the JSON true); anything else, a body that is not
/// a JSON object included, is 400 bad_message and nothing is sent. The session is the one that Ownership.SessionRef resolves
/// (AD-4): a sessionRef in the body is ignored. A valid body is handed to WebChatIn (Post), whose JSON output says what became
/// of it (as BreakFeed reads its service's output): an accepted message answers 202 {"clientId"}, a clientId that the session
/// already used included, and a message that the session's allowance refused (the online demo's, AD-20) answers 429
/// {"error": {"code": "allowance", "message"}, "retryAt", "limit"} with the UTC time when the session may send again and the
/// limit. A session that can't be read, a production that can't take the message, an error of WebChatIn (a busy allowance
/// included) and an output that is not a JSON object are 500 server_error.
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
	Set sc = $SYSTEM.Status.OK(), refused = 0
	Try {
		Set answer = ##class(%DynamicAbstractObject).%FromJSON(output)
		If 'answer.%IsA("%Library.DynamicObject") {
			Set sc = $SYSTEM.Status.Error(5001, "WebChatIn answered an output that is not a JSON object")
		} Else {
			Set refused = (answer.refused = 1)
			If refused {
				Set retryAt = answer.retryAt
				Set limit = answer.limit
			}
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If refused Quit ..Fail(429, "allowance", $Replace(..#MESSAGEALLOWANCE, "{limit}", limit), , {"retryAt": (retryAt), "limit": (+limit)})
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

/// Hands the mail to SimMailboxIn and answers from the service's output: 202 {"ref"}, or, for an email that the online demo's
/// limit refused (AD-20), 429 {"error": {"code": "email_limit", "message"}, "retryAt"} with the UTC time when the session may send
/// again. An error, or an output that is not a JSON object with a ref or a refusal with a retryAt, is 500 server_error.
ClassMethod MailAccepted(mail As OcuTalon.Channel.SimMailbox.Mail) As %Status [ Private ]
{
	Set sc = ..Mail(mail, .output)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set answer = ##class(%DynamicAbstractObject).%FromJSON(output)
		If answer.refused = 1 {
			Set retryAt = answer.retryAt
			If (answer.%GetTypeOf("retryAt") '= "string") || (retryAt = "") Set sc = $SYSTEM.Status.Error(5001, "SimMailboxIn refused the email with no retryAt")
		} Else {
			Set ref = answer.ref
			If (answer.%GetTypeOf("ref") '= "string") || (ref = "") Set sc = $SYSTEM.Status.Error(5001, "SimMailboxIn answered no ref")
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If answer.refused = 1 Quit ..Fail(429, "email_limit", ..#MESSAGEEMAILLIMIT, , {"retryAt": (retryAt)})
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
	If code = "not_allowed" Quit ..Fail(403, "not_allowed", $Select(kind = "fix": ..#MESSAGENOTAPPROVER, kind = "setting": ..#MESSAGENOTAPPROVERSETTING, 1: ..#MESSAGENOTAPPROVERTOOL))
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
///   - the answer: Ok is 200 {"result":"done"}; not_built is 501 not_built; not_found is 404; failed and unknown_command are 500 server_error;
///     not_allowed, the owner's refusal, is 409 not_dismissible with MESSAGENOTDISMISSIBLE (the owner's Message is developer text, and the
///     words a user sees are the channel's). Any other outcome, which the real IncidentManager never gives to a dismissal, is 409
///     not_dismissible with its own Message, or MESSAGENOTDISMISSIBLE when it has none.
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
	If $ListFind($ListBuild("failed", "unknown_command"), outcome) {
		Quit ..ServerError($SYSTEM.Status.Error(5001, "The dismissal was answered "_outcome))
	}
	If outcome = "not_allowed" Quit ..Fail(409, "not_dismissible", ..#MESSAGENOTDISMISSIBLE)
	Quit ..Fail(409, "not_dismissible", $Select(result.Message '= "": result.Message, 1: ..#MESSAGENOTDISMISSIBLE))
}

/// POST /v1/decisions/:ref/got-it (Story 18.4; AD-1, AD-4, AD-14): the press of Got it on a tell-now notice, which the route submits and
/// never decides (SessionOps does: the first press wins). The notice's Ref is its Decision's Ref. In order:
///   - the session (Ownership.SessionRef) and the Decision (Ownership.Decision) of that session, which must be tell-now: a failed read is 500
///     server_error, and any other Decision is 404 not_found, before anything is submitted;
///   - the channel: phone for the exact body {"channel":"phone"}, else web (an unreadable body too);
///   - Commands.Submit of an OcuTalon.Msg.Command.GotIt (the Ref, the channel) with origin web_user, for the session; an error status is 500 server_error;
///   - the answer: handled and already_handled are 200 {"result":"done","handledAt"} with Handled.Marked of the Ref; not_found is 404; not_built is
///     501 not_built; any other outcome is 500 server_error.
ClassMethod GotIt(ref As %String) As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set decision = ##class(OcuTalon.Data.Ownership).Decision(ref, sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(decision) || (decision.Outcome '= "tellnow") Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set command = ##class(OcuTalon.Msg.Command.GotIt).%New()
	Set command.Ref = decision.Ref
	Set command.SessionRef = sessionRef
	Set command.Channel = ..GotItChannel()
	Kill decision
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	If result.Ok {
		Set %response.ContentType = ..#CONTENTTYPE
		Write {"result": "done", "handledAt": (##class(OcuTalon.Data.Handled).Marked(command.Ref))}.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	Set outcome = result.Outcome
	If outcome = "not_found" Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If outcome = "not_built" Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
	Quit ..ServerError($SYSTEM.Status.Error(5001, "The Got it was answered "_outcome))
}

/// The channel of a Got it press: phone when the body is exactly the object {"channel":"phone"}, else web.
ClassMethod GotItChannel() As %String [ Private ]
{
	Set channel = "web"
	Try {
		Set body = ##class(%DynamicAbstractObject).%FromJSON(..BodyText())
		If $IsObject(body) && body.%IsA("%Library.DynamicObject") && (body.%Size() = 1) && (body.%GetTypeOf("channel") = "string") && (body.channel = "phone") Set channel = "phone"
	} Catch exception {
		Set channel = "web"
	}
	Quit channel
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

/// GET /v1/settings: the settings page's values (SettingsOps.Values). The admin check was made before the route.
ClassMethod Settings() As %Status
{
	Try {
		Set body = ##class(OcuTalon.Core.SettingsOps).Values()
	} Catch exception {
		Return ..ServerError(exception.AsStatus())
	}
	Set %response.ContentType = ..#CONTENTTYPE
	Write body.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// POST /v1/settings/budgets: see SaveSection.
ClassMethod SaveBudgets() As %Status
{
	Quit ..SaveSection("budgets")
}

/// POST /v1/settings/daily-digest: see SaveSection.
ClassMethod SaveDailyDigest() As %Status
{
	Quit ..SaveSection("daily-digest")
}

/// POST /v1/settings/time-zone: see SaveSection.
ClassMethod SaveTimeZone() As %Status
{
	Quit ..SaveSection("time-zone")
}

/// POST /v1/settings/check-thresholds: see SaveSection.
ClassMethod SaveCheckThresholds() As %Status
{
	Quit ..SaveSection("check-thresholds")
}

/// POST /v1/settings/channels (Stories 21.2 and 21.3): see the class description. On the online demo it answers 409 not_available before the body is read. The
/// body is a JSON object, and anything else is 400 bad_settings with no field and nothing offered or submitted. A body with an origin member is 400 with fields
/// ["origin"]. A password or clientSecret that is present but not a JSON string, or a string of more than PASSWORDMAX characters, is 400 bad_settings
/// with the field named, nothing offered or submitted, so that no secret value ever reaches the command. Any other non-empty string secret
/// is offered to SecretHandoff and replaced in the body by its reference; the SaveSettings command (slug channels, origin web_admin, the IRIS user of
/// the call, the CSP session's Ref) carries only those references and the request's origin. Whatever the submit answers, or throws, each reference is then taken with
/// no wait and the value discarded (a Take of a reference that SettingsOps already took fails harmlessly). The answers are those of Answer.
ClassMethod SaveChannels() As %Status
{
	If ##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1 Quit ..Fail(409, "not_available", ..#MESSAGENOTAVAILABLE)
	If '..SettingsBody(.body) Quit ..BadSettings([])
	If body.%IsDefined("origin") Quit ..BadSettings(["origin"])
	Set bad = []
	For name = "password", "clientSecret" {
		Set type = body.%GetTypeOf(name)
		If ((type '= "string") && (type '= "unassigned")) || ((type = "string") && ($Length(body.%Get(name)) > ..#PASSWORDMAX)) Do bad.%Push(name)
	}
	If bad.%Size() Quit ..BadSettings(bad)
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set uris = ""
	Try {
		For name = "password", "clientSecret" {
			Set secret = $Select(body.%GetTypeOf(name) = "string": body.%Get(name), 1: "")
			If secret = "" Continue
			Set sc = ##class(OcuTalon.Core.SecretHandoff).Put(secret, .uri)
			Kill secret
			If $SYSTEM.Status.IsError(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
			Set uris = uris_$ListBuild(uri)
			Do body.%Set(name, uri, "string")
		}
		Do body.%Set("origin", ..PageOrigin(), "string")
		Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
		Set command.Slug = "channels"
		Set command.Changes = body.%ToJSON()
		Set command.ActingUser = $USERNAME
		Set command.SessionRef = sessionRef
		Set sc = ..SubmitChannels(command, .result)
	} Catch exception {
		Kill secret
		Set sc = exception.AsStatus()
	}
	Set position = 0
	While $ListNext(uris, position, one) {
		Do ##class(OcuTalon.Core.SecretHandoff).Take(one, .discard, 0)
		Kill discard
	}
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Quit ..Answer(result, "")
}

/// POST /v1/settings/channels/sign-in (Story 21.3): see the class description. The online demo answers 409 not_available before the body is read; the body is
/// exactly {"action": "start" or "check"}. One MailSignIn is submitted through Commands.Submit with origin web_admin.
ClassMethod SignInMail() As %Status
{
	If ##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1 Quit ..Fail(409, "not_available", ..#MESSAGENOTAVAILABLE)
	If '..SettingsBody(.body) || (body.%Size() '= 1) || (body.%GetTypeOf("action") '= "string") || ((body.action '= "start") && (body.action '= "check")) Quit ..BadSettings(["action"])
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set command = ##class(OcuTalon.Msg.Command.MailSignIn).%New()
	Set command.Action = body.action
	Set command.PageOrigin = ..PageOrigin()
	Set command.ActingUser = $USERNAME
	Set command.SessionRef = sessionRef
	Set sc = ..SubmitSignIn(command, .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	If result.Outcome = "refused" {
		Try {
			Set fields = ##class(%DynamicAbstractObject).%FromJSON(result.Data).fields
		} Catch {
			Set fields = ""
		}
		Quit ..BadSettings($Select($IsObject(fields): fields, 1: ["signIn"]))
	}
	If result.Outcome = "not_available" Quit ..Fail(409, "not_available", ..#MESSAGENOTAVAILABLE)
	If 'result.Ok || ((result.Outcome '= "started") && (result.Outcome '= "checked")) Quit ..ServerError($SYSTEM.Status.Error(5001, "SettingsOps answered the mail sign-in with '"_result.Outcome_"'"))
	Try {
		Set answer = {"result": (result.Outcome)}
		Set data = ##class(%DynamicAbstractObject).%FromJSON(result.Data)
		Set iterator = data.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do answer.%Set(name, value, data.%GetTypeOf(name))
		}
	} Catch exception {
		Return ..ServerError(exception.AsStatus())
	}
	Set %response.ContentType = ..#CONTENTTYPE
	Write answer.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// The origin of the request, as the browser envelope checks it: http or https (from %request.Secure) and the Host header. A test subclass overrides it.
ClassMethod PageOrigin() As %String [ Private ]
{
	Quit $Select(%request.Secure: "https", 1: "http")_"://"_%request.GetCgiEnv("HTTP_HOST")
}

/// The save of one settings section (AD-1, AD-4, AD-19): the body is a JSON object of the section's field to value, and anything else is 400
/// bad_settings with no field and nothing submitted. The route submits one SaveSettings command (the section's slug, the body as it is, the IRIS user of
/// the call and the CSP session's Ref) through Commands.Submit with origin web_admin, and SettingsOps decides what is acceptable. The answers are
/// those of Answer.
ClassMethod SaveSection(section As %String) As %Status [ Private ]
{
	If '..SettingsBody(.body) Quit ..BadSettings([])
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set command = ##class(OcuTalon.Msg.Command.SaveSettings).%New()
	Set command.Slug = section
	Set command.Changes = body.%ToJSON()
	Set command.ActingUser = $USERNAME
	Set command.SessionRef = sessionRef
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Quit ..Answer(result, "")
}

/// The one submit of SaveChannels: the command through Commands.Submit with origin web_admin. A test subclass overrides it.
ClassMethod SubmitChannels(command As OcuTalon.Msg.Command.SaveSettings, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
}

/// The one submit of SignInMail: the command through Commands.Submit with origin web_admin. A test subclass overrides it.
ClassMethod SubmitSignIn(command As OcuTalon.Msg.Command.MailSignIn, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
}

/// POST /v1/settings/demo-mode: the body is {"demoMode": true or false} and nothing else; any other body is 400 bad_settings, naming demoMode
/// unless it is a boolean. The route submits a
/// SetDemoMode command with origin web_admin, which SettingsOps carries out as it does for the terminal (audit, value, Demo step). The answers are those of
/// Answer; a Demo step that failed after the value was written (step_failed) is 409 demo_step_failed with MESSAGEDEMOSTEPFAILED.
ClassMethod SaveDemoMode() As %Status
{
	If '..SettingsBody(.body) || (body.%Size() '= 1) || (body.%GetTypeOf("demoMode") '= "boolean") Quit ..BadSettings($Select(body = "": [], body.%GetTypeOf("demoMode") = "boolean": [], 1: ["demoMode"]))
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set command = ##class(OcuTalon.Msg.Command.SetDemoMode).%New()
	Set command.DemoMode = body.demoMode
	Set command.ActingUser = $USERNAME
	Set command.SessionRef = sessionRef
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Quit ..Answer(result, $Select(command.DemoMode: "on", 1: "off"))
}

/// The answer to a save from the CommandResult (word is "on" or "off" for a demo mode save): Ok is 200 {"result":"done","sections"} with the
/// sections read fresh; refused is 400 bad_settings with the refused fields (Data); not_built is 501; not_available is 409; step_failed is 409 demo_step_failed; no result,
/// not_audited, failed, unknown_command and any other outcome are 500 server_error.
ClassMethod Answer(result As OcuTalon.Msg.CommandResult, word As %String) As %Status [ Private ]
{
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	If result.Ok {
		Try {
			Set answer = {"result": "done", "sections": (##class(OcuTalon.Core.SettingsOps).Values().sections)}
		} Catch exception {
			Return ..ServerError(exception.AsStatus())
		}
		Set %response.ContentType = ..#CONTENTTYPE
		Write answer.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	Set outcome = result.Outcome
	If outcome = "refused" {
		Try {
			Set fields = ##class(%DynamicAbstractObject).%FromJSON(result.Data).fields
		} Catch {
			Set fields = []
		}
		Quit ..BadSettings($Select($IsObject(fields): fields, 1: []))
	}
	If outcome = "not_built" Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
	If outcome = "not_available" Quit ..Fail(409, "not_available", ..#MESSAGENOTAVAILABLE)
	If (outcome = "step_failed") && (word '= "") Quit ..Fail(409, "demo_step_failed", $Replace(..#MESSAGEDEMOSTEPFAILED, "{v}", word))
	Quit ..ServerError($SYSTEM.Status.Error(5001, "The settings save was answered "_outcome))
}

/// 400 bad_settings with MESSAGEBADSETTINGS and the names of the refused fields.
ClassMethod BadSettings(fields As %DynamicArray) As %Status [ Private ]
{
	Quit ..Fail(400, "bad_settings", ..#MESSAGEBADSETTINGS, , {"fields": (fields)})
}

/// The request body as a JSON object, and 1 when it is one; otherwise 0, with body empty.
ClassMethod SettingsBody(Output body As %DynamicObject) As %Boolean [ Private ]
{
	Set body = ""
	Try {
		Set parsed = ##class(%DynamicAbstractObject).%FromJSON(..BodyText())
	} Catch {
		Set parsed = ""
	}
	If '$IsObject(parsed) || 'parsed.%IsA("%Library.DynamicObject") Quit 0
	Set body = parsed
	Quit 1
}

/// Every route whose story hasn't shipped: 501 not_built. arg is the route's :ref or :name.
ClassMethod NotBuilt(arg As %String = "") As %Status
{
	Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
}

/// POST /v1/settings/models: see SaveSection.
ClassMethod SaveModels() As %Status
{
	Quit ..SaveSection("models")
}

/// POST /v1/settings/models/test (AD-1, AD-4, AD-8, AD-19; Story 18.3): tests the saved first model of one agent. The body is exactly {"agent": string}; any other
/// body, and an agent that SettingsOps refuses, is 400 bad_settings with the field agent. One TestModel is submitted through Commands.Submit with origin web_admin
/// (the path is under /v1/settings/, so IsSettingsUrl's admin gate covers it). Ok is 200 with the CommandResult's Data, {"answered", "seconds", "reason"}; an error
/// status, no result or any other outcome is 500 server_error, with the cause logged.
ClassMethod TestModel() As %Status
{
	If '..SettingsBody(.body) || (body.%Size() '= 1) || (body.%GetTypeOf("agent") '= "string") || ($Length(body.agent) > 32) Quit ..BadSettings(["agent"])
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set command = ##class(OcuTalon.Msg.Command.TestModel).%New()
	Set command.Agent = body.agent
	Set command.SessionRef = sessionRef
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	If result.Outcome = "refused" Quit ..BadSettings(["agent"])
	If 'result.Ok || (result.Outcome '= "tested") Quit ..ServerError($SYSTEM.Status.Error(5001, "SettingsOps answered the model test with '"_result.Outcome_"'"))
	Set %response.ContentType = ..#CONTENTTYPE
	Write result.Data
	Quit $SYSTEM.Status.OK()
}

/// The snapshot's last key, traceAccount: {"user", "password"}, the read-only Visual Trace account that the online demo
/// publishes (AD-19 calls the published accounts not secrets), for the header's Visual Trace menu. Present only when the
/// public setting onlineDemo is 1 and both readonlyUser and readonlyPassword are set; any other state returns "" and the
/// snapshot has no such key, so a local install's snapshot keeps its keys. Both values are read through Data.Setting.Get,
/// as StateBody reads onlineDemo. It is a page-only field: no live event carries it.
ClassMethod TraceAccount() As %DynamicObject [ Private ]
{
	If ##class(OcuTalon.Data.Setting).Get("onlineDemo") '= 1 Quit ""
	Set user = ##class(OcuTalon.Data.Setting).Get("readonlyUser")
	Set password = ##class(OcuTalon.Data.Setting).Get("readonlyPassword")
	If (user = "") || (password = "") Quit ""
	Quit {"user": (user), "password": (password)}
}

/// The online demo's reset fields of the snapshot (Story 16.8, AD-12, AD-19): the active resetSoon condition appended to status (the
/// StatusMonitor.ResetSoon computation, exported through Status.ActiveOf), then, as the snapshot's last key, nextReset: the one
/// next reset, Public.Settings.NextReset, set only when there is one. With the flag off it adds nothing, so a local install's
/// snapshot keeps its keys. A page-only field: the reset event carries the same value.
ClassMethod AddReset(body As %DynamicObject) [ Private ]
{
	If ##class(OcuTalon.Data.Setting).Get("onlineDemo") '= 1 Quit
	Set conditions = ##class(%Library.ListOfObjects).%New()
	Do conditions.Insert(##class(OcuTalon.Core.StatusMonitor).ResetSoon())
	Set active = ##class(OcuTalon.Live.Payload.Status).ActiveOf(conditions)
	Set iterator = active.%GetIterator()
	While iterator.%GetNext(.position, .condition) {
		Do body.status.%Push(condition)
	}
	Set next = ##class(OcuTalon.Data.Public.Settings).NextReset()
	If next '= "" Set body.nextReset = next
}

/// The pairing routes (AD-1, AD-4, AD-13): 404 not_found while the release doesn't include Telegram, before anything else is read.
/// Otherwise DELETE is Unpair and POST is PairingCode.
ClassMethod Pairing() As %Status
{
	If '##class(OcuTalon.Channel.Telegram.In).Included() Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If %request.Method = "DELETE" Quit ..Unpair()
	Quit ..PairingCode()
}

/// POST /v1/pairing/code: a pairing code for the CSP session's session. It answers 409 not_available when the recorded Telegram state
/// is not on (MESSAGETELEGRAMOFF) or a pause is set (MESSAGETELEGRAMPAUSED), before it reads the session, and nothing is written.
/// Otherwise it makes the code (a Ref), stores only its hash and an expiry CODESECONDS from now through Data.Pairing.StoreCode (which replaces the session's
/// earlier code), and answers 200 {"code","expiresAt"}: the one place that the code exists. A session that can't be read and a code
/// that can't be stored are 500 server_error.
ClassMethod PairingCode() As %Status [ Private ]
{
	If ##class(OcuTalon.Data.StatusMark).TelegramState() '= "on" Quit ..Fail(409, "not_available", ..#MESSAGETELEGRAMOFF)
	If ##class(OcuTalon.Live.Payload.Status).TelegramPausedUntil() '= "" Quit ..Fail(409, "not_available", ..#MESSAGETELEGRAMPAUSED)
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set code = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set expiresAt = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), ..#CODESECONDS)
	Set sc = ##class(OcuTalon.Data.Pairing).StoreCode(sessionRef, ##class(OcuTalon.Data.Pairing).HashCode(code), expiresAt)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set %response.ContentType = ..#CONTENTTYPE
	Write {"code": (code), "expiresAt": (expiresAt)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// DELETE /v1/pairing: unpairs the CSP session's chat. It never reads the body and submits an Unpair command for the session through
/// Commands.Submit (origin web_user), which reaches SessionOps through CommandsIn, synchronously. Ok and not_paired are 200
/// {"result":"done"} (nothing paired is not an error); not_built is 501 not_built; a status or any other outcome is 500 server_error.
ClassMethod Unpair() As %Status [ Private ]
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set command = ##class(OcuTalon.Msg.Command.Unpair).%New()
	Set command.SessionRef = sessionRef
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	If result.Ok || (result.Outcome = "not_paired") {
		Set %response.ContentType = ..#CONTENTTYPE
		Write {"result": "done"}.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	If result.Outcome = "not_built" Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
	Quit ..ServerError($SYSTEM.Status.Error(5001, "The unpair was answered "_result.Outcome))
}

/// The snapshot of a session, keys in this order: the version, the instance zone, the session's epoch, each stream's
/// last Seq (read before any section, so that every change after the cursors is an event the page will apply), the chat
/// and the rail (read through Ownership: the chat holds the newest CHATMAX of the session's turns, visible noticed
/// incidents and web notice cards merged by time, oldest first; the rail its pending approval requests, checks, pending
/// reminders and newest decisions), the signed-in user (the session row's, never the client's), admin (whether the signed-in user holds OcuTalonAdmin, which only decides the page's
/// Settings link), the booleans onlineDemo and demoMode, models:
/// the display names of the triage, diagnosis and chat agents' models, telegram: whether the release includes Telegram
/// and the session's pairing, status: the active status conditions, and, only while demo mode is on, phone: the session's
/// newest PHONEMAX simulated-phone messages, oldest first, mailbox: the session's newest MAILMAX simulated-mailbox emails,
/// oldest first, each the mailbox payload plus, when the session has a decide decision of the email's Item, the member
/// decision (its payload), and guide: the guide that Demo.Guide.Compute derives; after those, traceAccount (TraceAccount: the
/// read-only account's user name and password) only when onlineDemo is 1 and both read-only values are set; on the online
/// demo, idleSeconds (IdleSeconds: the page's idle cap) comes before traceAccount, resetSoon is appended to status when active and
/// the last key is nextReset when there is a next reset (AddReset).
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
	Do body.%Set("admin", ..IsAdmin(), "boolean")
	Do body.%Set("onlineDemo", ##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1, "boolean")
	Do body.%Set("demoMode", ##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Install.Step.Demo).#MODEKEY) = "1", "boolean")
	Set body.models = {
		"triage": (..ModelName(..ResolveModel("TriageAgent"))),
		"diagnosis": (..ModelName(..ResolveModel("DiagnosisAgent"))),
		"chat": (..ModelName(..ResolveModel("ChatAgent")))
	}
	Set telegram = {"included": false, "state": "off", "botUserName": "", "paired": false, "displayName": "", "pausedUntil": ""}
	Do telegram.%Set("included", ##class(OcuTalon.Channel.Telegram.In).Included(), "boolean")
	Set telegram.state = ##class(OcuTalon.Data.StatusMark).TelegramState(.botUserName)
	Set telegram.botUserName = botUserName
	Set telegram.pausedUntil = ##class(OcuTalon.Live.Payload.Status).TelegramPausedUntil()
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
	If body.onlineDemo Set body.idleSeconds = ..IdleSeconds()
	Set account = ..TraceAccount()  Set:$IsObject(account) body.traceAccount = account
	Do ..AddReset(body)
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Do ##class(OcuTalon.Web.TraceLink).Add(body, .viewer)
	Quit body
}

/// The idle cap in seconds that the online demo's snapshot carries (Setting IDLEKEY): the stored value when it is a whole number
/// above 0, else Setting IDLESEED (600).
ClassMethod IdleSeconds() As %Integer [ Private ]
{
	Set seconds = ##class(OcuTalon.Data.Setting).Get(##class(OcuTalon.Data.Setting).#IDLEKEY, ##class(OcuTalon.Data.Setting).#IDLESEED)
	Quit $Select((seconds ? 1.N) && (seconds > 0): +seconds, 1: ##class(OcuTalon.Data.Setting).#IDLESEED)
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
/// and reminder cards that WebChatOut kept, DW-62), as live items ({"type", "payload"}), oldest first. An incident whose
/// DecisionRef is a decision of the session's own carries it as the member decision beside payload, the Decision payload
/// object, so that the card's footer finds its diagnosis decision after a load; another owner's decision or an empty
/// DecisionRef gives none, and a read that fails throws. The three reads are
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
		Set item = {"type": "incident", "payload": (..PayloadObject(##class(OcuTalon.Live.Payload.Incident).FromRow(incident)))}
		If incident.DecisionRef '= "" {
			Set decision = ##class(OcuTalon.Data.Ownership).Decision(incident.DecisionRef, sessionRef, .sc)
			Do ..Check(sc)
			If $IsObject(decision) Set item.decision = ..PayloadObject(##class(OcuTalon.Live.Payload.Decision).FromRow(decision))
		}
		Set merged("T"_incident.NoticedAt, 1, incident.%Id()) = item
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

/// Writes the status line and the error body {"error": {"code", "message"}}, followed by "approval" when a payload object is given
/// and then by every member of extra when an object is given (a 429's retryAt and limit). status is the number, 400 to 501.
ClassMethod Fail(status As %Integer, code As %String, message As %String, approval As %DynamicObject = "", extra As %DynamicObject = "") As %Status
{
	Set %response.ContentType = ..#CONTENTTYPE
	Set %response.Status = $Case(status,
		400: ..#HTTP400BADREQUEST,
		401: ..#HTTP401UNAUTHORIZED,
		403: ..#HTTP403FORBIDDEN,
		404: ..#HTTP404NOTFOUND,
		405: ..#HTTP405METHODNOTALLOWED,
		409: ..#HTTP409CONFLICT,
		429: ..#HTTP429TOOMANYREQUESTS,
		503: ..#HTTP503SERVICEUNAVAILABLE,
		500: ..#HTTP500INTERNALSERVERERROR,
		501: ..#HTTP501NOTIMPLEMENTED,
		: status)
	Set body = ..ErrorBody(code, message)
	If $IsObject(approval) Set body.approval = approval
	If $IsObject(extra) {
		Set iterator = extra.%GetIterator()
		While iterator.%GetNext(.name, .value, .type) {
			If $IsObject(value) {
				Do body.%Set(name, value)
			} Else {
				Do body.%Set(name, value, type)
			}
		}
	}
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

/// GET /v1/persona (AD-19; Epic 40): the signed-in session's persona as SettingsOps.Persona reads it, 200 {"preset","language","custom",
/// "customOffered","pendingRef"}, every value with its JSON type. A session that can't be read and a read that fails are 500
/// server_error, with the cause logged and no value sent.
ClassMethod GetPersona() As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set persona = ..ReadPersona(sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set %response.ContentType = ..#CONTENTTYPE
	Write persona.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// PUT /v1/persona (AD-1, AD-4, AD-19; Epic 40): saves the signed-in session's persona. The session is Ownership.SessionRef's and a
/// sessionRef in the body is ignored. In order: the session (a failure is 500 server_error); the body (PersonaBody; a bad one is 400
/// bad_persona and nothing is submitted); the values the preset does not use are dropped (language is "" unless the preset is language,
/// custom is "" unless it is custom: DW-669) and a used language of more than 40 characters or a used custom of more than 1,000
/// (UTF-16 units, as SettingsOps counts them) is 400 bad_language or bad_custom with SettingsOps' message, nothing submitted; a
/// SetPersona with the preset and the used values, submitted with origin web_user (an error status or no result is 500 server_error).
/// SettingsOps validates and writes, and the answer follows its result:
///   - Ok: 200 {"result":"done","message","preset","language","custom"}, the message as the owner gave it (the Saved sentence when it gave
///     none) and the values as it saved them; Data that can't be read is 500 server_error;
///   - bad_preset, bad_language, bad_custom, custom_not_offered: 400 with the outcome as the code and the owner's message;
///   - not_built: 501 not_built;
///   - any other outcome: 500 not_saved with the owner's message as given.
/// A refusal or a failure that came with no message carries the server_error sentence.
ClassMethod PutPersona() As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '..PersonaBody(.preset, .language, .custom) Quit ..Fail(400, "bad_persona", ##class(OcuTalon.Core.SettingsOps).#MESSAGENOTSAVED)
	If preset '= "language" Set language = ""
	If preset '= "custom" Set custom = ""
	If $Length(language) > 40 Quit ..Fail(400, "bad_language", ##class(OcuTalon.Core.SettingsOps).#MESSAGEBADLANGUAGE)
	If $Length(custom) > 1000 Quit ..Fail(400, "bad_custom", ##class(OcuTalon.Core.SettingsOps).#MESSAGEBADCUSTOM)
	Set command = ##class(OcuTalon.Msg.Command.SetPersona).%New()
	Set command.SessionRef = sessionRef
	Set command.Preset = preset
	Set command.Language = language
	Set command.Custom = custom
	Set sc = ..SubmitPersona(command, .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	Set outcome = result.Outcome
	Set message = $Select(result.Message '= "": result.Message, result.Ok: ##class(OcuTalon.Core.SettingsOps).#MESSAGESAVED, 1: ..#MESSAGESERVERERROR)
	If result.Ok {
		Set sc = $SYSTEM.Status.OK()
		Try {
			Set saved = ##class(%DynamicAbstractObject).%FromJSON(result.Data)
			Set answer = {}
			Do answer.%Set("result", "done", "string")
			Do answer.%Set("message", message, "string")
			Do answer.%Set("preset", saved.preset, "string")
			Do answer.%Set("language", saved.language, "string")
			Do answer.%Set("custom", saved.custom, "string")
		} Catch exception {
			Set sc = exception.AsStatus()
		}
		If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
		Set %response.ContentType = ..#CONTENTTYPE
		Write answer.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	If $ListFind($ListBuild("bad_preset", "bad_language", "bad_custom", "custom_not_offered"), outcome) Quit ..Fail(400, outcome, message)
	If outcome = "not_built" Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
	Quit ..Fail(500, "not_saved", message)
}

/// The preset, language and custom of the PUT /v1/persona body, and 1 when it is a valid one: a JSON object whose preset is a string and
/// whose language and custom, when present, are strings (other members are ignored). An absent language or custom is "". Otherwise 0,
/// with all three empty. The values are not judged here: SettingsOps does.
ClassMethod PersonaBody(Output preset As %String, Output language As %String, Output custom As %String) As %Boolean [ Private ]
{
	Set (preset, language, custom) = ""
	Try {
		Set body = ##class(%DynamicAbstractObject).%FromJSON(..BodyText())
	} Catch {
		Set body = ""
	}
	If '$IsObject(body) || 'body.%IsA("%Library.DynamicObject") Quit 0
	If body.%GetTypeOf("preset") '= "string" Quit 0
	Set languageType = body.%GetTypeOf("language")
	Set customType = body.%GetTypeOf("custom")
	If (languageType '= "string") && (languageType '= "unassigned") Quit 0
	If (customType '= "string") && (customType '= "unassigned") Quit 0
	Set preset = body.preset
	If languageType = "string" Set language = body.language
	If customType = "string" Set custom = body.custom
	Quit 1
}

/// The persona of the session as SettingsOps.Persona reads it; sc is an error status when a part of it could not be read.
ClassMethod ReadPersona(sessionRef As %String, Output sc As %Status) As %DynamicObject [ Private ]
{
	Quit ##class(OcuTalon.Core.SettingsOps).Persona(sessionRef, .sc)
}

/// Submits the SetPersona with origin web_user; result is the CommandResult. An error status means the command never reached CommandsIn.
ClassMethod SubmitPersona(command As OcuTalon.Msg.Command.SetPersona, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
}

/// GET /v1/heartbeat (AD-4, AD-12, AD-19; Epic 39): the signed-in session's heartbeat as SettingsOps.Heartbeat reads it from the rows, with
/// traceUrl added where the view names a trace (Web.TraceLink). A session that can't be read and a read that fails are 500 server_error, with
/// the cause logged and no value sent.
ClassMethod GetHeartbeat() As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set heartbeat = ..ReadHeartbeat(sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
	Do ##class(OcuTalon.Web.TraceLink).Add(heartbeat, .viewer)
	Set %response.ContentType = ..#CONTENTTYPE
	Write heartbeat.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// PUT /v1/heartbeat (AD-1, AD-4, AD-19; Epic 39): saves the signed-in session's heartbeat settings. The session is Ownership.SessionRef's and a
/// sessionRef in the body is ignored. In order: the session (a failure is 500 server_error); the body (HeartbeatBody; a bad one is 400
/// bad_heartbeat and nothing is submitted); a checklist of more than Checks.Beat CHECKLISTMAX characters is 400 bad_checklist with SettingsOps'
/// message, nothing submitted; a SetHeartbeat with the five values (on as 1 or 0, the interval as the text of its number), submitted with origin
/// web_user (an error status or no result is 500 server_error). SettingsOps validates and writes, and the answer follows its result:
///   - Ok: 200 {"result":"done","message","on","interval","from","to","checklist"}, the message as the owner gave it (the Saved sentence when it
///     gave none) and the values as it saved them; Data that can't be read is 500 server_error;
///   - bad_on, bad_interval, bad_hours, bad_checklist: 400 with the outcome as the code and the owner's message;
///   - not_built: 501 not_built;
///   - any other outcome: 500 not_saved with the owner's message as given.
/// A refusal or a failure that came with no message carries the server_error sentence.
ClassMethod PutHeartbeat() As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '..HeartbeatBody(.on, .interval, .from, .to, .checklist) Quit ..Fail(400, "bad_heartbeat", ##class(OcuTalon.Core.SettingsOps).#MESSAGENOTSAVED)
	If $Length(checklist) > ##class(OcuTalon.Checks.Beat).#CHECKLISTMAX Quit ..Fail(400, "bad_checklist", ##class(OcuTalon.Core.SettingsOps).#MESSAGEBADCHECKLIST)
	Set command = ##class(OcuTalon.Msg.Command.SetHeartbeat).%New()
	Set command.SessionRef = sessionRef
	Set command.On = $Select(on: "1", 1: "0")
	Set command.Interval = interval
	Set command.From = from
	Set command.To = to
	Set command.Checklist = checklist
	Set sc = ..SubmitHeartbeat(command, .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	Set outcome = result.Outcome
	Set message = $Select(result.Message '= "": result.Message, result.Ok: ##class(OcuTalon.Core.SettingsOps).#MESSAGEHEARTBEATSAVED, 1: ..#MESSAGESERVERERROR)
	If result.Ok {
		Set sc = $SYSTEM.Status.OK()
		Try {
			Set saved = ##class(%DynamicAbstractObject).%FromJSON(result.Data)
			Set answer = {}
			Do answer.%Set("result", "done", "string")
			Do answer.%Set("message", message, "string")
			Do answer.%Set("on", saved.on, "boolean")
			Do answer.%Set("interval", saved.interval, "number")
			Do answer.%Set("from", saved.from, "string")
			Do answer.%Set("to", saved.to, "string")
			Do answer.%Set("checklist", saved.checklist, "string")
		} Catch exception {
			Set sc = exception.AsStatus()
		}
		If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
		Set %response.ContentType = ..#CONTENTTYPE
		Write answer.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	If $ListFind($ListBuild("bad_on", "bad_interval", "bad_hours", "bad_checklist"), outcome) Quit ..Fail(400, outcome, message)
	If outcome = "not_built" Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
	Quit ..Fail(500, "not_saved", message)
}

/// POST /v1/heartbeat/run (AD-1, AD-4, AD-18, AD-26; Epic 39): asks for a beat now for the signed-in session. The body is never read. The session
/// is Ownership.SessionRef's (a failure is 500 server_error); a RunHeartbeat is submitted with origin web_user, which CommandsIn sends to Checks
/// as a BeatNow (an error status or no result is 500 server_error). The answer follows Checks' result:
///   - Ok: 202 {"result":"sent"};
///   - cooldown, cap, nokey, empty, backoff: 409 {"error":{"code","message"}} with the outcome as the code and its sentence, in which {time} is the
///     time of the result's availableAt as Tools.CommandCall.TimeLabel gives it (the catalog's time: " ET" on the online demo; "at" becomes "on"
///     before a dated time), and availableAt (UTC) beside the error when Data has one;
///   - not_built: 501 not_built;
///   - anything else (failed included): 500 server_error, with the cause logged.
ClassMethod RunHeartbeat() As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set command = ##class(OcuTalon.Msg.Command.RunHeartbeat).%New()
	Set command.SessionRef = sessionRef
	Set sc = ..SubmitHeartbeat(command, .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	If result.Ok {
		Set %response.ContentType = ..#CONTENTTYPE
		Set %response.Status = ..#HTTP202ACCEPTED
		Write {"result": "sent"}.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	Set outcome = result.Outcome
	If $ListFind($ListBuild("cooldown", "cap", "nokey", "empty", "backoff"), outcome) {
		Set availableAt = ""
		Try {
			Set availableAt = ##class(%DynamicAbstractObject).%FromJSON(result.Data).%Get("availableAt")
		} Catch {
			Set availableAt = ""
		}
		Set message = $Case(outcome, "cooldown": ..#MESSAGERUNCOOLDOWN, "cap": ..#MESSAGERUNCAP, "nokey": ..#MESSAGERUNNOKEY, "empty": ..#MESSAGERUNEMPTY, : ..#MESSAGERUNBACKOFF)
		Set time = ##class(OcuTalon.Tools.CommandCall).TimeLabel(availableAt, ##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
		If (time '= "") && ($Extract(time, 1, 5) '? 2N1":"2N) Set message = $Replace(message, "at {time}", "on {time}")
		Set message = $Replace(message, "{time}", time)
		Quit ..Fail(409, outcome, message, , $Select(availableAt '= "": {"availableAt": (availableAt)}, 1: ""))
	}
	If outcome = "not_built" Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
	Quit ..ServerError($SYSTEM.Status.Error(5001, "Checks answered the run with '"_outcome_"'"))
}

/// POST /v1/settings/daily-digest/send (AD-1, AD-4, AD-14, AD-32; Story 18.2): sends the signed-in admin's digest now. The body is never read. The
/// path is under /v1/settings/, so IsSettingsUrl's admin gate covers it (a non-admin is 403 not_admin). The session is Ownership.SessionRef's (a
/// failure is 500 server_error); one SendDigest with a fresh IdempotencyKey is submitted through Commands.Submit with origin web_admin. Ok is
/// 202 {"result":"sending"}; an error status, no result or any other outcome is 500 server_error, with the cause logged.
ClassMethod SendDigest() As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set command = ##class(OcuTalon.Msg.Command.SendDigest).%New()
	Set command.SessionRef = sessionRef
	Set command.IdempotencyKey = "web-digest-"_$SYSTEM.Util.CreateGUID()
	Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_admin", .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	If 'result.Ok Quit ..ServerError($SYSTEM.Status.Error(5001, "Digest answered the send with '"_result.Outcome_"'"))
	Set %response.ContentType = ..#CONTENTTYPE
	Set %response.Status = ..#HTTP202ACCEPTED
	Write {"result": "sending"}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// The on, interval, from, to and checklist of the PUT /v1/heartbeat body, and 1 when it is a valid one: a JSON object whose on is a boolean,
/// whose interval is a number and whose from, to and checklist are strings (other members are ignored; a missing member is a bad body). on comes
/// out as 1 or 0 and interval as the text of its number. Otherwise 0, with all five empty. The values are not judged here: SettingsOps does.
ClassMethod HeartbeatBody(Output on As %Boolean, Output interval As %String, Output from As %String, Output to As %String, Output checklist As %String) As %Boolean [ Private ]
{
	Set (on, interval, from, to, checklist) = ""
	Try {
		Set body = ##class(%DynamicAbstractObject).%FromJSON(..BodyText())
	} Catch {
		Set body = ""
	}
	If '$IsObject(body) || 'body.%IsA("%Library.DynamicObject") Quit 0
	If (body.%GetTypeOf("on") '= "boolean") || (body.%GetTypeOf("interval") '= "number") Quit 0
	If (body.%GetTypeOf("from") '= "string") || (body.%GetTypeOf("to") '= "string") || (body.%GetTypeOf("checklist") '= "string") Quit 0
	Set on = $Select(body.on: 1, 1: 0)
	Set interval = body.interval
	Set from = body.from
	Set to = body.to
	Set checklist = body.checklist
	Quit 1
}

/// The heartbeat of the session as SettingsOps.Heartbeat reads it; sc is an error status when a part of it could not be read.
ClassMethod ReadHeartbeat(sessionRef As %String, Output sc As %Status) As %DynamicObject [ Private ]
{
	Quit ##class(OcuTalon.Core.SettingsOps).Heartbeat(sessionRef, .sc)
}

/// Submits the SetHeartbeat or RunHeartbeat with origin web_user; result is the CommandResult. An error status means the command never reached
/// CommandsIn.
ClassMethod SubmitHeartbeat(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
}

/// POST /v1/decisions/:ref/noise (AD-1, AD-4, AD-21; Epic 41): marks one of the session's own notices as noise, which PrecedentOps records as a precedent. The session is
/// the CSP session's. In order: the session and the decision's visibility (Ownership.Decision; a failed read is 500 server_error and a decision the session
/// can't see is 404 not_found, before anything is submitted); the channel (phone only for the exact body {"channel":"phone"}, else web); a MarkNoise
/// submitted with origin web_user through SubmitMemory (an error status or no result is 500 server_error). The answer follows the owner's result:
///   - Ok (marked and already_marked): 200 {"result":"done","markedAt"}, the time of the first mark;
///   - too_old: 409 too_old with MESSAGETOOOLD; not_found: 404 not_found; not_built: 501 not_built;
///   - anything else: 500 server_error, with the cause logged.
ClassMethod MarkNoise(ref As %String) As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set row = ##class(OcuTalon.Data.Ownership).Decision(ref, sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(row) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set command = ##class(OcuTalon.Msg.Command.MarkNoise).%New()
	Set command.DecisionRef = row.Ref
	Set command.SessionRef = sessionRef
	Set command.Channel = $Select(..NoiseBodyIsPhone(): "phone", 1: "web")
	Kill row
	Set sc = ..SubmitMemory(command, .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	If result.Ok {
		Set sc = $SYSTEM.Status.OK()
		Try {
			Set answer = {}
			Do answer.%Set("result", "done", "string")
			Do answer.%Set("markedAt", ##class(%DynamicAbstractObject).%FromJSON(result.Data).%Get("answeredAt"), "string")
		} Catch exception {
			Set sc = exception.AsStatus()
		}
		If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
		Set %response.ContentType = ..#CONTENTTYPE
		Write answer.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	Set outcome = result.Outcome
	If outcome = "too_old" Quit ..Fail(409, "too_old", ..#MESSAGETOOOLD)
	If outcome = "not_found" Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If outcome = "not_built" Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
	Quit ..ServerError($SYSTEM.Status.Error(5001, "The noise mark was answered "_outcome))
}

/// 1 only when the request body is exactly the JSON object {"channel":"phone"}: one member, named channel, the string phone.
ClassMethod NoiseBodyIsPhone() As %Boolean [ Private ]
{
	Try {
		Set body = ##class(%DynamicAbstractObject).%FromJSON(..BodyText())
	} Catch {
		Set body = ""
	}
	If '$IsObject(body) || 'body.%IsA("%Library.DynamicObject") Quit 0
	Quit (body.%Size() = 1) && (body.%GetTypeOf("channel") = "string") && (body.channel = "phone")
}

/// GET /v1/memory/precedents (AD-4, AD-21; Epic 41): the session's own precedents, newest first, at most PRECEDENTSMAX, as 200 {"precedents":[...]}. A seeded row is never
/// one of them. A session that can't be read and a read that fails are 500 server_error, with the cause logged.
ClassMethod Precedents() As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set rows = ##class(OcuTalon.Data.Ownership).Precedents(sessionRef, ..#PRECEDENTSMAX, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set list = []
	For i = 1:1:rows.Count() {
		Do list.%Push(##class(OcuTalon.Data.Precedent).View(rows.GetAt(i)))
	}
	Set %response.ContentType = ..#CONTENTTYPE
	Write {"precedents": (list)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// DELETE /v1/memory/precedents/:ref (AD-1, AD-4, AD-21; Epic 41): forgets one of the session's own precedents. In order: the session and the row's visibility
/// (Ownership.Precedent; a failed read is 500 server_error and a row the session can't see, a seeded one included, is 404 not_found before anything is
/// submitted); a ForgetPrecedent submitted with origin web_user through SubmitMemory (an error status or no result is 500 server_error). The answer: Ok
/// 200 {"result":"done"}; not_found 404; not_built 501; anything else 500 server_error.
ClassMethod ForgetPrecedent(ref As %String) As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set row = ##class(OcuTalon.Data.Ownership).Precedent(ref, sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(row) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set command = ##class(OcuTalon.Msg.Command.ForgetPrecedent).%New()
	Set command.PrecedentRef = row.Ref
	Set command.SessionRef = sessionRef
	Kill row
	Set sc = ..SubmitMemory(command, .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	If result.Ok {
		Set %response.ContentType = ..#CONTENTTYPE
		Write {"result": "done"}.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	Set outcome = result.Outcome
	If outcome = "not_found" Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If outcome = "not_built" Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
	Quit ..ServerError($SYSTEM.Status.Error(5001, "The forget was answered "_outcome))
}

/// GET /v1/memory/notes?day=today|yesterday (AD-4; Epic 41): the session's daily note for a day of the instance zone, as 200 {"day","date","lines"}: date is the
/// local date YYYY-MM-DD, and lines are the lines of DailyNote.Build, as strings. A missing day means today; any other day is 404 not_found. A session
/// that can't be read is 500 server_error.
ClassMethod Notes() As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set day = %request.Get("day")
	If day = "" Set day = "today"
	If (day '= "today") && (day '= "yesterday") Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set date = $Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()), "T", 1)
	If day = "yesterday" Set date = $ZDate($ZDateH(date, 3) - 1, 3)
	Set lines = []
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set text = ..NoteText(sessionRef, date)
		For i = 1:1:$Length(text, $Char(10)) {
			Set line = $Piece(text, $Char(10), i)
			If line '= "" Do lines.%Push(line, "string")
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set %response.ContentType = ..#CONTENTTYPE
	Write {"day": (day), "date": (date), "lines": (lines)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// The note of the session for the local day (Data.DailyNote.Build); a seam for the tests.
ClassMethod NoteText(sessionRef As %String, date As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.DailyNote).Build(sessionRef, date)
}

/// GET /v1/memory/items?q= (AD-4, AD-13, AD-21; Epic 41, second part): the session's memories as 200 {"items":[{ref, text, savedAt, source, pinned}],"total"}, each
/// item a memory without its origin, pinned a boolean. A blank q lists the newest MEMORYLISTMAX and total is the session's count; otherwise q (trimmed, at most
/// MEMORYQUERYMAX characters) is searched, the best come back, and total is their number. Neither read touches Data.Memory or Memory.List/Search here (ReadMemories).
/// A session that can't be read and a failed read or search are 500 server_error; a search that has no answer in time is 503 search_busy.
ClassMethod MemoryItems() As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set query = $ZStrip($Extract($ZStrip(%request.Get("q"), "<>WC"), 1, ..#MEMORYQUERYMAX), "<>WC")
	Set sc = ..ReadMemories(sessionRef, query, .items, .total, .busy, .refusal)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If busy Quit ..SearchBusy()
	If $IsObject(refusal) Quit ..Fail(429, "allowance", $Replace(..#MESSAGEALLOWANCE, "{limit}", refusal.limit), , {"retryAt": (refusal.retryAt), "limit": (+refusal.limit)})
	Set %response.ContentType = ..#CONTENTTYPE
	Write {"items": (items), "total": (+total)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// GET /v1/memory/pinned (Story 41.13; AD-1, AD-4, AD-13, AD-21): the session's pinned memories as 200 {"items":[{ref, text, savedAt, source, pinned}],"used"}, newest pin first, with
/// used the tokens of the core-memory block as MemoryOps computed them (ReadPinned). A session that can't be read and a failed read are 500 server_error; a read that has no
/// answer in time is 503 search_busy with Retry-After.
ClassMethod PinnedMemories() As %Status
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set sc = ..ReadPinned(sessionRef, .items, .used, .busy)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If busy Quit ..SearchBusy()
	Set %response.ContentType = ..#CONTENTTYPE
	Write {"items": (items), "used": (+used)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// The 503 search_busy answer of the memory reads: the header Retry-After with SEARCHRETRYAFTER seconds, then the busy message.
ClassMethod SearchBusy() As %Status [ Private ]
{
	Do %response.SetHeader("Retry-After", ..#SEARCHRETRYAFTER)
	Quit ..Fail(503, "search_busy", ..#MESSAGESEARCHBUSY)
}

/// The pinned items of the session as the array [{ref, text, savedAt, source, pinned}] and used, the tokens of their core-memory block: a ListPinnedMemories with the session's
/// SessionRef, submitted with origin web_user through SubmitMemory, which MemoryOps answers with {items, used} in Data. An error status, no result and an answer that is not Ok with
/// that shape are errors; an answer with Outcome busy is busy 1 with an OK status. A seam for the tests.
ClassMethod ReadPinned(sessionRef As %String, Output items As %DynamicArray, Output used As %Integer, Output busy As %Boolean) As %Status [ Private ]
{
	Set items = [], used = 0, busy = 0
	Set command = ##class(OcuTalon.Msg.Command.ListPinnedMemories).%New()
	Set command.SessionRef = sessionRef
	Set sc = ..SubmitMemory(command, .result)
	If $SYSTEM.Status.IsError(sc) Quit sc
	If '$IsObject(result) Quit $SYSTEM.Status.Error(5001, "CommandsIn answered no result")
	If result.Outcome = "busy" {
		Set busy = 1
		Quit $SYSTEM.Status.OK()
	}
	If 'result.Ok Quit $SYSTEM.Status.Error(5001, "The ListPinnedMemories was answered "_result.Outcome)
	Try {
		Set found = ##class(%DynamicAbstractObject).%FromJSON(result.Data)
		If ($ClassName(found) '= "%Library.DynamicObject") || ($ClassName(found.items) '= "%Library.DynamicArray") || (found.%GetTypeOf("used") '= "number") Throw ##class(%Exception.General).%New("ReadPinned", 5001, , "The ListPinnedMemories answered no items and used")
		Set items = found.items
		Set used = found.used
	} Catch exception {
		Set items = [], used = 0
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The items of the session for the query, as the array [{ref, text, savedAt, source, pinned}], and their total; busy is 1 (and the status OK) when a search has no
/// answer in time. A blank query is the session's newest memories through Ownership (ListMemories), anything else a search (SearchMemories). A seam for the tests.
ClassMethod ReadMemories(sessionRef As %String, query As %String, Output items As %DynamicArray, Output total As %Integer, Output busy As %Boolean, Output refusal As %DynamicObject) As %Status [ Private ]
{
	Set items = [], total = 0, busy = 0, refusal = ""
	If query = "" Quit ..ListMemories(sessionRef, .items, .total)
	Quit ..SearchMemories(sessionRef, query, .items, .total, .busy, .refusal)
}

/// The session's newest MEMORYLISTMAX memories and its count of them, read through Ownership.Memories and MemoryTotal.
ClassMethod ListMemories(sessionRef As %String, Output items As %DynamicArray, Output total As %Integer) As %Status [ Private ]
{
	Set items = [], total = 0
	Set rows = ##class(OcuTalon.Data.Ownership).Memories(sessionRef, ..#MEMORYLISTMAX, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Set count = ##class(OcuTalon.Data.Ownership).MemoryTotal(sessionRef, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	For i = 1:1:rows.Count() {
		Set row = rows.GetAt(i)
		Set item = {}
		Set item.ref = row.Ref
		Set item.text = row.Text
		Set item.savedAt = row.SavedAt
		Set item.source = $Select(row.Source = "learned": "learned", 1: "told")
		Do item.%Set("pinned", (+row.Pinned = 1), "boolean")
		Do items.%Push(item)
	}
	Set total = count
	Quit $SYSTEM.Status.OK()
}

/// The best memories of the session for the query: a SearchMemory with the session's SessionRef, submitted with origin web_user through SubmitMemory, which MemoryOps answers
/// with the items in Data (the web user can't embed a query itself). An error status, no result and an answer that is not Ok with items are errors; an answer with Outcome
/// busy (the gate got no answer in time) is busy 1 with an OK status.
ClassMethod SearchMemories(sessionRef As %String, query As %String, Output items As %DynamicArray, Output total As %Integer, Output busy As %Boolean, Output refusal As %DynamicObject) As %Status [ Private ]
{
	Set items = [], total = 0, busy = 0, refusal = ""
	Set command = ##class(OcuTalon.Msg.Command.SearchMemory).%New()
	Set command.Query = query
	Set command.SessionRef = sessionRef
	Set sc = ..SubmitMemory(command, .result)
	If $SYSTEM.Status.IsError(sc) Quit sc
	If '$IsObject(result) Quit $SYSTEM.Status.Error(5001, "CommandsIn answered no result")
	If result.Outcome = "busy" {
		Set busy = 1
		Quit $SYSTEM.Status.OK()
	}
	If result.Outcome = "allowance" Quit ..AllowanceRefusal(result, .refusal)
	If 'result.Ok Quit $SYSTEM.Status.Error(5001, "The SearchMemory was answered "_result.Outcome)
	Try {
		Set found = ##class(%DynamicAbstractObject).%FromJSON(result.Data)
		If $ClassName(found) '= "%Library.DynamicArray" Throw ##class(%Exception.General).%New("SearchMemories", 5001, , "The SearchMemory answered no items")
		Set items = found
		Set total = found.%Size()
	} Catch exception {
		Set items = [], total = 0
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// The refusal of a search that the online demo's message allowance stopped (Story 41.13): the {retryAt, limit} of the result's Data. A Data that holds no retryAt and limit is an error status.
ClassMethod AllowanceRefusal(result As OcuTalon.Msg.CommandResult, Output refusal As %DynamicObject) As %Status [ Private ]
{
	Set refusal = ""
	Set sc = $SYSTEM.Status.OK()
	Try {
		Set found = ##class(%DynamicAbstractObject).%FromJSON(result.Data)
		If ($ClassName(found) '= "%Library.DynamicObject") || (found.%GetTypeOf("retryAt") '= "string") || (found.%GetTypeOf("limit") '= "number") Throw ##class(%Exception.General).%New("AllowanceRefusal", 5001, , "The SearchMemory allowance answer holds no retryAt and limit")
		Set refusal = found
	} Catch exception {
		Set refusal = ""
		Set sc = exception.AsStatus()
	}
	Quit sc
}

/// POST /v1/memory/:ref/pin (AD-1, AD-4, AD-13, AD-21): submits a PinMemory for the session's memory with origin web_user. See MemoryItemCommand for the answers.
ClassMethod PinMemory(ref As %String) As %Status
{
	Quit ..MemoryItemCommand("PinMemory", ref)
}

/// DELETE /v1/memory/:ref/pin: submits an UnpinMemory in the same way.
ClassMethod UnpinMemory(ref As %String) As %Status
{
	Quit ..MemoryItemCommand("UnpinMemory", ref)
}

/// DELETE /v1/memory/items/:ref: submits a ForgetMemory in the same way.
ClassMethod ForgetMemory(ref As %String) As %Status
{
	Quit ..MemoryItemCommand("ForgetMemory", ref)
}

/// The one body of the three memory item writes: submits the command of the verb (PinMemory, UnpinMemory or ForgetMemory) for the ref and the session
/// (Ownership.SessionRef, never the client's) with origin web_user through SubmitMemory. A ref that is empty or longer than MEMORYREFMAX names no memory
/// and is 404 not_found before anything is submitted; whether the ref is the session's own is MemoryOps' check. A session that can't be read, an error
/// status or no result is 500 server_error. The answer: Ok 200 {"result":"done"}; not_found 404; over_cap 409 with MESSAGEOVERCAP (a pin or unpin only);
/// not_built 501; anything else 500 server_error.
ClassMethod MemoryItemCommand(verb As %String, ref As %String) As %Status [ Private ]
{
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If (ref = "") || ($Length(ref) > ..#MEMORYREFMAX) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set command = $ClassMethod("OcuTalon.Msg.Command."_verb, "%New")
	Set command.MemoryRef = ref
	Set command.SessionRef = sessionRef
	Set sc = ..SubmitMemory(command, .result)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	If '$IsObject(result) Quit ..ServerError($SYSTEM.Status.Error(5001, "CommandsIn answered no result"))
	If result.Ok {
		Set %response.ContentType = ..#CONTENTTYPE
		Write {"result": "done"}.%ToJSON()
		Quit $SYSTEM.Status.OK()
	}
	Set outcome = result.Outcome
	If outcome = "not_found" Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	If (outcome = "over_cap") && (verb '= "ForgetMemory") Quit ..Fail(409, "over_cap", ..#MESSAGEOVERCAP)
	If outcome = "not_built" Quit ..Fail(501, "not_built", ..#MESSAGENOTBUILT)
	Quit ..ServerError($SYSTEM.Status.Error(5001, "The "_verb_" was answered "_outcome))
}

/// Submits the MarkNoise, ForgetPrecedent, PinMemory, UnpinMemory, ForgetMemory or SearchMemory with origin web_user; result is the CommandResult. An error status means the command never reached CommandsIn.
/// A ListPinnedMemories is submitted the same way (Story 41.13).
ClassMethod SubmitMemory(command As OcuTalon.Msg.Command, Output result As OcuTalon.Msg.CommandResult) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
}

/// The 403 text of a refused page answer to a setting request (U-114: the owner kept this sentence for the API); its own parameter, so
/// that a change of the tool-call wording cannot reach it.
Parameter MESSAGENOTAPPROVERSETTING = "Only an approver can answer this request.";

}
