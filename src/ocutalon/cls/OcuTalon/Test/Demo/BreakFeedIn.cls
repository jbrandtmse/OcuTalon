/// Tests of Demo.BreakFeedIn (Story 4.3; matrix rows 1 and 4 to 9 and 11; AD-12). The press runs on a shadow instance of
/// Test.Demo.BreakFeedInProbe, which keeps the real lock, Guide.Compute, run rows and publishes and answers the two sends (the close
/// and the trigger) from ^OcuTalonTest, so that no production is needed (a slot can run this class). Every session is a fixture session
/// (zzbreak<n>), removed after its test (Fixture.Clean). The real batches, and the item swap, are Test.Demo.BreakFeedProduction's.
///   - TestSent: a press with nothing in its way sends once; the run is written before the send, is sending at the send and is sent
///     after it; the events are sending and sent with one startedAt; the send carries the session, the channel and the TraceRef;
///   - TestNotWatching, TestBusy: an inactive press answers its reason and writes and sends nothing;
///   - TestReplayClosesFirst, TestCloseRefused, TestCloseFails: the session's own resolved Orders incidents are closed, oldest
///     first, before any run is written; a refusal or an error leaves no run and no send;
///   - TestTriggerFails: the run stays sending, with one event, and the error status is the answer;
///   - TestHeldLock: a press that can't take the session's lock in LOCKWAIT seconds answers incident_in_progress;
///   - TestBadInput: a press that is none, has no session or has a session with no row is an error status and writes nothing;
///   - TestNotATurn: no Turn and no Decision, and the press's methods name no Allowance, WebChatIn or Conversation.
Class OcuTalon.Test.Demo.BreakFeedIn Extends %UnitTest.TestCase
{

Parameter NS = "OCUORDERS";

Parameter PROD = "OcuTalon.Demo.Orders.Production";

/// The run's number.
Property Number As %Integer;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("BreakFeedIn", "n"))
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("BreakFeedInProbe")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterOneTest() As %Status
{
	Kill ^OcuTalonTest("BreakFeedInProbe")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	Kill ^OcuTalonTest("BreakFeedIn", "hold"), ^OcuTalonTest("BreakFeedIn", "try")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

/// Row 1 (the press): one run, written before the send, sending at the send and sent after it; the events are sending and sent with
/// one startedAt; the send carries the session, the channel and the TraceRef; no close is sent.
Method TestSent()
{
	Set ref = ..Watching()
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef
	Set output = ..Press(ref, .sc)
	Do $$$AssertStatusOK(sc, "the press is accepted")
	Set answer = {}.%FromJSON(output)
	Do $$$AssertEquals(answer.outcome, "sent", "the outcome is sent")
	Do $$$AssertEquals(answer.state, "sent", "the state is sent")
	Do $$$AssertEquals(..Calls(), "trigger", "the only send is the trigger: there is no incident to close")
	Do $$$AssertEquals(^OcuTalonTest("BreakFeedInProbe", "calls", 1, "runs"), "1:sending", "the run is written, as sending, before the send")
	Do $$$AssertEquals(^OcuTalonTest("BreakFeedInProbe", "calls", 1, "session"), ref, "the send carries the session")
	Do $$$AssertEquals(^OcuTalonTest("BreakFeedInProbe", "calls", 1, "channel"), "web", "the send carries the channel web")
	Do $$$AssertEquals(^OcuTalonTest("BreakFeedInProbe", "calls", 1, "superSession"), trace, "the send's SuperSession is the session's TraceRef")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs(ref), "1:sent", "one run, now sent")
	Set run = ##class(OcuTalon.Data.Ownership).LatestBreakFeedRun(ref, .sc)
	Do $$$AssertEquals(answer.startedAt, run.StartedAt, "the answer's startedAt is the run's")
	Do $$$AssertTrue(run.StartedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "StartedAt is a UTC time to the second")
	Set events = ..Events(ref)
	Do $$$AssertEquals(events.%Size(), 2, "two events besides the guide's")
	Do $$$AssertEquals(events.%Get(0).state, "sending", "the first is sending")
	Do $$$AssertEquals(events.%Get(1).state, "sent", "the second is sent")
	Do $$$AssertEquals(events.%Get(0).startedAt, run.StartedAt, "sending carries the run's startedAt")
	Do $$$AssertEquals(events.%Get(1).startedAt, run.StartedAt, "sent carries the same startedAt")
	Do ..AssertUnlocked(ref)
}

/// Row 4: a session that watches nothing is refused with not_watching: no run, no send, no event.
Method TestNotWatching()
{
	Set ref = ..NewSession()
	Set output = ..Press(ref, .sc)
	Do $$$AssertStatusOK(sc, "the press is accepted")
	Do $$$AssertEquals(output, {"outcome": "inactive", "reason": "not_watching"}.%ToJSON(), "the answer is inactive, not_watching")
	Do ..AssertNothing(ref)
	Do ..AssertUnlocked(ref)
}

/// Row 5: an Orders incident of the session that is open (each variant), awaiting approval or fixing, or a run under 180 s with no
/// notice, refuses the press with incident_in_progress: nothing is sent or written.
Method TestBusy()
{
	Set cases = $ListBuild("open", "open rejected", "open fallback", "open no_fix", "awaiting_approval", "fixing")
	Set position = 0
	While $ListNext(cases, position, case) {
		Set ref = ..Watching()
		Set fields = {"State": ($Piece(case, " ", 1))}
		If $Length(case, " ") = 2 Set fields.OpenVariant = $Piece(case, " ", 2)
		Do ##class(OcuTalon.Test.Data.Fixture).Incident(ref, , ..#NS, ..#PROD, fields)
		Set output = ..Press(ref, .sc)
		Do $$$AssertEquals(output, {"outcome": "inactive", "reason": "incident_in_progress"}.%ToJSON(), "an incident that is "_case_": inactive, incident_in_progress")
		Do ..AssertNothing(ref)
	}
	Set ref = ..Watching()
	Do ##class(OcuTalon.Test.Data.Fixture).BreakFeedRun(ref, "sent")
	Set output = ..Press(ref, .sc)
	Do $$$AssertEquals(output, {"outcome": "inactive", "reason": "incident_in_progress"}.%ToJSON(), "a run under 180 s with no notice: inactive, incident_in_progress")
	Do $$$AssertEquals(..Calls(), "", "nothing is sent for the run")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs(ref), "1:sent", "no second run is written")
}

/// Row 7: the session's own noticed resolved Orders incidents, oldest first, are closed (closeForReplay, origin web_user, the session)
/// before any run is written; then the run is written and the batch is triggered. A resolved incident of owner instance, of another
/// session, of another production, an unnoticed one and an incident in another state get no command.
Method TestReplayClosesFirst()
{
	Set ref = ..Watching()
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef
	Set other = ..Watching()
	Set newer = ##class(OcuTalon.Test.Data.Fixture).Incident(ref, "2030-01-02T10:00:00Z", ..#NS, ..#PROD, {"State": "resolved"})
	Set older = ##class(OcuTalon.Test.Data.Fixture).Incident(ref, "2030-01-01T10:00:00Z", ..#NS, ..#PROD, {"State": "resolved"})
	Do ##class(OcuTalon.Test.Data.Fixture).Incident("instance", "2030-01-01T11:00:00Z", ..#NS, ..#PROD, {"State": "resolved"})
	Do ##class(OcuTalon.Test.Data.Fixture).Incident(other, "2030-01-01T12:00:00Z", ..#NS, ..#PROD, {"State": "resolved"})
	Do ##class(OcuTalon.Test.Data.Fixture).Incident(ref, "2030-01-01T13:00:00Z", ..#NS, "Zz.Other", {"State": "resolved"})
	Do ##class(OcuTalon.Test.Data.Fixture).Incident(ref, "", ..#NS, ..#PROD, {"State": "resolved"})
	Do ##class(OcuTalon.Test.Data.Fixture).Incident(ref, "2030-01-01T14:00:00Z", ..#NS, ..#PROD, {"State": "closed", "OpenVariant": "fix"})
	Set output = ..Press(ref, .sc)
	Do $$$AssertStatusOK(sc, "the press is accepted")
	Do $$$AssertEquals({}.%FromJSON(output).outcome, "sent", "the press is sent")
	Do $$$AssertEquals(..Calls(), "close,close,trigger", "two closes, oldest first, and then the trigger")
	Do $$$AssertEquals(^OcuTalonTest("BreakFeedInProbe", "calls", 1, "ref"), older, "the older incident is closed first")
	Do $$$AssertEquals(^OcuTalonTest("BreakFeedInProbe", "calls", 2, "ref"), newer, "the newer incident is closed second")
	For n = 1, 2 {
		Do $$$AssertEquals(^OcuTalonTest("BreakFeedInProbe", "calls", n, "verb"), "closeForReplay", "close "_n_" is a closeForReplay")
		Do $$$AssertEquals(^OcuTalonTest("BreakFeedInProbe", "calls", n, "session"), ref, "close "_n_" carries the session")
		Do $$$AssertEquals(^OcuTalonTest("BreakFeedInProbe", "calls", n, "origin"), "web_user", "close "_n_" has the origin web_user")
		Do $$$AssertEquals(^OcuTalonTest("BreakFeedInProbe", "calls", n, "runs"), "0:", "close "_n_" comes before any run")
		Do $$$AssertEquals(^OcuTalonTest("BreakFeedInProbe", "calls", n, "superSession"), trace, "close "_n_" carries the session's TraceRef as its SuperSession")
	}
	Do $$$AssertEquals(^OcuTalonTest("BreakFeedInProbe", "calls", 3, "runs"), "1:sending", "the run is written after the closes, as sending, before the trigger")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs(ref), "1:sent", "one run, sent")
}

/// Row 8 (the refusal): a close answered Ok 0 is inactive, incident_in_progress; no run, no trigger.
Method TestCloseRefused()
{
	Set ref = ..Watching()
	Do ##class(OcuTalon.Test.Data.Fixture).Incident(ref, , ..#NS, ..#PROD, {"State": "resolved"})
	Set ^OcuTalonTest("BreakFeedInProbe", "answer", "close") = "refuse"
	Set output = ..Press(ref, .sc)
	Do $$$AssertStatusOK(sc, "the press is accepted")
	Do $$$AssertEquals(output, {"outcome": "inactive", "reason": "incident_in_progress"}.%ToJSON(), "the answer is inactive, incident_in_progress")
	Do $$$AssertEquals(..Calls(), "close", "one close and no trigger")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs(ref), "0:", "no run is written")
	Do $$$AssertEquals(..Events(ref).%Size(), 0, "no event is published")
	Kill ^OcuTalonTest("BreakFeedInProbe")
	Set ref = ..Watching()
	Do ##class(OcuTalon.Test.Data.Fixture).Incident(ref, , ..#NS, ..#PROD, {"State": "resolved"})
	Set ^OcuTalonTest("BreakFeedInProbe", "answer", "close") = "none"
	Set output = ..Press(ref, .sc)
	Do $$$AssertEquals(output, {"outcome": "inactive", "reason": "incident_in_progress"}.%ToJSON(), "a close with no answer is a refusal too")
	Do $$$AssertEquals(..Calls(), "close", "and nothing else is sent")
}

/// Row 8 (the failure): a close that errors or times out is an error status, with no run and no trigger.
Method TestCloseFails()
{
	Set ref = ..Watching()
	Do ##class(OcuTalon.Test.Data.Fixture).Incident(ref, , ..#NS, ..#PROD, {"State": "resolved"})
	Set ^OcuTalonTest("BreakFeedInProbe", "answer", "close") = "error"
	Set output = ..Press(ref, .sc)
	Do $$$AssertStatusNotOK(sc, "the press is an error status")
	Do $$$AssertEquals(output, "", "there is no answer")
	Do $$$AssertEquals(..Calls(), "close", "one close and no trigger")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs(ref), "0:", "no run is written")
	Do $$$AssertEquals(..Events(ref).%Size(), 0, "no event is published")
	Do ..AssertUnlocked(ref)
}

/// Row 9: a trigger that fails is an error status; the run stays sending, with its one sending event.
Method TestTriggerFails()
{
	Set ref = ..Watching()
	Set ^OcuTalonTest("BreakFeedInProbe", "answer", "trigger") = "error"
	Set output = ..Press(ref, .sc)
	Do $$$AssertStatusNotOK(sc, "the press is an error status")
	Do $$$AssertEquals(output, "", "there is no answer")
	Do $$$AssertEquals(..Calls(), "trigger", "the trigger was asked once")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs(ref), "1:sending", "the run stays sending")
	Set events = ..Events(ref)
	Do $$$AssertEquals(events.%Size(), 1, "one event")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).state, "sending", "it is sending")
	Do $$$AssertEquals(##class(OcuTalon.Demo.Guide).Compute(ref).BreakFeed.Stage, "sending", "the guide reports the stage sending")
	Do ..AssertUnlocked(ref)
}

/// Row 6 (the lock): a press that can't take the session's lock within LOCKWAIT seconds answers incident_in_progress and does nothing.
/// The probe's LOCKWAIT is 1, so a press that waits for the real 10 seconds is too slow.
Method TestHeldLock()
{
	Set ref = ..Watching()
	Kill ^OcuTalonTest("BreakFeedIn", "hold", ref)
	Job ##class(OcuTalon.Test.Demo.BreakFeedIn).Holder(ref)
	Do ..WaitFor($Name(^OcuTalonTest("BreakFeedIn", "hold", ref, "ready")), 30)
	Do $$$AssertEquals($Get(^OcuTalonTest("BreakFeedIn", "hold", ref, "ready")), 1, "the holder has the session's lock")
	Set start = $ZHorolog
	Set output = ..Press(ref, .sc)
	Set elapsed = $ZHorolog - start
	Set ^OcuTalonTest("BreakFeedIn", "hold", ref, "release") = 1
	Do ..WaitFor($Name(^OcuTalonTest("BreakFeedIn", "hold", ref, "done")), 30)
	Do $$$AssertStatusOK(sc, "the press is accepted")
	Do $$$AssertEquals(output, {"outcome": "inactive", "reason": "incident_in_progress"}.%ToJSON(), "the answer is inactive, incident_in_progress")
	Do $$$AssertTrue(elapsed < 8, "the press waited LOCKWAIT of the probe (1 s), not the product's 10 s: "_elapsed)
	Do ..AssertNothing(ref)
	Do $$$AssertEquals(##class(OcuTalon.Demo.BreakFeedIn).#LOCKWAIT, 10, "the product waits 10 s for the lock")
}

/// The job body of TestHeldLock: takes the session's lock and holds it until released.
ClassMethod Holder(ref As %String)
{
	Lock +^OcuTalon.Demo.BreakFeed(ref):5
	If '$Test {
		Set ^OcuTalonTest("BreakFeedIn", "hold", ref, "ready") = 0
		Quit
	}
	Set ^OcuTalonTest("BreakFeedIn", "hold", ref, "ready") = 1
	Set deadline = $ZHorolog + 60
	While '$Get(^OcuTalonTest("BreakFeedIn", "hold", ref, "release")) && ($ZHorolog < deadline) {
		Hang 0.05
	}
	Lock -^OcuTalon.Demo.BreakFeed(ref)
	Set ^OcuTalonTest("BreakFeedIn", "hold", ref, "done") = 1
}

/// A press that is not a Demo.Press, has an empty SessionRef or a SessionRef with no row is an error status, and writes and sends nothing.
Method TestBadInput()
{
	Set ref = ..Watching()
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Demo.BreakFeedInProbe", .sc)
	Set other = ##class(OcuTalon.Demo.Msg.SendOrders).%New()
	Set other.SessionRef = ref
	Do $$$AssertStatusNotOK(probe.OnProcessInput(other, .output), "a SendOrders is no press")
	Do $$$AssertStatusNotOK(probe.OnProcessInput("", .output), "no input is no press")
	Set press = ##class(OcuTalon.Demo.Press).%New()
	Do $$$AssertStatusNotOK(probe.OnProcessInput(press, .output), "a press with no session is refused")
	Set press.SessionRef = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do $$$AssertStatusNotOK(probe.OnProcessInput(press, .output), "a press of a session with no row is refused")
	Do ..AssertNothing(ref)
	Do $$$AssertEquals($Order(^OcuTalonTest("BreakFeedInProbe", "calls", "")), "", "nothing is sent")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.BreakFeedRun WHERE SessionRef = ?", press.SessionRef)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 0, "no run is written for the session with no row")
}

/// Row 11: a press is not a turn. The session has no Turn and no Decision after it, and the methods of BreakFeedIn, PartnerTrigger and
/// Web.Api.BreakFeed name no Core.Allowance, WebChatIn or Conversation.
Method TestNotATurn()
{
	Set ref = ..Watching()
	Do ..Press(ref, .sc)
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Turn WHERE SessionRef = ?", ref)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 0, "the session has no Turn")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision WHERE OwnerRef = ?", ref)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 0, "the session has no Decision")
	For class = "OcuTalon.Demo.BreakFeedIn", "OcuTalon.Demo.PartnerTrigger", "OcuTalon.Web.Api" {
		Set text = ..Code(class, $Select(class = "OcuTalon.Web.Api": "BreakFeed,Press", 1: ""))
		Do $$$AssertTrue($Length(text) > 100, class_": its code was read")
		For name = "Allowance", "WebChatIn", "Conversation", "Core.Turn", "Msg.Item" {
			Do $$$AssertTrue(text '[ name, class_" does not name "_name)
		}
	}
}

/// The code of the methods of the class (the names in the comma-separated list, or every method of the class when it is empty),
/// without the comments of the class and of the methods.
ClassMethod Code(class As %String, names As %String) As %String [ Private ]
{
	Set definition = ##class(%Dictionary.ClassDefinition).%OpenId(class)
	Set text = ""
	For i = 1:1:definition.Methods.Count() {
		Set method = definition.Methods.GetAt(i)
		If (names '= "") && '$ListFind($ListFromString(names), method.Name) Continue
		Set text = text_method.Implementation.Read(1000000)
	}
	Quit text
}

/// A session of a fixture user whose Orders check is watched.
Method Watching() As %String [ Private ]
{
	Set ref = ..NewSession()
	Do ##class(OcuTalon.Test.Data.Fixture).Check(ref, ..#NS, ..#PROD)
	Quit ref
}

/// A fixture session.
Method NewSession() As %String [ Private ]
{
	Quit ##class(OcuTalon.Test.Data.Fixture).Session("zzbreak"_..Number)
}

/// Presses for the session on a shadow instance of the probe; the answer's JSON text, and the status in sc.
Method Press(ref As %String, Output sc As %Status) As %String [ Private ]
{
	Set probe = ##class(Ens.Host).GetShadowInstance("class||OcuTalon.Test.Demo.BreakFeedInProbe", .sc)
	If '$IsObject(probe) Quit ""
	Set input = ##class(OcuTalon.Demo.Press).%New()
	Set input.SessionRef = ref
	Set sc = probe.OnProcessInput(input, .output)
	Quit output
}

/// The seam calls of the press in order, as "close,close,trigger".
ClassMethod Calls() As %String [ Private ]
{
	Set text = ""
	Set n = ""
	For {
		Set n = $Order(^OcuTalonTest("BreakFeedInProbe", "calls", n), 1, call)
		Quit:n=""
		Set text = text_$Select(text = "": "", 1: ",")_call
	}
	Quit text
}

/// The breakfeed.progress events of the stream, in order, as an array of their payloads (the guide's events are left out).
ClassMethod Events(ref As %String) As %DynamicArray [ Private ]
{
	Set events = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Payload FROM OcuTalon_Live.Event WHERE Stream = ? AND Type = 'breakfeed.progress' ORDER BY Seq", ref)
	While result.%Next() {
		Do events.%Push({}.%FromJSON(result.%Get("Payload")))
	}
	Quit events
}

/// No run, no call and no breakfeed.progress event for the session.
Method AssertNothing(ref As %String) [ Private ]
{
	Do $$$AssertEquals(..Calls(), "", "nothing is sent")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs(ref), "0:", "no run is written")
	Do $$$AssertEquals(..Events(ref).%Size(), 0, "no event is published")
}

/// The session's lock is free once the press has returned: a job of its own takes it without waiting and says so.
Method AssertUnlocked(ref As %String) [ Private ]
{
	Kill ^OcuTalonTest("BreakFeedIn", "try", ref)
	Job ##class(OcuTalon.Test.Demo.BreakFeedIn).TryLock(ref)
	Do ..WaitFor($Name(^OcuTalonTest("BreakFeedIn", "try", ref)), 30)
	Do $$$AssertEquals($Get(^OcuTalonTest("BreakFeedIn", "try", ref)), 1, "the press has released the session's lock")
}

/// The job body of AssertUnlocked: takes the session's lock for up to 5 s, records whether it got it, and lets it go.
ClassMethod TryLock(ref As %String)
{
	Lock +^OcuTalon.Demo.BreakFeed(ref):5
	Set got = $Test
	If got Lock -^OcuTalon.Demo.BreakFeed(ref)
	Set ^OcuTalonTest("BreakFeedIn", "try", ref) = got
}

/// Waits up to seconds for the global node named by ref to hold a value.
ClassMethod WaitFor(ref As %String, seconds As %Integer) [ Private ]
{
	Set deadline = $ZHorolog + seconds
	While ('$Data(@ref)) && ($ZHorolog < deadline) {
		Hang 0.05
	}
}

}
