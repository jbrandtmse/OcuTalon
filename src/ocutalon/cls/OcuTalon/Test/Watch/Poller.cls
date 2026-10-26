/// Tests of OcuTalon.Watch.FailurePoller and of the failure batches that it sends to IncidentManager (Story 5.2; AD-4, AD-5, AD-15, AD-26). THEY RUN IN THROWAWAY
/// STACKS AND IN CI ONLY (Rule 21), with demo mode on, through Test.Watch.Case, over the RUNNING production: its FailurePoller job picks up the failures that
/// the tests make in OCUORDERS (failing Orders orders, a header moved to the error status, event-log rows with no session) and sends FailureBatch
/// messages to the item IncidentManager, which the tests read as plain objects (Case.Batches). They fail with the reason where OCUORDERS or the production is
/// missing. A test waits at most 30 seconds for a batch, polling every half second: a test bound, not NFR-7 (the 15 second limit is measured in the
/// clean-machine rehearsal). "No further batch" waits 7 seconds, two polls. Every failure, header, log row and batch of a test is removed after it.
///   - TestSessionTaggedAndUntagged (rows Session-tagged, Untagged, Fix copy; AC 1): three failing orders tagged with the TraceRef of session A, which watches
///     Orders, and two untagged ones arrive; the batches cover those five failures once, A's under A's Ref with SuperSession A's TraceRef, the others under
///     instance with an empty SuperSession, each its own trace session, each Completed (Status 9) at IncidentManager, every failure a header failure of
///     OrdersFromPartner with the error's own sentence, its header id and its time to the second, and no batch follows (the event-log rows of the failed
///     headers are no failures of their own);
///   - TestScopesInOnePoll: A-tagged, B-tagged (B watches nothing) and untagged failures that wait while the poller is stopped arrive in one poll: three batches,
///     one per scope, with the same PolledAt, and B's failures are B's;
///   - TestAgainAfterRestart: the poller is stopped, two failures arrive and the poller is started: those two are batched once, and the earlier one is not
///     batched again;
///   - TestLateError: a header made earlier enters the error status after a later one was batched, and is batched once, later (a mark by header id would skip it);
///   - TestWatchAfterFailures: failures before the production's first watch are not batched, the failure after it is;
///   - TestUnreadable: with Read on the Orders data database removed from the service role nothing is read, no batch is sent and the mark is as it was; with
///     the grant back the failures that arrived are batched once;
///   - TestNotOwnProduction: a watch row for OCUTALON and the Orders production, with OCUTALON readable and a failed header in OCUTALON, reads nothing and makes no
///     mark;
///   - TestHeaderlessLog (row Headerless log row): an event-log row of type 2 and one of type 6 with no session are one failure each, of kind error and
///     alert, with the ConfigName as item, under instance;
///   - TestReadErrorWarns (row Read or send error): a read that throws gives one Type 3 warning that names the production, no error row, the mark as it was and an OK answer;
///   - TestSendErrorWarns (row Read or send error): with the probe's send failing, a poll of three failures gives one Type 3 warning that names the production and
///     the cause, an OK answer, no mark and nothing sent; with the send back the same three are sent once;
///   - TestFlood (row Flood): two sessions watch a production that only the probe reads; 600 failures that the probe's read gives (on a production that only the probe reads) are sent 500 in the first poll and the other 100
///     in the second, each once, and a third poll sends nothing and leaves the mark.
Class OcuTalon.Test.Watch.Poller Extends OcuTalon.Test.Watch.Case
{

Parameter POLLERCLASS = "OcuTalon.Watch.FailurePoller";

Parameter PROBE = "OcuTalon.Test.Watch.PollerProbe";

/// The production that only the probe reads (no running production has it, so the running poller answers not_current for it), the first header id minus
/// one of its fed failures and the stamp the feed counts its seconds from.
Parameter FLOODPRODUCTION = "Zz.FloodProduction";

Parameter FLOODFIRST = 900000;

Parameter FLOODSTART = "2026-10-25 08:00:00.000";

Method TestSessionTaggedAndUntagged()
{
	If '..Ready() Quit
	Set a = ..Session("tag")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	Set since = ..Since()
	If '..Fail(3, trace) Quit
	If '..Fail(2, "") Quit
	Set failed = ..WaitFailed(5)
	Do ..Split(failed, trace, .tagged, .rest)
	Do $$$AssertEquals($Length(tagged, ","), 3, "three of the failed headers carry A's TraceRef")
	Set batches = ..WaitBatched(since, 5)
	Do $$$AssertEquals(..Count(batches), 5, "the batches hold five failures")
	Do $$$AssertEquals(..Ids(batches, a), tagged, "A's scope holds the three tagged headers, once each")
	Do $$$AssertEquals(..Ids(batches, "instance"), rest, "the instance scope holds the two untagged ones, once each")
	Set sessions = ""
	Set iterator = batches.%GetIterator()
	While iterator.%GetNext(, .batch) {
		Do $$$AssertEquals(batch.status, 9, "batch "_batch.id_" is Completed at IncidentManager")
		Do $$$AssertEquals(batch.namespace_"|"_batch.production, ..#ORDERS_"|"_..#ORDERSPRODUCTION, "batch "_batch.id_" names OCUORDERS and the Orders production")
		Do $$$AssertTrue((batch.ownerRef = a) || (batch.ownerRef = "instance"), "its OwnerRef is A's Ref or instance: "_batch.ownerRef)
		Do $$$AssertEquals(batch.superSession, $Select(batch.ownerRef = a: trace, 1: ""), "its SuperSession is the scope's TraceRef, empty for instance")
		Do $$$AssertTrue(batch.sessionId '= "", "it has a trace session of its own")
		Do $$$AssertNotTrue($Data(sessions(batch.sessionId)), "that no other batch shares")
		Set sessions(batch.sessionId) = ""
		Do $$$AssertTrue(batch.polledAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "PolledAt is UTC to the second: "_batch.polledAt)
		Set at = batch.failures.%GetIterator()
		While at.%GetNext(, .failure) {
			Do $$$AssertEquals(failure.kind_"|"_failure.item, "header|OrdersFromPartner", "failure "_failure.headerId_" is a header failure of OrdersFromPartner")
			Do $$$AssertEquals(failure.errorText, ..#ORDERDATETEXT, "with the error's own sentence")
			Do $$$AssertTrue(failure.failedAt ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "FailedAt is UTC to the second: "_failure.failedAt)
			Do $$$AssertTrue((failure.sessionId '= "") && (failure.bodyClass '= "") && (failure.source '= "") && (failure.logId '= ""), "and it carries the session, the body class, the sender and the log row of the error")
		}
	}
	Do ..Settle()
	Set later = ..Batches(since)
	Do $$$AssertEquals(later.%Size(), batches.%Size(), "no batch follows within two polls")
	Do $$$AssertEquals(..Count(later), 5, "and still five failures were batched")
}

Method TestScopesInOnePoll()
{
	If '..Ready() Quit
	Set a = ..Session("one")
	Set b = ..Session("two")
	Set traceA = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set traceB = ##class(OcuTalon.Data.Session).RefIndexOpen(b).TraceRef
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	Set since = ..Since()
	If '..StopPoller() Quit
	If '..Fail(2, traceA) Quit
	If '..Fail(2, traceB) Quit
	If '..Fail(2, "") Quit
	Set failed = ..WaitFailed(6)
	If '..StartPoller() Quit
	Set batches = ..WaitBatched(since, 6)
	Do $$$AssertEquals(batches.%Size(), 3, "three batches: one per scope")
	Do $$$AssertEquals(..Count(batches, a), 2, "A's scope holds two failures")
	Do $$$AssertEquals(..Count(batches, b), 2, "B's scope holds two failures, though B watches nothing")
	Do $$$AssertEquals(..Count(batches, "instance"), 2, "the instance scope holds two")
	Set polls = ""
	Set iterator = batches.%GetIterator()
	While iterator.%GetNext(, .batch) {
		If '$Data(polls(batch.polledAt)) Set polls(batch.polledAt) = 0
		Set polls(batch.polledAt) = polls(batch.polledAt) + 1
		Do $$$AssertEquals(batch.superSession, $Case(batch.ownerRef, a: traceA, b: traceB, : ""), "batch "_batch.id_" is tagged with its scope's TraceRef")
	}
	Do $$$AssertEquals($Order(polls("")) '= "", 1, "the batches carry a PolledAt")
	Set first = $Order(polls(""))
	Do $$$AssertEquals($Order(polls(first)), "", "all three share one PolledAt")
	Do $$$AssertEquals($Get(polls(first)), 3, "so they are one poll's batches")
	Do $$$AssertEquals(..Ids(batches, a)_"|"_..Ids(batches, b)_"|"_..Ids(batches, "instance"), ..IdsOf(failed, traceA)_"|"_..IdsOf(failed, traceB)_"|"_..HeaderIds(..Untagged(failed, traceA, traceB)), "each scope holds its own headers")
}

Method TestAgainAfterRestart()
{
	If '..Ready() Quit
	Set a = ..Session("restart")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	Set since = ..Since()
	If '..Fail(1, trace) Quit
	Do ..WaitFailed(1)
	Set first = ..WaitBatched(since, 1, a)
	Do $$$AssertEquals(..Count(first, a), 1, "control: the first failure is batched")
	Set seenBatches = first.%Size()
	If '..StopPoller() Quit
	If '..Fail(2, trace) Quit
	Set failed = ..WaitFailed(3)
	Do $$$AssertEquals(..Batches(since).%Size(), seenBatches, "nothing is batched while the poller is stopped")
	If '..StartPoller() Quit
	Set batches = ..WaitBatched(since, 3, a)
	Do $$$AssertEquals(..Ids(batches, a), ..IdsOf(failed, trace), "all three failures are batched, each once: the two new ones after the start, the first not again")
	Do $$$AssertEquals(batches.%Size(), seenBatches + 1, "the two arrive in one batch")
	Do ..Settle()
	Do $$$AssertEquals(..Batches(since).%Size(), batches.%Size(), "and no batch follows")
}

Method TestLateError()
{
	If '..Ready() Quit
	Set a = ..Session("late")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	Set since = ..Since()
	Set late = ..LateHeader(trace)
	Do $$$AssertTrue(late '= "", "a header is made in "_..#ORDERS_" that has not failed")
	If '..Fail(1, trace) Quit
	Set failed = ..WaitFailed(1)
	Set first = ..WaitBatched(since, 1, a)
	Do $$$AssertEquals(..Ids(first, a), ..HeaderIds(failed), "the failed order is batched")
	Do $$$AssertTrue(late < failed.%Get(0).id, "and the header made earlier has the lower id")
	Do $$$AssertStatusOK(..LateError(late), "the header made earlier enters the error status")
	Set batches = ..WaitBatched(since, 2, a)
	Do $$$AssertEquals(..Ids(batches, a), $Select(late < failed.%Get(0).id: late_",", 1: "")_failed.%Get(0).id, "it is batched once, later, and the first one is not batched again")
	Do $$$AssertEquals(..Count(..Batches(since)), 2, "and no further failure is batched")
}

Method TestWatchAfterFailures()
{
	If '..Ready() Quit
	Set a = ..Session("after")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..ClearMark(..#ORDERS)
	Set since = ..Since()
	If '..Fail(2, "") Quit
	Do ..WaitFailed(2)
	Hang 1.2
	Do ..Watch(a)
	If '..Fail(1, trace) Quit
	Set failed = ..WaitFailed(3)
	Set batches = ..WaitBatched(since, 1)
	Do ..Settle()
	Set batches = ..Batches(since)
	Do $$$AssertEquals(..Ids(batches), ..IdsOf(failed, trace), "only the failure after the watch is batched")
	Do $$$AssertEquals(..Count(batches), 1, "the two failures before it are not")
}

Method TestUnreadable()
{
	If '..Ready() Quit
	Set a = ..Session("unread")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	Set since = ..Since()
	If '..Fail(1, trace) Quit
	Do ..WaitFailed(1)
	Do ..WaitBatched(since, 1, a)
	Set before = ..WaitMark(..#ORDERS, ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(before.exists, 1, "control: the first failure made the mark")
	Set batched = ..Batches(since).%Size()
	Do ..RevokeRole(..#ORDERSDATA)
	If '..Fail(2, trace) Quit
	Set failed = ..WaitFailed(3)
	Do ..Settle()
	Do $$$AssertEquals(..Batches(since).%Size(), batched, "with no Read on the Orders data database nothing is batched")
	Set after = ..Mark(..#ORDERS, ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(after.markAt_"|"_after.seen, before.markAt_"|"_before.seen, "and the mark is as it was")
	Do ..GrantRole(..#ORDERSDATA)
	Set batches = ..WaitBatched(since, 3, a)
	Do $$$AssertEquals(..Ids(batches, a), ..IdsOf(failed, trace), "with the grant back the failures that arrived are batched, once each")
	Do $$$AssertEquals(..Count(..Batches(since)), 3, "and no more at that point")
}

Method TestNotOwnProduction()
{
	If '..Ready() Quit
	Set a = ..Session("notown")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..ClearMark("OCUTALON")
	Do ..GrantRole(..#HOMEDATA)
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(a, "OCUTALON", ..#ORDERSPRODUCTION, {"DisplayName": "Orders", "AskedBy": "zzfixture", "CreatedAt": (##class(OcuTalon.Data.Time).NowUtc())})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Do $$$AssertEquals(##class(OcuTalon.Watch.Reader).Failures("OCUTALON", ..#ORDERSPRODUCTION, "2000-01-01 00:00:00.000", 10, .rows), "not_current", "control: the reader answers not_current for it")
	Set since = ..Since()
	Set ..HomeHeader = ..MakeHomeFailure()
	Do $$$AssertTrue(..HomeHeader '= "", "a failed header is made in OCUTALON, after the watch's CreatedAt")
	If '..Fail(1, trace) Quit
	Do ..WaitFailed(1)
	Do ..Settle()
	Do $$$AssertEquals(..Batches(since).%Size(), 0, "nothing is read from OCUTALON for the Orders production")
	Do $$$AssertEquals(..Mark("OCUTALON", ..#ORDERSPRODUCTION).exists, 0, "and it makes no mark")
}

Method TestHeaderlessLog()
{
	If '..Ready() Quit
	Set a = ..Session("headerless")
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	Set since = ..Since()
	Set config = "zzPollerLog"_..Number
	Set error = ..HeaderlessLog(2, config)
	Set alert = ..HeaderlessLog(6, config)
	Do $$$AssertTrue((error '= "") && (alert '= ""), "an error row and an alert row with no session are written to the event log of "_..#ORDERS)
	Set batches = ..WaitBatched(since, 2)
	Do $$$AssertEquals(..Count(batches), 2, "the two rows are two failures")
	Do $$$AssertEquals(..Count(batches, "instance"), 2, "under the instance scope")
	Set kinds = ""
	Set iterator = batches.%GetIterator()
	While iterator.%GetNext(, .batch) {
		Do $$$AssertEquals(batch.superSession, "", "an instance batch has an empty SuperSession")
		Set at = batch.failures.%GetIterator()
		While at.%GetNext(, .failure) {
			Set kinds(failure.kind) = failure.item_"|"_failure.headerId_"|"_failure.sessionId_"|"_failure.logId_"|"_failure.errorText
		}
	}
	Do $$$AssertEquals($Get(kinds("error")), config_"|||"_error_"|A fixture row with no session: "_config, "the error row: its ConfigName is the item, it has no header or session, and its text is the sentence")
	Do $$$AssertEquals($Get(kinds("alert")), config_"|||"_alert_"|A fixture row with no session: "_config, "the alert row too")
	Do $$$AssertEquals(..Count(..Batches(since)), 2, "and no further failure is batched")
}

Method TestReadErrorWarns()
{
	If '..Ready() Quit
	Set a = ..Session("readerror")
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	Set before = ..Mark(..#ORDERS, ..#ORDERSPRODUCTION)
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	If '$IsObject(host) Quit
	Set sc = host.OnProcessInput("", .output)
	Do $$$AssertStatusOK(sc, "OnProcessInput answers OK though the read throws")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, ..#PROBE, "OnProcessInput", $ListBuild(..#ORDERSPRODUCTION, $Parameter(..#PROBE, "FAILURE"))), 1, "one warning of the poller (the probe is its class at run time) names the production and the cause")
	Do $$$AssertEquals(..ErrorRows(mark), 0, "and it logs no error row")
	Set after = ..Mark(..#ORDERS, ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(after.exists_"|"_after.markAt_"|"_after.seen, before.exists_"|"_before.markAt_"|"_before.seen, "the mark is as it was")
}

/// The header that TestNotOwnProduction made in OCUTALON, "" when none.
Property HomeHeader As %Integer;

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..DropFlood()
	If ..HomeHeader '= "" Do ##class(Ens.MessageHeader).%DeleteId(..HomeHeader)
	Set ..HomeHeader = ""
	Set sc = ##super(testname)
	Do ..ClearMark(..#ORDERS)
	Do ..ClearMark("OCUTALON")
	Quit sc
}

/// A header in the error status in OCUTALON, processed now, that no watched production owns. Its id is given back.
ClassMethod MakeHomeFailure() As %Integer [ Private ]
{
	Set header = ##class(Ens.MessageHeader).%New()
	Set header.TimeCreated = $ZDateTime($ZTimeStamp, 3, 1, 3)
	Set header.TimeProcessed = header.TimeCreated
	Set header.SourceConfigName = "zzPollerSource"
	Set header.TargetConfigName = "zzPollerTarget"
	Set header.Type = 1
	Set header.Status = 8
	Set sc = header.%Save()
	Quit $Select($$$ISOK(sc): header.%Id(), 1: "")
}

Method TestSendErrorWarns()
{
	If '..Ready() Quit
	Set a = ..Session("senderror")
	Do ..DropFlood()
	Do ..FloodWatch(a)
	Do ..Feed(3)
	Set ^||PollerProbe("send") = "fail"
	Set mark = ##class(OcuTalon.Test.Agent.RunnerFixture).EventMark()
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	If '$IsObject(host) Quit
	Set sc = host.OnProcessInput("", .output)
	Do $$$AssertStatusOK(sc, "OnProcessInput answers OK though the send fails")
	Do $$$AssertEquals(##class(OcuTalon.Test.Agent.RunnerFixture).Warnings(mark, ..#PROBE, "OnProcessInput", $ListBuild(..#FLOODPRODUCTION, $Parameter(..#PROBE, "SENDFAILURE"))), 1, "one warning names the production and the cause")
	Do $$$AssertEquals(..ErrorRows(mark), 0, "and it logs no error row")
	Do $$$AssertEquals(+$Get(^||PollerProbe("sent")), 0, "nothing was sent")
	Do $$$AssertEquals(..Mark(..#ORDERS, ..#FLOODPRODUCTION).exists, 0, "and the production has no mark")
	Kill ^||PollerProbe("send")
	Set sc = host.OnProcessInput("", .output)
	Do $$$AssertStatusOK(sc, "the next poll answers OK")
	Do $$$AssertEquals(+$Get(^||PollerProbe("sent")), 1, "the three failures are sent once, in one batch")
	Do $$$AssertEquals($ListGet($Get(^||PollerProbe("sent", 1)), 3), 3, "the batch holds all three")
	Do $$$AssertEquals(..Mark(..#ORDERS, ..#FLOODPRODUCTION).exists, 1, "and the mark is saved")
	Do ..DropFlood()
}

Method TestFlood()
{
	If '..Ready() Quit
	Set a = ..Session("flood")
	Do ..DropFlood()
	Do ..FloodWatch(a)
	Do ..FloodWatch(..Session("floodtwo"))
	Do ..Feed(600)
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	If '$IsObject(host) Quit
	Do host.OnProcessInput("", .output)
	Do $$$AssertEquals(+$Get(^||PollerProbe("sent")), 1, "the first poll sends one batch")
	Set batch = $Get(^||PollerProbe("sent", 1))
	Do $$$AssertEquals($ListGet(batch, 3)_"|"_$ListGet(batch, 4)_"|"_$ListGet(batch, 2), "500|"_(..#FLOODFIRST + 1)_"|instance", "of the first 500 failures, in order, under the instance scope")
	Set marked = ..Mark(..#ORDERS, ..#FLOODPRODUCTION)
	Do $$$AssertEquals($Length(marked.seen, ","), 3, "the mark keeps the failures of its last 2 seconds as seen")
	Do $$$AssertEquals(+$Get(^||PollerProbe("limit")), 1, "two sessions watch the production and it is read once")
	Do host.OnProcessInput("", .output)
	Do $$$AssertEquals(+$Get(^||PollerProbe("sent")), 2, "the second poll sends one batch")
	Set batch = $Get(^||PollerProbe("sent", 2))
	Do $$$AssertEquals($ListGet(batch, 3)_"|"_$ListGet(batch, 4), "100|"_(..#FLOODFIRST + 501), "the other 100 failures, and none of the first 500 again")
	Do $$$AssertEquals($Get(^||PollerProbe("limit", 1))_"|"_$Get(^||PollerProbe("limit", 2)), "500|503", "the reader is asked for 500, then for 500 and the 3 failures that the mark holds as seen")
	Set marked = ..Mark(..#ORDERS, ..#FLOODPRODUCTION)
	Do host.OnProcessInput("", .output)
	Do $$$AssertEquals(+$Get(^||PollerProbe("sent")), 2, "the third poll sends nothing")
	Set after = ..Mark(..#ORDERS, ..#FLOODPRODUCTION)
	Do $$$AssertEquals(after.markAt_"|"_after.seen, marked.markAt_"|"_marked.seen, "and leaves the mark")
	Do ..DropFlood()
}

/// The probe's feed: count failures of a header each, ids FLOODFIRST + 1 on, one second apart from FLOODSTART on, in the probe's rows mode.
Method Feed(count As %Integer) [ Private ]
{
	Kill ^||PollerProbe
	Set feed = []
	For i = 1:1:count {
		Do feed.%Push({"kind": "header", "headerId": (..#FLOODFIRST + i), "sessionId": "", "superSession": "", "item": "zzFlood", "source": "zzSource", "bodyClass": "Ens.StringRequest", "at": (##class(OcuTalon.Watch.Mark).Shift(..#FLOODSTART, i)), "logId": "", "errorText": "zz flood"})
	}
	Set ^||PollerProbe("feed") = feed.%ToJSON()
	Set ^||PollerProbe("mode") = "rows"
}

/// A watch row of the session on the production that only the probe reads, created before the feed's first failure.
Method FloodWatch(sessionRef As %String) [ Private ]
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(sessionRef, ..#ORDERS, ..#FLOODPRODUCTION, {"DisplayName": "Zz flood", "AskedBy": "zzfixture", "CreatedAt": "2026-10-25T07:00:00Z"})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
}

/// Removes the probe's state, the flood production's mark and its watch rows.
Method DropFlood() [ Private ]
{
	Kill ^||PollerProbe
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.WatchMark WHERE Production = ?", ..#FLOODPRODUCTION)
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.BackgroundCheck WHERE Production = ?", ..#FLOODPRODUCTION)
}

/// The header ids of the failed headers that carry the TraceRef (ascending, as given), and those that do not, comma-separated.
ClassMethod Split(failed As %DynamicArray, trace As %String, Output tagged As %String, Output rest As %String) [ Private ]
{
	Set tagged = ..IdsOf(failed, trace)
	Set rest = ..HeaderIds(..Untagged(failed, trace))
}

/// The ids of the failed headers whose SuperSession is the value.
ClassMethod IdsOf(failed As %DynamicArray, super As %String) As %String [ Private ]
{
	Set ids = ""
	Set iterator = failed.%GetIterator()
	While iterator.%GetNext(, .failure) {
		If failure.superSession = super Set ids = ids_$Select(ids = "": "", 1: ",")_failure.id
	}
	Quit ids
}

/// The failed headers whose SuperSession is none of the values.
ClassMethod Untagged(failed As %DynamicArray, first As %String, second As %String = "") As %DynamicArray [ Private ]
{
	Set rest = []
	Set iterator = failed.%GetIterator()
	While iterator.%GetNext(, .failure) {
		If (failure.superSession '= first) && ((second = "") || (failure.superSession '= second)) Do rest.%Push(failure)
	}
	Quit rest
}

/// The number of error rows (Type 2) that the poller or the probe logged after the event-log mark.
ClassMethod ErrorRows(mark As %Integer) As %Integer [ Private ]
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND SourceClass IN (?, ?)", mark, ..#POLLERCLASS, ..#PROBE)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

}
