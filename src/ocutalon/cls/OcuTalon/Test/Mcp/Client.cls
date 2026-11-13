/// OcuTalon's MCP probe (Story 22.9; AD-6, AD-19, AD-21, AD-22): OcuTalon.Mcp.Client Probe and OcuTalon.Mcp.Attach Probe against the loopback mock of
/// OcuTalon.Test.Mcp.Mock, which each test starts and stops. The tests need neither the production nor a model, so they run on a warm throwaway and in CI.
///   - TestSilent: a mock that reads the request and never answers gives unreachable within 6 seconds (the probe's limit is 2);
///   - TestAnswers: a mock that answers gives an empty string, and logs exactly one initialize whose header check says absent (no credential is sent) and whose
///     client is iris (the probe's own %Net.HttpRequest, not AI Hub's client);
///   - TestRefused: a port with no listener gives unreachable within 3 seconds;
///   - TestNotUsable: a url that is not http:// or https:// with a host and no user information, and an empty url, give failed, and nothing is sent;
///   - TestStatusIsAnAnswer: a mock that answers 401, 403 and 503 gives an empty string (any HTTP status is an answer, and a server that wants a credential answers 401);
///   - TestEndpoint: the host, port, scheme and path of an http:// and an https:// url (the scheme's default port, a query kept, a query straight after the host, a
///     fragment dropped, an underscore in the host, a bracketed IPv6 address; a broken bracket or port is not usable), and an https url
///     against the plain mock gives unreachable (the probe speaks TLS and not plain HTTP), and against a silent mock gives unreachable within 6 seconds, the TLS handshake included;
///   - TestNoAuthorization: the mock checks the Authorization header and says absent for the probe's request (the credential a real server wants is never sent);
///   - TestRedirectNotFollowed: a server that answers 302 Found with a Location that names a second mock gives an empty string (a status is an answer), and the second
///     mock gets no request (the probe follows no redirect);
///   - TestStalledBody: a mock that sends the status line and the headers of an event stream (200 OK) and then no body, for longer than the probe's limit, gives an
///     empty string within 6 seconds (the status line is an answer, although Post fails with a read timeout on the body);
///   - TestStalledBodyKeepsStatus: the platform fact that Probe rests on: %Net.HttpRequest Post returns an error for such a mock and its HttpResponse still holds the
///     status 200;
///   - TestAttachProbe: Attach Probe gives failed for an entry that does not exist and an empty string for an entry whose url is the mock;
///   - Story 22.3 (ListTool and CallTool, with the mock's Call, Pages and Session modes): TestListTool (a tool is found with its description and input schema after one initialize, the
///     notification and one tools/list, all from the client iris; a tool the server does not list is notfound; the credential header reaches the server on every request),
///     TestListToolPages (a tool on the second and on the third page is found by following nextCursor; a server whose pages never end is notfound after MAXPAGES pages), TestListToolBody
///     (an answer as a one-event text/event-stream body is read like a JSON body; an HTTP error status and an empty body are failed),
///     TestSession (the Mcp-Session-Id of initialize goes back on the notification, the tools/list and the tools/call), TestCallTool (the text result, an event stream, the arguments
///     as given, a result with isError true, a JSON-RPC error and an HTTP status that is not 2xx: only the text of a result that is not an error is returned, and the text of a failure
///     never), TestCallToolSilent (a server that reads tools/call and never answers gives timeout within CALLSECONDS + 3 seconds, and unreachable when it is gone), TestCredentialHeader (a header
///     with a control character, an empty value or a name that is no token is failed and nothing is sent), and TestNothingLeaks (no answer holds the url, the credential or the text of a failure);
///   - TestHttpsVerifiesTheServer (Story 22.3, condition (b)): the request that Probe, ListTool and CallTool share for an https url speaks TLS with the installer's client SSL
///     configuration, which verifies the server's certificate (VerifyPeer on, no accept-any setting), follows no redirect, and bounds the connection and the handshake by PROBESECONDS for a call
///     too; for an http url it names no SSL configuration;
///   - every test leaves no mock job, no mock node and no Config Store entry behind, and none of the answers holds the mock's address.
Class OcuTalon.Test.Mcp.Client Extends %UnitTest.TestCase
{

Parameter MOCK = "OcuTalon.Test.Mcp.Mock";

/// The most seconds a silent probe may take (the limit is 2, and the margin is for a loaded host).
Parameter SILENTBOUND = 6;

/// The most seconds a refused probe may take.
Parameter REFUSEDBOUND = 3;

/// The header the mock checks, and the value it expects: the probe sends neither.
Parameter HEADER = "X-Zz-Key";

/// The most seconds a tools/call to a silent server may take (CALLSECONDS is 20, and the margin is for a loaded host).
Parameter CALLBOUND = 23;

Property Port As %Integer [ InitialExpression = 0 ];

Property Number As %Integer;

/// The name of the fixture Config Store entry, "" when the test made none.
Property Entry As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Port = 0
	Set ..Entry = ""
	Set ..Number = $Increment(^OcuTalonTest("McpClient", "n"))
	Do ..Remove()
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Remove()
	Do $$$AssertEquals(..Leftovers(), "", "the test leaves no mock job, mock node or Config Store entry behind")
	Quit $$$OK
}

Method TestSilent()
{
	If '..StartMock() Quit
	Do $ClassMethod(..#MOCK, "Silence", ..Port)
	Set start = $ZHorolog
	Set answer = ##class(OcuTalon.Mcp.Client).Probe(..Url())
	Set elapsed = $ZHorolog - start
	Do $$$AssertEquals(answer, "unreachable", "a server that reads the request and never answers is unreachable")
	Do $$$AssertTrue(elapsed < ..#SILENTBOUND, "and the probe gives up within " _ ..#SILENTBOUND _ " seconds")
	Set requests = $ClassMethod(..#MOCK, "Requests", ..Port)
	Do $$$AssertEquals(requests.%Size(), 1, "the mock read one request")
	If requests.%Size() = 0 Quit
	Do $$$AssertEquals(requests.%Get(0).method _ "|" _ requests.%Get(0).answered, "initialize|0", "an initialize, which it answered with nothing")
}

Method TestAnswers()
{
	If '..StartMock() Quit
	Set answer = ##class(OcuTalon.Mcp.Client).Probe(..Url())
	Do $$$AssertEquals(answer, "", "a server that answers is an empty string")
	Set requests = $ClassMethod(..#MOCK, "Requests", ..Port)
	Do $$$AssertEquals(requests.%Size(), 1, "and the mock logged one request")
	If requests.%Size() = 0 Quit
	Set request = requests.%Get(0)
	Do $$$AssertEquals(request.method _ "|" _ request.auth _ "|" _ request.client _ "|" _ request.answered, "initialize|absent|iris|1", "an initialize with no credential from OcuTalon's own client, which the mock answered")
}

Method TestRefused()
{
	If '..StartMock() Quit
	Do $ClassMethod(..#MOCK, "Stop", ..Port)
	Set start = $ZHorolog
	Set answer = ##class(OcuTalon.Mcp.Client).Probe(..Url())
	Set elapsed = $ZHorolog - start
	Do $$$AssertEquals(answer, "unreachable", "a port with no listener is unreachable")
	Do $$$AssertTrue(elapsed < ..#REFUSEDBOUND, "within " _ ..#REFUSEDBOUND _ " seconds")
}

Method TestNotUsable()
{
	If '..StartMock() Quit
	Set port = ..Port
	For url = "ftp://x", "", "localhost", "http://", "http://user:secret@127.0.0.1:" _ port _ "/mcp", "http://127.0.0.1:99999/mcp", "http://127.0.0.1:" _ port _ "/m cp", "file:///etc/passwd" {
		Do $$$AssertEquals(##class(OcuTalon.Mcp.Client).Probe(url), "failed", "a url that is not usable is failed (case " _ $Increment(case) _ ")")
	}
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Requests", port).%Size(), 0, "and nothing was sent to the mock")
}

Method TestStatusIsAnAnswer()
{
	If '..StartMock() Quit
	For line = "401 Unauthorized", "403 Forbidden", "503 Service Unavailable" {
		Do $ClassMethod(..#MOCK, "Status", ..Port, line)
		Do $$$AssertEquals(##class(OcuTalon.Mcp.Client).Probe(..Url()), "", "a server that answers " _ $Piece(line, " ") _ " is an answer")
	}
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Requests", ..Port).%Size(), 3, "the mock got the three requests")
}

Method TestEndpoint()
{
	Do $$$AssertEquals(..Split("https://example.com/mcp?x=1"), "example.com|443|1|/mcp?x=1", "an https url: the default port 443, the scheme, the path with its query")
	Do $$$AssertEquals(..Split("http://example.com"), "example.com|80|0|", "an http url with no path: the default port 80")
	Do $$$AssertEquals(..Split("HTTP://my_host:8080/a/b"), "my_host|8080|0|/a/b", "an underscore in the host, an explicit port and an upper-case scheme")
	Do $$$AssertEquals(..Split("https://example.com?x=1"), "example.com|443|1|/?x=1", "a query straight after the host gets the path /")
	Do $$$AssertEquals(..Split("http://[::1]:8080/mcp#part"), "[::1]|8080|0|/mcp", "a bracketed IPv6 address, which registration allows, and a fragment that is dropped")
	Do $$$AssertEquals(..Split("https://[::1]/mcp"), "[::1]|443|1|/mcp", "a bracketed IPv6 address with the default port")
	For url = "http://[::1/mcp", "http://::1/mcp", "http://[zz]/mcp", "http://example.com:/mcp" {
		Do $$$AssertEquals(..Split(url), "|||", "an address that is not usable (case " _ $Increment(case) _ ")")
	}
	If '..StartMock() Quit
	Set start = $ZHorolog
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Client).Probe("https://127.0.0.1:" _ ..Port _ "/mcp"), "unreachable", "an https url against a server that speaks plain HTTP is unreachable")
	Do $$$AssertTrue($ZHorolog - start < ..#SILENTBOUND, "within " _ ..#SILENTBOUND _ " seconds")
	Do $ClassMethod(..#MOCK, "Silence", ..Port, 12)
	Set start = $ZHorolog
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Client).Probe("https://127.0.0.1:" _ ..Port _ "/mcp"), "unreachable", "an https url against a server that accepts and never completes the handshake is unreachable")
	Do $$$AssertTrue($ZHorolog - start < ..#SILENTBOUND, "and the probe gives up within " _ ..#SILENTBOUND _ " seconds, the handshake included")
}

Method TestNoAuthorization()
{
	Set sc = $ClassMethod(..#MOCK, "Start", .port, , "Authorization", "Bearer zz" _ ..Number)
	Do $$$AssertStatusOK(sc, "the mock starts, checking the Authorization header")
	If $$$ISERR(sc) Quit
	Set ..Port = port
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Client).Probe(..Url()), "", "the server answers")
	Set requests = $ClassMethod(..#MOCK, "Requests", port)
	Do $$$AssertEquals(requests.%Size(), 1, "and the mock logged one request")
	If requests.%Size() Do $$$AssertEquals(requests.%Get(0).auth, "absent", "which carries no Authorization header")
}

Method TestRedirectNotFollowed()
{
	If '..StartMock() Quit
	Set sc = $ClassMethod(..#MOCK, "Start", .target)
	Do $$$AssertStatusOK(sc, "a second mock, the redirect target, starts")
	If $$$ISERR(sc) Quit
	Try {
		Do $ClassMethod(..#MOCK, "Status", ..Port, "302 Found", "http://127.0.0.1:" _ target _ "/mcp")
		Do $$$AssertEquals(##class(OcuTalon.Mcp.Client).Probe(..Url()), "", "a server that answers 302 Found has answered")
		Do $$$AssertEquals($ClassMethod(..#MOCK, "Requests", ..Port).%Size(), 1, "the first mock got the request")
		Do $$$AssertEquals($ClassMethod(..#MOCK, "Requests", target).%Size(), 0, "and the probe did not follow the redirect to the second mock")
	} Catch exception {
		Do $$$AssertEquals(exception.Name, "", "the test raised no exception")
	}
	Do $ClassMethod(..#MOCK, "Stop", target), $ClassMethod(..#MOCK, "Forget", target)
	Do $$$AssertTrue('$ClassMethod(..#MOCK, "Running", target) && '$Data(^IRIS.Temp.OcuTalonMcpMock(target)), "and the second mock leaves no job and no node behind")
}

Method TestStalledBody()
{
	If '..StartMock() Quit
	Do $ClassMethod(..#MOCK, "Stall", ..Port, 12)
	Set start = $ZHorolog
	Set answer = ##class(OcuTalon.Mcp.Client).Probe(..Url())
	Set elapsed = $ZHorolog - start
	Do $$$AssertTrue(elapsed < ..#SILENTBOUND, "a server that sends a status line and headers and then no body does not hold the probe past " _ ..#SILENTBOUND _ " seconds")
	Do $$$AssertEquals(answer, "", "and the status it sent is an answer, although its body never completed")
	Set requests = $ClassMethod(..#MOCK, "Requests", ..Port)
	Do $$$AssertEquals(requests.%Size(), 1, "the mock read one request")
	If requests.%Size() Do $$$AssertEquals(requests.%Get(0).method _ "|" _ requests.%Get(0).answered, "initialize|0", "an initialize, whose reply never completed")
}

Method TestStalledBodyKeepsStatus()
{
	If '..StartMock() Quit
	Do $ClassMethod(..#MOCK, "Stall", ..Port, 12)
	Set request = ##class(%Net.HttpRequest).%New()
	Set request.Server = "127.0.0.1"
	Set request.Port = ..Port
	Set request.OpenTimeout = 2
	Set request.Timeout = 2
	Set request.WriteTimeout = 2
	Set request.ContentType = "application/json"
	Do request.EntityBody.Write("{}")
	Set start = $ZHorolog
	Set sc = request.Post("/mcp")
	Do $$$AssertTrue($ZHorolog - start < ..#SILENTBOUND, "the request gives up within " _ ..#SILENTBOUND _ " seconds")
	Do $$$AssertTrue($$$ISERR(sc), "Post returns an error when the body never arrives")
	Do $$$AssertTrue($IsObject(request.HttpResponse), "and the request still holds a response")
	If $IsObject(request.HttpResponse) Do $$$AssertEquals(request.HttpResponse.StatusCode, 200, "whose status is the 200 that the server sent")
}

Method TestAttachProbe()
{
	If '..StartMock() Quit
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Attach).Probe("zzcli", "AI.MCP.OcuTalon_zzcli" _ ..Number _ "none"), "failed", "an entry that does not exist is failed")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Attach).Probe("zzcli", ""), "failed", "so is an empty config name")
	Do $$$AssertStatusOK(##class(%ConfigStore.DescriptorManager).RebuildRegistry(), "the Config Store registry is rebuilt")
	Set ..Entry = "AI.MCP.OcuTalon_zzcli" _ ..Number
	Do $$$AssertStatusOK(##class(%ConfigStore.Configuration).Create("AI", "MCP", "", "OcuTalon_zzcli" _ ..Number, {"transport": "remote", "url": (..Url()), "auth": {"type": "header", "name": (..#HEADER), "value": ("zz" _ ..Number)}}), "the fixture entry is made (it names a header, which the probe never sends)")
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Attach).Probe("zzcli", ..Entry), "", "an entry whose url is the mock gives an empty string")
	Set requests = $ClassMethod(..#MOCK, "Requests", ..Port)
	Do $$$AssertEquals(requests.%Size(), 1, "and the mock got one request")
	If requests.%Size() Do $$$AssertEquals(requests.%Get(0).client _ "|" _ requests.%Get(0).auth, "iris|absent", "from the probe, with no credential")
	Do $ClassMethod(..#MOCK, "Stop", ..Port)
	Do $$$AssertEquals(##class(OcuTalon.Mcp.Attach).Probe("zzcli", ..Entry), "unreachable", "the same entry gives unreachable once the mock is gone")
}

/// Story 22.3: ListTool finds the tool by its name with the server's definition. One initialize, the notification and one tools/list reach the mock, all from the client iris, and
/// each carries the credential header; a tool the server does not list is notfound, and an answer carries neither the url nor the credential.
Method TestListTool()
{
	If '..StartMock() Quit
	Set client = "OcuTalon.Mcp.Client"
	Set reason = $ClassMethod(client, "ListTool", ..Url(), ..Header(), "zz_lookup", .definition, .session)
	Do $$$AssertEquals(reason, "", "a tool that the server lists is found")
	Do $$$AssertEquals($IsObject(definition) && (definition.name = "zz_lookup"), 1, "with the server's definition")
	If $IsObject(definition) {
		Do $$$AssertEquals(definition.description, "Looks up a ticket.", "its description")
		Do $$$AssertEquals(definition.inputSchema.%ToJSON(), {"type": "object", "properties": {"id": {"type": "string"}}}.%ToJSON(), "and its input schema")
	}
	Do $$$AssertEquals(session, "", "a server that gives no session gives an empty one")
	Set requests = $ClassMethod(..#MOCK, "Requests", ..Port)
	Set methods = ""
	Set clients = ""
	Set auth = ""
	Set iterator = requests.%GetIterator()
	While iterator.%GetNext(, .request) {
		Set methods = methods _ $ListBuild(request.method)
		Set clients = clients _ $ListBuild(request.client)
		Set auth = auth _ $ListBuild(request.auth)
	}
	Do $$$AssertEquals($ListToString(methods), "initialize,notifications/initialized,tools/list", "the mock got an initialize, the notification and one tools/list")
	Do $$$AssertEquals($ListToString(clients), "iris,iris,iris", "all from OcuTalon's own client")
	Do $$$AssertEquals($ListToString(auth), "matched,matched,matched", "each with the credential header")
	Set reason = $ClassMethod(client, "ListTool", ..Url(), ..Header(), "zz_missing", .definition)
	Do $$$AssertEquals(reason _ "|" _ definition, "notfound|", "a tool that the server does not list is notfound, with no definition")
	Set reason = $ClassMethod(client, "ListTool", ..Url(), "", "zz_lookup", .definition)
	Do $$$AssertEquals(reason, "", "with no header the request carries none (the mock does not insist)")
	Set last = $ClassMethod(..#MOCK, "Requests", ..Port).%Size() - 1
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Requests", ..Port).%Get(last).auth, "absent", "and the mock says absent")
}

/// Story 22.3: ListTool follows nextCursor, page after page, until it finds the tool; a server whose pages never end is notfound after MAXPAGES (10) pages.
Method TestListToolPages()
{
	If '..StartMock($ListBuild("zz_x1", "zz_x2", "zz_x3")) Quit
	Set client = "OcuTalon.Mcp.Client"
	Do $ClassMethod(..#MOCK, "Pages", ..Port, 2)
	Do $$$AssertEquals($ClassMethod(client, "ListTool", ..Url(), ..Header(), "zz_x3", .definition), "", "a tool on the third page (five tools, two to a page) is found")
	Set lists = 0
	Set iterator = $ClassMethod(..#MOCK, "Requests", ..Port).%GetIterator()
	While iterator.%GetNext(, .request) {
		If request.method = "tools/list" Set lists = lists + 1
	}
	Do $$$AssertEquals(lists, 3, "after three tools/list requests")
	Do $$$AssertEquals($ClassMethod(client, "ListTool", ..Url(), ..Header(), "zz_lookup", .definition), "", "a tool on the first page is found at once")
	Do $$$AssertEquals($ClassMethod(client, "ListTool", ..Url(), ..Header(), "zz_none", .definition), "notfound", "a tool that no page lists is notfound")
	Do $ClassMethod(..#MOCK, "Forget", ..Port)
	Do $ClassMethod(..#MOCK, "Pages", ..Port, -1)
	Set before = $ClassMethod(..#MOCK, "Requests", ..Port).%Size()
	Do $$$AssertEquals($ClassMethod(client, "ListTool", ..Url(), ..Header(), "zz_never", .definition), "notfound", "a server whose pages never end is notfound")
	Set requests = $ClassMethod(..#MOCK, "Requests", ..Port)
	Set lists = 0
	Set iterator = requests.%GetIterator()
	While iterator.%GetNext(, .request) {
		If request.method = "tools/list" Set lists = lists + 1
	}
	Do $$$AssertEquals(lists, $Parameter(client, "MAXPAGES"), "after MAXPAGES pages")
}

/// Story 22.3: the answer as a one-event event stream is read like a JSON body; an HTTP error status and an empty body are failed.
Method TestListToolBody()
{
	If '..StartMock() Quit
	Set client = "OcuTalon.Mcp.Client"
	Do $ClassMethod(..#MOCK, "Call", ..Port, "sse")
	Do $$$AssertEquals($ClassMethod(client, "CallTool", ..Url(), ..Header(), "zz_lookup", {}, .result), "", "a tools/call answered as an event stream is read")
	Do $$$AssertEquals($IsObject(result) && (result.content.%Get(0).text = "The mock ran zz_lookup"), 1, "its result is the event's")
	Do $$$AssertEquals($ClassMethod(client, "ListTool", ..Url(), ..Header(), "zz_lookup", .definition), "", "a tools/list answered as an event stream is read")
	Do $$$AssertEquals($IsObject(definition) && (definition.name = "zz_lookup") && (definition.%GetTypeOf("inputSchema") = "object"), 1, "and its tool is the event's")
	Do $ClassMethod(..#MOCK, "Status", ..Port, "500 Internal Server Error")
	Do $$$AssertEquals($ClassMethod(client, "ListTool", ..Url(), ..Header(), "zz_lookup", .definition), "failed", "an HTTP error on initialize is failed")
	Do $ClassMethod(..#MOCK, "Status", ..Port, "404 Not Found")
	Do $$$AssertEquals($ClassMethod(client, "ListTool", ..Url(), ..Header(), "zz_lookup", .definition), "failed", "so is a 404")
	Do $ClassMethod(..#MOCK, "Stop", ..Port)
	Do $ClassMethod(..#MOCK, "Forget", ..Port)
	Do ..StartMock()
	Do $ClassMethod(..#MOCK, "Status", ..Port, "200 OK")
	Do $$$AssertEquals($ClassMethod(client, "ListTool", ..Url(), ..Header(), "zz_lookup", .definition), "failed", "an answer with no body is failed")
}

/// Story 22.3: the Mcp-Session-Id that initialize answers goes back on the notification, the tools/list and the tools/call.
Method TestSession()
{
	If '..StartMock() Quit
	Set client = "OcuTalon.Mcp.Client"
	Do $ClassMethod(..#MOCK, "Session", ..Port, "zzsession" _ ..Number)
	Do $$$AssertEquals($ClassMethod(client, "ListTool", ..Url(), ..Header(), "zz_lookup", .definition, .session), "", "the tool is found")
	Do $$$AssertEquals(session, "zzsession" _ ..Number, "and the session of the server is given back")
	Do $$$AssertEquals($ClassMethod(client, "CallTool", ..Url(), ..Header(), "zz_lookup", {}, .result, session), "", "the call is answered")
	Set seen = ""
	Set iterator = $ClassMethod(..#MOCK, "Requests", ..Port).%GetIterator()
	While iterator.%GetNext(, .request) {
		Set seen = seen _ $ListBuild(request.method _ "=" _ request.session)
	}
	Do $$$AssertEquals($ListToString(seen), "initialize=,notifications/initialized=zzsession" _ ..Number _ ",tools/list=zzsession" _ ..Number _ ",tools/call=zzsession" _ ..Number, "the initialize carried none, and every later request carried it")
}

/// Story 22.3: CallTool answers the result of a tool that ran with the arguments as given, within CALLSECONDS; the text of a result that is an error, of a JSON-RPC error and of an HTTP
/// error is never returned.
Method TestCallTool()
{
	If '..StartMock() Quit
	Set client = "OcuTalon.Mcp.Client"
	Set reason = $ClassMethod(client, "CallTool", ..Url(), ..Header(), "zz_lookup", {"id": "zzarg1"}, .result)
	Do $$$AssertEquals(reason, "", "a tool that ran is an empty reason")
	Do $$$AssertEquals($IsObject(result) && (result.content.%Get(0).text = "The mock ran zz_lookup"), 1, "with the server's result")
	Set requests = $ClassMethod(..#MOCK, "Requests", ..Port)
	Do $$$AssertEquals(requests.%Size() _ "|" _ requests.%Get(0).method _ "|" _ requests.%Get(0).tool _ "|" _ requests.%Get(0).client _ "|" _ requests.%Get(0).auth, "1|tools/call|zz_lookup|iris|matched", "the mock got one tools/call for the tool, from the client iris, with the credential header")
	Do $ClassMethod(..#MOCK, "Call", ..Port, "echo")
	Do $ClassMethod(client, "CallTool", ..Url(), ..Header(), "zz_lookup", {"id": "zzarg2", "n": 3}, .result)
	Do $$$AssertEquals($IsObject(result) && (result.content.%Get(0).text = ("echo:" _ {"id": "zzarg2", "n": 3}.%ToJSON())), 1, "the arguments reach the server as given")
	Do $ClassMethod(..#MOCK, "Call", ..Port, "mixed")
	Do $ClassMethod(client, "CallTool", ..Url(), ..Header(), "zz_lookup", {}, .result)
	Do $$$AssertEquals($IsObject(result) && (result.content.%Size() = 3), 1, "a result of three parts is returned whole")
	For mode = "iserror", "rpcerror" {
		Do $ClassMethod(..#MOCK, "Call", ..Port, mode)
		Set reason = $ClassMethod(client, "CallTool", ..Url(), ..Header(), "zz_lookup", {}, .result)
		Do $$$AssertEquals(reason _ "|" _ $IsObject(result), "failed|0", mode _ " is failed, with no result")
	}
	For line = "500 Internal Server Error", "401 Unauthorized", "404 Not Found" {
		Do $ClassMethod(..#MOCK, "Call", ..Port, "status", line)
		Set reason = $ClassMethod(client, "CallTool", ..Url(), ..Header(), "zz_lookup", {}, .result)
		Do $$$AssertEquals(reason _ "|" _ $IsObject(result), "failed|0", $Piece(line, " ") _ " is failed, with no result")
	}
	Do $ClassMethod(..#MOCK, "Call", ..Port, "long", 300000)
	Set reason = $ClassMethod(client, "CallTool", ..Url(), ..Header(), "zz_lookup", {}, .result)
	Do $$$AssertEquals(reason _ "|" _ $IsObject(result), "|1", "a long text is returned whole: the cut is the tool's")
	Do $$$AssertEquals(result.content.%Get(0).text, $Translate($Justify("", 300000), " ", "x"), "300,000 characters")
	Do $ClassMethod(..#MOCK, "Call", ..Port, "long", 1200000)
	Set reason = $ClassMethod(client, "CallTool", ..Url(), ..Header(), "zz_lookup", {}, .result)
	Do $$$AssertEquals(reason _ "|" _ $IsObject(result), "failed|0", "a body of more than MAXBODY characters is failed")
}

/// Story 22.3: a server that reads tools/call and never answers gives timeout within CALLSECONDS + 3 seconds; one that is gone gives unreachable.
Method TestCallToolSilent()
{
	If '..StartMock() Quit
	Set client = "OcuTalon.Mcp.Client"
	Do $ClassMethod(..#MOCK, "Silence", ..Port, 40)
	Set start = $ZHorolog
	Set reason = $ClassMethod(client, "CallTool", ..Url(), ..Header(), "zz_lookup", {}, .result)
	Set elapsed = $ZHorolog - start
	Do $$$AssertEquals(reason _ "|" _ $IsObject(result), "timeout|0", "a silent server is a timeout, with no result")
	Do $$$AssertTrue(elapsed < ..#CALLBOUND, "within " _ ..#CALLBOUND _ " seconds: " _ $Number(elapsed, 1))
	Do $$$AssertTrue(elapsed > ($Parameter(client, "CALLSECONDS") - 2), "and not before CALLSECONDS: a tool may take that long")
	Do $ClassMethod(..#MOCK, "Speak", ..Port)
	Do $ClassMethod(..#MOCK, "Stop", ..Port)
	Set start = $ZHorolog
	Set reason = $ClassMethod(client, "CallTool", ..Url(), ..Header(), "zz_lookup", {}, .result)
	Do $$$AssertEquals(reason, "unreachable", "a server that is gone is unreachable")
	Do $$$AssertTrue($ZHorolog - start < ..#REFUSEDBOUND, "at once")
}

/// Story 22.3: a header that holds a control character, an empty value or a name that is no token is failed and nothing is sent; a url that is not usable is failed too.
Method TestCredentialHeader()
{
	If '..StartMock() Quit
	Set client = "OcuTalon.Mcp.Client"
	Set bad = $ListBuild({"name": "X-Zz", "value": ("a" _ $Char(13, 10) _ "X-Evil: 1")}.%ToJSON(), {"name": "X-Zz", "value": ""}.%ToJSON(), {"name": "X Zz", "value": "a"}.%ToJSON(), {"name": "", "value": "a"}.%ToJSON(), {"name": "X-Zz"}.%ToJSON(), {"name": 5, "value": "a"}.%ToJSON(), {"name": "X-Zz", "value": ("a" _ $Char(0))}.%ToJSON())
	Set position = 0
	While $ListNext(bad, position, text) {
		Set header = {}.%FromJSON(text)
		Do $$$AssertEquals($ClassMethod(client, "ListTool", ..Url(), header, "zz_lookup", .definition), "failed", "the header " _ $Increment(case) _ " is failed")
		Do $$$AssertEquals($ClassMethod(client, "CallTool", ..Url(), header, "zz_lookup", {}, .result), "failed", "also for a call")
	}
	Do $$$AssertEquals($ClassMethod(client, "ListTool", "ftp://x", ..Header(), "zz_lookup", .definition), "failed", "a url that is not usable is failed")
	Do $$$AssertEquals($ClassMethod(client, "CallTool", "", ..Header(), "zz_lookup", {}, .result), "failed", "also for a call")
	Do $$$AssertEquals($ClassMethod(..#MOCK, "Requests", ..Port).%Size(), 0, "and nothing was sent to the mock")
}

/// Story 22.3: no answer of ListTool or CallTool holds the url, the credential or the text of a failing server.
Method TestNothingLeaks()
{
	If '..StartMock() Quit
	Set client = "OcuTalon.Mcp.Client"
	Set text = ""
	Do $ClassMethod(..#MOCK, "Call", ..Port, "iserror")
	Set text = text _ $ClassMethod(client, "CallTool", ..Url(), ..Header(), "zz_lookup", {}, .result) _ "|" _ $IsObject(result)
	Do $ClassMethod(..#MOCK, "Call", ..Port, "rpcerror")
	Set text = text _ $ClassMethod(client, "CallTool", ..Url(), ..Header(), "zz_lookup", {}, .result) _ "|" _ $IsObject(result)
	Set text = text _ $ClassMethod(client, "ListTool", ..Url(), ..Header(), "zz_none", .definition, .session) _ "|" _ session
	Do $$$AssertTrue(text '[ "mock-failure-text", "the text of a failing server is in no answer")
	Do $$$AssertTrue(text '[ "127.0.0.1", "nor the url")
	Do $$$AssertTrue(text '[ ("zz" _ ..Number), "nor the credential")
}

/// Story 22.3, condition (b): the request of an https url names the installer's client SSL configuration, which verifies the server; a call to a server that waits longer than the connection
/// limit for the answer still bounds the connection and the handshake by PROBESECONDS.
Method TestHttpsVerifiesTheServer()
{
	Set client = "OcuTalon.Mcp.Client"
	Do $$$AssertEquals($ClassMethod(client, "Open", "https://example.invalid:8443/mcp?x=1", 20, .request, .path, 2), 1, "an https url opens")
	Do $$$AssertEquals(request.Https _ "|" _ request.SSLConfiguration _ "|" _ request.Server _ "|" _ request.Port _ "|" _ path, "1|" _ ##class(OcuTalon.Install.Step.SSL).#NAME _ "|example.invalid|8443|/mcp?x=1", "it speaks TLS with the installer's client configuration")
	Do $$$AssertEquals(request.FollowRedirect _ "|" _ request.OpenTimeout _ "|" _ request.Timeout _ "|" _ request.WriteTimeout, "0|2|20|2", "follows no redirect, and bounds the connection and the handshake by 2 s and the answer by 20 s")
	Set name = ##class(OcuTalon.Install.Step.SSL).#NAME
	Do $$$AssertStatusOK(..SslProperties(name, .properties), "the configuration exists")
	Do $$$AssertEquals($Get(properties("VerifyPeer")) _ "|" _ $Get(properties("Type")) _ "|" _ $Get(properties("Enabled")), "1|0|1", "and it is a client configuration that verifies the server")
	Do $$$AssertEquals($ClassMethod(client, "Open", "http://127.0.0.1:1/mcp", 2, .plain, .path), 1, "an http url opens")
	Do $$$AssertEquals(+plain.Https _ "|" _ plain.SSLConfiguration, "0|", "and names no SSL configuration")
	Do $$$AssertEquals($ClassMethod(client, "Open", "https://user:pw@example.invalid/mcp", 2, .none, .path), 0, "a url with user information is not usable")
}

/// The properties of the SSL configuration of the name, read in %SYS.
ClassMethod SslProperties(name As %String, Output properties) As %Status [ Private ]
{
	New $Namespace
	Set $Namespace = "%SYS"
	Quit ##class(Security.SSLConfigs).Get(name, .properties)
}

/// Endpoint of the url as host|port|https|path.
Method Split(url As %String) As %String [ Private ]
{
	If '##class(OcuTalon.Mcp.Client).Endpoint(url, .server, .port, .https, .path) Quit "|||"
	Quit server _ "|" _ port _ "|" _ https _ "|" _ path
}

/// Starts the mock and keeps its port. The mock checks a header that the probe never sends, so that its log says absent for a request with no credential.
/// 1 when the mock runs.
Method StartMock(extra As %List = "") As %Boolean [ Private ]
{
	Set sc = $ClassMethod(..#MOCK, "Start", .port, extra, ..#HEADER, "zz" _ ..Number)
	Do $$$AssertStatusOK(sc, "the mock starts")
	If $$$ISERR(sc) Quit 0
	Set ..Port = port
	Quit 1
}

/// The credential header of the fixture: the name the mock checks and the value it expects.
Method Header() As %DynamicObject [ Private ]
{
	Quit {"name": (..#HEADER), "value": ("zz" _ ..Number)}
}

/// The url of the mock's mcp endpoint.
Method Url() As %String [ Private ]
{
	Quit "http://127.0.0.1:" _ ..Port _ "/mcp"
}

/// Ends the mock and its log, and removes the fixture entry. Each step is attempted whatever happened before.
Method Remove() [ Private ]
{
	If ..Port Do $ClassMethod(..#MOCK, "Stop", ..Port), $ClassMethod(..#MOCK, "Forget", ..Port)
	Set entry = "AI.MCP.OcuTalon_zzcli" _ ..Number
	If ##class(%ConfigStore.Configuration).Exists(entry) Do ##class(%ConfigStore.Configuration).Delete(entry)
}

/// What is left of the fixtures, as a text of places ("" when nothing).
Method Leftovers() As %String [ Private ]
{
	Set places = ""
	If ##class(%ConfigStore.Configuration).Exists("AI.MCP.OcuTalon_zzcli" _ ..Number) Set places = places _ $ListBuild("the Config Store entry")
	If ..Port, $Data(^IRIS.Temp.OcuTalonMcpMock(..Port)) || $ClassMethod(..#MOCK, "Running", ..Port) Set places = places _ $ListBuild("a mock node or job")
	Quit $ListToString(places, ", ")
}

}
