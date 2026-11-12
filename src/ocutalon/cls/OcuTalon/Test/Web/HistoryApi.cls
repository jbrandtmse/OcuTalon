/// Tests of the history routes (Story 25.2; AD-1, AD-4, AD-13, AD-20, AD-26, AD-27), called with stand-in request and response objects and a CSP session whose
/// OcuTalon.SessionRef is a fixture session (as Test.Web.UsageApi does). Safe on a slot: no production is needed. The rows are fixtures (Test.Data.Fixture),
/// removed after every test.
///   - TestDispatch: Web.Api forwards /v1/history to Web.History, whose routes are GET /decisions and GET /incidents; /v1/historyx is no route, POST is no route,
///     and the whole chain from Web.Api is refused 403 no_role by the forwarded dispatch in a process that lacks the OcuTalon user role;
///   - TestBadParams: every bad value of a known parameter is 404 not_found with the notes route's body; unknown parameters are ignored;
///   - TestDecisionsShape: 200 application/json; the top-level keys are exactly page, pages and decisions, every decision's keys are the contract's, and no
///     SessionRef, user name, row id, ownerRef, itemId, traceHeaderId or kind is in the body; a decision with no usage row has the channel "";
///   - TestFilters: the filters through the route, a second page of 26 rows, a page past the last (200 with an empty list), the order;
///   - TestIncidentsShape: the incident keys, the stored summary as text, "" for no summary and for one that cannot be rendered, closedAt "" while open;
///   - TestIsolation: another session's rows, eval's and instance's never appear in either list;
///   - TestNoSession: a CSP session with no OcuTalon session of the signed-in user is 500 server_error.
Class OcuTalon.Test.Web.HistoryApi Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Web.History";

/// The keys of a decision of the body, in the order the route writes them.
Parameter DECISIONKEYS = "ref,outcome,reasons,fallback,fallbackReason,itemSummary,recordedAt,channel,traceUrl,confidence,costUSD";

/// The keys of an incident of the body, in the order the route writes them.
Parameter INCIDENTKEYS = "ref,state,fallback,count,itemNoun,firstAt,noticedAt,closedAt,summary,traceUrl";

/// The run's number.
Property Number As %Integer;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

/// The Refs of the fixture sessions of the test, comma-separated.
Property Sessions As %String(MAXLEN = "");

/// The Refs of the fixture rows of the test, comma-separated.
Property Refs As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("HistoryApi", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	If ..Sessions '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Sessions)
	Set ..Sessions = "", ..Refs = ""
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $$$OK
}

/// The map, the forwarded class and its two routes.
Method TestDispatch()
{
	Set sc = ##class(%CSP.REST).ParseUrlMap("OcuTalon.Web.Api", .routes)
	Do $$$AssertStatusOK(sc, "Web.Api's URL map parses")
	Set maps = 0
	Set i = ""
	For {
		Set i = $Order(routes(i), 1, route)
		Quit:i=""
		If (route.type = "M") && (route.url = "/v1/history") {
			Set maps = maps + 1
			Set map = route
		}
	}
	Do $$$AssertEquals(maps, 1, "Web.Api's URL map holds exactly one Map for /v1/history")
	Do $$$AssertEquals(map.forward, "OcuTalon.Web.History", "it forwards to Web.History")
	Set matcher = ##class(%Regex.Matcher).%New(map.regex)
	Do $$$AssertTrue(matcher.Match("/v1/history"), "the prefix itself matches")
	Do $$$AssertTrue(matcher.Match("/v1/history/decisions"), "and a path under it")
	Do $$$AssertTrue('matcher.Match("/v1/historyx"), "a longer word does not")
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Test.Web.Api).Routes("OcuTalon.Web.History"), "|"), "GET /decisions Decisions|GET /incidents Incidents", "Web.History's routes: GET /decisions and GET /incidents")

	Set route = ##class(OcuTalon.Web.History).DispatchMap("/decisions", "GET", .verbs, .args)
	Do $$$AssertEquals($ListGet(route, 1)_"|"_$ListGet(route, 2)_"|"_$ListGet(route, 3), "R|Decisions|OcuTalon.Web.History", "GET /decisions is Decisions")
	Set route = ##class(OcuTalon.Web.History).DispatchMap("/incidents", "GET", .verbs, .args)
	Do $$$AssertEquals($ListGet(route, 1)_"|"_$ListGet(route, 2)_"|"_$ListGet(route, 3), "R|Incidents|OcuTalon.Web.History", "GET /incidents is Incidents")
	For path = "/decisions", "/incidents" {
		Set route = ##class(OcuTalon.Web.History).DispatchMap(path, "POST", .verbs, .args)
		Do $$$AssertEquals(route, "", "POST "_path_" is no route")
	}
	For path = "", "/", "/zzRef", "/decisions/x", "/incidents/x" {
		Set route = ##class(OcuTalon.Web.History).DispatchMap(path, "GET", .verbs, .args)
		Do $$$AssertEquals(route, "", "GET '"_path_"' is no route")
	}

	New %request, %response, %session
	Set %request = ..Envelope("GET")
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set holds = ##class(OcuTalon.Web.Public.Shell).HasRole()
	Kill args, verbs
	Set sc = ##class(OcuTalon.Test.Web.Api).Capture(.capture)
	Set route = ""
	Try {
		Set route = ##class(OcuTalon.Web.Api).DispatchMap("/v1/history/decisions", "GET", .verbs, .args)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Set written = ##class(OcuTalon.Test.Web.Api).Collect(.capture)
	Do $$$AssertStatusOK(sc, "GET /v1/history/decisions dispatches without an error")
	If holds {
		Do $$$AssertEquals($ListGet(route, 1)_"|"_$ListGet(route, 2)_"|"_$ListGet(route, 3), "R|Decisions|OcuTalon.Web.History", "GET /v1/history/decisions from Web.Api reaches Web.History.Decisions")
	} Else {
		Do $$$AssertEquals($ListGet(route, 1)_"|"_$ListGet(route, 2), "M|OcuTalon.Web.History", "GET /v1/history/decisions from Web.Api is forwarded to Web.History, whose dispatch ran")
		Do $$$AssertTrue(written [ """no_role""", "and refused the caller who lacks the OcuTalon user role: "_written)
	}
}

/// Every bad value of a known parameter is 404 not_found and reads nothing; an unknown parameter is ignored.
Method TestBadParams()
{
	Set a = ..Session()
	Do ..Dec(a, "act", 0, "web")
	Set notFound = {"error": {"code": "not_found", "message": "OcuTalon has nothing at this address."}}.%ToJSON()
	Set bad = $ListBuild("outcome=foo", "outcome=", "outcome=Act", "outcome=ACT", "outcome=tell now", "outcome=act&outcome=ignore", "channel=x", "channel=", "channel=Web", "channel=web,phone", "fallback=1", "fallback=0", "fallback=", "fallback=Yes", "fallback=true", "fallback=yes&fallback=no", "day=2026-13-01", "day=2026-02-30", "day=11/10/2026", "day=", "day=2026-1-1", "day=20261110", "day=2026-11-10T00:00:00", "day=today", "page=0", "page=01", "page=abc", "page=10000", "page=", "page=-1", "page=1.5", "page=+1", "page=1e1", "page=1&page=2", "page=99999")
	Set position = 0
	While $ListNext(bad, position, query) {
		For route = "Decisions", "Incidents" {
			If (route = "Incidents") && ($Piece(query, "=", 1) '= "page") Continue
			Set body = ..Call(a, route, query, .response)
			Do $$$AssertEquals(response.Status, "404 Not Found", route_" ?"_query_": 404")
			Do $$$AssertEquals(body, notFound, route_" ?"_query_": not_found")
		}
	}
	For query = "foo=1", "foo=", "sessionRef="_a, "ownerRef=eval", "page=1&foo=bar", "outcome=act&limit=1000" {
		Set body = ..Call(a, "Decisions", query, .response)
		Do $$$AssertEquals(response.Status, "200 OK", "?"_query_": an unknown parameter is ignored: "_body)
	}
	Set body = ..Call(a, "Incidents", "outcome=nonsense&channel=x", .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the incidents route takes only page: the decision filters are unknown there")
}

/// The decisions body: its keys are an allow-list, so that no row id, SessionRef, owner, user name, ItemId or trace header id can appear.
Method TestDecisionsShape()
{
	Set a = ..Session()
	Set ref = ..Dec(a, "act", 0, "mailbox", "2030-01-01T10:00:00Z", {"Confidence": ".85", "CostUSD": ".002", "Reasons": "Needs a reply.", "FallbackReason": ""})
	Set bare = ..Dec(a, "tellnow", 1, "", "2029-01-01T10:00:00Z", {"FallbackReason": "no_key", "Confidence": "", "CostUSD": ""})
	Set body = ..Call(a, "Decisions", "", .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "200 JSON")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(..KeysOf(answer), "page,pages,decisions", "the top level holds exactly page, pages and decisions, in that order")
	Do $$$AssertEquals(answer.page_"|"_answer.pages_"|"_answer.decisions.%Size(), "1|1|2", "page 1 of 1 with two decisions")
	Set first = answer.decisions.%Get(0)
	Do $$$AssertEquals(..KeysOf(first), ..#DECISIONKEYS, "a full decision holds exactly the eleven keys")
	Do $$$AssertEquals(first.ref_"|"_first.outcome_"|"_first.reasons_"|"_first.fallback_"|"_first.channel, ref_"|act|Needs a reply.|0|mailbox", "a decision's values")
	Do $$$AssertEquals(first.%GetTypeOf("fallback"), "boolean", "fallback is a JSON boolean")
	Do $$$AssertEquals(first.confidence_"|"_first.costUSD_"|"_first.recordedAt, ".85|.002|2030-01-01T10:00:00Z", "confidence and cost are set")
	Do $$$AssertEquals(first.%GetTypeOf("confidence")_"|"_first.%GetTypeOf("costUSD"), "number|number", "and numbers")
	Do $$$AssertTrue(first.traceUrl [ "SESSIONID=42", "the trace URL is the rail's: "_first.traceUrl)
	Set second = answer.decisions.%Get(1)
	Do $$$AssertEquals(second.ref, bare, "the older decision is second")
	Do $$$AssertEquals(..KeysOf(second), "ref,outcome,reasons,fallback,fallbackReason,itemSummary,recordedAt,channel,traceUrl", "a decision with no confidence and no cost has neither key")
	Do $$$AssertEquals(second.channel_"|"_second.%GetTypeOf("channel"), "|string", "a decision with no usage row has the channel """"")
	Do $$$AssertEquals(second.fallback_"|"_second.fallbackReason, "1|no_key", "its fallback and reason")
	Set low = $ZConvert(body, "L")
	Do $$$AssertTrue(body '[ a, "the body holds no SessionRef")
	Do $$$AssertTrue(body '[ $Username, "the body holds no user name")
	Do $$$AssertTrue(low '[ """id""", "the body holds no row id")
	Do $$$AssertTrue(low '[ "ownerref", "the body holds no ownerRef")
	Do $$$AssertTrue(low '[ "itemid", "the body holds no itemId")
	Do $$$AssertTrue(low '[ "traceheaderid", "the body holds no traceHeaderId")
	Do $$$AssertTrue(low '[ """kind""", "the body holds no kind")
	Do $$$AssertTrue(low '[ "tracenamespace", "the body holds no traceNamespace")
	Set empty = ..Call(..Session(), "Decisions", "", .response)
	Do $$$AssertEquals(response.Status_"|"_empty, "200 OK|"_{"page": 1, "pages": 1, "decisions": []}.%ToJSON(), "a session with none: 200, one page, no decision")
}

/// The filters through the route, the second of two pages and a page past the last.
Method TestFilters()
{
	Set a = ..Session()
	Set today = ..LocalDate(0), yesterday = ..LocalDate(1)
	Do ..Dec(a, "ignore", 0, "web", ..Utc(today, "10:00:00"))
	Do ..Dec(a, "digest", 0, "mailbox", ..Utc(today, "11:00:00"))
	Do ..Dec(a, "digest", 1, "", ..Utc(yesterday, "10:00:00"))
	Do ..Dec(a, "tellnow", 0, "phone", ..Utc(yesterday, "11:00:00"))
	Do ..Dec(a, "act", 0, "mailbox", ..Utc(yesterday, "12:00:00"))
	Do ..AssertSummaries(a, "", "digest|ignore|act|tellnow|digest", "no filter")
	Do ..AssertSummaries(a, "outcome=digest", "digest", "outcome digest: the fallback digest is a Tell now")
	Do ..AssertSummaries(a, "outcome=tellnow", "tellnow|digest", "outcome tellnow: the stored one and the fallback")
	Do ..AssertSummaries(a, "fallback=yes", "digest", "fallback yes")
	Do ..AssertSummaries(a, "fallback=no", "digest|ignore|act|tellnow", "fallback no")
	Do ..AssertSummaries(a, "channel=mailbox", "digest|act", "channel mailbox")
	Do ..AssertSummaries(a, "channel=phone", "tellnow", "channel phone")
	Do ..AssertSummaries(a, "day="_yesterday, "act|tellnow|digest", "day yesterday")
	Do ..AssertSummaries(a, "outcome=act&channel=mailbox&day="_yesterday_"&fallback=no", "act", "all four filters")
	Do ..AssertSummaries(a, "outcome=act&channel=web", "", "no match")
	Set body = ..Call(a, "Decisions", "outcome=act&channel=web", .response)
	Do $$$AssertEquals(body, {"page": 1, "pages": 1, "decisions": []}.%ToJSON(), "no match: 200 with one page and an empty list")

	Set b = ..Session()
	Set base = ##class(OcuTalon.Data.Time).FromLocal(yesterday_"T01:00:00")
	For i = 1:1:26 Do ..Dec(b, "act", 0, "mailbox", ##class(OcuTalon.Data.Time).AddSeconds(base, i * 60), {"Summary": ("zz p"_i)})
	Set body = ..Call(b, "Decisions", "outcome=act&channel=mailbox&page=2", .response)
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(response.Status_"|"_answer.page_"|"_answer.pages_"|"_answer.decisions.%Size()_"|"_answer.decisions.%Get(0).itemSummary, "200 OK|2|2|1|zz p1", "page 2 of 26: the oldest row, two pages")
	Set answer = {}.%FromJSON(..Call(b, "Decisions", "page=1", .response))
	Do $$$AssertEquals(answer.decisions.%Size()_"|"_answer.decisions.%Get(0).itemSummary_"|"_answer.decisions.%Get(24).itemSummary, "25|zz p26|zz p2", "page 1: 25 rows, newest first")
	For page = 3, 9999 {
		Set body = ..Call(b, "Decisions", "page="_page, .response)
		Do $$$AssertEquals(response.Status, "200 OK", "page "_page_": 200")
		Do $$$AssertEquals(body, {"page": (page), "pages": 2, "decisions": []}.%ToJSON(), "page "_page_": an empty list and the page count")
	}
}

/// The incidents body: the keys, the stored summary as text, "" for none and for one that cannot be rendered, closedAt "" while open, and the paging.
Method TestIncidentsShape()
{
	Set a = ..Session()
	Set summary = "{""parts"":[{""key"":""summary.noFixRan"",""slots"":{}}],""lines"":[]}"
	Set noun = "{""one"":""order"",""other"":""orders""}"
	Set closed = ..Inc(a, ..Utc(..LocalDate(2), "09:00:00"), {"State": "closed", "ClosedAt": "2030-01-01T11:00:00Z", "Summary": (summary), "ItemNoun": (noun), "TraceHeaderId": 77, "Count": 4})
	Set open = ..Inc(a, ..Utc(..LocalDate(1), "09:00:00"), {"State": "open", "Fallback": 1})
	Set broken = ..Inc(a, ..Utc(..LocalDate(0), "09:00:00"), {"State": "closed", "Summary": "not json"})
	Set body = ..Call(a, "Incidents", "", .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "200 JSON")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(..KeysOf(answer), "page,pages,incidents", "the top level holds exactly page, pages and incidents, in that order")
	Do $$$AssertEquals(answer.page_"|"_answer.pages_"|"_answer.incidents.%Size(), "1|1|3", "page 1 of 1 with three incidents")
	Do $$$AssertEquals(answer.incidents.%Get(0).ref_"|"_answer.incidents.%Get(1).ref_"|"_answer.incidents.%Get(2).ref, broken_"|"_open_"|"_closed, "newest noticed first")
	Set row = answer.incidents.%Get(2)
	Do $$$AssertEquals(..KeysOf(row), ..#INCIDENTKEYS, "a closed incident with a summary holds exactly the ten keys")
	Do $$$AssertEquals(row.state_"|"_row.fallback_"|"_row.count_"|"_row.itemNoun.one_"|"_row.itemNoun.other, "closed|0|4|order|orders", "its values")
	Do $$$AssertEquals(row.%GetTypeOf("fallback")_"|"_row.%GetTypeOf("count"), "boolean|number", "fallback is a boolean and count a number")
	Do $$$AssertEquals(row.firstAt_"|"_row.closedAt, "2030-01-01T09:00:00Z|2030-01-01T11:00:00Z", "its times")
	Do $$$AssertEquals(row.summary, "No fix ran, so nothing was changed.", "the stored summary is rendered as text")
	Do $$$AssertTrue(row.traceUrl [ "SESSIONID=77", "the trace URL is the diagnosis session's: "_row.traceUrl)
	Set row = answer.incidents.%Get(1)
	Do $$$AssertEquals(row.closedAt_"|"_row.summary_"|"_row.state_"|"_row.fallback, "||open|1", "an open fallback incident: closedAt and summary are """", fallback is true")
	Do $$$AssertEquals(..KeysOf(row), "ref,state,fallback,count,firstAt,noticedAt,closedAt,summary", "and has no itemNoun and no traceUrl (no header id, no noun)")
	Set row = answer.incidents.%Get(0)
	Do $$$AssertEquals(row.summary, "", "a summary that cannot be rendered is """", never a 500")
	Set low = $ZConvert(body, "L")
	Do $$$AssertTrue(body '[ a, "the body holds no SessionRef")
	Do $$$AssertTrue(body '[ $Username, "the body holds no user name")
	Do $$$AssertTrue(low '[ """id""", "the body holds no row id")
	Do $$$AssertTrue(low '[ "ownerref", "the body holds no ownerRef")
	Do $$$AssertTrue(low '[ "traceheaderid", "the body holds no traceHeaderId")
	Do $$$AssertTrue(low '[ "zzns", "the body holds no namespace")
	Do $$$AssertTrue(low '[ "zz.production", "the body holds no production")
	Set empty = ..Call(..Session(), "Incidents", "", .response)
	Do $$$AssertEquals(response.Status_"|"_empty, "200 OK|"_{"page": 1, "pages": 1, "incidents": []}.%ToJSON(), "a session with none: 200, one page, no incident")
	Set b = ..Session()
	Set base = ##class(OcuTalon.Data.Time).NowUtc()
	For i = 1:1:26 Do ..Inc(b, ##class(OcuTalon.Data.Time).AddSeconds(base, -i * 60), {"Count": (i)})
	Set answer = {}.%FromJSON(..Call(b, "Incidents", "page=2", .response))
	Do $$$AssertEquals(answer.page_"|"_answer.pages_"|"_answer.incidents.%Size()_"|"_answer.incidents.%Get(0).count, "2|2|1|26", "page 2 of 26: the oldest incident")
	Set body = ..Call(b, "Incidents", "page=9999", .response)
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|"_{"page": 9999, "pages": 2, "incidents": []}.%ToJSON(), "a page past the last: 200 with an empty list")
}

/// Another session's rows, eval's and instance's never appear in either list.
Method TestIsolation()
{
	Set a = ..Session(), b = ..Session()
	Do ..Dec(a, "act", 0, "web", , {"Summary": "zz mine"})
	Do ..Dec(b, "act", 0, "web", , {"Summary": "zz theirs"})
	Do ..Dec("eval", "act", 0, "web", , {"Summary": "zz eval"})
	Do ..Dec("instance", "act", 0, "web", , {"Summary": "zz instance"})
	Do ..Inc(a, ##class(OcuTalon.Data.Time).NowUtc(), {"Count": 11})
	Do ..Inc(b, ##class(OcuTalon.Data.Time).NowUtc(), {"Count": 22})
	Do ..Inc("eval", ##class(OcuTalon.Data.Time).NowUtc(), {"Count": 33})
	Do ..Inc("instance", ##class(OcuTalon.Data.Time).NowUtc(), {"Count": 44})
	Do ..Inc(a, "", {"Count": 55})
	For query = "", "outcome=act", "outcome=act&channel=web&fallback=no" {
		Do ..AssertSummaries(a, query, "zz mine", "A sees its own decision only ("_query_")")
		Do ..AssertSummaries(b, query, "zz theirs", "B sees its own decision only ("_query_")")
	}
	Set answer = {}.%FromJSON(..Call(a, "Incidents", "", .response))
	Do $$$AssertEquals(answer.incidents.%Size()_"|"_answer.incidents.%Get(0).count, "1|11", "A sees its own noticed incident only")
	Set answer = {}.%FromJSON(..Call(b, "Incidents", "", .response))
	Do $$$AssertEquals(answer.incidents.%Size()_"|"_answer.incidents.%Get(0).count, "1|22", "B sees its own incident only")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Set answer = {}.%FromJSON(..Call(a, "Incidents", "", .response))
	Do $$$AssertEquals(answer.incidents.%Size()_"|"_answer.incidents.%Get(0).count, "1|11", "on a local install A still sees none of eval's and none of the instance's of an unwatched production")
}

/// A session that can't be read is 500 server_error.
Method TestNoSession()
{
	For route = "Decisions", "Incidents" {
		Set body = ..Call("zzNoSuchSession", route, "", .response)
		Do $$$AssertEquals(+response.Status, 500, route_": 500")
		Do $$$AssertEquals({}.%FromJSON(body).error.code, "server_error", route_": server_error")
	}
}

/// --- helpers ---
/// The local date YYYY-MM-DD of today minus ago days.
ClassMethod LocalDate(ago As %Integer) As %String [ Private ]
{
	Set today = $Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()), "T", 1)
	Quit $ZDate($ZDateH(today, 3) - ago, 3)
}

/// The UTC time of the local date and time hms.
ClassMethod Utc(date As %String, hms As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Time).FromLocal(date_"T"_hms)
}

/// A fixture session of the IRIS user who runs the tests; returns its Ref.
Method Session() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Quit ref
}

/// A decide decision of the owner with the outcome and fallback flag, summary "zz "_outcome unless fields says otherwise, and a usage row of the channel when it is
/// not ""; returns its Ref.
Method Dec(owner As %String, outcome As %String, fallback As %Boolean, channel As %String, at As %String = {##class(OcuTalon.Data.Time).NowUtc()}, fields As %DynamicObject = "") As %String [ Private ]
{
	Set all = {"Outcome": (outcome), "Fallback": (fallback), "Summary": ("zz "_outcome)}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.name, .value) {
			Do all.%Set(name, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, "decide", at, all)
	Set ..Refs = ..Refs_","_ref
	If channel '= "" Do ##class(OcuTalon.Test.Data.Fixture).Usage(ref, owner, {"Channel": (channel), "RecordedAt": (at)})
	Quit ref
}

/// An incident of the owner noticed at noticedAt ("" for none), with the fields set after the defaults (FirstAt 2030-01-01T09:00:00Z, State open); returns its Ref.
Method Inc(owner As %String, noticedAt As %String, fields As %DynamicObject = "") As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(owner, noticedAt, , , fields)
	Set ..Refs = ..Refs_","_ref
	Quit ref
}

/// The itemSummary of page 1 of the decisions the query gives, newest first, joined with "|", equal to expected.
Method AssertSummaries(session As %String, query As %String, expected As %String, message As %String) [ Private ]
{
	Set body = ..Call(session, "Decisions", query, .response)
	Do $$$AssertEquals(response.Status, "200 OK", message_": 200: "_body)
	Set list = {}.%FromJSON(body).decisions
	Set text = ""
	For i = 0:1:list.%Size() - 1 Set text = text_$Select(text = "": "", 1: "|")_$Replace(list.%Get(i).itemSummary, "zz ", "")
	Do $$$AssertEquals(text, $Replace(expected, "zz ", ""), message)
}

/// Calls the route (Decisions or Incidents) as the CSP session of the session with the query string; response is the %response.
Method Call(session As %String, route As %String, query As %String, Output response) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", "GET")
	For i = 1:1:$Length(query, "&") {
		Set pair = $Piece(query, "&", i)
		If pair = "" Continue
		Set name = $Piece(pair, "=", 1)
		Do %request.Set(name, $Piece(pair, "=", 2, *), %request.Count(name) + 1)
	}
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzHistoryApi"_..Number, 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, route)
	Do $$$AssertStatusOK(sc, route_" returns OK")
	Set response = %response
	Quit written
}

/// The member names of an object, comma-separated, in order.
ClassMethod KeysOf(object As %DynamicObject) As %String [ Private ]
{
	Set keys = ""
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Quit keys
}

/// A request that keeps the browser envelope (a GET needs none, but the dispatch reads these parts).
ClassMethod Envelope(method As %String) As OcuTalon.Test.Web.StubRequest [ Private ]
{
	Quit ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", method, "application/json", "1", "http://localhost:52773", "localhost:52773")
}

}
