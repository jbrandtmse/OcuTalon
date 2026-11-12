/// Tests of the queue-backlog check against a real queue (Story 23.7; AD-3, AD-18, AD-26, AD-28, AD-32). THEY RUN IN THROWAWAY STACKS AND IN CI ONLY (Rule 21), with demo mode on, through
/// Test.Watch.Case: the real Checks reads the queues of the test feed through Watch.Reader, and the finding goes through Intake and the decision to the person's web chat. The feed is
/// OcuTalon.Test.Checks.Queue.Fixture: its own namespace and production (QueueSink holds its queue while the test says so), installed for the test and removed after it. Install refuses where
/// the throwaway's mount of the evaluation set does not exist.
///   - TestQueueRead (Task 0): with the sink held and 105 requests sent, the reader's queue read of the feed gives the sink's queue with its count in the status Queued; the count, the time of the
///     read and the time the queue takes to drain after the release are logged (the measurement the spec records);
///   - TestTwoCrossings (AC5, Integration): the sink held and its queue filled past 100, a run, a second run, the queue drained, a run, filled past 100 again and a run send exactly two
///     watch.queueBacklog Items for QueueSink to Intake, one for each crossing, each with a decision from Intake, and the person's web chat gets the tell-now text that the catalog renders for
///     each. The feed's headers by status, its item states and its production state are the same before and after each run with the sink held. Between the drain and the second crossing the test
///     makes the told time of the queue two hours old, the one thing that the hourly cooldown (AC12) would otherwise decide;
///   - TestOnlineDemoReadsOnlyOrders (AC7): with the online demo flag on and the feed's queue above its threshold, a run reads the Orders production only: Reported has no key for the feed's namespace
///     and no Item is sent for it.
Class OcuTalon.Test.Checks.QueueBacklog Extends OcuTalon.Test.Checks.BeatCase
{

Parameter FIXTURE = "OcuTalon.Test.Checks.Queue.Fixture";

/// The requests sent to fill the queue: above the default threshold of 100.
Parameter FILL = 105;

/// The seconds the test waits for the queue to fill and to drain.
Parameter WAITQUEUE = 60;

Parameter WAITDRAIN = 120;

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..Clean()
	Quit ##super(testname)
}

Method OnAfterAllTests() As %Status
{
	Do ..Clean()
	Quit ##super()
}

/// Releases the sink and removes the feed: nothing if it was never installed.
ClassMethod Clean()
{
	Try {
		If ##class(%SYS.Namespace).Exists($Parameter(..#FIXTURE, "NAMESPACE")) Do $ClassMethod(..#FIXTURE, "Release")
	} Catch {
	}
	Do $ClassMethod(..#FIXTURE, "Remove")
}

/// Task 0: the reader's view of a held queue. The count is logged with the read's time and the drain time, and it is above 100.
Method TestQueueRead()
{
	If '..Ready() Quit
	If '..Installed() Quit
	Do $ClassMethod(..#FIXTURE, "Hold")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Fill", ..#FILL), ..#FILL_" requests are sent to the held sink")
	Set queued = ..WaitInSink(100, ..#WAITQUEUE)
	Set entry = ..Entry()
	If '$IsObject(entry) Quit
	Set start = $ZHorolog
	Set outcome = ##class(OcuTalon.Watch.Reader).Failures(entry.namespace, entry.production, "", 0, .rows, .state, .disabled, .stoppedAt, .errored, .queues)
	Set seconds = $ZHorolog - start
	Do $$$AssertEquals(outcome, "read", "the feed's production is read")
	Do $$$AssertTrue($IsObject(queues), "its queues are read: they are not the empty string that stands for an unread queue")
	If '$IsObject(queues) Quit
	Set found = ""
	Set iterator = queues.%GetIterator()
	While iterator.%GetNext(, .queue) {
		If queue.name = $Parameter(..#FIXTURE, "SINK") Set found = queue
	}
	Do $$$AssertTrue($IsObject(found), "the sink has a queue")
	If '$IsObject(found) Quit
	Do $$$AssertTrue(found.count > 100, "and it holds more than 100 messages: "_found.count)
	Do $$$AssertTrue(found.count '> ..#FILL, "and no more than were sent: "_found.count)
	Do $$$AssertEquals(rows.%Size(), 0, "limit 0 reads no failure")
	Do $$$AssertTrue(##class(OcuTalon.Data.Time).Seconds(found.oldestAt) '= "", "its oldest message has a UTC time: "_found.oldestAt)
	Do $ClassMethod(..#FIXTURE, "Release")
	Set released = $ZHorolog
	Set left = ..WaitInSink(0, ..#WAITDRAIN, 1)
	Do $$$AssertEquals(left, 0, "after the release the queue drains")
	Do $$$LogMessage("Task 0 (Story 23.7): "_..#FILL_" requests sent, "_queued_" in Status Queued when the read began, the sink's queue read as count "_found.count_" (oldest "_found.oldestAt_"), the read took "_$Justify(seconds, 0, 3)_" s, the queue drained "_$Justify($ZHorolog - released, 0, 3)_" s after the release")
}

/// AC5: exactly two Items for the two crossings, each with a decision and the person's web chat text; the feed is not changed by a run.
Method TestTwoCrossings()
{
	If '..Ready() Quit
	If '..Installed() Quit
	Set session = ..Session("queuebacklog")
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.Session SET CreatedAt = ? WHERE Ref = ?", "2999-01-01T00:00:00Z", session)
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, "", "", {"Kind": "queues", "DisplayName": "Queue-backlog check", "AskedBy": "zzfixture", "CreatedAt": (##class(OcuTalon.Data.Time).NowUtc()), "NextDueAt": (..Ahead())})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set floor = ..Top("Ens.MessageHeader", $Namespace)
	Set tickAt = ..Check(ref).NextDueAt

	Do $ClassMethod(..#FIXTURE, "Hold")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Fill", ..#FILL), ..#FILL_" requests are sent to the held sink")
	Do $$$AssertTrue(..WaitInSink(100, ..#WAITQUEUE) > 100, "the sink's queue holds more than 100 messages")
	Set before = $ClassMethod(..#FIXTURE, "Snapshot")
	Set first = ..Run(ref, tickAt, "the first run")
	If first = "" Quit
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "Snapshot"), before, "the feed's headers by status, item states and production state are the same after the first run")
	Set second = ..Run(ref, ..Later(tickAt, 1), "the second run")
	If second = "" Quit
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "Snapshot"), before, "and after the second")
	Set items = ..Findings(trace, session, floor)
	Do $$$AssertEquals(items.%Size(), 1, "one Item for the queue above its threshold, not one for each run: "_items.%Size())
	Set row = ..Check(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "failed|1 queue over its threshold", "the row is failed")

	Do $ClassMethod(..#FIXTURE, "Release")
	Do $$$AssertEquals(..WaitInSink(0, ..#WAITDRAIN, 1), 0, "the queue drains")
	Set third = ..Run(ref, ..Later(tickAt, 2), "the run after the drain")
	If third = "" Quit
	Set row = ..Check(ref)
	Do $$$AssertEquals(row.Result_"|"_..Names(row.Reported), "passed|", "the row is passed and the queue left above")
	Do $$$AssertEquals(..Findings(trace, session, floor).%Size(), 1, "and no Item was sent")
	Do $$$AssertStatusOK(##class(OcuTalon.Test.Checks.Queues).Age(ref), "the told time of the queue is made two hours old")

	Do $ClassMethod(..#FIXTURE, "Hold")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Fill", ..#FILL), ..#FILL_" requests are sent again")
	Do $$$AssertTrue(..WaitInSink(100, ..#WAITQUEUE) > 100, "the queue holds more than 100 messages again")
	Set before = $ClassMethod(..#FIXTURE, "Snapshot")
	Set fourth = ..Run(ref, ..Later(tickAt, 3), "the run after the second crossing")
	If fourth = "" Quit
	Do $$$AssertEquals($ClassMethod(..#FIXTURE, "Snapshot"), before, "the feed is the same after that run too")
	Set items = ..Findings(trace, session, floor)
	Do $$$AssertEquals(items.%Size(), 2, "exactly two Items for the two crossings: "_items.%Size())
	If items.%Size() '= 2 Quit
	Set texts = ""
	For i = 0:1:1 {
		Set item = items.%Get(i)
		Set slots = {}.%FromJSON(item.slots)
		Do $$$AssertEquals(item.catalogKey_"|"_slots.itemName_"|"_slots.production, "watch.queueBacklog|"_$Parameter(..#FIXTURE, "SINK")_"|"_..Label(), "item "_(i + 1)_": the key, the queue and the production's display name")
		Do $$$AssertTrue((slots.count > 100) && (slots.count '> ..#FILL), "item "_(i + 1)_": its count is above the threshold: "_slots.count)
		Do $$$AssertEquals(item.channel_"|"_item.provenance_"|"_item.superSession, "system|untrusted|"_trace, "item "_(i + 1)_": system, untrusted, with the session's TraceRef as SuperSession")
		Do $$$AssertTrue((item.sessionId = item.headerId) && (item.sessionId '= first), "item "_(i + 1)_": in a trace session of its own, not the Tick's: "_item.sessionId)
		Set decision = ..Decision(item.sessionId, item.itemId)
		If $IsObject(decision) Do $$$AssertEquals(decision.catalogKey_"|"_decision.slots, item.catalogKey_"|"_item.slots, "item "_(i + 1)_": Intake sent OutcomeRouter one ItemDecision with the same CatalogKey and Slots")
		Set texts = texts_$ListBuild(##class(OcuTalon.Msg.Catalog).Render(item.catalogKey, item.slots, ##class(OcuTalon.Channel.WebChat.Out).#CHANNEL))
	}
	Set delivered = ..WebTexts(session, 2)
	Do $$$AssertEquals($ListLength(delivered), 2, "the session's web chat got two notifications")
	For i = 1:1:$ListLength(texts) {
		Do $$$AssertTrue($ListFind(delivered, $List(texts, i)), "one of them is the catalog's rendering of item "_i_": "_$List(texts, i))
		Do $$$AssertEquals($Piece($List(texts, i), $Char(10), 2), "Why now: you asked me to watch queue backlogs.", "with the Why now line")
	}
}

/// AC7: on the online demo a run reads the Orders production only.
Method TestOnlineDemoReadsOnlyOrders()
{
	If '..Ready() Quit
	If '..Installed() Quit
	Do ..SetOnlineDemo(1)
	Set listed = ##class(OcuTalon.Watch.Reader).Productions()
	Do $$$AssertEquals(listed.%Size(), 1, "precondition: the reader lists one production on the online demo")
	If listed.%Size() '= 1 Quit
	Do $$$AssertEquals(listed.%Get(0).namespace, ##class(OcuTalon.Install.Step.Demo).#NAMESPACE, "and it is the Orders production")
	Set session = ..Session("queueonline")
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.Session SET CreatedAt = ? WHERE Ref = ?", "2999-01-01T00:00:00Z", session)
	Set trace = ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, "", "", {"Kind": "queues", "DisplayName": "Queue-backlog check", "AskedBy": "zzfixture", "CreatedAt": (##class(OcuTalon.Data.Time).NowUtc()), "NextDueAt": (..Ahead())})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set floor = ..Top("Ens.MessageHeader", $Namespace)
	Set tickAt = ..Check(ref).NextDueAt
	Do $ClassMethod(..#FIXTURE, "Hold")
	Do $$$AssertStatusOK($ClassMethod(..#FIXTURE, "Fill", ..#FILL), ..#FILL_" requests are sent to the held sink")
	Do $$$AssertTrue(..WaitInSink(100, ..#WAITQUEUE) > 100, "the feed's queue is above its threshold")
	If ..Run(ref, tickAt, "the run on the online demo") = "" Quit
	Do $$$AssertEquals(..Findings(trace, session, floor).%Size(), 0, "no Item was sent for the other namespace")
	Set row = ..Check(ref)
	Do $$$AssertEquals(..Names(row.Reported), "", "and Reported has no key for it: "_row.Reported)
	Do $$$AssertTrue(row.LastRunAt '= "", "the row ran")
	Do $$$AssertTrue(row.Reported '[ $Parameter(..#FIXTURE, "NAMESPACE"), "Reported does not name the feed's namespace")
}

/// --- helpers ---
/// Installs the feed; 1 when it is installed, else a failed assertion with the status (Install refuses where the throwaway's mount does not exist) and 0.
Method Installed() As %Boolean [ Private ]
{
	Set sc = $ClassMethod(..#FIXTURE, "Install")
	Do $$$AssertStatusOK(sc, "the queue test feed is installed")
	Quit $$$ISOK(sc)
}

/// The reader's entry for the feed, or "" with a failed assertion.
Method Entry() As %DynamicObject [ Private ]
{
	Set found = ""
	Set iterator = ##class(OcuTalon.Watch.Reader).Productions().%GetIterator()
	While iterator.%GetNext(, .entry) {
		If entry.namespace = $Parameter(..#FIXTURE, "NAMESPACE") Set found = entry
	}
	Do $$$AssertTrue($IsObject(found), "the reader lists the feed's production")
	Quit found
}

/// The display name that the reader gives the feed's production.
Method Label() As %String [ Private ]
{
	Set entry = ..Entry()
	Quit $Select($IsObject(entry): entry.displayName, 1: "")
}

/// The sink's queue, waiting up to seconds until it holds more than above (or, with down 1, no more than above): the last count.
Method WaitInSink(above As %Integer, seconds As %Integer, down As %Boolean = 0) As %Integer [ Private ]
{
	Set end = $ZHorolog + seconds
	For {
		Set count = $ClassMethod(..#FIXTURE, "Queued")
		If $Select(down: count '> above, 1: count > above) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit count
}

/// A Tick of the time to the real Checks; the id of its session, or "" with a failed assertion.
Method Run(ref As %String, tickAt As %String, label As %String) As %Integer [ Private ]
{
	Set session = ..Tick(tickAt)
	Do $$$AssertTrue(session '= "", label_": Checks answers the Tick")
	Quit session
}

/// The time n minutes after the Tick time.
ClassMethod Later(tickAt As %String, n As %Integer) As %String [ Private ]
{
	Quit ##class(OcuTalon.Watch.Mark).FailedAt(##class(OcuTalon.Watch.Mark).Shift(tickAt, 60 * n))
}

/// The names in all the above lists of a Reported, comma-separated.
ClassMethod Names(reported As %String) As %String [ Private ]
{
	If reported = "" Quit ""
	Set object = ##class(%DynamicAbstractObject).%FromJSON(reported)
	If object.%GetTypeOf("above") '= "object" Quit ""
	Set names = ""
	Set iterator = object.above.%GetIterator()
	While iterator.%GetNext(.namespace, .list) {
		Set inner = list.%GetIterator()
		While inner.%GetNext(, .name) {
			Set names = names_$Select(names = "": "", 1: ",")_name
		}
	}
	Quit names
}

/// The ItemDecision that Intake sent to OutcomeRouter for the item in the session, as {catalogKey, slots}, waiting up to WAITDIAGNOSIS seconds for it; "" with a failed assertion when
/// there is none.
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

/// The texts of the session's web chat notifications, a $List, waiting up to WAITDIAGNOSIS seconds for count of them.
Method WebTexts(session As %String, count As %Integer) As %List [ Private ]
{
	Set channel = ##class(OcuTalon.Channel.WebChat.Out).#CHANNEL
	Set end = $ZHorolog + ..#WAITDIAGNOSIS
	For {
		Set rows = ##class(OcuTalon.Test.Core.Observe).DeliveryRows(session)
		Set texts = ""
		For i = 1:1:rows.Count() {
			If rows.GetAt(i).Channel = channel Set texts = texts_$ListBuild(rows.GetAt(i).Text)
		}
		If ($ListLength(texts) '< count) || ($ZHorolog > end) Quit
		Hang 0.25
	}
	Quit texts
}

}
