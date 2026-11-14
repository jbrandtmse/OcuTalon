/// The run of a source row in Checks (Story 22.11; AD-5, AD-18, AD-21, AD-30, AD-33), the QueueProbe pattern: Test.Mcp.SourceProbe replaces the seams of Checks.Process (the send of a
/// poll, the tool's classification, the stop notice), the tests call OnRequest with real Tick objects and OnResponse with the Replies of Decide, over fixture sessions and rows of
/// Test.Data.Fixture, and read the rows, the CheckRun rows, the Items that Record sent and the polls that were sent. No production, no MCP server and no model is needed, and the rows are
/// of the probe's Kind (zzsources), which the production's own Checks never runs. The probe keeps a fixed time in 2030 (TICK); a run's own time is the clock's.
///   - TestFirstRunBaseline (matrix 1, AC "each run"): a due Read-only source is sent one request of kind tool and provenance untrusted, with the Ref only as its Input, a new ItemId, the
///     row's session as OwnerRef, channel system and the Tick's trace; its NextDueAt is the tick time plus 15 minutes and the key of the send is <Ref>|<time>; the answer "T-1 open" is the
///     first success, so it records passed, sends no Item, and Reported is {"seen":[<hash>],"baseline":1,"stopped":""}; LastRunHeaderId is the Tick's session, one CheckRun row exists and
///     the check payload carries kind source, the result and intervalMinutes;
///   - TestNewResult (matrix 2): a later answer that is not in seen is one Item (the row's session, channel system, provenance untrusted, Subject the source's name, Text the answer),
///     its hash joins seen, and a send of the Item that fails is one warning and is not sent again;
///   - TestSeenBefore (matrix 3): an answer whose hash is in seen sends no Item; seen keeps the newest 50 hashes, so the oldest answer is new again;
///   - TestEmptyAnswer (matrix 3): an empty answer is passed, never an Item, and not a hash; it can be the baseline;
///   - TestUnreachable, TestTimeout, TestOtherFailure (matrix 4): the words unreachable, timeout and any other, an error status of Decide included, are not_checked with
///     REASONSOURCEUNREACHABLE, REASONTIMEOUT and REASONREAD, and the CheckRun Reason is unreachable, timeout and error; a failed run is never the baseline;
///   - TestStoppedBeforeSend, TestStoppedAfterDenial, TestStoppedChanged (matrix 5): a source whose tool is no longer Read-only makes no poll and records not_checked with
///     REASONNOTREADONLY at once, with Reported.stopped not_read_only (CheckRun Reason stopped); a denial of the gate is stopped only when the tool is no longer Read-only (else error);
///     the words changed and notreadonly are stopped;
///   - TestStoppedNotifiesOnce, TestResume (matrix 5): the stop notice is sent once for each transition, none for the next stopped run, and a classification that is Read-only again
///     polls at the next due time and clears stopped; a stopped run is never the baseline;
///   - TestNextDueAtAtSend (AC "each run"): NextDueAt is the tick time plus the interval from the send on, and the record of the answer leaves it;
///   - TestRemovedMeanwhile (matrix 6): an answer for a source that was removed records nothing: no CheckRun row, no Item, no event;
///   - TestRepointBaseline, TestAnswerBeforeRepoint (matrix 9, DW-1328): after Watch.Ops SetSource moves CreatedAt (a new target), the next success is a baseline again (no Item, seen
///     afresh), and an answer sent before the move records nothing;
///   - TestOnlineDemoNoPoll (matrix 7): with the online demo (the probe's flag, and the real setting) a Tick sends no poll and records nothing, even for a stopped source;
///   - TestStoppedCoverage: a recorded stopped run gives Coverage.Build the line digest.notCheckedStopped;
///   - TestSourceStoppedNotice: Mcp.Ops SourceStopped sends mcp.sourceStopped with the four slots to every admin, and an unreadable list of admins is one warning;
///   - TestStopThroughTheRealSeams: with the real SourceClass (the tool's classification row) and the real StopNotice (Mcp.Ops, through the probe's OPSCLASS), a risky tool is stopped with no poll
///     and the admin's notice names the source, the tool, the server and the time; Read-only again polls;
///   - TestOldestDueFirst: when more sources are due than one Tick may send, the source with the oldest NextDueAt is sent first, whatever the order of the rows;
///   - TestOneInFlightNoQueueStale: with three due sources and polls that wait, one poll is sent at a time, the others keep their NextDueAt and are sent at
///     the next Tick after an answer, each within the interval plus 180 seconds of the first Tick (Coverage MISSEDSECONDS), and a mark that is older than INFLIGHTSECONDS holds nothing.
Class OcuTalon.Test.Mcp.SourceRun Extends %UnitTest.TestCase
{

Parameter PROBE = "OcuTalon.Test.Mcp.SourceProbe";

/// The time of the first Tick.
Parameter TICK = "2030-06-01T12:00:00Z";

/// The id of the session that the probe runs in.
Parameter SESSIONID = 424244;

Parameter SERVER = "zz";

Parameter TOOL = "zz_lookup";

/// The server of the tool whose classification row TestStopThroughTheRealSeams makes.
Parameter REALSERVER = "zzsrunreal";

/// The run's number.
Property Number As %Integer;

/// The Refs of the fixture rows of the test being run, comma-separated.
Property Refs As %String(MAXLEN = "");

/// The Refs of the source rows of the test being run, comma-separated.
Property Checks As %String(MAXLEN = "");

/// The number of the newest row of the event log when the test began.
Property LogMark As %Integer;

/// What the public online-demo setting held before a test changed it, and 1 once one has.
Property SavedDemo As %String;

Property DemoSaved As %Boolean [ InitialExpression = 0 ];

Method OnBeforeAllTests() As %Status
{
	Set ..Number = $Increment(^OcuTalonTest("McpSourceRun", "n"))
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Set ..Refs = ""
	Set ..Checks = ""
	Set ..DemoSaved = 0
	Set ..LogMark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Do $ClassMethod(..#PROBE, "Reset")
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	If ..DemoSaved Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedDemo)
	Set ..DemoSaved = 0
	For i = 1:1:$Length(..Checks, ",") {
		Set ref = $Piece(..Checks, ",", i)
		If ref = "" Continue
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "Record", $Parameter(..#PROBE, "LOGFINDING")_ref)
		Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(..LogMark, "PollSource", $Parameter(..#PROBE, "LOGPOLLSEND")_ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGRAN")_ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Digest_Data.CheckRun WHERE CheckRef = ?", ref)
		Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.BackgroundCheck WHERE Ref = ?", ref)
	}
	If ..Refs '= "" Do ##class(OcuTalon.Test.Data.Fixture).Clean(..Refs)
	Set ..Refs = ""
	Set ..Checks = ""
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Mcp.ToolClassification WHERE Server = ?", ..#REALSERVER)
	Kill ^||ZzOps
	Do $ClassMethod(..#PROBE, "Reset")
	Quit $$$OK
}

/// matrix 1 (see the class description).
Method TestFirstRunBaseline()
{
	Set host = ..Host()
	Set session = ..Owner("first")
	Set ref = ..Source(session, "Jira")
	Do ..Tick(host, ..At(0))
	Set polls = $ClassMethod(..#PROBE, "Polls")
	Do $$$AssertEquals(polls.%Size(), 1, "one poll is sent for the due source")
	If polls.%Size() '= 1 Quit
	Set poll = polls.%Get(0)
	Do $$$AssertEquals(poll.kind _ "|" _ poll.provenance _ "|" _ poll.ownerRef _ "|" _ poll.channel _ "|" _ poll.summary _ "|" _ poll.traceRef, "tool|untrusted|" _ session _ "|system|Source poll|" _ ..TraceOf(session), "a request of kind tool and provenance untrusted, for the row's session, channel system, in its trace")
	Do $$$AssertEquals(poll.input, {"source": (ref)}.%ToJSON(), "its Input is the Ref and nothing else")
	Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).IsRef(poll.itemId) && (poll.itemId '= ref), "its ItemId is a new Ref")
	Do $$$AssertEquals($Piece(poll.key, "|", 1), ref, "the completion key starts with the Ref")
	Do $$$AssertTrue($Piece(poll.key, "|", 2) ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "and ends with the time of the send")
	Do $$$AssertEquals(poll.sessionId, ..#SESSIONID, "the request is sent in the Tick's session")
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.NextDueAt, ##class(OcuTalon.Bridge.Time).PlusSeconds(..At(0), 900), "NextDueAt is the tick time plus 15 minutes, set at the send")
	Do $$$AssertEquals(row.LastRunAt _ "|" _ row.Result, "|", "nothing is recorded before the answer")
	Do ..Answer(host, ref, "T-1 open")
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result _ "|" _ row.Finding _ "|" _ row.LastRunHeaderId, "passed||" _ ..#SESSIONID, "the first success is passed, in the Tick's session")
	Do $$$AssertTrue(row.LastRunAt '= "", "LastRunAt is set")
	Do $$$AssertEquals(row.Reported, "{""seen"":[""" _ ..Hash("T-1 open") _ """],""baseline"":1,""stopped"":""""}", "Reported holds the hash of the answer, the baseline and no stop")
	Do $$$AssertEquals(..FindingItems().%Size(), 0, "the baseline sends no Item")
	Do $$$AssertEquals(..RunOf(ref).result _ "|" _ ..RunCount(ref), "passed|1", "one CheckRun row exists, passed")
	Set view = ##class(%DynamicAbstractObject).%FromJSON(..ViewOf(ref))
	Do $$$AssertEquals(view.kind _ "|" _ view.result _ "|" _ view.intervalMinutes _ "|" _ view.traceHeaderId, $Parameter(..#PROBE, "SOURCEKIND") _ "|passed|15|" _ ..#SESSIONID, "the check payload carries the row's kind, the result, intervalMinutes and the trace header")
}

/// matrix 2 (see the class description).
Method TestNewResult()
{
	Set host = ..Host()
	Set session = ..Owner("new")
	Set ref = ..Source(session, "Jira")
	Do ..Run(host, ref, 0, "T-1 open")
	Do ..Run(host, ref, 1, "T-1 open" _ $Char(10) _ "T-2 open")
	Set items = ..FindingItems()
	Do $$$AssertEquals(items.%Size(), 1, "the new answer is one Item")
	If items.%Size() = 1 {
		Set item = items.%Get(0)
		Do $$$AssertEquals(item.sessionRef _ "|" _ item.channel _ "|" _ item.provenance _ "|" _ item.subject _ "|" _ item.text, session _ "|system|untrusted|Jira|T-1 open" _ $Char(10) _ "T-2 open", "for the row's session, channel system, provenance untrusted, Subject the name and Text the answer")
		Do $$$AssertTrue(##class(OcuTalon.Bridge.Approval).IsRef(item.itemId), "with a new ItemId")
		Do $$$AssertEquals(item.sessionId, "", "sent in a trace session of its own")
		Do $$$AssertEquals(item.superSession, ..TraceOf(session), "with the row's TraceRef as its SuperSession")
	}
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result, "passed", "the run is passed")
	Set reported = ##class(%DynamicAbstractObject).%FromJSON(row.Reported)
	Do $$$AssertEquals(reported.seen.%Size() _ "|" _ reported.seen.%Get(1), "2|" _ ..Hash("T-1 open" _ $Char(10) _ "T-2 open"), "the hash joins seen, newest last")
	// a send that fails is one warning and is not sent again
	Do $ClassMethod(..#PROBE, "FailFindings", "T-3")
	Do ..Run(host, ref, 2, "T-3 open")
	Do $$$AssertEquals(..Warnings("Record", $Parameter(..#PROBE, "LOGFINDING") _ ref), 1, "a failed send of the Item is one warning")
	Do $$$AssertEquals(..Stored(ref).Result, "passed", "the run is still passed")
	Do $ClassMethod(..#PROBE, "FailFindings", "")
	Do ..Run(host, ref, 3, "T-3 open")
	Do $$$AssertEquals(..FindingItems().%Size(), 2, "and it is not sent again: the hash is in seen")
}

/// matrix 3, newest 50 (see the class description).
Method TestSeenBefore()
{
	Set host = ..Host()
	Set ref = ..Source(..Owner("seen"), "Jira")
	Do ..Run(host, ref, 0, "a0")
	Do $$$AssertEquals(..FindingItems().%Size(), 0, "the baseline sends no Item")
	Do ..Run(host, ref, 1, "a0")
	Do $$$AssertEquals(..FindingItems().%Size(), 0, "an answer seen before sends no Item")
	For i = 1:1:52 {
		Do ..Run(host, ref, i + 1, "a" _ i)
	}
	Do $$$AssertEquals(..FindingItems().%Size(), 52, "52 new answers are 52 Items")
	Set reported = ##class(%DynamicAbstractObject).%FromJSON(..Stored(ref).Reported)
	Do $$$AssertEquals(reported.seen.%Size(), 50, "seen keeps the newest 50 hashes")
	Do $$$AssertEquals(reported.seen.%Get(49), ..Hash("a52"), "the newest is last")
	Do ..Run(host, ref, 60, "a52")
	Do ..Run(host, ref, 61, "a30")
	Do $$$AssertEquals(..FindingItems().%Size(), 52, "answers among the newest 50 send nothing")
	Do ..Run(host, ref, 62, "a2")
	Do $$$AssertEquals(..FindingItems().%Size(), 53, "an answer that fell out of the newest 50 is new again")
	Do $$$AssertEquals(##class(%DynamicAbstractObject).%FromJSON(..Stored(ref).Reported).seen.%Size(), 50, "and seen is still 50")
}

/// matrix 3, the empty answer (see the class description).
Method TestEmptyAnswer()
{
	Set host = ..Host()
	Set ref = ..Source(..Owner("empty"), "Jira")
	Do ..Run(host, ref, 0, "")
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result _ "|" _ row.Reported, "passed|{""seen"":[],""baseline"":1,""stopped"":""""}", "an empty first answer is passed and the baseline, with no hash")
	Do ..Run(host, ref, 1, "")
	Do $$$AssertEquals(..Stored(ref).Result _ "|" _ ..FindingItems().%Size(), "passed|0", "an empty answer is passed and never an Item")
	Do ..Run(host, ref, 2, "T-1")
	Do $$$AssertEquals(..FindingItems().%Size(), 1, "and the next answer with text is one")
}

/// matrix 4, the server is down (see the class description).
Method TestUnreachable()
{
	Do ..Failure("unreachable", $Parameter(..#PROBE, "REASONSOURCEUNREACHABLE"), "unreachable")
}

/// matrix 4, no answer in time.
Method TestTimeout()
{
	Do ..Failure("timeout", $Parameter(..#PROBE, "REASONTIMEOUT"), "timeout")
}

/// matrix 4, any other word, and the error status of Decide.
Method TestOtherFailure()
{
	Do ..Failure("failed", $Parameter(..#PROBE, "REASONREAD"), "error")
	Do ..Failure("demo", $Parameter(..#PROBE, "REASONREAD"), "error")
	Do ..Failure("invalid", $Parameter(..#PROBE, "REASONREAD"), "error")
	Do ..Failure("zz unknown word", $Parameter(..#PROBE, "REASONREAD"), "error")
	Do ..Failure("no reply", $Parameter(..#PROBE, "REASONREAD"), "error")
	Do ..Failure("denied", $Parameter(..#PROBE, "REASONREAD"), "error")
	Do ..Failure("error status", $Parameter(..#PROBE, "REASONREAD"), "error")
}

/// matrix 5, before the send (see the class description).
Method TestStoppedBeforeSend()
{
	Set host = ..Host()
	Set session = ..Owner("stopbefore")
	Set ref = ..Source(session, "Jira")
	Do $ClassMethod(..#PROBE, "FeedClass", ..#SERVER, ..#TOOL, "risky")
	Do ..Tick(host, ..At(0))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Polls").%Size(), 0, "no poll is sent for a tool that is no longer Read-only")
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result _ "|" _ row.Finding, "not_checked|" _ $Parameter(..#PROBE, "REASONNOTREADONLY"), "the run is not_checked with REASONNOTREADONLY")
	Do $$$AssertEquals(row.NextDueAt, ##class(OcuTalon.Bridge.Time).PlusSeconds(..At(0), 900), "NextDueAt is the tick time plus the interval")
	Do $$$AssertEquals(##class(%DynamicAbstractObject).%FromJSON(row.Reported).stopped, "not_read_only", "Reported.stopped is not_read_only")
	Do $$$AssertEquals(##class(%DynamicAbstractObject).%FromJSON(row.Reported).baseline, 0, "a stopped run is not the baseline")
	Do $$$AssertEquals(..RunOf(ref).result _ "|" _ ..RunOf(ref).reason, "not_checked|stopped", "the CheckRun Reason is stopped")
	Set stops = $ClassMethod(..#PROBE, "Stops")
	Do $$$AssertEquals(stops.%Size(), 1, "one stop notice is sent")
	If stops.%Size() = 1 Do $$$AssertEquals(stops.%Get(0).source _ "|" _ stops.%Get(0).tool _ "|" _ stops.%Get(0).server _ "|" _ (stops.%Get(0).time = row.LastRunAt), "Jira|" _ ..#TOOL _ "|" _ ..#SERVER _ "|1", "with the source, the tool, the server and the time of the run")
	Do $$$AssertEquals(..FindingItems().%Size(), 0, "no Item is sent")
}

/// matrix 5, after a denial (see the class description).
Method TestStoppedAfterDenial()
{
	Set host = ..Host()
	Set ref = ..Source(..Owner("stopdeny"), "Jira")
	Do ..Tick(host, ..At(0))
	Do ..Answer(host, ref, "", "denied")
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result _ "|" _ row.Finding, "not_checked|" _ $Parameter(..#PROBE, "REASONREAD"), "a denial while the tool is still Read-only is an error, not a stop")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Stops").%Size(), 0, "and sends no stop notice")
	Do $ClassMethod(..#PROBE, "FeedClass", ..#SERVER, ..#TOOL, "unclassified")
	Do ..Answer(host, ref, "", "denied")
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result _ "|" _ row.Finding _ "|" _ ##class(%DynamicAbstractObject).%FromJSON(row.Reported).stopped, "not_checked|" _ $Parameter(..#PROBE, "REASONNOTREADONLY") _ "|not_read_only", "a denial of a tool that is not Read-only is a stop")
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Stops").%Size(), 1, "with one stop notice")
}

/// matrix 5, the tool changed (see the class description).
Method TestStoppedChanged()
{
	Set host = ..Host()
	Set ref = ..Source(..Owner("stopchanged"), "Jira")
	Do ..Tick(host, ..At(0))
	Do ..Answer(host, ref, "", "changed")
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result _ "|" _ row.Finding _ "|" _ ..RunOf(ref).reason, "not_checked|" _ $Parameter(..#PROBE, "REASONNOTREADONLY") _ "|stopped", "the word changed is a stop")
	Do ..Tick(host, ..At(20))
	Do ..Answer(host, ref, "", "notreadonly")
	Do $$$AssertEquals(..Stored(ref).Finding _ "|" _ $ClassMethod(..#PROBE, "Stops").%Size(), $Parameter(..#PROBE, "REASONNOTREADONLY") _ "|1", "so is notreadonly, and the second stop sends no second notice")
}

/// matrix 5, once for each transition (see the class description).
Method TestStoppedNotifiesOnce()
{
	Set host = ..Host()
	Set ref = ..Source(..Owner("once"), "Jira")
	Do $ClassMethod(..#PROBE, "FeedClass", ..#SERVER, ..#TOOL, "risky")
	Do ..Tick(host, ..At(0))
	Do ..Tick(host, ..At(20))
	Do ..Tick(host, ..At(40))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Stops").%Size(), 1, "three stopped runs send one notice")
	Do $$$AssertEquals(..Stored(ref).Result _ "|" _ ..Stored(ref).Finding, "not_checked|" _ $Parameter(..#PROBE, "REASONNOTREADONLY"), "and each is recorded as not_checked with REASONNOTREADONLY")
	Do $ClassMethod(..#PROBE, "FeedClass", ..#SERVER, ..#TOOL, "read-only")
	Do ..Run(host, ref, 60, "T-1 open")
	Do $$$AssertEquals(##class(%DynamicAbstractObject).%FromJSON(..Stored(ref).Reported).stopped, "", "a good run clears stopped")
	Do $ClassMethod(..#PROBE, "FeedClass", ..#SERVER, ..#TOOL, "risky")
	Do ..Tick(host, ..At(1300))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Stops").%Size(), 2, "a later stop notifies once more")
}

/// matrix 5, the tool is Read-only again (see the class description).
Method TestResume()
{
	Set host = ..Host()
	Set ref = ..Source(..Owner("resume"), "Jira")
	Do $ClassMethod(..#PROBE, "FeedClass", ..#SERVER, ..#TOOL, "risky")
	Do ..Tick(host, ..At(0))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Polls").%Size(), 0, "stopped: no poll")
	Do $ClassMethod(..#PROBE, "FeedClass", ..#SERVER, ..#TOOL, "read-only")
	Do ..Tick(host, ..At(14))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Polls").%Size(), 0, "not due yet: still no poll")
	Do ..Tick(host, ..At(16))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Polls").%Size(), 1, "Read-only again: the next due run polls")
	Do ..Answer(host, ref, "T-1 open")
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result _ "|" _ ##class(%DynamicAbstractObject).%FromJSON(row.Reported).stopped _ "|" _ ##class(%DynamicAbstractObject).%FromJSON(row.Reported).baseline, "passed||1", "the success clears stopped and is the baseline, since the stopped run was not")
	Do $$$AssertEquals(..FindingItems().%Size(), 0, "with no Item")
}

/// NextDueAt (see the class description).
Method TestNextDueAtAtSend()
{
	Set host = ..Host()
	Set ref = ..Source(..Owner("due"), "Jira", {"IntervalMinutes": 30})
	Do ..Tick(host, ..At(0))
	Set due = ##class(OcuTalon.Bridge.Time).PlusSeconds(..At(0), 1800)
	Do $$$AssertEquals(..Stored(ref).NextDueAt, due, "NextDueAt is the tick time plus the row's 30 minutes from the send on")
	Do ..Answer(host, ref, "T-1 open")
	Do $$$AssertEquals(..Stored(ref).NextDueAt, due, "and the record of the answer leaves it")
	Do ..Answer(host, ref, "", "timeout")
	Do $$$AssertEquals(..Stored(ref).NextDueAt, due, "also for a failed run")
	Do ..Tick(host, ..At(1))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Polls").%Size(), 1, "a Tick before the due time sends nothing more")
}

/// matrix 6 (see the class description).
Method TestRemovedMeanwhile()
{
	Set host = ..Host()
	Set session = ..Owner("removed")
	Set ref = ..Source(session, "Jira")
	Do ..Tick(host, ..At(0))
	Do ##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(ref, .id)
	Do ##class(OcuTalon.Data.BackgroundCheck).%DeleteId(id)
	Do ..Answer(host, ref, "T-1 open")
	Do ..Answer(host, ref, "T-2 open")
	Do $$$AssertEquals(##class(OcuTalon.Data.BackgroundCheck).RefIndexExists(ref), 0, "the row is not created again")
	Do $$$AssertEquals(..RunCount(ref), 0, "no CheckRun row is written")
	Do $$$AssertEquals(..FindingItems().%Size(), 0, "no Item is sent")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Events(session, "check").%Size(), 0, "and no check event is published")
	Do $$$AssertEquals(..Ran(ref), 0, "and no run is logged")
}

/// matrix 9, the repoint (see the class description).
Method TestRepointBaseline()
{
	Set host = ..Host()
	Set session = ..Owner("repoint")
	Do $$$AssertStatusOK(##class(OcuTalon.Watch.Ops).SetSource(session, ..#SERVER, ..#TOOL, "Jira", "{""q"":""a""}", 15, "zzfixture", .ref, .created), "a source row is made through Watch.Ops SetSource")
	Do ..Flip(ref, 1)
	Set ..Refs = ..Refs _ "," _ ref
	Set ..Checks = ..Checks _ $Select(..Checks = "": "", 1: ",") _ ref
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET CreatedAt = ? WHERE Ref = ?", "2020-01-01T00:00:00Z", ref)
	Do ..Run(host, ref, 0, "T-1 open")
	Do ..Run(host, ref, 1, "T-1 open" _ $Char(10) _ "T-2 open")
	Do $$$AssertEquals(..FindingItems().%Size(), 1, "before the repoint a new answer is an Item")
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET LastRunAt = ? WHERE Ref = ?", "2021-01-01T00:00:00Z", ref)
	Do ..Flip(ref, 0)
	Do $$$AssertStatusOK(##class(OcuTalon.Watch.Ops).SetSource(session, ..#SERVER, ..#TOOL, "Jira", "{""q"":""b""}", 15, "zzfixture", .again, .made), "the source is updated with new arguments")
	Do ..Flip(ref, 1)
	Do $$$AssertEquals(again _ "|" _ made, ref _ "|0", "the same row")
	Set created = ..Stored(ref).CreatedAt
	Do $$$AssertTrue(created ] "2020-01-01T00:00:00Z", "CreatedAt moved to now")
	Do ..Run(host, ref, 2, "T-9 open")
	Set row = ..Stored(ref)
	Do $$$AssertEquals(..FindingItems().%Size(), 1, "the next success sends no Item")
	Do $$$AssertEquals(row.Reported, "{""seen"":[""" _ ..Hash("T-9 open") _ """],""baseline"":1,""stopped"":""""}", "Reported starts afresh with the new answer")
	Do ..Run(host, ref, 3, "T-9 open" _ $Char(10) _ "T-10 open")
	Do $$$AssertEquals(..FindingItems().%Size(), 2, "and the run after it is a normal one")
}

/// matrix 9, an answer from before the repoint (see the class description).
Method TestAnswerBeforeRepoint()
{
	Set host = ..Host()
	Set ref = ..Source(..Owner("before"), "Jira", {"CreatedAt": (##class(OcuTalon.Data.Time).NowUtc())})
	Do ..Tick(host, ..At(0))
	Set stale = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -60)
	Do ..Answer(host, ref, "T-1 open", "", stale)
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.LastRunAt _ "|" _ row.Result _ "|" _ ..RunCount(ref), "||0", "an answer sent before CreatedAt records nothing")
	Do $$$AssertEquals(..FindingItems().%Size(), 0, "and sends no Item")
	Do $$$AssertTrue('(row.Reported [ "inflight"), "and takes the in-flight mark off")
	Do ..Answer(host, ref, "T-1 open")
	Do $$$AssertEquals(..Stored(ref).Result, "passed", "an answer sent after CreatedAt is recorded")
}

/// matrix 7 (see the class description).
Method TestOnlineDemoNoPoll()
{
	Set host = ..Host()
	Set ref = ..Source(..Owner("demo"), "Jira")
	Set host.Demo = 1
	Do ..Tick(host, ..At(0))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Polls").%Size(), 0, "the probe's flag: no poll is sent")
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.LastRunAt _ "|" _ row.Result _ "|" _ row.NextDueAt, "||", "and nothing is recorded: the row is as it was")
	Do $ClassMethod(..#PROBE, "FeedClass", ..#SERVER, ..#TOOL, "risky")
	Do ..Tick(host, ..At(1))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Stops").%Size() _ "|" _ ..RunCount(ref) _ "|" _ ..Stored(ref).LastRunAt, "0|0|", "not even a stopped run")
	Do $ClassMethod(..#PROBE, "FeedClass", ..#SERVER, ..#TOOL, "read-only")
	Set host.Demo = ""
	Set ..SavedDemo = ##class(OcuTalon.Data.Public.Settings).Get("onlineDemo")
	Set ..DemoSaved = 1
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", 1)
	Do ..Tick(host, ..At(2))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Polls").%Size() _ "|" _ ..Stored(ref).LastRunAt, "0|", "the real setting onlineDemo 1: no poll either")
	Do ##class(OcuTalon.Data.Public.Settings).Set("onlineDemo", ..SavedDemo)
	Set ..DemoSaved = 0
	Do ..Tick(host, ..At(3))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Polls").%Size(), 1, "with the setting back as it was the source is polled")
}

/// The coverage of a stopped run (see the class description).
Method TestStoppedCoverage()
{
	Set host = ..Host()
	Set session = ..Owner("coverage")
	Set ref = ..Source(session, "Jira")
	Do $ClassMethod(..#PROBE, "FeedClass", ..#SERVER, ..#TOOL, "risky")
	Do ..Tick(host, ..At(0))
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET Kind = ? WHERE Ref = ?", ##class(OcuTalon.Watch.Ops).#SOURCEKIND, ref)
	Set ranAt = ..Stored(ref).LastRunAt
	Set to = ##class(OcuTalon.Data.Time).AddSeconds(ranAt, 30)
	Set from = ##class(OcuTalon.Data.Time).AddSeconds(ranAt, -120)
	Do $$$AssertStatusOK(##class(OcuTalon.Checks.Coverage).Build(session, from, to, .rows, .lines, .vitals), "the coverage is built")
	Set found = ""
	Set iterator = lines.%GetIterator()
	While iterator.%GetNext(, .line) {
		If line.key = "digest.notCheckedStopped" Set found = line
	}
	Do $$$AssertTrue($IsObject(found), "a stopped source gives the line digest.notCheckedStopped")
	If $IsObject(found) Do $$$AssertEquals(found.slots.entry, "Jira", "for the source")
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET Kind = ? WHERE Ref = ?", $Parameter(..#PROBE, "SOURCEKIND"), ref)
}

/// The stop notice (see the class description).
Method TestSourceStoppedNotice()
{
	Kill ^||ZzOps
	Set ^||ZzOps("admins") = $ListBuild("zzadminA", "zzadminB")
	Set sc = ##class(OcuTalon.Test.Mcp.OpsProbe).SourceStopped("Jira", "zz_lookup", "zzserver", "2030-06-01T12:00:00Z")
	Do $$$AssertStatusOK(sc, "SourceStopped answers OK")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%Size(), 2, "two admins get one notice each")
	For admin = "zzadminA", "zzadminB" {
		Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount(admin, "mcp.sourceStopped"), 1, admin _ " gets mcp.sourceStopped")
	}
	Set notice = ##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%Get(0)
	Set slots = ##class(%DynamicAbstractObject).%FromJSON(notice.slots)
	Do $$$AssertEquals(notice.kind _ "|" _ slots.source _ "|" _ slots.tool _ "|" _ slots.server _ "|" _ slots.time, "status|Jira|zz_lookup|zzserver|2030-06-01T12:00:00Z", "a status notice with the source, tool, server and time")
	Do $$$AssertEquals(slots.%Size(), 4, "and no other slot")
	Set rendered = ##class(OcuTalon.Msg.Catalog).RenderAt(notice.key, slots, "web", slots.time, 0, .renderStatus)
	Do $$$AssertTrue($$$ISOK(renderStatus) && (rendered [ "Jira") && (rendered [ "zz_lookup") && (rendered [ "zzserver"), "the catalog renders the notice with the source, tool and server")
	Kill ^||ZzOps
	Set ^||ZzOps("adminsError") = 1
	Set mark = ##class(OcuTalon.Test.Core.Observe).LastLog()
	Set sc = ##class(OcuTalon.Test.Mcp.OpsProbe).SourceStopped("Jira", "zz_lookup", "zzserver", "2030-06-01T12:00:00Z")
	Do $$$AssertStatusNotOK(sc, "an unreadable list of admins is an error status")
	Do $$$AssertEquals(##class(OcuTalon.Test.Mcp.OpsProbe).Notices().%Size(), 0, "with no notice")
	Do $$$AssertEquals(##class(OcuTalon.Test.Core.Observe).Warnings(mark, .text, "Notify", "OcuTalon.Mcp.Ops"), 1, "and one warning")
	Do ##class(OcuTalon.Test.Core.Observe).RemoveWarnings(mark, "Notify", "OcuTalon.Mcp.Ops")
	Kill ^||ZzOps
}

/// The stop through the real SourceClass and StopNotice (see the class description).
Method TestStopThroughTheRealSeams()
{
	Set host = ..Host()
	Set host.RealSeams = 1
	Kill ^||ZzOps
	Set ^||ZzOps("admins") = $ListBuild("zzadminA")
	Set ref = ..Source(..Owner("real"), "Jira", {"Server": (..#REALSERVER), "Tool": "zz_realtool"})
	Set class = ##class(OcuTalon.Mcp.ToolClassification).%New()
	Set class.Server = ..#REALSERVER
	Set class.Tool = "zz_realtool"
	Set class.Classification = "risky"
	Set class.Fingerprint = "zzfp"
	Do $$$AssertStatusOK(class.%Save(), "the classification row of the tool is risky")
	Do ..Tick(host, ..At(0))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Polls").%Size(), 0, "no poll is sent for a tool that the classification row says is risky")
	Do $$$AssertEquals(..Stored(ref).Finding, $Parameter(..#PROBE, "REASONNOTREADONLY"), "the run is the stopped one")
	Set notices = ##class(OcuTalon.Test.Mcp.OpsProbe).Notices()
	Do $$$AssertEquals(notices.%Size() _ "|" _ ##class(OcuTalon.Test.Mcp.OpsProbe).NoticeCount("zzadminA", "mcp.sourceStopped"), "1|1", "the admin gets one mcp.sourceStopped")
	If notices.%Size() = 1 {
		Set slots = ##class(%DynamicAbstractObject).%FromJSON(notices.%Get(0).slots)
		Do $$$AssertEquals(slots.source _ "|" _ slots.tool _ "|" _ slots.server, "Jira|zz_realtool|" _ ..#REALSERVER, "with the source's name, the tool and the server in their slots")
		Do $$$AssertEquals(slots.time, ..Stored(ref).LastRunAt, "and the time of the run")
	}
	Set class.Classification = "read-only"
	Do $$$AssertStatusOK(class.%Save(), "the tool is read-only again")
	Do ..ForceDue(ref)
	Do ..Tick(host, ..At(1))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Polls").%Size(), 1, "the next due run polls")
}

/// Oldest NextDueAt first (see the class description).
Method TestOldestDueFirst()
{
	Set host = ..Host()
	Set session = ..Owner("oldest")
	Set a = ..Source(session, "A", {"NextDueAt": "2030-06-01T11:55:00Z"})
	Set b = ..Source(session, "B", {"NextDueAt": "2030-06-01T11:50:00Z"})
	Set c = ..Source(session, "C", {"NextDueAt": "2030-06-01T11:59:00Z"})
	Set expected = $ListBuild(b, a, c)
	For n = 0:1:2 {
		Do ..Tick(host, ..At(n))
		Set polls = $ClassMethod(..#PROBE, "Polls")
		Do $$$AssertEquals(polls.%Size(), n + 1, "the Tick of step " _ n _ " sends one poll")
		If polls.%Size() = (n + 1) Do $$$AssertEquals($Piece(polls.%Get(n).key, "|", 1), $List(expected, n + 1), "the source that has waited longest is sent first")
		Do ..Answer(host, $List(expected, n + 1), "T-" _ n)
	}
}

/// Option (a) (see the class description).
Method TestOneInFlightNoQueueStale()
{
	Set host = ..Host()
	Set session = ..Owner("inflight")
	Set one = ..Source(session, "One")
	Set two = ..Source(session, "Two")
	Set three = ..Source(session, "Three")
	Do ..Tick(host, ..At(0))
	Set polls = $ClassMethod(..#PROBE, "Polls")
	Do $$$AssertEquals(polls.%Size(), 1, "three sources due at once: one poll is sent")
	Do $$$AssertEquals($Piece(polls.%Get(0).key, "|", 1), one, "the first in the order of the rows")
	Do $$$AssertEquals(..Stored(two).NextDueAt _ "|" _ ..Stored(three).NextDueAt, "|", "the others keep their NextDueAt (empty, due)")
	Do ..Tick(host, ..At(1))
	Do $$$AssertEquals($ClassMethod(..#PROBE, "Polls").%Size(), 1, "the next Tick, while the poll waits, sends no other")
	Do ..Answer(host, one, "T-1 open")
	Do $$$AssertEquals(..Stored(one).Result _ "|" _ (..Stored(one).Reported [ "inflight"), "passed|0", "the answer is recorded and takes the mark off")
	Do ..Tick(host, ..At(2))
	Set polls = $ClassMethod(..#PROBE, "Polls")
	Do $$$AssertEquals(polls.%Size() _ "|" _ $Piece(polls.%Get(1).key, "|", 1), "2|" _ two, "after the answer the next due source is sent, one at a time")
	Do $$$AssertEquals(..Stored(two).NextDueAt, ##class(OcuTalon.Bridge.Time).PlusSeconds(..At(2), 900), "its NextDueAt is set at the send")
	// a poll that never answers: its mark goes stale
	Set old = ##class(OcuTalon.Data.Time).AddSeconds(##class(OcuTalon.Data.Time).NowUtc(), -(##class(OcuTalon.Checks.Process).#INFLIGHTSECONDS + 10))
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET Reported = ? WHERE Ref = ?", {"seen": [], "baseline": 0, "stopped": "", "inflight": (old)}.%ToJSON(), two)
	Do ..Tick(host, ..At(3))
	Set polls = $ClassMethod(..#PROBE, "Polls")
	Do $$$AssertEquals(polls.%Size() _ "|" _ $Piece(polls.%Get(2).key, "|", 1), "3|" _ three, "a mark older than INFLIGHTSECONDS holds nothing: the third source is sent")
	// every source polled within the interval plus 180 seconds of the first Tick: the third source's send is the Tick of step 3, and that Tick is at most 3 minutes after the first
	Set limit = 900 + ##class(OcuTalon.Checks.Coverage).#MISSEDSECONDS
	Set waited = ##class(OcuTalon.Data.Time).Seconds(..At(3)) - ##class(OcuTalon.Data.Time).Seconds(..At(0))
	Do $$$AssertEquals(..Stored(three).NextDueAt, ##class(OcuTalon.Bridge.Time).PlusSeconds(..At(3), 900), "the third source's send set its NextDueAt at the Tick of step 3")
	Do $$$AssertTrue(waited <= limit - 900, "the third source waited " _ waited _ " seconds for its first poll, within the " _ (limit - 900) _ " seconds that the coverage allows beyond the interval")
	// a send that fails takes the mark off, one warning for each source
	For ref = one, two, three {
		Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET Reported = '' WHERE Ref = ?", ref)
	}
	Do $ClassMethod(..#PROBE, "FailPolls", 1)
	Do ..Tick(host, ..At(30))
	Do $$$AssertEquals(..Warnings("PollSource", $Parameter(..#PROBE, "LOGPOLLSEND")), 3, "a send that fails is one warning for each source, and the next source is tried")
	Do $$$AssertEquals(($ListLength($ListFromString(..Checks)) - ((..Stored(one).Reported [ "inflight") + (..Stored(two).Reported [ "inflight") + (..Stored(three).Reported [ "inflight"))), 3, "and none is left marked in flight")
	Do $ClassMethod(..#PROBE, "FailPolls", 0)
}

/// --- helpers ---
/// A shadow instance of the probe, in this process, with a known session.
Method Host() As OcuTalon.Test.Mcp.SourceProbe
{
	Set host = ##class(Ens.Host).GetShadowInstance("class||" _ ..#PROBE, .sc)
	Do $$$AssertTrue($IsObject(host), "a shadow instance of the probe is made")
	If $IsObject(host) Set host.%SessionId = ..#SESSIONID
	Quit host
}

/// A fixture session; its Ref is the owner of the fixture check.
Method Owner(name As %String) As %String
{
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Session("zzsrun" _ ..Number _ name)
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ ref
	Quit ref
}

/// A source row of the session, of the probe's Kind, due at once, created long ago, for the server and tool of the class; fields, an object of property names and values, is set after
/// the defaults. Its Ref.
Method Source(session As %String, name As %String, fields As %DynamicObject = "") As %String
{
	Set values = {"Kind": ($Parameter(..#PROBE, "SOURCEKIND")), "DisplayName": (name), "CreatedAt": "2020-01-01T00:00:00Z", "NextDueAt": "", "Server": (..#SERVER), "Tool": (..#TOOL), "IntervalMinutes": 15, "Arguments": "{}"}
	If $IsObject(fields) {
		Set iterator = fields.%GetIterator()
		While iterator.%GetNext(.key, .value) {
			Do values.%Set(key, value)
		}
	}
	Set ref = ##class(OcuTalon.Test.Data.Fixture).Check(session, "", "", values)
	Set ..Refs = ..Refs _ $Select(..Refs = "": "", 1: ",") _ ref
	Set ..Checks = ..Checks _ $Select(..Checks = "": "", 1: ",") _ ref
	Quit ref
}

/// Moves the row between the probe's Kind (probe 1) and the real one (probe 0), so that Watch.Ops SetSource finds it.
Method Flip(ref As %String, probe As %Boolean)
{
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET Kind = ? WHERE Ref = ?", $Select(probe: $Parameter(..#PROBE, "SOURCEKIND"), 1: ##class(OcuTalon.Watch.Ops).#SOURCEKIND), ref)
}

/// A Tick of the time, handled by the probe.
Method Tick(host As OcuTalon.Test.Mcp.SourceProbe, tickAt As %String)
{
	Set tick = ##class(OcuTalon.Msg.Tick).%New()
	Set tick.TickAt = tickAt
	Do $$$AssertStatusOK(host.OnRequest(tick, .response), "the Tick at " _ tickAt _ " is answered OK")
}

/// The time of the Tick of step n: TICK plus n minutes.
ClassMethod At(n As %Integer) As %String
{
	Quit ##class(OcuTalon.Bridge.Time).PlusSeconds(..#TICK, 60 * n)
}

/// A Tick at step n, and the answer to the poll that it sent (text, or the failure word when word is not empty).
Method Run(host As OcuTalon.Test.Mcp.SourceProbe, ref As %String, n As %Integer, text As %String)
{
	Do ..ForceDue(ref)
	Do ..Tick(host, ..At(n * 20))
	Do ..Answer(host, ref, text)
}

/// Makes the row due again, as 15 minutes would.
Method ForceDue(ref As %String)
{
	Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE OcuTalon_Data.BackgroundCheck SET NextDueAt = '' WHERE Ref = ?", ref)
}

/// Feeds the answer of a poll of the row to OnResponse, as Decide gives it: the Reply with the text and the failure word. word "no reply" gives no Reply, and "error status" is
/// the error of Decide's call (OnError). sentAt is the time of the send, now unless given.
Method Answer(host As OcuTalon.Test.Mcp.SourceProbe, ref As %String, text As %String, word As %String = "", sentAt As %String = "")
{
	If sentAt = "" Set sentAt = ##class(OcuTalon.Data.Time).NowUtc()
	Set key = ref _ "|" _ sentAt
	Set request = ##class(OcuTalon.Msg.Tick).%New()
	If word = "error status" {
		Do $$$AssertStatusOK(host.OnError(request, .out, "", $SYSTEM.Status.Error(5001, "zz Decide refused"), key), "OnError takes the error of the call")
		Do $$$AssertStatusOK(host.OnResponse(request, .out, "", "", key), "and the call of OnResponse that the host makes for the same key after it")
		Quit
	}
	Set reply = $Select(word = "no reply": "", 1: ##class(OcuTalon.Bridge.Msg.Reply).%New())
	If $IsObject(reply) {
		Set reply.Text = text
		Set reply.FailureText = word
	}
	Do $$$AssertStatusOK(host.OnResponse(request, .out, "", reply, key), "OnResponse takes the answer")
}

/// A due source, its poll and a failed answer: the run is not_checked with the finding and the CheckRun Reason, and is not the baseline.
Method Failure(word As %String, finding As %String, reason As %String)
{
	Set host = ..Host()
	Set ref = ..Source(..Owner("fail" _ $Translate(word, " ", "")), "Jira")
	Do ..Tick(host, ..At(0))
	Do ..Answer(host, ref, "", word)
	Set row = ..Stored(ref)
	Do $$$AssertEquals(row.Result _ "|" _ row.Finding, "not_checked|" _ finding, "(" _ word _ ") the run is not_checked with the finding")
	Do $$$AssertEquals(..RunOf(ref).reason, reason, "(" _ word _ ") the CheckRun Reason is " _ reason)
	Set reported = ##class(%DynamicAbstractObject).%FromJSON(row.Reported)
	Do $$$AssertEquals(reported.baseline _ "|" _ reported.stopped, "0|", "(" _ word _ ") it is not the baseline and not a stop")
	Do $$$AssertEquals(row.NextDueAt, ##class(OcuTalon.Bridge.Time).PlusSeconds(..At(0), 900), "(" _ word _ ") NextDueAt stands")
	Do $$$AssertEquals(..FindingItems().%Size(), 0, "(" _ word _ ") no Item is sent")
	Do $$$AssertEquals(..RunCount(ref) _ "|" _ ..Ran(ref), "1|1", "(" _ word _ ") one CheckRun row is written and the run is announced once")
}

/// The SHA-256 of the UTF-8 text as 64 lower-case hexadecimal characters.
ClassMethod Hash(text As %String) As %String
{
	Set digest = $SYSTEM.Encryption.SHAHash(256, $ZConvert(text, "O", "UTF8"))
	Set hex = ""
	For i = 1:1:$Length(digest) {
		Set hex = hex _ $ZConvert($Extract($ZHex(256 + $Ascii(digest, i)), 2, 3), "L")
	}
	Quit hex
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

/// The number of CheckRun rows of the check.
ClassMethod RunCount(ref As %String) As %Integer
{
	Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Digest_Data.CheckRun WHERE CheckRef = ?", ref)
	Do rs.%Next()
	Quit +rs.%GetData(1)
}

/// The number of info lines (Type 4) of runs of the check since the test began.
Method Ran(ref As %String) As %Integer
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Util.Log WHERE ID > ? AND Type = 4 AND Text %STARTSWITH ?", ..LogMark, $Parameter(..#PROBE, "LOGRAN") _ ref)
	Do result.%Next()
	Quit +result.%GetData(1)
}

/// The number of warnings since the test began that the method logged and that start as given.
Method Warnings(method As %String, start As %String) As %Integer
{
	Quit ##class(OcuTalon.Test.Core.Observe).Warnings(..LogMark, .text, method, start)
}

}
