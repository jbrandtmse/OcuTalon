/// Tests of POST /v1/incidents/:ref/dismiss (Story 6.4; AD-1, AD-4, AD-15, AD-22, AD-26, AD-29), called with stand-in request and
/// response objects and a CSP session whose OcuTalon.SessionRef is the fixture session (as Test.Web.Api does), through the real
/// production: the route submits through Commands.Submit, CommandsIn sends the IncidentCommand, and the real IncidentManager item
/// answers it. THIS CLASS RUNS IN THROWAWAY STACKS AND IN CI ONLY (Rule 21): where OcuTalon.Production does not run every test fails
/// with that reason, so that a broken stack can never give a green shard. Demo mode is on for the whole run (the guide reads it); it is
/// put back, with onlineDemo, in OnAfterAllTests, which also removes the fixture rows, events and the sessions' messages. The commands
/// that IncidentManager received are read from the bodies of the CommandsIn to IncidentManager headers of the session's trace
/// (CommandList). Test.Demo.IncidentManagerDouble is put behind the item only inside TestOwnerErrorIs500, for the two answers the real
/// item never gives.
///   - TestOwnIncidentCloses: an own open (rejected) noticed incident, with a done request and its ended FixRun, answers 200
///     {"result":"done"}; its row is closed; one IncidentCommand dismiss (the ref, the session, origin web_user) reached IncidentManager,
///     with the session's TraceRef as SuperSession; one incident event of state closed carries the request and its result; no Turn and no
///     chat.message;
///   - TestResolvedIncidentCloses: a resolved incident closes the same way;
///   - TestBreakFeedAvailableAgain: with demo mode on and the session watching Orders, an open Orders incident keeps Break the feed
///     inactive (incident_in_progress) until its dismissal, and a guide.state event follows the closed incident event;
///   - TestRefusedIs409: an awaiting_approval incident and a fixing one are refused by the real item (not_allowed) and answer 409
///     not_dismissible with MESSAGENOTDISMISSIBLE, never 500, and the rows stay;
///   - TestRealItemAppliesAD15DismissRows (QA): through Commands.Submit, the real item refuses an open incident that is not noticed and a
///     closed one (Ok 0, Outcome not_allowed, its developer message, nothing published) and closes a resolved one (Ok 1, Outcome closed,
///     the Ref, ClosedAt, one closed view published);
///   - TestOwnerErrorIs500: with the double behind the item, its "error" setting answers 500 server_error and the row stays, and its
///     "refuse" setting (an answer with no Message) is 409 not_dismissible with MESSAGENOTDISMISSIBLE, and its default refusal of an
///     awaiting_approval incident (an outcome other than not_allowed, with a Message) is 409 not_dismissible with that Message; the real
///     item is put back inside the test, also after a failure, and again in OnAfterAllTests;
///   - TestOtherSessionsIncidentIs404 (AC7, a required CI check): with onlineDemo off and on, another session's noticed incident, an
///     unnoticed own one, an eval one, an unwatched instance one (and with the flag on a watched instance one) and an unknown ref
///     answer 404 not_found before anything is submitted: no command reaches IncidentManager, the rows stay and no incident event is published;
///   - TestBodyIsIgnored: a sessionRef in the body neither reaches another session's incident (404) nor changes the command's session.
Class OcuTalon.Test.Web.DismissApi Extends %UnitTest.TestCase
{

/// The run's number.
Property Number As %Integer;

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 200);

/// The TraceRefs of the fixture sessions, for the clean-up of the messages.
Property Traces As %DynamicArray;

/// The public setting onlineDemo before the tests, "" when it was absent.
Property SavedOnline As %String;

/// The demo.mode row before the tests (Test.Demo.Step.Saved).
Property SavedModeFound As %Boolean;

Property SavedModeValue As %String(MAXLEN = 1000);

Property SavedModeUpdatedAt As %String(MAXLEN = 20);

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("DismissApi", "n"))
	Set ..Traces = []
	Set ..Missing = ""
	Set ..SavedOnline = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set ..SavedModeFound = found, ..SavedModeValue = value, ..SavedModeUpdatedAt = updatedAt
	If '##class(Ens.Director).IsProductionRunning(.name) || (name '= "OcuTalon.Production") {
		Set ..Missing = "OcuTalon.Production does not run in OCUTALON: this class runs in throwaways and CI only (Rule 21)"
		Quit $SYSTEM.Status.OK()
	}
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, ##class(OcuTalon.Data.Time).NowUtc())
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	// The real item is back even when TestOwnerErrorIs500 died between Use and its own Restore (Restore does nothing when nothing was saved).
	Do ##class(OcuTalon.Test.Demo.IncidentManagerDouble).Restore()
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedOnline)
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..SavedModeFound, ..SavedModeValue, ..SavedModeUpdatedAt)
	Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Traces, "OCUTALON")
	Kill ^OcuTalonTest("IncidentManagerDouble")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

/// An own open (rejected) noticed incident with a done request and its ended FixRun: the closed view lists the request with its result.
Method TestOwnIncidentCloses()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set trace = ..TraceOf(session)
	Set request = ##class(OcuTalon.Bridge.Ids).NewRef()
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(session, , , , {"OpenVariant": "rejected", "RequestRefs": (request)})
	Do ##class(OcuTalon.Test.Data.Fixture).Approval(session, incident, "done", , {"Ref": (request)})
	Do ##class(OcuTalon.Test.Data.Fixture).FixRun(incident, request, {"Total": 50, "Resent": 50, "Completed": 50, "FailedAgain": 0, "Skipped": 0, "Interrupted": 0, "Reason": ""})
	Set body = ..Call(session, incident, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the answer is 200")
	Do $$$AssertEquals(response.ContentType, "application/json", "JSON")
	Do $$$AssertEquals(body, "{""result"":""done""}", "the body is {result: done}")
	Do $$$AssertEquals(..StateOf(incident), "closed", "the row is closed")
	Do $$$AssertEquals(..Commands(trace), 1, "IncidentManager got one command")
	Do $$$AssertEquals(..CommandOf(trace, 1), "dismiss|"_incident_"|"_session_"|web_user", "its verb, incident, session and origin")
	Set closed = ..ClosedEvents(session, incident)
	Do $$$AssertEquals(closed.%Size(), 1, "one incident event of state closed is published")
	If closed.%Size() = 1 {
		Set payload = closed.%Get(0).payload
		Do $$$AssertEquals(payload.requests.%Size(), 1, "it carries the incident's request")
		If payload.requests.%Size() = 1 Do $$$AssertEquals(payload.requests.%Get(0).ref_"|"_payload.requests.%Get(0).result.completed, request_"|50", "the request and its result")
	}
	Do $$$AssertEquals(..CommandsInHeaders(trace), 1, "one CommandsIn to IncidentManager header carries the session's TraceRef")
	Do $$$AssertEquals(..TurnCount(session), 0, "no Turn")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "chat.message").%Size(), 0, "and no chat.message")
}

/// A resolved incident closes the same way.
Method TestResolvedIncidentCloses()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(session, , , , {"State": "resolved", "OpenVariant": ""})
	Set body = ..Call(session, incident, .response)
	Do $$$AssertEquals(response.Status_"|"_body, "200 OK|{""result"":""done""}", "200 {result: done}")
	Do $$$AssertEquals(..StateOf(incident), "closed", "the row is closed")
	Do $$$AssertEquals(..Commands(..TraceOf(session)), 1, "one command")
	Do $$$AssertEquals(..ClosedEvents(session, incident).%Size(), 1, "and one closed event")
}

/// Break the feed: inactive while an open Orders incident stands (incident_in_progress), active after its dismissal.
Method TestBreakFeedAvailableAgain()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set ns = ##class(OcuTalon.Install.Step.Demo).#NAMESPACE, production = ##class(OcuTalon.Install.Step.Demo).#PRODUCTION
	Do ##class(OcuTalon.Test.Data.Fixture).Check(session, ns, production)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(session, , ns, production, {"OpenVariant": "rejected"})
	Set guide = ##class(OcuTalon.Demo.Guide).Compute(session)
	Do $$$AssertEquals(guide.BreakFeed.Active_"|"_guide.BreakFeed.Reason, "0|incident_in_progress", "before the dismissal Break the feed is inactive")
	Set body = ..Call(session, incident, .response)
	Do $$$AssertEquals(response.Status, "200 OK", "the dismissal is 200: "_body)
	Set guide = ##class(OcuTalon.Demo.Guide).Compute(session)
	Do $$$AssertEquals(guide.BreakFeed.Active_"|"_guide.BreakFeed.Reason, "1|", "after it Break the feed is active")
	Set events = ##class(OcuTalon.Live.Event).Since(session, 0, 200, "session")
	Set closedAt = -1, guideAfter = 0
	For i = 0:1:events.%Size() - 1 {
		Set event = events.%Get(i)
		If (event.type = "incident") && (event.payload.ref = incident) && (event.payload.state = "closed") Set closedAt = i
		If (closedAt >= 0) && (i > closedAt) && (event.type = "guide.state") && event.payload.breakFeed.active Set guideAfter = 1
	}
	Do $$$AssertTrue(closedAt >= 0, "a closed incident event is published")
	Do $$$AssertTrue(guideAfter, "and a guide.state event with Break the feed active follows it")
}

/// The real item's refusal (not_allowed) is 409 not_dismissible with MESSAGENOTDISMISSIBLE, not 500.
Method TestRefusedIs409()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set states = $ListBuild("awaiting_approval", "fixing")
	Set position = 0
	While $ListNext(states, position, state) {
		Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(session, , , , {"State": (state), "OpenVariant": ""})
		Set body = ..Call(session, incident, .response)
		Do $$$AssertEquals(response.Status, "409 Conflict", state_": the answer is 409")
		Do $$$AssertEquals(body, ..ErrorBody("not_dismissible", ##class(OcuTalon.Web.Api).#MESSAGENOTDISMISSIBLE), state_": not_dismissible with MESSAGENOTDISMISSIBLE")
		Do $$$AssertEquals(..StateOf(incident), state, state_": the row is unchanged")
	}
	Do $$$AssertEquals(..Commands(..TraceOf(session)), 2, "IncidentManager got both commands")
}

/// The dismiss rows of AD-15 on the real item, which the route's visibility check hides from the route tests: through Commands.Submit (the
/// route's call), an open incident that is not noticed and a closed one are refused (Ok 0, Outcome not_allowed, the item's developer message) and left
/// as they are with nothing published; a resolved one closes (Ok 1, Outcome closed, the Ref, ClosedAt set) and its closed view is published once.
Method TestRealItemAppliesAD15DismissRows()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set manager = "OcuTalon.Watch.IncidentManager"
	Set cases = $ListBuild($ListBuild("open and not noticed", $ClassMethod(fixture, "Incident", session, ""), "open", 0))
	Set cases = cases_$ListBuild($ListBuild("closed", $ClassMethod(fixture, "Incident", session, , , , {"State": "closed", "OpenVariant": ""}), "closed", 0))
	Set cases = cases_$ListBuild($ListBuild("resolved", $ClassMethod(fixture, "Incident", session, , , , {"State": "resolved", "OpenVariant": ""}), "resolved", 1))
	Set position = 0
	Set sent = 0
	While $ListNext(cases, position, case) {
		Set label = $List(case, 1), ref = $List(case, 2), state = $List(case, 3)
		Set eventsBefore = ..IncidentEvents(session)
		Set command = ##class(OcuTalon.Msg.Command.Dismiss).%New()
		Set command.IncidentRef = ref
		Set command.SessionRef = session
		Set sc = ##class(OcuTalon.Core.Commands).Submit(command, "web_user", .result)
		Set sent = sent + 1
		Do $$$AssertStatusOK(sc, label_": Submit returns OK")
		Do $$$AssertEquals(..Commands(..TraceOf(session)), sent, label_": IncidentManager got the command")
		If $List(case, 4) {
			Do $$$AssertEquals(result.Ok_"|"_result.Outcome_"|"_result.Ref, "1|closed|"_ref, label_": Ok 1, Outcome closed, the Ref")
			Do $$$AssertEquals(..StateOf(ref), "closed", label_": the row is closed")
			Do $$$AssertTrue(##class(OcuTalon.Data.Incident).RefIndexOpen(ref).ClosedAt '= "", label_": with ClosedAt")
			Do $$$AssertEquals(..ClosedEvents(session, ref).%Size(), 1, label_": and its closed view is published once")
		} Else {
			Do $$$AssertEquals(result.Ok_"|"_result.Outcome, "0|not_allowed", label_": Ok 0, Outcome not_allowed")
			Do $$$AssertEquals(result.Message, $Parameter(manager, "MESSAGENOTALLOWED"), label_": with the item's developer message")
			Do $$$AssertEquals(..StateOf(ref), state, label_": the row is unchanged")
			Do $$$AssertEquals(..IncidentEvents(session), eventsBefore, label_": and nothing is published")
		}
	}
}

/// The two answers the real item never gives, from the double behind the item: an error status is 500 server_error and the row stays, and a
/// refusal with no Message is 409 not_dismissible with MESSAGENOTDISMISSIBLE. The real item is put back in the test, also after a failure.
Method TestOwnerErrorIs500()
{
	If '..Guard() Quit
	Set session = ..Session()
	Set double = "OcuTalon.Test.Demo.IncidentManagerDouble"
	Kill ^OcuTalonTest("IncidentManagerDouble")
	Set swapped = $ClassMethod(double, "Use")
	Do $$$AssertStatusOK(swapped, "the double is put behind the IncidentManager item")
	Try {
		If $SYSTEM.Status.IsOK(swapped) {
			Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(session)
			Set ^OcuTalonTest("IncidentManagerDouble", "answer") = "error"
			Set body = ..Call(session, incident, .response)
			Do $$$AssertEquals(response.Status, "500 Internal Server Error", "an error status is 500")
			Do $$$AssertEquals(body, ..ErrorBody("server_error", ##class(OcuTalon.Web.Api).#MESSAGESERVERERROR), "server_error")
			Do $$$AssertEquals(..StateOf(incident), "open", "the row is unchanged")
			Set ^OcuTalonTest("IncidentManagerDouble", "answer") = "refuse"
			Set body = ..Call(session, incident, .response)
			Do $$$AssertEquals(response.Status, "409 Conflict", "a refusal with no Message is 409")
			Do $$$AssertEquals(body, ..ErrorBody("not_dismissible", ##class(OcuTalon.Web.Api).#MESSAGENOTDISMISSIBLE), "with MESSAGENOTDISMISSIBLE")
			Do $$$AssertEquals(..StateOf(incident), "open", "the row is unchanged")
			Kill ^OcuTalonTest("IncidentManagerDouble", "answer")
			Set held = ##class(OcuTalon.Test.Data.Fixture).Incident(session, , , , {"State": "awaiting_approval", "OpenVariant": ""})
			Set body = ..Call(session, held, .response)
			Do $$$AssertEquals(response.Status, "409 Conflict", "a refusal of another outcome than not_allowed is 409")
			Do $$$AssertEquals(body, ..ErrorBody("not_dismissible", "zz the double refuses to dismiss an incident that is awaiting_approval"), "with the Message that the outcome carries")
			Do $$$AssertEquals(..StateOf(held), "awaiting_approval", "the row is unchanged")
		}
	} Catch exception {
		Do $$$AssertTrue(0, "the test threw: "_exception.DisplayString())
	}
	// Also when Use failed: it may have changed the item before it failed, and Restore does nothing when nothing was saved.
	Do $$$AssertStatusOK($ClassMethod(double, "Restore"), "the real IncidentManager is put back")
	Kill ^OcuTalonTest("IncidentManagerDouble")
}

/// AC7: what the session can't see is 404 not_found before anything is submitted, with onlineDemo off and on.
Method TestOtherSessionsIncidentIs404()
{
	If '..Guard() Quit
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set mine = ..Session()
	Set theirs = $ClassMethod(fixture, "Session", "zzdismissother"_..Number)
	Do ..Keep(theirs)
	Set traces = $ListBuild(..TraceOf(mine), ..TraceOf(theirs))
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set watched = "Zz.Dismiss"_..Number_".Watched"
	Do $ClassMethod(fixture, "Check", mine, "ZZNS", watched)
	Set cases = $ListBuild($ListBuild("another session's noticed incident", $ClassMethod(fixture, "Incident", theirs), 0))
	Set cases = cases_$ListBuild($ListBuild("an unnoticed own incident", $ClassMethod(fixture, "Incident", mine, ""), 0))
	Set cases = cases_$ListBuild($ListBuild("an eval incident", $ClassMethod(fixture, "Incident", "eval"), 0))
	Set cases = cases_$ListBuild($ListBuild("an unwatched instance incident", $ClassMethod(fixture, "Incident", "instance", now, "ZZNS", "Zz.Dismiss"_..Number_".Unwatched"), 0))
	Set cases = cases_$ListBuild($ListBuild("a watched instance incident", $ClassMethod(fixture, "Incident", "instance", now, "ZZNS", watched), 1))
	Set cases = cases_$ListBuild($ListBuild("an unknown ref", "zzmissing"_..Number, 0))
	For flag = "", 1 {
		Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", flag)
		Set position = 0
		While $ListNext(cases, position, case) {
			Set label = $List(case, 1)_" (onlineDemo "_$Select(flag = "": "off", 1: "on")_")"
			Set ref = $List(case, 2)
			If $List(case, 3) && (flag '= 1) Continue
			Set before = ..StateOf(ref)
			Set eventsBefore = ..IncidentEvents(mine) + ..IncidentEvents(theirs)
			Set body = ..Call(mine, ref, .response)
			Do $$$AssertEquals(response.Status, "404 Not Found", label_": 404")
			Do $$$AssertEquals(body, ..ErrorBody("not_found", ##class(OcuTalon.Web.Api).#MESSAGENOTFOUND), label_": the not_found body")
			Do $$$AssertEquals(..Commands($List(traces, 1))_"|"_..Commands($List(traces, 2)), "0|0", label_": no command reached IncidentManager")
			Do $$$AssertEquals(..StateOf(ref), before, label_": the row is unchanged")
			Do $$$AssertEquals(..IncidentEvents(mine) + ..IncidentEvents(theirs), eventsBefore, label_": no incident event is published")
		}
	}
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", "")
}

/// A sessionRef in the body is ignored: it can't reach another session's incident, and it doesn't change the command's session.
Method TestBodyIsIgnored()
{
	If '..Guard() Quit
	Set mine = ..Session()
	Set theirs = ##class(OcuTalon.Test.Data.Fixture).Session("zzdismissbody"_..Number)
	Do ..Keep(theirs)
	Set others = ##class(OcuTalon.Test.Data.Fixture).Incident(theirs)
	Set body = ..Call(mine, others, .response, {"sessionRef": (theirs)}.%ToJSON())
	Do $$$AssertEquals(response.Status, "404 Not Found", "another session's incident is 404, whoever the body names")
	Do $$$AssertEquals(..Commands(..TraceOf(mine))_"|"_..Commands(..TraceOf(theirs)), "0|0", "and no command reached IncidentManager")
	Do $$$AssertEquals(..StateOf(others), "open", "the row is unchanged")
	Set own = ##class(OcuTalon.Test.Data.Fixture).Incident(mine)
	Set body = ..Call(mine, own, .response, {"sessionRef": (theirs)}.%ToJSON())
	Do $$$AssertEquals(response.Status, "200 OK", "an own incident is dismissed: "_body)
	Do $$$AssertEquals(..CommandOf(..TraceOf(mine), 1), "dismiss|"_own_"|"_mine_"|web_user", "for the CSP session's Ref, not the body's")
}

/// --- helpers ---
/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
}

/// The fixture session of the IRIS user who runs the tests (the user that Ownership.SessionRef resolves the CSP session for).
Method Session() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Do ..Keep(ref)
	Quit ref
}

/// Keeps the session's TraceRef for the clean-up of the messages.
Method Keep(ref As %String) [ Private ]
{
	Do ..Traces.%Push(..TraceOf(ref))
}

/// The TraceRef of the session.
Method TraceOf(ref As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef
}

/// Calls the route for the incident as the CSP session of the session (a body is the request's content), through Written; response
/// is the %response, and the result is what the route wrote. The call is made with the %request and %response set here.
Method Call(session As %String, ref As %String, Output response, body As %String = "") As %String [ Private ]
{
	New %request, %response, %session
	Set application = "/ocutalon/api/"
	Set %request = $Select(body = "": ##class(OcuTalon.Test.Web.StubRequest).Make(application), 1: ##class(OcuTalon.Test.Web.StubRequest).MakeBody(application, body))
	Set %response = ##class(%CSP.Response).%New()
	Set %response.ContentType = ""
	Set %session = ##class(%CSP.Session).%New("ZzDismissApi"_..Number, 0)
	Set %session.Data("OcuTalon.SessionRef") = session
	Set written = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Api", "DismissIncident", ref)
	Do $$$AssertStatusOK(sc, "DismissIncident returns OK")
	Set response = %response
	Quit written
}

/// The error body of the route for the code and the message.
Method ErrorBody(code As %String, message As %String) As %String [ Private ]
{
	Quit {"error": {"code": (code), "message": (message)}}.%ToJSON()
}

/// The state of the incident's row, "" when there is none.
Method StateOf(ref As %String) As %String [ Private ]
{
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	Quit $Select($IsObject(row): row.State, 1: "")
}

/// The IncidentCommands that CommandsIn sent to IncidentManager in the trace, oldest first, as the array of {verb, incident, session, origin} of
/// their bodies.
Method CommandList(trace As %String) As %DynamicArray [ Private ]
{
	Set list = []
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "CommandsIn", "IncidentManager")
	For i = 0:1:headers.%Size() - 1 {
		Set body = ##class(OcuTalon.Msg.IncidentCommand).%OpenId(headers.%Get(i).bodyId)
		If $IsObject(body) Do list.%Push({"verb": (body.Verb), "incident": (body.IncidentRef), "session": (body.SessionRef), "origin": (body.Origin)})
	}
	Quit list
}

/// The number of commands that IncidentManager received in the trace.
Method Commands(trace As %String) As %Integer [ Private ]
{
	Quit ..CommandList(trace).%Size()
}

/// The verb, incident, session and origin of the trace's command n.
Method CommandOf(trace As %String, n As %Integer) As %String [ Private ]
{
	Set command = ..CommandList(trace).%Get(n - 1)
	If '$IsObject(command) Quit ""
	Quit command.verb_"|"_command.incident_"|"_command.session_"|"_command.origin
}

/// The incident events of the session's stream, of state closed, for the incident.
Method ClosedEvents(session As %String, incident As %String) As %DynamicArray [ Private ]
{
	Set found = []
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "incident")
	For i = 0:1:events.%Size() - 1 {
		Set event = events.%Get(i)
		If (event.payload.ref = incident) && (event.payload.state = "closed") Do found.%Push(event)
	}
	Quit found
}

/// The number of incident events of the session's stream.
Method IncidentEvents(session As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Core.Observe).Events(session, "incident").%Size()
}

/// The number of requests from CommandsIn to IncidentManager whose SuperSession is the trace.
Method CommandsInHeaders(trace As %String) As %Integer [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "CommandsIn", "IncidentManager").%Size()
}

/// The number of Turn rows of the session.
Method TurnCount(session As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Turn WHERE SessionRef = ?", session)
	Do result.%Next()
	Quit +result.%GetData(1)
}

}
