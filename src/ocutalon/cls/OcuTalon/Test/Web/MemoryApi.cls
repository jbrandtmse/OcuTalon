/// Tests of the memory routes of OcuTalon.Web.Api (Story 41.2; AD-1, AD-4, AD-13, AD-21; FR-72): POST /v1/decisions/:ref/noise, GET /v1/memory/precedents,
/// DELETE /v1/memory/precedents/:ref and GET /v1/memory/notes, called with stand-in request and response objects and a CSP session whose OcuTalon.SessionRef is a
/// fixture session. Safe on a slot: the writes go through the SubmitMemory seam of Test.Web.MemoryApiProbe, which answers what the test scripts and records
/// what the route submitted; the reads (Ownership) are the real ones. The signed-out 401 comes from the superclass ApiBase and is tested over real HTTP
/// (web/e2e/api/memory.spec.ts). The expected texts are written out here, never read from Web.Api. The fixture sessions, Decisions and Precedent rows are
/// removed by Ref.
///   - TestListPrecedents: the session's own rows, newest first, at most 100, each with the seven members of the view, and no seeded row and no other session's;
///   - TestForgetPrecedent: a ref the session can't see is 404 before anything is submitted; its own row submits a ForgetPrecedent for the session and answers
///     200 {"result":"done"}; the owner's other answers are mapped;
///   - TestNoise: a decision the session can't see is 404 before anything is submitted; its own submits a MarkNoise with channel phone only for the exact body
///     {"channel":"phone"}; the owner's answers are mapped (marked and already_marked 200 with markedAt; too_old 409; not_found 404; not_built 501; the rest 500);
///   - TestTooOldText: the approved sentence of the 409, pinned by a copy held here;
///   - TestNotes: today, yesterday and no day are 200 {"day","date","lines":[]} for a session that has no records, with the instance-zone date, and any other day is 404;
///   - TestNoteLines: the note text is split on line feeds into non-empty strings, the builder gets the session and the local date, and a throw is 500 server_error;
///   - TestNoSessionIs500: with no CSP session every route is 500 server_error and nothing is submitted.
Class OcuTalon.Test.Web.MemoryApi Extends %UnitTest.TestCase
{

/// The class of the stand-in whose seam answers the owner.
Parameter PROBE = "OcuTalon.Test.Web.MemoryApiProbe";

/// The approved text of the noise route's 409 too_old (public text), held here word for word.
Parameter TOOOLD = "This notice is too old to mark as noise. Nothing was changed.";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the Precedent rows of the run, comma-separated.
Property Rows As %String(MAXLEN = "");

/// The session that the stand-in CSP session is bound to.
Property Current As %String;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("MemoryApi", "n"))
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("MemoryApiProbe")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	For i = 1:1:$Length(..Rows, ",") {
		Set ref = $Piece(..Rows, ",", i)
		If ref '= "" {
			Set row = ##class(OcuTalon.Data.Precedent).RefIndexOpen(ref)
			If $IsObject(row) Do ##class(OcuTalon.Data.Precedent).%DeleteId(row.%Id())
		}
	}
	Set ..Rows = ""
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Kill ^OcuTalonTest("MemoryApiProbe")
	Quit $SYSTEM.Status.OK()
}

/// GET /v1/memory/precedents answers the session's own rows newest first, each as the seven members of the view, and no seeded row and no row of another session.
Method TestListPrecedents()
{
	Set session = ..Session(), other = ..OtherSession()
	Set body = ..Call("Precedents", .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "200 JSON")
	Do $$$AssertEquals(body, "{""precedents"":[]}", "no rows: an empty list")
	Set a = ..Make(session, "2030-01-01T10:00:00Z"), b = ..Make(session, "2030-01-03T10:00:00Z"), c = ..Make(session, "2030-01-02T10:00:00Z")
	Do ..Make(other, "2030-01-04T10:00:00Z"), ..Make("eval", "2030-01-05T10:00:00Z", "zzrun")
	Set body = ..Call("Precedents", .response)
	Set answer = {}.%FromJSON(body)
	Set refs = ""
	For i = 0:1:answer.precedents.%Size() - 1 {
		Set refs = refs_$Select(refs = "": "", 1: ",")_answer.precedents.%Get(i).ref
	}
	Do $$$AssertEquals(refs, b_","_c_","_a, "the session's own rows, newest first, and nobody else's")
	Set item = answer.precedents.%Get(0)
	Set names = ""
	Set iterator = item.%GetIterator()
	While iterator.%GetNext(.name, .value) {
		Set names = names_$Select(names = "": "", 1: ",")_name
	}
	Do $$$AssertEquals(names, "ref,answeredAt,channel,answeredChannel,summary,outcome,answer", "the seven members, in order")
	Do $$$AssertEquals(item.answeredAt_"|"_item.channel_"|"_item.answeredChannel_"|"_item.summary_"|"_item.outcome_"|"_item.answer, "2030-01-03T10:00:00Z|mailbox|phone|zz summary|tellnow|noise", "and their values")
	For i = 1:1:101 {
		Do ..Make(session, "2031-01-01T10:00:"_$Extract(100 + (i # 60), 2, 3)_"Z")
	}
	Set answer = {}.%FromJSON(..Call("Precedents", .response))
	Do $$$AssertEquals(answer.precedents.%Size(), 100, "at most 100 rows")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("MemoryApiProbe", "submitted")), 0, "(nothing was submitted)")
}

/// DELETE /v1/memory/precedents/:ref: a ref the session can't see (another session's, a seeded row's, an unknown or an empty one) is 404 not_found before
/// anything is submitted; its own submits one ForgetPrecedent for the session and answers 200 {"result":"done"}; the owner's other answers are mapped.
Method TestForgetPrecedent()
{
	Set session = ..Session(), other = ..OtherSession()
	Set mine = ..Make(session, "2030-01-01T10:00:00Z")
	Set theirs = ..Make(other, "2030-01-02T10:00:00Z")
	Set seeded = ..Make("eval", "2030-01-03T10:00:00Z", "zzrun")
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(1, "forgotten")
	For ref = theirs, seeded, "zzunknown", "zz" {
		Set body = ..Call("ForgetPrecedent", .response, ref)
		Do $$$AssertEquals(response.Status_"|"_body, "404 Not Found|"_..ErrorBody("not_found", "OcuTalon has nothing at this address."), "'"_ref_"' is 404 not_found")
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("MemoryApiProbe", "submitted")), 0, "nothing was submitted for them")
	Set body = ..Call("ForgetPrecedent", .response, mine)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType_"|"_body, "200 OK|application/json|{""result"":""done""}", "its own row: 200 done")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted"), 1, "one command was submitted")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted", 1, "class")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "session")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "ref"), "OcuTalon.Msg.Command.ForgetPrecedent|"_session_"|"_mine, "a ForgetPrecedent for the session's own row")
	Set cases = $ListBuild($ListBuild("not_found", ..Spec(0, "not_found"), "404 Not Found", ..ErrorBody("not_found", "OcuTalon has nothing at this address.")), $ListBuild("not_built", ..Spec(0, "not_built"), "501 Not Implemented", ..ErrorBody("not_built", "This part of OcuTalon isn't built yet.")), $ListBuild("failed", ..Spec(0, "failed"), "500 Internal Server Error", ..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again.")), $ListBuild("an error status", "fail", "500 Internal Server Error", ..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again.")), $ListBuild("no result", "none", "500 Internal Server Error", ..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again.")))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set ^OcuTalonTest("MemoryApiProbe", "submit") = $List(case, 2)
		Set body = ..Call("ForgetPrecedent", .response, mine)
		Do $$$AssertEquals(response.Status_"|"_body, $List(case, 3)_"|"_$List(case, 4), $List(case, 1)_" is mapped")
	}
}

/// POST /v1/decisions/:ref/noise: the session's own decision is submitted as a MarkNoise with channel phone only for the exact body {"channel":"phone"}; a decision
/// the session can't see is 404 not_found and nothing is submitted; the owner's answers are mapped.
Method TestNoise()
{
	Set session = ..Session(), other = ..OtherSession()
	Set mine = ..Decision(session), theirs = ..Decision(other), seeded = ..Decision("eval")
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(1, "marked", "{""answeredAt"":""2030-01-01T10:00:00Z""}")
	For ref = theirs, seeded, "zzunknown", "zz" {
		Set body = ..Noise(.response, ref, "{""channel"":""phone""}")
		Do $$$AssertEquals(response.Status_"|"_body, "404 Not Found|"_..ErrorBody("not_found", "OcuTalon has nothing at this address."), "'"_ref_"' is 404 not_found")
	}
	Do $$$AssertEquals(+$Get(^OcuTalonTest("MemoryApiProbe", "submitted")), 0, "nothing was submitted for them")
	Set bodies = $ListBuild($ListBuild("{""channel"":""phone""}", "phone"), $ListBuild("{ ""channel"" : ""phone"" }", "phone"), $ListBuild("{""channel"":""web""}", "web"), $ListBuild("{""channel"":""Phone""}", "web"), $ListBuild("{""channel"":""phone"",""x"":1}", "web"), $ListBuild("{""channel"":1}", "web"), $ListBuild("{}", "web"), $ListBuild("[""phone""]", "web"), $ListBuild("""phone""", "web"), $ListBuild("zz not json", "web"), $ListBuild("{""channel"":""phone""", "web"))
	Set position = 0, n = 0
	While $ListNext(bodies, position, pair) {
		Set n = n + 1
		Set body = ..Noise(.response, mine, $List(pair, 1))
		Do $$$AssertEquals(response.Status_"|"_response.ContentType_"|"_body, "200 OK|application/json|{""result"":""done"",""markedAt"":""2030-01-01T10:00:00Z""}", "body "_$List(pair, 1)_": 200 done with markedAt")
		Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted", n, "class")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", n, "session")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", n, "ref"), "OcuTalon.Msg.Command.MarkNoise|"_session_"|"_mine, "body "_$List(pair, 1)_": a MarkNoise for the session's own decision")
		Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted", n, "channel"), $List(pair, 2), "body "_$List(pair, 1)_": channel "_$List(pair, 2))
	}
	Set body = ..Noise(.response, mine, "", 0)
	Do $$$AssertEquals(response.Status_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", n + 1, "channel"), "200 OK|web", "no body at all: 200, channel web")
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(1, "already_marked", "{""answeredAt"":""2030-01-02T10:00:00Z""}")
	Set body = ..Noise(.response, mine, "{}")
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""done"",""markedAt"":""2030-01-02T10:00:00Z""}", "already_marked: 200 done with the first time")
	Set tooOld = "{""error"":{""code"":""too_old"",""message"":"""_..#TOOOLD_"""}}"
	Set cases = $ListBuild($ListBuild("too_old", ..Spec(0, "too_old"), "409 Conflict", tooOld), $ListBuild("not_found", ..Spec(0, "not_found"), "404 Not Found", ..ErrorBody("not_found", "OcuTalon has nothing at this address.")), $ListBuild("not_built", ..Spec(0, "not_built"), "501 Not Implemented", ..ErrorBody("not_built", "This part of OcuTalon isn't built yet.")), $ListBuild("failed", ..Spec(0, "failed"), "500 Internal Server Error", ..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again.")), $ListBuild("not_allowed", ..Spec(0, "not_allowed"), "500 Internal Server Error", ..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again.")), $ListBuild("an error status", "fail", "500 Internal Server Error", ..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again.")), $ListBuild("no result", "none", "500 Internal Server Error", ..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again.")), $ListBuild("an Ok result whose Data is no JSON", ..Spec(1, "marked", "zz"), "500 Internal Server Error", ..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again.")))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set ^OcuTalonTest("MemoryApiProbe", "submit") = $List(case, 2)
		Set body = ..Noise(.response, mine, "{}")
		Do $$$AssertEquals(response.Status_"|"_body, $List(case, 3)_"|"_$List(case, 4), $List(case, 1)_" is mapped")
	}
}

/// The approved sentence of the 409 too_old: the parameter equals the copy held here, and the route's 409 body carries it word for word.
Method TestTooOldText()
{
	Do $$$AssertEquals($Parameter(..#PROBE, "MESSAGETOOOLD"), "This notice is too old to mark as noise. Nothing was changed.", "the parameter is the approved sentence")
	Do $$$AssertEquals($Parameter(..#PROBE, "MESSAGETOOOLD"), ..#TOOOLD, "and equals the test's copy")
	Set session = ..Session()
	Set mine = ..Decision(session)
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(0, "too_old")
	Set body = ..Noise(.response, mine, "{}")
	Do $$$AssertEquals(response.Status, "409 Conflict", "the status is 409")
	Set error = {}.%FromJSON(body).error
	Do $$$AssertEquals(error.code_"|"_error.message, "too_old|"_..#TOOOLD, "the code and the sentence")
}

/// GET /v1/memory/notes: today, yesterday and no day are 200 {"day","date","lines":[]} (the fixture session has no records, so the real builder answers no line), with the date of the day in
/// the instance zone; any other day is 404 not_found.
Method TestNotes()
{
	Set session = ..Session()
	Set before = $Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()), "T", 1)
	Set body = ..Notes("today", .response)
	Set after = $Piece(##class(OcuTalon.Data.Time).ToLocal(##class(OcuTalon.Data.Time).NowUtc()), "T", 1)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "today: 200 JSON")
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(answer.day_"|"_answer.lines.%Size(), "today|0", "the day and no lines")
	Do $$$AssertTrue((answer.date = before) || (answer.date = after), "the date is the instance zone's today: "_answer.date)
	Do $$$AssertTrue(answer.date ? 4N1"-"2N1"-"2N, "in the form YYYY-MM-DD")
	Do $$$AssertEquals(body, "{""day"":""today"",""date"":"""_answer.date_""",""lines"":[]}", "the members, in order")
	Set body = ..Notes("yesterday", .response)
	Set yesterday = {}.%FromJSON(body)
	Do $$$AssertEquals(response.Status_"|"_yesterday.day_"|"_yesterday.lines.%Size(), "200 OK|yesterday|0", "yesterday: 200")
	Do $$$AssertEquals($ZDateH(answer.date, 3) - $ZDateH(yesterday.date, 3), 1, "and it is the day before today")
	Set body = ..Notes("", .response, 0)
	Set none = {}.%FromJSON(body)
	Do $$$AssertEquals(response.Status_"|"_none.day, "200 OK|today", "no day means today")
	For day = "zz", "Today", "tomorrow", "2030-01-01" {
		Set body = ..Notes(day, .response)
		Do $$$AssertEquals(response.Status_"|"_body, "404 Not Found|"_..ErrorBody("not_found", "OcuTalon has nothing at this address."), "'"_day_"' is 404 not_found")
	}
}

/// The note text of the builder is split on line feeds, empty lines are dropped, the builder is given the session and the date that the answer carries, and a throw is 500.
Method TestNoteLines()
{
	Set session = ..Session()
	Set ^OcuTalonTest("MemoryApiProbe", "noteText") = "first" _ $Char(10) _ $Char(10) _ "second" _ $Char(10)
	Set body = ..Notes("today", .response)
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(response.Status_"|"_answer.lines.%ToJSON(), "200 OK|[""first"",""second""]", "two lines, no empty one")
	Do $$$AssertEquals($Get(^OcuTalonTest("MemoryApiProbe", "note", "session"))_"|"_$Get(^OcuTalonTest("MemoryApiProbe", "note", "date")), session_"|"_answer.date, "the builder got the session and the answer's date")
	Set body = ..Notes("yesterday", .response)
	Set yesterday = {}.%FromJSON(body)
	Do $$$AssertEquals($Get(^OcuTalonTest("MemoryApiProbe", "note", "date")), yesterday.date, "for yesterday it got yesterday's date")
	Set ^OcuTalonTest("MemoryApiProbe", "noteText") = "throw"
	Set body = ..Notes("today", .response)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again."), "a throw of the builder is 500 server_error")
	Do $$$AssertTrue($Get(^OcuTalonTest("MemoryApiProbe", "logged")) [ "zz the note could not be built", "and the cause is logged")
}

/// With no CSP session every route is 500 server_error, nothing is submitted, and the cause is logged.
Method TestNoSessionIs500()
{
	Set error = ..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again.")
	Set body = ..Call("Precedents", .response, , 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "the list is 500")
	Set body = ..Call("ForgetPrecedent", .response, "zzref", 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "the forget is 500")
	Set body = ..Noise(.response, "zzref", "{}", 1, 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "the noise mark is 500")
	Set body = ..Notes("today", .response, 1, 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "the notes are 500")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("MemoryApiProbe", "submitted")), 0, "nothing was submitted")
	Do $$$AssertTrue($Get(^OcuTalonTest("MemoryApiProbe", "logged")) '= "", "the cause is logged")
}

/// --- helpers ---
/// The fixture session of the IRIS user who runs the tests (the user that Ownership.SessionRef resolves the CSP session for).
Method Session() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Current = ref
	Quit ref
}

/// Another fixture session.
Method OtherSession() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzmemoryapiother")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A decide Decision of the owner, recorded for the clean-up. Returns its Ref.
Method Decision(owner As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Decision(owner, "decide")
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// Saves a Precedent row of the owner, recorded for the clean-up. Returns its Ref. A run Ref makes it a seeded row.
Method Make(owner As %String, answeredAt As %String, run As %String = "") As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Precedent).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.OwnerRef = owner
	Set row.Channel = "mailbox"
	Set row.MatchKey = "zz.memoryapi@example.com"
	Set row.Summary = "zz summary"
	Set row.Outcome = "tellnow"
	Set row.Answer = "noise"
	Set row.AnsweredAt = answeredAt
	Set row.AnsweredChannel = "phone"
	Set row.SourceRef = row.Ref
	Set row.EvalRunRef = run
	Do $$$AssertStatusOK(row.%Save(), "a fixture row is saved")
	Set ..Rows = ..Rows_$Select(..Rows = "": "", 1: ",")_row.Ref
	Quit row.Ref
}

/// The JSON of a scripted CommandResult.
Method Spec(ok As %Boolean, outcome As %String, data As %String = "") As %String [ Private ]
{
	Quit {"ok": (ok), "outcome": (outcome), "message": "zz owner message", "data": (data)}.%ToJSON()
}

/// Calls the route method of the probe with the stand-in request and the current session (none with noSession) and returns what it wrote.
Method Call(method As %String, Output response, ref As %String = "", noSession As %Boolean = 0) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", $Select(method = "ForgetPrecedent": "DELETE", 1: "GET"))
	Quit ..Run(method, .response, noSession, ref)
}

/// Calls MarkNoise with a request whose body is json (no body at all with hasBody 0).
Method Noise(Output response, ref As %String, json As %String, hasBody As %Boolean = 1, noSession As %Boolean = 0) As %String [ Private ]
{
	New %request, %response, %session
	If hasBody {
		Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", json)
	} Else {
		Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", "POST")
	}
	Quit ..Run("MarkNoise", .response, noSession, ref)
}

/// Calls Notes with the query value day (no query value when day is empty).
Method Notes(day As %String, Output response, hasDay As %Boolean = 1, noSession As %Boolean = 0) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", "GET")
	If hasDay && (day '= "") Do %request.Set("day", day)
	Quit ..Run("Notes", .response, noSession)
}

/// Runs the method of the probe as the CSP session of the current session; the caller has set %request.
Method Run(method As %String, Output response, noSession As %Boolean, ref As %String = "") As %String [ Private ]
{
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	If 'noSession {
		Set %session = ##class(%CSP.Session).%New("ZzMemoryApi"_..Number, 0)
		Set %session.Data("OcuTalon.SessionRef") = ..Current
	}
	If method = "Notes" || (method = "Precedents") {
		Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, method)
	} Else {
		Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, ..#PROBE, method, ref)
	}
	Do $$$AssertStatusOK(sc, method_" returns OK")
	Set response = %response
	Quit written
}

/// The error body of the route for the code and the message.
Method ErrorBody(code As %String, message As %String) As %String [ Private ]
{
	Quit {"error": {"code": (code), "message": (message)}}.%ToJSON()
}

}
