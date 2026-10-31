/// Tests of Checks, OcuTalon.Checks.Process, in the running production (Story 5.6; AD-4, AD-12, AD-15, AD-18, AD-26, AD-28, AD-33). THEY RUN IN THROWAWAY STACKS
/// AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case, and fresh: a real Tick acts on every check row and every quiet incident of the
/// namespace, so each test asserts only on its own rows. A Tick is sent as HeartbeatIn sends it, from an adapterless service created with
/// Ens.Director.CreateBusinessService, to the Checks item; the service's session is the Tick's trace session. A test that runs its row sends its own Tick
/// synchronously at the row's NextDueAt (the fixture watch is due a day ahead, see Case.Watch); TestQuietClose's own Tick is at the clock's now. The first
/// three tests also send a real-shaped Tick themselves (RealTick: at the clock's now, asynchronously, waited for) at the worst moment: in TestTickRunsTheWatch
/// and TestFailingOrders it changes none of the test's rows, and in TestQuietClose it, or a real Tick before it, is the Tick that closes the quiet incident.
///   - TestTickRunsTheWatch (AC 1, DW-66): a real Tick leaves the due-ahead watch of Orders without a run; the Tick at its NextDueAt passes it: the row holds the run
///     time, passed, no finding and the Tick's session, its next due time is the Tick's time plus 60 seconds, one check event equal to FromRow is on the session's
///     stream, and /state (Web.Api.StateBody) shows the run with the trace in OcuTalon's own namespace and a trace URL that ends in the Tick's session;
///   - TestFailingOrders (AC 2): three failing orders tagged with the session's TraceRef, a real Tick that runs nothing, then the Tick at the due time fails the
///     run ("3 new failures"); with Orders stopped the finding of the Tick a minute later begins "Production stopped" (and, from Story 30.4, that Tick sends one
///     finding Item to Intake, which this test does not assert); Orders is started again and runs;
///   - TestStoppedProductionIsReportedOnce (Story 30.4; AC 1, AC 2; FR-33; the matrix row 12): the Tick at NextDueAt only records the baseline (running); after Orders is
///     stopped, the Ticks a minute and two minutes later send exactly one Item from Checks to Intake for the session, across both Ticks' sessions: key watch.productionStopped,
///     production "Orders", a time between just before the stop and just after it (IRIS's own stop time), the session's TraceRef as SuperSession. Intake sends one
///     ItemDecision to OutcomeRouter with the same CatalogKey and Slots (Integration AC). Orders is started again;
///   - TestDisabledItemIsReportedOnce (Story 30.4; AC 1, AC 2; the matrix row 13): the session's fixture watch has the CI mock's marker check-finding-tell-now in its display name; the
///     baseline Tick, then OrdersToWarehouse disabled in OCUORDERS and two Ticks send exactly one watch.itemDisabled Item for it, and the session's web chat gets one tell-now
///     notification whose text is the catalog's rendering of that key and those slots, its second line "Why now: you asked me to watch the {name} production." (Integration
///     AC). The item is enabled again after the test, also after a failure (OnAfterOneTest);
///   - TestQuietClose (AC 3): a real Tick, before the test's own, makes the real IncidentManager close a noticed resolved incident whose last failure is 16 minutes
///     old (closed with ClosedAt, one incident event closed). Across all sessions of Checks exactly one closeQuiet names it, and it goes in a session whose first
///     request is a Tick to Checks, with the owner's TraceRef as SuperSession; the test's own Tick sends none. The 14 minute incident stays resolved;
///   - TestStartAndStop (AC 4): a StartWatch and a StopWatch through the WatchOps item put check events on the session's stream, in order: FromRow of the new
///     row with no run, then the same Ref with stopped true. WatchOps makes the row due at once, so a real Tick may run it between the two: where an event
///     carries lastRunAt, the first event names the row, each middle event is a run of it and the last is the stop.
Class OcuTalon.Test.Checks.Heartbeat Extends OcuTalon.Test.Watch.Case
{

Parameter SESSIONPREFIX = "zzbeat";

Parameter WATCHOPS = "WatchOps";

/// The marker that makes the CI mock tell the user about the check's finding.
Parameter MARKER = "[[mock:check-finding-tell-now]]";

Method TestTickRunsTheWatch()
{
	If '..Ready() Quit
	Set session = ..Session("tick")
	Set ref = ..Watch(session)
	Hang 1.1
	If ..RealTick() = "" Quit
	Set row = ..Check(ref)
	Do $$$AssertEquals(row.LastRunAt_"|"_row.Result, "|", "a real Tick does not run the watch: it is not due for a day")
	Set tickAt = row.NextDueAt
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
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
	If ..RealTick() = "" Quit
	Set row = ..Check(ref)
	Do $$$AssertEquals(row.LastRunAt_"|"_row.Result, "|", "a real Tick does not run the watch: it is not due for a day")
	Set tickAt = row.NextDueAt
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

Method TestStoppedProductionIsReportedOnce()
{
	If '..Ready() Quit
	Set session = ..Session("stopreport")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set ref = ..Watch(session)
	Set tickAt = ..Check(ref).NextDueAt
	Set base = ..Tick(tickAt)
	If base = "" Quit
	Do $$$AssertEquals($Extract(..Check(ref).Reported, 1, 12), "{""stopped"":0", "the Tick at NextDueAt records the baseline: Orders runs")
	Do $$$AssertEquals(..Findings(base, session).%Size(), 0, "and sends no Item")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	If '..StopOrders() Quit
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Set next = ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(tickAt, 60))
	Set first = ..Tick(next)
	If first = "" Quit
	Set last = ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(next, 60))
	Set second = ..Tick(last)
	If second = "" Quit
	Set items = ..Findings(first, session)
	Do $$$AssertEquals(items.%Size()_"|"_..Findings(second, session).%Size(), "1|0", "the first Tick after the stop sends one Item to Intake for the session, and the second sends none")
	If items.%Size() = 1 {
		Set item = items.%Get(0)
		Set slots = {}.%FromJSON(item.slots)
		Do $$$AssertEquals(item.catalogKey_"|"_slots.production, "watch.productionStopped|Orders", "its key and production")
		Do $$$AssertTrue('(before ] slots.time) && '(slots.time ] after), "and its time is the stop's, between just before and just after it: "_slots.time)
		Do $$$AssertEquals(item.channel_"|"_item.provenance_"|"_item.superSession, "system|untrusted|"_trace, "from the system channel, untrusted, with the session's TraceRef as SuperSession")
		Set decision = ..Decision(first, item.itemId)
		If $IsObject(decision) Do $$$AssertEquals(decision.catalogKey_"|"_decision.slots, item.catalogKey_"|"_item.slots, "Intake sent OutcomeRouter one ItemDecision with the same CatalogKey and Slots")
	}
	Do ..StartOrders()
}

Method TestDisabledItemIsReportedOnce()
{
	If '..Ready() Quit
	Set session = ..Session("disabledreport")
	Set name = "Orders "_..#MARKER
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, ..#ORDERS, ..#ORDERSPRODUCTION, {"DisplayName": (name), "AskedBy": "zzfixture", "CreatedAt": (##class(OcuTalon.Data.Time).NowUtc()), "NextDueAt": (..Ahead())})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set tickAt = ..Check(ref).NextDueAt
	Set base = ..Tick(tickAt)
	If base = "" Quit
	Do $$$AssertEquals($Extract(..Check(ref).Reported, 1, 12), "{""stopped"":0", "the Tick at NextDueAt records the baseline")
	Do $$$AssertEquals(..Findings(base, session).%Size(), 0, "and sends no Item")
	Set ..ItemDisabled = 1
	Do $$$AssertStatusOK(..SetItemEnabled(0), ..#ITEMNAME_" is disabled in "_..#ORDERS)
	Set next = ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(tickAt, 60))
	Set first = ..Tick(next)
	If first = "" Quit
	Set last = ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(next, 60))
	Set second = ..Tick(last)
	If second = "" Quit
	Set items = ..Findings(first, session)
	Do $$$AssertEquals(items.%Size()_"|"_..Findings(second, session).%Size(), "1|0", "exactly one Item goes to Intake for the disabled item, in the first Tick after it")
	If items.%Size() '= 1 Quit
	Set item = items.%Get(0)
	Set slots = {}.%FromJSON(item.slots)
	Do $$$AssertEquals(item.catalogKey_"|"_slots.itemName_"|"_slots.production, "watch.itemDisabled|"_..#ITEMNAME_"|"_name, "with the key, the item's name and the production's name")

	// Integration AC: the tell-now decision reaches the session's web chat once, as the catalog renders it
	Set channel = ##class(OcuTalon.Channel.WebChat.Out).#CHANNEL
	Do ##class(OcuTalon.Test.Core.Observe).WaitDeliveries(session, 1, ..#WAITDIAGNOSIS)
	Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
	Set texts = ""
	For i = 1:1:rows.Count() {
		If rows.GetAt(i).Channel = channel Set texts = texts_$ListBuild(rows.GetAt(i).Text)
	}
	Do $$$AssertEquals($ListLength(texts), 1, "the session's web chat got one notification")
	If $ListLength(texts) '= 1 Quit
	Set expected = ##class(OcuTalon.Msg.Catalog).Render(item.catalogKey, item.slots, channel)
	Do $$$AssertEquals($List(texts, 1), expected, "whose text is the catalog's rendering of the key and the slots")
	Do $$$AssertEquals($Piece($List(texts, 1), $Char(10), 2), "Why now: you asked me to watch the "_name_" production.", "with the Why now line")
	Do $$$AssertTrue($List(texts, 1) [ ("The "_..#ITEMNAME_" in the "_name_" production was disabled"), "and it says that the item was disabled: "_$List(texts, 1))
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
	If ..RealTick() = "" Quit
	Set id = ..Tick(##class(OcuTalon.Data.Time).NowUtc())
	If id = "" Quit
	Set row = ..Incident(quiet)
	Do $$$AssertEquals(row.State_"|"_(row.ClosedAt '= ""), "closed|1", "the 16 minute incident is closed, with ClosedAt")
	Do $$$AssertEquals(..Incident(recent).State, "resolved", "and the 14 minute incident stays resolved")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "incident", 1, 10)
	Do $$$AssertEquals(events.%Size(), 1, "one incident event is on the session's stream")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.ref_"|"_events.%Get(0).payload.state, quiet_"|closed", "closed, for the 16 minute incident")
	Set sent = ..QuietRequests(quiet)
	Do $$$AssertEquals(sent.%Size(), 1, "Checks sent exactly one closeQuiet for the 16 minute incident, across all its sessions")
	If sent.%Size() = 1 {
		Set request = sent.%Get(0)
		Set headers = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(request.sessionId)
		Set first = $Select(headers.%Size(): headers.%Get(0), 1: {})
		Do $$$AssertEquals(first.type_"|"_first.target_"|"_first.bodyClass, "1|"_..#CHECKS_"|OcuTalon.Msg.Tick", "it went in a session whose first request is a Tick to Checks")
		Do $$$AssertEquals(request.superSession, trace, "with the owner's TraceRef as its SuperSession")
		Do $$$AssertTrue(request.sessionId '= id, "and not in the session of the test's own Tick, which sent none")
	}
	Do $$$AssertEquals(..QuietRequests(recent).%Size(), 0, "none names the 14 minute incident")
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
	Set first = ##class(OcuTalon.Test.Core.Observe).Events(session, "check", 1, 20)
	Set row = ..Check(started.Ref)
	Do $$$AssertTrue($IsObject(row), "the row exists")
	Set stop = ##class(OcuTalon.Msg.Command.StopWatch).%New()
	Set stop.SessionRef = session
	Set stop.IdempotencyKey = "zzbeatstop"
	Set stop.Origin = "tool"
	Set stop.Namespace = ..#ORDERS
	Set stop.Production = ..#ORDERSPRODUCTION
	Do $$$AssertStatusOK($ClassMethod(fixture, "Send", ..#WATCHOPS, stop, .stopped), "WatchOps answers the StopWatch")
	Do $$$AssertEquals(stopped.Outcome, "stopped", "stopped: "_stopped.Message)
	Set events = ..WaitStopped(session)
	Set ran = 0
	For i = 0:1:events.%Size() - 1 {
		If events.%Get(i).payload.lastRunAt '= "" Set ran = 1
	}
	If 'ran {
		Do $$$AssertEquals(first.%Size(), 1, "one check event reaches the stream")
		If $IsObject(row) && (first.%Size() = 1) {
			Do ##class(OcuTalon.Live.Payload.Check).FromRow(row).%JSONExportToString(.expected)
			Do $$$AssertEquals(first.%Get(0).payload.%ToJSON(), expected, "it is FromRow of the new row")
			Do $$$AssertEquals(first.%Get(0).payload.lastRunAt_"|"_first.%Get(0).payload.%IsDefined("traceHeaderId"), "|0", "with no run and no trace")
		}
		Do $$$AssertEquals(events.%Size(), 2, "a second check event reaches the stream")
	} Else {
		Do $$$LogMessage("A real Tick ran the row between the start and the stop: the first event names the row, the middle events are its runs and the last is the stop")
		Do $$$AssertTrue(events.%Size() > 2, "the stream holds the start, at least one run and the stop")
		Do $$$AssertTrue((events.%Get(0).payload.ref = started.Ref) && 'events.%Get(0).payload.stopped, "the first event names the row and is no stop")
		For i = 1:1:events.%Size() - 2 {
			Do $$$AssertTrue((events.%Get(i).payload.ref = started.Ref) && (events.%Get(i).payload.lastRunAt '= "") && 'events.%Get(i).payload.stopped, "event "_(i + 1)_" is a run of the row")
		}
	}
	If events.%Size() '< 2 {
		Set payload = events.%Get(events.%Size() - 1).payload
		Do $$$AssertEquals(payload.ref_"|"_payload.stopped, started.Ref_"|1", "the last event has the same Ref and stopped true")
		Do $$$AssertEquals(payload.%GetTypeOf("stopped"), "boolean", "and stopped is a JSON boolean, which the page's filter tests with ===")
		Do $$$AssertEquals(payload.namespace_"|"_payload.production_"|"_payload.displayName, ..#ORDERS_"|"_..#ORDERSPRODUCTION_"|Orders", "and the watch's name")
		Do $$$AssertTrue(events.%Get(events.%Size() - 1).seq > events.%Get(0).seq, "after the first")
	}
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(started.Ref), 0, "the row is gone")
}

/// The finding Items that Checks sent to Intake in the Tick's trace session for the owner, in order, as a dynamic array of {itemId, catalogKey, slots, channel,
/// provenance, superSession (of the header)}.
ClassMethod Findings(tickSession As %String, owner As %String) As %DynamicArray [ Private ]
{
	Set found = []
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(tickSession), 1, ..#CHECKS, "Intake")
	For i = 0:1:sent.%Size() - 1 {
		If sent.%Get(i).bodyClass '= "OcuTalon.Msg.Item" Continue
		Set body = ##class(OcuTalon.Msg.Item).%OpenId(sent.%Get(i).bodyId)
		If $IsObject(body) && (body.SessionRef = owner) {
			Do found.%Push({"itemId": (body.ItemId), "catalogKey": (body.CatalogKey), "slots": (body.Slots), "channel": (body.Channel), "provenance": (body.Provenance), "superSession": (sent.%Get(i).superSession)})
		}
	}
	Quit found
}

/// The ItemDecision that Intake sent to OutcomeRouter for the item in the Tick's session, as {catalogKey, slots}, waiting up to WAITDIAGNOSIS seconds for it;
/// "" with a failed assertion when there is none.
Method Decision(tickSession As %String, itemId As %String) As %DynamicObject [ Private ]
{
	Set end = $ZHorolog + ..#WAITDIAGNOSIS
	Set found = ""
	For {
		Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(tickSession), 1, "Intake", "OutcomeRouter")
		For i = 0:1:sent.%Size() - 1 {
			If sent.%Get(i).bodyClass '= "OcuTalon.Msg.ItemDecision" Continue
			Set body = ##class(OcuTalon.Msg.ItemDecision).%OpenId(sent.%Get(i).bodyId)
			If $IsObject(body) && (body.ItemId = itemId) Set found = {"catalogKey": (body.CatalogKey), "slots": (body.Slots)}
		}
		If $IsObject(found) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertTrue($IsObject(found), "Intake sent OutcomeRouter the ItemDecision of the item")
	Quit found
}

/// --- helpers ---
/// The check events of the session's stream once its stop event (stopped true) is there, or after 20 seconds without it.
Method WaitStopped(session As %String) As %DynamicArray [ Private ]
{
	Set end = $ZHorolog + 20
	For {
		Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "check")
		Set stopped = 0
		For i = 0:1:events.%Size() - 1 {
			If events.%Get(i).payload.stopped Set stopped = 1
		}
		If stopped || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit events
}

/// The closeQuiet requests from Checks to IncidentManager whose IncidentCommand names the incident, in any session, as a dynamic array of {sessionId,
/// superSession}.
ClassMethod QuietRequests(incident As %String) As %DynamicArray [ Private ]
{
	Set found = []
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT SessionId, SuperSession, MessageBodyId FROM Ens.MessageHeader WHERE Type = 1 AND SourceConfigName = ? AND TargetConfigName = ? AND MessageBodyClassName = ? ORDER BY ID", ..#CHECKS, ..#MANAGER, "OcuTalon.Msg.IncidentCommand")
	While rs.%Next() {
		Set command = ##class(OcuTalon.Msg.IncidentCommand).%OpenId(rs.%GetData(3))
		If $IsObject(command) && (command.IncidentRef = incident) && (command.Verb = ##class(OcuTalon.Watch.Transitions).#CLOSEQUIET) {
			Do found.%Push({"sessionId": (rs.%GetData(1)), "superSession": (rs.%GetData(2))})
		}
	}
	Quit found
}

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

/// A fixture incident of the session on Orders, noticed, resolved, with the last failure at the time; its Ref (removed with the test's rows).
Method Resolved(session As %String, lastAt As %String) As %String [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Incident(session, ##class(OcuTalon.Data.Time).NowUtc(), ..#ORDERS, ..#ORDERSPRODUCTION, {"State": "resolved", "OpenVariant": "", "LastAt": (lastAt)})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

}
