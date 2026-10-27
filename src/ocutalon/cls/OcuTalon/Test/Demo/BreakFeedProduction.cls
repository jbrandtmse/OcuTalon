/// End-to-end tests of Break the feed in the real productions (Story 4.3; matrix rows 1, 2, 3, 6, 7, 8, 10 and 12). THIS CLASS RUNS IN
/// THROWAWAY STACKS AND IN CI ONLY (Rule 21), guarded as Test.Demo.Production is: it needs the namespace OCUORDERS with the Orders
/// production running, and OcuTalon.Production running. Where either is missing every test fails with that reason, so that a broken
/// stack can never give a green shard.
/// The press is the real one: BreakFeedIn is created in the test's process (Ens.Director.CreateBusinessService) and takes a Demo.Press,
/// as Web.Api sends it, and the real PartnerTrigger makes the real partner send its batch. Only the IncidentManager item is swapped, for
/// Test.Demo.IncidentManagerDouble (Test.Agent.RunnerFixture.UseItemClass), until OnAfterAllTests puts the class back; the real
/// FailurePoller keeps running, so the class holds the Orders WatchMark ahead while it runs (Test.Demo.Production.HoldFailures) and
/// releases it after its batches are removed (ReleaseFailures): none of the class's failures is ever read, so none reaches the double or
/// becomes an incident that a later session would see.
///   - TestPressSendsFiftyRealFailures: rows 1, 2 and 11 (every message of the press is BreakFeedIn to PartnerTrigger; no Turn, no Decision);
///   - TestOtherMeansFailTheSame: row 3;
///   - TestTwoQuickPressesSendOneBatch: row 6;
///   - TestReplayClosesTheResolvedIncident and TestRefusedCloseSendsNothing: rows 7 and 8;
///   - TestFailuresAreErrors: rows 8, 9 and 10 (the failures): a close that the double answers with an error, and a press whose audit
///     write fails (the Action event disabled for the test), are error statuses through the real sends; the first writes no run, the
///     second leaves its run sending and sends no order;
///   - TestPressIsAudited: row 10;
///   - TestTwoSessionsGetTheirOwnBatch: row 12.
/// Each session's messages, in OCUORDERS and in OCUTALON, are removed with Fixture.RemoveMessages in OnAfterAllTests.
Class OcuTalon.Test.Demo.BreakFeedProduction Extends %UnitTest.TestCase
{

Parameter NS = "OCUORDERS";

Parameter PROD = "OcuTalon.Demo.Orders.Production";

/// The audit event of a Break the feed press.
Parameter EVENT = "OcuTalon/Action/Action";

/// How long a wait for the audit entry lasts, in seconds.
Parameter AUDITSECONDS = 30;

/// How long a wait for the processes of the quick presses lasts, in seconds.
Parameter PRESSSECONDS = 60;

/// The run's number.
Property Number As %Integer;

/// The TraceRefs that this run used.
Property Traces As %DynamicArray;

/// The reason why every test fails, or empty.
Property Missing As %String(MAXLEN = 200);

/// What UseItemClass saved of the IncidentManager item, "" when it did not swap.
Property Saved As %DynamicObject;

/// The state of the audit event before the run, "" when it does not exist.
Property EventWas As %String;

/// 1 when OnBeforeAllTests held the Orders failures, so that OnAfterAllTests releases them.
Property Held As %Boolean;

Method OnBeforeAllTests() As %Status
{
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Set ..Number = $Increment(^OcuTalonTest("BreakFeedProduction", "n"))
	Set ..Traces = []
	Set ..Missing = ""
	Set ..Saved = ""
	Set ..EventWas = ""
	Set ..Held = 0
	If '##class(%SYS.Namespace).Exists(..#NS) {
		Set ..Missing = "OCUORDERS does not exist: this class runs in throwaways and CI only (Rule 21)"
	} ElseIf '##class(OcuTalon.Test.Demo.Production).Running() {
		Set ..Missing = "The Orders production does not run in OCUORDERS"
	} ElseIf '..OcuTalonRunning() {
		Set ..Missing = "OcuTalon.Production does not run in OCUTALON"
	}
	If ..Missing '= "" Quit $SYSTEM.Status.OK()
	Set sc = ##class(OcuTalon.Test.Demo.Production).HoldFailures()
	If $SYSTEM.Status.IsError(sc) {
		Set ..Missing = "The Orders failures could not be held: "_$SYSTEM.Status.GetErrorText(sc)
		Quit $SYSTEM.Status.OK()
	}
	Set ..Held = 1
	Set ..EventWas = ##class(OcuTalon.Test.Bridge.AuditLog).EventState(..#EVENT)
	If ..EventWas = 0 Do ##class(OcuTalon.Test.Bridge.AuditLog).SetEvent(..#EVENT, 1)
	Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).UseItemClass("IncidentManager", "OcuTalon.Test.Demo.IncidentManagerDouble", .saved)
	Set ..Saved = saved
	If $SYSTEM.Status.IsError(sc) Set ..Missing = "The IncidentManager item could not take the double: "_$SYSTEM.Status.GetErrorText(sc)
	Quit $SYSTEM.Status.OK()
}

Method OnBeforeOneTest() As %Status
{
	Kill ^OcuTalonTest("IncidentManagerDouble")
	Kill ^OcuTalonTest("BreakFeedProduction", "press")
	Quit $SYSTEM.Status.OK()
}

Method OnAfterAllTests() As %Status
{
	If $IsObject(..Saved) {
		Set sc = ##class(OcuTalon.Test.Agent.RunnerFixture).RestoreItemClass("IncidentManager", ..Saved)
		If $SYSTEM.Status.IsError(sc) Write !, "The IncidentManager item was not restored: ", $SYSTEM.Status.GetErrorText(sc), !
	}
	If ..EventWas = 0 Do ##class(OcuTalon.Test.Bridge.AuditLog).SetEvent(..#EVENT, 0)
	If ..Missing = "" || $IsObject(..Saved) {
		Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Traces, ..#NS)
		Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(..Traces, "OCUTALON")
	}
	If ..Held Do ##class(OcuTalon.Test.Demo.Production).ReleaseFailures()
	Kill ^OcuTalonTest("IncidentManagerDouble")
	Kill ^OcuTalonTest("BreakFeedProduction")
	Do ##class(OcuTalon.Test.Data.Fixture).Clean()
	Quit $SYSTEM.Status.OK()
}

/// Rows 1 and 2: a press of a session that watches Orders is sent, with its run and events; the batch is exactly 50 headers at
/// OrdersFromPartner in status Error, in 50 sessions, none at OrdersToWarehouse, each with the transform's error.
Method TestPressSendsFiftyRealFailures()
{
	If '..Guard() Quit
	Set ref = ..Watching()
	Set trace = ..TraceOf(ref)
	Set output = ..Press(ref, .sc)
	Do $$$AssertStatusOK(sc, "the press is accepted")
	Set answer = {}.%FromJSON(output)
	Do $$$AssertEquals(answer.outcome, "sent", "the press is sent")
	Set run = ##class(OcuTalon.Data.Ownership).LatestBreakFeedRun(ref, .scRun)
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs(ref), "1:sent", "one run, sent")
	Do $$$AssertEquals(run.StartedAt, answer.startedAt, "the answer's startedAt is the run's")

	Set events = ..Events(ref)
	Do $$$AssertEquals(events.%Size(), 4, "the stream holds four events of the press")
	If events.%Size() = 4 {
		Do $$$AssertEquals(events.%Get(0).type_":"_events.%Get(0).payload.state, "breakfeed.progress:sending", "the first is breakfeed.progress, sending")
		Do $$$AssertEquals(events.%Get(1).type_":"_events.%Get(1).payload.breakFeed.stage, "guide.state:sending", "then guide.state, stage sending")
		Do $$$AssertEquals(events.%Get(2).type_":"_events.%Get(2).payload.state, "breakfeed.progress:sent", "then breakfeed.progress, sent")
		Do $$$AssertEquals(events.%Get(3).type_":"_events.%Get(3).payload.breakFeed.stage, "guide.state:waiting", "then guide.state, stage waiting")
		Do $$$AssertEquals(events.%Get(0).payload.startedAt, run.StartedAt, "sending carries the run's startedAt")
		Do $$$AssertEquals(events.%Get(2).payload.startedAt, run.StartedAt, "sent carries the same startedAt")
	}

	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "BreakFeedIn", "PartnerTrigger")
	Do $$$AssertEquals(sent.%Size(), 1, "OCUTALON holds one request BreakFeedIn to PartnerTrigger")
	If sent.%Size() = 1 {
		Do $$$AssertEquals(sent.%Get(0).bodyClass, "OcuTalon.Demo.Msg.SendOrders", "it is a SendOrders")
		Do $$$AssertEquals(sent.%Get(0).superSession, trace, "its SuperSession is the session's TraceRef")
		Set body = ##class(OcuTalon.Demo.Msg.SendOrders).%OpenId(sent.%Get(0).bodyId)
		Do $$$AssertEquals(body.SessionRef, ref, "it carries the SessionRef")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "BreakFeedIn", "IncidentManager").%Size(), 0, "none goes to IncidentManager")
	Do ..AssertNotATurn(ref, headers)

	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).WaitCount(trace, "OrdersFromPartner", 8, 50), 50, "50 orders fail at OrdersFromPartner")
	Do ..AssertBatch(trace, 50)
	Hang 4
	Set requests = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(requests, 1, "FailurePoller", "IncidentManager").%Size(), 0, "FailurePoller sent nothing to IncidentManager: the failures are held")
}

/// Row 3: one order sent through Partner.Send directly, in MM/DD/YYYY, fails at the same item, with the same status and error text.
Method TestOtherMeansFailTheSame()
{
	If '..Guard() Quit
	Set ref = ..Watching()
	Set trace = ..TraceOf(ref)
	Do ..Press(ref, .sc)
	Set other = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Keep(other)
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).Send(1, "MM/DD/YYYY", other, ""), "", "an order is sent through the partner directly")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).WaitCount(other, "OrdersFromPartner", 8, 1), 1, "it fails at OrdersFromPartner")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).WaitCount(trace, "OrdersFromPartner", 8, 50), 50, "the press's 50 orders fail there too")
	Set header = ##class(OcuTalon.Test.Demo.Production).Headers(other).%Get(0)
	Do $$$AssertEquals(header.source_"->"_header.target, "PartnerOrdersIn->OrdersFromPartner", "the same item")
	Do $$$AssertEquals(header.status, 8, "the same status: Error")
	Do $$$AssertEquals(..ErrorOf(header.sessionId), 1, "the same error text")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).Count(other, "OrdersToWarehouse", 9), 0, "nothing reaches the warehouse")
}

/// Row 6: two presses at once for the session send one batch: one sent, one incident_in_progress, one run, 50 headers and not 100. The
/// session has a resolved incident, whose close the double holds for a second, so that a press that let go of the lock before it wrote its
/// run would let the other one in.
Method TestTwoQuickPressesSendOneBatch()
{
	If '..Guard() Quit
	Set ref = ..Watching()
	Set trace = ..TraceOf(ref)
	Do ##class(OcuTalon.Test.Data.Fixture).Incident(ref, , ..#NS, ..#PROD, {"State": "resolved"})
	Set ^OcuTalonTest("IncidentManagerDouble", "delay") = 1
	Kill ^OcuTalonTest("BreakFeedProduction", "press")
	For slot = 1, 2 {
		Job ##class(OcuTalon.Test.Demo.BreakFeedProduction).Presser(ref, slot)
	}
	Do ..WaitFor($Name(^OcuTalonTest("BreakFeedProduction", "press", ref, 1, "ready")), ..#PRESSSECONDS)
	Do ..WaitFor($Name(^OcuTalonTest("BreakFeedProduction", "press", ref, 2, "ready")), ..#PRESSSECONDS)
	Set ^OcuTalonTest("BreakFeedProduction", "press", ref, "gate") = 1
	Do ..WaitFor($Name(^OcuTalonTest("BreakFeedProduction", "press", ref, 1, "done")), ..#PRESSSECONDS)
	Do ..WaitFor($Name(^OcuTalonTest("BreakFeedProduction", "press", ref, 2, "done")), ..#PRESSSECONDS)
	Set outcomes = ""
	For slot = 1, 2 {
		Do $$$AssertEquals($Get(^OcuTalonTest("BreakFeedProduction", "press", ref, slot, "status")), 1, "press "_slot_" is accepted")
		Set outcomes = outcomes_$Select(outcomes = "": "", 1: ",")_$Get(^OcuTalonTest("BreakFeedProduction", "press", ref, slot, "outcome"))
	}
	Do $$$AssertTrue((outcomes = "sent,inactive:incident_in_progress") || (outcomes = "inactive:incident_in_progress,sent"), "one press is sent and one is incident_in_progress: "_outcomes)
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs(ref), "1:sent", "one run")
	Do $$$AssertEquals($Get(^OcuTalonTest("IncidentManagerDouble", "commands"), 0), 1, "the incident was closed once")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).WaitCount(trace, "OrdersFromPartner", 8, 50), 50, "50 orders fail")
	Hang 3
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).Count(trace, "OrdersFromPartner", 8), 50, "still 50 headers after the wait, not 100")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(..TraceOf(ref))
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "BreakFeedIn", "PartnerTrigger").%Size(), 1, "PartnerTrigger was asked once")
}

/// The job body of TestTwoQuickPressesSendOneBatch: waits for the gate, presses, and records the answer.
ClassMethod Presser(ref As %String, slot As %Integer)
{
	Set ^OcuTalonTest("BreakFeedProduction", "press", ref, slot, "ready") = 1
	Set deadline = $ZHorolog + ..#PRESSSECONDS
	While '$Get(^OcuTalonTest("BreakFeedProduction", "press", ref, "gate")) && ($ZHorolog < deadline) {
		Hang 0.01
	}
	Set output = ""
	Try {
		Set input = ##class(OcuTalon.Demo.Press).%New()
		Set input.SessionRef = ref
		Set sc = ##class(Ens.Director).CreateBusinessService("BreakFeedIn", .service)
		If $SYSTEM.Status.IsOK(sc) Set sc = service.ProcessInput(input, .output)
	} Catch exception {
		Set sc = exception.AsStatus()
	}
	Set ^OcuTalonTest("BreakFeedProduction", "press", ref, slot, "status") = $SYSTEM.Status.IsOK(sc)
	If $SYSTEM.Status.IsOK(sc) {
		Set answer = {}.%FromJSON(output)
		Set ^OcuTalonTest("BreakFeedProduction", "press", ref, slot, "outcome") = answer.outcome_$Select(answer.outcome = "inactive": ":"_answer.reason, 1: "")
	} Else {
		Set ^OcuTalonTest("BreakFeedProduction", "press", ref, slot, "outcome") = $SYSTEM.Status.GetErrorText(sc)
	}
	Set ^OcuTalonTest("BreakFeedProduction", "press", ref, slot, "done") = 1
}

/// Row 7: the session's noticed resolved Orders incident gets exactly one closeForReplay (the session, origin web_user) while the session
/// has no run; the double closes it, and then the batch is sent and fails as in rows 1 and 2. A resolved instance incident and another
/// session's resolved Orders incident get no command.
Method TestReplayClosesTheResolvedIncident()
{
	If '..Guard() Quit
	Set ref = ..Watching()
	Set other = ..Watching()
	Set trace = ..TraceOf(ref)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(ref, , ..#NS, ..#PROD, {"State": "resolved"})
	Set shared = ##class(OcuTalon.Test.Data.Fixture).Incident("instance", , ..#NS, ..#PROD, {"State": "resolved"})
	Set foreign = ##class(OcuTalon.Test.Data.Fixture).Incident(other, , ..#NS, ..#PROD, {"State": "resolved"})
	Set output = ..Press(ref, .sc)
	Do $$$AssertStatusOK(sc, "the press is accepted")
	Do $$$AssertEquals({}.%FromJSON(output).outcome, "sent", "the press is sent")
	Do $$$AssertEquals(^OcuTalonTest("IncidentManagerDouble", "commands"), 1, "the double got exactly one command")
	Do $$$AssertEquals(^OcuTalonTest("IncidentManagerDouble", "commands", 1), "closeForReplay", "a closeForReplay")
	Do $$$AssertEquals(^OcuTalonTest("IncidentManagerDouble", "commands", 1, "ref"), incident, "for the session's incident")
	Do $$$AssertEquals(^OcuTalonTest("IncidentManagerDouble", "commands", 1, "session"), ref, "with the SessionRef")
	Do $$$AssertEquals(^OcuTalonTest("IncidentManagerDouble", "commands", 1, "origin"), "web_user", "with the origin web_user")
	Do $$$AssertEquals(^OcuTalonTest("IncidentManagerDouble", "commands", 1, "runs"), "0:", "while the session had no run")
	Set closed = ##class(OcuTalon.Data.Incident).RefIndexOpen(incident)
	Do $$$AssertEquals(closed.State, "closed", "the incident is closed")
	Do $$$AssertTrue(closed.ClosedAt '= "", "with a ClosedAt")
	Do $$$AssertEquals(##class(OcuTalon.Data.Incident).RefIndexOpen(shared).State, "resolved", "the instance incident is untouched")
	Do $$$AssertEquals(##class(OcuTalon.Data.Incident).RefIndexOpen(foreign).State, "resolved", "the other session's incident is untouched")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).WaitCount(trace, "OrdersFromPartner", 8, 50), 50, "50 orders fail")
	Do ..AssertBatch(trace, 50)
}

/// Row 8: a close that the double refuses is inactive, incident_in_progress; there is no run, no PartnerTrigger message and no batch.
Method TestRefusedCloseSendsNothing()
{
	If '..Guard() Quit
	Set ref = ..Watching()
	Set trace = ..TraceOf(ref)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(ref, , ..#NS, ..#PROD, {"State": "resolved"})
	Set ^OcuTalonTest("IncidentManagerDouble", "answer") = "refuse"
	Set output = ..Press(ref, .sc)
	Do $$$AssertStatusOK(sc, "the press is accepted")
	Do $$$AssertEquals(output, {"outcome": "inactive", "reason": "incident_in_progress"}.%ToJSON(), "the answer is inactive, incident_in_progress")
	Do $$$AssertEquals(^OcuTalonTest("IncidentManagerDouble", "commands"), 1, "the double got the one command")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs(ref), "0:", "no run")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(headers, 1, "BreakFeedIn", "PartnerTrigger").%Size(), 0, "no message to PartnerTrigger")
	Hang 1
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).Headers(trace).%Size(), 0, "no order in OCUORDERS")
	Do $$$AssertEquals(##class(OcuTalon.Data.Incident).RefIndexOpen(incident).State, "resolved", "the incident was not closed")
}

/// Rows 8, 9 and 10 (the failures), through the real sends: a close that the double answers with an error is an error status, with no
/// run and no PartnerTrigger message; a press whose audit write fails (the Action event disabled, and enabled again after the press) is
/// an error status from PartnerTrigger, the run stays sending and no order is sent.
Method TestFailuresAreErrors()
{
	If '..Guard() Quit
	Set ref = ..Watching()
	Set trace = ..TraceOf(ref)
	Set incident = ##class(OcuTalon.Test.Data.Fixture).Incident(ref, , ..#NS, ..#PROD, {"State": "resolved"})
	Set ^OcuTalonTest("IncidentManagerDouble", "answer") = "error"
	Set output = ..Press(ref, .sc)
	Do $$$AssertStatusNotOK(sc, "a close answered with an error: the press is an error status")
	Do $$$AssertEquals(output, "", "there is no answer")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs(ref), "0:", "no run")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "BreakFeedIn", "PartnerTrigger").%Size(), 0, "no message to PartnerTrigger")
	Do $$$AssertEquals(##class(OcuTalon.Data.Incident).RefIndexOpen(incident).State, "resolved", "the incident was not closed")

	Kill ^OcuTalonTest("IncidentManagerDouble")
	Set ref = ..Watching()
	Set trace = ..TraceOf(ref)
	Do ##class(OcuTalon.Test.Bridge.AuditLog).SetEvent(..#EVENT, 0)
	Set output = ..Press(ref, .sc)
	Do ##class(OcuTalon.Test.Bridge.AuditLog).SetEvent(..#EVENT, 1)
	Do $$$AssertStatusNotOK(sc, "the audit write failed: the press is an error status")
	Do $$$AssertEquals(output, "", "there is no answer")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.BreakFeedInProbe).Runs(ref), "1:sending", "the run stays sending")
	Do $$$AssertEquals(##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, "BreakFeedIn", "PartnerTrigger").%Size(), 1, "PartnerTrigger was asked once")
	Hang 1
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).Headers(trace).%Size(), 0, "no order in OCUORDERS")
}

/// Row 10: one press, one Action entry in the audit log within 180 s, naming the session, the user and the channel web; a refused press
/// writes none.
Method TestPressIsAudited()
{
	If '..Guard() Quit
	Set ref = ..Watching()
	Set refused = ..NewSession()
	Set user = ##class(OcuTalon.Data.Session).RefIndexOpen(ref).IrisUser
	Set mark = ##class(OcuTalon.Test.Bridge.AuditLog).Now()
	Do ..Press(ref, .sc)
	Do $$$AssertStatusOK(sc, "the press is accepted")
	Set entries = ##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", ref, "", 1, ..#AUDITSECONDS)
	Do $$$AssertEquals(entries.%Size(), 1, "exactly one Action entry names the session")
	If entries.%Size() = 1 {
		Set data = entries.%Get(0).data
		Do $$$AssertEquals(data.sessionRef, ref, "its sessionRef is the session")
		Do $$$AssertEquals(data.irisUser, user, "its user is the session's IrisUser")
		Do $$$AssertEquals(data.channel, "web", "its channel is web")
		Do $$$AssertEquals(data.counts.orders, 50, "it counts 50 orders")
		Do $$$AssertEquals(entries.%Get(0).description, "Break the feed: 50 orders", "its description")
	}
	Set output = ..Press(refused, .sc)
	Do $$$AssertEquals(output, {"outcome": "inactive", "reason": "not_watching"}.%ToJSON(), "the second press is refused: its session watches nothing")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Wait(mark, "OcuTalon", "Action", "Action", refused, "", 1, 3).%Size(), 0, "a refused press writes no entry")
	Do $$$AssertEquals(##class(OcuTalon.Test.Bridge.AuditLog).Entries(mark, "OcuTalon", "Action", "Action", ref).%Size(), 1, "and still one entry names the session")
}

/// Row 12: two sessions pressed at once get 50 failed orders each, none crossing over; PartnerOrdersIn's settings are unchanged; and a
/// YYYY-MM-DD control batch afterwards completes at OrdersToWarehouse.
Method TestTwoSessionsGetTheirOwnBatch()
{
	If '..Guard() Quit
	Set first = ..Watching()
	Set second = ..Watching()
	Set traceFirst = ..TraceOf(first)
	Set traceSecond = ..TraceOf(second)
	Do $$$AssertTrue(traceFirst '= traceSecond, "the sessions have their own TraceRefs")
	Set before = ..ItemSettings("PartnerOrdersIn")
	Do $$$AssertTrue(before '= "", "PartnerOrdersIn was read")
	Kill ^OcuTalonTest("BreakFeedProduction", "press")
	Job ##class(OcuTalon.Test.Demo.BreakFeedProduction).Presser(first, 1)
	Job ##class(OcuTalon.Test.Demo.BreakFeedProduction).Presser(second, 1)
	Do ..WaitFor($Name(^OcuTalonTest("BreakFeedProduction", "press", first, 1, "ready")), ..#PRESSSECONDS)
	Do ..WaitFor($Name(^OcuTalonTest("BreakFeedProduction", "press", second, 1, "ready")), ..#PRESSSECONDS)
	Set ^OcuTalonTest("BreakFeedProduction", "press", first, "gate") = 1
	Set ^OcuTalonTest("BreakFeedProduction", "press", second, "gate") = 1
	Do ..WaitFor($Name(^OcuTalonTest("BreakFeedProduction", "press", first, 1, "done")), ..#PRESSSECONDS)
	Do ..WaitFor($Name(^OcuTalonTest("BreakFeedProduction", "press", second, 1, "done")), ..#PRESSSECONDS)
	Do $$$AssertEquals($Get(^OcuTalonTest("BreakFeedProduction", "press", first, 1, "outcome")), "sent", "the first press is sent")
	Do $$$AssertEquals($Get(^OcuTalonTest("BreakFeedProduction", "press", second, 1, "outcome")), "sent", "the second press is sent")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).WaitCount(traceFirst, "OrdersFromPartner", 8, 50), 50, "50 orders of the first session fail")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).WaitCount(traceSecond, "OrdersFromPartner", 8, 50), 50, "50 orders of the second session fail")
	Hang 2
	Do ..AssertBatch(traceFirst, 50)
	Do ..AssertBatch(traceSecond, 50)
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).Headers(traceFirst).%Size(), 50, "the first session's TraceRef carries exactly its 50 headers")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).Headers(traceSecond).%Size(), 50, "the second session's carries its own 50")
	Do $$$AssertEquals(..ItemSettings("PartnerOrdersIn"), before, "PartnerOrdersIn's settings are unchanged")
	Set control = ##class(OcuTalon.Bridge.Ids).NewRef()
	Do ..Keep(control)
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).Send(1, "YYYY-MM-DD", control, "2026-10-16"), "", "a control batch in YYYY-MM-DD is sent")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).WaitCount(control, "OrdersToWarehouse", 9, 1), 1, "it completes at OrdersToWarehouse")
}

/// QA, row 11 in the real production: a press is production messages and no turn. Every message that carries the TraceRef in OCUTALON is
/// between BreakFeedIn and PartnerTrigger (none to WebChatIn, Conversation or any other item), and the session has no Turn and no Decision.
Method AssertNotATurn(ref As %String, headers As %DynamicArray) [ Private ]
{
	Set stray = ""
	For i = 0:1:headers.%Size() - 1 {
		Set header = headers.%Get(i)
		If '$ListFind($ListBuild("BreakFeedIn", "PartnerTrigger"), header.source) || '$ListFind($ListBuild("BreakFeedIn", "PartnerTrigger"), header.target) Set stray = stray_header.source_"->"_header.target_" "
	}
	Do $$$AssertEquals(stray, "", "every message of the press is between BreakFeedIn and PartnerTrigger")
	Do $$$AssertTrue(headers.%Size() > 0, "and there is at least one")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.Turn WHERE SessionRef = ?", ref)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 0, "the session has no Turn")
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Bridge_Data.Decision WHERE OwnerRef = ?", ref)
	Do result.%Next()
	Do $$$AssertEquals(result.%GetData(1), 0, "the session has no Decision")
}

/// The batch of the TraceRef: count headers at OrdersFromPartner, all in status Error, none at OrdersToWarehouse, in count different
/// sessions, each with the transform's error "Expected YYYY-MM-DD, got '<MM/DD/YYYY>'." in its event log.
Method AssertBatch(trace As %String, count As %Integer) [ Private ]
{
	Set headers = ##class(OcuTalon.Test.Demo.Production).Headers(trace)
	Do $$$AssertEquals(headers.%Size(), count, "the batch is "_count_" headers")
	Set wrong = 0
	Set unlogged = 0
	Set unformatted = 0
	For i = 0:1:headers.%Size() - 1 {
		Set header = headers.%Get(i)
		If (header.source_"->"_header.target '= "PartnerOrdersIn->OrdersFromPartner") || (header.status '= 8) Set wrong = wrong + 1
		If '(header.body.OrderDate ? 2N1"/"2N1"/"4N) Set unformatted = unformatted + 1
		If '..ErrorOf(header.sessionId) Set unlogged = unlogged + 1
	}
	Do $$$AssertEquals(wrong, 0, "every header is at OrdersFromPartner in status Error")
	Do $$$AssertEquals(unformatted, 0, "every order is dated MM/DD/YYYY")
	Do $$$AssertEquals(unlogged, 0, "every session's event log ends with Expected YYYY-MM-DD, got '<MM/DD/YYYY>'.")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).Count(trace, "OrdersToWarehouse", 9), 0, "none reaches OrdersToWarehouse")
	Do $$$AssertEquals(##class(OcuTalon.Test.Demo.Production).Sessions(trace), count, "the orders are in "_count_" sessions")
}

/// 1 when the event log of the session holds the transform's error that ends "Expected YYYY-MM-DD, got '<MM/DD/YYYY>'.".
ClassMethod ErrorOf(session As %String) As %Boolean [ Private ]
{
	Set texts = ##class(OcuTalon.Test.Demo.Production).ErrorTexts(session)
	For i = 0:1:texts.%Size() - 1 {
		If $Translate(texts.%Get(i), $Char(13, 10), "") ? .E1"Expected YYYY-MM-DD, got '"2N1"/"2N1"/"4N1"'." Quit
	}
	Quit (i < texts.%Size())
}

/// The item of the Orders production as JSON text (name, className, enabled, poolSize and settings, as Test.Demo.Production.Snapshot
/// reads the production definition), "" when the item is not there. The snapshot is taken for a reference that has no messages.
ClassMethod ItemSettings(item As %String) As %String [ Private ]
{
	Set items = ##class(OcuTalon.Test.Demo.Production).Snapshot(##class(OcuTalon.Bridge.Ids).NewRef()).items
	For i = 0:1:items.%Size() - 1 {
		If items.%Get(i).name = item Return items.%Get(i).%ToJSON()
	}
	Quit ""
}

/// The live events of the stream that the press made (breakfeed.progress and guide.state), in order, as an array of {type, payload}.
ClassMethod Events(ref As %String) As %DynamicArray [ Private ]
{
	Set events = []
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT Type, Payload FROM OcuTalon_Live.Event WHERE Stream = ? AND Type IN ('breakfeed.progress', 'guide.state') ORDER BY Seq", ref)
	While result.%Next() {
		Do events.%Push({"type": (result.%Get("Type")), "payload": ({}.%FromJSON(result.%Get("Payload")))})
	}
	Quit events
}

/// Presses for the session as Web.Api does, in this process: the answer's JSON text, and the status in sc.
Method Press(ref As %String, Output sc As %Status) As %String [ Private ]
{
	Set output = ""
	Set input = ##class(OcuTalon.Demo.Press).%New()
	Set input.SessionRef = ref
	Set sc = ##class(Ens.Director).CreateBusinessService("BreakFeedIn", .service)
	If $SYSTEM.Status.IsError(sc) Quit ""
	Set sc = service.ProcessInput(input, .output)
	Quit output
}

/// A fixture session that watches the Orders production.
Method Watching() As %String [ Private ]
{
	Set ref = ..NewSession()
	Do ##class(OcuTalon.Test.Data.Fixture).Check(ref, ..#NS, ..#PROD)
	Quit ref
}

/// A fixture session, whose TraceRef is kept for the clean-up of the messages.
Method NewSession() As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzbfprod"_..Number)
	Do ..Keep(..TraceOf(ref))
	Quit ref
}

/// The TraceRef of the session.
ClassMethod TraceOf(ref As %String) As %String [ Private ]
{
	Quit ##class(OcuTalon.Data.Session).RefIndexOpen(ref).TraceRef
}

/// Keeps a SuperSession for the clean-up.
Method Keep(trace As %String) [ Private ]
{
	Do ..Traces.%Push(trace)
}

/// 1 when OcuTalon.Production runs in this namespace.
ClassMethod OcuTalonRunning() As %Boolean [ Private ]
{
	Quit ''##class(Ens.Director).IsProductionRunning(.name) && (name = "OcuTalon.Production")
}

/// 1 when the test may run. Otherwise it fails with the reason, and the test quits.
Method Guard() As %Boolean [ Private ]
{
	If ..Missing '= "" {
		Do $$$AssertTrue(0, ..Missing)
		Quit 0
	}
	Quit 1
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
