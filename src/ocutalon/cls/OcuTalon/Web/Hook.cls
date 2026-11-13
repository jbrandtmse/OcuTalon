/// The dispatch class of the application /ocutalon/hook (AD-13, AD-14, AD-17, AD-19, AD-24; Story 35.3): the one address through which another system sends
/// OcuTalon an event. The application is unauthenticated (UseSession 0, no sign-in) and holds only the role OcuTalonWebhook; it exists on a local install only
/// (the online demo has no hook application and this class answers 404 there too). One route, POST /<ref> with the webhook's Ref (Data.Webhook); every other
/// method and path is 404, and an Allow header is never sent (an OPTIONS request, which the web server dispatches before the role applies, is answered by the
/// public base class OcuTalon.Web.Public.HookBase). Every refusal is a status line with no body. In order:
///   - 401: an unknown or malformed Ref, a missing or wrong secret (the header X-OcuTalon-Webhook-Secret), or a Ref whose owning session has no row. The secret is
///     checked as a salted hash in constant time (Data.Webhook Matches), and an unknown Ref is compared against Data.Webhook DUMMYHASH, so all of them take the same time;
///   - 413: a body of more than Data.Webhook BODYMAX bytes, by the size alone, before the body is read or parsed;
///   - 400: a body that is not a JSON object or array (a scalar, text, an empty body, a form);
///   - 429, with Retry-After (the seconds to the next UTC hour): the webhook's 121st valid event in one UTC clock hour (Data.Webhook ACCEPTEDMAX);
///   - 503: the production cannot take the event (WebhookIn is not available, or the hand-over throws); nothing becomes an item, the hour's accepted count is
///     given back (Data.Webhook Unaccept) and the console log names the Ref and the status;
///   - 202, with no body: WebhookIn has sent the Item (channel webhook, untrusted, the owning session, the webhook's name as subject, the body as text) to Intake,
///     which decides afterwards. The answer never waits for the decision.
/// A 401, 413, 400 or 429 is a rejection: Data.Webhook Reject counts it in the slot of its Ref (or "?" for an unknown or malformed Ref), and when an entry is
/// due (at most one per Data.Webhook AUDITSECONDS per slot) Data.Webhook RecordRejection writes the audit entry. A 404 and a 503 are not counted. An audit write
/// that fails is logged without any request data and changes no answer. No log line or audit entry holds a header, the body, the secret or the caller's address.
/// The answer carries no header of the production's: the SuperSession header that WebhookIn's hand-over sets on the response is deleted, so no answer shows the
/// owning session's trace identifier. The class reads tables with object access only; its one write is the counters global (AD-1).
Class OcuTalon.Web.Hook Extends OcuTalon.Web.Public.HookBase
{

Parameter UseSession = 0;

Parameter HandleCorsRequest = 0;

/// The header that carries the secret, as the CGI variable holds it.
Parameter SECRETVARIABLE = "HTTP_X_OCUTALON_WEBHOOK_SECRET";

Parameter HTTP413CONTENTTOOLARGE = "413 Content Too Large";

Parameter HTTP429TOOMANYREQUESTS = "429 Too Many Requests";

Parameter HTTP503SERVICEUNAVAILABLE = "503 Service Unavailable";

/// The name of the business service that takes the event.
Parameter SERVICE = "WebhookIn";

/// The response header that a business service created in a CSP process sets from its SuperSession.
Parameter SUPERSESSIONHEADER = "VND.InterSystems.Ensemble.SuperSession";

/// The most characters of a status text that the 503 console line holds.
Parameter LOGSTATUSMAX = 200;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/:ref" Method="POST" Call="Receive"/>
</Routes>
}

/// Lets the dispatch decide: the default check needs Read on the data database, which the unauthenticated user does not hold.
ClassMethod AccessCheck(Output authorized As %Boolean = 0) As %Status
{
	Set authorized = 1
	Quit $SYSTEM.Status.OK()
}

/// The status line of every answer, with no body: the cause of an error is never sent. A 405 is answered as 404.
ClassMethod ReportHttpStatusCode(pHttpStatus, pSC As %Status = {$$$OK}) As %Status
{
	Set %response.Status = $Select(+pHttpStatus = 405: ..#HTTP404NOTFOUND, 1: pHttpStatus)
	Quit $SYSTEM.Status.OK()
}

/// A method that the route does not take is 404, and the Allow header that the superclass would send is not.
ClassMethod Http405(pSupportedVerbs As %String = "") As %Status
{
	Quit ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
}

/// POST /<ref>: see the class description.
ClassMethod Receive(ref As %String) As %Status
{
	If ..OnlineDemo() Quit ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
	Set now = ..Now()
	Set row = ##class(OcuTalon.Data.Webhook).Lookup($Get(ref))
	Set slot = $Select($IsObject(row): row.Ref, 1: "?")
	If '..Authenticated(row, ..Secret()) Quit ..Rejected(slot, now, ..#HTTP401UNAUTHORIZED)
	If ..BodySize() > ##class(OcuTalon.Data.Webhook).#BODYMAX Quit ..Rejected(slot, now, ..#HTTP413CONTENTTOOLARGE)
	If '..JsonBody(.text) Quit ..Rejected(slot, now, ..#HTTP400BADREQUEST)
	If '##class(OcuTalon.Data.Webhook).Accept(row.Ref, now, .retryAfter) {
		Do %response.SetHeader("Retry-After", retryAfter)
		Quit ..Rejected(slot, now, ..#HTTP429TOOMANYREQUESTS)
	}
	Set event = ##class(OcuTalon.Channel.Webhook.Event).%New()
	Set event.SessionRef = row.SessionRef
	Set event.Name = row.Name
	Set event.Text = text
	Try {
		Set sc = ..Hand(event)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Do %response.DeleteHeader(..#SUPERSESSIONHEADER)
	If $SYSTEM.Status.IsError(sc) {
		Do ##class(OcuTalon.Data.Webhook).Unaccept(row.Ref, now)
		Do ..Log("OcuTalon.Web.Hook: "_..#SERVICE_" unavailable for webhook "_row.Ref_": "_$Extract($Translate($SYSTEM.Status.GetErrorText(sc), $Char(13, 10), "  "), 1, ..#LOGSTATUSMAX))
		Quit ..ReportHttpStatusCode(..#HTTP503SERVICEUNAVAILABLE)
	}
	Quit ..ReportHttpStatusCode(..#HTTP202ACCEPTED)
}

/// 1 when the row exists, its owning session has a row and the secret is the one that its hash was made from. The hash of an unknown Ref is DUMMYHASH, so the
/// comparison runs in every case, and the answer does not tell which of the reasons it was.
ClassMethod Authenticated(row As OcuTalon.Data.Webhook, secret As %String) As %Boolean [ Private ]
{
	Set stored = $Select($IsObject(row): row.SecretHash, 1: ##class(OcuTalon.Data.Webhook).#DUMMYHASH)
	Set matched = ..Compare(stored, secret)
	Quit matched && $IsObject(row) && ##class(OcuTalon.Data.Session).RefIndexExists(row.SessionRef)
}

/// The one constant-time comparison of the hook: Data.Webhook Matches. A test subclass overrides it to see which hash a request was compared against.
ClassMethod Compare(stored As %String, secret As %String) As %Boolean [ Private ]
{
	Quit ##class(OcuTalon.Data.Webhook).Matches(stored, secret)
}

/// The one audit write of the hook: Data.Webhook RecordRejection. A test subclass overrides it.
ClassMethod Audit(slot As %String, count As %Integer) As %Status [ Private ]
{
	Quit ##class(OcuTalon.Data.Webhook).RecordRejection(slot, count)
}

/// Counts the rejection in its slot, writes the audit entry when one is due, and answers with the status line.
ClassMethod Rejected(slot As %String, now As %String, status As %String) As %Status [ Private ]
{
	Try {
		If ##class(OcuTalon.Data.Webhook).Reject(slot, now, .count) {
			Set sc = ..Audit(slot, count)
			If $SYSTEM.Status.IsError(sc) Do ..Log("OcuTalon.Web.Hook: a rejection audit entry could not be written")
		}
	} Catch {
		Do ..Log("OcuTalon.Web.Hook: a rejection could not be counted")
	}
	Quit ..ReportHttpStatusCode(status)
}

/// 1 when the body is a JSON object or array, with its text (UTF-8 decoded) in text; otherwise 0. A form body is never JSON, whatever CSP parsed.
ClassMethod JsonBody(Output text As %String) As %Boolean [ Private ]
{
	Set text = ""
	If ..IsForm() Quit 0
	Try {
		Set text = ..BodyText()
		Set parsed = ##class(%DynamicAbstractObject).%FromJSON(text)
		Set valid = $IsObject(parsed)
	} Catch {
		Set valid = 0
	}
	Quit valid
}

/// The webhook's secret from the request header, "" when there is none.
ClassMethod Secret() As %String [ Private ]
{
	Quit %request.GetCgiEnv(..#SECRETVARIABLE)
}

/// The size of the body in bytes, before anything is read: the larger of the stream's size and the declared content length.
ClassMethod BodySize() As %Integer [ Private ]
{
	Set content = %request.Content
	Set size = $Select($IsObject(content): +content.Size, 1: 0)
	Set declared = +%request.GetCgiEnv("CONTENT_LENGTH")
	Quit $Select(declared > size: declared, 1: size)
}

/// 1 when the request's content type is a form (urlencoded or multipart).
ClassMethod IsForm() As %Boolean [ Private ]
{
	Set type = $ZConvert($ZStrip($Piece(%request.ContentType, ";", 1), "<>W"), "L")
	Quit (type = "application/x-www-form-urlencoded") || ($Extract(type, 1, 10) = "multipart/")
}

/// The body decoded from UTF-8 to text. It is called only for a body of at most BODYMAX bytes.
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

/// Hands the event to WebhookIn: the service is created in this process and takes the event with ProcessInput, so that the Item enters the production through its
/// business service (AD-1). An error status means that the event did not reach the production. A test subclass overrides it.
ClassMethod Hand(event As OcuTalon.Channel.Webhook.Event) As %Status [ Private ]
{
	Set sc = ##class(Ens.Director).CreateBusinessService(..#SERVICE, .service)
	If $SYSTEM.Status.IsError(sc) Quit sc
	Quit service.ProcessInput(event, .output)
}

/// The current UTC time. A test subclass overrides it.
ClassMethod Now() As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Time).NowUtc()
}

/// 1 when the online-demo flag is set. A test subclass overrides it.
ClassMethod OnlineDemo() As %Boolean [ Private ]
{
	Quit (##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1)
}

/// One line of the console log. It never holds a header, the body, a secret or the caller's address. A test subclass overrides it.
ClassMethod Log(text As %String) [ Private ]
{
	Try {
		Do ##class(%SYS.System).WriteToConsoleLog(text, 0, 1)
	} Catch {
	}
}

}
