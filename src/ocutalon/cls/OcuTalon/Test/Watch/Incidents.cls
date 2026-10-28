Include Ensemble

/// Tests of IncidentManager's grouping and settle rule (Story 5.3; AD-4, AD-5, AD-12, AD-15, AD-26). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with
/// demo mode on, through Test.Watch.Case, over the RUNNING production: IncidentManager is an item of it, so the class runs fresh (a warm stack's running job
/// keeps its old code). Failures arrive either from the real poller (the burst) or as FailureBatch messages that the test sends from an adapterless host
/// (Case.SendBatch); the incident and group rows and the session streams are read as plain data. They fail with the reason where OCUORDERS or demo mode is
/// missing. The settle settings are the code defaults, 10 and 30 seconds: no setting row is written. A test waits at most 20 seconds (45 for the trickle),
/// polling every half second: a test bound, not NFR-7. The rows, events and batches of a test are removed after it. Every test points the runners at the CI
/// mock (Case.PointKeys), whose default diagnosis is the one with a fix (a data-format change), which is noticed with its dry run (Story 7.2): with no key
/// the diagnosis is a fallback, and a fallback is noticed at once. The repair is valid only when the incident's evidence pack holds a sample body that names the
/// field, so TestTwoSessions and TestInstanceShared, whose negatives need a notice that has not come yet, deliver a failed fixture order of OCUORDERS
/// (Case.SampleOrder) as the first failure of each incident, with the marker diagnosis-late in every failure's text, so that the diagnosis comes 6 seconds
/// after the diagnosing event (LATE).
///   - TestBurstThroughThePoller (rows Burst and Trace): session A watches Orders and 50 failing orders tagged with A's TraceRef become one open incident of A
///     with one group (Story 5.8: Seq 1, Count 50, the incident's FirstAt and LastAt, NoticeCount 50, the error summary "The order date was not in the expected format."
///     and, on the incident, FirstHeaderId the earliest failed header), `noticed`, `settling` and (Story 5.4, once the settle rule has ended) `diagnosing` on A's stream, a NoticeCount of 50 once the quiet time has passed since LastAt, and, since Story 7.2,
///     the with-fix notice: NoticedAt set, the state awaiting_approval, one incident event, one incident.withFix Notification and the incident in A's ownership read; and the incident's own trace session whose first header carries A's TraceRef;
///   - TestTrickle: one failure every 4 seconds for 24 seconds: the settle ends 30 seconds after the first failure, before the quiet time has passed, with
///     the count by then, and the batches that joined it published no second noticed, settling or diagnosing; a later failure raises Count and keeps NoticeCount, in
///     the same incident;
///   - TestResent: a batch that repeats held keys adds only its new keys, and none of its times, and a batch that joins an unnoticed incident publishes no
///     incident event;
///   - TestPattern: two dates of one sentence are one group, another item and other words are other incidents, and so are the same item and text in another
///     production, in another namespace, or with an item that differs only in case;
///   - TestTwoSessions (rows Two sessions and Before the notice): the same cause for sessions A and B makes two incidents, each stream holds its own
///     incident's events, nobody sees an unnoticed incident while the delayed diagnosis (the marker diagnosis-late, 6 seconds) is on its way, and once the real notice has
///     come (Story 7.2: NoticedAt, with the fix or without it, as the dry run of the incident's failed orders gives) each session lists its own;
///   - TestInstanceShared (rows Instance shared and After the notice): an untagged cause on a production that A and B watch is one instance incident, announced
///     on both streams, with an empty SuperSession; the ownership API finds it for nobody while the delayed diagnosis (diagnosis-late) is on its way and, once the
///     real notice has come, for A and B but not for a session that does not watch, each of the two having one with-fix notification that carries the one request's
///     Ref; a same-cause batch then moves Count and
///     LastAt but not NoticeCount, makes one more incident event for each of the two sessions, no second incident, no notification and no second request;
///   - TestClosedOpensNew: a same-cause failure after the incident is closed (once its waiter has started) makes a new incident with its own Ref;
///   - TestWaitersAfterRestart (row Restart while settling): with the item stopped and started during the wait, the settle still ends once, and the waiter of a
///     deleted incident completes with no error and writes nothing;
///   - TestNobodyToTell: an instance incident of a production that nobody watches makes its rows, publishes nothing on the instance stream and logs no warning,
///     also once its waiter has started; its failure has no FailedAt, so it is held at the batch's PolledAt.
Class OcuTalon.Test.Watch.Incidents Extends OcuTalon.Test.Watch.Case
{

/// The namespace and the production of the incidents that the tests make by SendBatch: nothing runs there, and no session watches it unless a test says so.
Parameter SYNTHNS = "ZZNS";

/// The marker (a prefix of an error text) that picks the mock's delayed diagnosis scenario, which answers 6 seconds late.
Parameter LATE = "[[mock:diagnosis-late]] ";

Parameter SYNTH = "Zz.Incidents";

/// Another namespace, and another production, for the incidents that must not join those of SYNTHNS and SYNTH.
Parameter OTHERNS = "ZZNS2";

Parameter OTHERPRODUCTION = "Zz.Incidents2";

/// The seconds between the failures of the trickle, and their number: the last is sent at 24 seconds, so the maximum (30) ends the settle before the quiet
/// time (10) after the last failure would.
Parameter STEP = 4;

Parameter TRICKLE = 7;

/// 1 while the test has the IncidentManager item stopped.
Property ManagerStopped As %Boolean [ InitialExpression = 0 ];

Method OnAfterOneTest(testname As %String) As %Status
{
	Set sc = $$$OK
	If ..ManagerStopped {
		Set ..ManagerStopped = 0
		Set sc = ##class(Ens.Director).TempStopConfigItem(..#MANAGER, 0, 1)
	}
	Quit $SYSTEM.Status.AppendStatus(sc, ##super(testname))
}

Method TestBurstThroughThePoller()
{
	If '..Ready() || '..PointKeys() Quit
	Set a = ..Session("burst")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Do ..ClearMark(..#ORDERS)
	Do ..Watch(a)
	Set since = ..Since()
	If '..Fail(50, trace) Quit
	Set failed = ..WaitFailed(50)
	Set rows = ..WaitIncident(a, ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(rows.%Size(), 1, "one incident for the burst of A")
	If rows.%Size() < 1 Quit
	Set ref = rows.%Get(0).ref
	Set noticeCount = ..WaitNoticeCount(ref)
	Do $$$AssertTrue(..WaitDiagnosed(ref), "the incident holds its diagnosis")
	Do $$$AssertTrue(..WaitAnswered(ref), "and IncidentManager has handled the answer")
	Do $$$AssertTrue(..WaitRow(ref, "NoticedAt", "", ..#WAITINCIDENT) '= "", "the with-fix notice follows: NoticedAt is set")
	Do ..WaitNotices(ref, 1)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set row = ..Incidents(a, ..#ORDERSPRODUCTION).%Get(0)
	Do $$$AssertEquals(..Incidents(a, ..#ORDERSPRODUCTION).%Size(), 1, "and still one when the settle has ended")
	Do $$$AssertEquals(row.ownerRef_"|"_row.namespace_"|"_row.production_"|"_row.state, a_"|"_..#ORDERS_"|"_..#ORDERSPRODUCTION_"|awaiting_approval", "it is A's, of the Orders production, and awaiting approval")
	Do $$$AssertEquals(row.count, 50, "its Count is the 50 failures")
	Set first = ""
	Set last = ""
	Set firstId = ""
	Set iterator = failed.%GetIterator()
	While iterator.%GetNext(, .header) {
		Set at = ##class(OcuTalon.Watch.Mark).FailedAt(header.at)
		If (first = "") || (first ] at) || ((first = at) && (header.id < firstId)) {
			Set first = at
			Set firstId = header.id
		}
		If (last = "") || (at ] last) Set last = at
	}
	Do $$$AssertEquals(row.firstAt_"|"_row.lastAt, first_"|"_last, "FirstAt and LastAt are the first and last FailedAt")
	Do $$$AssertTrue(row.noticedAt '= "", "NoticedAt is set: the usable data-format diagnosis has a fix, which is noticed with its dry run (Story 7.2)")
	Do $$$AssertEquals(noticeCount, 50, "NoticeCount is 50 once the quiet time has passed since LastAt")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Settle).Wait(row.firstAt, row.lastAt, now, 10, 30), 0, "and the settle rule has ended by then")
	Set group = ..Group(ref)
	Do $$$AssertEquals(group.count_"|"_group.itemName_"|"_group.errorPattern, "1|OrdersFromPartner|"_##class(OcuTalon.Watch.Settle).Pattern(..#ORDERDATETEXT), "one group: OrdersFromPartner and the pattern of the measured sentence")
	Do $$$AssertEquals($Length(group.seen, ","), 50, "which holds the 50 keys")
	Set kept = group.groups.%Get(0)
	Do $$$AssertEquals(kept.seq_"|"_kept.count_"|"_kept.firstAt_"|"_kept.lastAt_"|"_kept.noticeCount, "1|50|"_row.firstAt_"|"_row.lastAt_"|50", "the group is Seq 1 with the 50 failures, the incident's times and the NoticeCount")
	Do $$$AssertEquals(kept.errorSummary, "The order date was not in the expected format.", "its error summary is the first sentence of the error")
	Do $$$AssertEquals(..Incidents(a, ..#ORDERSPRODUCTION).%Get(0).firstHeaderId, firstId, "FirstHeaderId is the earliest failed header, the lowest id among equal times")
	Set progress = ##class(OcuTalon.Test.Core.Observe).Events(a, "watch.progress", 3, 20)
	Do $$$AssertEquals(progress.%Size(), 3, "A's stream holds three watch.progress events")
	If progress.%Size() = 3 {
		Do $$$AssertEquals(progress.%Get(0).payload.stage_"|"_progress.%Get(0).payload.ref, "noticed|"_ref, "the first is noticed for the incident")
		Do $$$AssertEquals(progress.%Get(1).payload.stage_"|"_progress.%Get(1).payload.ref, "settling|"_ref, "the second settling")
		Do $$$AssertEquals(progress.%Get(2).payload.stage_"|"_progress.%Get(2).payload.ref, "diagnosing|"_ref, "and the third diagnosing, once the settle rule has ended")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(a, "incident").%Size(), 1, "one incident event: the with-fix notice")
	Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incidents(a).Count(), 1, "A's ownership read lists the noticed incident")
	Set notes = ..NoticeBodies(ref)
	Do $$$AssertEquals(notes.%Size(), 1, "and A has one Notification of it")
	If notes.%Size() = 1 Do $$$AssertEquals(notes.%Get(0).kind_"|"_notes.%Get(0).catalogKey, "incident|incident.withFix", "the with-fix notice")
	Set batches = ..Batches(since)
	Set sessions = ""
	Set iterator = batches.%GetIterator()
	While iterator.%GetNext(, .batch) {
		Set sessions = sessions_","_batch.sessionId_","
	}
	Do $$$AssertTrue(row.traceHeaderId '= "", "the incident has a trace session")
	Do $$$AssertTrue(sessions '[ (","_row.traceHeaderId_","), "which is none of the batches' sessions")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(row.traceHeaderId)
	Do $$$AssertTrue(headers.%Size() > 0, "and holds messages")
	If headers.%Size() > 0 {
		Do $$$AssertEquals(headers.%Get(0).id_"|"_headers.%Get(0).bodyClass_"|"_headers.%Get(0).superSession, row.traceHeaderId_"|OcuTalon.Watch.Msg.Settle|"_trace, "its first header is the waiter's request, and its SuperSession is A's TraceRef")
	}
}

Method TestTrickle()
{
	If '..Ready() || '..PointKeys() Quit
	Set a = ..Session("trickle")
	Set item = ..Item("t")
	Set since = ..Since()
	Set rows = []
	For i = 1:1:..#TRICKLE {
		Do ..Deliver(..#SYNTHNS, ..#SYNTH, a, [{"item": (item), "text": ("Field 'Qty' was empty in order "_i), "at": (..Stamp(0))}])
		If i = 1 {
			Set rows = ..WaitIncident(a, ..#SYNTH)
			If rows.%Size() < 1 Quit
			Set ref = rows.%Get(0).ref
		}
		If i < ..#TRICKLE Hang ..#STEP
	}
	If rows.%Size() < 1 {
		Do $$$AssertTrue(0, "the first failure makes an incident")
		Quit
	}
	Set noticeCount = ..WaitNoticeCount(ref, ..#WAITTRICKLE)
	Set now = ##class(OcuTalon.Data.Time).NowUtc()
	Set row = ..Incidents(a, ..#SYNTH).%Get(0)
	Do $$$AssertEquals(..Incidents(a, ..#SYNTH).%Size(), 1, "the trickle is one incident")
	Do $$$AssertEquals(noticeCount, ..#TRICKLE, "the settle ends with the count by then: all "_..#TRICKLE_" failures")
	Do $$$AssertEquals(##class(OcuTalon.Watch.Settle).Wait(row.firstAt, row.lastAt, now, 10, 30), 0, "the rule has ended")
	Do $$$AssertTrue(##class(OcuTalon.Watch.Settle).Wait(row.firstAt, row.lastAt, now, 10, 1000) > 0, "by the maximum, before the quiet time since the last failure has passed")
	Set progress = ##class(OcuTalon.Test.Core.Observe).Events(a, "watch.progress", 3, 20)
	Do $$$AssertEquals(progress.%Size(), 3, "the batches that joined the incident announced it no more and started no other waiter")
	If progress.%Size() = 3 Do $$$AssertEquals(progress.%Get(0).payload.stage_"|"_progress.%Get(1).payload.stage_"|"_progress.%Get(2).payload.stage_"|"_progress.%Get(1).payload.ref, "noticed|settling|diagnosing|"_ref, "noticed, settling and diagnosing once each, for the incident")
	Do ..Deliver(..#SYNTHNS, ..#SYNTH, a, [{"item": (item), "text": "Field 'Qty' was empty in order 99", "at": (..Stamp(0))}])
	Set count = ..WaitCount(ref, ..#TRICKLE + 1)
	Set row = ..Incidents(a, ..#SYNTH).%Get(0)
	Do $$$AssertEquals(..Incidents(a, ..#SYNTH).%Size(), 1, "it joins the same incident")
	Do $$$AssertEquals(row.count_"|"_row.noticeCount, (..#TRICKLE + 1)_"|"_..#TRICKLE, "Count moves and NoticeCount stays")
	Do $$$AssertEquals(..Group(ref).count, 1, "in the one group")
}

Method TestResent()
{
	If '..Ready() || '..PointKeys() Quit
	Set a = ..Session("resent")
	Set item = ..Item("r")
	Set since = ..Since()
	Set s1 = ..Stamp(-4)
	Set s2 = ..Stamp(-3)
	Set s3 = ..Stamp(-2)
	Do ..Deliver(..#SYNTHNS, ..#SYNTH, a, [{"item": (item), "text": "Field 'Qty' was empty in order 1", "at": (s1)}, {"item": (item), "text": "Field 'Qty' was empty in order 2", "at": (s2)}, {"item": (item), "text": "Field 'Qty' was empty in order 3", "at": (s3)}], .keys)
	Set rows = ..WaitIncident(a, ..#SYNTH)
	If rows.%Size() < 1 {
		Do $$$AssertTrue(0, "the first batch makes an incident")
		Quit
	}
	Set ref = rows.%Get(0).ref
	Do $$$AssertEquals(..WaitCount(ref, 3), 3, "it holds three failures")
	Set before = ..Incidents(a, ..#SYNTH).%Get(0)
	Set second = $Extract(keys.%Get(1), 2, $Length(keys.%Get(1)))
	Set third = $Extract(keys.%Get(2), 2, $Length(keys.%Get(2)))
	Set s4 = ..Stamp(-1)
	Do ..Deliver(..#SYNTHNS, ..#SYNTH, a, [{"item": (item), "text": "Field 'Qty' was empty in order 2", "at": (..Stamp(-100)), "id": (second)}, {"item": (item), "text": "Field 'Qty' was empty in order 3", "at": (..Stamp(50)), "id": (third)}, {"item": (item), "text": "Field 'Qty' was empty in order 4", "at": (s4)}], .again)
	Do $$$AssertEquals(..WaitCount(ref, 4), 4, "only the new failure is counted")
	Hang 1
	Set row = ..Incidents(a, ..#SYNTH).%Get(0)
	Do $$$AssertEquals(..Incidents(a, ..#SYNTH).%Size(), 1, "in the same incident")
	Do $$$AssertEquals(row.count, 4, "Count is 4 after the pause too")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(a, "incident").%Size(), 0, "and a batch that joins an unnoticed incident publishes no incident event")
	Do $$$AssertEquals(before.firstAt_"|"_row.firstAt_"|"_row.lastAt, s1_"|"_s1_"|"_s4, "a held failure adds no time: FirstAt is as it was and LastAt is the new failure's")
	Do $$$AssertEquals(..Group(ref).seen, keys.%Get(0)_","_keys.%Get(1)_","_keys.%Get(2)_","_again.%Get(2), "the group holds each key once, oldest first")
}

Method TestPattern()
{
	If '..Ready() || '..PointKeys() Quit
	Set a = ..Session("pattern")
	Set item = ..Item("p")
	Set other = ..Item("q")
	Set since = ..Since()
	Set text = "The order date was not in the expected format. Expected YYYY-MM-DD, got '10/16/2026'."
	Set text2 = "The order date was not in the expected format. Expected YYYY-MM-DD, got '10/17/2026'."
	Set words = "The order quantity was missing."
	Do ..Deliver(..#SYNTHNS, ..#SYNTH, a, [{"item": (item), "text": (text), "at": (..Stamp(-3))}, {"item": (item), "text": (text2), "at": (..Stamp(-2))}, {"item": (other), "text": (text), "at": (..Stamp(-2))}, {"item": (item), "text": (words), "at": (..Stamp(-1))}])
	Set rows = ..WaitIncident(a, ..#SYNTH, 3)
	Do $$$AssertEquals(rows.%Size(), 3, "three incidents: the two dates, another item, other words")
	If rows.%Size() '= 3 Quit
	Set dates = ..Group(rows.%Get(0).ref)
	Do $$$AssertEquals(rows.%Get(0).count_"|"_dates.itemName_"|"_dates.errorPattern, "2|"_item_"|"_##class(OcuTalon.Watch.Settle).Pattern(text), "the two dates are one group of two failures")
	Do $$$AssertEquals(dates.errorPattern, "The order date was not in the expected format. Expected YYYY-MM-DD, got '#/#/#'.", "with the digits masked")
	Set another = ..Group(rows.%Get(1).ref)
	Do $$$AssertEquals(rows.%Get(1).count_"|"_another.itemName, "1|"_other, "another item with the same text is its own incident")
	Set reworded = ..Group(rows.%Get(2).ref)
	Do $$$AssertEquals(rows.%Get(2).count_"|"_reworded.itemName_"|"_reworded.errorPattern, "1|"_item_"|"_words, "other words are their own incident")
	Do ..Deliver(..#SYNTHNS, ..#SYNTH, a, [{"item": (item), "text": "The order date was not in the expected format. Expected YYYY-MM-DD, got '10/18/2026'.", "at": (..Stamp(0))}])
	Do $$$AssertEquals(..WaitCount(rows.%Get(0).ref, 3), 3, "it joins the first incident")
	Do $$$AssertEquals(..Incidents(a, ..#SYNTH).%Size(), 3, "and makes no fourth")
	Set date = {"item": (item), "text": (text), "at": (..Stamp(0))}
	Do ..Deliver(..#SYNTHNS, ..#OTHERPRODUCTION, a, [(date)])
	Do $$$AssertEquals(..WaitIncident(a, ..#OTHERPRODUCTION).%Size(), 1, "the same item and text in another production is its own incident")
	Do ..Deliver(..#OTHERNS, ..#OTHERPRODUCTION, a, [(date)])
	Do $$$AssertEquals(..WaitIncident(a, ..#OTHERPRODUCTION, 2).%Size(), 2, "and in another namespace of that production another")
	Do ..Deliver(..#SYNTHNS, ..#SYNTH, a, [{"item": ($ZConvert(item, "U")), "text": (text), "at": (..Stamp(0))}])
	Do $$$AssertEquals(..WaitIncident(a, ..#SYNTH, 4).%Size(), 4, "and an item that differs only in case is another incident: the comparison is exact")
}

Method TestTwoSessions()
{
	If '..Ready() || '..PointKeys() Quit
	Set a = ..Session("two1")
	Set b = ..Session("two2")
	Set item = ..Item("s")
	Set since = ..Since()
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set sampleA = ..SampleOrder(##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef)
	Set sampleB = ..SampleOrder(##class(OcuTalon.Data.Session).RefIndexOpen(b).TraceRef)
	Do ..Deliver(..#ORDERS, ..#ORDERSPRODUCTION, a, [{"item": (item), "text": (..#LATE_"Field 'Qty' was empty in order 1"), "at": (..Stamp(-1)), "id": (sampleA)}, {"item": (item), "text": (..#LATE_"Field 'Qty' was empty in order 2"), "at": (..Stamp(-1))}])
	Do ..Deliver(..#ORDERS, ..#ORDERSPRODUCTION, b, [{"item": (item), "text": (..#LATE_"Field 'Qty' was empty in order 3"), "at": (..Stamp(-1)), "id": (sampleB)}])
	Set rowsA = ..WaitIncident(a, ..#ORDERSPRODUCTION)
	Set rowsB = ..WaitIncident(b, ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(rowsA.%Size()_"|"_rowsB.%Size(), "1|1", "each session has one incident")
	If (rowsA.%Size() '= 1) || (rowsB.%Size() '= 1) Quit
	Set refA = rowsA.%Get(0).ref
	Set refB = rowsB.%Get(0).ref
	Do $$$AssertTrue(refA '= refB, "two incidents, with two Refs")
	Do $$$AssertEquals(..WaitCount(refA, 2), 2, "A's holds A's two failures")
	Do $$$AssertEquals(..Incidents(b, ..#ORDERSPRODUCTION).%Get(0).count, 1, "and B's holds B's one")
	Set progressA = ##class(OcuTalon.Test.Core.Observe).Events(a, "watch.progress", 3, ..#WAITINCIDENT + ..#WAITTRICKLE)
	Set progressB = ##class(OcuTalon.Test.Core.Observe).Events(b, "watch.progress", 3, ..#WAITINCIDENT)
	Do $$$AssertEquals(progressA.%Size()_"|"_progressB.%Size(), "3|3", "each stream holds three watch.progress events, the third once the settle rule has ended; the delayed diagnosis is still on its way")
	If (progressA.%Size() = 3) && (progressB.%Size() = 3) {
		Do $$$AssertEquals(progressA.%Get(0).payload.ref_"|"_progressA.%Get(1).payload.ref_"|"_progressA.%Get(2).payload.ref, refA_"|"_refA_"|"_refA, "A's are for A's incident")
		Do $$$AssertEquals(progressB.%Get(0).payload.ref_"|"_progressB.%Get(1).payload.ref_"|"_progressB.%Get(2).payload.ref, refB_"|"_refB_"|"_refB, "and B's for B's")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(a, "incident").%Size() + ##class(OcuTalon.Test.Core.Observe).Events(b, "incident").%Size(), 0, "no incident event before a notice")
	For each = a, b {
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).Incidents(each, .sc).Count(), 0, "an unnoticed incident is not in Incidents")
		Do $$$AssertStatusOK(sc, "which read without an error")
		Do $$$AssertEquals(##class(OcuTalon.Data.Ownership).RecentIncidents(each, 10, .sc).Count(), 0, "nor in RecentIncidents")
		Do $$$AssertStatusOK(sc, "which read without an error")
		Do $$$AssertEquals($IsObject(##class(OcuTalon.Data.Ownership).Incident(refA, each, .scA)) + $IsObject(##class(OcuTalon.Data.Ownership).Incident(refB, each, .scB)), 0, "nor found by its Ref")
		Do $$$AssertTrue($$$ISOK(scA) && $$$ISOK(scB), "which read without an error")
	}
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Tell", "IncidentManager could not"), 0, "and no warning was logged")
	Do $$$AssertTrue(..WaitDiagnosed(refA), "A's incident then holds its diagnosis")
	Do $$$AssertTrue(..WaitDiagnosed(refB), "and B's holds its")
	Do $$$AssertTrue(..WaitRow(refA, "NoticedAt", "", ..#WAITINCIDENT) '= "", "A's incident is noticed (the real notice)")
	Do $$$AssertTrue(..WaitRow(refB, "NoticedAt", "", ..#WAITINCIDENT) '= "", "and B's")
	Set listA = ##class(OcuTalon.Data.Ownership).Incidents(a, .scA)
	Set listB = ##class(OcuTalon.Data.Ownership).Incidents(b, .scB)
	Do $$$AssertTrue($$$ISOK(scA) && $$$ISOK(scB), "the noticed incidents are read without an error")
	Do $$$AssertEquals(listA.Count()_"|"_listB.Count(), "1|1", "each session now lists one incident")
	If (listA.Count() = 1) && (listB.Count() = 1) Do $$$AssertEquals(listA.GetAt(1).Ref_"|"_listB.GetAt(1).Ref, refA_"|"_refB, "its own")
	Do $$$AssertEquals($IsObject(##class(OcuTalon.Data.Ownership).Incident(refA, b, .sc)) + $IsObject(##class(OcuTalon.Data.Ownership).Incident(refB, a, .sc)), 0, "and neither finds the other's by its Ref")
}

Method TestInstanceShared()
{
	If '..Ready() || '..PointKeys() Quit
	Set a = ..Session("inst1")
	Set b = ..Session("inst2")
	Do ..Watch(a)
	Do ..Watch(b)
	Set item = ..Item("i")
	Set since = ..Since()
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do ..Deliver(..#ORDERS, ..#ORDERSPRODUCTION, "instance", [{"item": (item), "text": (..#LATE_"Field 'Qty' was empty in order 1"), "at": (..Stamp(-2)), "id": (..SampleOrder(""))}, {"item": (item), "text": (..#LATE_"Field 'Qty' was empty in order 2"), "at": (..Stamp(-1))}, {"item": (item), "text": (..#LATE_"Field 'Qty' was empty in order 3"), "at": (..Stamp(-1))}])
	Set rows = ..WaitIncident("instance", ..#ORDERSPRODUCTION)
	Do $$$AssertEquals(rows.%Size(), 1, "one instance incident")
	If rows.%Size() '= 1 Quit
	Set ref = rows.%Get(0).ref
	Do $$$AssertEquals(..Group(ref).itemName, item, "it is the incident of the test's item")
	Do $$$AssertEquals(..WaitCount(ref, 3), 3, "with the three failures")
	For each = a, b {
		Set progress = ##class(OcuTalon.Test.Core.Observe).Events(each, "watch.progress", 3, ..#WAITINCIDENT + ..#WAITTRICKLE)
		Do $$$AssertEquals(progress.%Size(), 3, "the stream of a watching session holds three watch.progress events")
		If progress.%Size() = 3 Do $$$AssertEquals(progress.%Get(0).payload.stage_"|"_progress.%Get(1).payload.stage_"|"_progress.%Get(2).payload.stage_"|"_progress.%Get(0).payload.ref, "noticed|settling|diagnosing|"_ref, "noticed, settling then diagnosing, for the incident")
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(each, "incident").%Size(), 0, "and no incident event while the delayed diagnosis is on its way")
	}
	Set row = ..Incidents("instance", ..#ORDERSPRODUCTION).%Get(0)
	Do $$$AssertTrue(row.traceHeaderId '= "", "the incident has a trace session")
	Set headers = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(row.traceHeaderId)
	Do $$$AssertTrue(headers.%Size() > 0, "which holds messages")
	If headers.%Size() > 0 Do $$$AssertEquals(headers.%Get(0).id_"|"_headers.%Get(0).superSession, row.traceHeaderId_"|", "its first header has an empty SuperSession, the scope being instance")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Tell", "IncidentManager could not"), 0, "no warning was logged")
	Set c = ..Session("inst3")
	Do $$$AssertEquals(..Finds(ref, a, b, c), "000", "before the notice no session finds the instance incident by its Ref")
	Do $$$AssertTrue(..WaitDiagnosed(ref), "the incident then holds its diagnosis")
	Do $$$AssertTrue(..WaitRow(ref, "NoticedAt", "", ..#WAITINCIDENT) '= "", "and is noticed (the real notice)")
	Do ..WaitNotices(ref, 2)
	Do $$$AssertEquals(..Finds(ref, a, b, c), "110", "after it, the two watching sessions find it and a session that does not watch the production does not")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(a, "incident", 1, 5).%Size()_"|"_##class(OcuTalon.Test.Core.Observe).Events(b, "incident", 1, 5).%Size(), "1|1", "each watching session got one incident event with the notice")
	Set requests = ..Requests(ref)
	Do $$$AssertEquals(requests.%Size(), 1, "exactly one request names the incident")
	Set approval = $Select(requests.%Size() = 1: requests.%Get(0).ref, 1: "")
	Set notices = ..NoticeBodies(ref)
	Set sessions = ""
	Set iterator = notices.%GetIterator()
	While iterator.%GetNext(, .note) {
		Set sessions = sessions_","_note.sessionRef_"="_note.catalogKey_"|"_note.approvalRef
		Do $$$AssertEquals(note.catalogKey_"|"_note.approvalRef, "incident.withFix|"_approval, "each is the with-fix notice with the request's Ref")
	}
	Do $$$AssertEquals(notices.%Size(), 2, "and A and B each have one notification of the incident: "_sessions)
	Set noticeCount = notices.%Size()
	Set later = ..Stamp(0)
	Do ..Deliver(..#ORDERS, ..#ORDERSPRODUCTION, "instance", [{"item": (item), "text": (..#LATE_"Field 'Qty' was empty in order 4"), "at": (later)}])
	Do $$$AssertEquals(..WaitCount(ref, 4), 4, "Count moves to 4")
	For each = a, b {
		Set events = ##class(OcuTalon.Test.Core.Observe).Events(each, "incident", 2, 5)
		Do $$$AssertEquals(events.%Size(), 2, "each watching session gets one more incident event")
		If events.%Size() = 2 Do $$$AssertEquals(events.%Get(1).payload.ref_"|"_events.%Get(1).payload.count_"|"_events.%Get(1).payload.noticeCount, ref_"|4|3", "with the new count and the count at the notice")
	}
	Hang 1
	For each = a, b {
		Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(each, "incident").%Size(), 2, "and no third one")
	}
	Set row = ..Incidents("instance", ..#ORDERSPRODUCTION).%Get(0)
	Do $$$AssertEquals(..Incidents("instance", ..#ORDERSPRODUCTION).%Size(), 1, "there is still one incident")
	Do $$$AssertEquals(row.count_"|"_row.noticeCount, "4|3", "NoticeCount stays")
	Do $$$AssertEquals(row.lastAt, later, "LastAt moved to the new failure")
	Do $$$AssertEquals(..Notifications(ref), noticeCount, "and no new notification carries the incident's Ref")
	Do $$$AssertEquals(..Requests(ref).%Size(), 1, "nor a second request")
}

Method TestClosedOpensNew()
{
	If '..Ready() || '..PointKeys() Quit
	Set a = ..Session("closed")
	Set item = ..Item("c")
	Set since = ..Since()
	Do ..Deliver(..#SYNTHNS, ..#SYNTH, a, [{"item": (item), "text": "Field 'Qty' was empty in order 1", "at": (..Stamp(-1))}])
	Set rows = ..WaitIncident(a, ..#SYNTH)
	If rows.%Size() < 1 {
		Do $$$AssertTrue(0, "the failure makes an incident")
		Quit
	}
	Set first = rows.%Get(0).ref
	Do $$$AssertTrue(..WaitWaiter(a, ..#SYNTH), "its waiter has started, so the close cannot race the waiter's save")
	Do $$$AssertEquals(..CloseIncident(first), 1, "the incident is closed (fixture)")
	Do ..Deliver(..#SYNTHNS, ..#SYNTH, a, [{"item": (item), "text": "Field 'Qty' was empty in order 2", "at": (..Stamp(0))}])
	Set rows = ..WaitIncident(a, ..#SYNTH, 2)
	Do $$$AssertEquals(rows.%Size(), 2, "a second incident is made")
	If rows.%Size() '= 2 Quit
	Do $$$AssertTrue(rows.%Get(1).ref '= first, "with a new Ref")
	Do $$$AssertEquals(rows.%Get(0).state_"|"_rows.%Get(0).count_"|"_rows.%Get(1).state_"|"_rows.%Get(1).count, "closed|1|open|1", "the closed incident is as it was and the new one is open with the new failure")
	Set end = $ZHorolog + ..#WAITINCIDENT
	For {
		Set noticed = ""
		Set progress = ##class(OcuTalon.Test.Core.Observe).Events(a, "watch.progress")
		Set iterator = progress.%GetIterator()
		While iterator.%GetNext(, .event) {
			If event.payload.stage = "noticed" Set noticed = noticed_$Select(noticed = "": "", 1: ",")_event.payload.ref
		}
		If ($Length(noticed, ",") '< 2) || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Do $$$AssertEquals(noticed, first_","_rows.%Get(1).ref, "each incident has its own noticed event")
}

Method TestWaitersAfterRestart()
{
	If '..Ready() || '..PointKeys() Quit
	Set a = ..Session("restart")
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(a).TraceRef
	Set kept = ..Item("k")
	Set dropped = ..Item("d")
	Set since = ..Since()
	Do ..Deliver(..#SYNTHNS, ..#SYNTH, a, [{"item": (kept), "text": "Field 'Qty' was empty in order 1", "at": (..Stamp(0))}, {"item": (dropped), "text": "Field 'Qty' was empty in order 2", "at": (..Stamp(0))}])
	Set rows = ..WaitIncident(a, ..#SYNTH, 2)
	Do $$$AssertEquals(rows.%Size(), 2, "two incidents are settling")
	If rows.%Size() '= 2 Quit
	Set end = $ZHorolog + ..#WAITINCIDENT
	For {
		Set rows = ..Incidents(a, ..#SYNTH)
		If (rows.%Size() = 2) && (rows.%Get(0).traceHeaderId '= "") && (rows.%Get(1).traceHeaderId '= "") Quit
		If $ZHorolog > end Quit
		Hang 0.5
	}
	Do $$$AssertTrue((rows.%Size() = 2) && (rows.%Get(0).traceHeaderId '= "") && (rows.%Get(1).traceHeaderId '= ""), "both waiters have started and wait on their alarms")
	If (rows.%Size() '= 2) || (rows.%Get(0).traceHeaderId = "") || (rows.%Get(1).traceHeaderId = "") Quit
	Set keptRef = rows.%Get(0).ref
	Set keptSession = rows.%Get(0).traceHeaderId
	Set droppedSession = rows.%Get(1).traceHeaderId
	Set droppedRef = rows.%Get(1).ref
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set ..ManagerStopped = 1
	Do $$$AssertStatusOK(##class(Ens.Director).TempStopConfigItem(..#MANAGER, 1, 1), "the "_..#MANAGER_" item is stopped during the wait")
	Do $$$AssertEquals(..DeleteIncident(droppedRef), 1, "the second incident is deleted while it is stopped")
	Hang 2
	Do $$$AssertStatusOK(##class(Ens.Director).TempStopConfigItem(..#MANAGER, 0, 1), "the item is started again")
	Set ..ManagerStopped = 0
	Set noticeCount = ..WaitNoticeCount(keptRef)
	Do $$$AssertEquals(noticeCount, 1, "the settle of the kept incident still ends, with its count")
	Hang 2
	Set rows = ..Incidents(a, ..#SYNTH)
	Do $$$AssertEquals(rows.%Size(), 1, "the deleted incident was not made again")
	Do $$$AssertEquals(##class(OcuTalon.Data.Incident).RefIndexExists(droppedRef), 0, "and the waiter wrote nothing")
	Do $$$AssertEquals(..Group(droppedRef).count, 0, "no group either")
	Set errors = 0
	For each = keptSession, droppedSession {
		Set headers = ##class(OcuTalon.Test.Data.Fixture).SessionHeaders(each)
		Do $$$AssertTrue(headers.%Size() > 0, "a waiter's session holds its messages")
		Set iterator = headers.%GetIterator()
		While iterator.%GetNext(, .header) {
			If header.isError Set errors = errors + 1
		}
	}
	Set headers = ##class(OcuTalon.Test.Data.Fixture).Headers(trace)
	Set iterator = headers.%GetIterator()
	While iterator.%GetNext(, .header) {
		If header.isError Set errors = errors + 1
	}
	Do $$$AssertEquals(errors, 0, "no message of the waiters' sessions is in error")
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 2 AND ConfigName = ?", mark, ..#MANAGER)
	Do rs.%Next()
	Do $$$AssertEquals(+rs.%GetData(1), 0, "and the event log holds no error of the item")
}

Method TestNobodyToTell()
{
	If '..Ready() || '..PointKeys() Quit
	Set a = ..Session("nobody")
	Set item = ..Item("n")
	Set since = ..Since()
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set before = ##class(OcuTalon.Test.Core.Observe).Events("instance", "watch.progress").%Size()
	Set polledFrom = ##class(OcuTalon.Data.Time).NowUtc()
	Do ..Deliver(..#SYNTHNS, "Zz.Nobody", "instance", [{"item": (item), "text": "Field 'Qty' was empty in order 1", "at": ""}])
	Set polledTo = ##class(OcuTalon.Data.Time).NowUtc()
	Set rows = ..WaitIncident("instance", "Zz.Nobody")
	Do $$$AssertEquals(rows.%Size(), 1, "the incident row is made")
	If rows.%Size() '= 1 Quit
	Do $$$AssertEquals(..Group(rows.%Get(0).ref).itemName, item, "with its group")
	Set row = rows.%Get(0)
	Do $$$AssertTrue((row.firstAt = row.lastAt) && '(polledFrom ] row.firstAt) && '(row.firstAt ] polledTo), "a failure with no FailedAt is held at the batch's PolledAt: "_row.firstAt)
	Do $$$AssertTrue(..WaitWaiter("instance", "Zz.Nobody"), "its waiter has started")
	Hang 1
	Set end = $ZHorolog + ..#WAITBATCH
	For {
		Set batches = ..Batches(since)
		If (batches.%Size() > 0) && (batches.%Get(0).status = 9) Quit
		If $ZHorolog > end Quit
		Hang 0.5
	}
	Do $$$AssertEquals(batches.%Size() > 0 && (batches.%Get(0).status = 9), 1, "and the batch is completed")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events("instance", "watch.progress").%Size(), before, "nothing is published on the instance stream")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Tell", "IncidentManager could not"), 0, "and no warning is logged: no watcher is not an error")
}

/// Sends the batch (Case.SendBatch) and asserts that it was accepted; keys are the keys of its failures.
Method Deliver(namespace As %String, production As %String, ownerRef As %String, failures As %DynamicArray, Output keys As %DynamicArray) [ Private ]
{
	Set sc = ..SendBatch(namespace, production, ownerRef, failures, .keys)
	Do $$$AssertStatusOK(sc, "a batch of "_failures.%Size()_" failure(s) for '"_ownerRef_"' is sent")
}

/// Waits up to WAITINCIDENT seconds, polling every half second, until the owner's newest incident of the production has a trace session: its waiter has started
/// and saved it. 1 when it has.
Method WaitWaiter(ownerRef As %String, production As %String) As %Boolean [ Private ]
{
	Set end = $ZHorolog + ..#WAITINCIDENT
	For {
		Set rows = ..Incidents(ownerRef, production)
		Set started = (rows.%Size() > 0) && (rows.%Get(rows.%Size() - 1).traceHeaderId '= "")
		If started || ($ZHorolog > end) Quit
		Hang 0.5
	}
	Quit started
}

/// For each of the three sessions, 1 when the ownership API finds the incident by its Ref for it, else 0; an error in the read is the caller's red.
ClassMethod Finds(ref As %String, a As %String, b As %String, c As %String) As %String
{
	Set found = ""
	For each = a, b, c {
		Set incident = ##class(OcuTalon.Data.Ownership).Incident(ref, each, .sc)
		Set found = found_$Select($$$ISERR(sc): "e", 1: $IsObject(incident))
	}
	Quit found
}

/// The stamp of the second that is seconds from now, as a failure carries it.
ClassMethod Stamp(seconds As %Integer) As %String
{
	Quit ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(##class(OcuTalon.Watch.Mark).Normal(##class(OcuTalon.Data.Time).NowUtc()), seconds))
}

/// The fixture of a closed incident: sets its State to closed. 1 when it saved.
ClassMethod CloseIncident(ref As %String) As %Boolean
{
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	If '$IsObject(row) Quit 0
	Set row.State = "closed"
	Quit $$$ISOK(row.%Save())
}

/// Deletes the incident and its groups. 1 when it was there.
ClassMethod DeleteIncident(ref As %String) As %Boolean
{
	Set row = ##class(OcuTalon.Data.Incident).RefIndexOpen(ref)
	If '$IsObject(row) Quit 0
	Set id = row.%Id()
	Kill row
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.FailureGroup WHERE IncidentRef = ?", ref)
	Quit $$$ISOK(##class(OcuTalon.Data.Incident).%DeleteId(id))
}

}
