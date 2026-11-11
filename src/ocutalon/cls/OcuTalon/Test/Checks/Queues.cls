/// Tests of the queue-backlog check's rules and runs (Story 23.7; AD-18, AD-19, AD-26, AD-28, AD-32, AD-33): OcuTalon.Checks.Queues (the pure rules) and the runs of
/// OcuTalon.Checks.Process RunQueues. The tests need no production and no namespace but their own: they call OnRequest of a shadow instance of Test.Checks.QueueProbe in
/// the test process, with real Tick objects, over fixture sessions and rows of Test.Data.Fixture, and read the rows, the sessions' streams, the log and what the probe
/// recorded. They run warm. The rows are of the probe's Kind (zzqueues), which no real Checks runs, and the probe keeps only the rows of the test. The Tick's time is a
/// fixed time in 2030 (TICK); a run's own time is the clock's, so the ages of the queues are given from now.
///   - TestOver (pure): the one threshold rule: more messages than queueMessages, or messages whose oldest has waited more than queueWaitMinutes minutes; exactly at the limit
///     is not above; an unreadable oldest time and an empty queue are never above by age;
///   - TestCrossings (pure; matrix "First run, above", "Still above", "Falls below, rises again", "Age crossing", "Namespace unread"): the first run reports every queue that is above,
///     the next reports none of them, a queue that fell below and is above again after the cooldown is reported once more, an unread namespace and a namespace that is not in
///     the readings keep their previous list, an invalid previous is no baseline, and reported holds only the non-empty lists;
///   - TestCooldown (pure; AC12, Contest Planner ruling): a queue is reported at most once an hour: a queue that drops below and backs up again within the hour is not reported and
///     is not in above, the first run at or after the hour that still finds it above reports it, a different queue is not held back, and a told time of an hour or more is dropped;
///   - TestFirstRun, TestStillAbove, TestFallsBelowRisesAgain, TestAgeCrossing (AC2, AC3; through the probe): the Items, their fields, their trace, the row's result and finding,
///     Reported, the check event, the reads that were made (the entries and the queues of each, nothing else) and the CheckRun;
///   - TestFlappingThroughARun (AC12): a queue that is reported, drops below and backs up again within the hour sends no second Item through a run;
///   - TestAdminThreshold (AC6): the limits are read on every run (checks.thresholds.queueMessages), and a stored value that is not a number reads as the default;
///   - TestNamespaceUnread and TestListUnreadable (AC4; matrix "Namespace unread", "List unreadable", "Empty list"): not_checked with the REASON of the first unread namespace (read
///     throws, unreadable, not_current, or queues given as ""), its previous list kept, the other namespaces' crossings still sent; a list that throws or is empty is not_checked
///     REASONREAD with Reported unchanged; the CheckRun holds the reason (Coverage.ReasonOf) and the row is never passed;
///   - TestStoppedMeanwhile (matrix "Stopped meanwhile"): the row is deleted during the read: nothing is recorded, sent or published;
///   - TestSendFails (matrix "Send fails"): one warning for the Item that cannot be sent, the other Items still go and the failed one is not sent again;
///   - TestDue: a row that is not due at the Tick does not run; the next one is the Tick plus 60 seconds;
///   - TestQueueFindingRenders: each Item's key and slots render to the catalog's text on the web channel, local and online demo, for one message and for many; a queue
///     above by count whose oldest time is unreadable gets the run time in its oldestAt slot and renders.
/// Each test starts from the default thresholds (100 messages, 10 minutes) and puts the stored ones back after it.
Class OcuTalon.Test.Checks.Queues Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Checks.QueueProbe";

/// The time of the first Tick.
Parameter TICK = "2030-06-01T12:00:00Z";

/// The id of the session that the probe runs in.
Parameter SESSIONID = 424243;

/// The seconds of the cooldown, as Checks.Queues gives it.
Parameter HOUR = 3600;

Parameter QUEUEMESSAGES = "checks.thresholds.queueMessages";

Parameter QUEUEWAIT = "checks.thresholds.queueWaitMinutes";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the checks of the test being run, comma-separated (the probe's Only).
Property Checks As %String(MAXLEN = "");

/// The number of the newest row of the event log when the test began.
Property LogMark As %Integer;

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("ChecksQueues", "n"))
	Kill ^||QueuesTest
	For key = ..#QUEUEMESSAGES, ..#QUEUEWAIT {
		Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
		Set ^||QueuesTest(key) = $ListBuild($IsObject(row), $Select($IsObject(row): row.Value, 1: ""))
	}
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Checks = ""
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do $ClassMethod(..#PROBE, "Reset")
	Do ##class(OcuTalon.Data.Setting).Set(..#QUEUEMESSAGES, 100)
	Do ##class(OcuTalon.Data.Setting).Set(..#QUEUEWAIT, 10)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	Do ..PutBack()
	For i = 1:1:$Length(..Checks, ",") {
		Set ref = $Piece(..Checks, ",", i)
		If ref = "" Continue
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "RunQueues", $Parameter(..#PROBE, "LOGREAD")_ref)
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Record", $Parameter(..#PROBE, "LOGFINDING")_ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGRAN")_ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.CheckRun WHERE CheckRef = ?", ref)
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Set ..Checks = ""
	Do $ClassMethod(..#PROBE, "Reset")
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	Do ..PutBack()
	Kill ^||QueuesTest
	Quit $$$OK
}

/// Puts each threshold setting back as it was before the class began: its value, or no row when it had none.
Method PutBack()
{
	Set key = ""
	For {
		Set key = $Order(^||QueuesTest(key), 1, was)
		Quit:key=""
		If $List(was, 1) {
			Do ##class(OcuTalon.Data.Setting).Set(key, $List(was, 2))
		} Else {
			Set row = ##class(OcuTalon.Data.Setting).KeyIndexOpen(key)
			If $IsObject(row) Do ##class(OcuTalon.Data.Setting).%DeleteId(row.%Id())
			Kill ^||OcuTalon.Setting(key)
		}
	}
}

/// The one rule of a queue.
Method TestOver()
{
	Set limit = {"queueMessages": 100, "queueWaitMinutes": 10}
	Set now = ##class(OcuTalon.Data.Time).Seconds(..#TICK)
	Do $$$AssertEquals(##class(OcuTalon.Checks.Queues).Over(..Queue("A", 101, ..Ago(60)), limit, now, .byCount, .waited), 1, "101 messages are above")
	Do $$$AssertEquals(byCount_"|"_waited, "1|0", "by count, not by age")
	Do $$$AssertEquals(##class(OcuTalon.Checks.Queues).Over(..Queue("A", 100, ..Ago(540)), limit, now, .byCount, .waited), 0, "100 messages that waited 9 minutes are not above")
	Do $$$AssertEquals(byCount_"|"_waited, "0|0", "by neither")
	Do $$$AssertEquals(##class(OcuTalon.Checks.Queues).Over(..Queue("A", 3, ..Ago(660)), limit, now, .byCount, .waited), 1, "3 messages that waited 11 minutes are above")
	Do $$$AssertEquals(byCount_"|"_waited, "0|660", "by age, with the seconds waited")
	Do $$$AssertEquals(##class(OcuTalon.Checks.Queues).Over(..Queue("A", 3, ..Ago(600)), limit, now, .byCount, .waited), 0, "exactly 10 minutes is not more than 10 minutes")
	Do $$$AssertEquals(##class(OcuTalon.Checks.Queues).Over(..Queue("A", 3, ..Ago(601)), limit, now, .byCount, .waited), 1, "601 seconds is")
	Do $$$AssertEquals(##class(OcuTalon.Checks.Queues).Over(..Queue("A", 0, ..Ago(900)), limit, now, .byCount, .waited), 0, "an empty queue is never above by age")
	Do $$$AssertEquals(waited, 0, "and has waited nothing")
	Do $$$AssertEquals(##class(OcuTalon.Checks.Queues).Over(..Queue("A", 3, ""), limit, now, .byCount, .waited), 0, "an oldest time that is empty is not above by age")
	Do $$$AssertEquals(##class(OcuTalon.Checks.Queues).Over(..Queue("A", 3, "not a time"), limit, now, .byCount, .waited), 0, "nor one that is unreadable")
	Do $$$AssertEquals(##class(OcuTalon.Checks.Queues).Over(..Queue("A", 101, ..Ago(900)), limit, now, .byCount, .waited), 1, "both rules at once")
	Do $$$AssertEquals(byCount_"|"_waited, "1|900", "give both results")
	Do $$$AssertEquals(##class(OcuTalon.Checks.Queues).Over(..Queue("A", 6, ..Ago(60)), {"queueMessages": 5, "queueWaitMinutes": 10}, now, .byCount), 1, "the limits are the caller's: 6 messages are above 5")
}

/// The reporting rule, pure (matrix rows 1 to 5 and 7). A reading at offset n is taken n seconds after TICK, and its ages are as old at that time.
Method TestCrossings()
{
	Set limit = {"queueMessages": 100, "queueWaitMinutes": 10}
	Set now = ##class(OcuTalon.Data.Time).Seconds(..#TICK)
	Set found = ##class(OcuTalon.Checks.Queues).Crossings("", ..Reading("N", 0, "A=101=30,B=100=30,C=3=660"), limit, now, .first)
	Do $$$AssertEquals(..Items(found), "N|NN|A|101,N|NN|C|3", "the first run reports every queue that is above, in queue order, with its namespace, display name and count")
	Do $$$AssertEquals(found.%Get(0).oldestAt, ..Ago(30), "and the oldest message's time")
	Do $$$AssertEquals(..Above(first, "N"), "A,C", "Reported holds them in above")
	Set found = ##class(OcuTalon.Checks.Queues).Crossings(first, ..Reading("N", 60, "A=101=30,B=100=30,C=3=660"), limit, now + 60, .second)
	Do $$$AssertEquals(found.%Size(), 0, "the next run reports none of them")
	Do $$$AssertEquals(..Above(second, "N"), "A,C", "and they stay in above")
	Set found = ##class(OcuTalon.Checks.Queues).Crossings(second, ..Reading("N", 120, "A=100=540,B=5=60"), limit, now + 120, .third)
	Do $$$AssertEquals(found.%Size(), 0, "a queue that falls below is not reported, and one that is gone is not either")
	Do $$$AssertEquals(..Above(third, "N"), "", "A and C leave above")
	Set found = ##class(OcuTalon.Checks.Queues).Crossings(third, ..Reading("N", 120 + ..#HOUR, "A=101=30,B=100=30,C=3=660"), limit, now + 120 + ..#HOUR, .fourth)
	Do $$$AssertEquals(..Items(found), "N|NN|A|101,N|NN|C|3", "after the cooldown, a queue that is above again is reported once more")
	Do $$$AssertEquals(..Above(fourth, "N"), "A,C", "and enters above")
	Set found = ##class(OcuTalon.Checks.Queues).Crossings("", ..Reading("N", 0, ""), limit, now, .none)
	Do $$$AssertEquals(found.%Size()_"|"_none, "0|{""above"":{}}", "nothing above is {""above"":{}}: only non-empty lists, and no told member without an entry")
	Set readings = ..Reading("N", 0, "A=101=30,B=100=30,C=3=660")
	For previous = "not json", "[1]", "7", """text""", "{""above"": 5}", "{""above"": {""N"": ""A""}}", "{""above"": {""N"": 5}}" {
		Set found = ##class(OcuTalon.Checks.Queues).Crossings(previous, readings, limit, now, .any)
		Do $$$AssertEquals(found.%Size(), 2, "a previous of "_previous_" is no baseline: everything above is new")
	}
	Set previous = {"above": {"N": ["A"], "M": ["Z"], "L": ["Y"]}}.%ToJSON()
	Set two = ..Reading("M", 0, "Z=5=30,W=200=30")
	Do two.%Push({"namespace": "N", "production": "Zz.N", "displayName": "NN", "read": 0, "queues": []})
	Set found = ##class(OcuTalon.Checks.Queues).Crossings(previous, two, limit, now, .kept)
	Do $$$AssertEquals(..Items(found), "M|MM|W|200", "an unread namespace reports nothing, and a read one reports its new queue")
	Do $$$AssertEquals(..Above(kept, "N")_"|"_..Above(kept, "M")_"|"_..Above(kept, "L"), "A|W|Y", "the unread namespace keeps its list, the read one has its own, and a namespace that is not in the readings keeps its list")
	Set found = ##class(OcuTalon.Checks.Queues).Crossings(previous, ..Reading("N", 0, "A=101=30"), limit, now, .again)
	Do $$$AssertEquals(found.%Size(), 0, "a queue in the previous list of a read namespace is not new")
}

/// The once-an-hour rule (AC12; the Contest Planner's ruling), pure.
Method TestCooldown()
{
	Set limit = {"queueMessages": 100, "queueWaitMinutes": 10}
	Set start = ##class(OcuTalon.Data.Time).Seconds(..#TICK)
	Set found = ##class(OcuTalon.Checks.Queues).Crossings("", ..Reading("N", 0, "A=101=30"), limit, start, .t0)
	Do $$$AssertEquals(..Items(found), "N|NN|A|101", "T: reported")
	Do $$$AssertEquals(..Told(t0, "N", "A"), ..#TICK, "its told time is the run time")
	Set found = ##class(OcuTalon.Checks.Queues).Crossings(t0, ..Reading("N", 300, "A=50=30"), limit, start + 300, .t1)
	Do $$$AssertEquals(found.%Size()_"|"_..Above(t1, "N"), "0|", "T+5 min below: nothing, and A leaves above")
	Do $$$AssertEquals(..Told(t1, "N", "A"), ..#TICK, "but its told time stays")
	Set found = ##class(OcuTalon.Checks.Queues).Crossings(t1, ..Reading("N", 600, "A=101=30,B=101=30"), limit, start + 600, .t2)
	Do $$$AssertEquals(..Items(found), "N|NN|B|101", "T+10 min backs up again: A is held back, and B, a different queue of the namespace, is reported")
	Do $$$AssertEquals(..Above(t2, "N"), "B", "A is not in above")
	Set found = ##class(OcuTalon.Checks.Queues).Crossings(t2, ..Reading("N", 3599, "A=101=30,B=101=30"), limit, start + 3599, .t3)
	Do $$$AssertEquals(found.%Size()_"|"_..Above(t3, "N"), "0|B", "one second short of the hour it is still held back")
	Set found = ##class(OcuTalon.Checks.Queues).Crossings(t3, ..Reading("N", 3660, "A=101=30,B=101=30"), limit, start + 3660, .t4)
	Do $$$AssertEquals(..Items(found), "N|NN|A|101", "T+61 min, still above: reported once, so a stuck queue is never silenced for good")
	Do $$$AssertEquals(..Above(t4, "N"), "A,B", "and it enters above")
	Do $$$AssertEquals(..Told(t4, "N", "A"), ##class(OcuTalon.Data.Time).AddSeconds(..#TICK, 3660), "with the new told time")
	Set found = ##class(OcuTalon.Checks.Queues).Crossings(t4, ..Reading("N", 3700, "A=50=30"), limit, start + 3700, .t5)
	Set found = ##class(OcuTalon.Checks.Queues).Crossings(t5, ..Reading("N", 3800, "A=101=30"), limit, start + 3800, .t6)
	Do $$$AssertEquals(found.%Size()_"|"_..Above(t6, "N"), "0|", "it flaps within the next hour: nothing more")
	Set found = ##class(OcuTalon.Checks.Queues).Crossings(t6, ..Reading("N", 3660 + ..#HOUR, "A=50=30"), limit, start + 3660 + ..#HOUR, .t7)
	Do $$$AssertEquals(..Told(t7, "N", "A"), "", "a told time of an hour or more is dropped from the new Reported")
	Set found = ##class(OcuTalon.Checks.Queues).Crossings(t7, ..Reading("N", 3660 + ..#HOUR + 60, "A=101=30"), limit, start + 3660 + ..#HOUR + 60, .t8)
	Do $$$AssertEquals(..Items(found), "N|NN|A|101", "and a queue that backs up after that is reported")
	Set found = ##class(OcuTalon.Checks.Queues).Crossings("{""told"": {""N"": {""A"": ""not a time""}}}", ..Reading("N", 0, "A=101=30"), limit, start, .t9)
	Do $$$AssertEquals(..Items(found), "N|NN|A|101", "a told time that is unreadable holds nothing back")
	Set told = {"above": {}, "told": {"N": {"A": "2030-06-01T11:59:30Z"}}}.%ToJSON()
	Set found = ##class(OcuTalon.Checks.Queues).Crossings(told, [{"namespace": "N", "production": "Zz.N", "displayName": "NN", "read": 0, "queues": []}], limit, start, .t10)
	Do $$$AssertEquals(..Told(t10, "N", "A"), "2030-06-01T11:59:30Z", "an unread namespace keeps its told time too")
}

/// Matrix row "First run, above" with the reads and the record (AC2).
Method TestFirstRun()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Owner("first")
	Set trace = ..TraceOf(session)
	Set ref = ..Row(session)
	Do $ClassMethod(..#PROBE, "FeedEntries", [{"namespace": "ZZQA", "production": "Zz.QA", "displayName": "QA"}, {"namespace": "ZZQB", "production": "Zz.QB", "displayName": "QB"}])
	Set oldest = ..Back(30)
	Do ..Feed("ZZQA", [(..Queue("A", 101, oldest)), (..Queue("B", 100, oldest)), (..Queue("C", 3, ..Back(660)))])
	Do ..Feed("ZZQB", [(..Queue("D", 150, oldest)), (..Queue("E", 1, ..Back(700)))])
	Do ..Tick(host, ..At(0))
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "failed|4 queues over their threshold", "the row is failed, and says how many queues")
	Set items = ..FindingItems()
	Do $$$AssertEquals(items.%Size(), 4, "four Items were sent")
	If items.%Size() = 4 {
		Set names = ""
		For i = 0:1:3 {
			Set item = items.%Get(i)
			Set names = names_$ListBuild(..Slot(item.slots, "itemName"))
			Do $$$AssertEquals(item.sessionRef_"|"_item.channel_"|"_item.provenance_"|"_item.catalogKey, session_"|system|untrusted|watch.queueBacklog", "item "_(i + 1)_": the session, channel system, untrusted, the catalog key")
			Do $$$AssertEquals(item.sessionId_"|"_item.superSession, "|"_trace, "item "_(i + 1)_": in a trace session of its own with the session's TraceRef as SuperSession (AD-26)")
			Do $$$AssertEquals(..Slot(item.slots, "production"), $Select(i < 2: "QA", 1: "QB"), "item "_(i + 1)_": the production's display name")
		}
		Do $$$AssertEquals($ListToString(names), "A,C,D,E", "in reading order and queue order")
		Set first = items.%Get(0)
		Do $$$AssertEquals(first.text, "The A queue in the QA production has 101 messages waiting.", "the text of the Item")
		Do $$$AssertEquals(..Slot(first.slots, "count")_"|"_..Slot(first.slots, "oldestAt"), "101|"_oldest, "its count and the oldest message's time")
		Do $$$AssertEquals(items.%Get(3).text, "The E queue in the QB production has 1 message waiting.", "the text for one message")
		Do $$$AssertTrue(..Slot(first.slots, "time") ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "and the run's time")
	}
	Do $$$AssertEquals(..Above(row.Reported, "ZZQA")_"|"_..Above(row.Reported, "ZZQB"), "A,C|D,E", "Reported holds the queues that are above, by namespace")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "EntryCalls"), 1, "the entries were listed once")
	Set calls = $ClassMethod(..#PROBE, "QueueCalls")
	Do $$$AssertEquals(calls.%Size()_"|"_calls.%Get(0).namespace_"|"_calls.%Get(0).production_"|"_calls.%Get(1).namespace_"|"_calls.%Get(1).production, "2|ZZQA|Zz.QA|ZZQB|Zz.QB", "and the queues of each entry were read, and nothing else")
	Do $$$AssertEquals(row.LastRunHeaderId, ..#SESSIONID, "the row holds the run's trace session")
	Do $$$AssertEquals(row.NextDueAt, ..At(1), "the next due time is the Tick plus 60 seconds")
	Set events = ##class(OcuTalon.Test.Core.Observe).Events(session, "check")
	Do $$$AssertEquals(events.%Size(), 1, "one check event was published")
	If events.%Size() = 1 Do $$$AssertEquals(events.%Get(0).payload.%ToJSON(), ..ViewOf(ref), "FromRow of the row after the run")
	Do $$$AssertEquals(..Ran(ref), 1, "and one line names the run")
	Set run = ..RunOf(ref)
	Do $$$AssertEquals(run.result_"|"_run.reason_"|"_run.finding, "failed||4 queues over their threshold", "the CheckRun holds the run")
	Set one = ..Owner("firstOne")
	Set oneRef = ..Row(one)
	Do ..Feed("ZZQA", [(..Queue("A", 101, ..Back(30)))])
	Do ..Feed("ZZQB", [])
	Do ..Tick(host, ..At(0))
	Do $$$AssertEquals(..Stored(oneRef).Result_"|"_..Stored(oneRef).Finding, "failed|1 queue over its threshold", "one queue is said in the singular")
}

/// Matrix row "Still above" (AC3).
Method TestStillAbove()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Owner("still")
	Set ref = ..Row(session)
	Do $ClassMethod(..#PROBE, "FeedEntries", [{"namespace": "ZZQA", "production": "Zz.QA", "displayName": "QA"}])
	Do ..Feed("ZZQA", [(..Queue("A", 101, ..Back(30)))])
	Do ..Tick(host, ..At(0))
	Do $$$AssertEquals(..FindingItems().%Size(), 1, "the first run sent one Item")
	Do ..Feed("ZZQA", [(..Queue("A", 150, ..Back(90)))])
	Do ..Tick(host, ..At(1))
	Do $$$AssertEquals(..FindingItems().%Size(), 1, "the next run, with the queue still above, sent none")
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "failed|1 queue over its threshold", "and the row is still failed")
	Do $$$AssertEquals(..Above(row.Reported, "ZZQA"), "A", "with the queue in above")
}

/// Matrix row "Falls below, rises again" (AC3): the queue drops below, or is gone, and backs up again after the cooldown.
Method TestFallsBelowRisesAgain()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Owner("falls")
	Set ref = ..Row(session)
	Do $ClassMethod(..#PROBE, "FeedEntries", [{"namespace": "ZZQA", "production": "Zz.QA", "displayName": "QA"}])
	Do ..Feed("ZZQA", [(..Queue("A", 101, ..Back(30)))])
	Do ..Tick(host, ..At(0))
	Do $$$AssertEquals(..FindingItems().%Size(), 1, "the first run sent one Item")
	Do ..Feed("ZZQA", [(..Queue("A", 100, ..Back(540)))])
	Do ..Tick(host, ..At(1))
	Set row = ..Stored(ref)
	Do $$$AssertEquals(..FindingItems().%Size()_"|"_row.Result_"|"_row.Finding, "1|passed|", "100 messages that waited 9 minutes: no Item, and the row is passed")
	Do $$$AssertEquals(..Above(row.Reported, "ZZQA"), "", "A left above")
	Do $$$AssertStatusOK(..Age(ref), "the told times are two hours old")
	Do ..Feed("ZZQA", [(..Queue("A", 101, ..Back(30)))])
	Do ..Tick(host, ..At(2))
	Do $$$AssertEquals(..FindingItems().%Size(), 2, "above again after the cooldown: one more Item")
	Do ..Feed("ZZQA", [])
	Do ..Tick(host, ..At(3))
	Set row = ..Stored(ref)
	Do $$$AssertEquals(..FindingItems().%Size()_"|"_row.Result, "2|passed", "gone from the list: no Item, passed")
	Do $$$AssertStatusOK(..Age(ref), "the told times are two hours old")
	Do ..Feed("ZZQA", [(..Queue("A", 120, ..Back(30)))])
	Do ..Tick(host, ..At(4))
	Do $$$AssertEquals(..FindingItems().%Size(), 3, "and above once more: one more Item")
}

/// Matrix row "Age crossing" (AC2).
Method TestAgeCrossing()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Owner("age")
	Set ref = ..Row(session)
	Do $ClassMethod(..#PROBE, "FeedEntries", [{"namespace": "ZZQA", "production": "Zz.QA", "displayName": "QA"}])
	Do ..Feed("ZZQA", [(..Queue("A", 3, ..Back(660)))])
	Do ..Tick(host, ..At(0))
	Set items = ..FindingItems()
	Do $$$AssertEquals(items.%Size(), 1, "3 messages whose oldest waited 11 minutes: one Item")
	If items.%Size() = 1 Do $$$AssertEquals(..Slot(items.%Get(0).slots, "count"), 3, "with count 3")
	Do $$$AssertEquals(..Stored(ref).Result, "failed", "and the row is failed")
}

/// AC12 through a run: reported, below, above again within the hour: no second Item, and the queue stays out of above.
Method TestFlappingThroughARun()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Owner("flap")
	Set ref = ..Row(session)
	Do $ClassMethod(..#PROBE, "FeedEntries", [{"namespace": "ZZQA", "production": "Zz.QA", "displayName": "QA"}])
	Do ..Feed("ZZQA", [(..Queue("A", 101, ..Back(30)))])
	Do ..Tick(host, ..At(0))
	Do ..Feed("ZZQA", [(..Queue("A", 10, ..Back(30)))])
	Do ..Tick(host, ..At(1))
	Do ..Feed("ZZQA", [(..Queue("A", 101, ..Back(30)))])
	Do ..Tick(host, ..At(2))
	Set row = ..Stored(ref)
	Do $$$AssertEquals(..FindingItems().%Size(), 1, "it backed up again within the hour: no second Item")
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "failed|1 queue over its threshold", "the row is still failed: the queue is over its threshold")
	Do $$$AssertEquals(..Above(row.Reported, "ZZQA"), "", "but it is not in above")
	Do $$$AssertEquals(..Told(row.Reported, "ZZQA", "A") '= "", 1, "and its told time is kept")
	Do $$$AssertStatusOK(..Age(ref), "the told times are two hours old")
	Do ..Tick(host, ..At(3))
	Do $$$AssertEquals(..FindingItems().%Size(), 2, "the first run after the hour that still finds it above sends one")
}

/// AC6: the limits are read on every run, and a value that is not a number is the default.
Method TestAdminThreshold()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Owner("admin")
	Set ref = ..Row(session)
	Do $ClassMethod(..#PROBE, "FeedEntries", [{"namespace": "ZZQA", "production": "Zz.QA", "displayName": "QA"}])
	Do ..Feed("ZZQA", [(..Queue("A", 6, ..Back(30)))])
	Do ..Tick(host, ..At(0))
	Do $$$AssertEquals(..FindingItems().%Size()_"|"_..Stored(ref).Result, "0|passed", "6 messages are not above the default")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set(..#QUEUEMESSAGES, 5), "an admin sets queueMessages to 5")
	Do $$$AssertEquals(##class(OcuTalon.Checks.Coverage).CurrentLimits().queueMessages, 5, "CurrentLimits reads it")
	Do ..Tick(host, ..At(1))
	Set items = ..FindingItems()
	Do $$$AssertEquals(items.%Size()_"|"_..Stored(ref).Result, "1|failed", "6 messages are above 5 on the next run")
	If items.%Size() = 1 Do $$$AssertEquals(..Slot(items.%Get(0).slots, "count"), 6, "with count 6")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set(..#QUEUEMESSAGES, "many"), "a value that is not a number is stored")
	Do $$$AssertEquals(##class(OcuTalon.Checks.Coverage).CurrentLimits().queueMessages, 100, "CurrentLimits reads the default for it")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set(..#QUEUEMESSAGES, 100), "the default is back")
	Do $$$AssertStatusOK(##class(OcuTalon.Data.Setting).Set(..#QUEUEWAIT, 1), "queueWaitMinutes is 1")
	Do $$$AssertEquals(##class(OcuTalon.Checks.Coverage).CurrentLimits().queueWaitMinutes, 1, "CurrentLimits reads it")
	Do ..Feed("ZZQA", [(..Queue("A", 3, ..Back(90))), (..Queue("B", 3, ..Back(30)))])
	Do ..Tick(host, ..At(2))
	Do $$$AssertEquals(..Above(..Stored(ref).Reported, "ZZQA"), "A", "an oldest message that waited 90 seconds is above 1 minute, and 30 seconds is not")
}

/// Matrix rows "Namespace unread" (AC4): each way a namespace is unread, in the first and the second position.
Method TestNamespaceUnread()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set cases = $ListBuild($ListBuild("throws", {"throw": "boom"}.%ToJSON(), "Couldn't be read"), $ListBuild("unreadable", {"outcome": "unreadable", "queues": []}.%ToJSON(), "No read access to its namespace"), $ListBuild("not current", {"outcome": "not_current", "queues": []}.%ToJSON(), "No longer its namespace's production"), $ListBuild("queues given as an empty string", {"outcome": "read", "queues": ""}.%ToJSON(), "Couldn't be read"))
	For i = 1:1:$ListLength(cases) {
		Set case = $List(cases, i)
		Set label = $List(case, 1)
		Set session = ..Owner("unread"_i)
		Set ref = ..Row(session)
		Set floor = ..FindingItems().%Size()
		Do $ClassMethod(..#PROBE, "FeedEntries", [{"namespace": "ZZQA", "production": "Zz.QA", "displayName": "QA"}, {"namespace": "ZZQB", "production": "Zz.QB", "displayName": "QB"}])
		Do ..Feed("ZZQA", [(..Queue("A", 101, ..Back(30)))])
		Do ..Feed("ZZQB", [(..Queue("D", 150, ..Back(30)))])
		Do ..Tick(host, ..At(0))
		Do $$$AssertEquals(..FindingItems().%Size() - floor, 2, label_": the first run reports both")
		Do ..Feed("ZZQA", [(..Queue("A", 101, ..Back(30))), (..Queue("F", 120, ..Back(30)))])
		Do $ClassMethod(..#PROBE, "FeedQueues", "ZZQB", ##class(%DynamicObject).%FromJSON($List(case, 2)))
		#; The second run falls in another second than the first, so that its LastRunAt changes and the CheckRun is written (Coverage.RecordRun).
		Hang 1.1
		Do ..Tick(host, ..At(1))
		Set row = ..Stored(ref)
		Do $$$AssertEquals(row.Result_"|"_row.Finding, "not_checked|"_$List(case, 3), label_": not_checked with the reason, never passed")
		Do $$$AssertEquals(..FindingItems().%Size() - floor, 3, label_": the read namespace's new crossing is still sent")
		Do $$$AssertEquals(..Above(row.Reported, "ZZQA")_"|"_..Above(row.Reported, "ZZQB"), "A,F|D", label_": the unread namespace keeps its previous list")
		Set run = ..RunOf(ref)
		Do $$$AssertEquals(run.result_"|"_run.reason, "not_checked|"_$Case($List(case, 3), "Couldn't be read": "error", : "unreachable"), label_": the CheckRun holds the reason")
		Do ..Feed("ZZQB", [(..Queue("D", 150, ..Back(30)))])
		Do ..Tick(host, ..At(2))
		Do $$$AssertEquals(..FindingItems().%Size() - floor, 3, label_": read again, the queue that stayed above is not reported again")
		Do $$$AssertEquals(..Stored(ref).Result, "failed", label_": and the row is failed")
		If label = "throws" Do $$$AssertEquals(..Warnings("RunQueues", $Parameter(..#PROBE, "LOGREAD")_ref), 1, label_": one warning for the read that threw")
	}
	Set session = ..Owner("unreadFirst")
	Set ref = ..Row(session)
	Do $ClassMethod(..#PROBE, "FeedEntries", [{"namespace": "ZZQA", "production": "Zz.QA", "displayName": "QA"}, {"namespace": "ZZQB", "production": "Zz.QB", "displayName": "QB"}])
	Do $ClassMethod(..#PROBE, "FeedQueues", "ZZQA", {"outcome": "not_current", "queues": []})
	Do $ClassMethod(..#PROBE, "FeedQueues", "ZZQB", {"outcome": "unreadable", "queues": []})
	Do ..Tick(host, ..At(0))
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding, "not_checked|No longer its namespace's production", "two unread namespaces: the reason of the first in list order")
}

/// Matrix rows "List unreadable" and "Empty list" (AC4).
Method TestListUnreadable()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Owner("list")
	Set ref = ..Row(session)
	Set before = {"above": {"ZZQA": ["A"]}}.%ToJSON()
	Do $$$AssertEquals(##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET Reported = ? WHERE Ref = ?", before, ref).%SQLCODE, 0, "the row has something reported")
	Do $ClassMethod(..#PROBE, "FeedEntries", {"throw": "the list is refused"})
	Do ..Tick(host, ..At(0))
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding_"|"_row.Reported, "not_checked|Couldn't be read|"_before, "a list that throws: not_checked, Couldn't be read, Reported unchanged")
	Do $$$AssertEquals(..FindingItems().%Size(), 0, "and no Item")
	Do $$$AssertEquals(..Warnings("RunQueues", $Parameter(..#PROBE, "LOGREAD")_ref), 1, "with one warning")
	Do $$$AssertEquals(..RunOf(ref).reason, "error", "and the CheckRun's reason is error")
	Do $ClassMethod(..#PROBE, "FeedEntries", [])
	Do ..Tick(host, ..At(1))
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result_"|"_row.Finding_"|"_row.Reported, "not_checked|Couldn't be read|"_before, "an empty list: the same, never passed on nothing")
	Do $$$AssertEquals(..FindingItems().%Size(), 0, "no Item")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "QueueCalls").%Size(), 0, "and no queue was read")
}

/// Matrix row "Stopped meanwhile".
Method TestStoppedMeanwhile()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Owner("gone")
	Set ref = ..Row(session)
	Do $ClassMethod(..#PROBE, "FeedEntries", [{"namespace": "ZZQA", "production": "Zz.QA", "displayName": "QA"}])
	Do $ClassMethod(..#PROBE, "FeedQueues", "ZZQA", {"queues": [(..Queue("A", 101, ..Back(30)))], "delete": (ref)})
	Do ..Tick(host, ..At(0))
	Do $$$AssertEquals($IsObject(##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)), 0, "the row stays deleted")
	Do $$$AssertEquals(..FindingItems().%Size(), 0, "no Item was sent")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "check").%Size(), 0, "no event was published")
	Do $$$AssertEquals(..Ran(ref), 0, "and no run was logged")
}

/// Matrix row "Send fails".
Method TestSendFails()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Owner("send")
	Set ref = ..Row(session)
	Do $ClassMethod(..#PROBE, "FeedEntries", [{"namespace": "ZZQA", "production": "Zz.QA", "displayName": "QA"}])
	Do ..Feed("ZZQA", [(..Queue("Aqueue", 101, ..Back(30))), (..Queue("Bqueue", 102, ..Back(30)))])
	Do $ClassMethod(..#PROBE, "FailFindings", "The Aqueue queue")
	Do ..Tick(host, ..At(0))
	Do $$$AssertEquals(..FindingItems().%Size(), 2, "both Items were sent: the failing send does not stop the other")
	Do $$$AssertEquals(..Warnings("Record", $Parameter(..#PROBE, "LOGFINDING")_ref), 1, "one warning for the one that failed")
	Do ..Tick(host, ..At(1))
	Do $$$AssertEquals(..FindingItems().%Size(), 2, "the failed one is not sent again: its crossing is already reported")
	Do $$$AssertEquals(..Above(..Stored(ref).Reported, "ZZQA"), "Aqueue,Bqueue", "Reported holds both")
}

/// A row that is not due does not run; one that is due runs once and is next due a minute after the Tick.
Method TestDue()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Owner("due")
	Set ref = ..Row(session, ..At(2))
	Set other = ..Owner("dueOther")
	Set otherRef = ..Row(other, "", "zzother")
	Do $ClassMethod(..#PROBE, "FeedEntries", [{"namespace": "ZZQA", "production": "Zz.QA", "displayName": "QA"}])
	Do ..Feed("ZZQA", [(..Queue("A", 101, ..Back(30)))])
	Do ..Tick(host, ..At(0))
	Do $$$AssertEquals(..Stored(ref).LastRunAt_"|"_..Stored(otherRef).LastRunAt, "|", "a row due in two minutes did not run, and a row of another kind did not")
	Do ..Tick(host, ..At(2))
	Set row = ..Stored(ref)
	Do $$$AssertEquals((row.LastRunAt '= "")_"|"_row.NextDueAt, "1|"_..At(3), "at its time it ran, and it is next due the Tick plus 60 seconds")
	Do $$$AssertEquals(..Stored(otherRef).LastRunAt, "", "the other kind still did not")
	Do ..Tick(host, ..At(2))
	Do $$$AssertEquals(..Ran(ref), 1, "a second Tick with the same time ran nothing")
}

/// Each Item's key and slots render to the catalog's text (AD-32), on the web channel on a local install and on the online demo, for many messages and for one.
Method TestQueueFindingRenders()
{
	Set host = ..Host()
	If '$IsObject(host) Quit
	Set session = ..Owner("render")
	Set ref = ..Row(session)
	Do $ClassMethod(..#PROBE, "FeedEntries", [{"namespace": "ZZQA", "production": "Zz.QA", "displayName": "Zz QA"}])
	Do ..Feed("ZZQA", [(..Queue("A", 105, ..Back(700))), (..Queue("B", 1, ..Back(900)))])
	Do ..Tick(host, ..At(0))
	Set items = ..FindingItems()
	Do $$$AssertEquals(items.%Size(), 2, "two Items")
	If items.%Size() '= 2 Quit
	Set why = $Char(10)_"Why now: you asked me to watch queue backlogs."
	For online = 0, 1 {
		Set suffix = $Select(online: " ET", 1: "")
		For n = 0, 1 {
			Set slots = items.%Get(n).slots
			Set now = ..Slot(slots, "time")
			Set clock = ##class(OcuTalon.Data.Time).ForMessage(now, now)_suffix
			Set oldest = ##class(OcuTalon.Data.Time).ForMessage(..Slot(slots, "oldestAt"), now)_suffix
			Set name = $Select(n = 0: "A", 1: "B")
			Set expected = "The "_name_" queue in the Zz QA production had "_$Select(n = 0: "105 messages", 1: "1 message")_" waiting at "_clock_", "_$Select(n = 0: "the oldest since ", 1: "since ")_oldest_"."_why
			Set text = ##class(OcuTalon.Msg.Catalog).RenderAt(items.%Get(n).catalogKey, slots, "web", now, online, .sc)
			Do $$$AssertStatusOK(sc, "item "_(n + 1)_" renders on the web channel, online demo "_online)
			Do $$$AssertEquals(text, expected, "item "_(n + 1)_": the catalog's text, online demo "_online)
		}
	}
	Do ..Feed("ZZQA", [(..Queue("A", 105, ..Back(700))), (..Queue("B", 1, ..Back(900))), (..Queue("C", 101, ""))])
	Do ..Tick(host, ..At(1))
	Set items = ..FindingItems()
	Do $$$AssertEquals(items.%Size(), 3, "a third Item, for C, whose oldest time is unreadable")
	If items.%Size() '= 3 Quit
	Set slots = items.%Get(2).slots
	Do $$$AssertEquals(..Slot(slots, "oldestAt"), ..Slot(slots, "time"), "its oldestAt slot is the run time")
	Do ##class(OcuTalon.Msg.Catalog).RenderAt(items.%Get(2).catalogKey, slots, "web", ..Slot(slots, "time"), 0, .sc)
	Do $$$AssertStatusOK(sc, "and it renders on the web channel")
}

/// --- helpers ---
/// A shadow instance of the probe, in this process, with a known session.
Method Host() As OcuTalon.Test.Checks.QueueProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||"_..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	If $IsObject(host) Set host.%SessionId = ..#SESSIONID
	Quit host
}

/// A fixture session; its Ref is the owner of the fixture check.
Method Owner(name As %String) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzqrs"_..Number_name)
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Quit ref
}

/// A queue-backlog row of the session, of the probe's Kind (or of the kind given), due at the time (at once unless given); its Ref.
Method Row(session As %String, dueAt As %String = "", kind As %String = {$Parameter(..#PROBE, "QUEUEKIND")}) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, "", "", {"Kind": (kind), "DisplayName": "Queue-backlog check", "CreatedAt": "2030-05-01T10:00:00Z", "NextDueAt": (dueAt)})
	Set ..Refs = ..Refs_$Select(..Refs = "": "", 1: ",")_ref
	Set ..Checks = ..Checks_$Select(..Checks = "": "", 1: ",")_ref
	Quit ref
}

/// A Tick of the time, handled by the probe.
Method Tick(host As OcuTalon.Test.Checks.QueueProbe, tickAt As %String)
{
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = tickAt
	Set host.Only = ..Checks
	Do $$$AssertStatusOK(host.OnRequest(tick, .response), "the Tick at "_tickAt_" is answered OK")
}

/// The time of the Tick of step n: TICK plus n minutes.
ClassMethod At(n As %Integer) As %String
{
	Quit ##class(OcuTalon.Bridge.Time).PlusSeconds(..#TICK, 60 * n)
}

/// What ReadQueues answers for the namespace: read, with these queues.
Method Feed(namespace As %String, queues As %DynamicArray)
{
	Do $ClassMethod(..#PROBE, "FeedQueues", namespace, {"outcome": "read", "queues": (queues)})
}

/// The readings of one read namespace taken offset seconds after TICK: specs is "name=count=age,..." with the age in seconds at that time (the oldest message's time is
/// that far back). The namespace's production is Zz.<namespace> and its display name the namespace twice.
ClassMethod Reading(namespace As %String, offset As %Integer, specs As %String) As %DynamicArray
{
	Set queues = []
	For i = 1:1:$Length(specs, ",") {
		Set spec = $Piece(specs, ",", i)
		If spec = "" Continue
		Do queues.%Push(..Queue($Piece(spec, "=", 1), $Piece(spec, "=", 2), ..Ago($Piece(spec, "=", 3) - offset)))
	}
	Quit [{"namespace": (namespace), "production": ("Zz."_namespace), "displayName": (namespace_namespace), "read": 1, "queues": (queues)}]
}

/// A queue as the reader gives it.
ClassMethod Queue(name As %String, count As %Integer, oldestAt As %String) As %DynamicObject
{
	Quit {"name": (name), "count": (count), "oldestAt": (oldestAt)}
}

/// The UTC time that many seconds before TICK: the age of a message at a pure rule, whose nowSeconds is TICK.
ClassMethod Ago(seconds As %Integer) As %String
{
	Quit ##class(OcuTalon.Data.Time).AddSeconds(..#TICK, -seconds)
}

/// The UTC time that many seconds before now: the age of a message at a run, which reads the clock.
ClassMethod Back(seconds As %Integer) As %String
{
	Quit ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -seconds)
}

/// The findings as "namespace|displayName|item|count" joined with a comma.
ClassMethod Items(found As %DynamicArray) As %String
{
	Set text = ""
	Set iterator = found.%GetIterator()
	While iterator.%GetNext(, .one) {
		Set text = text_$Select(text = "": "", 1: ",")_one.namespace_"|"_one.displayName_"|"_one.item_"|"_one.count
	}
	Quit text
}

/// The names in the above list of the namespace in a Reported, comma-separated.
ClassMethod Above(reported As %String, namespace As %String) As %String
{
	Set object = ##class(%DynamicAbstractObject).%FromJSON(reported)
	If object.%GetTypeOf("above") '= "object" Quit ""
	Set list = object.above.%Get(namespace)
	If '$IsObject(list) Quit ""
	Set names = ""
	Set iterator = list.%GetIterator()
	While iterator.%GetNext(, .name) {
		Set names = names_$Select(names = "": "", 1: ",")_name
	}
	Quit names
}

/// The told time of the queue in a Reported, "" when there is none.
ClassMethod Told(reported As %String, namespace As %String, name As %String) As %String
{
	Set object = ##class(%DynamicAbstractObject).%FromJSON(reported)
	If object.%GetTypeOf("told") '= "object" Quit ""
	Set inner = object.told.%Get(namespace)
	Quit $Select($IsObject(inner): inner.%Get(name), 1: "")
}

/// Makes every told time of the row two hours old, as an hour of waiting would: a status, OK or the error of the update.
ClassMethod Age(ref As %String) As %Status
{
	Set row = ..Stored(ref)
	Set object = ##class(%DynamicAbstractObject).%FromJSON(row.Reported)
	Set old = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -2 * ..#HOUR)
	If object.%GetTypeOf("told") = "object" {
		Set iterator = object.told.%GetIterator()
		While iterator.%GetNext(.namespace, .entries) {
			Set inner = entries.%GetIterator()
			While inner.%GetNext(.name) {
				Do entries.%Set(name, old)
			}
		}
	}
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET Reported = ? WHERE Ref = ?", object.%ToJSON(), ref)
	Quit $Select(rs.%SQLCODE < 0: $SYSTEM.Status.Error(5001, rs.%Message), 1: $$$OK)
}

/// The row as stored now (Checks changes it with SQL, so an object that the test opened before is reloaded).
ClassMethod Stored(ref As %String) As OcuTalon.Data.BackgroundCheck
{
	Set row = ##class(OcuTalon.Data.BackgroundCheck).RefIndexOpen(ref)
	If $IsObject(row) Do row.%Reload()
	Quit row
}

/// The TraceRef of a fixture session.
ClassMethod TraceOf(session As %String) As %String
{
	Quit ##class(OcuTalon.Data.Session).RefIndexOpen(session).TraceRef
}

/// The finding Items that the probe sent, in order.
ClassMethod FindingItems() As %DynamicArray
{
	Quit $ClassMethod(..#PROBE, "FindingItems")
}

/// The slot of an Item's JSON slots.
ClassMethod Slot(slots As %String, name As %String) As %String
{
	Quit ##class(%DynamicAbstractObject).%FromJSON(slots).%Get(name)
}

/// The JSON of FromRow of the row of the Ref.
ClassMethod ViewOf(ref As %String) As %String
{
	Do ##class(OcuTalon.Live.Payload.Check).FromRow(..Stored(ref)).%JSONExportToString(.json)
	Quit json
}

/// The newest CheckRun of the check as {result, reason, finding}.
ClassMethod RunOf(ref As %String) As %DynamicObject
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Result, Reason, Finding FROM OcuTalon_Digest_Data.CheckRun WHERE CheckRef = ? ORDER BY ID DESC", ref)
	If rs.%Next() Quit {"result": (rs.%Get("Result")), "reason": (rs.%Get("Reason")), "finding": (rs.%Get("Finding"))}
	Quit {"result": "", "reason": "", "finding": ""}
}

/// The number of info lines (Type 4) of runs of the check since the test began.
Method Ran(ref As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGRAN")_ref)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of warnings since the test began that the method logged and that start as given.
Method Warnings(method As %String, start As %String) As %Integer
{
	Quit ##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, method, start)
}

}
