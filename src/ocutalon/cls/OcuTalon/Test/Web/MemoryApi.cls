/// Tests of the memory routes of OcuTalon.Web.Api (Stories 41.2 and 41.9; AD-1, AD-4, AD-13, AD-21; FR-72): POST /v1/decisions/:ref/noise, GET /v1/memory/precedents,
/// DELETE /v1/memory/precedents/:ref, GET /v1/memory/notes, GET /v1/memory/items, POST and DELETE /v1/memory/:ref/pin and DELETE /v1/memory/items/:ref, called with
/// stand-in request and response objects and a CSP session whose OcuTalon.SessionRef is a fixture session. Safe on a slot: the writes go through the SubmitMemory seam
/// of Test.Web.MemoryApiProbe, which records what the route submitted and answers what the test scripts, or in its real mode lets the real gate and the real MemoryOps
/// answer through shadow instances (a SearchMemory too, and in its timeout mode the real gate gets no answer in time); the precedent reads and the memory list (Ownership) are the real
/// ones, and the memory item reads go through the probe's ReadMemories seam, which records, fails, or makes the real read (the list through Ownership, the search through SearchMemory). The signed-out 401 comes from the superclass ApiBase and is tested over real HTTP (web/e2e/api/memory.spec.ts). The expected texts
/// are written out here, never read from Web.Api. None of these tests reads a memory through Memory.List or Memory.Search from the route: the list is Ownership's, and the search is
/// the SearchMemory verb that the real MemoryOps answers. The fixture sessions, Decisions and Precedent rows, and the fixture sessions' memory rows, are removed by Ref.
///   - TestListPrecedents: the session's own rows, newest first, at most 100, each with the seven members of the view, and no seeded row and no other session's;
///   - TestForgetPrecedent: a ref the session can't see is 404 before anything is submitted; its own row submits a ForgetPrecedent for the session and answers
///     200 {"result":"done"}; the owner's other answers are mapped;
///   - TestNoise: a decision the session can't see is 404 before anything is submitted; its own submits a MarkNoise with channel phone only for the exact body
///     {"channel":"phone"}; the owner's answers are mapped (marked and already_marked 200 with markedAt; too_old 409; not_found 404; not_built 501; the rest 500);
///   - TestTooOldText: the approved sentence of the 409, pinned by a copy held here;
///   - TestNotes: today, yesterday and no day are 200 {"day","date","lines":[]} for a session that has no records, with the instance-zone date, and any other day is 404;
///   - TestNoteLines: the note text is split on line feeds into non-empty strings, the builder gets the session and the local date, and a throw is 500 server_error;
///   - TestNoSessionIs500: with no CSP session every route is 500 server_error and nothing is submitted;
///   - TestItems (Story 41.9): GET /v1/memory/items lists the session's own memories newest first as {ref, text, savedAt, source, pinned} with the session's total, never
///     another session's, at most 20, through Ownership with no command submitted; q is trimmed and cut at 2,000 characters, a blank q lists, and a failed read is 500 server_error;
///   - TestItemsSearch: a search is a SearchMemory that the real MemoryOps answers with the session's own best memories only (on OcuTalon's image; a named skip elsewhere);
///   - TestSearchSubmitsTheVerb: a search submits one SearchMemory for the session and the trimmed q, relays the owner's items with their count, and maps the other answers: failed, not
///     allowed, an error status, no result and an answer whose Data is not an array of items are 500 server_error (the failed-search row); busy is 503 search_busy;
///   - TestSearchBusy: a search whose owner gives no answer in time (the real gate, with a send that times out) is 503 search_busy with the busy sentence, after a wait of 20 seconds, and logs no error;
///   - TestPinned (Story 41.13): GET /v1/memory/pinned submits one ListPinnedMemories for the session, relays the owner's {items, used} as they are, and maps the other answers (failed, an error status, no result and Data
///     that is not {items, used} are 500 server_error); through the real gate and the real MemoryOps it lists the session's own pins newest first with used from the core-memory block, and never another session's;
///   - TestPinnedBusy: a pinned read whose owner gives no answer in time is 503 search_busy with Retry-After 5, after the 20-second wait, and logs no error;
///   - TestSearchAllowance: an answer allowance to a search is 429 allowance with the messages route's body (retryAt, limit) and no Retry-After; through the real gate on the online demo a search past the limit is 429, sends nothing and records no Turn;
///   - TestSearchHandler: the real MemoryOps.OnSearch answers failed for an empty query, and searches only the command's own SessionRef (on OcuTalon's image; a named skip elsewhere);
///   - TestPin: POST and DELETE /v1/memory/:ref/pin submit PinMemory and UnpinMemory for the session with origin web_user; the owner's answers are mapped (done 200,
///     not_found 404, over_cap 409, not_built 501, the rest 500), and a ref that names no memory is 404 before anything is submitted; in real mode (the real gate and the real
///     MemoryOps, Story 41.12) an own memory is pinned (200) and unpinned (200), a pin over the cap is 409 over_cap and changes nothing, and another session's ref and an
///     unknown ref are 404 not_found and change nothing;
///   - TestOverCapText: the approved sentence of the 409, pinned by a copy held here;
///   - TestPinPhotoText (Story 26.3): the ruled sentence of the 409 pin_photo, pinned by a copy held here, for a pin only;
///   - TestForgetMemory: DELETE /v1/memory/items/:ref submits a ForgetMemory for the session; the owner's answers are mapped (an over_cap is not a 409 here); the real gate
///     and the real MemoryOps answer 404 for an unknown ref;
///   - TestForgetOtherSessionReal: through the real gate and the real MemoryOps, another session's real memory is 404 not_found and is kept, and the session's own is forgotten;
///   - TestRefLength (Story 41.9, QA): a ref of exactly 22 characters is submitted by all three write routes with the ref unchanged, and one of 23 is 404 before anything is submitted;
///   - TestItemsQuery: q is trimmed after the cut at 2,000 characters, a q of exactly 2,000 characters is kept whole, and a q of whitespace and control characters is blank;
///   - TestSessionNeverFromClient: a SessionRef, sessionRef, session or OwnerRef in the query or in a JSON body is ignored by the list, the search and the three writes;
///   - TestWriteRoutesBehindEnvelope: OnPreDispatch (past the role check) refuses the three write routes without the AD-13 envelope (not JSON, no X-OcuTalon-Request, wrong Origin) with
///     403, and lets the full envelope and the GET list through.
Class OcuTalon.Test.Web.MemoryApi Extends %UnitTest.TestCase
{

/// The class of the stand-in whose seam answers the owner.
Parameter PROBE = "OcuTalon.Test.Web.MemoryApiProbe";

/// The approved text of the noise route's 409 too_old (public text), held here word for word.
Parameter TOOOLD = "This notice is too old to mark as noise. Nothing was changed.";

/// The approved text of the pin route's 409 over_cap (public text), held here word for word.
Parameter OVERCAP = "That would go over the 1,000-token limit. Unpin something first.";

/// The ruled text of the pin route's 409 pin_photo (Story 26.3, public text), held here word for word.
Parameter PINPHOTO = "This memory came from a photo, so it can't be pinned.";

/// The text of the search's 503 search_busy (public text, pending the Planner's approval), held here word for word.
Parameter SEARCHBUSY = "Search is busy right now. Try again in a moment.";

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
	For i = 1:1:$Length(..Refs, ",") {
		If $Piece(..Refs, ",", i) '= "" Do ##class(OcuTalon.Test.Memory.Fixture).Purge($Piece(..Refs, ",", i))
	}
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

/// GET /v1/memory/items: the session's own memories newest first, each as the five members of the item (no origin), pinned a boolean, total the session's count, at
/// most 20 items, and never another session's. q is trimmed and cut at 2,000 characters before the read, a blank q is a list, and a failed read is 500 server_error.
Method TestItems()
{
	Set session = ..Session(), other = ..OtherSession()
	Set body = ..Items(.response, , 0)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType_"|"_body, "200 OK|application/json|{""items"":[],""total"":0}", "no memories: an empty list")
	Set a = ..Memory(session, "zz first", "2030-01-01T10:00:00Z", "learned", 1)
	Set b = ..Memory(session, "zz second", "2030-01-03T10:00:00Z")
	Set c = ..Memory(session, "zz third", "2030-01-02T10:00:00Z", "told")
	Do ..Memory(other, "zz other", "2030-01-04T10:00:00Z", "told", 1)
	Set none = ..Items(.response, , 0)
	Set blank = ..Items(.response, "   ")
	Do $$$AssertEquals(blank, none, "a blank q is the same list")
	Do $$$AssertEquals(+$Get(^OcuTalonTest("MemoryApiProbe", "submitted")), 0, "and a list submits no SearchMemory")
	Set answer = {}.%FromJSON(none)
	Set refs = ""
	For i = 0:1:answer.items.%Size() - 1 {
		Set refs = refs_$Select(refs = "": "", 1: ",")_answer.items.%Get(i).ref
	}
	Do $$$AssertEquals(refs, b_","_c_","_a, "the session's own memories, newest first, and nobody else's")
	Do $$$AssertEquals(answer.total, 3, "total is the session's count")
	Do $$$AssertEquals(answer.items.%Get(0).%ToJSON(), "{""ref"":"""_b_""",""text"":""zz second"",""savedAt"":""2030-01-03T10:00:00Z"",""source"":""told"",""pinned"":false}", "a row with no Source is told, unpinned, with the five members in order")
	Do $$$AssertEquals(answer.items.%Get(2).%ToJSON(), "{""ref"":"""_a_""",""text"":""zz first"",""savedAt"":""2030-01-01T10:00:00Z"",""source"":""learned"",""pinned"":true}", "a learned, pinned row says so")
	For i = 1:1:18 {
		Do ..Memory(session, "zz more "_i, "2031-01-01T10:00:"_$Extract(100 + i, 2, 3)_"Z")
	}
	Set answer = {}.%FromJSON(..Items(.response, , 0))
	Do $$$AssertEquals(answer.items.%Size()_"|"_answer.total, "20|21", "at most 20 items, and total is the whole count")
	Kill ^OcuTalonTest("MemoryApiProbe", "read")
	Set ^OcuTalonTest("MemoryApiProbe", "readMode") = "record"
	Set body = ..Items(.response, "  vpn gateway  ")
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""items"":[],""total"":0}", "a search with no hit is an empty list")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "read", "session")_"|"_^OcuTalonTest("MemoryApiProbe", "read", "query"), session_"|vpn gateway", "the read got the session's own Ref and the trimmed q")
	Do ..Items(.response, "   ")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "read", "query"), "", "a blank q reaches the read as empty")
	Do ..Items(.response, $Translate($Justify("", 2100), " ", "x"))
	Do $$$AssertEquals($Length(^OcuTalonTest("MemoryApiProbe", "read", "query")), 2000, "q is cut at 2,000 characters")
	Set ^OcuTalonTest("MemoryApiProbe", "readMode") = "fail"
	Set body = ..Items(.response, , 0)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again."), "a failed read is 500 server_error")
	Do $$$AssertTrue($Get(^OcuTalonTest("MemoryApiProbe", "logged")) [ "zz the memories could not be read", "and the cause is logged")
	Set ^OcuTalonTest("MemoryApiProbe", "readMode") = "ownershipFails"
	Set body = ..Items(.response, , 0)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again."), "a list that Ownership refuses (the real list branch fails) is 500 server_error, not an empty list")
}

/// With q the route searches (a SearchMemory that the real MemoryOps answers with the best 5) and answers only the session's own memories, total their number. Needs the embedder
/// of OcuTalon's image.
Method TestItemsSearch()
{
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do $$$AssertSkipped("Not OcuTalon's image: "_##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE_" does not exist on this instance (a slot or a developer instance)")
		Quit
	}
	Set session = ..Session(), other = ..OtherSession()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Prepare(.state), "the embedder is prepared")
	Try {
		Set mine = ##class(OcuTalon.Bridge.Ids).NewRef(), theirs = ##class(OcuTalon.Bridge.Ids).NewRef()
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(session, mine, "the VPN gateway is vpn.example.test", "2030-01-01T10:00:00Z"), "the session's memory is stored")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(other, theirs, "the VPN gateway of the other team is vpn.other.test", "2030-01-02T10:00:00Z"), "another session's memory is stored")
		Set ^OcuTalonTest("MemoryApiProbe", "submit") = "real"
		Set body = ..Items(.response, "vpn gateway")
		Set answer = {}.%FromJSON(body)
		Do $$$AssertEquals(response.Status, "200 OK", "200")
		Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "class")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "session"), "1|OcuTalon.Msg.Command.SearchMemory|"_session, "one SearchMemory was submitted, for the session")
		Do $$$AssertEquals(answer.items.%Size()_"|"_answer.total, "1|1", "one item, and total is the item count")
		Do $$$AssertEquals(answer.items.%Get(0).%ToJSON(), "{""ref"":"""_mine_""",""text"":""the VPN gateway is vpn.example.test"",""savedAt"":""2030-01-01T10:00:00Z"",""source"":""told"",""pinned"":false}", "it is the session's own memory, and not the other session's")
		Set mineRefs = mine
		For i = 1:1:6 {
			Set more = ##class(OcuTalon.Bridge.Ids).NewRef(), mineRefs = mineRefs_","_more
			Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(session, more, "the VPN gateway number "_i_" is vpn"_i_".example.test", "2030-01-0"_(i + 1)_"T10:00:00Z"), "another of the session's memories is stored")
		}
		Set answer = {}.%FromJSON(..Items(.response, "vpn gateway"))
		Set found = 1
		For i = 0:1:answer.items.%Size() - 1 {
			If (","_mineRefs_",") '[ (","_answer.items.%Get(i).ref_",") Set found = 0
		}
		Do $$$AssertEquals(answer.items.%Size()_"|"_answer.total, "5|5", "seven memories of the session match: the best 5 come back, and total is the item count")
		Do $$$AssertTrue(found, "and every one of them is the session's own, never the other session's")
	} Catch exception {
		Do $$$AssertTrue(0, "the search threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
}

/// A search submits one SearchMemory with the session's own Ref and the trimmed q (origin web_user, through the SubmitMemory seam), relays the items of the owner's answer with total
/// their number, and maps every other answer: not Ok (failed, not_allowed, any outcome), an error status, no result and Data that is not an array of items are 500 server_error
/// with the cause logged; Outcome busy is 503 search_busy with the busy sentence. This is the real search branch of the route (the probe's ReadMemories seam is not used).
Method TestSearchSubmitsTheVerb()
{
	Set session = ..Session()
	Set serverError = ..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again.")
	Set items = [{"ref": "zzmemone", "text": "zz one", "savedAt": "2030-01-01T10:00:00Z", "source": "told", "pinned": false}, {"ref": "zzmemtwo", "text": "zz two", "savedAt": "2030-01-02T10:00:00Z", "source": "learned", "pinned": true}]
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(1, "done", items.%ToJSON())
	Set body = ..Items(.response, "  vpn gateway  ")
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "200 OK|application/json", "200 JSON")
	Do $$$AssertEquals(body, {"items": (items), "total": 2}.%ToJSON(), "the owner's items, as they are, with total their number")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted"), 1, "one command was submitted")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted", 1, "class")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "session")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "ref"), "OcuTalon.Msg.Command.SearchMemory|"_session_"|vpn gateway", "a SearchMemory for the session and the trimmed q")
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(1, "done", "[]")
	Set body = ..Items(.response, "vpn")
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""items"":[],""total"":0}", "no hit: an empty list")
	Set cases = $ListBuild($ListBuild("failed", ..Spec(0, "failed")), $ListBuild("not_allowed", ..Spec(0, "not_allowed")), $ListBuild("an unknown outcome", ..Spec(0, "zz")), $ListBuild("a failed answer that carries items", ..Spec(0, "failed", "[]")), $ListBuild("an error status", "fail"), $ListBuild("no result", "none"), $ListBuild("Data that is not JSON", ..Spec(1, "done", "not json")), $ListBuild("Data that is an object", ..Spec(1, "done", "{}")), $ListBuild("no Data", ..Spec(1, "done")))
	Set position = 0
	While $ListNext(cases, position, case) {
		Kill ^OcuTalonTest("MemoryApiProbe", "logged")
		Set ^OcuTalonTest("MemoryApiProbe", "submit") = $List(case, 2)
		Set body = ..Items(.response, "vpn")
		Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_serverError, "a search answered with "_$List(case, 1)_" is 500 server_error")
		Do $$$AssertTrue($Get(^OcuTalonTest("MemoryApiProbe", "logged")) '= "", "and the cause is logged")
	}
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(0, "busy")
	Set body = ..Items(.response, "vpn")
	Do $$$AssertEquals(response.Status_"|"_response.ContentType_"|"_body, "503 Service Unavailable|application/json|"_..ErrorBody("search_busy", ..#SEARCHBUSY), "Outcome busy is 503 search_busy with the busy sentence")
	Do $$$AssertEquals(response.GetHeader("Retry-After"), 5, "and it carries Retry-After: 5")
}

/// A search whose owner gives no answer in time: the real gate (CommandsIn on a send that times out, as the framework does) answers Outcome busy after the 20-second wait for a SearchMemory,
/// and the route answers 503 search_busy with the busy sentence, never a hang or a 500, and logs no error. The busy sentence is held here word for word.
Method TestSearchBusy()
{
	Set session = ..Session()
	Do $$$AssertEquals($Parameter(..#PROBE, "MESSAGESEARCHBUSY"), "Search is busy right now. Try again in a moment.", "the parameter is the busy sentence")
	Do $$$AssertEquals($Parameter(..#PROBE, "MESSAGESEARCHBUSY"), ..#SEARCHBUSY, "and equals the test's copy")
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = "timeout"
	Set body = ..Items(.response, "vpn gateway")
	Do $$$AssertEquals(response.Status_"|"_response.ContentType_"|"_body, "503 Service Unavailable|application/json|"_..ErrorBody("search_busy", ..#SEARCHBUSY), "503 search_busy")
	Do $$$AssertEquals($Get(^OcuTalonTest("MemoryApiProbe", "waited")), 20, "after the wait of 20 seconds that the gate asked for")
	Do $$$AssertEquals(response.GetHeader("Retry-After"), 5, "with Retry-After: 5")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted", 1, "class")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "session"), "OcuTalon.Msg.Command.SearchMemory|"_session, "for a SearchMemory of the session")
	Do $$$AssertEquals($Get(^OcuTalonTest("MemoryApiProbe", "logged")), "", "and no error was logged: a busy search is not a server error")
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = "timeout"
	Set body = ..Call("ForgetMemory", .response, "zzmemref")
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again."), "control: a forget whose owner gives no answer is a failed command, 500, not busy")
	Do $$$AssertEquals(response.GetHeader("Retry-After"), "", "and carries no Retry-After")
	Do $$$AssertEquals($Get(^OcuTalonTest("MemoryApiProbe", "waited")), 120, "after the wait of 120 seconds")
}

/// GET /v1/memory/pinned submits one ListPinnedMemories for the session (origin web_user, through the SubmitMemory seam), relays the owner's {items, used} as they are, and maps every other
/// answer: not Ok, an error status, no result, and Data that is not an object of an items array and a numeric used are 500 server_error with the cause logged. Through the real gate and the
/// real MemoryOps the items are the session's own pins newest first and used is the core-memory block's tokens rounded up: pins of 2,000 and 1,956 characters make a block of 4,000
/// characters, which is 1000.
Method TestPinned()
{
	Set session = ..Session(), other = ..OtherSession()
	Set serverError = ..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again.")
	Set items = [{"ref": "zzmemone", "text": "zz one", "savedAt": "2030-01-01T10:00:00Z", "source": "told", "pinned": true}]
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(1, "done", {"items": (items), "used": 2}.%ToJSON())
	Set body = ..Call("PinnedMemories", .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType_"|"_body, "200 OK|application/json|"_{"items": (items), "used": 2}.%ToJSON(), "200 with the owner's items and used, as they are")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "class")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "session"), "1|OcuTalon.Msg.Command.ListPinnedMemories|"_session, "one ListPinnedMemories was submitted, for the session")
	Do $$$AssertEquals(response.GetHeader("Retry-After"), "", "with no Retry-After")
	Set cases = $ListBuild($ListBuild("failed", ..Spec(0, "failed")), $ListBuild("an unknown outcome", ..Spec(0, "zz")), $ListBuild("an error status", "fail"), $ListBuild("no result", "none"), $ListBuild("Data that is not JSON", ..Spec(1, "done", "not json")), $ListBuild("Data that is an array", ..Spec(1, "done", "[]")), $ListBuild("no used", ..Spec(1, "done", "{""items"":[]}")), $ListBuild("a used that is text", ..Spec(1, "done", "{""items"":[],""used"":""7""}")), $ListBuild("no items", ..Spec(1, "done", "{""used"":7}")), $ListBuild("no Data", ..Spec(1, "done")))
	Set position = 0
	While $ListNext(cases, position, case) {
		Kill ^OcuTalonTest("MemoryApiProbe", "logged")
		Set ^OcuTalonTest("MemoryApiProbe", "submit") = $List(case, 2)
		Set body = ..Call("PinnedMemories", .response)
		Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_serverError, "a pinned read answered with "_$List(case, 1)_" is 500 server_error")
		Do $$$AssertTrue($Get(^OcuTalonTest("MemoryApiProbe", "logged")) '= "", "and the cause is logged")
	}
	Kill ^OcuTalonTest("MemoryApiProbe", "submit"), ^OcuTalonTest("MemoryApiProbe", "readPinned")
	Set ^OcuTalonTest("MemoryApiProbe", "readPinnedMode") = "record"
	Set body = ..Call("PinnedMemories", .response)
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""items"":[],""used"":0}", "no pin: an empty list and used 0")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "readPinned", "session"), session, "the read got the session's own Ref")
	Set ^OcuTalonTest("MemoryApiProbe", "readPinnedMode") = "fail"
	Set body = ..Call("PinnedMemories", .response)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_serverError, "a failed read is 500 server_error")
	Kill ^OcuTalonTest("MemoryApiProbe", "readPinnedMode")

	Set first = ..Memory(session, $Translate($Justify("", 2000), " ", "a"), "2030-01-01T10:00:00Z", "told", 1)
	Set second = ..Memory(session, $Translate($Justify("", 1956), " ", "b"), "2030-01-02T10:00:00Z", "learned", 1)
	Do ..Memory(session, "zz never pinned", "2030-01-03T10:00:00Z", "told")
	Do ..Memory(other, "zz another session's pin", "2030-01-04T10:00:00Z", "told", 1)
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = "real"
	Set body = ..Call("PinnedMemories", .response)
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(response.Status, "200 OK", "through the real gate and MemoryOps: 200")
	Do $$$AssertEquals(answer.items.%Size()_"|"_answer.items.%Get(0).ref_"|"_answer.items.%Get(1).ref, "2|"_second_"|"_first, "the session's two pins, newest first, and nobody else's")
	Do $$$AssertEquals(answer.items.%Get(0).source_"|"_answer.items.%Get(0).pinned, "learned|1", "each with its source and pinned true")
	Do $$$AssertEquals(answer.used, 1000, "used is (36 + 3 + 2,000 + 3 + 1,956 + 2) / 4 = 1000")
}

/// A pinned read whose owner gives no answer in time (the real gate, on a send that times out) is 503 search_busy with the busy sentence and Retry-After 5, after the 20-second wait, and logs no
/// error. An answer of Outcome busy is the same.
Method TestPinnedBusy()
{
	Set session = ..Session()
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = "timeout"
	Set body = ..Call("PinnedMemories", .response)
	Do $$$AssertEquals(response.Status_"|"_response.ContentType_"|"_body, "503 Service Unavailable|application/json|"_..ErrorBody("search_busy", ..#SEARCHBUSY), "503 search_busy")
	Do $$$AssertEquals(response.GetHeader("Retry-After"), 5, "with Retry-After: 5")
	Do $$$AssertEquals($Get(^OcuTalonTest("MemoryApiProbe", "waited")), 20, "after the wait of 20 seconds that the gate asked for")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted", 1, "class")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "session"), "OcuTalon.Msg.Command.ListPinnedMemories|"_session, "for a ListPinnedMemories of the session")
	Do $$$AssertEquals($Get(^OcuTalonTest("MemoryApiProbe", "logged")), "", "and no error was logged")
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(0, "busy")
	Set body = ..Call("PinnedMemories", .response)
	Do $$$AssertEquals(response.Status_"|"_body, "503 Service Unavailable|"_..ErrorBody("search_busy", ..#SEARCHBUSY), "an answer of Outcome busy is the same")
	Do $$$AssertEquals(response.GetHeader("Retry-After"), 5, "with Retry-After: 5")
}

/// A search answered allowance is 429 allowance with exactly the messages route's body (the error, then retryAt and the limit as a number) and no Retry-After; an allowance answer whose Data holds no
/// retryAt and limit is 500. On the online demo through the real gate, with the limit at 2 and two entries held, a search is 429 with the oldest entry plus 3600 seconds, nothing is searched, no Turn
/// is recorded and the session's entries are unchanged; a blank list is not counted. The settings are put back.
Method TestSearchAllowance()
{
	Set session = ..Session()
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(0, "allowance", {"retryAt": "2030-01-01T00:00:00Z", "limit": 50}.%ToJSON())
	Set body = ..Items(.response, "vpn")
	Do $$$AssertEquals(response.Status_"|"_response.ContentType, "429 Too Many Requests|application/json", "an allowance answer is 429")
	Do $$$AssertEquals(body, "{""error"":{""code"":""allowance"",""message"":""You've used this session's 50 messages for the hour.""},""retryAt"":""2030-01-01T00:00:00Z"",""limit"":50}", "with the messages route's body")
	Do $$$AssertEquals(response.GetHeader("Retry-After"), "", "and no Retry-After")
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(0, "allowance", "{}")
	Set body = ..Items(.response, "vpn")
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again."), "an allowance answer with no retryAt and limit is 500")

	Set settings = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")_"|"_##class(OcuTalon.Data.Public.Settings).Get("messageAllowance")
	Try {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
		Do ##class(OcuTalon.Data.Public.Settings).Set("messageAllowance", 2)
		Set oldest = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -1000)
		Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
		Set row.AllowanceTimes = $ListBuild(oldest, ##class(OcuTalon.Data.Time).AddSeconds(oldest, 10))
		Do $$$AssertStatusOK(row.%Save(), "the session holds two entries")
		Kill ^OcuTalonTest("MemoryApiProbe")
		Set ^OcuTalonTest("MemoryApiProbe", "submit") = "real"
		Set body = ..Items(.response, "vpn")
		Do $$$AssertEquals(response.Status, "429 Too Many Requests", "through the real gate a search past the limit is 429")
		Do $$$AssertEquals(body, "{""error"":{""code"":""allowance"",""message"":""You've used this session's 2 messages for the hour.""},""retryAt"":"""_##class(OcuTalon.Data.Time).AddSeconds(oldest, 3600)_""",""limit"":2}", "with the oldest entry plus 3600 seconds and the limit")
		Set row = ##class(OcuTalon.Data.Session).RefIndexOpen(session)
		Do row.%Reload()
		Set turns = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Turn WHERE SessionRef = ?", session)
		Do turns.%Next()
		Do $$$AssertEquals($ListLength(row.AllowanceTimes)_"|"_row.AllowanceUntil_"|"_turns.%GetData(1), "2||0", "and it added no entry, no window and no Turn")
		Set body = ..Items(.response, , 0)
		Do $$$AssertEquals(response.Status, "200 OK", "the list is not counted")
	} Catch exception {
		Do $$$AssertTrue(0, "the allowance test threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", $Piece(settings, "|", 1))
	Do ##class(OcuTalon.Data.Public.Settings).Set("messageAllowance", $Piece(settings, "|", 2))
}

/// The real MemoryOps.OnSearch (on a shadow instance, as the production runs it): an empty or blank query answers failed (Ok 0) and throws nothing; with the embedder of OcuTalon's image it
/// answers Ok 1, done, with the items [{ref, text, savedAt, source, pinned}] of the command's own SessionRef only, so that another session's search for a phrase only the first session's memory
/// holds returns none of the first session's memories (a boolean pinned, no origin). The route sets that SessionRef (TestSessionNeverFromClient).
Method TestSearchHandler()
{
	Set owner = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Memory.Ops", .sc)
	Do $$$AssertStatusOK(sc, "a shadow instance of MemoryOps is made")
	Set session = ..Session(), other = ..OtherSession()
	For query = "", "   " {
		Set command = ##class(OcuTalon.Msg.Command.SearchMemory).%New()
		Set command.SessionRef = session
		Set command.Query = query
		Set sc = owner.OnSearch(command, .response)
		Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Data, "0|failed|", "a search for '"_query_"' answers failed, with no items")
	}
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do $$$AssertSkipped("Not OcuTalon's image: "_##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE_" does not exist on this instance (a slot or a developer instance)")
		Quit
	}
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Prepare(.state), "the embedder is prepared")
	Try {
		Set mine = ##class(OcuTalon.Bridge.Ids).NewRef(), lunch = ##class(OcuTalon.Bridge.Ids).NewRef()
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(session, mine, "the zzquokka gateway is quokka.example.test", "2030-01-01T10:00:00Z", "tool", "zzmemoryapi", "learned"), "the session's memory is stored")
		Set row = ##class(OcuTalon.Data.Memory).RefIndexOpen(mine)
		Set row.Pinned = 1
		Do $$$AssertStatusOK(row.%Save(), "and pinned")
		Set command = ##class(OcuTalon.Msg.Command.SearchMemory).%New()
		Set command.SessionRef = session
		Set command.Query = "zzquokka gateway"
		Set sc = owner.OnSearch(command, .response)
		Do $$$AssertStatusOK(sc, "the handler answers OK")
		Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|done", "Ok 1, done")
		Do $$$AssertEquals(response.Data, "[{""ref"":"""_mine_""",""text"":""the zzquokka gateway is quokka.example.test"",""savedAt"":""2030-01-01T10:00:00Z"",""source"":""learned"",""pinned"":true}]", "the session's own memory, in the five members, pinned a boolean, with no origin")
		Set command.SessionRef = other
		Set sc = owner.OnSearch(command, .response)
		Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Data, "1|done|[]", "another session's search for the same phrase finds none of the first session's memories")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(other, lunch, "an unrelated note about lunch", "2030-01-02T10:00:00Z"), "another session's own, unrelated memory is stored")
		Set sc = owner.OnSearch(command, .response)
		Do $$$AssertEquals(response.Ok_"|"_response.Outcome, "1|done", "the other session's search is answered")
		Do $$$AssertTrue(response.Data '[ mine, "and holds none of the first session's memories")
		Do $$$AssertTrue(response.Data [ lunch, "only its own")
	} Catch exception {
		Do $$$AssertTrue(0, "the search threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
}

/// POST and DELETE /v1/memory/:ref/pin submit a PinMemory and an UnpinMemory with the ref and the session's own Ref (origin web_user); Ok is 200 {"result":"done"}, and
/// the owner's other answers are mapped. A ref that is empty or too long names no memory: 404 before anything is submitted. In real mode the real gate lets web_user
/// through and the real MemoryOps (a shadow instance, as the production runs it) handles the pin: an own memory is pinned (200, Pinned 1) and unpinned (200, Pinned 0); with a pinned
/// 2,000-character memory, the pin of a 1,957-character one is 409 over_cap and the row is unchanged; another session's ref (an unpinned one for the pin, a pinned one for the unpin) and an unknown ref are 404 and nothing changes.
Method TestPin()
{
	Set session = ..Session()
	Set serverError = ..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again.")
	Set overCap = "{""error"":{""code"":""over_cap"",""message"":"""_..#OVERCAP_"""}}"
	For verb = "PinMemory", "UnpinMemory" {
		Kill ^OcuTalonTest("MemoryApiProbe")
		Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(1, "pinned")
		Set body = ..Call(verb, .response, "zzmemref")
		Do $$$AssertEquals(response.Status_"|"_response.ContentType_"|"_body, "200 OK|application/json|{""result"":""done""}", verb_": 200 done")
		Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted"), 1, verb_": one command was submitted")
		Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted", 1, "class")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "session")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "ref"), "OcuTalon.Msg.Command."_verb_"|"_session_"|zzmemref", verb_" for the session and the ref")
		For ref = "", $Translate($Justify("", 23), " ", "x") {
			Set body = ..Call(verb, .response, ref)
			Do $$$AssertEquals(response.Status_"|"_body, "404 Not Found|"_..ErrorBody("not_found", "OcuTalon has nothing at this address."), verb_": '"_ref_"' names no memory: 404")
		}
		Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted"), 1, verb_": and nothing more was submitted")
		Set cases = $ListBuild($ListBuild("not_found", ..Spec(0, "not_found"), "404 Not Found", ..ErrorBody("not_found", "OcuTalon has nothing at this address.")), $ListBuild("over_cap", ..Spec(0, "over_cap"), "409 Conflict", overCap), $ListBuild("not_built", ..Spec(0, "not_built"), "501 Not Implemented", ..ErrorBody("not_built", "This part of OcuTalon isn't built yet.")), $ListBuild("failed", ..Spec(0, "failed"), "500 Internal Server Error", serverError), $ListBuild("not_allowed", ..Spec(0, "not_allowed"), "500 Internal Server Error", serverError), $ListBuild("an error status", "fail", "500 Internal Server Error", serverError), $ListBuild("no result", "none", "500 Internal Server Error", serverError))
		Set position = 0
		While $ListNext(cases, position, case) {
			Set ^OcuTalonTest("MemoryApiProbe", "submit") = $List(case, 2)
			Set body = ..Call(verb, .response, "zzmemref")
			Do $$$AssertEquals(response.Status_"|"_body, $List(case, 3)_"|"_$List(case, 4), verb_": "_$List(case, 1)_" is mapped")
		}
	}
	Kill ^OcuTalonTest("MemoryApiProbe")
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = "real"
	Set other = ..OtherSession()
	Set own = ..Memory(session, "zz own memory", "2030-01-01T10:00:00Z")
	Set theirs = ..Memory(other, "zz another session's memory", "2030-01-02T10:00:00Z")
	Set theirsPinned = ..Memory(other, "zz another session's pinned memory", "2030-01-02T11:00:00Z", "", 1)
	Set body = ..Call("PinMemory", .response, own)
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""done""}", "real: the session's own memory is pinned, 200 done")
	Do $$$AssertEquals(..PinnedOf(own), 1, "and its Pinned is 1")
	Set body = ..Call("UnpinMemory", .response, own)
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""done""}", "real: and unpinned, 200 done")
	Do $$$AssertEquals(..PinnedOf(own), 0, "its Pinned is 0")
	Set big = ..Memory(session, $Translate($Justify("", 2000), " ", "a"), "2030-01-03T10:00:00Z", "", 1)
	Set over = ..Memory(session, $Translate($Justify("", 1957), " ", "b"), "2030-01-04T10:00:00Z")
	Set body = ..Call("PinMemory", .response, over)
	Do $$$AssertEquals(response.Status_"|"_body, "409 Conflict|"_overCap, "real: with a pinned 2,000-character memory, the pin of a 1,957-character one is 409 over_cap")
	Do $$$AssertEquals(..PinnedOf(over)_"|"_..PinnedOf(big), "0|1", "and nothing changed")
	For verb = "PinMemory", "UnpinMemory" {
		Set body = ..Call(verb, .response, $Select(verb = "PinMemory": theirs, 1: theirsPinned))
		Do $$$AssertEquals(response.Status_"|"_body, "404 Not Found|"_..ErrorBody("not_found", "OcuTalon has nothing at this address."), "real: "_verb_" of another session's ref is 404 not_found")
		Set body = ..Call(verb, .response, "zzMemoryPin0000000001")
		Do $$$AssertEquals(response.Status_"|"_body, "404 Not Found|"_..ErrorBody("not_found", "OcuTalon has nothing at this address."), "real: "_verb_" of an unknown ref is 404 not_found")
	}
	Do $$$AssertEquals(..PinnedOf(theirs)_"|"_..PinnedOf(theirsPinned), "0|1", "and the other session's memories are unchanged (one unpinned, one pinned)")
}

/// The stored Pinned of the memory with the Ref (0 for an empty one), read fresh.
ClassMethod PinnedOf(ref As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Pinned FROM OcuTalon_Data.Memory WHERE Ref = ?", ref)
	If result.%Next() Quit +result.%GetData(1)
	Quit "none"
}

/// The approved sentence of the 409 over_cap: the parameter equals the copy held here, and the route's 409 body carries it word for word.
Method TestOverCapText()
{
	Do $$$AssertEquals($Parameter(..#PROBE, "MESSAGEOVERCAP"), "That would go over the 1,000-token limit. Unpin something first.", "the parameter is the approved sentence")
	Do $$$AssertEquals($Parameter(..#PROBE, "MESSAGEOVERCAP"), ..#OVERCAP, "and equals the test's copy")
	Set session = ..Session()
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(0, "over_cap")
	Set body = ..Call("PinMemory", .response, "zzmemref")
	Do $$$AssertEquals(response.Status, "409 Conflict", "the status is 409")
	Set error = {}.%FromJSON(body).error
	Do $$$AssertEquals(error.code_"|"_error.message, "over_cap|"_..#OVERCAP, "the code and the sentence")
}

/// The sentence of the 409 pin_photo (Story 26.3, Planner ruling V3): the parameter equals the copy held here, a pin answered pin_photo is a 409 with that code and sentence, and
/// an unpin or a forget that is answered pin_photo is not (it is a 500, as any outcome the route does not map).
Method TestPinPhotoText()
{
	Do $$$AssertEquals($Parameter(..#PROBE, "MESSAGEPINPHOTO"), "This memory came from a photo, so it can't be pinned.", "the parameter is the ruled sentence")
	Do $$$AssertEquals($Parameter(..#PROBE, "MESSAGEPINPHOTO"), ..#PINPHOTO, "and equals the test's copy")
	Set session = ..Session()
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(0, "pin_photo")
	Set body = ..Call("PinMemory", .response, "zzmemref")
	Do $$$AssertEquals(response.Status, "409 Conflict", "the status is 409")
	Set error = {}.%FromJSON(body).error
	Do $$$AssertEquals(error.code_"|"_error.message, "pin_photo|"_..#PINPHOTO, "the code and the sentence")
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(0, "pin_photo")
	Set body = ..Call("UnpinMemory", .response, "zzmemref")
	Do $$$AssertEquals(response.Status, "500 Internal Server Error", "an unpin answered pin_photo is not a 409")
}

/// DELETE /v1/memory/items/:ref submits a ForgetMemory for the session and the ref (origin web_user), with no pre-check of the row: Ok is 200 {"result":"done"}; not_found 404;
/// not_built 501; anything else, an over_cap included, 500. A ref that names no memory is 404 before anything is submitted. In real mode the real gate and the real MemoryOps
/// answer 404 for a ref that is not a memory.
Method TestForgetMemory()
{
	Set session = ..Session()
	Set serverError = ..ErrorBody("server_error", "Something went wrong inside OcuTalon. Try again.")
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(1, "forgotten")
	Set body = ..Call("ForgetMemory", .response, "zzmemref")
	Do $$$AssertEquals(response.Status_"|"_response.ContentType_"|"_body, "200 OK|application/json|{""result"":""done""}", "200 done")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted"), 1, "one command was submitted")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted", 1, "class")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "session")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "ref"), "OcuTalon.Msg.Command.ForgetMemory|"_session_"|zzmemref", "a ForgetMemory for the session and the ref")
	For ref = "", $Translate($Justify("", 23), " ", "x") {
		Set body = ..Call("ForgetMemory", .response, ref)
		Do $$$AssertEquals(response.Status_"|"_body, "404 Not Found|"_..ErrorBody("not_found", "OcuTalon has nothing at this address."), "'"_ref_"' names no memory: 404")
	}
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted"), 1, "and nothing more was submitted")
	Set cases = $ListBuild($ListBuild("not_found", ..Spec(0, "not_found"), "404 Not Found", ..ErrorBody("not_found", "OcuTalon has nothing at this address.")), $ListBuild("not_built", ..Spec(0, "not_built"), "501 Not Implemented", ..ErrorBody("not_built", "This part of OcuTalon isn't built yet.")), $ListBuild("failed", ..Spec(0, "failed"), "500 Internal Server Error", serverError), $ListBuild("over_cap", ..Spec(0, "over_cap"), "500 Internal Server Error", serverError), $ListBuild("an error status", "fail", "500 Internal Server Error", serverError), $ListBuild("no result", "none", "500 Internal Server Error", serverError))
	Set position = 0
	While $ListNext(cases, position, case) {
		Set ^OcuTalonTest("MemoryApiProbe", "submit") = $List(case, 2)
		Set body = ..Call("ForgetMemory", .response, "zzmemref")
		Do $$$AssertEquals(response.Status_"|"_body, $List(case, 3)_"|"_$List(case, 4), $List(case, 1)_" is mapped")
	}
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = "real"
	Set body = ..Call("ForgetMemory", .response, "zzunknownref")
	Do $$$AssertEquals(response.Status_"|"_body, "404 Not Found|"_..ErrorBody("not_found", "OcuTalon has nothing at this address."), "the real gate and the real MemoryOps: a ref that is no memory is 404 not_found")
}

/// Through the real gate and the real MemoryOps.OnForget, another session's real memory is 404 not_found and is still stored, and the session's own memory is forgotten
/// (200 done) and gone. Needs the embedder of OcuTalon's image to store the rows.
Method TestForgetOtherSessionReal()
{
	If '##class(OcuTalon.Test.Memory.Fixture).OnImage() {
		Do $$$AssertSkipped("Not OcuTalon's image: "_##class(OcuTalon.Test.Memory.Fixture).#VERSIONFILE_" does not exist on this instance (a slot or a developer instance)")
		Quit
	}
	Set session = ..Session(), other = ..OtherSession()
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Prepare(.state), "the embedder is prepared")
	Try {
		Set mine = ##class(OcuTalon.Bridge.Ids).NewRef(), theirs = ##class(OcuTalon.Bridge.Ids).NewRef()
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(session, mine, "zz the session's own memory", "2030-01-01T10:00:00Z"), "the session's memory is stored")
		Do $$$AssertStatusOK(##class(OcuTalon.Test.Memory.Fixture).Store(other, theirs, "zz another session's memory", "2030-01-02T10:00:00Z"), "another session's memory is stored")
		Set ^OcuTalonTest("MemoryApiProbe", "submit") = "real"
		Set body = ..Call("ForgetMemory", .response, theirs)
		Do $$$AssertEquals(response.Status_"|"_body, "404 Not Found|"_..ErrorBody("not_found", "OcuTalon has nothing at this address."), "another session's memory: 404 not_found")
		Do $$$AssertEquals(##class(OcuTalon.Data.Memory).RefIndexExists(theirs), 1, "and it is still stored")
		Set body = ..Call("ForgetMemory", .response, mine)
		Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""done""}", "the session's own memory: 200 done")
		Do $$$AssertEquals(##class(OcuTalon.Data.Memory).RefIndexExists(mine), 0, "and it is gone")
	} Catch exception {
		Do $$$AssertTrue(0, "the real forget threw: "_exception.DisplayString())
	}
	Do ##class(OcuTalon.Test.Memory.Fixture).Restore(.state)
}

/// A ref of exactly MEMORYREFMAX (22) characters is a ref: all three write routes submit it unchanged. One of 23 characters names no memory and is 404 not_found before anything is submitted.
Method TestRefLength()
{
	Set session = ..Session()
	Set exact = $Translate($Justify("", 22), " ", "x"), over = exact_"x"
	Do $$$AssertEquals($Length(exact), 22, "the boundary ref is 22 characters")
	For verb = "PinMemory", "UnpinMemory", "ForgetMemory" {
		Kill ^OcuTalonTest("MemoryApiProbe")
		Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(1, "done")
		Set body = ..Call(verb, .response, exact)
		Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""done""}", verb_": a 22-character ref is submitted and answered")
		Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted"), 1, verb_": one command was submitted")
		Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted", 1, "ref")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "session"), exact_"|"_session, verb_": with the ref unchanged, for the session")
		Set body = ..Call(verb, .response, over)
		Do $$$AssertEquals(response.Status_"|"_body, "404 Not Found|"_..ErrorBody("not_found", "OcuTalon has nothing at this address."), verb_": a 23-character ref is 404")
		Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted"), 1, verb_": and nothing more was submitted")
	}
}

/// The q of the list route: cut at 2,000 characters and then trimmed (so a cut that ends in whitespace is trimmed too), kept whole at exactly 2,000, and blank when it holds
/// only whitespace and control characters (the list, not a search). Inner whitespace stays.
Method TestItemsQuery()
{
	Set session = ..Session()
	Set ^OcuTalonTest("MemoryApiProbe", "readMode") = "record"
	Set body = ..Items(.response, $Translate($Justify("", 2000), " ", "x"))
	Do $$$AssertEquals($Length(^OcuTalonTest("MemoryApiProbe", "read", "query")), 2000, "a q of exactly 2,000 characters is kept whole")
	Set body = ..Items(.response, $Translate($Justify("", 1999), " ", "x")_"     y")
	Do $$$AssertEquals($Length(^OcuTalonTest("MemoryApiProbe", "read", "query")), 1999, "a cut that ends in whitespace is trimmed: 1,999 characters")
	Do $$$AssertEquals($Extract(^OcuTalonTest("MemoryApiProbe", "read", "query"), 1999), "x", "and ends in the last letter")
	Set body = ..Items(.response, $Char(9, 10, 13)_"  ")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "read", "query"), "", "a q of tabs, line feeds and spaces is blank")
	Set body = ..Items(.response, "vpn   gateway")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "read", "query"), "vpn   gateway", "inner whitespace is kept")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "read", "session"), session, "and the read is for the session")
}

/// No route takes a session from the client (AD-4): a SessionRef, sessionRef, session or OwnerRef in the query string or in a JSON body is ignored. The list answers only the
/// session's own memories, the search reads for the session's Ref, and the three writes submit the session's Ref.
Method TestSessionNeverFromClient()
{
	Set session = ..Session(), other = ..OtherSession()
	Set mine = ..Memory(session, "zz mine", "2030-01-01T10:00:00Z")
	Set theirs = ..Memory(other, "zz theirs", "2030-01-02T10:00:00Z")
	Set body = ..ClientCall("MemoryItems", .response, "", other)
	Set answer = {}.%FromJSON(body)
	Do $$$AssertEquals(response.Status_"|"_answer.items.%Size()_"|"_answer.total, "200 OK|1|1", "the list with another session's Ref in the query: one item")
	Do $$$AssertEquals(answer.items.%Get(0).ref, mine, "and it is the session's own memory, not "_theirs)
	Set ^OcuTalonTest("MemoryApiProbe", "readMode") = "record"
	Set body = ..ClientCall("MemoryItems", .response, "", other, "vpn")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "read", "session")_"|"_^OcuTalonTest("MemoryApiProbe", "read", "query"), session_"|vpn", "the search reads for the session's Ref")
	Kill ^OcuTalonTest("MemoryApiProbe")
	Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(1, "done", "[]")
	Set body = ..ClientCall("MemoryItems", .response, "", other, "vpn")
	Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted", 1, "class")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "session"), "OcuTalon.Msg.Command.SearchMemory|"_session, "the SearchMemory carries the session's Ref, not the client's")
	For verb = "PinMemory", "UnpinMemory", "ForgetMemory" {
		Kill ^OcuTalonTest("MemoryApiProbe", "submitted")
		Set ^OcuTalonTest("MemoryApiProbe", "submit") = ..Spec(1, "done")
		Set body = ..ClientCall(verb, .response, "zzmemref", other)
		Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""done""}", verb_" is answered")
		Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted"), 1, verb_": one command was submitted")
		Do $$$AssertEquals(^OcuTalonTest("MemoryApiProbe", "submitted", 1, "session")_"|"_^OcuTalonTest("MemoryApiProbe", "submitted", 1, "ref"), session_"|zzmemref", verb_" is for the session's Ref, not the client's")
	}
}

/// OnPreDispatch (with the role check passed, as the probe does) applies the AD-13 envelope to the three write routes of the memory items: a call without a JSON Content-Type,
/// without X-OcuTalon-Request: 1 or with another site's Origin is 403 and the dispatch stops (continue 0); the whole envelope goes through; and the GET list is exempt.
Method TestWriteRoutesBehindEnvelope()
{
	Set message = "OcuTalon refused this request because it didn't come from the OcuTalon page."
	Set urls = $ListBuild($ListBuild("POST", "/v1/memory/zzmemref/pin"), $ListBuild("DELETE", "/v1/memory/zzmemref/pin"), $ListBuild("DELETE", "/v1/memory/items/zzmemref"))
	Set position = 0
	While $ListNext(urls, position, route) {
		Set method = $List(route, 1), url = $List(route, 2), label = method_" "_url
		Set body = ..PreDispatch(url, method, "application/json", "", "http://h:1", "h:1", .response, .continue)
		Do $$$AssertEquals(response.Status_"|"_continue_"|"_body, "403 Forbidden|0|"_..ErrorBody("no_request_header", message), label_" without X-OcuTalon-Request is refused and the dispatch stops")
		Set body = ..PreDispatch(url, method, "text/plain", "1", "http://h:1", "h:1", .response, .continue)
		Do $$$AssertEquals(response.Status_"|"_continue_"|"_..Code(body), "403 Forbidden|0|not_json", label_" with text/plain is refused")
		Set body = ..PreDispatch(url, method, "application/json", "1", "http://evil.example", "h:1", .response, .continue)
		Do $$$AssertEquals(response.Status_"|"_continue_"|"_..Code(body), "403 Forbidden|0|wrong_origin", label_" from another site is refused")
		Set body = ..PreDispatch(url, method, "application/json", "1", "http://h:1", "h:1", .response, .continue)
		Do $$$AssertEquals(continue_"|"_body, "1|", label_" with the whole envelope goes through")
	}
	Set body = ..PreDispatch("/v1/memory/items", "GET", "", "", "", "", .response, .continue)
	Do $$$AssertEquals(continue_"|"_body, "1|", "the GET list needs no envelope")
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
	Set body = ..Items(.response, , 0, 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "the memory items are 500")
	Set body = ..Items(.response, "vpn", 1, 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "a memory search is 500")
	Set body = ..Call("PinnedMemories", .response, , 1)
	Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, "the pinned read is 500")
	For method = "PinMemory", "UnpinMemory", "ForgetMemory" {
		Set body = ..Call(method, .response, "zzref", 1)
		Do $$$AssertEquals(response.Status_"|"_body, "500 Internal Server Error|"_error, method_" is 500")
	}
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

/// Saves a memory of the owner (a fixture session's Ref) with a vector that has no meaning, so that no embedder is needed; it is removed with the owner's Ref.
/// Returns its Ref. Source is empty for a row as saved before Story 41.8.
Method Memory(owner As %String, text As %String, savedAt As %String, source As %String = "", pinned As %Boolean = 0) As %String [ Private ]
{
	Set ones = ""
	For i = 1:1:384 {
		Set ones = ones_$Select(i > 1: ",", 1: "")_"1"
	}
	Set row = ##class(OcuTalon.Data.Memory).%New()
	Set row.Ref = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set row.SessionRef = owner
	Set row.Text = text
	Set row.SavedAt = savedAt
	Set row.ItemId = "zzmemoryapi"
	Set row.Origin = "tool"
	Set row.Source = source
	Set row.Pinned = pinned
	If pinned Set row.PinnedAt = savedAt
	Set row.Embedding = ##class(OcuTalon.Test.Memory.Fixture).ToVector(ones)
	Do $$$AssertStatusOK(row.%Save(), "a fixture memory is saved")
	Quit row.Ref
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
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", $Case(method, "ForgetPrecedent": "DELETE", "UnpinMemory": "DELETE", "ForgetMemory": "DELETE", "PinMemory": "POST", : "GET"))
	Quit ..Run(method, .response, noSession, ref)
}

/// Calls MemoryItems with the query value q (no query value when hasQ is 0 or q is empty).
Method Items(Output response, q As %String = "", hasQ As %Boolean = 1, noSession As %Boolean = 0) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeCall("/ocutalon/api/", "GET")
	If hasQ && (q '= "") Do %request.Set("q", q)
	Quit ..Run("MemoryItems", .response, noSession)
}

/// The error code of an error body, or "(no error)" when the body is not one.
Method Code(body As %String) As %String [ Private ]
{
	If body = "" Quit "(no error)"
	Set json = {}.%FromJSON(body)
	Quit $Select($IsObject(json.error): json.error.code, 1: "(no error)")
}

/// Calls the route method of the probe with the stand-in request that carries another session's Ref the way a client might send it: in the query (SessionRef, sessionRef,
/// session and OwnerRef) and in a JSON body. q is the search text of MemoryItems (none when empty).
Method ClientCall(method As %String, Output response, ref As %String = "", other As %String, q As %String = "") As %String [ Private ]
{
	New %request, %response, %session
	Set json = {"SessionRef": (other), "sessionRef": (other), "session": (other), "OwnerRef": (other)}.%ToJSON()
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", json)
	For name = "SessionRef", "sessionRef", "session", "OwnerRef" {
		Do %request.Set(name, other)
	}
	If q '= "" Do %request.Set("q", q)
	Quit ..Run(method, .response, 0, ref)
}

/// Runs OnPreDispatch of the probe (its HasUserRole answers 1) for the URL and method with a stand-in request made of the Content-Type, the X-OcuTalon-Request value, the Origin and
/// the Host (Test.Web.Api's PreDispatchOf); returns what it wrote. continue is the dispatch flag that it left.
Method PreDispatch(url As %String, method As %String, contentType As %String, header As %String, origin As %String, host As %String, Output response, Output continue) As %String [ Private ]
{
	Set body = ##class(OcuTalon.Test.Web.Api).PreDispatchOf(..#PROBE, "ZzMemoryApi"_..Number, url, method, contentType, header, origin, host, .response, .continue, .sc)
	Do $$$AssertStatusOK(sc, "OnPreDispatch returns OK")
	Quit body
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
	If method = "Notes" || (method = "Precedents") || (method = "MemoryItems") || (method = "PinnedMemories") {
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
