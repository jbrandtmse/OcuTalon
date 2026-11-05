/// Tests of the documents routes (Story 34.2; AD-1, AD-4, AD-13, AD-21), called with stand-in request and response objects and a CSP session
/// whose OcuTalon.SessionRef is a fixture session (as Test.Web.DismissApi does), through Test.Web.DocumentsProbe, whose Submit records the
/// command instead of sending it to CommandsIn. Safe on a slot: no production is needed. Rows are fixtures (Test.Data.Fixture), removed before
/// and after the tests; the public setting onlineDemo and the probe's globals are put back.
///   - TestDispatch (Task 0 (a)): Web.Api's URL map holds exactly one Map, for /v1/documents, forwarded to Web.Documents, and the forwarded class
///     routes GET and POST of the empty remainder and DELETE of /:ref to List, Add and Remove; a Map of the same kind (Test.Web.DocumentsMapProbe)
///     reaches the probe's three routes through the forwarded role check; the whole chain from Web.Api.DispatchMap reaches Web.Documents' routes in
///     a process that holds the OcuTalon user role, and in one that lacks it the forwarded dispatch refuses 403 no_role;
///   - TestList: two sessions' documents, newest addedAt first and only the caller's own on the online demo; on a local install the instance's
///     documents to every session; the keys of a row;
///   - TestAddAccepted: one AddDocument per accepted extension, in any case, with the decoded byte size, the CSP session's Ref (a sessionRef of
///     the body is ignored) and origin web_user, and 200 {"result":"done","ref"};
///   - TestAddRefused: every refusal of the Matrix is a 400 bad_document with its reason (none for a malformed body) and submits nothing; a file
///     of 10,485,760 bytes is accepted and one of 10,485,761 refused too_large, for a .md, .txt, .pdf and .docx alike;
///   - TestBodyBound: a body of BODYMAX bytes is parsed and one byte more is 413 body_too_large before it is parsed, with nothing submitted;
///   - TestLargeBody: a request stream with a 10 MB PDF and a non-ASCII name parses with the exact size and name;
///   - TestOutcomes: not_built is 501, not_found is 404 (remove), failed, an unknown outcome, an error status and no result are 500;
///   - TestNoSession: a CSP session with no OcuTalon session of the signed-in user (a failed read) is 500 server_error on the list, the add and the
///     remove, with nothing submitted;
///   - TestRealSubmitOrigin: the class's real Submit (which no test reaches while DocumentOps is disabled) names ORIGIN, web_user, as the origin it
///     passes to Commands.Submit;
///   - TestOwnerNotRunning: while the owner item is not running (DocumentOps is disabled until Story 19.4) a valid add and a remove of an own document
///     are 501 not_built at once and nothing is submitted;
///   - TestOwnerRunningReadsTheItem: the real OwnerRunning is 1 for an enabled item and 0 for a disabled or unknown one (a stand-in item of the test);
///   - TestRemove: another session's document, an unknown ref and an empty-case variant of a ref are 404 with nothing submitted; an own one
///     submits one RemoveDocument (the document's Ref, the session, web_user) and is 200 {"result":"done"};
///   - TestEnvelope: the forwarded dispatch refuses a POST and a DELETE without the browser envelope 403, and lets a GET and a full envelope through.
Class OcuTalon.Test.Web.DocumentsApi Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Web.DocumentsProbe";

/// The run's number.
Property Number As %Integer;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("DocumentsApi", "n"))
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Kill ^OcuTalonTest("DocumentsProbe")
	Quit $$$OK
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("DocumentsProbe")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Kill ^OcuTalonTest("DocumentsProbe")
	Quit $$$OK
}

/// The map, the forwarded class and its three routes (Task 0 (a)).
Method TestDispatch()
{
	Set sc = ##class(%CSP.REST).ParseUrlMap("OcuTalon.Web.Api", .routes)
	Do $$$AssertStatusOK(sc, "Web.Api's URL map parses")
	Set maps = 0
	Set i = ""
	For {
		Set i = $Order(routes(i), 1, route)
		Quit:i=""
		If route.type = "M" {
			Set maps = maps + 1
			Set map = route
		}
	}
	Do $$$AssertEquals(maps, 1, "Web.Api's URL map holds exactly one Map")
	Do $$$AssertEquals(map.url, "/v1/documents", "its prefix is /v1/documents")
	Do $$$AssertEquals(map.forward, "OcuTalon.Web.Documents", "it forwards to Web.Documents")
	Set matcher = ##class(%Regex.Matcher).%New(map.regex)
	Do $$$AssertTrue(matcher.Match("/v1/documents"), "the prefix itself matches")
	Do $$$AssertTrue(matcher.Match("/v1/documents/abc"), "the prefix and a ref match")
	Do $$$AssertTrue('matcher.Match("/v1/documentsx"), "a longer word does not")
	Do $$$AssertTrue('matcher.Match("/v1/state"), "another route does not")
	Do $$$AssertEquals($ListToString(##class(OcuTalon.Test.Web.Api).Routes("OcuTalon.Web.Documents"), "|"), "GET  List|POST  Add|DELETE /:ref Remove", "Web.Documents' routes, in order")

	Set route = ##class(OcuTalon.Web.Documents).DispatchMap("", "GET", .verbs, .args)
	Do $$$AssertEquals($ListGet(route, 1)_"|"_$ListGet(route, 2)_"|"_$ListGet(route, 3), "R|List|OcuTalon.Web.Documents", "GET of the empty remainder is List")
	Set route = ##class(OcuTalon.Web.Documents).DispatchMap("", "POST", .verbs, .args)
	Do $$$AssertEquals($ListGet(route, 1)_"|"_$ListGet(route, 2)_"|"_$ListGet(route, 3), "R|Add|OcuTalon.Web.Documents", "POST of the empty remainder is Add")
	Kill args
	Set route = ##class(OcuTalon.Web.Documents).DispatchMap("/zzRef", "DELETE", .verbs, .args)
	Do $$$AssertEquals($ListGet(route, 1)_"|"_$ListGet(route, 2)_"|"_$ListGet(route, 3)_"|"_$Get(args(1)), "R|Remove|OcuTalon.Web.Documents|zzRef", "DELETE of /:ref is Remove with the ref")
	Kill args
	Set route = ##class(OcuTalon.Web.Documents).DispatchMap("", "DELETE", .verbs, .args)
	Do $$$AssertEquals(route, "", "DELETE of the empty remainder is no route")
	Do $$$AssertTrue((verbs [ ",GET,") && (verbs [ ",POST,") && (verbs '[ "DELETE"), "but the verbs that match are GET and POST: "_verbs)

	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/api/")
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	// The whole chain through a Map of the same kind (Test.Web.DocumentsMapProbe forwards to the probe, whose roles the test sets): the map, the
	// forwarded dispatch's role check and its own routes. The empty remainder reaches List and Add; /:ref reaches Remove with the ref.
	Set ^OcuTalonTest("DocumentsProbe", "roles") = "%DB_OCUTALON,"_##class(OcuTalon.Web.Public.Shell).#ROLE
	For case = $ListBuild("/v1/documents", "GET", "List", ""), $ListBuild("/v1/documents", "POST", "Add", ""), $ListBuild("/v1/documents/zzRef", "DELETE", "Remove", "zzRef") {
		Kill args, verbs
		Set %request = ..Envelope($List(case, 2))
		Set route = ##class(OcuTalon.Test.Web.DocumentsMapProbe).DispatchMap($List(case, 1), $List(case, 2), .verbs, .args)
		Set label = $List(case, 2)_" "_$List(case, 1)
		Do $$$AssertEquals($ListGet(route, 1)_"|"_$ListGet(route, 2)_"|"_$ListGet(route, 3)_"|"_$Get(args(1)), "R|"_$List(case, 3)_"|OcuTalon.Test.Web.DocumentsProbe|"_$List(case, 4), label_" through the map reaches "_$List(case, 3))
	}
	Kill ^OcuTalonTest("DocumentsProbe", "roles")

	// The whole chain from Web.Api: the forwarded dispatch runs its own role check first.
	Set holds = ##class(OcuTalon.Web.Public.Shell).HasRole()
	For case = $ListBuild("/v1/documents", "GET", "List"), $ListBuild("/v1/documents", "POST", "Add"), $ListBuild("/v1/documents/zzRef", "DELETE", "Remove") {
		Kill args, verbs
		Set %request = ..Envelope($List(case, 2))
		Set sc = ##class(OcuTalon.Test.Web.Api).Capture(.capture)
		Set route = ""
		Try {
			Set route = ##class(OcuTalon.Web.Api).DispatchMap($List(case, 1), $List(case, 2), .verbs, .args)
		} Catch exception {
			Set sc = exception.AsStatus()
		}
		Set written = ##class(OcuTalon.Test.Web.Api).Collect(.capture)
		Set label = $List(case, 2)_" "_$List(case, 1)
		Do $$$AssertStatusOK(sc, label_" dispatches without an error")
		If holds {
			Do $$$AssertEquals($ListGet(route, 1)_"|"_$ListGet(route, 2)_"|"_$ListGet(route, 3), "R|"_$List(case, 3)_"|OcuTalon.Web.Documents", label_" from Web.Api reaches Web.Documents")
		} Else {
			Do $$$AssertEquals($ListGet(route, 1)_"|"_$ListGet(route, 2), "M|OcuTalon.Web.Documents", label_" from Web.Api is forwarded to Web.Documents, whose dispatch ran")
			Do $$$AssertTrue(written [ """no_role""", label_": and refused the caller who lacks the OcuTalon user role: "_written)
		}
	}
}

/// The caller's documents, newest first; the instance's on a local install.
Method TestList()
{
	Set a = ..Session("a"), b = ..Session("b")
	Set old = ##class(OcuTalon.Test.Data.Fixture).Document(a, "zz old a.md", {"AddedAt": "2030-01-01T10:00:00Z"})
	Set new = ##class(OcuTalon.Test.Data.Fixture).Document(a, "zz new a.pdf", {"AddedAt": "2030-01-03T10:00:00Z", "ContentType": "pdf", "State": "failed", "Reason": "not_built", "Size": 1234})
	Set mid = ##class(OcuTalon.Test.Data.Fixture).Document(a, "zz mid a.txt", {"AddedAt": "2030-01-02T10:00:00Z", "State": "ready"})
	Set theirs = ##class(OcuTalon.Test.Data.Fixture).Document(b, "zz b.md", {"AddedAt": "2030-01-04T10:00:00Z"})
	Set shared = ##class(OcuTalon.Test.Data.Fixture).Document("instance", "zz shared.md", {"AddedAt": "2030-01-05T10:00:00Z"})
	Set body = ..Call("List", a, , .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the list is 200: "_body)
	Set list = ..Refs(body)
	Do $$$AssertEquals(list, new_","_mid_","_old, "online demo: A gets only its own rows, newest addedAt first")
	Set row = {}.%FromJSON(body).documents.%Get(0)
	Do $$$AssertEquals(row.ref_"|"_row.name_"|"_row.addedAt_"|"_row.size_"|"_row.state_"|"_row.reason_"|"_row.removed, new_"|zz new a.pdf|2030-01-03T10:00:00Z|1234|failed|not_built|0", "a row carries ref, name, addedAt, size, state, reason and removed")
	Do $$$AssertEquals(..Keys(body), "ref,name,addedAt,size,state,reason,removed", "in that order")
	Set body = ..Call("List", b, , .response)
	Do $$$AssertEquals(..Refs(body), theirs, "online demo: B gets only its own row")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	// On a local install every instance row is listed, so only the rows this test made are compared.
	Set mine = $ListBuild(shared, new, mid, old, theirs)
	Set body = ..Call("List", a, , .response)
	Do $$$AssertEquals(..Refs(body, mine), shared_","_new_","_mid_","_old, "local install: A gets the instance's row and its own, newest first, and not B's")
	Set body = ..Call("List", b, , .response)
	Do $$$AssertEquals(..Refs(body, mine), shared_","_theirs, "local install: B gets the instance's row and its own")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Set empty = ..Session("empty")
	Set body = ..Call("List", empty, , .response)
	Do $$$AssertEquals(body, "{""documents"":[]}", "a session with none gets an empty list")
}

/// An accepted file submits one AddDocument for the CSP session.
Method TestAddAccepted()
{
	Set a = ..Session("a")
	Set cases = $ListBuild($ListBuild("Results runbook.md", "markdown"), $ListBuild("notes.MARKDOWN", "markdown"), $ListBuild("a.b.txt", "text"), $ListBuild("Plan.PDF", "pdf"), $ListBuild("memo.DocX", "docx"))
	For i = 1:1:$ListLength(cases) {
		Set case = $List(cases, i)
		Set body = ..Call("Add", a, {"name": ($List(case, 1)), "content": "aGVsbG8=", "sessionRef": "zzsomeoneelse"}.%ToJSON(), .response)
		Set label = $List(case, 1)
		Do $$$AssertEquals(response.Status, "200 OK", label_" is 200: "_body)
		Do $$$AssertEquals(body, {"result": "done", "ref": "zzDocRef0123456789abcd"}.%ToJSON(), label_": {""result"":""done"",""ref""}")
		Do $$$AssertEquals(..Submits(), i, label_": one command more")
		Do $$$AssertEquals(..Submit(i, "class")_"|"_..Submit(i, "origin")_"|"_..Submit(i, "name")_"|"_..Submit(i, "contentType")_"|"_..Submit(i, "size")_"|"_..Submit(i, "sessionRef"), "OcuTalon.Msg.Command.AddDocument|web_user|"_$List(case, 1)_"|"_$List(case, 2)_"|5|"_a, label_": class, origin, name, ContentType, decoded size and the CSP session's Ref (not the body's)")
	}
	// Markdown and plain text of exactly the limit are accepted as well.
	Kill ^OcuTalonTest("DocumentsProbe", "submits")
	Set body = ..CallStream("Add", a, ..Body("limit.md", ##class(OcuTalon.Web.Documents).#FILEMAX), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a .md of 10,485,760 bytes is accepted: "_$Extract(body, 1, 200))
	Do $$$AssertEquals(..Submit(1, "size"), 10485760, "with all its bytes")
}

/// Every refusal of the Matrix, with its reason, and nothing submitted.
Method TestAddRefused()
{
	Set a = ..Session("a")
	Set limit = ##class(OcuTalon.Web.Documents).#FILEMAX
	Set text = "OcuTalon can add Markdown, plain-text, PDF and Word (.docx) files up to 10 MB."
	Set b64 = "aGVsbG8="
	Set cases = $ListBuild(
		$ListBuild("photo.png", b64, "wrong_type"), $ListBuild("noextension", b64, "wrong_type"), $ListBuild("archive.md.exe", b64, "wrong_type"), $ListBuild("trailing.pdf.", b64, "wrong_type"), $ListBuild("old.doc", b64, "wrong_type"),
		$ListBuild("empty.md", "", "empty"), $ListBuild("empty.pdf", "", "empty"))
	For i = 1:1:$ListLength(cases) {
		Set case = $List(cases, i)
		Set body = ..Call("Add", a, {"name": ($List(case, 1)), "content": ($List(case, 2))}.%ToJSON(), .response)
		Set label = $List(case, 1)_" ("_$List(case, 3)_")"
		Do $$$AssertEquals(response.Status, "400 Bad Request", label_" is 400")
		Do $$$AssertEquals(body, {"error": {"code": "bad_document", "message": (text)}, "reason": ($List(case, 3))}.%ToJSON(), label_": bad_document with its reason")
	}
	// A name that is not an extension of an accepted type is refused before the size is looked at.
	Set body = ..CallStream("Add", a, ..Body("big.png", limit + 1), .response)
	Do $$$AssertEquals($Piece($Piece(body, """reason"":""", 2), """", 1), "wrong_type", "a wrong type of 10 MB and a byte is wrong_type")
	// One file of each family, one byte over the limit, is refused too_large; the limit itself is accepted.
	For name = "over.md", "over.txt", "over.pdf", "over.docx" {
		Set body = ..CallStream("Add", a, ..Body(name, limit + 1), .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", name_" of 10,485,761 bytes is 400")
		Do $$$AssertEquals(body, {"error": {"code": "bad_document", "message": (text)}, "reason": "too_large"}.%ToJSON(), name_" is refused too_large")
	}
	Do $$$AssertEquals(..Submits(), 0, "nothing was submitted")
	For name = "edge.md", "edge.txt", "edge.pdf", "edge.docx" {
		Set body = ..CallStream("Add", a, ..Body(name, limit), .response)
		Do $$$AssertEquals(response.Status, "200 OK", name_" of 10,485,760 bytes is accepted: "_$Extract(body, 1, 200))
	}
	Do $$$AssertEquals(..Submits(), 4, "the four files at the limit were submitted")
	Kill ^OcuTalonTest("DocumentsProbe", "submits")
	// A body that is not an object with a string name of 1 to 255 characters and a string content of valid base64: bad_document, no reason.
	Set long = $Justify("", 252)
	Set long = $Translate(long, " ", "n")_".md"
	Set bad = $ListBuild("", "not json", "[]", "{}", "{""name"":""a.md""}", "{""content"":""aGVsbG8=""}", "{""name"":5,""content"":""aGVsbG8=""}", "{""name"":""a.md"",""content"":5}", "{""name"":""a.md"",""content"":null}", "{""name"":"""",""content"":""aGVsbG8=""}", "{""name"":"""_long_"x"",""content"":""aGVsbG8=""}", "{""name"":""a.md"",""content"":""!!!not base64!!!""}")
	For i = 1:1:$ListLength(bad) {
		Set json = $List(bad, i)
		Set body = ..Call("Add", a, json, .response)
		Set label = "body "_i_" '"_$Extract(json, 1, 40)_"'"
		Do $$$AssertEquals(response.Status, "400 Bad Request", label_" is 400")
		Do $$$AssertEquals(body, {"error": {"code": "bad_document", "message": (text)}}.%ToJSON(), label_": bad_document, no reason")
	}
	Do $$$AssertEquals(..Submits(), 0, "and nothing was submitted")
	// 255 characters is allowed.
	Set body = ..Call("Add", a, {"name": (long), "content": "aGVsbG8="}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a name of 255 characters is accepted: "_body)
}

/// A body of BODYMAX bytes is read; one byte more is refused 413 before parsing.
Method TestBodyBound()
{
	Set a = ..Session("a")
	Set max = ##class(OcuTalon.Web.Documents).#BODYMAX
	Do $$$AssertEquals(max, (((##class(OcuTalon.Web.Documents).#FILEMAX + 2) \ 3) * 4) + 4096, "BODYMAX is the base64 size of the limit plus 4,096")
	Set body = ..CallStream("Add", a, ..Body("bound.md", 5, max), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "a body of BODYMAX bytes is read: "_$Extract(body, 1, 200))
	Do $$$AssertEquals(..Submits(), 1, "and submitted")
	Set stream = ..Body("bound.md", 5, max + 1)
	Do $$$AssertEquals(stream.Size, max + 1, "the over-size body has one byte more")
	Set body = ..CallStream("Add", a, stream, .response)
	Do $$$AssertEquals(response.Status, "413 Content Too Large", "one byte more is 413")
	Do $$$AssertEquals(body, {"error": {"code": "body_too_large", "message": "OcuTalon can add Markdown, plain-text, PDF and Word (.docx) files up to 10 MB."}}.%ToJSON(), "body_too_large")
	Do $$$AssertEquals(..Submits(), 1, "and nothing more was submitted")
	// A body that is not JSON at all and over the bound is 413 too: the size is judged before the text is read.
	Set junk = ##class(%CSP.BinaryStream).%New()
	Do junk.Write($Justify("", 1000))
	For i = 1:1:(max \ 1000) + 1 Do junk.Write($Justify("", 1000))
	Do junk.Rewind()
	Set body = ..CallStream("Add", a, junk, .response)
	Do $$$AssertEquals(response.Status, "413 Content Too Large", "a junk body over the bound is 413, not 400")
}

/// The request stream with a 10 MB PDF and a non-ASCII name is parsed from the stream, never through a string.
Method TestLargeBody()
{
	Set name = "R"_$Char(233)_"sum"_$Char(233)_" "_$Char(8230)_" runbook "_$Char(955)_".pdf"
	Set stream = ..Body(name, ##class(OcuTalon.Web.Documents).#FILEMAX)
	Do $$$AssertTrue(stream.Size > 13000000, "the request body is about 14 MB: "_stream.Size)
	Set ok = ##class(OcuTalon.Web.Documents).ParseBody(stream, .parsed, .bytes)
	Do $$$AssertEquals(ok, 1, "the body parses")
	Do $$$AssertEquals(parsed, name, "with the exact non-ASCII name: "_$ZHex($Ascii($Extract(parsed, 2)))_" "_$Length(parsed)_" characters")
	Do $$$AssertEquals(bytes.Size, 10485760, "and exactly the 10,485,760 bytes of the file")
	Do bytes.Rewind()
	Do $$$AssertEquals(bytes.Read(4), "AAAA", "whose bytes are the file's")
	// A multi-byte character cut by a 32,000-byte read of the body is read whole, wherever the cut falls.
	Set wide = $Char(233, 8364, 55348, 56606)_".md"
	For pad = 31975:1:31990 {
		Set stream = ##class(%CSP.BinaryStream).%New()
		Do stream.Write($ZConvert("{""pad"":"""_$Translate($Justify("", pad), " ", "x")_""",""name"":"""_wide_""",""content"":""aGVsbG8=""}", "O", "UTF8"))
		Do stream.Rewind()
		Set ok = ##class(OcuTalon.Web.Documents).ParseBody(stream, .parsed, .bytes)
		If 'ok || (parsed '= wide) Do $$$AssertEquals(parsed, wide, "a name cut by the read at pad "_pad_" is whole")
		If 'ok || (parsed '= wide) Quit
	}
	Do $$$AssertEquals(parsed, wide, "the name is whole at every cut")
}

/// The owner's answers and a failed submit.
Method TestOutcomes()
{
	Set a = ..Session("a")
	Set doc = ##class(OcuTalon.Test.Data.Fixture).Document(a, "zz outcome.md")
	Set cases = $ListBuild($ListBuild("not_built", 501, "not_built"), $ListBuild("not_found", 500, "server_error"), $ListBuild("failed", 500, "server_error"), $ListBuild("zzother", 500, "server_error"), $ListBuild("status", 500, "server_error"), $ListBuild("none", 500, "server_error"))
	For i = 1:1:$ListLength(cases) {
		Set case = $List(cases, i)
		Set ^OcuTalonTest("DocumentsProbe", "answer") = $List(case, 1)
		Set body = ..Call("Add", a, {"name": "a.md", "content": "aGVsbG8="}.%ToJSON(), .response)
		Do $$$AssertEquals(+response.Status, $List(case, 2), "Add, the owner says "_$List(case, 1)_": "_$List(case, 2))
		Do $$$AssertEquals({}.%FromJSON(body).error.code, $List(case, 3), "Add, "_$List(case, 1)_": "_$List(case, 3))
		Set body = ..Call("Remove", a, , .response, doc)
		Set status = $Case($List(case, 1), "not_found": 404, : $List(case, 2))
		Set code = $Case($List(case, 1), "not_found": "not_found", : $List(case, 3))
		Do $$$AssertEquals(+response.Status, status, "Remove, the owner says "_$List(case, 1)_": "_status)
		Do $$$AssertEquals({}.%FromJSON(body).error.code, code, "Remove, "_$List(case, 1)_": "_code)
	}
	Set ^OcuTalonTest("DocumentsProbe", "answer") = "not_built"
	Set body = ..Call("Add", a, {"name": "a.md", "content": "aGVsbG8="}.%ToJSON(), .response)
	Do $$$AssertEquals({}.%FromJSON(body).error.message, "This part of OcuTalon isn't built yet.", "the not_built text is the API's own")
}

/// A read that fails (the CSP session has no OcuTalon session of the signed-in user) is 500 server_error, whatever the route, and nothing is submitted.
Method TestNoSession()
{
	Set own = ##class(OcuTalon.Test.Data.Fixture).Document(..Session("a"), "zz own.md")
	Set nobody = "zzNoSuchSession"
	Set body = ..Call("List", nobody, , .response)
	Do $$$AssertEquals(+response.Status, 500, "List is 500")
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "server_error", "List: server_error")
	Set body = ..Call("Add", nobody, {"name": "a.md", "content": "aGVsbG8="}.%ToJSON(), .response)
	Do $$$AssertEquals(+response.Status, 500, "Add is 500")
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "server_error", "Add: server_error")
	Set body = ..Call("Remove", nobody, , .response, own)
	Do $$$AssertEquals(+response.Status, 500, "Remove is 500")
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "server_error", "Remove: server_error")
	Do $$$AssertEquals(..Submits(), 0, "nothing was submitted")
}

/// The real Submit is reached by no other test until Story 19.4 enables DocumentOps (the guard answers first), so its source is read: it hands the
/// command to Commands.Submit with ORIGIN, which is web_user (AD-1: CommandsIn takes AddDocument and RemoveDocument from that origin only).
Method TestRealSubmitOrigin()
{
	Do $$$AssertEquals(##class(OcuTalon.Web.Documents).#ORIGIN, "web_user", "ORIGIN is web_user")
	Set method = ##class(%Dictionary.MethodDefinition).%OpenId("OcuTalon.Web.Documents||Submit")
	Do $$$AssertTrue($IsObject(method), "Web.Documents defines its own Submit")
	If '$IsObject(method) Quit
	Set code = ""
	Do method.Implementation.Rewind()
	While 'method.Implementation.AtEnd {
		Set code = code_method.Implementation.Read(2000)
	}
	Set code = $Translate(code, $Char(9, 10, 13)_" ")
	Do $$$AssertTrue(code [ "##class(OcuTalon.Core.Commands).Submit(command,..#ORIGIN,.result)", "Submit passes ORIGIN, and no other origin, to Commands.Submit: "_code)
	Do $$$AssertEquals($Length(code, "Submit("), 2, "and calls Commands.Submit once")
}

/// While DocumentOps is not running, nothing is submitted and the answer is 501 not_built (the send would wait for CommandsIn's timeout).
Method TestOwnerNotRunning()
{
	Set a = ..Session("a")
	Set own = ##class(OcuTalon.Test.Data.Fixture).Document(a, "zz own.md")
	Set ^OcuTalonTest("DocumentsProbe", "owner") = "off"
	Set body = ..Call("Add", a, {"name": "a.md", "content": "aGVsbG8="}.%ToJSON(), .response)
	Do $$$AssertEquals(+response.Status, 501, "Add is 501")
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "not_built", "not_built")
	Set body = ..Call("Remove", a, , .response, own)
	Do $$$AssertEquals(+response.Status, 501, "Remove is 501")
	Do $$$AssertEquals({}.%FromJSON(body).error.code, "not_built", "not_built")
	Set body = ..Call("Remove", a, , .response, "zzNoSuchRef")
	Do $$$AssertEquals(+response.Status, 404, "a document the session cannot see is 404 first")
	Do $$$AssertEquals(..Submits(), 0, "nothing was submitted")
	Kill ^OcuTalonTest("DocumentsProbe", "owner")
	Set body = ..Call("Add", a, {"name": "a.md", "content": "aGVsbG8="}.%ToJSON(), .response)
	Do $$$AssertEquals(response.Status, "200 OK", "with the owner running the add is submitted: "_body)
}

/// The real OwnerRunning reads the item's IsEnabled in the running production: enabled is running; disabled and unknown are not.
Method TestOwnerRunningReadsTheItem()
{
	Set item = ##class(OcuTalon.Test.Web.DocumentsOwnerProbe).#OWNER
	Kill ^Ens.Runtime("ConfigItem", item)
	Do $$$AssertEquals(##class(OcuTalon.Test.Web.DocumentsOwnerProbe).Running(), 0, "an item the production does not hold is not running")
	Set ^Ens.Runtime("ConfigItem", item, "IsEnabled") = 0
	Do $$$AssertEquals(##class(OcuTalon.Test.Web.DocumentsOwnerProbe).Running(), 0, "a disabled item is not running")
	Set ^Ens.Runtime("ConfigItem", item, "IsEnabled") = 1
	Do $$$AssertEquals(##class(OcuTalon.Test.Web.DocumentsOwnerProbe).Running(), 1, "an enabled item is running")
	Kill ^Ens.Runtime("ConfigItem", item)
}

/// Remove checks the session's view first.
Method TestRemove()
{
	Set a = ..Session("a"), b = ..Session("b")
	Set own = ##class(OcuTalon.Test.Data.Fixture).Document(a, "zz own.md")
	Set theirs = ##class(OcuTalon.Test.Data.Fixture).Document(b, "zz theirs.md")
	Set shared = ##class(OcuTalon.Test.Data.Fixture).Document("instance", "zz shared.md")
	Set notFound = {"error": {"code": "not_found", "message": "OcuTalon has nothing at this address."}}.%ToJSON()
	For ref = theirs, shared, "zzNoSuchRef", $ZConvert(own, "U"), "" {
		Set body = ..Call("Remove", a, , .response, ref)
		Do $$$AssertEquals(response.Status, "404 Not Found", "'"_ref_"' is 404 for A")
		Do $$$AssertEquals(body, notFound, "with not_found")
	}
	Do $$$AssertEquals(..Submits(), 0, "nothing was submitted")
	Set body = ..Call("Remove", a, "{""sessionRef"":"""_b_"""}", .response, own)
	Do $$$AssertEquals(response.Status, "200 OK", "an own document is removed: "_body)
	Do $$$AssertEquals(body, "{""result"":""done""}", "{""result"":""done""}")
	Do $$$AssertEquals(..Submits(), 1, "one command")
	Do $$$AssertEquals(..Submit(1, "class")_"|"_..Submit(1, "origin")_"|"_..Submit(1, "documentRef")_"|"_..Submit(1, "sessionRef"), "OcuTalon.Msg.Command.RemoveDocument|web_user|"_own_"|"_a, "a RemoveDocument for the document and the CSP session")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Set body = ..Call("Remove", a, , .response, shared)
	Do $$$AssertEquals(response.Status, "200 OK", "on a local install the instance's document is removable: "_body)
	Do $$$AssertEquals(..Submit(2, "documentRef"), shared, "and the command names it")
	Set body = ..Call("Remove", a, , .response, theirs)
	Do $$$AssertEquals(response.Status, "404 Not Found", "but not another session's own document")
	Do $$$AssertEquals(..Submits(), 2, "and nothing more was submitted")
}

/// The forwarded dispatch runs the browser envelope: a state-changing call without it is refused 403 before the route.
Method TestEnvelope()
{
	Set ^OcuTalonTest("DocumentsProbe", "roles") = "%DB_OCUTALON,"_##class(OcuTalon.Web.Public.Shell).#ROLE
	Set origin = "http://localhost:52773", host = "localhost:52773"
	For method = "POST", "DELETE" {
		Set url = $Select(method = "POST": "", 1: "/zzRef")
		Set written = ..PreDispatch(url, method, "text/plain", "1", origin, host, .continue)
		Do $$$AssertEquals(continue, 0, method_" with the wrong Content-Type stops the dispatch")
		Do $$$AssertEquals({}.%FromJSON(written).error.code, "not_json", method_": not_json")
		Set written = ..PreDispatch(url, method, "application/json", "", origin, host, .continue)
		Do $$$AssertEquals({}.%FromJSON(written).error.code, "no_request_header", method_": no_request_header")
		Set written = ..PreDispatch(url, method, "application/json", "1", "http://evil.example", host, .continue)
		Do $$$AssertEquals({}.%FromJSON(written).error.code, "wrong_origin", method_": wrong_origin")
		Set written = ..PreDispatch(url, method, "application/json; charset=utf-8", "1", origin, host, .continue)
		Do $$$AssertEquals(continue_"|"_written, "1|", method_" with the full envelope goes on")
	}
	Set written = ..PreDispatch("", "GET", "", "", "", host, .continue)
	Do $$$AssertEquals(continue_"|"_written, "1|", "a GET needs no envelope")
	Set ^OcuTalonTest("DocumentsProbe", "roles") = "%DB_OCUTALON"
	Set written = ..PreDispatch("", "GET", "", "", "", host, .continue)
	Do $$$AssertEquals(continue, 0, "a signed-in user without the OcuTalon user role is stopped")
	Do $$$AssertEquals({}.%FromJSON(written).error.code, "no_role", "no_role")
}

/// --- helpers ---
/// A fixture session of the IRIS user who runs the tests (the user that Ownership.SessionRef resolves the CSP session for; the name only
/// says which of the test's sessions it is). Returns its Ref.
Method Session(name As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Session($Username)
}

/// Calls the route method of the probe as the CSP session of the session (a body is the request's content, UTF-8 bytes as the CSP server
/// hands it over); response is the %response, and the result is what the route wrote.
Method Call(method As %String, session As %String, body As %String = "", Output response, args...) As %String [ Private ]
{
	New %request, %response, %session
	Set application = "/ocutalon/api/"
	Set %request = $Select(body = "": ##class(OcuTalon.Test.Web.StubRequest).Make(application), 1: ##class(OcuTalon.Test.Web.StubRequest).MakeBody(application, body, 1))
	Quit ..Run(method, session, .response, args...)
}

/// As Call, with the request's content a stream that the test built.
Method CallStream(method As %String, session As %String, stream As %CSP.BinaryStream, Output response, args...) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).Make("/ocutalon/api/")
	Do stream.Rewind()
	Set %request.Content = stream
	Quit ..Run(method, session, .response, args...)
}

/// The call itself, with the globals of the caller set.
Method Run(method As %String, session As %String, Output response, args...) As %String [ Private ]
{
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzDocumentsApi"_..Number, 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, method, args...)
	Do $$$AssertStatusOK(sc, method_" returns OK")
	Set response = %response
	Quit written
}

/// A request of the method that keeps the browser envelope (the JSON Content-Type, X-OcuTalon-Request, its own Origin).
ClassMethod Envelope(method As %String) As OcuTalon.Test.Web.StubRequest [ Private ]
{
	Quit ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", method, "application/json", "1", "http://localhost:52773", "localhost:52773")
}

/// Runs OnPreDispatch of the probe for the URL and method with a stand-in request; returns what it wrote. continue is the dispatch flag it left.
Method PreDispatch(url As %String, method As %String, contentType As %String, header As %String, origin As %String, host As %String, Output continue) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", method, contentType, header, origin, host)
	Set %response = ##class(%CSP.Response).%New()
	Set %session = ##class(%CSP.Session).%New("ZzDocumentsApiPre"_..Number, 0)
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

/// A request body for a file of that many bytes (a stream of UTF-8 bytes, positioned at its start), without ever holding it in a string: the
/// JSON {"name","content"} with the content in base64, then spaces up to total bytes when total is given (the file's bytes are "A").
ClassMethod Body(name As %String, size As %Integer, total As %Integer = 0) As %CSP.BinaryStream
{
	Set object = {}
	Set object.name = name
	Set head = $Extract(object.%ToJSON(), 1, *-1)_",""content"":"""
	Set stream = ##class(%CSP.BinaryStream).%New()
	Do stream.Write($ZConvert(head, "O", "UTF8"))
	Set chunk = $Translate($Justify("", 30000), " ", "A")
	Set encoded = $SYSTEM.Encryption.Base64Encode(chunk, 1)
	Set left = size
	While left >= 30000 {
		Do stream.Write(encoded)
		Set left = left - 30000
	}
	If left > 0 Do stream.Write($SYSTEM.Encryption.Base64Encode($Extract(chunk, 1, left), 1))
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

/// The number of commands the probe recorded.
Method Submits() As %Integer [ Private ]
{
	Quit +$Get(^OcuTalonTest("DocumentsProbe", "submits"))
}

/// One field of the probe's nth command.
Method Submit(n As %Integer, field As %String) As %String [ Private ]
{
	Quit $Get(^OcuTalonTest("DocumentsProbe", "submits", n, field))
}

/// The refs of a list body, in order, comma-separated; only those in the list only when it is given.
Method Refs(body As %String, only As %List = "") As %String [ Private ]
{
	Set refs = ""
	Set documents = {}.%FromJSON(body).documents
	For i = 0:1:documents.%Size() - 1 {
		Set ref = documents.%Get(i).ref
		If (only '= "") && '$ListFind(only, ref) Continue
		Set refs = refs_$Select(refs = "": "", 1: ",")_ref
	}
	Quit refs
}

/// The keys of the first row of a list body, in order, comma-separated.
Method Keys(body As %String) As %String [ Private ]
{
	Set keys = ""
	Set iterator = {}.%FromJSON(body).documents.%Get(0).%GetIterator()
	While iterator.%GetNext(.key) {
		Set keys = keys_$Select(keys = "": "", 1: ",")_key
	}
	Quit keys
}

}
