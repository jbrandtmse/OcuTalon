/// The usage route of /ocutalon/api (Story 37.2; AD-4, AD-13, AD-18, AD-20), forwarded from OcuTalon.Web.Api's URL map
/// (<Map Prefix="/v1/usage">), so the role check and the browser envelope run again in the forwarded dispatch:
///   - GET /v1/usage?days=1|7|30 answers 200 {"days","limit","buckets"} for the CSP session's own Usage rows only (Ownership.Usage; the session's
///     Ref comes from the CSP session, never from the request). days is the local dates of the range, oldest first and today last. limit is the
///     request-size limit, Decide's MAXREQUESTTOKENS. buckets holds one object for each distinct (day, agent, channel, model, estimated):
///     {"day","agent","channel","model","estimated","inputTokens","outputTokens","cacheReadTokens","cacheWriteTokens","costUSD","largestRequestTokens"}.
///     No ref, row id, owner or user name is in the body.
///   - A missing days means 7. Any other value than exactly 1, 7 or 30 (0, 31, abc, an empty value) is 404 not_found, and nothing is read.
///   - A session or a read that fails is 500 server_error.
/// The route reads only and publishes nothing.
Class OcuTalon.Web.Usage Extends OcuTalon.Web.Api
{

/// The range, in days, when the request has none.
Parameter DEFAULTDAYS = 7;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="" Method="GET" Call="Read"/>
</Routes>
}

/// GET /v1/usage: see the class description.
ClassMethod Read() As %Status
{
	Set days = $Select(%request.IsDefined("days"): %request.Get("days"), 1: ..#DEFAULTDAYS)
	If (days '= "1") && (days '= "7") && (days '= "30") Quit ..Fail(404, "not_found", ..#MESSAGENOTFOUND)
	Set sessionRef = ##class(OcuTalon.Data.Ownership).SessionRef(.sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set usage = ##class(OcuTalon.Data.Ownership).Usage(sessionRef, days, .sc)
	If $SYSTEM.Status.IsError(sc) Quit ..ServerError(sc)
	Set %response.ContentType = ..#CONTENTTYPE
	Write {"days": (usage.days), "limit": (##class(OcuTalon.Bridge.Process.Decide).#MAXREQUESTTOKENS), "buckets": (usage.buckets)}.%ToJSON()
	Quit $SYSTEM.Status.OK()
}

}
