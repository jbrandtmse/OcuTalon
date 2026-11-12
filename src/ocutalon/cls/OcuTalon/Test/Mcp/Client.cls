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

/// Endpoint of the url as host|port|https|path.
Method Split(url As %String) As %String [ Private ]
{
	If '##class(OcuTalon.Mcp.Client).Endpoint(url, .server, .port, .https, .path) Quit "|||"
	Quit server _ "|" _ port _ "|" _ https _ "|" _ path
}

/// Starts the mock and keeps its port. The mock checks a header that the probe never sends, so that its log says absent for a request with no credential.
/// 1 when the mock runs.
Method StartMock() As %Boolean [ Private ]
{
	Set sc = $ClassMethod(..#MOCK, "Start", .port, , ..#HEADER, "zz" _ ..Number)
	Do $$$AssertStatusOK(sc, "the mock starts")
	If $$$ISERR(sc) Quit 0
	Set ..Port = port
	Quit 1
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
