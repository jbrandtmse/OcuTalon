/// The REST surface of OcuTalon at /ocutalon/api (AD-13): JSON, versioned under /v1, one CSP session shared
/// with /ocutalon and the trace applications.
///   - GET /v1/state is the snapshot and GET /v1/events the poll (AD-12); every other route of the release answers
///     501 not_built until its story ships, and the pairing routes answer 404 while Telegram is not included.
///   - A request without a session is answered 401 signed_out with no WWW-Authenticate header, so that no browser
///     opens its own password prompt; the public superclass OcuTalon.Web.Public.ApiBase does that, because the
///     answer comes before any role exists. A signed-in user without the OcuTalon user role is answered 403
///     no_role, and the session stays open for the trace applications.
///   - A state-changing call (any method but GET, HEAD and OPTIONS) needs Content-Type: application/json, the
///     header X-OcuTalon-Request: 1 and an Origin that is the request's own origin (AD-13).
///   - No call takes a SessionRef from the client (AD-4): the session is the signed-in user's row.
///   - Every error is {"error": {"code", "message"}} in plain English.
Class OcuTalon.Web.Api Extends OcuTalon.Web.Public.ApiBase
{

Parameter UseSession = 1;

Parameter CONTENTTYPE = "application/json";

Parameter CHARSET = "utf-8";

Parameter HandleCorsRequest = 0;

Parameter HTTP501NOTIMPLEMENTED = "501 Not Implemented";

Parameter MESSAGEBADCURSOR = "The after and afterInstance values must be whole numbers of zero or more.";

Parameter MESSAGENOTJSON = "OcuTalon refused this request because it wasn't sent as JSON.";

Parameter MESSAGENOHEADER = "OcuTalon refused this request because it didn't come from the OcuTalon page.";

Parameter MESSAGEWRONGORIGIN = "OcuTalon refused this request because it came from another site.";

Parameter MESSAGENOTFOUND = "OcuTalon has nothing at this address.";

Parameter MESSAGENOTALLOWED = "This address doesn't accept that kind of request.";

Parameter MESSAGESERVERERROR = "Something went wrong inside OcuTalon. Try again.";

Parameter MESSAGENOTBUILT = "This part of OcuTalon isn't built yet.";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/v1/state" Method="GET" Call="State"/>
<Route Url="/v1/events" Method="GET" Call="Events"/>
<Route Url="/v1/messages" Method="POST" Call="NotBuilt"/>
<Route Url="/v1/approvals/:ref/answer" Method="POST" Call="NotBuilt"/>
<Route Url="/v1/incidents/:ref/dismiss" Method="POST" Call="NotBuilt"/>
<Route Url="/v1/demo/break-feed" Method="POST" Call="NotBuilt"/>
<Route Url="/v1/mailbox/incoming" Method="POST" Call="NotBuilt"/>
<Route Url="/v1/mailbox/samples/:name" Method="POST" Call="NotBuilt"/>
<Route Url="/v1/guide/markers" Method="POST" Call="NotBuilt"/>
<Route Url="/v1/session/end" Method="POST" Call="NotBuilt"/>
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
	If status = 500 {
		If $SYSTEM.Status.IsError(pSC) {
			Try {
				Do ##class(%SYS.System).WriteToConsoleLog("OcuTalon.Web.Api: "_$Translate($SYSTEM.Status.GetErrorText(pSC), $Char(13, 10), "  "), 0, 1)
			} Catch {
			}
		}
		Quit ..Fail(500, "server_error", ..#MESSAGESERVERERROR)
	}
	Quit ##super(pHttpStatus, pSC)
}

/// GET /v1/state
ClassMethod State() As %Status
{
	Set session = ##class(OcuTalon.Data.Session).ForUser($Username, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Write ..StateBody(session).%ToJSON()
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
	Set session = ##class(OcuTalon.Data.Session).ForUser($Username, .sc)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Write ..EventsBody(session, +after, +afterInstance).%ToJSON()
	Quit $SYSTEM.Status.OK()
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

/// The snapshot of a session: the version, the instance zone, the session's epoch, each stream's last Seq, and
/// the chat and rail sections (empty until Story 2.2 fills them).
ClassMethod StateBody(session As OcuTalon.Data.Session) As %DynamicObject
{
	Quit {
		"version": (..Version()),
		"instanceZone": (##class(OcuTalon.Data.Time).Zone()),
		"epoch": (session.Epoch),
		"streams": {
			"session": (##class(OcuTalon.Live.Publish).LastSeq(session.Ref)),
			"instance": (##class(OcuTalon.Live.Publish).LastSeq(##class(OcuTalon.Live.Publish).#INSTANCE))
		},
		"chat": [],
		"rail": {"approvals": [], "checks": [], "reminders": [], "decisions": []}
	}
}

/// The events after the two cursors: the session's own stream first, then the instance stream, each in Seq order
/// and at most MAXEVENTS long, with the session's epoch.
ClassMethod EventsBody(session As OcuTalon.Data.Session, after As %Integer, afterInstance As %Integer) As %DynamicObject
{
	Set events = ##class(OcuTalon.Live.Event).Since(session.Ref, after, ##class(OcuTalon.Live.Event).#MAXEVENTS, "session")
	Set instance = ##class(OcuTalon.Live.Event).Since(##class(OcuTalon.Live.Publish).#INSTANCE, afterInstance, ##class(OcuTalon.Live.Event).#MAXEVENTS, "instance")
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
