/// The History page's routes of /ocutalon/api (Story 25.2; AD-4, AD-13, AD-20, AD-26, AD-27), forwarded from OcuTalon.Web.Api's URL map
/// (<Map Prefix="/v1/history">), so the role check and the browser envelope run again in the forwarded dispatch:
///   - GET /v1/history/decisions?outcome=&channel=&day=&fallback=&page= answers 200 {"page","pages","decisions":[...]} for the CSP session's own decide
///     decisions only (Ownership.HistoryDecisions; the session's Ref comes from the CSP session, never from the request), newest first, 25 to a page. Each
///     decision is {ref, outcome, reasons, fallback, fallbackReason, itemSummary, recordedAt, channel, traceUrl, confidence, costUSD}: the payload of the rail's
///     decision row (Live.Payload.Decision.FromRow, its trace URL added by TraceLink) with the channel of the decision's usage rows, "" for a decision that no
///     model call served; traceUrl appears only when it could be built, confidence and costUSD only when set. outcome is ignore, digest, tellnow or act (tellnow
///     also matches every fallback decision), channel a Msg.Enum CHANNEL, day an instance-zone date YYYY-MM-DD, fallback yes or no, page 1 to 9999 with no leading zero.
///   - GET /v1/history/incidents?page= answers 200 {"page","pages","incidents":[...]} for the incidents the session sees (Ownership.HistoryIncidents), newest
///     first, 25 to a page. Each incident is {ref, state, fallback, count, itemNoun, firstAt, noticedAt, closedAt, summary, traceUrl}: summary is the stored
///     summary of the incident as text (Watch.Summary.Text for the web), "" when none is stored or it cannot be rendered; closedAt is "" while the incident is
///     open; traceUrl appears only when it could be built.
///   - A page past the last answers 200 with an empty list and the page count. Any other value of a known parameter (an empty value, a second value, a
///     misspelt word, a date the zone does not read) is 404 not_found and nothing is read; an unknown parameter is ignored.
///   - A session or a read that fails is 500 server_error.
/// No row id, SessionRef, owner, user name, ItemId or trace header id is in the body. The routes read only and publish nothing.
Class OcuTalon.Web.History Extends OcuTalon.Web.Api
{

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/decisions" Method="GET" Call="Decisions"/>
<Route Url="/incidents" Method="GET" Call="Incidents"/>
</Routes>
}

/// GET /v1/history/decisions: see the class description.
ClassMethod Decisions() As %Status
{
	Set outcome = "", channel = "", day = "", fallback = "", page = 1
	If '..ParamOf("outcome", ##class(OcuTalon.Msg.Enum).#OUTCOME, .outcome) || '..ParamOf("channel", ##class(OcuTalon.Msg.Enum).#CHANNEL, .channel) || '..ParamOf("fallback", "yes,no", .fallback) || '..DayParam(.day) || '..PageParam(.page) {
		Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	}
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set rows = ##class(OcuTalon.Data.Ownership).HistoryDecisions(sessionRef, outcome, channel, day, fallback, page, .pages, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set decisions = []
	Try {
		Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
		For i = 1:1:rows.Count() {
			Set row = rows.GetAt(i)
			Set channelOf = ##class(OcuTalon.Data.Ownership).DecisionChannel(row.Ref, sessionRef, .sc)
			Do ..Check(sc)
			Set json = ..PayloadObject(##class(OcuTalon.Live.Payload.Decision).FromRow(row))
			Do ##class(OcuTalon.Web.TraceLink).Add(json, .viewer)
			Set item = {}
			Do item.%Set("ref", row.Ref)
			Do item.%Set("outcome", row.Outcome)
			Do item.%Set("reasons", row.Reasons)
			Do item.%Set("fallback", (row.Fallback = 1), "boolean")
			Do item.%Set("fallbackReason", row.FallbackReason)
			Do item.%Set("itemSummary", row.Summary)
			Do item.%Set("recordedAt", row.RecordedAt)
			Do item.%Set("channel", channelOf)
			If json.%Get("traceUrl") '= "" Do item.%Set("traceUrl", json.%Get("traceUrl"))
			If row.Confidence '= "" Do item.%Set("confidence", row.Confidence, "number")
			If row.CostUSD '= "" Do item.%Set("costUSD", row.CostUSD, "number")
			Do decisions.%Push(item)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set %response.ContentType = ..#CONTENTTYPE
	Write {"page": (page), "pages": (pages), "decisions": (decisions)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// GET /v1/history/incidents: see the class description.
ClassMethod Incidents() As %Status
{
	Set page = 1
	If '..PageParam(.page) Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set rows = ##class(OcuTalon.Data.Ownership).HistoryIncidents(sessionRef, page, .pages, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set incidents = []
	Try {
		Do ##class(OcuTalon.Web.TraceLink).Viewer(.viewer)
		For i = 1:1:rows.Count() {
			Set row = rows.GetAt(i)
			Set item = {}
			Do item.%Set("ref", row.Ref)
			Do item.%Set("state", row.State)
			Do item.%Set("fallback", (row.Fallback = 1), "boolean")
			Do item.%Set("count", +row.Count, "number")
			Set noun = ..Noun(row.ItemNoun)
			If $IsObject(noun) Do item.%Set("itemNoun", noun)
			Do item.%Set("firstAt", row.FirstAt)
			Do item.%Set("noticedAt", row.NoticedAt)
			Do item.%Set("closedAt", row.ClosedAt)
			Do item.%Set("summary", ..SummaryText(row))
			Set url = ##class(OcuTalon.Web.TraceLink).Url(row.TraceHeaderId, $Namespace, , , .viewer)
			If url '= "" Do item.%Set("traceUrl", url)
			Do incidents.%Push(item)
		}
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set %response.ContentType = ..#CONTENTTYPE
	Write {"page": (page), "pages": (pages), "incidents": (incidents)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

/// 1 when the query parameter name is absent (value stays "") or holds exactly one value that is one of the comma-separated allowed values (value is then
/// that value); 0 for any other value, an empty one and a second value included.
ClassMethod ParamOf(name As %String, allowed As %String, Output value As %String) As %Boolean [ Private ]
{
	Set value = ""
	If '%request.IsDefined(name) Quit 1
	If %request.Count(name) '= 1 Quit 0
	Set value = %request.Get(name)
	Quit $ListFind($ListFromString(allowed), value) > 0
}

/// 1 when day is absent (value stays "") or exactly one YYYY-MM-DD that the instance zone reads (Data.Time.FromLocal); 0 for anything else.
ClassMethod DayParam(Output value As %String) As %Boolean [ Private ]
{
	Set value = ""
	If '%request.IsDefined("day") Quit 1
	If %request.Count("day") '= 1 Quit 0
	Set value = %request.Get("day")
	If value '? 4N1"-"2N1"-"2N Quit 0
	Quit ##class(OcuTalon.Data.Time).FromLocal(value_"T00:00:00") '= ""
}

/// 1 when page is absent (value stays 1) or exactly one whole number from 1 to the highest page, with no leading zero; 0 for anything else.
ClassMethod PageParam(Output value As %Integer) As %Boolean [ Private ]
{
	Set value = 1
	If '%request.IsDefined("page") Quit 1
	If %request.Count("page") '= 1 Quit 0
	Set text = %request.Get("page")
	If (text '? 1.4N) || (+text '= text) || (text < 1) || (text > ##class(OcuTalon.Data.Ownership).#HISTORYPAGEMAX) Quit 0
	Set value = +text
	Quit 1
}

/// The item noun of an incident row as {"one","other"}, "" when the row has none or it cannot be read (Live.Payload.Incident.FromRow's shape).
ClassMethod Noun(stored As %String) As %DynamicObject [ Private ]
{
	If stored = "" Quit ""
	Set noun = ""
	Try {
		Set read = ##class(%DynamicObject).%FromJSON(stored)
		Set noun = {"one": (read.one), "other": (read.other)}
	} Catch {
		Set noun = ""
	}
	Quit noun
}

/// The stored summary of the incident as text, "" when there is none or it cannot be rendered. The row was read through Ownership.
ClassMethod SummaryText(row As OcuTalon.Data.Incident) As %String [ Private ]
{
	If row.Summary = "" Quit ""
	Set text = ##class(OcuTalon.Watch.Summary).Text(row.Ref, "web", .sc)
	Quit $Select($SYSTEM.Status.IsOK(sc): text, 1: "")
}

}
