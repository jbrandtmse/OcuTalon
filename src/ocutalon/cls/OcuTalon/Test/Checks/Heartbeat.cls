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
///     stopped, the Tick a minute later (run more than a second after the stop) sends exactly one Item from Checks to Intake for the session and the Tick two minutes
///     later none: key watch.productionStopped, production "Orders", a time between just before the stop and just after it (IRIS's own stop time, not the run's), the
///     session's TraceRef as SuperSession, in a trace session of its own (AD-26). Intake sends one ItemDecision to OutcomeRouter in that session with the same CatalogKey
///     and Slots (Integration AC); (QA) the Item's only route is Checks to Intake and its only decision is Intake to OutcomeRouter (Routes). Orders is started again;
///   - TestDisabledItemIsReportedOnce (Story 30.4; AC 1, AC 2; the matrix row 13): the session's fixture watch has the CI mock's marker check-finding-tell-now in its display name; the
///     baseline Tick, then OrdersToWarehouse disabled in OCUORDERS and two Ticks: the first sends exactly one watch.itemDisabled Item for it and the second none, and the
///     session's web chat gets one tell-now notification whose text is the catalog's rendering of that key and those slots, its second line "Why now: you asked me to
///     watch the {name} production." (Integration AC). The item is enabled again after the test, also after a failure (Case.SetItemEnabled, OnAfterOneTest);
///   - TestQuietClose (AC 3): a real Tick, before the test's own, makes the real IncidentManager close a noticed resolved incident whose last failure is 16 minutes
///     old (closed with ClosedAt, one incident event closed). Across all sessions of Checks exactly one closeQuiet names it, and it goes in a session whose first
///     request is a Tick to Checks, with the owner's TraceRef as SuperSession; the test's own Tick sends none. The 14 minute incident stays resolved;
///   - TestStartAndStop (AC 4): a StartWatch and a StopWatch through the WatchOps item put check events on the session's stream, in order: FromRow of the new
///     row with no run, then the same Ref with stopped true. WatchOps makes the row due at once, so a real Tick may run it between the two: where an event
///     carries lastRunAt, the first event names the row, each middle event is a run of it and the last is the stop.
///   - TestBeatNowIsAnswered (Stories 39.1 and 39.3; Integration AC; AD-18): a BeatNow that HeartbeatIn sends Checks synchronously is answered OK with a CommandResult whose Outcome is the code "empty" (the
///     person has no checklist), and the service's session holds no message whose target is Intake and no request whose source is Checks: a held beat sends nothing.
///   - TestBeatReachesIntake (Story 39.3; AC 2, AC 5; Integration AC; FR-64, AD-18, AD-26): a person with a checklist that holds a mock marker has a row due at T0; the Tick at T0 sends one Item from
///     Checks to Intake (channel heartbeat, untrusted, the subject and the checklist as text) in a trace session of its own with the TraceRef as SuperSession; Intake records a Decision for it,
///     the CI mock's log holds exactly one request with the marker, and the Tick a minute later records the outcome, cost, decision and trace session on the row.
///   - TestAnHourOfTicks (Story 39.3; AC 5): an hour of Ticks, a minute apart, for a person on a 30-minute interval whose checklist changed since the last ignore: one request at the first Tick,
///     none at the 59 after it (the second due beat, at 30 minutes, is unchanged since the Ignore and is skipped), and the hour holds one request.
///   - TestBeatNowReachesIntake (Story 39.3; AC 4; Integration AC; AD-18): through the real seam, with the key and the cap read by Beat, a BeatNow for a person with a checklist, unchanged since the
///     last ignore, answers sent with the ItemId as Ref; the Item reaches Intake, which records a Decision, and the CI mock's log holds exactly one request. A second BeatNow 119 seconds later answers
///     cooldown with availableAt, sends nothing and makes no request.
/// The tests of the beat start with the preconditions that make a beat run: the TriageAgent's key is present (the entries point at the CI mock key variable) and the daily cap is not reached.
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
	Set floor = ..Top("Ens.MessageHeader", $Namespace)
	Set base = ..Tick(tickAt)
	If base = "" Quit
	Do $$$AssertEquals($Extract(..Check(ref).Reported, 1, 12), "{""stopped"":0", "the Tick at NextDueAt records the baseline: Orders runs")
	Do $$$AssertEquals(..Findings(trace, session, floor).%Size(), 0, "and sends no Item")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	If '..StopOrders() Quit
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	// the run comes more than a second after the stop, so that only IRIS's own stop time lies between before and after
	Hang 1.1
	Set next = ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(tickAt, 60))
	Set floor = ..Top("Ens.MessageHeader", $Namespace)
	Set first = ..Tick(next)
	If first = "" Quit
	Set items = ..Findings(trace, session, floor)
	Set later = ..Top("Ens.MessageHeader", $Namespace)
	Set last = ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(next, 60))
	Set second = ..Tick(last)
	If second = "" Quit
	Set again = ..Findings(trace, session, later)
	Do $$$AssertEquals(items.%Size()_"|"_again.%Size(), "1|0", "the first Tick after the stop sends one Item to Intake for the session, and the second sends none: "_items.%Size()_"|"_again.%Size())
	If items.%Size() = 1 {
		Set item = items.%Get(0)
		Set slots = {}.%FromJSON(item.slots)
		Do $$$AssertEquals(item.catalogKey_"|"_slots.production, "watch.productionStopped|Orders", "its key and production")
		Do $$$AssertTrue('(before ] slots.time) && '(slots.time ] after), "and its time is IRIS's stop time, between just before and just after the stop (the run came later): "_before_" "_slots.time_" "_after)
		Do $$$AssertEquals(item.channel_"|"_item.provenance_"|"_item.superSession, "system|untrusted|"_trace, "from the system channel, untrusted, with the session's TraceRef as SuperSession")
		Do $$$AssertTrue((item.sessionId = item.headerId) && (item.sessionId '= first), "in a trace session of its own, not the Tick's (AD-26): "_item.sessionId_" (Tick "_first_")")
		Set decision = ..Decision(item.sessionId, item.itemId)
		If $IsObject(decision) Do $$$AssertEquals(decision.catalogKey_"|"_decision.slots, item.catalogKey_"|"_item.slots, "Intake sent OutcomeRouter one ItemDecision in the item's session with the same CatalogKey and Slots")
		Set routes = ..Routes(trace, floor, item.itemId)
		Do $$$AssertEquals(routes, "Item Checks>Intake|ItemDecision Intake>OutcomeRouter", "(QA) the Item goes to Intake only, once, and Intake sends the one ItemDecision to OutcomeRouter: nothing goes from Checks to OutcomeRouter or Notify: "_routes)
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
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set tickAt = ..Check(ref).NextDueAt
	Set floor = ..Top("Ens.MessageHeader", $Namespace)
	Set base = ..Tick(tickAt)
	If base = "" Quit
	Do $$$AssertEquals($Extract(..Check(ref).Reported, 1, 12), "{""stopped"":0", "the Tick at NextDueAt records the baseline")
	Do $$$AssertEquals(..Findings(trace, session, floor).%Size(), 0, "and sends no Item")
	Do $$$AssertStatusOK(..SetItemEnabled(0), ..#ITEMNAME_" is disabled in "_..#ORDERS)
	Set next = ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(tickAt, 60))
	Set floor = ..Top("Ens.MessageHeader", $Namespace)
	Set first = ..Tick(next)
	If first = "" Quit
	Set items = ..Findings(trace, session, floor)
	Set later = ..Top("Ens.MessageHeader", $Namespace)
	Set last = ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(next, 60))
	Set second = ..Tick(last)
	If second = "" Quit
	Set again = ..Findings(trace, session, later)
	Do $$$AssertEquals(items.%Size()_"|"_again.%Size(), "1|0", "exactly one Item goes to Intake for the disabled item, in the first Tick after it: "_items.%Size()_"|"_again.%Size())
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

/// The finding Items that Checks sent to Intake for the owner, with the owner's TraceRef (trace) as SuperSession, in the headers above the floor (a header id), in
/// order, as a dynamic array of {itemId, catalogKey, slots, channel, provenance, subject, text, and of the header superSession, sessionId and headerId}. Each ItemId joins
/// ItemIds, so that OnAfterOneTest removes the decision and the usage that it made.
Method Findings(trace As %String, owner As %String, floor As %Integer) As %DynamicArray [ Private ]
{
	Set found = []
	Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).Headers(trace), 1, ..#CHECKS, "Intake")
	For i = 0:1:sent.%Size() - 1 {
		Set header = sent.%Get(i)
		If (header.id '> floor) || (header.bodyClass '= "OcuTalon.Msg.Item") Continue
		Set body = ##class(OcuTalon.Msg.Item).%OpenId(header.bodyId)
		If $IsObject(body) && (body.SessionRef = owner) {
			Do found.%Push({"itemId": (body.ItemId), "catalogKey": (body.CatalogKey), "slots": (body.Slots), "channel": (body.Channel), "provenance": (body.Provenance), "subject": (body.Subject), "text": (body.Text), "superSession": (header.superSession), "sessionId": (header.sessionId), "headerId": (header.id)})
			If '$ListFind(..ItemIds, body.ItemId) Set ..ItemIds = ..ItemIds_$ListBuild(body.ItemId)
		}
	}
	Quit found
}

/// (QA) Where the item travelled in its owner's trace (trace, the TraceRef) above the floor: one entry "Item source>target" per request from Checks or Intake
/// that carried the Item with the id, and "ItemDecision source>target" per such request that carried its decision, in order, separated by "|". OutcomeRouter's
/// own forward of the decision (to DigestStore for a digest) is the router's routing, not the item's.
Method Routes(trace As %String, floor As %Integer, itemId As %String) As %String [ Private ]
{
	Set routes = ""
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	For i = 0:1:headers.%Size() - 1 {
		Set header = headers.%Get(i)
		If (header.type '= 1) || (header.id '> floor) Continue
		If (header.source '= ..#CHECKS) && (header.source '= "Intake") Continue
		If (header.bodyClass '= "OcuTalon.Msg.Item") && (header.bodyClass '= "OcuTalon.Msg.ItemDecision") Continue
		Set body = $ClassMethod(header.bodyClass, "%OpenId", header.bodyId)
		If $IsObject(body) && (body.ItemId = itemId) {
			Set routes = routes_$Select(routes = "": "", 1: "|")_$Piece(header.bodyClass, ".", 3)_" "_header.source_">"_header.target
		}
	}
	Quit routes
}

/// The ItemDecision that Intake sent to OutcomeRouter for the item in the session (the item's own trace session, which Intake keeps), as {catalogKey, slots},
/// waiting up to WAITDIAGNOSIS seconds for it; "" with a failed assertion when there is none.
Method Decision(session As %String, itemId As %String) As %DynamicObject [ Private ]
{
	Set end = $ZHorolog + ..#WAITDIAGNOSIS
	Set found = ""
	For {
		Set sent = ##class(OcuTalon.Test.Data.Fixture).Between(##class(OcuTalon.Test.Data.Fixture).SessionHeaders(session), 1, "Intake", "OutcomeRouter")
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

/// The preconditions of a beat: 1 when the entries of the runners point at the CI mock key variable, the TriageAgent's key is present and today's cap is not reached;
/// otherwise a failed assertion that names the precondition, and 0.
Method Beatable() As %Boolean [ Private ]
{
	If '..PointKeys() Quit 0
	Set keyed = ##class(OcuTalon.Bridge.Keys).Status(##class(OcuTalon.Checks.Beat).#AGENT)
	Do $$$AssertEquals(keyed, 1, "precondition: the TriageAgent's key is present (Bridge.Keys.Status)")
	Set capped = ##class(OcuTalon.Bridge.Budget).State().capped
	Do $$$AssertEquals(+capped, 0, "precondition: the daily cost cap is not reached (Bridge.Budget.State)")
	Quit (keyed = 1) && 'capped
}

/// The first minute that is two days ahead of now, as a UTC stamp: no real Tick reaches a row due then.
ClassMethod Due() As %String [ Private ]
{
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Quit $Extract(##class(OcuTalon.Data.Time).AddSeconds(now, 172800), 1, 17)_"00Z"
}

/// The person's HeartbeatBeat row, due at the time and with the quiet key, made before the settings (on, a 30 minute interval, all day, the checklist), so that a real Tick
/// does not run it first.
Method SeedBeat(session As %String, dueAt As %String, checklist As %String, quietKey As %String) [ Private ]
{
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).%New()
	Set row.SessionRef = session
	Set row.NextDueAt = dueAt
	Set row.LastQuietKey = quietKey
	Do $$$AssertStatusOK(row.%Save(), "the person's row is made, due at "_dueAt)
	For name = "on", "interval", "from", "to", "checklist" {
		Set value = $Case(name, "on": 1, "interval": 30, "checklist": checklist, : "")
		Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set(##class(OcuTalon.Checks.Beat).SettingKey(session, name), value), "the setting "_name_" is written")
	}
}

/// The person's HeartbeatBeat row as stored now.
ClassMethod Beat(session As %String) As OcuTalon.Data.HeartbeatBeat [ Private ]
{
	Set row = ##class(OcuTalon.Data.HeartbeatBeat).SessionRefIndexOpen(session)
	If $IsObject(row) Do row.%Reload()
	Quit row
}

/// The person's decision for the beat Item (Kind decide), waiting up to WAITDIAGNOSIS seconds; "" when there is none.
Method WaitDecision(itemId As %String, session As %String) As OcuTalon.Bridge.Data.Decision [ Private ]
{
	Set end = $ZHorolog + ..#WAITDIAGNOSIS
	For {
		Set decision = ##class(OcuTalon.Data.Ownership).DecisionOfItem(itemId, session, .sc)
		If $IsObject(decision) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit decision
}

/// The number of requests that the CI mock logged after the mark and that carry the person's marker (decide-ignore:<the session's Ref>).
ClassMethod Marked(mark As %Integer, session As %String) As %Integer [ Private ]
{
	Set count = 0
	If $$$ISERR(##class(OcuTalon.Test.Contract.Mock).LogSince(mark, .entries)) Quit -1
	Set iterator = entries.%GetIterator()
	While iterator.%GetNext(, .entry) {
		If (entry.marker '= "") && $Find(entry.marker, session) Set count = count + 1
	}
	Quit count
}

Method OnAfterOneTest(testname As %String) As %Status
{
	For i = 1:1:$Length(..Sessions, ",") {
		If $Piece(..Sessions, ",", i) '= "" Do ##class(OcuTalon.Test.Checks.Beat).Forget($Piece(..Sessions, ",", i))
	}
	Quit ##super(testname)
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

Method TestBeatNowIsAnswered()
{
	If '..Ready() Quit
	Set session = ..Session("beatnow")
	Do $$$AssertStatusOK(##class(Ens.Director).CreateBusinessService(..#HEARTBEAT, .service), "the "_..#HEARTBEAT_" service is created")
	If '$IsObject(service) Quit
	Set request = ##class(OcuTalon.Checks.Msg.BeatNow).%New()
	Set request.SessionRef = session
	Set request.RequestedAt = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK(service.SendRequestSync(..#CHECKS, request, .response, ..#TICKWAIT), "Checks answers the BeatNow OK")
	Do $$$AssertTrue($IsObject($Get(response)) && response.%IsA("OcuTalon.Msg.CommandResult"), "with a CommandResult")
	If $IsObject($Get(response)) Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref, "0|empty|", "whose outcome is empty: the person has no checklist")
	Set id = service.%SessionId
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ? AND TargetConfigName = ?", id, ..#CHECKS)
	Do rs.%Next()
	Do $$$AssertEquals(rs.%GetData(1), 1, "the session holds the one request to Checks")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ? AND TargetConfigName = 'Intake'", id)
	Do rs.%Next()
	Do $$$AssertEquals(rs.%GetData(1), 0, "no message of the session is for Intake")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId = ? AND Type = 1 AND SourceConfigName = ?", id, ..#CHECKS)
	Do rs.%Next()
	Do $$$AssertEquals(rs.%GetData(1), 0, "and Checks sent no request")
}

Method TestBeatReachesIntake()
{
	If '..Ready() Quit
	If '..Beatable() Quit
	Set session = ..Session("beatintake")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set t0 = ..Due()
	Set text = "zz beat [[mock:decide-ignore:"_session_"]]"
	Do ..SeedBeat(session, t0, text, "")
	Set floor = ..Top("Ens.MessageHeader", $Namespace)
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set tick = ..Tick(t0)
	If tick = "" Quit
	Set items = ..Findings(trace, session, floor)
	Do $$$AssertEquals(items.%Size(), 1, "the Tick at T0 sends one Item from Checks to Intake for the person")
	If items.%Size() '= 1 Quit
	Set item = items.%Get(0)
	Do $$$AssertEquals(item.channel_"|"_item.provenance_"|"_item.subject_"|"_item.text, "heartbeat|untrusted|Heartbeat check-in|"_text, "a heartbeat Item, untrusted, with the subject and the checklist as its text")
	Do $$$AssertEquals(item.superSession, trace, "with the person's TraceRef as SuperSession")
	Do $$$AssertTrue((item.sessionId = item.headerId) && (item.sessionId '= tick), "in a trace session of its own, not the Tick's (AD-26): "_item.sessionId_" (Tick "_tick_")")
	Set decision = ..WaitDecision(item.itemId, session)
	Do $$$AssertTrue($IsObject(decision), "Intake records a Decision for the Item")
	Set marked = ..Marked(mark, session)
	Do $$$AssertEquals(marked, 1, "and the CI mock's log holds exactly one request with the marker")
	If '$IsObject(decision) Quit
	Set next = ##class(OcuTalon.Data.Time).AddSeconds(t0, 60)
	If ..Tick(next) = "" Quit
	Set row = ..Beat(session)
	Do $$$AssertEquals(row.LastOutcome_"|"_row.LastFallback_"|"_row.LastDecisionRef_"|"_row.LastTraceSessionId, decision.Outcome_"|0|"_decision.Ref_"|"_decision.TraceSessionId, "the Tick a minute later records the decision on the row")
	Do $$$AssertEquals(decision.Outcome, "ignore", "which is the mock's ignore")
	Do $$$AssertEquals(+row.LastCostUSD, +decision.CostUSD, "with its cost")
	Do $$$AssertEquals(row.LastItemId_"|"_row.NextDueAt, item.itemId_"|"_##class(OcuTalon.Data.Time).AddSeconds(t0, 1800), "and the row still names the beat and its next due time")
}

Method TestBeatNowReachesIntake()
{
	If '..Ready() Quit
	If '..Beatable() Quit
	Set session = ..Session("beatnowintake")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set t0 = ..Due()
	Set text = "zz run now [[mock:decide-ignore:"_session_"]]"
	Do ..SeedBeat(session, ##class(OcuTalon.Data.Time).AddSeconds(t0, 86400), text, ##class(OcuTalon.Checks.Beat).Key(text))
	Do $$$AssertStatusOK(##class(Ens.Director).CreateBusinessService(..#HEARTBEAT, .service), "the "_..#HEARTBEAT_" service is created")
	If '$IsObject(service) Quit
	Set floor = ..Top("Ens.MessageHeader", $Namespace)
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set request = ##class(OcuTalon.Checks.Msg.BeatNow).%New()
	Set request.SessionRef = session
	Set request.RequestedAt = t0
	Do $$$AssertStatusOK(service.SendRequestSync(..#CHECKS, request, .response, ..#TICKWAIT), "Checks answers the BeatNow OK")
	If '$IsObject($Get(response)) Do $$$AssertTrue(0, "with a CommandResult") Quit
	Set items = ..Findings(trace, session, floor)
	Do $$$AssertEquals(items.%Size(), 1, "the BeatNow sends one Item from Checks to Intake")
	If items.%Size() '= 1 Quit
	Set item = items.%Get(0)
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref_"|"_response.Data, "1|sent|"_item.itemId_"|", "the answer is sent, with the ItemId as Ref")
	Do $$$AssertEquals(item.channel_"|"_item.provenance_"|"_item.text_"|"_item.superSession, "heartbeat|untrusted|"_text_"|"_trace, "a heartbeat Item with the checklist, in the person's trace")
	Set decision = ..WaitDecision(item.itemId, session)
	Do $$$AssertTrue($IsObject(decision), "Intake records a Decision for the Item")
	Do $$$AssertEquals(..Marked(mark, session), 1, "and the CI mock's log holds exactly one request with the marker")
	Set again = ##class(OcuTalon.Checks.Msg.BeatNow).%New()
	Set again.SessionRef = session
	Set again.RequestedAt = ##class(OcuTalon.Data.Time).AddSeconds(t0, 119)
	Do $$$AssertStatusOK(service.SendRequestSync(..#CHECKS, again, .response, ..#TICKWAIT), "Checks answers a second BeatNow OK")
	If '$IsObject($Get(response)) Do $$$AssertTrue(0, "with a CommandResult") Quit
	Do $$$AssertEquals(response.Ok_"|"_response.Outcome_"|"_response.Ref_"|"_response.Data, "0|cooldown||"_{"availableAt": (##class(OcuTalon.Data.Time).AddSeconds(t0, 120))}.%ToJSON(), "119 seconds later the answer is cooldown, with the time it may run")
	Do $$$AssertEquals(..Findings(trace, session, floor).%Size(), 1, "and no further Item goes")
	Do $$$AssertEquals(..Marked(mark, session), 1, "and no further request")
}

Method TestAnHourOfTicks()
{
	If '..Ready() Quit
	If '..Beatable() Quit
	Set session = ..Session("beathour")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set t0 = ..Due()
	Set text = "zz an hour [[mock:decide-ignore:"_session_"]]"
	Do ..SeedBeat(session, t0, text, ##class(OcuTalon.Checks.Beat).Key("zz an earlier checklist"))
	Set floor = ..Top("Ens.MessageHeader", $Namespace)
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	If ..Tick(t0) = "" Quit
	Set items = ..Findings(trace, session, floor)
	Do $$$AssertEquals(items.%Size(), 1, "the Tick at T0, with a checklist that changed since the last ignore, sends one Item")
	If items.%Size() '= 1 Quit
	Set decision = ..WaitDecision(items.%Get(0).itemId, session)
	Do $$$AssertTrue($IsObject(decision), "and Intake records its Decision")
	Set first = ..Marked(mark, session)
	Do $$$AssertEquals(first, 1, "which is one request to the mock")
	If '$IsObject(decision) Quit
	Set mark = ##class(OcuTalon.Test.Contract.Mock).LogMark()
	Set floor = ..Top("Ens.MessageHeader", $Namespace)
	Set failed = 0
	For minute = 1:1:59 {
		If ..Tick(##class(OcuTalon.Data.Time).AddSeconds(t0, 60 * minute)) = "" Set failed = 1 Quit
		If minute = 30 {
			Set row = ..Beat(session)
			Do $$$AssertEquals(row.LastSkipAt_"|"_row.LastSkipReason, ##class(OcuTalon.Data.Time).AddSeconds(t0, 1800)_"|unchanged", "at 30 minutes the due beat is unchanged since the Ignore and is skipped")
		}
	}
	If failed Quit
	Do $$$AssertEquals(..Marked(mark, session), 0, "the 59 Ticks after the first make no request")
	Do $$$AssertEquals(..Findings(trace, session, floor).%Size(), 0, "and send no further Item")
	Do $$$AssertEquals(..Beat(session).NextDueAt, ##class(OcuTalon.Data.Time).AddSeconds(t0, 3600), "the next beat is due an hour after T0")
	Do $$$AssertEquals(first + ..Marked(mark, session), 1, "the hour holds one request")
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
