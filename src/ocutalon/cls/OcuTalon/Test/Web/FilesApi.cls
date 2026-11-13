/// Tests of the files route (Story 25.3; AD-1, AD-4, AD-13, AD-14, AD-21), called with stand-in request and response objects and a CSP session whose
/// OcuTalon.SessionRef is a fixture session (as Test.Web.DocumentsApi does), through Test.Web.FilesProbe, whose Post records the Channel.WebChat.Post instead of
/// sending it to WebChatIn. Safe on a slot: no production is needed. Rows are fixtures (Test.Data.Fixture), removed before and after the tests, with the sent file rows of
/// the test's sessions; the public setting onlineDemo and the probe's globals are put back. Every sentence is written out here.
///   - TestDispatch: Web.Api's URL map holds exactly one Map for /v1/files, forwarded to Web.Files, whose only route is POST of the empty remainder (Send); GET, PUT, DELETE
///     and PATCH of the empty remainder and every method of /zzRef and of /zzRef/content are no route, and a wrong verb is answered 404 not_found with no Allow header;
///   - TestAccepted: a PDF, a Word file, a JPEG (.jpg and .jpeg) and a PNG are 202 {"clientId","file":{"ref","name","mediaType","size"}} with the exact keys and media
///     types, one SentFile row of the CSP session each (the Ref in the answer), and one Post of the file with no text; a sessionRef, a mediaType and a type in the body are ignored;
///   - TestRefused: a file of 10,485,761 bytes is 400 bad_file too_large with its size, 0 bytes is empty, and every other kind of file is wrong_type: the matrix's names, a
///     renamed .exe (MZ bytes) and .html named x.pdf and x.png with a declared mediaType of application/pdf, nothing stored and nothing posted; 10,485,760 bytes are accepted;
///   - TestBadBodies: every bad body is 400 bad_file with no reason, nothing stored;
///   - TestBodyBound, TestBodyBounds: a body over BODYMAX is 413 body_too_large at the route and in OnPreDispatch of both dispatch classes; the three declarations of the bound are
///     equal to Web.Documents' BODYMAX;
///   - TestDuplicateClientId: the second send of a clientId is 202 {"clientId"} and its file row is dropped;
///   - TestSendFailures: an error status, a thrown error, an output that is not JSON and a refusal of WebChatIn are 500 server_error with no row left;
///   - TestOnlineDemo: on the online demo the answer is 409 not_available with the off text before the body is read, nothing is stored or posted and the session's allowance
///     is untouched;
///   - TestEnvelope: the forwarded dispatch refuses a POST without the browser envelope 403 and a user without the role 403 no_role;
///   - TestStateFlagOff: Web.Api's snapshot holds filesReadable as a boolean right after demoMode, equal to Core.Files.Readable() (false on this branch: the tripwire Story 26.2 flips).
Class OcuTalon.Test.Web.FilesApi Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Web.FilesProbe";

/// The run's number.
Property Number As %Integer;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

/// The SessionRefs that Session made, comma-separated; OnAfterAllTests deletes their file rows.
Property Sessions As %String(MAXLEN = "");

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("FilesApi", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Kill ^OcuTalonTest("FilesProbe")
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("FilesProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	For i = 1:1:$Length(..Sessions, ",") Do ##class(OcuTalon.Data.SentFile).DropSession($Piece(..Sessions, ",", i))
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Kill ^OcuTalonTest("FilesProbe")
	Quit $$$OK
}

Method TestDispatch()
{
	Set sc = ##class(%CSP.REST).ParseUrlMap("OcuTalon.Web.Api", .routes)
	Do $$$AssertStatusOK(sc, "Web.Api's URL map parses")
	Set maps = 0
	Set i = ""
	For {
		Set i = $Order(routes(i), 1, route)
		Quit:i=""
		If (route.type = "M") && (route.url = "/v1/files") {
			Set maps = maps + 1
			Set map = route
		}
	}
	Do $$$AssertEquals(maps, 1, "Web.Api's URL map holds exactly one Map for /v1/files")
	Do $$$AssertEquals(map.forward, "OcuTalon.Web.Files", "it forwards to Web.Files")
	Set matcher = ##class(%Regex.Matcher).%New(map.regex)
	Do $$$AssertTrue(matcher.Match("/v1/files"), "the prefix itself matches")
	Do $$$AssertTrue(matcher.Match("/v1/files/abc"), "the prefix and a ref match")
	Do $$$AssertTrue('matcher.Match("/v1/filesx"), "a longer word does not")
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Test.Web.Api).Routes("OcuTalon.Web.Files"), "|"), "POST  Send", "Web.Files' only route is POST of the empty remainder")
	Set route = ##class(OcuTalon.Web.Files).DispatchMap("", "POST", .verbs, .args)
	Do $$$AssertEquals($ListGet(route, 1)_"|"_$ListGet(route, 2)_"|"_$ListGet(route, 3), "R|Send|OcuTalon.Web.Files", "POST of the empty remainder is Send")
	For method = "GET", "PUT", "DELETE", "PATCH" {
		Kill verbs, args
		Set route = ##class(OcuTalon.Web.Files).DispatchMap("", method, .verbs, .args)
		Do $$$AssertEquals(route, "", method_" of the empty remainder is no route")
	}
	For url = "/zzRef", "/zzRef/content", "/zzRef/" {
		For method = "GET", "PUT", "POST", "DELETE", "PATCH" {
			Kill verbs, args
			Set route = ##class(OcuTalon.Web.Files).DispatchMap(url, method, .verbs, .args)
			Do $$$AssertEquals(route, "", method_" "_url_" is no route")
		}
	}
	// Under /v1/files the class dispatched first answers a wrong verb with 404 not_found and no Allow header; elsewhere the 405 is unchanged.
	For case = $ListBuild("/ocutalon/api/v1/files", 404), $ListBuild("/ocutalon/api/v1/files/", 404), $ListBuild("/ocutalon/api/v1/files?x=1", 404), $ListBuild("/OcuTalon/API/v1/Files", 404), $ListBuild("/ocutalon/api/v1/filesx", 405), $ListBuild("/ocutalon/api/v1/documents", 405), $ListBuild("/ocutalon/api/v1/state", 405) {
		Set written = ..WrongVerb($List(case, 1), .response)
		Do $$$AssertEquals(response.Status, $Select($List(case, 2) = 404: "404 Not Found", 1: "405 Method Not Allowed"), $List(case, 1)_": the status of a wrong verb")
		Do $$$AssertEquals({}.%FromJSON(written).error.code, $Select($List(case, 2) = 404: "not_found", 1: "method_not_allowed"), $List(case, 1)_": the code")
	}
	// The answer to a wrong verb, through the whole dispatch (the envelope and the role are satisfied).
	Set ^OcuTalonTest("FilesProbe", "roles") = "%DB_OCUTALON,"_##class(OcuTalon.Web.Public.Shell).#ROLE
	For case = $ListBuild("", "GET"), $ListBuild("", "PUT"), $ListBuild("", "DELETE"), $ListBuild("", "PATCH"), $ListBuild("/zzRef", "GET"), $ListBuild("/zzRef/content", "GET"), $ListBuild("/zzRef", "DELETE") {
		Set written = ..Dispatched($List(case, 1), $List(case, 2), .response)
		Set label = $List(case, 2)_" '"_$List(case, 1)_"'"
		Do $$$AssertEquals(response.Status, "404 Not Found", label_" is 404")
		Do $$$AssertEquals(written, {"error": {"code": "not_found", "message": "OcuTalon has nothing at this address."}}.%ToJSON(), label_": not_found")
		Do $$$AssertEquals(response.GetHeader("ALLOW"), "", label_": no Allow header")
	}
}

Method TestAccepted()
{
	Set a = ..Session("a")
	Set cases = $ListBuild($ListBuild("a.pdf", "pdf", "application/pdf"), $ListBuild("B.DOCX", "docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"), $ListBuild("c.jpg", "jpeg", "image/jpeg"), $ListBuild("c.jpeg", "jpeg", "image/jpeg"), $ListBuild("d.png", "png", "image/png"))
	For i = 1:1:$ListLength(cases) {
		Set case = $List(cases, i)
		Set name = $List(case, 1)
		Set bytes = ..Sample($List(case, 2))
		Set size = bytes.Size
		Set body = ..Call(a, ..Json("zzc"_..Number_i, name, bytes, {"sessionRef": "zzsomeoneelse", "mediaType": "text/plain", "type": "text/plain"}), .response)
		Do $$$AssertEquals(response.Status, "202 Accepted", name_" is 202: "_body)
		Set answer = {}.%FromJSON(body)
		Do $$$AssertEquals(..Keys(answer)_"|"_..Keys(answer.file), "clientId,file|ref,name,mediaType,size", name_": the keys of the answer and of the file")
		Do $$$AssertEquals(answer.clientId_"|"_answer.file.name_"|"_answer.file.mediaType_"|"_answer.file.size, "zzc"_..Number_i_"|"_name_"|"_$List(case, 3)_"|"_size, name_": the answer holds the clientId, the name, the media type and the size")
		Set row = ##class(OcuTalon.Data.SentFile).RefIndexOpen(answer.file.ref)
		Do $$$AssertEquals($Select($IsObject(row): row.SessionRef_"|"_row.Channel, 1: "(no row)"), a_"|web", name_": one row of the CSP session, channel web")
		Do $$$AssertEquals(..Post(i, "sessionRef")_"|"_..Post(i, "clientId")_"|"_..Post(i, "text")_"|"_..Post(i, "fileRef")_"|"_..Post(i, "fileName")_"|"_..Post(i, "fileMediaType")_"|"_..Post(i, "fileSize"), a_"|zzc"_..Number_i_"||"_answer.file.ref_"|"_name_"|"_$List(case, 3)_"|"_size, name_": the post names the file and has no text")
		Do $$$AssertEquals(..Post(i, "rowFound"), 1, name_": the file's row existed when the Item was posted")
	}
	Do $$$AssertEquals(..Posts()_"|"_..Files(a), "5|5", "five posts and five rows")
}

Method TestRefused()
{
	Set a = ..Session("a")
	Set text = "OcuTalon can read PDF, Word (.docx), JPEG and PNG files up to 10 MB."
	Set pdfType = {"mediaType": "application/pdf"}
	Set cases = $ListBuild($ListBuild("x.txt", "text", "wrong_type"), $ListBuild("x.md", "text", "wrong_type"), $ListBuild("x.gif", "gif", "wrong_type"), $ListBuild("x.doc", "doc", "wrong_type"),
		$ListBuild("x.png", "pdf", "wrong_type"), $ListBuild("x.pdf", "none", "wrong_type"), $ListBuild("setup.pdf", "exe", "wrong_type"), $ListBuild("page.pdf", "html", "wrong_type"), $ListBuild("page.png", "html", "wrong_type"),
		$ListBuild("x.docx", "zipnoword", "wrong_type"), $ListBuild("noextension", "pdf", "wrong_type"), $ListBuild("empty.pdf", "empty", "empty"))
	For i = 1:1:$ListLength(cases) {
		Set case = $List(cases, i)
		Set bytes = ..Sample($List(case, 2))
		Set size = bytes.Size
		Set body = ..Call(a, ..Json("zzc"_..Number_"r"_i, $List(case, 1), bytes, pdfType), .response)
		Set label = $List(case, 1)_" with "_$List(case, 2)_" bytes"
		Do $$$AssertEquals(response.Status, "400 Bad Request", label_" is 400")
		Do $$$AssertEquals(body, {"error": {"code": "bad_file", "message": (text)}, "reason": ($List(case, 3)), "size": (size)}.%ToJSON(), label_": bad_file, "_$List(case, 3)_" and the size")
	}
	Set limit = ##class(OcuTalon.Core.Files).#FILEMAX
	Set over = ..Padded("pdf", limit + 1)
	Set body = ..CallStream(a, ..JsonStream("zzc"_..Number_"over", "over.pdf", over), .response)
	Do $$$AssertEquals(response.Status_"|"_body, "400 Bad Request|"_{"error": {"code": "bad_file", "message": (text)}, "reason": "too_large", "size": (limit + 1)}.%ToJSON(), "10,485,761 bytes are too_large with their size")
	Do $$$AssertEquals(..Files(a)_"|"_..Posts(), "0|0", "nothing was stored and nothing posted")
	Set body = ..CallStream(a, ..JsonStream("zzc"_..Number_"edge", "edge.pdf", ..Padded("pdf", limit)), .response)
	Do $$$AssertEquals($Piece(response.Status, " "), "202", "10,485,760 bytes are accepted: "_$Extract(body, 1, 200))
	Do $$$AssertEquals(..Files(a)_"|"_..Posts(), "1|1", "and stored and posted")
}

Method TestBadBodies()
{
	Set a = ..Session("a")
	Set text = "OcuTalon can read PDF, Word (.docx), JPEG and PNG files up to 10 MB."
	Set ok = "{""clientId"":""zzc1"",""name"":""a.pdf"",""content"":""JVBERi0x""}"
	Set long = $Translate($Justify("", 256), " ", "n")_".pdf"
	Set bad = $ListBuild("", "not json", "[]", "{}", "{""clientId"":""zzc1"",""name"":""a.pdf""}", "{""name"":""a.pdf"",""content"":""JVBERi0x""}", "{""clientId"":"""",""name"":""a.pdf"",""content"":""JVBERi0x""}", "{""clientId"":5,""name"":""a.pdf"",""content"":""JVBERi0x""}",
		"{""clientId"":"""_$Translate($Justify("", 129), " ", "c")_""",""name"":""a.pdf"",""content"":""JVBERi0x""}", "{""clientId"":""zzc1"",""name"":"""",""content"":""JVBERi0x""}", "{""clientId"":""zzc1"",""name"":""   "",""content"":""JVBERi0x""}",
		"{""clientId"":""zzc1"",""name"":""a"_"\n"_".pdf"",""content"":""JVBERi0x""}", "{""clientId"":""zzc1"",""name"":""a"_"\u0000"_".pdf"",""content"":""JVBERi0x""}", "{""clientId"":""zzc1"",""name"":5,""content"":""JVBERi0x""}",
		"{""clientId"":""zzc1"",""name"":"""_long_""",""content"":""JVBERi0x""}", "{""clientId"":""zzc1"",""name"":""a.pdf"",""content"":5}", "{""clientId"":""zzc1"",""name"":""a.pdf"",""content"":null}", "{""clientId"":""zzc1"",""name"":""a.pdf"",""content"":""!!!not base64!!!""}")
	For i = 1:1:$ListLength(bad) {
		Set json = $List(bad, i)
		Set body = ..Call(a, json, .response)
		Set label = "body "_i_" '"_$Extract(json, 1, 50)_"'"
		Do $$$AssertEquals(response.Status, "400 Bad Request", label_" is 400")
		Do $$$AssertEquals(body, {"error": {"code": "bad_file", "message": (text)}}.%ToJSON(), label_": bad_file, no reason")
	}
	Do $$$AssertEquals(..Files(a)_"|"_..Posts(), "0|0", "nothing was stored or posted")
	Set body = ..Call(a, ok, .response)
	Do $$$AssertEquals($Piece(response.Status, " "), "202", "the control body is accepted: "_body)
}

Method TestBodyBound()
{
	Set a = ..Session("a")
	Set max = ##class(OcuTalon.Web.Documents).#BODYMAX
	Set stream = ..JsonStream("zzc"_..Number_"b", "bound.pdf", ..Sample("pdf"), , max)
	Do $$$AssertEquals(stream.Size, max, "the body is BODYMAX bytes")
	Set body = ..CallStream(a, stream, .response)
	Do $$$AssertEquals($Piece(response.Status, " "), "202", "a body of BODYMAX bytes is read: "_$Extract(body, 1, 200))
	Set stream = ..JsonStream("zzc"_..Number_"c", "bound.pdf", ..Sample("pdf"), , max + 1)
	Set body = ..CallStream(a, stream, .response)
	Do $$$AssertEquals(response.Status_"|"_body, "413 Content Too Large|"_{"error": {"code": "body_too_large", "message": "OcuTalon can read PDF, Word (.docx), JPEG and PNG files up to 10 MB."}}.%ToJSON(), "one byte more is 413 body_too_large")
	Do $$$AssertEquals(..Files(a)_"|"_..Posts(), "1|1", "and nothing more was stored or posted")
	Set junk = ##class(%CSP.BinaryStream).%New()
	For i = 1:1:(max \ 1000) + 1 Do junk.Write($Justify("", 1000))
	Do junk.Rewind()
	Set body = ..CallStream(a, junk, .response)
	Do $$$AssertEquals(response.Status, "413 Content Too Large", "a junk body over the bound is 413, not 400")
}

Method TestBodyBounds()
{
	Set max = ##class(OcuTalon.Web.Documents).#BODYMAX
	Set default = ##class(OcuTalon.Web.BodyLimit).#MAXBYTES
	Do $$$AssertEquals(##class(OcuTalon.Web.Files).#BODYMAX, max, "Web.Files' BODYMAX is Web.Documents'")
	Do $$$AssertEquals(##class(OcuTalon.Web.BodyLimit).Bound("OcuTalon.Web.Api", "/v1/files", "POST"), max, "Web.Api declares POST /v1/files at BODYMAX")
	Do $$$AssertEquals(##class(OcuTalon.Web.BodyLimit).Bound("OcuTalon.Web.Files", "", "POST"), max, "Web.Files declares POST of the remainder at BODYMAX")
	Do $$$AssertEquals(##class(OcuTalon.Web.BodyLimit).Bound(..#PROBE, "", "POST"), max, "and so does the probe that extends it")
	Do $$$AssertEquals(##class(OcuTalon.Web.BodyLimit).Bound("OcuTalon.Web.Api", "/v1/files", "GET"), default, "a GET keeps the default")
	Set role = "%DB_OCUTALON," _ ##class(OcuTalon.Web.Public.Shell).#ROLE
	Set savedApi = $Get(^OcuTalonTest("ApiProbe", "roles"))
	Set hadApi = $Data(^OcuTalonTest("ApiProbe", "roles"))
	Set ^OcuTalonTest("ApiProbe", "roles") = role
	Set ^OcuTalonTest("FilesProbe", "roles") = role
	Set refused = {"error": {"code": "body_too_large", "message": (##class(OcuTalon.Web.BodyLimit).#MESSAGEBODYTOOLARGE)}}.%ToJSON()
	For case = $ListBuild("OcuTalon.Test.Web.ApiProbe", "/v1/files"), $ListBuild(..#PROBE, "") {
		Set class = $List(case, 1), url = $List(case, 2)
		Set label = $Piece(class, ".", *) _ " POST '" _ url _ "'"
		Set written = ..SizedDispatch(class, url, "POST", max, .response, .continue)
		Do $$$AssertEquals(continue _ "|" _ written, "1|", label _ " takes " _ max _ " bytes")
		Set written = ..SizedDispatch(class, url, "POST", max + 1, .response, .continue)
		Do $$$AssertEquals(response.Status _ "|" _ continue _ "|" _ written, "413 Content Too Large|0|" _ refused, label _ " refuses " _ (max + 1) _ " bytes")
	}
	Kill ^OcuTalonTest("FilesProbe", "roles")
	If hadApi Set ^OcuTalonTest("ApiProbe", "roles") = savedApi
	If 'hadApi Kill ^OcuTalonTest("ApiProbe", "roles")
}

Method TestDuplicateClientId()
{
	Set a = ..Session("a")
	Set json = ..Json("zzc"_..Number_"dup", "dup.pdf", ..Sample("pdf"))
	Set first = ..Call(a, json, .response)
	Do $$$AssertEquals($Piece(response.Status, " "), "202", "the first send is 202")
	Set body = ..Call(a, json, .response)
	Do $$$AssertEquals(response.Status_"|"_body, "202 Accepted|"_{"clientId": ("zzc"_..Number_"dup")}.%ToJSON(), "the second answer is 202 with the same clientId and no file")
	Do $$$AssertEquals(..Files(a)_"|"_..Posts(), "1|2", "one row remains: the second file's row is dropped")
	Do $$$AssertEquals(##class(OcuTalon.Core.Files).Describe({}.%FromJSON(first).file.ref, a).name, "dup.pdf", "and it is the first's")
}

Method TestSendFailures()
{
	Set a = ..Session("a")
	For answer = "status", "throw", "garbage", "refused" {
		Set ^OcuTalonTest("FilesProbe", "answer") = answer
		Set body = ..Call(a, ..Json("zzc"_..Number_answer, "fail.pdf", ..Sample("pdf")), .response)
		Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_{"error": {"code": "server_error", "message": "Something went wrong inside OcuTalon. Try again."}}.%ToJSON(), answer_": 500 server_error")
		Do $$$AssertEquals(..Files(a), 0, answer_": the stored file is dropped again")
	}
	Do $$$AssertEquals(..Posts(), 4, "all four were posted")
}

Method TestOnlineDemo()
{
	Set a = ..Session("a")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set before = ##class(OcuTalon.Data.Session).RefIndexOpen(a).AllowanceTimes
	Set text = "Sending files is off on the online demo. It works on your own install."
	Set body = ..Call(a, ..Json("zzc"_..Number_"demo", "demo.pdf", ..Sample("pdf")), .response)
	Do $$$AssertEquals(response.Status_"|"_body, "409 Conflict|"_{"error": {"code": "not_available", "message": (text)}}.%ToJSON(), "409 not_available with the off text")
	Set body = ..Call(a, "not even json", .response)
	Do $$$AssertEquals(response.Status, "409 Conflict", "also for a body that would be refused: the body is not read")
	Do $$$AssertEquals(..Files(a)_"|"_..Posts(), "0|0", "nothing was stored or posted")
	Do $$$AssertEquals(##class(OcuTalon.Data.Session).RefIndexOpen(a).AllowanceTimes, before, "the session's allowance is untouched")
}

Method TestEnvelope()
{
	Set ^OcuTalonTest("FilesProbe", "roles") = "%DB_OCUTALON,"_##class(OcuTalon.Web.Public.Shell).#ROLE
	Set origin = "http://localhost:52773", host = "localhost:52773"
	Set written = ..PreDispatch("", "POST", "text/plain", "1", origin, host, .continue)
	Do $$$AssertEquals(continue, 0, "a POST with the wrong Content-Type stops the dispatch")
	Do $$$AssertEquals({}.%FromJSON(written).error.code, "not_json", "not_json")
	Set written = ..PreDispatch("", "POST", "application/json", "", origin, host, .continue)
	Do $$$AssertEquals({}.%FromJSON(written).error.code, "no_request_header", "no_request_header")
	Set written = ..PreDispatch("", "POST", "application/json", "1", "http://evil.example", host, .continue)
	Do $$$AssertEquals({}.%FromJSON(written).error.code, "wrong_origin", "wrong_origin")
	Set written = ..PreDispatch("", "POST", "application/json", "1", origin, host, .continue)
	Do $$$AssertEquals(continue_"|"_written, "1|", "a POST with the full envelope goes on")
	Set ^OcuTalonTest("FilesProbe", "roles") = "%DB_OCUTALON"
	Set written = ..PreDispatch("", "POST", "application/json", "1", origin, host, .continue)
	Do $$$AssertEquals(continue, 0, "a signed-in user without the OcuTalon user role is stopped")
	Do $$$AssertEquals({}.%FromJSON(written).error.code, "no_role", "no_role")
}

/// The tripwire that Story 26.2 flips: nothing reads a sent file yet, so the flag is false.
Method TestStateFlagOff()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzfilesstate"_..Number)
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(ref))
	Set keys = ..Keys(body)
	Do $$$AssertTrue(keys [ "demoMode,filesReadable,models", "filesReadable is right after demoMode: "_keys)
	Do $$$AssertEquals(body.%GetTypeOf("filesReadable"), "boolean", "filesReadable is a boolean")
	Do $$$AssertEquals(body.filesReadable, ##class(OcuTalon.Core.Files).Readable(), "it equals Core.Files.Readable()")
	Do $$$AssertEquals(body.filesReadable, 0, "and it is false on this branch")
}

/// --- helpers ---
/// A fixture session of the IRIS user who runs the tests. Returns its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set ..Sessions = ..Sessions_$Select(..Sessions = "": "", 1: ",")_ref
	Quit ref
}

/// Calls Send as the CSP session of the session with the body as the request's content (UTF-8 bytes as the CSP server hands it over).
Method Call(session As %String, body As %String, Output response) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = $Select(body = "": ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/api/"), 1: ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", body, 1))
	Quit ..Run(session, .response)
}

/// As Call, with the request's content a stream that the test built.
Method CallStream(session As %String, stream As %CSP.BinaryStream, Output response) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/api/")
	Do stream.Rewind()
	Set %request.Content = stream
	Quit ..Run(session, .response)
}

Method Run(session As %String, Output response) As %String [ Private ]
{
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzFilesApi"_..Number, 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, "Send")
	Do $$$AssertStatusOK(sc, "Send returns OK")
	Set response = %response
	Quit written
}

/// The whole dispatch of the probe for the URL and method, with the browser envelope; returns what it wrote. response is the %response.
Method Dispatched(url As %String, method As %String, Output response) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", method, "application/json", "1", "http://localhost:52773", "localhost:52773")
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzFilesApiDispatch"_..Number, 0)
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, "DispatchRequest", url, method)
	Do $$$AssertStatusOK(sc, "DispatchRequest returns OK")
	Set response = %response
	Quit written
}

/// What Web.Api answers to a wrong verb on the request URL; response is the %response.
Method WrongVerb(url As %String, Output response) As %String [ Private ]
{
	New %request, %response
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/api/")
	Set %request.URL = url
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Api", "Http405", "POST")
	Do $$$AssertStatusOK(sc, "Http405 returns OK")
	Set response = %response
	Quit written
}

/// Runs OnPreDispatch of the probe for the URL and method with a stand-in request; returns what it wrote. continue is the dispatch flag it left.
Method PreDispatch(url As %String, method As %String, contentType As %String, header As %String, origin As %String, host As %String, Output continue) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", method, contentType, header, origin, host)
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New("ZzFilesApiPre"_..Number, 0)
	Set %response.ContentType = ""
	Set continue = 1
	Set sc = ##class(OcuTalon.Test.Web.Api).Capture(.capture)
	If $SYSTEM.Status.IsOK(sc) {
		Try {
			Set sc = $ClassMethod(..#PROBE, "OnPreDispatch", url, method, .continue)
		} Catch exception {
			Set sc = exception.AsStatus()
		}
	}
	Set written = ##class(OcuTalon.Test.Web.Api).Collect(.capture)
	Do $$$AssertStatusOK(sc, "OnPreDispatch returns OK")
	Quit written
}

/// Runs OnPreDispatch of the class for a request of the method whose body is a stream of exactly bytes bytes, with the whole browser envelope, and returns what it
/// wrote. response is the %response and continue the dispatch flag it left.
Method SizedDispatch(class As %String, url As %String, method As %String, bytes As %Integer, Output response, Output continue) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", method, "application/json", "1", "http://localhost:52773", "localhost:52773")
	Set stream = ##class(%CSP.BinaryStream).%New()
	Set chunk = $Translate($Justify("", 30000), " ", "x")
	Set left = bytes
	While left > 0 {
		Set part = $Select(left > 30000: 30000, 1: left)
		Do stream.Write($Extract(chunk, 1, part))
		Set left = left - part
	}
	Do stream.Rewind()
	Set %request.Content = stream
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzFilesApiSized"_..Number, 0)
	Set continue = 1
	Set sc = ##class(OcuTalon.Test.Web.Api).Capture(.capture)
	If $SYSTEM.Status.IsOK(sc) {
		Try {
			Set sc = $ClassMethod(class, "OnPreDispatch", url, method, .continue)
		} Catch exception {
			Set sc = exception.AsStatus()
		}
	}
	Set written = ##class(OcuTalon.Test.Web.Api).Collect(.capture)
	Do $$$AssertStatusOK(sc, "OnPreDispatch returns OK")
	Set response = %response
	Quit written
}

/// The request body for the file as a string: {"clientId","name","content"} with the content in base64, then the members of extra. For small files only.
Method Json(clientId As %String, name As %String, bytes As %Stream.Object, extra As %DynamicObject = "") As %String [ Private ]
{
	Set object = {"clientId": (clientId), "name": (name)}
	Do bytes.Rewind()
	Set content = ""
	While 'bytes.AtEnd {
		Set content = content_$SYSTEM.Encryption.Base64Encode(bytes.Read(30000), 1)
	}
	Set object.content = content
	If $IsObject(extra) {
		Set iterator = extra.%GetIterator()
		While iterator.%GetNext(.key, .value) {
			Do object.%Set(key, value)
		}
	}
	Quit object.%ToJSON()
}

/// The request body for the file as a stream of UTF-8 bytes that never sits in one string: as Json, then spaces up to total bytes when total is given.
Method JsonStream(clientId As %String, name As %String, bytes As %Stream.Object, extra As %DynamicObject = "", total As %Integer = 0) As %CSP.BinaryStream [ Private ]
{
	Set object = {"clientId": (clientId), "name": (name)}
	Set head = $Extract(object.%ToJSON(), 1, *-1)_",""content"":"""
	Set stream = ##class(%CSP.BinaryStream).%New()
	Do stream.Write($ZConvert(head, "O", "UTF8"))
	Do bytes.Rewind()
	While 'bytes.AtEnd {
		Do stream.Write($SYSTEM.Encryption.Base64Encode(bytes.Read(30000), 1))
	}
	Do stream.Write("""}")
	If total > stream.Size {
		Set pad = total - stream.Size
		While pad > 0 {
			Set part = $Select(pad > 30000: 30000, 1: pad)
			Do stream.Write($Justify("", part))
			Set pad = pad - part
		}
	}
	Do stream.Rewind()
	Quit stream
}

/// A new binary stream that holds the string.
Method Stream(data As %String) As %Stream.TmpBinary [ Private ]
{
	Set stream = ##class(%Stream.TmpBinary).%New()
	If data '= "" Do stream.Write(data)
	Do stream.Rewind()
	Quit stream
}

/// The bytes of a small file of the kind (pdf, docx, jpeg, png, text, gif, doc, exe, html, zipnoword, empty, none).
Method Sample(kind As %String) As %Stream.TmpBinary [ Private ]
{
	If kind = "pdf" Quit ..Stream("%PDF-1.4 zz")
	If kind = "png" Quit ..Stream($Char(137, 80, 78, 71, 13, 10, 26, 10)_"IHDR zz")
	If kind = "jpeg" Quit ..Stream($Char(255, 216, 255, 224)_"JFIF zz")
	If kind = "text" Quit ..Stream("plain text zz")
	If kind = "gif" Quit ..Stream("GIF89a zz")
	If kind = "doc" Quit ..Stream($Char(208, 207, 17, 224, 161, 177, 26, 225)_"zz")
	If kind = "exe" Quit ..Stream("MZ"_$Char(144, 0, 3, 0)_"zz")
	If kind = "html" Quit ..Stream("<html><script>alert('zz')</script></html>")
	If kind = "empty" Quit ..Stream("")
	If kind = "docx" {
		Set stream = ##class(OcuTalon.Test.Docs.Samples).Docx(##class(OcuTalon.Test.Docs.Samples).Paragraph("zz"))
		Do stream.Rewind()
		Quit stream
	}
	If kind = "zipnoword" {
		Set entries(1) = "readme.txt"
		Set entries(1, "data") = "zz"
		Set stream = ##class(OcuTalon.Test.Docs.Samples).Zip(.entries, 1)
		Do stream.Rewind()
		Quit stream
	}
	Quit ..Stream("unknown bytes zz")
}

/// A stream of exactly size bytes that starts like a PDF (kind pdf) or with no signature.
Method Padded(kind As %String, size As %Integer) As %Stream.TmpBinary [ Private ]
{
	Set stream = ##class(%Stream.TmpBinary).%New()
	Set head = $Select(kind = "pdf": "%PDF-", 1: "zzzzz")
	Do stream.Write(head)
	Do ##class(OcuTalon.Test.Docs.Samples).Fill(stream, size - $Length(head))
	Do stream.Rewind()
	Quit stream
}

/// The keys of the object, in order, comma-separated.
Method Keys(object As %DynamicObject) As %String [ Private ]
{
	Set keys = ""
	Set iterator = object.%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Quit keys
}

/// The number of SentFile rows of the session.
Method Files(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.SentFile WHERE SessionRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of posts the probe recorded.
Method Posts() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("FilesProbe", "posts"))
}

/// One field of the probe's nth post.
Method Post(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("FilesProbe", "posts", n, field))
}

}
