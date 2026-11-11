/// Tests of the usage route (Story 37.2; AD-1, AD-4, AD-13, AD-20), called with stand-in request and response objects and a CSP session whose
/// OcuTalon.SessionRef is a fixture session (as Test.Web.DocumentsApi does). Safe on a slot: no production is needed. The Usage rows are fixtures
/// (Test.Data.Fixture.Usage) under one tag, and the sessions are fixture rows, removed after every test.
///   - TestDispatch: Web.Api forwards /v1/usage to Web.Usage, whose one route is GET of the empty remainder to Read; the whole chain from Web.Api
///     reaches Read in a process that holds the OcuTalon user role and is refused 403 no_role by the forwarded dispatch in one that lacks it;
///   - TestDays: no days is 7 days; 1, 7 and 30 are accepted with that many dates; 0, 5, 31, abc, an empty value and other spellings of a number are 404
///     not_found with the notes route's body, and nothing is read;
///   - TestShape: 200 application/json; the top-level keys are exactly days, limit and buckets, every bucket's keys are exactly the eleven of the contract,
///     limit is Decide's MAXREQUESTTOKENS, and no Ref, row id, user name or SessionRef is in the body;
///   - TestIsolation: another session's rows, eval's and instance's never appear in the body;
///   - TestNoSession: a CSP session with no OcuTalon session of the signed-in user is 500 server_error;
///   - TestFailedRead: a usage read that fails (a row whose time cannot be read) is 500 server_error, never an empty range;
///   - TestDayEdge: the day edge, the first-day and tomorrow bounds, the retry runner's stored agent and a NULL cost, through the route, in a zone
///     whose midnight is not the UTC midnight.
Class OcuTalon.Test.Web.UsageApi Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Web.Usage";

/// The eleven keys of a bucket, in the order the route writes them.
Parameter BUCKETKEYS = "day,agent,channel,model,estimated,inputTokens,outputTokens,cacheReadTokens,cacheWriteTokens,costUSD,largestRequestTokens";

/// The run's number.
Property Number As %Integer;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

/// The tag the fixture Usage rows are recorded under.
Property Tag As %String;

/// The Refs of the fixture sessions of the test, comma-separated.
Property Sessions As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("UsageApi", "n"))
	Set ..Tag = "zzusageapi"_..Number
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
	Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Tag)
	If ..Sessions '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Sessions)
	Set ..Sessions = ""
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Quit $$$OK
}

/// The map, the forwarded class and its one route.
Method TestDispatch()
{
	Set sc = ##class(%CSP.REST).ParseUrlMap("OcuTalon.Web.Api", .routes)
	Do $$$AssertStatusOK(sc, "Web.Api's URL map parses")
	Set maps = 0
	Set i = ""
	For {
		Set i = $Order(routes(i), 1, route)
		Quit:i=""
		If (route.type = "M") && (route.url = "/v1/usage") {
			Set maps = maps + 1
			Set map = route
		}
	}
	Do $$$AssertEquals(maps, 1, "Web.Api's URL map holds exactly one Map for /v1/usage")
	Do $$$AssertEquals(map.forward, "OcuTalon.Web.Usage", "it forwards to Web.Usage")
	Set matcher = ##class(%Regex.Matcher).%New(map.regex)
	Do $$$AssertTrue(matcher.Match("/v1/usage"), "the prefix itself matches")
	Do $$$AssertTrue('matcher.Match("/v1/usagex"), "a longer word does not")
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Test.Web.Api).Routes("OcuTalon.Web.Usage"), "|"), "GET  Read", "Web.Usage's routes: GET of the empty remainder")

	Set route = ##class(OcuTalon.Web.Usage).DispatchMap("", "GET", .verbs, .args)
	Do $$$AssertEquals($ListGet(route, 1)_"|"_$ListGet(route, 2)_"|"_$ListGet(route, 3), "R|Read|OcuTalon.Web.Usage", "GET of the empty remainder is Read")
	Set route = ##class(OcuTalon.Web.Usage).DispatchMap("", "POST", .verbs, .args)
	Do $$$AssertEquals(route, "", "POST is no route")
	Set route = ##class(OcuTalon.Web.Usage).DispatchMap("/zzRef", "GET", .verbs, .args)
	Do $$$AssertEquals(route, "", "a path after the prefix is no route")

	New %request, %response, %session
	Set %request = ..Envelope("GET")
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set holds = ##class(OcuTalon.Web.Public.Shell).HasRole()
	Kill args, verbs
	Set sc = ##class(OcuTalon.Test.Web.Api).Capture(.capture)
	Set route = ""
	Try {
		Set route = ##class(OcuTalon.Web.Api).DispatchMap("/v1/usage", "GET", .verbs, .args)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Set written = ##class(OcuTalon.Test.Web.Api).Collect(.capture)
	Do $$$AssertStatusOK(sc, "GET /v1/usage dispatches without an error")
	If holds {
		Do $$$AssertEquals($ListGet(route, 1)_"|"_$ListGet(route, 2)_"|"_$ListGet(route, 3), "R|Read|OcuTalon.Web.Usage", "GET /v1/usage from Web.Api reaches Web.Usage.Read")
	} Else {
		Do $$$AssertEquals($ListGet(route, 1)_"|"_$ListGet(route, 2), "M|OcuTalon.Web.Usage", "GET /v1/usage from Web.Api is forwarded to Web.Usage, whose dispatch ran")
		Do $$$AssertTrue(written [ """no_role""", "and refused the caller who lacks the OcuTalon user role: "_written)
	}
}

/// The range: absent is 7; 1, 7 and 30 are accepted; anything else is 404 not_found and reads nothing.
Method TestDays()
{
	Set a = ..Session()
	Set body = ..Call(a, , .response, 0)
	Do $$$AssertEquals(response.Status, "200 OK", "no days: 200: "_body)
	Do $$$AssertEquals({}.%FromJSON(body).days.%Size(), 7, "no days means 7 dates")
	For days = 1, 7, 30 {
		Set body = ..Call(a, days, .response)
		Do $$$AssertEquals(response.Status, "200 OK", "days="_days_": 200: "_body)
		Do $$$AssertEquals({}.%FromJSON(body).days.%Size(), days, "days="_days_": that many dates")
	}
	Set notFound = {"error": {"code": "not_found", "message": "OcuTalon has nothing at this address."}}.%ToJSON()
	For days = 0, 5, 31, "abc", "", -1, "07", " 7", "7 ", "7.0", "1e1", "8", "29", "100", "7,30", "all" {
		Set body = ..Call(a, days, .response)
		Do $$$AssertEquals(response.Status, "404 Not Found", "days='"_days_"': 404")
		Do $$$AssertEquals(body, notFound, "days='"_days_"': not_found")
	}
}

/// The 200 body: its keys are an allow-list, so that no ref, row id, user name or SessionRef can appear.
Method TestShape()
{
	Set a = ..Session()
	Do ..Row(a, "ChatAgent", "web", "zz-usage-model-a", 0, 120, 30, 20, 10, ".5", 4321)
	Do ..Row(a, "compaction", "web", "zz-usage-model-a", 1, 80, 20, 0, 0, ".25", 1500)
	Set body = ..Call(a, 7, .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "200 JSON")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(..KeysOf(answer), "days,limit,buckets", "the top level holds exactly days, limit and buckets, in that order")
	Do $$$AssertEquals(answer.limit, ##class(OcuTalon.Bridge.Process.Decide).#MAXREQUESTTOKENS, "limit is Decide's MAXREQUESTTOKENS")
	Do $$$AssertEquals(answer.limit, 100000, "which is 100000")
	Do $$$AssertEquals(answer.buckets.%Size(), 2, "two buckets")
	Set today = $Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()), "T", 1)
	Do $$$AssertEquals(answer.days.%Get(6), today, "today is the last date")
	For i = 0:1:answer.buckets.%Size() - 1 {
		Do $$$AssertEquals(..KeysOf(answer.buckets.%Get(i)), ..#BUCKETKEYS, "bucket "_i_" holds exactly the eleven keys")
	}
	Set chat = answer.buckets.%Get(0)
	Do $$$AssertEquals(chat.agent_"|"_chat.channel_"|"_chat.model_"|"_chat.estimated_"|"_chat.inputTokens_"|"_chat.outputTokens_"|"_chat.cacheReadTokens_"|"_chat.cacheWriteTokens_"|"_+chat.costUSD_"|"_chat.largestRequestTokens, "ChatAgent|web|zz-usage-model-a|0|120|30|20|10|.5|4321", "a bucket's values")
	Do $$$AssertEquals(answer.buckets.%Get(1).agent_"|"_answer.buckets.%Get(1).estimated, "compaction|1", "the compaction row is its own estimated bucket")
	Do $$$AssertEquals(answer.buckets.%Get(1).%GetTypeOf("estimated"), "boolean", "estimated is a JSON boolean")
	Do $$$AssertTrue(body '[ a, "the body holds no SessionRef")
	Do $$$AssertTrue(body '[ $Username, "the body holds no user name")
	Do $$$AssertTrue(body '[ ..Tag, "the body holds no fixture Ref")
	Do $$$AssertTrue($ZConvert(body, "L") '[ "ref", "the body holds nothing named ref")
	Do $$$AssertTrue($ZConvert(body, "L") '[ """id""", "the body holds no row id")
	Set empty = ..Call(..Session(), 7, .response)
	Do $$$AssertEquals(response.Status_"|"_{}.%FromJSON(empty).buckets.%ToJSON(), "200 OK|[]", "a session with none: 200 and buckets []")
}

/// Another session's rows and those of eval and instance never appear.
Method TestIsolation()
{
	Set a = ..Session(), b = ..Session()
	Do ..Row(a, "ChatAgent", "web", "zz-usage-model-a", 0, 10, 1, 0, 0, ".1", 100)
	Do ..Row(b, "ChatAgent", "web", "zz-usage-model-b", 0, 20, 2, 0, 0, ".2", 200)
	Do ..Row("eval", "ChatAgent", "web", "zz-usage-model-eval", 0, 30, 3, 0, 0, ".3", 300)
	Do ..Row("instance", "ChatAgent", "web", "zz-usage-model-instance", 0, 40, 4, 0, 0, ".4", 400)
	Set body = ..Call(a, 7, .response)
	Do $$$AssertEquals(..Models(body), "zz-usage-model-a", "A sees its own row only")
	Set body = ..Call(b, 7, .response)
	Do $$$AssertEquals(..Models(body), "zz-usage-model-b", "B sees its own row only")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Set body = ..Call(a, 7, .response)
	Do $$$AssertEquals(..Models(body), "zz-usage-model-a", "on a local install A still sees its own row only, not the instance's")
}

/// A session that can't be read is 500 server_error.
Method TestNoSession()
{
	Set body = ..Call("zzNoSuchSession", 7, .response)
	Do $$$AssertEquals(+response.Status, 500, "500")
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "server_error", "server_error")
}

/// A read that fails is 500 server_error: a row of the session whose time cannot be read fails Ownership.Usage, and the route answers the error,
/// never 200 with an empty range.
Method TestFailedRead()
{
	Set a = ..Session()
	Set utc = ##class(OcuTalon.Data.Time).FromLocal(..LocalDate(0)_"T12:30:00")
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(..Tag, a, {"RecordedAt": ($Extract(utc, 1, 19)_"X"), "InputTokens": 1})
	Set body = ..Call(a, 7, .response)
	Do $$$AssertEquals(+response.Status, 500, "500: "_body)
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "server_error", "server_error")
}

/// The I/O matrix's day edge, null cost and retry runner rows, through the route, in a process zone whose midnight is not the UTC
/// midnight: a row at local 23:59:59 of day D and one at local 00:00:00 of day D+1 are in two buckets, D and D+1; a row before the first day's midnight
/// and one at the first instant of tomorrow are left out; the retry runner keeps its stored agent; a row with no cost counts 0 in costUSD. The zone, the
/// InstanceZone row and the private state of Bridge.Time are put back whatever happens.
Method TestDayEdge()
{
	Set saved = ##class(OcuTalon.Test.Bridge.ZoneCase).CurrentZone()
	Set zoneRow = ##class(OcuTalon.Test.Bridge.ZoneCase).ForgetZoneRow()
	Try {
		Do $SYSTEM.Process.TimeZone("Pacific/Auckland")
		Kill ^||OcuTalon.Bridge.Time
		Do ..DayEdgeIn()
	} Catch exception {
		Do $$$AssertStatusOK(exception.AsStatus(), "the day edge test ran without an error")
	}
	Do ##class(OcuTalon.Test.Bridge.ZoneCase).RestoreZoneRow(zoneRow)
	Kill ^||OcuTalon.Bridge.Time
	Do ##class(OcuTalon.Test.Bridge.ZoneCase).PutZone(saved)
}

/// TestDayEdge's body, in the zone the test set.
Method DayEdgeIn() [ Private ]
{
	Set a = ..Session()
	Set d0 = ..LocalDate(0), d1 = ..LocalDate(1), d6 = ..LocalDate(6)
	Do ..RowAt(a, ..LocalDate(7), "23:59:59", "TriageAgent", "zz-usage-edge", 1000, ".1")
	Do ..RowAt(a, d6, "00:00:00", "TriageAgent", "zz-usage-edge", 6, ".06")
	Do ..RowAt(a, d1, "23:59:59", "TriageAgent", "zz-usage-edge", 10, ".01")
	Do ..RowAt(a, d0, "00:00:00", "ChatAgentRetry", "zz-usage-edge", 20, "")
	Do ..RowAt(a, ..LocalDate(-1), "00:00:00", "TriageAgent", "zz-usage-edge", 5000, ".5")
	Set body = ..Call(a, 7, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "days=7: 200: "_body)
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.days.%Get(0)_"|"_answer.days.%Get(6), d6_"|"_d0, "days=7 lists the 6 days before today and today")
	Do $$$AssertEquals(answer.buckets.%Size(), 3, "three buckets: the row before the first day's midnight and the one at the first instant of tomorrow are left out")
	Set first = answer.buckets.%Get(0), second = answer.buckets.%Get(1), third = answer.buckets.%Get(2)
	Do $$$AssertEquals(first.day_"|"_first.inputTokens, d6_"|6", "the row at local 00:00:00 of the first day is in")
	Do $$$AssertEquals(second.day_"|"_second.agent_"|"_second.inputTokens_"|"_+second.costUSD, d1_"|TriageAgent|10|.01", "the row at local 23:59:59 is in day D's bucket")
	Do $$$AssertEquals(third.day_"|"_third.agent_"|"_third.inputTokens, d0_"|ChatAgentRetry|20", "the row at local 00:00:00 is in day D+1's bucket, and the retry runner keeps its stored agent")
	Do $$$AssertEquals(+third.costUSD, 0, "a row with no cost counts 0")
	Do $$$AssertEquals(third.%GetTypeOf("costUSD"), "number", "and costUSD is a number")
	Set body = ..Call(a, 1, .response)
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.days.%Size()_"|"_answer.buckets.%Size()_"|"_answer.buckets.%Get(0).agent, "1|1|ChatAgentRetry", "days=1 holds today's row only: yesterday's 23:59:59 row is out")
}

/// --- helpers ---
/// The local date YYYY-MM-DD of today minus ago days (a negative ago is after today), in the process zone.
ClassMethod LocalDate(ago As %Integer) As %String [ Private ]
{
	Set today = $Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()), "T", 1)
	Quit $ZDate($ZDateH(today, 3) - ago, 3)
}

/// A Usage row of the owner at the local time date, hms; cost "" is NULL.
Method RowAt(owner As %String, date As %String, hms As %String, agent As %String, model As %String, inTokens As %Integer, cost As %String) [ Private ]
{
	Set fields = {"Agent": (agent), "Channel": "web", "Model": (model), "InputTokens": (inTokens), "OutputTokens": 0, "CacheReadTokens": 0, "CacheWriteTokens": 0, "LargestRequestTokens": (inTokens), "RequestCount": 1}
	Set fields.RecordedAt = ##class(OcuTalon.Data.Time).FromLocal(date_"T"_hms)
	If cost '= "" Set fields.CostUSD = cost
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(..Tag, owner, fields)
}

/// A fixture session of the IRIS user who runs the tests; returns its Ref.
Method Session() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Quit ref
}

/// A Usage row of the owner recorded now.
Method Row(owner As %String, agent As %String, channel As %String, model As %String, estimated As %Boolean, inTokens As %Integer, outTokens As %Integer, cacheRead As %Integer, cacheWrite As %Integer, cost As %String, largest As %Integer) [ Private ]
{
	Set fields = {"Agent": (agent), "Channel": (channel), "Model": (model), "Estimated": (estimated), "InputTokens": (inTokens), "OutputTokens": (outTokens), "CacheReadTokens": (cacheRead), "CacheWriteTokens": (cacheWrite), "LargestRequestTokens": (largest), "CostUSD": (cost), "RequestCount": 1}
	Do ##class(OcuTalon.Test.Data.Fixture).Usage(..Tag, owner, fields)
}

/// Calls Read as the CSP session of the session with the query value days (no query value when hasDays is 0); response is the %response.
Method Call(session As %String, days As %String = "", Output response, hasDays As %Boolean = 1) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", "GET")
	If hasDays Do %request.Set("days", days)
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzUsageApi"_..Number, 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, "Read")
	Do $$$AssertStatusOK(sc, "Read returns OK")
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

/// The distinct models of a body's buckets, sorted, comma-separated.
ClassMethod Models(body As %String) As %String [ Private ]
{
	Kill seen
	Set buckets = {}.%FromJSON(body).buckets
	For i = 0:1:buckets.%Size() - 1 Set seen(buckets.%Get(i).model) = ""
	Set text = "", model = ""
	For {
		Set model = $Order(seen(model))
		If model = "" Quit
		Set text = text_$Select(text = "": "", 1: ",")_model
	}
	Quit text
}

/// A request that keeps the browser envelope (a GET needs none, but the dispatch reads these parts).
ClassMethod Envelope(method As %String) As OcuTalon.Test.Web.StubRequest [ Private ]
{
	Quit ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", method, "application/json", "1", "http://localhost:52773", "localhost:52773")
}

}
