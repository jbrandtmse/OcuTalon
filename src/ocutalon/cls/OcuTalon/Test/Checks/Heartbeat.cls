/// Tests of Checks, OcuTalon.Checks.Process, in the running production (Story 5.6; AD-4, AD-12, AD-15, AD-18, AD-26, AD-28, AD-33). THEY RUN IN THROWAWAY STACKS
/// AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case, and fresh: a real Tick acts on every check row and every quiet incident of the
/// namespace, so each test asserts only on its own rows. A Tick is sent as HeartbeatIn sends it, from an adapterless service created with
/// Ens.Director.CreateBusinessService, synchronously to the Checks item; the service's session is the Tick's trace session.
///   - TestTickRunsTheWatch (AC 1, DW-66): a due watch of Orders passes on its first Tick: the row holds the run time, passed, no finding and the Tick's session,
///     its next due time is the Tick's time plus 60 seconds, one check event equal to FromRow is on the session's stream, and /state (Web.Api.StateBody) shows the
///     run with the trace in OcuTalon's own namespace and a trace URL that ends in the Tick's session;
///   - TestFailingOrders (AC 2): three failing orders tagged with the session's TraceRef fail the next run ("3 new failures"); with Orders stopped the finding begins
///     "Production stopped"; Orders is started again and runs;
///   - TestQuietClose (AC 3): the real IncidentManager closes a noticed resolved incident whose last failure is 16 minutes old (closed with ClosedAt, one incident
///     event closed, and the closeQuiet request in the Tick's session carries the owner's TraceRef as SuperSession) and leaves the 14 minute one resolved;
///   - TestStartAndStop (AC 4): a StartWatch and a StopWatch through the WatchOps item put two check events on the session's stream, in order: FromRow of the new
///     row with no run, then the same Ref with stopped true.
Class OcuTalon.Test.Checks.Heartbeat Extends OcuTalon.Test.Watch.Case
{

Parameter SESSIONPREFIX = "zzbeat";

/// The service that sends the Tick, and the item that handles it.
Parameter HEARTBEAT = "HeartbeatIn";

Parameter CHECKS = "Checks";

Parameter WATCHOPS = "WatchOps";

/// The longest a Tick is waited for, in seconds.
Parameter TICKWAIT = 60;

Method TestTickRunsTheWatch()
{
	If '..Ready() Quit
	Set session = ..Session("tick")
	Set ref = ..Watch(session)
	Hang 1.1
	Set tickAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set before = tickAt
	Set id = ..Tick(tickAt)
	If id = "" Quit
	Set row = ..Check(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "passed|", "the watch passed with an empty finding")
	Do $$$AssertTrue('(before ] row.LastRunAt) && '(row.LastRunAt ] ##class(OcuTalon.Data.Time).NowUtc()), "LastRunAt is the run time: "_row.LastRunAt)
	Do $$$AssertEquals(row.LastRunHeaderId, id, "LastRunHeaderId is the Tick's session")
	Do $$$AssertEquals(row.NextDueAt, ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(tickAt, 60)), "NextDueAt is the Tick's time plus 60 seconds")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "check", 1, 10)
	Do $$$AssertEquals(events.%Size(), 1, "one check event is on the session's stream")
	Do ##class(OcuTalon.Live.Payload.Check).FromRow(row).%JSONExportToString(.expected)
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.%ToJSON(), expected, "and it is FromRow of the row")
	Set body = ##class(OcuTalon.Web.Api).StateBody(##class(OcuTalon.Data.Session).RefIndexOpen(session))
	Set found = ""
	Set iterator = body.rail.checks.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.ref = ref Set found = entry
	}
	Do $$$AssertTrue($IsObject(found), "/state lists the check")
	If $IsObject(found) {
		Do $$$AssertEquals(found.lastRunAt_"|"_found.result, row.LastRunAt_"|passed", "with the run")
		Do $$$AssertEquals(found.traceHeaderId_"|"_found.traceNamespace, id_"|"_$Namespace, "and the trace of the Tick's session in OcuTalon's own namespace")
		Do $$$AssertEquals(found.traceUrl, "/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID="_id, "with a trace URL into OCUTALON's trace application")
	}
}

Method TestFailingOrders()
{
	If '..Ready() Quit
	Set session = ..Session("failing")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set ref = ..Watch(session)
	If '..Fail(3, trace) Quit
	Do ..WaitFailed(3)
	Set tickAt = ##class(OcuTalon.Data.Time).NowUtc()
	If ..Tick(tickAt) = "" Quit
	Set row = ..Check(ref)
	Do $$$AssertEquals(row.Result, "failed", "the run fails")
	Do $$$AssertEquals($Extract(row.Finding, 1, 14), "3 new failures", "and the finding begins with the three failures: "_row.Finding)
	If '..StopOrders() Quit
	Set next = ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(tickAt, 60))
	If ..Tick(next) = "" Quit
	Set row = ..Check(ref)
	Do $$$AssertEquals(row.Result, "failed", "with Orders stopped the run fails")
	Do $$$AssertEquals($Extract(row.Finding, 1, 18), "Production stopped", "and the finding begins with the state: "_row.Finding)
	Do ..StartOrders()
	Do $$$AssertTrue(..OrdersRunning(), "Orders runs again")
}

Method TestQuietClose()
{
	If '..Ready() Quit
	Set session = ..Session("quiet")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set long = ##class(OcuTalon.Bridge.Time).PlusSeconds(##class(OcuTalon.Data.Time).NowUtc(), -960)
	Set short = ##class(OcuTalon.Bridge.Time).PlusSeconds(##class(OcuTalon.Data.Time).NowUtc(), -840)
	Set quiet = ..Resolved(session, long)
	Set recent = ..Resolved(session, short)
	Set id = ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	If id = "" Quit
	Set row = ..Incident(quiet)
	Do $$$AssertEquals(row.State_"|"_(row.ClosedAt '= ""), "closed|1", "the 16 minute incident is closed, with ClosedAt")
	Do $$$AssertEquals(..Incident(recent).State, "resolved", "and the 14 minute incident stays resolved")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "incident", 1, 10)
	Do $$$AssertEquals(events.%Size(), 1, "one incident event is on the session's stream")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.ref_"|"_events.%Get(0).payload.state, quiet_"|closed", "closed, for the 16 minute incident")
	Set requests = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(id), 1, ..#CHECKS, ..#MANAGER)
	Set mine = 0
	For i = 0:1:requests.%Size() - 1 {
		If requests.%Get(i).superSession = trace Set mine = mine + 1
	}
	Do $$$AssertEquals(mine, 1, "Checks sent one closeQuiet in the Tick's session, with the owner's TraceRef as its SuperSession")
}

Method TestStartAndStop()
{
	If '..Ready() Quit
	Set session = ..Session("startstop")
	Set fixture = ..#FIXTURE
	Set start = ##class(OcuTalon.Msg.Command.StartWatch).%New()
	Set start.SessionRef = session
	Set start.IdempotencyKey = "zzbeatstart"
	Set start.Origin = "tool"
	Set start.Namespace = ..#ORDERS
	Set start.Production = ..#ORDERSPRODUCTION
	Set start.DisplayName = "Orders"
	Do $$$AssertStatusOK($ClassMethod(fixture, "Send", ..#WATCHOPS, start, .started), "WatchOps answers the StartWatch")
	Do $$$AssertEquals(started.Outcome, "started", "started: "_started.Message)
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "check", 1, 20)
	Do $$$AssertEquals(events.%Size(), 1, "one check event reaches the stream")
	Set row = ..Check(started.Ref)
	Do $$$AssertTrue($IsObject(row), "the row exists")
	If $IsObject(row) && (events.%Size() = 1) {
		Do ##class(OcuTalon.Live.Payload.Check).FromRow(row).%JSONExportToString(.expected)
		Do $$$AssertEquals(events.%Get(0).payload.%ToJSON(), expected, "it is FromRow of the new row")
		Do $$$AssertEquals(events.%Get(0).payload.lastRunAt_"|"_events.%Get(0).payload.%IsDefined("traceHeaderId"), "|0", "with no run and no trace")
	}
	Set stop = ##class(OcuTalon.Msg.Command.StopWatch).%New()
	Set stop.SessionRef = session
	Set stop.IdempotencyKey = "zzbeatstop"
	Set stop.Origin = "tool"
	Set stop.Namespace = ..#ORDERS
	Set stop.Production = ..#ORDERSPRODUCTION
	Do $$$AssertStatusOK($ClassMethod(fixture, "Send", ..#WATCHOPS, stop, .stopped), "WatchOps answers the StopWatch")
	Do $$$AssertEquals(stopped.Outcome, "stopped", "stopped: "_stopped.Message)
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "check", 2, 20)
	Do $$$AssertEquals(events.%Size(), 2, "a second check event reaches the stream")
	If events.%Size() = 2 {
		Set payload = events.%Get(1).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.stopped, started.Ref_"|1", "it has the same Ref and stopped true")
		Do $$$AssertEquals(payload.%GetTypeOf("stopped"), "boolean", "and stopped is a JSON boolean, which the page's filter tests with ===")
		Do $$$AssertEquals(payload.namespace_"|"_payload.production_"|"_payload.displayName, ..#ORDERS_"|"_..#ORDERSPRODUCTION_"|Orders", "and the watch's name")
		Do $$$AssertTrue(events.%Get(1).seq > events.%Get(0).seq, "after the first")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(started.Ref), 0, "the row is gone")
}

/// --- helpers ---
/// The check row as stored now: other processes change it, and an object that this one opened before is reloaded.
ClassMethod Check(ref As %String) As OcuTalon.Data.BackgroundCheck [ Private ]
{
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
	If $IsObject(row) Do row.%Reload()
	Quit row
}

/// The incident row as stored now.
ClassMethod Incident(ref As %String) As OcuTalon.Data.Incident [ Private ]
{
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	If $IsObject(row) Do row.%Reload()
	Quit row
}

/// Sends a Tick of the time from HeartbeatIn to Checks and waits for the answer; the id of the service's session, the Tick's trace session, or "" with a failed
/// assertion.
Method Tick(tickAt As %String) As %Integer [ Private ]
{
	Set sc = ##class(Ens.Director).CreateBusinessService(..#HEARTBEAT, .service)
	Do $$$AssertStatusOK(sc, "the "_..#HEARTBEAT_" service is created")
	If $$$ISERR(sc) Quit ""
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = tickAt
	Set sc = service.SendRequestSync(..#CHECKS, tick, .response, ..#TICKWAIT)
	Do $$$AssertStatusOK(sc, "Checks answers the Tick at "_tickAt)
	If $$$ISERR(sc) Quit ""
	Quit service.%SessionId
}

/// A fixture incident of the session on Orders, noticed, resolved, with the last failure at the time; its Ref (removed with the test's rows).
Method Resolved(session As %String, lastAt As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(session, ##class(OcuTalon.Data.Time).NowUtc(), ..#ORDERS, ..#ORDERSPRODUCTION, {"State": "resolved", "OpenVariant": "", "LastAt": (lastAt)})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

}
