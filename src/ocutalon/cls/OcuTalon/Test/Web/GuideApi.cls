/// Tests of POST /v1/guide/markers and of the guide in /v1/state (Story 4.2; matrix rows 17 and 18; AD-1, AD-12), called with stand-in
/// request and response objects like Test.Web.Api (Written, StubRequest.MakeBody) and the real Web.Api:
///   - TestTraceOpened and TestRunAgain: the answer is 200 with the guide view, a guide.state event follows, and trace_opened sets step 5
///     while run_again starts the next epoch and clears step 5;
///   - TestBadBody: any other body is 400 bad_marker and nothing is written;
///   - TestDemoOff: with demo mode off the answer is 404 not_found, before the body is read, and nothing is written;
///   - TestOnlyTheMarkerChanges: a marker changes only the session's GuideState, and Run again leaves its turns, checks, reminders,
///     incidents and Break the feed runs as they were (counts and refs); a sessionRef in the body is ignored;
///   - TestStateCarriesTheGuide: /state's guide is Compute's view with demo mode on, and absent with it off.
/// The fixture session is a row of the IRIS user (zzguideapi rows are removed by Fixture.Clean); demo.mode is saved before the tests and
/// put back after them.
Class OcuTalon.Test.Web.GuideApi Extends %UnitTest.TestCase
{

Parameter NS = "OCUORDERS";

Parameter PROD = "OcuTalon.Demo.Orders.Production";

Property SavedModeFound As %Boolean;

Property SavedModeValue As %String(MAXLEN = 1000);

Property SavedModeUpdatedAt As %String(MAXLEN = 20);

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do ##class(OcuTalon.Test.Demo.Step).Saved(.found, .value, .updatedAt)
	Set ..SavedModeFound = found, ..SavedModeValue = value, ..SavedModeUpdatedAt = updatedAt
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Do ##class(OcuTalon.Test.Demo.Step).Put(1, ##class(OcuTalon.Data.Time).NowUtc())
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Do ##class(OcuTalon.Test.Demo.Step).PutBack(..SavedModeFound, ..SavedModeValue, ..SavedModeUpdatedAt)
	Quit $SYSTEM.Status.OK()
}

/// trace_opened answers 200 with the guide view, sets step 5, and a guide.state follows.
Method TestTraceOpened()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set csp = ..Csp(ref)
	Set body = ..Post(csp, "{""marker"":""trace_opened""}", .response)
	Do $$$AssertEquals(..Ok(response), 1, "200: "_response.Status)
	Do $$$AssertEquals(response.ContentType, "application/json", "JSON")
	Set view = ##class(%DynamicObject).%FromJSON(body)
	Do $$$AssertEquals(view.runEpoch_"|"_view.steps.%Get(4).done_"|"_view.step, "1|1|1", "epoch 1, step 5 done, the current step still 1")
	Do ##class(OcuTalon.Demo.Guide).Compute(ref).%JSONExportToString(.computed)
	Do $$$AssertEquals(##class(%DynamicObject).%FromJSON(body).%ToJSON(), computed, "the answer is Compute's view")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(ref, "guide.state")
	Do $$$AssertEquals(events.%Size(), 1, "one guide.state follows")
	Do $$$AssertEquals(events.%Get(0).payload.%ToJSON(), computed, "with that view")
	Set row = ##class(OcuTalon.Data.GuideState).ForSession(ref)
	Do $$$AssertEquals(row.RunEpoch_"|"_row.TraceOpened_"|"_row.RunStartedAt, "1|1|", "the row has epoch 1 and the flag")
	Do ..Post(csp, "{""marker"":""trace_opened""}", .response)
	Do $$$AssertEquals(..Ok(response), 1, "a repeat answers 200 too")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(ref, "guide.state").%Size(), 1, "and publishes nothing, the view being the same")
}

/// run_again adds 1 to the epoch, clears step 5 and sets the start of the epoch; steps 3 to 5 reset.
Method TestRunAgain()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ref = $ClassMethod(fixture, "Session", $Username)
	Set csp = ..Csp(ref)
	Do $ClassMethod(fixture, "Check", ref, ..#NS, ..#PROD)
	Set incident = $ClassMethod(fixture, "Incident", ref, "2020-01-01T10:00:00Z", ..#NS, ..#PROD, {"State": "resolved"})
	Do $ClassMethod(fixture, "Approval", ref, incident, "approved")
	Do ..Post(csp, "{""marker"":""trace_opened""}", .response)
	Set view = ##class(%DynamicObject).%FromJSON(..Post(csp, "{""marker"":""run_again""}", .response))
	Do $$$AssertEquals(..Ok(response), 1, "200: "_response.Status)
	Do $$$AssertEquals(view.runEpoch, 2, "the epoch rose to 2")
	Set done = ""
	For i = 0:1:4 {
		Set done = done_view.steps.%Get(i).done
	}
	Do $$$AssertEquals(done, "10000", "steps 3 to 5 reset; the watch still counts")
	Do $$$AssertEquals(view.finished, 0, "not finished")
	Set row = ##class(OcuTalon.Data.GuideState).ForSession(ref)
	Do $$$AssertEquals(row.RunEpoch_"|"_row.TraceOpened, "2|0", "the row has epoch 2 and no trace flag")
	Do $$$AssertTrue(row.RunStartedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "RunStartedAt is a UTC time: "_row.RunStartedAt)
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(ref, "guide.state").%Size(), 2, "a guide.state followed each marker")
	Do ..Post(csp, "{""marker"":""run_again""}", .response)
	Do $$$AssertEquals(##class(OcuTalon.Data.GuideState).ForSession(ref).RunEpoch, 3, "a second run again makes epoch 3")

	Set fresh = $ClassMethod(fixture, "Session", $Username)
	Set view = ##class(%DynamicObject).%FromJSON(..Post(..Csp(fresh), "{""marker"":""run_again""}", .response))
	Do $$$AssertEquals(view.runEpoch, 2, "a session with no row goes to epoch 2")
}

/// Any other body is 400 bad_marker and nothing is written.
Method TestBadBody()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set csp = ..Csp(ref)
	Set bodies = $ListBuild("", "{}", "[]", """run_again""", "not json", "{""marker"":""other""}", "{""marker"":1}", "{""marker"":null}", "{""Marker"":""run_again""}", "{""marker"":[""run_again""]}", "{""marker"":""trace_opened ""}")
	Set position = 0
	While $ListNext(bodies, position, json) {
		Set body = ..Post(csp, json, .response)
		Do $$$AssertEquals(response.Status, "400 Bad Request", "400 for '"_json_"'")
		Set error = ##class(%DynamicObject).%FromJSON(body).error
		Do $$$AssertEquals(error.code_"|"_error.message, "bad_marker|"_##class(OcuTalon.Web.Api).#MESSAGEBADMARKER, "bad_marker and its text for '"_json_"'")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.GuideState).ForSession(ref), "", "no GuideState row was written")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(ref, "guide.state").%Size(), 0, "and no event")
	Do $$$AssertEquals(##class(OcuTalon.Web.Api).#MESSAGEBADMARKER, "A guide marker must be trace_opened or run_again.", "the text")
}

/// With demo mode off the endpoint answers 404 not_found before it reads the body, and writes nothing.
Method TestDemoOff()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set csp = ..Csp(ref)
	Do ##class(OcuTalon.Test.Demo.Step).Put(0, ##class(OcuTalon.Data.Time).NowUtc())
	For json = "{""marker"":""trace_opened""}", "{""marker"":""run_again""}", "not json" {
		Set body = ..Post(csp, json, .response)
		Do $$$AssertEquals(response.Status, "404 Not Found", "404 for '"_json_"'")
		Do $$$AssertEquals(##class(%DynamicObject).%FromJSON(body).error.code, "not_found", "not_found")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.GuideState).ForSession(ref), "", "nothing was written")
	Do ##class(OcuTalon.Test.Demo.Step).Remove()
	Do ..Post(csp, "{""marker"":""trace_opened""}", .response)
	Do $$$AssertEquals(response.Status, "404 Not Found", "404 with no demo.mode row")
}

/// A marker changes only the session's GuideState; Run again leaves the session's turns, checks, reminders, incidents and
/// Break the feed runs as they were, and a sessionRef in the body is ignored.
Method TestOnlyTheMarkerChanges()
{
	Set fixture = "OcuTalon.Test.Data.Fixture"
	Set ref = $ClassMethod(fixture, "Session", $Username)
	Set other = $ClassMethod(fixture, "Session", "zzguideapiother")
	Set csp = ..Csp(ref)
	Do $ClassMethod(fixture, "Turn", ref)
	Do $ClassMethod(fixture, "Check", ref, ..#NS, ..#PROD)
	Do $ClassMethod(fixture, "Reminder", ref)
	Set incident = $ClassMethod(fixture, "Incident", ref, , ..#NS, ..#PROD, {"State": "resolved"})
	Do $ClassMethod(fixture, "Approval", ref, incident, "approved")
	Do $ClassMethod(fixture, "BreakFeedRun", ref)
	Do $ClassMethod(fixture, "GuideState", other, 5, "", 1)
	Set before = ..Fingerprint(ref)
	Set otherBefore = ..Fingerprint(other)
	Do ..Post(csp, "{""marker"":""trace_opened"",""sessionRef"":"""_other_"""}", .response)
	Do $$$AssertEquals(..Fingerprint(ref), before, "trace_opened changes none of the session's data rows")
	Do ..Post(csp, "{""marker"":""run_again"",""sessionRef"":"""_other_"""}", .response)
	Do $$$AssertEquals(..Ok(response), 1, "run_again answers 200")
	Do $$$AssertEquals(..Fingerprint(ref), before, "run_again changes none of the session's data rows")
	Do $$$AssertEquals(..Fingerprint(other), otherBefore, "and none of another session's")
	Set row = ##class(OcuTalon.Data.GuideState).ForSession(other)
	Do $$$AssertEquals(row.RunEpoch_"|"_row.TraceOpened, "5|1", "a sessionRef in the body is ignored")
}

/// /state carries the guide as Compute derives it, last, with demo mode on; with it off there is no guide key.
Method TestStateCarriesTheGuide()
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session($Username)
	Set csp = ..Csp(ref)
	Do ..Post(csp, "{""marker"":""trace_opened""}", .response)
	Set session = ##class(OcuTalon.Data.Session).RefIndexOpen(ref)
	Set state = ##class(OcuTalon.Web.Api).StateBody(session)
	Set keys = ""
	Set iterator = state.%GetIterator()
	While iterator.%GetNext(.key) {
		Set last = key
	}
	Do $$$AssertEquals(last, "guide", "guide is the last key")
	Do ##class(OcuTalon.Demo.Guide).Compute(ref).%JSONExportToString(.computed)
	Do $$$AssertEquals(state.guide.%ToJSON(), computed, "it is Compute's view")
	Do $$$AssertEquals(state.guide.steps.%Get(4).done, 1, "with the trace marker")
	Do ##class(OcuTalon.Test.Demo.Step).Put(0, ##class(OcuTalon.Data.Time).NowUtc())
	Set state = ##class(OcuTalon.Web.Api).StateBody(session)
	Do $$$AssertEquals(state.%IsDefined("guide"), 0, "with demo mode off there is no guide key")
}

/// A fingerprint of the session's data rows that the guide reads: the refs of its turns, checks, pending reminders and incidents,
/// the incidents' states, variants and notice times, its approval requests in every state, and the IDs and times of its Break the
/// feed runs, with their count.
Method Fingerprint(ref As %String) As %String [ Private ]
{
	Set text = ""
	For method = "Turns", "Checks", "Reminders", "Incidents", "Approvals" {
		Set rows = $ClassMethod("OcuTalon.Data.Ownership", method, ref, .sc)
		For i = 1:1:rows.Count() {
			Set text = text_method_":"_rows.GetAt(i).%Id()_";"
		}
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, State, StartedAt FROM OcuTalon_Data.BreakFeedRun WHERE SessionRef = ? ORDER BY ID", ref)
	While result.%Next() {
		Set text = text_"run:"_result.%Get("ID")_","_result.%Get("State")_","_result.%Get("StartedAt")_";"
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Ref, State, OpenVariant, NoticedAt FROM OcuTalon_Data.Incident WHERE OwnerRef = ? ORDER BY ID", ref)
	While result.%Next() {
		Set text = text_"incident:"_result.%Get("ID")_","_result.%Get("Ref")_","_result.%Get("State")_","_result.%Get("OpenVariant")_","_result.%Get("NoticedAt")_";"
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Ref, State FROM OcuTalon_Bridge_Data.ApprovalRequest WHERE OwnerRef = ? ORDER BY ID", ref)
	While result.%Next() {
		Set text = text_"request:"_result.%Get("ID")_","_result.%Get("Ref")_","_result.%Get("State")_";"
	}
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Reminder WHERE SessionRef = ?", ref)
	Do result.%Next()
	Quit text_"reminders:"_result.%GetData(1)
}

/// A CSP session that holds the fixture session's Ref.
Method Csp(ref As %String) As %CSP.Session [ Private ]
{
	Set csp = ##class(%CSP.Session).%New("ZzGuideApi", 0)
	Set csp.Data("OcuTalon.SessionRef") = ref
	Quit csp
}

/// Calls GuideMarkers with a stand-in request whose body is json and the given CSP session, and returns the body that it wrote.
Method Post(session As %CSP.Session, json As %String, Output response) As %String [ Private ]
{
	New %request, %response, %session
	Set %request = ##class(OcuTalon.Test.Web.StubRequest).MakeBody("/ocutalon/api/", json)
	Set %response = ##class(%CSP.Response).%New()
	Set %session = session
	Set %response.ContentType = ""
	Set body = ##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Api", "GuideMarkers")
	Set response = %response
	Do $$$AssertStatusOK(sc, "GuideMarkers returns OK")
	Quit body
}

/// 1 when the response is a 200: the status line is empty (the default) or 200 OK.
ClassMethod Ok(response As %CSP.Response) As %Boolean [ Private ]
{
	Quit (response.Status = "") || (response.Status = "200 OK")
}

}
